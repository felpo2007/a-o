--!strict
-- Partida Warfare/Offensive/Skirmish: sorteio dos pontos fortes, captura, tempo e vitória (Parte 4).
-- Servidor público alterna Warfare e Offensive; o privado fica no modo escolhido pelo dono.
-- Ritmo e clareza (pedido do dono, 2026-11-11):
--   - pontos fortes sorteados em cadeia a partir da frente (Front.pickStrongpoints): a frente
--     inicial fica compacta;
--   - atrito no Warfare (Capture.newScore): reforços por lado, -1 por morte, sangria por setor de
--     vantagem; zerou, perdeu;
--   - o Match_State leva quem está tomando cada setor, a disputa, as baixas, os reforços e o placar
--     final (HUD da frente, avisos e tela de fim no cliente);
--   - reunião avançada, reunião do squad e posições do squad (FrontService) e a imagem da carta
--     (CartaService) começam aqui: o Main não está na lista de arquivos desta tarefa.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AfterAction = require(ReplicatedStorage.Shared.AfterAction)
local Capture = require(ReplicatedStorage.Shared.Capture)
local Front = require(ReplicatedStorage.Shared.Front)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Offensive = require(ReplicatedStorage.Shared.Offensive)
local Weather = require(ReplicatedStorage.Shared.Weather)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Combatants = require(script.Parent.Combatants)

export type Strongpoint = { sector: number, name: string, x: number, z: number, real: boolean }

