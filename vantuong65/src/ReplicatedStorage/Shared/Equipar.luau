--!strict
-- Armas e itens na mão (2026-11-13, pedido do dono: "não consigo puxar arma e selecionar os itens",
-- "os itens como armas e resto não estão aparecendo", "coloque arma secundária para todos").
-- Módulo PURO (tests/luau/itens.luau). Runtime: Controllers/WeaponController (troca e granada na mão),
-- Controllers/ItemView (mãos de 1ª pessoa), Controllers/BarraItens.client (faixa das vagas) e
-- Modules/ArmaNaMao (o que os outros veem).
-- Causa achada: a troca era um ciclo só (tecla 1 / Y) entre as armas do equipamento, e quase todo
-- papel tinha UMA arma: apertar não fazia nada. As teclas 2 a 0 e a roda do mouse não existiam, e os
-- itens só saíam pela roda de equipamento, sem nada na mão até o arremesso.
-- Vagas fixas (memória muscular, como a roda): 1 principal, 2 pistola (o antitanque: 1 pistola, 2
-- lançador), 3 granada, 4 fumaça, 5 bandagem, 6 torniquete, 7 (era o binóculo, D-190), 8 pá, 9
-- construir, 0 ferramenta do papel. Item que não dá agora fica apagado, no lugar.
local Equipar = {}

export type Slot = { n: number, id: string, key: string, label: string, kind: string }

Equipar.SLOTS = {
	{ n = 1, id = "primaria", key = "One", label = "Arma principal", kind = "weapon" },
	{ n = 2, id = "secundaria", key = "Two", label = "Arma secundária", kind = "weapon" },
	{ n = 3, id = "frag", key = "Three", label = "Granada", kind = "grenade" },
	{ n = 4, id = "smoke", key = "Four", label = "Fumaça", kind = "grenade" },
	{ n = 5, id = "bandage", key = "Five", label = "Bandagem", kind = "item" },
	{ n = 6, id = "tourniquet", key = "Six", label = "Torniquete", kind = "item" },
	{ n = 7, id = "binoculars", key = "Seven", label = "Binóculo", kind = "item" },
	{ n = 8, id = "shovel", key = "Eight", label = "Pá de trincheira", kind = "item" },
	{ n = 9, id = "build", key = "Nine", label = "Construir", kind = "item" },
	{ n = 10, id = "role_tool", key = "Zero", label = "Ferramenta do papel", kind = "item" },
} :: { Slot }

-- D-190 (dono: "retire o binóculo das formas de obtenção e uso durante a partida"): o item sai da vaga
-- 7 (a faixa das vagas a esconde e a tecla 7 não faz nada), da roda de equipamento, dos atalhos (a
-- tecla B e a vaga 7 saíram do InputMap) e do tutorial. A vaga 7 fica na lista para os números das
-- outras não mudarem. O código do binóculo (WeaponController, ItemView) fica, travado: a ótica do
-- comandante do veículo é outra coisa (VehicleController, "v_binoculars") e continua.
Equipar.REMOVED = { binoculars = true } :: { [string]: boolean }

-- Pistola de cada lado (Shared/Weapons): M1911A1 nos EUA, Tipo 54 (TT-33 chinesa) no VC.
Equipar.PISTOL = { US = "m1911", VC = "type54" } :: { [string]: string }

-- Lançador do antitanque na mão: a arte que existe (RPG-2 do VC). A bazuca M20 dos EUA ainda não tem
-- modelo (fica "launcher": sem arma de 1ª pessoa até a arte; frente de combate).
Equipar.LAUNCHER_ART = { VC = "rpg2" } :: { [string]: string }

function Equipar.handId(id: string?, faction: string?): string?
	if id == "launcher" then
		return (faction and Equipar.LAUNCHER_ART[faction]) or "launcher"
	end
	return id
end

-- Ação do InputMap da vaga n (teclado): "slot_1" ... "slot_9", "slot_0".
function Equipar.actionOf(n: number): string
	return "slot_" .. tostring(n % 10)
end

-- Vaga da ação (o inverso de actionOf), ou nil.
function Equipar.slotOfAction(id: string): number?
	local d = string.match(id, "^slot_(%d)$")
	if not d then
		return nil
	end
	local n = tonumber(d) :: number
	return if n == 0 then 10 else n
end

