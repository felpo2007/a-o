--!strict
-- D-254 e D-255: o setor piloto do Objetivo C (Vila). Módulo PURO: só dados e regras.
-- A planta é gerada por tools/vila_piloto_plano.py (Shared/VilaPovoado) e a montagem fica em
-- Modules/VilaPilotoService. Posições em metros a partir do centro do objetivo.
-- Só entra no jogo publicado com LIGADA = true, depois da aprovação do dono. No Studio: atributo
-- VT65DevPiloto = true no workspace, no modo Edit, antes do Play.
local Povoado = require(script and (script :: any).Parent.VilaPovoado or "./VilaPovoado") :: any

local VilaPiloto = {}

VilaPiloto.LIGADA = false
VilaPiloto.SETOR = "Vila"
VilaPiloto.MEIO_M = Povoado.MEIO :: number -- metade do lado do setor
VilaPiloto.POVOADO = Povoado.CONSTRUCOES :: { any }
VilaPiloto.VIELAS = Povoado.VIELAS :: { { { number } } }
VilaPiloto.LAGOA = Povoado.LAGOA :: { x: number, z: number, a: number, b: number, giro: number }
VilaPiloto.PASSARELAS = Povoado.PASSARELAS :: { any }
VilaPiloto.CENA = Povoado.CENA :: { any }
VilaPiloto.PLANTAS = Povoado.PLANTAS :: { any }
VilaPiloto.CERCAS = Povoado.CERCAS :: { any }

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

local function P(key: string, x: number, z: number, giro: number, escala: number?): Peca
	return { key = key, x = x, z = z, giro = giro, escala = escala }
end
-- O que não vem da planta: a entrada sul, a cobertura baixa do cruzamento e a lama da rua
VilaPiloto.PECAS = {
	P("ret_vila_posto", -1.5, 47, 0),
	P("ret_vila_sacos", 9.5, 8, -45),
	P("ret_vila_sacos", -9.5, 14.5, 45),
	P("ret_vila_sacos", 14, -8.5, 20),
	P("ret_vila_sacos", -8, -5, 135),
	P("ret_vila_carga", 21, 5, -10),
	P("ret_vila_carga", 7, -14, 35),
	P("exp_carroca", 18, 7.5, 200),
} :: { Peca }

-- As vias que passam pela área (medidas em Data/Roads, metros a partir do centro)
VilaPiloto.RUAS = {
	{ { -50, 49 }, { -23, 23 }, { -5, 5 }, { -1, 0 } },
	{ { -1, 0 }, { -2, 9 }, { -2, 18 }, { -1, 36 }, { -1, 80 } },
	{ { -1, 0 }, { 8, -5 }, { 17, -13 }, { 35, -31 }, { 60, -56 } },
	{ { 8, -4 }, { 17, -1 }, { 26, 0 }, { 53, 0 }, { 85, 0 } },
} :: { { { number } } }

function VilaPiloto.noSetor(x: number, z: number, folga: number?): boolean
	local m = VilaPiloto.MEIO_M + (folga or 0)
	return math.abs(x) <= m and math.abs(z) <= m
end

local function distVias(vias: { { { number } } }, x: number, z: number): number
	local melhor = math.huge
	for _, via in vias do
		for i = 1, #via - 1 do
			local a, b = via[i], via[i + 1]
			local ux, uz = b[1] - a[1], b[2] - a[2]
			local t = math.clamp(((x - a[1]) * ux + (z - a[2]) * uz) / (ux * ux + uz * uz), 0, 1)
			local dx, dz = x - (a[1] + t * ux), z - (a[2] + t * uz)
			melhor = math.min(melhor, dx * dx + dz * dz)
		end
	end
	return math.sqrt(melhor)
end

-- Distância (m) até o eixo da via mais próxima. A viela é estreita: conta como 1,7 m mais longe
function VilaPiloto.distRua(x: number, z: number): number
	return math.min(distVias(VilaPiloto.RUAS, x, z), distVias(VilaPiloto.VIELAS, x, z) + 1.7)
end

-- O piso fica sob a construção: ali não nasce capim nem cai peça solta
local RAIOS2: { number } = {}
for k, c in VilaPiloto.POVOADO do
	RAIOS2[k] = ((c.lx / 2 + 3) ^ 2 + (c.lz / 2 + 3) ^ 2)
