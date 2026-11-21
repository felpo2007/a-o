--!strict
-- Loja (menu do jogo → Loja, tecla L ou a caixa de munição da mesa do lobby): passes cosméticos,
-- apoio, Premium, assinatura e o armário. Estilo novo (2026-11-11: o dono não gostou do papel
-- datilografado): painel escuro sólido, as duas abas grandes em Oswald no alto, cada item numa linha
-- escura com o nome em Oswald, a descrição em Arimo e o preço num botão oliva; o que já é seu leva a
-- etiqueta "✔ SEU".
-- Navegável no controle: abre com foco no 1º item, A compra/equipa, B fecha (Parte 12.5). No lobby,
-- o cursor virtual do controle também clica aqui (todo botão passa por UiKit.bind).
-- Os preços são lidos ao vivo (GetProductInfoAsync) para o Managed Pricing do Roblox valer.
-- Ao fechar avisa o lobby (Bus "shop_closed"), que devolve a câmera para a mesa.
-- A Intendência (Progresso.client) abre junto, à esquerda: a pasta fica à direita dela e encolhe
-- para não cobrir o painel (antes, numa tela de 1280 px, as duas se sobrepunham).
-- Só no Studio: workspace:SetAttribute("VT65DevTela", "loja") abre a loja.
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Commerce = require(ReplicatedStorage.Shared.Commerce)
local JogarAgora = require(ReplicatedStorage.Shared.JogarAgora) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Roles = require(ReplicatedStorage.Shared.Roles) :: any
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Bus = require(script.Parent.Bus)
local CampanhaCliente = require(script.Parent.CampanhaCliente)
local Input = require(script.Parent.Input)
local LobbyPalco = require(script.Parent.LobbyPalco)
local RodaArte = require(script.Parent.RodaArte)
local SoldierPreview = require(script.Parent.SoldierPreview)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end
-- D-207 (referências do dono: a loja ocupa a esquerda e o soldado fica à direita, na luz): o painel
-- cresceu de 720 x 620 para 1120 x 900 e saiu do meio para a esquerda; no lobby o palco (LobbyPalco)
-- põe o soldado do jogador à direita dele
local W, H = px(1120, 1490), px(900, 1200)
local X0 = px(48, 64) -- margem da esquerda
-- abas na mesma ficha (D-93: antes eram duas telas, uma por cima da outra). Plano de volta diária
-- (2026-11-12): MERCADO (mercado do dia, reforços, Pacote de Recruta, créditos e o passe) e
-- VANTAGENS (as vantagens compradas, com o número exato e o teto). D-207 (§9: "Destaques, Itens,
-- Conjuntos, Caixas e Códigos"): a vitrine virou DESTAQUES, o mercado vem logo depois, e entrou
-- CÓDIGOS
local TABS = {
	{ id = "loja", name = "DESTAQUES" },
	-- D-211 (dono: "coloque o botão do armário no lobby"; "cadê a M16 para os americanos"): a arma
	-- principal de cada papel e o que você já tem para vestir
	{ id = "armario", name = "ARMÁRIO" },
	{ id = "mercado", name = "MERCADO" },
	-- D-173: caixas de suprimentos (Controllers/CaixasTela.client desenha dentro do host dela)
	{ id = "caixas", name = "CAIXAS" },
	-- D-175: ARQUIVO MILITAR STARLITE (Controllers/ArquivoTela.client desenha dentro do host dela)
	{ id = "arquivo", name = "ARQUIVO" },
	{ id = "vantagens", name = "VANTAGENS" },
	{ id = "intendencia", name = "INTENDÊNCIA" },
	{ id = "codigos", name = "CÓDIGOS" },
}
-- D-124 (lote 11, "deixe a loja atrativa"): a loja abre na vitrine (era a intendência, uma lista de
-- equipamento com botões bege, a primeira coisa que se via)
local tab = "loja"
local function tabIndex(id: string): number?
	for i, d in TABS do
		if d.id == id then
			return i
		end
	end
	return nil
end

-- Categoria de um passe ou produto do Commerce (os itens novos do plano entram no Commerce com ID 0
-- até o coordenador criá-los no Roblox). Pelo `kind`/`grants` e, de reserva, pelo nome da chave.
local function classify(key: string, kind: string?): string
	local k = string.upper(key)
	local g = string.lower(kind or "")
	local function has(...: string): boolean
		for _, w in { ... } do
			if string.find(k, w, 1, true) or string.find(g, string.lower(w), 1, true) then
				return true
			end
		end
		return false
	end
	-- a ordem importa: o pacote das 7 tem PERK no nome (PASS_PERK_ALL, kind "perk_bundle") e o
	-- pular nível tem SEASON (PRODUCT_SEASON_SKIP, grants "season_skip")
	if has("COMBAT") or g == "perk_bundle" or string.find(k, "PERK_ALL", 1, true) then
		return "combatente"
	elseif g == "season_skip" or has("SKIP") then
		return "skip"
	elseif g == "perk" or g == "vantagem" or has("PERK", "VANT") then
		return "perk"
	elseif has("SEASON", "TEMPORADA") then
		return "season"
	elseif has("LEVEL", "NIVEL") then
		return "skip"
	elseif has("BOOST", "REFORCO", "DOUBLE") then
		return "boost"
	elseif has("CREDIT") then
		return "credits"
	elseif has("RECRUIT", "RECRUTA") then
		return "recruit"
	end
	return "other"
end

local gui = Instance.new("ScreenGui")
gui.Name = "VT65Shop"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 30
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
end)
gui.Parent = player:WaitForChild("PlayerGui")

local V = UiKit.V
local F = UiKit.F
-- D-207: o fundo. No lobby, só o escuro da esquerda (o palco e o soldado aparecem à direita, como nas
-- referências); fora dele (em campo, tecla L), um véu na tela inteira.
local fundo = Instance.new("Frame")
fundo.Name = "Fundo"
fundo.Position = UDim2.fromOffset(-200, -200)
fundo.Size = UDim2.new(1, 400, 1, 400)
fundo.BackgroundColor3 = Color3.fromRGB(5, 5, 4)
fundo.BackgroundTransparency = 1
fundo.BorderSizePixel = 0
fundo.Parent = gui
local fundoGrad = Instance.new("UIGradient")
fundoGrad.Parent = fundo
local function pintarFundo(noPalco: boolean)
	fundo.BackgroundTransparency = 0
	fundoGrad.Transparency = if noPalco
		then NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(0.72, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		})
		else NumberSequence.new(0.25)
end

-- o painel, à esquerda; UiKit.fit encolhe numa janela pequena (D-93: numa janela de 671 x 565 o
-- FECHAR ficava em y = −28)
local folder = Instance.new("Frame")
folder.Name = "Painel"
folder.AnchorPoint = Vector2.new(0, 0.5)
folder.Position = UDim2.new(0, X0, 0.5, 0)
folder.Size = UDim2.fromOffset(W, H)
folder.BackgroundColor3 = V.PANEL
folder.BackgroundTransparency = UiKit.Estilo.fundo(0.12)
folder.BorderSizePixel = 0
folder.Active = true -- tapa a mesa do lobby atrás (o clique não atravessa)
folder.Parent = gui
UiKit.corner(folder, 4)
UiKit.edge(folder, V.LINE, 1, 0.35)
-- a margem da esquerda entra na conta (no passe, sem ela, o FECHAR saía da tela à direita)
local fit = UiKit.fit(gui, folder, W + X0, H, 12)
Acabamento.sombra(folder, 24, Vector2.new(0, 9), 0.6)
do -- filete âmbar no alto (D-207; era oliva): o acento do cabeçalho
	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = V.AMBAR
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, px(120, 160), 0, px(3, 4))
	accent.Parent = folder
	UiKit.corner(accent, 2)
end

-- D-207: cabeçalho como nas referências: o título, uma linha do que se vende e, à direita, o saldo
local PADX = px(24, 32)
local HEAD_H = px(80, 106)
do
	local t = UiKit.title(folder, "LOJA", px(46, 62))
	t.Name = "Titulo"
	t.Position = UDim2.fromOffset(PADX, px(14, 18))
	t.Size = UDim2.fromOffset(px(300, 400), px(48, 64))
	local s = UiKit.kicker(folder, "VISUAIS, CAIXAS E APOIO · AS VANTAGENS TÊM TETO", px(14, 20), V.DIM)
	s.Name = "Subtitulo"
	s.Position = UDim2.fromOffset(PADX + 2, px(62, 82))
	s.Size = UDim2.fromOffset(px(620, 820), px(20, 28))
end
-- o saldo de créditos (o "+" leva ao mercado, onde se compram)
local saldo = Instance.new("Frame")
saldo.Name = "Saldo"
saldo.AnchorPoint = Vector2.new(1, 0)
saldo.Position = UDim2.new(1, -(PADX + px(130, 172)), 0, px(22, 30))
saldo.Size = UDim2.fromOffset(px(200, 266), px(38, 52))
saldo.BackgroundColor3 = V.PANEL_2
saldo.BorderSizePixel = 0
saldo.Parent = folder
UiKit.corner(saldo, 4)
UiKit.edge(saldo, V.AMBAR, 1, 0.3)
local saldoTxt = UiKit.text2(saldo, "", px(20, 28), V.TEXT, F.TITLE)
saldoTxt.Position = UDim2.fromOffset(px(12, 16), 0)
saldoTxt.Size = UDim2.new(1, -px(56, 74), 1, 0)
local saldoMais = Instance.new("TextButton")
saldoMais.Name = "Mais"
saldoMais.AnchorPoint = Vector2.new(1, 0.5)
saldoMais.Position = UDim2.new(1, -px(5, 7), 0.5, 0)
saldoMais.Size = UDim2.fromOffset(px(30, 40), px(30, 40))
saldoMais.BackgroundColor3 = V.AMBAR
saldoMais.AutoButtonColor = false
saldoMais.FontFace = F.TITLE
saldoMais.TextSize = UiKit.text(px(22, 30))
saldoMais.TextColor3 = V.AMBAR_TEXTO
saldoMais.Text = "+"
saldoMais.Selectable = false
saldoMais.Parent = saldo
UiKit.corner(saldoMais, 3)
local function pintarSaldo()
	local cr = player:GetAttribute("Credits")
	saldoTxt.Text = if type(cr) == "number" then Progression.money(cr) else "–"
end
player:GetAttributeChangedSignal("Credits"):Connect(pintarSaldo)
pintarSaldo()

-- abas grandes (LB/RB, Q/E ou clique), com o botão do controle ou a tecla nas pontas; a ativa em
-- texto claro com o traço âmbar embaixo
local TAB_H = px(48, 66)
local TAB_Y = px(14, 18) + HEAD_H
local tabRow = Instance.new("Frame")
tabRow.BackgroundTransparency = 1
tabRow.Position = UDim2.fromOffset(PADX, TAB_Y)
tabRow.Size = UDim2.new(1, -2 * PADX, 0, TAB_H)
tabRow.Parent = folder
local dicaAba: { { img: ImageLabel, key: TextLabel, acao: string } } = {}
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, px(18, 26))
	l.Parent = tabRow
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = V.LINE
	rule.BackgroundTransparency = 0.4
	rule.BorderSizePixel = 0
	rule.Position = UDim2.fromOffset(PADX, TAB_Y + TAB_H)
	rule.Size = UDim2.new(1, -2 * PADX, 0, 1)
	rule.Parent = folder
	for i, acao in { "ui_tab_prev", "ui_tab_next" } do
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(px(28, 38), px(28, 38))
		img.LayoutOrder = if i == 1 then 0 else 100
		img.Parent = tabRow
		local key = UiKit.text2(tabRow, "", px(15, 21), V.TEXT, F.TITLE_MED)
		key.BackgroundColor3 = V.PANEL_3
		key.BackgroundTransparency = 0
		key.AutomaticSize = Enum.AutomaticSize.X
		key.Size = UDim2.fromOffset(0, px(26, 36))
		key.TextXAlignment = Enum.TextXAlignment.Center
		key.LayoutOrder = if i == 1 then 0 else 100
		UiKit.corner(key, 3)
		UiKit.pad(key, px(8, 10))
		table.insert(dicaAba, { img = img, key = key, acao = acao })
	end
