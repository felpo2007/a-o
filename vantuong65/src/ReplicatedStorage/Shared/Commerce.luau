--!strict
-- Catálogo de monetização SEM VANTAGEM (prompt, Parte 11): só cosméticos históricos, unidade,
-- servidores privados, Premium e apoio. Nenhuma arma, munição, tempo de spawn ou stat à venda.
--
-- IDs: crie cada item no Creator Dashboard (Monetization) e cole o número aqui. ID 0 = desligado
-- (o item some da loja). PREÇOS NÃO FICAM NO CÓDIGO: a loja lê o preço com GetProductInfoAsync
-- para o Managed Pricing (preço regional e teste de preço) funcionar. Sugestões em MONETIZATION.md.
--
-- Regra de neutralidade visual: variações cosméticas não podem mudar silhueta, tamanho nem a
-- cor média do soldado além de ±5% de luminância. Nada de camuflagem "melhor" à venda.
local Commerce = {}

Commerce.IDS = {
	-- Game Passes (compra única)
	PASS_USMC_1965 = 0, -- "Uniformes USMC 1965"
	PASS_VC_1965 = 0, -- "Uniformes da Força Principal 1965"
	PASS_UNIT = 0, -- "Passe de Unidade" (criar unidade/clã, tag, lista)
	PASS_SUPPORTER = 0, -- "Apoiador — Dossiê Starlite"
	-- Developer Products (consumíveis)
	PRODUCT_TIP_SMALL = 0, -- "Apoiar o desenvolvimento (pequeno)"
	PRODUCT_TIP_LARGE = 0, -- "Apoiar o desenvolvimento (grande)"
	-- Experience Subscription (mensal; o criador precisa estar habilitado)
	SUBSCRIPTION_UNIT_RESERVE = "", -- "Reserva da Unidade"; ex.: "EXP-1234567890"
}

export type Pass = { key: string, name: string, description: string }
Commerce.Passes = {
	{
		key = "PASS_USMC_1965",
		name = "Uniformes USMC 1965",
		description = "Capa Mitchell lado nuvem, mangas arregaçadas, toalha no pescoço e frasco de repelente na tira do capacete. Só visual.",
	},
	{
		key = "PASS_VC_1965",
		name = "Uniformes da Força Principal 1965",
		description = "Uniforme verde, capacete de fibra, chapéu de selva e tubo de arroz a tiracolo. Só visual.",
	},
	{
		key = "PASS_UNIT",
		name = "Passe de Unidade",
		description = "Crie uma unidade com nome e tag, convide membros e apareça no relatório pós-ação. Sem vantagem em combate.",
	},
	{
		key = "PASS_SUPPORTER",
		name = "Apoiador — Dossiê Starlite",
		description = "Libera o dossiê histórico (mapas, linha do tempo de 18/08/1965) e a fita de campanha no relatório pós-ação.",
	},
} :: { Pass }

export type Product = { key: string, name: string, description: string, grants: string }
Commerce.Products = {
	{
		key = "PRODUCT_TIP_SMALL",
		name = "Apoiar o desenvolvimento",
		description = "Ajuda a manter o jogo (pesquisa histórica, servidores). Sem recompensa em jogo.",
		grants = "tip",
	},
	{
		key = "PRODUCT_TIP_LARGE",
		name = "Apoiar o desenvolvimento (grande)",
		description = "Ajuda a manter o jogo. Sem recompensa em jogo.",
		grants = "tip",
	},
} :: { Product }

