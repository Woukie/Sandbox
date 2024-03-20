extends CharacterBody3D
## Credits:
# Special thanks to Majikayo Games for original solution to stair_step_down!
# (https://youtu.be/-WjM1uksPIk)
#
# Special thanks to Myria666 for their paper on Quake movement mechanics (used for stair_step_up)!
# (https://github.com/myria666/qMovementDoc)
#
# Special thanks to Andicraft for their help with implementation stair_step_up!
# (https://github.com/Andicraft)
#
# Woukie:
# I added some shit
# - Movement overhaul
# - Configurable height
# - Crouching
# - Sliding
# - Interaction system with a PID for dragging items

## Notes:
# 0. All shape colliders are supported. Although, I would recommend Capsule colliders for enemies
#		as it works better with the Navigation Meshes. Its up to you what shape you want to use
#		for players.
#
# 1. To adjust the step-up/down height, just change the MAX_STEP_UP/MAX_STEP_DOWN values below.
#
# 2. This uses Jolt Physics as the default Godot Physics has a few bugs:
#	1: Small gaps that you should be able to fit through both ways will block you in Godot Physics.
#		You can see this demonstrated with the floating boxes in front of the big stairs.
#	2: Walking into some objects may push the player downward by a small amount which causes
#		jittering and causes the floor to be detected as a step.
#	TLDR: This still works with default Godot Physics, although it feels a lot better in Jolt Physics.

#region ANNOTATIONS ################################################################################
@export_category("Movement Settings")
@export var PLAYER_SPEED := 7.0					# Player's movement speed.
@export var PLAYER_CROUCH_SPEED := 4.0			# Player's crouch speed.
@export var PLAYER_SPRINT_SPEED := 12.0			# Player's sprint speed.
@export var JUMP_VELOCITY := 6.0				# Player's jump velocity.
@export var CROUCH_BOOST := 2.0					# Velocity boost for crouching while sprinting.
@export var LAND_BOOST := 3.0						# Velocity boost when landing crouched and fast.
@export var LAND_BOOST_SPEED_REQUIREMENT := 5.0	# Velocity requirement for land boosting
@export var JUMP_BOOST := 1.3					# Velocity boost for jumping while sprinting.
@export var JUMP_COOLDOWN := 0.1				# Min time between jumps

@export_category("Size Settings")
@export var STANDING_HEIGHT := 2.0
@export var CROUCHING_HEIGHT := 1.0

@export_category("Step Settings")
@export var MAX_STEP_UP := 0.5					# Maximum height in meters the player can step up.
@export var MAX_STEP_DOWN := -0.5				# Maximum height in meters the player can step down.

@export_category("Camera Settings")
@export var MOUSE_SENSITIVITY := 0.4			# Mouse movement sensitivity.
@export var CAMERA_SMOOTHING := 75.0			# Amount of camera smoothing.

@export_category("Interaction Settings")
@export var HOVER_DISTANCE := 3.0				# How close you have to be to an interactable to hover over it
@export var INACTIVE_CROSSHAIR: Texture = null
@export var ACTIVE_CROSSHAIR: Texture = null
@export var GRAB_CROSSHAIR: Texture = null
@export_flags_3d_physics var HOVER_MASK := collision_mask # Layers used for hover collision

@export_category("Drag Settings")
@export var MAX_DRAG_DISTANCE := 3.0			# Furthest you can carry an item in front of you
@export var MIN_DRAG_DISTANCE := 1.0			# Closest you can carry an item in front of you
@export var DRAG_SCROLL_SENSITIVITY := 0.3		# How much to change holding distnace by per scroll
@export var DRAG_BREAK_DISTANCE := 3.0			# How far an item can be from the target position before it drops
@export var MAX_DRAG_FORCE := 30.0				# How much force the player can exert onto the interactable they wish to drag
@export var KP = 150.0  # Responsiveness (Proportional gain)
@export var KI = 0.0   # Steady-state accuracy (Integral gain)
@export var KD = 7.0   # Damping and oscillation reduction (Derivative gain)
@export_flags_3d_physics var DRAG_MASK := collision_mask # Layers used for dragging items

