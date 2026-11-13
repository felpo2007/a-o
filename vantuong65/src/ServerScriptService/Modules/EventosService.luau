--!strict
-- Eventos da partida no servidor (pedido do dono, 2026-11-12, depois de jogar a v36: "faça o jogo mais
-- interativo, com eventos e outras coisas; o jogo tem que ser divertido"). Regras, números e fontes em
-- Shared/Eventos (testados no Lune).
--   Ritmo: o primeiro evento no minuto 1 (a inserção de helicóptero, que puxa os dois lados para o
--   mesmo lugar), depois um a cada 2 a 3 min, nunca o mesmo duas vezes seguidas, alternando o lado
--   favorecido. O contra-ataque é reação: entra quando um lado perde um setor (Warfare/Skirmish).
--   Barragens (naval, A-4, morteiro do VC): aviso de 8 a 10 s antes do primeiro impacto, fumaça de
--   marcação, pontos de nascimento da área bloqueados (SpawnService.addBlocker), dano pelo
--   ExplosionService.detonate (Explosive) e uma janela de 60 s: quem favorece e entra no ponto ganha;
--   quem é alvo e segura o ponto até o fim ganha também.
--   Cada evento: aviso pelo Toast (remote Evento_Aviso, o Eventos.client só chama a API), marcador por
--   atributo em ReplicatedStorage.VT65Eventos (sempre replicado, fora do streaming) e recompensa pelo
--   ProgressionService.award (Progression.REWARDS ganha as chaves "evento_*" no início).
-- Studio: workspace:SetAttribute("VT65DevEvento", id) dispara agora ("naval", "air", "heli", "mortar",
-- "medevac", "depot", "counter" ou "proximo"); o valor volta a nil sozinho.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Eventos = require(ReplicatedStorage.Shared.Eventos)
local Explosive = require(ReplicatedStorage.Shared.Explosive)
local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local Front = require(ReplicatedStorage.Shared.Front)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Medical = require(ReplicatedStorage.Shared.Medical)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Rng = require(ReplicatedStorage.Shared.Rng)
local SpawnRules = require(ReplicatedStorage.Shared.SpawnRules)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles) :: any
local AssetLoader = require(script.Parent.AssetLoader)
local Combatants = require(script.Parent.Combatants)
local ExplosionService = require(script.Parent.ExplosionService)
local LogisticsService = require(script.Parent.LogisticsService)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)
local ProgressionService = require(script.Parent.ProgressionService)
local SpawnService = require(script.Parent.SpawnService)

local EventosService = {}
local M = MapConfig.STUD_M
local C = Eventos.C
local rng = Rng.new(os.time())
local function roll(): number
	return rng:next()
end

-- ===== estado =====
type Ev = {
	uid: number,
	id: string,
	def: Eventos.Def,
	side: string, -- favorecido
	target: string, -- o outro lado
	x: number,
	z: number,
	sector: number?,
	t0: number,
	endsAt: number,
	phase: string,
	marker: Configuration,
	props: { Instance },
	paid: { [Player]: boolean }, -- recompensa principal já dada
	paid2: { [Player]: boolean }, -- a segunda
	data: { [string]: any },
	update: (ev: Ev, now: number) -> boolean, -- true = acabou
}
local active: { Ev } = {}
local nextUid = 0
local lastId: string? = nil
local lastSide: string? = nil
local counts: { [string]: number } = { US = 0, VC = 0 }
local nextAt = math.huge
local matchKey = -1
local prevOwner: { string } = {}
local markers: Folder? = nil
local world: Folder? = nil

-- ===== utilidades =====
local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function ground(x: number, z: number): Vector3
	return Vector3.new(x, SpawnService.groundY(x, z) + 0.3, z)
end

local function grid(x: number, z: number): string
	return FireSupport.localToGrid(x, z, MapConfig.GridOrigin1965, M, 6)
end

local function sectorLabel(s: number?): string
	local sp = if s then MatchService.points[s] else nil
	return if s and sp then string.format("S%d %s", s, sp.name) elseif s then "S" .. s else "a área marcada"
end

local function notify(faction: string, ev: Ev, text: string, kind: string, duration: number?)
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Faction") == faction then
			Net.event("Evento_Aviso"):FireClient(p, {
				evento = ev.id,
				texto = text,
				tipo = kind,
				titulo = ev.def.name,
				chave = "evento:" .. ev.uid,
				duracao = duration,
			})
		end
	end
end

local function distM(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) * M
end

-- combatentes de pé de um lado, com a posição
local function standing(faction: string): { { e: Combatants.Entry, pos: Vector3 } }
	local out = {}
	for _, e in Combatants.list() do
		local r = Combatants.root(e)
		if e.faction == faction and r and Combatants.active(e) then
			table.insert(out, { e = e, pos = r.Position })
		end
	end
	return out
