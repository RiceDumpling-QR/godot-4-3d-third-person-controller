class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

@onready var animation_tree : AnimationTree = $AnimationTree
@onready var _locomotion_state: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]

var _current_state := &"idle"


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func update_locomotion(speed_ratio: float, grounded: bool, vertical_speed: float, just_landed: bool) -> void:
	animation_tree["parameters/StateMachine/move/blend_position"] = clampf(speed_ratio, 0.0, 1.0)

	var desired_state: StringName
	if just_landed:
		desired_state = &"ground_impact"
	elif not grounded:
		desired_state = &"jump" if vertical_speed > 0.0 else &"fall"
	elif speed_ratio > 0.05:
		desired_state = &"move"
	else:
		desired_state = &"idle"

	if desired_state != _current_state:
		_locomotion_state.travel(desired_state)
		_current_state = desired_state
