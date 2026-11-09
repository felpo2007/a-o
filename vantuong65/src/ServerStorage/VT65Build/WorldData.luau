--!strict
-- Acesso às alturas e ao uso do solo exportados (grade de 16 studs = 4,48 m).
-- Funciona no Roblox e no Lune: recebe os módulos de dados já carregados.
-- require duplo: no Roblox usa script.Parent; no Lune (sem "script"), caminho relativo.
local Base64 = (if (script :: any) ~= nil then require((script :: any).Parent.Base64) else require("./Base64")) :: any

export type GridSpec = {
	width: number,
	height: number,
	cellStuds: number,
	originX: number,
	originZ: number,
	heightOffsetCm: number,
	heightChunks: { string },
	rowsPerChunk: number,
	classNames: { string },
	classesRle: string,
}

export type World = {
	grid: GridSpec,
	heights: buffer, -- u16 por célula, cm + offset
	classes: buffer, -- u8 por célula
	heightAt: (self: World, x: number, z: number) -> number, -- studs
	classAt: (self: World, x: number, z: number) -> number,
	cellHeight: (self: World, col: number, row: number) -> number, -- studs
}

local STUD_M = 0.28

local WorldData = {}

-- chunks: lista de { row0, rows, data } na ordem de grid.heightChunks
function WorldData.load(grid: GridSpec, chunks: { { row0: number, rows: number, data: string } }): World
	local w, h = grid.width, grid.height
	local heights = buffer.create(w * h * 2)
	for _, ch in chunks do
		local b = Base64.decode(ch.data)
		buffer.copy(heights, ch.row0 * w * 2, b, 0, buffer.len(b))
	end
	local rle = Base64.decode(grid.classesRle)
	local classes = buffer.create(w * h)
	local o = 0
	for i = 0, buffer.len(rle) - 2, 2 do
		local c = buffer.readu8(rle, i)
		local n = buffer.readu8(rle, i + 1)
		buffer.fill(classes, o, c, n)
		o += n
	end
	assert(o == w * h, "RLE de classes inconsistente")

	local self = { grid = grid, heights = heights, classes = classes } :: any

	function self.cellHeight(_: World, col: number, row: number): number
		col = math.clamp(col, 0, w - 1)
		row = math.clamp(row, 0, h - 1)
		local cm = buffer.readu16(heights, (row * w + col) * 2) - grid.heightOffsetCm
		return cm / 100 / STUD_M
	end

	-- bilinear entre centros de célula
	function self.heightAt(me: World, x: number, z: number): number
		local fx = (x - grid.originX) / grid.cellStuds - 0.5
		local fz = (z - grid.originZ) / grid.cellStuds - 0.5
		local c0, r0 = math.floor(fx), math.floor(fz)
		local tx, tz = fx - c0, fz - r0
		local h00 = me:cellHeight(c0, r0)
		local h10 = me:cellHeight(c0 + 1, r0)
		local h01 = me:cellHeight(c0, r0 + 1)
		local h11 = me:cellHeight(c0 + 1, r0 + 1)
		return (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz
	end

	function self.classAt(_: World, x: number, z: number): number
		local col = math.clamp(math.floor((x - grid.originX) / grid.cellStuds), 0, w - 1)
		local row = math.clamp(math.floor((z - grid.originZ) / grid.cellStuds), 0, h - 1)
		return buffer.readu8(classes, row * w + col)
	end

	return self :: World
end

return WorldData
