--!strict
-- Parte 13 (celular e tablet): regras puras do toque, testadas no Lune (tests/luau/toque.luau).
-- Tamanho físico dos botões, layouts prontos (2 polegares, 3 dedos, 4 dedos), espelho do canhoto e
-- layouts próprios, zonas da tela e dono de cada toque, analógico proporcional com a trava da
-- corrida, olhar pelo arrasto e pelo giroscópio, regras do botão de mira e o transpor sozinho.
-- Runtime: Controllers/ToqueHud.client (HUD), Controllers/EditorHud.client (editor),
-- Controllers/CameraLook.client (olhar e giroscópio) e Controllers/Input (ações virtuais).
-- Realismo: nada aqui mostra inimigo; o toque só troca a forma de apertar os mesmos botões.
local Toque = {}

-- ===== tamanho físico =====
-- No celular, 1 px de interface do Roblox ≈ 1 pt (iOS) ou 1 dp (Android): ~160 por polegada. No
-- tablet (lado curto ≥ 600 px) o ponto é maior (iPad ≈ 132 por polegada). Não há DPI de verdade
-- no Roblox: é um palpite pelo tamanho da tela.
Toque.MIN_MM = 9 -- 44 pt / 48 dp
Toque.FIRE_MM = 16 -- tiro: bem maior
Toque.MIN_PX = 48 -- 48 dp (Android) cobre também os 44 pt do iOS
Toque.MARGIN_MM = 2 -- margem extra além da área segura
Toque.SLACK = 0.12 -- o dedo pega um pouco além da borda do botão (fração do raio)

function Toque.dpiGuess(shortSide: number): number
	if shortSide >= 600 then
		return 132
	end
	return 160
end

-- mm -> px sem limites (margens, distâncias de gesto)
function Toque.rawPx(mm: number, screenPx: number, dpiGuess: number?): number
	local dpi = dpiGuess or Toque.dpiGuess(screenPx)
	return mm / 25.4 * dpi
end

-- Tamanho de um botão em px: o físico pedido, nunca abaixo do mínimo de toque nem acima de 32% do
-- lado curto da tela. screenPx = lado curto da tela (px de interface).
function Toque.px(mm: number, screenPx: number, dpiGuess: number?): number
	local p = Toque.rawPx(mm, screenPx, dpiGuess)
	local cap = math.max(Toque.MIN_PX, screenPx * 0.32)
	return math.floor(math.clamp(p, Toque.MIN_PX, cap) + 0.5)
end

-- px -> mm (o olhar converte o arrasto para milímetros do dedo)
function Toque.mm(px: number, dpi: number): number
	return px / dpi * 25.4
end

-- Botão com a escala do editor (60–150%); o mínimo de toque vale sempre.
function Toque.buttonPx(mm: number, scale: number, screenPx: number, dpiGuess: number?): number
	local base = Toque.rawPx(mm, screenPx, dpiGuess) * math.clamp(scale, 0.6, 1.5)
	local cap = math.max(Toque.MIN_PX, screenPx * 0.32)
	return math.floor(math.clamp(base, Toque.MIN_PX, cap) + 0.5)
end

-- ===== botões =====
-- kind: "stick" (analógico), "fire" (tiro; o direito gira a câmera ao arrastar), "aim" (mira),
-- "latch" (toca liga, toca de novo desliga: inclinar), "posture" (tocar agacha, segurar deita,
-- deslizar para cima levanta), "jump", "wheel" (tocar/segurar abre a roda em volta do polegar),
-- "press" (aperta enquanto o dedo está em cima), "giveup" (segurar 1 s), "slot" (vaga de outro
-- agente: o botão contextual de interagir é do T2).
-- show: quando aparece. "move" a pé e no veículo; "foot" a pé; "aim" mirando; "game" em todo
-- contexto de jogo (até caído); "talk" a pé e caído; "voice" com a voz disponível (a pé e no
-- veículo); "downed" caído; "slot" nunca (quem desenha é o dono da vaga).
-- spec: ações do Input.virtual ("a|b" = um botão com duas ações; "a:tap" fixa o tipo).
-- glyph: texto curto no botão (frase inteira: o Traducao traduz).
export type Def = {
	id: string,
	spec: string?,
	kind: string,
	glyph: string,
	label: string,
	mm: number,
	show: string,
	optional: boolean?,
}

