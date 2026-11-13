--!strict
-- Faixa das vagas (2026-11-13, pedido do dono: "os itens como armas e resto não estão aparecendo").
-- Aparece por 2,5 s quando a arma ou o item da mão muda (ou ao apertar uma vaga) e some: HUD mínimo.
-- Mostra as 10 vagas fixas (Shared/Equipar): as duas armas pelo nome, granada e fumaça com o que
-- sobra, os itens; a da mão acesa em latão, o que não dá agora apagado no lugar (como a roda). No
-- teclado, o número de cada tecla. No toque, um toque curto numa vaga a escolhe (Bus "vaga_usar",
-- WeaponController); arrastar por cima não escolhe (é o olhar).
-- Fontes (só atributos locais do WeaponController e os do servidor): Vagas, Vaga, ItemNaMao, Frags,
-- Smokes, Role. Studio: workspace:SetAttribute("VT65DevTela", "vagas") mostra a faixa.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Equipar = require(ReplicatedStorage.Shared.Equipar)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local SHOW_S = 2.5

local gui = UiKit.screen("VT65BarraItens", 16)
gui.Enabled = false
local row = Instance.new("Frame")
row.Name = "Vagas"
row.AnchorPoint = Vector2.new(0.5, 1)
row.BackgroundTransparency = 1
row.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = row
local fade = Instance.new("UIScale")
fade.Parent = row

type Card = { b: TextButton, name: TextLabel, key: TextLabel, e: UIStroke, t0: number?, p0: Vector3? }
local cards: { Card } = {}
for n = 1, #Equipar.SLOTS do
	local b = Instance.new("TextButton")
	b.Name = "Vaga" .. n
	b.LayoutOrder = n
	b.Text = ""
	b.AutoButtonColor = false
	b.Selectable = false
	b.BackgroundColor3 = UiKit.CARD_DARK
	b.BackgroundTransparency = 0.25
	b.Parent = row
	UiKit.corner(b, 4)
	local e = UiKit.edge(b, UiKit.KHAKI, 1, 0.7)
	local name = UiKit.rotulo(b, 12, UiKit.KHAKI, UiKit.HEAD_FONT)
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 1, -3)
	name.Size = UDim2.new(1, -6, 0.62, 0)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextWrapped = true
	name.TextScaled = true
	local key = UiKit.rotulo(b, 11, UiKit.BRASS_LIGHT, UiKit.HEAD_FONT)
	key.Position = UDim2.fromOffset(4, 2)
	key.Size = UDim2.new(1, -8, 0.36, 0)
	key.Text = if n == 10 then "0" else tostring(n)
	local c: Card = { b = b, name = name, key = key, e = e }
	cards[n] = c
	-- toque: um toque curto escolhe; arrastar (olhar) não
	b.InputBegan:Connect(function(i: InputObject)
		if i.UserInputType == Enum.UserInputType.Touch then
			c.t0, c.p0 = os.clock(), i.Position
		end
	end)
	b.InputEnded:Connect(function(i: InputObject)
		if i.UserInputType ~= Enum.UserInputType.Touch or not (c.t0 and c.p0) then
			return
		end
		local quick = os.clock() - c.t0 < 0.35 and (i.Position - c.p0).Magnitude < 12
		c.t0, c.p0 = nil, nil
		if quick and gui.Enabled then
			Bus.fire("vaga_usar", n)
		end
	end)
end

local function num(name: string): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else 0
end

local function role(): string?
	local r = player:GetAttribute("Role")
	return if type(r) == "string" then r else nil
end

local function weaponName(id: string?): string
	if id == "launcher" then
		return "Lançador"
	end
	local wp = if id then Weapons.get(id) else nil
	return if wp then wp.name else ""
end

