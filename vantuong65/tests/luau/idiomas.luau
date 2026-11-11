--!strict
-- Testes dos idiomas (D-84). Uso: lune run tests/luau/idiomas.luau
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

local S = "../../src/ReplicatedStorage/Shared/"
local Lang = require(S .. "Lang")
local AfterAction = require(S .. "AfterAction") :: any
local Casualty = require(S .. "Casualty") :: any

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
					for sp in string.gmatch(clean, "%%[%-%+#0]*%d*%.?%d*[dsfiqxg]") do
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

-- ===== cobertura (D-84): todo texto de tela tem de estar nos três dicionários =====
local function readDict(code: string): { [string]: string }
	return net.jsonDecode(fs.readFile("src/ReplicatedStorage/Shared/LangData/" .. code .. ".json")) :: any
end

-- Mínimo de textos de tela que o extrator tem de achar (se cair muito, o extrator quebrou)
local MIN_TELAS = 1300
-- Frases que nunca podem faltar: mensagens montadas pelo servidor e peças delas
local OBRIGATORIAS = {
	"Abatido por %s, ~%d m a %s",
	"Reunião — %s",
	"Reunião do squad %s",
	"Onde caiu (%s)",
	"Fim de partida: %s",
	"Pá: %s",
	"faltam %s",
	"norte",
	"nordeste",
	"fuzil",
	"metralhadora",
	"morteiro",
	"%s  %s perde o controle de S%d (%s).",
	"Vitória do USMC. Duração: %d min.",
}

