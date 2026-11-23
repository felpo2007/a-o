--!strict
-- D-215 (dono: "quero transição nas telas de vitoria carregamento etc"; "analise como o jogo de box no
-- roblox faz suas transições tela de carregamento etc"): a cortina das trocas grandes de tela. Um
-- quadrado escuro e inclinado atravessa a tela da esquerda para a direita com a faixa âmbar na frente,
-- cobre, mostra o nome da próxima tela no meio e sai pela direita com a faixa de trás. A troca de
-- conteúdo acontece com a tela coberta (nada pisca).
-- Usada na saída da tela de entrada para o lobby e nas fases do fim de partida (comemoração,
-- votação, preparando o campo, a partida nova). A conta (posições e curvas) é do CortinaCurva.
-- Movimento reduzido: sem atravessar; o painel esmaece no lugar.
-- Uma de cada vez: um pedido que chega com outra passando espera a vez.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CortinaCurva = require(script.Parent:WaitForChild("CortinaCurva"))
local Estilo = require(script.Parent:WaitForChild("Estilo"))

local Cortina = {}

local V, F = Estilo.V, Estilo.F

type Partes = {
	gui: ScreenGui,
	painel: Frame,
	titulo: TextLabel,
	sub: TextLabel,
	faixas: { Frame },
}
local partes: Partes? = nil
local ocupada = false
local coberta = false

local function montar(): Partes
	local p = partes
	if p and p.gui.Parent then
		return p
	end
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "VT65Cortina"
	gui.DisplayOrder = 1000 -- acima de tudo, até da tela de entrada (100)
	gui.IgnoreGuiInset = true
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = pg
	local painel = Instance.new("Frame")
	painel.Name = "Painel"
	painel.AnchorPoint = Vector2.new(0.5, 0.5)
	painel.BackgroundColor3 = V.BG
	painel.BorderSizePixel = 0
	painel.Rotation = CortinaCurva.INCLINA
	painel.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(V.BG_OLIVE, V.BG)
	g.Parent = painel
	-- as faixas: âmbar e cáqui na frente (direita) e atrás (esquerda), giram com o painel
	local faixas: { Frame } = {}
	for _, f in
		{
			{ x = 1, larg = 18, cor = V.AMBAR, dx = 0 },
			{ x = 1, larg = 6, cor = V.KHAKI, dx = 26 },
			{ x = 0, larg = 18, cor = V.AMBAR, dx = -18 },
			{ x = 0, larg = 6, cor = V.KHAKI, dx = -32 },
		}
	do
		local fr = Instance.new("Frame")
		fr.Name = "Faixa"
		fr.BackgroundColor3 = f.cor
		fr.BorderSizePixel = 0
		fr.Position = UDim2.new(f.x, f.dx, 0, 0)
		fr.Size = UDim2.new(0, f.larg, 1, 0)
		fr.Parent = painel
		table.insert(faixas, fr)
	end
	local titulo = Instance.new("TextLabel")
	titulo.Name = "Titulo"
	titulo.BackgroundTransparency = 1
	titulo.AnchorPoint = Vector2.new(0.5, 0.5)
	titulo.Position = UDim2.fromScale(0.5, 0.47)
	titulo.Size = UDim2.new(0.9, 0, 0, Estilo.px(84, 120))
	titulo.FontFace = F.TITLE
	titulo.Text = "STARLITE"
	titulo.TextColor3 = V.TEXT
	titulo.TextSize = Estilo.ts(Estilo.px(72, 100))
	titulo.TextTransparency = 1
	titulo.ZIndex = 3
	titulo.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0.47, Estilo.px(44, 62))
	sub.Size = UDim2.new(0.9, 0, 0, Estilo.px(28, 40))
	sub.FontFace = F.TITLE_MED
	sub.TextColor3 = V.AMBAR
	sub.TextSize = Estilo.ts(Estilo.px(20, 28))
	sub.TextTransparency = 1
	sub.ZIndex = 3
	sub.Parent = gui
	local novo: Partes = { gui = gui, painel = painel, titulo = titulo, sub = sub, faixas = faixas }
	partes = novo
	return novo
end

