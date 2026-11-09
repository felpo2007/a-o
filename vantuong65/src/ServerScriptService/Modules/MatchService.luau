--!strict
-- Partida Warfare/Skirmish: sorteio dos pontos fortes, captura, tempo e vitória (Parte 4).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Capture = require(ReplicatedStorage.Shared.Capture)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)

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
local pendingMode: string? = nil

local function limitSeconds(): number
	return (if MatchService.mode == "Skirmish" then Capture.C.skirmishMinutes else Capture.C.warfareMinutes) * 60
end

function MatchService.newMatch(mode: string?)
	MatchService.mode = mode or pendingMode or MatchService.mode
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
	local initial = table.clone(MapConfig.InitialOwner)
	local active = { true, true, true, true, true }
	if MatchService.mode == "Skirmish" then
		active = { false, false, true, false, false }
	end
	MatchService.state = Capture.new(initial, active)
	MatchService.initialOwner = initial
	MatchService.capturedAt = {}
	MatchService.startedAt = os.clock()
	MatchService.waveEpoch = MatchService.startedAt
	MatchService.ended = false
	-- marcadores do greybox: mostra só o ponto sorteado de cada setor
	local folder = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild("Strongpoints")
	if folder then
		for _, p in folder:GetChildren() do
			local chosen = MatchService.points[p:GetAttribute("Sector")]
			local on = chosen ~= nil and chosen.name == p.Name and active[chosen.sector]
			p.Transparency = if on then 0.6 else 1
		end
	end
	ReplicatedStorage:SetAttribute("MatchMode", MatchService.mode)
end

function MatchService.requestMode(mode: string)
	pendingMode = mode -- vale para a próxima partida (ou já, se ninguém entrou)
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
	for _, player in Players:GetPlayers() do
		local faction = player:GetAttribute("Faction")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if
			(faction == "US" or faction == "VC")
			and root
			and hum
			and hum.Health > 0
			and not player:GetAttribute("Downed")
		then
			for s, sp in MatchService.points do
				local dx, dz = root.Position.X - sp.x, root.Position.Z - sp.z
				if dx * dx + dz * dz <= r2 then
					local c = out[s] :: any
					c[faction] += 1
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
	})
end

local function endMatch(winner: string)
	MatchService.ended = true
	ReplicatedStorage:SetAttribute("LastWinner", winner)
	publish()
	task.delay(30, function()
		MatchService.newMatch()
	end)
end

function MatchService.start()
	MatchService.newMatch("Warfare")
	task.spawn(function()
		while true do
			task.wait(1)
			local st = MatchService.state
			if st and not MatchService.ended then
				lastCounts = counts()
				for _, ev in Capture.step(st, lastCounts, 1) do
					if ev.kind == "captured" then
						MatchService.capturedAt[ev.sector] = os.clock()
					end
				end
				local w = Capture.winner(st, os.clock() - MatchService.startedAt, limitSeconds())
				if w then
					endMatch(w)
				end
			end
			publish()
		end
	end)
end

return MatchService
