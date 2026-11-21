--!strict
-- Conversa no campo, lado do servidor (pedido do dono, 2026-11-12: "permita falar pelo jogo com quem
-- está perto e com o seu batalhão"). Regras puras em Shared/Conversa.
--
-- Texto (TextChatService; o filtro de texto do Roblox vale em todos os canais):
--   VT65Perto: quem está em campo; cada mensagem só chega a quem está a até 40 m de quem escreveu
--     (ShouldDeliverCallback, na hora do envio: exato, sem custo por quadro);
--   VT65Squad_<lado>_<nome>: um por squad, com os membros do squad (em campo ou não);
--   lado: o RBXTeam<cor> que o Roblox cria para cada Team (o canal "equipe", /t), se existir; senão
--     VT65Lado_<lado>, mantido aqui;
--   RBXGeneral (geral do Roblox): só fora do campo. Em campo não envia (CanSend = false) nem recebe.
--   Membros: 2 Hz, mexendo só no que mudou. Todo canal leva o atributo VT65Canal ("perto", "squad",
--   "lado", "geral") para as abas da janela do chat (JanelaChat, do agente de interface).
--
-- Voz (API de áudio; default.project.json: VoiceChatService.UseAudioApi = Enabled e
-- EnableDefaultVoice = false, então a voz é toda montada pelo jogo):
--   um AudioDeviceInput "VT65Voz" em cada Player, com AccessType = Allow e a lista de quem pode receber
--   o som (Conversa.voiceAllow, 2 Hz e na hora em que o rádio abre ou fecha): quem está em campo a até
--   50 m e, só com o rádio aberto, o próprio squad. Inimigo longe nunca recebe o som.
--   Rádio: Voz_Radio (c->s true/false), validado (em campo, de pé, com squad; fecha sozinho em 60 s);
--   Voz_Estado (s->c { squad, radio = { UserId } }) só para os membros do squad.
--
-- Studio: workspace:SetAttribute("VT65DevConversa", true) imprime no Output ([VT65 CONVERSA]) a
-- configuração da voz, as listas de cada voz e os membros de cada canal.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local VoiceChatService = game:GetService("VoiceChatService")

local Conversa = require(ReplicatedStorage.Shared.Conversa)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)

local Comunicacao = {}
local M = MapConfig.STUD_M
local C = Conversa.C

-- ===== quem é quem (2 Hz) =====
local radioOn: { [Player]: number } = {} -- quem está no rádio (instante em que abriu)
local lastToggle: { [Player]: number } = {}
local who: { [Player]: Conversa.Who } = {}
local byUser: { [number]: Conversa.Who } = {}

local function whoOf(p: Player): Conversa.Who
	local c = p.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	local inField = hum ~= nil and root ~= nil and hum.Health > 0
	local pos = if root then root.Position else Vector3.zero
	local f, sq = p:GetAttribute("Faction"), p:GetAttribute("SquadId")
	return {
		userId = p.UserId,
		faction = if type(f) == "string" then f else nil,
		squad = if type(sq) == "string" then sq else nil,
		inField = inField,
		downed = c ~= nil and c:GetAttribute("Downed") == true,
		x = pos.X * M,
		z = pos.Z * M,
		radio = radioOn[p] ~= nil,
	}
end

local function refreshWho(): { Conversa.Who }
	table.clear(who)
	table.clear(byUser)
	local all = {}
	for _, p in Players:GetPlayers() do
		local w = whoOf(p)
		who[p] = w
		byUser[p.UserId] = w
		table.insert(all, w)
	end
	return all
end

-- posição na hora (o chat de perto confere no envio, não na última conta)
local function whoNow(userId: number): Conversa.Who?
	local p = Players:GetPlayerByUserId(userId)
	return if p then whoOf(p) else nil
end

-- ===== texto =====
local textOn = false
local channelsFolder: Instance? = nil
local nearChannel: TextChannel? = nil
local squadChannels: { [string]: TextChannel } = {}
local sideChannels: { [string]: TextChannel } = {} -- canais VT65Lado_* (só quando não há RBXTeam)
local adding: { [TextChannel]: { [number]: boolean } } = {}

