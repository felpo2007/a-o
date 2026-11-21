--!strict
-- Levar veículo (D-103; pedido do dono, 2026-11-12: "coloque a opção de comprar um veículo quando
-- nascer e ele spawnar do seu lado"). Na carta de inserção, um cartão escuro na margem direita da
-- carta mostra o que vai junto ("A PÉ" ou a viatura); o painel escolhe a viatura e a forma de pagar
-- (CI ou Robux). Regras e preços em Shared/CompraVeiculo; o servidor (CompraVeiculoService) arma o
-- pedido, acha o lugar ao lado ao nascer e só então cobra.
-- Controle: X na carta abre o painel (o X não marca nada na inserção); direcional + A escolhe, B
-- fecha. Mouse e toque: clique no cartão. A DeployScreen avisa quando a pasta de inserção está
-- aberta (Bus "insercao_painel", um gancho só).
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Net = require(ReplicatedStorage.Shared.Net)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local SpawnTransition = require(script.Parent.SpawnTransition)
local UiEfeitos = require(script.Parent.UiEfeitos)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V = UiKit.V
local NAME = "compra_veiculo"
local ORDER = 21 -- acima da inserção (20), abaixo da tela da baixa (25)
local SIDE_PT: { [string]: string } = { US = "EUA", VC = "VC" }

local function sideColor(f: any): Color3
	return if f == "VC" then V.VC else V.US
end

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function faction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

local function specName(spec: string): string
	local s = Vehicles.SPECS[spec]
	return if s then s.name else spec
end

-- ===== palco de 1280 x 720, o mesmo do GameUI (a carta de inserção vai de x 356 a 1240) =====
local gui = UiKit.screen("VT65CompraVeiculo", ORDER)
gui.IgnoreGuiInset = true
local DESIGN_W, DESIGN_H = 1280, 720
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
stage.BackgroundTransparency = 1
stage.Parent = gui
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage
local function fit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	local k = math.min(s.X / DESIGN_W, s.Y / DESIGN_H)
	if UiKit.tv() then
		k = math.max(k * 0.92, 1)
	end
	stageScale.Scale = k
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- ===== cartão (margem direita da carta, abaixo do norte e do zoom) =====
local CARD_W = 344 -- D-223: na ficha do destino, à direita da carta
local card = UiKit.panel(stage, V.PANEL, 0.08, true)
card.Name = "Veiculo"
card.AnchorPoint = Vector2.new(0, 1) -- D-228: preso ao pé da ficha do destino, para não cobrir o resumo
card.Position = UDim2.fromOffset(910, 650)
card.Size = UDim2.fromOffset(CARD_W, 0)
card.AutomaticSize = Enum.AutomaticSize.Y
card.Visible = false
local cardStripe = Instance.new("Frame")
cardStripe.Size = UDim2.new(1, 0, 0, 4)
cardStripe.BorderSizePixel = 0
cardStripe.Parent = card
local cardBody = Instance.new("Frame")
cardBody.BackgroundTransparency = 1
cardBody.Size = UDim2.new(1, 0, 0, 0)
cardBody.AutomaticSize = Enum.AutomaticSize.Y
cardBody.Parent = card
UiKit.pad(cardBody, 10, 10, 10, 10)
UiKit.list(cardBody, false, 4)
local cardKicker = UiKit.kicker(cardBody, "VEÍCULO AO NASCER", 12)
cardKicker.Size = UDim2.new(1, 0, 0, 16)
cardKicker.LayoutOrder = 1
-- D-124: a imagem da viatura escolhida (tools/blender/loja.py, o modelo do jogo); com o ID da
-- imagem em 0 (AssetIds.LojaImages), fica só o nome
local cardImage = Instance.new("ImageLabel")
cardImage.Name = "Imagem"
cardImage.BackgroundTransparency = 1
cardImage.ScaleType = Enum.ScaleType.Fit
cardImage.Size = UDim2.new(1, 0, 0, 72)
cardImage.Visible = false
cardImage.LayoutOrder = 2
cardImage.Parent = cardBody
local function vehicleImage(spec: string?): string?
	local id = if spec then (AssetIds.LojaImages or {})[spec] else nil
	return if type(id) == "number" and id ~= 0 then string.format("rbxassetid://%d", id) else nil
end
local cardTitle = UiKit.title(cardBody, "A PÉ", 22)
cardTitle.Size = UDim2.new(1, 0, 0, 28)
cardTitle.LayoutOrder = 3
local cardNote = UiKit.text2(cardBody, "", 13, V.DIM)
cardNote.Size = UDim2.new(1, 0, 0, 0)
cardNote.AutomaticSize = Enum.AutomaticSize.Y
cardNote.TextWrapped = true
cardNote.TextXAlignment = Enum.TextXAlignment.Left
cardNote.LayoutOrder = 4

local openPanel: () -> ()
local cardBtn = UiKit.action(cardBody, "LEVAR VEÍCULO", "secondary", function()
	openPanel()
end, { action = "map_mark", ctx = "map", h = 38 })
cardBtn.button.LayoutOrder = 5
cardBtn.button.Selectable = false -- no controle quem abre é o X (a carta não navega pela interface)

local function cardLabel()
	local dev = Input.device()
	if dev == "gamepad" or dev == "touch" then
		cardBtn.label.Text = "LEVAR VEÍCULO"
	else
		local _, key = Input.glyph("map_mark", "map")
		cardBtn.label.Text = string.format("LEVAR VEÍCULO · %s", UiKit.upper(key))
	end
end
cardLabel()
Input.DeviceChanged:Connect(cardLabel)

-- ===== painel de escolha =====
-- D-236 (dono: "melhore oq eu apontei nas imagens com imagens melhores feitas com qualidade, efeitos
-- visuais"): no lugar da lista de botões, uma vitrine no meio da tela, com um cartão por viatura (a
-- imagem do modelo sobre a luz do lado, a ficha e os dois preços), sobre uma cena do jogo.
local PANEL_W = 880
local CARTAO_W = 412
local CARTAO_H = 338
local panel = UiKit.panel(stage, V.PANEL, 0, true)
panel.Name = "LevarVeiculo"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromOffset(DESIGN_W // 2, DESIGN_H // 2)
panel.Size = UDim2.fromOffset(PANEL_W, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.ClipsDescendants = true
panel.Visible = false
panel.ZIndex = 3
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
do
	local capa = (AssetIds.Capas or {}).posto
	if type(capa) == "number" and capa ~= 0 then
		local f = Instance.new("ImageLabel")
		f.Name = "Cena"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ScaleType = Enum.ScaleType.Crop
		f.Image = "rbxassetid://" .. capa
		f.ZIndex = -3
		f.Parent = panel
		local veu = Instance.new("Frame")
		veu.Name = "VeuCena"
		veu.BackgroundColor3 = Color3.fromRGB(13, 15, 11)
		veu.BorderSizePixel = 0
		veu.Size = UDim2.fromScale(1, 1)
		veu.ZIndex = -2
		veu.Parent = panel
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.3, 0.12),
			NumberSequenceKeypoint.new(1, 0.04),
		})
		g.Parent = veu
	end
