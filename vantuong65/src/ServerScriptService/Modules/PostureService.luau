--!strict
-- Postura (Parte 10.5 e 12.2): em pé, agachado, deitado, inclinado e correndo. O servidor é a
-- autoridade: muda HipHeight e velocidade (MedicalService.apply) e grava atributos no modelo; os
-- clientes posam todo mundo pelos atributos (PostureController). Não deixa levantar sob teto baixo.
-- Movimento (2026-11-11): o fôlego mora no cliente (Movement.client); aqui há um orçamento de corrida
-- MAIS FOLGADO (Movement.serverBudgetStep) que só corta quem ignora o fôlego. "Vaulting" (transpor)
-- vai para o modelo por ~1 s para os outros clientes dobrarem as pernas.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemAnim = require(ReplicatedStorage.Shared.ItemAnim)
local Joints = require(ReplicatedStorage.Shared.Joints)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local SoldierAnims = require(ReplicatedStorage.Shared.SoldierAnims)
local Combatants = require(script.Parent.Combatants)
local MedicalService = require(script.Parent.MedicalService)

local PostureService = {}
-- studs que o HumanoidRootPart desce (a câmera desce junto). D-94: agachado 2,2 -> 1,03, o quanto a
-- cabeça desce nos clipes agachados (tools/anim: de 1,506 m de pé para 1,218 m de joelho e 1,219 m
-- andando agachado = 0,288 m). Com 2,2 a câmera ficava ~33 cm abaixo da cabeça da animação.
-- Mudou aqui? Regrave os clipes agachados e deitados no tools/anim (o teste anim confere).
-- D-98 (soldado de 2,0 m, Shared/Corpo.K = 8/7): DROP, MIN_HIP e a descida do PRONE_ROOT são os
-- da D-94 vezes K (1,03 -> 1,1771; 4,4 -> 5,0286; 0,2 -> 0,2286; −0,6 -> −0,6857). Assim o HipHeight
-- de cada postura cresce na mesma proporção do corpo e os clipes gravados no corpo de 1,75 m tocam
-- sem regravar (o Animator escala a Root por HipHeight / AuthoredHipHeight).
local DROP = { crouch = 1.1771, prone = 5.0286 }
-- HipHeight nunca negativo: com 2,4 − 4,4 = −2 o Humanoid ficava em queda livre o tempo todo e
-- deitado em encosta virava escorregador (66 m/s no teste do Studio, 2026-11-10).
local MIN_HIP = 0.2286
-- Deitado: o SERVIDOR deita o corpo (junta Root), para os acertos (raycast no servidor) baterem
-- com o que se vê. Antes só os clientes posavam e o "deitado" do servidor era o corpo enterrado.
local PRONE_ROOT = CFrame.new(0, -0.6857, 0) * CFrame.Angles(math.rad(-85), 0, 0)

-- Motor6D ou AnimationConstraint (Shared/Joints): com a atualização de juntas do Roblox, a junta
-- Root virou AnimationConstraint e o corpo deixou de deitar (reteste no Studio, 2026-11-10).
local function setProneJoint(model: Model, prone: boolean)
	local lower = model:FindFirstChild("LowerTorso")
	local root = lower and Joints.find(lower, "Root")
	if not root then
		return
	end
	local orig = Joints.rest(root)
	if not orig then
		return
	end
	Joints.setC0(root, if prone then orig * PRONE_ROOT else orig)
end

