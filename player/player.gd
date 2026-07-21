class_name Player
extends CharacterBody3D

signal weapon_switched(weapon_name: String)

const BULLET_SCENE := preload("bullet.tscn")
const COIN_SCENE := preload("coin/coin.tscn")

enum WEAPON_TYPE { DEFAULT, GRENADE }

## Speed of shot bullets.
@export var bullet_speed := 10.0
## Forward impulse after a melee attack.
@export var attack_impulse := 10.0
## Max throwback force after player takes a hit
@export var max_throwback_force := 15.0
## Projectile cooldown
@export var shoot_cooldown := 0.5
## Grenade cooldown
@export var grenade_cooldown := 0.5
## Maximum horizontal movement speed in world units per second.
@export var movement_speed := 8.0
## Rate at which the player reaches full movement speed.
@export var acceleration := 28.0
## Rate at which the player comes to rest without movement input.
@export var deceleration := 36.0
## Initial upward speed of a grounded jump.
@export var jump_velocity := 10.0
## Gravity while jump is held during ascent, allowing a moderately higher jump.
@export var held_jump_gravity := 18.0
## Gravity after jump is released and while falling.
@export var fall_gravity := 30.0
## How quickly the visible character turns toward movement.
@export var turn_speed := 12.0
## Horizontal distance between footstep sounds.
@export var footstep_distance := 2.8

@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _attack_animation_player: AnimationPlayer = $CharacterRotationRoot/MeleeAnchor/AnimationPlayer
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast
@onready var _grenade_aim_controller: GrenadeLauncher = $GrenadeLauncher
@onready var _character_skin: CharacterSkin = $CharacterRotationRoot/CharacterSkin
@onready var _ui_aim_reticle: ColorRect = %AimReticle
@onready var _ui_coins_container: HBoxContainer = %CoinsContainer
@onready var _step_sound: AudioStreamPlayer3D = $StepSound
@onready var _landing_sound: AudioStreamPlayer3D = $LandingSound

@onready var _equipped_weapon: WEAPON_TYPE = WEAPON_TYPE.DEFAULT
@onready var _last_strong_direction := Vector3.FORWARD
@onready var _ground_height: float = 0.0
@onready var _start_position := global_transform.origin
@onready var _coins := 0

@onready var _shoot_cooldown_tick := shoot_cooldown
@onready var _grenade_cooldown_tick := grenade_cooldown

var _footstep_progress := 0.0
var _physics_initialized := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_controller.setup(self)
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	_grenade_aim_controller.visible = false
	weapon_switched.emit(WEAPON_TYPE.keys()[0])

	# When copying this character to a new project, the project may lack required input actions.
	# In that case, we register input actions for the user at runtime.
	if not InputMap.has_action("move_left"):
		_register_input_actions()

func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	var position_before := global_position

	# Calculate ground height for camera controller
	if _ground_shapecast.get_collision_count() > 0:
		for collision_result in _ground_shapecast.collision_result:
			_ground_height = max(_ground_height, collision_result.point.y)
	else:
		_ground_height = global_position.y + _ground_shapecast.target_position.y
	if global_position.y < _ground_height:
		_ground_height = global_position.y

	# Swap weapons
	if Input.is_action_just_pressed("swap_weapons"):
		_equipped_weapon = WEAPON_TYPE.DEFAULT if _equipped_weapon == WEAPON_TYPE.GRENADE else WEAPON_TYPE.GRENADE
		_grenade_aim_controller.visible = _equipped_weapon == WEAPON_TYPE.GRENADE
		weapon_switched.emit(WEAPON_TYPE.keys()[_equipped_weapon])

	# Get combat state
	var is_attacking := Input.is_action_pressed("attack") and not _attack_animation_player.is_playing()
	var is_just_attacking := Input.is_action_just_pressed("attack")
	var is_aiming := Input.is_action_pressed("aim") and is_on_floor()
	if is_aiming:
		_last_strong_direction = (_camera_controller.global_transform.basis * Vector3.BACK).normalized()

	# Set aiming camera and UI
	if is_aiming:
		_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.OVER_SHOULDER)
		_grenade_aim_controller.throw_direction = _camera_controller.camera.quaternion * Vector3.FORWARD
		_grenade_aim_controller.from_look_position = _camera_controller.camera.global_position
		_ui_aim_reticle.visible = true
	else:
		_camera_controller.set_pivot(_camera_controller.CAMERA_PIVOT.THIRD_PERSON)
		_grenade_aim_controller.throw_direction = _last_strong_direction
		_grenade_aim_controller.from_look_position = global_position
		_ui_aim_reticle.visible = false

	# Update attack state and position

	_shoot_cooldown_tick += delta
	_grenade_cooldown_tick += delta

	if is_attacking:
		match _equipped_weapon:
			WEAPON_TYPE.DEFAULT:
				if is_aiming and is_on_floor():
					if _shoot_cooldown_tick > shoot_cooldown:
						_shoot_cooldown_tick = 0.0
						shoot()
				elif is_just_attacking:
					attack()
			WEAPON_TYPE.GRENADE:
				if _grenade_cooldown_tick > grenade_cooldown:
					_grenade_cooldown_tick = 0.0
					_grenade_aim_controller.throw_grenade()

	_update_movement(delta, is_aiming)
	_update_jump(delta, was_on_floor)
	move_and_slide()
	_update_locomotion_feedback(position_before, was_on_floor)


