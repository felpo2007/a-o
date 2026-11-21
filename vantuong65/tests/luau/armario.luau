--!strict
-- D-211 (lote 96): o ARMÁRIO no lobby, a arma principal guardada no perfil (a M16 dos EUA) e os nomes
-- sem vietnamita na tela.
-- Uso, a partir de vantuong65/:  lune run tests/luau/armario.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local M = "../../src/ServerScriptService/Modules/"
local Roles = require(S .. "Roles") :: any
local MapConfig = require(S .. "MapConfig") :: any
local Progression = require(S .. "Progression") :: any
local ProfileSchema = require(M .. "ProfileSchema") :: any

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
local SRV = "src/ServerScriptService/Modules/"

test("M16: escolha dos EUA (líder, fuzileiro, médico e suporte)", function()
	for _, rid in { "squad_leader", "rifleman", "medic", "support" } do
		assert(table.find(Roles.primaries("US", rid), "m16"), rid)
	end
	assert(Roles.primaryFor("US", "rifleman", "m16") == "m16")
	assert(Roles.primaryFor("US", "rifleman", "ak47") == "m14", "fora da lista: a padrão")
end)

test("a escolha vai e volta no atributo, em ordem fixa", function()
	local s = Roles.packPrefs({ ["US:support"] = "win12", ["US:rifleman"] = "m16" })
	assert(s == "US:rifleman=m16;US:support=win12", s)
	local m = Roles.unpackPrefs(s)
	assert(m["US:rifleman"] == "m16" and m["US:support"] == "win12")
	assert(next(Roles.unpackPrefs(nil)) == nil and next(Roles.unpackPrefs("")) == nil)
	assert(Roles.chavePref("VC", "rifleman") == "VC:rifleman")
end)

test("perfil: o campo armas nasce vazio e a migração só guarda texto curto", function()
	local p = ProfileSchema.default()
	assert(type(p.armas) == "table" and next(p.armas) == nil)
	local raw = ProfileSchema.default()
	raw.armas = { ["US:rifleman"] = "m16", [5] = "x", ["US:support"] = string.rep("a", 40) }
	local back = ProfileSchema.migrate(raw)
	assert(back.armas["US:rifleman"] == "m16")
	assert(back.armas[5] == nil and back.armas["US:support"] == nil)
	assert(next(ProfileSchema.migrate({ schema = 1 }).armas) == nil, "perfil antigo sem o campo")
end)

test("servidor: Arma_Escolher confere a lista do papel, grava, publica e troca o equipamento", function()
	local ts = ler(SRV .. "TeamService.luau")
	local a = assert(string.find(ts, 'Net.event("Arma_Escolher").OnServerEvent:Connect', 1, true))
	local corpo = string.sub(ts, a, a + 1400)
	assert(string.find(corpo, "table.find(Roles.primaries(faction, roleId), weapon)", 1, true))
	assert(string.find(corpo, "p.armas[Roles.chavePref(faction, roleId)] = weapon", 1, true))
	assert(
		string.find(corpo, "publicaArmas(player)", 1, true)
			and string.find(corpo, "applyLoadout(player, roleId, weapon)", 1, true)
	)
	assert(
		string.find(ts, "primary = primary or preferida(player, faction, roleId)", 1, true),
		"sem arma no pedido: a do perfil"
	)
	assert(string.find(ler("src/ReplicatedStorage/Shared/Net.luau"), '"Arma_Escolher"', 1, true))
end)

test("lobby e loja: a entrada ARMÁRIO abre a aba da arma de cada papel", function()
	local mp = ler(C .. "MenuPrincipal.client.luau")
	assert(string.find(mp, '"ARMARIO",\n\t"ARMÁRIO",', 1, true))
	assert(string.find(mp, 'Bus.fire("shop_open", "armario")', 1, true))
	local sc = ler(C .. "ShopController.client.luau")
	assert(string.find(sc, '{ id = "armario", name = "ARMÁRIO" }', 1, true))
	-- D-225: a aba é a ArmarioTela (categorias, grade de imagens e ficha)
	local at = ler(C .. "ArmarioTela.luau")
	assert(string.find(sc, "ArmarioTela.novo(armarioPage", 1, true))
	assert(string.find(at, 'Net.event("Arma_Escolher"):FireServer(f, rid, e.id)', 1, true))
	assert(string.find(at, "img = ArteCatalogo.arma(w)", 1, true), "a imagem da arma")
	local ds = ler(C .. "DeployScreen.luau")
	assert(string.find(ds, 'Net.event("Arma_Escolher"):FireServer(f, id, nextId)', 1, true), "o cartão também grava")
	assert(string.find(ds, 'Roles.unpackPrefs(player:GetAttribute("ArmasPreferidas"))', 1, true))
end)

test("nomes simples: o setor C é a Vila; esquadras, postos e itens do VC em português", function()
	assert(MapConfig.Sectors[3].name == "C Vila", MapConfig.Sectors[3].name)
	assert(MapConfig.Strongpoints[3].name == "Vila")
	-- letras só do vietnamita, uma a uma (o padrão do Lua compara bytes: uma classe [...] com letras
	-- acentuadas casaria o "é" do português)
	local VN = {
		"ư",
		"ơ",
		"đ",
		"Đ",
		"ạ",
		"ả",
		"ấ",
		"ầ",
		"ậ",
		"ắ",
		"ặ",
		"ế",
		"ề",
		"ệ",
		"ị",
		"ọ",
		"ộ",
		"ồ",
		"ớ",
		"ờ",
		"ụ",
		"ủ",
		"ứ",
		"ừ",
		"Tân",
	}
	local function semVn(s: string): boolean
		for _, l in VN do
			if string.find(s, l, 1, true) then
				return false
			end
		end
		return true
	end
	for _, u in { "command", "infantry" } do
		for _, n in Roles.units.VC[u].names do
			assert(semVn(n), n)
		end
	end
	for f, list in Progression.RANKS or {} do
		for _, r in list do
			assert(semVn(tostring(r.name)), string.format("%s %s", f, tostring(r.name)))
		end
	end
	-- as telas que mostravam Vạn Tường e Quảng Ngãi (o "VẠN TƯỜNG 1965" que sobra na tela de entrada só
	-- pré-carrega a fonte do idioma vietnamita e nunca aparece)
	local ls = ler("src/ReplicatedFirst/LoadingScreen.client.luau")
	assert(not string.find(ls, "· VẠN TƯỜNG", 1, true) and not string.find(ls, "de Vạn Tường", 1, true))
	assert(not string.find(ls, "An Cường (2):", 1, true))
	for _, arq in
		{
			C .. "MenuPrincipal.client.luau",
			C .. "DeployScreen.luau",
			"src/ReplicatedStorage/Shared/AfterAction.luau",
		}
	do
		local t = ler(arq) -- só o texto de tela (comentário pode citar o lugar)
		assert(not string.find(t, "VẠN TƯỜNG", 1, true) and not string.find(t, "Starlite · Vạn", 1, true), arq)
	end
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
