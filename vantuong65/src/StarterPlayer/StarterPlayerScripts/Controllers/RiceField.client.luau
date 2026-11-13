--!strict
-- Arrozal vivo (D-74): cobre de arroz os tabuleiros perto da câmera. O servidor põe o dossel (placa
-- verde na altura do arroz, Map.Arrozal) em cada tabuleiro plantado; aqui o dossel dos tabuleiros a
-- menos de RiceField.FAR some e o tabuleiro inteiro recebe ladrilhos de cartões: o alto (96
-- cartões) a menos de RiceField.NEAR, o baixo (24) no resto. Os ladrilhos vêm de uma reserva e só
-- mudam de lugar (sem criar e destruir peça a cada passo). A grade e o giro de cada ladrilho saem
-- da posição do tabuleiro (Shared/RiceField): todos os jogadores veem o mesmo arroz.
-- Também faz tremer a chama das lamparinas dos túneis e do fogão (tag VT65Lamp, MapLife).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RiceField = require(ReplicatedStorage.Shared.RiceField)

local camera = workspace.CurrentCamera
local HIDDEN = CFrame.new(0, -5000, 0)
local player = game:GetService("Players").LocalPlayer

-- D-82: opção de detalhe (Graficos.client): 1, 0,6 ou 0,3
local function detail(): number
	local d = player:GetAttribute("GfxDetail")
	return if type(d) == "number" then d else 1
end
-- alcance do arroz em cartões (fora dele, o dossel) e do ladrilho alto, por nível de detalhe
local function ranges(): (number, number)
	local d = detail()
	if d >= 0.99 then
		return RiceField.FAR, RiceField.NEAR
	elseif d >= 0.5 then
		return RiceField.FAR * 0.7, RiceField.NEAR * 0.6
	end
	return RiceField.FAR * 0.45, RiceField.NEAR * 0.35
end

local art = ReplicatedStorage:WaitForChild("VT65RiceArt", 900)
local map = workspace:WaitForChild("Map", 900)
local holder = Instance.new("Folder")
holder.Name = "VT65ArrozLocal"
holder.Parent = workspace

type Tile = { part: MeshPart, lod: string, base: CFrame?, half: number? }
type Field = { part: BasePart, active: boolean, tiles: { [number]: Tile } }

local templates: { [string]: MeshPart } = {}
local pools: { [string]: { MeshPart } } = { hi = {}, lo = {} }
local fields: { [BasePart]: Field } = {}
local stats = { hi = 0, lo = 0 }

local function take(lod: string): MeshPart?
	local list = pools[lod]
	local p = table.remove(list)
	if p then
		return p
	end
	local tpl = templates[lod]
	if not tpl then
		return nil
	end
	local c = tpl:Clone()
	c.Parent = holder
	return c
end

local function give(t: Tile)
	t.part.CFrame = HIDDEN
	table.insert(pools[t.lod], t.part)
	stats[t.lod] -= 1
end

local function release(f: Field)
	for k, t in f.tiles do
		give(t)
		f.tiles[k] = nil
	end
	f.active = false
	f.part.LocalTransparencyModifier = 0
end

