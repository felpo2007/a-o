--!strict
-- Caixas de suprimentos (D-173): a aba CAIXAS da loja (ShopController manda "caixas_show" com a área
-- dela) e as telas por cima: ITENS E PROBABILIDADES (antes de qualquer compra ou abertura), a
-- ABERTURA, a TROCA de Fragmentos, o HISTÓRICO e o CARTÃO (plaqueta e moldura).
-- Regras da tela (política "Paid Random Items" do Roblox e o pedido do dono):
--   - o resultado vem do servidor JÁ GRAVADO; a animação só mostra o que saiu (nada de "quase");
--   - a lista de itens com a chance exata de cada um está sempre a um botão com texto, antes do
--     botão de comprar/abrir, e mostra o que o jogador já tem (vira Fragmentos);
--   - caixa paga só aparece para quem o servidor libera (venda ligada, PolicyService ok); sem pressa
--     artificial, sem contador falso, sem preço inventado (o preço vem do GetProductInfoAsync);
--   - animação: completa, curta ou sem (botão no alto), e PULAR a qualquer momento.
-- D-174: as caixas grátis dos marcos (Recruta, Serviço, Batalhão, Campanha, Veterano) ficam
-- guardadas até o jogador abrir, cada uma com o "como ganhar"; a COMPRA DIRETA troca créditos
-- de intendência ($, ganhos jogando) pelo cosmético escolhido, sem sorteio.
-- Controle: tudo é botão selecionável (A escolhe, B volta). Studio: VT65DevTela = "caixas".
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Caixas = require(ReplicatedStorage.Shared.Caixas) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression) :: any
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ItemArte = require(script.Parent.ItemArte)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local V, F, px = UiKit.V, UiKit.F, UiKit.px

local state: any = nil
local host: Frame? = nil
local root: Frame? = nil
local prices: { [number]: number } = {}
local anim = "completa" -- "completa" | "curta" | "sem"
local ANIM_NEXT = { completa = "curta", curta = "sem", sem = "completa" }
local ANIM_LABEL = { completa = "EFEITOS: COMPLETOS", curta = "EFEITOS: CURTOS", sem = "EFEITOS: DESLIGADOS" }
local MOTIVO = {
	desligada = "A venda em Robux ainda não foi liberada.",
	restrito = "Indisponível na sua conta pela regra do Roblox para itens aleatórios pagos.",
	politica_sem_resposta = "Não deu para confirmar sua conta agora. Tente mais tarde.",
	fora_da_temporada = "Fora da temporada.",
	sem_produto = "Ainda não está à venda.",
	invalida = "Caixa em manutenção.",
}

-- ===== ajudas =====
local function rgb(t: any, def: Color3): Color3
	return if type(t) == "table" and #t >= 3 then Color3.fromRGB(t[1], t[2], t[3]) else def
end

local function rar(id: string?): any
	if state and id then
		for _, r in state.raridades do
			if r.id == id then
				return r
			end
		end
	end
	return { id = "comum", nome = "Comum", cor = { 158, 158, 150 }, fragmentos = 0 }
end

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

local function kindName(kind: string): string
	return if kind == "emblema"
		then "Emblema do cartão"
		elseif kind == "plaqueta" then "Plaqueta do cartão"
		elseif kind == "moldura" then "Moldura do cartão"
		elseif kind == "creditos" then "Créditos ($)"
		elseif kind == "fragmentos" then "Fragmentos de Arsenal"
		else "Acabamento ou uniforme"
end

local function ehSaldo(item: any): boolean
	return item ~= nil and (item.kind == "creditos" or item.kind == "fragmentos")
end

-- desenho do item (emblema, plaqueta, moldura, arma em 3D, pano do uniforme ou prêmio de saldo),
-- quadrado de lado `s`: Controllers/ItemArte (D-175, o mesmo do ARQUIVO MILITAR)
local function desenhaItem(parent: Instance, item: any, s: number): Frame
	return ItemArte.desenha(parent, item, s)
end

