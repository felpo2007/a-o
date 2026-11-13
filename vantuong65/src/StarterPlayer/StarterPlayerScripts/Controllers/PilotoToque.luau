--!strict
-- Veículos no toque (Parte 13, T3): a parte pura, testada no Lune (tests/luau/toque_veiculo.luau).
-- Sem `game` nem `script`. O VehicleController e o ToqueVeiculo.client usam a mesma tabela
-- `PilotoToque.lever` (a alavanca do coletivo na tela): a tela escreve o que o polegar faz, o
-- controlador lê, aplica e devolve o coletivo de verdade para a alavanca acompanhar.
--   - motorista: o analógico flutuante da esquerda (Input.move) dirige: frente acelera, trás freia e,
--     parado, dá ré (a mesma leitura do LT no VehicleDrive); o volante tem a curva do controle;
--   - piloto do UH-34D: analógico esquerdo = cíclico; alavanca vertical à direita = coletivo (de
--     posição, como a de verdade: o polegar arrasta a alavanca de onde ela está, sem salto); botões
--     de pedal = guinada; o estabilizador (assistência, não piloto automático) liga ao assumir os
--     comandos no toque;
--   - botões: tamanho físico (mm) convertido para px da interface; nada na metade do analógico.
local PilotoToque = {}

-- ===== tamanho físico (mm) =====
-- Mínimo de toque ≈ 9 mm (44 pt / 48 dp); tiro ≈ 16 mm (contrato da Parte 13).
PilotoToque.MM = {
	min = 9, -- lugar, sair, munição, estabilizador
	mid = 11, -- coaxial, ótica, binóculo, marcar, pedais
	fire = 16, -- tiro principal / porta
	leverW = 13,
	leverMin = 22, -- curso mínimo da alavanca
	leverMax = 40,
	margin = 4,
	gap = 2.5,
	tightMargin = 2, -- tela baixa: primeiro aperta as margens, só depois encolhe os botões
	tightGap = 1.5,
}

-- Pontos (px da interface do Roblox) por polegada. No celular a interface do Roblox trabalha em
-- pontos (iOS ~163 pt/pol, Android 160 dp/pol); no tablet o ponto é maior na mão (~132 pt/pol no
-- iPad). O mesmo palpite do Shared/Toque.rawPx (T1), que o runtime usa quando existe; este é a
-- reserva e o que o teste usa.
function PilotoToque.dpiGuess(shortSidePx: number): number
	return if shortSidePx >= 600 then 132 else 160
end

function PilotoToque.mmToPx(mm: number, shortSidePx: number): number
	return math.floor(mm / 25.4 * PilotoToque.dpiGuess(shortSidePx) + 0.5)
end

-- ===== motorista =====
PilotoToque.PURE_STEER_DEG = 12 -- polegar quase de lado: só gira/esterça, sem arrancar
PilotoToque.PURE_THROTTLE_DEG = 8 -- polegar quase reto: só acelera/freia, sem puxar o volante

-- Analógico virtual já com a zona morta (Input.move: x direita, y para cima, −1..1) → acelerador
-- (+ frente, − freio/ré) e volante (+ direita), com a curva do controle (mais fino no centro).
function PilotoToque.drive(x: number, y: number, wheeled: boolean): (number, number)
	local m = math.sqrt(x * x + y * y)
	if m < 1e-4 then
		return 0, 0
	end
	local throttle = math.clamp(y, -1, 1)
	local steer = math.sign(x) * math.abs(math.clamp(x, -1, 1)) ^ (if wheeled then 1.2 else 1.4)
	local fromSide = math.deg(math.asin(math.clamp(math.abs(y) / m, 0, 1))) -- 0 = de lado, 90 = reto
	if fromSide < PilotoToque.PURE_STEER_DEG then
		throttle = 0
	elseif fromSide > 90 - PilotoToque.PURE_THROTTLE_DEG then
		steer = 0
	end
	return throttle, steer
end

-- ===== piloto: alavanca do coletivo =====
export type Lever = {
	held: boolean, -- o polegar está na alavanca
	value: number, -- posição 0..1 (com o polegar: o comando; sem: acompanha o coletivo real)
	grabY: number,
	grabV: number,
	hover: number?, -- coletivo que paira agora (marca na alavanca), do VehicleController
	assist: boolean, -- estabilizador ligado (o botão acende), do VehicleController
}

