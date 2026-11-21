--!strict
-- D-212 (lote 97): a loja na composição das referências do dono (vitrine de três colunas, CONJUNTOS)
-- e as imagens novas das caixas (Blender). Conferências de dados e de fonte.
-- Uso, a partir de vantuong65/:  lune run tests/luau/loja_vitrine.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Caixas = require(S .. "Caixas") :: any
local AssetIds = require(S .. "AssetIds") :: any
local Conjuntos = require(S .. "Conjuntos") :: any
local Commerce = require(S .. "Commerce") :: any

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
local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"

test("cada caixa do catálogo tem a imagem nova publicada e o render no Blender", function()
	local py = ler("tools/blender/caixas_loja.py")
	for _, c in Caixas.CAIXAS do
		local id = AssetIds.CaixaLoja[c.id]
		assert(type(id) == "number" and id > 0, string.format("sem imagem publicada: %s", c.id))
		assert(
			string.find(py, string.format('"%s": {', c.id), 1, true),
			string.format("sem receita no Blender: %s", c.id)
		)
		assert(fs.isFile(string.format("assets/ui/caixas/%s.png", c.id)), c.id)
	end
end)

test("o servidor resolve o decal na imagem; o cliente cai no caixote 3D sem ela", function()
	local iu = ler("src/ServerScriptService/Modules/ImagensUi.luau")
	assert(string.find(iu, "function ImagensUi.caixas()", 1, true) and string.find(iu, '"ImgCaixa_" .. id', 1, true))
	assert(string.find(iu, "ImagensUi.caixas()", 1, true))
	local ci = ler(C .. "CaixaImagem.luau")
	assert(string.find(ci, 'string.format("ImgCaixa_%s", caixaId)', 1, true))
	assert(string.find(ci, "reserva = caixote3d(holder, modelo)", 1, true), "a reserva 3D")
	local ct = ler(C .. "CaixasTela.client.luau")
	assert(string.find(ct, "CaixaImagem.desenha(arte, c.id", 1, true), "a aba CAIXAS usa a imagem")
end)

test("vitrine: três colunas, caixa paga só para quem pode comprar e o clique leva à caixa", function()
	local sc = ler(C .. "ShopController.client.luau")
	for _, t in { '"MERCADO DO DIA"', '"SEMPRE NA LOJA"', "CaixaGrande_%s", "CaixaLinha_%s", "COLETADOS %d/%d" } do
		assert(string.find(sc, t, 1, true), t)
	end
	assert(string.find(sc, 'if not (c.tipo == "paga" and c.bloqueio ~= nil) and c.disponivel ~= false then', 1, true))
	assert(string.find(sc, 'Bus.fire("caixa_foco", c.id)\n\tsetTab("caixas")', 1, true))
	assert(string.find(sc, "vit.LayoutOrder = -200", 1, true), "acima do destaque (-100)")
	local ct = ler(C .. "CaixasTela.client.luau")
	assert(
		string.find(ct, 'Bus.on("caixa_foco"', 1, true) and string.find(ct, 'string.format("Caixa_%s", foco)', 1, true)
	)
end)

test("abas: CONJUNTOS e CAIXAS na frente, INTENDÊNCIA oculta (o LB/RB pula)", function()
	local sc = ler(C .. "ShopController.client.luau")
	local a = assert(string.find(sc, '{ id = "loja", name = "DESTAQUES" }', 1, true))
	local b = assert(string.find(sc, '{ id = "conjuntos", name = "CONJUNTOS" }', a, true))
	local c = assert(string.find(sc, '{ id = "caixas", name = "CAIXAS" }', b, true))
	assert(a < b and b < c)
	assert(string.find(sc, '{ id = "intendencia", name = "INTENDÊNCIA", oculta = true }', 1, true))
	assert(string.find(sc, "if not TABS[i].oculta then", 1, true))
end)

test("conjuntos: cada um tem o passe à venda e a aba compra pelo próprio passe", function()
	for _, cj in Conjuntos.LISTA do
		assert((tonumber(Commerce.IDS[cj.key]) or 0) > 0, cj.key)
		assert(#cj.itens > 0, cj.key)
	end
	local sc = ler(C .. "ShopController.client.luau")
	assert(string.find(sc, "MarketplaceService:PromptGamePassPurchase(player, idPasse)", 1, true))
	assert(string.find(sc, "MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)", 1, true), "o SEU de quem tem")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
