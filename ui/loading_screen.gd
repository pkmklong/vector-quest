extends CanvasLayer

## Loading screen that shows while the game loads

@onready var progress_bar: ProgressBar = $Control/ProgressBar
@onready var status_label: Label = $Control/StatusLabel
@onready var title_label: Label = $Control/TitleLabel

var target_scene_path := "res://ui/title_screen.tscn"
var loading_status: Array = []
var progress := 0.0

func _ready() -> void:
	# Start loading the main scene in background
	ResourceLoader.load_threaded_request(target_scene_path)

func _process(_delta: float) -> void:
	# Check loading progress
	var status := ResourceLoader.load_threaded_get_status(target_scene_path, loading_status)
	
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if loading_status.size() > 0:
			progress = loading_status[0] * 100.0
		progress_bar.value = progress
		status_label.text = "Loading neural network... %d%%" % int(progress)
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		# Loading complete - switch to scene
		progress_bar.value = 100
		status_label.text = "Initializing..."
		
		var scene := ResourceLoader.load_threaded_get(target_scene_path)
		get_tree().change_scene_to_packed(scene)
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		status_label.text = "Failed to load!"
