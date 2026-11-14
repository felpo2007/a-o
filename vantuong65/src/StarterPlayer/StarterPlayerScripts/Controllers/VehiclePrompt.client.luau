--!strict
-- Entrar nos veículos e escolher o lugar (D-100; pedido do dono, 2026-11-12: "coloque a interface do
-- botão para eu entrar neles ou pilotar quando chegar perto"; antes o jogador sentava no lugar que
-- encostasse, caía como "MUNICIADOR · Passageiro" no M48 e não tinha como dirigir).
-- - Perto de um veículo do próprio lado aparece o cartão do ProximityPrompt "VT65Embarcar"
--   (VehicleService, estilo Custom): nome, lugares livres e "segure X / F para entrar"; no mouse e no
--   toque, um clique no cartão.
-- - O painel lista os lugares (Motorista ou Piloto, Atirador, Comandante, Municiador, Carona, Tropa),
--   livre ou ocupado; o que pede papel mostra "Trocar para Tripulante/Piloto e entrar" (a regra é de
--   Roles; o servidor confere tudo no remote Vehicle_Board). Dentro: trocar de lugar, sair e, se o
--   veículo tombou ou está preso, desvirar. No controle: direcional + A, B fecha.
-- - Dentro do veículo o painel abre segurando Y (C no teclado) (VehicleController, Bus "vehicle_panel").
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Roles = require(ReplicatedStorage.Shared.Roles)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)
local Bus = require(script.Parent.Bus)
local Input = require(script.Parent.Input)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer
local V, F = UiKit.V, UiKit.F
local PROMPT = "VT65Embarcar"
local KIND_PT: { [string]: string } = {
	tracked = "Blindado",
	amphibious = "Anfíbio",
	heli = "Helicóptero",
	wheeled = "Viatura",
}
local SIDE_PT: { [string]: string } = { US = "EUA", VC = "VC" }

local function sideColor(faction: any): Color3
	return if faction == "VC" then V.VC else V.US
end

local function humanoid(): Humanoid?
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

local function vehicleOf(inst: Instance?): Model?
	local m = inst and inst:FindFirstAncestorWhichIsA("Model")
	while m and not m:GetAttribute("VehicleId") do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m
end

local function seatOf(model: Model, id: string): Seat?
	local s = model:FindFirstChild("Seat_" .. id)
	return if s and s:IsA("Seat") then s else nil
end

local function freeSeats(model: Model): (number, number)
	local free, total = 0, 0
	for _, s in model:GetChildren() do
		if s:IsA("Seat") and not s.Disabled then
			total += 1
			if not s.Occupant then
				free += 1
			end
		end
	end
	return free, total
end

local gui = UiKit.screen("VT65Embarque", 31)

-- ===== cartão do prompt (perto do veículo) =====
local card = Instance.new("TextButton")
card.Name = "Cartao"
card.Text = ""
card.AutoButtonColor = false
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 1, -UiKit.px(170, 230))
card.Size = UDim2.fromOffset(UiKit.px(320, 460), UiKit.px(70, 100))
card.BackgroundColor3 = V.PANEL
card.BackgroundTransparency = 0.1
card.BorderSizePixel = 0
card.Visible = false
card.Selectable = false
card.Parent = gui
UiKit.corner(card, 4)
UiKit.stroke(card, V.LINE, 1, 0.5)
local cardStripe = Instance.new("Frame")
cardStripe.Size = UDim2.new(0, UiKit.px(4, 6), 1, 0)
cardStripe.BorderSizePixel = 0
cardStripe.Parent = card
local P = UiKit.px(14, 20)
local cardKicker = UiKit.kicker(card, "", 12)
cardKicker.Position = UDim2.fromOffset(P, UiKit.px(6, 8))
cardKicker.Size = UDim2.new(1, -2 * P, 0, UiKit.px(16, 24))
local cardTitle = UiKit.title(card, "", 20)
cardTitle.Position = UDim2.fromOffset(P, UiKit.px(20, 30))
cardTitle.Size = UDim2.new(1, -2 * P, 0, UiKit.px(24, 34))
local cardHint = UiKit.text2(card, "", 13, V.DIM, F.BODY)
cardHint.Position = UDim2.fromOffset(P, UiKit.px(44, 64))
cardHint.Size = UDim2.new(1, -2 * P, 0, UiKit.px(18, 26))
local holdBack, holdFill = UiKit.bar(card, UiKit.px(3, 4), V.BRASS)
holdBack.AnchorPoint = Vector2.new(0, 1)
holdBack.Position = UDim2.new(0, 0, 1, 0)
holdBack.BackgroundTransparency = 1

