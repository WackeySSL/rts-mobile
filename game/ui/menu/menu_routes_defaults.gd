class_name MenuRoutesDefaults
extends RefCounted
## The routes the app registers at the start (plan P524b). A later row (P525 skirmish, P544
## tutorial, P515 continue) adds one line to `register`. The statics live here, not
## on a MenuScreen subclass (a static on a screen leaked at exit, P527).
## Rule: register `X.new`, never a lambda (static teardown order); `MenuRoutes.register` refuses
## a lambda with a warning.


## Registers every route that has a screen today into `routes`.
static func register(routes: MenuRoutes) -> void:
	routes.register(MenuRoutes.HOW_TO_PLAY, HowToPlayScreen.new)
	routes.register(MenuRoutes.SKIRMISH, MapSelect.new)
	routes.register(MenuRoutes.SETTINGS, SettingsScreen.new)
	routes.register(MenuRoutes.LICENCES, LicencesScreen.new)
