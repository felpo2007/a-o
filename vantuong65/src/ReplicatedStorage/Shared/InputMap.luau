--!strict
-- Parte 12 (controle em primeiro lugar): mapa de entrada puro, testado no Lune.
-- Define contextos, ações por botão (controle primeiro; teclado/mouse como equivalente), padrões
-- ajustáveis e a matemática da mira no analógico, das rodas radiais, do cursor com ímã e da
-- máquina de estados que impede entrada travada. A camada de runtime é Controllers/Input.
local InputMap = {}

-- Contextos: um de jogo por vez (infantaria, veículo terrestre, helicóptero); "aim" é uma camada da
-- infantaria (L3/R3 inclinam); mapa, menu e roda ficam por cima e bloqueiam o jogo (Sink).
InputMap.CONTEXTS = {
	global = { priority = 90, game = true, sink = false }, -- vale em todos os contextos de jogo
	infantry = { priority = 100, game = true, sink = false },
	aim = { priority = 110, game = true, sink = false },
	ground_vehicle = { priority = 120, game = true, sink = false },
	helicopter = { priority = 120, game = true, sink = false },
	wheel = { priority = 250, game = false, sink = true },
	map = { priority = 300, game = false, sink = true },
	menu = { priority = 400, game = false, sink = true },
} :: { [string]: { priority: number, game: boolean, sink: boolean } }

-- press: dispara ao apertar (e solta ao soltar); tap/hold: o mesmo botão faz duas coisas, separadas
-- pelo tempo de segurar (Parte 12.2: nunca duplo toque em combate).
export type Press = "press" | "tap" | "hold"
export type Action = {
	id: string,
	ctx: string,
	pad: string?, -- nome do Enum.KeyCode do controle
	padPress: Press,
	key: string?, -- nome do Enum.KeyCode do teclado/mouse
	keyPress: Press,
	seat: string?, -- em veículos: "driver" | "gunner" | "commander" | "door" | nil (qualquer)
	label: string,
}

local A: { Action } = {}
local function act(
	id: string,
	ctx: string,
	pad: string?,
	padPress: Press,
	key: string?,
	keyPress: Press,
	label: string,
	seat: string?
)
	table.insert(A, {
		id = id,
		ctx = ctx,
		pad = pad,
		padPress = padPress,
		key = key,
		keyPress = keyPress,
		label = label,
		seat = seat,
	})
end

