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
