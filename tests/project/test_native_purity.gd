extends GdUnitTestSuite
## C++ purity guard for native/sim_kernels/src (ADR 0013 sections 2, 4 and 6; CLAUDE.md rule 1).
## Comments and string and character literals are blanked (line numbers stay), then each rule is
## a regex over the whole text. core/ (plain C++17 over WorldView): no float, <cmath>, time,
## randomness, thread, atomic, mutable static, thread_local, allocation without `// alloc-ok`,
## unordered container, std::hash, Godot header, SIMD intrinsic, cast, char, short, int or long,
## integer literal other than 0 and 1 outside a commented `constexpr` (the mirror of a GDScript
## const), or raw int8 or int32 pointer outside `struct WorldView`. bind/ (the only code that
## touches Godot types, so Godot headers, heap use and int are fine): the float, time, randomness
## and thread bans, no Packed*Array parameter (each form writes to a silent copy), and
## reinterpret_cast or const_cast only in world_access.h. Both scans pass while core/ is absent
## (P54 adds it); the fixtures keep them from being vacuous: every banned word is probed and every
## rule has a flagged and a legal fixture. The ClassDB and SimKernels bans are in test_sim_purity.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const NATIVE_DIR: String = "res://native/sim_kernels/src"
const COMMENT_FIXTURE: String = "res://tests/project/fixtures/native_comments_and_strings.txt"
const CORE: String = "core"
const BIND: String = "bind"
## The rules that bind/ does not have; packed_param is the one that core/ does not have.
const CORE_ONLY: Array[String] = [
	"alloc", "unordered", "godot_header", "simd", "plain_type", "int_literal", "raw_pointer"
]
## A quoted include keeps its path (the Godot header rule reads it); the rest is blanked.
const BLANKED: String = (
	r'(#\s*include\s*"[^"\n]*")|"(?:[^"\\\n]|\\.)*"'
	+ r"|(?<![0-9A-Za-z_])'(?:[^'\\\n]|\\.)+'|//[^\n]*|/\*[\s\S]*?\*/"
)
const CONSTEXPR_STATEMENT: String = r"\bconstexpr\b[^;]*;"
const WORLD_VIEW: String = r"\b(?:struct|class)\s+WorldView\b[^;{]*\{"

