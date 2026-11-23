--!strict
-- D-254 (prompt V5, §19): monta a área piloto do Objetivo C depois da arte do mapa e antes dos lampiões.
-- Os dados e as regras ficam em Shared/VilaPiloto. Reaproveita o mesmo MeshId por chave (instancing).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local VilaPiloto = require(ReplicatedStorage.Shared.VilaPiloto)

local VilaPilotoService = {}
local M = MapConfig.STUD_M

-- o que pode sair de baixo de uma construção nova (nunca o que tem regra de jogo, como a toca do VC)
local REMOVIVEL = {
	coconut_palm = true,
	banana = true,
	shrub = true,
	granary = true,
	hut_kitchen = true,
	water_jar = true,
	bamboo_clothesline = true,
	straw_stack = true,
	bamboo_fence = true,
	ph_island_tree_01 = true,
	ph_island_tree_02 = true,
	ph_island_tree_03 = true,
	elephant_grass = true,
	bamboo_clump = true,
} :: { [string]: boolean }

function VilaPilotoService.ativa(): boolean
	if VilaPiloto.LIGADA then
		return true
	end
	return RunService:IsStudio() and workspace:GetAttribute("VT65DevPiloto") == true
end

function VilaPilotoService.centro(): (number?, number?)
	for _, sp in MapConfig.Strongpoints do
		if sp.name == VilaPiloto.SETOR then
			return sp.x, sp.z
		end
	end
	return nil, nil
end

local function chao(x: number, z: number): number?
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { workspace.Terrain }
	local r = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), p)
	return if r then r.Position.Y else nil
end

-- marca do chão: acompanha a inclinação do terreno e fica 3 cm acima dele
local function assenta(x: number, z: number, yaw: number): CFrame?
	local d = 1.3 / M
	local y0, y1, y2 = chao(x - d, z - d), chao(x + d, z - d), chao(x, z + d)
	if not (y0 and y1 and y2) then
		return nil
	end
	local a = Vector3.new(x - d, y0, z - d)
	local n = (Vector3.new(x, y2, z + d) - a):Cross(Vector3.new(x + d, y1, z - d) - a).Unit
	if n.Y < 0 then
		n = -n
	end
	local centro = chao(x, z) or (y0 + y1 + y2) / 3
	local frente = CFrame.Angles(0, yaw, 0).LookVector
	local direita = frente:Cross(n).Unit
	local f = n:Cross(direita).Unit
	return CFrame.fromMatrix(Vector3.new(x, centro + 0.03 / M, z), direita, n, -f)
end

-- O alfa parcial da SurfaceAppearance sai cortado no jogo; marca de borda suave precisa de Decal.
-- `desce` separa as camadas: trilha, depois a terra molhada, e a água da poça por cima.
local DECAIS: { [string]: { larg: number, prof: number, desce: number, transp: number? } } = {
	poca_halo = { larg = 5.0, prof = 4.0, desce = 0.012 },
	trilha = { larg = 6.0, prof = 3.4, desce = 0.024, transp = 0.32 },
}

local function marcaDecal(nome: string, cf: CFrame, escala: number?, ordem: number, pai: Instance): boolean
	local info = DECAIS[nome]
	local id = AssetIds.ChaoVila and AssetIds.ChaoVila[nome]
	if not info or not id or id == 0 then
		return false
	end
	local e = escala or 1
	local base = Instance.new("Part")
	base.Name = "VilaMarca_" .. nome
	base.Anchored = true
	base.CanCollide, base.CanQuery, base.CanTouch, base.CastShadow = false, false, false, false
	base.Transparency = 1
	base.Size = Vector3.new(info.larg / M * e, 0.05, info.prof / M * e)
	base.CFrame = cf * CFrame.new(0, -0.025 - info.desce - (ordem % 2) * 0.004, 0)
	local d = Instance.new("Decal")
	d.Face = Enum.NormalId.Top
	d.Transparency = info.transp or 0
	d.Texture = "rbxassetid://" .. tostring(id)
	d.Parent = base
	base.Parent = pai
	return true
end

local function acha(lista: { Instance }, key: string, x: number, z: number): Model?
	local melhor: Model? = nil
	local dist = 1.5 / M
	for _, c in lista do
		if c.Name == key and c:IsA("Model") then
			local q = c:GetPivot().Position
			local d = math.sqrt((q.X - x) ^ 2 + (q.Z - z) ^ 2)
			if d < dist then
				melhor, dist = c, d
			end
		end
	end
	return melhor
end

-- tira o que ficou embaixo da construção nova
local CASA_COM_JANELA = {
	ret_vila_palafita_a = true,
	ret_vila_palafita_b = true,
	ret_vila_terra = true,
	ret_vila_dinh = true,
} :: { [string]: boolean }

