extends Node2D

const LEVEL_SIDEBAR_SCENE = preload("res://ui/level_sidebar.tscn")
const BADGE_SCENE = preload("res://ui/badge.tscn")

@onready var player: CharacterBody2D = $Player
@onready var ui_layer: CanvasLayer = $UILayer
@onready var health_bar: Control = $UILayer/HealthBar
@onready var health_bar_fill: ColorRect = $UILayer/HealthBar/BarFill
@onready var phase_label: Label = $UILayer/PhaseLabel

var sidebar: Control
var activation_value_label: Label
var threshold_line: ColorRect
var level_completed := false
var has_started := false
var player_was_started := false
var current_phase := 0  # 0=embedding, 1=encoder_attn, 2=encoder_ff, 3=decoder_attn, 4=decoder_ff, 5=output

# Layout constants
const START_X := -400.0
const EMBEDDING_X := -300.0
const ENCODER_ATTN_X := -100.0
const ENCODER_FF_X := 100.0
const DECODER_ATTN_X := 100.0  # Same X as encoder FF, but different Y
const DECODER_FF_X := 300.0
const OUTPUT_X := 500.0
const BASE_Y := 0.0
const ENCODER_Y := -120.0  # Encoder row (upper)
const DECODER_Y := 150.0   # Decoder row (lower, offset)

# Attention mechanics
var attention_score := 0.5  # Like activation, but for attention
var queries_collected := 0
var keys_matched := 0
var masks_hit := 0

# Player visual transformation
var player_is_embedding := true
var embedding_visual: Node2D  # The vertical vector visual
var start_label: Label  # START > / < RESTART

func _ready() -> void:
	# Add sidebar
	sidebar = LEVEL_SIDEBAR_SCENE.instantiate()
	sidebar.level_selected.connect(_on_level_selected)
	ui_layer.add_child(sidebar)
	
	# Setup menu button
	
	# Create level structure
	_create_embedding_layer()
	_create_section_header("ENCODER", ENCODER_ATTN_X - 90, Color(0.5, 0.5, 1.0), ENCODER_Y)
	_create_encoder_attention()
	_create_encoder_feedforward()
	_create_encoder_decoder_separator()
	_create_section_header("DECODER", DECODER_ATTN_X - 90, Color(1.0, 0.5, 0.8), DECODER_Y)
	_create_decoder_attention()
	_create_decoder_feedforward()
	_create_output_layer()
	_create_formula_display()
	_create_instructions()
	
	# Position player as embedding vector
	player.global_position = Vector2(START_X - 100, BASE_Y)
	player.spawn_position = player.global_position
	player.network_bounds = Rect2(START_X - 200, -300, OUTPUT_X - START_X + 400, 600)
	player.magnitude = attention_score
	player.has_started = false
	player.gradient_active = false
	
	# Create embedding visual (vertical vector) attached to player
	_create_embedding_visual()
	
	# Setup health bar extras (threshold line, value label)
	_setup_activation_bar_extras()
	
	_update_ui()

func _setup_activation_bar_extras() -> void:
	var bar_width := 400.0
	var threshold_x := bar_width * 0.5  # 0.5 threshold position
	
	# Glow behind the line
	var glow := ColorRect.new()
	glow.size = Vector2(10, 32)
	glow.position = Vector2(threshold_x - 5, 25)
	glow.color = Color(0.5, 0.8, 1.0, 0.3)
	health_bar.add_child(glow)
	
	# Main threshold line
	threshold_line = ColorRect.new()
	threshold_line.size = Vector2(4, 28)
	threshold_line.position = Vector2(threshold_x - 2, 27)
	threshold_line.color = Color(0.5, 0.9, 1.0, 0.9)
	health_bar.add_child(threshold_line)
	
	# Threshold label
	var threshold_label := Label.new()
	threshold_label.text = "0.5"
	threshold_label.add_theme_font_size_override("font_size", 12)
	threshold_label.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0, 0.8))
	threshold_label.position = Vector2(threshold_x - 10, 54)
	health_bar.add_child(threshold_label)
	
	# Value label (shows current attention)
	activation_value_label = Label.new()
	activation_value_label.text = "0.50"
	activation_value_label.add_theme_font_size_override("font_size", 18)
	activation_value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	activation_value_label.position = Vector2(405, 30)
	health_bar.add_child(activation_value_label)

func _on_level_selected(level_id: String) -> void:
	if level_id != "transformer" and LevelManager.is_level_unlocked(level_id):
		var level_data = LevelManager.get_level(level_id)
		if not level_data.is_empty():
			LevelManager.set_current_level(level_id)
			get_tree().change_scene_to_file(level_data["scene"])

func _process(_delta: float) -> void:
	if not player:
		return
	
	# Update embedding visual position
	if embedding_visual and player_is_embedding:
		embedding_visual.global_position = player.global_position
	
	# Update player color based on phase
	_update_player_color()
	
	# Track start
	if has_started and not player_was_started:
		player_was_started = true
		if start_label:
			start_label.text = "< RESTART"
			start_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 0.9))
	
	# Check for restart (fly back past start while still in embedding phase)
	if player_was_started and player.global_position.x < START_X - 50 and current_phase == 0:
		_restart()

