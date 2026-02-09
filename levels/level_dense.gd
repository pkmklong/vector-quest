extends Node2D

const NEURON_SCENE = preload("res://objects/neuron.tscn")
const WEIGHT_SCENE = preload("res://objects/weight.tscn")
const RELU_GATE_SCENE = preload("res://objects/relu_gate.tscn")
const GOAL_ZONE_SCENE = preload("res://objects/goal_zone.tscn")
const DROPOUT_SCENE = preload("res://objects/dropout.tscn")
const OUTPUT_CLASS_SCENE = preload("res://objects/output_class.tscn")
const BADGE_SCENE = preload("res://ui/badge.tscn")
const BATCH_NORM_SCENE = preload("res://objects/batch_norm.tscn")
const LEVEL_SIDEBAR_SCENE = preload("res://ui/level_sidebar.tscn")

const LEVEL_ID := "dense_nn"  # This level's identifier

# Network architecture - wide input narrowing to output (classic classifier shape)
@export var layer_sizes: Array[int] = [8, 6, 4, 2]
@export var layer_spacing: float = 300.0
@export var neuron_spacing: float = 100.0

# Visual settings
@export var connection_color: Color = Color(0.3, 0.2, 0.5, 0.3)
@export var weight_density: float = 0.85  # Probability of weight on each connection

var neurons: Array = []  # 2D array: neurons[layer][index]
var start_pos: Vector2
var end_pos: Vector2

@onready var neurons_container: Node2D = $Neurons
@onready var connections_container: Node2D = $Connections
@onready var weights_container: Node2D = $Weights
@onready var relu_gates_container: Node2D = $ReluGates
@onready var dropouts_container: Node2D = $Dropouts
@onready var batch_norms_container: Node2D = $BatchNorms
@onready var player: CharacterBody2D = $Player
@onready var ui_layer: CanvasLayer = $UILayer
@onready var badge_container: Control = $UILayer/BadgeContainer
@onready var gradient_warning: Label = $UILayer/GradientWarning
@onready var health_bar: Control = $UILayer/HealthBar
@onready var health_bar_fill: ColorRect = $UILayer/HealthBar/BarFill
@onready var exploding_warning: Label = $UILayer/ExplodingWarning

var level_completed := false
var activation_value_label: Label  # Shows current activation value
var threshold_line: ColorRect  # Glowing line at 0.5 threshold
var dropout_positions: Array[Vector2] = []  # Track dropout locations
var target_class: String = ""  # The class player should aim for
var output_classes: Array = []  # Store output class nodes
var death_count := 0  # Track deaths - 2nd death restarts level
var checkpoint_pos: Vector2  # BatchNorm checkpoint position
var has_checkpoint := false
var go_to_start_label: Label  # Warning shown when player in NN without starting
var start_label: Label  # START/RESTART label above input layer
var player_was_started := false  # Track previous has_started state to detect restart
var sidebar: Control  # Reference to the level sidebar

# Scoring system - Binary Cross-Entropy
var total_bce_score := 0.0  # Running total of BCE losses (lower is better)
var runs_completed := 0  # Number of successful runs
var play_again_btn: Node2D = null  # Reference to play again button

func _ready() -> void:
	_generate_network()
	_position_player()
	_set_network_bounds()
	player.magnitude_changed.connect(_on_player_magnitude_changed)
	player.died.connect(_on_player_died)
	_create_go_to_start_label()
	_setup_level_sidebar()
	_create_instructions_panel()
	_setup_activation_bar_extras()

func _setup_activation_bar_extras() -> void:
	# Add glowing threshold line at 0.5 (50% of bar width)
	# Bar is 400px wide, so threshold is at 200px
	var bar_width := 400.0
	var threshold_x := bar_width * 0.5  # 0.5 threshold position
	
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
	activation_value_label.text = "1.00"
	activation_value_label.add_theme_font_size_override("font_size", 18)
	activation_value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	activation_value_label.position = Vector2(405, 30)
	health_bar.add_child(activation_value_label)

func _create_go_to_start_label() -> void:
	go_to_start_label = Label.new()
	go_to_start_label.text = "PASS THROUGH INPUT LAYER TO START"
	go_to_start_label.add_theme_font_size_override("font_size", 20)
	go_to_start_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 1.0))
	go_to_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_to_start_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	go_to_start_label.position = Vector2(-180, -60)
	go_to_start_label.visible = false
	ui_layer.add_child(go_to_start_label)

func _setup_level_sidebar() -> void:
	sidebar = LEVEL_SIDEBAR_SCENE.instantiate()
	sidebar.level_selected.connect(_on_sidebar_level_selected)
	ui_layer.add_child(sidebar)

