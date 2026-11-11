--!strict
-- Progressão no cliente (D-72): avisos de ganho (+XP, +CI), a cerimônia de promoção e o painel de
-- equipamento de campo na Intendência do lobby (abre junto com a loja: Bus "shop_open"). O servidor
-- (ProgressionService) decide tudo; aqui só se mostra e se pede (Gear_Buy, Gear_Equip).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local screen = UiKit.screen("VT65Progresso", 40)
local state: { [string]: any }? = nil

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

-- ===== avisos de ganho (embaixo, no centro) =====
local toasts = Instance.new("Frame")
toasts.Name = "Ganhos"
toasts.BackgroundTransparency = 1
toasts.AnchorPoint = Vector2.new(0.5, 1)
toasts.Position = UDim2.new(0.5, 0, 1, -150)
toasts.Size = UDim2.fromOffset(420, 120)
toasts.Parent = screen
local tl = Instance.new("UIListLayout")
tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
tl.Padding = UDim.new(0, 4)
tl.Parent = toasts

local function toast(text: string)
	local t = Instance.new("TextLabel")
	t.BackgroundColor3 = UiKit.NIGHT
	t.BackgroundTransparency = 0.35
	t.TextColor3 = UiKit.KHAKI
	t.Font = Enum.Font.GothamBold
	t.TextSize = UiKit.text(16)
	t.Size = UDim2.fromOffset(400, if UiKit.tv() then 36 else 28)
	t.Text = text
	t.Parent = toasts
	local kids = toasts:GetChildren()
	if #kids > 5 then -- só os 4 mais novos (o 1º filho é o layout)
		kids[2]:Destroy()
	end
	task.delay(2.6, function()
		local tw = TweenService:Create(t, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		t:Destroy()
	end)
end

-- ===== promoção (cerimônia animada no alto) =====
local function ceremony(r: { [string]: any })
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 90)
	card.Size = UDim2.fromOffset(520, 190)
	card.BackgroundColor3 = UiKit.CARD
	card.BorderSizePixel = 0
	card.Parent = screen
	local sc = Instance.new("UIScale")
	sc.Scale = 0.6
	sc.Parent = card
	local corner = Instance.new("UIStroke")
	corner.Thickness = 3
	corner.Color = UiKit.RULE_RED
	corner.Parent = card
	local head = Instance.new("TextLabel")
	head.BackgroundColor3 = UiKit.OLIVE
	head.BorderSizePixel = 0
	head.Size = UDim2.new(1, 0, 0, 40)
	head.Font = Enum.Font.GothamBlack
	head.TextColor3 = UiKit.KHAKI
	head.TextSize = UiKit.text(22)
	head.Text = if state and state.faction == "VC" then "THĂNG CHỨC  ·  PROMOÇÃO" else "PROMOTION  ·  PROMOÇÃO"
	head.Parent = card
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(0, 50)
	name.Size = UDim2.new(1, 0, 0, 52)
	name.Font = Enum.Font.Bodoni
	name.TextColor3 = UiKit.INK
	name.TextSize = UiKit.text(40)
	name.Text = tostring(r.name or ("Posto " .. tostring(r.to)))
	name.Parent = card
	local pt = Instance.new("TextLabel")
	pt.BackgroundTransparency = 1
	pt.Position = UDim2.fromOffset(0, 104)
	pt.Size = UDim2.new(1, 0, 0, 28)
	pt.Font = Enum.Font.Gotham
	pt.TextColor3 = UiKit.INK
	pt.TextSize = UiKit.text(18)
	pt.Text = tostring(r.pt or "")
	pt.Parent = card
	local stamp = Instance.new("TextLabel")
	stamp.BackgroundTransparency = 1
	stamp.Position = UDim2.fromOffset(0, 140)
	stamp.Size = UDim2.new(1, 0, 0, 34)
	stamp.Font = Enum.Font.GothamBlack
	stamp.TextColor3 = UiKit.STAMP
	stamp.TextSize = UiKit.text(22)
	stamp.Rotation = -3
	stamp.TextTransparency = 1
	stamp.Text = string.format("SOLDO: +%s %s", fmt(tonumber(r.bonus) or 0), tostring(state and state.cur or "CI"))
	stamp.Parent = card
	TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.6, function()
		TweenService:Create(stamp, TweenInfo.new(0.2), { TextTransparency = 0, Rotation = -6 }):Play()
	end)
	task.delay(4.2, function()
		local fade = TweenInfo.new(0.5)
		for _, d in card:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			end
		end
		local tw = TweenService:Create(card, fade, { BackgroundTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		card:Destroy()
	end)
end

-- ===== painel de equipamento (Intendência) =====
local panel = Instance.new("ScrollingFrame")
panel.Name = "Equipamento"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 24, 0.5, 0)
panel.Size = UDim2.new(0, 380, 0.78, 0)
panel.BackgroundColor3 = UiKit.CARD
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 6
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.Visible = false
panel.Parent = screen
local pl = Instance.new("UIListLayout")
pl.Padding = UDim.new(0, 6)
pl.SortOrder = Enum.SortOrder.LayoutOrder
pl.HorizontalAlignment = Enum.HorizontalAlignment.Center
pl.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 10)
pad.PaddingBottom = UDim.new(0, 10)
pad.Parent = panel

