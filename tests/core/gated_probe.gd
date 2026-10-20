extends SimProbe
## A SimProbe for the worker tests (plan P38w), installed as a runner's `probe`, so it gets every
## begin() and mark() of Sim.step on the thread that runs the job. begin() counts the jobs under a
## Mutex and flags a job that begins before the one before it ended (its mark of REMOVE or a later
## phase). It can delay every job by a set number of ms, and hold one chosen job in begin() on the
## probe's own Semaphore until the test calls release(). The hold is a try_wait() loop with
## OS.delay_msec(1) steps that gives up after CAP_MSEC and lets the job end, because the runner's
## join (wait_to_finish()) has no timeout and a worker left blocked would hang CI. CAP_MSEC is half
## the runner's wait cap, so a runner freed over a held job still gets its job back before the
## join's wait gives up with an error. release() is idempotent. Not a test suite. It has its own
## file because an inner class may not extend a script, and it never names itself
## (tests/project/test_inner_classes_extend_engine_classes.gd).

@warning_ignore("integer_division") const CAP_MSEC: int = MatchRunner.WAIT_CAP_MSEC / 2

## Jobs begun so far.
var begin_count: int:
	get:
		_mutex.lock()
		var count: int = _begins
		_mutex.unlock()
		return count
## True once a job began before the one before it ended.
var overlapped: bool:
	get:
		_mutex.lock()
		var seen: bool = _overlapped
		_mutex.unlock()
		return seen
## True once a hold reached the cap and let its job go.
var gave_up: bool:
	get:
		_mutex.lock()
		var capped: bool = _gave_up
		_mutex.unlock()
		return capped

var _mutex: Mutex = Mutex.new()
var _gate: Semaphore = Semaphore.new()
var _blocked: Semaphore = Semaphore.new()
var _begins: int = 0
var _inside: bool = false
var _overlapped: bool = false
var _gave_up: bool = false
var _hold_at: int = 0
var _delay_msec: int = 0
var _released: bool = false


## Holds the job whose begin() is the `begin_number`-th one (1 for the first job) until release().
func hold(begin_number: int) -> void:
	_mutex.lock()
	_hold_at = begin_number
	_mutex.unlock()


## Makes every begin() from now on wait `msec` ms (0: none).
func delay(msec: int) -> void:
	_mutex.lock()
	_delay_msec = msec
	_mutex.unlock()


## Lets the held job go, now or when it reaches the hold. A second call does nothing.
func release() -> void:
	_mutex.lock()
	var first: bool = not _released
	_released = true
	_mutex.unlock()
	if first:
		_gate.post()


## Waits on the calling thread until the held job is blocked in begin(), up to `timeout_msec`;
## false at the cap.
func wait_blocked(timeout_msec: int = CAP_MSEC) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not _blocked.try_wait():
		if Time.get_ticks_msec() >= until:
			return false
		OS.delay_msec(1)
	return true


func begin() -> void:
	_mutex.lock()
	_begins += 1
	_overlapped = _overlapped or _inside
	_inside = true
	var held: bool = _begins == _hold_at
	var wait_msec: int = _delay_msec
	_mutex.unlock()
	if wait_msec > 0:
		OS.delay_msec(wait_msec)
	if held:
		_blocked.post()
		_block()


func mark(phase: int) -> void:
	if phase >= SimProbe.Phase.REMOVE:
		_mutex.lock()
		_inside = false
		_mutex.unlock()


## The capped hold: until release(), or CAP_MSEC.
func _block() -> void:
	var until: int = Time.get_ticks_msec() + CAP_MSEC
	while not _gate.try_wait():
		if Time.get_ticks_msec() >= until:
			_mutex.lock()
			_gave_up = true
			_mutex.unlock()
			return
		OS.delay_msec(1)
