--!strict
-- D-216 (dono: "os textos no celular estão horriveis tudo em cima do outro"): nenhum texto passa da
-- caixa dele. O tamanho da letra sobe com a preferência do aparelho (Estilo.textoK, até 1,45) e com as
-- traduções, mas as caixas são fixas: no celular a letra transbordava e encostava na de baixo.
-- Aqui, todo TextLabel e TextButton da PlayerGui que não couber passa a encolher até caber
-- (TextScaled com o teto no tamanho de projeto, sem nunca crescer além dele).
-- Fica de fora: o que tem tamanho automático (a caixa cresce com o texto), o que já escala e quem
-- pede com o atributo "TextoLivre". Confere em rodízio, poucos por quadro, porque a caixa pode ganhar
-- tamanho, texto ou tradução depois de criada.
local TextoCabe = {}

TextoCabe.MINIMO = 8 -- px: abaixo disto o texto não se lê
TextoCabe.POR_QUADRO = 40

export type Props = {
	escala: boolean,
	automatico: boolean,
	livre: boolean,
	texto: string,
	w: number,
	h: number,
	cabe: boolean,
}

-- Regra pura: este texto precisa encolher agora?
function TextoCabe.precisa(p: Props): boolean
	if p.escala or p.automatico or p.livre or p.texto == "" then
		return false
	end
	-- ainda sem tamanho (animando ou fora da tela): espera
	if p.w < 6 or p.h < 6 then
		return false
	end
	return not p.cabe
end

-- O teto e o piso do texto que passa a encolher: nunca maior que o de projeto
function TextoCabe.limites(tamanho: number): (number, number)
	local teto = math.max(1, math.floor(tamanho + 0.5))
	return teto, math.min(TextoCabe.MINIMO, teto)
end

local function encolhe(o: any)
	local ok = pcall(function()
		local a = o.AbsoluteSize
		if
			not TextoCabe.precisa({
				escala = o.TextScaled,
				automatico = o.AutomaticSize ~= Enum.AutomaticSize.None,
				livre = o:GetAttribute("TextoLivre") == true,
				texto = o.Text,
				w = a.X,
				h = a.Y,
				cabe = o.TextFits,
			})
		then
			return
		end
		if not o:FindFirstChildOfClass("UITextSizeConstraint") then
			local teto, piso = TextoCabe.limites(o.TextSize)
			local lim = Instance.new("UITextSizeConstraint")
			lim.Name = "TextoCabe"
			lim.MaxTextSize = teto
			lim.MinTextSize = piso
			lim.Parent = o
		end
		o.TextScaled = true
	end)
	if not ok then
		o = nil
	end
end

local iniciado = false
function TextoCabe.iniciar()
	if iniciado then
		return
	end
	iniciado = true
	task.spawn(function()
		local Players = game:GetService("Players")
		local RunService = game:GetService("RunService")
		local player = Players.LocalPlayer
		local pg = player:WaitForChild("PlayerGui")
		local lista: { Instance } = {}
		local visto: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
		local function add(o: Instance)
			if (o:IsA("TextLabel") or o:IsA("TextButton")) and not visto[o] then
				visto[o] = true
				table.insert(lista, o)
			end
		end
		for _, o in pg:GetDescendants() do
			add(o)
		end
		pg.DescendantAdded:Connect(add)
		local i = 0
		RunService.Heartbeat:Connect(function()
			for _ = 1, TextoCabe.POR_QUADRO do
				local n = #lista
				if n == 0 then
					return
				end
				i += 1
				if i > n then
					i = 1
				end
				local o = lista[i]
				if o.Parent == nil then
					-- saiu da tela: troca pelo último (se voltar, o DescendantAdded põe de novo)
					visto[o] = nil
					lista[i] = lista[n]
					lista[n] = nil
					i -= 1
				else
					encolhe(o)
				end
			end
		end)
	end)
end

return TextoCabe
