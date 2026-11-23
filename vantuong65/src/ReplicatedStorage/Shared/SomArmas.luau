--!strict
-- Som das armas (D-107; D-204, prompt de jogabilidade §9: "não gosto dos sons atuais das armas").
-- Dados e contas puras (Lune: tests/luau/combate e sons); quem toca é o Controllers/Som, chamado pelo
-- AudioController (tiros, recarga, clique seco, ferrolho, estojo, bala, passos, impactos, explosões),
-- pelo Acerto e pelo Ferrolho.
-- D-204: cada arma tem o seu KIT de som (tools/sons_armas.py, síntese própria; os trechos em
-- Shared/SomKits; o arquivo em AssetIds.Sounds.<kit>). Antes, 12 armas dividiam 5 disparos de
-- biblioteca com o tom trocado. No kit:
--   - p1..p4: o tiro em 1ª pessoa (a mecânica no ouvido, o grave forte); a próxima variação nunca é
--     a mesma da última (SomArmas.sorteia);
--   - e1..e3: o tiro de outro soldado perto (o sopro da boca e o estalo da bala, sem a mecânica);
--   - seco, as peças da recarga (SomArmas.RECARGA, no tempo da animação), ciclo (ferrolho ou bomba),
--     estojo1 e estojo2.
-- Camadas do tiro alheio (a soma é a de antes, D-107):
--   - perto (até ~120 m): o "e" da arma;
--   - médio e longe: kit_distancia pela família (fuzil, pistola, pesado), com o atraso do som (d / 349
--     m/s) e os agudos caindo;
--   - a cauda, pelo lugar de quem ouve (kit_caudas: aberto, mata, fechado, túnel), feita junto com o
--     tiro e tocada até o fim (a nova apaga a mais velha em 80 ms, sem estalo);
--   - estalo da bala supersônica a até 8 m, zunido a até 4 m (e a subsônica a até 6 m): kit_balas.
local SomArmas = {}

export type Arma = {
	kit: string, -- AssetIds.Sounds e Shared/SomKits
	familia: string, -- "fuzil" | "pistola" | "pesado": a cauda e o tiro de longe
	recarga: string, -- SomArmas.RECARGA
	estojo: boolean?, -- o estojo pulando (semi e automático)
	ciclo: boolean?, -- ferrolho manual ou bomba entre os tiros (trecho "ciclo")
	vol: number?,
}

SomArmas.ARMA = {
	m14 = { kit = "kit_m14", familia = "fuzil", recarga = "caixa", estojo = true },
	m16 = { kit = "kit_m16", familia = "fuzil", recarga = "caixa", estojo = true },
	type56 = { kit = "kit_type56", familia = "fuzil", recarga = "caixa", estojo = true },
	sks = { kit = "kit_sks", familia = "fuzil", recarga = "clipe", estojo = true },
	rpd = { kit = "kit_rpd", familia = "fuzil", recarga = "fita", estojo = true },
	m60 = { kit = "kit_m60", familia = "fuzil", recarga = "fita", estojo = true },
	m1911 = { kit = "kit_m1911", familia = "pistola", recarga = "pistola", estojo = true },
	type54 = { kit = "kit_type54", familia = "pistola", recarga = "pistola", estojo = true },
	m70 = { kit = "kit_m70", familia = "fuzil", recarga = "manual", ciclo = true },
	mosin = { kit = "kit_mosin", familia = "fuzil", recarga = "manual", ciclo = true },
	win12 = { kit = "kit_win12", familia = "pesado", recarga = "tubo", ciclo = true, estojo = true },
	m79 = { kit = "kit_m79", familia = "pesado", recarga = "lancador" },
} :: { [string]: Arma }

-- Arma sem linha própria (as que vierem): a da classe
SomArmas.CLASSE = {
	rifle = SomArmas.ARMA.m14,
	mg = SomArmas.ARMA.m60,
	pistol = SomArmas.ARMA.m1911,
	launcher = SomArmas.ARMA.m79,
	shotgun = SomArmas.ARMA.win12,
} :: { [string]: Arma }

