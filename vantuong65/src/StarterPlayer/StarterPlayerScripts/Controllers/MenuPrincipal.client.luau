--!strict
-- Menu principal = o lobby (D-206; prompt de interface §6 e as referências do dono, 2026-11-20: "quero
-- q vc se baseie nas imagens para criar o lobby ... com imagens bem feitas transições de qualidade
-- como se fosse um jogo sensacional de alta qualidade visual").
-- Das referências vem a composição, numa grade dentro da área segura (§6):
--   - esquerda, no escuro: a marca, o cartão grande do JOGAR (a ação mais evidente) e a navegação
--     em letras grandes (ARSENAL, MISSÕES, PERFIL, COMO JOGAR), depois LOJA, PASSE e CONFIGURAÇÕES;
--   - centro e direita: o próprio soldado do jogador num acampamento ao fim da tarde (LobbyPalco);
--   - direita: o resumo do passe e das ordens do dia, a recompensa diária e um destaque da loja
--     (posição secundária, fora do caminho do JOGAR);
--   - rodapé: os comandos do aparelho à esquerda; saldo, posto, jogadores e o jogador à direita.
-- A identidade é deste jogo (1965, âmbar e oliva, as capas do dono): nada de nome, ícone ou texto
-- das referências.
-- Transições (§4): a entrada escalonada (os blocos esmaecem e deslizam, a câmera desce e a luz do
-- soldado acende); o foco (mouse, controle ou toque) realça a entrada com a barra âmbar, troca a
-- descrição e a imagem do cartão grande (fusão de 0,3 s) e ajusta o enquadramento do soldado. Com
-- movimento reduzido, só esmaece e corta.
-- Comportamento (o de antes): abre uma vez por sessão depois da tela de entrada, sem corpo em campo;
-- o JOGAR fecha e mostra a mesa do lobby (lado, squad, papel e ponto). Enquanto aberto, o atributo
-- "MenuPrincipal" do jogador fica true (o GameUI esconde a mesa) e a câmera é do palco. As outras
-- telas (loja, passe, missões, cartão, configurações, tutorial) abrem por cima; o menu esmaece e o
-- soldado muda de enquadramento.
-- Studio: workspace "VT65DevTela" = "menu_principal" abre de novo; "VT65DevNome" troca o nome
-- mostrado no rodapé (capturas sem o nome da conta).
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local SolarPosition = require(ReplicatedStorage.Shared.SolarPosition)
local Bus = require(script.Parent.Bus)
local CampanhaCliente = require(script.Parent.CampanhaCliente)
local ComoJogar = require(script.Parent.ComoJogar)
local Input = require(script.Parent.Input)
local LobbyPalco = require(script.Parent.LobbyPalco)
local ArteCatalogo = require(script.Parent.ArteCatalogo)
local FundoLobby = require(script.Parent.FundoLobby)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local Estilo = UiKit.Estilo

-- fim de tarde de 18/08/1965 em Vạn Tường (hora de Saigon, UTC+8): sol a ~13° no oés-noroeste
local MENU_HOUR = 18.1
local SUN = { year = 1965, month = 8, day = 18, tz = 8, lat = 15.30, lon = 108.85 }
local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local function img(id: number?): string
	return if type(id) == "number" and id > 0 then "rbxassetid://" .. id else ""
end
local CAPA = AssetIds.Capas or {}
local LOJA_IMG = AssetIds.LojaImages or {}

-- ===== telas =====
-- o fundo (sombras sobre o palco) cobre a tela inteira, fora da área segura também
local fundo = Instance.new("ScreenGui")
fundo.Name = "VT65MenuFundo"
fundo.ResetOnSpawn = false
fundo.IgnoreGuiInset = true
fundo.DisplayOrder = 27
fundo.Enabled = false
pcall(function()
	fundo.ScreenInsets = Enum.ScreenInsets.None
end)
fundo.Parent = player:WaitForChild("PlayerGui")
-- D-222 (dono: "troque o fundo do lobby, coloque algo com mais qualidade e não deixe ele tremendo"; o
-- lobby fica sem personagem): uma imagem parada na frente do palco 3D
FundoLobby.novo(fundo, 0, -5)

local function sombra(name: string, rot: number, size: UDim2, pos: UDim2, anchor: Vector2, keys: { { number } }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = anchor
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = Color3.fromRGB(5, 5, 4)
	f.BorderSizePixel = 0
	f.Parent = fundo
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	local seq = {}
	for _, k in keys do
		table.insert(seq, NumberSequenceKeypoint.new(k[1], k[2]))
	end
	g.Transparency = NumberSequence.new(seq)
	g.Parent = f
	return f
end
-- a coluna da esquerda no escuro (como nas referências), o rodapé e o alto mais fundos
local sombraEsq = sombra(
	"Esquerda",
	0,
	UDim2.fromScale(0.62, 1),
	UDim2.fromScale(0, 0),
	Vector2.zero,
	{ { 0, 0.02 }, { 0.45, 0.2 }, { 0.78, 0.72 }, { 1, 1 } }
)
local sombraBaixo =
	sombra("Baixo", -90, UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 1), Vector2.new(0, 1), { { 0, 0.25 }, { 1, 1 } })
local sombraCima =
	sombra("Cima", 90, UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0), Vector2.zero, { { 0, 0.45 }, { 1, 1 } })
-- o escuro do JOGAR (a tela some num preto quente antes da mesa)
local cortina = Instance.new("Frame")
cortina.Name = "Cortina"
cortina.Size = UDim2.fromScale(1, 1)
cortina.BackgroundColor3 = Color3.fromRGB(8, 7, 5)
cortina.BackgroundTransparency = 1
cortina.BorderSizePixel = 0
cortina.ZIndex = 10
cortina.Parent = fundo

local gui = UiKit.screen("VT65MenuPrincipal", 28) -- acima do lobby (18 a 22), abaixo da loja (30)
gui.Enabled = false
local palco = Instance.new("Frame")
palco.Name = "Palco"
palco.Size = UDim2.fromScale(1, 1)
palco.BackgroundTransparency = 1
palco.Parent = gui

-- Escala: o projeto é de 1080 de altura; a tela mede a altura (e a largura, para caber nas telas
-- estreitas). Cada bloco fica preso à sua borda (esquerda, direita, rodapé) e escala sozinho.
local escalas: { UIScale } = {}
-- D-216 (dono: "os textos no celular estão horriveis tudo em cima do outro"): com menos de 620 de
-- altura o projeto de 1080 não cabe (a escala parava em 0,42 e a coluna passava da tela, cortando
-- LOJA, ARMÁRIO e PASSE). Ali entra o arranjo compacto (`aplicarCompacto`, no fim das peças).
local COMPACTO_ALTURA, COMPACTO_H, COMPACTO_W = 620, 600, 1180
local aplicarCompacto: (boolean) -> () = function() end
local function ehCompacto(): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and cam.ViewportSize.Y < COMPACTO_ALTURA
end
local function escalaAgora(): number
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
	if ehCompacto() then
		return math.clamp(math.min(v.Y / COMPACTO_H, v.X / COMPACTO_W), 0.42, 1)
	end
	return math.clamp(math.min(v.Y / 1080, v.X / 1640), 0.42, 1.3)
end
-- o soldado fica no meio do espaço livre entre o que está escrito à esquerda (72 + 600 do projeto)
-- e os quadros da direita (que começam 34 depois da borda do bloco de 560)
local function ajustarAlvo()
	local w = gui.AbsoluteSize.X
	if w < 10 then
		local cam = workspace.CurrentCamera
		w = if cam then cam.ViewportSize.X else 1920
	end
	local k = escalaAgora()
	local l = (if ehCompacto() then 16 + 440 else 72 + 600) * k
	local r = w - (560 - 34) * k
	LobbyPalco.telaX = math.clamp((l + r) / 2 / math.max(w, 1), 0.4, 0.8)
end
local function reescalar()
	local k = escalaAgora()
	for _, s in escalas do
		s.Scale = k
	end
	aplicarCompacto(ehCompacto())
	ajustarAlvo()
end

local function bloco(name: string, anchor: Vector2, pos: UDim2, w: number, h: number): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Name = name
	g.AnchorPoint = anchor
	g.Position = pos
	g.Size = UDim2.fromOffset(w, h)
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	g.Parent = palco
	local s = Instance.new("UIScale")
	s.Name = "Escala"
	s.Parent = g
	table.insert(escalas, s)
	g:SetAttribute("Base", pos)
	return g
end

local esq = bloco("Conteudo", Vector2.zero, UDim2.fromScale(0, 0), 720, 1080)
local dir = bloco("Resumo", Vector2.new(1, 0), UDim2.fromScale(1, 0), 560, 1080)
local rodape = bloco("Perfil", Vector2.new(1, 1), UDim2.fromScale(1, 1), 820, 104)
local dicasB = bloco("Dicas", Vector2.new(0, 1), UDim2.fromScale(0, 1), 900, 80)
reescalar()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(reescalar)
end

