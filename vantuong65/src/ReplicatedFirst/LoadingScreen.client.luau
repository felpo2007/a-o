--!strict
-- Tela de entrada (pedido do dono, 2026-11-11: "na tela de carregamento demore um pouco mais para
-- carregar, porém carregue todas as features do jogo"; "torne o jogo 1000x mais liso"; "não gosto
-- dessa escrita no papel"; "gostei muito da primeira tela de carregamento do jogo, use ela de
-- inspiração para as outras"). O layout da primeira tela no estilo novo (ReplicatedFirst/Estilo):
-- fundo escuro de cor única; à esquerda o nome do jogo ("STARLITE: Vietnã 1965") enorme numa
-- moldura fina, o subtítulo, o briefing (um fato curto por vez) num painel escuro de borda fina e
-- três números grandes do que já chegou (sons, animações, arte); à direita a carta da área sendo
-- traçada (grade, curvas de nível, os eixos e o objetivo); embaixo a linha curta do que está
-- carregando e a barra fina com o progresso REAL. É a referência visual das outras telas.
-- O que carrega (ContentProvider:PreloadAsync, em lotes; o callback conta cada asset):
--   1. o jogo (game.Loaded) e 2. os remotes do servidor;
--   3. a interface: fontes, as texturas do Acabamento, os botões do controle e as imagens que o
--      servidor resolveu (Img_*, a carta tática CartaImage_*), chão e céu do AssetIds;
--   4. todos os sons do AssetIds.Sounds;
--   5. as animações do soldado (Shared/SoldierAnims);
--   6. os manequins do lobby e a arte das armas (o PreviewService marca Ready) e
--   7. a arte que já está no cliente: malhas, texturas, decalques, SurfaceAppearance, imagens,
--      partículas, roupas, céu e MaterialVariant do ReplicatedStorage, do Workspace já replicado,
--      do Lighting e do MaterialService (cada id uma vez só);
--   8. o terreno (atributo TerrainReady: o servidor só avisa quando acaba).
-- Só com tudo pronto aparece "ENTRAR" (clique, toque, Enter/Espaço ou A; Y abre o idioma) e uma
-- contagem de 10 s entra sozinha. Teto de segurança: com 90 s, "ENTRAR" aparece de qualquer jeito
-- e o resto termina no lobby. A saída só toca tweens já criados (nada pesado no mesmo quadro).
-- Fora o Estilo, o Idioma e o Acabamento (mesmo ReplicatedFirst), não depende de nada: aparece desde
-- o 1º quadro.
-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "carregamento") reabre a
-- tela e refaz o carregamento de verdade (o que já está na memória chega rápido) para a foto;
-- qualquer outro valor (ou nil) fecha, se já estiver pronta.
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local Estilo = require(script.Parent:WaitForChild("Estilo"))
local Acabamento = require(script.Parent:WaitForChild("Acabamento"))
local Idioma = require(script.Parent:WaitForChild("Idioma"))

local player = Players.LocalPlayer
local V, F = Estilo.V, Estilo.F
local TV = Estilo.tv()

local CAP_S = 90 -- teto de segurança
local AUTO_S = 10 -- com tudo pronto, entra sozinha depois disso
local BATCH = 16 -- assets por chamada do PreloadAsync (a barra anda por lote e por asset)

local QUINT = Enum.EasingStyle.Quint
local OUT, INOUT = Enum.EasingDirection.Out, Enum.EasingDirection.InOut

