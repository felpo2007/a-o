--!strict
-- Arma (F2 + Parte 12): disparo com semente, mira (FOV), recarga, seletor, alça de mira,
-- balanço com "prender a respiração", recuo com tendência aleatória, troca de arma (o antitanque tem
-- o lançador como 2ª arma), binóculo, corpo a corpo e baioneta.
-- Sem retícula, sem hitmarker, sem contador de munição na tela (Parte 1). Entradas pela camada
-- Input: controle e teclado/mouse têm o MESMO balanço, inércia e recuo (Parte 12.4).
-- 3ª pessoa (ThirdPerson.client): o tiro sai do OLHO do personagem e vai até o ponto da retícula
-- (ViewMode), nunca da câmera atrás do ombro; do quadril, com a dispersão de Movement.hipSpreadDeg.
-- O cansaço (Movement.client, atributo "Stamina") aumenta o balanço da mira de ferro.
-- 2026-11-12 (pedido do dono: armas automáticas, armas que não atiravam, sniper, tiro do veículo):
--   - o gatilho é o Shared/Gatilho (o mesmo que o servidor confere): um gatilho por arma, com a
--     munição e o seletor dela; segurar no automático sai na cadência cíclica; o toque no semi que
--     cai no intervalo sai logo depois (antes era perdido); trocar de mira com o dedo no gatilho não
--     solta mais a rajada;
--   - seletor por papel (Weapons.modesFor): Tipo 56 no automático primeiro; M14 só no semi, salvo o
--     fuzileiro automático; ferrolho nos fuzis de precisão, com a luneta (Controllers/Luneta);
--   - lugar aberto de veículo (D-100): o gatilho e a recarga vêm do VehicleController pelo Bus
--     ("seat_fire", "seat_reload"); o tiro só sai com o atributo local "SeatFire" (ângulo do lugar).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local AssetIds = require(ReplicatedStorage.Shared.AssetIds)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Gatilho = require(ReplicatedStorage.Shared.Gatilho)
local Melee = require(ReplicatedStorage.Shared.Melee)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Haptics = require(script.Parent.Haptics)
local Input = require(script.Parent.Input)
local KnifeView = require(script.Parent.KnifeView)
local Luneta = require(script.Parent.Luneta)
local Toast = require(script.Parent.Toast)
local UiKit = require(script.Parent.UiKit)
local ViewMode = require(script.Parent.ViewMode)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local slots: { string } = {}
local slot = 1
local weapon: Weapons.Weapon? = nil
local launcher = false -- slot do foguete (antitanque)
local aiming = false
local binoculars = false
local lastLaunch = 0
local seedRng = Rng.new(os.time() + player.UserId)
local recoilPitch, recoilYaw = 0, 0
local recoilReturn = 0 -- graus que a boca ainda desce sozinha depois da subida
local RECOIL_DEG_PER_MS = 0.9 -- graus de subida por m/s de recuo livre
local RECOIL_RETURN = 0.6 -- fração da subida que volta sozinha (o resto o jogador corrige)
local swayT = 0
-- gatilho, munição de reserva e alça (índice em Weapons.zeros) de cada arma
local triggers: { [string]: Gatilho.Trigger } = {}
local spareBy: { [string]: number } = {}
local zeroBy: { [string]: number } = {}
-- respiração presa (PLACEHOLDER: até 4 s; soltar depois de 3 s cansa por 2,5 s)
local breath = { untilT = 0, start = 0, ready = 0, outUntil = 0, len = 4 }
-- luneta: mistura 0..1 de levar o olho à ocular
local scope = { blend = 0 }
-- bipé (Weapons.BIPOD): "prone" (armado no chão), "rested" (guarda-mão sobre um apoio) ou nil
local bipod = { state = nil :: string?, params = RaycastParams.new() }
bipod.params.FilterType = Enum.RaycastFilterType.Exclude
bipod.params.RespectCanCollide = true

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

local function seatPart(): BasePart?
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum.SeatPart
end

local function seated(): boolean
	return seatPart() ~= nil
end

local function myRole(): string?
	local r = player:GetAttribute("Role")
	return if type(r) == "string" then r else nil
end

