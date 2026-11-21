--!strict
-- Efeito visual das explosões (D-77, pedido do dono: "granadas com gráficos"). Antes a explosão era
-- só som e cratera. Agora, no aviso Fire_Impact do servidor (ExplosionService):
-- - clarão (luz forte por 0,15 s) e bola de fogo curta, que somem rápido (explosivo militar quase
--   não faz chama; a nuvem é de terra e fumaça);
-- - nuvem de terra marrom que sobe e se espalha, e fumaça cinza que fica alguns segundos;
-- - torrões de terra caindo e faíscas;
-- - na água (arrozal, riacho) uma coluna de água branca no lugar da terra;
-- - câmera treme perto (cai com a distância);
-- O tamanho vem do tipo (granada, morteiro, canhão, bomba). Tudo local e apagado depois.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ExplosaoEfeito = require(ReplicatedStorage.Shared.ExplosaoEfeito)
local GrenadeArt = require(ReplicatedStorage.Shared.GrenadeArt)
local Net = require(ReplicatedStorage.Shared.Net)
local Input = require(script.Parent.Input)

local M = 0.28
local camera = workspace.CurrentCamera
local TEX = {
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
	smoke = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	dust = "rbxasset://textures/particles/smoke_main.dds",
	sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	square = "rbxasset://textures/particles/SquareParticle.png",
	-- D-198: a smoke_main só aparece com cor clara; com cinza escuro ou preto some (Studio, teste lado
	-- a lado). Fumaça escura usa esta, que já é escura (a cor só clareia um pouco)
	escura = "rbxasset://textures/particles/explosion01_smoke_main.dds",
}
-- D-198: a escala por tipo (1 = granada de mão) vem do Shared/ExplosaoEfeito, independente do raio
-- de dano (Explosive) e do empurrão (Explosive.impulsoM)

local fx = Instance.new("Folder")
fx.Name = "VT65Explosoes"
fx.Parent = workspace

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do
		table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(keys)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- água sob o ponto? (lâmina do arrozal ou água do terreno)
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Exclude
local function inWater(pos: Vector3): boolean
	waterParams.FilterDescendantsInstances = { fx, camera }
	waterParams.IgnoreWater = false
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), waterParams)
	if not hit then
		return false
	end
	return hit.Material == Enum.Material.Water
		or hit.Instance:GetAttribute("Material") == "PaddyWater"
		or hit.Instance.Name == "PaddyWater"
end

-- tremor da câmera: soma dos pedidos, cai sozinho
local shake = 0
RunService:BindToRenderStep("VT65Tremor", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
	if shake <= 0.001 then
		shake = 0
		return
	end
	local t = os.clock() * 40
	local a = shake * math.rad(1.6)
	camera.CFrame *= CFrame.Angles(math.noise(t, 1) * a, math.noise(t, 2) * a, math.noise(t, 3) * a * 0.5)
	shake = math.max(0, shake - dt * 2.5)
end)

-- D-198: o ajuste do jogador (Configurações > Acessibilidade, "Tremor das explosões", 0 a 1)
local function ajusteTremor(): number
	local v = (Input.settings :: any).cameraShake
	return if type(v) == "number" then v else 1
end

