--!strict
-- Tela de baixa (pedido do dono, 2026-11-11). Realismo da Parte 9.5: sem killcam e sem o nome de
-- quem atirou. A causa diz só o que o soldado perceberia: o tipo de arma pelo som (Parte 9.8: "cada
-- facção reconhece a arma inimiga pelo som"), a direção em 8 rumos e a distância arredondada como
-- se estima de ouvido ("Abatido por fuzil, ~120 m a nordeste"). Módulo puro (tests/luau/modo.luau).
local Casualty = {}

-- rumo de onde veio o tiro, a partir de quem caiu: 8 setores de 45° (X = leste, Z = sul no jogo)
Casualty.BEARINGS = { "norte", "nordeste", "leste", "sudeste", "sul", "sudoeste", "oeste", "noroeste" }

function Casualty.bearing(dx: number, dz: number): string
	local a = math.deg(math.atan2(dx, -dz)) -- 0 = norte, 90 = leste
	if a < 0 then
		a += 360
	end
	return Casualty.BEARINGS[math.floor((a + 22.5) / 45) % 8 + 1]
end

-- distância de ouvido: grosseira e mais grosseira quanto mais longe
function Casualty.roundDistance(m: number): number
	local step = if m < 50 then 5 elseif m < 150 then 10 elseif m < 400 then 25 elseif m < 1000 then 50 else 100
	return math.max(step, math.floor(m / step + 0.5) * step)
end

local WEAPON = {
	rifle = "fuzil",
	mg = "metralhadora",
	pistol = "pistola",
	launcher = "lança-granadas",
}

-- explosivo pelo id do ExplosionService (Shared/Explosive)
local EXPLOSIVE = {
	mortar_81 = "morteiro",
	mortar_82 = "morteiro",
	naval_5in = "tiro naval",
	bomb_250lb = "bomba de avião",
	he_90 = "canhão de tanque",
	heat_106 = "canhão sem recuo",
	pg2 = "foguete",
	rocket_35 = "foguete",
	grenade_us = "granada",
	grenade_vc = "granada",
}

export type Cause = {
	kind: string, -- "shot" | "explosion" | "melee" | "unknown"
	weaponKind: string?, -- rifle | mg | pistol | launcher (tiro)
	explosive: string?, -- id do explosivo
	melee: string?, -- golpe (Shared/Melee: estocada, lado, baioneta, coronhada)
	blade: string?, -- faca de quem golpeou (Melee.KNIFE: kabar = faca, dao = facão)
	dx: number?, -- da vítima até a origem (studs)
	dz: number?,
	studM: number?,
}

-- arma branca pelo golpe (D-94): faca ou facão (pela faca do lado), baioneta ou coronhada
function Casualty.meleeWord(attack: string?, blade: string?): string
	if attack == "baioneta" then
		return "baioneta"
	elseif attack == "coronhada" then
		return "coronhada"
	elseif attack == "estocada" or attack == "lado" then
		return if blade == "dao" then "facão" else "faca"
	end
	return "arma branca"
end

function Casualty.weaponWord(kind: string?): string
	return if kind then WEAPON[kind] or "arma de fogo" else "arma de fogo"
end

function Casualty.explosiveWord(id: string?): string
	return if id then EXPLOSIVE[id] or "explosão" else "explosão"
end

-- Linha principal da causa. downed = ainda caído (a frase fica no gerúndio do ferimento).
function Casualty.text(c: Cause?, downed: boolean?): string
	-- corpo a corpo: sem rumo nem distância (é ali mesmo)
	if c and c.kind == "melee" then
		local word = Casualty.meleeWord(c.melee, c.blade)
		return if downed
			then string.format("Ferido a %s, corpo a corpo", word)
			else string.format("Abatido a %s, corpo a corpo", word)
	end
	if not c or c.kind == "unknown" or c.dx == nil or c.dz == nil then
		return if downed then "Ferido — origem não identificada" else "Morto em ação — origem não identificada"
	end
	local m = math.sqrt(c.dx * c.dx + c.dz * c.dz) * (c.studM or 0.28)
	local dist = Casualty.roundDistance(m)
	local bearing = Casualty.bearing(c.dx, c.dz)
	-- a frase inteira é um modelo (o dicionário de idiomas traduz o modelo, não as peças)
	if c.kind == "explosion" then
		local word = Casualty.explosiveWord(c.explosive)
		if m < 6 then
			return if downed
				then string.format("Ferido por estilhaços de %s, a poucos metros", word)
				else string.format("Estilhaços de %s, a poucos metros", word)
		end
		return if downed
			then string.format("Ferido por estilhaços de %s, ~%d m a %s", word, dist, bearing)
			else string.format("Estilhaços de %s, ~%d m a %s", word, dist, bearing)
	end
	local weapon = Casualty.weaponWord(c.weaponKind)
	return if downed
		then string.format("Ferido por %s, ~%d m a %s", weapon, dist, bearing)
		else string.format("Abatido por %s, ~%d m a %s", weapon, dist, bearing)
end

-- Linha curta das telas de ferido e de baixa (estilo novo, 2026-11-11): o mesmo que text(), mas a
-- origem desconhecida vira "Causa desconhecida" (curto e honesto; o "origem não identificada" de
-- text() fica para quem já o usa).
function Casualty.short(c: Cause?, downed: boolean?): string
	if not c or c.kind == "unknown" or (c.kind ~= "melee" and (c.dx == nil or c.dz == nil)) then
		return "Causa desconhecida"
	end
	return Casualty.text(c, downed)
end

-- Grupo data-hora de 1965 (fuso H = UTC+8, como o AfterAction): dia 18, hora local do jogo.
function Casualty.dtg(clockHours: number): string
	local total = math.floor(clockHours * 60 + 0.5) % 1440
	return string.format("18%02d%02dH AUG 65", total // 60, total % 60)
end

-- "1 min 12 s" (tempo em campo)
function Casualty.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	if s < 60 then
		return string.format("%d s", s)
	end
	return string.format("%d min %02d s", s // 60, s % 60)
end

-- Pulso (bpm) de quem está caído sangrando: sobe com o tempo (choque), de 110 a 150. t em [0, 1]
-- (fração da janela de 60 s já passada). Valores de projeto, sem fonte clínica.
function Casualty.pulse(t: number): number
	return 110 + 40 * math.clamp(t, 0, 1)
end

return Casualty
