--!strict
-- Contagem do começo da partida (D-122, pedido do dono: "a partida deve começar com cada um na sua base
-- com uma contagem regressiva; depois a partida começa e os jogadores vão dominar os pontos").
-- O servidor manda no Match_State quantos segundos faltam (prep). Aqui, no alto do meio da tela:
--   - "A PARTIDA COMEÇA EM", o número grande e "Espere na sua base" (os 5 últimos pulsam);
--   - no zero, "VALENDO!" em latão por 2,5 s, com "Tome os pontos".
-- Some com o menu principal aberto (ele tem a tela toda) e não pede clique.
-- Lote 22 (contagem de 10 s com os veículos): embaixo, "Pegue um veículo e espere na base"; quem o
-- servidor puxa de volta (PreparoService: atributo PrepVolta do Player) vê "Não saia da base!" em
-- vermelho por 2,5 s.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F

local gui = UiKit.screen("VT65Contagem", 26) -- acima do HUD de campo, abaixo da tela de baixa (25+)
gui.IgnoreGuiInset = true
gui.Enabled = false

local box = Instance.new("CanvasGroup")
box.Name = "Contagem"
box.AnchorPoint = Vector2.new(0.5, 0)
box.Position = UDim2.new(0.5, 0, 0, 120)
box.Size = UDim2.fromOffset(520, 210)
box.BackgroundTransparency = 1
box.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = box

local function label(y: number, h: number, font: Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(0, y)
	t.Size = UDim2.new(1, 0, 0, h)
	t.FontFace = font
	t.TextSize = UiKit.text(size)
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.55
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.Parent = box
	return t
end

local top = label(0, 32, F.TITLE_MED, 26, V.KHAKI)
local num = label(30, 120, F.TITLE, 110, V.TEXT)
local sub = label(156, 30, F.BODY, 22, V.TEXT)

local shown = -1
local goUntil = 0
local lastPrep = 0
local backUntil = 0 -- até quando mostra o "Não saia da base!"
local AVISO_COR = Color3.fromRGB(255, 96, 80)

local function menuOpen(): boolean
	return player:GetAttribute("MenuPrincipal") == true
end

-- Lote 22: a contagem é de quem já está em campo. Na mesa (escolha de lado, squad e papel: o
-- VT65LobbyBackdrop ligado) ela tapava as bandeiras; ali a partida espera cheia (MatchService) e o
-- número ficava parado em 10.
local function inField(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local lobby = pg and pg:FindFirstChild("VT65LobbyBackdrop")
	if lobby and lobby:IsA("ScreenGui") and lobby.Enabled then
		return false
	end
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and player:GetAttribute("Role") ~= nil
end

local function paint(prep: number)
	if prep > 0 then
		top.Text = "A PARTIDA COMEÇA EM"
		top.TextColor3 = V.KHAKI
		num.Text = string.format("%d", prep)
		num.TextColor3 = if prep <= 5 then UiKit.BRASS_LIGHT else V.TEXT
		if os.clock() < backUntil then
			sub.Text = "Não saia da base!"
			sub.TextColor3 = AVISO_COR
		else
			sub.Text = "Pegue um veículo e espere na base"
			sub.TextColor3 = V.TEXT
		end
		if prep ~= shown then
			shown = prep
			-- cada segundo: o número cresce e assenta (os 5 últimos com mais força)
			scale.Scale = if prep <= 5 then 1.18 else 1.06
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	else
		top.Text = ""
		num.Text = "VALENDO!"
		num.TextColor3 = UiKit.BRASS_LIGHT
		sub.Text = "Tome os pontos"
		sub.TextColor3 = V.TEXT
	end
end

-- o servidor puxou este jogador de volta para a base: avisa já, sem esperar o próximo Match_State
player:GetAttributeChangedSignal("PrepVolta"):Connect(function()
	backUntil = os.clock() + 2.5
	if gui.Enabled and lastPrep > 0 then
		paint(lastPrep)
	end
end)

Net.event("Match_State").OnClientEvent:Connect(function(st: any)
	if type(st) ~= "table" then
		return
	end
	local prep = if type(st.prep) == "number" then st.prep else 0
	if st.ended then
		prep = 0
	end
	if lastPrep > 0 and prep <= 0 and not st.ended then
		goUntil = os.clock() + 2.5 -- acabou a contagem: VALENDO!
		scale.Scale = 1.25
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
	lastPrep = prep
	local on = (prep > 0 or os.clock() < goUntil) and not menuOpen() and inField()
	gui.Enabled = on
	if on then
		paint(prep)
	end
	if prep <= 0 and os.clock() >= goUntil then
		shown = -1
	end
end)

-- o VALENDO! some sozinho (o Match_State chega a cada 1 s; aqui fecha no tempo certo)
task.spawn(function()
	while true do
		task.wait(0.25)
		if gui.Enabled and ((lastPrep <= 0 and os.clock() >= goUntil) or not inField()) then
			gui.Enabled = false
		end
	end
end)