local function tween(
	o: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local tw = TweenService:Create(o, TweenInfo.new(t, style or QUINT, dir or OUT), props)
	tw:Play()
	return tw
end

-- ===== montagem =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Loading"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)

local bg = Estilo.backdrop(gui, V.BG)
local vignette = Instance.new("ImageLabel")
vignette.Name = "Vinheta"
vignette.BackgroundTransparency = 1
vignette.Size = UDim2.fromScale(1, 1)
vignette.Image = Acabamento.VINHETA
vignette.ImageColor3 = Color3.new(0, 0, 0)
vignette.ImageTransparency = 0.2
vignette.Parent = bg

-- palco de 1280 x 720 que escala com a tela
local stage = Instance.new("Frame")
stage.Name = "Palco"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(1280, 720)
stage.BackgroundTransparency = 1
stage.Parent = bg
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage

local LEFT, RIGHT = 88, 1192

-- Layout da primeira tela de entrada (o dono: "gostei muito da primeira tela de carregamento do
-- jogo, use ela de inspiração para as outras"), no estilo novo: à esquerda o título enorme, o
-- subtítulo, o briefing num painel escuro de borda fina e os números do que já chegou; à direita a
-- carta da área sendo traçada; embaixo a linha da etapa, a barra e o ENTRAR.

-- ----- título: o nome enorme na moldura fina, o filete oliva e o subtítulo -----
local TITLE_SIZE, TITLE_MAX = 76, 700 -- o título encolhe se passar da coluna (tradução mais longa)
local titleBox, title = Estilo.titleBox(stage, "STARLITE: VIETNÃ 1965", TITLE_SIZE)
title.FontFace = F.TITLE -- o nome do jogo no Oswald
titleBox.Position = UDim2.fromOffset(LEFT - 4, 92)
local function fitTitle()
	local sw = stage.AbsoluteSize.X
	if sw < 10 then
		return
	end
	local w = titleBox.AbsoluteSize.X / sw * 1280 -- largura no palco de projeto
	if w > TITLE_MAX and title.TextSize > 44 then
		title.TextSize = math.max(44, title.TextSize - 4)
	end
end
titleBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTitle)
title:GetPropertyChangedSignal("Text"):Connect(function()
	title.TextSize = Estilo.ts(TITLE_SIZE) -- texto novo (idioma): mede de novo do tamanho cheio
end)
local accent = Instance.new("Frame")
accent.Name = "Filete"
accent.BackgroundColor3 = V.OLIVE_HI
accent.BorderSizePixel = 0
accent.Position = UDim2.fromOffset(LEFT, 222)
accent.Size = UDim2.fromOffset(120, 5)
accent.Parent = stage
local subtitle = Estilo.text(stage, "Operação Starlite · Vạn Tường, 18–24 ago 1965", 20, V.DIM, F.BODY)
subtitle.Position = UDim2.fromOffset(LEFT, 234)
subtitle.Size = UDim2.fromOffset(700, 28)
subtitle.TextTruncate = Enum.TextTruncate.AtEnd

-- ----- briefing: painel escuro de borda fina, um fato curto por vez (The First Fight, USMC 2015;
-- citações em research/F0_FONTES.md) -----
local BRIEFING: { { texto: string, pagina: string } } = {
	{
		texto = "18 AGO 1965 · 0630H. As companhias K e I desembarcam como planejado na Green Beach.",
		pagina = "p. 21",
	},
	{ texto = "A praia não foi bombardeada: a vila de An Cường (1) fica perto demais.", pagina = "p. 21" },
	{ texto = "A companhia K toma o terreno alto logo depois da vila, com a Colina 22.", pagina = "p. 21" },
	{ texto = "Sebes de bambu e árvores de 1,8 a 2,4 m dividem cada arrozal.", pagina = "p. 10" },
	{ texto = "An Cường (2): vila de mata fechada, trincheiras cobertas de galhos e toras.", pagina = "p. 25" },
	{ texto = "LZ Blue, logo ao sul de Nam Yên (3). A Colina 43 fica uns 400 m a sudoeste.", pagina = "p. 29" },
	{ texto = "A Colina 30, ao norte de An Cường (2), domina a zona de pouso.", pagina = "p. 29" },
}
local BW, BH = 700, 150
local brief = Estilo.panel(stage, V.PANEL, 0.06, true)
brief.Name = "Briefing"
brief.Position = UDim2.fromOffset(LEFT, 278)
brief.Size = UDim2.fromOffset(BW, BH)
local briefBar = Instance.new("Frame")
briefBar.Name = "Faixa"
briefBar.BackgroundColor3 = V.OLIVE_HI
briefBar.BorderSizePixel = 0
briefBar.Size = UDim2.new(0, 4, 1, 0)
briefBar.Parent = brief
local briefHead = Estilo.kicker(brief, "BRIEFING", 15)
briefHead.Position = UDim2.fromOffset(22, 12)
briefHead.Size = UDim2.fromOffset(300, 22)
local briefIdx = Estilo.kicker(brief, "", 15)
briefIdx.AnchorPoint = Vector2.new(1, 0)
briefIdx.Position = UDim2.new(1, -20, 0, 12)
briefIdx.Size = UDim2.fromOffset(80, 22)
briefIdx.TextXAlignment = Enum.TextXAlignment.Right
local briefText = Estilo.body(brief, "", 19, V.TEXT)
briefText.Position = UDim2.fromOffset(22, 40)
briefText.Size = UDim2.fromOffset(BW - 44, 56)
briefText.TextTruncate = Enum.TextTruncate.AtEnd
local briefSrc = Estilo.text(brief, "", 13, V.DIM, F.BODY)
briefSrc.Position = UDim2.fromOffset(22, 102)
briefSrc.Size = UDim2.fromOffset(BW - 44, 18)
briefSrc.TextTruncate = Enum.TextTruncate.AtEnd
-- tempo do fato na tela: um fio que encurta
local briefLine = Instance.new("Frame")
briefLine.Name = "Tempo"
briefLine.BackgroundColor3 = V.OLIVE
briefLine.BorderSizePixel = 0
briefLine.Position = UDim2.fromOffset(22, 130)
briefLine.Size = UDim2.fromOffset(BW - 44, 2)
briefLine.Parent = brief

-- ----- números do que já chegou -----
local stats = Estilo.statRow(stage, { { "SONS", "—" }, { "ANIMAÇÕES", "—" }, { "ARTE", "—" } }, 52)
stats.frame.Position = UDim2.fromOffset(LEFT, 454)
local statSounds, statAnims, statArt = stats.stats[1], stats.stats[2], stats.stats[3]

-- ----- carta da área, à direita: grade, mar, curvas de nível, os eixos a vermelho e o objetivo
-- piscando (como na primeira tela, sem papel: painel escuro de borda fina) -----
local MAP = 352
local mapPanel = Estilo.panel(stage, V.PANEL, 0.06, true)
mapPanel.Name = "Carta"
mapPanel.AnchorPoint = Vector2.new(1, 0)
mapPanel.Position = UDim2.fromOffset(RIGHT, 104)
mapPanel.Size = UDim2.fromOffset(MAP, MAP + 36)
local area = Instance.new("Frame")
area.Name = "Area"
area.BackgroundColor3 = Color3.fromRGB(28, 32, 24)
area.BorderSizePixel = 0
area.Position = UDim2.fromOffset(16, 16)
area.Size = UDim2.fromOffset(MAP - 32, MAP - 32)
area.Parent = mapPanel
local GRID = Color3.fromRGB(92, 108, 128)
local CONTOUR = Color3.fromRGB(176, 150, 96)
local sea = Instance.new("Frame")
sea.Name = "Mar"
sea.BackgroundColor3 = Color3.fromRGB(34, 54, 78)
sea.BorderSizePixel = 0
sea.Position = UDim2.fromScale(0.9, 0)
sea.Size = UDim2.fromScale(0.1, 1)
sea.Parent = area
local seaName = Estilo.kicker(area, "MAR", 11, Color3.fromRGB(120, 150, 186))
seaName.AnchorPoint = Vector2.new(0.5, 0.5)
seaName.Position = UDim2.fromScale(0.95, 0.5)
seaName.Size = UDim2.fromOffset(40, 16)
seaName.TextXAlignment = Enum.TextXAlignment.Center
seaName.Rotation = 90
type Draw = { f: Frame, full: UDim2, from: UDim2, delay: number }
local draws: { Draw } = {}
for i = 1, 8 do
	local v = Instance.new("Frame")
	v.BackgroundColor3 = GRID
	v.BackgroundTransparency = 0.6
	v.BorderSizePixel = 0
	v.Position = UDim2.fromScale(i / 9, 0)
	v.Parent = area
	table.insert(draws, { f = v, full = UDim2.new(0, 1, 1, 0), from = UDim2.new(0, 1, 0, 0), delay = i * 0.04 })
	local h = v:Clone()
	h.Position = UDim2.fromScale(0, i / 9)
	h.Parent = area
	table.insert(draws, { f = h, full = UDim2.new(1, 0, 0, 1), from = UDim2.new(0, 0, 0, 1), delay = i * 0.04 + 0.02 })
end
-- curvas de nível das duas colinas (anéis que crescem do cume para fora)
for hIdx, hill in { { 0.32, 0.4, 5 }, { 0.6, 0.74, 4 } } do
	for k = 1, hill[3] do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(hill[1], hill[2])
		ring.BackgroundTransparency = 1
		ring.Parent = area
		Estilo.corner(ring, 999)
		Estilo.stroke(ring, CONTOUR, if k == 1 then 2 else 1, 0.3)
		local r = 0.06 + k * 0.05
		table.insert(draws, {
			f = ring,
			full = UDim2.fromScale(r * (1.3 - 0.05 * k), r),
			from = UDim2.fromScale(0, 0),
			delay = 0.35 + hIdx * 0.2 + k * 0.08,
		})
	end
end
local hill43 = Estilo.text(area, "43", 13, V.DIM, F.BODY_B)
hill43.Position = UDim2.fromOffset(78, 100)
hill43.Size = UDim2.fromOffset(40, 16)
local hill30 = Estilo.text(area, "30", 13, V.DIM, F.BODY_B)
hill30.Position = UDim2.fromOffset(186, 210)
hill30.Size = UDim2.fromOffset(40, 16)
-- eixos: o desembarque vindo da praia e o da LZ no norte
local axisBeach = Acabamento.linha(area, V.RED, 4, 18, 5)
local axisLz = Acabamento.linha(area, V.RED_HI, 3, 12, 5)
local objective = Acabamento.marca(area, V.RED_HI, 22, 6)
objective.raiz.Position = UDim2.fromScale(0.36, 0.44)
objective.raiz.Visible = false
local mapLabel = Estilo.kicker(mapPanel, "CARTA 1:50.000 · VẠN TƯỜNG · QUẢNG NGÃI", 13)
mapLabel.Position = UDim2.fromOffset(16, MAP - 8)
mapLabel.Size = UDim2.fromOffset(MAP - 32, 30)

-- ----- base: o que está carregando, o número grande, a barra e o ENTRAR -----
local status = Estilo.text(stage, "", 20, V.TEXT, F.BODY)
status.Position = UDim2.fromOffset(LEFT, 612)
status.Size = UDim2.fromOffset(760, 28)
status.TextTruncate = Enum.TextTruncate.AtEnd
local percent = Estilo.text(stage, "0%", 50, V.TEXT, F.TITLE)
percent.AnchorPoint = Vector2.new(1, 0)
percent.Position = UDim2.fromOffset(RIGHT, 586)
percent.Size = UDim2.fromOffset(240, 58)
percent.TextXAlignment = Enum.TextXAlignment.Right
local barBack, barFill = Estilo.bar(stage, 6, V.OLIVE_HI)
barBack.Position = UDim2.fromOffset(LEFT, 656)
barBack.Size = UDim2.fromOffset(RIGHT - LEFT, 6)
-- brilho que corre na barra enquanto uma etapa não tem número (manequins, terreno)
local shine = Instance.new("Frame")
shine.Name = "Brilho"
shine.Size = UDim2.fromScale(1, 1)
shine.BackgroundColor3 = V.TEXT
shine.BorderSizePixel = 0
shine.ZIndex = 3
shine.Visible = false
shine.Parent = barBack
local shineGrad = Instance.new("UIGradient")
shineGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.42, 1),
	NumberSequenceKeypoint.new(0.5, 0.5),
	NumberSequenceKeypoint.new(0.58, 1),
	NumberSequenceKeypoint.new(1, 1),
})
shineGrad.Parent = shine

