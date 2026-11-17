extends RefCounted
class_name BlitzRng
# Blitz3D's SeedRnd / Rnd / Rand (bbmath.cpp): a Park-Miller generator, x = 48271 * x mod (2^31 - 1) by Schrage's method.
# Every Rnd or Rand call advances it exactly once whatever its range, so a port only reproduces a 1.3.11 sequence when it
# makes the same calls in the same order.
# randi_range / randf_range let it stand in where a RandomNumberGenerator was used.

const A := 48271
const M := 2147483647
const Q := 44488
const R := 3399

var state := 1

static func seed_number(text: String) -> int:
	# GenerateSeedNumber (Main.bb): XOR of the character codes, each shifted left by 0..23 in turn
	var value := 0
	var shift := 0
	for i in text.length():
		value = value ^ (text.unicode_at(i) << shift)
		shift = (shift + 1) % 24
	return value

func seed_rnd(value: int) -> void:
	value = value & 0x7fffffff
	state = value if value != 0 else 1

func _next() -> float:
	state = A * (state % Q) - R * (state / Q)
	if state < 0:
		state += M
	return float(state & 65535) / 65536.0 + 0.5 / 65536.0

# Rand(from, to = 1): the bounds are swapped when to < from, so Rand(n) is 1..n.
func rand(from: int, to: int = 1) -> int:
	if to < from:
		var t := from
		from = to
		to = t
	return int(_next() * float(to - from + 1)) + from

# Rnd(from, to = 0): Rnd(n) is n - n * r, not n * r.
func rnd(from: float, to: float = 0.0) -> float:
	return _f32(_next() * (_f32(to) - _f32(from)) + _f32(from))

func randi_range(from: int, to: int) -> int:
	return rand(from, to)

func randf_range(from: float, to: float) -> float:
	return rnd(from, to)

static func _f32(value: float) -> float:
	var packed := PackedFloat32Array([value])
	return packed[0]