-- unlock: "default" | "pass:<KEY>" | "premium" | "subscription"
export type Cosmetic = { id: string, faction: string, slot: string, name: string, unlock: string, check: string }
Commerce.Cosmetics = {
	-- EUA (USMC, agosto de 1965) — conferir cada item em foto antes do asset final (Parte 9)
	{
		id = "us_cover_leaf",
		faction = "US",
		slot = "helmet",
		name = "Capa Mitchell — lado folha",
		unlock = "default",
		check = "foto",
	},
	{
		id = "us_cover_cloud",
		faction = "US",
		slot = "helmet",
		name = "Capa Mitchell — lado nuvem",
		unlock = "pass:PASS_USMC_1965",
		check = "foto",
	},
	{
		id = "us_cover_faded",
		faction = "US",
		slot = "helmet",
		name = "Capa Mitchell desbotada",
		unlock = "premium",
		check = "foto",
	},
	{
		id = "us_utility_down",
		faction = "US",
		slot = "uniform",
		name = "Utilitário OG-107",
		unlock = "default",
		check = "foto",
	},
	{
		id = "us_utility_rolled",
		faction = "US",
		slot = "uniform",
		name = "OG-107, mangas arregaçadas",
		unlock = "pass:PASS_USMC_1965",
		check = "foto",
	},
	{ id = "us_none", faction = "US", slot = "extra", name = "Sem acessório", unlock = "default", check = "-" },
	{
		id = "us_towel",
		faction = "US",
		slot = "extra",
		name = "Toalha verde no pescoço",
		unlock = "pass:PASS_USMC_1965",
		check = "foto",
	},
	{
		id = "us_repellent_band",
		faction = "US",
		slot = "extra",
		name = "Repelente na tira do capacete",
		unlock = "pass:PASS_USMC_1965",
		check = "foto",
	},
	-- VC (1º Regimento, força principal) — uniforme cáqui ou verde, não só "pijama preto"
	{ id = "vc_khaki", faction = "VC", slot = "uniform", name = "Uniforme cáqui", unlock = "default", check = "foto" },
	{
		id = "vc_green",
		faction = "VC",
		slot = "uniform",
		name = "Uniforme verde",
		unlock = "pass:PASS_VC_1965",
		check = "foto",
	},
	{ id = "vc_bare", faction = "VC", slot = "helmet", name = "Sem cobertura", unlock = "default", check = "-" },
	{
		id = "vc_pith_helmet",
		faction = "VC",
		slot = "helmet",
		name = "Capacete de fibra",
		unlock = "pass:PASS_VC_1965",
		check = "foto",
	},
	{
		id = "vc_jungle_hat",
		faction = "VC",
		slot = "helmet",
		name = "Chapéu de selva",
		unlock = "pass:PASS_VC_1965",
		check = "foto",
	},
	{ id = "vc_none", faction = "VC", slot = "extra", name = "Sem acessório", unlock = "default", check = "-" },
	{
		id = "vc_rice_tube",
		faction = "VC",
		slot = "extra",
		name = "Tubo de arroz a tiracolo",
		unlock = "pass:PASS_VC_1965",
		check = "foto",
	},
	{
		id = "vc_scarf",
		faction = "VC",
		slot = "extra",
		name = "Lenço xadrez",
		unlock = "premium",
		check = "foto + consultor",
	},
	-- assinatura: um item histórico a cada temporada (rotativo)
	{
		id = "us_ribbon_reserve",
		faction = "US",
		slot = "extra",
		name = "Fita da Reserva (assinatura)",
		unlock = "subscription",
		check = "-",
	},
	{
		id = "vc_ribbon_reserve",
		faction = "VC",
		slot = "extra",
		name = "Fita da Reserva (assinatura)",
		unlock = "subscription",
		check = "-",
	},
} :: { Cosmetic }

export type Ownership = { passes: { [string]: boolean }, premium: boolean, subscription: boolean }

function Commerce.isUnlocked(c: Cosmetic, own: Ownership): boolean
	if c.unlock == "default" then
		return true
	elseif c.unlock == "premium" then
		return own.premium
	elseif c.unlock == "subscription" then
		return own.subscription
	end
	local key = string.match(c.unlock, "^pass:(.+)$")
	return key ~= nil and own.passes[key] == true
end

function Commerce.unlockedIds(own: Ownership): { string }
	local out = {}
	for _, c in Commerce.Cosmetics do
		if Commerce.isUnlocked(c, own) then
			table.insert(out, c.id)
		end
	end
	return out
end

function Commerce.find(id: string): Cosmetic?
	for _, c in Commerce.Cosmetics do
		if c.id == id then
			return c
		end
	end
	return nil
end

function Commerce.defaultLoadout(faction: string): { [string]: string }
	local out = {}
	for _, c in Commerce.Cosmetics do
		if c.faction == faction and c.unlock == "default" then
			out[c.slot] = c.id
		end
	end
	return out
end

-- Valida um pedido de equipar (servidor): item existe, é da facção/slot e está liberado.
function Commerce.canEquip(id: string, faction: string, slot: string, own: Ownership): boolean
	local c = Commerce.find(id)
	return c ~= nil and c.faction == faction and c.slot == slot and Commerce.isUnlocked(c, own)
end

function Commerce.productKeyById(productId: number): string?
	for key: string, id: any in Commerce.IDS :: any do
		if type(id) == "number" and id ~= 0 and id == productId and string.sub(key, 1, 8) == "PRODUCT_" then
			return key
		end
	end
	return nil
end

-- Eventos de análise aceitos do cliente (funil da loja). Lista fechada: o cliente não inventa nomes.
Commerce.FunnelSteps = { "store_open", "item_view", "prompt", "purchase" }

return Commerce
