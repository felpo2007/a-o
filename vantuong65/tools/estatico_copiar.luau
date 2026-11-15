--!nocheck
-- D-155: copia do jogo rodando (servidor, Studio pelo MCP) um conjunto de arte já posto pelo
-- AssetLoader (assentado, tingido e com o MapLife aplicado) para virar modelo fixo do place (SLIM).
-- Rode com o `execute_luau` no Server, com a arte posta (Map.Art com o atributo Placed). Devolve um
-- texto compacto (o assistente do Studio não deixa mandar por HTTP); grave-o em
-- assets/estatico/<conjunto>.txt e rode o tools/estatico.py.
-- O conjunto: o modelo da chave CHAVE mais perto do CENTRO e os objetos que não são planta a até
-- RAIO_M dele.
-- Formato (uma linha por coisa; números em studs, graus no giro em Y):
--   M <chave> <x> <y> <z> <giro> <escala>          modelo de primeiro nível (pivô)
--   N <a/b/c>                                       submodelo pelo caminho (as peças seguintes ficam nele)
--   P <nome> <malha> <x> <y> <z> <giro> <sx> <sy> <sz> <marcas> <Material|->
--      marcas: c CanCollide, q CanQuery, s CastShadow, t Transparency 1, h CanTouch
--   S <cor> <normal> <rugosidade> <metal> <AlphaMode> <r,g,b>   SurfaceAppearance da última peça
--   C <r,g,b>                                       cor da última peça (só se fugir do padrão)
--   B <classe> <forma|-> <nome> <x> <y> <z> <R00..R22> <sx> <sy> <sz> <marcas> <Material|-> <material> <r,g,b>
--      D-168: peça comum (Part, WedgePart, CornerWedgePart) das construções de peças do MapLife,
--      com o CFrame inteiro (há peças inclinadas), o material do Roblox e a cor
--   X <texto>                                       algo fora do previsto (o estatico.py recusa)
local CHAVE = "vila_casa_03"
local CENTRO = Vector3.new(-1280.5, 0, -1804.7)
local RAIO_M = 10
local M = 0.28
local COR_PADRAO = Color3.fromRGB(163, 162, 165)

local linhas = {}
local function f(n: number): string
	return string.format("%.3f", n)
end
local function giro(c: CFrame): number
	local look = c.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end
local function rgb(c: Color3): string
	return string.format("%.4f,%.4f,%.4f", c.R, c.G, c.B)
end
local function id(s: string): string
	return (string.gsub(s, "^rbxassetid://", ""))
end

local function marcasDe(p: BasePart): string
	local marcas = (if p.CanCollide then "c" else "")
		.. (if p.CanQuery then "q" else "")
		.. (if p.CastShadow then "s" else "")
		.. (if p.Transparency >= 1 then "t" else "")
		.. (if p.CanTouch then "h" else "")
	return if marcas == "" then "-" else marcas
end

-- D-168: peça comum, com o CFrame inteiro
local function bloco(p: BasePart)
	if string.find(p.Name, "%s") then
		table.insert(linhas, "X nome com espaço " .. p:GetFullName())
	end
	if p.Transparency > 0 and p.Transparency < 1 then
		table.insert(linhas, "X transparência " .. p.Transparency .. " " .. p:GetFullName())
	end
	for k, v in
		{
			Reflectance = p.Reflectance ~= 0,
			Anchored = not p.Anchored,
			Massless = p.Massless,
			CollisionGroup = p.CollisionGroup ~= "Default",
			MaterialVariant = p.MaterialVariant ~= "",
			TopSurface = p.TopSurface ~= Enum.SurfaceType.Smooth,
			BottomSurface = p.BottomSurface ~= Enum.SurfaceType.Smooth,
		}
	do
		if v then
			table.insert(linhas, "X " .. k .. " fora do padrão em " .. p:GetFullName())
		end
	end
	for k in p:GetAttributes() do
		if k ~= "Material" then
			table.insert(linhas, "X atributo " .. k .. " em " .. p:GetFullName())
		end
	end
	for _, c in p:GetChildren() do
		table.insert(linhas, "X filho " .. c.ClassName .. " em " .. p:GetFullName())
	end
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local rot = {}
	for _, r in { r00, r01, r02, r10, r11, r12, r20, r21, r22 } do
		table.insert(rot, string.format("%.6f", r))
	end
	local s = p.Size
	table.insert(
		linhas,
		table.concat({
			"B",
			p.ClassName,
			if p:IsA("Part") then (p :: Part).Shape.Name else "-",
			p.Name,
			f(x),
			f(y),
			f(z),
			table.concat(rot, " "),
			f(s.X),
			f(s.Y),
			f(s.Z),
			marcasDe(p),
			tostring(p:GetAttribute("Material") or "-"),
			p.Material.Name,
			rgb(p.Color),
		}, " ")
	)
