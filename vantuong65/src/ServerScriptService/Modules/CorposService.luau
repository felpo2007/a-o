--!strict
-- Morte e corpos no SERVIDOR (D-107; regras e números em Shared/Corpos). Pedido do dono: "os mortos
-- não somem do mapa e nem ficam deitados também", "faça animação para quando ele morrer".
-- Causas achadas: o Humanoid quebrava as juntas na morte (BreakJointsOnDeath) e o bot morto seguia
-- preso de pé pela AlignOrientation "BotFacing" (torque de 1e7) que o BotLocomotion deixa ligada; o
-- jogador morto ficava no lugar até renascer e o bot sumia de uma vez em 5 s.
-- Agora, igual para jogador e bot (a física é do servidor e replica: todos veem a mesma queda):
-- 1. ao morrer, boneco de pano: as juntas animadas do R15 desligam e entram juntas com limite
--    (Corpos.JUNTAS: dobradiça no cotovelo e no joelho, bola com cone e giro no resto, nos eixos de
--    repouso do R15); sai o que segura o corpo de pé (AlignOrientation, IK), a arma da mão (a do chão
--    é do CombatService/BotService) e o assento; um empurrão leve tomba quem morreu em pé;
-- 2. quem morreu deitado ou caído (o deitado não colide com o terreno, PostureService) sobe o quanto
--    estava enterrado antes de ganhar colisão: com a peça dentro do chão o boneco era cuspido;
-- 3. parado (ou em Corpos.ASSENTAR_MAX_S) congela: vira uma cópia ancorada em workspace.Corpos, sem
--    colisão e fora das consultas (bala e visão passam), e o original fica invisível e ancorado (o
--    bot o BotService destrói; o do jogador é o personagem dele até renascer: câmera e telas);
-- 4. depois de Corpos.VIDA_S o corpo some (atributos "VT65Some"/"VT65SomeS": o MorteFx de cada
--    cliente apaga em Corpos.SUMIR_S); acima do Corpos.TETO o mais velho some antes.
-- Evacuado pelo medevac ou morto num assento de veículo: sem corpo (sai do campo / fica no veículo).
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Corpos = require(ReplicatedStorage.Shared.Corpos)
local Joints = require(ReplicatedStorage.Shared.Joints)
local Combatants = require(script.Parent.Combatants)

local CorposService = {}

type Caindo = {
	model: Model,
	t0: number,
	parado: number,
	pecas: { BasePart },
	empurrado: boolean,
	y0: number, -- altura do HRP ao morrer (chão de referência)
}
type NoChao = { model: Model, nasceu: number, sumindo: boolean }
local caindo: { [Model]: Caindo } = {}
local fila: { NoChao } = {} -- do mais velho ao mais novo
local folder: Folder? = nil

