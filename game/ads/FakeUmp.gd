class_name FakeUmp
extends ConsentBackend
## The fake consent backend: editor, tests, web preview and every build without the real UMP
## plugin (ADR 0039 section 3). Scriptable: consent required or not, obtained or denied, an info
## update that never answers, a form that never loads or never closes, and offline. With
## `auto_close` a form closes at once with the scripted answer; without it a placeholder is drawn on
## `host` and its buttons decide (or `dismiss` is called). Reaches no network and no plugin.

## Scripts for tests.
var consent_required: bool = false
## What a form that closes by itself answers; a placeholder's Accept and Decline override it.
var obtained: bool = true
var info_never_answers: bool = false
var form_never_loads: bool = false
var form_never_closes: bool = false
var offline: bool = false
## Fake-only: forms close at once. Set by AdService from `fake_auto_close`.
var auto_close: bool = true
## Fake-only: draw the placeholder on `host`.
var draw_placeholders: bool = false
var host: Node = null

var info_updates: int = 0
## The debug geography the last update was asked for.
var last_debug_eea: bool = false
var forms_shown: int = 0

var _info: Step = Step.PENDING
var _granted: bool = false
var _is_open: bool = false
var _node: FakeConsentForm = null


func update_info(debug_eea: bool) -> void:
	info_updates += 1
	last_debug_eea = debug_eea
	if offline:
		_info = Step.FAILED
	else:
		_info = Step.PENDING if info_never_answers else Step.DONE


func info_state() -> Step:
	return _info


func is_form_required() -> bool:
	return _info == Step.DONE and (consent_required or last_debug_eea)


func form_state() -> Step:
	if offline:
		return Step.FAILED
	return Step.PENDING if form_never_loads else Step.DONE


func show_form() -> void:
	_show(false)


func can_request_ads() -> bool:
	return _info == Step.DONE and (not is_form_required() or _granted)


func is_privacy_options_required() -> bool:
	return is_form_required()


func show_privacy_options() -> void:
	_show(true)


## A button press (or a test): the open form is dismissed with `accepted` as the answer.
func dismiss(accepted: bool) -> void:
	if not _is_open:
		return
	_is_open = false
	_granted = accepted
	_clear()
	form_dismissed.emit()


## A Close press on the privacy options form: dismissed, nothing changed.
func close_unchanged() -> void:
	dismiss(_granted)


func _show(with_close: bool) -> void:
	forms_shown += 1
	_is_open = true
	if form_never_closes:
		return
	if auto_close:
		dismiss(obtained)
	elif draw_placeholders and host != null and is_instance_valid(host) and host.is_inside_tree():
		_node = FakeConsentForm.build(
			with_close, dismiss.bind(true), dismiss.bind(false), close_unchanged
		)
		host.add_child(_node)


func _clear() -> void:
	if is_instance_valid(_node):
		_node.queue_free()
	_node = null
