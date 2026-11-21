--!strict
-- Testes dos pedidos do dono de 21/11 (D-216 a D-220): mira inclinada, texto que cabe, Robux, emblemas,
-- caixas por língua, sons gravados. Uso: lune run tests/luau/pedidos21.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local AssetIds = require(S .. "AssetIds") :: any
local InputMap = require(S .. "InputMap") :: any
local SomArmas = require(S .. "SomArmas") :: any
local SomGravacoes = require(S .. "SomGravacoes") :: any
local SomKits = require(S .. "SomKits") :: any
local TextoCabe = require("../../src/ReplicatedFirst/TextoCabe") :: any

local CTRL = "src/StarterPlayer/StarterPlayerScripts/Controllers/"

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

local function semComentarios(t: string): string
	local linhas = {}
	for linha in string.gmatch(t, "[^\n]+") do
		table.insert(linhas, (string.gsub(linha, "%-%-.*$", "")))
	end
	return table.concat(linhas, "\n")
end

print("== mira inclinada (D-216)")
test("o botão do analógico passa o lado: direita, esquerda, reto", function()
	assert(InputMap.leanCycle(0) == 1)
	assert(InputMap.leanCycle(1) == -1)
	assert(InputMap.leanCycle(-1) == 0)
end)
test("a inclinação lê o estado do interruptor, não a tecla segura", function()
	local t = semComentarios(fs.readFile(CTRL .. "Inclinar.luau"))
	assert(string.find(t, "st.lean", 1, true), "sem st.lean")
	assert(not string.find(t, 'Input.on("lean', 1, true), "ainda escuta a tecla segura")
end)

print("== texto que cabe (D-216)")
local base = { escala = false, automatico = false, livre = false, texto = "ABC", w = 100, h = 20, cabe = false }
local function com(m: { [string]: any }): any
	local c = table.clone(base) :: any
	for k, v in m do
		c[k] = v
	end
	return c
end
test("encolhe só o que não cabe", function()
	assert(TextoCabe.precisa(base))
	assert(not TextoCabe.precisa(com({ cabe = true })))
end)
test("fica de fora: automático, escalado, livre, vazio e sem tamanho", function()
	for _, m in { { automatico = true }, { escala = true }, { livre = true }, { texto = "" }, { w = 0 }, { h = 3 } } do
		assert(not TextoCabe.precisa(com(m :: any)))
	end
end)
test("nunca cresce além do tamanho de projeto", function()
	local teto, piso = TextoCabe.limites(14.4)
	assert(teto == 14 and piso == TextoCabe.MINIMO)
	local t2, p2 = TextoCabe.limites(6)
	assert(t2 == 6 and p2 == 6)
end)

print("== Robux (D-217)")
test("nenhuma tela mostra R$", function()
	for _, nome in fs.readDir(CTRL) do
		if string.sub(nome, -5) == ".luau" then
			local t = semComentarios(fs.readFile(CTRL .. nome))
			assert(not string.find(t, "R$", 1, true), nome)
		end
	end
end)

print("== emblemas (D-218)")
test("todo emblema do jogo tem imagem publicada", function()
	local t = fs.readFile("src/ReplicatedStorage/Shared/Cosmeticos.luau")
	local n = 0
	for id in string.gmatch(t, 'id%s*=%s*"(emb_[%w_]+)"') do
		n += 1
		assert((AssetIds.Emblemas[id] or 0) ~= 0, "sem imagem: " .. id)
	end
	assert(n >= 20, "catálogo não lido")
	assert((AssetIds.Emblemas.emb_padrao or 0) ~= 0 and (AssetIds.Emblemas.emb_top10 or 0) ~= 0)
end)

