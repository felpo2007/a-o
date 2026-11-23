--!strict
-- Medição do que flutua (pedido do dono, 2026-11-13: "helicópteros estão flutuando no chão" e
-- "conserte tudo que esteja flutuando"). Para cada coisa do mapa, a base VISÍVEL (peças com
-- Transparency < 1, sem Colisao_* e Zona_*) contra o chão (terreno e peças com colisão, fora o
-- próprio modelo) por um raio para baixo no meio e nos 4 cantos da pegada (60% da meia caixa; planta:
-- 0,3 m em volta do pé). Folga = base − chão, em metros: positiva = no ar.
-- Gancho do Studio (servidor): workspace:SetAttribute("VT65DevFlutua", true) imprime no Output, por
-- tipo, quantos foram medidos, quantos têm um canto no ar (> 15 cm), quantos estão inteiros no ar
-- (> 10 cm nos 5 pontos), o pior e a lista dos 15 piores ([VT65 TESTE] flutua ...).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RiceField = require(ReplicatedStorage.Shared.RiceField)

local Flutua = {}
local M = 0.28
Flutua.CORNER_M = 0.15 -- canto no ar: a maior folga passa disto
Flutua.ALL_M = 0.10 -- inteiro no ar: a menor folga passa disto
Flutua.FOOT_M = 0.05 -- pé de soldado no ar
Flutua.heights = {} :: { number } -- altura de cada soldado em pé na última medição (m)

export type Row = {
	kind: string,
	key: string,
	minGap: number, -- m
	maxGap: number, -- m
	hidden: number, -- m: quanto o fundo invisível (colisão, zona) desce abaixo do visível
	pos: Vector3,
}

local function hiddenPart(p: BasePart): boolean
	local n = p.Name
	return p.Transparency >= 0.99 or string.sub(n, 1, 8) == "Colisao_" or string.sub(n, 1, 5) == "Zona_"
end

-- caixa das peças no referencial `frame` (mínimo e máximo locais); visible: só o que se vê
function Flutua.box(m: Instance, frame: CFrame, visible: boolean): (Vector3?, Vector3?)
	local lo: Vector3? = nil
	local hi: Vector3? = nil
	local list: { Instance } = if m:IsA("BasePart") then { m } else m:GetDescendants()
	for _, p in list do
		if p:IsA("BasePart") and not (visible and hiddenPart(p)) then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:ToObjectSpace(p.CFrame):GetComponents()
			local h = p.Size / 2
			local e = Vector3.new(
				math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
				math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
				math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
			)
			local c = Vector3.new(x, y, z)
			lo = if lo then lo:Min(c - e) else c - e
			hi = if hi then hi:Max(c + e) else c + e
		end
	end
	return lo, hi
end

