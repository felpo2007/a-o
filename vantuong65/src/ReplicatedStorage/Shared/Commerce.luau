--!strict
-- Catálogo de monetização (prompt, Parte 11): cosméticos históricos, unidade, servidores privados,
-- Premium e apoio. Nenhuma arma, munição, tempo de spawn ou stat à venda.
-- EXCEÇÃO decidida pelo dono em 2026-11-11 ("quero usar robux"), só para os itens de Commerce.GAMEPLAY:
--   - os dois kits de equipamento (Game Pass): também saem de graça num posto alto e, item a item,
--     com os créditos de intendência ganhos jogando (Shared/Progression);
--   - o renascer onde caiu (Developer Product): não encurta a espera de spawn (paga-se o lugar) e
--     também pode ser pago com créditos.
-- O teste "catálogo só aceita estes itens de jogo" (tests/luau/f2.luau) barra qualquer outro.
--
-- IDs: crie cada item no Creator Dashboard (Monetization) e cole o número aqui. ID 0 = desligado
-- (o item some da loja). PREÇOS NÃO FICAM NO CÓDIGO: a loja lê o preço com GetProductInfoAsync
-- para o Managed Pricing (preço regional e teste de preço) funcionar. Sugestões em MONETIZATION.md.
--
-- Regra de neutralidade visual: variações cosméticas não podem mudar silhueta, tamanho nem a
-- cor média do soldado além de ±5% de luminância. Nada de camuflagem "melhor" à venda.
-- EXCEÇÃO do dono (2026-11-11): as skins de Shared/Skins (arma, uniforme e camuflagem de mato) ficam
-- fora desta regra, com catálogo e IDs próprios; a camuflagem de mato dá vantagem contra os bots
-- ("vantagem comprada" autorizada). Commerce.GAMEPLAY continua com os 3 itens da D-72.
local Commerce = {}

Commerce.IDS = {
	-- Game Passes (compra única)
	PASS_USMC_1965 = 2078234463, -- "Uniformes USMC 1965"
	PASS_VC_1965 = 2078306456, -- "Uniformes da Força Principal 1965"
	PASS_UNIT = 2079194497, -- "Passe de Unidade" (criar unidade/clã, tag, lista)
	PASS_SUPPORTER = 2078948463, -- "Apoiador — Dossiê Starlite"
	PASS_KIT_VETERAN = 2079866464, -- "Kit Veterano" (equipamento nível 1; decisão do dono, 2026-11-11)
	PASS_KIT_ELITE = 2079338501, -- "Kit de Elite" (equipamento nível 2, inclui o Veterano)
	-- Developer Products (consumíveis)
	PRODUCT_TIP_SMALL = 3730455552, -- "Apoiar o desenvolvimento (pequeno)"
	PRODUCT_TIP_LARGE = 3730455555, -- "Apoiar o desenvolvimento (grande)"
	PRODUCT_RESPAWN_INPLACE = 3730455499, -- "Renascer onde caiu" (decisão do dono, 2026-11-11)
	-- campanha (plano de volta diária, 2026-11-12): Commerce.CampaignPasses / CampaignProducts.
	-- 0 = ainda não criado (o botão some); o tools/roblox_cloud.py create-store cria e grava aqui.
	PASS_SEASON_S1 = 2081672426, -- "Passe de Campanha: Veterano (Temporada 1)"
	PASS_RECRUIT = 2081942423, -- "Pacote de Recruta" (compra única)
	PASS_PERK_SPEED = 2082356430, -- "Pernas de Maratonista"
	PASS_PERK_HEALTH = 2081606414, -- "Couro Duro"
	PASS_PERK_BREATH = 2082974399, -- "Fôlego de Atirador"
	PASS_PERK_RELOAD = 2081582455, -- "Mãos Rápidas"
	PASS_PERK_MEDIC = 2082308430, -- "Socorrista Treinado"
	PASS_PERK_POCKETS = 2082056423, -- "Bolsos Extras"
	PASS_PERK_EAGLE = 2083364414, -- "Olho de Águia"
	PASS_PERK_ALL = 2082956450, -- "Pacote Combatente" (as 7)
	PRODUCT_SEASON_SKIP = 3730606735, -- "Pular um nível do passe"
	PRODUCT_BOOST_XP_1H = 3730606738, -- "XP dobrado por 1 h"
	PRODUCT_BOOST_XP_24H = 3730606739, -- "XP dobrado por 24 h"
	PRODUCT_BOOST_CR_1H = 3730606741, -- "Créditos dobrados por 1 h"
	PRODUCT_CREDITS_500 = 3730606747, -- "500 créditos"
	PRODUCT_CREDITS_1200 = 3730606748, -- "1.200 créditos"
	PRODUCT_CREDITS_3000 = 3730606751, -- "3.000 créditos"
	-- veículo ao nascer (D-103, pedido do dono 2026-11-12): Commerce.VehicleProducts. 0 = ainda não
	-- criado (o botão de Robux some; o de CI continua)
	PRODUCT_VEH_M151 = 3730793969, -- "Veículo ao nascer: M151 MUTT"
	PRODUCT_VEH_M35 = 3730793971, -- "Veículo ao nascer: caminhão M35"
	PRODUCT_VEH_PEUGEOT403 = 3730793973, -- "Veículo ao nascer: Peugeot 403"
	-- Experience Subscription (mensal; o criador precisa estar habilitado)
	SUBSCRIPTION_UNIT_RESERVE = "", -- "Reserva da Unidade"; ex.: "EXP-1234567890"
}

