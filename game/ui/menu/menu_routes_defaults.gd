class_name MenuRoutesDefaults
extends RefCounted
## The routes the app registers at the start (plan P524b). A later row adds one line to
## `register`. The statics live here, not on a MenuScreen subclass (a static on a screen leaked at
## exit, P527).
## Rule: register `XScript.new` (the screen's script, preloaded below), never a lambda (static
## teardown order); `MenuRoutes.register` refuses a lambda with a warning.
## Rule: never write `GlobalClass.new` without the call parentheses. The web release template's
## analyzer does not find a `new` member on a global class used as a value ("Cannot find member
## "new" in base ...", P451): the script then fails to compile in the export and the menu is dead.
## `X.new()` (a call) and `ScriptConst.new` (a value on a preloaded script) both work there.

const HowToPlayScript: GDScript = preload("res://game/ui/menu/HowToPlayScreen.gd")
const MapSelectScript: GDScript = preload("res://game/ui/menu/MapSelect.gd")
const TutorialScript: GDScript = preload("res://game/ui/menu/TutorialScreen.gd")
const SettingsScript: GDScript = preload("res://game/ui/menu/SettingsScreen.gd")
const LicencesScript: GDScript = preload("res://game/ui/menu/LicencesScreen.gd")
const RestoreScript: GDScript = preload("res://game/ui/menu/RestoreScreen.gd")


## Registers every route that has a screen today into `routes`.
static func register(routes: MenuRoutes) -> void:
	routes.register(MenuRoutes.HOW_TO_PLAY, HowToPlayScript.new)
	routes.register(MenuRoutes.SKIRMISH, MapSelectScript.new)
	routes.register(MenuRoutes.TUTORIAL, TutorialScript.new)
	routes.register(MenuRoutes.SETTINGS, SettingsScript.new)
	routes.register(MenuRoutes.LICENCES, LicencesScript.new)
	routes.register(MenuRoutes.CONTINUE, RestoreScript.new)
