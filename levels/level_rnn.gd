extends Node2D

const LEVEL_SIDEBAR_SCENE = preload("res://ui/level_sidebar.tscn")
const BADGE_SCENE = preload("res://ui/badge.tscn")

@onready var player: CharacterBody2D = $Player
@onready var ui_layer: CanvasLayer = $UILayer
@onready var health_bar_fill: ColorRect = $UILayer/HealthBar/BarFill
@onready var time_step_label: Label = $UILayer/TimeStepLabel

var sidebar: Control
var level_completed := false
var has_started := false
var player_was_started := false  # Track for restart detection
var complete_label: Label = null  # Completion message label
var play_again_btn: Node2D = null  # Play again button
var current_cell := 0
var cell_state := 0.5

var forget_gates := []
var input_gates := []
var x_collectibles := []  # Input data collectibles
var i_collectibles := []  # Input gate collectibles
var start_label: Label  # Reference to START/RESTART label

const TOTAL_CELLS := 4
const CELL_WIDTH := 350.0
const CELL_HEIGHT := 150.0
const CELL_SPACING := 30.0
const START_X := -250.0
const BASE_Y := 250.0

func _ready() -> void:
	# Add sidebar
	sidebar = LEVEL_SIDEBAR_SCENE.instantiate()
	sidebar.level_selected.connect(_on_level_selected)
	ui_layer.add_child(sidebar)
	
	# Create cells
	_create_cells()
	
	# Add "c" label to health bar (cell state)
	var c_label = Label.new()
	c_label.text = "c:"
	c_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	c_label.offset_left = -245
	c_label.offset_top = 18
	c_label.add_theme_font_size_override("font_size", 16)
	c_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
	ui_layer.add_child(c_label)
	
	# Add "h" label for player (hidden state)
	var h_label = Label.new()
	h_label.text = "You = h (hidden state)"
	h_label.position = Vector2(START_X - 100, BASE_Y + 50)
	h_label.add_theme_font_size_override("font_size", 14)
	h_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4, 0.8))
	add_child(h_label)
	
	# Position player
	player.global_position = Vector2(START_X - 100, BASE_Y)
	player.spawn_position = player.global_position
	var top_y = BASE_Y - (TOTAL_CELLS - 1) * (CELL_HEIGHT + CELL_SPACING)
	# Expanded bounds to allow flying beyond output after completion
	player.network_bounds = Rect2(START_X - 200, top_y - 400, CELL_WIDTH + 600, BASE_Y - top_y + 600)
	player.magnitude = cell_state
	player.has_started = false
	player.gradient_active = false
	
	_update_ui()

func _on_level_selected(level_id: String) -> void:
	if level_id != "rnn" and LevelManager.is_level_unlocked(level_id):
		var level_data = LevelManager.get_level(level_id)
		if not level_data.is_empty():
			LevelManager.set_current_level(level_id)
			get_tree().change_scene_to_file(level_data["scene"])

func _process(_delta: float) -> void:
	var t = float(Time.get_ticks_msec()) / 1000.0
	
	for gate in forget_gates:
		var node = gate["node"]
		# Random 2D movement within cell - but stay away from left (spawn area)
		var off_y = sin(t * 2.0 + gate["phase"]) * gate["range_y"]
		var off_x = sin(t * 1.3 + gate["phase"] * 0.7) * gate["range_x"]
		node.position.x = gate["base_x"] + off_x
		node.position.y = gate["base_y"] + off_y
	
	for gate in input_gates:
		var node = gate["node"]
		var off = sin(t * 1.5 + gate["phase"]) * gate["range"]
		node.position.x = gate["base_x"] + off
	
	# Pulse x collectibles (glow effect)
	for x_data in x_collectibles:
		if not x_data["collected"]:
			var pulse = 0.7 + 0.3 * sin(t * 4.0 + x_data["cell_idx"] * 1.5)
			x_data["node"].modulate = Color(1, 1, 1, pulse)
	
	# Pulse i collectibles (glow effect)
	for i_data in i_collectibles:
		if not i_data["collected"]:
			var pulse = 0.7 + 0.3 * sin(t * 3.5 + i_data["cell_idx"] * 2.0)
			i_data["node"].modulate = Color(1, 1, 1, pulse)
	
	# Track start state for restart detection
	if has_started and not player_was_started:
		player_was_started = true
		# Update label to show restart option
		if start_label:
			start_label.text = "< RESTART"
			start_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 0.9))
	
	# Check for restart (player flies back past start zone AND is near cell 0)
	# Only restart if player is at the first cell's y level, not when teleported to other cells
	var start_zone_x = START_X - 20  # Where start zone collision is
	var player_before_start = player.global_position.x < start_zone_x - 40
	var near_first_cell = absf(player.global_position.y - BASE_Y) < CELL_HEIGHT  # Within cell 0's y range
	if player_was_started and player_before_start and near_first_cell and current_cell == 0:
		_restart()

