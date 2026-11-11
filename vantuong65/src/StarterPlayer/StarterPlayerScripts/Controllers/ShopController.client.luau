--!strict
-- Loja (menu do jogo → Loja, tecla L ou a caixa de munição da mesa do lobby): passes cosméticos,
-- apoio, Premium, assinatura e o armário. Visual de formulário de requisição de 1965: pasta parda,
-- folha pautada com linha vermelha, cada item numa ficha com o nome em Oswald, a descrição em Arimo
-- e o preço num botão de latão; o que já é seu leva o carimbo verde "SEU".
-- Navegável no controle: abre com foco no 1º item, A compra/equipa, B fecha (Parte 12.5). No lobby,
-- o cursor virtual do controle também clica aqui (todo botão passa por UiKit.bind).
-- Os preços são lidos ao vivo (GetProductInfoAsync) para o Managed Pricing do Roblox valer.
-- Ao fechar avisa o lobby (Bus "shop_closed"), que devolve a câmera para a mesa.
-- A Intendência (Progresso.client) abre junto, à esquerda: a pasta fica à direita dela e encolhe
-- para não cobrir o painel (antes, numa tela de 1280 px, as duas se sobrepunham).
-- Só no Studio: workspace:SetAttribute("VT65DevTela", "loja") abre a loja.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end
local W, H = px(620, 820), px(620, 780)
local LEFT = px(24 + 400 + 24, 24 + 470 + 24) -- a Intendência ocupa a esquerda
local OLIVE_INK = Color3.fromRGB(58, 82, 44)

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

-- pasta parda com a folha de requisição por cima
local folder = Instance.new("Frame")
folder.Name = "Pasta"
folder.AnchorPoint = Vector2.new(1, 0.5)
folder.Position = UDim2.new(1, -24, 0.5, 0)
folder.Size = UDim2.fromOffset(W, H)
folder.BackgroundColor3 = UiKit.MANILA
folder.BorderSizePixel = 0
folder.Active = true -- tapa a mesa do lobby atrás (o clique não atravessa)
folder.Parent = gui
UiKit.corner(folder, 5)
UiKit.lit(folder, 0.8)
UiKit.edge(folder, UiKit.INK, 1, 0.55)
local openScale = Instance.new("UIScale") -- a pasta "abre" ao aparecer; também é a escala de ajuste
openScale.Parent = folder
Acabamento.sombra(folder, 24, Vector2.new(0, 9), 0.6)

-- escala: cabe à direita da Intendência; numa janela estreita demais, ocupa o centro
local fitK = 1
local function fit()
	local a = gui.AbsoluteSize
	if a.X < 10 then
		return
	end
	local room = a.X - LEFT - 24
	if room < W * 0.55 then
		folder.AnchorPoint = Vector2.new(0.5, 0.5)
		folder.Position = UDim2.fromScale(0.5, 0.5)
		room = a.X - 32
	else
		folder.AnchorPoint = Vector2.new(1, 0.5)
		folder.Position = UDim2.new(1, -24, 0.5, 0)
	end
	fitK = math.clamp(math.min(room / W, (a.Y - 32) / H), 0.45, 1)
	openScale.Scale = fitK
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

local kicker = UiKit.rotulo(folder, px(14, 22), UiKit.INK, UiKit.TYPE_FONT)
kicker.Position = UDim2.fromOffset(px(20, 26), px(12, 16))
kicker.Size = UDim2.new(1, -px(180, 240), 0, px(18, 26))
kicker.TextTransparency = 0.3
kicker.Text = "FORMULÁRIO DE REQUISIÇÃO · INTENDÊNCIA · 1965"
local title = UiKit.rotulo(folder, px(28, 40), UiKit.INK, UiKit.HEAD_FONT)
title.Position = UDim2.fromOffset(px(18, 24), px(28, 38))
title.Size = UDim2.new(1, -px(180, 240), 0, px(38, 52))
title.Text = "LOJA E ARMÁRIO"
local sub = UiKit.rotulo(folder, px(14, 22), UiKit.INK, UiKit.BODY_FONT)
sub.Position = UDim2.fromOffset(px(20, 26), px(66, 92))
sub.Size = UDim2.new(1, -px(40, 52), 0, px(20, 28))
sub.TextTransparency = 0.15
sub.Text = "Tudo aqui é visual ou apoio. Nada vende vantagem em combate."

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -px(16, 22), 0, px(16, 22))
close.Size = UDim2.fromOffset(px(118, 160), px(36, 50))
close.BackgroundColor3 = UiKit.DRAB
close.AutoButtonColor = false
close.TextColor3 = UiKit.KHAKI
close.FontFace = UiKit.HEAD_FONT
close.TextSize = UiKit.text(16)
close.Text = "FECHAR ✕"
close.Selectable = false -- no controle, B
close.Parent = folder
UiKit.corner(close, 3)
UiKit.lit(close, 0.72)