end
local stripe = Instance.new("Frame")
stripe.Size = UDim2.new(1, 0, 0, 5)
stripe.BorderSizePixel = 0
stripe.Parent = panel
local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, 0, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.Parent = panel
UiKit.pad(body, 18, 18, 22, 22)
UiKit.list(body, false, 8)
local kicker = UiKit.kicker(body, "", 14)
kicker.Size = UDim2.new(1, 0, 0, 18)
kicker.LayoutOrder = 1
local title = UiKit.title(body, "LEVAR VEÍCULO", 36)
title.Size = UDim2.new(1, 0, 0, 42)
title.LayoutOrder = 2
local info = UiKit.text2(
	body,
	"Sai a 4-10 m de você, virado para o objetivo, quando você entra pelo QG ou por um ponto de reunião. Só é cobrado quando o lugar é achado. Um por vez; abandonado, some; destruído, não volta.",
	14,
	V.TEXT
)
info.Size = UDim2.new(1, 0, 0, 0)
info.AutomaticSize = Enum.AutomaticSize.Y
info.TextWrapped = true
info.TextXAlignment = Enum.TextXAlignment.Left
info.LayoutOrder = 3
local rows = Instance.new("Frame")
rows.Name = "Lista"
rows.BackgroundTransparency = 1
rows.Size = UDim2.new(1, 0, 0, CARTAO_H)
rows.LayoutOrder = 4
rows.Parent = body
do
	local l = UiKit.list(rows, true, 12) :: any
	if l then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
end
local rodape = Instance.new("Frame")
rodape.Name = "Rodape"
rodape.BackgroundTransparency = 1
rodape.Size = UDim2.new(1, 0, 0, 44)
rodape.LayoutOrder = 5
rodape.Parent = body
do
	local l = UiKit.list(rodape, true, 10) :: any
	if l then
		l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
