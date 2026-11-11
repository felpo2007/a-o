--!strict
-- Arma (F2 + Parte 12): disparo com semente, mira (FOV), recarga, seletor, alça de mira (zeragem
-- de 100/200/300 m), balanço com "prender a respiração", recuo com tendência aleatória, troca de
-- arma (o antitanque tem o lançador como 2ª arma), binóculo, corpo a corpo e baioneta.
-- Sem retícula, sem hitmarker, sem contador de munição na tela (Parte 1). Entradas pela camada
-- Input: controle e teclado/mouse têm o MESMO balanço, inércia e recuo (Parte 12.4).
-- 3ª pessoa (ThirdPerson.client): o tiro sai do OLHO do personagem e vai até o ponto da retícula
-- (ViewMode), nunca da câmera atrás do ombro; do quadril, com a dispersão de Movement.hipSpreadDeg.
-- O cansaço (Movement.client, atributo "Stamina") aumenta o balanço da mira de ferro.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local AssetIds = require(ReplicatedStorage.Shared.AssetIds)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Haptics = require(script.Parent.Haptics)
local Input = require(script.Parent.Input)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)
local ViewMode = require(script.Parent.ViewMode)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local slots: { string } = {}
local slot = 1
local weapon: Weapons.Weapon? = nil
local launcher = false -- slot do foguete (antitanque)
local modeIdx = 1
local mag = 0
local firing = false
local aiming = false
local binoculars = false
local lastShot = 0
local seedRng = Rng.new(os.time() + player.UserId)
local recoilPitch, recoilYaw = 0, 0
local recoilReturn = 0 -- graus que a boca ainda desce sozinha depois da subida
local RECOIL_DEG_PER_MS = 0.9 -- graus de subida por m/s de recuo livre
local RECOIL_RETURN = 0.6 -- fração da subida que volta sozinha (o resto o jogador corrige)
local ZEROS = { 100, 200, 300 }
local zeroIdx = 1
local breathUntil, breathReady = 0, 0
local swayT = 0

-- aviso curto na tela (seletor, alça, arma): sistema de avisos (Toast), um aviso só para a arma
-- (cada troca atualiza o aberto em vez de empilhar). A tela fica para a vinheta do binóculo.
local hud = UiKit.screen("VT65WeaponToast", 15)
local function say(text: string)
	Toast.show(text, "info", { key = "arma", fallback = "Arma", duration = 1.8 })
end

-- vinheta do binóculo
local binoc = Instance.new("Frame")
binoc.Size = UDim2.fromScale(1, 1)
binoc.BackgroundTransparency = 1
binoc.Visible = false
binoc.Parent = hud
for _, side in { -1, 1 } do
	local c = Instance.new("Frame")
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.new(0.5, side * 170, 0.5, 0)
	c.Size = UDim2.fromOffset(380, 380)
	c.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.Thickness = 900
	s.Color = Color3.new(0, 0, 0)
	s.Parent = c
	local r = Instance.new("UICorner")
	r.CornerRadius = UDim.new(1, 0)
	r.Parent = c
	c.Parent = binoc
end

local function seated(): boolean
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.SeatPart ~= nil
end

local function equip()
	local s = player:GetAttribute("Loadout")
	slots = if type(s) == "string" then string.split(s, ",") else {}
	-- arma pega do chão (servidor) substitui a principal até o próximo spawn
	local carried = player:GetAttribute("CarriedWeapon")
	if type(carried) == "string" and #slots > 0 then
		slots[1] = carried
	end
	if player:GetAttribute("Role") == "anti_tank" then
		table.insert(slots, "launcher")
	end
	slot = math.clamp(slot, 1, math.max(#slots, 1))
	local id = slots[slot]
	launcher = id == "launcher"
	local wp = if id and not launcher then Weapons.get(id) else nil
	weapon = if wp and wp.enabled then wp else nil
	modeIdx = 1
	-- local (não replica): a arma em primeira pessoa (WeaponVisuals) segue a arma equipada
	player:SetAttribute("EquippedWeapon", if launcher then "launcher" elseif weapon then weapon.id else nil)
end

local spare = 0
local reloadUntil = 0
-- tempo de recarga por tipo de arma: espelha CombatService.RELOAD (o servidor manda)
local RELOAD_S: { [string]: number } = { rifle = 3.0, mg = 7.0, pistol = 2.5, launcher = 3.0 }

Net.event("Combat_Ammo").OnClientEvent:Connect(function(a)
	mag = a.mag
	spare = if type(a.spare) == "number" then a.spare else spare
	reloadUntil = 0
end)

-- cor do traçante pela facção da arma e pelo modo daltônico do jogador (Accessibility)
local function tracerColor(faction: string): Color3
	local c = Accessibility.tracer(faction, Input.settings.colorblind)
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- O traçante é desenhado pelo WeaponVisuals: um risco curto que voa pela trajetória, saindo da
-- boca do cano. Antes era uma linha reta do olho até o impacto, acesa por 0,08 s.
local function tracer(shot: any, color: Color3)
	Bus.fire("tracer", shot, color)
end

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot)
	local wp = Weapons.get(shot.w)
	-- só metralhadoras com traçante (proporção real das fitas a confirmar: PLACEHOLDER 1 em 5)
	if wp and wp.kind == "mg" and shot.seed % 5 == 0 then
		tracer(shot, tracerColor(wp.faction))
	end
end)

