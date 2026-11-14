--!strict
-- Botão contextual de interagir no toque (Parte 13, T2). Só aparece quando há algo a fazer:
--   - interação do mundo (ProximityPrompt na tela): abrir caixote, pegar arma ou munição, pegar o
--     rádio, plantar/desarmar carga, desarmar armadilha, destruir túnel, entrar no veículo (o
--     "VT65Embarcar" abre o painel de lugares do VehiclePrompt). O botão faz o mesmo que segurar X/F:
--     prompt:InputHoldBegin() ao apertar e InputHoldEnd() ao soltar; o anel enche no HoldDuration;
--   - companheiro perto (3 m, a mesma conta do MedicalController): REANIMAR (médico, caído), TRATAR
--     (médico) ou CURATIVO (seu curativo nele). Aperta a ação "interact" (Input.virtual do T1; sem ele,
--     o Bus "interact_ally" do MedicalController); o anel segue o tempo do servidor (atributos
--     VT65AcaoT/VT65AcaoS do personagem, MedicalService).
-- Como no PC, a interação do mundo vence o companheiro. Não há "arrastar ferido" no jogo (o servidor
-- não tem a mecânica): nada a ligar aqui. Construir tem a prévia própria (ObraToque).
-- Lugar: a vaga "interact" do HUD de toque do T1 (Shared/Toque, layouts e editor; a tela VT65Toque
-- publica centro e lado); sem ele, à direita, acima do tiro. Some fora do toque, no menu, no mapa,
-- caído, morto, em veículo e com a vaga desligada no editor do HUD.
-- Studio: workspace:SetAttribute("VT65DevTela", "interagir") mostra o botão de exemplo por 15 s
-- (segurar enche o anel em 3 s), com ou sem toque.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local ToqueTelas = require(script.Parent.ToqueTelas)
local ToqueUi = require(script.Parent.ToqueUi)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local M = 0.28
local ALLY_REACH = 3 / M -- MedicalController.nearestAlly

local gui = UiKit.screen("VT65Interagir", 15) -- acima do HUD de campo (13), abaixo dos menus
gui.Enabled = false
local size = math.floor(ToqueUi.minPx() * 1.5)
local round = ToqueUi.roundButton(gui, "Interagir", size, "◉")
local button = round.button

-- ===== o que há por perto =====
local shown: { [ProximityPrompt]: boolean } = {}
ProximityPromptService.PromptShown:Connect(function(p: ProximityPrompt)
	shown[p] = true
end)
ProximityPromptService.PromptHidden:Connect(function(p: ProximityPrompt)
	shown[p] = nil
end)

local bandages = 0
Net.event("Medical_State").OnClientEvent:Connect(function(s: any)
	if type(s) == "table" and type(s.bandages) == "number" then
		bandages = s.bandages
	end
end)

local function rootOf(m: Instance?): BasePart?
	local r = m and m:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function promptPos(p: ProximityPrompt): Vector3?
	local par = p.Parent
	if par and par:IsA("Attachment") then
		return par.WorldPosition
	elseif par and par:IsA("BasePart") then
		return par.Position
	elseif par and par:IsA("Model") then
		return par:GetPivot().Position
	end
	return nil
end

local function promptList(root: BasePart): { ToqueTelas.PromptInfo }
	local out: { ToqueTelas.PromptInfo } = {}
	for p in shown do
		if p.Parent == nil or not p.Enabled then
			shown[p] = nil
			continue
		end
		local pos = promptPos(p)
		if pos then
			table.insert(out, {
				key = p,
				dist = (pos - root.Position).Magnitude,
				hold = p.HoldDuration,
				text = p.ActionText,
				vehicle = p.Name == "VT65Embarcar",
			})
		end
	end
	return out
end