-- caixa 3D (cópia do servidor em ReplicatedStorage.VT65CaixasArte) num ViewportFrame
local function viewport(parent: Instance, modelo: string, s: number): (ViewportFrame, Camera, Model?)
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromOffset(s, s)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 146, 130)
	vp.LightColor = Color3.fromRGB(255, 240, 214)
	vp.LightDirection = Vector3.new(-1, -1.4, -0.6)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local folder = ReplicatedStorage:FindFirstChild("VT65CaixasArte")
	local src = folder and folder:FindFirstChild(modelo)
	local m: Model
	if src and src:IsA("Model") then
		m = src:Clone()
	else
		-- sem a arte publicada: um caixote simples, para a tela nunca ficar vazia
		m = Instance.new("Model")
		local p = Instance.new("Part")
		p.Size = Vector3.new(2.6, 1.6, 1.6)
		p.Color = Color3.fromRGB(96, 92, 58)
		p.Material = Enum.Material.WoodPlanks
		p.Anchored = true
		p.Parent = m
		m.PrimaryPart = p
	end
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	local d = size.Magnitude * 1.7
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(d * 0.55, d * 0.42, d * 0.72), cf.Position)
	return vp, cam, m
end

-- ===== estado =====
local function fetch(): any
	local ok, s = pcall(function()
		return Net.func("Suprimento_Get"):InvokeServer()
	end)
	if ok and type(s) == "table" and not s.carregando then
		state = s
	end
	return state
end

local function priceOf(id: number): number?
	if id == 0 then
		return nil
	end
	if prices[id] then
		return prices[id]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)
	end)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		prices[id] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

-- ===== telas por cima =====
local overlays: { [string]: ScreenGui } = {}
local function closeOverlay(name: string)
	local g = overlays[name]
	if g then
		overlays[name] = nil
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
	for _, name in { "CaixaAbertura", "CaixaOdds", "CaixaTroca", "CaixaLoja", "CaixaHist", "CaixaCartao" } do
		if overlays[name] and UiKit.backFor(name) then
			closeOverlay(name)
			return
		end
	end
end)

local refresh: () -> () = function() end
local abrirGratis: (c: any) -> () = function(_c: any) end
local comprar: (c: any) -> () = function(_c: any) end

-- botão de ação da caixa (abrir com bilhete, abrir uma guardada ou comprar), ou nil se não há o que
-- fazer
local function botaoAcao(parent: Instance, c: any): any
	if c.tipo == "gratuita" and c.fonte == "marco" then
		local g = c.guardadas or 0
		local a = UiKit.action(
			parent,
			if g == 1
				then "ABRIR · 1 GUARDADA"
				elseif g > 1 then string.format("ABRIR · %d GUARDADAS", g)
				else "NENHUMA GUARDADA",
			"premio",
			function()
				abrirGratis(c)
			end,
			{ h = px(46, 62) }
		)
		a.enabled(g >= 1 and c.bloqueio == nil)
		return a
	end
	if c.tipo == "gratuita" then
		local n = c.bilhetes or 1
		local a = UiKit.action(
			parent,
			string.format("ABRIR · %d BILHETE%s", n, if n > 1 then "S" else ""),
			"premio",
			function()
				abrirGratis(c)
			end,
			{ h = px(46, 62) }
		)
		a.enabled(state.bilhetes >= n and c.bloqueio == nil)
		return a
	end
	if c.bloqueio then
		return nil
	end
	local p = priceOf(c.produtoId)
	local label = if p then string.format("COMPRAR · R$ %d", p) else "COMPRAR"
	local a = UiKit.action(parent, label, "robux", function()
		comprar(c)
	end, { h = px(46, 62) })
	return a
end