local function newChannel(name: string, kind: string): TextChannel
	local ch = Instance.new("TextChannel")
	ch.Name = name
	ch:SetAttribute("VT65Canal", kind)
	ch.Parent = channelsFolder
	return ch
end

local function sourcesOf(ch: TextChannel): { [number]: TextSource }
	local out: { [number]: TextSource } = {}
	for _, s in ch:GetChildren() do
		if s:IsA("TextSource") then
			out[s.UserId] = s
		end
	end
	return out
end

-- deixa o canal com exatamente estes membros (AddUserAsync cede a vez: roda à parte, sem repetir)
local function syncMembers(ch: TextChannel, want: { [number]: boolean })
	local have = sourcesOf(ch)
	for uid, s in have do
		if not want[uid] then
			s:Destroy() -- é assim que se tira alguém de um TextChannel
		end
	end
	local pending = adding[ch] or {}
	adding[ch] = pending
	for uid in want do
		if not have[uid] and not pending[uid] then
			pending[uid] = true
			task.spawn(function()
				pcall(function()
					ch:AddUserAsync(uid)
				end)
				pending[uid] = nil
			end)
		end
	end
end

-- canal do lado: o RBXTeam<cor> do Roblox, se existir
local function teamChannel(faction: string): TextChannel?
	local teams = game:GetService("Teams")
	local t = teams:FindFirstChild(faction)
	if not (t and t:IsA("Team") and channelsFolder) then
		return nil
	end
	local ch = (channelsFolder :: Instance):FindFirstChild("RBXTeam" .. t.TeamColor.Name)
	return if ch and ch:IsA("TextChannel") then ch else nil
end

local function syncText(all: { Conversa.Who })
	if not textOn then
		return
	end
	local want = Conversa.members(all)
	if nearChannel then
		syncMembers(nearChannel, want.near)
	end
	-- squads: um canal por squad com gente; o que esvaziou some
	for sid, set in want.squads do
		local ch = squadChannels[sid]
		if not ch or ch.Parent == nil then
			local nc = newChannel(Conversa.squadChannel(sid), "squad")
			nc:SetAttribute("VT65Squad", sid)
			nc:SetAttribute("VT65Nome", string.match(sid, ":(.+)$") or sid)
			squadChannels[sid] = nc
			ch = nc
		end
		syncMembers(ch :: TextChannel, set)
	end
	for sid, ch in squadChannels do
		if not want.squads[sid] then
			ch:Destroy()
			adding[ch] = nil
			squadChannels[sid] = nil
		end
	end
	-- lado: o RBXTeam do Roblox (membros pelo Team, que é o lado) ou o nosso
	for _, faction in { "US", "VC" } do
		local team = teamChannel(faction)
		local own = sideChannels[faction]
		if team then
			if not team:GetAttribute("VT65Canal") then
				team:SetAttribute("VT65Canal", "lado")
				team:SetAttribute("VT65Lado", faction)
			end
			if own then
				own:Destroy()
				adding[own] = nil
				sideChannels[faction] = nil
			end
		else
			if not own or own.Parent == nil then
				local nc = newChannel("VT65Lado_" .. faction, "lado")
				nc:SetAttribute("VT65Lado", faction)
				sideChannels[faction] = nc
				own = nc
			end
			syncMembers(own :: TextChannel, want.sides[faction] or {})
		end
	end
	-- geral do Roblox: em campo não envia
	local general = channelsFolder and (channelsFolder :: Instance):FindFirstChild("RBXGeneral")
	if general and general:IsA("TextChannel") then
		for uid, s in sourcesOf(general) do
			local w = byUser[uid]
			local can = not (w and w.inField)
			if s.CanSend ~= can then
				s.CanSend = can
			end
		end
	end
end