-- kind: nil = cosmético/unidade/apoio; "kit" = equipamento (Commerce.GAMEPLAY). suggestedRobux: só
-- para criar o item no Roblox (a loja lê o preço real ao vivo, por causa do Managed Pricing).
export type Pass = { key: string, name: string, description: string, kind: string?, suggestedRobux: number? }
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
	{
		key = "PASS_KIT_VETERAN",
		name = "Kit Veterano",
		description = "Equipamento nível 1 nos dois lados: bandoleira M2 ou peitoral Tipo 56 (+2 carregadores), cantil extra e estojo de socorro reforçado. Também sai de graça no posto 5 (Sergeant) ou item a item com créditos de intendência.",
		kind = "kit",
		suggestedRobux = 149,
	},
	{
		key = "PASS_KIT_ELITE",
		name = "Kit de Elite",
		description = "Equipamento nível 2 (inclui o Kit Veterano): colete M1955 antiestilhaço e fumaça extra (EUA), granada de cabo e fumaça extras (VC). Também sai de graça no posto 7 (Gunnery Sergeant) ou com créditos de intendência.",
		kind = "kit",
		suggestedRobux = 299,
	},
} :: { Pass }

-- grants: "tip" (apoio, sem nada em jogo) | "respawn" (um renascer onde caiu, guardado no perfil)
export type Product = { key: string, name: string, description: string, grants: string, suggestedRobux: number? }
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
	{
		key = "PRODUCT_RESPAWN_INPLACE",
		name = "Renascer onde caiu",
		description = "Volta a campo no ponto onde você caiu, na mesma espera do spawn normal. Só abre se não houver inimigo a menos de 100 m nem área inimiga travada. Se o renascer ficar impossível, ele fica guardado para a próxima queda.",
		grants = "respawn",
		suggestedRobux = 25,
	},
} :: { Product }

-- Itens de jogo à venda (exceção do dono, 2026-11-11). Lista FECHADA: o teste da F2 recusa qualquer
-- passe ou produto de jogo fora dela.
Commerce.GAMEPLAY = {
	PASS_KIT_VETERAN = "kit",
	PASS_KIT_ELITE = "kit",
	PRODUCT_RESPAWN_INPLACE = "respawn",
} :: { [string]: string }