Toque.BUTTONS = {
	{ id = "stick", kind = "stick", glyph = "", label = "Analógico", mm = 26, show = "move" },
	{ id = "fire", spec = "fire", kind = "fire", glyph = "FOGO", label = "Atirar", mm = 16, show = "foot" },
	{
		id = "fire_left",
		spec = "fire",
		kind = "fire",
		glyph = "FOGO",
		label = "Atirar (esquerda)",
		mm = 12,
		show = "foot",
		optional = true,
	},
	{ id = "aim", spec = "aim", kind = "aim", glyph = "MIRA", label = "Mirar", mm = 12, show = "foot" },
	{ id = "reload", spec = "reload", kind = "press", glyph = "RECARGA", label = "Recarregar", mm = 10, show = "foot" },
	{
		id = "posture",
		spec = "crouch|prone",
		kind = "posture",
		glyph = "AGACHAR",
		label = "Agachar / deitar",
		mm = 11,
		show = "foot",
	},
	{ id = "jump", spec = "jump", kind = "jump", glyph = "PULAR", label = "Pular / transpor", mm = 11, show = "foot" },
	{
		id = "swap",
		spec = "swap_weapon|bayonet",
		kind = "press",
		glyph = "ARMA",
		label = "Trocar arma / baioneta",
		mm = 10,
		show = "foot",
	},
	{
		id = "equip",
		spec = "last_item|equip_wheel",
		kind = "wheel",
		glyph = "ITEM",
		label = "Último item / roda de equipamento",
		mm = 10,
		show = "foot",
	},
	{ id = "melee", spec = "melee", kind = "press", glyph = "GOLPE", label = "Corpo a corpo", mm = 9, show = "foot" },
	{
		id = "fire_mode",
		spec = "fire_mode|zeroing",
		kind = "press",
		glyph = "SELETOR",
		label = "Seletor / alça de mira",
		mm = 9,
		show = "foot",
	},
	{
		id = "hold_breath",
		spec = "hold_breath",
		kind = "press",
		glyph = "FÔLEGO",
		label = "Prender a respiração",
		mm = 10,
		show = "aim",
	},
	{
		id = "bandage",
		spec = "quick_bandage",
		kind = "press",
		glyph = "BANDAGEM",
		label = "Bandagem rápida",
		mm = 10,
		show = "foot",
	},
	{
		id = "lean_l",
		spec = "lean_left",
		kind = "latch",
		glyph = "◄",
		label = "Inclinar à esquerda",
		mm = 9,
		show = "foot",
	},
	{
		id = "lean_r",
		spec = "lean_right",
		kind = "latch",
		glyph = "►",
		label = "Inclinar à direita",
		mm = 9,
		show = "foot",
	},
	{ id = "interact", kind = "slot", glyph = "", label = "Interagir (contextual)", mm = 12, show = "slot" },
	{ id = "map", spec = "map", kind = "press", glyph = "MAPA", label = "Mapa", mm = 9, show = "game" },
	{ id = "menu", spec = "game_menu", kind = "press", glyph = "MENU", label = "Menu", mm = 9, show = "game" },
	{
		id = "view",
		spec = "view_toggle:tap|shoulder_swap:hold",
		kind = "press",
		glyph = "CÂMERA",
		label = "1ª/3ª pessoa / trocar ombro",
		mm = 9,
		show = "foot",
	},
	{
		id = "comm",
		spec = "comm_wheel",
		kind = "wheel",
		glyph = "COMUNICAR",
		label = "Roda de comunicação",
		mm = 10,
		show = "talk",
	},
	{ id = "mark", spec = "mark", kind = "press", glyph = "MARCAR", label = "Marcar", mm = 9, show = "talk" },
	{
		id = "radio",
		spec = "radio_talk",
		kind = "press",
		glyph = "RÁDIO",
		label = "Falar no rádio",
		mm = 10,
		show = "voice",
	},
	{
		id = "channel",
		spec = "radio_channel",
		kind = "press",
		glyph = "CANAL",
		label = "Canal do rádio",
		mm = 9,
		show = "foot",
	},
	{
		id = "give_up",
		spec = "give_up",
		kind = "giveup",
		glyph = "DESISTIR",
		label = "Desistir (caído)",
		mm = 12,
		show = "downed",
	},
} :: { Def }