end
local function pintarDicasAba()
	for _, d in dicaAba do
		local img, txt = Input.glyph(d.acao, "menu")
		local toque = Input.device() == "touch" or ToqueUi.active()
		d.img.Visible = not toque and img ~= nil
		d.img.Image = img or ""
		d.key.Visible = not toque and img == nil and txt ~= ""
		d.key.Text = UiKit.keyName(txt)
	end
end
pintarDicasAba()
local tabButtons: { [string]: TextButton } = {}
local setTab: (id: string) -> () = function(_id: string) end
for i, d in TABS do
	local b = Instance.new("TextButton")
	b.Name = d.id
	b.AutoButtonColor = false
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, TAB_H)
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.FontFace = UiKit.Estilo.headFont(d.name)
	b.TextSize = UiKit.text(px(18, 25)) -- D-207/D-211: oito abas cabem no painel de 1120
	b.TextColor3 = V.DIM
	b.Text = d.name
	b.Selectable = false
	b.LayoutOrder = i
	b.Parent = tabRow
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px(2, 4))
	p.PaddingRight = UDim.new(0, px(2, 4))
	p.PaddingBottom = UDim.new(0, px(6, 8))
	p.Parent = b
	local mark = Instance.new("Frame")
	mark.Name = "Marca"
	mark.AnchorPoint = Vector2.new(0.5, 1)
	mark.Position = UDim2.new(0.5, 0, 1, px(6, 8))
	mark.Size = UDim2.new(1, px(4, 8), 0, px(3, 4))
	mark.BackgroundColor3 = V.AMBAR -- D-205: a seleção em âmbar
	mark.BackgroundTransparency = 1
	mark.BorderSizePixel = 0
	mark.Parent = b
	UiKit.bind(b, function()
		setTab(d.id)
	end)
	tabButtons[d.id] = b
end
UiKit.bind(saldoMais, function()
	setTab("mercado") -- os créditos se compram no mercado
end)

-- fechar: botão fino, só contorno (no controle, B). Liga em shop_close → setOpen(false)
local closeBtn = UiKit.action(folder, "FECHAR ×", "secondary", function()
	Bus.fire("shop_close")
end, { h = px(38, 52) })
local close = closeBtn.button
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -PADX, 0, px(22, 30))
close.Size = UDim2.fromOffset(px(118, 160), px(38, 52))
close.Selectable = false

-- a lista (rola no analógico direito ou na roda do mouse), direto no painel
local TOP = TAB_Y + TAB_H + px(8, 10)
local FOOT = px(48, 66)
local sheet = Instance.new("Frame")
sheet.Name = "Conteudo"
sheet.Position = UDim2.fromOffset(px(10, 14), TOP)
sheet.Size = UDim2.new(1, -2 * px(10, 14), 1, -(TOP + FOOT))
sheet.BackgroundTransparency = 1
sheet.BorderSizePixel = 0
sheet.Parent = folder
local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.fromOffset(0, 4)
panel.Size = UDim2.new(1, 0, 1, -6)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.ScrollBarThickness = px(5, 7)
panel.ScrollBarImageColor3 = V.LINE
panel.ScrollBarImageTransparency = 0.2
panel.Selectable = false
panel.Parent = sheet
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 14)
pad.Parent = panel
-- a página da Intendência (Progresso.client) entra aqui quando a aba dela está ativa
local host = Instance.new("Frame")
host.Name = "Intendencia"
host.BackgroundTransparency = 1
host.Position = UDim2.fromOffset(0, 6)
host.Size = UDim2.new(1, 0, 1, -6)
host.Visible = false
host.Parent = sheet
-- D-173: a página das caixas (CaixasTela.client) entra aqui quando a aba CAIXAS está ativa
local hostCaixas = host:Clone()
hostCaixas.Name = "Caixas"
hostCaixas.Parent = sheet
-- D-175: a página do ARQUIVO MILITAR (ArquivoTela.client)
local hostArquivo = host:Clone()
hostArquivo.Name = "Arquivo"
hostArquivo.Parent = sheet

-- páginas MERCADO e VANTAGENS: listas que rolam, como a da loja (montadas quando o conteúdo muda)
local function newPage(name: string): ScrollingFrame
	local p = panel:Clone()
	p.Name = name
	p.Visible = false
	for _, c in p:GetChildren() do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then
			c:Destroy()
		end
	end
	p.Parent = sheet
	return p
end
local marketPage = newPage("Mercado")
local perkPage = newPage("Vantagens")
local codesPage = newPage("Codigos")
local armarioPage = newPage("Armario")
local pages: { [string]: ScrollingFrame } =
	{ loja = panel, armario = armarioPage, mercado = marketPage, vantagens = perkPage, codigos = codesPage }

-- ----- CÓDIGOS (D-207; §9: "Trate código válido, inválido, expirado e já utilizado. O servidor
-- confirma o benefício.") -----
-- Montada uma vez: o campo, o RESGATAR (trava enquanto o servidor responde), a resposta do servidor e
-- os códigos que esta conta já usou (campaign.owned "codigo:*", do estado da campanha).
local codigo: { [string]: any } = {}
do
	local f = Instance.new("Frame")
	f.Name = "Resgatar"
	f.LayoutOrder = 1
	f.Size = UDim2.new(1, -24, 0, px(250, 330))
	f.BackgroundColor3 = V.PANEL_2
	f.BorderSizePixel = 0
	f.Parent = codesPage
	UiKit.corner(f, 4)
	UiKit.edge(f, V.LINE, 1, 0.4)
	local P = px(24, 32)
	local t = UiKit.title(f, "RESGATAR UM CÓDIGO", px(38, 52))
	t.Position = UDim2.fromOffset(P, P)
	t.Size = UDim2.new(1, -2 * P, 0, px(46, 62))
	local s = UiKit.body(f, "Um uso por conta. Quem confere e entrega é o servidor.", px(15, 21), V.DIM)
	s.Position = UDim2.fromOffset(P, P + px(50, 66))
	s.Size = UDim2.new(1, -2 * P, 0, px(22, 30))
	local box = Instance.new("TextBox")
	box.Name = "Campo"
	box.Position = UDim2.fromOffset(P, P + px(86, 114))
	box.Size = UDim2.new(1, -(2 * P + px(220, 290)), 0, px(54, 72))
	box.BackgroundColor3 = V.BG
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.PlaceholderText = "DIGITE O CÓDIGO"
	box.PlaceholderColor3 = V.MUTED
	box.Text = ""
	box.FontFace = F.TITLE_MED
	box.TextSize = UiKit.text(px(24, 32))
	box.TextColor3 = V.TEXT
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Selectable = true
	box.SelectionImageObject = UiKit.FOCUS
	box.Parent = f
	UiKit.corner(box, 3)
	UiKit.edge(box, V.TEXT, 2, 0.15)
	UiKit.pad(box, px(16, 22))
	local resultado = UiKit.body(f, "", px(16, 22), V.DIM)
	resultado.Name = "Resposta"
	resultado.Position = UDim2.fromOffset(P, P + px(150, 198))
	resultado.Size = UDim2.new(1, -2 * P, 0, px(26, 34))
	local enviado = false
	local btn: UiKit.Action
	local envio = 0
	local function enviar()
		if enviado then
			return -- sem pedido duplicado enquanto o servidor responde
		end
		local txt = box.Text
		if (string.gsub(txt, "%s", "")) == "" then
			btn.erro("Digite um código")
			return
		end
		enviado = true
		envio += 1
		local meu = envio
		btn.carregando(true)
		resultado.Text = "Conferindo…"
		resultado.TextColor3 = V.DIM
		CampanhaCliente.action("code_redeem", { code = txt })
		-- sem resposta em 8 s: destrava e avisa (a rede pode ter caído)
		task.delay(8, function()
			if enviado and envio == meu then
				enviado = false
				btn.carregando(false)
				resultado.Text = "Sem resposta do servidor. Tente de novo."
				resultado.TextColor3 = V.RED_HI
			end
		end)
	end
	btn = UiKit.action(f, "RESGATAR", "primary", enviar, { h = px(54, 72) })
	btn.button.Name = "Resgatar"
	btn.button.AnchorPoint = Vector2.new(1, 0)
	btn.button.Position = UDim2.new(1, -P, 0, P + px(86, 114))
	btn.button.Size = UDim2.fromOffset(px(206, 274), px(54, 72))
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			enviar()
		end
	end)
	local usados = UiKit.body(f, "", px(14, 20), V.DIM)
	usados.Name = "Usados"
	usados.Position = UDim2.fromOffset(P, P + px(184, 242))
	usados.Size = UDim2.new(1, -2 * P, 0, px(22, 30))
	codigo.box, codigo.btn, codigo.resultado, codigo.usados = box, btn, resultado, usados
	codigo.fim = function(ok: boolean, msg: string?)
		enviado = false
		btn.carregando(false)
		resultado.Text = msg or (if ok then "Código aceito." else "O código não passou.")
		resultado.TextColor3 = if ok then V.OLIVE_HI else V.RED_HI
		if ok then
			box.Text = ""
		else
			btn.erro("Não passou")
		end
	end
end
local function renderCodes()
	local st = CampanhaCliente.get()
	local list: { string } = {}
	if st and type(st.owned) == "table" then
		for k in st.owned do
			if type(k) == "string" and string.sub(k, 1, 7) == "codigo:" then
				table.insert(list, string.sub(k, 8))
			end
		end
	end
	table.sort(list)
	codigo.usados.Text = if #list > 0 then string.format("Já usados nesta conta: %s", table.concat(list, ", ")) else ""
end

do -- filete sobre as dicas do pé
	local r = Instance.new("Frame")
	r.AnchorPoint = Vector2.new(0, 1)
	r.BackgroundColor3 = V.LINE
	r.BackgroundTransparency = 0.4
	r.BorderSizePixel = 0
	r.Position = UDim2.new(0, PADX, 1, -FOOT)
	r.Size = UDim2.new(1, -2 * PADX, 0, 1)
	r.Parent = folder
end
local foot = UiKit.chips(folder, px(30, 44), false, px(14, 22))
foot.frame.AnchorPoint = Vector2.new(0, 1)
foot.frame.Position = UDim2.new(0, PADX, 1, -px(9, 12))
foot.frame.Size = UDim2.new(1, -2 * PADX, 0, px(30, 44))

local state: any = { passes = {}, unlocked = {}, equipped = {} }
local priceCache: { [string]: string } = {}
local iconCache: { [string]: number } = {}
local order = 0

-- Preço e ícone ao vivo sem travar a vitrine: o 1º desenho mostra "R$ …" e a miniatura desenhada; o
-- botão e a imagem se completam quando o Roblox responde. GetProductInfoAsync devolve o preço
-- (Managed Pricing) e o IconImageAssetId: o ícone que já está publicado no passe ou no produto.
local DEFAULT_ICON = 88963008124478
local pricePending: { [string]: boolean } = {}
local priceWaiting: { [string]: { (string) -> () } } = {}
local iconWaiting: { [string]: { (number) -> () } } = {}
local function priceKey(id: number, infoType: Enum.InfoType): string
	return tostring(infoType) .. id
