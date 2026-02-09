extends Node

## GameManager - Handles browser focus/unfocus and global game state

var is_paused := false
var pause_overlay: ColorRect = null

func _ready() -> void:
	# Keep processing even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Connect to window focus signals for browser tab switching
	get_tree().root.focus_entered.connect(_on_window_focus_entered)
	get_tree().root.focus_exited.connect(_on_window_focus_exited)
	
	# Create pause overlay (hidden by default)
	_create_pause_overlay()

func _create_pause_overlay() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.02, 0.02, 0.04, 0.85)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	pause_overlay.z_index = 1000
	
	# Add "PAUSED" label
	var label := Label.new()
	label.text = "PAUSED"
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 0.9))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-80, -30)
	pause_overlay.add_child(label)
	
	# Add "Click to resume" hint
	var hint := Label.new()
	hint.text = "Click to resume"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER)
	hint.position = Vector2(-60, 30)
	pause_overlay.add_child(hint)
	
	# Add to scene tree as CanvasLayer so it's always on top
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(pause_overlay)
	add_child(canvas)

func _on_window_focus_entered() -> void:
	# Don't auto-resume, require click
	pass

func _on_window_focus_exited() -> void:
	_pause_game()

func _input(event: InputEvent) -> void:
	# Resume on click or key press when paused
	if is_paused:
		if event is InputEventMouseButton and event.pressed:
			_resume_game()
		elif event is InputEventKey and event.pressed:
			# Resume on Escape, Space, or Enter
			if event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
				_resume_game()

func _pause_game() -> void:
	if is_paused:
		return
	is_paused = true
	get_tree().paused = true
	if pause_overlay:
		pause_overlay.visible = true

func _resume_game() -> void:
	if not is_paused:
		return
	is_paused = false
	get_tree().paused = false
	if pause_overlay:
		pause_overlay.visible = false

func _notification(what: int) -> void:
	# Handle browser visibility change
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause_game()