local function startText()
	local okVersion = pcall(function()
		assert(TextChatService.ChatVersion == Enum.ChatVersion.TextChatService)
	end)
	if not okVersion then
		warn("[VT65] conversa: o chat do place não é o TextChatService; canais de texto desligados")
		return
	end
	channelsFolder = TextChatService:WaitForChild("TextChannels", 15)
	if not channelsFolder then
		local f = Instance.new("Folder")
		f.Name = "TextChannels"
		f.Parent = TextChatService
		channelsFolder = f
	end
	textOn = true
	local near = newChannel("VT65Perto", "perto")
	near.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource): boolean
		local from = message.TextSource
		if not from then
			return false
		end
		return Conversa.nearText(whoNow(from.UserId), whoNow(target.UserId))
	end
	nearChannel = near
	local function hookGeneral(ch: Instance)
		if ch.Name == "RBXGeneral" and ch:IsA("TextChannel") then
			ch:SetAttribute("VT65Canal", "geral")
			ch.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource): boolean
				local from = message.TextSource
				if not from then
					return true -- mensagem do sistema
				end
				return Conversa.generalText(whoNow(from.UserId), whoNow(target.UserId))
			end
		end
	end
	for _, ch in (channelsFolder :: Instance):GetChildren() do
		hookGeneral(ch)
	end
	(channelsFolder :: Instance).ChildAdded:Connect(hookGeneral)
end

-- ===== voz =====
local voiceOn = false
local lastAllow: { [Player]: { number } } = {}

local function inputOf(p: Player): AudioDeviceInput?
	local d = p:FindFirstChild("VT65Voz")
	return if d and d:IsA("AudioDeviceInput") then d else nil
end

local function ensureInput(p: Player)
	if inputOf(p) then
		return
	end
	local d = Instance.new("AudioDeviceInput")
	d.Name = "VT65Voz"
	d.Player = p
	d.AccessType = Enum.AccessModifierType.Allow
	d.Muted = false -- microfone aberto para a voz de perto; o botão de microfone do Roblox continua valendo
	d:SetUserIdAccessList({}) -- ninguém ouve até a primeira conta
	d.Parent = p
	lastAllow[p] = {}
end

local function updateAllow(p: Player, all: { Conversa.Who })
	local d = inputOf(p)
	local w = who[p]
	if not (voiceOn and d and w) then
		return
	end
	local allow = Conversa.voiceAllow(w, all)
	if not Conversa.sameIds(allow, lastAllow[p] or {}) then
		lastAllow[p] = allow
		d:SetUserIdAccessList(allow)
	end
end

-- Lê uma propriedade do VoiceChatService que o script pode não ter permissão de ler (nil = não deu).
local function voiceProp(name: string): any
	local ok, v = pcall(function()
		return (VoiceChatService :: any)[name]
	end)
	return if ok then v else nil
end

local function startVoice()
	local api = voiceProp("UseAudioApi")
	local default = voiceProp("EnableDefaultVoice")
	if api ~= nil and api ~= Enum.AudioApiRollout.Enabled then
		warn("[VT65] voz: VoiceChatService.UseAudioApi não está em Enabled; fica a voz padrão do Roblox, sem rádio")
		return
	end
	if default == true then
		warn("[VT65] voz: EnableDefaultVoice ligado; fica a voz padrão do Roblox, sem rádio nem alcance de 40 m")
		return
	end
	voiceOn = true
	for _, p in Players:GetPlayers() do
		ensureInput(p)
	end
	Players.PlayerAdded:Connect(ensureInput)
end

-- ===== rádio do squad =====
local function pushSquad(sid: string?)
	if not sid then
		return
	end
	local on = {}
	local members = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("SquadId") == sid then
			table.insert(members, p)
			if radioOn[p] then
				table.insert(on, p.UserId)
			end
		end
	end
	for _, p in members do
		Net.event("Voz_Estado"):FireClient(p, { squad = sid, radio = on })
	end
end

local function setRadio(p: Player, on: boolean)
	if (radioOn[p] ~= nil) == on then
		return
	end
	if on then
		radioOn[p] = os.clock()
	else
		radioOn[p] = nil
	end
	if who[p] then
		who[p].radio = on
	end
	local sq = p:GetAttribute("SquadId")
	pushSquad(if type(sq) == "string" then sq else nil)
	local all = {}
	for _, w in who do
		table.insert(all, w)
	end
	updateAllow(p, all)