func _create_cells() -> void:
	for i in range(TOTAL_CELLS):
		var y = BASE_Y - i * (CELL_HEIGHT + CELL_SPACING)
		
		# Cell outer glow
		var glow = ColorRect.new()
		glow.size = Vector2(CELL_WIDTH + 8, CELL_HEIGHT + 8)
		glow.position = Vector2(START_X - 4, y - CELL_HEIGHT / 2 - 4)
		glow.color = Color(0.9, 0.5, 0.3, 0.15)
		glow.z_index = -7
		add_child(glow)
		
		# Cell border
		var border = ColorRect.new()
		border.size = Vector2(CELL_WIDTH + 4, CELL_HEIGHT + 4)
		border.position = Vector2(START_X - 2, y - CELL_HEIGHT / 2 - 2)
		border.color = Color(0.9, 0.6, 0.4, 0.4)
		border.z_index = -6
		add_child(border)
		
		# Cell box (main)
		var box = ColorRect.new()
		box.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
		box.position = Vector2(START_X, y - CELL_HEIGHT / 2)
		box.color = Color(0.08, 0.06, 0.12, 0.95)
		box.z_index = -5
		add_child(box)
		
		# Inner gradient effect (top highlight)
		var highlight = ColorRect.new()
		highlight.size = Vector2(CELL_WIDTH - 20, 3)
		highlight.position = Vector2(START_X + 10, y - CELL_HEIGHT / 2 + 5)
		highlight.color = Color(0.9, 0.6, 0.4, 0.2)
		highlight.z_index = -4
		add_child(highlight)
		
		# Add barriers to keep player inside cell (top, bottom, left after entry)
		_create_cell_barriers(y, i)
		
		# Cell label with time subscript
		var lbl = Label.new()
		lbl.text = "LSTM Cell"
		lbl.position = Vector2(START_X + 10, y - CELL_HEIGHT / 2 + 12)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.5, 0.4, 0.8))
		add_child(lbl)
		
		# Time step badge
		var t_bg = ColorRect.new()
		t_bg.size = Vector2(50, 24)
		t_bg.position = Vector2(START_X + CELL_WIDTH - 60, y - CELL_HEIGHT / 2 + 8)
		t_bg.color = Color(0.9, 0.5, 0.3, 0.3)
		add_child(t_bg)
		
		var t_lbl = Label.new()
		t_lbl.text = "t=" + str(i + 1)
		t_lbl.position = Vector2(START_X + CELL_WIDTH - 52, y - CELL_HEIGHT / 2 + 10)
		t_lbl.add_theme_font_size_override("font_size", 16)
		t_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
		add_child(t_lbl)
		
		# Forget gate (red) - positioned in right half of cell (away from spawn)
		var f_cont = Node2D.new()
		f_cont.position = Vector2(START_X + CELL_WIDTH / 2 + 20, y)
		add_child(f_cont)
		
		# Forget gate glow
		var f_glow = ColorRect.new()
		f_glow.size = Vector2(58, 58)
		f_glow.position = Vector2(-29, -29)
		f_glow.color = Color(1.0, 0.2, 0.2, 0.25)
		f_cont.add_child(f_glow)
		
		var f_box = ColorRect.new()
		f_box.size = Vector2(50, 50)
		f_box.position = Vector2(-25, -25)
		f_box.color = Color(0.7, 0.15, 0.15, 0.95)
		f_cont.add_child(f_box)
		
		# Inner border
		var f_inner = ColorRect.new()
		f_inner.size = Vector2(44, 44)
		f_inner.position = Vector2(-22, -22)
		f_inner.color = Color(0.9, 0.25, 0.25, 0.9)
		f_cont.add_child(f_inner)
		
		var f_lbl = Label.new()
		f_lbl.text = "f"
		f_lbl.position = Vector2(-8, -12)
		f_lbl.add_theme_font_size_override("font_size", 22)
		f_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		f_cont.add_child(f_lbl)
		
		# Subscript "t"
		var f_sub = Label.new()
		f_sub.text = "t"
		f_sub.position = Vector2(4, -4)
		f_sub.add_theme_font_size_override("font_size", 12)
		f_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		f_cont.add_child(f_sub)
		
		var f_area = Area2D.new()
		f_area.collision_layer = 0
		f_area.collision_mask = 1
		f_area.monitoring = true
		var f_coll = CollisionShape2D.new()
		var f_shape = RectangleShape2D.new()
		f_shape.size = Vector2(50, 50)
		f_coll.shape = f_shape
		f_area.add_child(f_coll)
		f_area.body_entered.connect(_on_forget.bind(i))
		f_cont.add_child(f_area)
		
		# Position forget gate in right half of cell (away from spawn on left)
		# base_x is center of movement range, range_x is how far it can move left/right
		var f_base_x = START_X + CELL_WIDTH / 2 + 20  # Center-right of cell
		var f_range_x = 60.0  # Can move 60px left/right from center
		var f_range_y = 50.0  # Can move 50px up/down
		forget_gates.append({"node": f_cont, "base_x": f_base_x, "base_y": y, "range_x": f_range_x, "range_y": f_range_y, "phase": i * 1.5})
		
		# Input gate (green) - styled
		var i_cont = Node2D.new()
		i_cont.position = Vector2(START_X + CELL_WIDTH - 95, y)
		add_child(i_cont)
		
		# Input gate glow (cool blue)
		var i_glow = ColorRect.new()
		i_glow.size = Vector2(58, 58)
		i_glow.position = Vector2(-29, -29)
		i_glow.color = Color(0.2, 0.5, 1.0, 0.25)
		i_cont.add_child(i_glow)
		
		var i_box = ColorRect.new()
		i_box.size = Vector2(50, 50)
		i_box.position = Vector2(-25, -25)
		i_box.color = Color(0.12, 0.35, 0.7, 0.95)
		i_cont.add_child(i_box)
		
		# Inner border
		var i_inner = ColorRect.new()
		i_inner.size = Vector2(44, 44)
		i_inner.position = Vector2(-22, -22)
		i_inner.color = Color(0.2, 0.5, 0.9, 0.9)
		i_cont.add_child(i_inner)
		
		var i_lbl = Label.new()
		i_lbl.text = "i"
		i_lbl.position = Vector2(-6, -12)
		i_lbl.add_theme_font_size_override("font_size", 22)
		i_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		i_cont.add_child(i_lbl)
		
		# Subscript "t"
		var i_sub = Label.new()
		i_sub.text = "t"
		i_sub.position = Vector2(4, -4)
		i_sub.add_theme_font_size_override("font_size", 12)
		i_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		i_cont.add_child(i_sub)
		
		# "COLLECT" label above i
		var i_collect_lbl = Label.new()
		i_collect_lbl.text = "COLLECT"
		i_collect_lbl.position = Vector2(-32, -50)
		i_collect_lbl.add_theme_font_size_override("font_size", 12)
		i_collect_lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 0.9))
		i_cont.add_child(i_collect_lbl)
		
		var i_area = Area2D.new()
		i_area.collision_layer = 0
		i_area.collision_mask = 1
		i_area.monitoring = true
		var i_coll = CollisionShape2D.new()
		var i_shape = RectangleShape2D.new()
		i_shape.size = Vector2(50, 50)
		i_coll.shape = i_shape
		i_area.add_child(i_coll)
		i_area.body_entered.connect(_on_i_collected.bind(i, i_cont))
		i_cont.add_child(i_area)
		
		input_gates.append({"node": i_cont, "base_x": START_X + CELL_WIDTH - 95, "base_y": y, "range": 45.0, "phase": i * 2.0 + 1.0})
		i_collectibles.append({"node": i_cont, "cell_idx": i, "collected": false})
		
		# x collectible (input data) - positioned in center of cell, prominent
		var x_cont = Node2D.new()
		x_cont.position = Vector2(START_X + CELL_WIDTH / 2, y)
		add_child(x_cont)
		
		# Outer glow (green, more intense, pulsing in _process)
		var x_glow_outer = ColorRect.new()
		x_glow_outer.size = Vector2(70, 70)
		x_glow_outer.position = Vector2(-35, -35)
		x_glow_outer.color = Color(0.2, 1.0, 0.4, 0.2)
		x_cont.add_child(x_glow_outer)
		
		# Middle glow
		var x_glow_mid = ColorRect.new()
		x_glow_mid.size = Vector2(58, 58)
		x_glow_mid.position = Vector2(-29, -29)
		x_glow_mid.color = Color(0.3, 1.0, 0.5, 0.3)
		x_cont.add_child(x_glow_mid)
		
		# Inner glow
		var x_glow = ColorRect.new()
		x_glow.size = Vector2(48, 48)
		x_glow.position = Vector2(-24, -24)
		x_glow.color = Color(0.4, 1.0, 0.5, 0.4)
		x_cont.add_child(x_glow)
		
		# x orb (green core)
		var x_orb = ColorRect.new()
		x_orb.size = Vector2(40, 40)
		x_orb.position = Vector2(-20, -20)
		x_orb.color = Color(0.3, 0.9, 0.45, 0.95)
		x_cont.add_child(x_orb)
		
		# x label (bigger)
		var x_lbl = Label.new()
		x_lbl.text = "x"
		x_lbl.position = Vector2(-9, -14)
		x_lbl.add_theme_font_size_override("font_size", 24)
		x_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		x_cont.add_child(x_lbl)
		
		# "COLLECT" label above (green to match x)
		var collect_lbl = Label.new()
		collect_lbl.text = "COLLECT"
		collect_lbl.position = Vector2(-32, -50)
		collect_lbl.add_theme_font_size_override("font_size", 12)
		collect_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6, 0.9))
		x_cont.add_child(collect_lbl)
		
		# x collision (bigger)
		var x_area = Area2D.new()
		x_area.collision_layer = 0
		x_area.collision_mask = 1
		x_area.monitoring = true
		var x_coll = CollisionShape2D.new()
		var x_shape = RectangleShape2D.new()
		x_shape.size = Vector2(40, 40)
		x_coll.shape = x_shape
		x_area.add_child(x_coll)
		x_area.body_entered.connect(_on_x_collected.bind(i, x_cont))
		x_cont.add_child(x_area)
		
		x_collectibles.append({"node": x_cont, "cell_idx": i, "collected": false})
		
		# Start zone
		if i == 0:
			start_label = Label.new()
			start_label.text = "START >"
			start_label.position = Vector2(START_X - 100, y - 10)
			start_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
			start_label.add_theme_font_size_override("font_size", 18)
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
			narrative.text = "Your goal is to keep cell state above the threshold by the time you reach the output—you are predicting the next token.\n\nAvoid the forget gate (f)—it lowers cell state. Collect input (i) and hidden state (x) in each cell to build state.\n\nComplete the run with the lowest BCE you can."
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
			avoid_label.text = "Avoid: f (forget gate)"
			avoid_label.add_theme_font_size_override("font_size", 14)
			avoid_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
			legend_container.add_child(avoid_label)
			
			var collect_label = Label.new()
			collect_label.text = "Collect: i and x"
			collect_label.add_theme_font_size_override("font_size", 14)
			collect_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
			legend_container.add_child(collect_label)
			
			var goal_label = Label.new()
			goal_label.text = "Goal: cell state > 0.25"
			goal_label.add_theme_font_size_override("font_size", 14)
			goal_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
			legend_container.add_child(goal_label)
			
			var s_area = Area2D.new()
			s_area.collision_layer = 0
			s_area.collision_mask = 1
			s_area.monitoring = true
			var s_coll = CollisionShape2D.new()
			var s_shape = RectangleShape2D.new()
			s_shape.size = Vector2(40, CELL_HEIGHT)
			s_coll.shape = s_shape
			s_area.add_child(s_coll)
			s_area.position = Vector2(START_X - 20, y)
			s_area.body_entered.connect(_on_start)
			add_child(s_area)
		
		# Exit zone with visual
		var exit_x = START_X + CELL_WIDTH + 10
		
		# Exit zone glow
		var exit_glow = ColorRect.new()
		exit_glow.size = Vector2(30, CELL_HEIGHT - 20)
		exit_glow.position = Vector2(exit_x, y - CELL_HEIGHT / 2 + 10)
		exit_glow.color = Color(0.4, 0.9, 0.5, 0.2)
		add_child(exit_glow)
		
		# Exit zone collision - detect player
		var e_area = Area2D.new()
		e_area.collision_layer = 0  # Don't collide with anything
		e_area.collision_mask = 1  # Detect layer 1 (player)
		e_area.monitoring = true
		var e_coll = CollisionShape2D.new()
		var e_shape = RectangleShape2D.new()
		e_shape.size = Vector2(40, CELL_HEIGHT)
		e_coll.shape = e_shape
		e_area.add_child(e_coll)
		e_area.position = Vector2(exit_x + 15, y)
		e_area.body_entered.connect(_on_exit.bind(i))
		add_child(e_area)
		
		# Exit arrow label
		var exit_lbl = Label.new()
		if i < TOTAL_CELLS - 1:
			exit_lbl.text = ">"
		else:
			exit_lbl.text = ">"
		exit_lbl.position = Vector2(exit_x + 5, y - 12)
		exit_lbl.add_theme_font_size_override("font_size", 22)
		exit_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6, 0.8))
		add_child(exit_lbl)
	
	# Arrows between cells - recurrent connections with arrowheads
	for i in range(TOTAL_CELLS - 1):
		var y1 = BASE_Y - i * (CELL_HEIGHT + CELL_SPACING)
		var y2 = BASE_Y - (i + 1) * (CELL_HEIGHT + CELL_SPACING)
		var mid_y = (y1 + y2) / 2
		
		# Outer glow line - curves around to left of next cell
		var glow = Line2D.new()
		glow.add_point(Vector2(START_X + CELL_WIDTH + 30, y1))
		glow.add_point(Vector2(START_X + CELL_WIDTH + 70, mid_y))
		glow.add_point(Vector2(START_X - 80, y2))  # Left of next cell (outside barriers)
		glow.width = 12
		glow.default_color = Color(0.9, 0.5, 0.3, 0.15)
		glow.z_index = -3
		add_child(glow)
		
		# Main arrow line
		var arrow = Line2D.new()
		arrow.add_point(Vector2(START_X + CELL_WIDTH + 30, y1))
		arrow.add_point(Vector2(START_X + CELL_WIDTH + 70, mid_y))
		arrow.add_point(Vector2(START_X - 80, y2))  # Left of next cell (outside barriers)
		arrow.width = 4
		arrow.default_color = Color(0.95, 0.6, 0.35, 0.8)
		arrow.z_index = -2
		add_child(arrow)
		
		# Arrowhead at end (pointing right into cell)
		var head_pos = Vector2(START_X - 80, y2)
		var head_dir = Vector2(1, 0).normalized()  # Pointing right, toward cell
		_draw_arrowhead(head_pos, head_dir, Color(0.95, 0.6, 0.35, 0.9))
		
		# Flow dots along the path
		_add_flow_indicator(Vector2(START_X + CELL_WIDTH + 50, y1 - 15), i)
		
		# "h" label for hidden state
		var h_lbl = Label.new()
		h_lbl.text = "h"
		h_lbl.position = Vector2(START_X + CELL_WIDTH + 75, mid_y - 12)
		h_lbl.add_theme_font_size_override("font_size", 16)
		h_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.5, 0.8))
		add_child(h_lbl)
		
		var h_sub = Label.new()
		h_sub.text = str(i + 1)
		h_sub.position = Vector2(START_X + CELL_WIDTH + 85, mid_y - 6)
		h_sub.add_theme_font_size_override("font_size", 10)
		h_sub.add_theme_color_override("font_color", Color(0.95, 0.7, 0.5, 0.6))
		add_child(h_sub)
	
	# Output zone - simple label
	var top_y = BASE_Y - (TOTAL_CELLS - 1) * (CELL_HEIGHT + CELL_SPACING)
	
	var out_lbl = Label.new()
	out_lbl.text = "output"
	out_lbl.position = Vector2(START_X + CELL_WIDTH + 50, top_y - 12)
	out_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6, 0.9))
	out_lbl.add_theme_font_size_override("font_size", 20)
	add_child(out_lbl)
	
	# Formula - styled card
	_create_formula_display()