end
local foot = UiKit.chips(body, 30, false, 13)
foot.frame.LayoutOrder = 6

-- ===== estado =====
type State = { spec: string?, pay: string?, state: string, msg: string?, cooldown: number, mine: number, team: number }
local st: State = { spec = nil, pay = nil, state = "none", msg = nil, cooldown = 0, mine = 0, team = 0 }
local stAt = os.clock()
local insertOpen = false
local asked = false
local robuxPrice: { [number]: number } = {}

local function cooldownLeft(): number
	return math.max(0, math.ceil(st.cooldown - (os.clock() - stAt)))
end

local function myCredits(): number
	local c = player:GetAttribute("Credits")
	return if type(c) == "number" then c else 0
end

local function priceRobux(id: number): number?
	if id == 0 then
		return nil
	end
	local p = robuxPrice[id]
	if p == nil then
		robuxPrice[id] = -1 -- buscando
		task.spawn(function()
			local ok, inf = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
			end)
			robuxPrice[id] = if ok
					and type(inf) == "table"
					and type(inf.PriceInRobux) == "number"
				then inf.PriceInRobux
				else -1
		end)
		return nil
	end
	return if p >= 0 then p else nil
end

local function paintCard()
	local f = faction()
	cardStripe.BackgroundColor3 = sideColor(f)
	local img = vehicleImage(st.spec)
	cardImage.Visible = img ~= nil
	cardImage.Image = img or ""
	local cd = cooldownLeft()
	if st.spec then
		cardTitle.Text = UiKit.upper(specName(st.spec))
		local item = CompraVeiculo.ITEMS[st.spec]
		if st.state == "reserved" then
			cardNote.Text = "Confirme a compra em Robux"
		elseif st.pay == "robux" then
			cardNote.Text = "Robux: a compra abre quando o lugar ao seu lado for achado"
		elseif item then
			cardNote.Text = string.format("%d CI, cobrados só quando o lugar for achado", item.credits)
		end
	else
		cardTitle.Text = "A PÉ"
		cardNote.Text = if cd > 0
			then string.format("Próximo veículo em %d s", cd)
			else "Escolha antes de inserir: QG ou ponto de reunião"
	end
	cardTitle.FontFace = UiKit.headFont(cardTitle.Text)
end

-- ===== linhas do painel =====
type Row = { action: UiKit.Action, refresh: () -> () }
local open: { rows: { Row }, cartoes: { Instance } } = { rows = {}, cartoes = {} }

local function close()
	if not panel.Visible then
		return
	end
	panel.Visible = false
	UiKit.release(panel)
	UiKit.closed(NAME)
	Input.closeMenu()
	if not alive() then
		GuiService.GuiNavigationEnabled = false -- a carta tem o cursor dela (GameUI)
	end
	for _, r in open.rows do
		r.action.button:Destroy()
	end
	table.clear(open.rows)
	for _, c in open.cartoes do
		c:Destroy() -- os efeitos do cartão param junto
	end
	table.clear(open.cartoes)
end

local function addRow(
	pai: Instance,
	text: string,
	kind: string,
	order: number,
	larg: UDim,
	onClick: () -> (),
	refresh: ((UiKit.Action) -> ())?
)
	local a = UiKit.action(pai, text, kind, onClick, { action = nil, ctx = nil, h = 44 })
	a.button.LayoutOrder = order
	a.button.Size = UDim2.new(larg, UDim.new(0, 44))
	local row: Row = {
		action = a,
		refresh = function()
			if refresh then
				refresh(a)
			end
		end,
	}
	row.refresh()
	table.insert(open.rows, row)
end

local function order(spec: string, pay: string)
	Net.event("Vehicle_Order"):FireServer({ spec = spec, pay = pay })
	close()
end

-- motivo de não poder agora (o servidor confere de novo): texto curto da linha
local function blockedWhy(): string?
	if st.state == "reserved" then
		return "COMPRA ESPERANDO"
	end
	if st.mine >= CompraVeiculo.RULES.perPlayer and st.spec == nil then
		return "JÁ TEM UM EM CAMPO"
	end
	if st.team >= CompraVeiculo.RULES.teamCap and st.spec == nil then
		return string.format("LADO NO TETO (%d)", CompraVeiculo.RULES.teamCap)
	end
	local cd = cooldownLeft()
	if cd > 0 then
		return string.format("ESPERA %d S", cd)
	end
	return nil
end

