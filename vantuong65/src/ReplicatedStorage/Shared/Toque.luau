--!strict
-- Parte 13 (celular e tablet): regras puras do toque, testadas no Lune (tests/luau/toque.luau).
-- Tamanho físico dos botões, layouts prontos (2 polegares, 3 dedos, 4 dedos), espelho do canhoto e
-- layouts próprios, zonas da tela e dono de cada toque, analógico proporcional com a trava da
-- corrida, olhar pelo arrasto e pelo giroscópio, regras do botão de mira e o transpor sozinho.
-- v39 (dono, jogando no celular: "deixe a tela o mais limpa possível", "deixe somente os botões
-- importantes; o resto automático"): botões fixos só os do uso o tempo todo, os outros aparecem
-- quando servem (Ctx), zonas livres para o HUD das outras telas (ZONES) e as regras do que é
-- automático no toque (recarga na pausa, golpe, inclinar na quina, ímã leve, tiro sozinho, pegar
-- munição, respiração na luneta).
-- Runtime: Controllers/ToqueHud.client (HUD), Controllers/ToqueAuto (automáticos),
-- Controllers/EditorHud.client (editor), Controllers/CameraLook.client (olhar, giroscópio e ímã) e
-- Controllers/Input (ações virtuais).
-- Realismo: nada aqui mostra inimigo além do que o soldado vê; o toque só troca a forma de apertar
-- os mesmos botões.
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
-- agente: o botão contextual de interagir é do Interagir.client).
-- show: quando aparece. "move" a pé e no veículo; "foot" a pé; "game" em todo contexto de jogo
-- (até caído); "talk" a pé e caído; "downed" caído; "slot" nunca (quem desenha é o dono da vaga).
-- Contextuais (v39, só quando servem; o Ctx diz): "reload" (carregador gasto, Toque.showReload),
-- "melee" (inimigo à vista a poucos metros, sem mirar), "breath" (na luneta, com a respiração
-- sozinha desligada), "bleed" (sangrando, com bandagem ou torniquete) e "radio" (com a voz do jogo
-- ou, a pé, para quem fala com o comando).
-- spec: ações do Input.virtual ("a|b" = um botão com duas ações; "a:tap" fixa o tipo).
-- glyph: texto curto no botão (frase inteira: o Traducao traduz).
-- Saíram da tela na v39 (layout salvo com eles: o botão é ignorado): ARMA e SELETOR (o cartão da
-- arma: tocar troca, segurar abre seletor, alça e baioneta), MARCAR (tocar no COMUNICAR), CÂMERA
-- (menu: Configurações > Toque > Câmera) e CANAL (tocar no RÁDIO).
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
		id = "equip",
		spec = "last_item|equip_wheel",
		kind = "wheel",
		glyph = "ITEM",
		label = "Último item / roda de equipamento",
		mm = 10,
		show = "foot",
	},
	{
		id = "comm",
		spec = "mark|comm_wheel",
		kind = "wheel",
		glyph = "COMUNICAR",
		label = "Marcar (tocar) / roda de comunicação (segurar)",
		mm = 10,
		show = "talk",
	},
	{ id = "map", spec = "map", kind = "press", glyph = "MAPA", label = "Mapa", mm = 9, show = "game" },
	{ id = "menu", spec = "game_menu", kind = "press", glyph = "MENU", label = "Menu", mm = 9, show = "game" },
	-- contextuais (só quando servem)
	{
		id = "reload",
		spec = "reload",
		kind = "press",
		glyph = "RECARGA",
		label = "Recarregar (aparece com o carregador gasto)",
		mm = 10,
		show = "reload",
	},
	{
		id = "melee",
		spec = "melee",
		kind = "press",
		glyph = "GOLPE",
		label = "Corpo a corpo (aparece com o inimigo perto)",
		mm = 10,
		show = "melee",
	},
	{
		id = "hold_breath",
		spec = "hold_breath",
		kind = "press",
		glyph = "FÔLEGO",
		label = "Prender a respiração (na luneta)",
		mm = 10,
		show = "breath",
	},
	{
		id = "bandage",
		spec = "quick_bandage",
		kind = "press",
		glyph = "BANDAGEM",
		label = "Bandagem rápida (aparece sangrando)",
		mm = 10,
		show = "bleed",
	},
	{
		id = "radio",
		spec = "radio_channel:tap|radio_talk:hold",
		kind = "press",
		glyph = "RÁDIO",
		label = "Rádio: segurar fala, tocar troca o canal",
		mm = 10,
		show = "radio",
	},
	{
		id = "interact",
		kind = "slot",
		glyph = "",
		label = "Interagir (aparece perto de algo)",
		mm = 13.5,
		show = "slot",
	},
	-- opcionais (desligados no padrão; o editor liga): o inclinar é sozinho na quina (ToqueAuto)
	{
		id = "lean_l",
		spec = "lean_left",
		kind = "latch",
		glyph = "◄",
		label = "Inclinar à esquerda",
		mm = 9,
		show = "foot",
		optional = true,
	},
	{
		id = "lean_r",
		spec = "lean_right",
		kind = "latch",
		glyph = "►",
		label = "Inclinar à direita",
		mm = 9,
		show = "foot",
		optional = true,
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
-- celular deitado (16:9 a 20:9); no runtime o centro é preso para o botão inteiro caber.
-- v39: o polegar direito tem o tiro e, em volta dele, mira, pular, agachar, ITEM e os contextuais
-- (recarga, golpe/fôlego, interagir); o esquerdo, o analógico e a bandagem (sangrando). No alto,
-- pequenos: mapa e menu à esquerda, COMUNICAR e o rádio à direita. O miolo do alto, a coluna da
-- esquerda acima do polegar e o pé do meio ficam para o HUD das outras telas (ZONES).
-- Golpe e fôlego dividem o lugar: o golpe nunca aparece mirando; o fôlego, só na luneta.
export type Pos = { x: number, y: number, on: boolean? }
local TWO: { [string]: Pos } = {
	stick = { x = 0.185, y = 0.77 },
	fire = { x = 0.855, y = 0.68 },
	fire_left = { x = 0.065, y = 0.36, on = false },
	aim = { x = 0.955, y = 0.42 },
	posture = { x = 0.75, y = 0.92 },
	jump = { x = 0.955, y = 0.92 },
	equip = { x = 0.72, y = 0.65 },
	comm = { x = 0.80, y = 0.09 },
	map = { x = 0.035, y = 0.09 },
	menu = { x = 0.135, y = 0.09 },
	reload = { x = 0.735, y = 0.42 },
	melee = { x = 0.835, y = 0.34 },
	hold_breath = { x = 0.835, y = 0.34 },
	bandage = { x = 0.05, y = 0.68 },
	radio = { x = 0.90, y = 0.09 },
	interact = { x = 0.61, y = 0.52 },
	lean_l = { x = 0.30, y = 0.64, on = false },
	lean_r = { x = 0.40, y = 0.64, on = false },
	give_up = { x = 0.855, y = 0.68 }, -- só caído (o tiro some)
}
-- 3 dedos: o indicador esquerdo atira no alto à esquerda
local THREE: { [string]: Pos } = {
	fire_left = { x = 0.065, y = 0.36, on = true },
}
-- 4 dedos: os dois indicadores no alto (tiro à esquerda, mira à direita; o golpe e o fôlego vão
-- para o lugar da mira, perto do polegar)
local FOUR: { [string]: Pos } = {
	fire_left = { x = 0.065, y = 0.36, on = true },
	aim = { x = 0.85, y = 0.33 },
	melee = { x = 0.955, y = 0.42 },
	hold_breath = { x = 0.955, y = 0.42 },
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

-- Tablet (lado curto ≥ 600 px de interface): os mesmos botões, mais perto dos cantos de baixo (o
-- polegar alcança ~6 cm a partir do canto, num tablet a fração do celular ficaria longe demais). A
-- distância de cada botão até o canto do lado dele encolhe (TABLET_K); a fileira do alto não muda.
Toque.TABLET_SHORT = 600
Toque.TABLET_K = { x = 0.62, y = 0.78 } -- PLACEHOLDER (o alcance do polegar não foi medido)
Toque.TOP_ROW = { map = true, menu = true, comm = true, radio = true } :: { [string]: boolean }

function Toque.isTablet(shortPx: number): boolean
	return shortPx >= Toque.TABLET_SHORT
end

function Toque.compact(id: string, p: Pos): Pos
	if Toque.TOP_ROW[id] then
		return p
	end
	local ax = if p.x < 0.5 then 0 else 1
	return { x = ax + (p.x - ax) * Toque.TABLET_K.x, y = 1 + (p.y - 1) * Toque.TABLET_K.y, on = p.on }
end

-- Layout efetivo: o preset (ou o próprio salvo, por cima do de 2 polegares: botão novo ganha o lugar
-- padrão), espelhado para o canhoto. tablet: o preset compacto nos cantos (o salvo vale como está).
-- Um layout salvo com botão que saiu do jogo (ARMA, SELETOR, MARCAR, CÂMERA, CANAL) é ignorado.
function Toque.layout(s: LayoutSettings, mirror: boolean?, tablet: boolean?): { [string]: Slot }
	local name = s.touchLayout
	local base = Toque.PRESETS[name] or TWO
	local out: { [string]: Slot } = {}
	for _, d in Toque.BUTTONS do
		local p = base[d.id] or TWO[d.id]
		if tablet then
			p = Toque.compact(d.id, p)
		end
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
-- Os campos opcionais são os contextuais (v39): reload (Toque.showReload), melee (inimigo à vista a
-- poucos metros, Toque.meleeNear), breath (na luneta com a respiração sozinha desligada), bleed
-- (sangrando com bandagem ou torniquete), command (fala com o comando: comandante, morteiro ou quem
-- carrega o rádio).
export type Ctx = {
	foot: boolean,
	vehicle: boolean,
	downed: boolean,
	aiming: boolean,
	voice: boolean,
	reload: boolean?,
	melee: boolean?,
	breath: boolean?,
	bleed: boolean?,
	command: boolean?,
}

function Toque.visible(d: Def, c: Ctx): boolean
	local foot = c.foot and not c.downed and not c.vehicle
	local s = d.show
	if s == "move" then
		return (foot or c.vehicle) and not c.downed
	elseif s == "foot" then
		return foot
	elseif s == "game" then
		return foot or c.vehicle or c.downed
	elseif s == "talk" then
		return (foot or c.downed) and not c.vehicle
	elseif s == "downed" then
		return c.downed
	elseif s == "reload" then
		return foot and c.reload == true
	elseif s == "melee" then
		return foot and c.melee == true and not c.aiming
	elseif s == "breath" then
		return foot and c.breath == true and c.aiming
	elseif s == "bleed" then
		return foot and c.bleed == true
	elseif s == "radio" then
		-- no veículo só a voz (o canal é da infantaria)
		return not c.downed and ((c.voice and (foot or c.vehicle)) or (c.command == true and foot))
	end
	return false
end

-- ===== contextuais =====
-- RECARGA: carregador gasto, com reserva e sem recarga correndo. Com a recarga automática ligada (o
-- WeaponController recarrega sozinho ao esvaziar), só a recarga tática numa pausa: carregador pela
-- metade ou menos (e não vazio: o vazio a automática cobre) e 1,5 s sem atirar.
Toque.RELOAD_AUTO_FRAC = 0.5 -- PLACEHOLDER
Toque.RELOAD_PAUSE_S = 1.5 -- PLACEHOLDER

export type ReloadIn = {
	mag: number?,
	size: number?,
	spare: number?,
	reloading: boolean,
	auto: boolean,
	sinceShot: number,
}

function Toque.showReload(i: ReloadIn): boolean
	local mag, size, spare = i.mag, i.size, i.spare
	if mag == nil or size == nil or size <= 0 or i.reloading or (spare or 0) <= 0 or mag >= size then
		return false
	end
	if i.auto then
		return mag > 0 and mag <= size * Toque.RELOAD_AUTO_FRAC and i.sinceShot >= Toque.RELOAD_PAUSE_S
	end
	return true
end

-- GOLPE: inimigo vivo À VISTA (raio direto da cabeça, quem chama confere) a até 4 m e na frente. O
-- alcance do golpe mais longo é 2,1 m (baioneta, Shared/Melee): o botão chega um pouco antes.
Toque.MELEE_M = 4 -- PLACEHOLDER
Toque.MELEE_DEG = 70 -- PLACEHOLDER

function Toque.meleeNear(distM: number, angDeg: number, visible: boolean): boolean
	return visible and distM <= Toque.MELEE_M and angDeg <= Toque.MELEE_DEG
end

-- BANDAGEM: sangrando e com o que pôr
function Toque.showBandage(bleed: number?, bandages: number?, tourniquets: number?): boolean
	return (bleed or 0) > 0 and ((bandages or 0) + (tourniquets or 0)) > 0
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

-- ===== zonas livres do HUD (v39) =====
-- Retângulos (frações da área segura, destro) onde as outras telas desenham no toque, sem botão
-- por baixo nem uma em cima da outra (tests/luau/toque.luau confere em 16:9, 19,5:9, 20:9 e 4:3,
-- destro e canhoto, nos layouts prontos, com todos os contextuais acesos):
--   topo      faixa da frente (FrontHud)
--   bussola   bússola (HudCampo)
--   eventos   eventos da partida (EventosHud), na coluna da esquerda acima do polegar
--   avisos    avisos (Toast) e as mensagens do squad (feed do InfantryController)
--   cartao    cartão da arma (HudCampo): tocar troca de arma, segurar abre seletor, alça e baioneta
--   captura   painel da captura do setor (FrontHud)
--   tutorial  cartão do tutorial (TutorialController): cobre eventos e avisos enquanto dura
--   vagas     faixa das vagas (BarraItens), 2,5 s por cima da faixa e da bússola
-- O miolo (a mira e o marcador de acerto) fica sempre livre. No celular de 19,5:9 o painel da
-- captura e o cartão da arma ficam com ~50% do tamanho do PC: conferir a leitura no aparelho.
-- Frações PLACEHOLDER (o teste garante que nada se cobre; o tamanho bom de ler, só no aparelho).
Toque.ZONES = {
	topo = { x0 = 0.19, y0 = 0.00, x1 = 0.74, y1 = 0.14 },
	-- v41: a faixa da frente subiu para a barra do Roblox (FrontHud) e a bússola subiu para o alto
	-- da área ("como era antes"); a zona "topo" ficou de reserva (Studio sem a barra)
	bussola = { x0 = 0.25, y0 = 0.00, x1 = 0.64, y1 = 0.13 },
	-- v41 (pedido do dono: "coloque isso mais para o canto da tela e um pouco menor"): eventos e
	-- avisos mais estreitos (a escala sai da largura da zona), encostados na esquerda
	eventos = { x0 = 0.00, y0 = 0.27, x1 = 0.30, y1 = 0.40 },
	avisos = { x0 = 0.00, y0 = 0.40, x1 = 0.34, y1 = 0.56 },
	cartao = { x0 = 0.46, y0 = 0.80, x1 = 0.66, y1 = 1.00 },
	captura = { x0 = 0.27, y0 = 0.58, x1 = 0.50, y1 = 0.80 },
	tutorial = { x0 = 0.00, y0 = 0.27, x1 = 0.46, y1 = 0.56 },
	vagas = { x0 = 0.19, y0 = 0.00, x1 = 0.74, y1 = 0.27 },
	-- v41 (pedido do dono: "botoes estao em cima da outros"): o cartão de caído (CasualtyScreen) no
	-- pé, à esquerda do DESISTIR (que fica no lugar do tiro); caído não há analógico nem cartão da arma
	caido = { x0 = 0.03, y0 = 0.62, x1 = 0.74, y1 = 1.00 },
} :: { [string]: Rect }
-- zonas que só existem num contexto (o teste confere os botões só dele): o cartão de caído só caído
Toque.ZONE_CTX = { caido = "downed" } :: { [string]: string }
-- com o tiro do indicador esquerdo (3 e 4 dedos) a coluna da esquerda começa depois dele
Toque.ZONES_INDEX = { eventos = 0.13, avisos = 0.13, tutorial = 0.13 } :: { [string]: number }
-- zonas que se cobrem de propósito (uma substitui a outra por um tempo)
Toque.ZONE_SHARE = {
	tutorial = { eventos = true, avisos = true },
	vagas = { topo = true, bussola = true },
	bussola = { topo = true },
	-- caído o painel da captura e o cartão da arma somem (FrontHud, HudCampo)
	caido = { captura = true, cartao = true },
} :: { [string]: { [string]: boolean } }

-- Zona em px da área W x H (origem no canto de cima à esquerda da área); mirror: canhoto; index:
-- o tiro do indicador esquerdo está ligado.
function Toque.zoneRect(name: string, W: number, H: number, mirror: boolean?, index: boolean?): Rect?
	local z = Toque.ZONES[name]
	if not z then
		return nil
	end
	local x0, x1 = z.x0, z.x1
	if index and Toque.ZONES_INDEX[name] then
		x0 = math.max(x0, Toque.ZONES_INDEX[name])
	end
	if mirror then
		x0, x1 = 1 - x1, 1 - x0
	end
	return { x0 = x0 * W, y0 = z.y0 * H, x1 = x1 * W, y1 = z.y1 * H }
end

-- Escala para um quadro de w x h caber na zona (nunca cresce além de maxK; piso minK).
function Toque.fitK(w: number, h: number, zw: number, zh: number, maxK: number, minK: number): number
	if w <= 0 or h <= 0 then
		return maxK
	end
	return math.clamp(math.min(zw / w, zh / h), minK, maxK)
end

-- círculo (botão) encosta no retângulo?
function Toque.circleHitsRect(cx: number, cy: number, r: number, z: Rect): boolean
	local nx = math.clamp(cx, z.x0, z.x1)
	local ny = math.clamp(cy, z.y0, z.y1)
	return (cx - nx) ^ 2 + (cy - ny) ^ 2 < (r - 0.5) ^ 2
end

function Toque.rectsHit(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.y0 < b.y1 - 0.5 and b.y0 < a.y1 - 0.5
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

-- v39: andando firme para a frente (analógico além da metade) também sobe o obstáculo baixo; o
-- Movement só transpõe se houver obstáculo que dê, senão o "pular" virtual não faz nada.
export type VaultIn = {
	enabled: boolean,
	sprinting: boolean,
	forward: boolean,
	grounded: boolean,
	speedRatio: number,
	walking: boolean?,
}

function Toque.autoVault(st: Vault, dt: number, now: number, i: VaultIn): boolean
	local pushing = i.sprinting or i.walking == true
	if not (i.enabled and pushing and i.forward and i.grounded) or i.speedRatio >= Toque.VAULT_RATIO then
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

-- ===== automáticos do toque (v39; runtime em Controllers/ToqueAuto, cada um com opção no menu) =====
-- Limites, para o celular não ficar mais forte que o PC:
--   - nada atravessa parede, mata ou fumaça: quem chama confere a vista com um raio direto;
--   - nada no tiro do quadril: ímã e tiro sozinho só mirando, até 150 m (o alcance da fricção);
--   - o ímã só acompanha quem o jogador já está movendo a mira para seguir (dedo arrastando ou
--     andando), puxa no máximo 1,5°/s e nunca gruda (a fricção do controle continua a mesma);
--   - o tiro sozinho espera 0,25 s com a mira no inimigo (o tempo de reação de uma pessoa), no semi
--     dá um tiro a cada 0,3 s no máximo e vem DESLIGADO;
--   - inclinar e respirar só fazem o que o PC faz com Q/E e Shift, nos mesmos limites.
-- Os números desta parte (e os do tablet, das zonas e da recarga e do golpe acima) são PLACEHOLDER:
-- escolhidos no papel, sem teste em aparelho real.

-- Inclinar sozinho: mirando, colado numa quina (a parede logo à frente do olho, sem inclinar) e com a
-- vista aberta de um lado só, inclina para esse lado e fica enquanto a quina continuar.
Toque.LEAN_AHEAD_M = 1.0
Toque.LEAN_CLEAR_M = 4
Toque.LEAN_ARM_S = 0.2 -- a quina firme por isto antes de inclinar (passar rente não inclina)

export type Lean = { side: number, want: number, t: number }
function Toque.newLean(): Lean
	return { side = 0, want = 0, t = 0 }
end

export type LeanIn = {
	enabled: boolean,
	aiming: boolean,
	blocked: boolean, -- correndo, deitado, transpondo, no veículo
	manual: boolean, -- o jogador ligou um botão de inclinar
	ahead: boolean, -- parede a até LEAN_AHEAD_M à frente do olho sem inclinar
	clearL: boolean, -- vista aberta (LEAN_CLEAR_M) saindo do olho inclinado à esquerda
	clearR: boolean,
}

-- Devolve −1 (esquerda), 0 ou 1.
function Toque.autoLean(st: Lean, dt: number, i: LeanIn): number
	if not (i.enabled and i.aiming) or i.blocked or i.manual then
		st.side, st.want, st.t = 0, 0, 0
		return 0
	end
	if st.side ~= 0 then
		local open = if st.side < 0 then i.clearL else i.clearR
		if i.ahead and open then
			return st.side
		end
		st.side = 0
	end
	local want = 0
	if i.ahead and i.clearL ~= i.clearR then
		want = if i.clearL then -1 else 1
	end
	if want ~= st.want then
		st.want, st.t = want, 0
	else
		st.t += dt
	end
	if want ~= 0 and st.t >= Toque.LEAN_ARM_S then
		st.side = want
	end
	return st.side
end

-- Ímã leve (só toque): graus a girar para o alvo neste quadro. Mesmo cone da fricção
-- (InputMap.assistFactor, alvo de 0,3 m), vezes MAGNET_CONE_K.
Toque.ASSIST_RANGE_M = 150 -- o mesmo InputMap.ASSIST_RANGE_M
Toque.MAGNET_DEG_S = 1.5
Toque.MAGNET_CONE_K = 2

function Toque.magnetCone(distM: number): number
	return (math.deg(math.atan(0.3 / math.max(distM, 1))) * 1.5 + 0.5) * Toque.MAGNET_CONE_K
end

function Toque.magnet(
	enabled: boolean,
	mode: string,
	visible: boolean,
	distM: number,
	angDeg: number,
	moving: boolean,
	dt: number
): number
	if not (enabled and visible and moving) or mode == "hip" or distM <= 0 or distM > Toque.ASSIST_RANGE_M then
		return 0
	end
	if angDeg <= 0 or angDeg >= Toque.magnetCone(distM) then
		return 0
	end
	return math.min(Toque.MAGNET_DEG_S * dt, angDeg * 0.25)
end

-- Tiro sozinho (opção, desligada no padrão): mirando, com a mira EM CIMA de um inimigo à vista.
Toque.AUTOFIRE_REACT_S = 0.25
Toque.AUTOFIRE_GAP_S = 0.3
Toque.AUTOFIRE_LOSE_S = 0.1

export type AutoFire = { onT: number, offT: number, held: boolean, lastTap: number }
function Toque.newAutoFire(): AutoFire
	return { onT = 0, offT = 0, held = false, lastTap = -math.huge }
end

export type AutoFireIn = {
	enabled: boolean,
	aiming: boolean,
	onTarget: boolean,
	full: boolean, -- automático: segura enquanto estiver no alvo; semi/ferrolho: toques
	canFire: boolean, -- a pé, sem recarga, sem o dedo do jogador no tiro
}

-- Devolve "press", "release" ou nil (o aperto virtual do tiro).
function Toque.autoFire(st: AutoFire, dt: number, now: number, i: AutoFireIn): string?
	local ok = i.enabled and i.aiming and i.canFire
	if ok and i.onTarget then
		st.onT += dt
		st.offT = 0
	else
		st.offT += dt
		if not ok or st.offT >= Toque.AUTOFIRE_LOSE_S then
			st.onT = 0
		end
	end
	if st.held then
		if not i.full or not ok or st.onT <= 0 then
			st.held = false
			return "release"
		end
		return nil
	end
	local gap = if i.full then 0 else Toque.AUTOFIRE_GAP_S
	if ok and i.onTarget and st.onT >= Toque.AUTOFIRE_REACT_S and now - st.lastTap >= gap then
		st.held, st.lastTap = true, now
		return "press"
	end
	return nil
end

-- Pegar munição e abrir caixote ao encostar (opção): parado ou devagar a até 1,6 m, sem atirar há
-- 2 s; uma vez a cada 20 s por objeto. Arma do chão, rádio, carga e armadilha são escolha: nunca.
Toque.PICKUP_M = 1.6
Toque.PICKUP_SPEED = 1.2 -- m/s
Toque.PICKUP_QUIET_S = 2
Toque.PICKUP_AGAIN_S = 20
Toque.PICKUP_KINDS = { ammo = true, crate = true } :: { [string]: boolean }

function Toque.autoPickup(
	enabled: boolean,
	kind: string?,
	distM: number,
	speedMs: number,
	sinceShot: number,
	sinceLast: number
): boolean
	return enabled
		and kind ~= nil
		and Toque.PICKUP_KINDS[kind] == true
		and distM <= Toque.PICKUP_M
		and speedMs <= Toque.PICKUP_SPEED
		and sinceShot >= Toque.PICKUP_QUIET_S
		and sinceLast >= Toque.PICKUP_AGAIN_S
end

-- Respiração sozinha na luneta (opção): prende ao entrar na luneta e solta um pouco antes do ponto
-- em que segurar cansa (Weapons.BREATH_TIRED_K), como faria quem segura o Shift no PC.
Toque.BREATH_EARLY_S = 0.15

function Toque.breathRelease(heldS: number, lenS: number, tiredK: number): boolean
	return heldS >= lenS * tiredK - Toque.BREATH_EARLY_S
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
