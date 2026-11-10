--!strict
-- Apoio de fogo por coordenada de grade (Parte 9.5): pedido em grade UTM da carta de 1965 (quadrado
-- de 100 km "BS"), correção do observador ("mais 100, direita 50"), dispersão circular (CEP) e as
-- habilidades do comandante com recarga e custo em suprimento.
local FireSupport = {}

-- Quadrado de 100 km BS da folha 6739 I: E 2xx xxx, N 16x xxx (MapConfig.Grid: "BS 700928" =
-- E 270000, N 1692800). Coordenadas locais: E = E0 + x*0,28 ; N = N0 - z*0,28 (MapConfig).
FireSupport.SQUARE = "BS"
FireSupport.E100K = 200000
FireSupport.N100K = 1600000

export type Origin = { e: number, n: number }

-- "BS 7003 9285", "70039285", "700 928" → E, N (m, canto SW da célula) e precisão (m).
function FireSupport.parseGrid(text: string): (number?, number?, number?)
	local up = string.upper(text)
	up = string.gsub(up, FireSupport.SQUARE, "")
	local digits = string.gsub(up, "%D", "")
	local n = #digits
	if n < 4 or n > 10 or n % 2 ~= 0 then
		return nil, nil, nil
	end
	local half = n // 2
	local precision = 10 ^ (5 - half)
	local e = (tonumber(string.sub(digits, 1, half)) :: number) * precision
	local no = (tonumber(string.sub(digits, half + 1)) :: number) * precision
	return FireSupport.E100K + e, FireSupport.N100K + no, precision
end

-- grade → centro da célula em studs do jogo
function FireSupport.gridToLocal(text: string, origin: Origin, studM: number): (number?, number?)
	local e, n, p = FireSupport.parseGrid(text)
	if not e or not n or not p then
		return nil, nil
	end
	local ce, cn = e + p / 2, n + p / 2
	return (ce - origin.e) / studM, (origin.n - cn) / studM
end

-- studs do jogo → texto de grade com `digits` algarismos (6 = 100 m, 8 = 10 m)
function FireSupport.localToGrid(x: number, z: number, origin: Origin, studM: number, digits: number): string
	local e = origin.e + x * studM - FireSupport.E100K
	local n = origin.n - z * studM - FireSupport.N100K
	local half = digits // 2
	local p = 10 ^ (5 - half)
	local fmt = "%0" .. half .. "d"
	return FireSupport.SQUARE
		.. " "
		.. string.format(fmt, math.floor(e / p))
		.. " "
		.. string.format(fmt, math.floor(n / p))
end

-- "mais 100, direita 50" / "menos 50 esquerda 25" / "add 100 right 50" → (alongar m, direita m)
function FireSupport.parseCorrection(text: string): (number, number)
	local t = string.lower(text)
	local along, right = 0, 0
	for word, num in string.gmatch(t, "(%a+)%s*(%d+)") do
		local v = tonumber(num) :: number
		if word == "mais" or word == "add" then
			along += v
		elseif word == "menos" or word == "drop" then
			along -= v
		elseif word == "direita" or word == "right" then
			right += v
		elseif word == "esquerda" or word == "left" then
			right -= v
		end
	end
	return along, right
end

-- Correção no eixo observador→alvo (OT). Quadro: x = leste, z = sul. Em metros.
function FireSupport.adjust(
	tx: number,
	tz: number,
	ox: number,
	oz: number,
	along: number,
	right: number
): (number, number)
	local dx, dz = tx - ox, tz - oz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		dx, dz, len = 0, -1, 1 -- sem linha OT: assume observador ao sul olhando para o norte
	end
	dx, dz = dx / len, dz / len
	local rx, rz = -dz, dx -- direita de quem olha ao longo de (dx, dz)
	return tx + dx * along + rx * right, tz + dz * along + rz * right
end

-- Deslocamento aleatório com distribuição normal circular de CEP dado (50% dentro do raio CEP).
function FireSupport.dispersion(u1: number, u2: number, cepM: number): (number, number)
	local r = cepM * math.sqrt(math.log(1 - math.min(u1, 0.999999)) / math.log(0.5))
	local a = u2 * 2 * math.pi
	return r * math.cos(a), r * math.sin(a)
end

export type Ability = {
	id: string,
	name: string,
	faction: string,
	who: string, -- "commander" | "mortar"
	kind: string, -- "salvo" | "line" | "supply" | "tunnel"
	explosive: string?,
	rounds: number?,
	cepM: number?,
	delayS: number, -- do pedido ao primeiro impacto (além do tempo de voo calculado)
	intervalS: number?, -- entre impactos
	cooldownS: number,
	supply: number,
	dangerCloseM: number?, -- distância mínima de amigos sem confirmação
	note: string,
}

