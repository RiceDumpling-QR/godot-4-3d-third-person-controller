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

## Top ground movement speed.
@export var move_speed := 7.0
## How quickly the character speeds up towards its target velocity.
@export var acceleration := 18.0
## How quickly the character slows down once movement input stops, letting it drift to a stop.
@export var deceleration := 7.0
## How quickly the character turns to face its movement direction.
@export var rotation_speed := 12.0
## Upward velocity applied the instant the jump button is pressed.
@export var jump_initial_impulse := 9.0
## Extra upward force applied while the jump button is held down, for a taller jump.
@export var jump_extra_force := 26.0
## Longest the jump button can be held to keep adding extra height.
@export var jump_max_hold_time := 0.2
## Seconds between footstep sounds when moving at full speed.
@export var footstep_interval := 0.33

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
@onready var _gravity: float = -30.0
@onready var _ground_height: float = 0.0
@onready var _start_position := global_transform.origin
@onready var _coins := 0

@onready var _shoot_cooldown_tick := shoot_cooldown
@onready var _grenade_cooldown_tick := grenade_cooldown

var _is_jumping := false
var _jump_hold_time := 0.0
var _was_on_floor := true
var _footstep_elapsed := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_controller.setup(self)
	_grenade_aim_controller.visible = false
	weapon_switched.emit(WEAPON_TYPE.keys()[0])

	# When copying this character to a new project, the project may lack required input actions.
	# In that case, we register input actions for the user at runtime.
	if not InputMap.has_action("move_left"):
		_register_input_actions()

func _physics_process(delta: float) -> void:
	var is_on_floor_now := is_on_floor()

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

	# Ground movement, relative to the camera's point of view
	var camera_basis := _camera_controller.global_transform.basis
	var camera_forward := camera_basis * Vector3.BACK
	var camera_right := camera_basis * Vector3.RIGHT
	camera_forward.y = 0.0
	camera_right.y = 0.0
	camera_forward = camera_forward.normalized() if camera_forward.length() > 0.0001 else Vector3.ZERO
	camera_right = camera_right.normalized() if camera_right.length() > 0.0001 else Vector3.ZERO

	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_direction := camera_forward * -move_input.y + camera_right * move_input.x

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := move_direction * move_speed
	var speed_change := acceleration if move_direction.length() > 0.0 else deceleration
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, speed_change * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if horizontal_velocity.length() > 0.1:
		var facing_angle := atan2(horizontal_velocity.x, horizontal_velocity.z)
		_rotation_root.rotation.y = lerp_angle(_rotation_root.rotation.y, facing_angle, rotation_speed * delta)

	# Get combat state
	var is_attacking := Input.is_action_pressed("attack") and not _attack_animation_player.is_playing()
	var is_just_attacking := Input.is_action_just_pressed("attack")
	var is_aiming := Input.is_action_pressed("aim") and is_on_floor_now
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
				if is_aiming and is_on_floor_now:
					if _shoot_cooldown_tick > shoot_cooldown:
						_shoot_cooldown_tick = 0.0
						shoot()
				elif is_just_attacking:
					attack()
			WEAPON_TYPE.GRENADE:
				if _grenade_cooldown_tick > grenade_cooldown:
					_grenade_cooldown_tick = 0.0
					_grenade_aim_controller.throw_grenade()

	# Jumping: a short tap gives a small hop, holding the button gives a taller jump.
	if is_on_floor_now and Input.is_action_just_pressed("jump"):
		velocity.y = jump_initial_impulse
		_is_jumping = true
		_jump_hold_time = 0.0

	if _is_jumping:
		if Input.is_action_pressed("jump") and _jump_hold_time < jump_max_hold_time:
			velocity.y += jump_extra_force * delta
			_jump_hold_time += delta
		else:
			_is_jumping = false

	velocity.y += _gravity * delta

	# Locomotion animation, footsteps and landing feedback
	var current_horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := clamp(current_horizontal_speed / move_speed, 0.0, 1.0)
	if is_on_floor_now:
		if not _was_on_floor:
			_is_jumping = false
			_landing_sound.play()
			_character_skin.land()
			_footstep_elapsed = footstep_interval
		elif speed_ratio > 0.05:
			_character_skin.move(speed_ratio)
			_footstep_elapsed += delta * speed_ratio
			if _footstep_elapsed >= footstep_interval:
				_footstep_elapsed = 0.0
				_step_sound.play()
		else:
			_character_skin.idle()
			_footstep_elapsed = 0.0
	else:
		_footstep_elapsed = 0.0
		if velocity.y > 0.0:
			_character_skin.jump()
		else:
			_character_skin.fall()
	_was_on_floor = is_on_floor_now

	var position_before := global_position
	move_and_slide()
	var position_after := global_position

	# If velocity is not 0 but the difference of positions after move_and_slide is,
	# character might be stuck somewhere!
	var delta_position := position_after - position_before
	var epsilon := 0.001
	if delta_position.length() < epsilon and velocity.length() > epsilon:
		global_position += get_wall_normal() * 0.1


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
