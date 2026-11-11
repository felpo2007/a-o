--!strict
-- Túneis sob An Cường (2) para os bots (D-90; pedido do dono: "faça os bots entenderem como
-- utilizar ... os túneis"). Regra do dono (2026-11-11): só o VC entra; os EUA nunca entram (o
-- TunnelService tira de lá quem é dos EUA, jogador ou bot), mas desconfiam das bocas.
--   - VC: entra numa boca perto quando a saída fica bem mais perto do destino (deslocamento
--     escondido), some ferido ou cercado, e embosca: espera no pé do poço da saída até o inimigo
--     chegar a ~45 m e sai atirando;
--   - a travessia é física: o bot desce o poço, anda agachado (0,84 m/s, a velocidade do agachado)
--     no traçado de Shared/TunnelLinks e sobe na saída. Lá embaixo a raiz fica ancorada e ninguém na
--     superfície o vê (o terreno tapa); quem estiver no túnel vê;
--   - EUA: acham a boca camuflada a ~25 m com visada (ou tropeçando nela, ou vendo um VC entrar ou
--     sair) e jogam granada nela (uma a cada 90 s por boca, para o time). A granada cai pelo poço e
--     estoura lá embaixo (ExplosionService); o VC perto foge pelo túnel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local BotMove = require(ReplicatedStorage.Shared.BotMove)
local Movement = require(ReplicatedStorage.Shared.Movement)
local TunnelLinks = require(ReplicatedStorage.Shared.TunnelLinks)
local Tunnels = require(ReplicatedStorage.Shared.Tunnels) :: any
local BotLocomotion = require(script.Parent.BotLocomotion)
local BotTypes = require(script.Parent.BotTypes)
local BotWorld = require(script.Parent.BotWorld)
local Combatants = require(script.Parent.Combatants)
local TunnelService = require(script.Parent.TunnelService)

type Bot = BotTypes.Bot

local BotTunnels = {}
local M = 0.28
local T = BotBrain.TUNNEL
local DEPTH = Tunnels.DEPTH_M / M

type Pt = { id: string, x: number, z: number, floor: number }
export type Transit = {
	from: string,
	exit: string,
	pts: { Pt },
	seg: number,
	s: number, -- studs andados no trecho
	phase: string, -- "approach" | "down" | "walk" | "wait" | "up"
	t: number,
	hipY: number, -- raiz acima dos pés (agachado)
	ambush: boolean,
	waitUntil: number,
	goal: Vector3?,
	top: number, -- altura do chão na boca da saída
}

local known: { [string]: { [string]: boolean } } = { US = {}, VC = {} } -- bocas conhecidas por lado
local lastGrenade: { [string]: number } = {}
local transits: { [Bot]: Transit } = {}
local nextSpot: { [Bot]: number } = setmetatable({}, { __mode = "k" }) :: any
local spotParams = RaycastParams.new()
spotParams.FilterType = Enum.RaycastFilterType.Exclude

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function entrances(): { TunnelService.Entrance }
	local out = {}
	for _, e in TunnelService.entrances() do
		if not TunnelService.destroyed[e.id] then
			table.insert(out, e)
		end
	end
	return out
end

-- Pontos do caminho no túnel (piso = chão - 3 m, como o TunnelGeometry)
local function worldPath(via: { string }): { Pt }
	local cx, cz = BotWorld.villageCenter()
	local out: { Pt } = {}
	for _, p in TunnelLinks.toWorld(via, cx, cz) do
		table.insert(out, { id = p.id, x = p.x, z = p.z, floor = BotWorld.heightAt(p.x, p.z) - DEPTH })
	end
	return out
end

local function blockedSet(): { [string]: boolean }
	local b: { [string]: boolean } = {}
	for id, v in TunnelService.destroyed do
		if v then
			b[id] = true
		end
	end
	return b
end

function BotTunnels.inTransit(bot: Bot): boolean
	return transits[bot] ~= nil
end

function BotTunnels.knownBy(faction: string): { [string]: boolean }
	return known[faction] or {}
end

