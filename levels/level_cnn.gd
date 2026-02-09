extends Node2D

const LEVEL_SIDEBAR_SCENE = preload("res://ui/level_sidebar.tscn")
const BADGE_SCENE = preload("res://ui/badge.tscn")

const LEVEL_ID := "cnn"

# Layer definitions: [grid_size, kernel_size, kernel_speed]
var conv_layers := [
	{"grid_size": 8, "kernel_size": 3, "speed": 0.4},  # Conv1: 8x8, 3x3 kernel
	{"grid_size": 6, "kernel_size": 3, "speed": 0.35},  # Conv2: 6x6, 3x3 kernel (after pool)
	{"grid_size": 4, "kernel_size": 2, "speed": 0.3},   # Conv3: 4x4, 2x2 kernel (after pool)
]

# Layout settings
const LAYER_SPACING := 550.0  # Horizontal space between layers
const CELL_SIZE := 50.0  # Size of each grid cell
const START_X := -800.0  # Where player starts
const KERNEL_DAMAGE := 0.25  # Damage when touching kernel
const START_ACTIVATION := 0.35  # Start below threshold - collect MAX pools to reach it
const ACTIVATION_THRESHOLD := 0.5  # Need this at output to complete
const MAX_POOL_BOOST := 0.20  # Activation gain per MAX pool collected (can recover from kernel hit)

# Runtime state
var kernels: Array[Dictionary] = []  # Each kernel: {visual, area, pos, layer_idx, grid_offset}
var level_completed := false
var has_started := false
var complete_label: Label = null  # Completion message label

# Start mechanic
var start_x_threshold: float = 0.0  # X position of first layer
var start_label: Label = null
var prev_x: float = 0.0  # Track previous x for crossing detection
var sidebar: Control  # Reference to the level sidebar

# Max Pool zones inside grids
var max_pool_zones: Array = []  # Track max pool zone data
var max_pools_collected := 0
var max_pools_total := 0

# Below-threshold at softmax: show message + restart icon to fly onto
var softmax_output_x: float = 0.0
var restart_icon_node: Node2D = null

@onready var player: CharacterBody2D = $Player
@onready var ui_layer: CanvasLayer = $UILayer
@onready var badge_container: Control = $UILayer/BadgeContainer
@onready var info_label: Label = $UILayer/InfoLabel
@onready var health_bar: Control = $UILayer/HealthBar
@onready var health_bar_fill: ColorRect = $UILayer/HealthBar/BarFill
@onready var layers_container: Node2D = $Layers

var network_bounds: Rect2
var activation_value_label: Label  # Shows current activation value
var threshold_line: ColorRect  # Glowing line at 0.5 threshold

func _ready() -> void:
	_setup_level_sidebar()
	_create_network()
	_position_player()
	_create_softmax_output()
	_set_network_bounds()
	
	player.magnitude_changed.connect(_on_player_magnitude_changed)
	_setup_activation_bar_extras()
	player.magnitude = START_ACTIVATION  # Start low - collect MAX pools to reach threshold

func _setup_activation_bar_extras() -> void:
	# Bar maps magnitude [0, 1] to fill
	# Bar is 400px wide, so threshold 0.5 = 200px
	var bar_width := 400.0
	var threshold_x := bar_width * ACTIVATION_THRESHOLD
	
	# Glow behind the line (soft, wide)
	var glow := ColorRect.new()
	glow.size = Vector2(10, 32)
	glow.position = Vector2(threshold_x - 5, 25)
	glow.color = Color(1.0, 1.0, 0.5, 0.3)
	health_bar.add_child(glow)
	
	# Main threshold line
	threshold_line = ColorRect.new()
	threshold_line.size = Vector2(4, 28)
	threshold_line.position = Vector2(threshold_x - 2, 27)
	threshold_line.color = Color(1.0, 1.0, 0.6, 0.9)
	health_bar.add_child(threshold_line)
	
	# Threshold label
	var threshold_label := Label.new()
	threshold_label.text = "0.5"
	threshold_label.add_theme_font_size_override("font_size", 12)
	threshold_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 0.8))
	threshold_label.position = Vector2(threshold_x - 10, 54)
	health_bar.add_child(threshold_label)
	
	# Value label (shows current activation)
	activation_value_label = Label.new()
	activation_value_label.text = "%.2f" % START_ACTIVATION
	activation_value_label.add_theme_font_size_override("font_size", 18)
	activation_value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	activation_value_label.position = Vector2(405, 30)
	health_bar.add_child(activation_value_label)