local function explode(id: string, pos: Vector3)
	local s = ExplosaoEfeito.de(id).escala
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	if dM > 1500 then
		return
	end
	local water = inWater(pos)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 0.3 / M, 0))
	anchor.Parent = fx
	Debris:AddItem(anchor, 9)
	-- clarão
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 196, 120)
	light.Brightness = 10
	light.Range = math.min(60, 8 * s / M)
	light.Shadows = false
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.18 * s, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	-- bola de fogo: curta e baixa
	local ball = Instance.new("Part")
	ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.CastShadow = true, false, false, false, false
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 170, 70)
	ball.Size = Vector3.one * (0.6 * s / M)
	ball.CFrame = anchor.CFrame
	ball.Parent = fx
	TweenService:Create(ball, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (2.4 * s / M),
		Transparency = 1,
		Color = Color3.fromRGB(120, 70, 40),
	}):Play()
	Debris:AddItem(ball, 0.3)
	-- núcleo
	emitter(anchor, {
		Texture = TEX.core,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 120, 40)),
		Size = seq(0, 1.2 * s / M, 1, 3.2 * s / M),
		Transparency = seq(0, 0.1, 1, 1),
		Lifetime = NumberRange.new(0.18, 0.3),
		Speed = NumberRange.new(2 / M, 5 / M),
		SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360),
	}):Emit(math.floor(5 * s))
	-- faíscas
	emitter(anchor, {
		Texture = TEX.sparks,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 120)),
		Size = seq(0, 0.12 / M, 1, 0),
		Lifetime = NumberRange.new(0.3, 0.7),
		Speed = NumberRange.new(10 / M, 22 / M),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -9.8 / M, 0),
		Drag = 2,
	}):Emit(math.floor(18 * s))
	if water then
		-- coluna de água: sobe branca e cai
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(235, 238, 236), Color3.fromRGB(190, 196, 190)),
			-- coluna estreita: granada levanta ~3–5 m de água, morteiro ~10 m (no Studio a 1ª versão
			-- virou uma nuvem branca do tamanho de um prédio)
			Size = seq(0, 0.35 * s / M, 0.5, 0.9 * s / M, 1, 1.3 * s / M),
			Transparency = seq(0, 0.1, 0.7, 0.45, 1, 1),
			Lifetime = NumberRange.new(0.9, 1.5),
			Speed = NumberRange.new(5 * s / M, 9 * s / M),
			SpreadAngle = Vector2.new(9, 9),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
			Drag = 0.6,
			Rotation = NumberRange.new(0, 360),
		}):Emit(math.floor(26 * s))
		emitter(anchor, {
			Texture = TEX.square,
			Color = ColorSequence.new(Color3.fromRGB(220, 226, 226)),
			Size = seq(0, 0.08 / M, 1, 0.03 / M),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(6 / M, 14 / M),
			SpreadAngle = Vector2.new(50, 50),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
		}):Emit(math.floor(40 * s))
	else
		-- terra: nuvem marrom que sobe e torrões caindo
		-- (a textura explosion01_smoke do Roblox é quase preta: a nuvem saía uma bola escura)
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(150, 122, 92), Color3.fromRGB(176, 164, 148)),
			Size = seq(0, 0.7 * s / M, 0.4, 2.2 * s / M, 1, 3.4 * s / M),
			Transparency = seq(0, 0.2, 0.6, 0.6, 1, 1),
			Lifetime = NumberRange.new(2.5, 4.5),
			Speed = NumberRange.new(4 * s / M, 9 * s / M),
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0.3 / M, -1 / M, 0),
			Drag = 2.2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
		}):Emit(math.floor(16 * s))
		emitter(anchor, {
			Texture = TEX.square,
			Color = ColorSequence.new(Color3.fromRGB(70, 56, 40), Color3.fromRGB(96, 78, 56)),
			Size = seq(0, 0.1 / M, 1, 0.06 / M),
			Lifetime = NumberRange.new(1.0, 1.8),
			Speed = NumberRange.new(7 * s / M, 15 * s / M),
			SpreadAngle = Vector2.new(55, 55),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200, 200),
		}):Emit(math.floor(36 * s))
		-- poeira rasteira (onda de choque levantando o chão)
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(150, 132, 108)),
			Size = seq(0, 1 * s / M, 1, 3 * s / M),
			Transparency = seq(0, 0.35, 1, 1),
			Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(6 * s / M, 10 * s / M),
			SpreadAngle = Vector2.new(85, 85),
			Drag = 3,
			Rotation = NumberRange.new(0, 360),
		}):Emit(math.floor(12 * s))
	end
	-- fumaça cinza que fica. D-198: com a smoke_main e cor cinza ela quase não aparecia (Studio); a
	-- textura escura dá a fumaça cinza-escura do explosivo
	emitter(anchor, {
		Texture = TEX.escura,
		Color = ColorSequence.new(Color3.fromRGB(232, 226, 218), Color3.fromRGB(252, 250, 246)),
		Size = seq(0, 1.2 * s / M, 1, 4.5 * s / M),
		Transparency = seq(0, 0.5, 0.5, 0.7, 1, 1),
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(1 / M, 3 / M),
		SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0.4 / M, 0.6 / M, 0.2 / M),
		Drag = 1,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-10, 10),
	}):Emit(math.floor(8 * s))
	-- tremor: forte a poucos metros, some a ~50 m da granada (mais longe para bomba); D-198: vezes o
	-- ajuste do jogador (Configurações, "Tremor das explosões")
	shake = math.min(1.5, shake + ExplosaoEfeito.tremor(dM, s, ajusteTremor()))
