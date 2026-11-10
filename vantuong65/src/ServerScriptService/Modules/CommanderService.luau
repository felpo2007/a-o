--!strict
-- Comandante e missões de fogo (F4, Parte 9.5): pedido por grade da carta de 1965 com correção do
-- observador, confirmação de "perigo próximo", tempo de voo calculado (morteiro) e impactos com
-- dispersão. Morteiro: o tubo está na posição construída (LogisticsService, mortar_pit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FireSupport = require(ReplicatedStorage.Shared.FireSupport)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Mortar = require(ReplicatedStorage.Shared.Mortar)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Combatants = require(script.Parent.Combatants)
local ExplosionService = require(script.Parent.ExplosionService)
local LogisticsService = require(script.Parent.LogisticsService)
local SpawnService = require(script.Parent.SpawnService)
local TunnelService = require(script.Parent.TunnelService)

local CommanderService = {}
local M = MapConfig.STUD_M
local rng = Rng.new(19650818)
local readyAt: { [string]: { [string]: number } } = { US = {}, VC = {} }
-- último alvo por jogador (para "mais 100, direita 50" sem repetir a grade)
local lastTarget: { [Player]: { x: number, z: number } } = {}

local MORTAR_OF = { us_mortar_81 = "us_81", vc_mortar_82 = "vc_82" }
-- navio ao largo: 3 km a leste da praia (design, D-36), para tempo de voo e som distante
local SHIP = { x = 5714.3 + 3000 / 0.28, z = -357.1 }
-- 5"/38 Mark 12 (contratorpedeiro USS Orleck, que cobriu o desembarque na Starlite): 2.500 ft/s com
-- o cano médio, 2.600 com o novo (navweaps WNUS_5-38_mk12). A distância do navio segue PLACEHOLDER.
local NAVAL_V = 762 -- m/s

local function reply(player: Player, msg: { [string]: any })
	Net.event("Commander_State"):FireClient(player, msg)
end

local function friendlyNearM(faction: string, x: number, z: number): number
	local best = math.huge
	for _, e in Combatants.list() do
		if e.faction == faction and Combatants.active(e) then
			local r = Combatants.root(e)
			if r then
				local d = Vector3.new(r.Position.X - x, 0, r.Position.Z - z).Magnitude * M
				best = math.min(best, d)
			end
		end
	end
	return best
end

local function groundAt(x: number, z: number): Vector3
	return Vector3.new(x, SpawnService.groundY(x, z) + 0.3, z)
end

local function broadcastState(faction: string)
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Faction") == faction then
			reply(p, { supply = LogisticsService.supply(faction), readyAt = readyAt[faction], now = os.clock() })
		end
	end
end

local function handle(player: Player, req: any)
	if type(req) ~= "table" or type(req.ability) ~= "string" then
		return
	end
	local faction = player:GetAttribute("Faction")
	local role = player:GetAttribute("Role")
	if type(faction) ~= "string" or type(role) ~= "string" then
		return
	end
	local a = FireSupport.ABILITIES[req.ability]
	local now = os.clock()
	local ok, why =
		FireSupport.canUse(req.ability, faction, role, LogisticsService.supply(faction), readyAt[faction], now)
	if not ok or not a then
		reply(player, { error = why })
		return
	end
	-- alvo: grade (obrigatória na 1ª vez) + correção opcional relativa ao observador
	local x: number?, z: number? = nil, nil
	if type(req.grid) == "string" and #req.grid > 0 then
		x, z = FireSupport.gridToLocal(req.grid, MapConfig.GridOrigin1965, M)
		if not x then
			reply(player, { error = "grade inválida (ex.: BS 7003 9285)" })
			return
		end
	elseif type(req.x) == "number" and type(req.z) == "number" and req.x == req.x and req.z == req.z then
		-- alvo escolhido no mapa com o cursor (controle, sem digitar): dentro da área de jogo
		local Bd = MapConfig.Bounds
		if req.x < Bd.minX or req.x > Bd.maxX or req.z < Bd.minZ or req.z > Bd.maxZ then
			reply(player, { error = "alvo fora do mapa" })
			return
		end
		x, z = req.x, req.z
	elseif lastTarget[player] then
		x, z = lastTarget[player].x, lastTarget[player].z
	end
	if not x or not z then
		reply(player, { error = "informe a grade do alvo" })
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if type(req.correction) == "string" and #req.correction > 0 and root then
		local along, right = FireSupport.parseCorrection(req.correction)
		local nx, nz = FireSupport.adjust(x * M, z * M, root.Position.X * M, root.Position.Z * M, along, right)
		x, z = nx / M, nz / M
	end
	local tx, tz = x :: number, z :: number
	lastTarget[player] = { x = tx, z = tz }

	if a.kind == "salvo" or a.kind == "line" then
		local friendly = friendlyNearM(faction, tx, tz)
		if a.dangerCloseM and friendly < a.dangerCloseM and req.confirm ~= true then
			reply(player, {
				warning = string.format("PERIGO PRÓXIMO: amigos a %d m do alvo. Repita com confirmação.", friendly),
			})
			return
		end
		-- tempo de voo: morteiro pelo solver, a partir do tubo; naval pela distância
		local tof = 0
		local launch: Vector3? = nil
		local mortarId = MORTAR_OF[a.id]
		if mortarId then
			local mx, mz = player:GetAttribute("MortarX"), player:GetAttribute("MortarZ")
			if type(mx) ~= "number" or type(mz) ~= "number" then
				reply(player, { error = "construa a posição de morteiro primeiro (tecla J)" })
				return
			end
			local rangeM = Vector3.new(tx - mx, 0, tz - mz).Magnitude * M
			local dh = (SpawnService.groundY(tx, tz) - SpawnService.groundY(mx, mz)) * M
			local elev, t = Mortar.solve(mortarId, rangeM, dh)
			if not elev or not t then
				local s = Mortar.spec(mortarId) :: any
				reply(
					player,
					{ error = string.format("fora do alcance (%d–%d m): %d m", s.minRangeM, s.maxRangeM, rangeM) }
				)
				return
			end
			tof = t
			launch = groundAt(mx, mz)
			reply(player, {
				info = string.format("no alvo em %.0f s · elevação %.0f mils", tof + a.delayS, Mortar.toMils(elev)),
			})
		elseif a.id == "us_naval_5in" then
			tof = Vector3.new(tx - SHIP.x, 0, tz - SHIP.z).Magnitude * M / NAVAL_V
			Net.unreliable("Fire_Launch"):FireAllClients({ kind = "naval", x = SHIP.x, y = 0, z = SHIP.z })
		end
		LogisticsService.spend(faction, a.supply)
		readyAt[faction][a.id] = now + a.cooldownS
		local heading = if root then math.atan2(root.CFrame.LookVector.X, -root.CFrame.LookVector.Z) else 0
		local impacts = FireSupport.impacts(a, tx, tz, heading, M, function()
			return rng:next()
		end)
		for _, imp in impacts do
			local tLaunch = a.delayS + imp.t
			if launch then
				local lp = launch
				task.delay(tLaunch, function()
					Net.unreliable("Fire_Launch"):FireAllClients({ kind = "mortar", x = lp.X, y = lp.Y, z = lp.Z })
				end)
			end
			local tImpact = tLaunch + tof
			task.delay(math.max(tImpact - 2.5, 0), function()
				local p = groundAt(imp.x, imp.z)
				Net.unreliable("Fire_Incoming"):FireAllClients({ x = p.X, y = p.Y, z = p.Z })
			end)
			task.delay(tImpact, function()
				ExplosionService.detonate(a.explosive :: string, groundAt(imp.x, imp.z))
			end)
		end
	elseif a.kind == "supply" then
		readyAt[faction][a.id] = now + a.cooldownS
		task.delay(a.delayS, function()
			LogisticsService.spawnCrate(faction, Vector3.new(tx, 0, tz))
		end)
		reply(player, { info = string.format("suprimento chega em %d s", a.delayS) })
	elseif a.kind == "tunnel" then
		local best, bestD = nil, math.huge
		for _, en in TunnelService.entrances() do
			local d = Vector3.new(en.x - tx, 0, en.z - tz).Magnitude
			if not TunnelService.destroyed[en.id] and d < bestD then
				best, bestD = en, d
			end
		end
		if not best then
			reply(player, { error = "nenhuma entrada de túnel intacta" })
			return
		end
		LogisticsService.spend(faction, a.supply)
		readyAt[faction][a.id] = now + a.cooldownS
		LogisticsService.tempGarrison(faction, best.x, best.z, "Reforço " .. best.id, 180)
		reply(player, { info = "reforço aberto na entrada " .. best.id .. " por 180 s" })
	end
	broadcastState(faction)
end

function CommanderService.start()
	Net.event("Commander_Request").OnServerEvent:Connect(handle)
	Players.PlayerRemoving:Connect(function(p)
		lastTarget[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			broadcastState("US")
			broadcastState("VC")
		end
	end)
end

return CommanderService
