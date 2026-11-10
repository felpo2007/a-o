--!strict
-- Menus de entrada e mapa tático (F2 + Parte 12.5).
-- Painel lateral: facção → squad → papel. Abre com foco no 1º botão; A confirma, B volta.
-- Mapa (tocar View / M): setores e pontos fortes, nunca inimigos (Parte 9.5). No controle, o
-- analógico esquerdo move um cursor com ímã que gruda nos pontos de spawn e nos pontos fortes; o
-- direito dá zoom; LB/RB pulam entre spawns liberados; A escolhe; X marca; Y troca de papel;
-- B/Select fecham. A navegação automática do Roblox fica desligada no mapa (a nossa assume).
-- Modos: "spawn" (morto), "view" (aberto em jogo) e "target" (comandante escolhendo o alvo).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local gui = UiKit.screen("VT65Menus", 20)
gui.IgnoreGuiInset = true

local PAPER, INK = UiKit.PAPER, UiKit.INK

local function frame(parent: Instance, size: UDim2, pos: UDim2): Frame
	local f = Instance.new("Frame")
	f.Size, f.Position = size, pos
	f.BackgroundColor3 = PAPER
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function clear(f: Instance)
	for _, c in f:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIScale") and c.Name ~= "Keep" then
			c:Destroy()
		end
	end
end

-- painel lateral (facção / squad / papel)
local side = frame(gui, UDim2.fromOffset(if UiKit.tv() then 460 else 340, 560), UDim2.fromOffset(16, 80))
local sideList = Instance.new("UIListLayout")
sideList.Padding = UDim.new(0, 6)
sideList.SortOrder = Enum.SortOrder.LayoutOrder
sideList.Parent = side

-- mapa tático: janela fixa; a "tela" interna escala com o zoom
local mapFrame = frame(gui, UDim2.fromOffset(720, 432), UDim2.new(0, if UiKit.tv() then 500 else 380, 0, 80))
mapFrame.ClipsDescendants = true
mapFrame.Visible = false
local canvas = Instance.new("Frame")
canvas.Name = "Keep"
canvas.BackgroundColor3 = PAPER
canvas.BorderSizePixel = 0
canvas.Size = UDim2.fromScale(1, 1)
canvas.Parent = mapFrame
local status = Instance.new("TextLabel")
status.Name = "Keep"
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 0, 1, 0)
status.Size = UDim2.new(1, 0, 0, if UiKit.tv() then 34 else 26)
status.BackgroundColor3 = Color3.fromRGB(40, 36, 28)
status.BackgroundTransparency = 0.2
status.TextColor3 = Color3.new(1, 1, 1)
status.Font = Enum.Font.GothamMedium
status.TextSize = UiKit.text(15)
status.ZIndex = 5
status.Parent = mapFrame
local cursorUI = Instance.new("Frame")
cursorUI.Name = "Keep"
cursorUI.AnchorPoint = Vector2.new(0.5, 0.5)
cursorUI.Size = UDim2.fromOffset(26, 26)
cursorUI.BackgroundTransparency = 1
cursorUI.ZIndex = 6
local cs = Instance.new("UIStroke")
cs.Thickness = 3
cs.Color = Color3.fromRGB(255, 214, 0)
cs.Parent = cursorUI
local cr = Instance.new("UICorner")
cr.CornerRadius = UDim.new(1, 0)
cr.Parent = cursorUI
cursorUI.Parent = mapFrame

local B = MapConfig.Bounds
local function toUV(x: number, z: number): Vector2
	return Vector2.new((x - B.minX) / (B.maxX - B.minX), (z - B.minZ) / (B.maxZ - B.minZ))
end
local function fromUV(u: number, v: number): (number, number)
	return B.minX + u * (B.maxX - B.minX), B.minZ + v * (B.maxZ - B.minZ)
end

local squadState: any = nil
local spawnList: { any } = {}
local matchState: any = nil
local mode: string = "spawn" -- "spawn" | "view" | "target"
local pinned = false
local targetAbility: string? = nil
local cursor = Vector2.new(0.5, 0.5)
local zoom = 1
local focused: InputMap.MagnetPoint? = nil
local focusIdx: number? = nil

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- pontos com ímã: spawns (no modo spawn) e pontos fortes
local function magnetPoints(): { InputMap.MagnetPoint }
	local pts = {}
	if mode == "spawn" then
		for _, pt in spawnList do
			local uv = toUV(pt.x, pt.z)
			table.insert(pts, { id = "spawn:" .. pt.id, x = uv.X, y = uv.Y })
		end
	end
	if matchState then
		for _, sp in matchState.points do
			local uv = toUV(sp.x, sp.z)
			table.insert(pts, { id = "sp:" .. sp.name, x = uv.X, y = uv.Y })
		end
	end
	return pts