func _create_instructions_panel() -> void:
	# Instructions - to the right of left sidebar (220px wide), with clear gap
	var wrap_w := 320
	var wrap_h := 340
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
	narrative.text = "Your goal is to keep activation above 0.5 by the time you reach the output layer.\n\nAvoid DROPOUT zones—they kill your signal. Collect positive WEIGHTS to boost activation. Pass through ReLU gates to shape your values.\n\nComplete the network with the lowest BCE you can."
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
	avoid_label.text = "Avoid: DROPOUT, negative weights"
	avoid_label.add_theme_font_size_override("font_size", 14)
	avoid_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	legend_container.add_child(avoid_label)
	
	var collect_label = Label.new()
	collect_label.text = "Collect: positive WEIGHTS"
	collect_label.add_theme_font_size_override("font_size", 14)
	collect_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	legend_container.add_child(collect_label)
	
	var relu_label = Label.new()
	relu_label.text = "ReLU: clips negatives to 0"
	relu_label.add_theme_font_size_override("font_size", 14)
	relu_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4, 1.0))
	legend_container.add_child(relu_label)
	
	var goal_label = Label.new()
	goal_label.text = "Goal: activation > 0.5"
	goal_label.add_theme_font_size_override("font_size", 14)
	goal_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
	legend_container.add_child(goal_label)

func _on_sidebar_level_selected(level_id: String) -> void:
	if level_id != LEVEL_ID and LevelManager.is_level_unlocked(level_id):
		var level_data := LevelManager.get_level(level_id)
		if not level_data.is_empty():
			LevelManager.set_current_level(level_id)
			get_tree().change_scene_to_file(level_data["scene"])

func _process(_delta: float) -> void:
	# Pulse the gradient warning when visible
	if gradient_warning.visible and player.magnitude < 0.25:
		var pulse := sin(Time.get_ticks_msec() / 100.0) * 0.3 + 0.7
		gradient_warning.modulate.a = pulse
	
	# Update exploding gradient warning
	_update_exploding_warning()
	
	# Show "Go to START" warning if player is in NN but hasn't started
	_update_go_to_start_warning()
	
	# Check for start/restart transitions
	_update_start_restart()

func _update_go_to_start_warning() -> void:
	if not go_to_start_label or not player:
		return
	
	# Don't show warning after level is completed (we have PLAY AGAIN button)
	if level_completed:
		go_to_start_label.visible = false
		return
	
	# Check if player has the has_started property
	if not "has_started" in player:
		go_to_start_label.visible = false
		return
	
	# Show warning if player is past the input layer but hasn't passed THROUGH it
	var input_x: float = neurons[0][0]["pos"].x if neurons.size() > 0 else 0.0
	var is_past_input: bool = player.global_position.x > input_x
	var should_show: bool = is_past_input and not player.has_started
	
	go_to_start_label.visible = should_show
	go_to_start_label.text = "PASS THROUGH INPUT LAYER TO START"
	
	# Pulse effect when visible
	if should_show:
		var pulse := sin(Time.get_ticks_msec() / 300.0) * 0.2 + 0.8
		go_to_start_label.modulate.a = pulse

func _update_start_restart() -> void:
	if not player or not "has_started" in player:
		return
	
	var input_x: float = neurons[0][0]["pos"].x if neurons.size() > 0 else 0.0
	var player_before_input := player.global_position.x < input_x - 30
	
	# Detect when player first starts - change label to RESTART
	if player.has_started and not player_was_started:
		player_was_started = true
		if start_label:
			start_label.text = "< RESTART"
			start_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 0.9))
	
	# Detect when player flies back through input layer to restart
	if player_was_started and player_before_input:
		_restart_run()

func _restart_run() -> void:
	# Reset the game for a new run
	player_was_started = false
	level_completed = false
	death_count = 0
	has_checkpoint = false
	
	# Remove play again button if it exists
	if play_again_btn and is_instance_valid(play_again_btn):
		play_again_btn.queue_free()
		play_again_btn = null
	
	# Reset player state and position to input layer
	player.global_position = start_pos
	if "has_started" in player:
		player.has_started = false
	if "level_complete" in player:
		player.level_complete = false
	if "gradient_active" in player:
		player.gradient_active = false
	player.magnitude = 1.0
	player.velocity = Vector2.ZERO
	if "external_velocity" in player:
		player.external_velocity = Vector2.ZERO
	
	# Reset visual state
	if player.has_method("_update_gradient_visuals"):
		player._update_gradient_visuals()
	
	# Reset output classes
	for oc in output_classes:
		if is_instance_valid(oc) and oc.has_method("reset"):
			oc.reset()
	
	# Change label back to START
	if start_label:
		start_label.text = "START >"
		start_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5, 0.9))
	
	# Hide the badge (but keep running score)
	if sidebar:
		var sidebar_badge_container = sidebar.get_badge_container()
		if sidebar_badge_container:
			for child in sidebar_badge_container.get_children():
				if child.name != "RunningScore":
					child.queue_free()

