--!strict
-- Jogar agora, lado do cliente (pedido do dono, 2026-11-13: "Botão 'jogar agora', que já põe o
-- jogador num squad e no último ponto de spawn usado"; "faça o jogo mais fast paced"). Um toque:
--   1. pede ao servidor (Spawn_Request "quick"): ele põe no lado, no squad e no papel (os da última
--      vez ou os mais adequados, Shared/JogarAgora) e responde o ponto (o último usado ou o melhor)
--      no atributo "JogarAgora";
--   2. aqui a espera do ponto conta (Spawn_State) e, a 2,5 s do fim, começa a transição de sempre
--      (SpawnTransition: a área carrega enquanto a espera acaba; o pedido do ponto só sai com a
--      espera zerada e o servidor valida tudo de novo);
--   3. o ponto fechou no meio da espera: pede de novo (até 2 vezes); sem resposta em 4 s, ou sem
--      ponto, abre a carta de inserção para escolher.
-- O cartão (JOGAR AGORA, a espera e o cancelar) fica num palco de 1280 x 720 igual ao do lobby
-- (GameUI): na mesa embaixo à direita, na escolha de lado no alto à direita, na carta de inserção
-- embaixo do painel da esquerda (no toque, no alto à esquerda). Nos outros painéis some.
-- Controle: X na mesa e na escolha de lado; teclado: Enter na mesa e J em qualquer tela do lobby;
-- B, M, Backspace ou o próprio botão cancelam. Outras telas chamam JogarAgora.start: a tela de baixa
-- (RENASCER), o menu do jogo (Bus "jogar_agora") e a tela de entrada (atributo "JogarAgora" na
-- VT65Loading).
-- Studio: workspace:SetAttribute("VT65DevTela", "jogar") aperta o JOGAR AGORA.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Carta = require(ReplicatedStorage.Shared.Carta)
local CompraVeiculo = require(ReplicatedStorage.Shared.CompraVeiculo)
local Front = require(ReplicatedStorage.Shared.Front)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Regras = require(ReplicatedStorage.Shared.JogarAgora)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Bus = require(script.Parent.Bus)
local CartaView = require(script.Parent.CartaView)
local DeployScreen = require(script.Parent.DeployScreen)
local Input = require(script.Parent.Input)
local LobbyScene = require(script.Parent.LobbyScene)
local SpawnTransition = require(script.Parent.SpawnTransition)
local Toast = require(script.Parent.Toast)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local JogarAgora = {}

local player = Players.LocalPlayer
local V = UiKit.V
local ASK_S = 4 -- sem resposta do servidor: abre a carta
local EARLY_S = 2.5 -- a transição começa antes do fim da espera (a área carrega no meio)
local LOST_S = 3 -- ponto que não aparece na lista: pede de novo
local SIDE: { [string]: string } = { US = "EUA", VC = "VC" }

type Phase = "idle" | "asking" | "waiting" | "going"
local S = {
	phase = "idle" :: Phase,
	n = 0,
	askedAt = 0,
	vehicle = false,
	point = nil :: string?,
	pointSince = 0,
	total = 0, -- espera do ponto quando a contagem começou (a barra)
	retries = 0,
	list = {} :: { any },
	listAt = 0,
	match = nil :: any,
}

local function alive(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function faction(): string?
	local f = player:GetAttribute("Faction")
	return if type(f) == "string" then f else nil
end

local function hasRole(): boolean
	return type(player:GetAttribute("Role")) == "string" and type(player:GetAttribute("SquadId")) == "string"
end

-- objetivo do lado (studs), pelo Match_State (a mesma conta do servidor)
local function objective(): (number?, number?)
	local st, f = S.match, faction()
	if type(st) ~= "table" or not f or type(st.owner) ~= "table" or type(st.active) ~= "table" then
		return nil, nil
	end
	local ok, _, s = pcall(Front.objective, st.owner, st.active, f)
	local p = if ok and s and type(st.points) == "table" then st.points[s] else nil
	if type(p) == "table" and type(p.x) == "number" and type(p.z) == "number" then
		return p.x, p.z
	end
	return nil, nil
end

local function entry(id: string?): any?
	if not id then
		return nil
	end
	for _, e in S.list do
		if type(e) == "table" and e.id == id then
			return e
		end
	end
	return nil
end

local function age(): number
	return os.clock() - S.listAt
end

-- O ponto que o jogar agora escolheria agora (sem pedir nada): o pedido em curso, ou a mesma conta
-- do servidor sobre a última lista. Devolve o ponto e a espera que falta.
function JogarAgora.preview(vehicle: boolean?): (any?, number?)
	local e = entry(S.point)
	if not e then
		local last = player:GetAttribute("UltimoPonto")
		local ox, oz = objective()
		e = Regras.pickPoint(S.list, if type(last) == "string" then last else nil, {
			vehicle = vehicle,
			allowed = CompraVeiculo.pointAllowed,
			objX = ox,
			objZ = oz,
			age = age(),
		})
	end
	if not e then
		return nil, nil
	end
	return e, Regras.waitLeft(e, age())
end

-- "Alfa · Fuzileiro · Reunião — Cemitério": lista curta (o Lang traduz cada pedaço)
function JogarAgora.summary(vehicle: boolean?): string
	local parts: { string } = {}
	local f = faction()
	local sid = player:GetAttribute("SquadId")
	local role = player:GetAttribute("Role")
	if f and type(sid) == "string" then
		table.insert(parts, string.match(sid, ":(.+)$") or sid)
	else
		local c = Regras.decode(player:GetAttribute("UltimaEscolha"))
		local side = f or c.f
		table.insert(parts, if side then SIDE[side] or side else "Lado com vaga")
		table.insert(parts, if c.sq and (f == nil or c.f == f) then c.sq else "Squad com vaga")
		if type(role) ~= "string" and c.role and (f == nil or c.f == f) then
			role = c.role
		end
	end
	local def = if type(role) == "string" then Roles.roles[role] else nil
	if def then
		table.insert(parts, def.name)
	end
	local e = JogarAgora.preview(vehicle)
	if e and type(e.name) == "string" then
		table.insert(parts, e.name)
	elseif type(player:GetAttribute("UltimoPonto")) == "string" then
		table.insert(parts, "Último ponto")
	end
	return table.concat(parts, " · ")
end

function JogarAgora.busy(): boolean
	return S.phase ~= "idle"
end

function JogarAgora.phase(): string
	return S.phase
end

-- espera que falta no ponto escolhido (nil: ainda sem ponto)
function JogarAgora.waitLeft(): number?
	local e = entry(S.point)
	return if e then Regras.waitLeft(e, age()) else nil
end

local paint: () -> () = function() end

local function stop()
	S.phase = "idle"
	S.point = nil
	paint()
end

local function openInsert()
	if not alive() and hasRole() then
		DeployScreen.open("insert")
	end
end

local function fail(msg: string)
	stop()
	Toast.show(msg, "alerta", { title = "Jogar agora", key = "jogar_agora" })
	openInsert()
end

local function ask()
	S.n = S.n % 99999 + 1
	S.askedAt = os.clock()
	S.phase = "asking"
	Net.event("Spawn_Request"):FireServer("quick", { n = S.n, v = S.vehicle })
	paint()
end

local function retry()
	if S.retries >= 2 then
		fail("O ponto mudou: escolha outro na carta")
		return
	end
	S.retries += 1
	S.point = nil
	ask()
end

-- Começa (devolve false se não dá agora). opts.vehicle: só pontos onde o veículo comprado sai.
function JogarAgora.start(opts: { vehicle: boolean? }?): boolean
	if alive() or SpawnTransition.busy() then
		return false
	end
	S.vehicle = opts ~= nil and opts.vehicle == true
	if S.phase ~= "idle" then
		return true
	end
	S.retries = 0
	S.point = nil
	ask()
	return true
end

function JogarAgora.cancel()
	if S.phase == "asking" or S.phase == "waiting" then
		stop()
	end
end

-- leva o cursor da carta ao ponto escolhido
local function focusPoint()
	local e = entry(S.point)
	if e and type(e.x) == "number" and type(e.z) == "number" then
		local u, v = Carta.toUV(MapConfig.Bounds, e.x, e.z)
		pcall(CartaView.goTo, u, v)
	end
end

-- entra: a transição carrega a área; o pedido do ponto só sai com a espera zerada
local function go(e: any)
	S.phase = "going"
	paint()
	local id = e.id :: string
	local started = SpawnTransition.go({ id = id, name = tostring(e.name), x = e.x, z = e.z }, function()
		local t0 = os.clock()
		while os.clock() - t0 < 15 do
			local cur = entry(id)
			if not cur or Regras.waitLeft(cur, age()) <= 0 then
				break
			end
			task.wait(0.1)
		end
		Net.event("Spawn_Request"):FireServer(id)
	end)
	if not started then
		S.phase = "waiting" -- outra inserção em curso: tenta no próximo passo
	end
end

-- ===== resposta do servidor =====
player:GetAttributeChangedSignal("JogarAgora"):Connect(function()
	local id, why, n = Regras.parseReply(player:GetAttribute("JogarAgora"))
	if n ~= S.n or S.phase ~= "asking" then
		return
	end
	if why then
		fail(why)
		return
	end
	S.point = id
	S.pointSince = os.clock()
	S.total = 0
	S.phase = "waiting"
	openInsert()
	focusPoint()
	paint()
end)

Net.event("Spawn_State").OnClientEvent:Connect(function(list: any)
	if type(list) == "table" then
		S.list = list
		S.listAt = os.clock()
	end
end)
Net.event("Match_State").OnClientEvent:Connect(function(st: any)
	if type(st) == "table" then
		S.match = st
	end
end)

-- passo (10 vezes por segundo, nada por quadro)
local function step()
	if S.phase == "idle" then
		return
	end
	if alive() then
		stop() -- já em campo (por aqui ou por outro caminho)
		return
	end
	if S.phase == "going" then
		if not SpawnTransition.busy() then
			stop() -- a transição acabou (deu certo ou foi recusada: a carta fica para escolher)
		end
		return
	end
	if S.phase == "asking" then
		if os.clock() - S.askedAt > ASK_S then
			fail("Sem resposta do servidor: escolha o ponto na carta")
		end
		return
	end
	-- esperando o ponto
	if SpawnTransition.busy() then
		stop() -- o jogador escolheu outro ponto na carta
		return
	end
	local e = entry(S.point)
	if not e then
		if os.clock() - S.pointSince > LOST_S then
			retry()
		end
		return
	end
	if not Regras.usable(e, { vehicle = S.vehicle, allowed = CompraVeiculo.pointAllowed }) then
		retry()
		return
	end
	local left = Regras.waitLeft(e, age())
	S.total = math.max(S.total, left)
	if left <= EARLY_S then
		go(e)
	end
end

-- ===== cartão no palco do lobby =====
local gui = UiKit.screen("VT65JogarAgora", 21) -- acima da carta (20), abaixo dos botões de toque (22)
gui.IgnoreGuiInset = true
local DESIGN_W, DESIGN_H = 1280, 720
local stage = Instance.new("Frame")
stage.Name = "Stage"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromOffset(DESIGN_W, DESIGN_H)
stage.BackgroundTransparency = 1
stage.Parent = gui
local stageScale = Instance.new("UIScale")
stageScale.Parent = stage
local function fit()
	local s = gui.AbsoluteSize
	if s.X < 10 or s.Y < 10 then
		return
	end
	local k = math.min(s.X / DESIGN_W, s.Y / DESIGN_H)
	if UiKit.tv() then
		k = math.max(k * 0.92, 1)
	end
	stageScale.Scale = k
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

local card = Instance.new("Frame")
card.Name = "JogarAgora"
card.BackgroundTransparency = 1
card.Size = UDim2.fromOffset(300, 0)
card.AutomaticSize = Enum.AutomaticSize.Y
card.Visible = false
card.Parent = stage
UiKit.list(card, false, 4)

local toggle: () -> ()
local btn = UiKit.action(card, "JOGAR AGORA", "free", function()
	toggle()
end, { h = 60 })
btn.button.LayoutOrder = 1
btn.label.TextXAlignment = Enum.TextXAlignment.Left
btn.label.TextSize = UiKit.text(26)
local bar = Instance.new("Frame")
bar.Name = "Espera"
bar.AnchorPoint = Vector2.new(0, 1)
bar.Position = UDim2.fromScale(0, 1)
bar.Size = UDim2.new(0, 0, 0, 4)
bar.BackgroundColor3 = V.TEXT
bar.BackgroundTransparency = 0.25
bar.BorderSizePixel = 0
bar.Parent = btn.button
local line = UiKit.text2(card, "", 14, V.TEXT)
line.LayoutOrder = 2
line.Size = UDim2.new(1, 0, 0, 20)
line.TextTruncate = Enum.TextTruncate.AtEnd
line.TextStrokeColor3 = V.BG
line.TextStrokeTransparency = 0.35

toggle = function()
	if S.phase == "idle" then
		JogarAgora.start()
	else
		JogarAgora.cancel()
	end
end

-- onde o cartão fica (palco de projeto) e se aparece
local function place(): boolean
	local root = DeployScreen.root
	if not root.Visible or alive() or SpawnTransition.busy() then
		return false
	end
	if UiKit.top() ~= nil then
		return false -- outra tela por cima (loja, menu, baixa, painel do veículo)
	end
	local panel = DeployScreen.panel()
	-- na sala de arquivo (escolha de lado, ou trocando de lado) as fichas ocupam a faixa de baixo
	local choosing = faction() == nil or LobbyScene.screenPoint("pick_US") ~= nil
	if ToqueUi.active() and panel == "insert" then
		card.AnchorPoint = Vector2.new(0, 0)
		card.Position = UDim2.fromOffset(16, 64) -- abaixo da faixa do Roblox
		card.Size = UDim2.fromOffset(280, 0)
	elseif panel == "insert" then
		card.AnchorPoint = Vector2.new(0, 1)
		card.Position = UDim2.fromOffset(56, 652)
		card.Size = UDim2.fromOffset(268, 0)
	elseif choosing then
		card.AnchorPoint = Vector2.new(1, 0)
		card.Position = UDim2.fromOffset(1240, 140)
		card.Size = UDim2.fromOffset(300, 0)
	elseif panel == "desk" then
		card.AnchorPoint = Vector2.new(1, 1)
		card.Position = UDim2.fromOffset(1240, if UiKit.tv() then 600 else 664)
		card.Size = UDim2.fromOffset(300, 0)
	else
		return false -- squad, papel, diária e loja: o jogador está escolhendo à mão
	end
	return true
end

paint = function()
	local show = place()
	card.Visible = show
	if not show then
		return
	end
	local pad = Input.isGamepad()
	local insert = DeployScreen.panel() == "insert"
	local label, sub, info, fill = "JOGAR AGORA", "", JogarAgora.summary(), 0
	if S.phase == "asking" then
		label, info = "PROCURANDO…", "Squad, papel e ponto"
	elseif S.phase == "waiting" or S.phase == "going" then
		local left = JogarAgora.waitLeft()
		local e = entry(S.point)
		label = if left and left > 0.5 then string.format("ENTRANDO EM %d s", math.ceil(left)) else "ENTRANDO"
		sub = "CANCELAR"
		info = if e and type(e.name) == "string" then e.name else info
		fill = if left and S.total > 0 then 1 - math.clamp(left / S.total, 0, 1) else 1
	end
	if btn.label.Text ~= label then
		btn.label.Text = label
	end
	btn.sub.Text = sub
	line.Text = info
	bar.Size = UDim2.new(fill, 0, 0, 4)
	bar.Visible = S.phase ~= "idle"
	UiKit.setGlyph(btn, if pad and not insert then UiKit.padImage(Enum.KeyCode.ButtonX) else nil)
end

local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	step()
	paint()
end)
Input.DeviceChanged:Connect(function()
	task.defer(paint)
end)

-- teclado e controle: X e Enter na mesa e na escolha de lado; J em qualquer tela do lobby
UserInputService.InputBegan:Connect(function(io: InputObject)
	if not card.Visible or UserInputService:GetFocusedTextBox() then
		return
	end
	if Input.state.menus > 1 then
		return -- o cartão de idiomas (ou outro) por cima do lobby
	end
	local k = io.KeyCode
	local insert = DeployScreen.panel() == "insert"
	if k == Enum.KeyCode.J or (not insert and (k == Enum.KeyCode.ButtonX or k == Enum.KeyCode.Return)) then
		toggle()
	end
end)
-- voltar (B, Backspace, M) cancela: quem trata é o GameUI (o mesmo aperto não volta à mesa)

-- outras telas pedem pelo barramento (menu do jogo)
Bus.on("jogar_agora", function(opts: any)
	JogarAgora.start(if type(opts) == "table" then opts else nil)
end)

-- tela de entrada: "JOGAR AGORA" lá vira o pedido aqui, quando o lobby e o terreno estiverem prontos
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local function watch(g: Instance)
		if g.Name ~= "VT65Loading" then
			return
		end
		local function check()
			if g:GetAttribute("JogarAgora") ~= true then
				return
			end
			g:SetAttribute("JogarAgora", nil)
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < 30 do
					if ReplicatedStorage:GetAttribute("TerrainReady") ~= false and DeployScreen.root.Visible then
						break
					end
					task.wait(0.25)
				end
				task.wait(0.4) -- a câmera da mesa chega
				JogarAgora.start()
			end)
		end
		g:GetAttributeChangedSignal("JogarAgora"):Connect(check)
		check()
	end
	for _, g in pg:GetChildren() do
		watch(g)
	end
	pg.ChildAdded:Connect(watch)
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "jogar" then
			return
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil)
		end)
		print("[VT65 TESTE] jogar agora:", JogarAgora.start(), JogarAgora.summary())
	end)
end

return JogarAgora