-- Armas das vagas: o equipamento do papel (Roles.loadout), com a arma pega do chão no lugar da 1ª
-- (o servidor troca a principal: CombatService), e o lançador do antitanque por último ("launcher").
function Equipar.weapons(loadout: { string }, role: string?, carried: string?): { string }
	local out = table.clone(loadout)
	if carried and carried ~= "" then
		if #out > 0 then
			out[1] = carried
		else
			out = { carried }
		end
	end
	if role == "anti_tank" then
		table.insert(out, "launcher")
	end
	return out
end

-- Próxima arma no ciclo (Y, roda do mouse, botão ARMA do toque); dir = 1 ou −1.
function Equipar.cycle(n: number, cur: number, dir: number): number
	if n <= 0 then
		return 0
	end
	return (math.clamp(cur, 1, n) - 1 + dir) % n + 1
end

-- ===== troca (tempos do Front 44, WeaponData.DrawTime; números de jogo, PLACEHOLDER) =====
-- Guardar a arma da mão leva 40% do saque dela, entre 0,15 e 0,3 s; depois a nova sobe no saque
-- dela. M14 como a Garand, M60/RPD como a MG 42, Tipo 56 como a StG 44, SKS como a G43/SVT, fuzis de
-- ferrolho como a Springfield/Kar98k, M79 como a espingarda M1897, lançador como a bazuca M1A1.
Equipar.DRAW_S = {
	m14 = 0.6,
	m70 = 0.7,
	m60 = 1.0,
	m79 = 0.55,
	m1911 = 0.3,
	type56 = 0.55,
	sks = 0.6,
	rpd = 1.0,
	type54 = 0.3,
	mosin = 0.7,
	launcher = 0.9,
	rpg2 = 0.9,
	win12 = 0.55, -- D-108: como a M1897 do Front 44
	m16 = 0.55, -- D-146: leve, como o Tipo 56
} :: { [string]: number }
Equipar.DRAW_KIND = { rifle = 0.6, mg = 1.0, pistol = 0.3, launcher = 0.9, shotgun = 0.55 } :: { [string]: number }

function Equipar.drawS(id: string?, kind: string?): number
	return (id and Equipar.DRAW_S[id]) or (kind and Equipar.DRAW_KIND[kind]) or 0.6
end

function Equipar.holsterS(id: string?, kind: string?): number
	return math.clamp(Equipar.drawS(id, kind) * 0.4, 0.15, 0.3)
end

-- ===== D-194: a troca como estado (prompt de jogabilidade, item 10) =====
-- Altura da arma pela troca: 0 = em uso, 1 = embaixo, fora da vista. A arma desce, troca lá
-- embaixo e a nova sobe; o dedo só chega ao gatilho no fim da subida (Equipar.trocaFim).
-- - Pedido no meio de outra troca: continua da altura em que a arma está (antes recomeçava de cima e
--   a arma pulava), com a descida que falta (holsterS × (1 − altura)).
-- - Voltar para a arma que está descendo (antes de chegar embaixo) cancela a troca: ela sobe de onde
--   está, no saque dela vezes a altura (trocaVolta).
-- - 3ª pessoa: a mesma curva, mas só sobe quando a arma nova chegou ao corpo (o servidor a põe na
--   mão), ou depois de TROCA_ESPERA_S embaixo (trocaSobe).
export type Troca = {
	t0: number, -- começo
	d0: number, -- altura no começo (0..1)
	hold: number, -- descida que falta (s)
	draw: number, -- subida (s); math.huge = fica embaixo (granada na mão)
	top: number, -- de onde a subida parte (1, ou d0 na volta)
	riseAt: number?, -- começo da subida (nil: esperando a arma nova, só na 3ª pessoa)
}
Equipar.TROCA_ESPERA_S = 0.6

