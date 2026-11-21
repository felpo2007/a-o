--!strict
-- Contagem do começo da partida (D-122, pedido do dono: "a partida deve começar com cada um na sua base
-- com uma contagem regressiva; depois a partida começa e os jogadores vão dominar os pontos").
-- D-203 (§22): o número sai do relógio do servidor: o atributo "VT65InicioEm" do ReplicatedStorage (a
-- hora em que a partida vale, no GetServerTimeNow; MatchService) passa pelo Shared/Rodada.contagem.
-- Todos os clientes viram o número juntos e quem entra no meio lê o atributo. Antes vinha do
-- Match_State, a cada 1 s: cada cliente virava o número quando o pacote chegava. Depois do fim
-- ("VT65Fase" fora de "jogo") não há contagem. Aqui, no alto do meio da tela:
--   - "A PARTIDA COMEÇA EM", o número grande e "Espere na sua base" (os 5 últimos pulsam, cada um
--     com um toque seco, D-203);
--   - no zero, "VALENDO!" em latão por 2,5 s, com "Tome os pontos" e o apito de campo (D-203; os
--     sons saem de tools/sons_partida.py).
-- Some com o menu principal aberto (ele tem a tela toda) e não pede clique.
-- Lote 22 (contagem de 10 s com os veículos): embaixo, "Pegue um veículo e espere na base"; quem o
-- servidor puxa de volta (PreparoService: atributo PrepVolta do Player) vê "Não saia da base!" em
-- vermelho por 2,5 s.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Rodada = require(ReplicatedStorage.Shared.Rodada)
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

-- D-216 (dono: "os textos no celular estão horriveis tudo em cima do outro"): na tela baixa do celular
-- a contagem sobe e encolhe, para a frase de baixo não cair em cima do cartão da arma
local function encaixa()
	local cam = workspace.CurrentCamera
	local baixa = cam ~= nil and cam.ViewportSize.Y < 620
	box.Position = UDim2.new(0.5, 0, 0, if baixa then 104 else 120)
	box.Size = UDim2.fromOffset(520, if baixa then 124 else 210)
	top.Size = UDim2.new(1, 0, 0, if baixa then 22 else 32)
	top.TextSize = UiKit.text(if baixa then 18 else 26)
	num.Position = UDim2.fromOffset(0, if baixa then 20 else 30)
	num.Size = UDim2.new(1, 0, 0, if baixa then 74 else 120)
	num.TextSize = UiKit.text(if baixa then 66 else 110)
	sub.Position = UDim2.fromOffset(0, if baixa then 96 else 156)
	sub.Size = UDim2.new(1, 0, 0, if baixa then 24 else 30)
	sub.TextSize = UiKit.text(if baixa then 15 else 22)
end
encaixa()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(encaixa)
end

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

-- o servidor puxou este jogador de volta para a base: avisa já
player:GetAttributeChangedSignal("PrepVolta"):Connect(function()
	backUntil = os.clock() + 2.5
	if gui.Enabled and lastPrep > 0 then
		paint(lastPrep)
	end
end)

-- D-203: sons da contagem (Sounds.contagem_tique e partida_apito; 0 = sem som), carregados antes
local function idSom(chave: string): number?
	local id = AssetIds.Sounds and AssetIds.Sounds[chave]
	return if type(id) == "number" and id ~= 0 then id else nil
end
task.spawn(function()
	local lista = {}
	for _, k in { "contagem_tique", "partida_apito" } do
		local id = idSom(k)
		if id then
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. id
			table.insert(lista, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(lista)
	end)
	for _, s in lista do
		s:Destroy()
	end
end)
local function tocar(chave: string, vol: number)
	local id = idSom(chave)
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "VT65Contagem_" .. chave
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol
	local g = SoundService:FindFirstChild("VT65Efeitos")
	if g and g:IsA("SoundGroup") then
		s.SoundGroup = g
	end
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

-- depois do fim da partida (fim, comemoração, votação, restauração) não há contagem
local function acabou(): boolean
	local f = ReplicatedStorage:GetAttribute("VT65Fase")
	return type(f) == "string" and f ~= "jogo"
end

local function passo()
	local inicio = ReplicatedStorage:GetAttribute("VT65InicioEm")
	local prep = Rodada.contagem(if type(inicio) == "number" then inicio else nil, workspace:GetServerTimeNow())
	local fim = acabou()
	if fim then
		prep = 0
	end
	local campo = inField() and not menuOpen()
	if lastPrep > 0 and prep <= 0 and not fim then
		goUntil = os.clock() + 2.5 -- acabou a contagem: VALENDO!
		scale.Scale = 1.25
		TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		if campo then
			tocar("partida_apito", 0.6)
		end
	elseif prep > 0 and prep <= 5 and prep ~= lastPrep and campo then
		tocar("contagem_tique", 0.35)
	end
	lastPrep = prep
	local on = (prep > 0 or os.clock() < goUntil) and campo
	gui.Enabled = on
	if on then
		paint(prep)
	end
	if prep <= 0 and os.clock() >= goUntil then
		shown = -1
	end
end

-- 20 vezes por segundo: o número vira no máximo 50 ms depois do relógio do servidor
local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 0.05 then
		return
	end
	acc = 0
	passo()
end)