end

local function readySpawns(): { any }
	local out = {}
	for _, pt in spawnList do
		if not pt.blocked then
			table.insert(out, pt)
		end
	end
	return out
end

local function spawnById(id: string): any
	for _, pt in spawnList do
		if "spawn:" .. pt.id == id then
			return pt
		end
	end
	return nil
end

local function drawMap()
	clear(canvas)
	if not matchState then
		return
	end
	for _, s in MapConfig.Sectors do
		local xs = {}
		for i = 1, #s.polygon, 2 do
			table.insert(xs, s.polygon[i])
		end
		local x0, x1 = math.min(table.unpack(xs)), math.max(table.unpack(xs))
		local band = Instance.new("Frame")
		band.Position = UDim2.fromScale(toUV(x0, B.minZ).X, 0)
		band.Size = UDim2.fromScale((x1 - x0) / (B.maxX - B.minX), 1)
		local owner = matchState.owner[s.id]
		band.BackgroundColor3 = if owner == "US"
			then Color3.fromRGB(110, 120, 150)
			elseif owner == "VC" then Color3.fromRGB(150, 110, 100)
			else Color3.fromRGB(170, 165, 140)
		band.BackgroundTransparency = if matchState.active[s.id] then 0.5 else 0.85
		band.BorderSizePixel = 1
		band.Parent = canvas
	end
	for _, sp in matchState.points do
		local d = Instance.new("TextLabel")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		local uv = toUV(sp.x, sp.z)
		d.Position = UDim2.fromScale(uv.X, uv.Y)
		d.Size = UDim2.fromOffset(140, 20)
		d.BackgroundTransparency = 1
		d.TextColor3 = INK
		d.Font = Enum.Font.Code
		d.TextSize = UiKit.text(13)
		d.Text = "◎ " .. sp.name
		d.Parent = canvas
	end
	if mode == "spawn" then
		for _, pt in spawnList do
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			local uv = toUV(pt.x, pt.z)
			b.Position = UDim2.fromScale(uv.X, uv.Y)
			b.Size = UDim2.fromOffset(136, if UiKit.tv() then 44 else 34)
			b.BackgroundColor3 = if pt.blocked then Color3.fromRGB(120, 60, 50) else Color3.fromRGB(60, 80, 50)
			b.TextColor3 = Color3.new(1, 1, 1)
			b.TextSize = UiKit.text(12)
			b.Font = Enum.Font.GothamMedium
			b.Selectable = false -- no controle, o cursor com ímã escolhe
			b.Text = pt.name
				.. "\n"
				.. (
					if pt.blocked
						then (pt.why or "bloqueado")
						elseif pt.wait > 0 then string.format("%d s", pt.wait)
						else "PRONTO"
				)
			local s = Instance.new("UIStroke")
			s.Thickness = if focused and focused.id == "spawn:" .. pt.id then 3 else 0
			s.Color = Color3.fromRGB(255, 214, 0)
			s.Parent = b
			b.Parent = canvas
			b.Activated:Connect(function()
				Net.event("Spawn_Request"):FireServer(pt.id)
			end)
		end
	end
	if mode == "target" and not Input.isGamepad() then
		-- mouse: clicar em qualquer ponto escolhe o alvo
		local pick = Instance.new("TextButton")
		pick.Size = UDim2.fromScale(1, 1)
		pick.BackgroundTransparency = 1
		pick.Text = ""
		pick.Selectable = false
		pick.Parent = canvas
		pick.Activated:Connect(function()
			local m = game:GetService("UserInputService"):GetMouseLocation()
			local rel = (m - canvas.AbsolutePosition - Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y))
				/ canvas.AbsoluteSize
			local x, z = fromUV(math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1))
			Bus.fire("target_chosen", targetAbility, x, z)
			Bus.fire("map_target_end")
		end)
	end
	local t = matchState.timeLeft or 0
	status.Text = string.format("%s — %02d:%02d", matchState.mode, t // 60, t % 60)
end

local function drawSide()
	clear(side)
	local faction = player:GetAttribute("Faction")
	if not faction then
		UiKit.label(side, "Escolha o lado")
		UiKit.button(side, "Fuzileiros dos EUA (USMC)", function()
			Net.event("Team_Choose"):FireServer("US")
		end, 1)
		UiKit.button(side, "1º Regimento (Viet Cong)", function()
			Net.event("Team_Choose"):FireServer("VC")
		end, 2)
	elseif not player:GetAttribute("SquadId") then
		UiKit.label(side, "Squads")
		if squadState then
			local n = 0
			for _, s in squadState.squads do
				n += 1
				local size = Roles.units[faction][s.unit].size
				UiKit.button(side, string.format("Entrar: %s (%d/%d)", s.name, #s.members, size), function()
					Net.event("Squad_Action"):FireServer({ op = "join", id = s.id })
				end, n)
			end
			for unit, def in Roles.units[faction] do
				local ok = not def.heavy or (squadState.size or 0) >= Roles.HEAVY_UNLOCK
				if ok then
					n += 1
					UiKit.button(side, "Criar: " .. unit, function()
						Net.event("Squad_Action"):FireServer({ op = "create", unit = unit })
					end, n)
				end
			end
		end
	elseif not player:GetAttribute("Role") then
		UiKit.label(side, "Papel")
		local mySquad: any = nil
		if squadState then
			for _, s in squadState.squads do
				if s.id == player:GetAttribute("SquadId") then
					mySquad = s
				end
			end
		end
		local n = 0
		if mySquad then
			for id, r in Roles.roles do
				if r.unit == mySquad.unit and Roles.loadout[faction][id] then
					n += 1
					UiKit.button(side, r.name .. " — " .. table.concat(Roles.loadout[faction][id], ", "), function()
						Net.event("Role_Choose"):FireServer(id)
					end, n)
				end
			end
		end
		UiKit.button(side, "Sair do squad", function()
			Net.event("Squad_Action"):FireServer({ op = "leave" })
		end, 99)
	elseif not alive() then
		UiKit.label(side, "Escolha onde renascer no mapa")
		local _, padText = Input.glyph("map_role", "map")
		UiKit.label(side, string.format("Trocar de papel: %s (+15 s)", padText), 14)
	end
end

-- o painel lateral é um "menu" (personagem parado, A confirma) enquanto não houver papel
local sideAsMenu = false
local mapOpenState = false

local function syncInput()
	local wantMenu = side.Visible and not mapFrame.Visible
	if wantMenu ~= sideAsMenu then
		sideAsMenu = wantMenu
		if wantMenu then
			Input.openMenu()
		else
			Input.closeMenu()
		end
	end
	local wantMap = mapFrame.Visible and alive()
	if wantMap ~= mapOpenState then
		mapOpenState = wantMap
		Input.event(if wantMap then "map_open" else "map_close")
	end
	-- no mapa a navegação é nossa (cursor com ímã); fora dele, a do Roblox
	local inMap = mapFrame.Visible
	GuiService.GuiNavigationEnabled = not inMap
	cursorUI.Visible = inMap and Input.isGamepad()
	if wantMenu then
		UiKit.focus(side)
	elseif inMap then
		GuiService.SelectedObject = nil
	end
end

local function refresh()
	local dead = not alive()
	local hasRole = player:GetAttribute("Role") ~= nil
	side.Visible = dead or not hasRole
	mapFrame.Visible = (dead and hasRole) or pinned or mode == "target"
	local targeting = mode == "target"
	if not targeting then
		if dead and hasRole then
			mode = "spawn"
		elseif not dead then
			mode = "view"
		end
	end
	drawSide()
	if mapFrame.Visible then
		drawMap()
	end
	syncInput()
end

UiKit.watch(side, function()
	return side.Visible and not mapFrame.Visible
end)

-- ===== entradas do mapa =====
local function moveCursorTo(pt: any)
	local uv = toUV(pt.x, pt.z)
	cursor = uv
end

Input.on("map", "tap", function()
	pinned = not pinned
	refresh()
end)
Input.on("map", "press", function() -- M no teclado
	pinned = not pinned
	refresh()
end)
Input.on("map_close", "press", function()
	if mode == "target" then
		Bus.fire("map_target_end")
	end
	pinned = false
	refresh()
end)
Input.on("map_back", "press", function()
	if mode == "target" then
		Bus.fire("map_target_end")
	end
	pinned = false
	refresh()
end)
Input.on("map_next", "press", function()
	local list = readySpawns()
	focusIdx = InputMap.cycle(#list, focusIdx, 1)
	if focusIdx then
		moveCursorTo(list[focusIdx])
	end
end)
Input.on("map_prev", "press", function()
	local list = readySpawns()
	focusIdx = InputMap.cycle(#list, focusIdx, -1)
	if focusIdx then
		moveCursorTo(list[focusIdx])
	end
end)
Input.on("map_select", "press", function()
	if mode == "target" then
		local x, z = fromUV(cursor.X, cursor.Y)
		if focused and string.sub(focused.id, 1, 3) == "sp:" then
			x, z = fromUV(focused.x, focused.y)
		end
		Bus.fire("target_chosen", targetAbility, x, z)
		Bus.fire("map_target_end")
	elseif mode == "spawn" and focused then
		local pt = spawnById(focused.id)
		if pt then
			Net.event("Spawn_Request"):FireServer(pt.id)
		end
	end
end)
Input.on("map_mark", "press", function()
	local x, z = fromUV(cursor.X, cursor.Y)
	Net.event("Squad_Mark"):FireServer({ pos = Vector3.new(x, 0, z), kind = "map" })
end)
Input.on("map_role", "press", function()
	if mode == "spawn" and not alive() then
		player:SetAttribute("Role", nil) -- só o menu; o servidor confirma ao escolher
		refresh()
	end
end)

-- modo alvo (comandante / morteiro): pedido vindo do CommanderController
Bus.on("map_target", function(ability: string, label: string?)
	targetAbility = ability
	mode = "target"
	status.Text = "ALVO: " .. (label or ability) .. " — mova o cursor e confirme"
	refresh()
end)
Bus.on("map_target_end", function()
	if mode == "target" then
		mode = if alive() then "view" else "spawn"
		targetAbility = nil
		refresh()
	end
end)

-- cursor, ímã e zoom (controle)
RunService.RenderStepped:Connect(function(dt: number)
	if not mapFrame.Visible then
		return
	end
	if Input.isGamepad() and not (Input.state.disconnected or Input.state.robloxMenu) then
		local mv = Input.move()
		cursor = Vector2.new(
			math.clamp(cursor.X + mv.X * dt * 0.45 / zoom, 0, 1),
			math.clamp(cursor.Y - mv.Y * dt * 0.45 / zoom, 0, 1)
		)
		local r = Input.stickRaw("right")
		local _, zy = InputMap.radialDeadzone(0, r.Y, 0.2, 0.95)
		zoom = math.clamp(zoom + zy * dt * 2, 1, 4)
	end
	local f = InputMap.magnet(cursor.X, cursor.Y, magnetPoints(), 0.035 / zoom)
	if (f and f.id) ~= (focused and focused.id) then
		focused = f
		if mode == "spawn" then
			drawMap()
		end
	end
	local shown = if focused then Vector2.new(focused.x, focused.y) else cursor
	-- tela interna: escala e desloca para manter o cursor visível
	canvas.Size = UDim2.fromScale(zoom, zoom)
	local px = math.clamp(0.5 - cursor.X * zoom, 1 - zoom, 0)
	local py = math.clamp(0.5 - cursor.Y * zoom, 1 - zoom, 0)
	canvas.Position = UDim2.fromScale(px, py)
	cursorUI.Position = UDim2.fromScale(px + shown.X * zoom, py + shown.Y * zoom)
	if focused and mode == "spawn" then
		local pt = spawnById(focused.id)
		if pt then
			status.Text = string.format(
				"%s — %s",
				pt.name,
				if pt.blocked
					then (pt.why or "bloqueado")
					elseif pt.wait > 0 then string.format("espera %d s", pt.wait)
					else "PRONTO"
			)
		end
	end
end)

-- ===== estado do jogo =====
Net.event("Squad_State").OnClientEvent:Connect(function(st)
	squadState = st
	refresh()
end)
Net.event("Spawn_State").OnClientEvent:Connect(function(st)
	spawnList = st
	if mapFrame.Visible then
		drawMap()
	end
end)
Net.event("Match_State").OnClientEvent:Connect(function(st)
	matchState = st
	if mapFrame.Visible then
		drawMap()
	end
end)
for _, a in { "Faction", "SquadId", "Role" } do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
player.CharacterAdded:Connect(function(char)
	pinned = false
	refresh()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(refresh)
end)
Input.DeviceChanged:Connect(refresh)

-- aviso enquanto o servidor gera o terreno
local loading = Instance.new("TextLabel")
loading.AnchorPoint = Vector2.new(0.5, 0)
loading.Position = UDim2.fromScale(0.5, 0.02)
loading.Size = UDim2.fromOffset(620, 44)
loading.BackgroundColor3 = PAPER
loading.TextColor3 = INK
loading.Font = Enum.Font.GothamMedium
loading.TextSize = UiKit.text(18)
loading.Text = "Preparando o campo de batalha (terreno de 4 x 2,4 km)…"
loading.Parent = gui
local function loadingState()
	loading.Visible = ReplicatedStorage:GetAttribute("TerrainReady") == false
end
ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Connect(loadingState)
loadingState()
refresh()
