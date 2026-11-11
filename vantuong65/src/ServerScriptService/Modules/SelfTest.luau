--!strict
-- Autoteste dentro do motor (só no Studio). Roda no MESMO servidor do jogo (os módulos são os de
-- verdade, ao contrário do require da barra de comando). Para rodar, durante o Play, na barra de
-- comando do lado do servidor:
--     workspace:SetAttribute("VT65SelfTest", true)
-- Cada verificação imprime "[VT65 TESTE] ok|FALHA|pulado nome: detalhe" e, no fim, um resumo.
-- Leva ~2 min (o Offensive espera 90 s de captura de verdade pelo laço da partida).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AfterAction = require(ReplicatedStorage.Shared.AfterAction)
local Ballistics = require(ReplicatedStorage.Shared.Ballistics)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig) :: any
local Rng = require(ReplicatedStorage.Shared.Rng)
local Combatants = require(script.Parent.Combatants)
local ExplosionService = require(script.Parent.ExplosionService)
local FieldWorkService = require(script.Parent.FieldWorkService)
local LogisticsService = require(script.Parent.LogisticsService)
local MatchService = require(script.Parent.MatchService)
local MedicalService = require(script.Parent.MedicalService)
local PostureService = require(script.Parent.PostureService)
local SpawnService = require(script.Parent.SpawnService)
local TunnelService = require(script.Parent.TunnelService)
local VehicleService = require(script.Parent.VehicleService)

local SelfTest = {}
local M = 0.28
local okN, failN, skipN = 0, 0, 0

local function report(kind: string, name: string, detail: string?)
	if kind == "ok" then
		okN += 1
	elseif kind == "FALHA" then
		failN += 1
	else
		skipN += 1
	end
	print(string.format("[VT65 TESTE] %s %s%s", kind, name, if detail then ": " .. detail else ""))
end

local function check(name: string, fn: () -> (string, string?))
	local ok, kind, detail = pcall(fn)
	if not ok then
		report("FALHA", name, "erro: " .. tostring(kind))
	else
		report(kind, name, detail)
	end
end

local function waitFor(cond: () -> boolean, timeout: number): boolean
	local t0 = os.clock()
	while not cond() do
		if os.clock() - t0 > timeout then
			return false
		end
		task.wait(0.25)
	end
	return true
end

local function bots(faction: string): { any }
	local out = {}
	for _, e in Combatants.list() do
		if e.faction == faction and not e.player and Combatants.active(e) then
			table.insert(out, e)
		end
	end
	return out
end

local function playerChar(): (Player?, Model?)
	local p = Players:GetPlayers()[1]
	local c = p and p.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if p and c and hum and hum.Health > 0 then
		return p, c
	end
	return p, nil
end

-- ===== verificações =====
local function terrain(): (string, string?)
	local ok = waitFor(function()
		return ReplicatedStorage:GetAttribute("TerrainReady") == true
	end, 180)
	return if ok then "ok" else "FALHA", if ok then "TerrainReady" else "terreno não ficou pronto em 180 s"
end

local function botsUp(): (string, string?)
	waitFor(function()
		return #bots("US") > 0 and #bots("VC") > 0
	end, 60)
	local us, vc = #bots("US"), #bots("VC")
	return if us > 0 and vc > 0 then "ok" else "FALHA", string.format("%d bots EUA, %d bots VC", us, vc)
end