function PilotoToque.newLever(): Lever
	return { held = false, value = 0.55, grabY = 0, grabV = 0.55, hover = nil, assist = true }
end

-- a alavanca da tela (uma só no cliente)
PilotoToque.lever = PilotoToque.newLever()

-- o polegar pega a alavanca onde ela está (current = coletivo real): nada salta
function PilotoToque.grab(L: Lever, y: number, current: number)
	L.held = true
	L.value = math.clamp(current, 0, 1)
	L.grabY = y
	L.grabV = L.value
end

-- arrasto: o curso inteiro da alavanca (trackPx) vale o coletivo inteiro; para cima sobe
function PilotoToque.drag(L: Lever, y: number, trackPx: number)
	if not L.held then
		return
	end
	L.value = math.clamp(L.grabV + (L.grabY - y) / math.max(trackPx, 1), 0, 1)
end

function PilotoToque.release(L: Lever)
	L.held = false
end

-- sem o polegar, a alavanca mostra o coletivo real (o estabilizador mexe nele)
function PilotoToque.follow(L: Lever, collective: number)
	if not L.held then
		L.value = math.clamp(collective, 0, 1)
	end
end

-- comando da alavanca: a posição se o polegar está nela, nil se não
function PilotoToque.command(L: Lever): number?
	return if L.held then L.value else nil
end

-- ===== coletivo (vale para todos os aparelhos; o VehicleController chama) =====
PilotoToque.COLLECTIVE_RATE = 0.35 -- por segundo com gatilho ou tecla (D-61)
PilotoToque.HOVER_TAU_K = 0.8 -- o estabilizador leva o coletivo ao pairado em ~1,2 s
PilotoToque.GROUND_MARGIN = 0.05 -- no chão, sem comando, fica logo abaixo do pairado

-- Antes do modelo: gatilho/tecla somam com taxa; a alavanca do toque dá a posição direto.
function PilotoToque.collectiveInput(c: number, up: number, lever: number?, dt: number): number
	if lever then
		return math.clamp(lever, 0, 1)
	end
	return math.clamp(c + up * PilotoToque.COLLECTIVE_RATE * dt, 0, 1)
end

-- Depois do modelo: o estabilizador (assistência, não piloto automático) só age quando o piloto não
-- está comandando o coletivo (manual = gatilho/tecla apertado ou polegar na alavanca). No ar, leva
-- ao pairado; no chão, fica logo abaixo dele (só sai do chão com comando). Sem estabilizador ou sem
-- potência para medir o pairado (hover nil), o coletivo fica onde o piloto deixou.
function PilotoToque.collectiveAssist(
	c: number,
	manual: boolean,
	assist: boolean,
	hover: number?,
	onGround: boolean,
	dt: number
): number
	if not assist or manual or hover == nil then
		return c
	end
	local h = hover :: number
	if onGround then
		return math.min(c, math.max(h - PilotoToque.GROUND_MARGIN, 0))
	end
	return c + (h - c) * math.min(1, dt * PilotoToque.HOVER_TAU_K)
end

-- pedais: +1 direito, −1 esquerdo, os dois juntos se anulam
function PilotoToque.pedal(left: boolean, right: boolean): number
	return (if right then 1 else 0) - (if left then 1 else 0)
end

-- Estabilizador ao assumir os comandos: no toque sempre ligado (o polegar no analógico flutuante
-- não segura o pairado sozinho); no controle e no teclado fica a escolha da sessão (D-100: o padrão
-- já é ligado).
function PilotoToque.assistOnEnter(current: boolean, touch: boolean): boolean
	return if touch then true else current
end

-- ===== disposição dos botões (paisagem, dois polegares) =====
-- Retângulos em px da interface, origem no canto de cima à esquerda da área segura. Tudo à direita
-- (a metade esquerda é do analógico flutuante); mirror espelha para canhotos (touchMirror do T1).
export type Rect = { x: number, y: number, w: number, h: number }
export type Opts = {
	fire: boolean, -- tem tiro (atirador com arma, porta)
	coax: boolean, -- coaxial (canhão de 90 mm)
	optic: boolean, -- ótica / zoom
	ammo: boolean, -- trocar munição / recarregar
	mirror: boolean,
	avoid: Rect?, -- botão de outro HUD no alto à direita (o rádio do HUD de toque do T1), px sem espelho
}

