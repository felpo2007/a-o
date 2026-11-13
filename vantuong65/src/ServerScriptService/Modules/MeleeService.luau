--!strict
-- Corpo a corpo no servidor (D-94), chamado pelo FieldService (Combat_Melee, baioneta). Regras e
-- números no Shared/Melee (puro, testado no Lune). O servidor é a autoridade:
-- - o cliente só pede {dir, rifle?}; o golpe (estocada, golpe de lado, baioneta, coronhada) sai do
--   estado do servidor (baioneta armada, faca na mão, combinação de toques);
-- - validação: vivo, de pé no chão (sem assento, transpor ou arremesso), direção finita e perto da
--   frente do corpo, intervalo mínimo do golpe (com o saque), uma tarefa por vez;
-- - o acerto é resolvido NO INSTANTE DO IMPACTO (antecipação + estocada), com a geometria do
--   servidor: alcance do peito ao ponto mais próximo do corpo, cone em torno da mira e linha livre
--   (parede, terreno, porta: nada atravessa). Quem sai do alcance durante a antecipação escapa;
-- - dano por energia equivalente (Medical): estocada certeira no tronco derruba (caído);
-- - bots também golpeiam (reflexo a 4 Hz, Melee.botAttack) e são golpeados (Combatants).
-- Para todos: atributos "Melee" (golpe) e "MeleeT" (relógio do servidor) no modelo (animação de
-- 3ª pessoa dos bots), faca soldada na mão direita enquanto está fora da bainha, baioneta na boca
-- do fuzil, e Combat_Melee (s->c) para o som e o efeito discreto do impacto.
-- Studio: workspace:SetAttribute("VT65DevFaca", ...) (ver devHook no fim).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Corpo = require(ReplicatedStorage.Shared.Corpo)
local Melee = require(ReplicatedStorage.Shared.Melee)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Combatants = require(script.Parent.Combatants)
local MedicalService = require(script.Parent.MedicalService)

local MeleeService = {}
local M = Melee.STUD_M
local rng = Rng.new(1966)
local EFFECT_M = 90 -- quem está até aqui recebe o som e o efeito do golpe

type State = {
	last: string?,
	lastAt: number,
	nextAt: number,
	knifeUntil: number,
	token: number,
	dev: boolean, -- boneco do Studio: golpe sem dano
}
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any

local function stateOf(model: Model): State
	local s = states[model]
	if not s then
		s = { last = nil, lastAt = -10, nextAt = 0, knifeUntil = 0, token = 0, dev = false }
		states[model] = s
	end
	return s
end

local function alive(model: Model): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model:GetAttribute("Downed") ~= true
end

local function zoneOf(part: Instance): string
	local n = part.Name
	if n == "Head" then
		return "head"
	elseif string.find(n, "Arm") or string.find(n, "Hand") then
		return "arm"
	elseif string.find(n, "Leg") or string.find(n, "Foot") then
		return "leg"
	end
	return "torso"
end

