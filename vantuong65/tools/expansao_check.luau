--!nocheck
-- D-232: confere a expansão da Vila e do Arrozal contra o mapa de antes, sem abrir o Studio.
--   lune run tools/expansao_check.luau
-- Peça antiga não pode mudar (chave, posição, giro e base). Peça nova não pode cair em área de captura,
-- círculo de nascer, estrada, lâmina, dique, riacho, patamar antigo nem em cima de outra peça nova.
local process = require("@lune/process")
local R = require :: any

local WorldData = R("../src/ServerStorage/VT65Build/WorldData")
local Grid = R("../src/ServerStorage/VT65Build/Data/Grid")
local Features = R("../src/ServerStorage/VT65Build/Data/Features")
local Village = R("../src/ServerStorage/VT65Build/Data/Village")
local Roads = R("../src/ServerStorage/VT65Build/Data/Roads")
local Bases = R("../src/ServerStorage/VT65Build/Data/Bases")
local MapConfig = R("../src/ReplicatedStorage/Shared/MapConfig")
local Site = R("../src/ServerStorage/VT65Build/Site")
local ArtPlan = R("../src/ServerScriptService/Modules/ArtPlan")
local ArtBudget = R("../src/ServerScriptService/Modules/ArtBudget")
local Expansao = R("../src/ServerScriptService/Modules/Expansao")
local AssetIds = R("../src/ReplicatedStorage/Shared/AssetIds")
local M = 0.28
local CAPTURA_M = 35

-- pegada planejada (X, Y, Z em metros) de quem ainda não está no ArtBudget
local PLANO = {
	exp_palafita_a = { 7.8, 7, 10.3 },
	exp_palafita_b = { 7, 6, 8.5 },
	exp_casas_ligadas = { 12, 5, 7 },
	exp_casa_vala = { 8, 5, 7 },
	exp_carroca = { 7, 4, 5 },
	exp_abrigo = { 8, 3, 6 },
	exp_trincheira = { 2.4, 2, 6 },
	exp_prancha = { 1.2, 0.4, 3.4 },
	exp_celeiro = { 16, 8, 10 },
	exp_galpao = { 10, 4, 6 },
	exp_deposito = { 5, 5, 5 },
	exp_casa_verde = { 9, 5, 8 },
	exp_ruina = { 9, 4, 7 },
	exp_comporta = { 11, 5, 7 },
	exp_telheiro = { 7, 3, 5 },
	exp_patio = { 8, 1, 6 },
	exp_passarela = { 9, 1.5, 1.5 },
	exp_muro = { 4, 1, 0.45 },
	exp_sobrado_a = { 14.5, 8.6, 10.1 },
	exp_sobrado_b = { 15.3, 8.9, 10.5 },
	exp_sobrado_c = { 13.9, 8.8, 10.9 },
	exp_sobrado_d = { 15.2, 9, 10.7 },
}
for k, d in PLANO do
	if not ArtBudget.DIMS[k] then
		ArtBudget.DIMS[k] = { d[1] / M, d[2] / M, d[3] / M }
	end
end
for _, k in { "exp_figueira", "exp_arvore_a", "exp_arvore_b", "exp_rocha", "exp_samambaia" } do
	ArtBudget.BASE_R[k] = ArtBudget.BASE_R[k] or 2
end

local chunks = {}
for _, name in Grid.heightChunks do
	table.insert(chunks, R("../src/ServerStorage/VT65Build/Data/" .. name))
end
local world = WorldData.load(Grid, chunks)
local dados = { features = Features, village = Village, roads = Roads, bases = Bases, mapConfig = MapConfig }
local function has(key: string): boolean
	if string.sub(key, 1, 4) == "exp_" then
		return true
	end
	local id = AssetIds.Models[key]
	return type(id) == "number" and id ~= 0
end
local function plano(ligada: boolean)
	Expansao.LIGADA = ligada
	local ctx = ArtPlan.load(world, dados)
	local st = ArtPlan.structures(ctx, has)
	local pl = ArtPlan.plants(ctx, st, {}, has)
	return ctx, st, pl
end

local _, st0, pl0 = plano(false)
local ctx, st1, pl1 = plano(true)
local erros = 0
local function erro(...)
	erros += 1
	print("ERRO", ...)