-- ----- peças -----
local function rotulo(parent: Instance, text: string, font: Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	-- títulos no Oswald; com letra do vietnamita ou símbolo (★ ✓ ›), no Arimo Bold, que tem
	t.FontFace = if font == F.BODY or font == F.BODY_B then font else Estilo.headFont(text, font)
	t.TextSize = Estilo.ts(size)
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = text
	t.Parent = parent
	return t
end
local function caixa(parent: Instance, x: number, y: number, w: number, h: number): Frame
	local f = Estilo.panel(parent, V.PANEL, 0.12, true)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	return f
end
local function regua(parent: Instance, x: number, y: number, w: number, color: Color3?, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or V.LINE
	f.BackgroundTransparency = tr or 0.35
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, 1)
	f.Parent = parent
	return f
end
local function etiqueta(parent: Instance, text: string, color: Color3, dark: boolean?): TextLabel
	local t = Estilo.tag(parent, text, color, 14)
	t.Size = UDim2.fromOffset(0, 26)
	t.TextColor3 = if dark then V.AMBAR_TEXTO else V.TEXT
	return t
end
local function barra(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local back, fill = Estilo.bar(parent, h, color)
	back.Position = UDim2.fromOffset(x, y)
	back.Size = UDim2.fromOffset(w, h)
	return fill
end

-- ===== esquerda =====
local X0 = 72
-- ----- marca -----
local marca = Instance.new("Frame")
marca.Name = "Marca"
marca.BackgroundTransparency = 1
marca.Position = UDim2.fromOffset(X0, 50)
marca.Size = UDim2.fromOffset(620, 170)
marca.Parent = esq
local m1 = rotulo(marca, "STARLITE", F.TITLE, 74, V.TEXT)
m1.Size = UDim2.fromOffset(620, 80)
local m2 = rotulo(marca, "VIETNÃ 1965", F.TITLE_MED, 32, V.KHAKI)
m2.Position = UDim2.fromOffset(3, 78)
m2.Size = UDim2.fromOffset(620, 38)
local m3 = Instance.new("Frame")
m3.BackgroundColor3 = V.RED
m3.BorderSizePixel = 0
m3.Position = UDim2.fromOffset(4, 124)
m3.Size = UDim2.fromOffset(96, 4)
m3.Parent = marca
local m4 = rotulo(marca, "OPERAÇÃO STARLITE · AGOSTO DE 1965", F.BODY, 16, V.DIM)
m4.Position = UDim2.fromOffset(4, 134)
m4.Size = UDim2.fromOffset(620, 24)

-- ----- cartão grande: JOGAR -----
local k1 = rotulo(esq, "PARTIDA", F.TITLE_REG, 16, V.DIM)
k1.Position = UDim2.fromOffset(X0, 236)
k1.Size = UDim2.fromOffset(300, 22)
local reguaPartida = regua(esq, X0, 262, 600)

local CARD_W, CARD_H = 600, 214
local card = Instance.new("TextButton")
card.Name = "JOGAR"
card.AutoButtonColor = false
card.Text = ""
card.Position = UDim2.fromOffset(X0, 276)
card.Size = UDim2.fromOffset(CARD_W, CARD_H)
card.BackgroundColor3 = V.BG
card.BorderSizePixel = 0
card.ClipsDescendants = true
card.Selectable = true
card.SelectionImageObject = UiKit.FOCUS
card.Parent = esq
UiKit.corner(card, 4)
local cardEdge = UiKit.edge(card, V.LINE, 1, 0.4)
-- duas imagens para a fusão; a de cima cresce devagar (Ken Burns) enquanto está à vista
local capaA = Instance.new("ImageLabel")
capaA.Name = "CapaA"
capaA.BackgroundTransparency = 1
capaA.AnchorPoint = Vector2.new(0.5, 0.5)
capaA.Position = UDim2.fromScale(0.5, 0.5)
capaA.Size = UDim2.fromScale(1.06, 1.06)
capaA.ScaleType = Enum.ScaleType.Crop
capaA.Parent = card
local capaB = capaA:Clone()
capaB.Name = "CapaB"
capaB.ImageTransparency = 1
capaB.Parent = card
-- o escuro da esquerda, para o texto
local capaSombra = Instance.new("Frame")
capaSombra.Name = "Sombra"
capaSombra.Size = UDim2.fromScale(1, 1)
capaSombra.BackgroundColor3 = Color3.fromRGB(6, 6, 5)
capaSombra.BorderSizePixel = 0
capaSombra.Parent = card
local csg = Instance.new("UIGradient")
csg.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.08),
	NumberSequenceKeypoint.new(0.55, 0.55),
	NumberSequenceKeypoint.new(1, 0.95),
})
csg.Parent = capaSombra
-- o botão âmbar dentro do cartão (a ação principal)
local jogarBox = Instance.new("Frame")
jogarBox.Name = "Botao"
jogarBox.BackgroundColor3 = V.AMBAR
jogarBox.BorderSizePixel = 0
jogarBox.Position = UDim2.fromOffset(28, 30)
jogarBox.Size = UDim2.fromOffset(250, 78)
jogarBox.Parent = card
UiKit.corner(jogarBox, 3)
UiKit.edge(jogarBox, V.AMBAR_TEXTO, 2, 0.55)
local jogarTxt = rotulo(jogarBox, "JOGAR", F.TITLE, 54, V.AMBAR_TEXTO)
jogarTxt.Name = "Texto"
jogarTxt.Position = UDim2.fromOffset(22, 0)
jogarTxt.Size = UDim2.new(1, -60, 1, 0)
local jogarSeta = rotulo(jogarBox, "›", F.TITLE, 50, V.AMBAR_TEXTO)
jogarSeta.AnchorPoint = Vector2.new(1, 0)
jogarSeta.Position = UDim2.new(1, -18, 0, -2)
jogarSeta.Size = UDim2.fromOffset(26, 78)
local jogarSub = rotulo(card, "Escolha o lado, o squad, o papel e onde nascer.", F.BODY, 17, V.TEXT)
jogarSub.Position = UDim2.fromOffset(30, 124)
jogarSub.Size = UDim2.fromOffset(CARD_W - 60, 24)
local jogarModo = rotulo(card, "", F.TITLE_MED, 16, V.KHAKI)
jogarModo.Name = "Modo"
jogarModo.Position = UDim2.fromOffset(30, 156)
jogarModo.Size = UDim2.fromOffset(CARD_W - 60, 22)
local jogarTecla = Instance.new("ImageLabel")
jogarTecla.Name = "Tecla"
jogarTecla.BackgroundTransparency = 1
jogarTecla.AnchorPoint = Vector2.new(0, 0.5)
jogarTecla.Position = UDim2.new(1, 12, 0.5, 0)
jogarTecla.Size = UDim2.fromOffset(34, 34)
jogarTecla.Visible = false
jogarTecla.Parent = jogarBox

-- ----- navegação -----
type Item = {
	id: string,
	b: TextButton,
	label: TextLabel,
	linha: Frame, -- o texto e a etiqueta, lado a lado (desliza no foco)
	bar: Frame,
	tag: TextLabel?,
	desc: string,
	capa: string,
	quadro: string,
	acao: () -> (),
	big: boolean,
}
local itens: { Item } = {}
local focoAtual: Item? = nil

local function item(
	parent: Instance,
	id: string,
	text: string,
	y: number,
	h: number,
	size: number,
	desc: string,
	capa: string,
	quadro: string,
	acao: () -> ()
): Item
	local b = Instance.new("TextButton")
	b.Name = id
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Position = UDim2.fromOffset(X0, y)
	b.Size = UDim2.fromOffset(600, h)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = parent
	local bar = Instance.new("Frame")
	bar.Name = "Barra"
	bar.BackgroundColor3 = V.AMBAR
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 0, 0.5, 0)
	bar.Size = UDim2.new(0, 0, 0.72, 0)
	bar.Parent = b
	local linha = Instance.new("Frame")
	linha.Name = "Linha"
	linha.BackgroundTransparency = 1
	linha.AutomaticSize = Enum.AutomaticSize.X
	linha.Size = UDim2.fromOffset(0, h)
	linha.Parent = b
	local lay = Estilo.list(linha, true, 14)
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	local l = rotulo(linha, text, F.TITLE, size, V.TEXT)
	l.Name = "Texto"
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, h)
	l.LayoutOrder = 1
	local it: Item = {
		id = id,
		b = b,
		label = l,
		linha = linha,
		bar = bar,
		tag = nil,
		desc = desc,
		capa = capa,
		quadro = quadro,
		acao = acao,
		big = size >= 36,
	}
	table.insert(itens, it)
	return it
end
local function tagDe(it: Item, text: string, color: Color3, dark: boolean?)
	local t = it.tag
	if not t then
		local nt = etiqueta(it.linha, text, color, dark)
		nt.Name = "Etiqueta"
		nt.LayoutOrder = 2 -- logo depois do texto (a fileira cresce sozinha)
		it.tag = nt
		t = nt
	end
	local tt = t :: TextLabel
	tt.Text = text
	tt.BackgroundColor3 = color
	tt.TextColor3 = if dark then V.AMBAR_TEXTO else V.TEXT
	tt.Visible = text ~= ""
end

local open = false
local opened = false -- já abriu nesta sessão (só reabre pelo gancho do Studio)
local busy = false -- um botão de cada vez (o JOGAR fechando)
local function livre(): boolean
	return open and not busy
end

