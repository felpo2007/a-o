--!strict
-- Sinal dos eventos de jogo para a campanha (missões, medalhas, passe, ordens do comandante;
-- 2026-11-12). Quem já concede XP dispara aqui (ProgressionService: abate, assistência, captura,
-- reanimação, tratamento, tempo em campo, fim de partida; DailyRewardService: selo do dia) e o
-- CampanhaService ouve. Sem dependência circular: este módulo não requer ninguém.
-- Eventos (nome, dados):
--   kill { weapon, kind, victimBot }   assist {}   capture { sector }   neutralize { sector }
--   revive { target }   treat {}   bandage {}   was_revived {}   time { seconds }
--   match_end { result = "win"|"draw"|"loss", seconds, faction }   daily_seal { day }
local CampanhaEventos = {}

type Fn = (player: Player, name: string, data: { [string]: any }) -> ()
local listeners: { Fn } = {}

function CampanhaEventos.connect(fn: Fn)
	table.insert(listeners, fn)
end

function CampanhaEventos.fire(player: Player, name: string, data: { [string]: any }?)
	local d = data or {}
	for _, fn in listeners do
		task.spawn(fn, player, name, d)
	end
end

return CampanhaEventos
