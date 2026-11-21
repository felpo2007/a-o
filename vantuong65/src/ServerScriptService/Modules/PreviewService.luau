--!strict
-- Manequins da tela de deslocamento (prévia 3D no cliente, Controllers/SoldierPreview).
-- Um soldado por facção, montado como no spawn: HumanoidDescription de Characters.describe,
-- Players:CreateHumanoidModelFromDescriptionAsync (como o BotService), uniforme e equipamento de
-- Characters.dress e a arma do fuzileiro por AssetLoader.attachWeapon. Tudo ancorado, sem scripts, em
-- ReplicatedStorage.VT65Preview.<US|VC>. O cliente clona num ViewportFrame e troca a arma pela do
-- papel escolhido: por isso este módulo também carrega a arte de todas as armas-base dos papéis
-- (AssetLoader.template põe as cópias em ReplicatedStorage.VT65WeaponArt).
-- Lobby diegético (mesa de campanha do LobbyScene): também carrega alguns modelos publicados para
-- a mesa, em VT65Preview.Props (capacetes e sacos de areia). Só assets do dono carregam pelo
-- InsertService; sem eles o cliente usa a versão feita de peças.
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.AssetIds) :: any
local Roles = require(ReplicatedStorage.Shared.Roles)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)

local PreviewService = {}

PreviewService.FOLDER = "VT65Preview"
-- chave -> grupo do AssetIds (o modelo vai para VT65Preview.Props.<chave>)
local PROPS: { [string]: string } = {
	us_m1_helmet = "Accessories",
	vc_pith_helmet = "Accessories",
	sandbags = "Models",
}
PreviewService.PROPS = PROPS
-- D-206: o acampamento do lobby (Controllers/LobbyPalco). Os mesmos modelos do mapa, já preparados
-- pelo AssetLoader.template (folha de duas faces, sem colisão de folhagem), copiados para
-- VT65Preview.Props.<chave>. Sem a arte, o palco põe o que tiver.
local ACAMPAMENTO = {
	-- EUA
	"us_command_tent",
	"us_tent_gp_medium",
	"caixa_municao_us",
	"ammo_crate",
	"us_jerrycans",
	"us_fuel_drums",
	"sandbag_wall",
	"m151",
	"uh34d_v3",
	"us_flagpole",
	-- VC
	"vc_lean_to",
	"vc_hammock",
	"vc_weapon_rack",
	"caixa_municao_vc",
	"rice_sack",
	"clay_lamp",
	"vc_hoang_cam_kitchen",
	-- mata dos dois
	"coconut_palm",
	"banana",
	"bamboo_clump",
}
PreviewService.ACAMPAMENTO = ACAMPAMENTO

-- Modelo publicado parado, sem scripts e fora das consultas (o cliente clona na cena do lobby)
local function loadProp(key: string, group: string, folder: Folder)
	local id = AssetIds[group] and AssetIds[group][key]
	if type(id) ~= "number" or id == 0 then
		return
	end
	local ok, c = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not c then
		warn("[VT65] lobby: não carregou o modelo", key, c)
		return
	end
	local m = (c:FindFirstChildWhichIsA("Model") or c) :: Instance
	local model: Model
	if m:IsA("Model") then
		model = m
	else
		model = Instance.new("Model")
		for _, ch in c:GetChildren() do
			ch.Parent = model
		end
	end
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			parts += 1
		end
	end
	if parts == 0 then
		return
	end
	model.Name = key
	model:SetAttribute("Parts", parts) -- o cliente espera chegar tudo (como os manequins)
	model.Parent = folder
	if model ~= c then
		c:Destroy()
	end
end

