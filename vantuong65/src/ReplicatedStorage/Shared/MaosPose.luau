--!strict
-- Mãos de 1ª pessoa (D-99). Pedido do dono, com foto: em 1ª pessoa as mãos da pistola eram "duas
-- bolas laranjas" (as elipsoides da D-69). Aqui a forma da mão em cada pega, em METROS, no espaço da
-- arma (x direita, y cima, −z para a frente), com a origem no ponto da mão que o WeaponVisuals usa:
-- - "grip": a direita no punho (pistola e fuzil): palma do lado direito, médio, anelar e mínimo
--   fechados pela frente até o lado esquerdo, indicador no gatilho, polegar por cima;
-- - "support": a esquerda embaixo do guarda-mão: palma para cima, dedos subindo pelo lado direito,
--   polegar pelo esquerdo;
-- - "cup": a esquerda da pistola, abraçando a direita pela frente, polegar adiante;
-- - "flat": dedos quase retos (carta, tapa no carregador, curativo).
-- Cada forma é um conjunto de cápsulas (cadeias de pontos com raio) e caixas. O Controllers/Maos1P
-- monta com peças (reserva) e o tools/maos (Blender, metaballs) faz a malha do GLB com estes mesmos
-- números (tools/maos/exportar.luau grava assets/blender/maos_1p/capsulas.json). Medidas de mão
-- adulta de ~1,80 m (palma 8,5 x 8 cm, dedo 1,8 cm de espessura). PLACEHOLDER.
-- Módulo puro (sem Vector3): testado no Lune (tests/luau/faca.luau).
local MaosPose = {}

export type V = { number }
export type Chain = { pts: { V }, r: number, mat: string? } -- mat: "skin" (padrão) | "nail"
export type Box = { c: V, s: V }
export type Pose = { hand: string, chains: { Chain }, boxes: { Box } }

local function add(a: V, b: V): V
	return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

-- giro em torno de X (rad) de um ponto relativo a `o`
local function rotX(p: V, o: V, ang: number): V
	local y, z = p[2] - o[2], p[3] - o[3]
	local c, s = math.cos(ang), math.sin(ang)
	return { p[1], o[2] + y * c - z * s, o[3] + y * s + z * c }
end

-- forma escrita em torno do centro do punho `g` (no espaço da mão), com o punho inclinado `rake`
local function around(g: V, rake: number, chains: { Chain }, boxes: { Box }): ({ Chain }, { Box })
	local outC, outB = {}, {}
	for _, ch in chains do
		local pts = {}
		for _, p in ch.pts do
			table.insert(pts, rotX(add(p, g), g, rake))
		end
		table.insert(outC, { pts = pts, r = ch.r, mat = ch.mat })
	end
	for _, b in boxes do
		table.insert(outB, { c = rotX(add(b.c, g), g, rake), s = b.s })
	end
	return outC, outB
end

local function finger(pts: { V }, r: number): Chain
	return { pts = pts, r = r }
end

