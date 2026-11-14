--!strict
-- HUD da frente, avisos de setor e tela de fim de partida (pedido do dono, 2026-11-11: "não fica
-- claro o que está em disputa", "fim de partida claro, com placar").
--   - faixa no alto, ao centro (acima dos avisos do Toast): modo e relógio, os 5 setores com o dono
--     (cor fixa por lado, 2026-11-12: azul = EUA, vermelho = VC, cáqui = neutro; "nosso" é o ponto
--     branco no canto), quem está tomando (▲ nós, ▼ eles), a
--     disputa (⚔) e o progresso; reforços (Warfare) ou a frente (Offensive); e o objetivo do time
--     com rumo e distância ("ATACAR · S3 Cemitério · ~420 m a noroeste"). Some com a carta e os menus;
--   - captura: no setor em que estou tomando ou disputando, um painel abaixo do meio da tela com o
--     estado, a barra do progresso e quantos aliados e inimigos há na área (Match_State.inArea);
--   - avisos pelo Toast: setor sob ataque, em disputa, tomado, perdido, neutralizado, frente que
--     anda, reforços baixos e 5 minutos;
--   - fim: tela cheia de cor única com VITÓRIA / DERROTA / EMPATE enorme, o motivo e os números
--     (setores, reforços, baixas, duração; USMC x VC) sobre o relatório pós-ação; some sozinha em
--     9 s, com o botão do relatório, A, Enter, clique ou o voltar.
-- Nada aqui mostra inimigo: só o estado dos pontos (Parte 9.5). Studio: o VT65DevEnd do servidor
-- encerra a partida e mostra a tela de fim; workspace:SetAttribute("VT65DevTela", "fim") só a mostra.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Casualty = require(ReplicatedStorage.Shared.Casualty)
local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local TV = UiKit.tv()
local function px(pc: number, tv: number): number
	return if TV then tv else pc
end

local V = UiKit.V
local C = {
	card = V.PANEL, -- estilo novo: o mesmo painel escuro das telas
	nosso = Color3.fromRGB(70, 104, 170),
	inimigo = Color3.fromRGB(176, 58, 44),
	neutro = Color3.fromRGB(150, 140, 106),
	khaki = UiKit.KHAKI,
	brass = UiKit.BRASS,
}

local hud = UiKit.screen("VT65Frente", 14)
local stripFit: UiKit.Fit? = nil
local strip = Instance.new("Frame")
strip.Name = "Faixa"
strip.AnchorPoint = Vector2.new(0.5, 0)
strip.Position = UDim2.new(0.5, 0, 0, px(6, 8))
strip.Size = UDim2.fromOffset(px(560, 820), px(52, 62))
strip.BackgroundColor3 = C.card
strip.BackgroundTransparency = 0.12
strip.BorderSizePixel = 0
strip.Visible = false
strip.Parent = hud
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = strip
	local s = Instance.new("UIStroke")
	s.Color = V.LINE
	s.Transparency = 0.45
	s.Parent = strip
	-- janela estreita: a faixa encolhe inteira (nada passa da borda)
	stripFit = UiKit.fit(hud, strip, strip.Size.X.Offset, 1, 8)
end

-- Toque (Parte 13): os cantos de cima são dos botões do HUD de toque (mapa, menu, câmera... e
-- comunicar, marcar, rádio). A faixa vai para o vão entre eles (ToqueUi.topBand), encolhendo para
-- caber; a bússola e o cartão da arma (HudCampo) descem logo abaixo dela.
local function placeStripTouch()
	local scale = strip:FindFirstChildOfClass("UIScale")
	-- v41 (pedido do dono, foto do celular: "coloque isso mais para cima como era antes"): no toque a
	-- faixa sobe para a linha da barra do Roblox, no vão livre à direita dos botões dele
	-- (GuiService.TopbarInset), centrada na tela quando cabe. A bússola sobe para o alto da área do
	-- HUD (zona "bussola"). Sem a barra (Studio antigo, inset vazio), fica a zona "topo" da v39.
	if ToqueUi.active() then
		local ok, tb = pcall(function(): Rect
			return GuiService.TopbarInset
		end)
		local cam = workspace.CurrentCamera
		if ok and tb and cam and tb.Width > 160 then
			local vp = cam.ViewportSize
			local w0 = strip.Size.X.Offset
			local k = ToqueTelas.fitScale(w0, math.min(tb.Width - 12, vp.X * 0.5), 1, 0.4)
			if scale then
				scale.Scale = k
			end
			local half = w0 * k / 2
			local cx = math.clamp(vp.X / 2, tb.Min.X + half + 6, math.max(tb.Max.X - half - 6, tb.Min.X + half + 6))
			strip.AnchorPoint = Vector2.new(0.5, 0)
			strip.Position = UDim2.fromOffset(cx - hud.AbsolutePosition.X, tb.Min.Y + 2 - hud.AbsolutePosition.Y)
			return
		end
	end
	-- v39: a zona livre "topo" do HUD de toque (Shared/Toque.ZONES), no alto entre o mapa/menu e o
	-- COMUNICAR; a bússola desce logo abaixo (zona "bussola", HudCampo)
	if ToqueUi.fitZone(strip, scale, "topo", strip.Size.X.Offset, strip.Size.Y.Offset, Vector2.new(0.5, 0), 1, 0.4) then
		return
	end
	if ToqueUi.active() then
		local x0, x1 = ToqueUi.topBand()
		local k = ToqueTelas.fitScale(strip.Size.X.Offset, x1 - x0 - 12, 1, 0.4)
		if scale then
			scale.Scale = k
		end
		strip.Position = UDim2.fromOffset((x0 + x1) / 2 - hud.AbsolutePosition.X, px(6, 8))
	elseif strip.Position.X.Scale ~= 0.5 then
		strip.Position = UDim2.new(0.5, 0, 0, px(6, 8))
		if scale and stripFit then
			scale.Scale = stripFit.k()
		end
	end
end

local function text(parent: Instance, size: number, color: Color3, head: boolean?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.TextColor3 = color
	t.TextSize = size
	if head then
		t.FontFace = UiKit.HEAD_FONT
	else
		t.Font = UiKit.BODY_FONT
	end
	t.Parent = parent
	return t
end

local ROW1 = px(30, 36)
local clockMode = text(strip, px(11, 18), C.khaki, true)
clockMode.Position = UDim2.fromOffset(10, 3)
clockMode.Size = UDim2.fromOffset(px(80, 120), px(12, 18))
clockMode.TextXAlignment = Enum.TextXAlignment.Left
local clock = text(strip, px(18, 26), Color3.fromRGB(236, 228, 204), true)
clock.Position = UDim2.fromOffset(10, px(13, 18))
clock.Size = UDim2.fromOffset(px(80, 120), px(18, 22))
clock.TextXAlignment = Enum.TextXAlignment.Left
local scoreText = text(strip, px(13, 22), C.khaki, true)
scoreText.AnchorPoint = Vector2.new(1, 0)
scoreText.Position = UDim2.new(1, -10, 0, 4)
scoreText.Size = UDim2.fromOffset(px(120, 190), ROW1 - 4)
scoreText.TextXAlignment = Enum.TextXAlignment.Right
scoreText.RichText = true
local objective = text(strip, px(13, 22), Color3.fromRGB(236, 228, 204))
objective.AnchorPoint = Vector2.new(0.5, 1)
objective.Position = UDim2.new(0.5, 0, 1, -3)
objective.Size = UDim2.new(1, -20, 0, px(16, 24))
objective.RichText = true

-- os 5 setores
local CHIP_W, CHIP_H = px(46, 70), px(24, 30)
local chips: { any } = {}
do
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 4)
	-- D-123: um chip por setor do mapa (3 no mapa de 700 m)
	local nS = #MapConfig.Sectors
	row.Size = UDim2.fromOffset(nS * CHIP_W + (nS - 1) * 4, CHIP_H)
	row.Parent = strip
	for i = 1, nS do
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset((i - 1) * (CHIP_W + 4), 0)
		f.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
		f.BackgroundColor3 = C.neutro
		f.BorderSizePixel = 0
		f.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 3)
		c.Parent = f
		local st = Instance.new("UIStroke")
		st.Color = C.brass
		st.Thickness = 2
		st.Transparency = 1
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = f
		local name = text(f, px(13, 20), Color3.fromRGB(246, 240, 222), true)
		name.Size = UDim2.new(1, 0, 1, -4)
		name.Text = Front.letra(i)
		name.TextStrokeTransparency = 0.6
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, 2, 1, -2)
		bar.Size = UDim2.new(1, -4, 0, px(3, 4))
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 0.5
		bar.BorderSizePixel = 0
		bar.Parent = f
		local fill = Instance.new("Frame")
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar
		local mark = text(f, px(12, 18), Color3.new(1, 1, 1), true)
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -2, 0, -1)
		mark.Size = UDim2.fromOffset(14, 14)
		mark.TextStrokeTransparency = 0.3
		-- "nosso" por ícone (a cor é do lado: azul EUA, vermelho VC, para os dois times)
		local own = text(f, px(9, 14), Color3.new(1, 1, 1), true)
		own.Position = UDim2.fromOffset(2, 0)
		own.Size = UDim2.fromOffset(px(10, 14), px(10, 14))
		own.Text = "●"
		own.TextStrokeTransparency = 0.4
		own.Visible = false
		-- "você está aqui": filete claro em cima do setor em que estou capturando ou disputando
		local here = Instance.new("Frame")
		here.Name = "Aqui"
		here.AnchorPoint = Vector2.new(0.5, 1)
		here.Position = UDim2.new(0.5, 0, 0, -2)
		here.Size = UDim2.new(1, 4, 0, px(3, 4))
		here.BackgroundColor3 = V.TEXT
		here.BorderSizePixel = 0
		here.Visible = false
		here.Parent = f
		chips[i] = { frame = f, stroke = st, name = name, fill = fill, mark = mark, own = own, here = here }
	end
