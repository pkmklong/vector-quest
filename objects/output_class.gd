extends Area2D
class_name OutputClass

## Output zone - checks player's activation value to determine classification

signal classified(predicted_class: int, is_correct: bool, activation: float, bce_loss: float)

@export var activation_threshold: float = 0.5  # Activation > threshold = Class 1
@export var target_class: int = 1  # Which class player should achieve (0 or 1)
@export var radius: float = 50.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var glow: Polygon2D = $Glow
@onready var label: Label = $Label
@onready var flash_label: Label = $FlashLabel

var has_triggered := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_visuals()
	flash_label.visible = false

func _update_visuals() -> void:
	if not is_inside_tree():
		await ready
	
	if collision_shape and collision_shape.shape:
		collision_shape.shape.radius = radius
	
	if glow:
		glow.polygon = _create_circle(radius * 1.2, 16)
		glow.color = Color(0.6, 0.4, 0.9, 0.3)  # Purple for Softmax
	
	if label:
		label.text = "Softmax"
		label.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0, 0.9))

func _create_circle(r: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / segments) * TAU
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return points

func _on_body_entered(body: Node2D) -> void:
	if has_triggered:
		return
	
	# Only process if player has started the game
	if not ("has_started" in body and body.has_started):
		return
	
	if body is CharacterBody2D and "magnitude" in body:
		has_triggered = true
		var activation: float = body.magnitude
		var predicted_class := 1 if activation > activation_threshold else 0
		var is_correct := (predicted_class == target_class)
		
		# Calculate Binary Cross-Entropy loss: -[y*log(p) + (1-y)*log(1-p)]
		# For target_class=1: BCE = -log(p)
		# Clamp activation to avoid log(0) or log of negative
		var p := clampf(activation, 0.0001, 0.9999)
		var bce: float
		if target_class == 1:
			bce = -log(p)
		else:
			bce = -log(1.0 - p)
		
		_show_classification(activation, predicted_class, is_correct, bce)
		classified.emit(predicted_class, is_correct, activation, bce)

func _show_classification(activation: float, predicted_class: int, correct: bool, bce: float) -> void:
	# Show activation value, result, and BCE loss
	var class_text := "Class " + str(predicted_class)
	var result_text := "CORRECT" if correct else "WRONG"
	var bce_text := "BCE Loss: %.3f" % bce
	
	flash_label.text = "Activation: %.2f\n%s\n%s\n%s" % [activation, class_text, result_text, bce_text]
	flash_label.visible = true
	flash_label.scale = Vector2(0.5, 0.5)
	
	if correct:
		flash_label.modulate = Color(0.3, 1.0, 0.5, 1.0)
		glow.color = Color(0.3, 1.0, 0.5, 0.7)
	else:
		flash_label.modulate = Color(1.0, 0.3, 0.2, 1.0)
		glow.color = Color(1.0, 0.3, 0.2, 0.7)
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash_label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash_label, "modulate:a", 0.0, 2.0).set_delay(1.0)
	
	var glow_target := Color(0.3, 0.8, 0.4, 0.3) if correct else Color(0.5, 0.3, 0.3, 0.3)
	tween.tween_property(glow, "color", glow_target, 0.5)

func reset() -> void:
	has_triggered = false
	if glow:
		glow.color = Color(0.6, 0.4, 0.9, 0.3)

func _process(_delta: float) -> void:
	if not has_triggered:
		var time := Time.get_ticks_msec() / 1000.0
		var pulse := sin(time * 2.0) * 0.1 + 0.9
		if glow:
			glow.scale = Vector2(pulse, pulse)
