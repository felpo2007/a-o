--!strict
-- Sol real de 18/08/1965 em Vạn Tường (Parte 9.6): calcula a direção real (SolarPosition) e ajusta
-- ClockTime e GeographicLatitude para o Roblox reproduzi-la. O tempo corre em tempo real.
-- A partida começa às 07:00 (D-64): às 06:30 o sol ainda está a −0,9° e o mapa ficava no escuro.
-- Névoa matinal dourada que se dissipa entre 06:30 e 08:00.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Horarios = require(ReplicatedStorage.Shared.Horarios)
local SolarPosition = require(ReplicatedStorage.Shared.SolarPosition)

local LightingService = {}
LightingService.DATE = { 1965, 8, 18 }
LightingService.TZ = 8 -- hora de Saigon em 1965 (UTC+8) — confirmar (DESIGN D-27)
LightingService.LAT, LightingService.LON = 15.30, 108.85

-- v43 (pedido do dono: "o sol está atrapalhando um pouco a visão"): 08:30 (era 07:00, o sol a 6,2° no
-- leste-nordeste, contraluz no olho de quem olha para o leste). Às 08:30 ele já está bem mais alto; o
-- desembarque foi às 06:30 e o combate seguiu o dia todo.
LightingService.START_HOUR = 8.5
local startHour = LightingService.START_HOUR
local t0 = os.clock()
local lastC, lastL = startHour, 15
local lastHour = startHour
local applyAtmosphere: () -> ()
local relogioParado = false -- D-248: o fim de tarde fica no fim de tarde a partida inteira
local atmHora: Horarios.Atm? = nil

function LightingService.setStart(hour: number)
	startHour = hour
	t0 = os.clock()
	lastC, lastL = hour, 15
	LightingService.update()
end

function LightingService.hourNow(): number
	if relogioParado then
		return startHour
	end
	return startHour + (os.clock() - t0) / 3600
end

local function getDir(c: number, l: number): (number, number, number)
	Lighting.ClockTime = c
	Lighting.GeographicLatitude = l
	local d = Lighting:GetSunDirection()
	return d.X, d.Y, d.Z
end

function LightingService.update()
	local hour = LightingService.hourNow()
	local y, m, d = table.unpack(LightingService.DATE)
	local az, el = SolarPosition.compute(y, m, d, hour, LightingService.TZ, LightingService.LAT, LightingService.LON)
	local tx, ty, tz = SolarPosition.direction(az, el)
	local c, l, errDeg = hour, LightingService.LAT, 0
	-- D-224: de noite não há sol para acertar: vale o relógio (a lua e as estrelas são do Roblox)
	if el > -3 then
		c, l, errDeg = SolarPosition.fit(tx, ty, tz, getDir, lastC, lastL)
	end
	Lighting.ClockTime = c
	Lighting.GeographicLatitude = l
	lastC, lastL = c, l
	ReplicatedStorage:SetAttribute("SunAzimuth", az)
	ReplicatedStorage:SetAttribute("SunElevation", el)
	ReplicatedStorage:SetAttribute("SunFitErrorDeg", errDeg)
	lastHour = hour
	applyAtmosphere()
end

-- névoa matinal (mais densa ao amanhecer, dissipa em 1,5 h, Parte 9.6) + chuva (Weather): a pancada
-- engrossa a névoa e escurece o céu. Recalcula quando a hora anda e quando a chuva muda.
-- Valores de arte (D-64): névoa quente e baixa que pega a luz do sol rasante, sem tapar 300 m.
-- D-69: com o céu de foto, a névoa da D-64 (Haze 2,5 às 07:00) cobria tudo de laranja chapado;
-- caiu para ~1,2 e as nuvens da foto aparecem (conferido no Studio).
applyAtmosphere = function()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		local k = math.clamp((lastHour - 6.5) / 1.5, 0, 1)
		local rain = ReplicatedStorage:GetAttribute("Rain")
		local r = if type(rain) == "number" then rain else 0
		local fixa = atmHora
		if fixa then
			atm.Density = fixa.densidade + 0.25 * r
			atm.Haze = fixa.haze + 2.0 * r
			atm.Glare = fixa.brilho * (1 - r)
			return
		end
		atm.Density = 0.34 - 0.08 * k + 0.25 * r
		atm.Haze = 1.4 - 0.6 * k + 2.0 * r
		-- v43: o brilho em volta do sol caiu a 1/3 (era 0,5 × (1 − 0,4k): 0,3 depois das 08:00)
		atm.Glare = 0.17 * (1.0 - 0.4 * k) * (1 - r)
	end