local function pastaCorpos(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local n = Instance.new("Folder")
	n.Name = "Corpos"
	n.Parent = workspace
	folder = n
	return n
end

local function pecas(model: Model): { BasePart }
	local out: { BasePart } = {}
	for _, n in Corpos.PECAS do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			table.insert(out, p)
		end
	end
	return out
end

-- a outra peça de uma junta, solda ou restrição (nil se não for peça)
local function outra(j: Instance, p: BasePart): Instance?
	local a: any = j
	if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("NoCollisionConstraint") then
		local p0, p1 = a.Part0, a.Part1
		return if p0 == p then p1 else p0
	elseif j:IsA("Constraint") then
		local a0, a1 = a.Attachment0, a.Attachment1
		local q0 = a0 and a0.Parent
		local q1 = a1 and a1.Parent
		return if q0 == p then q1 else q0
	end
	return nil
end

-- Solda do assento e qualquer junta do corpo com peça de fora (veículo): ancorar o corpo ancoraria
-- o veículo junto.
local function soltarDeFora(model: Model)
	for _, p in pecas(model) do
		for _, j in p:GetJoints() do
			local o = outra(j, p)
			if o and not o:IsDescendantOf(model) then
				j:Destroy()
			end
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		for _, j in root:GetJoints() do
			local o = outra(j, root)
			if o and not o:IsDescendantOf(model) then
				j:Destroy()
			end
		end
	end
end

-- O que segura o corpo de pé ou o move (AlignOrientation "BotFacing" dos bots, forças, IK)
local function desligarForcas(model: Model)
	for _, d in model:GetDescendants() do
		if
			d:IsA("AlignOrientation")
			or d:IsA("AlignPosition")
			or d:IsA("LinearVelocity")
			or d:IsA("AngularVelocity")
			or d:IsA("VectorForce")
			or d:IsA("Torque")
			or d:IsA("IKControl")
		then
			(d :: any).Enabled = false
		elseif d:IsA("BodyMover") then
			d:Destroy()
		end
	end
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Peças de cada lado e o repouso da junta (C0, C1), Motor6D ou AnimationConstraint (Shared/Joints)
local function lados(j: Instance): (BasePart?, BasePart?, CFrame?, CFrame?)
	if j:IsA("Motor6D") then
		return j.Part0, j.Part1, Joints.rest(j), j.C1
	elseif j:IsA("AnimationConstraint") then
		local a0, a1 = j.Attachment0, j.Attachment1
		local p0 = a0 and a0.Parent
		local p1 = a1 and a1.Parent
		if a1 and p0 and p0:IsA("BasePart") and p1 and p1:IsA("BasePart") then
			return p0, p1, Joints.rest(j), a1.CFrame
		end
	end
	return nil, nil, nil, nil
end

-- Juntas animadas -> juntas com limite. A HumanoidRootPart fica soldada ao quadril (sem massa e sem
-- colisão): a câmera e o pivô do modelo acompanham o corpo caído (como no Front 44).
local function juntasDePano(model: Model)
	for name, spec in Corpos.JUNTAS do
		local j = Joints.find(model, name)
		if j then
			local p0, p1, c0, c1 = lados(j)
			if p0 and p1 and c0 and c1 then
				(j :: any).Enabled = false
				local e1, e2 = Corpos.eixos(spec)
				local r = CFrame.fromMatrix(Vector3.zero, v3(e1), v3(e2))
				local a0 = Instance.new("Attachment")
				a0.Name = "VT65Corpo0_" .. name
				a0.CFrame = c0 * r
				a0.Parent = p0
				local a1 = Instance.new("Attachment")
				a1.Name = "VT65Corpo1_" .. name
				a1.CFrame = c1 * r
				a1.Parent = p1
				if spec.tipo == "dobra" then
					local h = Instance.new("HingeConstraint")
					h.Name = "VT65Corpo_" .. name
					h.LimitsEnabled = true
					h.LowerAngle = spec.min or -90
					h.UpperAngle = spec.max or 90
					h.Restitution = 0
					h.Attachment0, h.Attachment1 = a0, a1
					h.Parent = p1
				else
					local b = Instance.new("BallSocketConstraint")
					b.Name = "VT65Corpo_" .. name
					b.LimitsEnabled = true
					b.UpperAngle = spec.cone or 45
					b.TwistLimitsEnabled = true
					b.TwistLowerAngle = -(spec.giro or 15)
					b.TwistUpperAngle = spec.giro or 15
					b.Restitution = 0
					b.Attachment0, b.Attachment1 = a0, a1
					b.Parent = p1
				end
			end
		end
	end
	-- juntas esféricas que vêm prontas no corpo novo do Roblox: fora (as nossas têm os limites)
	for _, d in model:GetDescendants() do
		if d:IsA("BallSocketConstraint") and string.sub(d.Name, 1, 9) ~= "VT65Corpo" then
			d.Enabled = false
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lower = model:FindFirstChild("LowerTorso") :: BasePart?
	local rj = lower and Joints.find(lower, "Root")
	if rj then
		(rj :: any).Enabled = false
	end
	if root and lower then
		root.Anchored = false
		root.Massless = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		local w = Instance.new("WeldConstraint")
		w.Name = "VT65CorpoRaiz"
		w.Part0, w.Part1 = lower, root
		w.Parent = root
	end
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }

-- chão (terreno e peças sólidas do mapa) embaixo de um ponto, sem soldados nem corpos
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local function chaoEm(pos: Vector3, model: Model): number?
	local skip: { Instance } = { model, pastaCorpos() }
	local comb = workspace:FindFirstChild("Combatants")
	if comb then
		table.insert(skip, comb)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = skip
	-- começa só 2,5 studs acima: num túnel o raio não nasce dentro do teto
	local hit = workspace:Raycast(pos + Vector3.new(0, 2.5, 0), Vector3.new(0, -12, 0), groundParams)
	return if hit then hit.Position.Y else nil
end

-- parte mais baixa da peça (studs)
local function fundo(p: BasePart): number
	local cf, s = p.CFrame, p.Size
	local half = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
		/ 2
	return p.Position.Y - half
end

-- corpo deitado meio enterrado: sobe o quanto falta para nenhuma peça ficar dentro do chão
local function desenterrar(model: Model, ps: { BasePart })
	local lista: { { number } } = {}
	for _, p in ps do
		local g = chaoEm(p.Position, model)
		if g then
			table.insert(lista, { fundo(p), g })
		end
	end
	local up = Corpos.erguer(lista)
	if up > 0 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, up, 0))
	end
end

local function emPe(model: Model): boolean
	local ut = model:FindFirstChild("UpperTorso") :: BasePart?
	return ut ~= nil and ut.CFrame.UpVector.Y > Corpos.EM_PE_Y
end

-- Some com o original sem destruir (personagem do jogador e bot: os donos destroem): invisível,
-- ancorado e sem colisão nem consulta.
local function esconder(model: Model)
	soltarDeFora(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = true
		elseif d:IsA("Decal") then -- Texture herda de Decal
			d.Transparency = 1
		end
	end
end

local function comecarSumir(c: NoChao, dur: number)
	if c.sumindo then
		return
	end
	c.sumindo = true
	c.model:SetAttribute("VT65SomeS", dur)
	c.model:SetAttribute("VT65Some", workspace:GetServerTimeNow())
	task.delay(dur + 0.3, function()
		c.model:Destroy()
		local i = table.find(fila, c)
		if i then
			table.remove(fila, i)
		end
	end)
end

local function aplicarTeto()
	local n = 0
	for _ in caindo do
		n += 1
	end
	local f: Corpos.Fila = {}
	for _, c in fila do
		table.insert(f, { nasceu = c.nasceu, sumindo = c.sumindo })
	end
	for _, s in Corpos.paraSumir(f, n, os.clock()) do
		comecarSumir(fila[s.i], s.s)
	end
end

-- Cópia parada do corpo (o que fica no chão): sem scripts, juntas, restrições nem HumanoidRootPart;
-- peças ancoradas, sem colisão e fora das consultas. O Humanoid fica (veste a farda), sem estados.
local function copiar(model: Model, nasceu: number): Model?
	model.Archivable = true -- o personagem do jogador vem com Archivable falso
	local ok, c = pcall(function(): Model?
		return model:Clone()
	end)
	if not ok or not c then
		return nil
	end
	local corpo = c :: Model
	for _, d in corpo:GetDescendants() do
		if
			d:IsA("LuaSourceContainer")
			or d:IsA("Constraint")
			or d:IsA("JointInstance")
			or d:IsA("WeldConstraint")
			or d:IsA("NoCollisionConstraint")
			or d:IsA("IKControl")
			or d:IsA("ProximityPrompt")
			or d:IsA("Sound")
			or d:IsA("BillboardGui")
			or d:IsA("ForceField")
		then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local hrp = corpo:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp:Destroy()
	end
	local hum = corpo:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		hum.EvaluateStateMachine = false
	end
	for k in corpo:GetAttributes() do
		corpo:SetAttribute(k, nil) -- nada de "Faction", "Downed", "Bot"...: não é mais soldado
	end
	corpo.Name = "Corpo"
	corpo:SetAttribute("VT65Corpo", workspace:GetServerTimeNow())
	pcall(function()
		corpo.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- chega inteiro ou não chega
	end)
	corpo.Parent = pastaCorpos()
	table.insert(fila, { model = corpo, nasceu = nasceu, sumindo = false })
	return corpo
end

-- Ficou em pé (encostado num muro, preso): deita a cópia de costas, girando em volta dos pés, e a
-- põe no chão. Raro; garante que nenhum corpo fica de pé.
local function deitarAForca(corpo: Model)
	local ut = corpo:FindFirstChild("UpperTorso") :: BasePart?
	if not ut or ut.CFrame.UpVector.Y <= Corpos.EM_PE_Y then
		return
	end
	local pivot = corpo:GetPivot()
	local look = ut.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local axis = flat:Cross(Vector3.yAxis) -- tomba para trás
	local ps = pecas(corpo)
	local low = math.huge
	for _, p in ps do
		low = math.min(low, fundo(p))
	end
	local feet = Vector3.new(pivot.X, low, pivot.Z)
	local rot = CFrame.fromAxisAngle(axis, math.pi / 2) -- em volta da direita: a cabeça vai para trás
	corpo:PivotTo(CFrame.new(feet) * rot * CFrame.new(-feet) * pivot)
	local lista: { { number } } = {}
	local lowest = math.huge
	for _, p in ps do
		local g = chaoEm(p.Position, corpo)
		local f = fundo(p)
		lowest = math.min(lowest, f - (g or f))
		if g then
			table.insert(lista, { f, g })
		end
	end
	local up = Corpos.erguer(lista)
	local down = if up <= 0 and lowest < math.huge and lowest > 0.15 then lowest - 0.05 else 0
	corpo:PivotTo(corpo:GetPivot() + Vector3.new(0, up - down, 0))
end

-- Congela: atravessou o chão? volta para cima dele; cópia no chão; original escondido. O raio sai
-- da altura em que o soldado estava vivo (num túnel, dentro do túnel: não acha o chão lá de cima).
local function congelar(c: Caindo)
	caindo[c.model] = nil
	local model = c.model
	local ut = model:FindFirstChild("UpperTorso") :: BasePart?
	if ut then
		local from = Vector3.new(ut.Position.X, math.max(c.y0, ut.Position.Y), ut.Position.Z)
		local hit = workspace:Raycast(from, Vector3.new(0, -60, 0), terrainOnly)
		if hit and ut.Position.Y < hit.Position.Y - 1.0 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, hit.Position.Y + 0.6 - ut.Position.Y, 0))
		end
	end
	local corpo = copiar(model, c.t0)
	if corpo then
		deitarAForca(corpo)
	end
	esconder(model)
	aplicarTeto()