end

local state: any = nil
local prev: any = nil
local cooldown: { [string]: number } = {}
local once: { [string]: boolean } = {}

local function mine(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

local function enemyOf(f: string?): string
	return if f == "US" then "VC" else "US"
end

-- cor fixa por lado (pedido do dono, 2026-11-12): VC sempre vermelho e EUA sempre azul, para os dois
-- times; "nosso" vai por ícone ou texto, nunca pela cor
local function rel(owner: string?): Color3
	if owner == "US" then
		return V.US
	elseif owner == "VC" then
		return V.VC
	end
	return C.neutro
end

local function sectorName(st: any, s: number): string
	local p = st.points and st.points[s]
	return if p then string.format("%s %s", Front.letra(s), p.name) else Front.letra(s)
end

local function throttle(key: string, seconds: number): boolean
	local now = os.clock()
	if (cooldown[key] or -math.huge) + seconds > now then
		return false
	end
	cooldown[key] = now
	return true
end

-- ===== avisos a partir da diferença entre dois estados =====
local function alerts(st: any, old: any)
	local f = mine()
	if not f or st.ended or not old or old.ended or old.mode ~= st.mode then
		return
	end
	local e = enemyOf(f)
	for s = 1, #st.owner do
		local was, now = old.owner[s], st.owner[s]
		local name = sectorName(st, s)
		if was ~= now then
			-- cada aviso é um modelo inteiro (o nome do setor entra no %s; o dicionário traduz o modelo)
			if now == f then
				Toast.show(string.format("%s é nosso", name), "sucesso", { title = "Setor tomado" })
			elseif now == e then
				Toast.show(string.format("%s caiu nas mãos do inimigo", name), "erro", { title = "Setor perdido" })
			elseif was == f then
				Toast.show(
					string.format("%s foi neutralizado: retome o ponto", name),
					"alerta",
					{ title = "Setor neutralizado" }
				)
			else
				Toast.show(
					string.format("%s neutralizado: continue até tomar", name),
					"info",
					{ title = "Setor neutralizado" }
				)
			end
		elseif st.active[s] then
			local cap, oldCap = st.capturing and st.capturing[s], old.capturing and old.capturing[s]
			local con, oldCon = st.contested and st.contested[s], old.contested and old.contested[s]
			if con and not oldCon and throttle("disputa" .. s, 45) then
				Toast.show(
					string.format("%s: os dois lados no ponto, a captura parou", name),
					"alerta",
					{ title = "Em disputa" }
				)
			elseif cap == e and oldCap ~= e and now == f and throttle("ataque" .. s, 45) then
				Toast.show(
					string.format("%s sob ataque", name),
					"alerta",
					{ title = "Setor sob ataque", key = "ataque" .. s }
				)
			elseif cap == f and oldCap ~= f and now ~= f and throttle("tomando" .. s, 60) then
				Toast.show(string.format("Tomando %s", name), "info", { title = "Captura" })
			end
		end
	end
	if st.mode == "Offensive" and st.front ~= old.front and type(st.front) == "number" and st.front >= 1 then
		Toast.show(
			string.format("A frente passa para %s (+15 min no relógio)", sectorName(st, st.front)),
			if f == "US" then "sucesso" else "alerta",
			{ title = "Frente" }
		)
	end
	if st.score and st.score.max then
		for _, side in { f, e } do
			local key = "reforcos" .. side
			if not once[key] and (st.score[side] or 0) <= st.score.max * 0.25 then
				once[key] = true
				Toast.show(
					if side == f then "Nossos reforços estão em 25%" else "Reforços do inimigo em 25%",
					if side == f then "alerta" else "info",
					{ title = "Reforços" }
				)
			end
		end
	end
	if not once.cinco and (st.timeLeft or 9999) <= 300 and (old.timeLeft or 0) > 300 then
		once.cinco = true
		Toast.show("Faltam 5 minutos", "alerta", { title = "Relógio" })
	end
end

-- ===== faixa =====
local function render(st: any)
	local f = mine()
	local t = math.max(0, math.floor(st.timeLeft or 0))
	clockMode.Text = UiKit.upper(st.mode or "")
	clock.Text = string.format("%02d:%02d", t // 60, t % 60)
	clock.TextColor3 = if t <= 300 and not st.ended then Color3.fromRGB(244, 184, 96) else Color3.fromRGB(236, 228, 204)
	local role, target = nil, nil
	if f then
		role, target = Front.objective(st.owner, st.active, f, st.capturing)
	end
	for i, ch in chips do
		local owner = st.owner[i]
		local active = st.active[i]
		ch.frame.Visible = owner ~= nil
		ch.frame.BackgroundColor3 = rel(owner)
		ch.frame.BackgroundTransparency = if active then 0 else 0.55
		ch.name.TextTransparency = if active then 0 else 0.4
		ch.own.Visible = f ~= nil and owner == f
		-- progresso: positivo = para os EUA (azul), negativo = para o VC (vermelho), para todos
		local p = st.progress[i] or 0
		ch.fill.BackgroundColor3 = if p >= 0 then Color3.fromRGB(150, 182, 236) else Color3.fromRGB(240, 140, 120)
		ch.fill.Size = UDim2.fromScale(math.abs(p), 1)
		local cap = st.capturing and st.capturing[i]
		local con = st.contested and st.contested[i]
		ch.mark.Text = if con then "⚔" elseif cap == f then "▲" elseif cap then "▼" else ""
		ch.mark.TextColor3 = if con
			then Color3.fromRGB(255, 214, 120)
			elseif cap == f then Color3.fromRGB(190, 220, 255)
			else Color3.fromRGB(255, 170, 150)
		ch.target = i == target
		ch.contested = con == true
		if not ch.contested then -- em disputa, quem cuida do contorno é o pisca (paintPulses)
			ch.stroke.Transparency = if ch.target then 0 else 1
		end
	end
	-- direita: reforços (Warfare) ou frente (Offensive)
	if st.score and f then
		-- cores fixas: o primeiro (azul) é sempre o dos EUA, o segundo (vermelho) o do VC
		scoreText.Text = string.format(
			'REFORÇOS <font color="#96B6EC">%d</font> · <font color="#F08C78">%d</font>',
			st.score.US or 0,
			st.score.VC or 0
		)
	elseif st.mode == "Offensive" and type(st.front) == "number" and st.front >= 1 then
		scoreText.Text = string.format("FRENTE %s", Front.letra(st.front))
	else
		scoreText.Text = ""
	end
	-- objetivo com rumo e distância de onde estou
	if role and target and st.points and st.points[target] then
		local p = st.points[target]
		local where = ""
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dx, dz = p.x - root.Position.X, p.z - root.Position.Z
			local m = math.sqrt(dx * dx + dz * dz) * 0.28
			where = if m < 50
				then " · você está nele"
				else string.format(" · ~%d m a %s", Casualty.roundDistance(m), Casualty.bearing(dx, dz))
		end
		local verb = if role == "attack"
			then '<font color="#ECCA74">ATACAR</font>'
			else '<font color="#ECCA74">DEFENDER</font>'
		objective.Text = string.format("%s · %s%s", verb, sectorName(st, target), where)
	else
		objective.Text = ""
	end
end

-- o pisca da disputa: um tween em laço por setor (antes era por quadro), ligado e desligado só
-- quando a disputa muda
local pulses: { [number]: Tween } = {}
local function paintPulses()
	for i, ch in chips do
		local tw = pulses[i]
		if ch.contested and not tw then
			ch.stroke.Color = Color3.fromRGB(255, 214, 120)
			ch.stroke.Transparency = 0
			local t = TweenService:Create(
				ch.stroke,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.8 }
			)
			pulses[i] = t
			t:Play()
		elseif not ch.contested and tw then
			tw:Cancel()
			pulses[i] = nil
			ch.stroke.Color = C.brass
			ch.stroke.Transparency = if ch.target then 0 else 1
		end
	end
end

-- ===== captura (pedido do dono, 2026-11-12) =====
-- No setor que estou capturando ou disputando: o estado, a barra do progresso (azul = para os EUA,
-- vermelho = para o VC, para os dois times) e quantos aliados e inimigos há na área (Match_State.inArea:
-- a contagem do servidor a cada segundo, a mesma da captura). O setor ganha um filete claro em cima
-- na faixa. Fica abaixo do meio da tela (o alto é da faixa e dos avisos; o pé, da bússola) e some com
-- os menus, o mapa e a tela de baixa, como a faixa. Montado uma vez; entra e sai esmaecendo.
local CAP_R2 = MapConfig.CaptureRadiusStuds ^ 2
local capW, capH = px(330, 460), px(92, 128)
local cap = Instance.new("CanvasGroup")
cap.Name = "Captura"
cap.AnchorPoint = Vector2.new(0.5, 0)
-- v43 (pedido do dono: "coloque a tela de disputa do objetivo mais para baixo"): 0,74 (era 0,66),
-- acima da bússola do pé
local CAP_Y = 0.74
cap.Position = UDim2.fromScale(0.5, CAP_Y)
cap.Size = UDim2.fromOffset(capW, capH)
cap.BackgroundColor3 = V.PANEL
cap.BackgroundTransparency = 0.1
cap.BorderSizePixel = 0
cap.GroupTransparency = 1
cap.Visible = false
cap.Parent = hud
UiKit.corner(cap, 4)
UiKit.stroke(cap, V.LINE, 1, 0.4)
local capFit = UiKit.fit(hud, cap, capW, capH, 8)
local CP = px(12, 16)
local capName = UiKit.title(cap, "", px(18, 26))
capName.Position = UDim2.fromOffset(CP, CP - 2)
capName.Size = UDim2.new(1, -2 * CP - px(130, 180), 0, px(24, 34))
local capTag = UiKit.tag(cap, "TOMANDO", V.OLIVE, px(13, 20))
capTag.AnchorPoint = Vector2.new(1, 0)
capTag.Position = UDim2.new(1, -CP, 0, CP)
local capBack, capFill = UiKit.bar(cap, px(8, 12), V.US)
capBack.Position = UDim2.fromOffset(CP, CP + px(30, 42))
capBack.Size = UDim2.new(1, -2 * CP, 0, px(8, 12))
-- aliados à esquerda, inimigos à direita: o número grande e o rótulo ao lado
local function countGroup(label: string, right: boolean): TextLabel
	local g = Instance.new("Frame")
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
	g.Position = UDim2.new(if right then 1 else 0, if right then -CP else CP, 0, CP + px(44, 62))
	g.Size = UDim2.fromOffset(0, px(28, 40))
	g.AutomaticSize = Enum.AutomaticSize.X
	g.Parent = cap
	UiKit.list(g, true, px(6, 8))
	local n = UiKit.title(g, "0", px(24, 34))
	n.AutomaticSize = Enum.AutomaticSize.X
	n.Size = UDim2.fromOffset(0, px(28, 40))
	n.LayoutOrder = 1
	local k = UiKit.kicker(g, label, px(13, 20))
	k.AutomaticSize = Enum.AutomaticSize.X
	k.Size = UDim2.fromOffset(0, px(28, 40))
	k.LayoutOrder = 2
	return n
end
local allyN = countGroup("ALIADOS", false)
local enemyN = countGroup("INIMIGOS", true)

local capVisible = false
local capTween: Tween? = nil
local capSector: number? = nil
local function setCapVisible(on: boolean)
	if on == capVisible then
		return
	end
	capVisible = on
	local old = capTween
	if old then
		old:Cancel()
	end
	if on then
		cap.Visible = true
	end
	local t = TweenService:Create(cap, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		GroupTransparency = if on then 0 else 1,
	})
	capTween = t
	t.Completed:Once(function(s: Enum.PlaybackState)
		if s == Enum.PlaybackState.Completed and not capVisible then
			cap.Visible = false
		end
	end)
	t:Play()