local BODY = {
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

-- peito de quem golpeia (de onde o alcance é medido)
local function chestOf(model: Model): Vector3?
	local ut = model:FindFirstChild("UpperTorso") :: BasePart?
	if ut then
		return ut.Position + ut.CFrame.UpVector * (0.12 / M)
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	return if head then head.Position - Vector3.new(0, 0.25 / M, 0) else nil
end

-- ponto da caixa da peça mais perto do segmento a -> b (amostras ao longo do segmento)
local function closestOnPart(p: BasePart, a: Vector3, b: Vector3): Vector3
	local half = p.Size / 2
	local best, bestD = p.Position, math.huge
	for i = 0, 6 do
		local s = a:Lerp(b, i / 6)
		local l = p.CFrame:PointToObjectSpace(s)
		local q = p.CFrame:PointToWorldSpace(
			Vector3.new(
				math.clamp(l.X, -half.X, half.X),
				math.clamp(l.Y, -half.Y, half.Y),
				math.clamp(l.Z, -half.Z, half.Z)
			)
		)
		local d = (q - s).Magnitude
		if d < bestD then
			best, bestD = q, d
		end
	end
	return best
end

type Hit = { model: Model, part: BasePart, pos: Vector3, precise: boolean, zone: string }

-- Alvo do golpe agora (geometria do servidor) ou nil. Devolve também o ponto onde a lâmina parou
-- (parede ou nada) para o efeito.
local function resolve(attacker: Model, dir: Vector3, a: Melee.Attack, faction: string?): (Hit?, Vector3?)
	local o = chestOf(attacker)
	if not o then
		return nil, nil
	end
	local reach = (a.reachM + Melee.LAG_M) / M
	local tip = o + dir * reach
	local cands: { Melee.Candidate } = {}
	for _, e in Combatants.list() do
		local m = e.model
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if m ~= attacker and e.faction ~= faction and hum and hum.Health > 0 and root then
			if (root.Position - o).Magnitude <= reach + 1.6 / M then
				for _, p in m:GetChildren() do
					if p:IsA("BasePart") and BODY[p.Name] then
						local q = closestOnPart(p, o, tip)
						local v = q - o
						local key = { model = m, part = p, pos = q }
						table.insert(cands, {
							distM = v.Magnitude * M,
							angDeg = Melee.angleDeg(dir.X, dir.Y, dir.Z, v.X, v.Y, v.Z),
							zone = zoneOf(p),
							key = key,
						})
					end
				end
			end
		end
	end
	local best, precise = Melee.pick(a.id, cands, Melee.LAG_M)
	-- linha livre do peito até o ponto (o que tem colisão bloqueia: parede, tronco, terreno)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { attacker }
	local fx = workspace:FindFirstChild("VT65Effects")
	if fx then
		table.insert(ignore, fx)
	end
	if best then
		local key = best.key
		table.insert(ignore, key.model)
		params.FilterDescendantsInstances = ignore
		local v = key.pos - o
		local len = math.max(v.Magnitude - Melee.LOS_PAD_M / M, 0)
		if len < 1e-3 or not workspace:Raycast(o, v.Unit * len, params) then
			return { model = key.model, part = key.part, pos = key.pos, precise = precise, zone = best.zone }, key.pos
		end
	end
	params.FilterDescendantsInstances = ignore
	local wall = workspace:Raycast(o, dir * (a.reachM / M), params)
	return nil, if wall then wall.Position else nil
end

-- ===== faca na mão (3ª pessoa, todos veem) =====
function MeleeService.knifeOf(model: Model): string
	local f = model:GetAttribute("Faction")
	return if f == "VC" then Melee.KNIFE.VC else Melee.KNIFE.US
end

local function setHandKnife(model: Model, on: boolean)
	local cur = model:FindFirstChild("FacaMao")
	if not on then
		if cur then
			cur:Destroy()
		end
		local eq = model:FindFirstChild("Equipamento")
		local h = eq and eq:FindFirstChild("Eq_knife_handle")
		if h and h:IsA("BasePart") then
			h.Transparency = 0
		end
		return
	end
	if cur then
		return
	end
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	local k = KnifeModel.build(MeleeService.knifeOf(model))
	if not (hand and k) then
		return
	end
	local knife = k :: Model
	knife.Name = "FacaMao"
	-- D-98: a mão do soldado de 2 m é K vezes maior; o punho da faca desce junto
	knife:PivotTo(hand.CFrame * CFrame.new(0, Melee.HAND_GRIP_Y * Corpo.K, 0))
	KnifeModel.weld(knife)
	local w = Instance.new("WeldConstraint")
	local kp = knife.PrimaryPart :: BasePart
	w.Part0, w.Part1 = hand, kp
	w.Parent = kp
	knife.Parent = model
	-- o cabo do cinto (peça provisória do Gear) some enquanto a faca está na mão
	local eq = model:FindFirstChild("Equipamento")
	local h = eq and eq:FindFirstChild("Eq_knife_handle")
	if h and h:IsA("BasePart") then
		h.Transparency = 1
	end
end

-- ===== efeitos =====
local function broadcast(at: Vector3, msg: { [string]: any })
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - at).Magnitude * M <= EFFECT_M then
			Net.event("Combat_Melee"):FireClient(p, msg)
		end
	end
end

