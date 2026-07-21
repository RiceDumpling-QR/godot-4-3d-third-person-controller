extends SceneTree

const TEST_SCENE := preload("res://verifier/locomotion_test.tscn")
const COLLISION_TEST_SCENE := preload("res://verifier/locomotion_collision_test.tscn")
const ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"attack", &"aim"]
const EPSILON := 0.0001

var _checks: Array[Dictionary] = []
var _diagnostics: Dictionary = {}
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

	await _check_environment()
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
	await _check_collision_aware_movement()
	await _check_animation_integration()
	await _check_feedback_integration()
	await _check_camera_and_combat_preservation()

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
		"diagnostics": _diagnostics,
		"godot_version": Engine.get_version_info().string,
	}
	_write_result(result)
	print("========================================")
	print("FINAL SCORE: %.2f/%.0f" % [total, maximum])
	print("JSON: ", ProjectSettings.globalize_path(_output_path))
	quit(0)


func _check_environment() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	var player_script_loaded := player != null and player.get_script() != null
	var missing_actions: Array[String] = []
	for action in ACTIONS:
		if not InputMap.has_action(action):
			missing_actions.append(String(action))
	_diagnostics = {
		"player_script_loaded": player_script_loaded,
		"missing_input_actions": missing_actions,
		"fixture_player_found": player != null,
	}
	print("[DIAGNOSTIC] player_script_loaded=%s missing_actions=%s" % [player_script_loaded, missing_actions])
	await _free_fixture(fixture.world)


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
	var points := 12.0 * float(passed) / 4.0
	_add_check("basic_movement", points, 12.0, {
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
		points = 15.0
	elif rotation_degrees >= 60.0 and rotation_degrees <= 120.0:
		points = 7.5
	_add_check("camera_relative_movement", points, 15.0, {
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
		points = 8.0
	elif ratio >= 0.75 and ratio <= 1.12:
		points = 4.0
	_add_check("diagonal_normalization", points, 8.0, {
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
		points += 3.0
	if not_instant:
		points += 2.5
	if reaches_run_speed:
		points += 2.5
	_add_check("acceleration", points, 8.0, {"speed_samples": samples})


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
	var prerequisite_met := first_speed >= 2.0
	if prerequisite_met and first_speed > final_speed + 0.5:
		points += 4.0
	if prerequisite_met and final_speed <= 0.15:
		points += 4.0
	await _free_fixture(fixture.world)
	_add_check("stopping", points, 8.0, {"first_speed": first_speed, "final_speed": final_speed, "movement_prerequisite_met": prerequisite_met})


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
		points = 8.0
	elif error_degrees <= 20.0:
		points = 4.0
	await _free_fixture(fixture.world)
	_add_check("travel_orientation", points, 8.0, {
		"angular_error_degrees": error_degrees,
		"facing": _vec3(facing),
		"movement_direction": _vec3(movement_direction),
	})


func _check_grounded_jump() -> void:
	var jump := await _jump_sample(1, false)
	var points := 0.0
	var valid_launch: bool = jump.max_rise >= 0.5
	if jump.max_rise >= 1.5:
		points += 5.0
	if valid_launch and jump.left_floor:
		points += 4.0
	jump["valid_launch"] = valid_launch
	_add_check("grounded_jump", points, 9.0, jump)


func _check_midair_jump_rejection() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	Input.action_press("jump")
	await _wait_physics(3)
	Input.action_release("jump")
	var valid_initial_jump := player.velocity.y > 0.25
	var safety := 0
	while player.velocity.y >= -0.25 and safety < 180:
		await physics_frame
		safety += 1
	var before := player.velocity.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var after := player.velocity.y
	var points := 4.0 if valid_initial_jump and after <= 0.25 else 0.0
	await _free_fixture(fixture.world)
	_add_check("midair_jump_rejection", points, 4.0, {"velocity_before": before, "velocity_after": after, "jump_prerequisite_met": valid_initial_jump})


func _check_variable_jump() -> void:
	var tapped := await _jump_sample(1, false)
	var held := await _jump_sample(30, false)
	var difference: float = held.max_rise - tapped.max_rise
	var points := 0.0
	if difference >= 0.15 and held.max_rise > tapped.max_rise * 1.04:
		points = 4.0
	elif difference >= 0.08:
		points = 2.0
	_add_check("variable_jump_height", points, 4.0, {
		"tapped_rise": tapped.max_rise,
		"held_rise": held.max_rise,
		"difference": difference,
	})


func _check_landing() -> void:
	var jump := await _jump_sample(20, true)
	var points := 0.0
	var prerequisite_met: bool = jump.left_floor and jump.max_rise >= 0.5
	if prerequisite_met and jump.landed:
		points += 2.0
	if prerequisite_met and absf(jump.final_height - jump.start_height) <= 0.08:
		points += 2.0
	jump["jump_prerequisite_met"] = prerequisite_met
	_add_check("stable_landing", points, 4.0, jump)


func _check_collision_aware_movement() -> void:
	var fixture := await _new_collision_fixture()
	var player: CharacterBody3D = fixture.player
	var start := player.global_position
	_press([&"move_up"])
	await _wait_physics(90)
	_release_all()
	var displacement := player.global_position - start
	var approached_wall := displacement.z >= 1.0
	# The wall begins at z=2.75 and the player's capsule radius is about 0.5.
	var blocked_by_wall := player.global_position.z <= 2.4
	var final_position := player.global_position
	await _free_fixture(fixture.world)

	var slide_fixture := await _new_collision_fixture()
	var slide_player: CharacterBody3D = slide_fixture.player
	var slide_start := slide_player.global_position
	_press([&"move_up", &"move_right"])
	await _wait_physics(55)
	_release_all()
	var slide_displacement := slide_player.global_position - slide_start
	var slid_along_wall := absf(slide_displacement.x) >= 1.0 and slide_player.global_position.z <= 2.45
	var points := 0.0
	if approached_wall:
		points += 2.0
	if approached_wall and blocked_by_wall:
		points += 3.0
	if approached_wall and blocked_by_wall and slid_along_wall:
		points += 2.0
	await _free_fixture(slide_fixture.world)
	_add_check("collision_aware_movement", points, 7.0, {
		"displacement": _vec3(displacement),
		"final_position": _vec3(final_position),
		"slide_displacement": _vec3(slide_displacement),
		"approached_wall": approached_wall,
		"blocked_by_wall": blocked_by_wall,
		"slid_along_wall": slid_along_wall,
	})


func _check_animation_integration() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	var animation_tree := player.get_node_or_null("CharacterRotationRoot/CharacterSkin/AnimationTree") as AnimationTree
	var playback: AnimationNodeStateMachinePlayback = null
	if animation_tree:
		playback = animation_tree.get("parameters/StateMachine/playback") as AnimationNodeStateMachinePlayback
	var initial_state := String(playback.get_current_node()) if playback else ""
	_press([&"move_up"])
	await _wait_physics(45)
	var moving_state := String(playback.get_current_node()) if playback else ""
	_release_all()
	Input.action_press("jump")
	await _wait_physics(3)
	var rising_state := String(playback.get_current_node()) if playback else ""
	Input.action_release("jump")
	var safety := 0
	while player.velocity.y >= 0.0 and safety < 180:
		await physics_frame
		safety += 1
	await _wait_physics(2)
	var falling_state := String(playback.get_current_node()) if playback else ""
	var tree_active := animation_tree != null and animation_tree.active
	var movement_transition := moving_state != initial_state and moving_state != ""
	var air_transition := rising_state != "" and falling_state != "" and (rising_state != initial_state or falling_state != initial_state)
	var points := 0.0
	if tree_active:
		points += 1.0
	if movement_transition:
		points += 2.0
	if air_transition:
		points += 2.0
	await _free_fixture(fixture.world)
	_add_check("animation_integration", points, 5.0, {
		"tree_active": tree_active,
		"initial_state": initial_state,
		"moving_state": moving_state,
		"rising_state": rising_state,
		"falling_state": falling_state,
	})


func _check_feedback_integration() -> void:
	var fixture := await _new_fixture()
	var player: CharacterBody3D = fixture.player
	var step_sound := player.get_node_or_null("StepSound") as AudioStreamPlayer3D
	var landing_sound := player.get_node_or_null("LandingSound") as AudioStreamPlayer3D
	var character_skin := player.get_node_or_null("CharacterRotationRoot/CharacterSkin")
	var step_signal_connected := false
	if character_skin and character_skin.has_signal("stepped"):
		for connection in character_skin.get_signal_connection_list("stepped"):
			if connection.callable.get_object() == player:
				step_signal_connected = true
	_press([&"move_up"])
	await _wait_physics(60)
	_release_all()
	var step_stream_present := step_sound != null and step_sound.stream != null
	var landing_stream_present := landing_sound != null and landing_sound.stream != null
	var step_configured := step_stream_present and step_signal_connected
	var landing_configured := landing_stream_present
	var points := 0.0
	if step_configured:
		points += 1.5
	if landing_configured:
		points += 1.5
	await _free_fixture(fixture.world)
	_add_check("locomotion_feedback", points, 3.0, {
		"step_stream_present": step_stream_present,
		"step_signal_connected": step_signal_connected,
		"landing_stream_present": landing_stream_present,
		"headless_note": "Checks feedback wiring because dummy headless audio does not expose playback state.",
	})


func _check_camera_and_combat_preservation() -> void:
	var fixture := await _new_fixture(PI / 2.0)
	var player: CharacterBody3D = fixture.player
	var camera_controller := player.get_node_or_null("CameraController") as Node3D
	var camera_yaw := camera_controller.rotation.y if camera_controller else 0.0
	var camera_preserved := camera_controller != null and absf(absf(camera_yaw) - PI / 2.0) <= 0.1
	var attack_player := player.get_node_or_null("CharacterRotationRoot/MeleeAnchor/AnimationPlayer") as AnimationPlayer
	Input.action_press("attack")
	await _wait_physics(3)
	var attack_speed := _horizontal_speed(player.velocity)
	var attack_started := attack_player != null and (attack_player.is_playing() or attack_player.current_animation == "Attack")
	attack_started = attack_started or attack_speed >= 2.0
	Input.action_release("attack")
	var points := 0.0
	if camera_preserved:
		points += 2.0
	if attack_started:
		points += 3.0
	await _free_fixture(fixture.world)
	_add_check("camera_combat_preservation", points, 5.0, {
		"camera_yaw_degrees": rad_to_deg(camera_yaw),
		"camera_preserved": camera_preserved,
		"attack_started": attack_started,
		"attack_horizontal_speed": attack_speed,
	})


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


func _new_collision_fixture() -> Dictionary:
	_release_all()
	var world := COLLISION_TEST_SCENE.instantiate()
	root.add_child(world)
	await _wait_physics(20)
	var player := world.get_node("Player") as CharacterBody3D
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
