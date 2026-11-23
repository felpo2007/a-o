--!strict
-- D-218 (dono: "faça imagens sensacionais para os emblemas"): a insígnia de cada emblema
-- (tools/blender/emblemas.py) numa ImageLabel. O ID da imagem vem do servidor (Modules/ImagensUi,
-- atributo "ImgEmblema_<id>" no ReplicatedStorage). Enquanto não chega (ou se o decal não abriu), quem
-- chamou mantém o desenho de reserva (a sigla); quando chega, a imagem entra sozinha.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EmblemaImagem = {}

-- o ID da imagem do emblema, ou nil enquanto o servidor não resolveu
function EmblemaImagem.id(emblemaId: string?): number?
	if not emblemaId then
		return nil
	end
	local v = ReplicatedStorage:GetAttribute(string.format("ImgEmblema_%s", emblemaId))
	return if type(v) == "number" and v ~= 0 then v else nil
end

-- uma ligação por imagem: a mesma ImageLabel troca de emblema sem acumular conexões
local ligacoes: { [ImageLabel]: RBXScriptConnection } = {}

-- Uma ImageLabel vazia e invisível para o `mostra` preencher
function EmblemaImagem.nova(parent: Instance): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "EmblemaArte"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Fit
	img.Visible = false
	img.Destroying:Once(function()
		local c = ligacoes[img]
		if c then
			c:Disconnect()
			ligacoes[img] = nil
		end
	end)
	img.Parent = parent
	return img
end

-- Mostra o emblema em `img`. `aoMudar(temImagem)` roda agora e quando a imagem chegar, para quem
-- chamou esconder o desenho de reserva. Devolve se a imagem já está pronta.
function EmblemaImagem.mostra(img: ImageLabel, emblemaId: string?, aoMudar: ((boolean) -> ())?): boolean
	local velha = ligacoes[img]
	if velha then
		velha:Disconnect()
		ligacoes[img] = nil
	end
	local function pinta(): boolean
		local id = EmblemaImagem.id(emblemaId)
		img.Image = if id then string.format("rbxassetid://%d", id) else ""
		img.Visible = id ~= nil
		if aoMudar then
			aoMudar(id ~= nil)
		end
		return id ~= nil
	end
	if emblemaId and not EmblemaImagem.id(emblemaId) then
		ligacoes[img] = ReplicatedStorage:GetAttributeChangedSignal(string.format("ImgEmblema_%s", emblemaId))
			:Connect(function()
				pinta()
			end)
	end
	return pinta()
end

return EmblemaImagem