-- ITENS E PROBABILIDADES (antes de comprar ou abrir)
local function abrirOdds(c: any)
	local W, H = px(640, 860), px(580, 780)
	local _, panel = overlay("CaixaOdds", 42, W, H)
	closeButton(panel, "CaixaOdds")
	local t = text(panel, UiKit.upper(c.nome), px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local custo = if c.fonte == "marco"
		then string.format("Grátis, não se compra. Como ganhar: %s", c.ganha or "jogando.")
		elseif c.tipo == "gratuita" then string.format(
			"Custo: %d Bilhete de Recompensa (ganho jogando; não se compra).",
			c.bilhetes or 1
		)
		else (function(): string
			local p = priceOf(c.produtoId)
			return if p
				then string.format("Preço: R$ %d (Robux), cobrado pelo Roblox na confirmação.", p)
				else "Preço: confirmado pelo Roblox na compra."
		end)()
	local sub =
		text(panel, custo .. " · 1 resultado por abertura. Chances exatas: a soma é 100%.", px(14, 19), V.DIM, F.BODY)
	sub.Position = UDim2.fromOffset(px(18, 24), px(48, 62))
	sub.Size = UDim2.new(1, -px(36, 48), 0, px(36, 48))
	-- por raridade
	local chips = frame(panel, UDim2.new(1, -px(36, 48), 0, px(26, 34)))
	chips.Position = UDim2.fromOffset(px(18, 24), px(88, 116))
	UiKit.list(chips, true, px(10, 14))
	for _, r in state.raridades do
		local w = c.porRaridade[r.id] or 0
		if w > 0 then
			local chip = UiKit.tag(
				chips,
				string.format("%s %s", UiKit.upper(r.nome), Caixas.pct(w)),
				rgb(r.cor, V.DIM),
				px(13, 18)
			)
			chip.AutomaticSize = Enum.AutomaticSize.X
		end
	end
	-- lista completa
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(122, 162))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(122, 162) - px(150, 200))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = panel
	UiKit.list(list, false, px(4, 6))
	for i, e in c.lista do
		local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(34, 46)), if i % 2 == 0 then V.PANEL_2 else V.PANEL, 0)
		row.LayoutOrder = i
		local r = rar(e.item.raridade)
		local sw = frame(row, UDim2.fromOffset(px(10, 14), px(24, 32)), rgb(r.cor, V.DIM), 0)
		sw.Position = UDim2.fromOffset(px(6, 8), px(5, 7))
		UiKit.corner(sw, 2)
		local nm = text(
			row,
			string.format("%s · %s · %s", e.item.nome, UiKit.upper(r.nome), kindName(e.item.kind)),
			px(14, 19),
			V.TEXT,
			F.BODY
		)
		nm.Position = UDim2.fromOffset(px(24, 32), 0)
		nm.Size = UDim2.new(1, -px(250, 330), 1, 0)
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		local pc = text(row, e.pct, px(16, 22), V.KHAKI, F.TITLE)
		pc.AnchorPoint = Vector2.new(1, 0)
		pc.Position = UDim2.new(1, -px(8, 10), 0, 0)
		pc.Size = UDim2.new(0, px(80, 106), 1, 0)
		pc.TextXAlignment = Enum.TextXAlignment.Right
		if e.repetido then
			local d =
				text(row, string.format("JÁ TEM → +%d FRAGMENTOS", e.fragmentos), px(12, 16), V.BRASS, F.TITLE_MED)
			d.AnchorPoint = Vector2.new(1, 0)
			d.Position = UDim2.new(1, -px(94, 124), 0, 0)
			d.Size = UDim2.new(0, px(150, 200), 1, 0)
			d.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
	-- regras e o botão de agir
	local regras = text(panel, "• " .. table.concat(state.regras, "\n• "), px(13, 17), V.DIM, F.BODY)
	regras.AnchorPoint = Vector2.new(0, 1)
	regras.Position = UDim2.new(0, px(18, 24), 1, -px(64, 86))
	regras.Size = UDim2.new(1, -px(36, 48), 0, px(84, 112))
	regras.TextYAlignment = Enum.TextYAlignment.Top
	local row = frame(panel, UDim2.new(1, -px(36, 48), 0, px(46, 62)))
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.new(0, px(18, 24), 1, -px(12, 16))
	local a = botaoAcao(row, c)
	if a then
		a.button.Size = UDim2.new(0.6, 0, 1, 0)
	end
	UiKit.focus(panel)
end

