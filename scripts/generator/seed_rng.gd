class_name SeedRng32
extends RefCounted

# Bit-for-bit compatible with std::mt19937. Index selection deliberately uses
# rejection sampling, matching the former Qt implementation on every platform.
const _N := 624
const _M := 397
const _MATRIX_A := 0x9908B0DF
const _UPPER_MASK := 0x80000000
const _LOWER_MASK := 0x7FFFFFFF
const _U32_MASK := 0xFFFFFFFF

var _state: Array[int] = []
var _index := _N


func _init(seed: int) -> void:
	_state.resize(_N)
	_state[0] = seed & _U32_MASK
	for index in range(1, _N):
		var previous: int = _state[index - 1]
		_state[index] = (1812433253 * (previous ^ (previous >> 30)) + index) & _U32_MASK


func next_u32() -> int:
	if _index >= _N:
		_twist()
	var value: int = _state[_index]
	_index += 1
	value ^= value >> 11
	value ^= (value << 7) & 0x9D2C5680
	value ^= (value << 15) & 0xEFC60000
	value ^= value >> 18
	return value & _U32_MASK


func pick_index(count: int) -> int:
	if count <= 1:
		return 0
	var bound := count & _U32_MASK
	var limit := int(_U32_MASK / float(bound)) * bound
	while true:
		var value := next_u32()
		if value < limit:
			return value % bound
	return 0


func coin_flip() -> bool:
	return (next_u32() & 1) != 0


func shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := pick_index(index + 1)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary


func _twist() -> void:
	for index in range(_N):
		var value: int = (_state[index] & _UPPER_MASK) | (_state[(index + 1) % _N] & _LOWER_MASK)
		var next_value: int = _state[(index + _M) % _N] ^ (value >> 1)
		if (value & 1) != 0:
			next_value ^= _MATRIX_A
		_state[index] = next_value & _U32_MASK
	_index = 0