end

-- 1. o que já existia não mudou
local novos = {}
local velhos = {}
for _, it in st1 do
	table.insert(if it.expansao then novos else velhos, it)
end
if #velhos ~= #st0 then
	erro("construções antigas", #st0, "->", #velhos)
end
for i, a in st0 do
	local b = velhos[i]
	if not b or a.key ~= b.key or a.x ~= b.x or a.z ~= b.z or a.yaw ~= b.yaw or math.abs(a.base - b.base) > 1e-6 then
		erro("mudou:", a.key, a.x, a.z)
	end
end
local function chave(p)
	return string.format("%s|%.3f|%.3f", p.key, p.x, p.z)
end
local de1 = {}
for _, p in pl1 do
	de1[chave(p)] = p
end
local tiradas, moveu = 0, 0
for _, p in pl0 do
	local q = de1[chave(p)]
	if not q then
		tiradas += 1
	elseif math.abs(q.base - p.base) > 1e-3 then
		moveu += 1
	end
end
print(string.format("construções antigas iguais: %d | novas: %d", #st0, #novos))
print(
	string.format(
		"plantas: %d antes, %d depois | tiradas pelo novo chão: %d | só reassentadas: %d",
		#pl0,
		#pl1,
		tiradas,
		moveu
	)
)

-- 2. peça nova no lugar certo
local function cantos(it, folga)
	local out = {}
	local ca, sa = math.cos(it.yaw), math.sin(it.yaw)
	for i = -2, 2 do
		for j = -2, 2 do
			local lx, lz = i / 2 * (it.hx + folga), j / 2 * (it.hz + folga)
			table.insert(out, { it.x + lx * ca + lz * sa, it.z - lx * sa + lz * ca })
		end
	end
	return out
end
local function dentro(a, px, pz, folga)
	local dx, dz = px - a.x, pz - a.z
	local ca, sa = math.cos(a.yaw), math.sin(a.yaw)
	local lx, lz = dx * ca - dz * sa, dx * sa + dz * ca
	return math.abs(lx) < a.hx + folga and math.abs(lz) < a.hz + folga
end
local function pontoForte(nome)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == nome then
			return sp
		end
	end
	return nil
end
local function distSeg(px, pz, x1, z1, x2, z2)
	local dx, dz = x2 - x1, z2 - z1
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - x1) * dx + (pz - z1) * dz) / l2, 0, 1) else 0
	return math.sqrt((x1 + t * dx - px) ^ 2 + (z1 + t * dz - pz) ^ 2)
