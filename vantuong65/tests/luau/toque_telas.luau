--!strict
-- Parte 13 (celular e tablet), agente T2: telas e ações complexas no toque. Lógica pura do
-- Controllers/ToqueTelas e conferências de fonte das telas.
-- Uso, a partir de vantuong65/:  lune run tests/luau/toque_telas.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local S = "../../src/ReplicatedStorage/Shared/"
local ToqueTelas = require("../../" .. C .. "ToqueTelas") :: any
local Logistics = require(S .. "Logistics") :: any
local FieldWork = require(S .. "FieldWork") :: any
local Medical = require(S .. "Medical") :: any
local InputMap = require(S .. "InputMap") :: any

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FALHA " .. name .. ": " .. tostring(err))
	end
end
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.4f vs %.4f", msg or "", a, b))
end

-- ===== dedo gordo =====
test("dedo gordo: o alvo pequeno cresce até o mínimo, centrado; o grande fica igual", function()
	local x, y, w, h = ToqueTelas.expand(100, 100, 20, 20, 48, 48)
	assert(x == 86 and y == 86 and w == 48 and h == 48, "20 px vira 48 em volta do centro")
	local x2, y2, w2, h2 = ToqueTelas.expand(0, 0, 200, 60, 48, 48)
	assert(x2 == 0 and y2 == 0 and w2 == 200 and h2 == 60, "o que já é grande não muda")
end)

test("dedo gordo: o dedo perto pega o botão; longe, nada; entre dois, o mais perto e, empatado, o menor", function()
	-- fechar: x 100..120 (alvo 86..134); salvar: x 128..158 (alvo 119..167); vão de 8 px entre eles
	local rects = {
		{ id = "fechar", x = 100, y = 100, w = 20, h = 20 },
		{ id = "salvar", x = 128, y = 100, w = 30, h = 20 },
	}
	assert(ToqueTelas.pick(95, 95, rects, 48) == "fechar", "na borda do alvo aumentado")
	assert(ToqueTelas.pick(60, 60, rects, 48) == nil, "longe de todos")
	assert(ToqueTelas.pick(121, 110, rects, 48) == "fechar", "no vão, mais perto do pequeno") -- 1 x 7
	assert(ToqueTelas.pick(127, 110, rects, 48) == "salvar", "no vão, mais perto do outro") -- 7 x 1
	assert(ToqueTelas.pick(165, 110, rects, 48) == "salvar", "além da borda, dentro do alvo")
	-- dentro dos dois (sobrepostos): distância 0 nos dois, vence o menor
	local over = {
		{ id = "grande", x = 0, y = 0, w = 200, h = 200 },
		{ id = "pequeno", x = 50, y = 50, w = 10, h = 10 },
	}
	assert(ToqueTelas.pick(55, 55, over, 48) == "pequeno")
	-- botão sem tamanho (escondido, ainda sem layout) nunca é alvo
	assert(ToqueTelas.pick(5, 5, { { id = "zero", x = 0, y = 0, w = 0, h = 0 } }, 48) == nil)
end)

test("toque x arrasto: curto e parado é toque; longo ou andando é arrasto", function()
	assert(ToqueTelas.isTap(0.1, 3, 4))
	assert(not ToqueTelas.isTap(0.1, 30, 0), "andou: arrasto")
	assert(not ToqueTelas.isTap(0.8, 0, 0), "segurou: não é toque")
	assert(ToqueTelas.isTap(ToqueTelas.TAP_S, ToqueTelas.TAP_MOVE_PX, 0), "no limite ainda é toque")
end)

-- ===== mapa =====
test("pinça: o zoom segue a razão dos dedos, preso nos limites", function()
	near(ToqueTelas.pinch(1.5, 100, 200, 1, 8), 3, 1e-9, "dedos afastam 2x")
	near(ToqueTelas.pinch(4, 200, 100, 1, 8), 2, 1e-9, "dedos juntam pela metade")
	near(ToqueTelas.pinch(4, 100, 1000, 1, 8), 8, 1e-9, "teto")
	near(ToqueTelas.pinch(2, 100, 10, 1, 8), 1, 1e-9, "piso")
	near(ToqueTelas.pinch(2, 0, 50, 1, 8), 2, 1e-9, "dedos no mesmo ponto: nada muda")
end)

