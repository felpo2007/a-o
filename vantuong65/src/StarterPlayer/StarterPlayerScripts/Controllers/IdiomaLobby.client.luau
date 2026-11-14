--!strict
-- Idioma no lobby (pedido do dono, 2026-11-11: "faça o jogo completamente na língua que foi
-- selecionada"). Um chip "IDIOMA · LANGUAGE" no cabeçalho da mesa (ao lado da plaqueta do posto; na
-- TV, no canto de baixo à direita) abre o cartão de idiomas (ReplicatedFirst/Idioma). No controle: Y
-- (livre no contexto do menu) ou o cursor virtual do lobby.
-- Primeira vez: conta nova (XP 0) com o idioma em "automático" vê o cartão uma vez, logo que a mesa
-- aparece. O DataStore não guarda "já escolheu" (FieldService/ProfileSchema são de outra pessoa):
-- quem escolhe um idioma deixa de ser "automático" e não vê de novo.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local UserInputService = game:GetService("UserInputService")

local Idioma = require(ReplicatedFirst:WaitForChild("Idioma"))
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)
local VirtualCursor = require(script.Parent.VirtualCursor)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local root = DeployScreen.root

local opened = false
local function open(first: boolean?)
	if Idioma.aberto() or not root.Visible then
		return
	end
	opened = true
	Input.openMenu() -- B, LB/RB e o resto do lobby esperam o cartão fechar
	Idioma.abrir({
		z = 22, -- acima do lobby (20), abaixo do cursor virtual (60)
		cursor = VirtualCursor.isActive(),
		bind = UiKit.bind,
		primeiraVez = first,
		aoFechar = function()
			Input.closeMenu()
		end,
	})
end

local chip = Idioma.chip(root, {
	bind = UiKit.bind,
	onClick = function()
		open(false)
	end,
	padKey = Enum.KeyCode.ButtonY,
})
if TV then
	chip.button.AnchorPoint = Vector2.new(1, 1)
	chip.button.Position = UDim2.fromOffset(1240, 664)
else
	chip.button.Position = UDim2.fromOffset(612, 14)
end
chip.button.ZIndex = 4
Idioma.soAteEscolher(chip.button) -- v43: escolhido o idioma, só nas Configurações do menu do jogo

-- Y no controle, com a mesa por cima de tudo (nenhum menu aberto sobre o lobby)
UserInputService.InputBegan:Connect(function(io: InputObject)
	if
		io.KeyCode == Enum.KeyCode.ButtonY
		and chip.button.Visible
		and root.Visible
		and Input.state.menus <= 1
		and not Idioma.aberto()
	then
		open(false)
	end
end)
Input.SettingsChanged:Connect(function()
	chip.atualizar()
end)

-- gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "idioma") abre o cartão de
-- idiomas onde estiver (no lobby, como a primeira vez)
if game:GetService("RunService"):IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "idioma" then
			return
		end
		if root.Visible then
			open(true)
		elseif not Idioma.aberto() then
			Idioma.abrir({ z = 110, primeiraVez = true })
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
	end)
end

-- D-107: entrou em campo com o cartão aberto (JOGAR AGORA direto da mesa ou da tela de entrada):
-- fecha, fica no automático (no teste da v39 o cartão ficava por cima do jogo)
player.CharacterAdded:Connect(function()
	if Idioma.aberto() then
		Idioma.fechar()
	end
end)

-- primeira vez: depois que a tela de entrada sai e a configuração da conta chega
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	while true do
		task.wait(1)
		if opened then
			return
		end
		local loading = pg:FindFirstChild("VT65Loading")
		local loadingUp = loading ~= nil
			and loading:IsA("ScreenGui")
			and loading.Enabled
			and loading:GetAttribute("Saindo") ~= true
		local xp = player:GetAttribute("XP")
		if Input.loaded and not loadingUp and root.Visible and type(xp) == "number" then
			if xp == 0 and Input.settings.lang == "auto" and Input.state.menus <= 1 then
				task.wait(1.2) -- a câmera da mesa chega primeiro
				open(true)
			end
			return
		end
	end
end)
