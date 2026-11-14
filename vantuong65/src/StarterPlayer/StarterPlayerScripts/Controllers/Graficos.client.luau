--!strict
-- Opções de gráficos (D-82, pedido do dono: "opções no jogo para ajeitar os gráficos"). Tudo
-- local, no cliente de quem escolheu; salvo na conta junto com o controle (Input.settings):
-- - Sombras do sol (Lighting.GlobalShadows): a opção que mais pesa em máquina fraca;
-- - Efeitos de tela: completo (brilho, raios de sol e correção de cor), leve (sem o brilho, que é
--   o mais caro) ou desligado;
-- - Brilho: compensação de exposição, de −1 a +1 EV em volta do valor do jogo;
-- - Detalhe: alto, médio ou baixo. Vai no atributo local "GfxDetail" do jogador (1, 0,6 ou 0,3);
--   arroz, poeira, folhas e fumaça (RiceField, Ambiente) e as faixas e a poeira dos veículos
--   (VehicleFx) reduzem alcance e densidade por ele.
-- - Sombra das árvores (2026-11-12, opção nova gfxPlantShadows, true/false; sem a chave, desligada):
--   as copas grandes da mata (o AssetLoader marca com o atributo PlantShadow) fazem sombra no chão.
--   Cada copa com sombra é desenhada de novo em cada faixa do mapa de sombra do sol; com a mata
--   inteira, é o maior custo de GPU depois da própria mata. Desligada, só a sombra das casas e do
--   relevo fica.
-- Parte 13 (celular e tablet, T3): as escolhas passam pelo Aparelho.profile (puro, testado no Lune):
-- - perfil de celular (toque sem teclado nem mouse, fora da TV): sem sombra das copas, sem brilho e
--   sem raios de sol, detalhe no máximo médio. A sombra do sol fica na escolha do jogador;
-- - economia de bateria (batterySaver, escolha do jogador, nunca padrão; vale em qualquer aparelho):
--   sem sombra nenhuma, sem brilho nem raios, detalhe baixo e o disparo deixa de vibrar (Haptics);
-- - NUNCA muda por aparelho: a mata, o capim e o arroz que escondem (o dossel do arrozal fica no
--   detalhe baixo), a Atmosphere (névoa e alcance de visão), a grama do terreno, os soldados, a
--   fumaça de granada e de explosão, o clarão do tiro e o traçante, e a correção de cor (contraste)
--   na escolha do jogador, igual à do PC.
-- Limites do Roblox (o que script não faz): travar o fps (no celular o Roblox fica em 60; a opção
-- "Taxa de quadros máxima" do menu do Roblox é do PC e não tem 30), mudar a resolução de render ou a
-- qualidade gráfica do menu Esc (que continua valendo por cima e é o maior ganho de bateria), e o
-- raio de streaming (propriedade do Workspace, a mesma para todos os aparelhos).
-- Studio: workspace:SetAttribute("VT65DevTela", "perfilmovel") força o perfil de celular neste
-- cliente (de novo: volta ao normal) e mostra no Output o que ficou valendo.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Aparelho = require(script.Parent.Aparelho)
local Input = require(script.Parent.Input)

local player = Players.LocalPlayer
local BASE_EXPOSURE = Lighting.ExposureCompensation

local state = {
	plantShadows = false,
	devMobile = false, -- Studio: perfil de celular forçado
}

local function isMobile(): boolean
	if state.devMobile then
		return true
	end
	local tenFoot = false
	pcall(function()
		tenFoot = GuiService:IsTenFootInterface()
	end)
	return Aparelho.isMobile({
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		mouse = UserInputService.MouseEnabled,
		tenFoot = tenFoot,
	})
end

local function setPlantShadow(m: Instance)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = state.plantShadows
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

local function profile(): Aparelho.Profile
	local s = Input.settings :: any
	return Aparelho.profile({
		gfxShadows = s.gfxShadows == true,
		gfxPlantShadows = s.gfxPlantShadows == true,
		gfxPost = if type(s.gfxPost) == "string" then s.gfxPost else "light",
		gfxDetail = if type(s.gfxDetail) == "string" then s.gfxDetail else "high",
		batterySaver = s.batterySaver == true,
	}, isMobile())
end

local function apply()
	local s = Input.settings :: any
	local p = profile()
	Lighting.GlobalShadows = p.shadows
	Lighting.ExposureCompensation = BASE_EXPOSURE + s.gfxBrightness * 5
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local cc = Lighting:FindFirstChild("ColorCorrection")
	if bloom then
		bloom.Enabled = p.bloom
	end
	if rays then
		rays.Enabled = p.sunRays
	end
	if cc and cc:IsA("ColorCorrectionEffect") then
		cc.Enabled = p.colorCorrection
	end
	player:SetAttribute("GfxDetail", p.detail)
	if p.plantShadows ~= state.plantShadows then
		state.plantShadows = p.plantShadows
		applyPlants()
	end
end

apply()
Input.SettingsChanged:Connect(apply)
-- o Lighting chega pela rede depois do script em alguns casos: reaplica quando os efeitos aparecem
Lighting.ChildAdded:Connect(function()
	task.defer(apply)
end)
-- teclado ou mouse ligado/desligado no tablet: o perfil acompanha
UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(apply)
UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(apply)

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
				d.CastShadow = state.plantShadows
			end
		end
	end)
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "perfilmovel" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil) -- local: no cliente o mesmo valor repete
		end)
		state.devMobile = not state.devMobile
		apply()
		local p = profile()
		print(
			string.format(
				"[VT65 PERFIL] celular %s | sombra do sol %s, das copas %s | brilho %s, raios %s, cor %s | detalhe %.1f | vibra no disparo %s",
				tostring(isMobile()),
				tostring(p.shadows),
				tostring(p.plantShadows),
				tostring(p.bloom),
				tostring(p.sunRays),
				tostring(p.colorCorrection),
				p.detail,
				tostring(p.hapticFire)
			)
		)
	end)
end
