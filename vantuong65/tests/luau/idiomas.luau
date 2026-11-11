--!strict
-- Testes dos idiomas (D-84). Uso: lune run tests/luau/idiomas.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local Lang = require("../../src/ReplicatedStorage/Shared/Lang")

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

local t = Lang.compile({
	["Fuzileiro"] = "Rifleman",
	["Alistar-se"] = "Enlist",
	["Escolha o seu lado"] = "Choose your side",
	["Equipamento: %.1f de %.1f kg (vale no próximo spawn)"] = "Gear: %.1f of %.1f kg (applies on next spawn)",
	["%s: %s"] = "%s - %s", -- só especificador: ignorado (casaria com tudo)
	["Detalhe (arroz, poeira, folhas, fumaça)"] = "Detail (rice, dust, leaves, smoke)",
	["alto"] = "high",
	["Desembarque em %s às %s"] = "Landing at %s at %s",
	["Atirar"] = "Fire",
	["Chegam reforços em %d s"] = "Reinforcements in %d s",
	["100%% pronto"] = "100%% ready",
	["Atirar: {a}. Escolha a cobertura."] = "Fire: {a}. Pick your cover.",
})

test("marcador {a} do tutorial vale como texto variável", function()
	assert(Lang.translate(t, "Atirar: LMB. Escolha a cobertura.") == "Fire: LMB. Pick your cover.")
end)

test("frase exata, caixa alta e espaços", function()
	assert(Lang.translate(t, "Fuzileiro") == "Rifleman")
	assert(Lang.translate(t, "FUZILEIRO") == "RIFLEMAN", "caixa alta")
	assert(Lang.translate(t, "ALISTAR-SE") == "ENLIST")
	assert(Lang.translate(t, "  Escolha o seu lado ") == "  Choose your side ", "espaços nas pontas")
	assert(Lang.translate(t, "texto que não existe") == nil)
	assert(Lang.translate(t, "12:34") == nil, "sem letras")
end)

test("modelos com números e textos", function()
	assert(
		Lang.translate(t, "Equipamento: 3.2 de 10.5 kg (vale no próximo spawn)")
			== "Gear: 3.2 of 10.5 kg (applies on next spawn)"
	)
	assert(Lang.translate(t, "Chegam reforços em 12 s") == "Reinforcements in 12 s")
	assert(Lang.translate(t, "Desembarque em Vạn Tường às 06:30") == "Landing at Vạn Tường at 06:30")
	assert(Lang.translate(t, "100% pronto") == "100% ready", "%% literal")
	assert(Lang.translate(t, "qualquer: coisa") == nil, "modelo só de especificador não entra")
end)

test("rótulo: valor, linhas e RichText", function()
	assert(
		Lang.translate(t, "Detalhe (arroz, poeira, folhas, fumaça): alto")
			== "Detail (rice, dust, leaves, smoke): high"
	)
	assert(Lang.translate(t, "Fuzileiro\nAlistar-se") == "Rifleman\nEnlist", "linha a linha")
	assert(Lang.translate(t, "<b>Atirar</b>") == "<b>Fire</b>", "pedaço entre marcas")
	local viet = 'Desembarque em <font family="x">Vạn Tường</font> às 06:30'
	assert(
		Lang.translate(t, viet) == 'Landing at <font family="x">Vạn Tường</font> at 06:30',
		"frase inteira com o nome marcado de volta: " .. tostring(Lang.translate(t, viet))
	)
end)

test("idioma da conta e caixa alta vietnamita", function()
	assert(Lang.fromLocale("en-us") == "en" and Lang.fromLocale("es-mx") == "es")
	assert(Lang.fromLocale("pt-br") == "pt" and Lang.fromLocale("vi-vn") == "vi")
	assert(Lang.fromLocale("de-de") == "en" and Lang.fromLocale(nil) == "en", "sem dicionário: inglês")
	assert(Lang.upper("An Cường") == "AN CƯỜNG", Lang.upper("An Cường"))
	assert(Lang.upper("ação") == "AÇÃO" and Lang.upper("đồi") == "ĐỒI")
end)

-- dicionários de verdade (Shared/LangData): todo modelo traduzido mantém os especificadores
test("dicionários: especificadores iguais ao português", function()
	local dir = "src/ReplicatedStorage/Shared/LangData"
	if not fs.isDir(dir) then
		return
	end
	local bad = {}
	for _, name in fs.readDir(dir) do
		if string.sub(name, -5) == ".json" then
			local dict = net.jsonDecode(fs.readFile(dir .. "/" .. name)) :: { [string]: string }
			for pt, tr in dict do
				local function specs(s: string): { string }
					local out = {}
					local clean = string.gsub(s, "%%%%", "")
					for sp in string.gmatch(clean, "%%[%-%+ #0]*%d*%.?%d*[dsfiqxg]") do
						table.insert(out, string.sub(sp, -1))
					end
					for _ in string.gmatch(clean, "{%a+}") do
						table.insert(out, "{}")
					end
					return out
				end
				local a, b = specs(pt), specs(tr)
				if table.concat(a) ~= table.concat(b) then
					table.insert(bad, name .. ": " .. pt)
				end
			end
			Lang.compile(dict)
		end
	end
	assert(#bad == 0, #bad .. " com especificador diferente, ex.: " .. tostring(bad[1]))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
