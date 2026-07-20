extends SceneTree

const TEST_SCENE := preload("res://verifier/locomotion_test.tscn")
const ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"attack", &"aim"]
const EPSILON := 0.0001

var _checks: Array[Dictionary] = []
var _output_path := "res://verifier/results/latest.json"
var _label := "candidate"


func _init() -> void:
	_parse_arguments()
	_run.call_deferred()


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--output" and index + 1 < args.size():
			_output_path = args[index + 1]
		elif args[index] == "--label" and index + 1 < args.size():
			_label = args[index + 1]


func _run() -> void:
	print("Locomotion verifier: ", _label)
	print("========================================")

	await _check_basic_movement()
	await _check_camera_relative_movement()
	await _check_diagonal_normalization()
	await _check_acceleration()
	await _check_stopping()
	await _check_orientation()
	await _check_grounded_jump()
	await _check_midair_jump_rejection()
	await _check_variable_jump()
	await _check_landing()

	var total := 0.0
	var maximum := 0.0
	for check in _checks:
		total += check.points
		maximum += check.maximum

	var result := {
		"label": _label,
		"score": snappedf(total, 0.01),
		"maximum": maximum,
		"checks": _checks,
		"godot_version": Engine.get_version_info().string,
	}
	_write_result(result)
	print("========================================")
	print("FINAL SCORE: %.2f/%.0f" % [total, maximum])
	print("JSON: ", ProjectSettings.globalize_path(_output_path))
	quit(0)


func _check_basic_movement() -> void:
	var distances := {}
	var directions := {}
	var alignments := {}
	var passed := 0
	var expected_directions := {
		&"move_up": Vector3.BACK,
		&"move_down": Vector3.FORWARD,
		&"move_left": Vector3.RIGHT,
		&"move_right": Vector3.LEFT,
	}
	for action in expected_directions:
		var sample := await _movement_sample([action], 60)
		distances[String(action)] = sample.distance
		directions[String(action)] = _vec3(sample.direction)
		var alignment: float = sample.direction.dot(expected_directions[action])
		alignments[String(action)] = alignment
		if sample.distance >= 4.5 and alignment >= 0.9:
			passed += 1
	var points := 15.0 * float(passed) / 4.0
	_add_check("basic_movement", points, 15.0, {
		"distances": distances,
		"directions": directions,
		"direction_alignments": alignments,
		"minimum_distance": 4.5,
		"directions_passing": passed,
	})


func _check_camera_relative_movement() -> void:
	var base := await _movement_sample([&"move_up"], 60, 0.0)
	var turned := await _movement_sample([&"move_up"], 60, PI / 2.0)
	var rotation_degrees := rad_to_deg(_unsigned_angle(base.direction, turned.direction))
	var points := 0.0
	if rotation_degrees >= 80.0 and rotation_degrees <= 100.0:
		points = 20.0
	elif rotation_degrees >= 60.0 and rotation_degrees <= 120.0:
		points = 10.0
	_add_check("camera_relative_movement", points, 20.0, {
		"direction_change_degrees": rotation_degrees,
		"base_direction": _vec3(base.direction),
		"turned_direction": _vec3(turned.direction),
	})


func _check_diagonal_normalization() -> void:
	var straight := await _movement_sample([&"move_up"], 60)
	var diagonal := await _movement_sample([&"move_up", &"move_right"], 60)
	var ratio: float = diagonal.distance / maxf(straight.distance, EPSILON)
	var points := 0.0
	# In Godot 4.6, Input.get_vector() normalizes the diagonal before this
	# project's square-to-circle mapping, so the locked original measures
	# sqrt(3) / 2 (about 0.866). Keep the band broad enough for frame jitter,
	# while still rejecting an unbounded 1.414x diagonal implementation.
	if ratio >= 0.82 and ratio <= 1.05:
		points = 10.0
	elif ratio >= 0.75 and ratio <= 1.12:
		points = 5.0
	_add_check("diagonal_normalization", points, 10.0, {
		"straight_distance": straight.distance,
		"diagonal_distance": diagonal.distance,
		"ratio": ratio,
	})


func _check_acceleration() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	_press([&"move_up"])
	var samples: Array[float] = []
	for frame in 45:
		await physics_frame
		if frame in [0, 4, 14, 44]:
			samples.append(_horizontal_speed(player.velocity))
	_release_all()
	await _free_fixture(fixture.world)

	var grows := samples.size() == 4 and samples[0] < samples[1] and samples[1] <= samples[2] + 0.05 and samples[2] <= samples[3] + 0.05
	var not_instant := samples.size() == 4 and samples[0] < samples[3] * 0.75
	var reaches_run_speed := samples.size() == 4 and samples[3] >= 6.5 and samples[3] <= 9.5
	var points := 0.0
	if grows:
		points += 4.0
	if not_instant:
		points += 3.0
	if reaches_run_speed:
		points += 3.0
	_add_check("acceleration", points, 10.0, {"speed_samples": samples})


func _check_stopping() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	_press([&"move_up"])
	await _wait_physics(60)
	_release_all()
	await physics_frame
	var first_speed := _horizontal_speed(player.velocity)
	await _wait_physics(30)
	var final_speed := _horizontal_speed(player.velocity)
	var points := 0.0
	if first_speed > final_speed + 0.5:
		points += 5.0
	if final_speed <= 0.15:
		points += 5.0
	await _free_fixture(fixture.world)
	_add_check("stopping", points, 10.0, {"first_speed": first_speed, "final_speed": final_speed})


