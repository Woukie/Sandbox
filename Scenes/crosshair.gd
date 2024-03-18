extends CanvasLayer

@export var INACTIVE_CROSSHAIR: Resource = null
@export var ACTIVE_CROSSHAIR: Resource = null

@onready var TEXTURE_RECT = $Control/TextureRect

signal set_crosshair_active(active: bool)  # Existing signal

func set_active(active: bool):
	TEXTURE_RECT.texture = ACTIVE_CROSSHAIR if active else INACTIVE_CROSSHAIR