local function render()
	local vagas = string.split(tostring(player:GetAttribute("Vagas") or ""), ",")
	local cur = num("Vaga")
	local hand = player:GetAttribute("ItemNaMao")
	local counts = { frags = num("Frags"), smokes = num("Smokes") }
	local canBuild = false
	for _, b in Logistics.BUILDS do
		if b.role[role() or ""] then
			canBuild = true
		end
	end
	local touch = Input.touchActive()
	local vp = workspace.CurrentCamera.ViewportSize
	local w = math.floor(math.clamp((vp.X - 40) / #cards - 4, 46, if TV then 96 else 68))
	-- no toque fica na zona "vagas" do HUD (Shared/Toque.ZONES: no alto, sem botão por baixo; antes
	-- ficava a 17% da altura e cobria os botões de cima, pegando o toque deles)
	local zone = if touch then ToqueUi.zoneIn(gui, "vagas") else nil
	if zone then
		w = math.floor(math.clamp(zone.w / #cards - 4, 30, 68))
	end
	local h = math.floor(w * 0.7)
	row.Size = UDim2.fromOffset((w + 4) * #cards, h)
	if zone then
		row.AnchorPoint = Vector2.new(0.5, 0)
		row.Position = UDim2.fromOffset(zone.x + zone.w / 2, zone.y)
	else
		-- no toque sem zona (HUD de toque ainda não montado) fica no alto; embaixo estão os polegares
		row.AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)
		row.Position = if touch then UDim2.fromScale(0.5, 0.17) else UDim2.new(0.5, 0, 1, if TV then -190 else -130)
	end
	for n, c in cards do
		local def = Equipar.SLOTS[n]
		local label, on, lit
		if def.kind == "weapon" then
			local id = vagas[n]
			label = weaponName(if id ~= "" then id else nil)
			on = label ~= ""
			lit = on and hand == nil and cur == n
			if not on then
				label = def.label
			end
		else
			on = Equipar.itemOk(def.id, role(), counts, canBuild)
			lit = hand == def.id
			label = def.label
			if def.id == "frag" then
				label = string.format("%s ×%d", def.label, counts.frags)
			elseif def.id == "smoke" then
				label = string.format("%s ×%d", def.label, counts.smokes)
			end
		end
		c.b.Size = UDim2.fromOffset(w, h)
		c.name.Text = label
		c.name.FontFace = UiKit.headFont(label)
		c.key.Visible = not touch and not Input.isGamepad()
		c.b.Active = touch
		c.b.BackgroundColor3 = if lit then UiKit.OLIVE else UiKit.CARD_DARK
		c.b.BackgroundTransparency = if lit then 0.05 elseif on then 0.25 else 0.6
		c.name.TextColor3 = if lit then UiKit.CARD else UiKit.KHAKI
		c.name.TextTransparency = if on then 0 else 0.55
		c.e.Color = if lit then UiKit.BRASS else UiKit.KHAKI
		c.e.Thickness = if lit then 2 else 1
		c.e.Transparency = if lit then 0 else 0.7
	end
end

local token = 0
local function show()
	local st = Input.state
	if not st.alive or st.downed or st.vehicle or st.menus > 0 or st.map then
		return
	end
	token += 1
	local my = token
	render()
	if not gui.Enabled then
		gui.Enabled = true
		fade.Scale = 0.94
		TweenService:Create(fade, UiKit.QUICK, { Scale = 1 }):Play()
	end
	task.delay(SHOW_S, function()
		if token == my then
			gui.Enabled = false
		end
	end)
end

Bus.on("vagas_mostrar", show)
for _, name in { "Vaga", "Vagas", "ItemNaMao", "Frags", "Smokes" } do
	player:GetAttributeChangedSignal(name):Connect(function()
		if gui.Enabled or name == "Vaga" or name == "ItemNaMao" then
			show()
		end
	end)
end
-- menu, mapa, morte, veículo: some na hora
Input.StateChanged:Connect(function()
	local st = Input.state
	if gui.Enabled and (not st.alive or st.downed or st.vehicle or st.menus > 0 or st.map) then
		token += 1
		gui.Enabled = false
	end
end)
Input.DeviceChanged:Connect(function()
	if gui.Enabled then
		render()
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "vagas" then
			show()
		end
	end)
end