-- ===== golpe =====
-- Pedido de golpe (jogador ou bot). Devolve o golpe aceito ou nil. dir: direção da mira.
function MeleeService.attack(model: Model, dir: Vector3, wantRifle: boolean?): string?
	if not alive(model) then
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or hum.SeatPart ~= nil or model:GetAttribute("Vaulting") or model:GetAttribute("Throwing") then
		return nil
	end
	local f = root.CFrame.LookVector
	if not Melee.dirOk(dir.X, dir.Y, dir.Z, f.X, f.Z) then
		return nil
	end
	local s = stateOf(model)
	local now = os.clock()
	if now < s.nextAt then
		return nil
	end
	local knifeOut = now < s.knifeUntil
	local bayonet = model:GetAttribute("Bayonet") == true
	local id = Melee.choose(bayonet, wantRifle == true, s.last, now - s.lastAt)
	local a = Melee.get(id) :: Melee.Attack
	local delay = Melee.impactDelay(id, knifeOut)
	s.nextAt = now + Melee.cooldown(id, knifeOut)
	s.last, s.lastAt = id, now + delay - a.impact
	s.token += 1
	local token = s.token
	if a.weapon == "knife" then
		s.knifeUntil = now + delay + a.recover + Melee.SHEATHE_AFTER_S
		setHandKnife(model, true)
		task.delay(delay + a.recover + Melee.SHEATHE_AFTER_S + Melee.SHEATHE_S, function()
			if states[model] == s and s.token == token and model.Parent then
				setHandKnife(model, false)
			end
		end)
	end
	model:SetAttribute("Melee", id)
	model:SetAttribute("MeleeT", workspace:GetServerTimeNow())
	model:SetAttribute("MeleeDraw", a.weapon == "knife" and not knifeOut)
	local unit = dir.Unit
	broadcast(root.Position, { k = "golpe", by = model, a = id, draw = a.weapon == "knife" and not knifeOut })
	task.delay(delay, function()
		if states[model] ~= s or s.token ~= token or not alive(model) then
			return
		end
		local by = Players:GetPlayerFromCharacter(model)
		local hit, pos = resolve(model, unit, a, model:GetAttribute("Faction") :: string?)
		if hit then
			local victim = hit.model
			local downed = victim:GetAttribute("Downed") == true
			local knife = if a.weapon == "knife" then MeleeService.knifeOf(model) else nil
			local energy = Melee.energy(id, hit.zone, hit.precise, knife)
			if not s.dev then
				MedicalService.hit(victim, hit.zone, energy, rng:next(), by)
			end
			broadcast(hit.pos, {
				k = "impacto",
				by = model,
				alvo = victim,
				a = id,
				corpo = true,
				x = hit.pos.X,
				y = hit.pos.Y,
				z = hit.pos.Z,
				dx = unit.X,
				dy = unit.Y,
				dz = unit.Z,
			})
			MeleeService.lastHit = {
				attack = id,
				zone = hit.zone,
				precise = hit.precise,
				energy = energy,
				downedBefore = downed,
				t = os.clock(),
			}
		elseif pos then
			broadcast(pos, { k = "impacto", by = model, a = id, corpo = false, x = pos.X, y = pos.Y, z = pos.Z })
		end
	end)
	return id
end
MeleeService.lastHit = nil :: any -- último acerto (autoteste e gancho do Studio)

-- c->s { dir, rifle? }
function MeleeService.onRequest(p: Player, req: any)
	local c = p.Character
	if not (c and Combatants.get(c)) or type(req) ~= "table" or typeof(req.dir) ~= "Vector3" then
		return
	end
	MeleeService.attack(c, req.dir, req.rifle == true)
end

-- ===== baioneta =====
local function setBayonetModel(model: Model, on: boolean)
	local w = model:FindFirstChild("Weapon") :: Model?
	local old = w and w:FindFirstChild("Baioneta")
	if old then
		old:Destroy()
	end
	local primary = w and w.PrimaryPart
	local muzzle = primary and primary:FindFirstChild("Muzzle") :: Attachment?
	local wid = w and w:GetAttribute("WeaponId")
	local bid = if type(wid) == "string" then Melee.BAYONET[wid] else nil
	if not (on and w and primary and muzzle and bid) then
		return
	end
	local k = KnifeModel.build(bid)
	if not k then
		return
	end
	local b = k :: Model
	b.Name = "Baioneta"
	b:PivotTo(MeleeService.bayonetPivot(muzzle.WorldCFrame, b))
	KnifeModel.weld(b)
	local weld = Instance.new("WeldConstraint")
	local bp = b.PrimaryPart :: BasePart
	weld.Part0, weld.Part1 = primary, bp
	weld.Parent = bp
	b.Parent = w
