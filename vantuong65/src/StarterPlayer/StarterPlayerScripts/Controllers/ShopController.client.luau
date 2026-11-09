--!strict
-- Loja (tecla B): passes cosméticos, apoio, Premium, assinatura e o armário de cosméticos.
-- Os preços são lidos ao vivo (GetProductInfoAsync) para o Managed Pricing do Roblox valer.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Commerce = require(ReplicatedStorage.Shared.Commerce)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Shop"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.fromOffset(560, 560)
panel.Position = UDim2.new(0.5, -280, 0.5, -280)
panel.BackgroundColor3 = Color3.fromRGB(214, 203, 170)
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = panel

local state: any = { passes = {}, unlocked = {}, equipped = {} }
local priceCache: { [string]: string } = {}

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

local function label(text: string, bold: boolean?)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -12, 0, if bold then 30 else 44)
	t.BackgroundTransparency = 1
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = Color3.fromRGB(40, 36, 28)
	t.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	t.TextSize = if bold then 18 else 14
	t.Text = text
	t.Parent = panel
end

local function button(text: string, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -12, 0, 34)
	b.BackgroundColor3 = Color3.fromRGB(96, 104, 70)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 15
	b.Text = text
	b.Parent = panel
	b.Activated:Connect(onClick)
end

local function render()
	for _, c in panel:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	label("Intendência — tudo aqui é visual ou apoio. Nada vende vantagem em combate.", true)
	for _, pass in Commerce.Passes do
		local id = (Commerce.IDS :: any)[pass.key] :: number
		if id ~= 0 then
			label(pass.name .. " — " .. pass.description)
			if state.passes[pass.key] then
				label("✔ Já é seu")
			else
				button("Comprar  " .. price(id, Enum.InfoType.GamePass), function()
					Net.event("Commerce_Track"):FireServer("prompt", pass.key)
					MarketplaceService:PromptGamePassPurchase(player, id)
				end)
			end
		end
	end
	for _, prod in Commerce.Products do
		local id = (Commerce.IDS :: any)[prod.key] :: number
		if id ~= 0 then
			label(prod.name .. " — " .. prod.description)
			button("Apoiar  " .. price(id, Enum.InfoType.Product), function()
				Net.event("Commerce_Track"):FireServer("prompt", prod.key)
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		end
	end
	local sid = Commerce.IDS.SUBSCRIPTION_UNIT_RESERVE
	if sid ~= "" and not state.subscription then
		label("Reserva da Unidade (mensal) — um item histórico por temporada e a fita da Reserva.")
		button("Assinar", function()
			Net.event("Commerce_Track"):FireServer("prompt", "SUBSCRIPTION")
			MarketplaceService:PromptSubscriptionPurchase(player, sid)
		end)
	end
	if not state.premium then
		label("Roblox Premium — libera a capa Mitchell desbotada e o lenço xadrez (visuais).")
		button("Conhecer o Premium", function()
			Net.event("Commerce_Track"):FireServer("prompt", "PREMIUM")
			MarketplaceService:PromptPremiumPurchase(player)
		end)
	end
	-- armário: só itens liberados; o servidor valida de novo ao equipar
	local faction = player:GetAttribute("Faction") :: string?
	if faction then
		label("Armário — " .. faction, true)
		for _, c in Commerce.Cosmetics do
			if c.faction == faction and table.find(state.unlocked, c.id) then
				local eq = state.equipped[faction] and state.equipped[faction][c.slot] == c.id
				button((if eq then "● " else "○ ") .. c.slot .. ": " .. c.name, function()
					Net.event("Commerce_Equip"):FireServer(faction, c.slot, c.id)
				end)
			end
		end
	end
end

Net.event("Commerce_State").OnClientEvent:Connect(function(s)
	state = s
	if gui.Enabled then
		render()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			Net.event("Commerce_Track"):FireServer("store_open")
			task.spawn(function()
				local ok, s = pcall(function()
					return Net.func("Commerce_GetState"):InvokeServer()
				end)
				if ok and s then
					state = s
				end
				render()
			end)
		end
	end
end)
