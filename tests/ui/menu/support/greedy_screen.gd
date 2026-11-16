extends MenuScreen
## A menu screen that uses the back request itself (test double for test_menu_stack.gd).

var asked: int = 0


func on_back() -> bool:
	asked += 1
	return true