local NAV_Y, NAV_H = 512, 52
item(
	esq,
	"ARSENAL",
	"ARSENAL",
	NAV_Y,
	NAV_H,
	40,
	"Equipamento por posto e créditos: o que vai no peso do seu kit.",
	"trincheira",
	"arsenal",
	function()
		Bus.fire("shop_open", "intendencia")
	end
)
local itMissoes = item(
	esq,
	"MISSOES",
	"MISSÕES",
	NAV_Y + NAV_H,
	NAV_H,
	40,
	"Ordens do dia e da semana: XP, créditos e estrelas do passe.",
	"riacho",
	"missoes",
	function()
		Bus.fire("missoes_open")
	end
)
item(
	esq,
	"PERFIL",
	"PERFIL",
	NAV_Y + 2 * NAV_H,
	NAV_H,
	40,
	"Seu cartão: posto, medalhas, emblema e o placar da semana.",
	"chuva",
	"perfil",
	function()
		Bus.fire("cartao_open")
	end
)
item(
	esq,
	"TUTORIAL",
	"COMO JOGAR",
	NAV_Y + 3 * NAV_H,
	NAV_H,
	40,
	"Os comandos e o básico da partida, sem entrar em campo.",
	"posto",
	"tutorial",
	function()
		ComoJogar.open()
	end
)
local descr = rotulo(esq, "", F.BODY, 17, V.DIM)
descr.Name = "Descricao"
descr.Position = UDim2.fromOffset(X0 + 22, NAV_Y + 4 * NAV_H + 6)
descr.Size = UDim2.fromOffset(580, 26)
descr.TextTruncate = Enum.TextTruncate.AtEnd
local descrSeta = rotulo(esq, "▸", F.BODY_B, 16, V.AMBAR)
descrSeta.Position = UDim2.fromOffset(X0, NAV_Y + 4 * NAV_H + 6)
descrSeta.Size = UDim2.fromOffset(18, 26)
local SEP_Y = NAV_Y + 4 * NAV_H + 46
local reguaSecoes = regua(esq, X0, SEP_Y, 600)
local SEC_Y, SEC_H = SEP_Y + 14, 48
item(
	esq,
	"LOJA",
	"LOJA",
	SEC_Y,
	SEC_H,
	34,
	"Uniformes, acabamentos de arma, conjuntos e caixas.",
	"loja",
	"loja",
	function()
		Bus.fire("shop_open")
	end
)
-- D-211 (dono: "coloque o botão do armário no lobby"): a arma de cada papel (a M16 dos EUA está lá) e o
-- que você já tem para vestir
item(
	esq,
	"ARMARIO",
	"ARMÁRIO",
	SEC_Y + SEC_H,
	SEC_H,
	34,
	"Sua arma principal por papel (M14, M16, espingarda...) e o que você já tem para vestir.",
	"armario",
	"arsenal",
	function()
		Bus.fire("shop_open", "armario")
	end
)
local itPasse = item(
	esq,
	"PASSE",
	"PASSE DE CAMPANHA",
	SEC_Y + 2 * SEC_H,
	SEC_H,
	34,
	"A trilha da temporada: recompensas por estrelas de partidas e ordens.",
	"bambu",
	"passe",
	function()
		Bus.fire("passe_open")
	end
)
item(
	esq,
	"CONFIGURACOES",
	"CONFIGURAÇÕES",
	SEC_Y + 3 * SEC_H,
	40,
	24,
	"Controles, mira, som, gráficos, idioma e acessibilidade.",
	"vila",
	"config",
	function()
		Bus.fire("menu_open", 1) -- aba Configurações
	end
)

-- ===== direita: passe, ordens do dia, diária e destaque =====
local RX, RW = 34, 470
-- ----- passe -----
local passeCard = Instance.new("TextButton")
passeCard.Name = "CartaoPasse"
passeCard.AutoButtonColor = false
passeCard.Text = ""
passeCard.Position = UDim2.fromOffset(RX, 48)
passeCard.Size = UDim2.fromOffset(RW, 196)
passeCard.BackgroundColor3 = V.PANEL
passeCard.BackgroundTransparency = Estilo.fundo(0.1)
passeCard.BorderSizePixel = 0
passeCard.Selectable = true
passeCard.SelectionImageObject = UiKit.FOCUS
passeCard.Parent = dir
UiKit.corner(passeCard, 4)
UiKit.edge(passeCard, V.LINE, 1, 0.45)
local pKick = rotulo(passeCard, "PASSE DE CAMPANHA", F.TITLE_REG, 15, V.DIM)
pKick.Position = UDim2.fromOffset(18, 12)
pKick.Size = UDim2.fromOffset(300, 22)
local pFim = rotulo(passeCard, "", F.TITLE_REG, 15, V.DIM)
pFim.AnchorPoint = Vector2.new(1, 0)
pFim.Position = UDim2.new(1, -18, 0, 12)
pFim.Size = UDim2.fromOffset(200, 22)
pFim.TextXAlignment = Enum.TextXAlignment.Right
regua(passeCard, 18, 40, RW - 36)
local pNivelK = rotulo(passeCard, "NÍVEL", F.TITLE_MED, 17, V.DIM)
pNivelK.Position = UDim2.fromOffset(18, 52)
pNivelK.Size = UDim2.fromOffset(80, 40)
local pNivel = rotulo(passeCard, "–", F.TITLE, 48, V.TEXT)
pNivel.Position = UDim2.fromOffset(80, 46)
pNivel.Size = UDim2.fromOffset(120, 52)
local pEstrelas = rotulo(passeCard, "", F.TITLE_MED, 18, V.KHAKI)
pEstrelas.AnchorPoint = Vector2.new(1, 0)
pEstrelas.Position = UDim2.new(1, -18, 0, 58)
pEstrelas.Size = UDim2.fromOffset(220, 30)
pEstrelas.TextXAlignment = Enum.TextXAlignment.Right
local pFill = barra(passeCard, 18, 104, RW - 36, 8, V.AMBAR)
local pVer = rotulo(passeCard, "VER O PASSE  ›", F.TITLE_MED, 18, V.TEXT)
pVer.Position = UDim2.fromOffset(18, 128)
pVer.Size = UDim2.fromOffset(200, 30)
local pVet = rotulo(passeCard, "", F.TITLE_MED, 16, V.DIM)
pVet.AnchorPoint = Vector2.new(1, 0)
pVet.Position = UDim2.new(1, -18, 0, 128)
pVet.Size = UDim2.fromOffset(240, 30)
pVet.TextXAlignment = Enum.TextXAlignment.Right
local pEstado = rotulo(passeCard, "", F.BODY, 14, V.DIM)
pEstado.Position = UDim2.fromOffset(18, 162)
pEstado.Size = UDim2.fromOffset(RW - 36, 22)

-- ----- ordens do dia -----
local ordens = caixa(dir, RX, 262, RW, 286)
ordens.Name = "Ordens"
local oKick = rotulo(ordens, "ORDENS DO DIA", F.TITLE_REG, 15, V.DIM)
oKick.Position = UDim2.fromOffset(18, 12)
oKick.Size = UDim2.fromOffset(240, 22)
local oNovas = rotulo(ordens, "", F.TITLE_REG, 15, V.DIM)
oNovas.AnchorPoint = Vector2.new(1, 0)
oNovas.Position = UDim2.new(1, -18, 0, 12)
oNovas.Size = UDim2.fromOffset(220, 22)
oNovas.TextXAlignment = Enum.TextXAlignment.Right
regua(ordens, 18, 40, RW - 36)
type Linha = { f: Frame, img: ImageLabel, t: TextLabel, n: TextLabel, r: TextLabel, fill: Frame }
local linhas: { Linha } = {}
for i = 1, 3 do
	local f = Instance.new("Frame")
	f.Name = "Ordem" .. i
	f.BackgroundColor3 = V.PANEL_2
	f.BackgroundTransparency = Estilo.fundo(0.15)
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(14, 50 + (i - 1) * 64)
	f.Size = UDim2.fromOffset(RW - 28, 58)
	f.Parent = ordens
	UiKit.corner(f, 3)
	-- D-227: a imagem da ordem (a arma, a bandeira, a maleta...)
	local img = Instance.new("ImageLabel")
	img.Name = "Imagem"
	img.BackgroundColor3 = V.BG
	img.BackgroundTransparency = 0.25
	img.BorderSizePixel = 0
	img.ScaleType = Enum.ScaleType.Fit
	img.Position = UDim2.fromOffset(4, 4)
	img.Size = UDim2.fromOffset(50, 50)
	img.Parent = f
	UiKit.corner(img, 3)
	local t = rotulo(f, "", F.TITLE_MED, 17, V.TEXT)
	t.Position = UDim2.fromOffset(62, 4)
	t.Size = UDim2.fromOffset(RW - 190, 28)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	local r = rotulo(f, "", F.TITLE, 18, V.AMBAR)
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.new(1, -12, 0, 4)
	r.Size = UDim2.fromOffset(100, 28)
	r.TextXAlignment = Enum.TextXAlignment.Right
	local fill = barra(f, 62, 38, RW - 200, 5, V.KHAKI)
	local n = rotulo(f, "", F.TITLE_MED, 14, V.DIM)
	n.AnchorPoint = Vector2.new(1, 0)
	n.Position = UDim2.new(1, -12, 0, 30)
	n.Size = UDim2.fromOffset(100, 22)
	n.TextXAlignment = Enum.TextXAlignment.Right
	table.insert(linhas, { f = f, img = img, t = t, n = n, r = r, fill = fill })
