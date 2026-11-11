--!strict
-- Partida Warfare/Offensive/Skirmish: sorteio dos pontos fortes, captura, tempo e vitória (Parte 4).
-- Servidor público alterna Warfare e Offensive; o privado fica no modo escolhido pelo dono.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AfterAction = require(ReplicatedStorage.Shared.AfterAction)
local Capture = require(ReplicatedStorage.Shared.Capture)
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
	MatchService.points = {}
	for s, list in bySector do
		local sp = list[1 + math.floor(rng:next() * #list)]
		MatchService.points[s] = { sector = s, name = sp.name, x = sp.x, z = sp.z, real = sp.real }
	end
	MatchService.offensive = nil
	if MatchService.mode == "Offensive" then
		local o = Offensive.new(5)
		MatchService.offensive = o
		MatchService.state = o.capture
		MatchService.initialOwner = table.clone(o.capture.owner)
	else
		local initial = table.clone(MapConfig.InitialOwner)
		local active = { true, true, true, true, true }
		if MatchService.mode == "Skirmish" then
			active = { false, false, true, false, false }
		end
		MatchService.state = Capture.new(initial, active)
		MatchService.initialOwner = initial
	end
	MatchService.capturedAt = {}
	MatchService.startedAt = os.clock()
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

local function counts(): { { US: number, VC: number } }
	local out = {}
	local r2 = MapConfig.CaptureRadiusStuds ^ 2
	for s = 1, 5 do
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
	Net.event("Match_State"):FireAllClients({
		mode = MatchService.mode,
		owner = st.owner,
		progress = st.progress,
		active = st.active,
		points = pts,
		timeLeft = math.max(0, limitSeconds() - (os.clock() - MatchService.startedAt)),
		ended = MatchService.ended,
		front = if MatchService.offensive then MatchService.offensive.front else nil,
		-- relatório pós-ação: só no fim (texto pronto, ~70 linhas no máximo)
		report = if MatchService.ended and MatchService.report then AfterAction.lines(MatchService.report) else nil,
	})
end

local function endMatch(winner: string)
	MatchService.ended = true
	local st = MatchService.state
	if MatchService.report and st then
		AfterAction.finish(MatchService.report, winner, os.clock() - MatchService.startedAt, st.owner)
	end
	ReplicatedStorage:SetAttribute("LastWinner", winner)
	publish()
	task.delay(30, function()
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
			end
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local st = MatchService.state
			if st and not MatchService.ended then
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
				local w = if o then Offensive.winner(o, elapsed) else Capture.winner(st, elapsed, limitSeconds())
				if w then
					endMatch(w)
				end
			end
			publish()
		end
	end)
end

return MatchService