func _setup_level_sidebar() -> void:
	sidebar = LEVEL_SIDEBAR_SCENE.instantiate()
	sidebar.level_selected.connect(_on_sidebar_level_selected)
	ui_layer.add_child(sidebar)

func _on_sidebar_level_selected(level_id: String) -> void:
	if level_id != LEVEL_ID and LevelManager.is_level_unlocked(level_id):
		var level_data := LevelManager.get_level(level_id)
		if not level_data.is_empty():
			LevelManager.set_current_level(level_id)
			get_tree().change_scene_to_file(level_data["scene"])

func _create_network() -> void:
	var x_pos := START_X + 200  # Start position for first layer
	var layer_positions: Array[Dictionary] = []  # Store positions for connection lines
	
	for i in range(conv_layers.size()):
		var layer_data: Dictionary = conv_layers[i]
		var grid_size: int = layer_data["grid_size"]
		var kernel_size: int = layer_data["kernel_size"]
		var speed: float = layer_data["speed"]
		
		# Create the grid/layer
		var layer_node := Node2D.new()
		layer_node.position.x = x_pos
		layers_container.add_child(layer_node)
		
		var grid_pixel_size := grid_size * CELL_SIZE
		var grid_offset := Vector2(0, -grid_pixel_size / 2)
		
		# Store layer position info for connection lines
		layer_positions.append({
			"x": x_pos,
			"top": grid_offset.y,
			"bottom": grid_offset.y + grid_pixel_size,
			"width": grid_pixel_size
		})
		
		# Create grid background
		_create_grid_visual(layer_node, grid_size, grid_offset)
		
		# Create barriers above and below grid (force player through)
		_create_layer_barriers(layer_node, grid_pixel_size, grid_offset)
		
		# Store first layer position for start mechanic
		if i == 0:
			start_x_threshold = x_pos
		
		# Create kernel (hazard to avoid)
		var kernel_data := _create_kernel(layer_node, kernel_size, grid_offset, i, speed)
		kernel_data["grid_size"] = grid_size
		kernel_data["grid_offset"] = grid_offset
		kernel_data["layer_x"] = x_pos
		kernels.append(kernel_data)
		
		# Create MAX POOL zone inside the grid (player must collect this)
		_create_max_pool_zone(layer_node, kernel_size, grid_size, grid_offset, x_pos, i)
		
		# Add layer label
		var label := Label.new()
		label.text = "CONV %d\n%dx%d -> %dx%d" % [i + 1, grid_size, grid_size, kernel_size, kernel_size]
		label.position = grid_offset + Vector2(grid_pixel_size / 2 - 40, -50)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.9))
		layer_node.add_child(label)
		
		# Add math annotation below
		var math_label := Label.new()
		math_label.text = "y = σ(W * x + b)"
		math_label.position = grid_offset + Vector2(grid_pixel_size / 2 - 60, grid_pixel_size + 20)
		math_label.add_theme_font_size_override("font_size", 16)
		math_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.8))
		layer_node.add_child(math_label)
		
		x_pos += LAYER_SPACING
	
	# Draw connection lines between layers
	_create_connection_lines(layer_positions)

func _create_connection_lines(layer_positions: Array[Dictionary]) -> void:
	# Draw lines connecting layers like in CNN architecture diagrams
	for i in range(layer_positions.size() - 1):
		var from_layer: Dictionary = layer_positions[i]
		var to_layer: Dictionary = layer_positions[i + 1]
		
		var from_right: float = from_layer["x"] + from_layer["width"]
		var to_left: float = to_layer["x"]
		
		# Create multiple connection lines from corners and edges
		var line_color := Color(0.4, 0.5, 0.7, 0.3)
		
		# Top corner to top corner
		_draw_connection_line(
			Vector2(from_right, from_layer["top"]),
			Vector2(to_left, to_layer["top"]),
			line_color
		)
		
		# Bottom corner to bottom corner
		_draw_connection_line(
			Vector2(from_right, from_layer["bottom"]),
			Vector2(to_left, to_layer["bottom"]),
			line_color
		)
		
		# Top to bottom (crossing lines for depth effect)
		_draw_connection_line(
			Vector2(from_right, from_layer["top"]),
			Vector2(to_left, to_layer["bottom"]),
			Color(0.3, 0.4, 0.6, 0.15)
		)
		
		# Bottom to top
		_draw_connection_line(
			Vector2(from_right, from_layer["bottom"]),
			Vector2(to_left, to_layer["top"]),
			Color(0.3, 0.4, 0.6, 0.15)
		)
		
		# Middle lines for more "connected" feel
		var from_mid_y: float = (from_layer["top"] + from_layer["bottom"]) / 2
		var to_mid_y: float = (to_layer["top"] + to_layer["bottom"]) / 2
		
		_draw_connection_line(
			Vector2(from_right, from_mid_y),
			Vector2(to_left, to_mid_y),
			Color(0.5, 0.6, 0.8, 0.25)
		)

