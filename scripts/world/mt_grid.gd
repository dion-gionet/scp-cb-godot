class_name MtGrid
extends RefCounted
# The maintenance tunnels' layout (UpdateEvents.bb "room2tunnel" 3170-3560): a 19 x 19 grid, a 100-cell random walk, each cell's
# neighbour count as its kind, the generator room at the west edge, the two elevator cells, and every piece's yaw. The original seeds
# the generator again (SeedRnd GenerateSeedNumber(RandomSeed)) and puts the old state back afterwards, so the layout depends on the
# map seed alone and the draws made while the pieces are placed (the pieces' yaws, CreateItem's Rand(360), CreateDoor's Rand(8)) are
# part of that stream.
#
# Cell kinds: 0 none, 1 dead end, 2 straight or corner, 3 T, 4 cross, 5 the first elevator cell, 6 the last, 7 the generator room.
# Reads outside the array count as 0 (Blitz reads the memory next to it; no cell is ever near the edge).

const SIZE := 19
const CELLS := SIZE * SIZE

var cells := PackedInt32Array()
var angles := PackedInt32Array()     # the piece's yaw in quarter turns (angles[] of the original)
var first := Vector2i(-1, 0)         # firstX, firstY: the original writes firstX twice and never lastX, so the two start as -1,0 and 0,-1
var last := Vector2i(0, -1)
var item_yaws: Array[int] = []       # the SCP-500-01 and the night vision goggles in the generator room
var rng_state := 0
var cell_count := 0

func at(x: int, y: int) -> int:
	var index := x + y * SIZE
	return cells[index] if index >= 0 and index < CELLS else 0

static func generate(seed_value: int) -> MtGrid:
	var grid := MtGrid.new()
	grid._run(seed_value)
	return grid

func _run(seed_value: int) -> void:
	var rng := BlitzRng.new()
	rng.seed_rnd(seed_value)
	cells.resize(CELLS)
	angles.resize(CELLS)
	_walk(rng)
	_count_neighbours()
	_place_generator(rng)
	_find_elevator_cells()
	if last == first:
		push_error("The maintenance tunnels could not be generated properly!")
	_orient(rng)
	rng_state = rng.state
	for value in cells:
		if value > 0:
			cell_count += 1

func _walk(rng: BlitzRng) -> void:
	var dir := rng.rand(0, 1) << 1
	var x := SIZE / 2 + rng.rand(-2, 2)
	var y := SIZE / 2 + rng.rand(-2, 2)
	cells[x + y * SIZE] = 1
	cells[(x + 1) + y * SIZE if dir == 2 else (x - 1) + y * SIZE] = 1
	var count := 2
	while count < 100:
		var run := rng.rand(1, 5)
		run = run << rng.rand(1, 2)
		for i in range(1, run + 1):
			var moved := true
			match dir:
				0:
					if x < SIZE - 2 - (i % 2):
						x += 1
					else:
						moved = false
				1:
					if y < SIZE - 2 - (i % 2):
						y += 1
					else:
						moved = false
				2:
					if x > 1 + (i % 2):
						x -= 1
					else:
						moved = false
				3:
					if y > 1 + (i % 2):
						y -= 1
					else:
						moved = false
			if not moved:
				break
			if cells[x + y * SIZE] == 0:
				cells[x + y * SIZE] = 1
				count += 1
		dir += (rng.rand(0, 1) << 1) - 1
		while dir < 0:
			dir += 4
		while dir > 3:
			dir -= 4

func _count_neighbours() -> void:
	for y in SIZE:
		for x in SIZE:
			if cells[x + y * SIZE] > 0:
				cells[x + y * SIZE] = int(at(x, y + 1) > 0) + int(at(x, y - 1) > 0) + int(at(x + 1, y) > 0) + int(at(x - 1, y) > 0)

# The west-most column with a cell: the generator room goes beside one of its cells, tried cell by cell until a Rand(0, 1) says yes.
func _place_generator(rng: BlitzRng) -> void:
	var max_x := SIZE - 1
	var retry := false
	var x := 0
	while x <= max_x:
		for y in SIZE:
			if at(x + 1, y) > 0:
				max_x = x
				if at(x + 1, y + 1) < 3 and at(x + 1, y - 1) < 3:
					retry = true
					if rng.rand(0, 1) == 1:
						cells[x + 1 + y * SIZE] += 1
						cells[x + y * SIZE] = 7
						retry = false
						break
		if retry:
			x -= 1
		x += 1

func is_straight(x: int, y: int) -> bool:
	return (at(x + 1, y) > 0 and at(x - 1, y) > 0) or (at(x, y + 1) > 0 and at(x, y - 1) > 0)

func _find_elevator_cells() -> void:
	for y in SIZE:
		for x in SIZE:
			if at(x, y) != 2:
				continue
			if not is_straight(x, y):
				continue
			var plain := at(x - 1, y) < 3 and at(x + 1, y) < 3 and at(x, y - 1) < 3 and at(x, y + 1) < 3
			var clear := at(x - 1, y - 1) < 1 and at(x + 1, y - 1) < 1 and at(x - 1, y + 1) < 1
			if plain and clear:
				if first.x == -1 or first.y == -1:
					first = Vector2i(x, y)
				last = Vector2i(x, y)

# The placement loop's draws, in its order (rows, then columns).
func _orient(rng: BlitzRng) -> void:
	for y in SIZE:
		for x in SIZE:
			var kind := cells[x + y * SIZE]
			if kind <= 0:
				continue
			var below := at(x, y + 1)
			var above := at(x, y - 1)
			var east := at(x + 1, y)
			var west := at(x - 1, y)
			var angle := 0
			match kind:
				1, 7:
					angle = 1 if east > 0 else 3 if west > 0 else 2 if below > 0 else 0
				2:
					if Vector2i(x, y) == first or Vector2i(x, y) == last:
						cells[x + y * SIZE] = 6
					if east > 0 and west > 0:
						angle = rng.rand(0, 1) * 2 + 1
					elif below > 0 and above > 0:
						angle = rng.rand(0, 1) * 2
					elif below > 0 and east > 0:
						angle = 0
					elif below > 0 and west > 0:
						angle = 1
					elif above > 0 and east > 0:
						angle = 3
					else:
						angle = 2
					if Vector2i(x, y) == first:
						cells[x + y * SIZE] = 5
				3:
					if below > 0 and east > 0 and west > 0:
						angle = 1
					elif above > 0 and east > 0 and west > 0:
						angle = 3
					elif east > 0 and below > 0 and above > 0:
						angle = 0
					else:
						angle = 2
				_:
					angle = rng.rand(0, 3)
			angles[x + y * SIZE] = angle
			var now := cells[x + y * SIZE]
			if now == 7:
				item_yaws = [rng.rand(360), rng.rand(360)]
			if now == 5 or now == 6:
				rng.rand(8)