-- folha pautada com a lista (rola no analógico direito ou na roda do mouse)
local TOP = px(96, 132)
local FOOT = px(44, 62)
local sheet = Instance.new("Frame")
sheet.Name = "Folha"
sheet.Position = UDim2.fromOffset(px(12, 16), TOP)
sheet.Size = UDim2.new(1, -2 * px(12, 16), 1, -(TOP + FOOT))
sheet.BackgroundColor3 = UiKit.CARD
sheet.BorderSizePixel = 0
sheet.Parent = folder
UiKit.corner(sheet, 3)
UiKit.lit(sheet, 0.9)
UiKit.edge(sheet, UiKit.INK, 1, 0.6)
do
	local r = Instance.new("Frame")
	r.BackgroundColor3 = UiKit.RULE_RED
	r.BorderSizePixel = 0
	r.Position = UDim2.fromOffset(0, 3)
	r.Size = UDim2.new(1, 0, 0, 2)
	r.Parent = sheet
end
local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.fromOffset(0, 8)
panel.Size = UDim2.new(1, 0, 1, -10)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.ScrollBarThickness = px(6, 8)
panel.ScrollBarImageColor3 = UiKit.INK
panel.ScrollBarImageTransparency = 0.5
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

local foot = UiKit.chips(folder, px(30, 44), true, px(14, 22))
foot.frame.AnchorPoint = Vector2.new(0, 1)
foot.frame.Position = UDim2.new(0, px(20, 26), 1, -px(8, 12))
foot.frame.Size = UDim2.new(1, -px(40, 52), 0, px(30, 44))

local state: any = { passes = {}, unlocked = {}, equipped = {} }
local priceCache: { [string]: string } = {}
local order = 0

local function price(id: number, infoType: Enum.InfoType): string
	local key = tostring(infoType) .. id
	if priceCache[key] then
		return priceCache[key]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, infoType)
	end)
	local p = if ok and info and info.PriceInRobux then string.format("R$ %d", info.PriceInRobux) else "—"
	priceCache[key] = p
	return p
end

local function section(text: string)
	order += 1
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -24, 0, px(30, 42))
	f.Parent = panel
	local t = UiKit.rotulo(f, 16, UiKit.INK, UiKit.HEAD_FONT)
	t.Size = UDim2.new(1, 0, 1, -4)
	t.Text = text
	t.FontFace = UiKit.headFont(text)
	local r = Instance.new("Frame")
	r.AnchorPoint = Vector2.new(0, 1)
	r.Position = UDim2.fromScale(0, 1)
	r.Size = UDim2.new(1, 0, 0, 2)
	r.BackgroundColor3 = UiKit.RULE_RED
	r.BorderSizePixel = 0
	r.Parent = f
end

