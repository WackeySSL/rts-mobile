class_name ConsentBackend
extends RefCounted
## The seam between AdService and a consent SDK (ADR 0039 section 3). AdService and ConsentGate own
## the flow, the timeouts and the "can request ads" answer; a backend only asks and reports.
## Methods never block: the info update and the form load answer through `info_state` and
## `form_state`, and a shown form ends with `form_dismissed`. This base is inert: its update
## fails, so ads stay unrequested. `FakeUmp` is the scriptable fake; the real UMP backend is P405.

## The form (consent or privacy options) was dismissed.
signal form_dismissed

enum Step { PENDING, DONE, FAILED }


## Starts the consent info update. `debug_eea` asks for the EEA debug geography (test devices).
func update_info(_debug_eea: bool) -> void:
	pass


func info_state() -> Step:
	return Step.FAILED


## After a finished update: whether UMP says a consent form must be shown.
func is_form_required() -> bool:
	return false


func load_form() -> void:
	pass


func form_state() -> Step:
	return Step.FAILED


## Shows the loaded consent form; `form_dismissed` follows when it closes.
func show_form() -> void:
	pass


## UMP's answer after the update and any form: may ads be requested at all.
func can_request_ads() -> bool:
	return false


func is_privacy_options_required() -> bool:
	return false


## Shows the privacy options form; `form_dismissed` follows when it closes.
func show_privacy_options() -> void:
	pass