func _update_player_color() -> void:
	if not player:
		return
	
	# Color progression through transformer
	var color: Color
	match current_phase:
		0:  # Embedding - cyan/blue
			color = Color(0.3, 0.8, 1.0)
		1:  # Encoder attention - blue to purple
			color = Color(0.5, 0.5, 1.0)
		2:  # Encoder feedforward - purple
			color = Color(0.7, 0.4, 1.0)
		3:  # Decoder attention - purple to magenta
			color = Color(0.9, 0.4, 0.8)
		4:  # Decoder feedforward - magenta to green
			color = Color(0.6, 0.8, 0.5)
		5:  # Output - green
			color = Color(0.4, 1.0, 0.6)
		_:
			color = Color(1, 1, 1)
	
	player.modulate = color

func _create_embedding_visual() -> void:
	# Create vertical vector visual (rectangle with horizontal bars)
	embedding_visual = Node2D.new()
	embedding_visual.z_index = 10
	
	# Main rectangle (vertical)
	var rect = ColorRect.new()
	rect.size = Vector2(30, 80)
	rect.position = Vector2(-15, -40)
	rect.color = Color(0.3, 0.8, 1.0, 0.8)
	embedding_visual.add_child(rect)
	
	# Horizontal bars (representing vector elements)
	for i in range(5):
		var bar = ColorRect.new()
		bar.size = Vector2(26, 3)
		bar.position = Vector2(-13, -35 + i * 16)
		bar.color = Color(0.1, 0.3, 0.5, 0.9)
		embedding_visual.add_child(bar)
	
	# Border
	var border = ReferenceRect.new()
	border.size = Vector2(30, 80)
	border.position = Vector2(-15, -40)
	border.border_color = Color(0.5, 0.9, 1.0, 0.9)
	border.border_width = 2
	embedding_visual.add_child(border)
	
	# Label
	var lbl = Label.new()
	lbl.text = "x"
	lbl.position = Vector2(-6, 45)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	embedding_visual.add_child(lbl)
	
	add_child(embedding_visual)

func _create_embedding_layer() -> void:
	var x = EMBEDDING_X
	
	# Section background
	var bg = ColorRect.new()
	bg.size = Vector2(120, 400)
	bg.position = Vector2(x - 60, -200)
	bg.color = Color(0.1, 0.2, 0.3, 0.5)
	bg.z_index = -10
	add_child(bg)
	
	# Title
	var title = Label.new()
	title.text = "EMBEDDING"
	title.position = Vector2(x - 50, -220)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0, 0.9))
	add_child(title)
	
	# Embedding matrix visual (grid)
	for row in range(8):
		for col in range(4):
			var cell = ColorRect.new()
			cell.size = Vector2(20, 20)
			cell.position = Vector2(x - 45 + col * 25, -150 + row * 40)
			var intensity = randf_range(0.2, 0.6)
			cell.color = Color(intensity * 0.5, intensity * 0.8, intensity, 0.7)
			add_child(cell)
	
	# Entry zone
	var entry = Area2D.new()
	entry.collision_layer = 0
	entry.collision_mask = 1
	entry.monitoring = true
	var entry_coll = CollisionShape2D.new()
	var entry_shape = RectangleShape2D.new()
	entry_shape.size = Vector2(40, 400)
	entry_coll.shape = entry_shape
	entry.add_child(entry_coll)
	entry.position = Vector2(x, 0)
	entry.body_entered.connect(_on_embedding_entered)
	add_child(entry)
	
	# Start label (stored for restart toggle)
	start_label = Label.new()
	start_label.text = "START >"
	start_label.position = Vector2(START_X - 80, -10)
	start_label.add_theme_font_size_override("font_size", 18)
	start_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	add_child(start_label)

func _create_section_header(text: String, x: float, color: Color, y_offset: float = 0) -> void:
	# Big section header above the sections
	var header = Label.new()
	header.text = text
	header.position = Vector2(x, y_offset - 160)
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", color)
	header.z_index = 5
	add_child(header)
	
	# Underline
	var line = ColorRect.new()
	line.size = Vector2(180, 3)
	line.position = Vector2(x, y_offset - 130)
	line.color = color
	line.color.a = 0.7
	add_child(line)

func _create_encoder_decoder_separator() -> void:
	# Arrow from encoder (upper) to decoder (lower) showing K,V flow
	var start_x = ENCODER_FF_X + 60
	var start_y = ENCODER_Y
	var end_x = DECODER_ATTN_X - 80
	var end_y = DECODER_Y
	
	# Curved arrow using Line2D
	var arrow = Line2D.new()
	arrow.add_point(Vector2(start_x, start_y))
	arrow.add_point(Vector2(start_x + 40, (start_y + end_y) / 2))
	arrow.add_point(Vector2(end_x, end_y))
	arrow.width = 4
	arrow.default_color = Color(0.8, 0.6, 0.9, 0.7)
	arrow.z_index = -5
	add_child(arrow)
	
	# Glow for arrow
	var glow = Line2D.new()
	glow.add_point(Vector2(start_x, start_y))
	glow.add_point(Vector2(start_x + 40, (start_y + end_y) / 2))
	glow.add_point(Vector2(end_x, end_y))
	glow.width = 12
	glow.default_color = Color(0.8, 0.6, 0.9, 0.2)
	glow.z_index = -6
	add_child(glow)
	
	# K,V label on the arrow
	var kv_lbl = Label.new()
	kv_lbl.text = "K,V"
	kv_lbl.position = Vector2(start_x + 20, (start_y + end_y) / 2 - 25)
	kv_lbl.add_theme_font_size_override("font_size", 16)
	kv_lbl.add_theme_color_override("font_color", Color(0.8, 0.6, 0.9, 0.9))
	add_child(kv_lbl)
	
	# Arrow head
	var head = Label.new()
	head.text = "v"
	head.position = Vector2(end_x - 8, end_y - 40)
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(0.8, 0.6, 0.9, 0.9))
	add_child(head)