func _draw_connection_line(from: Vector2, to: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = 2.0
	line.default_color = color
	line.z_index = -10  # Behind grids
	add_child(line)

func _create_max_pool_zone(parent: Node2D, kernel_size: int, grid_size: int, grid_offset: Vector2, layer_x: float, layer_idx: int) -> void:
	max_pools_total += 1
	
	var zone_pixel_size = kernel_size * CELL_SIZE
	
	# Random position within valid grid area (where kernel-sized zone fits)
	var max_cells = grid_size - kernel_size
	var rand_x = randi_range(0, max_cells)
	var rand_y = randi_range(0, max_cells)
	var zone_x = rand_x * CELL_SIZE
	var zone_y = rand_y * CELL_SIZE
	
	# Zone container
	var zone = Node2D.new()
	zone.position = grid_offset + Vector2(zone_x, zone_y)
	zone.set_meta("collected", false)
	zone.set_meta("layer_idx", layer_idx)
	zone.set_meta("grid_x", rand_x)  # Store grid position for pattern alignment
	zone.set_meta("grid_y", rand_y)
	parent.add_child(zone)
	
	# Outer glow (light green)
	var glow = ColorRect.new()
	glow.size = Vector2(zone_pixel_size + 12, zone_pixel_size + 12)
	glow.position = Vector2(-6, -6)
	glow.color = Color(0.3, 1.0, 0.5, 0.2)
	glow.z_index = 1
	zone.add_child(glow)
	
	# Zone cells with checkerboard pattern (green-tinted, matches kernel pattern exactly)
	for my in range(kernel_size):
		for mx in range(kernel_size):
			var mcell = ColorRect.new()
			mcell.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
			mcell.position = Vector2(mx * CELL_SIZE + 1, my * CELL_SIZE + 1)
			# Same pattern as kernel - (mx + my) % 2
			var is_dark = (mx + my) % 2 == 0
			mcell.color = Color(0.1, 0.4, 0.2, 0.8) if is_dark else Color(0.18, 0.55, 0.3, 0.8)
			mcell.z_index = 2
			zone.add_child(mcell)
	
	# Border
	var border = ReferenceRect.new()
	border.size = Vector2(zone_pixel_size, zone_pixel_size)
	border.border_color = Color(0.4, 1.0, 0.6, 0.9)
	border.border_width = 3.0
	border.editor_only = false
	border.z_index = 3
	zone.add_child(border)
	
	# MAX label
	var label = Label.new()
	label.text = "MAX"
	label.position = Vector2(zone_pixel_size / 2 - 22, zone_pixel_size / 2 - 10)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	label.z_index = 4
	zone.add_child(label)
	
	# Collision area
	var area = Area2D.new()
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(zone_pixel_size, zone_pixel_size)
	collision.shape = shape
	collision.position = Vector2(zone_pixel_size / 2, zone_pixel_size / 2)
	area.add_child(collision)
	area.body_entered.connect(_on_max_zone_entered.bind(zone))
	zone.add_child(area)
	
	# Store zone data
	max_pool_zones.append({
		"node": zone,
		"layer_x": layer_x,
		"collected": false
	})

func _on_max_zone_entered(body: Node2D, zone: Node2D) -> void:
	if body != player or not has_started:
		return
	if zone.get_meta("collected"):
		return
	
	zone.set_meta("collected", true)
	max_pools_collected += 1
	
	# Boost activation (need these to reach threshold)
	player.magnitude = minf(player.magnitude + MAX_POOL_BOOST, 1.0)
	
	# Visual feedback
	var pct := int(MAX_POOL_BOOST * 100)
	var feedback = Label.new()
	feedback.text = "MAX POOL +%d%%" % pct
	feedback.global_position = player.global_position + Vector2(-50, -60)
	feedback.add_theme_font_size_override("font_size", 18)
	feedback.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	feedback.z_index = 100
	add_child(feedback)
	
	var tween = create_tween()
	tween.tween_property(feedback, "global_position:y", feedback.global_position.y - 40, 0.8)
	tween.parallel().tween_property(feedback, "modulate:a", 0.0, 0.8)
	tween.tween_callback(feedback.queue_free)
	
	# Fade out the zone
	var fade_tween = create_tween()
	fade_tween.tween_property(zone, "modulate:a", 0.3, 0.3)
	
	_update_ui()

func _create_layer_barriers(parent: Node2D, grid_pixel_size: float, grid_offset: Vector2) -> void:
	var barrier_height := 800.0  # Tall barriers
	var barrier_width := grid_pixel_size + 40  # Slightly wider than grid
	
	# Top barrier
	var top_barrier := StaticBody2D.new()
	var top_collision := CollisionShape2D.new()
	var top_shape := RectangleShape2D.new()
	top_shape.size = Vector2(barrier_width, barrier_height)
	top_collision.shape = top_shape
	top_barrier.add_child(top_collision)
	top_barrier.position = Vector2(grid_pixel_size / 2, grid_offset.y - barrier_height / 2 - 10)
	parent.add_child(top_barrier)
	
	# Bottom barrier
	var bottom_barrier := StaticBody2D.new()
	var bottom_collision := CollisionShape2D.new()
	var bottom_shape := RectangleShape2D.new()
	bottom_shape.size = Vector2(barrier_width, barrier_height)
	bottom_collision.shape = bottom_shape
	bottom_barrier.add_child(bottom_collision)
	bottom_barrier.position = Vector2(grid_pixel_size / 2, grid_offset.y + grid_pixel_size + barrier_height / 2 + 10)
	parent.add_child(bottom_barrier)

func _create_grid_visual(parent: Node2D, grid_size: int, offset: Vector2) -> void:
	var grid_pixel_size := grid_size * CELL_SIZE
	
	# Grid cells - horizontal stripes (clearly different from kernel/MAX checkerboard)
	for y in range(grid_size):
		for x in range(grid_size):
			var cell := ColorRect.new()
			cell.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
			cell.position = offset + Vector2(x * CELL_SIZE + 1, y * CELL_SIZE + 1)
			# Horizontal stripes - alternates by row only
			var is_dark := y % 2 == 0
			cell.color = Color(0.08, 0.06, 0.14) if is_dark else Color(0.16, 0.13, 0.24)
			cell.z_index = -2
			parent.add_child(cell)
	
	# Border
	var border := ReferenceRect.new()
	border.position = offset
	border.size = Vector2(grid_pixel_size, grid_pixel_size)
	border.border_color = Color(0.5, 0.4, 0.7, 0.8)
	border.border_width = 3.0
	border.editor_only = false
	parent.add_child(border)

func _create_kernel(parent: Node2D, kernel_size: int, grid_offset: Vector2, layer_idx: int, speed: float) -> Dictionary:
	var kernel_pixel_size := kernel_size * CELL_SIZE
	
	# Kernel visual container
	var kernel_visual := Node2D.new()
	kernel_visual.position = grid_offset  # Start at top-left
	parent.add_child(kernel_visual)
	
	# Kernel danger glow (red/orange - this is a hazard!)
	var outer_glow := ColorRect.new()
	outer_glow.size = Vector2(kernel_pixel_size + 16, kernel_pixel_size + 16)
	outer_glow.position = Vector2(-8, -8)
	outer_glow.color = Color(1.0, 0.3, 0.2, 0.2)
	kernel_visual.add_child(outer_glow)
	
	var inner_glow := ColorRect.new()
	inner_glow.size = Vector2(kernel_pixel_size + 6, kernel_pixel_size + 6)
	inner_glow.position = Vector2(-3, -3)
	inner_glow.color = Color(1.0, 0.4, 0.3, 0.3)
	kernel_visual.add_child(inner_glow)
	
	# Kernel cells with matching checkerboard pattern (red-tinted)
	for ky in range(kernel_size):
		for kx in range(kernel_size):
			var kcell := ColorRect.new()
			kcell.size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
			kcell.position = Vector2(kx * CELL_SIZE + 1, ky * CELL_SIZE + 1)
			var is_dark := (kx + ky) % 2 == 0
			kcell.color = Color(0.35, 0.12, 0.1, 0.7) if is_dark else Color(0.5, 0.18, 0.15, 0.7)
			kernel_visual.add_child(kcell)
	
	# Kernel border
	var border := ReferenceRect.new()
	border.size = Vector2(kernel_pixel_size, kernel_pixel_size)
	border.border_color = Color(1.0, 0.5, 0.3, 0.9)
	border.border_width = 3.0
	border.editor_only = false
	kernel_visual.add_child(border)
	
	# Kernel label
	var label := Label.new()
	label.text = "KERNEL"
	label.position = Vector2(kernel_pixel_size / 2 - 28, kernel_pixel_size / 2 - 10)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.7, 0.95))
	kernel_visual.add_child(label)
	
	# Collision area for kernel
	var kernel_area := Area2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(kernel_pixel_size - 10, kernel_pixel_size - 10)  # Slightly smaller for fairness
	collision.shape = shape
	collision.position = Vector2(kernel_pixel_size / 2, kernel_pixel_size / 2)
	kernel_area.add_child(collision)
	kernel_area.body_entered.connect(_on_kernel_hit.bind(layer_idx))
	kernel_visual.add_child(kernel_area)
	
	return {
		"visual": kernel_visual,
		"area": kernel_area,
		"pos": Vector2i(0, 0),
		"layer_idx": layer_idx,
		"kernel_size": kernel_size,
		"speed": speed,
		"timer": 0.0,
		"direction": 1,  # 1 = right, -1 = left
	}

