--!strict
-- Dano, explosão e destroço dos veículos (D-197; prompt de jogabilidade, item 16). Módulo PURO (tests/
-- luau/destroco.luau). O servidor (VehicleService.destroyVehicle) decide o dano uma vez só; o cliente
-- (Controllers/VeiculoDano.client) desenha: fumaça e fogo pelo dano, a explosão do tamanho do veículo
-- e o destroço queimando até sumir. O efeito não mexe em dano nem em juntas.
local VeiculoDano = {}

-- Porte pela massa da ficha: o tamanho da explosão, dos pedaços e do som.
export type Porte = "leve" | "medio" | "pesado"
function VeiculoDano.porte(massKg: number): Porte
	if massKg < 3000 then
		return "leve" -- jipe M151, Peugeot 403
	elseif massKg < 15000 then
		return "medio" -- caminhão M35, Ontos, UH-34D
	end
	return "pesado" -- M48A3, LVTP-5
end

-- escala: tamanho do efeito (1 = granada de mão, como o ExplosionFx); fragmentos: pedaços que voam
-- (limitados); volume e tom do som; fumacaS: o destroço fumega (o servidor o tira aos 30 s).
-- PLACEHOLDER de efeito (a olho no Studio).
export type Explosao = {
	escala: number,
	fragmentos: number,
	volume: number,
	tom: number,
	fumacaS: number,
	luz: number, -- alcance da luz (m)
}
VeiculoDano.EXPLOSAO = {
	leve = { escala = 2.2, fragmentos = 5, volume = 1.4, tom = 1.0, fumacaS = 20, luz = 18 },
	medio = { escala = 3.0, fragmentos = 7, volume = 1.7, tom = 0.85, fumacaS = 25, luz = 24 },
	pesado = { escala = 3.8, fragmentos = 10, volume = 2.0, tom = 0.7, fumacaS = 28, luz = 30 },
} :: { [string]: Explosao }

-- Estágio do dano pela integridade (100 = inteiro): fumaça clara do motor, depois fogo, e o destroço.
export type Estagio = "inteiro" | "fumaca" | "fogo" | "destroco"
VeiculoDano.FUMACA_ATE = 60
VeiculoDano.FOGO_ATE = 25
function VeiculoDano.estagio(integridade: number?, destruido: boolean): Estagio
	if destruido then
		return "destroco"
	end
	local i = integridade or 100
	if i <= VeiculoDano.FOGO_ATE then
		return "fogo"
	elseif i <= VeiculoDano.FUMACA_ATE then
		return "fumaca"
	end
	return "inteiro"
end

-- Ferimento de quem está dentro quando o veículo é destruído: lugar fechado (dentro do casco, cabine,
-- helicóptero) morre na explosão; lugar aberto (cabeça fora da escotilha, jipe, caçamba, tropa em cima)
-- leva a onda e os estilhaços no tronco, abaixo do que derruba (Medical.C.torsoDownJ = 1500 J), e é
-- posto para fora. Antes todos levavam 3000 J no tronco: na regra médica isso só derruba, e o ferido
-- ficava caído e sentado no destroço até ele sumir.
export type Ferimento = { zona: string, energiaJ: number, mata: boolean }
function VeiculoDano.ferimento(aberto: boolean, heli: boolean): Ferimento
	if aberto and not heli then
		return { zona = "torso", energiaJ = 900, mata = false }
	end
	return { zona = "head", energiaJ = 3000, mata = true }
end

-- D-246 (dono: "estou morrendo por tiros dentro do tanque"): em lugar fechado de um blindado o soldado
-- fica atrás do casco. Bala e estilhaço não chegam nele; o que mata a tripulação é destruir o veículo.
-- Jipe, caminhão e helicóptero têm chapa fina e continuam sem essa proteção.
function VeiculoDano.blindado(kind: any): boolean
	return kind == "tracked" or kind == "amphibious"
end

function VeiculoDano.naBlindagem(hum: any): boolean
	local seat = hum and hum.SeatPart
	if not seat or seat:GetAttribute("Open") == true then
		return false
	end
	local m = seat:FindFirstAncestorWhichIsA("Model")
	return m ~= nil and VeiculoDano.blindado(m:GetAttribute("Kind")) and m:GetAttribute("Destroyed") ~= true
end

-- Fumaça e fogo do destroço com o tempo (1 no começo, 0 no fim de fumacaS): a fumaça preta fica, o
-- fogo some antes.
function VeiculoDano.queima(t: number, fumacaS: number): (number, number)
	local u = math.clamp(t / math.max(fumacaS, 1e-3), 0, 1)
	local fumaca = 1 - u * u
	local fogo = math.clamp(1 - u / 0.6, 0, 1)
	return fumaca, fogo
end

return VeiculoDano
