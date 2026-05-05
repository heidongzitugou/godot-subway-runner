extends CharacterBody3D

signal hit_obstacle(kind: String)
signal landed
signal jumped
signal slid

const LANES: Array[float] = [-3.0, 0.0, 3.0]
const SWITCH_SPEED: float = 20.0
const JUMP_VEL: float = 11.8
const DOUBLE_JUMP_VEL: float = 9.4
const GRAVITY_VAL: float = 34.0
const SLIDE_DUR: float = 0.66
const MAX_JUMPS: int = 2

var current_lane: int = 1
var slide_timer: float = 0.0
var is_sliding: bool = false
var can_move: bool = true
var run_time: float = 0.0
var was_in_air: bool = false
var jump_phase: float = 0.0
var land_squash: float = 0.0
var idle_time: float = 0.0
var jump_count: int = 0
var lane_motion: float = 0.0
var hit_react_timer: float = 0.0

@onready var collide_shape: CollisionShape3D = $CollisionShape3D
@onready var slide_shape: CollisionShape3D = $SlideCollision
@onready var model_root: Node3D = $ModelRoot
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree

enum AnimState { IDLE, RUN, JUMP, SLIDE, LAND, HIT }
var current_anim: AnimState = AnimState.IDLE

var miku_model: Node3D = null
var skeleton: Skeleton3D = null
var arm_l_idx: int = -1
var arm_r_idx: int = -1
var leg_l_idx: int = -1
var leg_r_idx: int = -1
var spine_idx: int = -1
var head_idx: int = -1
var hair_l_start: int = -1

# Additional bone indices
var shoulder_l_idx: int = -1
var shoulder_r_idx: int = -1
var forearm_l_idx: int = -1
var forearm_r_idx: int = -1
var thigh_l_idx: int = -1
var thigh_r_idx: int = -1
var spine2_idx: int = -1
var neck_idx: int = -1


func _ready() -> void:
	position.x = LANES[current_lane]
	slide_shape.disabled = true
	_setup_model()
	_setup_animation_tree()

func _setup_model() -> void:
	var model_scene = load("res://assets/models/miku.glb")
	if model_scene:
		miku_model = model_scene.instantiate()
	if not miku_model:
		# Fallback: visible placeholder cube
		var fallback := MeshInstance3D.new()
		fallback.mesh = BoxMesh.new()
		fallback.mesh.size = Vector3(0.6, 1.8, 0.3)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color8(57, 200, 190)
		fmat.emission_enabled = true
		fmat.emission = Color8(57, 200, 190)
		fmat.emission_energy_multiplier = 0.5
		fallback.mesh.material = fmat
		fallback.position.y = 1.0
		model_root.add_child(fallback)
		return
	miku_model.scale = Vector3(1.0, 1.0, 1.0)
	model_root.add_child(miku_model)

	skeleton = _find_skeleton(miku_model)
	if skeleton:
		arm_l_idx = 52
		arm_r_idx = 15
		leg_l_idx = 223
		leg_r_idx = 214
		spine_idx = 6
		head_idx = 87
		hair_l_start = 106
		shoulder_l_idx = 50
		shoulder_r_idx = 13
		forearm_l_idx = 53
		forearm_r_idx = 16
		thigh_l_idx = 221
		thigh_r_idx = 212
		spine2_idx = 5
		neck_idx = 85

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found: return found
	return null

