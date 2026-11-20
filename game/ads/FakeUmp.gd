class_name FakeUmp
extends ConsentBackend
## The fake consent backend: editor, tests, web preview and every build without the real UMP
## plugin (ADR 0039 section 3). It models UMP's status (see ConsentBackend's notes) and is
## scriptable: consent required or not, accepted or declined, a decline that limits ads or blocks
## them, an info update that never answers, a form that fails or never loads or never closes, a
## show that fails, and offline. With `auto_close` a form closes at once with the scripted answer;
## without it a placeholder is drawn on `host` and its buttons decide (or `dismiss` is called).
## Reaches no network and no plugin.

## Scripts for tests.
var consent_required: bool = false
## What a form that closes by itself answers; a placeholder's Accept and Decline override it.
var obtained: bool = true
## UMP's behaviour: a decline still ends OBTAINED, so ads (limited) are served. False blocks them.
var decline_limits_ads: bool = true
var info_never_answers: bool = false
var form_load_fails: bool = false
var form_never_loads: bool = false
var form_never_closes: bool = false
var show_fails: bool = false
## A show that never opens: no form, no dismissal, until `show_held_form` (a late show).
var show_never_shows: bool = false
var offline: bool = false
## Fake-only: forms close at once. Set by ConsentFlow from `fake_auto_close`.
var auto_close: bool = true
## Fake-only: draw the placeholder on `host`.
var draw_placeholders: bool = false
var host: Node = null

var info_updates: int = 0
## The debug geography the last update was asked for (it makes the user an EEA user).
var last_debug_eea: bool = false
var forms_shown: int = 0
var app_pauses: int = 0

var _info: Step = Step.PENDING
var _status: Status = Status.UNKNOWN
var _eea_user: bool = false
var _is_open: bool = false
var _node: FakeConsentForm = null
var _held_with_close: bool = false
var _is_held: bool = false
var _is_late: bool = false


func update_info(debug_eea: bool) -> void:
	info_updates += 1
	last_debug_eea = debug_eea
	if offline:
		_info = Step.FAILED
	elif info_never_answers:
		_info = Step.PENDING
	else:
		answer_info()


## Test hook: a pending info update answers now.
func answer_info() -> void:
	_info = Step.DONE
	_eea_user = consent_required or last_debug_eea
	if not _eea_user:
		_status = Status.NOT_REQUIRED
	elif _status != Status.OBTAINED:
		_status = Status.REQUIRED


func info_state() -> Step:
	return _info


func consent_status() -> Status:
	return _status


func form_state() -> Step:
	if offline or form_load_fails:
		return Step.FAILED
	return Step.PENDING if form_never_loads else Step.DONE


func show_form() -> void:
	_show(false)


func can_request_ads() -> bool:
	return _status == Status.NOT_REQUIRED or _status == Status.OBTAINED


## Stays true for a returning EEA user even when no form showed this launch.
func is_privacy_options_required() -> bool:
	return _info == Step.DONE and _eea_user


func show_privacy_options() -> void:
	_show(true)


## A button press (or a test): the open form is dismissed with `accepted` as the answer.
func dismiss(accepted: bool) -> void:
	if not _is_open:
		return
	_is_open = false
	_status = Status.OBTAINED if accepted or decline_limits_ads else Status.REQUIRED
	_end()


## A Close press on the privacy options form: dismissed, nothing changed.
func close_unchanged() -> void:
	if _is_open:
		_is_open = false
		_end()


func notify_app_paused() -> void:
	app_pauses += 1


## An SDK cannot recall a started show: the cut run's show may still open (`show_held_form`).
func cancel_pending_show() -> void:
	if _is_held:
		_is_held = false
		_is_late = true


## Test hook: a show held by `show_never_shows` opens now (it came late).
func show_held_form() -> void:
	if _is_held or _is_late:
		_is_held = false
		_is_late = false
		_open(_held_with_close)


func _show(with_close: bool) -> void:
	if _is_open or _is_held:
		form_dismissed.emit()  # Refused: nothing new opens, and no waiting gate hangs.
		return
	if show_never_shows:
		_is_held = true
		_held_with_close = with_close
		return
	_open(with_close)


func _open(with_close: bool) -> void:
	forms_shown += 1
	if show_fails:
		form_dismissed.emit()
		return
	_is_open = true
	form_shown.emit()
	if form_never_closes:
		return
	if auto_close:
		dismiss(obtained)
	elif draw_placeholders and is_instance_valid(host) and host.is_inside_tree():
		_node = FakeConsentForm.build(
			with_close, dismiss.bind(true), dismiss.bind(false), close_unchanged
		)
		host.add_child(_node)
	else:
		# Nothing to draw on (no host in the tree): answer as scripted, like FakeBilling's sheet.
		dismiss(obtained)


func _end() -> void:
	if is_instance_valid(_node):
		_node.queue_free()
	_node = null
	form_dismissed.emit()