test("ponto de inserção: o mais perto do dedo dentro do raio; fora do raio, nenhum", function()
	local pts = { { id = "a", x = 100, y = 100 }, { id = "b", x = 130, y = 100 }, { id = "c", x = 400, y = 400 } }
	local p = ToqueTelas.nearest(120, 100, pts, 38)
	assert(p and p.id == "b", "b está a 10, a a 20")
	assert(ToqueTelas.nearest(250, 250, pts, 38) == nil)
end)

test("carta em tela cheia: o retângulo de projeto cobre a tela toda (abaixo da faixa do Roblox)", function()
	-- celular 844 x 390, palco 1280 x 720 escalado por min(844/1280, 390/720) = 0,5417
	local vpW, vpH = 844, 390
	local k = math.min(vpW / 1280, vpH / 720)
	local top = 36
	local x, y, w, h = ToqueTelas.fullRect(vpW, vpH, k, 1280, 720, top, 0)
	-- de volta para a tela: canto do palco + projeto × k
	local ox, oy = vpW / 2 - 1280 * k / 2, vpH / 2 - 720 * k / 2
	near(ox + x * k, 0, 1e-6, "borda esquerda")
	near(ox + (x + w) * k, vpW, 1e-6, "borda direita")
	near(oy + y * k, top, 1e-6, "abaixo da faixa")
	near(oy + (y + h) * k, vpH, 1e-6, "pé da tela")
	assert(x < 0 and w > 1280, "o celular é mais largo que 16:9: a carta passa do palco dos lados")
end)

test("botão de inserir: espera escrita até ficar pronto; bloqueado diz o motivo", function()
	local none = ToqueTelas.spawnButton(nil)
	assert(none.text == "TOQUE NUM PONTO" and not none.ready)
	local w = ToqueTelas.spawnButton({ name = "LZ Norte", wait = 11.2 })
	assert(w.text == "ESPERA 12 s" and w.sub == "LZ Norte" and not w.ready, w.text)
	local b = ToqueTelas.spawnButton({ name = "Vila", blocked = true, why = "inimigo perto" })
	assert(b.text == "BLOQUEADO" and b.sub == "inimigo perto" and not b.ready)
	local e = ToqueTelas.spawnButton({ name = "Squad", ready = false, why = "companheiro em combate" })
	assert(e.text == "ESPERE" and e.sub == "companheiro em combate" and not e.ready)
	local r = ToqueTelas.spawnButton({ name = "QG", wait = 0 })
	assert(r.text == "INSERIR" and r.sub == "QG" and r.ready)
end)

-- ===== 2º toque confirma =====
test("2º toque: o 1º mostra, o 2º no mesmo item confirma; outro item ou tempo esgotado recomeça", function()
	local st = ToqueTelas.newTap2()
	assert(not ToqueTelas.secondTap(st, "medic", 10), "1º toque só mostra")
	assert(ToqueTelas.secondTap(st, "medic", 11), "2º toque confirma")
	assert(not ToqueTelas.secondTap(st, "medic", 12), "depois de confirmar, recomeça")
	assert(not ToqueTelas.secondTap(st, "sniper", 12.5), "outro cartão: só mostra")
	assert(not ToqueTelas.secondTap(st, "sniper", 12.5 + ToqueTelas.SECOND_TAP_S + 0.1), "tempo esgotado")
	assert(ToqueTelas.secondTap(st, "sniper", 17), "agora sim")
end)

-- ===== interagir =====
test("interagir: o prompt do mundo vence o companheiro (como no PC); o mais perto entre prompts", function()
	local prompts = {
		{ key = "caixote", dist = 9, hold = 3, text = "Abrir suprimento", vehicle = false },
		{ key = "arma", dist = 4, hold = 0.6, text = "Pegar M14", vehicle = false },
	}
	local c = ToqueTelas.chooseInteraction(prompts, { downed = true, hurt = true }, true, 5)
	assert(c and c.kind == "prompt" and c.key == "arma" and c.label == "Pegar M14", "o mais perto")
	near(c.hold, 0.6, 1e-9, "o anel enche no HoldDuration")
	local v = ToqueTelas.chooseInteraction(
		{ { key = "m48", dist = 5, hold = 0.4, text = "Entrar", vehicle = true } },
		nil,
		false,
		0
	)
	assert(v and v.label == "ENTRAR" and v.glyph == "►", "veículo")
	local empty =
		ToqueTelas.chooseInteraction({ { key = "p", dist = 1, hold = 0, text = "", vehicle = false } }, nil, false, 0)
	assert(empty and empty.label == "INTERAGIR", "prompt sem texto")
end)