func _update_exploding_warning() -> void:
	if not exploding_warning or not player:
		return
	
	# Check if player has the exploding gradient properties
	if not "out_of_bounds" in player or not "gradient_active" in player:
		exploding_warning.visible = false
		return
	
	if player.out_of_bounds and player.gradient_active:
		exploding_warning.visible = true
		var time_left: float = player.EXPLODING_GRADIENT_TIME - player.exploding_gradient_timer
		exploding_warning.text = "EXPLODING GRADIENT %.1fs" % time_left
		
		# Pulse faster as time runs out
		var urgency: float = player.exploding_gradient_timer / player.EXPLODING_GRADIENT_TIME
		var pulse := sin(Time.get_ticks_msec() / (200.0 - urgency * 150.0)) * 0.3 + 0.7
		exploding_warning.modulate = Color(1.0, 0.5 - urgency * 0.3, 0.2, pulse)
	else:
		exploding_warning.visible = false

func _set_network_bounds() -> void:
	# Calculate bounds from neuron positions with padding
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	
	for layer in neurons:
		for neuron_data in layer:
			var pos: Vector2 = neuron_data["pos"]
			min_pos.x = min(min_pos.x, pos.x)
			min_pos.y = min(min_pos.y, pos.y)
			max_pos.x = max(max_pos.x, pos.x)
			max_pos.y = max(max_pos.y, pos.y)
	
	# Add padding around the network (tight so leaving triggers quickly)
	var padding := 30.0
	min_pos -= Vector2(padding, padding)
	max_pos += Vector2(padding, padding)
	
	var bounds := Rect2(min_pos, max_pos - min_pos)
	if player.has_method("set_network_bounds"):
		player.set_network_bounds(bounds)
	
	# Set gradient activation point at first hidden layer (where ReLU activations start)
	if neurons.size() > 1 and player.has_method("set_gradient_activation_x"):
		var first_hidden_x: float = neurons[1][0]["pos"].x - 30  # Slightly before the layer
		player.set_gradient_activation_x(first_hidden_x)
	
	# Set START gate - player must pass through the input layer to start
	if neurons.size() > 0 and "start_x" in player:
		var input_layer: Array = neurons[0]
		player.start_x = input_layer[0]["pos"].x - 20  # Slightly before input layer
		# Set vertical bounds with padding
		var start_padding := 60.0
		player.start_y_min = input_layer[0]["pos"].y - start_padding  # Top of input layer
		player.start_y_max = input_layer[input_layer.size() - 1]["pos"].y + start_padding  # Bottom of input layer

func _on_player_magnitude_changed(new_magnitude: float) -> void:
	# Update health bar
	if health_bar_fill:
		# Scale bar - negative values show as empty, positive fill up
		var fill_amount: float = clamp(new_magnitude, 0.0, 2.0) / 2.0
		health_bar_fill.scale.x = fill_amount * 2.0
		
		# Color based on momentum value
		if new_magnitude < 0:
			# Negative momentum - red/orange warning
			health_bar_fill.color = Color(1.0, 0.3, 0.1, 1.0)
		else:
			# Positive momentum - shifts from red to cyan
			var t: float = clamp(new_magnitude, 0.0, 1.0)
			health_bar_fill.color = Color(
				lerpf(1.0, 0.3, t),
				lerpf(0.3, 0.9, t),
				lerpf(0.2, 1.0, t),
				1.0
			)
	
	# Update the value label
	if activation_value_label:
		activation_value_label.text = "%.2f" % new_magnitude
		# Color the value based on threshold
		if new_magnitude < 0.5:
			activation_value_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 1.0))
		else:
			activation_value_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7, 1.0))
	
	# Show gradient warning
	if new_magnitude < 0.5:
		gradient_warning.visible = true
		var alpha := (0.5 - new_magnitude) * 2.0
		gradient_warning.modulate.a = alpha
	else:
		gradient_warning.visible = false

