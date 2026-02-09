extends CharacterBody2D

signal magnitude_changed(new_value: float)
signal died
signal respawned

@export var speed: float = 400.0
@export var acceleration: float = 2400.0
@export var deceleration: float = 3200.0

var magnitude: float = 1.0:
	set(value):
		magnitude = clamp(value, -1.0, 1.0)  # Can go negative (ReLU clips it), saturates at 1
		magnitude_changed.emit(magnitude)
		_update_color()

var spawn_position: Vector2
var is_dead: bool = false
var gradient_active: bool = false  # Controls vanishing gradient drain - starts inactive
var has_started: bool = false  # True once player passes through START
var level_complete: bool = false  # True once player completes the NN - stops all effects

## Activation threshold - gradient activates when player passes this x position
var gradient_activation_x: float = 0.0  # Set by level (first hidden layer x position)

## Start gate - player must pass through the input layer to start
var start_x: float = 0.0  # X position of input layer
var start_y_min: float = 0.0  # Top of input layer (lowest y value)
var start_y_max: float = 0.0  # Bottom of input layer (highest y value)
var _prev_x: float = 0.0  # Track previous x for crossing detection

## Exploding Gradient (out of bounds)
var network_bounds: Rect2 = Rect2()  # Set by level
var out_of_bounds: bool = false
var exploding_gradient_timer: float = 0.0
const EXPLODING_GRADIENT_TIME: float = 1.0

@onready var visuals: Node2D = $Visuals
@onready var glow_outer: Polygon2D = $Visuals/GlowOuter
@onready var glow_mid: Polygon2D = $Visuals/GlowMid
@onready var triangle: Polygon2D = $Visuals/Triangle
@onready var triangle_core: Polygon2D = $Visuals/TriangleCore
@onready var trail: Line2D = $Trail
@onready var trail_glow: Line2D = $TrailGlow
@onready var magnitude_bar: Node2D = $MagnitudeBar
@onready var magnitude_fill: ColorRect = $MagnitudeBar/Fill

var trail_points: Array[Vector2] = []
const MAX_TRAIL_POINTS := 40
const TRAIL_POINT_DISTANCE := 8.0  # Minimum distance between trail points

# External forces (from weights, etc.) - stored separately so input doesn't cancel them
var external_velocity: Vector2 = Vector2.ZERO
const EXTERNAL_FRICTION := 0.92  # How quickly external forces decay

func _ready() -> void:
	spawn_position = global_position
	_prev_x = global_position.x  # Initialize for crossing detection
	_update_color()
	_update_gradient_visuals()  # Start fainter until player passes through START
	# Show small magnitude bar above cursor
	if magnitude_bar:
		magnitude_bar.visible = true
		magnitude_bar.scale = Vector2(0.8, 0.6)  # Make it smaller

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	var input_dir := Vector2.ZERO
	
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	
	# Check if player has CROSSED through the input layer (START gate)
	# Must cross from left to right of start_x WHILE within vertical bounds
	if not has_started and start_x != 0.0:
		var crossing_start := _prev_x < start_x and global_position.x >= start_x
		var within_y_bounds := global_position.y >= start_y_min and global_position.y <= start_y_max
		if crossing_start and within_y_bounds:
			has_started = true
			gradient_active = true  # Activate exploding gradient when game starts
			_update_gradient_visuals()  # Update to full brightness when started
	
	# Track previous x position for next frame
	_prev_x = global_position.x
	
	var target_velocity := input_dir * speed
	
	# Calculate input-based velocity
	var input_velocity := velocity - external_velocity
	if input_dir.length() > 0:
		input_velocity = input_velocity.move_toward(target_velocity, acceleration * delta)
	else:
		input_velocity = input_velocity.move_toward(Vector2.ZERO, deceleration * delta)
	
	# Decay external velocity over time (friction)
	external_velocity *= EXTERNAL_FRICTION
	if external_velocity.length() < 1.0:
		external_velocity = Vector2.ZERO
	
	# Combine input velocity with external forces
	velocity = input_velocity + external_velocity
	
	# Rotate visuals to face movement direction (not the whole player)
	if velocity.length() > 10:
		var target_rotation := velocity.angle() + PI / 2
		visuals.rotation = lerp_angle(visuals.rotation, target_rotation, 15.0 * delta)
	
	move_and_slide()
	_update_trail()
	_update_magnitude_bar_position()
	_apply_vanishing_gradient(delta)
	_check_exploding_gradient(delta)

