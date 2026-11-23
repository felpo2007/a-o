--!strict
-- D-254 (prompt V5, §19): a área piloto do Objetivo C (Vila). Módulo PURO: só dados e regras.
-- A montagem fica em Modules/VilaPilotoService. Posições em metros a partir do centro do objetivo.
--   - TROCAS: a construção antiga sai e a nova entra no mesmo lugar e giro (mesmo patamar, mesma rua);
--   - PECAS: o que é novo (posto, torre, sacos, carga, poças e plantas).
-- Só entra no jogo publicado com LIGADA = true, depois da aprovação do dono. No Studio: atributo
-- VT65DevPiloto = true no workspace, no modo Edit, antes do Play.
local VilaPiloto = {}

VilaPiloto.LIGADA = false
VilaPiloto.SETOR = "Vila"
VilaPiloto.RAIO_M = 72 -- até onde o chão é repintado
VilaPiloto.RAIO_CERCA_M = 72 -- cercas antigas trocadas pela leve

export type Troca = { de: string, x: number, z: number, para: string }
export type Peca = {
	key: string,
	x: number,
	z: number,
	giro: number, -- graus
	escala: number?,
	plano: boolean?, -- poça: sem colisão e sem sombra
	planta: boolean?, -- folhagem: sem colisão
	decal: string?, -- marca de borda suave em AssetIds.ChaoVila
	soDecal: boolean?, -- não põe a malha, só o decal
}

VilaPiloto.TROCAS = {
	{ de = "Vila_dinh", x = -17.6, z = -17.6, para = "ret_vila_dinh" },
	{ de = "Vila_chua", x = 18.5, z = 18.5, para = "ret_sino_salao" },
	{ de = "Vila_banca", x = -15.6, z = -8.3, para = "ret_merc_banca_a" },
	{ de = "Vila_banca", x = -6.4, z = -17.5, para = "ret_merc_banca_b" },
	{ de = "Vila_banca", x = -24.8, z = 0.9, para = "ret_merc_banca_c" },
	{ de = "Vila_banca", x = 2.8, z = -26.7, para = "ret_merc_banca_a" },
	{ de = "vila_casa_03", x = 3.5, z = -38.1, para = "ret_vila_palafita_a" },
	{ de = "vila_casa_04", x = 37.5, z = -20.5, para = "ret_vila_palafita_b" },
	{ de = "vila_casa_02", x = -43.4, z = -13.0, para = "ret_vila_terra" },
	{ de = "vila_casa_03", x = 44.2, z = 11.9, para = "ret_vila_palafita_a" },
	{ de = "vila_casa_03", x = -39.7, z = 24.0, para = "ret_vila_palafita_b" },
	{ de = "vila_casa_04", x = 35.5, z = 31.9, para = "ret_vila_terra" },
	{ de = "vila_casa_10", x = 51.6, z = -11.0, para = "ret_vila_palafita_b" },
	{ de = "vila_casa_06", x = 28.4, z = -46.9, para = "ret_vila_terra" },
	{ de = "vila_casa_03", x = 19.1, z = 51.4, para = "ret_vila_palafita_a" },
	{ de = "vila_casa_05", x = -32.7, z = 57.8, para = "ret_vila_palafita_b" },
	{ de = "vila_casa_09", x = 50.5, z = 40.4, para = "ret_vila_palafita_a" },
	{ de = "vila_casa_08", x = 8.3, z = -63.5, para = "ret_vila_palafita_b" },
} :: { Troca }

local function P(key: string, x: number, z: number, giro: number, escala: number?): Peca
	return { key = key, x = x, z = z, giro = giro, escala = escala }
end
local function poca(x: number, z: number, giro: number, escala: number): Peca
	return { key = "ret_vila_poca", x = x, z = z, giro = giro, escala = escala, plano = true, decal = "poca_halo" }
end
local function planta(key: string, x: number, z: number, giro: number, escala: number?): Peca
	return { key = key, x = x, z = z, giro = giro, escala = escala, planta = true }
end

