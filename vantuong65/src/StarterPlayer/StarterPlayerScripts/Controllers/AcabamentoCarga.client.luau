--!strict
-- Carga das texturas dos acabamentos de arma (D-181). A SurfaceAppearance pronta do acabamento
-- (Skins.applyWeapon, etiqueta Skins.TAG_ACABAMENTO) pede 4 imagens. Se uma falha, a arma fica
-- clara a partida inteira. No Studio falharam 10 de 240 pedidas de uma vez, e a imagem
-- recém-enviada também falha por alguns minutos. Aqui:
--   - cada SurfaceAppearance de acabamento que aparece (a sua arma, as dos outros, as imagens das
--     telas) é pré-carregada. Se falhar, tenta de novo 3 vezes (4, 8 e 12 s) e recoloca a SA na
--     peça para o render ler a textura de novo;
--   - se não chegar, volta a arte de fábrica só neste cliente (a SA original guardada na pasta
--     VT65SkinSA da peça) em vez da arma clara. Quando o acabamento muda, o novo entra normalmente;
--   - os acabamentos que você equipou (atributo "WeaponSkins") são pré-carregados ao mudar, para a
--     arma já nascer pintada.
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skins = require(ReplicatedStorage.Shared.Skins)

local TAG = Skins.TAG_ACABAMENTO
local ESPERAS = { 4, 8, 12 }

local player = Players.LocalPlayer

-- true = as imagens da SurfaceAppearance chegaram. Script do jogo não lê o ColorMap (só plugin):
-- os 4 IDs vêm no atributo "Mapas" da SA pronta (tools/acabamentos.py --luau).
local function precarrega(sa: Instance): boolean
	local ims = {}
	local mapas = sa:GetAttribute("Mapas")
	if type(mapas) ~= "string" then
		return true -- sem a lista, não há o que conferir
	end
	for id in string.gmatch(mapas, "%d+") do
		local im = Instance.new("ImageLabel")
		im.Image = "rbxassetid://" .. id
		table.insert(ims, im)
	end
	local ok = true
	pcall(function()
		ContentProvider:PreloadAsync(ims, function(_, st)
			if st == Enum.AssetFetchStatus.Failure or st == Enum.AssetFetchStatus.TimedOut then
				ok = false
			end
		end)
	end)
	for _, im in ims do
		im:Destroy()
	end
	return ok
end

-- a textura não chegou: a arte de fábrica volta só neste cliente
local function voltaFabrica(sa: Instance)
	local mp = sa.Parent
	local guarda = if mp then mp:FindFirstChild("VT65SkinSA") else nil
	local orig = if guarda then guarda:FindFirstChildOfClass("SurfaceAppearance") else nil
	if not (mp and guarda and orig) then
		return
	end
	sa.Parent = nil
	orig.Parent = mp
	mp:SetAttribute("AcabamentoFalhou", true)
	local con: RBXScriptConnection? = nil
	con = mp.ChildAdded:Connect(function(c)
		if c:HasTag(TAG) then
			-- outro acabamento chegou: a original volta para a pasta, como está no servidor
			if orig.Parent == mp then
				orig.Parent = guarda
			end
			mp:SetAttribute("AcabamentoFalhou", nil)
			if con then
				con:Disconnect()
			end
		end
	end)
end

local vistos: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function cuida(sa: Instance)
	if not sa:IsA("SurfaceAppearance") or vistos[sa] then
		return
	end
	vistos[sa] = true
	task.spawn(function()
		if precarrega(sa) then
			return
		end
		for _, espera in ESPERAS do
			task.wait(espera)
			local mp = sa.Parent
			if not mp then
				return -- o acabamento saiu da arma
			end
			if precarrega(sa) then
				-- chegou depois: recoloca na peça para o render ler a textura de novo
				sa.Parent = nil
				sa.Parent = mp
				return
			end
		end
		if sa.Parent then
			voltaFabrica(sa)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(cuida)
for _, sa in CollectionService:GetTagged(TAG) do
	cuida(sa)
end

-- os seus acabamentos: pré-carregados ao equipar, antes de nascer
local function precarregaMeus()
	local pasta = ReplicatedStorage:FindFirstChild("VT65AcabamentosSA")
	if not pasta then
		return
	end
	for arma, id in Skins.decodeWeapons(player:GetAttribute("WeaponSkins")) do
		local sa = pasta:FindFirstChild(Skins.chavePronta(id, arma))
		if sa then
			task.spawn(precarrega, sa)
		end
	end
end
player:GetAttributeChangedSignal("WeaponSkins"):Connect(precarregaMeus)
task.defer(precarregaMeus)