func _setup_animation_tree() -> void:
	# Create blend animations for state transitions (0.15s crossfade)
	var lib := AnimationLibrary.new()

	for anim_name in ["blend_to_run", "blend_to_jump", "blend_to_slide", "blend_to_idle", "blend_to_land", "blend_to_hit"]:
		var anim := Animation.new()
		anim.length = 0.15
		anim.loop_mode = Animation.LOOP_NONE
		anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(0, ".:blend_weight")
		anim.track_insert_key(0, 0.0, 0.0)
		anim.track_insert_key(0, 0.15, 1.0)
		lib.add_animation(anim_name, anim)

	anim_player.add_animation_library("transitions", lib)
	anim_player.animation_finished.connect(_on_anim_finished)

	# Build AnimationTree state machine
	var sm := AnimationNodeStateMachine.new()
	anim_tree.tree_root = sm
	anim_tree.anim_player = anim_player.get_path()

	# Add state nodes
	var idle_node := AnimationNodeAnimation.new()
	var run_node := AnimationNodeAnimation.new()
	var jump_node := AnimationNodeAnimation.new()
	var slide_node := AnimationNodeAnimation.new()
	var land_node := AnimationNodeAnimation.new()
	var hit_node := AnimationNodeAnimation.new()

	sm.add_node("Idle", idle_node)
	sm.add_node("Run", run_node)
	sm.add_node("Jump", jump_node)
	sm.add_node("Slide", slide_node)
	sm.add_node("Land", land_node)
	sm.add_node("Hit", hit_node)

	# Transition nodes (crossfade, 0.08s)
	var tr_idle_run := AnimationNodeStateMachineTransition.new()
	tr_idle_run.xfade_time = 0.08
	var tr_run_jump := AnimationNodeStateMachineTransition.new()
	tr_run_jump.xfade_time = 0.05
	var tr_run_slide := AnimationNodeStateMachineTransition.new()
	tr_run_slide.xfade_time = 0.05
	var tr_jump_land := AnimationNodeStateMachineTransition.new()
	tr_jump_land.xfade_time = 0.08
	var tr_land_run := AnimationNodeStateMachineTransition.new()
	tr_land_run.xfade_time = 0.08
	var tr_slide_run := AnimationNodeStateMachineTransition.new()
	tr_slide_run.xfade_time = 0.08
	var tr_hit := AnimationNodeStateMachineTransition.new()
	tr_hit.xfade_time = 0.05
	var tr_land_idle := AnimationNodeStateMachineTransition.new()
	tr_land_idle.xfade_time = 0.15

	sm.add_transition("Idle", "Run", tr_idle_run)
	sm.add_transition("Run", "Jump", tr_run_jump)
	sm.add_transition("Run", "Slide", tr_run_slide)
	sm.add_transition("Jump", "Land", tr_jump_land)
	sm.add_transition("Land", "Run", tr_land_run)
	sm.add_transition("Slide", "Run", tr_slide_run)
	sm.add_transition("Jump", "Hit", tr_hit)
	sm.add_transition("Run", "Hit", tr_hit)
	sm.add_transition("Slide", "Hit", tr_hit)
	sm.add_transition("Idle", "Hit", tr_hit)
	sm.add_transition("Land", "Idle", tr_land_idle)

	anim_tree.active = true

func _on_anim_finished(anim_name: String) -> void:
	match anim_name:
		"blend_to_land":
			if is_on_floor() and can_move:
				_transition_to(AnimState.RUN)
		"blend_to_hit":
			pass  # handled by game.gd

func _transition_to(state: AnimState) -> void:
	if state == AnimState.HIT:
		hit_react_timer = 0.35
	current_anim = state

func _physics_process(delta: float) -> void:
	if not can_move:
		if hit_react_timer > 0.0:
			hit_react_timer -= delta
			_animate_hit(delta)
		else:
			_animate_idle(delta)
		return
	run_time += delta

	var target_x: float = LANES[current_lane]
	lane_motion = lerpf(lane_motion, target_x - position.x, delta * 10.0)
	position.x = move_toward(position.x, target_x, SWITCH_SPEED * delta)

	var _was_on_floor := is_on_floor()
	if not is_on_floor():
		velocity.y -= GRAVITY_VAL * delta
		was_in_air = true
		jump_phase += delta

	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0:
			end_slide()

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
		jump_count = 0
		if was_in_air:
			was_in_air = false
			land_squash = 0.18
			jump_phase = 0.0
			_transition_to(AnimState.LAND)
			landed.emit()

	move_and_slide()

	# Smooth land squash recovery
	if land_squash > 0.001:
		land_squash = lerpf(land_squash, 0.0, delta * 12.0)

	# Procedural animation (driven by state)
	if can_move:
		if is_on_floor() and not is_sliding:
			_animate_run(delta)
		elif is_sliding:
			_animate_slide(delta)
		else:
			_animate_jump(delta)

	# Lane change tilt
	var dx: float = target_x - position.x
	rotation.z = lerpf(rotation.z, clampf(-dx * 0.075, -0.24, 0.24), delta * 12.0)

	# Obstacle collision (with vaulting over low obstacles)
	if can_move:
		for i in get_slide_collision_count():
			var collision := get_slide_collision(i)
			var collider := collision.get_collider()
			if collider and collider.has_meta(&"obstacle"):
				var obs_kind: String = collider.get_meta(&"kind")
				# Vault over crates and low barriers when jumping high enough
				if (obs_kind == "crate" or obs_kind == "barrier") and global_position.y > 1.6:
					continue
				if obs_kind == "roof_train" and global_position.y > 2.45:
					continue
				if obs_kind == "gate" and is_sliding:
					continue
				_transition_to(AnimState.HIT)
				hit_obstacle.emit(obs_kind)
				break

