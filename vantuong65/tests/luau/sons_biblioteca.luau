--!nocheck
-- D-252: os sons trocados pela biblioteca licenciada estão no AssetIds e têm ganho seguro.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds")
local SonsBiblioteca = require("../../src/ReplicatedStorage/Shared/SonsBiblioteca")

local ok, falhas = 0, 0
local function test(nome: string, f: () -> ())
	local passou, erro = pcall(f)
	if passou then
		ok += 1
	else
		falhas += 1
		print("FALHA: " .. nome .. ": " .. tostring(erro))
	end
end

test("cada som trocado está no AssetIds com o ID da biblioteca", function()
	for chave, id in SonsBiblioteca.IDS do
		assert(AssetIds.Sounds[chave] == id, chave)
	end
end)

test("o ID sintetizado anterior fica guardado e o registro aponta para a gravação", function()
	local ids = serde.decode("json", fs.readFile("assets/roblox_ids.json"))
	for chave, id in SonsBiblioteca.IDS do
		assert(tonumber(ids["Sounds." .. chave]) == id, "registro de " .. chave)
		local velho = tonumber(ids["Sounds." .. chave .. "_sintese"])
		assert(type(velho) == "number" and velho ~= id, "sintetizado de " .. chave)
	end
end)

test("o ganho só vale para som trocado e não passa do limite do Roblox", function()
	for chave, g in SonsBiblioteca.GANHO do
		assert(SonsBiblioteca.IDS[chave] ~= nil, chave)
		assert(g > 0 and g <= 10, chave)
	end
	assert(SonsBiblioteca.ganho("nao_existe") == 1)
end)

test("o AudioController aplica o ganho nos sons e nas ambiências", function()
	local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/AudioController.client.luau")
	assert(string.find(src, "s.Volume = volume * SonsBiblioteca.ganho(key)", 1, true), "sons")
	assert(string.find(src, "0.2 * SonsBiblioteca.ganho(AMB[z])", 1, true), "ambiências")
end)

print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("falhou")
end