func _on_kernel_hit(body: Node2D, layer_idx: int) -> void:
	if body == player and has_started and not level_completed:
		player.magnitude -= KERNEL_DAMAGE
		
		# Flash red warning
		var flash := ColorRect.new()
		flash.color = Color(1.0, 0.2, 0.2, 0.5)
		flash.size = Vector2(150, 150)
		flash.position = player.global_position - Vector2(75, 75)
		add_child(flash)
		
		var tween := create_tween()
		tween.tween_property(flash, "modulate:a", 0.0, 0.2)
		tween.tween_callback(flash.queue_free)
		
		# Check for death
		if player.magnitude <= -1.0:
			_on_player_died()

func _position_player() -> void:
	player.global_position = Vector2(START_X, 0)
	player.spawn_position = Vector2(START_X, 0)
	prev_x = START_X

func _create_softmax_output() -> void:
	var last_layer_x: float = START_X + 200 + (conv_layers.size() - 1) * LAYER_SPACING
	var last_grid_size: int = conv_layers[conv_layers.size() - 1]["grid_size"]
	var last_grid_width: float = last_grid_size * CELL_SIZE
	var output_x := last_layer_x + last_grid_width + 150  # Closer to last layer
	
	# Softmax zone
	var softmax_zone := Area2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(100, 300)
	collision.shape = shape
	softmax_zone.add_child(collision)
	softmax_zone.position = Vector2(output_x, 0)
	softmax_zone.body_entered.connect(_on_softmax_entered)
	add_child(softmax_zone)
	softmax_output_x = output_x
	
	# Visual
	var bg := ColorRect.new()
	bg.size = Vector2(100, 300)
	bg.position = Vector2(-50, -150)
	bg.color = Color(0.2, 0.4, 0.8, 0.3)
	softmax_zone.add_child(bg)
	
	var label := Label.new()
	label.text = "SOFTMAX\nOUTPUT"
	label.position = Vector2(-40, -20)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0, 1.0))
	softmax_zone.add_child(label)
	
	# Math annotation
	var math := Label.new()
	math.text = "σ(z)ᵢ = eᶻⁱ/Σeᶻʲ"
	math.position = Vector2(-55, 170)
	math.add_theme_font_size_override("font_size", 16)
	math.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.8))
	softmax_zone.add_child(math)
	
	# Start/Restart label at first layer
	start_label = Label.new()
	start_label.text = "START >"
	var first_grid_size: int = conv_layers[0]["grid_size"]
	var first_grid_height: float = first_grid_size * CELL_SIZE
	start_label.position = Vector2(start_x_threshold - 80, -first_grid_height / 2 - 40)
	start_label.add_theme_font_size_override("font_size", 22)
	start_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 0.9))
	add_child(start_label)
	
	# Instructions - to the right of left sidebar (220px wide), with clear gap
	var wrap_w := 320
	var wrap_h := 310
	var sidebar_width := 220
	var left_margin := sidebar_width + 60
	var top_margin := 80
	
	var instr_panel = PanelContainer.new()
	instr_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	instr_panel.anchor_left = 0.0
	instr_panel.anchor_right = 0.0
	instr_panel.offset_left = left_margin
	instr_panel.offset_right = left_margin + wrap_w
	instr_panel.offset_top = top_margin
	instr_panel.offset_bottom = top_margin + wrap_h
	instr_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.14, 0.92)
	panel_style.border_color = Color(0.4, 0.6, 0.9, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(12)
	instr_panel.add_theme_stylebox_override("panel", panel_style)
	ui_layer.add_child(instr_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	instr_panel.add_child(vbox)
	
	var instr_header = Label.new()
	instr_header.text = "Instructions:"
	instr_header.add_theme_font_size_override("font_size", 22)
	instr_header.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0, 1.0))
	vbox.add_child(instr_header)
	
	var narrative = Label.new()
	narrative.text = "Your goal is to keep activation above 0.5 by the time you reach the softmax output.\n\nAvoid the moving KERNEL—it lowers activation. Collect MAX pool zones in each layer to boost activation.\n\nComplete the network with the lowest BCE you can."
	narrative.custom_minimum_size.x = wrap_w - 24
	narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narrative.add_theme_font_size_override("font_size", 16)
	narrative.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 1.0))
	vbox.add_child(narrative)
	
	# Color-coded legend
	var legend_container = VBoxContainer.new()
	legend_container.add_theme_constant_override("separation", 4)
	vbox.add_child(legend_container)
	
	var avoid_label = Label.new()
	avoid_label.text = "Avoid: KERNEL"
	avoid_label.add_theme_font_size_override("font_size", 14)
	avoid_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	legend_container.add_child(avoid_label)
	
	var collect_label = Label.new()
	collect_label.text = "Collect: MAX pool"
	collect_label.add_theme_font_size_override("font_size", 14)
	collect_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	legend_container.add_child(collect_label)
	
	var goal_label = Label.new()
	goal_label.text = "Goal: activation > 0.5"
	goal_label.add_theme_font_size_override("font_size", 14)
	goal_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
	legend_container.add_child(goal_label)

