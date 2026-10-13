extends GdUnitTestSuite
## C++ purity guard for native/sim_kernels/src (ADR 0013 sections 2, 4 and 6; CLAUDE.md rule 1).
## Comments and string and character literals are blanked (line numbers stay), then each rule is
## a regex over the whole text. core/ (plain C++17 over WorldView): no float, <cmath>, time,
## randomness, thread, atomic, mutable static or inline variable, thread_local, allocation without
## `// alloc-ok`, unordered container, std::hash, Godot header, SIMD intrinsic, cast, char, short,
## int or long, integer literal other than 0 and 1 outside a `constexpr` variable with a comment of
## its own (on its line or alone on the line above: the mirror of a GDScript const), and raw int8
## or int32 pointer outside a `struct|class *View` body or used through `.name` or `->name` outside
## it (the accessors belong in the body). bind/ (the only code that touches Godot types, so Godot
## headers, heap use and int are fine): the float, time, randomness and thread bans (godot-cpp
## headers pull in <cmath> and <atomic>, so the words are banned too, not only the includes), no
## Packed*Array parameter by value or reference (the ADR bans those; a pointer is in place and
## legal), and reinterpret_cast or const_cast only in world_access.h. Both layers: no static
## Godot or std object (const or not: it is built lazily on the worker). Both scans pass while
## core/ is absent (P54 adds it, and its PR adds an assertion that core/ is seen). Every banned
## word is probed and counted, and the ADR-named bans are pinned by hand (PINNED) apart from the
## word lists, so deleting a word fails; every rule has a flagged and a legal fixture. Blind
## spots, left to review: a global without static or inline, and `static int64_t n(0);`. The
## ClassDB and SimKernels bans are in test_sim_purity.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const NATIVE_DIR: String = "res://native/sim_kernels/src"
const COMMENT_FIXTURE: String = "res://tests/project/fixtures/native_comments_and_strings.txt"
const CORE: String = "core"
const BIND: String = "bind"
const EXTENSIONS: Array[String] = ["cpp", "h", "hpp"]
## Any other C or C++ source or header is never scanned. (Build output, `.os`, is not source.)
const UNSCANNED: Array[String] = ["c", "cc", "cxx", "hh", "hxx", "inl", "inc", "ipp", "tpp"]
## The rules that bind/ does not have; packed_param is the one that core/ does not have.
const CORE_ONLY: Array[String] = [
	"alloc", "unordered", "godot_header", "simd", "plain_type", "int_literal", "raw_pointer"
]
## The number of banned words in RULES. A word dropped from a list fails the test until this line
## is edited with it, so a deletion is a decision in the diff and not a silent hole.
const BANNED_WORDS: int = 276
## A quoted include keeps its path (the Godot header rule reads it); the rest is blanked.
const BLANKED: String = (
	r'(#\s*include\s*"[^"\n]*")|"(?:[^"\\\n]|\\.)*"'
	+ r"|(?<![0-9A-Za-z_])'(?:[^'\\\n]|\\.)+'|//[^\n]*|/\*[\s\S]*?\*/"
)
## A constexpr variable, not a function or `if constexpr`: no ( or { before its = or {.
const CONSTEXPR_STATEMENT: String = r"\bconstexpr\b[^;(){}=]*(?:=|\{)[^;]*;"
## The body of a view struct, where raw pointers belong, and the pointer names declared in it.
const VIEW: String = r"\b(?:struct|class)\s+\w*View\b[^;{]*\{"
const VIEW_POINTER: String = r"\bu?int(?:8|32)_t\b\s*(?:const\s*)?\*\s*(?:const\s+)?(\w+)"
## What ends a variable declaration: = ; { or a direct-init of a literal, `n("x")` (blanked).
const VARIABLE_END: String = r"[^;(){}=]*(?:[=;{]|\((?:\s+|\s*[-+]?\d[\w']*\s*)\))"