local MatchService = {}
MatchService.mode = "Warfare"
MatchService.state = nil :: Capture.State?
MatchService.points = {} :: { [number]: Strongpoint }
MatchService.startedAt = 0
MatchService.waveEpoch = 0
MatchService.capturedAt = {} :: { [number]: number }
MatchService.initialOwner = {} :: { [number]: string }
MatchService.ended = false
MatchService.offensive = nil :: Offensive.State?
MatchService.report = nil :: AfterAction.Report? -- relatório pós-ação da partida em curso
MatchService.shower = nil :: Weather.Shower? -- pancada de chuva sorteada para a partida (ou nenhuma)
MatchService.rotation = { "Warfare", "Offensive" }
MatchService.countsOverride = nil :: (() -> { { US: number, VC: number } })? -- só autoteste (Studio)
MatchService.score = nil :: Capture.Score? -- reforços (atrito), só no Warfare
MatchService.winner = nil :: string?
MatchService.endedAt = 0
MatchService.NEXT_MATCH_S = 30 -- relatório e placar na tela antes da próxima partida
-- D-122 (pedido do dono: "a partida deve começar com cada um na sua base com uma contagem regressiva;
-- depois a partida começa e os jogadores vão dominar os pontos"): cada partida nova abre com PREP_S
-- de preparo. Nele não há captura nem sangria de reforços, o relógio da partida não anda, todo mundo
-- nasce no QG e fica perto dele (PreparoService) e os bots esperam na base.
MatchService.PREP_S = 30
MatchService.prepUntil = 0

function MatchService.inPrep(): boolean
	return not MatchService.ended and os.clock() < MatchService.prepUntil
end

function MatchService.prepLeft(): number
	return math.max(0, MatchService.prepUntil - os.clock())
end

-- algum jogador (gente) vivo em campo? A contagem só corre com alguém para vê-la: num servidor novo
-- a partida abre com todos ainda carregando (~70 s no Studio) e os 30 s passariam no menu
local function humanInField(): boolean
	for _, p in Players:GetPlayers() do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return true
		end
	end
	return false
end
local holding = false -- contagem segurada até o primeiro jogador nascer
local pendingMode: string? = nil
local fixedMode = false -- servidor privado: o dono escolheu o modo

local function limitSeconds(): number
	local o = MatchService.offensive
	if MatchService.mode == "Offensive" and o then
		return o.deadline -- cresce a cada setor tomado
	end
	return (if MatchService.mode == "Skirmish" then Capture.C.skirmishMinutes else Capture.C.warfareMinutes) * 60
end

-- Bandeira no ponto forte sorteado de cada setor ativo (D-64). Antes era um disco amarelo de
-- ForceField, do greybox. O disco continua no mapa (atributos do ponto), mas invisível. A bandeira
-- troca com o dono: EUA, Frente (VC) ou só o mastro (neutro).
local M = 0.28
local flagFolder: Folder? = nil
local flags: { [number]: Model } = {}

local function groundAt(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return if hit then hit.Position.Y else 0
end

local function flagPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Size, p.CFrame, p.Color, p.Material = size, cf, color, mat
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = parent
	return p
end

-- pano de 1,5 x 1,0 m preso no topo do mastro, para +X; camadas mais grossas na frente (sem z-fighting)
local function paintFlag(m: Model, owner: string)
	if m:GetAttribute("Owner") == owner then
		return
	end
	m:SetAttribute("Owner", owner)
	local old = m:FindFirstChild("Cloth")
	if old then
		old:Destroy()
	end
	if owner ~= "US" and owner ~= "VC" then
		return -- neutro: só o mastro
	end
	local cloth = Instance.new("Model")
	cloth.Name = "Cloth"
	local top = m:GetAttribute("Top") :: CFrame
	local W, H = 1.5 / M, 1.0 / M
	local function rect(u0: number, v0: number, w: number, h: number, t: number, color: Color3)
		local cf = top * CFrame.new((u0 + w / 2) * W, -(v0 + h / 2) * H, 0)
		flagPart(cloth, Vector3.new(w * W, h * H, t / M), cf, color, Enum.Material.Fabric)
	end
	if owner == "US" then
		rect(0, 0, 1, 1, 0.02, Color3.fromRGB(236, 232, 220))
		for k = 0, 6, 2 do
			rect(0, k / 7, 1, 1 / 7, 0.026, Color3.fromRGB(160, 36, 44))
		end
		rect(0, 0, 0.4, 4 / 7, 0.032, Color3.fromRGB(40, 48, 92))
	else
		rect(0, 0, 1, 0.5, 0.02, Color3.fromRGB(196, 38, 36))
		rect(0, 0.5, 1, 0.5, 0.02, Color3.fromRGB(30, 92, 168))
		local star = top * CFrame.new(0.5 * W, -0.5 * H, 0) * CFrame.Angles(0, 0, math.rad(45))
		flagPart(
			cloth,
			Vector3.new(0.22 / M, 0.22 / M, 0.03 / M),
			star,
			Color3.fromRGB(250, 214, 40),
			Enum.Material.Fabric
		)
	end
	cloth.Parent = m
end

local function updateFlags()
	local st = MatchService.state
	if not st then
		return
	end
	for s, m in flags do
		paintFlag(m, st.owner[s] or "Neutral")
	end
end

local waitingTerrain = false
local function showMarkers()
	local st = MatchService.state
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Strongpoints")
	if not (folder and st) then
		return
	end
	-- o mastro vai no chão real: o terreno é gerado em runtime (~50 s)
	if ReplicatedStorage:GetAttribute("TerrainReady") ~= true then
		if not waitingTerrain then
			waitingTerrain = true
			task.spawn(function()
				while ReplicatedStorage:GetAttribute("TerrainReady") ~= true do
					ReplicatedStorage:GetAttributeChangedSignal("TerrainReady"):Wait()
				end
				waitingTerrain = false
				showMarkers()
			end)
		end
		return
	end
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			p.Transparency = 1
		end
	end
	if not flagFolder then
		local f = Instance.new("Folder")
		f.Name = "Flags"
		f.Parent = map
		flagFolder = f
	end
	for s, m in flags do
		m:Destroy()
		flags[s] = nil
	end
	for s, sp in MatchService.points do
		if st.active[s] then
			local m = Instance.new("Model")
			m.Name = "Flag_" .. sp.name
			local y = groundAt(sp.x, sp.z)
			local poleH = 7 / M
			local pole = flagPart(
				m,
				Vector3.new(poleH, 0.08 / M, 0.08 / M),
				CFrame.new(sp.x, y + poleH / 2, sp.z) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(92, 76, 54),
				Enum.Material.Wood
			)
			pole.Shape = Enum.PartType.Cylinder
			pole.CastShadow = true
			m:SetAttribute("Top", CFrame.new(sp.x + 0.05 / M, y + poleH - 0.15 / M, sp.z))
			m.Parent = flagFolder
			flags[s] = m
		end
	end
	updateFlags()
end

function MatchService.newMatch(mode: string?)
	MatchService.mode = mode or pendingMode or Capture.nextMode(MatchService.mode, fixedMode, MatchService.rotation)
	pendingMode = nil
	local rng = Rng.new(os.time())
	local bySector: { [number]: { any } } = {}
	for _, sp in MapConfig.Strongpoints do
		bySector[sp.sector] = bySector[sp.sector] or {}
		table.insert(bySector[sp.sector], sp)
	end
	-- um ponto por setor, sorteado em cadeia a partir da frente inicial: o vizinho mais perto do
	-- ponto já escolhido tem mais chance (peso 1/d²). Antes era um sorteio solto por setor e a frente
	-- podia começar a 1 km do ponto de reunião (5 min até o primeiro contato no Studio).
	local n = #MapConfig.Sectors
	local picked = Front.pickStrongpoints(bySector, n, Front.firstSector(MatchService.mode, n), function()
		return rng:next()
	end)
	MatchService.points = {}
	for s, sp in picked do
		MatchService.points[s] = { sector = s, name = sp.name, x = sp.x, z = sp.z, real = sp.real }
	end
	MatchService.score = if MatchService.mode == "Warfare" then Capture.newScore() else nil
	MatchService.winner = nil
	MatchService.offensive = nil
	if MatchService.mode == "Offensive" then
		local o = Offensive.new(#MapConfig.Sectors)
		MatchService.offensive = o
		MatchService.state = o.capture
		MatchService.initialOwner = table.clone(o.capture.owner)
	else
		local initial = table.clone(MapConfig.InitialOwner)
		-- D-123: quantos setores o mapa tiver (3 no mapa de 700 m); no Skirmish, só o do meio
		local nS = #MapConfig.Sectors
		local active = table.create(nS, true)
		if MatchService.mode == "Skirmish" then
			active = table.create(nS, false)
			active[math.ceil(nS / 2)] = true
		end
		MatchService.state = Capture.new(initial, active)
		MatchService.initialOwner = initial
	end
	MatchService.capturedAt = {}
	-- o relógio da partida começa quando a contagem acaba (D-122)
	MatchService.prepUntil = os.clock() + MatchService.PREP_S
	MatchService.startedAt = MatchService.prepUntil
	MatchService.waveEpoch = MatchService.startedAt
	MatchService.ended = false
	showMarkers()
	MatchService.report = AfterAction.new(MatchService.mode, Lighting.ClockTime)
	-- chuva: o Skirmish (20 min) é curto demais; Warfare e Offensive podem ter uma pancada
	local wr = Rng.new(os.time() + 1965)
	MatchService.shower = if MatchService.mode == "Skirmish"
		then nil
		else Weather.schedule(Capture.C.warfareMinutes * 60, function()
			return wr:next()
		end)
	ReplicatedStorage:SetAttribute("Rain", 0)
	ReplicatedStorage:SetAttribute("MatchMode", MatchService.mode)
end

function MatchService.requestMode(mode: string)
	pendingMode = mode -- vale para a próxima partida (ou já, se ninguém entrou)
	fixedMode = true
	if #Players:GetPlayers() <= 1 then
		MatchService.newMatch(mode)
	end
end

function MatchService.ownerOf(sector: number): string
	local st = MatchService.state
	return if st then st.owner[sector] else "Neutral"
end

local lastCounts: { { US: number, VC: number } } = {}

function MatchService.isContested(sector: number): boolean
	local c = lastCounts[sector]
	return c ~= nil and c.US > 0 and c.VC > 0
end

-- D-107 (bots: contra-ataque): quantos do outro lado estão na área de captura do setor (a contagem do
-- último segundo, a mesma da captura)
function MatchService.enemiesIn(sector: number, faction: string): number
	local c = lastCounts[sector]
	if not c then
		return 0
	end
	return if faction == "US" then c.VC elseif faction == "VC" then c.US else 0
end

local function counts(): { { US: number, VC: number } }
	local out = {}
	local r2 = MapConfig.CaptureRadiusStuds ^ 2
	for s = 1, #MapConfig.Sectors do
		out[s] = { US = 0, VC = 0 }
	end
	for _, e in Combatants.list() do
		local root = Combatants.root(e)
		if (e.faction == "US" or e.faction == "VC") and root and Combatants.active(e) then
			for s, sp in MatchService.points do
				local dx, dz = root.Position.X - sp.x, root.Position.Z - sp.z
				if dx * dx + dz * dz <= r2 then
					local c = out[s] :: any
					c[e.faction] += 1
				end
			end
		end
	end
	return out
end

local function publish()
	local st = MatchService.state
	if not st then
		return
	end
	local pts = {}
	for s, sp in MatchService.points do
		pts[s] = { name = sp.name, x = sp.x, z = sp.z }
	end
	-- quem está tomando cada setor e a disputa (o estado do ponto, nunca a posição de ninguém). Vão
	-- como listas cheias ("" = ninguém): tabela com buraco perde as chaves numéricas no remote.
	local cap, con = Capture.activity(st, lastCounts)
	local capturing, contested = {}, {}
	-- quantos de cada lado estão na área de captura de cada setor (a contagem do segundo, a mesma da
	-- captura): a barra de captura do HUD mostra aliados e inimigos a quem está no ponto. É o estado
	-- do ponto (números), nunca a posição de ninguém. Lista cheia: o remote perde chave com buraco.
	local inArea = {}
	for s = 1, #st.owner do
		capturing[s] = cap[s] or ""
		contested[s] = con[s] == true
		local c = lastCounts[s]
		inArea[s] = { US = if c then c.US else 0, VC = if c then c.VC else 0 }
	end
	local rep = MatchService.report
	local score = MatchService.score
	local now = os.clock()
	Net.event("Match_State"):FireAllClients({
		mode = MatchService.mode,
		owner = st.owner,
		progress = st.progress,
		active = st.active,
		points = pts,
		timeLeft = math.max(0, limitSeconds() - math.max(0, now - MatchService.startedAt)),
		elapsed = math.max(0, now - MatchService.startedAt),
		-- D-122: segundos que faltam para a partida começar (0 = valendo)
		prep = math.ceil(MatchService.prepLeft()),
		ended = MatchService.ended,
		front = if MatchService.offensive then MatchService.offensive.front else nil,
		capturing = capturing,
		contested = contested,
		inArea = inArea,
		-- atrito (Warfare): reforços de cada lado e o inicial, para a barra do HUD
		score = if score then { US = score.US, VC = score.VC, max = Capture.C.reinforcements } else nil,
		kia = if rep then { US = AfterAction.total(rep, "US"), VC = AfterAction.total(rep, "VC") } else nil,
		winner = MatchService.winner,
		nextIn = if MatchService.ended
			then math.max(0, MatchService.NEXT_MATCH_S - (now - MatchService.endedAt))
			else nil,
		-- relatório pós-ação: só no fim (texto pronto, ~70 linhas no máximo)
		report = if MatchService.ended and rep then AfterAction.lines(rep) else nil,
	})
end

-- Progressão (D-72): eventos de captura e fim de partida para quem ganha XP. Ganchos postos pelo
-- ProgressionService (sem dependência circular).
MatchService.onEvent = nil :: ((kind: string, sector: number, team: string?) -> ())?
MatchService.onEnd = nil :: ((winner: string, seconds: number) -> ())?

local function endMatch(winner: string)
	MatchService.ended = true
	MatchService.winner = winner
	MatchService.endedAt = os.clock()
	if MatchService.onEnd then
		task.spawn(MatchService.onEnd, winner, os.clock() - MatchService.startedAt)
	end
	local st = MatchService.state
	if MatchService.report and st then
		AfterAction.finish(MatchService.report, winner, os.clock() - MatchService.startedAt, st.owner)
	end
	ReplicatedStorage:SetAttribute("LastWinner", winner)
	publish()
	task.delay(MatchService.NEXT_MATCH_S, function()
		MatchService.newMatch()
	end)
end

function MatchService.start()
	MatchService.newMatch("Warfare")
	-- Ganchos de teste SÓ no Studio (o require da barra de comando pega outra cópia deste módulo):
	--   workspace:SetAttribute("VT65DevMode", "Offensive")  -- troca o modo agora (e fixa)
	--   workspace:SetAttribute("VT65DevEnd", true)          -- encerra a partida (relatório pós-ação)
	if RunService:IsStudio() then
		local function devMode()
			local m = workspace:GetAttribute("VT65DevMode")
			if m == "Warfare" or m == "Offensive" or m == "Skirmish" then
				pendingMode = nil
				fixedMode = true
				MatchService.newMatch(m)
			end
		end
		workspace:GetAttributeChangedSignal("VT65DevMode"):Connect(devMode)
		devMode()
		workspace:GetAttributeChangedSignal("VT65DevEnd"):Connect(function()
			local st = MatchService.state
			if workspace:GetAttribute("VT65DevEnd") == true and st and not MatchService.ended then
				workspace:SetAttribute("VT65DevEnd", nil)
				local us, vc = Capture.count(st, "US"), Capture.count(st, "VC")
				endMatch(if us > vc then "US" elseif vc > us then "VC" else "draw")
			end
		end)
	end
	-- baixas para o relatório: cada morte conta no setor onde aconteceu
	Combatants.Added:Connect(function(e: any)
		local hum = Combatants.humanoid(e)
		if not hum then
			return
		end
		hum.Died:Once(function()
			local rep, root = MatchService.report, Combatants.root(e)
			local evacuated = e.model:GetAttribute("Evacuated") == true -- medevac não é baixa
			if rep and not evacuated and not MatchService.ended and (e.faction == "US" or e.faction == "VC") then
				local s = if root then Geometry.sectorAt(MapConfig.Sectors, root.Position.X, root.Position.Z) else nil
				AfterAction.casualty(rep, e.faction, s)
				if MatchService.score then
					Capture.casualty(MatchService.score, e.faction) -- atrito: cada morte gasta um reforço
				end
			end
		end)
	end)
	-- reunião avançada, reunião do squad e posições do squad; imagem da carta (decal -> imagem).
	-- require aqui dentro: os dois dependem do SpawnService, que depende deste módulo.
	local FrontService = require(script.Parent:WaitForChild("FrontService")) :: any
	FrontService.start()
	-- contagem do começo (D-122): nascer só no QG e ficar perto dele
	local PreparoService = require(script.Parent:WaitForChild("PreparoService")) :: any
	PreparoService.start()
	local CartaService = require(script.Parent:WaitForChild("CartaService")) :: any
	task.spawn(CartaService.start)
	task.spawn(function()
		while true do
			task.wait(1)
			local st = MatchService.state
			if st and not MatchService.ended and MatchService.inPrep() then
				lastCounts = counts() -- na contagem (D-122): nada se captura, nada sangra, o relógio espera
				if not humanInField() then
					-- ninguém em campo ainda: a contagem espera cheia (bots parados na base)
					MatchService.prepUntil = os.clock() + MatchService.PREP_S
					holding = true
				elseif holding then
					-- o primeiro jogador nasceu: a contagem corre e o relógio da partida começa depois dela
					holding = false
					MatchService.startedAt = MatchService.prepUntil
					MatchService.waveEpoch = MatchService.startedAt
				end
			elseif st and not MatchService.ended then
				-- autoteste no Studio pode simular quem está em cada ponto forte
				local override = MatchService.countsOverride
				lastCounts = if override and RunService:IsStudio() then override() else counts()
				local o = MatchService.offensive
				local events: { Offensive.Event } = if o
					then Offensive.step(o, lastCounts, 1)
					else Capture.step(st, lastCounts, 1) :: any
				local rep = MatchService.report
				for _, ev in events do
					if rep then
						local sp = MatchService.points[ev.sector]
						AfterAction.event(
							rep,
							os.clock() - MatchService.startedAt,
							ev.kind,
							ev.sector,
							ev.team,
							sp and sp.name
						)
					end
					if MatchService.onEvent then
						task.spawn(MatchService.onEvent, ev.kind, ev.sector, (ev :: any).team)
					end
					if ev.kind == "captured" then
						MatchService.capturedAt[ev.sector] = os.clock()
					elseif ev.kind == "advanced" then
						showMarkers() -- a frente andou: o próximo ponto forte aparece
					end
				end
				updateFlags()
				local elapsed = os.clock() - MatchService.startedAt
				-- chuva (no Studio, workspace:SetAttribute("VT65DevRain", 0..1) força a intensidade)
				local dev = if RunService:IsStudio() then workspace:GetAttribute("VT65DevRain") else nil
				local rain = if type(dev) == "number"
					then math.clamp(dev, 0, 1)
					else Weather.intensity(MatchService.shower, elapsed)
				local cur = ReplicatedStorage:GetAttribute("Rain")
				if type(cur) ~= "number" or math.abs(cur - rain) > 0.01 then
					ReplicatedStorage:SetAttribute("Rain", math.floor(rain * 100 + 0.5) / 100)
				end
				local score = MatchService.score
				if score then
					Capture.bleed(score, st, 1) -- atrito: quem tem menos setores sangra reforços
				end
				local w = if o then Offensive.winner(o, elapsed) else Capture.winner(st, elapsed, limitSeconds(), score)
				if w then
					endMatch(w)
				end
			end
			publish()
		end
	end)
end

return MatchService