## How a list of words becomes a regex piece, and the probe that must trip it: [regex, probe].
const SHAPES: Dictionary[String, Array] = {
	"word": [r"\b(?:%s)\b", "%s"],
	"call": [r"\b(?:%s)\s*\(", "%s(0)"],
	"method": [r"\.(?:%s)\s*\(", "v.%s(0)"],
	"std": [r"\bstd::(?:%s)\b", "std::%s"],
	"singleton": [r"\b(?:%s)::get_singleton\b", "%s::get_singleton()"],
	"include": [r"#\s*include\s*<(?:%s)>", "#include <%s>"],
	"path": [r'#\s*include\s*[<"][^>"]*(?:%s)', '#include "x/%s.h"'],
}
## Rows of "rule shape words", or "rule raw regex" (no spaces). A rule is its rows joined, each
## row's words filled into its shape. Words are regex text (`math\.h`). The test probes each word.
const RULES: Array[String] = [
	"float_type word float double",
	r"float_literal raw (?<![\w.])(?:\d[\d']*\.\d*|\.\d+)|(?<![\w.])\d[\d']*[eE][+-]?\d",
	r"cmath include cmath math\.h tgmath\.h cfloat float\.h complex",
	"cmath std sqrt pow exp log sin cos tan atan atan2 floor ceil round trunc fmod hypot",
	r"time include chrono ctime time\.h sys/time\.h",
	"time std chrono",
	"time call clock time clock_gettime gettimeofday nanosleep usleep __rdtsc",
	"time singleton Time OS Engine",
	"random include random",
	"random std mt19937 mt19937_64 random_device",
	r"random raw \bstd::\w+_(?:engine|distribution)\b",
	"random word RandomNumberGenerator",
	"random call rand srand random srandom drand48 randi randf randi_range randf_range randomize",
	r"threads include thread atomic mutex future condition_variable semaphore pthread\.h omp\.h",
	"threads std thread atomic atomic_flag mutex recursive_mutex shared_mutex timed_mutex",
	"threads word Thread Mutex Semaphore WorkerThreadPool",
	r"threads raw \b(?:pthread_\w+|__atomic_\w+)\b|#\s*pragma\s+omp\b",
	"thread_local word thread_local __thread",
	# A variable has no `(` before its `=`, `;` or `{`; a function does. const is fine.
	r"mutable_static raw \bstatic\b(?![^;(){}=]*\b(?:const|constexpr)\b)[^;(){}=]*[=;{]",
	"alloc word new malloc calloc realloc aligned_alloc posix_memalign alloca strdup",
	"alloc call free",
	r"alloc raw \bdelete\b(?!\s*;)",
	"alloc std vector string basic_string map multimap set multiset list forward_list deque",
	"alloc std queue priority_queue stack make_unique make_shared unique_ptr shared_ptr allocator",
	"alloc method resize reserve push_back emplace_back push_front shrink_to_fit",
	"unordered word unordered_map unordered_set unordered_multimap unordered_multiset",
	"unordered std hash",
	"godot_header path godot gdextension bind/ world_access",
	"godot_header word godot",
	r"simd include x86intrin\.h intrin\.h arm_neon\.h arm_sve\.h wasm_simd128\.h",
	"simd std experimental::simd",
	r"simd raw #\s*include\s*<\w*mmintrin\.h>|\b_mm\d*_\w+|\b__m\d+\w*|\bvector_size\b",
	r"simd raw \b(?:u?int|float)\d+x\d+(?:x\d+)?_t\b|\b__builtin_ia32_",
	"plain_type word char short int long signed unsigned wchar_t char8_t char16_t char32_t",
	r"int_literal raw (?<![\w.])(?:0[xX][\da-fA-F']+|0[bB][01']+|\d[\d']*)[uUlL]*(?![\w.])",
	r"raw_pointer raw \bu?int(?:8|32)_t\b\s*(?:const\s*)?\*",
	"cast word reinterpret_cast const_cast",
	r"packed_param raw [(,]\s*(?:const\s+)?(?:godot::)?Packed\w*Array\s*[&*]*\s*\w*\s*[,)=]",
]

