--!strict
-- Aliados, squad e objetivos na tela (pedido do dono, 2026-11-11: "você deve conseguir ver quem são
-- seus aliados e deve ver a todo momento o seu batalhão, onde ele está, e ver na sua tela onde
-- estão os objetivos"). Marcadores presos no mundo (BillboardGui, o motor desenha a cada quadro):
--   - ALIADO à vista: chevron azul discreto sobre a cabeça, o nome curto quando está perto (40 m);
--     a parede tapa (AlwaysOnTop desligado) e some a 150 m;
--   - SQUAD: sempre na tela, mesmo atrás de parede e longe (fora do alcance do streaming, pela
--     posição que o FrontService manda a cada 2 s), em latão, com o nome e a distância; o líder com
--     ★; caído em vermelho com ✚;
--   - OBJETIVO do time: ATACAR ou DEFENDER, o setor e a distância, sempre na tela; os outros
--     setores ativos num selo pequeno na cor do dono (o mesmo da faixa da frente).
-- Nunca inimigo (Parte 9.5): só modelos com o atributo "Faction" igual ao seu.
-- Custo: atualiza a 12 Hz, só texto, cor e Adornee; os marcadores são reaproveitados (no máximo 24
-- aliados, os mais perto, e todo o squad). Distância e altura pelo MapConfig.STUD_M e pelo chão
-- medido uma vez por ponto (nada de número fixo do mapa: ele vai mudar de tamanho).
-- Marcadores.squad() devolve o squad para a bússola do HudCampo.
-- Studio: workspace:SetAttribute("VT65DevTela", "aliados") marca os aliados e os objetivos mesmo
-- sem squad (para a foto).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local Marcadores = {}

local player = Players.LocalPlayer
local M = MapConfig.STUD_M or 0.28
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local C = {
	ally = Color3.fromRGB(150, 182, 236), -- o azul "nosso" da faixa da frente, claro
	squad = UiKit.BRASS_LIGHT,
	leader = Color3.fromRGB(255, 226, 140),
	down = Color3.fromRGB(240, 124, 104),
	attack = Color3.fromRGB(240, 124, 104),
	defend = Color3.fromRGB(150, 182, 236),
	neutral = UiKit.KHAKI,
	ink = Color3.fromRGB(14, 14, 10),
}
local MAX_ALLIES = 24
local ALLY_RANGE_M = 150
local NAME_RANGE_M = 40

-- ===== peças =====
local pg = player:WaitForChild("PlayerGui")

local function label(parent: Instance, size: number, color: Color3, font: any): TextLabel
	local t = UiKit.rotulo(parent, size, color, font)
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextStrokeColor3 = C.ink
	t.TextStrokeTransparency = 0.35
	return t
end

type Mark = {
	bb: BillboardGui,
	icon: TextLabel,
	name: TextLabel,
	key: string,
	used: boolean,
}

-- marcador de gente (aliado ou squad): ícone e nome embaixo
local function newPersonMark(): Mark
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65Marca"
	bb.ResetOnSpawn = false
	bb.Size = UDim2.fromOffset(px(140, 200), px(36, 52))
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.LightInfluence = 0
	bb.Enabled = false
	local icon = label(bb, 14, C.ally, Enum.Font.ArimoBold)
	icon.Size = UDim2.new(1, 0, 0, px(16, 24))
	icon.Text = "▼"
	local name = label(bb, 12, C.ally, UiKit.HEAD_FONT)
	name.Position = UDim2.fromOffset(0, px(15, 22))
	name.Size = UDim2.new(1, 0, 0, px(18, 26))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	bb.Parent = pg
	return { bb = bb, icon = icon, name = name, key = "", used = false }
end

type Goal = { bb: BillboardGui, verb: TextLabel, info: TextLabel, card: Frame, edge: UIStroke, att: Attachment }
local function newGoalMark(): Goal
	local att = Instance.new("Attachment")
	att.Name = "Objetivo"
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65Objetivo"
	bb.ResetOnSpawn = false
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(px(176, 250), px(64, 90))
	bb.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	bb.Adornee = att
	bb.Enabled = false
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0)
	card.Size = UDim2.new(1, 0, 0, px(44, 62))
	card.BackgroundColor3 = UiKit.CARD_DARK
	card.BackgroundTransparency = 0.25
	card.BorderSizePixel = 0
	card.Parent = bb
	UiKit.corner(card, 3)
	local edge = UiKit.edge(card, C.attack, 1.5, 0.2)
	local verb = label(card, 15, C.attack, UiKit.HEAD_FONT)
	verb.Size = UDim2.new(1, 0, 0, px(20, 28))
	verb.Position = UDim2.fromOffset(0, 2)
	local info = label(card, 13, UiKit.CARD, UiKit.BODY_FONT)
	info.Position = UDim2.fromOffset(4, px(21, 30))
	info.Size = UDim2.new(1, -8, 0, px(18, 26))
	info.TextTruncate = Enum.TextTruncate.AtEnd
	local pin = label(bb, 14, C.attack, Enum.Font.ArimoBold)
	pin.Name = "Ponta"
	pin.Position = UDim2.fromOffset(0, px(44, 62))
	pin.Size = UDim2.new(1, 0, 0, px(18, 26))
	pin.Text = "▼"
	bb.Parent = pg
	return { bb = bb, verb = verb, info = info, card = card, edge = edge, att = att }
