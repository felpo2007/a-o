--!strict
-- Progressão no cliente (D-72): avisos de ganho (+XP, +$), a cerimônia de promoção e o painel da
-- Intendência do lobby (abre junto com a loja: Bus "shop_open"), com duas abas:
--   - EQUIPAMENTO: o equipamento de campo (Gear_Buy, Gear_Equip);
--   - SKINS (2026-11-11, Shared/Skins): acabamento de arma, uniforme e camuflagem de mato, com
--     prévia, preço em $ e em Robux (o botão de Robux só com ID diferente de 0) e equipar.
-- O servidor (ProgressionService, CommerceService) decide tudo; aqui só se mostra e se pede. A
-- skin usa os mesmos remotes do equipamento (o id diz o que é).
-- Visual do lobby: oliva escuro, cáqui e latão. Controle: LT/RT (Z/C no teclado) trocam de aba, A
-- escolhe, B fecha (a loja); as dicas aparecem em chips com o botão do controle conectado.
-- Também roda aqui o que as skins pedem em campo (sem script novo):
--   - a arma de 1ª pessoa (câmera) e a cópia local de ReplicatedStorage.VT65WeaponArt ganham o
--     acabamento do atributo "WeaponSkins" do jogador;
--   - as folhas da camuflagem de mato balançam ao vento (workspace.GlobalWind), barato: só perto da
--     câmera e a 30 Hz; a própria camuflagem não faz sombra.
-- Ganhos e promoção saem pelo sistema de avisos (Toast).
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Acabamento = require(game:GetService("ReplicatedFirst"):WaitForChild("Acabamento"))
local BotBrain = require(ReplicatedStorage.Shared.BotBrain)
local GunModel = require(ReplicatedStorage.Shared.GunModel)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local screen = UiKit.screen("VT65Progresso", 40)
local state: { [string]: any }? = nil
local TV = UiKit.tv()

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

local money = Progression.money

-- ===== promoção: ficha de papel no topo da pilha de avisos, com o carimbo do soldo =====
local function ceremony(r: { [string]: any })
	local nameText = if r.name then tostring(r.name) else string.format("Posto %s", tostring(r.to))
	local headText = if state and state.faction == "VC"
		then "THĂNG CHỨC  ·  PROMOÇÃO"
		else "PROMOTION  ·  PROMOÇÃO"
	local soldo = string.format("SOLDO: +%s", money(tonumber(r.bonus) or 0))
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

-- ============================================================================================
-- Painel da Intendência (oliva escuro, cáqui e latão)
-- ============================================================================================
local PW = if TV then 470 else 400
local HEADER_H = if TV then 78 else 62
local TABS_H = if TV then 48 else 34
local PREVIEW_H = if TV then 190 else 150
local FOOT_H = if TV then 40 else 30
local CARD_BG = Color3.fromRGB(58, 62, 46)
local OFF_BG = Color3.fromRGB(70, 72, 60)
local OFF_TEXT = Color3.fromRGB(150, 142, 112)

local root = Instance.new("Frame")
root.Name = "Intendencia"
root.AnchorPoint = Vector2.new(0, 0.5)
root.Position = UDim2.new(0, 24, 0.5, 0)
root.Size = UDim2.new(0, PW, 0.84, 0)
root.BackgroundColor3 = UiKit.DRAB
root.BorderSizePixel = 0
root.Active = true
root.Visible = false
root.Parent = screen
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = root
	local s = Instance.new("UIStroke")
	s.Color = UiKit.KHAKI
	s.Transparency = 0.65
	s.Parent = root
	UiKit.lit(root, 0.78)
	Acabamento.sombra(root, 22, Vector2.new(0, 8), 0.55)
	-- janela baixa: o painel encolhe (a lista rola dentro dele)
	UiKit.fit(screen, root, PW, 420, 12)
end