end
local function fetch(id: number, infoType: Enum.InfoType)
	local key = priceKey(id, infoType)
	if pricePending[key] or priceCache[key] then
		return
	end
	pricePending[key] = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		local p = if ok and info and info.PriceInRobux then string.format("R$ %d", info.PriceInRobux) else "—"
		priceCache[key] = p
		local icon = if ok and info then tonumber((info :: any).IconImageAssetId) else nil
		-- D-124: o ícone padrão dos produtos (o cubo cinza, o mesmo em todos, medido no Studio) não
		-- conta como imagem: fica o desenho na cor do item
		if icon == DEFAULT_ICON then
			icon = nil
		end
		if icon and icon > 0 then
			iconCache[key] = icon
		end
		local waiting = priceWaiting[key]
		if waiting then
			for _, fn in waiting do
				pcall(fn, p)
			end
		end
		local iw = iconWaiting[key]
		if iw and icon and icon > 0 then
			for _, fn in iw do
				pcall(fn, icon)
			end
		end
		priceWaiting[key] = nil
		iconWaiting[key] = nil
	end)
end
local function price(id: number, infoType: Enum.InfoType): string
	fetch(id, infoType)
	return priceCache[priceKey(id, infoType)] or "R$ …"
end
-- quem espera o preço: roda agora se já chegou, senão quando chegar
local function onPrice(id: number, infoType: Enum.InfoType, fn: (string) -> ())
	local key = priceKey(id, infoType)
	fetch(id, infoType)
	local p = priceCache[key]
	if p then
		fn(p)
	else
		priceWaiting[key] = priceWaiting[key] or {}
		table.insert(priceWaiting[key], fn)
	end
end
-- quem espera o ícone publicado: roda agora se já chegou, senão quando chegar (sem ícone, nunca)
local function onIcon(id: number, infoType: Enum.InfoType, fn: (number) -> ())
	local key = priceKey(id, infoType)
	fetch(id, infoType)
	local icon = iconCache[key]
	if icon then
		fn(icon)
	elseif not priceCache[key] then
		iconWaiting[key] = iconWaiting[key] or {}
		table.insert(iconWaiting[key], fn)
	end
end

local function section(text: string, parent: Instance?)
	order += 1
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -24, 0, px(32, 44))
	f.Parent = parent or panel
	-- cabeçalho de seção: Oswald cáqui e um filete fino (sem a linha vermelha da ficha)
	local t = UiKit.rotulo(f, 15, V.KHAKI, F.TITLE_MED)
	t.Size = UDim2.new(1, 0, 1, -4)
	t.Text = UiKit.upper(text)
	t.FontFace = UiKit.Estilo.headFont(text, F.TITLE_MED)
	local r = Instance.new("Frame")
	r.AnchorPoint = Vector2.new(0, 1)
	r.Position = UDim2.fromScale(0, 1)
	r.Size = UDim2.new(1, 0, 0, 1)
	r.BackgroundColor3 = V.LINE
	r.BackgroundTransparency = 0.3
	r.BorderSizePixel = 0
	r.Parent = f
end

local function note(text: string, parent: Instance?): TextLabel
	order += 1
	local t = UiKit.rotulo(parent or panel, 14, V.DIM, UiKit.BODY_FONT)
	t.LayoutOrder = order
	t.Size = UDim2.new(1, -28, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.TextWrapped = true
	t.Text = text
	return t
end

-- ===== vitrine (pedido do dono, 2026-11-11: "loja incrível, chamativa e atrativa") =====
-- Um destaque grande no alto (imagem, nome, selo, descrição curta, preço num botão cheio e o soldado
-- do lado do jogador à direita) e cartões grandes em duas colunas (imagem, nome, tipo, selo e o preço
-- cheio). Passar o mouse ou o foco num cartão leva o item para o destaque. Sem ícone publicado, a
-- miniatura é desenhada (sigla grande sobre a faixa da cor do item).
export type Offer = {
	key: string,
	name: string,
	desc: string,
	kind: string, -- seção do catálogo (o rótulo pequeno do cartão)
	id: number,
	infoType: Enum.InfoType?, -- nil: sem preço em Robux (Premium, assinatura)
	fmt: string, -- texto do botão com o preço no %s (ou o texto inteiro)
	owned: boolean,
	mark: string, -- sigla da miniatura desenhada
	accent: Color3,
	action: () -> (),
}

-- Selos. O Commerce e o Skins não têm dado de venda nem de lançamento: lista curta e explícita
-- (revisar com o dono quando houver números do Creator Dashboard).
local BADGE: { [string]: string } = {
	PASS_KIT_VETERAN = "NOVO",
	PASS_KIT_ELITE = "NOVO",
	PRODUCT_RESPAWN_INPLACE = "NOVO",
	PASS_USMC_1965 = "MAIS VENDIDO",
	PASS_VC_1965 = "MAIS VENDIDO",
}
-- o destaque de entrada: o primeiro desta ordem que o jogador ainda não tem
local FEATURED: { [string]: { string } } = {
	US = { "PASS_USMC_1965", "PASS_KIT_ELITE", "PASS_KIT_VETERAN", "PASS_SUPPORTER" },
	VC = { "PASS_VC_1965", "PASS_KIT_ELITE", "PASS_KIT_VETERAN", "PASS_SUPPORTER" },
	none = { "PASS_KIT_ELITE", "PASS_KIT_VETERAN", "PASS_SUPPORTER" },
}
-- sigla e cor da miniatura desenhada (sem letra solta que precise de tradução)
local MARK: { [string]: { text: string, color: Color3 } } = {
	PASS_USMC_1965 = { text = "65", color = V.US },
	PASS_VC_1965 = { text = "65", color = V.VC },
	PASS_UNIT = { text = "★", color = V.KHAKI },
	PASS_SUPPORTER = { text = "★", color = V.BRASS },
	PASS_KIT_VETERAN = { text = "1", color = V.OLIVE_HI },
	PASS_KIT_ELITE = { text = "2", color = V.OLIVE_HI },
	PRODUCT_TIP_SMALL = { text = "+", color = V.KHAKI },
	PRODUCT_TIP_LARGE = { text = "++", color = V.KHAKI },
	PRODUCT_RESPAWN_INPLACE = { text = "×", color = V.RED_HI },
	SUB = { text = "R", color = V.KHAKI },
	PREMIUM = { text = "P", color = V.TEXT },
}

-- D-124: imagens da loja feitas com os modelos do próprio jogo (tools/blender/loja.py, fundo
-- transparente). A imagem mostra só o que o item dá. Sem o ID da imagem (LojaImages = 0), fica o
-- desenho: a sigla na cor do item.
local LOJA_IMG: { [string]: string } = {
	PASS_USMC_1965 = "usmc",
	PASS_VC_1965 = "vc",
	PASS_KIT_ELITE = "elite",
}
local function lojaImage(name: string?): string?
	local ids = AssetIds.LojaImages or {}
	local id = if name then ids[name] else nil
	return if type(id) == "number" and id ~= 0 then string.format("rbxassetid://%d", id) else nil
end

-- miniatura: o fundo na cor do item (de cima para baixo), a imagem (render da loja ou a publicada
-- no passe) e, sem imagem, a sigla desenhada
type Thumb = { frame: Frame, image: ImageLabel, mark: TextLabel, strip: Frame }
local function thumb(parent: Instance, markSize: number): Thumb
	local f = Instance.new("Frame")
	f.Name = "Miniatura"
	f.BackgroundColor3 = V.PANEL_3
	f.BorderSizePixel = 0
	f.ClipsDescendants = true
	f.Parent = parent
	UiKit.corner(f, 3)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.45, 0.45, 0.45))
	g.Parent = f
	local mark = UiKit.text2(f, "", markSize, V.KHAKI, F.TITLE)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.TextTransparency = 0.1
	local strip = Instance.new("Frame")
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, px(4, 6))
	strip.BorderSizePixel = 0
	strip.Parent = f
	local image = Instance.new("ImageLabel")
	image.Name = "Icone"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(0.96, 0.96)
	image.ScaleType = Enum.ScaleType.Fit
	image.Visible = false
	image.Parent = f
	return { frame = f, image = image, mark = mark, strip = strip }
end
-- o fundo da miniatura: a cor do item escurecida (a imagem se destaca, a cor diz o tipo)
local function tintThumb(t: Thumb, accent: Color3)
	t.frame.BackgroundColor3 = accent:Lerp(V.PANEL, 0.62)
	t.strip.BackgroundColor3 = accent
end
local function paintThumb(t: Thumb, o: Offer)
	t.mark.Text = o.mark
	t.mark.TextColor3 = o.accent
	tintThumb(t, o.accent)
	t.image.Visible = false
	local render = lojaImage(LOJA_IMG[o.key])
	if render then
		t.image.Image = render
		t.image.Visible = true
		t.mark.Visible = false
		return
	end
	local infoType = o.infoType
	if infoType then
		onIcon(o.id, infoType, function(icon: number)
			if t.frame.Parent then
				t.image.Image = string.format("rbxassetid://%d", icon)
				t.image.Visible = true
				t.mark.Visible = false
			end
		end)
	end
	t.mark.Visible = not t.image.Visible
end

-- texto do botão de preço (o %s recebe o preço quando chega)
local function priceText(o: Offer, set: (string) -> ())
	local infoType = o.infoType
	if infoType then
		set(string.format(o.fmt, price(o.id, infoType)))
		onPrice(o.id, infoType, function(p: string)
			set(string.format(o.fmt, p))
		end)
	else
		set(o.fmt)
	end
end

