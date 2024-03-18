extends Node3D

class_name interactable

@export_category("Interactable Settings")
@export var DRAGGABLE := false			# Whether the object can be dragged
@export var HOLDABLE := false			# Whether the object can be held like an item
@export var NAME := ""					# The name shown when hovering over the object
@export var DRAG_HOVER_DISTANCE := 0.1	# distance to hover the object above the ground when dragging

@onready var JOINT = $Joint
@onready var HOVER_ZONE = $HoverZone