-- 2026-11-11: Oswald nos títulos e Arimo no texto, as fontes de época das outras telas (era Gotham)
local function label(parent: Instance, s: string, size: number, color: Color3, bold: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	if bold then
		t.FontFace = UiKit.HEAD_FONT
	else
		t.Font = UiKit.BODY_FONT
	end
	t.TextSize = UiKit.text(size)
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Text = s
	t.Parent = parent
	return t
end

-- cabeçalho: nome, dinheiro do jogo em latão e o posto
local title = label(root, "INTENDÊNCIA", 20, UiKit.KHAKI, true)
title.FontFace = UiKit.HEAD_FONT
title.Position = UDim2.fromOffset(14, 6)
title.Size = UDim2.new(0.5, -14, 0, if TV then 36 else 28)
local moneyLabel = label(root, "", 22, UiKit.BRASS, true)
moneyLabel.FontFace = UiKit.HEAD_FONT
moneyLabel.TextXAlignment = Enum.TextXAlignment.Right
moneyLabel.Position = UDim2.new(0.5, 0, 0, 6)
moneyLabel.Size = UDim2.new(0.5, -14, 0, if TV then 36 else 28)
local rankLabel = label(root, "", 13, UiKit.KHAKI)
rankLabel.Position = UDim2.fromOffset(14, if TV then 44 else 36)
rankLabel.Size = UDim2.new(1, -28, 0, if TV then 28 else 20)
rankLabel.TextTransparency = 0.15

-- abas com o indicador de latão deslizando
local tabsBar = Instance.new("Frame")
tabsBar.BackgroundTransparency = 1
tabsBar.Position = UDim2.fromOffset(10, HEADER_H)
tabsBar.Size = UDim2.new(1, -20, 0, TABS_H)
tabsBar.Parent = root
local tabLine = Instance.new("Frame")
tabLine.BackgroundColor3 = UiKit.BRASS
tabLine.BorderSizePixel = 0
tabLine.AnchorPoint = Vector2.new(0, 1)
tabLine.Size = UDim2.new(0.5, 0, 0, 3)
tabLine.Position = UDim2.new(0, 0, 1, 0)
tabLine.ZIndex = 3
tabLine.Parent = tabsBar

-- prévia da skin (só na aba SKINS)
local preview = Instance.new("Frame")
preview.Name = "Previa"
preview.BackgroundColor3 = UiKit.NIGHT
preview.BorderSizePixel = 0
preview.Position = UDim2.fromOffset(10, HEADER_H + TABS_H + 6)
preview.Size = UDim2.new(1, -20, 0, PREVIEW_H)
preview.Visible = false
preview.Parent = root
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 3)
	c.Parent = preview
end
local view = Instance.new("ViewportFrame")
view.BackgroundTransparency = 1
view.Position = UDim2.fromOffset(4, 4)
view.Size = UDim2.new(0.58, -8, 1, -8)
view.Ambient = Color3.fromRGB(150, 148, 138)
view.LightColor = Color3.fromRGB(255, 244, 226)
view.LightDirection = Vector3.new(-0.6, -1, -0.4)
view.Parent = preview
local viewCam = Instance.new("Camera")
viewCam.FieldOfView = 24
viewCam.Parent = view
view.CurrentCamera = viewCam
local swatch = Instance.new("Frame")
swatch.BackgroundColor3 = UiKit.DRAB
swatch.BorderSizePixel = 0
swatch.ClipsDescendants = true
swatch.Position = UDim2.fromOffset(10, 10)
swatch.Size = UDim2.new(0.58, -20, 1, -20)
swatch.Parent = preview
local pvName = label(preview, "", 15, UiKit.KHAKI, true)
pvName.Position = UDim2.new(0.58, 4, 0, 8)
pvName.Size = UDim2.new(0.42, -12, 0, 0)
pvName.AutomaticSize = Enum.AutomaticSize.Y
local pvInfo = label(preview, "", 12, UiKit.KHAKI)
pvInfo.Position = UDim2.new(0.58, 4, 0, if TV then 60 else 46)
pvInfo.Size = UDim2.new(0.42, -12, 1, if TV then -64 else -50)
pvInfo.TextYAlignment = Enum.TextYAlignment.Top
pvInfo.TextTransparency = 0.1

-- lista rolável (analógico direito ou roda do mouse)
local body = Instance.new("ScrollingFrame")
body.Name = "Lista"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 6
body.ScrollBarImageColor3 = UiKit.KHAKI
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.CanvasSize = UDim2.new()
body.Parent = root
local bl = Instance.new("UIListLayout")
bl.Padding = UDim.new(0, 6)
bl.SortOrder = Enum.SortOrder.LayoutOrder
bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
bl.Parent = body
local bp = Instance.new("UIPadding")
bp.PaddingTop = UDim.new(0, 6)
bp.PaddingBottom = UDim.new(0, 10)
bp.Parent = body

-- rodapé: dicas de botão em chips
local footer = Instance.new("Frame")
footer.BackgroundTransparency = 1
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 12, 1, -4)
footer.Size = UDim2.new(1, -24, 0, FOOT_H)
footer.Parent = root
local fl = Instance.new("UIListLayout")
fl.FillDirection = Enum.FillDirection.Horizontal
fl.Padding = UDim.new(0, 14)
fl.VerticalAlignment = Enum.VerticalAlignment.Center
fl.SortOrder = Enum.SortOrder.LayoutOrder
fl.Parent = footer