func _create_encoder_attention() -> void:
	var x = ENCODER_ATTN_X
	var y = ENCODER_Y
	
	# No background - let the matrices define the space
	
	# Title - "SELF-ATTENTION" label only
	var title = Label.new()
	title.text = "SELF-ATTENTION"
	title.position = Vector2(x - 70, y - 130)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0, 0.9))
	add_child(title)
	
	# Attention block with overlapping Q, K, V matrices (enlarged)
	_create_attention_block(x, y, "encoder_self")
	
	# Attention mask (triangular area to avoid)
	_create_attention_mask(x + 100, y - 40)
	
	# Entry zone
	var entry = Area2D.new()
	entry.collision_layer = 0
	entry.collision_mask = 1
	entry.monitoring = true
	var entry_coll = CollisionShape2D.new()
	var entry_shape = RectangleShape2D.new()
	entry_shape.size = Vector2(40, 250)
	entry_coll.shape = entry_shape
	entry.add_child(entry_coll)
	entry.position = Vector2(x + 110, y)
	entry.body_entered.connect(_on_encoder_attention_complete)
	add_child(entry)

func _create_attention_block(base_x: float, base_y: float, block_id: String) -> void:
	# Create overlapping matrix visuals for Q, K
	# V is placed at a RANDOM location - revealed when Q+K collected (attention shows WHERE to look)
	var block = Node2D.new()
	block.position = Vector2(base_x, base_y)
	block.set_meta("block_id", block_id)
	block.set_meta("q_collected", false)
	block.set_meta("k_collected", false)
	block.set_meta("v_available", false)
	block.set_meta("v_collected", false)
	add_child(block)
	
	# Store reference
	if not has_meta("attention_blocks"):
		set_meta("attention_blocks", [])
	var blocks = get_meta("attention_blocks")
	blocks.append(block)
	set_meta("attention_blocks", blocks)
	
	# Enlarged overlapping matrix backgrounds (offset to show depth) - Q and K matrices
	var matrix_colors = [
		Color(1.0, 0.6, 0.3, 0.15),  # Q - orange (subtle)
		Color(0.3, 0.8, 1.0, 0.18),  # K - cyan (subtle)
	]
	
	for i in range(2):
		var matrix = ColorRect.new()
		matrix.name = "Matrix" + str(i)
		matrix.size = Vector2(120, 160)  # Much larger
		matrix.position = Vector2(-60 + i * 15, -80 + i * 12)
		matrix.color = matrix_colors[i]
		block.add_child(matrix)
		
		# Horizontal bars inside matrix (more bars, larger)
		for j in range(6):
			var bar = ColorRect.new()
			bar.size = Vector2(100, 6)
			bar.position = Vector2(-50 + i * 15, -65 + i * 12 + j * 24)
			bar.color = matrix_colors[i]
			bar.color.a = 0.4
			bar.name = "Bar" + str(i) + "_" + str(j)
			block.add_child(bar)
	
	# "QK^T" label
	var qk_label = Label.new()
	qk_label.text = "QK"
	qk_label.position = Vector2(-15, -70)
	qk_label.add_theme_font_size_override("font_size", 14)
	qk_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.9, 0.8))
	block.add_child(qk_label)
	
	# Q collectible (left side of matrix)
	var q_cont = Node2D.new()
	q_cont.name = "Q"
	q_cont.position = Vector2(-25, 0)
	
	var q_glow = ColorRect.new()
	q_glow.size = Vector2(45, 45)
	q_glow.position = Vector2(-22, -22)
	q_glow.color = Color(1.0, 0.6, 0.3, 0.3)
	q_cont.add_child(q_glow)
	
	var q_box = ColorRect.new()
	q_box.size = Vector2(35, 35)
	q_box.position = Vector2(-17, -17)
	q_box.color = Color(1.0, 0.6, 0.3, 0.95)
	q_cont.add_child(q_box)
	
	var q_lbl = Label.new()
	q_lbl.text = "Q"
	q_lbl.position = Vector2(-8, -10)
	q_lbl.add_theme_font_size_override("font_size", 18)
	q_lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	q_cont.add_child(q_lbl)
	
	var q_area = Area2D.new()
	q_area.collision_layer = 0
	q_area.collision_mask = 1
	q_area.monitoring = true
	var q_coll = CollisionShape2D.new()
	var q_shape = RectangleShape2D.new()
	q_shape.size = Vector2(35, 35)
	q_coll.shape = q_shape
	q_area.add_child(q_coll)
	q_area.body_entered.connect(_on_q_collected.bind(block))
	q_cont.add_child(q_area)
	block.add_child(q_cont)
	
	# K collectible (right side of matrix)
	var k_cont = Node2D.new()
	k_cont.name = "K"
	k_cont.position = Vector2(25, 0)
	
	var k_glow = ColorRect.new()
	k_glow.size = Vector2(45, 45)
	k_glow.position = Vector2(-22, -22)
	k_glow.color = Color(0.3, 0.8, 1.0, 0.3)
	k_cont.add_child(k_glow)
	
	var k_box = ColorRect.new()
	k_box.size = Vector2(35, 35)
	k_box.position = Vector2(-17, -17)
	k_box.color = Color(0.3, 0.8, 1.0, 0.95)
	k_cont.add_child(k_box)
	
	var k_lbl = Label.new()
	k_lbl.text = "K"
	k_lbl.position = Vector2(-8, -10)
	k_lbl.add_theme_font_size_override("font_size", 18)
	k_lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	k_cont.add_child(k_lbl)
	
	var k_area = Area2D.new()
	k_area.collision_layer = 0
	k_area.collision_mask = 1
	k_area.monitoring = true
	var k_coll = CollisionShape2D.new()
	var k_shape = RectangleShape2D.new()
	k_shape.size = Vector2(35, 35)
	k_coll.shape = k_shape
	k_area.add_child(k_coll)
	k_area.body_entered.connect(_on_k_collected.bind(block))
	k_cont.add_child(k_area)
	block.add_child(k_cont)
	
	# V is placed at a RANDOM offset position - this is WHERE attention tells you to look!
	var v_offset_x = randf_range(80, 150) * (1 if randf() > 0.5 else -1)
	var v_offset_y = randf_range(-60, 60)
	block.set_meta("v_offset", Vector2(v_offset_x, v_offset_y))
	
	# V collectible (at random location, hidden initially)
	var v_cont = Node2D.new()
	v_cont.name = "V"
	v_cont.position = Vector2(v_offset_x, v_offset_y)
	v_cont.modulate.a = 0  # HIDDEN until Q+K collected
	
	# V has a pulsing glow to show it's the target
	var v_glow_outer = ColorRect.new()
	v_glow_outer.name = "VGlowOuter"
	v_glow_outer.size = Vector2(70, 70)
	v_glow_outer.position = Vector2(-35, -35)
	v_glow_outer.color = Color(0.5, 1.0, 0.5, 0.2)
	v_cont.add_child(v_glow_outer)
	
	var v_glow = ColorRect.new()
	v_glow.size = Vector2(55, 55)
	v_glow.position = Vector2(-27, -27)
	v_glow.color = Color(0.5, 1.0, 0.5, 0.35)
	v_cont.add_child(v_glow)
	
	var v_box = ColorRect.new()
	v_box.size = Vector2(45, 45)
	v_box.position = Vector2(-22, -22)
	v_box.color = Color(0.4, 0.9, 0.4, 0.95)
	v_cont.add_child(v_box)
	
	var v_lbl = Label.new()
	v_lbl.text = "V"
	v_lbl.position = Vector2(-10, -14)
	v_lbl.add_theme_font_size_override("font_size", 24)
	v_lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	v_cont.add_child(v_lbl)
	
	# "ATTEND HERE" label
	var attend_lbl = Label.new()
	attend_lbl.name = "AttendLabel"
	attend_lbl.text = "ATTEND"
	attend_lbl.position = Vector2(-30, -55)
	attend_lbl.add_theme_font_size_override("font_size", 12)
	attend_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 0.9))
	v_cont.add_child(attend_lbl)
	
	var v_area = Area2D.new()
	v_area.collision_layer = 0
	v_area.collision_mask = 1
	v_area.monitoring = true
	var v_coll = CollisionShape2D.new()
	var v_shape = RectangleShape2D.new()
	v_shape.size = Vector2(45, 45)
	v_coll.shape = v_shape
	v_area.add_child(v_coll)
	v_area.body_entered.connect(_on_v_collected.bind(block))
	v_cont.add_child(v_area)
	block.add_child(v_cont)
	
	# Arrow pointing from QK to V (hidden initially, shows WHERE to attend)
	var arrow = Line2D.new()
	arrow.name = "AttentionArrow"
	arrow.add_point(Vector2(0, 20))
	arrow.add_point(Vector2(v_offset_x * 0.5, v_offset_y * 0.5 + 10))
	arrow.add_point(Vector2(v_offset_x - sign(v_offset_x) * 30, v_offset_y))
	arrow.width = 3
	arrow.default_color = Color(0.5, 1.0, 0.5, 0.6)
	arrow.modulate.a = 0  # Hidden initially
	block.add_child(arrow)
	
	# Arrow glow
	var arrow_glow = Line2D.new()
	arrow_glow.name = "AttentionArrowGlow"
	arrow_glow.add_point(Vector2(0, 20))
	arrow_glow.add_point(Vector2(v_offset_x * 0.5, v_offset_y * 0.5 + 10))
	arrow_glow.add_point(Vector2(v_offset_x - sign(v_offset_x) * 30, v_offset_y))
	arrow_glow.width = 10
	arrow_glow.default_color = Color(0.5, 1.0, 0.5, 0.15)
	arrow_glow.modulate.a = 0
	arrow_glow.z_index = -1
	block.add_child(arrow_glow)
	
	# Formula label (shown after V collected)
	var formula = Label.new()
	formula.name = "Formula"
	formula.text = "softmax(QK^T) * V"
	formula.position = Vector2(-60, 55)
	formula.add_theme_font_size_override("font_size", 12)
	formula.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	formula.modulate.a = 0
	block.add_child(formula)
	
	# Checkmark (shown after V collected)
	var check = Label.new()
	check.name = "Check"
	check.text = "OK"
	check.position = Vector2(-12, 70)
	check.add_theme_font_size_override("font_size", 18)
	check.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	check.modulate.a = 0
	block.add_child(check)