end

-- selo pequeno dos outros setores ativos
type Seal = { bb: BillboardGui, t: TextLabel, att: Attachment }
local function newSeal(): Seal
	local att = Instance.new("Attachment")
	att.Name = "Setor"
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65Setor"
	bb.ResetOnSpawn = false
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(px(110, 160), px(22, 32))
	bb.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	bb.Adornee = att
	bb.Enabled = false
	local t = label(bb, 13, C.neutral, UiKit.HEAD_FONT)
	t.Size = UDim2.fromScale(1, 1)
	bb.Parent = pg
	return { bb = bb, t = t, att = att }
end

local persons: { Mark } = {}
local goal = newGoalMark()
local seals: { Seal } = {}

-- ===== chão (uma vez por ponto) =====
local groundCache: { [string]: number } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundY(x: number, z: number): number
	local key = string.format("%d:%d", math.floor(x / 8), math.floor(z / 8))
	local y = groundCache[key]
	if y then
		return y
	end
	local skip: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local cb = workspace:FindFirstChild("Combatants")
	if cb then
		table.insert(skip, cb)
	end
	rayParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), rayParams)
	local gy = if hit then hit.Position.Y else 0
	groundCache[key] = gy
	return gy
end

-- ===== estado =====
local squadState: any = nil
local farSquad: { any } = {}
local matchState: any = nil
local dev = 0

Net.event("Squad_State").OnClientEvent:Connect(function(st: any)
	squadState = st
end)
Net.event("Match_State").OnClientEvent:Connect(function(st: any)
	if type(st) == "table" and type(st.owner) == "table" then
		matchState = st
	end
end)
task.spawn(function()
	Net.event("Squad_Positions").OnClientEvent:Connect(function(list: any)
		farSquad = if type(list) == "table" then list else {}
	end)
end)

local function myFaction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

local function leaderId(): number?
	local sid = player:GetAttribute("SquadId")
	if type(sid) ~= "string" or type(squadState) ~= "table" or type(squadState.squads) ~= "table" then
		return nil
	end
	for _, s in squadState.squads do
		if s.id == sid then
			return tonumber(s.leader)
		end
	end
	return nil
end

local function inField(): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and player:GetAttribute("Role") ~= nil and Input.state.alive
end

