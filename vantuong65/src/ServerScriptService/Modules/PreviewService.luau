--!strict
-- Manequins da tela de deslocamento (prévia 3D no cliente, Controllers/SoldierPreview).
-- Um soldado por facção, montado como no spawn: HumanoidDescription de Characters.describe,
-- Players:CreateHumanoidModelFromDescriptionAsync (como o BotService), uniforme e equipamento de
-- Characters.dress e a arma do fuzileiro por AssetLoader.attachWeapon. Tudo ancorado, sem scripts, em
-- ReplicatedStorage.VT65Preview.<US|VC>. O cliente clona num ViewportFrame e troca a arma pela do
-- papel escolhido: por isso este módulo também carrega a arte de todas as armas-base dos papéis
-- (AssetLoader.template põe as cópias em ReplicatedStorage.VT65WeaponArt).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Roles = require(ReplicatedStorage.Shared.Roles)
local AssetLoader = require(script.Parent.AssetLoader)
local Characters = require(script.Parent.Characters)

local PreviewService = {}

PreviewService.FOLDER = "VT65Preview"

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
	Characters.dress(model, faction, nil)
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

function PreviewService.start()
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