local function note(text: string)
	order += 1
	local t = UiKit.rotulo(panel, 14, UiKit.OLIVE, UiKit.TYPE_FONT)
	t.LayoutOrder = order
	t.Size = UDim2.new(1, -28, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.TextWrapped = true
	t.Text = text
end

-- ficha de item: nome e descrição à esquerda; à direita o botão (preço/ação) ou o carimbo SEU
local function item(
	key: string,
	name: string,
	desc: string?,
	buttonText: string?,
	onClick: (() -> ())?,
	owned: boolean?
)
	order += 1
	local card = Instance.new("Frame")
	card.Name = key
	card.LayoutOrder = order
	card.BackgroundColor3 = Color3.fromRGB(242, 236, 214)
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, -24, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = panel
	UiKit.corner(card, 3)
	UiKit.edge(card, UiKit.INK, 1, 0.75)
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingRight = UDim.new(0, px(12, 16)), UDim.new(0, px(12, 16))
	p.PaddingTop, p.PaddingBottom = UDim.new(0, px(8, 12)), UDim.new(0, px(10, 14))
	p.Parent = card
	local right = px(170, 230)
	local n = UiKit.rotulo(card, 18, UiKit.INK, UiKit.HEAD_FONT)
	n.Size = UDim2.new(1, -right, 0, px(24, 34))
	n.Text = name
	n.FontFace = UiKit.headFont(name)
	n.TextTruncate = Enum.TextTruncate.AtEnd
	if desc and desc ~= "" then
		local d = UiKit.rotulo(card, 14, UiKit.INK, UiKit.BODY_FONT)
		d.Position = UDim2.fromOffset(0, px(26, 36))
		d.Size = UDim2.new(1, -right, 0, 0)
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.TextWrapped = true
		d.TextTransparency = 0.15
		d.Text = desc
	end
	if owned then
		local s = UiKit.rotulo(card, 18, OLIVE_INK, UiKit.HEAD_FONT)
		s.AnchorPoint = Vector2.new(1, 0)
		s.Position = UDim2.new(1, -8, 0, 2)
		s.Size = UDim2.fromOffset(right - 30, px(32, 44))
		s.TextXAlignment = Enum.TextXAlignment.Center
		s.Rotation = -6
		s.Text = "✔ SEU"
		UiKit.edge(s, OLIVE_INK, 2, 0.2)
	elseif buttonText and onClick then
		local b = Instance.new("TextButton")
		b.Name = "Botao"
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, 0, 0, 0)
		b.Size = UDim2.fromOffset(right - 16, px(36, 50))
		b.BackgroundColor3 = UiKit.BRASS
		b.AutoButtonColor = false
		b.FontFace = UiKit.HEAD_FONT
		b.TextColor3 = UiKit.NIGHT
		b.TextSize = UiKit.text(16)
		b.Text = buttonText
		b.TextWrapped = true
		b.Selectable = true
		b.SelectionImageObject = UiKit.FOCUS
		b.Parent = card
		UiKit.corner(b, 3)
		UiKit.lit(b, 0.78)
		local r = UiKit.realce(b, UiKit.BRASS, UiKit.BRASS_LIGHT, 1.04)
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
end

-- linha do armário: um botão por item (● equipado, ○ não)
local function lockerRow(key: string, text: string, on: boolean, onClick: () -> ())
	order += 1
	local b = Instance.new("TextButton")
	b.Name = key
	b.LayoutOrder = order
	b.Size = UDim2.new(1, -24, 0, px(38, 54))
	b.BackgroundColor3 = if on then UiKit.DRAB else Color3.fromRGB(242, 236, 214)
	b.AutoButtonColor = false
	b.Text = ""
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = panel
	UiKit.corner(b, 3)
	UiKit.edge(b, UiKit.INK, 1, 0.7)
	local mark = UiKit.rotulo(b, 16, if on then UiKit.BRASS else UiKit.OLIVE, Enum.Font.ArimoBold)
	mark.Position = UDim2.fromOffset(px(12, 16), 0)
	mark.Size = UDim2.new(0, px(22, 30), 1, 0)
	mark.Text = if on then "●" else "○"
	local t = UiKit.rotulo(b, 16, if on then UiKit.CARD else UiKit.INK, UiKit.BODY_FONT)
	t.Position = UDim2.fromOffset(px(38, 52), 0)
	t.Size = UDim2.new(1, -px(50, 66), 1, 0)
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	local r = UiKit.realce(b, b.BackgroundColor3, if on then UiKit.OLIVE else Color3.fromRGB(250, 244, 226), 1.01)
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
		foot.add(UiKit.padImage(Enum.KeyCode.ButtonA), nil, "A", "Requisitar / equipar")
		foot.action("ui_back", "menu", "Fechar")
	elseif dev == "touch" then
		foot.add(nil, nil, "Toque", "no botão do item")
	else
		foot.add(nil, nil, "Clique", "no botão do item")
		foot.action("ui_back", "menu", "Fechar")
		foot.add(nil, nil, "L", "Loja")
	end
end