-- Números de cadência, CEP e recarga são de DESIGN/PLACEHOLDER (D-36) até haver tabela de tiro.
FireSupport.ABILITIES = {
	us_mortar_81 = {
		id = "us_mortar_81",
		name = "Morteiro 81 mm (seção)",
		faction = "US",
		who = "mortar",
		kind = "salvo",
		explosive = "mortar_81",
		rounds = 6,
		cepM = 35,
		delayS = 10,
		intervalS = 2.5,
		cooldownS = 90,
		supply = 30,
		dangerCloseM = 100,
		note = "voo calculado pelo solver do M29 a partir da posição do morteiro",
	},
	us_naval_5in = {
		id = "us_naval_5in",
		name = "Tiro naval 5 pol.",
		faction = "US",
		who = "commander",
		kind = "salvo",
		explosive = "naval_5in",
		rounds = 4,
		cepM = 60,
		delayS = 25,
		intervalS = 3,
		cooldownS = 240,
		supply = 80,
		dangerCloseM = 300,
		note = "navio ao largo, a leste da praia (DESIGN D-36)",
	},
	us_air_strike = {
		id = "us_air_strike",
		name = "Ataque aéreo (A-4)",
		faction = "US",
		who = "commander",
		kind = "line",
		explosive = "bomb_250lb",
		rounds = 4,
		cepM = 25,
		delayS = 45,
		intervalS = 0.3,
		cooldownS = 420,
		supply = 120,
		dangerCloseM = 250,
		note = "4 bombas em linha de 120 m",
	},
	us_supply_drop = {
		id = "us_supply_drop",
		name = "Suprimento por UH-34D",
		faction = "US",
		who = "commander",
		kind = "supply",
		delayS = 60,
		cooldownS = 180,
		supply = 0,
		note = "+100 de suprimento num caixote no ponto pedido",
	},
	vc_mortar_82 = {
		id = "vc_mortar_82",
		name = "Cối 82 mm",
		faction = "VC",
		who = "mortar",
		kind = "salvo",
		explosive = "mortar_82",
		rounds = 4,
		cepM = 45,
		delayS = 8,
		intervalS = 3,
		cooldownS = 100,
		supply = 30,
		dangerCloseM = 100,
		note = "voo calculado pelo solver do 82-BM-37 a partir da posição do morteiro",
	},
	vc_tunnel_reinforce = {
		id = "vc_tunnel_reinforce",
		name = "Reforço pelo túnel",
		faction = "VC",
		who = "commander",
		kind = "tunnel",
		delayS = 0,
		cooldownS = 300,
		supply = 60,
		note = "abre um ponto de reunião numa entrada de túnel por 180 s",
	},
	vc_porters = {
		id = "vc_porters",
		name = "Carregadores com munição",
		faction = "VC",
		who = "commander",
		kind = "supply",
		delayS = 90,
		cooldownS = 240,
		supply = 0,
		note = "+100 de suprimento num ponto controlado",
	},
} :: { [string]: Ability }

export type Cooldowns = { [string]: number }

-- pode usar? devolve ok e motivo
function FireSupport.canUse(
	id: string,
	faction: string,
	role: string,
	supply: number,
	readyAt: Cooldowns,
	now: number
): (boolean, string?)
	local a = FireSupport.ABILITIES[id]
	if not a then
		return false, "habilidade desconhecida"
	end
	if a.faction ~= faction then
		return false, "outra facção"
	end
	if a.who ~= role then
		return false, "papel errado"
	end
	if (readyAt[id] or 0) > now then
		return false, string.format("recarga: %d s", math.ceil((readyAt[id] or 0) - now))
	end
	if supply < a.supply then
		return false, "suprimento insuficiente"
	end
	return true, nil
end

-- pontos de impacto (studs) para um pedido: salvo = em torno do alvo; linha = ao longo do rumo
function FireSupport.impacts(
	a: Ability,
	x: number,
	z: number,
	headingRad: number,
	studM: number,
	rand: () -> number
): { { x: number, z: number, t: number } }
	local out = {}
	local n = a.rounds or 1
	for i = 1, n do
		local cx, cz = x, z
		if a.kind == "line" then
			local off = ((i - 1) / math.max(n - 1, 1) - 0.5) * 120 / studM
			cx += math.sin(headingRad) * off
			cz -= math.cos(headingRad) * off
		end
		local dx, dz = FireSupport.dispersion(rand(), rand(), a.cepM or 0)
		table.insert(out, { x = cx + dx / studM, z = cz + dz / studM, t = (i - 1) * (a.intervalS or 0) })
	end
	return out
end

return FireSupport
