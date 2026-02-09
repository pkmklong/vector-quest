extends Control

## Sidebar UI showing level progression

signal level_selected(level_id: String)
signal menu_pressed

@onready var level_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/LevelList
@onready var badge_container: VBoxContainer = $Panel/MarginContainer/VBoxContainer/BadgeSection/BadgeContainer
@onready var menu_button: Button = $Panel/MarginContainer/VBoxContainer/MenuButton
@onready var restart_button: Button = $Panel/MarginContainer/VBoxContainer/RestartButton

var level_items: Dictionary = {}  # level_id -> Control node

func _ready() -> void:
	_build_level_list()
	
	if menu_button:
		menu_button.pressed.connect(_on_menu_button_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)
	
	# Connect to level manager signals
	if LevelManager:
		LevelManager.level_completed.connect(_on_level_completed)
		LevelManager.level_unlocked.connect(_on_level_unlocked)

func _on_menu_button_pressed() -> void:
	menu_pressed.emit()
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")

func _on_restart_button_pressed() -> void:
	# Clear best BCE and completed state for all levels, then reload current level
	if LevelManager:
		LevelManager.reset_all_progress()
		var level_data = LevelManager.get_level(LevelManager.current_level_id)
		if not level_data.is_empty():
			get_tree().change_scene_to_file(level_data["scene"])

func _build_level_list() -> void:
	# Clear existing
	for child in level_list.get_children():
		child.queue_free()
	level_items.clear()
	
	# Build level entries
	for level in LevelManager.get_all_levels():
		var item := _create_level_item(level)
		level_list.add_child(item)
		level_items[level["id"]] = item

func _create_level_item(level: Dictionary) -> Control:
	var container := PanelContainer.new()
	container.name = level["id"]
	
	# Style based on state
	var style := StyleBoxFlat.new()
	if level["id"] == LevelManager.current_level_id:
		style.bg_color = Color(0.2, 0.4, 0.6, 0.8)  # Current level - blue
	elif level["completed"]:
		style.bg_color = Color(0.15, 0.35, 0.2, 0.8)  # Completed - green
	elif level["unlocked"]:
		style.bg_color = Color(0.2, 0.2, 0.25, 0.8)  # Unlocked - dark
	else:
		style.bg_color = Color(0.1, 0.1, 0.12, 0.6)  # Locked - darker
	
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	container.add_theme_stylebox_override("panel", style)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	container.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	
	# Level name row
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)
	
	# Badge/status icon
	var status_label := Label.new()
	if level["completed"]:
		status_label.text = "DONE "
		status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	elif level["unlocked"]:
		status_label.text = "> "
		status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	else:
		status_label.text = "LOCK "
		status_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	status_label.add_theme_font_size_override("font_size", 14)
	name_row.add_child(status_label)
	
	# Level name
	var name_label := Label.new()
	name_label.text = level["name"]
	name_label.add_theme_font_size_override("font_size", 16)
	if level["unlocked"]:
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	else:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	name_row.add_child(name_label)
	
	# Score row (if completed)
	if level["completed"] and level["best_bce"] >= 0:
		var score_label := Label.new()
		score_label.text = "Best BCE: %.3f  |  Runs: %d" % [level["best_bce"], level["runs"]]
		score_label.add_theme_font_size_override("font_size", 12)
		score_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
		vbox.add_child(score_label)
	elif not level["unlocked"]:
		var locked_label := Label.new()
		locked_label.text = "Complete previous to unlock"
		locked_label.add_theme_font_size_override("font_size", 11)
		locked_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		vbox.add_child(locked_label)
	
	# Make clickable if unlocked
	if level["unlocked"]:
		container.mouse_filter = Control.MOUSE_FILTER_STOP
		container.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				level_selected.emit(level["id"])
		)
	
	return container

func _on_level_completed(_level_id: String, _bce_score: float) -> void:
	_build_level_list()

func _on_level_unlocked(_level_id: String) -> void:
	_build_level_list()

func update_current_level() -> void:
	_build_level_list()

func get_badge_container() -> VBoxContainer:
	return badge_container

func add_badge(badge_node: Control) -> void:
	if badge_container:
		badge_container.add_child(badge_node)
