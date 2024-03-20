extends Resource
class_name Interaction

@export var input = ""
@export var display_name = ""

func _init(_input:= "interact_primary", _display_name:="Eat"):
	input = _input
	display_name = _display_name
