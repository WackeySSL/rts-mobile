extends GdUnitTestSuite
## The unit life draws only from match time and an integer hash (plan P136, ADR 0027 section 2): no
## life file, and no life function of a layer, may read `Time` or the OS clock, call `randi`,
## `randf` or `RandomNumberGenerator`, call `hash()` (its output is not part of any contract), or
## make a Particles node. The life files are listed here and each row that adds one appends it; the
## layers have clocks of their own for other things (`UnitLayer.clock` stamps hit times), so only
## their life functions are scanned. A source scan with documented gaps, not a proof: a name built
## from a string is not seen. The patterns have fixtures that they must flag and must spare.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const SourceScan: GDScript = preload("res://tests/view/support/source_scan.gd")
const LIFE_FILES: Array[String] = [
	"res://game/view/LifeClock.gd",
	"res://game/view/LifeSettings.gd",
	"res://game/view/LifeFx.gd",
	"res://game/view/GroundFx.gd",
	"res://game/view/StrikeFx.gd",
	"res://game/view/AirFx.gd",
	"res://game/view/StrikeNet.gd",
	"res://game/view/RigLife.gd",
	"res://game/view/SquadPoses.gd",
	"res://game/view/BuildingAnims.gd",
]
## The life functions of the layers, by file.
const LIFE_FUNCTIONS: Dictionary[String, Array] = {
	"res://game/view/UnitLayer.gd":
	[
		"_on_ticked",
		"_shot_seen",
		"_build_turret_table",
		"_kick_rigs",
		"_apply_kick",
		"_update_rigs",
		"_apply_idle",
		"_show_hull",
	],
	"res://game/view/BuildingLayer.gd":
	["_on_ticked", "_shot_seen", "_kick_heads", "_sweep_heads", "_dress_anim", "_play_anims"],
}
const BANNED: String = (
	r"\bTime\b|\bOS\s*\.\s*get_ticks\w*|\bEngine\s*\.\s*get_(frames|physics)\w*"
	+ r"|\b(randi|randf|randi_range|randf_range|randfn|randomize|rand_from_seed|shuffle|pick_random)\b"
	+ r"|\bRandomNumberGenerator\b|\bhash\s*\(|\b(CPU|GPU)Particles[23]D\b"
)
const FLAGGED: Array[String] = [
	"var now: int = Time.get_ticks_msec()",
	"var t := Time.get_unix_time_from_system()",
	"var t: int = OS.get_ticks_msec()",
	"var f: int = Engine.get_frames_drawn()",
	"var r: int = randi() % 4",
	"var r: float = randf()",
	"var r: int = randi_range(0, 3)",
	"var g := RandomNumberGenerator.new()",
	"var h: int = hash(id)",
	"var h: int = hash (id)",
	"var p := CPUParticles2D.new()",
	"var p: GPUParticles2D = null",
	"items.shuffle()",
	"var x = items.pick_random()",
	"randomize()",
]
const CLEAN: Array[String] = [
	"var t: float = LifeClock.ms(snap, alpha)",
	"var t: float = LifeClock.tick_ms(tick)",
	"var h: int = LifeClock.mix(id, 3)",
	"var hash_of: int = mix_of(id)",
	"var timer_count: int = 0",
	"var lifetime: int = life.emit_life_ms[kind]",
	"# Time.get_ticks_msec() is the frame clock, which life does not use",
	"var seed_of: int = LifeClock.pick(id, 0, 4)",
	"var particles_made: int = 0",
]


func test_no_life_file_reads_a_clock_or_a_random_generator_or_makes_particles() -> void:
	var found: Array[String] = []
	for path: String in LIFE_FILES:
		found.append_array(_hits(FileAccess.get_file_as_string(path), path))
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_no_life_function_of_a_layer_does_either() -> void:
	var found: Array[String] = []
	for path: String in LIFE_FUNCTIONS:
		for name: String in LIFE_FUNCTIONS[path]:
			var code: String = SourceScan.function(path, name)
			assert_int(code.count("\n")).override_failure_message(name).is_greater(2)
			found.append_array(_hits(code, "%s %s" % [path, name]))
	assert_array(found).override_failure_message("\n".join(found)).is_empty()


func test_the_scan_flags_what_it_must_and_spares_the_rest() -> void:
	for source: String in FLAGGED:
		assert_array(_hits(source, "fixture")).override_failure_message(source).has_size(1)
	for source: String in CLEAN:
		assert_array(_hits(source, "fixture")).override_failure_message(source).is_empty()


func test_the_scan_reads_the_files_it_should() -> void:
	for path: String in LIFE_FILES:
		(
			assert_int(FileAccess.get_file_as_string(path).length())
			. override_failure_message(path)
			. is_greater(500)
		)
	for path: String in LIFE_FUNCTIONS:
		assert_int(FileAccess.get_file_as_string(path).length()).is_greater(5000)


## "where: line: text" for each line of `source`, comments taken out, that matches BANNED.
func _hits(source: String, where: String) -> Array[String]:
	var banned: RegEx = RegEx.create_from_string(BANNED)
	var found: Array[String] = []
	var lines: PackedStringArray = FileScan.code_lines(source)
	for index: int in lines.size():
		if banned.search(lines[index]) != null:
			found.append("%s:%d: %s" % [where, index + 1, lines[index].strip_edges()])
	return found