-- referencial só com o giro em Y do pivô
local function yawFrame(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(cf.Position)
	end
	return CFrame.lookAt(cf.Position, cf.Position + flat)
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
params.IgnoreWater = true
local skip: { Instance } = {}
local soldierParams = RaycastParams.new()
soldierParams.FilterType = Enum.RaycastFilterType.Exclude
soldierParams.RespectCanCollide = true
soldierParams.IgnoreWater = true

-- altura do chão (studs) sob (x, z), de `fromY` + 8 para baixo, sem o próprio modelo
function Flutua.ground(x: number, fromY: number, z: number, own: Instance?): number?
	local list = table.clone(skip)
	if own then
		table.insert(list, own)
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(Vector3.new(x, fromY + 8, z), Vector3.new(0, -160, 0), params)
	return if hit then hit.Position.Y else nil
end

-- Trincheira: fica sobre a vala, só os 4 cantos a 45% contam. A boca de túnel não entra: fica dentro
-- do colar do poço (as paredes de peças), e o raio desce pelo poço até o túnel.
-- Ponte: só as duas cabeceiras (a 40% do comprimento), que apoiam nas margens.
local OVER_HOLE: { [string]: boolean } = { trench_section = true }
local SKIP: { [string]: boolean } = { tunnel_entrance = true }
local CORNERS = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
local FIVE = { { 0, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

-- folga (m) da base visível sobre o chão no meio e nos 4 cantos. spread (studs): pegada fixa em volta
-- do pivô (planta); sem ele, 60% da meia caixa visível
function Flutua.measure(m: Instance, frame: CFrame, kind: string, spread: number?): Row?
	local lo, hi = Flutua.box(m, frame, true)
	if not lo or not hi then
		return nil
	end
	local alo = Flutua.box(m, frame, false)
	local bottom = (frame * Vector3.new(0, lo.Y, 0)).Y
	local cx, cz = (lo.X + hi.X) / 2, (lo.Z + hi.Z) / 2
	local hx, hz = (hi.X - lo.X) * 0.3, (hi.Z - lo.Z) * 0.3
	local points = FIVE
	if spread then
		cx, cz, hx, hz = 0, 0, spread, spread
	elseif OVER_HOLE[m.Name] then
		hx, hz, points = (hi.X - lo.X) * 0.45, (hi.Z - lo.Z) * 0.45, CORNERS
	elseif m.Name == "log_bridge" then
		-- o eixo longo da ponte: cabeceiras a 40% do comprimento, no meio da largura
		local alongX = hi.X - lo.X >= hi.Z - lo.Z
		hx = if alongX then (hi.X - lo.X) * 0.4 else 0
		hz = if alongX then 0 else (hi.Z - lo.Z) * 0.4
		points = { { 1, 1 }, { -1, -1 } }
	end
	local mn, mx = math.huge, -math.huge
	for _, o in points do
		local wp = frame * Vector3.new(cx + o[1] * hx, lo.Y, cz + o[2] * hz)
		local g = Flutua.ground(wp.X, bottom, wp.Z, m)
		if g then
			local gap = (bottom - g) * M
			mn, mx = math.min(mn, gap), math.max(mx, gap)
		end
	end
	if mn == math.huge then
		return nil
	end
	local hidden = if alo and alo.Y < lo.Y - 0.02 then (lo.Y - alo.Y) * M else 0
	return { kind = kind, key = m.Name, minGap = mn, maxGap = mx, hidden = hidden, pos = frame.Position }
end

local HOUSE = { "^hut_", "^house_", "^vila_casa", "^parts:" }
local function artKind(m: Instance): string
	if m:GetAttribute("Foliage") then
		return "planta de quintal e vila"
	end
	local n = m.Name
	for _, p in HOUSE do
		if string.match(n, p) then
			return "casa"
		end
	end
	if string.sub(n, 1, 3) == "us_" or string.sub(n, 1, 3) == "vc_" then
		return "base"
	end
	return "objeto"
end

local function pivotOf(m: Instance): CFrame?
	if m:IsA("Model") then
		return m:GetPivot()
	elseif m:IsA("BasePart") then
		return m.CFrame
	end
	return nil
end

-- soldado em pé: o pé (fundo visível) contra o chão sob a HumanoidRootPart
local function soldier(char: Model, rows: { Row }, heights: { number })
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 or hum.Sit or hum.FloorMaterial == Enum.Material.Air then
		return
	end
	if
		hum:GetState() ~= Enum.HumanoidStateType.Running
		and hum:GetState() ~= Enum.HumanoidStateType.RunningNoPhysics
	then
		return
	end
	local frame = yawFrame(root.CFrame)
	local lo, hi = Flutua.box(char, frame, true)
	if not lo or not hi then
		return
	end
	local bottom = (frame * Vector3.new(0, lo.Y, 0)).Y
	-- o soldado pode estar em cima de veículo, tronco ou caixote: aqui conta tudo que tem colisão,
	-- menos os soldados
	local comb = workspace:FindFirstChild("Combatants")
	soldierParams.FilterDescendantsInstances = if comb then { char, comb } else { char }
	local hit = workspace:Raycast(
		Vector3.new(root.Position.X, bottom + 8, root.Position.Z),
		Vector3.new(0, -160, 0),
		soldierParams
	)
	local g = if hit then hit.Position.Y else nil
	if g then
		local gap = (bottom - g) * M
		table.insert(
			rows,
			{ kind = "soldado em pé", key = char.Name, minGap = gap, maxGap = gap, hidden = 0, pos = root.Position }
		)
	end
	-- altura sem o que fica na cabeça (capacete, chapéu): do pé ao topo da Head
	local head = char:FindFirstChild("Head") :: BasePart?
	if head then
		table.insert(heights, (head.Position.Y + head.Size.Y / 2 - bottom) * M)
	end
end

-- Mede tudo. Devolve as linhas por item (para o teste e as fotos).
function Flutua.scan(): { Row }
	local rows: { Row } = {}
	local map = workspace:FindFirstChild("Map")
	skip = {}
	for _, n in { "Combatants", "Vehicles", "Corpos", "DroppedWeapons", "Granadas", "Smoke" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	local art = map and map:FindFirstChild("Art")
	local jungle = art and art:FindFirstChild("Jungle")
	if jungle then
		table.insert(skip, jungle) -- tronco de árvore não conta como chão de ninguém
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local n = 0
	local function tick()
		n += 1
		if n % 400 == 0 then
			task.wait()
		end
	end
	local function add(r: Row?)
		if r then
			table.insert(rows, r)
		end
	end
	-- construções, bases, objetos e plantas de quintal (Map/Art); vida da vila; animais; mata
	if art then
		for _, m in art:GetChildren() do
			local cf = pivotOf(m)
			if cf and not SKIP[m.Name] then
				tick()
				local kind = artKind(m)
				add(Flutua.measure(m, yawFrame(cf), kind, if kind == "planta de quintal e vila" then 0.3 / M else nil))
			end
		end
		for _, sub in { "VidaDaVila", "Animals" } do
			local f = art:FindFirstChild(sub)
			for _, m in if f then f:GetChildren() else {} do
				local cf = pivotOf(m)
				if cf then
					tick()
					local kind = if sub == "Animals" then "animal" else "vida da vila"
					add(Flutua.measure(m, yawFrame(cf), kind, if sub == "Animals" then 0.3 / M else nil))
				end
			end
		end
		for _, m in if jungle then jungle:GetChildren() else {} do
			local cf = pivotOf(m)
			if cf then
				tick()
				add(Flutua.measure(m, yawFrame(cf), "mata", 0.3 / M))
			end
		end
	end
	-- arroz (ladrilhos do arrozal), marcos do mapa e campo de tiro (alvo, centro e placa de distância
	-- ficam pendurados no poste: conta o poste; a placa da linha conta pelas pernas dela)
	local HUNG = { "^Alvo", "^Centro", "^Placa" }
	local function hung(n: string): boolean
		for _, p in HUNG do
			if string.match(n, p) then
				return true
			end
		end
		return false
	end
	-- arroz: o pé dos ladrilhos (RiceField.client: a lâmina menos RiceField.BASE) contra o fundo do
	-- tabuleiro; o "Dossel" é o plano das folhas, alto de propósito (CANOPY_Y acima da água)
	local arrozal = map and map:FindFirstChild("Arrozal")
	for _, d in if arrozal then arrozal:GetChildren() else {} do
		local waterY = d:GetAttribute("WaterY")
		if d:IsA("BasePart") and type(waterY) == "number" then
			tick()
			local foot = waterY - RiceField.BASE
			local mn, mx = math.huge, -math.huge
			for _, o in FIVE do
				local wp = d.CFrame * Vector3.new(o[1] * d.Size.X * 0.4, 0, o[2] * d.Size.Z * 0.4)
				local g = Flutua.ground(wp.X, foot, wp.Z, d)
				if g then
					mn, mx = math.min(mn, (foot - g) * M), math.max(mx, (foot - g) * M)
				end
			end
			if mn < math.huge then
				table.insert(
					rows,
					{ kind = "arroz (pé)", key = d.Name, minGap = mn, maxGap = mx, hidden = 0, pos = d.Position }
				)
			end
		end
	end
	for _, spec in
		{
			{ map and map:FindFirstChild("Flags"), "bandeira" },
			{ map and map:FindFirstChild("Strongpoints"), "ponto forte" },
			{ map and map:FindFirstChild("HQ"), "QG" },
			{ workspace:FindFirstChild("CampoDeTiro"), "campo de tiro" },
			{ workspace:FindFirstChild("Logistics"), "logística (caixas)" },
		}
	do
		local f = spec[1] :: Instance?
		local list: { Instance } = if f then f:GetChildren() else {}
		for _, m in list do
			local cf = pivotOf(m)
			if cf then
				tick()
				add(Flutua.measure(m, yawFrame(cf), spec[2] :: string, nil))
			elseif m:IsA("Folder") then
				for _, c in m:GetChildren() do
					local ccf = pivotOf(c)
					local onPost = spec[2] == "campo de tiro"
						and hung(c.Name)
						and (c.Name ~= "PlacaLinha" or m:FindFirstChild("PernaPlaca") ~= nil)
					if ccf and not onPost then
						tick()
						add(Flutua.measure(c, yawFrame(ccf), spec[2] :: string, nil))
					end
				end
			end
		end
	end
	-- veículos: a arte (rodas e lagarta) contra o chão sob o chassi; sem ocupante e parados
	local vehicles = workspace:FindFirstChild("Vehicles")
	for _, v in if vehicles then vehicles:GetChildren() else {} do
		local chassis = v:FindFirstChild("Chassis") :: BasePart?
		local artM = v:FindFirstChild("Art")
		if chassis and artM then
			local moving = chassis.AssemblyLinearVelocity.Magnitude * M > 0.3
			local kind = "veículo " .. tostring(v:GetAttribute("Spec")) .. (if moving then " (andando)" else "")
			-- fundo visível da arte (rodas, lagarta) contra o chão no meio e nos cantos do chassi (a 40%)
			local frame = yawFrame(chassis.CFrame)
			local lo = Flutua.box(artM, frame, true)
			if lo then
				local bottom = (frame * Vector3.new(0, lo.Y, 0)).Y
				local mn, mx = math.huge, -math.huge
				for _, o in FIVE do
					local wp = chassis.CFrame
						* Vector3.new(o[1] * chassis.Size.X * 0.4, -chassis.Size.Y / 2, o[2] * chassis.Size.Z * 0.4)
					local g = Flutua.ground(wp.X, bottom, wp.Z, v)
					if g then
						mn, mx = math.min(mn, (bottom - g) * M), math.max(mx, (bottom - g) * M)
					end
				end
				-- o chassi (a caixa da física) contra o chão também
				local cb = chassis.Position.Y - chassis.Size.Y / 2
				local g = Flutua.ground(chassis.Position.X, cb, chassis.Position.Z, v)
				if mn < math.huge then
					table.insert(rows, {
						kind = kind,
						key = v.Name,
						minGap = mn,
						maxGap = mx,
						hidden = if g then (cb - g) * M else 0,
						pos = chassis.Position,
					})
				end
			end
		end
	end
	-- soldados em pé (bots e jogadores) e a altura deles
	local heights: { number } = {}
	local comb = workspace:FindFirstChild("Combatants")
	for _, c in if comb then comb:GetChildren() else {} do
		if c:IsA("Model") then
			soldier(c, rows, heights)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character.Parent ~= comb then
			soldier(p.Character, rows, heights)
		end
	end
	Flutua.heights = heights
	-- corpos (D-107), armas caídas e granadas: a peça mais baixa contra o chão sob ela
	for _, spec in
		{
			{ workspace:FindFirstChild("Corpos"), "corpo" },
			{ workspace:FindFirstChild("DroppedWeapons"), "arma no chão" },
			{ workspace:FindFirstChild("Granadas"), "granada" },
		}
	do
		local f = spec[1] :: Instance?
		local list: { Instance } = if f then f:GetChildren() else {}
		for _, m in list do
			local low: BasePart? = nil
			local parts: { Instance } = if m:IsA("BasePart") then { m :: Instance } else m:GetDescendants()
			for _, d in parts do
				if d:IsA("BasePart") and not hiddenPart(d) then
					local b = d.Position.Y - d.Size.Y / 2
					if not low or b < (low :: BasePart).Position.Y - (low :: BasePart).Size.Y / 2 then
						low = d
					end
				end
			end
			if low then
				local frame = yawFrame(low.CFrame)
				local lo = Flutua.box(low, frame, true)
				local bottom = if lo then (frame * Vector3.new(0, lo.Y, 0)).Y else low.Position.Y
				local g = Flutua.ground(low.Position.X, bottom, low.Position.Z, m)
				if g then
					local gap = (bottom - g) * M
					table.insert(rows, {
						kind = spec[2] :: string,
						key = m.Name,
						minGap = gap,
						maxGap = gap,
						hidden = 0,
						pos = low.Position,
					})
				end
			end
		end
	end
	return rows
end

local function fmt(x: number): string
	return (string.gsub(string.format("%.2f", x), "%.", ","))
end

-- Resumo por tipo (linhas [VT65 TESTE]); também devolve as linhas
function Flutua.report(): { string }
	local t0 = os.clock()
	local rows = Flutua.scan()
	local byKind: { [string]: { Row } } = {}
	local order: { string } = {}
	for _, r in rows do
		if not byKind[r.kind] then
			byKind[r.kind] = {}
			table.insert(order, r.kind)
		end
		table.insert(byKind[r.kind], r)
	end
	table.sort(order)
	local lines: { string } = {}
	for _, kind in order do
		local list = byKind[kind]
		local vehicle = string.find(kind, "^veículo") ~= nil
		local corner, whole, hid = 0, 0, 0
		local worst: Row? = nil
		local gaps: { number } = {}
		for _, r in list do
			local lim = if kind == "soldado em pé" then Flutua.FOOT_M else Flutua.CORNER_M
			if r.maxGap > lim then
				corner += 1
			end
			if r.minGap > Flutua.ALL_M then
				whole += 1
			end
			if r.hidden > 0.05 and not vehicle then
				hid += 1
			end
			if not worst or r.maxGap > worst.maxGap then
				worst = r
			end
			table.insert(gaps, r.maxGap)
		end
		table.sort(gaps)
		local w = worst :: Row
		local extra = if vehicle
			then string.format(", chassi a %s m do chão", fmt(w.hidden))
			elseif hid > 0 then string.format(", %d com o fundo invisível abaixo do visível", hid)
			else ""
		table.insert(
			lines,
			string.format(
				"[VT65 TESTE] flutua %s: %d medidos, %d com canto no ar, %d inteiros no ar; mediana %s m; pior %s m (%s em %.0f, %.0f, %.0f)%s",
				kind,
				#list,
				corner,
				whole,
				fmt(gaps[math.ceil(#gaps / 2)]),
				fmt(w.maxGap),
				w.key,
				w.pos.X,
				w.pos.Y,
				w.pos.Z,
				extra
			)
		)
	end
	-- os 15 piores fora dos soldados
	table.sort(rows, function(a: Row, b: Row): boolean
		return a.minGap > b.minGap
	end)
	local k = 0
	for _, r in rows do
		if r.kind ~= "soldado em pé" and r.minGap > Flutua.ALL_M then
			k += 1
			table.insert(
				lines,
				string.format(
					"[VT65 TESTE] flutua no ar #%d: %s (%s) de %s a %s m em (%.0f, %.0f, %.0f)",
					k,
					r.key,
					r.kind,
					fmt(r.minGap),
					fmt(r.maxGap),
					r.pos.X,
					r.pos.Y,
					r.pos.Z
				)
			)
			if k >= 15 then
				break
			end
		end
	end
	local hs = table.clone(Flutua.heights)
	table.sort(hs)
	if #hs > 0 then
		table.insert(
			lines,
			string.format(
				"[VT65 TESTE] flutua soldado: altura do pé ao topo da cabeça %s m (mediana de %d)",
				fmt(hs[math.ceil(#hs / 2)]),
				#hs
			)
		)
	end
	table.insert(lines, string.format("[VT65 TESTE] flutua: %d itens medidos em %.1f s", #rows, os.clock() - t0))
	for _, l in lines do
		print(l)
	end
	return lines
end

-- Gancho do Studio: workspace:SetAttribute("VT65DevFlutua", true)
function Flutua.hook()
	if not RunService:IsStudio() then
		return
	end
	workspace:GetAttributeChangedSignal("VT65DevFlutua"):Connect(function()
		if workspace:GetAttribute("VT65DevFlutua") then
			workspace:SetAttribute("VT65DevFlutua", nil)
			task.spawn(Flutua.report)
		end
	end)
end

return Flutua
