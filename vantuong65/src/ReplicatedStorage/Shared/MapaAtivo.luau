--!strict
-- D-243: qual mapa este servidor roda. Um place só, com o mapa escolhido quando o servidor sobe
-- (Modules/MapaBoot grava o atributo VT65Mapa no workspace antes de qualquer outro módulo ler o MapConfig).
-- Sem o atributo, é o mapa de sempre. Fora do Roblox (Lune), também.
local MapasRet = require(script and (script :: any).Parent.MapasRet or "./MapasRet") :: any

local MapaAtivo = {}

MapaAtivo.PADRAO = "vantuong"
MapaAtivo.ATRIBUTO = "VT65Mapa"

local PROJETOS: { [string]: any } = {
	frente = MapasRet.FRENTE,
	comboio = MapasRet.COMBOIO,
}

local memo: string? = nil

function MapaAtivo.conhecido(id: any): boolean
	return id == MapaAtivo.PADRAO or (type(id) == "string" and PROJETOS[id] ~= nil)
end

function MapaAtivo.id(): string
	if memo then
		return memo
	end
	if (game :: any) == nil then
		return MapaAtivo.PADRAO
	end
	local v = workspace:GetAttribute(MapaAtivo.ATRIBUTO)
	if v == nil and game:GetService("RunService"):IsClient() then
		-- o cliente pode rodar antes de o atributo chegar: o servidor sempre o grava ao subir
		local t0 = os.clock()
		while v == nil and os.clock() - t0 < 20 do
			task.wait()
			v = workspace:GetAttribute(MapaAtivo.ATRIBUTO)
		end
	end
	if v == nil then
		return MapaAtivo.PADRAO
	end
	local escolhido: string = if MapaAtivo.conhecido(v) then v :: any else MapaAtivo.PADRAO
	memo = escolhido
	return escolhido
end

function MapaAtivo.retangular(): boolean
	return PROJETOS[MapaAtivo.id()] ~= nil
end

function MapaAtivo.projeto(): any
	return PROJETOS[MapaAtivo.id()]
end

-- Planta (m, X leste, Y norte) para o mundo (studs): o centro do mapa fica na origem.
function MapaAtivo.mundo(p: any, x: number, y: number): (number, number)
	local s = MapasRet.M_POR_STUD
	return (x - p.compM / 2) / s, -(y - p.profM / 2) / s
end

-- Mundo para a planta.
function MapaAtivo.planta(p: any, wx: number, wz: number): (number, number)
	local s = MapasRet.M_POR_STUD
	return wx * s + p.compM / 2, p.profM / 2 - wz * s
end

-- Os campos do MapConfig para um mapa retangular. Faixas de setor de oeste para leste, cortadas no meio do
-- caminho entre os centros.
function MapaAtivo.configPara(id: string): any
	local p = PROJETOS[id]
	assert(p, "mapa desconhecido: " .. tostring(id))
	local s = MapasRet.M_POR_STUD
	local mx, mz = p.compM / 2 / s, p.profM / 2 / s
	local cortes: { number } = { -mx }
	for i = 1, #p.setores - 1 do
		table.insert(cortes, ((p.setores[i].x + p.setores[i + 1].x) / 2 - p.compM / 2) / s)
	end
	table.insert(cortes, mx)
	local setores, pontos = {}, {}
	for i, st in p.setores do
		local x0, x1 = cortes[i], cortes[i + 1]
		table.insert(setores, {
			id = i,
			name = st.id .. " " .. st.nome,
			polygon = { x0, mz, x0, -mz, x1, -mz, x1, mz },
		})
		local wx, wz = MapaAtivo.mundo(p, st.x, st.y)
		table.insert(pontos, { sector = i, name = st.nome, x = wx, z = wz, real = false, note = "mapa retangular" })
	end
	local ox, oz = MapaAtivo.mundo(p, p.baseOeste.x, p.baseOeste.y)
	local lx, lz = MapaAtivo.mundo(p, p.baseLeste.x, p.baseLeste.y)
	return {
		Bounds = { minX = -mx, maxX = mx, minZ = -mz, maxZ = mz },
		-- a folha da carta é quadrada e cobre a largura; o mapa é a faixa do meio dela
		CartaBounds = { minX = -mx, maxX = mx, minZ = -mx, maxZ = mx },
		CartaFaixa = { u0 = 0, u1 = 1, v0 = 0.5 - mz / (2 * mx), v1 = 0.5 + mz / (2 * mx) },
		CaptureRadiusStuds = (p.regras.larguraCapturaM or 28) / 2 / s,
		Sectors = setores,
		Strongpoints = pontos,
		-- o Oeste é o VC e o Leste os EUA, como no mapa de sempre
		HQ = {
			US = { x = lx, z = lz, note = "base leste" },
			VC = { x = ox, z = oz, note = "base oeste" },
		},
		Locations = {},
		InitialOwner = { "VC", "VC", "Neutral", "US", "US" },
	}
end

-- Sobrepõe os campos do mapa deste servidor no MapConfig gerado (que é o do mapa de sempre).
function MapaAtivo.aplicar(MapConfig: any): any
	if not MapaAtivo.retangular() then
		return MapConfig
	end
	for k, v in MapaAtivo.configPara(MapaAtivo.id()) do
		MapConfig[k] = v
	end
	return MapConfig
end

return MapaAtivo
