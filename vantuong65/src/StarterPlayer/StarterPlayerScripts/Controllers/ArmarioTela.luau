--!strict
-- D-225 (dono: "melhore o armário", com a referência do outro jogo: categorias à esquerda, grade de
-- imagens no meio e a ficha do item à direita). Cinco categorias: ARMAS (a principal de cada classe),
-- ACABAMENTOS, UNIFORMES, CAMUFLAGEM e COMEMORAÇÃO. Três estados que não se confundem:
--   - em foco: o cartão sob o cursor (só acende);
--   - selecionado: o que a ficha mostra;
--   - equipado: a etiqueta EQUIPADO (o que vai para a partida).
-- Comprar continua na INTENDÊNCIA e nos conjuntos do ARQUIVO; aqui, o botão leva até lá.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local ArteCatalogo = require(script.Parent.ArteCatalogo)
local ItemArte = require(script.Parent.ItemArte)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local px = UiKit.px

local ArmarioTela = {}

export type Ctx = {
	lado: () -> string,
	trocarLado: (f: string) -> (),
	comemoracoes: (f: string) -> GuiObject,
	cosmeticos: (f: string) -> { { id: string, nome: string, slot: string, eq: boolean } },
	equiparCosmetico: (f: string, slot: string, id: string) -> (),
	irIntendencia: () -> (),
	irConjuntos: () -> (),
}

ArmarioTela.CATEGORIAS = {
	{ id = "armas", nome = "ARMAS" },
	{ id = "acabamentos", nome = "ACABAMENTOS" },
	{ id = "uniformes", nome = "UNIFORMES" },
	{ id = "camuflagem", nome = "CAMUFLAGEM" },
	{ id = "visuais", nome = "VISUAIS" },
	{ id = "comemoracao", nome = "COMEMORAÇÃO" },
}
local NOME_SLOT = { helmet = "CAPACETE", uniform = "UNIFORME", extra = "ACESSÓRIO" } :: { [string]: string }
local PAPEIS = { "rifleman", "squad_leader", "medic", "support", "machine_gunner", "commander", "sniper" }
local DOURADO = Color3.fromRGB(226, 178, 74)
local CARTAO = Color3.fromRGB(32, 35, 28)
local CARTAO_HI = Color3.fromRGB(50, 54, 40)
local RAPIDO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function icone(cat: string): string
	if cat == "armas" then
		return ArteCatalogo.arma("m14")
	elseif cat == "acabamentos" then
		return ArteCatalogo.arma("m16")
	elseif cat == "uniformes" then
		return ArteCatalogo.classe("rifleman")
	elseif cat == "camuflagem" then
		return ArteCatalogo.classe("sniper")
	elseif cat == "visuais" then
		return ArteCatalogo.classe("medic")
	end
	return ArteCatalogo.classe("squad_leader")
end

