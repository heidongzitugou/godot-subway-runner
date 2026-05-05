extends CharacterBody3D

signal hit_obstacle(kind: String)
signal landed

const LANES: Array[float] = [-3.0, 0.0, 3.0]
const SWITCH_SPEED: float = 16.0
const JUMP_VEL: float = 11.0
const GRAVITY_VAL: float = 32.0
const SLIDE_DUR: float = 0.6

var current_lane: int = 1
var slide_timer: float = 0.0
var is_sliding: bool = false
var can_move: bool = true
var run_time: float = 0.0
var was_in_air: bool = false

@onready var collide_shape: CollisionShape3D = $CollisionShape3D
@onready var slide_shape: CollisionShape3D = $SlideCollision
@onready var model_root: Node3D = $ModelRoot

var miku_model: Node3D = null
var skeleton: Skeleton3D = null
var arm_l_idx: int = -1
var arm_r_idx: int = -1
var leg_l_idx: int = -1
var leg_r_idx: int = -1
var spine_idx: int = -1
var head_idx: int = -1
var hair_l_start: int = -1
var hair_r_start: int = -1

func _ready() -> void:
	position.x = LANES[current_lane]
	slide_shape.disabled = true
	_setup_model()

func _setup_model() -> void:
	var model_scene = load("res://assets/models/character/miku.glb")
	if not model_scene:
		return
	miku_model = model_scene.instantiate()
	if not miku_model:
		return
	miku_model.scale = Vector3(1.0, 1.0, 1.0)
	miku_model.rotation_degrees = Vector3(0, 0, 0)
	model_root.position = Vector3(0, 1.0, 0)
	model_root.add_child(miku_model)

	# Find skeleton for animation
	skeleton = _find_skeleton(miku_model)
	if skeleton:
		# MMD bone indices from console output
		arm_l_idx = 52  # 左腕
		arm_r_idx = 15  # 右腕
		leg_l_idx = 223 # 左足
		leg_r_idx = 214 # 右足
		spine_idx = 6   # 上半身
		head_idx = 87   # 頭
		hair_l_start = 106 # 左髪1

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found: return found
	return null

func _physics_process(delta: float) -> void:
	if not can_move: return
	run_time += delta

	var target_x: float = LANES[current_lane]
	position.x = move_toward(position.x, target_x, SWITCH_SPEED * delta)

	if not is_on_floor():
		velocity.y -= GRAVITY_VAL * delta
		was_in_air = true

	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0:
			end_slide()

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
		if was_in_air:
			was_in_air = false
			landed.emit()

	move_and_slide()

	# Procedural running animation
	if can_move and is_on_floor():
		var is_running: bool = not is_sliding
		var bob: float = sin(run_time * 12.0) * 0.05 if is_running else 0.01
		model_root.position.y = 0.5 if is_sliding else (1.0 + bob)

		# Full body running animation
		var arm_swing: float = sin(run_time * 10.0) * 0.5 if is_running else 0.0
		var leg_swing: float = cos(run_time * 10.0) * 0.45 if is_running else 0.0
		var spine_lean: float = 0.15 if is_running else 0.0
		var hair_sway: float = sin(run_time * 8.0 + 1.5) * 0.12 if is_running else 0.0
		if skeleton:
			# Arms swing forward/back (alternating)
			if arm_l_idx >= 0:
				skeleton.set_bone_pose_rotation(arm_l_idx, Quaternion(Vector3(0,1,0), arm_swing))
			if arm_r_idx >= 0:
				skeleton.set_bone_pose_rotation(arm_r_idx, Quaternion(Vector3(0,1,0), -arm_swing))
			# Legs swing forward/back
			if leg_l_idx >= 0:
				skeleton.set_bone_pose_rotation(leg_l_idx, Quaternion(Vector3(0,1,0), leg_swing))
			if leg_r_idx >= 0:
				skeleton.set_bone_pose_rotation(leg_r_idx, Quaternion(Vector3(0,1,0), -leg_swing))
			# Spine leans forward when running
			if spine_idx >= 0:
				skeleton.set_bone_pose_rotation(spine_idx, Quaternion(Vector3(0,1,0), spine_lean))
			# Head stabilizes (slight counter to body bob)
			if head_idx >= 0:
				skeleton.set_bone_pose_rotation(head_idx, Quaternion(Vector3(0,1,0), -bob * 2.0))
			# Hair sways side to side
			if hair_l_start >= 0:
				for hi in range(9):
					var sk: int = hair_l_start + hi
					if sk < skeleton.get_bone_count():
						skeleton.set_bone_pose_rotation(sk, Quaternion(Vector3(0,0,1), hair_sway * (1 + hi * 0.3)))

	# Tilt during lane change
	var dx: float = target_x - position.x
	rotation.z = clampf(-dx * 0.04, -0.12, 0.12)

	# Obstacle collision
	if can_move:
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var collider := collision.get_collider()
			if collider and collider.has_meta(&"obstacle"):
				hit_obstacle.emit(collider.get_meta(&"kind"))
				break

func switch_lane(dir: int) -> void:
	if not can_move: return
	current_lane = clampi(current_lane + dir, 0, 2)

func do_jump() -> void:
	if not can_move or not is_on_floor() or is_sliding: return
	velocity.y = JUMP_VEL

func do_slide() -> void:
	if not can_move or not is_on_floor() or is_sliding: return
	is_sliding = true
	slide_timer = SLIDE_DUR
	model_root.position.y = 0.5
	model_root.scale = Vector3(1.0, 0.5, 1.0)
	collide_shape.disabled = true
	slide_shape.disabled = false

func end_slide() -> void:
	is_sliding = false
	model_root.position.y = 1.0
	model_root.scale = Vector3(1.0, 1.0, 1.0)
	collide_shape.disabled = false
	slide_shape.disabled = true

func freeze() -> void:
	can_move = false

func unfreeze() -> void:
	can_move = true
