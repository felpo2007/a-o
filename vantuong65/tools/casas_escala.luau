--!nocheck
-- D-236 (dono: "as casas estao mt pequenas para os soldados aumente o tamanho de todas elas").
-- Escolhe quanto cada casa cresce, até 25%, sem encostar em estrada, beco, água, nascer, centro da
-- captura ou outra construção. O anexo do próprio quintal não conta: o ArtPlan tira o que ficar embaixo.
-- Grava Modules/CasasEscala.luau e assets/estatico/ajuste_casas.json (novo pivô de cada casa da arte
-- fixa, sem precisar recopiar do Studio).
--   lune run tools/casas_escala.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local R = require :: any

local WorldData = R("../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../src/ServerStorage/VT65Build/Data/Roads")
local Bases = R("../src/ServerStorage/VT65Build/Data/Bases")
local MapConfig = R("../src/ReplicatedStorage/Shared/MapConfig")
local ArtPlan = R("../src/ServerScriptService/Modules/ArtPlan")
local CasasEscala = R("../src/ServerScriptService/Modules/CasasEscala")
local StaticArt = R("../src/ServerScriptService/Modules/StaticArt")
local AssetIds = R("../src/ReplicatedStorage/Shared/AssetIds")
local Expansao = R("../src/ServerScriptService/Modules/Expansao")
local M = 0.28

local FATORES = { 1.25, 1.2, 1.15, 1.1, 1.05 }
local CASA = {
	house_tile = true,
	hut_thatch = true,
	hut_veranda = true,
	exp_palafita_a = true,
	exp_palafita_b = true,
	exp_casas_ligadas = true,
	exp_casa_vala = true,
	exp_casa_verde = true,
	exp_celeiro = true,
	exp_deposito = true,
	exp_galpao = true,
	exp_telheiro = true,
	exp_abrigo = true,
	exp_carroca = true,
	exp_ruina = true,
	exp_sobrado_a = true,
	exp_sobrado_b = true,
	exp_sobrado_c = true,
	exp_sobrado_d = true,
}
local function ehCasa(it): boolean
	return CASA[it.key] == true or string.sub(it.key, 1, 9) == "vila_casa"
end
local CHAO_RUIM = { estrada = true, beco = true, riacho = true, lamina = true, dique = true, clareira = true }

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, R("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local dados = { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig }
local function has(key: string): boolean
	local id = AssetIds.Models[key]
	return type(id) == "number" and id ~= 0
end
local function plano(tabela)
	CasasEscala.f = tabela
	local ctx = ArtPlan.load(world, dados)
	return ctx, ArtPlan.structures(ctx, has)
end

local ctx0, st0 = plano({})
local casas, outros = {}, {}
for _, it in st0 do
	if ehCasa(it) then
		table.insert(casas, it)
	elseif not it.foliage then
		table.insert(outros, it)
	end
end

local function chaoRuim(it, k): string?
	local ca, sa = math.cos(it.yaw), math.sin(it.yaw)
	for i = -4, 4 do
		for j = -4, 4 do
			if math.abs(i) == 4 or math.abs(j) == 4 then
				local lx, lz = i / 4 * it.hx * k, j / 4 * it.hz * k
				local x, z = it.x + lx * ca + lz * sa, it.z - lx * sa + lz * ca
				local p = ArtPlan.groundProblem(ctx0, x, z, 0.3 / M)
				if p and CHAO_RUIM[p] then
					return p
				end
				for _, sp in MapConfig.Strongpoints do
					local antes = math.sqrt((it.x - sp.x) ^ 2 + (it.z - sp.z) ^ 2) * M
					local agora = math.sqrt((x - sp.x) ^ 2 + (z - sp.z) ^ 2) * M
					if agora < 13 and agora < antes then
						return "centro da captura"
					end
				end
			end
		end
	end
	return nil
end

local function maior(it, f)
	return { x = it.x, z = it.z, yaw = it.yaw, hx = it.hx * f, hz = it.hz * f }
end

-- os caminhos e as valas da expansão, com a mesma conta do tools/expansao_check
local function distSeg(px, pz, x1, z1, x2, z2)
	local dx, dz = x2 - x1, z2 - z1
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - x1) * dx + (pz - z1) * dz) / l2, 0, 1) else 0
	return math.sqrt((x1 + t * dx - px) ^ 2 + (z1 + t * dz - pz) ^ 2)
end
local SEGMENTOS = {}
for _, sp in MapConfig.Strongpoints do
	local setor = Expansao.SETORES[sp.name]
	if setor then
		for _, b in setor.becos do
			for i = 1, #b - 3, 2 do
				table.insert(SEGMENTOS, {
					sp.x + b[i] / M,
					sp.z + b[i + 1] / M,
					sp.x + b[i + 2] / M,
					sp.z + b[i + 3] / M,
					(Expansao.BECO_MEIA_M + 0.25) / M,
				})
			end
		end
		for _, ct in setor.cortes do
			for i = 1, #ct.pts - 1 do
				local p, q = ct.pts[i], ct.pts[i + 1]
				table.insert(SEGMENTOS, {
					sp.x + p[1] / M,
					sp.z + p[2] / M,
					sp.x + q[1] / M,
					sp.z + q[2] / M,
					(ct.largura / 2 + ct.margem + 0.05) / M,
				})
			end
		end
	end
end
local function pegaCaminhoNovo(it, k): boolean
	local ca, sa = math.cos(it.yaw), math.sin(it.yaw)
	for i = -4, 4 do
		for j = -4, 4 do
			local lx, lz = i / 4 * it.hx * k, j / 4 * it.hz * k
			local x, z = it.x + lx * ca + lz * sa, it.z - lx * sa + lz * ca
			for _, s in SEGMENTOS do
				if distSeg(x, z, s[1], s[2], s[3], s[4]) < s[5] then
					return true
				end
			end
		end
	end
	return false
