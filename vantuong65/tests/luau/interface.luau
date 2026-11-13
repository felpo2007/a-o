--!strict
-- Testes das interfaces refeitas (2026-11-11: caveira do abate, pular o tutorial, idioma, menus).
-- Uso, a partir de vantuong65/:  lune run tests/luau/interface.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local InputMap = require(S .. "InputMap") :: any
local Lang = require(S .. "Lang")
local AssetIds = require(S .. "AssetIds") :: any

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

-- ===== pular o tutorial: sem conflito no InputMap =====
local function withActions(extra: { any }, fn: () -> ())
	local n = #InputMap.ACTIONS
	for _, a in extra do
		table.insert(InputMap.ACTIONS, a)
	end
	local ok, err = pcall(fn)
	for i = #InputMap.ACTIONS, n + 1, -1 do
		table.remove(InputMap.ACTIONS, i)
	end
	if not ok then
		error(err, 0)
	end
end

test("pular o tutorial: Backspace segurado (jogo) e Y segurado (menu) não criam conflito", function()
	local before = #InputMap.conflicts() + #InputMap.keyConflicts()
	assert(before == 0, "o mapa padrão já tem conflito")
	withActions({
		-- teclado: Backspace segurado, valendo em todos os contextos de jogo (camada global)
		{
			id = "tutorial_skip",
			ctx = "global",
			pad = nil,
			padPress = "press",
			key = "Backspace",
			keyPress = "hold",
			label = "Pular o tutorial",
		},
		-- controle: Y segurado com o menu do jogo aberto (faixa do tutorial)
		{
			id = "tutorial_skip_menu",
			ctx = "menu",
			pad = "ButtonY",
			padPress = "hold",
			key = nil,
			keyPress = "press",
			label = "Pular o tutorial",
		},
	}, function()
		local c, k = InputMap.conflicts(), InputMap.keyConflicts()
		assert(#c == 0, table.concat(c, "; "))
		assert(#k == 0, table.concat(k, "; "))
	end)
end)

test("controle: os 15 botões já têm ação na infantaria (por isso o caminho é o menu)", function()
	local used: { [string]: boolean } = {}
	for _, a in InputMap.ACTIONS do
		if (a.ctx == "infantry" or a.ctx == "global") and a.pad then
			used[a.pad] = true
		end
	end
	local all = {
		"ButtonA",
		"ButtonB",
		"ButtonX",
		"ButtonY",
		"ButtonL1",
		"ButtonR1",
		"ButtonL2",
		"ButtonR2",
		"ButtonL3",
		"ButtonR3",
		"ButtonSelect",
		"DPadUp",
		"DPadDown",
		"DPadLeft",
		"DPadRight",
	}
	for _, b in all do
		assert(used[b], b .. " está livre: dá para pôr o pular direto no cartão")
		-- qualquer "segurar" a mais nesse botão quebra a regra de conflito
		withActions({
			{
				id = "tutorial_skip_test",
				ctx = "global",
				pad = b,
				padPress = "hold",
				key = nil,
				keyPress = "press",
				label = "x",
			},
		}, function()
			assert(#InputMap.conflicts() > 0, b .. " aceitaria um segurar a mais")
		end)
	end
end)

test("menu: Y e X livres no contexto do menu (pular tutorial e idioma)", function()
	for _, a in InputMap.ACTIONS do
		if a.ctx == "menu" then
			assert(a.pad ~= "ButtonY" and a.pad ~= "ButtonX", a.id)
		end
	end
end)

-- ===== caveira do abate =====
test("caveira: chave nova em AssetIds.Images e no plano de upload, PNG 1024 RGBA", function()
	assert(type(AssetIds.Images.caveira_abate) == "number", "AssetIds.Images.caveira_abate")
	local plan = net.jsonDecode(fs.readFile("assets/upload_plan.json"))
	local item = nil
	for _, it in plan do
		if it.key == "Images.caveira_abate" then
			item = it
		end
	end
	assert(item, "falta Images.caveira_abate no upload_plan.json")
	assert(item.assetType == "Decal", item.assetType)
	assert(fs.isFile(item.file), "rode: uv run python tools/make_caveira.py")
	local png = fs.readFile(item.file)
	assert(string.sub(png, 2, 4) == "PNG", "não é PNG")
	local function u32(i: number): number
		local a, b, c, d = string.byte(png, i, i + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	assert(u32(17) == 1024 and u32(21) == 1024, "1024 x 1024")
	assert(string.byte(png, 26) == 6, "RGBA (cor tipo 6)")
end)

-- ===== textos de tela prontos para tradução =====
-- texto colado aos pedaços com .. não casa com o dicionário: nos arquivos novos e refeitos, nenhum
-- literal com espaço na ponta encostado num ".." (chaves internas como "n:" .. k não têm espaço)
local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local FILES = {
	C .. "Caveira.client.luau",
	C .. "GameMenu.client.luau",
	C .. "HudCampo.client.luau",
	C .. "IdiomaLobby.client.luau",
	C .. "Reconexao.client.luau",
	C .. "Wheel.luau",
	C .. "VehicleHudView.luau",
	C .. "AfterActionController.client.luau",
	C .. "ShopController.client.luau",
	C .. "TutorialController.client.luau",
	C .. "FrontHud.client.luau",
	C .. "CasualtyScreen.luau",
	C .. "GameUI.client.luau",
	C .. "DeployScreen.luau",
	C .. "Marcadores.luau",
	C .. "Progresso.client.luau",
	C .. "JanelaChat.client.luau",
	C .. "Toast.luau",
	C .. "CartaView.luau",
	"src/ReplicatedFirst/Idioma.luau",
	"src/ReplicatedFirst/LoadingScreen.client.luau",
}
test("telas: nenhum texto montado aos pedaços com '..'", function()
	local bad = {}
	for _, f in FILES do
		for n, l in string.split(fs.readFile(f), "\n") do
			local code = string.gsub(l, "%-%-.*$", "") -- tira o comentário
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

test("modelos novos casam no dicionário (ex.: setor tomado, tutorial pulado, câmera)", function()
	local t = Lang.compile({
		["%s é nosso"] = "%s is ours",
		["Câmera: 3ª pessoa (%s)"] = "Camera: 3rd person (%s)",
		["direito"] = "right",
		["Tutorial pulado. Refazer: menu do jogo → Squad e papel."] = "Tutorial skipped. Redo: game menu → Squad and role.",
		["Equipamento: %.1f de %.1f kg (vale no próximo spawn)"] = "Gear: %.1f of %.1f kg (applies on next spawn)",
		["Conflito: %s e %s em %s"] = "Conflict: %s and %s on %s",
	})
	assert(Lang.translate(t, "S3 Cemitério é nosso") == "S3 Cemitério is ours")
	assert(Lang.translate(t, "Câmera: 3ª pessoa (direito)") == "Camera: 3rd person (right)")
	assert(
		Lang.translate(t, "Tutorial pulado. Refazer: menu do jogo → Squad e papel.")
			== "Tutorial skipped. Redo: game menu → Squad and role."
	)
	assert(
		Lang.translate(t, "Equipamento: 7.5 de 22.0 kg (vale no próximo spawn)")
			== "Gear: 7.5 of 22.0 kg (applies on next spawn)"
	)
	assert(Lang.translate(t, "Conflito: Correr e Mirar em Shift") == "Conflict: Correr and Mirar on Shift")
end)

-- ===== volume (menu de opções → Som) =====
test("volume: efeitos 0,5, ambiente 0,6 e música 0,35 no padrão; 0 a 1 no validate", function()
	local d = InputMap.DEFAULTS
	assert(d.volEffects == 0.5 and d.volAmbient == 0.6 and d.volMusic == 0.35, "padrões")
	local s = InputMap.validate({ volEffects = 2, volAmbient = -1, volMusic = "alto" })
	assert(s.volEffects == 1 and s.volAmbient == 0 and s.volMusic == 0.35, "faixas")
	assert(InputMap.validate({ volMusic = 0.2 }).volMusic == 0.2)
end)

-- ===== movimento da câmera (Acessib.) =====
test("movimento da câmera: padrão 1 (100%), 0 a 1 no validate", function()
	assert(InputMap.DEFAULTS.cameraBob == 1, "padrão")
	assert(InputMap.validate({ cameraBob = 3 }).cameraBob == 1, "teto")
	assert(InputMap.validate({ cameraBob = -2 }).cameraBob == 0, "piso")
	assert(InputMap.validate({ cameraBob = "x" }).cameraBob == 1, "lixo volta ao padrão")
	assert(InputMap.validate({ cameraBob = 0.4 }).cameraBob == 0.4)
end)

-- ===== roda radial: fichas sem sobrepor e fora do anel (Studio: 5 e 6 encavaladas, 1 no anel) =====
test("roda: nenhuma ficha encosta em outra (nem a acesa, 1,1x) e todas ficam fora do anel", function()
	local src = fs.readFile(C .. "Wheel.luau")
	local s1, s2 = string.match(src, "local SIZE = px%((%d+), (%d+)%)")
	local fx, fy = string.match(src, "local RX, RY = SIZE %* ([%d%.]+), SIZE %* ([%d%.]+)")
	local w1, w2, h1, h2 = string.match(src, "local CARD_W, CARD_H = px%((%d+), (%d+)%), px%((%d+), (%d+)%)")
	local ringK = string.match(src, "local ring = circle%(center, ([%d%.]+)")
	assert(s1 and fx and w1 and ringK, "constantes da roda mudaram de forma: ajuste o teste")
	for _, v in { { s1, w1, h1 }, { s2, w2, h2 } } do
		local size, cw, ch = tonumber(v[1]) :: number, tonumber(v[2]) :: number, tonumber(v[3]) :: number
		local rx, ry = size * (tonumber(fx) :: number), size * (tonumber(fy) :: number)
		local ring = size * (tonumber(ringK) :: number) / 2
		local c = {}
		for i = 1, 8 do
			local a = (i - 1) * math.pi / 4
			c[i] = { x = math.sin(a) * rx, y = -math.cos(a) * ry }
		end
		for i = 1, 8 do
			-- ponto da ficha mais perto do centro (retângulo): longe do anel
			local dx = math.max(math.abs(c[i].x) - cw / 2, 0)
			local dy = math.max(math.abs(c[i].y) - ch / 2, 0)
			assert(math.sqrt(dx * dx + dy * dy) > ring + 2, string.format("ficha %d encosta no anel (%d)", i, size))
			for j = i + 1, 8 do
				-- uma das duas pode estar acesa (escala 1,1)
				local hw, hh = cw * 1.1 / 2 + cw / 2, ch * 1.1 / 2 + ch / 2
				local ox = math.abs(c[i].x - c[j].x) < hw
				local oy = math.abs(c[i].y - c[j].y) < hh
				assert(not (ox and oy), string.format("fichas %d e %d se sobrepõem (%d)", i, j, size))
			end
		end
	end
end)

-- ===== voltar (B, Esc, Backspace): uma tela por aperto, a de cima =====
test("voltar: cada tela que fecha com o voltar entra e sai da pilha do UiKit", function()
	for file, name in
		{
			["GameMenu.client.luau"] = "menu",
			["ShopController.client.luau"] = "loja",
			["AfterActionController.client.luau"] = "relatorio",
			["FrontHud.client.luau"] = "fim",
		} :: { [string]: string }
	do
		local src = fs.readFile(C .. file)
		assert(string.find(src, string.format('UiKit.opened("%s"', name), 1, true), file .. ": opened")
		assert(string.find(src, string.format('UiKit.closed("%s")', name), 1, true), file .. ": closed")
		assert(string.find(src, string.format('UiKit.backFor("%s")', name), 1, true), file .. ": backFor")
		assert(string.find(src, "UiKit.release(", 1, true), file .. ": o foco sai da tela fechada")
	end
end)

-- ===== inserção: a câmera chega nivelada (Studio: chegava olhando o chão, −77°) =====
test("inserção: câmera nivelada (−5° a 0°) em tween curto, antes do voo, em todo caminho", function()
	local src = fs.readFile(C .. "SpawnTransition.luau")
	local deg = tonumber(string.match(src, "local LEVEL_PITCH = math%.rad%((%-?[%d%.]+)%)"))
	assert(deg and deg >= -5 and deg <= 0, "LEVEL_PITCH fora de −5° a 0°")
	local s = tonumber(string.match(src, "local LEVEL_S = ([%d%.]+)"))
	assert(s and s >= 0.15 and s <= 0.5, "tween do nível curto (0,15 a 0,5 s)")
	-- o nível termina antes do voo: cabe na pausa do carimbo (0,5 s) com a ordem ainda opaca
	assert(s <= 0.5)
	-- todo caminho que chama o voo nivela antes (inserção e gancho de teste)
	local starts, settles = 0, 0
	for line in string.gmatch(src, "[^\n]+") do
		local code = string.gsub(line, "%-%-.*$", "")
		if string.find(code, "startFlight()", 1, true) and not string.find(code, "function", 1, true) then
			starts += 1
		end
		if string.find(code, "settleCamera()", 1, true) and not string.find(code, "function", 1, true) then
			settles += 1
		end
	end
	assert(starts >= 1 and settles == starts, string.format("voos %d, nivelamentos %d", starts, settles))
	-- rumo: objetivo do time; sem objetivo, a frente do HumanoidRootPart
	assert(string.find(src, "Front.objective", 1, true), "rumo no objetivo")
	assert(string.find(src, "root.CFrame.LookVector", 1, true), "sem objetivo: a frente do corpo")
	-- a imagem do voo nunca passa de −80° (não vira de cabeça para baixo)
	assert(string.find(src, "math.rad(80)", 1, true), "trava da imagem do voo")
	-- o mesmo cálculo do tween: começa no pitch de agora e termina exatamente no nível, sem salto
	local function smooth(t: number): number
		return t * t * t * (t * (t * 6 - 15) + 10)
	end
	local p0, pT = math.rad(-77), math.rad(deg :: number)
	local last = p0
	for i = 1, 30 do
		local p = p0 + (pT - p0) * smooth(i / 30)
		assert(math.abs(p - last) < math.rad(9), "passo grande demais num quadro") -- 30 quadros ~ 0,5 s
		last = p
	end
	assert(math.abs(last - pT) < 1e-9)
end)

-- ===== estilo novo (2026-11-11: "não gosto dessa escrita no papel e dessa ideia") =====
-- A tela de entrada saiu da lista em 2026-11-13: o dono pediu de volta a tela antiga (película,
-- briefing datilografado e carta com o carimbo), que é a única com máquina de escrever.
local REDONE = {
	"src/ReplicatedFirst/Idioma.luau",
	C .. "CasualtyScreen.luau",
	C .. "DeployScreen.luau",
	C .. "LobbyScene.luau",
	C .. "CartaView.luau",
	C .. "GameUI.client.luau",
	C .. "SpawnTransition.luau",
	C .. "GameMenu.client.luau",
	C .. "ShopController.client.luau",
	C .. "Progresso.client.luau",
	C .. "FrontHud.client.luau",
	C .. "AfterActionController.client.luau",
	C .. "CommanderController.client.luau",
}
test("estilo novo: nenhuma tela refeita usa máquina de escrever, fonte Code ou texto datilografado", function()
	local bad = {}
	for _, f in REDONE do
		for n, l in string.split(fs.readFile(f), "\n") do
			local code = string.gsub(l, "%-%-.*$", "")
			for _, w in { "SpecialElite", "TYPE_OLD", "datilografar", "Enum.Font.Code", "PatrickHand" } do
				if string.find(code, w, 1, true) then
					table.insert(bad, string.format("%s:%d (%s)", f, n, w))
				end
			end
		end
	end
	assert(#bad == 0, table.concat(bad, ", "))
end)

test("estilo novo: tokens e peças num lugar só (Estilo no ReplicatedFirst, reexportado pelo UiKit)", function()
	local est = fs.readFile("src/ReplicatedFirst/Estilo.luau")
	for _, k in { "BG", "PANEL", "TEXT", "DIM", "OLIVE", "KHAKI", "RED" } do
		assert(string.find(est, "\n\t" .. k .. " = Color3", 1, true), "Estilo.V." .. k)
	end
	assert(string.find(est, 'Font.fromName("Oswald"', 1, true) and string.find(est, "Enum.Font.Arimo", 1, true))
	local kit = fs.readFile(C .. "UiKit.luau")
	for _, k in { "panel", "title", "titleBox", "statRow", "itemCard", "backdrop" } do
		assert(string.find(kit, string.format("UiKit.%s = Estilo.%s", k, k), 1, true), "UiKit." .. k)
	end
	assert(string.find(kit, "function UiKit.action(", 1, true), "botão com entrada")
	-- cada tela refeita usa o estilo (UiKit.V/F ou o Estilo direto, no ReplicatedFirst)
	for _, f in REDONE do
		local src = fs.readFile(f)
		assert(
			string.find(src, "UiKit.V", 1, true) or string.find(src, "Estilo", 1, true),
			f .. " não usa o estilo novo"
		)
	end
end)

test("idioma: bandeiras desenhadas (sem imagem) para PT, EN, ES, VI e o globo do automático", function()
	local src = fs.readFile("src/ReplicatedFirst/Bandeiras.luau")
	for _, c in { "pt", "en", "es", "vi", "auto" } do
		assert(string.find(src, '"' .. c .. '"', 1, true) or string.find(src, c .. " =", 1, true), "bandeira " .. c)
	end
	assert(not string.find(src, "rbxassetid://", 1, true), "bandeira com imagem")
	assert(string.find(src, "UIGradient", 1, true), "desenho com UIGradient")
	assert(
		string.find(fs.readFile("src/ReplicatedFirst/Idioma.luau"), "Bandeiras", 1, true),
		"o cartão usa as bandeiras"
	)
end)

test("carregamento: pré-carga de verdade (sons, animações, arte) e ENTRAR só no fim, com teto", function()
	local src = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")
	assert(string.find(src, "PreloadAsync", 1, true), "PreloadAsync")
	assert(string.find(src, "Sounds", 1, true), "sons do AssetIds")
	assert(string.find(src, "SoldierAnims", 1, true), "animações")
	assert(string.find(src, "90", 1, true), "teto de segurança de ~90 s")
end)

test("carta: túneis só para o VC e pontos do squad (kind = squad)", function()
	local src = fs.readFile(C .. "CartaView.luau")
	assert(string.find(src, "TunnelLinks", 1, true), "rede de túneis")
	assert(string.find(src, '"VC"', 1, true), "túneis condicionados ao lado VC")
	assert(string.find(src, '"squad"', 1, true), "pontos de nascer no squad")
end)

test("baixa: renascer, renascer aqui (créditos e Robux) e voltar, com o motivo do bloqueio", function()
	local src = fs.readFile(C .. "CasualtyScreen.luau")
	assert(string.find(src, '"RENASCER"', 1, true), "RENASCER")
	assert(string.find(src, '"inplace", "robux"', 1, true), "Robux pelo servidor (que abre a compra)")
	assert(string.find(src, '"RENASCER ONDE CAIU"', 1, true), "linha do mesmo lugar (v44: rótulo claro)")
	assert(string.find(src, "CenaBaixa.show", 1, true), "o próprio soldado, caído")
end)

-- ===== tela de baixa de 2026-11-13: soldado caído, renascer rápido, veículo e desistir sempre =====
test("baixa: RENASCER é o jogar agora; veículo pelo pedido da D-103; carta à parte", function()
	local src = fs.readFile(C .. "CasualtyScreen.luau")
	assert(string.find(src, "JogarAgora.start({ vehicle = vehicle })", 1, true), "renascer rápido")
	assert(
		string.find(src, '"RENASCER COM VEÍCULO"', 1, true) and string.find(src, '"ESCOLHER OUTRO PONTO"', 1, true),
		"v44: veículo e carta com rótulos claros"
	)
	assert(string.find(src, "FireServer({ spec = o.spec, pay = o.pay })", 1, true), "Vehicle_Order da carta")
	assert(string.find(src, 'msg.state == "armed"', 1, true), "só renasce com o pedido armado")
	assert(string.find(src, "CompraVeiculo.productId(spec) ~= 0", 1, true), "Robux só com produto criado")
	-- desistir: o anel fica sempre na tela; a espera vem do Shared/Medical (pode ser zero ou sumir)
	assert(string.find(src, "D.ring.Visible = true", 1, true), "anel sempre visível")
	assert(not string.find(src, "Medical.C.giveUpAfter -", 1, true), "sem conta direta no campo")
	assert(string.find(src, "tonumber((Medical.C :: any).giveUpAfter) or 0", 1, true), "campo sumido = 0")
end)

test("baixa: a cena deita o soldado pelas juntas (Motor6D e AnimationConstraint) e larga a arma", function()
	local src = fs.readFile(C .. "CenaBaixa.luau")
	for _, j in { "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightHip", "LeftHip", "LeftKnee" } do
		assert(string.find(src, "\t" .. j .. " = deg(", 1, true), "pose sem " .. j)
	end
	assert(string.find(src, 'IsA("AnimationConstraint")', 1, true), "junta nova do avatar")
	assert(string.find(src, '"RestC0"', 1, true), "C0 de repouso (a postura mexe no C0)")
	assert(string.find(src, 'FindFirstChild("Weapon")', 1, true), "a arma sai da mão")
	assert(string.find(src, "VT65Preview", 1, true), "sem retrato: o manequim do lado")
	assert(not string.find(src, "RenderStepped", 1, true), "nada por quadro")
end)

-- ===== cores de compra (2026-11-13): Robux, créditos e grátis com cor própria e texto legível =====
local function lin(c: number): number
	local s = c / 255
	return if s <= 0.04045 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
end
local function lum(r: number, g: number, b: number): number
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end
test("cores de compra: três cores diferentes, texto claro com contraste >= 3:1 (texto grande)", function()
	local kit = fs.readFile(C .. "UiKit.luau")
	local est = fs.readFile("src/ReplicatedFirst/Estilo.luau")
	local function rgb(src: string, pat: string): (number, number, number)
		local r, g, b = string.match(src, pat)
		assert(r, "cor não achada: " .. pat)
		return tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number
	end
	local tr, tg, tb = rgb(est, "\tTEXT = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
	local text = lum(tr, tg, tb)
	local seen: { [string]: boolean } = {}
	for _, k in { "robux", "ci" } do
		local r, g, b = rgb(kit, "\t" .. k .. " = { base = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
		local c = (text + 0.05) / (lum(r, g, b) + 0.05)
		assert(c >= 3, string.format("%s: contraste %.2f", k, c))
		seen[string.format("%d,%d,%d", r, g, b)] = true
	end
	local or_, og, ob = rgb(est, "\tOLIVE = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
	assert((text + 0.05) / (lum(or_, og, ob) + 0.05) >= 3, "grátis (oliva)")
	seen[string.format("%d,%d,%d", or_, og, ob)] = true
	local n = 0
	for _ in seen do
		n += 1
	end
	assert(n == 3, "as três formas de pagar com cores diferentes")
	assert(string.find(kit, "function UiKit.payPaint(", 1, true) and string.find(kit, "setKind = function", 1, true))
end)

test("cores de compra: baixa, loja, carta de inserção, passe e intendência usam o padrão", function()
	local function has(file: string, needle: string)
		assert(string.find(fs.readFile(C .. file), needle, 1, true), file .. ": " .. needle)
	end
	has("CasualtyScreen.luau", '"Renascer aqui · Robux", "robux"')
	has("CasualtyScreen.luau", 'setKind("ci")')
	has("ShopController.client.luau", 'UiKit.action(f, "", "robux"')
	has("ShopController.client.luau", 'UiKit.payPaint(bt, "robux"')
	has("ShopController.client.luau", 'pay = if isRobux then "robux" else "ci"')
	has("CompraVeiculo.client.luau", 'addRow(name, "robux"')
	has("CompraVeiculo.client.luau", 'addRow(name, "ci"')
	has("TelaPasse.client.luau", 'UiKit.action(prev, "", "robux"')
	has("Progresso.client.luau", "robux = { bg = UiKit.PAGAR.robux.base")
end)

test("carregamento: o visual antigo (b85331e) com o carregamento completo e o JOGAR AGORA", function()
	local src = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")
	for _, t in { "Acabamento.filme", '"SECRET"', "BRIEFING · O QUE O COMANDO SABE", "pontilha" } do
		assert(string.find(src, t, 1, true), "visual antigo: " .. t)
	end
	for _, t in { "scanArt(workspace", "soundList()", "animList()", "TerrainReady", "CAP_S = 90" } do
		assert(string.find(src, t, 1, true), "carregamento completo: " .. t)
	end
	assert(string.find(src, 'gui:SetAttribute("JogarAgora", true)', 1, true), "JOGAR AGORA")
	local ja = fs.readFile(C .. "JogarAgora.luau")
	assert(string.find(ja, '"VT65Loading"', 1, true) and string.find(ja, 'GetAttribute("JogarAgora")', 1, true))
end)

test("comandos: só com teclado e mouse ou controle; no toque nunca; fora da faixa de cima", function()
	local src = fs.readFile(C .. "PainelComandos.client.luau")
	assert(string.find(src, "keysMakeSense()", 1, true), "filtro do aparelho")
	assert(string.find(src, 'if d ~= "kbm" or ToqueUi.active() then', 1, true), "toque nunca")
	assert(string.find(src, "TouchEnabled and not UserInputService.KeyboardEnabled", 1, true), "celular")
	assert(string.find(src, "Input.DeviceChanged:Connect(refresh)", 1, true), "troca na hora")
	assert(string.find(src, "TOP_RESERVE", 1, true) and string.find(src, "Vector2.new(0, 1)", 1, true))
end)

-- ===== roda: fica aberta enquanto o botão estiver seguro (o dono: "a tela some muito rápido") =====
test("roda: o contexto da roda solta o botão que a abriu; a soltura física é que confirma", function()
	-- a causa: no contexto "wheel" a ação que abriu a roda não existe, então o Input a solta na hora
	local opener = {}
	for _, a in InputMap.ACTIONS do
		if a.id == "equip_wheel" or a.id == "comm_wheel" then
			table.insert(opener, a)
		end
	end
	assert(#opener >= 2, "ações das rodas")
	assert(not InputMap.survives(opener, "wheel"), "se sobrevivesse, o holdEnd falso não existiria")
	-- a correção: a roda sabe quem a abriu e quem chama ignora o holdEnd com o botão ainda apertado
	local wheel = fs.readFile(C .. "Wheel.luau")
	assert(string.find(wheel, "function Wheel.heldDown", 1, true), "Wheel.heldDown")
	assert(string.find(wheel, "InputEnded", 1, true) and string.find(wheel, 'Bus.fire("wheel_confirm")', 1, true))
	local inf = fs.readFile(C .. "InfantryController.client.luau")
	assert(
		string.find(inf, '"equip_wheel")', 1, true) and string.find(inf, '"comm_wheel"', 1, true),
		"abre dizendo quem segura"
	)
	local _, guards = string.gsub(inf, "and not Wheel%.heldDown%(%)", "")
	assert(guards >= 2, "os dois holdEnd ignoram a soltura falsa")
end)

-- ===== menos texto: 1ª frase e o resto, sem quebrar o RichText =====
local Texto = require("../../" .. C .. "Texto")
test("menos texto: a 1ª frase sai inteira, com o botão em RichText", function()
	local a, b = Texto.splitSentence('Atirar: <font color="#D6AC48"><b>RT</b></font>. Um ou dois tiros derrubam.')
	assert(a == 'Atirar: <font color="#D6AC48"><b>RT</b></font>.', a)
	assert(b == "Um ou dois tiros derrubam.", b)
	local c, e = Texto.splitSentence("Tratar ou reanimar um ferido: <b>X</b>, perto dele.")
	assert(c == "Tratar ou reanimar um ferido: <b>X</b>, perto dele." and e == "")
	local f, g = Texto.splitSentence("Alça de mira (100, 200, 300 m): <b>V</b>.")
	assert(g == "" and f == "Alça de mira (100, 200, 300 m): <b>V</b>.")
	-- tradução para o inglês (o dicionário devolve a frase inteira): divide do mesmo jeito
	local h, i = Texto.splitSentence("Fire: <b>RT</b>. One or two rifle hits drop a man.")
	assert(h == "Fire: <b>RT</b>." and i == "One or two rifle hits drop a man.")
end)

-- ===== marcadores: nunca inimigo (Parte 9.5) =====
test("marcadores: só modelos do mesmo lado (Faction igual), nada de inimigo", function()
	local src = fs.readFile(C .. "Marcadores.luau")
	-- toda escolha de quem marcar passa pelo lado do jogador
	local _, nFaction = string.gsub(src, 'GetAttribute%("Faction"%) == faction', "")
	assert(nFaction >= 2, "jogadores e bots filtrados pelo lado")
	assert(not string.find(src, "~= faction", 1, true), "nenhum ramo para o outro lado")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