Toque.BY_ID = {} :: { [string]: Def }
for _, d in Toque.BUTTONS do
	Toque.BY_ID[d.id] = d
end

-- ===== layouts =====
-- Centro de cada botão em frações da área segura (x 0 = esquerda, y 0 = alto). Desenhados para o
-- celular deitado (16:9 a 19,5:9); no runtime o centro é preso para o botão inteiro caber.
-- A bússola fica no alto, ao centro (HudCampo): o miolo do alto fica livre.
export type Pos = { x: number, y: number, on: boolean? }
local TWO: { [string]: Pos } = {
	stick = { x = 0.15, y = 0.70 },
	fire = { x = 0.855, y = 0.66 },
	fire_left = { x = 0.30, y = 0.50, on = false },
	aim = { x = 0.955, y = 0.42 },
	reload = { x = 0.75, y = 0.47 },
	posture = { x = 0.74, y = 0.93 },
	jump = { x = 0.955, y = 0.90 },
	swap = { x = 0.62, y = 0.88 },
	equip = { x = 0.655, y = 0.64 },
	melee = { x = 0.84, y = 0.30 },
	fire_mode = { x = 0.52, y = 0.91 },
	hold_breath = { x = 0.46, y = 0.40 }, -- só mirando
	bandage = { x = 0.05, y = 0.36 },
	lean_l = { x = 0.21, y = 0.33 },
	lean_r = { x = 0.30, y = 0.33 },
	interact = { x = 0.58, y = 0.40 },
	map = { x = 0.04, y = 0.09 },
	menu = { x = 0.135, y = 0.09 },
	view = { x = 0.23, y = 0.09 },
	channel = { x = 0.325, y = 0.09 },
	comm = { x = 0.70, y = 0.09 },
	mark = { x = 0.80, y = 0.09 },
	radio = { x = 0.90, y = 0.09 },
	give_up = { x = 0.855, y = 0.66 }, -- só caído (o tiro some)
}
-- 3 dedos: o indicador esquerdo atira no alto à esquerda
local THREE: { [string]: Pos } = {
	fire_left = { x = 0.10, y = 0.36, on = true },
	bandage = { x = 0.36, y = 0.55 },
	stick = { x = 0.18, y = 0.75 },
}
-- 4 dedos: os dois indicadores no alto (tiro à esquerda, mira à direita)
local FOUR: { [string]: Pos } = {
	fire_left = { x = 0.10, y = 0.36, on = true },
	bandage = { x = 0.36, y = 0.55 },
	stick = { x = 0.18, y = 0.75 },
	aim = { x = 0.945, y = 0.34 },
	melee = { x = 0.82, y = 0.30 },
}
local function over(base: { [string]: Pos }, extra: { [string]: Pos }): { [string]: Pos }
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end
Toque.PRESETS = {
	two = TWO,
	three = over(TWO, THREE),
	four = over(TWO, FOUR),
} :: { [string]: { [string]: Pos } }
Toque.LAYOUTS = { "two", "three", "four", "custom1", "custom2", "custom3" }
Toque.CUSTOM = { custom1 = true, custom2 = true, custom3 = true } :: { [string]: boolean }

