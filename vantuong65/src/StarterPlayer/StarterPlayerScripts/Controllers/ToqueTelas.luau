--!strict
-- Toque nas telas e nas ações complexas (Parte 13, T2): a lógica pura, sem serviço do Roblox,
-- testada no Lune (tests/luau/toque_telas.luau). Quem desenha e liga é o ToqueUi, o Interagir, o
-- ObraToque, o HudCampo, a CartaView e as telas.
--   - dedo gordo: o alvo de cada botão cresce até o mínimo de toque (sem mexer no desenho);
--   - toque x arrasto, pinça do mapa, ponto mais perto do dedo, 2º toque que confirma;
--   - qual interação o botão contextual faz (prompt do mundo ou companheiro ferido);
--   - onde a construção fica (a mesma conta do servidor) e as opções do seletor de tiro;
--   - o retângulo de tela cheia do mapa e o texto do botão de inserir.
local ToqueTelas = {}

-- Mínimo de toque enquanto o Shared/Toque (T1) não existir: 48 px na escala da interface do Roblox
-- no celular (≈ 44 pt / 48 dp, ~9 mm). O tiro é maior (~16 mm).
ToqueTelas.MIN_PX = 48
ToqueTelas.FIRE_PX = 84
ToqueTelas.TAP_S = 0.35 -- toque curto: até isto segurando
ToqueTelas.TAP_MOVE_PX = 14 -- e andando até isto (mais é arrasto)
ToqueTelas.SECOND_TAP_S = 4 -- o 2º toque no mesmo item confirma dentro deste tempo

-- ===== dedo gordo =====
-- Retângulo aumentado até o mínimo, sem sair do centro (o que já é grande fica como está).
function ToqueTelas.expand(
	x: number,
	y: number,
	w: number,
	h: number,
	minW: number,
	minH: number
): (number, number, number, number)
	local w2, h2 = math.max(w, minW), math.max(h, minH)
	return x - (w2 - w) / 2, y - (h2 - h) / 2, w2, h2
end

-- Distância do ponto até o retângulo (0 dentro).
function ToqueTelas.rectDist(px: number, py: number, x: number, y: number, w: number, h: number): number
	local dx = math.max(x - px, 0, px - (x + w))
	local dy = math.max(y - py, 0, py - (y + h))
	return math.sqrt(dx * dx + dy * dy)
end

export type Rect = { id: any, x: number, y: number, w: number, h: number }

-- O botão que o dedo quis: o retângulo AUMENTADO precisa conter o ponto; entre vários, o mais perto
-- do retângulo de verdade e, empatando, o menor (o botão pequeno ao lado do grande).
function ToqueTelas.pick(px: number, py: number, rects: { Rect }, minPx: number): any?
	local best: Rect? = nil
	local bestD, bestA = math.huge, math.huge
	for _, r in rects do
		if r.w <= 0 or r.h <= 0 then
			continue
		end
		local ex, ey, ew, eh = ToqueTelas.expand(r.x, r.y, r.w, r.h, minPx, minPx)
		if px >= ex and px <= ex + ew and py >= ey and py <= ey + eh then
			local d = ToqueTelas.rectDist(px, py, r.x, r.y, r.w, r.h)
			local a = r.w * r.h
			if d < bestD - 1e-6 or (math.abs(d - bestD) <= 1e-6 and a < bestA) then
				best, bestD, bestA = r, d, a
			end
		end
	end
	return if best then best.id else nil
end

-- Toque curto e parado (o resto é arrasto ou segurar).
function ToqueTelas.isTap(seconds: number, dx: number, dy: number): boolean
	return seconds <= ToqueTelas.TAP_S and math.sqrt(dx * dx + dy * dy) <= ToqueTelas.TAP_MOVE_PX
end

-- ===== mapa =====
-- Pinça: o zoom acompanha a razão entre a distância dos dedos agora e no começo.
function ToqueTelas.pinch(z0: number, d0: number, d1: number, zmin: number, zmax: number): number
	if d0 <= 1 then
		return math.clamp(z0, zmin, zmax)
	end
	return math.clamp(z0 * d1 / d0, zmin, zmax)
end

export type Point = { id: any, x: number, y: number }

