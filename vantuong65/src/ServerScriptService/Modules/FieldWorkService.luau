--!strict
-- Pá de trincheira e medevac (Parte 11). Regras em Shared/FieldWork.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local FieldWork = require(ReplicatedStorage.Shared.FieldWork)
local ItemAnim = require(ReplicatedStorage.Shared.ItemAnim)
local Logistics = require(ReplicatedStorage.Shared.Logistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Net = require(ReplicatedStorage.Shared.Net)
local PaArte = require(ReplicatedStorage.Shared.PaArte)
local AssetLoader = require(script.Parent.AssetLoader)
local Combatants = require(script.Parent.Combatants)
local LogisticsService = require(script.Parent.LogisticsService)
local PostureService = require(script.Parent.PostureService)

local FieldWorkService = {}
local M = 0.28
local lastDig: { [Player]: number } = {}
local digging: { [Player]: boolean } = {}
local holes = 0
-- D-193: o que cada buraco mudou, para a partida nova devolver (o terreno de antes, voxel a voxel, e o
-- parapeito de sacos que ele pôs). Volta na ordem contrária: buracos vizinhos se sobrepõem.
type Buraco = { region: Region3, mats: any, occs: any, parapeito: Model? }
local buracos: { Buraco } = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include

local function toast(p: Player, text: string)
	Net.event("Logistics_State"):FireClient(p, { error = text })
end

-- Lote 27 (D-142): andamento (não é erro). O "Cavando… fique parado" saía com o ✗ do erro.
local function info(p: Player, text: string)
	Net.event("Logistics_State"):FireClient(p, { info = text })
end

-- Buraco com o fundo na altura pedida. O voxel do terreno tem 4 studs (1,12 m) e a superfície é
-- suavizada: um FillBlock de 0,6 m de largura afundava só 0,2 a 0,5 m (reteste no Studio,
-- 2026-11-10). Aqui as colunas de voxels sob a pegada ficam vazias acima do fundo, e o voxel do
-- fundo fica com ocupação proporcional. A pegada vira múltiplo do voxel (2,2 a 3,4 m de lado).
-- A suavização ainda ergue o fundo de um buraco tão estreito: pedindo 1,2 m ele ficava a 0,58 m
-- (média de 10 buracos no Studio); pedindo 1,8 m, a 1,19 m (mediana de 42 medidas). Daí o extra.
-- D-183: a pegada é de 2 x 2 voxels alinhados à grade (FieldWork.holeGrid); com 1 voxel de largura o
-- fundo ficava a 0,62 m. SMOOTH_EXTRA_M medido no Studio no buraco de 2 x 2 (2026-11-19): folga 0,3 →
-- 0,87 a 0,94 m no centro; 0,6 → 1,24 m nos 4 pontos medidos; 0,9 → 1,54 m.
local VOXEL = 4
local SMOOTH_EXTRA_M = 0.6
local function excavate(minX: number, maxX: number, minZ: number, maxZ: number, topY: number, floorY: number): Buraco
	local region = Region3.new(Vector3.new(minX, floorY - VOXEL, minZ), Vector3.new(maxX, topY + 2 * VOXEL, maxZ))
		:ExpandToGrid(VOXEL)
	local mats, occs = workspace.Terrain:ReadVoxels(region, VOXEL)
	-- D-193: o terreno de antes (para devolver na partida nova)
	local antes: Buraco = { region = region, mats = nil, occs = nil, parapeito = nil }
	antes.mats, antes.occs = workspace.Terrain:ReadVoxels(region, VOXEL)
	local size = mats.Size
	local y0 = region.CFrame.Position.Y - region.Size.Y / 2
	for x = 1, size.X do
		for z = 1, size.Z do
			-- material do chão da coluna: o voxel cheio mais alto
			local ground = Enum.Material.Ground
			for y = size.Y, 1, -1 do
				if mats[x][y][z] ~= Enum.Material.Air then
					ground = mats[x][y][z]
					break
				end
			end
			-- lote 27 (D-142): terra revolvida no fundo. Com o capim de cima, a grama animada do terreno
			-- crescia dentro do buraco e o escondia (Studio, 2026-11-14)
			if ground == Enum.Material.Grass or ground == Enum.Material.LeafyGrass then
				ground = Enum.Material.Ground
			end
			for y = 1, size.Y do
				local yb = y0 + (y - 1) * VOXEL
				if yb >= floorY then
					mats[x][y][z] = Enum.Material.Air
					occs[x][y][z] = 0
				elseif yb + VOXEL > floorY then
					local o = (floorY - yb) / VOXEL
					if occs[x][y][z] > o or mats[x][y][z] == Enum.Material.Air then
						mats[x][y][z] = ground
						occs[x][y][z] = o
					end
				end
			end
		end
	end
	workspace.Terrain:WriteVoxels(region, VOXEL, mats, occs)
	table.insert(buracos, antes)
	return antes
end

-- D-193: a partida nova devolve o terreno de cada buraco (do último ao primeiro) e tira os parapeitos;
-- a conta de buracos e a espera de cada jogador zeram
function FieldWorkService.restaurar(): number
	local n = #buracos
	for i = n, 1, -1 do
		local b = buracos[i]
		pcall(function()
			workspace.Terrain:WriteVoxels(b.region, VOXEL, b.mats, b.occs)
		end)
		if b.parapeito then
			b.parapeito:Destroy()
		end
	end
	table.clear(buracos)
	holes = 0
	table.clear(lastDig)
	return n
end

-- ===== pá =====
-- D-183: as pazadas no buraco (Shared/ItemAnim.PA, o mesmo relógio da animação): a terra sai do buraco
-- para a direita de quem cava e o som de cada pazada (tools/sons_pa.py) toca em laço. Todos veem e
-- ouvem (peça do servidor). Devolve a função que para tudo.
local function emitter(
	name: string,
	size: { number },
	speed: NumberRange,
	life: NumberRange,
	alpha: number
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(92, 70, 48), Color3.fromRGB(122, 98, 72))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size[1]), NumberSequenceKeypoint.new(1, size[2]) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, alpha), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = life
	e.Speed = speed
	e.SpreadAngle = Vector2.new(20, 20)
	e.Acceleration = Vector3.new(0, -9.8 / M, 0)
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = 0
	return e
