--!strict
-- D-253 (prompt V5, §4: "NÃO DEVE EXISTIR VENTO NO JOGO"): o vento fica zerado no servidor e no cliente, e
-- volta a zero se algum script mudar a propriedade. O teste tests/luau/sem_vento.luau varre o código.
local SemVento = {}

local ligado = false

local function zera()
	if workspace.GlobalWind ~= Vector3.zero then
		workspace.GlobalWind = Vector3.zero
	end
	-- nem toda versão do motor deixa o script escrever a turbulência (no arquivo do place ela já é 0)
	pcall(function()
		if (workspace :: any).AirTurbulenceIntensity ~= 0 then
			(workspace :: any).AirTurbulenceIntensity = 0
		end
	end)
end

function SemVento.aplicar()
	zera()
	if ligado then
		return
	end
	ligado = true
	workspace:GetPropertyChangedSignal("GlobalWind"):Connect(zera)
	pcall(function()
		workspace:GetPropertyChangedSignal("AirTurbulenceIntensity" :: any):Connect(zera)
	end)
end

return SemVento
