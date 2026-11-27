extends RefCounted
## The mid-play fixtures of the chain sweep (plan rows P591b, P593b-2). Not a test suite. Seven
## beats of the lessons aim their ring at a control that exists only in the middle of play: the
## check mark of a placement ghost, the check mark of a strike aim, Home and Board, Repair, Mine and
## Mend. Three more aim at a unit the lesson makes or meets (the wave in view for `attack`, the
## fighter on its pad for `tap-air`, the truck built for `select-truck`), and `home` and `mine`
## start on a unit step with nothing selected. Each is brought up here the way a player brings it
## up, never by showing the control: units a lesson would have trained stand in the scenario's
## spawn list (`scenario_for`), damage is written to the World, and the placement and the strike
## aim begin through the real card tap and the real button and ground tap of the controller
## (`prepare`).

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const PLAYER: int = 1
const PLACE_TICKS: int = 160  ## A power plant takes 150 ticks to build.
const PLACE_ROUNDS: int = 12
## The units a beat's fixture adds to its lesson's scenario: [owner, unit, tile x, tile y].
const SPAWNS: Dictionary[String, Array] = {
	"air/board": [[1, "fossil_transport", 12, 10]],
	"support/mine": [[1, "fossil_shot_truck", 12, 10]],
	"support/select-truck": [[1, "fossil_shot_truck", 12, 10]],
	"basics/attack": [[2, "renew_rifle", 13, 8], [2, "renew_rifle", 14, 9]],
}
## The beats that have a fixture ("lesson/beat").
const BEATS: Array[String] = [
	"air/board",
	"air/home",
	"air/tap-air",
	"basics/attack",
	"basics/placed",
	"strikes/fire",
	"support/mend",
	"support/mine",
	"support/repair",
	"support/select-truck",
]

var failure: String = ""  ## What the fixture could not bring up, empty when it did.

var _suite: GdUnitTestSuite
var _main: Node
var _runner: MatchRunner
var _selection: SelectionModel
var _sidebar: BuildSidebar


func _init(
	suite: GdUnitTestSuite, main: Node, selection: SelectionModel, sidebar: BuildSidebar
) -> void:
	_suite = suite
	_main = main
	_runner = main.get_node("MatchRunner")
	_selection = selection
	_sidebar = sidebar


## Whether `pair` ("lesson/beat") has a fixture.
static func has(pair: String) -> bool:
	return BEATS.has(pair)


## `scenario` with the units of `pair`'s fixture added (a copy; the lesson's own stays as it is).
static func scenario_for(pair: String, scenario: ScenarioDef) -> ScenarioDef:
	var made: ScenarioDef = scenario.duplicate() as ScenarioDef
	var spawns: Array[SpawnDef] = []
	spawns.assign(scenario.spawns)
	for entry: Array in SPAWNS.get(pair, []):
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	made.spawns = spawns
	return made


## Brings up the state `pair`'s control needs and leaves the player's selection as the beat expects.
func prepare(pair: String) -> void:
	match pair:
		"air/home", "air/tap-air":
			await _train(&"fossil_fighter")
			_selection.clear()  # The ring starts on the fighter, as for a player who has not tapped it.
		"basics/attack", "support/select-truck", "support/mine":
			_selection.clear()  # The units are in the scenario; nothing is selected yet.
		"air/board":
			_select_type(&"rifle_squad")
		"support/repair":
			_select_hurt(&"light_tank")
		"support/mend":
			_select_hurt(&"power_plant")
		"basics/placed":
			await _place(&"power_plant")
		"strikes/fire":
			await _aim()
		_:
			failure = "no fixture for %s" % pair
	for _frame: int in 3:
		await _suite.await_idle_frame()


func _select_type(type_id: StringName) -> void:
	var ids: PackedInt32Array = _ids(type_id)
	if ids.is_empty():
		failure = "no own %s to select" % type_id
		return
	_selection.set_ids(ids)