local function quadro(pai: Instance?, cor: Color3, tr: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = cor
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.Parent = pai
	return f
end

local function letra(pai: Instance, t: string, tam: number, cor: Color3, fonte: Font): TextLabel
	local l = UiKit.rotulo(pai, tam, cor, fonte)
	l.Text = t
	l.BackgroundTransparency = 1
	l.TextTruncate = Enum.TextTruncate.AtEnd
	return l
end

local function botao(pai: Instance?, cor: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = cor
	b.BorderSizePixel = 0
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.ClipsDescendants = true
	b.Parent = pai
	UiKit.corner(b, 4)
	return b
end

local function liga(b: GuiButton, clique: () -> (), quente: ((boolean) -> ())?)
	UiKit.bind(b, clique, quente)
	if quente then
		b.MouseEnter:Connect(function()
			quente(true)
		end)
		b.MouseLeave:Connect(function()
			quente(false)
		end)
		b.SelectionGained:Connect(function()
			quente(true)
		end)
		b.SelectionLost:Connect(function()
			quente(false)
		end)
	end
end

function ArmarioTela.novo(pagina: ScrollingFrame, ctx: Ctx): any
	pagina.AutomaticCanvasSize = Enum.AutomaticSize.None
	pagina.CanvasSize = UDim2.new()
	pagina.ScrollingEnabled = false
	local raiz = quadro(pagina, V.BG, 1)
	raiz.Name = "ArmarioNovo"
	raiz.Size = UDim2.new(1, -px(12, 16), 1, -px(10, 14))

	local COL, FICHA, GAP = px(190, 256), px(316, 420), px(10, 14)

	-- ----- categorias -----
	local col = quadro(raiz, Color3.fromRGB(20, 22, 18), 0.04)
	col.Name = "Categorias"
	col.Size = UDim2.new(0, COL, 1, 0)
	UiKit.corner(col, 4)
	local ladoB: { [string]: { b: TextButton, t: TextLabel } } = {}
	for i, f in { "US", "VC" } do
		local b = botao(col, CARTAO)
		b.Name = "Lado_" .. f
		b.Position = UDim2.new((i - 1) * 0.5, px(6, 8), 0, px(6, 8))
		b.Size = UDim2.new(0.5, -px(9, 12), 0, px(38, 50))
		local t = letra(b, if f == "US" then "EUA" else "VC", px(19, 25), V.TEXT, F.TITLE)
		t.Size = UDim2.fromScale(1, 1)
		t.TextXAlignment = Enum.TextXAlignment.Center
		ladoB[f] = { b = b, t = t }
		liga(b, function()
			ctx.trocarLado(f)
		end)
	end
	local catB: { [string]: { b: TextButton, r: Frame, t: TextLabel } } = {}
	local cat = "armas"
	local sub: string? = nil
	local sel: string? = nil
	local render: () -> ()
	for i, d in ArmarioTela.CATEGORIAS do
		local b = botao(col, CARTAO)
		b.Name = "Cat_" .. d.id
		b.BackgroundTransparency = 1
		b.Position = UDim2.fromOffset(px(6, 8), px(50, 66) + (i - 1) * px(68, 90))
		b.Size = UDim2.new(1, -px(12, 16), 0, px(64, 85))
		local im = Instance.new("ImageLabel")
		im.BackgroundTransparency = 1
		im.Image = icone(d.id)
		im.ScaleType = Enum.ScaleType.Fit
		im.Position = UDim2.fromOffset(px(8, 10), px(2, 3))
		im.Size = UDim2.new(1, -px(16, 20), 0, px(38, 50))
		im.Parent = b
		local t = letra(b, d.nome, px(17, 23), V.DIM, F.TITLE_MED)
		t.Position = UDim2.new(0, 0, 1, -px(24, 32))
		t.Size = UDim2.new(1, 0, 0, px(22, 30))
		t.TextXAlignment = Enum.TextXAlignment.Center
		local r = quadro(b, DOURADO)
		r.Position = UDim2.fromOffset(0, px(8, 10))
		r.Size = UDim2.new(0, px(4, 5), 1, -px(16, 20))
		catB[d.id] = { b = b, r = r, t = t }
		liga(b, function()
			if cat ~= d.id then
				cat, sub, sel = d.id, nil, nil
				render()
			end
		end, function(on: boolean)
			if cat ~= d.id then
				TweenService:Create(b, RAPIDO, { BackgroundTransparency = if on then 0.4 else 1 }):Play()
			end
		end)
	end

	-- ----- miolo -----
	local miolo = quadro(raiz, V.BG, 1)
	miolo.Name = "Miolo"
	miolo.Position = UDim2.fromOffset(COL + GAP, 0)
	miolo.Size = UDim2.new(1, -(COL + FICHA + 2 * GAP), 1, 0)
	local chips = Instance.new("ScrollingFrame")
	chips.Name = "Filtro"
	chips.BackgroundTransparency = 1
	chips.BorderSizePixel = 0
	chips.Size = UDim2.new(1, 0, 0, px(44, 58))
	chips.CanvasSize = UDim2.new()
	chips.AutomaticCanvasSize = Enum.AutomaticSize.X
	chips.ScrollBarThickness = 3
	chips.ScrollingDirection = Enum.ScrollingDirection.X
	chips.Parent = miolo
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.Padding = UDim.new(0, px(6, 8))
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = chips
	local grade = Instance.new("ScrollingFrame")
	grade.Name = "Grade"
	grade.BackgroundTransparency = 1
	grade.BorderSizePixel = 0
	grade.Position = UDim2.fromOffset(0, px(50, 66))
	grade.Size = UDim2.new(1, 0, 1, -px(50, 66))
	grade.CanvasSize = UDim2.new()
	grade.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grade.ScrollBarThickness = px(5, 7)
	grade.ScrollBarImageColor3 = V.KHAKI
	grade.Parent = miolo
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -px(8, 10), 0, px(178, 236))
	gl.CellPadding = UDim2.fromOffset(px(8, 10), px(8, 10))
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grade
	UiKit.pad(grade, px(2, 3), px(8, 10), px(2, 3), px(4, 6))
	local vazio = letra(miolo, "", px(17, 23), V.DIM, F.BODY)
	vazio.Name = "Vazio"
	vazio.Position = UDim2.fromOffset(px(8, 10), px(60, 80))
	vazio.Size = UDim2.new(1, -px(16, 20), 0, px(60, 80))
	vazio.TextWrapped = true
	vazio.TextTruncate = Enum.TextTruncate.None
	vazio.Visible = false
	-- o bloco das comemorações (prévia e lista) ocupa o miolo e a ficha
	local hostCom = quadro(raiz, V.BG, 1)
	hostCom.Name = "Comemoracoes"
	hostCom.Position = UDim2.fromOffset(COL + GAP, 0)
	hostCom.Size = UDim2.new(1, -(COL + GAP), 1, 0)
	hostCom.Visible = false

	-- ----- ficha -----
	local ficha = quadro(raiz, Color3.fromRGB(20, 22, 18), 0.04)
	ficha.Name = "Ficha"
	ficha.AnchorPoint = Vector2.new(1, 0)
	ficha.Position = UDim2.fromScale(1, 0)
	ficha.Size = UDim2.new(0, FICHA, 1, 0)
	ficha.ClipsDescendants = true
	UiKit.corner(ficha, 4)
	UiKit.edge(ficha, DOURADO, 1, 0.55)
	local pv = quadro(ficha, Color3.fromRGB(28, 30, 24))
	pv.Name = "Previa"
	pv.Position = UDim2.fromOffset(px(10, 14), px(10, 14))
	pv.Size = UDim2.new(1, -px(20, 28), 0, px(250, 332))
	pv.ClipsDescendants = true
	UiKit.corner(pv, 4)
	local pvImg = Instance.new("ImageLabel")
	pvImg.BackgroundTransparency = 1
	pvImg.ScaleType = Enum.ScaleType.Fit
	pvImg.Size = UDim2.fromScale(1, 1)
	pvImg.Parent = pv
	local fTipo = letra(ficha, "", px(15, 20), DOURADO, F.TITLE_MED)
	fTipo.Position = UDim2.fromOffset(px(14, 18), px(268, 356))
	fTipo.Size = UDim2.new(1, -px(28, 36), 0, px(20, 26))
	local fNome = letra(ficha, "", px(26, 35), V.TEXT, F.TITLE)
	fNome.Position = UDim2.fromOffset(px(14, 18), px(288, 382))
	fNome.Size = UDim2.new(1, -px(28, 36), 0, px(36, 48))
	local fDesc = letra(ficha, "", px(16, 21), V.DIM, F.BODY)
	fDesc.Position = UDim2.fromOffset(px(14, 18), px(326, 432))
	fDesc.Size = UDim2.new(1, -px(28, 36), 0, px(70, 94))
	fDesc.TextWrapped = true
	fDesc.TextTruncate = Enum.TextTruncate.None
	fDesc.TextYAlignment = Enum.TextYAlignment.Top
	local fEstado = letra(ficha, "", px(16, 21), V.OLIVE_HI, F.TITLE_MED)
	fEstado.AnchorPoint = Vector2.new(0, 1)
	fEstado.Position = UDim2.new(0, px(14, 18), 1, -px(66, 86))
	fEstado.Size = UDim2.new(1, -px(28, 36), 0, px(22, 30))
	local fBotao = botao(ficha, V.AMBAR)
	fBotao.Name = "Acao"
	fBotao.AnchorPoint = Vector2.new(0, 1)
	fBotao.Position = UDim2.new(0, px(12, 16), 1, -px(12, 16))
	fBotao.Size = UDim2.new(1, -px(24, 32), 0, px(48, 64))
	local fBotaoT = letra(fBotao, "", px(21, 28), V.AMBAR_TEXTO, F.TITLE)
	fBotaoT.Size = UDim2.fromScale(1, 1)
	fBotaoT.TextXAlignment = Enum.TextXAlignment.Center
	local acao: (() -> ())? = nil
	liga(fBotao, function()
		local fn = acao
		if fn then
			fn()
		end
	end)

	-- ----- estado do servidor (acabamentos que você tem e o que está equipado) -----
	local prog: any = nil
	-- D-225: o que está equipado em cada lado (o armário mostra os dois, qualquer que seja o seu agora)
	local function skinsDoServidor(f: string): (any, any)
		local sk = if type(prog) == "table" then prog.skins else nil
		if type(sk) ~= "table" then
			return {}, {}
		end
		local por = if type(sk.porLado) == "table" then sk.porLado[f] else nil
		return sk.owned or {}, por or (if sk.faction == f then sk.on else nil) or {}
	end
	Net.event("Progress_State").OnClientEvent:Connect(function(s: any)
		if type(s) == "table" then
			prog = s
			if raiz.Visible and pagina.Visible then
				render()
				if type(s.result) == "string" and s.result ~= "" then
					Toast.show(UiKit.capitalize(s.result), "info", { title = "Armário" })
				end
			end
		end
	end)
	local function pedeEstado()
		if prog then
			return
		end
		task.spawn(function()
			local ok, s = pcall(function()
				return Net.func("Progress_Get"):InvokeServer()
			end)
			if ok and type(s) == "table" then
				prog = s
				if pagina.Visible then
					render()
				end
			end
		end)
	end

	-- ----- a lista da categoria -----
	type Entrada = {
		id: string,
		nome: string,
		sub: string,
		img: string?,
		skin: any?,
		tem: boolean,
		eq: boolean,
		arma: string?,
		cos: string?, -- o encaixe de um visual comprado (capacete, uniforme, acessório)
	}

	local function filtros(f: string): { { id: string, nome: string } }
		local out: { { id: string, nome: string } } = {}
		if cat == "armas" then
			for _, rid in PAPEIS do
				if #Roles.primaries(f, rid) > 1 then
					table.insert(out, { id = rid, nome = UiKit.upper(Roles.roles[rid].name) })
				end
			end
		elseif cat == "acabamentos" then
			for _, wp in Weapons.list do
				if wp.faction == f and wp.enabled then
					table.insert(out, { id = wp.id, nome = Weapons.shortName(wp.id, f) })
				end
			end
		end
		return out
	end

	local function entradas(f: string): { Entrada }
		local out: { Entrada } = {}
		local owned, on = skinsDoServidor(f)
		if cat == "armas" and sub then
			local prefs = Roles.unpackPrefs(player:GetAttribute("ArmasPreferidas"))
			local escolhida = Roles.primaryFor(f, sub, prefs[Roles.chavePref(f, sub)])
			for _, w in Roles.primaries(f, sub) do
				local wp = Weapons.get(w)
				table.insert(out, {
					id = w,
					nome = Weapons.shortName(w, f),
					sub = if wp then tostring(wp.cartridge or "") else "",
					img = ArteCatalogo.arma(w),
					tem = true,
					eq = w == escolhida,
				})
			end
		elseif cat == "acabamentos" and sub then
			for _, x in Skins.list("weapon", f) do
				local daArma = x.weapon == sub or (x.universal and Skins.armaUniversal(sub))
				if daArma and (not x.soCaixa or owned[x.id]) then
					table.insert(out, {
						id = x.id,
						nome = x.name,
						sub = if x.universal then "Universal" else "",
						skin = x,
						tem = owned[x.id] ~= nil and owned[x.id] ~= false,
						eq = on[sub] == x.id,
						arma = if x.universal then sub else nil,
					})
				end
			end
		elseif cat == "uniformes" or cat == "camuflagem" then
			local k = if cat == "uniformes" then "uniform" else "camo"
			for _, x in Skins.list(k, f) do
				table.insert(out, {
					id = x.id,
					nome = x.name,
					sub = "",
					skin = x,
					tem = owned[x.id] ~= nil and owned[x.id] ~= false,
					eq = on[k] == x.id,
				})
			end
		elseif cat == "visuais" then
			for _, c in ctx.cosmeticos(f) do
				table.insert(out, { id = c.id, nome = c.nome, sub = "", tem = true, eq = c.eq, cos = c.slot })
			end
		end
		-- o que você tem vem primeiro
		table.sort(out, function(a: Entrada, b: Entrada): boolean
			if a.eq ~= b.eq then
				return a.eq
			elseif a.tem ~= b.tem then
				return a.tem
			end
			return a.nome < b.nome
		end)
		return out
	end

	-- visual sem imagem própria: o encaixe escrito grande, no lugar da arte
	local function arteDoEncaixe(pai: Instance, slot: string, h: number): TextLabel
		local l = letra(pai, NOME_SLOT[slot] or UiKit.upper(slot), px(22, 30), V.KHAKI, F.TITLE)
		l.BackgroundColor3 = Color3.fromRGB(24, 26, 20)
		l.BackgroundTransparency = 0
		l.Position = UDim2.fromOffset(px(6, 8), px(6, 8))
		l.Size = UDim2.new(1, -px(12, 16), 0, h)
		l.TextXAlignment = Enum.TextXAlignment.Center
		UiKit.corner(l, 3)
		return l
	end

	local function pintaFicha(f: string, e: Entrada?)
		for _, c in pv:GetChildren() do
			if c ~= pvImg and c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		pvImg.Image = ""
		acao = nil
		if not e then
			fTipo.Text, fNome.Text, fDesc.Text, fEstado.Text = "", "", "Escolha um item na grade.", ""
			fBotao.Visible = false
			return
		end
		fNome.Text = UiKit.upper(e.nome)
		fBotao.Visible = true
		if e.cos then
			local slot = e.cos
			fTipo.Text = NOME_SLOT[slot] or UiKit.upper(slot)
			fDesc.Text = ""
			arteDoEncaixe(pv, slot, px(238, 316))
			fEstado.Text, fEstado.TextColor3 = if e.eq then "✓ EQUIPADO" else "SEU", V.OLIVE_HI
			fBotaoT.Text = if e.eq then "EQUIPADO" else "EQUIPAR"
			fBotao.BackgroundColor3 = if e.eq then V.PANEL_3 else V.AMBAR
			fBotaoT.TextColor3 = if e.eq then V.DIM else V.AMBAR_TEXTO
			if not e.eq then
				acao = function()
					ctx.equiparCosmetico(f, slot, e.id)
				end
			end
		elseif e.skin then
			local s = e.skin
			fTipo.Text = if s.kind == "weapon"
				then "ACABAMENTO"
				elseif s.kind == "uniform" then "UNIFORME"
				else "CAMUFLAGEM"
			fDesc.Text = tostring(s.desc or "")
			local arma = s.kind == "weapon"
			local box = ItemArte.desenha(pv, { id = s.id }, px(250, 332), {
				soldado = s.kind == "uniform",
				aspecto = if arma then (FICHA - px(20, 28)) / px(250, 332) else nil,
				arma = e.arma,
			})
			box.AnchorPoint = Vector2.new(0.5, 0.5)
			box.Position = UDim2.fromScale(0.5, 0.5)
			if arma then
				box.Size = UDim2.fromScale(1, 1)
			end
			if e.tem then
				fEstado.Text = if e.eq then "✓ EQUIPADO" else "SEU"
				fEstado.TextColor3 = V.OLIVE_HI
				fBotaoT.Text = if e.eq then "TIRAR" else "EQUIPAR"
				fBotao.BackgroundColor3 = if e.eq then V.PANEL_3 else V.AMBAR
				fBotaoT.TextColor3 = if e.eq then V.TEXT else V.AMBAR_TEXTO
				acao = function()
					Net.event("Gear_Equip"):FireServer(s.id, not e.eq, e.arma, f)
				end
			elseif s.soPasse then
				fEstado.Text, fEstado.TextColor3 = "No conjunto em Game Pass", V.KHAKI
				fBotaoT.Text = "VER O CONJUNTO"
				fBotao.BackgroundColor3, fBotaoT.TextColor3 = V.PANEL_3, V.TEXT
				acao = ctx.irConjuntos
			else
				fEstado.Text, fEstado.TextColor3 = "Ainda não é seu", V.KHAKI
				fBotaoT.Text = "VER NA INTENDÊNCIA"
				fBotao.BackgroundColor3, fBotaoT.TextColor3 = V.PANEL_3, V.TEXT
				acao = ctx.irIntendencia
			end
		else
			local wp = Weapons.get(e.id)
			fTipo.Text = "ARMA PRINCIPAL"
			fDesc.Text = if wp
				then string.format("%s · %d tiros · %d por minuto", tostring(wp.cartridge or ""), wp.magazine, wp.rpm)
				else ""
			pvImg.Image = e.img or ""
			fEstado.Text, fEstado.TextColor3 = if e.eq then "✓ EQUIPADA" else "", V.OLIVE_HI
			fBotaoT.Text = if e.eq then "EQUIPADA" else "EQUIPAR"
			fBotao.BackgroundColor3 = if e.eq then V.PANEL_3 else V.AMBAR
			fBotaoT.TextColor3 = if e.eq then V.DIM else V.AMBAR_TEXTO
			local rid = sub
			if not e.eq and rid then
				acao = function()
					Net.event("Arma_Escolher"):FireServer(f, rid, e.id)
				end
			end
		end
	end

	local geracao = 0
	render = function()
		geracao += 1
		local minha = geracao
		pedeEstado()
		local f = ctx.lado()
		for id, l in ladoB do
			local on = id == f
			l.b.BackgroundColor3 = if on then (if id == "US" then V.US else V.VC) else CARTAO
			l.t.TextColor3 = if on then V.TEXT else V.DIM
		end
		for id, c in catB do
			local on = id == cat
			c.r.Visible = on
			c.b.BackgroundColor3 = CARTAO_HI
			c.b.BackgroundTransparency = if on then 0 else 1
			c.t.TextColor3 = if on then V.TEXT else V.DIM
		end
		local noCom = cat == "comemoracao"
		miolo.Visible, ficha.Visible, hostCom.Visible = not noCom, not noCom, noCom
		for _, c in hostCom:GetChildren() do
			c:Destroy()
		end
		if noCom then
			local b = ctx.comemoracoes(f)
			b.Size = UDim2.fromScale(1, 1)
			b.Parent = hostCom
			return
		end
		-- filtro: a classe (armas) ou a arma (acabamentos)
		for _, c in chips:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
		local fs = filtros(f)
		chips.Visible = #fs > 0
		grade.Position = UDim2.fromOffset(0, if #fs > 0 then px(50, 66) else 0)
		grade.Size = UDim2.new(1, 0, 1, if #fs > 0 then -px(50, 66) else 0)
		local valido = false
		for _, x in fs do
			valido = valido or x.id == sub
		end
		if #fs > 0 and not valido then
			sub = fs[1].id
		end
		for i, x in fs do
			local on = x.id == sub
			local b = botao(chips, if on then V.OLIVE else CARTAO)
			b.LayoutOrder = i
			b.AutomaticSize = Enum.AutomaticSize.X
			b.Size = UDim2.fromOffset(0, px(38, 50))
			local t = letra(b, x.nome, px(16, 22), if on then V.TEXT else V.DIM, F.TITLE_MED)
			t.TextTruncate = Enum.TextTruncate.None
			t.AutomaticSize = Enum.AutomaticSize.X
			t.Size = UDim2.fromOffset(0, px(38, 50))
			UiKit.pad(b, px(12, 16), px(12, 16))
			liga(b, function()
				if sub ~= x.id then
					sub, sel = x.id, nil
					render()
				end
			end)
		end
		-- a grade: arma em cartão largo (duas colunas); pano e farda em três
		local largo = cat == "armas" or cat == "acabamentos"
		gl.CellSize = if largo
			then UDim2.new(0.5, -px(8, 10), 0, px(178, 236))
			else UDim2.new(1 / 3, -px(8, 10), 0, px(206, 272))
		for _, c in grade:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local lista = entradas(f)
		vazio.Visible = #lista == 0
		vazio.Text = if cat == "visuais"
			then "Nada liberado ainda para este lado: caixas, passe e caderneta dão visuais."
			else "Nada por aqui ainda."
		local atual: Entrada? = nil
		for _, e in lista do
			if e.id == sel then
				atual = e
			end
		end
		if not atual then
			atual = lista[1]
			sel = if atual then atual.id else nil
		end
		pintaFicha(f, atual)
		local bordas: { [string]: UIStroke } = {}
		task.spawn(function()
			for i, e in lista do
				if minha ~= geracao then
					return
				end
				local c = botao(grade, CARTAO)
				c.Name = "Item_" .. e.id
				c.LayoutOrder = i
				local borda = UiKit.edge(c, if e.id == sel then DOURADO else V.LINE, if e.id == sel then 2 else 1, 0.1)
				bordas[e.id] = borda
				if e.cos then
					arteDoEncaixe(c, e.cos, px(140, 186))
				elseif e.skin then
					local ladoArte = if largo then px(118, 156) else px(150, 198)
					local box = ItemArte.desenha(c, { id = e.skin.id }, ladoArte, {
						aspecto = if largo then 2.2 else nil,
						arma = e.arma,
						soldado = e.skin.kind == "uniform", -- D-229: a farda vestida, não o retalho
					})
					box.AnchorPoint = Vector2.new(0.5, 0)
					box.Position = UDim2.new(0.5, 0, 0, px(6, 8))
					if largo then
						box.Size = UDim2.new(1, -px(12, 16), 0, ladoArte)
					end
				else
					local im = Instance.new("ImageLabel")
					im.BackgroundTransparency = 1
					im.Image = e.img or ""
					im.ScaleType = Enum.ScaleType.Fit
					im.Position = UDim2.fromOffset(px(6, 8), px(6, 8))
					im.Size = UDim2.new(1, -px(12, 16), 0, px(118, 156))
					im.Parent = c
				end
				local n = letra(c, e.nome, px(17, 23), if e.tem then V.TEXT else V.DIM, F.TITLE)
				n.Position = UDim2.new(0, px(10, 14), 1, -px(50, 66))
				n.Size = UDim2.new(1, -px(20, 28), 0, px(24, 32))
				local st = letra(
					c,
					if e.eq then "✓ EQUIPADO" elseif e.tem then "SEU" else "🔒 BLOQUEADO",
					px(14, 19),
					if e.eq then V.OLIVE_HI elseif e.tem then V.KHAKI else V.MUTED,
					F.TITLE_MED
				)
				st.Position = UDim2.new(0, px(10, 14), 1, -px(26, 34))
				st.Size = UDim2.new(1, -px(20, 28), 0, px(20, 26))
				liga(c, function()
					local velha = sel and bordas[sel]
					if velha then
						velha.Color, velha.Thickness = V.LINE, 1
					end
					sel = e.id
					borda.Color, borda.Thickness = DOURADO, 2
					pintaFicha(f, e)
				end, function(on: boolean)
					TweenService:Create(c, RAPIDO, { BackgroundColor3 = if on then CARTAO_HI else CARTAO }):Play()
				end)
				if i % 4 == 0 then
					task.wait() -- os cartões com ViewportFrame entram aos poucos
				end
			end
		end)
	end

	-- Studio: workspace "VT65DevArmario" = id da categoria
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevArmario"):Connect(function()
			local v = workspace:GetAttribute("VT65DevArmario")
			if type(v) == "string" and catB[v] then
				cat, sub, sel = v, nil, nil
				render()
			end
		end)
	end

	return { render = render, raiz = raiz }
end

return ArmarioTela