## "rule|source": what the words cannot say. The source trips its rule, and nothing else, in the
## layers that have it. A line break is \n. Literals are 0 and 1 unless the rule is int_literal.
const FLAGGED: Array[String] = [
	"float_literal|int64_t x = 3.5;",
	"float_literal|int64_t x = 2.;",
	"float_literal|int64_t x = .5;",
	"float_literal|int64_t x = 1e3;",
	"random|std::normal_distribution<int64_t> d;",
	"random|std::default_random_engine e;",
	"godot_header|#include <godot_cpp/variant/variant.hpp>",
	"threads|pthread_mutex_t m;",
	"threads|int64_t v = __atomic_load_n(&x, 0);",
	"threads|#pragma omp parallel for",
	"mutable_static|static int64_t counter = 0;",
	"mutable_static|static int64_t cache;",
	"mutable_static|int64_t f() {\n\tstatic int64_t calls = 0;\n\treturn calls;\n}",
	"alloc|delete p;",
	"simd|#include <immintrin.h>",
	"simd|__m128i v;",
	"simd|int32x4_t v;",
	"simd|float32x4_t v;",
	"simd|x = _mm_add_epi32(a, b);",
	"simd|x = __builtin_ia32_pause();",
	"simd|typedef int64_t Lane __attribute__((vector_size(1)));",
	"int_literal|int64_t m = 0x7fffffff;",
	"int_literal|int64_t b = 0b101;",
	"int_literal|int64_t a = 1'0 + 2'0;",
	"int_literal|int64_t n = -2;",
	"int_literal|constexpr int64_t UNREACHED = 2147483647;",
	"int_literal|constexpr int64_t K = 0;  // mirrors GDScript K\nint64_t n = 7;",
	"raw_pointer|const int32_t *px = nullptr;",
	"raw_pointer|uint8_t *flags = nullptr;",
	"raw_pointer|int32_t const *px = nullptr;",
	"raw_pointer|struct WorldView {\n\tint64_t n;\n};\nuint8_t *flags = nullptr;",
	"packed_param|void flow(godot::PackedInt32Array p);",
	"packed_param|Variant f(const PackedByteArray &p, int64_t n);",
	"packed_param|void g(int64_t n,\n\tPackedInt64Array &p);",
	"packed_param|void h(PackedInt32Array &);",
	"packed_param|void k(PackedInt32Array p = PackedInt32Array());",
]
## "rule|source": look-alikes of the rule that no layer may flag.
const LEGAL: Array[String] = [
	"float_type|int64_t floats = 0;  // float and double in a comment",
	"float_literal|constexpr int64_t MASK = 0x1e3;  // mirrors GDScript MASK",
	"cmath|#include <cstdint>\n#include <cstddef>\nauto e = std::experimental::foo;",
	"time|int64_t span = tick_time(1);",
	"random|int64_t span = operand(1);",
	"threads|int64_t atomic_count = 0;\nint64_t thread_count = 1;",
	"thread_local|int64_t thread_local_count = 0;",
	"mutable_static|static int64_t f(int64_t x) { return x; }\nstatic constexpr int64_t K = 0;",
	"mutable_static|static const int64_t L = 1;",
	"alloc|std::vector<int64_t> events;  // alloc-ok\nFoo(const Foo &) = delete;\nint64_t newest = 0;",
	"unordered|int64_t unordered_count = 0;\nint64_t hashed = 1;",
	'godot_header|#include <cstdint>\n#include "world_view.h"',
	"simd|int64_t mm_lanes = 0;\nint64_t vector_size_total = 1;",
	'plain_type|uint8_t byte = 0;\nint64_t point = 0;  // int and long\nnote("char short");',
	"int_literal|int64_t a = 0;\nint64_t b = -1;\nint64_t c = 0u + 1ULL;",
	"int_literal|constexpr int64_t U = 2147483647;  // mirrors GDScript U",
	"int_literal|// DX mirrors the twin's DX.\nconstexpr int64_t DX[4] = {\n\t0, 3,\n\t-3\n};",
	"raw_pointer|struct WorldView { const uint8_t *flags; };",
	(
		"raw_pointer|struct WorldView {\n\tconst int32_t *px;\n"
		+ "\tint64_t pos_x(int64_t row) const { return px[row]; }\n\tuint8_t *flags;\n};"
	),
	"cast|auto v = static_cast<int32_t>(x);",
	"packed_param|PackedInt32Array make(int64_t n);\nauto a = PackedByteArray();",
	"packed_param|foo(1, PackedInt32Array());\nfor (const PackedInt32Array &p : list) {}",
]

var _regexes: Dictionary[String, RegEx] = {}
var _blanked: RegEx
var _constexpr: RegEx
var _world_view: RegEx


func before() -> void:
	_blanked = _compile(BLANKED)
	_constexpr = _compile(CONSTEXPR_STATEMENT)
	_world_view = _compile(WORLD_VIEW)
	var patterns: Dictionary[String, String] = _patterns()
	for rule: String in patterns:
		_regexes[rule] = _compile(patterns[rule])


func test_core_sources_are_pure() -> void:
	assert_array(_scan_tree(CORE)).is_empty()


func test_bind_sources_follow_the_boundary_rules() -> void:
	# The skeleton must be seen, or the scan below could pass on an unreadable folder.
	assert_array(_sources(BIND)).contains(
		[NATIVE_DIR + "/bind/register_types.cpp", NATIVE_DIR + "/bind/sim_kernels.h"]
	)
	assert_array(_scan_tree(BIND)).is_empty()


func test_every_rule_has_a_flagged_and_a_legal_fixture() -> void:
	assert_array(_names(FLAGGED + _probes(), "|", 0)).contains_exactly_in_any_order(_regexes.keys())
	assert_array(_names(LEGAL, "|", 0)).contains_exactly_in_any_order(_regexes.keys())