-- O lado fica sabendo da boca (os EUA, para a granada)
local function discover(faction: string, id: string)
	local k = known[faction]
	if k and not k[id] then
		k[id] = true
		print(string.format("[VT65] bots: %s acharam a boca de túnel %s", faction, id))
	end
end

-- Um VC entrou ou saiu: os EUA perto (até alertM) com visada ficam sabendo da boca
local function alert(id: string, pos: Vector3)
	for _, e in Combatants.list() do
		if e.faction == "US" and Combatants.active(e) then
			local r = Combatants.root(e)
			if r and flat(r.Position, pos) * M <= T.alertM then
				spotParams.FilterDescendantsInstances = { e.model }
				local hit = workspace:Raycast(r.Position, pos + Vector3.new(0, 2, 0) - r.Position, spotParams)
				if not hit or (hit.Position - pos).Magnitude < 4 / M then
					discover("US", id)
					return
				end
			end
		end
	end
end

-- Começa a ir para a boca `id` e atravessar até `exit` (só VC).
function BotTunnels.start(bot: Bot, id: string, exit: string, ambush: boolean, goal: Vector3?): boolean
	if bot.faction ~= "VC" or transits[bot] then
		return false
	end
	local via = TunnelLinks.path(id, exit, blockedSet())
	if not via then
		return false
	end
	local pts = worldPath(via)
	if #pts < 2 then
		return false
	end
	local ex = pts[#pts]
	transits[bot] = {
		from = id,
		exit = exit,
		pts = pts,
		seg = 1,
		s = 0,
		phase = "approach",
		t = 0,
		hipY = 0,
		ambush = ambush,
		waitUntil = 0,
		goal = goal,
		top = BotWorld.heightAt(ex.x, ex.z),
	}
	bot.tunnel = transits[bot]
	return true
end

local function finish(bot: Bot)
	transits[bot] = nil
	bot.tunnel = nil
	local m = bot.model
	if m then
		m:SetAttribute("InTunnel", nil)
	end
end

-- Melhor travessia (entrada perto do bot, saída perto do destino) para quem anda até `goal`.
local function bestCrossing(pos: Vector3, goal: Vector3): (string?, string?)
	local list = entrances()
	local best, bestGain, bi, bo = nil :: string?, 0, nil :: string?, nil :: string?
	for _, a in list do
		local apos = Vector3.new(a.x, 0, a.z)
		local toEntry = flat(pos, apos) * M
		if toEntry <= T.useWithinM then
			for _, b in list do
				if b.id ~= a.id then
					local entryToGoal = flat(apos, goal) * M
					local exitToGoal = flat(Vector3.new(b.x, 0, b.z), goal) * M
					if BotBrain.tunnelWorth(toEntry, entryToGoal, exitToGoal) then
						local gain = entryToGoal - exitToGoal - toEntry
						if gain > bestGain then
							best, bestGain, bi, bo = a.id, gain, a.id, b.id
						end
					end
				end
			end
		end
	end
	local _ = best
	return bi, bo
end

-- VC calmo indo para `goal`: usa o túnel se compensa. Só o líder (ou quem anda sozinho) escolhe;
-- o seguidor vai atrás do líder que entrou. Devolve true se assumiu o movimento.
function BotTunnels.considerMove(bot: Bot, root: BasePart, goal: Vector3, leads: boolean): boolean
	if bot.faction ~= "VC" or transits[bot] then
		return transits[bot] ~= nil
	end
	local sq = bot.squad
	local leader = if sq then sq.leader else nil
	local lt = if leader and leader ~= bot then transits[leader] else nil
	if lt then
		return BotTunnels.start(bot, lt.from, lt.exit, lt.ambush, lt.goal)
	end
	if not leads then
		return false
	end
	local a, b = bestCrossing(root.Position, goal)
	if a and b then
		return BotTunnels.start(bot, a, b, false, goal)
	end
	return false
end

-- VC ferido ou cercado com uma boca perto: some (sai na boca mais longe da ameaça)
function BotTunnels.vanish(bot: Bot, root: BasePart, threat: Vector3): boolean
	if bot.faction ~= "VC" or transits[bot] then
		return transits[bot] ~= nil
	end
	local list = entrances()
	local entry: string? = nil
	local bestD = math.huge
	for _, e in list do
		local d = flat(root.Position, Vector3.new(e.x, 0, e.z)) * M
		if d <= T.vanishWithinM and d < bestD then
			entry, bestD = e.id, d
		end
	end
	if not entry then
		return false
	end
	local exit: string? = nil
	local far = -1
	for _, e in list do
		local d = flat(threat, Vector3.new(e.x, 0, e.z))
		if e.id ~= entry and d > far then
			exit, far = e.id, d
		end
	end
	if not exit then
		return false
	end
	return BotTunnels.start(bot, entry :: string, exit :: string, true, nil)
end

-- Emboscada (gancho do Studio e VC defendendo An Cường): entra em `id` e espera em `exit`
function BotTunnels.ambush(bot: Bot, id: string, exit: string): boolean
	return BotTunnels.start(bot, id, exit, true, nil)
end

-- VC defendendo um objetivo perto da rede (até 250 m do centro da vila): espera no pé do poço da
-- boca virada para o inimigo (axisYaw: rumo do objetivo para o inimigo). Uma vez por vida.
local ambushedLife: { [Bot]: number } = setmetatable({}, { __mode = "k" }) :: any
function BotTunnels.defend(bot: Bot, root: BasePart, point: Vector3, axisYaw: number): boolean
	if bot.faction ~= "VC" or transits[bot] or ambushedLife[bot] == bot.life then
		return false
	end
	local list = entrances()
	local cx, cz = BotWorld.villageCenter()
	if #list < 2 or flat(point, Vector3.new(cx, 0, cz)) * M > 250 then
		return false
	end
	local front = point + Vector3.new(-math.sin(axisYaw), 0, -math.cos(axisYaw)) * (60 / M)
	local exit: string? = nil
	local ed = math.huge
	for _, e in list do
		local d = flat(Vector3.new(e.x, 0, e.z), front)
		if d < ed then
			exit, ed = e.id, d
		end
	end
	local entry: string? = nil
	local nd = math.huge
	for _, e in list do
		if e.id ~= exit then
			local d = flat(root.Position, Vector3.new(e.x, 0, e.z))
			if d < nd then
				entry, nd = e.id, d
			end
		end
	end
	if not (entry and exit) or nd * M > 150 then
		return false
	end
	ambushedLife[bot] = bot.life
	return BotTunnels.start(bot, entry :: string, exit :: string, true, nil)
end

-- EUA: acha bocas (visada até spotM, tropeço até stumbleM) e joga granada nas conhecidas.
-- Devolve true se arremessou.
function BotTunnels.suspect(bot: Bot, model: Model, root: BasePart, head: BasePart, now: number): boolean
	if bot.faction ~= "US" then
		return false
	end
	local k = known.US
	if now >= (nextSpot[bot] or 0) then
		nextSpot[bot] = now + 2
		for _, e in entrances() do
			if not k[e.id] then
				local p = Vector3.new(e.x, BotWorld.heightAt(e.x, e.z) + 0.6, e.z)
				local d = flat(root.Position, p) * M
				if d <= T.stumbleM then
					discover("US", e.id)
				elseif d <= T.spotM then
					spotParams.FilterDescendantsInstances = { model }
					local hit = workspace:Raycast(head.Position, p - head.Position, spotParams)
					if not hit or (hit.Position - p).Magnitude < 2.5 / M then
						discover("US", e.id)
					end
				end
			end
		end
	end
	local G = bot.diff.grenade
	if bot.grenades >= G.perLife or now < bot.nextGrenade then
		return false
	end
	for _, e in entrances() do
		if k[e.id] and now >= (lastGrenade[e.id] or -math.huge) then
			local p = Vector3.new(e.x, BotWorld.heightAt(e.x, e.z), e.z)
			local d = flat(root.Position, p) * M
			if d >= G.minM and d <= G.maxM then
				lastGrenade[e.id] = now + T.grenadeCooldownS
				if BotTypes.hooks.throwGrenade(bot, p) then
					print(string.format("[VT65] bots: granada na boca do túnel %s (%.0f m)", e.id, d))
					-- VC lá embaixo perto do poço: foge pelo túnel quando ouve a granada cair
					task.delay(1, function()
						for b, tr in transits do
							local ex = tr.pts[#tr.pts]
							if
								(tr.phase == "wait" or tr.phase == "walk")
								and flat(Vector3.new(ex.x, 0, ex.z), p) * M <= T.scareM
							then
								tr.ambush = false
								tr.phase = "walk"
								local alt: string? = nil
								for _, o in entrances() do
									if o.id ~= tr.exit and o.id ~= e.id then
										alt = o.id
										break
									end
								end
								if alt then
									local via = TunnelLinks.path(ex.id, alt, blockedSet())
									if via then
										tr.pts = worldPath(via)
										tr.seg, tr.s, tr.exit = 1, 0, alt
										local last = tr.pts[#tr.pts]
										tr.top = BotWorld.heightAt(last.x, last.z)
									end
								end
								local _ = b
							end
						end
					end)
					return true
				end
				return false
			end
		end
	end
	return false
end

-- Pensamento de quem está indo para a boca ou dentro do túnel (BotService chama a cada 0,3 s)
function BotTunnels.think(bot: Bot, model: Model, hum: Humanoid, root: BasePart, now: number)
	local tr = transits[bot]
	if not tr then
		return
	end
	if TunnelService.destroyed[tr.exit] then
		-- saída fechada: procura outra a partir de onde está
		local alt: string? = nil
		for _, e in entrances() do
			if e.id ~= tr.exit then
				alt = e.id
				break
			end
		end
		local here = tr.pts[math.min(tr.seg, #tr.pts)].id
		local via = if alt then TunnelLinks.path(here, alt :: string, blockedSet()) else nil
		if via and alt then
			tr.pts, tr.seg, tr.s, tr.exit = worldPath(via), 1, 0, alt
		end
	end
	if tr.phase == "approach" then
		local a = tr.pts[1]
		if TunnelService.destroyed[tr.from] then
			finish(bot)
			return
		end
		-- vai até a beira do poço (1,5 m do centro, do lado de onde vem), não para cima do buraco
		local c = Vector3.new(a.x, root.Position.Y, a.z)
		local away = Vector3.new(root.Position.X - a.x, 0, root.Position.Z - a.z)
		local p = if away.Magnitude > 1 then c + away.Unit * (1.5 / M) else c
		local d = flat(root.Position, p) * M
		if d <= 0.9 then
			-- desce: agacha, ancora e vai para o pé do poço
			BotTypes.hooks.setStance(model, "crouch")
			BotLocomotion.stop(bot, nil)
			-- raiz acima dos pés com o HipHeight do agachado (a raiz ainda está descendo)
			tr.hipY = hum.HipHeight + root.Size.Y / 2
			tr.top = BotWorld.heightAt(a.x, a.z)
			root.Anchored = true
			model:SetAttribute("InTunnel", tr.from)
			tr.phase, tr.t = "down", 0
			alert(tr.from, Vector3.new(a.x, tr.top, a.z))
		else
			BotLocomotion.go(bot, p, if d > 6 then "jog" else "walk", { tolerance = 0.6 / M })
		end
	elseif tr.phase == "wait" then
		local ex = tr.pts[#tr.pts]
		local exPos = Vector3.new(ex.x, tr.top, ex.z)
		local trigger = now >= tr.waitUntil
		for _, e in Combatants.list() do
			if e.faction ~= bot.faction and Combatants.active(e) then
				local r = Combatants.root(e)
				if r and flat(r.Position, exPos) * M <= T.ambushTriggerM then
					trigger = true
					bot.lastKnown, bot.lastKnownAt = r.Position, now
					break
				end
			end
		end
		if trigger then
			tr.phase, tr.t = "up", 0
		end
	end
end

-- Sai do túnel ao lado do poço (não em cima do buraco), virado para o destino ou o inimigo
local function emerge(bot: Bot, model: Model, root: BasePart, tr: Transit)
	local ex = tr.pts[#tr.pts]
	local look = tr.goal or bot.lastKnown
	local a = if look then BotMove.yawTo(look.X - ex.x, look.Z - ex.z) else math.random() * 2 * math.pi
	local r = T.exitOffsetM / M
	local x, z = ex.x - math.sin(a) * r, ex.z - math.cos(a) * r
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, tr.top + 20, z), Vector3.new(0, -60, 0), params)
	local y = if hit then hit.Position.Y else tr.top
	model:PivotTo(CFrame.new(x, y + tr.hipY + 0.3, z) * CFrame.Angles(0, a, 0))
	root.Anchored = false
	BotLocomotion.setYaw(bot, a)
	alert(tr.exit, Vector3.new(ex.x, tr.top, ex.z))
	finish(bot)
end

-- Movimento lá embaixo (cada quadro, só para quem está no túnel)
local function stepTransit(bot: Bot, tr: Transit, dt: number, now: number)
	local model = bot.model
	local root = if model then model:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
	if not (model and root and hum) or hum.Health <= 0 then
		finish(bot)
		return
	end
	if tr.phase == "approach" or tr.phase == "wait" then
		return
	end
	tr.t += dt
	local m = model :: Model
	if tr.phase == "down" then
		local a = tr.pts[1]
		local k = math.clamp(tr.t / T.climbS, 0, 1)
		local y = tr.top + (a.floor - tr.top) * k
		m:PivotTo(CFrame.new(a.x, y + tr.hipY, a.z) * root.CFrame.Rotation)
		if k >= 1 then
			tr.phase, tr.t = "walk", 0
		end
	elseif tr.phase == "walk" then
		local i = tr.seg
		if i >= #tr.pts then
			if tr.ambush then
				tr.phase = "wait"
				tr.waitUntil = now + T.ambushMaxS
			else
				tr.phase, tr.t = "up", 0
			end
			return
		end
		local a, b = tr.pts[i], tr.pts[i + 1]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		tr.s += Movement.CROUCH / M * dt
		if tr.s >= len then
			tr.s -= len
			tr.seg += 1
			return
		end
		local k = if len > 1e-6 then tr.s / len else 1
		local x, z = a.x + (b.x - a.x) * k, a.z + (b.z - a.z) * k
		local y = a.floor + (b.floor - a.floor) * k
		local yaw = BotMove.yawTo(b.x - a.x, b.z - a.z)
		m:PivotTo(CFrame.new(x, y + tr.hipY, z) * CFrame.Angles(0, yaw, 0))
	elseif tr.phase == "up" then
		local ex = tr.pts[#tr.pts]
		local k = math.clamp(tr.t / T.climbS, 0, 1)
		local y = ex.floor + (tr.top - ex.floor) * k
		m:PivotTo(CFrame.new(ex.x, y + tr.hipY, ex.z) * root.CFrame.Rotation)
		if k >= 1 then
			emerge(bot, m, root, tr)
		end
	end
end

-- Limpa o estado de uma vida que acabou
function BotTunnels.reset(bot: Bot)
	if transits[bot] then
		finish(bot)
	end
end

function BotTunnels.startLoop()
	RunService.Heartbeat:Connect(function(dt: number)
		if next(transits) == nil then
			return
		end
		local now = os.clock()
		for bot, tr in transits do
			local ok, err = pcall(function(): any
				stepTransit(bot, tr, math.min(dt, 0.1), now)
				return nil
			end)
			if not ok then
				warn("[VT65] bots: túnel falhou:", err)
				finish(bot)
			end
		end
	end)
	-- nova partida: os EUA esquecem as bocas achadas
	local MatchService = require(script.Parent.MatchService)
	local last = MatchService.startedAt
	task.spawn(function()
		while true do
			task.wait(5)
			if MatchService.startedAt ~= last then
				last = MatchService.startedAt
				known.US = {}
				table.clear(lastGrenade)
			end
		end
	end)
end

return BotTunnels
