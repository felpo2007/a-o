--!strict
-- Inserção sem entrar travado (pedido do dono, 2026-11-11). Ao escolher o ponto de spawn:
--   1. a tela escurece numa "ordem de inserção" (estilo novo, 2026-11-11: painel escuro, o nome do
--      ponto grande, grade, hora e lado em números, uma linha da etapa e a barra fina com o progresso
--      real; ao lado, a carta pequena com o eixo correndo do QG até o ponto, que pisca) e os
--      controles ficam parados (Input.openMenu);
--   2. o cliente pede o streaming da área do ponto (RequestStreamAroundAsync) e só DEPOIS pede o
--      spawn ao servidor (o servidor valida tudo de novo);
--   3. espera o corpo novo chegar no ponto, segura o HumanoidRootPart parado (só no cliente, dono da
--      física do próprio corpo), pede o streaming em volta dele e confere que há chão embaixo;
--   4. solta o corpo, marca "EM CAMPO" e, ainda por baixo da ordem, nivela a câmera (tween curto
--      até −3°, rumo no objetivo do time); a ordem esmaece enquanto a câmera desce do alto até o
--      lugar dela (voo de grua); só então devolve o controle.
-- Se o servidor recusar (o corpo não chega), a ordem é marcada "RECUSADA" e o lobby volta.
-- Tempos-limite são de segurança: nunca deixam o jogador preso aqui.
-- A barra é um NumberValue em tween: anda suave e nunca volta. Do Acabamento ficam só a linha de
-- avanço e a marca que pisca na carta pequena (sem película, papel nem máquina de escrever).
-- Voo de câmera sem brigar com a câmera do jogo: a câmera do Roblox, a de ombro (ThirdPerson) e o
-- resto continuam calculando a câmera "de verdade" a cada quadro; antes deles ela é devolvida
-- (prioridade Camera - 2) e, depois de todos (Last), só a imagem é deslocada para o alto. No fim do
-- voo a imagem coincide com a câmera de verdade: nada pula. Qualquer botão pula o voo.
-- Gancho de teste (só no Studio): workspace:SetAttribute("VT65DevTela", "transicao") mostra a ordem
-- (sem pedir spawn) e a segura no "EM CAMPO" para a foto; mudar o valor (ou nil) solta, com o voo
-- se houver corpo em campo.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Acabamento = require(ReplicatedFirst:WaitForChild("Acabamento"))
local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local SpawnTransition = {}
local player = Players.LocalPlayer

export type Point = { id: string, name: string, x: number, z: number }

local V, F = UiKit.V, UiKit.F
local TV = UiKit.tv()
local B = MapConfig.Bounds

local STREAM_POINT_S = 8 -- s máximos esperando a área do ponto
local BODY_S = 8 -- s esperando o corpo novo
local PLACE_S = 3 -- s esperando o corpo ir para o ponto
local GROUND_S = 4 -- s esperando o chão embaixo

local FLY_S = 1.3 -- s do voo de grua
local FLY_RISE = 18 -- studs acima da câmera de verdade no começo (~5 m)
local FLY_PITCH = math.rad(32) -- olhando mais para baixo no começo
local FLY_HANDOFF = 0.8 -- fração do voo em que o controle volta (a imagem já está a ~1 stud)

local DESIGN_W, DESIGN_H = 880, 360 -- palco da ordem (painel + carta pequena)

local function tween(
	o: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?,
	delay: number?
): Tween
	local tw = TweenService:Create(
		o,
		TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
	tw:Play()
	return tw
end

-- ===== desenho =====
local gui = Instance.new("ScreenGui")
gui.Name = "VT65Insertion"
gui.ResetOnSpawn = false
gui.DisplayOrder = 90 -- acima do lobby e dos menus, abaixo do aviso de controle desconectado
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.None
end)

-- fundo de cor única, escura (nada atrás recebe clique durante a inserção)
local bg = UiKit.backdrop(gui, V.BG_NIGHT)
bg.BackgroundTransparency = 1

-- palco da ordem: CanvasGroup (entra e sai esmaecendo inteiro), escala com a tela
local holder = Instance.new("CanvasGroup")
holder.Name = "Ordem"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
holder.BackgroundTransparency = 1
holder.GroupTransparency = 1
holder.Parent = bg
local fit = Instance.new("UIScale")
fit.Parent = holder