-- Deitado, o corpo encosta no chão. Com a colisão normal o soldado era empurrado e escorregava
-- (reteste no Studio, 2026-11-10: 70 m em 5 s numa encosta de 14°), e o Humanoid religa o
-- CanCollide do tronco. Por isso, grupos de colisão: o corpo deitado não colide com o terreno
-- ("Ground"), mas os dois continuam colidindo com o grupo padrão, e os raycasts dos tiros (grupo
-- Default) ainda acertam o corpo. O HumanoidRootPart fica no Default e segura o soldado pelo HipHeight.
local GROUND, PRONE_BODY = "Ground", "ProneBody"
-- D-107: deitado (ou caído), a HumanoidRootPart continua EM PÉ (caixa de ~0,8 m acima do quadril) e a
-- bala do servidor a acertava como "tronco" no ar, acima do corpo deitado. Fora das consultas
-- enquanto deitado; a visão dos bots mira a cabeça e não muda.
local function setProneCollision(model: Model, prone: boolean)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if p.Name ~= "HumanoidRootPart" then
				p.CollisionGroup = if prone then PRONE_BODY else "Default"
			elseif p.Parent == model then
				p.CanQuery = not prone
			end
		end
	end
end

local function headroom(model: Model, need: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local head = model:FindFirstChild("Head") :: BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if head then head.Position elseif root then root.Position else nil
	return from == nil or workspace:Raycast(from, Vector3.new(0, need + 0.3, 0), params) == nil
end

-- stance: "stand" | "crouch" | "prone"
local function setStance(model: Model, stance: string): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or model:GetAttribute("Downed") then
		return false
	end
	local cur = if model:GetAttribute("Prone")
		then "prone"
		elseif model:GetAttribute("Crouched") then "crouch"
		else "stand"
	if cur == stance then
		return true
	end
	local curDrop = if cur == "stand" then 0 else DROP[cur]
	local newDrop = if stance == "stand" then 0 else DROP[stance]
	if newDrop < curDrop and not headroom(model, curDrop - newDrop) then
		return false -- sem espaço para subir (túnel, teto baixo)
	end
	local base = model:GetAttribute("BaseHipHeight")
	if type(base) ~= "number" then
		base = hum.HipHeight
		model:SetAttribute("BaseHipHeight", base)
	end
	hum.HipHeight = math.max((base :: number) - newDrop, MIN_HIP)
	setProneJoint(model, stance == "prone")
	setProneCollision(model, stance == "prone")
	model:SetAttribute("Crouched", stance == "crouch")
	model:SetAttribute("Prone", stance == "prone")
	if stance ~= "stand" then
		model:SetAttribute("Sprinting", false)
	end
	if stance == "prone" then
		model:SetAttribute("Lean", 0)
	end
	MedicalService.apply(model)
	return true
end
PostureService.setStance = setStance

function PostureService.setCrouch(model: Model, on: boolean): boolean
	return setStance(model, if on then "crouch" else "stand")
end

-- Caído (D-107, "os feridos estão de pé ao invés de deitados"): o MedicalService chama isto
-- (gancho onDowned) quando "Downed" muda, para jogador e bot. Caído = deitado DE COSTAS: HipHeight
-- do deitado, junta Root girada SoldierAnims.DOWNED e erguida até as costas encostarem no chão (no
-- servidor, sem clipe, é o que a bala acerta), grupo do deitado e "Prone" (câmera baixa, rastejo
-- zero, bots o veem deitado). A pose dos braços e das pernas é dos clientes (Controllers/MorteFx).
-- Parado no lugar: sem girar com a câmera (AutoRotate volta ao levantar). Reanimado: de bruços e,
-- se couber, agachado (o SoldierAnimations levanta suave do C0 de costas).
-- orig = repouso da Root (no R15, na base da HumanoidRootPart: a base fica a HipHeight do chão);
-- se o Attachment estiver noutra altura, desconta.
local function downedRoot(model: Model, hip: number, orig: CFrame): CFrame
	local lower = model:FindFirstChild("LowerTorso") :: BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local half = if lower then lower.Size.Z / 2 else 0.7143
	local off = if hrp then hrp.Size.Y / 2 + orig.Position.Y else 0
	local D = SoldierAnims.DOWNED
	return CFrame.new(0, SoldierAnims.downedRootY(half, hip) - off, 0) * CFrame.Angles(math.rad(D.pitchDeg), 0, 0)
end

function PostureService.setDowned(model: Model, on: boolean)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.SeatPart ~= nil then
		return -- morto (o CorposService cuida) ou no assento do veículo (fica sentado)
	end
	local base = model:GetAttribute("BaseHipHeight")
	if type(base) ~= "number" then
		base = hum.HipHeight
		model:SetAttribute("BaseHipHeight", base)
	end
	if on then
		local hip = math.max((base :: number) - DROP.prone, MIN_HIP)
		hum.HipHeight = hip
		local lower = model:FindFirstChild("LowerTorso")
		local root = lower and Joints.find(lower, "Root")
		local orig = root and Joints.rest(root)
		if root and orig then
			Joints.setC0(root, orig * downedRoot(model, hip, orig))
		end
		setProneCollision(model, true)
		model:SetAttribute("Crouched", false)
		model:SetAttribute("Prone", true)
		model:SetAttribute("Sprinting", false)
		model:SetAttribute("Lean", 0)
		model:SetAttribute("VT65LevantouT", nil)
		model:SetAttribute("VT65CaidoT", workspace:GetServerTimeNow()) -- a queda dos clientes começa aqui
		if model:GetAttribute("VT65GiroAntes") == nil then
			model:SetAttribute("VT65GiroAntes", hum.AutoRotate)
		end
		hum.AutoRotate = false
		return
	end
	model:SetAttribute("VT65CaidoT", nil)
	local was = model:GetAttribute("VT65GiroAntes")
	model:SetAttribute("VT65GiroAntes", nil)
	if type(was) == "boolean" then
		hum.AutoRotate = was
	end
	setProneJoint(model, true) -- de bruços: o deitado de sempre
	model:SetAttribute("VT65LevantouT", workspace:GetServerTimeNow())
	setStance(model, "crouch")
end

-- orçamento de corrida por jogador (0..1), folgado de propósito (ver Movement.SERVER_*)
local budget: { [Player]: number } = {}
local cartaAt: { [Player]: number } = {} -- última troca da carta na mão (D-98)
local itemAt: { [Player]: number } = {} -- última troca do item na mão (D-99)
local budgetChar: { [Player]: Model? } = {}

function PostureService.start()
	for _, g in { GROUND, PRONE_BODY } do
		if not PhysicsService:IsCollisionGroupRegistered(g) then
			PhysicsService:RegisterCollisionGroup(g)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(PRONE_BODY, GROUND, false)
	workspace.Terrain.CollisionGroup = GROUND
	MedicalService.onDowned = PostureService.setDowned -- D-107: caído deita de costas
	Players.PlayerRemoving:Connect(function(p)
		budget[p] = nil
		budgetChar[p] = nil
		cartaAt[p] = nil
		itemAt[p] = nil
	end)
	task.spawn(function()
		local DT = 0.25
		while true do
			task.wait(DT)
			for _, p in Players:GetPlayers() do
				local char = p.Character
				if budgetChar[p] ~= char then
					budgetChar[p] = char
					budget[p] = 1 -- renasceu descansado (o cliente também zera o cansaço)
				end
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local v = if root then root.AssemblyLinearVelocity else Vector3.zero
				-- só gasta correndo de verdade (como o cliente), não com a corrida ligada e parado
				local running = char ~= nil
					and char:GetAttribute("Sprinting") == true
					and Vector3.new(v.X, 0, v.Z).Magnitude * Movement.STUD_M > Movement.SPRINT_COUNT_MPS
				local b = Movement.serverBudgetStep(budget[p] or 1, DT, running)
				budget[p] = b
				if running and b <= 0 and char then
					char:SetAttribute("Sprinting", false)
					MedicalService.apply(char)
				end
				-- D-98: caído, sentado ou morto, a carta sai da mão (D-99: e o item também)
				if char and (char:GetAttribute("Carta") or char:GetAttribute("VT65Item")) then
					local hum = char:FindFirstChildOfClass("Humanoid")
					if not hum or hum.Health <= 0 or hum.SeatPart ~= nil or char:GetAttribute("Downed") then
						char:SetAttribute("Carta", nil)
						char:SetAttribute("VT65Item", nil)
					end
				end
			end
		end
	end)
	Net.event("Posture_Set").OnServerEvent:Connect(function(player, req: any)
		local char = player.Character
		if not (char and Combatants.get(char)) then
			return
		end
		if type(req) == "table" and (req.vault == "vault" or req.vault == "mantle") then
			-- transpor: só de pé, sem estar caído, um por vez
			local hum = char:FindFirstChildOfClass("Humanoid")
			if
				hum
				and hum.Health > 0
				and not char:GetAttribute("Prone")
				and not char:GetAttribute("Downed")
				and not char:GetAttribute("Vaulting")
			then
				char:SetAttribute("Vaulting", true)
				local dur = if type(req.dur) == "number" and req.dur == req.dur
					then math.clamp(req.dur, 0.3, 1.5)
					else 0.8
				task.delay(dur, function()
					if char.Parent then
						char:SetAttribute("Vaulting", nil)
					end
				end)
			end
			return
		end
		if type(req) == "boolean" then -- formato antigo: agachar
			setStance(char, if req then "crouch" else "stand")
			return
		end
		if type(req) ~= "table" then
			return
		end
		if req.stance == "stand" or req.stance == "crouch" or req.stance == "prone" then
			setStance(char, req.stance)
		end
		-- D-99 (inclinar do Front 44): −1..1 em quartos (o cliente manda menos que 1 quando a parede
		-- limita); deitado, correndo ou caído, nada
		if type(req.lean) == "number" and req.lean == req.lean then
			local l = math.round(math.clamp(req.lean, -1, 1) * 4) / 4
			local off = char:GetAttribute("Prone") or char:GetAttribute("Sprinting") or char:GetAttribute("Downed")
			char:SetAttribute("Lean", if off then 0 else l)
		end
		-- D-98: carta aberta na mão (todos veem: PostureController). Vivo, de pé no chão (sem assento) e
		-- no máximo 4 trocas por segundo; caído ou sentado, a carta some.
		if type(req.carta) == "boolean" then
			local now = os.clock()
			if now - (cartaAt[player] or 0) >= 0.25 then
				cartaAt[player] = now
				local hum = char:FindFirstChildOfClass("Humanoid")
				local ok = req.carta
					and hum ~= nil
					and hum.Health > 0
					and hum.SeatPart == nil
					and char:GetAttribute("Downed") ~= true
				char:SetAttribute("Carta", if ok then true else nil)
			end
		end
		-- D-99: item na mão que todos veem (rádio, binóculo, pá, cantil: Controllers/ItemView manda;
		-- PostureController anima). Vivo, a pé, sem estar caído; até 4 trocas por segundo. false tira.
		if req.item ~= nil then
			local now = os.clock()
			if now - (itemAt[player] or 0) >= 0.25 then
				itemAt[player] = now
				local hum = char:FindFirstChildOfClass("Humanoid")
				local it = if type(req.item) == "string" and ItemAnim.ITEMS[req.item] then req.item else nil
				if it and hum and hum.Health > 0 and hum.SeatPart == nil and char:GetAttribute("Downed") ~= true then
					char:SetAttribute("VT65ItemT", workspace:GetServerTimeNow())
					char:SetAttribute("VT65Item", it)
				else
					char:SetAttribute("VT65Item", nil)
				end
			end
		end
		if type(req.sprint) == "boolean" then
			local ok = req.sprint
				and not char:GetAttribute("Crouched")
				and not char:GetAttribute("Prone")
				and (if budgetChar[player] == char then budget[player] or 1 else 1) >= Movement.SERVER_MIN_TO_START
			char:SetAttribute("Sprinting", ok)
			MedicalService.apply(char)
		end
	end)
end

return PostureService