-- Ponto mais perto do dedo dentro do raio (mesmas unidades dos pontos), ou nil.
function ToqueTelas.nearest(px: number, py: number, pts: { Point }, radius: number): Point?
	local best: Point? = nil
	local bestD = radius
	for _, p in pts do
		local d = math.sqrt((p.x - px) ^ 2 + (p.y - py) ^ 2)
		if d <= bestD then
			best, bestD = p, d
		end
	end
	return best
end

-- Retângulo (unidades de projeto do palco) que cobre a tela inteira: o palco de dw x dh fica no
-- meio da tela, escalado por k. top: a faixa de cima (botões do Roblox) em px; margin em px.
function ToqueTelas.fullRect(
	vpW: number,
	vpH: number,
	k: number,
	dw: number,
	dh: number,
	top: number,
	margin: number
): (number, number, number, number)
	local kk = math.max(k, 0.05)
	local ox, oy = vpW / 2 - dw * kk / 2, vpH / 2 - dh * kk / 2 -- canto do palco na tela
	local sx, sy = margin, math.max(top, margin)
	local sw, sh = math.max(vpW - 2 * margin, 10), math.max(vpH - sy - margin, 10)
	return (sx - ox) / kk, (sy - oy) / kk, sw / kk, sh / kk
end

-- Botão de inserir no toque: o texto grande, a linha de baixo e se está pronto.
export type SpawnButton = { text: string, sub: string, ready: boolean }
function ToqueTelas.spawnButton(pt: any): SpawnButton
	if type(pt) ~= "table" then
		return { text = "TOQUE NUM PONTO", sub = "", ready = false }
	end
	local name = if type(pt.name) == "string" then pt.name else ""
	if pt.blocked then
		return { text = "BLOQUEADO", sub = if type(pt.why) == "string" then pt.why else name, ready = false }
	elseif type(pt.wait) == "number" and pt.wait > 0 then
		return { text = string.format("ESPERA %d s", math.ceil(pt.wait)), sub = name, ready = false }
	elseif pt.ready == false then
		return { text = "ESPERE", sub = if type(pt.why) == "string" then pt.why else name, ready = false }
	end
	return { text = "INSERIR", sub = name, ready = true }
end

-- ===== 2º toque confirma =====
-- 1º toque num item: mostra (devolve false e guarda); 2º toque no MESMO item a tempo: confirma.
export type Tap2 = { id: string?, t: number }
function ToqueTelas.newTap2(): Tap2
	return { id = nil, t = -math.huge }
end
function ToqueTelas.secondTap(st: Tap2, id: string, now: number): boolean
	if st.id == id and now - st.t <= ToqueTelas.SECOND_TAP_S then
		st.id, st.t = nil, -math.huge
		return true
	end
	st.id, st.t = id, now
	return false
end

-- ===== interagir =====
export type PromptInfo = {
	key: any, -- o próprio ProximityPrompt
	dist: number, -- studs até o personagem
	hold: number, -- HoldDuration
	text: string, -- ActionText
	vehicle: boolean, -- "VT65Embarcar"
}
export type AllyInfo = { downed: boolean, hurt: boolean }
export type Choice = { kind: string, key: any, label: string, glyph: string, hold: number, op: string? }

-- O que o botão contextual faz agora. Como no PC (MedicalController): havendo interação do mundo
-- (prompt) na tela, ela vence; senão, o companheiro perto que dá para ajudar. Nada útil: nil (o
-- botão some). Reanimar e tratar são do médico; o curativo em outro gasta um dos seus.
function ToqueTelas.chooseInteraction(
	prompts: { PromptInfo },
	ally: AllyInfo?,
	isMedic: boolean,
	bandages: number
): Choice?
	local best: PromptInfo? = nil
	for _, p in prompts do
		if not best or p.dist < best.dist then
			best = p
		end
	end
	if best then
		local label = if best.vehicle then "ENTRAR" elseif best.text ~= "" then best.text else "INTERAGIR"
		return {
			kind = "prompt",
			key = best.key,
			label = label,
			glyph = if best.vehicle then "►" else "◉",
			hold = math.max(best.hold, 0),
			op = nil,
		}
	end
	if ally then
		if ally.downed then
			if isMedic then
				return { kind = "ally", key = nil, label = "REANIMAR", glyph = "+", hold = 0, op = "revive" }
			end
			return nil -- caído só o médico levanta (o servidor recusa o resto)
		elseif ally.hurt then
			if isMedic then
				return { kind = "ally", key = nil, label = "TRATAR", glyph = "+", hold = 0, op = "treat" }
			elseif bandages > 0 then
				return { kind = "ally", key = nil, label = "CURATIVO", glyph = "+", hold = 0, op = "bandage" }
			end
		end
	end
	return nil