end

local function morreu(model: Model)
	if caindo[model] or model:GetAttribute("VT65Morto") then
		return
	end
	model:SetAttribute("VT65Morto", workspace:GetServerTimeNow())
	local hum = model:FindFirstChildOfClass("Humanoid")
	-- evacuado (medevac) ou morto no assento: sem corpo
	if model:GetAttribute("Evacuated") == true or (hum and hum.SeatPart ~= nil) then
		if hum and hum.SeatPart then
			hum.Sit = false
		end
		esconder(model)
		return
	end
	local deitado = model:GetAttribute("Prone") == true or model:GetAttribute("Downed") == true
	soltarDeFora(model)
	desligarForcas(model)
	local arma = model:FindFirstChild("Weapon")
	if arma then
		arma:Destroy() -- a arma no chão é o pickup do CombatService/BotService
	end
	local faca = model:FindFirstChild("FacaMao")
	if faca then
		faca:Destroy()
	end
	local ps = pecas(model)
	for _, p in ps do
		p.Anchored = false
	end
	juntasDePano(model)
	if deitado then
		desenterrar(model, ps)
	end
	for _, p in ps do
		p.CanCollide = true
		p.CanQuery = false -- bala e visão passam pelo corpo
		p.CanTouch = false
		p.CollisionGroup = Corpos.GRUPO
		pcall(function()
			p:SetNetworkOwner(nil) -- o servidor simula: todos veem a mesma queda
		end)
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	-- em pé: um empurrão leve para trás e de lado (sem ele o boneco pode só desabar no lugar)
	local ut = model:FindFirstChild("UpperTorso") :: BasePart?
	if ut and not deitado then
		local r = Random.new()
		local back = -ut.CFrame.LookVector
		local side = ut.CFrame.RightVector * r:NextNumber(-0.5, 0.5)
		local dir = Vector3.new(back.X + side.X, 0, back.Z + side.Z)
		if dir.Magnitude > 1e-3 then
			ut.AssemblyLinearVelocity += dir.Unit * Corpos.EMPURRAO
		end
	end
	local y0 = if root then root.Position.Y else (if ut then ut.Position.Y else 0)
	caindo[model] = { model = model, t0 = os.clock(), parado = 0, pecas = ps, empurrado = false, y0 = y0 }
	aplicarTeto()
