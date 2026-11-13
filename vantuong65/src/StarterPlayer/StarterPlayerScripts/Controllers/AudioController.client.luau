--!strict
-- Áudio da F3 (Parte 5 e 10.7): ambiências por zona com crossfade, passos por material (seus e
-- dos outros, 3D), tiros alheios em camadas por distância com atraso do som (d/349 m/s),
-- estalo supersônico quando a bala passa perto e impacto por material. Sem asset (ID 0) fica mudo.
-- D-107 (pedido do dono: "melhore o áudio das armas"): o tiro PRÓPRIO toca aqui (antes era o
-- WeaponController, um som só): disparo da arma, corpo grave, cauda pelo lugar (eco no aberto,
-- abafado na mata, reverberação na vila e no túnel), estojo e ferrolho. Os tiros dos outros ganham o
-- disparo da própria arma de perto, agudos caindo com a distância, a cauda e o zunido da bala que
-- passa rente. Dados em Shared/SomArmas; quem toca é o Controllers/Som.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Accessibility = require(ReplicatedStorage.Shared.Accessibility)
local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local SomArmas = require(ReplicatedStorage.Shared.SomArmas)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Weather = require(ReplicatedStorage.Shared.Weather)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local Som = require(script.Parent.Som)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = MapConfig.STUD_M
local SND = AssetIds.Sounds

local function sid(key: string): string?
	local id = SND[key]
	return if type(id) == "number" and id ~= 0 then "rbxassetid://" .. id else nil
end

-- ===== mixagem (D-91, depois de jogar: "o barulho é insuportável, os sons estão muito altos e
-- continuam mesmo no menu") =====
-- Todo som do jogo passa por um grupo: efeitos (tiros, passos, explosões, motores), ambiente (água,
-- vila, praia, túnel) e música (só no menu). Efeitos e ambiente baixaram; no lobby e na tela de
-- inserção o ambiente some e entra a música baixa.
local function group(name: string, volume: number): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	return g
end
local sfxGroup = group("VT65Efeitos", 0.5)
local ambGroup = group("VT65Ambiente", 0.6)
local musicGroup = group("VT65Musica", 0.35)
-- volume escolhido no menu do jogo (Configurações → Som), salvo na conta (Input.settings)
local function applyVolumes()
	local s = Input.settings :: any
	sfxGroup.Volume = tonumber(s.volEffects) or 0.5
	ambGroup.Volume = tonumber(s.volAmbient) or 0.6
	musicGroup.Volume = tonumber(s.volMusic) or 0.35
end
Input.SettingsChanged:Connect(applyVolumes)
applyVolumes()
-- sons criados por outros scripts (arma, veículo, explosão) também entram nos efeitos
local function adopt(inst: Instance)
	if inst:IsA("Sound") and inst.SoundGroup == nil then
		inst.SoundGroup = sfxGroup
	end
end
workspace.DescendantAdded:Connect(adopt)
SoundService.DescendantAdded:Connect(adopt)
task.spawn(function()
	for _, d in workspace:GetDescendants() do
		adopt(d)
	end
end)

local function inField(): boolean
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and Input.state.alive
end

local music: Sound? = nil
do
	local id = sid("music_menu")
	if id then
		local s = Instance.new("Sound")
		s.Name = "MusicaMenu"
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = musicGroup
		s.Parent = SoundService
		s:Play()
		music = s
	end
end

-- ===== legendas de som (acessibilidade): aparecem quando o som chegaria, mesmo sem asset =====
local capGui = UiKit.screen("VT65Captions", 15)
local capList = Instance.new("Frame")
capList.AnchorPoint = Vector2.new(0.5, 1)
capList.Position = UDim2.new(0.5, 0, 1, -170)
capList.Size = UDim2.fromOffset(640, 160)
capList.BackgroundTransparency = 1
capList.Parent = capGui
local capLayout = Instance.new("UIListLayout")
capLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
capLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
capLayout.Padding = UDim.new(0, 3)
capLayout.Parent = capList
local lastCap: { [string]: number } = {}
local function caption(key: string, what: string, pos: Vector3?, delay: number?)
	if not Input.settings.captions then
		return
	end
	local now = os.clock()
	if (lastCap[key] or 0) > now - 1.5 then
		return -- uma legenda por tipo de som a cada 1,5 s (rajada não vira parede de texto)
	end
	lastCap[key] = now
	local d = if pos then (pos - camera.CFrame.Position) * M else Vector3.zero
	local text = Accessibility.caption(what, d.X, d.Z)
	task.delay(delay or 0, function()
		-- mesmo contraste de antes (branco sobre preto); a faixa só abraça o texto, com canto leve
		local l = Instance.new("TextLabel")
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.fromOffset(0, if UiKit.tv() then 34 else 26)
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.BackgroundTransparency = 0.35
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Font = Enum.Font.GothamMedium
		l.TextSize = UiKit.text(18)
		l.Text = text
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = l
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 4)
		round.Parent = l
		l.Parent = capList
		task.delay(4, function()
			l:Destroy()
		end)
	end)
