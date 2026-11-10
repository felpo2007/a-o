--!strict
-- GERADO por tools/weapon_landmarks.py a partir dos GLB das armas. Não editar à mão.
-- Pontos no espaço da MeshPart publicada (studs, centro da caixa na origem).
-- forward = eixo que aponta para a boca. lowX = menor X da malha com o punho na
-- origem e a boca em −Z (arma caída de lado). lengthM = comprimento da malha (m).
export type Art = {
	forward: string,
	muzzle: Vector3,
	sight: Vector3,
	grip: Vector3,
	support: Vector3,
	lowX: number,
	lengthM: number,
}
local WeaponArt: { [string]: Art } = {
	m14 = {
		forward = "+Z",
		muzzle = Vector3.new(0.025, 0.419, 2.011),
		sight = Vector3.new(0.025, 0.561, -0.362),
		grip = Vector3.new(0.025, 0.241, -0.965),
		support = Vector3.new(0.025, 0.277, -0.08),
		lowX = -0.133,
		lengthM = 1.126,
	},
	type56 = {
		forward = "+Z",
		muzzle = Vector3.new(0.042, 0.349, 1.575),
		sight = Vector3.new(0.042, 0.546, -0.063),
		grip = Vector3.new(0.042, 0.17, -0.535),
		support = Vector3.new(0.042, 0.206, 0.157),
		lowX = -0.083,
		lengthM = 0.882,
	},
	sks = {
		forward = "+Z",
		muzzle = Vector3.new(0.076, 0.199, 1.823),
		sight = Vector3.new(0.076, 0.396, -0.328),
		grip = Vector3.new(0.076, 0.02, -0.875),
		support = Vector3.new(0.076, 0.056, -0.073),
		lowX = -0.085,
		lengthM = 1.021,
	},
	m60 = {
		forward = "-Z",
		muzzle = Vector3.new(0.057, 0.109, -1.973),
		sight = Vector3.new(0.057, 0.265, 0.158),
		grip = Vector3.new(0.057, -0.07, 0.75),
		support = Vector3.new(0.057, -0.034, -0.118),
		lowX = -0.338,
		lengthM = 1.105,
	},
	rpd = {
		forward = "+Z",
		muzzle = Vector3.new(0.05, 0.439, 1.852),
		sight = Vector3.new(0.05, 0.488, -0.185),
		grip = Vector3.new(0.05, 0.26, -0.741),
		support = Vector3.new(0.05, 0.296, 0.148),
		lowX = -0.553,
		lengthM = 1.037,
	},
	m79 = {
		forward = "+Z",
		muzzle = Vector3.new(0.001, 0.075, 1.305),
		sight = Vector3.new(0.001, 0.196, 0.183),
		grip = Vector3.new(0.001, -0.104, -0.209),
		support = Vector3.new(0.001, -0.068, 0.366),
		lowX = -0.132,
		lengthM = 0.731,
	},
	m1911 = {
		forward = "-Z",
		muzzle = Vector3.new(0.002, 0.187, -0.386),
		sight = Vector3.new(0.002, 0.271, 0.216),
		grip = Vector3.new(0.002, -0.027, 0.216),
		support = Vector3.new(0.002, -0.027, 0.216),
		lowX = -0.061,
		lengthM = 0.216,
	},
	type54 = {
		forward = "-Z",
		muzzle = Vector3.new(-0.154, 0.203, -0.348),
		sight = Vector3.new(-0.154, 0.264, 0.195),
		grip = Vector3.new(-0.154, -0.011, 0.195),
		support = Vector3.new(-0.154, -0.011, 0.195),
		lowX = -0.057,
		lengthM = 0.195,
	},
	rpg2 = {
		forward = "-X",
		muzzle = Vector3.new(-2.143, 0.016, 0.001),
		sight = Vector3.new(-0.814, 0.688, 0.001),
		grip = Vector3.new(-0.429, -0.306, 0.001),
		support = Vector3.new(0.214, -0.163, 0.001),
		lowX = -0.329,
		lengthM = 1.2,
	},
}

return WeaponArt
