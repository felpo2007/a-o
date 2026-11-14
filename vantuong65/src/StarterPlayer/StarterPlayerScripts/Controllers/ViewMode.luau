--!strict
-- Estado da câmera (1ª ou 3ª pessoa) compartilhado entre os controllers. Quem escreve é o
-- ThirdPerson.client (a cada quadro); quem lê: WeaponController (origem e direção do tiro),
-- InfantryController (marcar), Movement.client.
-- Contrato com o WeaponVisuals: o atributo local Players.LocalPlayer "ThirdPersonView" é true
-- SÓ quando a câmera está de fato em 3ª pessoa (mistura ≥ Movement.VIEW_THRESHOLD); em 1ª pessoa,
-- inclusive mirando, é false.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Movement = require(ReplicatedStorage.Shared.Movement)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Movement.STUD_M

local ViewMode = {}
ViewMode.third = false -- câmera DE FATO em 3ª pessoa
ViewMode.alpha = 0 -- mistura 0 (1ª) .. 1 (3ª), já suavizada
ViewMode.eye = Vector3.zero -- olho do personagem (a câmera de 1ª pessoa) neste quadro

-- Botão de 1ª/3ª pessoa (2026-11-13, dono: "coloque o botão para 3ª pessoa"). A ação é "view_toggle"
-- (InputMap: O no teclado, direcional → segurado no controle; no toque, Input.virtual("view_toggle",
-- true/false) ou o botão "view" do Shared/Toque). Quem não passa pelo Input chama direto:
--   ViewMode.toggle()        alterna 1ª/3ª pessoa (salvo na conta; avisa se o modo não deixa)
--   ViewMode.swapShoulder()  troca o ombro da 3ª pessoa
--   ViewMode.wanted()        true se o jogador escolheu a 3ª pessoa
-- O ThirdPerson.client põe as funções aqui ao carregar.
ViewMode.toggle = (function() end) :: () -> ()
ViewMode.swapShoulder = (function() end) :: () -> ()
ViewMode.wanted = function(): boolean
	return false
end

-- O servidor pode desligar a 3ª pessoa por modo: workspace:SetAttribute("ThirdPersonAllowed", false).
function ViewMode.allowed(): boolean
	return workspace:GetAttribute("ThirdPersonAllowed") ~= false
end

-- Origem dos raios de jogo (tiro, marcar): o olho em 3ª pessoa; a própria câmera em 1ª.
function ViewMode.origin(): Vector3
	if ViewMode.third and ViewMode.eye.Magnitude > 0 then
		return ViewMode.eye
	end
	return camera.CFrame.Position
end

local function ignoreList(): { Instance }
	local list: { Instance } = { camera }
	if player.Character then
		table.insert(list, player.Character)
	end
	local fx = workspace:FindFirstChild("VT65Effects")
	if fx then
		table.insert(list, fx)
	end
	return list
end

-- Folhagem e lâmina d'água: não param a mira (a bala atravessa bambu e capim; Parte 3).
local function seeThrough(inst: Instance): boolean
	if not inst:IsA("BasePart") or inst.CanCollide then
		return false
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	return not (model and model:FindFirstChildOfClass("Humanoid"))
end

-- Ponto para onde a retícula (centro da tela) aponta. Em 3ª pessoa o raio começa na altura do olho
-- ao longo da linha de visada (o que fica entre a câmera e o personagem não conta).
function ViewMode.aimPoint(maxStuds: number): Vector3
	local cf = camera.CFrame
	local look = cf.LookVector
	local start = cf.Position
	if ViewMode.third then
		local t = math.max((ViewMode.eye - cf.Position):Dot(look), 0)
		start += look * t
	end
	local ignore = ignoreList()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local from, left = start, maxStuds
	for _ = 1, 5 do
		local r = workspace:Raycast(from, look * left, params)
		if not r then
			break
		end
		if not seeThrough(r.Instance) then
			return r.Position
		end
		table.insert(ignore, r.Instance)
		params.FilterDescendantsInstances = ignore
		left -= (r.Position - from).Magnitude
		from = r.Position
	end
	return start + look * maxStuds
end

-- Direção do tiro: em 1ª pessoa, a linha de visada; em 3ª, do olho até o ponto da retícula (a bala
-- nunca sai da câmera, que pode estar atrás de uma parede no ombro).
function ViewMode.aimDirection(): (Vector3, Vector3)
	local cf = camera.CFrame
	if not ViewMode.third then
		return cf.Position, cf.LookVector
	end
	local o = ViewMode.origin()
	local p = ViewMode.aimPoint(1500 / M)
	local d = p - o
	if d.Magnitude < 2 or d.Unit:Dot(cf.LookVector) < 0.2 then
		return o, cf.LookVector -- alvo colado no ombro ou atrás do olho: segue a linha de visada
	end
	return o, d.Unit
end

-- Dispersão do quadril em 3ª pessoa (graus), pela velocidade, fôlego e postura (Movement).
function ViewMode.hipSpread(): number
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and root) then
		return 0
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude * M
	local st = player:GetAttribute("Stamina")
	local stance = if char:GetAttribute("Prone") == true
		then "prone"
		elseif char:GetAttribute("Crouched") == true then "crouch"
		else "stand"
	return Movement.hipSpreadDeg(speed, if type(st) == "number" then st else 1, stance)
end

return ViewMode