-- ----- destaque (montado uma vez; cada item só troca os textos) -----
local HERO_H = px(236, 316)
local PREV_W = px(210, 280)
local hero: { [string]: any } = {}
local comprar: (o: Offer) -> () = function(_o: Offer) end -- (definida depois do destaque)
do
	local f = Instance.new("Frame")
	f.Name = "Destaque"
	f.LayoutOrder = -100
	f.BackgroundColor3 = V.PANEL_2
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, -24, 0, HERO_H)
	f:SetAttribute("Fixo", true) -- o redesenho da lista não destrói o destaque
	f.Parent = panel
	UiKit.corner(f, 4)
	UiKit.edge(f, V.LINE, 1, 0.4)
	do -- luz caindo da esquerda e o canto do soldado um pouco mais claro
		local g = Instance.new("UIGradient")
		g.Rotation = 0
		g.Color = ColorSequence.new({
			-- cor do gradiente vai de 0 a 1 (1,15 dava "color value out of range" no console): a mesma
			-- proporção, com o canto do soldado no branco
			ColorSequenceKeypoint.new(0, Color3.new(0.71, 0.71, 0.72)),
			ColorSequenceKeypoint.new(0.6, Color3.new(0.87, 0.87, 0.9)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 0.96)),
		})
		g.Parent = f
	end
	-- D-124: a faixa da capa do jogo no fundo (o arrozal, a vila e o dique no fim da tarde), com um
	-- véu escuro da esquerda para o texto ler bem; sem a imagem, fica o painel de antes
	local banner = lojaImage("destaque")
	if banner then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Fundo"
		bg.BackgroundTransparency = 1
		bg.Image = banner
		bg.ScaleType = Enum.ScaleType.Crop
		bg.Size = UDim2.fromScale(1, 1)
		bg.ZIndex = 0
		bg.Parent = f
		UiKit.corner(bg, 4)
		local veil = Instance.new("Frame")
		veil.Name = "Veu"
		veil.BackgroundColor3 = V.BG
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = 0
		veil.Parent = bg
		UiKit.corner(veil, 4)
		local vg = Instance.new("UIGradient")
		vg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 0.72),
		})
		vg.Parent = veil
	end
	-- a imagem grande do item à direita (quando há render da loja); senão, o soldado do lado
	local render = Instance.new("ImageLabel")
	render.Name = "Imagem"
	render.BackgroundTransparency = 1
	render.ScaleType = Enum.ScaleType.Fit
	render.AnchorPoint = Vector2.new(1, 0.5)
	render.Position = UDim2.new(1, -px(4, 6), 0.5, 0)
	render.Size = UDim2.new(0, PREV_W + px(40, 54), 1, -px(8, 12))
	render.Visible = false
	render.Parent = f
	hero.render = render
	-- o soldado do lado do jogador, iluminado de lado, à direita
	local pv = SoldierPreview.newStill(-0.55)
	local pf = pv.frame :: Frame
	pf.AnchorPoint = Vector2.new(1, 0)
	pf.Position = UDim2.new(1, -px(4, 6), 0, px(4, 6))
	pf.Size = UDim2.new(0, PREV_W, 1, -px(8, 12))
	pf.Parent = f
	local pvNote = pv.note
	if pvNote then
		pvNote.TextSize = UiKit.text(13)
	end
	hero.preview = pv
	hero.soldier = pf
	local P = px(18, 24)
	local TH = px(72, 96)
	local th = thumb(f, px(34, 46))
	th.frame.Position = UDim2.fromOffset(P, P)
	th.frame.Size = UDim2.fromOffset(TH, TH)
	hero.thumb = th
	local textX = P + TH + px(14, 18)
	local textW = -(textX + PREV_W + px(12, 16))
	local kick = UiKit.kicker(f, "DESTAQUE", px(13, 20), V.KHAKI)
	kick.Position = UDim2.fromOffset(textX, P - 2)
	kick.Size = UDim2.fromOffset(px(90, 130), px(20, 28))
	local badge = UiKit.tag(f, "", V.RED, px(12, 18))
	badge.Position = UDim2.fromOffset(textX + px(92, 132), P)
	hero.badge = badge
	local name = UiKit.title(f, "", px(28, 40))
	name.Position = UDim2.fromOffset(textX, P + px(22, 30))
	name.Size = UDim2.new(1, textW, 0, px(48, 64))
	name.TextWrapped = true
	name.TextScaled = true
	do
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = UiKit.text(px(28, 40))
		lim.MinTextSize = UiKit.text(px(16, 24))
		lim.Parent = name
	end
	hero.name = name
	local desc = UiKit.body(f, "", px(14, 22), V.DIM)
	desc.Position = UDim2.fromOffset(P, P + TH + px(10, 14))
	desc.Size = UDim2.new(1, -(P + PREV_W + px(12, 16)), 0, px(56, 80))
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	hero.desc = desc
	-- cores de compra (UiKit.PAGAR, 2026-11-13): tudo da vitrine se paga em Robux (verde)
	local buy = UiKit.action(f, "", "robux", function()
		local o = hero.offer :: Offer?
		if o and not o.owned then
			comprar(o)
		end
	end, { h = px(54, 74) })
	buy.button.Name = "Comprar"
	buy.button.AnchorPoint = Vector2.new(0, 1)
	buy.button.Position = UDim2.new(0, P, 1, -P)
	buy.button.Size = UDim2.new(1, -(P + PREV_W + px(12, 16)), 0, px(54, 74))
	hero.buy = buy
	local own = UiKit.tag(f, "✔ SEU", V.OLIVE, px(18, 26))
	own.AnchorPoint = Vector2.new(0, 1)
	own.Position = UDim2.new(0, P, 1, -P)
	own.Visible = false
	hero.own = own
	hero.frame = f
end

local function setHero(o: Offer)
	if hero.offer == o then
		return
	end
	local first = hero.offer == nil
	hero.offer = o
	hero.name.Text = UiKit.upper(o.name)
	hero.name.FontFace = UiKit.headFont(o.name)
	hero.desc.Text = o.desc
	local b = BADGE[o.key]
	hero.badge.Visible = b ~= nil
	hero.badge.Text = b or ""
	hero.badge.BackgroundColor3 = if b == "NOVO" then V.OLIVE else V.RED
	paintThumb(hero.thumb, o)
	-- a imagem do item vai grande à direita; a miniatura da esquerda fica com a sigla
	local big = lojaImage(LOJA_IMG[o.key])
	hero.render.Visible = big ~= nil
	hero.render.Image = big or ""
	hero.soldier.Visible = big == nil
	if big then
		hero.thumb.image.Visible = false
		hero.thumb.mark.Visible = true
	end
	hero.buy.button.Visible = not o.owned
	hero.own.Visible = o.owned
	hero.buy.enabled(true) -- item novo no destaque: o botão volta ao normal (D-207)
	priceText(o, function(t: string)
		if hero.offer == o then
			hero.buy.label.Text = t
		end
	end)
	if not first then -- troca de item: o texto novo entra deslizando um pouco
		UiKit.enter({ hero.name, hero.desc }, 8, 0.03)
	end
end

-- ----- compra (D-207; §9: "Preveja compra em andamento, cancelamento, confirmação, erro e entrega
-- pendente. O botão não deve permitir solicitações duplicadas") -----
-- Só pelo destaque: o botão trava com "…" enquanto a janela do Roblox está aberta; fechada sem
-- comprar, "Compra cancelada"; comprada, "ENTREGANDO…" até o servidor mandar a posse (Commerce_State)
-- ou 15 s ("entrega pendente": chega quando o servidor confirmar). O resultado do Roblox é só para a
-- tela: quem entrega é o servidor (ProcessReceipt / posse do passe).
local compraAtiva: Offer? = nil
local compraGen = 0
local function fimCompra(comprado: boolean)
	local o = compraAtiva
	if not o then
		return
	end
	compraAtiva = nil
	local b = hero.buy
	b.carregando(false)
	if not comprado then
		b.erro("Compra cancelada")
		return
	end
	local g = compraGen
	if o.infoType == Enum.InfoType.GamePass then
		b.enabled(false)
		b.label.Text = "ENTREGANDO…"
		task.delay(15, function()
			if compraGen == g and hero.offer == o and not o.owned then
				b.enabled(true)
				b.erro("Entrega pendente")
				Bus.fire("toast", "A compra passou; o item chega quando o servidor confirmar.")
			end
		end)
	else
		Bus.fire("toast", "Compra confirmada.")
	end
end
comprar = function(o: Offer)
	if compraAtiva then
		return -- sem pedido duplicado
	end
	compraAtiva = o
	compraGen += 1
	local g = compraGen
	hero.buy.carregando(true)
	local ok = pcall(o.action)
	if not ok then
		compraAtiva = nil
		hero.buy.carregando(false)
		hero.buy.erro("A compra não abriu")
		return
	end
	-- a janela do Roblox não respondeu (fechada de outro jeito): destrava em 90 s
	task.delay(90, function()
		if compraAtiva == o and compraGen == g then
			compraAtiva = nil
			hero.buy.carregando(false)
		end
	end)
end
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr: Player, _id: number, comprado: boolean)
	if plr == player then
		fimCompra(comprado)
	end
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(uid: number, _id: number, comprado: boolean)
	if uid == player.UserId then
		fimCompra(comprado)
	end
end)
-- Premium e assinatura: o Roblox não diz se comprou; só destrava
MarketplaceService.PromptPremiumPurchaseFinished:Connect(function()
	local o = compraAtiva
	if o then
		compraAtiva = nil
		hero.buy.carregando(false)
	end
end)
pcall(function()
	(MarketplaceService :: any).PromptSubscriptionPurchaseFinished:Connect(function()
		local o = compraAtiva
		if o then
			compraAtiva = nil
			hero.buy.carregando(false)
		end
	end)
end)

-- ----- cartão da grade -----
local CARD_H = px(236, 314) -- D-124: a imagem do item ganhou espaço (era 176)
local lastHot: ((on: boolean) -> ())? = nil -- toque: o cartão aceso por último (apaga ao tocar outro)
local function card(parent: Instance, o: Offer, n: number): GuiObject
	local f = Instance.new("Frame")
	f.Name = o.key
	f.LayoutOrder = n
	f.BackgroundColor3 = V.PANEL_2
	f.BorderSizePixel = 0
	f.Parent = parent
	UiKit.corner(f, 4)
	local edge = UiKit.edge(f, V.LINE, 1, 0.5)
	local P = px(10, 14)
	local th = thumb(f, px(30, 42))
	th.frame.Position = UDim2.fromOffset(P, P)
	th.frame.Size = UDim2.new(1, -2 * P, 0, px(128, 172))
	paintThumb(th, o)
	local b = BADGE[o.key]
	if b then
		local t = UiKit.tag(th.frame, b, if b == "NOVO" then V.OLIVE else V.RED, px(11, 17))
		t.AnchorPoint = Vector2.new(1, 0)
		t.Position = UDim2.new(1, -6, 0, 6)
	end
	local y = P + px(128, 172) + px(6, 8)
	local nm = UiKit.title(f, UiKit.upper(o.name), px(17, 24))
	nm.Position = UDim2.fromOffset(P, y)
	nm.Size = UDim2.new(1, -2 * P, 0, px(22, 30))
	local kd = UiKit.kicker(f, UiKit.upper(o.kind), px(12, 18))
	kd.Position = UDim2.fromOffset(P, y + px(22, 30))
	kd.Size = UDim2.new(1, -2 * P, 0, px(16, 24))
	local function hot(on: boolean)
		UiKit.tween(edge, UiKit.QUICK, {
			Color = if on then V.OLIVE_HI else V.LINE,
			Transparency = if on then 0 else 0.5,
		})
		if on then
			setHero(o)
		end
	end
	f.MouseEnter:Connect(function()
		hot(true)
	end)
	f.MouseLeave:Connect(function()
		hot(false)
	end)
	-- toque (Parte 13): sem "passar o mouse", tocar no cartão (fora do preço) mostra o item no
	-- destaque (descrição e soldado); antes, só abrindo a compra dava para ler. Vale para os já seus.
	if ToqueUi.active() then
		local ver = Instance.new("TextButton")
		ver.Name = "Ver"
		ver.Text = ""
		ver.AutoButtonColor = false
		ver.BackgroundTransparency = 1
		ver.Selectable = false
		ver.Size = UDim2.fromScale(1, 1)
		ver.ZIndex = 0 -- por baixo do botão do preço
		ver.Parent = f
		ver.Activated:Connect(function()
			if lastHot and lastHot ~= hot then
				lastHot(false)
			end
			lastHot = hot
			hot(true)
		end)
	end
	if o.owned then
		local t = UiKit.tag(f, "✔ SEU", V.OLIVE, px(14, 20))
		t.AnchorPoint = Vector2.new(0, 1)
		t.Position = UDim2.new(0, P, 1, -P)
	else
		-- preço bem à vista: botão cheio de largura inteira
		local bt = Instance.new("TextButton")
		bt.Name = "Botao"
		bt.AnchorPoint = Vector2.new(0, 1)
		bt.Position = UDim2.new(0, P, 1, -P)
		bt.Size = UDim2.new(1, -2 * P, 0, px(36, 50))
		bt.AutoButtonColor = false
		bt.FontFace = F.TITLE_MED
		bt.TextColor3 = V.TEXT
		bt.TextSize = UiKit.text(16)
		bt.TextTruncate = Enum.TextTruncate.AtEnd
		bt.Selectable = true
		bt.SelectionImageObject = UiKit.FOCUS
		bt.Parent = f
		UiKit.corner(bt, 3)
		priceText(o, function(t: string)
			if bt.Parent then
				bt.Text = t
			end
		end)
		local r = UiKit.payPaint(bt, "robux", 1.03) -- preço em Robux: verde (UiKit.PAGAR)
		local function both(on: boolean)
			r.set(on)
			hot(on)
		end
		bt.MouseEnter:Connect(function()
			both(true)
		end)
		bt.MouseLeave:Connect(function()
			both(false)
		end)
		bt.SelectionGained:Connect(function()
			both(true)
		end)
		bt.SelectionLost:Connect(function()
			both(false)
		end)
		-- D-207 (§9: "Ao selecionar, abrir detalhes e prévia antes da ação de comprar"): o cartão
		-- não compra; leva o item para o destaque (detalhes e imagem grande) e o foco para o comprar
		UiKit.bind(bt, function()
			setHero(o)
			UiKit.tween(panel, UiKit.SOFT, { CanvasPosition = Vector2.zero })
			if Input.isGamepad() then
				GuiService.SelectedObject = hero.buy.button
			end
		end, both)
	end
	return f
