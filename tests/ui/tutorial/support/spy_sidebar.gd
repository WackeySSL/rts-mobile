extends BuildSidebar
## A `BuildSidebar` that only counts the cards it was asked to reveal (plan row P591). Not a test
## suite. A file of its own, since an inner class with a script base is not allowed.

var asked: Array[ItemTile] = []


func _ready() -> void:  # No HUD feed here: the spy only counts the asks.
	pass


func reveal_tile(tile: ItemTile) -> void:
	asked.append(tile)
