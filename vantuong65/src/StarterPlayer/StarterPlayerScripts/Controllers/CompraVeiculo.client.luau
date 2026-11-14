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

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Net = require(ReplicatedStorage.Shared.Net)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local SpawnTransition = require(script.Parent.SpawnTransition)
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
local CARD_W = 172
local card = UiKit.panel(stage, V.PANEL, 0.08, true)
card.Name = "Veiculo"
card.Position = UDim2.fromOffset(1240 - 8 - CARD_W, 146 + 84)
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
cardImage.Size = UDim2.new(1, 0, 0, 114)
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
local PANEL_W = 360
local panel = UiKit.panel(stage, V.PANEL, 0.04, true)
panel.Name = "LevarVeiculo"
panel.Position = UDim2.fromOffset(1240 - 8 - PANEL_W, 154)
panel.Size = UDim2.fromOffset(PANEL_W, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Visible = false
panel.ZIndex = 3
local stripe = Instance.new("Frame")
stripe.Size = UDim2.new(1, 0, 0, 5)
stripe.BorderSizePixel = 0
stripe.Parent = panel
local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, 0, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.Parent = panel
UiKit.pad(body, 14, 14, 14, 14)
UiKit.list(body, false, 6)
local kicker = UiKit.kicker(body, "", 13)
kicker.Size = UDim2.new(1, 0, 0, 18)
kicker.LayoutOrder = 1
local title = UiKit.title(body, "LEVAR VEÍCULO", 26)
title.Size = UDim2.new(1, 0, 0, 32)
title.LayoutOrder = 2
local info = UiKit.text2(
	body,
	"Sai a 4-10 m de você, virado para o objetivo, quando você entra pelo QG ou por um ponto de reunião. Só é cobrado quando o lugar é achado. Um por vez; abandonado, some; destruído, não volta.",
	13,
	V.DIM
)
info.Size = UDim2.new(1, 0, 0, 0)
info.AutomaticSize = Enum.AutomaticSize.Y
info.TextWrapped = true
info.TextXAlignment = Enum.TextXAlignment.Left
info.LayoutOrder = 3
local rows = Instance.new("Frame")
rows.Name = "Lista"
rows.BackgroundTransparency = 1
rows.Size = UDim2.new(1, 0, 0, 0)
rows.AutomaticSize = Enum.AutomaticSize.Y
rows.LayoutOrder = 4
rows.Parent = body
UiKit.list(rows, false, 4)
local foot = UiKit.chips(body, 30, false, 13)
foot.frame.LayoutOrder = 5

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
local open: { rows: { Row } } = { rows = {} }

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
end

local function addRow(text: string, kind: string, order: number, onClick: () -> (), refresh: ((UiKit.Action) -> ())?)
	local a = UiKit.action(rows, text, kind, onClick, { action = nil, ctx = nil, h = 44 })
	a.button.LayoutOrder = order
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
	stripe.BackgroundColor3 = sideColor(f)
	kicker.Text = UiKit.upper(string.format("veículo ao nascer · %s", SIDE_PT[f :: string] or ""))
	local n = 0
	for _, spec in list :: { string } do
		local item = CompraVeiculo.ITEMS[spec]
		local name = UiKit.upper(specName(spec))
		n += 1
		-- cores de compra (UiKit.PAGAR, 2026-11-13): créditos âmbar, Robux verde, apagado sem saldo
		addRow(name, "ci", n, function()
			order(spec, "ci")
		end, function(a: UiKit.Action)
			local why = blockedWhy()
			local chosen = st.spec == spec and st.pay == "ci"
			if chosen then
				a.sub.Text = "ESCOLHIDO · " .. string.format("%d CI", item.credits)
				a.enabled(false)
			elseif why then
				a.sub.Text = why
				a.enabled(false)
			elseif myCredits() < item.credits then
				a.sub.Text = string.format("FALTAM %d CI", item.credits - myCredits())
				a.enabled(false)
			else
				a.sub.Text = string.format("%d CI", item.credits)
				a.enabled(true)
			end
		end)
		local id = CompraVeiculo.productId(spec)
		if id ~= 0 then
			n += 1
			addRow(name, "robux", n, function()
				order(spec, "robux")
			end, function(a: UiKit.Action)
				local why = blockedWhy()
				local p = priceRobux(id)
				local price = if p then string.format("%d ROBUX", p) else "ROBUX"
				if st.spec == spec and st.pay == "robux" then
					a.sub.Text = "ESCOLHIDO · " .. price
					a.enabled(false)
				elseif why then
					a.sub.Text = why
					a.enabled(false)
				else
					a.sub.Text = price
					a.enabled(true)
				end
			end)
		end
	end
	addRow("IR A PÉ", "ghost", n + 1, function()
		Net.event("Vehicle_Order"):FireServer({ op = "cancel" })
		close()
	end, function(a: UiKit.Action)
		a.button.Visible = st.spec ~= nil and st.state ~= "reserved"
	end)
	addRow("FECHAR", "ghost", n + 2, close)
	foot.clear()
	foot.action("ui_back", "menu", "Fechar")
	panel.Visible = true
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