end

local function award(ev: Ev, p: Player?, second: boolean)
	if not p then
		return
	end
	local paid = if second then ev.paid2 else ev.paid
	if paid[p] then
		return
	end
	paid[p] = true
	pcall(ProgressionService.award, p, "evento_" .. ev.id .. (if second then "_outro" else ""))
end

-- jogadores de um lado de pé a até rM de (x, z)
local function playersNear(faction: string, x: number, z: number, rM: number): { Player }
	local out = {}
	for _, s in standing(faction) do
		if s.e.player and distM(s.pos.X, s.pos.Z, x, z) <= rM then
			table.insert(out, s.e.player)
		end
	end
	return out
end

local function setPhase(ev: Ev, phase: string)
	ev.phase = phase
	ev.marker:SetAttribute("Fase", phase)
end

local function finish(ev: Ev)
	setPhase(ev, "fim")
	for _, inst in ev.props do
		inst:Destroy()
	end
	table.clear(ev.props)
	local m = ev.marker
	task.delay(5, function()
		m:Destroy()
	end)
end

-- Novo evento com marcador. raioM: área do evento no mapa.
local function newEv(id: string, side: string, x: number, z: number, sector: number?, raioM: number, durS: number): Ev
	nextUid += 1
	local def = Eventos.DEFS[id]
	local now = os.clock()
	local marker = Instance.new("Configuration")
	marker.Name = string.format("%s_%d", id, nextUid)
	for k, v in
		{
			Evento = id,
			Nome = def.name,
			Lado = side,
			Alvo = Eventos.other(side),
			X = x,
			Z = z,
			RaioM = raioM,
			Setor = sector or 0,
			Fase = "aviso",
			Inicio = serverNow(),
			Fim = serverNow() + durS,
			Grade = grid(x, z),
		} :: { [string]: any }
	do
		marker:SetAttribute(k, v)
	end
	marker.Parent = markers
	local ev: Ev = {
		uid = nextUid,
		id = id,
		def = def,
		side = side,
		target = Eventos.other(side),
		x = x,
		z = z,
		sector = sector,
		t0 = now,
		endsAt = now + durS,
		phase = "aviso",
		marker = marker,
		props = {},
		paid = {},
		paid2 = {},
		data = {},
		update = function(_: Ev, _n: number): boolean
			return true
		end,
	}
	table.insert(active, ev)
	return ev
end

local function anchoredPart(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Size, p.CFrame, p.Color, p.Material = size, cf, color, mat
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Parent = parent
	return p
end

-- fumaça de marcação (Smoke do Roblox: partícula simples)
local function smoke(ev: Ev, x: number, z: number, color: Color3)
	local g = ground(x, z)
	local p = anchoredPart(Vector3.new(0.4, 0.4, 0.4), CFrame.new(g), color, Enum.Material.Metal, world :: Folder)
	p.Transparency = 1
	local s = Instance.new("Smoke")
	s.Color = color
	s.Opacity = 0.35
	s.RiseVelocity = 6
	s.Size = 9
	s.Parent = p
	table.insert(ev.props, p)
end

-- ===== alvos =====
local function stateOk(): boolean
	return MatchService.state ~= nil
		and not MatchService.ended
		and ReplicatedStorage:GetAttribute("TerrainReady") ~= false
end

-- setor que `side` ataca (ou o primeiro setor inimigo vizinho de um setor dele) e o ponto forte
local function attackTarget(side: string): (number?, any)
	local st = MatchService.state :: any
	if not st then
		return nil, nil
	end
	local kind, s = Front.objective(st.owner, st.active, side)
	if kind == "attack" and s and MatchService.points[s] then
		return s, MatchService.points[s]
	end
	for _, pair in Front.forwardPairs(st.owner, st.active, side) do
		if MatchService.points[pair.target] then
			return pair.target, MatchService.points[pair.target]
		end
	end
	return nil, nil
end

-- vetor unitário do QG de `side` para o QG do outro (para onde a barragem recua e a LZ chega)
local function axis(side: string): (number, number)
	local a, b = MapConfig.HQ[side], MapConfig.HQ[Eventos.other(side)]
	local dx, dz = b.x - a.x, b.z - a.z
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-6)
	return dx / len, dz / len
end

local function barrageTarget(def: Eventos.Def, side: string): (number?, number?, number?)
	local s, sp = attackTarget(side)
	if not (s and sp) then
		return nil, nil, nil
	end
	local t = Explosive.TYPES[def.explosive or ""]
	if not t then
		return nil, nil, nil
	end
	local friends = {}
	for _, f in standing(side) do
		table.insert(friends, { x = f.pos.X, z = f.pos.Z })
	end
	local ax, az = axis(side)
	local danger = 2 * (def.cepM or 0) + (if def.line then 60 else 0) + t.lethalM
	local x, z = Eventos.safeCenter(sp.x, sp.z, ax, az, friends, danger, { MapConfig.HQ.US, MapConfig.HQ.VC }, M)
	return x, z, s