-- Infantaria (Parte 12.2). Mover e olhar ficam com o PlayerModule/CameraLook. O pulo continua no
-- PlayerModule; "jump" só escuta o mesmo botão para o contextual (transpor/escalar, levantar).
act("sprint", "infantry", "ButtonL3", "press", "LeftShift", "press", "Correr")
act("jump", "infantry", "ButtonA", "press", "Space", "press", "Pular / transpor")
act("melee", "infantry", "ButtonR3", "press", "MouseMiddleButton", "press", "Corpo a corpo")
act("aim", "infantry", "ButtonL2", "press", "MouseRightButton", "press", "Mirar")
act("fire", "infantry", "ButtonR2", "press", "MouseLeftButton", "press", "Atirar")
act("last_item", "infantry", "ButtonL1", "tap", "X", "tap", "Último item")
act("equip_wheel", "infantry", "ButtonL1", "hold", "X", "hold", "Roda de equipamento")
act("mark", "infantry", "ButtonR1", "tap", "Z", "tap", "Marcar")
act("comm_wheel", "infantry", "ButtonR1", "hold", "Z", "hold", "Roda de comunicação")
act("crouch", "infantry", "ButtonB", "tap", "C", "tap", "Agachar")
act("prone", "infantry", "ButtonB", "hold", "C", "hold", "Deitar")
act("reload", "infantry", "ButtonX", "tap", "R", "press", "Recarregar")
act("interact", "infantry", "ButtonX", "hold", "F", "hold", "Interagir")
-- 2026-11-13 ("não consigo puxar arma e selecionar os itens"): Y troca entre as armas; no teclado,
-- as teclas 1 a 0 escolhem a vaga direto (Shared/Equipar: 1 principal, 2 pistola, 3 granada, 4
-- fumaça, 5 bandagem, 6 torniquete, 7 binóculo, 8 pá, 9 construir, 0 ferramenta do papel) e a roda
-- do mouse troca de arma (Controllers/Input). No controle os itens seguem na roda de equipamento (LB).
act("swap_weapon", "infantry", "ButtonY", "tap", nil, "press", "Trocar arma")
act("bayonet", "infantry", "ButtonY", "hold", "K", "press", "Baioneta")
act("slot_1", "infantry", nil, "press", "One", "press", "Arma principal")
act("slot_2", "infantry", nil, "press", "Two", "press", "Arma secundária")
act("slot_3", "infantry", nil, "press", "Three", "press", "Granada")
act("slot_4", "infantry", nil, "press", "Four", "press", "Fumaça")
act("slot_5", "infantry", nil, "press", "Five", "press", "Bandagem")
act("slot_6", "infantry", nil, "press", "Six", "press", "Torniquete")
act("slot_7", "infantry", nil, "press", "Seven", "press", "Binóculo")
act("slot_8", "infantry", nil, "press", "Eight", "press", "Pá de trincheira")
act("slot_9", "infantry", nil, "press", "Nine", "press", "Construir")
act("slot_0", "infantry", nil, "press", "Zero", "press", "Ferramenta do papel")
-- Direcional ↑ e →: tocar mantém a função da Parte 12 (binóculo, canal de rádio); segurar controla a
-- câmera de 3ª pessoa (pedido do dono, 2026-11-11). No teclado, O e I.
act("binoculars", "infantry", "DPadUp", "tap", "B", "press", "Binóculo")
act("shoulder_swap", "infantry", "DPadUp", "hold", "I", "press", "Trocar ombro (3ª pessoa)")
act("quick_bandage", "infantry", "DPadDown", "tap", "G", "press", "Bandagem rápida")
-- Rádio do squad (2026-11-12): segurar para falar com o squad em qualquer lugar (Controllers/Voz.client).
-- No controle não sobrava botão: ↓ tocar segue a bandagem rápida e segurar abre o rádio. No teclado,
-- Caps Lock (B é o binóculo; N e J são atalhos do CommanderController; L, da loja).
act("radio_talk", "infantry", "DPadDown", "hold", "CapsLock", "press", "Rádio do squad (segurar)")
act("fire_mode", "infantry", "DPadLeft", "tap", "V", "tap", "Seletor de tiro")
act("zeroing", "infantry", "DPadLeft", "hold", "V", "hold", "Alça de mira")
act("radio_channel", "infantry", "DPadRight", "tap", "U", "press", "Canal de rádio")
act("view_toggle", "infantry", "DPadRight", "hold", "O", "press", "1ª / 3ª pessoa")
act("map", "global", "ButtonSelect", "tap", "M", "press", "Mapa tático")
act("game_menu", "global", "ButtonSelect", "hold", "P", "press", "Menu do jogo")
act("give_up", "infantry", nil, "press", "H", "press", "Desistir (caído: segure B)")
act("tourniquet", "infantry", nil, "press", "T", "press", "Torniquete (também na roda)")
-- D-99 (inclinar do Front 44): Q/E no teclado a qualquer hora a pé, segurando. Antes ficavam só na
-- camada de mira e sem mirar a tecla não chegava ("os botões de se inclinar não estão funcionando").
act("lean_left", "infantry", nil, "press", "Q", "press", "Inclinar à esquerda")
act("lean_right", "infantry", nil, "press", "E", "press", "Inclinar à direita")
-- Camada de mira: L3/R3 (afundar os analógicos) inclinam enquanto mira, a pedido do usuário (D-69):
-- no controle não sobra botão fora da mira (L3 corre, R3 é o corpo a corpo, o direcional tem
-- tocar/segurar). LB prende a respiração; RB segue marcando. O teclado usa o Q/E da infantaria.
act("lean_left", "aim", "ButtonL3", "press", nil, "press", "Inclinar à esquerda")
act("lean_right", "aim", "ButtonR3", "press", nil, "press", "Inclinar à direita")
act("hold_breath", "aim", "ButtonL1", "press", "LeftShift", "press", "Prender a respiração")

-- Veículo terrestre (Parte 12.3). Direção: analógico esquerdo (ou A/D); acelerar/frear: gatilhos
-- (ou W/S) lidos como eixo no VehicleController.
act("v_fire", "ground_vehicle", "ButtonR2", "press", "MouseLeftButton", "press", "Tiro principal", "gunner")
act("v_optic", "ground_vehicle", "ButtonL2", "press", "MouseRightButton", "press", "Ótica / zoom", "gunner")
act("v_coax", "ground_vehicle", "ButtonR1", "press", "F", "press", "Metralhadora coaxial", "gunner")
act("v_ammo", "ground_vehicle", "ButtonX", "press", "X", "press", "Trocar munição / recarregar", "gunner")
act("v_binoculars", "ground_vehicle", "ButtonL2", "press", "MouseRightButton", "press", "Binóculo", "commander")
act("v_mark", "ground_vehicle", "ButtonR1", "press", "F", "press", "Marcar alvo", "commander")
act("v_door_fire", "ground_vehicle", "ButtonR2", "press", "MouseLeftButton", "press", "Atirar", "door")
act("v_switch_seat", "ground_vehicle", "ButtonY", "hold", "C", "press", "Trocar de assento")
act("v_exit", "ground_vehicle", "ButtonB", "hold", "Y", "press", "Sair")
act("radio_talk", "ground_vehicle", "DPadDown", "hold", "CapsLock", "press", "Rádio do squad (segurar)")
-- Helicóptero. Cíclico: analógico esquerdo (WASD); coletivo: RT/LT (Espaço/Ctrl) como eixo.
act("h_pedal_left", "helicopter", "ButtonL1", "press", "Q", "press", "Pedal esquerdo", "driver")
act("h_pedal_right", "helicopter", "ButtonR1", "press", "E", "press", "Pedal direito", "driver")
act("h_stabilize", "helicopter", "ButtonA", "hold", "R", "press", "Estabilizar pairado", "driver")
act("v_door_fire", "helicopter", "ButtonR2", "press", "MouseLeftButton", "press", "Atirar", "door")
act("v_optic", "helicopter", "ButtonL2", "press", "MouseRightButton", "press", "Zoom leve", "door")
act("v_switch_seat", "helicopter", "ButtonY", "hold", "C", "press", "Trocar de assento")
act("v_exit", "helicopter", "ButtonB", "hold", "Y", "press", "Sair")
act("radio_talk", "helicopter", "DPadDown", "hold", "CapsLock", "press", "Rádio do squad (segurar)")