end

-- linha do armário: um botão por item (● equipado, ○ não)
local function lockerRow(key: string, text: string, on: boolean, onClick: () -> ())
	order += 1
	local b = Instance.new("TextButton")
	b.Name = key
	b.LayoutOrder = order
	b.Size = UDim2.new(1, -24, 0, px(40, 56))
	b.BackgroundColor3 = if on then V.PANEL_3 else V.PANEL_2
	b.AutoButtonColor = false
	b.Text = ""
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = panel
	UiKit.corner(b, 3)
	UiKit.edge(b, if on then V.OLIVE_HI else V.LINE, 1, if on then 0.2 else 0.6)
	local mark = UiKit.rotulo(b, 16, if on then V.OLIVE_HI else V.MUTED, Enum.Font.ArimoBold)
	mark.Position = UDim2.fromOffset(px(12, 16), 0)
	mark.Size = UDim2.new(0, px(22, 30), 1, 0)
	mark.Text = if on then "●" else "○"
	local t = UiKit.rotulo(b, 16, if on then V.TEXT else V.DIM, UiKit.BODY_FONT)
	t.Position = UDim2.fromOffset(px(38, 52), 0)
	t.Size = UDim2.new(1, -px(50, 66), 1, 0)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	local r = UiKit.realce(b, b.BackgroundColor3, V.PANEL_3, 1.01)
	b.MouseEnter:Connect(function()
		r.set(true)
	end)
	b.MouseLeave:Connect(function()
		r.set(false)
	end)
	b.SelectionGained:Connect(function()
		r.set(true)
	end)
	b.SelectionLost:Connect(function()
		r.set(false)
	end)
	UiKit.bind(b, onClick)
end

local function renderFoot()
	foot.clear()
	local dev = Input.device()
	if dev == "gamepad" then
		foot.pair("ui_tab_prev", "ui_tab_next", "menu", "Abas")
		foot.add(UiKit.padImage(Enum.KeyCode.ButtonA), nil, "A", "Escolher")
		foot.action("ui_back", "menu", "Fechar")
	elseif dev == "touch" or ToqueUi.active() then
		foot.add(nil, nil, "Toque", "na aba ou no item")
	else
		foot.pair("ui_tab_prev", "ui_tab_next", "menu", "Abas")
		foot.add(nil, nil, "Clique", "no item")
		foot.action("ui_back", "menu", "Fechar")
	end
end

-- o catálogo à venda agora (passes e produtos com ID, assinatura e Premium se ainda não tem)
local function offers(): { Offer }
	local out: { Offer } = {}
	local function add(o: Offer)
		table.insert(out, o)
	end
	local function mark(key: string): (string, Color3)
		local m = MARK[key]
		return if m then m.text else "★", if m then m.color else V.KHAKI
	end
	for _, pass in Commerce.Passes do
		local id = (Commerce.IDS :: any)[pass.key] :: number
		-- vantagens, passe da temporada, reforços, créditos e Recruta têm a aba própria (MERCADO,
		-- VANTAGENS): a vitrine fica com os visuais, os kits e o apoio
		if id ~= 0 and classify(pass.key, pass.kind) == "other" then
			local mt, mc = mark(pass.key)
			add({
				key = pass.key,
				name = pass.name,
				desc = pass.description,
				kind = "Passes",
				id = id,
				infoType = Enum.InfoType.GamePass,
				fmt = "REQUISITAR · %s",
				owned = state.passes[pass.key] == true,
				mark = mt,
				accent = mc,
				action = function()
					Net.event("Commerce_Track"):FireServer("prompt", pass.key)
					MarketplaceService:PromptGamePassPurchase(player, id)
				end,
			})
		end
	end
	for _, prod in Commerce.Products do
		local id = (Commerce.IDS :: any)[prod.key] :: number
		if id ~= 0 and classify(prod.key, prod.grants) == "other" then
			local mt, mc = mark(prod.key)
			add({
				key = prod.key,
				name = prod.name,
				desc = prod.description,
				kind = "Apoio",
				id = id,
				infoType = Enum.InfoType.Product,
				fmt = if prod.grants == "respawn" then "REQUISITAR · %s" else "APOIAR · %s",
				owned = false,
				mark = mt,
				accent = mc,
				action = function()
					Net.event("Commerce_Track"):FireServer("prompt", prod.key)
					MarketplaceService:PromptProductPurchase(player, id)
				end,
			})
		end
	end
	local sid = Commerce.IDS.SUBSCRIPTION_UNIT_RESERVE
	if sid ~= "" and not state.subscription then
		local mt, mc = mark("SUB")
		add({
			key = "sub",
			name = "Reserva da Unidade (mensal)",
			desc = "Um item histórico por temporada e a fita da Reserva.",
			kind = "Assinatura",
			id = 0,
			infoType = nil,
			fmt = "ASSINAR",
			owned = false,
			mark = mt,
			accent = mc,
			action = function()
				Net.event("Commerce_Track"):FireServer("prompt", "SUBSCRIPTION")
				MarketplaceService:PromptSubscriptionPurchase(player, sid)
			end,
		})
	end
	if not state.premium then
		local mt, mc = mark("PREMIUM")
		add({
			key = "premium",
			name = "Roblox Premium",
			desc = "Libera a capa Mitchell desbotada e o lenço xadrez (visuais).",
			kind = "Roblox Premium",
			id = 0,
			infoType = nil,
			fmt = "CONHECER O PREMIUM",
			owned = false,
			mark = mt,
			accent = mc,
			action = function()
				Net.event("Commerce_Track"):FireServer("prompt", "PREMIUM")
				MarketplaceService:PromptPremiumPurchase(player)
			end,
		})
	end
	return out
end

