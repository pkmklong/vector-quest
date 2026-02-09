extends Area2D
class_name GoalZone

signal level_completed

@export var zone_size: Vector2 = Vector2(80, 200):
	set(value):
		zone_size = value
		_update_visuals()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var background: ColorRect = $Background
@onready var glow: ColorRect = $Glow
@onready var label: Label = $Label

var completed := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_visuals()

func _process(_delta: float) -> void:
	if not completed:
		# Pulsing glow animation
		var time := Time.get_ticks_msec() / 1000.0
		var pulse := sin(time * 2.0) * 0.2 + 0.8
		glow.modulate.a = pulse * 0.5

func _on_body_entered(body: Node2D) -> void:
	if completed:
		return
	
	if body is CharacterBody2D:
		completed = true
		_play_complete_animation()
		level_completed.emit()

func _play_complete_animation() -> void:
	# Flash bright
	var tween := create_tween()
	tween.tween_property(background, "color", Color(0.3, 1.0, 0.5, 0.8), 0.2)
	tween.tween_property(background, "color", Color(0.2, 0.9, 0.4, 0.5), 0.3)

func _update_visuals() -> void:
	if not is_inside_tree():
		await ready
	
	var half := zone_size / 2
	
	if collision_shape and collision_shape.shape:
		collision_shape.shape.size = zone_size
	
	if background:
		background.position = -half
		background.size = zone_size
	
	if glow:
		glow.position = -half - Vector2(10, 10)
		glow.size = zone_size + Vector2(20, 20)
	
	if label:
		label.position = Vector2(-half.x, -half.y - 30)
		label.size = Vector2(zone_size.x, 25)