func _on_softmax_entered(body: Node2D) -> void:
	if body != player or not has_started or level_completed:
		return
	# Must reach activation threshold by collecting MAX pools
	if player.magnitude < ACTIVATION_THRESHOLD:
		if restart_icon_node != null:
			return  # Already showed message and icon
		# Message: you didn't get the activation
		var msg = Label.new()
		msg.text = "Below activation threshold!\nCollect more MAX pools to reach 0.5"
		msg.global_position = player.global_position + Vector2(-180, -80)
		msg.add_theme_font_size_override("font_size", 18)
		msg.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
		msg.z_index = 100
		add_child(msg)
		var tween = create_tween()
		tween.tween_property(msg, "global_position:y", msg.global_position.y - 30, 2.0)
		tween.parallel().tween_property(msg, "modulate:a", 0.0, 2.0)
		tween.tween_callback(msg.queue_free)
		# Restart icon: fly onto it to go back to start and replay
		_create_restart_icon()
		return
	_complete_level()

func _create_restart_icon() -> void:
	if restart_icon_node != null:
		return
	restart_icon_node = Node2D.new()
	restart_icon_node.position = Vector2(softmax_output_x - 120, 0)
	restart_icon_node.z_index = 20
	add_child(restart_icon_node)
	# Glow
	var glow = ColorRect.new()
	glow.size = Vector2(90, 90)
	glow.position = Vector2(-45, -45)
	glow.color = Color(1.0, 0.75, 0.2, 0.25)
	restart_icon_node.add_child(glow)
	# Background
	var bg = ColorRect.new()
	bg.size = Vector2(70, 70)
	bg.position = Vector2(-35, -35)
	bg.color = Color(0.2, 0.15, 0.1, 0.9)
	restart_icon_node.add_child(bg)
	# Border
	var border = ReferenceRect.new()
	border.size = Vector2(70, 70)
	border.position = Vector2(-35, -35)
	border.border_color = Color(1.0, 0.8, 0.3, 0.95)
	border.border_width = 3
	border.editor_only = false
	restart_icon_node.add_child(border)
	# Label
	var lbl = Label.new()
	lbl.text = "RESTART"
	lbl.position = Vector2(-32, -10)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))
	restart_icon_node.add_child(lbl)
	# Subtitle
	var sub = Label.new()
	sub.text = "Fly here"
	sub.position = Vector2(-28, 12)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5, 0.9))
	restart_icon_node.add_child(sub)
	# Collision - fly onto to restart
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var coll = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(80, 80)
	coll.shape = shape
	area.add_child(coll)
	area.body_entered.connect(_on_restart_icon_entered)
	restart_icon_node.add_child(area)

