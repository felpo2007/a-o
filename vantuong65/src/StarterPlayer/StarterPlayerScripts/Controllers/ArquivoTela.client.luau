--!strict
-- ARQUIVO MILITAR STARLITE (D-175): a aba ARQUIVO da loja (ShopController manda "arquivo_show" com
-- a área dela). O álbum de todos os cosméticos, por categoria, e as coleções temáticas com prêmio
-- garantido. O catálogo e as origens vêm do Shared/Arquivo; a posse e o resgate, do servidor
-- (Arquivo_Get, Arquivo_Resgatar: o prêmio já está gravado quando a tela mostra).
-- Visual de documento militar (papel, máquina de escrever, carimbo). Nenhum texto diminui quem
-- ainda não tem o item: o que falta aparece apagado, com o caminho para conseguir.
-- Controle: tudo é botão selecionável (A escolhe, B volta). Studio: VT65DevTela = "arquivo".
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Arquivo = require(ReplicatedStorage.Shared.Arquivo) :: any
local Caixas = require(ReplicatedStorage.Shared.Caixas) :: any
local Commerce = require(ReplicatedStorage.Shared.Commerce) :: any
local Conjuntos = require(ReplicatedStorage.Shared.Conjuntos) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression) :: any
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ItemArte = require(script.Parent.ItemArte)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local V, F, px = UiKit.V, UiKit.F, UiKit.px
local player = Players.LocalPlayer
local TYPE = Font.fromEnum(UiKit.TYPE_OLD)
local PAPEL = Color3.fromRGB(214, 202, 168)
local TINTA = Color3.fromRGB(46, 40, 30)
local CARIMBO = Color3.fromRGB(150, 40, 34)

local state: any = nil
local host: Frame? = nil
local root: Frame? = nil
local aba = "colecoes" -- "colecoes" ou o id de uma categoria

-- ===== ajudas =====
local function frame(parent: Instance, size: UDim2, color: Color3?, tr: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.BackgroundColor3 = color or V.PANEL
	f.BackgroundTransparency = if color then tr or 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, s: string, size: number, color: Color3?, font: any?): TextLabel
	local t = UiKit.rotulo(parent, size, color or V.TEXT, font)
	t.Text = s
	t.TextWrapped = true
	return t
end

local function scroll(parent: Instance): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = parent
	return list
end

local function possui(id: string): boolean
	return state ~= nil and state.possui ~= nil and state.possui[id] == true
end

local function nomeCategoria(id: string): string
	for _, c in Arquivo.CATEGORIAS do
		if c.id == id then
			return c.nome
		end
	end
	return id
end

local function nomeCaixa(id: string?): string
	local c = id and Caixas.get(id)
	return if c then c.nome else (id or "?")
end

-- uma linha de "como conseguir" (só o que existe de verdade: caixa paga desligada não aparece)
local function origemTexto(o: any): string?
	if o.tipo == "caixa" then
		if o.paga then
			if not Caixas.PAGAS_LIGADAS then
				return nil
			end
			return if o.temporada
				then string.format("%s (Robux, só na temporada)", nomeCaixa(o.caixa))
				else string.format("%s (Robux)", nomeCaixa(o.caixa))
		end
		return string.format("%s (grátis)", nomeCaixa(o.caixa))
	elseif o.tipo == "troca" then
		return string.format("Troca: %d Fragmentos (aba CAIXAS)", o.custo)
	elseif o.tipo == "compra_direta" then
		return string.format("Compra direta: %s em créditos (aba CAIXAS)", Progression.money(o.preco))
	elseif o.tipo == "intendencia" then
		return string.format("Intendência: %s em créditos", Progression.money(o.preco))
	elseif o.tipo == "robux" then
		return "Compra em Robux na loja"
	elseif o.tipo == "passe" then
		local c = Conjuntos.get(o.passe)
		return string.format("Conjunto %s (Game Pass, compra única)", if c then c.nome else tostring(o.passe))
	elseif o.tipo == "colecao" then
		local c = Arquivo.colecao(o.colecao)
		return string.format("Prêmio da coleção %s", if c then c.nome else tostring(o.colecao))
	end
	return nil