end

-- Fração do anel (0..1) de uma ação que começou em t0 e dura dur s.
function ToqueTelas.progress(t0: number, dur: number, now: number): number
	if dur <= 0 then
		return 1
	end
	return math.clamp((now - t0) / dur, 0, 1)
end

-- Quantos segmentos do anel acendem (n segmentos).
function ToqueTelas.ringLit(frac: number, n: number): number
	return math.clamp(math.floor(frac * n + 1e-6), 0, n)
end

-- Centro do botão contextual (px) quando o Shared/Toque não diz: à direita, acima do tiro.
-- O tiro fica no canto de baixo à direita (centro a margin + fire/2 das bordas).
function ToqueTelas.interactSlot(vpW: number, vpH: number, fire: number, size: number, margin: number): (number, number)
	local fx = vpW - margin - fire / 2
	local fy = vpH - margin - fire / 2
	return fx - fire * 0.15, fy - fire / 2 - margin - size / 2
end

-- ===== faixa livre no alto (HUD de campo no toque) =====
-- Os botões do HUD de toque (T1) ocupam os cantos de cima (mapa, menu, câmera, canal à esquerda;
-- comunicar, marcar, rádio à direita). A faixa do meio, entre eles, é da faixa da frente, da bússola
-- e do cartão da arma. rects: botões visíveis (px); x0..x1 = área toda; topY = até onde um botão
-- conta como "do alto" (centro acima disto). Devolve o vão livre (x0, x1) e a base dos botões do alto
-- (y abaixo da qual o resto pode descer sem cobrir nenhum deles).
function ToqueTelas.topBand(rects: { Rect }, x0: number, x1: number, topY: number): (number, number, number)
	local mid = (x0 + x1) / 2
	local left, right, base = x0, x1, 0
	for _, r in rects do
		local cx, cy = r.x + r.w / 2, r.y + r.h / 2
		if cy <= topY then
			if cx < mid then
				left = math.max(left, r.x + r.w)
			else
				right = math.min(right, r.x)
			end
			base = math.max(base, r.y + r.h)
		end
	end
	if right - left < 40 then
		return x0, x1, base -- nada cabe entre eles: a faixa inteira (o resto se vira com a escala)
	end
	return left, right, base
end

-- Escala para um quadro de largura w caber num vão (nunca cresce; piso para continuar legível).
function ToqueTelas.fitScale(w: number, gap: number, maxK: number, minK: number): number
	if w <= 0 then
		return maxK
	end
	return math.clamp(gap / w, minK, maxK)
end

-- ===== construção (pá e obras) =====
-- Prévia (m): largura, profundidade, altura e a distância à frente que o SERVIDOR usa
-- (LogisticsService: 2 m à frente da raiz, rumo da raiz; FieldWorkService: a pá, 1,5 m). As medidas
-- das obras com modelo (sacos de areia, morteiro, armadilhas) são aproximadas: só a pegada.
export type Preview = { w: number, d: number, h: number, ahead: number }
ToqueTelas.PREVIEW = {
	dig = { w = 1.8, d = 0.6, h = 0.25, ahead = 1.5 },
	garrison = { w = 1.2, d = 0.1, h = 2.2, ahead = 2 },
	mg_nest = { w = 2.2, d = 0.8, h = 0.7, ahead = 2 },
	mortar_pit = { w = 1.6, d = 1.6, h = 0.6, ahead = 2 },
	ammo = { w = 0.6, d = 0.4, h = 0.4, ahead = 2 },
	punji = { w = 1.0, d = 1.0, h = 0.15, ahead = 2 },
	tripwire = { w = 2.0, d = 0.1, h = 0.3, ahead = 2 },
} :: { [string]: Preview }

-- Onde a obra cai: raiz + frente horizontal × distância (studs) e o rumo (rad, convenção do
-- CFrame:ToOrientation: 0 olhando para −Z).
function ToqueTelas.buildSpot(
	rx: number,
	rz: number,
	lx: number,
	lz: number,
	aheadStuds: number
): (number, number, number)
	local m = math.sqrt(lx * lx + lz * lz)
	if m < 1e-6 then
		lx, lz, m = 0, -1, 1
	end
	local ux, uz = lx / m, lz / m
	return rx + ux * aheadStuds, rz + uz * aheadStuds, math.atan2(-ux, -uz)