func _on_q_collected(body: Node2D, block: Node2D) -> void:
	if body != player or not has_started:
		return
	if block.get_meta("q_collected"):
		return
	
	block.set_meta("q_collected", true)
	var q_node = block.get_node("Q")
	
	# Fade Q
	var tw = create_tween()
	tw.tween_property(q_node, "modulate:a", 0.3, 0.3)
	
	_show_msg("Q collected!", Color(1.0, 0.6, 0.3))
	attention_score += 0.05
	player.magnitude = attention_score
	_update_ui()
	
	# Check if both Q and K collected
	_check_qk_complete(block)

func _on_k_collected(body: Node2D, block: Node2D) -> void:
	if body != player or not has_started:
		return
	if block.get_meta("k_collected"):
		return
	
	block.set_meta("k_collected", true)
	var k_node = block.get_node("K")
	
	# Fade K
	var tw = create_tween()
	tw.tween_property(k_node, "modulate:a", 0.3, 0.3)
	
	_show_msg("K collected!", Color(0.3, 0.8, 1.0))
	attention_score += 0.05
	player.magnitude = attention_score
	_update_ui()
	
	# Check if both Q and K collected
	_check_qk_complete(block)

func _check_qk_complete(block: Node2D) -> void:
	if block.get_meta("q_collected") and block.get_meta("k_collected") and not block.get_meta("v_available"):
		block.set_meta("v_available", true)
		
		# Reveal V at its random location + show arrow pointing to it
		var v_node = block.get_node("V")
		var arrow = block.get_node("AttentionArrow")
		var arrow_glow = block.get_node("AttentionArrowGlow")
		
		var tw = create_tween()
		# First show the arrow (attention weights show WHERE to look)
		tw.tween_property(arrow_glow, "modulate:a", 1.0, 0.3)
		tw.parallel().tween_property(arrow, "modulate:a", 1.0, 0.3)
		# Then reveal V (the value at that location)
		tw.tween_property(v_node, "modulate:a", 1.0, 0.4)
		
		_show_msg("Attention computed! Go to V!", Color(0.5, 1.0, 0.5))

