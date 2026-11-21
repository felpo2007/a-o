--!strict
-- D-213 (lote 98): a animação da abertura das caixas e a vida da loja. A matemática (Shared/Efeitos)
-- e as ligações (texturas, sons, camadas da caixa aberta, regras da tela).
-- Uso, a partir de vantuong65/:  lune run tests/luau/efeitos.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Efeitos = require(S .. "Efeitos") :: any
local Caixas = require(S .. "Caixas") :: any
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
local function ler(p: string): string
	return (string.gsub(fs.readFile(p), "\r\n", "\n"))
end
local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"

test("roteiro: queda, tremor, estouro, saída e fim em ordem; curto de verdade", function()
	for modo, r in Efeitos.ROTEIRO do
		assert(r.pouso <= r.tremor and r.tremor < r.estouro and r.estouro < r.saida and r.saida < r.fim, modo)
	end
	assert(Efeitos.ROTEIRO.completa.fim <= 2.6, "a completa não passa de 2,6 s antes da roleta")
	assert(Efeitos.ROTEIRO.curta.fim <= 0.8, "a curta não passa de 0,8 s")
	assert(Efeitos.ROTEIRO.sem == nil, "sem efeitos: sem abertura")
end)

test("queda acelera até o chão; o amasso volta ao normal", function()
	local p = Efeitos.ROTEIRO.completa.pouso
	assert(Efeitos.queda(0, p) < -1.3 and Efeitos.queda(p, p) == 0 and Efeitos.queda(5, p) == 0)
	-- acelera: a segunda metade do tempo cobre mais caminho que a primeira
	local a = Efeitos.queda(p / 2, p) - Efeitos.queda(0, p)
	local b = Efeitos.queda(p, p) - Efeitos.queda(p / 2, p)
	assert(b > 2 * a, string.format("%.3f %.3f", a, b))
	local sx, sy = Efeitos.amasso(0)
	assert(sy < 1 and sx > 1, "amassa no pouso")
	sx, sy = Efeitos.amasso(1.5)
	assert(math.abs(sx - 1) < 0.001 and math.abs(sy - 1) < 0.001, "e volta")
end)

test("tremor cresce até o estouro; força 0 não mexe", function()
	local dur = 1.0
	local function pico(t0: number, t1: number): number
		local m = 0
		for k = 0, 200 do
			local t = t0 + (t1 - t0) * k / 200
			local _, _, g = Efeitos.tremor(t, dur, 1)
			m = math.max(m, math.abs(g))
		end
		return m
	end
	local cedo, tarde = pico(0, 0.2), pico(0.8, 1.0)
	assert(tarde > 2.5 * cedo, string.format("%.2f %.2f", cedo, tarde))
	assert(tarde <= 6.01, "no máximo 6 graus")
	local dx, dy, g = Efeitos.tremor(0.5, dur, 0)
	assert(dx == 0 and dy == 0 and g == 0)
	local _, dy2 = Efeitos.tremor(0.7, dur, 1)
	assert(dy2 <= 0, "os pulinhos são só para cima")
end)

test("tampa: sobe, tomba e some", function()
	local dx, dy, _, tr = Efeitos.tampa(0.15)
	assert(dy < 0 and dx > 0 and tr == 0, "sobe para o lado, ainda à vista")
	local _, _, g1 = Efeitos.tampa(0.2)
	local _, _, g2 = Efeitos.tampa(0.4)
	assert(g2 > g1, "gira")
	local _, _, _, tr2 = Efeitos.tampa(0.8)
	assert(tr2 == 1, "sumiu antes da roleta entrar")
	assert(
		Efeitos.ROTEIRO.completa.estouro + 0.75 <= Efeitos.ROTEIRO.completa.fim,
		"a tampa some antes da saída acabar"
	)
end)