end

-- D-224: o horário votado para a próxima partida. A luz de cada um parte sempre dos valores do place.
type BaseLuz = {
	amb: Color3,
	ext: Color3,
	brilho: number,
	expo: number,
	atmCor: Color3?,
	atmDecai: Color3?,
	atmDesloc: number?,
	bloom: { i: number, s: number, t: number }?,
	raios: { i: number, s: number }?,
}
local baseLuz: BaseLuz? = nil
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
function LightingService.aplicarHorario(id: string)
	local h = Horarios.por(id) or Horarios.por(Horarios.PADRAO)
	if not h then
		return
	end
	local b = baseLuz
	if not b then
		local a0 = Lighting:FindFirstChildOfClass("Atmosphere")
		local b0 = Lighting:FindFirstChildOfClass("BloomEffect")
		local r0 = Lighting:FindFirstChildOfClass("SunRaysEffect")
		b = {
			amb = Lighting.Ambient,
			ext = Lighting.OutdoorAmbient,
			brilho = Lighting.Brightness,
			expo = Lighting.ExposureCompensation,
			atmCor = a0 and a0.Color,
			atmDecai = a0 and a0.Decay,
			atmDesloc = a0 and a0.Offset,
			bloom = if b0 then { i = b0.Intensity, s = b0.Size, t = b0.Threshold } else nil,
			raios = if r0 then { i = r0.Intensity, s = r0.Spread } else nil,
		}
		baseLuz = b
	end
	local base = b :: BaseLuz
	local cor = Color3.fromRGB(h.luz.cor[1], h.luz.cor[2], h.luz.cor[3])
	Lighting.Ambient = if h.luz.ambiente then rgb(h.luz.ambiente) else base.amb:Lerp(cor, h.luz.mistura)
	Lighting.OutdoorAmbient = if h.luz.externo then rgb(h.luz.externo) else base.ext:Lerp(cor, h.luz.mistura)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	atmHora = h.luz.atm
	if atm then
		local x = h.luz.atm
		atm.Color = if x then rgb(x.cor) else base.atmCor or atm.Color
		atm.Decay = if x then rgb(x.decai) else base.atmDecai or atm.Decay
		atm.Offset = if x then x.deslocamento else base.atmDesloc or atm.Offset
	end
	local bl = Lighting:FindFirstChildOfClass("BloomEffect")
	local vb = h.luz.bloom or base.bloom
	if bl and vb then
		bl.Intensity, bl.Size, bl.Threshold = vb.i, vb.s, vb.t
	end
	local sr = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local vr = h.luz.raios or base.raios
	if sr and vr then
		sr.Intensity, sr.Spread = vr.i, vr.s
	end
	relogioParado = h.parado == true
	Lighting.Brightness = base.brilho * h.luz.brilho
	Lighting.ExposureCompensation = base.expo + h.luz.exposicao
	-- a cor do horário num efeito próprio (soma com o ColorCorrection do jogo, sem mexer nele)
	local achado = Lighting:FindFirstChild("VT65Hora")
	local cc: ColorCorrectionEffect = if achado and achado:IsA("ColorCorrectionEffect")
		then achado
		else Instance.new("ColorCorrectionEffect")
	cc.Name = "VT65Hora"
	cc.TintColor = Color3.fromRGB(h.luz.tinta[1], h.luz.tinta[2], h.luz.tinta[3])
	cc.Saturation = h.luz.saturacao
	cc.Contrast = h.luz.contraste or 0
	cc.Parent = Lighting
	ReplicatedStorage:SetAttribute("VT65Hora", h.id)
	LightingService.setStart(h.hora)
end

function LightingService.start()
	ReplicatedStorage:GetAttributeChangedSignal("Rain"):Connect(applyAtmosphere)
	LightingService.aplicarHorario(Horarios.PADRAO)
	-- D-224 (só no Studio): workspace "VT65DevHora" = "manha" | "meiodia" | "tarde" | "noite"
	if game:GetService("RunService"):IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevHora"):Connect(function()
			local v = workspace:GetAttribute("VT65DevHora")
			if type(v) == "string" then
				LightingService.aplicarHorario(v)
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(15)
			LightingService.update()
		end
	end)
end

return LightingService