end
-- o chão como era, para julgar cada peça contra o mapa antigo
local ctx0 = plano(false)
Expansao.LIGADA = true
for _, it in novos do
	local sp = pontoForte(it.objective)
	local cruza = (it.key == "exp_prancha" or it.key == "exp_passarela" or it.key == "exp_comporta")
	local probs = {}
	local lo, hi = math.huge, -math.huge
	for _, c in cantos(it, 0) do
		local dcap = math.sqrt((c[1] - sp.x) ^ 2 + (c[2] - sp.z) ^ 2) * M
		if dcap < CAPTURA_M + 2 then
			probs["captura"] = true
		end
		local p = ArtPlan.groundProblem(ctx0, c[1], c[2], 1 / M)
		if p and not (cruza and p == "riacho") then
			probs[p] = true
		end
		local h = Site.column(ctx0.site, c[1], c[2])
		lo, hi = math.min(lo, h), math.max(hi, h)
	end
	for _, o in st0 do
		if o.padded or o.group == "house" then
			local d = math.sqrt((o.x - it.x) ^ 2 + (o.z - it.z) ^ 2)
			if d < (math.sqrt(o.hx ^ 2 + o.hz ^ 2) + math.sqrt(it.hx ^ 2 + it.hz ^ 2) + 6 / M) then
				for _, c in cantos(it, 5 / M) do
					if dentro(o, c[1], c[2], 0) then
						probs["perto de " .. o.key] = true
						break
					end
				end
			end
		end
	end
	for _, o in novos do
		if o ~= it and not (string.find(o.id, "trincheira") and string.find(it.id, "trincheira")) then
			for _, c in cantos(it, 0) do
				if dentro(o, c[1], c[2], 0) then
					probs["sobre " .. o.id] = true
					break
				end
			end
		end
	end
	local B = MapConfig.Bounds
	if it.x < B.minX + 30 or it.x > B.maxX - 30 or it.z < B.minZ + 30 or it.z > B.maxZ - 30 then
		probs["borda"] = true
	end
	-- nada novo em cima dos caminhos e das valas novos (a travessia e a comporta existem para isso)
	local setor = Expansao.SETORES[it.objective]
	if not cruza then
		for _, b in setor.becos do
			for i = 1, #b - 3, 2 do
				for _, c in cantos(it, 0) do
					local d = distSeg(
						c[1],
						c[2],
						sp.x + b[i] / M,
						sp.z + b[i + 1] / M,
						sp.x + b[i + 2] / M,
						sp.z + b[i + 3] / M
					)
					if d < (Expansao.BECO_MEIA_M + 0.2) / M then
						probs["sobre o caminho novo"] = true
					end
				end
			end
		end
		for _, ct in setor.cortes do
			for i = 1, #ct.pts - 1 do
				local p, q = ct.pts[i], ct.pts[i + 1]
				for _, c in cantos(it, 0) do
					local d = distSeg(c[1], c[2], sp.x + p[1] / M, sp.z + p[2] / M, sp.x + q[1] / M, sp.z + q[2] / M)
					if d < (ct.largura / 2 + ct.margem) / M then
						probs["sobre a água nova"] = true
					end
				end
			end
		end
	end
	local lista = {}
	for k in probs do
		table.insert(lista, k)
	end
	table.sort(lista)
	local txt = table.concat(lista, ", ")
	print(
		string.format(
			"%-9s %-13s %-20s (%6.1f, %6.1f) desnível %.1f m %s",
			it.objective,
			it.id,
			it.key,
			(it.x - sp.x) * M,
			(it.z - sp.z) * M,
			(hi - lo) * M,
			if txt == "" then "ok" else "<< " .. txt
		)
	)
	if txt ~= "" then
		erros += 1
	end
end
-- 3. os caminhos novos: fora de lâmina, dique, riacho e patamar antigo; e só cruzam água numa travessia
for _, sp in MapConfig.Strongpoints do
	local setor = Expansao.SETORES[sp.name]
	if not setor then
		continue
	end
	for nb, b in setor.becos do
		for i = 1, #b - 3, 2 do
			local x1, z1, x2, z2 = sp.x + b[i] / M, sp.z + b[i + 1] / M, sp.x + b[i + 2] / M, sp.z + b[i + 3] / M
			local passos = math.max(1, math.ceil(math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2) * M))
			for k = 0, passos do
				local x, z = x1 + (x2 - x1) * k / passos, z1 + (z2 - z1) * k / passos
				local g = ArtPlan.groundProblem(ctx0, x, z, 0.6 / M)
				if g == "lamina" or g == "dique" or g == "riacho" or g == "patamar" then
					erro(
						sp.name,
						"caminho",
						nb,
						"sobre",
						g,
						string.format("(%.1f, %.1f)", (x - sp.x) * M, (z - sp.z) * M)
					)
					break
				end
				for _, ct in setor.cortes do
					for j = 1, #ct.pts - 1 do
						local p, q = ct.pts[j], ct.pts[j + 1]
						local d = distSeg(x, z, sp.x + p[1] / M, sp.z + p[2] / M, sp.x + q[1] / M, sp.z + q[2] / M)
						if d < ct.largura / 2 / M then
							local tem = false
							for _, o in novos do
								if
									(o.key == "exp_prancha" or o.key == "exp_passarela") and dentro(o, x, z, 0.8 / M)
								then
									tem = true
								end
							end
							if not tem then
								erro(
									sp.name,
									"caminho",
									nb,
									"cruza",
									ct.id,
									"sem travessia",
									string.format("(%.1f, %.1f)", (x - sp.x) * M, (z - sp.z) * M)
								)
							end
						end
					end
				end
			end
		end
	end
end
print("problemas:", erros)
process.exit(if erros == 0 then 0 else 1)