-- ABERTURA: o resultado já está gravado no servidor; aqui só a apresentação
local function abertura(c: any, res: any, item: any)
	local W, H = px(560, 740), px(560, 740)
	local g, panel = overlay("CaixaAbertura", 46, W, H)
	panel.BackgroundColor3 = V.BG
	local r = rar(res.raridade)
	local rc = rgb(r.cor, V.KHAKI)
	local skip = false
	local pular = UiKit.action(panel, "PULAR", "secondary", function()
		skip = true
	end, { h = px(38, 52) })
	pular.button.AnchorPoint = Vector2.new(1, 0)
	pular.button.Position = UDim2.new(1, -px(14, 20), 0, px(12, 16))
	pular.button.Size = UDim2.fromOffset(px(110, 146), px(38, 52))
	local stage = frame(panel, UDim2.fromScale(1, 1))
	local vp, cam, m = viewport(stage, c.modelo or "caixa_municao_us", px(360, 480))
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.45)
	local flash = frame(g, UDim2.fromScale(1, 1), rc, 1)
	flash.ZIndex = 5
	local function espera(t: number)
		local t0 = os.clock()
		while os.clock() - t0 < t and not skip do
			task.wait()
		end
	end
	if anim ~= "sem" and m then
		local cf, size = m:GetBoundingBox()
		local d = size.Magnitude * 1.7
		local longe = CFrame.lookAt(cf.Position + Vector3.new(d * 0.9, d * 0.7, d * 1.2), cf.Position)
		local perto = CFrame.lookAt(cf.Position + Vector3.new(d * 0.4, d * 0.32, d * 0.55), cf.Position)
		cam.CFrame = longe
		local curta = anim == "curta"
		TweenService:Create(cam, TweenInfo.new(if curta then 0.45 else 1.0, Enum.EasingStyle.Quint), { CFrame = perto })
			:Play()
		espera(if curta then 0.45 else 1.0)
		if not curta and not skip then
			-- as travas: duas batidas secas (sem tremer a tela, só a caixa)
			local p0 = m:GetPivot()
			for _, ang in { 3, -3, 2, 0 } do
				m:PivotTo(p0 * CFrame.Angles(0, 0, math.rad(ang)))
				espera(0.07)
			end
			m:PivotTo(p0)
		end
		if not skip then
			flash.BackgroundTransparency = if curta then 0.6 else 0.25
			TweenService:Create(flash, TweenInfo.new(if curta then 0.25 else 0.5), { BackgroundTransparency = 1 })
				:Play()
			if res.raridade == "lendario" and not curta then
				espera(0.25)
				flash.BackgroundTransparency = 0.35
				TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
			end
		end
	end
	if overlays.CaixaAbertura ~= g then
		return -- outra abertura tomou o lugar desta (ou a tela fechou)
	end
	flash.BackgroundTransparency = 1
	stage:Destroy()
	pular.button.Visible = false
	-- revelação
	local card = frame(panel, UDim2.fromScale(1, 1))
	UiKit.list(card, false, px(10, 14), Enum.HorizontalAlignment.Center)
	UiKit.pad(card, px(18, 24), px(18, 24), px(40, 54), px(14, 18))
	if item then
		local box = desenhaItem(card, item, px(200, 270))
		box.LayoutOrder = 1
		if res.raridade == "lendario" or res.raridade == "epico" then
			local glow = box:FindFirstChildOfClass("UIStroke")
			if glow then
				glow.Thickness = 4
			end
		end
	end
	if res.raridade then -- sem item (Fragmentos fixos): sem etiqueta de raridade
		local tag = UiKit.tag(card, UiKit.upper(r.nome), rc, px(16, 22))
		tag.LayoutOrder = 2
		tag.AutomaticSize = Enum.AutomaticSize.X
	end
	local nome = text(card, if item then item.nome else "Fragmentos de Arsenal", px(26, 34), V.TEXT, F.TITLE)
	nome.LayoutOrder = 3
	nome.Size = UDim2.new(1, 0, 0, px(36, 48))
	nome.TextXAlignment = Enum.TextXAlignment.Center
	local linha = if res.origem == "restrito"
		then string.format(
			"Itens aleatórios pagos indisponíveis para a sua conta agora: +%d Fragmentos de Arsenal, sem sorteio.",
			res.fragmentos
		)
		elseif res.repetido then string.format(
			"Você já tinha este item: virou +%d Fragmentos de Arsenal.",
			res.fragmentos
		)
		elseif ehSaldo(item) then "Entrou no seu saldo."
		elseif res.origem == "compra" then "Comprado com créditos: já é seu."
		else "Novo no seu arsenal."
	local l = text(card, linha, px(15, 20), if res.repetido then V.BRASS else V.KHAKI, F.BODY)
	l.LayoutOrder = 4
	l.Size = UDim2.new(1, 0, 0, px(40, 54))
	l.TextXAlignment = Enum.TextXAlignment.Center
	local row = frame(card, UDim2.new(1, 0, 0, px(46, 62)))
	row.LayoutOrder = 5
	UiKit.list(row, true, px(12, 16), Enum.HorizontalAlignment.Center)
	if item and not res.repetido and (item.kind == "plaqueta" or item.kind == "moldura") then
		local usar = UiKit.action(row, "USAR NO CARTÃO", "primary", function()
			local slot = if item.kind == "plaqueta" then "tag" else "mol"
			pcall(function()
				local rr = Net.func("Suprimento_Equipar"):InvokeServer({ slot = slot, item = item.id })
				if type(rr) == "table" and rr.estado then
					state = rr.estado
				end
			end)
			closeOverlay("CaixaAbertura")
			refresh()
		end, { h = px(46, 62) })
		usar.button.Size = UDim2.fromOffset(px(200, 270), px(46, 62))
	end
	local ok = UiKit.action(row, "OK", "secondary", function()
		closeOverlay("CaixaAbertura")
	end, { h = px(46, 62) })
	ok.button.Size = UDim2.fromOffset(px(120, 160), px(46, 62))
	UiKit.focus(row)
end