func _on_v_collected(body: Node2D, block: Node2D) -> void:
	if body != player or not has_started:
		return
	if not block.get_meta("v_available") or block.get_meta("v_collected"):
		return
	
	block.set_meta("v_collected", true)
	var v_node = block.get_node("V")
	var formula = block.get_node("Formula")
	var check = block.get_node("Check")
	var arrow = block.get_node("AttentionArrow")
	var arrow_glow = block.get_node("AttentionArrowGlow")
	
	# Fade V and arrow, show formula and checkmark at the QK location
	var tw = create_tween()
	tw.tween_property(v_node, "modulate:a", 0.2, 0.3)
	tw.parallel().tween_property(arrow, "modulate:a", 0.2, 0.3)
	tw.parallel().tween_property(arrow_glow, "modulate:a", 0.0, 0.3)
	tw.tween_property(formula, "modulate:a", 1.0, 0.3)
	tw.tween_property(check, "modulate:a", 1.0, 0.3)
	
	# V is the main content boost - bigger reward for finding WHERE to attend
	_show_msg("Value collected! +15%", Color(0.4, 1.0, 0.5))
	attention_score += 0.15
	player.magnitude = attention_score
	_update_ui()

# Legacy function for simple KQV (keeping for any remaining calls)
func _create_kqv_elements(base_x: float, y_offset: float, label_text: String, color: Color) -> void:
	var cont = Node2D.new()
	cont.position = Vector2(base_x - 60, y_offset)
	
	# Glow
	var glow = ColorRect.new()
	glow.size = Vector2(50, 50)
	glow.position = Vector2(-25, -25)
	glow.color = Color(color.r, color.g, color.b, 0.3)
	cont.add_child(glow)
	
	# Box
	var box = ColorRect.new()
	box.size = Vector2(40, 40)
	box.position = Vector2(-20, -20)
	box.color = color
	cont.add_child(box)
	
	# Label
	var lbl = Label.new()
	lbl.text = label_text
	lbl.position = Vector2(-10, -12)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	cont.add_child(lbl)
	
	# Collision
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var coll = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40, 40)
	coll.shape = shape
	area.add_child(coll)
	area.body_entered.connect(_on_kqv_collected.bind(label_text, cont))
	cont.add_child(area)
	
	add_child(cont)

func _create_attention_mask(x: float, y: float) -> void:
	# Triangular mask zone (causal masking visualization)
	var mask_cont = Node2D.new()
	mask_cont.position = Vector2(x, y)
	
	# Draw triangular mask using polygon
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(60, 0),
		Vector2(60, 60)
	])
	poly.color = Color(0.8, 0.2, 0.2, 0.4)
	mask_cont.add_child(poly)
	
	# Label
	var lbl = Label.new()
	lbl.text = "MASK"
	lbl.position = Vector2(15, 15)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 0.9))
	mask_cont.add_child(lbl)
	
	# Collision for mask (damages player)
	var area = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var coll = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(50, 50)
	coll.shape = shape
	coll.position = Vector2(30, 30)
	area.add_child(coll)
	area.body_entered.connect(_on_mask_hit)
	mask_cont.add_child(area)
	
	add_child(mask_cont)

