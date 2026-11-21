--!strict
-- D-210 (prompt de interface §13): HUD de infantaria. Lógica pura do Shared/HudInfantaria e
-- conferências de fonte (servidor, HUD novo, cartão da arma, marcadores e coluna de comandos).
-- Uso, a partir de vantuong65/:  lune run tests/luau/hud_infantaria.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local H = require("../../src/ReplicatedStorage/Shared/HudInfantaria") :: any

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
local function near(a: number, b: number, tol: number, msg: string?)
	assert(math.abs(a - b) <= tol, string.format("%s: %.3f vs %.3f", msg or "", a, b))
end

local C = "src/StarterPlayer/StarterPlayerScripts/Controllers/"
local M = "src/ServerScriptService/Modules/"

test("vida: o valor real, arredondado; nível pela fração; vivo nunca mostra 0", function()
	local f, t, n = H.vida(112, 112)
	assert(f == 1 and t == "112" and n == "bem")
	f, t, n = H.vida(56, 112)
	near(f, 0.5, 1e-9)
	assert(t == "56" and n == "ferido")
	f, t, n = H.vida(20, 112)
	assert(t == "20" and n == "grave")
	f, t = H.vida(0.3, 100)
	assert(t == "1", "0,3 de vida ainda é vivo")
	f, t = H.vida(0, 100)
	assert(f == 0 and t == "0")
	f, t = H.vida(150, 100)
	assert(f == 1 and t == "100", "nunca passa do máximo")
	f = H.vida(nil, nil)
	assert(f == 0)
end)

