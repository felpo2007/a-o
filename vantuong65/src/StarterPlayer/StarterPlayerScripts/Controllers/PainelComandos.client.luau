--!strict
-- Coluna de comandos (pedido do dono, 2026-11-12): uma coluna discreta na lateral esquerda da tela
-- com os botões e o que fazem no contexto de agora (a pé, no veículo, no helicóptero, pelo assento),
-- no ícone do controle conectado ou na tecla, conforme o aparelho (Input.glyph, que já segue o
-- remapeamento). Some com os menus, o mapa, a roda, a tela de ferido e de baixa e enquanto o
-- tutorial está na tela (o cartão dele já mostra o botão do passo). Pode ser escondida no menu do
-- jogo (Configurações, chave hintsPanel).
-- Leve: as linhas são criadas uma vez e só são reescritas quando o contexto, o assento, o aparelho
-- ou as configurações mudam; a visibilidade é olhada nos eventos da camada Input e, de reserva,
-- duas vezes por segundo (só leitura de estado).
-- Os rótulos são os das ações (InputMap), frases do dicionário: o Traducao traduz cada um.
-- 2026-11-13 (dono: "por que tem os comandos do teclado aparecendo se estou jogando no celular?"):
-- só com teclado e mouse (as teclas) ou com controle (os botões dele); no toque nunca aparece. Troca
-- na hora com a última entrada (Input.DeviceChanged).
-- 2026-11-13 (fotos do dono: a lista do squad do Roblox, com fotos e nomes, ficava por cima da
-- coluna): a coluna fica embaixo à esquerda, acima do registro de rádio, abaixo de uma faixa
-- reservada no alto (as listas do Roblox e a ordem do comandante); numa tela baixa ela desce até o
-- pé e encolhe (UIScale) para caber nessa faixa, em qualquer tamanho de tela.
-- Studio: workspace:SetAttribute("VT65DevTela", "comandos") mostra a coluna por 8 s (mesmo com o
-- tutorial aberto).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Input = require(script.Parent.Input)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V = UiKit.V
local px = UiKit.px

-- o que cada contexto mostra (na ordem); ações que o assento ou o aparelho não têm ficam de fora
local SHOW: { [string]: { string } } = {
	infantry = {
		"reload",
		"crouch",
		"prone",
		"sprint",
		"interact",
		"swap_weapon",
		"comm_wheel",
		"map",
		"game_menu",
	},
}
local HEADER: { [string]: string } = {
	infantry = "A PÉ",
	ground_vehicle = "VEÍCULO",
	helicopter = "HELICÓPTERO",
}
local MAX_ROWS = 10

-- faixas reservadas (px de tela, abaixo da faixa do Roblox): no alto, as listas do Roblox (squad do
-- Roblox, voz) e a ordem do comandante; embaixo, o registro de rádio (InfantryController: 330 px do
-- pé) e, mais baixo, o cartão do tutorial e o painel do veículo. PLACEHOLDER: conferir nas fotos.
local TOP_RESERVE = px(250, 330)
local FEED_TOP = 338 -- acima do registro de rádio (preferido)
local LOW_BOTTOM = px(176, 240) -- acima do tutorial e do painel do veículo (tela baixa)
local MIN_K = 0.6

local gui = UiKit.screen("VT65Comandos", 12) -- junto do HUD, abaixo dos menus
local col = Instance.new("CanvasGroup")
col.Name = "Comandos"
col.AnchorPoint = Vector2.new(0, 1)
col.Position = UDim2.new(0, px(12, 24), 1, -FEED_TOP)
col.AutomaticSize = Enum.AutomaticSize.XY
col.Size = UDim2.new()
col.BackgroundColor3 = V.PANEL
col.BackgroundTransparency = 0.35
col.BorderSizePixel = 0
col.GroupTransparency = 1
col.Visible = false
col.Parent = gui
UiKit.corner(col, 4)
UiKit.stroke(col, V.LINE, 1, 0.6)
UiKit.pad(col, px(10, 14), px(12, 16), px(8, 12))
UiKit.list(col, false, px(3, 5))
local colScale = Instance.new("UIScale")
colScale.Parent = col

