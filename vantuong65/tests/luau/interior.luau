--!nocheck
-- D-241: o lampião dos interiores (conta pura) e a luz nova do mapa.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local luau = require("@lune/luau")
local Lampiao = luau.load(fs.readFile("src/ReplicatedStorage/Shared/LampiaoInterior.luau"), { debugName = "Lampiao" })()

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

test("o globo passa da cabeça e não encosta no teto em todas as casas medidas", function()
	-- pés-direitos medidos no Studio nas 10 casas da vila (D-241)
	for _, teto in { 15.9, 17.3, 17.9, 15.8, 15.0, 17.3, 17.3, 13.8, 20.4, 13.9 } do
		local y = Lampiao.alturaGlobo(teto)
		assert(y, "sem altura para " .. teto)
		assert(y >= Lampiao.CABECA, "bate na cabeça: " .. y)
		assert(y <= teto - Lampiao.FOLGA_TETO + 1e-6, "encosta no teto: " .. y)
	end
end)

test("sem pé-direito não há lampião", function()
	assert(Lampiao.alturaGlobo(8) == nil)
end)

test("os pontos começam no centro e não se repetem", function()
	local c = Lampiao.candidatos(4, 2)
	assert(c[1][1] == 0 and c[1][2] == 0)
	assert(#c == 17, "1 + 8 por anel")
	local vistos = {}
	for _, p in c do
		local k = p[1] .. ":" .. p[2]
		assert(not vistos[k], "repetido " .. k)
		vistos[k] = true
	end
end)

test("a chama respira sem apagar nem estourar", function()
	local menor, maior = math.huge, -math.huge
	for i = 0, 4000 do
		local v = Lampiao.chama(i * 0.013, 3.7)
		menor, maior = math.min(menor, v), math.max(maior, v)
	end
	assert(menor >= 0.86 - 1e-6 and maior <= 1.06 + 1e-6, string.format("%.3f a %.3f", menor, maior))
	assert(maior - menor > 0.1, "chama parada")
end)

test("a chama fica mais laranja e mais forte à noite; hora desconhecida usa a do dia", function()
	local corDia, brilhoDia = Lampiao.daHora("manha")
	local corNoite, brilhoNoite = Lampiao.daHora("noite")
	assert(corDia == Lampiao.COR and brilhoDia == Lampiao.BRILHO)
	assert(brilhoNoite > brilhoDia and corNoite[2] < corDia[2] and corNoite[3] < corDia[3])
	local c = Lampiao.daHora(nil)
	assert(c == Lampiao.COR)
end)

test("a peça do lampião não colide nem recebe tiro", function()
	local src = fs.readFile("src/ServerScriptService/Modules/InteriorLuz.luau")
	for _, s in { "p.CanCollide = false", "p.CanQuery = false", "p.CanTouch = false", "p.CastShadow = false" } do
		assert(string.find(src, s, 1, true), s)
	end
	assert(string.find(src, "luz.Shadows = false", 1, true), "luz sem sombra")
	local loader = fs.readFile("src/ServerScriptService/Modules/AssetLoader.luau")
	assert(string.find(loader, "InteriorLuz).instalar(map)", 1, true), "o carregador instala")
end)

test("a luz do mapa continua em ShadowMap e o chão nunca fica claro demais", function()
	local p = serde.decode("json", fs.readFile("default.project.json"))
	local L = p.tree.Lighting
	assert(L["$properties"].Technology == "ShadowMap", "Future pesa na GPU de 2 GB (decisão antiga)")
	assert(L.Bloom["$properties"].Threshold >= 1.1, "brilho só no que é muito claro")
	local look = fs.readFile("src/ServerScriptService/Modules/TerrainLook.luau")
	local r, g, b = string.match(look, "Ground = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
	assert(r and tonumber(r) < 175 and tonumber(g) < 130 and tonumber(b) < 100, "terra sem foto não pode virar bege")
end)

print(string.format("%d ok, %d falhas", ok, falhas))
if falhas > 0 then
	error("interior: falhou")
end