local function place(o: GuiObject, x: number, y: number, w: number, h: number): GuiObject
	o.Position = UDim2.fromOffset(x, y)
	o.Size = UDim2.fromOffset(w, h)
	return o
end

-- ----- a ordem: painel escuro, o ponto grande, três números, a etapa e a barra -----
local PW = 520
local card = UiKit.panel(holder, V.PANEL, 0)
card.Name = "Painel"
place(card, 0, 0, PW, DESIGN_H)
local head = UiKit.kicker(card, "ORDEM DE INSERÇÃO", 16, V.DIM)
place(head, 28, 22, PW - 200, 22)
-- etiqueta do fim ("EM CAMPO" / "RECUSADA"): entra com um pulo, no canto de cima
local done = UiKit.tag(card, "", V.OLIVE, 16)
done.AnchorPoint = Vector2.new(1, 0)
done.Position = UDim2.new(1, -24, 0, 20)
done.Size = UDim2.fromOffset(0, UiKit.px(28, 38))
done.Visible = false
done.ZIndex = 3
local doneHit = Instance.new("UIScale")
doneHit.Parent = done
local pointName = UiKit.title(card, "", 40, V.TEXT)
place(pointName, 26, 48, PW - 52, 54)
local numbers = UiKit.statRow(card, { { "GRADE", "—" }, { "HORA", "—" }, { "LADO", "—" } }, 26)
numbers.frame.Position = UDim2.fromOffset(28, 112)
local gridValue, clockValue, sideValue = numbers.stats[1].value, numbers.stats[2].value, numbers.stats[3].value
local stageText = UiKit.body(card, "", 16, V.TEXT)
place(stageText, 28, 214, PW - 150, 24)
stageText.TextWrapped = false
stageText.TextTruncate = Enum.TextTruncate.AtEnd
stageText.TextYAlignment = Enum.TextYAlignment.Center
local percent = UiKit.title(card, "0%", 26, V.TEXT)
place(percent, PW - 140, 208, 112, 34)
percent.TextXAlignment = Enum.TextXAlignment.Right
local barBack, barFill = UiKit.bar(card, 6, V.OLIVE_HI)
place(barBack, 28, 250, PW - 56, 6)
local note = UiKit.body(card, "Na chegada, qualquer botão pula a descida da câmera.", 13, V.MUTED)
place(note, 28, DESIGN_H - 48, PW - 56, if TV then 26 else 20)
note.TextWrapped = false
note.TextTruncate = Enum.TextTruncate.AtEnd

-- ----- carta pequena com o ponto -----
local MAP = DESIGN_H
local map = UiKit.panel(holder, V.PANEL_2, 0)
map.Name = "Carta"
place(map, DESIGN_W - MAP, 0, MAP, MAP)
map.ClipsDescendants = true
-- setores da carta (faixas alternadas, escuras)
for i, s in MapConfig.Sectors do
	local x0, x1 = math.huge, -math.huge
	for k = 1, #s.polygon, 2 do
		x0 = math.min(x0, s.polygon[k])
		x1 = math.max(x1, s.polygon[k])
	end
	local u0 = (x0 - B.minX) / (B.maxX - B.minX)
	local u1 = (x1 - B.minX) / (B.maxX - B.minX)
	local band = Instance.new("Frame")
	band.BorderSizePixel = 0
	band.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(44, 52, 36) else Color3.fromRGB(36, 42, 30)
	band.Position = UDim2.fromScale(math.clamp(u0, 0, 1), 0)
	band.Size = UDim2.fromScale(math.clamp(u1 - u0, 0, 1), 1)
	band.Parent = map
end
local gridLines: { { f: Frame, full: UDim2, from: UDim2 } } = {}
for i = 1, 7 do
	for _, vertical in { true, false } do
		local l = Instance.new("Frame")
		l.BorderSizePixel = 0
		l.BackgroundColor3 = V.LINE
		l.BackgroundTransparency = 0.45
		l.Position = if vertical then UDim2.fromScale(i / 8, 0) else UDim2.fromScale(0, i / 8)
		l.ZIndex = 2
		l.Parent = map
		table.insert(gridLines, {
			f = l,
			full = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1),
			from = if vertical then UDim2.new(0, 1, 0, 0) else UDim2.new(0, 0, 0, 1),
		})
	end
