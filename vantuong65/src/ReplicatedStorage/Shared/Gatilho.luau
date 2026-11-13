--!strict
-- Gatilho (2026-11-12). Pedido do dono depois de jogar: "as armas não estão automáticas", "algumas
-- armas não estão atirando", "conserte as armas bugadas". A regra do disparo fica aqui, pura (testada
-- no Lune, tests/luau/armas.luau), e vale dos dois lados:
--   - cliente (WeaponController): quando sai o tiro. Semi, tiro único e ferrolho: um tiro por
--     aperto; o toque que cai no intervalo espera até BUFFER_S e sai assim que pode (antes era
--     perdido: clicar rápido na SKS "não atirava"). Automático: segurou, sai na cadência cíclica,
--     com o tempo acumulado (a 60 quadros por segundo a M60 não perde tiro por arredondamento).
--     Sem munição: um clique por aperto;
--   - servidor (CombatService): o tiro vale? Modo do papel, munição, recarga, cadência por balde de
--     créditos no relógio do tiro (t, hora do servidor vista pelo cliente; antes era a hora de
--     chegada, e o tremor da rede derrubava tiros da rajada), origem perto da cabeça e, sentado, só
--     no lugar aberto e dentro do ângulo (Vehicles.inArc, com folga).
local Weapons = require(script and (script :: any).Parent.Weapons or "./Weapons") :: any

local Gatilho = {}

Gatilho.BUFFER_S = 0.25 -- toque guardado enquanto a arma não pode atirar (semi/ferrolho)
Gatilho.CATCHUP_S = 1 / 30 -- automático: atraso de até um quadro a 30 fps não perde cadência
Gatilho.MAX_LAG = 0.25 -- D-25: defasagem aceita do relógio do tiro (o tiro velho não é recusado:
-- o relógio é preso nesta janela, a cadência continua garantida)
Gatilho.TOLERANCE = 0.15 -- folga da cadência (D-25: 85% do intervalo)
Gatilho.BURST = 2 -- automático: créditos guardados (um quadro de tremor entre dois tiros)
Gatilho.ORIGIN_STUDS = 8 -- D-25: origem a até 8 studs da cabeça
Gatilho.ARC_SLACK_DEG = 8 -- folga do ângulo do lugar (o veículo mexe entre o cliente e o servidor)

-- ===== cliente =====
export type Trigger = {
	weapon: string,
	mode: string,
	mag: number,
	held: boolean,
	queued: number, -- até quando um toque espera para sair (0 = nenhum)
	last: number, -- hora do último tiro (relógio do cliente)
	reloadUntil: number,
	dryDone: boolean, -- já clicou neste aperto
}

function Gatilho.new(weaponId: string, mode: string, mag: number): Trigger
	return {
		weapon = weaponId,
		mode = mode,
		mag = mag,
		held = false,
		queued = 0,
		last = -math.huge,
		reloadUntil = 0,
		dryDone = false,
	}
end

function Gatilho.press(t: Trigger, now: number)
	t.held = true
	t.dryDone = false
	if t.mode ~= "auto" then
		t.queued = now + Gatilho.BUFFER_S
	end
end

function Gatilho.release(t: Trigger, _now: number)
	t.held = false
end

-- soltar tudo (troca de arma, menu, morte): nada fica preso nem guardado
function Gatilho.cancel(t: Trigger)
	t.held = false
	t.queued = 0
end

-- O jogador quer atirar agora? (gatilho apertado no automático ou toque guardado)
function Gatilho.wants(t: Trigger, now: number): boolean
	return (t.mode == "auto" and t.held) or (t.queued > 0 and now <= t.queued)
end

-- Ferrolho ainda manobrando (para a animação e para o aviso)
function Gatilho.cycling(t: Trigger, now: number): boolean
	local wp = Weapons.get(t.weapon)
	return t.mode == "bolt" and wp ~= nil and now - t.last < Weapons.interval(wp, "bolt")
end

-- Passo do quadro: "fire" (sai um tiro: o chamador manda ao servidor), "dry" (clique sem munição)
-- ou nil.
function Gatilho.step(t: Trigger, now: number): string?
	if t.queued > 0 and now > t.queued then
		t.queued = 0 -- o toque venceu sem sair (recarregando, ferrolho)
	end
	if not Gatilho.wants(t, now) or now < t.reloadUntil then
		return nil
	end
	local wp = Weapons.get(t.weapon)
	if not wp then
		return nil
	end
	if t.mag <= 0 then
		t.queued = 0
		if not t.dryDone then
			t.dryDone = true
			return "dry"
		end
		return nil
	end
	local iv = Weapons.interval(wp, t.mode)
	local since = now - t.last
	if since < iv - 1e-6 then
		return nil
	end
	t.queued = 0
	-- automático: a próxima conta a partir da hora em que este tiro deveria ter saído
	t.last = if t.mode == "auto" and since < iv + Gatilho.CATCHUP_S then t.last + iv else now
	t.mag -= 1
	return "fire"