local function clear()
	for _, c in panel:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local order = 0
local function line(text: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	order += 1
	local t = UiKit.label(panel, text, size or 15)
	t.LayoutOrder = order
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.new(1, -20, 0, 0)
	if color then
		t.TextColor3 = color
	end
	return t
end

local function button(text: string, onClick: () -> (), enabled: boolean): TextButton
	order += 1
	local b = UiKit.button(panel, text, onClick, order)
	b.Size = UDim2.new(1, -20, 0, if UiKit.tv() then 44 else 30)
	if not enabled then
		b.BackgroundColor3 = Color3.fromRGB(150, 146, 130)
		b.AutoButtonColor = false
	end
	return b
end

local function render()
	local s = state
	if not panel.Visible or not s then
		return
	end
	clear()
	order = 0
	line("EQUIPAMENTO DE CAMPO", 20, UiKit.RULE_RED, true)
	line(string.format("%s  ·  %s XP", tostring(s.rankName), fmt(s.xp)), 15, UiKit.INK, true)
	line(string.format("%s %s (%s)", fmt(s.credits), tostring(s.cur), tostring(s.currency)), 15, UiKit.OLIVE, true)
	if (tonumber(s.respawnCredits) or 0) > 0 then
		line(string.format("Renasceres guardados: %d", s.respawnCredits), 14, UiKit.OLIVE)
	end
	line(
		"O kit padrão de 1965 vem sempre. Cada item abaixo soma a ele e pesa no corpo. Liberação permanente: pelo posto, com créditos ou pelo passe em Robux.",
		13
	)
	for _, t in s.tiers do
		line(string.format("%s (nível %d)", t.name, t.tier), 17, UiKit.INK, true)
		if t.owned then
			line("Passe seu: nível liberado.", 13, UiKit.OLIVE)
		else
			line(string.format("De graça no posto %d (%s).", t.rank, tostring(t.rankName)), 13)
			if (tonumber(t.passId) or 0) > 0 then
				button("Liberar o nível com Robux", function()
					MarketplaceService:PromptGamePassPurchase(player, t.passId)
				end, true)
			end
		end
		for _, g in s.gear do
			if g.tier == t.tier then
				line(string.format("• %s  (%.1f kg)", g.name, g.kg), 15, UiKit.INK, true)
				line(g.effect, 13)
				if g.unlocked then
					local how = if g.how == "rank"
						then "pelo posto"
						elseif g.how == "pass" then "pelo passe"
						else "comprado"
					button((if g.on then "LEVANDO" else "DEIXADO") .. " (" .. how .. ") — trocar", function()
						Net.event("Gear_Equip"):FireServer(g.id, not g.on)
					end, true)
				elseif (tonumber(s.rank) or 1) < g.buyRank then
					button(
						string.format("Posto %d para comprar (%s %s)", g.buyRank, fmt(g.price), tostring(s.cur)),
						function() end,
						false
					)
				else
					local can = (tonumber(s.credits) or 0) >= g.price
					button(string.format("Comprar por %s %s", fmt(g.price), tostring(s.cur)), function()
						Net.event("Gear_Buy"):FireServer(g.id)
					end, can)
				end
			end
		end
	end
	if s.result then
		line(tostring(s.result), 14, UiKit.STAMP, true)
	end
	UiKit.focus(panel)
end

Net.event("Progress_State").OnClientEvent:Connect(function(s: any)
	if type(s) ~= "table" then
		return
	end
	state = s
	local g = s.gain
	if type(g) == "table" and ((g.xp or 0) > 0 or (g.cr or 0) > 0) then
		local parts = {}
		if (g.xp or 0) > 0 then
			table.insert(parts, "+" .. fmt(g.xp) .. " XP")
		end
		if (g.cr or 0) > 0 then
			table.insert(parts, "+" .. fmt(g.cr) .. " " .. tostring(s.cur))
		end
		toast(table.concat(parts, " · ") .. "   " .. tostring(g.label))
	end
	if type(s.rankUp) == "table" then
		ceremony(s.rankUp)
	end
	render()
end)

Bus.on("shop_open", function()
	panel.Visible = true
	if not state then
		local ok, s = pcall(function()
			return Net.func("Progress_Get"):InvokeServer()
		end)
		if ok and type(s) == "table" then
			state = s
		end
	end
	render()
end)
Bus.on("shop_closed", function()
	panel.Visible = false
end)
UiKit.watch(panel, function()
	return panel.Visible
end)
