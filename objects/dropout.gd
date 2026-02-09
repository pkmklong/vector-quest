extends Area2D
class_name Dropout

signal player_killed

@export var radius: float = 35.0:
	set(value):
		radius = value
		_update_visuals()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var event_horizon: Polygon2D = $EventHorizon
@onready var accretion_disk: Polygon2D = $AccretionDisk
@onready var outer_glow: Polygon2D = $OuterGlow
@onready var core: Polygon2D = $Core

var rotation_speed := 2.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_visuals()

func _process(delta: float) -> void:
	# Rotate the accretion disk
	if accretion_disk:
		accretion_disk.rotation += rotation_speed * delta
	
	# Pulse the outer glow
	var time := Time.get_ticks_msec() / 1000.0
	var pulse := sin(time * 3.0) * 0.15 + 0.85
	if outer_glow:
		outer_glow.scale = Vector2(pulse, pulse)
	
	# Slight core flicker
	if core:
		var flicker := randf_range(0.8, 1.0)
		core.modulate.a = flicker

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.has_method("die"):
		# Don't kill if player hasn't started or has completed the level
		if "has_started" in body and not body.has_started:
			return
		if "level_complete" in body and body.level_complete:
			return
		# Pull effect before death
		_play_death_effect(body)

func _play_death_effect(player: CharacterBody2D) -> void:
	# Quick pull toward center then kill
	var tween := create_tween()
	tween.tween_property(player, "global_position", global_position, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): 
		player.die()
		player_killed.emit()
	)

func _update_visuals() -> void:
	if not is_inside_tree():
		await ready
	
	if collision_shape and collision_shape.shape:
		collision_shape.shape.radius = radius
	
	# Create visual layers
	if outer_glow:
		outer_glow.polygon = _create_circle(radius * 2.0, 24)
		outer_glow.color = Color(0.4, 0.1, 0.5, 0.15)
	
	if accretion_disk:
		accretion_disk.polygon = _create_ring(radius * 1.4, radius * 0.9, 32)
		accretion_disk.color = Color(0.6, 0.2, 0.8, 0.4)
	
	if event_horizon:
		event_horizon.polygon = _create_circle(radius * 0.85, 20)
		event_horizon.color = Color(0.1, 0.0, 0.15, 0.9)
	
	if core:
		core.polygon = _create_circle(radius * 0.3, 12)
		core.color = Color(0.0, 0.0, 0.0, 1.0)

func _create_circle(r: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return points

func _create_ring(outer_r: float, inner_r: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	# Outer edge
	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle) * outer_r, sin(angle) * outer_r))
	# Inner edge (reverse)
	for i in range(segments, -1, -1):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle) * inner_r, sin(angle) * inner_r))
	return points