local function build(faction: string, folder: Folder)
	local weaponId = Roles.loadout[faction].rifleman[1]
	local desc = Characters.describe(faction, nil, 0)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[VT65] prévia: não montou o manequim", faction, model)
		return
	end
	model.Name = faction
	-- fora do Workspace: nada de física nem de scripts; as peças ficam onde o servidor as montou
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy() -- o Animate rodaria dentro da PlayerGui (ViewportFrame) no cliente
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	-- o VC sem cosmético não tem cobertura de cabeça e o manequim da mesa saía careca (Studio, D-93):
	-- a prévia usa o capacete de medula (o mesmo prop da mesa do VC); sem a arte, fica como antes
	Characters.dress(model, faction, if faction == "VC" then { helmet = "vc_pith_helmet" } else nil)
	AssetLoader.attachWeapon(model, weaponId)
	-- âncora em tudo DEPOIS de vestir e armar: capacete, colete e arma já estão na posição soldada, e
	-- o WorldModel do ViewportFrame não resolve as soldas
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model:SetAttribute("Faction", faction)
	model:SetAttribute("Weapon", weaponId)
	-- O cliente recebe o modelo em pedaços: clonando no ChildAdded, a prévia do VC saía só com um
	-- braço e o fuzil (captura no Studio, D-64). Com a contagem, o cliente espera chegar tudo.
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	model:SetAttribute("Parts", parts)
	model.Parent = folder
end

