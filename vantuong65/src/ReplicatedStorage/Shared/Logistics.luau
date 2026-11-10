--!strict
-- Logística (F4): suprimento por facção, renda por minuto, caixotes físicos e construções.
-- Números são de design (D-37): ajustar em playtest. Nada aqui é vendável (D-20).
local Logistics = {}

Logistics.START = 150
Logistics.CAP = 1000
Logistics.CRATE = 100 -- suprimento por caixote
-- renda por minuto: base + por ponto forte controlado. EUA: navios e praia; VC: depósitos locais.
Logistics.INCOME = {
	US = { base = 20, perPoint = 6 },
	VC = { base = 16, perPoint = 8 },
} :: { [string]: { base: number, perPoint: number } }

export type BuildDef = {
	id: string,
	name: string,
	cost: number,
	role: { [string]: boolean },
	minEnemyM: number, -- distância mínima de inimigos vivos
	nearSupplyM: number?, -- precisa de caixote a esta distância (nil = não precisa)
	limit: number, -- por facção
}

Logistics.BUILDS = {
	garrison = {
		id = "garrison",
		name = "Posto de reunião",
		cost = 50,
		role = { squad_leader = true },
		minEnemyM = 150,
		nearSupplyM = 50,
		limit = 4,
	},
	mg_nest = {
		id = "mg_nest",
		name = "Ninho de metralhadora (sacos de areia)",
		cost = 30,
		role = { engineer = true, squad_leader = true },
		minEnemyM = 60,
		nearSupplyM = 50,
		limit = 6,
	},
	mortar_pit = {
		id = "mortar_pit",
		name = "Posição de morteiro",
		cost = 40,
		role = { mortar = true },
		minEnemyM = 200,
		nearSupplyM = nil,
		limit = 2,
	},
	ammo = {
		id = "ammo",
		name = "Caixa de munição",
		cost = 20,
		role = { squad_leader = true, engineer = true },
		minEnemyM = 60,
		nearSupplyM = 50,
		limit = 6,
	},
} :: { [string]: BuildDef }

-- capacidade de caixotes por veículo (design): LVTP-5 traz da praia, UH-34D lança de cima
Logistics.CARRY = { lvtp5 = 3, uh34d = 2, m48a3 = 0, ontos = 0 }

export type State = { supply: { [string]: number }, acc: { [string]: number } }

function Logistics.new(): State
	return { supply = { US = Logistics.START, VC = Logistics.START }, acc = { US = 0, VC = 0 } }
end

-- avança dt segundos; owned = pontos fortes controlados por facção. Devolve o suprimento.
function Logistics.tick(s: State, dt: number, owned: { [string]: number }): { [string]: number }
	for f, inc in Logistics.INCOME do
		local perMin = inc.base + inc.perPoint * (owned[f] or 0)
		s.acc[f] += perMin * dt / 60
		local whole = math.floor(s.acc[f])
		if whole > 0 then
			s.acc[f] -= whole
			s.supply[f] = math.min(Logistics.CAP, s.supply[f] + whole)
		end
	end
	return s.supply
end

function Logistics.spend(s: State, faction: string, amount: number): boolean
	if (s.supply[faction] or 0) < amount then
		return false
	end
	s.supply[faction] -= amount
	return true
end

function Logistics.add(s: State, faction: string, amount: number)
	s.supply[faction] = math.min(Logistics.CAP, (s.supply[faction] or 0) + amount)
end

-- Validação de construção (puro): papel, custo, limite, inimigos e caixote por perto.
function Logistics.canBuild(
	s: State,
	faction: string,
	role: string,
	id: string,
	count: number,
	nearestEnemyM: number,
	nearestCrateM: number
): (boolean, string?)
	local b = Logistics.BUILDS[id]
	if not b then
		return false, "construção desconhecida"
	end
	if not b.role[role] then
		return false, "papel não pode construir"
	end
	if count >= b.limit then
		return false, "limite atingido"
	end
	if nearestEnemyM < b.minEnemyM then
		return false, "inimigos perto demais"
	end
	if b.nearSupplyM and nearestCrateM > b.nearSupplyM then
		return false, "precisa de caixote de suprimento perto"
	end
	if (s.supply[faction] or 0) < b.cost then
		return false, "suprimento insuficiente"
	end
	return true, nil
end

return Logistics