func _on_restart_icon_entered(body: Node2D) -> void:
	if body != player:
		return
	_restart_level()


func _set_network_bounds() -> void:
	var min_x := START_X - 100
	var max_x := START_X + 200 + conv_layers.size() * LAYER_SPACING + 200
	var max_grid: float = float(conv_layers[0]["grid_size"]) * CELL_SIZE
	network_bounds = Rect2(min_x, -max_grid, max_x - min_x, max_grid * 2)
	
	if player.has_method("set") and "network_bounds" in player:
		player.network_bounds = network_bounds

func _process(delta: float) -> void:
	var current_x := player.global_position.x
	
	# Always allow restart check, even after completion
	if has_started:
		if prev_x >= start_x_threshold and current_x < start_x_threshold:
			_restart_level()
			return
	
	if level_completed:
		prev_x = current_x
		return
	var first_grid_size: int = conv_layers[0]["grid_size"]
	var first_grid_width: float = first_grid_size * CELL_SIZE
	var first_layer_right := start_x_threshold + first_grid_width
	
	# Check for crossing through first layer
	if not has_started:
		# Player must cross FROM left of first layer TO inside first layer
		if prev_x < start_x_threshold and current_x >= start_x_threshold:
			# Started! Player crossed into first layer
			has_started = true
			player.has_started = true
			player.gradient_active = true
			player.magnitude = START_ACTIVATION  # Start low - collect MAX pools to reach threshold
			# Set prev_x so restart requires moving right first then back left
			prev_x = start_x_threshold
			
			# Update label to RESTART
			if start_label:
				start_label.text = "< RESTART"
				start_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4, 0.9))
			return  # Skip the rest of this frame's checks
	
	prev_x = current_x
	
	# Always update kernels (so player sees them moving before starting)
	for kernel in kernels:
		_update_kernel(kernel, delta)
	
	_update_ui()

