--!strict
-- Janela do chat do Roblox no campo (D-93, visto no Studio: "Digite '/?' ou '/help'…" e as mensagens
-- de equipe ficavam no canto de cima à esquerda, por cima da faixa de XP). O chat continua: só vai
-- para o alto à DIREITA (livre no HUD: a faixa da frente e os avisos ficam no meio, o tutorial e o
-- registro de rádio embaixo à esquerda, a arma embaixo à direita), mais estreita, mais baixa e mais
-- transparente, no Arimo (tem as letras do vietnamita).
-- Quando aparece (um dono só: antes o LobbyScene ligava e desligava e nada mais escondia): some com
-- o lobby aberto (VT65LobbyBackdrop ligado), com qualquer tela de menu (menu do jogo, loja, relatório,
-- ficha de baixa, tela de fim: Input.state.menus > 0) e com o mapa. Muda só quando a decisão muda.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

local function apply(cfg: Instance)
	if not cfg:IsA("ChatWindowConfiguration") then
		return
	end
	local w = cfg :: any
	for prop, value in
		{
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			WidthScale = 0.8,
			HeightScale = 0.65,
			BackgroundTransparency = 0.72,
			TextSize = UiKit.text(14),
			TextStrokeTransparency = 0.6,
			FontFace = Font.fromEnum(Enum.Font.Arimo),
		} :: { [string]: any }
	do
		pcall(function()
			w[prop] = value
		end)
	end
end

-- ===== mostrar ou esconder =====
local lobby: ScreenGui? = nil
local shown: boolean? = nil
local function decide()
	local lobbyOn = lobby ~= nil and lobby.Enabled
	local want = not lobbyOn and Input.state.menus == 0 and not Input.state.map
	if want == shown then
		return
	end
	shown = want
	pcall(function()
		local cfg = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if cfg then
			cfg.Enabled = want
		end
		-- só a janela não basta: a barra de digitar e as mensagens do sistema seguiam por cima
		local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
		if bar then
			bar.Enabled = want
		end
		local tabsCfg = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
		if tabsCfg then
			tabsCfg.Enabled = want
		end
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, want)
	end)
end

-- ===== abas dos canais (2026-11-12: canais perto, squad, lado e geral, Modules/Comunicacao) =====
-- As abas do Roblox mostram o NOME do canal: os canais do jogo (VT65*) ganham, só neste cliente, o
-- rótulo da aba no idioma do jogador (o servidor continua com o nome dele; o CanaisChat acha o de
-- perto pelo atributo VT65Canal). Os do Roblox (RBXGeneral, RBXTeam...) ficam como estão: o próprio
-- Roblox os rotula ("Geral", "Time") no idioma da conta.
local TAB_NAMES: { [string]: { [string]: string } } = {
	pt = { perto = "Perto", squad = "Squad", lado = "Time", geral = "Geral" },
	en = { perto = "Nearby", squad = "Squad", lado = "Team", geral = "General" },
	es = { perto = "Cerca", squad = "Escuadra", lado = "Equipo", geral = "General" },
	vi = { perto = "Gần", squad = "Tiểu đội", lado = "Phe", geral = "Chung" },
}
local function label(ch: Instance)
	if not ch:IsA("TextChannel") then
		return
	end
	local kind = ch:GetAttribute("VT65Canal")
	local orig = ch:GetAttribute("VT65Nome")
	if type(orig) ~= "string" then
		if string.sub(ch.Name, 1, 4) ~= "VT65" then
			return -- canal do Roblox
		end
		orig = ch.Name
		ch:SetAttribute("VT65Nome", orig) -- o nome do servidor, guardado (local)
	end
	local lang = player:GetAttribute("Lang")
	local names = TAB_NAMES[if type(lang) == "string" then lang else "pt"] or TAB_NAMES.pt
	local want = if type(kind) == "string" then names[kind] else nil
	if want and ch.Name ~= want then
		pcall(function()
			ch.Name = want
		end)
	end
end
local function watchChannels(folder: Instance)
	for _, ch in folder:GetChildren() do
		label(ch)
	end
	folder.ChildAdded:Connect(function(ch)
		label(ch)
		ch:GetAttributeChangedSignal("VT65Canal"):Connect(function()
			label(ch)
		end)
	end)
end
player:GetAttributeChangedSignal("Lang"):Connect(function()
	local folder = TextChatService:FindFirstChild("TextChannels")
	if folder then
		for _, ch in folder:GetChildren() do
			label(ch)
		end
	end
end)

local function tabs(c: Instance)
	if not c:IsA("ChannelTabsConfiguration") then
		return
	end
	local w = c :: any
	for prop, value in
		{
			Enabled = true,
			BackgroundTransparency = 0.72,
			TextSize = UiKit.text(14),
			FontFace = Font.fromEnum(Enum.Font.ArimoBold),
		} :: { [string]: any }
	do
		pcall(function()
			w[prop] = value
		end)
	end
end

local function onConfig(c: Instance)
	apply(c)
	tabs(c)
	if c:IsA("ChatWindowConfiguration") or c:IsA("ChatInputBarConfiguration") or c:IsA("ChannelTabsConfiguration") then
		shown = nil -- configuração nova: aplica a decisão de novo
		decide()
	end
	if c.Name == "TextChannels" then
		watchChannels(c)
	end
end
for _, c in TextChatService:GetChildren() do
	onConfig(c)
end
TextChatService.ChildAdded:Connect(onConfig)

Input.StateChanged:Connect(decide)
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local function watchGui(g: Instance)
		if g.Name == "VT65LobbyBackdrop" and g:IsA("ScreenGui") then
			lobby = g
			g:GetPropertyChangedSignal("Enabled"):Connect(decide)
			decide()
		end
	end
	for _, g in pg:GetChildren() do
		watchGui(g)
	end
	pg.ChildAdded:Connect(watchGui)
	-- rede de segurança barata (2 Hz): algum caminho que mude o estado sem avisar
	while true do
		task.wait(0.5)
		decide()
	end
end)
decide()