-- companheiro mais perto (jogador ou bot) a até 3 m
local function nearestAlly(root: BasePart): ToqueTelas.AllyInfo?
	local mine = player:GetAttribute("Faction")
	local best: Model? = nil
	local bestD = ALLY_REACH
	local function consider(m: Model)
		local r = rootOf(m)
		if r and m:GetAttribute("Faction") == mine then
			local d = (r.Position - root.Position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			consider(p.Character)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				consider(m)
			end
		end
	end
	local m = best
	if not m then
		return nil
	end
	local owner = Players:GetPlayerFromCharacter(m)
	local downed = m:GetAttribute("Downed") == true or (owner ~= nil and owner:GetAttribute("Downed") == true)
	local hum = m:FindFirstChildOfClass("Humanoid")
	local hurt = hum ~= nil and hum.Health > 0 and hum.Health < hum.MaxHealth - 1
	return { downed = downed, hurt = hurt }
end

-- ===== estado =====
local choice: ToqueTelas.Choice? = nil
type Holding = { io: InputObject, choice: ToqueTelas.Choice, t0: number }
local holding: Holding? = nil
local devUntil = 0
local DEV_CHOICE: ToqueTelas.Choice =
	{ kind = "dev", key = nil, label = "ABRIR SUPRIMENTO", glyph = "◉", hold = 3, op = nil }

local function canShow(): boolean
	local s = Input.state
	return s.alive and not s.downed and s.vehicle == nil and s.menus == 0 and not s.map
end

local function refreshChoice()
	if os.clock() < devUntil then
		choice = DEV_CHOICE
		return
	end
	local char = player.Character
	local root = rootOf(char)
	if not (root and ToqueUi.active() and canShow()) then
		choice = nil
		return
	end
	choice = ToqueTelas.chooseInteraction(
		promptList(root :: BasePart),
		nearestAlly(root :: BasePart),
		player:GetAttribute("Role") == "medic",
		bandages
	)
end

local function finish()
	local h = holding
	if not h then
		return
	end
	holding = nil
	local c = h.choice
	if c.kind == "prompt" then
		local p = c.key :: ProximityPrompt
		pcall(function()
			p:InputHoldEnd()
		end)
	elseif c.kind == "ally" then
		ToqueUi.press("interact", false)
	end
	button.BackgroundColor3 = UiKit.V.PANEL
end

local function begin(io: InputObject)
	local c = choice
	if holding or not c then
		return
	end
	holding = { io = io, choice = c, t0 = os.clock() }
	button.BackgroundColor3 = UiKit.V.OLIVE
	if c.kind == "prompt" then
		local p = c.key :: ProximityPrompt
		pcall(function()
			p:InputHoldBegin()
		end)
	elseif c.kind == "ally" then
		-- o mesmo X segurado / F do PC (MedicalController.interactAlly); sem Input.virtual, pelo Bus.
		-- A soltura (finish) vai sempre: o Input guarda o dedo no botão até soltar.
		if ToqueUi.hasVirtual() then
			ToqueUi.press("interact", true)
		else
			Bus.fire("interact_ally")
		end
	end
end

button.InputBegan:Connect(function(io: InputObject)
	local t = io.UserInputType
	if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
		begin(io)
	end
end)
UserInputService.InputEnded:Connect(function(io: InputObject)
	local h = holding
	if h and h.io == io then
		finish()
	end
end)

-- ===== lugar =====
-- A vaga que o HUD de toque publica (VT65Toque: InteractPos/InteractSize/InteractVisible, espaço do
-- AbsolutePosition: aqui vira posição dentro desta tela). Sem o HUD, à direita, acima do tiro.
local slotOn = true
local function place()
	local center, slotSize, vis = ToqueUi.slot("Interagir", gui)
	slotOn = vis ~= false -- o jogador desligou a vaga no editor do HUD: o botão não aparece
	if center then
		local p = center - gui.AbsolutePosition
		button.Position = UDim2.fromOffset(p.X, p.Y)
		local s = math.max(size, slotSize or 0)
		button.Size = UDim2.fromOffset(s, s)
		return
	end
	local vp = gui.AbsoluteSize
	local cx, cy = ToqueTelas.interactSlot(vp.X, vp.Y, ToqueUi.firePx(), size, 16)
	button.Position = UDim2.fromOffset(cx, cy)
	button.Size = UDim2.fromOffset(size, size)
end

-- ===== quadro a quadro =====
local acc = 0
local lastLabel = ""
RunService.RenderStepped:Connect(function(dt: number)
	acc += dt
	if acc >= 0.1 then
		acc = 0
		refreshChoice()
		local h = holding
		if h and (choice == nil or (h.choice.kind == "prompt" and not shown[h.choice.key])) then
			finish() -- o prompt sumiu (andou, outro pegou) ou a tela mudou
		end
		place()
	end
	local c = choice
	local on = c ~= nil and (slotOn or os.clock() < devUntil)
	if gui.Enabled ~= on then
		gui.Enabled = on
	end
	if not c then
		round.ring.set(0)
		lastLabel = ""
		return
	end
	-- só quando muda: o Traducao.client troca o texto pela tradução, e reescrever todo quadro brigaria
	if c.label ~= lastLabel then
		lastLabel = c.label
		round.glyph.Text = c.glyph
		round.label.Text = UiKit.upper(c.label)
	end
	-- anel: o segurar do prompt (local) ou a ação que o servidor está contando (médico, curativo)
	local frac = 0
	local h = holding
	if h and h.choice.kind ~= "ally" then
		frac = ToqueTelas.progress(h.t0, h.choice.hold, os.clock())
	end
	local char = player.Character
	if char and char:GetAttribute("VT65Acao") then
		local t0, s = char:GetAttribute("VT65AcaoT"), char:GetAttribute("VT65AcaoS")
		if type(t0) == "number" and type(s) == "number" then
			frac = math.max(frac, ToqueTelas.progress(t0, s, workspace:GetServerTimeNow()))
		end
	end
	round.ring.set(frac)
end)

player.CharacterAdded:Connect(function()
	finish()
	table.clear(shown)
end)

-- Studio: botão de exemplo (com ou sem toque) para o Device Emulator
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") == "interagir" then
			devUntil = os.clock() + 15
			task.defer(function()
				workspace:SetAttribute("VT65DevTela", nil)
			end)
		end
	end)
end