func _draw_arrowhead(pos: Vector2, dir: Vector2, col: Color) -> void:
	var size = 14.0
	var angle = 0.5  # radians
	
	# Calculate arrowhead points
	var left = dir.rotated(PI - angle) * size
	var right = dir.rotated(PI + angle) * size
	
	var head = Line2D.new()
	head.add_point(pos + left)
	head.add_point(pos)
	head.add_point(pos + right)
	head.width = 4
	head.default_color = col
	head.z_index = -1
	add_child(head)

func _add_flow_indicator(pos: Vector2, idx: int) -> void:
	# Small animated chevrons to show flow direction
	for j in range(3):
		var chev = Label.new()
		chev.text = ">"
		chev.position = pos + Vector2(j * 12, j * 8)
		chev.add_theme_font_size_override("font_size", 14)
		chev.add_theme_color_override("font_color", Color(0.95, 0.6, 0.35, 0.4 - j * 0.1))
		chev.rotation = 0.8  # Angle towards next cell
		add_child(chev)

func _create_cell_barriers(y: float, cell_idx: int) -> void:
	var barrier_thickness = 20.0
	
	# Top barrier - only covers cell width, not extended to left
	var top_barrier = StaticBody2D.new()
	var top_coll = CollisionShape2D.new()
	var top_shape = RectangleShape2D.new()
	top_shape.size = Vector2(CELL_WIDTH, barrier_thickness)
	top_coll.shape = top_shape
	top_barrier.add_child(top_coll)
	top_barrier.position = Vector2(START_X + CELL_WIDTH / 2, y - CELL_HEIGHT / 2 - barrier_thickness / 2)
	add_child(top_barrier)
	
	# Bottom barrier - only covers cell width, not extended to left
	var bot_barrier = StaticBody2D.new()
	var bot_coll = CollisionShape2D.new()
	var bot_shape = RectangleShape2D.new()
	bot_shape.size = Vector2(CELL_WIDTH, barrier_thickness)
	bot_coll.shape = bot_shape
	bot_barrier.add_child(bot_coll)
	bot_barrier.position = Vector2(START_X + CELL_WIDTH / 2, y + CELL_HEIGHT / 2 + barrier_thickness / 2)
	add_child(bot_barrier)
	
	# Right barrier - stops player at exit zone (only for non-final cells)
	# Final cell has no right barrier so player can fly beyond output after completion
	if cell_idx < TOTAL_CELLS - 1:
		var right_barrier = StaticBody2D.new()
		var right_coll = CollisionShape2D.new()
		var right_shape = RectangleShape2D.new()
		right_shape.size = Vector2(barrier_thickness, CELL_HEIGHT)
		right_coll.shape = right_shape
		right_barrier.add_child(right_coll)
		right_barrier.position = Vector2(START_X + CELL_WIDTH + 50, y)  # Just past exit zone
		add_child(right_barrier)
	
	# No left barrier - player enters from left via recurrent connection