local function layoutBody(withPreview: boolean)
	local top = HEADER_H + TABS_H + 6 + (if withPreview then PREVIEW_H + 6 else 0)
	preview.Visible = withPreview
	body.Position = UDim2.fromOffset(0, top)
	body.Size = UDim2.new(1, 0, 1, -(top + FOOT_H + 8))
end

-- ===== botões (mouse, toque, A do controle e o cursor virtual do lobby) =====
type Style = "primary" | "normal" | "off" | "on"
local STYLE: { [string]: { bg: Color3, fg: Color3 } } = {
	primary = { bg = UiKit.BRASS, fg = UiKit.NIGHT },
	normal = { bg = UiKit.OLIVE, fg = UiKit.KHAKI },
	off = { bg = OFF_BG, fg = OFF_TEXT },
	on = { bg = UiKit.KHAKI, fg = UiKit.NIGHT },
}
local buttons: { [string]: TextButton } = {} -- por chave (refoco depois de redesenhar)

local function button(
	parent: Instance,
	text: string,
	style: Style,
	key: string,
	onClick: () -> (),
	hover: (() -> ())?,
	focus: ((on: boolean) -> ())? -- realce ligou/desligou (mouse, foco e cursor virtual)
): TextButton
	local st = STYLE[style]
	local b = Instance.new("TextButton")
	b.Name = key
	b.AutoButtonColor = style ~= "off"
	b.BackgroundColor3 = st.bg
	b.TextColor3 = st.fg
	b.FontFace = UiKit.headFont(text)
	b.TextSize = UiKit.text(15)
	b.TextWrapped = true
	b.Text = text
	b.Size = UDim2.new(1, 0, 0, if TV then 44 else 30)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b:SetAttribute("Key", key)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 3)
	c.Parent = b
	b.Parent = parent
	local h = hover
	local fo = focus
	UiKit.bind(
		b,
		onClick,
		if h or fo
			then function(on: boolean)
				if on and h then
					h()
				end
				if fo then
					fo(on)
				end
			end
			else nil
	)
	if h then
		b.MouseEnter:Connect(h)
		b.SelectionGained:Connect(h)
	end
	if fo then
		b.MouseEnter:Connect(function()
			fo(true)
		end)
		b.MouseLeave:Connect(function()
			fo(false)
		end)
		b.SelectionGained:Connect(function()
			fo(true)
		end)
		b.SelectionLost:Connect(function()
			fo(false)
		end)
	end
	buttons[key] = b
	return b
end

-- linha de botões lado a lado (larguras iguais)
local function rowOf(parent: Instance, order: number): Frame
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, if TV then 44 else 30)
	r.LayoutOrder = order
	r.Parent = parent
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = r
	return r
end
local function fitRow(r: Frame)
	local n = 0
	for _, c in r:GetChildren() do
		if c:IsA("GuiButton") then
			n += 1
		end
	end
	local gap = 6 * math.max(n - 1, 0)
	for i, c in r:GetChildren() do
		if c:IsA("GuiButton") then
			c.Size = UDim2.new(1 / math.max(n, 1), -gap / math.max(n, 1), 1, 0)
			c.LayoutOrder = i
		end
	end
end

local order = 0
local function line(text: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	order += 1
	local t = label(body, text, size or 14, color or UiKit.KHAKI, bold)
	t.LayoutOrder = order
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Size = UDim2.new(1, -24, 0, 0)
	return t
end
local function fullButton(
	text: string,
	style: Style,
	key: string,
	onClick: () -> (),
	focus: ((on: boolean) -> ())?
): TextButton
	order += 1
	local b = button(body, text, style, key, onClick, nil, focus)
	b.Size = UDim2.new(1, -24, 0, if TV then 44 else 30)
	b.LayoutOrder = order
	return b
end

local function clear()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	table.clear(buttons)
end

-- ===== estado da tela =====
local tab: "gear" | "skins" = "gear"
local cat: string = "weapon" -- "weapon" | "uniform" | "camo"
local sel: string? = nil -- skin na prévia
local confirmId: string? = nil -- compra com $ pedindo confirmação (2º clique)
local confirmUntil = 0
local render: () -> () = function() end

-- preço ao vivo em Robux (Managed Pricing); sem resposta, a sugestão do catálogo
local priceCache: { [number]: number } = {}
local priceAsked: { [number]: boolean } = {}
local function robuxText(s: Skins.Skin): string
	local id = Skins.robuxId(s)
	return string.format("R$ %s", tostring(priceCache[id] or s.robux))
end
local function askPrice(s: Skins.Skin)
	local id = Skins.robuxId(s)
	if id == 0 or priceAsked[id] then
		return
	end
	priceAsked[id] = true
	task.spawn(function()
		local infoType = if s.robuxKind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end)
		local p = if ok and type(info) == "table" then tonumber((info :: any).PriceInRobux) else nil
		if p then
			priceCache[id] = p
			local b = buttons["rbx:" .. s.id]
			if b and b.Parent then
				b.Text = robuxText(s)
			end
		end
	end)
