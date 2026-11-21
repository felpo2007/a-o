--!strict
-- Painel do veículo. Só DESENHA: o VehicleController calcula tudo e chama
--   local Hud = VehicleHudView.new()
--   Hud.ground({ name = spec.name, kmh = d.v * 3.6, gear = gearTxt, rpm = d.rpm, ground = "lama",
--                note = "patinando", integrity = 100, engine = 100, tracks = 100,
--                faction = "US", seat = "Motorista", warn = nil, wheeled = false })
--   Hud.heli({ name = "UH-34D", tempC = AIR_C, rotor = heli.rotor, knots = V * 1.9438,
--              altM = gearH, climb = heli.vy, demandHp = .., availHp = .., reqHp = .., torque = ..,
--              warn = "...", faction = "US", assist = true })
--   Hud.seat({ name = spec.name, seat = "Atirador", weapon = "gun_90", ammo = "he", fire = "RT",
--              tubes = nil, faction = "US", personal = false, canFire = nil, closed = false })
--   Hud.hide()
-- D-100 (pedido do dono, 2026-11-12, junto com o painel de lugares): no estilo das telas novas
-- (painel escuro, título em Oswald, cor do lado: EUA azul, VC vermelho), com o nome do lugar, o
-- estado da própria arma num lugar aberto ("no ângulo" / "fora do ângulo"), o aviso de veículo preso
-- ou tombado e as teclas de trocar de lugar e sair. Mesmo lugar e largura de antes (16 px da
-- esquerda, 360 px: o tutorial fica à direita dele). Nenhuma instância nova por quadro.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local VehicleHudView = {}
VehicleHudView.WIDTH = 360 -- o TutorialController põe o cartão à direita: 16 + 360 + 12

local V, F = UiKit.V, UiKit.F
local px = UiKit.px

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
	faction: string?,
	seat: string?,
	warn: string?, -- preso, tombado
	wheeled: boolean?, -- "Rodas" no lugar de "Esteiras"
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
	faction: string?,
	assist: boolean?, -- estabilizador
}
export type Seat = {
	name: string,
	seat: string,
	weapon: string?,
	ammo: string?,
	fire: string?,
	tubes: number?,
	faction: string?,
	personal: boolean?, -- a própria arma do ocupante (lugar aberto)
	canFire: boolean?, -- no ângulo do lugar e em 1ª pessoa
	closed: boolean?, -- lugar fechado: não atira
	warn: string?,
}
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

local function weaponName(id: string): string
	local n = WEAPON_NAME[id]
	if n then
		return n
	end
	local wp = Weapons.get(id)
	return if wp and wp.name then wp.name else id
end

-- toque como entrada principal (contrato da Parte 13: Input.touchActive do T1)
local function touchOn(): boolean
	local f = (Input :: any).touchActive
	if type(f) == "function" then
		return f() == true
	end
	return Input.device() == "touch"
end

local function health(v: number?): Color3
	local x = math.clamp((v or 100) / 100, 0, 1)
	return if x > 0.6 then V.KHAKI elseif x > 0.3 then Color3.fromRGB(226, 148, 52) else V.RED
end