test("cobertura: todo texto de tela (tools/i18n/telas.json) está em en, es e vi", function()
	if not fs.isFile("tools/i18n/telas.json") then
		return
	end
	local telas = net.jsonDecode(fs.readFile("tools/i18n/telas.json")) :: { string }
	assert(#telas >= MIN_TELAS, "telas.json com só " .. #telas .. " textos: rode tools/i18n/extrai.py")
	for _, code in { "en", "es", "vi" } do
		local dict = readDict(code)
		local missing = {}
		for _, k in telas do
			if dict[k] == nil then
				table.insert(missing, k)
			end
		end
		local pct = 100 * (#telas - #missing) / #telas
		assert(
			#missing == 0,
			string.format(
				"%s: %.1f%% (%d faltam), ex.: %s. Rode: uv run python tools/i18n/extrai.py --faltam %s",
				code,
				pct,
				#missing,
				tostring(missing[1]),
				code
			)
		)
		for _, k in OBRIGATORIAS do
			assert(dict[k] ~= nil, code .. ": falta a frase obrigatória " .. k)
		end
	end
end)

test("dicionários: tradução vazia ou só com espaço não vale", function()
	for _, code in { "en", "es", "vi" } do
		for pt, tr in readDict(code) do
			assert(string.find(tr, "%S") ~= nil, code .. ": tradução vazia para " .. pt)
		end
	end
end)

local DICT = {} :: { [string]: Lang.Table }
for _, code in { "en", "es", "vi" } do
	DICT[code] = Lang.compile(readDict(code))
end

test("texto montado inteiro: causa da baixa nos três idiomas", function()
	local c = { kind = "shot", weaponKind = "rifle", dx = 303, dz = -303 } -- ~120 m a nordeste
	local pt = Casualty.text(c, false)
	assert(pt == "Abatido por fuzil, ~120 m a nordeste", pt)
	assert(
		Lang.translate(DICT.en, pt) == "Killed by rifle, ~120 m to the northeast",
		tostring(Lang.translate(DICT.en, pt))
	)
	assert(Lang.translate(DICT.es, pt) == "Abatido por fusil, ~120 m al nordeste")
	assert(Lang.translate(DICT.vi, pt) == "Bị hạ bởi súng trường, ~120 m hướng đông bắc")
	local boom = Casualty.text({ kind = "explosion", explosive = "mortar_81", dx = -30, dz = 0 }, true)
	assert(Lang.translate(DICT.en, boom) == "Wounded by shrapnel from mortar, ~10 m to the west", boom)
	local close = Casualty.text({ kind = "explosion", explosive = "grenade_us", dx = 3, dz = 0 }, false)
	assert(
		Lang.translate(DICT.es, close) == "Metralla de granada, a pocos metros",
		tostring(Lang.translate(DICT.es, close))
	)
	-- a ficha da tela de baixa: "CAUSA      " .. texto (rótulo em coluna)
	local row = "CAUSA      " .. pt
	assert(Lang.translate(DICT.en, row) == "CAUSE      Killed by rifle, ~120 m to the northeast")
end)

test("texto montado inteiro: relatório pós-ação sai traduzido", function()
	local r = AfterAction.new("Offensive", 6.5)
	AfterAction.event(r, 95, "neutralized", 1, "VC", "Colina 43")
	AfterAction.event(r, 180, "captured", 1, "US", "Colina 43")
	AfterAction.event(r, 300, "advanced", 2, "US", nil)
	AfterAction.casualty(r, "VC", 1)
	AfterAction.finish(r, "US", 3600, { "US", "VC" })
	local lines = AfterAction.lines(r)
	local want = {
		en = {
			"   180631H AUG 65  VC loses control of S1 (Hill 43).",
			"   180633H AUG 65  USMC captures S1 (Hill 43).",
			"   180635H AUG 65  the front moves to S2.",
			"   USMC victory. Duration: 60 min.",
			"   Sectors at the end: S1 USMC · S2 VC",
		},
		es = {
			"   180631H AUG 65  VC pierde el control de S1 (Colina 43).",
			"   180633H AUG 65  USMC toma S1 (Colina 43).",
			"   180635H AUG 65  el frente pasa a S2.",
			"   Victoria del USMC. Duración: 60 min.",
		},
		vi = {
			"   180631H AUG 65  VC mất quyền kiểm soát S1 (Đồi 43).",
			"   180633H AUG 65  USMC chiếm S1 (Đồi 43).",
			"   Giao tranh ác liệt nhất: S1 (1 tử trận).",
			"   USMC chiến thắng. Thời lượng: 60 phút.",
		},
	}
	local function has(set: { string }, s: string): boolean
		return table.find(set, s) ~= nil
	end
	for code, expected in want do
		local out = {}
		for _, l in lines do
			table.insert(out, Lang.translate(DICT[code], l) or l)
		end
		for _, e in expected do
			assert(has(out, e), code .. ": falta a linha " .. e .. "\n" .. table.concat(out, "\n"))
		end
	end
end)

test("prefixo, sufixo, coluna, plural engolido e fonte larga", function()
	local en, vi = DICT.en, DICT.vi
	assert(Lang.translate(en, "Desarmar Estacas punji") == "Disarm Punji stakes", "prefixo conhecido")
	assert(Lang.translate(en, "Pegar M14") == "Pick up M14")
	assert(Lang.translate(en, "Alfa (caído)") == "Alpha (downed)", tostring(Lang.translate(en, "Alfa (caído)")))
	assert(
		Lang.translate(vi, "Sequência: 3 dias · Total: 5 selos") == "Chuỗi: 3 ngày · Tổng: 5 tem",
		tostring(Lang.translate(vi, "Sequência: 3 dias · Total: 5 selos"))
	)
	assert(Lang.translate(en, "Sequência: 1 dia · Total: 1 selo") == "Streak: 1 day · Total: 1 seal")
	-- modelo com espaços nas pontas na chave também casa
	local t = Lang.compile({ ["   Setores: %d de %s"] = "   Sectors: %d of %s" })
	assert(
		Lang.translate(t, "   Setores: 3 de 5") == "   Sectors: 3 of 5",
		tostring(Lang.translate(t, "   Setores: 3 de 5"))
	)
	-- modelo só com letra acentuada nas peças fixas vale (antes ficava de fora)
	local acc = Lang.compile({ ["Mão: %s"] = "Hand: %s" })
	assert(Lang.translate(acc, "Mão: sem munição") == "Hand: sem munição")
	assert(Lang.needsWide("Tập hợp") and Lang.needsWide("Đồi 43") and Lang.needsWide("ƯU"))
	assert(not Lang.needsWide("Reunión de la escuadra") and not Lang.needsWide("Hill 43 — ação"))
end)

-- cada modelo dos dicionários tem de casar com o próprio exemplo (um modelo mais geral não pode
-- engolir outro): troca %d/%f por números e %s/{a} por "Zq<n>" e confere a tradução
test("modelos: cada um casa com o seu exemplo (nenhum é engolido por outro)", function()
	local function sample(x: string): string
		local n = 0
		local r = string.gsub(x, "%%[%-%+#0]*%d*%.?%d*([dsfiqxg])", function(k: string): string
			n += 1
			if k == "s" then
				return "Zq" .. n
			end
			return tostring(10 + n)
		end)
		r = string.gsub(r, "{%a+}", "Zq9")
		return (string.gsub(r, "%%%%", "%%"))
	end
	local bad = {}
	local total = 0
	for _, code in { "en", "es", "vi" } do
		for pt, trl in readDict(code) do
			local has = string.find(pt, "%%[%-%+#0]*%d*%.?%d*[dsfiqxg]") or string.find(pt, "{%a+}")
			-- modelo com menos de 3 letras fixas ("%d de %d") nunca vira padrão: genérico demais
			local fixed = string.gsub(string.gsub(pt, "%%[%-%+#0]*%d*%.?%d*[dsfiqxg]", ""), "[^%a]", "")
			if has and #fixed >= 3 and not string.find(trl, "%%%.0s") then
				total += 1
				-- colunas de relatório ("ARMAS  %s") refazem o recuo: compara sem a largura dos espaços
				local got = Lang.translate(DICT[code], sample(pt))
				local gotFlat = if got then string.gsub(got, " +", " ") else nil
				if gotFlat ~= string.gsub(sample(trl), " +", " ") then
					table.insert(bad, string.format("%s: %s -> %s", code, pt, tostring(got)))
				end
			end
		end
	end
	assert(total > 300, "poucos modelos conferidos: " .. total)
	assert(#bad == 0, #bad .. " modelos engolidos, ex.: " .. tostring(bad[1]))
end)

print(string.format("%d ok, %d falhas", passed, failed))
if failed > 0 then
	process.exit(1)
end
