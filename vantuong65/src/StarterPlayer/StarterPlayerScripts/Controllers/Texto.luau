--!strict
-- Funções de texto puras (sem serviço do Roblox; testadas no Lune, tests/luau/interface.luau).

local Texto = {}

-- 1ª frase e o resto ("Atirar: <b>RT</b>. Um ou dois tiros..." -> "Atirar: <b>RT</b>.", "Um ou
-- dois tiros..."). O ponto dentro de uma marca do RichText não conta; fim de frase é ". ", "! " ou
-- "? " (o sinal pode vir antes de marcas que fecham). Sem fim de frase, o texto todo e "".
function Texto.splitSentence(text: string): (string, string)
	local depth = 0
	local n = #text
	for i = 1, n do
		local c = string.sub(text, i, i)
		if c == "<" then
			depth += 1
		elseif c == ">" then
			depth = math.max(depth - 1, 0)
		elseif depth == 0 and (c == "." or c == "!" or c == "?") then
			local j = i + 1
			while string.sub(text, j, j) == "<" do
				local close = string.find(text, ">", j, true)
				if not close then
					break
				end
				j = close + 1
			end
			if string.sub(text, j, j) == " " and j < n then
				return string.sub(text, 1, j - 1), (string.gsub(string.sub(text, j + 1), "^%s+", ""))
			end
		end
	end
	return text, ""
end

return Texto