-- Raia e balística: o tiro do jogo (mesma conta do CombatService, com a zeragem do cliente)
-- sai da linha de tiro, na altura do olho em pé, mirando o centro de cada alvo.
local function range(): (string, string?)
	local folder = workspace:FindFirstChild("CampoDeTiro")
	if not folder then
		return "FALHA", "workspace.CampoDeTiro não existe"
	end
	local lines = {}
	local bad = false
	-- sementes de 32 bits, como as do WeaponController. Com 1 a 5 o primeiro sorteio do xorshift sai
	-- quase zero e a dispersão vira ~4σ sempre para o mesmo lado (todos os tiros à direita).
	local seeds = Rng.new(19650818)
	for _, side in { { f = "US", w = "m14" }, { f = "VC", w = "type56" } } do
		local sub = folder:FindFirstChild(side.f)
		local line = sub and sub:FindFirstChild("LinhaDeTiro") :: BasePart?
		if not (sub and line) then
			bad = true
			table.insert(lines, side.f .. ": sem linha de tiro")
			continue
		end
		local eye = line.Position + Vector3.new(0, 1.5 / M - 0.25 / M, 0)
		for _, d in sub:GetChildren() do
			local dist = d:GetAttribute("RangeTarget")
			if not (d:IsA("BasePart") and type(dist) == "number") then
				continue
			end
			local hits = 0
			local blockedBy: string? = nil
			for _ = 1, 5 do
				local seed = seeds:nextU32()
				local aim = CFrame.lookAt(eye, d.Position)
				local zero = Ballistics.zeroAngle(side.w, dist)
				local dir = (aim * CFrame.Angles(zero, 0, 0)).LookVector
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				local ignore: { Instance } = {}
				params.FilterDescendantsInstances = ignore
				local hit = Ballistics.trace({
					ox = eye.X * M,
					oy = eye.Y * M,
					oz = eye.Z * M,
					dx = dir.X,
					dy = dir.Y,
					dz = dir.Z,
					weaponId = side.w,
					seed = seed,
				}, function(ax, ay, az, bx, by, bz)
					local from = Vector3.new(ax, ay, az) / M
					local delta = Vector3.new(bx - ax, by - ay, bz - az) / M
					for _ = 1, 6 do
						local r = workspace:Raycast(from, delta, params)
						if not r then
							return nil
						end
						-- materiais que a bala atravessa (CombatService.PASS): sebe e palha
						local mat = r.Instance:GetAttribute("Material")
						if mat == "Bamboo" or mat == "Thatch" then
							table.insert(ignore, r.Instance)
							params.FilterDescendantsInstances = ignore
						else
							local p = r.Position * M
							return { x = p.X, y = p.Y, z = p.Z, target = r.Instance }
						end
					end
					return nil
				end)
				if hit and hit.target == d then
					hits += 1
				elseif hit and hit.target then
					blockedBy = (hit.target :: Instance):GetFullName()
				end
			end
			if hits < 4 then
				bad = true
			end
			table.insert(
				lines,
				-- sem "m: N/": o Output do Roblox apaga esse trecho (reteste no Studio, 2026-11-10)
				string.format(
					"%s %d m, %d de 5%s",
					side.f,
					dist,
					hits,
					if blockedBy and hits < 5 then " (parou em " .. blockedBy .. ")" else ""
				)
			)
		end
	end
	return if bad then "FALHA" else "ok", table.concat(lines, "; ")
end

-- Bug 3 do teste no Studio: deitado não pode ficar em queda livre nem escorregar.
local function prone(): (string, string?)
	local _, c = playerChar()
	if not c then
		return "pulado", "sem personagem do jogador"
	end
	local hum = c:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart
	if not PostureService.setStance(c, "prone") then
		return "FALHA", "setStance recusou deitar"
	end
	task.wait(2.5)
	local hip = hum.HipHeight
	local state = hum:GetState()
	local v = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude * M
	-- corpo deitado no servidor: mede o tronco (vale para Motor6D e AnimationConstraint)
	local torso = c:FindFirstChild("UpperTorso") :: BasePart?
	local tilt = if torso then math.deg(math.acos(math.clamp(torso.CFrame.UpVector.Y, -1, 1))) else 0
	local posed = tilt >= 60
	PostureService.setStance(c, "stand")
	local good = hip >= 0.2 and state ~= Enum.HumanoidStateType.Freefall and v < 1 and posed
	return if good then "ok" else "FALHA",
		string.format(
			"HipHeight %.2f, estado %s, deslizando %.2f m/s, tronco a %.0f° da vertical no servidor",
			hip,
			state.Name,
			v,
			tilt
		)
end

