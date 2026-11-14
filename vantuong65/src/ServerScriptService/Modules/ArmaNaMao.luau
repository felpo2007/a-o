--!strict
-- Arma e granada na mão que TODOS veem (2026-11-13, pedido do dono: "os itens como armas e resto não
-- estão aparecendo"). Antes a troca de arma era só do cliente: o corpo seguia com a principal na mão
-- (a pistola sacada nunca aparecia) e a granada só surgia no ar. O cliente (WeaponController) avisa
-- o que tem na mão por Posture_Set { arma = id } (o mesmo remote da postura; cada serviço lê o seu
-- campo). Aqui, conferido:
-- - arma de fogo das vagas (Shared/Equipar.weapons do papel, com a arma pega do chão): vai à mão
--   direita (AssetLoader.attachWeapon, a mesma da arma do chão; o PostureController segura a pistola
--   com a pega de pistola) e a principal, se não for ela, vai às costas a tiracolo ("ArmaCostas");
-- - "launcher": a arte do lançador que existe (RPG-2 do VC); a bazuca M20 ainda não tem modelo;
-- - "frag"/"smoke" com granada sobrando: a granada desenhada (Shared/GrenadeArt.hand) soldada na mão
--   direita ("GranadaMao"); sai da mão no arremesso (atributo "Throwing" do FieldService, em 0,4 s).
-- Pedidos juntos (trocas rápidas) viram um só a cada 0,1 s: vale o último.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Corpo = require(ReplicatedStorage.Shared.Corpo)
local Equipar = require(ReplicatedStorage.Shared.Equipar)
local GrenadeArt = require(ReplicatedStorage.Shared.GrenadeArt)
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AssetLoader = require(script.Parent.AssetLoader)
local MeleeService = require(script.Parent.MeleeService)

local ArmaNaMao = {}
local M = 0.28
local RELEASE_S = Equipar.GRENADE.releaseS -- FieldService.RELEASE_S

local pending: { [Player]: any } = {}

local function alive(p: Player): Model?
	local c = p.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if c and hum and hum.Health > 0 and hum.SeatPart == nil and not c:GetAttribute("Downed") then
		return c
	end
	return nil
end

local function slotsOf(p: Player): { string }
	local lo = p:GetAttribute("Loadout")
	local carried = p:GetAttribute("CarriedWeapon")
	local role = p:GetAttribute("Role")
	return Equipar.weapons(
		if type(lo) == "string" and lo ~= "" then string.split(lo, ",") else {},
		if type(role) == "string" then role else nil,
		if type(carried) == "string" then carried else nil
	)
end

-- solda todas as peças na principal e a principal em `to`, sem peso nem colisão
local function weldAll(m: Model, to: BasePart)
	local primary = m.PrimaryPart :: BasePart
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.CastShadow = false
			d.Massless = true
			if d ~= primary then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = primary, d
				w.Parent = d
			end
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = to, primary
	w.Parent = primary
end

-- Arma longa às costas (a tiracolo): punho no meio das costas, boca para cima por trás do ombro
-- direito, alça para fora. Nil tira. Pistola não vai às costas (fica no coldre, Modules/Gear).
-- PLACEHOLDER de lugar (35° de inclinação, 12 cm fora das costas): conferir no Studio.
function ArmaNaMao.back(char: Model, id: string?)
	local old = char:FindFirstChild("ArmaCostas")
	if old and id and old:GetAttribute("WeaponId") == id then
		return
	end
	if old then
		old:Destroy()
	end
	local wp = if id then Weapons.get(id) else nil
	local ut = char:FindFirstChild("UpperTorso") :: BasePart?
	if not (id and wp and ut) or wp.kind == "pistol" then
		return
	end
	local w = AssetLoader.weaponModel(id, wp.kind)
	if not w.PrimaryPart then
		w:Destroy()
		return
	end
	local a = math.rad(35)
	-- D-108: a arma é Corpo.ARMA_K mais grossa (GunModel.fit): o vão das costas cresce junto
	local pos = Vector3.new(0, -0.05 / M, ut.Size.Z / 2 + 0.12 / M * Corpo.ARMA_K)
	-- eixos da arma: +X para a direita-baixo, +Y (alto da arma) para fora das costas, boca (−Z)
	-- para cima e para a direita
	local cf = CFrame.fromMatrix(pos, Vector3.new(math.cos(a), -math.sin(a), 0), Vector3.new(0, 0, 1))
	w:PivotTo(ut.CFrame * cf)
	weldAll(w, ut)
	w.Name = "ArmaCostas"
	w:SetAttribute("WeaponId", id)
	w.Parent = char
end

-- Granada na mão direita (nil tira).
function ArmaNaMao.grenade(char: Model, kind: string?, faction: string?)
	local old = char:FindFirstChild("GranadaMao")
	if old and kind and old:GetAttribute("Kind") == kind then
		return
	end
	if old then
		old:Destroy()
	end
	local hand = char:FindFirstChild("RightHand") :: BasePart?
	if not (kind and hand) then
		return
	end
	local m = GrenadeArt.hand(kind, faction)
	m:SetAttribute("Kind", kind)
	m:ScaleTo(m:GetScale() * Corpo.ARMA_K) -- D-108: granada maior, como as armas (em volta do pivô)
	-- na palma: logo abaixo do centro da mão de bloco
	m:PivotTo(hand.CFrame * CFrame.new(0, -hand.Size.Y * 0.45, 0))
	weldAll(m, hand)
	m.Parent = char
end

local function apply(p: Player, arma: any)
	local char = alive(p)
	if not char then
		return
	end
	local faction = p:GetAttribute("Faction")
	local fac = if type(faction) == "string" then faction else nil
	if arma == "frag" or arma == "smoke" then
		local left = p:GetAttribute(if arma == "frag" then "Frags" else "Smokes")
		if type(left) == "number" and left > 0 then
			ArmaNaMao.grenade(char, arma, fac)
		end
		return
	end
	ArmaNaMao.grenade(char, nil, fac)
	local list = slotsOf(p)
	if type(arma) ~= "string" or not table.find(list, arma) then
		return
	end
	local handId = Equipar.handId(arma, fac)
	if handId and Weapons.get(handId) then
		local cur = char:FindFirstChild("Weapon")
		if not (cur and cur:GetAttribute("WeaponId") == handId) then
			AssetLoader.attachWeapon(char, handId)
			-- a baioneta segue a arma da mão (a pistola não tem; a do fuzil volta com o fuzil)
			MeleeService.setBayonet(char, char:GetAttribute("Bayonet") == true, handId)
		end
	end
	ArmaNaMao.back(char, if list[1] ~= arma then list[1] else nil)
end

local function watch(char: Model)
	-- o braço lança: a granada sai da mão do corpo junto com a do FieldService
	char:GetAttributeChangedSignal("Throwing"):Connect(function()
		if char:GetAttribute("Throwing") == true then
			task.delay(RELEASE_S, function()
				local g = char:FindFirstChild("GranadaMao")
				if g then
					g:Destroy()
				end
			end)
		end
	end)
end

function ArmaNaMao.start()
	Net.event("Posture_Set").OnServerEvent:Connect(function(p: Player, req: any)
		if type(req) ~= "table" or req.arma == nil then
			return
		end
		local first = pending[p] == nil
		pending[p] = req.arma
		if first then
			task.delay(0.1, function()
				local arma = pending[p]
				pending[p] = nil
				if arma ~= nil then
					apply(p, arma)
				end
			end)
		end
	end)
	local function onPlayer(p: Player)
		p.CharacterAdded:Connect(watch)
		if p.Character then
			watch(p.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		pending[p] = nil
	end)
end

return ArmaNaMao
