--!strict
-- Lote 102 (D-222 a D-229): o lobby sem personagem, a preparação em quatro passos, o mapa de nascer, o
-- horário votado, o armário, o passe e as ordens do dia.
-- Uso, a partir de vantuong65/:  lune run tests/luau/preparacao.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Horarios = require("../../src/ReplicatedStorage/Shared/Horarios") :: any

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

test("horários: quatro, com a luz completa, e a noite azulada", function()
	assert(#Horarios.LISTA == 4)
	for _, h in Horarios.LISTA do
		assert(h.hora >= 0 and h.hora < 24, h.id)
		assert(#h.luz.cor == 3 and #h.luz.tinta == 3, h.id)
		assert(type(h.luz.saturacao) == "number", h.id)
	end
	local noite = Horarios.por("noite")
	assert(noite.luz.tinta[3] > noite.luz.tinta[1], "a noite puxa para o azul")
	assert(noite.luz.saturacao < 0, "a noite tira cor")
	local tarde = Horarios.por("tarde")
	assert(tarde.hora > 18 and tarde.hora < 19.2, "a luz dourada vem antes do pôr do sol")
	assert(Horarios.PADRAO == "tarde" and tarde.parado == true, "D-248: fim de tarde, sem escurecer na partida")
	assert(tarde.luz.atm and tarde.luz.bloom and tarde.luz.raios, "D-248: céu, brilho e raios próprios")
end)

test("horários: apuração com maioria, empate, voto inválido e sem voto", function()
	assert(Horarios.apurar({}) == Horarios.PADRAO, "sem voto")
	assert(Horarios.apurar({ a = "noite", b = "noite", c = "tarde" }) == "noite", "maioria")
	assert(Horarios.apurar({ a = "noite", b = "manha" }) == "manha", "empate: o primeiro da lista")
	local vence, conta = Horarios.apurar({ a = "lua", b = "tarde" })
	assert(vence == "tarde", "o inválido não conta")
	assert(conta.lua == nil and conta.tarde == 1)
end)

test("o servidor valida o voto e aplica o horário", function()
	local rs = ler("src/ServerScriptService/Modules/RodadaService.luau")
	assert(has(rs, 'if type(hora) == "string" and Horarios.por(hora) then'), "voto validado")
	local ls = ler("src/ServerScriptService/Modules/LightingService.luau")
	assert(has(ls, 'cc.Name = "VT65Hora"'), "a cor do horário num efeito próprio")
	assert(has(ls, "local h = Horarios.por(id) or Horarios.por(Horarios.PADRAO)"), "id ruim cai no padrão")
end)

test("fundo do lobby: cobre qualquer tela sem distorcer", function()
	local src = ler(C .. "FundoLobby.luau")
	local corpo = string.match(src, "function FundoLobby%.cobre.-\nend\n")
	assert(corpo, "cobre não achado")
	local chunk = luau.load("local FundoLobby = {}\n" .. (corpo :: string) .. "return FundoLobby")
	local F = (chunk :: any)()
	for _, t in { { 1920, 1080 }, { 800, 360 }, { 839, 656 }, { 2560, 1080 } } do
		local w, h = F.cobre(t[1], t[2], 16 / 9)
		assert(w >= t[1] - 1e-6 and h >= t[2] - 1e-6, "sobra borda")
		assert(math.abs(w / h - 16 / 9) < 1e-6, "distorceu")
	end
	local a, b = F.cobre(0, 0, 16 / 9)
	assert(a == 0 and b == 0)
end)

test("lobby e preparação sem personagem; imagem só ao passar por cima", function()
	local ds = ler(C .. "DeployScreen.luau")
	assert(not has(ds, "LobbyScene"), "a mesa 3D saiu")
	assert(not has(ds, "SoldierPreview"), "sem soldado na preparação")
	local mp = ler(C .. "MenuPrincipal.client.luau")
	assert(has(mp, "IMG_REPOUSO, IMG_FOCO = 1, 0"), "imagens só no foco")
	assert(has(mp, "FundoLobby.novo(fundo"), "o fundo parado")
end)

test("preparação: os quatro passos e o equipamento na escolha da classe", function()
	local p = ler(C .. "Preparacao.luau")
	local ordem = {}
	for _, id in { '"TIME"', '"GRUPO"', '"CLASSE"', '"ONDE NASCER"' } do
		local i = string.find(p, id, 1, true)
		assert(i, id)
		table.insert(ordem, i :: number)
	end
	for i = 2, #ordem do
		assert(ordem[i] > ordem[i - 1], "ordem dos passos")
	end
	assert(has(p, '"ARMA PRINCIPAL"') and has(p, '"SECUNDÁRIA"') and has(p, '"EQUIPAMENTO"'), "abas")
	assert(has(p, "Kit_Set"), "o equipamento vai ao servidor")
	assert(has(p, "Peso no limite"), "explica o impedimento")
end)

test("mapa de nascer: vista aérea limpa, com pinos", function()
	local ids = ler("src/ReplicatedStorage/Shared/AssetIds.luau")
	local bloco = string.match(ids, "CartaImages = (%b{})")
	assert(bloco, "CartaImages")
	for _, k in { "nw", "ne", "sw", "se" } do
		local v = string.match(bloco :: string, k .. " = (%d+)")
		assert(v and tonumber(v) ~= 0, "bloco sem imagem: " .. k)
	end
	local cv = ler(C .. "CartaView.luau")
	assert(has(cv, 'S.layers.eventos.Visible = mode ~= "spawn"'), "sem o raio dos eventos")
	assert(has(cv, 'local limpo = S.mode == "spawn"'), "pino com etiqueta")
	assert(has(cv, 'if trava then "🔒" else pointGlyph(pt)'), "cadeado no bloqueado")
end)

test("armário: categorias, estados que não se confundem e motivo de não ter", function()
	local a = ler(C .. "ArmarioTela.luau")
	for _, id in { "armas", "acabamentos", "uniformes", "camuflagem", "visuais", "comemoracao" } do
		assert(has(a, string.format('id = "%s"', id)), id)
	end
	assert(has(a, '"✓ EQUIPADO"') and has(a, '"SEU"') and has(a, '"🔒 BLOQUEADO"'), "os estados")
	local sc = ler(C .. "ShopController.client.luau")
	assert(has(sc, 'Net.event("Commerce_Equip"):FireServer(f, slot, id)'), "os visuais comprados continuam")
	local ps = ler("src/ServerScriptService/Modules/ProgressionService.luau")
	assert(has(ps, "porLado = {"), "o equipado de cada lado")
	assert(has(a, '"No conjunto em Game Pass"') and has(a, '"VER NA INTENDÊNCIA"'), "onde conseguir")
	assert(has(a, 'Net.event("Gear_Equip"):FireServer(s.id, not e.eq, e.arma, f)'), "equipar pelo servidor")
end)

test("ordens do dia: toda ordem tem imagem e os estados são escritos", function()
	local cat = ler(C .. "ArteCatalogo.luau")
	local bloco = string.match(cat, "local ORDEM = (%b{})")
	assert(bloco, "ORDEM")
	local m = ler("src/ReplicatedStorage/Shared/Missoes.luau")
	local n = 0
	for id in string.gmatch(m, 'id = "[dw]_([%w_]+)"') do
		n += 1
		assert(string.find(bloco :: string, "%f[%w_]" .. id .. " = "), "ordem sem imagem: " .. id)
	end
	assert(n >= 15, "ordens lidas: " .. n)
	local t = ler(C .. "TelaMissoes.client.luau")
	assert(has(t, '"EM ANDAMENTO"') and has(t, '"CONCLUÍDA · RECEBA O PRÊMIO"'), "estados")
	assert(has(t, "local canClaim = m.done == true and not claimed"), "não recebe duas vezes")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
