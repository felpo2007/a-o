--!strict
-- Para onde vai o que o jogador digita (2026-11-12; canais em Modules/Comunicacao). Em campo o geral do
-- Roblox não envia (CanSend = false), então quem está com o geral como alvo passa para o canal de perto
-- (VT65Perto, 40 m); fora do campo, quem estava no de perto volta para o geral. Um canal escolhido pelo
-- jogador (squad, lado) não muda. A janela e as abas do chat são do JanelaChat (agente de interface):
-- este script só mexe no ChatInputBarConfiguration.TargetTextChannel, a 2 Hz.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

local function inField(): boolean
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function member(ch: TextChannel): boolean
	for _, s in ch:GetChildren() do
		if s:IsA("TextSource") and s.UserId == player.UserId then
			return true
		end
	end
	return false
end

-- pelo nome do servidor ou pelo tipo (atributo VT65Canal): o JanelaChat renomeia os canais VT65* no
-- cliente para o rótulo da aba ("Perto", "Squad"...), então o de perto se acha pelo tipo
local function channel(folder: Instance, name: string): TextChannel?
	local ch = folder:FindFirstChild(name)
	if not (ch and ch:IsA("TextChannel")) and name == "VT65Perto" then
		for _, c in folder:GetChildren() do
			if c:IsA("TextChannel") and c:GetAttribute("VT65Canal") == "perto" then
				ch = c
				break
			end
		end
	end
	return if ch and ch:IsA("TextChannel") and member(ch) then ch else nil
end

local function step()
	local bar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	local folder = TextChatService:FindFirstChild("TextChannels")
	if not (bar and folder) then
		return
	end
	local target = bar.TargetTextChannel
	local kind = if target then target:GetAttribute("VT65Canal") else nil
	if inField() then
		if target == nil or kind == "geral" or target.Name == "RBXGeneral" then
			local near = channel(folder, "VT65Perto")
			if near then
				bar.TargetTextChannel = near
			end
		end
	elseif kind == "perto" then
		local general = channel(folder, "RBXGeneral")
		if general then
			bar.TargetTextChannel = general
		end
	end
end

while true do
	task.wait(0.5)
	pcall(step)
end