end

-- setor ativo em cuja área de captura eu estou (o servidor conta pelo mesmo raio)
local function hereSector(st: any): number?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (root and type(st.points) == "table") then
		return nil
	end
	for s, p in st.points do
		if st.active[s] and type(p.x) == "number" and type(p.z) == "number" then
			local dx, dz = root.Position.X - p.x, root.Position.Z - p.z
			if dx * dx + dz * dz <= CAP_R2 then
				return s
			end
		end
	end
	return nil
end

-- fromState: chegou um Match_State novo (a barra anda até o valor novo em ~1 s, como o servidor)
local function updateCapture(fromState: boolean)
	local st = state
	local f = mine()
	local s = if st and f and not st.ended then hereSector(st) else nil
	for i, ch in chips do
		ch.here.Visible = i == s
	end
	local show = false
	if st and f and s then
		local by = st.capturing and st.capturing[s]
		local con = st.contested and st.contested[s] == true
		show = con or by ~= nil
		if show then
			local owner = st.owner[s]
			local word, color, ink = "EM DISPUTA", V.BRASS, V.BG
			if not con and by == f then
				word, color, ink = if owner == f then "REFORÇANDO" else "TOMANDO", V.OLIVE, V.TEXT
			elseif not con then
				word, color, ink = if owner == f then "SOB ATAQUE" else "INIMIGO TOMANDO", V.RED, V.TEXT
			end
			if capTag.Text ~= word then
				capTag.Text = word
				capTag.FontFace = UiKit.Estilo.headFont(word, UiKit.F.TITLE_MED)
			end
			capTag.BackgroundColor3 = color
			capTag.TextColor3 = ink
			local name = sectorName(st, s)
			if capName.Text ~= name then
				capName.Text = name
				capName.FontFace = UiKit.Estilo.headFont(name)
			end
			local a = st.inArea and st.inArea[s]
			allyN.Text = tostring(if type(a) == "table" then a[f] or 0 else 0)
			enemyN.Text = tostring(if type(a) == "table" then a[enemyOf(f)] or 0 else 0)
			local p = st.progress[s] or 0
			capFill.BackgroundColor3 = if p >= 0 then V.US else V.VC
			local goal = UDim2.fromScale(math.clamp(math.abs(p), 0, 1), 1)
			if s ~= capSector then
				capFill.Size = goal -- setor novo: a barra já começa no valor
			elseif fromState then
				TweenService:Create(capFill, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Size = goal }):Play()
			end
		end
	end
	capSector = if show then s else nil
	-- caído o painel some (v41: no celular ele cobria o cartão de caído)
	setCapVisible(show and strip.Visible and not Input.state.downed)