end

-- ===== estado =====
local function fetch(): any
	local ok, s = pcall(function()
		return Net.func("Arquivo_Get"):InvokeServer()
	end)
	if ok and type(s) == "table" and not s.carregando then
		state = s
	end
	return state
end

-- ===== telas por cima =====
local overlays: { [string]: ScreenGui } = {}
local function closeOverlay(name: string)
	local g = overlays[name]
	if g then
		overlays[name] = nil
		if name == "ArquivoItem" then
			ItemArte.soltaSoldado()
		end
		UiKit.closed(name)
		UiKit.release(g)
		g:Destroy()
		if root then
			UiKit.focus(root)
		end
	end
end

local function overlay(name: string, order: number, w: number, h: number): (ScreenGui, Frame)
	closeOverlay(name)
	local g = UiKit.screen("VT65" .. name, order)
	local back = frame(g, UDim2.fromScale(1, 1), V.BG, 0.25)
	back.Active = true
	local panel = frame(g, UDim2.fromOffset(w, h), V.PANEL, 0.02)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Active = true
	UiKit.corner(panel, 4)
	UiKit.edge(panel, V.LINE, 1, 0.3)
	UiKit.fit(g, panel, w, h, 12)
	overlays[name] = g
	UiKit.opened(name, order)
	return g, panel
end

local function closeButton(parent: Instance, name: string)
	local a = UiKit.action(parent, "FECHAR ×", "secondary", function()
		closeOverlay(name)
	end, { h = px(38, 52) })
	a.button.AnchorPoint = Vector2.new(1, 0)
	a.button.Position = UDim2.new(1, -px(14, 20), 0, px(12, 16))
	a.button.Size = UDim2.fromOffset(px(118, 160), px(38, 52))
end

Input.on("ui_back", "press", function()
	for _, name in { "ArquivoPremio", "ArquivoItem" } do
		if overlays[name] and UiKit.backFor(name) then
			closeOverlay(name)
			return
		end
	end
end)

local build: () -> () = function() end

local function equipar(id: string, kind: string)
	local slot = if kind == "plaqueta" then "tag" else "mol"
	local ok, rr = pcall(function()
		return Net.func("Suprimento_Equipar"):InvokeServer({ slot = slot, item = id })
	end)
	Toast.show(if ok and type(rr) == "table" and rr.ok then "No seu cartão." else "Não deu para usar agora.")
end