func _animate_run(_delta: float) -> void:
	if current_anim != AnimState.RUN:
		_transition_to(AnimState.RUN)
	var cycle_speed: float = 11.5
	var t: float = run_time * cycle_speed
	var bob: float = sin(t) * 0.1
	var arm_swing: float = sin(t) * 0.92
	var leg_swing: float = cos(t) * 0.86
	var lane_twist: float = clampf(lane_motion * 0.12, -0.22, 0.22)
	var spine_lean: float = 0.20 + abs(lane_twist) * 0.35
	var spine_twist: float = sin(t * 0.5) * 0.1 + lane_twist
	var head_bob: float = -bob * 1.5
	var hair_sway: float = sin(t * 0.8 + 1.5) * 0.18 - lane_twist * 0.8
	var hair_secondary: float = cos(t * 1.2) * 0.1

	var squash_scale: float = 1.0 - land_squash
	var stretch_scale: float = 1.0 + land_squash * 0.5
	model_root.scale = Vector3(stretch_scale, squash_scale, stretch_scale)
	model_root.position.y = 1.0 + bob - land_squash * 0.3
	model_root.rotation.y = lerpf(model_root.rotation.y, lane_twist * 0.8, _delta * 10.0)
	model_root.rotation.x = lerpf(model_root.rotation.x, 0.03 + land_squash * 0.4, _delta * 10.0)

	if skeleton:
		if arm_l_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_l_idx, Quaternion(Vector3(1, 0, 0), 0.1) * Quaternion(Vector3(0, 1, 0), arm_swing))
		if arm_r_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_r_idx, Quaternion(Vector3(1, 0, 0), 0.1) * Quaternion(Vector3(0, 1, 0), -arm_swing))
		if forearm_l_idx >= 0:
			skeleton.set_bone_pose_rotation(forearm_l_idx, Quaternion(Vector3(1, 0, 0), 0.25 + abs(arm_swing) * 0.3))
		if forearm_r_idx >= 0:
			skeleton.set_bone_pose_rotation(forearm_r_idx, Quaternion(Vector3(1, 0, 0), 0.25 + abs(arm_swing) * 0.3))
		if shoulder_l_idx >= 0:
			skeleton.set_bone_pose_rotation(shoulder_l_idx, Quaternion(Vector3(0, 1, 0), arm_swing * 0.15))
		if shoulder_r_idx >= 0:
			skeleton.set_bone_pose_rotation(shoulder_r_idx, Quaternion(Vector3(0, 1, 0), -arm_swing * 0.15))
		if leg_l_idx >= 0:
			skeleton.set_bone_pose_rotation(leg_l_idx, Quaternion(Vector3(1, 0, 0), 0.05) * Quaternion(Vector3(0, 1, 0), leg_swing))
		if leg_r_idx >= 0:
			skeleton.set_bone_pose_rotation(leg_r_idx, Quaternion(Vector3(1, 0, 0), 0.05) * Quaternion(Vector3(0, 1, 0), -leg_swing))
		if thigh_l_idx >= 0:
			skeleton.set_bone_pose_rotation(thigh_l_idx, Quaternion(Vector3(0, 1, 0), leg_swing * 0.6))
		if thigh_r_idx >= 0:
			skeleton.set_bone_pose_rotation(thigh_r_idx, Quaternion(Vector3(0, 1, 0), -leg_swing * 0.6))
		if spine_idx >= 0:
			skeleton.set_bone_pose_rotation(spine_idx, Quaternion(Vector3(1, 0, 0), spine_lean) * Quaternion(Vector3(0, 0, 1), spine_twist))
		if spine2_idx >= 0:
			skeleton.set_bone_pose_rotation(spine2_idx, Quaternion(Vector3(1, 0, 0), spine_lean * 0.5))
		if head_idx >= 0:
			skeleton.set_bone_pose_rotation(head_idx, Quaternion(Vector3(1, 0, 0), head_bob))
		if neck_idx >= 0:
			skeleton.set_bone_pose_rotation(neck_idx, Quaternion(Vector3(1, 0, 0), head_bob * 0.5))
		if hair_l_start >= 0:
			for hi in range(9):
				var sk: int = hair_l_start + hi
				if sk < skeleton.get_bone_count():
					skeleton.set_bone_pose_rotation(sk,
						Quaternion(Vector3(0, 0, 1), hair_sway * (1.0 + hi * 0.25)) *
						Quaternion(Vector3(1, 0, 0), hair_secondary * (1.0 + hi * 0.15))
					)

