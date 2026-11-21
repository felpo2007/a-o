--!strict
-- Voz no campo, lado do cliente (pedido do dono, 2026-11-12: "permita falar pelo jogo com quem está
-- perto e com o seu batalhão"). O servidor (Modules/Comunicacao) cria o AudioDeviceInput "VT65Voz" de
-- cada jogador e decide quem recebe cada voz; aqui fica o que soa (regras e números em Shared/Conversa):
--   perto: um AudioEmitter na cabeça de cada outro jogador, com a curva de Conversa.NEAR_CURVE_M (some
--     aos 40 m), ouvido pelo AudioListener da câmera; posicional;
--   rádio do squad: enquanto um companheiro segura o rádio (Voz_Estado), a voz dele também passa por
--     passa-alta 350 Hz -> passa-baixa 3 kHz -> distorção leve -> saída, sem posição, em qualquer lugar
--     do mapa; clique do PRC-10 (AssetIds.Sounds.radio_squelch) ao abrir e ao fechar;
--   quem fala: um AudioAnalyzer em cada ALIADO (lido a 5 Hz), publicado em VozEstado para o HUD.
-- Botão: ação "radio_talk" do InputMap (segurar ↓ no controle; Caps Lock no teclado).
-- Os nós de áudio são locais (criados no cliente) e só tocam aqui. Laço de 2 Hz, nada por quadro.
-- Studio: workspace:SetAttribute("VT65DevTela", "voz") acende o ícone de fala dos aliados por 5 s.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local VoiceChatService = game:GetService("VoiceChatService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Conversa = require(ReplicatedStorage.Shared.Conversa)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)
local VozEstado = require(script.Parent.VozEstado)

local player = Players.LocalPlayer
local M = MapConfig.STUD_M
local C = Conversa.C
local GROUP = "VT65Voz" -- o ouvido da câmera só escuta os emissores de voz

local function voiceProp(name: string): any
	local ok, v = pcall(function()
		return (VoiceChatService :: any)[name]
	end)
	return if ok then v else nil
end
local api, default = voiceProp("UseAudioApi"), voiceProp("EnableDefaultVoice")
if (api ~= nil and api ~= Enum.AudioApiRollout.Enabled) or default == true then
	-- voz padrão do Roblox (sem rádio): nada a montar aqui
	return
end

-- ===== nós fixos: saída, ouvido e cadeia do rádio =====
local folder = Instance.new("Folder")
folder.Name = "VT65VozLocal"
folder.Parent = SoundService

local function wire(src: Instance, dst: Instance, parent: Instance): Wire
	local w = Instance.new("Wire")
	w.SourceInstance = src
	w.TargetInstance = dst
	w.Parent = parent
	return w
end

local out = Instance.new("AudioDeviceOutput")
out.Name = "Saida"
out.Parent = folder

local radioIn = Instance.new("AudioFader")
radioIn.Name = "RadioEntrada"
radioIn.Parent = folder
local highpass = Instance.new("AudioFilter")
highpass.Name = "RadioPassaAlta"
highpass.FilterType = Enum.AudioFilterType.Highpass24dB
highpass.Frequency = C.radioLowHz
highpass.Q = 0.707
highpass.Parent = folder
local lowpass = Instance.new("AudioFilter")
lowpass.Name = "RadioPassaBaixa"
lowpass.FilterType = Enum.AudioFilterType.Lowpass24dB
lowpass.Frequency = C.radioHighHz
lowpass.Q = 0.707
lowpass.Parent = folder
local distortion = Instance.new("AudioDistortion")
distortion.Name = "RadioDistorcao"
distortion.Level = C.radioDistortion
distortion.Parent = folder
local radioOut = Instance.new("AudioFader")
radioOut.Name = "RadioVolume"
radioOut.Volume = C.radioVolume
radioOut.Parent = folder
wire(radioIn, highpass, folder)
wire(highpass, lowpass, folder)
wire(lowpass, distortion, folder)
wire(distortion, radioOut, folder)
wire(radioOut, out, folder)

local squelch = Instance.new("Sound")
squelch.Name = "RadioClique"
squelch.SoundId = "rbxassetid://" .. tostring(AssetIds.Sounds.radio_squelch)
squelch.Volume = C.squelchVolume
squelch.Parent = folder -- o AudioController põe no grupo de efeitos

local listener: AudioListener? = nil
local function placeListener()
	local cam = workspace.CurrentCamera
	if not cam or (listener and listener.Parent == cam) then
		return
	end
	if listener then
		listener:Destroy()
	end
	local l = Instance.new("AudioListener")
	l.Name = "VT65Ouvido"
	l.AudioInteractionGroup = GROUP
	l.Parent = cam
	wire(l, out, l)
	listener = l
end
placeListener()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(placeListener)

-- ===== cada voz =====
type Spk = { input: AudioDeviceInput?, emitter: AudioEmitter?, radio: Wire?, analyzer: AudioAnalyzer?, loudAt: number? }
local spk: { [Player]: Spk } = {}
local squadRadio: { [number]: boolean } = {} -- UserIds do meu squad com o rádio aberto (Voz_Estado)
local curve = Conversa.attenuationStuds(M)

local function inputOf(p: Player): AudioDeviceInput?
	local d = p:FindFirstChild("VT65Voz")
	return if d and d:IsA("AudioDeviceInput") then d else nil
end

local function isAlly(p: Player): boolean
	local f = player:GetAttribute("Faction")
	return p == player or (f ~= nil and p:GetAttribute("Faction") == f)
end

local function sameSquad(p: Player): boolean
	local sq = player:GetAttribute("SquadId")
	return type(sq) == "string" and p:GetAttribute("SquadId") == sq
end

local function clear(p: Player, s: Spk)
	for _, inst in { s.emitter, s.radio, s.analyzer } :: { Instance? } do
		if inst then
			inst:Destroy()
		end
	end
	s.emitter, s.radio, s.analyzer, s.input = nil, nil, nil, nil
	VozEstado.set(p.UserId, false, false)
end

local function update(p: Player)
	local s = spk[p]
	if not s then
		s = {}
		spk[p] = s
	end
	local s1 = s :: Spk
	local d = inputOf(p)
	if d ~= s1.input then
		clear(p, s1)
		s1.input = d
	end
	if not d then
		return
	end
	-- perto: emissor na cabeça (a cabeça troca com o uniforme; o corpo pode sair do streaming)
	if p ~= player then
		local char = p.Character
		local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
		if not head then
			if s1.emitter then
				s1.emitter:Destroy()
				s1.emitter = nil
			end
		elseif not (s1.emitter and s1.emitter.Parent == head) then
			if s1.emitter then
				s1.emitter:Destroy()
			end
			local e = Instance.new("AudioEmitter")
			e.Name = "VT65VozPerto"
			e.AudioInteractionGroup = GROUP
			e:SetDistanceAttenuation(curve)
			e.Parent = head
			wire(d, e, e)
			s1.emitter = e
		end
	end
	-- rádio: só companheiro do meu squad com o rádio aberto (o servidor só manda o som para o squad)
	local wantRadio = p ~= player and squadRadio[p.UserId] == true and sameSquad(p)
	if wantRadio and not s1.radio then
		local w = wire(d, radioIn, folder)
		w.Name = "Radio_" .. p.UserId
		s1.radio = w
	elseif not wantRadio and s1.radio then
		s1.radio:Destroy()
		s1.radio = nil
	end
	-- quem fala: só aliados (o ícone nunca aparece para inimigo)
	if isAlly(p) then
		if not s1.analyzer then
			local a = Instance.new("AudioAnalyzer")
			a.Name = "Fala_" .. p.UserId
			a.Parent = folder
			wire(d, a, a)
			s1.analyzer = a
		end
	elseif s1.analyzer then
		s1.analyzer:Destroy()
		s1.analyzer = nil
		VozEstado.set(p.UserId, false, false)
	end
end

Players.PlayerRemoving:Connect(function(p)
	local s = spk[p]
	if s then
		clear(p, s)
		spk[p] = nil
	end
	squadRadio[p.UserId] = nil
end)

-- ===== rádio: estado do squad (servidor) =====
Net.event("Voz_Estado").OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" or type(msg.radio) ~= "table" or msg.squad ~= player:GetAttribute("SquadId") then
		return
	end
	local now: { [number]: boolean } = {}
	for _, uid in msg.radio do
		if type(uid) == "number" then
			now[uid] = true
		end
	end
	-- clique de abrir e fechar dos companheiros (o meu toca no botão)
	local click = false
	for uid in now do
		if not squadRadio[uid] and uid ~= player.UserId then
			click = true
		end
	end
	for uid in squadRadio do
		if not now[uid] and uid ~= player.UserId then
			click = true
		end
	end
	squadRadio = now
	if click then
		squelch:Play()
	end
	VozEstado.setSelf(VozEstado.available, now[player.UserId] == true)
	for _, p in Players:GetPlayers() do
		update(p)
	end
end)

-- ===== meu rádio =====
local holding = false
local voiceOk = true -- até a conta dizer que este jogador não tem voz ligada

local function canTalk(): boolean
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	return voiceOk
		and hum ~= nil
		and hum.Health > 0
		and player:GetAttribute("Downed") ~= true
		and type(player:GetAttribute("SquadId")) == "string"
end

local function startTx()
	if holding or not canTalk() then
		return
	end
	holding = true
	squelch:Play()
	Net.event("Voz_Radio"):FireServer(true)
end

local function stopTx()
	if not holding then
		return
	end
	holding = false
	squelch:Play()
	Net.event("Voz_Radio"):FireServer(false)
end

Input.on("radio_talk", "press", startTx) -- teclado: Caps Lock
Input.on("radio_talk", "holdStart", startTx) -- controle: ↓ segurado
Input.on("radio_talk", "release", stopTx)
Input.on("radio_talk", "holdEnd", stopTx)
Input.StateChanged:Connect(function()
	if holding and not InputMap.acceptsGame(Input.state) then
		stopTx() -- menu, mapa ou menu do Roblox abriu com o botão apertado
	end
end)
player:GetAttributeChangedSignal("Downed"):Connect(function()
	if player:GetAttribute("Downed") then
		stopTx() -- caído: o soltar do botão não chega (só olhar, desistir e chamar ajuda)
	end
end)
player.CharacterRemoving:Connect(stopTx)

task.spawn(function()
	local ok, on = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)
	if ok and on == false then
		voiceOk = false
	end
	VozEstado.setSelf(ok and on == true, VozEstado.transmitting)
end)