-- Roda radial: soltar o botão confirma; B cancela.
act("wheel_cancel", "wheel", "ButtonB", "press", "Backspace", "press", "Cancelar")
-- Mapa e spawn (Parte 12.5). Cursor: analógico esquerdo; zoom: analógico direito.
act("map_prev", "map", "ButtonL1", "press", "Q", "press", "Ponto anterior")
act("map_next", "map", "ButtonR1", "press", "E", "press", "Próximo ponto")
act("map_select", "map", "ButtonA", "press", "Return", "press", "Escolher")
act("map_mark", "map", "ButtonX", "press", "X", "press", "Marcar")
act("map_back", "map", "ButtonB", "press", "M", "press", "Fechar / voltar")
act("map_role", "map", "ButtonY", "press", "R", "press", "Trocar de papel")
act("map_close", "map", "ButtonSelect", "press", nil, "press", "Fechar mapa")
-- Menus: A confirma e B volta (navegação do Roblox); LB/RB abas; LT/RT sub-abas.
act("ui_back", "menu", "ButtonB", "press", "Backspace", "press", "Voltar")
act("ui_tab_prev", "menu", "ButtonL1", "press", "Q", "press", "Aba anterior")
act("ui_tab_next", "menu", "ButtonR1", "press", "E", "press", "Próxima aba")
act("ui_sub_prev", "menu", "ButtonL2", "press", "Z", "press", "Sub-aba anterior")
act("ui_sub_next", "menu", "ButtonR2", "press", "C", "press", "Próxima sub-aba")

InputMap.ACTIONS = A

-- Botões que o Roblox reserva (Parte 12.1): Start abre o menu do Roblox e nunca é usado.
InputMap.RESERVED = { ButtonStart = true }
-- Select só onde a navegação automática da interface está desligada (mapa e jogo).
InputMap.SELECT_OK = { global = true, map = true }

export type Settings = {
	holdTime: number,
	triggerThreshold: number,
	moveInner: number,
	moveOuter: number,
	lookInner: number,
	lookOuter: number,
	curve: string,
	sensHipX: number,
	sensHipY: number,
	sensAdsX: number,
	sensAdsY: number,
	sensScopeX: number,
	sensScopeY: number,
	turnAccel: boolean,
	invertY: boolean,
	swapSticks: boolean,
	swapTriggers: boolean,
	aimAssist: string,
	aimToggle: boolean,
	-- 2026-11-13: recarga automática quando o carregador esvazia (WeaponController: no toque e no
	-- controle; no teclado, como no Front 44, só ao apertar o gatilho vazio, o que vale sempre)
	autoReload: boolean,
	sprintToggle: boolean,
	wheelToggle: boolean,
	hapticFire: string,
	hapticDamage: string,
	fov: number, -- campo de visão base em graus (acessibilidade)
	colorblind: string, -- "off" | "protan" | "deutan" | "tritan" (cor dos traçantes)
	captions: boolean, -- legendas de som
	thirdPerson: boolean, -- câmera de ombro (3ª pessoa) fora da mira
	shoulderLeft: boolean, -- 3ª pessoa: ombro esquerdo
	remap: { [string]: string }, -- "ctx.actionId" -> KeyCode do controle
	-- D-82: teclado e mouse, gráficos e cursor virtual
	keymap: { [string]: string }, -- "ctx.actionId" -> KeyCode do teclado/mouse
	mouseSens: number, -- mouse no quadril (multiplica a sensibilidade do Roblox)
	mouseAds: number, -- fração do mouse apontando (mira de ferro)
	mouseScope: number, -- fração do mouse na luneta/binóculo
	virtualCursor: boolean, -- cursor virtual no analógico esquerdo nos menus
	gfxDetail: string, -- "high" | "medium" | "low": densidade de efeitos e alcance do detalhe
	gfxShadows: boolean, -- sombras do sol
	gfxPlantShadows: boolean, -- sombra das árvores e da vegetação (Graficos.client); padrão desligada
	gfxPost: string, -- "full" | "light" | "off": brilho, raios de sol e correção de cor
	gfxBrightness: number, -- ajuste de brilho (−0,2 a 0,2)
	lang: string, -- D-84: "auto" (idioma da conta) | "pt" | "en" | "es" | "vi"
	-- volume dos SoundGroups do AudioController (VT65Efeitos, VT65Ambiente, VT65Musica), 0 a 1
	volEffects: number,
	volAmbient: number,
	volMusic: number,
	-- movimento da câmera (balanço da passada, inércia da cabeça, inclinação nas curvas), 0 a 1;
	-- lido pelo Movement.client (acessibilidade: enjoo de movimento)
	cameraBob: number,
	-- coluna de comandos na lateral da tela (Controllers/PainelComandos); booleana, o validate saneia
	hintsPanel: boolean,
	-- Parte 13 (celular e tablet; Shared/Toque, Controllers/ToqueHud e EditorHud)
	touchAimToggle: boolean, -- mirar no toque: um toque liga, outro desliga (false: segurar)
	gyroMode: string, -- "off" | "aim" (só mirando) | "always"
	gyroSens: number,
	touchLookSens: number, -- olhar pelo arrasto (quadril)
	touchAdsSens: number, -- mira de ferro
	touchScopeSens: number, -- luneta/binóculo
	touchAccel: boolean, -- arrasto rápido gira mais
	touchOpacity: number, -- opacidade geral dos botões
	touchLayout: string, -- "two" | "three" | "four" | "custom1" | "custom2" | "custom3"
	touchMirror: boolean, -- canhoto: layout espelhado
	touchCustom: { [string]: { [string]: TouchSlot } }, -- até 3 layouts próprios (sanitizeTouchCustom)
	touchAutoVault: boolean, -- correndo contra o obstáculo, transpõe sozinho
	-- v39 (Shared/Toque, Controllers/ToqueAuto): automáticos do toque, cada um desligável
	touchAutoLean: boolean, -- mirando colado numa quina, inclina para o lado aberto
	touchAutoPickup: boolean, -- parado junto da caixa de munição ou do caixote, pega/abre sozinho
	touchAutoBreath: boolean, -- na luneta, prende a respiração sozinho (solta antes de cansar)
	touchAssist: boolean, -- fricção e ímã leve na mira de ferro/luneta (só toque)
	touchAutoFire: boolean, -- mirando com a mira no inimigo à vista, atira sozinho (padrão: desligado)
	batterySaver: boolean, -- economia de bateria (lido pelo agente de desempenho)
}