test("interagir: companheiro caído só o médico levanta; ferido: médico trata, os outros fazem curativo", function()
	local downed = { downed = true, hurt = true }
	local hurt = { downed = false, hurt = true }
	local fine = { downed = false, hurt = false }
	local r = ToqueTelas.chooseInteraction({}, downed, true, 0)
	assert(r and r.label == "REANIMAR" and r.op == "revive")
	assert(ToqueTelas.chooseInteraction({}, downed, false, 3) == nil, "o servidor recusa o resto")
	local t = ToqueTelas.chooseInteraction({}, hurt, true, 0)
	assert(t and t.label == "TRATAR" and t.op == "treat")
	local b = ToqueTelas.chooseInteraction({}, hurt, false, 2)
	assert(b and b.label == "CURATIVO" and b.op == "bandage")
	assert(ToqueTelas.chooseInteraction({}, hurt, false, 0) == nil, "sem curativo, nada")
	assert(ToqueTelas.chooseInteraction({}, fine, true, 5) == nil, "ninguém precisa: o botão some")
	assert(ToqueTelas.chooseInteraction({}, nil, true, 5) == nil)
	-- o servidor só aceita reanimar e tratar do médico (MedicalService): os rótulos batem
	assert(Medical.C.reviveTime > 0 and Medical.C.medicTreat > 0)
end)

test("anel de progresso: fração do tempo e segmentos acesos", function()
	near(ToqueTelas.progress(10, 4, 12), 0.5, 1e-9)
	near(ToqueTelas.progress(10, 4, 20), 1, 1e-9, "teto")
	near(ToqueTelas.progress(10, 4, 5), 0, 1e-9, "piso")
	near(ToqueTelas.progress(10, 0, 10), 1, 1e-9, "sem segurar: cheio")
	assert(ToqueTelas.ringLit(0.5, 20) == 10 and ToqueTelas.ringLit(1, 20) == 20 and ToqueTelas.ringLit(0, 20) == 0)
	assert(ToqueTelas.ringLit(0.999, 20) == 19, "só acende o segmento inteiro")
end)

test("lugar do botão contextual sem o HUD do T1: à direita, acima do tiro, dentro da tela", function()
	local W, H, fire, size, m = 844, 354, 100, 72, 16
	local cx, cy = ToqueTelas.interactSlot(W, H, fire, size, m)
	local fy = H - m - fire / 2
	assert(cx > W / 2 and cx + size / 2 <= W, "à direita e dentro")
	assert(cy + size / 2 <= fy - fire / 2, "acima do tiro, sem encostar")
	assert(cy - size / 2 >= 0)
end)

