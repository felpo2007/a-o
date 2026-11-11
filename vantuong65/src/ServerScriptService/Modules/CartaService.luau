--!strict
-- Imagem da carta tática (tools/make_carta.py, 4 blocos de 1024 px). O Open Cloud devolve o ID do
-- DECAL; a ImageLabel precisa do ID da IMAGEM. Se AssetIds.CartaImages já tem a imagem, ela vale.
-- Senão, com o decal publicado, o servidor abre o decal (InsertService:LoadAsset, só assets do dono
-- do jogo) e lê o Texture. O resultado vai em atributos do ReplicatedStorage ("CartaImage_nw" ...)
-- e o GameUI monta a carta; sem nada disso, o mapa usa o desenho simples de antes.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any

local CartaService = {}

local KEYS = { "nw", "ne", "sw", "se" }
-- Decais da carta do mapa de 2 x 2 km (D-87). O mapa virou 1 x 1 km (2026-11-11) e a imagem
-- velha mostraria outro recorte, com os setores e os pontos no lugar errado: enquanto AssetIds.Carta
-- tiver estes IDs, o mapa tático usa o desenho simples. Os blocos novos estão em assets/carta/.
CartaService.STALE_DECALS = {
	[125482274641488] = true,
	[105148744178501] = true,
	[97095607126684] = true,
	[128203928291104] = true,
} :: { [number]: boolean }

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
	local id = tonumber(string.match(tex, "%d+$") or "")
	return id
end

function CartaService.start()
	local images = AssetIds.CartaImages or {}
	local decals = AssetIds.Carta or {}
	local n = 0
	for _, k in KEYS do
		local id = images[k]
		if type(id) ~= "number" or id == 0 then
			local d = decals[k]
			local fresh = type(d) == "number" and d ~= 0 and not CartaService.STALE_DECALS[d]
			id = if fresh then imageOf(d :: number) else nil
		end
		if type(id) == "number" and id ~= 0 then
			ReplicatedStorage:SetAttribute("CartaImage_" .. k, id)
			n += 1
		end
	end
	ReplicatedStorage:SetAttribute("CartaPronta", n == #KEYS)
	local stale = 0
	for _, k in KEYS do
		if CartaService.STALE_DECALS[decals[k] or 0] then
			stale += 1
		end
	end
	if stale > 0 then
		warn(
			string.format(
				"[VT65] carta tática: %d blocos ainda são da carta de 2 x 2 km; suba os de assets/carta e troque AssetIds.Carta",
				stale
			)
		)
	end
	if n > 0 and n < #KEYS then
		warn(
			string.format(
				"[VT65] carta tática: só %d de %d blocos resolvidos; o mapa usa o desenho simples",
				n,
				#KEYS
			)
		)
	end
end

return CartaService
