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
--   - MARCA GUIADA (2026-11-11, pedido do dono: "marcar na carta e ser guiado"): a sua marca
--     pessoal (◆, posta na carta pelo GameUI, só neste cliente) e a marca do líder para o squad (★,
--     cor própria, chega pelo Squad_Mark com leader = true, com aviso no Toast); no mundo com a
--     distância, somem ao chegar (ARRIVE_M);
--   - MARCAS DO SQUAD no mundo (ponto e área aproximada de inimigo, Squad_Mark): as iguais se
--     juntam (a mesma área marcada duas vezes saía repetida, uma em cima da outra) e as próximas
--     sobem um degrau cada (não se empilham).
-- Cores FIXAS por lado (pedido do dono): EUA sempre azul (UiKit.V.US), VC sempre vermelho
-- (UiKit.V.VC); "nosso/inimigo" só por ícone ou texto (ATACAR/DEFENDER, ≈ inimigo).
-- Nunca inimigo (Parte 9.5): só modelos com o atributo "Faction" igual ao seu; a área de inimigo é
-- a marcação aproximada do próprio squad (D-48).
-- Custo: atualiza a 12 Hz, só texto, cor e Adornee; os marcadores são reaproveitados (no máximo 24
-- aliados, os mais perto, e todo o squad). Distância e altura pelo MapConfig.STUD_M e pelo chão de
-- verdade (raio de cima para baixo no terreno e nas peças, guardado por ponto; sem chão carregado,
-- a altura do jogador como piso e nova tentativa depois: o objetivo ficava embaixo do chão).
-- Marcadores.squad() devolve o squad para a bússola do HudCampo; Marcadores.waypoints() as marcas
-- guiadas para a carta (CartaView).
-- Studio: workspace:SetAttribute("VT65DevTela", "aliados") marca os aliados e os objetivos mesmo
-- sem squad (para a foto); "voz" acende o ícone de quem fala nos aliados por 5 s; "eventos" mostra os
-- eventos de exemplo no mundo (anel e marcador) mesmo fora de campo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Comms = require(ReplicatedStorage.Shared.Comms)
local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local EventosVisual = require(script.Parent.EventosVisual)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)
local VozEstado = require(script.Parent.VozEstado)

local Marcadores = {}

local player = Players.LocalPlayer
local M = MapConfig.STUD_M or 0.28
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local C = {
	us = UiKit.V.US, -- EUA: sempre azul
	vc = UiKit.V.VC, -- VC: sempre vermelho
	squad = UiKit.BRASS_LIGHT,
	leader = Color3.fromRGB(255, 226, 140),
	down = Color3.fromRGB(240, 124, 104),
	neutral = UiKit.KHAKI,
	ink = Color3.fromRGB(14, 14, 10),
	mine = Color3.fromRGB(120, 214, 176), -- sua marca (a mesma cor da carta)
	lead = Color3.fromRGB(236, 120, 200), -- marca do líder (a mesma cor da carta)
	point = UiKit.KHAKI, -- ponto marcado pelo squad
}
local function sideColor(f: string?): Color3
	return if f == "US" then C.us elseif f == "VC" then C.vc else C.neutral