-- TROCA de Fragmentos por item garantido
local function abrirTroca()
	local W, H = px(640, 860), px(580, 780)
	local _, panel = overlay("CaixaTroca", 42, W, H)
	closeButton(panel, "CaixaTroca")
	local t = text(panel, "TROCA DE FRAGMENTOS", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local sub = text(
		panel,
		string.format(
			"Você tem %d Fragmentos de Arsenal. Cada troca é garantida: você escolhe o item. Fragmentos não viram Robux nem dinheiro.",
			state.fragmentos
		),
		px(14, 19),
		V.DIM,
		F.BODY
	)
	sub.Position = UDim2.fromOffset(px(18, 24), px(48, 62))
	sub.Size = UDim2.new(1, -px(36, 48), 0, px(40, 54))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(94, 124))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(106, 140))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = panel
	UiKit.list(list, false, px(6, 8))
	for i, e in state.troca do
		local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(58, 78)), V.PANEL_2, 0)
		row.LayoutOrder = i
		local box = desenhaItem(row, e.item, px(50, 68))
		box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
		local r = rar(e.item.raridade)
		local nm = text(
			row,
			string.format("%s\n%s · %s", e.item.nome, UiKit.upper(r.nome), kindName(e.item.kind)),
			px(14, 18),
			V.TEXT,
			F.BODY
		)
		nm.Position = UDim2.fromOffset(px(64, 86), 0)
		nm.Size = UDim2.new(1, -px(270, 360), 1, 0)
		local label = if e.possui then "JÁ TEM" else string.format("TROCAR · %d", e.custo)
		local a = UiKit.action(row, label, "ci", function()
			local ok, rr = pcall(function()
				return Net.func("Suprimento_Trocar"):InvokeServer(e.item.id)
			end)
			if ok and type(rr) == "table" then
				if rr.estado then
					state = rr.estado
				end
				if rr.ok then
					closeOverlay("CaixaTroca")
					refresh()
					abertura({ modelo = "caixa_municao_us" }, rr.resultado, rr.item)
				else
					Toast.show(
						if rr.motivo == "fragmentos" then "Fragmentos insuficientes." else "Não deu para trocar agora."
					)
				end
			end
		end, { h = px(40, 54) })
		a.button.AnchorPoint = Vector2.new(1, 0.5)
		a.button.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
		a.button.Size = UDim2.fromOffset(px(170, 226), px(40, 54))
		a.enabled(not e.possui and state.fragmentos >= e.custo)
	end
	UiKit.focus(panel)
end

-- COMPRA DIRETA (D-174, caminho C): o cosmético escolhido por créditos ($), sem sorteio
local function abrirLoja()
	local W, H = px(640, 860), px(580, 780)
	local _, panel = overlay("CaixaLoja", 42, W, H)
	closeButton(panel, "CaixaLoja")
	local t = text(panel, "COMPRA DIRETA", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local sub = text(
		panel,
		string.format(
			"Você tem %s em créditos (ganhos em partidas e missões). Você escolhe o item e leva ele, sem sorteio.",
			Progression.money(state.creditos or 0)
		),
		px(14, 19),
		V.DIM,
		F.BODY
	)
	sub.Position = UDim2.fromOffset(px(18, 24), px(48, 62))
	sub.Size = UDim2.new(1, -px(36, 48), 0, px(40, 54))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(94, 124))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(106, 140))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = panel
	UiKit.list(list, false, px(6, 8))
	for i, e in state.loja or {} do
		local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(58, 78)), V.PANEL_2, 0)
		row.LayoutOrder = i
		local box = desenhaItem(row, e.item, px(50, 68))
		box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
		local r = rar(e.item.raridade)
		local nm = text(
			row,
			string.format("%s\n%s · %s", e.item.nome, UiKit.upper(r.nome), kindName(e.item.kind)),
			px(14, 18),
			V.TEXT,
			F.BODY
		)
		nm.Position = UDim2.fromOffset(px(64, 86), 0)
		nm.Size = UDim2.new(1, -px(270, 360), 1, 0)
		local label = if e.possui then "JÁ TEM" else string.format("LEVAR · %s", Progression.money(e.preco))
		local a = UiKit.action(row, label, "ci", function()
			local ok, rr = pcall(function()
				return Net.func("Suprimento_Loja"):InvokeServer(e.item.id)
			end)
			if ok and type(rr) == "table" then
				if rr.ok then
					closeOverlay("CaixaLoja")
					refresh()
					abertura({ modelo = "caixa_municao_us" }, rr.resultado, rr.item)
				else
					Toast.show(
						if rr.motivo == "creditos"
							then "Créditos insuficientes: jogue partidas e cumpra missões."
							elseif rr.motivo == "possui" then "Você já tem este item."
							else "Não deu para levar agora."
					)
				end
			end
		end, { h = px(40, 54) })
		a.button.AnchorPoint = Vector2.new(1, 0.5)
		a.button.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
		a.button.Size = UDim2.fromOffset(px(190, 252), px(40, 54))
		a.enabled(not e.possui and (state.creditos or 0) >= e.preco)
	end
	UiKit.focus(panel)