local shown: ProximityPrompt? = nil
local holdTween: Tween? = nil

local function myFaction(): any
	return player:GetAttribute("Faction")
end

local function cardFor(prompt: ProximityPrompt)
	local model = vehicleOf(prompt)
	if not model then
		return
	end
	local spec = Vehicles.SPECS[tostring(model:GetAttribute("Spec"))]
	local faction = model:GetAttribute("Faction")
	cardStripe.BackgroundColor3 = sideColor(faction)
	cardKicker.Text = UiKit.upper(
		string.format("%s · %s", SIDE_PT[tostring(faction)] or "", KIND_PT[spec and spec.kind or ""] or "Veículo")
	)
	cardTitle.Text = UiKit.upper(if spec then spec.name else model.Name)
	cardTitle.FontFace = UiKit.headFont(cardTitle.Text)
	local free, total = freeSeats(model)
	local key = if Input.isGamepad() then "X" elseif Input.device() == "touch" then "" else "F"
	cardHint.Text = if key == ""
		then string.format("Toque para entrar · %d de %d lugares livres", free, total)
		else string.format("Segure %s para entrar · %d de %d lugares livres", key, free, total)
end

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
	if prompt.Name ~= PROMPT then
		return
	end
	local model = vehicleOf(prompt)
	if not model or model:GetAttribute("Faction") ~= myFaction() then
		prompt.Enabled = false -- veículo do outro lado: nem o cartão nem a tecla (só neste cliente)
		return
	end
	local h = humanoid()
	if h and h.SeatPart then
		return -- dentro: o painel abre segurando Y / C
	end
	shown = prompt
	cardFor(prompt)
	holdFill.Size = UDim2.fromScale(0, 1)
	card.Visible = Input.state.menus == 0
end)

ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
	if prompt == shown then
		shown = nil
		card.Visible = false
	end
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
	if prompt ~= shown then
		return
	end
	holdFill.Size = UDim2.fromScale(0, 1)
	local t = TweenService:Create(holdFill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 1),
	})
	holdTween = t
	t:Play()
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
	if prompt ~= shown then
		return
	end
	local t = holdTween
	if t then
		t:Cancel()
		holdTween = nil
	end
	holdFill.Size = UDim2.fromScale(0, 1)
end)

-- o lado mudou (troca de time): os prompts apagados neste cliente voltam
player:GetAttributeChangedSignal("Faction"):Connect(function()
	local folder = workspace:FindFirstChild("Vehicles")
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == PROMPT then
				d.Enabled = vehicleOf(d) ~= nil and (vehicleOf(d) :: Model):GetAttribute("Faction") == myFaction()
			end
		end
	end
end)

-- ===== painel de lugares =====
local panel = UiKit.panel(gui, V.PANEL, 0.04, true)
panel.Name = "Lugares"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
local W = UiKit.px(440, 640)
panel.Size = UDim2.fromOffset(W, 200)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Visible = false
local stripe = Instance.new("Frame")
stripe.Size = UDim2.new(1, 0, 0, UiKit.px(4, 6))
stripe.BorderSizePixel = 0
stripe.Parent = panel
local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, 0, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.Parent = panel
UiKit.pad(body, P, P, UiKit.px(14, 20), UiKit.px(14, 20))
UiKit.list(body, false, UiKit.px(6, 9))
local kicker = UiKit.kicker(body, "", 13)
kicker.Size = UDim2.new(1, 0, 0, UiKit.px(18, 26))
kicker.LayoutOrder = 1
local title = UiKit.title(body, "", 26)
title.Size = UDim2.new(1, 0, 0, UiKit.px(32, 46))
title.LayoutOrder = 2
local rows = Instance.new("Frame")
rows.Name = "Lista"
rows.BackgroundTransparency = 1
rows.Size = UDim2.new(1, 0, 0, 0)
rows.AutomaticSize = Enum.AutomaticSize.Y
rows.LayoutOrder = 3
rows.Parent = body
UiKit.list(rows, false, UiKit.px(4, 6))
local foot = UiKit.chips(body, UiKit.px(26, 38), false, 13)
foot.frame.LayoutOrder = 4
local fit = UiKit.fit(gui, panel, W, UiKit.px(560, 820))

