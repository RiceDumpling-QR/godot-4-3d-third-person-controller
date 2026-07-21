class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

@onready var animation_tree : AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]

var _current_state := ""


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func update_locomotion(horizontal_speed: float, max_speed: float, grounded: bool, vertical_speed: float) -> void:
	var next_state: String
	if not grounded:
		next_state = "jump" if vertical_speed > 0.0 else "fall"
	elif horizontal_speed > 0.15:
		next_state = "move"
	else:
		next_state = "idle"

	if next_state != _current_state:
		_state_machine.travel(next_state)
		_current_state = next_state

	# The blend space is authored from walk (0) to run (1).
	animation_tree["parameters/StateMachine/move/blend_position"] = clampf(horizontal_speed / max_speed, 0.0, 1.0)
