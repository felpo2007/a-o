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

local ImagensUi = {}

ImagensUi.KEYS = { "caveira_abate" }

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

function ImagensUi.start()
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