end

-- ===== fim de partida =====
-- Estilo novo (pedido do dono, 2026-11-11: "não gosto dessa escrita no papel"): tela cheia de cor
-- única, escura e saturada (vitória oliva, derrota vermelha, empate quase preto), o resultado enorme
-- num retângulo de borda fina, o motivo numa linha, os números grandes com o rótulo em cima
-- separados por barras inclinadas (USMC em azul, VC em vermelho, lado a lado), a contagem da próxima
-- partida e o botão do relatório. O conteúdo é um CanvasGroup: entra e sai esmaecendo inteiro.
local endGui = UiKit.screen("VT65FimDePartida", 43) -- acima do relatório pós-ação (40)
endGui.IgnoreGuiInset = true -- o fundo cobre a tela inteira, também atrás da barra do Roblox
endGui.Enabled = false
local endShown: number? = nil
local closeEnd: () -> ()
type EndParts = {
	bg: Frame,
	accent: Frame,
	hold: CanvasGroup,
	fit: UiKit.Fit,
	kicker: TextLabel,
	box: Frame,
	word: TextLabel,
	why: TextLabel,
	legend: TextLabel,
	stats: Frame,
	row: any, -- Estilo.StatRow: SETORES, REFORÇOS, BAIXAS, DURAÇÃO
	nextIn: TextLabel,
	report: UiKit.Action,
	parts: { GuiObject },
}
local endParts: EndParts
do
	local EW, EH = px(980, 1340), px(500, 700)
	local bg = UiKit.backdrop(endGui, V.BG)
	bg.BackgroundTransparency = 1
	-- faixa de cor no alto da tela (o acento do resultado)
	local accent = Instance.new("Frame")
	accent.Name = "Faixa"
	accent.Size = UDim2.new(1, 0, 0, px(5, 8))
	accent.BackgroundColor3 = V.OLIVE
	accent.BorderSizePixel = 0
	accent.Parent = bg
	local hold = Instance.new("CanvasGroup")
	hold.Name = "Conteudo"
	hold.AnchorPoint = Vector2.new(0.5, 0.5)
	hold.Position = UDim2.fromScale(0.5, 0.5)
	hold.Size = UDim2.fromOffset(EW, EH)
	hold.BackgroundTransparency = 1
	hold.GroupTransparency = 1
	hold.Parent = endGui
	-- cabe em qualquer janela: a entrada termina na escala de ajuste (fit.k), não em 1
	local fit = UiKit.fit(endGui, hold, EW, EH, 24)
	local kicker = UiKit.kicker(hold, "OPERAÇÃO STARLITE · FIM DA AÇÃO", px(18, 26))
	kicker.Position = UDim2.fromOffset(0, 0)
	kicker.Size = UDim2.new(1, 0, 0, px(24, 34))
	local box, word = UiKit.titleBox(hold, "VITÓRIA", px(96, 136))
	box.Position = UDim2.fromOffset(0, px(34, 48))
	-- o motivo numa linha só: a letra encolhe se a frase (ou a tradução) for longa
	local why = UiKit.text2(hold, "", px(22, 32), V.TEXT)
	why.Position = UDim2.fromOffset(0, px(176, 246))
	why.Size = UDim2.new(1, 0, 0, px(30, 42))
	why.TextScaled = true
	do
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = px(22, 32)
		lim.MinTextSize = px(13, 20)
		lim.Parent = why
	end
	-- legenda dos lados (as cores dos números) e a fileira de números
	local legend = UiKit.kicker(hold, "", px(15, 22))
	legend.RichText = true
	legend.Position = UDim2.fromOffset(0, px(226, 316))
	legend.Size = UDim2.new(1, 0, 0, px(20, 28))
	local stats = Instance.new("Frame")
	stats.Name = "Numeros"
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(0, px(250, 350))
	stats.Size = UDim2.new(1, 0, 0, px(90, 126))
	stats.Parent = hold
	-- montada uma vez: abrir só troca os valores (sem reforços no Offensive, o número some)
	local row = UiKit.statRow(stats, {
		{ "SETORES", "0" },
		{ "REFORÇOS", "0" },
		{ "BAIXAS", "0" },
		{ "DURAÇÃO", "0:00" },
	}, px(56, 78))
	for _, s in row.stats do
		s.value.RichText = true
	end
	local nextIn = UiKit.kicker(hold, "", px(16, 24))
	nextIn.Position = UDim2.fromOffset(0, px(358, 500))
	nextIn.Size = UDim2.new(0.48, 0, 0, px(22, 32))
	local report = UiKit.action(hold, "VER O RELATÓRIO", "primary", function()
		-- o A que ainda vinha do tiro não fecha a tela no instante em que ela abre
		if endShown and os.clock() - endShown >= 0.6 then
			closeEnd()
		end
	end, { h = px(64, 88) })
	report.button.Name = "Relatorio"
	report.button.Position = UDim2.fromOffset(0, px(392, 548))
	report.button.Size = UDim2.fromOffset(px(460, 640), px(64, 88))
	endParts = {
		bg = bg,
		accent = accent,
		hold = hold,
		fit = fit,
		kicker = kicker,
		box = box,
		word = word,
		why = why,
		legend = legend,
		stats = stats,
		row = row,
		nextIn = nextIn,
		report = report,
		parts = { kicker, box, why, legend, stats, nextIn, report.button },
	}
