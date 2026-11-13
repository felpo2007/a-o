--!strict
-- Métrica do dono (2026-11-12): "nos primeiros 3 minutos de gameplay, já tenha tido pelo menos uma
-- troca de tiros". Por jogador e por partida: o tempo da primeira entrada em campo até a primeira
-- troca de tiros, que é qualquer um destes, a até 150 m (Eventos.C.contactM):
--   - ele atirou e um inimigo de pé estava a até 8° da linha do tiro;
--   - um inimigo atirou nele do mesmo jeito (levou tiro, mesmo sem acertar);
--   - ele acertou ou foi acertado por um inimigo.
-- Registro: atributo "PrimeiroContatoS" no Player, linha "[VT65 METRICA]" no Output e a métrica da
-- partida em atributos do ReplicatedStorage (VT65ContatoN, VT65ContatoMedianaS, VT65ContatoMedioS,
-- VT65ContatoPiorS, VT65ContatoAte3minPct, VT65ContatoSemContato), atualizados a cada 5 s; resumo no
-- Output ao fim de cada partida. Bots não entram na conta.
-- Os ganchos envolvem CombatService.fire e MedicalService.hit chamadas pela tabela, como o
-- SpawnService e o BotService já fazem: só leem, o tiro e o dano seguem iguais.
-- Studio: workspace:SetAttribute("VT65DevContato", true) imprime o resumo agora.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Eventos = require(ReplicatedStorage.Shared.Eventos)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local CombatService = require(script.Parent.CombatService)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)

local ContatoService = {}
local M = MapConfig.STUD_M
local C = Eventos.C

local firstIn: { [Player]: number } = {} -- primeira entrada em campo nesta partida (os.clock)
local done: { [Player]: boolean } = {}
local metric = Eventos.newMetric()
local matchKey = -1
local shooting: Model? = nil -- quem está atirando agora (o dano sai dentro do CombatService.fire)

local function lateCount(now: number): number
	local n = 0
	for p, t in firstIn do
		if not done[p] and now - t > C.goalS then
			n += 1
		end
	end
	return n
end

local function publish()
	local late = lateCount(os.clock())
	local s = Eventos.summary(metric, late)
	ReplicatedStorage:SetAttribute("VT65ContatoN", s.n)
	ReplicatedStorage:SetAttribute("VT65ContatoMedianaS", math.floor(s.median + 0.5))
	ReplicatedStorage:SetAttribute("VT65ContatoMedioS", math.floor(s.mean + 0.5))
	ReplicatedStorage:SetAttribute("VT65ContatoPiorS", math.floor(s.worst + 0.5))
	ReplicatedStorage:SetAttribute("VT65ContatoAte3minPct", math.floor(s.within * 100 + 0.5))
	ReplicatedStorage:SetAttribute("VT65ContatoSemContato", late)
end

local function report(label: string)
	local late = lateCount(os.clock())
	local s = Eventos.summary(metric, late)
	print(
		string.format(
			"[VT65 METRICA] %s: %d jogador(es) com troca de tiros, mediana %.0f s, média %.0f s, pior %.0f s; "
				.. "%d%% em até %d s; %d em campo há mais de %d s sem troca",
			label,
			s.n,
			s.median,
			s.mean,
			s.worst,
			math.floor(s.within * 100 + 0.5),
			C.goalS,
			late,
			C.goalS
		)
	)
end

local function resetIfNewMatch()
	if MatchService.startedAt == matchKey then
		return
	end
	if matchKey >= 0 then
		report("fim da partida")
	end
	matchKey = MatchService.startedAt
	table.clear(firstIn)
	table.clear(done)
	metric = Eventos.newMetric()
	-- quem já está em campo quando a partida começa conta daqui
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and p:GetAttribute("Faction") then
			firstIn[p] = now
		end
		p:SetAttribute("PrimeiroContatoS", nil)
	end
	publish()
end

local function engaged(p: Player?, why: string, dM: number)
	if not p or done[p] then
		return
	end
	resetIfNewMatch()
	local t0 = firstIn[p]
	if not t0 then
		return
	end
	done[p] = true
	local s = os.clock() - t0
	Eventos.addContact(metric, s)
	p:SetAttribute("PrimeiroContatoS", math.floor(s * 10 + 0.5) / 10)
	print(string.format("[VT65 METRICA] %s: primeira troca de tiros em %.0f s (%s, a %.0f m)", p.Name, s, why, dM))
	publish()
end

-- tiro validado: quem atirou num inimigo e quem estava na linha do tiro
local function onShot(shooter: Model, origin: Vector3, dir: Vector3)
	local se = Combatants.get(shooter)
	if not se then
		return
	end
	for _, e in Combatants.list() do
		local r = Combatants.root(e)
		if e.faction ~= se.faction and r and Combatants.active(e) then
			local pos = r.Position
			if Eventos.inCone(origin.X, origin.Z, dir.X, dir.Z, pos.X, pos.Z, C.contactM, C.coneDeg, M) then
				local dM = Vector3.new(pos.X - origin.X, 0, pos.Z - origin.Z).Magnitude * M
				engaged(se.player, "atirou num inimigo", dM)
				engaged(e.player, "levou tiro", dM)
			end
		end
	end
end

-- dano dentro de um tiro: acertou e foi acertado
local function onHit(victim: Model)
	local shooter = shooting
	local ve, se = Combatants.get(victim), Combatants.get(shooter)
	if not (ve and se and shooter) or ve.faction == se.faction then
		return
	end
	local a, b = Combatants.root(ve), Combatants.root(se)
	if not (a and b) then
		return
	end
	local dM = (a.Position - b.Position).Magnitude * M
	if dM <= C.contactM then
		engaged(ve.player, "foi atingido", dM)
		engaged(se.player, "acertou um inimigo", dM)
	end
end

local function hook()
	local fire0 = CombatService.fire
	CombatService.fire = function(
		shooter: Model,
		weaponId: string,
		origin: Vector3,
		dir: Vector3,
		seed: number,
		exceptPlayer: Player?
	)
		local prev = shooting
		shooting = shooter
		local ok, err = pcall(function(): any
			fire0(shooter, weaponId, origin, dir, seed, exceptPlayer)
			return nil
		end)
		shooting = prev
		if not ok then
			error(err, 0) -- o tiro falhou de verdade: não engole o erro
		end
		pcall(onShot, shooter, origin, dir)
	end
	local hit0 = MedicalService.hit
	MedicalService.hit = function(victim: Model, zone: string, energyJ: number, roll: number, by: Player?)
		hit0(victim, zone, energyJ, roll, by)
		if shooting then
			pcall(onHit, victim)
		end
	end
end

local function watch(p: Player)
	p.CharacterAdded:Connect(function()
		resetIfNewMatch()
		if not firstIn[p] and p:GetAttribute("Faction") then
			firstIn[p] = os.clock() -- primeira entrada em campo desta partida
		end
	end)
end

function ContatoService.start()
	hook()
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		firstIn[p] = nil
		done[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			pcall(function(): any
				resetIfNewMatch()
				publish()
				return nil
			end)
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevContato"):Connect(function()
			if workspace:GetAttribute("VT65DevContato") then
				report("agora")
			end
		end)
	end
end

return ContatoService