# Called by weights and other force fields to push the player
func apply_force(force: Vector2) -> void:
	external_velocity += force

func _update_trail() -> void:
	# Only add point if we've moved enough distance from last point
	if velocity.length() > 10:
		var should_add := trail_points.is_empty()
		if not should_add:
			var dist := global_position.distance_to(trail_points[0])
			should_add = dist >= TRAIL_POINT_DISTANCE
		
		if should_add:
			trail_points.insert(0, global_position)
			if trail_points.size() > MAX_TRAIL_POINTS:
				trail_points.pop_back()
	elif trail_points.size() > 0:
		# Fade out trail when stopped
		trail_points.pop_back()
	
	# Build trail with the player position at front for seamless connection
	var display_points: PackedVector2Array = []
	display_points.append(global_position)  # Always connect to current position
	for pt in trail_points:
		display_points.append(pt)
	
	# Trail is top_level at origin, so global positions work directly
	trail.global_position = Vector2.ZERO
	trail.points = display_points
	
	# Glow trail (wider, behind main trail)
	trail_glow.global_position = Vector2.ZERO
	trail_glow.points = display_points

func _update_magnitude_bar_position() -> void:
	# Keep magnitude bar above player (it's top_level so needs manual positioning)
	magnitude_bar.global_position = global_position + Vector2(0, -45)

func _apply_vanishing_gradient(_delta: float) -> void:
	# Auto-drain removed - activation only affected by NN elements (weights, ReLU, etc.)
	# Just update visuals based on current magnitude
	_update_gradient_visuals()

func _check_exploding_gradient(delta: float) -> void:
	# Don't check exploding gradient if level is complete or gradient not active
	if level_complete or not gradient_active:
		out_of_bounds = false
		exploding_gradient_timer = 0.0
		return
	
	# Check if player is outside network bounds
	if network_bounds.size != Vector2.ZERO:
		var was_out := out_of_bounds
		out_of_bounds = not network_bounds.has_point(global_position)
		
		if out_of_bounds:
			exploding_gradient_timer += delta
			
			# Drain activation while out of bounds (exploding gradient penalty)
			magnitude -= 0.3 * delta  # Lose 0.3 activation per second
			
			# Update visuals - player glows brighter/redder as timer increases
			var urgency: float = exploding_gradient_timer / EXPLODING_GRADIENT_TIME
			var pulse := sin(Time.get_ticks_msec() / (150.0 - urgency * 100.0)) * 0.3 + 0.7
			var red_tint := Color(1.0, 1.0 - urgency * 0.7, 1.0 - urgency * 0.8, 1.0)
			visuals.modulate = red_tint * pulse
			
			# Explode if timer runs out
			if exploding_gradient_timer >= EXPLODING_GRADIENT_TIME:
				_explode()
		else:
			# Back in bounds - reset timer and visuals
			if was_out:
				exploding_gradient_timer = 0.0
				_update_gradient_visuals()