func _trigger_vanishing_gradient() -> void:
	# Show dramatic "Vanishing Gradient" death message
	var death_label := Label.new()
	death_label.text = "VANISHING GRADIENT!"
	death_label.add_theme_font_size_override("font_size", 48)
	death_label.add_theme_color_override("font_color", Color(0.6, 0.3, 0.8, 1.0))
	death_label.position = player.global_position + Vector2(-200, -100)
	death_label.z_index = 100
	add_child(death_label)
	
	# Subtitle explanation
	var subtitle := Label.new()
	subtitle.text = "Activation too low - pick the MAX value!"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0, 0.9))
	subtitle.position = player.global_position + Vector2(-140, -40)
	subtitle.z_index = 100
	add_child(subtitle)
	
	# Fade out and restart
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(death_label.queue_free)
	tween.tween_callback(subtitle.queue_free)
	tween.tween_callback(_restart_level)

func _update_kernel(kernel: Dictionary, delta: float) -> void:
	kernel["timer"] += delta
	
	if kernel["timer"] >= kernel["speed"]:
		kernel["timer"] = 0.0
		
		var grid_size: int = kernel["grid_size"]
		var kernel_size: int = kernel["kernel_size"]
		var max_pos := grid_size - kernel_size
		
		# Move kernel
		kernel["pos"].x += kernel["direction"]
		
		# Bounce at edges
		if kernel["pos"].x > max_pos:
			kernel["pos"].x = max_pos
			kernel["direction"] = -1
			kernel["pos"].y += 1
			
			# Wrap rows
			if kernel["pos"].y > max_pos:
				kernel["pos"].y = 0
		elif kernel["pos"].x < 0:
			kernel["pos"].x = 0
			kernel["direction"] = 1
			kernel["pos"].y += 1
			
			if kernel["pos"].y > max_pos:
				kernel["pos"].y = 0
		
		# Update visual position
		var grid_offset: Vector2 = kernel["grid_offset"]
		kernel["visual"].position = grid_offset + Vector2(kernel["pos"].x * CELL_SIZE, kernel["pos"].y * CELL_SIZE)
		
		# Flash effect
		var tween := create_tween()
		tween.tween_property(kernel["visual"], "modulate", Color(1.3, 1.0, 1.0, 1.0), 0.1)
		tween.tween_property(kernel["visual"], "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)

func _on_player_died() -> void:
	_restart_level()

func _restart_level() -> void:
	level_completed = false
	player.magnitude = START_ACTIVATION  # Start low again
	player.global_position = Vector2(START_X, 0)
	player.velocity = Vector2.ZERO
	has_started = false
	player.has_started = false
	player.gradient_active = false
	prev_x = START_X
	# Remove restart icon if it was shown (below-threshold at softmax)
	if restart_icon_node != null:
		restart_icon_node.queue_free()
		restart_icon_node = null
	# Remove completion label if exists
	if complete_label and is_instance_valid(complete_label):
		complete_label.queue_free()
		complete_label = null
	
	# Reset max pool zones
	max_pools_collected = 0
	for zone_data in max_pool_zones:
		var zone = zone_data["node"]
		if is_instance_valid(zone):
			zone.modulate.a = 1.0
			zone.set_meta("collected", false)
	
	# Update label back to START
	if start_label:
		start_label.text = "START >"
		start_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 0.9))
	
	# Reset all kernels
	for kernel in kernels:
		kernel["pos"] = Vector2i(0, 0)
		kernel["direction"] = 1
		kernel["timer"] = 0.0
		var grid_offset: Vector2 = kernel["grid_offset"]
		kernel["visual"].position = grid_offset

