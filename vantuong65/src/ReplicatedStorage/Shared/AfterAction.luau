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
local VERB = {
	neutralized = "perde o controle de",
	captured = "toma",
	advanced = "a frente passa para",
	overrun = "toma o último setor:",
}

local function sectorName(e: Entry): string
	return if e.name then string.format("S%d (%s)", e.sector or 0, e.name) else "S" .. tostring(e.sector or 0)
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
		local e = list[i]
		local who = TEAM[e.team or ""] or (e.team or "?")
		local text
		if e.kind == "neutralized" then
			text = string.format("%s %s %s.", who, VERB.neutralized, sectorName(e))
		elseif e.kind == "advanced" then
			text = string.format("%s %s.", VERB.advanced, sectorName(e))
		elseif VERB[e.kind] then
			text = string.format("%s %s %s.", who, VERB[e.kind], sectorName(e))
		else
			text = e.kind
		end
		table.insert(out, string.format("   %s  %s", AfterAction.dtg(r, e.t), text))
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
		table.insert(out, string.format("   Combate mais pesado: S%d (%d mortos).", worst, worstN))
	end
	table.insert(out, "")
	table.insert(out, "3. RESULTADO")
	local w = r.winner
	local res = if w == "US" then "Vitória do USMC." elseif w == "VC" then "Vitória do VC." else "Empate."
	if r.duration then
		res ..= string.format(" Duração: %d min.", math.floor(r.duration / 60 + 0.5))
	end
	table.insert(out, "   " .. res)
	if r.owner then
		local o = {}
		for s, own in r.owner do
			table.insert(
				o,
				string.format("S%d %s", s, if own == "US" then "USMC" elseif own == "VC" then "VC" else "—")
			)
		end
		table.insert(out, "   Setores no fim: " .. table.concat(o, " · "))
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