end

-- HISTÓRICO dos últimos resultados (o servidor guarda 100; aqui os 20 mais novos)
local function abrirHist()
	local W, H = px(560, 740), px(520, 700)
	local _, panel = overlay("CaixaHist", 42, W, H)
	closeButton(panel, "CaixaHist")
	local t = text(panel, "HISTÓRICO", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(60, 80))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(72, 96))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.Parent = panel
	UiKit.list(list, false, px(4, 6))
	if #state.hist == 0 then
		local e = text(list, "Nenhuma caixa aberta ainda.", px(15, 20), V.DIM, F.BODY)
		e.Size = UDim2.new(1, 0, 0, px(30, 40))
	end
	for i, h in state.hist do
		local quando = os.date("%d/%m %H:%M", h.t)
		local o = if h.origem == "bilhete"
			then "bilhete"
			elseif h.origem == "marco" then "caixa ganha"
			elseif h.origem == "compra" then "créditos"
			elseif h.origem == "colecao" then "coleção do Arquivo"
			elseif h.origem == "recibo" then "Robux"
			elseif h.origem == "restrito" then "Robux (sem sorteio)"
			else "troca"
		local s = if h.item
			then string.format(
				"%s · %s%s",
				h.item.nome,
				o,
				if h.repetido then string.format(" · repetido: +%d fragmentos", h.fragmentos) else ""
			)
			else string.format("+%d fragmentos · %s", h.fragmentos, o)
		local row = text(list, string.format("%s · %s", quando, s), px(14, 18), V.TEXT, F.BODY)
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, px(26, 34))
		row.TextTruncate = Enum.TextTruncate.AtEnd
	end
	UiKit.focus(panel)
end

-- CARTÃO: plaqueta e moldura escolhidas
local function abrirCartao()
	local W, H = px(560, 740), px(520, 700)
	local _, panel = overlay("CaixaCartao", 42, W, H)
	closeButton(panel, "CaixaCartao")
	local t = text(panel, "MEU CARTÃO", px(24, 32), V.TEXT, F.TITLE)
	t.Position = UDim2.fromOffset(px(18, 24), px(14, 18))
	t.Size = UDim2.new(1, -px(170, 230), 0, px(32, 42))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(px(18, 24), px(60, 80))
	list.Size = UDim2.new(1, -px(36, 48), 1, -px(72, 96))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.Parent = panel
	UiKit.list(list, false, px(6, 8))
	local n = 0
	for _, slot in { "tag", "mol" } do
		for _, it in state.meus[slot] do
			n += 1
			local row = frame(list, UDim2.new(1, -px(10, 14), 0, px(58, 78)), V.PANEL_2, 0)
			row.LayoutOrder = n
			local box = desenhaItem(row, it, px(50, 68))
			box.Position = UDim2.fromOffset(px(4, 5), px(4, 5))
			local nm = text(row, it.nome, px(15, 20), V.TEXT, F.BODY)
			nm.Position = UDim2.fromOffset(px(64, 86), 0)
			nm.Size = UDim2.new(1, -px(230, 310), 1, 0)
			local em = state.on[slot] == it.id
			local a = UiKit.action(
				row,
				if em then "TIRAR" else "USAR",
				if em then "secondary" else "primary",
				function()
					pcall(function()
						local rr = Net.func("Suprimento_Equipar")
							:InvokeServer({ slot = slot, item = if em then "" else it.id })
						if type(rr) == "table" and rr.estado then
							state = rr.estado
						end
					end)
					abrirCartao()
				end,
				{ h = px(40, 54) }
			)
			a.button.AnchorPoint = Vector2.new(1, 0.5)
			a.button.Position = UDim2.new(1, -px(8, 10), 0.5, 0)
			a.button.Size = UDim2.fromOffset(px(130, 174), px(40, 54))
		end
	end
	if n == 0 then
		local e =
			text(list, "Plaquetas e molduras saem das caixas e da troca de Fragmentos.", px(15, 20), V.DIM, F.BODY)
		e.Size = UDim2.new(1, 0, 0, px(40, 54))
	end
	UiKit.focus(panel)