-- Um botão de um layout próprio de toque: centro (frações da área segura, sempre o lado destro),
-- escala do editor (60–150%) e opacidade própria; on = mostrar (botões opcionais).
export type TouchSlot = { x: number, y: number, scale: number, alpha: number, on: boolean? }

InputMap.DEFAULTS = {
	holdTime = 0.3,
	triggerThreshold = 0.15,
	moveInner = 0.15,
	moveOuter = 0.95,
	lookInner = 0.12,
	lookOuter = 0.95,
	curve = "exponential",
	sensHipX = 1.0,
	sensHipY = 0.85,
	sensAdsX = 0.55,
	sensAdsY = 0.5,
	sensScopeX = 0.3,
	sensScopeY = 0.28,
	turnAccel = true,
	invertY = false,
	swapSticks = false,
	swapTriggers = false,
	aimAssist = "minimal",
	aimToggle = false,
	autoReload = true,
	sprintToggle = true,
	wheelToggle = false,
	hapticFire = "normal",
	hapticDamage = "normal",
	fov = 70,
	colorblind = "off",
	captions = false,
	thirdPerson = false,
	shoulderLeft = false,
	remap = {},
	keymap = {},
	mouseSens = 1.0,
	mouseAds = 0.7,
	mouseScope = 0.45,
	virtualCursor = false,
	gfxDetail = "high",
	gfxShadows = true,
	gfxPlantShadows = false, -- pedido do agente do mapa (2026-11-12): sombra das plantas pesa
	gfxPost = "light", -- era "full" (2026-11-12: o leve é o padrão; o completo fica na opção)
	gfxBrightness = 0,
	lang = "auto",
	volEffects = 0.5,
	volAmbient = 0.6,
	volMusic = 0.35,
	cameraBob = 1,
	hintsPanel = true,
	touchAimToggle = true,
	gyroMode = "off",
	gyroSens = 1,
	touchLookSens = 1,
	touchAdsSens = 0.6,
	touchScopeSens = 0.4,
	touchAccel = false,
	touchOpacity = 0.75,
	touchLayout = "two",
	touchMirror = false,
	touchCustom = {},
	touchAutoVault = true,
	touchAutoLean = true,
	touchAutoPickup = true,
	touchAutoBreath = true,
	touchAssist = true,
	touchAutoFire = false,
	batterySaver = false,
} :: Settings

-- Configurações que mudam os botões (o runtime refaz os bindings só quando uma delas muda).
InputMap.BINDING_KEYS = { remap = true, swapTriggers = true, keymap = true } :: { [string]: boolean }

-- Teclas que não podem receber ação (D-82): Esc abre o menu do Roblox, WASD andam (PlayerModule),
-- Tab é a lista de jogadores, / abre o chat, F9 o console, F11/F12 tela cheia e gravação.
InputMap.KEY_RESERVED = {
	Escape = true,
	W = true,
	A = true,
	S = true,
	D = true,
	Tab = true,
	Slash = true,
	F9 = true,
	F11 = true,
	F12 = true,
	Print = true,
	Unknown = true,
} :: { [string]: boolean }