local function short(s: string): string
	if (utf8.len(s) or #s) <= 12 then
		return s
	end
	local cut = utf8.offset(s, 12)
	return (if cut then string.sub(s, 1, cut - 1) else s) .. "…"
end

-- ===== quem marcar =====
export type Squadmate = { pos: Vector3, leader: boolean, downed: boolean, name: string }
local squadNow: { Squadmate } = {}
function Marcadores.squad(): { Squadmate }
	return squadNow
end

type Who = {
	key: string,
	adornee: Instance?, -- cabeça do modelo (quando ele existe neste cliente)
	pos: Vector3,
	name: string,
	squad: boolean,
	leader: boolean,
	downed: boolean,
	dist: number, -- m
}

local function collect(myPos: Vector3, faction: string): { Who }
	local out: { Who } = {}
	local sid = player:GetAttribute("SquadId")
	local lead = leaderId()
	local seen: { [number]: boolean } = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if p ~= player and c and p:GetAttribute("Faction") == faction then
			local head = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
			local h = c:FindFirstChildOfClass("Humanoid")
			if head and head:IsA("BasePart") and h and h.Health > 0 then
				local same = type(sid) == "string" and p:GetAttribute("SquadId") == sid
				seen[p.UserId] = true
				table.insert(out, {
					key = "p" .. p.UserId,
					adornee = head,
					pos = head.Position,
					name = p.DisplayName,
					squad = same,
					leader = same and lead == p.UserId,
					downed = c:GetAttribute("Downed") == true,
					dist = (head.Position - myPos).Magnitude * M,
				})
			end
		end
	end
	-- squad longe (fora do streaming): a posição do FrontService
	if type(sid) == "string" then
		for _, e in farSquad do
			local id = tonumber(e.id)
			if id and id ~= player.UserId and not seen[id] and type(e.x) == "number" then
				local pos = Vector3.new(e.x, groundY(e.x, e.z) + 5, e.z)
				table.insert(out, {
					key = "p" .. id,
					adornee = nil,
					pos = pos,
					name = tostring(e.name or "?"),
					squad = true,
					leader = lead == id,
					downed = e.downed == true,
					dist = (pos - myPos).Magnitude * M,
				})
			end
		end
	end
	-- bots do mesmo lado
	local cb = workspace:FindFirstChild("Combatants")
	if cb then
		for _, m in cb:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Faction") == faction then
				local head = m:FindFirstChild("Head") or m:FindFirstChild("HumanoidRootPart")
				local h = m:FindFirstChildOfClass("Humanoid")
				if head and head:IsA("BasePart") and h and h.Health > 0 then
					local d = (head.Position - myPos).Magnitude * M
					if d <= ALLY_RANGE_M then
						local role = m:GetAttribute("Role")
						local def = if type(role) == "string" then Roles.roles[role] else nil
						table.insert(out, {
							key = "b" .. m:GetFullName(),
							adornee = head,
							pos = head.Position,
							name = if def then tostring(def.name) else "",
							squad = false,
							leader = false,
							downed = m:GetAttribute("Downed") == true,
							dist = d,
						})
					end
				end
			end
		end
	end
	return out
end

-- ponto do mundo para quem não tem modelo (squad longe): uma Attachment no Terrain por marcador
local loose: { [Mark]: Attachment } = {}
local function looseAnchor(mk: Mark, pos: Vector3): Attachment
	local a = loose[mk]
	if not a then
		local na = Instance.new("Attachment")
		na.Name = "SquadLonge"
		na.Parent = workspace.Terrain
		loose[mk] = na
		a = na
	end
	a.WorldPosition = pos
	return a
end

local function paintPerson(mk: Mark, w: Who)
	local bb = mk.bb
	if w.adornee then
		bb.Adornee = w.adornee
	else
		bb.Adornee = looseAnchor(mk, w.pos)
	end
	bb.AlwaysOnTop = w.squad -- o squad aparece atrás de parede; os outros aliados, só à vista
	bb.MaxDistance = if w.squad then math.huge else ALLY_RANGE_M / M
	local color = if w.downed then C.down elseif w.leader then C.leader elseif w.squad then C.squad else C.ally
	mk.icon.TextColor3 = color
	mk.name.TextColor3 = color
	mk.icon.Text = if w.downed then "✚" elseif w.leader then "★" elseif w.squad then "◆" else "▼"
	mk.icon.TextSize = UiKit.text(if w.squad then 16 else 13)
	local showName = w.squad or w.dist <= NAME_RANGE_M
	mk.name.Visible = showName and w.name ~= ""
	if showName then
		local n = short(w.name)
		mk.name.Text = if w.downed
			then string.format("%s · caído", n)
			elseif w.squad and w.dist > NAME_RANGE_M then string.format(
				"%s · %d m",
				n,
				math.floor(w.dist / 5 + 0.5) * 5
			)
			else n
		mk.name.FontFace = UiKit.headFont(n)
	end
	-- longe some devagar (os aliados fora do squad)
	local fade = if w.squad then 0 else math.clamp((w.dist - 90) / 60, 0, 0.7)
	mk.icon.TextTransparency = fade
	mk.name.TextTransparency = fade
	mk.icon.TextStrokeTransparency = 0.35 + fade * 0.5
	mk.name.TextStrokeTransparency = 0.35 + fade * 0.5
	if not bb.Enabled then
		bb.Enabled = true
		-- entra crescendo um pouco (sem tween de tamanho a cada quadro)
		mk.icon.TextTransparency = 1
		TweenService:Create(mk.icon, TweenInfo.new(0.25), { TextTransparency = fade }):Play()
	end
end

local function hideAll()
	for _, mk in persons do
		mk.bb.Enabled = false
		mk.used = false
	end
	goal.bb.Enabled = false
	for _, s in seals do
		s.bb.Enabled = false
	end
	table.clear(squadNow)
end

-- ===== objetivos =====
local function sectorPos(st: any, s: number): Vector3?
	local p = st.points and st.points[s]
	if not p then
		return nil
	end
	return Vector3.new(p.x, groundY(p.x, p.z), p.z)
end

local function paintGoals(myPos: Vector3, faction: string)
	local st = matchState
	if not st or st.ended then
		goal.bb.Enabled = false
		for _, s in seals do
			s.bb.Enabled = false
		end
		return
	end
	local cap = {}
	if type(st.capturing) == "table" then
		for i, v in st.capturing do
			cap[i] = if v == "" then nil else v
		end
	end
	local role, target = Front.objective(st.owner, st.active, faction, cap)
	local tpos = if target then sectorPos(st, target) else nil
	if role and target and tpos then
		if goal.att.Parent ~= workspace.Terrain then
			goal.att.Parent = workspace.Terrain
		end
		goal.att.WorldPosition = tpos
		local color = if role == "attack" then C.attack else C.defend
		goal.verb.Text = if role == "attack" then "ATACAR" else "DEFENDER"
		goal.verb.TextColor3 = color
		goal.edge.Color = color
		local pin = goal.bb:FindFirstChild("Ponta") :: TextLabel?
		if pin then
			pin.TextColor3 = color
		end
		local p = st.points[target]
		local d = (Vector3.new(tpos.X, myPos.Y, tpos.Z) - myPos).Magnitude * M
		local name = string.format("S%d %s", target, tostring(p.name or ""))
		goal.info.Text = if d < 50
			then string.format("%s · você está nele", name)
			else string.format("%s · %d m", name, math.floor(d / 10 + 0.5) * 10)
		goal.info.Font = if string.find(name, "[\196-\225]") then Enum.Font.Arimo else UiKit.BODY_FONT
		goal.bb.Enabled = true
	else
		goal.bb.Enabled = false
	end
	-- os outros setores ativos: selo pequeno na cor do dono
	local k = 0
	for s = 1, #st.owner do
		if st.active[s] and s ~= target then
			local pos = sectorPos(st, s)
			if pos then
				k += 1
				local seal = seals[k]
				if not seal then
					seal = newSeal()
					seals[k] = seal
				end
				if seal.att.Parent ~= workspace.Terrain then
					seal.att.Parent = workspace.Terrain
				end
				seal.att.WorldPosition = pos
				local owner = st.owner[s]
				seal.t.TextColor3 = if owner == faction
					then C.defend
					elseif owner == "US" or owner == "VC" then C.attack
					else C.neutral
				local d = (Vector3.new(pos.X, myPos.Y, pos.Z) - myPos).Magnitude * M
				seal.t.Text = string.format("S%d · %d m", s, math.floor(d / 10 + 0.5) * 10)
				seal.bb.Enabled = true
			end
		end
	end
	for i = k + 1, #seals do
		seals[i].bb.Enabled = false
	end
end

-- ===== laço (12 Hz) =====
local byKey: { [string]: Mark } = {}
task.spawn(function()
	while true do
		task.wait(1 / 12)
		local faction = myFaction()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (faction and root and (inField() or os.clock() < dev)) then
			hideAll()
			table.clear(byKey)
			continue
		end
		local myPos = root.Position
		local list = collect(myPos, faction)
		-- o squad sempre; os outros aliados, os mais perto até o limite
		table.sort(list, function(a: Who, b: Who): boolean
			if a.squad ~= b.squad then
				return a.squad
			end
			return a.dist < b.dist
		end)
		local chosen: { Who } = {}
		local allies = 0
		for _, w in list do
			if w.squad then
				table.insert(chosen, w)
			elseif allies < MAX_ALLIES then
				allies += 1
				table.insert(chosen, w)
			end
		end
		for _, mk in persons do
			mk.used = false
		end
		-- o mesmo marcador para a mesma pessoa (nada pisca quando a ordem muda)
		local nextByKey: { [string]: Mark } = {}
		for _, w in chosen do
			local mk = byKey[w.key]
			if mk then
				mk.used = true
				nextByKey[w.key] = mk
			end
		end
		local freeIdx = 1
		for _, w in chosen do
			if not nextByKey[w.key] then
				while freeIdx <= #persons and persons[freeIdx].used do
					freeIdx += 1
				end
				local mk: Mark
				if freeIdx <= #persons then
					mk = persons[freeIdx]
				else
					mk = newPersonMark()
					table.insert(persons, mk)
				end
				mk.used = true
				mk.key = w.key
				nextByKey[w.key] = mk
			end
		end
		table.clear(squadNow)
		for _, w in chosen do
			paintPerson(nextByKey[w.key], w)
			if w.squad then
				table.insert(squadNow, { pos = w.pos, leader = w.leader, downed = w.downed, name = w.name })
			end
		end
		for _, mk in persons do
			if not mk.used then
				mk.bb.Enabled = false
				mk.key = ""
			end
		end
		byKey = nextByKey
		paintGoals(myPos, faction)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "aliados" then
			dev = os.clock() + 20
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end

return Marcadores