local function textos(p: Partes, tr: number)
	p.titulo.TextTransparency = tr
	p.sub.TextTransparency = tr
end

local function transp(p: Partes, tr: number)
	p.painel.BackgroundTransparency = tr
	for _, f in p.faixas do
		f.BackgroundTransparency = tr
	end
end

-- anima `dur` s chamando f(u) a cada quadro (u de 0 a 1)
local function anima(dur: number, f: (u: number) -> ())
	local t0 = os.clock()
	while true do
		local u = if dur > 0 then math.clamp((os.clock() - t0) / dur, 0, 1) else 1
		f(u)
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

-- Cobre a tela (espera terminar). `titulo` e `sub` aparecem no meio, com a tela coberta.
function Cortina.cobrir(titulo: string?, sub: string?)
	while ocupada do
		task.wait()
	end
	ocupada = true
	local p = montar()
	local calmo = Estilo.reduzMovimento()
	local T = if calmo then CortinaCurva.TEMPO_CALMO else CortinaCurva.TEMPO
	local tam = p.gui.AbsoluteSize
	local W, H = math.max(tam.X, 1), math.max(tam.Y, 1)
	local lado, x0, xm = CortinaCurva.posicoes(W, H)
	p.painel.Size = UDim2.fromOffset(lado, lado)
	p.titulo.Text = titulo or "STARLITE"
	p.sub.Text = sub or ""
	textos(p, 1)
	p.gui.Enabled = true
	if calmo then
		p.painel.Position = UDim2.fromOffset(xm, H / 2)
		anima(T.entra, function(u: number)
			transp(p, 1 - u)
		end)
	else
		transp(p, 0)
		anima(T.entra, function(u: number)
			local k = CortinaCurva.entra(u)
			p.painel.Position = UDim2.fromOffset(x0 + (xm - x0) * k, H / 2)
		end)
	end
	coberta = true
	-- o nome da próxima tela acende com a tela coberta
	anima(math.min(0.15, T.segura), function(u: number)
		textos(p, 1 - u)
	end)
	ocupada = false
end

-- Descobre a tela (espera terminar): a cortina segue saindo pela direita.
function Cortina.descobrir()
	while ocupada do
		task.wait()
	end
	local p = partes
	if not (p and coberta) then
		return
	end
	ocupada = true
	local calmo = Estilo.reduzMovimento()
	local T = if calmo then CortinaCurva.TEMPO_CALMO else CortinaCurva.TEMPO
	local tam = p.gui.AbsoluteSize
	local W, H = math.max(tam.X, 1), math.max(tam.Y, 1)
	local _, _, xm, x1 = CortinaCurva.posicoes(W, H)
	task.wait(T.segura)
	anima(0.12, function(u: number)
		textos(p, u)
	end)
	if calmo then
		anima(T.sai, function(u: number)
			transp(p, u)
		end)
	else
		anima(T.sai, function(u: number)
			local k = CortinaCurva.sai(u)
			p.painel.Position = UDim2.fromOffset(xm + (x1 - xm) * k, H / 2)
		end)
	end
	p.gui.Enabled = false
	coberta = false
	ocupada = false
end

-- Se a cortina falhar no meio, ela some e libera a vez (a troca de tela nunca fica presa nela).
function Cortina.soltar()
	local p = partes
	if p then
		p.gui.Enabled = false
	end
	ocupada = false
	coberta = false
end

-- Cobre, troca (fn, com a tela coberta) e descobre. A troca acontece mesmo se a cortina falhar.
function Cortina.passar(fn: () -> (), titulo: string?, sub: string?)
	local okC, errC = pcall(function()
		Cortina.cobrir(titulo, sub)
	end)
	if not okC then
		warn("[VT65] cortina: não cobriu: " .. tostring(errC))
		Cortina.soltar()
	end
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn("[VT65] cortina: a troca falhou: " .. tostring(err))
	end
	if okC then
		local okD, errD = pcall(function()
			Cortina.descobrir()
		end)
		if not okD then
			warn("[VT65] cortina: não descobriu: " .. tostring(errD))
			Cortina.soltar()
		end
	end
end

function Cortina.coberta(): boolean
	return coberta
end

return Cortina