export type Slot = { x: number, y: number, scale: number, alpha: number, on: boolean }
export type LayoutSettings = { touchLayout: string, touchMirror: boolean, touchCustom: any }

-- Layout efetivo: o preset (ou o próprio salvo, por cima do de 2 polegares: botão novo ganha o lugar
-- padrão), espelhado para o canhoto.
function Toque.layout(s: LayoutSettings, mirror: boolean?): { [string]: Slot }
	local name = s.touchLayout
	local base = Toque.PRESETS[name] or TWO
	local out: { [string]: Slot } = {}
	for _, d in Toque.BUTTONS do
		local p = base[d.id] or TWO[d.id]
		local on = true
		if d.optional then
			on = p.on == true
		end
		out[d.id] = { x = p.x, y = p.y, scale = 1, alpha = 1, on = on }
	end
	local custom = if Toque.CUSTOM[name] and type(s.touchCustom) == "table" then s.touchCustom[name] else nil
	if type(custom) == "table" then
		for id, e in custom do
			local o = out[id]
			if o and type(e) == "table" then
				o.x = if type(e.x) == "number" then math.clamp(e.x, 0, 1) else o.x
				o.y = if type(e.y) == "number" then math.clamp(e.y, 0, 1) else o.y
				o.scale = if type(e.scale) == "number" then math.clamp(e.scale, 0.6, 1.5) else o.scale
				o.alpha = if type(e.alpha) == "number" then math.clamp(e.alpha, 0.1, 1) else o.alpha
				if type(e.on) == "boolean" then
					o.on = e.on
				end
			end
		end
	end
	local m = if mirror == nil then s.touchMirror else mirror
	if m then
		for _, o in out do
			o.x = 1 - o.x
		end
	end
	return out
end

-- Do layout na tela (talvez espelhado) para o formato salvo (sempre o destro), saneado.
function Toque.toCustom(slots: { [string]: Slot }, mirrored: boolean): { [string]: any }
	local out: { [string]: any } = {}
	for id, o in slots do
		if Toque.BY_ID[id] then
			local x = if mirrored then 1 - o.x else o.x
			out[id] = {
				x = math.floor(math.clamp(x, 0, 1) * 1000 + 0.5) / 1000,
				y = math.floor(math.clamp(o.y, 0, 1) * 1000 + 0.5) / 1000,
				scale = math.floor(math.clamp(o.scale, 0.6, 1.5) * 100 + 0.5) / 100,
				alpha = math.floor(math.clamp(o.alpha, 0.1, 1) * 100 + 0.5) / 100,
				on = o.on,
			}
		end
	end
	return out
end

-- Centro em px, preso para o botão inteiro (size px) caber na área W x H.
function Toque.place(x: number, y: number, size: number, W: number, H: number): (number, number)
	local r = size / 2
	local cx = math.clamp(x * W, math.min(r, W / 2), math.max(W - r, W / 2))
	local cy = math.clamp(y * H, math.min(r, H / 2), math.max(H - r, H / 2))
	return cx, cy
end

-- ===== visibilidade =====
export type Ctx = { foot: boolean, vehicle: boolean, downed: boolean, aiming: boolean, voice: boolean }

function Toque.visible(d: Def, c: Ctx): boolean
	local foot = c.foot and not c.downed and not c.vehicle
	local s = d.show
	if s == "move" then
		return (foot or c.vehicle) and not c.downed
	elseif s == "foot" then
		return foot
	elseif s == "aim" then
		return foot and c.aiming
	elseif s == "game" then
		return foot or c.vehicle or c.downed
	elseif s == "talk" then
		return (foot or c.downed) and not c.vehicle
	elseif s == "voice" then
		return c.voice and (foot or c.vehicle) and not c.downed
	elseif s == "downed" then
		return c.downed
	end
	return false
end

-- ===== zonas e dono de cada toque =====
-- Zona do analógico flutuante: a metade de baixo do lado do polegar esquerdo (o direito no
-- canhoto). O resto, fora dos botões, é a câmera.
export type Rect = { x0: number, y0: number, x1: number, y1: number }
Toque.STICK_ZONE = { x0 = 0, y0 = 0.2, x1 = 0.46, y1 = 1 } :: Rect

