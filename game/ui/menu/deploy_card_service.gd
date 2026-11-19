extends Node
## The autoload that installs the deploy card (plan P536): it builds one `DeployCard` on the root
## and hands it `MenuFlow`, so `MenuFlow` itself is not edited. No class_name (an autoload; see
## tests/project/test_autoloads.gd), listed after MenuFlow.

var card: DeployCard = null


func _ready() -> void:
	card = DeployCard.new()
	card.name = &"DeployCard"
	add_child(card)
	card.attach(MenuFlow)