openPanel = function()
	local f = faction()
	local list = if f then CompraVeiculo.ORDER[f] else nil
	if panel.Visible or not (list and card.Visible) then
		return
	end
	local cor = sideColor(f)
	stripe.BackgroundColor3 = cor
	kicker.Text = UiKit.upper(string.format("veículo ao nascer · %s", SIDE_PT[f :: string] or ""))
	local n = 0
	for ordem, spec in list :: { string } do
		local item = CompraVeiculo.ITEMS[spec]
		local ficha = Vehicles.SPECS[spec]
		-- o cartão: a viatura sobre a luz do lado, o nome, a ficha e os dois preços
		local c = UiKit.panel(rows, V.PANEL_2, 0.08, true)
		c.Name = "Cartao_" .. spec
		c.LayoutOrder = ordem
		c.Size = UDim2.fromOffset(CARTAO_W, CARTAO_H)
		c.ClipsDescendants = true
		table.insert(open.cartoes, c)
		local traco = c:FindFirstChildOfClass("UIStroke")
		local luz = Instance.new("CanvasGroup") -- corta os raios girados dentro do cartão
		luz.Name = "Luz"
		luz.BackgroundTransparency = 1
		luz.BorderSizePixel = 0
		luz.Size = UDim2.new(1, 0, 0, 196)
		luz.ZIndex = 1
		luz.Parent = c
		UiEfeitos.halo(luz, UDim2.fromOffset(CARTAO_W // 2, 104), cor, 400, 0.45, 3.2, 1)
		UiEfeitos.raios(luz, Vector2.new(CARTAO_W // 2, 104), cor, 520, 3, 5, 1)
		local arte = Instance.new("ImageLabel")
		arte.Name = "Viatura"
		arte.BackgroundTransparency = 1
		arte.AnchorPoint = Vector2.new(0.5, 0)
		arte.Position = UDim2.new(0.5, 0, 0, 2)
		arte.Size = UDim2.new(1, -40, 0, 194)
		arte.ScaleType = Enum.ScaleType.Fit
		arte.Image = vehicleImage(spec) or ""
		arte.ZIndex = 3
		arte.Parent = c
		UiEfeitos.varre(c, 4.5 + ordem * 0.7, Color3.fromRGB(255, 244, 214), 4)
		local nome = UiKit.title(c, UiKit.upper(specName(spec)), 26)
		nome.Position = UDim2.fromOffset(14, 198)
		nome.Size = UDim2.new(1, -28, 0, 32)
		nome.ZIndex = 5
		local lugares = if ficha and ficha.seats then #ficha.seats else 0
		local kmh = if ficha then ficha.maxKmh else nil
		local dados = UiKit.text2(
			c,
			if kmh
				then string.format("%d lugares · até %d km/h", lugares, kmh)
				else string.format("%d lugares", lugares),
			15,
			V.KHAKI
		)
		dados.Position = UDim2.fromOffset(14, 230)
		dados.Size = UDim2.new(1, -28, 0, 22)
		dados.TextXAlignment = Enum.TextXAlignment.Left
		dados.ZIndex = 5
		local precos = Instance.new("Frame")
		precos.Name = "Precos"
		precos.BackgroundTransparency = 1
		precos.AnchorPoint = Vector2.new(0.5, 1)
		precos.Position = UDim2.new(0.5, 0, 1, -14)
		precos.Size = UDim2.new(1, -28, 0, 44)
		precos.ZIndex = 5
		precos.Parent = c
		UiKit.list(precos, true, 8)
		local id = CompraVeiculo.productId(spec)
		local meia = if id ~= 0 then UDim.new(0.5, -4) else UDim.new(1, 0)
		local function marcaEscolha()
			if traco then
				traco.Color = if st.spec == spec then V.BRASS else V.LINE
				traco.Thickness = if st.spec == spec then 3 else 1
				traco.Transparency = if st.spec == spec then 0 else 0.45
			end
		end
		n += 1
		-- cores de compra (UiKit.PAGAR, 2026-11-13): créditos âmbar, Robux verde, apagado sem saldo
		addRow(precos, string.format("%d CI", item.credits), "ci", 1, meia, function()
			order(spec, "ci")
		end, function(a: UiKit.Action)
			marcaEscolha()
			local why = blockedWhy()
			a.sub.Text = ""
			if st.spec == spec and st.pay == "ci" then
				a.label.Text = "ESCOLHIDO"
				a.enabled(false)
			elseif why then
				a.label.Text = why
				a.enabled(false)
			elseif myCredits() < item.credits then
				a.label.Text = string.format("FALTAM %d CI", item.credits - myCredits())
				a.enabled(false)
			else
				a.label.Text = string.format("%d CI", item.credits)
				a.enabled(true)
			end
		end)
		if id ~= 0 then
			n += 1
			addRow(precos, "ROBUX", "robux", 2, meia, function()
				order(spec, "robux")
			end, function(a: UiKit.Action)
				local why = blockedWhy()
				local p = priceRobux(id)
				a.sub.Text = ""
				if st.spec == spec and st.pay == "robux" then
					a.label.Text = "ESCOLHIDO"
					a.enabled(false)
				elseif why then
					a.label.Text = why
					a.enabled(false)
				else
					a.label.Text = if p then string.format("%d ROBUX", p) else "ROBUX"
					a.enabled(true)
				end
			end)
		end
	end
	addRow(rodape, "IR A PÉ", "ghost", 1, UDim.new(0, 170), function()
		Net.event("Vehicle_Order"):FireServer({ op = "cancel" })
		close()
	end, function(a: UiKit.Action)
		a.button.Visible = st.spec ~= nil and st.state ~= "reserved"
	end)
	addRow(rodape, "FECHAR", "ghost", 2, UDim.new(0, 170), close)
	foot.clear()
	foot.action("ui_back", "menu", "Fechar")
	panel.Visible = true
	-- a vitrine entra com um pulo curto (parada, com movimento reduzido)
	if UiKit.Estilo.reduzMovimento() then
		panelScale.Scale = 1
	else
		panelScale.Scale = 0.94
		TweenService:Create(panelScale, TweenInfo.new(0.24, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	Input.openMenu()
	UiKit.opened(NAME, ORDER)
	GuiService.GuiNavigationEnabled = true
	UiKit.focus(rows)
end

-- ===== entradas =====
-- X / tecla X na carta de inserção (o "marcar" só vale em campo)
Input.on("map_mark", "press", function()
	if card.Visible and not panel.Visible and not alive() then
		openPanel()
	end
end)
Input.on("ui_back", "press", function()
	if panel.Visible and UiKit.backFor(NAME) then
		close()
	end
end)

-- a DeployScreen avisa a cada desenho se a pasta de inserção está aberta
Bus.on("insercao_painel", function(on: any)
	insertOpen = on == true
end)

Net.event("Vehicle_OrderState").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" then
		return
	end
	st = {
		spec = if type(msg.spec) == "string" then msg.spec else nil,
		pay = if type(msg.pay) == "string" then msg.pay else nil,
		state = if type(msg.state) == "string" then msg.state else "none",
		msg = if type(msg.msg) == "string" then msg.msg else nil,
		cooldown = if type(msg.cooldown) == "number" then msg.cooldown else 0,
		mine = if type(msg.mine) == "number" then msg.mine else 0,
		team = if type(msg.team) == "number" then msg.team else 0,
	}
	stAt = os.clock()
	if st.msg then
		Bus.fire("toast", st.msg) -- recusa do pedido na carta (o que acontece ao nascer vem pelo Vehicle_Notice)
	end
	paintCard()
	for _, r in open.rows do
		r.refresh()
	end
end)

player:GetAttributeChangedSignal("Faction"):Connect(function()
	st = { spec = nil, pay = nil, state = "none", msg = nil, cooldown = 0, mine = 0, team = 0 }
	close()
	paintCard()
end)

-- cartão só na carta de inserção, morto, sem outra tela por cima
local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 0.2 then
		return
	end
	acc = 0
	local f = faction()
	local top = UiKit.top()
	local show = insertOpen
		and player:GetAttribute("MenuPrincipal") ~= true -- a carta fica atrás do menu principal (D-118)
		and not alive()
		and f ~= nil
		and CompraVeiculo.ORDER[f] ~= nil
		and not SpawnTransition.busy()
		and (top == nil or top == NAME)
	if show and not asked then
		asked = true
		Net.event("Vehicle_Order"):FireServer({ op = "get" })
	end
	if card.Visible ~= show then
		card.Visible = show
		if show then
			paintCard()
		end
	end
	if not show then
		close()
		return
	end
	if panel.Visible then
		GuiService.GuiNavigationEnabled = true -- o GameUI desliga ao redesenhar a carta
		local sel = GuiService.SelectedObject
		if Input.isGamepad() and not (sel and sel:IsDescendantOf(panel)) then
			UiKit.focus(rows)
		end
		for _, r in open.rows do
			r.refresh()
		end
	end
	if st.spec == nil then
		paintCard() -- a espera conta no cartão
	end
end)

paintCard()