function Toque.zone(mirror: boolean): Rect
	local z = Toque.STICK_ZONE
	if mirror then
		return { x0 = 1 - z.x1, y0 = z.y0, x1 = 1 - z.x0, y1 = z.y1 }
	end
	return table.clone(z)
end

export type HitButton = { id: string, cx: number, cy: number, r: number }

-- Quem fica com um toque que começa em (x, y) px: o botão sob o dedo (o mais central, se dois se
-- tocam), senão o analógico (na zona dele), senão a câmera.
function Toque.hit(x: number, y: number, W: number, H: number, buttons: { HitButton }, zone: Rect): string
	local best, bestK = nil :: string?, math.huge
	for _, b in buttons do
		local d = math.sqrt((x - b.cx) ^ 2 + (y - b.cy) ^ 2)
		local k = d / math.max(b.r, 1)
		if k <= 1 + Toque.SLACK and k < bestK then
			best, bestK = b.id, k
		end
	end
	if best then
		return best
	end
	local fx, fy = x / math.max(W, 1), y / math.max(H, 1)
	if fx >= zone.x0 and fx <= zone.x1 and fy >= zone.y0 and fy <= zone.y1 then
		return "stick"
	end
	return "camera"
end

-- Cada toque pertence ao controle onde começou: passar por cima de outro botão não o aciona e
-- soltar fora solta o dono. Um botão (ou o analógico) já seguro por outro dedo não é tomado: o
-- dedo novo vira câmera.
export type Tracker = { owners: { [any]: string }, held: { [string]: any } }

function Toque.newTracker(): Tracker
	return { owners = {}, held = {} }
end

function Toque.claim(tr: Tracker, touch: any, hitId: string): string
	local id = hitId
	if id ~= "camera" and tr.held[id] ~= nil then
		id = "camera"
	end
	tr.owners[touch] = id
	if id ~= "camera" then
		tr.held[id] = touch
	end
	return id
end

function Toque.owner(tr: Tracker, touch: any): string?
	return tr.owners[touch]
end

-- Fim do toque (onde quer que o dedo esteja): devolve o dono, que é solto.
function Toque.release(tr: Tracker, touch: any): string?
	local id = tr.owners[touch]
	if id == nil then
		return nil
	end
	tr.owners[touch] = nil
	if tr.held[id] == touch then
		tr.held[id] = nil
	end
	return id
end

-- App em segundo plano, ligação, notificação que tira o foco: solta tudo; devolve os donos soltos.
function Toque.releaseAll(tr: Tracker): { string }
	local out = {}
	for _, id in tr.owners do
		table.insert(out, id)
	end
	table.clear(tr.owners)
	table.clear(tr.held)
	table.sort(out)
	return out
end

-- ===== analógico (proporcional) e trava da corrida =====
Toque.STICK_INNER = 0.08 -- zona morta (fração do raio)
Toque.SPRINT_MAG = 0.92 -- na borda, para a frente, corre
Toque.SPRINT_CONE_DEG = 30
Toque.LOCK_K = 1.75 -- o cadeado fica 1,75 raio acima do centro

export type Stick = { locked: boolean, sprint: boolean, inLock: boolean }

function Toque.newStick(): Stick
	return { locked = false, sprint = false, inLock = false }
end

-- tocar no analógico destrava (o dedo novo manda de novo)
function Toque.stickBegan(st: Stick)
	st.locked, st.inLock = false, false
end

-- mirar ou atirar destrava
function Toque.unlock(st: Stick)
	st.locked, st.inLock = false, false
end

