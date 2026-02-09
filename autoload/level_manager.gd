extends Node

## Manages level progression and completion data

signal level_unlocked(level_id: String)
signal level_completed(level_id: String, bce_score: float)

# Level definitions
# Set to false for release, true for testing
const DEBUG_UNLOCK_ALL := true

var levels: Array[Dictionary] = [
	{
		"id": "dense_nn",
		"name": "Dense NN",
		"description": "Fully connected network",
		"scene": "res://levels/level_dense.tscn",
		"unlocked": true,
		"completed": false,
		"best_bce": -1.0,
		"runs": 0
	},
	{
		"id": "cnn",
		"name": "CNN",
		"description": "Convolutional network",
		"scene": "res://levels/level_cnn.tscn",
		"unlocked": DEBUG_UNLOCK_ALL,
		"completed": false,
		"best_bce": -1.0,
		"runs": 0
	},
	{
		"id": "rnn",
		"name": "LSTM",
		"description": "Long Short-Term Memory",
		"scene": "res://levels/level_rnn.tscn",
		"unlocked": DEBUG_UNLOCK_ALL,
		"completed": false,
		"best_bce": -1.0,
		"runs": 0
	},
	{
		"id": "transformer",
		"name": "Transformer",
		"description": "Attention mechanism",
		"scene": "res://levels/level_transformer.tscn",
		"unlocked": DEBUG_UNLOCK_ALL,
		"completed": false,
		"best_bce": -1.0,
		"runs": 0
	}
]

var current_level_id: String = "dense_nn"

func _ready() -> void:
	pass

func get_level(level_id: String) -> Dictionary:
	for level in levels:
		if level["id"] == level_id:
			return level
	return {}

func get_current_level() -> Dictionary:
	return get_level(current_level_id)

func complete_level(level_id: String, bce_score: float) -> void:
	var level := get_level(level_id)
	if level.is_empty():
		return
	
	level["completed"] = true
	level["runs"] += 1
	
	# Update best BCE (lower is better)
	if level["best_bce"] < 0 or bce_score < level["best_bce"]:
		level["best_bce"] = bce_score
	
	level_completed.emit(level_id, bce_score)
	
	# Unlock next level
	_unlock_next_level(level_id)

func _unlock_next_level(completed_level_id: String) -> void:
	var found_completed := false
	for level in levels:
		if found_completed and not level["unlocked"]:
			level["unlocked"] = true
			level_unlocked.emit(level["id"])
			break
		if level["id"] == completed_level_id:
			found_completed = true

func is_level_unlocked(level_id: String) -> bool:
	var level := get_level(level_id)
	return level.get("unlocked", false)

func get_all_levels() -> Array[Dictionary]:
	return levels

func set_current_level(level_id: String) -> void:
	if is_level_unlocked(level_id):
		current_level_id = level_id

## Clear all completion state and best BCE so levels no longer show as completed
func reset_all_progress() -> void:
	for level in levels:
		level["completed"] = false
		level["best_bce"] = -1.0
		level["runs"] = 0
