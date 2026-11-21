--!strict
-- Arrozal (D-74): regras puras do arroz nos 1.155 tabuleiros d'água do mapa (78% da área).
-- O servidor põe, em cada tabuleiro plantado, um "dossel": uma placa verde na altura do arroz,
-- que é o que se vê de longe. O cliente esconde o dossel dos tabuleiros perto da câmera e cobre
-- o tabuleiro com ladrilhos de arroz em cartões (RiceField.client): perto, o alto; longe, o baixo.
-- Tudo sai da posição do tabuleiro, então todos os jogadores veem o mesmo arroz, no mesmo lugar.
-- Em agosto de 1965 (Starlite, 18/08) a lavoura de verão-outono estava em pé, ~50 dias depois do
-- transplante; uma parte dos tabuleiros ainda com muda nova ou em pousio (DESIGN, sem fonte de
-- proporção: 60/25/15 é escolha de projeto).
local RiceField = {}

RiceField.TILE = 16 -- studs (4,5 m): lado nominal do ladrilho
RiceField.INSET = 1 -- studs entre o arroz e a borda do tabuleiro (pé do dique)
RiceField.NEAR = 30 / 0.28 -- até aqui o ladrilho alto (96 cartões)
RiceField.FAR = 65 / 0.28 -- até aqui há ladrilhos; além, o dossel
RiceField.BASE = 0.35 -- studs: o pé do arroz fica abaixo da água
RiceField.HEIGHT = { mature = 1.0, young = 0.55 } :: { [string]: number }
-- altura do dossel (studs acima da água) na escala 1: onde as folhas fecham, vista de longe
RiceField.CANOPY_Y = 1.6

-- Inteiro determinístico em [0, 1000) a partir de inteiros (sem estado, igual em todo lugar).
local function hash(a: number, b: number, c: number?): number
	local h = bit32.bxor(bit32.band(a * 73856093, 0x7fffffff), bit32.band(b * 19349663, 0x7fffffff))
	h = bit32.bxor(h, bit32.band((c or 0) * 83492791, 0x7fffffff))
	h = bit32.band(h * 2654435761, 0xffffffff)
	return bit32.rshift(h, 8) % 1000
end
RiceField.hash = hash

-- Estado do tabuleiro pelo centro (studs): "mature" 60%, "young" 25%, "fallow" 15%.
function RiceField.kind(x: number, z: number): string
	local h = hash(math.floor(x), math.floor(z))
	if h < 600 then
		return "mature"
	elseif h < 850 then
		return "young"
	end
	return "fallow"
end

-- Grade de ladrilhos de um tabuleiro sx x sz (studs, já sem a margem): número de colunas e
-- linhas e o lado de cada ladrilho (entre 2/3 e 4/3 do nominal, cobrindo tudo sem sobra).
function RiceField.grid(sx: number, sz: number): (number, number, number, number)
	local nx = math.max(1, math.floor(sx / RiceField.TILE + 0.5))
	local nz = math.max(1, math.floor(sz / RiceField.TILE + 0.5))
	return nx, nz, sx / nx, sz / nz
end

-- Ladrilho girado 180° ou não (as linhas continuam alinhadas; quebra a repetição).
function RiceField.flip(fx: number, fz: number, i: number, j: number): boolean
	return hash(math.floor(fx) + i * 7, math.floor(fz) + j * 13, i + j) % 2 == 1
end

-- Distância (studs) de um ponto (no espaço do tabuleiro) ao retângulo do tabuleiro.
function RiceField.distToRect(lx: number, lz: number, sx: number, sz: number): number
	local dx = math.max(math.abs(lx) - sx / 2, 0)
	local dz = math.max(math.abs(lz) - sz / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- "hi", "lo" ou nil (longe: fica o dossel)
function RiceField.lod(dist: number): string?
	if dist < RiceField.NEAR then
		return "hi"
	elseif dist < RiceField.FAR then
		return "lo"
	end
	return nil
end

return RiceField