end
local oTodas = Instance.new("TextButton")
oTodas.Name = "TodasOrdens"
oTodas.AutoButtonColor = false
oTodas.BackgroundTransparency = 1
oTodas.Text = ""
oTodas.Position = UDim2.fromOffset(14, 246)
oTodas.Size = UDim2.fromOffset(RW - 28, 32)
oTodas.Selectable = true
oTodas.SelectionImageObject = UiKit.FOCUS
oTodas.Parent = ordens
local oResumo = rotulo(oTodas, "", F.TITLE_REG, 15, V.DIM)
oResumo.Size = UDim2.fromOffset(260, 32)
local oVer = rotulo(oTodas, "TODAS AS ORDENS  ›", F.TITLE_MED, 16, V.TEXT)
oVer.AnchorPoint = Vector2.new(1, 0)
oVer.Position = UDim2.new(1, 0, 0, 0)
oVer.Size = UDim2.fromOffset(200, 32)
oVer.TextXAlignment = Enum.TextXAlignment.Right

-- ----- recompensa diária -----
local diaria = caixa(dir, RX, 566, RW, 64)
diaria.Name = "Diaria"
local dBarra = Instance.new("Frame")
dBarra.BackgroundColor3 = V.AMBAR
dBarra.BorderSizePixel = 0
dBarra.Size = UDim2.new(0, 4, 1, 0)
dBarra.Parent = diaria
local dTit = rotulo(diaria, "RECOMPENSA DIÁRIA", F.TITLE_MED, 17, V.TEXT)
dTit.Position = UDim2.fromOffset(18, 6)
dTit.Size = UDim2.fromOffset(260, 26)
local dSub = rotulo(diaria, "", F.TITLE_REG, 14, V.DIM)
dSub.Position = UDim2.fromOffset(18, 32)
dSub.Size = UDim2.fromOffset(280, 22)
local pips: { Frame } = {}
for i = 1, 7 do
	local p = Instance.new("Frame")
	p.Name = "Dia" .. i
	p.AnchorPoint = Vector2.new(1, 0.5)
	p.Position = UDim2.new(1, -16 - (7 - i) * 20, 0.5, 0)
	p.Size = UDim2.fromOffset(14, 14)
	p.BackgroundColor3 = V.PANEL_3
	p.BorderSizePixel = 0
	p.Parent = diaria
	UiKit.corner(p, 2)
	table.insert(pips, p)
end

-- ----- destaque (carrossel; posição secundária) -----
local DEST_H = 184
local destaque = Instance.new("TextButton")
destaque.Name = "Destaque"
destaque.AutoButtonColor = false
destaque.Text = ""
destaque.Position = UDim2.fromOffset(RX, 648)
destaque.Size = UDim2.fromOffset(RW, DEST_H)
destaque.BackgroundColor3 = V.BG
destaque.BorderSizePixel = 0
destaque.ClipsDescendants = true
destaque.Selectable = true
destaque.SelectionImageObject = UiKit.FOCUS
destaque.Parent = dir
UiKit.corner(destaque, 4)
UiKit.edge(destaque, V.LINE, 1, 0.45)
local dImg = Instance.new("ImageLabel")
dImg.Name = "Imagem"
dImg.BackgroundTransparency = 1
dImg.Size = UDim2.fromScale(1, 1)
dImg.ScaleType = Enum.ScaleType.Crop
dImg.Parent = destaque
local dSom = capaSombra:Clone()
dSom.Parent = destaque
local dKick = rotulo(destaque, "", F.TITLE_MED, 14, V.AMBAR)
dKick.Position = UDim2.fromOffset(18, 16)
dKick.Size = UDim2.fromOffset(300, 22)
local dTitulo = rotulo(destaque, "", F.TITLE, 34, V.TEXT)
dTitulo.Position = UDim2.fromOffset(18, 38)
dTitulo.Size = UDim2.fromOffset(300, 82)
dTitulo.TextWrapped = true
dTitulo.TextYAlignment = Enum.TextYAlignment.Top
local dDesc = rotulo(destaque, "", F.BODY, 14, V.TEXT)
dDesc.Position = UDim2.fromOffset(18, 124)
dDesc.Size = UDim2.fromOffset(260, 36)
dDesc.TextWrapped = true
dDesc.TextYAlignment = Enum.TextYAlignment.Top
local dPontos: { Frame } = {}

-- ===== rodapé =====
local perfil = caixa(rodape, 0, 18, 820, 70)
perfil.Name = "Barra"
local seps: { Frame } = {}
local function sep(x: number)
	local s = Instance.new("Frame")
	s.BackgroundColor3 = V.LINE
	s.BackgroundTransparency = 0.4
	s.BorderSizePixel = 0
	s.Position = UDim2.fromOffset(x, 16)
	s.Size = UDim2.fromOffset(1, 38)
	s.Parent = perfil
	table.insert(seps, s)
end
local moeda = Instance.new("TextLabel")
moeda.Name = "Moeda"
moeda.BackgroundColor3 = V.AMBAR
moeda.BorderSizePixel = 0
moeda.Position = UDim2.fromOffset(18, 21)
moeda.Size = UDim2.fromOffset(28, 28)
moeda.FontFace = F.TITLE
moeda.TextSize = 18
moeda.TextColor3 = V.AMBAR_TEXTO
moeda.Text = Progression.CUR
moeda.Parent = perfil
UiKit.corner(moeda, 14)
local rCred = rotulo(perfil, "–", F.TITLE, 24, V.TEXT)
rCred.Name = "Creditos"
rCred.Position = UDim2.fromOffset(54, 17)
rCred.Size = UDim2.fromOffset(120, 36)
sep(184)
local rPostoK = rotulo(perfil, "POSTO", F.TITLE_REG, 13, V.DIM)
rPostoK.Position = UDim2.fromOffset(200, 12)
rPostoK.Size = UDim2.fromOffset(170, 18)
local rPosto = rotulo(perfil, "–", F.TITLE_MED, 20, V.TEXT)
rPosto.Name = "Posto"
rPosto.Position = UDim2.fromOffset(200, 30)
rPosto.Size = UDim2.fromOffset(170, 28)
rPosto.TextTruncate = Enum.TextTruncate.AtEnd
sep(384)
local rGenteK = rotulo(perfil, "NO SERVIDOR", F.TITLE_REG, 13, V.DIM)
rGenteK.Position = UDim2.fromOffset(400, 12)
rGenteK.Size = UDim2.fromOffset(110, 18)
local rGente = rotulo(perfil, "–", F.TITLE_MED, 20, V.TEXT)
rGente.Name = "Jogadores"
rGente.Position = UDim2.fromOffset(400, 30)
rGente.Size = UDim2.fromOffset(110, 28)
sep(520)
local avatar = Instance.new("ImageLabel")
avatar.Name = "Avatar"
avatar.BackgroundColor3 = V.PANEL_3
avatar.BorderSizePixel = 0
avatar.Position = UDim2.fromOffset(536, 13)
avatar.Size = UDim2.fromOffset(44, 44)
avatar.Parent = perfil
UiKit.corner(avatar, 4)
local rNome = rotulo(perfil, "", F.TITLE_MED, 20, V.TEXT)
rNome.Name = "Nome"
rNome.Position = UDim2.fromOffset(592, 10)
rNome.Size = UDim2.fromOffset(150, 28)
rNome.TextTruncate = Enum.TextTruncate.AtEnd
local rNivel = rotulo(perfil, "", F.TITLE_MED, 14, V.KHAKI)
rNivel.AnchorPoint = Vector2.new(1, 0)
rNivel.Position = UDim2.new(1, -18, 0, 12)
rNivel.Size = UDim2.fromOffset(70, 24)
rNivel.TextXAlignment = Enum.TextXAlignment.Right
local rXp = barra(perfil, 592, 46, 210, 5, V.AMBAR)

-- dicas do aparelho (embaixo à esquerda)
local chips = UiKit.chips(dicasB, 30, false, 15)
chips.frame.Position = UDim2.fromOffset(X0, 28)
local bgLoad = rotulo(dicasB, "", F.BODY, 14, V.DIM)
bgLoad.Name = "SegundoPlano"
bgLoad.Position = UDim2.fromOffset(X0, 2)
bgLoad.Size = UDim2.fromOffset(700, 22)
bgLoad.TextTruncate = Enum.TextTruncate.AtEnd

-- ===== D-216: o arranjo compacto (celular) =====
-- A coluna começa abaixo dos botões do Roblox (no canto de cima), com todas as entradas à vista; à
-- direita ficam o passe e as ordens; o rodapé encolhe para não cobrir nada. Sai o que é repetido
-- (marca, descrição da entrada, dicas de teclado, diária e destaque, que têm tela própria).
type Ajuste = { o: any, normal: { [string]: any }, compacto: { [string]: any } }
local ajustes: { Ajuste } = {}
local function ajuste(o: any, compacto: { [string]: any })
	local normal: { [string]: any } = {}
	for k in compacto do
		normal[k] = o[k]
	end
	table.insert(ajustes, { o = o, normal = normal, compacto = compacto })
