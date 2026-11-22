--!strict
-- D-239: nenhum item da loja fica sem imagem (Armário, camuflagem e vantagens).
local fs = require("@lune/fs")

local AssetIds = require("../../src/ReplicatedStorage/Shared/AssetIds") :: any
local Commerce = require("../../src/ReplicatedStorage/Shared/Commerce") :: any

local ok, fail = 0, 0
local function test(name: string, fn: () -> ())
	local good, err = pcall(fn)
	if good then
		ok += 1
	else
		fail += 1
		print("FALHOU: " .. name .. "\n  " .. tostring(err))
	end
end

local fonte = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/ArteCatalogo.luau")

local function tabela(nome: string): { [string]: string }
	local corpo = string.match(fonte, "local " .. nome .. " = (%b{})")
	assert(corpo, "sem a tabela " .. nome)
	local out: { [string]: string } = {}
	for k, v in string.gmatch(corpo :: string, '([%w_]+) = "([%w_]+)"') do
		out[k] = v
	end
	return out
end

local function temImagem(chave: string): boolean
	local id = AssetIds.Catalogo[chave]
	return type(id) == "number" and id ~= 0
end

test("todo visual do Armário, dos dois lados, tem imagem publicada", function()
	local iguais = tabela("VISUAL_IGUAL")
	local n, lados = 0, {} :: { [string]: boolean }
	for _, c in Commerce.Cosmetics do
		n += 1
		lados[c.faction] = true
		local chave = "vis_" .. (iguais[c.id] or c.id)
		assert(temImagem(chave), "sem imagem: " .. c.id)
	end
	assert(n >= 20 and lados.US and lados.VC, "catálogo incompleto")
end)

test("as três camuflagens têm imagem", function()
	for _, id in { "camo_rice", "camo_jungle", "camo_bamboo" } do
		assert(temImagem("vis_" .. id), "sem imagem: " .. id)
	end
end)

test("cada vantagem tem a própria imagem", function()
	local oferta = tabela("OFERTA")
	local vistas: { [string]: string } = {}
	local n = 0
	for _, p in Commerce.CampaignPasses do
		if p.kind == "perk" or p.kind == "perk_bundle" then
			n += 1
			local img = oferta[p.key]
			assert(img and temImagem(img), "sem imagem: " .. p.key)
			assert(not vistas[img], p.key .. " repete a imagem de " .. tostring(vistas[img]))
			vistas[img] = p.key
		end
	end
	assert(n == 8, "esperava 8 vantagens, veio " .. n)
end)

test("toda imagem apontada pela loja existe no catálogo", function()
	for chave, img in tabela("OFERTA") do
		assert(temImagem(img), chave .. " -> " .. img)
	end
end)

print(string.format("visuais: %d ok, %d falhas", ok, fail))
if fail > 0 then
	error("falhas")
end