-- as curvas do KnifeView: a descida acelera sem parar no fim; a subida sai e chega suave
local function easeIn(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (2 - x) * 0.5 + x * x * 0.5
end
local function easeIO(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Troca nova a partir da altura de agora. esperar: a subida espera trocaSobe (3ª pessoa).
function Equipar.trocaNova(now: number, down0: number, holsterS: number, drawS: number, esperar: boolean?): Troca
	local d0 = math.clamp(down0, 0, 1)
	local hold = math.max(holsterS, 0) * (1 - d0)
	return {
		t0 = now,
		d0 = d0,
		hold = hold,
		draw = math.max(drawS, 0),
		top = 1,
		riseAt = if esperar then nil else now + hold,
	}
end

-- Cancela a troca: a arma que descia sobe de onde está (drawS = o saque dela).
function Equipar.trocaVolta(now: number, down0: number, drawS: number): Troca
	local d0 = math.clamp(down0, 0, 1)
	return { t0 = now, d0 = d0, hold = 0, draw = math.max(drawS, 0) * d0, top = d0, riseAt = now }
end

-- instante em que a arma chega embaixo (a troca do modelo)
function Equipar.trocaEmbaixo(tr: Troca): number
	return tr.t0 + tr.hold
end

-- 3ª pessoa: a arma nova chegou ao corpo em `at`; a subida começa (nunca antes de chegar embaixo)
function Equipar.trocaSobe(tr: Troca, at: number)
	if tr.riseAt == nil then
		tr.riseAt = math.max(at, tr.t0 + tr.hold)
	end
end

-- começo da subida, contando a espera máxima da 3ª pessoa
local function riseOf(tr: Troca, now: number): number?
	local r = tr.riseAt
	if r == nil and now >= tr.t0 + tr.hold + Equipar.TROCA_ESPERA_S then
		return tr.t0 + tr.hold + Equipar.TROCA_ESPERA_S
	end
	return r
end

-- Altura da arma agora (0..1)
function Equipar.trocaDown(tr: Troca, now: number): number
	local t = now - tr.t0
	if t < 0 then
		return tr.d0
	end
	if t < tr.hold then
		return tr.d0 + (1 - tr.d0) * easeIn(t / tr.hold)
	end
	local top = if tr.hold > 0 then 1 else tr.top
	local r = riseOf(tr, now)
	if r == nil or now < r then
		return top
	end
	if tr.draw <= 0 then
		return 0
	end
	return top * (1 - easeIO((now - r) / tr.draw))
end

-- Fim da troca (a arma pronta), ou nil enquanto a 3ª pessoa espera a arma nova
function Equipar.trocaFim(tr: Troca, now: number): number?
	local r = riseOf(tr, now)
	return if r then r + tr.draw else nil
end

-- A arma da troca está pronta agora?
function Equipar.trocaPronta(tr: Troca?, now: number): boolean
	if not tr then
		return true
	end
	local f = Equipar.trocaFim(tr, now)
	return f ~= nil and now >= f
end

-- ===== o que os outros veem (atributo "Troca" do personagem, posto pelo servidor) =====
-- "t0;d0;hold;draw;alvo;v": t0 no relógio do servidor; alvo = o que vai à mão (id da arma da mão,
-- "frag"/"smoke"); v = "v" na volta, "n" na troca nova. O próprio cliente põe o mesmo texto no
-- atributo local "VT65Troca" (sem esperar a volta do servidor).
export type TrocaVista = { tr: Troca, alvo: string, volta: boolean }

function Equipar.trocaTexto(t0: number, tr: Troca, alvo: string, volta: boolean): string
	return string.format(
		"%.3f;%.3f;%.3f;%.3f;%s;%s",
		t0,
		tr.d0,
		tr.hold,
		math.min(tr.draw, 99),
		alvo,
		if volta then "v" else "n"
	)
end

function Equipar.trocaLer(s: any): TrocaVista?
	if type(s) ~= "string" then
		return nil
	end
	local a, b, c, d, alvo, v = string.match(s, "^([%d%.%-]+);([%d%.]+);([%d%.]+);([%d%.]+);([%w_]*);([vn])$")
	local t0, d0, hold, draw = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if not (t0 and d0 and hold and draw and alvo and v) then
		return nil
	end
	local volta = v == "v"
	local tr = if volta
		then Equipar.trocaVolta(t0, d0, if d0 > 0 then draw / d0 else 0)
		else Equipar.trocaNova(t0, d0, if d0 < 1 then hold / (1 - d0) else 0, draw, true)
	-- d0 = 1 na troca nova: já embaixo (vinha da granada)
	return { tr = tr, alvo = alvo, volta = volta }
end

-- Limites do que o servidor aceita do cliente (s)
Equipar.TROCA_MAX_HOLD = 0.5
Equipar.TROCA_MAX_DRAW = 1.5

-- ===== item que dá para usar agora (mesma regra da roda de equipamento) =====
-- frags/smokes: o que sobra (atributos Frags/Smokes); canBuild: o papel tem alguma construção.
export type Counts = { frags: number, smokes: number }
-- D-108: a ferramenta do suporte é a caixa de munição (Controllers/CaixaMunicao.client: prévia e pôr)
Equipar.ROLE_TOOL = { commander = true, anti_tank = true, medic = true, support = true } :: {
	[string]: boolean,
}

-- D-129: o nome da vaga 0 e da roda pelo papel ("Ferramenta do papel" não dizia o que faz). O
-- antitanque põe o lançador na mão; o médico trata ou reanima o companheiro mais perto.
Equipar.ROLE_TOOL_LABEL = {
	commander = "Ordens",
	anti_tank = "Lançador",
	medic = "Socorrer",
	support = "Caixa de munição",
} :: { [string]: string }

function Equipar.roleToolLabel(role: string?): string
	return (role and Equipar.ROLE_TOOL_LABEL[role]) or "Ferramenta do papel"
end

function Equipar.itemOk(id: string, role: string?, counts: Counts, canBuild: boolean): boolean
	if Equipar.REMOVED[id] then
		return false
	elseif id == "frag" then
		return counts.frags > 0
	elseif id == "smoke" then
		return counts.smokes > 0
	elseif id == "build" then
		return canBuild
	elseif id == "role_tool" then
		return role ~= nil and Equipar.ROLE_TOOL[role] == true
	end
	return true
end

-- ===== granada na mão (Front 44, GrenadeModels.Timing e Controller.startGrenade/releaseGrenade) =====
-- Apertar o gatilho tira o pino e arma o braço; soltar lança (se o braço ainda não armou, lança assim
-- que armar: o movimento nunca pula). Mirando ao soltar: por baixo, curta (força 0,55 do Front 44).
-- O pedido ao servidor sai no começo do lançamento; o servidor solta a granada da mão em releaseS
-- (FieldService.RELEASE_S), o mesmo instante da mão de 1ª pessoa.
Equipar.GRENADE = {
	drawS = 0.3, -- do cinto à mão
	pinS = 0.24, -- o pino sai (Front 44: PinOut 0,24 de 1 s)
	readyS = 0.3, -- braço armado (Front 44: Ready 0,3)
	throwS = 0.8, -- o gesto inteiro do lançamento (FieldService.THROW_S)
	releaseS = 0.4, -- a granada sai da mão (FieldService.RELEASE_S)
	underPower = 0.55, -- por baixo (Front 44: força ~0,55)
	backS = 0.2, -- guardar a granada sem lançar (o pino volta)
}

function Equipar.throwPower(under: boolean): number
	return if under then Equipar.GRENADE.underPower else 1
end

-- fases: "saque", "pronta", "armando", "armada", "lancando", "fim"
export type Hand = {
	kind: string,
	phase: string,
	t0: number, -- começo da fase (os.clock)
	armOnReady: boolean, -- apertou durante o saque
	release: boolean, -- soltou o gatilho (lança assim que armar)
	under: boolean, -- por baixo
	pinOut: boolean,
}

function Equipar.newHand(kind: string, now: number): Hand
	return { kind = kind, phase = "saque", t0 = now, armOnReady = false, release = false, under = false, pinOut = false }
end

-- dedo no gatilho
function Equipar.press(h: Hand, now: number)
	if h.phase == "pronta" then
		h.phase, h.t0 = "armando", now
		h.release = false
	elseif h.phase == "saque" then
		h.armOnReady = true
		h.release = false
	end
end

-- dedo fora do gatilho; under = mirando (por baixo)
function Equipar.release(h: Hand, under: boolean)
	if h.phase == "armando" or h.phase == "armada" or (h.phase == "saque" and h.armOnReady) then
		h.release = true
		h.under = under
	end
end

-- Avança no tempo. Devolve "pin" quando o pino sai, "throw" quando o pedido ao servidor deve sair
-- (uma vez) e "done" quando o gesto acaba (volta para a arma).
function Equipar.handStep(h: Hand, now: number): string?
	local G = Equipar.GRENADE
	if h.phase == "saque" and now - h.t0 >= G.drawS then
		h.t0 = h.t0 + G.drawS
		h.phase = if h.armOnReady then "armando" else "pronta"
	end
	if h.phase == "armando" then
		if not h.pinOut and now - h.t0 >= G.pinS then
			h.pinOut = true
			return "pin"
		end
		if now - h.t0 >= G.readyS then
			h.phase, h.t0 = "armada", h.t0 + G.readyS
		end
	end
	if h.phase == "armada" and h.release then
		h.phase, h.t0 = "lancando", now
		return "throw"
	end
	if h.phase == "lancando" and now - h.t0 >= G.throwS then
		h.phase = "fim"
		return "done"
	end
	return nil
end

-- Tempo na fase (s), para as mãos.
function Equipar.phaseTime(h: Hand, now: number): number
	return math.max(now - h.t0, 0)
end

return Equipar