-- Redesenha só o que mudou: com o mesmo estado (abrir de novo, trocar de aba), nada é recriado; o
-- destaque e o soldado são montados uma vez e só trocam os textos.
local lastSig = ""
local function render()
	-- D-207: no lobby (sem lado ainda) vale o último lado escolhido; o armário equipa nele e o
	-- soldado do palco (o do próprio jogador) veste na hora
	local faction = player:GetAttribute("Faction") :: string?
	if faction ~= "US" and faction ~= "VC" then
		local c = JogarAgora.decode(player:GetAttribute("UltimaEscolha"))
		faction = if c.f == "US" or c.f == "VC" then c.f else nil
	end
	SoldierPreview.set(hero.preview, faction, nil)
	local sig = ""
	pcall(function()
		sig = HttpService:JSONEncode({ s = state, f = faction or "" })
	end)
	if sig ~= "" and sig == lastSig then
		renderFoot()
		return
	end
	lastSig = sig
	for _, c in panel:GetChildren() do
		if c:IsA("GuiObject") and not c:GetAttribute("Fixo") then
			c:Destroy()
		end
	end
	order = 0
	local list = offers()
	-- destaque: o mesmo item se ainda está à venda; senão o primeiro da ordem de entrada sem dono
	local keep: Offer? = nil
	local cur = hero.offer :: Offer?
	for _, o in list do
		if cur and o.key == cur.key then
			keep = o
		end
	end
	if not keep then
		for _, key in FEATURED[faction or "none"] or FEATURED.none do
			for _, o in list do
				if not keep and o.key == key and not o.owned then
					keep = o
				end
			end
		end
	end
	keep = keep or list[1]
	hero.frame.Visible = keep ~= nil
	if keep then
		hero.offer = nil -- força a troca (o item pode ter mudado de dono)
		setHero(keep)
	end
	if #list > 0 then
		order += 1
		local grid = Instance.new("Frame")
		grid.Name = "Vitrine"
		grid.LayoutOrder = order
		grid.BackgroundTransparency = 1
		grid.Size = UDim2.new(1, -24, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Parent = panel
		local gl = Instance.new("UIGridLayout")
		-- D-207: três colunas no painel largo (como a grade das referências)
		gl.CellSize = UDim2.new(1 / 3, -px(7, 10), 0, CARD_H)
		gl.CellPadding = UDim2.fromOffset(px(10, 14), px(10, 14))
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid
		for i, o in list do
			card(grid, o, i)
		end
	else
		note("Nenhum item à venda neste servidor.")
	end
	note("Aqui só visual, apoio e os kits (que também saem jogando). Vantagens: aba própria, com teto.")
	-- armário: só itens liberados (passe, Premium ou ganhos na caderneta); o servidor valida ao equipar
	if faction then
		section(if faction == "US" then "Armário · EUA" else "Armário · VC")
		local any = false
		for _, c in Commerce.Cosmetics do
			if c.faction == faction and table.find(state.unlocked, c.id) then
				any = true
				local eq = state.equipped[faction] and state.equipped[faction][c.slot] == c.id
				local text = if c.unlock == "daily"
					then string.format("%s: %s (caderneta)", c.slot, c.name)
					else string.format("%s: %s", c.slot, c.name)
				lockerRow("eq:" .. c.id, text, eq == true, function()
					Net.event("Commerce_Equip"):FireServer(faction, c.slot, c.id)
				end)
			end
		end
		if not any then
			note("Nada liberado ainda para este lado.")
		end
		note("Os dias 3 e 7 da caderneta de serviço (recompensa diária) dão itens que só saem de lá.")
	end
	renderFoot()
end

-- ============================================================================================
-- MERCADO e VANTAGENS (plano de volta diária, 2026-11-12; estado em Controllers/CampanhaCliente)
-- ============================================================================================
-- Sem pressão falsa: os tempos são os de verdade (virada do dia UTC, fim do reforço comprado, fim
-- de semana), em texto neutro, sem vermelho piscando.
local function hm(sec: number): string
	local s = math.max(0, math.floor(sec))
	local h, m = s // 3600, (s % 3600) // 60
	if h >= 24 then
		return string.format("%d d %d h", h // 24, h % 24)
	elseif h > 0 then
		return string.format("%d h %02d min", h, m)
	end
	return string.format("%d min", math.max(m, 1))
end

-- tipo do item (código do servidor -> rótulo curto do cartão)
local KIND_NAME: { [string]: string } = {
	camo = "Camuflagem",
	uniform = "Uniforme",
	emblem = "Emblema",
	title = "Título",
	gear = "Equipamento",
	boost = "Reforço",
	killcard = "Cartão de abate",
	gesture = "Gesto",
	music = "Música",
	credits = "Créditos",
	skin = "Skin",
	stars = "Estrelas",
}
local KIND_MARK: { [string]: { text: string, color: Color3 } } = {
	camo = { text = "C", color = V.OLIVE_HI },
	uniform = { text = "U", color = V.KHAKI },
	emblem = { text = "★", color = V.BRASS },
	title = { text = "T", color = V.TEXT },
	gear = { text = "E", color = V.OLIVE_HI },
	boost = { text = "×2", color = V.BRASS },
	credits = { text = "$", color = V.KHAKI },
	stars = { text = "★", color = V.BRASS },
}

-- passes e produtos do Commerce de uma categoria (classify), do mais barato ao mais caro
type Entry = { key: string, name: string, desc: string, id: number, infoType: Enum.InfoType, robux: number }
local function entries(cat: string): { Entry }
	local out: { Entry } = {}
	for _, p in Commerce.Passes do
		if classify(p.key, p.kind) == cat then
			table.insert(out, {
				key = p.key,
				name = p.name,
				desc = p.description,
				id = tonumber((Commerce.IDS :: any)[p.key]) or 0,
				infoType = Enum.InfoType.GamePass,
				robux = p.suggestedRobux or 0,
			})
		end
	end
	for _, p in Commerce.Products do
		if classify(p.key, p.grants) == cat then
			table.insert(out, {
				key = p.key,
				name = p.name,
				desc = p.description,
				id = tonumber((Commerce.IDS :: any)[p.key]) or 0,
				infoType = Enum.InfoType.Product,
				robux = p.suggestedRobux or 0,
			})
		end
	end
	-- os da campanha moram em listas próprias do Commerce (passe, vantagens, reforços, créditos)
	local C = Commerce :: any
	for _, p in (C.CampaignPasses or {}) :: { any } do
		if classify(p.key, p.kind) == cat then
			table.insert(out, {
				key = p.key,
				name = p.name,
				desc = p.description,
				id = tonumber((Commerce.IDS :: any)[p.key]) or 0,
				infoType = Enum.InfoType.GamePass,
				robux = p.suggestedRobux or 0,
			})
		end
	end
	for _, p in (C.CampaignProducts or {}) :: { any } do
		if classify(p.key, p.grants) == cat then
			table.insert(out, {
				key = p.key,
				name = p.name,
				desc = p.description,
				id = tonumber((Commerce.IDS :: any)[p.key]) or 0,
				infoType = Enum.InfoType.Product,
				robux = p.suggestedRobux or 0,
			})
		end
	end
	table.sort(out, function(a, b)
		return if a.robux ~= b.robux then a.robux < b.robux else a.name < b.name
	end)
	return out
end

local function prompt(e: Entry)
	if e.id == 0 then
		return
	end
	Net.event("Commerce_Track"):FireServer("prompt", e.key)
	if e.infoType == Enum.InfoType.GamePass then
		MarketplaceService:PromptGamePassPurchase(player, e.id)
	else
		MarketplaceService:PromptProductPurchase(player, e.id)
	end
end

-- cartão compacto das páginas novas: miniatura, nome, tipo, uma ou duas linhas e o preço cheio
type PageItem = {
	key: string,
	name: string,
	kind: string,
	desc: string?,
	mark: string,
	accent: Color3,
	badge: string?,
	owned: boolean,
	price: ((set: (string) -> ()) -> ())?, -- escreve o texto do botão (agora e quando o preço chegar)
	enabled: boolean,
	onClick: () -> (),
	pay: string?, -- forma de pagar (UiKit.PAGAR: "robux", "ci"); nil = ação sem compra (oliva)
	icon: { id: number, infoType: Enum.InfoType }?, -- D-124: o ícone publicado no passe, se houver
}
local ITEM_H = px(150, 206)
local function itemCard(parent: Instance, it: PageItem, n: number): Frame
	local f = Instance.new("Frame")
	f.Name = it.key
	f.LayoutOrder = n
	f.BackgroundColor3 = V.PANEL_2
	f.BorderSizePixel = 0
	f.Parent = parent
	UiKit.corner(f, 4)
	local edge = UiKit.edge(f, if it.owned then V.OLIVE_HI else V.LINE, 1, if it.owned then 0.2 else 0.5)
	local P = px(10, 14)
	local TH = px(56, 78)
	local th = thumb(f, px(24, 34))
	th.frame.Position = UDim2.fromOffset(P, P)
	th.frame.Size = UDim2.fromOffset(TH, TH)
	th.mark.Text = it.mark
	th.mark.TextColor3 = it.accent
	tintThumb(th, it.accent) -- D-124: o fundo na cor do item
	local render = lojaImage(LOJA_IMG[it.key])
	local ic = it.icon
	if render then
		th.image.Image = render
		th.image.Visible = true
		th.mark.Visible = false
	elseif ic then
		onIcon(ic.id, ic.infoType, function(icon: number)
			if th.frame.Parent then
				th.image.Image = string.format("rbxassetid://%d", icon)
				th.image.Visible = true
				th.mark.Visible = false
			end
		end)
	end
	local x = P + TH + px(10, 14)
	local nm = UiKit.title(f, UiKit.upper(it.name), px(16, 23))
	nm.Position = UDim2.fromOffset(x, P - 2)
	nm.Size = UDim2.new(1, -(x + P), 0, px(22, 30))
	local kd = UiKit.kicker(f, UiKit.upper(it.kind), px(12, 18))
	kd.Position = UDim2.fromOffset(x, P + px(20, 28))
	kd.Size = UDim2.new(1, -(x + P), 0, px(16, 24))
	if it.badge then
		local t = UiKit.tag(th.frame, it.badge, V.OLIVE, px(10, 15))
		t.AnchorPoint = Vector2.new(0.5, 1)
		t.Position = UDim2.new(0.5, 0, 1, -px(5, 7))
	end
	if it.desc and it.desc ~= "" then
		local d = UiKit.body(f, it.desc, px(13, 19), V.DIM)
		d.Position = UDim2.fromOffset(x, P + px(38, 54))
		d.Size = UDim2.new(1, -(x + P), 0, px(34, 48))
		d.TextTruncate = Enum.TextTruncate.AtEnd
	end
	if it.owned then
		local t = UiKit.tag(f, "✔ SEU", V.OLIVE, px(14, 20))
		t.AnchorPoint = Vector2.new(0, 1)
		t.Position = UDim2.new(0, P, 1, -P)
		return f
	end
	local bt = UiKit.action(f, "", if it.enabled then (it.pay or "primary") else "secondary", function()
		if it.enabled then
			it.onClick()
		end
	end, { h = px(36, 50) })
	bt.button.AnchorPoint = Vector2.new(0, 1)
	bt.button.Position = UDim2.new(0, P, 1, -P)
	bt.button.Size = UDim2.new(1, -2 * P, 0, px(36, 50))
	bt.label.TextXAlignment = Enum.TextXAlignment.Center
	bt.label.TextSize = UiKit.text(px(16, 22))
	if not it.enabled then
		bt.enabled(false)
	end
	local setter = it.price
	if setter then
		setter(function(t: string)
			if bt.button.Parent then
				bt.label.Text = t
			end
		end)
	end
	local function hot(on: boolean)
		UiKit.tween(edge, UiKit.QUICK, {
			Color = if on then V.OLIVE_HI else V.LINE,
			Transparency = if on then 0 else 0.5,
		})
	end
	bt.button.SelectionGained:Connect(function()
		hot(true)
	end)
	bt.button.SelectionLost:Connect(function()
		hot(false)
	end)
	f.MouseEnter:Connect(function()
		hot(true)
	end)
	f.MouseLeave:Connect(function()
		hot(false)
	end)
	return f
end

-- grade de duas colunas (wide: uma coluna larga)
local function grid(parent: Instance, wide: boolean?): Frame
	order += 1
	local g = Instance.new("Frame")
	g.Name = "Grade"
	g.LayoutOrder = order
	g.BackgroundTransparency = 1
	g.Size = UDim2.new(1, -24, 0, 0)
	g.AutomaticSize = Enum.AutomaticSize.Y
	g.Parent = parent
	local gl = Instance.new("UIGridLayout")
	-- D-207: três colunas no painel largo (a linha larga continua inteira)
	gl.CellSize = if wide then UDim2.new(1, 0, 0, ITEM_H) else UDim2.new(1 / 3, -px(7, 10), 0, ITEM_H)
	gl.CellPadding = UDim2.fromOffset(px(10, 14), px(10, 14))
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = g
	return g
end

-- cartão de um passe ou produto em Robux (ID 0: ainda não criado no Roblox -> "EM BREVE", apagado)
local function robuxItem(e: Entry, kind: string, mark: string, accent: Color3, owned: boolean, badge: string?): PageItem
	return {
		key = e.key,
		name = e.name,
		kind = kind,
		desc = e.desc,
		mark = mark,
		accent = accent,
		badge = badge,
		owned = owned,
		enabled = e.id ~= 0,
		pay = "robux",
		icon = if e.id ~= 0 then { id = e.id, infoType = e.infoType } else nil,
		price = function(set: (string) -> ())
			if e.id == 0 then
				set("EM BREVE")
				return
			end
			set(string.format("COMPRAR · %s", price(e.id, e.infoType)))
			onPrice(e.id, e.infoType, function(p: string)
				set(string.format("COMPRAR · %s", p))
			end)
		end,
		onClick = function()
			prompt(e)
		end,
	}
end

local function campaignLeft(t: any): number
	return if type(t) == "number" then CampanhaCliente.left(t) else 0
end

-- relógios das páginas (só texto, 1 vez por segundo com a página aberta)
local timers: { () -> () } = {}
local function clearPage(p: ScrollingFrame)
	table.clear(timers)
	for _, c in p:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
end
local function timerNote(parent: Instance, text: () -> string): TextLabel
	local t = note(text(), parent)
	table.insert(timers, function()
		if t.Parent then
			t.Text = text()
		end
	end)
	return t
end

-- ----- MERCADO -----
local marketSig = ""
local function renderMarket(force: boolean?)
	local s = CampanhaCliente.get()
	local sig = ""
	pcall(function()
		sig = HttpService:JSONEncode({
			m = s and s.market,
			b = s and s.boosts and { s.boosts.xpUntil, s.boosts.crUntil, s.boosts.weekend },
			r = s and s.recruit,
			se = s and s.season and { s.season.level, s.season.stars, s.season.veteran },
			p = state.passes,
		})
	end)
	if not force and sig ~= "" and sig == marketSig then
		return
	end
	marketSig = sig
	local p = marketPage
	clearPage(p)
	if not s then
		note("Recebendo o mercado do servidor…", p)
		CampanhaCliente.refresh()
		return
	end
	-- passe da temporada: resumo e a porta para a tela do passe
	local se = s.season
	section("Passe de campanha", p)
	do
		local g = grid(p, true)
		itemCard(g, {
			key = "passe",
			name = if se and type(se.name) == "string" then se.name else "Passe de campanha",
			kind = if se and se.veteran then "Veterano" else "Trilha grátis",
			desc = if se
				then string.format(
					"Nível %d de %d · %d de %d estrelas no nível",
					tonumber(se.level) or 0,
					tonumber(se.maxLevel) or 50,
					tonumber(se.starsInLevel) or 0,
					tonumber(se.starsPerLevel) or 0
				)
				else nil,
			mark = "★",
			accent = V.BRASS,
			owned = false,
			enabled = true,
			price = function(set: (string) -> ())
				set("ABRIR O PASSE")
			end,
			onClick = function()
				Bus.fire("passe_open")
			end,
		}, 1)
	end
	-- mercado do dia: 4 itens e o destaque da semana
	local m = s.market
	section("Mercado do dia", p)
	if type(m) == "table" then
		timerNote(p, function()
			return string.format("Itens novos em %s (virada do dia UTC).", hm(campaignLeft(m.resetsAt)))
		end)
		local function marketItem(mi: any, n: number, parent: Instance, badge: string?)
			local kind = tostring(mi.kind or "")
			local km = KIND_MARK[kind]
			local isRobux = mi.currency == "robux"
			local key = if type(mi.productKey) == "string" then mi.productKey else ""
			-- os itens do mercado são skins: o ID mora no Skins.IDS (o robuxKey da skin); os do
			-- Commerce ficam de reserva
			local SkinsMod = require(ReplicatedStorage.Shared.Skins) :: any
			local id = tonumber((Commerce.IDS :: any)[key]) or tonumber((SkinsMod.IDS or {})[key]) or 0
			local isPass = string.sub(key, 1, 5) == "PASS_"
			local infoType = if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product
			itemCard(parent, {
				key = tostring(mi.id),
				name = tostring(mi.name or mi.id),
				kind = KIND_NAME[kind] or "Item",
				desc = nil,
				mark = if km then km.text else "★",
				accent = if km then km.color else V.KHAKI,
				badge = badge,
				owned = mi.owned == true,
				enabled = not isRobux or id ~= 0,
				pay = if isRobux then "robux" else "ci",
				price = function(set: (string) -> ())
					if not isRobux then
						set(string.format("COMPRAR · %s", Progression.money(tonumber(mi.price) or 0)))
					elseif id == 0 then
						set(string.format("R$ %d", tonumber(mi.price) or 0))
					else
						set(string.format("COMPRAR · %s", price(id, infoType)))
						onPrice(id, infoType, function(pr: string)
							set(string.format("COMPRAR · %s", pr))
						end)
					end
				end,
				onClick = function()
					if not isRobux then
						CampanhaCliente.action("market_buy", { id = mi.id })
					elseif id ~= 0 then
						Net.event("Commerce_Track"):FireServer("prompt", key)
						if isPass then
							MarketplaceService:PromptGamePassPurchase(player, id)
						else
							MarketplaceService:PromptProductPurchase(player, id)
						end
					end
				end,
			}, n)
		end
		if type(m.weekly) == "table" then
			marketItem(m.weekly, 1, grid(p, true), "DA SEMANA")
		end
		local g = grid(p)
		for i, mi in (if type(m.items) == "table" then m.items else {}) :: { any } do
			if type(mi) == "table" then
				marketItem(mi, i, g)
			end
		end
	else
		note("O mercado abre quando o servidor mandar a lista do dia.", p)
	end
	-- reforços: XP e créditos dobrados por tempo (o tempo comprado sobrevive à troca de servidor)
	local b = s.boosts
	section("Reforços", p)
	if type(b) == "table" then
		if b.weekend then
			local t = UiKit.tag(p, "XP DOBRADO DE FIM DE SEMANA", V.BRASS, px(14, 20))
			order += 1
			t.LayoutOrder = order
			if type(b.weekendEndsAt) == "number" then
				timerNote(p, function()
					return string.format(
						"Para todos, até domingo 23h59 (Brasília): faltam %s.",
						hm(campaignLeft(b.weekendEndsAt))
					)
				end)
			end
		end
		if campaignLeft(b.xpUntil) > 0 then
			timerNote(p, function()
				return string.format("XP dobrado ativo: mais %s.", hm(campaignLeft(b.xpUntil)))
			end)
		end
		if campaignLeft(b.crUntil) > 0 then
			timerNote(p, function()
				return string.format("Créditos dobrados ativos: mais %s.", hm(campaignLeft(b.crUntil)))
			end)
		end
	end
	local boosts = entries("boost")
	if #boosts > 0 then
		local g = grid(p)
		for i, e in boosts do
			itemCard(g, robuxItem(e, "Reforço", "×2", V.BRASS, false), i)
		end
	else
		note("Os reforços chegam em breve.", p)
	end
	-- Pacote de Recruta (compra única)
	local rec = entries("recruit")
	if #rec > 0 then
		section("Pacote de Recruta", p)
		local owned = type(s.recruit) == "table" and s.recruit.owned == true
		local g = grid(p, true)
		for i, e in rec do
			itemCard(g, robuxItem(e, "Compra única", "R", V.OLIVE_HI, owned or state.passes[e.key] == true), i)
		end
	end
	-- créditos em pacotes
	local packs = entries("credits")
	if #packs > 0 then
		section("Créditos", p)
		local g = grid(p)
		for i, e in packs do
			itemCard(g, robuxItem(e, "Créditos", "$", V.KHAKI, false), i)
		end
	end
	UiKit.focus(p)
end

-- ----- VANTAGENS -----
-- rótulo curto de cada chave de vantagem ativa (Campanha_State.perks: multiplicador final)
local PERK_NAME: { [string]: string } = {
	speed = "Velocidade",
	health = "Vida",
	breath = "Fôlego",
	sway = "Balanço",
	reload = "Recarga",
	bandage = "Bandagem",
	bleed = "Sangramento",
	mags = "Carregadores",
	grenades = "Granadas",
	mark = "Marcação",
}
local function perkValue(v: number): string
	if v >= 2 and v == math.floor(v) then
		return string.format("+%d", v)
	elseif v >= 1 then
		return string.format("+%d%%", math.floor((v - 1) * 100 + 0.5))
	end
	return string.format("-%d%%", math.floor((1 - v) * 100 + 0.5))
end
local perkSig = ""
local function renderPerks(force: boolean?)
	local s = CampanhaCliente.get()
	local sig = ""
	pcall(function()
		sig = HttpService:JSONEncode({ k = s and s.perks, p = state.passes })
	end)
	if not force and sig ~= "" and sig == perkSig then
		return
	end
	perkSig = sig
	local p = perkPage
	clearPage(p)
	section("Vantagens", p)
	note("Teto: no máximo +12% em qualquer número de combate, somando vantagens e kits.", p)
	-- as ativas agora (a ficha do jogador mostra as mesmas: ninguém acha que é trapaça)
	local active = if s and type(s.perks) == "table" then s.perks else nil
	if active and next(active) then
		section("Ativas", p)
		order += 1
		local row = Instance.new("Frame")
		row.Name = "Ativas"
		row.LayoutOrder = order
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -24, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Parent = p
		local rl = Instance.new("UIGridLayout")
		rl.CellSize = UDim2.fromOffset(px(150, 210), px(24, 34))
		rl.CellPadding = UDim2.fromOffset(6, 6)
		rl.Parent = row
		for key, v in active :: { [string]: any } do
			if type(v) == "number" and v ~= 1 then
				local t = UiKit.tag(
					row,
					string.format("%s %s", UiKit.upper(PERK_NAME[key] or key), perkValue(v)),
					V.OLIVE,
					px(13, 19)
				)
				t.AutomaticSize = Enum.AutomaticSize.None
			end
		end
	end
	local combo = entries("combatente")
	local perks = entries("perk")
	if #combo == 0 and #perks == 0 then
		note("As vantagens chegam em breve.", p)
		return
	end
	if #combo > 0 then
		local g = grid(p, true)
		for i, e in combo do
			itemCard(g, robuxItem(e, "As 7 juntas", "7", V.BRASS, state.passes[e.key] == true, "PACOTE"), i)
		end
	end
	if #perks > 0 then
		section("Uma a uma", p)
		local g = grid(p)
		for i, e in perks do
			itemCard(g, robuxItem(e, "Vantagem", "+", V.OLIVE_HI, state.passes[e.key] == true), i)
		end
	end
	UiKit.focus(p)
end

-- ----- ARMÁRIO (D-211) -----
-- A arma principal de cada papel do lado (Roles.PRIMARY) com a imagem do modelo do jogo (RodaArte):
-- escolher grava no perfil (Arma_Escolher) e vale no próximo nascimento, no jogar agora e nas próximas
-- sessões. Embaixo, o que você já tem para vestir e o caminho para os acabamentos (INTENDÊNCIA).
local ARMARIO_PAPEIS =
	{ "squad_leader", "rifleman", "medic", "support", "machine_gunner", "commander", "anti_tank", "sniper" }
local armarioLado: string? = nil -- o lado mostrado (nil: o de agora ou o último escolhido)
local function ladoAtual(): string
	local f = player:GetAttribute("Faction")
	if f == "US" or f == "VC" then
		return f
	end
	local c = JogarAgora.decode(player:GetAttribute("UltimaEscolha"))
	return if c and (c.f == "US" or c.f == "VC") then c.f else "US"
end
-- a arma enche o quadro largo do cartão (o RodaArte enquadra pela diagonal)
local function encherArte(vp: ViewportFrame)
	local cam = vp.CurrentCamera
	local m = vp:FindFirstChildOfClass("Model")
	if cam and m then
		local alvo = m:GetBoundingBox().Position
		cam.CFrame = CFrame.lookAt(alvo + (cam.CFrame.Position - alvo) * 0.55, alvo)
	end
end
local function renderArmario()
	local p = armarioPage
	for _, c in p:GetChildren() do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then
			c:Destroy()
		end
	end
	local ordem = 0
	local function add(o: GuiObject)
		ordem += 1
		o.LayoutOrder = ordem
		o.Parent = p
	end
	local f = armarioLado or ladoAtual()
	-- o lado mostrado: EUA | VC
	local lados = Instance.new("Frame")
	lados.Name = "Lados"
	lados.BackgroundTransparency = 1
	lados.Size = UDim2.new(1, -24, 0, px(40, 54))
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, px(10, 14))
	ll.Parent = lados
	for _, lado in { "US", "VC" } do
		local on = lado == f
		local b = UiKit.action(
			lados,
			if lado == "US" then "EUA" else "VC",
			if on then "primary" else "secondary",
			function()
				armarioLado = lado
				renderArmario()
			end,
			{ h = px(40, 54) }
		)
		b.button.Name = lado
		b.button.Size = UDim2.fromOffset(px(140, 190), px(40, 54))
	end
	add(lados)
	local t = UiKit.title(nil, "ARMA PRINCIPAL", px(30, 40))
	t.Size = UDim2.new(1, -24, 0, px(38, 50))
	add(t)
	add(note("Escolha a arma de cada papel: vale no próximo nascimento e fica guardada."))
	local prefs = Roles.unpackPrefs(player:GetAttribute("ArmasPreferidas"))
	for _, rid in ARMARIO_PAPEIS do
		local list = Roles.primaries(f, rid)
		local def = Roles.roles[rid]
		if #list > 1 and def then
			local row = Instance.new("Frame")
			row.Name = rid
			row.Size = UDim2.new(1, -24, 0, px(214, 286))
			row.BackgroundColor3 = V.PANEL_2
			row.BorderSizePixel = 0
			UiKit.corner(row, 4)
			UiKit.edge(row, V.LINE, 1, 0.5)
			local nome = UiKit.title(row, UiKit.upper(def.name), px(22, 30))
			nome.Position = UDim2.fromOffset(px(16, 22), px(10, 14))
			nome.Size = UDim2.new(1, -px(32, 44), 0, px(30, 40))
			local cards = Instance.new("Frame")
			cards.BackgroundTransparency = 1
			cards.Position = UDim2.fromOffset(px(16, 22), px(46, 62))
			cards.Size = UDim2.new(1, -px(32, 44), 0, px(156, 208))
			cards.Parent = row
			local cl = Instance.new("UIListLayout")
			cl.FillDirection = Enum.FillDirection.Horizontal
			cl.Padding = UDim.new(0, px(12, 16))
			cl.SortOrder = Enum.SortOrder.LayoutOrder
			cl.Parent = cards
			local escolhida = Roles.primaryFor(f, rid, prefs[Roles.chavePref(f, rid)])
			for i, w in list do
				local on = w == escolhida
				local c = Instance.new("TextButton")
				c.Name = w
				c.LayoutOrder = i
				c.AutoButtonColor = false
				c.Text = ""
				c.Size = UDim2.fromOffset(px(230, 306), px(156, 208))
				c.BackgroundColor3 = if on then V.PANEL_3 else UiKit.CARD_DARK
				c.BorderSizePixel = 0
				c.Selectable = true
				c.SelectionImageObject = UiKit.FOCUS
				c.Parent = cards
				UiKit.corner(c, 4)
				UiKit.edge(c, if on then V.AMBAR else V.LINE, if on then 2 else 1, if on then 0 else 0.5)
				local vp = RodaArte.frame(c)
				vp.Position = UDim2.fromOffset(px(8, 10), px(8, 10))
				vp.Size = UDim2.new(1, -px(16, 20), 0, px(96, 128))
				RodaArte.show(vp, string.format("weapon:%s", w))
				encherArte(vp)
				local n = UiKit.title(c, Weapons.shortName(w, f), px(20, 27))
				n.Position = UDim2.fromOffset(px(12, 16), px(106, 142))
				n.Size = UDim2.new(1, -px(24, 32), 0, px(24, 32))
				local tag = UiKit.rotulo(c, 13, if on then V.AMBAR else V.DIM, UiKit.F.BODY_B)
				tag.Position = UDim2.fromOffset(px(12, 16), px(130, 174))
				tag.Size = UDim2.new(1, -px(24, 32), 0, px(18, 24))
				tag.Text = if on then "✓ ESCOLHIDA" else "ESCOLHER"
				local r = UiKit.realce(c, c.BackgroundColor3, V.PANEL_3, 1.02)
				c.MouseEnter:Connect(function()
					r.set(true)
				end)
				c.MouseLeave:Connect(function()
					r.set(false)
				end)
				c.SelectionGained:Connect(function()
					r.set(true)
				end)
				c.SelectionLost:Connect(function()
					r.set(false)
				end)
				UiKit.bind(c, function()
					if not on then
						Net.event("Arma_Escolher"):FireServer(f, rid, w)
					end
				end)
			end
			add(row)
		end
	end
	-- visuais: o que você já tem para vestir neste lado (o servidor valida ao equipar)
	local v = UiKit.title(nil, "VISUAIS", px(30, 40))
	v.Size = UDim2.new(1, -24, 0, px(38, 50))
	add(v)
	local any = false
	for _, c in Commerce.Cosmetics do
		if c.faction == f and table.find(state.unlocked, c.id) then
			any = true
			local eq = state.equipped[f] and state.equipped[f][c.slot] == c.id
			local b = Instance.new("TextButton")
			b.Name = string.format("eq_%s", c.id)
			b.AutoButtonColor = false
			b.Text = ""
			b.Size = UDim2.new(1, -24, 0, px(40, 56))
			b.BackgroundColor3 = if eq then V.PANEL_3 else V.PANEL_2
			b.Selectable = true
			b.SelectionImageObject = UiKit.FOCUS
			UiKit.corner(b, 3)
			UiKit.edge(b, if eq then V.OLIVE_HI else V.LINE, 1, if eq then 0.2 else 0.6)
			local tx = UiKit.rotulo(b, 16, if eq then V.TEXT else V.DIM, UiKit.BODY_FONT)
			tx.Position = UDim2.fromOffset(px(14, 18), 0)
			tx.Size = UDim2.new(1, -px(28, 36), 1, 0)
			tx.Text = string.format("%s  %s: %s", if eq then "●" else "○", c.slot, c.name)
			UiKit.bind(b, function()
				Net.event("Commerce_Equip"):FireServer(f, c.slot, c.id)
			end)
			add(b)
		end
	end
	if not any then
		add(note("Nada liberado ainda para este lado: caixas, passe e caderneta dão visuais."))
	end
	local ir = UiKit.action(nil, "ACABAMENTOS E UNIFORMES ›", "secondary", function()
		setTab("intendencia")
	end, { h = px(48, 64) })
	ir.button.Size = UDim2.new(1, -24, 0, px(48, 64))
	add(ir.button)
end
player:GetAttributeChangedSignal("ArmasPreferidas"):Connect(function()
	if gui.Enabled and tab == "armario" then
		renderArmario()
	end
end)

local function renderPage()
	if tab == "mercado" then
		renderMarket()
	elseif tab == "vantagens" then
		renderPerks()
	elseif tab == "codigos" then
		renderCodes()
	elseif tab == "armario" then
		renderArmario()
	end
end

CampanhaCliente.Changed:Connect(function(_s: any, result: any)
	if gui.Enabled then
		renderPage()
	end
	if type(result) == "table" and result.op == "code_redeem" then
		codigo.fim(result.ok == true, if type(result.msg) == "string" then result.msg else nil)
	end
	if type(result) == "table" and result.op == "market_buy" then
		Bus.fire(
			"toast",
			if type(result.msg) == "string" and result.msg ~= ""
				then result.msg
				elseif result.ok then "Compra feita."
				else "A compra não passou."
		)
	end
end)
-- relógios: 1 vez por segundo, só com a loja aberta numa página que tem relógio
task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled and (tab == "mercado" or tab == "vantagens") then
			for _, fn in timers do
				fn()
			end
		end
	end
end)