func _create_formula_display() -> void:
	var form_y = BASE_Y + CELL_HEIGHT / 2 + 50
	
	# Formula with color-coded elements matching visuals
	# c = f*c + i*x
	var base_x = START_X + CELL_WIDTH / 2 - 80
	
	# "c" (cell state - orange like health bar)
	var c1 = Label.new()
	c1.text = "c"
	c1.position = Vector2(base_x, form_y)
	c1.add_theme_font_size_override("font_size", 18)
	c1.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
	add_child(c1)
	
	# "="
	var eq = Label.new()
	eq.text = "="
	eq.position = Vector2(base_x + 18, form_y)
	eq.add_theme_font_size_override("font_size", 18)
	eq.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	add_child(eq)
	
	# "f" (forget - red)
	var f1 = Label.new()
	f1.text = "f"
	f1.position = Vector2(base_x + 35, form_y)
	f1.add_theme_font_size_override("font_size", 18)
	f1.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	add_child(f1)
	
	# "*c"
	var c2 = Label.new()
	c2.text = "*c"
	c2.position = Vector2(base_x + 47, form_y)
	c2.add_theme_font_size_override("font_size", 18)
	c2.add_theme_color_override("font_color", Color(0.9, 0.6, 0.4))
	add_child(c2)
	
	# "+"
	var plus = Label.new()
	plus.text = "+"
	plus.position = Vector2(base_x + 75, form_y)
	plus.add_theme_font_size_override("font_size", 18)
	plus.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	add_child(plus)
	
	# "i" (input gate - blue)
	var i1 = Label.new()
	i1.text = "i"
	i1.position = Vector2(base_x + 95, form_y)
	i1.add_theme_font_size_override("font_size", 18)
	i1.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
	add_child(i1)
	
	# "*x" (input data - green)
	var x1 = Label.new()
	x1.text = "*x"
	x1.position = Vector2(base_x + 105, form_y)
	x1.add_theme_font_size_override("font_size", 18)
	x1.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	add_child(x1)