end
local function oculta(lista: { any })
	for _, o in lista do
		ajuste(o, { Visible = false })
	end
end
do
	local XC, WC, TOPO = 16, 440, 112
	oculta({ marca, k1, reguaPartida, reguaSecoes, descr, descrSeta, jogarModo, diaria, destaque, dicasB })
	oculta({ rPostoK, rPosto, rGenteK, rGente, seps[2], seps[3] })
	ajuste(card, { Position = UDim2.fromOffset(XC, TOPO), Size = UDim2.fromOffset(WC, 124) })
	ajuste(jogarBox, { Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(250, 62) })
	ajuste(jogarTxt, { TextSize = Estilo.ts(46) })
	ajuste(jogarSeta, { Size = UDim2.fromOffset(26, 62) })
	ajuste(jogarSub, { Position = UDim2.fromOffset(18, 84), Size = UDim2.fromOffset(WC - 36, 28) })
	local LINHA = 44
	local ordem = { "ARSENAL", "MISSOES", "PERFIL", "TUTORIAL", "LOJA", "ARMARIO", "PASSE", "CONFIGURACOES" }
	for i, id in ordem do
		for _, it in itens do
			if it.id == id then
				local y = TOPO + 130 + (i - 1) * LINHA + (if i > 4 then 6 else 0)
				local h = if id == "CONFIGURACOES" then 36 else LINHA - 2
				ajuste(it.b, { Position = UDim2.fromOffset(XC, y), Size = UDim2.fromOffset(WC, h) })
				ajuste(it.linha, { Size = UDim2.fromOffset(0, h) })
				ajuste(it.label, { Size = UDim2.fromOffset(0, h) })
			end
		end
	end
	ajuste(passeCard, { Position = UDim2.fromOffset(RX, 8) })
	ajuste(ordens, { Position = UDim2.fromOffset(RX, 212) })
	ajuste(perfil, { Position = UDim2.fromOffset(820 - RW - 56, 30), Size = UDim2.fromOffset(RW, 70) })
	ajuste(avatar, { Position = UDim2.fromOffset(198, 13) })
	ajuste(rNome, { Position = UDim2.fromOffset(252, 10), Size = UDim2.fromOffset(136, 28) })
	ajuste(rXp.Parent, { Position = UDim2.fromOffset(252, 46), Size = UDim2.fromOffset(200, 5) })
end
aplicarCompacto = function(on: boolean)
	for _, a in ajustes do
		local valores: { [string]: any } = if on then a.compacto else a.normal
		for k, v in valores do
			a.o[k] = v
		end
	end
end
reescalar()

