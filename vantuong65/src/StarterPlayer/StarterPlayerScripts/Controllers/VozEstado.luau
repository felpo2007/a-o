--!strict
-- Estado da voz para a interface (ícone de quem fala no HUD). Escrito só pelo Voz.client; a interface
-- lê com VozEstado.get(userId) ou ouve VozEstado.Changed. Só traz ALIADOS (o próprio jogador incluído):
-- o inimigo nunca entra aqui, nem quando é ouvido de perto.
local VozEstado = {}

export type Speaker = {
	talking: boolean, -- a voz dele está chegando agora (perto ou pelo rádio)
	radio: boolean, -- companheiro do squad com o rádio aberto
}

VozEstado.available = false -- a voz do jogo está montada e este jogador tem a voz ligada no Roblox
VozEstado.transmitting = false -- este jogador está no rádio (o servidor aceitou)
VozEstado.speakers = {} :: { [number]: Speaker }

local changed = Instance.new("BindableEvent")
-- (userId, talking, radio). userId 0: mudou available ou transmitting.
VozEstado.Changed = changed.Event

function VozEstado.get(userId: number): (boolean, boolean)
	local s = VozEstado.speakers[userId]
	if s then
		return s.talking, s.radio
	end
	return false, false
end

function VozEstado.set(userId: number, talking: boolean, radio: boolean)
	local s = VozEstado.speakers[userId]
	if (s and s.talking == talking and s.radio == radio) or (not s and not talking and not radio) then
		return
	end
	if talking or radio then
		VozEstado.speakers[userId] = { talking = talking, radio = radio }
	else
		VozEstado.speakers[userId] = nil
	end
	changed:Fire(userId, talking, radio)
end

function VozEstado.setSelf(available: boolean, transmitting: boolean)
	if VozEstado.available == available and VozEstado.transmitting == transmitting then
		return
	end
	VozEstado.available, VozEstado.transmitting = available, transmitting
	changed:Fire(0, transmitting, transmitting)
end

return VozEstado
