--!strict
-- Relatório pós-ação (Parte 11, "Lançamento"): linha do tempo, baixas e avanços no estilo dos
-- relatórios militares de 1965. Hora em grupo data-hora (DTG): dia, hora e minuto + fuso "H"
-- (UTC+8, o horário local usado em D-27), mês e ano: "180631H AUG 65". Módulo puro.
local AfterAction = {}

AfterAction.DAY = 18 -- 18 de agosto de 1965, dia do desembarque
AfterAction.MAX_ENTRIES = 60 -- o relatório cabe numa tela

export type Entry = { t: number, kind: string, sector: number?, team: string?, name: string? }
export type Report = {
	mode: string,
	startClock: number, -- hora local do início (ex.: 6.5 = 06:30)
	entries: { Entry },
	kia: { [string]: { [number]: number } }, -- facção -> setor (0 = fora) -> mortos
	winner: string?,
	duration: number?,
	owner: { string }?,
}

function AfterAction.new(mode: string, startClock: number): Report
	return { mode = mode, startClock = startClock, entries = {}, kia = { US = {}, VC = {} } }
end

-- DTG a partir do segundo t da partida
function AfterAction.dtg(r: Report, t: number): string
	local total = math.floor(r.startClock * 60 + t / 60) -- minutos desde 00:00 do dia 18
	local day = AfterAction.DAY + total // 1440
	local m = total % 1440
	return string.format("%02d%02d%02dH AUG 65", day, m // 60, m % 60)
end

function AfterAction.event(r: Report, t: number, kind: string, sector: number?, team: string?, name: string?)
	table.insert(r.entries, { t = t, kind = kind, sector = sector, team = team, name = name })
end

function AfterAction.casualty(r: Report, faction: string, sector: number?)
	local f = r.kia[faction]
	if f then
		local s = sector or 0
		f[s] = (f[s] or 0) + 1
	end
end

function AfterAction.total(r: Report, faction: string): number
	local n = 0
	local f: { [number]: number } = r.kia[faction] or {}
	for _, v in f do
		n += v
	end
	return n
end

local TEAM = { US = "USMC", VC = "VC" }

-- letra do setor (v41, pedido do dono: "troque os objetivos por A B C D E"; Shared/Front.letra)
local function letra(s: number): string
	return if s >= 1 and s <= 26 then string.char(64 + s) else "?"
end

-- Cada linha da linha do tempo é um modelo inteiro em português (hora, lado, setor e nome do setor
-- entram nos %): o dicionário de idiomas traduz o modelo, não as peças.
local MODELS = {
	neutralized = {
		named = "   %s  %s perde o controle de %s (%s).",
		plain = "   %s  %s perde o controle de %s.",
	},
	captured = {
		named = "   %s  %s toma %s (%s).",
		plain = "   %s  %s toma %s.",
	},
	overrun = {
		named = "   %s  %s toma o último setor: %s (%s).",
		plain = "   %s  %s toma o último setor: %s.",
	},
	advanced = {
		named = "   %s  a frente passa para %s (%s).",
		plain = "   %s  a frente passa para %s.",
	},
}

local function entryLine(r: Report, e: Entry): string
	local when = AfterAction.dtg(r, e.t)
	local sector = letra(e.sector or 0)
	local who = TEAM[e.team or ""] or (e.team or "?")
	if e.kind == "neutralized" then
		return if e.name
			then string.format(MODELS.neutralized.named, when, who, sector, e.name)
			else string.format(MODELS.neutralized.plain, when, who, sector)
	elseif e.kind == "captured" then
		return if e.name
			then string.format(MODELS.captured.named, when, who, sector, e.name)
			else string.format(MODELS.captured.plain, when, who, sector)
	elseif e.kind == "overrun" then
		return if e.name
			then string.format(MODELS.overrun.named, when, who, sector, e.name)
			else string.format(MODELS.overrun.plain, when, who, sector)
	elseif e.kind == "advanced" then
		return if e.name
			then string.format(MODELS.advanced.named, when, sector, e.name)
			else string.format(MODELS.advanced.plain, when, sector)
	end
	return string.format("   %s  %s", when, e.kind)
end

-- Linhas do relatório: cabeçalho, linha do tempo (até MAX_ENTRIES, mais recentes por último),
-- baixas e resultado.
function AfterAction.lines(r: Report): { string }
	local out = {
		"RELATÓRIO PÓS-AÇÃO — OPERAÇÃO STARLITE (VẠN TƯỜNG)",
		string.format("Modo: %s. Início %s.", r.mode, AfterAction.dtg(r, 0)),
		"",
		"1. LINHA DO TEMPO",
	}
	local list = r.entries
	local first = math.max(1, #list - AfterAction.MAX_ENTRIES + 1)
	if first > 1 then
		table.insert(out, string.format("   (%d registros anteriores omitidos)", first - 1))
	end
	for i = first, #list do
		table.insert(out, entryLine(r, list[i]))
	end
	if #list == 0 then
		table.insert(out, "   Sem mudança de controle nos setores.")
	end
	table.insert(out, "")
	table.insert(out, "2. BAIXAS (MORTOS)")
	table.insert(out, string.format("   USMC: %d    VC: %d", AfterAction.total(r, "US"), AfterAction.total(r, "VC")))
	local worst, worstN = nil :: number?, 0
	for s = 1, 5 do
		local n = (r.kia.US[s] or 0) + (r.kia.VC[s] or 0)
		if n > worstN then
			worst, worstN = s, n
		end
	end
	if worst then
		table.insert(out, string.format("   Combate mais pesado: %s (%d mortos).", letra(worst), worstN))
	end
	table.insert(out, "")
	table.insert(out, "3. RESULTADO")
	local w = r.winner
	local mins = if r.duration then math.floor(r.duration / 60 + 0.5) else nil
	local res
	if w == "US" then
		res = if mins then string.format("   Vitória do USMC. Duração: %d min.", mins) else "   Vitória do USMC."
	elseif w == "VC" then
		res = if mins then string.format("   Vitória do VC. Duração: %d min.", mins) else "   Vitória do VC."
	else
		res = if mins then string.format("   Empate. Duração: %d min.", mins) else "   Empate."
	end
	table.insert(out, res)
	if r.owner then
		local o = {}
		for s, own in r.owner do
			table.insert(
				o,
				string.format("%s %s", letra(s), if own == "US" then "USMC" elseif own == "VC" then "VC" else "—")
			)
		end
		table.insert(out, string.format("   Setores no fim: %s", table.concat(o, " · ")))
	end
	return out
end

-- Fecha o relatório
function AfterAction.finish(r: Report, winner: string, duration: number, owner: { string })
	r.winner = winner
	r.duration = duration
	r.owner = table.clone(owner)
end

return AfterAction