end

local function onRadio(p: Player, on: any)
	if type(on) ~= "boolean" then
		return
	end
	local now = os.clock()
	if now - (lastToggle[p] or 0) < C.radioMinGapS and on then
		return
	end
	lastToggle[p] = now
	if on then
		local w = whoOf(p)
		if Conversa.radioCheck(w.inField, w.downed, w.squad) then
			pushSquad(w.squad) -- o cliente acerta o estado (não está no rádio)
			return
		end
	end
	setRadio(p, on)
end

-- ===== laço =====
local function step()
	local all = refreshWho()
	local now = os.clock()
	-- rádio: fecha quem caiu, saiu do campo, perdeu o squad ou esqueceu o botão apertado
	for p, t0 in radioOn do
		local w = who[p]
		if not w or Conversa.radioCheck(w.inField, w.downed, w.squad) or now - t0 > C.radioMaxS then
			setRadio(p, false)
		end
	end
	syncText(all)
	if voiceOn then
		for _, p in Players:GetPlayers() do
			ensureInput(p)
			updateAllow(p, all)
		end
	end
end

local function devReport()
	print(
		string.format(
			"[VT65 CONVERSA] voz: UseAudioApi=%s EnableDefaultVoice=%s ligada=%s; texto=%s",
			tostring(voiceProp("UseAudioApi")),
			tostring(voiceProp("EnableDefaultVoice")),
			tostring(voiceOn),
			tostring(textOn)
		)
	)
	for _, p in Players:GetPlayers() do
		local d = inputOf(p)
		local w = who[p]
		print(
			string.format(
				"[VT65 CONVERSA] %s: em campo=%s squad=%s rádio=%s voz=%s ouvem=%s",
				p.Name,
				tostring(w and w.inField),
				tostring(w and w.squad),
				tostring(radioOn[p] ~= nil),
				tostring(d ~= nil),
				if d then table.concat(d:GetUserIdAccessList(), ",") else "-"
			)
		)
	end
	if channelsFolder then
		for _, ch in (channelsFolder :: Instance):GetChildren() do
			if ch:IsA("TextChannel") then
				local ids = {}
				for uid in sourcesOf(ch) do
					table.insert(ids, tostring(uid))
				end
				print(
					string.format(
						"[VT65 CONVERSA] canal %s (%s): %s",
						ch.Name,
						tostring(ch:GetAttribute("VT65Canal")),
						table.concat(ids, ",")
					)
				)
			end
		end
	end
end

function Comunicacao.start()
	Net.event("Voz_Radio").OnServerEvent:Connect(onRadio)
	Players.PlayerRemoving:Connect(function(p)
		local sq = p:GetAttribute("SquadId")
		local was = radioOn[p] ~= nil
		radioOn[p] = nil
		lastToggle[p] = nil
		lastAllow[p] = nil
		if was then
			pushSquad(if type(sq) == "string" then sq else nil)
		end
	end)
	-- troca de squad: quem entra fica sabendo quem está no rádio; o rádio de quem sai fecha
	local function watch(p: Player)
		local prev = p:GetAttribute("SquadId")
		p:GetAttributeChangedSignal("SquadId"):Connect(function()
			if radioOn[p] then
				radioOn[p] = nil
			end
			pushSquad(if type(prev) == "string" then prev else nil)
			prev = p:GetAttribute("SquadId")
			pushSquad(if type(prev) == "string" then prev else nil)
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	startVoice()
	task.spawn(startText)
	task.spawn(function()
		while true do
			task.wait(C.syncS)
			local ok, err = pcall(function(): any
				step()
				return nil
			end)
			if not ok then
				warn("[VT65] conversa:", err)
			end
		end
	end)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevConversa"):Connect(function()
			if workspace:GetAttribute("VT65DevConversa") then
				devReport()
			end
		end)
	end
end

return Comunicacao
