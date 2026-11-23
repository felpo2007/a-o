--!nocheck
-- D-253 (prompt V5, §4): nenhum sistema do jogo pode criar, usar ou simular vento.
local fs = require("@lune/fs")

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

local fontes: { [string]: string } = {}
local function varre(pasta: string)
	for _, nome in fs.readDir(pasta) do
		local c = pasta .. "/" .. nome
		if fs.isDir(c) then
			varre(c)
		elseif string.sub(nome, -5) == ".luau" and not string.find(c, "Data", 1, true) then
			fontes[c] = fs.readFile(c)
		end
	end
end
varre("src")

test("só o SemVento escreve no GlobalWind, e sempre zero", function()
	for c, t in fontes do
		for valor in string.gmatch(t, "GlobalWind%s*=%s*([^\r\n]+)") do
			assert(string.find(c, "SemVento", 1, true), c .. " escreve no vento")
			assert(string.find(valor, "Vector3.zero", 1, true), c .. ": " .. valor)
		end
	end
end)

test("nenhuma partícula é levada pelo vento", function()
	for c, t in fontes do
		assert(not string.find(t, "WindAffectsDrag = true", 1, true), c)
	end
end)

test("servidor e cliente aplicam o vento zero", function()
	local srv = fs.readFile("src/ServerScriptService/Modules/TerrainLook.luau")
	local cli = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/Ambiente.client.luau")
	assert(string.find(srv, "SemVento", 1, true), "servidor")
	assert(string.find(cli, "SemVento.aplicar()", 1, true), "cliente")
end)

test("sem poeira nem folhas no ar, sem balanço de camuflagem e sem som de vento", function()
	local amb = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/Ambiente.client.luau")
	assert(not string.find(amb, '"Poeira"', 1, true) and not string.find(amb, '"Folhas"', 1, true), "partículas")
	for c, t in fontes do
		assert(not string.find(t, "swayAngles", 1, true), c .. " balança a camuflagem")
		if not string.find(c, "AssetIds", 1, true) then
			assert(not string.find(t, "vento_cabine", 1, true), c .. " toca vento")
		end
	end
end)

test("a bandeira da comemoração fica parada", function()
	local t = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/CenaComemoracao.luau")
	assert(string.find(t, "local onda = math.sin(k * 0.62)", 1, true), "dobra fixa")
	assert(not string.find(t, "self.t - k", 1, true), "o pano não pode ondular com o tempo")
end)

test("a água não tem onda de vento", function()
	local t = fs.readFile("src/ServerScriptService/Modules/TerrainLook.luau")
	assert(string.find(t, '"WaterWaveSize", 0)', 1, true), "tamanho")
	assert(string.find(t, '"WaterWaveSpeed", 0)', 1, true), "velocidade")
end)

print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("falhou")
end
