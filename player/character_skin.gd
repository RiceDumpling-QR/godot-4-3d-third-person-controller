class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

@onready var animation_tree : AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]

var _current_state := &""


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func update_locomotion(horizontal_speed: float, max_speed: float, grounded: bool, vertical_speed: float, just_landed: bool) -> void:
	var target_state: StringName
	if just_landed:
		target_state = &"ground_impact"
	elif not grounded:
		target_state = &"jump" if vertical_speed > 0.0 else &"fall"
	elif horizontal_speed > 0.15:
		target_state = &"move"
	else:
		target_state = &"idle"

	animation_tree["parameters/StateMachine/move/blend_position"] = clamp(horizontal_speed / max(max_speed, 0.001), 0.0, 1.0)
	if target_state != _current_state:
		_state_machine.travel(target_state)
		_current_state = target_state
