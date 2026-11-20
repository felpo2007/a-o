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
local lastDig: { [Player]: number } = {} -- quando o jogador começou o último buraco novo
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
-- 2026-11-10). As colunas de voxels sob a pegada ficam vazias acima do fundo, e o voxel do fundo fica
-- com ocupação proporcional. A suavização ainda ergue o fundo de um buraco tão estreito: pedindo
-- 1,2 m ele ficava a 0,58 m (média de 10 buracos no Studio); pedindo 1,8 m, a 1,19 m (mediana de 42
-- medidas). Daí o extra. D-183: a pegada é de 2 x 2 voxels alinhados à grade (FieldWork.holeGrid);
-- com 1 voxel de largura o fundo ficava a 0,62 m. SMOOTH_EXTRA_M medido no Studio no buraco de 2 x 2
-- (2026-11-19): folga 0,3 → 0,87 a 0,94 m no centro; 0,6 → 1,24 m nos 4 pontos medidos; 0,9 → 1,54 m.
local VOXEL = 4
local SMOOTH_EXTRA_M = 0.6
local FUNDO_M = FieldWork.DIG.depthM + SMOOTH_EXTRA_M
-- D-195: o capim do fundo vira terra revolvida (lote 27, D-142: com o capim, a grama animada do
-- terreno crescia dentro do buraco e o escondia)
local CAPIM = { [Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true } :: { [any]: boolean }

-- ===== D-195: a obra de cada buraco (pazada a pazada) =====
-- A grade 4 x 4 de voxels em volta do buraco (o buraco são as 4 do meio): o terreno de antes (que a
-- partida nova devolve, D-193), quantas pazadas já entraram e o lado do monte e do parapeito.
type Obra = {
	key: string,
	cx: number,
	cz: number,
	half: number,
	surf: number, -- topo do chão no meio (studs)
	ax: number, -- eixo para onde quem começou olhava (±1 ou 0): o lado do monte e do parapeito
	az: number,
	look: Vector3,
	hit: Vector3,
	k: number,
	n: number,
	buraco: Buraco,
}
local obras: { [string]: Obra } = {}
local paMao: { [Player]: { crouched: boolean, conns: { RBXScriptConnection } } } = {}
local lastStroke: { [Player]: number } = {}

local function obraKey(cx: number, cz: number): string
	return string.format("%d:%d", math.round(cx), math.round(cz))
end

-- Escreve a obra com k pazadas, sempre a partir do terreno de antes: o resultado é o mesmo não
-- importa quem cavou nem em que ordem as pazadas chegaram. 16 colunas de poucos voxels por pazada.
local function aplicar(o: Obra)
	local b = o.buraco
	local mats, occs = b.mats, b.occs
	local size = mats.Size
	local y0 = b.region.CFrame.Position.Y - b.region.Size.Y / 2
	local outM, outO = {}, {}
	for x = 1, size.X do
		outM[x], outO[x] = {}, {}
		for y = 1, size.Y do
			outM[x][y], outO[x][y] = {}, {}
		end
		for z = 1, size.Z do
			local colM, colO = {}, {}
			local chao = Enum.Material.Ground
			for y = 1, size.Y do
				colM[y], colO[y] = mats[x][y][z], occs[x][y][z]
			end
			for y = size.Y, 1, -1 do
				if colM[y] ~= Enum.Material.Air then
					chao = if CAPIM[colM[y]] then Enum.Material.Ground else colM[y]
					break
				end
			end
			local tipo = FieldWork.coluna(x, z, o.ax, o.az)
			local j = FieldWork.jitter(o.cx, o.cz, x, z)
			local dy = FieldWork.alturaColuna(tipo, o.k, o.n, FUNDO_M, j, SMOOTH_EXTRA_M) / M
			local topo = FieldWork.topoColuna(colO, y0, VOXEL)
			local alvo = if tipo == "buraco" then math.min(o.surf + dy, topo) else topo + dy
			-- o monte é terra solta (a de baixo do capim)
			local nm, no = FieldWork.colunaVoxels(
				colM,
				colO,
				y0,
				VOXEL,
				alvo,
				if tipo == "monte" then Enum.Material.Ground else chao,
				Enum.Material.Air,
				CAPIM
			)
			for y = 1, size.Y do
				outM[x][y][z], outO[x][y][z] = nm[y], no[y]
			end
		end
	end
	workspace.Terrain:WriteVoxels(b.region, VOXEL, outM, outO)
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
	table.clear(obras) -- D-195: as obras em andamento também
	table.clear(lastStroke)
	holes = 0
	table.clear(lastDig)
	return n
end

-- ===== pá =====
-- D-183: as pazadas no buraco (Shared/ItemAnim.PA, o mesmo relógio da animação): a terra sai do buraco
-- para a direita de quem cava. Todos veem e ouvem (peça do servidor).
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

-- D-195: UMA pazada (antes, 5 em laço): o som inteiro dela (pa_cavar, 1,4 s, a lâmina crava aos
-- 0,35 s), a poeira na hora em que crava e os torrões quando joga (1,0 s)
local function pazadaFx(at: Vector3, right: Vector3)
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
	s.Volume = 0.9
	s.PlaybackSpeed = 0.96 + math.random() * 0.08 -- variação pequena, sem mudar o caráter
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 2 / M
	s.RollOffMaxDistance = 40 / M
	s.Parent = part
	part.Parent = workspace
	s:Play()
	local C = FieldWork.DIG
	task.delay(C.contatoS, function()
		poeira:Emit(5)
	end)
	task.delay(1.0, function()
		torrao:Emit(14)
		poeira:Emit(3)
	end)
	task.delay(3, function()
		part:Destroy()
	end)
end

-- Parapeito de sacos de areia no fim do buraco. Lote 27 (D-142): ATRAVESSADO na frente do buraco (o
-- comprido dos sacos, o Z do modelo, ao longo do buraco) e sem aterro: o patamar de terra do
-- AssetLoader.place tapava o buraco. Assenta no chão mais baixo de 3 pontos. D-183: no lado do buraco
-- que dá para onde o soldado olhava, fora da borda (1,5 voxel do meio). D-195: em cima do monte.
local function parapeito(o: Obra)
	local axis = Vector3.new(o.ax, 0, o.az)
	local face = CFrame.lookAt(Vector3.new(o.cx, o.surf, o.cz), Vector3.new(o.cx, o.surf, o.cz) + axis)
	local front = face * CFrame.new(0, 0, -(1.5 * o.half + 0.3 / M))
	local folder = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild("Art")
	if not folder then
		return
	end
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
		local saco =
			AssetLoader.placeAt("sandbags", CFrame.new(front.X, lo - 0.05 / M, front.Z) * across.Rotation, folder)
		o.buraco.parapeito = if typeof(saco) == "Instance" and saco:IsA("Model") then saco else nil
	end
end

-- Buraco novo à frente de quem cava: as regras de antes (terra, longe da base inimiga, fora da
-- água e de piso, 1 buraco novo por minuto, limite no mapa) e o terreno de antes guardado.
local function novaObra(p: Player, char: Model, root: BasePart, look: Vector3, cx: number, cz: number): Obra?
	local C = FieldWork.DIG
	local half = VOXEL
	local at = Vector3.new(cx, root.Position.Y, cz)
	local hit = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), terrainOnly)
	if not hit then
		return nil
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
	-- a pá cavava embaixo dele e o buraco ficava escondido. Raio curto, só na faixa de 0,6 m acima do
	-- chão. Planta não conta (folhagem não colide). D-183: no meio e nos 4 cantos de dentro do buraco.
	for _, q0 in { { 0, 0 }, { -0.7, -0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { 0.7, 0.7 } } do
		local q = Vector3.new(cx + q0[1] * half, hit.Position.Y, cz + q0[2] * half)
		local floor = workspace:Raycast(q + Vector3.new(0, 0.6 / M, 0), Vector3.new(0, -0.7 / M, 0), anyParams)
		if
			floor
			and floor.Instance ~= workspace.Terrain
			and floor.Instance:IsA("BasePart")
			and (floor.Instance :: BasePart).CanCollide
		then
			toast(p, "Pá: aqui tem piso, procure chão de terra")
			return nil
		end
	end
	local ok, why, waitS = FieldWork.canDig(hqDistM, onWater, lastDig[p], os.clock(), holes)
	if not ok then
		if waitS then
			toast(p, string.format("Pá: próximo buraco em %d s", waitS)) -- D-183: diz quanto falta
		else
			toast(p, string.format("Pá: %s", tostring(why)))
		end
		return nil
	end
	lastDig[p] = os.clock()
	holes += 1
	local surf = hit.Position.Y
	-- a grade 4 x 4 em volta (o buraco e as bordas), do fundo até 3 voxels acima do chão (o monte e o
	-- chão em declive)
	local region = Region3.new(
		Vector3.new(cx - 2 * half, surf - FUNDO_M / M - VOXEL, cz - 2 * half),
		Vector3.new(cx + 2 * half, surf + 3 * VOXEL, cz + 2 * half)
	):ExpandToGrid(VOXEL)
	local b: Buraco = { region = region, mats = nil, occs = nil, parapeito = nil }
	b.mats, b.occs = workspace.Terrain:ReadVoxels(region, VOXEL)
	table.insert(buracos, b)
	local ax, az = 0, 0
	if math.abs(look.X) > math.abs(look.Z) then
		ax = if look.X >= 0 then 1 else -1
	else
		az = if look.Z >= 0 then 1 else -1
	end
	local o: Obra = {
		key = obraKey(cx, cz),
		cx = cx,
		cz = cz,
		half = half,
		surf = surf,
		ax = ax,
		az = az,
		look = look,
		hit = hit.Position,
		k = 0,
		n = C.pazadas,
		buraco = b,
	}
	obras[o.key] = o
	return o
end

-- Onde vai a pazada: um buraco começado perto do ponto à frente continua; senão, um novo na grade.
local function alvoDaPazada(p: Player, char: Model, root: BasePart): Obra?
	local C = FieldWork.DIG
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return nil
	end
	look = look.Unit
	local want = root.Position + look * (C.aheadM / M)
	local best: Obra?, bestD = nil, C.juntoM / M
	for _, o in obras do
		if o.k < o.n then
			local d = Vector2.new(o.cx - want.X, o.cz - want.Z).Magnitude
			if d <= bestD then
				best, bestD = o, d
			end
		end
	end
	if best then
		return best
	end
	local cx, cz = FieldWork.holeGrid(want.X, want.Z, VOXEL)
	if obras[obraKey(cx, cz)] then
		toast(p, "Pá: este buraco já está pronto")
		return nil
	end
	return novaObra(p, char, root, look, cx, cz)
end

local function vivo(p: Player): (Model?, Humanoid?, BasePart?)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or hum.Health <= 0 or char:GetAttribute("Downed") or hum.SeatPart then
		return nil, nil, nil
	end
	return char, hum, root
end

-- A pá na mão (vaga 8, roda, toque). O servidor põe a pá na mão com o relógio dele (VT65Item e
-- VT65ItemT): todos veem. D-183: em pé, a ponta da pá ficava a 0,5-0,7 m do chão: quem pega a pá se
-- agacha, e volta a ficar em pé ao guardar, se ninguém mudou a postura no meio.
local guardar: (p: Player) -> ()

local function pegar(p: Player)
	local char, hum = vivo(p)
	if not (char and hum) or char:GetAttribute("VT65Item") == "shovel" then
		return
	end
	char:SetAttribute("VT65ItemT", workspace:GetServerTimeNow())
	char:SetAttribute("VT65Item", "shovel")
	local crouched = false
	if not char:GetAttribute("Prone") and not char:GetAttribute("Crouched") then
		crouched = PostureService.setStance(char, "crouch")
	end
	-- sentou num veículo ou caiu ferido: a pá volta ao cinto
	local h = hum :: Humanoid
	local c = char :: Model
	paMao[p] = {
		crouched = crouched,
		conns = {
			h:GetPropertyChangedSignal("SeatPart"):Connect(function()
				if h.SeatPart then
					guardar(p)
				end
			end),
			c:GetAttributeChangedSignal("Downed"):Connect(function()
				if c:GetAttribute("Downed") then
					guardar(p)
				end
			end),
		},
	}
	Net.event("Logistics_State"):FireClient(p, { key = "pa_mao" })
	info(p, string.format("Pá na mão: uma pazada por aperto do gatilho (%d para o buraco)", FieldWork.DIG.pazadas))
end

function guardar(p: Player)
	local char = p.Character
	local st = paMao[p]
	paMao[p] = nil
	if st then
		for _, c in st.conns do
			c:Disconnect()
		end
	end
	if not char then
		return
	end
	if char:GetAttribute("VT65Item") == "shovel" then
		char:SetAttribute("VT65Item", nil)
	end
	if
		st
		and st.crouched
		and char.Parent
		and char:GetAttribute("Crouched") == true
		and not char:GetAttribute("Downed")
	then
		PostureService.setStance(char, "stand")
	end
	Net.event("Logistics_State"):FireClient(p, { key = "pa_guardada" })
end

-- Uma pazada: o servidor confere a pá na mão, a cadência (o excesso é jogado fora: não vira fila),
-- o lugar e, no contato (contatoS), que quem cava não saiu dali. A animação de todos começa com o
-- atributo VT65PazadaT; o som e a terra são do servidor.
local function pazada(p: Player)
	local char, hum, root = vivo(p)
	if not (char and hum and root) or char:GetAttribute("VT65Item") ~= "shovel" then
		return
	end
	local now = os.clock()
	if not FieldWork.podePazada(lastStroke[p], now) then
		return
	end
	local o = alvoDaPazada(p, char, root)
	if not o then
		return
	end
	lastStroke[p] = now
	char:SetAttribute("VT65PazadaT", workspace:GetServerTimeNow())
	pazadaFx(o.hit, root.CFrame.RightVector)
	local C = FieldWork.DIG
	local start = root.Position
	task.delay(C.contatoS, function()
		local r2 = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not r2 or char.Parent == nil or hum.Health <= 0 or char:GetAttribute("Downed") or hum.SeatPart then
			return
		end
		-- só o deslocamento no chão (agachar baixa o corpo). O servidor vê o corpo do cliente com o atraso
		-- da física (~0,15-0,2 s no Studio): por isso também o alcance, a pá tem que chegar ao buraco.
		local flat = Vector3.new(1, 0, 1)
		local longe = ((r2.Position - Vector3.new(o.cx, r2.Position.Y, o.cz)) * flat).Magnitude * M
		if ((r2.Position - start) * flat).Magnitude * M > C.stillM or longe > C.alcanceM then
			toast(p, "Pá: pazada perdida (você se moveu)")
			return
		end
		if obras[o.key] ~= o or o.k >= o.n then
			return -- a partida nova devolveu o chão, ou outro terminou o buraco
		end
		o.k += 1
		aplicar(o)
		if o.k >= o.n then
			parapeito(o)
			-- D-129: avisa que acabou (antes o buraco aparecia calado)
			Net.event("Logistics_State"):FireClient(p, { ok = "Buraco pronto: entre nele para se abrigar" })
		else
			info(p, string.format("Buraco: %d/%d", o.k, o.n))
		end
	end)
end

-- Dig_Request { op = "pegar" | "guardar" | "pazada" }; sem op (toque, versão antiga): alterna a pá
local function onDig(p: Player, req: any)
	local op = if type(req) == "table" then req.op else nil
	if op == "pazada" then
		pazada(p)
	elseif op == "guardar" then
		guardar(p)
	elseif op == "pegar" then
		pegar(p)
	else
		local char = p.Character
		if char and char:GetAttribute("VT65Item") == "shovel" then
			guardar(p)
		else
			pegar(p)
		end
	end
end

-- autoteste (SelfTest): pega a pá, dá as pazadas na cadência e guarda (~9 s, como antes)
function FieldWorkService.dig(p: Player)
	pegar(p)
	task.spawn(function()
		task.wait(ItemAnim.PA.t0)
		for _ = 1, FieldWork.DIG.pazadas do
			pazada(p)
			task.wait(FieldWork.DIG.pazadaS)
		end
		guardar(p)
	end)
end

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
		lastStroke[p] = nil
		paMao[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			medevacTick()
		end
	end)
end

return FieldWorkService