end

-- som 3D num ponto do mundo (ou 2D se pos == nil)
local function play(key: string, pos: Vector3?, volume: number, maxDist: number?, delay: number?)
	local id = sid(key)
	if not id then
		return
	end
	local function go()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume
		s.SoundGroup = sfxGroup
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = maxDist or 400
		local holder: Instance = SoundService
		local att: Attachment? = nil
		if pos then
			local a = Instance.new("Attachment")
			a.WorldPosition = pos
			a.Parent = workspace.Terrain
			att = a
			holder = a
		end
		s.Parent = holder
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
			if att then
				att:Destroy()
			end
		end)
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

-- ===== ambiências =====
local AMB: { [string]: string } = {
	paddy = "ambience_paddy_morning",
	village = "ambience_village",
	beach = "ambience_beach",
	tunnel = "ambience_tunnel",
}
local loops: { [string]: Sound } = {}
for zone, key in AMB do
	local id = sid(key)
	if id then
		local s = Instance.new("Sound")
		s.Name = "Amb_" .. zone
		s.SoundId = id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = ambGroup
		s.Parent = SoundService
		s:Play()
		loops[zone] = s
	end
end

local villages: { Vector3 } = {}
local beachX = math.huge
for _, l in MapConfig.Locations do
	if
		string.find(l.name, "An Cường")
		or string.find(l.name, "Nam Yên")
		or string.find(l.name, "An Thới")
		or string.find(l.name, "An Phước")
		or string.find(l.name, "Lạc Sơn")
	then
		table.insert(villages, Vector3.new(l.x, 0, l.z))
	end
	-- no mapa de 2 x 2 km (D-63) a praia ficou fora: sem o local, o som de praia não toca
	if string.find(l.name, "Green Beach") then
		beachX = l.x - 120 / M
	end
end