func _create_encoder_feedforward() -> void:
	var x = ENCODER_FF_X
	var y = ENCODER_Y
	
	# Title
	var title = Label.new()
	title.text = "FEED FORWARD"
	title.position = Vector2(x - 55, y - 130)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0, 0.9))
	add_child(title)
	
	# DNN-style vertical neuron layout
	var neuron_positions: Array = []
	var neuron_spacing = 60.0
	var num_neurons = 4
	var start_y = y - (num_neurons - 1) * neuron_spacing / 2
	
	for i in range(num_neurons):
		var neuron_y = start_y + i * neuron_spacing
		neuron_positions.append(Vector2(x, neuron_y))
		
		# Outer glow
		var glow = ColorRect.new()
		glow.size = Vector2(50, 50)
		glow.position = Vector2(x - 25, neuron_y - 25)
		glow.color = Color(0.7, 0.4, 1.0, 0.15)
		add_child(glow)
		
		# Inner glow
		var inner = ColorRect.new()
		inner.size = Vector2(38, 38)
		inner.position = Vector2(x - 19, neuron_y - 19)
		inner.color = Color(0.7, 0.4, 1.0, 0.3)
		add_child(inner)
		
		# Core
		var neuron = ColorRect.new()
		neuron.size = Vector2(28, 28)
		neuron.position = Vector2(x - 14, neuron_y - 14)
		neuron.color = Color(0.75, 0.5, 1.0, 0.9)
		add_child(neuron)
	
	# Connection lines between neurons (subtle)
	for i in range(num_neurons - 1):
		var line = Line2D.new()
		line.add_point(neuron_positions[i])
		line.add_point(neuron_positions[i + 1])
		line.width = 2
		line.default_color = Color(0.7, 0.4, 1.0, 0.3)
		line.z_index = -1
		add_child(line)
	
	# ReLU label
	var relu = Label.new()
	relu.text = "ReLU"
	relu.position = Vector2(x + 30, y - 8)
	relu.add_theme_font_size_override("font_size", 14)
	relu.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
	add_child(relu)
	
	# Entry zone
	var entry = Area2D.new()
	entry.collision_layer = 0
	entry.collision_mask = 1
	entry.monitoring = true
	var entry_coll = CollisionShape2D.new()
	var entry_shape = RectangleShape2D.new()
	entry_shape.size = Vector2(50, 250)
	entry_coll.shape = entry_shape
	entry.add_child(entry_coll)
	entry.position = Vector2(x + 50, y)
	entry.body_entered.connect(_on_encoder_ff_complete)
	add_child(entry)

func _create_decoder_attention() -> void:
	var x = DECODER_ATTN_X
	var y = DECODER_Y
	
	# No background - let the matrices define the space
	
	# Title - "CROSS-ATTENTION" label only
	var title = Label.new()
	title.text = "CROSS-ATTENTION"
	title.position = Vector2(x - 70, y - 130)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.8, 0.9))
	add_child(title)
	
	# Cross attention block with overlapping Q, K, V matrices (enlarged)
	_create_attention_block(x, y, "decoder_cross")
	
	# Attention mask
	_create_attention_mask(x + 100, y - 40)
	
	# Entry zone
	var entry = Area2D.new()
	entry.collision_layer = 0
	entry.collision_mask = 1
	entry.monitoring = true
	var entry_coll = CollisionShape2D.new()
	var entry_shape = RectangleShape2D.new()
	entry_shape.size = Vector2(40, 250)
	entry_coll.shape = entry_shape
	entry.add_child(entry_coll)
	entry.position = Vector2(x + 110, y)
	entry.body_entered.connect(_on_decoder_attention_complete)
	add_child(entry)

func _create_decoder_feedforward() -> void:
	var x = DECODER_FF_X
	var y = DECODER_Y
	
	# Title
	var title = Label.new()
	title.text = "FEED FORWARD"
	title.position = Vector2(x - 55, y - 130)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 0.5, 0.9))
	add_child(title)
	
	# DNN-style vertical neuron layout
	var neuron_positions: Array = []
	var neuron_spacing = 60.0
	var num_neurons = 4
	var start_y = y - (num_neurons - 1) * neuron_spacing / 2
	
	for i in range(num_neurons):
		var neuron_y = start_y + i * neuron_spacing
		neuron_positions.append(Vector2(x, neuron_y))
		
		# Outer glow
		var glow = ColorRect.new()
		glow.size = Vector2(50, 50)
		glow.position = Vector2(x - 25, neuron_y - 25)
		glow.color = Color(0.6, 0.85, 0.4, 0.15)
		add_child(glow)
		
		# Inner glow
		var inner = ColorRect.new()
		inner.size = Vector2(38, 38)
		inner.position = Vector2(x - 19, neuron_y - 19)
		inner.color = Color(0.6, 0.85, 0.4, 0.3)
		add_child(inner)
		
		# Core
		var neuron = ColorRect.new()
		neuron.size = Vector2(28, 28)
		neuron.position = Vector2(x - 14, neuron_y - 14)
		neuron.color = Color(0.65, 0.9, 0.5, 0.9)
		add_child(neuron)
	
	# Connection lines between neurons (subtle)
	for i in range(num_neurons - 1):
		var line = Line2D.new()
		line.add_point(neuron_positions[i])
		line.add_point(neuron_positions[i + 1])
		line.width = 2
		line.default_color = Color(0.6, 0.85, 0.4, 0.3)
		line.z_index = -1
		add_child(line)
	
	# ReLU label
	var relu = Label.new()
	relu.text = "ReLU"
	relu.position = Vector2(x + 30, y - 8)
	relu.add_theme_font_size_override("font_size", 14)
	relu.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
	add_child(relu)
	
	# Entry zone
	var entry = Area2D.new()
	entry.collision_layer = 0
	entry.collision_mask = 1
	entry.monitoring = true
	var entry_coll = CollisionShape2D.new()
	var entry_shape = RectangleShape2D.new()
	entry_shape.size = Vector2(50, 250)
	entry_coll.shape = entry_shape
	entry.add_child(entry_coll)
	entry.position = Vector2(x + 50, y)
	entry.body_entered.connect(_on_decoder_ff_complete)
	add_child(entry)