-- Valor do analógico: dx, dy em px (tela: y para baixo), R = raio. Devolve x, y (y para cima) e a
-- magnitude 0..1: pouco = devagar e silencioso, metade anda, a borda é o máximo.
function Toque.stickValue(dx: number, dy: number, R: number): (number, number, number)
	local len = math.sqrt(dx * dx + dy * dy)
	if len <= 1e-6 or R <= 0 then
		return 0, 0, 0
	end
	local m = len / R
	local inner = Toque.STICK_INNER
	local mag = if m <= inner then 0 else math.min((m - inner) / (1 - inner), 1)
	return dx / len * mag, -dy / len * mag, mag
end

-- Um quadro do analógico. touching = dedo no analógico (dx, dy: dedo menos a base, px).
-- Devolve x, y (−1..1) e se pede corrida. Empurrar até a borda para a frente corre; arrastar
-- além, até o cadeado, trava a corrida (solta o dedo e continua correndo para a frente).
function Toque.stickStep(st: Stick, touching: boolean, dx: number, dy: number, R: number): (number, number, boolean)
	if not touching then
		st.inLock = false
		if st.locked then
			st.sprint = true
			return 0, 1, true
		end
		st.sprint = false
		return 0, 0, false
	end
	local cone = math.rad(Toque.SPRINT_CONE_DEG)
	local up = if R > 0 then -dy / R else 0
	local side = math.atan2(math.abs(dx), math.max(-dy, 1e-6)) -- 0 = reto para a frente
	st.inLock = up >= Toque.LOCK_K and side <= cone
	st.locked = st.inLock -- sair do cadeado com o dedo ainda no chão destrava
	if st.locked then
		st.sprint = true
		return 0, 1, true
	end
	local x, y, m = Toque.stickValue(dx, dy, R)
	local ang = if m > 0 then math.atan2(math.abs(x), math.max(y, 1e-6)) else math.pi
	if st.sprint then
		st.sprint = m >= 0.8 and y > 0 and ang <= cone + math.rad(10) -- histerese
	else
		st.sprint = m >= Toque.SPRINT_MAG and y > 0 and ang <= cone
	end
	return x, y, st.sprint
end

-- ===== transpor sozinho ao correr contra o obstáculo (opção touchAutoVault) =====
export type Vault = { t: number, lastAt: number }
Toque.VAULT_HOLD_S = 0.2 -- encostado correndo por 0,2 s
Toque.VAULT_GAP_S = 1.0
Toque.VAULT_RATIO = 0.35 -- andando a menos de 35% do pedido = parado no obstáculo

function Toque.newVault(): Vault
	return { t = 0, lastAt = -math.huge }
end

export type VaultIn = { enabled: boolean, sprinting: boolean, forward: boolean, grounded: boolean, speedRatio: number }

function Toque.autoVault(st: Vault, dt: number, now: number, i: VaultIn): boolean
	if not (i.enabled and i.sprinting and i.forward and i.grounded) or i.speedRatio >= Toque.VAULT_RATIO then
		st.t = 0
		return false
	end
	st.t += dt
	if st.t >= Toque.VAULT_HOLD_S and now - st.lastAt >= Toque.VAULT_GAP_S then
		st.t = 0
		st.lastAt = now
		return true
	end
	return false
end

-- ===== olhar pelo arrasto =====
export type LookSettings = {
	touchLookSens: number,
	touchAdsSens: number,
	touchScopeSens: number,
	touchAccel: boolean,
	invertY: boolean,
	gyroMode: string,
	gyroSens: number,
}
Toque.LOOK_DEG_PER_MM = 2.2 -- sensibilidade 1, quadril
Toque.ACCEL_MAX = 1.0 -- +100% num arrasto rápido (opção touchAccel)
Toque.ACCEL_V0 = 80 -- mm/s: abaixo, sem aceleração
Toque.ACCEL_V1 = 320 -- mm/s: aceleração cheia

function Toque.lookSens(s: LookSettings, mode: string): number
	if mode == "ads" then
		return s.touchAdsSens
	elseif mode == "scope" then
		return s.touchScopeSens
	end
	return s.touchLookSens
end