## A fixture trips its rule and nothing else; a banned word trips its rule, maybe more (`float.h`
## holds `float`). In the layer without the rule, neither trips it.
func test_every_fixture_and_banned_word_trips_its_rule() -> void:
	assert_array(_probes()).is_not_empty()
	assert_array(_misjudged(FLAGGED, true)).is_empty()
	assert_array(_misjudged(_probes(), false)).is_empty()


func test_legal_fixtures_pass_in_both_layers() -> void:
	var wrongly_flagged: Array[String] = []
	for layer: String in [CORE, BIND]:
		for entry: String in LEGAL:
			for report: String in _violations(layer, "fixture.cpp", _source(entry)):
				wrongly_flagged.append("%s: %s" % [layer, report])
	assert_array(wrongly_flagged).is_empty()


## Banned words in comments, strings and character literals are blanked, a quoted include is
## kept, and the line numbers survive: the only report is the last line of the fixture.
func test_comments_and_strings_never_flag_and_keep_the_line_numbers() -> void:
	var source: String = FileAccess.get_file_as_string(COMMENT_FIXTURE)
	assert_array(_violations(BIND, "f.cpp", source)).is_empty()
	assert_array(_violations(CORE, "f.cpp", source)).contains_exactly(
		["f.cpp:11: plain_type: int e = int(0);  // the one report: plain_type, twice on this line"]
	)


func test_a_cast_belongs_to_world_access_in_bind_and_nowhere_in_core() -> void:
	var source: String = "auto *p = reinterpret_cast<Foo *>(q);"
	assert_array(_violations(BIND, "bind/world_access.h", source)).is_empty()
	assert_array(_violations(BIND, "bind/kernel_flow.cpp", source)).is_not_empty()
	assert_array(_violations(CORE, "core/world_access.h", source)).is_not_empty()


func _compile(pattern: String) -> RegEx:
	var regex: RegEx = RegEx.new()
	assert_int(regex.compile(pattern)).is_equal(OK)
	return regex


## The regex of each rule: its rows joined, each row's words filled into its shape.
func _patterns() -> Dictionary[String, String]:
	var patterns: Dictionary[String, String] = {}
	for row: String in RULES:
		var parts: PackedStringArray = row.split(" ", true, 2)
		var piece: String = parts[2]
		if parts[1] != "raw":
			piece = SHAPES[parts[1]][0] % piece.replace(" ", "|")
		patterns[parts[0]] = (patterns[parts[0]] + "|" + piece) if patterns.has(parts[0]) else piece
	return patterns


## "rule|source" for each banned word: the shape's probe with the word in it.
func _probes() -> Array[String]:
	var found: Array[String] = []
	for row: String in RULES:
		var parts: PackedStringArray = row.split(" ", true, 2)
		if parts[1] != "raw":
			for word: String in parts[2].split(" "):
				found.append("%s|%s" % [parts[0], SHAPES[parts[1]][1] % word.replace("\\", "")])
	return found


## The entries that the scan judges wrongly. In a layer with the entry's rule the source must trip
## it (and, if `exact`, nothing else); in the other layer it must not trip it.
func _misjudged(entries: Array, exact: bool) -> Array[String]:
	var wrong: Array[String] = []
	for layer: String in [CORE, BIND]:
		for entry: String in entries:
			var rule: String = entry.get_slice("|", 0)
			var owned: bool = _has_rule(layer, rule)
			var reports: Array[String] = _violations(layer, "fixture.cpp", _source(entry))
			var found: Array[String] = _names(reports, ": ", 1)
			if found.has(rule) != owned or (owned and exact and found.size() != 1):
				wrong.append("%s: %s -> %s" % [layer, entry, found])
	return wrong


func _sources(layer: String) -> Array[String]:
	var found: Array[String] = []
	for extension: String in [".cpp", ".h", ".hpp"]:
		found.append_array(FileScan.list_files(NATIVE_DIR.path_join(layer), extension))
	found.sort()
	return found