end

-- Girar o soldado em passos (graus); o rumo volta para −π..π.
function ToqueTelas.turn(yaw: number, deg: number): number
	local y = yaw + math.rad(deg)
	return (y + math.pi) % (2 * math.pi) - math.pi
end

-- ===== nomes dos botões na tela (tutorial e dicas no toque) =====
-- O que o jogador procura na tela do celular para cada ação (o HUD de toque e as telas): nunca a
-- tecla do teclado. Ação sem nome aqui cai em "botão na tela". v39: os nomes dos botões que ficaram
-- (o texto escrito neles) e onde foi parar o que saiu da tela (cartão da arma, COMUNICAR, ITEM, MENU).
-- O Input.glyph também usa esta tabela no toque (tutorial, avisos, fichas).
ToqueTelas.TOUCH_NAME = {
	fire = "FOGO",
	aim = "MIRA",
	reload = "RECARGA",
	sprint = "ANALÓGICO NA BORDA",
	jump = "PULAR",
	crouch = "AGACHAR",
	prone = "AGACHAR (segurar)",
	melee = "GOLPE",
	interact = "INTERAGIR",
	swap_weapon = "CARTÃO DA ARMA", -- tocar no cartão da arma troca de arma (HudCampo)
	bayonet = "CARTÃO DA ARMA (segurar)",
	last_item = "ITEM",
	equip_wheel = "ITEM (segurar)",
	comm_wheel = "COMUNICAR (segurar)",
	mark = "COMUNICAR",
	binoculars = "ITEM (segurar)",
	quick_bandage = "BANDAGEM",
	tourniquet = "ITEM (segurar)",
	give_up = "DESISTIR",
	radio_talk = "RÁDIO (segurar)",
	radio_channel = "RÁDIO",
	view_toggle = "MENU",
	shoulder_swap = "MENU",
	lean_left = "INCLINAR",
	lean_right = "INCLINAR",
	hold_breath = "FÔLEGO",
	fire_mode = "CARTÃO DA ARMA (segurar)", -- segurar o cartão da arma abre o seletor e a alça
	zeroing = "CARTÃO DA ARMA (segurar)",
	map = "MAPA",
	game_menu = "MENU",
	-- veículos (T3)
	v_fire = "TIRO",
	v_door_fire = "TIRO",
	v_optic = "ÓTICA",
	v_coax = "COAXIAL",
	v_ammo = "MUNIÇÃO",
	v_switch_seat = "ASSENTO",
	v_exit = "SAIR",
	h_stabilize = "ESTABILIZAR",
} :: { [string]: string }

function ToqueTelas.touchName(actionId: string): string
	return ToqueTelas.TOUCH_NAME[actionId] or "botão na tela"
end

-- ===== seletor de tiro e alça =====
-- Botões do cartão da arma (as ações que já existem): "mode" = seletor (V tocar), "zero_up" = alça
-- (V segurar), "zero_down" = a arma de um modo só e alça longa (M79, lunetas): tocar V desce a alça.
-- v39: "bayonet" = armar/recolher a baioneta (B segurar do controle), na arma que leva baioneta.
function ToqueTelas.weaponOptions(nModes: number, nZeros: number, bayonet: boolean?): { string }
	local out = {}
	if nModes <= 1 and nZeros > 3 then
		out = { "zero_down", "zero_up" }
	else
		if nModes > 1 then
			table.insert(out, "mode")
		end
		if nZeros > 1 then
			table.insert(out, "zero_up")
		end
	end
	if bayonet then
		table.insert(out, "bayonet")
	end
	return out
end

-- Cartão da arma no toque (v39): um toque curto troca de arma; segurar parado (CARD_HOLD_S) abre o
-- seletor, a alça e a baioneta. Arrastar não é nem um nem outro (o dedo foi olhar). Devolve "tap",
-- "hold" ou nil (ainda não decidiu / nada). ended: o dedo saiu da tela.
ToqueTelas.CARD_HOLD_S = 0.4

function ToqueTelas.cardGesture(heldS: number, movedPx: number, ended: boolean): string?
	if movedPx > ToqueTelas.TAP_MOVE_PX then
		return nil
	end
	if heldS >= ToqueTelas.CARD_HOLD_S then
		return "hold"
	end
	return if ended then "tap" else nil
end

return ToqueTelas
