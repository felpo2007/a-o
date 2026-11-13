--!strict
-- Som das armas (D-107; pedido do dono: "melhore o áudio das armas", "mostre quando você acerta o
-- tiro com o dano, ou barulho diferente mas leve"). Dados e contas puras (Lune: tests/luau/combate);
-- quem toca é o Controllers/AudioController (tiros, ferrolho, estojo, estalo) e o Controllers/Acerto
-- (marcador), pelo Controllers/Som.
-- Camadas do tiro:
--   - perto (até ~120 m): o disparo da arma (classe + ajuste de tom por arma) e, até 40 m, o "corpo"
--     (o mesmo disparo uma oitava abaixo, só graves: o tiro fica encorpado);
--   - médio e longe: os tiros gravados a ~150 m e ~500 m (AssetIds.Sounds), com os agudos caindo com
--     a distância e o som chegando com o atraso dele (d / 349 m/s);
--   - cauda pelo lugar de quem ouve: aberto (arrozal, clareira) = eco que rola, longo; mata = cauda
--     curta e abafada; fechado (vila, construção) = reverberação curta; túnel = reverberação forte;
--   - estalo supersônico quando a bala passa a até 8 m, zunido quando passa a até 4 m (e sempre na
--     bala subsônica: .45 ACP).
-- Sons "F44": os mesmos do Front 44 (Pro Sound Effects na Creator Store, liberados para uso em
-- experiências); cada arquivo traz vários disparos e o jogo toca só o trecho de um (start, len). Se
-- um id não carregar, o Controllers/Som usa `alt` (chave de AssetIds.Sounds).
local SomArmas = {}

export type Def = {
	id: number,
	start: number?, -- início do trecho (s)
	len: number?, -- duração do trecho (s)
	vol: number,
	pitch: number?,
	alt: string?, -- chave de AssetIds.Sounds se o id não carregar
}

SomArmas.LIB = {
	-- disparos por classe (F44 Config.Sounds.Shots)
	fuzil_cheio = { id = 9118173739, start = 0, len = 1.7, vol = 0.95, pitch = 1.12, alt = "shot_m14" },
	fuzil_semi = { id = 9118174539, start = 0.17, len = 1.4, vol = 0.9, pitch = 1.16, alt = "shot_m14" },
	auto = { id = 9116335315, start = 0.06, len = 0.55, vol = 0.85, pitch = 0.9, alt = "shot_type56" },
	metralhadora = { id = 9116335315, start = 0.06, len = 0.3, vol = 0.85, pitch = 1.05, alt = "shot_m14" },
	pistola = { id = 9117396996, start = 0.03, len = 0.32, vol = 0.75, pitch = 1, alt = "shot_m14" },
	lancador = { id = 12222065, start = 0, len = 1.8, vol = 1, pitch = 1, alt = "mortar_launch" },
	-- D-108: espingarda calibre 12 (F44 Shots.Shotgun: o disparo grave e largo, com eco)
	espingarda = { id = 9112910245, start = 0.04, len = 0.8, vol = 1, pitch = 1, alt = "shot_m14" },
	-- mecânica (F44 Bolt, Shell)
	mec_ferrolho = { id = 9116357355, start = 0, len = 1.3, vol = 0.55, pitch = 1.15 },
	mec_estojo = { id = 9113633058, start = 0.18, len = 0.22, vol = 0.3, pitch = 1 },
	-- D-108: bomba da espingarda (F44 Pump: o mesmo arquivo do disparo, logo depois dele: telha para
	-- trás e para a frente) e cartucho entrando no depósito (F44 Reload, só o estalo do começo,
	-- mais agudo: PLACEHOLDER, ouvir no Studio). Estojo de plástico vermelho caindo: F44 Shell grave.
	mec_bomba = { id = 9112910245, start = 0.84, len = 0.7, vol = 0.7, pitch = 1 },
	mec_cartucho = { id = 9117889191, start = 1.0, len = 0.28, vol = 0.5, pitch = 1.35 },
	mec_cartucho_cai = { id = 9113633058, start = 0.18, len = 0.22, vol = 0.32, pitch = 0.62 },
	-- bala passando (F44 Whiz); o estalo supersônico é o do jogo (AssetIds.Sounds.crack)
	bala_zunido = { id = 9118168273, start = 0, len = 0.4, vol = 0.7, pitch = 1, alt = "crack" },
	-- marcador de acerto (F44 Hit, HeadHit, Kill): leve, 2D, só para quem atirou
	acerto_corpo = { id = 15675032796, vol = 0.45, pitch = 1, alt = "dry_click" },
	acerto_cabeca = { id = 15675059323, vol = 0.55, pitch = 1, alt = "dry_click" },
	acerto_abate = { id = 9117969717, start = 0, len = 0.5, vol = 0.5, pitch = 1, alt = "dry_click" },
} :: { [string]: Def }

-- baque da bala no corpo, no lugar do alvo (F44 FleshHit): um dos quatro
SomArmas.CARNE = {
	{ id = 9114482141, start = 0, len = 0.5, vol = 0.5 },
	{ id = 9114482303, start = 0, len = 0.5, vol = 0.5 },
	{ id = 9114482300, start = 0, len = 0.5, vol = 0.5 },
	{ id = 9114482566, start = 0, len = 0.5, vol = 0.5 },
} :: { Def }

export type Arma = {
	tiro: string, -- chave em LIB
	pitch: number, -- ajuste de tom sobre o da classe (calibre)
	vol: number?,
	ferrolho: boolean?, -- manobra entre tiros (som de ferrolho)
	estojo: boolean?, -- estojo pulando (semi e automático)
	mecanica: string?, -- D-108: som da manobra entre tiros (chave em LIB; senão mec_ferrolho)
	cartucho: string?, -- D-108: som de cada cartucho entrando na recarga um a um (chave em LIB)
}

-- Por arma (ajuste de tom como o PerWeapon do Front 44: calibre maior, tom mais baixo)
SomArmas.ARMA = {
	m14 = { tiro = "fuzil_semi", pitch = 0.94, estojo = true }, -- 7,62x51: mais grave que o Garand do F44
	m60 = { tiro = "metralhadora", pitch = 0.92, estojo = true },
	m1911 = { tiro = "pistola", pitch = 0.88 }, -- .45 ACP grave (o F44 usa 0,9)
	m79 = { tiro = "lancador", pitch = 1.35, vol = 0.8 }, -- "tump" do 40 mm, mais curto que o foguete
	type56 = { tiro = "auto", pitch = 1.04, estojo = true },
	sks = { tiro = "fuzil_semi", pitch = 1.08, estojo = true },
	rpd = { tiro = "metralhadora", pitch = 1.08, estojo = true },
	type54 = { tiro = "pistola", pitch = 1.18 }, -- 7,62x25: estalo seco (o F44 usa 1,18 na TT-33)
	m70 = { tiro = "fuzil_cheio", pitch = 0.96, ferrolho = true },
	mosin = { tiro = "fuzil_cheio", pitch = 1.05, ferrolho = true }, -- o F44 usa 1,05 no Mosin
	-- D-108: 12 de cano curto, um tom abaixo da M1897 do F44 (mais carga de pólvora no 00 militar:
	-- PLACEHOLDER de ouvido); bomba entre os tiros e cartucho a cartucho na recarga
	win12 = {
		tiro = "espingarda",
		pitch = 0.94,
		vol = 1.05,
		ferrolho = true,
		mecanica = "mec_bomba",
		cartucho = "mec_cartucho",
	},
} :: { [string]: Arma }

-- Arma sem linha própria (as que vierem): pela classe
SomArmas.CLASSE = {
	rifle = { tiro = "fuzil_semi", pitch = 1, estojo = true },
	mg = { tiro = "metralhadora", pitch = 1, estojo = true },
	pistol = { tiro = "pistola", pitch = 1 },
	launcher = { tiro = "lancador", pitch = 1.35, vol = 0.8 },
	shotgun = { tiro = "espingarda", pitch = 1, ferrolho = true, mecanica = "mec_bomba", cartucho = "mec_cartucho" },
} :: { [string]: Arma }

-- Som da manobra entre tiros da arma (ferrolho ou bomba)
function SomArmas.mecanica(id: string?, kind: string?): string
	local a = SomArmas.arma(id or "", kind)
	return a.mecanica or "mec_ferrolho"
end

function SomArmas.arma(id: string, kind: string?): Arma
	return SomArmas.ARMA[id] or SomArmas.CLASSE[kind or "rifle"] or SomArmas.CLASSE.rifle
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

export type Cauda = {
	eco: boolean, -- true: eco que rola (EchoSoundEffect); false: reverberação (ReverbSoundEffect)
	delay: number, -- eco: atraso (s)
	feedback: number, -- eco: realimentação (0..1)
	wet: number, -- dB
	decay: number, -- reverberação: decaimento (s)
}

-- Cauda do tiro pelo lugar de quem ouve (PLACEHOLDER de mixagem, a ouvir no Studio)
SomArmas.CAUDA = {
	aberto = { eco = true, delay = 0.32, feedback = 0.38, wet = -9, decay = 0 },
	mata = { eco = false, delay = 0, feedback = 0, wet = -12, decay = 0.7 },
	fechado = { eco = false, delay = 0, feedback = 0, wet = -9, decay = 0.5 },
	tunel = { eco = false, delay = 0, feedback = 0, wet = -3, decay = 1.6 },
} :: { [string]: Cauda }

-- ===== bala passando =====
-- O que se ouve da bala que passa a `closestM` do ouvinte: "bala_estalo" (supersônica, até 8 m; o
-- AssetIds.Sounds.crack), "bala_zunido" (até 4 m, ou a subsônica até 6 m) ou nil. Volume 0..1.
function SomArmas.passagem(closestM: number, speed: number, sound: number): (string?, number)
	local supersonic = speed > sound
	if supersonic and closestM < 8 then
		return "bala_estalo", math.clamp(1.2 - closestM / 8, 0.3, 1.1)
	end
	if closestM < (if supersonic then 4 else 6) then
		return "bala_zunido", math.clamp(1 - closestM / 6, 0.25, 0.9)
	end
	return nil, 0
end

return SomArmas