Net.event("Commerce_State").OnClientEvent:Connect(function(s)
	state = s
	if gui.Enabled then
		render()
		renderPage()
	end
end)

-- aba ativa: a loja (lista desta tela) ou a intendência (página do Progresso montada na folha)
local function paintTabs()
	for id, b in tabButtons do
		local on = id == tab
		TweenService:Create(b, UiKit.QUICK, { TextColor3 = if on then V.TEXT else V.DIM }):Play()
		local mark = b:FindFirstChild("Marca")
		if mark and mark:IsA("Frame") then
			TweenService:Create(mark, UiKit.QUICK, { BackgroundTransparency = if on then 0 else 1 }):Play()
		end
	end
end
local pageBase: { [Instance]: UDim2 } = {}
setTab = function(id: string)
	if not tabIndex(id) then
		return
	end
	tab = id
	paintTabs()
	if not gui.Enabled then
		return
	end
	for pid, pg in pages do
		pg.Visible = pid == id
	end
	host.Visible = id == "intendencia"
	hostCaixas.Visible = id == "caixas"
	hostArquivo.Visible = id == "arquivo"
	if id == "caixas" then
		Bus.fire("caixas_show", hostCaixas)
	else
		Bus.fire("caixas_hide")
	end
	if id == "arquivo" then
		Bus.fire("arquivo_show", hostArquivo)
	else
		Bus.fire("arquivo_hide")
	end
	if id == "intendencia" then
		Bus.fire("intendencia_show", host)
	elseif id ~= "caixas" and id ~= "arquivo" then
		Bus.fire("intendencia_hide")
		renderPage() -- mercado e vantagens: só redesenha se o estado mudou
		UiKit.focus(pages[id])
	else
		Bus.fire("intendencia_hide")
	end
	-- a folha nova desliza um pouco (o conteúdo já existe: nada é criado aqui)
	-- posição de repouso guardada: trocar de aba rápido não deixa a folha deslocada no meio do tween
	local page: GuiObject = if id == "intendencia"
		then host
		elseif id == "caixas" then hostCaixas
		elseif id == "arquivo" then hostArquivo
		else pages[id]
	local p0: UDim2 = pageBase[page] or page.Position
	pageBase[page] = p0
	page.Position = p0 + UDim2.fromOffset(px(14, 20), 0)
	TweenService:Create(page, TweenInfo.new(0.22, Enum.EasingStyle.Quint), { Position = p0 }):Play()