## Halves the health of the first own `type_id` (the World's own array, as a fight leaves it), one
## tick to publish it, and selects it.
func _select_hurt(type_id: StringName) -> void:
	var ids: PackedInt32Array = _ids(type_id)
	if ids.is_empty():
		failure = "no own %s to hurt" % type_id
		return
	var row: int = _runner.snapshot.index_of(ids[0])
	_runner.world.hp[row] = maxi(1, _runner.world.hp[row] / 2)
	_runner.run_ticks(1)
	_selection.set_ids(ids.slice(0, 1))


## The structure's card tapped (it queues, paid at once), the match played until it is built, then
## a tap on its Ready card.
func _place(type_id: StringName) -> void:
	var type: int = _runner.snapshot.type_ids.find(type_id)
	_sidebar.open()
	_sidebar.select_tab(_runner.snapshot.type_tab[type])
	await _suite.await_idle_frame()
	var tile: ItemTile = _sidebar.find_child("Tile_%s" % type_id, true, false) as ItemTile
	if tile == null or tile.state != ItemTile.State.AVAILABLE:
		failure = "the card of %s cannot be queued" % type_id
		return
	tile.chose.emit()
	for _round: int in PLACE_ROUNDS:  # A base with no power builds slowly: play until it is built.
		_runner.run_ticks(PLACE_TICKS)
		_sidebar.refresh()
		await _suite.await_idle_frame()
		if tile.state == ItemTile.State.READY:
			break
	if tile.state != ItemTile.State.READY:
		failure = "the card of %s is not Ready (state %d)" % [type_id, tile.state]
		return
	tile.chose.emit()


## The unit's card tapped (it queues, paid at once) and the match played until it stands: a
## trained aircraft has the airfield it left as its home, which a spawned one has not.
func _train(type_id: StringName) -> void:
	var type: int = _runner.snapshot.type_ids.find(type_id)
	_sidebar.open()
	_sidebar.select_tab(_runner.snapshot.type_tab[type])
	await _suite.await_idle_frame()
	var tile: ItemTile = _sidebar.find_child("Tile_%s" % type_id, true, false) as ItemTile
	if tile == null or tile.state != ItemTile.State.AVAILABLE:
		failure = "the card of %s cannot be queued" % type_id
		return
	tile.chose.emit()
	for _round: int in PLACE_ROUNDS:
		_runner.run_ticks(PLACE_TICKS)
		if not _ids(type_id).is_empty():
			break
	var feed: HudStateFeed = (
		_main.find_children("*", "HudStateFeed", true, false)[0] as HudStateFeed
	)
	feed.state.close(feed.state.current)  # A tap on the map: the drawer folds.
	await _suite.await_idle_frame()


## The strike button, then a tap on the nearest enemy.
func _aim() -> void:
	var button: BaseButton = _hud("StrikeButton") as BaseButton
	if button == null or not button.is_visible_in_tree() or button.disabled:
		failure = "the strike button is not tappable"
		return
	button.button_pressed = true
	await _suite.await_idle_frame()
	var snap: MatchSnapshot = _runner.snapshot
	for row: int in snap.unit_count():
		if snap.owner[row] != PLAYER and snap.owner[row] != 0 and snap.hp[row] > 0:
			_tap_ground(Vector2i(snap.pos_x[row], snap.pos_y[row]))
			return
	failure = "no enemy to aim at"


## A tap through the controller at ground point `ground` (milli-tiles), the camera centred on it.
func _tap_ground(ground: Vector2i) -> void:
	var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
	var at: Vector2 = IsoProjection.ground_to_px(ground.x, ground.y)
	camera.centre_on(at)
	camera.force_update_scroll()
	var tap: GestureEvent = GestureEvent.new()
	tap.kind = GestureEvent.Kind.TAP
	tap.position = camera.world_to_screen(at)
	(_main.get_node("PlayerController") as PlayerController).handle_gesture(tap)


func _hud(node_name: String) -> Node:
	return _main.get_node("Hud").find_child(node_name, true, false)


## The ids of the player's rows of `type_id`.
func _ids(type_id: StringName) -> PackedInt32Array:
	var snap: MatchSnapshot = _runner.snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		if snap.owner[row] == PLAYER and snap.type_ids[snap.type_index[row]] == type_id:
			ids.append(snap.unit_id[row])
	return ids