func _generate_network() -> void:
	var total_width := (layer_sizes.size() - 1) * layer_spacing
	var start_x := -total_width / 2
	
	# Create neurons for each layer
	for layer_idx in range(layer_sizes.size()):
		var layer_neurons: Array = []
		var num_neurons := layer_sizes[layer_idx]
		var total_height := (num_neurons - 1) * neuron_spacing
		var start_y := -total_height / 2
		
		for neuron_idx in range(num_neurons):
			var neuron := NEURON_SCENE.instantiate()
			var pos := Vector2(
				start_x + layer_idx * layer_spacing,
				start_y + neuron_idx * neuron_spacing
			)
			neuron.position = pos
			
			# Color neurons by layer
			var hue := float(layer_idx) / float(layer_sizes.size() - 1)
			_color_neuron(neuron, hue)
			
			neurons_container.add_child(neuron)
			layer_neurons.append({"node": neuron, "pos": pos})
		
		neurons.append(layer_neurons)
	
	# Start BEFORE the input layer so player can explore first
	var input_layer_x: float = neurons[0][0]["pos"].x
	var middle_input_idx := layer_sizes[0] / 2
	start_pos = Vector2(input_layer_x - 150, neurons[0][middle_input_idx]["pos"].y)
	end_pos = neurons[layer_sizes.size() - 1][layer_sizes[layer_sizes.size() - 1] / 2]["pos"] + Vector2(150, 0)
	
	# Add "START" label above input layer
	_create_start_label()
	
	# Create connections and weights between layers
	for layer_idx in range(layer_sizes.size() - 1):
		_create_layer_connections(layer_idx)
		_create_weights_label(layer_idx)
	
	# Add ReLU gates at hidden layers, Softmax at output (accurate to real classifiers)
	for layer_idx in range(1, layer_sizes.size()):
		var is_output_layer := layer_idx == layer_sizes.size() - 1
		
		if is_output_layer:
			# Output layer uses Softmax (no death gates - just pass through)
			_create_layer_label(layer_idx, "Softmax")
			# Add classification zones at output neurons
			_create_output_classes(layer_idx)
		else:
			# Hidden layers use ReLU
			_create_layer_label(layer_idx, "ReLU")
			for neuron_data in neurons[layer_idx]:
				_create_relu_gate_at_neuron(neuron_data["pos"])
	
	# Add 1-2 random dropout hazards in hidden layers
	_create_dropouts()
	
	# BatchNorm removed - too crowded
	# _create_batch_norms()
	
	# Add barriers to force passage through layers
	_create_layer_barriers()
	
	# Add math annotations below the network
	_create_math_annotations()

func _create_layer_connections(layer_idx: int) -> void:
	var from_layer: Array = neurons[layer_idx]
	var to_layer: Array = neurons[layer_idx + 1]
	
	for from_neuron in from_layer:
		for to_neuron in to_layer:
			var from_pos: Vector2 = from_neuron["pos"]
			var to_pos: Vector2 = to_neuron["pos"]
			
			# ALL connections have weight effects - normal distribution-ish
			var activation_effect: float = randf_range(-0.7, 0.7)
			
			# Intensity based on absolute strength (0 to 1 scale)
			var intensity: float = absf(activation_effect)
			
			# Draw connection line - color AND intensity based on effect
			var line := Line2D.new()
			line.add_point(from_pos)
			line.add_point(to_pos)
			
			if activation_effect < 0:
				# Red spectrum - intensity determines how deep the red
				_add_glow_layers(from_pos, to_pos, Color(0.9, 0.3, 0.3), intensity)
				line.width = 2.0
				line.default_color = Color(0.9, 0.4, 0.4, 0.15 + intensity * 0.25)
			else:
				# Green spectrum - intensity determines how deep the green
				_add_glow_layers(from_pos, to_pos, Color(0.3, 0.85, 0.4), intensity)
				line.width = 2.0
				line.default_color = Color(0.4, 0.85, 0.45, 0.15 + intensity * 0.25)
			
			connections_container.add_child(line)
			
			# Create invisible weight zone for the effect
			_create_weight_on_connection(from_pos, to_pos, activation_effect)

func _add_glow_layers(from_pos: Vector2, to_pos: Vector2, base_color: Color, intensity: float) -> void:
	# Single soft glow - intensity controls opacity
	var glow_line := Line2D.new()
	glow_line.add_point(from_pos)
	glow_line.add_point(to_pos)
	glow_line.width = 40.0
	glow_line.default_color = Color(base_color.r, base_color.g, base_color.b, 0.06 + intensity * 0.08)
	glow_line.z_index = -1
	glow_line.antialiased = true
	connections_container.add_child(glow_line)

