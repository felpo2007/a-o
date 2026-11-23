--!strict
-- Barramento de eventos entre os controllers do cliente (roda → comandante, mapa → spawn etc.).
local Bus = {}
local events: { [string]: BindableEvent } = {}

local function get(name: string): BindableEvent
	local e = events[name]
	if not e then
		e = Instance.new("BindableEvent")
		events[name] = e
	end
	return e :: BindableEvent
end

function Bus.fire(name: string, ...: any)
	get(name):Fire(...)
end

function Bus.on(name: string, fn: (...any) -> ()): RBXScriptConnection
	return get(name).Event:Connect(fn)
end

return Bus
