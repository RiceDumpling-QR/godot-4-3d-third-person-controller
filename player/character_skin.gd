class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

@onready var animation_tree : AnimationTree = $AnimationTree


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1


func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