end

local closeToken = 0
local shopOpen = false -- aberta de fato (na saída a tela ainda fica ligada 0,16 s)
local function setOpen(open: boolean, which: string?)
	if which then
		tab = which
	end
	-- fechar duas vezes na mesma saída (B e o FECHAR) descontava o contador de menus em dobro
	if open == shopOpen then
		if open and which then
			setTab(which)
		end
		return
	end
	shopOpen = open
	closeToken += 1
	local my = closeToken
	if open then
		gui.Enabled = true
		UiKit.opened("loja", gui.DisplayOrder)
		-- D-207: entra da esquerda, sobre o palco (no lobby) ou sobre o véu (em campo)
		pintarFundo(LobbyPalco.aberto())
		pintarDicasAba()
		fundo.BackgroundTransparency = 1
		UiKit.tween(fundo, TweenInfo.new(0.3, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
		folder.Position = UDim2.new(0, X0 - px(40, 54), 0.5, 0)
		fit.play(TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), 1, 0.97)
		UiKit.tween(folder, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, X0, 0.5, 0),
		})
		Input.openMenu()
		Net.event("Commerce_Track"):FireServer("store_open")
		render() -- com o que já se sabe: a pasta nunca abre vazia esperando o servidor
		setTab(tab)
		local openedAt = os.clock()
		task.spawn(function()
			local ok, s = pcall(function()
				return Net.func("Commerce_GetState"):InvokeServer()
			end)
			if not (ok and type(s) == "table") then
				return
			end
			local same = false
			pcall(function()
				same = HttpService:JSONEncode(s) == HttpService:JSONEncode(state)
			end)
			state = s
			if same then
				return
			end
			-- redesenha só se mudou, e depois da entrada (nada é recriado no meio da animação)
			task.wait(math.max(0, openedAt + 0.32 - os.clock()))
			if gui.Enabled and closeToken == my then
				render()
				renderPage()
				if pages[tab] then
					UiKit.focus(pages[tab])
				end
			end
		end)
	else
		Input.closeMenu()
		UiKit.closed("loja")
		UiKit.release(gui)
		Bus.fire("intendencia_hide")
		Bus.fire("caixas_hide")
		Bus.fire("arquivo_hide")
		Bus.fire("shop_closed")
		local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		fit.play(info, 0.95)
		task.delay(0.16, function()
			if closeToken == my then
				gui.Enabled = false
			end
		end)
	end
end

-- o FECHAR já está ligado (UiKit.action → shop_close → setOpen(false))
-- shop_open(aba?): "loja" ou "intendencia" (sem aba: a última usada; a primeira é a vitrine, D-124)
Bus.on("shop_open", function(which: string?)
	setOpen(true, which)
end)
Bus.on("shop_close", function()
	setOpen(false)
end)
Input.on("ui_back", "press", function()
	if shopOpen and UiKit.backFor("loja") then
		setOpen(false)
	end
end)
-- LB/RB (Q/E) trocam a aba (LT/RT ficam para as abas de dentro da intendência)
for action, dir in { ui_tab_prev = -1, ui_tab_next = 1 } :: { [string]: number } do
	Input.on(action, "press", function()
		if gui.Enabled and UiKit.top() == "loja" then
			local i = tabIndex(tab) or 1
			setTab(TABS[(i - 1 + dir) % #TABS + 1].id)
		end
	end)
end
Input.DeviceChanged:Connect(function()
	if gui.Enabled then
		renderFoot()
		pintarDicasAba()
	end
end)
UiKit.watch(panel, function()
	return gui.Enabled
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.L and not UserInputService:GetFocusedTextBox() then
		setOpen(not shopOpen)
	end
end)

if RunService:IsStudio() then
	-- "loja" abre na aba da loja; "intendencia" na da intendência; "mercado" no mercado do dia;
	-- "vantagens" nas vantagens
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		local v = workspace:GetAttribute("VT65DevTela")
		if
			v == "loja"
			or v == "intendencia"
			or v == "mercado"
			or v == "vantagens"
			or v == "caixas"
			or v == "arquivo"
		then
			Bus.fire("shop_open", v)
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
