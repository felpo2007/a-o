--!strict
-- D-220 (dono: "os sons estão horriveis"): os tiros e as explosões passam a ser GRAVAÇÕES reais da
-- biblioteca licenciada da Roblox (criador verificado ProSoundEffects, grátis para experiências), no
-- lugar da síntese da D-204. As peças que a biblioteca não cobre (recarga, ferrolho, estojo, passos,
-- bala, o M79) continuam nos kits. Se uma gravação não carregar, o Controllers/Som toca o trecho do kit.
--
-- Cada arma usa a gravação da própria arma ou, se não há, a de munição igual ou próxima:
--   Type 56: AK-47. SKS: outras tomadas de AK-47 (o mesmo 7,62 x 39). M16: CAR-16 (.223).
--   M14: BAR .30-06. M60: SG-43 (fita, 7,62 x 54R). RPD: rajadas de AK-47.
--   Mosin e M70: o último tiro das rajadas do SG-43 (fuzil de munição cheia, com a cauda natural).
--   M1911: Grizzly .45. Type 54: Beretta 9 mm. Espingarda: Remington 870.
--
-- Os recortes (início, duração e pico em dB) foram medidos no arquivo decodificado (D-220): o começo do
-- tiro, o fim antes do tiro seguinte da rajada ou da cauda abaixo de cerca de -42 dB.
local SomGravacoes = {}

export type Trecho = {
	id: number,
	ini: number, -- s, o começo do tiro no arquivo
	dur: number, -- s
	db: number, -- pico do tiro no arquivo
	tom: number?, -- diferença entre armas que usam a mesma gravação
}

local function T(id: number, ini: number, dur: number, db: number, tom: number?): Trecho
	return { id = id, ini = ini, dur = dur, db = db, tom = tom }
end

export type Kit = {
	tiros: { Trecho }?, -- p1..p4 e e1..e3 (em rodízio)
	nomeados: { [string]: Trecho }?, -- trechos com nome (as explosões)
	cauda: boolean?, -- o recorte já traz a cauda natural: a cauda sintética entra bem baixa
}

SomGravacoes.KIT = {
	kit_type56 = {
		cauda = true,
		tiros = {
			T(9114727268, 0.004, 0.63, -2.9),
			T(9114727327, 0.004, 0.63, -2.9),
			T(9114726749, 0.004, 0.634, -2.9),
			T(9114726695, 0.004, 0.656, -2.9),
		},
	},
	kit_sks = {
		cauda = true,
		tiros = {
			T(9114726893, 0.004, 0.634, -2.9, 0.97),
			T(9114726947, 0.004, 0.628, -2.9, 0.97),
			T(9114727110, 0.004, 0.676, -2.9, 0.97),
		},
	},
	kit_m16 = {
		cauda = true,
		tiros = {
			T(9116335036, 0.004, 0.85, -3.5),
			T(9116335315, 0.004, 0.85, -3.5),
			T(9116335273, 0.004, 0.85, -3.6),
			T(9116335175, 0.004, 0.85, -3.5),
		},
	},
	kit_m14 = {
		tiros = {
			T(9114729496, 0.962, 0.3, -3.9),
			T(9114729452, 0.598, 0.3, -4.0),
			T(9114725670, 1.64, 0.3, -4.4),
		},
	},
	kit_m60 = {
		tiros = {
			T(9119029803, 0, 0.098, -10.6),
			T(9119029801, 0, 0.094, -10.3),
			T(9119029236, 0, 0.095, -11.1),
		},
	},
	kit_rpd = {
		tiros = {
			T(9116353301, 0, 0.085, -9),
			T(9116353098, 0, 0.07, -9),
			T(9116353340, 0, 0.085, -9),
		},
	},
	kit_mosin = {
		cauda = true,
		tiros = {
			T(9119029618, 1.26, 0.9, -9.8, 0.97),
			T(9119029237, 1.592, 0.9, -11.2, 0.97),
			T(9119029800, 0.472, 0.9, -15.3, 0.97),
		},
	},
	kit_m70 = {
		cauda = true,
		tiros = {
			T(9119029803, 1.066, 0.55, -10, 1.03),
			T(9119029236, 2.68, 0.46, -11, 1.03),
			T(9119029801, 2.542, 0.7, -10.9, 1.03),
		},
	},
	kit_m1911 = {
		cauda = true,
		tiros = {
			T(9117402319, 0, 0.85, -5.4),
			T(9117402631, 0, 0.85, -6.1),
			T(9117402616, 0, 0.85, -5.8),
			T(9117396996, 0.034, 0.85, -5.1),
		},
	},
	kit_type54 = {
		cauda = true,
		tiros = {
			T(9114720234, 0.002, 0.85, -4.2),
			T(9114720789, 0.002, 0.85, -4.4),
			T(9114720229, 0.002, 0.85, -4.2),
			T(9114720477, 0.002, 0.85, -4.3),
		},
	},
	kit_win12 = {
		cauda = true,
		tiros = {
			T(9114708745, 0, 0.77, -6.3),
			T(9114724281, 0, 0.57, -7.3),
			T(9114724429, 2.318, 0.77, -7.1),
		},
	},
	kit_explosoes = {
		nomeados = {
			granada1 = T(9116973611, 0.01, 0.69, -1.7),
			granada2 = T(9116973607, 0.015, 0.79, -1.8),
			granada3 = T(9116973348, 0.015, 0.81, -2.2),
			pesada1 = T(9117876706, 0.115, 3.25, -2.8),
			pesada2 = T(9117876319, 0.265, 3.23, -2.6),
		},
	},
} :: { [string]: Kit }

