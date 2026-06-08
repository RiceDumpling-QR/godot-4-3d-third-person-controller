extends Node


func _ready() -> void:
	await RenderingServer.frame_post_draw
	queue_free()