local function update(f: Field, camPos: Vector3, far: number, near: number)
	local part = f.part
	local cf, size = part.CFrame, part.Size
	local lp = cf:PointToObjectSpace(camPos)
	if RiceField.distToRect(lp.X, lp.Z, size.X, size.Z) >= far then
		if f.active then
			release(f)
		end
		return
	end
	local waterY = part:GetAttribute("WaterY")
	local h = part:GetAttribute("H")
	if type(waterY) ~= "number" or type(h) ~= "number" then
		return
	end
	if not f.active then
		f.active = true
		part.LocalTransparencyModifier = 1
	end
	local nx, nz, tw, tz = RiceField.grid(size.X, size.Z)
	local rot = cf.Rotation
	local k = 0
	for i = 0, nx - 1 do
		local lx = -size.X / 2 + (i + 0.5) * tw
		for j = 0, nz - 1 do
			k += 1
			local lz = -size.Z / 2 + (j + 0.5) * tz
			local dx, dz = lp.X - lx, lp.Z - lz
			local lod = if math.sqrt(dx * dx + dz * dz) < near then "hi" else "lo"
			local t = f.tiles[k]
			if not t or t.lod ~= lod then
				if t then
					give(t)
				end
				local p = take(lod)
				if p then
					local tpl = templates[lod]
					local sy = tpl.Size.Y * h
					p.Size = Vector3.new(tpl.Size.X * tw / RiceField.TILE, sy, tpl.Size.Z * tz / RiceField.TILE)
					local w = cf:PointToWorldSpace(Vector3.new(lx, 0, lz))
					local flip = if RiceField.flip(part.Position.X, part.Position.Z, i, j) then math.pi else 0
					local base = CFrame.new(w.X, waterY - RiceField.BASE + sy / 2, w.Z)
						* rot
						* CFrame.Angles(0, flip, 0)
					p.CFrame = base
					f.tiles[k] = { part = p, lod = lod, base = base, half = sy / 2 }
					stats[lod] += 1
				else
					f.tiles[k] = nil
				end
			end
		end
	end
end

local function watch(folder: Instance)
	local function add(c: Instance)
		if c:IsA("BasePart") and not fields[c] then
			fields[c] = { part = c, active = false, tiles = {} }
		end
	end
	for _, c in folder:GetChildren() do
		add(c)
	end
	folder.ChildAdded:Connect(add)
	-- streaming: o tabuleiro que sai do raio devolve os ladrilhos
	folder.ChildRemoved:Connect(function(c: Instance)
		if c:IsA("BasePart") then
			local f = fields[c]
			if f then
				release(f)
				fields[c] = nil
			end
		end
	end)
end

-- chama das lamparinas: tremor leve só nas que estão perto (custo zero longe)
local function flicker(now: number, camPos: Vector3)
	for _, flame in CollectionService:GetTagged("VT65Lamp") do
		if flame:IsA("BasePart") and (flame.Position - camPos).Magnitude < 90 then
			local light = flame:FindFirstChildOfClass("PointLight")
			if light then
				local s = flame.Position.X * 0.37 + flame.Position.Z * 0.11
				light.Brightness = 0.95 + 0.18 * math.sin(now * 9.1 + s) + 0.1 * math.sin(now * 23.7 + s * 2)
			end
		end
	end
end

-- D-80 tinha o arroz de perto balançando com o vento (15 vezes por segundo, ladrilho por ladrilho).
-- 2026-11-13: sem vento no jogo (pedido do dono: "retire o vento, está pesando demais"); o arroz
-- fica parado e o laço saiu.

task.spawn(function()
	if art and map then
		for _, lod in { "hi", "lo" } do
			local t = art:WaitForChild(lod, 60)
			if t and t:IsA("MeshPart") then
				templates[lod] = t
			end
		end
		local folder = map:WaitForChild("Arrozal", 900)
		if folder then
			watch(folder)
		end
	end
	local lastPos = Vector3.new(math.huge, 0, 0)
	local lastFull = 0
	while true do
		local now = os.clock()
		local camPos = camera.CFrame.Position
		-- passo completo quando a câmera anda 6 studs ou a cada 1 s (tabuleiro que chegou pelo streaming)
		if (camPos - lastPos).Magnitude > 6 or now - lastFull > 1 then
			lastPos, lastFull = camPos, now
			local far, near = ranges()
			for _, f in fields do
				if f.part.Parent then
					update(f, camPos, far, near)
				end
			end
			holder:SetAttribute("Ladrilhos", stats.hi + stats.lo)
			holder:SetAttribute("Perto", stats.hi)
		end
		flicker(now, camPos)
		task.wait(0.1)
	end
end)