func _explode() -> void:
	if is_dead:
		return
	
	is_dead = true
	velocity = Vector2.ZERO
	external_velocity = Vector2.ZERO
	died.emit()
	
	# Show "Exploding Gradient" text
	var explode_label := Label.new()
	explode_label.text = "Exploding Gradient"
	explode_label.add_theme_font_size_override("font_size", 20)
	explode_label.add_theme_color_override("font_color", Color(1, 0.4, 0.2, 1))
	explode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explode_label.position = global_position + Vector2(-80, -80)
	explode_label.z_index = 100
	get_tree().current_scene.add_child(explode_label)
	
	# Animate the label - float up and fade
	var label_tween := create_tween()
	label_tween.set_parallel(true)
	label_tween.tween_property(explode_label, "position:y", explode_label.position.y - 50, 0.8)
	label_tween.tween_property(explode_label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	label_tween.chain().tween_callback(explode_label.queue_free)
	
	# Explosion animation - flash bright, expand, then fade
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Flash white/red
	visuals.modulate = Color(1, 0.5, 0.3, 1)
	
	# Expand rapidly then fade
	tween.tween_property(visuals, "scale", Vector2(3.0, 3.0), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "modulate", Color(1, 0.2, 0.1, 0.0), 0.3)
	
	# Respawn after explosion
	tween.chain().tween_callback(respawn)

func set_network_bounds(bounds: Rect2) -> void:
	network_bounds = bounds

func set_gradient_activation_x(x_pos: float) -> void:
	gradient_activation_x = x_pos

func complete_level() -> void:
	# Mark level as complete - NN stops affecting player
	level_complete = true
	has_started = false  # Stop NN effects (weights, ReLU, etc.)
	# Disable exploding gradient when level is complete
	gradient_active = false
	out_of_bounds = false
	exploding_gradient_timer = 0.0
	magnitude = 1.0
	# Reset visuals to normal (full brightness despite has_started=false)
	visuals.modulate = Color(1, 1, 1, 1)
	_update_gradient_visuals()

func _update_gradient_visuals() -> void:
	# Make player fainter when not started (visual cue that game hasn't begun)
	# But keep full brightness if level is complete
	var base_alpha := 1.0
	if not has_started and not level_complete:
		base_alpha = 0.5  # Fainter when not started
	
	# Make player more transparent as magnitude drops (only when started)
	var mag_alpha := 0.4 + (magnitude * 0.6)  # Range: 0.4 to 1.0
	var alpha := base_alpha * mag_alpha
	visuals.modulate.a = alpha
	
	# Trail also fades
	if trail:
		trail.modulate.a = alpha
	if trail_glow:
		trail_glow.modulate.a = alpha * 0.7

func _update_color() -> void:
	var color := _get_magnitude_color()
	var dim_color := Color(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.15)
	var mid_color := Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.3)
	var core_color := Color(
		lerpf(color.r, 1.0, 0.6),
		lerpf(color.g, 1.0, 0.6),
		lerpf(color.b, 1.0, 0.6),
		1.0
	)
	
	if glow_outer:
		glow_outer.modulate = dim_color
	if glow_mid:
		glow_mid.modulate = mid_color
	if triangle:
		triangle.color = color
	if triangle_core:
		triangle_core.color = core_color
	if magnitude_fill:
		magnitude_fill.color = color
		magnitude_fill.scale.x = magnitude

func _get_magnitude_color() -> Color:
	# Shift from red (negative) to dim cyan (0) to bright white-cyan (1)
	var t: float = (magnitude + 1.0) / 2.0  # Map [-1, 1] to [0, 1]
	var r: float = lerpf(0.8, 0.5, t) if magnitude < 0 else lerpf(0.1, 0.5, t)
	var g: float = lerpf(0.2, 1.0, t)
	var b: float = lerpf(0.2, 1.0, t)
	return Color(r, g, b, 1.0)

# Public methods for gameplay
func add_magnitude(amount: float) -> void:
	magnitude += amount

func take_damage(amount: float) -> void:
	magnitude -= amount

func die() -> void:
	if is_dead:
		return
	
	is_dead = true
	velocity = Vector2.ZERO
	external_velocity = Vector2.ZERO
	died.emit()
	
	# Death animation - flash red and shrink
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Flash red
	visuals.modulate = Color(1, 0.2, 0.2, 1)
	
	# Rapid shrink and spin
	tween.tween_property(visuals, "scale", Vector2(0.1, 0.1), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(visuals, "rotation", visuals.rotation + PI * 4, 0.3)
	tween.tween_property(visuals, "modulate:a", 0.0, 0.3)
	
	# Hide trails (but keep magnitude bar visible)
	trail.visible = false
	trail_glow.visible = false
	
	# Respawn after delay
	await tween.finished
	await get_tree().create_timer(0.3).timeout
	respawn()

func respawn() -> void:
	# Reset position
	global_position = spawn_position
	
	# Reset state
	velocity = Vector2.ZERO
	external_velocity = Vector2.ZERO
	trail_points.clear()
	magnitude = 1.0
	_prev_x = spawn_position.x  # Reset for crossing detection
	
	# Gradient will reactivate when player passes activation layer again
	gradient_active = false
	
	# Reset visuals
	visuals.scale = Vector2(1, 1)
	visuals.rotation = 0
	visuals.modulate = Color(1, 1, 1, 1)
	
	# Reset trail opacity
	if trail:
		trail.modulate.a = 1.0
	if trail_glow:
		trail_glow.modulate.a = 0.7
	
	# Show elements
	trail.visible = true
	trail_glow.visible = true
	magnitude_bar.visible = true
	
	# Spawn animation - fade in and grow
	visuals.scale = Vector2(0.1, 0.1)
	visuals.modulate.a = 0.0
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visuals, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(visuals, "modulate:a", 1.0, 0.3)
	
	await tween.finished
	is_dead = false
	respawned.emit()

func set_spawn_point(pos: Vector2) -> void:
	spawn_position = pos
