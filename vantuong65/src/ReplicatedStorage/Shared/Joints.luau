--!strict
-- Juntas do avatar R15. Eram Motor6D; com a atualização de juntas do avatar do Roblox elas vêm como
-- AnimationConstraint (reteste no Studio 0.746, 2026-11-10: as 15 juntas de jogadores e bots).
-- A pose de repouso de uma AnimationConstraint é o CFrame do Attachment0, que faz o papel do C0 do
-- Motor6D (C0 · Transform · C1⁻¹ ≡ A0 · Transform · A1⁻¹). Sem isto, agachar, inclinar e deitar não
-- posavam ninguém: o código só mexia em Motor6D.
local Joints = {}

-- Junta pelo nome ("Root", "LeftKnee", "Waist"…), seja Motor6D ou AnimationConstraint.
function Joints.find(parent: Instance, name: string): Instance?
	local j = parent:FindFirstChild(name, true)
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return j
	end
	return nil
end

-- "C0" da junta: Motor6D.C0 ou o CFrame do Attachment0.
function Joints.getC0(j: Instance): CFrame?
	if j:IsA("Motor6D") then
		return j.C0
	elseif j:IsA("AnimationConstraint") then
		local a0 = j.Attachment0
		return if a0 then a0.CFrame else nil
	end
	return nil
end

function Joints.setC0(j: Instance, cf: CFrame)
	if j:IsA("Motor6D") then
		j.C0 = cf
	elseif j:IsA("AnimationConstraint") then
		local a0 = j.Attachment0
		if a0 then
			a0.CFrame = cf
		end
	end
end

return Joints