-- D-236 (dono: "altere o barulho do dano, do recarregamento, etc esta mt estranho, faça barulhos reais"):
-- o manuseio das armas e o corpo também viram gravações da mesma biblioteca. Início, duração e pico
-- medidos no áudio decodificado. Fontes, pela descrição do arquivo:
--   carregador de fuzil e alavanca: "AK-47, Clip Handling Action"; ferrolho: "Machine Gun Bolt, M85";
--   fita: "Loading Ammunition Belt"; pistola: "Pistol Clip, Loading" e "Pistol Handling";
--   bomba: "12 Gauge Shotgun, Pump Action"; estojo: "Ammo Shell Drop"; corpo: "Body Hit"; dor: "Pained Gasp".
local ESTOJOS = { T(9113109832, 0, 0.44, -3.1, 0.94), T(9113108632, 0, 0.49, -3.5, 0.9) }
local SOLTA = T(9113104335, 0, 0.16, -6)
local CAI = T(9113107271, 0, 0.6, -4.8, 0.62) -- o carregador vazio batendo no chão
local SECO = T(9117396530, 0.01, 0.11, -12.1)

local MANUSEIO: { [string]: { [string]: Trecho } } = {
	kit_type56 = {
		seco = SECO,
		solta = SOLTA,
		sai = T(9116347612, 0.16, 0.2, 3.2, 0.9),
		cai = CAI,
		entra = T(9116347612, 0.16, 0.24, 3.2),
		tapa = T(9116348009, 1.005, 0.17, 3.3),
		ferrolho = T(9116348209, 0.985, 0.62, 3.3),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_m16 = {
		seco = T(9117396530, 0.01, 0.11, -12.1, 1.08),
		solta = T(9113104335, 0, 0.16, -6, 1.1),
		sai = T(9113104176, 0.035, 0.11, -3.6, 1.04),
		cai = CAI,
		entra = T(9116347624, 0.137, 0.23, 3.3, 1.08),
		tapa = T(9113104176, 0.325, 0.14, -1.7, 1.06),
		ferrolho = T(9116348009, 0.74, 0.44, 3.3, 1.08),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_m14 = {
		seco = T(9117396530, 0.01, 0.11, -12.1, 0.94),
		solta = T(9113104335, 0, 0.16, -6, 0.92),
		sai = T(9113104358, 0.78, 0.13, -1.7, 0.92),
		cai = CAI,
		entra = T(9116348211, 0.398, 0.31, 3.2, 0.92),
		tapa = T(9116348009, 1.005, 0.17, 3.3, 0.9),
		ferrolho = T(9116357621, 0, 0.66, -2.6),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_sks = {
		seco = SECO,
		abre = T(9116344648, 0, 0.2, -19),
		clipe = T(9117396156, 0, 0.14, -6.4, 0.94),
		desce = T(9116339838, 0.235, 0.42, -14.2),
		clipe_sai = T(9117396716, 0.718, 0.09, -14.4),
		fecha = T(9116344663, 0, 0.13, -16.7),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_m60 = {
		seco = T(9117396530, 0.01, 0.11, -12.1, 0.88),
		tampa_abre = T(9116342002, 0, 0.26, -19.9),
		fita = T(9116339857, 0, 1, -17.1),
		tampa_fecha = T(9116340490, 0.125, 0.34, -14.3),
		ferrolho = T(9116357355, 0, 0.33, -3.9),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_rpd = {
		seco = T(9117396530, 0.01, 0.11, -12.1, 0.9),
		tampa_abre = T(9116342102, 0, 0.25, -16.8),
		fita = T(9116339838, 0.235, 0.42, -14.2, 0.96),
		tampa_fecha = T(9116342102, 0.71, 0.15, -16.8),
		ferrolho = T(9116357383, 0, 0.42, -8.7),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_m1911 = {
		seco = T(9117396530, 0.01, 0.11, -12.1, 0.96),
		solta = SOLTA,
		sai = T(9117396464, 0.26, 0.09, -15.6),
		cai = T(9113107271, 0, 0.6, -4.8, 0.74),
		entra = T(9117396464, 0.492, 0.2, -6.5),
		slide = T(9116344648, 0.272, 0.1, -16.3),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_type54 = {
		seco = T(9117396530, 0.01, 0.11, -12.1, 1.04),
		solta = T(9113104335, 0, 0.16, -6, 1.06),
		sai = T(9117396464, 0.26, 0.09, -15.6, 1.05),
		cai = T(9113107271, 0, 0.6, -4.8, 0.78),
		entra = T(9117396156, 0, 0.14, -6.4),
		slide = T(9116344869, 0.417, 0.09, -15.6),
		estojo1 = ESTOJOS[1],
		estojo2 = ESTOJOS[2],
	},
	kit_m70 = {
		seco = SECO,
		abre = T(9116357355, 0, 0.32, -3.9, 0.94),
		cartucho = T(9117396156, 0, 0.13, -6.4, 1.08),
		fecha = T(9116357621, 0.535, 0.12, -16.4, 0.94),
		ciclo = T(9116357621, 0, 0.66, -2.6, 0.92),
	},
	kit_mosin = {
		seco = SECO,
		abre = T(9116357383, 0, 0.38, -8.7, 0.88),
		cartucho = T(9117396156, 0, 0.13, -6.4, 1),
		fecha = T(9116357383, 0.456, 0.11, -15.9, 0.88),
		ciclo = T(9116357383, 0, 0.56, -8.7, 0.86),
	},
	kit_win12 = {
		seco = SECO,
		cartucho = T(9112912000, 0, 0.17, -7.9, 0.86),
		ciclo = T(9112911836, 0, 0.62, -8.1),
		estojo1 = T(9113107271, 0, 0.6, -4.8, 0.8),
		estojo2 = T(9113106947, 0.15, 0.6, -2.8, 0.8),
	},
	kit_balas = {
		acerto_corpo = T(9113485306, 0, 0.2, -7.1, 1.2),
		acerto_cabeca = T(9113490484, 0, 0.3, -3.2, 1.12),
		acerto_abate = T(9113489882, 0, 0.46, -5.6),
	},
	kit_impactos = {
		carne1 = T(9113497758, 0, 0.24, -5.5),
		carne2 = T(9113490003, 0, 0.31, -3.3),
		carne3 = T(9113488143, 0, 0.32, -1.7),
		carne4 = T(9113497945, 0, 0.18, -7.7),
	},
	-- o soldado levando o tiro (Controllers/AudioController): o baque e o fôlego que falta
	kit_corpo = {
		baque1 = T(9113490003, 0, 0.31, -3.3, 0.92),
		baque2 = T(9113497758, 0, 0.24, -5.5, 0.9),
		baque3 = T(9113488143, 0, 0.32, -1.7, 0.88),
		dor1 = T(9114029889, 0, 0.46, -4.2),
		dor2 = T(9114030316, 0.06, 0.4, -6.5),
		dor3 = T(9125572953, 0, 0.21, -11.6),
	},
}
for kit, pecas in MANUSEIO do
	local k = SomGravacoes.KIT[kit]
	if not k then
		k = {}
		SomGravacoes.KIT[kit] = k
	end
	local nomeados: { [string]: Trecho } = k.nomeados or {}
	k.nomeados = nomeados
	for nome, t in pecas do
		nomeados[nome] = t
	end
end

-- A gravação que toca no lugar do trecho `trecho` do kit, ou nil (fica o trecho do kit)
function SomGravacoes.de(kit: string, trecho: string): Trecho?
	local k = SomGravacoes.KIT[kit]
	if not k then
		return nil
	end
	local nomeados = k.nomeados
	if nomeados and nomeados[trecho] then
		return nomeados[trecho]
	end
	local tiros = k.tiros
	if not tiros then
		return nil
	end
	local n = tonumber(string.match(trecho, "^[pe](%d+)$"))
	if not n then
		return nil
	end
	return tiros[(n - 1) % #tiros + 1]
end

-- O recorte já traz a cauda natural?
function SomGravacoes.temCauda(kit: string): boolean
	local k = SomGravacoes.KIT[kit]
	return k ~= nil and k.cauda == true
end

-- O ganho que leva o pico do recorte a -3 dB (a gravação mais baixa não some na mistura)
function SomGravacoes.volume(t: Trecho): number
	return math.clamp(10 ^ ((-3 - t.db) / 20), 0.4, 4)
end

-- Todos os arquivos usados, sem repetir (para o pré-carregamento)
function SomGravacoes.ids(): { number }
	local vistos: { [number]: boolean } = {}
	local lista: { number } = {}
	local function poe(t: Trecho)
		if not vistos[t.id] then
			vistos[t.id] = true
			table.insert(lista, t.id)
		end
	end
	for _, k in SomGravacoes.KIT do
		local tiros: { Trecho } = k.tiros or {}
		for _, t in tiros do
			poe(t)
		end
		local nomeados: { [string]: Trecho } = k.nomeados or {}
		for _, t in nomeados do
			poe(t)
		end
	end
	table.sort(lista)
	return lista
end

return SomGravacoes