func _animate_jump(_delta: float) -> void:
	if current_anim != AnimState.JUMP:
		_transition_to(AnimState.JUMP)
	var tuck: float = clampf(jump_phase * 3.0, 0.0, 1.0)
	var rise: float = clampf(velocity.y / JUMP_VEL, -1.0, 1.0)
	var double_flip: float = 0.0
	if jump_count > 1:
		double_flip = sin(clampf(jump_phase * 5.0, 0.0, PI)) * 0.55
	model_root.position.y = 1.0 + velocity.y * 0.02
	model_root.scale = Vector3(1.0 + tuck * 0.12, 1.0 - tuck * 0.18 + maxf(rise, 0.0) * 0.08, 1.0 + tuck * 0.12)
	model_root.rotation.x = lerpf(model_root.rotation.x, -0.12 + double_flip, _delta * 8.0)
	model_root.rotation.y = lerpf(model_root.rotation.y, clampf(lane_motion * 0.08, -0.18, 0.18), _delta * 8.0)

	if skeleton:
		if arm_l_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_l_idx, Quaternion(Vector3(1, 0, 0), -0.85 * tuck) * Quaternion(Vector3(0, 1, 0), 0.42 * tuck))
		if arm_r_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_r_idx, Quaternion(Vector3(1, 0, 0), -0.85 * tuck) * Quaternion(Vector3(0, 1, 0), -0.42 * tuck))
		if leg_l_idx >= 0:
			skeleton.set_bone_pose_rotation(leg_l_idx, Quaternion(Vector3(1, 0, 0), 0.95 * tuck))
		if leg_r_idx >= 0:
			skeleton.set_bone_pose_rotation(leg_r_idx, Quaternion(Vector3(1, 0, 0), 0.7 * tuck))
		if spine_idx >= 0:
			skeleton.set_bone_pose_rotation(spine_idx, Quaternion(Vector3(1, 0, 0), 0.08 + tuck * 0.28 + double_flip * 0.25))
		if hair_l_start >= 0:
			for hi in range(9):
				var sk: int = hair_l_start + hi
				if sk < skeleton.get_bone_count():
					skeleton.set_bone_pose_rotation(sk, Quaternion(Vector3(1, 0, 0), -0.3 * tuck * (1.0 + hi * 0.1)))

func _animate_slide(_delta: float) -> void:
	if current_anim != AnimState.SLIDE:
		_transition_to(AnimState.SLIDE)
	var slide_progress: float = 1.0 - clampf(slide_timer / SLIDE_DUR, 0.0, 1.0)
	var settle: float = sin(slide_progress * PI)
	model_root.position.y = lerpf(model_root.position.y, 0.42, _delta * 16.0)
	model_root.scale = Vector3(1.12, 0.46, 1.08)
	model_root.rotation.x = lerpf(model_root.rotation.x, -0.42 - settle * 0.15, _delta * 14.0)
	model_root.rotation.y = lerpf(model_root.rotation.y, clampf(lane_motion * 0.08, -0.15, 0.15), _delta * 10.0)

	if skeleton:
		if arm_l_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_l_idx, Quaternion(Vector3(1, 0, 0), 0.75) * Quaternion(Vector3(0, 1, 0), -0.85))
		if arm_r_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_r_idx, Quaternion(Vector3(1, 0, 0), 0.75) * Quaternion(Vector3(0, 1, 0), 0.85))
		if leg_l_idx >= 0:
			skeleton.set_bone_pose_rotation(leg_l_idx, Quaternion(Vector3(1, 0, 0), 1.05))
		if leg_r_idx >= 0:
			skeleton.set_bone_pose_rotation(leg_r_idx, Quaternion(Vector3(1, 0, 0), -0.18))
		if spine_idx >= 0:
			skeleton.set_bone_pose_rotation(spine_idx, Quaternion(Vector3(1, 0, 0), -0.42))
		if head_idx >= 0:
			skeleton.set_bone_pose_rotation(head_idx, Quaternion(Vector3(1, 0, 0), 0.3))