local function triggerFor(wp: Weapons.Weapon): Gatilho.Trigger
	local t = triggers[wp.id]
	if not t then
		t = Gatilho.new(wp.id, Weapons.modesFor(wp, myRole())[1], 0)
		triggers[wp.id] = t
	end
	-- o papel pode ter mudado: o modo continua só se o papel o tem
	if not Weapons.modeAllowed(wp, t.mode, myRole()) then
		t.mode = Weapons.modesFor(wp, myRole())[1]
	end
	return t
end

-- Arma que atira agora: sentado, a do lugar aberto (a principal, "Weapon" do assento); a pé, a
-- equipada. Lugar fechado ou lançador: nenhuma.
local function active(): (Weapons.Weapon?, Gatilho.Trigger?)
	local s = seatPart()
	if s then
		local id = s:GetAttribute("Weapon")
		local wp = if s:GetAttribute("Personal") == true and type(id) == "string" then Weapons.get(id) else nil
		if wp and wp.enabled then
			return wp, triggerFor(wp)
		end
		return nil, nil
	end
	local wp = weapon
	if wp then
		return wp, triggerFor(wp)
	end
	return nil, nil
end

local function aimingNow(): boolean
	if seated() then
		return player:GetAttribute("VehicleAim") == true
	end
	return aiming
end

