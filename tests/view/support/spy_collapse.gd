extends BuildingCollapse
## A `BuildingCollapse` that notes what the layer hands it (plan P159's tests), then collapses it.
## Not a test suite; a file of its own because an inner class may not extend a script.

var calls: Array[Array] = []  ## [id, died tick, was a site, cancelled] of each `adopt`.


func adopt(entry: BuildingLayer.Entry, tick: int, was_site: bool, cancelled: bool) -> void:
	calls.append([entry.id, tick, was_site, cancelled])
	super(entry, tick, was_site, cancelled)
