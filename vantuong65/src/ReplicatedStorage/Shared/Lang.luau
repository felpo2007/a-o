--!strict
-- Idiomas (D-84, pedido do dono: "faça o jogo no mínimo em 3 línguas: inglês, português, espanhol
-- e outras"). Puro, testado no Lune (tests/luau/idiomas.luau).
--
-- O jogo é escrito em português. Cada idioma é um dicionário português -> tradução
-- (Shared/LangData/<idioma>.json, gerado por tools/i18n). A tradução acontece no texto que vai para
-- a tela (Controllers/Traducao.client), sem mexer em cada tela:
--   1. frase exata;
--   2. a mesma em caixa alta (UiKit.upper(nome) na tela, "Fuzileiro" no código);
--   3. sem os espaços das pontas;
--   4. modelo com números/textos: a chave pode ter %d, %s, %.1f... ("Equipamento: %.1f de %.1f kg");
--      o que entra no %s também é traduzido se estiver no dicionário;
--   5. "Rótulo: valor" com o rótulo no dicionário;
--   6. linha a linha (texto com quebras) e pedaço a pedaço entre as marcas do RichText;
--   7. "Rótulo   valor" (colunas de relatório, 2 ou mais espaços) com o rótulo no dicionário;
--   8. prefixo ou sufixo conhecido ("Desarmar " .. nome, nome .. " (caído)"): a chave termina (ou
--      começa) em espaço no dicionário e o resto é traduzido à parte.
-- Sem tradução, o texto fica em português.
-- (Chaves com modelo ignoram os espaços das pontas: o texto de tela chega sem eles na regra 3.)
local Lang = {}

Lang.LANGS = { "pt", "en", "es", "vi" }
Lang.NAMES = { pt = "Português", en = "English", es = "Español", vi = "Tiếng Việt" } :: { [string]: string }

-- "en-us" -> "en"; idioma sem dicionário cai no inglês (o mais lido no Roblox)
function Lang.fromLocale(id: string?): string
	local code = string.lower(string.sub(id or "", 1, 2))
	if code == "pt" or code == "es" or code == "vi" or code == "en" then
		return code
	end
	return "en"
end

-- ===== caixa alta com acentos (português e vietnamita) =====
local function upCodepoint(cp: number): number
	if cp >= 97 and cp <= 122 then
		return cp - 32
	elseif cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then
		return cp - 32
	elseif ((cp >= 0x100 and cp <= 0x137) or (cp >= 0x14A and cp <= 0x177)) and cp % 2 == 1 then
		return cp - 1
	elseif cp == 0x1A1 or cp == 0x1B0 then
		return cp - 1
	elseif cp >= 0x1EA0 and cp <= 0x1EF9 and cp % 2 == 1 then
		return cp - 1
	end
	return cp
end

function Lang.upper(s: string): string
	local ok, out = pcall(function(): string
		local parts = {}
		for _, cp in utf8.codes(s) do
			table.insert(parts, utf8.char(upCodepoint(cp)))
		end
		return table.concat(parts)
	end)
	return if ok then out else string.upper(s)
end

-- ===== modelos com especificadores do string.format =====
type Pat = { pat: string, segs: { string }, kinds: { string }, tspecs: { string }, lits: number }
export type Table = {
	exact: { [string]: string },
	upper: { [string]: string },
	pats: { Pat },
	cache: { [string]: string | false },
	cached: number,
}

local SPEC = "%%[%-%+#0]*%d*%.?%d*[dsfiqxg]"
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

-- Separa um texto de formato em pedaços literais e especificadores ("%%" vira "%"). Devolve também
-- o especificador inteiro de cada um ("%.1f", "%.0s"...).
local function split(fmt: string): ({ string }, { string }, { string })
	local segs, kinds, specs = {}, {}, {}
	local cur = {}
	local i = 1
	while i <= #fmt do
		local c = string.sub(fmt, i, i)
		-- {a}, {b}...: marcador do tutorial (o botão da ação entra no lugar), vale como %s
		if c == "{" then
			local a, b = string.find(fmt, "^{%a+}", i)
			if a and b then
				table.insert(segs, table.concat(cur))
				cur = {}
				table.insert(kinds, "s")
				table.insert(specs, string.sub(fmt, i, b))
				i = b + 1
				continue
			end
		end
		if c == "%" then
			if string.sub(fmt, i + 1, i + 1) == "%" then
				table.insert(cur, "%")
				i += 2
				continue
			end
			local a, b = string.find(fmt, SPEC, i)
			if a == i and b then
				table.insert(segs, table.concat(cur))
				cur = {}
				table.insert(kinds, string.sub(fmt, b, b))
				table.insert(specs, string.sub(fmt, i, b))
				i = b + 1
				continue
			end
		end
		table.insert(cur, c)
		i += 1
	end
	table.insert(segs, table.concat(cur))
	return segs, kinds, specs
end

local CAPTURE: { [string]: string } = {
	d = "([%+%-]?%d+)",
	i = "([%+%-]?%d+)",
	f = "([%+%-]?%d+%.?%d*)",
	g = "([%+%-]?%d+%.?%d*)",
	x = "(%x+)",
	s = "(.-)",
	q = "(.-)",
}

-- letras fixas do modelo: ASCII e latinas acentuadas (UTF-8: \195-\199 e \225 = Vietnamita)
local function letters(s: string): number
	local n = 0
	for _ in string.gmatch(s, "[%a\195-\199\225][\128-\191]*") do
		n += 1
	end
	-- marcas que também fixam o modelo: · — ► ▲ (UTF-8) e o til do "~120 m"
	for _ in string.gmatch(s, "[\194\226\240~][\128-\191]*") do
		n += 1
	end
	return n
end

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Alguma letra do bloco Latino Estendido (U+0100 a U+1FFF: Ă Ư ờ ạ...) que as fontes de época não têm.
function Lang.needsWide(s: string): boolean
	local ok, res = pcall(function(): boolean
		for _, cp in utf8.codes(s) do
			if cp >= 0x100 and cp <= 0x1FFF then
				return true
			end
		end
		return false
	end)
	return ok and res
end

-- Compila um dicionário português -> tradução.
function Lang.compile(dict: { [string]: string }): Table
	local t: Table = { exact = {}, upper = {}, pats = {}, cache = {}, cached = 0 }
	for pt, tr in dict do
		if type(pt) ~= "string" or type(tr) ~= "string" or tr == "" then
			continue
		end
		local segs, kinds = split(pt)
		if #kinds == 0 then
			local plain = table.concat(segs)
			local trPlain = table.concat((split(tr))) -- "%%" -> "%" também na tradução
			t.exact[plain] = trPlain
			t.upper[Lang.upper(plain)] = Lang.upper(trPlain)
		else
			-- o texto de tela chega sem os espaços das pontas (translate corta antes): a chave também
			segs, kinds = split(trim(pt))
			local tsegs, tkinds, tspecs = split(trim(tr))
			local lits = letters(table.concat(segs))
			if #tkinds == #kinds and lits >= 3 then
				local parts = {}
				for i, s in segs do
					table.insert(parts, (string.gsub(s, MAGIC, "%%%0")))
					if kinds[i] then
						table.insert(parts, CAPTURE[kinds[i]] or "(.-)")
					end
				end
				table.insert(t.pats, {
					pat = "^" .. table.concat(parts) .. "$",
					segs = tsegs,
					kinds = kinds,
					tspecs = tspecs,
					lits = lits,
				})
			end
		end
	end
	-- os mais específicos (mais letras fixas) primeiro
	table.sort(t.pats, function(a: Pat, b: Pat): boolean
		return a.lits > b.lits
	end)
	return t
end

local function word(t: Table, s: string): string
	return t.exact[s] or t.upper[s] or s
end

local translate: (t: Table, text: string, depth: number) -> string?

local function viaPattern(t: Table, text: string): string?
	for _, p in t.pats do
		local caps = { string.match(text, p.pat) }
		if #caps > 0 and #caps == #p.kinds then
			local out = {}
			for i, s in p.segs do
				table.insert(out, s)
				local c = caps[i]
				-- "%.0s" na tradução engole o valor (o "s" do plural português: "dia%s")
				if c and p.tspecs[i] ~= "%.0s" then
					table.insert(out, if p.kinds[i] == "s" then word(t, c) else c)
				end
			end
			return table.concat(out)
		end
	end
	return nil
end

-- Prefixo ou sufixo conhecido: "Desarmar " .. nome, "SOLDO: +" .. valor, nome .. " (caído)". As
-- chaves vêm do extrator (cada texto de tela e o seu miolo) e começam ou terminam em espaço ou
-- pontuação. Vale o prefixo mais longo e o sufixo mais longo (olha só os primeiros e os últimos
-- AFFIX_SPAN bytes: o resultado fica no cache de Lang.translate).
local AFFIX_SPAN = 48

local function isBreak(text: string, i: number): boolean
	local b = string.byte(text, i)
	return b ~= nil and b < 128 and string.find(string.char(b), "[%s%p]") ~= nil
end

local function viaAffix(t: Table, text: string, depth: number): string?
	local n = #text
	if n < 3 then
		return nil
	end
	local prefix: string? = nil
	local preEnd = 0
	for i = math.min(n - 1, AFFIX_SPAN), 2, -1 do
		if isBreak(text, i) then
			local pre = string.sub(text, 1, i)
			local hit = t.exact[pre] or t.upper[pre]
			if hit then
				prefix, preEnd = hit, i
				break
			end
		end
	end
	if prefix then
		local rest = string.sub(text, preEnd + 1)
		return prefix .. (translate(t, rest, depth + 1) or word(t, rest))
	end
	for j = math.max(2, n - AFFIX_SPAN), n - 1 do
		if isBreak(text, j) then
			local suf = string.sub(text, j)
			local hit = t.exact[suf] or t.upper[suf]
			if hit then
				local rest = string.sub(text, 1, j - 1)
				return (translate(t, rest, depth + 1) or word(t, rest)) .. hit
			end
		end
	end
	return nil
end

translate = function(t: Table, text: string, depth: number): string?
	local hit = t.exact[text] or t.upper[text]
	if hit then
		return hit
	end
	-- espaços nas pontas
	local pre, core, post = string.match(text, "^(%s*)(.-)(%s*)$")
	if core and core ~= text and core ~= "" then
		local c = translate(t, core, depth + 1)
		return if c then (pre :: string) .. c .. (post :: string) else nil
	end
	-- "CAUSA      Abatido por fuzil": rótulo em coluna (2 ou mais espaços); o valor fica na mesma
	-- coluna. Vem antes dos modelos porque um modelo que começa por %s engoliria a linha.
	local col, gap, val = string.match(text, "^(.-%S)(  +)(%S.*)$")
	if col then
		local tc = t.exact[col] or t.upper[col]
		if tc then
			local width = (utf8.len(col :: string) or #(col :: string)) + #(gap :: string)
			local pad = math.max(1, width - (utf8.len(tc) or #tc))
			return tc .. string.rep(" ", pad) .. (translate(t, val :: string, depth + 1) or word(t, val :: string))
		end
	end
	local p = viaPattern(t, text)
	if p then
		return p
	end
	if depth > 2 then
		return nil
	end
	-- linha a linha
	if string.find(text, "\n", 1, true) then
		local lines = string.split(text, "\n")
		local changed = false
		for i, l in lines do
			local tl = translate(t, l, depth + 1)
			if tl then
				lines[i] = tl
				changed = true
			end
		end
		return if changed then table.concat(lines, "\n") else nil
	end
	-- RichText: primeiro a frase inteira sem as marcas; as palavras que estavam marcadas (nome
	-- vietnamita no Arimo, tecla em cor) voltam marcadas na tradução
	if string.find(text, "<", 1, true) then
		local plain = string.gsub(text, "<[^>]+>", "")
		local whole = translate(t, plain, depth + 1)
		if whole then
			-- cada trecho marcado volta marcado: o mesmo texto (nome próprio) ou a tradução dele
			local out = whole
			local from = 1
			for o, _, i, c in string.gmatch(text, "(<(%a+)[^>]*>)([^<]+)(</%a+>)") do
				local open, inner, close = o :: string, i :: string, c :: string
				local piece = inner
				local a, b = string.find(out, piece, from, true)
				if not a then
					piece = word(t, inner)
					a, b = string.find(out, piece, from, true)
				end
				if a and b then
					out = string.sub(out, 1, a - 1) .. open .. piece .. close .. string.sub(out, b + 1)
					from = a + #open + #piece + #close
				end
			end
			return out
		end
		-- senão, os pedaços entre as marcas
		local changed = false
		local out = string.gsub(text, ">([^<]+)<", function(seg: string): string
			local ts = translate(t, seg, depth + 1)
			if ts then
				changed = true
				return ">" .. ts .. "<"
			end
			return ">" .. seg .. "<"
		end)
		-- pedaços antes da primeira marca e depois da última
		out = string.gsub(out, "^([^<]+)<", function(seg: string): string
			local ts = translate(t, seg, depth + 1)
			if ts then
				changed = true
				return ts .. "<"
			end
			return seg .. "<"
		end)
		out = string.gsub(out, ">([^>]+)$", function(seg: string): string
			local ts = translate(t, seg, depth + 1)
			if ts then
				changed = true
				return ">" .. ts
			end
			return ">" .. seg
		end)
		return if changed then out else nil
	end
	-- "Rótulo: valor"
	local head, rest = string.match(text, "^(.-): (.+)$")
	if head then
		local th = t.exact[head] or t.upper[head]
		if th then
			return th .. ": " .. (translate(t, rest :: string, depth + 1) or word(t, rest :: string))
		end
	end
	local viaAff = viaAffix(t, text, depth)
	if viaAff then
		return viaAff
	end
	-- lista "Alfa · Fuzileiro": peça a peça
	if string.find(text, " · ", 1, true) then
		local parts = string.split(text, " · ")
		local changed = false
		for i, part in parts do
			local tp = translate(t, part, depth + 1)
			if tp then
				parts[i] = tp
				changed = true
			end
		end
		if changed then
			return table.concat(parts, " · ")
		end
	end
	return nil
end

-- Tradução do texto, ou nil se não houver (fica o português). Guarda o resultado.
function Lang.translate(t: Table, text: string): string?
	local c = t.cache[text]
	if c ~= nil then
		return if c == false then nil else c :: string
	end
	-- sem letra nenhuma (números, horas, símbolos): nada a traduzir
	local r: string? = nil
	if string.find(text, "[%a\128-\255]") then
		r = translate(t, text, 0)
	end
	if t.cached > 4000 then
		table.clear(t.cache)
		t.cached = 0
	end
	t.cache[text] = if r then r else false
	t.cached += 1
	return r
end

return Lang