-- ===== dados =====
-- 12345 -> "12.345"
local function fmt(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local partes = {}
	while #s > 3 do
		table.insert(partes, 1, string.sub(s, -3))
		s = string.sub(s, 1, -4)
	end
	table.insert(partes, 1, s)
	return (if n < 0 then "-" else "") .. table.concat(partes, ".")
end
local function tempo(seg: number): string
	seg = math.max(0, math.floor(seg))
	local d = seg // 86400
	local h = (seg % 86400) // 3600
	local m = (seg % 3600) // 60
	if d > 0 then
		return string.format("%dD %dH", d, h)
	elseif h > 0 then
		return string.format("%dH %02dM", h, m)
	end
	return string.format("%dM", m)
end

local function nomeMostrado(): string
	if RunService:IsStudio() then
		local d = workspace:GetAttribute("VT65DevNome")
		if type(d) == "string" and d ~= "" then
			return d
		end
	end
	return player.DisplayName
end

local function atualizarPerfil()
	local cr = player:GetAttribute("Credits")
	rCred.Text = if type(cr) == "number" then fmt(cr) else "–"
	local xp = player:GetAttribute("XP")
	local rn = player:GetAttribute("RankName")
	if type(xp) == "number" then
		local rank, inRank, need = Progression.progress(xp)
		rPosto.Text = if type(rn) == "string" then UiKit.upper(rn) else ("POSTO " .. rank)
		rNivel.Text = "POSTO " .. rank
		rXp.Size = UDim2.fromScale(if need > 0 then math.clamp(inRank / need, 0, 1) else 1, 1)
	else
		rPosto.Text = "–"
		rNivel.Text = ""
		rXp.Size = UDim2.fromScale(0, 1)
	end
	rGente.Text = tostring(#Players:GetPlayers())
	rNome.Text = UiKit.upper(nomeMostrado())
	local modo = ReplicatedStorage:GetAttribute("MatchMode")
	jogarModo.Text = string.format(
		"%s · %d %s NO SERVIDOR",
		UiKit.upper(if type(modo) == "string" then modo else "Warfare"),
		#Players:GetPlayers(),
		if #Players:GetPlayers() == 1 then "JOGADOR" else "JOGADORES"
	)
end
for _, a in { "Credits", "XP", "RankName" } do
	player:GetAttributeChangedSignal(a):Connect(atualizarPerfil)
end
Players.PlayerAdded:Connect(atualizarPerfil)
Players.PlayerRemoving:Connect(function()
	task.defer(atualizarPerfil)
end)
ReplicatedStorage:GetAttributeChangedSignal("MatchMode"):Connect(atualizarPerfil)
task.spawn(function()
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and type(url) == "string" then
		avatar.Image = url
	end
end)

-- passe e ordens (CampanhaCliente); sem o estado ainda, "carregando" (nunca uma conta vazia)
local function atualizarCampanha()
	local st = CampanhaCliente.get()
	if not st then
		pNivel.Text = "–"
		pEstado.Text = "carregando o passe…"
		oResumo.Text = "carregando as ordens…"
		for _, l in linhas do
			l.f.Visible = false
		end
		return
	end
	local s = st.season or {}
	pKick.Text = UiKit.upper(string.format("PASSE DE CAMPANHA · %s", tostring(s.name or "")))
	if s.active == false then
		pFim.Text = "TEMPORADA ENCERRADA"
	else
		pFim.Text = "TERMINA EM " .. tempo(CampanhaCliente.left(s.endsAt))
	end
	pNivel.Text = tostring(s.level or 0)
	local per = tonumber(s.starsPerLevel) or 1
	local inL = tonumber(s.starsInLevel) or 0
	local maxed = (tonumber(s.level) or 0) >= (tonumber(s.maxLevel) or math.huge)
	pEstrelas.Text = if maxed then "NÍVEL MÁXIMO" else string.format("★ %d / %d", inL, per)
	pFill.Size = UDim2.fromScale(if maxed then 1 else math.clamp(inL / math.max(per, 1), 0, 1), 1)
	pVet.Text = if s.veteran then "✓ VETERANO ATIVO" else "🔒 VETERANO BLOQUEADO"
	pVet.TextColor3 = if s.veteran then V.OLIVE_HI else V.DIM
	pVet.FontFace = F.BODY_B
	pEstado.Text = if s.veteran
		then "As duas trilhas valem para você."
		else "A trilha grátis vale para todos; a Veterano, com o passe."
	tagDe(itPasse, if s.level then "NÍVEL " .. tostring(s.level) else "", V.AMBAR, true)
	-- ordens
	local ms = st.missions or {}
	oNovas.Text = "NOVAS EM " .. tempo(CampanhaCliente.left(ms.dailyResetAt))
	local feitas, total = 0, 0
	for i, l in linhas do
		local m = (ms.daily or {})[i]
		l.f.Visible = m ~= nil
		if m then
			total += 1
			local done = m.done == true
			if done then
				feitas += 1
			end
			local goal = math.max(tonumber(m.goal) or 1, 1)
			-- D-216: o texto da ordem é um modelo ("Fazer %d abates"); em caixa alta o %d virava %D e
			-- aparecia na tela. Sem caixa alta, a tradução acha o modelo
			local modelo = tostring(m.text or "")
			local okTexto, textoOrdem = pcall(string.format, modelo, goal)
			l.t.Text = if okTexto then textoOrdem else modelo
			l.t.TextColor3 = if done then V.DIM else V.TEXT
			l.img.Image = ArteCatalogo.ordem(m.id)
			l.img.ImageTransparency = if m.claimed == true then 0.5 else 0
			local prog = math.min(tonumber(m.progress) or 0, goal)
			-- D-227: concluída, mas ainda sem receber, chama; recebida apaga
			local receber = done and m.claimed ~= true
			l.n.Text = if m.claimed == true
				then "✓ RECEBIDA"
				elseif receber then "RECEBER ›"
				else string.format("%s / %s", fmt(prog), fmt(goal))
			l.n.FontFace = if done then F.BODY_B else F.TITLE_MED
			l.n.TextColor3 = if receber then V.AMBAR elseif done then V.OLIVE_HI else V.DIM
			l.fill.Size = UDim2.fromScale(prog / goal, 1)
			l.fill.BackgroundColor3 = if done then V.OLIVE_HI else V.KHAKI
			local rw = m.reward or {}
			l.r.Text = if (tonumber(rw.xp) or 0) > 0
				then string.format("+%s XP", fmt(rw.xp))
				elseif (tonumber(rw.stars) or 0) > 0 then string.format("+%d ★", rw.stars)
				else ""
		end
	end
	oResumo.Text = string.format("%d DE %d FEITAS HOJE", feitas, total)
	tagDe(itMissoes, if total > 0 then string.format("%d/%d", feitas, total) else "", V.PANEL_3)
end
CampanhaCliente.Changed:Connect(function()
	if open then
		atualizarCampanha()
	end
end)

-- recompensa diária (Daily_Get / Daily_State)
local daily: { [string]: any }? = nil
local dailyAt = 0
local function atualizarDiaria()
	local d = daily
	if not (d and d.ready) then
		dSub.Text = "carregando…"
		for _, p in pips do
			p.BackgroundColor3 = V.PANEL_3
		end
		return
	end
	local day = tonumber(d.day) or 1
	local left = (tonumber(d.resetIn) or 0) - (os.clock() - dailyAt)
	if d.canClaim then
		dSub.Text = string.format("DIA %d DE 7 · PRONTA PARA RECEBER", day)
		dSub.TextColor3 = V.AMBAR
	else
		dSub.Text = string.format("DIA %d DE 7 · PRÓXIMA EM %s", day, tempo(left))
		dSub.TextColor3 = V.DIM
	end
	for i, p in pips do
		local feito = i < day or (i == day and d.claimedToday == true)
		p.BackgroundColor3 = if feito then V.AMBAR elseif i == day then V.KHAKI else V.PANEL_3
		p.BackgroundTransparency = if i == day and not feito then 0.3 else 0
	end
end
task.spawn(function()
	Net.event("Daily_State").OnClientEvent:Connect(function(s: any)
		if type(s) == "table" then
			daily, dailyAt = s, os.clock()
			if open then
				atualizarDiaria()
			end
		end
	end)
end)
local function pedirDiaria()
	task.spawn(function()
		local ok, s = pcall(function()
			return Net.func("Daily_Get"):InvokeServer()
		end)
		if ok and type(s) == "table" then
			daily, dailyAt = s, os.clock()
			atualizarDiaria()
		end
	end)
end

-- destaque: a loja (o banner da vitrine) e o passe (a capa do bambuzal); troca a cada 7 s
type Slide = { kick: string, titulo: string, desc: string, imagem: string, acao: () -> () }
local SLIDES: { Slide } = {
	{
		kick = "LOJA · UNIFORMES DE 1965",
		titulo = "FARDAS E ACABAMENTOS",
		desc = "Cosméticos: não mudam o combate.",
		imagem = img(LOJA_IMG.destaque),
		acao = function()
			Bus.fire("shop_open")
		end,
	},
	{
		kick = "PASSE DE CAMPANHA",
		titulo = "TRILHA VETERANO",
		desc = "O que você já alcançou chega na compra.",
		imagem = img(CAPA.bambu),
		acao = function()
			Bus.fire("passe_open")
		end,
	},
}
local slide = 1
local slideT = 0
for i = 1, #SLIDES do
	local p = Instance.new("Frame")
	p.Name = "Ponto" .. i
	p.AnchorPoint = Vector2.new(1, 1)
	p.Position = UDim2.new(1, -18 - (#SLIDES - i) * 20, 1, -16)
	p.Size = UDim2.fromOffset(12, 12)
	p.BackgroundColor3 = V.TEXT
	p.BorderSizePixel = 0
	p.Rotation = 45
	p.Parent = destaque
	table.insert(dPontos, p)
end
local function mostrarSlide(i: number, anim: boolean)
	slide = (i - 1) % #SLIDES + 1
	slideT = os.clock()
	local s = SLIDES[slide]
	dKick.Text = s.kick
	dTitulo.Text = s.titulo
	dDesc.Text = s.desc
	dImg.Image = s.imagem
	for j, p in dPontos do
		p.BackgroundColor3 = if j == slide then V.AMBAR else V.TEXT
		p.BackgroundTransparency = if j == slide then 0 else 0.55
	end
	if anim then
		dImg.ImageTransparency = 0.6
		UiKit.tween(dImg, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { ImageTransparency = 0 })
	end
end
mostrarSlide(1, false)

-- ===== foco e transições =====
local capaAtual = ""
local capaFrente = capaA
-- D-217: a imagem de cada entrada (a do ARMÁRIO é a capa do jogo sem o título, resolvida pelo servidor)
local function urlCapa(id: string): string
	if id == "loja" then
		return img(LOJA_IMG.destaque)
	elseif id == "armario" then
		local v = ReplicatedStorage:GetAttribute("Img_menu_armario")
		return if type(v) == "number" and v ~= 0 then string.format("rbxassetid://%d", v) else img(CAPA.posto)
	end
	return if id ~= "" then img(CAPA[id]) else ""
end

-- D-217 (dono: "a cada negocio q vc passa em cima tem uma imagem diferente como no jogar" e "deixe os
-- botoes do passe e da loja chamativos"): cada entrada tem a sua imagem, sempre à vista (no celular não
-- existe passar o dedo em cima), apagada à esquerda para o texto ler e acesa à direita; no foco ela
-- acende e cresce. LOJA e PASSE têm a faixa de cor cheia, o texto contrastado e o brilho passando.
local DESTAQUE = {
	LOJA = { cor = V.AMBAR, texto = V.AMBAR_TEXTO, atraso = 0.6 },
	PASSE = { cor = V.RED_HI, texto = V.TEXT, atraso = 3.4 },
} :: { [string]: { cor: Color3, texto: Color3, atraso: number } }
-- D-222 (dono: "quero que as imagens apareçam no lobby somente quando passar por cima dos botões")
local IMG_REPOUSO, IMG_FOCO = 1, 0
type Fundo = { imagem: ImageLabel, cor: Frame? }
local fundos: { [Item]: Fundo } = {}
for _, it in itens do
	it.b.ClipsDescendants = true
	UiKit.corner(it.b, 3)
	local im = Instance.new("ImageLabel")
	im.Name = "Fundo"
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.Size = UDim2.fromScale(1, 1)
	im.ScaleType = Enum.ScaleType.Crop
	im.Image = urlCapa(it.capa)
	im.ImageTransparency = IMG_REPOUSO
	im.ZIndex = -2
	im.Parent = it.b
	local d = DESTAQUE[it.id]
	local g = Instance.new("UIGradient")
	g.Transparency = if d
		then NumberSequence.new(0)
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.82),
			NumberSequenceKeypoint.new(1, 0.05),
		})
	g.Parent = im
	local cor: Frame? = nil
	if d then
		local c = Instance.new("Frame")
		c.Name = "Cor"
		c.BackgroundColor3 = d.cor
		c.BorderSizePixel = 0
		c.Size = UDim2.fromScale(1, 1)
		c.ZIndex = -1
		c.Parent = it.b
		local cg = Instance.new("UIGradient")
		cg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.08),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		cg.Parent = c
		cor = c
		it.label.TextColor3 = d.texto
		UiKit.edge(it.b, d.cor, 2, 0)
		UiEfeitos.varre(it.b, 4.5, nil, 5, d.atraso)
	end
	fundos[it] = { imagem = im, cor = cor }
end
-- a imagem do ARMÁRIO chega do servidor depois de abrir
ReplicatedStorage:GetAttributeChangedSignal("Img_menu_armario"):Connect(function()
	for it, f in fundos do
		if it.capa == "armario" then
			f.imagem.Image = urlCapa("armario")
		end
	end
end)

local function trocarCapa(id: string)
	local url = urlCapa(id)
	if url == "" or url == capaAtual then
		return
	end
	capaAtual = url
	-- fusão: a de trás recebe a nova e aparece por cima da da frente (camadas fixas: as duas capas
	-- em 1 e 2, a sombra em 3, o botão e os textos em 4)
	local tras = if capaFrente == capaA then capaB else capaA
	capaFrente.ZIndex = 1
	tras.ZIndex = 2
	tras.Image = url
	tras.ImageTransparency = 1
	tras.Size = UDim2.fromScale(1.06, 1.06)
	UiKit.tween(tras, FADE, { ImageTransparency = 0 })
	if not Estilo.reduzMovimento() then
		-- o zoom lento da nova (Ken Burns); a velha para onde estava
		TweenService:Create(tras, TweenInfo.new(9, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1.14, 1.14) })
			:Play()
	end
	capaFrente = tras
end
capaSombra.ZIndex = 3
-- D-222 (dono: "quero que as imagens apareçam no lobby somente quando passar por cima dos botões"): um
-- véu cobre a capa do JOGAR em repouso e sai com o foco (mouse, toque ou controle)
local capaVeu = Instance.new("Frame")
capaVeu.Name = "CapaVeu"
capaVeu.BackgroundColor3 = V.PANEL
capaVeu.BackgroundTransparency = 0.04
capaVeu.BorderSizePixel = 0
capaVeu.Size = UDim2.fromScale(1, 1)
capaVeu.ZIndex = 3
capaVeu.Parent = card
local function mostraCapa(on: boolean)
	UiKit.tween(capaVeu, UiKit.SOFT, { BackgroundTransparency = if on then 1 else 0.04 })
end
for _, o in { jogarBox, jogarSub, jogarModo } :: { GuiObject } do
	o.ZIndex = 4
end