## How a list of words becomes a regex piece, and the probe that must trip it: [regex, probe].
const SHAPES: Dictionary[String, Array] = {
	"word": [r"\b(?:%s)\b", "%s"],
	"call": [r"\b(?:%s)\s*\(", "%s(0)"],
	"method": [r"\.(?:%s)\s*\(", "v.%s(0)"],
	"std": [r"\bstd::(?:%s)\b", "std::%s"],
	"singleton": [r"\b(?:%s)::get_singleton\b", "%s::get_singleton()"],
	"include": [r"#\s*include\s*<(?:%s)>", "#include <%s>"],
	"path": [r'#\s*include\s*[<"][^>"]*(?:%s)', '#include "x/%s.h"'],
	"static": [r"\bstatic\b[^;(){}=]*\b(?:%s)\b" + VARIABLE_END, "static const %s n = 0;"],
}
## Rows of "rule shape words", or "rule raw regex" (no spaces). A rule is its rows joined, each
## row's words filled into its shape. Words are regex text (`math\.h`). The test probes each word.
const RULES: Array[String] = [
	"float_type word float double real_t Vector2 Vector3 Vector4 Rect2 Transform2D Transform3D",
	"float_type word Basis Quaternion Color Plane AABB Projection",
	r"float_literal raw (?<![\w.])(?:\d[\d']*\.\d*|\.\d+)|(?<![\w.])\d[\d']*[eE][+-]?\d",
	r"float_literal raw (?<![\w.])0[xX][\da-fA-F'.]*[pP][+-]?\d",
	r"cmath include cmath math\.h tgmath\.h cfloat float\.h complex",
	"cmath std sqrt pow exp exp2 expm1 log log2 log10 log1p sin cos tan asin acos atan atan2",
	"cmath std sinh cosh tanh floor ceil round lround llround trunc fmod remainder hypot fabs",
	"cmath std cbrt fma fmin fmax fdim modf ldexp frexp copysign nearbyint rint lrint",
	"cmath std isnan isinf isfinite signbit",
	"cmath call sqrt pow exp exp2 log log2 log10 sin cos tan atan atan2 floor ceil round trunc",
	"cmath call lround fmod hypot fabs cbrt fma fmin fmax modf",
	r"cmath raw \bMath::\w+|\b__builtin_(?:sqrt|pow|exp|log|sin|cos|tan|atan|floor|ceil)\w*",
	r"cmath raw \b__builtin_(?:round|trunc|fabs|fmod|inf|nan|huge_val)\w*",
	r"time include chrono ctime time\.h sys/time\.h",
	"time std chrono",
	"time call clock time clock_gettime gettimeofday nanosleep usleep __rdtsc",
	"time singleton Time OS Engine",
	"random include random",
	"random std mt19937 mt19937_64 random_device",
	r"random raw \bstd::\w+_(?:engine|distribution)\b",
	"random word RandomNumberGenerator",
	"random call rand srand random srandom drand48 randi randf randi_range randf_range randomize",
	r"threads include thread atomic mutex shared_mutex future condition_variable semaphore",
	r"threads include barrier latch stop_token pthread\.h omp\.h",
	"threads std thread jthread atomic mutex recursive_mutex shared_mutex timed_mutex",
	"threads std this_thread lock_guard unique_lock shared_lock scoped_lock async promise future",
	"threads std shared_future packaged_task condition_variable condition_variable_any once_flag",
	"threads std call_once counting_semaphore binary_semaphore",
	"threads word Thread Mutex Semaphore WorkerThreadPool SafeNumeric SafeFlag SafeRefCount",
	"threads word SpinLock BinaryMutex MutexLock RWLock",
	r"threads raw \bstd::atomic\w*|\b(?:pthread_\w+|__atomic_\w+|__sync_\w+)\b|\b_Atomic\b",
	r"threads raw #\s*pragma\s+omp\b",
	"thread_local word thread_local __thread",
	# A variable has no `(` before its `=`, `;` or `{`; a function does. _is_constant judges const.
	r"mutable_static raw \b(?:static|inline)\b[^;(){}=]*[=;{]",
	# Built on first use, on the worker: const or not, no static Godot or heap object (ADR 0013 s6).
	"static_object static StringName String Variant NodePath Array Dictionary Callable Signal",
	"static_object static Object Ref RID TypedArray PackedByteArray PackedInt32Array",
	"static_object static std::string std::vector std::map std::set std::list std::deque",
	"static_object static std::function std::unique_ptr std::shared_ptr",
	"alloc word new malloc calloc realloc aligned_alloc posix_memalign alloca strdup",
	"alloc call free",
	r"alloc raw \bdelete\b(?!\s*;)",
	"alloc include vector string map set list forward_list deque queue stack memory functional",
	"alloc include sstream valarray",
	"alloc std vector string basic_string map multimap set multiset list forward_list deque",
	"alloc std queue priority_queue stack make_unique make_shared unique_ptr shared_ptr allocator",
	"alloc std valarray function stable_sort inplace_merge stringstream ostringstream to_string",
	"alloc method resize reserve push_back emplace_back push_front shrink_to_fit",
	"unordered word unordered_map unordered_set unordered_multimap unordered_multiset",
	"unordered include unordered_map unordered_set",
	"unordered std hash",
	"godot_header path godot gdextension bind/ world_access",
	"godot_header word godot",
	r"simd include x86intrin\.h intrin\.h arm_neon\.h arm_sve\.h wasm_simd128\.h experimental/simd",
	"simd std experimental::simd",
	r"simd raw #\s*include\s*<\w*mmintrin\.h>|\b_mm\d*_\w+|\b__m\d+\w*|\bvector_size\b",
	r"simd raw \b(?:u?int|float)\d+x\d+(?:x\d+)?_t\b|\b__builtin_ia32_",
	"plain_type word char short int long signed unsigned wchar_t char8_t char16_t char32_t",
	r"int_literal raw (?<![\w.])(?:0[xX][\da-fA-F']+|0[bB][01']+|\d[\d']*)[uUlL]*(?![\w.])",
	r"raw_pointer raw \bu?int(?:8|32)_t\b\s*(?:const\s*)?\*",
	"cast word reinterpret_cast const_cast",
	# The parameter (its type, const, :: and godot:: included) is group 1, so a report has its line.
	(
		r"packed_param raw [(,]\s*((?:const\s+)?(?:[\w:]*::)?Packed\w*Array"
		+ r"\s*(?:const\b\s*)?&{0,2}\s*\w*\s*[,)=])"
	),
	r"packed_param raw \b(?:using\s+\w+\s*=|typedef\b)[^;]*\bPacked\w*Array\b",
]