end

-- o botão do relatório mostra o A no controle e o Enter no teclado
local function paintReportKey()
	local r = endParts.report
	if Input.isGamepad() then
		UiKit.setGlyph(r, UiKit.padImage(Enum.KeyCode.ButtonA))
		r.sub.Text = ""
	else
		UiKit.setGlyph(r, nil)
		r.sub.Text = if Input.device() == "touch" then "" else "Enter"
	end
end
Input.DeviceChanged:Connect(paintReportKey)

local function colored(c: Color3, s: string): string
	return string.format('<font color="#%s"><b>%s</b></font>', c:ToHex(), s)
end
-- "3 – 2" com o número do USMC em azul e o do VC em vermelho
local function versus(a: number, b: number): string
	return string.format("%s  %s  %s", colored(V.US, tostring(a)), colored(V.MUTED, "–"), colored(V.VC, tostring(b)))
end

local function reason(st: any): string
	local w = st.winner
	if w ~= "US" and w ~= "VC" then
		return "Tempo esgotado com setores e reforços iguais."
	end
	local who = if w == "US" then "USMC" else "VC"
	local loser = if w == "US" then "VC" else "US"
	if st.mode == "Offensive" then
		return if w == "US"
			then "O USMC tomou o último setor."
			else "O relógio zerou: a defesa do VC segurou a linha."
	end
	if st.score and (st.score[loser] or 1) <= 0 then
		return string.format("Os reforços do %s acabaram.", if loser == "US" then "USMC" else "VC")
	end
	local all = true
	for i, o in st.owner do
		if st.active[i] and o ~= w then
			all = false
		end
	end
	if all then
		return string.format("O %s tomou todos os setores.", who)
	end
	return string.format("Tempo esgotado: o %s tem mais setores (ou mais reforços).", who)