func _create_output_layer() -> void:
	var x = OUTPUT_X
	var y = DECODER_Y  # Output follows decoder row
	
	# No background - just title and nodes
	
	# Title
	var title = Label.new()
	title.text = "OUTPUT"
	title.position = Vector2(x - 35, y - 130)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 0.9))
	add_child(title)
	
	# Softmax output nodes - vertical stack
	var tokens = ["cat", "dog", "bird"]
	for i in range(3):
		var y_pos = y - 50 + i * 50
		var node = ColorRect.new()
		node.size = Vector2(60, 35)
		node.position = Vector2(x - 30, y_pos - 17)
		node.color = Color(0.3, 0.7, 0.4, 0.8)
		add_child(node)
		
		var lbl = Label.new()
		lbl.text = tokens[i]
		lbl.position = Vector2(x - 20, y_pos - 8)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		add_child(lbl)
	
	# Completion zone
	var complete_zone = Area2D.new()
	complete_zone.collision_layer = 0
	complete_zone.collision_mask = 1
	complete_zone.monitoring = true
	var complete_coll = CollisionShape2D.new()
	var complete_shape = RectangleShape2D.new()
	complete_shape.size = Vector2(60, 200)
	complete_coll.shape = complete_shape
	complete_zone.add_child(complete_coll)
	complete_zone.position = Vector2(x, y)
	complete_zone.body_entered.connect(_on_output_reached)
	add_child(complete_zone)

func _create_formula_display() -> void:
	var form_y = 250
	
	# Attention formula
	var formula = Label.new()
	formula.text = "Attention(Q,K,V) = softmax(QK^T / sqrt(d)) * V"
	formula.position = Vector2(-200, form_y)
	formula.add_theme_font_size_override("font_size", 14)
	formula.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 0.7))
	add_child(formula)

func _create_instructions() -> void:
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
	
	var header = Label.new()
	header.text = "Instructions:"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0, 1.0))
	vbox.add_child(header)
	
	var narrative = Label.new()
	narrative.text = "Your goal is to keep your attention score above 0.5 by the time you reach the output.\n\nCollect Q, K, and V in each attention block to boost attention. Avoid MASK zones—they lower your attention. Move through embedding, encoder, and decoder.\n\nComplete the network with the lowest BCE you can."
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
	avoid_label.text = "Avoid: MASK zones"
	avoid_label.add_theme_font_size_override("font_size", 14)
	avoid_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	legend_container.add_child(avoid_label)
	
	var collect_label = Label.new()
	collect_label.text = "Collect: Q, K, V"
	collect_label.add_theme_font_size_override("font_size", 14)
	collect_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	legend_container.add_child(collect_label)
	
	var goal_label = Label.new()
	goal_label.text = "Goal: reach OUTPUT"
	goal_label.add_theme_font_size_override("font_size", 14)
	goal_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
	legend_container.add_child(goal_label)

# Event handlers
func _on_embedding_entered(body: Node2D) -> void:
	if body != player:
		return
	
	if not has_started:
		has_started = true
		player.has_started = true
		player.gradient_active = true
	
	# Transform from embedding vector to cursor
	if player_is_embedding:
		player_is_embedding = false
		if embedding_visual:
			# Animate fade out
			var tw = create_tween()
			tw.tween_property(embedding_visual, "modulate:a", 0.0, 0.3)
			tw.tween_callback(embedding_visual.queue_free)
		
		_show_msg("Embedded!", Color(0.5, 0.9, 1.0))
		current_phase = 1
		_update_ui()

func _on_kqv_collected(body: Node2D, kqv_type: String, node: Node2D) -> void:
	if body != player or not has_started:
		return
	
	# Bonus for collecting
	attention_score += 0.08
	attention_score = minf(attention_score, 1.0)
	
	var color: Color
	match kqv_type:
		"Q":
			queries_collected += 1
			color = Color(1.0, 0.6, 0.3)
			_show_msg("Query +8%", color)
		"K":
			keys_matched += 1
			color = Color(0.3, 0.8, 1.0)
			_show_msg("Key +8%", color)
		"V":
			color = Color(0.5, 1.0, 0.5)
			_show_msg("Value +8%", color)
	
	# Fade out collected item
	var tw = create_tween()
	tw.tween_property(node, "modulate:a", 0.3, 0.3)
	
	player.magnitude = attention_score
	_update_ui()

func _on_mask_hit(body: Node2D) -> void:
	if body != player or not has_started or level_completed:
		return
	
	masks_hit += 1
	attention_score -= 0.15
	attention_score = maxf(attention_score, 0)
	_show_msg("Masked! -15%", Color(1.0, 0.4, 0.4))
	
	player.magnitude = attention_score
	_update_ui()
	
	if attention_score <= 0:
		_show_msg("ATTENTION COLLAPSE!", Color(1.0, 0.3, 0.3))
		await get_tree().create_timer(1.5).timeout
		_restart()

