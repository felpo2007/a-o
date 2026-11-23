--!strict
-- D-243: as travessias dos mapas retangulares, em peças simples (blockout): tabuleiro, guarda-corpo e esteios.
-- A colisão fica aqui mesmo quando o modelo final do Blender entrar: o comboio precisa de uma ponte estável.
local MapaPontes = {}

local M = 0.28
local MADEIRA = Color3.fromRGB(106, 84, 62)
local ESCURA = Color3.fromRGB(70, 56, 42)

local function peca(pai: Instance, nome: string, tam: Vector3, cf: CFrame, cor: Color3, colide: boolean): Part
	local p = Instance.new("Part")
	p.Name = nome
	p.Anchored = true
	p.Size = tam
	p.CFrame = cf
	p.Color = cor
	p.Material = Enum.Material.WoodPlanks
	p.CanCollide = colide
	p.CanQuery = colide
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Material", "Wood")
	p.Parent = pai
	return p
end

function MapaPontes.montar(map: Instance, layout: any): number
	local pasta = Instance.new("Folder")
	pasta.Name = "Pontes"
	for i, b in layout.pontes do
		local m = Instance.new("Model")
		m.Name = string.format("%s_%d", b.tipo, i)
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local a, c = Vector3.new(b.x1, b.y, b.z1), Vector3.new(b.x2, b.y, b.z2)
		local d = (c - a).Unit
		-- o tabuleiro entra 3 m em cada margem
		local inicio, fim = a - d * (3 / M), c + d * (3 / M)
		local comp = (fim - inicio).Magnitude
		local base = CFrame.lookAt((inicio + fim) / 2, fim)
		local esp = 0.3 / M
		-- D-251: com o modelo do Blender por cima, as peças ficam só como colisão
		local comArte = b.arte == true
		local tab =
			peca(m, "Tabuleiro", Vector3.new(b.largura, esp, comp), base * CFrame.new(0, -esp / 2, 0), MADEIRA, true)
		if comArte then
			tab.Transparency = 1
		end
		local alt = 1.05 / M
		for _, lado in { -1, 1 } do
			local x = lado * (b.largura / 2 - 0.08 / M)
			local corr =
				peca(m, "Corrimao", Vector3.new(0.12 / M, 0.12 / M, comp), base * CFrame.new(x, alt, 0), ESCURA, true)
			if comArte then
				corr.Transparency = 1
			end
			local n = if comArte then -1 else math.max(2, math.floor(comp * M / 2.5))
			for k = 0, n do
				local z = -comp / 2 + comp * k / n
				peca(
					m,
					"Montante",
					Vector3.new(0.14 / M, alt, 0.14 / M),
					base * CFrame.new(x, alt / 2, z),
					ESCURA,
					false
				)
				if k > 0 and k < n then
					peca(
						m,
						"Esteio",
						Vector3.new(0.3 / M, 4 / M, 0.3 / M),
						base * CFrame.new(x, -2 / M - esp, z),
						ESCURA,
						false
					)
				end
			end
		end
		m.Parent = pasta
	end
	pasta.Parent = map
	return #layout.pontes
end

return MapaPontes