-- ===== laços: 2 Hz para os nós, 5 Hz para quem fala =====
task.spawn(function()
	while true do
		task.wait(C.syncS)
		for _, p in Players:GetPlayers() do
			update(p)
		end
		if holding and not canTalk() then
			stopTx()
		end
	end
end)

local devUntil = 0
task.spawn(function()
	while true do
		task.wait(0.2)
		local now = os.clock()
		for p, s in spk do
			local a = s.analyzer
			if a then
				local talking, at = Conversa.speaking(a.RmsLevel, now, s.loudAt)
				s.loudAt = at
				if now < devUntil then
					talking = true
				end
				VozEstado.set(p.UserId, talking, squadRadio[p.UserId] == true or (now < devUntil and sameSquad(p)))
			end
		end
	end
end)

-- Studio: acende o ícone de fala de todos os aliados por 5 s (para ver o HUD sem ninguém falando)
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("VT65DevTela"):Connect(function()
		if workspace:GetAttribute("VT65DevTela") ~= "voz" then
			return
		end
		devUntil = os.clock() + 5
		for _, p in Players:GetPlayers() do
			if isAlly(p) then
				VozEstado.set(p.UserId, true, sameSquad(p))
			end
		end
		task.delay(5.3, function()
			for _, p in Players:GetPlayers() do
				local s = spk[p]
				if not (s and s.analyzer) then
					VozEstado.set(p.UserId, false, false)
				end
			end
		end)
		task.defer(function()
			workspace:SetAttribute("VT65DevTela", nil) -- local: no cliente, o mesmo valor repete
		end)
	end)
end
