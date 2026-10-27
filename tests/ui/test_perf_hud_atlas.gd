extends GdUnitTestSuite
## PerfHud, the atlas keys (plan P113): `atlas_bake_ms` and `atlas_page` are descriptive and carry
## no verdict. The scene that bakes the per-match atlas sets them; the summary, the card and the
## copy report print them, `restart()` keeps them (the atlas is per match, not per run), and no
## value of them changes a verdict or the gate.

const Rig: GDScript = preload("res://tests/ui/support/perf_hud_rig.gd")
const ROW: String = "atlas bake %.1f ms | page %s (no verdict)"


func test_a_scene_that_bakes_no_atlas_reads_zero_and_none() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	assert_float(s["atlas_bake_ms"]).is_equal(0.0)
	assert_str(s["atlas_page"]).is_equal("none")
	assert_array(Array(hud.card_lines())).contains([ROW % [0.0, "none"]])


func test_the_bake_time_and_the_page_reach_the_summary_the_card_and_the_copy_report() -> void:
	var hud: PerfHud = auto_free(Rig.hud())
	var sent: Array[String] = []
	hud.clipboard_sink = func(text: String) -> void: sent.append(text)
	hud.atlas_bake_ms = 312.46
	hud.atlas_page = "4096x2258 at 1.000"
	Rig.run(hud)
	var s: Dictionary = hud.summary()
	assert_float(s["atlas_bake_ms"]).is_equal(312.46)
	assert_str(s["atlas_page"]).is_equal("4096x2258 at 1.000")
	assert_array(Array(hud.card_lines())).contains([ROW % [312.46, "4096x2258 at 1.000"]])
	hud.copy_report()
	var json: JSON = JSON.new()
	assert_int(json.parse(sent[0])).is_equal(OK)
	assert_float(json.data["atlas_bake_ms"]).is_equal(312.46)
	assert_str(json.data["atlas_page"]).is_equal("4096x2258 at 1.000")


func test_restart_keeps_the_atlas_numbers_and_they_never_change_a_verdict() -> void:
	var plain: PerfHud = auto_free(Rig.hud())
	Rig.run(plain)
	var hud: PerfHud = auto_free(Rig.hud())
	hud.atlas_bake_ms = 99_999.0  # A bake that took a minute: reported, never judged.
	hud.atlas_page = "4096x4096 at 0.250"
	Rig.run(hud)
	assert_array(hud.summary()["verdicts"]).is_equal(plain.summary()["verdicts"])
	assert_bool(hud.summary()["gate_pass"]).is_equal(plain.summary()["gate_pass"])
	hud.restart()
	assert_float(hud.summary()["atlas_bake_ms"]).is_equal(99_999.0)
	assert_str(hud.summary()["atlas_page"]).is_equal("4096x4096 at 0.250")