local enter = Estilo.button(stage, "ENTRAR", "primary", 72)
enter.button.Name = "Entrar"
enter.button.AnchorPoint = Vector2.new(1, 0)
enter.button.Position = UDim2.fromOffset(RIGHT, 566)
enter.button.Size = UDim2.fromOffset(340, 72)
enter.button.Selectable = false -- A, Enter e Espaço chegam pelo InputBegan (um clique só)
enter.button.Visible = false
local enterScale = Instance.new("UIScale")
enterScale.Parent = enter.button

-- ----- idioma (pedido do dono, 2026-11-11): chip no alto à direita; Y no controle -----
local function openLanguage()
	if not Idioma.aberto() then
		Idioma.abrir({ z = 101 })
	end
end
local langChip = Idioma.chip(stage, { onClick = openLanguage, padKey = Enum.KeyCode.ButtonY })
langChip.button.AnchorPoint = Vector2.new(1, 0)
langChip.button.Position = UDim2.fromOffset(RIGHT, 46)

gui.Parent = player:WaitForChild("PlayerGui")

-- ===== escala do palco (sem laço por quadro: só quando a janela muda) =====
local function fit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	local k = math.max(math.min(s.X / 1280, s.Y / 720), 0.45)
	if TV then
		k = math.max(k * 0.92, 1) -- margem de segurança da TV
	end
	stageScale.Scale = k
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- ===== progresso =====
-- peso de cada etapa na barra (soma 1); frac[i] de 0 a 1
local WEIGHTS = { 0.04, 0.04, 0.12, 0.16, 0.08, 0.16, 0.28, 0.12 }
local frac: { number } = { 0, 0, 0, 0, 0, 0, 0, 0 }
local prog = Instance.new("NumberValue")
local target = 0
prog.Changed:Connect(function(v: number)
	local x = math.clamp(v, 0, 1)
	barFill.Size = UDim2.fromScale(x, 1)
	percent.Text = string.format("%d%%", math.floor(x * 100 + 0.5))
end)
local function setTarget(v: number)
	if v <= target then
		return -- só anda para a frente
	end
	target = v
	tween(prog, 0.35, { Value = v }, Enum.EasingStyle.Quad)
