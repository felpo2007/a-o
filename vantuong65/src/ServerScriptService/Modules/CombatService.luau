--!strict
-- Validação de tiros no servidor (Parte 7): o cliente manda origem, direção, instante, semente e
-- modo; o servidor confere tudo (Shared/Gatilho.validate: arma, modo do papel, munição, recarga,
-- cadência, origem e o lugar do veículo), refaz a MESMA simulação determinística (Ballistics) com
-- raycasts próprios e aplica o dano. Sem hitmarker.
-- 2026-11-12 (pedido do dono: "algumas armas não estão atirando"):
--   - munição por ARMA do equipamento (antes só a 1ª: o granadeiro tinha a M79 desligada na 1ª vaga
--     e a M1911 na 2ª, e o servidor recusava todo tiro da pistola);
--   - cadência no relógio do tiro, não na chegada (o tremor da rede derrubava tiros da rajada);
--   - M79 atira: granada M406 simulada, arma entre 14 e 27 m e explode (ExplosionService);
--   - tiro de dentro do veículo no lugar aberto (D-100): o casco do próprio veículo não para a bala;
--   - Studio: o motivo de cada tiro recusado vai no atributo "VT65TiroRecusado" do jogador.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local Gatilho = require(ReplicatedStorage.Shared.Gatilho)
local Net = require(ReplicatedStorage.Shared.Net)
local Pickup = require(ReplicatedStorage.Shared.Pickup)
local Rng = require(ReplicatedStorage.Shared.Rng)
local Vantagens = require(ReplicatedStorage.Shared.Vantagens)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AssetLoader = require(script.Parent.AssetLoader)
local Combatants = require(script.Parent.Combatants)
local ExplosionService = require(script.Parent.ExplosionService)
local MedicalService = require(script.Parent.MedicalService)
local AnimalService = require(script.Parent.AnimalService)
local TrainingService = require(script.Parent.TrainingService)

local CombatService = {}
local M = 0.28
local LOS_CHECK_STUDS = 1.0 / M -- origem mais longe que isto da cabeça precisa de linha livre
local MAGS = Weapons.MAGS -- PLACEHOLDER de dotação
-- materiais que a bala atravessa perdendo velocidade (fração mantida). PLACEHOLDER até a
-- tabela de penetração em cm por material (Parte 10.7).
local PASS = { Bamboo = 0.85, Thatch = 0.8, Canvas = 0.9 } -- Canvas: lona das barracas (bases, 2026-11-13)

-- munição de uma arma (a do servidor manda); gate = cadência (Gatilho)
type Rec = Gatilho.Rec
local ammo: { [Player]: Rec } = {} -- arma principal (a 1ª do equipamento ou a pega do chão)
local extra: { [Player]: { [string]: Rec } } = {} -- as outras do equipamento (pistola do granadeiro)

local function newRec(wp: Weapons.Weapon, mags: number): Rec
	return {
		weapon = wp.id,
		mag = wp.magazine,
		spare = math.max(mags - 1, 0),
		reloadUntil = 0,
		gate = Gatilho.newGate(),
	}
end

local function loadout(player: Player): { string }
	local s = player:GetAttribute("Loadout")
	return if type(s) == "string" then string.split(s, ",") else {}
end

-- registro da arma `w` do jogador (sem `w`: a principal)
local function recFor(player: Player, w: any): Rec?
	local a = ammo[player]
	if type(w) ~= "string" then
		return a
	end
	if a and a.weapon == w then
		return a
	end
	local x = extra[player]
	return x and x[w]
end

local function sendAmmo(player: Player, rec: Rec)
	Net.event("Combat_Ammo")
		:FireClient(player, { w = rec.weapon, weapon = rec.weapon, mag = rec.mag, spare = rec.spare })
end

local function resetAmmo(player: Player)
	ammo[player] = nil
	local others: { [string]: Rec } = {}
	extra[player] = others
	for i, id in loadout(player) do
		local wp = Weapons.get(id)
		if wp and wp.enabled then
			if i == 1 then
				-- equipamento por peso (Kit_Set): carregadores escolhidos; senão a dotação padrão;
				-- + equipamento liberado (D-72, ProgressionService.applyGear): bandoleira/peitoral;
				-- + vantagem "Bolsos Extras" (Vant_mags, gravada pelo servidor com a posse do passe)
				local km, gm = player:GetAttribute("KitMags"), player:GetAttribute("GearMags")
				local mags = Weapons.magsFor(
					wp,
					if type(km) == "number" then km else nil,
					if type(gm) == "number" then gm else nil,
					Vantagens.extra(player, "mags")
				)
				ammo[player] = newRec(wp, mags)
			elseif not others[id] then
				others[id] = newRec(wp, MAGS[wp.kind] or 3)
			end
		end
	end
	player:SetAttribute("CarriedWeapon", nil)
	-- as outras primeiro: o cartão da arma (HudCampo) fica com a principal, que é a equipada ao nascer
	for _, rec in others do
		sendAmmo(player, rec)
	end
	local a = ammo[player]
	if a then
		sendAmmo(player, a)
	end