-- Arrasto (px) -> graus (direita, para cima). Arrastar para a direita gira para a direita; para
-- cima, olha para cima (Y invertido troca). A assistência mínima é aplicada por quem chama.
function Toque.lookDelta(
	dxPx: number,
	dyPx: number,
	dt: number,
	dpi: number,
	s: LookSettings,
	mode: string
): (number, number)
	if dxPx == 0 and dyPx == 0 then
		return 0, 0
	end
	local mx, my = Toque.mm(dxPx, dpi), Toque.mm(dyPx, dpi)
	local k = Toque.LOOK_DEG_PER_MM * Toque.lookSens(s, mode)
	if s.touchAccel and dt > 0 then
		local v = math.sqrt(mx * mx + my * my) / dt
		local a = math.clamp((v - Toque.ACCEL_V0) / (Toque.ACCEL_V1 - Toque.ACCEL_V0), 0, 1)
		k *= 1 + Toque.ACCEL_MAX * a
	end
	local yaw = mx * k
	local pitch = -my * k
	if s.invertY then
		pitch = -pitch
	end
	return yaw, pitch
end

-- ===== giroscópio =====
Toque.GYRO_DEAD_DEG = 0.02 -- tremor da mão parada (por amostra)

-- Giro do aparelho entre duas leituras (rx, ry: ângulos XYZ de atual * anterior:Inverse(), como o
-- exemplo do DeviceRotationChanged) -> graus (direita, para cima). flip: deitado para o outro lado
-- (a gravidade diz). Modo "off" nada; "aim" só mirando (ferro ou luneta); "always" sempre.
function Toque.gyroStep(rx: number, ry: number, flip: boolean, s: LookSettings, mode: string): (number, number)
	if s.gyroMode == "off" or (s.gyroMode == "aim" and mode == "hip") then
		return 0, 0
	end
	local sg = if flip then -1 else 1
	local pitch = math.deg(rx) * sg * s.gyroSens
	local yaw = math.deg(ry) * sg * s.gyroSens
	if math.abs(pitch) < Toque.GYRO_DEAD_DEG * s.gyroSens then
		pitch = 0
	end
	if math.abs(yaw) < Toque.GYRO_DEAD_DEG * s.gyroSens then
		yaw = 0
	end
	return yaw, pitch
end

-- ===== botão de mira =====
-- Devolve os apertos virtuais da ação "aim" ({true}, {false}, {true, false} ou {}) e se o botão
-- fica travado apertado.
-- padToggle (Acessib. "Mirar: alternar", aimToggle): o WeaponController já alterna a cada aperto;
-- touchToggle (touchAimToggle, padrão no toque): um toque liga e outro desliga; senão, segurar.
function Toque.aimOps(touchToggle: boolean, padToggle: boolean, latched: boolean, down: boolean): ({ boolean }, boolean)
	if padToggle then
		if down then
			return { true, false }, false
		end
		return {}, false
	end
	if touchToggle then
		if not down then
			return {}, latched
		end
		if latched then
			return { false }, false
		end
		return { true }, true
	end
	return { down }, down
end

-- ===== especificação das ações de um botão =====
export type Part = { id: string, kind: string? }

-- "crouch|prone" -> {crouch}, {prone}; "view_toggle:tap|shoulder_swap:hold" fixa o tipo.
function Toque.parseSpec(spec: string): { Part }
	local out: { Part } = {}
	for _, piece in string.split(spec, "|") do
		local id, kind = string.match(piece, "^([%w_]+):(%a+)$")
		if id then
			if kind == "press" or kind == "tap" or kind == "hold" then
				local p: Part = { id = id, kind = kind :: string }
				table.insert(out, p)
			end
		elseif string.match(piece, "^[%w_]+$") then
			table.insert(out, { id = piece })
		end
	end
	return out
end

function Toque.specHas(spec: string, actionId: string): boolean
	for _, p in Toque.parseSpec(spec) do
		if p.id == actionId then
			return true
		end
	end
	return false
end

return Toque