end

local function digFx(at: Vector3, right: Vector3): () -> ()
	local P = ItemAnim.PA
	local part = Instance.new("Part")
	part.Name = "VT65PaTerra"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	local pos = at + Vector3.new(0, 0.25 / M, 0)
	part.CFrame = CFrame.lookAt(pos, pos + right * 0.55 + Vector3.yAxis * 0.85)
	local torrao = emitter("Torrao", { 0.28, 0.4 }, NumberRange.new(9, 15), NumberRange.new(0.6, 0.9), 0)
	torrao.Parent = part
	local poeira = emitter("Poeira", { 1.2, 3.2 }, NumberRange.new(1.5, 4), NumberRange.new(1.0, 1.6), 0.55)
	poeira.Acceleration = Vector3.new(0, 0.3 / M, 0)
	poeira.Parent = part
	local s = Instance.new("Sound")
	s.Name = "Pazada"
	local id = AssetIds.Sounds.pa_cavar
	s.SoundId = "rbxassetid://"
		.. tostring(if type(id) == "number" and id ~= 0 then id else AssetIds.Sounds.impact_earth)
	s.Looped = true
	s.Volume = 0.9
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 2 / M
	s.RollOffMaxDistance = 40 / M
	s.Parent = part
	part.Parent = workspace
	local alive = true
	local function burst(e: ParticleEmitter, rate: number, dur: number)
		e.Rate = rate
		task.delay(dur, function()
			e.Rate = 0
		end)
	end
	task.spawn(function()
		local t0 = os.clock()
		local function waitUntil(t: number): boolean
			local d = t - (os.clock() - t0)
			if d > 0 then
				task.wait(d)
			end
			return alive
		end
		if not waitUntil(P.t0) then
			return
		end
		s:Play()
		for i = 0, P.n - 1 do
			local base = P.t0 + i * P.periodo
			if not waitUntil(base + 0.35) then
				return
			end
			burst(poeira, 14, 0.15) -- crava: a poeira sobe do buraco
			if not waitUntil(base + 1.0) then
				return
			end
			burst(torrao, 60, 0.2) -- joga: os torrões voam para a direita
			burst(poeira, 10, 0.2)
		end
	end)
	return function()
		if not alive then
			return
		end
		alive = false
		s:Stop()
		torrao.Rate, poeira.Rate = 0, 0
		task.delay(1.8, function()
			part:Destroy()
		end)
	end
end