-- ===== direita no punho =====
-- O ponto da mão fica 1,2 cm à direita e 1,5 cm atrás do Attachment "Grip" (WeaponVisuals): o
-- centro do punho está em (−0,012; 0; −0,015). Punho de ~3,2 x 4,4 cm, inclinado 15° (topo à frente).
local GRIP_C, GRIP_B = around({ -0.012, 0, -0.015 }, math.rad(-15), {
	-- palma e base do polegar encostadas na traseira do punho; o pulso vai para trás e para baixo
	finger({ { 0.020, -0.040, 0.026 }, { 0.022, 0.028, 0.028 } }, 0.014),
	finger({ { 0.026, -0.010, 0.030 }, { 0.014, -0.028, 0.062 } }, 0.022),
	-- médio, anelar e mínimo: do nó (frente-direita) pela frente do punho até o lado esquerdo
	finger(
		{ { 0.034, 0.012, -0.018 }, { 0.012, 0.012, -0.034 }, { -0.014, 0.012, -0.030 }, { -0.026, 0.012, -0.008 } },
		0.0095
	),
	finger(
		{ { 0.034, -0.010, -0.018 }, { 0.012, -0.010, -0.034 }, { -0.014, -0.010, -0.030 }, { -0.025, -0.010, -0.008 } },
		0.009
	),
	finger(
		{ { 0.032, -0.032, -0.014 }, { 0.012, -0.032, -0.030 }, { -0.012, -0.032, -0.026 }, { -0.021, -0.032, -0.010 } },
		0.008
	),
	-- indicador no gatilho
	finger(
		{ { 0.034, 0.036, -0.016 }, { 0.020, 0.040, -0.040 }, { 0.004, 0.036, -0.054 }, { -0.004, 0.030, -0.052 } },
		0.009
	),
	-- polegar por cima, fechando do lado esquerdo
	finger(
		{ { 0.026, 0.040, 0.020 }, { 0.000, 0.050, 0.010 }, { -0.024, 0.046, -0.004 }, { -0.030, 0.040, -0.026 } },
		0.011
	),
}, {
	{ c = { 0.030, -0.004, 0.010 }, s = { 0.022, 0.088, 0.074 } },
})

-- ===== esquerda embaixo do guarda-mão =====
-- O ponto da mão fica 2,5 cm abaixo do Attachment "Support": o guarda-mão (~4,5 cm) passa em y = 0,025.
local SUP_C: { Chain } = {
	finger({ { -0.010, 0.000, 0.030 }, { 0.000, -0.010, 0.052 } }, 0.022), -- pulso
	finger(
		{ { 0.024, 0.004, -0.030 }, { 0.036, 0.018, -0.030 }, { 0.034, 0.036, -0.033 }, { 0.022, 0.048, -0.034 } },
		0.009
	),
	finger(
		{ { 0.026, 0.004, -0.010 }, { 0.038, 0.018, -0.010 }, { 0.036, 0.037, -0.013 }, { 0.023, 0.049, -0.014 } },
		0.0095
	),
	finger(
		{ { 0.026, 0.004, 0.010 }, { 0.037, 0.018, 0.010 }, { 0.035, 0.036, 0.007 }, { 0.023, 0.047, 0.006 } },
		0.009
	),
	finger(
		{ { 0.024, 0.004, 0.028 }, { 0.034, 0.016, 0.028 }, { 0.032, 0.032, 0.025 }, { 0.022, 0.041, 0.024 } },
		0.008
	),
	finger({ { -0.026, 0.004, 0.024 }, { -0.036, 0.018, 0.000 }, { -0.032, 0.030, -0.026 } }, 0.0105), -- polegar
}
local SUP_B: { Box } = { { c = { -0.004, 0.000, 0.004 }, s = { 0.064, 0.020, 0.080 } } }

-- ===== esquerda da pistola (abraça a direita) =====
-- Ponto da mão: Grip + (−0,025; −0,035; −0,01); o centro do punho fica em (0,025; 0,035; 0,01).
local CUP_C, CUP_B = around({ 0.025, 0.035, 0.010 }, 0, {
	finger({ { -0.044, -0.040, 0.030 }, { -0.025, -0.045, 0.040 } }, 0.022), -- pulso
	finger(
		{ { -0.040, -0.004, -0.026 }, { -0.018, -0.004, -0.048 }, { 0.012, -0.004, -0.050 }, { 0.030, -0.004, -0.036 } },
		0.0095
	),
	finger(
		{ { -0.040, -0.024, -0.026 }, { -0.018, -0.024, -0.049 }, { 0.012, -0.024, -0.051 }, { 0.030, -0.024, -0.037 } },
		0.0095
	),
	finger(
		{ { -0.040, -0.044, -0.024 }, { -0.018, -0.044, -0.046 }, { 0.010, -0.044, -0.048 }, { 0.027, -0.044, -0.035 } },
		0.009
	),
	finger(
		{ { -0.039, -0.062, -0.020 }, { -0.020, -0.062, -0.040 }, { 0.005, -0.062, -0.042 }, { 0.020, -0.062, -0.032 } },
		0.008
	),
	finger({ { -0.040, 0.012, 0.010 }, { -0.032, 0.032, -0.020 }, { -0.026, 0.040, -0.048 } }, 0.0105), -- polegar
}, {
	{ c = { -0.046, -0.020, 0.004 }, s = { 0.022, 0.080, 0.070 } },
})

