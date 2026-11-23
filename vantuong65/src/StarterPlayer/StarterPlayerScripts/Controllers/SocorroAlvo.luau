--!strict
-- D-236: os companheiros vistos deste cliente e quem o soldado socorre agora (regra em Shared/Socorro).
-- Usado pela tecla de interagir (MedicalController), pelo botão do toque (Interagir) e pelo SocorroHud.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Socorro = require(ReplicatedStorage.Shared.Socorro)

local SocorroAlvo = {}

local M = 0.28
local player = Players.LocalPlayer

export type Item = {
	model: Model,
	head: BasePart,
	nome: string,
	info: Socorro.Aliado,
	cuidando: boolean, -- alguém já está cuidando dele
}

SocorroAlvo.curativos = 0
Net.event("Medical_State").OnClientEvent:Connect(function(s: any)
	if type(s) == "table" and type(s.bandages) == "number" then
		SocorroAlvo.curativos = s.bandages
	end
end)

function SocorroAlvo.medico(): boolean
	return player:GetAttribute("Role") == "medic"
end

local function nomeDe(m: Model, dono: Player?): string
	if dono then
		return dono.DisplayName
	end
	local role = m:GetAttribute("Role")
	local def = if type(role) == "string" then Roles.roles[role] else nil
	return if def then tostring(def.name) else "Companheiro"
end

-- Todos os companheiros vivos com corpo neste cliente, com o que cada um precisa
function SocorroAlvo.aliados(): { Item }
	local out: { Item } = {}
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = workspace.CurrentCamera
	if not (char and root and cam) then
		return out
	end
	local lado = player:GetAttribute("Faction")
	local olho = cam.CFrame.Position
	local mira = cam.CFrame.LookVector
	local function ve(m: Model, dono: Player?)
		if m == char or m:GetAttribute("Faction") ~= lado then
			return
		end
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		local head = (m:FindFirstChild("Head") or r) :: BasePart?
		local h = m:FindFirstChildOfClass("Humanoid")
		if not (r and head and h) or h.Health <= 0 then
			return
		end
		local downed = m:GetAttribute("Downed") == true or (dono ~= nil and dono:GetAttribute("Downed") == true)
		local bleeding = m:GetAttribute("VT65Sangra") == true
		local frac = if downed then 0 else math.clamp(h.Health / math.max(h.MaxHealth, 1), 0, 1)
		local para = head.Position - olho
		local ang = if para.Magnitude > 0.01 then math.deg(math.acos(math.clamp(mira:Dot(para.Unit), -1, 1))) else 0
		table.insert(out, {
			model = m,
			head = head,
			nome = nomeDe(m, dono),
			cuidando = m:GetAttribute("VT65Cuidando") == true,
			info = {
				downed = downed,
				bleeding = bleeding,
				hurt = h.Health < h.MaxHealth - 1,
				frac = frac,
				distM = (r.Position - root.Position).Magnitude * M,
				angDeg = ang,
			},
		})
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			ve(p.Character, p)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
				ve(m, nil)
			end
		end
	end
	return out
end

-- Quem a tecla de interagir socorre agora: o mais urgente ao alcance
function SocorroAlvo.alvo(lista: { Item }?): Item?
	local melhor: Item? = nil
	local nota = math.huge
	for _, it in lista or SocorroAlvo.aliados() do
		if it.info.distM <= Socorro.ALCANCE_M and Socorro.precisa(it.info) then
			local n = Socorro.nota(it.info)
			if n < nota then
				melhor, nota = it, n
			end
		end
	end
	return melhor
end

function SocorroAlvo.acao(it: Item): Socorro.Acao?
	return Socorro.acao(it.info, SocorroAlvo.medico(), SocorroAlvo.curativos)
end

return SocorroAlvo
