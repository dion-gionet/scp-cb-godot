extends RefCounted
# Raw DEFLATE decoder (RFC 1951). Godot's own decompress wants a zlib or gzip wrapper with a
# checksum, which MSZIP chunks of DirectX .x files do not have.

const LENGTH_BASE := [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
const LENGTH_EXTRA := [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
const DIST_BASE := [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
const DIST_EXTRA := [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
const CODE_ORDER := [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

var _data: PackedByteArray
var _byte := 0
var _bit := 0
var out: PackedByteArray = PackedByteArray()

static func inflate(data: PackedByteArray, dictionary: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var d := new()
	d._data = data
	d.out = dictionary.duplicate()
	d._run()
	return d.out.slice(dictionary.size())

func _bits(count: int) -> int:
	var value := 0
	for i in count:
		if _byte >= _data.size():
			return value
		value |= ((_data[_byte] >> _bit) & 1) << i
		_bit += 1
		if _bit == 8:
			_bit = 0
			_byte += 1
	return value

# canonical Huffman table: {"counts": [..], "symbols": [..]}
func _table(lengths: Array) -> Dictionary:
	var counts: Array = []
	counts.resize(16)
	counts.fill(0)
	for l in lengths:
		counts[l] += 1
	counts[0] = 0
	var offsets: Array = []
	offsets.resize(16)
	offsets[1] = 0
	for i in range(1, 15):
		offsets[i + 1] = offsets[i] + counts[i]
	var symbols: Array = []
	symbols.resize(lengths.size())
	for s in lengths.size():
		if lengths[s] != 0:
			symbols[offsets[lengths[s]]] = s
			offsets[lengths[s]] += 1
	return {"counts": counts, "symbols": symbols}

func _decode(table: Dictionary) -> int:
	var code := 0
	var first := 0
	var index := 0
	var counts: Array = table.counts
	for length in range(1, 16):
		code |= _bits(1)
		var count: int = counts[length]
		if code - count < first:
			return table.symbols[index + (code - first)]
		index += count
		first += count
		first <<= 1
		code <<= 1
	return -1

func _run() -> void:
	var final := 0
	while final == 0 and _byte < _data.size():
		final = _bits(1)
		var kind := _bits(2)
		if kind == 0:
			# stored block: the rest of the current byte is padding, then LEN and NLEN, then LEN raw bytes
			if _bit != 0:
				_bit = 0
				_byte += 1
			if _byte + 4 > _data.size():
				return
			var length := _data.decode_u16(_byte)
			_byte += 4
			out.append_array(_data.slice(_byte, _byte + length))
			_byte += length
		elif kind == 1:
			var lengths: Array = []
			lengths.resize(288)
			for i in 288:
				lengths[i] = 8 if i < 144 else (9 if i < 256 else (7 if i < 280 else 8))
			var dist: Array = []
			dist.resize(30)
			dist.fill(5)
			_codes(_table(lengths), _table(dist))
		elif kind == 2:
			var nlen := _bits(5) + 257
			var ndist := _bits(5) + 1
			var ncode := _bits(4) + 4
			var cl: Array = []
			cl.resize(19)
			cl.fill(0)
			for i in ncode:
				cl[CODE_ORDER[i]] = _bits(3)
			var cl_table := _table(cl)
			var lengths: Array = []
			while lengths.size() < nlen + ndist:
				var sym := _decode(cl_table)
				if sym < 0:
					return      # bad or truncated data
				if sym < 16:
					lengths.append(sym)
				else:
					var prev := 0
					var repeat := 0
					if sym == 16:
						if lengths.is_empty():
							return
						prev = lengths[lengths.size() - 1]
						repeat = 3 + _bits(2)
					elif sym == 17:
						repeat = 3 + _bits(3)
					else:
						repeat = 11 + _bits(7)
					for i in repeat:
						lengths.append(prev)
			_codes(_table(lengths.slice(0, nlen)), _table(lengths.slice(nlen)))
		else:
			return

func _codes(lit: Dictionary, dist: Dictionary) -> void:
	while _byte < _data.size():     # every bit read: what follows would be made up
		var sym := _decode(lit)
		if sym < 0 or sym == 256:
			return
		if sym < 256:
			out.append(sym)
		else:
			sym -= 257
			if sym >= LENGTH_BASE.size():
				return
			var length: int = LENGTH_BASE[sym] + _bits(LENGTH_EXTRA[sym])
			var ds := _decode(dist)
			if ds < 0 or ds >= DIST_BASE.size():
				return
			var distance: int = DIST_BASE[ds] + _bits(DIST_EXTRA[ds])
			var start := out.size() - distance
			if start < 0:
				return
			for i in length:
				out.append(out[start + i])
