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
--   6. linha a linha (texto com quebras) e pedaço a pedaço entre as marcas do RichText.
-- Sem tradução, o texto fica em português.
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
type Pat = { pat: string, segs: { string }, kinds: { string }, lits: number }
export type Table = {
	exact: { [string]: string },
	upper: { [string]: string },
	pats: { Pat },
	cache: { [string]: string | false },
	cached: number,
}

local SPEC = "%%[%-%+ #0]*%d*%.?%d*[dsfiqxg]"
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

-- Separa um texto de formato em pedaços literais e especificadores ("%%" vira "%").
local function split(fmt: string): ({ string }, { string })
	local segs, kinds = {}, {}
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
				i = b + 1
				continue
			end
		end
		table.insert(cur, c)
		i += 1
	end
	table.insert(segs, table.concat(cur))
	return segs, kinds
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

local function letters(s: string): number
	local n = 0
	for _ in string.gmatch(s, "%a") do
		n += 1
	end
	return n
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
			local tsegs, tkinds = split(tr)
			local lits = letters(table.concat(segs))
			if #tkinds == #kinds and lits >= 3 then
				local parts = {}
				for i, s in segs do
					table.insert(parts, (string.gsub(s, MAGIC, "%%%0")))
					if kinds[i] then
						table.insert(parts, CAPTURE[kinds[i]] or "(.-)")
					end
				end
				table.insert(
					t.pats,
					{ pat = "^" .. table.concat(parts) .. "$", segs = tsegs, kinds = kinds, lits = lits }
				)
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
				if c then
					table.insert(out, if p.kinds[i] == "s" then word(t, c) else c)
				end
			end
			return table.concat(out)
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
			return th .. ": " .. word(t, rest :: string)
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
