extends RefCounted
## What the sorted world draws from (ADR 0023 section 2: one texture, so one call): the sprites
## that resolve to `WorldSort.Z_SORT`, found by the z they are drawn at and never by a name, so a
## sprite added to the sort under any name counts. The cast shadows (P237) draw at z 1 and 2 from
## the atlas's second page and are not among them.


## The z Godot draws `item` at: its own, plus its parents' while it is relative.
static func resolved_z(item: CanvasItem) -> int:
	var z: int = 0
	var node: Node = item
	while node is CanvasItem:
		var canvas: CanvasItem = node as CanvasItem
		z += canvas.z_index
		if not canvas.z_as_relative:
			break
		node = node.get_parent()
	return z


## The Sprite2D nodes under `root` that draw at `WorldSort.Z_SORT`.
static func sprites(root: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var at: Node = stack.pop_back()
		var sprite: Sprite2D = at as Sprite2D
		if sprite != null and resolved_z(sprite) == WorldSort.Z_SORT:
			found.append(sprite)
		stack.append_array(at.get_children())
	return found


## The distinct textures of those sprites.
static func textures(root: Node) -> Array[Texture2D]:
	var found: Array[Texture2D] = []
	for sprite: Sprite2D in sprites(root):
		if sprite.texture != null and not found.has(sprite.texture):
			found.append(sprite.texture)
	return found
