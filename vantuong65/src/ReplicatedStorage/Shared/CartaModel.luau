--!strict
-- Carta topográfica na mão (D-98): o mesmo papel em 1ª pessoa (Controllers/CartaMao) e na mão de
-- cada soldado que está com o mapa aberto (PostureController, atributo "Carta" posto pelo servidor).
-- Folha de carta dobrada em quatro (meia carta de ~50 × 36 cm à vista, PLACEHOLDER) com o vinco do
-- meio, papel de cor creme e, se a carta do jogo está carregada (atributos "CartaImage_nw"... do
-- ReplicatedStorage, CartaService), a imagem dela na face de leitura. Sem a imagem: quadrícula e
-- manchas de mata e arrozal desenhadas, para não ficar uma folha em branco.
-- Convenção: pivô no centro da folha; face impressa no +Z da peça (NormalId.Back); Attachments
-- "MaoE" e "MaoD" onde as mãos seguram (bordas esquerda e direita, um pouco abaixo do meio).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CartaModel = {}
local M = 0.28
CartaModel.W_M, CartaModel.H_M = 0.5, 0.36 -- folha dobrada, à vista (m)
CartaModel.FOLD_DEG = 10 -- as duas metades abertas como um livro
local PAPER = Color3.fromRGB(226, 214, 182)
local INK = Color3.fromRGB(92, 84, 62)
local GREEN = Color3.fromRGB(150, 168, 118)
local PADDY = Color3.fromRGB(196, 202, 150)

local function bare(p: BasePart)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function face(half: BasePart, xFrom: number, xTo: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 140
	gui.LightInfluence = 1
	gui.Parent = half
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = PAPER
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = gui
	local ready = ReplicatedStorage:GetAttribute("CartaPronta") == true
	if ready then
		-- a carta inteira (2 × 2 blocos) atravessa as duas metades: cada metade mostra a sua faixa
		local w = 1 / (xTo - xFrom)
		for i, key in { "nw", "ne", "sw", "se" } do
			local id = ReplicatedStorage:GetAttribute("CartaImage_" .. key)
			if type(id) == "number" then
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.Image = string.format("rbxassetid://%d", id)
				img.ScaleType = Enum.ScaleType.Stretch
				local col, row = (i - 1) % 2, (i - 1) // 2
				img.Size = UDim2.fromScale(0.5 * w, 0.5)
				img.Position = UDim2.fromScale((col * 0.5 - xFrom) * w, row * 0.5)
				img.Parent = frame
			end
		end
	else
		-- desenho simples: manchas de mata e arrozal e a quadrícula de 1 km
		for i = 1, 5 do
			local blob = Instance.new("Frame")
			blob.BackgroundColor3 = if i % 2 == 0 then PADDY else GREEN
			blob.BorderSizePixel = 0
			blob.Size = UDim2.fromScale(0.25 + 0.07 * i, 0.2 + 0.05 * i)
			blob.Position = UDim2.fromScale(((i * 0.37) % 1) - 0.1, ((i * 0.53) % 1) - 0.1)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.4, 0)
			c.Parent = blob
			blob.Parent = frame
		end
		for k = 1, 3 do
			for _, vertical in { true, false } do
				local line = Instance.new("Frame")
				line.BackgroundColor3 = INK
				line.BackgroundTransparency = 0.35
				line.BorderSizePixel = 0
				line.Size = if vertical then UDim2.new(0, 2, 1, 0) else UDim2.new(1, 0, 0, 2)
				line.Position = if vertical then UDim2.fromScale(k / 4, 0) else UDim2.fromScale(0, k / 4)
				line.Parent = frame
			end
		end
	end
end

-- Folha aberta (duas metades com o vinco no meio). Peças soltas; quem usa solda ou ancora.
function CartaModel.build(): Model
	local model = Instance.new("Model")
	model.Name = "VT65Carta"
	local w, h, t = CartaModel.W_M / M, CartaModel.H_M / M, 0.004 / M
	local fold = math.rad(CartaModel.FOLD_DEG)
	local main = Instance.new("Part")
	main.Name = "Folha"
	main.Size = Vector3.new(0.05, 0.05, 0.05)
	main.Transparency = 1
	bare(main)
	main.CFrame = CFrame.identity
	main.Parent = model
	for i, side in { -1, 1 } do
		local half = Instance.new("Part")
		half.Name = if side < 0 then "Esquerda" else "Direita"
		half.Size = Vector3.new(w / 2, h, t)
		half.Color = PAPER
		half.Material = Enum.Material.SmoothPlastic
		bare(half)
		-- cada metade gira no vinco (x = 0) para trás, e a carta abre como um livro
		half.CFrame = CFrame.Angles(0, -side * fold, 0) * CFrame.new(side * w / 4, 0, 0)
		face(half, if i == 1 then 0 else 0.5, if i == 1 then 0.5 else 1)
		half.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = main, half
		weld.Parent = half
	end
	local function hand(name: string, x: number)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = Vector3.new(x * (w / 2 - 0.03 / M), -0.04 / M, -0.02 / M)
		a.Parent = main
	end
	hand("MaoE", -1)
	hand("MaoD", 1)
	model.PrimaryPart = main
	return model
end

return CartaModel