test("estados do corpo: hemorragia vale mais que sangrando; perna e braço feridos", function()
	assert(#H.estados(nil) == 0)
	assert(#H.estados({ bleed = 0 }) == 0)
	local e = H.estados({ bleed = 0.5, arterial = true, leg = true, arm = true })
	assert(#e == 3 and e[1].texto == "HEMORRAGIA" and e[1].grave, e[1].texto)
	assert(e[2].texto == "PERNA FERIDA" and e[3].texto == "BRAÇO FERIDO")
	local s = H.estados({ bleed = 0.2 })
	assert(#s == 1 and s[1].texto == "SANGRANDO" and not s[1].grave)
end)

test("direção do dano: à frente 0, direita +90, esquerda −90, atrás ±180 (câmera para −Z)", function()
	near(H.anguloDano(0, -1, 0, -10), 0, 1e-6, "frente")
	near(H.anguloDano(0, -1, 10, 0), 90, 1e-6, "direita")
	near(H.anguloDano(0, -1, -10, 0), -90, 1e-6, "esquerda")
	near(math.abs(H.anguloDano(0, -1, 0, 10)), 180, 1e-6, "atrás")
	-- câmera para +X: o tiro de +Z vem da direita
	near(H.anguloDano(1, 0, 0, 10), 90, 1e-6, "girada")
	assert(H.anguloDano(0, -1, 0, 0) == 0, "em cima: sem direção")
end)

test("abates: no máximo 4, o mais novo em cima; o próprio acende", function()
	local lista = {}
	for i = 1, 6 do
		H.empilha(lista, i, H.FEED_MAX)
	end
	assert(#lista == 4 and lista[1] == 6 and lista[4] == 3)
	local arma = function(id: string?, lado: string?): string
		return string.format("%s/%s", tostring(id), tostring(lado))
	end
	local a = H.abate({ k = "Ana", ku = 7, kf = "US", v = "Bot", vu = 0, vf = "VC", w = "m14" }, 7, arma)
	assert(a and a.meu and a.arma == "m14/US" and a.ladoCaiu == "VC")
	local b = H.abate({ k = "X", ku = 1, kf = "VC", v = "Ana", vu = 7, vf = "US", w = "type56" }, 7, arma)
	assert(b and b.meu, "a sua queda também acende")
	local c = H.abate({ k = "X", ku = 1, kf = "VC", v = "Y", vu = 2, vf = "US" }, 7, arma)
	assert(c and not c.meu)
	assert(H.abate({ v = "sem quem" }, 7, arma) == nil)
end)

test("esquadrão: só o próprio squad, sem você, o líder primeiro, papel com chave número ou texto", function()
	local st = {
		squads = {
			{ id = "US:Bravo", members = { 9 }, leader = 9, roles = {} },
			{
				id = "US:Alfa",
				name = "Alfa",
				members = { 1, 2, 3, 4 },
				leader = 3,
				roles = { [2] = "medic", ["3"] = "squad_leader" },
			},
		},
	}
	local info = function(id: number): (string?, string)
		if id == 4 then
			return nil, "fora" -- saiu do servidor
		end
		return string.format("P%d", id), if id == 2 then "caido" else "campo"
	end
	local l = H.esquadrao(st, "US:Alfa", 1, info)
	assert(#l == 2, "sem você e sem quem saiu: " .. #l)
	assert(l[1].id == 3 and l[1].lider and l[1].papel == "squad_leader", "o líder primeiro")
	assert(l[2].id == 2 and l[2].estado == "caido" and l[2].papel == "medic")
	assert(#H.esquadrao(st, nil, 1, info) == 0, "sem squad")
	assert(#H.esquadrao(nil, "US:Alfa", 1, info) == 0)
end)

test("objetivo: capturar, defender e contestar; perto da mira", function()
	assert(H.verbo("attack", false) == "capturar")
	assert(H.verbo("defend", false) == "defender")
	assert(H.verbo("attack", true) == "contestar" and H.verbo("defend", true) == "contestar")
	assert(H.pertoDoCentro(960, 540, 1920, 1080, 0.09))
	assert(H.pertoDoCentro(960 + 90, 540, 1920, 1080, 0.09), "dentro do raio de 97 px")
	assert(not H.pertoDoCentro(960 + 120, 540, 1920, 1080, 0.09))
end)

-- ===== ligações =====
test("servidor: o abate creditado vai a todos no Combat_Feed (sem posição)", function()
	local ps = ler(M .. "ProgressionService.luau")
	local a = assert(string.find(ps, 'Net.event("Combat_Kill"):FireClient(killer', 1, true))
	local b = assert(string.find(ps, 'Net.event("Combat_Feed"):FireAllClients({', a, true))
	local fim = assert(string.find(ps, "})", b, true))
	local corpo = string.sub(ps, b, fim)
	for _, k in { "k = killer.DisplayName", "kf = factionOf(killer)", "vf = e.faction", "w = wid" } do
		assert(string.find(corpo, k, 1, true), k)
	end
	assert(not string.find(corpo, "Position", 1, true), "nunca a posição")
	assert(string.find(ler("src/ReplicatedStorage/Shared/Net.luau"), '"Combat_Feed"', 1, true))
end)

test("HUD novo: vida do Humanoid, estados do Medical_State, dano do Combat_Hit, XP do Progresso", function()
	local hi = ler(C .. "HudInfantaria.client.luau")
	for _, t in
		{
			"h.HealthChanged:Connect",
			'Net.event("Medical_State").OnClientEvent',
			'Net.event("Combat_Hit").OnClientEvent',
			'Net.event("Combat_Feed").OnClientEvent',
			'Net.event("Squad_State").OnClientEvent',
			'Bus.on("hud_ganho"',
			'UiKit.screen("VT65Esquadrao"',
			'Bus.fire("esquadrao_mudou")',
		}
	do
		assert(string.find(hi, t, 1, true), t)
	end
	local pr = ler(C .. "Progresso.client.luau")
	assert(string.find(pr, 'Bus.fire(\n\t\t\t"hud_ganho"', 1, true), "em campo o ganho vai para o HUD")
	assert(string.find(pr, "Toast.reward(", 1, true), "no lobby, o aviso de sempre")
	local pc = ler(C .. "PainelComandos.client.luau")
	assert(string.find(pc, 'Bus.on("esquadrao_mudou", layout)', 1, true))
	assert(string.find(pc, "local top = reservaDoAlto()", 1, true), "a coluna começa embaixo do esquadrão")
end)

test("cartão da arma: a imagem do modelo (RodaArte) e o equipamento com a quantidade", function()
	local hc = ler(C .. "HudCampo.client.luau")
	assert(string.find(hc, "local art = RodaArte.frame(card)", 1, true))
	assert(string.find(hc, "RodaArte.show(A.art, artOf(W.id))", 1, true))
	for _, k in { '"frag", "smoke", "bandage"', 'GetAttribute("Frags")', 'GetAttribute("Smokes")', "s.bandages" } do
		assert(string.find(hc, k, 1, true), k)
	end
end)

test("marcadores e faixa: o mesmo verbo do objetivo; nomes somem perto da mira", function()
	local mk = ler(C .. "Marcadores.luau")
	assert(string.find(mk, "HudInfantaria.verbo(role,", 1, true))
	assert(string.find(mk, "and not naMira", 1, true))
	local fh = ler(C .. "FrontHud.client.luau")
	assert(string.find(fh, "HudInfantaria.verbo(role,", 1, true) and string.find(fh, "CONTESTAR", 1, true))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