end

-- ===== D-198: a explosão grande (bomba do A-4, tiro naval) =====
-- Clarão curto (luz e tela), bola de fogo em lóbulos que sobe e escurece, anel de poeira rasteira
-- que corre pelo chão, coluna de fumaça que pende com o vento, poucos detritos com física e o tremor
-- pela distância. A superfície muda a cor e os pedaços (terra, vegetação, estrutura, água). Cada
-- uma varia um pouco (lóbulos, giro, ritmo, tamanho, inclinação). Detalhe pela distância e pela
-- qualidade gráfica, e um teto de explosões, luzes e pedaços ao mesmo tempo.
local ativos = { grandes = 0, luzes = 0, detritos = 0 }
local LIM = ExplosaoEfeito.LIMITES
local Lighting = game:GetService("Lighting")
local clarao = Instance.new("ColorCorrectionEffect")
clarao.Name = "VT65Clarao"
clarao.Parent = Lighting

local function qualidade(): number
	local ok, q = pcall(function(): number
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return if ok and type(q) == "number" and q >= 1 then q else 6 -- 0 = automático
end

local surfParams = RaycastParams.new()
surfParams.FilterType = Enum.RaycastFilterType.Exclude
local function superficieEm(pos: Vector3): ExplosaoEfeito.Superficie
	surfParams.FilterDescendantsInstances = { fx, camera }
	surfParams.IgnoreWater = false
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), surfParams)
	if not hit then
		return "terra"
	end
	local inst = hit.Instance
	local nome = if inst:GetAttribute("Material") == "PaddyWater" then "PaddyWater" else inst.Name
	return ExplosaoEfeito.superficie(hit.Material.Name, inst == workspace.Terrain, nome)
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local seedN = 0
local function explodeGrande(id: string, pos: Vector3)
	local T = ExplosaoEfeito.de(id)
	local dM = (pos - camera.CFrame.Position).Magnitude * M
	if dM > 2500 then
		return
	end
	local det = ExplosaoEfeito.detalhe(dM, qualidade())
	if ativos.grandes >= LIM.grandes then
		det = math.min(det, 0.35) -- muitas ao mesmo tempo: as de agora saem simples
	end
	ativos.grandes += 1
	task.delay(4, function()
		ativos.grandes -= 1
	end)
	seedN += 1
	local v = ExplosaoEfeito.variacao(math.floor(pos.X * 7 + pos.Z * 13) + seedN * 7919)
	local s = T.escala * v.tamanhoK
	local sup = superficieEm(pos)
	local cor = ExplosaoEfeito.CORES[sup]
	local agua = sup == "agua"
	local colunaS = (T.colunaS or 10) * v.tempoK
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 0.4 / M, 0)) * CFrame.Angles(0, v.giro, 0)
	anchor.Parent = fx
	Debris:AddItem(anchor, colunaS + 12)
	-- 1) clarão: luz forte e curta (com teto de luzes) e um branco rápido na tela de quem está perto
	if ativos.luzes < LIM.luzes then
		ativos.luzes += 1
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 130)
		light.Brightness = 18
		light.Range = math.min(60, 10 * s / M)
		light.Shadows = false
		light.Parent = anchor
		TweenService:Create(light, TweenInfo.new(0.35 * v.tempoK, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
		task.delay(0.4, function()
			ativos.luzes -= 1
			light:Destroy()
		end)
	end
	if dM < 500 then
		clarao.Brightness = math.max(clarao.Brightness, 0.22 * (1 - dM / 500))
		TweenService:Create(clarao, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	end
	-- 2) bola de fogo em lóbulos: nasce amarela, cresce, sobe e escurece até virar fumaça
	if not agua then
		for i = 1, v.lobos do
			local a = v.giro + i * (2 * math.pi / v.lobos)
			local off = Vector3.new(math.cos(a), 0.3 + 0.4 * ((i % 3) / 2), math.sin(a)) * (0.9 * s / M)
			local ball = Instance.new("Part")
			ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.CastShadow =
				true, false, false, false, false
			ball.Shape = Enum.PartType.Ball
			ball.Material = Enum.Material.Neon
			ball.Color = Color3.fromRGB(255, 214, 120)
			ball.Size = Vector3.one * (0.9 * s / M)
			ball.CFrame = CFrame.new(pos + off * 0.3)
			ball.Parent = fx
			local dur = (0.55 + 0.1 * i) * v.tempoK
			TweenService:Create(ball, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				-- a bomba de 250 lb: ~15 m de bola de fogo (a 1ª versão saiu do tamanho de uma árvore)
				Size = Vector3.one * ((3.2 + 0.3 * i) * s / M),
				CFrame = CFrame.new(pos + off + Vector3.new(0, 1.6 * s / M, 0)),
				Color = Color3.fromRGB(90, 42, 22),
				Transparency = 1,
			}):Play()
			Debris:AddItem(ball, dur + 0.05)
		end
		emitter(anchor, {
			Texture = TEX.core,
			LightEmission = 1,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 160)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 40)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 34, 20)),
			}),
			Size = seq(0, 1.4 * s / M, 0.5, 3.2 * s / M, 1, 4.2 * s / M),
			Transparency = seq(0, 0.05, 0.7, 0.4, 1, 1),
			Lifetime = NumberRange.new(0.6 * v.tempoK, 1.1 * v.tempoK),
			Speed = NumberRange.new(3 / M, 9 / M),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, 5 / M, 0),
			Rotation = NumberRange.new(0, 360),
		}):Emit(math.max(4, math.floor(10 * s * det)))
	end
	-- faíscas e estilhaços incandescentes
	emitter(anchor, {
		Texture = TEX.sparks,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 120)),
		Size = seq(0, 0.16 / M, 1, 0),
		Lifetime = NumberRange.new(0.6, 1.4),
		Speed = NumberRange.new(16 / M, 34 / M),
		SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, -9.8 / M, 0),
		Drag = 1,
	}):Emit(math.floor(24 * s * det))
	-- 3) anel de poeira (ou de água) que corre rente ao chão: 8 jatos em volta
	for i = 0, 7 do
		local att = Instance.new("Attachment")
		att.CFrame = CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.Angles(math.rad(-4), 0, 0)
		att.Parent = anchor
		emitter(att, {
			Texture = TEX.dust,
			EmissionDirection = Enum.NormalId.Front,
			-- clara: a smoke_main some com cor escura (D-198); 1ª versão rápida demais (376 studs/s) e rala
			Color = ColorSequence.new(
				rgb(cor.poeira):Lerp(Color3.new(1, 1, 1), 0.25),
				rgb(cor.poeira):Lerp(Color3.new(0.85, 0.83, 0.8), 0.5)
			),
			Size = seq(0, 1.6 * s / M, 1, 4.6 * s / M),
			Transparency = seq(0, if agua then 0.1 else 0.15, 0.6, 0.45, 1, 1),
			Lifetime = NumberRange.new(2.4, 4),
			Speed = NumberRange.new(7 * s / M, 11 * s / M),
			SpreadAngle = Vector2.new(14, 5),
			Drag = 2.6,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
		}):Emit(math.max(2, math.floor(6 * det)))
	end
	-- água: a coluna branca alta e a chuva de gotas no lugar dos pedaços
	if agua then
		emitter(anchor, {
			Texture = TEX.dust,
			Color = ColorSequence.new(Color3.fromRGB(240, 242, 240), Color3.fromRGB(196, 204, 200)),
			Size = seq(0, 0.6 * s / M, 0.5, 1.6 * s / M, 1, 2.4 * s / M),
			Transparency = seq(0, 0.05, 0.7, 0.4, 1, 1),
			Lifetime = NumberRange.new(1.4, 2.4),
			Speed = NumberRange.new(12 * s / M, 20 * s / M),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(0, -9.8 / M, 0),
			Drag = 0.4,
			Rotation = NumberRange.new(0, 360),
		}):Emit(math.floor(30 * s * det))
	end
	-- 4) coluna de fumaça: sai por um tempo, sobe e pende com o vento (a inclinação da variação)
	local col = Instance.new("Attachment")
	col.CFrame = CFrame.Angles(v.inclina, 0, v.inclina * 0.6)
	col.Parent = anchor
	local smoke = emitter(col, {
		Texture = if agua then TEX.dust else TEX.escura,
		EmissionDirection = Enum.NormalId.Top,
		Color = if agua
			then ColorSequence.new(Color3.fromRGB(220, 224, 222), Color3.fromRGB(180, 186, 184))
			else ColorSequence.new(Color3.fromRGB(235, 222, 205), Color3.fromRGB(255, 252, 246)),
		Size = seq(0, 2 * s / M, 0.4, 4.5 * s / M, 1, 7 * s / M),
		-- a 2ª versão saiu um borrão preto: mais transparente, e a poeira clara de baixo dá os tons
		Transparency = seq(0, 0.35, 0.6, 0.55, 1, 1),
		Lifetime = NumberRange.new(10, 15),
		Speed = NumberRange.new(5 / M, 9 / M),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(0.5 / M, 0.6 / M, 0.25 / M),
		Drag = 0.6,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-8, 8),
		Rate = if agua then 3 * det else 7 * det,
	})
	smoke.Enabled = true
	-- a poeira clara que sobe junto (terra e cinza): a coluna fica cinza-marrom embaixo e escura em cima
	local poeira = if agua
		then nil
		else emitter(col, {
			Texture = TEX.dust,
			EmissionDirection = Enum.NormalId.Top,
			Color = ColorSequence.new(rgb(cor.poeira):Lerp(Color3.new(1, 1, 1), 0.3), Color3.fromRGB(205, 200, 190)),
			Size = seq(0, 2.2 * s / M, 1, 6 * s / M),
			Transparency = seq(0, 0.3, 0.6, 0.6, 1, 1),
			Lifetime = NumberRange.new(6, 10),
			Speed = NumberRange.new(3 / M, 6 / M),
			SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(0.4 / M, 0.3 / M, 0.2 / M),
			Drag = 0.8,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-8, 8),
			Rate = 6 * det,
		})
	if poeira then
		poeira.Enabled = true
	end
	task.delay(math.min(colunaS * 0.35, 6) * (if agua then 0.5 else 1), function()
		smoke.Enabled = false
		if poeira then
			poeira.Enabled = false
		end
	end)
	-- 5) detritos com física: torrões, galhos e folhas, ou tábuas, com teto ao mesmo tempo
	local n = math.min(math.floor((T.detritos or 6) * det), LIM.detritos - ativos.detritos)
	if not agua and n > 0 then
		ativos.detritos += n
		task.delay(5, function()
			ativos.detritos -= n
		end)
		local rng = Random.new(seedN)
		for _ = 1, n do
			local p = Instance.new("Part")
			p.CanQuery, p.CanTouch = false, false
			if sup == "estrutura" then
				p.Size = Vector3.new(rng:NextNumber(0.4, 0.9), 0.04, rng:NextNumber(0.08, 0.14)) / M
				p.Material = Enum.Material.Wood
			elseif sup == "vegetacao" then
				p.Size = Vector3.new(rng:NextNumber(0.2, 0.6), 0.03, rng:NextNumber(0.03, 0.08)) / M
				p.Material = Enum.Material.Grass
			else
				local e = rng:NextNumber(0.12, 0.3)
				p.Size = Vector3.new(e, e * 0.8, e) / M
				p.Material = Enum.Material.Ground
			end
			p.Color = rgb(cor.pedaco):Lerp(Color3.new(0.2, 0.18, 0.15), rng:NextNumber(0, 0.4))
			p.CFrame = CFrame.new(pos + Vector3.new(0, 1 / M, 0))
				* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
			p.Parent = fx
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.8, 1.8), rng:NextNumber(-1, 1)).Unit
			p.AssemblyLinearVelocity = dir * rng:NextNumber(12, 24) / M
			p.AssemblyAngularVelocity =
				Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
			Debris:AddItem(p, 5)
		end
	end
	-- 6) tremor pela distância, vezes o ajuste do jogador
	shake = math.min(1.5, shake + ExplosaoEfeito.tremor(dM, s, ajusteTremor()))
