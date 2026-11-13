--!strict
-- Reforços (plano de volta diária, 2026-11-12, seções 1 e 3): XP dobrado e créditos dobrados por
-- tempo (comprados em Robux ou ganhos no passe e no Pacote de Recruta) e o XP dobrado de fim de
-- semana, para todos (sexta 18h a domingo 23h59, horário de Brasília). A hora de fim fica no perfil
-- (campaign.boosts): sobrevive à troca de servidor e à saída do jogo (o relógio corre igual).
-- Os bônus SOMAM (não multiplicam): 1 + reforço de XP (1) + fim de semana (1) + amigo no squad
-- (0,10) = até 3,1x de XP; créditos: 1 + reforço (1) + Veterano (0,10) = até 2,1x.
-- Puro, testado no Lune (tests/luau/campanha.luau).
local Calendario = require(script and (script :: any).Parent.Calendario or "./Calendario") :: any

local Reforcos = {}

Reforcos.BRT = -3 -- Brasília (sem horário de verão desde 2019)
Reforcos.FRIEND_XP = 0.10 -- amigo no mesmo squad
Reforcos.MAX_SECONDS = 30 * 86400 -- teto de tempo acumulado de cada reforço

export type Boosts = { xpUntil: number, crUntil: number }

-- fim de semana de XP dobrado: sexta 18:00 até domingo 23:59:59 (Brasília). Devolve se vale agora e
-- quando acaba (segunda 00:00 de Brasília, em UTC)
function Reforcos.weekend(t: number): (boolean, number?)
	local wd = Calendario.weekday(t, Reforcos.BRT)
	local localT = t + Reforcos.BRT * 3600
	local sec = localT % Calendario.DAY
	local on = (wd == 5 and sec >= 18 * 3600) or wd == 6 or wd == 0
	if not on then
		return false, nil
	end
	local daysToMonday = (8 - wd) % 7
	if daysToMonday == 0 then
		daysToMonday = 7
	end
	local mondayLocal = (math.floor(localT / Calendario.DAY) + daysToMonday) * Calendario.DAY
	return true, mondayLocal - Reforcos.BRT * 3600
end

-- estende um reforço: soma ao fim atual (ou a partir de agora, se já acabou)
function Reforcos.extend(b: Boosts, kind: string, seconds: number, now: number)
	local s = math.max(0, math.floor(seconds))
	if kind == "xp" then
		b.xpUntil = math.min(math.max(b.xpUntil, now) + s, now + Reforcos.MAX_SECONDS)
	elseif kind == "cr" then
		b.crUntil = math.min(math.max(b.crUntil, now) + s, now + Reforcos.MAX_SECONDS)
	end
end

-- multiplicadores efetivos agora
function Reforcos.mult(b: Boosts, now: number, veteran: boolean, friendInSquad: boolean): (number, number)
	local xp = 1
	if b.xpUntil > now then
		xp += 1
	end
	if Reforcos.weekend(now) then
		xp += 1
	end
	if friendInSquad then
		xp += Reforcos.FRIEND_XP
	end
	local cr = 1
	if b.crUntil > now then
		cr += 1
	end
	if veteran then
		cr += 0.10
	end
	return xp, cr
end

function Reforcos.sanitize(raw: any): Boosts
	local b: Boosts = { xpUntil = 0, crUntil = 0 }
	if type(raw) == "table" then
		local x, c = tonumber(raw.xpUntil), tonumber(raw.crUntil)
		b.xpUntil = if x and x == x and x > 0 then math.floor(x) else 0
		b.crUntil = if c and c == c and c > 0 then math.floor(c) else 0
	end
	return b
end

return Reforcos