local cardHot = false
local function pintarCard(on: boolean)
	cardHot = on
	UiKit.tween(jogarBox, UiKit.QUICK, { BackgroundColor3 = if on then V.AMBAR_HI else V.AMBAR })
	UiKit.tween(cardEdge, UiKit.QUICK, { Color = if on then V.AMBAR else V.LINE, Transparency = if on then 0 else 0.4 })
	UiKit.tween(jogarSeta, UiKit.QUICK, { Position = UDim2.new(1, if on then -10 else -18, 0, -2) })
end

local function pintarItem(it: Item, on: boolean)
	UiKit.tween(it.bar, UiKit.QUICK, { Size = UDim2.new(0, if on then 5 else 0, 0.72, 0) })
	UiKit.tween(it.linha, UiKit.QUICK, { Position = UDim2.fromOffset(if on then 18 else 0, 0) })
	local d = DESTAQUE[it.id]
	if not d then
		UiKit.tween(it.label, UiKit.QUICK, { TextColor3 = if on then V.AMBAR_HI else V.TEXT })
	end
	-- D-217: a imagem da entrada acende e cresce um pouco no foco
	local f = fundos[it]
	if f then
		UiKit.tween(f.imagem, UiKit.SOFT, {
			ImageTransparency = if on then IMG_FOCO else IMG_REPOUSO,
			Size = UDim2.fromScale(if on then 1.08 else 1, if on then 1.08 else 1),
		})
	end
end

local DESC_JOGAR = "Entre na partida: escolha o lado, o squad, o papel e onde nascer."
local voltaGen = 0
-- foco num item (nil = o JOGAR): realce, descrição, capa e enquadramento do soldado
local function focar(it: Item?)
	voltaGen += 1
	if focoAtual == it and (it ~= nil or cardHot) then
		return
	end
	local antes = focoAtual
	if antes then
		pintarItem(antes, false)
	end
	focoAtual = it
	mostraCapa(it == nil) -- a capa do JOGAR só com o foco nele; cada entrada acende a própria imagem
	if it then
		pintarCard(false)
		pintarItem(it, true)
		descr.Text = it.desc
		trocarCapa(it.capa)
		LobbyPalco.enquadrar(it.quadro)
	else
		pintarCard(true)
		descr.Text = DESC_JOGAR
		trocarCapa("arrozal")
		LobbyPalco.enquadrar("jogar")
	end
	if not Estilo.reduzMovimento() then
		descr.TextTransparency = 0.6
		UiKit.tween(descr, UiKit.QUICK, { TextTransparency = 0 })
	end
end
-- o mouse saiu de tudo: depois de um instante volta ao JOGAR, sem realce, e ao quadro de início
local function soltar()
	voltaGen += 1
	local g = voltaGen
	task.delay(0.5, function()
		if g == voltaGen and open and GuiService.SelectedObject == nil then
			local antes = focoAtual
			if antes then
				pintarItem(antes, false)
			end
			focoAtual = nil
			pintarCard(false)
			mostraCapa(false)
			descr.Text = DESC_JOGAR
			trocarCapa("arrozal")
			LobbyPalco.enquadrar("inicio")
		end
	end)
end

-- ===== ações =====
local function abrirTela(it: Item)
	if livre() then
		it.acao()
	end
end

local function hoverDe(it: Item?): (boolean) -> ()
	return function(on: boolean)
		if on then
			focar(it)
		else
			soltar()
		end
	end
end

for _, it in itens do
	local h = hoverDe(it)
	UiKit.bind(it.b, function()
		abrirTela(it)
	end, h)
	it.b.MouseEnter:Connect(function()
		h(true)
	end)
	it.b.MouseLeave:Connect(function()
		h(false)
	end)
	it.b.SelectionGained:Connect(function()
		h(true)
	end)
	it.b.SelectionLost:Connect(function()
		h(false)
	end)
	-- apertar: afunda um pouco
	it.b.MouseButton1Down:Connect(function()
		UiKit.tween(it.label, UiKit.QUICK, { TextTransparency = 0.25 })
	end)
	it.b.MouseButton1Up:Connect(function()
		UiKit.tween(it.label, UiKit.QUICK, { TextTransparency = 0 })
	end)
end
do
	local h = hoverDe(nil)
	card.MouseEnter:Connect(function()
		h(true)
	end)
	card.MouseLeave:Connect(function()
		h(false)
	end)
	card.SelectionGained:Connect(function()
		h(true)
	end)
	card.SelectionLost:Connect(function()
		h(false)
	end)
	local esc = Instance.new("UIScale")
	esc.Parent = jogarBox
	card.MouseButton1Down:Connect(function()
		UiKit.tween(esc, UiKit.QUICK, { Scale = 0.96 })
	end)
	card.MouseButton1Up:Connect(function()
		UiKit.tween(esc, UiKit.QUICK, { Scale = 1 })
	end)
	card.MouseLeave:Connect(function()
		UiKit.tween(esc, UiKit.QUICK, { Scale = 1 })
	end)
end
UiKit.principal(card)
-- realce dos cartões da direita: a borda acende em âmbar (e a imagem do destaque cresce um pouco)
local function realceCartao(b: GuiButton, edge: UIStroke?, txt: TextLabel?)
	local function set(on: boolean)
		if edge then
			UiKit.tween(
				edge,
				UiKit.QUICK,
				{ Color = if on then V.AMBAR else V.LINE, Transparency = if on then 0 else 0.45 }
			)
		end
		if txt then
			UiKit.tween(txt, UiKit.QUICK, { TextColor3 = if on then V.AMBAR_HI else V.TEXT })
		end
		if b == destaque then
			UiKit.tween(dImg, UiKit.SOFT, { Size = UDim2.fromScale(if on then 1.05 else 1, if on then 1.05 else 1) })
		end
	end
	b.MouseEnter:Connect(function()
		set(true)
	end)
	b.MouseLeave:Connect(function()
		set(false)
	end)
	b.SelectionGained:Connect(function()
		set(true)
	end)
	b.SelectionLost:Connect(function()
		set(false)
	end)
end
dImg.AnchorPoint = Vector2.new(0.5, 0.5)
dImg.Position = UDim2.fromScale(0.5, 0.5)
realceCartao(passeCard, passeCard:FindFirstChildOfClass("UIStroke"), pVer)
realceCartao(oTodas, nil, oVer)
realceCartao(destaque, destaque:FindFirstChildOfClass("UIStroke"), nil)
UiKit.bind(passeCard, function()
	if livre() then
		Bus.fire("passe_open")
	end
end, function(on: boolean)
	if on then
		LobbyPalco.enquadrar("passe")
	end
end)
passeCard.SelectionGained:Connect(function()
	LobbyPalco.enquadrar("passe")
end)
UiKit.bind(oTodas, function()
	if livre() then
		Bus.fire("missoes_open")
	end
end)
UiKit.bind(destaque, function()
	if livre() then
		SLIDES[slide].acao()
	end
end)

-- navegação do controle: a coluna da esquerda em volta (↑ ↓); → vai para o resumo, ← volta
local ordem: { GuiObject } = { card }
for _, it in itens do
	table.insert(ordem, it.b)
