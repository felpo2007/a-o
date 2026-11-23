--!strict
-- D-252 (dono: "use tool box from roblox for audios"): sons trocados pelas gravações da biblioteca
-- licenciada da Roblox (Pro Sound Effects). Só essa biblioteca entra: envios de outros usuários podem não
-- tocar no jogo publicado e muitos são cópias de outros jogos (regra do projeto).
-- As gravações têm nível diferente do som antigo. O ganho iguala o volume percebido, a partir do
-- PlaybackLoudness medido no Studio com Volume 1 (média nos laços, pico nos sons curtos):
--   arrozal 45,9 contra 66; vila 12,8 contra 61; artilharia ao longe, pico 57 contra 389.
-- O ID sintetizado anterior fica em `assets/roblox_ids.json`, na chave `Sounds.<nome>_sintese`.
local SonsBiblioteca = {}

SonsBiblioteca.IDS = {
	ambience_paddy_morning = 9112831058, -- mata com pássaros e insetos, em laço
	ambience_village = 9112802806, -- pássaros ativos, em laço
	mortar_launch = 9125698534, -- saída do morteiro, com o assobio
	naval_distant = 9113169432, -- artilharia distante
	faca_saque = 9116197246, -- faca saindo da bainha de couro
	bandage = 9113836270, -- pano rasgando
} :: { [string]: number }

SonsBiblioteca.GANHO = {
	ambience_paddy_morning = 1.4,
	ambience_village = 4.8,
	naval_distant = 5,
} :: { [string]: number }

-- O multiplicador de volume do som `chave` (1 quando ele não precisa de ajuste)
function SonsBiblioteca.ganho(chave: string): number
	return SonsBiblioteca.GANHO[chave] or 1
end

return SonsBiblioteca