func _on_start(body: Node2D) -> void:
	if body != player or has_started:
		return
	has_started = true
	player.has_started = true
	player.gradient_active = true
	_show_msg("Cell 1 - GO!", Color(0.4, 1.0, 0.6))
	_update_ui()

func _on_exit(body: Node2D, idx: int) -> void:
	if body != player or not has_started or level_completed:
		return
	if idx != current_cell:
		return
	
	# Check if both i and x were collected in this cell - required to unlock exit
	var i_collected = false
	var x_collected = false
	
	for i_data in i_collectibles:
		if i_data["cell_idx"] == current_cell and i_data["collected"]:
			i_collected = true
			break
	
	for x_data in x_collectibles:
		if x_data["cell_idx"] == current_cell and x_data["collected"]:
			x_collected = true
			break
	
	if not i_collected and not x_collected:
		_show_msg("Collect i and x!", Color(0.5, 0.9, 0.8))
		return
	elif not i_collected:
		_show_msg("Collect i!", Color(0.4, 0.7, 1.0))
		return
	elif not x_collected:
		_show_msg("Collect x!", Color(0.4, 1.0, 0.5))
		return
	
	if current_cell >= TOTAL_CELLS - 1:
		if cell_state < 0.25:
			_show_msg("VANISHING GRADIENT!", Color(0.8, 0.3, 0.9))
			await get_tree().create_timer(1.5).timeout
			if not level_completed:
				_restart()
		else:
			_complete()
		return
	
	cell_state *= 0.95
	current_cell += 1
	var next_y = BASE_Y - current_cell * (CELL_HEIGHT + CELL_SPACING)
	player.global_position = Vector2(START_X - 80, next_y)  # Outside cell and barriers, enter from left
	player.velocity = Vector2.ZERO  # Stop momentum
	_show_msg("Cell " + str(current_cell + 1) + " OK!", Color(0.4, 1.0, 0.6))
	_update_ui()