func _create_weight_on_connection(from_pos: Vector2, to_pos: Vector2, activation_effect: float) -> void:
	var weight := WEIGHT_SCENE.instantiate()
	
	# Position at center of connection
	weight.position = from_pos.lerp(to_pos, 0.5)
	
	# Direction follows connection
	var base_dir := (to_pos - from_pos).normalized()
	var angle_offset := randf_range(-0.3, 0.3)
	var push_dir := base_dir.rotated(angle_offset)
	
	# Set properties
	weight.push_direction = push_dir
	weight.push_strength = randf_range(150.0, 350.0)
	weight.activation_effect = activation_effect
	
	# Size covers most of the connection length for vicinity effect
	var connection_length := from_pos.distance_to(to_pos)
	weight.size = Vector2(connection_length * 0.7, 50.0)
	
	# Rotate to align with connection
	weight.rotation = base_dir.angle()
	
	# Hide visuals - the colored line shows the effect instead
	weight.show_visuals = false
	
	weights_container.add_child(weight)

func _create_weights_label(layer_idx: int) -> void:
	var from_layer: Array = neurons[layer_idx]
	var to_layer: Array = neurons[layer_idx + 1]
	
	# Position between the two layers
	var from_x: float = from_layer[0]["pos"].x
	var to_x: float = to_layer[0]["pos"].x
	var mid_x := (from_x + to_x) / 2
	var top_y: float = min(from_layer[0]["pos"].y, to_layer[0]["pos"].y)
	var bottom_y: float = max(from_layer[from_layer.size() - 1]["pos"].y, to_layer[to_layer.size() - 1]["pos"].y)
	
	# Label above - staggered from ReLU (at -50 instead of -85)
	var label_top := Label.new()
	label_top.text = "y = Wx + b"
	label_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_top.position = Vector2(mid_x - 60, top_y - 50)
	label_top.size = Vector2(120, 30)
	label_top.add_theme_font_size_override("font_size", 20)
	label_top.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1.0))
	connections_container.add_child(label_top)
	
	# Label below - staggered from ReLU (at +95 instead of +55)
	var label_bottom := Label.new()
	label_bottom.text = "y = Wx + b"
	label_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_bottom.position = Vector2(mid_x - 60, bottom_y + 95)
	label_bottom.size = Vector2(120, 30)
	label_bottom.add_theme_font_size_override("font_size", 20)
	label_bottom.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1.0))
	connections_container.add_child(label_bottom)

func _create_layer_label(layer_idx: int, text: String) -> void:
	var layer: Array = neurons[layer_idx]
	
	# Get positions for top and bottom
	var top_pos: Vector2 = layer[0]["pos"]
	var bottom_pos: Vector2 = layer[layer.size() - 1]["pos"]
	
	# Use name + math formulas
	var display_text := text
	if text == "ReLU":
		display_text = "ReLU: max(0, x)"
	elif text == "Softmax":
		display_text = "Softmax: eˣⁱ/Σeˣʲ"
	
	# Label above
	var label_top := Label.new()
	label_top.text = display_text
	label_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_top.position = Vector2(top_pos.x - 90, top_pos.y - 85)
	label_top.size = Vector2(180, 35)
	label_top.add_theme_font_size_override("font_size", 20)
	label_top.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8, 1.0))
	neurons_container.add_child(label_top)
	
	# Label below
	var label_bottom := Label.new()
	label_bottom.text = display_text
	label_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_bottom.position = Vector2(bottom_pos.x - 90, bottom_pos.y + 55)
	label_bottom.size = Vector2(180, 35)
	label_bottom.add_theme_font_size_override("font_size", 20)
	label_bottom.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8, 1.0))
	neurons_container.add_child(label_bottom)

func _create_start_label() -> void:
	var input_layer: Array = neurons[0]
	var top_pos: Vector2 = input_layer[0]["pos"]
	
	start_label = Label.new()
	start_label.text = "START >"
	start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_label.position = Vector2(top_pos.x - 130, top_pos.y - 80)
	start_label.size = Vector2(100, 30)
	start_label.add_theme_font_size_override("font_size", 18)
	start_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5, 0.9))
	neurons_container.add_child(start_label)
	

func _create_relu_gate_at_neuron(neuron_pos: Vector2) -> void:
	var relu_gate := RELU_GATE_SCENE.instantiate()
	# Position gate at the neuron center (circular overlay)
	relu_gate.position = neuron_pos
	relu_gate.radius = 38.0  # Slightly larger than neuron visual
	# All ReLU gates now behave the same: max(0, x) - clips negative momentum to zero
	relu_gates_container.add_child(relu_gate)

