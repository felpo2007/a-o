--!strict
-- Opções de gráficos (D-82, pedido do dono: "opções no jogo para ajeitar os gráficos"). Tudo
-- local, no cliente de quem escolheu; salvo na conta junto com o controle (Input.settings):
-- - Sombras do sol (Lighting.GlobalShadows): a opção que mais pesa em máquina fraca;
-- - Efeitos de tela: completo (brilho, raios de sol e correção de cor), leve (sem o brilho, que é
--   o mais caro) ou desligado;
-- - Brilho: compensação de exposição, de −1 a +1 EV em volta do valor do jogo;
-- - Detalhe: alto, médio ou baixo. Vai no atributo local "GfxDetail" do jogador (1, 0,6 ou 0,3);
--   arroz, poeira, folhas e fumaça (RiceField, Ambiente) reduzem alcance e densidade por ele.
-- - Sombra das árvores (2026-11-12, opção nova gfxPlantShadows, true/false; sem a chave, desligada):
--   as copas grandes da mata (o AssetLoader marca com o atributo PlantShadow) fazem sombra no chão.
--   Cada copa com sombra é desenhada de novo em cada faixa do mapa de sombra do sol; com a mata
--   inteira, é o maior custo de GPU depois da própria mata. Desligada, só a sombra das casas e do
--   relevo fica.
-- A qualidade gráfica do Roblox (menu Esc) continua valendo por cima.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local BASE_EXPOSURE = Lighting.ExposureCompensation
local DETAIL = { high = 1, medium = 0.6, low = 0.3 }

local plantShadows = false
local function setPlantShadow(m: Instance)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = plantShadows
		end
	end
end

local art: Instance? = nil
local function applyPlants()
	if not art then
		return
	end
	for _, m in (art :: Instance):GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("PlantShadow") == true then
			setPlantShadow(m)
		end
	end
end

local function apply()
	local s = Input.settings :: any
	Lighting.GlobalShadows = s.gfxShadows
	Lighting.ExposureCompensation = BASE_EXPOSURE + s.gfxBrightness * 5
	local post = s.gfxPost
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local cc = Lighting:FindFirstChild("ColorCorrection")
	if bloom then
		bloom.Enabled = post == "full"
	end
	if rays then
		rays.Enabled = post ~= "off"
	end
	if cc and cc:IsA("ColorCorrectionEffect") then
		cc.Enabled = post ~= "off"
	end
	player:SetAttribute("GfxDetail", DETAIL[s.gfxDetail] or 1)
	local want = s.gfxPlantShadows == true
	if want ~= plantShadows then
		plantShadows = want
		applyPlants()
	end
end

apply()
Input.SettingsChanged:Connect(apply)
-- o Lighting chega pela rede depois do script em alguns casos: reaplica quando os efeitos aparecem
Lighting.ChildAdded:Connect(function()
	task.defer(apply)
end)

-- a mata chega por streaming: cada copa marcada que entra recebe a opção da vez
task.spawn(function()
	local map = workspace:WaitForChild("Map", 120)
	local a = map and map:WaitForChild("Art", 300)
	if not a then
		return
	end
	art = a
	applyPlants()
	a.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("BasePart") then
			local m = d:FindFirstAncestorWhichIsA("Model")
			if m and m:GetAttribute("PlantShadow") == true then
				d.CastShadow = plantShadows
			end
		end
	end)
end)
