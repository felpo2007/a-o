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
local Progression = require(
	if script
		then (game :: any):GetService("ReplicatedStorage").Shared.Progression
		else "../../ReplicatedStorage/Shared/Progression"
) :: any
local Skins = require(
	if script
		then (game :: any):GetService("ReplicatedStorage").Shared.Skins
		else "../../ReplicatedStorage/Shared/Skins"
) :: any

local ProfileSchema = {}

-- 1: perfil da F2/F6. 2 (2026-11-11): recompensa diária (daily) e cosméticos ganhos (earned).
-- 3 (2026-11-11): progressão: XP, créditos de intendência, equipamento comprado com créditos, a
-- escolha do equipamento e os "renasceres guardados" (Developer Product em Robux ainda não usado).
-- Skins (2026-11-11, Shared/Skins): campo `skins` (posse e escolha por lado). A migração é por
-- campo, como a das outras versões: perfil sem `skins` (qualquer versão) começa sem nenhuma. O
-- número fica 3: os testes da F2 e da progressão conferem a versão 3; subir para 4 pede trocar o
-- número esperado lá (só informativo: nada aqui depende do número).
ProfileSchema.VERSION = 3
ProfileSchema.MAX_EARNED = 128
ProfileSchema.MAX_XP = 1000000000
ProfileSchema.MAX_RESPAWN_CREDITS = 1000
ProfileSchema.MAX_SKINS = 256

-- Recompensa diária (a regra fica em Shared/Commerce): dias seguidos, dia UTC do último resgate
-- (-1 = nunca) e total de selos
export type Daily = { run: number, lastDay: number, total: number }

export type Profile = {
	schema: number,
	equipped: { [string]: { [string]: string } }, -- facção -> slot -> cosmético
	purchases: { [string]: number }, -- PurchaseId -> os.time()
	tips: number,
	unit: { id: string? },
	stats: { matches: number, playSeconds: number },
	settings: { [string]: any }?, -- controle e acessibilidade (Parte 12.8); saneado no Settings_Get
	tutorial: { [string]: boolean }, -- papéis com o tutorial concluído (F6)
	daily: Daily, -- v2
	earned: { [string]: boolean }, -- v2: cosméticos ganhos em jogo (unlock "daily"), id -> true
	xp: number, -- v3: experiência total (só cresce)
	credits: number, -- v3: créditos de intendência (ganhos jogando; nunca vendidos por Robux)
	gear: { [string]: boolean }, -- v3: equipamento comprado com créditos (permanente), id -> true
	gearOn: { [string]: boolean }, -- v3: escolha do equipamento; só guarda os desmarcados (false)
	respawnCredits: number, -- v3: renasceres no lugar comprados em Robux e ainda não usados
	skins: SkinsData, -- skins de arma, uniforme e camuflagem (Shared/Skins)
}

-- owned: compradas com $ ou por Developer Product (id -> true; o Game Pass não fica aqui).
-- on: escolha por lado e por encaixe (id da arma, "uniform" ou "camo") -> id da skin.
export type SkinsData = { owned: { [string]: boolean }, on: { [string]: { [string]: string } } }

-- Valores de progressão já gravados no DataStore (base do "delta" da sessão: PlayerData.save)
export type Synced = { xp: number, credits: number, respawnCredits: number }

function ProfileSchema.default(): Profile
	return {
		schema = ProfileSchema.VERSION,
		equipped = {},
		purchases = {},
		tips = 0,
		unit = {},
		stats = { matches = 0, playSeconds = 0 },
		tutorial = {},
		daily = { run = 0, lastDay = -1, total = 0 },
		earned = {},
		xp = 0,
		credits = Progression.START_CREDITS,
		gear = {},
		gearOn = {},
		respawnCredits = 0,
		skins = { owned = {}, on = { US = {}, VC = {} } },
	}
end

-- inteiro finito ou nil (NaN, infinito e texto viram nil)
local function int(v: any): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return math.floor(v)
end

-- v1 não tinha o campo: começa sem sequência. Valores corrompidos voltam ao seguro (sem sequência,
-- total nunca negativo); quem nunca resgatou não tem sequência.
function ProfileSchema.sanitizeDaily(raw: any): Daily
	local d: Daily = { run = 0, lastDay = -1, total = 0 }
	if type(raw) ~= "table" then
		return d
	end
	d.lastDay = math.max(int(raw.lastDay) or -1, -1)
	d.run = math.clamp(int(raw.run) or 0, 0, 1000000)
	d.total = math.clamp(int(raw.total) or 0, 0, 1000000)
	if d.lastDay < 0 then
		d.run = 0
	end
	if d.total < d.run then
		d.total = d.run
	end
	return d
end