@export_category("Debug Settings")
@export var STEP_DOWN_DEBUG := false			# Enable these to get detailed info on the step down/up process.
@export var STEP_UP_DEBUG := false

## Node References
@onready var CAMERA_NECK = $CameraNeck
@onready var CAMERA_HEAD = $CameraNeck/CameraHead
@onready var CAMERA_PITCH = $CameraNeck/CameraHead/CameraPitch
@onready var PLAYER_CAMERA = $CameraNeck/CameraHead/CameraPitch/PlayerCamera
@onready var PLAYER_COLLISION = $PlayerCollision
@onready var TEXTURE_RECT = $Crosshair/Control/TextureRect
@onready var NAME = $Interactable/Name
@onready var INTERACTIONS = $Interactable/Interactions
@onready var LINE = $Line
@onready var BASE = $Base
@onready var STAND_CAST = $Base/StandCast

# Particles
@onready var PARTICLES_JUMP = $Base/Particles/Jump
@onready var PARTICLES_JUMP_BOOST = $Base/Particles/JumpBoost
@onready var PARTICLES_LAND = $Base/Particles/Land
@onready var PARTICLES_SPRINTING = $Base/Particles/Sprinting
@onready var PARTICLES_SLIDING = $Base/Particles/Sliding

#endregion

#region VARIABLES ##################################################################################
var is_grounded := true					# If player is grounded this frame
var was_grounded := true				# If player was grounded last frame
var is_crouching := false				# If player is crouching this frame
var was_crouching := false				# If the player was crouching last frame
var sprinting := false					# If player is sprinting this frame
var jumping := false					# If player is jumping this frame
var jumped_at := Time.get_unix_time_from_system() # Last time the player jumped in unix time (seconds)
var previous_velocity := Vector3.ZERO	# Stores the velocity of the previous frame
var old_velocity := Vector3.ZERO		# Stores the velocity of the frame before the previous

var wish_dir := Vector3.ZERO			# Player input (WASD) direction

var vertical := Vector3(0, 1, 0)		# Shortcut for converting vectors to vertical
var horizontal := Vector3(1, 0, 1)		# Shortcut for converting vectors to horizontal

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")		# Default Gravity

var hovering_over = null # Current interactable the player is looking and within range of
var dragging: RigidBody3D = null # The interactable the player is dragging
var holding: RigidBody3D = null # The interactable the player is holding
var grab_offset = Vector3.ZERO # Where on the interactible did you grab it

# Specifically for dragging
var integral: Vector3 = Vector3.ZERO  # Integral term accumulator
var previous_error: Vector3 = Vector3.ZERO  # Previous error
var drag_distance = 0

#endregion

#region IMPLEMENTATION #############################################################################
# Function: On scene load
func _ready():
	# Capture mouse on start
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Function: Handle defined inputs
func _input(event):
	# Handle ESC input
	if event.is_action_pressed("mouse_toggle"):
		_toggle_mouse_mode()

	# Handle Mouse input
	if event is InputEventMouseMotion and (Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED):
		_camera_input(event)

