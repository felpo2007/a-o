--!strict
-- Arma do inimigo (Parte 11, "Lançamento"): a arma de quem morre fica no chão só com a munição do
-- carregador. Quem pega troca pela própria arma (que fica no chão com o que tinha). A caixa de
-- munição do seu lado não reabastece arma do outro lado. Módulo puro.
local Pickup = {}

Pickup.TTL_S = 120 -- a arma caída some depois de 2 min (limite de peças no mapa)

export type Ammo = { weapon: string, mag: number, spare: number }

-- O que cai de quem morreu: a arma com o carregador que estava nela, sem os sobressalentes.
-- Arma vazia não cai (não haveria motivo para pegar).
function Pickup.dropOnDeath(a: Ammo?): Ammo?
	if not a or a.mag <= 0 then
		return nil
	end
	return { weapon = a.weapon, mag = a.mag, spare = 0 }
end

-- Pegar `p` com a arma `current` na mão: devolve a nova munição e o que fica no chão.
function Pickup.swap(current: Ammo?, p: Ammo): (Ammo, Ammo?)
	local new = { weapon = p.weapon, mag = p.mag, spare = p.spare }
	local dropped = if current then { weapon = current.weapon, mag = current.mag, spare = current.spare } else nil
	return new, dropped
end

-- Caixa de munição: só para arma do próprio lado.
function Pickup.canRefill(weaponFaction: string?, playerFaction: string?): boolean
	return weaponFaction ~= nil and weaponFaction == playerFaction
end

return Pickup