-- ===== mão aberta (escrita como direita) =====
local FLAT_C: { Chain } = {
	finger({ { 0.000, 0.000, 0.030 }, { 0.000, -0.010, 0.060 } }, 0.023), -- pulso
	finger({ { -0.026, 0.000, -0.030 }, { -0.027, -0.004, -0.056 }, { -0.027, -0.012, -0.074 } }, 0.0085),
	finger({ { -0.009, 0.000, -0.032 }, { -0.009, -0.004, -0.062 }, { -0.009, -0.012, -0.082 } }, 0.0095),
	finger({ { 0.009, 0.000, -0.032 }, { 0.009, -0.004, -0.059 }, { 0.009, -0.012, -0.078 } }, 0.009),
	finger({ { 0.026, 0.000, -0.030 }, { 0.027, -0.004, -0.054 }, { 0.027, -0.012, -0.070 } }, 0.008),
	finger({ { 0.036, 0.000, 0.020 }, { 0.046, -0.006, -0.010 }, { 0.044, -0.012, -0.032 } }, 0.0105),
}
local FLAT_B: { Box } = { { c = { 0.000, 0.000, 0.004 }, s = { 0.075, 0.022, 0.080 } } }

MaosPose.POSES = {
	grip = { hand = "R", chains = GRIP_C, boxes = GRIP_B },
	support = { hand = "L", chains = SUP_C, boxes = SUP_B },
	cup = { hand = "L", chains = CUP_C, boxes = CUP_B },
	flat = { hand = "R", chains = FLAT_C, boxes = FLAT_B },
} :: { [string]: Pose }

-- Forma pronta para um lado ("R" ou "L"): a escrita para o outro lado é espelhada em x.
function MaosPose.get(name: string, side: string): Pose
	local p = MaosPose.POSES[name] or MaosPose.POSES[if side == "L" then "support" else "grip"]
	if p.hand == side then
		return p
	end
	local chains: { Chain } = {}
	for _, ch in p.chains do
		local pts = {}
		for _, v in ch.pts do
			table.insert(pts, { -v[1], v[2], v[3] })
		end
		table.insert(chains, { pts = pts, r = ch.r, mat = ch.mat })
	end
	local boxes: { Box } = {}
	for _, b in p.boxes do
		table.insert(boxes, { c = { -b.c[1], b.c[2], b.c[3] }, s = b.s })
	end
	return { hand = side, chains = chains, boxes = boxes }
end

-- Caixa que contém a forma (m): mín. e máx. por eixo.
function MaosPose.bounds(p: Pose): (V, V)
	local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local function grow(c: V, h: V)
		for i = 1, 3 do
			lo[i] = math.min(lo[i], c[i] - h[i])
			hi[i] = math.max(hi[i], c[i] + h[i])
		end
	end
	for _, ch in p.chains do
		for _, v in ch.pts do
			grow(v, { ch.r, ch.r, ch.r })
		end
	end
	for _, b in p.boxes do
		grow(b.c, { b.s[1] / 2, b.s[2] / 2, b.s[3] / 2 })
	end
	return lo, hi
end

-- Antebraço (m): pulso de pele e manga do uniforme. Comprimento até o cotovelo: FOREARM_M.
MaosPose.FOREARM_M = 0.27
MaosPose.WRIST = { r = 0.026, len = 0.05 }
MaosPose.SLEEVE = {
	US = { r0 = 0.040, r1 = 0.047, cuff = 0.050, cuffLen = 0.035 }, -- manga arregaçada (dobra grossa)
	VC = { r0 = 0.037, r1 = 0.043, cuff = 0.0, cuffLen = 0.0 }, -- manga lisa, mais fina
}

return MaosPose
