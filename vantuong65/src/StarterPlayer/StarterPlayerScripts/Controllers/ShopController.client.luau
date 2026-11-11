--!strict
-- Loja (menu do jogo → Loja, tecla L ou a caixa de munição da mesa do lobby): passes cosméticos,
-- apoio, Premium, assinatura e o armário. Visual de formulário de requisição de 1965 (papel, máquina
-- de escrever, carimbo), com a mesma tinta do lobby.
-- Navegável no controle: abre com foco no 1º item, A compra/equipa, B fecha (Parte 12.5). No lobby,
-- o cursor virtual do controle também clica aqui (todo botão é UiKit.button/UiKit.bind).
-- Os preços são lidos ao vivo (GetProductInfoAsync) para o Managed Pricing do Roblox valer.
-- Ao fechar avisa o lobby (Bus "shop_closed"), que devolve a câmera para a mesa.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local HEAD, TYPE = Enum.Font.Oswald, Enum.Font.SpecialElite

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
folder.AnchorPoint = Vector2.new(0.5, 0.5)
folder.Position = UDim2.fromScale(0.5, 0.5)
folder.Size = UDim2.fromOffset(if UiKit.tv() then 760 else 600, if UiKit.tv() then 700 else 600)
folder.BackgroundColor3 = UiKit.MANILA
folder.BorderSizePixel = 0
folder.Active = true -- tapa a mesa do lobby atrás (o clique não atravessa)
folder.Parent = gui
local fit = Instance.new("UISizeConstraint")
fit.MaxSize = Vector2.new(900, 900)
fit.Parent = folder
local openScale = Instance.new("UIScale") -- a pasta "abre" ao aparecer
openScale.Parent = folder
local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(0, 4)
fc.Parent = folder
local fs = Instance.new("UIStroke")
fs.Color = UiKit.INK
fs.Transparency = 0.6
fs.Parent = folder

local function text(parent: Instance, s: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextSize = UiKit.text(size)
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Text = s
	t.Parent = parent
	return t
end

local title = text(folder, "INTENDÊNCIA · FORMULÁRIO DE REQUISIÇÃO", HEAD, 24, UiKit.INK)
title.Position = UDim2.fromOffset(18, 10)
title.Size = UDim2.new(1, -170, 0, 34)
local sub = text(folder, "Tudo aqui é visual ou apoio. Nada vende vantagem em combate.", TYPE, 15, UiKit.INK)
sub.Position = UDim2.fromOffset(18, 44)
sub.Size = UDim2.new(1, -36, 0, 22)

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 12)
close.Size = UDim2.fromOffset(132, if UiKit.tv() then 46 else 34)
close.BackgroundColor3 = UiKit.DRAB
close.TextColor3 = UiKit.KHAKI
close.Font = HEAD
close.TextSize = UiKit.text(17)
close.Text = "FECHAR ✕"
close.AutoButtonColor = true
close.Selectable = true
close.SelectionImageObject = UiKit.FOCUS
close.Parent = folder

-- folha pautada com a lista (rola no analógico direito ou na roda do mouse)
local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.fromOffset(14, 74)
panel.Size = UDim2.new(1, -28, 1, -88)
panel.BackgroundColor3 = UiKit.CARD
panel.BorderSizePixel = 0
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.ScrollBarThickness = 8
panel.ScrollBarImageColor3 = UiKit.INK
panel.Parent = folder
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 12)
pad.Parent = panel

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
	local p = if ok and info and info.PriceInRobux then "R$ " .. tostring(info.PriceInRobux) else "—"
	priceCache[key] = p
	return p
end

local function label(s: string, bold: boolean?)
	order += 1
	local t = text(panel, s, if bold then HEAD else TYPE, if bold then 19 else 15, UiKit.INK)
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.LayoutOrder = order
	if bold then
		local rule = Instance.new("Frame")
		rule.BackgroundColor3 = UiKit.RULE_RED
		rule.BorderSizePixel = 0
		rule.AnchorPoint = Vector2.new(0, 1)
		rule.Position = UDim2.fromScale(0, 1)
		rule.Size = UDim2.new(1, 0, 0, 2)
		rule.Parent = t
	end