## "rule|source": what the words cannot say. The source trips its rule, and nothing else, in the
## layers that have it. A line break is \n. Literals are 0 and 1 unless the rule is int_literal.
const FLAGGED: Array[String] = [
	"float_literal|int64_t x = 3.5;",
	"float_literal|int64_t x = 2.;",
	"float_literal|int64_t x = .5;",
	"float_literal|int64_t x = 1e3;",
	"float_literal|int64_t x = 0x1p3;",
	"float_literal|auto x = 0x1.8p-1;",
	"cmath|auto r = __builtin_sqrt(x);",
	"random|std::normal_distribution<int64_t> d;",
	"random|std::default_random_engine e;",
	"godot_header|#include <godot_cpp/variant/variant.hpp>",
	"threads|pthread_mutex_t m;",
	"threads|int64_t v = __atomic_load_n(&x, 0);",
	"threads|int64_t v = __sync_fetch_and_add(&x, 1);",
	"threads|_Atomic int64_t v;",
	"threads|std::atomic_int64_t counter;",
	"threads|#pragma omp parallel for",
	"mutable_static|static int64_t counter = 0;",
	"mutable_static|static int64_t cache;",
	"mutable_static|int64_t f() {\n\tstatic int64_t calls = 0;\n\treturn calls;\n}",
	"mutable_static|inline int64_t g_calls = 0;",
	"mutable_static|static const int64_t *last = nullptr;",
	'static_object|static const StringName n = "cost";',
	'static_object|StringName name() {\n\tstatic const StringName n("cost");\n\treturn n;\n}',
	"static_object|void f() {\n\tstatic const Variant v(1);\n}",
	"alloc|delete p;",
	"alloc|p = new Foo;  // not alloc-ok",
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
	"int_literal|constexpr int64_t H = T / 2;",
	"int_literal|int64_t t = 0;  // note\nconstexpr int64_t H = 1000;",
	"int_literal|// helper for cells\nconstexpr int64_t cell_of(int64_t x) {\n\treturn x / 1000;\n}",
	"int_literal|int64_t f() {\n\tif constexpr (true) {  // fast\n\t\treturn 1000;\n\t}\n}",
	"raw_pointer|const int32_t *px = nullptr;",
	"raw_pointer|uint8_t *flags = nullptr;",
	"raw_pointer|int32_t const *px = nullptr;",
	"raw_pointer|struct WorldView {\n\tint64_t n;\n};\nuint8_t *flags = nullptr;",
	"raw_pointer|struct WorldView {\n\tconst int32_t *px;\n};\nauto a = w.px[0];",
	"raw_pointer|struct SlotView {\n\tint32_t *const cost;\n};\nauto *p = slot->cost;",
	"packed_param|void flow(godot::PackedInt32Array p);",
	"packed_param|Variant f(const PackedByteArray &p, int64_t n);",
	"packed_param|void g(int64_t n,\n\tPackedInt64Array &p);",
	"packed_param|void h(PackedInt32Array &);",
	"packed_param|void k(PackedInt32Array p = PackedInt32Array());",
	"packed_param|void f(PackedInt32Array const &p);",
	"packed_param|void f(const ::godot::PackedInt32Array &&p);",
	"packed_param|using Ints = PackedInt32Array;",
]
## "rule|source": look-alikes of the rule that no layer may flag.
const LEGAL: Array[String] = [
	"float_type|int64_t floats = 0;  // float and double in a comment\nVector2i v;",
	"float_literal|constexpr int64_t MASK = 0x1e3;  // mirrors GDScript MASK",
	"cmath|#include <cstdint>\n#include <cstddef>\nauto e = std::experimental::foo;",
	"cmath|int64_t math_floor_count = floor_div(1, 1);\nint64_t Mathematics = 0;",
	"time|int64_t span = tick_time(1);",
	"random|int64_t span = operand(1);",
	"threads|int64_t atomic_count = 0;\nint64_t thread_count = 1;\nint64_t SpinLockCount = 0;",
	"thread_local|int64_t thread_local_count = 0;",
	"mutable_static|static int64_t f(int64_t x) { return x; }\nstatic constexpr int64_t K = 0;",
	"mutable_static|static const int64_t L = 1;\nconstexpr static int64_t M = 0;",
	"mutable_static|const static int64_t B = 1;\ninline constexpr int64_t U = 1;",
	"mutable_static|static int64_t *const P = nullptr;",
	"static_object|static StringName name_of(int64_t row);\nstatic Variant none();",
	'static_object|class Names {\n\tStringName cost;\npublic:\n\tNames() : cost("cost") {}\n};',
	"alloc|std::vector<int64_t> events;  // alloc-ok\nFoo(const Foo &) = delete;\nint64_t newest = 0;",
	"unordered|int64_t unordered_count = 0;\nint64_t hashed = 1;",
	'godot_header|#include <cstdint>\n#include "world_view.h"',
	"simd|int64_t mm_lanes = 0;\nint64_t vector_size_total = 1;",
	"plain_type|flags[row] = static_cast<uint8_t>(v);\nint64_t point = 0;  // int and long",
	'plain_type|note("char short");',
	"int_literal|int64_t a = 0;\nint64_t b = -1;\nint64_t c = 0u + 1ULL;",
	"int_literal|constexpr int64_t U = 2147483647;  // mirrors GDScript U",
	"int_literal|// DX mirrors the twin's DX.\nconstexpr int64_t DX[4] = {\n\t0, 3,\n\t-3\n};",
	"int_literal|/* FlowField.UNREACHED */\nconstexpr int64_t UNREACHED = 0x3FFFFFFF;",
	"int_literal|constexpr int64_t V{7};  /* mirrors GDScript V */",
	"raw_pointer|struct WorldView { const uint8_t *flags; };",
	(
		"raw_pointer|struct WorldView {\n\tconst int32_t *px;\n"
		+ "\tint64_t pos_x(int64_t row) const { return px[row]; }\n\tuint8_t *flags;\n};"
	),
	(
		"raw_pointer|struct SlotView {\n\tint32_t *cost;\n"
		+ "\tint64_t at(int64_t i) const { return cost[i]; }\n};\n"
		+ "int64_t d(SlotView s, int64_t i) { return s.at(i) - s.cost_at(i); }"
	),
	"cast|auto v = static_cast<int32_t>(x);",
	"packed_param|PackedInt32Array make(int64_t n);\nauto a = PackedByteArray();",
	"packed_param|foo(1, PackedInt32Array());\nfor (const PackedInt32Array &p : list) {}",
	"packed_param|int64_t size_of(const PackedInt32Array *a);\nvoid g(PackedInt32Array *const a);",
	"packed_param|using Row = int64_t;\ntypedef int64_t Tick;",
]
## "rule|source" for each ADR-named ban, apart from the word lists above: a probe made from a
## word dies with the word, so these stay when a word is dropped from RULES.
const PINNED: Array[String] = [
	"float_type|double d;",
	"float_type|float f;",
	"cmath|#include <cmath>",
	"cmath|x = std::sqrt(y);",
	"cmath|x = sqrt(y);",
	"cmath|x = Math::sqrt(y);",
	"unordered|std::hash<int64_t> h;",
	"unordered|std::unordered_map<int64_t, int64_t> m;",
	"threads|std::thread t;",
	"threads|std::atomic<int64_t> a;",
	"threads|#include <mutex>",
	"threads|std::mutex m;",
	"thread_local|thread_local int64_t x = 0;",
	"alloc|auto *p = new Foo;",
	"alloc|p = malloc(8);",
	"alloc|std::vector<int64_t> v;",
	"time|#include <chrono>",
	"time|t = OS::get_singleton();",
	"time|t = Time::get_singleton();",
	"time|t = Engine::get_singleton();",
	"random|#include <random>",
	"random|x = rand();",
	"plain_type|long n;",
	"plain_type|char c;",
	"plain_type|short s;",
	"plain_type|int i;",
	"cast|auto *q = const_cast<Foo *>(p);",
	"cast|auto *q = reinterpret_cast<Foo *>(p);",
]
var _regexes: Dictionary[String, RegEx] = {}
var _blanked: RegEx
var _constexpr: RegEx
var _view: RegEx
var _view_pointer: RegEx
var _const_word: RegEx


