--!strict
-- Faixa dos eventos da partida (Controllers/EventosVisual lê ReplicatedStorage.VT65Eventos): à direita
-- da tela, uma linha por evento, empilhadas (no máximo 4, as que acabam antes em cima). Cada linha:
-- filete e rótulo na cor da fase, ícone do evento, o nome, o setor e a grade, e a contagem regressiva
-- até o fim. Some com os menus, o mapa, a roda e a tela de baixa (caído ou morto).
-- As linhas são criadas uma vez e reaproveitadas; a lista muda só por evento do EventosVisual e o
-- relógio reescreve o texto 4 vezes por segundo (nada por quadro).
-- Studio: workspace:SetAttribute("VT65DevTela", "eventos") mostra eventos de exemplo (um em cada fase)
-- por 20 s, sem o servidor, aqui, na carta e no mundo.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EventosVisual = require(script.Parent.EventosVisual)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local V, F = UiKit.V, UiKit.F
local px = UiKit.px
local MAX = 4
local W, H, GAP = px(280, 400), px(48, 68), px(6, 9)

local gui = UiKit.screen("VT65EventosHud", 14) -- com o HUD da frente (14), abaixo dos menus
local holder = Instance.new("Frame")
holder.Name = "Eventos"
holder.AnchorPoint = Vector2.new(1, 0)
holder.Position = UDim2.new(1, -px(16, 24), 0.3, 0)
holder.Size = UDim2.fromOffset(W, MAX * (H + GAP))
holder.BackgroundTransparency = 1
holder.Parent = gui
local fit = UiKit.fit(gui, holder, W + 40, MAX * (H + GAP) + 40, 8)

type Row = {
	key: string?,
	frame: Frame,
	bar: Frame,
	icon: TextLabel,
	name: TextLabel,
	phase: TextLabel,
	where: TextLabel,
	clock: TextLabel,
}
local rows: { Row } = {}
for i = 1, MAX do
	local f = UiKit.panel(holder, V.PANEL, 0.1)
	f.Name = string.format("Evento%d", i)
	f.Position = UDim2.fromOffset(0, (i - 1) * (H + GAP))
	f.Size = UDim2.fromOffset(W, H)
	f.Visible = false
	local bar = Instance.new("Frame")
	bar.Name = "Fase"
	bar.Size = UDim2.new(0, px(4, 6), 1, 0)
	bar.BackgroundColor3 = V.KHAKI
	bar.BorderSizePixel = 0
	bar.Parent = f
	local iconBox = Instance.new("Frame")
	iconBox.Name = "Icone"
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.new(0, px(12, 16), 0.5, 0)
	iconBox.Size = UDim2.fromOffset(H - px(14, 20), H - px(14, 20))
	iconBox.BackgroundColor3 = V.PANEL_3
	iconBox.BorderSizePixel = 0
	iconBox.Parent = f
	UiKit.corner(iconBox, 4)
	local icon = UiKit.text2(iconBox, "", px(18, 26), V.TEXT, F.BODY_B)
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	local x = px(12, 16) + H - px(14, 20) + px(10, 14)
	local name = UiKit.title(f, "", px(16, 23), V.TEXT)
	name.Position = UDim2.fromOffset(x, px(5, 7))
	name.Size = UDim2.new(1, -x - px(70, 100), 0, px(20, 28))
	local phase = UiKit.kicker(f, "", px(12, 18), V.KHAKI)
	phase.AutomaticSize = Enum.AutomaticSize.X
	phase.Position = UDim2.fromOffset(x, px(26, 37))
	phase.Size = UDim2.fromOffset(0, px(16, 24))
	local where = UiKit.kicker(f, "", px(12, 18), V.DIM)
	where.Position = UDim2.fromOffset(x + px(84, 120), px(26, 37))
	where.Size = UDim2.new(1, -x - px(84, 120) - px(70, 100), 0, px(16, 24))
	local clock = UiKit.title(f, "", px(22, 31), V.TEXT)
	clock.AnchorPoint = Vector2.new(1, 0.5)
	clock.Position = UDim2.new(1, -px(12, 16), 0.5, 0)
	clock.Size = UDim2.fromOffset(px(64, 92), px(28, 40))
	clock.TextXAlignment = Enum.TextXAlignment.Right
	rows[i] = { key = nil, frame = f, bar = bar, icon = icon, name = name, phase = phase, where = where, clock = clock }
end

local shown: { EventosVisual.Ev } = {}

local function clockText(s: number): string
	local t = math.ceil(s)
	return string.format("%d:%02d", t // 60, t % 60)
end

local function paint()
	shown = EventosVisual.list()
	for i, r in rows do
		local ev = shown[i]
		if not ev then
			r.key = nil
			r.frame.Visible = false
			continue
		end
		local fresh = r.key ~= ev.key
		r.key = ev.key
		r.frame.Visible = true
		local c = EventosVisual.color(ev.fase)
		r.bar.BackgroundColor3 = c
		r.icon.Text = EventosVisual.icon(ev.id)
		r.name.Text = UiKit.upper(ev.name)
		r.name.FontFace = UiKit.headFont(ev.name)
		r.phase.Text = EventosVisual.PHASE_TEXT[ev.fase] or ""
		r.phase.TextColor3 = c
		-- onde: o setor (S3) e a grade de 1965; sem setor, só a grade
		r.where.Text = if ev.sector then string.format("S%d · %s", ev.sector, ev.grade) else ev.grade
		r.clock.Text = clockText(EventosVisual.left(ev))
		r.clock.TextColor3 = if ev.fase == "fim" then V.MUTED else V.TEXT
		if fresh then
			-- a linha nova entra deslizando da direita
			local p = UDim2.fromOffset(0, (i - 1) * (H + GAP))
			r.frame.Position = p + UDim2.fromOffset(px(24, 34), 0)
			TweenService:Create(r.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), { Position = p }):Play()
		end
	end
end

local function wanted(): boolean
	local s = Input.state
	return #shown > 0
		and s.menus == 0
		and not s.map
		and s.alive
		and not s.downed
		and s.wheel == nil
		and not s.disconnected
end

EventosVisual.Changed:Connect(function()
	paint()
	gui.Enabled = wanted()
end)
Input.StateChanged:Connect(function()
	gui.Enabled = wanted()
end)
paint()
gui.Enabled = wanted()

-- relógio e visibilidade, 4 vezes por segundo
task.spawn(function()
	while true do
		task.wait(0.25)
		local want = wanted()
		if gui.Enabled ~= want then
			gui.Enabled = want
			if want then
				fit.play(TweenInfo.new(0.2, Enum.EasingStyle.Quint), 1, 0.96)
			end
		end
		if want then
			for i, r in rows do
				local ev = shown[i]
				if ev and r.frame.Visible then
					r.clock.Text = clockText(EventosVisual.left(ev))
				end
			end
		end
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "eventos" then
			EventosVisual.dev(20)
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