local function zeroOf(wp: Weapons.Weapon): number
	local list = Weapons.zeros(wp)
	return list[math.clamp(zeroBy[wp.id] or 1, 1, #list)]
end

local function equip()
	for _, t in triggers do
		Gatilho.cancel(t)
	end
	local s = player:GetAttribute("Loadout")
	slots = if type(s) == "string" then string.split(s, ",") else {}
	-- arma pega do chão (servidor) substitui a principal até o próximo spawn
	local carried = player:GetAttribute("CarriedWeapon")
	if type(carried) == "string" and #slots > 0 then
		slots[1] = carried
	elseif type(carried) == "string" then
		slots = { carried }
	end
	if player:GetAttribute("Role") == "anti_tank" then
		table.insert(slots, "launcher")
	end
	slot = math.clamp(slot, 1, math.max(#slots, 1))
	local id = slots[slot]
	launcher = id == "launcher"
	local wp = if id and not launcher then Weapons.get(id) else nil
	weapon = if wp and wp.enabled then wp else nil
	local t = if weapon then triggerFor(weapon) else nil
	-- local (não replica): a arma em primeira pessoa (WeaponVisuals) segue a arma equipada
	player:SetAttribute("EquippedWeapon", if launcher then "launcher" elseif weapon then weapon.id else nil)
	player:SetAttribute("FireMode", if t then t.mode else nil)
	if weapon then
		-- o servidor reenvia a munição desta arma (o cartão da arma no HUD mostra a equipada)
		Net.event("Combat_Ammo"):FireServer({ w = weapon.id })
	end
end

Net.event("Combat_Ammo").OnClientEvent:Connect(function(a)
	if type(a) ~= "table" then
		return
	end
	local id = if type(a.w) == "string" then a.w elseif type(a.weapon) == "string" then a.weapon else nil
	local wp = if id then Weapons.get(id) elseif weapon then weapon else nil
	if not wp then
		return
	end
	local t = triggerFor(wp)
	local mag = tonumber(a.mag) or t.mag
	local spare = if type(a.spare) == "number" then a.spare else spareBy[wp.id]
	-- só a recarga (ou munição nova) libera o gatilho; a resposta à troca de arma não
	if mag ~= t.mag or spare ~= spareBy[wp.id] then
		t.reloadUntil = 0
	end
	t.mag = mag
	spareBy[wp.id] = spare
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
	m70 = S.shot_m14, -- .30-06: PLACEHOLDER até um som próprio
	m79 = S.mortar_launch, -- "tump" do 40 mm: PLACEHOLDER (som do morteiro)
	type56 = S.shot_type56,
	sks = S.shot_type56,
	rpd = S.shot_type56,
	type54 = S.shot_type56,
	mosin = S.shot_type56, -- 7,62x54R: PLACEHOLDER até um som próprio
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

-- O corpo deixa atirar agora? Sentado: só com "SeatFire" (lugar aberto, 1ª pessoa, no ângulo).
local function canShoot(): boolean
	local char = player.Character
	if not (char and char:FindFirstChild("Head")) or binoculars then
		return false
	end
	if player:GetAttribute("Downed") or bodyBusy() then
		return false
	end
	if Input.state.map then -- carta aberta na mão (D-98): o fuzil está a tiracolo
		return false
	end
	if seated() then
		return player:GetAttribute("SeatFire") == true
	end
	return not KnifeView.busy()
end

-- Origem e direção do tiro. 1ª pessoa: a câmera (o olho). 3ª pessoa: do olho até o ponto da
-- retícula, com a dispersão do quadril (semente própria, derivada da do tiro).
local function shotRay(seed: number): (Vector3, Vector3)
	local o, d = ViewMode.aimDirection()
	if ViewMode.third and not aiming and not seated() then
		local r = Rng.new(seed + 7)
		local spread = math.rad(ViewMode.hipSpread())
		local ang, rad = r:next() * 2 * math.pi, spread * math.sqrt(r:next())
		local cf = CFrame.lookAt(Vector3.zero, d) * CFrame.Angles(rad * math.sin(ang), rad * math.cos(ang), 0)
		d = cf.LookVector
	end
	return o, d
end

-- Sai um tiro (o Gatilho já decidiu): manda ao servidor, efeitos locais e recuo.
local function shoot(wp: Weapons.Weapon, t: Gatilho.Trigger)
	local char = player.Character
	local seed = seedRng:nextU32()
	local o, look = shotRay(seed)
	-- alça zerada: o cano sobe o ângulo de zeragem em relação à linha de visada
	local zero = Ballistics.zeroAngle(wp.id, zeroOf(wp))
	local third = ViewMode.third and not seated()
	local basis = if third then CFrame.lookAt(Vector3.zero, look) else camera.CFrame.Rotation
	local d = (basis * CFrame.Angles(zero, 0, 0)).LookVector
	local shot: { [string]: any } = {
		w = wp.id,
		m = t.mode,
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
	if third then
		shot.by = char -- 3ª pessoa: o traçante local sai da arma do corpo (a de 1ª pessoa some)
	end
	Bus.fire("shot_fired", shot) -- clarão, recuo da arma e poeira no impacto (WeaponVisuals)
	playId(SHOT_SOUND[wp.id] or 0, if wp.kind == "launcher" then 0.5 else 0.8)
	if wp.kind == "mg" and seed % 5 == 0 then
		tracer(shot, tracerColor(wp.faction))
	end
	if t.mode == "bolt" then
		Bus.fire("bolt_cycle", Weapons.interval(wp, "bolt")) -- ferrolho na 1ª pessoa (WeaponVisuals)
	end
	-- Recuo (D-69): velocidade de recuo livre (impulso do projétil e dos gases, ~1,5x, contra a
	-- massa da arma, em m/s) vira graus de subida da boca. Antes a conta fazia math.deg da
	-- velocidade: ~100° por tiro na M14, e a câmera ia ao céu ("diminua recoil", usuário).
	-- Agora: M14 ~2,3°, Type 56 ~2,1°, M60 ~1,0°, M1911 ~4,6°, M70 ~2,1°, Mosin ~2,4° e M79 ~8°.
	-- Padrão aleatório com tendência por semente (Parte 10.3); parte volta sozinha (RECOIL_RETURN).
	-- No automático a subida soma tiro a tiro (a volta só começa quando a rajada para).
	local impulse = (wp.bulletMassG / 1000) * wp.muzzleVelocity * 1.5
	local kick = (impulse / wp.massLoadedKg) * RECOIL_DEG_PER_MS
	if player:GetAttribute("ArmImpaired") then
		kick *= 1.5
	end
	if aimingNow() then
		kick *= 0.8
	end
	local bp = bipod.state and Weapons.BIPOD[bipod.state]
	if bp then
		kick *= bp.kick -- bipé armado ou arma apoiada: a boca sobe menos
	end
	local r = Rng.new(seed)
	recoilPitch += kick
	recoilYaw += (r:next() - 0.35) * kick * 0.6 -- tendência leve para a direita
	recoilReturn += kick * RECOIL_RETURN
	Haptics.fire(kick, t.mode == "auto")
end

-- foguete do antitanque (slot "launcher"): pelo VehicleService, como antes
local function launchRocket()
	local now = os.clock()
	if now - lastLaunch > 1 and canShoot() and not seated() then
		lastLaunch = now
		local _, dir = ViewMode.aimDirection() -- o foguete sai da cabeça (VehicleService)
		Net.event("Vehicle_Fire"):FireServer({ dir = dir })
		Haptics.fire(1.6, false)
	end
end

-- ===== entradas (camada Input) =====
local function triggerDown()
	if launcher and not seated() then
		launchRocket()
		return
	end
	if not seated() and KnifeView.busy() then -- faca na mão (D-94): o gatilho a devolve à bainha
		KnifeView.sheatheNow()
		return
	end
	local _, t = active()
	if t then
		Gatilho.press(t, os.clock())
	end
end
local function triggerUp()
	local _, t = active()
	if t then
		Gatilho.release(t, os.clock())
	end
end
Input.on("fire", "press", triggerDown)
Input.on("fire", "release", triggerUp)
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
-- Recarga (D-69): pede ao servidor e, se ele vai aceitar (há carregador, não está recarregando e
-- o carregador não está cheio), o WeaponVisuals anima a troca com as mãos no tempo do servidor.
local function startReload()
	local wp, t = active()
	local now = os.clock()
	if not (wp and t) or now < t.reloadUntil or (spareBy[wp.id] or 0) <= 0 or t.mag >= wp.magazine then
		return
	end
	if not seated() and KnifeView.busy() then
		KnifeView.sheatheNow()
		return
	end
	local dur = Weapons.reloadTime(wp, Vantagens.mult(player, "reload")) -- "Mãos Rápidas" (o servidor confere)
	-- o servidor manda: o gatilho só volta com a munição nova (Combat_Ammo); a folga cobre a rede
	t.reloadUntil = now + dur + 1
	Gatilho.cancel(t)
	Net.event("Combat_Reload"):FireServer({ w = wp.id })
	playId(if wp.faction == "US" then S.reload_m14 else S.reload_type56, 0.7)
	Bus.fire("reload_start", dur, wp.kind)
end
Input.on("reload", "tap", startReload)
Input.on("reload", "press", startReload) -- R no teclado é "press"
-- D-100: no lugar aberto do veículo o gatilho (RT/LMB) e a recarga (X) vêm do VehicleController
Bus.on("seat_fire", function(on: boolean)
	local wp, t = active()
	if not (wp and t) then
		return
	end
	if on then
		if t.mag <= 0 and (spareBy[wp.id] or 0) > 0 then
			startReload() -- na porta do helicóptero não há botão de recarga: o gatilho vazio recarrega
		else
			Gatilho.press(t, os.clock())
		end
	else
		Gatilho.release(t, os.clock())
	end
end)
Bus.on("seat_reload", startReload)

-- alça: segurar sobe; arma de um modo só e alça longa (M79, lunetas): tocar desce
local function stepZero(dir: number)
	local wp = active()
	if not wp then
		return
	end
	local list = Weapons.zeros(wp)
	local i = (zeroBy[wp.id] or 1) + dir
	if i > #list then
		i = 1
	elseif i < 1 then
		i = #list
	end
	zeroBy[wp.id] = i
	say(string.format("Alça de mira: %d m", list[i]))
end
Input.on("fire_mode", "tap", function()
	local wp, t = active()
	if not (wp and t) then
		return
	end
	local modes = Weapons.modesFor(wp, myRole())
	if #modes == 1 and #Weapons.zeros(wp) > 3 then
		stepZero(-1)
		return
	end
	local i = table.find(modes, t.mode) or 0
	t.mode = modes[i % #modes + 1]
	Gatilho.cancel(t)
	player:SetAttribute("FireMode", t.mode)
	say(string.format("Seletor: %s", string.upper(t.mode)))
end)
Input.on("zeroing", "holdStart", function()
	stepZero(1)
end)
local function swap()
	if #slots > 1 then
		slot = slot % #slots + 1
		equip()
		say(if launcher then "Lançador" else (if weapon then weapon.name else "—"))
	end
end
Input.on("swap_weapon", "tap", swap)
Input.on("swap_weapon", "press", swap) -- tecla 1
-- prender a respiração: segurar (LB / Shift) até Weapons.BREATH_S (4 s; na luneta, vezes a vantagem
-- "breath" do passe "Fôlego de Atirador", 1,6); soltar antes acaba
local function endBreath(at: number)
	local held = at - breath.start
	breath.untilT = 0
	breath.ready = at + 1 + held * 0.5
	if held > breath.len * Weapons.BREATH_TIRED_K then
		breath.outUntil = at + 2.5 -- PLACEHOLDER: fôlego curto depois de segurar muito
	end
end
Input.on("hold_breath", "press", function()
	local now = os.clock()
	if aimingNow() and now >= breath.ready and breath.untilT == 0 then
		breath.len = Weapons.breathTime(player:GetAttribute("Scoped") == true, Vantagens.mult(player, "breath"))
		breath.start, breath.untilT = now, now + breath.len
	end
end)
Input.on("hold_breath", "release", function()
	local now = os.clock()
	if breath.untilT > 0 and now < breath.untilT then
		endBreath(now)
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
	for _, t in triggers do
		Gatilho.cancel(t)
	end
	setAim(false)
end)
-- Corpo a corpo (D-94, Shared/Melee): o toque pede o golpe ao servidor (que decide e confere tudo)
-- e começa já a animação de 1ª pessoa (KnifeView) e a de 3ª (SoldierAnimations, "melee_start").
-- Sem baioneta: faca (estocada; 2º toque logo depois = golpe de lado). Com a baioneta: estocada de
-- baioneta. O cliente espelha o intervalo do servidor só para não pedir à toa.
local meleeS = { last = nil :: string?, lastAt = -10, nextAt = 0, knifeUntil = 0 }
local function melee(rifle: boolean?)
	local char = player.Character
	if not char or seated() or binoculars or player:GetAttribute("Downed") or bodyBusy() then
		return
	end
	local now = os.clock()
	local _, t = active()
	if now < meleeS.nextAt or (t and now < t.reloadUntil) then
		return
	end
	local id = Melee.choose(char:GetAttribute("Bayonet") == true, rifle == true, meleeS.last, now - meleeS.lastAt)
	local a = Melee.get(id)
	if not a then
		return
	end
	local knifeOut = now < meleeS.knifeUntil
	local delay = Melee.impactDelay(id, knifeOut)
	meleeS.nextAt = now + Melee.cooldown(id, knifeOut)
	meleeS.last, meleeS.lastAt = id, now + delay - a.impact
	if a.weapon == "knife" then
		meleeS.knifeUntil = now + delay + a.recover + Melee.SHEATHE_AFTER_S
	end
	if t then
		Gatilho.cancel(t)
	end
	setAim(false)
	Net.event("Combat_Melee"):FireServer({ dir = camera.CFrame.LookVector, rifle = rifle == true })
	KnifeView.start(id, a.weapon == "knife" and not knifeOut)
	Bus.fire("melee_start", id, a.weapon == "knife" and not knifeOut)
	task.delay(delay, function()
		Haptics.fire(if a.weapon == "knife" then 0.9 else 1.4, false)
	end)
end
Input.on("melee", "press", function()
	melee(false)
end)
-- Studio:
--   workspace:SetAttribute("VT65DevFaca", "estocada" | "lado" | "baioneta" | "coronhada" | "laco" |
--   "parar") golpeia em 1ª pessoa (o resto do gancho é do servidor, MeleeService);
--   workspace:SetAttribute("VT65DevRajada", s) segura o gatilho por s segundos (0,05 = um toque) e
--   escreve no Output os tiros que saíram, a cadência medida e a munição (a arma vem do servidor:
--   VT65DevArma); o servidor escreve os tiros recusados ("[VT65 ARMAS] tiro recusado").
if RunService:IsStudio() then
	local devLoop = 0
	workspace:GetAttributeChangedSignal("VT65DevFaca"):Connect(function()
		local v = workspace:GetAttribute("VT65DevFaca")
		devLoop += 1
		local loop = devLoop
		if v == "estocada" then
			melee(false)
		elseif v == "coronhada" then
			melee(true)
		elseif v == "lado" then
			melee(false)
			task.delay(0.62, melee, false)
		elseif v == "baioneta" then
			Net.event("Posture_Set"):FireServer({ bayonet = true })
			task.delay(0.5, melee, false)
		elseif v == "laco" then
			task.spawn(function()
				while devLoop == loop do
					melee(false)
					task.wait(0.62)
					melee(false)
					task.wait(2.6)
				end
			end)
		end
	end)
	workspace:GetAttributeChangedSignal("VT65DevRajada"):Connect(function()
		local secs = workspace:GetAttribute("VT65DevRajada")
		local wp, t = active()
		if type(secs) ~= "number" or not (wp and t) then
			return
		end
		local mag0, shots = t.mag, 0
		local conn = Bus.on("shot_fired", function()
			shots += 1
		end)
		triggerDown()
		task.wait(secs)
		triggerUp()
		task.wait(0.1)
		conn:Disconnect()
		print(
			string.format(
				"[VT65 ARMAS] %s (%s): %d tiro(s) em %.2f s; cadência da ficha %d/min; carregador %d -> %d",
				wp.id,
				t.mode,
				shots,
				secs,
				wp.rpm,
				mag0,
				t.mag
			)
		)
	end)
end
local function bayonet()
	local char = player.Character
	local on = not (char and char:GetAttribute("Bayonet") == true)
	Net.event("Posture_Set"):FireServer({ bayonet = on })
	say(if on then "Baioneta armada" else "Baioneta recolhida")
end
Input.on("bayonet", "holdStart", bayonet)
Input.on("bayonet", "press", bayonet)

-- estado: menus, mapa, morte, veículo cancelam mira e disparo (nada fica preso). Entrar e sair da
-- mira (contexto "aim", que tem a infantaria por baixo) NÃO solta o gatilho: antes a rajada parava
-- ao apertar ou soltar a mira com o dedo no gatilho.
Input.StateChanged:Connect(function(cancelled: { string }, ctx: string)
	if ctx ~= "infantry" and ctx ~= "aim" then
		for _, t in triggers do
			Gatilho.cancel(t)
		end
	end
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

-- Bipé da arma neste quadro: deitado, armado no chão; de pé ou agachado mirando, apoiado se há
-- superfície até 0,3 m abaixo do guarda-mão (~0,55 m à frente do olho). Sentado, nenhum.
local function bipodNow(wp: Weapons.Weapon?): string?
	local char = player.Character
	if not (wp and char) or seated() or not Weapons.hasBipod(wp, myRole()) then
		return nil
	end
	if char:GetAttribute("Prone") == true then
		return "prone"
	end
	if not aiming then
		return nil
	end
	local cf = camera.CFrame
	bipod.params.FilterDescendantsInstances = { char, camera }
	local hit =
		workspace:Raycast(cf.Position + cf.LookVector * (0.55 / 0.28), Vector3.new(0, -0.3 / 0.28, 0), bipod.params)
	return if hit then "rested" else nil
end

-- balanço da mira: postura (deitado firma, PLACEHOLDER), respiração presa e fôlego curto
local function swayAmp(now: number): number
	local st = player:GetAttribute("Stamina")
	local tired = Movement.swayFactor(if type(st) == "number" then st else 1)
	local char = player.Character
	local stance = if char and char:GetAttribute("Prone") == true
		then 0.4
		elseif char and char:GetAttribute("Crouched") == true then 0.7
		else 1
	local amp = 0.12 * tired * stance * (if player:GetAttribute("ArmImpaired") then 2 else 1)
	local bp = bipod.state and Weapons.BIPOD[bipod.state]
	if bp then
		amp *= bp.sway
	end
	if player:GetAttribute("Scoped") == true then
		amp *= Vantagens.mult(player, "sway") -- "Fôlego de Atirador": 0,88 na luneta (teto de 12%)
	end
	if breath.untilT > 0 then
		amp *= 0.15
	elseif now < breath.outUntil then
		amp *= 1.7
	end
	return amp
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local wp, t = active()
	-- gatilho: o mesmo passo para mouse, controle e assento (Shared/Gatilho)
	if wp and t and Gatilho.wants(t, now) then
		if canShoot() then
			local act = Gatilho.step(t, now)
			if act == "fire" then
				shoot(wp, t)
			elseif act == "dry" then
				playId(S.dry_click, 0.8) -- Type 56 sem trava do ferrolho: só o clique (Parte 10.6)
			end
		elseif not t.held then
			t.queued = 0
		end
	end
	if breath.untilT > 0 and now >= breath.untilT then
		endBreath(breath.untilT)
	end
	local bs = bipodNow(wp)
	if bs ~= bipod.state then
		if bs == "prone" then
			say("Bipé armado") -- só ao deitar (apoiar e tirar do apoio é contínuo, sem aviso)
		end
		bipod.state = bs
		player:SetAttribute("Bipe", bs) -- local: "prone" | "rested" | nil (HUD, se quiser)
	end
	local aimNow = aimingNow()
	-- luneta: o olho chega à ocular, a tela vira a luneta e o FOV vai ao da luneta
	local sc = if wp and wp.scope and aiming and not binoculars and not seated() then wp.scope else nil
	local reloading = t ~= nil and now < t.reloadUntil
	scope.blend += ((if sc and not reloading then 1 else 0) - scope.blend) * math.min(1, dt * 9)
	local scoped = sc ~= nil and scope.blend > 0.8
	if player:GetAttribute("Scoped") ~= scoped then
		player:SetAttribute("Scoped", scoped) -- local: a arma de 1ª pessoa some (WeaponVisuals)
	end
	Input.aimMode = if binoculars or scoped then "scope" elseif aimNow then "ads" else "hip"
	if not seated() then
		-- mira: levar ao ombro leva tempo proporcional ao peso (Parte 10.4); binóculo 7x ≈ 10°
		-- FOV base ajustável (acessibilidade); a mira fecha um pouco (Weapons.ADS_FOV_K)
		local base = Input.settings.fov
		if scoped and sc then
			camera.FieldOfView = sc.fov -- a troca fica atrás do piscar da luneta
		else
			local target = if binoculars then 10 elseif aiming then base * Weapons.ADS_FOV_K else base
			local speed = if wp then 10 / math.max(wp.massLoadedKg, 1) else 4
			if camera.FieldOfView < base * 0.5 and not binoculars then
				speed = 10 -- saindo da luneta: o olho desencosta logo, não espera o peso da arma
			end
			camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * speed)
		end
	end
	-- balanço da mira (igual para controle e mouse): menor prendendo a respiração e deitado.
	-- Amplitude PLACEHOLDER (0,12° de pé; dobra com o braço ferido).
	if aimNow and wp then
		-- cansado (Movement.swayFactor): balança mais e mais rápido, como o peito arfando
		local st = player:GetAttribute("Stamina")
		local tired = Movement.swayFactor(if type(st) == "number" then st else 1)
		local ds = dt * (1 + 0.35 * (tired - 1)) -- o tempo do balanço corre mais rápido (a amplitude fica)
		swayT += ds
		local amp = swayAmp(now)
		local dp = math.cos(swayT * 1.3) * amp * 1.3 * ds
		local dyw = math.cos(swayT * 0.9) * amp * 0.9 * ds
		camera.CFrame *= CFrame.Angles(math.rad(dp), math.rad(dyw), 0)
	end
	-- tela da luneta: o círculo foge um pouco do centro com o coice e com o ferrolho manobrando
	if scoped and sc and t and wp then
		local cyc = 0
		if Gatilho.cycling(t, now) then
			cyc = math.sin(math.clamp((now - t.last) / Weapons.interval(wp, "bolt"), 0, 1) * math.pi)
		end
		Luneta.update(sc.reticle, camera.FieldOfView, Vector2.new(-recoilYaw * 0.01, recoilPitch * 0.02 + cyc * 0.12))
	else
		Luneta.update(nil, camera.FieldOfView, Vector2.zero)
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
	aiming, binoculars = false, false
	binoc.Visible = false
	breath.untilT, breath.outUntil = 0, 0
	for _, t in triggers do
		Gatilho.cancel(t)
		t.reloadUntil = 0
	end
	equip()
	player.CameraMode = Enum.CameraMode.LockFirstPerson -- primeira pessoa (Parte 10.5)
end)
equip()
