--!strict
-- Esquema do perfil salvo no DataStore (puro: testável no Lune). O PlayerData carrega, salva e
-- aplica recibos; aqui só se define o formato e a migração de dados antigos ou corrompidos.
local Roles = require(
	if script
		then (game :: any):GetService("ReplicatedStorage").Shared.Roles
		else "../../ReplicatedStorage/Shared/Roles"
) :: any
local Tutorial = require(
	if script
		then (game :: any):GetService("ReplicatedStorage").Shared.Tutorial
		else "../../ReplicatedStorage/Shared/Tutorial"
) :: any

local ProfileSchema = {}

ProfileSchema.VERSION = 1

export type Profile = {
	schema: number,
	equipped: { [string]: { [string]: string } }, -- facção -> slot -> cosmético
	purchases: { [string]: number }, -- PurchaseId -> os.time()
	tips: number,
	unit: { id: string? },
	stats: { matches: number, playSeconds: number },
	settings: { [string]: any }?, -- controle e acessibilidade (Parte 12.8); saneado no Settings_Get
	tutorial: { [string]: boolean }, -- papéis com o tutorial concluído (F6)
}

function ProfileSchema.default(): Profile
	return {
		schema = ProfileSchema.VERSION,
		equipped = {},
		purchases = {},
		tips = 0,
		unit = {},
		stats = { matches = 0, playSeconds = 0 },
		tutorial = {},
	}
end

-- Dado salvo (qualquer forma) -> perfil válido. Nunca descarta campo conhecido: o que não é
-- reconhecido vira o padrão.
function ProfileSchema.migrate(raw: any): Profile
	local p = ProfileSchema.default()
	if type(raw) ~= "table" then
		return p
	end
	if type(raw.equipped) == "table" then
		p.equipped = raw.equipped
	end
	if type(raw.purchases) == "table" then
		p.purchases = raw.purchases
	end
	p.tips = tonumber(raw.tips) or 0
	if type(raw.unit) == "table" then
		p.unit = raw.unit
	end
	if type(raw.stats) == "table" then
		p.stats.matches = tonumber(raw.stats.matches) or 0
		p.stats.playSeconds = tonumber(raw.stats.playSeconds) or 0
	end
	-- antes de 2026-11-10 este campo era descartado aqui: as configurações sumiam a cada login
	if type(raw.settings) == "table" then
		p.settings = raw.settings
	end
	p.tutorial = Tutorial.sanitize(raw.tutorial, Roles.roles)
	return p
end

return ProfileSchema
