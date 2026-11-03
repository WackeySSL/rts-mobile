class_name LifeClock
extends RefCounted
## The clock and the variation of the unit-life layer (ADR 0027 section 2). Life runs on match time,
## `(tick + alpha) x 1000 / Sim.TICK_RATE` ms from the published snapshot and the runner's alpha,
## so it stops with the match (a pause, the app in the background), is the same at the same tick on
## every device and frame rate, and a test sets a tick and an alpha instead of faking a clock. The
## frame clock (`Time`) is not used here or in any life file (test_life_purity.gd).
## An event of tick `t` is born at `tick_ms(t)`; its age is the clock minus that, clamped at 0
## (`age_ms`): in WORKER mode the runner restarts alpha at 0 in the first frame after a pause, so
## the clock can step back by up to one tick, and nothing may play backwards or go negative.
## Variation comes from `mix`, an integer hash of the entity id: stateless, the same in every run,
## and no `hash()`, `randi`, `randf` or `RandomNumberGenerator` anywhere in life code.

const MASK32: int = 0xFFFFFFFF
const MASK31: int = 0x7FFFFFFF
## Odd constants of the mix: the first two spread an id and a salt over 32 bits, the other three are
## the rounds of the finaliser (a multiply-xorshift mix; the values are in test_life_clock.gd).
const MUL_ID: int = 0x9E3779B1
const MUL_SALT: int = 0x85EBCA6B
const ADD: int = 0x27D4EB2F
const ROUND_A: int = 0x2C1B3C6D
const ROUND_B: int = 0x297A2D39


## Match time in ms at `alpha` (0 to 1) into the tick after the one `snap` is. A view float.
static func ms(snap: MatchSnapshot, alpha: float) -> float:
	return (float(snap.tick) + alpha) * 1000.0 / float(Sim.TICK_RATE)


## The match time at which tick `tick` happens: the birth of an event of that tick.
static func tick_ms(tick: int) -> float:
	return float(tick) * 1000.0 / float(Sim.TICK_RATE)


## How old a thing born at `born_ms` is at `now_ms`, never negative.
static func age_ms(now_ms: float, born_ms: float) -> float:
	return maxf(now_ms - born_ms, 0.0)


## A 31-bit integer mix of an entity id and a salt (a cycle number, a kind): the same for the same
## pair in every run and on every device, spread evenly over 0 to 2^31 - 1. Integer only, so no
## platform can differ. The inputs are masked to 31 bits and every product to 32 bits, so nothing
## overflows.
static func mix(id: int, salt: int) -> int:
	var by_id: int = ((id & MASK31) * MUL_ID) & MASK32
	var by_salt: int = ((salt & MASK31) * MUL_SALT) & MASK32
	var x: int = (by_id + by_salt + ADD) & MASK32
	x ^= x >> 15
	x = (x * ROUND_A) & MASK32
	x ^= x >> 12
	x = (x * ROUND_B) & MASK32
	x ^= x >> 15
	return x & MASK31


## `mix(id, salt)` as one of `count` slots, 0 to count - 1: the phase or the window of a periodic
## effect. `count` below 1 gives 0.
static func pick(id: int, salt: int, count: int) -> int:
	return mix(id, salt) % count if count > 0 else 0