end

-- as maiores primeiro: são as que mais precisam do espaço
table.sort(casas, function(a, b)
	local aa, ab = a.hx * a.hz, b.hx * b.hz
	if aa ~= ab then
		return aa > ab
	end
	return ArtPlan.chaveCasa(a.key, a.x, a.z) < ArtPlan.chaveCasa(b.key, b.x, b.z)
end)
local escolhido = {}
local function folgaEntre(a, b): number
	return if a.expansao ~= b.expansao then 3 / M else 0.4 / M
end
local function cabe(it, f): boolean
	local g = maior(it, f)
	if chaoRuim(it, f) and not chaoRuim(it, 1) then
		return false
	end
	if pegaCaminhoNovo(it, f) then
		return false
	end
	for _, o in casas do
		if o ~= it then
			local fo = escolhido[o] or 1
			local go = maior(o, fo)
			if
				ArtPlan.pegadasBatem(g, go, folgaEntre(it, o))
				and not ArtPlan.pegadasBatem(maior(it, 1), maior(o, 1), folgaEntre(it, o))
			then
				return false
			end
		end
	end
	for _, o in outros do
		local doQuintal = o.village ~= nil and not o.home
		if not doQuintal and (o.padded or o.group == "base" or o.group == "special") then
			if
				ArtPlan.pegadasBatem(g, o, folgaEntre(it, o))
				and not ArtPlan.pegadasBatem(maior(it, 1), o, folgaEntre(it, o))
			then
				return false
			end
		end
	end
	return true
end

local tabela = {}
local cont = { [1] = 0 }
for _, f in FATORES do
	cont[f] = 0
end
for _, it in casas do
	local f = 1
	for _, c in FATORES do
		if cabe(it, c) then
			f = c
			break
		end
	end
	escolhido[it] = f
	cont[f] += 1
	if f > 1 then
		tabela[ArtPlan.chaveCasa(it.key, it.x, it.z)] = f
	end
end

-- grava o módulo
local chaves = {}
for k in tabela do
	table.insert(chaves, k)
end
table.sort(chaves)
local ls = {
	"--!strict",
	'-- GERADO por tools/casas_escala.luau (D-236). Quanto cada casa cresce, por "chave|x|z".',
	"local CasasEscala = {}",
	"",
	"CasasEscala.f = {",
}
for _, k in chaves do
	table.insert(ls, string.format('\t["%s"] = %s,', k, tostring(tabela[k])))
end
table.insert(ls, "} :: { [string]: number }")
table.insert(ls, "")
table.insert(ls, "return CasasEscala")
table.insert(ls, "")
fs.writeFile("src/ServerScriptService/Modules/CasasEscala.luau", table.concat(ls, "\n"))

-- o plano novo: base nova de cada construção, para mover a arte fixa
local _, st1 = plano(tabela)
local function indexa(st)
	local out = {}
	for _, it in st do
		local k = if string.sub(it.key, 1, 6) == "parts:" then "Vila_" .. string.sub(it.key, 7) else it.key
		out[k] = out[k] or {}
		table.insert(out[k], it)
	end
	return out
end
local i0, i1 = indexa(st0), indexa(st1)
local function perto(lista, x, z)
	local best, bd = nil, math.huge
	for _, it in lista or {} do
		local d = (it.x - x) ^ 2 + (it.z - z) ^ 2
		if d < bd then
			best, bd = it, d
		end
	end
	return best, math.sqrt(bd)
end
local ajuste = {}
local nAjuste, semPar = 0, 0
for _, e in StaticArt.items do
	local a, d = perto(i0[e.key], e.x, e.z)
	if not a or d > 25 then
		semPar += 1
		print("sem par no plano:", e.key, e.x, e.z)
		continue
	end
	local b = nil
	for _, c in i1[e.key] or {} do
		if (c.origemX or c.x) == a.x and (c.origemZ or c.z) == a.z then
			b = c
			break
		end
	end
	if not b then
		-- anexo sem lugar novo: sai da arte fixa junto com o plano
		semPar += 1
		ajuste[string.format("%s|%.3f|%.3f|%.3f", e.key, e.x, e.y, e.z)] = { fora = true }
		nAjuste += 1
		continue
	end
	local f = b.scale / a.scale
	local nx = b.x - (a.x - e.x) * f
	local ny = b.base - (a.base - e.y) * f
	local nz = b.z - (a.z - e.z) * f
	if
		math.abs(f - 1) > 1e-6
		or math.abs(ny - e.y) > 1e-3
		or math.abs(nx - e.x) > 1e-3
		or math.abs(nz - e.z) > 1e-3
	then
		ajuste[string.format("%s|%.3f|%.3f|%.3f", e.key, e.x, e.y, e.z)] = {
			x = math.round(nx * 1000) / 1000,
			y = math.round(ny * 1000) / 1000,
			z = math.round(nz * 1000) / 1000,
			f = f,
		}
		nAjuste += 1
	end
end
fs.writeFile("assets/estatico/ajuste_casas.json", serde.encode("json", ajuste, true) .. "\n")

print("casas:", #casas)
for _, f in FATORES do
	print(string.format("  +%d%%: %d", math.round((f - 1) * 100), cont[f]))
end
print("  ficam iguais:", cont[1])
print("construções antes/depois:", #st0, #st1, "| anexos que saíram:", #st0 - #st1)
print("arte fixa: ajustes", nAjuste, "de", #StaticArt.items, "| sem par:", semPar)
