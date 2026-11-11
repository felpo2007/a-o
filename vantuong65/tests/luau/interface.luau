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