end

-- ===== barragens =====
local function startBarrage(id: string, side: string): Ev?
	local def = Eventos.DEFS[id]
	local x, z, s = barrageTarget(def, side)
	local t = Explosive.TYPES[def.explosive or ""]
	if not (x and z and t) then
		return nil
	end
	local reach = Eventos.reachM(def, t.casualtyM)
	local ev = newEv(id, side, x, z, s, reach, Eventos.barrageS(def))
	local ax, az = axis(side)
	-- linha do A-4 de través à frente; o salvo não usa o rumo
	local heading = math.atan2(-az, -ax)
	local imps = Eventos.impacts(def, x, z, heading, M, roll)
	local last = 0
	for _, imp in imps do
		last = math.max(last, imp.t)
	end
	ev.data.blockUntil = ev.t0 + last + 3
	ev.data.blockR = reach + C.blockExtraM
	ev.data.impactEnd = ev.t0 + last
	local warnS = def.warnS or 0
	local where = sectorLabel(s)
	local g = grid(x, z)
	if id == "naval" then
		smoke(ev, x, z, Color3.fromRGB(200, 60, 50))
		notify(
			side,
			ev,
			string.format(
				"Galveston e Orleck vão bater em %s (%s) em %d s. Fique fora da fumaça vermelha e assalte depois.",
				where,
				g,
				warnS
			),
			"info",
			warnS
		)
		notify(
			ev.target,
			ev,
			string.format("Tiro naval chegando em %s (%s)! Saia da área marcada: %d s.", where, g, warnS),
			"alerta",
			warnS
		)
	elseif id == "air" then
		smoke(ev, x, z, Color3.fromRGB(150, 70, 170))
		notify(
			side,
			ev,
			string.format("A-4 em ataque sobre %s (%s) em %d s. Fumaça violeta: fique longe.", where, g, warnS),
			"info",
			warnS
		)
		notify(
			ev.target,
			ev,
			string.format("Aviões! Bombas em %s (%s) em %d s. Saia da área marcada.", where, g, warnS),
			"alerta",
			warnS
		)
	else
		notify(
			side,
			ev,
			string.format(
				"Os tubos de 82 mm abriram fogo sobre %s (%s): impacto em %d s. Avance depois.",
				where,
				g,
				warnS
			),
			"info",
			warnS
		)
		notify(
			ev.target,
			ev,
			string.format("Morteiro! Granadas caindo em %s (%s) em %d s. Abrigue-se fora da área.", where, g, warnS),
			"alerta",
			warnS
		)
	end
	-- som do disparo (os clientes já tocam naval_distant e mortar_launch pelo Fire_Launch)
	local launchFrom: Vector3? = nil
	local b = MapConfig.Bounds
	if id == "naval" then
		launchFrom = Vector3.new(b.maxX + 3000 / M, 0, (b.minZ + b.maxZ) / 2) -- navio ao largo, a leste (D-36)
	elseif id == "mortar" then
		local hq = MapConfig.HQ.VC
		local lx, lz = Eventos.towards(x, z, hq.x, hq.z, 300, M, b, 30)
		launchFrom = ground(lx, lz)
	end
	for _, imp in imps do
		local tImpact = imp.t
		if launchFrom then
			local lp, kind = launchFrom :: Vector3, if id == "naval" then "naval" else "mortar"
			task.delay(math.max(tImpact - warnS, 0), function()
				Net.unreliable("Fire_Launch"):FireAllClients({ kind = kind, x = lp.X, y = lp.Y, z = lp.Z })
			end)
		end
		task.delay(math.max(tImpact - 2.5, 0), function()
			local p = ground(imp.x, imp.z)
			Net.unreliable("Fire_Incoming"):FireAllClients({ x = p.X, y = p.Y, z = p.Z })
		end)
		task.delay(tImpact, function()
			if ev.phase ~= "fim" then
				ExplosionService.detonate(def.explosive :: string, ground(imp.x, imp.z))
			end
		end)
	end
	ev.update = function(e: Ev, now: number): boolean
		local sp = if e.sector then MatchService.points[e.sector] else nil
		if e.phase == "aviso" and now >= e.t0 + warnS then
			setPhase(e, "ativo")
		elseif e.phase == "ativo" and now >= e.data.impactEnd + 1 then
			setPhase(e, "janela")
			notify(e.side, e, string.format("Barragem terminou: tome %s agora (%d s).", where, C.assaultS), "info", 5)
		end
		-- janela: quem favorece e entra no ponto forte ganha na hora
		if e.phase == "janela" and sp then
			for _, p in playersNear(e.side, sp.x, sp.z, MapConfig.CaptureRadiusStuds * M) do
				award(e, p, false)
			end
		end
		if now >= e.endsAt then
			if sp then
				for _, p in playersNear(e.target, sp.x, sp.z, MapConfig.CaptureRadiusStuds * M) do
					award(e, p, true) -- segurou o ponto debaixo de fogo
				end
			end
			return true
		end
		return false
	end
	return ev