end
-- QG do lado (quadrado na cor do lado) e o eixo do QG até o ponto
local hqMark = Instance.new("Frame")
hqMark.AnchorPoint = Vector2.new(0.5, 0.5)
hqMark.Size = UDim2.fromOffset(16, 12)
hqMark.BorderSizePixel = 0
hqMark.ZIndex = 4
hqMark.Visible = false
hqMark.Parent = map
UiKit.corner(hqMark, 2)
UiKit.stroke(hqMark, V.BG, 1.5)
local axis = Acabamento.linha(map, V.KHAKI, 3, 14, 5)
local marker = Acabamento.marca(map, V.BRASS, 20, 6)
marker.raiz.Visible = false
local STRIP = if TV then 32 else 26
local mapStrip = Instance.new("Frame")
mapStrip.BackgroundColor3 = V.PANEL
mapStrip.BackgroundTransparency = 0.1
mapStrip.BorderSizePixel = 0
mapStrip.Position = UDim2.new(0, 0, 1, -STRIP)
mapStrip.Size = UDim2.new(1, 0, 0, STRIP)
mapStrip.ZIndex = 7
mapStrip.Parent = map
local mapName = UiKit.kicker(mapStrip, "", 14, V.TEXT)
mapName.Position = UDim2.fromOffset(10, 0)
mapName.Size = UDim2.new(1, -20, 1, 0)
mapName.ZIndex = 7

task.spawn(function()
	gui.Parent = player:WaitForChild("PlayerGui")
end)

-- escala do palco: só quando a janela muda (nada por quadro)
local function refit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	local k = math.min(s.X / (DESIGN_W + 40), s.Y / (DESIGN_H + 80))
	if TV then
		k = math.max(k * 0.92, 1) -- margem de segurança da TV
	end
	fit.Scale = math.clamp(k, 0.5, 2.4)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
refit()

-- ===== estado =====
local busy = false
local showToken = 0
local prog = Instance.new("NumberValue")
local target = 0
prog.Changed:Connect(function(v: number)
	local x = math.clamp(v, 0, 1)
	barFill.Size = UDim2.fromScale(x, 1)
	percent.Text = string.format("%d%%", math.floor(x * 100 + 0.5))
end)

local function gridRef(x: number, z: number): string
	local g = MapConfig.GridOrigin1965
	local e = g.e + x * MapConfig.STUD_M
	local n = g.n - z * MapConfig.STUD_M
	return string.format("BS %03d%03d", math.floor((e % 100000) / 100), math.floor((n % 100000) / 100))
end

local function clock(): string
	local c = Lighting.ClockTime
	return string.format("%02d%02d", math.floor(c) % 24, math.floor((c % 1) * 60))
end

local function uv(x: number, z: number): (number, number)
	return math.clamp((x - B.minX) / (B.maxX - B.minX), 0, 1), math.clamp((z - B.minZ) / (B.maxZ - B.minZ), 0, 1)
end

-- a barra só anda para a frente (alvo novo menor que o atual é ignorado)
local function setTarget(p: number)
	if p <= target then
		return
	end
	target = p
	tween(prog, 0.5, { Value = p }, Enum.EasingStyle.Quad)
end

-- a etapa entra deslizando um pouco (sem máquina de escrever)
local function setStage(text: string, p: number)
	stageText.Text = Acabamento.viet(text)
	stageText.TextTransparency = 1
	stageText.Position = UDim2.fromOffset(36, 214)
	tween(stageText, 0.25, { TextTransparency = 0, Position = UDim2.fromOffset(28, 214) })
	setTarget(p)
end