end
local ARRIVE_M = 8 -- a marca guiada some quando você chega a esta distância (m, no chão)
local LEAD_TTL_S = 300 -- a marca do líder vale 5 min
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
	voice: TextLabel, -- quem fala (VozEstado): 🔊 de perto, 📻 pelo rádio
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
	local icon = label(bb, 14, C.neutral, Enum.Font.ArimoBold)
	icon.Size = UDim2.new(1, 0, 0, px(16, 24))
	icon.Text = "▼"
	local name = label(bb, 12, C.neutral, UiKit.HEAD_FONT)
	name.Position = UDim2.fromOffset(0, px(15, 22))
	name.Size = UDim2.new(1, 0, 0, px(18, 26))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local voice = label(bb, 14, UiKit.V.TEXT, Enum.Font.GothamBold)
	voice.AnchorPoint = Vector2.new(0, 0)
	voice.Position = UDim2.new(0.5, px(10, 14), 0, -1)
	voice.Size = UDim2.fromOffset(px(20, 28), px(18, 26))
	voice.Text = "🔊"
	voice.Visible = false
	bb.Parent = pg
	return { bb = bb, icon = icon, name = name, voice = voice, key = "", used = false }
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
	local edge = UiKit.edge(card, C.neutral, 1.5, 0.2)
	local verb = label(card, 15, C.neutral, UiKit.HEAD_FONT)
	verb.Size = UDim2.new(1, 0, 0, px(20, 28))
	verb.Position = UDim2.fromOffset(0, 2)
	local info = label(card, 13, UiKit.CARD, UiKit.BODY_FONT)
	info.Position = UDim2.fromOffset(4, px(21, 30))
	info.Size = UDim2.new(1, -8, 0, px(18, 26))
	info.TextTruncate = Enum.TextTruncate.AtEnd
	local pin = label(bb, 14, C.neutral, Enum.Font.ArimoBold)
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
-- Raio de cima para baixo no terreno e nas peças, guardado por quadrado de 8 studs. Sem chão neste
-- cliente (a área ainda não chegou pelo streaming), NADA é guardado: antes guardava 0 e o marcador
-- do objetivo ficava embaixo do chão para sempre. Aí vale um piso (a altura do seu pé, o mapa é
-- quase plano perto) e o raio tenta de novo em 2 s.
local groundCache: { [string]: number } = {}
local missUntil: { [string]: number } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function floorY(): number
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position.Y - 3 else 0
end
local function groundY(x: number, z: number): number
	local key = string.format("%d:%d", math.floor(x / 8), math.floor(z / 8))
	local y = groundCache[key]
	if y then
		return y
	end
	if (missUntil[key] or 0) > os.clock() then
		return floorY()
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
	if not hit then
		missUntil[key] = os.clock() + 2
		return floorY()
	end
	local gy = hit.Position.Y
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
-- userId: o UserId do jogador (nil para bot), para o HUD acender quem fala (VozEstado)
export type Squadmate = { pos: Vector3, leader: boolean, downed: boolean, name: string, userId: number? }
local squadNow: { Squadmate } = {}
function Marcadores.squad(): { Squadmate }
	return squadNow
end