local S = AssetIds.Sounds
local SHOT_SOUND: { [string]: number } = {
	m14 = S.shot_m14,
	m60 = S.shot_m14, -- mesmo cartucho 7.62x51 até a camada própria
	m1911 = S.shot_m14,
	type56 = S.shot_type56,
	sks = S.shot_type56,
	rpd = S.shot_type56,
	type54 = S.shot_type56,
}
local function playId(id: number, volume: number)
	if id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = camera
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local function setAim(on: boolean)
	if on == aiming then
		return
	end
	aiming = on
	player:SetAttribute("Aiming", on) -- local: a arma vai ao ombro (WeaponVisuals)
	Input.event("aim", on)
	if not on then
		Net.event("Posture_Set"):FireServer({ lean = 0 })
	end
end

-- transpondo, mergulhando ou deitando/levantando (Movement.client): não dá para atirar
local function bodyBusy(): boolean
	return player:GetAttribute("Vaulting") == true or player:GetAttribute("StanceBusy") == true
end

-- Origem e direção do tiro. 1ª pessoa: a câmera (o olho). 3ª pessoa: do olho até o ponto da
-- retícula, com a dispersão do quadril (semente própria, derivada da do tiro).
local function shotRay(seed: number): (Vector3, Vector3)
	local o, d = ViewMode.aimDirection()
	if ViewMode.third and not aiming then
		local r = Rng.new(seed + 7)
		local spread = math.rad(ViewMode.hipSpread())
		local ang, rad = r:next() * 2 * math.pi, spread * math.sqrt(r:next())
		local cf = CFrame.lookAt(Vector3.zero, d) * CFrame.Angles(rad * math.sin(ang), rad * math.cos(ang), 0)
		d = cf.LookVector
	end
	return o, d
end

local function fire()
	local wp = weapon
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if seated() or binoculars or not head or player:GetAttribute("Downed") or bodyBusy() then
		return
	end
	if launcher then
		local now = os.clock()
		if now - lastShot > 1 then
			lastShot = now
			local _, dir = ViewMode.aimDirection() -- o foguete sai da cabeça (VehicleService)
			Net.event("Vehicle_Fire"):FireServer({ dir = dir })
			Haptics.fire(1.6, false)
		end
		return
	end
	if not wp or os.clock() < reloadUntil then -- recarregando: o servidor recusaria o tiro
		return
	end
	if mag <= 0 then
		if os.clock() - lastShot > 0.3 then
			lastShot = os.clock()
			playId(S.dry_click, 0.8) -- Type 56 sem trava do ferrolho: só o clique (Parte 10.6)
		end
		return
	end
	local now = os.clock()
	if now - lastShot < Weapons.minInterval(wp) then
		return
	end
	lastShot = now
	mag -= 1
	local seed = seedRng:nextU32()
	local o, look = shotRay(seed)
	-- alça zerada: o cano sobe o ângulo de zeragem em relação à linha de visada
	local zero = Ballistics.zeroAngle(wp.id, ZEROS[zeroIdx])
	local basis = if ViewMode.third then CFrame.lookAt(Vector3.zero, look) else camera.CFrame.Rotation
	local d = (basis * CFrame.Angles(zero, 0, 0)).LookVector
	local shot: { [string]: any } = {
		w = wp.id,
		ox = o.X,
		oy = o.Y,
		oz = o.Z,
		dx = d.X,
		dy = d.Y,
		dz = d.Z,
		seed = seed,
		t = workspace:GetServerTimeNow(),
	}
	Net.event("Combat_Fire"):FireServer(shot)
	if ViewMode.third then
		shot.by = char -- 3ª pessoa: o traçante local sai da arma do corpo (a de 1ª pessoa some)
	end
	Bus.fire("shot_fired", shot) -- clarão, recuo da arma e poeira no impacto (WeaponVisuals)
	playId(SHOT_SOUND[wp.id] or 0, 0.8)
	if wp.kind == "mg" and seed % 5 == 0 then
		tracer(shot, tracerColor(wp.faction))
	end
	-- Recuo (D-69): velocidade de recuo livre (impulso do projétil e dos gases, ~1,5x, contra a
	-- massa da arma, em m/s) vira graus de subida da boca. Antes a conta fazia math.deg da
	-- velocidade: ~100° por tiro na M14, e a câmera ia ao céu ("diminua recoil", usuário).
	-- Agora: M14 ~2,3°, Type 56 ~1,8°, M60 ~1,0° e M1911 ~4,7° (a pistola volta rápido).
	-- Padrão aleatório com tendência por semente (Parte 10.3); parte volta sozinha (RECOIL_RETURN).
	local impulse = (wp.bulletMassG / 1000) * wp.muzzleVelocity * 1.5
	local kick = (impulse / wp.massLoadedKg) * RECOIL_DEG_PER_MS
	if player:GetAttribute("ArmImpaired") then
		kick *= 1.5
	end
	if aiming then
		kick *= 0.8
	end
	local r = Rng.new(seed)
	recoilPitch += kick
	recoilYaw += (r:next() - 0.35) * kick * 0.6 -- tendência leve para a direita
	recoilReturn += kick * RECOIL_RETURN
	Haptics.fire(kick, wp.modes[modeIdx] == "auto")