type Row = { action: UiKit.Action, refresh: () -> () }
local open = { model = nil :: Model?, rows = {} :: { Row }, at = 0 }

local function close()
	if not panel.Visible then
		return
	end
	panel.Visible = false
	UiKit.release(panel)
	UiKit.closed("embarque")
	Input.closeMenu()
	open.model = nil
	for _, r in open.rows do
		r.action.button:Destroy()
	end
	table.clear(open.rows)
end

local function request(req: { [string]: any })
	Net.event("Vehicle_Board"):FireServer(req)
	close()
end

local function addRow(text: string, kind: string, order: number, onClick: () -> (), refresh: ((UiKit.Action) -> ())?)
	local a = UiKit.action(rows, text, kind, onClick, { action = nil, ctx = nil, h = UiKit.px(44, 62) })
	a.button.LayoutOrder = order
	local row: Row = {
		action = a,
		refresh = function()
			if refresh then
				refresh(a)
			end
		end,
	}
	row.refresh()
	table.insert(open.rows, row)
	return a
end

local function tippedOrStuck(model: Model): boolean
	local ch = model:FindFirstChild("Chassis") :: BasePart?
	return ch ~= nil and (Vehicles.tipped(ch.CFrame.UpVector.Y) or model:GetAttribute("Stuck") == true)
end

local function openPanel(model: Model)
	local specId = tostring(model:GetAttribute("Spec"))
	local spec = Vehicles.SPECS[specId]
	local h = humanoid()
	if not (spec and h) or model:GetAttribute("Destroyed") then
		return
	end
	if panel.Visible then
		close()
	end
	open.model = model
	open.at = os.clock()
	local faction = model:GetAttribute("Faction")
	stripe.BackgroundColor3 = sideColor(faction)
	kicker.Text = UiKit.upper(
		string.format("%s · %s · escolha o lugar", SIDE_PT[tostring(faction)] or "", KIND_PT[spec.kind] or "")
	)
	title.Text = UiKit.upper(spec.name)
	title.FontFace = UiKit.headFont(title.Text)
	local hum = h :: Humanoid
	local inside = hum.SeatPart ~= nil and vehicleOf(hum.SeatPart) == model
	for i, info in Vehicles.seatList(specId) do
		addRow(UiKit.upper(info.label), "secondary", i, function()
			local seat = seatOf(model, info.id)
			if not seat or (seat.Occupant and seat.Occupant ~= hum) then
				Bus.fire("toast", "Lugar ocupado")
				return
			end
			local role, crew = player:GetAttribute("Role"), player:GetAttribute("VehicleCrew")
			local ok = Roles.canTakeSeat(
				spec.kind,
				info.id,
				if type(role) == "string" then role else nil,
				if type(crew) == "string" then crew else nil
			)
			request({ v = model, seat = info.id, crew = not ok })
		end, function(a: UiKit.Action)
			local seat = seatOf(model, info.id)
			local occ = seat and seat.Occupant
			local role, crew = player:GetAttribute("Role"), player:GetAttribute("VehicleCrew")
			local ok, need = Roles.canTakeSeat(
				spec.kind,
				info.id,
				if type(role) == "string" then role else nil,
				if type(crew) == "string" then crew else nil
			)
			local extra = if info.weapon == "gun_90" or info.weapon == "rr_106"
				then " · CANHÃO"
				elseif info.weapon then " · M60"
				elseif info.open then " · ATIRA"
				else ""
			if not seat or seat.Disabled then
				a.sub.Text = "—"
				a.enabled(false)
			elseif occ == hum then
				a.sub.Text = "VOCÊ"
				a.enabled(false)
			elseif occ then
				a.sub.Text = "OCUPADO"
				a.enabled(false)
			elseif not ok and need then
				a.sub.Text = UiKit.upper(string.format("trocar p/ %s", Roles.CREW_NAME[need] or need))
				a.enabled(true)
			else
				a.sub.Text = "LIVRE" .. extra
				a.enabled(true)
			end
		end)
	end
	local n = #open.rows
	addRow("DESVIRAR", "danger", n + 1, function()
		request({ op = "recover", v = model })
	end, function(a: UiKit.Action)
		a.button.Visible = tippedOrStuck(model)
	end)
	if inside then
		addRow("SAIR DO VEÍCULO", "secondary", n + 2, function()
			request({ op = "exit" })
		end)
	end
	addRow("FECHAR", "ghost", n + 3, close)
	foot.clear()
	foot.action("ui_back", "menu", "Fechar")
	panel.Visible = true
	card.Visible = false
	Input.openMenu()
	UiKit.opened("embarque", 31)
	fit.play(UiKit.SOFT, 1, 0.94)
	UiKit.focus(rows)
