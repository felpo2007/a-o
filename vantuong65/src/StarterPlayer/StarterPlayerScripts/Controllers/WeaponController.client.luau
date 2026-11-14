--!strict
-- Arma (F2 + Parte 12): disparo com semente, mira (FOV), recarga, seletor, alça de mira,
-- balanço com "prender a respiração", recuo com tendência aleatória, troca de arma (o antitanque tem
-- o lançador como 2ª arma), binóculo, corpo a corpo e baioneta.
-- Sem contador de munição na tela (Parte 1); o marcador de acerto veio na D-107 e a retícula do
-- quadril em 1ª pessoa na v41 (pedido do dono; mirando, só a alça e a massa). Entradas pela camada
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
-- 2026-11-13 (pedido do dono: "não consigo puxar arma e selecionar os itens", "arma secundária para
-- todos", granada de fumaça do Front 44, recarga automática):
--   - vagas (Shared/Equipar): teclas 1 a 0 escolhem direto (1 principal, 2 pistola, 3 granada, 4
--     fumaça, 5–0 itens), a roda do mouse, o Y e o botão ARMA do toque trocam de arma; a arma da mão
--     desce e a nova sobe (KnifeView.troca, tempos do Front 44) e o servidor põe a arma certa na mão do
--     corpo (Posture_Set { arma }, Modules/ArmaNaMao: a principal vai às costas);
--   - granada e fumaça NA MÃO (vagas 3 e 4, roda de equipamento e último item): apertar o gatilho
--     tira o pino e arma o braço; soltar lança; mirando ao soltar, por baixo (Front 44). Depois volta
--     para a arma (ItemView desenha as mãos);
--   - o binóculo e a faca saem com o gatilho (antes o gatilho não fazia nada com o binóculo);
--   - recarga automática: o gatilho no carregador vazio recarrega (todas as plataformas, como no Front
--     44); no toque e no controle a recarga também sai sozinha quando o carregador esvazia (opção
--     autoReload). Para as telas: atributos locais AutoRecarga, Carregador, Reserva, Recarregando,
--     Vagas, Vaga e ItemNaMao no LocalPlayer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local AssetIds = require(ReplicatedStorage.Shared.AssetIds)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Equipar = require(ReplicatedStorage.Shared.Equipar)
local Gatilho = require(ReplicatedStorage.Shared.Gatilho)
local InputMap = require(ReplicatedStorage.Shared.InputMap)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local Melee = require(ReplicatedStorage.Shared.Melee)
local Movement = require(ReplicatedStorage.Shared.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Bus = require(script.Parent.Bus)
local Haptics = require(script.Parent.Haptics)
local Input = require(script.Parent.Input)
local ItemView = require(script.Parent.ItemView)
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
-- graus de subida por m/s de recuo livre. v43 (pedido do dono: "diminua o recoil das armas"): 0,9 -> 0,6
-- (M14 ~1,5° por tiro, Type 56 ~1,4°, M60 ~0,7°, M1911 ~3,1°)
local RECOIL_DEG_PER_MS = 0.6
-- fração da subida que volta sozinha (o resto o jogador corrige). D-107 ("mais fast paced"): 0,6 -> 0,75;
-- v43: 0,85
local RECOIL_RETURN = 0.85
local RECOIL_YAW = 0.45 -- desvio para o lado (fração da subida); era 0,6
local swayT = 0
-- gatilho, munição de reserva e alça (índice em Weapons.zeros) de cada arma
local triggers: { [string]: Gatilho.Trigger } = {}
local spareBy: { [string]: number } = {}
local zeroBy: { [string]: number } = {}
-- respiração presa (PLACEHOLDER: até 4 s; soltar depois de 3 s cansa por 2,5 s)
local breath = { untilT = 0, start = 0, ready = 0, outUntil = 0, len = 4 }
-- luneta: mistura 0..1 de levar o olho à ocular
local scope = { blend = 0 }
-- vagas e mão (2026-11-13, Shared/Equipar): granada na mão, arma para voltar depois do arremesso,
-- troca em andamento (a última vale), até quando a troca segura o gatilho, o que o servidor sabe da
-- mão, "mirando" com a granada (por baixo) e a recarga automática pendente
local inv = {
	hand = nil :: Equipar.Hand?,
	prev = 1,
	token = 0,
	busyUntil = 0,
	sent = nil :: string?,
	under = false,
	autoAt = 0,
}
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

-- O servidor põe na mão do corpo o que este cliente tem na mão (Modules/ArmaNaMao): a arma da vaga
-- ("launcher" para o lançador) ou "frag"/"smoke".
local function tellServer(id: string?)
	if id ~= inv.sent then
		inv.sent = id
		Net.event("Posture_Set"):FireServer({ arma = id or false })
	end
end

-- granada na mão (nil = nenhuma): o ItemView desenha as mãos; a faixa das vagas mostra
local function setHand(h: Equipar.Hand?)
	inv.hand = h
	inv.under = false
	ItemView.hand(h)
	player:SetAttribute("ItemNaMao", if h then h.kind else nil)
end

local function equip()
	for _, t in triggers do
		Gatilho.cancel(t)
	end
	local s = player:GetAttribute("Loadout")
	-- arma pega do chão (servidor) substitui a principal até o próximo spawn; o lançador do antitanque
	-- vem depois das armas (Shared/Equipar)
	local carried = player:GetAttribute("CarriedWeapon")
	slots = Equipar.weapons(
		if type(s) == "string" and s ~= "" then string.split(s, ",") else {},
		myRole(),
		if type(carried) == "string" then carried else nil
	)
	slot = math.clamp(slot, 1, math.max(#slots, 1))
	local id = slots[slot]
	launcher = id == "launcher"
	local wp = if id and not launcher then Weapons.get(id) else nil
	weapon = if wp and wp.enabled then wp else nil
	local t = if weapon then triggerFor(weapon) else nil
	-- local (não replica): a arma em primeira pessoa (WeaponVisuals) segue a arma equipada; o lançador
	-- mostra a arte que houver (RPG-2 do VC; Equipar.handId)
	local faction = player:GetAttribute("Faction")
	local shown = Equipar.handId(
		if launcher then "launcher" elseif weapon then weapon.id else nil,
		if type(faction) == "string" then faction else nil
	)
	player:SetAttribute("EquippedWeapon", shown)
	player:SetAttribute("FireMode", if t then t.mode else nil)
	player:SetAttribute("Vagas", table.concat(slots, ","))
	player:SetAttribute("Vaga", slot)
	if weapon then
		-- o servidor reenvia a munição desta arma (o cartão da arma no HUD mostra a equipada)
		Net.event("Combat_Ammo"):FireServer({ w = weapon.id })
	end
	if not inv.hand and player.Character then
		tellServer(if launcher then "launcher" elseif weapon then weapon.id else nil)
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
-- o som do próprio tiro é do AudioController (Bus "shot_fired", Shared/SomArmas; D-107)
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
	-- granada na mão ou arma subindo/descendo na troca: o dedo não chega ao gatilho
	if inv.hand or os.clock() < inv.busyUntil then
		return false
	end
	return not KnifeView.busy()
end

-- Origem e direção do tiro. 1ª pessoa: a câmera (o olho). 3ª pessoa: do olho até o ponto da
-- retícula. Sem mirar, a dispersão do quadril (semente própria, derivada da do tiro); v41: também em
-- 1ª pessoa, que ganhou a retícula do quadril (sem ela, mirar não valeria nada com a retícula na tela).
local function shotRay(seed: number): (Vector3, Vector3)
	local o, d = ViewMode.aimDirection()
	if not aiming and not seated() then
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
	local hipSpread = not aiming and not seated() -- a direção já tem a dispersão do quadril
	local basis = if third or hipSpread then CFrame.lookAt(Vector3.zero, look) else camera.CFrame.Rotation
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
	Bus.fire("shot_fired", shot) -- clarão, recuo e poeira (WeaponVisuals); som (AudioController); acerto (Acerto)
	if wp.kind == "mg" and seed % 5 == 0 then
		tracer(shot, tracerColor(wp.faction))
	end
	if t.mode == "bolt" or t.mode == "pump" then
		-- ferrolho na 1ª pessoa (WeaponVisuals/Ferrolho); D-108: a bomba da espingarda também
		Bus.fire("bolt_cycle", Weapons.interval(wp, t.mode), wp.id)
	end
	-- Recuo (D-69): velocidade de recuo livre (impulso do projétil e dos gases, ~1,5x, contra a
	-- massa da arma, em m/s) vira graus de subida da boca. Antes a conta fazia math.deg da
	-- velocidade: ~100° por tiro na M14, e a câmera ia ao céu ("diminua recoil", usuário).
	-- Agora: M14 ~2,3°, Type 56 ~2,1°, M60 ~1,0°, M1911 ~4,6°, M70 ~2,1°, Mosin ~2,4° e M79 ~8°.
	-- Padrão aleatório com tendência por semente (Parte 10.3); parte volta sozinha (RECOIL_RETURN).
	-- No automático a subida soma tiro a tiro (a volta só começa quando a rajada para).
	local impulse = ((wp.chargeG or wp.bulletMassG) / 1000) * wp.muzzleVelocity * 1.5 -- D-108: 9 bagos
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
	recoilYaw += (r:next() - 0.35) * kick * RECOIL_YAW -- tendência leve para a direita
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

-- binóculo (tecla B, direcional ↑, roda de equipamento, vaga 7)
local function toggleBinoculars()
	binoculars = not binoculars
	binoc.Visible = binoculars
	player:SetAttribute("Binoculars", binoculars) -- local: a marcação vira "alvo" (área aproximada)
	if binoculars then
		setAim(false)
	end
end

-- Recarga (D-69): pede ao servidor e, se ele vai aceitar (há carregador, não está recarregando e
-- o carregador não está cheio), o WeaponVisuals anima a troca com as mãos no tempo do servidor.
local function startReload()
	local wp, t = active()
	local now = os.clock()
	if not (wp and t) or now < t.reloadUntil or (spareBy[wp.id] or 0) <= 0 or t.mag >= wp.magazine then
		return
	end
	if not seated() and (inv.hand or now < inv.busyUntil) then
		return -- granada na mão ou troca de arma: a recarga espera
	end
	if not seated() and KnifeView.busy() then
		KnifeView.sheatheNow()
		return
	end
	inv.autoAt = 0
	-- "Mãos Rápidas" (o servidor confere); D-108: a espingarda carrega cartucho a cartucho
	local spare = spareBy[wp.id] or 0
	local dur = Weapons.reloadTime(wp, Vantagens.mult(player, "reload"), t.mag, spare)
	-- o servidor manda: o gatilho só volta com a munição nova (Combat_Ammo); a folga cobre a rede
	t.reloadUntil = now + dur + 1
	Gatilho.cancel(t)
	Net.event("Combat_Reload"):FireServer({ w = wp.id })
	if wp.feed ~= "tube" then -- a espingarda: o som de cada cartucho (Ferrolho)
		playId(if wp.faction == "US" then S.reload_m14 else S.reload_type56, 0.7)
	end
	Bus.fire("reload_start", dur, wp.kind, Weapons.tubeShells(wp, t.mag, spare), t.mag <= 0, wp.id)
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
-- ===== vagas: trocar de arma e puxar itens (2026-11-13, Shared/Equipar) =====
local function nameOf(id: string?): string
	-- v41: o mesmo nome curto do cartão e das vagas (Weapons.shortName)
	local f = player:GetAttribute("Faction")
	local n = Weapons.shortName(id, if type(f) == "string" then f else nil)
	return if n ~= "" then n else "—"
end

-- Põe a arma da vaga i na mão: a atual desce (holsterS), troca lá embaixo e a nova sobe (drawS).
-- fromHand: vinha da granada (que já saiu da vista); a arma só sobe. A última troca pedida vale.
local function switchTo(i: number, fromHand: boolean)
	if i < 1 or i > #slots or seated() then
		return
	end
	if not fromHand and i == slot and not inv.hand and not binoculars then
		Bus.fire("vagas_mostrar") -- já está na mão: só mostra a faixa
		return
	end
	if binoculars then
		toggleBinoculars()
	end
	for _, t in triggers do
		Gatilho.cancel(t)
	end
	setAim(false)
	if inv.hand then
		setHand(nil)
		fromHand = true
	end
	local curId = if launcher then "launcher" elseif weapon then weapon.id else nil
	local hold = if fromHand then 0 else Equipar.holsterS(curId, weapon and weapon.kind)
	local newId = slots[i]
	local nwp = Weapons.get(newId)
	local draw = Equipar.drawS(newId, if newId == "launcher" then "launcher" elseif nwp then nwp.kind else nil)
	inv.token += 1
	local my = inv.token
	inv.busyUntil = os.clock() + hold + draw
	KnifeView.troca(hold, draw)
	Bus.fire("vagas_mostrar")
	task.delay(hold, function()
		if inv.token ~= my then
			return
		end
		slot = i
		equip()
		say(nameOf(slots[i]))
	end)
end

local function counts(): Equipar.Counts
	local f, s = player:GetAttribute("Frags"), player:GetAttribute("Smokes")
	return { frags = if type(f) == "number" then f else 0, smokes = if type(s) == "number" then s else 0 }
end

-- Granada ou fumaça na mão (vagas 3 e 4, roda de equipamento, último item): a arma desce e a
-- granada vem do cinto; o gatilho arma e lança (Equipar.press/release, RenderStepped).
local function drawGrenade(kind: string)
	if seated() or player:GetAttribute("Downed") or bodyBusy() then
		return
	end
	if inv.hand and inv.hand.kind == kind then
		return
	end
	if not Equipar.itemOk(kind, myRole(), counts(), false) then
		say(if kind == "smoke" then "Sem fumaça" else "Sem granadas")
		return
	end
	if binoculars then
		toggleBinoculars()
	end
	for _, t in triggers do
		Gatilho.cancel(t)
	end
	setAim(false)
	local curId = if launcher then "launcher" elseif weapon then weapon.id else nil
	local hold = if inv.hand then 0 else Equipar.holsterS(curId, weapon and weapon.kind)
	if inv.hand then
		setHand(nil)
	end
	inv.prev = slot
	inv.token += 1
	local my = inv.token
	KnifeView.troca(hold, math.huge) -- a arma desce e fica embaixo até voltar (switchTo)
	inv.busyUntil = os.clock() + hold
	Bus.fire("vagas_mostrar")
	task.delay(hold, function()
		if inv.token ~= my or seated() then
			return
		end
		setHand(Equipar.newHand(kind, os.clock()))
		tellServer(kind)
	end)
end

-- Usa a vaga n (teclas 1 a 0, toque na faixa das vagas)
local function useSlot(n: number)
	local def = Equipar.SLOTS[n]
	if not def then
		return
	end
	if def.kind == "weapon" then
		switchTo(n, false)
	elseif def.kind == "grenade" then
		drawGrenade(def.id)
	else
		-- itens: o mesmo caminho da roda de equipamento (InfantryController.useItem)
		local canBuild = false
		for _, b in Logistics.BUILDS do
			if b.role[myRole() or ""] then
				canBuild = true
			end
		end
		if not Equipar.itemOk(def.id, myRole(), counts(), canBuild) then
			say(string.format("%s: indisponível", def.label))
			return
		end
		Bus.fire("use_item", def.id)
	end
end

-- Y, botão ARMA do toque, roda do mouse: a próxima arma; com a granada na mão, volta para a arma
local function cycle(dir: number)
	if inv.hand then
		switchTo(slot, true)
	elseif #slots > 1 then
		switchTo(Equipar.cycle(#slots, slot, dir), false)
	end
end
Input.on("swap_weapon", "tap", function()
	cycle(1)
end)
Input.on("swap_weapon", "press", function()
	cycle(1)
end)
Input.on("weapon_next", "press", function()
	cycle(1)
end)
Input.on("weapon_prev", "press", function()
	cycle(-1)
end)
for n = 1, #Equipar.SLOTS do
	Input.on(Equipar.actionOf(n), "press", function()
		useSlot(n)
	end)
end
-- roda de equipamento e último item (InfantryController): granada e fumaça vêm para a mão
Bus.on("draw_item", function(kind: string)
	if kind == "frag" or kind == "smoke" then
		drawGrenade(kind)
	end
end)
-- faixa das vagas (BarraItens): tocar numa vaga
Bus.on("vaga_usar", function(n: number)
	if InputMap.allowed(Input.state, "swap_weapon") then
		useSlot(n)
	end
end)

-- ===== gatilho e mira =====
local function triggerDown()
	-- D-108: prévia da caixa de munição do suporte (Controllers/CaixaMunicao.client): o gatilho põe
	if player:GetAttribute("PondoCaixa") == true and not seated() then
		Bus.fire("caixa_por")
		return
	end
	if binoculars and not seated() then
		toggleBinoculars() -- o gatilho guarda o binóculo e a arma volta (antes ficava sem arma)
		return
	end
	local h = inv.hand
	if h and not seated() then
		Equipar.press(h, os.clock())
		return
	end
	if launcher and not seated() then
		launchRocket()
		return
	end
	if not seated() and KnifeView.busy() then -- faca na mão (D-94): o gatilho a devolve à bainha
		KnifeView.sheatheNow()
		return
	end
	local wp, t = active()
	if not (wp and t) then
		return
	end
	-- carregador vazio: o gatilho recarrega (Front 44; todas as plataformas). A arma sem trava do
	-- ferrolho (Tipo 56, Parte 10.6) ainda dá o clique.
	if t.mag <= 0 and (spareBy[wp.id] or 0) > 0 and os.clock() >= t.reloadUntil and not seated() then
		if not wp.boltHoldOpen then
			playId(S.dry_click, 0.8)
		end
		startReload()
		return
	end
	Gatilho.press(t, os.clock())
end
local function triggerUp()
	local h = inv.hand
	if h then
		Equipar.release(h, inv.under)
		return
	end
	local _, t = active()
	if t then
		Gatilho.release(t, os.clock())
	end
end
Input.on("fire", "press", triggerDown)
Input.on("fire", "release", triggerUp)
-- v43 (pedido do dono: "coloque o botão RB para lançar a granada"): granada rápida. Apertar puxa a
-- granada do cinto; segurando quando ela chega na mão, arma; soltar lança (como o gatilho). Solto
-- antes de chegar, ela fica na mão: o próximo RB (ou o gatilho) arma e lança.
local quickHeld = false
Input.on("quick_grenade", "press", function()
	quickHeld = true
	local h = inv.hand
	if h and h.kind == "frag" then
		triggerDown()
		return
	end
	drawGrenade("frag")
	task.spawn(function()
		local t0 = os.clock()
		while quickHeld and os.clock() - t0 < 2 do
			local hh = inv.hand
			if hh and hh.kind == "frag" then
				triggerDown()
				return
			end
			task.wait()
		end
	end)
end)
Input.on("quick_grenade", "release", function()
	quickHeld = false
	local h = inv.hand
	if h and h.kind == "frag" then
		triggerUp()
	end
end)
-- mirar: com a granada na mão, mirar ao soltar lança por baixo (curta)
Input.on("aim", "press", function()
	if inv.hand then
		inv.under = if Input.settings.aimToggle then not inv.under else true
		return
	end
	if Input.settings.aimToggle then
		setAim(not aiming)
	else
		setAim(true)
	end
end)
Input.on("aim", "release", function()
	if inv.hand then
		if not Input.settings.aimToggle then
			inv.under = false
		end
		return
	end
	if not Input.settings.aimToggle then
		setAim(false)
	end
end)
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
Input.on("binoculars", "press", toggleBinoculars) -- tecla B
-- (v43: no controle o binóculo fica na roda de equipamento; o ↑ é a câmera)
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
	if not char or seated() or binoculars or inv.hand or player:GetAttribute("Downed") or bodyBusy() then
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
	-- 2026-11-13: workspace:SetAttribute("VT65DevGranada", "frag" | "smoke" | "frag:baixo" |
	-- "smoke:baixo") puxa a granada, arma (0,5 s apertado) e lança (por baixo com ":baixo");
	-- "vaga:N" usa a vaga N como a tecla; "estado" escreve vagas, mão e munição no Output
	workspace:GetAttributeChangedSignal("VT65DevGranada"):Connect(function()
		local v = workspace:GetAttribute("VT65DevGranada")
		if type(v) ~= "string" then
			return
		end
		local kind, low = string.match(v, "^(%a+):?(%a*)$")
		if kind == "vaga" then
			useSlot(tonumber(low) or tonumber(string.match(v, "%d+") or "") or 1)
		elseif kind == "estado" then
			local _, t = active()
			print(
				string.format(
					"[VT65 ITENS] vagas %s, vaga %d, mão %s, carregador %s, reserva %s, auto %s",
					table.concat(slots, ","),
					slot,
					if inv.hand then inv.hand.kind .. "/" .. inv.hand.phase else "arma",
					tostring(t and t.mag),
					tostring(weapon and spareBy[weapon.id]),
					tostring(player:GetAttribute("AutoRecarga"))
				)
			)
		elseif kind == "frag" or kind == "smoke" then
			drawGrenade(kind)
			task.delay(Equipar.holsterS(nil, "rifle") + Equipar.GRENADE.drawS + 0.1, function()
				local h = inv.hand
				if h then
					Equipar.press(h, os.clock())
					task.wait(0.5)
					Equipar.release(h, low == "baixo")
				end
			end)
		end
		task.defer(function()
			workspace:SetAttribute("VT65DevGranada", nil)
		end)
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
	-- menu, mapa, roda, morte: a granada que ainda não saiu volta ao cinto (Front 44)
	local h = inv.hand
	if ctx ~= "infantry" and ctx ~= "aim" and h and h.phase ~= "lancando" then
		switchTo(slot, true)
	end
end)

-- roda de equipamento: binóculo
Bus.on("equip_item", function(id: string)
	if id == "binoculars" then
		toggleBinoculars()
	end
end)

-- Granada na mão neste quadro: o pino, o pedido ao servidor e a volta para a arma.
local function stepHand(now: number)
	local h = inv.hand
	if not h then
		return
	end
	if seated() or not player.Character then
		setHand(nil)
		return
	end
	local ev = Equipar.handStep(h, now)
	if ev == "pin" then
		playId(S.dry_click, 0.35) -- a argola saindo
	elseif ev == "throw" then
		local _, dir = ViewMode.aimDirection() -- 3ª pessoa: para o ponto da retícula
		Net.event("Throw_Request"):FireServer({ kind = h.kind, dir = dir, power = Equipar.throwPower(h.under) })
		Haptics.fire(0.6, false)
	elseif ev == "done" then
		switchTo(inv.prev, true)
	end
end

-- Recarga automática quando o carregador esvazia: no toque e no controle (opção autoReload, ligada
-- por padrão). No teclado vale a do gatilho vazio (Front 44). O estado vai para atributos locais.
local function autoReloadOn(): boolean
	return Input.settings.autoReload == true and (Input.isGamepad() or Input.touchActive())
end

local function setLocal(name: string, v: any)
	if player:GetAttribute(name) ~= v then
		player:SetAttribute(name, v)
	end
end

local function stepAmmo(wp: Weapons.Weapon?, t: Gatilho.Trigger?, now: number)
	local auto = autoReloadOn()
	setLocal("AutoRecarga", auto)
	setLocal("Carregador", if t then t.mag else nil)
	setLocal("Reserva", if wp then spareBy[wp.id] else nil)
	setLocal("Recarregando", t ~= nil and now < t.reloadUntil)
	if not (wp and t) or t.mag > 0 or now < t.reloadUntil or (spareBy[wp.id] or 0) <= 0 then
		inv.autoAt = 0
		return
	end
	if auto and not t.held and not KnifeView.busy() and not seated() then
		-- espera o dedo sair do gatilho e um instante (o último tiro ainda soa)
		if inv.autoAt == 0 then
			inv.autoAt = now + 0.25
		elseif now >= inv.autoAt then
			startReload()
		end
	end
end

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
	stepHand(now)
	stepAmmo(wp, t, now)
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
	-- v41 (pedido do dono: "coloque uma mira quando vc n esta mirando no hipfire"): a retícula do
	-- quadril (desenhada pelo ThirdPerson.client, em 1ª e 3ª pessoa) com arma de fogo pronta, sem
	-- mirar e sem correr (correndo a arma vai para o lado)
	local char = player.Character
	local hip = wp ~= nil
		and not aiming
		and not binoculars
		and not seated()
		and not (char and char:GetAttribute("Sprinting") == true)
		and canShoot()
	if player:GetAttribute("HipReticle") ~= hip then
		player:SetAttribute("HipReticle", hip) -- local
	end
	if not seated() then
		-- mira: levar ao ombro leva tempo proporcional ao peso (Parte 10.4); binóculo 7x ≈ 10°
		-- FOV base ajustável (acessibilidade); a mira fecha um pouco (Weapons.ADS_FOV_K)
		local base = Input.settings.fov
		if scoped and sc then
			camera.FieldOfView = sc.fov -- a troca fica atrás do piscar da luneta
		else
			local target = if binoculars then 10 elseif aiming then base * Weapons.ADS_FOV_K else base
			-- D-107 ("mais fast paced"): ao ombro mais rápido (era 10 / massa: M14 ~0,5 s, M60 ~1 s)
			local speed = if wp then math.max(16 / math.max(wp.massLoadedKg, 1), 3) else 4
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
		-- Parte 13: no toque a VOLTA é até 25% mais rápida (Input.recoilReturnK); o chute é o mesmo
		local back = recoilReturn * math.min(1, dt * 10 * Input.recoilReturnK())
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
	inv.token += 1 -- troca pendente da vida anterior não vale
	inv.busyUntil, inv.sent, inv.autoAt = 0, nil, 0
	setHand(nil)
	KnifeView.troca(0, 0)
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