end

-- ===== helicóptero (inserção e medevac dos EUA) =====
local HELI_LEN_M = (Vehicles.SPECS.uh34d and Vehicles.SPECS.uh34d.lengthM) or 14.4 -- fuselagem 47 ft 2 in

local function heliModel(): Model
	local tpl = AssetLoader.template("uh34d")
	local m: Model
	if tpl then
		m = tpl:Clone()
		local _, size = m:GetBoundingBox()
		local long = math.max(size.X, size.Z)
		if long > 0 then
			m:ScaleTo(m:GetScale() * (HELI_LEN_M / M) / long)
		end
	else
		-- sem arte publicada: caixa oliva no tamanho da fuselagem
		m = Instance.new("Model")
		local body = Instance.new("Part")
		body.Size = Vector3.new(1.7, 2.6, HELI_LEN_M) / M
		body.Color = Color3.fromRGB(70, 78, 56)
		body.Parent = m
		m.PrimaryPart = body
	end
	m.Name = "UH-34D (evento)"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		end
	end
	return m
end

-- desce em 6 s até o chão, fica, e sobe ao fim; poeira enquanto pousado
local function landHeli(ev: Ev, x: number, z: number)
	local m = heliModel()
	local g = ground(x, z)
	local _, size = m:GetBoundingBox()
	local yaw = math.atan2(ev.x - MapConfig.HQ[ev.side].x, ev.z - MapConfig.HQ[ev.side].z)
	local function at(h: number): CFrame
		return CFrame.new(g + Vector3.new(0, size.Y / 2 + h / M, 0)) * CFrame.Angles(0, yaw, 0)
	end
	m:PivotTo(at(60))
	m.Parent = world
	table.insert(ev.props, m)
	ev.data.heli = m
	task.spawn(function()
		for i = 1, 60 do
			if m.Parent == nil then
				return
			end
			m:PivotTo(at(60 * (1 - i / 60) ^ 2))
			task.wait(0.1)
		end
		local dust = anchoredPart(Vector3.new(1, 1, 1), CFrame.new(g), Color3.new(), Enum.Material.Air, m)
		dust.Transparency = 1
		local s = Instance.new("Smoke")
		s.Color = Color3.fromRGB(150, 128, 96)
		s.Opacity = 0.25
		s.RiseVelocity = 2
		s.Size = 14
		s.Parent = dust
	end)
end

local function liftHeli(ev: Ev)
	local m = ev.data.heli :: Model?
	if not (m and m.Parent) then
		return
	end
	local mm = m :: Model
	task.spawn(function()
		local cf = mm:GetPivot()
		for i = 1, 40 do
			if mm.Parent == nil then
				return
			end
			mm:PivotTo(cf + Vector3.new(0, (i / 40) ^ 2 * 60 / M, 0))
			task.wait(0.1)
		end
	end)
end

local function startLz(side: string): Ev?
	local s, sp = attackTarget(side)
	if not (s and sp) then
		return nil
	end
	local hq = MapConfig.HQ[side]
	local enemies = standing(Eventos.other(side))
	local x, z = nil :: number?, nil :: number?
	for extra = 0, 60, 20 do
		local cx, cz = Eventos.towards(sp.x, sp.z, hq.x, hq.z, C.lzFromTargetM + extra, M, MapConfig.Bounds, 30)
		local clear = true
		for _, en in enemies do
			if distM(en.pos.X, en.pos.Z, cx, cz) < C.lzEnemyClearM then
				clear = false
				break
			end
		end
		if clear then
			x, z = cx, cz
			break
		end
	end
	if not (x and z) then
		return nil
	end
	local def = Eventos.DEFS.heli
	local ev = newEv("heli", side, x, z, s, C.lzHotM, def.durationS)
	ev.data.hot = {} :: { [Player]: boolean }
	landHeli(ev, x, z)
	local g = grid(x, z)
	notify(
		side,
		ev,
		string.format(
			"UH-34D pousando reforços na LZ %s, a %d m de %s. Nasça na LZ.",
			g,
			C.lzFromTargetM,
			sectorLabel(s)
		),
		"info",
		8
	)
	notify(
		ev.target,
		ev,
		string.format("Helicópteros pousando na LZ %s! Ataque a LZ antes que o reforço avance.", g),
		"alerta",
		8
	)
	ev.update = function(e: Ev, now: number): boolean
		if e.phase == "aviso" and now >= e.t0 + 6 then
			setPhase(e, "ativo") -- pousado: vira ponto de nascimento (provedor abaixo)
		end
		if e.phase == "ativo" then
			for _, p in playersNear(e.target, e.x, e.z, C.lzHotM) do
				e.data.hot[p] = true
			end
			if now >= e.endsAt - 4 then
				setPhase(e, "janela")
				liftHeli(e)
			end
		end
		if now >= e.endsAt then
			for p in e.data.hot do
				local c = p.Character
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					award(e, p, true) -- atacou a LZ e está vivo
				end
			end
			return true
		end
		return false
	end
	return ev