test("faíscas: mesma semente, mesma explosão; o leque e a vida respeitados", function()
	local a = Efeitos.faiscas(40, 1965, -math.pi / 2, math.pi, 300, 800)
	local b = Efeitos.faiscas(40, 1965, -math.pi / 2, math.pi, 300, 800)
	local c = Efeitos.faiscas(40, 1966, -math.pi / 2, math.pi, 300, 800)
	assert(#a == 40)
	local iguais, diferentes = true, false
	for i = 1, 40 do
		if a[i].ang ~= b[i].ang or a[i].vel ~= b[i].vel then
			iguais = false
		end
		if a[i].ang ~= c[i].ang then
			diferentes = true
		end
		assert(a[i].ang >= -math.pi and a[i].ang <= 0, "dentro do leque de cima")
		assert(a[i].vel > 0 and a[i].vel <= 800 and a[i].vida > 0.5 and a[i].vida < 1.5)
	end
	assert(iguais and diferentes)
end)

test("partícula: sai do ponto, cai com a gravidade e some no fim da vida", function()
	local p = { ang = -math.pi / 2, vel = 500, vida = 1, tam = 1, atraso = 0, brilho = false }
	local x, y, tr = Efeitos.particula(p, 0, 500, 2.6)
	assert(x == 0 and y == 0 and tr == 1, "nasce no ponto, ainda apagada")
	local _, y1, tr1 = Efeitos.particula(p, 0.1, 500, 2.6)
	assert(y1 < 0 and tr1 < 0.1, "sobe e acende")
	-- a altura máxima passa e ela volta a descer
	local _, yA = Efeitos.particula(p, 0.4, 500, 2.6)
	local _, yB = Efeitos.particula(p, 0.9, 500, 2.6)
	assert(yB > yA, "a gravidade puxa de volta")
	local _, _, tr2 = Efeitos.particula(p, 1, 500, 2.6)
	assert(tr2 == 1, "morta no fim da vida")
	local vel, rumo = Efeitos.rumo(p, 0, 500, 2.6)
	assert(math.abs(vel - 500) < 0.01 and math.abs(rumo + 90) < 0.01, "rastro alinhado com a subida")
end)

test("quantas: cresce com a raridade; curta menos; sem efeitos, nenhuma", function()
	local antes = 0
	for _, r in { "comum", "incomum", "raro", "epico", "lendario" } do
		local n = Efeitos.quantas(r, "completa")
		assert(n > antes, r)
		antes = n
		assert(Efeitos.quantas(r, "curta") < n and Efeitos.quantas(r, "sem") == 0, r)
	end
	for _, r in Caixas.RARIDADES or {} do
		assert(Efeitos.FORCA[r.id] ~= nil, "força da luz de " .. tostring(r.id))
	end
end)

test("vida da loja: o brilho passa e some; o pulso e as brasas ficam no quadro", function()
	local escondida = 0
	for k = 0, 599 do
		local x = Efeitos.varredura(k * 0.01, 6, 0.9)
		assert(x >= -1.5 and x <= 1.5)
		if x == -1.5 then
			escondida += 1
		end
	end
	assert(escondida > 480, "o brilho passa rápido e descansa")
	for k = 0, 40 do
		local p = Efeitos.pulso(k * 0.1, 2)
		assert(p >= 0 and p <= 1)
	end
	for _, b in Efeitos.brasas(12, 7) do
		for k = 0, 50 do
			local x, y, tr = Efeitos.brasa(b, k * 0.37)
			assert(x > 0 and x < 1 and y >= 0 and y <= 1 and tr >= 0 and tr <= 1)
		end
	end
end)

test("camadas da caixa aberta, texturas e sons publicados e resolvidos", function()
	for _, c in Caixas.CAIXAS do
		for _, camada in { "corpo", "tampa" } do
			local k = string.format("%s_%s", c.id, camada)
			assert((tonumber(AssetIds.CaixaLoja[k]) or 0) > 0, "sem decal: " .. k)
			assert(fs.isFile(string.format("assets/ui/caixas/%s.png", k)), "sem render: " .. k)
		end
	end
	local iu = ler("src/ServerScriptService/Modules/ImagensUi.luau")
	for _, n in { "brilho", "faisca", "raio", "anel", "cintila" } do
		assert((tonumber(AssetIds.Images["efeito_" .. n]) or 0) > 0, "sem decal: efeito_" .. n)
		assert(fs.isFile(string.format("assets/ui/efeitos/%s.png", n)), n)
	end
	assert(string.find(iu, 'table.insert(ImagensUi.KEYS, "efeito_" .. nome)', 1, true))
	for _, s in { "caixa_pouso", "caixa_tremor", "caixa_estouro" } do
		assert((tonumber(AssetIds.Sounds[s]) or 0) > 0, "sem som: " .. s)
	end
	local ct = ler(C .. "CaixasTela.client.luau")
	for _, s in { '"caixa_pouso"', '"caixa_tremor"', '"caixa_estouro"' } do
		assert(string.find(ct, "tocar(" .. s, 1, true), s)
	end
end)

test("tela: a abertura usa a cor da caixa, respeita os efeitos e o movimento reduzido", function()
	local ct = ler(C .. "CaixasTela.client.luau")
	assert(string.find(ct, "local acento = CaixaImagem.ACENTO[tostring(c.id)] or V.AMBAR", 1, true), "a cor da caixa")
	assert(string.find(ct, 'if anim ~= "sem" and not UiEfeitos.calmo() then', 1, true), "sem efeitos: sem abertura")
	assert(string.find(ct, "t = math.max(t, R.fim)", 1, true), "o PULAR corta a abertura")
	-- a abertura vem antes da roleta e não sabe o resultado (a assinatura não recebe o res)
	assert(
		string.find(
			ct,
			"local function introCaixa(panel: Frame, W: number, H: number, c: any, modo: string, pulou: () -> boolean): Frame",
			1,
			true
		)
	)
	local ue = ler(C .. "UiEfeitos.luau")
	for _, f in { "faiscas", "onda", "raios", "halo", "cintilas", "varre", "brasas", "tremer" } do
		local a = assert(string.find(ue, "function UiEfeitos." .. f .. "(", 1, true), f)
		local corpo = string.sub(ue, a, a + 900)
		if f ~= "halo" and f ~= "raios" then
			assert(string.find(corpo, "UiEfeitos.calmo()", 1, true), "movimento reduzido: " .. f)
		end
	end
	assert(string.find(ue, "if not naTela(", 1, true), "os laços da loja param com a loja fechada")
	local sc = ler(C .. "ShopController.client.luau")
	assert(string.find(sc, "UiEfeitos.brasas(b, acento", 1, true) and string.find(sc, "UiEfeitos.varre(b, 6", 1, true))
end)

test("Studio: as camadas abertas esperam baixar; o quadro travado não pula fase", function()
	local ct = ler(C .. "CaixasTela.client.luau")
	assert(string.find(ct, "t += math.min(dt, 0.1)", 1, true), "quadro travado conta no máximo 0,1 s")
	assert(string.find(ct, "corpo.IsLoaded and tampa.IsLoaded", 1, true), "a troca espera as camadas")
	assert(string.find(ct, "im.ImageTransparency = 0.98", 1, true), "camada à vista (com 1 não baixa)")
	assert(string.find(ct, "preCaixa(tostring(c.id))", 1, true), "pré-carrega no ABRIR")
	assert(string.find(ct, '"VT65DevAbrir"', 1, true), "gancho do Studio pelo caminho do botão")
	local sc = ler(C .. "ShopController.client.luau")
	assert(
		string.find(sc, "ItemArte.desenha(arte, cj.itens[k], lado, { soldado = true })", 1, true),
		"o leque dos CONJUNTOS veste o soldado (Fundador de pano liso)"
	)
end)

-- D-214: o luau-lsp não acusa membro que não existe no UiKit (o `UiKit.estadoTag` do ARMÁRIO teria
-- quebrado a aba na loja publicada): cada UiKit.<nome> usado nos controladores tem que existir lá
-- (função, campo, reexporte do Estilo ou tipo exportado)
test("UiKit: todo membro usado nos controladores existe", function()
	local uk = ler(C .. "UiKit.luau")
	local existe: { [string]: boolean } = {}
	for linha in string.gmatch(uk .. "\n", "([^\n]*)\n") do
		local n = string.match(linha, "^UiKit%.([%w_]+)%s*=") or string.match(linha, "^function UiKit%.([%w_]+)")
		local tp = string.match(linha, "^export type ([%w_]+)")
		if n then
			existe[n] = true
		end
		if tp then
			existe[tp] = true
		end
	end
	local faltam = {}
	for _, nome in fs.readDir(C) do
		if string.sub(nome, -5) == ".luau" and nome ~= "UiKit.luau" then
			local src = ler(C .. nome)
			for m in string.gmatch(src, "UiKit%.([%a_][%w_]*)") do
				if not existe[m] then
					table.insert(faltam, nome .. ": UiKit." .. m)
				end
			end
		end
	end
	assert(#faltam == 0, table.concat(faltam, ", "))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
