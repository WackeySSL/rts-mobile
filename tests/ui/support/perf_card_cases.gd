extends RefCounted
## Fixed runs whose card text and summary JSON `test_perf_card_pin.gd` pins (plan P184, the
## `PerfHud` split moved the text into `PerfCard`). Not a test suite. `render()` gives one case as
## text: the card's lines, then the summary as sorted JSON. The keys that read the machine (model,
## engine, screen, os) are left out, and so is the card row that prints them.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const CASES: PackedStringArray = [
	"passing_units", "failing_debug_paused", "bases_arena", "android_native", "android_gdscript"
]
const MACHINE_KEYS: PackedStringArray = ["model", "engine", "screen", "os"]


static func hud_of(case_name: String) -> PerfHud:
	var hud: PerfHud = Rig.hud()
	hud.os_name = "Linux"
	hud.atlas_bake_ms = 12.5
	hud.atlas_page = "4096x2258 at 1.000"
	match case_name:
		"passing_units":
			Rig.run(hud)
		"failing_debug_paused":
			hud.debug_build = true
			Rig.pass_frames(hud, {}, {5: {"interval": 40000}, 6: {"calls": 0}})
			hud.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
			Rig.ticks(hud, hud.run_ticks, 20, 30_000)
		"bases_arena":
			hud.arena_kind = PerfHud.ARENA_BASES
			Rig.run(hud)
		"android_native":
			hud.os_name = MatchRunner.OS_ANDROID
			hud._sim_impl = MatchRunner.SimImpl.NATIVE
			hud._native_phases = ["FLOW", "MOVE"]
			hud._native_build = "arm64 release"
			hud._self_check_result = PerfHud.SELF_CHECK_MATCH
			Rig.run(hud)
		"android_gdscript":
			hud.os_name = MatchRunner.OS_ANDROID
			Rig.run(hud)
	return hud


static func render(case_name: String) -> String:
	var hud: PerfHud = hud_of(case_name)
	var lines: PackedStringArray = PackedStringArray()
	for line: String in hud.card_lines():
		if not line.contains(" | screen "):
			lines.append(line)
	var summary: Dictionary = hud.summary()
	for key: String in MACHINE_KEYS:
		summary.erase(key)
	hud.free()
	return "== %s ==\n%s\n%s\n" % [case_name, "\n".join(lines), JSON.stringify(summary, "  ", true)]
