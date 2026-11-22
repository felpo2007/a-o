--!strict
-- D-241: um lampião aceso pendurado no teto de cada casa da vila, e o globo nos lampiões da expansão
-- (que já tinham a luz, D-232, mas nenhum objeto que a explicasse). A peça não colide, não recebe tiro
-- e não faz sombra. Fica numa pasta própria (Map.LuzInterior): a arte fixa (SLIM) não pode ser mexida.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lampiao = require(ReplicatedStorage.Shared.LampiaoInterior)

local InteriorLuz = {}

local function peca(pai: Instance, nome: string, tam: Vector3, cf: CFrame, cor: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = nome
	p.Size = tam
	p.CFrame = cf
	p.Color = cor
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = pai
	return p
end

local function monta(pasta: Instance, pos: Vector3, tetoY: number, comLuz: boolean, forca: number?)
	local m = Instance.new("Model")
	m.Name = "Lampiao"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local cor = Color3.fromRGB(Lampiao.COR[1], Lampiao.COR[2], Lampiao.COR[3])
	local corGlobo = Color3.fromRGB(Lampiao.COR_GLOBO[1], Lampiao.COR_GLOBO[2], Lampiao.COR_GLOBO[3])
	local ferro = Color3.fromRGB(38, 32, 26)
	local globo = peca(m, "Globo", Vector3.new(0.72, 0.86, 0.72), CFrame.new(pos), corGlobo, Enum.Material.Neon)
	globo.Shape = Enum.PartType.Ball
	globo.Size = Vector3.one * 0.8
	peca(
		m,
		"Tampa",
		Vector3.new(0.86, 0.14, 0.86),
		CFrame.new(pos + Vector3.new(0, 0.46, 0)),
		ferro,
		Enum.Material.Metal
	)
	peca(m, "Base", Vector3.new(0.7, 0.1, 0.7), CFrame.new(pos - Vector3.new(0, 0.44, 0)), ferro, Enum.Material.Metal)
	local topo = pos.Y + 0.53
	local fio = math.max(tetoY - topo, 0.1)
	peca(m, "Arame", Vector3.new(0.06, fio, 0.06), CFrame.new(pos.X, topo + fio / 2, pos.Z), ferro, Enum.Material.Metal)
	if comLuz then
		local luz = Instance.new("PointLight")
		luz.Color = cor
		luz.Brightness = Lampiao.BRILHO * (forca or 1)
		luz.Range = Lampiao.ALCANCE
		luz.Shadows = false
		luz.Parent = globo
	end
	if forca then
		globo:SetAttribute("Forca", forca) -- o InteriorVivo respeita ao animar a chama
	end
	m.PrimaryPart = globo
	CollectionService:AddTag(globo, Lampiao.TAG)
	m.Parent = pasta
end

-- O ponto do lampião numa casa: com piso embaixo, teto em cima e sem parede encostada.
local function ponto(m: Model): (Vector3?, number?)
	local cf, sz = m:GetBoundingBox()
	local base = cf.Position.Y - sz.Y / 2
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { m }
	for _, c in Lampiao.candidatos(4, 2) do
		local q = cf * CFrame.new(c[1], 0, c[2])
		local origem = Vector3.new(q.X, base + 1.5, q.Z)
		local piso = workspace:Raycast(origem, Vector3.new(0, -2.5, 0), rp)
		local cima = workspace:Raycast(origem, Vector3.new(0, sz.Y, 0), rp)
		if piso and cima then
			local teto = cima.Position.Y - piso.Position.Y
			local y = Lampiao.alturaGlobo(teto)
			if y then
				local pos = Vector3.new(q.X, piso.Position.Y + y, q.Z)
				local livre = true
				for _, d in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
					if workspace:Raycast(pos, d * Lampiao.LADO_LIVRE, rp) then
						livre = false
						break
					end
				end
				if livre then
					return pos, cima.Position.Y
				end
			end
		end
	end
	return nil, nil
end

-- D-243: as construções do mercado têm vários cômodos: um lampião a cada tanto, nos pontos cobertos.
local MAX_MERCADO: { [string]: number } = {
	ret_merc_sobrado = 3,
	ret_merc_galeria = 4,
	ret_merc_oficina = 2,
	ret_merc_cozinha = 1,
	ret_merc_fachadas = 3,
	ret_olaria_galpao = 2,
	ret_escola_principal = 3,
	ret_escola_ala = 2,
	ret_engenho_galpao = 6,
	ret_esteio_comunal = 3,
	-- D-251: as cinco cenas do Comboio
	ret_comp_bomba = 1,
	ret_comp_celeiro = 2,
	ret_sino_salao = 3,
	ret_sino_loja_a = 2,
	ret_sino_loja_b = 2,
	ret_canal_oficina = 2,
	ret_serra_galpao = 4,
	ret_esp_armazem = 5,
	ret_esp_chamine = 1,
}
local ENTRE_LAMPIOES = 20 -- studs
local FORCA_MERCADO = 0.42
-- salões de pé-direito alto, sem forro: a luz precisa de mais força para chegar ao chão
local FORCA_MODELO: { [string]: number } = {
	ret_engenho_galpao = 0.62,
	ret_escola_principal = 0.6,
	ret_escola_ala = 0.6,
	ret_esteio_comunal = 0.7,
	ret_olaria_galpao = 0.6,
	ret_comp_celeiro = 0.45,
	ret_sino_salao = 0.45,
	ret_canal_oficina = 0.6,
	ret_serra_galpao = 0.45,
	ret_esp_armazem = 0.6,
}
local LAMPIAO_ALTURA_MAX = 12.5 -- studs do piso: abaixo da linha das treliças

local function pontosMercado(m: Model, maximo: number): { { pos: Vector3, teto: number } }
	local cf, sz = m:GetBoundingBox()
	local base = cf.Position.Y - sz.Y / 2
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { m }
	local cands: { { pos: Vector3, teto: number } } = {}
	for ix = -3, 3 do
		for iz = -3, 3 do
			local q = cf * CFrame.new(ix / 7 * sz.X, 0, iz / 7 * sz.Z)
			-- 1,1 m acima da base: acha também o piso elevado da casa comunal
			local origem = Vector3.new(q.X, base + 4, q.Z)
			local piso = workspace:Raycast(origem, Vector3.new(0, -6, 0), rp)
			local cima = workspace:Raycast(origem, Vector3.new(0, sz.Y, 0), rp)
			-- o térreo das lojas é mais baixo que o das casas (9,6 studs livres): o globo fica junto do teto
			local vao = if piso and cima then cima.Position.Y - piso.Position.Y else 0
			local y = if vao >= 9.6 then math.min(math.max(vao - 1.1, 8.5), LAMPIAO_ALTURA_MAX) else nil
			if piso and cima and y then
				local pos = Vector3.new(q.X, piso.Position.Y + y, q.Z)
				local livre = true
				for _, d in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
					if workspace:Raycast(pos, d * Lampiao.LADO_LIVRE, rp) then
						livre = false
					end
				end
				if livre then
					table.insert(cands, { pos = pos, teto = cima.Position.Y })
				end
			end
		end
	end
	-- espalha: o primeiro fica perto do centro e cada novo, o mais longe possível dos outros
	local out: { { pos: Vector3, teto: number } } = {}
	while #out < maximo do
		local melhor, nota = nil, -math.huge
		for _, c in cands do
			local n = -(c.pos - cf.Position).Magnitude
			if #out > 0 then
				n = math.huge
				for _, o in out do
					n = math.min(n, (o.pos - c.pos).Magnitude)
				end
				if n < ENTRE_LAMPIOES then
					n = -math.huge
				end
			end
			if n > nota then
				melhor, nota = c, n
			end
		end
		if not melhor then
			break
		end
		table.insert(out, melhor)
	end
	return out
end

-- Devolve quantas casas ganharam lampião, quantas ficaram sem lugar e quantos globos a expansão ganhou.
function InteriorLuz.instalar(map: Instance): (number, number, number)
	local pasta = Instance.new("Folder")
	pasta.Name = "LuzInterior"
	local feitas, semLugar, globos = 0, 0, 0
	local vistas: { [string]: boolean } = {}
	for i, d in map:GetDescendants() do
		if d:IsA("Model") and string.match(d.Name, "^vila_casa_%d+$") then
			local p = d:GetPivot().Position
			local chave = string.format("%d:%d", math.round(p.X / 2), math.round(p.Z / 2))
			if not vistas[chave] then
				vistas[chave] = true
				local pos, tetoY = ponto(d)
				if pos and tetoY then
					monta(pasta, pos, tetoY, true)
					feitas += 1
				else
					semLugar += 1
				end
			end
		elseif d:IsA("Model") and MAX_MERCADO[d.Name] then
			local lista = pontosMercado(d, MAX_MERCADO[d.Name])
			for _, q in lista do
				monta(pasta, q.pos, q.teto, true, FORCA_MODELO[d.Name] or FORCA_MERCADO)
			end
			if #lista > 0 then
				feitas += 1
			else
				semLugar += 1
			end
		elseif d:IsA("Attachment") and string.sub(d.Name, 1, 8) == "Lampiao_" then
			-- a luz da expansão continua onde está; o globo sobe para junto do teto do cômodo
			local dono = d:FindFirstAncestorWhichIsA("Model")
			if dono then
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Include
				rp.FilterDescendantsInstances = { dono }
				local w = d.WorldPosition
				local cima = workspace:Raycast(w, Vector3.new(0, 16, 0), rp)
				local tetoY = if cima then cima.Position.Y else w.Y + 2.5
				monta(pasta, Vector3.new(w.X, math.max(w.Y, tetoY - Lampiao.FOLGA_TETO), w.Z), tetoY, false)
				globos += 1
			end
		end
		if i % 4000 == 0 then
			task.wait()
		end
	end
	pasta.Parent = map
	print(
		string.format(
			"[VT65] interiores (D-241): %d casas com lampião, %d sem lugar, %d globos na expansão",
			feitas,
			semLugar,
			globos
		)
	)
	return feitas, semLugar, globos
end

return InteriorLuz