local header = UiKit.kicker(col, "A PÉ", px(12, 18))
header.AutomaticSize = Enum.AutomaticSize.X
header.Size = UDim2.fromOffset(0, px(16, 24))
header.LayoutOrder = 0

local ROW_H = px(24, 34)
local KEY_W = px(36, 52)
type Row = { f: Frame, img: ImageLabel, key: TextLabel, label: TextLabel, hold: TextLabel }
local rows: { Row } = {}
for i = 1, MAX_ROWS do
	local f = Instance.new("Frame")
	f.Name = "Linha"
	f.BackgroundTransparency = 1
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, ROW_H)
	f.LayoutOrder = i
	f.Visible = false
	f.Parent = col
	UiKit.list(f, true, px(8, 10))
	-- botão do controle (imagem) ou tecla (etiqueta escura), sempre na mesma largura: a coluna alinha
	local slot = Instance.new("Frame")
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(KEY_W, ROW_H)
	slot.LayoutOrder = 1
	slot.Parent = f
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromOffset(ROW_H - 2, ROW_H - 2)
	img.Visible = false
	img.Parent = slot
	local key = UiKit.text2(slot, "", px(12, 18), V.TEXT, UiKit.F.TITLE_MED)
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromScale(0.5, 0.5)
	key.Size = UDim2.fromOffset(KEY_W, ROW_H - 4)
	key.TextXAlignment = Enum.TextXAlignment.Center
	key.TextTruncate = Enum.TextTruncate.AtEnd
	key.BackgroundColor3 = V.PANEL_3
	key.BackgroundTransparency = 0
	key.Visible = false
	UiKit.corner(key, 3)
	UiKit.stroke(key, V.LINE, 1, 0.3)
	local label = UiKit.text2(f, "", px(13, 20), V.TEXT)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, ROW_H)
	label.TextTransparency = 0.1
	label.LayoutOrder = 2
	local hold = UiKit.kicker(f, "SEGURAR", px(11, 16))
	hold.AutomaticSize = Enum.AutomaticSize.X
	hold.Size = UDim2.fromOffset(0, ROW_H)
	hold.LayoutOrder = 3
	hold.Visible = false
	rows[i] = { f = f, img = img, key = key, label = label, hold = hold }
end

-- ===== conteúdo =====
local function find(id: string, ctx: string): InputMap.Action?
	for _, a in InputMap.ACTIONS do
		if a.id == id and a.ctx == ctx and (a.seat == nil or a.seat == Input.seat) then
			return a
		end
	end
	return nil
end

-- as ações do contexto: a lista fixa da infantaria; nos veículos, as do assento, na ordem do mapa
local function actionsFor(ctx: string): { InputMap.Action }
	local out: { InputMap.Action } = {}
	local fixed = SHOW[ctx]
	if fixed then
		for _, id in fixed do
			local a = find(id, ctx) or find(id, "global")
			if a then
				table.insert(out, a)
			end
		end
		return out
	end
	for _, a in InputMap.ACTIONS do
		if a.ctx == ctx and (a.seat == nil or a.seat == Input.seat) then
			table.insert(out, a)
		end
	end
	for _, id in { "map", "game_menu" } do
		local a = find(id, "global")
		if a then
			table.insert(out, a)
		end
	end
	return out
end

local function padName(code: string): string
	return (string.gsub(code, "^Button", ""))
end

local drawnKey = ""
local settingsVersion = 0
local function draw(ctx: string)
	local dev = Input.device()
	local key = string.format("%s|%s|%s|%d", ctx, dev, tostring(Input.seat), settingsVersion)
	if key == drawnKey then
		return
	end
	drawnKey = key
	header.Text = HEADER[ctx] or ""
	header.FontFace = UiKit.Estilo.headFont(header.Text, UiKit.F.TITLE_REG)
	local n = 0
	for _, a in actionsFor(ctx) do
		if n >= MAX_ROWS then
			break
		end
		local img, text = Input.glyph(a.id, a.ctx)
		if text ~= "?" and text ~= "" then
			n += 1
			local r = rows[n]
			r.f.Visible = true
			r.img.Visible = img ~= nil
			r.img.Image = img or ""
			r.key.Visible = img == nil
			r.key.Text = if dev == "gamepad" then padName(text) else UiKit.keyName(text)
			r.label.Text = a.label
			local press = if dev == "gamepad" then a.padPress else a.keyPress
			r.hold.Visible = press == "hold"
		end
	end
	for i = n + 1, MAX_ROWS do
		rows[i].f.Visible = false
	end