function SomArmas.arma(id: string, kind: string?): Arma
	return SomArmas.ARMA[id] or SomArmas.CLASSE[kind or "rifle"] or SomArmas.CLASSE.rifle
end

SomArmas.PROPRIO = 4 -- p1..p4
SomArmas.OUTRO = 3 -- e1..e3

-- Variação de 1 a n sem repetir a última (r em [0, 1)). Com uma só, sempre 1.
function SomArmas.sorteia(n: number, ultima: number?, r: number): number
	if n <= 1 then
		return 1
	end
	if not ultima or ultima < 1 or ultima > n then
		return math.clamp(1 + math.floor(r * n), 1, n)
	end
	local k = math.clamp(1 + math.floor(r * (n - 1)), 1, n - 1)
	return if k >= ultima then k + 1 else k
end

-- ===== recarga =====
-- Por tipo: { trecho do kit, fração da recarga em que a âncora do trecho cai }. As frações são as da
-- animação de 1ª pessoa (WeaponVisuals: o carregador sai de 0,13 a 0,25, o novo encaixa em 0,64, o
-- tapa em 0,66 e a alavanca vai de 0,79 a 0,86).
SomArmas.RECARGA = {
	caixa = {
		{ "solta", 0.12 },
		{ "sai", 0.13 },
		{ "cai", 0.33 },
		{ "entra", 0.64 },
		{ "tapa", 0.66 },
		{ "ferrolho", 0.79 },
	},
	pistola = { { "solta", 0.12 }, { "sai", 0.13 }, { "cai", 0.33 }, { "entra", 0.64 }, { "slide", 0.84 } },
	fita = { { "tampa_abre", 0.14 }, { "fita", 0.4 }, { "tampa_fecha", 0.66 }, { "ferrolho", 0.79 } },
	clipe = { { "abre", 0.1 }, { "clipe", 0.36 }, { "desce", 0.42 }, { "clipe_sai", 0.66 }, { "fecha", 0.8 } },
	manual = {
		{ "abre", 0.08 },
		{ "cartucho", 0.26 },
		{ "cartucho", 0.34 },
		{ "cartucho", 0.42 },
		{ "cartucho", 0.5 },
		{ "cartucho", 0.58 },
		{ "fecha", 0.8 },
	},
	lancador = { { "abre", 0.1 }, { "estojo_sai", 0.22 }, { "granada", 0.55 }, { "fecha", 0.78 } },
	tubo = {}, -- a espingarda: cartucho a cartucho no Controllers/Ferrolho
} :: { [string]: { { any } } }

export type Passo = { trecho: string, t: number }

-- Quando tocar cada peça (s desde o começo da recarga de `dur` s). ancora(trecho) = o instante dentro
-- do trecho que casa com a animação (Shared/SomKits). Nunca antes de 0.
function SomArmas.agenda(tipo: string, dur: number, ancora: (string) -> number): { Passo }
	local out: { Passo } = {}
	local lista = SomArmas.RECARGA[tipo]
	if not lista then
		return out
	end
	for _, e in lista do
		local trecho = e[1] :: string
		table.insert(out, { trecho = trecho, t = math.max(0, (e[2] :: number) * dur - ancora(trecho)) })
	end
	return out
end

-- ===== distância =====
-- Volumes das três camadas do tiro alheio pela distância (m): perto, médio e longe (0..1). As
-- faixas se cruzam, sem degrau: perto até 120 m, médio de 40 a 900 m, longe de 250 a 2.500 m.
function SomArmas.camadas(dM: number): (number, number, number)
	local d = math.max(dM, 0)
	local near = if d <= 30 then 1 else math.clamp(1 - (d - 30) / 90, 0, 1)
	local mid = 0
	if d > 40 and d < 900 then
		mid = if d < 120 then (d - 40) / 80 else math.clamp(1 - (d - 120) / 780, 0, 1)
	end
	local far = 0
	if d > 250 and d < 2500 then
		far = if d < 500 then (d - 250) / 250 else math.clamp(1 - (d - 500) / 2000, 0.15, 1)
	end
	return near, mid * 0.9, far * 0.8