end

-- ===== prévia =====
local function clearPreview()
	for _, c in view:GetChildren() do
		if c ~= viewCam then
			c:Destroy()
		end
	end
	for _, c in swatch:GetChildren() do
		c:Destroy()
	end
end

local function weaponPreview(s: Skins.Skin)
	local wid = s.weapon or ""
	local wp = Weapons.get(wid)
	local folder = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	local art = if folder then folder:FindFirstChild(wid) else nil
	local m: Model = if art and art:IsA("Model") then art:Clone() else GunModel.build(wid, if wp then wp.kind else nil)
	Skins.applyWeapon(m, s.id)
	m:PivotTo(CFrame.identity)
	m.Parent = view
	local cf, size = m:GetBoundingBox()
	local dist = size.Magnitude / 2 / math.tan(math.rad(viewCam.FieldOfView / 2)) * 1.02
	viewCam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist, dist * 0.18, dist * 0.12), cf.Position)
	swatch.Visible = false
end

-- retalho de pano (uniforme) ou de folhas (camuflagem) com as cores da skin: desenho simples e fixo
local function patchPreview(s: Skins.Skin)
	swatch.Visible = true
	local cols = s.swatch
	swatch.BackgroundColor3 = Color3.fromRGB(cols[1][1], cols[1][2], cols[1][3])
	local rng = Random.new(#s.id * 7919)
	local function piece(c: { number }, x: number, y: number, w: number, h: number, rot: number, round: number)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.Rotation = rot
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(round, 0)
		k.Parent = f
		f.Parent = swatch
	end
	if s.kind == "camo" then
		-- folhas: capim fino (arrozal), folha larga (selva), folha estreita (bambu)
		local w, h = 0.05, 0.5
		if s.camo == "jungle" then
			w, h = 0.2, 0.34
		elseif s.camo == "bamboo" then
			w, h = 0.07, 0.36
		end
		for _ = 1, 26 do
			local c = cols[rng:NextInteger(1, #cols)]
			piece(c, rng:NextNumber(0, 1), rng:NextNumber(0, 1), w, h, rng:NextNumber(-40, 40), 0.5)
		end
	elseif string.find(s.id, "tiger", 1, true) then
		for _ = 1, 16 do
			local c = cols[rng:NextInteger(2, #cols)]
			piece(
				c,
				rng:NextNumber(0, 1),
				rng:NextNumber(0, 1),
				rng:NextNumber(0.3, 0.7),
				0.05,
				rng:NextNumber(-8, 8),
				0.5
			)
		end
	elseif #cols > 1 then
		for _ = 1, 14 do
			local c = cols[rng:NextInteger(2, #cols)]
			local d = rng:NextNumber(0.12, 0.26)
			piece(c, rng:NextNumber(0, 1), rng:NextNumber(0, 1), d, d * 1.5, rng:NextNumber(0, 180), 0.5)
		end
	end
end

local function showPreview(id: string?)
	clearPreview()
	local s = if id then Skins.get(id) else nil
	if not s then
		pvName.Text = ""
		pvInfo.Text = "Escolha uma skin na lista para ver aqui."
		swatch.Visible = false
		return
	end
	pvName.Text = s.name
	local info = s.desc
	if s.kind == "camo" then
		local C = BotBrain.CAMO
		info ..= string.format(
			"\n\nVantagem: na vegetação certa os bots te veem a %d%% da distância; deitado, a %d%%.",
			math.floor(C.match * 100 + 0.5),
			math.floor(C.match * C.prone * 100 + 0.5)
		)
	elseif s.kind == "uniform" then
		info ..= "\n\nVale no próximo spawn."
	end
	pvInfo.Text = info
	if s.kind == "weapon" then
		weaponPreview(s)
	else
		patchPreview(s)
	end
end

local function select(id: string)
	if sel ~= id then
		sel = id
		showPreview(id)
		Net.event("Commerce_Track"):FireServer("item_view", id)
	end
end

-- ===== aba EQUIPAMENTO =====
-- Menos texto (pedido do dono, 2026-11-11): uma linha de abertura; o efeito de cada item só abre
-- no item sob o mouse, o foco ou o cursor virtual.
local function renderGear(s: { [string]: any })
	line("Soma ao kit de 1965 e pesa no corpo.", 13)
	for _, t in s.tiers do
		line(string.format("%s (nível %d)", t.name, t.tier), 16, UiKit.BRASS, true)
		if t.owned then
			line("Passe seu: nível liberado.", 13)
		else
			line(string.format("De graça no posto %d (%s).", t.rank, tostring(t.rankName)), 13)
			if (tonumber(t.passId) or 0) > 0 then
				fullButton("Liberar o nível com Robux", "normal", "tier:" .. t.key, function()
					MarketplaceService:PromptGamePassPurchase(player, t.passId)
				end)
			end
		end
		for _, g in s.gear do
			if g.tier == t.tier then
				line(string.format("• %s  (%.1f kg)", g.name, g.kg), 14, UiKit.KHAKI, true)
				local eff = line(g.effect, 13)
				eff.Visible = false
				local function showEffect(on: boolean)
					eff.Visible = on
				end
				if g.unlocked then
					-- frase inteira por caso (levando/deixado × como liberou): o dicionário traduz a frase
					local how = if g.how == "rank"
						then "pelo posto"
						elseif g.how == "pass" then "pelo passe"
						else "comprado"
					fullButton(
						string.format(if g.on then "LEVANDO (%s) — trocar" else "DEIXADO (%s) — trocar", how),
						if g.on then "on" else "normal",
						"gear:" .. g.id,
						function()
							Net.event("Gear_Equip"):FireServer(g.id, not g.on)
						end,
						showEffect
					)
				elseif (tonumber(s.rank) or 1) < g.buyRank then
					fullButton(
						string.format("Posto %d para comprar (%s)", g.buyRank, money(g.price)),
						"off",
						"gear:" .. g.id,
						function() end,
						showEffect
					)
				else
					local can = (tonumber(s.credits) or 0) >= g.price
					fullButton(
						string.format("Comprar por %s", money(g.price)),
						if can then "primary" else "off",
						"gear:" .. g.id,
						function()
							if can then
								Net.event("Gear_Buy"):FireServer(g.id)
							end
						end,
						showEffect
					)
				end
			end
		end
	end
end

-- ===== aba SKINS =====
local CAT_NAME = { weapon = "ARMAS", uniform = "UNIFORME", camo = "CAMUFLAGEM" }
local CAT_ORDER: { string } = { "weapon", "uniform", "camo" }

local function skinCard(s: Skins.Skin, sk: { [string]: any })
	local owned = sk.owned or {}
	local on = sk.on or {}
	local how = owned[s.id]
	local equipped = on[Skins.slotOf(s)] == s.id
	order += 1
	local card = Instance.new("Frame")
	card.Name = s.id
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -24, 0, 0)
	card.LayoutOrder = order
	card.Parent = body
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 3)
	cc.Parent = card
	if equipped then
		local st = Instance.new("UIStroke")
		st.Color = UiKit.BRASS
		st.Thickness = 2
		st.Parent = card
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 8)
	pad.Parent = card
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = card
	local function text(t: string, size: number, color: Color3, bold: boolean?, o: number)
		local x = label(card, t, size, color, bold)
		x.AutomaticSize = Enum.AutomaticSize.Y
		x.Size = UDim2.new(1, 0, 0, 0)
		x.LayoutOrder = o
	end
	text(s.name, 15, UiKit.KHAKI, true, 1)
	local status: string
	if equipped then
		status = "EQUIPADA"
	elseif how == "pass" then
		status = "Sua (passe)"
	elseif how then
		status = "Sua"
	else
		status = if Skins.robuxId(s) ~= 0
			then string.format("%s · %s", money(s.price), robuxText(s))
			else money(s.price)
	end
	text(status, 13, if how then UiKit.KHAKI else UiKit.BRASS, true, 2)
	local actions = rowOf(card, 3)
	local look = function()
		select(s.id)
	end
	if how then
		if equipped then
			button(actions, "TIRAR", "normal", "skin:" .. s.id, function()
				Net.event("Gear_Equip"):FireServer(s.id, false)
			end, look)
		else
			button(actions, "EQUIPAR", "primary", "skin:" .. s.id, function()
				Net.event("Gear_Equip"):FireServer(s.id, true)
			end, look)
		end
	else
		local have = tonumber(state and state.credits) or 0
		local can = have >= s.price
		local confirming = confirmId == s.id and os.clock() < confirmUntil
		local txt = if confirming
			then string.format("CONFIRMAR %s", money(s.price))
			elseif can then string.format("COMPRAR %s", money(s.price))
			else string.format("FALTAM %s", money(s.price - have))
		button(actions, txt, if can then "primary" else "off", "skin:" .. s.id, function()
			select(s.id)
			if not can then
				return
			end
			if confirmId == s.id and os.clock() < confirmUntil then
				confirmId = nil
				Net.event("Gear_Buy"):FireServer(s.id)
			else
				confirmId = s.id
				confirmUntil = os.clock() + 5
				render()
				task.delay(5.1, function()
					if confirmId == s.id and os.clock() >= confirmUntil then
						confirmId = nil
						render()
					end
				end)
			end
		end, look)
		local rid = Skins.robuxId(s)
		if rid ~= 0 then
			askPrice(s)
			button(actions, robuxText(s), "normal", "rbx:" .. s.id, function()
				select(s.id)
				Net.event("Commerce_Track"):FireServer("prompt", s.robuxKey)
				if s.robuxKind == "pass" then
					MarketplaceService:PromptGamePassPurchase(player, rid)
				else
					MarketplaceService:PromptProductPurchase(player, rid)
				end
			end, look)
		end
	end
	fitRow(actions)
end

-- "padrão" de um encaixe: tira a skin equipada nele
local function defaultRow(slot: string, sk: { [string]: any }, text: string)
	local cur = (sk.on or {})[slot]
	if cur then
		fullButton(text, "normal", "default:" .. slot, function()
			Net.event("Gear_Equip"):FireServer(cur, false)
		end)
	end
end

local function renderSkins(s: { [string]: any })
	local sk = s.skins or {}
	local faction: string? = sk.faction
	-- categorias
	order += 1
	local cats = rowOf(body, order)
	cats.Size = UDim2.new(1, -24, 0, if TV then 44 else 30)
	for _, c in CAT_ORDER do
		button(cats, CAT_NAME[c], if c == cat then "on" else "normal", "cat:" .. c, function()
			if cat ~= c then
				cat = c
				sel = nil
				render()
			end
		end)
	end
	fitRow(cats)
	if not faction then
		line("Escolha um lado na sala de arquivo para ver as skins dele.", 13)
		return
	end
	line("Fica sua para sempre, só no lado dela.", 12)
	local first: string? = nil
	if cat == "weapon" then
		for _, wp in Weapons.list do
			if wp.faction == faction then
				local list = {}
				for _, x in Skins.list("weapon", faction) do
					if x.weapon == wp.id then
						table.insert(list, x)
					end
				end
				if #list > 0 then
					line(wp.name, 16, UiKit.BRASS, true)
					defaultRow(wp.id, sk, "Voltar ao acabamento de fábrica")
					for _, x in list do
						first = first or x.id
						skinCard(x, sk)
					end
				end
			end
		end
	elseif cat == "uniform" then
		line("Os uniformes de época ficam no armário da loja.", 12)
		defaultRow("uniform", sk, "Voltar ao uniforme do armário")
		for _, x in Skins.list("uniform", faction) do
			first = first or x.id
			skinCard(x, sk)
		end
	else
		line("Folha e capim no corpo: os bots te veem de mais perto na mesma vegetação.", 12)
		defaultRow("camo", sk, "Sem camuflagem")
		for _, x in Skins.list("camo", faction) do
			first = first or x.id
			skinCard(x, sk)
		end
	end
	local want = sel
	local keep = want ~= nil and Skins.get(want) ~= nil and (Skins.get(want) :: Skins.Skin).kind == cat
	if not keep and first then
		sel = first
		showPreview(first)
	elseif keep then
		showPreview(want)
	end
end

-- ===== chips do rodapé =====
local function padImage(code: Enum.KeyCode): string?
	local img: string? = nil
	pcall(function()
		local v = UserInputService:GetImageForKeyCode(code) :: any
		if type(v) == "string" and v ~= "" then
			img = v
		end
	end)
	return img
end
local function chip(imgs: { string }, keys: string, text: string, o: number)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, FOOT_H)
	f.LayoutOrder = o
	f.Parent = footer
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 3)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	local sz = if TV then 30 else 22
	for i, img in imgs do
		local im = Instance.new("ImageLabel")
		im.BackgroundTransparency = 1
		im.Image = img
		im.Size = UDim2.fromOffset(sz, sz)
		im.LayoutOrder = i
		im.Parent = f
	end
	local t = label(f, if #imgs > 0 then text else string.format("[%s] %s", keys, text), 13, UiKit.KHAKI)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, FOOT_H)
	t.TextWrapped = false
	t.LayoutOrder = 10
end
local function renderChips()
	for _, c in footer:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local dev = Input.device()
	local ia, ta = Input.glyph("ui_sub_prev", "menu")
	local ib, tb = Input.glyph("ui_sub_next", "menu")
	if dev == "gamepad" then
		local imgs = {}
		for _, im in { ia, ib } do
			if im then
				table.insert(imgs, im)
			end
		end
		chip(if #imgs == 2 then imgs else {}, ta .. "/" .. tb, "Aba", 1)
		local a = padImage(Enum.KeyCode.ButtonA)
		chip(if a then { a } else {}, "A", "Escolher", 2)
		local ic, tc = Input.glyph("ui_back", "menu")
		chip(if ic then { ic } else {}, tc, "Fechar", 3)
	elseif dev == "kbm" then
		chip({}, ta .. "/" .. tb, "Aba", 1)
		chip({}, "Clique", "Escolher", 2)
	end
end
Input.DeviceChanged:Connect(function()
	if root.Visible then
		renderChips()
	end
end)

-- ===== abas =====
local tabButtons: { [string]: TextButton } = {}
local function setTab(t: "gear" | "skins")
	if tab ~= t then
		tab = t
		confirmId = nil
		render()
	end
end
for i, d in { { id = "gear", name = "EQUIPAMENTO" }, { id = "skins", name = "SKINS" } } do
	local b = Instance.new("TextButton")
	b.Name = d.id
	b.BackgroundTransparency = 1
	b.FontFace = UiKit.HEAD_FONT
	b.TextSize = UiKit.text(17)
	b.TextColor3 = UiKit.KHAKI
	b.Text = d.name
	b.Size = UDim2.new(0.5, 0, 1, 0)
	b.Position = UDim2.fromScale((i - 1) * 0.5, 0)
	b.Selectable = true
	b.SelectionImageObject = UiKit.FOCUS
	b.Parent = tabsBar
	UiKit.bind(b, function()
		setTab(d.id :: any)
	end)
	tabButtons[d.id] = b
end
local function paintTabs()
	for id, b in tabButtons do
		b.TextColor3 = if id == tab then UiKit.BRASS else UiKit.KHAKI
		b.TextTransparency = if id == tab then 0 else 0.25
	end
	UiKit.tween(tabLine, UiKit.SOFT, { Position = UDim2.new(if tab == "gear" then 0 else 0.5, 0, 1, 0) })
end
Input.on("ui_sub_prev", "press", function()
	if root.Visible then
		setTab(if tab == "gear" then "skins" else "gear")
	end
end)
Input.on("ui_sub_next", "press", function()
	if root.Visible then
		setTab(if tab == "gear" then "skins" else "gear")
	end
end)

render = function()
	local s = state
	if not root.Visible or not s then
		return
	end
	local focused = GuiService.SelectedObject
	local focusKey = if focused and focused:IsDescendantOf(root) then focused:GetAttribute("Key") else nil
	clear()
	order = 0
	moneyLabel.Text = money(tonumber(s.credits) or 0)
	-- lista "A · B · C" (o Lang traduz item a item)
	local rankParts = { tostring(s.rankName), string.format("%s XP", fmt(tonumber(s.xp) or 0)) }
	if (tonumber(s.respawnCredits) or 0) > 0 then
		table.insert(rankParts, string.format("renasceres guardados: %d", s.respawnCredits))
	end
	rankLabel.Text = table.concat(rankParts, " · ")
	paintTabs()
	layoutBody(tab == "skins")
	if tab == "gear" then
		renderGear(s)
	else
		renderSkins(s)
	end
	if s.result then
		line(UiKit.capitalize(tostring(s.result)), 14, UiKit.BRASS, true)
	end
	renderChips()
	local again = if type(focusKey) == "string" then buttons[focusKey] else nil
	if again and Input.isGamepad() then
		GuiService.SelectedObject = again
	else
		UiKit.focus(root)
	end
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
	root.Visible = true
	if not state then
		-- a tela nunca espera o servidor vazia: o painel abre já com o aviso e preenche quando chegar
		clear()
		order = 0
		line("Recebendo a intendência do servidor…", 14)
		task.spawn(function()
			local ok, s = pcall(function()
				return Net.func("Progress_Get"):InvokeServer()
			end)
			if ok and type(s) == "table" and not state then
				state = s
			end
			render()
		end)
		return
	end
	render()
end)
Bus.on("shop_closed", function()
	root.Visible = false
	confirmId = nil
end)
UiKit.watch(root, function()
	return root.Visible
end)

-- ============================================================================================
-- Skins em campo
-- ============================================================================================
-- Arma de 1ª pessoa: o WeaponVisuals clona da cópia em ReplicatedStorage.VT65WeaponArt (ou monta a
-- provisória) e põe na câmera. A cópia local e o que chega na câmera recebem o acabamento do
-- atributo "WeaponSkins" (só neste cliente; a de 3ª pessoa o servidor pinta no attachWeapon).
local function skinModel(m: Instance)
	if m:IsA("Model") then
		local wid = m:GetAttribute("WeaponId")
		if type(wid) == "string" then
			Skins.applyWeapon(m, Skins.weaponSkinFrom(player:GetAttribute("WeaponSkins"), wid))
		end
	end
end
local camConn: RBXScriptConnection? = nil
local function watchCamera()
	if camConn then
		camConn:Disconnect()
	end
	local cam = workspace.CurrentCamera
	if cam then
		camConn = cam.ChildAdded:Connect(skinModel)
		for _, c in cam:GetChildren() do
			skinModel(c)
		end
	end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()
local function watchArt(folder: Instance)
	folder.ChildAdded:Connect(skinModel)
	for _, c in folder:GetChildren() do
		skinModel(c)
	end
end
do
	local art = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	if art then
		watchArt(art)
	else
		local conn: RBXScriptConnection? = nil
		conn = ReplicatedStorage.ChildAdded:Connect(function(c)
			if c.Name == "VT65WeaponArt" then
				watchArt(c)
				if conn then
					conn:Disconnect()
				end
			end
		end)
	end
end
player:GetAttributeChangedSignal("WeaponSkins"):Connect(function()
	local art = ReplicatedStorage:FindFirstChild("VT65WeaponArt")
	for _, c in if art then art:GetChildren() else {} do
		skinModel(c)
	end
	local cam = workspace.CurrentCamera
	for _, c in if cam then cam:GetChildren() else {} do
		skinModel(c)
	end
end)

-- Camuflagem de mato: as soldas "Folhas" de cada peça (Characters) balançam o C0 em poucos graus.
-- Só perto da câmera e a 30 Hz. A própria camuflagem não faz sombra (só neste cliente).
type Leaf = { w: Weld, base: CFrame, ph: number }
local SWAY_RANGE = 70 / 0.28 -- studs
local ghillies: { [Instance]: { Leaf } } = {}
local function addGhillie(folder: Instance)
	local list: { Leaf } = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Folhas" then
			table.insert(list, { w = d, base = d.C0, ph = #list * 1.37 + #folder:GetFullName() * 0.11 })
		end
	end
	local char = player.Character
	if char and folder:IsDescendantOf(char) then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				d.CastShadow = false
			end
		end
	end
	ghillies[folder] = list
end
CollectionService:GetInstanceAddedSignal(Skins.GHILLIE_TAG):Connect(addGhillie)
CollectionService:GetInstanceRemovedSignal(Skins.GHILLIE_TAG):Connect(function(f)
	ghillies[f] = nil
end)
for _, f in CollectionService:GetTagged(Skins.GHILLIE_TAG) do
	addGhillie(f)
end
local swayAcc = 0
RunService.Heartbeat:Connect(function(dt: number)
	swayAcc += dt
	if swayAcc < 1 / 30 or next(ghillies) == nil then
		return
	end
	swayAcc = 0
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local wind = workspace.GlobalWind.Magnitude
	local t = os.clock()
	for folder, list in ghillies do
		local model = folder.Parent
		local rootPart = if model then model:FindFirstChild("HumanoidRootPart") else nil
		if not model then
			ghillies[folder] = nil
		elseif rootPart and rootPart:IsA("BasePart") and (rootPart.Position - camPos).Magnitude < SWAY_RANGE then
			for _, it in list do
				local ax, az = Skins.swayAngles(t, it.ph, wind)
				it.w.C0 = it.base * CFrame.Angles(ax, 0, az)
			end
		end
	end
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