-- etiqueta do fim: "EM CAMPO" (oliva) ou "RECUSADA" (vermelho), com um pulo curto
local function stampDone(text: string, color: Color3)
	done.Text = text
	done.FontFace = UiKit.Estilo.headFont(text, F.TITLE_MED)
	done.BackgroundColor3 = color
	done.Visible = true
	done.TextTransparency = 1
	done.BackgroundTransparency = 1
	doneHit.Scale = 1.25
	tween(doneHit, 0.24, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(done, 0.18, { TextTransparency = 0, BackgroundTransparency = 0 }, Enum.EasingStyle.Quad)
end

local function show(pt: Point)
	showToken += 1
	local u, v = uv(pt.x, pt.z)
	marker.raiz.Position = UDim2.fromScale(u, v)
	marker.raiz.Visible = false
	Acabamento.pulsar(marker, false)
	local grid = gridRef(pt.x, pt.z)
	mapName.Text = grid
	target = 0
	prog.Value = 0
	done.Visible = false
	stageText.Text = ""
	gui.Enabled = true
	refit()
	-- entra: o fundo escurece e a ordem sobe esmaecendo
	tween(bg, 0.3, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
	holder.Position = UDim2.new(0.5, 0, 0.5, 20)
	holder.GroupTransparency = 1
	tween(
		holder,
		0.35,
		{ Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 0 },
		Enum.EasingStyle.Quint,
		nil,
		0.06
	)
	-- a grade se desenha, o eixo corre do QG até o ponto e o ponto pisca
	for i, gl in gridLines do
		gl.f.Size = gl.from
		tween(gl.f, 0.45, { Size = gl.full }, Enum.EasingStyle.Quad, nil, 0.08 + i * 0.012)
	end
	local f = player:GetAttribute("Faction")
	local hq = if type(f) == "string" then MapConfig.HQ[f] else nil
	local my = showToken
	if hq then
		local hu, hv = uv(hq.x, hq.z)
		hqMark.Position = UDim2.fromScale(hu, hv)
		hqMark.BackgroundColor3 = if f == "VC" then V.VC else V.US
		hqMark.Visible = true
		Acabamento.tracar(axis, hu, hv, u, v, 0.9, 0.35)
	else
		hqMark.Visible = false
		Acabamento.apagar(axis)
	end
	task.delay(if hq then 1.25 else 0.5, function()
		if showToken == my and gui.Enabled then
			marker.raiz.Visible = true
			Acabamento.pulsar(marker, true)
		end
	end)
	-- o ponto grande e os três números (grade, hora, lado)
	pointName.Text = Acabamento.viet(UiKit.upper(pt.name))
	pointName.RichText = true
	pointName.FontFace = UiKit.headFont(pt.name)
	gridValue.Text = grid
	clockValue.Text = clock()
	sideValue.Text = if f == "US" then "EUA" elseif f == "VC" then "VC" else "?"
	UiKit.enter({ pointName :: GuiObject, numbers.frame }, 10, 0.06, 0.12)
end

-- some esmaecendo (o fundo e a ordem); `after` em s
local function hide(after: number)
	local my = showToken
	task.delay(after, function()
		if showToken ~= my then
			return -- outra ordem já abriu por cima
		end
		tween(
			holder,
			0.35,
			{ Position = UDim2.new(0.5, 0, 0.5, -14), GroupTransparency = 1 },
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.In
		)
		tween(bg, 0.5, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.delay(0.52, function()
			if showToken == my and not busy then
				Acabamento.pulsar(marker, false)
				Acabamento.apagar(axis)
				gui.Enabled = false
			end
		end)
	end)
end

-- ===== voo de grua (câmera) =====
local flight = { on = false, t = 0, real = nil :: CFrame?, skip = false }

-- curva sem tranco: começa e termina com velocidade e aceleração zero (smootherstep)
local function smooth(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function stopFlight()
	if not flight.on then
		return
	end
	flight.on = false
	flight.real = nil
	RunService:UnbindFromRenderStep("VT65InsertPre")
	RunService:UnbindFromRenderStep("VT65InsertPost")
end

-- Começa o voo (devolve false se a câmera não é a do jogo: aí não há voo).
local function startFlight(): boolean
	local cam = workspace.CurrentCamera
	if flight.on or not cam or cam.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	flight.on, flight.t, flight.real, flight.skip = true, 0, nil, false
	-- antes da câmera do Roblox: devolve a câmera de verdade do quadro anterior (ela calcula como se
	-- não houvesse voo)
	RunService:BindToRenderStep("VT65InsertPre", Enum.RenderPriority.Camera.Value - 2, function()
		local c = workspace.CurrentCamera
		local real = flight.real
		if c and real then
			c.CFrame = real
		end
	end)
	-- depois de todos: guarda a câmera de verdade e mostra a imagem do alto, descendo até ela
	RunService:BindToRenderStep("VT65InsertPost", Enum.RenderPriority.Last.Value, function(dt: number)
		local c = workspace.CurrentCamera
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not c or c.CameraType ~= Enum.CameraType.Custom or not hum or hum.Health <= 0 then
			stopFlight()
			return
		end
		local real = c.CFrame
		flight.real = real
		flight.t = if flight.skip then 1 else math.min(flight.t + dt / FLY_S, 1)
		local k = 1 - smooth(flight.t)
		-- a imagem nunca passa de −80° (com a câmera de verdade ainda inclinada, −77° − 32° virava a
		-- imagem de cabeça para baixo)
		local realPitch = real:ToOrientation()
		local extra = math.min(FLY_PITCH * k, math.max(0, realPitch + math.rad(80)))
		c.CFrame = CFrame.new(real.Position + Vector3.yAxis * (FLY_RISE * k))
			* real.Rotation
			* CFrame.Angles(-extra, 0, 0)
		if flight.t >= 1 then
			stopFlight() -- este quadro já é a câmera de verdade: nada pula
		end
	end)
	return true
end

-- qualquer botão (teclado, mouse, controle, toque) pula o voo
UserInputService.InputBegan:Connect(function(input: InputObject)
	if not flight.on then
		return
	end
	local t = input.UserInputType
	if
		t ~= Enum.UserInputType.MouseMovement
		and t ~= Enum.UserInputType.MouseWheel
		and t ~= Enum.UserInputType.Focus
	then
		if not (t == Enum.UserInputType.Gamepad1 and input.KeyCode.Name:sub(1, 5) == "Thumb") then
			flight.skip = true
		end
	end
end)

-- ===== câmera nivelada na chegada =====
-- Studio (D-93): depois da inserção a câmera chegava olhando quase reto para o chão (LookVector.Y
-- = −0,97, −77°) e o capim enchia a tela. A câmera do jogo herda a direção que tinha (a vista da
-- mesa do lobby olha para baixo) e o módulo do Roblox e o CameraLook mantêm o pitch que recebem.
-- Na chegada, com a ordem ainda cobrindo a tela, a câmera de verdade vai num tween curto até o
-- nível (LEVEL_PITCH), com o rumo no objetivo do time (sem objetivo: a frente do corpo). Roda
-- ANTES do módulo de câmera (que lê a direção atual a cada quadro: o nível persiste) e depois do
-- VT65InsertPre (que devolve a câmera de verdade). A inclinação lateral (roll) do Movement é
-- preservada: ele a desfaz no começo de cada quadro.
local LEVEL_S = 0.35 -- s do tween de nível
local LEVEL_PITCH = math.rad(-3) -- olhando o horizonte (entre −5° e 0°)
local LEVEL_WAIT_S = 3 -- s no máximo esperando a câmera do jogo (Custom)
local level = { on = false, t = 0, p0 = 0, y0 = 0, dy = 0, started = false, token = 0 }
local matchState: any = nil
task.spawn(function()
	Net.event("Match_State").OnClientEvent:Connect(function(st: any)
		if type(st) == "table" then
			matchState = st
		end
	end)
end)

-- rumo (yaw) para o objetivo do time; sem objetivo, a frente do HumanoidRootPart
local function levelYaw(root: BasePart?, fallback: number): number
	local st = matchState
	local f = player:GetAttribute("Faction")
	if root and type(st) == "table" and type(f) == "string" and type(st.owner) == "table" then
		local cap: { [number]: string } = {}
		if type(st.capturing) == "table" then
			for i, v in st.capturing do
				if type(v) == "string" and v ~= "" then
					cap[i] = v
				end
			end
		end
		local ok, _, target = pcall(Front.objective, st.owner, st.active or {}, f, cap)
		local p = if ok and target and type(st.points) == "table" then st.points[target] else nil
		if type(p) == "table" and type(p.x) == "number" and type(p.z) == "number" then
			local dx, dz = p.x - root.Position.X, p.z - root.Position.Z
			if dx * dx + dz * dz > 1 then
				return math.atan2(-dx, -dz)
			end
		end
	end
	if root then
		local lv = root.CFrame.LookVector
		if lv.X * lv.X + lv.Z * lv.Z > 1e-4 then
			return math.atan2(-lv.X, -lv.Z)
		end
	end
	return fallback
end

local function stopLevel()
	if level.on then
		level.on = false
		RunService:UnbindFromRenderStep("VT65InsertLevel")
	end
end

-- Nivela a câmera do jogo (todo caminho que termina em campo chama: inserção, renascer onde caiu,
-- gancho de teste). Espera a câmera virar a do jogo (o lobby a deixa Scriptable) até LEVEL_WAIT_S.
local function levelCamera()
	stopLevel()
	level.token += 1
	local my = level.token
	level.on, level.t, level.started = true, 0, false
	local since = os.clock()
	RunService:BindToRenderStep("VT65InsertLevel", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
		local c = workspace.CurrentCamera
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if level.token ~= my then
			return
		end
		if not c or c.CameraType ~= Enum.CameraType.Custom or not hum or hum.Health <= 0 then
			if os.clock() - since > LEVEL_WAIT_S then
				stopLevel()
			end
			return -- ainda não é a câmera do jogo: espera sem andar o relógio
		end
		local cf = c.CFrame
		local pitch, yaw, roll = cf:ToOrientation()
		if not level.started then
			level.started = true
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local yT = levelYaw(if root and root:IsA("BasePart") then root else nil, yaw)
			level.p0, level.y0 = pitch, yaw
			level.dy = (yT - yaw + math.pi) % (2 * math.pi) - math.pi -- o caminho mais curto
		end
		level.t = math.min(level.t + dt / LEVEL_S, 1)
		local e = smooth(level.t)
		c.CFrame = CFrame.new(cf.Position)
			* CFrame.fromOrientation(level.p0 + (LEVEL_PITCH - level.p0) * e, level.y0 + level.dy * e, roll)
		if level.t >= 1 then
			stopLevel()
		end
	end)
end

-- espera o nível terminar (ou desistir); no máximo LEVEL_S + LEVEL_WAIT_S
local function waitLevel()
	local t0 = os.clock()
	while level.on and os.clock() - t0 < LEVEL_S + LEVEL_WAIT_S do
		task.wait()
	end
end

-- espera o voo chegar à fração `frac` (ou acabar); no máximo FLY_S + 1 s
local function waitFlight(frac: number)
	local t0 = os.clock()
	while flight.on and flight.t < frac and os.clock() - t0 < FLY_S + 1 do
		task.wait()
	end
end

-- nivela por baixo da ordem (ainda opaca, 0,5 s com o carimbo) antes de o voo começar: o voo já
-- desce para uma câmera nivelada. Se a câmera do jogo ainda não chegou, o nível fica para quando
-- ela chegar (tween do mesmo jeito, nunca salto).
local function settleCamera()
	levelCamera()
	task.wait(0.5)
	if level.on and level.started then
		waitLevel()
	end
end

-- O fim de toda ordem que deu certo: carimbo, a ordem esmaece com a câmera descendo, controle volta.
local function arrive()
	stampDone("EM CAMPO", V.OLIVE)
	settleCamera()
	busy = false
	local flying = startFlight()
	hide(0)
	if flying then
		waitFlight(FLY_HANDOFF)
	else
		task.wait(0.45)
	end
	Input.closeMenu()
end

-- ===== etapas =====
local function streamAround(pos: Vector3, timeout: number)
	pcall(function()
		player:RequestStreamAroundAsync(pos, timeout)
	end)
end

local function newBody(old: Model?, timeout: number): (Model?, BasePart?)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local c = player.Character
		if c and c ~= old then
			local hum = c:FindFirstChildOfClass("Humanoid")
			local root = c:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				return c, root
			end
		end
		task.wait(0.1)
	end
	return nil, nil
end

local function groundUnder(root: BasePart, char: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	return workspace:Raycast(root.Position, Vector3.new(0, -60, 0), params) ~= nil
end

function SpawnTransition.busy(): boolean
	return busy
end

-- Começa a inserção no ponto; `fire` pede o spawn ao servidor. Devolve false se já há uma em curso.
function SpawnTransition.go(pt: Point, fire: () -> ()): boolean
	if busy then
		return false
	end
	busy = true
	Input.openMenu() -- personagem parado até a área chegar
	show(pt)
	task.spawn(function()
		local old = player.Character
		-- 1. área do ponto (o chão ainda nem existe no cliente)
		setStage("Recebendo a área de inserção…", 0.08)
		task.spawn(function()
			-- a barra anda enquanto o streaming responde (sem número inventado: o fim vem do Roblox)
			local t0 = os.clock()
			while busy and target < 0.55 and os.clock() - t0 < STREAM_POINT_S do
				setTarget(0.08 + 0.45 * (1 - math.exp(-(os.clock() - t0))))
				task.wait(0.15)
			end
		end)
		streamAround(Vector3.new(pt.x, 30, pt.z), STREAM_POINT_S)
		setStage("Área recebida. Pedindo a inserção ao comando…", 0.6)
		-- 2. pede o spawn e espera o corpo novo
		fire()
		local char, root = newBody(old, BODY_S)
		if not (char and root) then
			setStage("Inserção recusada pelo comando (o ponto mudou?). Escolha outro.", 0.6)
			stampDone("RECUSADA", V.RED)
			busy = false
			hide(1.6)
			Input.closeMenu()
			return
		end
		-- 3. o servidor leva o corpo ao ponto; segura-o parado enquanto o chão chega
		setStage("Desembarcando…", 0.72)
		local t0 = os.clock()
		while os.clock() - t0 < PLACE_S do
			local d = Vector2.new(root.Position.X - pt.x, root.Position.Z - pt.z).Magnitude
			if d < 80 then
				break
			end
			task.wait(0.05)
		end
		local held = false
		if root.Parent and not root.Anchored then
			root.Anchored = true
			held = true
		end
		setStage("Firmando o terreno sob os pés…", 0.82)
		streamAround(root.Position, GROUND_S)
		t0 = os.clock()
		while os.clock() - t0 < GROUND_S and root.Parent and not groundUnder(root, char) do
			task.wait(0.1)
		end
		if held and root.Parent then
			root.Anchored = false
		end
		-- 4. pronto
		setStage("Em posição.", 1)
		arrive()
	end)
	return true
end

-- ===== gancho de teste (só no Studio): a ordem na tela para a foto =====
if RunService:IsStudio() then
	local demoOn = false
	local function demo()
		if busy or demoOn then
			return
		end
		demoOn = true
		busy = true
		Input.openMenu()
		-- ponto de exemplo: o primeiro ponto forte real da carta (ou o meio dela)
		local pt: Point =
			{ id = "demo", name = "Centro da carta", x = (B.minX + B.maxX) / 2, z = (B.minZ + B.maxZ) / 2 }
		for _, sp in MapConfig.Strongpoints do
			if sp.real then
				pt = { id = "demo", name = sp.name, x = sp.x, z = sp.z }
				break
			end
		end
		show(pt)
		task.spawn(function()
			setStage("Recebendo a área de inserção…", 0.08)
			for k = 1, 6 do
				task.wait(0.2)
				setTarget(0.08 + 0.45 * (1 - math.exp(-k * 0.2)))
			end
			setStage("Área recebida. Pedindo a inserção ao comando…", 0.6)
			task.wait(0.9)
			setStage("Desembarcando…", 0.72)
			task.wait(0.7)
			setStage("Firmando o terreno sob os pés…", 0.82)
			task.wait(0.8)
			setStage("Em posição.", 1)
			stampDone("EM CAMPO", V.OLIVE)
			-- segura para a foto até o atributo mudar
			while workspace:GetAttribute("VT65DevTela") == "transicao" do
				task.wait(0.2)
			end
			settleCamera()
			busy = false
			local flying = startFlight()
			hide(0)
			if flying then
				waitFlight(FLY_HANDOFF)
			end
			Input.closeMenu()
			demoOn = false
		end)
	end
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "transicao" then
			demo()
		end
	end)
end

return SpawnTransition
