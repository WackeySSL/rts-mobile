class_name FakePoingSet
extends RefCounted
## The Poing singletons a backend looks up, one `FakePoingPlugin` each (own signals, own uid
## counter), all writing to one ordered call log.

## Every call across all the fakes, in order: name, arguments, singleton.
var calls: Array[Array] = []
var _plugins: Dictionary = {}


## The fake for `singleton`, created on first use.
func of(singleton: String) -> FakePoingPlugin:
	if not _plugins.has(singleton):
		_plugins[singleton] = FakePoingPlugin.new(singleton, calls)
	return _plugins[singleton]


func lookup(singleton: String) -> Object:
	return of(singleton)


func names() -> Array[String]:
	var out: Array[String] = []
	for entry: Array in calls:
		out.append(String(entry[0]))
	return out


## The arguments of the first call named `call_name` (without the name and the singleton).
func args_of(call_name: String) -> Array:
	for entry: Array in calls:
		if entry[0] == call_name:
			return entry.slice(1, entry.size() - 1)
	return []


func count(call_name: String) -> int:
	return names().count(call_name)