func _on_forget(body: Node2D, idx: int) -> void:
	if body != player or not has_started or level_completed or idx != current_cell:
		return
	cell_state -= 0.15
	cell_state = maxf(cell_state, 0)
	_show_msg("f*c: -15%", Color(1.0, 0.4, 0.4))
	_update_ui()
	if cell_state <= 0:
		_show_msg("MEMORY LOST!", Color(1.0, 0.3, 0.3))
		await get_tree().create_timer(1.5).timeout
		if not level_completed:
			_restart()

func _on_i_collected(body: Node2D, cell_idx: int, i_node: Node2D) -> void:
	if body != player or not has_started or level_completed or cell_idx != current_cell:
		return
	
	# Check if already collected
	for i_data in i_collectibles:
		if i_data["node"] == i_node and i_data["collected"]:
			return
	
	# Mark as collected
	for i_data in i_collectibles:
		if i_data["node"] == i_node:
			i_data["collected"] = true
	
	_show_msg("i collected!", Color(0.4, 0.7, 1.0))
	
	# Fade out
	var tw = create_tween()
	tw.tween_property(i_node, "modulate:a", 0.3, 0.3)
	
	# Check if both i and x collected - give bonus
	_check_ix_bonus()

func _on_x_collected(body: Node2D, cell_idx: int, x_node: Node2D) -> void:
	if body != player or not has_started or level_completed or cell_idx != current_cell:
		return
	
	# Check if already collected
	for x_data in x_collectibles:
		if x_data["node"] == x_node and x_data["collected"]:
			return
	
	# Mark as collected
	for x_data in x_collectibles:
		if x_data["node"] == x_node:
			x_data["collected"] = true
	
	_show_msg("x collected!", Color(0.4, 1.0, 0.5))
	
	# Fade out the x
	var tw = create_tween()
	tw.tween_property(x_node, "modulate:a", 0.3, 0.3)
	
	# Check if both i and x collected - give bonus
	_check_ix_bonus()

