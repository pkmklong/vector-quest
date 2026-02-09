extends Area2D
class_name Weight

## Direction of the push force (normalized automatically)
@export var push_direction: Vector2 = Vector2.RIGHT:
	set(value):
		push_direction = value.normalized() if value.length() > 0 else Vector2.RIGHT
		_update_visuals()

## Strength of the push force
@export var push_strength: float = 200.0

## Effect on player's activation value per second (positive = boost, negative = reduce)
@export var activation_effect: float = 0.0

## Size of the weight area
@export var size: Vector2 = Vector2(120, 80):
	set(value):
		size = value
		_update_visuals()

## Color of the weight (tint)
@export var weight_color: Color = Color(0.4, 0.6, 1.0, 0.3)

## Whether to show visual elements (set false for invisible effect zones)
@export var show_visuals: bool = true

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var background: ColorRect = $Background
@onready var flow_container: Node2D = $FlowContainer
@onready var border: ReferenceRect = $Border
@onready var sign_label: Label = $SignLabel

func _ready() -> void:
	_update_visuals()
	_create_flow_arrows()

func _physics_process(delta: float) -> void:
	# Check for overlapping bodies each frame
	var bodies := get_overlapping_bodies()
	for body in bodies:
		# Skip if player has completed the level
		if "level_complete" in body and body.level_complete:
			continue
		
		if body.has_method("apply_force"):
			# Apply force field push to player via their apply_force method
			var push_force := push_direction * push_strength * delta
			body.apply_force(push_force)
		
		# Apply activation effect (weights modify the signal strength) - only if player has started
		if activation_effect != 0.0 and "magnitude" in body and "has_started" in body and body.has_started:
			body.magnitude += activation_effect * delta
	
	# Animate flow arrows
	_animate_flow()

func _update_visuals() -> void:
	if not is_inside_tree():
		await ready
	
	# Update collision shape
	if collision_shape and collision_shape.shape:
		collision_shape.shape.size = size
	
	# Hide all visuals if show_visuals is false
	if not show_visuals:
		if background:
			background.visible = false
		if border:
			border.visible = false
		if sign_label:
			sign_label.visible = false
		if flow_container:
			flow_container.visible = false
		return
	
	# Update background
	if background:
		background.visible = true
		background.position = -size / 2
		background.size = size
		background.color = weight_color
	
	# Update border
	if border:
		border.visible = true
		border.position = -size / 2
		border.size = size
		border.border_color = Color(weight_color.r, weight_color.g, weight_color.b, 0.6)
	
	# Hide sign label - we use arrow colors instead
	if sign_label:
		sign_label.visible = false
	
	# Recreate flow arrows when direction changes
	if flow_container:
		flow_container.visible = true
		_create_flow_arrows()

func _create_flow_arrows() -> void:
	if not flow_container:
		return
	
	# Clear existing arrows
	for child in flow_container.get_children():
		child.queue_free()
	
	# Create grid of flow indicators
	var arrow_spacing := 30.0
	var cols := int(size.x / arrow_spacing)
	var rows := int(size.y / arrow_spacing)
	
	var angle := push_direction.angle()
	
	for row in range(rows):
		for col in range(cols):
			var arrow := _create_arrow()
			var x := -size.x / 2 + arrow_spacing / 2 + col * arrow_spacing
			var y := -size.y / 2 + arrow_spacing / 2 + row * arrow_spacing
			arrow.position = Vector2(x, y)
			arrow.rotation = angle
			# Stagger animation phase based on position along push direction
			var phase := (col * push_direction.x + row * push_direction.y) * 0.3
			arrow.set_meta("phase", phase)
			flow_container.add_child(arrow)

func _create_arrow() -> Polygon2D:
	var arrow := Polygon2D.new()
	# Small chevron shape pointing right (will be rotated)
	arrow.polygon = PackedVector2Array([
		Vector2(-6, -4),
		Vector2(0, 0),
		Vector2(-6, 4),
		Vector2(-4, 0)
	])
	# Color arrows based on activation effect
	if activation_effect < -0.05:
		arrow.color = Color(1.0, 0.4, 0.3, 0.6)  # Red for negative
	elif activation_effect > 0.05:
		arrow.color = Color(0.3, 1.0, 0.5, 0.6)  # Green for positive
	else:
		arrow.color = Color(0.7, 0.8, 1.0, 0.4)  # Light blue for neutral
	return arrow

func _animate_flow() -> void:
	if not flow_container:
		return
	
	var time := Time.get_ticks_msec() / 1000.0
	
	# Determine base color from activation effect
	var base_color: Color
	if activation_effect < -0.05:
		base_color = Color(1.0, 0.4, 0.3, 1.0)  # Red
	elif activation_effect > 0.05:
		base_color = Color(0.3, 1.0, 0.5, 1.0)  # Green
	else:
		base_color = Color(0.7, 0.8, 1.0, 1.0)  # Light blue
	
	for arrow in flow_container.get_children():
		var phase: float = arrow.get_meta("phase", 0.0)
		# Pulsing opacity based on time and position
		var pulse := sin(time * 3.0 + phase) * 0.5 + 0.5
		var base_alpha := 0.3 + pulse * 0.5
		arrow.color = Color(base_color.r, base_color.g, base_color.b, base_alpha)
		
		# Subtle scale pulse
		var scale_pulse := 0.8 + pulse * 0.4
		arrow.scale = Vector2(scale_pulse, scale_pulse)
