--!strict
-- Testes do veículo ao nascer (D-103, Lune): catálogo, regras do pedido, onde sai, lugar ao lado,
-- chão, abandono, recibo e as ligações no jogo. Uso: lune run tests/luau/compraveiculo.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local CompraVeiculo = require(S .. "CompraVeiculo") :: any
local Commerce = require(S .. "Commerce") :: any
local Vehicles = require(S .. "Vehicles") :: any

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f (tol %.4f)", msg or "", a, b, tol))
end

local R = CompraVeiculo.RULES

local function ctx(over: { [string]: any }?): any
	local c = {
		spec = "m151",
		faction = "US",
		bot = false,
		phase = "order",
		alive = false,
		mine = 0,
		team = 0,
		sinceLast = nil,
		pay = "ci",
		credits = 1000,
		productId = 0,
	}
	for k, v in over or {} do
		c[k] = v
	end
	return c
end

test("catálogo: só viaturas, do lado certo, com produto em Robux e preço em CI", function()
	local seen = 0
	for spec, item in CompraVeiculo.ITEMS do
		local s = Vehicles.SPECS[spec]
		assert(s, "ficha " .. spec)
		assert(s.kind == "wheeled", "só viatura (sem blindado nem helicóptero): " .. spec)
		assert(s.faction == item.faction, "lado de " .. spec)
		assert(item.credits > 0 and item.spec == spec, spec)
		assert(type(Commerce.IDS[item.key]) == "number", "chave em Commerce.IDS: " .. item.key)
		local vp = Commerce.vehicleProduct(item.key)
		assert(vp and vp.spec == spec and vp.suggestedRobux > 0 and #vp.description > 20, item.key)
		assert(CompraVeiculo.specByKey(item.key) == spec)
		assert(table.find(CompraVeiculo.ORDER[item.faction], spec), "na tela do lado: " .. spec)
		seen += 1
	end
	assert(seen == 3 and #Commerce.VehicleProducts == 3)
	assert(#CompraVeiculo.ORDER.US == 2 and #CompraVeiculo.ORDER.VC == 1)
	-- ID 0 = ainda não criado no Roblox: sem Robux, só CI
	for _, item in CompraVeiculo.ITEMS do
		if Commerce.IDS[item.key] == 0 then
			assert(CompraVeiculo.productId(item.spec) == 0)
		end
	end
	assert(Commerce.productKeyById(0) == nil)
	-- a lista de itens de jogo da D-72 não mudou (o veículo tem catálogo próprio)
	local n = 0
	for _ in Commerce.GAMEPLAY do
		n += 1
	end
	assert(n == 3 and #Commerce.Products == 3)
end)

test("pedido: regras (bot, lado, morto na carta, um por jogador, teto do lado, espera, saldo)", function()
	assert(CompraVeiculo.check(ctx()))
	assert(select(2, CompraVeiculo.check(ctx({ bot = true }))) == "bot", "bot não compra")
	assert(not CompraVeiculo.check(ctx({ faction = "VC" })), "M151 não é do VC")
	assert(CompraVeiculo.check(ctx({ faction = "VC", spec = "peugeot403" })))
	assert(not CompraVeiculo.check(ctx({ spec = "m48a3" })), "blindado não se compra")
	assert(not CompraVeiculo.check(ctx({ spec = "uh34d" })), "helicóptero não se compra")
	assert(not CompraVeiculo.check(ctx({ alive = true })), "o pedido é na carta, morto")
	assert(CompraVeiculo.check(ctx({ alive = true, phase = "deliver" })), "ao nascer já está vivo")
	assert(not CompraVeiculo.check(ctx({ mine = R.perPlayer })), "um vivo por jogador")
	assert(not CompraVeiculo.check(ctx({ team = R.teamCap })), "teto do lado")
	assert(CompraVeiculo.check(ctx({ team = R.teamCap - 1 })))
	local ok, why = CompraVeiculo.check(ctx({ sinceLast = R.cooldownS - 30 }))
	assert(not ok and string.find(why, "30 s", 1, true), why)
	assert(CompraVeiculo.check(ctx({ sinceLast = R.cooldownS })))
	local price = CompraVeiculo.ITEMS.m151.credits
	ok, why = CompraVeiculo.check(ctx({ credits = price - 20 }))
	assert(not ok and string.find(why, "20 CI", 1, true), why)
	assert(CompraVeiculo.check(ctx({ credits = price })))
	-- Robux: só com o produto criado; o saldo de CI não importa
	assert(not CompraVeiculo.check(ctx({ pay = "robux", productId = 0 })))
	assert(CompraVeiculo.check(ctx({ pay = "robux", productId = 123, credits = 0 })))
	assert(not CompraVeiculo.check(ctx({ pay = "pix" })))
end)

test("onde sai: QG e pontos de reunião; nunca túnel, companheiro, squad ou onde caiu", function()
	for _, id in { "hq", "rally:3", "forward:2:3" } do
		assert(CompraVeiculo.pointAllowed(id), id)
	end
	for _, id in { "tunnel:T4", "vcfront:T2", "mate:123", "squad:US:A", "inplace", "lz:7", "temp:Ponte", "" } do
		assert(not CompraVeiculo.pointAllowed(id), id)
	end
end)

test("rumo: chassi de frente para -Z, olha o objetivo; caixa e mundo no mesmo giro", function()
	for _, t in { { 10, 0 }, { 0, 10 }, { -7, -3 }, { 3, -9 } } do
		local yaw = CompraVeiculo.yawToward(0, 0, t[1], t[2])
		local fx, fz = CompraVeiculo.facing(yaw)
		local m = math.sqrt(t[1] ^ 2 + t[2] ^ 2)
		near(fx, t[1] / m, 1e-9, "fx")
		near(fz, t[2] / m, 1e-9, "fz")
		-- a frente do chassi (0, -1 na caixa) é a mesma direção
		local wx, wz = CompraVeiculo.toWorld(0, -1, yaw)
		near(wx, fx, 1e-9, "toWorld x")
		near(wz, fz, 1e-9, "toWorld z")
	end
	assert(CompraVeiculo.yawToward(5, 5, 5, 5) == 0)
end)

test("folga até a caixa (ponto dentro = 0; de lado, de frente e na quina)", function()
	-- caixa 4 x 2 m em (0, 0), rumo 0: largura em X, comprimento em Z
	assert(CompraVeiculo.gap(0.5, 1, 0, 0, 0, 4, 2) == 0)
	near(CompraVeiculo.gap(3, 0, 0, 0, 0, 4, 2), 2, 1e-9, "de lado")
	near(CompraVeiculo.gap(0, -5, 0, 0, 0, 4, 2), 3, 1e-9, "de frente")
	near(CompraVeiculo.gap(4, 5, 0, 0, 0, 4, 2), math.sqrt(9 + 9), 1e-9, "quina")
	-- girada 90°: o comprimento passa para X
	near(CompraVeiculo.gap(3, 0, 0, 0, math.rad(90), 4, 2), 1, 1e-9, "girada")
end)

test("lugar ao lado: 4 a 10 m, folga do soldado, ao lado primeiro, nas três viaturas", function()
	for spec in CompraVeiculo.ITEMS do
		local s = Vehicles.SPECS[spec]
		for _, yaw in { 0, 1.1, -2.5 } do
			local list = CompraVeiculo.candidates(yaw, s.lengthM, s.widthM)
			assert(#list >= 30, spec .. ": poucos lugares " .. #list)
			for _, c in list do
				local d = math.sqrt(c.dx * c.dx + c.dz * c.dz)
				assert(d >= 4 - 1e-6 and d <= 10 + 1e-6, spec .. " fora de 4-10 m: " .. d)
				near(d, c.distM, 1e-6)
				local g = CompraVeiculo.gap(0, 0, c.dx, c.dz, yaw, s.lengthM, s.widthM)
				assert(g >= R.gapM - 1e-9, spec .. " em cima do soldado")
			end
			-- o primeiro fica ao lado (perpendicular à frente), não à frente nem atrás
			local fx, fz = CompraVeiculo.facing(yaw)
			local c1 = list[1]
			local cosA = (c1.dx * fx + c1.dz * fz) / c1.distM
			assert(math.abs(cosA) < 0.05, spec .. ": o primeiro não está ao lado")
			-- de perto para longe
			for i = 2, #list do
				assert(list[i].distM >= list[i - 1].distM)
			end
		end
	end
	-- o M35 (7 m) não cabe a 4 m à frente sem passar por cima do soldado
	local s = Vehicles.SPECS.m35
	for _, c in CompraVeiculo.candidates(0, s.lengthM, s.widthM) do
		local fx, fz = CompraVeiculo.facing(0)
		local ahead = (c.dx * fx + c.dz * fz) / c.distM
		assert(not (c.distM == 4 and ahead > 0.99), "M35 a 4 m à frente")
	end
end)

test("chão: provas na caixa inteira, plano e no nível do pé", function()
	assert(#CompraVeiculo.footprint(3.35, 1.6) == 9)
	local fp = CompraVeiculo.footprint(6.98, 2.36)
	assert(#fp == 13)
	local corners = 0
	for _, p in fp do
		if math.abs(p[1]) == 2.36 / 2 and math.abs(p[2]) == 6.98 / 2 then
			corners += 1
		end
	end
	assert(corners == 4)
	assert(CompraVeiculo.groundOk({ 10, 10.2, 10.1, 9.9 }, 10))
	assert(select(2, CompraVeiculo.groundOk({ 10, 10 + R.flatM + 0.1 }, 10)) == "torto")
	assert(select(2, CompraVeiculo.groundOk({ 13, 13 }, 10)) == "desnível", "barranco acima do pé")
	assert(not CompraVeiculo.groundOk({}, 10))
end)

test("abandono: 90 s sem ninguém dentro nem perto; gente perto zera", function()
	local idle, gone = 0, false
	for _ = 1, 89 do
		idle, gone = CompraVeiculo.idleStep(idle, 1, false)
		assert(not gone)
	end
	idle, gone = CompraVeiculo.idleStep(idle, 1, false)
	assert(gone and R.abandonS == 90)
	idle, gone = CompraVeiculo.idleStep(80, 1, true)
	assert(idle == 0 and not gone)
end)

test("recibo sem entrega vira CI (nunca menos que o preço do veículo)", function()
	local price = CompraVeiculo.ITEMS.m35.credits
	assert(CompraVeiculo.refundCredits("m35", nil) == price)
	assert(CompraVeiculo.refundCredits("m35", 1) == price)
	assert(CompraVeiculo.refundCredits("m35", 25) == 25 * R.ciPerRobux)
	assert(CompraVeiculo.refundCredits("nada", 0) == 0)
	-- a taxa é a do pacote de 500 CI
	local pack = Commerce.campaignProduct("PRODUCT_CREDITS_500")
	assert(pack and pack.amount / pack.suggestedRobux == R.ciPerRobux)
end)

test("ligações no jogo: recibo, entrega, cobrança depois do lugar, tela e gancho", function()
	local net = fs.readFile("src/ReplicatedStorage/Shared/Net.luau")
	assert(string.find(net, '"Vehicle_Order"', 1, true) and string.find(net, '"Vehicle_OrderState"', 1, true))
	local cs = fs.readFile("src/ServerScriptService/Modules/CommerceService.luau")
	local route = string.find(cs, "return vehicleReceipt(player, info, vp)", 1, true)
	local generic = string.find(cs, "local grants = Commerce.productGrants(key)", 1, true)
	assert(route and generic and route < generic, "recibo do veículo antes do caminho genérico")
	assert(string.find(cs, "PlayerData.applyReceipt(player, tostring(info.PurchaseId)", 1, true))
	local vs = fs.readFile("src/ServerScriptService/Modules/VehicleService.luau")
	assert(string.find(vs, "CompraVeiculoService).start(", 1, true), "o VehicleService começa a compra")
	for _, fn in { "botBoard", "botLeave", "botInput", "botState", "botFire", "mainReady", "vehicles", "seat" } do
		assert(string.find(vs, "function VehicleService." .. fn .. "(", 1, true), "API dos bots: " .. fn)
	end
	local sv = fs.readFile("src/ServerScriptService/Modules/CompraVeiculoService.luau")
	local find = string.find(sv, "local r, reason = findSpot(char, o.spec, faction)", 1, true)
	local spend = string.find(sv, "ProgressionService.spendCredits(player, item.credits)", 1, true)
	local prompt = string.find(sv, "MarketplaceService:PromptProductPurchase(player, id)", 1, true)
	assert(find and spend and prompt and find < spend and find < prompt, "só cobra depois de achar o lugar")
	assert(string.find(sv, 'SetAttribute("BoughtBy"', 1, true))
	assert(string.find(sv, "CommerceService.vehicleReady = reserveValid", 1, true))
	local ds = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/DeployScreen.luau")
	assert(string.find(ds, 'Bus.fire("insercao_painel"', 1, true), "gancho na pasta de inserção")
	local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/CompraVeiculo.client.luau")
	assert(string.find(ui, 'Bus.on("insercao_painel"', 1, true) and string.find(ui, '"Vehicle_Order"', 1, true))
	assert(string.find(ui, 'Input.on("map_mark"', 1, true), "controle: X abre o painel")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