function ProfileSchema.sanitizeEarned(raw: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return out
	end
	local n = 0
	for k, v in raw do
		if type(k) == "string" and #k > 0 and #k < 48 and v == true then
			n += 1
			if n > ProfileSchema.MAX_EARNED then
				break
			end
			out[k] = true
		end
	end
	return out
end

-- só ids de equipamento conhecidos (Shared/Progression.GEAR); valores: só `true` (gear) ou boolean (gearOn)
function ProfileSchema.sanitizeGear(raw: any, onlyTrue: boolean): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return out
	end
	for k, v in raw do
		if type(k) == "string" and Progression.GEAR[k] ~= nil and type(v) == "boolean" and (v or not onlyTrue) then
			out[k] = v
		end
	end
	return out
end

-- Skins: a posse guarda qualquer id de texto curto (uma skin tirada do catálogo não some do perfil
-- de quem pagou); a escolha só guarda skin conhecida, do lado e no encaixe dela.
function ProfileSchema.sanitizeSkins(raw: any): SkinsData
	local out: SkinsData = { owned = {}, on = { US = {}, VC = {} } }
	if type(raw) ~= "table" then
		return out
	end
	if type(raw.owned) == "table" then
		local n = 0
		for k, v in raw.owned do
			if type(k) == "string" and #k > 0 and #k < 48 and v == true then
				n += 1
				if n > ProfileSchema.MAX_SKINS then
					break
				end
				out.owned[k] = true
			end
		end
	end
	if type(raw.on) == "table" then
		for _, f in { "US", "VC" } do
			local slots = raw.on[f]
			if type(slots) == "table" then
				for slot, id in slots do
					local s = if type(slot) == "string" then Skins.get(id) else nil
					if s and Skins.slotOf(s) == slot and Skins.sideOk(s, f) then
						out.on[f][slot] = id
					end
				end
			end
		end
	end
	return out
end

-- Posse das skins: união (dst <- src). Nunca tira o que já está em dst.
function ProfileSchema.mergeSkins(dst: SkinsData, src: SkinsData)
	for id, v in src.owned do
		if v == true then
			dst.owned[id] = true
		end
	end
end

function ProfileSchema.synced(p: Profile): Synced
	return { xp = p.xp, credits = p.credits, respawnCredits = p.respawnCredits }
end

-- Escreve em `rec` o registro salvo `stored` + o que a sessão mudou desde a última gravação
-- (mem - base): dois servidores (troca de servidor, saída atrasada) nunca apagam o ganho um do
-- outro, e um gasto da sessão nunca some. O equipamento comprado é união; a escolha é a da sessão.
-- `rec` pode ser o próprio `stored`. Devolve os valores gravados. Puro.
function ProfileSchema.applySession(rec: Profile, stored: Profile, mem: Profile, base: Synced): Synced
	local xp = math.clamp(stored.xp + (mem.xp - base.xp), 0, ProfileSchema.MAX_XP)
	local credits = math.clamp(stored.credits + (mem.credits - base.credits), 0, Progression.MAX_CREDITS)
	local rc = math.clamp(
		stored.respawnCredits + (mem.respawnCredits - base.respawnCredits),
		0,
		ProfileSchema.MAX_RESPAWN_CREDITS
	)
	local gear = table.clone(stored.gear)
	for id in mem.gear do
		gear[id] = true
	end
	rec.xp, rec.credits, rec.respawnCredits = xp, credits, rc
	rec.gear = gear
	rec.gearOn = table.clone(mem.gearOn)
	-- skins: a posse é união (compra noutro servidor ou recibo gravado direto no DataStore); a
	-- escolha é a da sessão
	local skins: SkinsData = { owned = table.clone(stored.skins.owned), on = { US = {}, VC = {} } }
	ProfileSchema.mergeSkins(skins, mem.skins)
	for f, slots in mem.skins.on do
		skins.on[f] = table.clone(slots)
	end
	rec.skins = skins
	return { xp = xp, credits = credits, respawnCredits = rc }
end

-- Depois de gravar: a memória vira o gravado + o que entrou nela enquanto gravava (snap = a
-- memória no instante da gravação). Devolve a base nova.
function ProfileSchema.afterWrite(mem: Profile, snap: Synced, wrote: Synced): Synced
	mem.xp = wrote.xp + (mem.xp - snap.xp)
	mem.credits = wrote.credits + (mem.credits - snap.credits)
	mem.respawnCredits = wrote.respawnCredits + (mem.respawnCredits - snap.respawnCredits)
	return { xp = wrote.xp, credits = wrote.credits, respawnCredits = wrote.respawnCredits }
end

-- Recibo de compra (puro): aplica uma única vez por PurchaseId. Devolve true se aplicou agora.
function ProfileSchema.applyReceipt(p: Profile, purchaseId: string, now: number, mutate: (Profile) -> ()): boolean
	if p.purchases[purchaseId] then
		return false
	end
	mutate(p)
	p.purchases[purchaseId] = now
	return true
end

-- O mais novo de dois estados da recompensa (perfil em memória x salvo por outro servidor)
function ProfileSchema.newerDaily(a: Daily, b: Daily): Daily
	if b.lastDay > a.lastDay or (b.lastDay == a.lastDay and b.total > a.total) then
		return { run = b.run, lastDay = b.lastDay, total = b.total }
	end
	return { run = a.run, lastDay = a.lastDay, total = a.total }
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
	-- v1 → v2: sem "daily"/"earned" no salvo, os padrões acima ficam (nada a converter)
	p.daily = ProfileSchema.sanitizeDaily(raw.daily)
	p.earned = ProfileSchema.sanitizeEarned(raw.earned)
	-- v2 → v3: sem os campos, XP zero, a verba inicial de créditos e nada comprado. Créditos
	-- corrompidos (não número) viram zero: a verba inicial só sai uma vez (campo ausente).
	p.xp = math.clamp(int(raw.xp) or 0, 0, ProfileSchema.MAX_XP)
	p.credits = if raw.credits == nil
		then Progression.START_CREDITS
		else math.clamp(int(raw.credits) or 0, 0, Progression.MAX_CREDITS)
	p.gear = ProfileSchema.sanitizeGear(raw.gear, true)
	p.gearOn = ProfileSchema.sanitizeGear(raw.gearOn, false)
	p.respawnCredits = math.clamp(int(raw.respawnCredits) or 0, 0, ProfileSchema.MAX_RESPAWN_CREDITS)
	-- sem `skins` (perfil de antes das skins): nada comprado, nada equipado
	p.skins = ProfileSchema.sanitizeSkins(raw.skins)
	return p
end

return ProfileSchema