func _check_orientation() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	var visual_root := player.get_node_or_null("CharacterRotationRoot") as Node3D
	_press([&"move_right"])
	await _wait_physics(45)
	_release_all()
	var movement_direction := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	var facing := Vector3.ZERO
	var error_degrees := 180.0
	if visual_root:
		facing = Vector3(visual_root.global_basis.z.x, 0.0, visual_root.global_basis.z.z).normalized()
		error_degrees = rad_to_deg(_unsigned_angle(facing, movement_direction))
	var points := 0.0
	if error_degrees <= 8.0:
		points = 10.0
	elif error_degrees <= 20.0:
		points = 5.0
	await _free_fixture(fixture.world)
	_add_check("travel_orientation", points, 10.0, {
		"angular_error_degrees": error_degrees,
		"facing": _vec3(facing),
		"movement_direction": _vec3(movement_direction),
	})


func _check_grounded_jump() -> void:
	var jump := await _jump_sample(1, false)
	var points := 0.0
	if jump.max_rise >= 1.5:
		points += 6.0
	if jump.left_floor:
		points += 4.0
	_add_check("grounded_jump", points, 10.0, jump)


func _check_midair_jump_rejection() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var safety := 0
	while player.velocity.y >= -0.25 and safety < 180:
		await physics_frame
		safety += 1
	var before := player.velocity.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var after := player.velocity.y
	var points := 5.0 if after <= 0.25 else 0.0
	await _free_fixture(fixture.world)
	_add_check("midair_jump_rejection", points, 5.0, {"velocity_before": before, "velocity_after": after})


func _check_variable_jump() -> void:
	var tapped := await _jump_sample(1, false)
	var held := await _jump_sample(30, false)
	var difference: float = held.max_rise - tapped.max_rise
	var points := 0.0
	if difference >= 0.15 and held.max_rise > tapped.max_rise * 1.04:
		points = 5.0
	elif difference >= 0.08:
		points = 2.5
	_add_check("variable_jump_height", points, 5.0, {
		"tapped_rise": tapped.max_rise,
		"held_rise": held.max_rise,
		"difference": difference,
	})


func _check_landing() -> void:
	var jump := await _jump_sample(20, true)
	var points := 0.0
	if jump.landed:
		points += 3.0
	if absf(jump.final_height - jump.start_height) <= 0.08:
		points += 2.0
	_add_check("stable_landing", points, 5.0, jump)


func _movement_sample(actions: Array, frames: int, camera_yaw := 0.0) -> Dictionary:
	var fixture := await _new_fixture(camera_yaw)
	var player: CharacterBody3D = fixture.player
	var start := player.global_position
	_press(actions)
	await _wait_physics(frames)
	_release_all()
	var displacement := player.global_position - start
	var horizontal := Vector3(displacement.x, 0.0, displacement.z)
	var result := {
		"distance": horizontal.length(),
		"direction": horizontal.normalized() if horizontal.length() > EPSILON else Vector3.ZERO,
	}
	await _free_fixture(fixture.world)
	return result


func _jump_sample(hold_frames: int, wait_for_landing: bool) -> Dictionary:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	var start_y := player.global_position.y
	var max_y := start_y
	var left_floor := false
	Input.action_press("jump")
	for frame in hold_frames:
		await physics_frame
		max_y = maxf(max_y, player.global_position.y)
		left_floor = left_floor or not player.is_on_floor()
	Input.action_release("jump")
	var landed := false
	for frame in 240:
		await physics_frame
		max_y = maxf(max_y, player.global_position.y)
		left_floor = left_floor or not player.is_on_floor()
		if left_floor and player.is_on_floor() and player.velocity.y <= 0.05:
			landed = true
			if not wait_for_landing or frame > 2:
				break
	var result := {
		"start_height": start_y,
		"max_height": max_y,
		"max_rise": max_y - start_y,
		"final_height": player.global_position.y,
		"left_floor": left_floor,
		"landed": landed,
	}
	await _free_fixture(fixture.world)
	return result


func _new_fixture(camera_yaw := 0.0) -> Dictionary:
	_release_all()
	var world := TEST_SCENE.instantiate()
	root.add_child(world)
	await _wait_physics(20)
	var player := world.get_node("Player") as CharacterBody3D
	var camera_controller := player.get_node_or_null("CameraController") as Node3D
	if camera_controller:
		camera_controller.set("_euler_rotation", Vector3(0.0, camera_yaw, 0.0))
		camera_controller.rotation = Vector3(0.0, camera_yaw, 0.0)
	await _wait_physics(3)
	return {"world": world, "player": player}


func _free_fixture(world: Node) -> void:
	_release_all()
	world.queue_free()
	await process_frame
	await physics_frame


func _press(actions: Array) -> void:
	for action in actions:
		Input.action_press(action)


func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func _wait_physics(frames: int) -> void:
	for frame in frames:
		await physics_frame


func _horizontal_speed(value: Vector3) -> float:
	return Vector2(value.x, value.z).length()


func _unsigned_angle(a: Vector3, b: Vector3) -> float:
	if a.length() <= EPSILON or b.length() <= EPSILON:
		return PI
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))


func _vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _add_check(name: String, points: float, maximum: float, measurements: Dictionary) -> void:
	var status := "PASS" if is_equal_approx(points, maximum) else ("FAIL" if is_zero_approx(points) else "PARTIAL")
	_checks.append({
		"name": name,
		"status": status,
		"points": snappedf(points, 0.01),
		"maximum": maximum,
		"measurements": measurements,
	})
	print("[%s] %-28s %5.2f/%-5.2f" % [status, name, points, maximum])


func _write_result(result: Dictionary) -> void:
	var absolute := ProjectSettings.globalize_path(_output_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "  "))
	else:
		push_error("Could not write verifier result to %s" % absolute)