type Who = {
	key: string,
	userId: number?, -- jogador (nil: bot)
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
					userId = p.UserId,
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
					userId = id,
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
							userId = nil,
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

-- quem fala (só aliados: o VozEstado nunca traz inimigo). Muda pelo evento VozEstado.Changed; o
-- laço de 12 Hz só repete o que já está guardado. VT65DevTela "voz" acende todos por 5 s.
local voiceDev = 0
local function paintVoice(mk: Mark, userId: number?)
	local talking, radio = false, false
	if userId then
		talking, radio = VozEstado.get(userId)
	end
	if os.clock() < voiceDev then
		talking = true
	end
	mk.voice.Visible = talking or radio
	mk.voice.Text = if radio then "📻" else "🔊"
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
	-- aliado fora do squad: a cor do lado (fixa); squad em latão; caído com ✚
	local color = if w.downed
		then C.down
		elseif w.leader then C.leader
		elseif w.squad then C.squad
		else sideColor(myFaction())
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
	paintVoice(mk, w.userId)
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
		-- a cor do dono do setor (fixa por lado; neutro em cáqui); atacar/defender vai no texto
		local color = sideColor(st.owner[target])
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
				seal.t.TextColor3 = sideColor(owner)
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

-- ===== marcas guiadas: a sua e a do líder =====
export type Waypoint = { x: number, z: number, from: string?, t: number }
local wps: { mine: Waypoint?, lead: Waypoint? } = { mine = nil, lead = nil }
type WpMark = { bb: BillboardGui, icon: TextLabel, dist: TextLabel, att: Attachment }
local function newWpMark(icon: string, color: Color3): WpMark
	local att = Instance.new("Attachment")
	att.Name = "MarcaGuiada"
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65MarcaGuiada"
	bb.ResetOnSpawn = false
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(px(110, 160), px(44, 64))
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bb.Adornee = att
	bb.Enabled = false
	local ic = label(bb, 20, color, Enum.Font.GothamBold)
	ic.Size = UDim2.new(1, 0, 0, px(22, 32))
	ic.Text = icon
	local d = label(bb, 14, UiKit.V.TEXT, UiKit.HEAD_FONT)
	d.Position = UDim2.fromOffset(0, px(22, 32))
	d.Size = UDim2.new(1, 0, 0, px(18, 26))
	d.TextTruncate = Enum.TextTruncate.AtEnd
	bb.Parent = pg
	return { bb = bb, icon = ic, dist = d, att = att }
end
local wpMarks: { mine: WpMark, lead: WpMark } = {
	mine = newWpMark("◆", C.mine),
	lead = newWpMark("★", C.lead),
}

-- a carta (CartaView) desenha as mesmas marcas
function Marcadores.waypoints(): { mine: Waypoint?, lead: Waypoint? }
	return wps
end

-- sua marca pessoal (só neste cliente; trocar a marca substitui a anterior)
function Marcadores.setWaypoint(x: number, z: number)
	wps.mine = { x = x, z = z, from = nil, t = os.clock() }
end
function Marcadores.clearWaypoint()
	wps.mine = nil
end

local function paintWaypoints(myPos: Vector3?)
	for _, k in { "mine", "lead" } do
		local w = (wps :: any)[k] :: Waypoint?
		local mk = (wpMarks :: any)[k] :: WpMark
		if w and k == "lead" and os.clock() - w.t > LEAD_TTL_S then
			wps.lead = nil
			w = nil
		end
		if w and myPos then
			local d = Vector3.new(w.x - myPos.X, 0, w.z - myPos.Z).Magnitude * M
			if d <= ARRIVE_M then
				-- chegou: a marca some (a do líder some só para quem chegou)
				if k == "mine" then
					wps.mine = nil
				else
					wps.lead = nil
				end
				mk.bb.Enabled = false
			else
				if mk.att.Parent ~= workspace.Terrain then
					mk.att.Parent = workspace.Terrain
				end
				mk.att.WorldPosition = Vector3.new(w.x, groundY(w.x, w.z), w.z)
				local dm = if d < 100 then math.floor(d + 0.5) else math.floor(d / 10 + 0.5) * 10
				mk.dist.Text = if k == "lead" and w.from
					then string.format("%s · %d m", short(w.from), dm)
					else string.format("%d m", dm)
				mk.bb.Enabled = true
			end
		else
			mk.bb.Enabled = false
		end
	end
end

-- ===== marcas do squad no mundo (Squad_Mark): juntar as iguais, afastar as próximas =====
type WorldMark = {
	kind: string,
	x: number,
	y: number,
	z: number,
	r: number?,
	froms: { string },
	born: number,
	att: Attachment,
	bb: BillboardGui,
	t: TextLabel,
	disc: Part?,
	mult: number, -- Olho de Águia de quem marcou (vantagem "mark"): a área dura mult × o tempo
}
local wmarks: { WorldMark } = {}
local MERGE_M = 25 -- área de inimigo a menos disso de outra: uma só

-- Olho de Águia (vantagem "mark", Shared/Vantagens): a área de inimigo marcada por quem tem o passe
-- fica mult × o tempo para o squad todo. O atributo Vant_mark está no Player (replica para todos):
-- acha o autor pelo nome que veio na marca; 1 sem o passe ou sem achar.
local function markMult(from: string): number
	for _, p in Players:GetPlayers() do
		if p.DisplayName == from or p.Name == from then
			return Vantagens.mult(p, "mark")
		end
	end
	return 1
end
local SPREAD_M = 30 -- marcas a menos disso: o rótulo sobe um degrau por vizinha

local function enemyColor(): Color3
	return if myFaction() == "VC" then C.us else C.vc
end

local function paintWorldMark(w: WorldMark)
	local names = table.concat(w.froms, ", ")
	if w.kind == "target" and w.r then
		w.t.Text = string.format("≈ inimigo (±%d m) — %s", math.floor(w.r + 0.5), names)
		w.t.TextColor3 = enemyColor()
	else
		w.t.Text = string.format("▼ %s", names)
		w.t.TextColor3 = C.point
	end
	w.att.WorldPosition = Vector3.new(w.x, w.y, w.z)
	local disc = w.disc
	if disc and w.r then
		disc.Size = Vector3.new(0.3, 2 * w.r / M, 2 * w.r / M)
		disc.CFrame = CFrame.new(w.x, w.y, w.z) * CFrame.Angles(0, 0, math.pi / 2)
		disc.Color = enemyColor()
	end
end

-- as próximas sobem um degrau por vizinha (a mais velha fica embaixo)
local function spreadWorldMarks()
	for i, w in wmarks do
		local k = 0
		for j = 1, i - 1 do
			local o = wmarks[j]
			if Vector3.new(o.x - w.x, 0, o.z - w.z).Magnitude * M < SPREAD_M then
				k += 1
			end
		end
		w.bb.StudsOffsetWorldSpace = Vector3.new(0, 4 + k * 2.6, 0)
	end
end

local function removeWorldMark(i: number)
	local w = table.remove(wmarks, i)
	if w then
		w.bb:Destroy()
		w.att:Destroy()
		if w.disc then
			w.disc:Destroy()
		end
	end
end

local function onSquadMark(m: any)
	if type(m) ~= "table" or type(m.x) ~= "number" or type(m.z) ~= "number" then
		return
	end
	local from = tostring(m.from or "?")
	-- marca do líder para o squad: vira a marca guiada (cor própria) e avisa
	if m.leader then
		wps.lead = { x = m.x, z = m.z, from = from, t = os.clock() }
		if from ~= player.DisplayName then
			Toast.show(
				string.format("%s marcou um ponto para o squad", from),
				"info",
				{ title = "Líder do squad", key = "marca_lider" }
			)
		end
		return
	end
	local kind = if m.kind == "target" then "target" else "point"
	local y = if type(m.y) == "number" and m.y ~= 0 then m.y else groundY(m.x, m.z)
	for _, w in wmarks do
		local near = Vector3.new(w.x - m.x, 0, w.z - m.z).Magnitude * M < MERGE_M
		local same = if kind == "target" then w.kind == "target" and near else w.kind == "point" and w.froms[1] == from
		if same then
			w.x, w.y, w.z, w.born = m.x, y, m.z, os.clock()
			w.mult = math.max(w.mult, markMult(from))
			if type(m.r) == "number" then
				w.r = m.r
			end
			if not table.find(w.froms, from) then
				table.insert(w.froms, from)
			end
			paintWorldMark(w)
			spreadWorldMarks()
			return
		end
	end
	local att = Instance.new("Attachment")
	att.Name = "MarcaSquad"
	att.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65MarcaSquad"
	bb.ResetOnSpawn = false
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(px(220, 320), px(24, 34))
	bb.Adornee = att
	local t = label(bb, 15, C.point, UiKit.HEAD_FONT)
	t.Size = UDim2.fromScale(1, 1)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	bb.Parent = pg
	local disc: Part? = nil
	if kind == "target" and type(m.r) == "number" then
		-- área aproximada no chão, que esmaece até sumir (Comms.markAlpha)
		local d = Instance.new("Part")
		d.Name = "AreaMarcada"
		d.Shape = Enum.PartType.Cylinder
		d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		d.Material = Enum.Material.Neon
		d.Transparency = 0.65
		d.Parent = workspace.Terrain
		disc = d
	end
	local w: WorldMark = {
		kind = kind,
		x = m.x,
		y = y,
		z = m.z,
		r = if type(m.r) == "number" then m.r else nil,
		froms = { from },
		born = os.clock(),
		att = att,
		bb = bb,
		t = t,
		disc = disc,
		mult = markMult(from),
	}
	table.insert(wmarks, w)
	while #wmarks > 24 do
		removeWorldMark(1)
	end
	paintWorldMark(w)
	spreadWorldMarks()
end
Net.event("Squad_Mark").OnClientEvent:Connect(onSquadMark)

-- as marcas esmaecem e somem (ponto em 10 s; área de inimigo no tempo do Comms), 4 vezes por segundo
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		local changed = false
		for i = #wmarks, 1, -1 do
			local w = wmarks[i]
			local age = now - w.born
			-- a área de inimigo dura mult × o tempo com o Olho de Águia de quem marcou
			local a = if w.kind == "target"
				then Comms.markAlpha(age / math.max(w.mult, 1))
				else math.clamp((10 - age) / 2, 0, 1)
			if a <= 0 then
				removeWorldMark(i)
				changed = true
			else
				w.t.TextTransparency = 1 - a
				w.t.TextStrokeTransparency = 0.35 + 0.65 * (1 - a)
				local disc = w.disc
				if disc then
					disc.Transparency = 1 - 0.35 * a
				end
			end
		end
		if changed then
			spreadWorldMarks()
		end
	end
end)