end

-- Onde vai o pivô (punho) da baioneta para ela ficar na boca: a M6 com o anel em volta do
-- quebra-chamas (lâmina por baixo do cano); o espigão do Tipo 56 aberto, por baixo do cano, com a
-- ponta 16 cm à frente da boca (PLACEHOLDER). muzzleCF: LookVector = boca (GunModel).
function MeleeService.bayonetPivot(muzzleCF: CFrame, b: Model): CFrame
	local pivot = b:GetPivot()
	local ring = KnifeModel.at(b, "Ring")
	if b:GetAttribute("KnifeId") == "m6" then
		local r = pivot:PointToObjectSpace(ring)
		return muzzleCF * CFrame.new(-r)
	end
	local tip = pivot:PointToObjectSpace(KnifeModel.at(b, "Tip"))
	return muzzleCF * CFrame.new(0, -0.03 / M, -0.16 / M) * CFrame.new(-tip)
end

function MeleeService.setBayonet(model: Model, on: boolean, weaponId: string?)
	local ok = on and weaponId ~= nil and Melee.BAYONET[weaponId] ~= nil
	model:SetAttribute("Bayonet", ok)
	setBayonetModel(model, ok)
end

-- ===== reflexo dos bots (servidor, 4 Hz) =====
local function botLoop()
	local lastTry: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
	while true do
		task.wait(0.25)
		local list = Combatants.list()
		for _, e in list do
			local m = e.model
			local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			if e.bot and root and alive(m) and not m:GetAttribute("Prone") then
				local best: Vector3?, bestD = nil, math.huge
				for _, o in list do
					local r = o.model:FindFirstChild("HumanoidRootPart") :: BasePart?
					if o.faction ~= e.faction and r and Combatants.active(o) then
						local d = (r.Position - root.Position).Magnitude
						if d < bestD then
							best, bestD = r.Position, d
						end
					end
				end
				if best and bestD * M <= Melee.BOT_REACH_M + 0.5 then
					local v = (best :: Vector3) - root.Position
					local f = root.CFrame.LookVector
					local ang = Melee.angleDeg(f.X, 0, f.Z, v.X, 0, v.Z)
					local now = os.clock()
					local id = Melee.botAttack(bestD * M - 0.3, ang, rng:next(), now - (lastTry[m] or -10), e.faction)
					if id then
						lastTry[m] = now
						MeleeService.attack(m, v.Unit, false)
					end
				end
			end
		end
	end
end

-- ===== arte publicada (cópia para os clientes: 1ª pessoa e a mão de todos) =====
local function loadArt()
	local ok, AssetLoader = pcall(function()
		return require(script.Parent.AssetLoader) :: any
	end)
	if not ok then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("VT65KnifeArt") or Instance.new("Folder")
	folder.Name = "VT65KnifeArt"
	folder.Parent = ReplicatedStorage
	for id, k in Weapons.knives do
		if not folder:FindFirstChild(id) then
			local tpl = AssetLoader.template(k.art)
			if tpl then
				local copy = tpl:Clone()
				copy.Name = id
				for _, d in copy:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
					end
				end
				copy.Parent = folder
			end
		end
	end
end

-- ===== ganchos do Studio =====
-- Na barra de comando (servidor ou cliente):
--   workspace:SetAttribute("VT65DevFaca", "boneco")         boneco inimigo a 1,6 m na sua frente
--   "boneco:estocada" | "boneco:lado" | "boneco:baioneta" | "boneco:coronhada"
--                                                           o boneco golpeia em laço (sem dano)
--   "bracos:stand" | "bracos:crouch" | "bracos:prone" | "bracos:sprint" | "bracos:girar"
--                                                           postura do boneco (braços em cada uma)
--   "arma:m14" (m60, m1911, type56, sks, rpd, type54)      arma na mão do boneco
--   "limpar"                                                tira o boneco
-- No cliente (WeaponController/KnifeView): "estocada", "lado", "baioneta", "coronhada" (um golpe em
-- 1ª pessoa) e "laco" (estocada e golpe de lado em laço até "parar").
local dummy: Model? = nil
local dummyLoop = 0