-- Quanto do canto de cima à direita fica livre para um botão de outro HUD (avoid, em px, sem
-- espelho): só se ele estiver na faixa de cima (até bandBottom).
function PilotoToque.topReserve(avoid: Rect?, W: number, bandBottom: number, gap: number): number
	if not avoid or avoid.y >= bandBottom or avoid.x + avoid.w <= W / 2 then
		return 0
	end
	return math.max(0, math.ceil(W - avoid.x + gap))
end

-- role: "driver" | "gunner" | "commander" | "door" | "pilot" | "passenger"
function PilotoToque.layout(role: string, W: number, H: number, o: Opts, px: (mm: number) -> number): { [string]: Rect }
	local MM = PilotoToque.MM
	-- altura da coluna da direita (mm) com estas margens
	local function need(margin: number, gap: number): number
		return if role == "pilot"
			then 2 * margin + MM.min + 2 * gap + MM.leverMin
			elseif role == "gunner" or role == "door" or role == "commander" then 2 * margin
				+ MM.min
				+ 2 * gap
				+ MM.mid
				+ MM.fire
			else 2 * margin + MM.min
	end
	-- não cabe: primeiro margens apertadas; ainda não cabe, tudo encolhe por igual (até 70%)
	local margin, gap = MM.margin, MM.gap
	if px(need(margin, gap)) > H then
		margin, gap = MM.tightMargin, MM.tightGap
	end
	local k = math.clamp(H / math.max(px(need(margin, gap)), 1), 0.7, 1)
	local function s(mm: number): number
		return math.floor(px(mm) * k + 0.5)
	end
	local m, g = s(margin), s(gap)
	local S, C, F = s(MM.min), s(MM.mid), s(MM.fire)
	local out: { [string]: Rect } = {}
	-- todos: sair no alto à direita (à esquerda do rádio do T1, se houver), lugares à esquerda dele
	local avoid = o.avoid
	local right = math.max(m, PilotoToque.topReserve(avoid, W, m + S + g, g))
	out.exit = { x = W - right - S, y = m, w = S, h = S }
	out.seat = { x = W - right - 2 * S - g, y = m, w = S, h = S }
	if role == "pilot" then
		local LW = s(MM.leverW)
		local y0 = m + S + 2 * g
		-- o rádio do T1 desce mais no tablet (9% da altura): a alavanca começa abaixo dele
		if avoid and avoid.x + avoid.w > W - m - LW - g then
			y0 = math.max(y0, avoid.y + avoid.h + 2 * g)
		end
		local LH = math.min(s(MM.leverMax), H - m - y0)
		out.lever = { x = W - m - LW, y = y0, w = LW, h = LH }
		-- rótulo "COLETIVO" no vão logo acima da alavanca
		out.leverLabel = { x = W - m - LW - g, y = y0 - math.floor(g * 1.75), w = LW + 2 * g, h = math.floor(g * 1.5) }
		local pr = { x = W - m - LW - g - C, y = H - m - C, w = C, h = C }
		out.pedalR = pr
		out.pedalL = { x = pr.x - g - C, y = pr.y, w = C, h = C }
		out.stab = { x = pr.x + C - S, y = pr.y - g - S, w = S, h = S }
	elseif role == "gunner" or role == "door" or role == "commander" then
		local fire = { x = W - m - F, y = H - m - F, w = F, h = F }
		local side = { x = fire.x - g - C, y = H - m - C, w = C, h = C } -- à esquerda do tiro
		local top = { x = W - m - C, y = fire.y - g - C, w = C, h = C } -- em cima do tiro
		if role == "commander" then
			out.binoc = top
			out.mark = side
		else
			if o.fire then
				out.fire = fire
			end
			if o.optic then
				out.optic = top
			end
			if o.coax and role == "gunner" then
				out.coax = side
			end
			if o.ammo and role == "gunner" then
				-- na diagonal de cima à esquerda, entre a coaxial e a ótica
				out.ammo = { x = side.x + C - S, y = top.y + C - S, w = S, h = S }
			end
		end
	end
	if o.mirror then
		for _, r in out do
			r.x = W - r.x - r.w
		end
	end
	return out
end

-- dois retângulos se encostam?
function PilotoToque.overlap(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return PilotoToque