end

-- Assentar (10 Hz): freia o que voa; parado ou no tempo máximo, congela. Em pé depois de 1,5 s
-- (encostado), um empurrão a mais.
local acc = 0
local function passo(dt: number)
	acc += dt
	if acc < 0.1 then
		return
	end
	local step = acc
	acc = 0
	local now = os.clock()
	for model, c in caindo do
		if not model.Parent then
			caindo[model] = nil
			continue
		end
		local maxV = 0
		for _, p in c.pecas do
			local v = p.AssemblyLinearVelocity
			local m = v.Magnitude
			if m > Corpos.VOO_MAX then
				p.AssemblyLinearVelocity = v.Unit * Corpos.VOO_MAX
				m = Corpos.VOO_MAX
			end
			local w = p.AssemblyAngularVelocity
			if w.Magnitude > Corpos.GIRO_MAX then
				p.AssemblyAngularVelocity = w.Unit * Corpos.GIRO_MAX
			end
			maxV = math.max(maxV, m)
		end
		local idade = now - c.t0
		if not c.empurrado and idade > 1.5 and emPe(model) then
			c.empurrado = true
			local ut = model:FindFirstChild("UpperTorso") :: BasePart?
			if ut then
				local back = -ut.CFrame.LookVector
				ut.AssemblyLinearVelocity += Vector3.new(back.X, 0, back.Z).Unit * Corpos.EMPURRAO * 1.5
			end
		end
		local parado, pronto = Corpos.assentar(c.parado, maxV, step, idade)
		c.parado = parado
		if pronto then
			congelar(c)
		end
	end
end

-- Vence o tempo dos corpos no chão (1 Hz)
local function vencer()
	while true do
		task.wait(1)
		aplicarTeto()
	end
end

-- Original tirado do mapa no meio da queda (bot removido, jogador saiu ou renasceu): congela antes
-- de sumir. Destroying vem antes da destruição; tirado sem destruir, o modelo ainda está inteiro.
local function vigiar(model: Model)
	local function salvar()
		local c = caindo[model]
		if c then
			caindo[model] = nil
			copiar(model, c.t0)
		end
	end
	model.Destroying:Connect(salvar)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			salvar()
		end
	end)
end

function CorposService.info(): (number, number, number)
	local n, some = 0, 0
	for _ in caindo do
		n += 1
	end
	for _, c in fila do
		if c.sumindo then
			some += 1
		end
	end
	return n, #fila - some, some
end

function CorposService.start()
	if not PhysicsService:IsCollisionGroupRegistered(Corpos.GRUPO) then
		PhysicsService:RegisterCollisionGroup(Corpos.GRUPO)
	end
	PhysicsService:CollisionGroupSetCollidable(Corpos.GRUPO, Corpos.GRUPO, false)
	-- o veículo passa por cima sem chutar o boneco (AssetLoader.VEHICLE_GROUP)
	local veh = "VT65Veiculo"
	if not PhysicsService:IsCollisionGroupRegistered(veh) then
		PhysicsService:RegisterCollisionGroup(veh)
	end
	PhysicsService:CollisionGroupSetCollidable(Corpos.GRUPO, veh, false)
	pastaCorpos()
	Combatants.Added:Connect(function(e: Combatants.Entry)
		local model = e.model
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		-- sem isto o Humanoid quebra as juntas na morte (o corpo desmonta ou fica preso de pé)
		hum.BreakJointsOnDeath = false
		vigiar(model)
		hum.Died:Once(function()
			morreu(model)
		end)
	end)
	RunService.Heartbeat:Connect(passo)
	task.spawn(vencer)
end

return CorposService
