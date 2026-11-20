--!strict
-- D-205 (prompt de interface, lote 90): fundação da interface. Cores por função com contraste medido,
-- estados com cor + símbolo + palavra, preferências do jogador (movimento, transparência, texto),
-- confirmação, abas e foco.
-- Uso, a partir de vantuong65/:  lune run tests/luau/componentes.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local InputMap = require("../../src/ReplicatedStorage/Shared/InputMap") :: any

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local F = "src/ReplicatedFirst/"

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

-- o checkout do Windows tem CRLF: as âncoras com quebra de linha são escritas em LF
local function ler(p: string): string
	return (string.gsub(fs.readFile(p), "\r\n", "\n"))
end

local function has(src: string, s: string): boolean
	return string.find(src, s, 1, true) ~= nil
end

local estilo = ler(F .. "Estilo.luau")
local kit = ler(C .. "UiKit.luau")

-- cor do Estilo.V pelo nome (lida do código, não copiada)
local function cor(nome: string): { number }
	local r, g, b = string.match(estilo, "\n\t" .. nome .. " = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
	assert(r and g and b, "cor não achada: " .. nome)
	return { tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number }
end

-- contraste do WCAG 2 (luminância relativa)
local function lum(c: { number }): number
	local function ch(v: number): number
		local s = v / 255
		return if s <= 0.03928 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
local function contraste(a: { number }, b: { number }): number
	local la, lb = lum(a), lum(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

test("cores por função: texto sobre o âmbar e foco com contraste medido (§3, §20)", function()
	local amb, txt = cor("AMBAR"), cor("AMBAR_TEXTO")
	local k1 = contraste(amb, txt)
	assert(k1 >= 7, string.format("texto do botão principal: %.2f:1 (pede 7:1)", k1))
	local k2 = contraste(cor("AMBAR_HI"), txt)
	assert(k2 >= 7, string.format("principal com o foco: %.2f:1", k2))
	local k3 = contraste(cor("TEXT"), cor("PANEL"))
	assert(k3 >= 7, string.format("texto no painel: %.2f:1", k3))
	local k4 = contraste(cor("DIM"), cor("PANEL"))
	assert(k4 >= 4.5, string.format("texto secundário: %.2f:1 (pede 4,5:1)", k4))
	-- indicador de foco: 3:1 contra o painel e contra a linha de lista (WCAG 1.4.11)
	for _, fundo in { "PANEL", "PANEL_2", "PANEL_3" } do
		local k = contraste(cor("FOCO"), cor(fundo))
		assert(k >= 3, string.format("foco sobre %s: %.2f:1", fundo, k))
	end
	print(string.format("       âmbar/texto %.1f:1, texto/painel %.1f:1, secundário %.1f:1", k1, k3, k4))
end)

test("estados: cor + símbolo + palavra, e o rótulo é a frase traduzível (§3)", function()
	for _, nome in { "adquirido", "equipado", "bloqueado", "indisponivel", "selecionado", "carregando", "erro" } do
		local linha = string.match(estilo, "\n\t" .. nome .. " = (%b{})")
		assert(linha, "estado sem linha: " .. nome)
		local simb = string.match(linha, 'simbolo = "([^"]*)"')
		local texto = string.match(linha, 'texto = "([^"]*)"')
		local rotulo = string.match(linha, 'rotulo = "([^"]*)"')
		assert(simb and simb ~= "", nome .. " sem símbolo")
		assert(texto and texto ~= "", nome .. " sem palavra")
		assert(rotulo == simb .. " " .. texto, nome .. ": rótulo diferente de símbolo + palavra")
	end
	assert(has(estilo, "function Estilo.estadoTag("), "etiqueta de estado")
	assert(has(estilo, "function Estilo.cardEstado("), "estado no cartão de item")
end)

test("preferências do Roblox: movimento, transparência e tamanho do texto (§4, §20)", function()
	assert(has(estilo, 'lerGui("ReducedMotionEnabled")'), "movimento reduzido do Roblox")
	assert(has(estilo, 'lerGui("PreferredTransparency")'), "transparência preferida")
	assert(has(estilo, 'lerGui("PreferredTextSize")'), "tamanho de texto preferido")
	-- escala do texto: Medium = 1 e crescente
	local ks = {}
	for _, n in { "Medium", "Large", "Larger", "Largest" } do
		local v = tonumber(string.match(estilo, n .. " = ([%d%.]+)"))
		assert(v, "TEXTO_K sem " .. n)
		table.insert(ks, v :: number)
	end
	assert(ks[1] == 1, "Medium muda o tamanho")
	for i = 2, #ks do
		assert(ks[i] > ks[i - 1], "TEXTO_K não cresce")
	end
	assert(ks[#ks] <= 1.5, "Largest grande demais para os quadros fixos")
	assert(has(estilo, "f.BackgroundTransparency = Estilo.fundo(tr or 0)"), "painel segue a transparência")
	assert(has(estilo, "local s = math.floor(size * Estilo.textoK() + 0.5)"), "texto segue o tamanho")
	assert(InputMap.DEFAULTS.uiReduceMotion == false, "opção do jogo começa desligada")
end)

test("transições de 0,15 a 0,30 s (§4)", function()
	local q = tonumber(string.match(estilo, "Estilo%.QUICK = TweenInfo%.new%(([%d%.]+)"))
	local s = tonumber(string.match(estilo, "Estilo%.SOFT = TweenInfo%.new%(([%d%.]+)"))
	assert(q and s, "QUICK/SOFT não achados")
	assert((q :: number) >= 0.15 and (s :: number) <= 0.3 and (q :: number) < (s :: number), "fora da faixa")
	assert(has(kit, "UiKit.QUICK = Estilo.QUICK") and has(kit, "UiKit.SOFT = Estilo.SOFT"), "UiKit usa os mesmos")
end)

test("movimento reduzido: o que desliza, cresce ou pulsa para (§20)", function()
	assert(has(kit, "if Estilo.reduzMovimento() then") and has(kit, "i = TweenInfo.new(0)"), "UiKit.tween")
	assert(has(estilo, "local parado = Estilo.reduzMovimento()"), "Estilo.enter")
	local fontes: { [string]: string } = {
		["LobbyScene.luau"] = "camDur = if UiKit.Estilo.reduzMovimento() then 0.01 else MOVE_TIME",
		["DiariaEntrada.client.luau"] = "if on and UiKit.Estilo.reduzMovimento() then",
		["MenuPrincipal.client.luau"] = "if ring and not UiKit.Estilo.reduzMovimento() then",
		["CartaView.luau"] = "if not UiKit.Estilo.reduzMovimento() then",
		["CenaBaixa.luau"] = "if Estilo.reduzMovimento() then",
	}
	for arq, ancora in fontes do
		assert(has(ler(C .. arq), ancora), arq .. " não segue o movimento reduzido")
	end
	local ls = ler(F .. "LoadingScreen.client.luau")
	assert(has(ls, "Estilo.reduzMovimento()"), "tela de entrada")
	local gm = ler(C .. "GameMenu.client.luau")
	assert(has(gm, '"Reduzir movimento da interface", "uiReduceMotion"'), "opção nas Configurações")
	assert(has(kit, 'player:SetAttribute("VT65ReduzMovimento"'), "a opção chega ao Estilo")
end)

test("ação principal em âmbar: botão do kit, JOGAR e CONTINUAR (§3)", function()
	assert(has(estilo, 'b.BackgroundColor3 = if k == "primary" then Estilo.V.AMBAR'), "Estilo.button")
	assert(has(kit, "return Estilo.V.AMBAR, Estilo.V.AMBAR_HI"), "realce do principal")
	local mp = ler(C .. "MenuPrincipal.client.luau")
	assert(has(mp, "AMBAR"), "JOGAR em âmbar")
	local ls = ler(F .. "LoadingScreen.client.luau")
	assert(has(ls, 'stampButton(868, 312, "CONTINUAR", EV.AMBAR, EV.AMBAR_HI'), "CONTINUAR em âmbar")
end)

test("botão: pressionado, carregando sem pedido duplicado, erro com o motivo (§3, §9)", function()
	assert(has(kit, "UiKit.tween(scl, UiKit.QUICK, { Scale = if v then 0.97"), "afunda ao apertar")
	assert(has(kit, "a.carregando = function(v: boolean)"), "carregando")
	assert(string.find(kit, 'parts%.sub%.Text = "…"%s+a%.enabled%(false%)'), "carregando trava o clique")
	assert(has(kit, "a.erro = function(msg: string)"), "erro")
	assert(has(kit, "if on then\n\t\t\tonClick()"), "clique só com o botão ligado")
	-- §21: a conexão do dispositivo sai junto com o botão
	assert(
		string.find(kit, "local devConn = Input%.DeviceChanged:Connect%(glyph%)%s+b%.Destroying:Connect"),
		"vazamento"
	)
end)

test("confirmação: foco em VOLTAR, preso na janela, B volta, foco devolvido (§18, §19)", function()
	assert(has(kit, "function UiKit.modal(o: ModalOpts): () -> ()"), "UiKit.modal")
	assert(has(kit, "UiKit.principal(voltar.button)"), "foco inicial em VOLTAR")
	assert(has(kit, "painel.SelectionGroup = true"), "foco preso na janela")
	assert(has(kit, 'if f and UiKit.backFor("confirma") then'), "B / Backspace voltam")
	assert(has(kit, 'UiKit.opened("confirma", g.DisplayOrder)'), "entra na pilha de telas")
	assert(has(kit, "if feito then\n\t\t\treturn"), "responde uma vez só")
	-- a pilha guarda o foco de antes e devolve ao fechar
	assert(has(kit, "table.insert(stack, at, { name = name, order = o, foco = antes })"), "guarda o foco")
	assert(has(kit, "if focoValido(f) then\n\t\t\t\t\t\tGuiService.SelectedObject = f"), "devolve o foco")
	-- o vigia de foco não puxa o foco de volta para a tela de baixo
	assert(has(kit, "and not focoPorCima(w.root) then"), "vigia respeita a tela de cima")
	-- a janela fica acima de todas as telas de menu, e o cursor virtual acima dela
	local ordem = tonumber(string.match(kit, 'UiKit%.screen%("VT65Confirma", (%d+)%)'))
	assert(ordem, "ordem da confirmação")
	-- de propósito por cima: o aviso de conexão perdida (Reconexao, 100)
	local acima = { ["UiKit.luau"] = true, ["VirtualCursor.luau"] = true, ["Reconexao.client.luau"] = true }
	for _, arq in fs.readDir(C) do
		if string.match(arq, "%.luau$") and not acima[arq] then
			local src = ler(C .. arq)
			for n in string.gmatch(src, 'UiKit%.screen%("[^"]+", (%d+)%)') do
				local nn: number = tonumber(n) or 0
				assert(nn < (ordem :: number), arq .. " fica por cima da confirmação")
			end
		end
	end
	local vc = tonumber(string.match(ler(C .. "VirtualCursor.luau"), "gui%.DisplayOrder = (%d+)"))
	assert(vc and vc > (ordem :: number), "o cursor virtual some atrás da confirmação")
end)

test("menu do jogo: restaurar padrões e sair do squad pedem confirmação (§18)", function()
	local gm = ler(C .. "GameMenu.client.luau")
	local n = 0
	for ini in string.gmatch(gm, '()"[%a]:reset"') do
		n += 1
		local trecho = string.sub(gm, ini, ini + 160)
		assert(has(trecho, "comConfirma("), "reset sem confirmação: " .. string.sub(trecho, 1, 12))
	end
	assert(n >= 6, "esperava 6 resets, achou " .. n)
	local leave = string.find(gm, '"s:leave"', 1, true)
	assert(leave and has(string.sub(gm, leave, leave + 140), "comConfirma("), "sair do squad sem confirmação")
	-- com a confirmação por cima, LB/RB e o direcional não mexem no menu de baixo
	assert(has(gm, 'or (topo ~= nil and topo ~= "menu")'), "busy() vê a tela de cima")
end)

test("abas: LB/RB e Q/E na ponta, só na tela de cima, sem sobra ao destruir (§18, §19)", function()
	assert(has(kit, "function UiKit.abas("), "UiKit.abas")
	assert(has(kit, 'dica1(imgA, keyA, "ui_tab_prev")') and has(kit, 'dica1(imgB, keyB, "ui_tab_next")'), "dicas")
	assert(has(kit, "if a.tela == topo and naTela(row) then"), "só a tela de cima")
	assert(has(kit, "abasVivas[row] = nil\n\t\tdevConn:Disconnect()"), "sai do registro ao destruir")
	-- as ações existem no contexto do menu com LB/RB e Q/E
	local achou = 0
	for _, a in InputMap.ACTIONS do
		if a.ctx == "menu" and (a.id == "ui_tab_prev" or a.id == "ui_tab_next") then
			achou += 1
			assert(a.pad == "ButtonL1" or a.pad == "ButtonR1", "aba fora de LB/RB: " .. a.id)
			assert(a.key == "Q" or a.key == "E", "aba fora de Q/E: " .. a.id)
		end
	end
	assert(achou == 2, "ui_tab_prev/next no menu")
end)

test("foco inicial na ação principal (§19)", function()
	assert(has(kit, "local f = principalEm(root) or firstSelectable(root)"), "UiKit.focus")
	local d = ler(C .. "DiariaEntrada.client.luau")
	assert(has(d, "UiKit.principal(mainBtn.button)"), "diária abre no RESGATAR")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