func _color_neuron(neuron: Node2D, hue: float) -> void:
	var color := Color.from_hsv(0.7 - hue * 0.3, 0.6, 0.9)
	var glow_color := Color(color.r, color.g, color.b, 0.15)
	
	var glow_outer := neuron.get_node("GlowOuter")
	var glow_inner := neuron.get_node("GlowInner")
	var core := neuron.get_node("Core")
	
	glow_outer.modulate = Color(color.r, color.g, color.b, 0.1)
	glow_inner.modulate = Color(color.r, color.g, color.b, 0.2)
	core.color = color

func _create_math_annotations() -> void:
	# Math annotations are now shown above each component in the network
	# (via _create_weights_label and _create_layer_label)
	pass

func _create_output_classes(layer_idx: int) -> void:
	var output_layer: Array = neurons[layer_idx]
	
	# Target is always Class 1 (activation > 0.5)
	var target_class_int := 1
	target_class = "Class 1"
	
	# Calculate center position of output layer for single Softmax zone
	var center_y := 0.0
	for neuron_data in output_layer:
		center_y += neuron_data["pos"].y
	center_y /= output_layer.size()
	
	var output_x: float = output_layer[0]["pos"].x
	
	# Create single Softmax output zone
	var oc := OUTPUT_CLASS_SCENE.instantiate()
	oc.position = Vector2(output_x + 60, center_y)  # Slightly past the output neurons
	oc.radius = 60.0
	oc.activation_threshold = 0.5
	oc.target_class = target_class_int
	oc.classified.connect(_on_classified)
	neurons_container.add_child(oc)
	output_classes.append(oc)
	
	# Show target objective
	_show_target_objective()

func _show_target_objective() -> void:
	# Create a label showing the target at the top of the screen
	var objective_label := Label.new()
	objective_label.text = "TARGET: Activation > 0.5"
	objective_label.add_theme_font_size_override("font_size", 18)
	objective_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_label.position = Vector2(-100, 70)
	ui_layer.add_child(objective_label)
	
	# Also show briefly in center at start
	var intro_label := Label.new()
	intro_label.text = "Goal: Keep Activation > 0.5"
	intro_label.add_theme_font_size_override("font_size", 28)
	intro_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5, 1.0))
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_label.set_anchors_preset(Control.PRESET_CENTER)
	intro_label.position = Vector2(-150, -40)
	ui_layer.add_child(intro_label)
	
	# Fade out the intro label
	var tween := create_tween()
	tween.tween_property(intro_label, "modulate:a", 0.0, 1.5).set_delay(2.0)
	tween.tween_callback(intro_label.queue_free)

func _on_classified(predicted_class: int, is_correct: bool, activation: float, bce_loss: float) -> void:
	if is_correct:
		runs_completed += 1
		total_bce_score += bce_loss
		_on_level_completed(bce_loss)
	else:
		_on_wrong_classification(predicted_class, activation)

func _create_dropouts() -> void:
	# Pick 1-2 random neurons from hidden layers to be dropouts
	var num_dropouts := randi_range(1, 2)
	var candidate_positions: Array[Vector2] = []
	
	# Collect all hidden layer neuron positions (not input or output)
	for layer_idx in range(1, layer_sizes.size() - 1):
		for neuron_data in neurons[layer_idx]:
			candidate_positions.append(neuron_data["pos"])
	
	# Randomly select positions for dropouts
	candidate_positions.shuffle()
	for i in range(min(num_dropouts, candidate_positions.size())):
		var pos: Vector2 = candidate_positions[i]
		dropout_positions.append(pos)
		
		var dropout := DROPOUT_SCENE.instantiate()
		dropout.position = pos
		dropout.radius = 40.0
		dropouts_container.add_child(dropout)

func _create_layer_barriers() -> void:
	# Create barriers above and below each layer to force passage through neurons
	for layer_idx in range(neurons.size()):
		var layer: Array = neurons[layer_idx]
		if layer.size() == 0:
			continue
		
		# Get top and bottom neuron positions
		var top_y: float = layer[0]["pos"].y
		var bottom_y: float = layer[layer.size() - 1]["pos"].y
		var x_pos: float = layer[0]["pos"].x
		
		# Barrier dimensions
		var barrier_height := 400.0  # Tall enough to block
		var barrier_width := 60.0
		
		# Top barrier (above top neuron)
		var top_barrier := StaticBody2D.new()
		var top_shape := CollisionShape2D.new()
		var top_rect := RectangleShape2D.new()
		top_rect.size = Vector2(barrier_width, barrier_height)
		top_shape.shape = top_rect
		top_barrier.add_child(top_shape)
		top_barrier.position = Vector2(x_pos, top_y - neuron_spacing/2 - barrier_height/2)
		neurons_container.add_child(top_barrier)
		
		# Bottom barrier (below bottom neuron)
		var bottom_barrier := StaticBody2D.new()
		var bottom_shape := CollisionShape2D.new()
		var bottom_rect := RectangleShape2D.new()
		bottom_rect.size = Vector2(barrier_width, barrier_height)
		bottom_shape.shape = bottom_rect
		bottom_barrier.add_child(bottom_shape)
		bottom_barrier.position = Vector2(x_pos, bottom_y + neuron_spacing/2 + barrier_height/2)
		neurons_container.add_child(bottom_barrier)

