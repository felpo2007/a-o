--!strict
-- Decodificador base64 -> buffer (dados de terreno exportados pelo Python).
local Base64 = {}

local lookup: { [number]: number } = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		lookup[string.byte(chars, i)] = i - 1
	end
end

function Base64.decode(s: string): buffer
	local len = #s
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local outLen = (len // 4) * 3 - pad
	local out = buffer.create(outLen)
	local o = 0
	for i = 1, len, 4 do
		local a = lookup[string.byte(s, i)] or 0
		local b = lookup[string.byte(s, i + 1)] or 0
		local c = lookup[string.byte(s, i + 2)] or 0
		local d = lookup[string.byte(s, i + 3)] or 0
		local n = a * 262144 + b * 4096 + c * 64 + d
		if o < outLen then
			buffer.writeu8(out, o, n // 65536)
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, (n // 256) % 256)
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, n % 256)
		end
		o += 3
	end
	return out
end

return Base64
