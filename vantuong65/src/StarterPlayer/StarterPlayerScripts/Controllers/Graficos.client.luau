--!strict
-- Opções de gráficos (D-82, pedido do dono: "opções no jogo para ajeitar os gráficos"). Tudo
-- local, no cliente de quem escolheu; salvo na conta junto com o controle (Input.settings):
-- - Sombras do sol (Lighting.GlobalShadows): a opção que mais pesa em máquina fraca;
-- - Efeitos de tela: completo (brilho, raios de sol e correção de cor), leve (sem o brilho, que é
--   o mais caro) ou desligado;
-- - Brilho: compensação de exposição, de −1 a +1 EV em volta do valor do jogo;
-- - Detalhe: alto, médio ou baixo. Vai no atributo local "GfxDetail" do jogador (1, 0,6 ou 0,3);
--   arroz, poeira, folhas e fumaça (RiceField, Ambiente) reduzem alcance e densidade por ele.
-- A qualidade gráfica do Roblox (menu Esc) continua valendo por cima.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local BASE_EXPOSURE = Lighting.ExposureCompensation
local DETAIL = { high = 1, medium = 0.6, low = 0.3 }

local function apply()
	local s = Input.settings
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
end

apply()
Input.SettingsChanged:Connect(apply)
-- o Lighting chega pela rede depois do script em alguns casos: reaplica quando os efeitos aparecem
Lighting.ChildAdded:Connect(function()
	task.defer(apply)
end)