local RANGES: { [string]: { number } } = {
	holdTime = { 0.2, 0.6 },
	triggerThreshold = { 0.02, 0.9 },
	moveInner = { 0, 0.5 },
	moveOuter = { 0.6, 1 },
	lookInner = { 0, 0.5 },
	lookOuter = { 0.6, 1 },
	sensHipX = { 0.1, 4 },
	sensHipY = { 0.1, 4 },
	sensAdsX = { 0.05, 4 },
	sensAdsY = { 0.05, 4 },
	sensScopeX = { 0.05, 4 },
	sensScopeY = { 0.05, 4 },
	fov = { 60, 90 },
	mouseSens = { 0.1, 3 },
	mouseAds = { 0.1, 1.5 },
	mouseScope = { 0.05, 1.5 },
	gfxBrightness = { -0.2, 0.2 },
	volEffects = { 0, 1 },
	volAmbient = { 0, 1 },
	volMusic = { 0, 1 },
	cameraBob = { 0, 1 },
	gyroSens = { 0.2, 3 },
	touchLookSens = { 0.2, 3 },
	touchAdsSens = { 0.1, 2 },
	touchScopeSens = { 0.1, 2 },
	touchOpacity = { 0.2, 1 },
}
local CHOICES: { [string]: { [string]: boolean } } = {
	gyroMode = { off = true, aim = true, always = true },
	touchLayout = { two = true, three = true, four = true, custom1 = true, custom2 = true, custom3 = true },
	gfxDetail = { high = true, medium = true, low = true },
	gfxPost = { full = true, light = true, off = true },
	lang = { auto = true, pt = true, en = true, es = true, vi = true },
	curve = { linear = true, exponential = true, dynamic = true },
	aimAssist = { minimal = true, off = true },
	hapticFire = { off = true, low = true, normal = true },
	hapticDamage = { off = true, low = true, normal = true },
	colorblind = { off = true, protan = true, deutan = true, tritan = true },
}

-- Layouts próprios do toque (Parte 13): só "custom1".."custom3"; em cada um até 40 botões de nome
-- curto (letras, números e _), centro preso em 0..1, escala 0,6–1,5, opacidade 0,1–1, "on"
-- booleano. Lixo (tipo errado, NaN, nome estranho) sai; layout vazio some.
InputMap.TOUCH_CUSTOM_SLOTS = { "custom1", "custom2", "custom3" }

local function num(v: any, lo: number, hi: number, def: number): number
	if type(v) ~= "number" or v ~= v then
		return def
	end
	return math.clamp(v, lo, hi)
end

function InputMap.sanitizeTouchCustom(raw: any): { [string]: { [string]: TouchSlot } }
	local out: { [string]: { [string]: TouchSlot } } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, name in InputMap.TOUCH_CUSTOM_SLOTS do
		local lay = raw[name]
		if type(lay) == "table" then
			local t: { [string]: TouchSlot } = {}
			local n = 0
			for id, e in lay do
				if
					type(id) == "string"
					and #id <= 24
					and string.match(id, "^[%w_]+$") ~= nil
					and type(e) == "table"
					and type(e.x) == "number"
					and type(e.y) == "number"
					and e.x == e.x
					and e.y == e.y
				then
					n += 1
					if n > 40 then
						break
					end
					t[id] = {
						x = math.clamp(e.x, 0, 1),
						y = math.clamp(e.y, 0, 1),
						scale = num(e.scale, 0.6, 1.5, 1),
						alpha = num(e.alpha, 0.1, 1, 1),
						on = if type(e.on) == "boolean" then e.on else nil,
					}
				end
			end
			if next(t) ~= nil then
				out[name] = t
			end
		end
	end
	return out
end

-- Saneia configurações vindas do cliente ou do DataStore (o servidor também chama).
function InputMap.validate(raw: any): Settings
	local out = table.clone(InputMap.DEFAULTS) :: any
	out.remap = {}
	out.keymap = {}
	out.touchCustom = {}
	if type(raw) ~= "table" then
		return out
	end
	out.touchCustom = InputMap.sanitizeTouchCustom(raw.touchCustom)
	for k, v in raw do
		local def = (InputMap.DEFAULTS :: any)[k]
		if type(k) ~= "string" or def == nil then
			continue
		end
		if RANGES[k] and type(v) == "number" and v == v then
			out[k] = math.clamp(v, RANGES[k][1], RANGES[k][2])
		elseif CHOICES[k] and type(v) == "string" and CHOICES[k][v] then
			out[k] = v
		elseif type(def) == "boolean" and type(v) == "boolean" then
			out[k] = v
		end
	end
	if type(raw.remap) == "table" then
		local n = 0
		for k, v in raw.remap do
			if type(k) == "string" and type(v) == "string" and #k < 48 and #v < 32 and not InputMap.RESERVED[v] then
				n += 1
				if n > 80 then
					break
				end
				out.remap[k] = v
			end
		end
	end
	if type(raw.keymap) == "table" then
		local n = 0
		for k, v in raw.keymap do
			if type(k) == "string" and type(v) == "string" and #k < 48 and #v < 32 and not InputMap.KEY_RESERVED[v] then
				n += 1
				if n > 80 then
					break
				end
				out.keymap[k] = v
			end
		end
	end
	if out.moveOuter <= out.moveInner + 0.1 then
		out.moveOuter = math.min(1, out.moveInner + 0.3)
	end
	if out.lookOuter <= out.lookInner + 0.1 then
		out.lookOuter = math.min(1, out.lookInner + 0.3)
	end
	return out