local function onDig(p: Player)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or hum.Health <= 0 or char:GetAttribute("Downed") or hum.SeatPart or digging[p] then
		return
	end
	local C = FieldWork.DIG
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return
	end
	look = look.Unit
	-- D-183: o buraco é de 2 x 2 voxels na grade do terreno, com o centro no canto de voxels mais perto
	-- do ponto à frente
	local want = root.Position + look * (C.aheadM / M)
	local cx, cz, half = FieldWork.holeGrid(want.X, want.Z, VOXEL)
	local at = Vector3.new(cx, want.Y, cz)
	local hit = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), terrainOnly)
	if not hit then
		return
	end
	-- D-183: perto da base inimiga não (antes: só em setor do próprio lado)
	local faction = p:GetAttribute("Faction")
	local enemy = if faction == "US" then "VC" elseif faction == "VC" then "US" else nil
	local hq = if enemy then MapConfig.HQ[enemy] else nil
	local hqDistM = if hq then Vector2.new(cx - hq.x, cz - hq.z).Magnitude * M else nil
	-- água: terreno de água ou a lâmina d'água do arrozal (peça com Material "PaddyWater")
	local anyParams = RaycastParams.new()
	anyParams.FilterType = Enum.RaycastFilterType.Exclude
	anyParams.FilterDescendantsInstances = { char }
	local top = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), anyParams)
	local onWater = hit.Material == Enum.Material.Water
		or (top ~= nil and top.Instance:GetAttribute("Material") == "PaddyWater")
	-- Lote 27 (D-142): piso sólido rente ao chão (heliponto, piso de barraca, patamar de construção):
	-- a pá cavava embaixo dele e o buraco ficava escondido (Studio: o autoteste cavou sob a esteira do
	-- heliponto dos EUA). Raio curto, só na faixa de 0,6 m acima do chão: o de cima batia no helicóptero
	-- parado no heliponto. Planta não conta (folhagem não colide). D-183: no meio e nos 4 cantos de
	-- dentro do buraco, que agora tem 2,24 m de lado.
	for _, o in { { 0, 0 }, { -0.7, -0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { 0.7, 0.7 } } do
		local q = Vector3.new(cx + o[1] * half, hit.Position.Y, cz + o[2] * half)
		local floor = workspace:Raycast(q + Vector3.new(0, 0.6 / M, 0), Vector3.new(0, -0.7 / M, 0), anyParams)
		if
			floor
			and floor.Instance ~= workspace.Terrain
			and floor.Instance:IsA("BasePart")
			and (floor.Instance :: BasePart).CanCollide
		then
			toast(p, "Pá: aqui tem piso, procure chão de terra")
			return
		end
	end
	local ok, why, waitS = FieldWork.canDig(hqDistM, onWater, lastDig[p], os.clock(), holes)
	if not ok then
		if waitS then
			toast(p, string.format("Pá: próximo buraco em %d s", waitS)) -- D-183: diz quanto falta
		else
			toast(p, string.format("Pá: %s", tostring(why)))
		end
		return
	end
	digging[p] = true
	local start = root.Position
	info(p, string.format("Cavando… fique parado %d s", C.seconds))
	-- D-99: a animação da pá (ItemView) segue esta chave, nunca o texto do aviso, que pode vir traduzido
	Net.event("Logistics_State"):FireClient(p, { key = "dig_start" })
	-- D-183: a terra voando e o som de cada pazada no buraco (todos veem e ouvem). O servidor põe a pá
	-- na mão com o relógio dele (VT65Item/VT65ItemT): a animação de todos começa com a terra e o som
	-- (antes era o Posture_Set do cliente, uma ida e volta depois)
	local stopFx = digFx(hit.Position, root.CFrame.RightVector)
	char:SetAttribute("VT65ItemT", workspace:GetServerTimeNow())
	char:SetAttribute("VT65Item", "shovel")
	-- D-183: em pé, a ponta da pá ficava a 0,5-0,7 m do chão (Studio): quem cava se agacha. Volta a
	-- ficar em pé no fim, se estava em pé e ninguém mudou a postura no meio
	local crouched = false
	if not char:GetAttribute("Prone") and not char:GetAttribute("Crouched") then
		crouched = PostureService.setStance(char, "crouch")
	end
	task.spawn(function()
		local t0 = os.clock()
		local why: string? = nil
		while os.clock() - t0 < C.seconds do
			task.wait(0.2)
			local r2 = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not r2 or char.Parent == nil or hum.Health <= 0 or char:GetAttribute("Downed") then
				why = "morto"
				break
			end
			-- D-183: cancela na hora em que se move (antes só no fim dos 8 s); só o deslocamento no chão,
			-- porque agachar baixa o corpo
			if ((r2.Position - start) * Vector3.new(1, 0, 1)).Magnitude * M > C.stillM then
				why = "moveu"
				break
			end
		end
		digging[p] = nil
		stopFx()
		if char:GetAttribute("VT65Item") == "shovel" then
			char:SetAttribute("VT65Item", nil)
		end
		if crouched and char.Parent and char:GetAttribute("Crouched") == true and not char:GetAttribute("Downed") then
			PostureService.setStance(char, "stand")
		end
		if why then
			if why == "moveu" then
				toast(p, "Pá: cancelado (você se moveu)")
			end
			Net.event("Logistics_State"):FireClient(p, { key = "dig_cancel" })
			return
		end
		lastDig[p] = os.clock()
		holes += 1
		-- buraco: tira o terreno; a terra vira o parapeito de sacos de areia à frente
		local surf = hit.Position.Y
		local buraco =
			excavate(cx - half, cx + half, cz - half, cz + half, surf, surf - (C.depthM + SMOOTH_EXTRA_M) / M)
		-- Lote 27 (D-142): o parapeito vai ATRAVESSADO na frente do buraco (o comprido dos sacos, o Z do
		-- modelo, ao longo do buraco) e sem aterro: o patamar de terra do AssetLoader.place tapava o
		-- buraco. Assenta no chão mais baixo de 3 pontos. D-183: no lado do buraco que dá para onde o
		-- soldado olha, fora da borda (a parede vai até o centro do voxel vizinho, 1,5 voxel do meio).
		local axis = if math.abs(look.X) > math.abs(look.Z)
			then Vector3.new(math.sign(look.X), 0, 0)
			else Vector3.new(0, 0, math.sign(look.Z))
		local face = CFrame.lookAt(Vector3.new(cx, surf, cz), Vector3.new(cx, surf, cz) + axis)
		local front = face * CFrame.new(0, 0, -(1.5 * half + 0.3 / M))
		local folder = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild("Art")
		if folder then
			local across = front * CFrame.Angles(0, math.pi / 2, 0)
			local lo = math.huge
			for _, s in { -0.9, 0, 0.9 } do
				local q = (across * CFrame.new(0, 0, s / M)).Position
				local h = workspace:Raycast(q + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), terrainOnly)
				if h then
					lo = math.min(lo, h.Position.Y)
				end
			end
			if lo < math.huge then
				local saco = AssetLoader.placeAt(
					"sandbags",
					CFrame.new(front.X, lo - 0.05 / M, front.Z) * across.Rotation,
					folder
				)
				buraco.parapeito = if typeof(saco) == "Instance" and saco:IsA("Model") then saco else nil
			end
		end
		-- D-129: avisa que acabou (antes o buraco aparecia calado)
		Net.event("Logistics_State"):FireClient(p, { ok = "Buraco pronto: entre nele para se abrigar" })
	end)