func before() -> void:
	_blanked = _compile(BLANKED)
	_constexpr = _compile(CONSTEXPR_STATEMENT)
	_view = _compile(VIEW)
	_view_pointer = _compile(VIEW_POINTER)
	_const_word = _compile(r"\bconst\b")
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


## A C++ file elsewhere in src/ (or with another extension) would be built and never scanned.
func test_every_native_source_sits_where_the_scans_look() -> void:
	var stray: Array[String] = []
	for path: String in FileScan.list_files(NATIVE_DIR, ""):
		var layer: String = path.trim_prefix(NATIVE_DIR + "/").get_slice("/", 0)
		var extension: String = path.get_extension()
		if extension in UNSCANNED or (extension in EXTENSIONS and not layer in [CORE, BIND]):
			stray.append(path)
	assert_array(stray).is_empty()


func test_every_rule_has_a_flagged_and_a_legal_fixture() -> void:
	assert_array(_names(FLAGGED + _probes(), "|", 0)).contains_exactly_in_any_order(_regexes.keys())
	assert_array(_names(LEGAL, "|", 0)).contains_exactly_in_any_order(_regexes.keys())


## A fixture trips its rule and nothing else; a banned word trips its rule, maybe more (`float.h`
## holds `float`). In the layer without the rule, neither trips it.
func test_every_fixture_and_banned_word_trips_its_rule() -> void:
	assert_array(_misjudged(FLAGGED, true)).is_empty()
	assert_array(_misjudged(PINNED, false)).is_empty()
	assert_array(_misjudged(_probes(), false)).is_empty()


