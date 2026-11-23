--!strict
-- Registro único de combatentes (jogadores e bots). Os serviços de captura, spawn, combate e
-- ferimentos trabalham com o MODELO do personagem, não com o Player.
local Combatants = {}

export type Entry = { model: Model, faction: string, player: Player?, bot: boolean }

local entries: { [Model]: Entry } = {}
local added = Instance.new("BindableEvent")
Combatants.Added = added.Event -- (entry)

function Combatants.register(model: Model, faction: string, player: Player?): Entry
	local e: Entry = { model = model, faction = faction, player = player, bot = player == nil }
	entries[model] = e
	model:SetAttribute("Faction", faction)
	model.Destroying:Connect(function()
		entries[model] = nil
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			entries[model] = nil
		end
	end)
	added:Fire(e)
	return e
end

function Combatants.get(model: Instance?): Entry?
	if model and model:IsA("Model") then
		return entries[model]
	end
	return nil
end

function Combatants.list(): { Entry }
	local out = {}
	for _, e in entries do
		table.insert(out, e)
	end
	return out
end

function Combatants.humanoid(e: Entry): Humanoid?
	return e.model:FindFirstChildOfClass("Humanoid")
end

function Combatants.root(e: Entry): BasePart?
	return e.model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- vivo e de pé (não incapacitado)
function Combatants.active(e: Entry): boolean
	local h = Combatants.humanoid(e)
	return h ~= nil and h.Health > 0 and not e.model:GetAttribute("Downed")
end

function Combatants.role(e: Entry): string?
	local r = e.model:GetAttribute("Role")
	if type(r) == "string" then
		return r
	end
	if e.player then
		local pr = e.player:GetAttribute("Role")
		return if type(pr) == "string" then pr else nil
	end
	return nil
end

return Combatants