function VehicleHudView.new(parent: Instance?): View
	local gui: Instance = parent or UiKit.screen("VT65Veiculo", 12)
	local W, H = px(VehicleHudView.WIDTH, 520), px(138, 196)
	local root = Instance.new("Frame")
	root.Name = "PainelVeiculo"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 16, 1, -16)
	root.Size = UDim2.fromOffset(W, H)
	root.BackgroundColor3 = V.PANEL
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui
	UiKit.corner(root, 4)
	UiKit.stroke(root, V.LINE, 1, 0.5)
	local bar = Instance.new("Frame") -- cor do lado
	bar.Size = UDim2.new(0, px(4, 6), 1, 0)
	bar.BackgroundColor3 = V.US
	bar.BorderSizePixel = 0
	bar.Parent = root
	local P = px(12, 18)

	local name = UiKit.title(root, "", 17)
	name.Position = UDim2.fromOffset(P, px(4, 6))
	name.Size = UDim2.new(1, -P - px(110, 150), 0, px(22, 32))
	local tag = UiKit.tag(root, "", V.PANEL_3, 13)
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -P, 0, px(6, 8))
	tag.Size = UDim2.fromOffset(0, px(20, 28))

	-- número grande (velocidade) e a unidade
	local big = UiKit.text2(root, "", 34, V.TEXT, F.TITLE)
	big.Position = UDim2.fromOffset(P, px(28, 40))
	big.Size = UDim2.fromOffset(px(86, 124), px(40, 58))
	big.TextXAlignment = Enum.TextXAlignment.Right
	local unit = UiKit.kicker(root, "", 12)
	unit.Position = UDim2.fromOffset(P + px(90, 128), px(46, 66))
	unit.Size = UDim2.fromOffset(px(50, 70), px(18, 26))
	-- conta-giros / potência: barra com faixa vermelha no fim e a marca da exigência
	local gx = P + px(146, 210)
	local gauge = Instance.new("Frame")
	gauge.Position = UDim2.fromOffset(gx, px(36, 52))
	gauge.Size = UDim2.new(1, -gx - P, 0, px(10, 14))
	gauge.BackgroundColor3 = V.PANEL_2
	gauge.BorderSizePixel = 0
	gauge.Parent = root
	UiKit.corner(gauge, 2)
	local red = Instance.new("Frame")
	red.AnchorPoint = Vector2.new(1, 0)
	red.Position = UDim2.fromScale(1, 0)
	red.Size = UDim2.fromScale(0.15, 1)
	red.BackgroundColor3 = V.RED
	red.BackgroundTransparency = 0.45
	red.BorderSizePixel = 0
	red.Parent = gauge
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = V.KHAKI
	fill.BorderSizePixel = 0
	fill.Parent = gauge
	UiKit.corner(fill, 2)
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.new(0, 0, 0, -3)
	mark.Size = UDim2.new(0, 2, 1, 6)
	mark.BackgroundColor3 = V.TEXT
	mark.BorderSizePixel = 0
	mark.Visible = false
	mark.Parent = gauge
	local gaugeText = UiKit.text2(root, "", 12, V.DIM, F.BODY)
	gaugeText.Position = UDim2.fromOffset(gx, px(48, 68))
	gaugeText.Size = UDim2.new(1, -gx - P, 0, px(16, 22))
	-- linha de baixo: chão / altura e avisos
	local info = UiKit.text2(root, "", 13, V.TEXT, F.BODY)
	info.Position = UDim2.fromOffset(P, px(70, 100))
	info.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
	info.TextTruncate = Enum.TextTruncate.AtEnd
	info.RichText = true
	-- estado: três barras (casco, motor, esteiras/rodas) ou o aviso
	local stateRow = Instance.new("Frame")
	stateRow.Position = UDim2.fromOffset(P, px(90, 128))
	stateRow.Size = UDim2.new(1, -2 * P, 0, px(14, 20))
	stateRow.BackgroundTransparency = 1
	stateRow.Parent = root
	type Bar = { label: TextLabel, back: Frame, fill: Frame }
	local bars: { Bar } = {}
	for i, lbl in { "Casco", "Motor", "Esteiras" } do
		local x = (i - 1) / 3
		local l = UiKit.kicker(stateRow, lbl, 11)
		l.Position = UDim2.new(x, 0, 0, 0)
		l.Size = UDim2.new(0.13, 0, 1, 0)
		local back = Instance.new("Frame")
		back.Position = UDim2.new(x + 0.14, 0, 0.3, 0)
		back.Size = UDim2.new(0.17, 0, 0.4, 0)
		back.BackgroundColor3 = V.PANEL_2
		back.BorderSizePixel = 0
		back.Parent = stateRow
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = V.KHAKI
		f.BorderSizePixel = 0
		f.Parent = back
		bars[i] = { label = l, back = back, fill = f }
	end
	local warn = UiKit.text2(root, "", 13, Color3.fromRGB(240, 124, 104), F.TITLE)
	warn.Position = UDim2.fromOffset(P, px(88, 126))
	warn.Size = UDim2.new(1, -2 * P, 0, px(18, 26))
	warn.TextTruncate = Enum.TextTruncate.AtEnd
	warn.Visible = false
	local warnPulse: Tween? = nil
	-- teclas: trocar de lugar e sair (as do contexto do veículo, controle ou teclado)
	local hints = UiKit.chips(root, px(20, 30), false, 12)
	hints.frame.AnchorPoint = Vector2.new(0, 1)
	hints.frame.Position = UDim2.new(0, P, 1, -px(6, 8))
	hints.frame.Size = UDim2.new(1, -2 * P, 0, px(20, 30))
	-- Toque (Parte 13): o canto de baixo à esquerda é do analógico flutuante. O painel sobe para o
	-- alto à esquerda, logo abaixo do mapa e do menu do HUD de toque (T1: centro a 9% da altura,
	-- 9 mm), um pouco menor e sem a fileira de teclas: os botões de lugar e sair estão na tela
	-- (ToqueVeiculo.client). O painel não pega toque (o analógico funciona por baixo dele).
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local hintsH = px(26, 38)
	local docked = ""
	local function touchTop(): number
		local a = if gui:IsA("GuiBase2d") then gui.AbsoluteSize else Vector2.new(800, 360)
		local short = math.min(a.X, a.Y)
		local ppm = (if short >= 600 then 132 else 160) / 25.4 -- px por mm (o palpite do Shared/Toque)
		local size = math.max(9 * ppm, 48)
		return math.floor(math.max(a.Y * 0.09, size / 2) + size / 2 + 2.5 * ppm + 0.5)
	end
	local function dock(): (UDim2, UDim2) -- lugar de repouso e de onde entra
		local touch = touchOn()
		local top = if touch then touchTop() else 0
		local d = if touch then string.format("touch%d", top) else "pc"
		if d ~= docked then
			docked = d
			root.AnchorPoint = if touch then Vector2.zero else Vector2.new(0, 1)
			root.Size = UDim2.fromOffset(W, if touch then H - hintsH else H)
			scale.Scale = if touch then 0.85 else 1
			hints.frame.Visible = not touch
			if root.Visible then
				root.Position = if touch then UDim2.fromOffset(16, top) else UDim2.new(0, 16, 1, -16)
			end
		end
		if touch then
			return UDim2.fromOffset(16, top), UDim2.fromOffset(-W, top)
		end
		return UDim2.new(0, 16, 1, -16), UDim2.new(0, -W, 1, -16)
	end
	local hintKey = ""
	local function refreshHints(heliCtx: boolean)
		local k = (if heliCtx then "h" else "g") .. (if Input.isGamepad() then "p" else "k")
		if k == hintKey then
			return
		end
		hintKey = k
		local ctx = if heliCtx then "helicopter" else "ground_vehicle"
		hints.clear()
		hints.action("v_switch_seat", ctx, "Lugares")
		hints.action("v_exit", ctx, "Sair")
	end

	local mode = ""
	local function show(m: string, faction: string?)
		bar.BackgroundColor3 = if faction == "VC" then V.VC else V.US
		local rest, from = dock()
		if not root.Visible then
			root.Visible = true
			root.Position = from
			TweenService:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = rest }):Play()
		end
		if m ~= mode then
			mode = m
			stateRow.Visible = m == "ground"
			gauge.Visible = m ~= "seat"
			big.Visible = m ~= "seat"
			unit.Visible = m ~= "seat"
			gaugeText.Visible = m ~= "seat"
		end
		refreshHints(m == "heli")
	end
	local function setWarn(text: string?)
		local on = text ~= nil and text ~= ""
		warn.Visible = on
		if mode == "ground" then
			stateRow.Visible = not on
		end
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
	local function setName(text: string)
		local t = UiKit.upper(text)
		if name.Text ~= t then
			name.Text = t
			name.FontFace = UiKit.headFont(t)
		end
	end

	local view: View = {} :: any
	view.root = root
	function view.ground(d: Ground)
		show("ground", d.faction)
		setName(d.name)
		tag.Text = UiKit.upper(if d.seat then string.format("%s · %s", d.seat, d.gear) else d.gear)
		big.Text = string.format("%d", math.floor(math.abs(d.kmh) + 0.5))
		unit.Text = "KM/H"
		local r = math.clamp(d.rpm, 0, 1)
		fill.Size = UDim2.fromScale(r, 1)
		fill.BackgroundColor3 = if r > 0.85 then V.RED else V.KHAKI
		mark.Visible = false
		gaugeText.Text = string.format("giro %d%%", math.floor(r * 100 + 0.5))
		info.Text = if d.note and d.note ~= ""
			then string.format('Chão: %s · <font color="#ECCA74">%s</font>', d.ground, d.note)
			else string.format("Chão: %s", d.ground)
		bars[3].label.Text = if d.wheeled then "Rodas" else "Esteiras"
		for i, v in { d.integrity, d.engine, d.tracks } do
			local b = bars[i]
			local x = math.clamp((v or 100) / 100, 0, 1)
			b.fill.Size = UDim2.fromScale(x, 1)
			b.fill.BackgroundColor3 = health(v)
		end
		setWarn(d.warn)
	end
	function view.heli(d: Heli)
		show("heli", d.faction)
		setName(d.name)
		tag.Text = if d.assist == false
			then string.format("%d °C · MANUAL", math.floor(d.tempC + 0.5))
			else string.format("%d °C · ESTAB.", math.floor(d.tempC + 0.5))
		big.Text = string.format("%d", math.floor(d.knots + 0.5))
		unit.Text = "NÓS"
		local avail = math.max(d.availHp, 1)
		fill.Size = UDim2.fromScale(math.clamp(d.demandHp / avail, 0, 1), 1)
		fill.BackgroundColor3 = if d.reqHp > d.availHp then V.RED else V.KHAKI
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
		show("seat", d.faction)
		setName(d.name)
		tag.Text = UiKit.upper(d.seat)
		local w = d.weapon
		if w == "rr_106" then
			info.Text = string.format("Tubos carregados: %d (recarregar: parado)", d.tubes or 0)
		elseif w and d.personal then
			-- fire nil: toque (o botão de tiro está na tela, sem tecla para citar)
			info.Text = if d.canFire and d.fire
				then string.format('%s · atirar: %s · <font color="#B4C878">no ângulo</font>', weaponName(w), d.fire)
				elseif d.canFire then string.format('%s · <font color="#B4C878">no ângulo</font>', weaponName(w))
				else string.format('%s · <font color="#F07C68">fora do ângulo do lugar</font>', weaponName(w))
		elseif w then
			local wn = weaponName(w)
			info.Text = if d.ammo and d.fire
				then string.format("%s · munição: %s · atirar: %s", wn, d.ammo, d.fire)
				elseif d.ammo then string.format("%s · munição: %s", wn, d.ammo)
				elseif d.fire then string.format("%s · atirar: %s", wn, d.fire)
				else wn
		elseif d.closed then
			info.Text = "Lugar fechado: daqui não se atira"
		else
			info.Text = "Passageiro"
		end
		setWarn(d.warn)
	end
	function view.hide()
		if root.Visible then
			setWarn(nil)
			root.Visible = false
			mode = ""
		end
	end
	Input.DeviceChanged:Connect(function()
		hintKey = ""
		dock()
		if mode ~= "" then
			refreshHints(mode == "heli")
		end
	end)
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
			faction = "US",
			assist = true,
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
			faction = "US",
			seat = "Motorista",
		})
	end
	return v
end

return VehicleHudView