local function underground(pos: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local r = workspace:Raycast(pos, Vector3.new(0, 25, 0), params)
	return r ~= nil and (r.Instance == workspace.Terrain or string.find(r.Instance.Name, "ceiling") ~= nil)
end

local function zoneAt(pos: Vector3): string
	if underground(pos) then
		return "tunnel"
	end
	if pos.X > beachX then
		return "beach"
	end
	for _, v in villages do
		if (Vector3.new(pos.X, 0, pos.Z) - v).Magnitude < 150 / M then
			return "village"
		end
	end
	return "paddy"
end

-- D-107: lugar de quem ouve, para a cauda dos tiros (SomArmas.lugar): 8 raios de 25 m em volta da
-- cabeça (tronco, parede, moita) e um para cima (copa ou telhado)
local lugar = SomArmas.LUGAR
local placeParams = RaycastParams.new()
placeParams.FilterType = Enum.RaycastFilterType.Exclude
local function measurePlace(pos: Vector3, zone: string): string
	local ignore: { Instance } = { camera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		table.insert(ignore, folder)
	end
	placeParams.FilterDescendantsInstances = ignore
	local hits = 0
	for i = 0, 7 do
		local a = i * math.pi / 4
		if workspace:Raycast(pos, Vector3.new(math.cos(a), 0, math.sin(a)) * (25 / M), placeParams) then
			hits += 1
		end
	end
	local roof = workspace:Raycast(pos, Vector3.new(0, 15 / M, 0), placeParams) ~= nil
	return SomArmas.lugar(hits, 8, roof, zone == "village", zone == "tunnel")
end

-- v41 ("jogo está bem pesado ainda"): o laço calado fica pausado (no Studio, com 100 bots, eram ~97
-- canais tocando; as quatro ambiências e a música do menu tocavam o tempo todo com volume 0)
local function quiet(s: Sound, target: number)
	if target <= 0 and s.Volume < 0.002 then
		s.Volume = 0
		if s.IsPlaying then
			s:Pause()
		end
	elseif target > 0 and not s.IsPlaying then
		if s.IsPaused then
			s:Resume()
		else
			s:Play()
		end
	end
end

task.spawn(function()
	while true do
		task.wait(0.5)
		-- fora de campo (lobby, inserção, morto) o ambiente some e a música baixa entra; em campo, o
		-- contrário. A mesa do lobby fica no mundo e contava como "arrozal" (o som de água tocava no menu).
		local field = inField()
		local zone = if field then zoneAt(camera.CFrame.Position) else ""
		if field then
			lugar = measurePlace(camera.CFrame.Position, zone)
		end
		for z, s in loops do
			local target = if z == zone then 0.2 else 0
			s.Volume += (target - s.Volume) * 0.35
			quiet(s, target)
		end
		local m = music
		if m then
			local target = if field then 0 else 0.5
			m.Volume += (target - m.Volume) * 0.25
			quiet(m, target)
		end
	end
end)

-- ===== passos =====
local function stepKey(root: BasePart, model: Model): string
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local r = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	if not r then
		return "step_grass"
	end
	local inst = r.Instance
	if inst ~= workspace.Terrain then
		local mat = inst:GetAttribute("Material")
		if mat == "PaddyWater" then
			return "step_paddy"
		elseif inst.Name == "Dike" then
			return "step_mud"
		elseif inst:FindFirstAncestor("log_bridge") then
			return "step_wood"
		end
		return "step_grass"
	end
	if r.Material == Enum.Material.Water then
		return "step_paddy"
	elseif r.Material == Enum.Material.Sand then
		return "step_sand"
	elseif r.Material == Enum.Material.Mud then
		return "step_mud"
	end
	return "step_grass"
end

local walked: { [Model]: { pos: Vector3, acc: number } } = setmetatable({}, { __mode = "k" }) :: any
local STRIDE = 0.8 / M -- ~0,8 m por passo (o arquivo de passos tem 4 passos: tocamos 1 a cada 4)

local function characters(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local folder = workspace:FindFirstChild("Combatants")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end

-- D-91: só os 4 mais perto fazem passo (com um squad de bots andando no arrozal, a água "ficava
-- repetindo"); volumes mais baixos e o passo na água mais baixo ainda.
local NEAREST_STEPS = 4
type Near = { char: Model, root: BasePart, d: number }
task.spawn(function()
	while true do
		task.wait(0.1)
		local listener = camera.CFrame.Position
		local near: { Near } = {}
		for _, char in characters() do
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - listener).Magnitude
				if d < 60 / M then
					table.insert(near, { char = char, root = root, d = d })
				end
			end
		end
		table.sort(near, function(a: Near, b: Near): boolean
			return a.d < b.d
		end)
		for i, n in near do
			if i > NEAREST_STEPS then
				walked[n.char] = nil -- volta a contar do zero quando entrar entre os mais perto
				continue
			end
			local char, root = n.char, n.root
			do
				local w = walked[char]
				if not w then
					walked[char] = { pos = root.Position, acc = 0 }
				else
					local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(w.pos.X, 0, w.pos.Z)).Magnitude
					w.pos = root.Position
					w.acc += d
					if w.acc >= STRIDE * 4 then
						w.acc = 0
						local rain = ReplicatedStorage:GetAttribute("Rain")
						-- rastejando quase não se ouve; correndo, mais alto (movimento, 2026-11-11)
						local base = if char:GetAttribute("Prone")
							then 0.1
							elseif char:GetAttribute("Crouched") then 0.16
							elseif char:GetAttribute("Sprinting") then 0.5
							else 0.35
						local key = stepKey(root, char)
						if key == "step_paddy" then
							base *= 0.55
						end
						local vol = base * Weather.footstepVolume(if type(rain) == "number" then rain else 0) -- a chuva cobre os passos
						play(key, root.Position, vol, 45 / M)
					end
				end
			end
		end
	end
end)

-- próprio corpo: aterrissagem (queda em m) e transpor/mergulho fazem o barulho do chão (Movement.client)
local function ownStep(volume: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if char and root then
		play(stepKey(root, char), root.Position, volume, 45 / M)
	end
end
Bus.on("landed", function(dropM: number)
	ownStep(math.clamp(0.4 + dropM * 0.3, 0.4, 1.2))
end)
Bus.on("vault_start", function()
	ownStep(0.5)
end)

-- ===== tiro próprio (D-107) =====
-- O WeaponController avisa cada tiro que sai (Bus "shot_fired"): disparo da arma (2D), o corpo (o
-- mesmo disparo uma oitava abaixo, só graves), a cauda pelo lugar e o estojo pulando. Na rajada a
-- cauda e o estojo não se empilham.
local lastTail, lastShell = 0, 0
local function ownShot(weaponId: string?)
	local wp = if type(weaponId) == "string" then Weapons.get(weaponId) else nil
	if not wp then
		return
	end
	local a = SomArmas.arma(wp.id, wp.kind)
	local def = SomArmas.LIB[a.tiro]
	if not def then
		return
	end
	local now = os.clock()
	local tail = now - lastTail > 0.12
	if tail then
		lastTail = now
	end
	local jitter = 1 + (math.random() - 0.5) * 0.04
	Som.play(def, {
		vol = 0.85 * (a.vol or 1),
		pitch = a.pitch * jitter,
		cauda = if tail then SomArmas.CAUDA[lugar] else nil,
	})
	if wp.kind ~= "launcher" then
		Som.play(def, { vol = 0.4 * (a.vol or 1), pitch = a.pitch * 0.55, low = 6, mid = -8, high = -30 })
	end
	if a.estojo and now - lastShell > 0.18 then
		lastShell = now
		Som.play("mec_estojo", { delay = 0.35 + math.random() * 0.15, vol = 0.6, pitch = 0.9 + math.random() * 0.25 })
	end
end
Bus.on("shot_fired", function(shot: any)
	ownShot(if type(shot) == "table" then shot.w else nil)
end)
-- v41 (pedido do dono: "a arma do tanque n sai som"): a metralhadora do assento (coaxial do atirador do
-- M48, M60 da cúpula e da porta) atirada por mim. O servidor manda o traçante e o som só para os OUTROS
-- (CombatService.fire, exceptPlayer) e o VehicleController só fazia o clarão: quem atirava não ouvia.
Bus.on("vehicle_mg_shot", function()
	ownShot("m60")
end)

-- ferrolho manobrado (fuzis de precisão): o som cabe no ciclo da arma. D-108: a bomba da espingarda
-- (SomArmas.mecanica) e o estojo de plástico caindo depois dela
Bus.on("bolt_cycle", function(dur: number, weaponId: string?)
	local key = SomArmas.mecanica(weaponId)
	local def = SomArmas.LIB[key] or SomArmas.LIB.mec_ferrolho
	local d = if type(dur) == "number" and dur > 0 then dur else 1
	local natural = (def.len or 1.3) / (def.pitch or 1)
	Som.play(def, { delay = 0.08, pitch = math.clamp(natural / d, 0.85, 1.25) })
	if key == "mec_bomba" then
		Som.play(
			"mec_cartucho_cai",
			{ delay = 0.5 + math.random() * 0.15, vol = 0.6, pitch = 0.9 + math.random() * 0.2 }
		)
	end
end)

-- ===== tiros dos outros: camadas, atraso do som, estalo e impacto =====
local function layer(key: string): SomArmas.Def?
	local id = SND[key]
	return if type(id) == "number" and id ~= 0 then { id = id, vol = 1 } else nil
end
local MID, FAR = layer("shot_mid"), layer("shot_distant")

-- v41 ("jogo está bem pesado ainda"): o disparo de quem está a mais de 100 m tem teto de 16 por
-- segundo (balde de 8). No Studio, com 100 bots, eram 33 sons de tiro tocando juntos; o tiroteio
-- longe continua soando cheio, e o de perto e a bala passando perto não entram no teto.
local FAR_RATE, FAR_CAP = 16, 8
local farBudget, farAt = FAR_CAP, os.clock()
local function farOk(): boolean
	local now = os.clock()
	farBudget = math.min(FAR_CAP, farBudget + (now - farAt) * FAR_RATE)
	farAt = now
	if farBudget >= 1 then
		farBudget -= 1
		return true
	end
	return false
end

Net.unreliable("Combat_Tracer").OnClientEvent:Connect(function(shot)
	local wp = Weapons.get(shot.w)
	if not wp then
		return
	end
	local origin = Vector3.new(shot.ox, shot.oy, shot.oz)
	local dir = Vector3.new(shot.dx, shot.dy, shot.dz).Unit
	local listener = camera.CFrame.Position
	local dM = (origin - listener).Magnitude * M
	local delay = dM / Ballistics.SOUND
	if dM < 2500 then
		caption(string.format("shot:%s", wp.id), string.format("Tiro de %s", wp.name or wp.id), origin, delay)
	end
	-- D-107: disparo da arma de perto (3D), tiros gravados de médio e longe na direção dele (3D sem
	-- atenuação: o volume é o da camada), agudos caindo com a distância e a cauda do lugar
	local a = SomArmas.arma(wp.id, wp.kind)
	local def = SomArmas.LIB[a.tiro]
	local near, mid, far = SomArmas.camadas(dM)
	local high = SomArmas.agudos(dM, lugar)
	local cauda = SomArmas.CAUDA[lugar]
	local jitter = 1 + (math.random() - 0.5) * 0.04
	local layers = dM <= 100 or farOk()
	if layers and near > 0.01 and def then
		Som.play(def, {
			pos = origin,
			vol = near * (a.vol or 1),
			pitch = a.pitch * jitter,
			delay = delay,
			minDist = 8 / M,
			maxDist = 1500 / M,
			high = high,
			cauda = cauda,
		})
		if dM < 40 and wp.kind ~= "launcher" then
			Som.play(def, {
				pos = origin,
				vol = 0.35 * near * (a.vol or 1),
				pitch = a.pitch * 0.55,
				delay = delay,
				minDist = 8 / M,
				maxDist = 400 / M,
				low = 6,
				mid = -8,
				high = -30,
			})
		end
	end
	if layers and mid > 0.01 and MID then
		Som.play(MID, { pos = origin, vol = mid * 0.8, delay = delay, minDist = 1e5, maxDist = 2e5, high = high * 0.5 })
	end
	if layers and far > 0.01 and FAR then
		Som.play(FAR, { pos = origin, vol = far * 0.7, delay = delay, minDist = 1e5, maxDist = 2e5, cauda = cauda })
	end
	-- ferrolho de quem atira perto (fuzil de precisão)
	if a.ferrolho and dM < 40 then
		Som.play("mec_ferrolho", { pos = origin, delay = delay + 0.3, vol = 0.8, minDist = 3 / M, maxDist = 60 / M })
	end
	-- estalo (supersônica) ou zunido: passagem mais próxima da trajetória (reta) até o ouvinte
	local t = (listener - origin):Dot(dir)
	if t > 0 then
		local closest = (origin + dir * t - listener).Magnitude * M
		local distM = t * M
		local tFlight = distM / math.max(wp.muzzleVelocity * 0.85, 1)
		local what, vol = SomArmas.passagem(closest, wp.muzzleVelocity * 0.85, Ballistics.SOUND)
		if what and distM > 15 then
			if what == "bala_estalo" then
				play("crack", nil, vol, nil, tFlight)
			else
				Som.play(what, { delay = tFlight, vol = vol, pitch = 0.9 + math.random() * 0.2 })
			end
			caption("crack", "Bala passando perto", nil, tFlight)
		end
	end
	-- impacto perto do ouvinte: refaz a trajetória com a mesma semente
	if dM < 150 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
		local hit = Ballistics.trace({
			ox = origin.X * M,
			oy = origin.Y * M,
			oz = origin.Z * M,
			dx = dir.X,
			dy = dir.Y,
			dz = dir.Z,
			weaponId = wp.id,
			seed = shot.seed,
			maxTime = 1,
		}, function(ax, ay, az, bx, by, bz)
			local r = workspace:Raycast(Vector3.new(ax, ay, az) / M, Vector3.new(bx - ax, by - ay, bz - az) / M, params)
			if not r then
				return nil
			end
			local key = "impact_earth"
			local mat = r.Instance:GetAttribute("Material")
			if mat == "PaddyWater" or r.Material == Enum.Material.Water then
				key = "impact_water"
			elseif mat == "Bamboo" then
				key = "impact_wood"
			elseif mat == "Thatch" then
				key = "impact_thatch"
			end
			local p = r.Position * M
			return { x = p.X, y = p.Y, z = p.Z, target = key }
		end)
		if hit then
			local pos = Vector3.new(hit.x, hit.y, hit.z) / M
			local dl = (pos - listener).Magnitude * M
			if dl < 80 then
				play(hit.target :: string, pos, 0.9, 80 / M, hit.t + dl / Ballistics.SOUND)
			end
		end
	end
end)

-- ===== F4: explosões, granada chegando, disparos e motores =====
Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e)
	local pos = Vector3.new(e.x, e.y, e.z)
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	if dM < 3000 then
		play("explosion", pos, math.clamp(1.4 - dM / 2500, 0.3, 1.4), 3000 / M, dM / Ballistics.SOUND)
		caption("explosion", "Explosão", pos, dM / Ballistics.SOUND)
	end
end)
Net.unreliable("Fire_Incoming").OnClientEvent:Connect(function(e)
	local pos = Vector3.new(e.x, e.y, e.z)
	if (pos - camera.CFrame.Position).Magnitude * M < 400 then
		play("incoming", pos, 1, 600 / M)
		caption("incoming", "Assobio de granada chegando", pos)
	end
end)
local LAUNCH: { [string]: string } = {
	mortar = "mortar_launch",
	naval = "naval_distant",
	gun_90 = "gun_90",
	rr_106 = "rr_106",
	rocket = "rr_106",
}
Net.unreliable("Fire_Launch").OnClientEvent:Connect(function(e)
	local pos = Vector3.new(e.x, e.y, e.z)
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	local k = LAUNCH[e.kind]
	if k and dM < 6000 then
		local what = if e.kind == "mortar"
			then "Disparo de morteiro"
			elseif e.kind == "naval" then "Tiro naval ao longe"
			else "Disparo de canhão/foguete"
		caption(string.format("launch:%s", e.kind), what, pos, dM / Ballistics.SOUND) -- chave, não texto
		if e.kind == "naval" then
			play(k, nil, 0.8, nil, dM / Ballistics.SOUND)
		else
			play(k, pos, 1, 2500 / M, dM / Ballistics.SOUND)
		end
	end
end)

-- motor dos veículos: VehicleFx.client (tom e volume pela rotação e pela carga, D-86)

local _ = RunService