end

-- Botão de controle de uma ação, com remapeamento do jogador.
function InputMap.padFor(a: Action, s: Settings?): string?
	local r = s and s.remap[a.ctx .. "." .. a.id]
	return r or a.pad
end

-- Tecla (ou botão do mouse) de uma ação, com a troca feita pelo jogador (D-82).
function InputMap.keyFor(a: Action, s: Settings?): string?
	local r = s and s.keymap and s.keymap[a.ctx .. "." .. a.id]
	return r or a.key
end

-- Contextos que valem juntos (o global entra em todos os de jogo; a mira se soma à infantaria).
function InputMap.layers(ctx: string): { string }
	if ctx == "aim" then
		return { "aim", "infantry", "global" }
	elseif InputMap.CONTEXTS[ctx] and InputMap.CONTEXTS[ctx].game then
		return { ctx, "global" }
	end
	return { ctx }
end

-- Na troca de contexto, uma tecla apertada continua valendo se TODAS as ações dela existem nas
-- camadas do contexto novo (ex.: o botão direito da mira, da infantaria, vale na mira). Se não,
-- ela é solta e fica consumida até o jogador soltá-la (o M que abriu o mapa não o fecha).
function InputMap.survives(actions: { Action }, newCtx: string): boolean
	local keep: { [string]: boolean } = {}
	for _, c in InputMap.layers(newCtx) do
		keep[c] = true
	end
	for _, a in actions do
		if not keep[a.ctx] then
			return false
		end
	end
	return true
end