end

-- ===== a aba =====
local function build()
	local h = host
	if not h then
		return
	end
	if root then
		root:Destroy()
	end
	local r = frame(h, UDim2.fromScale(1, 1))
	r.Name = "CaixasTela"
	root = r
	if not state then
		local t = text(r, "Carregando o depósito…", px(16, 22), V.DIM, F.BODY)
		t.Size = UDim2.new(1, 0, 0, px(40, 54))
		return
	end
	-- atalhos no alto, saldos e o aviso embaixo deles
	local top = frame(r, UDim2.new(1, 0, 0, px(44, 60)))
	UiKit.list(top, true, px(10, 14))
	local function atalho(label: string, order: number, fn: () -> (), w: number?)
		local a = UiKit.action(top, label, "secondary", fn, { h = px(38, 52) })
		a.button.Size = UDim2.fromOffset(w or px(110, 146), px(38, 52))
		a.button.LayoutOrder = order
	end
	atalho("COMPRA DIRETA", 1, abrirLoja, px(150, 200))
	atalho("TROCA", 2, abrirTroca, px(96, 128))
	atalho("HISTÓRICO", 3, abrirHist, px(110, 146))
	atalho("CARTÃO", 4, abrirCartao, px(96, 128))
	atalho(ANIM_LABEL[anim], 5, function()
		anim = ANIM_NEXT[anim]
		build()
	end, px(184, 244))
	local saldo = text(
		r,
		string.format(
			"CRÉDITOS %s · BILHETES %d (hoje %d de %d) · FRAGMENTOS %d",
			Progression.money(state.creditos or 0),
			state.bilhetes,
			state.hoje or 0,
			state.tetoDia or 4,
			state.fragmentos
		),
		px(15, 20),
		V.KHAKI,
		F.TITLE_MED
	)
	saldo.Position = UDim2.fromOffset(0, px(48, 64))
	saldo.Size = UDim2.new(1, 0, 0, px(22, 30))
	-- aviso da conta restrita (sem caixas pagas) e de onde vêm os bilhetes
	local nota = if state.restrito or not state.politicaOk
		then "Caixas pagas indisponíveis na sua conta. As caixas grátis, a troca e a compra direta continuam."
		else "Caixas grátis vêm de jogar: missões (Bilhetes), treinamento, patentes, passe e partidas. Não se compram."
	local n = text(r, nota, px(13, 17), V.DIM, F.BODY)
	n.Position = UDim2.fromOffset(0, px(70, 94))
	n.Size = UDim2.new(1, 0, 0, px(22, 30))
	-- as caixas
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, px(96, 128))
	list.Size = UDim2.new(1, 0, 1, -px(96, 128))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = px(5, 7)
	list.ScrollBarImageColor3 = V.LINE
	list.Parent = r
	UiKit.list(list, false, px(8, 10))
	local order = 0
	for _, c in state.caixas do
		-- caixa paga só para quem pode comprar agora (sem vitrine do que não dá para levar)
		if c.tipo == "paga" and c.bloqueio ~= nil then
			continue
		end
		order += 1
		local card = frame(list, UDim2.new(1, -px(10, 14), 0, px(150, 200)), V.PANEL_2, 0)
		card.LayoutOrder = order
		UiKit.corner(card, 4)
		UiKit.edge(card, V.LINE, 1, 0.4)
		local vp = viewport(card, c.modelo or "caixa_municao_us", px(140, 186))
		vp.Position = UDim2.fromOffset(px(6, 8), px(5, 7))
		local x = px(154, 204)
		local nm = text(card, UiKit.upper(c.nome), px(19, 26), V.TEXT, F.TITLE)
		nm.Position = UDim2.fromOffset(x, px(8, 10))
		nm.Size = UDim2.new(1, -x - px(230, 300), 0, px(26, 34))
		local ds = text(card, c.desc, px(13, 17), V.DIM, F.BODY)
		ds.Position = UDim2.fromOffset(x, px(36, 46))
		ds.Size = UDim2.new(1, -x - px(230, 300), 0, px(36, 48))
		ds.TextYAlignment = Enum.TextYAlignment.Top
		-- barra por raridade
		local bar = frame(card, UDim2.new(1, -x - px(230, 300), 0, px(10, 14)), V.PANEL, 0)
		bar.Position = UDim2.fromOffset(x, px(80, 106))
		UiKit.list(bar, true, 0)
		local legenda = {}
		for i, rr in state.raridades do
			local w = c.porRaridade[rr.id] or 0
			if w > 0 then
				local seg = frame(bar, UDim2.new(w / Caixas.ESCALA, 0, 1, 0), rgb(rr.cor, V.DIM), 0)
				seg.LayoutOrder = i
				table.insert(legenda, string.format("%s %s", rr.nome, Caixas.pct(w)))
			end
		end
		local lg = text(card, table.concat(legenda, " · "), px(12, 16), V.DIM, F.BODY)
		lg.Position = UDim2.fromOffset(x, px(94, 124))
		lg.Size = UDim2.new(1, -x - px(230, 300), 0, px(32, 42)) -- duas linhas: as 5 raridades cabem
		if c.fonte == "marco" then
			local como = text(card, "Como ganhar: " .. (c.ganha or "jogando."), px(12, 16), V.KHAKI, F.BODY)
			como.Position = UDim2.fromOffset(x, px(126, 166))
			como.Size = UDim2.new(1, -x - px(230, 300), 0, px(22, 30))
			como.TextTruncate = Enum.TextTruncate.AtEnd
		elseif c.temporada and c.fim then
			local fim = text(
				card,
				string.format("Só nesta temporada, até %s.", os.date("%d/%m/%Y", c.fim)),
				px(12, 16),
				V.KHAKI,
				F.BODY
			)
			fim.Position = UDim2.fromOffset(x, px(126, 166))
			fim.Size = UDim2.new(1, -x - px(230, 300), 0, px(22, 30))
		end
		-- botões: itens e probabilidades sempre antes do de agir
		local col = frame(card, UDim2.new(0, px(220, 290), 1, -px(16, 20)))
		col.AnchorPoint = Vector2.new(1, 0)
		col.Position = UDim2.new(1, -px(8, 10), 0, px(8, 10))
		UiKit.list(col, false, px(8, 10))
		local ver = UiKit.action(col, "VER ITENS E PROBABILIDADES", "secondary", function()
			abrirOdds(c)
		end, { h = px(44, 60) })
		ver.button.LayoutOrder = 1
		local a = botaoAcao(col, c)
		if a then
			a.button.LayoutOrder = 2
		elseif c.bloqueio then
			local why = text(col, MOTIVO[c.bloqueio] or "Indisponível.", px(12, 16), V.DIM, F.BODY)
			why.LayoutOrder = 2
			why.Size = UDim2.new(1, 0, 0, px(44, 60))
		end
	end
	UiKit.focus(r)
