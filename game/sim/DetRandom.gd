class_name DetRandom
extends RefCounted
## The match's seeded random stream (ADR 0007 section 7): xoshiro128** on four 32-bit words.
## Every intermediate stays non-negative and below 2^49 (ADR 0007 section 1), so nothing wraps.
## Owned by its holder and passed explicitly, never global; `DetRng` creates the streams.

## The stream of `World` (spawn jitter). AI controllers use STREAM_AI_BASE plus the player id.
const STREAM_SIM: int = 1
const STREAM_AI_BASE: int = 100

const MASK32: int = 0xFFFFFFFF
const SEED_MASK: int = 0x7FFFFFFF
const STREAM_MASK: int = 0xFFFF
const STREAM_STEP: int = 0x632BE5AB
const WORD_STEP: int = 0x9E3779B9
## The lowbias32 multipliers of mix32.
const MIX_1: int = 0x7FEB352D
const MIX_2: int = 0x846CA68B
## The largest n that next_int accepts (2^31).
const MAX_BOUND: int = 0x80000000

## The generator state. A fresh DetRandom is a valid non-zero state; `create` seeds it.
var _s0: int = 1
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0

## A generator for (seed, stream). The seed is masked to 0..2^31-1 and the stream to 0..65535.
## Word i is mix32(seed + stream * STREAM_STEP + i * WORD_STEP, mod 2^32); an all-zero state
## becomes word 0 = 1. The parameter keeps the contract's name, so it shadows `seed()`.
@warning_ignore("shadowed_global_identifier")
static func create(seed: int, stream: int) -> DetRandom:
	var base: int = (seed & SEED_MASK) + (stream & STREAM_MASK) * STREAM_STEP
	var rng: DetRandom = DetRandom.new()
	var words: PackedInt64Array = PackedInt64Array()
	for i: int in range(4):
		words.append(mix32((base + i * WORD_STEP) & MASK32))
	rng.set_state(words)
	return rng


## The low 32 bits of a * b for a and b in 0..2^32-1. The inner parentheses matter: `+` binds
## tighter than `<<`. Public so a test can compare it to the true product.
static func mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK32


## x rotated left by k bits, for x in 0..2^32-1 and k in 0..31.
static func rotl(x: int, k: int) -> int:
	return ((x << k) & MASK32) | (x >> (32 - k))


## lowbias32, an integer mixer for x in 0..2^32-1; it spreads nearby seeds over the whole state.
static func mix32(x: int) -> int:
	x ^= x >> 16
	x = mul32(x, MIX_1)
	x ^= x >> 15
	x = mul32(x, MIX_2)
	return x ^ (x >> 16)


## The next value, 0..2^32-1.
func next_u32() -> int:
	var result: int = mul32(rotl(mul32(_s1, 5), 7), 9)
	var t: int = (_s1 << 9) & MASK32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = rotl(_s3, 11)
	return result


## A value in 0..n-1 for n in 1..2^31, unbiased by rejection (it always draws at least once).
## Any other n returns 0 and draws nothing.
func next_int(n: int) -> int:
	if n < 1 or n > MAX_BOUND:
		return 0
	var limit: int = (1 << 32) - (1 << 32) % n
	var value: int = next_u32()
	while value >= limit:
		value = next_u32()
	return value % n


## A value in lo..hi inclusive, for lo and hi within +-2^61. A span past 2^31 or hi < lo
## returns lo and draws nothing.
func range_int(lo: int, hi: int) -> int:
	if hi < lo:
		return lo
	return lo + next_int(hi - lo + 1)


## Fisher-Yates from the end, in place.
func shuffle(values: PackedInt32Array) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = next_int(i + 1)
		var kept: int = values[i]
		values[i] = values[j]
		values[j] = kept


## One of the values, or 0 when the array is empty (nothing is drawn).
func pick_random(values: PackedInt32Array) -> int:
	if values.is_empty():
		return 0
	return values[next_int(values.size())]


## The four state words, each 0..2^32-1.
func state() -> PackedInt64Array:
	return PackedInt64Array([_s0, _s1, _s2, _s3])


## Sets the state from the first four words, each masked to 32 bits (a missing word is 0).
## An all-zero state becomes word 0 = 1, because xoshiro would stay at zero forever.
func set_state(words: PackedInt64Array) -> void:
	var count: int = words.size()
	_s0 = (words[0] if count > 0 else 0) & MASK32
	_s1 = (words[1] if count > 1 else 0) & MASK32
	_s2 = (words[2] if count > 2 else 0) & MASK32
	_s3 = (words[3] if count > 3 else 0) & MASK32
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1