-- Offensive pelo laço real da partida + relatório pós-ação.
local function offensive(): (string, string?)
	MatchService.newMatch("Offensive")
	local o = MatchService.offensive
	if not o or o.front ~= 4 then
		return "FALHA", "Offensive não começou com a frente em S4"
	end
	MatchService.countsOverride = function()
		local c = {}
		for s = 1, 5 do
			c[s] = { US = 0, VC = 0 }
		end
		c[4] = { US = 5, VC = 0 } -- 5 fuzileiros sozinhos no ponto: 90 s de VC a EUA
		return c
	end
	local took = waitFor(function()
		return o.front == 3
	end, 100)
	MatchService.countsOverride = nil
	if not took then
		return "FALHA", string.format("S4 não caiu em 100 s (progresso %.2f)", o.capture.progress[4])
	end
	workspace:SetAttribute("VT65DevEnd", true)
	local ended = waitFor(function()
		return MatchService.ended
	end, 5)
	local rep = MatchService.report
	local text = if rep then table.concat(AfterAction.lines(rep), "\n") else ""
	local hasCapture = string.find(text, "USMC toma S4", 1, true) ~= nil
	MatchService.newMatch("Warfare")
	return if ended and hasCapture then "ok" else "FALHA",
		string.format(
			"frente S3, prazo %d min, fim=%s, relatório %s",
			o.deadline // 60,
			tostring(ended),
			if hasCapture then "com a captura" else "SEM a captura"
		)
end

-- Arma do inimigo: bot morto deixa a arma no chão.
local function droppedWeapon(): (string, string?)
	local list = bots("VC")
	if #list == 0 then
		return "pulado", "sem bot VC"
	end
	local e = list[1]
	local folder = workspace:FindFirstChild("DroppedWeapons")
	local before = if folder then #folder:GetChildren() else 0
	local hum = Combatants.humanoid(e)
	if not hum then
		return "pulado", "bot sem Humanoid"
	end
	hum.Health = 0
	local ok = waitFor(function()
		local f = workspace:FindFirstChild("DroppedWeapons")
		return f ~= nil and #f:GetChildren() > before
	end, 3)
	return if ok then "ok" else "FALHA", if ok then "arma caída com prompt" else "nenhuma arma caiu em 3 s"
end