-- ===== eventos da partida no mundo (EventosVisual: barragem, ataque aéreo, LZ, morteiro...) =====
-- Um anel translúcido no chão do tamanho do raio, na cor da fase, e um marcador sempre visível no
-- centro com o ícone, o nome e a distância. Criado quando o evento aparece, apagado quando some; a
-- distância e a visibilidade (só em campo) mudam 4 vezes por segundo.
type EvMark = {
	att: Attachment,
	bb: BillboardGui,
	icon: TextLabel,
	name: TextLabel,
	dist: TextLabel,
	disc: Part,
	tr: number, -- transparência do anel em campo
	x: number,
	z: number,
}
local evMarks: { [string]: EvMark } = {}
local evField = true

local function newEvMark(): EvMark
	local att = Instance.new("Attachment")
	att.Name = "Evento"
	att.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Name = "VT65Evento"
	bb.ResetOnSpawn = false
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(px(160, 230), px(58, 84))
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bb.Adornee = att
	local icon = label(bb, 20, C.neutral, Enum.Font.GothamBold)
	icon.Size = UDim2.new(1, 0, 0, px(24, 34))
	local name = label(bb, 13, UiKit.V.TEXT, UiKit.HEAD_FONT)
	name.Position = UDim2.fromOffset(0, px(22, 32))
	name.Size = UDim2.new(1, 0, 0, px(17, 25))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local dist = label(bb, 12, UiKit.V.DIM, UiKit.HEAD_FONT)
	dist.Position = UDim2.fromOffset(0, px(39, 56))
	dist.Size = UDim2.new(1, 0, 0, px(16, 24))
	bb.Parent = pg
	local disc = Instance.new("Part")
	disc.Name = "AreaDoEvento"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch = true, false, false, false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Transparency = 1
	disc.Parent = workspace.Terrain
	return { att = att, bb = bb, icon = icon, name = name, dist = dist, disc = disc, tr = 0.82, x = 0, z = 0 }
