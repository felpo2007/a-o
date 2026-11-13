--!strict
-- Caixas de acerto (D-107, pedido do dono: "concerte o hitbox dos personagens", "os tiros não estão
-- acertando"). A conta das caixas e do raio é pura (Lune: tests/luau/combate.luau); fromModel e trace
-- só rodam no Roblox (servidor e cliente usam as mesmas).
-- Causas achadas (2026-11-13):
--   - o servidor fazia o raio contra as peças do corpo NA POSIÇÃO DO SERVIDOR na chegada do tiro. O
--     atirador vê o alvo atrasado pela rede (interpolação + meio ping) e com a pose que só os clientes
--     montam: os bots não são animados no servidor (SoldierAnims.BOTS anima só nos clientes), a
--     inclinação (Lean) é só atributo e o agachado do servidor é o corpo em pé afundado. Alvo andando,
--     inclinado ou agachado: o tiro que pegava na tela passava longe no servidor;
--   - cabeça de bloco (D-102): a peça "Head" do R15 é 2 x 1 x 1 (x 1,43) com a malha de cabeça por
--     cima, 1,25 x o lado curto. O raio batia na caixa da PEÇA: o topo e a nuca da cabeça que se vê
--     ficavam fora (e a peça sobrava dos lados, onde não há cabeça); o capacete (CanQuery = false)
--     deixava a bala passar.
-- Agora: o tiro pega numa caixa por parte do corpo, do tamanho do que se vê (cabeça de bloco pela
-- malha, capacete e colete por cima), com folga pequena. O servidor confere o tiro com as caixas na
-- posição dele; o cliente de quem atirou refaz a mesma bala contra as caixas como ELE vê os soldados e,
-- se pegou, avisa (Combat_Claim). O servidor confere esse aviso (trajetória da semente, caminho livre
-- até o ponto e o ponto perto do alvo, com folga pela velocidade dele) e aplica o dano.
local Ballistics = require(script and (script :: any).Parent.Ballistics or "./Ballistics") :: any

local Hitbox = {}

Hitbox.M = 0.28 -- m por stud

-- Zona de dano por peça do corpo (R15)
Hitbox.ZONE = {
	Head = "head",
	UpperTorso = "torso",
	LowerTorso = "torso",
	LeftUpperArm = "arm",
	LeftLowerArm = "arm",
	LeftHand = "arm",
	RightUpperArm = "arm",
	RightLowerArm = "arm",
	RightHand = "arm",
	LeftUpperLeg = "leg",
	LeftLowerLeg = "leg",
	LeftFoot = "leg",
	RightUpperLeg = "leg",
	RightLowerLeg = "leg",
	RightFoot = "leg",
} :: { [string]: string }

-- Equipamento que conta como corpo (modelos "Gear_*" do Characters): capacete e chapéu = cabeça,
-- colete = tronco. Peça do corpo que o servidor usa como referência do aviso.
Hitbox.GEAR = {
	Gear_us_m1_helmet = "head",
	Gear_vc_pith_helmet = "head",
	Gear_vc_jungle_hat = "head",
	Gear_us_m1955_vest = "torso",
} :: { [string]: string }
Hitbox.GEAR_PART = { head = "Head", torso = "UpperTorso" } :: { [string]: string }

-- Folga da caixa sobre o que se vê, por zona (PLACEHOLDER de jogo; o Front 44 usa 1,06 a 1,5). As
-- peças finas (braço) ganham mais.
Hitbox.PAD = { head = 1.06, torso = 1.08, arm = 1.25, leg = 1.15 } :: { [string]: number }
-- Cabeça de bloco (Part com a malha "Head"): a malha é um cubo de 1,25 x o lado curto da peça
-- (a peça é 2 x 1 x 1 vezes a escala). Cabeça em MeshPart: o tamanho dela.
Hitbox.HEAD_MESH = 1.25

-- Candidatos: soldado com o HumanoidRootPart a até REACH studs da linha do tiro (o corpo deitado tem
-- ~7 studs; a queda da bala soma à parte).
Hitbox.REACH = 9
-- Aviso do cliente (Combat_Claim): ponto até PATH_TOL studs da trajetória da semente; até CLAIM_S s
-- depois do tiro; perto da peça no servidor (tolerance).
Hitbox.PATH_TOL = 1.0
Hitbox.CLAIM_S = 1.0
Hitbox.LAG_S = 0.5 -- quanto o alvo pode ter andado entre o que o atirador viu e o servidor
Hitbox.CLAIM_BASE = 3 -- folga (studs) pela pose: bot sem animação no servidor, inclinação, agachado
Hitbox.CLAIM_MAX = 16 -- folga máxima (studs) entre o ponto do aviso e a peça no servidor

export type Box = {
	x: number,
	y: number,
	z: number,
	r: { number }, -- rotação como o CFrame:GetComponents (R00 R01 R02 R10 ... R22)
	hx: number,
	hy: number,
	hz: number,
	rad: number, -- raio da esfera que contém a caixa (descarte rápido)
	zone: string,
	part: string, -- peça do corpo que o aviso manda ao servidor
	model: any?, -- personagem (Roblox)
}

-- Caixa pelo centro, rotação (9 números) e tamanho inteiro.
function Hitbox.new(
	x: number,
	y: number,
	z: number,
	r: { number },
	sx: number,
	sy: number,
	sz: number,
	zone: string,
	part: string,
	model: any?
): Box
	local hx, hy, hz = sx / 2, sy / 2, sz / 2
	return {
		x = x,
		y = y,
		z = z,
		r = r,
		hx = hx,
		hy = hy,
		hz = hz,
		rad = math.sqrt(hx * hx + hy * hy + hz * hz),
		zone = zone,
		part = part,
		model = model,
	}
end

Hitbox.IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } :: { number }

