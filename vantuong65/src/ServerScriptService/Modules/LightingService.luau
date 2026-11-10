--!strict
-- Sol real de 18/08/1965 em Vạn Tường (Parte 9.6): calcula a direção real (SolarPosition) e ajusta
-- ClockTime e GeographicLatitude para o Roblox reproduzi-la. O tempo corre em tempo real.
-- Névoa matinal que se dissipa entre 06:30 e 07:30.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SolarPosition = require(ReplicatedStorage.Shared.SolarPosition)

local LightingService = {}
LightingService.DATE = { 1965, 8, 18 }
LightingService.TZ = 8 -- hora de Saigon em 1965 (UTC+8) — confirmar (DESIGN D-27)
LightingService.LAT, LightingService.LON = 15.30, 108.85

local startHour = 6.5
local t0 = os.clock()
local lastC, lastL = 6.5, 15

function LightingService.setStart(hour: number)
	startHour = hour
	t0 = os.clock()
	lastC, lastL = hour, 15
	LightingService.update()
end

function LightingService.hourNow(): number
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
	local c, l, errDeg = SolarPosition.fit(tx, ty, tz, getDir, lastC, lastL)
	Lighting.ClockTime = c
	Lighting.GeographicLatitude = l
	lastC, lastL = c, l
	ReplicatedStorage:SetAttribute("SunAzimuth", az)
	ReplicatedStorage:SetAttribute("SunElevation", el)
	ReplicatedStorage:SetAttribute("SunFitErrorDeg", errDeg)
	-- névoa matinal: mais densa ao amanhecer, dissipa em 1 h (Parte 9.6)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		local k = math.clamp((hour - 6.5) / 1.0, 0, 1)
		atm.Density = 0.45 - 0.10 * k
		atm.Haze = 2.5 - 0.9 * k
	end
end

function LightingService.start()
	LightingService.setStart(6.5)
	task.spawn(function()
		while true do
			task.wait(15)
			LightingService.update()
		end
	end)
end

return LightingService