VilaPiloto.PECAS = {
	-- a entrada sul e a torre que vigia o pátio
	P("ret_vila_posto", -1.5, 47, 0),
	P("ret_vila_torre", 30, -11, 90),
	-- cobertura baixa nos quatro cantos do cruzamento, sem fechar a pista
	P("ret_vila_sacos", 9.5, 8, -45),
	P("ret_vila_sacos", -9.5, 18, 45),
	P("ret_vila_sacos", 21, -9, 20),
	P("ret_vila_sacos", -8, -5, 135),
	P("ret_vila_carga", 27, 7, -10),
	P("ret_vila_carga", -9, 28, 80),
	P("ret_vila_carga", 14, -24, 40),
	P("ret_vila_carga", -29, 11, 120),
	-- a lama da rua
	poca(3, 11, 20, 0.72),
	poca(-2, 25, 75, 0.9),
	poca(14, -2, 130, 0.65),
	poca(27, 0.5, 10, 0.83),
	poca(-19, 19.5, 45, 0.72),
	poca(12, -11, 45, 0.58),
	poca(-1, 37, 100, 0.65),
	poca(38, -1, 170, 0.76),
	poca(23, -22, 50, 0.86),
	poca(-33, 33, 40, 0.65),
	poca(-1, 60, 90, 0.79),
	poca(58, 0, 0, 0.72),
	-- quintais: samambaia e bananeira junto das casas, fora das ruas
	planta("exp_samambaia", 12, -33, 10),
	planta("exp_samambaia", -4, -31, 80),
	planta("exp_samambaia", 30, -14, 140),
	planta("exp_samambaia", 46, -2.5, 30),
	planta("exp_samambaia", 33, 20, 200),
	planta("exp_samambaia", 26, 30, 260),
	planta("exp_samambaia", 10, 34, 40),
	planta("exp_samambaia", -12, 40, 110),
	planta("exp_samambaia", -30, 18, 300),
	planta("exp_samambaia", -36, 6, 170),
	planta("exp_samambaia", -33, -8, 60),
	planta("exp_samambaia", -29, -27, 220),
	planta("banana", 22, -35, 30, 1.0),
	planta("banana", 42, 22, 140, 1.1),
	planta("banana", -24, 40, 200, 0.95),
	planta("banana", -50, 8, 75, 1.05),
	planta("banana", 58, 23, 300, 1.0),
	planta("shrub", 8, 30, 15, 1.2),
	planta("shrub", -22, 31, 95, 1.1),
	planta("shrub", 39, -8, 160, 1.15),
	planta("shrub", 34, 44, 240, 1.2),
	planta("elephant_grass", -12, 26, 30, 0.8),
	planta("elephant_grass", 11, 40, 120, 0.8),
	planta("elephant_grass", 33, 9, 210, 0.75),
	planta("elephant_grass", -26, 22, 300, 0.8),
	planta("exp_samambaia", -12, 34, 20),
	planta("exp_samambaia", 10, 26, 150),
	planta("exp_samambaia", 41, 8, 70),
	planta("exp_samambaia", 62, 9, 240),
	planta("exp_samambaia", -6, 56, 330),
	planta("exp_samambaia", 12, 60, 100),
	-- a vida da rua: carroça, palha e potes junto das casas
	P("exp_carroca", -11.5, 44, 20),
	P("straw_stack", 30, 18, 0, 0.85),
	P("straw_stack", -25, 12, 40, 0.8),
	P("water_jar", 33.5, 6, 0),
	P("water_jar", 34.5, 7, 60),
	P("water_jar", -13, 25, 30),
	P("ret_vila_sacos", 12, 43, 90),
	P("ret_vila_carga", 11, 49, 15),
	-- mais cobertura no pátio, fora das pistas
	P("ret_vila_sacos", 15, 6.5, 12),
	P("ret_vila_sacos", -14, 9, 70),
	P("ret_vila_carga", 7, -14, 35),
	P("exp_carroca", 24, -5.5, 200),
} :: { Peca }

-- As vias que passam pela área (medidas em Data/Roads, metros a partir do centro)
VilaPiloto.RUAS = {
	{ { -50, 49 }, { -23, 23 }, { -5, 5 }, { -1, 0 } },
	{ { -1, 0 }, { -2, 9 }, { -2, 18 }, { -1, 36 }, { -1, 80 } },
	{ { -1, 0 }, { 8, -5 }, { 17, -13 }, { 35, -31 }, { 60, -56 } },
	{ { 8, -4 }, { 17, -1 }, { 26, 0 }, { 53, 0 }, { 85, 0 } },
} :: { { { number } } }

-- Distância (m) até o eixo da via mais próxima
function VilaPiloto.distRua(x: number, z: number): number
	local melhor = math.huge
	for _, via in VilaPiloto.RUAS do
		for i = 1, #via - 1 do
			local a, b = via[i], via[i + 1]
			local ux, uz = b[1] - a[1], b[2] - a[2]
			local t = math.clamp(((x - a[1]) * ux + (z - a[2]) * uz) / (ux * ux + uz * uz), 0, 1)
			local dx, dz = x - (a[1] + t * ux), z - (a[2] + t * uz)
			melhor = math.min(melhor, math.sqrt(dx * dx + dz * dz))
		end
	end
	return melhor
end

-- O piso fica sob a construção: ali não pode nascer capim, que atravessaria o assoalho
local RAIO_PISO: { [string]: number } = {
	ret_vila_dinh = 12,
	ret_sino_salao = 11,
	ret_vila_palafita_a = 7.5,
	ret_vila_palafita_b = 6.5,
	ret_vila_terra = 7.5,
	ret_merc_banca_a = 2.2,
	ret_merc_banca_b = 2.2,
	ret_merc_banca_c = 2.2,
}
function VilaPiloto.sobConstrucao(x: number, z: number): boolean
	for _, t in VilaPiloto.TROCAS do
		local r = RAIO_PISO[t.para] or 6
		if (x - t.x) ^ 2 + (z - t.z) ^ 2 < r * r then
			return true
		end
	end
	return false
