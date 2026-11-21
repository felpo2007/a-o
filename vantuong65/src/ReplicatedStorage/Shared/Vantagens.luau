--!strict
-- Vantagens compradas (plano, seção 5b; pedido do dono em 2026-11-12: "velocidade, mais vida, mais
-- respiração para segurar e outras ideias"). Game Passes permanentes, valem nos dois lados e
-- aparecem na loja com o número exato. Regras:
--   - TETO: nenhum número de combate passa de +12% (ou -12%, quando menos é melhor), mesmo somando
--     os passes e os kits de equipamento (Progression). Combate = o que decide o tiroteio na hora:
--     velocidade, vida, recarga e balanço da mira. O fôlego (tempo de prender a respiração), o
--     socorro (bandagem e sangramento) e a marca do inimigo são de apoio e ficam com o número do
--     plano. O balanço do plano (25% menos) é cortado pelo teto para 12%.
--   - Contagem (carregador e granada) soma com os kits, sem teto percentual (+1 cada).
--   - O SERVIDOR confere: o efeito sai da posse do passe no servidor, que grava atributos no jogador
--     (Vant_<chave>). Quem aplica o efeito é o dono de cada sistema (corpo, armas, marcas) lendo
--     Vantagens.mult(player, chave) ou Vantagens.extra(player, chave).
--   - Transparência: a ficha do jogador mostra as vantagens ativas (Campanha_State.perks).
-- Valores PLACEHOLDER, a ajustar no teste.
local Vantagens = {}

Vantagens.CAP = 0.12

-- chave -> como aplicar:
--   mult: multiplica o número base (velocidade, vida...); "time" = multiplica um TEMPO (menor é
--   mais rápido); "rate" = multiplica uma taxa (menor é mais devagar)
--   count: soma unidades
export type KeyDef = { kind: string, combat: boolean, label: string, unit: string }
Vantagens.KEYS = {
	speed = { kind = "mult", combat = true, label = "Velocidade no trote e na corrida", unit = "%" },
	health = { kind = "mult", combat = true, label = "Vida máxima", unit = "%" },
	breath = { kind = "mult", combat = false, label = "Tempo de prender a respiração", unit = "%" },
	sway = { kind = "mult", combat = true, label = "Balanço da mira na luneta", unit = "%" },
	reload = { kind = "time", combat = true, label = "Tempo de recarga", unit = "%" },
	bandage = { kind = "time", combat = false, label = "Tempo de bandagem e torniquete", unit = "%" },
	bleed = { kind = "rate", combat = false, label = "Velocidade do sangramento", unit = "%" },
	mags = { kind = "count", combat = false, label = "Carregadores", unit = "+" },
	grenades = { kind = "count", combat = false, label = "Granadas", unit = "+" },
	mark = { kind = "mult", combat = false, label = "Tempo da marca de inimigo para o squad", unit = "%" },
} :: { [string]: KeyDef }

-- os passes (chave em Commerce.IDS) e o que cada um dá
export type Perk = { key: string, name: string, desc: string, effects: { [string]: number } }
Vantagens.PERKS = {
	{
		key = "PASS_PERK_SPEED",
		name = "Pernas de Maratonista",
		desc = "+6% de velocidade no trote e na corrida.",
		effects = { speed = 1.06 },
	},
	{
		key = "PASS_PERK_HEALTH",
		name = "Couro Duro",
		desc = "+12% de vida máxima.",
		effects = { health = 1.12 },
	},
	{
		key = "PASS_PERK_BREATH",
		name = "Fôlego de Atirador",
		desc = "Prende a respiração por +60% do tempo e a mira balança 12% menos na luneta.",
		effects = { breath = 1.6, sway = 0.75 }, -- 0,75 do plano: o teto corta para 0,88
	},
	{
		key = "PASS_PERK_RELOAD",
		name = "Mãos Rápidas",
		desc = "Recarga 12% mais rápida.",
		effects = { reload = 0.88 },
	},
	{
		key = "PASS_PERK_MEDIC",
		name = "Socorrista Treinado",
		desc = "Bandagem e torniquete 35% mais rápidos; o sangramento corre 20% mais devagar.",
		effects = { bandage = 0.74, bleed = 0.8 },
	},
	{
		key = "PASS_PERK_POCKETS",
		name = "Bolsos Extras",
		desc = "+1 carregador e +1 granada (soma com os kits).",
		effects = { mags = 1, grenades = 1 },
	},
	{
		key = "PASS_PERK_EAGLE",
		name = "Olho de Águia",
		desc = "O inimigo que você marca fica 50% mais tempo marcado para o squad.",
		effects = { mark = 1.5 },
	},
} :: { Perk }
-- os 7 juntos com desconto
Vantagens.BUNDLE = "PASS_PERK_ALL"
Vantagens.BUNDLE_NAME = "Pacote Combatente"
Vantagens.BUNDLE_DESC = "As 7 vantagens juntas, com desconto."

-- passes que o jogador tem -> efeitos ativos (sem o teto)
local function raw(passes: { [string]: boolean }?): { [string]: number }
	local out: { [string]: number } = {}
	local ps = passes or {}
	local all = ps[Vantagens.BUNDLE] == true
	for _, p in Vantagens.PERKS do
		if all or ps[p.key] then
			for k, v in p.effects do
				local d = Vantagens.KEYS[k]
				if d and d.kind == "count" then
					out[k] = (out[k] or 0) + v
				else
					out[k] = (out[k] or 1) * v
				end
			end
		end
	end
	return out
end

-- aplica o teto de combate a um multiplicador final
function Vantagens.capped(key: string, v: number): number
	local d = Vantagens.KEYS[key]
	if not d or not d.combat or d.kind == "count" then
		return v
	end
	return math.clamp(v, 1 - Vantagens.CAP, 1 + Vantagens.CAP)
end

-- Efeito final por chave: passes x kits (kits: multiplicadores ou somas que o equipamento já dá na
-- mesma chave; hoje nenhum kit mexe nestas chaves, mas a soma fica pronta) com o teto. Para chaves
-- de contagem devolve só a parte da vantagem (o kit soma por conta própria).
function Vantagens.compute(passes: { [string]: boolean }?, kits: { [string]: number }?): { [string]: number }
	local r = raw(passes)
	local out: { [string]: number } = {}
	for k, v in r do
		local d = Vantagens.KEYS[k]
		if d.kind == "count" then
			out[k] = v
		else
			local kit = if kits and kits[k] then kits[k] else 1
			-- o que o kit já dá entra no teto; a vantagem fica com o que sobra
			local total = Vantagens.capped(k, v * kit)
			out[k] = total / kit
		end
	end
	return out
end

-- atributo no jogador
function Vantagens.attr(key: string): string
	return "Vant_" .. key
end

local function readAttr(inst: Instance?, key: string): number?
	if not inst then
		return nil
	end
	local v = inst:GetAttribute(Vantagens.attr(key))
	return if type(v) == "number" and v == v then v else nil
end

-- Multiplicador para quem aplica o efeito (1 sem passe). `who` = Player (ou o modelo do personagem,
-- que o servidor também marca). Sempre passa pelo teto, mesmo que alguém grave valor errado.
function Vantagens.mult(who: Instance?, key: string): number
	local d = Vantagens.KEYS[key]
	if not d or d.kind == "count" then
		return 1
	end
	local v = readAttr(who, key)
	if v == nil and who and who:IsA("Model") then
		local p = game:GetService("Players"):GetPlayerFromCharacter(who)
		v = readAttr(p, key)
	end
	return Vantagens.capped(key, v or 1)
end

-- Unidades a mais (carregador, granada); 0 sem passe
function Vantagens.extra(who: Instance?, key: string): number
	local d = Vantagens.KEYS[key]
	if not d or d.kind ~= "count" then
		return 0
	end
	local v = readAttr(who, key)
	if v == nil and who and who:IsA("Model") then
		local p = game:GetService("Players"):GetPlayerFromCharacter(who)
		v = readAttr(p, key)
	end
	return math.clamp(math.floor(v or 0), 0, 2)
end

-- texto do número exato para a loja e a ficha ("+6%", "-12%", "+1")
function Vantagens.display(key: string, v: number): string
	local d = Vantagens.KEYS[key]
	if not d then
		return ""
	end
	if d.kind == "count" then
		return string.format("+%d", math.floor(v))
	end
	local pct = math.floor((v - 1) * 100 + 0.5)
	return if pct >= 0 then string.format("+%d%%", pct) else string.format("%d%%", pct)
end

return Vantagens