end

-- ===== resgate de feridos =====
-- O ponto: a reunião atrás do ponto forte próprio mais perto da frente, 25 m para o lado.
local function ownFrontPoint(side: string): (number?, number?, number?)
	local st = MatchService.state :: any
	if not st then
		return nil, nil, nil
	end
	for _, pair in Front.forwardPairs(st.owner, st.active, side) do
		local sp = MatchService.points[pair.own]
		if sp then
			local x, z = SpawnRules.rallyPosition(sp.x, sp.z, side, M)
			x, z = Front.clampInside(MapConfig.Bounds, x, z + 25 / M, Front.C.rallyInsetM / M)
			return x, z, pair.own
		end
	end
	return nil, nil, nil
end

local function aidStation(ev: Ev, x: number, z: number)
	local g = ground(x, z)
	local f = Instance.new("Model")
	f.Name = "PostoDeSocorro"
	anchoredPart(
		Vector3.new(0.6, 0.12, 1.9) / M,
		CFrame.new(g + Vector3.new(0, 0.3 / M, 0)),
		Color3.fromRGB(150, 128, 80),
		Enum.Material.Wood,
		f
	)
	anchoredPart(
		Vector3.new(2.4, 0.05, 2.4) / M,
		CFrame.new(g + Vector3.new(0, 1.9 / M, 0)),
		Color3.fromRGB(70, 74, 52),
		Enum.Material.Fabric,
		f
	)
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		anchoredPart(
			Vector3.new(0.05, 1.9, 0.05) / M,
			CFrame.new(g + Vector3.new(c[1] * 1.15 / M, 0.95 / M, c[2] * 1.15 / M)),
			Color3.fromRGB(120, 100, 60),
			Enum.Material.Wood,
			f
		)
	end
	f.Parent = world
	table.insert(ev.props, f)
end

local function startMedevac(side: string): Ev?
	local x, z, s = ownFrontPoint(side)
	if not (x and z) then
		return nil
	end
	local def = Eventos.DEFS.medevac
	local ev = newEv("medevac", side, x, z, s, FieldWork.MEDEVAC.radiusM, def.durationS)
	ev.data.timer = {} :: { [Model]: number }
	if side == "US" then
		landHeli(ev, x, z)
		notify(
			side,
			ev,
			string.format(
				"Medevac: UH-34D pousado em %s por %d s. Feridos a até %d m são atendidos; caídos, evacuados.",
				grid(x, z),
				def.durationS,
				FieldWork.MEDEVAC.radiusM
			),
			"info",
			8
		)
	else
		aidStation(ev, x, z)
		notify(
			side,
			ev,
			string.format(
				"Posto de socorro aberto em %s por %d s: feridos a até %d m são atendidos.",
				grid(x, z),
				def.durationS,
				FieldWork.MEDEVAC.radiusM
			),
			"info",
			8
		)
	end
	ev.update = function(e: Ev, now: number): boolean
		if e.phase == "aviso" and now >= e.t0 + 6 then
			setPhase(e, "ativo")
		end
		if e.phase ~= "ativo" then
			return now >= e.endsAt
		end
		for _, en in Combatants.list() do
			local root, model = Combatants.root(en), en.model
			local hum = Combatants.humanoid(en)
			if en.faction ~= e.side or not root or not hum or hum.Health <= 0 or model:GetAttribute("Evacuated") then
				continue
			end
			local near = distM(root.Position.X, root.Position.Z, e.x, e.z) <= FieldWork.MEDEVAC.radiusM
			local st = MedicalService.get(model)
			local downed = model:GetAttribute("Downed") == true
			local wounded = st ~= nil and #st.wounds > 0
			local tt, done = FieldWork.boarding(e.data.timer[model] or 0, near and (downed or wounded), 1)
			e.data.timer[model] = tt
			if done then
				e.data.timer[model] = nil
				if downed then
					-- como o medevac do FieldWorkService: não conta como baixa, devolve suprimento
					model:SetAttribute("Evacuated", true)
					Logistics.add(LogisticsService.state, e.side, FieldWork.MEDEVAC.supply)
					hum.Health = 0
				elseif st and Medical.treat(st) then
					MedicalService.apply(model)
				end
				award(e, en.player, false)
				for _, p in playersNear(e.side, root.Position.X, root.Position.Z, C.escortM) do
					if p ~= en.player then
						award(e, p, true)
					end
				end
			end
		end
		if now >= e.endsAt - 4 then
			setPhase(e, "janela")
			liftHeli(e)
		end
		return now >= e.endsAt
	end
	return ev