local function firstPlayer(): (Player?, BasePart?)
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			return p, r
		end
	end
	return nil, nil
end

local function makeDummy()
	local p, r = firstPlayer()
	if not (p and r) then
		warn("[VT65 TESTE] VT65DevFaca: nenhum jogador em campo")
		return
	end
	if dummy then
		dummy:Destroy()
	end
	local Characters = require(script.Parent.Characters) :: any
	local AssetLoader = require(script.Parent.AssetLoader) :: any
	local faction = if p:GetAttribute("Faction") == "VC" then "US" else "VC"
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			Characters.describe(faction, nil, 7),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok or not model then
		warn("[VT65 TESTE] VT65DevFaca: não criou o boneco", model)
		return
	end
	local m = model :: Model
	m.Name = "Boneco_Faca"
	m:SetAttribute("Bot", true)
	m:SetAttribute("Role", "rifleman")
	local at = r.CFrame * CFrame.new(0, 0, -1.6 / M)
	m:PivotTo(CFrame.lookAt(at.Position, Vector3.new(r.Position.X, at.Y, r.Position.Z)))
	local folder = workspace:FindFirstChild("Combatants") or Instance.new("Folder")
	folder.Name = "Combatants"
	folder.Parent = workspace
	m.Parent = folder
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root:SetNetworkOwner(nil)
	end
	Combatants.register(m, faction, nil)
	AssetLoader.attachWeapon(m, if faction == "VC" then "sks" else "m14")
	Characters.dress(m, faction, nil)
	stateOf(m).dev = true
	dummy = m
	print("[VT65 TESTE] VT65DevFaca: boneco", faction, "a 1,6 m de", p.Name)
end

local function devHook()
	local v = workspace:GetAttribute("VT65DevFaca")
	if type(v) ~= "string" then
		return
	end
	local cmd, argm = string.match(v, "^(%w+):?(%w*)$")
	local arg: string = argm or ""
	if cmd == "boneco" and arg == "" then
		makeDummy()
	elseif cmd == "limpar" then
		dummyLoop += 1
		if dummy then
			dummy:Destroy()
			dummy = nil
		end
	elseif not dummy then
		return
	end
	local d = dummy :: Model
	if cmd == "boneco" and Melee.get(arg) then
		dummyLoop += 1
		local loop = dummyLoop
		MeleeService.setBayonet(d, arg == "baioneta", if d:GetAttribute("Faction") == "VC" then "sks" else "m14")
		task.spawn(function()
			while dummy == d and dummyLoop == loop and d.Parent do
				stateOf(d).nextAt = 0
				local root = d:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					MeleeService.attack(d, root.CFrame.LookVector, arg == "coronhada")
				end
				task.wait(1.6)
			end
		end)
	elseif cmd == "bracos" then
		local PostureService = require(script.Parent.PostureService) :: any
		if arg == "girar" then
			dummyLoop += 1
			local loop = dummyLoop
			task.spawn(function()
				while dummy == d and dummyLoop == loop and d.Parent do
					d:PivotTo(d:GetPivot() * CFrame.Angles(0, math.rad(3), 0))
					task.wait(1 / 30)
				end
			end)
		elseif arg == "sprint" then
			PostureService.setStance(d, "stand")
			d:SetAttribute("Sprinting", true)
		elseif arg == "carta" then
			-- D-98: o boneco abre a carta (a pose que os outros veem)
			d:SetAttribute("Carta", if d:GetAttribute("Carta") then nil else true)
		else
			d:SetAttribute("Carta", nil)
			PostureService.setStance(d, arg)
		end
	elseif cmd == "arma" and Weapons.get(arg) then
		local AssetLoader = require(script.Parent.AssetLoader) :: any
		AssetLoader.attachWeapon(d, arg)
	end
end

function MeleeService.start()
	task.spawn(loadArt)
	task.spawn(botLoop)
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevFaca"):Connect(devHook)
	end
end

return MeleeService
