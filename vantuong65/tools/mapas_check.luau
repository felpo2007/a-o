--!nocheck
-- D-243: confere os dados dos mapas retangulares sem o Studio: carrega o plano da arte, mede o terreno e as
-- construções (centros, limites, vias, água). Uso: lune run tools/mapas_check.luau
local WorldData = require("../src/ServerStorage/VT65Build/WorldData")
local ArtPlan = require("../src/ServerScriptService/Modules/ArtPlan")
local ArtBudget = require("../src/ServerScriptService/Modules/ArtBudget")
local MapaAtivo = require("../src/ReplicatedStorage/Shared/MapaAtivo")
local MapasRet = require("../src/ReplicatedStorage/Shared/MapasRet")
local Site = require("../src/ServerStorage/VT65Build/Site")

local M = 0.28
local problemas = 0
local function nota(s)
	problemas += 1
	print("  PROBLEMA " .. s)
end

local DADOS = {
	frente = {
		grid = require("../src/ServerStorage/VT65Build/Data_frente/Grid"),
		chunks = {
			require("../src/ServerStorage/VT65Build/Data_frente/Heights_00"),
			require("../src/ServerStorage/VT65Build/Data_frente/Heights_01"),
			require("../src/ServerStorage/VT65Build/Data_frente/Heights_02"),
		},
		features = require("../src/ServerStorage/VT65Build/Data_frente/Features"),
		roads = require("../src/ServerStorage/VT65Build/Data_frente/Roads"),
		layout = require("../src/ServerStorage/VT65Build/Data_frente/Layout"),
	},
	comboio = {
		grid = require("../src/ServerStorage/VT65Build/Data_comboio/Grid"),
		chunks = {
			require("../src/ServerStorage/VT65Build/Data_comboio/Heights_00"),
			require("../src/ServerStorage/VT65Build/Data_comboio/Heights_01"),
			require("../src/ServerStorage/VT65Build/Data_comboio/Heights_02"),
		},
		features = require("../src/ServerStorage/VT65Build/Data_comboio/Features"),
		roads = require("../src/ServerStorage/VT65Build/Data_comboio/Roads"),
		layout = require("../src/ServerStorage/VT65Build/Data_comboio/Layout"),
	},
}

local function confere(id, projeto)
	local d = DADOS[id]
	local mc = MapaAtivo.configPara(id)
	print(string.format("== %s (%s)", id, projeto.nome))
	local w = WorldData.load(d.grid, d.chunks)
	local ctx = ArtPlan.load(w, { features = d.features, roads = d.roads, layout = d.layout, mapConfig = mc })
	local estruturas = ArtPlan.structures(ctx, function(k)
		return ArtBudget.DIMS[k] ~= nil
	end)
	local B = mc.Bounds
	local larg, prof = (B.maxX - B.minX) * M, (B.maxZ - B.minZ) * M
	if math.abs(larg - projeto.compM) > 1e-6 or math.abs(prof - projeto.profM) > 1e-6 then
		nota(string.format("limites %.2f x %.2f m", larg, prof))
	end
	-- centros dos setores: ida e volta planta -> mundo
	for i, st in projeto.setores do
		local sp = mc.Strongpoints[i]
		local px, py = MapaAtivo.planta(projeto, sp.x, sp.z)
		if math.abs(px - st.x) > 1e-6 or math.abs(py - st.y) > 1e-6 then
			nota("centro do setor " .. st.id)
		end
		local h, wl = Site.column(ctx.site, sp.x, sp.z)
		if wl > h then
			nota("setor " .. st.id .. " dentro da água")
		end
	end
	local foraDaArea, naAgua = 0, 0
	for _, it in estruturas do
		if it.x < B.minX or it.x > B.maxX or it.z < B.minZ or it.z > B.maxZ then
			foraDaArea += 1
		end
		if w:classAt(it.x, it.z) == 5 then
			naAgua += 1
		end
	end
	if foraDaArea > 0 then
		nota(foraDaArea .. " construções fora da área")
	end
	if naAgua > 0 then
		nota(naAgua .. " construções no rio")
	end
	-- conjuntos de nascer: dentro da área, em chão seco e com duas saídas em direções diferentes
	local cs = d.layout.conjuntos
	if #cs < 16 then
		nota("só " .. #cs .. " conjuntos de nascer")
	end
	for _, c in cs do
		if c.x < B.minX or c.x > B.maxX or c.z < B.minZ or c.z > B.maxZ then
			nota("conjunto " .. c.id .. " fora da área")
		end
		local h, wl = Site.column(ctx.site, c.x, c.z)
		if wl > h then
			nota("conjunto " .. c.id .. " na água")
		end
		local ax, az = c.sx1 - c.x, c.sz1 - c.z
		local bx, bz = c.sx2 - c.x, c.sz2 - c.z
		local cosA = (ax * bx + az * bz) / (math.sqrt(ax * ax + az * az) * math.sqrt(bx * bx + bz * bz))
		if math.deg(math.acos(math.clamp(cosA, -1, 1))) < 74.9 then
			nota("conjunto " .. c.id .. ": saídas quase iguais")
		end
	end
	print(string.format("  %d conjuntos de nascer, cada um com 2 saídas", #cs))
	local nos = 0
	local minH, maxH = math.huge, -math.huge
	for x = B.minX, B.maxX, 16 do
		for z = B.minZ, B.maxZ, 16 do
			local h = Site.column(ctx.site, x, z)
			minH, maxH = math.min(minH, h), math.max(maxH, h)
			nos += 1
		end
	end
	print(
		string.format(
			"  área %.0f x %.0f m; %d construções; %d tabuleiros; %d pontes; chão de %.1f a %.1f m (%d colunas)",
			larg,
			prof,
			#estruturas,
			#ctx.paddies.list,
			#d.layout.pontes,
			minH * M,
			maxH * M,
			nos
		)
	)
end

confere("frente", MapasRet.FRENTE)
confere("comboio", MapasRet.COMBOIO)
print("problemas: " .. problemas)
if problemas > 0 then
	error("mapas_check: falhou")
end
