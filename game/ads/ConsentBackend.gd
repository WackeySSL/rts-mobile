class_name ConsentBackend
extends RefCounted
## The seam between AdService and a consent SDK (ADR 0039 section 3). ConsentFlow and ConsentGate
## own the flow, the timeouts and the "can request ads" answer; a backend only asks and reports.
## Methods never block: the info update and the form load answer through `info_state` and
## `form_state`, and a shown form ends with `form_dismissed`. This base is inert: its update
## fails, so ads stay unrequested. `FakeUmp` is the scriptable fake; the real UMP backend is P405.
##
## Contract: `form_dismissed` fires on EVERY terminal outcome of `show_form` and
## `show_privacy_options`, errors and "failed to show" included, so the awaiting flow never hangs.
##
## UMP facts the fake models, all to confirm in P405:
## - The status is UNKNOWN until the update, then REQUIRED, NOT_REQUIRED or (after a form) OBTAINED.
## - The form shows only while the status is REQUIRED.
## - A decline still ends in OBTAINED: ads may be requested and limited (non-personalised) ads are
##   served; only a script (`FakeUmp.decline_limits_ads`) models an SDK that blocks instead.
## - The privacy options requirement is separate: it stays REQUIRED for a returning EEA or UK user
##   even when no form shows this launch.
## - Offline: the plan returns false. UMP's pattern would use the stored consent instead; to
##   confirm in P405 (ADR note by the lead).
## - The debug geography's test-device hash comes from a git-ignored local file
##   (`AdIds.test_device_hash`, read by `UmpPluginBackend`).

## The form (consent or privacy options) was dismissed.
signal form_dismissed
## A form is on screen (or, for a backend that cannot observe it, was handed to the SDK). Fires
## before `form_dismissed`. A run that waits on `show_privacy_options` gives up at its deadline
## only while this has not fired; after it the run waits for the dismissal with no timeout.
signal form_shown

enum Step { PENDING, DONE, FAILED }
enum Status { UNKNOWN, REQUIRED, NOT_REQUIRED, OBTAINED }


## Starts the consent info update. `debug_eea` asks for the EEA debug geography (test devices).
func update_info(_debug_eea: bool) -> void:
	pass


func info_state() -> Step:
	return Step.FAILED


func consent_status() -> Status:
	return Status.UNKNOWN


## After a finished update: whether a consent form must be shown (status REQUIRED).
func is_form_required() -> bool:
	return consent_status() == Status.REQUIRED


func load_form() -> void:
	pass


func form_state() -> Step:
	return Step.FAILED


## Shows the loaded consent form; `form_dismissed` follows when it closes or fails.
func show_form() -> void:
	form_dismissed.emit()


## UMP's answer after the update and any form: may ads be requested at all.
func can_request_ads() -> bool:
	return false


## Separate from the status: whether Settings shows "Privacy options".
func is_privacy_options_required() -> bool:
	return false


## Shows the privacy options form; `form_shown` follows when it is up, `form_dismissed` when it
## closes or fails (a failure may come without `form_shown`).
func show_privacy_options() -> void:
	form_dismissed.emit()