end
for i, o in ordem do
	o.NextSelectionUp = ordem[if i == 1 then #ordem else i - 1]
	o.NextSelectionDown = ordem[if i == #ordem then 1 else i + 1]
	o.NextSelectionLeft = o
	o.NextSelectionRight = passeCard
end
passeCard.NextSelectionLeft = card
passeCard.NextSelectionDown = oTodas
passeCard.NextSelectionUp = destaque
oTodas.NextSelectionLeft = card
oTodas.NextSelectionUp = passeCard
oTodas.NextSelectionDown = destaque
destaque.NextSelectionLeft = card
destaque.NextSelectionUp = oTodas
destaque.NextSelectionDown = passeCard
for _, o in { passeCard, oTodas, destaque } do
	o.NextSelectionRight = o
end

-- dicas pelo aparelho
local function refreshHint()
	chips.clear()
	if Input.isGamepad() then
		chips.add(UiKit.padImage(Enum.KeyCode.ButtonA), nil, "A", "Escolher")
		chips.add(UiKit.padImage(Enum.KeyCode.DPadUp), UiKit.padImage(Enum.KeyCode.DPadDown), "↑↓", "Andar")
		local img0 = UiKit.padImage(Enum.KeyCode.ButtonA)
		jogarTecla.Image = img0 or ""
		jogarTecla.Visible = img0 ~= nil
	elseif Input.touchActive() then
		jogarTecla.Visible = false
	else
		chips.add(nil, nil, "ENTER", "Escolher")
		chips.add(nil, nil, "↑ ↓", "Andar")
		jogarTecla.Visible = false
	end
end
refreshHint()

-- D-186: o que a tela de entrada ainda carrega em segundo plano (atributo "VT65Fundo" do jogador)
local function refreshBgLoad()
	local v = player:GetAttribute("VT65Fundo")
	bgLoad.Text = if type(v) == "string" then v else ""
end
player:GetAttributeChangedSignal("VT65Fundo"):Connect(refreshBgLoad)
refreshBgLoad()

-- ===== sol de fim de tarde =====
local menuC: number?, menuL: number? = nil, nil
local savedC, savedL = 0, 0
local function fitSun()
	if menuC then
		return
	end
	local az, el = SolarPosition.compute(SUN.year, SUN.month, SUN.day, MENU_HOUR, SUN.tz, SUN.lat, SUN.lon)
	local tx, ty, tz = SolarPosition.direction(az, el)
	local c0, l0 = Lighting.ClockTime, Lighting.GeographicLatitude
	local c, l = SolarPosition.fit(tx, ty, tz, function(c1: number, l1: number)
		Lighting.ClockTime = c1
		Lighting.GeographicLatitude = l1
		local d = Lighting:GetSunDirection()
		return d.X, d.Y, d.Z
	end, 17.5, 15)
	Lighting.ClockTime, Lighting.GeographicLatitude = c0, l0
	menuC, menuL = c, l
end
-- o servidor acerta o sol a cada 15 s (LightingService): enquanto o menu está aberto, vale o daqui
local function holdSun()
	local c, l = menuC, menuL
	if c and l and math.abs(Lighting.ClockTime - c) > 0.01 then
		Lighting.ClockTime = c
		Lighting.GeographicLatitude = l
	end
end

-- ===== abrir e fechar =====
local savedFov: number? = nil
local blocos: { CanvasGroup } = { esq, dir, rodape, dicasB }
local function entrada()
	local parado = Estilo.reduzMovimento()
	for i, g in blocos do
		local base = g:GetAttribute("Base") :: UDim2
		g.GroupTransparency = 1
		local dx = if g == dir then 40 elseif g == esq then -40 else 0
		local dy = if g == rodape or g == dicasB then 24 else 0
		g.Position = base + UDim2.fromOffset(dx, dy)
		task.delay(if parado then 0 else 0.25 + 0.12 * (i - 1), function()
			if open then
				UiKit.tween(g, TweenInfo.new(0.55, Enum.EasingStyle.Quint), { GroupTransparency = 0, Position = base })
			end
		end)
	end
	-- os itens da esquerda chegam um depois do outro
	local lista: { GuiObject } = { marca, card }
	for _, it in itens do
		table.insert(lista, it.b)
	end
	for i, o in lista do
		local p = o.Position
		local base = o:GetAttribute("BaseItem")
		if typeof(base) ~= "UDim2" then
			o:SetAttribute("BaseItem", p)
			base = p
		end
		local b0 = base :: UDim2
		if not parado then
			o.Position = b0 + UDim2.fromOffset(-36, 0)
			task.delay(0.3 + 0.045 * i, function()
				if open then
					UiKit.tween(o, TweenInfo.new(0.5, Enum.EasingStyle.Quint), { Position = b0 })
				end
			end)
		else
			o.Position = b0
		end
	end
	for _, s in { sombraEsq, sombraBaixo, sombraCima } do
		s.BackgroundTransparency = 1
		UiKit.tween(s, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
	end
end

local function focusPlay()
	if open and Input.isGamepad() and not ComoJogar.isOpen() then
		GuiService.SelectedObject = card
	end
end

local cobertoAntes = false
local function setOpen(on: boolean)
	if on == open then
		return
	end
	open = on
	player:SetAttribute("MenuPrincipal", on)
	local cam = workspace.CurrentCamera
	if on then
		opened = true
		busy = false
		cobertoAntes = false
		if cam then
			savedFov = cam.FieldOfView
		end
		savedC, savedL = Lighting.ClockTime, Lighting.GeographicLatitude
		fitSun()
		holdSun()
		ajustarAlvo()
		LobbyPalco.enquadrar("inicio")
		LobbyPalco.abrir()
		Input.openMenu()
		atualizarPerfil()
		atualizarCampanha()
		atualizarDiaria()
		pedirDiaria()
		CampanhaCliente.refresh()
		focoAtual = nil
		for _, it in itens do
			pintarItem(it, false)
		end
		pintarCard(false)
		descr.Text = DESC_JOGAR
		capaAtual = ""
		trocarCapa("arrozal")
		capaVeu.BackgroundTransparency = 0.04
		cortina.BackgroundTransparency = 1
		fundo.Enabled = true
		gui.Enabled = true
		entrada()
		task.delay(0.6, focusPlay)
	else
		LobbyPalco.fechar()
		-- a hora da partida volta (o servidor acerta de novo em até 15 s)
		local mc = menuC
		if mc and math.abs(Lighting.ClockTime - mc) <= 0.01 then
			Lighting.ClockTime, Lighting.GeographicLatitude = savedC, savedL
		end
		if cam then
			cam.CameraType = Enum.CameraType.Custom -- a mesa (LobbyScene) ou o spawn assumem daqui
			cam.FieldOfView = savedFov or 70
		end
		UiKit.release(gui)
		gui.Enabled = false
		fundo.Enabled = false
		Input.closeMenu()
	end
end

-- D-222: o lobby não tem mais soldado para girar
LobbyPalco.podeGirar = function(): boolean
	return false
end

-- JOGAR: a câmera entra no soldado, o menu esmaece num escuro quente e a mesa do lobby aparece para
-- escolher lado, squad, papel e ponto (lote 66: o JOGAR não põe direto em campo)
local function play()
	if busy or not open then
		return
	end
	busy = true
	LobbyPalco.enquadrar("arsenal")
	for _, g in blocos do
		UiKit.tween(g, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { GroupTransparency = 1 })
	end
	local fade = UiKit.tween(cortina, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
	fade.Completed:Wait()
	setOpen(false)
end
UiKit.bind(card, function()
	task.spawn(play)
end, function(on: boolean)
	if on then
		focar(nil)
	else
		soltar()
	end
end)

-- outra tela por cima (loja, passe, missões, cartão, configurações, tutorial): o menu esmaece e o
-- soldado vai para o enquadramento dela; ao fechar, volta
local quadroDaTela: { [string]: string } = {
	loja = "loja",
	passe = "passe",
	missoes = "missoes",
	cartao = "perfil",
	menu = "config",
}
RunService.Heartbeat:Connect(function()
	if not open then
		return
	end
	holdSun()
	local topo = UiKit.top()
	local coberto = (topo ~= nil and topo ~= "confirma") or ComoJogar.isOpen()
	if coberto ~= cobertoAntes then
		cobertoAntes = coberto
		for _, g in blocos do
			UiKit.tween(g, FADE, { GroupTransparency = if coberto then 1 else 0 })
		end
		for _, s in { sombraEsq, sombraBaixo } do
			UiKit.tween(s, FADE, { BackgroundTransparency = if coberto then 0.55 else 0 })
		end
		if coberto then
			LobbyPalco.enquadrar(quadroDaTela[topo or ""] or (if ComoJogar.isOpen() then "tutorial" else "inicio"))
		else
			LobbyPalco.enquadrar(if focoAtual then (focoAtual :: Item).quadro else "inicio")
			atualizarPerfil()
			atualizarCampanha()
		end
	end
	-- o foco volta para o JOGAR quando outra tela fecha
	if not coberto and Input.isGamepad() and GuiService.SelectedObject == nil then
		focusPlay()
	end
	-- carrossel do destaque
	if not coberto and not Estilo.reduzMovimento() and os.clock() - slideT > 7 then
		mostrarSlide(slide + 1, true)
	end
end)
task.spawn(function()
	while true do
		task.wait(20)
		if open then
			atualizarDiaria()
			atualizarCampanha()
		end
	end
end)
Input.DeviceChanged:Connect(function()
	refreshHint()
	focusPlay()
end)

-- ===== quando abrir =====
-- Uma vez por sessão: quando a tela de entrada marca "Pronto" (ou some), sem corpo em campo.
local function inField(): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local w0 = os.clock()
	while os.clock() - w0 < 300 do
		local lg = pg:FindFirstChild("VT65Loading")
		if lg == nil or not lg:IsA("ScreenGui") or lg:GetAttribute("Pronto") == true or not lg.Enabled then
			break
		end
		task.wait(0.2)
	end
	if not opened and not inField() then
		setOpen(true)
		-- D-186: as CONFIGURAÇÕES da tela de entrada (atributo "AbrirConfig"): a aba abre por cima do
		-- menu, e a recompensa diária espera ela fechar
		local lg = pg:FindFirstChild("VT65Loading")
		local settings = lg ~= nil and lg:GetAttribute("AbrirConfig") == true
		if settings then
			task.delay(0.6, function()
				if open then
					Bus.fire("menu_open", 1) -- aba Configurações
				end
			end)
		end
		-- lote 16 (D-130, dono: "a recompensa diária deve aparecer toda vez que entro no jogo"): a
		-- caderneta abre por cima do menu, depois que ele assenta (Controllers/DiariaEntrada.client)
		task.delay(1.6, function()
			while settings and open and UiKit.top() ~= nil do
				task.wait(0.3)
			end
			if open then
				Bus.fire("diaria_entrada")
			end
		end)
	end
end)

-- lote 8 (D-120): o menu do jogo não tem mais loja nem passe; o "Menu principal" de lá abre este de
-- novo (em campo, o JOGAR só fecha: o Jogar agora não faz nada com o soldado vivo)
Bus.on("menu_principal_open", function()
	setOpen(true)
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "menu_principal" then
			setOpen(true)
		end
	end)
	workspace:GetAttributeChangedSignal("VT65DevNome"):Connect(atualizarPerfil)
end