func _on_encoder_attention_complete(body: Node2D) -> void:
	if body != player or not has_started or current_phase != 1:
		return
	current_phase = 2
	_show_msg("Encoder Attention OK!", Color(0.7, 0.5, 1.0))
	_update_ui()

func _on_encoder_ff_complete(body: Node2D) -> void:
	if body != player or not has_started or current_phase != 2:
		return
	current_phase = 3
	_show_msg("Encoder Complete!", Color(0.8, 0.5, 1.0))
	_update_ui()

func _on_decoder_attention_complete(body: Node2D) -> void:
	if body != player or not has_started or current_phase != 3:
		return
	current_phase = 4
	_show_msg("Decoder Attention OK!", Color(1.0, 0.5, 0.8))
	_update_ui()

func _on_decoder_ff_complete(body: Node2D) -> void:
	if body != player or not has_started or current_phase != 4:
		return
	current_phase = 5
	_show_msg("Decoder Complete!", Color(0.6, 0.9, 0.5))
	_update_ui()

func _on_output_reached(body: Node2D) -> void:
	if body != player or not has_started or level_completed:
		return
	
	if attention_score < 0.5:
		_show_msg("Need attention > 0.5!", Color(1.0, 0.7, 0.3))
		return
	
	_complete()

func _update_ui() -> void:
	player.magnitude = attention_score
	if health_bar_fill:
		health_bar_fill.scale.x = clampf(attention_score, 0, 1)
		if attention_score < 0.25:
			health_bar_fill.color = Color(1, 0.3, 0.3)
		elif attention_score < 0.5:
			health_bar_fill.color = Color(1, 0.7, 0.3)
		else:
			health_bar_fill.color = Color(0.5, 0.8, 1.0)
	
	# Update the value label
	if activation_value_label:
		activation_value_label.text = "%.2f" % attention_score
		if attention_score < 0.5:
			activation_value_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 1.0))
		else:
			activation_value_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7, 1.0))
	
	if phase_label:
		var phases = ["Embedding", "Encoder Attn", "Encoder FF", "Decoder Attn", "Decoder FF", "Output"]
		if current_phase < phases.size():
			phase_label.text = "Phase: " + phases[current_phase]

func _show_msg(text: String, color: Color) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.global_position = player.global_position + Vector2(-40, -50)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	lbl.z_index = 100
	add_child(lbl)
	
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

func _reset_attention_blocks() -> void:
	# Restore all Q/K/V blocks to initial state (like first entering the level)
	if not has_meta("attention_blocks"):
		return
	var blocks: Array = get_meta("attention_blocks")
	for block in blocks:
		if not is_instance_valid(block):
			continue
		block.set_meta("q_collected", false)
		block.set_meta("k_collected", false)
		block.set_meta("v_available", false)
		block.set_meta("v_collected", false)
		var q_node = block.get_node_or_null("Q")
		var k_node = block.get_node_or_null("K")
		var v_node = block.get_node_or_null("V")
		var arrow = block.get_node_or_null("AttentionArrow")
		var arrow_glow = block.get_node_or_null("AttentionArrowGlow")
		var formula = block.get_node_or_null("Formula")
		var check = block.get_node_or_null("Check")
		if q_node:
			q_node.modulate.a = 1.0
		if k_node:
			k_node.modulate.a = 1.0
		if v_node:
			v_node.modulate.a = 0.0
		if arrow:
			arrow.modulate.a = 0.0
		if arrow_glow:
			arrow_glow.modulate.a = 0.0
		if formula:
			formula.modulate.a = 0.0
		if check:
			check.modulate.a = 0.0

func _restart() -> void:
	level_completed = false
	has_started = false
	player_was_started = false
	current_phase = 0
	attention_score = 0.5
	queries_collected = 0
	keys_matched = 0
	masks_hit = 0
	
	player.global_position = Vector2(START_X - 100, BASE_Y)
	player.velocity = Vector2.ZERO
	player.has_started = false
	player.gradient_active = false
	player.magnitude = attention_score
	
	# Recreate embedding visual (same as first enter)
	player_is_embedding = true
	_create_embedding_visual()
	
	# Reset all attention blocks so Q/K visible, V/arrow/formula/check hidden (like first enter)
	_reset_attention_blocks()
	
	# Restore start label
	if start_label:
		start_label.text = "START >"
		start_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	
	_update_ui()

func _complete() -> void:
	level_completed = true
	
	var confidence = clampf(attention_score, 0.0001, 0.9999)
	var bce_loss = -log(confidence)
	
	if LevelManager:
		LevelManager.complete_level("transformer", bce_loss)
	
	var complete_label = Label.new()
	complete_label.text = "TRANSFORMER COMPLETE!\n\nPredicting: 'cat'\nConfidence: %.2f\nCross-Entropy: %.3f" % [confidence, bce_loss]
	complete_label.add_theme_font_size_override("font_size", 24)
	complete_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	complete_label.position = player.global_position + Vector2(80, -80)
	add_child(complete_label)
	
	var badge = BADGE_SCENE.instantiate()
	badge.modulate.a = 0
	if sidebar and sidebar.has_method("add_badge"):
		sidebar.add_badge(badge)
	var tw = create_tween()
	tw.tween_property(badge, "modulate:a", 1.0, 0.3)
	
	# Show play again button after a short delay
	await get_tree().create_timer(1.0).timeout
	_create_play_again_button()

func _create_play_again_button() -> void:
	var restart_btn = Node2D.new()
	restart_btn.position = player.global_position + Vector2(300, 0)
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
	_restart()
