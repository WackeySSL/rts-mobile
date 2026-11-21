extends ResultScreen
## A result screen whose buttons lack their `DpMinSize` (a test double for the null guard).


func add_button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = super(parent, text, action)
	for floor_dp: Node in button.find_children("*", "DpMinSize", false, false):
		button.remove_child(floor_dp)
		floor_dp.free()
	return button