-- ===== detalhe de um item =====
local function abrirItem(id: string)
	local it = ItemArte.info(id)
	local W, H = px(700, 930), px(470, 620)
	local _, panel = overlay("ArquivoItem", 44, W, H)
	closeButton(panel, "ArquivoItem")
	local S = px(300, 400)
	local quadro = frame(panel, UDim2.fromOffset(S, S), V.PANEL_2, 0)
	quadro.Position = UDim2.fromOffset(px(18, 24), px(60, 80))
	UiKit.corner(quadro, 6)
	UiKit.edge(quadro, ItemArte.corRaridade(it.raridade), 2, 0)
	if not ItemArte.soldado(quadro, id) then
		local box = ItemArte.desenha(quadro, id, S)
		box.Position = UDim2.fromScale(0, 0)
	end
	local x = px(18, 24) + S + px(18, 24)
	local col = frame(panel, UDim2.new(1, -x - px(18, 24), 1, -px(60, 80) - px(16, 20)))
	col.Position = UDim2.fromOffset(x, px(60, 80))
	UiKit.list(col, false, px(6, 8))
	local t = text(panel, UiKit.upper(it.nome or id), px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	t.TextTruncate = Enum.TextTruncate.AtEnd
	local r = ItemArte.raridade(it.raridade)
	local tag = UiKit.tag(
		col,
		string.format("%s · %s", UiKit.upper(r.nome), UiKit.upper(nomeCategoria(Arquivo.categoria(id) or ""))),
		ItemArte.corRaridade(it.raridade),
		px(14, 18)
	)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.LayoutOrder = 1
	local function linha(s: string, ordem: number, cor: Color3?, fonte: any?, alto: number?): TextLabel
		local l = text(col, s, px(14, 18), cor or V.DIM, fonte or F.BODY)
		l.LayoutOrder = ordem
		l.Size = UDim2.new(1, 0, 0, alto or px(20, 26))
		l.TextYAlignment = Enum.TextYAlignment.Top
		return l
	end
	linha(it.desc or "", 2, V.TEXT, F.BODY, px(38, 50))
	linha(
		if possui(id) then "✓ No seu arquivo." else "Ainda não está no seu arquivo.",
		3,
		if possui(id) then V.KHAKI else V.DIM,
		F.BODY_B
	)
	linha("COMO CONSEGUIR", 4, V.KHAKI, F.TITLE_MED)
	local n = 0
	for _, o in Arquivo.origens(id) do
		local s = origemTexto(o)
		if s then
			n += 1
			linha("• " .. s, 4 + n, V.TEXT)
		end
	end
	linha(
		string.format(
			"Compra direta: %s · Grátis jogando: %s",
			if Arquivo.compraDireta(id) then "sim" else "não",
			if Arquivo.gratis(id) then "sim" else "não"
		),
		50,
		V.DIM
	)
	if possui(id) and (it.kind == "plaqueta" or it.kind == "moldura") then
		local usar = UiKit.action(col, "USAR NO CARTÃO", "primary", function()
			equipar(id, it.kind)
		end, { h = px(42, 56) })
		usar.button.LayoutOrder = 60
		usar.button.Size = UDim2.new(0, px(220, 290), 0, px(42, 56))
	end
	UiKit.focus(panel)
end

-- ===== prêmio da coleção (já gravado no servidor) =====
local function telaPremio(c: any, res: any, item: any)
	local W, H = px(560, 740), px(560, 740)
	local _, panel = overlay("ArquivoPremio", 46, W, H)
	panel.BackgroundColor3 = V.BG
	local card = frame(panel, UDim2.fromScale(1, 1))
	UiKit.list(card, false, px(10, 14), Enum.HorizontalAlignment.Center)
	UiKit.pad(card, px(18, 24), px(18, 24), px(30, 40), px(14, 18))
	local selo = text(card, "COLEÇÃO COMPLETA", px(28, 38), CARIMBO, TYPE)
	selo.LayoutOrder = 1
	selo.Size = UDim2.new(1, 0, 0, px(36, 48))
	selo.TextXAlignment = Enum.TextXAlignment.Center
	selo.Rotation = -3
	local nc = text(card, UiKit.upper(c.nome), px(16, 22), V.DIM, F.TITLE_MED)
	nc.LayoutOrder = 2
	nc.Size = UDim2.new(1, 0, 0, px(22, 30))
	nc.TextXAlignment = Enum.TextXAlignment.Center
	local box = ItemArte.desenha(card, item or res.item, px(190, 250))
	box.LayoutOrder = 3
	local it = ItemArte.info(item or res.item)
	local tg =
		UiKit.tag(card, UiKit.upper(ItemArte.raridade(it.raridade).nome), ItemArte.corRaridade(it.raridade), px(16, 22))
	tg.LayoutOrder = 4
	tg.AutomaticSize = Enum.AutomaticSize.X
	local nome = text(card, it.nome or "", px(24, 32), V.TEXT, F.TITLE)
	nome.LayoutOrder = 5
	nome.Size = UDim2.new(1, 0, 0, px(32, 42))
	nome.TextXAlignment = Enum.TextXAlignment.Center
	local extra = {}
	if c.premio.fragmentos > 0 then
		table.insert(extra, string.format("+%d Fragmentos", c.premio.fragmentos))
	end
	if c.premio.creditos > 0 then
		table.insert(extra, string.format("+%s em créditos", Progression.money(c.premio.creditos)))
	end
	local l = text(
		card,
		(if res.repetido then "Você já tinha o item." else "Já está no seu arquivo.")
			.. (if #extra > 0 then " " .. table.concat(extra, " · ") else ""),
		px(15, 20),
		V.KHAKI,
		F.BODY
	)
	l.LayoutOrder = 6
	l.Size = UDim2.new(1, 0, 0, px(40, 54))
	l.TextXAlignment = Enum.TextXAlignment.Center
	local row = frame(card, UDim2.new(1, 0, 0, px(46, 62)))
	row.LayoutOrder = 7
	UiKit.list(row, true, px(12, 16), Enum.HorizontalAlignment.Center)
	if it.kind == "plaqueta" or it.kind == "moldura" then
		local usar = UiKit.action(row, "USAR NO CARTÃO", "primary", function()
			equipar(it.id, it.kind)
			closeOverlay("ArquivoPremio")
		end, { h = px(46, 62) })
		usar.button.Size = UDim2.fromOffset(px(200, 270), px(46, 62))
	end
	local ok = UiKit.action(row, "OK", "secondary", function()
		closeOverlay("ArquivoPremio")
	end, { h = px(46, 62) })
	ok.button.Size = UDim2.fromOffset(px(120, 160), px(46, 62))
	UiKit.focus(row)
end

local function resgatar(c: any)
	local ok, rr = pcall(function()
		return Net.func("Arquivo_Resgatar"):InvokeServer(c.id)
	end)
	if not (ok and type(rr) == "table") then
		Toast.show("Não deu para resgatar agora.")
		return
	end
	if type(rr.estado) == "table" and not rr.estado.carregando then
		state = rr.estado
	end
	if not rr.ok then
		Toast.show(
			if rr.motivo == "resgatada"
				then "Este prêmio já foi resgatado."
				elseif rr.motivo == "incompleta" then "A coleção ainda não está completa."
				else "Não deu para resgatar agora."
		)
		build()
		return
	end
	build()
	telaPremio(c, rr.resultado, rr.item)
end

-- ===== a aba =====
-- miniatura clicável (abre o detalhe); o que falta fica apagado
local function miniatura(parent: Instance, id: string, s: number, ordem: number, tem: boolean)
	local b = Instance.new("TextButton")
	b.Name = "Item_" .. id
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.Size = UDim2.fromOffset(s, s)
	b.LayoutOrder = ordem
	b.Selectable = true
	b.Parent = parent
	local box = ItemArte.desenha(b, id, s)
	box.Position = UDim2.fromScale(0, 0)
	if not tem then
		local veu = frame(box, UDim2.fromScale(1, 1), V.BG, 0.45)
		veu.Name = "Falta"
		veu.ZIndex = 5
		UiKit.corner(veu, 6)
	end
	UiKit.bind(b, function()
		abrirItem(id)
	end)
end

local function pagColecoes(area: Frame)
	local list = scroll(area)
	UiKit.list(list, false, px(8, 10))
	-- largura de verdade da área (a loja muda de tamanho com a tela): as miniaturas quebram linha
	local larg = area.AbsoluteSize.X
	if larg < 100 then
		larg = px(560, 740)
	end
	local cardW = larg - px(10, 14) - px(8, 10)
	local direita = px(156, 206) -- coluna do prêmio
	local margem = px(12, 16)
	local esq = cardW - direita - margem * 2 - px(8, 10) -- largura do texto e das miniaturas
	local s = px(52, 68)
	local gap = px(6, 8)
	local porLinha = math.max(1, math.floor((esq + gap) / (s + gap)))
	for i, c in Arquivo.COLECOES do
		local st = (state.colecoes or {})[c.id] or { tem = 0, total = #c.itens, completa = false, resgatada = false }
		local ids: { { id: string, tem: boolean } } = {}
		if c.colecoes then
			-- no arquivo completo, os prêmios das outras coleções (aceso = coleção completa)
			for _, sub in c.colecoes do
				local sc = Arquivo.colecao(sub)
				local sst = (state.colecoes or {})[sub]
				if sc then
					table.insert(ids, { id = sc.premio.item, tem = sst ~= nil and sst.completa == true })
				end
			end
		else
			for _, id in c.itens do
				table.insert(ids, { id = id, tem = possui(id) })
			end
		end
		local linhas = math.ceil(#ids / porLinha)
		local topoMinis = px(84, 110)
		local altEsq = topoMinis + linhas * (s + gap) + px(6, 8)
		local altDir = px(186, 246)
		local card = frame(list, UDim2.new(1, -px(10, 14), 0, math.max(altEsq, altDir)), V.PANEL_2, 0)
		card.LayoutOrder = i
		card.Name = "Colecao_" .. c.id
		UiKit.corner(card, 4)
		UiKit.edge(card, if st.completa then V.BRASS else V.LINE, 1, if st.completa then 0 else 0.4)
		local nm = text(card, UiKit.upper(c.nome), px(16, 22), V.KHAKI, TYPE)
		nm.Position = UDim2.fromOffset(margem, px(8, 10))
		nm.Size = UDim2.fromOffset(esq, px(26, 34))
		-- tela estreita: o título encolhe para caber inteiro (conferido no Studio, D-175)
		nm.TextWrapped = false
		nm.TextScaled = true
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = px(16, 22)
		lim.MinTextSize = 9
		lim.Parent = nm
		local ds = text(card, c.desc, px(13, 17), V.DIM, F.BODY)
		ds.Position = UDim2.fromOffset(margem, px(32, 42))
		ds.Size = UDim2.fromOffset(esq, px(30, 40)) -- até duas linhas
		ds.TextYAlignment = Enum.TextYAlignment.Top
		-- barra de progresso
		local numW = px(70, 92)
		local bar = frame(card, UDim2.fromOffset(math.max(20, esq - numW - px(8, 10)), px(8, 11)), V.PANEL, 0)
		bar.Position = UDim2.fromOffset(margem, px(68, 90))
		UiKit.corner(bar, 4)
		local fill = frame(bar, UDim2.fromScale(if st.total > 0 then st.tem / st.total else 0, 1), V.OLIVE_HI, 0)
		UiKit.corner(fill, 4)
		local pr = text(card, string.format("%d de %d", st.tem, st.total), px(13, 17), V.TEXT, F.TITLE_MED)
		pr.Position = UDim2.fromOffset(margem + esq - numW, px(62, 82))
		pr.Size = UDim2.fromOffset(numW, px(20, 26))
		pr.TextXAlignment = Enum.TextXAlignment.Right
		-- miniaturas em grade (quebram linha)
		local grade = frame(card, UDim2.fromOffset(esq, linhas * (s + gap)))
		grade.Position = UDim2.fromOffset(margem, topoMinis)
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(s, s)
		gl.CellPadding = UDim2.fromOffset(gap, gap)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grade
		for j, e in ids do
			miniatura(grade, e.id, s, j, e.tem)
		end
		-- o prêmio, na coluna da direita
		local col = frame(card, UDim2.new(0, direita, 1, -px(16, 20)))
		col.AnchorPoint = Vector2.new(1, 0)
		col.Position = UDim2.new(1, -px(8, 10), 0, px(8, 10))
		local pt = text(col, "PRÊMIO GARANTIDO", px(11, 14), V.DIM, F.TITLE_MED)
		pt.Size = UDim2.new(1, 0, 0, px(16, 20))
		local ps = px(58, 76)
		local pb = Instance.new("Frame")
		pb.BackgroundTransparency = 1
		pb.Size = UDim2.fromOffset(ps, ps)
		pb.Position = UDim2.fromOffset(0, px(18, 24))
		pb.Parent = col
		miniatura(pb, c.premio.item, ps, 1, st.resgatada == true)
		local pinfo = ItemArte.info(c.premio.item)
		local extras = {}
		if c.premio.fragmentos > 0 then
			table.insert(extras, string.format("+%d Fragmentos", c.premio.fragmentos))
		end
		if c.premio.creditos > 0 then
			table.insert(extras, string.format("+%s em créditos", Progression.money(c.premio.creditos)))
		end
		local bonus = text(col, table.concat(extras, "\n"), px(12, 15), V.KHAKI, F.BODY_B)
		bonus.Position = UDim2.fromOffset(ps + px(6, 8), px(18, 24))
		bonus.Size = UDim2.new(1, -ps - px(6, 8), 0, ps)
		bonus.TextYAlignment = Enum.TextYAlignment.Center
		local pn = text(col, pinfo.nome or c.premio.item, px(12, 15), V.TEXT, F.BODY)
		pn.Position = UDim2.fromOffset(0, px(18, 24) + ps + px(4, 6))
		pn.Size = UDim2.new(1, 0, 0, px(32, 42))
		pn.TextYAlignment = Enum.TextYAlignment.Top
		local label = if st.resgatada
			then "RESGATADO"
			elseif st.completa then "RESGATAR PRÊMIO"
			else string.format("AINDA FALTAM %d", math.max(0, st.total - st.tem))
		local a = UiKit.action(
			col,
			label,
			if st.completa and not st.resgatada then "premio" else "secondary",
			function()
				resgatar(c)
			end,
			{ h = px(40, 54) }
		)
		a.button.Name = "Resgatar_" .. c.id
		a.button.AnchorPoint = Vector2.new(0, 1)
		a.button.Position = UDim2.new(0, 0, 1, 0)
		a.button.Size = UDim2.new(1, 0, 0, px(40, 54))
		a.enabled(st.completa == true and not st.resgatada and not state.desligado)
	end
end

-- ===== conjuntos em Game Pass (D-176): itens novos e exclusivos, só visuais, compra única =====
local precos: { [number]: number } = {}
local function precoPasse(id: number): number?
	if id == 0 then
		return nil
	end
	if precos[id] then
		return precos[id]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.GamePass)
	end)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		precos[id] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

local function pagConjuntos(area: Frame)
	local list = scroll(area)
	UiKit.list(list, false, px(8, 10))
	local nota = text(
		list,
		"Compra única em Robux, permanente. Só visual: nada muda o combate. Os itens não saem de caixa.",
		px(13, 17),
		V.DIM,
		F.BODY
	)
	nota.LayoutOrder = 0
	nota.Size = UDim2.new(1, -px(10, 14), 0, px(34, 44))
	local larg = area.AbsoluteSize.X
	if larg < 100 then
		larg = px(560, 740)
	end
	local cardW = larg - px(10, 14) - px(8, 10)
	local direita = px(156, 206)
	local margem = px(12, 16)
	local esq = cardW - direita - margem * 2 - px(8, 10)
	local s = px(52, 68)
	local gap = px(6, 8)
	local porLinha = math.max(1, math.floor((esq + gap) / (s + gap)))
	for i, c in Conjuntos.LISTA do
		local tem = state.conjuntos ~= nil and state.conjuntos[c.key] == true
		local linhas = math.ceil(#c.itens / porLinha)
		local topoMinis = px(102, 132)
		local alt = math.max(topoMinis + linhas * (s + gap) + px(6, 8), px(150, 198))
		local card = frame(list, UDim2.new(1, -px(10, 14), 0, alt), V.PANEL_2, 0)
		card.LayoutOrder = i
		card.Name = "Conjunto_" .. c.key
		UiKit.corner(card, 4)
		UiKit.edge(card, if tem then V.BRASS else V.LINE, 1, if tem then 0 else 0.4)
		local nm = text(card, UiKit.upper(c.nome), px(16, 22), V.KHAKI, TYPE)
		nm.Position = UDim2.fromOffset(margem, px(8, 10))
		nm.Size = UDim2.fromOffset(esq, px(26, 34))
		nm.TextWrapped = false
		nm.TextScaled = true
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = px(16, 22)
		lim.MinTextSize = 9
		lim.Parent = nm
		local ds = text(card, c.desc, px(13, 17), V.DIM, F.BODY)
		ds.Position = UDim2.fromOffset(margem, px(34, 44))
		ds.Size = UDim2.fromOffset(esq, px(64, 84)) -- até quatro linhas
		ds.TextYAlignment = Enum.TextYAlignment.Top
		local grade = frame(card, UDim2.fromOffset(esq, linhas * (s + gap)))
		grade.Position = UDim2.fromOffset(margem, topoMinis)
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(s, s)
		gl.CellPadding = UDim2.fromOffset(gap, gap)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grade
		for j, id in c.itens do
			miniatura(grade, id, s, j, tem)
		end
		local col = frame(card, UDim2.new(0, direita, 1, -px(16, 20)))
		col.AnchorPoint = Vector2.new(1, 0)
		col.Position = UDim2.new(1, -px(8, 10), 0, px(8, 10))
		local id = tonumber((Commerce.IDS :: any)[c.key]) or 0
		local label = if tem then "NO SEU ARQUIVO" elseif id == 0 then "EM BREVE" else "COMPRAR"
		local a = UiKit.action(col, label, if tem or id == 0 then "secondary" else "robux", function()
			if tem or id == 0 then
				return
			end
			Net.event("Commerce_Track"):FireServer("prompt", c.key)
			MarketplaceService:PromptGamePassPurchase(player, id)
		end, { h = px(44, 58) })
		a.button.Name = "Comprar_" .. c.key
		a.button.AnchorPoint = Vector2.new(0, 1)
		a.button.Position = UDim2.new(0, 0, 1, 0)
		a.button.Size = UDim2.new(1, 0, 0, px(44, 58))
		a.enabled(not tem and id ~= 0)
		local pr = text(col, if tem then "✓ Já é seu" else "", px(14, 18), V.KHAKI, F.TITLE_MED)
		pr.Size = UDim2.new(1, 0, 0, px(22, 28))
		pr.TextXAlignment = Enum.TextXAlignment.Center
		if not tem and id ~= 0 then
			task.spawn(function()
				local v = precoPasse(id)
				if v and a.button.Parent then
					a.label.Text = string.format("COMPRAR · %s", UiKit.robux(v))
					pr.Text = "Preço lido do Roblox (pode variar por região)"
				end
			end)
		end
	end
end

local function pagCategoria(area: Frame, cat: string)
	local list = scroll(area)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(px(128, 170), px(176, 234))
	grid.CellPadding = UDim2.fromOffset(px(8, 10), px(8, 10))
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	local n = 0
	for _, id in Arquivo.itens() do
		if Arquivo.categoria(id) == cat then
			n += 1
			local tem = possui(id)
			local cel = frame(list, UDim2.fromScale(1, 1), V.PANEL_2, 0.4)
			cel.LayoutOrder = n
			cel.Name = "Cel_" .. id
			UiKit.corner(cel, 4)
			local s = px(116, 154)
			local mini = Instance.new("Frame")
			mini.BackgroundTransparency = 1
			mini.Size = UDim2.fromOffset(s, s)
			mini.Position = UDim2.fromOffset(px(6, 8), px(6, 8))
			mini.Parent = cel
			miniatura(mini, id, s, 1, tem)
			local it = ItemArte.info(id)
			local nm = text(cel, it.nome or id, px(12, 15), V.TEXT, F.BODY)
			nm.Position = UDim2.fromOffset(px(6, 8), s + px(8, 10))
			nm.Size = UDim2.new(1, -px(12, 16), 0, px(32, 42))
			nm.TextYAlignment = Enum.TextYAlignment.Top
			local stx = text(cel, if tem then "✓ NO ARQUIVO" else "", px(11, 14), V.KHAKI, F.TITLE_MED)
			stx.AnchorPoint = Vector2.new(0, 1)
			stx.Position = UDim2.new(0, px(6, 8), 1, -px(4, 6))
			stx.Size = UDim2.new(1, -px(12, 16), 0, px(16, 20))
		end
	end
end

build = function()
	local h = host
	if not h then
		return
	end
	if root then
		root:Destroy()
	end
	local r = frame(h, UDim2.fromScale(1, 1))
	r.Name = "ArquivoTela"
	root = r
	if not state then
		local t = text(r, "Abrindo o arquivo…", px(16, 22), V.DIM, F.BODY)
		t.Size = UDim2.new(1, 0, 0, px(40, 54))
		return
	end
	-- cabeçalho de papel
	local itens = Arquivo.itens()
	local temN = 0
	for _, id in itens do
		if possui(id) then
			temN += 1
		end
	end
	local completas = 0
	for _, c in Arquivo.COLECOES do
		local st = (state.colecoes or {})[c.id]
		if st and st.completa then
			completas += 1
		end
	end
	local top = frame(r, UDim2.new(1, 0, 0, px(58, 78)), PAPEL, 0)
	UiKit.corner(top, 3)
	local t = text(top, "ARQUIVO MILITAR STARLITE", px(24, 32), TINTA, TYPE)
	t.Position = UDim2.fromOffset(px(14, 18), px(4, 6))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(30, 40))
	local sub = text(
		top,
		string.format(
			"Coleções completas: %d de %d · Itens no arquivo: %d de %d",
			completas,
			#Arquivo.COLECOES,
			temN,
			#itens
		),
		px(13, 17),
		TINTA,
		F.BODY
	)
	sub.Position = UDim2.fromOffset(px(14, 18), px(34, 46))
	sub.Size = UDim2.new(1, -px(170, 230), 0, px(18, 24))
	local carimbo = frame(top, UDim2.fromOffset(px(140, 186), px(38, 50)))
	carimbo.AnchorPoint = Vector2.new(1, 0.5)
	carimbo.Position = UDim2.new(1, -px(14, 18), 0.5, 0)
	carimbo.Rotation = -6
	UiKit.edge(carimbo, CARIMBO, 2, 0)
	local ct = text(carimbo, "STARLITE · 1965", px(15, 20), CARIMBO, TYPE)
	ct.Size = UDim2.fromScale(1, 1)
	ct.TextXAlignment = Enum.TextXAlignment.Center
	-- abas da esquerda
	local topo = px(68, 90)
	local navW = px(200, 266)
	local nav = frame(r, UDim2.new(0, navW, 1, -topo))
	nav.Position = UDim2.fromOffset(0, topo)
	UiKit.list(nav, false, px(6, 8))
	local function botao(id: string, nome: string, conta: string, ordem: number)
		local a = UiKit.action(
			nav,
			string.format("%s  %s", nome, conta),
			if aba == id then "primary" else "secondary",
			function()
				aba = id
				build()
			end,
			{ h = px(42, 56) }
		)
		a.button.Name = "Aba_" .. id
		a.button.LayoutOrder = ordem
		a.button.Size = UDim2.new(1, 0, 0, px(42, 56))
	end
	botao("colecoes", "COLEÇÕES", string.format("%d/%d", completas, #Arquivo.COLECOES), 1)
	local temC = 0
	for _, c in Conjuntos.LISTA do
		if state.conjuntos and state.conjuntos[c.key] then
			temC += 1
		end
	end
	botao("conjuntos", "CONJUNTOS", string.format("%d/%d", temC, #Conjuntos.LISTA), 50)
	for i, c in Arquivo.CATEGORIAS do
		local tot, tem = 0, 0
		for _, id in itens do
			if Arquivo.categoria(id) == c.id then
				tot += 1
				if possui(id) then
					tem += 1
				end
			end
		end
		botao(c.id, UiKit.upper(c.nome), string.format("%d/%d", tem, tot), i + 1)
	end
	local area = frame(r, UDim2.new(1, -navW - px(10, 14), 1, -topo))
	area.Position = UDim2.fromOffset(navW + px(10, 14), topo)
	if aba == "colecoes" then
		pagColecoes(area)
	elseif aba == "conjuntos" then
		pagConjuntos(area)
	else
		pagCategoria(area, aba)
	end
	UiKit.focus(r)
end

local function refresh()
	task.spawn(function()
		fetch()
		if host and host.Visible then
			build()
		end
	end)
end

-- D-176: outra tela pede uma página (a Intendência abre os conjuntos)
Bus.on("arquivo_aba", function(id: string)
	if type(id) == "string" then
		aba = id
	end
end)
-- compra de um conjunto: o servidor grava os itens; relê o álbum
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, _id: number, ok: boolean)
	if who == player and ok then
		task.delay(1.5, refresh)
	end
end)

Bus.on("arquivo_show", function(h: Frame)
	host = h
	build()
	refresh()
end)
Bus.on("arquivo_hide", function()
	for name in table.clone(overlays) do
		closeOverlay(name)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "arquivo" then
			Bus.fire("shop_open", "arquivo")
		end
	end)
end
