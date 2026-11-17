class_name MenuRoutes
extends RefCounted
## Where the main menu's buttons lead (plan P524). A row that builds a screen registers a factory
## under its route; the main menu reads this table every time it shows, so a later row plugs in
## without an edit of the menu. A route nobody registered leaves its button present but disabled.

## A route was registered or the table was cleared: a shown menu looks again.
signal changed

const SKIRMISH: StringName = &"skirmish"  # P525 (map select)
const TUTORIAL: StringName = &"tutorial"  # P544 (TutorialScreen)
const HOW_TO_PLAY: StringName = &"how_to_play"  # P527
const SETTINGS: StringName = &"settings"  # P526
const CONTINUE: StringName = &"continue"  # P515 (resume)

## The table the app uses; tests make their own with `MenuRoutes.new()`.
static var shared: MenuRoutes = MenuRoutes.new()

var _factories: Dictionary[StringName, Callable] = {}


## `factory` takes no argument and returns a new `MenuScreen`.
func register(route: StringName, factory: Callable) -> void:
	_factories[route] = factory
	changed.emit()


## Empties the table (tests, so routes do not leak between suites).
func clear() -> void:
	_factories.clear()
	changed.emit()


func has(route: StringName) -> bool:
	return _factories.has(route) and _factories[route].is_valid()


## A new screen for `route`, or null when none is registered.
func make(route: StringName) -> MenuScreen:
	return (_factories[route].call() as MenuScreen) if has(route) else null
