--!strict
-- D-243: escolhe o mapa quando o servidor sobe, antes de qualquer módulo ler o MapConfig. Um place só: o mapa de
-- sempre continua intacto no arquivo; nos retangulares, a pasta de dados é trocada e o greybox é refeito.
-- No Studio: workspace:SetAttribute("VT65DevMapa", "frente" | "comboio") no modo de edição, antes do Play.
-- Em servidor reservado, vale o TeleportData do primeiro jogador, enquanto os mapas estiverem liberados.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MapaAtivo = require(ReplicatedStorage.Shared.MapaAtivo)
local MapasRet = require(ReplicatedStorage.Shared.MapasRet) :: any

local MapaBoot = {}

local function escolhe(): string
	if RunService:IsStudio() then
		local v = workspace:GetAttribute("VT65DevMapa")
		return if MapaAtivo.conhecido(v) then v :: string else MapaAtivo.PADRAO
	end
	if MapasRet.LIBERADOS ~= true or game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0 then
		return MapaAtivo.PADRAO
	end
	local p = Players:GetPlayers()[1]
	local t0 = os.clock()
	while not p and os.clock() - t0 < 20 do
		task.wait(0.1)
		p = Players:GetPlayers()[1]
	end
	if p then
		local dados = p:GetJoinData().TeleportData
		local v = if type(dados) == "table" then (dados :: any).mapa else nil
		if MapaAtivo.conhecido(v) then
			return v
		end
	end
	return MapaAtivo.PADRAO
end

local function monta()
	local id = escolhe()
	workspace:SetAttribute(MapaAtivo.ATRIBUTO, id)
	if id == MapaAtivo.PADRAO then
		return
	end
	local t0 = os.clock()
	local B = ServerStorage:WaitForChild("VT65Build")
	local velho = B:WaitForChild("Data")
	local novo = B:WaitForChild("Data_" .. id)
	velho.Name = "Data_" .. MapaAtivo.PADRAO
	novo.Name = "Data"
	local Build = require(B:WaitForChild("Build")) :: any
	Build.features() -- apaga o Map do arquivo (greybox e arte fixa) e monta o deste mapa
	local map = workspace:FindFirstChild("Map")
	if map then
		require(script.Parent.MapaPontes).montar(map, require(novo:WaitForChild("Layout")) :: any)
	end
	print(string.format("[VT65] mapa %s montado em %.1f s", id, os.clock() - t0))
end

-- Todo script de servidor chama isto na primeira linha: o primeiro monta, os outros esperam ele acabar.
local estado = "novo"
function MapaBoot.iniciar()
	if estado == "novo" then
		estado = "montando"
		local ok, erro = pcall(function(): any
			monta()
			return nil
		end)
		estado = "pronto"
		if not ok then
			error(erro)
		end
		return
	end
	while estado ~= "pronto" do
		task.wait()
	end
end

return MapaBoot