-- ===== construção =====
test("construção: a prévia cai onde o servidor põe (2 m à frente; a pá, 1,5 m) e com o rumo da raiz", function()
	local M = 0.28
	-- a mesma conta do servidor (só leitura): LogisticsService e FieldWorkService
	local logi = fs.readFile("src/ServerScriptService/Modules/LogisticsService.luau")
	assert(string.find(logi, "root.CFrame.LookVector * (2 / M)", 1, true), "obra: 2 m à frente da raiz")
	assert(string.find(logi, "root.CFrame:ToOrientation()", 1, true), "obra: rumo da raiz")
	for id in Logistics.BUILDS do
		local p = ToqueTelas.PREVIEW[id]
		assert(p, "prévia de " .. id)
		assert(p.ahead == 2, id .. ": 2 m")
	end
	assert(ToqueTelas.PREVIEW.dig.ahead == FieldWork.DIG.aheadM, "pá: FieldWork.DIG.aheadM")
	near(ToqueTelas.PREVIEW.dig.w, FieldWork.DIG.lengthM, 1e-9, "buraco: comprimento")
	near(ToqueTelas.PREVIEW.dig.d, FieldWork.DIG.widthM, 1e-9, "buraco: largura")
	-- olhando para −Z: 2 m à frente, rumo 0
	local x, z, yaw = ToqueTelas.buildSpot(10, 20, 0, -1, 2 / M)
	near(x, 10, 1e-9)
	near(z, 20 - 2 / M, 1e-9)
	near(yaw, 0, 1e-9)
	-- olhando para +X: rumo −90° (CFrame.Angles(0, yaw, 0).LookVector = (−sen, 0, −cos))
	local x2, z2, yaw2 = ToqueTelas.buildSpot(0, 0, 3, 0, 5)
	near(x2, 5, 1e-9)
	near(z2, 0, 1e-9)
	near(-math.sin(yaw2), 1, 1e-9, "LookVector.X")
	near(-math.cos(yaw2), 0, 1e-9, "LookVector.Z")
	-- olhar para cima (sem horizontal): cai para a frente padrão sem NaN
	local x3, z3, yaw3 = ToqueTelas.buildSpot(0, 0, 0, 0, 5)
	assert(x3 == x3 and z3 == z3 and yaw3 == yaw3)
end)

test("girar: passos de 45° voltam para −π..π", function()
	near(ToqueTelas.turn(0, 45), math.rad(45), 1e-9)
	near(ToqueTelas.turn(math.rad(170), 45), math.rad(-145), 1e-9)
	near(ToqueTelas.turn(math.rad(-170), -45), math.rad(145), 1e-9)
	local y = 0
	for _ = 1, 8 do
		y = ToqueTelas.turn(y, 45)
	end
	near(math.abs(y) % (2 * math.pi), 0, 1e-9, "oito passos: volta inteira")
end)

-- ===== seletor de tiro e alça =====
test("cartão da arma: seletor e alça pelas ações que existem (M79: alça − e +)", function()
	local function same(a: { string }, b: { string }): boolean
		return table.concat(a, ",") == table.concat(b, ",")
	end
	assert(same(ToqueTelas.weaponOptions(2, 3), { "mode", "zero_up" }), "fuzil com seletor")
	assert(same(ToqueTelas.weaponOptions(1, 7), { "zero_down", "zero_up" }), "M79 / luneta")
	assert(same(ToqueTelas.weaponOptions(1, 3), { "zero_up" }), "ferrolho de alça curta")
	assert(same(ToqueTelas.weaponOptions(3, 1), { "mode" }), "sem alça")
	-- as ações existem no InputMap (o botão aperta as mesmas do V)
	local ids: { [string]: boolean } = {}
	for _, a in InputMap.ACTIONS do
		ids[a.id] = true
	end
	assert(ids.fire_mode and ids.zeroing and ids.interact, "fire_mode, zeroing e interact")
end)