end

-- ===== entradas (camada Input) =====
Input.on("fire", "press", function()
	firing = true
	fire()
end)
Input.on("fire", "release", function()
	firing = false
end)
Input.on("aim", "press", function()
	if Input.settings.aimToggle then
		setAim(not aiming)
	else
		setAim(true)
	end
end)
Input.on("aim", "release", function()
	if not Input.settings.aimToggle then
		setAim(false)
	end
end)
-- Recarga (D-69): pede ao servidor e, se ele vai aceitar (há carregador e não está recarregando),
-- o WeaponVisuals anima a troca de carregador com as mãos no tempo do servidor.
local function startReload()
	local wp = weapon
	if not wp or os.clock() < reloadUntil or spare <= 0 then
		return
	end
	local dur = RELOAD_S[wp.kind] or 3
	reloadUntil = os.clock() + dur
	Net.event("Combat_Reload"):FireServer()
	playId(if wp.faction == "US" then S.reload_m14 else S.reload_type56, 0.7)
	Bus.fire("reload_start", dur, wp.kind)
end
Input.on("reload", "tap", startReload)
Input.on("reload", "press", startReload) -- R no teclado é "press"
Input.on("fire_mode", "tap", function()
	if weapon then
		modeIdx = modeIdx % #weapon.modes + 1
		say("Seletor: " .. string.upper(weapon.modes[modeIdx]))
	end
end)
Input.on("zeroing", "holdStart", function()
	zeroIdx = zeroIdx % #ZEROS + 1
	say(string.format("Alça de mira: %d m", ZEROS[zeroIdx]))
end)
Input.on("swap_weapon", "tap", function()
	if #slots > 1 then
		slot = slot % #slots + 1
		equip()
		say(if launcher then "Lançador" else (if weapon then weapon.name else "—"))
	end
end)
Input.on("swap_weapon", "press", function() -- tecla 1
	if #slots > 1 then
		slot = slot % #slots + 1
		equip()
		say(if launcher then "Lançador" else (if weapon then weapon.name else "—"))
	end
end)
Input.on("hold_breath", "press", function()
	local now = os.clock()
	if aiming and now >= breathReady then
		breathUntil = now + 4 -- PLACEHOLDER: 4 s de fôlego, 6 s para recuperar
		breathReady = now + 10
	end
end)
local function toggleBinoculars()
	binoculars = not binoculars
	binoc.Visible = binoculars
	player:SetAttribute("Binoculars", binoculars) -- local: a marcação vira "alvo" (área aproximada)
	if binoculars then
		setAim(false)
	end
