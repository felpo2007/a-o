--!strict
-- D-254 (prompt V5, §19): monta a área piloto do Objetivo C depois da arte do mapa e antes dos lampiões.
-- Os dados e as regras ficam em Shared/VilaPiloto. Reaproveita o mesmo MeshId por chave (instancing).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local VilaPiloto = require(ReplicatedStorage.Shared.VilaPiloto)
local TrunkProxy = require(script.Parent.TrunkProxy)
local TroncosPov = require(script.Parent.TroncosPov) :: any

local VilaPilotoService = {}
local M = MapConfig.STUD_M

-- o que sai do setor: casas antigas, objetos soltos e a vegetação, que volta pela planta. Nunca o que tem
-- regra de jogo, como a toca do VC, a bandeira e os túneis.
local SAI = {
	hut_kitchen = true,
	hut_thatch = true,
	hut_veranda = true,
	house_tile = true,
	granary = true,
	bamboo_clothesline = true,
	straw_stack = true,
	water_jar = true,
	bamboo_fence = true,
	well = true,
	Vila_horta = true,
	Vila_banca = true,
	Vila_chua = true,
	Vila_dinh = true,
	coconut_palm = true,
	banana = true,
	shrub = true,
	elephant_grass = true,
	bamboo_clump = true,
	canopy_tree = true,
	ph_island_tree_01 = true,
	ph_island_tree_02 = true,
	ph_island_tree_03 = true,
	exp_samambaia = true,
	exp_arvore_a = true,
	exp_arvore_b = true,
} :: { [string]: boolean }
-- árvores fazem sombra; o resto da folhagem não paga esse custo
local COM_SOMBRA = {
	ret_pov_p_coqueiro_a = true,
	ret_pov_p_coqueiro_b = true,
	ret_pov_p_arvore_a = true,
	ret_pov_p_arvore_b = true,
	bamboo_clump = true,
} :: { [string]: boolean }
-- SurfaceAppearance.Color em cartão recortado por alfa deixa manchas pretas (Studio, lote 122):
-- a cor da folhagem vem da textura. Aqui só entra o que não tem alfa.
local TOM_PAREDE = {
	ret_pov_laterita = Color3.fromRGB(164, 178, 182),
	ret_pov_patio = Color3.fromRGB(164, 178, 182),
	ret_pov_d_muro = Color3.fromRGB(164, 178, 182),
} :: { [string]: Color3 }
-- a telha nova fica vermelha demais: envelhece para o marrom da referência
local TOM_TELHA = Color3.fromRGB(176, 192, 198)
local COM_TELHA = {
	ret_pov_chua = true,
	ret_pov_medico = true,
	ret_pov_laterita = true,
	ret_pov_pho = true,
	ret_pov_patio = true,
	ret_merc_oficina = true,
	vila_casa_03 = true,
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
	local d = 2.0 / M
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
	return CFrame.fromMatrix(Vector3.new(x, centro + 0.05 / M, z), direita, n, -f)
end

-- O alfa parcial da SurfaceAppearance sai cortado no jogo; marca de borda suave precisa de Decal.
-- `desce` separa as camadas: trilha, depois a terra molhada, e a água da poça por cima.
local DECAIS: { [string]: { larg: number, prof: number, desce: number, transp: number? } } = {
	poca_halo = { larg = 5.0, prof = 4.0, desce = 0.012, transp = 0.38 },
	trilha = { larg = 6.0, prof = 3.4, desce = 0.024, transp = 0.64 },
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

-- o pé reto dos cartões de capim fica dentro da terra
local function enterra(m: Model)
	m:PivotTo(m:GetPivot() * CFrame.new(0, -0.16 / M, 0))
end

local UMA_FACE = {
	"ret_pov_p_coqueiro_a",
	"ret_pov_p_coqueiro_b",
	"ret_pov_p_arvore_a",
	"ret_pov_p_arvore_b",
	"ret_pov_p_arbusto_a",
	"ret_pov_p_arbusto_b",
}

local function semColisao(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = false, false, false, false
		end
	end
end

local function tingirParede(m: Model, cor: Color3)
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceAppearance") and d.Parent and d.Parent.Name == "Paredes" then
			d.Color = cor
		end
	end
end

-- os canteiros da horta saem muito saturados na luz da manhã
local TOM_HORTA = Color3.fromRGB(152, 150, 124)
local function tingirHorta(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceAppearance") and d.Parent and d.Parent.Name == "Mobilia" then
			d.Color = TOM_HORTA
		end
	end
end

local function tingirTelhado(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceAppearance") and d.Parent and string.sub(d.Parent.Name, 1, 7) == "Telhado" then
			d.Color = TOM_TELHA
		end
	end
end

-- o tronco invisível que para a bala e o soldado (a copa não colide)
local function poeTronco(m: Model, key: string, loader: any)
	local cilindros = TroncosPov[key]
	if not cilindros then
		return
	end
	loader.ensureGroups()
	local cf, tam = m:GetBoundingBox()
	local pe = cf * CFrame.new(0, -tam.Y / 2, 0)
	for i, c in cilindros do
		local rel, s = TrunkProxy.frame(c, m:GetScale())
		local p = Instance.new("Part")
		p.Name = TrunkProxy.PREFIX .. i
		p.Shape = Enum.PartType.Cylinder
		p.Size = s
		p.CFrame = pe * rel
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide, p.CanQuery = true, true
		p.CanTouch, p.CastShadow = false, false
		p.CollisionGroup = loader.TRUNK_GROUP
		p:SetAttribute("Material", "Wood")
		p.Parent = m
	end
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
	local feitas, faltam, tirados, postas = 0, 0, 0, 0

	-- 1. o setor fica limpo: só sai o que a planta substitui
	for _, pasta in pastas do
		for _, c in pasta:GetChildren() do
			if c:IsA("Model") and (SAI[c.Name] or string.sub(c.Name, 1, 10) == "vila_casa_") then
				local q = c:GetPivot().Position
				if VilaPiloto.noSetor((q.X - cx) * M, (q.Z - cz) * M, 1) then
					c:Destroy()
					tirados += 1
				end
			end
		end
	end
	-- as plantas novas já trazem as faces de que precisam:
	-- DoubleSided usa a normal da frente nos dois lados e a folha contra o sol estoura em branco
	for _, key in UMA_FACE do
		local tpl = loader.template(key)
		if tpl then
			for _, d in tpl:GetDescendants() do
				if d:IsA("MeshPart") and string.sub(d.Name, 1, 6) == "Folhas" then
					d.DoubleSided = false
				end
			end
		end
	end
	-- os coqueiros antigos da beirada do setor viram os novos, no mesmo lugar: sem isso a copa
	-- amarela e grossa aparece atrás das casas
	local trocados = 0
	if mata or art then
		for _, pasta in pastas do
			for _, c in pasta:GetChildren() do
				if c:IsA("Model") and c.Name == "coconut_palm" then
					local q = c:GetPivot().Position
					local px, pz = (q.X - cx) * M, (q.Z - cz) * M
					if VilaPiloto.noSetor(px, pz, 34) then
						local key = if trocados % 2 == 0 then "ret_pov_p_coqueiro_a" else "ret_pov_p_coqueiro_b"
						c:Destroy()
						local m = loader.place(key, q.X, q.Z, math.rad(trocados * 137 % 360), art, true, 1, true)
						if m then
							poeTronco(m, key, loader)
							trocados += 1
						end
					end
				end
			end
		end
	end
	-- 2. as construções, cada uma no seu patamar de terra
	for k, c in VilaPiloto.POVOADO do
		loader.comPatamar(c.key)
		local casa = loader.place(c.key, cx + c.x / M, cz + c.z / M, math.rad(c.giro), art)
		if casa then
			feitas += 1
			if COM_TELHA[c.key] then
				tingirTelhado(casa)
			end
			if TOM_PAREDE[c.key] then
				tingirParede(casa, TOM_PAREDE[c.key])
			end
		else
			faltam += 1
			warn("[VT65] povoado: modelo sem ID", c.key, c.nome)
		end
		if k % 6 == 0 then
			task.wait()
		end
	end
	-- 3. a passarela da lagoa fica na altura da água, sem aterro
	for _, c in VilaPiloto.PASSARELAS do
		local x, z = cx + c.x / M, cz + c.z / M
		local y = chao(x, z)
		if y and loader.placeAt(c.key, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(c.giro), 0), art) then
			postas += 1
		else
			faltam += 1
		end
	end
	-- 4. entrada, cobertura do cruzamento, lama e marcas de roda
	local todas: { VilaPiloto.Peca } = table.clone(VilaPiloto.PECAS)
	for _, q in VilaPiloto.marcas() do
		table.insert(todas, q)
	end
	for _, p in todas do
		if VilaPiloto.sobConstrucao(p.x, p.z, 0.2) then
			continue
		end
		local x, z = cx + p.x / M, cz + p.z / M
		local yaw = math.rad(p.giro)
		local cf: CFrame?
		if p.plano then
			cf = assenta(x, z, yaw)
		else
			local y = chao(x, z)
			cf = if y then CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) else nil
		end
		if not cf then
			faltam += 1
			continue
		end
		if p.decal and marcaDecal(p.decal, cf, p.escala, postas, art) and p.soDecal then
			postas += 1
			continue
		end
		local m = loader.placeAt(p.key, cf, art, p.escala)
		if m then
			postas += 1
			if p.plano then
				semColisao(m)
			end
		else
			faltam += 1
		end
	end
	task.wait()
	-- 5. os objetos de cena dos quintais e das ruas
	for k, c in VilaPiloto.CENA do
		local obj = loader.place(c.key, cx + c.x / M, cz + c.z / M, math.rad(c.giro), art)
		if obj then
			postas += 1
			if TOM_PAREDE[c.key] then
				tingirParede(obj, TOM_PAREDE[c.key])
			end
			if c.key == "ret_pov_d_horta" then
				tingirHorta(obj)
			end
		else
			faltam += 1
			warn("[VT65] povoado: cena sem ID", c.key)
		end
		if k % 20 == 0 then
			task.wait()
		end
	end
	-- 6. cercas de bambu e muros de laterita
	local cercas = 0
	for _, c in VilaPiloto.CERCAS do
		local x, z = cx + c.x / M, cz + c.z / M
		local y = chao(x, z)
		if y and loader.placeAt(c.key, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(c.giro), 0), art) then
			cercas += 1
		else
			faltam += 1
		end
	end
	-- 7. a vegetação, em quatro alturas, parada
	local plantas = 0
	for k, c in VilaPiloto.PLANTAS do
		local m = loader.place(
			c.key,
			cx + c.x / M,
			cz + c.z / M,
			math.rad(c.giro),
			art,
			true,
			c.escala,
			COM_SOMBRA[c.key] == true
		)
		if m then
			plantas += 1
			poeTronco(m, c.key, loader)
		else
			faltam += 1
		end
		if k % 25 == 0 then
			task.wait()
		end
	end
	-- 8. capim parado nos quintais: só onde o terreno é capim
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
		if r and (mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass) then
			local m = loader.place("ret_vila_capim", x, z, math.rad(q.giro), art, true, q.escala, false)
			if m then
				capim += 1
				semColisao(m)
				enterra(m)
				if capim % 80 == 0 then
					task.wait()
				end
			end
		end
	end
	-- 9. a beira das ruas: capim baixo e pedras soltas
	for k, q in VilaPiloto.bordaPontos() do
		if q.key == "ret_vila_capim" then
			-- tufo solto na terra batida parece um recorte: só nasce onde o chão já é capim
			local h =
				workspace:Raycast(Vector3.new(cx + q.x / M, 400, cz + q.z / M), Vector3.new(0, -600, 0), soTerreno)
			if not (h and h.Material == Enum.Material.Grass) then
				continue
			end
		end
		local m = loader.place(q.key, cx + q.x / M, cz + q.z / M, math.rad(q.giro), art, true, q.escala, false)
		if m then
			capim += 1
			semColisao(m)
			if q.key == "ret_vila_capim" then
				enterra(m)
			end
		end
		if k % 40 == 0 then
			task.wait()
		end
	end
	print(
		string.format(
			"[VT65] setor piloto da vila (D-255): %d construções, %d cercas, %d plantas, %d capim, %d peças, %d objetos tirados, %d falhas",
			feitas,
			cercas,
			plantas,
			capim,
			postas,
			tirados,
			faltam
		)
	)
end

return VilaPilotoService