-- ===== campanha (plano de volta diária, 2026-11-12; autorização do dono: "faça você, tem total
-- autorização") =====
-- Catálogo próprio, fora das listas acima (o teste da F2 guarda a lista da D-72). Regras do plano:
-- nada de caixa-surpresa paga (tudo o que se compra é visto antes), nada de pressão falsa, e as
-- vantagens (Shared/Vantagens) com teto de +12% em combate. suggestedRobux: só para criar o item
-- (a loja lê o preço ao vivo). PLACEHOLDER: preços a ajustar com o teste.
-- kind: "season" (trilha Veterano do passe) | "recruit" (Pacote de Recruta, compra única) |
-- "perk" (uma vantagem) | "perk_bundle" (as 7)
export type CampaignPass = { key: string, name: string, description: string, kind: string, suggestedRobux: number }
Commerce.CampaignPasses = {
	{
		key = "PASS_SEASON_S1",
		name = "Passe de Campanha: Veterano",
		description = "Temporada 1 da Operação Starlite: a trilha Veterano (uniformes, acabamentos, cartões de abate, gestos, música do menu) e 10% a mais de créditos. Quem compra no meio recebe tudo o que já passou.",
		kind = "season",
		suggestedRobux = 399,
	},
	{
		key = "PASS_RECRUIT",
		name = "Pacote de Recruta",
		description = "Uniforme de época, acabamento de arma, 3 dias de XP dobrado e 1.000 créditos. Compra única.",
		kind = "recruit",
		suggestedRobux = 99,
	},
	{
		key = "PASS_PERK_SPEED",
		name = "Pernas de Maratonista",
		description = "+6% de velocidade no trote e na corrida. Vale nos dois lados.",
		kind = "perk",
		suggestedRobux = 199,
	},
	{
		key = "PASS_PERK_HEALTH",
		name = "Couro Duro",
		description = "+12% de vida máxima. Vale nos dois lados.",
		kind = "perk",
		suggestedRobux = 249,
	},
	{
		key = "PASS_PERK_BREATH",
		name = "Fôlego de Atirador",
		description = "Prende a respiração por +60% do tempo e a mira balança 12% menos na luneta.",
		kind = "perk",
		suggestedRobux = 149,
	},
	{
		key = "PASS_PERK_RELOAD",
		name = "Mãos Rápidas",
		description = "Recarga 12% mais rápida. Vale nos dois lados.",
		kind = "perk",
		suggestedRobux = 199,
	},
	{
		key = "PASS_PERK_MEDIC",
		name = "Socorrista Treinado",
		description = "Bandagem e torniquete 35% mais rápidos; o sangramento corre 20% mais devagar.",
		kind = "perk",
		suggestedRobux = 99,
	},
	{
		key = "PASS_PERK_POCKETS",
		name = "Bolsos Extras",
		description = "+1 carregador e +1 granada (soma com os kits).",
		kind = "perk",
		suggestedRobux = 149,
	},
	{
		key = "PASS_PERK_EAGLE",
		name = "Olho de Águia",
		description = "O inimigo que você marca fica 50% mais tempo marcado para o squad.",
		kind = "perk",
		suggestedRobux = 99,
	},
	{
		key = "PASS_PERK_ALL",
		name = "Pacote Combatente",
		description = "As 7 vantagens juntas, com desconto. Nenhum número de combate passa de +12%.",
		kind = "perk_bundle",
		suggestedRobux = 799,
	},
} :: { CampaignPass }

-- grants: "season_skip" (estrelas até o próximo nível) | "boost_xp" / "boost_cr" (amount em
-- segundos) | "credits" (amount de $)
export type CampaignProduct = {
	key: string,
	name: string,
	description: string,
	grants: string,
	amount: number?,
	suggestedRobux: number,
}
Commerce.CampaignProducts = {
	{
		key = "PRODUCT_SEASON_SKIP",
		name = "Pular um nível do passe",
		description = "Sobe um nível do Passe de Campanha na hora (vale para as duas trilhas).",
		grants = "season_skip",
		suggestedRobux = 49,
	},
	{
		key = "PRODUCT_BOOST_XP_1H",
		name = "XP dobrado por 1 h",
		description = "Dobra o XP por 1 hora de relógio, em qualquer servidor. Soma com o fim de semana.",
		grants = "boost_xp",
		amount = 3600,
		suggestedRobux = 49,
	},
	{
		key = "PRODUCT_BOOST_XP_24H",
		name = "XP dobrado por 24 h",
		description = "Dobra o XP por 24 horas de relógio, em qualquer servidor.",
		grants = "boost_xp",
		amount = 86400,
		suggestedRobux = 149,
	},
	{
		key = "PRODUCT_BOOST_CR_1H",
		name = "Créditos dobrados por 1 h",
		description = "Dobra os créditos ganhos jogando por 1 hora de relógio.",
		grants = "boost_cr",
		amount = 3600,
		suggestedRobux = 49,
	},
	{
		key = "PRODUCT_CREDITS_500",
		name = "500 créditos",
		description = "500 créditos de intendência para o equipamento e as skins.",
		grants = "credits",
		amount = 500,
		suggestedRobux = 5,
	},
	{
		key = "PRODUCT_CREDITS_1200",
		name = "1.200 créditos",
		description = "1.200 créditos de intendência (20% a mais que o pacote de 500).",
		grants = "credits",
		amount = 1200,
		suggestedRobux = 10,
	},
	{
		key = "PRODUCT_CREDITS_3000",
		name = "3.000 créditos",
		description = "3.000 créditos de intendência (50% a mais que o pacote de 500).",
		grants = "credits",
		amount = 3000,
		suggestedRobux = 20,
	},
} :: { CampaignProduct }

function Commerce.campaignProduct(key: string): CampaignProduct?
	for _, p in Commerce.CampaignProducts do
		if p.key == key then
			return p
		end
	end
	return nil
end

-- ===== veículo ao nascer (D-103; pedido do dono, 2026-11-12: "coloque a opção de comprar um veículo
-- quando nascer e ele spawnar do seu lado") =====
-- Catálogo próprio, fora de Commerce.GAMEPLAY (a lista da D-72 continua com 3). Só viaturas sem arma
-- montada; o mesmo veículo sai com créditos de intendência (Shared/CompraVeiculo: preço em CI e
-- regras). O prompt de Robux só abre com o lugar ao lado do jogador já achado e reservado; recibo
-- que não vira veículo vira CI (CompraVeiculo.refundCredits). suggestedRobux: PLACEHOLDER, só para
-- criar o item (a loja lê o preço ao vivo).
export type VehicleProduct = { key: string, spec: string, name: string, description: string, suggestedRobux: number }
Commerce.VehicleProducts = {
	{
		key = "PRODUCT_VEH_M151",
		spec = "m151",
		name = "Veículo ao nascer: M151 MUTT",
		description = "Um jipe M151 ao seu lado quando você entra em campo por uma base ou ponto de reunião. Um por vez; some se ficar abandonado. Sem lugar livre, nada é cobrado.",
		suggestedRobux = 10,
	},
	{
		key = "PRODUCT_VEH_M35",
		spec = "m35",
		name = "Veículo ao nascer: caminhão M35",
		description = "Um caminhão M35 (motorista e 12 na carroceria) ao seu lado quando você entra em campo por uma base ou ponto de reunião. Um por vez; some se ficar abandonado. Sem lugar livre, nada é cobrado.",
		suggestedRobux = 15,
	},
	{
		key = "PRODUCT_VEH_PEUGEOT403",
		spec = "peugeot403",
		name = "Veículo ao nascer: Peugeot 403",
		description = "Uma picape Peugeot 403 ao seu lado quando você entra em campo por uma base ou ponto de reunião. Um por vez; some se ficar abandonada. Sem lugar livre, nada é cobrado.",
		suggestedRobux = 10,
	},
} :: { VehicleProduct }

function Commerce.vehicleProduct(key: string): VehicleProduct?
	for _, p in Commerce.VehicleProducts do
		if p.key == key then
			return p
		end
	end
	return nil
end

function Commerce.campaignPass(key: string): CampaignPass?
	for _, p in Commerce.CampaignPasses do
		if p.key == key then
			return p
		end
	end
	return nil
end

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
	-- recompensa diária (unlock "daily"): só saem da caderneta de serviço (dias 3 e 7), nunca à venda.
	-- Como os outros "extra", o Characters ainda não os desenha: aparecem no armário até a arte chegar.
	{
		id = "us_zippo",
		faction = "US",
		slot = "extra",
		name = "Isqueiro Zippo gravado",
		unlock = "daily",
		check = "foto",
	},
	{
		id = "us_cigarette_band",
		faction = "US",
		slot = "extra",
		name = "Maço de cigarros na tira do capacete",
		unlock = "daily",
		check = "foto",
	},
	{
		id = "vc_tire_sandals",
		faction = "VC",
		slot = "extra",
		name = "Dép lốp (sandálias de pneu)",
		unlock = "daily",
		check = "foto",
	},
	{
		id = "vc_mess_tin",
		faction = "VC",
		slot = "extra",
		name = "Marmita cà mèn no cinto",
		unlock = "daily",
		check = "foto",
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

-- earned: cosméticos ganhos em jogo (recompensa diária), id -> true; opcional (perfis antigos)
export type Ownership = {
	passes: { [string]: boolean },
	premium: boolean,
	subscription: boolean,
	earned: { [string]: boolean }?,
}

function Commerce.isUnlocked(c: Cosmetic, own: Ownership): boolean
	if c.unlock == "default" then
		return true
	elseif c.unlock == "premium" then
		return own.premium
	elseif c.unlock == "subscription" then
		return own.subscription
	elseif c.unlock == "daily" then
		local e = own.earned
		return e ~= nil and e[c.id] == true
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

function Commerce.passKeyById(passId: number): string?
	for _, list in { Commerce.Passes :: { any }, Commerce.CampaignPasses :: { any } } do
		for _, pass in list do
			local id = (Commerce.IDS :: any)[pass.key]
			if type(id) == "number" and id ~= 0 and id == passId then
				return pass.key
			end
		end
	end
	return nil
end

-- o que um produto entrega ("tip" | "respawn"), pela chave
function Commerce.productGrants(key: string): string?
	for _, p in Commerce.Products do
		if p.key == key then
			return p.grants
		end
	end
	return nil
end

-- Eventos de análise aceitos do cliente (funil da loja). Lista fechada: o cliente não inventa nomes.
Commerce.FunnelSteps = { "store_open", "item_view", "prompt", "purchase" }

-- ===== Recompensa diária: a caderneta de serviço =====
-- Um selo por dia UTC (o dia é o do relógio do SERVIDOR: os.time() / 86400). A trilha tem 7 dias,
-- os mesmos 7 dias da Operação Starlite (18 a 24 AGO 1965). Regra:
--   - resgate no dia seguinte ao último: a sequência continua (depois do dia 7 volta ao dia 1, e a
--     contagem de dias seguidos continua subindo);
--   - pulou um dia UTC inteiro sem resgatar: a sequência zera e o resgate volta ao dia 1;
--   - o total de dias de serviço e os cosméticos ganhos NUNCA se perdem (só a posição na trilha).
-- Cada selo é um dia de serviço na caderneta e dá créditos de intendência (a moeda ganha jogando,
-- Shared/Progression); os dias 3 e 7 dão também um cosmético que só sai daqui (unlock "daily"), nos
-- dois lados. Semana completa: $ 350.
Commerce.DAY_SECONDS = 86400
Commerce.TRACK_DAYS = 7
Commerce.DAILY_FACTIONS = { "US", "VC" } -- ordem fixa dos itens de um dia

export type DailyDay = {
	day: number,
	date: string,
	label: string,
	credits: number, -- créditos de intendência do dia
	items: { [string]: string }?,
}
Commerce.DailyTrack = {
	{ day = 1, date = "18 AGO", label = "Selo de serviço", credits = 25 },
	{ day = 2, date = "19 AGO", label = "Selo de serviço", credits = 30 },
	{
		day = 3,
		date = "20 AGO",
		label = "Selo + item",
		credits = 40,
		items = { US = "us_zippo", VC = "vc_tire_sandals" },
	},
	{ day = 4, date = "21 AGO", label = "Selo de serviço", credits = 45 },
	{ day = 5, date = "22 AGO", label = "Selo de serviço", credits = 50 },
	{ day = 6, date = "23 AGO", label = "Selo de serviço", credits = 60 },
	{
		day = 7,
		date = "24 AGO",
		label = "Selo + item",
		credits = 100,
		items = { US = "us_cigarette_band", VC = "vc_mess_tin" },
	},
} :: { DailyDay }

-- run: dias seguidos até lastDay; lastDay: dia UTC do último resgate (-1 = nunca); total: selos
export type DailyState = { run: number, lastDay: number, total: number }

export type DailyView = {
	canClaim: boolean,
	claimedToday: boolean,
	clockBehind: boolean, -- o último resgate está "no futuro" (relógio voltou): espera o dia chegar
	broken: boolean, -- havia sequência e ela zerou
	day: number, -- dia da trilha de hoje (resgatado ou a resgatar)
	run: number, -- dias seguidos que valem agora (0 se zerou)
}

export type DailyResult = {
	ok: boolean,
	reason: string?, -- "already" | "clock"
	day: number,
	run: number,
	state: DailyState,
	items: { string }, -- cosméticos do dia (os dois lados)
	newItems: { string }, -- os que o jogador ainda não tinha
	credits: number, -- créditos de intendência do dia (0 se recusado)
}

function Commerce.dayIndex(t: number): number
	return math.floor(t / Commerce.DAY_SECONDS)
end

-- segundos até a virada do dia UTC
function Commerce.secondsToNextDay(t: number): number
	return Commerce.DAY_SECONDS - math.floor(t) % Commerce.DAY_SECONDS
end

function Commerce.dailyDefault(): DailyState
	return { run = 0, lastDay = -1, total = 0 }
end

-- dia da trilha (1..7) de uma sequência de `run` dias seguidos
function Commerce.trackDay(run: number): number
	return (math.max(run, 1) - 1) % Commerce.TRACK_DAYS + 1
end

function Commerce.dailyView(s: DailyState, today: number): DailyView
	if s.lastDay == today then
		return {
			canClaim = false,
			claimedToday = true,
			clockBehind = false,
			broken = false,
			day = Commerce.trackDay(s.run),
			run = s.run,
		}
	elseif s.lastDay > today then
		return {
			canClaim = false,
			claimedToday = false,
			clockBehind = true,
			broken = false,
			day = Commerce.trackDay(s.run),
			run = s.run,
		}
	elseif s.lastDay >= 0 and s.lastDay == today - 1 then
		return {
			canClaim = true,
			claimedToday = false,
			clockBehind = false,
			broken = false,
			day = Commerce.trackDay(s.run + 1),
			run = s.run,
		}
	end
	return {
		canClaim = true,
		claimedToday = false,
		clockBehind = false,
		broken = s.lastDay >= 0 and s.run > 0,
		day = 1,
		run = 0,
	}
end

-- Resgate puro (o servidor chama dentro do UpdateAsync). earned: o que o jogador já tem.
function Commerce.dailyClaim(s: DailyState, today: number, earned: { [string]: boolean }?): DailyResult
	local v = Commerce.dailyView(s, today)
	if not v.canClaim then
		return {
			ok = false,
			reason = if v.claimedToday then "already" else "clock",
			day = v.day,
			run = s.run,
			state = { run = s.run, lastDay = s.lastDay, total = s.total },
			items = {},
			newItems = {},
			credits = 0,
		}
	end
	local run = v.run + 1
	local day = Commerce.trackDay(run)
	local items, newItems = {}, {}
	local entry = Commerce.DailyTrack[day]
	local byFaction = entry and entry.items
	if byFaction then
		for _, f in Commerce.DAILY_FACTIONS do
			local id = byFaction[f]
			if id then
				table.insert(items, id)
				if not (earned and earned[id]) then
					table.insert(newItems, id)
				end
			end
		end
	end
	return {
		ok = true,
		reason = nil,
		day = day,
		run = run,
		state = { run = run, lastDay = today, total = s.total + 1 },
		items = items,
		newItems = newItems,
		credits = if entry then entry.credits else 0,
	}
end

return Commerce
