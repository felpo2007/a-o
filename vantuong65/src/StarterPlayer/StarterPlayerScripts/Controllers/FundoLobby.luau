--!strict
-- D-222 (dono: "troque o fundo do lobby, coloque algo com mais qualidade e não deixe ele tremendo"): o
-- fundo do lobby e da preparação é uma imagem parada (tools/blender/lobby_fundo.py, 2048 x 1152, sem
-- personagem). O Roblox limita cada imagem a 1024: ela vai em quatro blocos, que cobrem a tela sem
-- distorcer (o que sobra sai pelas bordas). Sem os blocos, fica a capa do arrozal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any

local FundoLobby = {}

FundoLobby.ASPECTO = 16 / 9
local BLOCOS = {
	{ "lobby_nw", 0, 0, "fundo_nw" },
	{ "lobby_ne", 0.5, 0, "fundo_ne" },
	{ "lobby_sw", 0, 0.5, "fundo_sw" },
	{ "lobby_se", 0.5, 0.5, "fundo_se" },
} :: { { any } }

-- O tamanho que cobre uma tela de `w` x `h` mantendo a proporção da imagem (pura, para o teste)
function FundoLobby.cobre(w: number, h: number, aspecto: number): (number, number)
	if h <= 0 or w <= 0 then
		return 0, 0
	end
	if w / h > aspecto then
		return w, w / aspecto
	end
	return h * aspecto, h
end

local function url(id: any): string
	return if type(id) == "number" and id ~= 0 then string.format("rbxassetid://%d", id) else ""
end

-- D-250 (imagens do dono): a cena do key art, sem o título; sem ela, o arrozal do D-222
local function urlBloco(b: { any }): string
	local m = url((AssetIds.Marca or {})[b[4]])
	return if m ~= "" then m else url((AssetIds.Catalogo or {})[b[1]])
end

-- Fundo em tela cheia dentro de `pai`. `escuro` (0 a 1): véu por cima, para o que vem na frente.
function FundoLobby.novo(pai: Instance, escuro: number?, z: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "FundoLobby"
	holder.BackgroundColor3 = Color3.fromRGB(14, 13, 11)
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = true
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = z or 0
	local miolo = Instance.new("Frame")
	miolo.Name = "Imagem"
	miolo.BackgroundTransparency = 1
	miolo.AnchorPoint = Vector2.new(0.5, 0.5)
	miolo.Position = UDim2.fromScale(0.5, 0.5)
	miolo.Parent = holder
	local temBlocos = true
	for _, b in BLOCOS do
		if urlBloco(b) == "" then
			temBlocos = false
		end
	end
	if temBlocos then
		for _, b in BLOCOS do
			local i = Instance.new("ImageLabel")
			i.Name = b[1]
			i.BackgroundTransparency = 1
			i.Image = urlBloco(b)
			i.Position = UDim2.fromScale(b[2], b[3])
			-- um fio a mais: a emenda dos blocos não aparece em nenhuma escala
			i.Size = UDim2.fromScale(0.5015, 0.5015)
			i.Parent = miolo
		end
	else
		local i = Instance.new("ImageLabel")
		i.Name = "Reserva"
		i.BackgroundTransparency = 1
		i.Image = url((AssetIds.Capas or {}).arrozal)
		i.ScaleType = Enum.ScaleType.Crop
		i.Size = UDim2.fromScale(1, 1)
		i.Parent = miolo
	end
	if escuro and escuro > 0 then
		local v = Instance.new("Frame")
		v.Name = "Veu"
		v.BackgroundColor3 = Color3.fromRGB(10, 10, 9)
		v.BackgroundTransparency = 1 - escuro
		v.BorderSizePixel = 0
		v.Size = UDim2.fromScale(1, 1)
		v.Parent = holder
	end
	local function encaixa()
		local s = holder.AbsoluteSize
		local w, h = FundoLobby.cobre(s.X, s.Y, FundoLobby.ASPECTO)
		miolo.Size = UDim2.fromOffset(math.ceil(w), math.ceil(h))
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(encaixa)
	holder.Parent = pai
	encaixa()
	return holder
end

return FundoLobby
