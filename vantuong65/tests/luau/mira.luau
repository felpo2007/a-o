--!nocheck
-- D-242: a mira da espingarda e da M14, a mão que desce ao mirar, o cartucho na recarga e o aviso falso
-- de arquivos na tela de entrada.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ok, falhas = 0, 0
local function test(nome, fn)
	local sucesso, erro = pcall(fn)
	if sucesso then
		ok += 1
	else
		falhas += 1
		print("  FALHA " .. nome .. ": " .. tostring(erro))
	end
end

local Weapons = fs.readFile("src/ReplicatedStorage/Shared/Weapons.luau")
local Visuais = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/WeaponVisuals.client.luau")
local Postura = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/PostureController.client.luau")
local Entrada = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")

local function campoDe(id, campo)
	local i = string.find(Weapons, 'id = "' .. id .. '"', 1, true)
	assert(i, "sem a arma " .. id)
	local fim = string.find(Weapons, "\n\t\tsrc = {", i, true)
	return tonumber(string.match(string.sub(Weapons, i, fim), campo .. " = ([%d%.]+)"))
end

test("o olho da espingarda fica na coronha, atrás do punho, e acima da culatra", function()
	local eye, sobe = campoDe("win12", "adsEyeM"), campoDe("win12", "adsSobeM")
	assert(eye and eye >= 0.25, "o olho caía depois da mão direita")
	assert(sobe and sobe > 0 and sobe < 0.06, "o olho precisa ver o cano até a massa")
end)

test("a M14 fica à mesma distância da alça que a M16", function()
	assert(campoDe("m14", "adsEyeM") == campoDe("m16", "adsEyeM"))
end)

test("mirando, a mão do punho desce nos fuzis, mas não na pistola", function()
	local bloco = string.match(Visuais, "ADS_MAO_BAIXA: { %[string%]: number } = (%b{})")
	assert(bloco, "sem a tabela")
	local t = luau.load("return " .. bloco)()
	assert(t.rifle > 0 and t.mg > 0 and t.shotgun > 0)
	assert(t.pistol == nil, "na pistola as duas mãos ficam à vista")
	assert(string.find(Visuais, "viewSight + olhoSobe", 1, true), "o olho sobe só na conta da mira")
end)

test("a recarga da espingarda mostra um cartucho, não um carregador de fuzil", function()
	assert(string.find(Postura, "cartucho = Vector3.new", 1, true))
	assert(string.find(Postura, 'if tipo == "tubo" then "cartucho"', 1, true))
	assert(string.find(Postura, "carregadorNaMao(char, kind, comMag and not far, b.recargaTipo)", 1, true))
end)

test("entrada de id vazio não conta como arquivo que não baixou", function()
	assert(string.find(Entrada, 'status == Enum.AssetFetchStatus.Failure and _id ~= ""', 1, true))
end)

print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("mira: falhou")
end
