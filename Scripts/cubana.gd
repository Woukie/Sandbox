extends interactable

@onready var PARTICLES = $GPUParticles3D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func on_interact(interaction: Interaction):
	PARTICLES.restart()
	PARTICLES.set_emitting(true)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
