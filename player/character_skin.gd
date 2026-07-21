class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

@onready var animation_tree : AnimationTree = $AnimationTree
@onready var _locomotion_state: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/StateMachine/playback")

var _current_locomotion_state := ""


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1
	set_locomotion_state("idle")


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func set_locomotion_state(state: StringName, movement_intensity := 0.0) -> void:
	animation_tree["parameters/StateMachine/move/blend_position"] = clampf(movement_intensity, 0.0, 1.0)
	if _current_locomotion_state == state:
		return
	_current_locomotion_state = state
	_locomotion_state.travel(state)