func _update_movement(delta: float, is_aiming: bool) -> void:
	# The melee animation owns horizontal velocity for its short attack lunge.
	if _attack_animation_player.is_playing():
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera_forward := _camera_controller.camera.global_basis * Vector3.FORWARD
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right := _camera_controller.camera.global_basis * Vector3.RIGHT
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var movement_direction := camera_right * input.x + camera_forward * -input.y
	if movement_direction.length_squared() > 1.0:
		movement_direction = movement_direction.normalized()

	var target_velocity := movement_direction * movement_speed
	var change_rate := acceleration if not movement_direction.is_zero_approx() else deceleration
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var horizontal_target := Vector2(target_velocity.x, target_velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(horizontal_target, change_rate * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	var facing_direction := movement_direction
	if is_aiming:
		facing_direction = _last_strong_direction
	elif not movement_direction.is_zero_approx():
		_last_strong_direction = movement_direction
	if not facing_direction.is_zero_approx():
		var target_angle := atan2(facing_direction.x, facing_direction.z)
		_rotation_root.rotation.y = lerp_angle(
			_rotation_root.rotation.y,
			target_angle,
			1.0 - exp(-turn_speed * delta)
		)


func _update_jump(delta: float, was_on_floor: bool) -> void:
	var started_jump := Input.is_action_just_pressed("jump") and was_on_floor
	if started_jump:
		velocity.y = jump_velocity
		floor_snap_length = 0.0

	if started_jump or not was_on_floor:
		var gravity := held_jump_gravity if velocity.y > 0.0 and Input.is_action_pressed("jump") else fall_gravity
		velocity.y -= gravity * delta
	else:
		# Keep contact stable on slopes without accumulating downward velocity.
		velocity.y = minf(velocity.y, 0.0)


func _update_locomotion_feedback(position_before: Vector3, was_on_floor: bool) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	# Suppress a false landing event when the scene first establishes floor contact.
	var just_landed := _physics_initialized and not was_on_floor and is_on_floor()
	if just_landed:
		floor_snap_length = 0.35
		_landing_sound.play()
		_footstep_progress = 0.0
		_character_skin.set_locomotion_state("ground_impact", horizontal_speed / movement_speed)
	elif not is_on_floor():
		_footstep_progress = 0.0
		_character_skin.set_locomotion_state("jump" if velocity.y > 0.0 else "fall")
	elif horizontal_speed > 0.15:
		_character_skin.set_locomotion_state("move", horizontal_speed / movement_speed)
		var horizontal_motion := global_position - position_before
		horizontal_motion.y = 0.0
		_footstep_progress += horizontal_motion.length()
		if _footstep_progress >= footstep_distance:
			_footstep_progress = fmod(_footstep_progress, footstep_distance)
			_step_sound.play()
	else:
		_footstep_progress = 0.0
		_character_skin.set_locomotion_state("idle")
	_physics_initialized = true


func attack() -> void:
	_attack_animation_player.play("Attack")
	_character_skin.punch()
	velocity = _rotation_root.transform.basis * Vector3.BACK * attack_impulse


func shoot() -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.shooter = self
	var origin := global_position + Vector3.UP
	var aim_target := _camera_controller.get_aim_target()
	var aim_direction := (aim_target - origin).normalized()
	bullet.velocity = aim_direction * bullet_speed
	bullet.distance_limit = 14.0
	get_parent().add_child(bullet)
	bullet.global_position = origin


func reset_position() -> void:
	transform.origin = _start_position


func collect_coin() -> void:
	_coins += 1
	_ui_coins_container.update_coins_amount(_coins)


func lose_coins() -> void:
	var lost_coins: int = min(_coins, 5)
	_coins -= lost_coins
	for i in lost_coins:
		var coin := COIN_SCENE.instantiate()
		get_parent().add_child(coin)
		coin.global_position = global_position
		coin.spawn(1.5)
	_ui_coins_container.update_coins_amount(_coins)


func damage(_impact_point: Vector3, force: Vector3) -> void:
	# Always throws character up
	force.y = abs(force.y)
	velocity = force.limit_length(max_throwback_force)
	lose_coins()


## Used to register required input actions when copying this character to a different project.
func _register_input_actions() -> void:
	const INPUT_ACTIONS := {
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_up": KEY_W,
		"move_down": KEY_S,
		"jump": KEY_SPACE,
		"attack": MOUSE_BUTTON_LEFT,
		"aim": MOUSE_BUTTON_RIGHT,
		"swap_weapons": KEY_TAB,
		"pause": KEY_ESCAPE,
		"camera_left": KEY_Q,
		"camera_right": KEY_E,
		"camera_up": KEY_R,
		"camera_down": KEY_F,
	}
	for action in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var input_key = InputEventKey.new()
		input_key.keycode = INPUT_ACTIONS[action]
		InputMap.action_add_event(action, input_key)
