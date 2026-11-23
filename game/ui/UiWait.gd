class_name UiWait
extends RefCounted
## A button that is off only because something is being waited for (a restart, a purchase, a match
## start) is not a refusal: a tap on it gives no sound. `hold` sets the interface sounds' `no_click`
## meta while it waits and puts it back exactly as it was after (a `no_click` the button had
## before stays). Buttons that are unavailable for good (a locked map, an unaffordable card) are
## not held: a tap on them plays the refuse cue.

const NO_CLICK: StringName = &"no_click"
const PRIOR: StringName = &"wait_prior_no_click"


static func hold(button: BaseButton, waiting: bool) -> void:
	if waiting:
		if not button.has_meta(PRIOR):
			button.set_meta(PRIOR, button.get_meta(NO_CLICK, false))
		button.set_meta(NO_CLICK, true)
	elif button.has_meta(PRIOR):
		if not bool(button.get_meta(PRIOR)):
			button.remove_meta(NO_CLICK)
		button.remove_meta(PRIOR)