func _check_ix_bonus() -> void:
	# Check if both i and x are collected in current cell
	var i_collected = false
	var x_collected = false
	
	for i_data in i_collectibles:
		if i_data["cell_idx"] == current_cell and i_data["collected"]:
			i_collected = true
			break
	
	for x_data in x_collectibles:
		if x_data["cell_idx"] == current_cell and x_data["collected"]:
			x_collected = true
			break
	
	if i_collected and x_collected:
		# Both collected! Give i*x bonus
		cell_state += 0.12
		cell_state = minf(cell_state, 1.0)
		_show_msg("i*x: +12%", Color(0.5, 0.9, 0.8))
		_update_ui()

func _update_ui() -> void:
	player.magnitude = cell_state
	if health_bar_fill:
		health_bar_fill.scale.x = clampf(cell_state, 0, 1)
		if cell_state < 0.25:
			health_bar_fill.color = Color(1, 0.3, 0.3)
		elif cell_state < 0.5:
			health_bar_fill.color = Color(1, 0.7, 0.3)
		else:
			health_bar_fill.color = Color(0.9, 0.6, 0.4)
	if time_step_label:
		if has_started:
			time_step_label.text = "Cell: " + str(current_cell + 1) + "/" + str(TOTAL_CELLS)
		else:
			time_step_label.text = "Cell: -/" + str(TOTAL_CELLS)