end
function VilaPiloto.sobConstrucao(x: number, z: number, folga: number?): boolean
	local f = folga or 0.6
	for k, c in VilaPiloto.POVOADO do
		local dx, dz = x - c.x, z - c.z
		if dx * dx + dz * dz < RAIOS2[k] then
			local a = math.rad(c.giro)
			local ca, sa = math.cos(a), math.sin(a)
			if math.abs(dx * ca - dz * sa) < c.lx / 2 + f and math.abs(dx * sa + dz * ca) < c.lz / 2 + f then
				return true
			end
		end
	end
	return false
end

-- Trechos afundados na rua: depressões rasas do próprio terreno, sem água e sem Mud. O voxel
-- de 1,1 m faz da poça um polígono claro, e o Mud deste mapa é quase preto (Studio, lote 122)
VilaPiloto.POCAS = {
	{ x = -0.8, z = 12, a = 2.6, b = 1.7, giro = 80 },
	{ x = -2, z = 25, a = 3.0, b = 1.8, giro = 75 },
	{ x = 14, z = -2, a = 2.2, b = 1.5, giro = 130 },
	{ x = 27, z = 0.5, a = 2.8, b = 1.6, giro = 10 },
	{ x = -19, z = 19.5, a = 2.4, b = 1.6, giro = 45 },
	{ x = 23, z = -22, a = 2.8, b = 1.7, giro = 50 },
} :: { { x: number, z: number, a: number, b: number, giro: number } }

-- 0 no meio do trecho afundado mais próximo, 1 na beira
function VilaPiloto.pocaE(x: number, z: number): number
	local melhor = math.huge
	for _, q in VilaPiloto.POCAS do
		local dx, dz = x - q.x, z - q.z
		if dx * dx + dz * dz < 25 then
			local a = math.rad(q.giro)
			local u = dx * math.cos(a) - dz * math.sin(a)
			local v = dx * math.sin(a) + dz * math.cos(a)
			melhor = math.min(melhor, math.sqrt((u / q.a) ^ 2 + (v / q.b) ^ 2))
		end
	end
	return melhor
end

-- 0 no meio da lagoa, 1 na margem, mais de 1 fora dela
function VilaPiloto.lagoa(x: number, z: number): number
	local l = VilaPiloto.LAGOA
	local a = math.rad(l.giro)
	local dx, dz = x - l.x, z - l.z
	local u = dx * math.cos(a) - dz * math.sin(a)
	local v = dx * math.sin(a) + dz * math.cos(a)
	return math.sqrt((u / l.a) ^ 2 + (v / l.b) ^ 2)
end

