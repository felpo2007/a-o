--!strict
-- D-223 (dono: "isso está horrível, sem qualidade visual, genérico, sem imagens, sem ordem"): a preparação
-- em quatro passos numa barra só: 01 TIME, 02 GRUPO, 03 CLASSE e 04 ONDE NASCER, sem mesa 3D e sem
-- personagem. Cada passo é uma tela cheia de imagens (tools/blender/armas_catalogo.py):
--   - TIME: dois cartões grandes, a natureza-morta de cada lado, bandeira e efetivo;
--   - GRUPO: os grupos com as insígnias de quem já está em cada vaga, e o seu grupo ao lado;
--   - CLASSE: a lista das classes, a arma e o equipamento por imagens e a ficha do que está escolhido
--     (dono: "permita poder alterar o equipamento dentro do jogo na escolha da classe").
-- O passo 04 é a carta do GameUI: daqui vêm só a barra de cima e a de baixo. A lógica do caminho (o que
-- falta, os pedidos ao servidor) continua no DeployScreen, que passa os callbacks em `Ctx`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Kit = require(ReplicatedStorage.Shared.Kit)
local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local ArteCatalogo = require(script.Parent.ArteCatalogo)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F

local Preparacao = {}

export type Ctx = {
	lado: () -> string?,
	escolherLado: (f: string) -> (),
	abrir: (nome: string) -> (),
	voltar: () -> (),
	menu: () -> (),
	avisar: (msg: string) -> (),
	primaria: (f: string, rid: string) -> string?,
	trocarPrimaria: (rid: string, arma: string) -> (),
	escolherPapel: (rid: string) -> (),
	papelAtual: () -> string?,
	temSquad: () -> boolean,
	bloqueioDoLado: (f: string) -> string?,
	contagem: () -> (number, number),
	acharSquad: (st: any, sid: string) -> any,
	unidadeDoSquad: (f: string, sid: string) -> string?,
}

local DOURADO = Color3.fromRGB(226, 178, 74)
local PAINEL = Color3.fromRGB(20, 22, 18)
local CARTAO = Color3.fromRGB(32, 35, 28)
local CARTAO_HI = Color3.fromRGB(50, 54, 40)
local RAPIDO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SUAVE = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

Preparacao.PASSOS = {
	{ id = "lado", num = "01", nome = "TIME" },
	{ id = "squad", num = "02", nome = "GRUPO" },
	{ id = "role", num = "03", nome = "CLASSE" },
	{ id = "insert", num = "04", nome = "ONDE NASCER" },
}

Preparacao.DESC = {
	squad_leader = "Comanda o grupo e leva o rádio.",
	rifleman = "O soldado de linha: fuzil, granadas e mobilidade.",
	medic = "Cuida dos feridos do grupo.",
	support = "Põe caixas de munição e constrói posições.",
	machine_gunner = "Segura a linha com fogo contínuo.",
	anti_tank = "Destrói veículos com o lançador.",
	sniper = "Elimina alvos de longe, com luneta.",
	commander = "Pede apoio de fogo para o time.",
} :: { [string]: string }

local ORDEM_CLASSES =
	{ "rifleman", "squad_leader", "medic", "support", "machine_gunner", "anti_tank", "sniper", "commander" }

local TIMES = {
	US = { kicker = "USMC", titulo = "FUZILEIROS NAVAIS", linha = "RLT-7 · batalhões 3/3, 2/4 e 3/7", curto = "EUA" },
	VC = { kicker = "FORÇA PRINCIPAL", titulo = "VIET CONG", linha = "1º Regimento", curto = "VC" },
} :: { [string]: { kicker: string, titulo: string, linha: string, curto: string } }

local function corLado(f: string?): Color3
	return if f == "US" then V.US elseif f == "VC" then V.VC else DOURADO
end

-- ===== peças =====
local escala = 1
local textos: { { o: any, s: number } } = {}
function Preparacao.setScale(k: number)
	escala = k
	for _, e in textos do
		e.o.TextSize = UiKit.textAt(e.s, k)
	end
end