func _scan_tree(layer: String) -> Array[String]:
	var found: Array[String] = []
	for path: String in _sources(layer):
		found.append_array(_violations(layer, path, FileAccess.get_file_as_string(path)))
	return found


func _has_rule(layer: String, rule: String) -> bool:
	if rule == "packed_param":
		return layer == BIND
	return layer == CORE or not rule in CORE_ONLY


## The fixture's source: everything after the first `|`.
func _source(entry: String) -> String:
	return entry.substr(entry.find("|") + 1)


## The distinct values at `index` of the items split at `separator`: the rule names of fixture
## entries ("rule|source") or of reports ("label:line: rule: text").
func _names(items: Array, separator: String, index: int) -> Array[String]:
	var names: Array[String] = []
	for item: String in items:
		var name: String = item.split(separator, true, 2)[index]
		if not names.has(name):
			names.append(name)
	return names


## "label:line: rule: text" for each line a rule flags in `source`, rule by rule.
func _violations(layer: String, label: String, source: String) -> Array[String]:
	var raw: PackedStringArray = source.split("\n")
	var code: String = _blank(source)
	var view: Vector2i = _view_lines(code)
	var constants: Dictionary[int, bool] = _documented_constants(code, raw)
	var found: Array[String] = []
	for rule: String in _regexes:
		if not _has_rule(layer, rule):
			continue
		for hit: RegExMatch in _regexes[rule].search_all(code):
			var line: int = code.substr(0, hit.get_start()).count("\n") + 1
			var text: String = raw[line - 1]
			var allowed: bool = false
			match rule:
				"alloc":
					allowed = text.strip_edges().ends_with("// alloc-ok")
				"cast":
					allowed = layer == BIND and label.get_file() == "world_access.h"
				"raw_pointer":
					allowed = line >= view.x and line <= view.y
				"int_literal":
					allowed = hit.get_string().rstrip("uUlL") in ["0", "1"] or constants.has(line)
			var report: String = "%s:%d: %s: %s" % [label, line, rule, text.strip_edges()]
			if not allowed and not found.has(report):
				found.append(report)
	return found


## `source` with comments, string literals and character literals replaced by a space and their
## line breaks, so that line numbers hold. A quoted #include stays as it is.
func _blank(source: String) -> String:
	var code: String = ""
	var from: int = 0
	for hit: RegExMatch in _blanked.search_all(source):
		code += source.substr(from, hit.get_start() - from)
		var kept: String = hit.get_string(1)
		code += kept if not kept.is_empty() else " " + "\n".repeat(hit.get_string().count("\n"))
		from = hit.get_end()
	return code + source.substr(from)


## First and last line (1-based) of the `struct WorldView { ... }` body, the one place raw
## pointers belong, or (-1, -1) without one.
func _view_lines(code: String) -> Vector2i:
	var open: RegExMatch = _world_view.search(code)
	if open == null:
		return Vector2i(-1, -1)
	var depth: int = 1
	var at: int = open.get_end()
	while depth > 0 and at < code.length():
		depth += int(code[at] == "{") - int(code[at] == "}")
		at += 1
	var first: int = code.substr(0, open.get_start()).count("\n") + 1
	return Vector2i(first, code.substr(0, at).count("\n") + 1)


## The lines (1-based) of `constexpr ...;` statements that name their GDScript const in a
## comment: on one of their own lines, or alone on the line above.
func _documented_constants(code: String, raw: PackedStringArray) -> Dictionary[int, bool]:
	var lines: Dictionary[int, bool] = {}
	for hit: RegExMatch in _constexpr.search_all(code):
		var first: int = code.substr(0, hit.get_start()).count("\n")
		var last: int = first + hit.get_string().count("\n")
		var commented: bool = first > 0 and raw[first - 1].strip_edges().begins_with("//")
		for index: int in range(first, last + 1):
			commented = commented or raw[index].contains("//")
		if commented:
			for index: int in range(first, last + 1):
				lines[index + 1] = true
	return lines
