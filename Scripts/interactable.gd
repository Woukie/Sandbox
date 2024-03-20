extends Node3D

class_name interactable

@export_category("Interactable Settings")
@export var DRAGGABLE := false			# Whether the object can be dragged
@export var HOLDABLE := false			# Whether the object can be held like an item
@export var NAME := ""					# The name shown when hovering over the object
@export var DRAG_HOVER_DISTANCE := 0.1	# distance to hover the object above the ground when dragging
@export var ALIGNED_OFFSET := Vector3.FORWARD
@export var ALIGNED_ROTATION := Vector3.ZERO

@export var INTERACTIONS: Array[Interaction] = []
@export var HELD_INTERACTIONS: Array[Interaction] = []

@onready var JOINT = $Joint	
@onready var HOVER_ZONE = $HoverZone

func on_interact(interaction: Interaction):
	pass

func on_held_interact(interaction: Interaction):
	pass
