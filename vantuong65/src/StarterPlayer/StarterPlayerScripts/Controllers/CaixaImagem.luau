--!strict
-- D-212 (dono: "imagens brilhantes e realistas", "modifique as imagens das caixas"): a imagem de cada
-- caixa de suprimentos (tools/blender/caixas_loja.py: madeira, metal ou laca, latão, estêncil e a luz
-- da raridade) numa ImageLabel. O ID da imagem vem do servidor (Modules/ImagensUi, atributo
-- "ImgCaixa_<id>" no ReplicatedStorage). Enquanto não chega (ou se o decal não abriu), fica o caixote
-- 3D de antes (ReplicatedStorage.VT65CaixasArte) num ViewportFrame; quando chega, troca sozinho.
-- Usado pela vitrine da loja (ShopController), pela aba CAIXAS e pela abertura (CaixasTela).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaixaImagem = {}

-- o ID da imagem da caixa, ou nil enquanto o servidor não resolveu
function CaixaImagem.id(caixaId: string): number?
	local v = ReplicatedStorage:GetAttribute(string.format("ImgCaixa_%s", caixaId))
	return if type(v) == "number" and v ~= 0 then v else nil
end

-- o caixote 3D de antes (a reserva), enquadrado de três quartos
local function caixote3d(parent: Instance, modelo: string?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Caixote3D"
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 146, 130)
	vp.LightColor = Color3.fromRGB(255, 240, 214)
	vp.LightDirection = Vector3.new(-1, -1.4, -0.6)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local folder = ReplicatedStorage:FindFirstChild("VT65CaixasArte")
	local src = folder and modelo and folder:FindFirstChild(modelo)
	local m: Model
	if src and src:IsA("Model") then
		m = src:Clone()
	else
		m = Instance.new("Model")
		local p = Instance.new("Part")
		p.Size = Vector3.new(2.6, 1.6, 1.6)
		p.Color = Color3.fromRGB(96, 92, 58)
		p.Material = Enum.Material.WoodPlanks
		p.Anchored = true
		p.Parent = m
		m.PrimaryPart = p
	end
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	local d = size.Magnitude * 1.7
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(d * 0.55, d * 0.42, d * 0.72), cf.Position)
	return vp
end

-- A caixa dentro de `parent`, ocupando o pai inteiro (o pai decide o tamanho). Devolve o quadro.
function CaixaImagem.desenha(parent: Instance, caixaId: string, modelo: string?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "CaixaImagem"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	local img = Instance.new("ImageLabel")
	img.Name = "Imagem"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Fit
	img.Visible = false
	img.Parent = holder
	local reserva: ViewportFrame? = nil
	local function pinta()
		local id = CaixaImagem.id(caixaId)
		if id then
			img.Image = string.format("rbxassetid://%d", id)
			img.Visible = true
			local r = reserva
			if r then
				r:Destroy()
				reserva = nil
			end
		elseif not reserva then
			reserva = caixote3d(holder, modelo)
		end
	end
	local conn = ReplicatedStorage:GetAttributeChangedSignal(string.format("ImgCaixa_%s", caixaId)):Connect(pinta)
	holder.Destroying:Connect(function()
		conn:Disconnect()
	end)
	pinta()
	holder.Parent = parent
	return holder
end

return CaixaImagem