end

-- ===== servidor =====
-- Balde de créditos por arma: cada tiro gasta 1; o tempo devolve 1 a cada intervalo do modo.
export type Gate = { last: number, credit: number }

function Gatilho.newGate(): Gate
	return { last = -math.huge, credit = Gatilho.BURST }
end

-- Relógio do tiro preso na janela aceita (o cliente não adianta nem atrasa além dela)
function Gatilho.clampTime(t: number, now: number): number
	return math.clamp(t, now - Gatilho.MAX_LAG, now + 0.05)
end

-- Cadência: devolve true e gasta o crédito, ou false (rápido demais para a arma no modo).
function Gatilho.accept(g: Gate, wp: any, mode: string, t: number): boolean
	local iv = Weapons.interval(wp, mode)
	local cap = if mode == "auto" then Gatilho.BURST else 1
	local dt = if g.last == -math.huge then math.huge else math.max(t - g.last, 0)
	local credit = math.min(cap, g.credit + dt / iv)
	if credit < 1 - Gatilho.TOLERANCE then
		return false
	end
	g.credit = credit - 1
	g.last = math.max(g.last, t)
	return true
end

-- Lugar de veículo (D-100, contrato do VehicleService): atributos do assento lidos pelo chamador.
export type SeatInfo = {
	personal: boolean, -- "Personal": a própria arma do ocupante
	weapon: string?, -- "Weapon" do assento
	arc: { yaw: number, half: number, down: number, up: number }?, -- "ArcYaw/ArcHalf/ArcDown/ArcUp"
	relYawDeg: number, -- rumo do tiro menos o rumo do veículo (+ esquerda)
	pitchDeg: number, -- inclinação do tiro (+ para cima)
	turnDegS: number?, -- giro do veículo agora (graus/s): a folga cresce com ele (latência)
}

-- Folga do ângulo do lugar: fixa + o quanto o veículo gira dentro da janela de defasagem aceita
function Gatilho.arcSlack(turnDegS: number?): number
	return Gatilho.ARC_SLACK_DEG + math.abs(turnDegS or 0) * Gatilho.MAX_LAG
end

-- Mesma conta de Vehicles.inArc, com folga
function Gatilho.inArc(
	arc: { yaw: number, half: number, down: number, up: number },
	rel: number,
	pitch: number,
	slack: number
): boolean
	local d = (rel - arc.yaw + 180) % 360 - 180
	return math.abs(d) <= arc.half + slack and pitch >= arc.down - slack and pitch <= arc.up + slack
end

export type Shot = {
	weapon: string,
	mode: string,
	role: string?,
	t: number, -- relógio do tiro (servidor, visto pelo cliente)
	now: number, -- hora do servidor na chegada
	clock: number, -- os.clock do servidor (recarga)
	originStuds: number, -- distância da origem à cabeça
	seat: SeatInfo?,
}
export type Rec = { weapon: string, mag: number, spare: number, reloadUntil: number, gate: Gate }

-- O tiro vale? (true) ou (false, motivo). Gasta o crédito de cadência quando vale; a munição é
-- descontada pelo chamador.
function Gatilho.validate(rec: Rec, s: Shot): (boolean, string?)
	local wp = Weapons.get(s.weapon)
	if not wp or not wp.enabled or rec.weapon ~= s.weapon then
		return false, "arma"
	end
	if not Weapons.modeAllowed(wp, s.mode, s.role) then
		return false, "modo"
	end
	if rec.mag <= 0 then
		return false, "sem munição"
	end
	if s.clock < rec.reloadUntil then
		return false, "recarregando"
	end
	if s.originStuds > Gatilho.ORIGIN_STUDS then
		return false, "origem"
	end
	local seat = s.seat
	if seat then
		if not seat.personal or seat.weapon ~= s.weapon then
			return false, "lugar fechado"
		end
		local arc = seat.arc
		if not arc or not Gatilho.inArc(arc, seat.relYawDeg, seat.pitchDeg, Gatilho.arcSlack(seat.turnDegS)) then
			return false, "fora do ângulo"
		end
	end
	if not Gatilho.accept(rec.gate, wp, s.mode, Gatilho.clampTime(s.t, s.now)) then
		return false, "cadência"
	end
	return true, nil
end

return Gatilho