-- Tamanho da cabeça que se vê: MeshPart = o tamanho dela; Part de bloco = cubo pela malha.
function Hitbox.headSize(sx: number, sy: number, sz: number, isMesh: boolean): (number, number, number)
	if isMesh then
		return sx, sy, sz
	end
	local side = Hitbox.HEAD_MESH * math.min(sy, sz)
	return side, side, side
end

-- Fração [0, 1] do segmento A->B em que ele entra na caixa (0 = A já dentro), ou nil.
function Hitbox.segment(ax: number, ay: number, az: number, bx: number, by: number, bz: number, b: Box): number?
	local px, py, pz = ax - b.x, ay - b.y, az - b.z
	local dx, dy, dz = bx - ax, by - ay, bz - az
	-- esfera: ponto do segmento mais perto do centro
	local dd = dx * dx + dy * dy + dz * dz
	local t = if dd > 1e-12 then math.clamp(-(px * dx + py * dy + pz * dz) / dd, 0, 1) else 0
	local cx, cy, cz = px + dx * t, py + dy * t, pz + dz * t
	if cx * cx + cy * cy + cz * cz > b.rad * b.rad then
		return nil
	end
	local r = b.r
	-- eixos da caixa: colunas da rotação (direita, cima, trás)
	local o1 = px * r[1] + py * r[4] + pz * r[7]
	local o2 = px * r[2] + py * r[5] + pz * r[8]
	local o3 = px * r[3] + py * r[6] + pz * r[9]
	local d1 = dx * r[1] + dy * r[4] + dz * r[7]
	local d2 = dx * r[2] + dy * r[5] + dz * r[8]
	local d3 = dx * r[3] + dy * r[6] + dz * r[9]
	local tmin, tmax = 0, 1
	for i = 1, 3 do
		local o = if i == 1 then o1 elseif i == 2 then o2 else o3
		local d = if i == 1 then d1 elseif i == 2 then d2 else d3
		local h = if i == 1 then b.hx elseif i == 2 then b.hy else b.hz
		if math.abs(d) < 1e-12 then
			if math.abs(o) > h then
				return nil
			end
		else
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > tmin then
				tmin = t1
			end
			if t2 < tmax then
				tmax = t2
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end