# Function: Handle camera input
func _camera_input(event):
	var y_rotation = deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY)
	rotate_y(y_rotation)
	CAMERA_HEAD.rotate_y(y_rotation)
	CAMERA_PITCH.rotate_x(deg_to_rad(-event.relative.y * MOUSE_SENSITIVITY))
	CAMERA_PITCH.rotation.x = clamp(CAMERA_PITCH.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	# Update held item to align with camera
	realign_holding()

# Function: Handle mouse mode toggling
func _toggle_mouse_mode():
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Function: Handle frame-based physics processes
func _physics_process(delta):
	# Update player state
	was_grounded = is_grounded
	
	is_grounded = is_on_floor()
	
	was_crouching = is_crouching
	
	# Get player inputs
	is_crouching = Input.is_action_pressed("move_crouch")
	
	sprinting = Input.is_action_pressed("move_sprint")
	
	jumping = Input.is_action_just_pressed("move_jump") and is_grounded and Time.get_unix_time_from_system() - jumped_at > JUMP_COOLDOWN
	
	# Get player input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Handle Gravity
	if !is_grounded:
		velocity.y -= gravity * delta
	
	# Handle Jump
	if jumping:
		jumped_at = Time.get_unix_time_from_system()
		PLAYER_CAMERA.multiplier_position = 0.1
		PLAYER_CAMERA.multiplier_rotation = 0.1
		PARTICLES_JUMP.restart()
		PARTICLES_JUMP.set_emitting(true)
		
		velocity.y = JUMP_VELOCITY
	
	# Handle WASD Movement
	
	# Calculate move speed
	var move_speed := PLAYER_SPRINT_SPEED if sprinting else PLAYER_SPEED
	move_speed = PLAYER_CROUCH_SPEED if is_crouching else move_speed
	
	# Apply and add smoothing
	var target_velocity := wish_dir * move_speed
	var slowing_down := velocity.length() > target_velocity.length()
	
	var antislip := 1.0
	
	PARTICLES_SPRINTING.emitting = false
	PARTICLES_SLIDING.emitting = false
	
	if is_grounded:
		antislip = 0.25 if slowing_down else 0.5
		
		if sprinting and !is_crouching and velocity.length() > PLAYER_SPEED:
			PARTICLES_SPRINTING.emitting = true
		
		# If we are going slower but not when we are going a desired pace already, 
		# Effectively loses control and preserves momentum when slide boosting
		if is_crouching and slowing_down and velocity.length() > move_speed:
			PARTICLES_SLIDING.amount_ratio = clamp((velocity.length() / PLAYER_CROUCH_SPEED) / 2.0 - 1.0, 0.0, 1.0)
			PARTICLES_SLIDING.emitting = true
			PLAYER_CAMERA.multiplier_position *= 1.03
			PLAYER_CAMERA.multiplier_rotation *= 1.03
			antislip = 0.05
	else:
		antislip = 0.05
	
	target_velocity = velocity.lerp(target_velocity, antislip)
	
	if sprinting and is_grounded :
		if is_crouching and !was_crouching:
			target_velocity *= CROUCH_BOOST
			PLAYER_CAMERA.multiplier_position = 1
			PLAYER_CAMERA.multiplier_rotation = 0.5
		if jumping and not is_crouching and velocity.length() > PLAYER_SPEED:
			PARTICLES_JUMP_BOOST.restart()
			PARTICLES_JUMP_BOOST.set_emitting(true)
			target_velocity *= JUMP_BOOST
			PLAYER_CAMERA.multiplier_position = 0.5
			PLAYER_CAMERA.multiplier_rotation = 0.25
	
	if is_grounded and !was_grounded:
		PARTICLES_LAND.restart()
		PARTICLES_LAND.amount_ratio = clamp(abs(old_velocity.y) / 50.0, 0.0, 1.0)
		PARTICLES_LAND.process_material.initial_velocity_max = clamp(abs(old_velocity.y) / 10.0, 0.0, 1.0) * 5
		
		if is_crouching and velocity.length() >= LAND_BOOST_SPEED_REQUIREMENT:
			PLAYER_CAMERA.multiplier_position = 1
			PLAYER_CAMERA.multiplier_rotation = 0.5
			target_velocity *= LAND_BOOST
		else:
			PLAYER_CAMERA.multiplier_position = clamp(pow(abs(old_velocity.y) / 20, 2) - 0.3, 0.0, 3.0)
			PLAYER_CAMERA.multiplier_rotation = clamp(pow(abs(old_velocity.y) / 20, 2) - 0.3, 0.0, 3.0)
		
		PARTICLES_LAND.set_emitting(true)
	
	velocity.x = target_velocity.x
	velocity.z = target_velocity.z
	
	var max_decay = 0.93
	var min_decay = 0.8
	
	PLAYER_CAMERA.multiplier_position *= clamp(lerp(min_decay, max_decay, velocity.length() / PLAYER_SPEED), 0, max_decay)
	PLAYER_CAMERA.multiplier_rotation *= clamp(lerp(min_decay, max_decay, velocity.length() / PLAYER_SPEED), 0, max_decay)
	
	# Stair step up
	stair_step_up()
	
	# Move
	move_and_slide()
	
	# Stair step down
	stair_step_down()
	
	# Crouch collision
	crouch()
	
	# Smooth Camera
	smooth_camera_jitter(delta)
	
	hover_interactables()
	
	drag()
	
	# Interacting with the world
	interact()
	
	realign_holding()
	
	old_velocity = previous_velocity
	previous_velocity = velocity

func realign_holding():
	if holding:
		holding.global_position = CAMERA_PITCH.to_global(holding.ALIGNED_OFFSET)
		holding.global_rotation_degrees = CAMERA_PITCH.global_rotation_degrees
		holding.rotate_object_local(Vector3.UP, holding.ALIGNED_ROTATION.y)

# dragging and holding
func interact():
	var interactions = ""
	var name = ""
	
	if hovering_over:
		interactions += "LMB: DRAG\n" if hovering_over.DRAGGABLE else ""
		interactions += "E: HOLD\n" if hovering_over.HOLDABLE and !holding else ""
		name = hovering_over.NAME
		
		# Extra interaction for hovering
		var extra_interactions: Array[Interaction] = hovering_over.INTERACTIONS
		for interaction in extra_interactions:
			interactions += InputMap.action_get_events(interaction.input)[0].as_text() + ": " + interaction.display_name + "\n"
			if Input.is_action_pressed(interaction.input):
				hovering_over.on_interact(interaction)
		
		# Begin dragging something
		if Input.is_action_pressed("interact_drag"):
			dragging = hovering_over
		
		# Begin holding something
		if !holding and Input.is_action_pressed("interact_hold"):
			holding = hovering_over
			
			add_collision_exception_with(holding)
			STAND_CAST.add_exception(holding)
			
			holding.freeze = true
	
	if holding:
		interactions += "Q: DROP\n" if holding else ""
		
		# Extra interaction for holding
		var extra_interactions: Array[Interaction] = holding.HELD_INTERACTIONS
		for interaction in extra_interactions:
			interactions += InputMap.action_get_events(interaction.input)[0].as_text() + ": " + interaction.display_name + "\n"
			if Input.is_action_pressed(interaction.input):
				holding.on_held_interact(interaction)
		
		if Input.is_action_pressed("interact_drop"):
			remove_collision_exception_with(holding)
			STAND_CAST.remove_exception(holding)
			
			holding.freeze = false
			holding = null
	
	if not Input.is_action_pressed("interact_drag"):
		dragging = null
	
	INTERACTIONS.text = interactions
	NAME.text = name

# Handle dragging interactables
func drag():
	if not dragging: 
		LINE.RENDERING = false
		return
	
	LINE.RENDERING = true
	
	if Input.is_action_just_pressed("drag_away"):
		drag_distance += DRAG_SCROLL_SENSITIVITY
	
	if Input.is_action_just_pressed("drag_closer"):
		drag_distance -= DRAG_SCROLL_SENSITIVITY
	
	drag_distance = clamp(drag_distance, MIN_DRAG_DISTANCE, MAX_DRAG_DISTANCE)
	
	var mouse_position = get_viewport().get_mouse_position()
	var from = PLAYER_CAMERA.project_ray_origin(mouse_position)
	# We prefer offset as we want target position to be influenced by surface normals, even if target is outside range
	var offset = PLAYER_CAMERA.project_ray_normal(mouse_position) * MAX_DRAG_DISTANCE * 2 # Arbitrarilly large, will later clamp
	
	var query = PhysicsRayQueryParameters3D.create(from, from + offset, HOVER_MASK, [self, dragging] if !holding else [self, dragging, holding])
	query.collide_with_areas = false
	
	var result = get_world_3d().direct_space_state.intersect_ray(query)

	if result.has("position"):
		offset = result.position + result.normal * dragging.DRAG_HOVER_DISTANCE - from
	
	offset = offset.limit_length(drag_distance)
	
	var target_position = from + offset
	var current_position = dragging.to_global(grab_offset)
	
	# Apply dragging force
	
	var error = target_position - current_position
	
	if error.length() > DRAG_BREAK_DISTANCE:
		dragging = null
		LINE.snap()
		return
	
	var delta = get_process_delta_time()
	
	integral += error * delta  # delta is the time step since last update
	var derivative = (error - previous_error) / delta
	
	var required_force = KP * error + (KI * integral).limit_length(3.0) + KD * derivative
	
	previous_error = error
	
	required_force *= dragging.get_mass()
	
	required_force += dragging.get_mass() * gravity * Vector3.UP
	
	required_force = required_force.limit_length(MAX_DRAG_FORCE)
	
	dragging.apply_force(required_force, dragging.center_of_mass + dragging.to_global(grab_offset) - dragging.position)
	
	LINE.START = current_position
	LINE.END = target_position

# Handle hovering over interactables
func hover_interactables():
	hovering_over = null
	if dragging: 
		TEXTURE_RECT.texture = GRAB_CROSSHAIR
	else:
		var mouse_position = get_viewport().get_mouse_position()
		var from = PLAYER_CAMERA.project_ray_origin(mouse_position)
		var to = from + PLAYER_CAMERA.project_ray_normal(mouse_position) * HOVER_DISTANCE
		
		var query = PhysicsRayQueryParameters3D.create(from, to, HOVER_MASK, [self, holding] if holding else [self])
		
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		
		if result.has("collider"):
			var parent = result.collider
			if parent is interactable:
				grab_offset = parent.to_local(result.position)
				drag_distance = clamp(PLAYER_CAMERA.to_local(result.position).length(), MIN_DRAG_DISTANCE, MAX_DRAG_DISTANCE)
				hovering_over = parent
		TEXTURE_RECT.texture = ACTIVE_CROSSHAIR if hovering_over else INACTIVE_CROSSHAIR

# Handle crouching
func crouch():
	var target_height := STANDING_HEIGHT if not is_crouching else CROUCHING_HEIGHT
	var current_height = PLAYER_COLLISION.shape.get_height()
	
	STAND_CAST.target_position = Vector3.UP * current_height
	
	if target_height > current_height and STAND_CAST.is_colliding():
		return
	
	PLAYER_COLLISION.shape.set_height(current_height + (target_height - current_height) * 0.2)
	PLAYER_COLLISION.position = Vector3(0.0, (STANDING_HEIGHT - current_height) / 2, 0.0);
	
	var stand_progress = current_height - CROUCHING_HEIGHT / (STANDING_HEIGHT - CROUCHING_HEIGHT)
	
	BASE.position.y = (-PLAYER_COLLISION.shape.get_height() / 2) * stand_progress

# Function: Handle walking down stairs
func stair_step_down():
	if is_grounded:
		return

	# If we're falling from a step
	if velocity.y <= 0 and was_grounded:
		_debug_stair_step_down("SSD_ENTER", null)													## DEBUG

		# Initialize body test variables
		var body_test_result = PhysicsTestMotionResult3D.new()
		var body_test_params = PhysicsTestMotionParameters3D.new()

		body_test_params.from = self.global_transform			## We get the player's current global_transform
		body_test_params.motion = Vector3(0, MAX_STEP_DOWN, 0)	## We project the player downward

		if PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
			# Enters if a collision is detected by body_test_motion
			# Get distance to step and move player downward by that much
			position.y += body_test_result.get_travel().y
			apply_floor_snap()
			is_grounded = true
			_debug_stair_step_down("SSD_APPLIED", body_test_result.get_travel().y)					## DEBUG

# Function: Handle walking up stairs
func stair_step_up():
	if wish_dir == Vector3.ZERO:
		return

	_debug_stair_step_up("SSU_ENTER", null)															## DEBUG

	# 0. Initialize testing variables
	var body_test_params = PhysicsTestMotionParameters3D.new()
	var body_test_result = PhysicsTestMotionResult3D.new()

	var test_transform = global_transform				## Storing current global_transform for testing
	var distance = wish_dir * 0.1						## Distance forward we want to check
	body_test_params.from = self.global_transform		## Self as origin point
	body_test_params.motion = distance					## Go forward by current distance

	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# Pre-check: Are we colliding?
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		_debug_stair_step_up("SSU_EXIT_1", null)													## DEBUG

		## If we don't collide, return
		return

	# 1. Move test_transform to collision location
	var remainder = body_test_result.get_remainder()							## Get remainder from collision
	test_transform = test_transform.translated(body_test_result.get_travel())	## Move test_transform by distance traveled before collision

	_debug_stair_step_up("SSU_REMAINING", remainder)												## DEBUG
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 2. Move test_transform up to ceiling (if any)
	var step_up = MAX_STEP_UP * vertical
	body_test_params.from = test_transform
	body_test_params.motion = step_up
	PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
	test_transform = test_transform.translated(body_test_result.get_travel())

	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 3. Move test_transform forward by remaining distance
	body_test_params.from = test_transform
	body_test_params.motion = remainder
	PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
	test_transform = test_transform.translated(body_test_result.get_travel())

	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 3.5 Project remaining along wall normal (if any)
	## So you can walk into wall and up a step
	if body_test_result.get_collision_count() != 0:
		remainder = body_test_result.get_remainder().length()

		### Uh, there may be a better way to calculate this in Godot.
		var wall_normal = body_test_result.get_collision_normal()
		var dot_div_mag = wish_dir.dot(wall_normal) / (wall_normal * wall_normal).length()
		var projected_vector = (wish_dir - dot_div_mag * wall_normal).normalized()

		body_test_params.from = test_transform
		body_test_params.motion = remainder * projected_vector
		PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
		test_transform = test_transform.translated(body_test_result.get_travel())

		_debug_stair_step_up("SSU_TEST_POS", test_transform)										## DEBUG

	# 4. Move test_transform down onto step
	body_test_params.from = test_transform
	body_test_params.motion = MAX_STEP_UP * -vertical

	# Return if no collision
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		_debug_stair_step_up("SSU_EXIT_2", null)													## DEBUG

		return

	test_transform = test_transform.translated(body_test_result.get_travel())
	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 5. Check floor normal for un-walkable slope
	var surface_normal = body_test_result.get_collision_normal()
	var temp_floor_max_angle = floor_max_angle + deg_to_rad(20)
	if (snappedf(surface_normal.angle_to(vertical), 0.001) > temp_floor_max_angle):
		_debug_stair_step_up("SSU_EXIT_3", null)													## DEBUG

		return

	_debug_stair_step_up("SSU_TEST_POS", test_transform)											## DEBUG

	# 6. Move player up
	var global_pos = global_position
	var step_up_dist = test_transform.origin.y - global_pos.y
	_debug_stair_step_up("SSU_APPLIED", step_up_dist)												## DEBUG

	global_pos.y = test_transform.origin.y
	global_position = global_pos

# Function: Smooth camera jitter
func smooth_camera_jitter(delta):
	CAMERA_HEAD.global_position.x = CAMERA_NECK.global_position.x
	CAMERA_HEAD.global_position.y = lerpf(CAMERA_HEAD.global_position.y, CAMERA_NECK.global_position.y, CAMERA_SMOOTHING * delta)
	CAMERA_HEAD.global_position.z = CAMERA_NECK.global_position.z

	# Limit how far camera can lag behind its desired position
	CAMERA_HEAD.global_position.y = clampf(CAMERA_HEAD.global_position.y,
										-CAMERA_NECK.global_position.y - 1,
										CAMERA_NECK.global_position.y + 1)

## Debugging #######################################################################################

# Debug: Stair Step Down
func _debug_stair_step_down(param, value):
	if STEP_DOWN_DEBUG == false:
		return

	match param:
		"SSD_ENTER":
			print()
			print("Stair step down entered")
		"SSD_APPLIED":
			print("Stair step down applied, travel = ", value)

# Debug: Stair Step Up
func _debug_stair_step_up(param, value):
	if STEP_UP_DEBUG == false:
		return

	match param:
		"SSU_ENTER":
			print()
			print("SSU: Stair step up entered")
		"SSU_EXIT_1":
			print("SSU: Exited with no collisions")
		"SSU_TEST_POS":
			print("SSU: test_transform current position = ", value)
		"SSU_REMAINING":
			print("SSU: Remaining distance = ", value)
		"SSU_EXIT_2":
			print("SSU: Exited due to no step collision")
		"SSU_EXIT_3":
			print("SSU: Exited due to non-floor stepping")
		"SSU_APPLIED":
			print("SSU: Player moved up by ", value, " units")