local function render()
	for _, c in panel:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
	local listed = false
	local passes, products = {}, {}
	for _, pass in Commerce.Passes do
		if (Commerce.IDS :: any)[pass.key] ~= 0 then
			table.insert(passes, pass)
		end
	end
	for _, prod in Commerce.Products do
		if (Commerce.IDS :: any)[prod.key] ~= 0 then
			table.insert(products, prod)
		end
	end
	if #passes > 0 then
		section("Passes")
		for _, pass in passes do
			listed = true
			local id = (Commerce.IDS :: any)[pass.key] :: number
			local mine = state.passes[pass.key] == true
			item(
				"pass:" .. pass.key,
				pass.name,
				pass.description,
				string.format("REQUISITAR · %s", price(id, Enum.InfoType.GamePass)),
				function()
					Net.event("Commerce_Track"):FireServer("prompt", pass.key)
					MarketplaceService:PromptGamePassPurchase(player, id)
				end,
				mine
			)
		end
	end
	if #products > 0 then
		section("Apoio")
		for _, prod in products do
			listed = true
			local id = (Commerce.IDS :: any)[prod.key] :: number
			item(
				"prod:" .. prod.key,
				prod.name,
				prod.description,
				string.format("APOIAR · %s", price(id, Enum.InfoType.Product)),
				function()
					Net.event("Commerce_Track"):FireServer("prompt", prod.key)
					MarketplaceService:PromptProductPurchase(player, id)
				end
			)
		end
	end
	local sid = Commerce.IDS.SUBSCRIPTION_UNIT_RESERVE
	if sid ~= "" and not state.subscription then
		listed = true
		section("Assinatura")
		item(
			"sub",
			"Reserva da Unidade (mensal)",
			"Um item histórico por temporada e a fita da Reserva.",
			"ASSINAR",
			function()
				Net.event("Commerce_Track"):FireServer("prompt", "SUBSCRIPTION")
				MarketplaceService:PromptSubscriptionPurchase(player, sid)
			end
		)
	end
	if not state.premium then
		listed = true
		section("Roblox Premium")
		item(
			"premium",
			"Roblox Premium",
			"Libera a capa Mitchell desbotada e o lenço xadrez (visuais).",
			"CONHECER O PREMIUM",
			function()
				Net.event("Commerce_Track"):FireServer("prompt", "PREMIUM")
				MarketplaceService:PromptPremiumPurchase(player)
			end
		)
	end
	if not listed then
		note("Nenhum item à venda neste servidor.")
	end
	-- armário: só itens liberados (passe, Premium ou ganhos na caderneta); o servidor valida ao equipar
	local faction = player:GetAttribute("Faction") :: string?
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

Net.event("Commerce_State").OnClientEvent:Connect(function(s)
	state = s
	if gui.Enabled then
		render()
	end
end)

local closeToken = 0
local function setOpen(open: boolean)
	if open == gui.Enabled then
		return
	end
	closeToken += 1
	local my = closeToken
	if open then
		gui.Enabled = true
		fit()
		openScale.Scale = fitK * 0.92
		local p = folder.Position
		folder.Position = p + UDim2.fromOffset(0, 30)
		TweenService:Create(openScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = fitK,
		}):Play()
		TweenService:Create(folder, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = p,
		}):Play()
		Input.openMenu()
		Net.event("Commerce_Track"):FireServer("store_open")
		render()
		task.spawn(function()
			local ok, s = pcall(function()
				return Net.func("Commerce_GetState"):InvokeServer()
			end)
			if ok and s then
				state = s
			end
			render()
			UiKit.focus(panel)
		end)
	else
		Input.closeMenu()
		Bus.fire("shop_closed")
		local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(openScale, info, { Scale = fitK * 0.95 }):Play()
		task.delay(0.16, function()
			if closeToken == my then
				gui.Enabled = false
			end
		end)
	end
end

UiKit.bind(close, function()
	setOpen(false)
end)
Bus.on("shop_open", function()
	setOpen(true)
end)
Input.on("ui_back", "press", function()
	setOpen(false)
end)
Input.DeviceChanged:Connect(function()
	if gui.Enabled then
		renderFoot()
	end
end)
UiKit.watch(panel, function()
	return gui.Enabled
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.L and not UserInputService:GetFocusedTextBox() then
		setOpen(not gui.Enabled)
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "loja" then
			Bus.fire("shop_open")
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