-- Pá: o jogador cava no QG dos EUA (setor do próprio lado).
local function dig(): (string, string?)
	local p, c = playerChar()
	if not (p and c) then
		return "pulado", "sem personagem do jogador"
	end
	if p:GetAttribute("Faction") ~= "US" then
		return "pulado",
			"o teste da pá usa o lado EUA (o jogador está em " .. tostring(p:GetAttribute("Faction")) .. ")"
	end
	local hq = MapConfig.HQ.US
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	-- Chão seco perto do QG, no setor 5. Era fixo 60 m a oeste do QG: com a lâmina d'água do arrozal
	-- posta no terreno real (D-73) o ponto virou arrozal alagado e a pá recusava ("água").
	local anyParams = RaycastParams.new()
	anyParams.FilterType = Enum.RaycastFilterType.Exclude
	anyParams.FilterDescendantsInstances = { c }
	local x, z, g
	for _, o in { { -60, 0 }, { -60, 25 }, { -60, -25 }, { -40, 40 }, { -40, -40 }, { -90, 0 }, { -30, 0 } } do
		local tx, tz = hq.x + o[1] / M, hq.z + o[2] / M
		local hit = workspace:Raycast(Vector3.new(tx, 2000, tz), Vector3.new(0, -4000, 0), params)
		local top = workspace:Raycast(Vector3.new(tx, 2000, tz), Vector3.new(0, -4000, 0), anyParams)
		local wet = top ~= nil and top.Instance:GetAttribute("Material") == "PaddyWater"
		if hit and hit.Material ~= Enum.Material.Water and not wet then
			x, z, g = tx, tz, hit
			break
		end
	end
	if not (x and z and g) then
		return "FALHA", "sem chão seco perto do QG para o teste"
	end
	c:PivotTo(CFrame.new(x, 400, z))
	task.wait(1)
	local root = c:FindFirstChild("HumanoidRootPart") :: BasePart
	c:PivotTo(CFrame.new(g.Position + Vector3.new(0, 4, 0)))
	task.wait(1.5)
	local ahead = root.Position + root.CFrame.LookVector * Vector3.new(1, 0, 1) * (1.5 / M)
	FieldWorkService.dig(p)
	task.wait(9.5)
	local probe = workspace:Raycast(ahead + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
	local drop = if probe then (g.Position.Y - probe.Position.Y) * M else 0
	return if drop > 0.5 then "ok" else "FALHA",
		string.format("chão à frente desceu %.2f m (esperado ~1,2 m; a recusa aparece no aviso do jogador)", drop)
end

-- Medevac: bot EUA caído junto de um UH-34D pousado vira suprimento. Usa um UH-34D que já está
-- pousado no depósito. Antes o teste criava outro no depósito 1, que é do LVTP-5: os dois se
-- sobrepunham e o helicóptero não ficava parado (reteste no Studio, 2026-11-10).
local function medevac(): (string, string?)
	local list = bots("US")
	if #list == 0 then
		return "pulado", "sem bot EUA"
	end
	local heli: Model? = nil
	local vehicles = workspace:FindFirstChild("Vehicles")
	for _, m in (if vehicles then vehicles:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("Spec") == "uh34d" and not m:GetAttribute("Destroyed") then
			heli = m
			break
		end
	end
	local spawned = false
	if not heli then
		heli = VehicleService.spawn("uh34d", 5) -- depósito 5: o do UH-34D
		spawned = true
		task.wait(4) -- assentar no chão
	end
	local hp = heli and heli.PrimaryPart
	local e = list[#list]
	local st = MedicalService.get(e.model)
	if not (heli and hp and st) then
		if heli and spawned then
			heli:Destroy()
		end
		return "pulado", "sem UH-34D, chassi ou estado médico"
	end
	e.model:PivotTo(hp.CFrame * CFrame.new(6 / M, 0, 0))
	st.downedAt = os.clock()
	local before = LogisticsService.supply("US")
	local ok = waitFor(function()
		return e.model:GetAttribute("Evacuated") == true
	end, 10)
	local after = LogisticsService.supply("US")
	local speed = hp.AssemblyLinearVelocity.Magnitude * M
	if spawned then
		heli:Destroy()
	end
	return if ok then "ok" else "FALHA",
		string.format("evacuado=%s, suprimento %d → %d, UH-34D a %.1f m/s", tostring(ok), before, after, speed)
end

local function radio(): (string, string?)
	local p = Players:GetPlayers()[1]
	if not p then
		return "pulado", "sem jogador"
	end
	local role = p:GetAttribute("Role")
	local has = p:GetAttribute("Radio") == true
	if role == "radio_operator" then
		local c = p.Character
		local ant = c and c:FindFirstChild("RadioAntenna")
		return if has and ant then "ok" else "FALHA",
			string.format("rádio=%s, antena=%s", tostring(has), tostring(ant ~= nil))
	end
	return if has then "FALHA" else "ok", string.format("papel %s sem rádio (esperado)", tostring(role))
end

local function animals(): (string, string?)
	local art = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild("Art")
	-- com a mata (D-64) a arte demora mais: o teste rodava antes dos animais existirem
	if art then
		waitFor(function()
			return art:GetAttribute("Placed") == true
		end, 240)
	end
	local pen = art and art:FindFirstChild("Animals")
	if not pen then
		return "pulado", "sem modelos publicados (AssetIds em 0)"
	end
	return if #pen:GetChildren() > 0 then "ok" else "FALHA", string.format("%d animais", #pen:GetChildren())
end

-- Arte no chão: a base de cada modelo deve ficar perto do terreno sob o pivô. Em 2026-11-10 a arte
-- era posta antes do terreno existir e tudo ia para y = 0 (vilas enterradas até 20 m); este teste
-- teria pegado. Tolerância de 2 m (encosta e afundamento de túnel e trincheira); animais ficam de fora.
local function artOnGround(): (string, string?)
	local art = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild("Art")
	if not art then
		return "pulado", "sem modelos publicados (AssetIds em 0)"
	end
	if not waitFor(function()
		return art:GetAttribute("Placed") == true
	end, 240) then
		return "FALHA", "a arte não terminou de ser posta em 240 s"
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local n, bad, worst, worstName = 0, 0, 0, "-"
	for i, m in art:GetChildren() do
		if m:IsA("Model") then
			local cf, size = m:GetBoundingBox()
			local p = m:GetPivot().Position
			local hit = workspace:Raycast(Vector3.new(p.X, 3000, p.Z), Vector3.new(0, -6000, 0), params)
			if hit then
				n += 1
				local off = (cf.Position.Y - size.Y / 2 - hit.Position.Y) * M -- base menos chão (m)
				if math.abs(off) > 2 then
					bad += 1
				end
				if math.abs(off) > math.abs(worst) then
					worst, worstName = off, m.Name
				end
			end
		end
		if i % 500 == 0 then
			task.wait()
		end
	end
	local ok = n > 0 and bad <= n * 0.03
	return if ok then "ok" else "FALHA",
		string.format(
			"%d de %d modelos com a base a até 2 m do chão; pior %s a %+.1f m",
			n - bad,
			n,
			worstName,
			worst
		)
end

-- F4: morteiro de 81 mm a 3 m de um bot VC. O dano sai do servidor (Explosive + MedicalService).
local function explosion(): (string, string?)
	local list = bots("VC")
	local e = list[#list]
	local st = e and MedicalService.get(e.model)
	local root = e and Combatants.root(e)
	if not (e and st and root) then
		return "pulado", "sem bot VC"
	end
	local h0, w0 = st.health, #st.wounds
	ExplosionService.detonate("mortar_81", root.Position + Vector3.new(3 / M, -2, 0), nil)
	task.wait(0.5)
	local hurt = st.dead or st.downedAt ~= nil or #st.wounds > w0 or st.health < h0
	return if hurt then "ok" else "FALHA",
		string.format(
			"vida %.0f → %.0f, ferimentos %d → %d, caído=%s, morto=%s",
			h0,
			st.health,
			w0,
			#st.wounds,
			tostring(st.downedAt ~= nil),
			tostring(st.dead)
		)
end

-- F4: veículos do depósito parados no chão e com assento (sem motorista, nada anda sozinho)
local function vehicles(): (string, string?)
	local f = workspace:FindFirstChild("Vehicles")
	local n, seated, moving = 0, 0, 0
	local specs: { string } = {}
	for _, m in if f then f:GetChildren() else {} do
		local spec = m:GetAttribute("Spec")
		if m:IsA("Model") and type(spec) == "string" and not m:GetAttribute("Destroyed") then
			n += 1
			table.insert(specs, spec)
			local seat = m:FindFirstChildWhichIsA("VehicleSeat", true) or m:FindFirstChildWhichIsA("Seat", true)
			if seat then
				seated += 1
			end
			local pp = m.PrimaryPart
			local driven = seat and (seat :: any).Occupant ~= nil
			if pp and not driven and pp.AssemblyLinearVelocity.Magnitude * M > 1 then
				moving += 1
			end
		end
	end
	table.sort(specs)
	return if n > 0 and seated == n and moving == 0 then "ok" else "FALHA",
		string.format(
			"%d veículos (%s), %d com assento, %d andando sem motorista",
			n,
			table.concat(specs, ", "),
			seated,
			moving
		)
end

-- F4: túneis: as 5 entradas com o prompt de destruir; o VC só nasce no túnel do setor que é dele
local function tunnels(): (string, string?)
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Tunnels")
	local prompts = 0
	for _, p in if folder then folder:GetChildren() else {} do
		if p:GetAttribute("TunnelEntrance") and p:FindFirstChildOfClass("ProximityPrompt") then
			prompts += 1
		end
	end
	local expected, got = 0, 0
	for _, en in TunnelService.entrances() do
		if en.sector and MatchService.ownerOf(en.sector) == "VC" and not TunnelService.destroyed[en.id] then
			expected += 1
		end
	end
	for _, pt in SpawnService.points("VC") do
		if string.sub(pt.id, 1, 7) == "tunnel:" then
			got += 1
		end
	end
	return if prompts == 5 and got == expected then "ok" else "FALHA",
		string.format(
			"%d entradas com prompt (esperado 5); pontos de túnel do VC %d (esperado %d)",
			prompts,
			got,
			expected
		)
end

-- F6/D-72: progressão publicada nos atributos do jogador (só leitura: não mexe no perfil)
local function progression(): (string, string?)
	local p = Players:GetPlayers()[1]
	if not p then
		return "pulado", "sem jogador"
	end
	local keys = { "XP", "Rank", "RankName", "Credits", "RespawnCredits" }
	local missing = {}
	for _, k in keys do
		if p:GetAttribute(k) == nil then
			table.insert(missing, k)
		end
	end
	return if #missing == 0 then "ok" else "FALHA",
		if #missing == 0
			then string.format(
				"posto %s (%s), XP %s, créditos %s",
				tostring(p:GetAttribute("Rank")),
				tostring(p:GetAttribute("RankName")),
				tostring(p:GetAttribute("XP")),
				tostring(p:GetAttribute("Credits"))
			)
			else "faltam: " .. table.concat(missing, ", ")
end

-- Vida no mapa (D-74): dossel do arrozal, ladrilhos de arroz (com recorte), túneis com escora e
-- lamparina, fumaça, potes e medas nas vilas, manada com bezerro.
local function mapLife(): (string, string?)
	local map = workspace:FindFirstChild("Map")
	local art = map and map:FindFirstChild("Art")
	if not art then
		return "pulado", "sem arte publicada"
	end
	waitFor(function()
		return art:GetAttribute("Placed") == true
	end, 240)
	local rice = (map :: Instance):FindFirstChild("Arrozal")
	local tiles = ReplicatedStorage:FindFirstChild("VT65RiceArt")
	local hi = tiles and tiles:FindFirstChild("hi") :: BasePart?
	local life = (map :: Instance):FindFirstChild("TunnelLife")
	local lamps = #game:GetService("CollectionService"):GetTagged("VT65Lamp")
	local fx = art:FindFirstChild("VidaDaVila")
	local stacks, jars, calves = 0, 0, 0
	for _, m in art:GetChildren() do
		if m.Name == "MedaDePalha" then
			stacks += 1
		elseif m.Name == "PoteDagua" then
			jars += 1
		end
	end
	local pen = art:FindFirstChild("Animals")
	for _, m in if pen then pen:GetChildren() else {} do
		if m:IsA("Model") and m.Name == "water_buffalo" and m:GetScale() < 0.9 then
			calves += 1
		end
	end
	local nRice = if rice then #rice:GetChildren() else 0
	local ok = nRice > 500
		and hi ~= nil
		and hi.Transparency > 0
		and life ~= nil
		and lamps >= 20
		and fx ~= nil
		and #fx:GetChildren() >= 10
		and stacks > 0
		and jars > 0
		and calves >= 2
	return if ok then "ok" else "FALHA",
		string.format(
			"dossel %d, ladrilho com recorte %s, lamparinas %d, fumaças %d, medas %d, potes %d, bezerros %d",
			nRice,
			tostring(hi ~= nil and hi.Transparency > 0),
			lamps,
			if fx then #fx:GetChildren() else 0,
			stacks,
			jars,
			calves
		)
end

local function rain(): (string, string?)
	local atm = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
	local before = if atm then atm.Density else 0
	workspace:SetAttribute("VT65DevRain", 1)
	local ok = waitFor(function()
		return ReplicatedStorage:GetAttribute("Rain") == 1
	end, 3)
	task.wait(0.2)
	local after = if atm then atm.Density else 0
	workspace:SetAttribute("VT65DevRain", 0)
	task.wait(1.5)
	workspace:SetAttribute("VT65DevRain", nil)
	return if ok and (not atm or after > before) then "ok" else "FALHA",
		string.format(
			"Rain=1: %s; névoa %.2f → %.2f%s",
			tostring(ok),
			before,
			after,
			if atm then "" else " (sem Atmosphere)"
		)
end

function SelfTest.run()
	okN, failN, skipN = 0, 0, 0
	print("[VT65 TESTE] início")
	check("terreno", terrain)
	check("bots", botsUp)
	check("campo de tiro (raia e balística)", range)
	check("deitado sem queda livre", prone)
	check("arma caída de bot", droppedWeapon)
	check("rádio do squad", radio)
	check("animais da vila", animals)
	check("arte no chão", artOnGround)
	check("vida no mapa", mapLife)
	check("chuva", rain)
	check("pá de trincheira", dig)
	check("medevac", medevac)
	check("explosão de morteiro", explosion)
	check("veículos no depósito", vehicles)
	check("túneis e spawn do VC", tunnels)
	check("progressão nos atributos", progression)
	check("Offensive + relatório pós-ação", offensive)
	print(string.format("[VT65 TESTE] resumo: %d ok, %d falhas, %d pulados", okN, failN, skipN))
end

function SelfTest.start()
	if not RunService:IsStudio() then
		return
	end
	local running = false
	local function go()
		if workspace:GetAttribute("VT65SelfTest") == true and not running then
			running = true
			workspace:SetAttribute("VT65SelfTest", nil)
			task.spawn(function()
				SelfTest.run()
				running = false
			end)
		end
	end
	workspace:GetAttributeChangedSignal("VT65SelfTest"):Connect(go)
	go()
end

return SelfTest
