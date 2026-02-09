extends Area2D
class_name BatchNorm

signal checkpoint_activated

@export var zone_width: float = 80.0:
	set(value):
		zone_width = value
		if is_inside_tree():
			_setup_visuals()

@export var zone_height: float = 200.0:
	set(value):
		zone_height = value
		if is_inside_tree():
			_setup_visuals()

var is_active := false
var player_inside := false

@onready var background: ColorRect = $Background
@onready var glow_outer: ColorRect = $GlowOuter
@onready var glow_inner: ColorRect = $GlowInner
@onready var label: Label = $Label
@onready var particles: Node2D = $Particles
@onready var collision: CollisionShape2D = $CollisionShape2D

const TEAL := Color(0.2, 0.8, 0.9, 1.0)
const TEAL_GLOW := Color(0.2, 0.8, 0.9, 0.3)
const TEAL_DIM := Color(0.15, 0.5, 0.6, 0.6)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_setup_visuals()
	_create_particles()

func _setup_visuals() -> void:
	# Set up collision shape
	var shape := RectangleShape2D.new()
	shape.size = Vector2(zone_width, zone_height)
	collision.shape = shape
	
	# Background
	background.size = Vector2(zone_width, zone_height)
	background.position = Vector2(-zone_width / 2, -zone_height / 2)
	background.color = Color(0.1, 0.2, 0.25, 0.4)
	
	# Outer glow
	glow_outer.size = Vector2(zone_width + 30, zone_height + 30)
	glow_outer.position = Vector2(-zone_width / 2 - 15, -zone_height / 2 - 15)
	glow_outer.color = Color(0.2, 0.7, 0.8, 0.15)
	
	# Inner glow
	glow_inner.size = Vector2(zone_width + 10, zone_height + 10)
	glow_inner.position = Vector2(-zone_width / 2 - 5, -zone_height / 2 - 5)
	glow_inner.color = Color(0.3, 0.8, 0.9, 0.2)
	
	# Label with math annotation - above the zone, staggered from ReLU
	label.text = "BatchNorm: (x-μ)/σ"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-zone_width / 2 - 50, -zone_height / 2 - 55)
	label.size = Vector2(180, 30)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", TEAL)

func _process(delta: float) -> void:
	# Gentle pulsing glow
	var pulse := sin(Time.get_ticks_msec() / 800.0) * 0.5 + 0.5
	glow_outer.color.a = lerpf(0.1, 0.25, pulse)
	glow_inner.color.a = lerpf(0.15, 0.3, pulse)
	
	# Animate particles
	_animate_particles(delta)

func _animate_particles(delta: float) -> void:
	for particle in particles.get_children():
		particle.position.y -= 30 * delta
		particle.modulate.a -= 0.3 * delta
		
		# Reset particle when it fades or exits zone
		if particle.modulate.a <= 0 or particle.position.y < -zone_height / 2:
			particle.position.y = zone_height / 2 - randf() * 20
			particle.position.x = randf_range(-zone_width / 2 + 5, zone_width / 2 - 5)
			particle.modulate.a = randf_range(0.3, 0.7)

func _on_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return
	
	var player := body as CharacterBody2D
	player_inside = true
	
	# Activate checkpoint
	if not is_active:
		_activate_checkpoint(player)
	
	# Always normalize when entering
	_normalize_player(player)

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		player_inside = false

func _activate_checkpoint(player: CharacterBody2D) -> void:
	is_active = true
	checkpoint_activated.emit()
	
	# Update spawn point
	if player.has_method("set_spawn_point"):
		player.set_spawn_point(global_position)
	
	# Visual feedback - checkpoint activated
	var tween := create_tween()
	tween.tween_property(label, "modulate", Color(1, 1, 1, 1), 0.2)
	tween.tween_property(label, "modulate", TEAL, 0.3)
	
	# Flash the zone
	background.color = TEAL_GLOW
	tween.parallel().tween_property(background, "color", Color(0.1, 0.2, 0.25, 0.4), 0.5)

func _normalize_player(player: CharacterBody2D) -> void:
	# Restore magnitude
	if "magnitude" in player:
		var old_mag: float = player.magnitude
		player.magnitude = 1.0
		
		# Only play stabilizing animation if magnitude was low
		if old_mag < 0.8:
			_play_stabilize_animation(player)
	
	# Reset velocity (gentle stop)
	var tween := create_tween()
	tween.tween_property(player, "velocity", Vector2.ZERO, 0.15).set_ease(Tween.EASE_OUT)
	
	# Reset external velocity if present
	if "external_velocity" in player:
		player.external_velocity = Vector2.ZERO

func _play_stabilize_animation(player: CharacterBody2D) -> void:
	# Create expanding ring effect
	var ring := ColorRect.new()
	ring.size = Vector2(20, 20)
	ring.position = player.global_position - Vector2(10, 10)
	ring.color = TEAL
	ring.z_index = 10
	get_tree().current_scene.add_child(ring)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "size", Vector2(150, 150), 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "position", player.global_position - Vector2(75, 75), 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "color:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)
	
	# Flash the label
	label.modulate = Color(1, 1, 1, 1)
	var label_tween := create_tween()
	label_tween.tween_property(label, "modulate", TEAL, 0.3)

func _create_particles() -> void:
	# Create floating particles inside the zone
	for i in range(8):
		var particle := ColorRect.new()
		particle.size = Vector2(4, 4)
		particle.position = Vector2(
			randf_range(-zone_width / 2 + 5, zone_width / 2 - 5),
			randf_range(-zone_height / 2, zone_height / 2)
		)
		particle.color = TEAL
		particle.modulate.a = randf_range(0.3, 0.7)
		particles.add_child(particle)
