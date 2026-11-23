--!strict
-- D-99: tira os braços de dentro do corpo nos usos de item. Para cada chave de 3ª pessoa do
-- Shared/ItemAnim (mão direita e esquerda, no espaço da UpperTorso do corpo gravado), mede no
-- simulador do Shared/ArmIK (IK de dois ossos com os polos da carta, tronco reto e curvado como no
-- clipe) quanto o braço entra no corpo; se passar de LIMITE, procura o menor deslocamento da mão
-- (para a frente, para fora, para cima) que deixa o braço fora, dentro do alcance (ItemAnim.reach), e
-- REGRAVA as chaves no ItemAnim.luau. Uso (a partir de vantuong65):
--   lune run tools/anim/itens_fora.luau          (mede e regrava)
--   lune run tools/anim/itens_fora.luau medir    (só mede)
local fs = require("@lune/fs")
local process = require("@lune/process")

local ArmIK = require("../../src/ReplicatedStorage/Shared/ArmIK")
local ItemAnim = require("../../src/ReplicatedStorage/Shared/ItemAnim")

local M = 0.28
local LIMITE = 0.006 / M -- 0,6 cm (o teste aceita 2,5 cm no clipe; a folga cobre a interpolação e a mão do clipe)
-- curvatura do tronco de cada clipe (tools/anim/retarget.py ITEM_CLIPS), graus
local BEND = {
	bandage = 10,
	tourniquet = 25,
	bandage_other = 35,
	treat = 35,
	revive = 40,
	radio = 0,
	binoculars = 0,
	shovel = 25,
	canteen = -5,
}
local POLES = ItemAnim.POLES

local function depthOf(side: string, p: { number }, bend: number): number
	local worst = 0
	for _, b in { 0, bend } do
		local body = ArmIK.body(0, math.rad(b))
		local a = ArmIK.arm(side, p, POLES[side])
		for _, part in { a.upper, a.fore, a.hand } do
			worst = math.max(worst, ArmIK.depth(part, body))
		end
	end
	return worst
end

local function fix(side: string, p: { number }, bend: number): ({ number }, number)
	local q = ItemAnim.reach(p, side)
	local d0 = depthOf(side, q, bend)
	if d0 <= LIMITE then
		return q, d0
	end
	local out = if side == "R" then 1 else -1
	local best, bestCost, bestD = q, math.huge, d0
	for dz = 0, 6 do
		for dx = 0, 5 do
			for dy = -2, 3 do
				local cand = ItemAnim.reach({ q[1] + out * dx * 0.08, q[2] + dy * 0.08, q[3] - dz * 0.08 }, side)
				local d = depthOf(side, cand, bend)
				local cost = (cand[1] - q[1]) ^ 2 + (cand[2] - q[2]) ^ 2 + (cand[3] - q[3]) ^ 2
				if d <= LIMITE and cost < bestCost then
					best, bestCost, bestD = cand, cost, d
				end
			end
		end
	end
	return best, bestD
end

local function r3(x: number): number
	return math.round(x * 1000) / 1000
end

local function fmt(v: { number }): string
	return string.format("{ %s, %s, %s }", tostring(r3(v[1])), tostring(r3(v[2])), tostring(r3(v[3])))
end

local only = process.args[1] == "medir"
local fixed: { [string]: { { string } } } = {}
local worstAll = 0
for name, a in ItemAnim.ANIMS do
	local bend = BEND[name] or 0
	local keys = {}
	for _, k in a.tp do
		local r, l = k.r, k.l
		local dr, dl = 0, 0
		if a.right then
			r, dr = fix("R", k.r, bend)
		end
		if a.left then
			l, dl = fix("L", k.l, bend)
		end
		worstAll = math.max(worstAll, dr, dl)
		table.insert(keys, { fmt(r), fmt(l) })
		local moved = (a.right and (r[1] ~= k.r[1] or r[2] ~= k.r[2] or r[3] ~= k.r[3]))
			or (a.left and (l[1] ~= k.l[1] or l[2] ~= k.l[2] or l[3] ~= k.l[3]))
		if moved or dr > LIMITE or dl > LIMITE then
			print(
				string.format(
					"%-14s t=%-5s R %s  L %s  (%.1f / %.1f cm)",
					name,
					tostring(k.t),
					fmt(r),
					fmt(l),
					dr * M * 100,
					dl * M * 100
				)
			)
		end
	end
	fixed[name] = keys
end
print(string.format("pior depois: %.1f cm", worstAll * M * 100))
-- o caminho ENTRE as chaves (interpolação do jogo e do clipe, 30 quadros/s)
for name, a in ItemAnim.ANIMS do
	local bend = BEND[name] or 0
	local worst, at = 0, ""
	for i = 0, math.floor(a.dur * 30) do
		local t = i / 30
		local r, l = ItemAnim.sample(a.tp, t)
		for side, p in { R = r, L = l } do
			if (side == "R" and a.right) or (side == "L" and a.left) then
				local d = depthOf(side, ItemAnim.reach(p, side), bend)
				if d > worst then
					worst, at = d, string.format("%s em %.2f s", side, t)
				end
			end
		end
	end
	if worst > LIMITE then
		print(string.format("caminho %-14s %.1f cm (%s)", name, worst * M * 100, at))
	end
end
if only then
	return
end

-- regrava as chaves "tp" do ItemAnim.luau, na ordem, mantendo tempo, giro e comentário
local path = "src/ReplicatedStorage/Shared/ItemAnim.luau"
local lines = string.split(fs.readFile(path), "\n")
local cur: string? = nil
local inTp = false
local idx = 0
for i, line in lines do
	local anim = string.match(line, "^\t([%w_]+) = {%s*$")
	if anim and ItemAnim.ANIMS[anim] then
		cur, inTp, idx = anim, false, 0
	elseif cur and string.match(line, "^\t\ttp = {") then
		inTp, idx = true, 0
	elseif inTp and string.match(line, "^\t\t},") then
		inTp = false
	elseif inTp and cur then
		local pre, t, rest = string.match(line, "^(%s*k%()([%d%.]+), (.*)$")
		if pre and t and rest then
			idx += 1
			local key = fixed[cur][idx]
			-- o que vem depois das duas mãos (giro opcional, ")," e comentário); mão escrita como
			-- vetor ou como nome (CHEST_R) vira o número corrigido
			local function skip(s: string): string
				s = string.gsub(s, "^%s*", "")
				if string.sub(s, 1, 1) == "{" then
					local e = string.find(s, "}", 1, true) :: number
					return string.sub(s, e + 1)
				end
				return (string.gsub(s, "^[%w_]+", ""))
			end
			local afterR = skip(rest)
			local tail = skip((string.gsub(afterR, "^%s*,", "")))
			lines[i] = pre .. t .. ", " .. key[1] .. ", " .. key[2] .. tail
		end
	end
end
fs.writeFile(path, table.concat(lines, "\n"))
print("regravado:", path)
