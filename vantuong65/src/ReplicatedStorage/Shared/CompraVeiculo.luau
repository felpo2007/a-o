--!strict
-- Veículo ao nascer (D-103; pedido do dono, 2026-11-12: "coloque a opção de comprar um veículo quando
-- nascer e ele spawnar do seu lado"). Regras puras, testadas no Lune (tests/luau/compraveiculo.luau);
-- o servidor é o ServerScriptService/Modules/CompraVeiculoService e a tela, o
-- Controllers/CompraVeiculo.client (na carta de inserção).
-- - Só viaturas: EUA M151 e M35, VC Peugeot 403. Blindado e helicóptero ficam fora: os EUA já têm 6
--   nos depósitos (M48, Ontos, 2 LVTP-5, 2 UH-34D, renascem em 180 s) e o VC de 1965 não tinha
--   nenhum; vender mais seria comprar vantagem contra um lado sem resposta.
-- - Paga em créditos de intendência (CI) ou em Robux (um Developer Product por viatura, Commerce).
--   O CI só sai depois que o servidor acha o lugar; em Robux, o prompt só abre com o lugar já achado
--   e reservado. Sem lugar: avisa e nada é cobrado.
-- - Um vivo por jogador, teto por lado, espera entre compras, some abandonado, destruído não volta.
-- - Só sai em base e ponto de reunião (QG, reunião de setor, reunião avançada): nunca em túnel, no
--   companheiro, no ponto do squad ou onde caiu. Lá o pedido fica para a próxima inserção.
-- Números marcados PLACEHOLDER: proposta, a ajustar no teste.
local Commerce = require(script and (script :: any).Parent.Commerce or "./Commerce") :: any

local CompraVeiculo = {}

export type Item = {
	spec: string,
	faction: string,
	credits: number, -- preço em CI
	key: string, -- chave do Developer Product em Commerce.IDS
}

CompraVeiculo.ITEMS = {
	m151 = { spec = "m151", faction = "US", credits = 150, key = "PRODUCT_VEH_M151" }, -- PLACEHOLDER
	m35 = { spec = "m35", faction = "US", credits = 250, key = "PRODUCT_VEH_M35" }, -- PLACEHOLDER
	peugeot403 = { spec = "peugeot403", faction = "VC", credits = 150, key = "PRODUCT_VEH_PEUGEOT403" }, -- PLACEHOLDER
} :: { [string]: Item }

-- ordem na tela, por lado
CompraVeiculo.ORDER = {
	US = { "m151", "m35" },
	VC = { "peugeot403" },
} :: { [string]: { string } }

CompraVeiculo.RULES = {
	perPlayer = 1, -- comprado vivo por jogador
	teamCap = 6, -- PLACEHOLDER: comprados vivos por lado ao mesmo tempo
	cooldownS = 120, -- PLACEHOLDER: entre duas entregas do mesmo jogador
	abandonS = 90, -- parado sem ninguém dentro nem perto: some
	abandonNearM = 30, -- PLACEHOLDER: "perto" (qualquer soldado vivo)
	reserveS = 90, -- PLACEHOLDER: lugar reservado esperando o recibo em Robux
	deliverDelayS = 1.0, -- depois de nascer (o corpo assenta no chão)
	ringsM = { 4, 5.5, 7, 8.5, 10 }, -- distância do centro do veículo a quem nasceu (pedido: 4 a 10 m)
	gapM = 1.5, -- PLACEHOLDER: folga mínima entre o soldado e a caixa do veículo
	flatM = 0.6, -- PLACEHOLDER: desnível máximo do chão sob a caixa
	levelM = 2.0, -- PLACEHOLDER: chão do veículo a no máximo isto do pé de quem nasceu
	clearM = 0.3, -- PLACEHOLDER: margem da caixa livre (casa, árvore, veículo, gente)
	ciPerRobux = 100, -- recibo sem entrega vira CI nesta taxa (pacote de 500 CI = 5 R$, Commerce)
}

-- pontos de inserção onde o veículo sai (prefixo do id do SpawnService/FrontService)
local ALLOWED = { "rally:", "forward:" }

-- Direção (no plano) para onde aponta um chassi de rumo `yaw` (a frente do chassi é -Z).
function CompraVeiculo.facing(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end

-- Rumo do chassi que olha de (x, z) para (tx, tz).
function CompraVeiculo.yawToward(x: number, z: number, tx: number, tz: number): number
	local dx, dz = tx - x, tz - z
	if dx * dx + dz * dz < 1e-9 then
		return 0
	end
	return math.atan2(-dx, -dz)
end

-- Ponto local da caixa (x na largura, z no comprimento) -> plano do mundo, como CFrame.Angles(0, yaw, 0).
function CompraVeiculo.toWorld(lx: number, lz: number, yaw: number): (number, number)
	local c, s = math.cos(yaw), math.sin(yaw)
	return lx * c + lz * s, -lx * s + lz * c
end

-- Distância (no plano) de um ponto até a caixa L x W centrada em (cx, cz), de rumo `yaw`. 0 = dentro.
function CompraVeiculo.gap(px: number, pz: number, cx: number, cz: number, yaw: number, L: number, W: number): number
	local wx, wz = px - cx, pz - cz
	local c, s = math.cos(yaw), math.sin(yaw)
	local lx, lz = wx * c - wz * s, wx * s + wz * c
	local dx = math.max(math.abs(lx) - W / 2, 0)
	local dz = math.max(math.abs(lz) - L / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- rumos em volta de quem nasceu, relativos à frente do veículo: ao lado primeiro (o pedido: "do seu
-- lado"), depois na diagonal, à frente e atrás
local BEARINGS = { 90, -90, 60, -60, 120, -120, 30, -30, 150, -150, 0, 180 }

export type Spot = { dx: number, dz: number, distM: number }

-- Lugares candidatos (metros, relativos a quem nasceu), na ordem de preferência: de perto para
-- longe e, em cada anel, ao lado antes. Todos com a folga RULES.gapM até a caixa.
function CompraVeiculo.candidates(yaw: number, L: number, W: number): { Spot }
	local out: { Spot } = {}
	for _, d in CompraVeiculo.RULES.ringsM do
		for _, b in BEARINGS do
			local fx, fz = CompraVeiculo.facing(yaw + math.rad(b))
			local cx, cz = fx * d, fz * d
			if CompraVeiculo.gap(0, 0, cx, cz, yaw, L, W) >= CompraVeiculo.RULES.gapM then
				table.insert(out, { dx = cx, dz = cz, distM = d })
			end
		end
	end
	return out
end

-- Pontos de prova do chão sob a caixa (metros, no referencial da caixa): cantos, meios dos lados,
-- centro e, nos compridos, os quartos.
function CompraVeiculo.footprint(L: number, W: number): { { number } }
	local hx, hz = W / 2, L / 2
	local out = {
		{ 0, 0 },
		{ -hx, -hz },
		{ hx, -hz },
		{ -hx, hz },
		{ hx, hz },
		{ -hx, 0 },
		{ hx, 0 },
		{ 0, -hz },
		{ 0, hz },
	}
	if L > 4 then
		for _, q in { -hz / 2, hz / 2 } do
			table.insert(out, { -hx, q })
			table.insert(out, { hx, q })
		end
	end
	return out
end

-- Chão sob a caixa (alturas em metros de cada ponto de prova): plano o bastante e no nível do pé.
function CompraVeiculo.groundOk(heights: { number }, footY: number): (boolean, string?)
	if #heights == 0 then
		return false, "sem chão"
	end
	local lo, hi, sum = math.huge, -math.huge, 0
	for _, h in heights do
		lo, hi, sum = math.min(lo, h), math.max(hi, h), sum + h
	end
	if hi - lo > CompraVeiculo.RULES.flatM then
		return false, "torto"
	end
	if math.abs(sum / #heights - footY) > CompraVeiculo.RULES.levelM then
		return false, "desnível"
	end
	return true, nil
end

-- O veículo sai neste ponto de inserção? (id do Spawn_Request)
function CompraVeiculo.pointAllowed(pointId: string): boolean
	if pointId == "hq" then
		return true
	end
	for _, p in ALLOWED do
		if string.sub(pointId, 1, #p) == p then
			return true
		end
	end
	return false
end

export type Ctx = {
	spec: string,
	faction: string?,
	bot: boolean,
	phase: string, -- "order" (na carta, morto) | "deliver" (acabou de nascer)
	alive: boolean,
	mine: number, -- comprados vivos deste jogador
	team: number, -- comprados vivos do lado
	sinceLast: number?, -- s desde a última entrega deste jogador (nil = nunca)
	pay: string, -- "ci" | "robux"
	credits: number,
	productId: number,
}

-- Pode pedir (na carta) ou receber (ao nascer)? Devolve o motivo da recusa, em texto de tela.
function CompraVeiculo.check(ctx: Ctx): (boolean, string?)
	local item = CompraVeiculo.ITEMS[ctx.spec]
	if ctx.bot then
		return false, "bot"
	end
	if not item or item.faction ~= ctx.faction then
		return false, "Este veículo não é do seu lado"
	end
	if ctx.phase == "order" and ctx.alive then
		return false, "Peça o veículo na carta de inserção, antes de nascer"
	end
	local R = CompraVeiculo.RULES
	if ctx.mine >= R.perPlayer then
		return false, "Você já tem um veículo comprado em campo"
	end
	if ctx.team >= R.teamCap then
		return false, string.format("O seu lado já tem %d veículos comprados em campo", R.teamCap)
	end
	if ctx.sinceLast ~= nil and ctx.sinceLast < R.cooldownS then
		return false, string.format("Espere %d s para pedir outro veículo", math.ceil(R.cooldownS - ctx.sinceLast))
	end
	if ctx.pay == "ci" then
		if ctx.credits < item.credits then
			return false, string.format("Faltam %d CI para este veículo", item.credits - ctx.credits)
		end
	elseif ctx.pay == "robux" then
		if ctx.productId == 0 then
			return false, "A compra em Robux deste veículo ainda não foi liberada"
		end
	else
		return false, "Forma de pagamento inválida"
	end
	return true, nil
end

-- Abandono: `idle` sobe enquanto ninguém está dentro nem perto; passou de RULES.abandonS, some.
function CompraVeiculo.idleStep(idle: number, dt: number, busy: boolean): (number, boolean)
	if busy then
		return 0, false
	end
	local n = idle + dt
	return n, n >= CompraVeiculo.RULES.abandonS
end

-- Recibo em Robux que não pôde virar veículo (lugar perdido, morreu, recibo repetido noutro servidor):
-- vira CI, nunca menos que o preço do veículo em CI.
function CompraVeiculo.refundCredits(spec: string, robuxSpent: number?): number
	local item = CompraVeiculo.ITEMS[spec]
	local base = if item then item.credits else 0
	return math.max(base, math.floor((robuxSpent or 0) * CompraVeiculo.RULES.ciPerRobux))
end

-- ID do Developer Product da viatura (0 = ainda não criado no Roblox)
function CompraVeiculo.productId(spec: string): number
	local item = CompraVeiculo.ITEMS[spec]
	local id = if item then (Commerce.IDS :: any)[item.key] else nil
	return if type(id) == "number" then id else 0
end

-- viatura de um Developer Product (recibo)
function CompraVeiculo.specByKey(key: string): string?
	for spec, item in CompraVeiculo.ITEMS do
		if item.key == key then
			return spec
		end
	end
	return nil
end

return CompraVeiculo