-- ===== o soldado do próprio jogador (D-206; prompt de interface §6: "Use o próprio avatar do
-- jogador com seu uniforme, arma e equipamentos") =====
-- Montado como no spawn: Characters.describe/dress com os cosméticos equipados do lado, as skins de
-- uniforme e camuflagem desse lado (atributos no próprio modelo, porque no lobby o jogador ainda não
-- tem lado) e a arma principal do último papel. Parado e fora do mundo, na pasta VT65MeuSoldado da
-- PlayerGui: só o dono recebe. Refeito quando ele equipa um cosmético ou uma skin, troca de lado ou de
-- papel (no máximo um a cada PESSOAL_S).
local PESSOAL_S = 1.5
local pessoalGen: { [Player]: number } = {}

local function escolhaDe(player: Player): (string, string, string)
	local JogarAgora = require(ReplicatedStorage.Shared.JogarAgora) :: any
	local c = JogarAgora.decode(player:GetAttribute("UltimaEscolha"))
	local fa = player:GetAttribute("Faction")
	local faction = if fa == "US" or fa == "VC" then fa else (if c.f == "US" or c.f == "VC" then c.f else "US")
	local ra = player:GetAttribute("Role")
	local role = if type(ra) == "string" then ra else (if c.f == faction and c.role then c.role else "rifleman")
	local byRole = Roles.loadout[faction]
	local list = byRole[role] or byRole.rifleman
	local weapon = list[1]
	if c.f == faction and c.role == role and c.w and table.find(Roles.primaries(faction, role), c.w) then
		weapon = c.w
	end
	return faction, role, weapon
end

local function montaPessoal(player: Player)
	local PlayerData = require(script.Parent.PlayerData) :: any
	local ProgressionService = require(script.Parent.ProgressionService) :: any
	local prof = PlayerData.get(player)
	if not prof or not player.Parent then
		return
	end
	local faction, role, weapon = escolhaDe(player)
	local equipped = prof.equipped[faction]
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			Characters.describe(faction, equipped, player.UserId),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok or not model or not player.Parent then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	model.Name = "Soldado"
	model:SetAttribute("Dono", player.UserId)
	model:SetAttribute("Role", role)
	local skins = ProgressionService.skinsFor(player, faction)
	model:SetAttribute("SkinUniform", skins.uniform)
	model:SetAttribute("SkinCamo", skins.camo)
	Characters.dress(model, faction, equipped)
	AssetLoader.attachWeapon(model, weapon)
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			parts += 1
		end
	end
	model:SetAttribute("Faction", faction)
	model:SetAttribute("Weapon", weapon)
	model:SetAttribute("Parts", parts)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		model:Destroy()
		return
	end
	local folder = pg:FindFirstChild("VT65MeuSoldado")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "VT65MeuSoldado"
		f.Parent = pg
		folder = f
	end
	-- o novo entra antes de o velho sair: o cliente troca sem ficar sem soldado
	local old = (folder :: Instance):GetChildren()
	model.Parent = folder
	for _, o in old do
		o:Destroy()
	end
end

-- refaz o soldado do jogador daqui a pouco (vários pedidos juntos viram um)
function PreviewService.pessoal(player: Player)
	local g = (pessoalGen[player] or 0) + 1
	pessoalGen[player] = g
	task.delay(PESSOAL_S, function()
		if pessoalGen[player] == g and player.Parent then
			local ok, err = pcall(function(): any
				montaPessoal(player)
				return nil
			end)
			if not ok then
				warn("[VT65] lobby: soldado do jogador", player.UserId, err)
			end
		end
	end)
end

local function vigiaJogador(player: Player)
	for _, a in { "UltimaEscolha", "Faction", "Role" } do
		player:GetAttributeChangedSignal(a):Connect(function()
			PreviewService.pessoal(player)
		end)
	end
	-- perfil já carregado (o PlayerData.Loaded do start pega os que chegam depois)
	local PlayerData = require(script.Parent.PlayerData) :: any
	if PlayerData.get(player) then
		PreviewService.pessoal(player)
	end
	-- se a PlayerGui for refeita (renascer), a pasta volta
	player.CharacterAdded:Connect(function()
		task.wait(1)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg and not pg:FindFirstChild("VT65MeuSoldado") then
			PreviewService.pessoal(player)
		end
	end)
end

function PreviewService.start()
	-- D-206: o soldado de cada jogador (os ganchos de cosmético e skin chamam o mesmo)
	local CommerceService = require(script.Parent.CommerceService) :: any
	local ProgressionService = require(script.Parent.ProgressionService) :: any
	CommerceService.onEquip = PreviewService.pessoal
	ProgressionService.onSkinChange = PreviewService.pessoal
	local PlayerData = require(script.Parent.PlayerData) :: any
	PlayerData.Loaded:Connect(PreviewService.pessoal)
	Players.PlayerAdded:Connect(vigiaJogador)
	for _, p in Players:GetPlayers() do
		vigiaJogador(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		pessoalGen[p] = nil
	end)
	local folder = ReplicatedStorage:FindFirstChild(PreviewService.FOLDER) :: Folder?
	if not folder then
		local f = Instance.new("Folder")
		f.Name = PreviewService.FOLDER
		f.Parent = ReplicatedStorage
		folder = f
	end
	local root = folder :: Folder
	for _, faction in { "US", "VC" } do
		local ok, err = pcall(function(): any
			build(faction, root)
			return nil
		end)
		if not ok then
			warn("[VT65] prévia:", faction, err)
		end
	end
	-- objetos publicados da mesa do lobby
	local props = root:FindFirstChild("Props") :: Folder?
	if not props then
		local f = Instance.new("Folder")
		f.Name = "Props"
		f.Parent = root
		props = f
	end
	for key, group in PROPS do
		local ok, err = pcall(function(): any
			loadProp(key, group, props :: Folder)
			return nil
		end)
		if not ok then
			warn("[VT65] lobby: modelo", key, err)
		end
	end
	-- D-206: o acampamento do lobby, pelos templates do mapa (já carregados para a arte)
	for _, key in ACAMPAMENTO do
		local ok, err = pcall(function(): any
			local tpl = AssetLoader.template(key)
			if tpl and not (props :: Folder):FindFirstChild(key) then
				local m = tpl:Clone()
				local parts = 0
				for _, d in m:GetDescendants() do
					if d:IsA("BaseScript") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						parts += 1
					end
				end
				m.Name = key
				m:SetAttribute("Parts", parts)
				m.Parent = props
			end
			return nil
		end)
		if not ok then
			warn("[VT65] lobby: acampamento", key, err)
		end
	end
	-- arte das armas-base de todos os papéis (a prévia troca a arma ao escolher o papel)
	local seen: { [string]: boolean } = {}
	for _, byRole in Roles.loadout do
		for _, list in byRole do
			local id = list[1]
			if id and not seen[id] then
				seen[id] = true
				local ok, err = pcall(AssetLoader.template, id)
				if not ok then
					warn("[VT65] prévia: arma", id, err)
				end
			end
		end
	end
	root:SetAttribute("Ready", true)
end

return PreviewService