end

-- Agudos (dB, negativo) que o ar tira com a distância; a mata (lugar de quem ouve) tira mais
function SomArmas.agudos(dM: number, lugar: string?): number
	local k = if lugar == "mata" then 1 / 18 else 1 / 30
	return -math.clamp(dM * k, 0, 30)
end

-- trecho do kit_distancia: "<família>_medio_<v>" ou "<família>_longe_<v>" (3 variações)
SomArmas.DISTANCIA = 3
function SomArmas.distante(familia: string, faixa: string, v: number): string
	return string.format("%s_%s_%d", familia, faixa, v)
end

-- ===== lugar de quem ouve =====
SomArmas.LUGAR = "aberto" -- antes da primeira medida
-- Pelo eco: de N raios na horizontal (25 m), quantos bateram; teto = raio para cima bateu (copa ou
-- telhado); vila = dentro da vila (AudioController.zoneAt); tunel = debaixo da terra.
-- "aberto" | "mata" | "fechado" | "tunel"
function SomArmas.lugar(hits: number, total: number, teto: boolean, vila: boolean, tunel: boolean): string
	if tunel then
		return "tunel"
	end
	local f = if total > 0 then hits / total else 0
	if vila and f >= 0.4 then
		return "fechado"
	end
	if f >= 0.5 or (teto and f >= 0.25) then
		return "mata"
	end
	return "aberto"
end

-- D-204: a cauda é gravada no kit_caudas (por família e lugar, 2 variações): o eco que rola e
-- escurece no aberto, a cauda curta e abafada na mata, os reflexos cedo na vila e o tubo grave do
-- túnel. Antes era um efeito (EchoSoundEffect/ReverbSoundEffect) no próprio disparo, cortado com ele.
SomArmas.CAUDAS = 2
SomArmas.LUGARES = { "aberto", "mata", "fechado", "tunel" }
function SomArmas.cauda(familia: string, lugar: string, v: number): string
	local l = if table.find(SomArmas.LUGARES, lugar) then lugar else "aberto"
	return string.format("%s_%s_%d", familia, l, v)
end
SomArmas.CAUDA_VAGAS_PROPRIO = 2 -- caudas do próprio tiro tocando juntas (a rajada)
SomArmas.CAUDA_VAGAS_OUTROS = 4 -- dos tiros dos outros

-- ===== bala passando =====
-- O que se ouve da bala que passa a `closestM` do ouvinte: "estalo" (supersônica, até 8 m), "zunido"
-- (até 4 m, ou a subsônica até 6 m) ou nil. Volume 0..1. Trechos do kit_balas: estalo1..3, zunido1..3.
function SomArmas.passagem(closestM: number, speed: number, sound: number): (string?, number)
	local supersonic = speed > sound
	if supersonic and closestM < 8 then
		return "estalo", math.clamp(1.2 - closestM / 8, 0.3, 1.1)
	end
	if closestM < (if supersonic then 4 else 6) then
		return "zunido", math.clamp(1 - closestM / 6, 0.25, 0.9)
	end
	return nil, 0
end

-- ===== chão e impacto =====
-- passos (kit_passos, 6 variações por chão) pela chave antiga do AudioController.stepKey
SomArmas.PASSOS = 6
SomArmas.CHAO = {
	step_grass = "grama",
	step_mud = "lama",
	step_paddy = "arrozal",
	step_sand = "areia",
	step_wood = "madeira",
} :: { [string]: string }
-- impactos (kit_impactos, 4 variações por material)
SomArmas.IMPACTOS = 4
SomArmas.IMPACTO = {
	impact_earth = "terra",
	impact_water = "agua",
	impact_wood = "madeira",
	impact_thatch = "palha",
} :: { [string]: string }

return SomArmas