end

-- endOpen: a ficha está de pé (a ScreenGui ainda fica ligada 0,3 s na saída). Enquanto aberta ela
-- é uma tela de menu: o mouse fica solto (clique fecha) e o "voltar" (B, Esc, Backspace) também
-- fecha, sem passar para o relatório de baixo (pilha do UiKit).
local endOpen = false
local endToken = 0
closeEnd = function()
	if not endOpen then
		return
	end
	endOpen = false
	endShown = nil
	endToken += 1
	local my = endToken
	Input.closeMenu()
	UiKit.closed("fim")
	UiKit.release(endGui)
	local p = endParts
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	p.fit.play(info, 0.97)
	TweenService:Create(p.bg, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(p.accent, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(p.hold, info, { GroupTransparency = 1 }):Play()
	task.delay(0.31, function()
		if endToken ~= my then
			return
		end
		endGui.Enabled = false
		-- o relatório pós-ação fica por baixo: o foco do controle volta para ele
		local rep = player.PlayerGui:FindFirstChild("VT65AfterAction")
		if rep and rep:IsA("ScreenGui") and rep.Enabled then
			UiKit.focus(rep)
		end
	end)
end

local function showEnd(st: any)
	local f = mine()
	local p = endParts
	local w = st.winner
	-- palavra, fundo e acento: vitória oliva, derrota vermelha, empate quase preto
	local word, back, tone = "EMPATE", V.BG, V.KHAKI
	if w == f then
		word, back, tone = "VITÓRIA", V.BG_OLIVE, V.OLIVE_HI
	elseif w == "US" or w == "VC" then
		word, back, tone = "DERROTA", V.BG_RED, V.RED_HI
	end
	if not f then
		word = if w == "US" then "VITÓRIA DO USMC" elseif w == "VC" then "VITÓRIA DO VC" else "EMPATE"
		back, tone = V.BG, if w == "US" then V.US elseif w == "VC" then V.VC else V.KHAKI
	end
	p.word.Text = word
	p.word.FontFace = UiKit.Estilo.headFont(word)
	p.bg.BackgroundColor3 = back
	p.accent.BackgroundColor3 = tone
	p.why.Text = reason(st)
	-- números: setores, reforços (só no Warfare), baixas e a duração
	local sectors = { US = 0, VC = 0 }
	for i, o in st.owner do
		if st.active[i] and (o == "US" or o == "VC") then
			sectors[o] += 1
		end
	end
	p.legend.Text = string.format("%s  %s  %s", colored(V.US, "USMC"), colored(V.MUTED, "–"), colored(V.VC, "VC"))
	local stats = p.row.stats
	stats[1].value.Text = versus(sectors.US, sectors.VC)
	local hasScore = type(st.score) == "table"
	stats[2].frame.Visible = hasScore
	if hasScore then
		stats[2].value.Text = versus(st.score.US or 0, st.score.VC or 0)
	end
	local hasKia = type(st.kia) == "table"
	stats[3].frame.Visible = hasKia
	if hasKia then
		stats[3].value.Text = versus(st.kia.US or 0, st.kia.VC or 0)
	end
	local secs = math.max(0, math.floor((st.elapsed or 0) + 0.5))
	stats[4].value.Text = string.format("%d:%02d", secs // 60, secs % 60)
	-- a barra inclinada antes de um número escondido some junto (barras: ordens 3, 5 e 7)
	for _, c in p.row.frame:GetChildren() do
		if c:IsA("Frame") and c.Name == "Barra" then
			local after = stats[(c.LayoutOrder + 1) // 2]
			c.Visible = after == nil or after.frame.Visible
		end
	end
	p.nextIn.Text = ""
	paintReportKey()
	local shownAt = os.clock()
	endShown = shownAt
	endToken += 1
	local my = endToken
	if not endOpen then
		endOpen = true
		Input.openMenu()
	end
	UiKit.opened("fim", endGui.DisplayOrder)
	endGui.Enabled = true
	-- entra: o fundo cobre a tela, o conteúdo esmaece e assenta, as peças sobem uma a uma
	p.bg.BackgroundTransparency = 1
	p.accent.BackgroundTransparency = 1
	TweenService:Create(p.bg, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.04 }):Play()
	TweenService:Create(p.accent, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 }):Play()
	p.hold.GroupTransparency = 1
	TweenService:Create(p.hold, TweenInfo.new(0.32, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
	p.fit.play(TweenInfo.new(0.35, Enum.EasingStyle.Quint), 1, 1.04)
	UiKit.enter(p.parts, px(18, 26), 0.05, 0.05)
	task.delay(0.35, function()
		if endToken == my and endOpen then
			UiKit.focus(p.hold) -- o A do controle cai no botão do relatório
		end
	end)
	task.delay(9, function()
		if endShown == shownAt then
			closeEnd()
		end
	end)
end

Input.on("ui_back", "press", function()
	if endOpen and endShown and os.clock() - endShown >= 0.6 and UiKit.backFor("fim") then
		closeEnd()
	end
end)

-- ===== missões na tela de fim (plano de volta diária, 2026-11-12) =====
-- Ao lado do botão do relatório: as missões que andaram nesta partida (até 3), com o progresso.
-- O retrato do começo da partida é tirado do CampanhaCliente; o servidor pode mandar o progresso
-- do fim um instante depois: com a tela aberta, o bloco se refaz a cada estado novo.
local Missions: { [string]: any } = {}
do
	local CampanhaCliente = require(script.Parent.CampanhaCliente)
	local hold = endParts.hold
	local box = Instance.new("Frame")
	box.Name = "Missoes"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(1, 0)
	box.Position = UDim2.new(1, 0, 0, px(358, 500))
	box.Size = UDim2.new(0.5, 0, 0, px(100, 140))
	box.Visible = false
	box.Parent = hold
	local head = UiKit.kicker(box, "MISSÕES", px(15, 22), V.KHAKI)
	head.Size = UDim2.new(1, 0, 0, px(20, 28))
	local lines: { { TextLabel } } = {}
	for i = 1, 3 do
		local y = px(24, 34) + (i - 1) * px(24, 34)
		local t = UiKit.text2(box, "", px(15, 22), V.TEXT, UiKit.F.BODY)
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(0.78, 0, 0, px(22, 32))
		t.TextTruncate = Enum.TextTruncate.AtEnd
		local c = UiKit.text2(box, "", px(17, 24), V.TEXT, UiKit.F.TITLE)
		c.AnchorPoint = Vector2.new(1, 0)
		c.Position = UDim2.new(1, 0, 0, y)
		c.Size = UDim2.new(0.22, 0, 0, px(22, 32))
		c.TextXAlignment = Enum.TextXAlignment.Right
		lines[i] = { t, c }
	end
	local start: { [string]: number } = {}
	local function each(s: any, fn: (m: any) -> ())
		local ms = if type(s) == "table" then s.missions else nil
		if type(ms) ~= "table" then
			return
		end
		for _, scope in { "daily", "weekly" } do
			local list = ms[scope]
			if type(list) == "table" then
				for _, m in list do
					if type(m) == "table" and m.id ~= nil then
						fn(m)
					end
				end
			end
		end
	end
	-- começo da partida: guarda o progresso de cada missão
	function Missions.snapshot()
		table.clear(start)
		each(CampanhaCliente.get(), function(m)
			start[tostring(m.id)] = tonumber(m.progress) or 0
		end)
	end
	function Missions.paint()
		local moved = {}
		each(CampanhaCliente.get(), function(m)
			local before = start[tostring(m.id)]
			local now = tonumber(m.progress) or 0
			if before ~= nil and now > before and #moved < 3 then
				table.insert(moved, m)
			end
		end)
		box.Visible = #moved > 0
		for i, ln in lines do
			local m = moved[i]
			ln[1].Visible = m ~= nil
			ln[2].Visible = m ~= nil
			if m then
				local ok, s = pcall(string.format, tostring(m.text or m.id), tonumber(m.goal) or 0)
				ln[1].Text = if ok then s else tostring(m.text)
				ln[2].Text = string.format("%d/%d", tonumber(m.progress) or 0, tonumber(m.goal) or 0)
				ln[2].TextColor3 = if m.done then V.KHAKI else V.TEXT
			end
		end
	end
	CampanhaCliente.Changed:Connect(function()
		if endOpen then
			Missions.paint()
		elseif next(start) == nil then
			Missions.snapshot() -- o primeiro estado chegou depois do começo da partida
		end
	end)
	Missions.snapshot()
end

UserInputService.InputBegan:Connect(function(io: InputObject)
	if not endOpen or not endShown or os.clock() - endShown < 1.2 then
		return
	end
	local k = io.KeyCode
	if
		k == Enum.KeyCode.ButtonA
		or k == Enum.KeyCode.Return
		or k == Enum.KeyCode.Space
		or io.UserInputType == Enum.UserInputType.MouseButton1
		or io.UserInputType == Enum.UserInputType.Touch -- toque (Parte 13): tocar em qualquer lugar, como o clique
	then
		closeEnd()
	end
end)

-- ===== estado =====
Net.event("Match_State").OnClientEvent:Connect(function(st)
	if type(st) ~= "table" or type(st.owner) ~= "table" then
		return
	end
	-- "quem está tomando" vem como lista cheia com "" = ninguém (MatchService.publish)
	if type(st.capturing) == "table" then
		for i, v in st.capturing do
			if v == "" then
				st.capturing[i] = nil
			end
		end
	end
	prev, state = state, st
	if prev and not prev.ended and st.ended then
		showEnd(st)
		Missions.paint()
	elseif prev and prev.ended and not st.ended then
		table.clear(once)
		table.clear(cooldown)
		closeEnd()
		Missions.snapshot() -- partida nova: o progresso das missões conta daqui
		Toast.show(string.format("Nova partida: %s", st.mode), "info", { title = "Operação Starlite" })
	end
	alerts(st, prev)
	render(st)
	paintPulses()
	updateCapture(true)
end)

-- 10 Hz (antes era por quadro): visibilidade da faixa, o pé da tela de fim e o foco
local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	local st = state
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local inField = st ~= nil and mine() ~= nil and hum ~= nil and hum.Health > 0
	strip.Visible = inField and not Input.state.map and Input.state.menus == 0 and not endGui.Enabled
	placeStripTouch()
	-- toque v39: o painel da captura na zona livre "captura" (acima do cartão da arma, longe da mira)
	if
		not ToqueUi.fitZone(cap, capFit.scale, "captura", capW, capH, Vector2.new(0.5, 1), 1, 0.4)
		and cap.Position.X.Scale ~= 0.5
	then
		cap.AnchorPoint = Vector2.new(0.5, 0)
		cap.Position = UDim2.fromScale(0.5, CAP_Y)
		capFit.scale.Scale = capFit.k()
	end
	updateCapture(false) -- entrei ou saí da área de um setor
	if endOpen and endShown then
		local n = state and state.nextIn
		local t = if type(n) == "number" then string.format("Próxima partida em %d s", math.ceil(n)) else ""
		if endParts.nextIn.Text ~= t then
			endParts.nextIn.Text = t
		end
	end
	if GuiService.SelectedObject and endOpen and GuiService.SelectedObject:IsDescendantOf(player.PlayerGui) then
		-- com a tela de fim por cima, A não pode fechar o relatório de baixo
		local rep = player.PlayerGui:FindFirstChild("VT65AfterAction")
		if rep and GuiService.SelectedObject:IsDescendantOf(rep) then
			GuiService.SelectedObject = nil
		end
	end
end)

-- Studio: workspace:SetAttribute("VT65DevTela", "fim") mostra a tela de fim com um placar de
-- exemplo (vitória do meu lado por reforços), sem encerrar a partida
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "fim" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		local w = mine() or "US"
		showEnd({
			ended = true,
			winner = w,
			mode = "Warfare",
			owner = { "VC", "US", "US" },
			active = { true, true, true },
			score = { US = if w == "US" then 132 else 0, VC = if w == "VC" then 132 else 0, max = 400 },
			kia = { US = 31, VC = 58 },
			elapsed = 1512,
		})
	end)
end