func _create_batch_norms() -> void:
	# Add ONE BatchNorm checkpoint in the middle of the network
	var mid_layer_idx: int = layer_sizes.size() / 2  # Middle layer
	
	var curr_layer_x: float = neurons[mid_layer_idx - 1][0]["pos"].x
	var next_layer_x: float = neurons[mid_layer_idx][0]["pos"].x
	
	# Place BatchNorm centered between layers
	var bn_x: float = curr_layer_x + (next_layer_x - curr_layer_x) * 0.5
	
	# Calculate height based on the middle layer's vertical span
	var mid_layer: Array = neurons[mid_layer_idx]
	var top_y: float = mid_layer[0]["pos"].y
	var bottom_y: float = mid_layer[mid_layer.size() - 1]["pos"].y
	var layer_height: float = abs(top_y - bottom_y) + 120
	var layer_center_y: float = (top_y + bottom_y) / 2
	
	var bn_pos := Vector2(bn_x, layer_center_y)
	checkpoint_pos = bn_pos  # Store for respawn system
	
	var batch_norm := BATCH_NORM_SCENE.instantiate()
	batch_norm.position = bn_pos
	batch_norm.zone_height = layer_height
	batch_norm.zone_width = 60.0
	batch_norm.checkpoint_activated.connect(_on_checkpoint_activated)
	batch_norms_container.add_child(batch_norm)

func _on_checkpoint_activated() -> void:
	has_checkpoint = true

func _on_player_died() -> void:
	death_count += 1
	
	if death_count >= 2:
		# Second death - full restart
		_show_restart_message()
	elif has_checkpoint:
		# First death with checkpoint - respawn at BatchNorm
		_show_checkpoint_respawn()
	# If no checkpoint yet, player respawns at start (default behavior)

func _create_goal_zone() -> void:
	var goal := GOAL_ZONE_SCENE.instantiate()
	goal.position = end_pos
	
	# Size to cover the output layer height
	var output_layer: Array = neurons[layer_sizes.size() - 1]
	var min_y: float = output_layer[0]["pos"].y
	var max_y: float = output_layer[output_layer.size() - 1]["pos"].y
	goal.zone_size = Vector2(60, max_y - min_y + 100)
	
	goal.level_completed.connect(_on_level_completed)
	add_child(goal)

func _on_level_completed(bce_loss: float = 0.0) -> void:
	if level_completed:
		return
	level_completed = true
	
	# Notify LevelManager of completion
	if LevelManager:
		LevelManager.complete_level(LEVEL_ID, bce_loss)
	
	# Stop vanishing gradient and restore player magnitude
	if player.has_method("complete_level"):
		player.complete_level()
	
	# Show success badge in sidebar
	var badge := BADGE_SCENE.instantiate()
	badge.modulate.a = 0.0
	badge.custom_minimum_size = Vector2(180, 40)
	if sidebar and sidebar.has_method("add_badge"):
		sidebar.add_badge(badge)
	
	var tween := create_tween()
	tween.tween_property(badge, "modulate:a", 1.0, 0.3)
	
	# Show BCE score next to badge
	_show_score_display(bce_loss)
	
	# Show play again button after a short delay
	await get_tree().create_timer(1.0).timeout
	_create_play_again_button()

func _create_play_again_button() -> void:
	# Remove existing button if any
	if play_again_btn and is_instance_valid(play_again_btn):
		play_again_btn.queue_free()
	
	play_again_btn = Node2D.new()
	play_again_btn.position = end_pos + Vector2(250, 0)
	play_again_btn.z_index = 20
	add_child(play_again_btn)
	# Glow
	var glow = ColorRect.new()
	glow.size = Vector2(110, 70)
	glow.position = Vector2(-55, -35)
	glow.color = Color(0.2, 1.0, 0.5, 0.2)
	play_again_btn.add_child(glow)
	# Background
	var bg = ColorRect.new()
	bg.size = Vector2(100, 60)
	bg.position = Vector2(-50, -30)
	bg.color = Color(0.1, 0.2, 0.15, 0.9)
	play_again_btn.add_child(bg)
	# Border
	var border = ReferenceRect.new()
	border.size = Vector2(100, 60)
	border.position = Vector2(-50, -30)
	border.border_color = Color(0.4, 1.0, 0.6, 0.95)
	border.border_width = 3
	border.editor_only = false
	play_again_btn.add_child(border)
	# Label
	var lbl = Label.new()
	lbl.text = "PLAY\nAGAIN"
	lbl.position = Vector2(-30, -22)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_again_btn.add_child(lbl)
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
	play_again_btn.add_child(area)