local function limpa(pastas: { Instance }, m: Model): number
	local cf, tam = m:GetBoundingBox()
	local n = 0
	for _, pasta in pastas do
		for _, c in pasta:GetChildren() do
			if c ~= m and c:IsA("Model") and REMOVIVEL[c.Name] then
				local l = cf:PointToObjectSpace(c:GetPivot().Position)
				if math.abs(l.X) < tam.X / 2 + 0.6 / M and math.abs(l.Z) < tam.Z / 2 + 0.6 / M then
					c:Destroy()
					n += 1
				end
			end
		end
	end
	return n
end

function VilaPilotoService.montar(map: Instance, loader: any)
	local cx, cz = VilaPilotoService.centro()
	local art = map:FindFirstChild("Art")
	if not (cx and cz and art) then
		warn("[VT65] piloto da vila: sem o objetivo ou sem a arte")
		return
	end
	local mata = art:FindFirstChild("Jungle")
	local pastas: { Instance } = if mata then { art, mata } else { art }
	local filhos = art:GetChildren()
	local trocadas, faltam, tirados = 0, 0, 0

	for _, t in VilaPiloto.TROCAS do
		local x, z = cx + t.x / M, cz + t.z / M
		local velho = acha(filhos, t.de, x, z)
		if not velho then
			faltam += 1
			warn("[VT65] piloto da vila: não achei", t.de, t.x, t.z)
			continue
		end
		local piv = velho:GetPivot()
		local _, giro = piv:ToOrientation()
		local p = piv.Position
		velho:Destroy()
		local y = chao(p.X, p.Z) or p.Y
		local novo = loader.placeAt(t.para, CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, giro, 0), art)
		if novo then
			trocadas += 1
			tirados += limpa(pastas, novo)
		else
			faltam += 1
			warn("[VT65] piloto da vila: modelo sem ID", t.para)
		end
	end

	-- os potes estavam sobre o piso da casa antiga: descem para o chão
	for _, c in art:GetChildren() do
		if c.Name == "water_jar" and c:IsA("Model") then
			local piv = c:GetPivot()
			local q = piv.Position
			if math.sqrt((q.X - cx) ^ 2 + (q.Z - cz) ^ 2) * M < VilaPiloto.RAIO_M then
				local y = chao(q.X, q.Z)
				if y then
					local box, tam = c:GetBoundingBox()
					c:PivotTo(piv + Vector3.new(0, y - (box.Y - tam.Y / 2), 0))
				end
			end
		end
	end

	-- as cercas pesadas viram o trecho leve, no mesmo lugar (o comprido é o eixo Z da antiga e o X da nova)
	local cercas = 0
	for _, c in art:GetChildren() do
		if c.Name == "bamboo_fence" and c:IsA("Model") then
			local piv = c:GetPivot()
			local q = piv.Position
			if math.sqrt((q.X - cx) ^ 2 + (q.Z - cz) ^ 2) * M < VilaPiloto.RAIO_CERCA_M then
				local _, giro = piv:ToOrientation()
				local y = chao(q.X, q.Z) or q.Y
				local cf = CFrame.new(q.X, y, q.Z) * CFrame.Angles(0, giro + math.pi / 2, 0)
				if loader.placeAt("ret_vila_cerca", cf, art) then
					c:Destroy()
					cercas += 1
				end
			end
		end
	end

	local postas = 0
	local todas: { VilaPiloto.Peca } = table.clone(VilaPiloto.PECAS)
	for _, q in VilaPiloto.marcas() do
		table.insert(todas, q)
	end
	for _, p in todas do
		local x, z = cx + p.x / M, cz + p.z / M
		local yaw = math.rad(p.giro)
		local m: Model?
		if p.planta then
			m = loader.place(p.key, x, z, yaw, art, true, p.escala, false)
		else
			local cf: CFrame?
			if p.plano then
				cf = assenta(x, z, yaw)
			else
				local y = chao(x, z)
				cf = if y then CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) else nil
			end
			if cf then
				if p.decal and marcaDecal(p.decal, cf, p.escala, postas, art) and p.soDecal then
					postas += 1
					continue
				end
				m = loader.placeAt(p.key, cf, art, p.escala)
			end
		end
		if m then
			postas += 1
			if p.plano then
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
					end
				end
			elseif not p.planta then
				tirados += limpa(pastas, m)
			end
		else
			faltam += 1
		end
	end
	-- copa que atravessa a parede deixa a janela preta: afasta a árvore só o necessário
	local casas: { { cf: CFrame, tam: Vector3 } } = {}
	for _, c in art:GetChildren() do
		if c:IsA("Model") and CASA_COM_JANELA[c.Name] then
			local f, s = c:GetBoundingBox()
			table.insert(casas, { cf = f, tam = s })
		end
	end
	local afastadas = 0
	for _, c in art:GetChildren() do
		if c:IsA("Model") and string.sub(c.Name, 1, 14) == "ph_island_tree" then
			local _, copa = c:GetBoundingBox()
			local raio = math.max(copa.X, copa.Z) / 2 * 1.1
			local moveu = false
			for _ = 1, 3 do
				local q = c:GetPivot().Position
				local falta, dir = 0, nil :: Vector3?
				for _, b in casas do
					local l = b.cf:PointToObjectSpace(q)
					local ex = math.max(math.abs(l.X) - b.tam.X / 2, 0)
					local ez = math.max(math.abs(l.Z) - b.tam.Z / 2, 0)
					local d = math.sqrt(ex * ex + ez * ez)
					if raio - d > falta then
						falta = raio - d
						local v = Vector3.new(q.X - b.cf.Position.X, 0, q.Z - b.cf.Position.Z)
						dir = if v.Magnitude > 0.01 then v.Unit else Vector3.xAxis
					end
				end
				if not dir then
					break
				end
				local novo = q + dir * (falta + 0.3 / M)
				local y0, y1 = chao(q.X, q.Z), chao(novo.X, novo.Z)
				local dy = if y0 and y1 then y1 - y0 else 0
				c:PivotTo(c:GetPivot() + Vector3.new(novo.X - q.X, dy, novo.Z - q.Z))
				moveu = true
			end
			if moveu then
				afastadas += 1
			end
		end
	end
	-- as cercas ao longo das vias, em trechos de 4 m; o trecho que bateria numa construção fica de fora
	local caixas: { { cf: CFrame, tam: Vector3 } } = {}
	for _, c in art:GetChildren() do
		if
			c:IsA("Model")
			and string.sub(c.Name, 1, 4) == "ret_"
			and c.Name ~= "ret_vila_poca"
			and c.Name ~= "ret_vila_cerca"
		then
			local f, s = c:GetBoundingBox()
			table.insert(caixas, { cf = f, tam = s })
		end
	end
	local function livre(q: Vector3): boolean
		for _, b in caixas do
			local l = b.cf:PointToObjectSpace(q)
			if math.abs(l.X) < b.tam.X / 2 + 0.4 / M and math.abs(l.Z) < b.tam.Z / 2 + 0.4 / M then
				return false
			end
		end
		return true
	end
	for _, s in VilaPiloto.CERCAS do
		local ux, uz = s[3] - s[1], s[4] - s[2]
		local comp = math.sqrt(ux * ux + uz * uz)
		local n = math.max(1, math.floor(comp / 4))
		local yaw = math.atan2(-uz, ux)
		for k = 0, n - 1 do
			local f = (k + 0.5) / n
			local x, z = cx + (s[1] + ux * f) / M, cz + (s[2] + uz * f) / M
			local meia = Vector3.new(ux / comp * 2 / M, 0, uz / comp * 2 / M)
			local q = Vector3.new(x, 50, z)
			local y = chao(x, z)
			if y then
				q = Vector3.new(x, y, z)
			end
			if y and livre(q) and livre(q + meia) and livre(q - meia) then
				if loader.placeAt("ret_vila_cerca", CFrame.new(q) * CFrame.Angles(0, yaw, 0), art) then
					cercas += 1
				end
			end
		end
	end
	-- capim parado nos quintais: só onde o terreno é capim e fora das construções
	local capim = 0
	local soTerreno = RaycastParams.new()
	soTerreno.FilterType = Enum.RaycastFilterType.Include
	soTerreno.FilterDescendantsInstances = { workspace.Terrain }
	for _, q in VilaPiloto.capimPontos() do
		if capim >= VilaPiloto.MAX_CAPIM then
			break
		end
		local x, z = cx + q.x / M, cz + q.z / M
		local r = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), soTerreno)
		local mat = r and r.Material
		if r and (mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass) and livre(r.Position) then
			local m = loader.place("ret_vila_capim", x, z, math.rad(q.giro), art, true, q.escala, false)
			if m then
				capim += 1
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
					end
				end
				if capim % 80 == 0 then
					task.wait()
				end
			end
		end
	end
	print(
		string.format(
			"[VT65] piloto da vila (D-254): %d trocas, %d cercas, %d capim, %d árvores afastadas, %d peças, %d objetos tirados, %d falhas",
			trocadas,
			cercas,
			capim,
			afastadas,
			postas,
			tirados,
			faltam
		)
	)
end

return VilaPilotoService