end

local function button(s: string, onClick: () -> ())
	order += 1
	local b = UiKit.button(panel, s, onClick, order)
	b.Size = UDim2.new(1, 0, 0, if UiKit.tv() then 48 else 34)
	b.BackgroundColor3 = UiKit.DRAB
	b.TextColor3 = UiKit.KHAKI
	b.Font = HEAD
	b.TextSize = UiKit.text(16)
end

local function render()
	for _, c in panel:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	order = 0
	local listed = false
	for _, pass in Commerce.Passes do
		local id = (Commerce.IDS :: any)[pass.key] :: number
		if id ~= 0 then
			listed = true
			label(pass.name, true)
			label(pass.description)
			if state.passes[pass.key] then
				label("✔ Já é seu")
			else
				button("REQUISITAR  " .. price(id, Enum.InfoType.GamePass), function()
					Net.event("Commerce_Track"):FireServer("prompt", pass.key)
					MarketplaceService:PromptGamePassPurchase(player, id)
				end)
			end
		end
	end
	for _, prod in Commerce.Products do
		local id = (Commerce.IDS :: any)[prod.key] :: number
		if id ~= 0 then
			listed = true
			label(prod.name, true)
			label(prod.description)
			button("APOIAR  " .. price(id, Enum.InfoType.Product), function()
				Net.event("Commerce_Track"):FireServer("prompt", prod.key)
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		end
	end
	local sid = Commerce.IDS.SUBSCRIPTION_UNIT_RESERVE
	if sid ~= "" and not state.subscription then
		listed = true
		label("Reserva da Unidade (mensal)", true)
		label("Um item histórico por temporada e a fita da Reserva.")
		button("ASSINAR", function()
			Net.event("Commerce_Track"):FireServer("prompt", "SUBSCRIPTION")
			MarketplaceService:PromptSubscriptionPurchase(player, sid)
		end)
	end
	if not state.premium then
		listed = true
		label("Roblox Premium", true)
		label("Libera a capa Mitchell desbotada e o lenço xadrez (visuais).")
		button("CONHECER O PREMIUM", function()
			Net.event("Commerce_Track"):FireServer("prompt", "PREMIUM")
			MarketplaceService:PromptPremiumPurchase(player)
		end)
	end
	if not listed then
		label("Nenhum item à venda neste servidor.")
	end
	-- armário: só itens liberados (passe, Premium ou ganhos na caderneta); o servidor valida ao equipar
	local faction = player:GetAttribute("Faction") :: string?
	if faction then
		label("ARMÁRIO — " .. (if faction == "US" then "EUA" else "VC"), true)
		for _, c in Commerce.Cosmetics do
			if c.faction == faction and table.find(state.unlocked, c.id) then
				local eq = state.equipped[faction] and state.equipped[faction][c.slot] == c.id
				local tag = if c.unlock == "daily" then "  (caderneta)" else ""
				button((if eq then "● " else "○ ") .. c.slot .. ": " .. c.name .. tag, function()
					Net.event("Commerce_Equip"):FireServer(faction, c.slot, c.id)
				end)
			end
		end
		label("Os dias 3 e 7 da caderneta de serviço (recompensa diária) dão itens que só saem de lá.")
	end
end

Net.event("Commerce_State").OnClientEvent:Connect(function(s)
	state = s
	if gui.Enabled then
		render()
	end
end)

local function setOpen(open: boolean)
	if open == gui.Enabled then
		return
	end
	gui.Enabled = open
	if open then
		openScale.Scale = 0.9
		folder.Position = UDim2.new(0.5, 0, 0.5, 30)
		TweenService:Create(openScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		TweenService:Create(folder, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
		}):Play()
		Input.openMenu()
		Net.event("Commerce_Track"):FireServer("store_open")
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
UiKit.watch(panel, function()
	return gui.Enabled
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.L then
		setOpen(not gui.Enabled)
	end
end)