func _animate_hit(_delta: float) -> void:
	var t: float = clampf(hit_react_timer / 0.35, 0.0, 1.0)
	model_root.position.y = lerpf(model_root.position.y, 0.9, _delta * 8.0)
	model_root.scale = Vector3(1.05, 0.9, 1.1)
	model_root.rotation.x = lerpf(model_root.rotation.x, 0.55 * t, _delta * 12.0)
	model_root.rotation.z = lerpf(model_root.rotation.z, 0.22 * sin(t * PI), _delta * 12.0)
	if skeleton:
		if arm_l_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_l_idx, Quaternion(Vector3(1, 0, 0), -0.9) * Quaternion(Vector3(0, 1, 0), -0.7))
		if arm_r_idx >= 0:
			skeleton.set_bone_pose_rotation(arm_r_idx, Quaternion(Vector3(1, 0, 0), -0.9) * Quaternion(Vector3(0, 1, 0), 0.7))
		if spine_idx >= 0:
			skeleton.set_bone_pose_rotation(spine_idx, Quaternion(Vector3(1, 0, 0), -0.35))
		if head_idx >= 0:
			skeleton.set_bone_pose_rotation(head_idx, Quaternion(Vector3(1, 0, 0), 0.45))

func _animate_idle(delta: float) -> void:
	if current_anim != AnimState.IDLE:
		_transition_to(AnimState.IDLE)
	idle_time += delta
	var breath: float = sin(idle_time * 1.5) * 0.015
	model_root.position.y = 1.0 + breath
	model_root.scale = Vector3(1.0 + breath, 1.0 - breath * 0.5, 1.0 + breath)
	model_root.rotation = model_root.rotation.lerp(Vector3.ZERO, delta * 6.0)

	if skeleton:
		if spine_idx >= 0:
			skeleton.set_bone_pose_rotation(spine_idx, Quaternion(Vector3(1, 0, 0), breath * 1.5))
		if head_idx >= 0:
			skeleton.set_bone_pose_rotation(head_idx, Quaternion(Vector3(1, 0, 0), -breath * 2.0))
		if hair_l_start >= 0:
			for hi in range(9):
				var sk: int = hair_l_start + hi
				if sk < skeleton.get_bone_count():
					skeleton.set_bone_pose_rotation(sk, Quaternion(Vector3(0, 0, 1), sin(idle_time * 1.0 + hi * 0.3) * 0.04))

func switch_lane(dir: int) -> void:
	if not can_move: return
	current_lane = clampi(current_lane + dir, 0, 2)

func do_jump() -> void:
	if not can_move or is_sliding: return
	if is_on_floor():
		velocity.y = JUMP_VEL
		jump_count = 1
	elif jump_count < MAX_JUMPS:
		velocity.y = DOUBLE_JUMP_VEL
		jump_count += 1
	else:
		return
	jump_phase = 0.0
	_transition_to(AnimState.JUMP)
	jumped.emit()

func do_slide() -> void:
	if not can_move or not is_on_floor() or is_sliding: return
	is_sliding = true
	slide_timer = SLIDE_DUR
	model_root.position.y = 0.5
	model_root.scale = Vector3(1.0, 0.5, 1.0)
	collide_shape.disabled = true
	slide_shape.disabled = false
	_transition_to(AnimState.SLIDE)
	slid.emit()

func end_slide() -> void:
	is_sliding = false
	model_root.position.y = 1.0
	model_root.scale = Vector3(1.0, 1.0, 1.0)
	model_root.rotation.x = 0.0
	collide_shape.disabled = false
	slide_shape.disabled = true
	if is_on_floor() and can_move:
		_transition_to(AnimState.RUN)

func freeze() -> void:
	can_move = false
	if current_anim != AnimState.HIT:
		_transition_to(AnimState.IDLE)

func unfreeze() -> void:
	can_move = true
	_transition_to(AnimState.RUN)