end

Net.unreliable("Fire_Impact").OnClientEvent:Connect(function(e: any)
	if type(e) == "table" and type(e.x) == "number" then
		local id = tostring(e.id)
		local pos = Vector3.new(e.x, e.y, e.z)
		if ExplosaoEfeito.de(id).classe == "pesada" then
			explodeGrande(id, pos)
		else
			explode(id, pos)
		end
	end
end)

-- ===== granada no ar e no chão =====
-- O servidor simula um núcleo de 1 stud (invisível); aqui a granada desenhada segue o núcleo,
-- girando com ele, e encosta no chão quando para (senão ficaria 10 cm no ar).
type Live = { core: BasePart, model: Model, r: number }
local live: { [Instance]: Live } = {}
local restParams = RaycastParams.new()
restParams.FilterType = Enum.RaycastFilterType.Exclude

local function track(g: Instance)
	if not g:IsA("Model") or live[g] then
		return
	end
	local core = g:WaitForChild("Nucleo", 3)
	if not core or not core:IsA("BasePart") then
		return
	end
	local kind = g:GetAttribute("Kind")
	local faction = g:GetAttribute("Faction")
	local model, r = GrenadeArt.build(
		if type(kind) == "string" then kind else "frag",
		if type(faction) == "string" then faction else nil
	)
	model.Parent = fx
	live[g] = { core = core, model = model, r = r }
end

task.spawn(function()
	local folder = workspace:WaitForChild("Granadas", 120)
	if folder then
		for _, g in folder:GetChildren() do
			task.spawn(track, g)
		end
		folder.ChildAdded:Connect(track)
	end
end)

RunService.RenderStepped:Connect(function()
	for g, l in live do
		if g.Parent == nil or l.core.Parent == nil then
			l.model:Destroy()
			live[g] = nil
			continue
		end
		local pos = l.core.Position
		restParams.FilterDescendantsInstances = { fx, g, camera }
		local hit = workspace:Raycast(pos, Vector3.new(0, -0.9, 0), restParams)
		local at = if hit and (pos - hit.Position).Magnitude < 0.62 then hit.Position + hit.Normal * l.r else pos
		l.model:PivotTo(CFrame.new(at) * l.core.CFrame.Rotation)
	end
end)