end

-- O material do chão dentro da área. d: metros do centro; base: o que o mapa daria (nil = o da classe);
-- r1 e r2: ruídos de 0 a 1 (mancha grande e pequena); dRua: metros até o eixo da via; sob: há construção.
-- Pista de terra com as duas trilhas de roda em barro, beira gasta e quintal de capim.
function VilaPiloto.solo(
	d: number,
	base: string?,
	classe: number,
	r1: number,
	r2: number,
	dRua: number,
	sob: boolean
): string?
	if d > VilaPiloto.RAIO_M + (r1 - 0.5) * 12 or classe == 5 or classe == 2 then
		return base
	end
	-- sem Mud aqui: em voxel ele vira mancha angulosa; os sulcos e a lama ficam nos decais
	if dRua < 4.4 then
		return "Ground"
	end
	if sob then
		return "Ground"
	end
	if dRua < 6.2 then
		return if r2 > 0.52 then "LeafyGrass" else "Ground"
	end
	if r1 < 0.62 then
		return "Grass"
	end
	return if r1 < 0.8 and r2 <= 0.62 then "LeafyGrass" else "Ground"
end

-- As marcas do chão (2 triângulos cada): trilhas de roda ao longo das vias e folhas nos quintais
function VilaPiloto.marcas(): { Peca }
	local out: { Peca } = {}
	for _, via in VilaPiloto.RUAS do
		for i = 1, #via - 1 do
			local a, b = via[i], via[i + 1]
			local ux, uz = b[1] - a[1], b[2] - a[2]
			local comp = math.sqrt(ux * ux + uz * uz)
			local n = math.max(1, math.floor(comp / 5.2))
			for k = 0, n - 1 do
				local f = (k + 0.5) / n
				local x, z = a[1] + ux * f, a[2] + uz * f
				if math.sqrt(x * x + z * z) < VilaPiloto.RAIO_M - 4 then
					local giro = math.deg(math.atan2(-uz, ux))
					table.insert(out, {
						key = "ret_vila_trilha",
						x = x,
						z = z,
						giro = giro,
						plano = true,
						decal = "trilha",
						soDecal = true,
					})
				end
			end
		end
	end
	-- gerador fixo: as folhas caem sempre nos mesmos lugares
	local s = 1965
	local function r(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
	local postas = 0
	for _ = 1, 160 do
		local ang, raio, giro, esc = r() * math.pi * 2, 8 + r() * 56, r() * 360, 0.75 + r() * 0.5
		local x, z = math.cos(ang) * raio, math.sin(ang) * raio
		if postas < 34 and VilaPiloto.distRua(x, z) > 5.2 and not VilaPiloto.sobConstrucao(x, z) then
			table.insert(out, { key = "ret_vila_detritos", x = x, z = z, giro = giro, escala = esc, plano = true })
			postas += 1
		end
	end
	return out
end

-- Capim parado (regra de vento zero): a grama nativa do terreno se mexe mesmo com GlobalWind 0
VilaPiloto.MAX_CAPIM = 720
function VilaPiloto.capimPontos(): { { x: number, z: number, giro: number, escala: number } }
	local out = {}
	local s = 1971
	local function r(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
	local passo = 3
	local n = math.floor(VilaPiloto.RAIO_M / passo)
	for i = -n, n do
		for j = -n, n do
			local x, z = i * passo + (r() - 0.5) * 2.2, j * passo + (r() - 0.5) * 2.2
			local giro, escala = r() * 360, 0.85 + r() * 0.4
			local fora = math.sqrt(x * x + z * z) >= VilaPiloto.RAIO_M
			if not fora and VilaPiloto.distRua(x, z) > 5.4 and not VilaPiloto.sobConstrucao(x, z) then
				table.insert(out, { x = x, z = z, giro = giro, escala = escala })
			end
		end
	end
	return out
end

-- Trechos de cerca de bambu ao longo das vias (x1, z1, x2, z2); o que cairia numa construção fica de fora
VilaPiloto.CERCAS = {
	{ -8.5, 22, -8.5, 42 },
	{ 6.8, 30, 6.8, 42 },
	{ -9, 52, -9, 70 },
	{ 7, 54, 7, 70 },
	{ 30, 6.5, 40, 6.5 },
	{ 60, 6.5, 72, 6.5 },
	{ 60, -6.5, 74, -6.5 },
	{ -33, 40, -48, 55 },
	{ -44, 36, -56, 48 },
	{ 22, -38, 40, -56 },
	{ -22, 28, -30, 36 },
} :: { { number } }

return VilaPiloto