func _complete_level() -> void:
	level_completed = true
	
	# Calculate BCE based on final activation
	var activation := clampf(player.magnitude, 0.0001, 0.9999)
	var bce_loss := -log(activation)
	
	# Notify LevelManager
	if LevelManager:
		LevelManager.complete_level(LEVEL_ID, bce_loss)
	
	# Stop player effects
	if player.has_method("complete_level"):
		player.complete_level()
	
	# Show completion (remove old one first)
	if complete_label and is_instance_valid(complete_label):
		complete_label.queue_free()
	complete_label = Label.new()
	var pool_text := ""
	if max_pools_total > 0:
		pool_text = "\nMax Pools: %d/%d" % [max_pools_collected, max_pools_total]
	complete_label.text = "CNN COMPLETE!\nActivation: %.2f\nBCE: %.3f%s" % [player.magnitude, bce_loss, pool_text]
	complete_label.add_theme_font_size_override("font_size", 28)
	complete_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	complete_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	complete_label.set_anchors_preset(Control.PRESET_CENTER)
	complete_label.position = Vector2(-120, -80)
	ui_layer.add_child(complete_label)
	
	# Show badge in sidebar
	var badge := BADGE_SCENE.instantiate()
	badge.modulate.a = 0.0
	badge.custom_minimum_size = Vector2(180, 40)
	if sidebar and sidebar.has_method("add_badge"):
		sidebar.add_badge(badge)
	
	var tween := create_tween()
	tween.tween_property(badge, "modulate:a", 1.0, 0.3)
	
	# Show restart button after a short delay
	await get_tree().create_timer(1.0).timeout
	_create_play_again_button()

func _create_play_again_button() -> void:
	var restart_btn = Node2D.new()
	restart_btn.position = Vector2(softmax_output_x + 250, 0)
	restart_btn.z_index = 20
	add_child(restart_btn)
	# Glow
	var glow = ColorRect.new()
	glow.size = Vector2(110, 70)
	glow.position = Vector2(-55, -35)
	glow.color = Color(0.2, 1.0, 0.5, 0.2)
	restart_btn.add_child(glow)
	# Background
	var bg = ColorRect.new()
	bg.size = Vector2(100, 60)
	bg.position = Vector2(-50, -30)
	bg.color = Color(0.1, 0.2, 0.15, 0.9)
	restart_btn.add_child(bg)
	# Border
	var border = ReferenceRect.new()
	border.size = Vector2(100, 60)
	border.position = Vector2(-50, -30)
	border.border_color = Color(0.4, 1.0, 0.6, 0.95)
	border.border_width = 3
	border.editor_only = false
	restart_btn.add_child(border)
	# Label
	var lbl = Label.new()
	lbl.text = "PLAY\nAGAIN"
	lbl.position = Vector2(-30, -22)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_btn.add_child(lbl)
	# Collision
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var coll = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(100, 60)
	coll.shape = shape
	area.add_child(coll)
	area.body_entered.connect(_on_play_again_entered)
	restart_btn.add_child(area)

func _on_play_again_entered(body: Node2D) -> void:
	if body != player:
		return
	_restart_level()

func _on_player_magnitude_changed(new_magnitude: float) -> void:
	if health_bar_fill:
		var fill_percent := (new_magnitude + 1.0) / 2.0
		health_bar_fill.scale.x = clampf(fill_percent, 0.0, 1.0)
		
		if new_magnitude < 0:
			health_bar_fill.color = Color(1.0, 0.3, 0.3, 1.0)
		elif new_magnitude < ACTIVATION_THRESHOLD:
			health_bar_fill.color = Color(1.0, 0.7, 0.3, 1.0)
		else:
			health_bar_fill.color = Color(0.3, 0.8, 0.5, 1.0)
	
	# Update the value label
	if activation_value_label:
		activation_value_label.text = "%.2f" % new_magnitude
		# Color the value based on threshold
		if new_magnitude < ACTIVATION_THRESHOLD:
			activation_value_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 1.0))
		else:
			activation_value_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7, 1.0))

func _update_ui() -> void:
	if info_label:
		# Show max pool score
		if max_pools_total > 0:
			info_label.text = "Max Pools: %d/%d" % [max_pools_collected, max_pools_total]
			if max_pools_collected == max_pools_total:
				info_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1.0))
			else:
				info_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 0.9))
		else:
			info_label.text = "Collect the MAX zones!"
			info_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.8))
