extends GdUnitTestSuite
## RestoreScreen (plan P515): a title, a progress bar that follows the Restorer and a Cancel button
## of at least 48 dp. With no resume file the start it asks for changes nothing.


func test_the_bar_follows_the_restorers_progress() -> void:
	var screen: RestoreScreen = auto_free(RestoreScreen.new())
	add_child(screen)
	await await_idle_frame()
	var restorer: Restorer = auto_free(Restorer.new())
	screen._on_started(restorer)
	restorer.progressed.emit(5, 20)
	assert_float(screen._bar.max_value).is_equal(20.0)
	assert_float(screen._bar.value).is_equal(5.0)
	var buttons: Array[Button] = []
	for child: Node in screen.column.get_children():
		if child is Button:
			buttons.append(child as Button)
	assert_int(buttons.size()).is_equal(1)
	assert_str(buttons[0].text).is_equal(MainMenuText.ENGLISH[MainMenuText.RESTORE_CANCEL])