func _on_play_again_entered(body: Node2D) -> void:
	if body != player:
		return
	_restart_run()

func _show_score_display(bce_loss: float) -> void:
	# Flash the BCE score
	var score_flash := Label.new()
	score_flash.text = "BCE: %.3f" % bce_loss
	score_flash.add_theme_font_size_override("font_size", 32)
	score_flash.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	score_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_flash.set_anchors_preset(Control.PRESET_CENTER)
	score_flash.position = Vector2(-80, -100)
	score_flash.scale = Vector2(2.0, 2.0)
	ui_layer.add_child(score_flash)
	
	# Flash animation - big then settle
	var flash_tween := create_tween()
	flash_tween.tween_property(score_flash, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(score_flash, "modulate:a", 0.0, 1.0).set_delay(2.0)
	flash_tween.tween_callback(score_flash.queue_free)
	
	# Create/update persistent score display next to badge
	_update_running_score()

func _update_running_score() -> void:
	if not sidebar:
		return
	var sidebar_badge_container = sidebar.get_badge_container()
	if not sidebar_badge_container:
		return
	
	# Find or create the running score label
	var score_label: Label = sidebar_badge_container.get_node_or_null("RunningScore")
	if not score_label:
		score_label = Label.new()
		score_label.name = "RunningScore"
		score_label.add_theme_font_size_override("font_size", 11)
		sidebar_badge_container.add_child(score_label)
	
	# Calculate average BCE
	var avg_bce := total_bce_score / float(runs_completed) if runs_completed > 0 else 0.0
	
	# Update text (compact for sidebar)
	score_label.text = "Runs: %d\nBCE: %.3f (avg)" % [runs_completed, avg_bce]
	score_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 0.9))

func _on_wrong_classification(predicted_class: int, activation: float) -> void:
	if level_completed:
		return
	level_completed = true  # Prevent multiple triggers
	
	# Determine what went wrong
	var needed := "> 0.5" if target_class == "Class 1" else "≤ 0.5"
	
	# Show failure message
	var fail_label := Label.new()
	fail_label.text = "MISCLASSIFICATION!\nActivation: %.2f\nNeeded: %s for %s" % [activation, needed, target_class]
	fail_label.add_theme_font_size_override("font_size", 24)
	fail_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
	fail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fail_label.set_anchors_preset(Control.PRESET_CENTER)
	fail_label.position = Vector2(-150, -60)
	ui_layer.add_child(fail_label)
	
	# Respawn player after delay
	await get_tree().create_timer(2.5).timeout
	
	level_completed = false
	fail_label.queue_free()
	
	# Reset output classes
	for oc in output_classes:
		if is_instance_valid(oc) and oc.has_method("reset"):
			oc.reset()
	
	# Respawn player
	if player.has_method("respawn"):
		player.respawn()

func _position_player() -> void:
	player.position = start_pos
	# Set spawn point so player respawns here on death
	if player.has_method("set_spawn_point"):
		player.set_spawn_point(start_pos)

func _show_checkpoint_respawn() -> void:
	# Show brief message
	var msg := Label.new()
	msg.text = "Respawning at BatchNorm..."
	msg.add_theme_font_size_override("font_size", 20)
	msg.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9, 1.0))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.position = Vector2(-120, 0)
	ui_layer.add_child(msg)
	
	# Update spawn point to checkpoint
	if player.has_method("set_spawn_point"):
		player.set_spawn_point(checkpoint_pos)
	
	# Fade out message
	var tween := create_tween()
	tween.tween_property(msg, "modulate:a", 0.0, 0.8).set_delay(0.5)
	tween.tween_callback(msg.queue_free)

func _show_restart_message() -> void:
	# Show restart message
	var msg := Label.new()
	msg.text = "OUT OF LIVES!\nRestarting..."
	msg.add_theme_font_size_override("font_size", 28)
	msg.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3, 1.0))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.position = Vector2(-100, -30)
	ui_layer.add_child(msg)
	
	# Reset after delay
	await get_tree().create_timer(1.5).timeout
	msg.queue_free()
	
	# Full restart - reset death count, checkpoint, and respawn at start
	death_count = 0
	has_checkpoint = false
	
	if player.has_method("set_spawn_point"):
		player.set_spawn_point(start_pos)