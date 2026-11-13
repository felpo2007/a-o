--!strict
-- Blindados com tripulação de bots (D-90; pedido do dono: "faça os bots entenderem como utilizar os
-- veículos"). Regra do dono (2026-11-11): só os EUA têm M48A3, Ontos, LVTP-5 e UH-34D; o carro do
-- VC vem depois e cai aqui sozinho (a escolha é por lado do veículo e a direção é genérica,
-- Shared/BotDriver). Bot não pilota helicóptero (fica documentado na D-90).
--   - tripulação: motorista e atirador, tirados dos bots do lado (um blindado a partir de 8 bots,
--     mais um a cada 5: BotBrain.crewCount). Nascem no QG, vão até o depósito e embarcam;
--   - motorista: rota de lagarta (BotWorld: foge do arrozal e da mata fechada quando pode, nunca
--     passa por casa nem sebe de bambu; o Ontos não entra no riacho; o LVTP-5 boia) e a mesma
--     física do jogador (VehicleService); para a ~200 m do objetivo atrás de sebe, casa ou crista;
--   - atirador: procura alvo do reparo, gira a torre na velocidade da ficha e atira: coaxial ou
--     M60 em rajadas, canhão (HE) em grupo ou em quem está atrás de parede;
--   - LVTP-5: leva um squad de bots do depósito até ~180 m do objetivo, desembarca e volta.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local BotDriver = require(ReplicatedStorage.Shared.BotDriver)
local BotMove = require(ReplicatedStorage.Shared.BotMove)
local BotNav = require(ReplicatedStorage.Shared.BotNav)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local BotLocomotion = require(script.Parent.BotLocomotion)
local BotSquads = require(script.Parent.BotSquads)
local BotTypes = require(script.Parent.BotTypes)
local BotWorld = require(script.Parent.BotWorld)
local Combatants = require(script.Parent.Combatants)
local MatchService = require(script.Parent.MatchService)
local VehicleService = require(script.Parent.VehicleService)

type Bot = BotTypes.Bot

local BotVehicles = {}
local M = 0.28
local V = BotBrain.VEHICLE

export type Crew = {
	id: number,
	vehicle: Model,
	spec: string,
	kind: string,
	faction: string,
	members: { [string]: Bot }, -- assento -> bot
	state: string, -- "board" | "go" | "hold" | "load" | "drop" | "back"
	stateAt: number,
	route: BotMove.Path?,
	routeFollow: BotMove.Follow,
	routeGoal: Vector3?,
	routePending: boolean,
	routeAt: number,
	dest: Vector3?,
	depot: Vector3,
	exit: Vector3?, -- frente da boca da baia (VehicleService.depotExit); nil = depósito aberto
	leftDepot: boolean, -- já saiu da baia em linha reta (só então pede rota)
	sector: number?,
	forceSector: number?, -- gancho do Studio
	stuckT: number,
	stuckN: number, -- ré seguidas no mesmo lugar
	stuckAt: Vector3?,
	reverseUntil: number,
	turret: number,
	target: Model?,
	targetSince: number,
	nextShot: number,
	firing: boolean,
	mech: any, -- squad levado (LVTP-5)
	logAt: number,
}

local crews: { Crew } = {}
local nextId = 0

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function chassisOf(vehicle: Model): BasePart?
	return vehicle:FindFirstChild("Chassis") :: BasePart?
end

function BotVehicles.list(): { Crew }
	return crews
end

local function crewOf(bot: Bot): Crew?
	local c = bot.crew
	return if c and c.crew then c.crew :: Crew else nil
end

local function dissolve(c: Crew)
	for _, b in c.members do
		b.crew = nil
		local m = b.model
		local hum = m and m:FindFirstChildOfClass("Humanoid")
		if m and hum and hum.SeatPart then
			VehicleService.botLeave(m)
		end
		BotSquads.assign(b)
	end
	local sq = c.mech
	if sq then
		for _, b in sq.members do
			if b.crew and b.crew.crew == c then
				b.crew = nil
			end
		end
		sq.mech = nil
	end
	local i = table.find(crews, c)
	if i then
		table.remove(crews, i)
	end
end

-- Ordem de preferência: a da tabela e, depois, qualquer outro veículo de chão do lado
local function rank(spec: string): number
	local i = table.find(V.order, spec)
	return i or (#V.order + 1)
end

local function groundVehicles(faction: string): { Model }
	local out: { Model } = {}
	for _, v in VehicleService.vehicles() do
		local kind = v:GetAttribute("Kind")
		if v:GetAttribute("Faction") == faction and kind ~= "heli" and VehicleService.seat(v, "driver") then
			table.insert(out, v)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = rank(tostring(a:GetAttribute("Spec"))), rank(tostring(b:GetAttribute("Spec")))
		if ra ~= rb then
			return ra < rb
		end
		return (a:GetAttribute("VehicleId") :: number) < (b:GetAttribute("VehicleId") :: number)
	end)
	return out
end

local function newCrew(vehicle: Model, faction: string): Crew
	nextId += 1
	local ch = chassisOf(vehicle)
	local exit, spot = VehicleService.depotExit(vehicle)
	-- ainda na vaga da baia (a menos de 4 m dela): sai reto até a frente da boca
	local inBay = exit ~= nil and spot ~= nil and ch ~= nil and flat(ch.Position, spot) * M < 4
	return {
		id = nextId,
		vehicle = vehicle,
		spec = tostring(vehicle:GetAttribute("Spec")),
		kind = tostring(vehicle:GetAttribute("Kind")),
		faction = faction,
		members = {},
		state = "board",
		stateAt = os.clock(),
		route = nil,
		routeFollow = BotMove.newFollow(),
		routeGoal = nil,
		routePending = false,
		routeAt = -math.huge,
		dest = nil,
		depot = if ch then ch.Position else Vector3.zero,
		exit = exit,
		leftDepot = not inBay,
		sector = nil,
		forceSector = nil,
		stuckT = 0,
		stuckN = 0,
		stuckAt = nil,
		reverseUntil = 0,
		turret = 0,
		target = nil,
		targetSince = 0,
		nextShot = 0,
		firing = false,
		mech = nil,
		logAt = 0,
	}
end

-- Bots que podem virar tripulação: sem tripulação, sem ordem do Studio, de preferência mortos
-- (renascem já no QG) ou fora de combate, nunca o líder do squad
local function pickBots(bots: { Bot }, faction: string, n: number): { Bot }
	local cands: { Bot } = {}
	for _, b in bots do
		if b.faction == faction and not b.removed and not b.crew and b.order == nil and b.role ~= "squad_leader" then
			table.insert(cands, b)
		end
	end
	table.sort(cands, function(a, b)
		local sa = (if a.model then 1 else 0) + (if a.inCombat then 2 else 0)
		local sb = (if b.model then 1 else 0) + (if b.inCombat then 2 else 0)
		if sa ~= sb then
			return sa < sb
		end
		return a.id > b.id
	end)
	local out: { Bot } = {}
	for i = 1, math.min(n, #cands) do
		out[i] = cands[i]
	end
	return out
end

-- Monta e desfaz tripulações (a cada ~2 s)
function BotVehicles.assign(bots: { Bot }, forced: Model?)
	for i = #crews, 1, -1 do
		local c = crews[i]
		local gone = false
		for _, b in c.members do
			if b.removed then
				gone = true -- saiu bot (entrou gente): monta de novo com quem ficou
			end
		end
		if gone or not c.vehicle.Parent or c.vehicle:GetAttribute("Destroyed") then
			dissolve(c)
		end
	end
	for _, faction in { "US", "VC" } do
		local list = groundVehicles(faction)
		local mine = 0
		local total = 0
		for _, c in crews do
			if c.faction == faction then
				mine += 1
			end
		end
		for _, b in bots do
			if b.faction == faction and not b.removed then
				total += 1
			end
		end
		local want = BotBrain.crewCount(total, #list)
		if forced and forced:GetAttribute("Faction") == faction then
			want = math.max(want, mine + 1)
		end
		-- sobrou tripulação (saiu bot): desfaz a última
		while mine > want and #crews > 0 do
			for i = #crews, 1, -1 do
				if crews[i].faction == faction and crews[i].forceSector == nil then
					dissolve(crews[i])
					break
				end
			end
			mine -= 1
		end
		if mine < want then
			local order = list
			if forced then
				order = { forced }
				for _, v in list do
					if v ~= forced then
						table.insert(order, v)
					end
				end
			end
			for _, v in order do
				if mine >= want then
					break
				end
				local taken = false
				for _, c in crews do
					if c.vehicle == v then
						taken = true
					end
				end
				if not taken then
					local seats: { string } = {}
					for _, sid in V.crewSeats do
						if VehicleService.seat(v, sid) then
							table.insert(seats, sid)
						end
					end
					local picked = pickBots(bots, faction, #seats)
					if #picked >= 1 then
						local c = newCrew(v, faction)
						for k, b in picked do
							local sid = seats[k]
							c.members[sid] = b
							BotSquads.remove(b)
							b.crew = { crew = c, seat = sid }
						end
						table.insert(crews, c)
						mine += 1
						print(string.format("[VT65] bots: tripulação %d no %s (%d bots)", c.id, c.spec, #picked))
					end
				end
			end
		end
		-- LVTP-5: um squad de infantaria embarcado
		for _, c in crews do
			if c.faction == faction and (Vehicles.PASSENGERS[c.spec] or 0) > 0 and not c.mech then
				for _, sq in BotSquads.list() do
					if sq.faction == faction and not sq.mech and not sq.player and #sq.members >= 2 then
						c.mech = sq
						sq.mech = c
						break
					end
				end
			end
		end
	end
end

-- Nasce no QG quem vai embarcar (tripulação; squad do LVTP-5 esperando no depósito)
function BotVehicles.spawnAtHQ(bot: Bot): boolean
	if crewOf(bot) then
		return true
	end
	local sq = bot.squad
	local c = sq and sq.mech
	return c ~= nil and (c.state == "load" or c.state == "board")
end

local function seatPos(vehicle: Model, sid: string): Vector3?
	local s = VehicleService.seat(vehicle, sid)
	local ch = chassisOf(vehicle)
	if not (s and ch) then
		return nil
	end
	-- embarca pelo lado esquerdo, junto ao assento
	return (ch.CFrame * CFrame.new(-(ch.Size.X / 2 + 1.5 / M), 0, ch.CFrame:PointToObjectSpace(s.Position).Z)).Position
end

local function freePassengerSeat(vehicle: Model): string?
	for i = 1, Vehicles.PASSENGERS[tostring(vehicle:GetAttribute("Spec"))] or 0 do
		local s = VehicleService.seat(vehicle, "p" .. i)
		if s and not s.Occupant and not s.Disabled then
			return "p" .. i
		end
	end
	return nil
end

-- A pé e sem inimigo: tripulação vai embarcar; squad do LVTP-5 vai para o depósito. true se assumiu.
function BotVehicles.calm(bot: Bot, model: Model, root: BasePart): boolean
	local c = crewOf(bot)
	local sid: string? = nil
	if c then
		sid = bot.crew.seat
	else
		local sq = bot.squad
		local mc = sq and sq.mech
		if mc and (mc.state == "load" or mc.state == "board") and mc.vehicle.Parent then
			local mch = chassisOf(mc.vehicle)
			sid = freePassengerSeat(mc.vehicle)
			if not (sid and mch) or flat(root.Position, (mch :: BasePart).Position) * M > 400 then
				return false -- sem lugar, ou longe demais: vai a pé
			end
			c = mc
		end
	end
	if not (c and sid) then
		return false
	end
	local p = seatPos(c.vehicle, sid :: string)
	if not p then
		return false
	end
	local d = flat(root.Position, p) * M
	if d <= V.boardM then
		BotLocomotion.stop(bot, nil)
		if VehicleService.botBoard(c.vehicle, model, sid :: string) then
			print(string.format("[VT65] bots: %s embarcou no %s (%s)", model.Name, c.spec, sid :: string))
		end
		return true
	end
	BotTypes.hooks.setStance(model, "stand")
	BotLocomotion.goFar(bot, p, if d > 40 then "sprint" else "jog", { tolerance = 3 / M })
	return true
end

---------------------------------------------------------------------------------------------
-- Destino: atrás de cobertura, de frente para o objetivo
---------------------------------------------------------------------------------------------

-- Crista entre o lugar e o objetivo (casco escondido): sobe mais de 1,2 m na linha?
local function hullDown(spot: Vector3, point: Vector3): boolean
	local h0 = BotWorld.heightAt(spot.X, spot.Z) + 1.5 / M
	local dx, dz = point.X - spot.X, point.Z - spot.Z
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1 then
		return false
	end
	for k = 1, 10 do
		local t = k * (8 / M) / l
		if t >= 1 then
			break
		end
		if BotWorld.heightAt(spot.X + dx * t, spot.Z + dz * t) > h0 + 1.2 / M then
			return true
		end
	end
	return false
end

local function passable(spec: string, kind: string, p: Vector3): boolean
	local g = BotWorld.grid
	if not g then
		return true
	end
	local i = BotNav.index(g, p.X, p.Z)
	return i ~= nil and BotNav.cost(g, i, BotNav.profile(kind, spec)) < math.huge
end

-- Lugar de parada a `standM` do objetivo, do lado de quem vem (from): atrás de sebe, casa ou
-- trincheira; senão onde a crista esconde o casco; senão o próprio ponto.
local function standoffSpot(c: Crew, point: Vector3, from: Vector3, standM: number): Vector3
	local dir = Vector3.new(from.X - point.X, 0, from.Z - point.Z)
	dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(1, 0, 0)
	local base = point + dir * (standM / M)
	local best: Vector3? = nil
	local bestD = math.huge
	for _, e in BotWorld.coversNear(base, V.coverSearchM / M) do
		if e.kind == "hedge" or e.kind == "wall" or e.kind == "earth" then
			local px, pz, nx, nz = BotWorld.closest(e, base.X, base.Z)
			-- normal virada para o nosso lado (longe do objetivo)
			if (point.X - px) * nx + (point.Z - pz) * nz > 0 then
				nx, nz = -nx, -nz
			end
			local back = e.half + V.behindM / M
			local spot = Vector3.new(px + nx * back, 0, pz + nz * back)
			local d = flat(spot, base)
			if d < bestD and passable(c.spec, c.kind, spot) then
				best, bestD = spot, d
			end
		end
	end
	if not best then
		for _, r in { 0, 15, 30 } do
			for k = 0, 11 do
				local a = k * math.pi / 6
				local spot = base + Vector3.new(math.cos(a), 0, math.sin(a)) * (r / M)
				if hullDown(spot, point) and passable(c.spec, c.kind, spot) then
					best = spot
					break
				end
				if r == 0 then
					break
				end
			end
			if best then
				break
			end
		end
	end
	local p = best or base
	return Vector3.new(p.X, BotWorld.heightAt(p.X, p.Z), p.Z)
end

---------------------------------------------------------------------------------------------
-- Direção (10 vezes por segundo)
---------------------------------------------------------------------------------------------

local function wantRoute(c: Crew, pos: Vector3, dest: Vector3, now: number)
	local rg = c.routeGoal
	local stale = not c.route or not rg or flat(rg, dest) > 10 / M or now - c.routeAt > 60
	if c.route and not stale then
		local _, seg, off = BotMove.project(c.route :: BotMove.Path, pos.X, pos.Z, c.routeFollow.seg)
		c.routeFollow.seg = seg
		stale = off * M > 40
	end
	if stale and not c.routePending and now - c.routeAt > 3 then
		c.routePending = true
		c.routeAt = now
		local cc = c
		BotWorld.route("veh" .. c.id, c.kind, c.spec, pos, dest, function(pts: { Vector3 }?, _ok: boolean)
			cc.routePending = false
			if pts and #pts >= 2 then
				local list: { BotMove.Point } = {}
				for _, p in pts do
					table.insert(list, { x = p.X, z = p.Z, y = p.Y })
				end
				cc.route = BotMove.path(list)
				cc.routeFollow = BotMove.newFollow()
				cc.routeGoal = dest
			end
		end)
	end
end

-- Para e, se pedido, gira no lugar para ficar de frente para `faceAt` (lagarta: frente para o
-- objetivo, a blindagem mais grossa).
local function brake(c: Crew, ch: BasePart, vs: VehicleService.BotDriveState, faceAt: Vector3?)
	local thr = if vs.v > 0.3 then -1 elseif vs.v < -0.3 then 1 else 0
	local steer = 0
	local caps = BotDriver.caps(c.kind)
	if faceAt and caps.pivot and thr == 0 then
		local _, s, err = BotDriver.control(vs.yaw, vs.v, ch.Position.X, ch.Position.Z, faceAt.X, faceAt.Z, 0, caps)
		steer = if math.abs(err) > math.rad(20) then s else 0
	end
	VehicleService.botInput(c.vehicle, thr, steer)
end

-- direct: em linha reta, sem rota nem freada de chegada (saída da baia; quem chama vê a chegada)
local function driveTo(
	c: Crew,
	ch: BasePart,
	dest: Vector3?,
	now: number,
	dt: number,
	faceAt: Vector3?,
	direct: boolean?
): boolean
	local vs = VehicleService.botState(c.vehicle)
	if not vs then
		return false
	end
	local pos = ch.Position
	if not dest then
		brake(c, ch, vs, faceAt)
		return true
	end
	local distM = flat(pos, dest) * M
	if distM <= V.arriveM and not direct then
		brake(c, ch, vs, faceAt)
		return math.abs(vs.v) < 0.5
	end
	if not direct then
		wantRoute(c, pos, dest, now)
	end
	local caps = BotDriver.caps(c.kind)
	-- preso (barranco, casa, outro veículo): ré e rota nova
	if now < c.reverseUntil then
		VehicleService.botInput(c.vehicle, -0.7, 0.4)
		return false
	end
	local tx, tz = dest.X, dest.Z
	-- na reta da baia não freia para parar no ponto: chega devagar e segue
	local left = if direct then distM + V.arriveM else distM
	local corner = 0
	local r = if direct then nil else c.route
	if r then
		local s = BotMove.project(r, pos.X, pos.Z, c.routeFollow.seg)
		local look = math.clamp(math.abs(vs.v) * 1.8, V.lookM[1], V.lookM[2]) / M
		tx, tz = BotMove.at(r, math.min(s + look, r.length))
		left = math.max((r.length - s) * M, distM)
		corner = BotMove.cornerAhead(r, s, 25 / M)
	end
	local want = BotDriver.desiredSpeed(vs.top, left, corner, 1.5)
	local thr, steer = BotDriver.control(vs.yaw, vs.v, pos.X, pos.Z, tx, tz, want, caps)
	VehicleService.botInput(c.vehicle, thr, steer)
	-- preso: acelerando e não sai do lugar (girar no lugar não conta). A velocidade é a do casco: a
	-- do motor (vs.v) oscila contra o obstáculo (sobe, o contato derruba, sobe de novo) e o "preso"
	-- nunca fechava (teste da v38: tanque parado 2 min contra um tronco sem dar ré)
	local vel = ch.AssemblyLinearVelocity
	local realV = math.sqrt(vel.X * vel.X + vel.Z * vel.Z) * M
	if vs.blocked or (math.abs(thr) > 0.3 and math.min(math.abs(vs.v), realV) < 0.4) then
		c.stuckT += dt
	else
		c.stuckT = 0
	end
	if c.stuckT > V.stuckS then
		c.stuckT = 0
		c.reverseUntil = now + V.reverseS
		c.route = nil
		c.routeAt = -math.huge
		if direct then
			c.leftDepot = true -- boca da baia tapada (outro veículo): desiste da reta e pede rota
		else
			-- o que segurou (tronco, poste) entra na grade: a rota nova contorna
			local ignore: { Instance } = { c.vehicle }
			for _, name in { "Vehicles", "Combatants" } do
				local f = workspace:FindFirstChild(name)
				if f then
					table.insert(ignore, f)
				end
			end
			BotWorld.learnObstacle(ch, if thr < 0 then -1 else 1, ignore)
			-- a ré não tirou: na 3ª vez no mesmo lugar, desencalha (como o jogador) e recua 6 m
			local here = ch.Position
			local again = c.stuckAt ~= nil and flat(here, c.stuckAt :: Vector3) * M < 6
			c.stuckN = if again then c.stuckN + 1 else 1
			c.stuckAt = here
			if c.stuckN >= 3 then
				c.stuckN = 0
				c.reverseUntil = 0
				VehicleService.botRecover(c.vehicle, if thr < 0 then -6 else 6)
				print(string.format("[VT65] bots: %s desencalhado (tripulação %d)", c.spec, c.id))
			end
		end
	end
	return false
end

local function seated(b: Bot?, vehicle: Model): boolean
	local m = b and b.model
	local hum = m and m:FindFirstChildOfClass("Humanoid")
	local s = hum and hum.SeatPart
	return s ~= nil and s:IsDescendantOf(vehicle)
end

local function passengers(c: Crew): { Model }
	local out: { Model } = {}
	for _, s in c.vehicle:GetDescendants() do
		if s:IsA("Seat") and s.Occupant and string.match(s.Name, "^Seat_p%d+$") then
			table.insert(out, s.Occupant.Parent :: Model)
		end
	end
	return out
end

local function setState(c: Crew, st: string, now: number)
	if c.state ~= st then
		c.state = st
		c.stateAt = now
		c.route = nil
		c.routeGoal = nil
		c.stuckN = 0
		c.stuckAt = nil
		print(string.format("[VT65] bots: %s (tripulação %d) -> %s", c.spec, c.id, st))
	end
end

function BotVehicles.drive(now: number, dt: number)
	for _, c in crews do
		local ch = chassisOf(c.vehicle)
		local drv = c.members.driver
		if not ch or not seated(drv, c.vehicle) then
			continue
		end
		local chassis = ch :: BasePart
		local sector = c.forceSector
		local point: Vector3? = nil
		if sector then
			local sp = MatchService.points[sector]
			point = if sp then Vector3.new(sp.x, 0, sp.z) else nil
		else
			local p, s = BotTypes.hooks.objective(c.faction)
			point, sector = p, s
		end
		local transport = (Vehicles.PASSENGERS[c.spec] or 0) > 0 and c.mech ~= nil
		if c.state == "board" then
			setState(c, if transport then "load" else "go", now)
		end
		if c.state == "load" then
			local n = #passengers(c)
			local waited = now - c.stateAt
			-- sai com a tropa; sem ninguém depois de muito tempo, vai assim mesmo (apoio de fogo)
			if point and (n >= V.minLoad or (n >= 1 and waited > V.loadWaitS) or waited > V.loadWaitS * 2) then
				setState(c, "go", now)
			end
			driveTo(c, chassis, nil, now, dt)
		elseif (c.state == "go" or c.state == "hold") and not c.leftDepot and c.exit then
			-- sai da baia em linha reta até a frente da boca; a rota (que não entra nos taludes)
			-- começa dali
			local ex = c.exit :: Vector3
			if flat(chassis.Position, ex) * M <= 2.5 then
				c.leftDepot = true
			end
			driveTo(c, chassis, ex, now, dt, nil, true)
		elseif c.state == "go" or c.state == "hold" then
			if not point then
				driveTo(c, chassis, nil, now, dt)
				continue
			end
			local p = point :: Vector3
			if sector ~= c.sector or not c.dest then
				c.sector = sector
				local stand = if transport then V.dropM else (V.standoffM[c.spec] or 200)
				c.dest = standoffSpot(c, p, chassis.Position, stand)
				if c.state == "hold" then
					setState(c, "go", now)
				end
			end
			local arrived = driveTo(c, chassis, c.dest, now, dt, p)
			-- encalhado perto do destino (outro veículo parado na vaga, mata): fica ali mesmo
			local dd = c.dest
			if not arrived and c.stuckN >= 2 and dd and flat(chassis.Position, dd) * M < 40 then
				arrived = true
			end
			if arrived and c.state == "go" then
				setState(c, if transport and #passengers(c) > 0 then "drop" else "hold", now)
			end
		elseif c.state == "drop" then
			driveTo(c, chassis, nil, now, dt)
			for _, m in passengers(c) do
				VehicleService.botLeave(m)
			end
			if now - c.stateAt > 4 then
				setState(c, "back", now)
			end
		elseif c.state == "back" then
			-- volta para a frente da baia (a grade de rota marca a baia inteira como obstáculo)
			if driveTo(c, chassis, c.exit or c.depot, now, dt) then
				c.dest = nil
				setState(c, "load", now)
			end
		end
		if now >= c.logAt then
			c.logAt = now + 10
			local vs = VehicleService.botState(c.vehicle)
			local d = c.dest
			print(
				string.format(
					"[VT65] bots: %s %s a %.0f km/h no %s, faltam %.0f m",
					c.spec,
					c.state,
					if vs then math.abs(vs.v) * 3.6 else 0,
					if vs then vs.ground else "?",
					if d then flat(chassis.Position, d) * M else 0
				)
			)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Atirador (0,3 s, pelo pensamento do bot)
---------------------------------------------------------------------------------------------
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function perturb(dir: Vector3, sigma: number, rng: any): Vector3
	local up = if math.abs(dir.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local r = dir:Cross(up).Unit
	local q = r:Cross(dir).Unit
	return (dir + r * rng:gauss() * sigma + q * rng:gauss() * sigma).Unit
end

local function fireVolley(
	c: Crew,
	bot: Bot,
	target: Model,
	coax: boolean,
	origin: Vector3,
	distM: number,
	moving: boolean
)
	c.firing = true
	local n = math.floor(V.coaxVolley[1] + (V.coaxVolley[2] - V.coaxVolley[1] + 1) * bot.rng:next())
	local life = bot.life
	task.spawn(function()
		for i = 1, n do
			local part = (target:FindFirstChild("UpperTorso") or target:FindFirstChild("Head")) :: BasePart?
			if not part or bot.life ~= life or c.vehicle:GetAttribute("Destroyed") then
				break
			end
			local sigma = BotBrain.aimError(
				bot.diff,
				distM,
				{ moving = moving, stance = "crouch", shot = i, kind = "mg" }
			) * BotBrain.settleFactor(bot.diff, os.clock() - c.targetSince)
			VehicleService.botFire(c.vehicle, "gunner", perturb((part.Position - origin).Unit, sigma, bot.rng), coax)
			task.wait(0.1)
		end
		c.firing = false
		c.nextShot = os.clock() + BotBrain.pause(bot.diff, "mg", bot.rng:next())
	end)
end

-- Bot sentado que não é atirador: o motorista não faz nada aqui (BotVehicles.drive); o passageiro
-- desce se o veículo não está levando ninguém (tripulação desfeita, motorista morto) ou se levou
-- tiro perto (desembarque sob fogo); quem sentou sem tripulação desce.
function BotVehicles.seatedThink(bot: Bot, model: Model, now: number)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local vehicle = seat and seat:FindFirstAncestorWhichIsA("Model")
	if not (seat and vehicle) then
		return
	end
	local mine = crewOf(bot)
	if mine and mine.vehicle == vehicle then
		return -- tripulação no seu posto
	end
	local c: Crew? = nil
	for _, cc in crews do
		if cc.vehicle == vehicle then
			c = cc
		end
	end
	local carrying = c ~= nil
		and (c.state == "load" or c.state == "go")
		and seated(c.members.driver, vehicle)
		and not BotBrain.underFire(bot.diff, bot.supp)
	if not carrying then
		VehicleService.botLeave(model)
	end
	local _ = now
end

-- O atirador sentado procura e engaja. true se é um atirador sentado (o BotService não faz mais nada).
function BotVehicles.gunner(bot: Bot, model: Model, now: number): boolean
	local c = crewOf(bot)
	if not c or bot.crew.seat ~= "gunner" or not seated(bot, c.vehicle) then
		return false
	end
	local seat = VehicleService.seat(c.vehicle, "gunner")
	local ch = chassisOf(c.vehicle)
	if not (seat and ch) then
		return true
	end
	local weapon = tostring(seat:GetAttribute("Weapon") or "")
	local eye = seat.Position + Vector3.new(0, 2.5 / M, 0)
	losParams.FilterDescendantsInstances = { c.vehicle, model }
	-- alvo: inimigo mais perto com visada (no máximo 3 raios por vez)
	local cands: { { m: Model, d: number } } = {}
	for _, e in Combatants.list() do
		if e.faction ~= c.faction and Combatants.active(e) then
			local r = Combatants.root(e)
			if r then
				local d = (r.Position - eye).Magnitude * M
				if d < 450 and not e.model:GetAttribute("InTunnel") then
					table.insert(cands, { m = e.model, d = d })
				end
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.d < b.d
	end)
	local target: Model? = nil
	local tDist = 0
	for i = 1, math.min(3, #cands) do
		local head = cands[i].m:FindFirstChild("Head") :: BasePart?
		if head then
			local hit = workspace:Raycast(eye, head.Position - eye, losParams)
			if hit and hit.Instance:IsDescendantOf(cands[i].m) then
				target, tDist = cands[i].m, cands[i].d
				break
			end
		end
	end
	if target ~= c.target then
		c.target = target
		c.targetSince = now
	end
	if not target or c.firing or now < c.nextShot then
		return true
	end
	local tgt = target :: Model
	local tp = (tgt:FindFirstChild("UpperTorso") or tgt:FindFirstChild("Head")) :: BasePart?
	if not tp then
		return true
	end
	-- torre gira na velocidade da ficha
	local spec = Vehicles.SPECS[c.spec]
	local degS = (spec and spec.turretDegS) or V.turretDegS
	local want = BotMove.yawTo(tp.Position.X - eye.X, tp.Position.Z - eye.Z)
	c.turret = BotDriver.turret(c.turret, want, degS, 0.3)
	local react = V.gunReaction[1] + (V.gunReaction[2] - V.gunReaction[1]) * ((bot.id * 0.37) % 1)
	if math.abs(BotMove.wrap(want - c.turret)) > math.rad(V.aimToleranceDeg) or now - c.targetSince < react then
		return true
	end
	-- grupo perto do alvo e abrigo dele
	local near = 0
	for _, cand in cands do
		local r = cand.m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - tp.Position).Magnitude * M < 6 then
			near += 1
		end
	end
	losParams.FilterDescendantsInstances = { c.vehicle, model }
	local ray = workspace:Raycast(eye, tp.Position - eye, losParams)
	local covered = ray ~= nil and not ray.Instance:IsDescendantOf(tgt)
	local tubes = (c.vehicle:GetAttribute("Tubes") :: number?) or 0
	local gun = BotDriver.gunFor(weapon, tDist, near, covered, VehicleService.mainReady(c.vehicle, "gunner"), tubes)
	local vs = VehicleService.botState(c.vehicle)
	local moving = vs ~= nil and math.abs(vs.v) > 1
	if gun == "main" then
		-- canhão: no chão aos pés do alvo (HE espalha)
		local root = tgt:FindFirstChild("HumanoidRootPart") :: BasePart?
		local aimAt = if root then root.Position - Vector3.new(0, 2.5, 0) else tp.Position
		local sigma = BotBrain.aimError(bot.diff, tDist, { moving = moving, stance = "prone" })
		if VehicleService.botFire(c.vehicle, "gunner", perturb((aimAt - eye).Unit, sigma, bot.rng), false) then
			c.nextShot = now + V.mainEveryS
			print(string.format("[VT65] bots: %s atirou com o canhão a %.0f m", c.spec, tDist))
		end
	elseif gun == "coax" or gun == "m60" then
		fireVolley(c, bot, tgt, gun == "coax", eye, tDist, moving)
	end
	return true
end

-- Gancho do Studio: força uma tripulação neste veículo, indo para o setor `sector`
function BotVehicles.force(bots: { Bot }, vehicle: Model, sector: number?): Crew?
	BotVehicles.assign(bots, vehicle)
	for _, c in crews do
		if c.vehicle == vehicle then
			c.forceSector = sector
			c.dest = nil
			c.sector = nil
			return c
		end
	end
	return nil
end

function BotVehicles.reset(bot: Bot)
	-- vida nova: continua na tripulação (embarca de novo)
	local _ = bot
end

function BotVehicles.debugText(bot: Bot): string?
	local c = crewOf(bot)
	if not c then
		return nil
	end
	return string.format("%s %s (%s)", c.spec, c.state, bot.crew.seat)
end

local _ = MapConfig
return BotVehicles