-- ===== nomes dos botões no toque (tutorial) =====
test("tutorial no toque: toda ação do tutorial tem o nome do botão na tela (nunca a tecla)", function()
	local src = fs.readFile("src/ReplicatedStorage/Shared/Tutorial.luau")
	local miss = {}
	for id in string.gmatch(src, 'act%("([%w_]+)"') do
		if not ToqueTelas.TOUCH_NAME[id] then
			table.insert(miss, id)
		end
	end
	assert(#miss == 0, "sem nome: " .. table.concat(miss, ", "))
	assert(ToqueTelas.touchName("nao_existe") == "botão na tela")
	local tut = fs.readFile(C .. "TutorialController.client.luau")
	assert(string.find(tut, "ToqueTelas.touchName", 1, true), "o tutorial usa os nomes no toque")
end)

-- ===== v39: nada de teclado no toque =====
local function src(name: string): string
	return fs.readFile(C .. name)
end

test("nada de teclado no toque: os nomes são os escritos nos botões; o Input.glyph não dá tecla", function()
	local Toque = require(S .. "Toque") :: any
	-- o nome de cada ação que tem botão é o texto do botão (o jogador procura o que lê); os opcionais
	-- de seta (inclinar, desligados no padrão) ficam de fora
	local glyphOf: { [string]: string } = {}
	for _, d in Toque.BUTTONS do
		if d.spec and d.glyph ~= "" and not d.optional then
			for _, p in Toque.parseSpec(d.spec) do
				glyphOf[p.id] = glyphOf[p.id] or d.glyph
			end
		end
	end
	for id, g in glyphOf do
		local name = ToqueTelas.TOUCH_NAME[id]
		assert(name, id .. " sem nome no toque")
		assert(string.find(name, g, 1, true) == 1, string.format("%s: '%s' não começa com '%s'", id, name, g))
	end
	-- o que saiu da tela aponta para onde foi
	assert(string.find(ToqueTelas.TOUCH_NAME.swap_weapon, "CARTÃO", 1, true))
	assert(string.find(ToqueTelas.TOUCH_NAME.fire_mode, "CARTÃO", 1, true))
	assert(ToqueTelas.TOUCH_NAME.view_toggle == "MENU" and ToqueTelas.TOUCH_NAME.mark == "COMUNICAR")
	-- nenhum nome tem cara de tecla (uma letra, número ou nome de tecla)
	for id, name in ToqueTelas.TOUCH_NAME do
		assert(#name > 2, id .. ": nome curto demais (parece tecla)")
		for _, k in { "Shift", "Ctrl", "Espaço", "Caps", "LMB", "RMB", "Enter", "Backspace" } do
			assert(not string.find(name, k, 1, true), id .. ": " .. name)
		end
	end
	-- o Input.glyph no toque devolve o nome do botão (tutorial, fichas, avisos), nunca a tecla
	local input = src("Input.luau")
	assert(
		string.find(input, 'if device == "touch" then\n\t\treturn nil, ToqueTelas.TOUCH_NAME[actionId] or ""', 1, true),
		"Input.glyph sem o ramo do toque"
	)
	-- a roda não mostra os números 1–8 no toque; o painel de teclas some no toque
	assert(string.find(src("Wheel.luau"), "not Input.touchActive() -- as teclas 1–8 são do teclado", 1, true))
	assert(string.find(src("PainelComandos.client.luau"), "ToqueUi.active()", 1, true))
	-- no toque os avisos de interação do Roblox (que podem mostrar a tecla) dão lugar ao INTERAGIR
	local auto = src("ToqueAuto.luau")
	assert(string.find(auto, "Enum.ProximityPromptStyle.Custom", 1, true), "prompt sem o aviso do Roblox")
	-- o texto do HUD de toque e dos automáticos não cita tecla
	for _, f in { "ToqueHud.client.luau", "ToqueAuto.luau", "EditorHud.client.luau" } do
		for n, l in string.split(src(f), "\n") do
			local code = string.gsub(l, "%-%-.*$", "")
			for s in string.gmatch(code, '"([^"]*)"') do
				for _, k in { "[F]", "(F)", "(R)", "(C)", "(Z)", "(G)", "(V)", "Shift", "Caps Lock" } do
					assert(not string.find(s, k, 1, true), string.format("%s:%d cita tecla: %s", f, n, s))
				end
			end
		end
	end
end)

test("cartão da arma no toque: tocar troca, segurar abre seletor, alça e baioneta; arrastar não", function()
	assert(ToqueTelas.cardGesture(0.1, 2, true) == "tap", "toque curto troca")
	assert(ToqueTelas.cardGesture(0.1, 2, false) == nil, "ainda segurando: espera")
	assert(ToqueTelas.cardGesture(ToqueTelas.CARD_HOLD_S, 2, false) == "hold", "segurou: abre")
	assert(ToqueTelas.cardGesture(ToqueTelas.CARD_HOLD_S + 1, 2, true) == "hold", "soltou depois: já abriu")
	assert(ToqueTelas.cardGesture(0.1, 40, true) == nil, "arrastou: era o olhar")
	assert(ToqueTelas.CARD_HOLD_S > ToqueTelas.TAP_S - 0.01, "segurar é mais longo que o toque")
	local function same(a: { string }, b: { string }): boolean
		return table.concat(a, ",") == table.concat(b, ",")
	end
	assert(same(ToqueTelas.weaponOptions(2, 3, true), { "mode", "zero_up", "bayonet" }), "M14 com baioneta")
	assert(same(ToqueTelas.weaponOptions(1, 7, false), { "zero_down", "zero_up" }), "luneta sem baioneta")
	assert(same(ToqueTelas.weaponOptions(2, 3), { "mode", "zero_up" }), "sem dizer: sem baioneta")
	local hud = src("HudCampo.client.luau")
	for _, t in { 'ToqueUi.tap("swap_weapon")', 'ToqueUi.tap("bayonet")', "ToqueTelas.cardGesture(", '"cartao"' } do
		assert(string.find(hud, t, 1, true), t)
	end
	local ids: { [string]: boolean } = {}
	for _, a in InputMap.ACTIONS do
		ids[a.id] = true
	end
	assert(ids.swap_weapon and ids.bayonet, "as ações do cartão existem")
end)

test(
	"zonas livres: cada tela do HUD usa a sua no toque (faixa, bússola, cartão, eventos, avisos, captura, tutorial)",
	function()
		local uses = {
			["FrontHud.client.luau"] = { '"topo"', '"captura"' },
			["HudCampo.client.luau"] = { '"bussola"', '"cartao"' },
			["EventosHud.client.luau"] = { '"eventos"' },
			["Toast.luau"] = { '"avisos"' },
			["TutorialController.client.luau"] = { '"tutorial"' },
		}
		for f, list in uses do
			local s = src(f)
			for _, z in list do
				assert(string.find(s, z, 1, true), f .. " não usa a zona " .. z)
			end
		end
		-- as mensagens do squad no toque vão para os avisos (não ficam soltas no meio da tela)
		assert(string.find(src("InfantryController.client.luau"), 'key = "squad"', 1, true))
		-- o HUD de toque publica a área para as zonas
		local hud = src("ToqueHud.client.luau")
		for _, a in { '"AreaPos"', '"AreaSize"', '"Espelho"', '"Indicador"', '"Campo"' } do
			assert(string.find(hud, a, 1, true), a)
		end
		-- o rótulo do interagir fica dentro do botão (fora, cobria botões e zonas)
		local ui = src("ToqueUi.luau")
		assert(string.find(ui, "l.Position = UDim2.fromScale(0.5, 0.66)", 1, true), "rótulo dentro do círculo")
	end
)

-- ===== faixa do alto =====
test("faixa do alto: o vão entre os botões de cima (os de baixo não contam)", function()
	local rects = {
		{ id = "map", x = 5, y = 5, w = 56, h = 56 },
		{ id = "channel", x = 240, y = 5, w = 56, h = 56 },
		{ id = "comm", x = 546, y = 5, w = 56, h = 56 },
		{ id = "radio", x = 710, y = 5, w = 56, h = 56 },
		{ id = "fire", x = 650, y = 180, w = 100, h = 100 }, -- embaixo: não conta
	}
	local x0, x1, base = ToqueTelas.topBand(rects, 0, 820, 80)
	assert(x0 == 296 and x1 == 546 and base == 61, string.format("%d %d %d", x0, x1, base))
	local a, b, c = ToqueTelas.topBand({}, 0, 820, 80)
	assert(a == 0 and b == 820 and c == 0, "sem HUD: a tela toda")
	-- tão apertado que nada cabe: a faixa inteira (a escala se vira)
	local crowd = { { id = "l", x = 0, y = 0, w = 405, h = 50 }, { id = "r", x = 420, y = 0, w = 400, h = 50 } }
	local d, e = ToqueTelas.topBand(crowd, 0, 820, 80)
	assert(d == 0 and e == 820)
	near(ToqueTelas.fitScale(560, 250, 1, 0.4), 250 / 560, 1e-9)
	assert(ToqueTelas.fitScale(560, 900, 1, 0.4) == 1, "nunca cresce")
	assert(ToqueTelas.fitScale(560, 100, 1, 0.4) == 0.4, "piso legível")
end)

-- ===== conferências de fonte (src, definido acima) =====
test("interagir: o botão faz o mesmo que segurar X/F (prompt) e a ação interact (companheiro)", function()
	local s = src("Interagir.client.luau")
	assert(string.find(s, ":InputHoldBegin()", 1, true) and string.find(s, ":InputHoldEnd()", 1, true), "prompt")
	assert(string.find(s, 'ToqueUi.press("interact", true)', 1, true), "interact pelo Input.virtual")
	assert(string.find(s, 'ToqueUi.press("interact", false)', 1, true), "e solta sempre")
	assert(string.find(s, '"interagir"', 1, true), "gancho VT65DevTela = interagir")
	assert(string.find(s, "VT65AcaoT", 1, true), "anel no tempo do servidor (médico)")
	assert(string.find(src("MedicalController.client.luau"), 'Bus.on("interact_ally"', 1, true), "reserva sem virtual")
end)

test("mapa no toque: pinça, arrasto, toque escolhe, inserir com a espera e o alvo confirmado", function()
	local cv = src("CartaView.luau")
	assert(string.find(cv, "UserInputType.Touch then\n\t\t\ttouchMoved", 1, true), "arrasto e pinça no InputChanged")
	assert(string.find(cv, "ToqueTelas.pinch", 1, true) and string.find(cv, "ToqueTelas.nearest", 1, true))
	local ui = src("GameUI.client.luau")
	for _, t in { '"CONFIRMAR ALVO"', "ToqueTelas.spawnButton", "ToqueTelas.fullRect", '"VT65SemIma"' } do
		assert(string.find(ui, t, 1, true), t)
	end
	-- no toque, tocar no ponto não insere direto (só escolhe)
	assert(string.find(cv, "toque: só escolhe", 1, true))
end)

test("comandante e construção: nada de digitar no toque; obra passa pela prévia", function()
	local cc = src("CommanderController.client.luau")
	assert(string.find(cc, "not ToqueUi.active()", 1, true), "a grade digitada some no toque")
	assert(string.find(cc, 'Bus.fire("build_preview", id)', 1, true))
	assert(string.find(cc, '"FECHAR"', 1, true), "fechar visível")
	local inf = src("InfantryController.client.luau")
	assert(string.find(inf, 'Bus.fire("build_preview"', 1, true))
	local ob = src("ObraToque.client.luau")
	for _, t in { "Build_Request", "Dig_Request", "ToqueTelas.buildSpot", '"construir"' } do
		assert(string.find(ob, t, 1, true), t)
	end
end)

test("telas: o 1º toque mostra (papel, passe), o cartão da loja mostra o item, nada de hover", function()
	assert(string.find(src("DeployScreen.luau"), "ToqueTelas.secondTap(roleTap", 1, true), "papel")
	assert(string.find(src("TelaPasse.client.luau"), "ToqueTelas.secondTap(cellTap", 1, true), "passe")
	assert(string.find(src("ShopController.client.luau"), 'ver.Name = "Ver"', 1, true), "loja")
	assert(string.find(src("TelaMissoes.client.luau"), 'Instance.new("ScrollingFrame")', 1, true), "missões rolam")
	assert(string.find(src("FrontHud.client.luau"), "UserInputType.Touch", 1, true), "fim: tocar fecha")
	assert(string.find(src("VirtualCursor.luau"), "function VirtualCursor.touchSnap", 1, true), "dedo gordo")
end)

-- a mesma regra do teste "interface": texto de tela nunca montado com ".."
test("arquivos novos: nenhum texto de tela montado aos pedaços com '..'", function()
	local bad = {}
	for _, f in
		{
			"ToqueTelas.luau",
			"ToqueUi.luau",
			"Interagir.client.luau",
			"ObraToque.client.luau",
			"HudCampo.client.luau",
			"TutorialController.client.luau",
		}
	do
		for n, l in string.split(src(f), "\n") do
			local code = string.gsub(l, "%-%-.*$", "")
			if
				string.find(code, '"[^"]*[%a\128-\255][^"]* "%s*%.%.')
				or string.find(code, '%.%.%s*" [^"]*[%a\128-\255][^"]*"')
			then
				table.insert(bad, string.format("%s:%d", f, n))
			end
		end
	end
	assert(#bad == 0, table.concat(bad, ", "))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
