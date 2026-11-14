--!strict
-- Veículo ao nascer (D-103; pedido do dono, 2026-11-12: "coloque a opção de comprar um veículo quando
-- nascer e ele spawnar do seu lado"). Regras em Shared/CompraVeiculo; tela no
-- Controllers/CompraVeiculo.client (carta de inserção). Começa pelo VehicleService.start.
-- Fluxo:
--   1. Na carta, o jogador (morto) pede a viatura e a forma de pagar: Vehicle_Order. O servidor
--      confere as regras (lado, um por jogador, teto do lado, espera, saldo ou produto criado) e arma o
--      pedido. Nada é cobrado aqui.
--   2. Ao nascer (Spawn_Request num QG, reunião de setor ou reunião avançada; Combatants.Added), o
--      servidor procura um lugar a 4-10 m do soldado: raios no chão sob a caixa inteira (terreno ou
--      estrada, sem água, lama nem arrozal alagado, plano e no nível do pé), caixa livre de casa, árvore, veículo e
--      gente, dentro do mapa. O veículo fica virado para o objetivo do lado.
--   3. Achou: em CI, cobra (ProgressionService.spendCredits) e entrega; em Robux, reserva o lugar e
--      só então abre o prompt do Developer Product. O recibo (CommerceService) vira o veículo se a
--      reserva ainda vale; senão vira CI no perfil. Não achou: avisa e não cobra nada.
--   Túnel, companheiro, ponto do squad, onde caiu: o pedido fica para a próxima inserção.
--   Abandonado (sem ninguém dentro nem jogador perto) por 90 s: some. Destruído: sem reembolso.
--   Bots não compram (o remote é só de jogador).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Combatants = require(script.Parent.Combatants)
local CommerceService = require(script.Parent.CommerceService)
local MatchService = require(script.Parent.MatchService)
local PlayerData = require(script.Parent.PlayerData)
local ProgressionService = require(script.Parent.ProgressionService)

local CompraVeiculoService = {}

-- o que o VehicleService empresta (sem require de volta: ele é quem chama o start)
export type Api = {
	spawnAt: (specId: string, at: Vector3, yaw: number) -> Model?,
	vehicles: () -> { Model },
}

type Order = { spec: string, pay: string, at: number }
type Reserve = { spec: string, x: number, z: number, yaw: number, footY: number, at: number }

local M = MapConfig.STUD_M
local R = CompraVeiculo.RULES
local api: Api? = nil
local orders: { [Player]: Order } = {}
local reserves: { [Player]: Reserve } = {}
local lastDeliver: { [Player]: number } = {}
local lastPoint: { [Player]: { id: string, at: number } } = {}
local lastReq: { [Player]: number } = {}
local idle: { [Model]: number } = {}
local seenDestroyed: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function notice(player: Player, msg: string)
	Net.event("Vehicle_Notice"):FireClient(player, msg)
end

local function specName(spec: string): string
	local s = Vehicles.SPECS[spec]
	return if s then s.name else spec
end

local function alive(player: Player): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function credits(player: Player): number
	local p = PlayerData.get(player)
	return if p then p.credits else 0
end

-- comprados vivos: do jogador e do lado (as reservas em Robux contam, menos a de `except`)
local function counts(player: Player, faction: string?, except: Player?): (number, number)
	local mine, team = 0, 0
	local list: { Model } = if api then api.vehicles() else {}
	for _, m in list do
		local by = m:GetAttribute("BoughtBy")
		if by ~= nil then
			if by == player.UserId then
				mine += 1
			end
			if m:GetAttribute("Faction") == faction then
				team += 1
			end
		end
	end
	for p, r in reserves do
		if p ~= except then
			local item = CompraVeiculo.ITEMS[r.spec]
			if p == player then
				mine += 1
			end
			if item and item.faction == faction then
				team += 1
			end
		end
	end
	return mine, team
end

local function ctxFor(player: Player, spec: string, pay: string, phase: string, except: Player?): CompraVeiculo.Ctx
	local f = player:GetAttribute("Faction")
	local faction = if type(f) == "string" then f else nil
	local mine, team = counts(player, faction, except)
	local last = lastDeliver[player]
	return {
		spec = spec,
		faction = faction,
		bot = false,
		phase = phase,
		alive = alive(player),
		mine = mine,
		team = team,
		sinceLast = if last then os.clock() - last else nil,
		pay = pay,
		credits = credits(player),
		productId = CompraVeiculo.productId(spec),
	}
end

-- estado para a tela da carta
local function sendState(player: Player, msg: string?)
	local o, r = orders[player], reserves[player]
	local f = player:GetAttribute("Faction")
	local mine, team = counts(player, if type(f) == "string" then f else nil)
	local last = lastDeliver[player]
	Net.event("Vehicle_OrderState"):FireClient(player, {
		spec = if o then o.spec elseif r then r.spec else nil,
		pay = if o then o.pay elseif r then "robux" else nil,
		state = if r then "reserved" elseif o then "armed" else "none",
		msg = msg,
		cooldown = if last then math.max(0, math.ceil(R.cooldownS - (os.clock() - last))) else 0,
		mine = mine,
		team = team,
	})
end

-- ===== lugar ao lado =====
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
groundParams.IgnoreWater = false
local boxParams = OverlapParams.new()
boxParams.FilterType = Enum.RaycastFilterType.Exclude
boxParams.RespectCanCollide = true
local paddyParams = RaycastParams.new()
paddyParams.FilterType = Enum.RaycastFilterType.Include

-- chão que aceita o veículo: terreno (sem água nem lama) ou peça de estrada do mapa
local function groundHit(hit: RaycastResult?): boolean
	if not hit then
		return false
	end
	if hit.Instance == workspace.Terrain then
		return hit.Material ~= Enum.Material.Water and hit.Material ~= Enum.Material.Mud
	end
	return hit.Instance:GetAttribute("Material") == "Road"
end

-- Confere um lugar (centro cx, cz em studs; rumo yaw). Devolve a altura do chão (studs) ou nil.
local function spotOk(spec: Vehicles.Spec, cx: number, cz: number, yaw: number, footY: number): number?
	local B = MapConfig.Bounds
	local edge = 10 / M
	if cx < B.minX + edge or cx > B.maxX - edge or cz < B.minZ + edge or cz > B.maxZ - edge then
		return nil
	end
	local L, W, H = spec.lengthM, spec.widthM, spec.heightM
	local top = footY + 25 / M
	local drop = Vector3.new(0, -50 / M, 0)
	local heights: { number } = {}
	-- a lâmina d'água do arrozal não colide (o raio sólido passa por ela): raio próprio
	local map = workspace:FindFirstChild("Map")
	local sheet = map and map:FindFirstChild("PaddyWater")
	if sheet then
		paddyParams.FilterDescendantsInstances = { sheet }
	end
	for _, s in CompraVeiculo.footprint(L, W) do
		local wx, wz = CompraVeiculo.toWorld(s[1], s[2], yaw)
		local from = Vector3.new(cx + wx / M, top, cz + wz / M)
		local hit = workspace:Raycast(from, drop, groundParams)
		if not groundHit(hit) then
			return nil -- telhado, árvore, veículo, gente, água, lama ou buraco
		end
		if sheet and workspace:Raycast(from, drop, paddyParams) then
			return nil -- arrozal alagado
		end
		table.insert(heights, (hit :: RaycastResult).Position.Y * M)
	end
	if not CompraVeiculo.groundOk(heights, footY * M) then
		return nil
	end
	local sum = 0
	for _, h in heights do
		sum += h
	end
	local gy = sum / #heights / M
	-- caixa livre do chão (+0,35 m) até o teto do veículo, com folga
	local lift = 0.35
	local size = Vector3.new(W + 2 * R.clearM, math.max(H - lift, 0.5), L + 2 * R.clearM) / M
	local cf = CFrame.new(cx, gy + (lift + (H - lift) / 2) / M, cz) * CFrame.Angles(0, yaw, 0)
	for _, p in workspace:GetPartBoundsInBox(cf, size, boxParams) do
		if p:GetAttribute("Material") ~= "Road" then
			return nil
		end
	end
	return gy
end

-- rumo do objetivo do lado (setor a tomar ou a defender); sem partida, o QG do outro lado
local function objectiveYaw(faction: string, pos: Vector3): number
	local st = MatchService.state
	if st then
		local _, s = Front.objective(st.owner, st.active, faction)
		local sp = if s then MatchService.points[s] else nil
		if sp then
			return CompraVeiculo.yawToward(pos.X, pos.Z, sp.x, sp.z)
		end
	end
	local hq = MapConfig.HQ[if faction == "US" then "VC" else "US"]
	return CompraVeiculo.yawToward(pos.X, pos.Z, hq.x, hq.z)
end

-- Procura o lugar ao lado de quem nasceu. Devolve (reserva, nil) ou (nil, motivo).
local function findSpot(char: Model, specId: string, faction: string): (Reserve?, string?)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spec = Vehicles.SPECS[specId]
	if not (root and spec) then
		return nil, "sem personagem"
	end
	if char:GetAttribute("InTunnel") ~= nil then
		return nil, "túnel"
	end
	local pos = (root :: BasePart).Position
	groundParams.FilterDescendantsInstances = { char }
	boxParams.FilterDescendantsInstances = { workspace.Terrain }
	local foot = workspace:Raycast(pos, Vector3.new(0, -12 / M, 0), groundParams)
	local footY = if foot then foot.Position.Y else pos.Y - 3
	-- chão de cima a menos de 3 m (gruta, túnel, casa): não é lugar de veículo
	local up = workspace:Raycast(pos, Vector3.new(0, 3 / M, 0), groundParams)
	if up then
		return nil, "teto"
	end
	local yaw = objectiveYaw(faction, pos)
	groundParams.FilterDescendantsInstances = {}
	for _, c in CompraVeiculo.candidates(yaw, spec.lengthM, spec.widthM) do
		local cx, cz = pos.X + c.dx / M, pos.Z + c.dz / M
		if spotOk(spec, cx, cz, yaw, footY) then
			return { spec = specId, x = cx, z = cz, yaw = yaw, footY = footY, at = os.clock() }, nil
		end
	end
	return nil, "sem lugar"
end

-- Monta o veículo comprado no lugar achado. Não renasce (sem depósito).
local function deliver(player: Player, r: Reserve): Model?
	local a = api
	if not a then
		return nil
	end
	local m = a.spawnAt(r.spec, Vector3.new(r.x, 0, r.z), r.yaw)
	if not m then
		return nil
	end
	m:SetAttribute("BoughtBy", player.UserId)
	m:SetAttribute("BoughtName", player.DisplayName)
	lastDeliver[player] = os.clock()
	idle[m] = 0
	notice(player, string.format("%s ao seu lado", specName(r.spec)))
	return m
end

-- CI de volta fora de recibo (o veículo não montou depois de cobrado): delta da sessão, grava logo
local function giveBack(player: Player, amount: number)
	local p = PlayerData.get(player)
	if not p or amount <= 0 then
		return
	end
	p.credits += amount
	ProgressionService.push(player)
	task.spawn(PlayerData.save, player)
end

local function cancel(player: Player, msg: string)
	orders[player] = nil
	notice(player, msg)
	sendState(player) -- o texto foi pelo Vehicle_Notice (aviso na tela)
end

-- Acabou de nascer com um pedido armado: confere o ponto, as regras e o lugar; cobra só no fim.
local function tryDeliver(player: Player, char: Model)
	local o = orders[player]
	if not o or player.Character ~= char or not alive(player) then
		return
	end
	local pt = lastPoint[player]
	if not pt or os.clock() - pt.at > 60 or not CompraVeiculo.pointAllowed(pt.id) then
		local msg =
			"O veículo só sai no QG ou num ponto de reunião: o pedido fica para a próxima inserção. Nada foi cobrado."
		notice(player, msg)
		sendState(player) -- o texto foi pelo Vehicle_Notice (aviso na tela)
		return
	end
	local okRule, why = true, nil
	if o.pay ~= "dev" then -- pedido do gancho de teste: sem regra nem cobrança
		okRule, why = CompraVeiculo.check(ctxFor(player, o.spec, o.pay, "deliver"))
	end
	if not okRule then
		cancel(player, string.format("%s. O veículo não veio e nada foi cobrado.", why or "Pedido recusado"))
		return
	end
	local faction = tostring(player:GetAttribute("Faction"))
	local r, reason = findSpot(char, o.spec, faction)
	if not r then
		local msg = if reason == "túnel" or reason == "teto"
			then "Debaixo de teto o veículo não sai: o pedido fica para a próxima inserção. Nada foi cobrado."
			else "Sem lugar livre e plano a 4-10 m de você: o veículo não veio e nada foi cobrado."
		if reason == "túnel" or reason == "teto" then
			notice(player, msg)
			sendState(player) -- o texto foi pelo Vehicle_Notice (aviso na tela)
		else
			cancel(player, msg)
		end
		return
	end
	local spot = r :: Reserve
	local item = CompraVeiculo.ITEMS[o.spec]
	if o.pay == "ci" then
		if not ProgressionService.spendCredits(player, item.credits) then
			cancel(player, "CI insuficiente: o veículo não veio e nada foi cobrado.")
			return
		end
		orders[player] = nil
		if not deliver(player, spot) then
			giveBack(player, item.credits)
			notice(player, "O veículo não montou: os CI voltaram.")
		end
		sendState(player)
	elseif o.pay == "robux" then
		local id = CompraVeiculo.productId(o.spec)
		if id == 0 then
			cancel(player, "A compra em Robux deste veículo ainda não foi liberada. Nada foi cobrado.")
			return
		end
		orders[player] = nil
		reserves[player] = spot
		notice(player, string.format("Lugar reservado ao seu lado: confirme a compra do %s", specName(o.spec)))
		sendState(player)
		MarketplaceService:PromptProductPurchase(player, id)
	elseif o.pay == "dev" then
		orders[player] = nil
		deliver(player, spot)
		sendState(player)
	end
end

-- ===== recibo em Robux (CommerceService) =====
local function reserveValid(player: Player, spec: string): boolean
	local r = reserves[player]
	local spec2 = Vehicles.SPECS[spec]
	if not (r and spec2 and r.spec == spec) or os.clock() - r.at > R.reserveS or not alive(player) then
		return false
	end
	local ok = CompraVeiculo.check(ctxFor(player, spec, "robux", "deliver", player))
	return ok and spotOk(spec2, r.x, r.z, r.yaw, r.footY) ~= nil
end

local function onGrant(player: Player, spec: string, now: boolean, refund: number)
	local r = reserves[player]
	reserves[player] = nil
	if now and r and r.spec == spec then
		if not deliver(player, r) then
			giveBack(player, refund)
			notice(player, string.format("O veículo não montou: %d CI no seu saldo.", refund))
		end
	else
		notice(player, string.format("A compra entrou, mas o lugar se perdeu: %d CI no seu saldo.", refund))
	end
	sendState(player)
end

-- ===== pedido na carta =====
local function onOrder(player: Player, req: any)
	local t = os.clock()
	if t - (lastReq[player] or 0) < 0.25 or type(req) ~= "table" then
		return
	end
	lastReq[player] = t
	if req.op == "get" then
		sendState(player)
		return
	elseif req.op == "cancel" then
		orders[player] = nil
		sendState(player)
		return
	end
	local spec, pay = req.spec, req.pay
	if type(spec) ~= "string" or type(pay) ~= "string" or not CompraVeiculo.ITEMS[spec] then
		return
	end
	if reserves[player] then
		sendState(player, "Há uma compra em Robux esperando confirmação")
		return
	end
	local ok, why = CompraVeiculo.check(ctxFor(player, spec, pay, "order"))
	if not ok then
		sendState(player, why)
		return
	end
	orders[player] = { spec = spec, pay = pay, at = t }
	sendState(player)
end

-- ===== abandono e destruição =====
local function watchStep(dt: number)
	local folder = workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local people: { Vector3 } = {}
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and alive(p) then
			table.insert(people, root.Position)
		end
	end
	local near = R.abandonNearM / M
	for _, m in folder:GetChildren() do
		local by = m:GetAttribute("BoughtBy")
		if not (m:IsA("Model") and by ~= nil) then
			continue
		end
		local owner = Players:GetPlayerByUserId(by :: number)
		if m:GetAttribute("Destroyed") then
			if not seenDestroyed[m] then
				seenDestroyed[m] = true
				idle[m] = nil
				if owner then
					notice(
						owner,
						string.format(
							"Seu %s foi destruído (sem reembolso)",
							specName(tostring(m:GetAttribute("Spec")))
						)
					)
					sendState(owner)
				end
			end
			continue
		end
		local busy = false
		for _, s in m:GetChildren() do
			if s:IsA("Seat") and s.Occupant then
				busy = true
				break
			end
		end
		local ch = m:FindFirstChild("Chassis") :: BasePart?
		if not busy and ch then
			for _, pos in people do
				local d = Vector3.new(pos.X - ch.Position.X, 0, pos.Z - ch.Position.Z).Magnitude
				if d <= near then
					busy = true
					break
				end
			end
		end
		local n, gone = CompraVeiculo.idleStep(idle[m] or 0, dt, busy)
		idle[m] = n
		if gone then
			idle[m] = nil
			if owner then
				notice(
					owner,
					string.format("Seu %s ficou abandonado e foi recolhido", specName(tostring(m:GetAttribute("Spec"))))
				)
			end
			m:Destroy()
			if owner then
				sendState(owner)
			end
		end
	end
	for m in idle do
		if m.Parent == nil then
			idle[m] = nil
		end
	end
	-- reserva sem recibo (prompt fechado sem resposta): solta depois do prazo
	local t = os.clock()
	for p, r in reserves do
		if t - r.at > R.reserveS + 30 then
			reserves[p] = nil
			sendState(p)
		end
	end
end

-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevCompra", X) no primeiro jogador:
--   "m151" / "m35" / "peugeot403": em campo, procura o lugar agora e entrega sem cobrar (escreve no
--   Output onde ficou ou por que não achou); morto, arma o pedido sem cobrança para a próxima
--   inserção. "m151:ci" arma um pedido de verdade em CI. "abandono": os comprados ficam a 5 s de
--   sumir. "estado": imprime pedidos, reservas e contagens.
local function devCompra()
	local want = workspace:GetAttribute("VT65DevCompra")
	if type(want) ~= "string" then
		return
	end
	workspace:SetAttribute("VT65DevCompra", nil)
	local player = Players:GetPlayers()[1]
	if not player then
		warn("[VT65 TESTE] VT65DevCompra: nenhum jogador")
		return
	end
	if want == "abandono" then
		for m in idle do
			idle[m] = R.abandonS - 5
		end
		print("[VT65 TESTE] VT65DevCompra: comprados somem em 5 s se ninguém chegar perto")
		return
	elseif want == "estado" then
		local f = player:GetAttribute("Faction")
		local mine, team = counts(player, if type(f) == "string" then f else nil)
		local o, r = orders[player], reserves[player]
		print(
			"[VT65 TESTE] VT65DevCompra:",
			"pedido",
			if o then o.spec .. "/" .. o.pay else "-",
			"reserva",
			if r then r.spec else "-",
			"meus",
			mine,
			"lado",
			team
		)
		return
	end
	local spec, pay = string.match(want, "^([%w_]+):?(%a*)$")
	if not (spec and CompraVeiculo.ITEMS[spec]) then
		warn("[VT65 TESTE] VT65DevCompra: ficha desconhecida", want)
		return
	end
	local item = CompraVeiculo.ITEMS[spec :: string]
	player:SetAttribute("Faction", item.faction)
	if pay == "ci" then
		orders[player] = { spec = spec :: string, pay = "ci", at = os.clock() }
		sendState(player)
		print("[VT65 TESTE] VT65DevCompra: pedido em CI armado para a próxima inserção")
		return
	end
	local char = player.Character
	if char and alive(player) then
		local r, why = findSpot(char, spec :: string, item.faction)
		if r then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
			local d = Vector3.new(r.x - root.Position.X, 0, r.z - root.Position.Z).Magnitude * M
			deliver(player, r)
			print(string.format("[VT65 TESTE] VT65DevCompra: %s a %.1f m (sem cobrar)", spec :: string, d))
		else
			print("[VT65 TESTE] VT65DevCompra: não achou lugar:", why)
		end
	else
		orders[player] = { spec = spec :: string, pay = "dev", at = os.clock() }
		sendState(player)
		print("[VT65 TESTE] VT65DevCompra: pedido sem cobrança armado para a próxima inserção")
	end
end

function CompraVeiculoService.start(vehicleApi: Api)
	api = vehicleApi
	CommerceService.vehicleReady = reserveValid
	CommerceService.vehicleGrant = onGrant
	Net.event("Vehicle_Order").OnServerEvent:Connect(onOrder)
	-- o ponto escolhido na carta (o SpawnService decide se nasce; aqui só se anota)
	Net.event("Spawn_Request").OnServerEvent:Connect(function(player, pointId)
		if type(pointId) == "string" and #pointId < 80 then
			lastPoint[player] = { id = pointId, at = os.clock() }
		end
	end)
	Combatants.Added:Connect(function(entry: Combatants.Entry)
		local player = entry.player
		if player and orders[player] then
			task.delay(R.deliverDelayS, tryDeliver, player, entry.model)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, bought: boolean)
			local player = Players:GetPlayerByUserId(userId)
			local r = player and reserves[player]
			if player and r and not bought and CompraVeiculo.productId(r.spec) == productId then
				reserves[player] = nil
				notice(player, "Compra cancelada: nada foi cobrado")
				sendState(player)
			end
		end
	)
	local function arm(player: Player)
		player:GetAttributeChangedSignal("Faction"):Connect(function()
			orders[player] = nil
		end)
	end
	for _, p in Players:GetPlayers() do
		arm(p)
	end
	Players.PlayerAdded:Connect(arm)
	Players.PlayerRemoving:Connect(function(p)
		orders[p] = nil
		reserves[p] = nil
		lastDeliver[p] = nil
		lastPoint[p] = nil
		lastReq[p] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 then
			watchStep(acc)
			acc = 0
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevCompra"):Connect(function()
			task.spawn(devCompra)
		end)
	end
end

return CompraVeiculoService
