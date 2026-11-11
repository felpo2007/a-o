--!strict
-- Painel do veículo (pedido do dono, 2026-11-11: "melhore ainda mais todas as interfaces"; o HUD do
-- veículo era um TextLabel em Code com três linhas de texto puro: "M48A3 Patton 13 km/h ...").
-- Este módulo só DESENHA: o VehicleController (de outra pessoa) continua calculando tudo e chama
--   local Hud = VehicleHudView.new()
--   Hud.ground({ name = spec.name, kmh = d.v * 3.6, gear = gearTxt, rpm = d.rpm, ground = "lama",
--                note = "patinando", integrity = 100, engine = 100, tracks = 100 })
--   Hud.heli({ name = "UH-34D", tempC = AIR_C, rotor = heli.rotor, knots = V * 1.9438,
--              altM = gearH, climb = heli.vy, demandHp = .., availHp = .., reqHp = .., torque = ..,
--              warn = "SEM POTÊNCIA PARA PAIRAR: corra para ganhar sustentação" })
--   Hud.seat({ name = spec.name, seat = "Atirador", weapon = "gun_90", ammo = "he", fire = "RT",
--              tubes = nil })
--   Hud.hide()
-- no lugar de label.Text = string.format(...). Mesmo lugar e largura do painel antigo (16 px da
-- esquerda, 360 px: o tutorial fica à direita dele).
-- Visual de época: placa de instrumentos oliva com filete cáqui, nome em Oswald, velocímetro em
-- números grandes, conta-giros em barra com a faixa vermelha, marcha numa etiqueta, chão e avisos em
-- latão/vermelho, e o estado do casco em três barras. Nenhuma instância nova por quadro: cada
-- chamada só troca texto, tamanho e cor do que já existe. Texto em modelos inteiros (string.format)
-- para o dicionário de idiomas.
local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)

local VehicleHudView = {}
VehicleHudView.WIDTH = 360 -- o TutorialController põe o cartão à direita: 16 + 360 + 12

local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

export type Ground = {
	name: string,
	kmh: number,
	gear: string, -- "ré", "neutro", "1ª"...
	rpm: number, -- 0..1 do giro máximo
	ground: string, -- "terra", "lama", "arrozal"...
	note: string?, -- "boiando", "patinando"
	integrity: number?, -- 0..100
	engine: number?,
	tracks: number?,
}
export type Heli = {
	name: string,
	tempC: number,
	rotor: number, -- 0..1
	knots: number,
	altM: number,
	climb: number, -- m/s
	demandHp: number,
	availHp: number,
	reqHp: number,
	torque: number, -- 0..1
	warn: string?,
}
export type Seat = { name: string, seat: string, weapon: string?, ammo: string?, fire: string?, tubes: number? }
export type View = {
	ground: (d: Ground) -> (),
	heli: (d: Heli) -> (),
	seat: (d: Seat) -> (),
	hide: () -> (),
	root: Frame,
}

local WEAPON_NAME: { [string]: string } = {
	gun_90 = "Canhão de 90 mm",
	rr_106 = "Canhões sem recuo 106 mm",
	m60 = "Metralhadora M60",
}

local function health(v: number?): Color3
	local x = math.clamp((v or 100) / 100, 0, 1)
	return if x > 0.6 then UiKit.KHAKI elseif x > 0.3 then Color3.fromRGB(226, 148, 52) else UiKit.STAMP
end