end

-- ===== depósito de munição do VC =====
local function depotPoint(): (number?, number?, number?)
	local st = MatchService.state :: any
	local s = attackTarget("US")
	if not (st and s) then
		return nil, nil, nil
	end
	-- o setor do VC mais perto do que os EUA atacam (pode ser ele mesmo)
	local best: number? = nil
	for k = 1, #st.owner do
		if st.owner[k] == "VC" and st.active[k] and MatchService.points[k] then
			if not best or math.abs(k - s) < math.abs((best :: number) - s) then
				best = k
			end
		end
	end
	local sp = if best then MatchService.points[best] else nil
	if not (best and sp) then
		return nil, nil, nil
	end
	local x, z = SpawnRules.rallyPosition(sp.x, sp.z, "VC", M)
	x, z = Front.clampInside(MapConfig.Bounds, x, z + C.depotSideM / M, Front.C.rallyInsetM / M)
	return x, z, best
end

local function startDepot(side: string): Ev?
	local x, z, s = depotPoint()
	if not (x and z) then
		return nil
	end
	local def = Eventos.DEFS.depot
	local ev = newEv("depot", side, x, z, s, 15, def.durationS)
	local g = ground(x, z)
	local model = Instance.new("Model")
	model.Name = "DepositoVC"
	local main: Part? = nil
	for i, o in { { 0, 0 }, { 0.9, 0 }, { -0.9, 0 }, { 0, 0.7 }, { 0.9, 0.7 }, { 0.45, 0.35 } } do
		local y = if i == 6 then 0.75 else 0.25
		local p = anchoredPart(
			Vector3.new(0.8, 0.5, 0.6) / M,
			CFrame.new(g + Vector3.new(o[1] / M, y / M, o[2] / M)),
			Color3.fromRGB(104, 88, 54),
			Enum.Material.Wood,
			model
		)
		p.CanCollide, p.CanQuery = true, true -- abrigo e alvo de verdade
		main = main or p
	end
	model.Parent = world
	table.insert(ev.props, model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Plantar carga"
	prompt.ObjectText = "Depósito de munição do VC"
	prompt.HoldDuration = 5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = main
	ev.data.armedBy = nil :: Player?
	ev.data.blowAt = nil :: number?
	local FUSE = 8 -- aviso antes de explodir (nunca matar sem aviso)
	local function alive(p: Player): boolean
		local c = p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.Health > 0 and not (c :: Model):GetAttribute("Downed")
	end
	prompt.Triggered:Connect(function(p: Player)
		if ev.phase == "fim" or not alive(p) then
			return
		end
		local f = p:GetAttribute("Faction")
		if not ev.data.blowAt and f == "US" then
			ev.data.armedBy, ev.data.blowAt = p, os.clock() + FUSE
			prompt.ActionText, prompt.HoldDuration = "Desarmar carga", 4
			setPhase(ev, "armado")
			local sp = Instance.new("Sparkles")
			sp.SparkleColor = Color3.fromRGB(255, 190, 90)
			sp.Parent = main
			notify(
				"US",
				ev,
				string.format("Carga plantada no depósito: explode em %d s. Afaste-se.", FUSE),
				"alerta",
				FUSE
			)
			notify(
				"VC",
				ev,
				string.format("Carga no depósito %s! Desarme ou afaste-se: %d s.", grid(ev.x, ev.z), FUSE),
				"alerta",
				FUSE
			)
		elseif ev.data.blowAt and f == "VC" then
			ev.data.armedBy, ev.data.blowAt = nil, nil
			prompt.ActionText, prompt.HoldDuration = "Plantar carga", 5
			setPhase(ev, "ativo")
			local spk = main and main:FindFirstChildOfClass("Sparkles")
			if spk then
				spk:Destroy()
			end
			notify("VC", ev, "Carga desarmada. Segure o depósito.", "sucesso", 4)
			notify("US", ev, "O VC desarmou a carga no depósito.", "erro", 4)
		end
	end)
	local g6 = grid(x, z)
	notify(
		"US",
		ev,
		string.format("Depósito de munição do VC achado em %s: plante a carga (segure a interação).", g6),
		"info",
		8
	)
	notify("VC", ev, string.format("Defenda o depósito de munição em %s por %d s.", g6, def.durationS), "alerta", 8)
	ev.update = function(e: Ev, now: number): boolean
		if e.phase == "aviso" then
			setPhase(e, "ativo")
		end
		local blowAt = e.data.blowAt :: number?
		if blowAt and now >= blowAt then
			local by = e.data.armedBy :: Player?
			local pos = g + Vector3.new(0, 0.5 / M, 0)
			ExplosionService.detonate(def.explosive :: string, pos, by)
			for k, dt in { 1.2, 2.4 } do
				task.delay(dt, function()
					local a = k * 2.1
					ExplosionService.detonate("mortar_82", pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 5 / M, by)
				end)
			end
			award(e, by, true)
			for _, p in playersNear("US", e.x, e.z, 60) do
				award(e, p, true)
			end
			notify("US", e, "Depósito do VC destruído.", "sucesso", 4)
			notify("VC", e, "O depósito de munição foi destruído.", "erro", 4)
			return true
		end
		if now >= e.endsAt then
			Logistics.add(LogisticsService.state, "VC", 60) -- PLACEHOLDER: munição do depósito para o time
			for _, p in playersNear("VC", e.x, e.z, 80) do
				award(e, p, false)
			end
			notify("VC", e, "Depósito defendido: +60 de suprimento para o time.", "sucesso", 4)
			notify("US", e, "O depósito do VC ficou de pé.", "erro", 4)
			return true
		end
		return false
	end
	return ev
end

-- ===== contra-ataque =====
local function startCounter(sector: number, loser: string): Ev?
	local sp = MatchService.points[sector]
	if not sp or MatchService.mode == "Offensive" then
		return nil -- no Offensive o setor tomado pelos EUA fica travado
	end
	for _, e in active do
		if e.id == "counter" and e.sector == sector then
			return nil
		end
	end
	local def = Eventos.DEFS.counter
	local ev = newEv("counter", loser, sp.x, sp.z, sector, MapConfig.CaptureRadiusStuds * M, def.durationS)
	setPhase(ev, "ativo")
	notify(
		loser,
		ev,
		string.format("Contra-ataque: retome %s em %d s (recompensa de retomada).", sectorLabel(sector), def.durationS),
		"alerta",
		8
	)
	notify(
		ev.target,
		ev,
		string.format("O inimigo vai contra-atacar %s: segure por %d s.", sectorLabel(sector), def.durationS),
		"alerta",
		8
	)
	ev.update = function(e: Ev, now: number): boolean
		local st = MatchService.state :: any
		local owner = st and st.owner[sector]
		local rM = MapConfig.CaptureRadiusStuds * M
		if owner == e.side then
			for _, p in playersNear(e.side, e.x, e.z, rM) do
				award(e, p, false)
			end
			notify(e.side, e, string.format("%s retomado no contra-ataque.", sectorLabel(sector)), "sucesso", 4)
			return true
		end
		if now >= e.endsAt then
			for _, p in playersNear(e.target, e.x, e.z, rM) do
				award(e, p, true)
			end
			notify(e.target, e, string.format("Contra-ataque contido em %s.", sectorLabel(sector)), "sucesso", 4)
			return true
		end
		return false
	end
	return ev
end

-- ===== agenda =====
local STARTERS: { [string]: (side: string) -> Ev? } = {
	naval = function(side: string): Ev?
		return startBarrage("naval", side)
	end,
	air = function(side: string): Ev?
		return startBarrage("air", side)
	end,
	mortar = function(side: string): Ev?
		return startBarrage("mortar", side)
	end,
	heli = startLz,
	medevac = startMedevac,
	depot = startDepot,
}

local function barrageActive(): boolean
	for _, e in active do
		if e.def.kind == "barrage" and e.phase ~= "fim" then
			return true
		end
	end
	return false
end

-- Há alvo agora? (barato: só as escolhas de setor, sem montar nada)
local function availability(): { [string]: boolean }
	local usT = attackTarget("US") ~= nil
	local vcT = attackTarget("VC") ~= nil
	local busy = barrageActive()
	return {
		naval = usT and not busy,
		air = usT and not busy,
		mortar = vcT and not busy,
		heli = usT,
		medevac = true,
		depot = depotPoint() ~= nil,
	}
end

local function launch(id: string, side: string): boolean
	local fn = STARTERS[id]
	local def = Eventos.DEFS[id]
	if not (fn and def) then
		return false
	end
	local s = if def.side == "any" then side else def.side
	local ok, ev = pcall(fn, s)
	if not ok then
		warn("[VT65] evento", id, "falhou:", ev)
		return false
	end
	if ev then
		print(string.format("[VT65 EVENTO] %s para %s em %s", id, s, grid(ev.x, ev.z)))
		lastId, lastSide = id, s
		counts[s] = (counts[s] or 0) + 1
		return true
	end
	return false
end

local function resetMatch()
	for _, e in active do
		finish(e)
	end
	table.clear(active)
	matchKey = MatchService.startedAt
	nextAt = matchKey + C.firstAtS
	lastId, lastSide = nil, nil
	counts = { US = 0, VC = 0 }
	local st = MatchService.state :: any
	prevOwner = if st then table.clone(st.owner) else {}
end

local function step()
	if MatchService.startedAt ~= matchKey then
		resetMatch()
	end
	local now = os.clock()
	-- eventos em curso
	for i = #active, 1, -1 do
		local e = active[i]
		local ok, done = pcall(e.update, e, now)
		if not ok then
			warn("[VT65] evento", e.id, "falhou:", done)
		end
		if not ok or done then
			finish(e)
			table.remove(active, i)
		end
	end
	if not stateOk() then
		return
	end
	-- contra-ataque: setor perdido
	local st = MatchService.state :: any
	for _, loss in Eventos.losses(prevOwner, st.owner) do
		if st.active[loss.sector] then
			local ok, err = pcall(startCounter, loss.sector, loss.loser)
			if not ok then
				warn("[VT65] contra-ataque falhou:", err)
			end
		end
	end
	prevOwner = table.clone(st.owner)
	-- próximo evento da agenda
	if now >= nextAt then
		local avail = availability()
		local id: string?, side: string? = nil, nil
		if lastId == nil and avail.heli then
			id, side = "heli", "US" -- abertura: a LZ quente puxa os dois lados para o mesmo lugar
		else
			id, side = Eventos.pick(lastId, lastSide, counts, avail, roll())
		end
		if id and side and launch(id, side) then
			nextAt = now + Eventos.gap(roll())
		else
			nextAt = now + C.retryS
		end
	end
end

function EventosService.start()
	-- recompensas dos eventos no mesmo sistema de XP e créditos (teto por minuto incluído)
	for key, r in Eventos.rewards() do
		(Progression.REWARDS :: any)[key] = r
	end
	local mf = Instance.new("Folder")
	mf.Name = "VT65Eventos"
	mf.Parent = ReplicatedStorage
	markers = mf
	local wf = Instance.new("Folder")
	wf.Name = "VT65Eventos"
	wf.Parent = workspace
	world = wf
	-- ninguém nasce dentro de uma barragem já avisada (vale para os dois lados)
	SpawnService.addBlocker(function(x: number, z: number, _faction: string): string?
		local now = os.clock()
		for _, e in active do
			local untilT = e.data.blockUntil :: number?
			if untilT and now < untilT and distM(x, z, e.x, e.z) <= (e.data.blockR :: number) then
				return "barragem chegando"
			end
		end
		return nil
	end)
	-- LZ pousada: ponto de nascimento do lado que chega
	SpawnService.addProvider(function(faction: string): { SpawnService.Point }
		local out: { SpawnService.Point } = {}
		for _, e in active do
			if e.id == "heli" and e.side == faction and e.phase == "ativo" then
				table.insert(out, {
					id = "lz:" .. e.uid,
					name = string.format("LZ — inserção (%s)", grid(e.x, e.z)),
					x = e.x,
					z = e.z,
					kind = "rally",
				})
			end
		end
		return out
	end)
	-- quem nasceu na LZ leva a recompensa de inserção
	Combatants.Added:Connect(function(entry: Combatants.Entry)
		local p = entry.player
		local r = Combatants.root(entry)
		if not (p and r) then
			return
		end
		for _, e in active do
			if e.id == "heli" and e.side == entry.faction and e.phase == "ativo" then
				if distM(r.Position.X, r.Position.Z, e.x, e.z) <= 30 then
					award(e, p, false)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function(): any
				step()
				return nil
			end)
			if not ok then
				warn("[VT65] eventos:", err)
			end
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevEvento"):Connect(function()
			local v = workspace:GetAttribute("VT65DevEvento")
			if type(v) ~= "string" then
				return
			end
			task.defer(function()
				workspace:SetAttribute("VT65DevEvento", nil)
			end)
			if v == "proximo" then
				nextAt = 0
			elseif v == "counter" then
				local st = MatchService.state :: any
				local s = st and (attackTarget("US"))
				if s then
					print("[VT65 TESTE] contra-ataque:", startCounter(s, "US") ~= nil)
				end
			elseif STARTERS[v] then
				local def = Eventos.DEFS[v]
				local side = if def.side == "any" then (if lastSide == "US" then "VC" else "US") else def.side
				print("[VT65 TESTE] evento", v, "para", side, launch(v, side))
			else
				warn("[VT65] VT65DevEvento desconhecido:", v)
			end
		end)
	end
end

return EventosService
