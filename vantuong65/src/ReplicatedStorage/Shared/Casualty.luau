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
	kind: string, -- "shot" | "explosion" | "unknown"
	weaponKind: string?, -- rifle | mg | pistol | launcher (tiro)
	explosive: string?, -- id do explosivo
	dx: number?, -- da vítima até a origem (studs)
	dz: number?,
	studM: number?,
}

function Casualty.weaponWord(kind: string?): string
	return if kind then WEAPON[kind] or "arma de fogo" else "arma de fogo"
end

function Casualty.explosiveWord(id: string?): string
	return if id then EXPLOSIVE[id] or "explosão" else "explosão"
end

-- Linha principal da causa. downed = ainda caído (a frase fica no gerúndio do ferimento).
function Casualty.text(c: Cause?, downed: boolean?): string
	if not c or c.kind == "unknown" or c.dx == nil or c.dz == nil then
		return if downed then "Ferido — origem não identificada" else "Morto em ação — origem não identificada"
	end
	local m = math.sqrt(c.dx * c.dx + c.dz * c.dz) * (c.studM or 0.28)
	local where = string.format("~%d m a %s", Casualty.roundDistance(m), Casualty.bearing(c.dx, c.dz))
	if c.kind == "explosion" then
		local word = Casualty.explosiveWord(c.explosive)
		if m < 6 then
			where = "a poucos metros"
		end
		return string.format("%s de %s, %s", if downed then "Ferido por estilhaços" else "Estilhaços", word, where)
	end
	return string.format(
		"%s por %s, %s",
		if downed then "Ferido" else "Abatido",
		Casualty.weaponWord(c.weaponKind),
		where
	)
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