local function suave(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Relevo do setor, em metros: ondulação dos quintais, vala na beira das ruas e a bacia da lagoa.
-- n1 e n2: ruídos de 0 a 1. Devolve a soma na altura e o nível da água em relação ao chão original.
function VilaPiloto.relevo(x: number, z: number, n1: number, n2: number, sob: boolean): (number, number?)
	local borda = 1 - suave(VilaPiloto.MEIO_M, VilaPiloto.MEIO_M + 9, math.max(math.abs(x), math.abs(z)))
	if borda <= 0 then
		return 0, nil
	end
	local e = VilaPiloto.lagoa(x, z)
	if e < 1 then
		return -1.3 * (1 - e * e) - 0.06, -0.26
	end
	if sob then
		return 0, nil
	end
	local ep = VilaPiloto.pocaE(x, z)
	if ep < 1 then
		return -0.14 * (1 - ep * ep), nil
	end
	local dReal = distVias(VilaPiloto.RUAS, x, z)
	local fora = suave(2.6, 5.0, dReal)
	local dh = ((n1 - 0.5) * 0.85 + (n2 - 0.5) * 0.2) * fora
	dh -= 0.32 * math.exp(-(((dReal - 3.7) / 0.7) ^ 2))
	dh *= suave(1, 1.5, e)
	return dh * borda, nil
end

-- O material do chão. d: distância em quadrado ao centro; base: o do mapa (nil = o da classe);
-- r1 e r2: ruídos de 0 a 1; dRua: metros até a via; sob: há construção; e: a escala da lagoa.
-- Sem LeafyGrass: neste mapa ele fica quase preto e fazia uma faixa escura na beira da rua.
function VilaPiloto.solo(
	d: number,
	base: string?,
	classe: number,
	r1: number,
	r2: number,
	dRua: number,
	sob: boolean,
	e: number?
): string?
	if d > VilaPiloto.MEIO_M + 5 + (r1 - 0.5) * 8 or classe == 5 or classe == 2 then
		return base
	end
	if e and e < 0.98 then
		return "Mud"
	end
	if e and e < 1.4 then
		return if r2 > 0.45 then "Grass" else "Ground"
	end
	if dRua < 2.7 or sob then
		return "Ground"
	end
	if dRua < 3.9 then
		return if r2 > 0.42 then "Grass" else "Ground"
	end
	return if r1 < 0.8 then "Grass" else "Ground"
end

-- As marcas do chão (2 triângulos cada): trilhas de roda ao longo das vias e folhas nos quintais
function VilaPiloto.marcas(): { Peca }
	local out: { Peca } = {}
	for _, via in VilaPiloto.RUAS do
		for i = 1, #via - 1 do
			local a, b = via[i], via[i + 1]
			local ux, uz = b[1] - a[1], b[2] - a[2]
			local comp = math.sqrt(ux * ux + uz * uz)
			local n = math.max(1, math.floor(comp / 8))
			for k = 0, n - 1 do
				local f = (k + 0.5) / n
				local x, z = a[1] + ux * f, a[2] + uz * f
				if VilaPiloto.noSetor(x, z, 2) then
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
	for _ = 1, 400 do
		local x, z = (r() - 0.5) * 2 * VilaPiloto.MEIO_M, (r() - 0.5) * 2 * VilaPiloto.MEIO_M
		local giro, esc = r() * 360, 0.75 + r() * 0.5
		local fora = VilaPiloto.distRua(x, z) <= 3.9 or VilaPiloto.sobConstrucao(x, z) or VilaPiloto.lagoa(x, z) < 1.2
		if postas < 46 and not fora then
			table.insert(out, { key = "ret_vila_detritos", x = x, z = z, giro = giro, escala = esc, plano = true })
			postas += 1
		end
	end
	return out
end

-- Capim parado (regra de vento zero): a grama nativa do terreno se mexe mesmo com GlobalWind 0
VilaPiloto.MAX_CAPIM = 620
function VilaPiloto.capimPontos(): { { x: number, z: number, giro: number, escala: number } }
	local out = {}
	local s = 1971
	local function r(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
	local passo = 3.1
	local n = math.floor(VilaPiloto.MEIO_M / passo)
	for i = -n, n do
		for j = -n, n do
			local x, z = i * passo + (r() - 0.5) * 2.4, j * passo + (r() - 0.5) * 2.4
			local giro, escala = r() * 360, 0.8 + r() * 0.45
			local ok = VilaPiloto.noSetor(x, z) and VilaPiloto.distRua(x, z) > 3.9 and VilaPiloto.lagoa(x, z) > 1.15
			if ok and not VilaPiloto.sobConstrucao(x, z) then
				table.insert(out, { x = x, z = z, giro = giro, escala = escala })
			end
		end
	end
	return out
end

-- A beira das ruas: tufos de capim e pedras soltas, para o chão não terminar numa linha reta
function VilaPiloto.bordaPontos(): { { key: string, x: number, z: number, giro: number, escala: number } }
	local out = {}
	local s = 1973
	local function r(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
	for _, via in VilaPiloto.RUAS do
		for i = 1, #via - 1 do
			local a, b = via[i], via[i + 1]
			local ux, uz = b[1] - a[1], b[2] - a[2]
			local comp = math.sqrt(ux * ux + uz * uz)
			local nx, nz = -uz / comp, ux / comp
			local passos = math.max(1, math.floor(comp / 1.7))
			for k = 0, passos do
				local f = (k + r()) / passos
				for _, lado in { -1, 1 } do
					local d = 3.0 + r()
					local x = a[1] + ux * f + nx * lado * d
					local z = a[2] + uz * f + nz * lado * d
					local sorte, giro, esc = r(), r() * 360, 0.52 + r() * 0.3
					local livre = VilaPiloto.noSetor(x, z)
						and not VilaPiloto.sobConstrucao(x, z, 0.3)
						and VilaPiloto.lagoa(x, z) > 1.15
						and VilaPiloto.pocaE(x, z) > 1.3
						and distVias(VilaPiloto.RUAS, x, z) >= 2.9
					if livre and sorte < 0.72 then
						local key = if sorte < 0.18 then "ret_pov_p_pedras" else "ret_vila_capim"
						table.insert(out, { key = key, x = x, z = z, giro = giro, escala = esc })
					end
				end
			end
		end
	end
	return out
end

return VilaPiloto