end

-- ===== arma caída (Parte 11): pegar a arma do inimigo só com a munição dela =====
local pickups = Instance.new("Folder")
pickups.Name = "DroppedWeapons"
pickups.Parent = workspace

local spawnPickup: (pos: Vector3, a: Pickup.Ammo) -> ()
spawnPickup = function(pos: Vector3, a: Pickup.Ammo)
	local wp = Weapons.get(a.weapon)
	if not wp then
		return
	end
	-- a própria arma (publicada ou provisória) deitada de lado no chão (antes: uma tábua)
	local gun = AssetLoader.weaponModel(a.weapon, wp.kind)
	gun.Name = a.weapon
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local p = gun.PrimaryPart :: BasePart
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(pos + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), params)
	-- deitada de lado (Z = 90°): o lado −X da arma fica para baixo; ergue até ele tocar o chão
	local lowX = gun:GetAttribute("LowX")
	local lift = (if type(lowX) == "number" then -lowX else 0.025 / M) + 0.005 / M
	gun:PivotTo(
		CFrame.new((if hit then hit.Position else pos) + Vector3.new(0, lift, 0))
			* CFrame.Angles(0, math.random() * 2 * math.pi, 0)
			* CFrame.Angles(0, 0, math.pi / 2)
	)
	gun.Parent = pickups
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = string.format("Pegar %s", wp.name)
	prompt.ObjectText = string.format("%d cartucho(s) no carregador", a.mag)
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = p
	prompt.Triggered:Connect(function(player: Player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (char and hum) or hum.Health <= 0 or char:GetAttribute("Downed") or gun.Parent ~= pickups then
			return
		end
		gun:Destroy()
		local cur = ammo[player]
		local new, dropped =
			Pickup.swap(if cur then { weapon = cur.weapon, mag = cur.mag, spare = cur.spare } else nil, a)
		ammo[player] = {
			weapon = new.weapon,
			mag = new.mag,
			spare = new.spare,
			reloadUntil = 0,
			gate = Gatilho.newGate(),
		}
		player:SetAttribute("CarriedWeapon", new.weapon)
		AssetLoader.attachWeapon(char, new.weapon) -- a arma na mão troca junto
		sendAmmo(player, ammo[player])
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if dropped and root then
			spawnPickup(root.Position + root.CFrame.RightVector * 2, dropped)
		end
	end)
	task.delay(Pickup.TTL_S, function()
		gun:Destroy()
	end)
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

local function num(v: any): number?
	return if type(v) == "number" and v == v and math.abs(v) < 1e7 then v else nil
end

-- Granada de 40 mm (M79, M406): voa pela balística com a semente, arma a uma distância sorteada
-- entre wp.armM (14 a 27 m, FAS) e explode no impacto; antes disso ela só acerta como um projétil
-- pesado e lento (sem explodir).
local function launchGrenade(
	shooter: Model,
	wp: Weapons.Weapon,
	origin: Vector3,
	dir: Vector3,
	seed: number,
	params: RaycastParams
)
	local armR = wp.armM
	local arm = if armR then Rng.new(seed + 11):range(armR[1], armR[2]) else 0
	local target: Instance? = nil
	local hit, tFlight = Ballistics.trace({
		ox = origin.X * M,
		oy = origin.Y * M,
		oz = origin.Z * M,
		dx = dir.X,
		dy = dir.Y,
		dz = dir.Z,
		weaponId = wp.id,
		seed = seed,
		maxTime = wp.maxFlightS or 12,
		dt = 1 / 60,
	}, function(ax, ay, az, bx, by, bz)
		local from = Vector3.new(ax, ay, az) / M
		local r = workspace:Raycast(from, Vector3.new(bx - ax, by - ay, bz - az) / M, params)
		if not r then
			return nil
		end
		target = r.Instance
		local p = r.Position * M
		return { x = p.X, y = p.Y, z = p.Z, target = r.Instance }
	end)
	if not hit then
		return
	end
	local pos = Vector3.new(hit.x, hit.y, hit.z) / M
	local flownM = (pos - origin).Magnitude * M
	local by = Players:GetPlayerFromCharacter(shooter)
	task.delay(tFlight, function()
		if flownM >= arm then
			-- um palmo antes do ponto de impacto, para o efeito não nascer dentro do chão
			ExplosionService.detonate(wp.explosive or "grenade_us", pos - dir.Unit * (0.1 / M), by)
			return
		end
		local t = target
		local victim = t and Combatants.get(t:FindFirstAncestorOfClass("Model"))
		if t and victim then
			MedicalService.hit(victim.model, zoneOf(t), hit.energy, Rng.new(seed + 1):next(), by)
		end
	end)
end

-- Simula o tiro no servidor e aplica o dano. `shooter` é o modelo do personagem (jogador ou bot).
function CombatService.fire(
	shooter: Model,
	weaponId: string,
	origin: Vector3,
	dir: Vector3,
	seed: number,
	exceptPlayer: Player?
)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { shooter }
	-- sentado num veículo (lugar aberto, M60 do assento): o casco do próprio veículo não para a bala
	local hum = shooter:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local vehicle = seat and seat:FindFirstAncestorWhichIsA("Model")
	if vehicle and vehicle:GetAttribute("VehicleId") ~= nil then
		table.insert(ignore, vehicle)
	end
	params.FilterDescendantsInstances = ignore
	local wp = Weapons.get(weaponId)
	local speedFactor = 1
	local hit = nil
	if not (wp and wp.kind == "launcher") then
		hit = Ballistics.trace({
			ox = origin.X * M,
			oy = origin.Y * M,
			oz = origin.Z * M,
			dx = dir.X,
			dy = dir.Y,
			dz = dir.Z,
			weaponId = weaponId,
			seed = seed,
			maxTime = if wp then wp.maxFlightS else nil,
		}, function(ax, ay, az, bx, by, bz)
			local from = Vector3.new(ax, ay, az) / M
			local delta = Vector3.new(bx - ax, by - ay, bz - az) / M
			for _ = 1, 4 do -- até 4 materiais atravessáveis por segmento
				local r = workspace:Raycast(from, delta, params)
				if not r then
					return nil
				end
				local mat = r.Instance:GetAttribute("Material")
				local keep = if type(mat) == "string" then PASS[mat] else nil
				if keep then
					speedFactor *= keep
					table.insert(ignore, r.Instance)
					params.FilterDescendantsInstances = ignore
				else
					local p = r.Position * M
					return { x = p.X, y = p.Y, z = p.Z, target = r.Instance }
				end
			end
			return nil
		end)
	end
	AnimalService.noise(origin, false) -- búfalos e galinhas fogem do tiro (pista de detecção)
	-- traçante, som e impacto para os outros clientes (eles refazem a trajetória com a semente)
	local payload = {
		w = weaponId,
		ox = origin.X,
		oy = origin.Y,
		oz = origin.Z,
		dx = dir.X,
		dy = dir.Y,
		dz = dir.Z,
		seed = seed,
		by = shooter, -- o clarão de boca sai da arma de quem atirou (WeaponVisuals)
	}
	for _, other in Players:GetPlayers() do
		if other ~= exceptPlayer then
			Net.unreliable("Combat_Tracer"):FireClient(other, payload)
		end
	end
	if wp and wp.kind == "launcher" then
		launchGrenade(shooter, wp, origin, dir, seed, params)
		return
	end
	if hit and hit.target then
		local t = hit.target :: Instance
		if t:IsA("BasePart") and t:GetAttribute("RangeTarget") ~= nil then
			TrainingService.rangeHit(shooter, t, Vector3.new(hit.x, hit.y, hit.z) / M)
			return
		end
		TrainingService.nearMiss(shooter, Vector3.new(hit.x, hit.y, hit.z) / M, t)
		local model = (hit.target :: Instance):FindFirstAncestorOfClass("Model")
		local victim = Combatants.get(model)
		if victim then
			local energy = hit.energy * speedFactor * speedFactor
			local roll = Rng.new(seed + 1):next()
			-- quem atirou (se for jogador) vai para o registro de abate/assistência (D-72)
			local by = Players:GetPlayerFromCharacter(shooter)
			MedicalService.hit(victim.model, zoneOf(hit.target), energy, roll, by)
			if victim.player then -- vibração do lado do impacto (Parte 12.6)
				Net.event("Combat_Hit"):FireClient(victim.player, { x = origin.X, y = origin.Y, z = origin.Z })
			end
		end
	end
end

-- Arma caída de quem morreu (jogador ou bot): só com o carregador (Pickup.dropOnDeath).
function CombatService.dropWeapon(pos: Vector3, weapon: string, mag: number)
	local drop = Pickup.dropOnDeath({ weapon = weapon, mag = mag, spare = 0 })
	if drop then
		spawnPickup(pos, drop)
	end
end

-- reabastece a munição (caixa de munição construída pela logística). Arma do outro lado não
-- reabastece: quem pegou a arma do inimigo fica com o que tem nela.
function CombatService.refill(player: Player)
	local a = ammo[player]
	local wp = a and Weapons.get(a.weapon)
	if wp and not Pickup.canRefill(wp.faction, player:GetAttribute("Faction") :: string?) then
		return
	end
	resetAmmo(player)
end

-- Lugar do veículo de quem atira (nil = a pé), para o Gatilho.validate
local function seatInfo(hum: Humanoid, dir: Vector3): Gatilho.SeatInfo?
	local seat = hum.SeatPart
	if not seat then
		return nil
	end
	local vehicle = seat:FindFirstAncestorWhichIsA("Model")
	local chassis = vehicle and vehicle:FindFirstChild("Chassis")
	local fwd = if chassis and chassis:IsA("BasePart") then chassis.CFrame.LookVector else seat.CFrame.LookVector
	local fl, ff = Vector3.new(dir.X, 0, dir.Z), Vector3.new(fwd.X, 0, fwd.Z)
	local rel = 0
	if fl.Magnitude > 1e-3 and ff.Magnitude > 1e-3 then
		rel = math.deg(math.atan2(-fl.X, -fl.Z) - math.atan2(-ff.X, -ff.Z))
	end
	local yaw = num(seat:GetAttribute("ArcYaw"))
	local w = seat:GetAttribute("Weapon")
	return {
		personal = seat:GetAttribute("Personal") == true,
		weapon = if type(w) == "string" then w else nil,
		arc = if yaw
			then {
				yaw = yaw,
				half = num(seat:GetAttribute("ArcHalf")) or 0,
				down = num(seat:GetAttribute("ArcDown")) or 0,
				up = num(seat:GetAttribute("ArcUp")) or 0,
			}
			else nil,
		relYawDeg = rel,
		pitchDeg = math.deg(math.asin(math.clamp(dir.Unit.Y, -1, 1))),
		-- o veículo girando: a folga do ângulo cresce com o giro dentro da janela de defasagem
		turnDegS = if chassis and chassis:IsA("BasePart")
			then math.deg(chassis.AssemblyAngularVelocity.Magnitude)
			else nil,
	}
end

-- Studio: motivo do tiro recusado (atributo do jogador) e aviso no Output, um por motivo a cada 2 s
local refusedAt: { [string]: number } = {}
local function refused(player: Player, weaponId: string, why: string)
	if not RunService:IsStudio() then
		return
	end
	player:SetAttribute("VT65TiroRecusado", string.format("%s: %s", weaponId, why))
	local k = player.Name .. why
	if os.clock() - (refusedAt[k] or -10) > 2 then
		refusedAt[k] = os.clock()
		warn(string.format("[VT65 ARMAS] tiro recusado (%s, %s): %s", player.Name, weaponId, why))
	end
end

-- Studio: workspace:SetAttribute("VT65DevArma", "m70") dá a arma (com munição cheia) a todos os
-- jogadores em campo, como se tivessem pegado do chão; "m14:automatic_rifleman" também troca o papel
-- (o seletor da M14 abre para o automático).
local function devGive(spec: string)
	local id, role = string.match(spec, "^([%w_]+):?([%w_]*)$")
	local wp = id and Weapons.get(id)
	if not (wp and wp.enabled) then
		warn("[VT65 ARMAS] arma desconhecida ou desligada: " .. spec)
		return
	end
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char then
			if role and role ~= "" then
				p:SetAttribute("Role", role)
			end
			ammo[p] = newRec(wp, MAGS[wp.kind] or 3)
			p:SetAttribute("CarriedWeapon", wp.id)
			AssetLoader.attachWeapon(char, wp.id)
			sendAmmo(p, ammo[p])
			print(string.format("[VT65 ARMAS] %s com %s (papel %s)", p.Name, wp.id, tostring(p:GetAttribute("Role"))))
		end
	end
end

function CombatService.start()
	local function watch(p: Player)
		local function onChar(char: Model)
			resetAmmo(p)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Once(function()
					local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
					local a = ammo[p]
					local drop =
						Pickup.dropOnDeath(if a then { weapon = a.weapon, mag = a.mag, spare = a.spare } else nil)
					if drop and root and not char:GetAttribute("Evacuated") then -- evacuado leva a arma
						spawnPickup(root.Position, drop)
					end
				end)
			end
		end
		p.CharacterAdded:Connect(onChar)
		if p.Character then -- entrou antes do start (Studio): sem isto ficava sem munição nenhuma
			task.spawn(onChar, p.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		ammo[p] = nil
		extra[p] = nil
	end)

	-- recarga: { w = arma } (sem w: a principal)
	Net.event("Combat_Reload").OnServerEvent:Connect(function(player, req)
		local rec = recFor(player, if type(req) == "table" then req.w else nil)
		local wp = rec and Weapons.get(rec.weapon)
		if not (rec and wp) or rec.spare <= 0 or os.clock() < rec.reloadUntil or rec.mag >= wp.magazine then
			return
		end
		-- vantagem "Mãos Rápidas" (Vant_reload, 0,88): o gatilho só volta depois desta recarga
		local dur = Weapons.reloadTime(wp, Vantagens.mult(player, "reload"))
		rec.reloadUntil = os.clock() + dur
		task.delay(dur, function()
			if recFor(player, rec.weapon) == rec then
				rec.spare -= 1
				rec.mag = wp.magazine
				sendAmmo(player, rec)
			end
		end)
	end)

	-- o cliente trocou de arma: reenvia a munição dela (cartão da arma no HUD)
	local asked: { [Player]: number } = {}
	Net.event("Combat_Ammo").OnServerEvent:Connect(function(player, req)
		if os.clock() - (asked[player] or -1) < 0.2 then
			return
		end
		asked[player] = os.clock()
		local rec = recFor(player, if type(req) == "table" then req.w else nil)
		if rec then
			sendAmmo(player, rec)
		end
	end)

	Net.event("Combat_Fire").OnServerEvent:Connect(function(player, shot)
		if type(shot) ~= "table" then
			return
		end
		local char = player.Character
		local head = char and char:FindFirstChild("Head") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (char and head and hum) or hum.Health <= 0 or char:GetAttribute("Downed") then
			return
		end
		local rec = recFor(player, shot.w)
		local ox, oy, oz = num(shot.ox), num(shot.oy), num(shot.oz)
		local dx, dy, dz = num(shot.dx), num(shot.dy), num(shot.dz)
		local t, seed = num(shot.t), num(shot.seed)
		if not (rec and ox and oy and oz and dx and dy and dz and t and seed) then
			if not rec then
				refused(player, tostring(shot.w), "arma fora do equipamento")
			end
			return
		end
		local wp = Weapons.get(rec.weapon)
		local dir = Vector3.new(dx, dy, dz)
		if not wp or dir.Magnitude < 1e-3 then
			return
		end
		local r = player:GetAttribute("Role")
		local role = if type(r) == "string" then r else nil
		local mode = if type(shot.m) == "string" then shot.m else Weapons.modesFor(wp, role)[1]
		local origin = Vector3.new(ox, oy, oz)
		local ok, why = Gatilho.validate(rec, {
			weapon = rec.weapon,
			mode = mode,
			role = role,
			t = t,
			now = workspace:GetServerTimeNow(),
			clock = os.clock(),
			originStuds = (origin - head.Position).Magnitude,
			seat = seatInfo(hum, dir),
		})
		if not ok then
			refused(player, rec.weapon, why or "?")
			return
		end
		-- 3ª pessoa (2026-11-11): o cliente legítimo atira do olho, nunca da câmera atrás do ombro. Se a
		-- origem estiver a mais de ~1 m da cabeça e houver algo sólido no meio (câmera do outro lado de
		-- uma parede ou de uma crista), o tiro sai da cabeça. Até 1 m (inclinar, deitado, olho da
		-- câmera de 1ª pessoa) nada muda: o terreno irregular de quem está deitado não derruba o tiro.
		-- Sentado (D-100), o veículo não conta como parede.
		if (origin - head.Position).Magnitude > LOS_CHECK_STUDS then
			local los = RaycastParams.new()
			los.FilterType = Enum.RaycastFilterType.Exclude
			local skip: { Instance } = { char }
			local seat = hum.SeatPart
			local vehicle = seat and seat:FindFirstAncestorWhichIsA("Model")
			if vehicle then
				table.insert(skip, vehicle)
			end
			los.FilterDescendantsInstances = skip
			los.RespectCanCollide = true
			if workspace:Raycast(head.Position, origin - head.Position, los) then
				origin = head.Position
			end
		end
		rec.mag -= 1
		CombatService.fire(char, wp.id, origin, dir.Unit, seed, player)
	end)

	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("VT65DevArma"):Connect(function()
			local v = workspace:GetAttribute("VT65DevArma")
			if type(v) == "string" and v ~= "" then
				devGive(v)
			end
		end)
	end
end

return CombatService
