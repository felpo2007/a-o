--!strict
-- Acessibilidade (Parte 11, "Lançamento"): cores dos traçantes por tipo de visão de cor, campo de
-- visão e legendas. Módulo puro: inclui a simulação de daltonismo (Machado, Oliveira e Fernandes,
-- 2009, severidade 1,0) e a diferença de cor ΔE76 em CIELAB, para o teste MEDIR a distinção.
local Accessibility = {}

export type RGB = { number } -- 0..255

-- Histórico: traçante dos EUA vermelho, do bloco soviético verde. Na simulação de deuteranopia os
-- dois ficam a ΔE 24 (quase iguais); laranja x azul fica acima de 130 (medido no teste).
local HISTORIC = { US = { 255, 80, 60 }, VC = { 90, 255, 120 } }
local ORANGE_BLUE = { US = { 255, 170, 0 }, VC = { 60, 140, 255 } }

Accessibility.MODES = { "off", "protan", "deutan", "tritan" }
Accessibility.MODE_NAMES = {
	off = "desligado (vermelho x verde histórico)",
	protan = "protanopia (laranja x azul)",
	deutan = "deuteranopia (laranja x azul)",
	tritan = "tritanopia (vermelho x verde)",
}
Accessibility.TRACER = {
	off = HISTORIC,
	protan = ORANGE_BLUE,
	deutan = ORANGE_BLUE,
	tritan = HISTORIC, -- vermelho x verde já é o par mais distinto para tritanopia (ΔE 143)
} :: { [string]: { [string]: RGB } }

Accessibility.FOV_DEFAULT = 70
Accessibility.FOV_MIN = 60
Accessibility.FOV_MAX = 90

local MACHADO = {
	protan = {
		{ 0.152286, 1.052583, -0.204868 },
		{ 0.114503, 0.786281, 0.099216 },
		{ -0.003882, -0.048116, 1.051998 },
	},
	deutan = {
		{ 0.367322, 0.860646, -0.227968 },
		{ 0.280085, 0.672501, 0.047413 },
		{ -0.011820, 0.042940, 0.968881 },
	},
	tritan = {
		{ 1.255528, -0.076749, -0.178779 },
		{ -0.078411, 0.930809, 0.147602 },
		{ 0.004733, 0.691367, 0.303900 },
	},
}

function Accessibility.tracer(faction: string, mode: string?): RGB
	local pal = Accessibility.TRACER[mode or "off"] or HISTORIC
	return pal[faction] or pal.VC
end

local function toLinear(c: number): number
	local v = c / 255
	return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end

-- cor como a vê uma pessoa com o tipo de daltonismo (RGB linear)
function Accessibility.simulate(rgb: RGB, mode: string): { number }
	local l = { toLinear(rgb[1]), toLinear(rgb[2]), toLinear(rgb[3]) }
	local m = MACHADO[mode]
	if not m then
		return l
	end
	local out = {}
	for i = 1, 3 do
		out[i] = m[i][1] * l[1] + m[i][2] * l[2] + m[i][3] * l[3]
	end
	return out
end

local function lab(l: { number }): (number, number, number)
	local r, g, b = math.clamp(l[1], 0, 1), math.clamp(l[2], 0, 1), math.clamp(l[3], 0, 1)
	local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	local function f(t: number): number
		return if t > 216 / 24389 then t ^ (1 / 3) else (24389 / 27 * t + 16) / 116
	end
	local fx, fy, fz = f(x), f(y), f(z)
	return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)
end

-- ΔE76 entre duas cores vistas por quem tem o tipo `mode` ("off" = visão típica)
function Accessibility.deltaE(a: RGB, b: RGB, mode: string): number
	local l1, a1, b1 = lab(Accessibility.simulate(a, mode))
	local l2, a2, b2 = lab(Accessibility.simulate(b, mode))
	return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

-- Legenda de som (para quem joga sem áudio): texto curto com direção e distância aproximadas.
local DIRS = { "norte", "nordeste", "leste", "sudeste", "sul", "sudoeste", "oeste", "noroeste" }
-- dx, dz em metros no quadro local (+X = leste, +Z = sul)
function Accessibility.direction(dx: number, dz: number): string
	local ang = math.deg(math.atan2(dx, -dz)) % 360 -- 0 = norte, sentido horário
	return DIRS[math.floor((ang + 22.5) / 45) % 8 + 1]
end

function Accessibility.caption(what: string, dx: number, dz: number): string
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 15 then
		return string.format("[%s, perto]", what)
	end
	local step = if d < 200 then 25 elseif d < 1000 then 100 else 500
	return string.format("[%s, ~%d m a %s]", what, math.floor(d / step + 0.5) * step, Accessibility.direction(dx, dz))
end

return Accessibility