func test_no_banned_word_is_dropped_unnoticed() -> void:
	assert_int(_probes().size()).is_equal(BANNED_WORDS)


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


func test_a_parameter_is_reported_on_its_own_line() -> void:
	var source: String = "void f(\n\tint64_t a,\n\tconst PackedInt32Array &b,\n\tint64_t c);"
	assert_array(_violations(BIND, "f.cpp", source)).contains_exactly(
		["f.cpp:3: packed_param: const PackedInt32Array &b,"]
	)


func test_a_cast_belongs_to_world_access_in_bind_and_nowhere_in_core() -> void:
	var source: String = "auto *p = reinterpret_cast<Foo *>(q);"
	assert_array(_violations(BIND, "bind/world_access.h", source)).is_empty()
	assert_array(_violations(BIND, "bind/world_access_extra.h", source)).is_not_empty()
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
	for path: String in FileScan.list_files(NATIVE_DIR.path_join(layer), ""):
		if path.get_extension() in EXTENSIONS:
			found.append(path)
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
	var views: Array[Vector2i] = _views(code)
	var constants: Dictionary[int, bool] = _documented_constants(code, raw)
	var found: Array[String] = []
	for rule: String in _regexes:
		if not _has_rule(layer, rule):
			continue
		var hits: Array = _regexes[rule].search_all(code)
		if rule == "raw_pointer":
			hits.append_array(_member_uses(code, views))
		for hit: RegExMatch in hits:
			var at: int = hit.get_start(1) if hit.get_group_count() > 0 else -1
			var line: int = code.substr(0, at if at >= 0 else hit.get_start()).count("\n") + 1
			var text: String = raw[line - 1]
			var allowed: bool = false
			match rule:
				"alloc":
					allowed = text.strip_edges().ends_with("// alloc-ok")
				"cast":
					allowed = layer == BIND and label.get_file() == "world_access.h"
				"raw_pointer":
					allowed = _inside(views, hit.get_start())
				"int_literal":
					allowed = hit.get_string().rstrip("uUlL") in ["0", "1"] or constants.has(line)
				"mutable_static":
					allowed = _is_constant(_declaration(code, hit))
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