end

-- tecla (segurar X / F) no prompt
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	if prompt.Name ~= PROMPT then
		return
	end
	local h = humanoid()
	local model = vehicleOf(prompt)
	if model and h and not h.SeatPart and model:GetAttribute("Faction") == myFaction() then
		openPanel(model)
	end
end)
-- mouse e toque: clique no cartão
card.Activated:Connect(function()
	local p = shown
	local model = p and vehicleOf(p)
	if model then
		openPanel(model)
	end
end)
-- dentro do veículo: Y segurado / C (VehicleController)
Bus.on("vehicle_panel", function(model: Model)
	if panel.Visible then
		close()
	else
		openPanel(model)
	end
end)
Input.on("ui_back", "press", function()
	if panel.Visible and UiKit.backFor("embarque") then
		close()
	end
end)

-- o servidor explica a recusa (ocupado, papel, longe) ou o que mudou (papel de campo, desvirado)
Net.event("Vehicle_Notice").OnClientEvent:Connect(function(msg: any)
	if type(msg) == "string" then
		Bus.fire("toast", msg)
	end
end)

-- prompts do próprio veículo apagados enquanto sentado (X é recarregar/munição dentro)
local function setPrompts(on: boolean)
	local folder = workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == PROMPT then
			local m = vehicleOf(d)
			d.Enabled = on and m ~= nil and (m :: Model):GetAttribute("Faction") == myFaction()
		end
	end
end
local function watch(char: Model)
	local h = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not h then
		return
	end
	h:GetPropertyChangedSignal("SeatPart"):Connect(function()
		setPrompts(h.SeatPart == nil)
		if h.SeatPart then
			card.Visible = false
		end
	end)
	h.Died:Connect(close)
end
player.CharacterAdded:Connect(watch)
if player.Character then
	task.spawn(watch, player.Character)
end

-- painel aberto: lugares ao vivo; fecha se o veículo sumiu, explodiu ou ficou longe
local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += dt
	if acc < 0.2 then
		return
	end
	acc = 0
	if shown and card.Visible then
		cardFor(shown :: ProximityPrompt)
	end
	if shown then
		local hh = humanoid()
		card.Visible = Input.state.menus == 0 and not panel.Visible and hh ~= nil and hh.SeatPart == nil
	end
	local model = open.model
	if not (model and panel.Visible) then
		return
	end
	local h = humanoid()
	local ch = model:FindFirstChild("Chassis") :: BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (h and ch and root) or model.Parent == nil or model:GetAttribute("Destroyed") then
		close()
		return
	end
	local inside = (h :: Humanoid).SeatPart ~= nil
	local far = Vector3.new(root.Position.X - ch.Position.X, 0, root.Position.Z - ch.Position.Z).Magnitude
		> math.max(ch.Size.X, ch.Size.Z) / 2 + 6 / 0.28
	if not inside and far then
		close()
		return
	end
	for _, r in open.rows do
		r.refresh()
	end
end)
