extends Area2D
class_name ReluGate

## ReLU Gate - Implements real ReLU function: max(0, x)
## If player's momentum is negative, it gets clipped to zero

signal momentum_clipped

@export var radius: float = 35.0:
	set(value):
		radius = value
		_update_visuals()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var glow_ring: Polygon2D = $GlowRing
@onready var inner_glow: Polygon2D = $InnerGlow
@onready var symbol: Label = $Symbol
@onready var flash_timer: Timer = $FlashTimer

# Consistent blue/purple color for all ReLU gates
var base_color := Color(0.4, 0.5, 0.9, 0.5)
var glow_color := Color(0.3, 0.4, 0.8, 0.2)
var is_flashing := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	flash_timer.timeout.connect(_on_flash_timeout)
	_update_visuals()
	_setup_colors()

func _on_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	
	var player := body as CharacterBody2D
	
	# Only affect players who have started the game and haven't completed
	if not ("has_started" in player and player.has_started):
		return
	if "level_complete" in player and player.level_complete:
		return
	
	# Real ReLU: max(0, x) - clip negative values to zero
	if "magnitude" in player:
		if player.magnitude < 0:
			_clip_momentum(player)
		else:
			_pass_through(player)

func _clip_momentum(player: CharacterBody2D) -> void:
	# Store the negative value for visual feedback
	var clipped_amount: float = player.magnitude
	
	# Clip to zero (ReLU behavior)
	player.magnitude = 0.0
	
	# Visual feedback - flash orange/red to show clipping
	is_flashing = true
	inner_glow.color = Color(1.0, 0.4, 0.1, 0.9)
	glow_ring.color = Color(1.0, 0.3, 0.1, 0.6)
	
	# Show "CLIPPED" indicator
	_show_clipped_indicator(clipped_amount)
	
	# Emit signal
	momentum_clipped.emit()
	
	flash_timer.start(0.4)

func _pass_through(player: CharacterBody2D) -> void:
	# Positive momentum - pass through unchanged
	# Brief green flash to show safe passage
	is_flashing = true
	inner_glow.color = Color(0.3, 0.9, 0.5, 0.7)
	glow_ring.color = Color(0.2, 0.8, 0.4, 0.4)
	
	flash_timer.start(0.2)

func _show_clipped_indicator(clipped_value: float) -> void:
	# Create floating "CLIPPED" text
	var clip_label := Label.new()
	clip_label.text = "CLIPPED"
	clip_label.add_theme_font_size_override("font_size", 14)
	clip_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2, 1.0))
	clip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clip_label.position = global_position + Vector2(-30, -50)
	clip_label.z_index = 50
	get_tree().current_scene.add_child(clip_label)
	
	# Animate - float up and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(clip_label, "position:y", clip_label.position.y - 30, 0.6)
	tween.tween_property(clip_label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.chain().tween_callback(clip_label.queue_free)
	
	# Create particle effect - small squares flying off
	_create_clip_particles()

func _create_clip_particles() -> void:
	for i in range(5):
		var particle := ColorRect.new()
		particle.size = Vector2(4, 4)
		particle.color = Color(1.0, 0.3, 0.1, 0.9)
		particle.position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		particle.z_index = 45
		get_tree().current_scene.add_child(particle)
		
		# Animate particles flying outward and fading
		var angle := randf() * TAU
		var distance := randf_range(30, 60)
		var target_pos := particle.position + Vector2(cos(angle), sin(angle)) * distance
		
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", target_pos, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "modulate:a", 0.0, 0.4)
		tween.tween_property(particle, "size", Vector2(1, 1), 0.4)
		tween.chain().tween_callback(particle.queue_free)

func _on_flash_timeout() -> void:
	is_flashing = false
	_setup_colors()

func _setup_colors() -> void:
	if not is_inside_tree():
		return
	
	# All ReLU gates have the same blue/purple color
	base_color = Color(0.4, 0.5, 0.9, 0.5)
	glow_color = Color(0.3, 0.4, 0.8, 0.2)
	
	if inner_glow:
		inner_glow.color = base_color
	if glow_ring:
		glow_ring.color = glow_color
	if symbol:
		symbol.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0, 0.9))

func _update_visuals() -> void:
	if not is_inside_tree():
		await ready
	
	# Update collision shape (circle)
	if collision_shape:
		var shape := CircleShape2D.new()
		shape.radius = radius
		collision_shape.shape = shape
	
	# Create ring polygon
	var ring_points := _create_circle_points(radius + 8, 16)
	var inner_points := _create_circle_points(radius - 5, 16)
	
	if glow_ring:
		glow_ring.polygon = ring_points
	if inner_glow:
		inner_glow.polygon = inner_points

func _create_circle_points(r: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return points

func _process(_delta: float) -> void:
	# Subtle pulse animation
	if not is_flashing:
		var pulse := sin(Time.get_ticks_msec() / 600.0) * 0.15 + 0.85
		if inner_glow:
			inner_glow.color = Color(base_color.r, base_color.g, base_color.b, base_color.a * pulse)
		if glow_ring:
			glow_ring.color = Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * pulse)