## The character range [from, to) of each `struct|class ...View { ... }`, the one place raw
## pointers belong.
func _views(code: String) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for open: RegExMatch in _view.search_all(code):
		var depth: int = 1
		var at: int = open.get_end()
		while depth > 0 and at < code.length():
			depth += int(code[at] == "{") - int(code[at] == "}")
			at += 1
		found.append(Vector2i(open.get_start(), at))
	return found


func _inside(views: Array[Vector2i], at: int) -> bool:
	for view: Vector2i in views:
		if at >= view.x and at < view.y:
			return true
	return false


## The `.name` and `->name` uses of the pointers that the views declare, wherever they are: a
## pointer read outside the accessors is read without the widening of ADR 0013 section 4.
func _member_uses(code: String, views: Array[Vector2i]) -> Array[RegExMatch]:
	var names: PackedStringArray = []
	for view: Vector2i in views:
		for member: RegExMatch in _view_pointer.search_all(code.substr(view.x, view.y - view.x)):
			names.append(member.get_string(1))
	if names.is_empty():
		return []
	return _compile(r"(?:\.|->)\s*(?:%s)\b" % "|".join(names)).search_all(code)


## The declaration around a `static` or `inline` hit: from the last `;`, `{` or `}` to the hit.
func _declaration(code: String, hit: RegExMatch) -> String:
	var start: int = hit.get_start()
	var from: int = maxi(
		maxi(code.rfind(";", start), code.rfind("{", start)), code.rfind("}", start)
	)
	return code.substr(from + 1, hit.get_end() - from - 1)


## Is the variable const? `constexpr` anywhere, or `const` after the last `*` (a `const T *p`
## is a mutable pointer; `T *const p` is not).
func _is_constant(declaration: String) -> bool:
	var tail: String = declaration.substr(declaration.rfind("*") + 1)
	return declaration.contains("constexpr") or _const_word.search(tail) != null


## The lines (1-based) of `constexpr` variables that name their GDScript const in a comment of
## their own: on one of their lines, or alone on the line above.
func _documented_constants(code: String, raw: PackedStringArray) -> Dictionary[int, bool]:
	var lines: Dictionary[int, bool] = {}
	var code_lines: PackedStringArray = code.split("\n")
	for hit: RegExMatch in _constexpr.search_all(code):
		var first: int = code.substr(0, hit.get_start()).count("\n")
		var last: int = first + hit.get_string().count("\n")
		var commented: bool = (
			first > 0
			and code_lines[first - 1].strip_edges().is_empty()
			and not raw[first - 1].strip_edges().is_empty()
		)
		for index: int in range(first, last + 1):
			commented = commented or raw[index].contains("//") or raw[index].contains("/*")
		if commented:
			for index: int in range(first, last + 1):
				lines[index + 1] = true
	return lines
