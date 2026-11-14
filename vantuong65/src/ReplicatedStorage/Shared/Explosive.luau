--!strict
-- Efeito de explosivos em pessoas e no terreno. Raios letal/de baixas e cratera: PLACEHOLDER de
-- design (D-36) até haver manual de munição; o formato (letal → ferido → nada, cobertura e postura
-- reduzindo a exposição) é o que importa para o jogo e fica travado em teste.
local Explosive = {}

-- Incendiário (2026-11-12, napalm do ataque aéreo do A-4): mancha de fogo em elipse no chão, ao longo
-- do rumo do avião, que queima durationS. Quem fica dentro acumula exposição: a 1ª vez se queima
-- (ferimento), e com lethalS acumulados cai. A borda (fora da elipse até edgeM) só queima.
export type Burn = {
	lengthM: number, -- comprimento da mancha (ao longo do rumo)
	widthM: number,
	durationS: number,
	lethalS: number, -- exposição acumulada dentro da mancha que incapacita
	edgeM: number, -- faixa em volta que queima sem matar
	burnJ: number, -- energia do ferimento de queimadura (J), como a de um estilhaço
}

export type Type = {
	id: string,
	name: string,
	lethalM: number, -- dentro: incapacita (energia de tronco >= torsoDownJ)
	casualtyM: number, -- até aqui: chance de ferimento caindo com a distância
	craterM: number, -- raio da cratera no terreno (0 = sem cratera)
	fragJ: number, -- energia típica de um fragmento que fere (J)
	src: string,
	burn: Burn?,
}

Explosive.TYPES = {
	mortar_81 = {
		id = "mortar_81",
		name = "81 mm HE",
		lethalM = 8,
		casualtyM = 30,
		craterM = 1.2,
		fragJ = 700,
		src = "PLACEHOLDER",
	},
	mortar_82 = {
		id = "mortar_82",
		name = "82 mm HE",
		lethalM = 8,
		casualtyM = 28,
		craterM = 1.2,
		fragJ = 700,
		src = "PLACEHOLDER",
	},
	naval_5in = {
		id = "naval_5in",
		name = "5 pol. HE",
		lethalM = 15,
		casualtyM = 50,
		craterM = 2.2,
		fragJ = 900,
		src = "PLACEHOLDER",
	},
	bomb_250lb = {
		id = "bomb_250lb",
		name = "bomba de 250 lb",
		lethalM = 20,
		casualtyM = 70,
		craterM = 3.5,
		fragJ = 1000,
		src = "PLACEHOLDER",
	},
	he_90 = {
		id = "he_90",
		name = "90 mm HE (M48A3)",
		lethalM = 6,
		casualtyM = 22,
		craterM = 0.9,
		fragJ = 700,
		src = "PLACEHOLDER",
	},
	heat_106 = {
		id = "heat_106",
		name = "106 mm HEAT (Ontos)",
		lethalM = 4,
		casualtyM = 15,
		craterM = 0.6,
		fragJ = 600,
		src = "PLACEHOLDER",
	},
	pg2 = {
		id = "pg2",
		name = "PG-2 (RPG-2)",
		lethalM = 2,
		casualtyM = 8,
		craterM = 0.3,
		fragJ = 500,
		src = "PLACEHOLDER",
	},
	grenade_us = {
		id = "grenade_us",
		name = "granada de mão (EUA)",
		lethalM = 5,
		casualtyM = 15,
		craterM = 0,
		fragJ = 600,
		src = "PLACEHOLDER",
	},
	grenade_vc = {
		id = "grenade_vc",
		name = "granada de cabo (VC)",
		lethalM = 4,
		casualtyM = 12,
		craterM = 0,
		fragJ = 550,
		src = "PLACEHOLDER",
	},
	rocket_35 = {
		id = "rocket_35",
		name = "3,5 pol. HEAT (M20)",
		lethalM = 2.5,
		casualtyM = 10,
		craterM = 0.4,
		fragJ = 550,
		src = "PLACEHOLDER",
	},
	-- bomba incendiária (napalm) do A-4: quase sem sopro; o dano é o fogo (Explosive.burnAt)
	napalm = {
		id = "napalm",
		name = "bomba incendiária (napalm)",
		lethalM = 0,
		casualtyM = 0,
		craterM = 0,
		fragJ = 0,
		src = "PLACEHOLDER (mancha, duração e exposição: números de jogo, sem ficha)",
		burn = { lengthM = 70, widthM = 22, durationS = 25, lethalS = 2.0, edgeM = 6, burnJ = 600 },
	},
} :: { [string]: Type }

-- Fogo da mancha num ponto: "core" (dentro da elipse), "edge" (na faixa da borda) ou nil.
-- dx, dz: posição relativa ao centro (m); hx, hz: rumo do avião (unitário no plano).
function Explosive.burnAt(b: Burn, dx: number, dz: number, hx: number, hz: number): string?
	local along = dx * hx + dz * hz
	local across = -dx * hz + dz * hx
	local a, c = b.lengthM / 2, b.widthM / 2
	local q = (along / a) ^ 2 + (across / c) ^ 2
	if q <= 1 then
		return "core"
	end
	local qe = (along / (a + b.edgeM)) ^ 2 + (across / (c + b.edgeM)) ^ 2
	return if qe <= 1 then "edge" else nil
end

-- Exposição acumulada (s) -> o que acontece agora: "burn" (1ª queimadura), "lethal" ou nil.
-- already: o que já aconteceu com este corpo nesta mancha ("burn" | "lethal" | nil).
function Explosive.burnStep(b: Burn, zone: string?, exposedS: number, already: string?): string?
	if not zone or already == "lethal" then
		return nil
	end
	if zone == "core" and exposedS >= b.lethalS then
		return "lethal"
	end
	if already == nil then
		return "burn"
	end
	return nil
end

-- Exposição: 1 em pé e à vista; postura e cobertura reduzem (fatores de design).
Explosive.CROUCH = 0.6
Explosive.COVERED = 0.15

-- Resultado para um alvo a `distM`: "lethal" | "wound" | nil, e a energia a aplicar (J).
-- `u` em [0,1) é o sorteio (semente do servidor).
function Explosive.effect(id: string, distM: number, exposure: number, u: number): (string?, number)
	local t = Explosive.TYPES[id]
	if not t then
		return nil, 0
	end
	if distM <= t.lethalM * math.sqrt(exposure) then
		return "lethal", 2000
	end
	if distM > t.casualtyM then
		return nil, 0
	end
	-- chance cai com o quadrado da distância relativa (densidade de fragmentos ~ 1/d²)
	local rel = (distM - t.lethalM) / math.max(t.casualtyM - t.lethalM, 1)
	local p = math.clamp(1 - rel, 0, 1) ^ 2 * exposure
	if u < p then
		return "wound", t.fragJ * (1 - 0.5 * rel)
	end
	return nil, 0
end

-- Orçamento de crateras (Parte 9.6): no máximo `perMinute` por minuto, para limitar replicação.
export type Budget = { perMinute: number, stamps: { number } }

function Explosive.newBudget(perMinute: number): Budget
	return { perMinute = perMinute, stamps = {} }
end

function Explosive.allowCrater(b: Budget, now: number): boolean
	local keep = {}
	for _, t in b.stamps do
		if now - t < 60 then
			table.insert(keep, t)
		end
	end
	b.stamps = keep
	if #keep >= b.perMinute then
		return false
	end
	table.insert(b.stamps, now)
	return true
end

return Explosive
