--!strict
-- D-207 (lote 92): a loja sobre o palco do lobby, a compra só pelo destaque (com os estados) e os
-- códigos de resgate.
-- Uso, a partir de vantuong65/:  lune run tests/luau/loja.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local Codigos = require("../../src/ReplicatedStorage/Shared/Codigos")

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

local shop = ler("src/StarterPlayer/StarterPlayerScripts/Controllers/ShopController.client.luau")
local camp = ler("src/ServerScriptService/Modules/CampanhaService.luau")

test("códigos: válido, inválido, vencido, ainda não e já usado (§9)", function()
	local d = Codigos.LISTA[1]
	assert(d, "lista vazia")
	local dentro = math.max(d.de, 0) + 1
	local ok, motivo = Codigos.validar(d.codigo, dentro, {})
	assert(ok and motivo == "ok", "válido: " .. motivo)
	-- o jogador digita em minúscula, com espaço ou traço
	local baixo = string.lower(string.sub(d.codigo, 1, 4)) .. " - " .. string.sub(d.codigo, 5)
	assert((Codigos.validar(baixo, dentro, {})), "limpeza do texto")
	assert(select(2, Codigos.validar("NAOEXISTE123", dentro, {})) == "invalido", "inválido")
	assert(select(2, Codigos.validar("ABC$%", dentro, {})) == "invalido", "caractere estranho")
	assert(select(2, Codigos.validar(string.rep("A", Codigos.MAX + 1), dentro, {})) == "invalido", "longo demais")
	assert(select(2, Codigos.validar(123, dentro, {})) == "invalido", "não é texto")
	assert(select(2, Codigos.validar(d.codigo, d.ate + 1, {})) == "vencido", "vencido")
	if d.de > 0 then
		assert(select(2, Codigos.validar(d.codigo, d.de - 1, {})) == "ainda_nao", "ainda não")
	end
	local usados = { [Codigos.chave(d.codigo)] = true }
	assert(select(2, Codigos.validar(d.codigo, dentro, usados)) == "usado", "já usado")
	for _, m in { "invalido", "vencido", "ainda_nao", "usado", "espera" } do
		assert(Codigos.MENSAGEM[m], "sem mensagem: " .. m)
	end
end)

test("códigos: cabem no mapa de posse da campanha (chave < 48) e com prêmio", function()
	local vistos = {}
	for _, d in Codigos.LISTA do
		assert(Codigos.limpar(d.codigo) == d.codigo, "código fora do formato: " .. d.codigo)
		assert(#Codigos.chave(d.codigo) < 48, "chave longa: " .. d.codigo)
		assert(d.cr > 0 or d.estrelas > 0, "código sem prêmio: " .. d.codigo)
		assert(d.ate > d.de, "validade invertida: " .. d.codigo)
		assert(not vistos[d.codigo], "código repetido: " .. d.codigo)
		vistos[d.codigo] = true
	end
end)

test("servidor: o código vale uma vez, grava na hora e limita tentativas", function()
	assert(has(camp, 'elseif op == "code_redeem" then'), "operação")
	assert(has(camp, "Codigos.validar(msg.code, os.time(), c.owned)"), "valida no servidor")
	assert(has(camp, "c.owned[Codigos.chave(d.codigo)] = true"), "marca o uso")
	assert(has(camp, "ProgressionService.bonus(p, 0, d.cr,"), "créditos pelo bônus")
	assert(has(camp, "#recentes >= Codigos.TENTATIVAS"), "limite de tentativas")
	-- grava logo depois de entregar
	local i = string.find(camp, 'elseif op == "code_redeem" then', 1, true) :: number
	local j = string.find(camp, 'elseif op == "card_set" then', i, true) :: number
	assert(has(string.sub(camp, i, j), "task.spawn(PlayerData.save, p)"), "grava na hora")
end)

test("loja: as categorias do §9 e o painel à esquerda do soldado", function()
	for _, n in { '"DESTAQUES"', '"MERCADO"', '"CAIXAS"', '"CÓDIGOS"' } do
		assert(has(shop, n), "aba faltando: " .. n)
	end
	assert(has(shop, "folder.AnchorPoint = Vector2.new(0, 0.5)"), "painel à esquerda")
	assert(has(shop, "pintarFundo(LobbyPalco.aberto())"), "sobre o palco no lobby")
	assert(has(shop, "Progression.money(cr)"), "saldo de créditos")
end)

test("loja: o cartão não compra; a compra sai do destaque, sem pedido duplicado (§9)", function()
	-- nenhum botão de cartão liga direto na ação de compra
	assert(not has(shop, "UiKit.bind(bt, o.action"), "cartão comprando direto")
	assert(
		has(shop, "setHero(o)\n\t\t\tUiKit.tween(panel, UiKit.SOFT, { CanvasPosition = Vector2.zero })"),
		"cartão leva ao destaque"
	)
	assert(has(shop, "if compraAtiva then\n\t\treturn -- sem pedido duplicado"), "trava")
	assert(has(shop, "hero.buy.carregando(true)"), "em andamento")
	assert(has(shop, 'b.erro("Compra cancelada")'), "cancelada")
	assert(has(shop, 'b.label.Text = "ENTREGANDO…"'), "entregando")
	assert(has(shop, 'b.erro("Entrega pendente")'), "entrega pendente")
	assert(has(shop, "MarketplaceService.PromptGamePassPurchaseFinished:Connect"), "fim da janela do Roblox")
end)

test("loja: o armário usa o último lado no lobby (o soldado do palco veste na hora)", function()
	assert(has(shop, 'JogarAgora.decode(player:GetAttribute("UltimaEscolha"))'), "último lado")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
