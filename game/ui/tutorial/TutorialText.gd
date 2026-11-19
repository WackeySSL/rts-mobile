class_name TutorialText
extends RefCounted
## The English table of the tutorial (ADR 0044 section 3, plan row P543; the pattern of
## `MainMenuText`): the title and the prompt of every beat, by the keys of
## `data/tutorial/*.tres`. The words are for a first-time player: no data name, no file path.

const ENGLISH: Dictionary[StringName, String] = {
	&"tutorial.basics.title": "Basics",
	&"tutorial.basics.welcome":
	(
		"Welcome, commander. You lead the Derrick League. Your credits and "
		+ "power are up here, and the menu button is at the start. Tap Next."
	),
	&"tutorial.basics.pan": "Drag one finger across the map to move the view.",
	&"tutorial.basics.zoom":
	"Pinch your fingers apart to zoom in. The view settles on one of three " + "zoom levels.",
	&"tutorial.basics.radar":
	(
		"Tap the round radar. The whole map unfolds, and a tap or drag on it "
		+ "jumps the view there."
	),
	&"tutorial.basics.fog":
	(
		"Black ground is unexplored and dim ground is out of sight. You only "
		+ "see enemies where your units see now. Tap Next."
	),
	&"tutorial.basics.box":
	"Press and hold on the ground, then drag a box round your squads to " + "select them.",
	&"tutorial.basics.clear":
	(
		"Tap CLEAR to drop the selection. A box on empty ground, or a tap on "
		+ "bare ground, does it too. Tap Next."
	),
	&"tutorial.basics.double": "Double-tap one squad to select every squad of that kind on screen.",
	&"tutorial.basics.move":
	(
		"With your squads selected, tap the ground to send them there. STOP "
		+ "halts them where they stand."
	),
	&"tutorial.basics.across":
	(
		"Now send them across the ridge. Rock and water block everyone, so they "
		+ "walk round. You can also hold a finger on the radar map to send them "
		+ "there."
	),
	&"tutorial.basics.drawer": "Tap BUILD to open the build drawer. The game goes on behind it.",
	&"tutorial.basics.low-power":
	(
		"The power bar is red: your Oil Works uses more power than you make. "
		+ "Tap Next, then build a power plant."
	),
	&"tutorial.basics.power":
	"Tap the Power Plant card to queue it. When it says Ready, tap it to " + "place it.",
	&"tutorial.basics.placed":
	(
		"Drag the ghost to a free spot, then tap the check mark. BUILD still "
		+ "works while you place."
	),
	&"tutorial.basics.close":
	(
		"Touch the map and the drawer slides away. Hold a card to cancel the "
		+ "last one you queued. Tap Next."
	),
	&"tutorial.basics.field":
	"Your tanker brings in credits. Select it and tap the oil field to send " + "it to work.",
	&"tutorial.basics.barracks":
	"Build a Barracks the same way: BUILD, tap its card, wait for Ready, " + "place it.",
	&"tutorial.basics.train":
	"Open the Infantry tab and tap Rifle Squad twice. They appear beside " + "the Barracks.",
	&"tutorial.basics.rally":
	"Select the Barracks and tap the ground: new squads gather at that " + "flag. Tap Next.",
	&"tutorial.basics.groups":
	(
		"Select squads and tap the plus to save them as a group. Hold a group's "
		+ "number to overwrite it with your selection."
	),
	&"tutorial.basics.incoming":
	(
		"Enemy squads are coming. When you are hit out of view, a red message "
		+ "tells you: tap it to jump there, and watch the red wedge on the radar. "
		+ "Tap Next."
	),
	&"tutorial.basics.attack":
	(
		"Select your squads and tap an enemy to attack it. They keep fighting "
		+ "the next one until none is left."
	),
	&"tutorial.basics.pause":
	(
		"Tap the menu button to pause. Restart, Surrender and Exit ask first. "
		+ "Leaving the app saves the match: CONTINUE on the main menu picks it "
		+ "up."
	),
	&"tutorial.basics.win":
	(
		"To win, destroy the enemy Headquarters and every building that trains "
		+ "units. Skirmish lets you pick Easy, Normal or Hard. Tap Next."
	),
	&"tutorial.strikes.title": "Strikes and the satellite",
	&"tutorial.strikes.own":
	(
		"Your Deep Bore is charged. The round button above BUILD is its strike "
		+ "button: the ring fills while it charges. Tap Next."
	),
	&"tutorial.strikes.aim":
	(
		"Tap the ready button, then tap the map where the enemy squads stand. A "
		+ "ring shows how far the strike reaches; tap again to move it."
	),
	&"tutorial.strikes.fire":
	(
		"Tap the check mark to fire. Everyone sees a red ring and a warning "
		+ "triangle on the target while it closes."
	),
	&"tutorial.strikes.impact":
	(
		"When the ring closes the ground splits: every ground unit and building "
		+ "inside is hit, yours too, and a crater stays. Tap Next."
	),
	&"tutorial.strikes.off":
	(
		"A building with an amber bolt over it is switched off, yours or the "
		+ "enemy's. A Dusk Array does that to what it hits. Tap Next."
	),
	&"tutorial.strikes.sat":
	(
		"Your Skyrig is a space centre. Its one charge fills from the start; "
		+ "when it is ready the strike button serves it. Tap Next."
	),
	&"tutorial.strikes.sat-fire":
	"The sweep needs no target. Tap the ready button, then the lit check " + "mark.",
	&"tutorial.strikes.sat-on":
	(
		"The whole map is yours to see until the Skyrig is destroyed or sold. "
		+ "Enemy buildings stay dimly on the map. Tap Next."
	),
	&"tutorial.strikes.sat-pause":
	(
		"If the Skyrig is switched off or you run low on power, the sweep "
		+ "pauses and comes back by itself. Tap Next."
	),
	&"tutorial.strikes.enemy-sweep":
	(
		"When an enemy fires its sweep you get one warning line and a satellite "
		+ "badge on your screen. Tap Next."
	),
	&"tutorial.air.title": "Aircraft and carriers",
	&"tutorial.air.airfield":
	(
		"Your airfield has four landing pads, one aircraft per pad. A new one "
		+ "needs a radar and costs credits: BUILD, Structures. Tap Next."
	),
	&"tutorial.air.fighter": "Open the Flight tab and tap Fighter. It appears over a free pad.",
	&"tutorial.air.tap-air": "Tap the aircraft itself, not its shadow, to select it.",
	&"tutorial.air.unreachable":
	(
		"A fighter hits aircraft only. Tap an enemy tank and nothing is "
		+ "ordered: the marker shakes. Tap Next."
	),
	&"tutorial.air.bomber":
	(
		"A bomber drops its bombs, flies home to reload and waits on its pad. "
		+ "Tap an enemy to send it out again. Tap Next."
	),
	&"tutorial.air.home":
	(
		"With aircraft selected, tap HOME and they fly back to their pads to "
		+ "reload and be repaired. Tap Next."
	),
	&"tutorial.air.raid":
	(
		"An enemy aircraft is over your base. Your Burst Stack fires on its "
		+ "own, at aircraft only. Tap Next."
	),
	&"tutorial.air.wagon":
	"Open the Vehicles tab and tap Bunk Wagon. A carrier has no gun: it " + "carries squads.",
	&"tutorial.air.board":
	"Select squads, tap BOARD, tap the carrier, then the check mark. Tap " + "Next.",
	&"tutorial.air.unload":
	"Select the loaded carrier, tap UNLOAD, tap the ground, then the check " + "mark. Tap Next.",
	&"tutorial.support.title": "Repair, sale and mines",
	&"tutorial.support.select-plant": "Tap one of your power plants to select it.",
	&"tutorial.support.mend": "MEND repairs a building for a share of its price. Tap Next.",
	&"tutorial.support.sell":
	"SELL needs two taps: the first arms it and shows the refund, the " + "second sells. Tap Next.",
	&"tutorial.support.sell-last":
	(
		"With your Headquarters gone, selling your last barracks or factory "
		+ "asks first, because it loses the match. Tap Next."
	),
	&"tutorial.support.poke": "Enemy squads are shooting at your tanks. Tap Next.",
	&"tutorial.support.tanks": "Double-tap a tank to select both.",
	&"tutorial.support.repair":
	(
		"Hurt vehicles drive to your Weld Shed when you tap REPAIR, and are "
		+ "fixed there for credits. Tap Next."
	),
	&"tutorial.support.medics":
	(
		"Open the Infantry tab and tap Patchers. A medic squad mends hurt "
		+ "squads near it for free, but carries no weapon."
	),
	&"tutorial.support.shot-truck":
	"Open the Vehicles tab and tap Shot Truck. It lays mines and finds " + "hidden ones.",
	&"tutorial.support.mine":
	(
		"Select the truck, tap MINE, tap the ground, then the check mark. The "
		+ "button counts your mines. Tap Next."
	),
	&"tutorial.support.hidden":
	(
		"Enemy mines are hidden: no mark, nothing on the radar. A ground unit "
		+ "that walks over one sets it off. Your truck finds them. Tap Next."
	),
}

static var _registered: bool = false


## Adds the English table to the TranslationServer; a second call does nothing.
static func register() -> void:
	if _registered:
		return
	_registered = true
	var table: Translation = Translation.new()
	table.locale = "en"
	for key: StringName in ENGLISH:
		table.add_message(key, ENGLISH[key])
	TranslationServer.add_translation(table)
