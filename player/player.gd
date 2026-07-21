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
## Maximum horizontal locomotion speed.
@export var move_speed := 8.0
## How quickly the player reaches full speed while movement is held.
@export var acceleration := 24.0
## How quickly the player comes to rest when movement is released.
@export var deceleration := 30.0
## Initial upward speed of a jump. Also used by jumping pads.
@export var jump_initial_impulse := 10.5
## Reduced gravity applied while jump is held during ascent.
@export var jump_hold_gravity_scale := 0.55
## How quickly the visible character turns toward travel.
@export var turn_speed := 12.0
## Horizontal distance between footstep sounds at a full run.
@export var footstep_distance := 2.3

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

var _was_grounded := false
var _footstep_progress := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_controller.setup(self)
	_grenade_aim_controller.visible = false
	weapon_switched.emit(WEAPON_TYPE.keys()[0])

	# When copying this character to a new project, the project may lack required input actions.
	# In that case, we register input actions for the user at runtime.
	if not InputMap.has_action("move_left"):
		_register_input_actions()
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	# Assume a grounded spawn until the first physics step proves otherwise. This
	# prevents the initial floor contact from being reported as a landing.
	_was_grounded = true

func _physics_process(delta: float) -> void:
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

	var grounded_before_move := is_on_floor()
	var melee_motion_locked := _attack_animation_player.is_playing()
	_update_horizontal_movement(delta, melee_motion_locked)
	_update_jump_and_gravity(delta, grounded_before_move, melee_motion_locked)

	var position_before := global_position
	move_and_slide()
	var position_after := global_position
	_update_feedback_and_animation(position_after - position_before)


func _update_horizontal_movement(delta: float, movement_locked: bool) -> void:
	if movement_locked:
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera_forward := -_camera_controller.camera.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right := _camera_controller.camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	var move_direction := (camera_right * input.x + camera_forward * -input.y)
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	var target_velocity := move_direction * move_speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if not move_direction.is_zero_approx() else deceleration
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if not move_direction.is_zero_approx():
		_last_strong_direction = move_direction
		var target_angle := atan2(move_direction.x, move_direction.z)
		_rotation_root.rotation.y = lerp_angle(_rotation_root.rotation.y, target_angle, 1.0 - exp(-turn_speed * delta))


func _update_jump_and_gravity(delta: float, grounded: bool, movement_locked: bool) -> void:
	if grounded:
		if velocity.y < 0.0:
			velocity.y = 0.0
		if not movement_locked and Input.is_action_just_pressed("jump"):
			velocity.y = jump_initial_impulse
			_character_skin.set_locomotion_state(&"jump")
			return

	var gravity_scale := jump_hold_gravity_scale if velocity.y > 0.0 and Input.is_action_pressed("jump") else 1.0
	velocity.y += _gravity * gravity_scale * delta


func _update_feedback_and_animation(delta_position: Vector3) -> void:
	var grounded := is_on_floor()
	var just_landed := grounded and not _was_grounded
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	if just_landed:
		_landing_sound.play()
		_character_skin.set_locomotion_state(&"ground_impact")
		_footstep_progress = 0.0
	elif not grounded:
		_character_skin.set_locomotion_state(&"jump" if velocity.y > 0.0 else &"fall")
	elif horizontal_speed > 0.15:
		_character_skin.set_locomotion_state(&"move", horizontal_speed / move_speed)
	else:
		_character_skin.set_locomotion_state(&"idle")

	if grounded and horizontal_speed > 0.5 and not _attack_animation_player.is_playing():
		_footstep_progress += Vector2(delta_position.x, delta_position.z).length()
		var stride := lerpf(1.6, footstep_distance, clampf(horizontal_speed / move_speed, 0.0, 1.0))
		if _footstep_progress >= stride:
			_footstep_progress = fmod(_footstep_progress, stride)
			_step_sound.play()
	else:
		_footstep_progress = 0.0

	_was_grounded = grounded


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
