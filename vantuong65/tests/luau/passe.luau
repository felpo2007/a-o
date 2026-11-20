--!strict
-- D-208 (lote 93): o passe sobre o palco do lobby, com o desenho de cada recompensa e os cinco estados
-- do §11.
-- Uso, a partir de vantuong65/:  lune run tests/luau/passe.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

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
local function ler(p: string): string
	return (string.gsub(fs.readFile(p), "\r\n", "\n"))
end
local function has(src: string, s: string): boolean
	return string.find(src, s, 1, true) ~= nil
end

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local passe = ler(C .. "TelaPasse.client.luau")
local arte = ler(C .. "ItemArte.luau")
local temporada = ler("src/ReplicatedStorage/Shared/Temporada.luau")

test("toda recompensa da temporada tem desenho (§11: 'Imagem de cada recompensa')", function()
	local kinds: { [string]: boolean } = {}
	for k in string.gmatch(temporada, 'kind = "([%a_]+)"') do
		kinds[k] = true
	end
	local n = 0
	for k in kinds do
		n += 1
		local direto = has(arte, 'kind == "' .. k .. '"')
		assert(direto, "recompensa sem desenho: " .. k)
	end
	assert(n >= 8, "tipos de recompensa: " .. n)
	-- camuflagem e uniforme são itens de verdade: a arma com o acabamento e o pano da farda
	assert(has(arte, '(kind == "camo" or kind == "uniform") and id and Skins.get(id)'), "item de verdade")
	-- nada de emoji no lugar da imagem
	assert(not has(passe, "KIND_MARK"), "o emoji do lote 23 voltou")
end)

test("os cinco estados: bloqueada, alcançada, disponível, resgatada e dependente do Veterano", function()
	assert(has(passe, 'ready = { text = "RECEBER"'), "disponível")
	assert(has(passe, 'claimed = { text = "✓ RECEBIDO"'), "resgatada")
	assert(has(passe, 'locked = { text = "🔒 VETERANO"'), "dependente do Veterano")
	assert(has(passe, 'string.format("NÍVEL %d", lvl)'), "bloqueada mostra o nível")
	assert(has(passe, 'c.icon.GroupTransparency = if st == "claimed" then 0.55'), "a arte apaga junto")
	assert(has(passe, '"✓ VETERANO ATIVO"') and has(passe, '"🔒 VETERANO BLOQUEADO"'), "estado do premium")
end)

test("a casca: painel à esquerda do soldado, ordens a um clique, arte grande na ficha", function()
	assert(has(passe, "panel.AnchorPoint = Vector2.new(0, 0.5)"), "painel à esquerda")
	assert(has(passe, "pintarVeu(LobbyPalco.aberto())"), "sobre o palco no lobby")
	assert(has(passe, 'Bus.fire("missoes_open")'), "ordens do dia")
	assert(has(passe, "ItemArte.recompensa(prevThumb, rw, ICON)"), "arte grande da escolhida")
	-- a linha do tempo horizontal (D-124, pedido do dono) continua
	assert(has(passe, "list.ScrollingDirection = Enum.ScrollingDirection.X"), "linha do tempo horizontal")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
