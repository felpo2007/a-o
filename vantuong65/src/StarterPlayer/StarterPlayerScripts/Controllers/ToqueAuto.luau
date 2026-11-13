--!strict
-- Toque v39 (dono, jogando no celular: "deixe somente os importantes; o resto deve ser feito de forma
-- automática para o celular ou tablet"). Só vale com o toque como entrada; o ToqueHud chama step()
-- a cada quadro e lê ToqueAuto.ctx para os botões que aparecem quando servem.
-- Contextuais (Shared/Toque): RECARGA (carregador gasto; com a recarga automática do
-- WeaponController, só a tática na pausa), GOLPE (inimigo à vista a até 4 m), FÔLEGO (na luneta, com
-- a respiração sozinha desligada), BANDAGEM (sangrando) e RÁDIO (quem fala com o comando).
-- Automáticos, cada um com opção em Configurações > Toque:
--   - inclinar na quina mirando (touchAutoLean), pelos mesmos lean_left/lean_right do Q/E;
--   - respiração na luneta (touchAutoBreath): prende ao entrar, solta antes de cansar;
--   - pegar munição e abrir caixote ao encostar (touchAutoPickup), pelo mesmo segurar do prompt;
--   - tiro sozinho com a mira num inimigo à vista (touchAutoFire, DESLIGADO no padrão);
--   - os avisos de interação do Roblox (ProximityPrompt) não aparecem no toque: o botão INTERAGIR
--     (Interagir.client) já mostra o que fazer, sem tecla nenhuma.
-- O ímã leve da mira fica no CameraLook (gira a câmera); a recarga automática, no WeaponController.
-- Limites e números: Shared/Toque (testados no Lune). Nada vê através de parede, mata ou fumaça.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Radio = require(ReplicatedStorage.Shared.Radio)
local Smoke = require(ReplicatedStorage.Shared.Smoke)
local Toque = require(ReplicatedStorage.Shared.Toque)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local Weapons = require(ReplicatedStorage.Shared.Weapons) :: any
local Bus = require(script.Parent.Bus)
local Inclinar = require(script.Parent.Inclinar)
local Input = require(script.Parent.Input)

local ToqueAuto = {}
local player = Players.LocalPlayer
local M = Movement.STUD_M

-- o que o HUD mostra agora (Toque.Ctx, os campos contextuais)
ToqueAuto.ctx = { reload = false, melee = false, breath = false, bleed = false, command = false }
-- o tiro sozinho aperta pelo mesmo contador de dedos do botão de tiro (ToqueHud)
ToqueAuto.onFire = nil :: ((down: boolean) -> ())?
-- Studio: contextual forçado por alguns segundos (VT65DevToque "contexto:<nome>")
ToqueAuto.devUntil = {} :: { [string]: number }

export type StepIn = {
	dt: number,
	active: boolean, -- HUD de toque ligado (toque, vivo, em jogo)
	foot: boolean, -- a pé (não caído, não no veículo)
	aiming: boolean,
	manualLean: boolean, -- o jogador ligou um botão de inclinar
	fingerFire: boolean, -- o dedo do jogador está no tiro
}

local S = {
	running = false,
	lastShot = -math.huge,
	bleed = 0,
	bandages = 0,
	tourniquets = 0,
	meleeAt = 0,
	leanAt = 0,
	fireAt = 0,
	pickAt = 0,
	lean = Toque.newLean(),
	leanSide = 0,
	leanIn = { ahead = false, clearL = false, clearR = false },
	fire = Toque.newAutoFire(),
	fireHeld = false,
	onTarget = false,
	breathHeld = false,
	breathT0 = 0,
	breathDone = false, -- já soltou nesta entrada na luneta (não prende de novo até sair)
	shown = {} :: { [ProximityPrompt]: boolean },
	styled = {} :: { [ProximityPrompt]: boolean },
	picking = nil :: { prompt: ProximityPrompt, until_: number }?,
	pickedAt = {} :: { [ProximityPrompt]: number },
}

Bus.on("shot_fired", function()
	S.lastShot = os.clock()
end)

Net.event("Medical_State").OnClientEvent:Connect(function(s: any)
	if type(s) ~= "table" then
		return
	end
	S.bleed = if type(s.bleed) == "number" then s.bleed else 0
	S.bandages = if type(s.bandages) == "number" then s.bandages else 0
	S.tourniquets = if type(s.tourniquets) == "number" then s.tourniquets else 0
end)
player.CharacterAdded:Connect(function()
	S.bleed = 0
end)

local function setting(key: string): any
	return (Input.settings :: any)[key]
end

local function num(name: string): number?
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else nil
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = false
params.IgnoreWater = true

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true -- a parede de verdade (como o Inclinar)
wallParams.IgnoreWater = true

local function exclude(char: Model)
	local cam = workspace.CurrentCamera
	local list: { Instance } = { char }
	if cam then
		table.insert(list, cam)
	end
	params.FilterDescendantsInstances = list
	wallParams.FilterDescendantsInstances = list
end

-- o modelo de soldado (com Humanoid vivo) dono de uma peça, ou nil
local function soldierOf(inst: Instance?): Model?
	local m = inst and inst:FindFirstAncestorOfClass("Model")
	while m do
		local h = m:FindFirstChildOfClass("Humanoid")
		if h then
			return if h.Health > 0 then m else nil
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function isEnemy(m: Model): boolean
	local mine = player:GetAttribute("Faction")
	local theirs = m:GetAttribute("Faction")
	return type(mine) == "string" and type(theirs) == "string" and theirs ~= mine
end

-- ===== GOLPE: inimigo à vista a até 4 m, na frente =====
local function meleeScan(char: Model, eye: Vector3, look: Vector3): boolean
	local reach = Toque.MELEE_M / M
	local function check(m: Model): boolean
		local r = m:FindFirstChild("HumanoidRootPart")
		local torso = (m:FindFirstChild("UpperTorso") or r) :: BasePart?
		if not (r and r:IsA("BasePart") and torso and isEnemy(m)) then
			return false
		end
		local v = torso.Position - eye
		local dist = v.Magnitude
		if dist > reach or dist < 1e-3 then
			return false
		end
		local ang = math.deg(math.acos(math.clamp(look:Dot(v.Unit), -1, 1)))
		if ang > Toque.MELEE_DEG then
			return false
		end
		local hit = workspace:Raycast(eye, v, params)
		local visible = hit ~= nil and hit.Instance:IsDescendantOf(m)
		return Toque.meleeNear(dist * M, ang, visible)
	end
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if p ~= player and c and soldierOf(c:FindFirstChild("HumanoidRootPart")) and check(c) then
			return true
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and soldierOf(m:FindFirstChild("HumanoidRootPart")) and check(m) then
				return true
			end
		end
	end
	return false
end

-- ===== inclinar na quina (lean_left / lean_right, como o Q/E) =====
local function setLean(side: number)
	if side == S.leanSide then
		return
	end
	if S.leanSide < 0 then
		Input.virtual("lean_left", false)
	elseif S.leanSide > 0 then
		Input.virtual("lean_right", false)
	end
	S.leanSide = side
	if side < 0 then
		Input.virtual("lean_left", true)
	elseif side > 0 then
		Input.virtual("lean_right", true)
	end
end

local function leanRays(cam: Camera)
	-- o olho sem o inclinar de agora (a câmera já pode estar de lado)
	local cf = cam.CFrame
	local off = Movement.LEAN.offsetM / M
	local eye0 = cf.Position - cf.RightVector * (Inclinar.value() * off)
	local look = cf.LookVector
	local ahead = workspace:Raycast(eye0, look * (Toque.LEAN_AHEAD_M / M), wallParams)
	local far = look * (Toque.LEAN_CLEAR_M / M)
	local l = workspace:Raycast(eye0 - cf.RightVector * off, far, wallParams)
	local r = workspace:Raycast(eye0 + cf.RightVector * off, far, wallParams)
	S.leanIn.ahead, S.leanIn.clearL, S.leanIn.clearR = ahead ~= nil, l == nil, r == nil
end

-- ===== respiração na luneta (hold_breath, como o Shift) =====
local function setBreath(on: boolean)
	if on == S.breathHeld then
		return
	end
	S.breathHeld = on
	S.breathT0 = os.clock()
	Input.virtual("hold_breath", on)
end

local function stepBreath(scoped: boolean, enabled: boolean)
	if not (scoped and enabled) then
		setBreath(false)
		S.breathDone = false
		return
	end
	if not S.breathHeld and not S.breathDone then
		setBreath(true)
		return
	end
	if S.breathHeld then
		local len = Weapons.breathTime(true, Vantagens.mult(player, "breath"))
		if Toque.breathRelease(os.clock() - S.breathT0, len, Weapons.BREATH_TIRED_K) then
			setBreath(false)
			S.breathDone = true
		end
	end
end

-- ===== tiro sozinho (opção, desligado no padrão) =====
local function setFire(on: boolean)
	if on == S.fireHeld then
		return
	end
	S.fireHeld = on
	local f = ToqueAuto.onFire
	if f then
		f(on)
	else
		Input.virtual("fire", on)
	end
end

local function aimRay(cam: Camera): boolean
	local cf = cam.CFrame
	local hit = workspace:Raycast(cf.Position, cf.LookVector * (Toque.ASSIST_RANGE_M / M), params)
	local m = hit and soldierOf(hit.Instance)
	if not (hit and m and isEnemy(m)) then
		return false
	end
	return not Smoke.sightBlocked(cf.Position, hit.Position)
end

-- ===== interação: sem o aviso do Roblox no toque; munição e caixote ao encostar =====
local function restyle(p: ProximityPrompt, custom: boolean)
	if custom and p.Style == Enum.ProximityPromptStyle.Default then
		S.styled[p] = true
		p.Style = Enum.ProximityPromptStyle.Custom
	elseif not custom and S.styled[p] then
		S.styled[p] = nil
		p.Style = Enum.ProximityPromptStyle.Default
	else
		return
	end
	-- o aviso que já estava na tela só sai ao esconder: liga e desliga aqui (local)
	task.defer(function()
		if p.Parent and p.Enabled then
			p.Enabled = false
			p.Enabled = true
		end
	end)
end

ProximityPromptService.PromptShown:Connect(function(p: ProximityPrompt)
	S.shown[p] = true
	if Input.touchActive() then
		restyle(p, true)
	end
end)
ProximityPromptService.PromptHidden:Connect(function(p: ProximityPrompt)
	S.shown[p] = nil
end)
Input.DeviceChanged:Connect(function(d: string)
	if d ~= "touch" then
		for p in S.styled do
			restyle(p, false)
		end
	end
end)

local function promptKind(p: ProximityPrompt): (string?, BasePart?)
	local par = p.Parent
	if not (par and par:IsA("BasePart")) then
		return nil, nil
	end
	if par:GetAttribute("Faction") ~= player:GetAttribute("Faction") then
		return nil, nil
	end
	-- D-108: a caixa de munição do Suporte não tem aviso: o servidor entrega ao passar perto (em todo
	-- aparelho, CaixaMunicaoService); a "Caixa de munição" construída saiu da logística
	if par.Name == "Crate" then
		return "crate", par
	end
	return nil, nil
end

local function endPick()
	local pk = S.picking
	if pk then
		S.picking = nil
		pcall(function()
			pk.prompt:InputHoldEnd()
		end)
	end
end

local function stepPickup(root: BasePart, enabled: boolean)
	local now = os.clock()
	local pk = S.picking
	if pk then
		local _, part = promptKind(pk.prompt)
		local far = part == nil or (part.Position - root.Position).Magnitude * M > Toque.PICKUP_M + 0.4
		if now >= pk.until_ or far or not S.shown[pk.prompt] or not enabled then
			if now >= pk.until_ then
				S.pickedAt[pk.prompt] = now
			end
			endPick()
		end
		return
	end
	if not enabled then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector2.new(v.X, v.Z).Magnitude * M
	for p in S.shown do
		local kind, part = promptKind(p)
		if part and p.Enabled then
			local dist = (part.Position - root.Position).Magnitude * M
			local since = now - (S.pickedAt[p] or -math.huge)
			if Toque.autoPickup(true, kind, dist, speed, now - S.lastShot, since) then
				S.picking = { prompt = p, until_ = now + p.HoldDuration + 0.25 }
				S.pickedAt[p] = now -- não tenta de novo em seguida mesmo se o segurar cair
				pcall(function()
					p:InputHoldBegin()
				end)
				return
			end
		end
	end
end

-- ===== solta tudo (HUD fechou, caído, veículo, menu) =====
function ToqueAuto.stop()
	S.running = false
	setLean(0)
	S.lean = Toque.newLean()
	setBreath(false)
	S.breathDone = false
	setFire(false)
	S.fire = Toque.newAutoFire()
	endPick()
	for k in ToqueAuto.ctx do
		(ToqueAuto.ctx :: any)[k] = false
	end
end

-- ===== um quadro =====
function ToqueAuto.step(i: StepIn)
	local ctx = ToqueAuto.ctx
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not (i.active and i.foot and char and root and root:IsA("BasePart") and cam) then
		if S.running then
			ToqueAuto.stop()
		end
		return
	end
	S.running = true
	exclude(char)
	local now = os.clock()
	local scoped = player:GetAttribute("Scoped") == true
	-- contextuais
	local wid = player:GetAttribute("EquippedWeapon")
	local wp = if type(wid) == "string" then Weapons.get(wid) else nil
	ctx.reload = Toque.showReload({
		mag = num("Carregador"),
		size = if wp and type(wp.magazine) == "number" then wp.magazine else nil,
		spare = num("Reserva"),
		reloading = player:GetAttribute("Recarregando") == true,
		auto = player:GetAttribute("AutoRecarga") == true,
		sinceShot = now - S.lastShot,
	})
	ctx.bleed = Toque.showBandage(S.bleed, S.bandages, S.tourniquets)
	local role = player:GetAttribute("Role")
	ctx.command =
		Radio.canTalkToCommand(if type(role) == "string" then role else nil, player:GetAttribute("Radio") == true)
	ctx.breath = scoped and i.aiming and not setting("touchAutoBreath")
	if now - S.meleeAt >= 0.15 then
		S.meleeAt = now
		ctx.melee = meleeScan(char, cam.CFrame.Position, cam.CFrame.LookVector)
	end
	for k, untilT in ToqueAuto.devUntil do
		if now < untilT then
			(ctx :: any)[k] = true
		end
	end
	-- inclinar na quina
	local stance = if char:GetAttribute("Prone") then "prone" else "stand"
	local busy = Input.state.sprinting
		or stance == "prone"
		or player:GetAttribute("Vaulting") == true
		or player:GetAttribute("StanceBusy") == true
	local leanOn = setting("touchAutoLean") == true and i.aiming and not busy and not i.manualLean
	if leanOn and now - S.leanAt >= 0.1 then
		S.leanAt = now
		leanRays(cam)
	end
	setLean(Toque.autoLean(S.lean, i.dt, {
		enabled = setting("touchAutoLean") == true,
		aiming = i.aiming,
		blocked = busy,
		manual = i.manualLean,
		ahead = S.leanIn.ahead,
		clearL = S.leanIn.clearL,
		clearR = S.leanIn.clearR,
	}))
	-- respiração na luneta
	stepBreath(scoped and i.aiming, setting("touchAutoBreath") == true)
	-- tiro sozinho
	local fireOn = setting("touchAutoFire") == true
	if fireOn and i.aiming and now - S.fireAt >= 1 / 15 then
		S.fireAt = now
		S.onTarget = aimRay(cam)
	elseif not (fireOn and i.aiming) then
		S.onTarget = false
	end
	local mode = player:GetAttribute("FireMode")
	local op = Toque.autoFire(S.fire, i.dt, now, {
		enabled = fireOn,
		aiming = i.aiming,
		onTarget = S.onTarget,
		full = mode == "auto",
		canFire = not i.fingerFire and player:GetAttribute("Recarregando") ~= true,
	})
	if op == "press" then
		setFire(true)
	elseif op == "release" then
		setFire(false)
	end
	-- munição e caixote ao encostar
	if now - S.pickAt >= 0.2 then
		S.pickAt = now
		stepPickup(root :: BasePart, setting("touchAutoPickup") == true)
	end
end

-- Studio: o estado em uma linha (VT65DevToque "estado")
function ToqueAuto.describe(): string
	local c = ToqueAuto.ctx
	return string.format(
		"contexto: recarga=%s golpe=%s fôlego=%s bandagem=%s comando=%s | inclinar=%d fôlego preso=%s tiro sozinho=%s pegando=%s",
		tostring(c.reload),
		tostring(c.melee),
		tostring(c.breath),
		tostring(c.bleed),
		tostring(c.command),
		S.leanSide,
		tostring(S.breathHeld),
		tostring(S.fireHeld),
		tostring(S.picking ~= nil)
	)
end

return ToqueAuto