end

local function syncEvents()
	local seen: { [string]: boolean } = {}
	for _, ev in EventosVisual.list() do
		seen[ev.key] = true
		local mk = evMarks[ev.key]
		if not mk then
			mk = newEvMark()
			evMarks[ev.key] = mk
		end
		local y = groundY(ev.x, ev.z)
		mk.att.WorldPosition = Vector3.new(ev.x, y, ev.z)
		local r = EventosVisual.radiusStuds(ev)
		mk.disc.Size = Vector3.new(0.25, 2 * r, 2 * r)
		mk.disc.CFrame = CFrame.new(ev.x, y + 0.2, ev.z) * CFrame.Angles(0, 0, math.pi / 2)
		local c = EventosVisual.color(ev.fase)
		mk.disc.Color = c
		mk.tr = if ev.fase == "fim" then 0.95 else 0.82
		mk.disc.Transparency = if evField then mk.tr else 1
		mk.icon.Text = EventosVisual.icon(ev.id)
		mk.icon.TextColor3 = c
		mk.name.Text = UiKit.upper(ev.name)
		mk.name.FontFace = UiKit.headFont(ev.name)
		mk.x, mk.z = ev.x, ev.z
	end
	for key, mk in evMarks do
		if not seen[key] then
			mk.bb:Destroy()
			mk.att:Destroy()
			mk.disc:Destroy()
			evMarks[key] = nil
		end
	end
end
EventosVisual.Changed:Connect(syncEvents)
task.defer(syncEvents)

task.spawn(function()
	while true do
		task.wait(0.25)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local field = root ~= nil and (inField() or os.clock() < dev)
		evField = field
		for _, mk in evMarks do
			mk.bb.Enabled = field
			mk.disc.Transparency = if field then mk.tr else 1
			if field and root then
				local d = Vector3.new(mk.x - root.Position.X, 0, mk.z - root.Position.Z).Magnitude * M
				local dm = if d < 100 then math.floor(d + 0.5) else math.floor(d / 10 + 0.5) * 10
				mk.dist.Text = string.format("%d m", dm)
			end
		end
	end
end)

-- ===== laço (12 Hz) =====
local byKey: { [string]: Mark } = {}
-- alguém começou ou parou de falar: só o marcador dele muda, na hora (nada por quadro)
VozEstado.Changed:Connect(function(uid: number)
	if uid and uid ~= 0 then
		local mk = byKey["p" .. uid]
		if mk and mk.bb.Enabled then
			paintVoice(mk, uid)
		end
	end
end)
task.spawn(function()
	while true do
		task.wait(1 / 12)
		local faction = myFaction()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (faction and root and (inField() or os.clock() < dev)) then
			hideAll()
			table.clear(byKey)
			paintWaypoints(nil) -- some da tela, mas a marca continua para quando voltar a campo
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
				table.insert(
					squadNow,
					{ pos = w.pos, leader = w.leader, downed = w.downed, name = w.name, userId = w.userId }
				)
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
		paintWaypoints(myPos)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if v == "aliados" then
			dev = os.clock() + 20
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		elseif v == "eventos" then
			-- os eventos de exemplo (EventosHud põe no EventosVisual) aparecem no mundo mesmo fora de
			-- campo por 20 s; o EventosHud limpa o atributo
			dev = math.max(dev, os.clock() + 20)
		elseif v == "voz" then
			-- o ícone de fala acende em todos os aliados marcados por 5 s (o laço de 12 Hz apaga depois)
			voiceDev = os.clock() + 5
			dev = math.max(dev, os.clock() + 5)
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end

return Marcadores