end

refresh = function()
	task.spawn(function()
		fetch()
		if host and host.Visible then
			build()
		end
	end)
end

abrirGratis = function(c: any)
	local ok, rr = pcall(function()
		return Net.func("Suprimento_Abrir"):InvokeServer(c.id)
	end)
	if not (ok and type(rr) == "table") then
		Toast.show("Não deu para abrir agora.")
		return
	end
	if rr.estado then
		state = rr.estado
	end
	if not rr.ok then
		Toast.show(
			if rr.motivo == "bilhetes"
				then "Sem Bilhetes de Recompensa: cumpra uma missão do dia."
				elseif rr.motivo == "guardada" then "Nenhuma caixa desta guardada. Veja como ganhar no cartão dela."
				else "Não deu para abrir agora."
		)
		return
	end
	closeOverlay("CaixaOdds")
	build()
	abertura(c, rr.resultado, rr.item)
end

comprar = function(c: any)
	-- o servidor confere venda ligada, temporada e PolicyService antes de abrir o prompt
	Net.event("Suprimento_Comprar"):FireServer(c.id)
end

-- caixa paga entregue (recibo já gravado): a abertura com o resultado real
Net.event("Suprimento_Resultado").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.resultado) ~= "table" then
		return
	end
	local c = { modelo = "caixa_municao_us" }
	if state then
		for _, cc in state.caixas do
			if cc.id == msg.resultado.caixa then
				c = cc
			end
		end
	end
	closeOverlay("CaixaOdds")
	abertura(c, msg.resultado, msg.item)
	refresh()
end)

-- D-174: caixa grátis ganha num marco (fica guardada; a loja não abre sozinha)
Net.event("Suprimento_Ganhou").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.nome) ~= "string" then
		return
	end
	Toast.show(string.format("%s guardada: abra na loja, aba CAIXAS.", msg.nome))
	if host and host.Visible then
		refresh()
	else
		task.spawn(fetch)
	end
end)

Bus.on("caixas_show", function(h: Frame)
	host = h
	build()
	refresh()
end)
Bus.on("caixas_hide", function()
	for name in table.clone(overlays) do
		closeOverlay(name)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "caixas" then
			Bus.fire("shop_open", "caixas")
		end
	end)
end
