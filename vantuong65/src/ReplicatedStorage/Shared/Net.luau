--!strict
-- Remotes do jogo. O servidor cria (Net.server()), o cliente espera (Net.get()).
-- Eventos confiáveis: RemoteEvent; estado frequente/efeitos: UnreliableRemoteEvent (Parte 7).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	"Commerce_Equip", -- c->s: faction, slot, cosmeticId
	"Commerce_Track", -- c->s: passo do funil da loja
	"Commerce_State", -- s->c: estado de posse/equipados
	"PrivateServer_SetOptions", -- c->s: dono do servidor privado
	"Team_Choose", -- c->s: "US" | "VC"
	"Squad_Action", -- c->s: { op = "create"|"join"|"leave", ... }
	"Role_Choose", -- c->s: roleId
	"Spawn_Request", -- c->s: spawnPointId
	"Spawn_State", -- s->c: pontos e esperas
	"Combat_Fire", -- c->s: tiro (origem, direção, t, semente)
	"Combat_Reload", -- c->s: recarregar
	"Combat_Ammo", -- s->c: munição autoritativa (sem hitmarker: o servidor não confirma acertos)
	"Medical_Action", -- c->s: { op = "bandage"|"tourniquet"|"treat"|"revive"|"giveup", target? }
	"Medical_State", -- s->c: estado do próprio corpo
	"Match_State", -- s->c: setores, pontos fortes, tempo
	"Squad_State", -- s->c: squads do próprio time
	"Posture_Set", -- c->s: agachar (true/false)
	"Commander_Request", -- c->s: { ability, grid?, correction?, confirm? } (comandante e morteiro)
	"Commander_State", -- s->c: suprimento, recargas, avisos e erros
	"Build_Request", -- c->s: { kind } (logística)
	"Logistics_State", -- s->c: erro de construção
	"Vehicle_Fire", -- c->s: { dir } (arma do assento ou foguete antitanque)
	"Vehicle_Reload", -- c->s: recarga do Ontos (parado) / troca de munição do 90 mm
	"Vehicle_SwitchSeat", -- c->s: próximo assento livre permitido ao papel
	"Input_Type", -- c->s: "gamepad" | "kbm" | "touch" (equilíbrio controle x mouse)
	"Settings_Save", -- c->s: configurações de controle (saneadas no servidor)
	"Squad_Mark", -- c->s { x, y, z } / s->c { x, y, z, from, kind }: marcação para o squad
	"Squad_Message", -- c->s { id, channel } / s->c { id, from, channel }: mensagens predefinidas
	"Throw_Request", -- c->s { kind = "frag" | "smoke", dir }
	"Combat_Melee", -- c->s { dir }: coronhada ou baioneta
	"Combat_Hit", -- s->c { x, y, z }: origem do tiro que acertou (vibração do lado do impacto)
}
Net.Unreliable = {
	"Combat_Tracer", -- s->c: traçantes/efeitos de outros jogadores
	"Fire_Impact", -- s->c: explosão { id, x, y, z }
	"Fire_Incoming", -- s->c: assobio de granada chegando { x, y, z }
	"Fire_Launch", -- s->c: disparo de morteiro/canhão/naval/foguete { kind, x, y, z }
}
Net.Functions = {
	"Commerce_GetState",
	"Settings_Get",
}

local folderName = "VT65Remotes"

function Net.server(): Folder
	assert(RunService:IsServer(), "Net.server só no servidor")
	local f = ReplicatedStorage:FindFirstChild(folderName) :: Folder?
	if f then
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	for _, n in Net.Events do
		local r = Instance.new("RemoteEvent")
		r.Name = n
		r.Parent = folder
	end
	for _, n in Net.Unreliable do
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = n
		r.Parent = folder
	end
	for _, n in Net.Functions do
		local r = Instance.new("RemoteFunction")
		r.Name = n
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

function Net.event(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(folderName)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	local folder = ReplicatedStorage:WaitForChild(folderName)
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

function Net.func(name: string): RemoteFunction
	local folder = ReplicatedStorage:WaitForChild(folderName)
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