end

-- ===== lugar na tela =====
-- Embaixo à esquerda: o pé da coluna fica acima do registro de rádio se a faixa entre ele e a reserva
-- do alto couber a coluna; senão desce até acima do tutorial; e, se ainda não couber, encolhe.
local bottomOff = FEED_TOP
local function layout()
	local h = gui.AbsoluteSize.Y
	local k0 = math.max(colScale.Scale, 0.01)
	local natural = col.AbsoluteSize.Y / k0
	if h < 10 or natural < 10 then
		return
	end
	local bottom = FEED_TOP
	if h - FEED_TOP - TOP_RESERVE < natural then
		bottom = LOW_BOTTOM
	end
	local room = h - bottom - TOP_RESERVE
	local k = math.clamp(room / natural, MIN_K, 1)
	if math.abs(k - colScale.Scale) > 0.01 then
		colScale.Scale = k
	end
	bottomOff = bottom
	col.Position = UDim2.new(col.Position.X.Scale, col.Position.X.Offset, 1, -bottom)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
col:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

-- ===== mostrar e esconder =====
local devUntil = 0
local shown = false
local fade: Tween? = nil
local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	local old = fade
	if old then
		old:Cancel()
	end
	if on then
		col.Visible = true
		col.Position = UDim2.new(0, px(4, 12), 1, -bottomOff)
		layout()
	end
	local t = TweenService:Create(col, TweenInfo.new(0.22, Enum.EasingStyle.Quint), {
		GroupTransparency = if on then 0 else 1,
		Position = UDim2.new(0, if on then px(12, 24) else px(4, 12), 1, -bottomOff),
	})
	fade = t
	t.Completed:Once(function(s: Enum.PlaybackState)
		if s == Enum.PlaybackState.Completed and not shown then
			col.Visible = false
		end
	end)
	t:Play()
end

local function gameCtx(): string?
	local c = Input.context()
	if c == "aim" then
		return "infantry" -- mirar não troca a coluna (piscaria a cada mira)
	end
	if c == "infantry" or c == "ground_vehicle" or c == "helicopter" then
		return c
	end
	return nil
end

-- teclas só com teclado e mouse; botões só com controle; no toque, nada (celular e tablet sem
-- teclado também, se a camada Input ainda não trocou para o toque)
local function keysMakeSense(): boolean
	local d = Input.device()
	if d == "gamepad" then
		return true
	end
	if d ~= "kbm" or ToqueUi.active() then
		return false
	end
	return not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

local function refresh()
	local st = Input.state
	local dev = os.clock() < devUntil
	local ctx = gameCtx() or (if dev then "infantry" else nil)
	local want = ctx ~= nil
		and keysMakeSense()
		and (
			dev
			or (
				Input.settings.hintsPanel ~= false
				and player:GetAttribute("TutorialPasso") == nil
				and st.alive
				and not st.downed
				and not st.disconnected
			)
		)
	if want and ctx then
		draw(ctx)
	end
	setShown(want)
end

Input.StateChanged:Connect(refresh)
Input.DeviceChanged:Connect(refresh)
Input.SettingsChanged:Connect(function()
	settingsVersion += 1 -- remapeou ou ligou/desligou a coluna: reescreve
	refresh()
end)
player:GetAttributeChangedSignal("TutorialPasso"):Connect(refresh)
task.spawn(function()
	while true do
		task.wait(0.5)
		refresh() -- assento trocado sem evento, fim do gancho de teste
	end
end)
refresh()

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "comandos" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		devUntil = os.clock() + 8
		drawnKey = ""
		refresh()
	end)
end