end
local function setFrac(i: number, f: number)
	frac[i] = math.max(frac[i], math.clamp(f, 0, 1))
	local sum = 0
	for k, w in WEIGHTS do
		sum += w * frac[k]
	end
	setTarget(sum)
end

local shineTween: Tween? = nil
local function setWaiting(on: boolean)
	shine.Visible = on
	if on and not shineTween then
		shineGrad.Offset = Vector2.new(-1, 0)
		local tw = TweenService:Create(
			shineGrad,
			TweenInfo.new(1.4, Enum.EasingStyle.Sine, INOUT, -1),
			{ Offset = Vector2.new(1, 0) }
		)
		tw:Play()
		shineTween = tw
	elseif not on and shineTween then
		shineTween:Cancel()
		shineTween = nil
	end
end

-- a linha de baixo troca esmaecendo (0,18 s): nunca pisca seco
local statusToken = 0
local function setStatus(text: string)
	statusToken += 1
	local my = statusToken
	tween(status, 0.12, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
	task.delay(0.12, function()
		if statusToken == my then
			status.Text = text
			tween(status, 0.18, { TextTransparency = 0 }, Enum.EasingStyle.Quad)
		end
	end)
end

local function count(st: Estilo.Stat, done: number, total: number)
	st.value.Text = if total > 0 then string.format("%d/%d", math.min(done, total), total) else "—"
end

-- PreloadAsync em lotes: onStep(feitos, total) a cada asset e a cada lote
local function preload(items: { any }, onStep: (done: number, total: number) -> ())
	local total = #items
	onStep(0, total)
	local done = 0
	local i = 1
	while i <= total do
		local batch = table.move(items, i, math.min(i + BATCH - 1, total), 1, {})
		local n = 0
		pcall(function()
			ContentProvider:PreloadAsync(batch, function()
				n += 1
				onStep(done + math.min(n, #batch), total)
			end)
		end)
		done += #batch
		onStep(done, total)
		i += BATCH
	end
end

-- ===== o que carregar =====
local seen: { [string]: boolean } = {}
local function addId(list: { any }, id: any)
	if type(id) == "string" and id ~= "" and not seen[id] then
		seen[id] = true
		table.insert(list, id)
	end
end
local function assetId(n: any): string?
	return if type(n) == "number" and n ~= 0 then string.format("rbxassetid://%d", n) else nil
end
-- lê uma propriedade de conteúdo (algumas não podem ser lidas por script: nil)
local function prop(o: Instance, name: string): any
	local ok, v = pcall(function()
		return (o :: any)[name]
	end)
	return if ok then v else nil
end

-- a arte de uma árvore de instâncias: um id por asset (o mesmo id em mil árvores entra uma vez)
local function scanArt(root: Instance?, list: { any })
	if not root then
		return
	end
	local all = root:GetDescendants()
	for k, d in all do
		if d:IsA("MeshPart") then
			addId(list, prop(d, "MeshId"))
			addId(list, prop(d, "TextureID"))
		elseif d:IsA("SpecialMesh") then
			addId(list, prop(d, "MeshId"))
			addId(list, prop(d, "TextureId"))
		elseif d:IsA("Decal") then -- Texture também
			addId(list, prop(d, "Texture"))
		elseif d:IsA("SurfaceAppearance") then
			local c = prop(d, "ColorMap")
			if type(c) == "string" then
				addId(list, c)
				addId(list, prop(d, "NormalMap"))
				addId(list, prop(d, "RoughnessMap"))
				addId(list, prop(d, "MetalnessMap"))
			else
				table.insert(list, d) -- sem leitura: o PreloadAsync pega o que ela usa
			end
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			addId(list, prop(d, "Image"))
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
			addId(list, prop(d, "Texture"))
		elseif d:IsA("Shirt") then
			addId(list, prop(d, "ShirtTemplate"))
		elseif d:IsA("Pants") then
			addId(list, prop(d, "PantsTemplate"))
		elseif d:IsA("Sky") then
			for _, side in { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" } do
				addId(list, prop(d, side))
			end
		elseif d:IsA("MaterialVariant") then
			for _, m in { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" } do
				addId(list, prop(d, m))
			end
		end
		if k % 1500 == 0 then
			task.wait() -- varredura grande: um quadro de folga a cada 1.500 peças
		end
	end
end

local function sharedModule(name: string): any
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	local m = shared and shared:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, v = pcall(require, m)
		if ok then
			return v
		end
	end
	return nil
end

local function interfaceList(): { any }
	local list: { any } = {}
	-- fontes: um rótulo por fonte (o PreloadAsync baixa a fonte do rótulo)
	for _, font in
		{
			F.TITLE,
			F.TITLE_MED,
			F.TITLE_REG,
			F.BODY,
			F.BODY_B,
			Font.fromEnum(Enum.Font.GothamMedium),
			Font.fromEnum(Enum.Font.GothamBold),
		}
	do
		local l = Instance.new("TextLabel")
		l.FontFace = font
		l.Text = "VẠN TƯỜNG 1965"
		table.insert(list, l)
	end
	for _, img in { Acabamento.VINHETA, Acabamento.LUZ, Acabamento.SOMBRA } do
		addId(list, img)
	end
	-- botões do controle (os chips de dica e os botões das telas)
	for _, kc in
		{
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.ButtonX,
			Enum.KeyCode.ButtonY,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1,
			Enum.KeyCode.ButtonL2,
			Enum.KeyCode.ButtonR2,
			Enum.KeyCode.ButtonL3,
			Enum.KeyCode.ButtonR3,
			Enum.KeyCode.ButtonSelect,
			Enum.KeyCode.DPadUp,
			Enum.KeyCode.DPadDown,
			Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight,
			Enum.KeyCode.Thumbstick1,
			Enum.KeyCode.Thumbstick2,
		}
	do
		pcall(function()
			addId(list, UserInputService:GetImageForKeyCode(kc))
		end)
	end
	-- imagens que o servidor resolveu (caveira do abate, carta tática) e as do AssetIds que já são
	-- imagens (chão, céu)
	for name, v in ReplicatedStorage:GetAttributes() do
		if string.sub(name, 1, 4) == "Img_" or string.sub(name, 1, 11) == "CartaImage_" then
			addId(list, assetId(v))
		end
	end
	local ids = sharedModule("AssetIds")
	if type(ids) == "table" then
		for _, group in { "GroundImages", "SkyImages", "CartaImages" } do
			local g = ids[group]
			if type(g) == "table" then
				for _, v in g do
					addId(list, assetId(v))
				end
			end
		end
	end
	return list
end

local function soundList(): { any }
	local list: { any } = {}
	local ids = sharedModule("AssetIds")
	local sounds = if type(ids) == "table" then ids.Sounds else nil
	if type(sounds) == "table" then
		for _, v in sounds do
			local id = assetId(v)
			if id and not seen[id] then
				seen[id] = true
				local s = Instance.new("Sound")
				s.SoundId = id
				table.insert(list, s)
			end
		end
	end
	return list
end

local function animList(): { any }
	local list: { any } = {}
	local anims = sharedModule("SoldierAnims")
	local clips = if type(anims) == "table" then anims.CLIPS else nil
	if type(clips) == "table" then
		for _, c in clips do
			local id = if type(c) == "table" then assetId(c.id) else nil
			if id and not seen[id] then
				seen[id] = true
				local a = Instance.new("Animation")
				a.AnimationId = id
				table.insert(list, a)
			end
		end
	end
	return list
end

-- ===== ENTRAR e saída =====
local allReady = false
local capped = false
local closing = false
local alive = 0 -- geração do carregamento aberto (o gancho do Studio reabre)

local function refreshKey()
	local pad = string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
	local img: string? = nil
	if pad then
		pcall(function()
			local v = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA) :: any
			if type(v) == "string" and v ~= "" then
				img = v
			end
		end)
	end
	Estilo.setGlyph(enter, img)
end
UserInputService.LastInputTypeChanged:Connect(refreshKey)

local function hover(on: boolean)
	tween(enterScale, 0.18, { Scale = if on then 1.03 else 1 })
	tween(enter.button, 0.18, { BackgroundColor3 = if on then V.OLIVE_HI else V.OLIVE })
end
enter.button.MouseEnter:Connect(function()
	hover(true)
end)
enter.button.MouseLeave:Connect(function()
	hover(false)
end)

-- tudo o que esmaece na saída, com o valor de repouso (lido uma vez, antes de aparecer o ENTRAR)
type Fade = { o: Instance, prop: string, base: number }
local fades: { Fade } = {}
local function collectFades()
	table.clear(fades)
	local function add(o: Instance, p: string)
		local v = (o :: any)[p]
		if type(v) == "number" and v < 1 then
			table.insert(fades, { o = o, prop = p, base = v })
		end
	end
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			add(d, "BackgroundTransparency")
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				add(d, "TextTransparency")
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
				add(d, "ImageTransparency")
			end
		elseif d:IsA("UIStroke") then
			add(d, "Transparency")
		end
	end
end

local exitTweens: { Tween } = {}
local function prepareExit()
	collectFades()
	table.clear(exitTweens)
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Sine, INOUT)
	for _, f in fades do
		table.insert(exitTweens, TweenService:Create(f.o, info, { [f.prop] = 1 }))
	end
	table.insert(exitTweens, TweenService:Create(stage, info, { Position = UDim2.new(0.5, 0, 0.5, -16) }))
end

local function restoreFades()
	for _, f in fades do
		(f.o :: any)[f.prop] = f.base
	end
	stage.Position = UDim2.fromScale(0.5, 0.5)
end

local function close()
	if closing or not allReady then
		return
	end
	closing = true
	Idioma.fechar()
	gui:SetAttribute("Saindo", true) -- a mesa do lobby (LobbyScene) começa o travelling de chegada agora
	if #exitTweens == 0 then
		prepareExit() -- ENTRAR apertado no instante em que apareceu (a saída ainda não estava pronta)
	end
	local my = alive
	Acabamento.pulsar(objective, false) -- a marca para de piscar (o esmaecer manda nela agora)
	for _, t in exitTweens do
		t:Play()
	end
	task.delay(0.52, function()
		if alive ~= my then
			return
		end
		alive += 1 -- para a contagem, o briefing e o carregamento que ainda corre
		setWaiting(false)
		Acabamento.apagar(axisBeach)
		Acabamento.apagar(axisLz)
		if RunService:IsStudio() then
			-- no Studio a tela fica guardada para o gancho de teste (VT65DevTela)
			gui.Enabled = false
		else
			gui:Destroy()
		end
	end)
end

local function showEnter()
	if enter.button.Visible then
		return
	end
	refreshKey()
	allReady = true
	setWaiting(false)
	setStatus(if capped then "Quase pronto: o resto termina no lobby." else "Tudo pronto.")
	tween(percent, 0.2, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
	local b = enter.button
	b.Visible = true
	b.Position = UDim2.fromOffset(RIGHT, 586)
	b.BackgroundTransparency = 1
	enter.label.TextTransparency = 1
	enter.sub.TextTransparency = 1
	tween(b, 0.32, { Position = UDim2.fromOffset(RIGHT, 566), BackgroundTransparency = 0 })
	tween(enter.label, 0.3, { TextTransparency = 0 })
	tween(enter.sub, 0.3, { TextTransparency = 0.15 })
	enter.sub.Text = string.format("%d s", AUTO_S)
	task.delay(0.35, prepareExit) -- depois da entrada do botão (o repouso dele já é o final)
	-- contagem: entra sozinha (para enquanto o cartão de idioma está aberto)
	local my = alive
	task.spawn(function()
		local left = AUTO_S
		while alive == my and not closing and left > 0 do
			task.wait(1)
			if not Idioma.aberto() then
				left -= 1
				enter.sub.Text = string.format("%d s", left)
			end
		end
		if alive == my and not closing then
			close()
		end
	end)
end

enter.button.Activated:Connect(function()
	if not Idioma.recente() then
		close()
	end
end)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if closing or not gui.Enabled or Idioma.recente() then
		return -- com o cartão de idiomas aberto, A e Enter são dele
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.ButtonY then
		openLanguage()
	elseif allReady and (kc == Enum.KeyCode.Return or kc == Enum.KeyCode.Space or kc == Enum.KeyCode.ButtonA) then
		close()
	end
end)

-- ===== entrada da tela (tweens curtos, em fila) =====
-- a carta se desenha: grade, curvas de nível, os dois eixos correndo e o objetivo piscando
local function drawMap(d0: number)
	for _, d in draws do
		d.f.Size = d.from
		TweenService
			:Create(d.f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, OUT, 0, false, d0 + d.delay), { Size = d.full })
			:Play()
	end
	Acabamento.tracar(axisBeach, 0.93, 0.6, 0.4, 0.46, 1.2, d0 + 0.9)
	Acabamento.tracar(axisLz, 0.5, 0.06, 0.38, 0.36, 0.9, d0 + 1.5)
	objective.raiz.Visible = false
	Acabamento.pulsar(objective, false)
	local my = alive
	task.delay(d0 + 2.2, function()
		if alive == my and not closing then
			objective.raiz.Visible = true
			Acabamento.pulsar(objective, true)
		end
	end)
end

-- um fato do briefing por vez: entra esmaecendo, fica ~5 s com o fio do tempo encurtando e sai
local function briefingLoop(my: number)
	task.spawn(function()
		local i = 0
		task.wait(0.8)
		while alive == my and not closing do
			i = i % #BRIEFING + 1
			local b = BRIEFING[i]
			briefIdx.Text = string.format("%d/%d", i, #BRIEFING)
			briefSrc.Text = string.format("Fonte: The First Fight (USMC, 2015), %s", b.pagina)
			briefText.Text = b.texto
			briefText.TextTransparency = 1
			tween(briefText, 0.25, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
			briefLine.Size = UDim2.fromOffset(BW - 44, 2)
			tween(briefLine, 5.4, { Size = UDim2.fromOffset(0, 2) }, Enum.EasingStyle.Linear)
			task.wait(5.4)
			if alive ~= my or closing then
				break
			end
			tween(briefText, 0.25, { TextTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			task.wait(0.28)
		end
	end)
end

local function intro()
	Estilo.enter({ titleBox, accent, subtitle, brief, stats.frame }, 16, 0.06, 0.05)
	Estilo.enter({ mapPanel }, 22, 0, 0.12)
	title.TextTransparency = 1
	tween(title, 0.35, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
	accent.Size = UDim2.fromOffset(0, 5)
	tween(accent, 0.35, { Size = UDim2.fromOffset(120, 5) }, QUINT, OUT)
	drawMap(0.3)
	briefingLoop(alive)
end

-- ===== carregamento de verdade =====
-- (a geração `alive` já foi aberta por quem chama: a entrada, o briefing e o carregamento são dela)
local function run()
	local my = alive
	local t0 = os.clock()
	-- teto de segurança: com CAP_S, o ENTRAR aparece com o que já chegou
	task.delay(CAP_S, function()
		if alive == my and not allReady then
			capped = true
			showEnter()
		end
	end)
	local artDone, artTotal = 0, 0
	local function stage1()
		setStatus("Recebendo o jogo…")
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		setFrac(1, 1)
		setStatus("Recebendo as ordens do servidor…")
		ReplicatedStorage:WaitForChild("VT65Remotes", 60)
		setFrac(2, 1)
	end
	stage1()
	if alive ~= my then
		return
	end
	-- 3. interface (a carta tática chega do servidor logo no início: espera um pouco por ela)
	setStatus("Carregando a interface…")
	local w0 = os.clock()
	while ReplicatedStorage:GetAttribute("CartaPronta") == nil and os.clock() - w0 < 6 do
		task.wait(0.2)
	end
	preload(interfaceList(), function(done: number, total: number)
		setFrac(3, if total > 0 then done / total else 1)
	end)
	setFrac(3, 1)
	-- 4. sons
	setStatus("Carregando os sons…")
	preload(soundList(), function(done: number, total: number)
		count(statSounds, done, total)
		setFrac(4, if total > 0 then done / total else 1)
	end)
	setFrac(4, 1)
	-- 5. animações
	setStatus("Carregando as animações…")
	preload(animList(), function(done: number, total: number)
		count(statAnims, done, total)
		setFrac(5, if total > 0 then done / total else 1)
	end)
	setFrac(5, 1)
	-- 6. manequins do lobby e arte das armas (o PreviewService marca Ready quando termina)
	setStatus("Montando os soldados…")
	local preview = ReplicatedStorage:WaitForChild("VT65Preview", 30)
	if preview then
		setWaiting(true)
		local p0 = os.clock()
		while preview:GetAttribute("Ready") ~= true and os.clock() - p0 < 45 and alive == my do
			task.wait(0.25)
		end
		setWaiting(false)
	end
	local soldiers: { any } = {}
	scanArt(preview, soldiers)
	scanArt(ReplicatedStorage:FindFirstChild("VT65WeaponArt"), soldiers)
	artTotal = #soldiers
	preload(soldiers, function(done: number, total: number)
		artDone = done
		count(statArt, artDone, artTotal)
		setFrac(6, if total > 0 then done / total else 1)
	end)
	setFrac(6, 1)
	-- 7. o resto da arte que já está no cliente
	setStatus("Carregando a arte do mapa…")
	local art: { any } = {}
	scanArt(ReplicatedStorage, art)
	scanArt(workspace, art)
	scanArt(Lighting, art)
	pcall(function()
		scanArt(game:GetService("MaterialService"), art)
	end)
	local before = artDone
	artTotal += #art
	preload(art, function(done: number, total: number)
		artDone = before + done
		count(statArt, artDone, artTotal)
		setFrac(7, if total > 0 then done / total else 1)
	end)
	setFrac(7, 1)
	count(statArt, artTotal, artTotal)
	-- 8. terreno (sem número: o servidor só avisa quando acaba)
	if ReplicatedStorage:GetAttribute("TerrainReady") ~= true then
		setStatus("O servidor está gerando o terreno…")
		setWaiting(true)
		while ReplicatedStorage:GetAttribute("TerrainReady") ~= true and alive == my do
			task.wait(0.25)
		end
		setWaiting(false)
	end
	setFrac(8, 1)
	if alive ~= my then
		return
	end
	-- a barra chega ao fim antes do botão (nada aparece no meio do tween)
	task.wait(math.max(0.36, 0.6 - (os.clock() - t0)))
	if alive == my and not allReady then
		showEnter()
	end
end

alive += 1
intro()
task.spawn(run)

-- ===== gancho de teste (só no Studio): a tela de volta, carregando de novo, para a foto =====
if RunService:IsStudio() then
	local function demo()
		if gui.Parent == nil or (gui.Enabled and not closing) then
			return -- ainda é a entrada de verdade
		end
		alive += 1
		closing, allReady, capped = false, false, false
		gui:SetAttribute("Saindo", nil)
		restoreFades()
		gui.Enabled = true
		enter.button.Visible = false
		percent.TextTransparency = 0
		target = 0
		prog.Value = 0
		table.clear(seen)
		for i in frac do
			frac[i] = 0
		end
		for _, st in stats.stats do
			st.value.Text = "—"
		end
		intro()
		task.spawn(run)
	end
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "carregamento" then
			demo()
		elseif gui.Parent and gui.Enabled and allReady then
			task.spawn(close)
		end
	end)
end