print("== caixas por língua (D-219)")
local CAIXAS = {
	"gratuita",
	"recruta",
	"servico",
	"batalhao",
	"campanha",
	"veterano",
	"suprimentos",
	"especiais",
	"elite",
	"historica",
}
local IGUAIS = { elite_en = true, gratuita_es = true, veterano_es = true }
test("cada caixa tem a fechada e o corpo na língua, menos a palavra igual ao português", function()
	local n = 0
	for _, c in CAIXAS do
		for _, l in { "en", "es", "vi" } do
			local fechada = AssetIds.CaixaLoja[string.format("%s_%s", c, l)]
			local corpo = AssetIds.CaixaLoja[string.format("%s_corpo_%s", c, l)]
			if IGUAIS[string.format("%s_%s", c, l)] then
				assert(fechada == nil and corpo == nil, c .. l)
			else
				assert(fechada and corpo, "falta " .. c .. "_" .. l)
				n += 2
			end
		end
	end
	assert(n == 54, "imagens: " .. n)
end)
test("a tampa não tem nome, então não tem versão por língua", function()
	for k in AssetIds.CaixaLoja do
		assert(not string.find(k, "_tampa_", 1, true), k)
	end
end)

print("== sons gravados (D-220)")
test("toda arma com gravação, menos o M79", function()
	for id, a in SomArmas.ARMA do
		if id == "m79" then
			assert(SomGravacoes.de(a.kit, "p1") == nil)
		else
			for _, t in { "p1", "p2", "p3", "p4", "e1", "e2", "e3" } do
				assert(SomGravacoes.de(a.kit, t), id .. " " .. t)
			end
		end
	end
end)
test("peças que não são tiro continuam no kit", function()
	for _, t in { "seco", "ciclo", "estojo1" } do
		assert(SomGravacoes.de("kit_m16", t) == nil, t)
	end
	assert(SomGravacoes.de("kit_explosoes", "eco1") == nil)
end)
test("nenhum recorte é usado por duas armas", function()
	local visto: { [string]: string } = {}
	for kit, k in SomGravacoes.KIT do
		for _, t in k.tiros or {} do
			local c = string.format("%d@%.3f", t.id, t.ini)
			assert(not visto[c], c .. ": " .. kit .. " e " .. tostring(visto[c]))
			visto[c] = kit
		end
	end
end)
test("recortes válidos e volume limitado", function()
	local function confere(t: any)
		assert(t.id > 0 and t.ini >= 0 and t.dur > 0.05 and t.dur <= 4)
		local v = SomGravacoes.volume(t)
		assert(v >= 0.4 and v <= 4)
	end
	for _, k in SomGravacoes.KIT do
		for _, t in k.tiros or {} do
			confere(t)
		end
		for _, t in k.nomeados or {} do
			confere(t)
		end
	end
end)
test("as explosões gravadas existem no kit", function()
	for nome in SomGravacoes.KIT.kit_explosoes.nomeados do
		assert(SomKits.kit_explosoes.seg[nome], nome)
	end
end)
test("sem arquivo repetido no pré-carregamento", function()
	local vistos: { [number]: boolean } = {}
	local ids = SomGravacoes.ids()
	assert(#ids >= 30)
	for _, id in ids do
		assert(not vistos[id])
		vistos[id] = true
	end
end)
test("a música do menu é a nova, mais calma", function()
	assert(AssetIds.Sounds.music_menu == 1842762516)
end)

print("== comemoração (D-221)")
test("a cena avisa o pouso e os efeitos têm as duas camadas em volta do ViewportFrame", function()
	local cena = fs.readFile(CTRL .. "CenaComemoracao.luau")
	assert(string.find(cena, "self.aoPousar(lugar)", 1, true), "sem aviso do pouso")
	assert(string.find(cena, "vp.ZIndex = 3", 1, true), "o ViewportFrame entre as camadas")
	local efx = fs.readFile(CTRL .. "PodioEfeitos.luau")
	assert(string.find(efx, 'camada(pai, "EfeitosFundo", 2)', 1, true))
	assert(string.find(efx, 'camada(pai, "EfeitosFrente", 4)', 1, true))
	assert(string.find(efx, "UiEfeitos.calmo()", 1, true), "respeita reduzir movimento")
	local tela = fs.readFile(CTRL .. "FimDeRodada.client.luau")
	assert(string.find(tela, "efeitos:passo(dt)", 1, true) and string.find(tela, "efeitos:impacto(lugar)", 1, true))
end)

print(string.format("\n%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