func _show_msg(txt: String, col: Color) -> void:
	var lbl = Label.new()
	lbl.text = txt
	lbl.position = player.global_position + Vector2(-50, -60)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", col)
	lbl.z_index = 100
	add_child(lbl)
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 40, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)

func _restart() -> void:
	level_completed = false
	has_started = false
	player_was_started = false
	current_cell = 0
	cell_state = 0.5
	
	# Remove completion label if exists
	if complete_label and is_instance_valid(complete_label):
		complete_label.queue_free()
		complete_label = null
	
	# Remove play again button if exists
	if play_again_btn and is_instance_valid(play_again_btn):
		play_again_btn.queue_free()
		play_again_btn = null
	
	player.global_position = Vector2(START_X - 100, BASE_Y)
	player.velocity = Vector2.ZERO
	player.has_started = false
	player.gradient_active = false
	player.magnitude = cell_state
	
	# Reset x collectibles
	for x_data in x_collectibles:
		x_data["collected"] = false
		x_data["node"].modulate.a = 1.0
	
	# Reset i collectibles
	for i_data in i_collectibles:
		i_data["collected"] = false
		i_data["node"].modulate.a = 1.0
	
	# Reset start label
	if start_label:
		start_label.text = "START >"
		start_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	
	_update_ui()

func _complete() -> void:
	level_completed = true
	
	# Calculate BCE loss (like language model predicting next token)
	var confidence = clampf(cell_state, 0.0001, 0.9999)
	var bce_loss = -log(confidence)
	
	if LevelManager:
		LevelManager.complete_level("rnn", bce_loss)
	
	# Show completion message to the right of the player (remove old one first)
	if complete_label and is_instance_valid(complete_label):
		complete_label.queue_free()
	complete_label = Label.new()
	complete_label.text = "LSTM COMPLETE!\n\nPredicting next token...\nConfidence: %.2f\nBCE Loss: %.3f" % [confidence, bce_loss]
	complete_label.add_theme_font_size_override("font_size", 24)
	complete_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	complete_label.position = player.global_position + Vector2(60, -60)  # To the right of player
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
	# Remove existing button if any
	if play_again_btn and is_instance_valid(play_again_btn):
		play_again_btn.queue_free()
	
	play_again_btn = Node2D.new()
	play_again_btn.position = player.global_position + Vector2(300, 0)
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
	_restart()