end

FieldWorkService.dig = onDig -- autoteste (SelfTest) chama direto

-- ===== medevac =====
local boarding: { [Model]: number } = {}

local function helis(): { Model }
	local out = {}
	local f = workspace:FindFirstChild("Vehicles")
	for _, m in (if f then f:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("Spec") == "uh34d" then
			table.insert(out, m)
		end
	end
	return out
end

local function heliReady(h: Model): boolean
	local ch = h.PrimaryPart
	if not ch then
		return false
	end
	local hit = workspace:Raycast(ch.Position, Vector3.new(0, -200, 0), terrainOnly)
	local alt = if hit then (ch.Position.Y - ch.Size.Y / 2 - hit.Position.Y) * M else math.huge
	return FieldWork.heliReady(ch.AssemblyLinearVelocity.Magnitude * M, alt, h:GetAttribute("Destroyed") == true)
end

local function medevacTick()
	local ready = {}
	for _, h in helis() do
		if heliReady(h) and h.PrimaryPart then
			table.insert(ready, (h.PrimaryPart :: BasePart).Position)
		end
	end
	for _, e in Combatants.list() do
		local model, root = e.model, Combatants.root(e)
		if e.faction == "US" and root and model:GetAttribute("Downed") and not model:GetAttribute("Evacuated") then
			local near = false
			for _, pos in ready do
				if (pos - root.Position).Magnitude * M <= FieldWork.MEDEVAC.radiusM then
					near = true
				end
			end
			local t, done = FieldWork.boarding(boarding[model] or 0, near, 1)
			boarding[model] = t
			if done then
				boarding[model] = nil
				model:SetAttribute("Evacuated", true) -- não conta como morto no relatório
				local st = LogisticsService.state
				st.supply.US = math.min(Logistics.CAP, (st.supply.US or 0) + FieldWork.MEDEVAC.supply)
				local hum = Combatants.humanoid(e)
				if e.player then
					toast(
						e.player,
						string.format("Evacuado pelo UH-34D: +%d de suprimento para o time", FieldWork.MEDEVAC.supply)
					)
				end
				if hum then
					hum.Health = 0 -- sai do campo; renasce pelas regras normais
				end
			end
		end
	end
end

function FieldWorkService.start()
	terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
	Net.event("Dig_Request").OnServerEvent:Connect(onDig)
	-- D-183: a pá do Blender para a mão de 1ª e 3ª pessoa (Shared/PaArte): cópia dos modelos publicados
	task.spawn(function()
		local folder = Instance.new("Folder")
		folder.Name = PaArte.FOLDER
		for _, f in { "US", "VC" } do
			local key = PaArte.key(f)
			local tpl = AssetLoader.template(key)
			if tpl then
				local copy = tpl:Clone()
				copy.Name = key
				copy.Parent = folder
			end
		end
		folder.Parent = ReplicatedStorage
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastDig[p] = nil
		digging[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			medevacTick()
		end
	end)
end

return FieldWorkService
