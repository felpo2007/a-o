--!strict
-- Squads de bots (D-90; pedido do dono: os bots vão "em grupo, o squad do bot segue um líder, em
-- vez de cada um para um lado"):
--   - até 6 por squad; o líder é o primeiro vivo (o líder de squad, se houver);
--   - o líder pede a rota estratégica (BotWorld: foge do arrozal alagado, usa o dique, a sebe e a
--     mata) e anda por trechos do PathfindingService; os outros seguem o RASTRO dele em coluna (mata,
--     vila, riacho) ou em cunha (aberto), cada um no seu lugar, e olham para os lados andando;
--   - o líder espera quem ficou para trás; quem se perdeu volta pelo caminho;
--   - perto do objetivo o squad se espalha: na defesa, num arco virado para o inimigo; no ataque,
--     dentro do raio de captura;
--   - contato: quem vê avisa (o squad fica sabendo em 1–2 s); no ataque, metade avança de abrigo
--     em abrigo enquanto a outra metade cobre, trocando a cada 6–10 s (lances).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local BotMove = require(ReplicatedStorage.Shared.BotMove)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local BotLocomotion = require(script.Parent.BotLocomotion)
local BotTypes = require(script.Parent.BotTypes)
local BotWorld = require(script.Parent.BotWorld)
local MatchService = require(script.Parent.MatchService)

type Bot = BotTypes.Bot

local BotSquads = {}
local M = 0.28
local S = BotBrain.SQUAD

export type Squad = {
	id: number,
	faction: string,
	members: { Bot },
	leader: Bot?,
	trail: BotMove.Trail,
	formation: string,
	route: BotMove.Path?,
	routeGoal: Vector3?,
	routeAt: number,
	routePending: boolean,
	routeFollow: BotMove.Follow,
	goal: Vector3?,
	sector: number?,
	attack: boolean,
	phase: string, -- "move" | "deploy"
	leaderGait: string,
	bound: number, -- equipe que avança no lance (1 ou 2)
	boundAt: number,
	contact: Vector3?,
	contactAt: number,
	pendingPos: Vector3?,
	pendingAt: number,
	inContact: boolean,
	order: string?, -- cena do Studio
	mech: any, -- BotVehicles: LVTP-5 que leva este squad
	-- 2026-11-12: espera do líder com teto e lances perto do objetivo atacado
	waitSince: number?,
	boundMoving: boolean,
	boundPhaseEnd: number,
}

local squads: { Squad } = {}
local nextId = 0

local function alive(b: Bot): boolean
	local m = b.model
	if not m or b.removed or b.tunnel then
		return false
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not m:GetAttribute("Downed") and hum.SeatPart == nil
end

local function rootOf(b: Bot): BasePart?
	local m = b.model
	return if m then m:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function BotSquads.list(): { Squad }
	return squads
end

-- Entra num squad do lado com vaga (ou cria um)
function BotSquads.assign(bot: Bot)
	BotSquads.remove(bot)
	local sq: Squad? = nil
	for _, s in squads do
		if s.faction == bot.faction and #s.members < S.size then
			sq = s
			break
		end
	end
	if not sq then
		nextId += 1
		local new: Squad = {
			id = nextId,
			faction = bot.faction,
			members = {},
			leader = nil,
			trail = BotMove.newTrail(S.trailStepM / M, S.trailMaxM / M),
			formation = "file",
			route = nil,
			routeGoal = nil,
			routeAt = -math.huge,
			routePending = false,
			routeFollow = BotMove.newFollow(),
			goal = nil,
			sector = nil,
			attack = true,
			phase = "move",
			leaderGait = "jog",
			bound = 1,
			boundAt = 0,
			contact = nil,
			contactAt = -math.huge,
			pendingPos = nil,
			pendingAt = 0,
			inContact = false,
			order = nil,
			mech = nil,
			waitSince = nil,
			boundMoving = true,
			boundPhaseEnd = 0,
		}
		table.insert(squads, new)
		sq = new
	end
	local s = sq :: Squad
	table.insert(s.members, bot)
	bot.squad = s
	bot.team = (#s.members % 2) + 1
end

function BotSquads.remove(bot: Bot)
	local s = bot.squad :: Squad?
	if not s then
		return
	end
	local i = table.find(s.members, bot)
	if i then
		table.remove(s.members, i)
	end
	if s.leader == bot then
		s.leader = nil
	end
	bot.squad = nil
	if #s.members == 0 then
		local k = table.find(squads, s)
		if k then
			table.remove(squads, k)
		end
	end
end

function BotSquads.isLeader(bot: Bot): boolean
	local s = bot.squad :: Squad?
	return s ~= nil and s.leader == bot
end

-- Rumo (yaw do Roblox) do objetivo para o inimigo que ataca: reunião avançada dele mais perto, ou o
-- ponto forte dele mais perto, ou o QG.
local function threatAxis(faction: string, point: Vector3): number
	local enemy = if faction == "US" then "VC" else "US"
	local best: Vector3? = nil
	local bestD = math.huge
	local ok, FrontService = pcall(function(): any
		return require(script.Parent.FrontService) :: any
	end)
	if ok and FrontService and FrontService.forwardPoints then
		local okP, pts = pcall(FrontService.forwardPoints, enemy)
		for _, p in if okP and type(pts) == "table" then pts else {} do
			local v = Vector3.new(p.x, 0, p.z)
			local d = flat(v, point)
			if d < bestD then
				best, bestD = v, d
			end
		end
	end
	if not best then
		for s, sp in MatchService.points do
			if MatchService.ownerOf(s) == enemy then
				local v = Vector3.new(sp.x, 0, sp.z)
				local d = flat(v, point)
				if d > 1 and d < bestD then
					best, bestD = v, d
				end
			end
		end
	end
	local hq = MapConfig.HQ[enemy]
	local t = best or Vector3.new(hq.x, 0, hq.z)
	return BotMove.yawTo(t.X - point.X, t.Z - point.Z)
end

BotSquads.threatYaw = threatAxis

local function pickLeader(s: Squad): Bot?
	local best: Bot? = nil
	for _, b in s.members do
		if alive(b) then
			if b.role == "squad_leader" then
				return b
			end
			best = best or b
		end
	end
	return best
end

-- Uma vez a cada ~0,5 s: líder, rastro, formação, objetivo, fase, aviso de contato e lances.
function BotSquads.tick(now: number, objective: (string) -> (Vector3?, number?))
	for idx, s in squads do
		local leader = pickLeader(s)
		if leader ~= s.leader then
			s.leader = leader
			BotMove.trailClear(s.trail)
			s.route = nil
			s.routeGoal = nil
		end
		-- lugar de cada um (quem entrou no squad ou renasceu ganha o seu)
		local k = 1
		for _, b in s.members do
			if b == leader then
				b.slot = 0
			else
				b.slot = k
				k += 1
			end
		end
		local lr = if leader then rootOf(leader) else nil
		if lr then
			BotMove.trailPush(s.trail, lr.Position.X, lr.Position.Z)
			s.formation = BotMove.formationFor(BotWorld.isOpen(lr.Position))
		end
		-- objetivo do squad: o ponto forte, chegando por um rumo próprio (squads não se empilham)
		local point, sector = objective(s.faction)
		if point and sector then
			if s.sector ~= sector or not s.goal then
				s.sector = sector
				local a = (idx * 2.399) % (2 * math.pi) -- ângulo de ouro: squads em volta
				local r = BotBrain.C.objectiveSpreadM * 0.6 / M
				s.goal = point + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				s.route = nil
			end
			s.attack = MatchService.ownerOf(sector) ~= s.faction
			if lr then
				local d = flat(lr.Position, point) * M
				if s.phase == "move" and d < S.deployM then
					s.phase = "deploy"
				elseif s.phase == "deploy" and d > S.deployM * 1.8 then
					s.phase = "move"
				end
			end
		end
		-- aviso de contato chegou ao squad
		local pp = s.pendingPos
		if pp and now >= s.pendingAt then
			s.contact, s.contactAt = pp, now
			s.pendingPos = nil
		end
		local any = false
		for _, b in s.members do
			if b.inCombat and alive(b) then
				any = true
				break
			end
		end
		s.inContact = any
		if any and now >= s.boundAt then
			s.bound = if s.bound == 1 then 2 else 1
			s.boundAt = now + S.boundS[1] + (S.boundS[2] - S.boundS[1]) * math.random()
		end
	end
end

-- Quem viu o inimigo avisa o squad (chega em calloutS)
function BotSquads.callout(bot: Bot, pos: Vector3, now: number)
	local s = bot.squad :: Squad?
	if not s or s.pendingPos then
		return
	end
	local c = bot.diff.calloutS
	s.pendingPos = pos
	s.pendingAt = now + c[1] + (c[2] - c[1]) * bot.rng:next()
end

-- Contato avisado pelo squad (perto o bastante e recente)
function BotSquads.sharedThreat(bot: Bot, now: number): Vector3?
	local s = bot.squad :: Squad?
	local r = rootOf(bot)
	local c = if s then s.contact else nil
	if not (s and c and r) or now - s.contactAt > bot.style.forgetS then
		return nil
	end
	if flat(r.Position, c) * M > S.contactShareM then
		return nil
	end
	return c
end

-- Lances: no ataque com contato, a equipe da vez avança; a outra cobre.
function BotSquads.advancing(bot: Bot): boolean
	local s = bot.squad :: Squad?
	return s ~= nil and s.attack and s.inContact and bot.team == s.bound
end

function BotSquads.covering(bot: Bot): boolean
	local s = bot.squad :: Squad?
	return s ~= nil and s.attack and s.inContact and bot.team ~= s.bound
end

function BotSquads.phase(bot: Bot): string
	local s = bot.squad :: Squad?
	return if s then s.phase else "deploy"
end

-- Lugar de cada um perto do objetivo (studs): defesa no arco virado para o inimigo; ataque dentro
-- do raio de captura, do lado por onde o squad chegou.
function BotSquads.deployGoal(bot: Bot, point: Vector3): Vector3
	local s = bot.squad :: Squad?
	local count = if s then #s.members else 1
	local idx = (bot.slot or 0) + 1
	if s and not s.attack then
		local axis = threatAxis(bot.faction, point)
		local dx, dz = BotMove.defendSlot(idx, count, axis, ((bot.id * 0.618) % 1))
		return point + Vector3.new(dx, 0, dz)
	end
	local g = if s then s.goal else nil
	local from = g or point
	local axis = BotMove.yawTo(from.X - point.X, from.Z - point.Z)
	local dx, dz = BotMove.defendSlot(idx, count, axis, 0)
	local k = (MapConfig.CaptureRadiusStuds * 0.55) / math.max(math.sqrt(dx * dx + dz * dz), 1)
	return point + Vector3.new(dx * k, 0, dz * k)
end

-- Quanto o mais atrasado está do seu lugar (m)
local function tailLag(s: Squad, lr: BasePart): number
	local worst = 0
	for _, b in s.members do
		if b ~= s.leader and alive(b) then
			local r = rootOf(b)
			if r then
				local back, side = BotMove.slot(s.formation, b.slot)
				local x, z = BotMove.trailBehind(s.trail, lr.Position.X, lr.Position.Z, back / M)
				local d = flat(r.Position, Vector3.new(x, 0, z)) * M - math.abs(side)
				if d < S.regroupM then
					worst = math.max(worst, d)
				end
			end
		end
	end
	return worst
end

-- Líder: rota estratégica até o objetivo do squad, em trechos. Devolve o passo usado.
function BotSquads.lead(bot: Bot, root: BasePart, now: number, threatNear: boolean): string
	local s = bot.squad :: Squad?
	local goal = if s then s.goal else bot.goal
	if not (s and goal) then
		return "idle"
	end
	local pos = root.Position
	local distM = flat(pos, goal) * M
	-- rota estratégica: pede de novo se o objetivo mudou, se é velha ou se o líder saiu dela
	-- as pernas desistiram (preso, sem caminho): rota estratégica nova já
	if BotLocomotion.status(bot) == "failed" then
		s.route = nil
		s.routeAt = -math.huge
	end
	local route = s.route
	local off = 0
	if route then
		local _, seg, d = BotMove.project(route, pos.X, pos.Z, s.routeFollow.seg)
		s.routeFollow.seg = seg
		off = d * M
	end
	local rg = s.routeGoal
	local stale = not route or not rg or flat(rg, goal) > 20 / M or now - s.routeAt > S.routeEveryS or off > S.offRouteM
	if stale and not s.routePending and BotWorld.ready then
		s.routePending = true
		s.routeAt = now
		local sq = s
		local want = goal
		BotWorld.route("squad" .. s.id, "infantry", nil, pos, want, function(pts: { Vector3 }?, _ok: boolean)
			sq.routePending = false
			if pts and #pts >= 2 then
				local list: { BotMove.Point } = {}
				for _, p in pts do
					table.insert(list, { x = p.X, z = p.Z, y = p.Y })
				end
				sq.route = BotMove.path(list)
				sq.routeGoal = want
				sq.routeFollow = BotMove.newFollow()
			end
		end)
	end
	-- passo: cauteloso perto do objetivo ou do inimigo; corre no aberto com ameaça perto; anda se o
	-- squad ficou para trás e espera se ficou muito
	local lag = tailLag(s, root)
	local gait = "jog"
	if threatNear and BotWorld.isOpen(pos) then
		gait = "sprint"
	elseif distM < BotBrain.MOVE.walkCalmM or threatNear then
		gait = "walk"
	end
	if lag > S.leaderWaitM then
		-- 2026-11-12: espera no máximo leaderWaitMaxS; depois segue andando (quem ficou alcança)
		s.waitSince = s.waitSince or now
		if now - (s.waitSince :: number) < S.leaderWaitMaxS then
			s.leaderGait = "wait"
			BotLocomotion.stop(bot, nil)
			return "wait"
		end
		gait = "walk"
	else
		s.waitSince = nil
		if lag > S.leaderSlowM and gait ~= "sprint" then
			gait = "walk"
		end
	end
	-- 2026-11-12: perto do objetivo atacado e com contato recente, vai em lances: anda boundS, para
	-- boundPauseS (os outros param junto, olhando para fora); fora disso, segue direto
	if BotBrain.squadBounds(s.attack, distM, now - s.contactAt) then
		if now >= s.boundPhaseEnd then
			s.boundMoving = not s.boundMoving
			local r = if s.boundMoving then S.boundS else S.boundPauseS
			s.boundPhaseEnd = now + r[1] + (r[2] - r[1]) * math.random()
		end
		if not s.boundMoving then
			s.leaderGait = "wait"
			BotLocomotion.stop(bot, goal)
			return "wait"
		end
		if gait == "walk" and lag <= S.leaderSlowM then
			gait = "jog" -- no lance, trota
		end
	else
		s.boundMoving, s.boundPhaseEnd = true, 0
	end
	s.leaderGait = gait
	-- trecho: até legM à frente na rota (ou direto ao objetivo sem rota)
	local r = s.route
	local dest = goal
	local final = true
	local legStuds = BotBrain.MOVE.legM / M
	if r then
		local sNow = BotMove.project(r, pos.X, pos.Z, s.routeFollow.seg)
		local ahead = sNow + legStuds
		if ahead < r.length then
			local x, z, y = BotMove.at(r, ahead)
			dest = Vector3.new(x, y, z)
			final = false
		end
	elseif flat(pos, goal) > legStuds then
		-- sem rota ainda (mapa montando): trecho curto na direção do objetivo, nunca 1 km de uma vez
		local dir = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z).Unit
		dest = pos + dir * legStuds
		final = false
	end
	local cur = BotLocomotion.dest(bot)
	local need = cur == nil
		or BotLocomotion.status(bot) ~= "moving"
		or (flat(cur, dest) > 12 / M and BotLocomotion.left(bot) < BotBrain.MOVE.prefetchM)
		or (final and flat(cur, dest) > 3 / M)
	if need then
		BotLocomotion.go(bot, dest, gait, { final = final, keep = true, tolerance = 4 / M })
	else
		-- só o passo
		local st = bot.loco
		if st then
			st.gait = gait
		end
	end
	return gait
end

-- Seguidor: lugar no rastro do líder (coluna ou cunha). Devolve false se não há líder por perto
-- (o BotService decide sozinho).
local sideCheck: { [Bot]: { at: number, blocked: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

function BotSquads.setIgnore(list: { Instance })
	rayParams.FilterDescendantsInstances = list
end

function BotSquads.follow(bot: Bot, root: BasePart, now: number): boolean
	local s = bot.squad :: Squad?
	local leader = if s then s.leader else nil
	if not (s and leader and leader ~= bot and alive(leader)) then
		return false
	end
	local lr = rootOf(leader)
	if not lr then
		return false
	end
	local pos = root.Position
	local toLeader = flat(pos, lr.Position) * M
	if toLeader > S.regroupM * 2.5 then
		return false -- longe demais: vai sozinho para o objetivo
	end
	local back, side = BotMove.slot(s.formation, bot.slot)
	local x, z, dx, dz = BotMove.trailBehind(s.trail, lr.Position.X, lr.Position.Z, back / M)
	local base = Vector3.new(x, pos.Y, z)
	local target = base
	if side ~= 0 then
		local rx, rz = -dz, dx -- direita de quem marcha
		local cand = base + Vector3.new(rx * side / M, 0, rz * side / M)
		-- sebe ou parede entre o rastro e o lugar da cunha: fica no rastro (1 raio a cada 1,5 s)
		local chk = sideCheck[bot]
		local blocked: boolean
		if not chk or now >= chk.at then
			local hit = workspace:Raycast(
				base + Vector3.new(0, 1.5, 0),
				Vector3.new(cand.X - base.X, 0, cand.Z - base.Z),
				rayParams
			)
			blocked = hit ~= nil
			sideCheck[bot] = { at = now + 1.5, blocked = blocked }
		else
			blocked = chk.blocked
		end
		if not blocked then
			target = cand
		end
	end
	local distM = flat(pos, target) * M
	local leaderStopped = s.leaderGait == "wait" or BotLocomotion.speed(leader) < 0.3
	-- parado no lugar: olha para fora (cada um um setor; o último olha para trás)
	local march = Vector3.new(dx, 0, dz)
	local lookYaw = BotMove.yawTo(march.X, march.Z)
	local sector = if bot.slot == #s.members - 1 then math.pi else (if bot.slot % 2 == 1 then -1 else 1) * math.rad(60)
	if leaderStopped and distM < 1.5 then
		local a = lookYaw + sector
		BotLocomotion.stop(bot, pos + Vector3.new(-math.sin(a), 0, -math.cos(a)) * 20)
		return true
	end
	local behind = if toLeader > S.regroupM then toLeader else distM
	local cautious = s.leaderGait == "walk"
	local gait = BotBrain.gait({
		stance = "stand",
		distM = distM,
		urgent = s.leaderGait == "sprint",
		cautious = cautious,
		aiming = false,
		behindM = behind,
		legImpaired = bot.model ~= nil and (bot.model :: Model):GetAttribute("LegImpaired") == true,
	})
	-- andando cauteloso: olha para os lados de tempos em tempos (cone de visão, D-90)
	local face: Vector3? = nil
	if cautious and gait == "walk" then
		if now >= bot.scanAt then
			bot.scanAt = now
				+ BotBrain.MOVE.scanS[1]
				+ (BotBrain.MOVE.scanS[2] - BotBrain.MOVE.scanS[1]) * bot.rng:next()
			bot.scanSide = if bot.scanSide == 0 then (if bot.slot % 2 == 1 then 1 else -1) else -bot.scanSide
		end
		local a = lookYaw + bot.scanSide * math.rad(BotBrain.MOVE.scanDeg)
		face = pos + Vector3.new(-math.sin(a), 0, -math.cos(a)) * 20
	end
	if toLeader > S.regroupM then
		-- perdido: volta pelo caminho até o líder
		BotLocomotion.goFar(bot, lr.Position, gait, { tolerance = 6 / M })
	else
		BotLocomotion.go(bot, target, gait, { direct = distM < 15, tolerance = 1.2 / M, face = face })
	end
	return true
end

-- Gancho do Studio: força a ordem de um squad (cena)
function BotSquads.setOrder(s: Squad, order: string?)
	s.order = order
end

return BotSquads
