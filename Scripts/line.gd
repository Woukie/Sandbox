extends Node3D

class_name line

@export var START := Vector3.ZERO
@export var END := Vector3.ZERO
@export var WIDTH := 0.3
@export var RENDERING := false

@onready var MESH = $Mesh
@onready var PARTICLES = $GPUParticles3D

func snap():
	PARTICLES.restart()
	PARTICLES.set_emitting(true)

func _process(delta):
	MESH.visible = RENDERING
	
	if !RENDERING: return
	
	global_position = START.lerp(END, 0.5)
	scale.z = (START - END).length()
	scale.x = WIDTH
	scale.y = WIDTH
	look_at(END, get_viewport().get_camera_3d().position - MESH.global_position)