local function quadro(pai: Instance?, x: number, y: number, w: number, h: number, cor: Color3, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = cor
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = pai
	return f
end

local function letra(
	pai: Instance,
	t: string,
	tam: number,
	cor: Color3,
	fonte: Font,
	x: number,
	y: number,
	w: number,
	h: number,
	al: Enum.TextXAlignment?
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.FontFace = fonte
	l.Text = t
	l.TextColor3 = cor
	l.TextXAlignment = al or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.TextSize = UiKit.textAt(tam, escala)
	l.Parent = pai
	table.insert(textos, { o = l, s = tam })
	return l
end

local function imagem(
	pai: Instance,
	url: string,
	x: number,
	y: number,
	w: number,
	h: number,
	crop: boolean?
): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Image = url
	i.ScaleType = if crop then Enum.ScaleType.Crop else Enum.ScaleType.Fit
	i.Position = UDim2.fromOffset(x, y)
	i.Size = UDim2.fromOffset(w, h)
	i.Parent = pai
	return i
end

local function degrade(pai: Instance, rot: number, a: number, b: number, c: number?)
	local f = Instance.new("Frame")
	f.Name = "Sombra"
	f.BackgroundColor3 = Color3.fromRGB(8, 8, 7)
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = pai
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = if c
		then NumberSequence.new({
			NumberSequenceKeypoint.new(0, a),
			NumberSequenceKeypoint.new(0.5, c),
			NumberSequenceKeypoint.new(1, b),
		})
		else NumberSequence.new(a, b)
	g.Parent = f
end

local function botao(pai: Instance?, x: number, y: number, w: number, h: number, cor: Color3, tr: number?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = cor
	b.BackgroundTransparency = tr or 0
	b.BorderSizePixel = 0
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.ClipsDescendants = true
	b.Parent = pai
	return b
end

-- clique, mouse, foco e cursor do controle num só "quente"
local function liga(b: GuiButton, clique: () -> (), quente: ((boolean) -> ())?)
	local over, sel, pad = false, false, false
	local function aplica()
		if quente then
			quente(over or sel or pad)
		end
	end
	b.MouseEnter:Connect(function()
		over = true
		aplica()
	end)
	b.MouseLeave:Connect(function()
		over = false
		aplica()
	end)
	b.SelectionGained:Connect(function()
		sel = true
		aplica()
	end)
	b.SelectionLost:Connect(function()
		sel = false
		aplica()
	end)
	UiKit.bind(b, clique, function(on: boolean)
		pad = on
		aplica()
	end)
end

local function tw(o: Instance, info: TweenInfo, p: { [string]: any })
	TweenService:Create(o, info, p):Play()
end

-- ===== a tela =====
function Preparacao.novo(root: Frame, ctx: Ctx): any
	local view: any = {}

	-- ----- barra de cima -----
	local topo = quadro(root, 0, 0, 1280, 62, Color3.fromRGB(13, 14, 11), 0.04)
	topo.Name = "BarraPassos"
	-- D-228: a barra sobe além do palco (em tela mais alta que 16:9 não sobra faixa do fundo)
	topo.Size = UDim2.new(3, 0, 0, 662)
	topo.Position = UDim2.new(-1, 0, 0, -600)
	quadro(topo, 0, 661, 1280, 1, DOURADO, 0.55).Size = UDim2.new(1, 0, 0, 1)
	local barra = Instance.new("Frame")
	barra.BackgroundTransparency = 1
	barra.Size = UDim2.fromOffset(1280, 62)
	barra.Parent = root
	-- a marca fica depois dos botões do Roblox, no canto
	letra(barra, "STARLITE", 25, V.TEXT, F.TITLE, 156, 7, 170, 30)
	letra(barra, "VIETNÃ 1965", 13, DOURADO, F.TITLE_MED, 157, 36, 170, 18)
	type Passo = { b: TextButton, num: TextLabel, nome: TextLabel, risco: Frame, id: string }
	local passos: { Passo } = {}
	for i, d in Preparacao.PASSOS do
		local w = 172
		local b = botao(barra, 322 + (i - 1) * (w + 4), 0, w, 62, Color3.new(0, 0, 0), 1)
		b.Name = "Passo_" .. d.id
		local n = letra(b, d.num, 20, V.MUTED, F.TITLE, 6, 0, 32, 62, Enum.TextXAlignment.Right)
		local t = letra(b, d.nome, 19, V.DIM, F.TITLE_MED, 44, 0, w - 46, 62)
		local r = quadro(b, 8, 58, w - 16, 3, DOURADO)
		r.Visible = false
		local p: Passo = { b = b, num = n, nome = t, risco = r, id = d.id }
		passos[i] = p
		liga(b, function()
			if d.id == "lado" then
				ctx.abrir("faction")
			else
				ctx.abrir(d.id)
			end
		end, function(on: boolean)
			tw(b, RAPIDO, { BackgroundTransparency = if on then 0.86 else 1 })
		end)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
	end
	local cUS = letra(barra, "", 19, V.US, F.TITLE, 1036, 0, 104, 62, Enum.TextXAlignment.Right)
	local cVC = letra(barra, "", 19, V.VC, F.TITLE, 1150, 0, 104, 62, Enum.TextXAlignment.Right)

	-- ----- barra de baixo -----
	local pe = Instance.new("Frame")
	pe.Name = "BarraBaixo"
	pe.BackgroundTransparency = 1
	pe.Position = UDim2.fromOffset(0, 662)
	pe.Size = UDim2.fromOffset(1280, 58)
	pe.Parent = root
	local peFundo = quadro(pe, 0, 0, 1280, 58, Color3.fromRGB(13, 14, 11), 0.04)
	peFundo.Size = UDim2.new(3, 0, 0, 658)
	peFundo.Position = UDim2.new(-1, 0, 0, 0)
	quadro(peFundo, 0, 0, 1280, 1, DOURADO, 0.55).Size = UDim2.new(1, 0, 0, 1)
	-- D-237 (dono: "adicione um botão para voltar ao menu"): sempre à mão, em todos os passos
	local menu = botao(pe, 24, 8, 112, 42, Color3.fromRGB(34, 36, 30))
	menu.Name = "Menu"
	UiKit.corner(menu, 3)
	UiKit.edge(menu, DOURADO, 1, 0.45)
	letra(menu, "≡  MENU", 19, V.TEXT, F.TITLE_MED, 0, 0, 112, 42, Enum.TextXAlignment.Center)
	liga(menu, function()
		ctx.menu()
	end, function(on: boolean)
		tw(menu, RAPIDO, { BackgroundColor3 = if on then CARTAO_HI else Color3.fromRGB(34, 36, 30) })
	end)
	local voltar = botao(pe, 144, 8, 150, 42, Color3.fromRGB(34, 36, 30))
	voltar.Name = "Voltar"
	UiKit.corner(voltar, 3)
	UiKit.edge(voltar, V.KHAKI, 1, 0.5)
	letra(voltar, "◄  VOLTAR", 19, V.TEXT, F.TITLE_MED, 0, 0, 150, 42, Enum.TextXAlignment.Center)
	liga(voltar, function()
		ctx.voltar()
	end, function(on: boolean)
		tw(voltar, RAPIDO, { BackgroundColor3 = if on then CARTAO_HI else Color3.fromRGB(34, 36, 30) })
	end)
	local resumo = letra(pe, "", 18, V.DIM, F.TITLE_MED, 308, 8, 676, 42)
	local principal = botao(pe, 996, 6, 260, 46, V.AMBAR)
	principal.Name = "Principal"
	UiKit.corner(principal, 3)
	local principalTexto = letra(principal, "", 22, V.AMBAR_TEXTO, F.TITLE, 0, 0, 260, 46, Enum.TextXAlignment.Center)
	local acaoPrincipal: (() -> ())? = nil
	liga(principal, function()
		local fn = acaoPrincipal
		if fn then
			fn()
		end
	end, function(on: boolean)
		tw(principal, RAPIDO, { BackgroundColor3 = if on then V.AMBAR_HI else V.AMBAR })
	end)
	view.pe = pe
	view.resumo = resumo

	-- ----- páginas -----
	local function pagina(nome: string): Frame
		local p = Instance.new("Frame")
		p.Name = nome
		p.BackgroundTransparency = 1
		p.Position = UDim2.fromOffset(0, 66)
		p.Size = UDim2.fromOffset(1280, 594)
		p.Visible = false
		p.Parent = root
		return p
	end
	local pgLado, pgGrupo, pgClasse = pagina("PaginaTime"), pagina("PaginaGrupo"), pagina("PaginaClasse")

	-- ===== 01 TIME =====
	type CTime = {
		b: TextButton,
		im: ImageLabel,
		n: TextLabel,
		tag: TextLabel,
		cta: Frame,
		ctaT: TextLabel,
		borda: UIStroke,
	}
	local cTimes: { [string]: CTime } = {}
	local function cartaoTime(f: string, x: number)
		local info = TIMES[f]
		local b = botao(pgLado, x, 10, 610, 574, PAINEL)
		b.Name = "Time_" .. f
		UiKit.corner(b, 4)
		local borda = UiKit.edge(b, corLado(f), 2, 0.35)
		local im = imagem(b, ArteCatalogo.time(f), -12, -8, 634, 590, true)
		-- D-240: a bandeira ao vento enche o cartão; a sombra fica só embaixo, onde vai o texto
		degrade(b, 90, 0.9, 0.02, 0.6)
		quadro(b, 0, 0, 6, 574, corLado(f))
		letra(b, info.kicker, 19, corLado(f):Lerp(Color3.new(1, 1, 1), 0.35), F.TITLE_MED, 32, 24, 380, 26)
		letra(b, info.titulo, 46, V.TEXT, F.TITLE, 32, 372, 546, 58)
		letra(b, info.linha, 19, V.DIM, F.BODY, 32, 430, 546, 26)
		letra(b, "JOGADORES", 15, V.DIM, F.TITLE_MED, 32, 470, 180, 20)
		local n = letra(b, "", 40, V.TEXT, F.TITLE, 32, 488, 190, 62)
		local tag = letra(b, "", 16, V.TEXT, F.TITLE_MED, 196, 510, 130, 26, Enum.TextXAlignment.Center)
		tag.BackgroundTransparency = 0
		UiKit.corner(tag, 3)
		local cta = quadro(b, 366, 496, 216, 54, V.AMBAR)
		UiKit.corner(cta, 3)
		local ctaT = letra(cta, "", 23, V.AMBAR_TEXTO, F.TITLE, 0, 0, 216, 54, Enum.TextXAlignment.Center)
		cTimes[f] = { b = b, im = im, n = n, tag = tag, cta = cta, ctaT = ctaT, borda = borda }
		liga(b, function()
			ctx.escolherLado(f)
		end, function(on: boolean)
			tw(borda, RAPIDO, { Transparency = if on then 0 else 0.35, Thickness = if on then 3 else 2 })
			tw(im, SUAVE, {
				Size = UDim2.fromOffset(if on then 664 else 634, if on then 618 else 590),
				Position = UDim2.fromOffset(if on then -27 else -12, if on then -22 else -8),
			})
			tw(cta, RAPIDO, { BackgroundColor3 = if on then V.AMBAR_HI else V.AMBAR })
		end)
	end
	cartaoTime("US", 24)
	cartaoTime("VC", 646)

	local function pintaLado()
		local us, vc = ctx.contagem()
		local meu = ctx.lado()
		for f, c in cTimes do
			c.n.Text = string.format("%d/%d", if f == "US" then us else vc, Roles.TEAM_MAX)
			local why = ctx.bloqueioDoLado(f)
			if meu == f then
				c.tag.Text, c.tag.BackgroundColor3 = "SEU LADO", V.OLIVE
				c.ctaT.Text = "CONTINUAR ►"
			elseif why then
				c.tag.Text, c.tag.BackgroundColor3 = why, V.RED
				c.ctaT.Text = "ALISTAR-SE ►"
			else
				c.tag.Text, c.tag.BackgroundColor3 = "ABERTO", V.OLIVE
				c.ctaT.Text = "ALISTAR-SE ►"
			end
		end
	end

	-- ===== 02 GRUPO =====
	letra(pgGrupo, "ESCOLHA O SEU GRUPO", 34, V.TEXT, F.TITLE, 24, 6, 700, 44)
	local grupoSub = letra(pgGrupo, "", 18, V.DIM, F.BODY, 26, 48, 800, 24)
	local lista = Instance.new("ScrollingFrame")
	lista.Name = "Grupos"
	lista.BackgroundTransparency = 1
	lista.BorderSizePixel = 0
	lista.Position = UDim2.fromOffset(20, 78)
	lista.Size = UDim2.fromOffset(846, 512)
	lista.CanvasSize = UDim2.new()
	lista.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lista.ScrollBarThickness = 5
	lista.ScrollBarImageColor3 = V.KHAKI
	lista.Parent = pgGrupo
	local grade = Instance.new("UIGridLayout")
	grade.CellSize = UDim2.fromOffset(412, 188)
	grade.CellPadding = UDim2.fromOffset(10, 10)
	grade.SortOrder = Enum.SortOrder.LayoutOrder
	grade.Parent = lista
	local gPad = Instance.new("UIPadding")
	gPad.PaddingLeft, gPad.PaddingTop = UDim.new(0, 4), UDim.new(0, 4)
	gPad.Parent = lista

	type CGrupo = {
		b: TextButton,
		fundo: ImageLabel,
		nome: TextLabel,
		conta: TextLabel,
		tipo: TextLabel,
		acao: TextLabel,
		acaoF: Frame,
		vagas: { ImageLabel },
		borda: UIStroke,
		fn: (() -> ())?,
	}
	local cGrupos: { [string]: CGrupo } = {}
	local function cartaoGrupo(chave: string): CGrupo
		local b = botao(lista, 0, 0, 412, 188, CARTAO)
		b.Name = "Grupo_" .. chave
		b.ClipsDescendants = true
		UiKit.corner(b, 4)
		local borda = UiKit.edge(b, V.LINE, 1, 0.3)
		-- D-223: a imagem do time atrás do cartão, apagada para o texto ler
		local fundoG = imagem(b, "", 0, 0, 412, 188, true)
		fundoG.ImageTransparency = 0.74
		local tipo = letra(b, "", 15, DOURADO, F.TITLE_MED, 16, 10, 240, 20)
		local nome = letra(b, "", 36, V.TEXT, F.TITLE, 16, 28, 280, 44)
		local conta = letra(b, "", 30, V.TEXT, F.TITLE, 300, 22, 96, 44, Enum.TextXAlignment.Right)
		local vagas: { ImageLabel } = {}
		for i = 1, 6 do
			local o = imagem(b, "", 14 + (i - 1) * 56, 80, 48, 48)
			o.BackgroundTransparency = 0.35
			o.BackgroundColor3 = Color3.fromRGB(14, 15, 12)
			UiKit.corner(o, 24)
			vagas[i] = o
		end
		local acaoF = quadro(b, 12, 140, 388, 38, V.PANEL_3)
		UiKit.corner(acaoF, 3)
		local acao = letra(acaoF, "", 19, V.TEXT, F.TITLE_MED, 0, 0, 388, 38, Enum.TextXAlignment.Center)
		local c: CGrupo = {
			b = b,
			fundo = fundoG,
			nome = nome,
			conta = conta,
			tipo = tipo,
			acao = acao,
			acaoF = acaoF,
			vagas = vagas,
			borda = borda,
			fn = nil,
		}
		liga(b, function()
			local fn = c.fn
			if fn then
				fn()
			end
		end, function(on: boolean)
			tw(b, RAPIDO, { BackgroundColor3 = if on then CARTAO_HI else CARTAO })
			tw(borda, RAPIDO, { Transparency = if on then 0 else 0.3 })
		end)
		cGrupos[chave] = c
		return c
	end

	-- o seu grupo, à direita
	local meuG = quadro(pgGrupo, 878, 10, 378, 574, PAINEL, 0.04)
	UiKit.corner(meuG, 4)
	UiKit.edge(meuG, V.LINE, 1, 0.35)
	meuG.ClipsDescendants = true
	local meuImg = imagem(meuG, "", 0, 0, 378, 196, true)
	do
		local s = Instance.new("Frame")
		s.BackgroundTransparency = 1
		s.Size = UDim2.fromOffset(378, 196)
		s.Parent = meuG
		degrade(s, 90, 1, 0.05)
	end
	local meuK = letra(meuG, "SEU GRUPO", 15, DOURADO, F.TITLE_MED, 18, 142, 340, 20)
	local meuNome = letra(meuG, "", 32, V.TEXT, F.TITLE, 18, 158, 340, 40)
	type LinhaM = { f: Frame, im: ImageLabel, nome: TextLabel, cl: TextLabel }
	local linhasM: { LinhaM } = {}
	for i = 1, 6 do
		local l = quadro(meuG, 12, 204 + (i - 1) * 50, 354, 46, CARTAO)
		UiKit.corner(l, 3)
		local im = imagem(l, "", 4, 3, 40, 40)
		local n = letra(l, "", 18, V.TEXT, F.TITLE_MED, 52, 3, 296, 22)
		local c = letra(l, "", 15, V.DIM, F.BODY, 52, 24, 296, 18)
		linhasM[i] = { f = l, im = im, nome = n, cl = c }
	end
	local sair = botao(meuG, 12, 512, 354, 48, Color3.fromRGB(58, 34, 30))
	sair.Name = "SairDoGrupo"
	UiKit.corner(sair, 3)
	letra(sair, "SAIR DO GRUPO", 19, V.TEXT, F.TITLE_MED, 0, 0, 354, 48, Enum.TextXAlignment.Center)
	liga(sair, function()
		Net.event("Squad_Action"):FireServer({ op = "leave" })
	end, function(on: boolean)
		tw(sair, RAPIDO, { BackgroundColor3 = if on then V.RED else Color3.fromRGB(58, 34, 30) })
	end)

	local function pintaGrupo(f: string, st: any)
		local size: number? = if st and type(st.size) == "number" then st.size else nil
		local squads: { any } = if st and type(st.squads) == "table" then st.squads else {}
		local mySid = player:GetAttribute("SquadId")
		grupoSub.Text = if size
			then string.format(
				"Jogadores %s %d/%d · entre num grupo com vaga ou forme um novo",
				TIMES[f].curto,
				size,
				Roles.TEAM_MAX
			)
			else "Recebendo os grupos do servidor…"
		for _, c in cGrupos do
			c.b.Visible = false
			c.fundo.Image = ArteCatalogo.time(f)
		end
		local ordem = 0
		for _, unit in { "infantry", "command" } do
			local def = Roles.units[f][unit]
			local usados: { [string]: boolean } = {}
			for _, s in squads do
				if s.unit == unit and type(s.id) == "string" then
					usados[s.name] = true
					ordem += 1
					local c = cGrupos[s.id] or cartaoGrupo(s.id)
					c.fundo.Image = ArteCatalogo.time(f)
					c.b.Visible = true
					c.b.LayoutOrder = (table.find(def.names, s.name) or 50) + (if unit == "command" then 100 else 0)
					local membros: { any } = if type(s.members) == "table" then s.members else {}
					local n, cheio, meu = #membros, #membros >= def.size, s.id == mySid
					c.tipo.Text = if unit == "command" then "COMANDO" else "INFANTARIA"
					c.nome.Text = UiKit.upper(tostring(s.name))
					c.conta.Text = string.format("%d/%d", n, def.size)
					for i, o in c.vagas do
						o.Visible = i <= def.size
						local uid = membros[i]
						local rid = if uid and type(s.roles) == "table"
							then s.roles[tostring(uid)] or s.roles[uid]
							else nil
						o.Image = if rid then ArteCatalogo.classe(rid) else ""
						o.BackgroundColor3 = if uid then V.OLIVE else Color3.fromRGB(14, 15, 12)
					end
					c.acao.Text = if meu then "SEU GRUPO ✓" elseif cheio then "CHEIO" else "ENTRAR"
					c.acaoF.BackgroundColor3 = if meu
						then V.OLIVE
						elseif cheio then Color3.fromRGB(44, 40, 36)
						else V.PANEL_3
					c.borda.Color = if meu then DOURADO else V.LINE
					local id = s.id
					c.fn = function()
						if meu then
							ctx.abrir("role")
						elseif cheio then
							ctx.avisar("Grupo cheio: escolha outro ou forme um novo.")
						else
							Net.event("Squad_Action"):FireServer({ op = "join", id = id })
						end
					end
				end
			end
			local proximo: string? = nil
			for _, nm in def.names do
				if not usados[nm] then
					proximo = nm
					break
				end
			end
			if proximo then
				local c = cGrupos["novo:" .. unit] or cartaoGrupo("novo:" .. unit)
				c.fundo.Image = ArteCatalogo.time(f)
				c.b.Visible = true
				c.b.LayoutOrder = if unit == "command" then 200 else 99
				c.tipo.Text = if unit == "command" then "COMANDO" else "NOVO GRUPO"
				c.nome.Text = UiKit.upper(proximo)
				c.conta.Text = string.format("0/%d", def.size)
				for i, o in c.vagas do
					o.Visible = i <= def.size
					o.Image = ""
					o.BackgroundColor3 = Color3.fromRGB(14, 15, 12)
				end
				c.acao.Text = "+ FORMAR"
				c.acaoF.BackgroundColor3 = V.OLIVE
				c.borda.Color = V.OLIVE
				c.fn = function()
					Net.event("Squad_Action"):FireServer({ op = "create", unit = unit })
				end
			end
		end
		-- o painel do seu grupo
		meuImg.Image = ArteCatalogo.time(f)
		local sq = if type(mySid) == "string" then ctx.acharSquad(st, mySid) else nil
		sair.Visible = type(mySid) == "string"
		meuK.Text = if type(mySid) == "string" then "SEU GRUPO" else "SEM GRUPO"
		meuNome.Text = if type(mySid) == "string"
			then UiKit.upper(string.match(mySid, ":(.+)$") or mySid)
			else "ESCOLHA AO LADO"
		local membros: { any } = if sq and type(sq.members) == "table" then sq.members else {}
		for i, l in linhasM do
			local uid = membros[i]
			l.f.Visible = uid ~= nil
			if uid then
				local p = Players:GetPlayerByUserId(uid)
				local rid = if type(sq.roles) == "table" then sq.roles[tostring(uid)] or sq.roles[uid] else nil
				l.nome.Text = if p then p.DisplayName else "Soldado"
				l.cl.Text = if rid and Roles.roles[rid]
					then Roles.roles[rid].name
					else if uid == sq.leader then "Líder · sem classe" else "Sem classe"
				l.im.Image = if rid then ArteCatalogo.classe(rid) else ""
			end
		end
	end

	-- ===== 03 CLASSE =====
	-- a classe sob o cursor fica "vista" (nada vai ao servidor); CONFIRMAR CLASSE é que escolhe
	local vista: string? = nil
	local aba = "principal"
	local armaVista: string? = nil
	local kit: Kit.Kit? = nil
	local stAtual: any = nil
	local pintaClasse: () -> ()

	-- coluna das classes
	local colC = Instance.new("ScrollingFrame")
	colC.Name = "Classes"
	colC.BackgroundColor3 = PAINEL
	colC.BackgroundTransparency = 0.04
	colC.BorderSizePixel = 0
	colC.Position = UDim2.fromOffset(24, 10)
	colC.Size = UDim2.fromOffset(268, 574)
	colC.CanvasSize = UDim2.new()
	colC.AutomaticCanvasSize = Enum.AutomaticSize.Y
	colC.ScrollBarThickness = 4
	colC.Parent = pgClasse
	UiKit.corner(colC, 4)
	local colL = Instance.new("UIListLayout")
	colL.Padding = UDim.new(0, 4)
	colL.SortOrder = Enum.SortOrder.LayoutOrder
	colL.Parent = colC
	local colP = Instance.new("UIPadding")
	colP.PaddingLeft, colP.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	colP.PaddingTop, colP.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	colP.Parent = colC
	type LClasse = { b: TextButton, nome: TextLabel, vaga: TextLabel, risco: Frame, bloqueio: string?, hot: boolean }
	local lClasses: { [string]: LClasse } = {}
	local function linhaClasse(id: string): LClasse
		local b = botao(colC, 0, 0, 254, 74, CARTAO, 1)
		b.Name = "Classe_" .. id
		UiKit.corner(b, 3)
		imagem(b, ArteCatalogo.classe(id), 6, 5, 64, 64)
		local nome = letra(b, UiKit.upper(Roles.roles[id].name), 20, V.TEXT, F.TITLE, 78, 12, 170, 28)
		local vaga = letra(b, "", 15, V.DIM, F.TITLE_MED, 78, 40, 170, 20)
		local risco = quadro(b, 0, 8, 4, 58, DOURADO)
		risco.Visible = false
		local l: LClasse = { b = b, nome = nome, vaga = vaga, risco = risco, bloqueio = nil, hot = false }
		lClasses[id] = l
		liga(b, function()
			vista = id
			armaVista = nil
			pintaClasse()
		end, function(on: boolean)
			l.hot = on
			tw(b, RAPIDO, {
				BackgroundTransparency = if vista == id then 0 elseif on then 0.45 else 1,
			})
		end)
		return l
	end

	-- miolo: abas e a grade
	local miolo = quadro(pgClasse, 300, 10, 584, 574, PAINEL, 0.04)
	UiKit.corner(miolo, 4)
	miolo.ClipsDescendants = true
	type TabC = { b: TextButton, t: TextLabel, r: Frame }
	local abasC: { [string]: TabC } = {}
	for i, d in { { "principal", "ARMA PRINCIPAL" }, { "pistola", "SECUNDÁRIA" }, { "equip", "EQUIPAMENTO" } } do
		local b = botao(miolo, (i - 1) * 194, 0, 196, 50, Color3.new(1, 1, 1), 1)
		b.Name = "Aba_" .. d[1]
		local t = letra(b, d[2], 19, V.DIM, F.TITLE_MED, 0, 0, 196, 50, Enum.TextXAlignment.Center)
		local r = quadro(b, 10, 47, 176, 3, DOURADO)
		abasC[d[1]] = { b = b, t = t, r = r }
		liga(b, function()
			aba = d[1]
			armaVista = nil
			pintaClasse()
		end, function(on: boolean)
			tw(b, RAPIDO, { BackgroundTransparency = if on then 0.9 else 1 })
		end)
	end
	quadro(miolo, 0, 50, 584, 1, V.LINE, 0.4)

	-- cartões de arma (imagem grande)
	type CArma = {
		b: TextButton,
		im: ImageLabel,
		nome: TextLabel,
		sub: TextLabel,
		tag: TextLabel,
		borda: UIStroke,
		id: string?,
	}
	local cArmas: { CArma } = {}
	for i = 1, 4 do
		local x = 10 + ((i - 1) % 2) * 286
		local y = 62 + math.floor((i - 1) / 2) * 254
		local b = botao(miolo, x, y, 278, 246, CARTAO)
		b.Name = "Arma" .. i
		UiKit.corner(b, 4)
		local borda = UiKit.edge(b, V.LINE, 1, 0.35)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 140))
		g.Parent = b
		local im = imagem(b, "", 6, 26, 266, 133)
		local tag = letra(b, "", 14, V.BG, F.TITLE_MED, 176, 8, 94, 22, Enum.TextXAlignment.Center)
		tag.BackgroundColor3 = DOURADO
		tag.BackgroundTransparency = 0
		UiKit.corner(tag, 3)
		local nome = letra(b, "", 23, V.TEXT, F.TITLE, 14, 166, 252, 32)
		local sub = letra(b, "", 16, V.DIM, F.BODY, 14, 198, 252, 34)
		local c: CArma = { b = b, im = im, nome = nome, sub = sub, tag = tag, borda = borda, id = nil }
		cArmas[i] = c
		liga(b, function()
			local id = c.id
			if id and vista then
				armaVista = id
				local lado = ctx.lado()
				if aba == "principal" and lado and table.find(Roles.primaries(lado, vista), id) then
					ctx.trocarPrimaria(vista, id)
				end
				pintaClasse()
			end
		end, function(on: boolean)
			tw(im, SUAVE, {
				Position = UDim2.fromOffset(if on then -2 else 6, if on then 20 else 26),
				Size = UDim2.fromOffset(if on then 282 else 266, if on then 141 else 133),
			})
			if c.id ~= armaVista then
				tw(borda, RAPIDO, { Transparency = if on then 0 else 0.35 })
			end
		end)
	end

	-- linhas do equipamento
	local kitTotal = letra(miolo, "", 18, V.TEXT, F.TITLE_MED, 16, 60, 552, 24)
	local kitTrilho = quadro(miolo, 16, 88, 552, 8, Color3.fromRGB(12, 13, 10))
	UiKit.corner(kitTrilho, 4)
	local kitBarra = quadro(kitTrilho, 0, 0, 0, 8, DOURADO)
	UiKit.corner(kitBarra, 4)
	type LKit = { f: Frame, im: ImageLabel, nome: TextLabel, n: TextLabel, id: string }
	local lKits: { LKit } = {}
	local function mandaKit()
		local k = kit
		if k then
			Net.event("Kit_Set"):FireServer(k)
		end
	end
	local function tipoDaArma(f: string, rid: string): string
		local pid = ctx.primaria(f, rid)
		local lo = Roles.loadoutFor(f, rid, pid)
		local w = if lo then Weapons.get(lo[1]) else nil
		return if w then w.kind else "rifle"
	end
	local function mudaKit(item: string, d: number)
		local f = ctx.lado()
		if not (f and vista and kit) then
			return
		end
		local kind = tipoDaArma(f, vista)
		local novo: any = table.clone(kit :: any)
		novo[item] += d
		local ok = Kit.validate(novo, kind)
		if (ok :: any)[item] == (kit :: any)[item] and d > 0 then
			ctx.avisar("Peso no limite: tire outro item para levar mais.")
			return
		end
		kit = ok
		mandaKit()
		pintaClasse()
	end
	for i, it in Kit.ITEMS do
		local l = quadro(miolo, 10, 106 + (i - 1) * 116, 564, 108, CARTAO)
		UiKit.corner(l, 4)
		local im = imagem(l, "", 6, 4, 100, 100)
		local nome = letra(l, it.name, 24, V.TEXT, F.TITLE, 118, 14, 240, 34)
		letra(
			l,
			if it.kg then string.format("%.2f kg cada", it.kg) else "pelo tipo da arma",
			16,
			V.DIM,
			F.BODY,
			118,
			52,
			240,
			24
		)
		local menos = botao(l, 370, 28, 52, 52, V.PANEL_3)
		UiKit.corner(menos, 3)
		letra(menos, "−", 30, V.TEXT, F.TITLE, 0, 0, 52, 52, Enum.TextXAlignment.Center)
		local n = letra(l, "", 32, V.TEXT, F.TITLE, 424, 28, 62, 52, Enum.TextXAlignment.Center)
		local mais = botao(l, 490, 28, 52, 52, V.OLIVE)
		UiKit.corner(mais, 3)
		letra(mais, "+", 30, V.TEXT, F.TITLE, 0, 0, 52, 52, Enum.TextXAlignment.Center)
		liga(menos, function()
			mudaKit(it.id, -1)
		end)
		liga(mais, function()
			mudaKit(it.id, 1)
		end)
		lKits[i] = { f = l, im = im, nome = nome, n = n, id = it.id }
	end

	-- ficha à direita
	local ficha = quadro(pgClasse, 892, 10, 364, 574, PAINEL, 0.04)
	ficha.Name = "Ficha"
	UiKit.corner(ficha, 4)
	UiKit.edge(ficha, DOURADO, 1, 0.55)
	local fClasseImg = imagem(ficha, "", 14, 12, 64, 64)
	local fClasse = letra(ficha, "", 27, V.TEXT, F.TITLE, 88, 12, 266, 36)
	local fDesc = letra(ficha, "", 16, V.DIM, F.BODY, 88, 46, 266, 40)
	fDesc.TextWrapped = true
	fDesc.TextTruncate = Enum.TextTruncate.None
	fDesc.TextYAlignment = Enum.TextYAlignment.Top
	quadro(ficha, 14, 92, 336, 1, V.LINE, 0.4)
	local fArmaImg = imagem(ficha, "", 8, 100, 348, 174)
	local fArma = letra(ficha, "", 25, V.TEXT, F.TITLE, 16, 274, 336, 32)
	local fCart = letra(ficha, "", 16, DOURADO, F.TITLE_MED, 16, 304, 336, 22)
	type Stat = { key: string, nome: string, un: string, max: number, f: Frame, v: TextLabel }
	local stats: { Stat } = {}
	for i, d in
		{
			{ "muzzleVelocity", "VELOCIDADE", " m/s" },
			{ "rpm", "CADÊNCIA", "/min" },
			{ "magazine", "CARREGADOR", "" },
			{ "massLoadedKg", "PESO", " kg" },
		}
	do
		local y = 336 + (i - 1) * 40
		letra(ficha, d[2], 15, V.DIM, F.TITLE_MED, 16, y, 200, 18)
		local v = letra(ficha, "", 17, V.TEXT, F.TITLE, 200, y - 2, 148, 22, Enum.TextXAlignment.Right)
		local trilho = quadro(ficha, 16, y + 22, 332, 7, Color3.fromRGB(12, 13, 10))
		UiKit.corner(trilho, 3)
		local barraS = quadro(trilho, 0, 0, 0, 7, V.KHAKI)
		barraS.Size = UDim2.fromScale(0, 1)
		UiKit.corner(barraS, 3)
		local max = 1
		for _, w in Weapons.list do
			if w.enabled then
				max = math.max(max, (w :: any)[d[1]] :: number)
			end
		end
		stats[i] = { key = d[1], nome = d[2], un = d[3], max = max, f = barraS, v = v }
	end
	local fAviso = letra(ficha, "", 16, V.AMBAR, F.TITLE_MED, 16, 500, 336, 60)
	fAviso.TextWrapped = true
	fAviso.TextTruncate = Enum.TextTruncate.None
	fAviso.TextYAlignment = Enum.TextYAlignment.Top

	local function pintaFicha(armaId: string?)
		local w = if armaId then Weapons.get(armaId) else nil
		fArmaImg.Image = if armaId then ArteCatalogo.arma(armaId) else ""
		local lado = ctx.lado()
		fArma.Text = if w
			then w.name
			elseif (armaId == "m20" or armaId == "rpg2") and lado then Weapons.LAUNCHER_NAME[lado]
			else "—"
		fCart.Text = if w then tostring(w.cartridge or "") else ""
		for _, s in stats do
			local x = if w then (w :: any)[s.key] :: number else 0
			tw(s.f, SUAVE, { Size = UDim2.fromScale(math.clamp(x / s.max, 0, 1), 1) })
			s.v.Text = if not w
				then "—"
				elseif s.key == "massLoadedKg" then (string.gsub(string.format("%.1f", x), "%.", ",")) .. s.un
				else tostring(math.floor(x + 0.5)) .. s.un
		end
	end

	-- as vagas da classe no grupo (a mesma conta do servidor) e o que impede de escolher
	local function vagaDe(id: string, sq: any): (string, string?)
		local r = Roles.roles[id]
		local max = r.maxPerSquad
		local me = player.UserId
		if id == "squad_leader" and sq and sq.leader ~= me then
			return "SÓ O LÍDER", "SÓ O LÍDER"
		end
		if max then
			local ocupadas = 0
			if sq and type(sq.roles) == "table" then
				for uid, rr in sq.roles do
					if rr == id and tostring(uid) ~= tostring(me) then
						ocupadas += 1
					end
				end
			end
			local livres = max - ocupadas
			if sq and livres <= 0 then
				return "OCUPADA", "OCUPADA"
			end
			return string.format("VAGA %d/%d", math.max(livres, 0), max), nil
		end
		return "LIVRE", nil
	end

	function pintaClasse()
		local f = ctx.lado()
		if not f then
			return
		end
		local sid = player:GetAttribute("SquadId")
		if type(sid) ~= "string" then
			return
		end
		local sq = ctx.acharSquad(stAtual, sid)
		local unit: string? = if sq then sq.unit else ctx.unidadeDoSquad(f, sid)
		local atual = ctx.papelAtual()
		local primeira: string? = nil
		for ordem, id in ORDEM_CLASSES do
			local r = Roles.roles[id]
			local mostra = unit ~= nil and r.unit == unit and Roles.loadout[f][id] ~= nil
			local l = lClasses[id]
			if mostra and not l then
				l = linhaClasse(id)
			end
			if l then
				l.b.Visible = mostra
				l.b.LayoutOrder = ordem
				if mostra then
					local texto, bloq = vagaDe(id, sq)
					l.bloqueio = bloq
					l.vaga.Text = if atual == id then "ATUAL" else texto
					l.vaga.TextColor3 = if atual == id then V.OLIVE_HI elseif bloq then V.RED_HI else V.DIM
					if not primeira and not bloq then
						primeira = id
					end
				end
			end
		end
		if not (vista and lClasses[vista] and lClasses[vista].b.Visible) then
			vista = if atual and lClasses[atual] and lClasses[atual].b.Visible then atual else primeira
		end
		for id, l in lClasses do
			local on = id == vista
			l.risco.Visible = on
			l.b.BackgroundColor3 = CARTAO_HI
			l.b.BackgroundTransparency = if on then 0 elseif l.hot then 0.45 else 1
		end
		local rid = vista
		if not rid then
			return
		end
		local r = Roles.roles[rid]
		fClasseImg.Image = ArteCatalogo.classe(rid)
		fClasse.Text = UiKit.upper(r.name)
		fDesc.Text = Preparacao.DESC[rid] or ""
		local lo = Roles.loadoutFor(f, rid, ctx.primaria(f, rid)) or {}
		local lista2: { string } = {}
		if aba == "principal" then
			lista2 = Roles.primaries(f, rid)
			if rid == "anti_tank" then
				lista2 = { if f == "VC" then "rpg2" else "m20" } -- o lançador (vaga "launcher")
			end
		elseif aba == "pistola" then
			lista2 = { lo[#lo] }
		end
		for k, t in abasC do
			local on = k == aba
			t.r.Visible = on
			t.t.TextColor3 = if on then V.TEXT else V.DIM
		end
		-- principal e secundária: cartões de arma
		local escolhida = if aba == "principal" then ctx.primaria(f, rid) else lo[#lo]
		for i, c in cArmas do
			local id = lista2[i]
			c.b.Visible = aba ~= "equip" and id ~= nil
			c.id = id
			if id then
				local w = Weapons.get(id)
				c.im.Image = ArteCatalogo.arma(id)
				local lancador = id == "m20" or id == "rpg2"
				c.nome.Text = if w then w.name elseif lancador then Weapons.LAUNCHER_NAME[f] else id
				c.sub.Text = if w then tostring(w.cartridge or "") elseif lancador then "Lançador de foguetes" else ""
				local eq = id == escolhida or lancador
				c.tag.Visible = eq
				c.tag.Text = "EQUIPADA"
				c.borda.Color = if eq then DOURADO else V.LINE
				c.borda.Transparency = if eq then 0 else 0.35
				c.borda.Thickness = if eq then 2 else 1
			end
		end
		-- equipamento
		local noEquip = aba == "equip"
		kitTotal.Visible, kitTrilho.Visible = noEquip, noEquip
		local kind = tipoDaArma(f, rid)
		if not kit then
			kit = Kit.validate({
				mags = player:GetAttribute("KitMags"),
				frags = player:GetAttribute("KitFrags"),
				smokes = player:GetAttribute("KitSmokes"),
				bandages = player:GetAttribute("KitBandages"),
			}, kind)
		end
		local k = Kit.validate(kit, kind)
		kit = k
		for _, l in lKits do
			l.f.Visible = noEquip
			if noEquip then
				l.im.Image = ArteCatalogo.itemKit(l.id, f, kind)
				l.n.Text = tostring((k :: any)[l.id])
			end
		end
		if noEquip then
			local peso, lim = Kit.weight(k, kind), Kit.limit(kind)
			kitTotal.Text = string.format("PESO DO EQUIPAMENTO: %.1f de %.1f kg", peso, lim)
			kitBarra.Size = UDim2.new(math.clamp(peso / lim, 0, 1), 0, 1, 0)
		end
		-- ficha: a arma vista, a escolhida ou o lançador
		local mostra = armaVista
		if not mostra or (aba ~= "equip" and not table.find(lista2, mostra)) then
			mostra = if aba == "pistola"
				then lo[#lo]
				elseif rid == "anti_tank" then (if f == "VC" then "rpg2" else "m20")
				else lo[1]
		end
		pintaFicha(mostra)
		local bloq = lClasses[rid].bloqueio
		fAviso.Text = if bloq == "SÓ O LÍDER"
			then "Só o líder do grupo pode ser esta classe."
			elseif bloq then "Já há um soldado nesta classe no grupo."
			elseif rid == atual then "Esta é a sua classe atual."
			elseif atual then "Trocar de classe soma 15 s para nascer."
			else ""
	end

	-- ===== a barra de passos =====
	local function pintaPassos(passo: string, f: string?)
		local ordem = { lado = 1, squad = 2, role = 3, insert = 4 }
		local feito = {
			lado = f ~= nil,
			squad = ctx.temSquad(),
			role = ctx.papelAtual() ~= nil,
			insert = false,
		}
		for _, p in passos do
			local atual = p.id == passo
			p.risco.Visible = atual
			p.risco.BackgroundColor3 = if f then corLado(f):Lerp(DOURADO, 0.6) else DOURADO
			p.nome.TextColor3 = if atual then V.TEXT elseif feito[p.id] then V.KHAKI else V.MUTED
			p.num.TextColor3 = if atual then DOURADO elseif feito[p.id] then V.OLIVE_HI else V.MUTED
			p.num.Text = if feito[p.id] and not atual then "✓" else Preparacao.PASSOS[ordem[p.id]].num
		end
		local us, vc = ctx.contagem()
		cUS.Text = string.format("EUA %d/%d", us, Roles.TEAM_MAX)
		cVC.Text = string.format("VC %d/%d", vc, Roles.TEAM_MAX)
	end

	local paginaAtual: Frame? = nil
	local function mostra(p: Frame?)
		if p == paginaAtual then
			return
		end
		for _, o in { pgLado, pgGrupo, pgClasse } do
			o.Visible = o == p
		end
		paginaAtual = p
		if p then
			-- entra deslizando um pouco
			p.Position = UDim2.fromOffset(0, 80)
			tw(p, SUAVE, { Position = UDim2.fromOffset(0, 66) })
		end
	end

	-- passo: "lado" | "squad" | "role" | "insert"
	function view.render(passo: string, f: string?, st: any, podeVoltar: boolean)
		stAtual = st
		pintaPassos(passo, f)
		voltar.Visible = podeVoltar
		principal.Visible = false
		acaoPrincipal = nil
		resumo.Text = ""
		resumo.Position = UDim2.fromOffset(if podeVoltar then 308 else 148, 8)
		if passo == "lado" then
			mostra(pgLado)
			pintaLado()
			resumo.Text = "Escolha o seu lado para entrar na partida."
			-- D-237: já tem lado (veio olhar): segue sem precisar escolher de novo
			if f then
				principal.Visible = true
				principalTexto.Text = "GRUPO ►"
				principal.BackgroundColor3, principalTexto.TextColor3 = V.AMBAR, V.AMBAR_TEXTO
				acaoPrincipal = function()
					ctx.abrir("squad")
				end
			end
		elseif passo == "squad" and f then
			mostra(pgGrupo)
			pintaGrupo(f, st)
			if ctx.temSquad() then
				principal.Visible = true
				principalTexto.Text = "CLASSE ►"
				principal.BackgroundColor3, principalTexto.TextColor3 = V.AMBAR, V.AMBAR_TEXTO
				acaoPrincipal = function()
					ctx.abrir("role")
				end
			end
		elseif passo == "role" and f then
			mostra(pgClasse)
			pintaClasse()
			local rid = vista
			if rid then
				principal.Visible = true
				local bloq = lClasses[rid] and lClasses[rid].bloqueio
				principalTexto.Text = if rid == ctx.papelAtual() then "ONDE NASCER ►" else "CONFIRMAR CLASSE ►"
				principal.BackgroundColor3 = if bloq then V.PANEL_3 else V.AMBAR
				principalTexto.TextColor3 = if bloq then V.DIM else V.AMBAR_TEXTO
				local nomes: { string } = {}
				local doPapel: { string } = Roles.loadoutFor(f, rid, ctx.primaria(f, rid)) or {}
				for _, id in doPapel do
					local w = Weapons.get(id)
					table.insert(nomes, if w then w.name else id)
				end
				resumo.Text = string.format("%s · %s", Roles.roles[rid].name, table.concat(nomes, " + "))
				acaoPrincipal = function()
					if bloq then
						ctx.avisar(
							if bloq == "SÓ O LÍDER" then "Só o líder do grupo." else "Classe ocupada no grupo."
						)
						return
					end
					ctx.escolherPapel(rid)
					task.delay(0.5, mandaKit)
				end
			end
		else
			mostra(nil)
		end
	end

	function view.resetar()
		paginaAtual = nil
		vista, armaVista = nil, nil
		aba = "principal"
		kit = nil
		for _, o in { pgLado, pgGrupo, pgClasse } do
			o.Visible = false
		end
	end

	return view
end

return Preparacao
