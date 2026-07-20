class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

@onready var animation_tree : AnimationTree = $AnimationTree
@onready var _state_machine: AnimationNodeStateMachinePlayback = animation_tree["parameters/StateMachine/playback"]


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func idle() -> void:
	_state_machine.travel("idle")


## speed_ratio is the current horizontal speed relative to the max move speed, from 0 (walk) to 1 (run).
func move(speed_ratio: float) -> void:
	_state_machine.travel("move")
	animation_tree["parameters/StateMachine/move/blend_position"] = speed_ratio


func jump() -> void:
	_state_machine.travel("jump")


func fall() -> void:
	_state_machine.travel("fall")


func land() -> void:
	_state_machine.travel("ground_impact")
