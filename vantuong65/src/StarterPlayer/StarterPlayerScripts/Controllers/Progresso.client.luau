--!strict
-- Progressão no cliente (D-72): avisos de ganho (+XP, +CI), a cerimônia de promoção e o painel de
-- equipamento de campo na Intendência do lobby (abre junto com a loja: Bus "shop_open"). O servidor
-- (ProgressionService) decide tudo; aqui só se mostra e se pede (Gear_Buy, Gear_Equip).
-- Ganhos e promoção saem pelo sistema de avisos (Toast): chips de XP e de créditos, e a ficha da
-- promoção em papel com o carimbo do soldo.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local screen = UiKit.screen("VT65Progresso", 40)
local state: { [string]: any }? = nil

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

-- ===== promoção: ficha de papel no topo da pilha de avisos, com o carimbo do soldo =====
local function ceremony(r: { [string]: any })
	local nameText = tostring(r.name or ("Posto " .. tostring(r.to)))
	local headText = if state and state.faction == "VC"
		then "THĂNG CHỨC  ·  PROMOÇÃO"
		else "PROMOTION  ·  PROMOÇÃO"
	local soldo = string.format("SOLDO: +%s %s", fmt(tonumber(r.bonus) or 0), tostring(state and state.cur or "CI"))
	Toast.custom(function(card: Frame, lay: Toast.Layout): number
		local tv = lay.tv
		local y = lay.pad
		-- tarja oliva com o título
		local head = Instance.new("TextLabel")
		head.Name = "Tarja"
		head.BackgroundColor3 = UiKit.OLIVE
		head.BorderSizePixel = 0
		head.Position = UDim2.fromOffset(lay.x, y)
		head.Size = UDim2.fromOffset(lay.w, if tv then 40 else 28)
		head.FontFace = UiKit.headFont(headText)
		head.TextColor3 = UiKit.KHAKI
		head.TextSize = UiKit.text(18)
		head.Text = headText
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 2)
		hc.Parent = head
		head.Parent = card
		y += head.Size.Y.Offset + 4
		-- linha vermelha de cabeçalho da ficha
		local rule = Instance.new("Frame")
		rule.BackgroundColor3 = UiKit.RULE_RED
		rule.BorderSizePixel = 0
		rule.Position = UDim2.fromOffset(lay.x, y)
		rule.Size = UDim2.fromOffset(lay.w, 2)
		rule.Parent = card
		y += 6
		-- o posto, grande, e o nome em português
		local latin = not string.find(nameText, "[\196-\244]")
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(lay.x, y)
		name.Size = UDim2.fromOffset(lay.w, if tv then 56 else 42)
		name.Font = if latin then Enum.Font.Bodoni else Enum.Font.ArimoBold
		name.TextColor3 = UiKit.INK
		name.TextSize = if tv then 48 else 36
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = nameText
		name.Parent = card
		y += name.Size.Y.Offset
		local pt = Instance.new("TextLabel")
		pt.BackgroundTransparency = 1
		pt.Position = UDim2.fromOffset(lay.x, y)
		pt.Size = UDim2.fromOffset(lay.w, if tv then 30 else 22)
		pt.Font = UiKit.BODY_FONT
		pt.TextColor3 = UiKit.INK
		pt.TextSize = UiKit.text(16)
		pt.Text = tostring(r.pt or "")
		pt.Parent = card
		y += pt.Size.Y.Offset + 6
		-- carimbo: tinta e moldura, torto, cai sobre a ficha logo depois que ela entra
		local stampH = if tv then 46 else 34
		local stamp = Instance.new("TextLabel")
		stamp.AnchorPoint = Vector2.new(0.5, 0.5)
		stamp.AutomaticSize = Enum.AutomaticSize.X
		stamp.BackgroundTransparency = 1
		stamp.Position = UDim2.fromOffset(lay.x + lay.w / 2, y + stampH / 2)
		stamp.Size = UDim2.fromOffset(0, stampH)
		stamp.FontFace = UiKit.HEAD_FONT
		stamp.TextSize = UiKit.text(22)
		stamp.TextColor3 = UiKit.STAMP
		stamp.Rotation = -4
		stamp.TextTransparency = 1
		stamp.Text = soldo
		local sp = Instance.new("UIPadding")
		sp.PaddingLeft = UDim.new(0, 10)
		sp.PaddingRight = UDim.new(0, 10)
		sp.Parent = stamp
		local ink = Instance.new("UIStroke")
		ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ink.Color = UiKit.STAMP
		ink.Thickness = 2
		ink.Transparency = 1
		ink.Parent = stamp
		local sc = Instance.new("UIScale")
		sc.Scale = 1.6
		sc.Parent = stamp
		stamp.Parent = card
		task.delay(0.55, function()
			if card.BackgroundTransparency > 0.5 then
				return -- a ficha já está saindo
			end
			local hit = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(stamp, hit, { TextTransparency = 0.08, Rotation = -7 }):Play()
			TweenService:Create(ink, hit, { Transparency = 0.15 }):Play()
			TweenService:Create(sc, hit, { Scale = 1 }):Play()
		end)
		return y + stampH
	end, { kind = "recompensa", paper = true, duration = 5, key = "promocao" })
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
		Toast.reward(
			if g.label ~= nil then tostring(g.label) else "",
			tonumber(g.xp) or 0,
			tonumber(g.cr) or 0,
			tostring(s.cur)
		)
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

-- gancho de teste (só no Studio): workspace:SetAttribute("VT65DevToast", "promocao") mostra a ficha
-- de promoção (os outros valores ficam no Toast)
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevToast"):Connect(function()
		if workspace:GetAttribute("VT65DevToast") ~= "promocao" then
			return
		end
		local vc = state ~= nil and state.faction == "VC"
		ceremony(
			if vc
				then { name = "Tiểu đội trưởng", pt = "chefe de esquadra (squad)", bonus = 500, to = 5 }
				else { name = "Sergeant", pt = "sargento, líder de squad", bonus = 500, to = 5 }
		)
		task.defer(function()
			workspace:SetAttribute("VT65DevToast", nil) -- local: no cliente, o mesmo valor repete
		end)
	end)
end