-- Conflitos: dentro de cada pilha de camadas, o mesmo botão (no mesmo assento ou em "qualquer
-- assento") não pode ter duas ações do mesmo tipo, nem "press" junto com tap/hold. Na mira, a
-- camada de cima vence de propósito (LB/RB inclinam), então só se compara dentro da camada.
local function conflictsBy(s: Settings?, keyboard: boolean): { string }
	local out = {}
	for ctx in InputMap.CONTEXTS do
		local layers = if ctx == "aim" then { "aim" } else InputMap.layers(ctx)
		local groups: { [string]: { Action } } = {}
		for _, a in InputMap.ACTIONS do
			if table.find(layers, a.ctx) then
				local code = if keyboard then InputMap.keyFor(a, s) else InputMap.padFor(a, s)
				if code then
					groups[code] = groups[code] or {}
					table.insert(groups[code], a)
				end
			end
		end
		for code, list in groups do
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = list[i], list[j]
					local pa = if keyboard then a.keyPress else a.padPress
					local pb = if keyboard then b.keyPress else b.padPress
					local sameSeat = a.seat == nil or b.seat == nil or a.seat == b.seat
					local clash = pa == pb or pa == "press" or pb == "press"
					if sameSeat and clash then
						table.insert(out, string.format("%s|%s: %s x %s", ctx, code, a.id, b.id))
					end
				end
			end
		end
	end
	return out
end

function InputMap.conflicts(s: Settings?): { string }
	return conflictsBy(s, false)
end

-- O mesmo para o teclado e o mouse (D-82).
function InputMap.keyConflicts(s: Settings?): { string }
	return conflictsBy(s, true)
end

-- ===== analógicos =====

-- Zona morta RADIAL interna e externa (Parte 12.4): diagonais corretas, saída reescalada para 0..1.
function InputMap.radialDeadzone(x: number, y: number, inner: number, outer: number): (number, number)
	local m = math.sqrt(x * x + y * y)
	if m <= inner or m == 0 then
		return 0, 0
	end
	local scaled = math.clamp((m - inner) / math.max(outer - inner, 1e-3), 0, 1)
	return x / m * scaled, y / m * scaled
end

-- Curva de resposta sobre a magnitude (0..1).
function InputMap.curve(m: number, kind: string): number
	m = math.clamp(m, 0, 1)
	if kind == "linear" then
		return m
	elseif kind == "dynamic" then
		return 0.5 * m + 0.5 * m * m * m -- fino no centro, rápido nas bordas
	end
	return m * m -- exponencial (padrão)
end

InputMap.LOOK_DEG_S = 200 -- giro máximo no quadril, sensibilidade 1 (design)
InputMap.TURN_BOOST = 1.0 -- +100% de giro após 0,5 s com o analógico no máximo
InputMap.TURN_RAMP_S = 0.5

export type LookState = { edgeT: number }

-- Passo de olhar (graus de guinada e arfagem) a partir do analógico direito cru.
-- mode: "hip" | "ads" | "scope". A aceleração de giro só vale no quadril.
function InputMap.lookStep(x: number, y: number, dt: number, s: Settings, mode: string, st: LookState): (number, number)
	local dx, dy = InputMap.radialDeadzone(x, y, s.lookInner, s.lookOuter)
	local m = math.sqrt(dx * dx + dy * dy)
	if m == 0 then
		st.edgeT = 0
		return 0, 0
	end
	local cm = InputMap.curve(m, s.curve)
	local ux, uy = dx / m * cm, dy / m * cm
	local sx, sy = s.sensHipX, s.sensHipY
	if mode == "ads" then
		sx, sy = s.sensAdsX, s.sensAdsY
	elseif mode == "scope" then
		sx, sy = s.sensScopeX, s.sensScopeY
	end
	local boost = 1
	if s.turnAccel and mode == "hip" and m >= 0.98 then
		st.edgeT += dt
		boost = 1 + InputMap.TURN_BOOST * math.min(st.edgeT / InputMap.TURN_RAMP_S, 1)
	else
		st.edgeT = 0
	end
	local yaw = ux * InputMap.LOOK_DEG_S * sx * boost * dt
	local pitch = uy * InputMap.LOOK_DEG_S * sy * dt * (if s.invertY then -1 else 1)
	return yaw, pitch
end

-- Gatilho com limiar ajustável: 0 abaixo do limiar, reescalado acima.
function InputMap.trigger(z: number, threshold: number): number
	if z <= threshold then
		return 0
	end
	return math.clamp((z - threshold) / math.max(1 - threshold, 1e-3), 0, 1)
end

-- ===== assistência de mira (só controle) =====
InputMap.ASSIST_MAX = 0.3 -- desaceleração máxima (30%)
InputMap.ASSIST_RANGE_M = 150

-- Multiplicador do giro (1 = sem efeito, mínimo 0,7). Só com mira de ferro/luneta, alvo visível,
-- até 150 m. Nunca puxa nem gruda: só reduz a velocidade enquanto a mira passa sobre o alvo.
function InputMap.assistFactor(
	setting: string,
	mode: string,
	distM: number,
	angleDeg: number,
	visible: boolean,
	targetRadiusM: number
): number
	if setting ~= "minimal" or mode == "hip" or not visible or distM > InputMap.ASSIST_RANGE_M or distM <= 0 then
		return 1
	end
	local cone = math.deg(math.atan(targetRadiusM / distM)) * 1.5 + 0.5
	if angleDeg >= cone then
		return 1
	end
	return 1 - InputMap.ASSIST_MAX * (1 - angleDeg / cone)
end

-- ===== rodas radiais =====
InputMap.WHEEL_DEADZONE = 0.4

-- Índice do item (1 = topo, sentido horário) para o analógico em (x, y) com y para cima.
function InputMap.wheelIndex(x: number, y: number, n: number, deadzone: number?): number?
	local m = math.sqrt(x * x + y * y)
	if n <= 0 or m < (deadzone or InputMap.WHEEL_DEADZONE) then
		return nil
	end
	local a = math.atan2(x, y) -- 0 no topo, positivo para a direita
	if a < 0 then
		a += 2 * math.pi
	end
	local slice = 2 * math.pi / n
	return math.floor((a + slice / 2) / slice) % n + 1
end

-- ===== cursor com ímã (mapa e spawn) =====
export type MagnetPoint = { id: string, x: number, y: number }

-- Ponto mais próximo dentro do raio (unidades do mapa) ou nil.
function InputMap.magnet(cx: number, cy: number, points: { MagnetPoint }, radius: number): MagnetPoint?
	local best, bestD = nil, radius
	for _, p in points do
		local d = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
		if d <= bestD then
			best, bestD = p, d
		end
	end
	return best
end

-- Próximo/anterior na lista (LB/RB pulam entre pontos de spawn liberados).
function InputMap.cycle(n: number, current: number?, dir: number): number?
	if n <= 0 then
		return nil
	end
	if not current then
		return if dir > 0 then 1 else n
	end
	return (current - 1 + dir) % n + 1
end

-- ===== tocar x segurar =====
function InputMap.pressKind(heldSeconds: number, holdTime: number): string
	return if heldSeconds >= holdTime then "hold" else "tap"
end

-- ===== máquina de estados de entrada (Parte 12.7) =====
export type State = {
	menus: number,
	map: boolean,
	robloxMenu: boolean,
	disconnected: boolean,
	awaitRelease: boolean,
	alive: boolean,
	downed: boolean,
	vehicle: string?, -- "ground_vehicle" | "helicopter" | nil
	aiming: boolean,
	sprinting: boolean,
	lean: number,
	wheel: string?,
	-- Parte 13: o app saiu de foco (segundo plano, ligação, notificação, outra janela)
	unfocused: boolean,
}

function InputMap.newState(): State
	return {
		unfocused = false,
		menus = 0,
		map = false,
		robloxMenu = false,
		disconnected = false,
		awaitRelease = false,
		alive = true,
		downed = false,
		vehicle = nil,
		aiming = false,
		sprinting = false,
		lean = 0,
		wheel = nil,
	}
end

-- Cancela tudo que é "segurado" no jogo; devolve o que foi cancelado.
local function cancelHolds(s: State): { string }
	local out = {}
	if s.aiming then
		s.aiming = false
		table.insert(out, "aim")
	end
	if s.sprinting then
		s.sprinting = false
		table.insert(out, "sprint")
	end
	if s.lean ~= 0 then
		s.lean = 0
		table.insert(out, "lean")
	end
	if s.wheel then
		s.wheel = nil
		table.insert(out, "wheel")
	end
	return out
end

-- Aplica um evento e devolve as ações canceladas. Toda volta ao jogo exige soltar todos os botões
-- (o runtime relê GetGamepadState e manda "buttons_released") antes de aceitar comandos.
function InputMap.event(s: State, ev: string, arg: any?): { string }
	if ev == "menu_open" then
		s.menus += 1
		return cancelHolds(s)
	elseif ev == "menu_close" then
		s.menus = math.max(0, s.menus - 1)
		s.awaitRelease = true
	elseif ev == "map_open" then
		s.map = true
		return cancelHolds(s)
	elseif ev == "map_close" then
		s.map = false
		s.awaitRelease = true
	elseif ev == "roblox_menu_open" then
		s.robloxMenu = true
		return cancelHolds(s)
	elseif ev == "roblox_menu_close" then
		s.robloxMenu = false
		s.awaitRelease = true
	elseif ev == "disconnect" then
		s.disconnected = true
		return cancelHolds(s)
	elseif ev == "reconnect" then
		s.disconnected = false
		s.awaitRelease = true
	elseif ev == "focus_lost" then
		-- Parte 13: segundo plano, ligação, notificação: o que estava segurado é solto (o dedo
		-- some sem o fim do toque)
		s.unfocused = true
		return cancelHolds(s)
	elseif ev == "focus_back" then
		s.unfocused = false
		s.awaitRelease = true -- relê o estado: só volta com tudo solto
	elseif ev == "die" then
		s.alive, s.downed = false, false
		s.vehicle = nil
		return cancelHolds(s)
	elseif ev == "respawn" then
		s.alive, s.downed = true, false
		s.awaitRelease = true
		return cancelHolds(s)
	elseif ev == "downed" then
		s.downed = true
		return cancelHolds(s)
	elseif ev == "revived" then
		s.downed = false
		s.awaitRelease = true
	elseif ev == "vehicle_enter" then
		s.vehicle = arg
		s.awaitRelease = true
		return cancelHolds(s)
	elseif ev == "vehicle_exit" then
		s.vehicle = nil
		s.awaitRelease = true
		return cancelHolds(s)
	elseif ev == "seat_switch" then
		s.awaitRelease = true
		return cancelHolds(s)
	elseif ev == "tunnel_enter" then
		-- teto baixo: correr e inclinar não fazem sentido; mira continua
		local out = {}
		if s.sprinting then
			s.sprinting = false
			table.insert(out, "sprint")
		end
		if s.lean ~= 0 then
			s.lean = 0
			table.insert(out, "lean")
		end
		return out
	elseif ev == "buttons_released" then
		s.awaitRelease = false
	elseif ev == "aim" then
		s.aiming = arg == true
	elseif ev == "sprint" then
		s.sprinting = arg == true
	elseif ev == "lean" then
		-- D-99: a pé, mirando ou não (correndo ou deitado o corpo não inclina: Controllers/Inclinar)
		local ok = s.alive and not s.downed and s.vehicle == nil and InputMap.acceptsGame(s)
		s.lean = if arg == 0 or ok then math.clamp(tonumber(arg) or 0, -1, 1) else 0
	elseif ev == "wheel_open" then
		s.wheel = arg
	elseif ev == "wheel_close" then
		s.wheel = nil
	end
	return {}
end

-- Contexto ativo (o de cima vence). As camadas que valem junto vêm de InputMap.layers.
function InputMap.activeContext(s: State): string
	if s.menus > 0 then
		return "menu"
	elseif s.map or not s.alive then
		return "map" -- morto: tela de spawn
	elseif s.wheel then
		return "wheel"
	elseif s.vehicle then
		return s.vehicle :: string
	elseif s.aiming then
		return "aim"
	end
	return "infantry"
end

-- O jogo aceita comandos de jogo agora?
function InputMap.acceptsGame(s: State): boolean
	return not (s.disconnected or s.robloxMenu or s.awaitRelease or s.unfocused or s.menus > 0 or s.map or not s.alive)
end

-- Caído só aceita olhar, desistir e chamar ajuda (roda de comunicação).
InputMap.DOWNED_OK = { give_up = true, comm_wheel = true, mark = true, map = true, game_menu = true }

function InputMap.allowed(s: State, actionId: string): boolean
	if not InputMap.acceptsGame(s) then
		return false
	end
	if s.downed then
		return InputMap.DOWNED_OK[actionId] == true
	end
	return true
end

return InputMap