-- Primeira caixa que o segmento pega: (fração, caixa) ou nil.
function Hitbox.first(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	boxes: { Box }
): (number?, Box?)
	local best, which = math.huge, nil
	for _, b in boxes do
		local f = Hitbox.segment(ax, ay, az, bx, by, bz, b)
		if f and f < best then
			best, which = f, b
		end
	end
	if which then
		return best, which
	end
	return nil, nil
end

-- Distância do ponto P à trajetória gravada (lista plana x, y, z de cada ponto): (distância,
-- segmento 1.., fração no segmento). Trajetória com menos de 2 pontos: math.huge.
function Hitbox.near(path: { number }, px: number, py: number, pz: number): (number, number?, number)
	local best, seg, frac = math.huge, nil, 0
	local n = #path // 3
	for i = 1, n - 1 do
		local j = (i - 1) * 3
		local ax, ay, az = path[j + 1], path[j + 2], path[j + 3]
		local dx, dy, dz = path[j + 4] - ax, path[j + 5] - ay, path[j + 6] - az
		local dd = dx * dx + dy * dy + dz * dz
		local t = if dd > 1e-12 then math.clamp(((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / dd, 0, 1) else 0
		local cx, cy, cz = ax + dx * t - px, ay + dy * t - py, az + dz * t - pz
		local d = math.sqrt(cx * cx + cy * cy + cz * cz)
		if d < best then
			best, seg, frac = d, i, t
		end
	end
	return best, seg, frac
end

-- Folga (studs) entre o ponto do aviso e a peça do alvo no servidor: pose (bot sem animação no
-- servidor, inclinação, agachado), meio corpo da peça e o quanto o alvo andou na defasagem.
function Hitbox.tolerance(partDiag: number, speedStuds: number): number
	return math.min(Hitbox.CLAIM_BASE + partDiag / 2 + math.abs(speedStuds) * Hitbox.LAG_S, Hitbox.CLAIM_MAX)
end

-- Soldado perto da linha do tiro? rel = raiz - origem (studs), d = direção unitária, v = velocidade
-- da bala (m/s, para a queda). extra = folga a mais (studs).
function Hitbox.nearRay(
	relX: number,
	relY: number,
	relZ: number,
	dx: number,
	dy: number,
	dz: number,
	v: number,
	extra: number
): boolean
	local t = relX * dx + relY * dy + relZ * dz
	if t < -Hitbox.REACH then
		return false
	end
	local tm = math.max(t, 0) * Hitbox.M
	-- queda sem arrasto com a bala a 70% da boca, vezes 1,5 (a queda real é maior que a do vácuo)
	local fall = 0.5 * Ballistics.G * (tm / math.max(v * 0.7, 30)) ^ 2 * 1.5 / Hitbox.M
	local cx, cy, cz = relX - dx * t, relY - dy * t, relZ - dz * t
	local reach = Hitbox.REACH + fall + extra
	return cx * cx + cy * cy + cz * cz <= reach * reach
end

-- ===== Roblox =====

local function fromCFrame(cf: CFrame, sx: number, sy: number, sz: number, zone: string, part: string, model: Model): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return Hitbox.new(x, y, z, { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, sx, sy, sz, zone, part, model)
end

-- Caixa de um equipamento (modelo): a do Roblox; no Lune (testes, sem GetBoundingBox) a da 1ª peça
local function gearBox(m: Model): (CFrame?, Vector3?)
	local ok, cf, size = pcall(function()
		return m:GetBoundingBox()
	end)
	if ok then
		return cf, size
	end
	local p = m:FindFirstChildWhichIsA("BasePart", true)
	if p then
		return p.CFrame, p.Size
	end
	return nil, nil
end

-- Caixas do personagem como ESTA máquina o vê (peças do corpo, capacete e colete).
function Hitbox.fromModel(model: Model, out: { Box }?): { Box }
	local list: { Box } = out or {}
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") then
			local zone = Hitbox.ZONE[c.Name]
			if zone then
				local s = c.Size
				local sx, sy, sz = s.X, s.Y, s.Z
				if zone == "head" then
					sx, sy, sz = Hitbox.headSize(sx, sy, sz, c:IsA("MeshPart"))
				end
				local k = Hitbox.PAD[zone] or 1
				table.insert(list, fromCFrame(c.CFrame, sx * k, sy * k, sz * k, zone, c.Name, model))
			end
		elseif c:IsA("Model") then
			local zone = Hitbox.GEAR[c.Name]
			if zone then
				local cf, size = gearBox(c)
				if cf and size then
					table.insert(list, fromCFrame(cf, size.X, size.Y, size.Z, zone, Hitbox.GEAR_PART[zone], model))
				end
			end
		end
	end
	return list
end

export type Traced = {
	hit: any?, -- Ballistics.Hit (metros)
	box: Box?, -- caixa que a bala pegou (nil = mundo ou nada)
	keep: number, -- fração da velocidade que ficou nos materiais atravessados (Ballistics.PASS)
	path: { number }, -- pontos da trajetória em studs (só com record), até o impacto
	speed: { number }, -- velocidade (m/s) em cada segmento
	keepAt: { number }, -- fração "keep" no começo de cada segmento
}

-- Trajetória do tiro (a mesma semente no servidor e no cliente) contra o mundo e as caixas. `ignore`
-- sai do raio do mundo (quem atirou, o veículo dele e TODOS os soldados: quem decide o corpo é a
-- caixa). record: grava a trajetória (o servidor, para conferir o aviso do cliente).
function Hitbox.trace(
	weaponId: string,
	origin: Vector3,
	dir: Vector3,
	seed: number,
	maxTime: number?,
	ignore: { Instance },
	boxes: { Box },
	record: boolean
): Traced
	local M = Hitbox.M
	local dt = Ballistics.SHOT_DT
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	params.FilterDescendantsInstances = list
	local out: Traced = { hit = nil, box = nil, keep = 1, path = {}, speed = {}, keepAt = {} }
	local path, speed, keepAt = out.path, out.speed, out.keepAt
	local hit = Ballistics.trace({
		ox = origin.X * M,
		oy = origin.Y * M,
		oz = origin.Z * M,
		dx = dir.X,
		dy = dir.Y,
		dz = dir.Z,
		weaponId = weaponId,
		seed = seed,
		maxTime = maxTime,
		dt = dt,
	}, function(ax: number, ay: number, az: number, bx: number, by: number, bz: number): any?
		local A = Vector3.new(ax, ay, az) / M
		local B = Vector3.new(bx, by, bz) / M
		local delta = B - A
		if record then
			if #path == 0 then
				table.insert(path, A.X)
				table.insert(path, A.Y)
				table.insert(path, A.Z)
			end
			table.insert(path, B.X)
			table.insert(path, B.Y)
			table.insert(path, B.Z)
			table.insert(speed, delta.Magnitude * M / dt)
			table.insert(keepAt, out.keep)
		end
		local fb, bb = Hitbox.first(A.X, A.Y, A.Z, B.X, B.Y, B.Z, boxes)
		local dd = delta:Dot(delta)
		for _ = 1, 4 do -- até 4 materiais atravessáveis por segmento
			local r = workspace:Raycast(A, delta, params)
			local fw = if r and dd > 1e-12 then (r.Position - A):Dot(delta) / dd else math.huge
			if fb and bb and fb <= fw then
				out.box = bb
				local p = (A + delta * fb) * M
				return { x = p.X, y = p.Y, z = p.Z, target = nil }
			end
			if not r then
				return nil
			end
			local mat = r.Instance:GetAttribute("Material")
			local keep = if type(mat) == "string" then Ballistics.PASS[mat] else nil
			if keep then
				out.keep *= keep
				table.insert(list, r.Instance)
				params.FilterDescendantsInstances = list
			else
				local p = r.Position * M
				return { x = p.X, y = p.Y, z = p.Z, target = r.Instance }
			end
		end
		return nil
	end)
	out.hit = hit
	-- a trajetória gravada termina no impacto (o aviso não vale depois da parede)
	if record and hit and #path >= 3 then
		local n = #path
		path[n - 2], path[n - 1], path[n] = hit.x / M, hit.y / M, hit.z / M
	end
	return out
end

return Hitbox
