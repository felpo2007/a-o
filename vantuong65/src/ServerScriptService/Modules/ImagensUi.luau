--!strict
-- Imagens de interface publicadas pelo Open Cloud (assets/upload_plan.json, grupo Images). O Open
-- Cloud devolve o ID do DECAL; a ImageLabel precisa do ID da IMAGEM. O servidor abre o decal
-- (InsertService:LoadAsset, só assets do dono do jogo), lê o Texture e põe o ID da imagem num
-- atributo do ReplicatedStorage ("Img_<chave>"), como a CartaService faz com a carta. Sem o
-- atributo, o cliente usa o desenho de reserva (ex.: a caveira do abate feita com frames).
-- Chamado pelo ProgressionService.start (a caveira do abate sai do crédito do abate).
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Skins = require(ReplicatedStorage.Shared.Skins) :: any

local ImagensUi = {}

-- D-133: as bandeiras da escolha de lado (Controllers/Bandeiras: a imagem por cima do desenho)
ImagensUi.KEYS = { "caveira_abate", "bandeira_eua", "bandeira_frente", "rotor_borrao" }
-- D-213: as texturas dos efeitos de interface (Controllers/UiEfeitos: "Img_efeito_<nome>")
for _, nome in { "brilho", "faisca", "raio", "anel", "cintila" } do
	table.insert(ImagensUi.KEYS, "efeito_" .. nome)
end
-- D-217: a imagem da entrada ARMÁRIO do lobby (Controllers/MenuPrincipal: "Img_menu_armario")
table.insert(ImagensUi.KEYS, "menu_armario")
-- D-221: o cenário do pódio (Controllers/CenaComemoracao: "Img_podio_fundo")
table.insert(ImagensUi.KEYS, "podio_fundo")

local function imageOf(decalId: number): number?
	local ok, model = pcall(function()
		return InsertService:LoadAsset(decalId)
	end)
	if not ok or not model then
		return nil
	end
	local decal = model:FindFirstChildWhichIsA("Decal", true)
	local tex = if decal then decal.Texture else ""
	model:Destroy()
	return tonumber(string.match(tex, "%d+$") or "")
end

-- D-177: os moldes de roupa das skins de uniforme (decal -> imagem), para o cliente vestir o
-- soldado nos cartões das caixas, da roleta e do álbum ("Molde_<chave>" no ReplicatedStorage).
-- Um de cada vez: o InsertService limita pedidos em rajada.
function ImagensUi.moldes()
	task.spawn(function()
		local C = AssetIds.Clothing or {}
		local feitos: { [string]: boolean } = {}
		for _, s in Skins.CATALOG do
			if s.kind == "uniform" then
				for _, key in { s.shirt, s.pants } do
					local d = key and C[key]
					if key and not feitos[key] and type(d) == "number" and d ~= 0 then
						feitos[key] = true
						-- D-236: os moldes *_v3 agora são a versão pintada, publicada como Image (ID direto)
						local id = if string.sub(key, -3) == "_v3" then d else imageOf(d)
						if id and id ~= 0 then
							ReplicatedStorage:SetAttribute("Molde_" .. key, id)
						end
					end
				end
			end
		end
	end)
end

-- D-212: as imagens das caixas da loja ("ImgCaixa_<id>"), uma de cada vez (o InsertService limita
-- pedidos em rajada). Sem o atributo, o cliente mostra o caixote 3D de antes. D-213: também as duas
-- camadas da caixa aberta ("ImgCaixa_<id>_corpo" e "_tampa"), as chaves com "_" do mesmo grupo.
-- D-219: e o nome em outra língua ("<id>_en", "<id>_corpo_en"...; a tampa não tem nome).
function ImagensUi.passoDaCaixa(id: string): number
	if not string.find(id, "_", 1, true) then
		return 1 -- a fechada em português
	end
	if string.find(id, "_corpo", 1, true) or string.find(id, "_tampa", 1, true) then
		return 3 -- as camadas da abertura
	end
	return 2 -- a fechada em outra língua
end

function ImagensUi.caixas()
	task.spawn(function()
		-- primeiro as fechadas (a vitrine), depois as outras línguas e as camadas da abertura
		for _, passo in { 1, 2, 3 } do
			for id, d in AssetIds.CaixaLoja or {} do
				if ImagensUi.passoDaCaixa(id) ~= passo then
					continue
				end
				if type(d) == "number" and d ~= 0 then
					local img = imageOf(d)
					if img and img ~= 0 then
						ReplicatedStorage:SetAttribute("ImgCaixa_" .. id, img)
					else
						warn(
							string.format("[VT65] imagem da caixa %s: o decal %d não abriu; fica o caixote 3D", id, d)
						)
					end
				end
			end
		end
	end)
end

-- D-218: as insígnias dos emblemas ("ImgEmblema_<id>"), uma de cada vez. Sem o atributo, o cliente
-- mostra a sigla de antes (Controllers/EmblemaImagem).
function ImagensUi.emblemas()
	task.spawn(function()
		for id, d in AssetIds.Emblemas or {} do
			if type(d) == "number" and d ~= 0 then
				local img = imageOf(d)
				if img and img ~= 0 then
					ReplicatedStorage:SetAttribute("ImgEmblema_" .. id, img)
				else
					warn(string.format("[VT65] imagem do emblema %s: o decal %d não abriu; fica a sigla", id, d))
				end
			end
		end
	end)
end

function ImagensUi.start()
	ImagensUi.moldes()
	ImagensUi.caixas()
	ImagensUi.emblemas()
	local images = AssetIds.Images or {}
	for _, k in ImagensUi.KEYS do
		local d = images[k]
		if type(d) == "number" and d ~= 0 then
			task.spawn(function()
				local id = imageOf(d)
				if id and id ~= 0 then
					ReplicatedStorage:SetAttribute("Img_" .. k, id)
				else
					warn(string.format("[VT65] imagem de interface %s: o decal %d não abriu; fica o desenho", k, d))
				end
			end)
		end
	end
end

return ImagensUi
