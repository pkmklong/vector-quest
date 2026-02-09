extends Control

## Title screen with instructions

@onready var play_button: Button = $CenterContainer/ContentVBox/PlayButton
@onready var center_container: CenterContainer = $CenterContainer
@onready var background: ColorRect = $Background

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if play_button:
		play_button.pressed.connect(_start_game)
	
	# Force this control to match viewport size (Web fallback)
	_on_resized()
	get_viewport().size_changed.connect(_on_resized)
	resized.connect(_on_resized)

func _on_resized() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	# Force self to fill viewport
	size = vp_size
	# Force Background to fill
	if background:
		background.size = vp_size
	# Force CenterContainer to fill self
	if center_container:
		center_container.size = vp_size

func _start_game() -> void:
	get_tree().change_scene_to_file("res://levels/level_dense.tscn")
