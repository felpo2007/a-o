--!strict
-- D-206 (lote 91): o lobby novo. O palco do soldado (LobbyPalco), o soldado do próprio jogador
-- (PreviewService.pessoal) e o menu principal na composição das referências do dono.
-- Uso, a partir de vantuong65/:  lune run tests/luau/lobby.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local S = "src/ServerScriptService/Modules/"

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

local palco = ler(C .. "LobbyPalco.luau")
local menu = ler(C .. "MenuPrincipal.client.luau")
local preview = ler(S .. "PreviewService.luau")

-- as chaves do acampamento no servidor
local function acampamento(): { string }
	local bloco = string.match(preview, "local ACAMPAMENTO = (%b{})")
	assert(bloco, "ACAMPAMENTO não achado")
	local out = {}
	for k in string.gmatch(bloco :: string, '"([%w_]+)"') do
		table.insert(out, k)
	end
	return out
end

test("acampamento: todo modelo existe no AssetIds.Models (no Studio, os _v65 não carregavam)", function()
	local ks = acampamento()
	assert(#ks >= 15, "acampamento pequeno: " .. #ks)
	for _, k in ks do
		local id = AssetIds.Models[k]
		assert(type(id) == "number" and id > 0, "modelo sem ID no AssetIds.Models: " .. k)
	end
end)

test("palco: cada vaga usa um modelo que o servidor manda", function()
	local set = {}
	for _, k in acampamento() do
		set[k] = true
	end
	local n = 0
	for k in string.gmatch(palco, 'vaga%(h, "([%w_]+)"') do
		n += 1
		assert(set[k], "vaga sem modelo no servidor: " .. k)
	end
	assert(n >= 25, "vagas: " .. n)
end)

test("palco: enquadramentos a 2,5 m ou mais do soldado e o alvo perto do meio da tela", function()
	-- no Studio, a 2,25 m a arma enchia a tela e, a 1,55 m, o rosto
	local n = 0
	for nome, x, y, z, rest in
		string.gmatch(palco, "\n\t(%a+) = { cam = Vector3%.new%(([%-%d%.]+), ([%-%d%.]+), ([%-%d%.]+)%)(.-)}")
	do
		local dist = math.sqrt((tonumber(x) :: number) ^ 2 + (tonumber(z) :: number) ^ 2)
		assert(dist >= 2.5, string.format("%s: câmera a %.2f m", nome, dist))
		local yy = tonumber(string.match(rest, "y = ([%d%.]+)"))
		assert(yy and yy >= 0.35 and yy <= 0.65, nome .. ": alvo fora do meio")
		assert((tonumber(y) :: number) > 0.8, nome .. ": câmera no chão")
		n += 1
	end
	assert(n >= 7, "quadros: " .. n)
	-- o soldado vai para o meio do espaço livre entre as colunas (medido na tela, pelo menu)
	assert(has(menu, "LobbyPalco.telaX = math.clamp((l + r) / 2 / math.max(w, 1), 0.4, 0.8)"), "telaX")
	assert(has(palco, "local yaw = math.atan((x - 0.5) * 2 * tv * aspect)"), "mira pela tela")
end)

test("soldado do próprio jogador: como no spawn, só para o dono, refeito ao trocar", function()
	assert(has(preview, "Characters.describe(faction, equipped, player.UserId)"), "describe com os cosméticos")
	assert(has(preview, "Characters.dress(model, faction, equipped)"), "dress com os cosméticos")
	assert(has(preview, 'model:SetAttribute("Dono", player.UserId)'), "dono no modelo")
	assert(
		has(preview, 'f.Name = "VT65MeuSoldado"') and has(preview, 'player:FindFirstChildOfClass("PlayerGui")'),
		"PlayerGui"
	)
	assert(has(preview, "CommerceService.onEquip = PreviewService.pessoal"), "refaz ao equipar")
	assert(has(preview, "ProgressionService.onSkinChange = PreviewService.pessoal"), "refaz ao trocar skin")
	assert(has(preview, '{ "UltimaEscolha", "Faction", "Role" }'), "refaz ao trocar lado e papel")
	local chars = ler(S .. "Characters.luau")
	assert(select(2, string.gsub(chars, "local player = ownerOf%(model%)", "")) == 3, "rosto, papel e skin pelo dono")
	local commerce = ler(S .. "CommerceService.luau")
	assert(has(commerce, "task.spawn(CommerceService.onEquip, player)"), "gancho do Commerce_Equip")
	local sp = ler(C .. "SoldierPreview.luau")
	assert(
		has(sp, "-- D-206: no modo mundo (o palco do lobby) o modelo próprio fica de pé no ponto"),
		"setModel no mundo"
	)
end)

test("menu: a ação mais evidente é o JOGAR, e a navegação do §6 está toda lá", function()
	assert(has(menu, 'card.Name = "JOGAR"') and has(menu, "UiKit.principal(card)"), "JOGAR é a ação principal")
	assert(has(menu, "jogarBox.BackgroundColor3 = V.AMBAR"), "JOGAR em âmbar")
	for _, nome in
		{ '"ARSENAL"', '"MISSÕES"', '"PERFIL"', '"COMO JOGAR"', '"LOJA"', '"PASSE DE CAMPANHA"', '"CONFIGURAÇÕES"' }
	do
		assert(has(menu, nome), "entrada do menu faltando: " .. nome)
	end
	-- resumos à direita e o rodapé com dados reais (nada inventado)
	assert(has(menu, "CampanhaCliente.get()"), "passe e ordens do estado da campanha")
	assert(has(menu, 'Net.func("Daily_Get")'), "diária do servidor")
	assert(has(menu, 'player:GetAttribute("Credits")') and has(menu, "Progression.progress(xp)"), "saldo e posto")
	assert(has(menu, '"carregando o passe…"'), "estado de carregando, não uma conta vazia")
	-- o caminho do teste no Studio continua (CLAUDE.md)
	assert(
		has(menu, 'bloco("Conteudo"') and has(menu, 'palco.Name = "Palco"'),
		"VT65MenuPrincipal.Palco.Conteudo.JOGAR"
	)
end)

test("capas: as imagens do lobby são as da página do jogo (Pagina.miniatura_*)", function()
	local ids = net.jsonDecode(fs.readFile("assets/roblox_ids.json"))
	local pagina = {}
	for k, v in ids do
		if string.sub(k, 1, 7) == "Pagina." then
			pagina[tonumber(v) or v] = k -- o JSON guarda os IDs como texto
		end
	end
	local n = 0
	for nome, id in AssetIds.Capas do
		assert(pagina[id], "capa sem imagem da página: " .. nome)
		n += 1
	end
	assert(n >= 6, "capas: " .. n)
	-- cada entrada do menu com capa usa uma que existe
	for capa in string.gmatch(menu, '\n\t"([%l]+)",\n\t"[%l]+",\n\tfunction') do
		-- D-217: "armario" é a imagem própria da entrada (Images.menu_armario)
		assert(
			capa == "loja" or AssetIds.Capas[capa] or AssetIds.Images["menu_" .. capa],
			"entrada com capa que não existe: " .. capa
		)
	end
end)

test("transições: foco troca capa, descrição e enquadramento; movimento reduzido só esmaece", function()
	assert(has(menu, "trocarCapa(it.capa)") and has(menu, "LobbyPalco.enquadrar(it.quadro)"), "foco")
	assert(has(menu, "UiKit.tween(tras, FADE, { ImageTransparency = 0 })"), "fusão da capa")
	assert(has(menu, "local parado = Estilo.reduzMovimento()"), "entrada sem deslizar")
	assert(has(palco, "camDur = if Estilo.reduzMovimento() then 0 else MOVE_S"), "câmera corta")
	assert(has(palco, "camDe = if parado then QUADROS[quadroAtual] else CHEGADA"), "sem travelling de chegada")
	assert(has(palco, "e.Enabled = not parado"), "sem poeira")
	-- girar o soldado não aciona outro elemento: só fora da coluna e sem tela por cima
	assert(has(palco, "if not aberto or processed or not LobbyPalco.podeGirar() then"), "gesto separado")
	-- D-222: o lobby ficou sem soldado: não há o que girar, e o fundo é a imagem parada
	assert(has(menu, "LobbyPalco.podeGirar = function(): boolean\n\treturn false"), "podeGirar")
	assert(has(menu, "FundoLobby.novo(fundo, 0, -5)"), "fundo parado")
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