end
Input.on("binoculars", "press", toggleBinoculars) -- tecla B
Input.on("binoculars", "tap", toggleBinoculars) -- direcional ↑ tocar (segurar: trocar ombro)
-- transpor/mergulhar (Movement.client): a arma sai do ombro e o dedo sai do gatilho
Bus.on("vault_start", function()
	firing = false
	setAim(false)
end)
local function melee()
	Net.event("Combat_Melee"):FireServer({ dir = camera.CFrame.LookVector })
	Haptics.fire(1.0, false)
end
Input.on("melee", "press", melee)
local function bayonet()
	local char = player.Character
	local on = not (char and char:GetAttribute("Bayonet") == true)
	Net.event("Posture_Set"):FireServer({ bayonet = on })
	say(if on then "Baioneta armada" else "Baioneta recolhida")
end
Input.on("bayonet", "holdStart", bayonet)
Input.on("bayonet", "press", bayonet)

-- estado: menus, mapa, morte, veículo cancelam mira e disparo (nada fica preso)
Input.StateChanged:Connect(function(cancelled: { string }, ctx: string)
	firing = false
	if table.find(cancelled, "aim") then
		aiming = false
	end
	if ctx ~= "infantry" and ctx ~= "aim" and binoculars then
		binoculars = false
		binoc.Visible = false
	end
end)

-- roda de equipamento: binóculo
Bus.on("equip_item", function(id: string)
	if id == "binoculars" then
		toggleBinoculars()
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local wp = weapon
	if firing and wp and wp.modes[modeIdx] == "auto" then
		fire()
	end
	Input.aimMode = if binoculars then "scope" elseif aiming then "ads" else "hip"
	if not seated() then
		-- mira: levar ao ombro leva tempo proporcional ao peso (Parte 10.4); binóculo 7x ≈ 10°
		-- FOV base ajustável (acessibilidade); a mira aproxima na mesma proporção (55/70)
		local base = Input.settings.fov
		local target = if binoculars then 10 elseif aiming then base * 55 / 70 else base
		local speed = if wp then 10 / math.max(wp.massLoadedKg, 1) else 4
		camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * speed)
	end
	-- balanço da mira (igual para controle e mouse): menor prendendo a respiração.
	-- Amplitude PLACEHOLDER (0,12° parado; dobra com o braço ferido).
	if aiming and wp then
		-- cansado (Movement.swayFactor): balança mais e mais rápido, como o peito arfando
		local st = player:GetAttribute("Stamina")
		local tired = Movement.swayFactor(if type(st) == "number" then st else 1)
		local ds = dt * (1 + 0.35 * (tired - 1)) -- o tempo do balanço corre mais rápido (a amplitude fica)
		swayT += ds
		local amp = 0.12 * tired * (if player:GetAttribute("ArmImpaired") then 2 else 1)
		if os.clock() < breathUntil then
			amp *= 0.2
		end
		local dp = math.cos(swayT * 1.3) * amp * 1.3 * ds
		local dyw = math.cos(swayT * 0.9) * amp * 0.9 * ds
		camera.CFrame *= CFrame.Angles(math.rad(dp), math.rad(dyw), 0)
	end
	-- aplica e recupera o recuo
	if recoilPitch ~= 0 or recoilYaw ~= 0 then
		local stepP = recoilPitch * math.min(1, dt * 18)
		local stepY = recoilYaw * math.min(1, dt * 18)
		camera.CFrame *= CFrame.Angles(math.rad(stepP), math.rad(-stepY), 0)
		recoilPitch -= stepP
		recoilYaw -= stepY
		if math.abs(recoilPitch) < 1e-3 and math.abs(recoilYaw) < 1e-3 then
			recoilPitch, recoilYaw = 0, 0
		end
	end
	-- volta da boca: mais lenta que a subida, só depois que ela termina (~0,25 s)
	if recoilReturn > 0 and math.abs(recoilPitch) < 0.05 then
		local back = recoilReturn * math.min(1, dt * 7)
		camera.CFrame *= CFrame.Angles(math.rad(-back), 0, 0)
		recoilReturn -= back
		if recoilReturn < 1e-3 then
			recoilReturn = 0
		end
	end
end)

player:GetAttributeChangedSignal("Loadout"):Connect(equip)
player:GetAttributeChangedSignal("CarriedWeapon"):Connect(equip)
player:GetAttributeChangedSignal("Role"):Connect(equip)
player.CharacterAdded:Connect(function()
	slot = 1
	aiming, firing, binoculars = false, false, false
	binoc.Visible = false
	equip()
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- primeira pessoa (Parte 10.5)
end)
equip()