function VehicleHudView.new(parent: Instance?): View
	local gui: Instance = parent or UiKit.screen("VT65Veiculo", 12)
	local W, H = px(VehicleHudView.WIDTH, 520), px(112, 160)
	local root = Instance.new("Frame")
	root.Name = "PainelVeiculo"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 16, 1, -16)
	root.Size = UDim2.fromOffset(W, H)
	root.BackgroundColor3 = UiKit.CARD_DARK
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui
	UiKit.corner(root, 4)
	UiKit.lit(root, 0.7)
	UiKit.edge(root, UiKit.KHAKI, 1, 0.72)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, px(4, 6), 1, 0)
	bar.BackgroundColor3 = UiKit.BRASS
	bar.BorderSizePixel = 0
	bar.Parent = root
	local P = px(12, 18)

	local name = UiKit.rotulo(root, 17, UiKit.BRASS_LIGHT, UiKit.HEAD_FONT)
	name.Position = UDim2.fromOffset(P, px(4, 6))
	name.Size = UDim2.new(1, -P - px(100, 140), 0, px(22, 32))
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local tag = UiKit.rotulo(root, 13, UiKit.NIGHT, UiKit.HEAD_FONT)
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -P, 0, px(6, 8))
	tag.Size = UDim2.fromOffset(px(92, 130), px(18, 26))
	tag.BackgroundColor3 = UiKit.KHAKI
	tag.BackgroundTransparency = 0
	tag.TextXAlignment = Enum.TextXAlignment.Center
	UiKit.corner(tag, 3)

	-- número grande (velocidade) e a unidade
	local big = UiKit.rotulo(root, 34, UiKit.CARD, UiKit.HEAD_FONT)
	big.Position = UDim2.fromOffset(P, px(28, 40))
	big.Size = UDim2.fromOffset(px(86, 124), px(40, 58))
	big.TextXAlignment = Enum.TextXAlignment.Right
	local unit = UiKit.rotulo(root, 12, UiKit.KHAKI, UiKit.HEAD_REG)
	unit.Position = UDim2.fromOffset(P + px(90, 128), px(46, 66))
	unit.Size = UDim2.fromOffset(px(50, 70), px(18, 26))
	-- conta-giros / potência: barra com faixa vermelha no fim e a marca da exigência
	local gx = P + px(146, 210)
	local gauge = Instance.new("Frame")
	gauge.Position = UDim2.fromOffset(gx, px(36, 52))
	gauge.Size = UDim2.new(1, -gx - P, 0, px(10, 14))
	gauge.BackgroundColor3 = UiKit.DRAB
	gauge.BorderSizePixel = 0
	gauge.Parent = root
	UiKit.corner(gauge, 2)
	local red = Instance.new("Frame")
	red.AnchorPoint = Vector2.new(1, 0)
	red.Position = UDim2.fromScale(1, 0)
	red.Size = UDim2.fromScale(0.15, 1)
	red.BackgroundColor3 = UiKit.STAMP
	red.BackgroundTransparency = 0.45
	red.BorderSizePixel = 0
	red.Parent = gauge
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UiKit.BRASS
	fill.BorderSizePixel = 0
	fill.Parent = gauge
	UiKit.corner(fill, 2)
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.new(0, 0, 0, -3)
	mark.Size = UDim2.new(0, 2, 1, 6)
	mark.BackgroundColor3 = UiKit.CARD
	mark.BorderSizePixel = 0
	mark.Visible = false
	mark.Parent = gauge
	local gaugeText = UiKit.rotulo(root, 12, UiKit.KHAKI, UiKit.BODY_FONT)
	gaugeText.Position = UDim2.fromOffset(gx, px(48, 68))
	gaugeText.Size = UDim2.new(1, -gx - P, 0, px(16, 22))
	-- linha de baixo: chão / altura e avisos
	local info = UiKit.rotulo(root, 13, UiKit.CARD, UiKit.BODY_FONT)
	info.Position = UDim2.fromOffset(P, px(70, 100))
	info.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
	info.TextTruncate = Enum.TextTruncate.AtEnd
	info.RichText = true
	-- estado: três barras (casco, motor, esteiras) ou o aviso do helicóptero
	local stateRow = Instance.new("Frame")
	stateRow.Position = UDim2.fromOffset(P, px(90, 128))
	stateRow.Size = UDim2.new(1, -2 * P, 0, px(14, 20))
	stateRow.BackgroundTransparency = 1
	stateRow.Parent = root
	type Bar = { label: TextLabel, back: Frame, fill: Frame }
	local bars: { Bar } = {}
	for i, lbl in { "Casco", "Motor", "Esteiras" } do
		local x = (i - 1) / 3
		local l = UiKit.rotulo(stateRow, 11, UiKit.KHAKI, UiKit.HEAD_REG)
		l.Position = UDim2.new(x, 0, 0, 0)
		l.Size = UDim2.new(0.13, 0, 1, 0)
		l.Text = lbl
		l.TextScaled = false
		local back = Instance.new("Frame")
		back.Position = UDim2.new(x + 0.14, 0, 0.3, 0)
		back.Size = UDim2.new(0.17, 0, 0.4, 0)
		back.BackgroundColor3 = UiKit.DRAB
		back.BorderSizePixel = 0
		back.Parent = stateRow
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = UiKit.KHAKI
		f.BorderSizePixel = 0
		f.Parent = back
		bars[i] = { label = l, back = back, fill = f }
	end
	local warn = UiKit.rotulo(root, 13, Color3.fromRGB(240, 124, 104), UiKit.HEAD_FONT)
	warn.Position = UDim2.fromOffset(P, px(88, 126))
	warn.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
	warn.TextTruncate = Enum.TextTruncate.AtEnd
	warn.Visible = false
	local warnPulse: Tween? = nil

	local mode = ""
	local function show(m: string)
		if not root.Visible then
			root.Visible = true
			root.Position = UDim2.new(0, -W, 1, -16)
			TweenService
				:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 16, 1, -16) })
				:Play()
		end
		if m ~= mode then
			mode = m
			stateRow.Visible = m == "ground"
			gauge.Visible = m ~= "seat"
			big.Visible = m ~= "seat"
			unit.Visible = m ~= "seat"
			gaugeText.Visible = m ~= "seat"
		end
	end
	local function setWarn(text: string?)
		local on = text ~= nil and text ~= ""
		warn.Visible = on and mode == "heli"
		if on then
			warn.Text = text :: string
			if not warnPulse then
				local t = TweenService:Create(
					warn,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ TextTransparency = 0.5 }
				)
				t:Play()
				warnPulse = t
			end
		elseif warnPulse then
			warnPulse:Cancel()
			warnPulse = nil
			warn.TextTransparency = 0
		end
	end

	local view: View = {} :: any
	view.root = root
	function view.ground(d: Ground)
		show("ground")
		setWarn(nil)
		name.Text = d.name
		tag.Text = UiKit.upper(d.gear)
		big.Text = string.format("%d", math.floor(math.abs(d.kmh) + 0.5))
		unit.Text = "km/h"
		local r = math.clamp(d.rpm, 0, 1)
		fill.Size = UDim2.fromScale(r, 1)
		fill.BackgroundColor3 = if r > 0.85 then UiKit.STAMP else UiKit.BRASS
		mark.Visible = false
		gaugeText.Text = string.format("giro %d%%", math.floor(r * 100 + 0.5))
		info.Text = if d.note and d.note ~= ""
			then string.format('Chão: %s · <font color="#ECCA74">%s</font>', d.ground, d.note)
			else string.format("Chão: %s", d.ground)
		for i, v in { d.integrity, d.engine, d.tracks } do
			local b = bars[i]
			local x = math.clamp((v or 100) / 100, 0, 1)
			b.fill.Size = UDim2.fromScale(x, 1)
			b.fill.BackgroundColor3 = health(v)
		end
	end
	function view.heli(d: Heli)
		show("heli")
		name.Text = d.name
		tag.Text = string.format("%d °C", math.floor(d.tempC + 0.5))
		big.Text = string.format("%d", math.floor(d.knots + 0.5))
		unit.Text = "nós"
		local avail = math.max(d.availHp, 1)
		fill.Size = UDim2.fromScale(math.clamp(d.demandHp / avail, 0, 1), 1)
		fill.BackgroundColor3 = if d.reqHp > d.availHp then UiKit.STAMP else UiKit.BRASS
		mark.Visible = true
		mark.Position = UDim2.new(math.clamp(d.reqHp / avail, 0, 1), 0, 0, -3)
		gaugeText.Text = string.format(
			"potência %d de %d hp · torque %d%%",
			math.floor(d.demandHp + 0.5),
			math.floor(d.availHp + 0.5),
			math.floor(d.torque * 100 + 0.5)
		)
		info.Text = string.format(
			"Altura %d m · subida %+.1f m/s · rotor %d%%",
			math.floor(math.max(d.altM, 0) + 0.5),
			d.climb,
			math.floor(d.rotor * 100 + 0.5)
		)
		setWarn(d.warn)
	end
	function view.seat(d: Seat)
		show("seat")
		setWarn(nil)
		name.Text = d.name
		tag.Text = UiKit.upper(d.seat)
		local w = d.weapon
		if w == "rr_106" then
			info.Text = string.format("Tubos carregados: %d (recarregar: parado)", d.tubes or 0)
		elseif w then
			local wn = WEAPON_NAME[w] or w
			info.Text = if d.ammo
				then string.format("%s · munição: %s · atirar: %s", wn, d.ammo, d.fire or "?")
				else string.format("%s · atirar: %s", wn, d.fire or "?")
		else
			info.Text = "Passageiro"
		end
	end
	function view.hide()
		if root.Visible then
			setWarn(nil)
			root.Visible = false
			mode = ""
		end
	end
	return view
end

-- só para o gancho de teste do Studio (HudCampo): um painel de exemplo de cada tipo
function VehicleHudView.demo(kind: string): View
	local v = VehicleHudView.new()
	if kind == "helicoptero" then
		v.heli({
			name = "UH-34D",
			tempC = 31,
			rotor = 1,
			knots = 62,
			altM = 48,
			climb = 1.6,
			demandHp = 1210,
			availHp = 1390,
			reqHp = 1150,
			torque = 0.87,
			warn = nil,
		})
	else
		v.ground({
			name = "M48A3 Patton",
			kmh = 13,
			gear = "2ª",
			rpm = 0.62,
			ground = "lama",
			note = "patinando",
			integrity = 92,
			engine = 70,
			tracks = 28,
		})
	end
	return v
end

return VehicleHudView