end

local function peca(p: BasePart)
	if p:IsA("Part") or p:IsA("WedgePart") or p:IsA("CornerWedgePart") then
		bloco(p)
		return
	end
	if not p:IsA("MeshPart") then
		table.insert(linhas, "X peça " .. p.ClassName .. " " .. p:GetFullName())
		return
	end
	if math.abs(p.CFrame.UpVector.Y - 1) > 1e-4 then
		table.insert(linhas, "X peça inclinada " .. p:GetFullName())
	end
	local marcas = (if p.CanCollide then "c" else "")
		.. (if p.CanQuery then "q" else "")
		.. (if p.CastShadow then "s" else "")
		.. (if p.Transparency >= 1 then "t" else "")
		.. (if p.CanTouch then "h" else "")
	if p.Transparency > 0 and p.Transparency < 1 then
		table.insert(linhas, "X transparência " .. p.Transparency .. " " .. p:GetFullName())
	end
	for k, v in
		{
			Material = p.Material ~= Enum.Material.Plastic,
			Reflectance = p.Reflectance ~= 0,
			Anchored = not p.Anchored,
			Massless = p.Massless,
			CollisionGroup = p.CollisionGroup ~= "Default",
			MaterialVariant = p.MaterialVariant ~= "",
			TextureID = p.TextureID ~= "",
			DoubleSided = p.DoubleSided,
			RenderFidelity = p.RenderFidelity ~= Enum.RenderFidelity.Automatic,
		}
	do
		if v then
			table.insert(linhas, "X " .. k .. " fora do padrão em " .. p:GetFullName())
		end
	end
	for k in p:GetAttributes() do
		if k ~= "Material" then
			table.insert(linhas, "X atributo " .. k .. " em " .. p:GetFullName())
		end
	end
	local pos, s = p.Position, p.Size
	table.insert(
		linhas,
		table.concat({
			"P",
			p.Name,
			id(p.MeshId),
			f(pos.X),
			f(pos.Y),
			f(pos.Z),
			f(giro(p.CFrame)),
			f(s.X),
			f(s.Y),
			f(s.Z),
			if marcas == "" then "-" else marcas,
			tostring(p:GetAttribute("Material") or "-"),
		}, " ")
	)
	if p.Color ~= COR_PADRAO then
		table.insert(linhas, "C " .. rgb(p.Color))
	end
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") then
			table.insert(
				linhas,
				table.concat({
					"S",
					id(c.ColorMap),
					id(c.NormalMap),
					id(c.RoughnessMap),
					id(c.MetalnessMap),
					c.AlphaMode.Name,
					rgb((c :: any).Color),
				}, " ")
			)
		else
			table.insert(linhas, "X filho " .. c.ClassName .. " em " .. p:GetFullName())
		end
	end
end

-- submodelos em qualquer profundidade: "N a/b/c" (caminho a partir do modelo de cima)
local function no(m: Instance, caminho: string)
	for _, c in m:GetChildren() do
		if c:IsA("BasePart") then
			peca(c)
		elseif not c:IsA("Model") then
			table.insert(linhas, "X filho " .. c.ClassName .. " em " .. c:GetFullName())
		end
	end
	for _, c in m:GetChildren() do
		if c:IsA("Model") then
			local sub = if caminho == "" then c.Name else caminho .. "/" .. c.Name
			table.insert(linhas, "N " .. sub)
			no(c, sub)
		end
	end
end

local art = workspace.Map.Art
local casa, melhor = nil, math.huge
for _, m in art:GetChildren() do
	if m:IsA("Model") and m.Name == CHAVE then
		local p = m:GetPivot().Position
		local d = (Vector3.new(p.X, 0, p.Z) - CENTRO).Magnitude
		if d < melhor then
			casa, melhor = m, d
		end
	end
end
assert(casa, "sem " .. CHAVE)
local c0 = casa:GetPivot().Position
for _, m in art:GetChildren() do
	if m:IsA("Model") and not m:GetAttribute("Foliage") then
		local pv = m:GetPivot()
		if Vector3.new(pv.X - c0.X, 0, pv.Z - c0.Z).Magnitude * M <= RAIO_M then
			table.insert(
				linhas,
				table.concat({ "M", m.Name, f(pv.X), f(pv.Y), f(pv.Z), f(giro(pv)), f(m:GetScale()) }, " ")
			)
			no(m, "")
		end
	end
end
return table.concat(linhas, "\n")
