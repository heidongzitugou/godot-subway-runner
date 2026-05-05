extends Node3D
signal game_over(score: int, coins: int, best: int)

const BEST_KEY := "subway_best"
const LANE_X: Array[float] = [-3.0, 0.0, 3.0]
const BUILD_COLORS: Array[Color] = [
	Color8(57, 200, 190),   # Miku Teal
	Color8(240, 100, 150),  # Sakura Pink
	Color8(100, 180, 255),  # Light Blue
	Color8(255, 215, 70),   # Miku Gold
	Color8(180, 120, 220),  # Purple
	Color8(255, 150, 100),  # Orange
	Color8(140, 210, 255),  # Ice Blue
	Color8(220, 160, 220),  # Lavender
]
const DETAIL_COLORS: Array[Color] = [
	Color8(200, 245, 255),  # Cyan-white
	Color8(255, 220, 235),  # Pink-white
	Color8(220, 240, 255),  # Blue-white
	Color8(255, 250, 225),  # Warm white
	Color8(240, 225, 255),  # Purple-white
	Color8(255, 235, 220),  # Orange-white
	Color8(220, 255, 240),  # Mint-white
	Color8(200, 230, 255),  # Sky-white
]
const POOL_SIZE := 20
const WORLD_TILE_LENGTH := 120.0
const WORLD_LOOP_LENGTH := WORLD_TILE_LENGTH * 2.0
const CAMERA_BASE_FOV := 72.0
const CAMERA_DASH_FOV := 82.0

# KayKit building model paths
const KAYKIT_BUILDINGS := [
	"res://assets/models/buildings/building_A.gltf",
	"res://assets/models/buildings/building_B.gltf",
	"res://assets/models/buildings/building_C.gltf",
	"res://assets/models/buildings/building_D.gltf",
	"res://assets/models/buildings/building_E.gltf",
	"res://assets/models/buildings/building_F.gltf",
	"res://assets/models/buildings/building_G.gltf",
	"res://assets/models/buildings/building_H.gltf",
]

const KAYKIT_DECOR := [
	"res://assets/models/buildings/streetlight.gltf",
	"res://assets/models/buildings/bench.gltf",
	"res://assets/models/buildings/bush.gltf",
	"res://assets/models/buildings/trafficlight_A.gltf",
]
const TRAIN_MODEL := "res://assets/models/train/Train_2_by_get3dmodels.glb"
const TRAIN_BLOCKER_SCALE := Vector3(0.155, 0.078, 0.17)
const TRAIN_MOVING_SCALE := Vector3(0.135, 0.068, 0.135)
const TRAIN_ROOF_SCALE := Vector3(0.145, 0.07, 0.18)
const TRAIN_AMBIENT_SCALE := Vector3(0.105, 0.055, 0.14)
const SHIELD_MODEL := "res://assets/models/powerups/blue/power_blue.gltf"
const MAGNET_MODEL := "res://assets/models/powerups/red/star_red.gltf"
const DOUBLE_MODEL := "res://assets/models/powerups/yellow/diamond_yellow.gltf"
static var _kaykit_cache: Array = []
static var _decor_cache: Array = []

@onready var player: CharacterBody3D = $Player
@onready var hud_node: CanvasLayer = $HUD
@onready var coin_sound: AudioStreamPlayer = $CoinSound
@onready var jump_sound: AudioStreamPlayer = $JumpSound
@onready var hit_sound: AudioStreamPlayer = $HitSound
@onready var game_camera: Camera3D = $Camera3D

var score: int = 0
var coins: int = 0
var combo: int = 1
var combo_timer: float = 0.0
var speed: float = 1.0
var distance: float = 0.0
var world_speed: float = 8.0
var obst_timer: float = 0.0
var coin_timer: float = 0.0
var power_timer: float = 5.0
var running: bool = false
var paused: bool = false
var best: int = 0
var obstacles: Array[Node] = []
var coin_items: Array[Node] = []
var shake_amount: float = 0.0
var shield_time: float = 0.0
var magnet_time: float = 0.0
var dash_time: float = 0.0
var building_nodes_left: Array[Node] = []
var building_nodes_right: Array[Node] = []
var _all_buildings: Array[Node3D] = []
var atmos_timer: float = 10.0
var atmosphere_trains: Array[Node] = []
var world_poles: Array[Node] = []
var _sleepers: Array[Node] = []
var _rails: Array[Node] = []
var _world_segments: Array[Node] = []
var double_score_timer: float = 0.0
var last_milestone: int = 0
var bgm_cached: AudioStreamWAV = null
var score_bank: float = 0.0

var _obstacle_pool: Array[StaticBody3D] = []
var _coin_node_pool: Array[Node3D] = []
var _coin_mesh: MeshInstance3D = null
var _coin_star: MeshInstance3D = null
var _powerup_meshes: Dictionary = {}

static var _mat_cache: Dictionary = {}

var _touch_start: Vector2 = Vector2.ZERO
var _touch_id: int = -1
var _last_tap_time: int = 0

var _flash_overlay: ColorRect = null
var _flash_timer: float = 0.0
var _fever_overlay: ColorRect = null
var _player_fx_root: Node3D = null
var _player_fx_nodes: Array[MeshInstance3D] = []
var _visual_phase: float = 0.0
var _clouds: Array[TextureRect] = []
var _cloud_layer: CanvasLayer = null
var _hit_cooldown: float = 0.0

const BGM_PATH := "res://bgm.mp3"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	best = load_best()
	init_pools()
	setup_environment()
	setup_sounds()
	setup_effects()
	setup_clouds()

func init_pools() -> void:
	for i in POOL_SIZE:
		var obs := StaticBody3D.new()
		obs.set_meta(&"obstacle", true)
		obs.visible = false
		_obstacle_pool.append(obs)
		add_child(obs)

		var coin := Node3D.new()
		coin.visible = false
		coin.set_meta(&"coin", true)
		_coin_node_pool.append(coin)
		add_child(coin)

	# Coin mesh template
	_coin_mesh = MeshInstance3D.new()
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 0.4; cmesh.bottom_radius = 0.4; cmesh.height = 0.08
	var cmat := pbr_mat(Color8(255, 205, 55), 0.65, 0.12, Color8(255, 170, 20), 0.8)
	cmesh.material = cmat
	_coin_mesh.mesh = cmesh
	_coin_mesh.rotation.x = PI / 2.0

	_coin_star = MeshInstance3D.new()
	var smesh := CylinderMesh.new()
	smesh.top_radius = 0.2; smesh.bottom_radius = 0.2; smesh.height = 0.09
	var smat := pbr_mat(Color8(57, 240, 220), 0.55, 0.1, Color8(57, 200, 190), 1.0)
	smesh.material = smat
	_coin_star.mesh = smesh
	_coin_star.rotation.x = PI / 2.0

	# Powerup meshes - KayKit 3D models
	if ResourceLoader.exists(SHIELD_MODEL):
		var shield_mdl = load(SHIELD_MODEL)
		if shield_mdl:
			var s_inst: Node3D = shield_mdl.instantiate()
			s_inst.scale = Vector3(1.5, 1.5, 1.5)
			_powerup_meshes["shield"] = s_inst
	if not _powerup_meshes.has("shield"):
		_powerup_meshes["shield"] = make_powerup_fallback("shield")
	if ResourceLoader.exists(MAGNET_MODEL):
		var magnet_mdl = load(MAGNET_MODEL)
		if magnet_mdl:
			var m_inst: Node3D = magnet_mdl.instantiate()
			m_inst.scale = Vector3(1.5, 1.5, 1.5)
			_powerup_meshes["magnet"] = m_inst
	if not _powerup_meshes.has("magnet"):
		_powerup_meshes["magnet"] = make_powerup_fallback("magnet")
	if ResourceLoader.exists(DOUBLE_MODEL):
		var double_mdl = load(DOUBLE_MODEL)
		if double_mdl:
			var d_inst: Node3D = double_mdl.instantiate()
			d_inst.scale = Vector3(1.45, 1.45, 1.45)
			_powerup_meshes["double"] = d_inst
	if not _powerup_meshes.has("double"):
		_powerup_meshes["double"] = make_powerup_fallback("double")
	_powerup_meshes["dash"] = make_powerup_fallback("dash")

func make_powerup_fallback(kind: String) -> Node3D:
	var root := Node3D.new()
	var glow_color := Color8(57, 200, 190)
	if kind == "magnet":
		glow_color = Color8(255, 100, 150)
	elif kind == "double":
		glow_color = Color8(255, 215, 70)
	elif kind == "dash":
		glow_color = Color8(120, 180, 255)

	var core := MeshInstance3D.new()
	core.mesh = SphereMesh.new()
	core.mesh.radius = 0.35
	core.mesh.height = 0.7
	core.mesh.material = pbr_mat(glow_color, 0.25, 0.18, glow_color, 1.4)
	root.add_child(core)

	var ring := MeshInstance3D.new()
	ring.mesh = TorusMesh.new()
	ring.mesh.inner_radius = 0.34
	ring.mesh.outer_radius = 0.48
	ring.mesh.material = pbr_mat(Color8(220, 255, 250), 0.1, 0.25, glow_color, 0.9)
	ring.rotation.x = PI / 2.0
	root.add_child(ring)
	return root

func get_obstacle() -> StaticBody3D:
	for o in _obstacle_pool:
		if not o.visible:
			return o
	var o2 := StaticBody3D.new()
	o2.set_meta(&"obstacle", true)
	_obstacle_pool.append(o2)
	add_child(o2)
	return o2

func return_obstacle(obj: Node) -> void:
	if not is_instance_valid(obj): return
	obj.visible = false
	for c in obj.get_children():
		c.call_deferred(&"queue_free")

func get_coin_node() -> Node3D:
	for c in _coin_node_pool:
		if not c.visible:
			return c
	var c2 := Node3D.new()
	c2.set_meta(&"coin", true)
	_coin_node_pool.append(c2)
	add_child(c2)
	return c2

func return_coin_node(c: Node3D) -> void:
	if not is_instance_valid(c): return
	c.visible = false
	for child in c.get_children():
		child.call_deferred(&"queue_free")

func setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# Better sky with gradient
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color8(30, 80, 140)
	sky_mat.sky_horizon_color = Color8(160, 210, 240)
	sky_mat.ground_horizon_color = Color8(140, 180, 200)
	sky_mat.ground_bottom_color = Color8(60, 90, 110)
	sky_mat.sun_angle_max = 90.0
	sky_mat.sun_curve = 0.15
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	# Enhanced glow for neon/cyberpunk feel
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.85
	# Height fog for depth
	env.fog_enabled = true
	env.fog_light_color = Color8(170, 210, 240)
	env.fog_density = 0.0008
	env.fog_aerial_perspective = 0.4
	# Volumetric fog — light shafts and atmosphere (forward_plus)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_emission = Color8(180, 200, 230)
	env.volumetric_fog_emission_energy = 0.4
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_detail_spread = 2.0
	# SSIL for enhanced ambient occlusion (forward_plus)
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	env.ssil_normal_rejection = 0.4
	# SSAO
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 1.0
	env.ssao_light_affect = 0.35
	# Color adjustment
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 1.03

	we.environment = env
	add_child(we)
	move_child(we, 0)

	build_world()

	if is_instance_valid(game_camera):
		game_camera.look_at(Vector3(0.0, 1.8, -10.0), Vector3.UP)

func build_world() -> void:
	# Ground collision
	var ground_body := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	ground_col.shape = BoxShape3D.new()
	ground_col.shape.size = Vector3(40, 0.4, 120)
	ground_body.position = Vector3(0, -0.2, 0)
	ground_body.add_child(ground_col)
	add_child(ground_body)

	# Build world in 2 tiles for seamless scrolling
	for tile_idx in 2:
		var tz: float = -tile_idx * WORLD_TILE_LENGTH
		_build_world_tile(tz)
	build_buildings()
	build_miku_stage_decor()

func _build_world_tile(tz: float) -> void:
	# Main grass ground
	var gnd := MeshInstance3D.new()
	gnd.mesh = BoxMesh.new()
	gnd.mesh.size = Vector3(40, 0.15, 120)
	gnd.mesh.material = _load_tex("res://assets/textures/kenney/green_01.png", Color8(60, 160, 60), 10, 30, 0.95)
	gnd.position = Vector3(0, -0.08, tz)
	add_child(gnd)
	_world_segments.append(gnd)

	# Side grass strips
	for side in [-1, 1]:
		var side_grass := MeshInstance3D.new()
		side_grass.mesh = BoxMesh.new()
		side_grass.mesh.size = Vector3(14, 0.16, 120)
		side_grass.mesh.material = _load_tex("res://assets/textures/kenney/green_06.png", Color8(50, 150, 50), 4, 30, 0.95)
		side_grass.position = Vector3(side * 13.0, -0.07, tz)
		add_child(side_grass)
		_world_segments.append(side_grass)

	# Track bed
	var bed_mat = _load_tex("res://assets/textures/ground/gravel.png", Color8(145, 100, 60), 3, 30, 0.9)
	var bed := MeshInstance3D.new()
	bed.mesh = BoxMesh.new()
	bed.mesh.size = Vector3(10.0, 0.25, 120)
	bed.mesh.material = bed_mat
	bed.position = Vector3(0, 0.0, tz)
	add_child(bed)
	_world_segments.append(bed)

	# Wooden sleepers (30 per tile, 4m apart)
	var sleeper_mat = _load_tex("res://assets/textures/ground/wood.png", Color8(135, 85, 50), 0.5, 0.1, 0.95)
	for i in 30:
		var sleeper := MeshInstance3D.new()
		sleeper.mesh = BoxMesh.new()
		sleeper.mesh.size = Vector3(9.5, 0.18, 0.35)
		sleeper.mesh.material = sleeper_mat
		sleeper.position = Vector3(0, 0.09, tz - i * 4.0 + 2)
		add_child(sleeper)
		_sleepers.append(sleeper)

	# Rails
	for lane_i in 3:
		var lx: float = LANE_X[lane_i]
		for offset in [-0.6, 0.6]:
			var rail := MeshInstance3D.new()
			rail.mesh = BoxMesh.new()
			rail.mesh.size = Vector3(0.08, 0.14, 120)
			var rail_mat := StandardMaterial3D.new()
			rail_mat.albedo_color = Color8(190, 195, 200)
			rail_mat.metallic = 0.9; rail_mat.roughness = 0.35
			rail.mesh.material = rail_mat
			rail.position = Vector3(lx + offset, 0.22, tz)
			add_child(rail)
			_rails.append(rail)
		for offset in [-0.6, 0.6]:
			var rail_top := MeshInstance3D.new()
			rail_top.mesh = BoxMesh.new()
			rail_top.mesh.size = Vector3(0.06, 0.015, 120)
			var rtop_mat := StandardMaterial3D.new()
			rtop_mat.albedo_color = Color8(230, 235, 240)
			rtop_mat.metallic = 0.95; rtop_mat.roughness = 0.15
			rail_top.mesh.material = rtop_mat
			rail_top.position = Vector3(lx + offset, 0.3, tz)
			add_child(rail_top)
			_rails.append(rail_top)

	# Lane dividers
	for div_x in [-1.5, 1.5]:
		var divider := MeshInstance3D.new()
		divider.mesh = BoxMesh.new()
		divider.mesh.size = Vector3(0.04, 0.01, 120)
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(1, 1, 1, 0.12)
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		divider.mesh.material = dmat
		divider.position = Vector3(div_x, 0.26, tz)
		add_child(divider)
		_world_segments.append(divider)

		var neon := MeshInstance3D.new()
		neon.mesh = BoxMesh.new()
		neon.mesh.size = Vector3(0.08, 0.02, WORLD_TILE_LENGTH)
		neon.mesh.material = pbr_mat(Color8(57, 200, 190), 0.0, 0.25, Color8(57, 200, 190), 1.2)
		neon.position = Vector3(div_x, 0.34, tz)
		add_child(neon)
		_world_segments.append(neon)

	# Track edge curbs
	var curb_mat = _load_tex("res://assets/textures/ground/concrete.png", Color8(175, 140, 105), 0.5, 0.1, 0.85)
	for side in [-1, 1]:
		var curb := MeshInstance3D.new()
		curb.mesh = BoxMesh.new()
		curb.mesh.size = Vector3(0.3, 0.35, 120)
		curb.mesh.material = curb_mat
		curb.position = Vector3(side * 5.0, 0.1, tz)
		add_child(curb)
		_world_segments.append(curb)

	# Miku-style LED guard panels along both sides of the track.
	for side in [-1, 1]:
		for i in 6:
			var panel := MeshInstance3D.new()
			panel.mesh = BoxMesh.new()
			panel.mesh.size = Vector3(0.08, 1.0, 8.0)
			var panel_col := Color8(57, 200, 190) if i % 2 == 0 else Color8(255, 100, 170)
			panel.mesh.material = pbr_mat(Color8(18, 28, 38), 0.1, 0.35, panel_col, 0.55)
			panel.position = Vector3(side * 5.35, 1.0, tz - 8.0 - i * 18.0)
			add_child(panel)
			_world_segments.append(panel)

			var edge := MeshInstance3D.new()
			edge.mesh = BoxMesh.new()
			edge.mesh.size = Vector3(0.1, 0.05, 8.2)
			edge.mesh.material = pbr_mat(panel_col, 0.0, 0.25, panel_col, 1.2)
			edge.position = Vector3(side * 5.28, 1.55, tz - 8.0 - i * 18.0)
			add_child(edge)
			_world_segments.append(edge)

	# Overhead catenary wires
	for wx in [-2.0, 0.0, 2.0]:
		var wire := MeshInstance3D.new()
		wire.mesh = CylinderMesh.new()
		wire.mesh.top_radius = 0.02; wire.mesh.bottom_radius = 0.02; wire.mesh.height = 120
		wire.mesh.material = cached_mat(Color8(50, 50, 50), 0.4, 0.5)
		wire.rotation.x = PI / 2.0
		wire.position = Vector3(wx, 6.0, tz)
		add_child(wire)
		world_poles.append(wire)

	# Catenary poles with cross arms
	for pz in range(0, -130, -12):
		for side in [-1, 1]:
			var pole := MeshInstance3D.new()
			pole.mesh = CylinderMesh.new()
			pole.mesh.top_radius = 0.06; pole.mesh.bottom_radius = 0.08; pole.mesh.height = 6.5
			pole.mesh.material = tex_mat(Color8(90, 90, 90), 0.15, 0.4, 0.45, pz, 0.12)
			pole.position = Vector3(side * 5.2, 3.25, tz + pz)
			add_child(pole)
			world_poles.append(pole)
			var arm := MeshInstance3D.new()
			arm.mesh = BoxMesh.new()
			arm.mesh.size = Vector3(4.0, 0.1, 0.1)
			arm.mesh.material = cached_mat(Color8(80, 80, 80), 0.3, 0.5)
			arm.position = Vector3(side * 3.0, 6.3, tz + pz)
			add_child(arm)
			world_poles.append(arm)

func build_buildings() -> void:
	# Try loading KayKit models
	if _kaykit_cache.is_empty():
		for p in KAYKIT_BUILDINGS:
			if ResourceLoader.exists(p):
				var res = load(p)
				if res: _kaykit_cache.append(res)
		if _decor_cache.is_empty():
			for p in KAYKIT_DECOR:
				if ResourceLoader.exists(p):
					var res = load(p)
					if res: _decor_cache.append(res)

	for side in [-1, 1]:
		var list: Array[Node] = []
		for i in 28:
			var bw: float = 2.5 + randf() * 3.5
			var bh: float = 4.0 + randf() * 10.0
			var bd: float = 2.5 + randf() * 3.0
			var bz: float = -i * 8.5 - 6.0 + randf() * 2.0
			var bx: float = side * (6.5 + bw / 2.0 + randf() * 1.5)

			# Use KayKit 3D model if available
			if not _kaykit_cache.is_empty():
				var bldg: Node3D = _kaykit_cache[randi() % _kaykit_cache.size()].instantiate()
				bldg.position = Vector3(bx, 0, bz)
				var s: float = randf_range(2.0, 4.0)
				bldg.scale = Vector3(s, s * randf_range(1.0, 2.0), s)
				add_child(bldg)
				list.append(bldg)
				# Add street decoration every 2-3 buildings
				if i % 2 == 0 and not _decor_cache.is_empty():
					var dec: Node3D = _decor_cache[randi() % _decor_cache.size()].instantiate()
					dec.position = Vector3(side * (6.0 + randf() * 4.0), 0, bz + 4.0)
					dec.scale = Vector3.ONE * randf_range(1.5, 3.0)
					add_child(dec)
					list.append(dec)
				continue

			# Fallback: procedural buildings
			var bldg_root := Node3D.new()
			bldg_root.position = Vector3(bx, 0, bz)

			var body := MeshInstance3D.new()
			body.mesh = BoxMesh.new()
			body.mesh.size = Vector3(bw, bh, bd)
			var bcol: Color = BUILD_COLORS[i % BUILD_COLORS.size()]
			var body_mat := StandardMaterial3D.new()
			body_mat.albedo_color = bcol
			body_mat.metallic = 0.05; body_mat.roughness = 0.8
			if ResourceLoader.exists("res://assets/textures/kenney/green_08.png"):
				body_mat.albedo_texture = load("res://assets/textures/kenney/green_08.png")
				body_mat.uv1_scale = Vector3(bw / 2, bh / 2, 1)
			body.mesh.material = body_mat
			body.position.y = bh / 2.0
			bldg_root.add_child(body)

			# Roof with overhang
			var roof := MeshInstance3D.new()
			roof.mesh = BoxMesh.new()
			roof.mesh.size = Vector3(bw + 0.5, 0.35, bd + 0.5)
			var roof_mat := StandardMaterial3D.new()
			roof_mat.albedo_color = bcol.darkened(0.35)
			roof_mat.roughness = 0.7
			roof.mesh.material = roof_mat
			roof.position.y = bh + 0.18
			bldg_root.add_child(roof)

			# Windows with glow
			var win_cols: int = maxi(1, int(bw / 1.2))
			var win_rows: int = maxi(1, int(bh / 1.8))
			var face_z: float = -side * (bw / 2.0) - 0.01
			for r in win_rows:
				for c in win_cols:
					if randf() > 0.8: continue
					var win := MeshInstance3D.new()
					win.mesh = BoxMesh.new()
					win.mesh.size = Vector3(0.5, 0.7, 0.05)
					var wmat := StandardMaterial3D.new()
					wmat.albedo_color = Color8(255, 240, 220)
					if randf() > 0.5:
						wmat.emission_enabled = true
						wmat.emission = DETAIL_COLORS[i % DETAIL_COLORS.size()]
						wmat.emission_energy_multiplier = 0.5
					win.mesh.material = wmat
					var wx: float = -bw / 2.0 + 0.6 + c * (bw - 1.2) / maxf(1, win_cols - 1)
					var wy: float = 1.0 + r * (bh - 1.5) / maxf(1, win_rows)
					win.position = Vector3(wx, wy, face_z)
					bldg_root.add_child(win)
			add_child(bldg_root)
			list.append(bldg_root)
		if side == -1:
			building_nodes_left = list
		else:
			building_nodes_right = list
		_all_buildings.append_array(list)
	_add_vegetation()

func build_miku_stage_decor() -> void:
	var teal := pbr_mat(Color8(57, 200, 190), 0.0, 0.28, Color8(57, 200, 190), 1.1)
	var pink := pbr_mat(Color8(255, 100, 170), 0.0, 0.28, Color8(255, 100, 170), 0.9)
	var dark := pbr_mat(Color8(20, 28, 38), 0.2, 0.5, Color8(20, 60, 70), 0.15)

	for i in 8:
		var z := -18.0 - i * 26.0
		var arch := Node3D.new()
		arch.position = Vector3(0, 0, z)
		add_child(arch)
		_all_buildings.append(arch)

		for sx in [-1, 1]:
			var leg := MeshInstance3D.new()
			leg.mesh = CylinderMesh.new()
			leg.mesh.top_radius = 0.08
			leg.mesh.bottom_radius = 0.1
			leg.mesh.height = 7.2
			leg.mesh.material = teal
			leg.position = Vector3(sx * 5.4, 3.6, 0)
			arch.add_child(leg)

		var top := MeshInstance3D.new()
		top.mesh = BoxMesh.new()
		top.mesh.size = Vector3(10.8, 0.15, 0.15)
		top.mesh.material = teal
		top.position = Vector3(0, 7.15, 0)
		arch.add_child(top)

		for lx in [-3.4, 0.0, 3.4]:
			var lamp := MeshInstance3D.new()
			lamp.mesh = SphereMesh.new()
			lamp.mesh.radius = 0.16
			lamp.mesh.height = 0.32
			lamp.mesh.material = pink if int(abs(lx)) > 0 else teal
			lamp.position = Vector3(lx, 6.9, 0)
			arch.add_child(lamp)

	for i in 10:
		var side := -1 if i % 2 == 0 else 1
		var sign := Node3D.new()
		sign.position = Vector3(side * 8.2, 2.9, -12.0 - i * 21.0)
		sign.rotation.y = -side * PI / 2.0
		add_child(sign)
		_all_buildings.append(sign)

		var panel := MeshInstance3D.new()
		panel.mesh = BoxMesh.new()
		panel.mesh.size = Vector3(3.3, 1.45, 0.08)
		panel.mesh.material = dark
		sign.add_child(panel)

		var label := Label3D.new()
		label.text = "MIKU LIVE"
		label.font_size = 42
		label.modulate = Color8(57, 240, 220)
		label.outline_modulate = Color8(0, 0, 0)
		label.outline_size = 8
		label.position = Vector3(0, 0.08, 0.08)
		sign.add_child(label)

func setup_sounds() -> void:
	if coin_sound:
		coin_sound.stream = load("res://assets/audio/sfx/coin01.mp3")
		coin_sound.volume_db = -10.0
	if jump_sound:
		jump_sound.stream = load("res://assets/audio/sfx/jump.mp3")
		jump_sound.volume_db = -14.0
	if hit_sound:
		hit_sound.stream = load("res://assets/audio/sfx/hit.mp3")
		hit_sound.volume_db = -8.0
func _add_vegetation() -> void:
	var tree_colors := [Color8(60, 140, 60), Color8(45, 130, 50), Color8(80, 155, 70), Color8(50, 120, 55)]
	var bush_colors := [Color8(70, 150, 65), Color8(55, 135, 50), Color8(90, 160, 75)]
	var trunk_mat := pbr_mat(Color8(120, 85, 55), 0.0, 0.8)
	for side in [-1, 1]:
		var sx: float = side * (7.5 + randf() * 3.0)
		# Place vegetation at regular intervals
		for i in 28:
			var vz: float = -i * 4.5 - 2.0 + randf() * 2.0
			var roll: float = randf()
			if roll < 0.4:
				# Tree
				var tree := Node3D.new()
				tree.position = Vector3(sx + randf_range(-1.5, 1.5), 0, vz)
				var trunk := MeshInstance3D.new()
				trunk.mesh = CylinderMesh.new()
				trunk.mesh.top_radius = 0.08; trunk.mesh.bottom_radius = 0.12
				trunk.mesh.height = 1.5 + randf()
				trunk.mesh.material = trunk_mat
				trunk.position.y = trunk.mesh.height / 2.0
				tree.add_child(trunk)
				# Foliage layers
				for fi in 3:
					var foliage := MeshInstance3D.new()
					foliage.mesh = SphereMesh.new()
					var r: float = 0.4 - fi * 0.08
					foliage.mesh.radius = r; foliage.mesh.height = r * 2.0
					foliage.mesh.material = cached_mat(tree_colors[randi() % tree_colors.size()], 0.0, 0.85)
					foliage.position.y = trunk.mesh.height + fi * 0.3 - 0.1
					foliage.position.x = randf_range(-0.15, 0.15)
					tree.add_child(foliage)
				add_child(tree)
				_all_buildings.append(tree)
			elif roll < 0.75:
				# Bush cluster
				var bush := Node3D.new()
				bush.position = Vector3(sx + randf_range(-2.0, 2.0), 0, vz)
				for bi in randi_range(2, 4):
					var b := MeshInstance3D.new()
					b.mesh = SphereMesh.new()
					var br: float = randf_range(0.2, 0.45)
					b.mesh.radius = br; b.mesh.height = br * 2.0
					b.mesh.material = cached_mat(bush_colors[randi() % bush_colors.size()], 0.0, 0.9)
					b.position = Vector3(randf_range(-0.4, 0.4), br * 0.6, randf_range(-0.3, 0.3))
					bush.add_child(b)
				add_child(bush)
				_all_buildings.append(bush)

	if coin_sound:
		coin_sound.stream = load("res://assets/audio/sfx/coin01.mp3")
	if hit_sound:
		hit_sound.stream = load("res://assets/audio/sfx/hit.mp3")

func setup_clouds() -> void:
	_cloud_layer = CanvasLayer.new()
	_cloud_layer.layer = 1
	add_child(_cloud_layer)
	for i in 6:
		var cloud := TextureRect.new()
		var tex_path := "res://assets/particles/cloud_" + str(i) + ".png"
		cloud.texture = load(tex_path)
		cloud.self_modulate = Color(1, 1, 1, 0.65)
		cloud.position = Vector2(randf() * 1200, randf() * 180 + 10)
		cloud.size = Vector2(220, 70)
		cloud.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cloud_layer.add_child(cloud)
		_clouds.append(cloud)


func setup_effects() -> void:
	if not hud_node:
		return
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1, 0, 0, 0)
	_flash_overlay.size = Vector2(1200, 800)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.show_behind_parent = true
	hud_node.add_child(_flash_overlay)

	_fever_overlay = ColorRect.new()
	_fever_overlay.color = Color(0.0, 0.9, 0.85, 0.0)
	_fever_overlay.size = Vector2(1200, 800)
	_fever_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fever_overlay.show_behind_parent = true
	hud_node.add_child(_fever_overlay)
	setup_player_fx()

func setup_player_fx() -> void:
	if not is_instance_valid(player):
		return
	if _player_fx_root and is_instance_valid(_player_fx_root):
		_player_fx_root.queue_free()
	_player_fx_nodes.clear()

	_player_fx_root = Node3D.new()
	_player_fx_root.name = "MikuStatusFX"
	_player_fx_root.position = Vector3(0, 0.08, 0)
	_player_fx_root.visible = false
	player.add_child(_player_fx_root)

	var pad := MeshInstance3D.new()
	pad.mesh = CylinderMesh.new()
	pad.mesh.top_radius = 0.9
	pad.mesh.bottom_radius = 0.9
	pad.mesh.height = 0.025
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.15, 1.0, 0.9, 0.32)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color8(57, 240, 220)
	pad_mat.emission_energy_multiplier = 1.4
	pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad.mesh.material = pad_mat
	_player_fx_root.add_child(pad)
	_player_fx_nodes.append(pad)

	var colors := [Color8(57, 240, 220), Color8(255, 100, 170), Color8(255, 215, 70), Color8(120, 180, 255)]
	for i in 4:
		var note := MeshInstance3D.new()
		note.mesh = SphereMesh.new()
		note.mesh.radius = 0.08 + i * 0.01
		note.mesh.height = 0.18 + i * 0.02
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.emission_enabled = true
		mat.emission = colors[i]
		mat.emission_energy_multiplier = 1.8
		note.mesh.material = mat
		_player_fx_root.add_child(note)
		_player_fx_nodes.append(note)

func update_player_fx(dt: float) -> void:
	if not is_instance_valid(_player_fx_root):
		return
	var active := shield_time > 0 or magnet_time > 0 or double_score_timer > 0 or dash_time > 0 or combo >= 12
	_player_fx_root.visible = active
	if not active:
		return
	var intensity := 1.0
	if dash_time > 0:
		intensity = 1.6
	elif double_score_timer > 0:
		intensity = 1.35
	for i in _player_fx_nodes.size():
		var node := _player_fx_nodes[i]
		if not is_instance_valid(node):
			continue
		if i == 0:
			var pulse := 1.0 + sin(_visual_phase * 7.0) * 0.12
			node.scale = Vector3(pulse * intensity, 1.0, pulse * intensity)
			continue
		var angle := _visual_phase * (2.2 + i * 0.35) * intensity + float(i) * TAU / 4.0
		var radius := 0.48 + i * 0.1
		node.position = Vector3(cos(angle) * radius, 0.55 + sin(_visual_phase * 5.0 + i) * 0.18, sin(angle) * radius)
		node.scale = Vector3.ONE * (1.0 + sin(_visual_phase * 8.0 + i) * 0.12)

func make_tone(freq: float, dur: float, wave: String = "sine") -> AudioStreamWAV:
	var sr: int = 22050
	var n: int = int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / sr
		var s: float = sin(2.0 * PI * freq * t) if wave == "sine" else 2.0 * (freq * t - floor(freq * t + 0.5))
		var env: float = 1.0 - float(i) / n
		data.encode_s16(i * 2, clampi(int(s * env * 12000), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	return wav

func make_sweep(f1: float, f2: float, dur: float) -> AudioStreamWAV:
	var sr: int = 22050
	var n: int = int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / sr
		var freq: float = f1 + (f2 - f1) * (float(i) / n)
		var env: float = 1.0 - float(i) / n
		data.encode_s16(i * 2, clampi(int(sin(2.0 * PI * freq * t) * env * 12000), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	return wav

static func _load_tex(path: String, fallback_color: Color, uv_x: float, uv_y: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.uv1_scale = Vector3(uv_x, uv_y, 1)
	else:
		m.albedo_color = fallback_color
	m.roughness = rough
	return m

static func cached_mat(color: Color, met: float = 0.0, rough: float = 0.7) -> StandardMaterial3D:
	var key := str(color) + "_" + str(met) + "_" + str(rough)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = met
	m.roughness = rough
	_mat_cache[key] = m
	return m

static func pbr_mat(albedo: Color, met: float, rough: float, emit: Color = Color.BLACK, emit_energy: float = 0.0) -> StandardMaterial3D:
	var key := "pbr_" + str(albedo) + "_" + str(met) + "_" + str(rough) + "_" + str(emit) + "_" + str(emit_energy)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = met
	m.roughness = rough
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_energy
	_mat_cache[key] = m
	return m

# --- Procedural texture system ---

static var _tex_cache: Dictionary = {}

static func make_noise_tex(freq: float = 0.1, seed_: int = 0) -> NoiseTexture2D:
	var cache_key := "noise_" + str(freq) + "_" + str(seed_)
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key]
	var noise := FastNoiseLite.new()
	noise.frequency = freq
	noise.seed = seed_
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256; tex.height = 256
	_tex_cache[cache_key] = tex
	return tex

static func tex_mat(color: Color, freq: float = 0.08, met: float = 0.0, rough: float = 0.8, seed_: int = 0, tex_strength: float = 0.15) -> StandardMaterial3D:
	var key := "tex_" + str(color) + "_" + str(freq) + "_" + str(met) + "_" + str(rough) + "_" + str(seed_) + "_" + str(tex_strength)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color * (1.0 - tex_strength)
	m.metallic = met
	m.roughness = rough
	m.albedo_texture = make_noise_tex(freq, seed_)
	_tex_cache[key] = m
	return m

static func brick_mat(base_color: Color, brick_freq: float = 0.06, met: float = 0.0, rough: float = 0.8, seed_: int = 0) -> StandardMaterial3D:
	var key := "brick_" + str(base_color) + "_" + str(brick_freq) + "_" + str(met) + "_" + str(rough) + "_" + str(seed_)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var noise := FastNoiseLite.new()
	noise.frequency = brick_freq
	noise.seed = seed_
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 128; tex.height = 128

	var m := StandardMaterial3D.new()
	m.albedo_color = base_color * 0.7
	m.albedo_texture = tex
	m.metallic = met
	m.roughness = rough
	_tex_cache[key] = m
	return m

static func stripe_mat(color1: Color, color2: Color, stripe_freq: float = 4.0, met: float = 0.0, rough: float = 0.7) -> StandardMaterial3D:
	var key := "stripe_" + str(color1) + "_" + str(color2) + "_" + str(stripe_freq) + "_" + str(met) + "_" + str(rough)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var gtex := GradientTexture1D.new()
	gtex.width = 32
	var g := Gradient.new()
	g.set_color(0, color1)
	g.set_color(1, color2)
	gtex.gradient = g

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.albedo_texture = gtex
	m.uv1_scale = Vector3(stripe_freq, 1, 1)
	m.metallic = met
	m.roughness = rough
	_tex_cache[key] = m
	return m

func flash_screen(intensity: float = 0.4, duration: float = 0.2) -> void:
	if _flash_overlay:
		_flash_overlay.color = Color(1, 0.15, 0.15, intensity)
		_flash_timer = duration

func spawn_particles(world_pos: Vector3, color: Color, count: int = 8) -> void:
	var emitter := Node3D.new()
	emitter.position = world_pos
	add_child(emitter)

	var pmat := ParticleProcessMaterial.new()
	pmat.color = color
	pmat.particle_flag_align_y = false
	pmat.direction = Vector3.UP
	pmat.spread = 180.0
	pmat.gravity = Vector3(0, -5, 0)
	pmat.initial_velocity_min = 2.0
	pmat.initial_velocity_max = 5.0
	pmat.scale_min = 0.1
	pmat.scale_max = 0.25
	pmat.lifetime_randomness = 0.4

	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = 0.6
	p.process_material = pmat
	p.local_coords = false
	emitter.add_child(p)
	p.restart()
	var t := get_tree().create_timer(0.8)
	t.timeout.connect(emitter.queue_free)

func _process(delta: float) -> void:

	if not running or paused: return
	if not is_instance_valid(player): return

	var dt: float = minf(delta, 0.033)
	_visual_phase += dt
	var dash_boost := 1.45 if dash_time > 0 else 1.0
	distance += dt * world_speed * dash_boost
	speed = minf(3.25, 1.0 + distance / 10000.0)
	world_speed = 8.0 + speed * 5.0
	score_bank += dt * 24.0 * speed * combo * dash_boost * (2.0 if double_score_timer > 0 else 1.0)
	if score_bank >= 1.0:
		var score_delta := int(score_bank)
		score += score_delta
		score_bank -= score_delta
	combo_timer -= dt
	if combo_timer <= 0:
		combo = 1
	shield_time = maxf(0, shield_time - dt)
	magnet_time = maxf(0, magnet_time - dt)
	double_score_timer = maxf(0, double_score_timer - dt)
	dash_time = maxf(0, dash_time - dt)
	_hit_cooldown = maxf(0, _hit_cooldown - dt)
	shake_amount = maxf(0, shake_amount - dt * 10.0)
	update_hud()
	if _fever_overlay:
		var fever_alpha: float = 0.12 if double_score_timer > 0 or dash_time > 0 else 0.0
		_fever_overlay.color = _fever_overlay.color.lerp(Color(0.0, 0.9, 0.85, fever_alpha), dt * 5.0)
	update_player_fx(dt)

	# Scroll clouds slowly
	if _cloud_layer:
		for cloud in _clouds:
			if is_instance_valid(cloud):
				cloud.position.x -= dt * 15.0
				if cloud.position.x < -250:
					cloud.position.x = 1250

	# Milestone check (every 1000m)
	var m: int = int(distance / 1000.0)
	if m > last_milestone and m > 0:
		last_milestone = m
		score += m * 100
		flash_screen(0.2, 0.3)
		spawn_particles(player.global_position + Vector3(0, 1.5, 0), Color8(255, 215, 70), 20)

	obst_timer -= dt
	coin_timer -= dt
	power_timer -= dt
	atmos_timer -= dt

	if obst_timer <= 0:
		spawn_obstacle()
		obst_timer = maxf(0.65, 1.5 - speed * 0.06 - randf() * 0.15)
	if coin_timer <= 0:
		spawn_coins()
		coin_timer = 0.9 + randf() * 0.8
	if power_timer <= 0:
		spawn_powerup()
		if randf() > 0.7:
			spawn_double_score()
		power_timer = 6.0 + randf() * 5.0
	if atmos_timer <= 0:
		spawn_atmosphere_train()
		atmos_timer = 12.0 + randf() * 10.0

	if Input.is_action_just_pressed(&"ui_left"):
		player.switch_lane(-1)
	if Input.is_action_just_pressed(&"ui_right"):
		player.switch_lane(1)
	if Input.is_action_just_pressed(&"ui_up"):
		player.do_jump()

	if Input.is_action_just_pressed(&"ui_down"):
		player.do_slide()

	var mz: float = world_speed * dash_boost * dt
	for o in obstacles:
		if is_instance_valid(o):
			o.position.z += mz
			# Horizontal movement for moving trains
			if o.get_meta(&"moving", false):
				var move_dir: float = o.get_meta(&"move_dir", 0.0)
				o.position.x += move_dir * dt * 4.0
				if abs(o.position.x) > 4.5:
					o.set_meta(&"move_dir", -move_dir)
	for c in coin_items:
		if is_instance_valid(c):
			c.position.z += mz
			# Magnet attraction
			if magnet_time > 0 and is_instance_valid(player):
				var to_player: Vector3 = player.global_position - c.global_position
				var dist: float = to_player.length()
				if dist < 8.0:
					c.position += to_player.normalized() * dt * 15.0 * (1.0 - dist / 8.0)
			for child in c.get_children():
				if child is MeshInstance3D and child != c:
					child.rotation.y += dt * 5.0

	cleanup_passed(obstacles)
	cleanup_passed(coin_items)

	# Unified building scrolling
	for b in _all_buildings:
		if is_instance_valid(b):
			b.position.z += mz
			if b.position.z > 15.0:
				b.position.z -= WORLD_LOOP_LENGTH

	# Scroll sleepers
	for s in _sleepers:
		if is_instance_valid(s):
			s.position.z += mz
			if s.position.z > 15.0:
				s.position.z -= WORLD_LOOP_LENGTH
	# Scroll rails
	for r in _rails:
		if is_instance_valid(r):
			r.position.z += mz
			if r.position.z > 65.0:
				r.position.z -= WORLD_LOOP_LENGTH
	# Scroll world segments (ground, grass, bed, curbs, dividers)
	for ws in _world_segments:
		if is_instance_valid(ws):
			ws.position.z += mz
			if ws.position.z > 65.0:
				ws.position.z -= WORLD_LOOP_LENGTH
	# Scroll poles/wires
	for p in world_poles:
		if is_instance_valid(p):
			p.position.z += mz
			if p.position.z > 65.0:
				p.position.z -= WORLD_LOOP_LENGTH

	for t in atmosphere_trains:
		if is_instance_valid(t):
			t.position.z += mz * 1.2
			if t.position.z > 20.0:
				t.queue_free()
	atmosphere_trains = atmosphere_trains.filter(func(n): return is_instance_valid(n))

	# Camera follow with smoothing
	if is_instance_valid(game_camera) and is_instance_valid(player):
		var target_x: float = player.position.x * 0.28
		var target_y: float = 3.55 + player.velocity.y * 0.02
		var target_z: float = 6.8 + speed * 0.42
		game_camera.position.x = lerpf(game_camera.position.x, target_x, dt * 4.8)
		game_camera.position.y = lerpf(game_camera.position.y, target_y, dt * 3.5)
		game_camera.position.z = lerpf(game_camera.position.z, target_z, dt * 2.8)
		game_camera.fov = lerpf(game_camera.fov, CAMERA_DASH_FOV if dash_time > 0 else CAMERA_BASE_FOV, dt * 3.0)
		game_camera.look_at(Vector3(target_x, 1.75, -20.0), Vector3.UP)
		if shake_amount > 0.05:
			game_camera.position.x += (randf() - 0.5) * shake_amount * 0.3
			game_camera.position.y += (randf() - 0.5) * shake_amount * 0.2

	# Screen flash fade
	if _flash_timer > 0:
		_flash_timer -= dt
		if _flash_overlay:
			var a: float = _flash_timer / 0.2
			_flash_overlay.color = Color(1, 0.15, 0.15, a * 0.4)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_pause"):
		toggle_pause()
	elif event is InputEventScreenTouch:
		if event.pressed:
			var now := Time.get_ticks_msec()
			if now - _last_tap_time < 280:
				toggle_pause()
			_last_tap_time = now
			_touch_start = event.position
			_touch_id = event.index
		elif event.index == _touch_id:
			_touch_id = -1
			var swipe: Vector2 = event.position - _touch_start
			if swipe.length() > 40:
				var dx: float = swipe.x
				var dy: float = swipe.y
				if abs(dx) > abs(dy):
					if dx > 0: player.switch_lane(1)
					else: player.switch_lane(-1)
				else:
					if dy < 0:
						player.do_jump()
					else:
						player.do_slide()

func toggle_pause() -> void:
	if not running: return
	paused = not paused
	get_tree().paused = paused
	var bgm_node := find_child("BGM", false, false)
	if bgm_node is AudioStreamPlayer:
		bgm_node.stream_paused = paused
	if hud_node and hud_node.has_method(&"show_pause"):
		if paused:
			hud_node.show_pause()
		else:
			hud_node.hide_pause()

func update_hud() -> void:
	if hud_node and hud_node.has_method(&"update_score"):
		hud_node.update_score(score)
		hud_node.update_coins(coins)
		hud_node.update_speed(speed)
		hud_node.show_combo(combo)
		if hud_node.has_method(&"update_shield"):
			hud_node.update_shield(shield_time)
		if hud_node.has_method(&"update_magnet"):
			hud_node.update_magnet(magnet_time)
		if hud_node.has_method(&"update_multiplier"):
			hud_node.update_multiplier(double_score_timer)
		if hud_node.has_method(&"update_dash"):
			hud_node.update_dash(dash_time)

func make_bgm() -> AudioStreamWAV:
	if bgm_cached:
		return bgm_cached
	var bpm := 140.0
	var beats := 16
	var sr := 22050
	var beat_dur := 60.0 / bpm
	var total := beat_dur * beats
	var n := int(sr * total)
	var data := PackedByteArray()
	data.resize(n * 2)
	var bass := [82.41, 98.0, 110.0, 123.47]
	var mel := [261.63, 293.66, 329.63, 392.0, 440.0, 392.0, 329.63, 293.66,
				329.63, 392.0, 440.0, 523.25, 440.0, 392.0, 329.63, 293.66]
	for i in n:
		var t := float(i) / sr
		var beat := int(t / beat_dur) % beats
		var bt := (t - beat * beat_dur) / beat_dur
		var s := 0.0
		if beat % 2 == 0 and bt < 0.08:
			s += sin(2.0 * PI * 80.0 * (1.0 - bt * 8.0)) * 0.35
		if (beat == 4 or beat == 12) and bt < 0.06:
			s += (randf() * 2.0 - 1.0) * 0.2
		if bt < 0.04:
			s += (randf() * 2.0 - 1.0) * 0.06 * (0.5 if beat % 2 == 1 else 1.0)
		var bf: float = bass[beat % bass.size()]
		s += sin(2.0 * PI * bf * t * 0.5) * 0.06
		s += sin(2.0 * PI * bf * t) * 0.04
		if beat % 2 == 0:
			var mf: float = mel[beat % mel.size()]
			s += sin(2.0 * PI * mf * t) * 0.03 * (1.0 - bt * 0.5)
			s += sin(2.0 * PI * mf * 2.0 * t) * 0.015 * (1.0 - bt)
		var v := clampi(int(s * 10000), -32768, 32767)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	bgm_cached = wav
	return wav

func start_game() -> void:
	running = true
	paused = false
	get_tree().paused = false
	score = 0; coins = 0; combo = 1; combo_timer = 0.0
	score_bank = 0.0
	speed = 1.0; distance = 0.0; world_speed = 8.0
	obst_timer = 1.5; coin_timer = 0.5; power_timer = 5.0
	atmosphere_trains.clear(); atmos_timer = 8.0
	shield_time = 0.0; magnet_time = 0.0; dash_time = 0.0; shake_amount = 0.0; double_score_timer = 0.0; last_milestone = 0
	_hit_cooldown = 0.0
	if is_instance_valid(game_camera):
		game_camera.position = Vector3(0, 3.3, 6.2)
		game_camera.fov = CAMERA_BASE_FOV
	if is_instance_valid(player):
		player.position = Vector3(0, 1, 0)
		player.unfreeze()
		if not player.landed.is_connected(_on_player_landed):
			player.landed.connect(_on_player_landed)
		if player.has_signal(&"jumped") and not player.jumped.is_connected(_on_player_jumped):
			player.jumped.connect(_on_player_jumped)
		if player.has_signal(&"slid") and not player.slid.is_connected(_on_player_slid):
			player.slid.connect(_on_player_slid)

	for o in _obstacle_pool:
		return_obstacle(o)
	obstacles.clear()
	for c in _coin_node_pool:
		return_coin_node(c)
	coin_items.clear()

	var bgm := AudioStreamPlayer.new()
	bgm.stream = load(BGM_PATH) if ResourceLoader.exists(BGM_PATH) else make_bgm()
	bgm.name = "BGM"
	bgm.volume_db = -3.0
	add_child(bgm)
	bgm.play()

	if hud_node and hud_node.has_method(&"reset"):
		hud_node.reset()
	if hud_node and hud_node.has_method(&"hide_pause"):
		hud_node.hide_pause()

func stop_game() -> void:
	running = false

func end_run() -> void:
	var bgm_node := find_child("BGM")
	if bgm_node:
		bgm_node.queue_free()
	stop_game()
	if is_instance_valid(player) and player.has_method(&"freeze"):
		player.freeze()
	get_tree().paused = false
	shake_amount = 2.0
	flash_screen(0.5, 0.3)
	spawn_particles(player.global_position + Vector3(0, 1, 0), Color8(255, 100, 50), 16)
	var final_score: int = score
	if final_score > best:
		best = final_score
		save_best(final_score)
	if hit_sound: hit_sound.play()
	await get_tree().create_timer(0.5).timeout
	game_over.emit(final_score, coins, best)


func spawn_obstacle() -> void:
	var lane: int = randi() % 3
	var roll: float = randf()

	if roll < 0.12 and speed > 2.0:
		make_obstacle(LANE_X[lane], "roof_train")
		spawn_roof_coin_line(lane)
		return
	elif roll < 0.22 and speed > 2.0:
		# Subway-style two train blockade, one lane stays readable.
		var open_lane: int = randi() % 3
		for i in 3:
			if i != open_lane:
				make_obstacle(LANE_X[i], "train")
		return
	elif roll < 0.34 and speed > 1.5:
		# Triple lane block with one open
		var open_lane: int = randi() % 3
		for i in 3:
			if i != open_lane:
				make_obstacle(LANE_X[i], ["barrier", "gate", "crate"][randi() % 3])
		return
	elif roll < 0.44 and speed > 1.8:
		# Moving train crossing lanes
		make_obstacle(LANE_X[lane], "moving_train")
	elif roll < 0.54 and distance > 600:
		make_obstacle(LANE_X[lane], "train")
	elif roll < 0.66:
		make_obstacle(LANE_X[lane], "barrier")
	elif roll < 0.80:
		make_obstacle(LANE_X[lane], "gate")
	elif roll < 0.92:
		make_obstacle(LANE_X[lane], "cone")
	else:
		make_obstacle(LANE_X[lane], "crate")

func make_obstacle(x: float, type_: String) -> void:
	var root := get_obstacle()
	root.set_meta(&"kind", type_)
	root.position = Vector3(x, 0.0, -45.0)
	root.visible = true

	match type_:
		"barrier": _build_barrier(root)
		"gate": _build_gate(root)
		"cone": _build_cone(root)
		"train": _build_train(root)
		"roof_train": _build_roof_train(root)
		"moving_train": _build_moving_train(root)
		"crate": _build_crate(root)
		_: _build_barrier(root)

	obstacles.append(root)

func _build_barrier(root: Node3D) -> void:
	# Main body with hazard stripes
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(2.2, 2.5, 1.0)
	body.mesh.material = tex_mat(Color8(240, 130, 55), 0.12, 0.1, 0.6, 42, 0.12)
	body.position.y = 1.25
	root.add_child(body)

	# Yellow-black hazard stripes
	var stripe := MeshInstance3D.new()
	stripe.mesh = BoxMesh.new()
	stripe.mesh.size = Vector3(2.25, 0.28, 1.05)
	stripe.mesh.material = stripe_mat(Color8(255, 210, 30), Color8(30, 30, 30), 6.0, 0.0, 0.7)
	stripe.position.y = 1.55
	root.add_child(stripe)

	var stripe2 := MeshInstance3D.new()
	stripe2.mesh = BoxMesh.new()
	stripe2.mesh.size = Vector3(2.25, 0.28, 1.05)
	stripe2.mesh.material = stripe_mat(Color8(255, 210, 30), Color8(30, 30, 30), 6.0, 0.0, 0.7)
	stripe2.position.y = 0.9
	root.add_child(stripe2)

	# Red warning band
	var red_band := MeshInstance3D.new()
	red_band.mesh = BoxMesh.new()
	red_band.mesh.size = Vector3(2.25, 0.15, 1.05)
	red_band.mesh.material = cached_mat(Color8(220, 40, 40), 0.0, 0.5)
	red_band.position.y = 1.22
	root.add_child(red_band)

	# Top cap
	var top := MeshInstance3D.new()
	top.mesh = BoxMesh.new()
	top.mesh.size = Vector3(2.3, 0.12, 1.1)
	top.mesh.material = cached_mat(Color8(200, 100, 40), 0.1, 0.5)
	top.position.y = 2.55
	root.add_child(top)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(2.2, 2.5, 1.0)
	col.position.y = 1.25
	root.add_child(col)

func _build_gate(root: Node3D) -> void:
	# Gate posts with metallic look
	var post_mat = tex_mat(Color8(220, 55, 55), 0.1, 0.2, 0.45, 14, 0.1)
	for px in [-1.2, 1.2]:
		# Post base
		var base := MeshInstance3D.new()
		base.mesh = BoxMesh.new()
		base.mesh.size = Vector3(0.4, 0.15, 0.4)
		base.mesh.material = cached_mat(Color8(100, 100, 100), 0.5, 0.4)
		base.position = Vector3(px, 0.08, 0)
		root.add_child(base)

		var post := MeshInstance3D.new()
		post.mesh = CylinderMesh.new()
		post.mesh.top_radius = 0.1; post.mesh.bottom_radius = 0.13; post.mesh.height = 3.5
		post.mesh.material = post_mat
		post.position = Vector3(px, 1.8, 0)
		root.add_child(post)

		# Post top cap
		var cap := MeshInstance3D.new()
		cap.mesh = SphereMesh.new()
		cap.mesh.radius = 0.14; cap.mesh.height = 0.28
		cap.mesh.material = cached_mat(Color8(180, 40, 40), 0.3, 0.3)
		cap.position = Vector3(px, 3.6, 0)
		root.add_child(cap)

	# Cross bar with yellow-black stripes
	var bar := MeshInstance3D.new()
	bar.mesh = BoxMesh.new()
	bar.mesh.size = Vector3(2.5, 0.18, 0.18)
	bar.mesh.material = stripe_mat(Color8(255, 210, 30), Color8(30, 30, 30), 10.0, 0.2, 0.4)
	bar.position.y = 2.0
	root.add_child(bar)

	# Warning sign plate
	var sign_plate := MeshInstance3D.new()
	sign_plate.mesh = BoxMesh.new()
	sign_plate.mesh.size = Vector3(1.6, 0.55, 0.05)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color8(255, 210, 30)
	smat.emission_enabled = true
	smat.emission = Color8(255, 180, 20)
	smat.emission_energy_multiplier = 0.3
	sign_plate.mesh.material = smat
	sign_plate.position = Vector3(0, 1.1, 0.55)
	root.add_child(sign_plate)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(2.4, 2.0, 0.8)
	col.position.y = 1.5
	root.add_child(col)

func _build_cone(root: Node3D) -> void:
	# Traffic cone - orange with reflective stripes
	var cone := MeshInstance3D.new()
	cone.mesh = CylinderMesh.new()
	cone.mesh.top_radius = 0.05; cone.mesh.bottom_radius = 0.5; cone.mesh.height = 2.0
	cone.mesh.material = tex_mat(Color8(255, 140, 30), 0.15, 0.0, 0.5, 22, 0.1)
	cone.position.y = 1.0
	root.add_child(cone)

	# Reflective white bands
	for by in [0.45, 0.85, 1.25]:
		var band := MeshInstance3D.new()
		band.mesh = CylinderMesh.new()
		var br: float = 0.5 - (by - 0.1) * 0.22
		band.mesh.top_radius = br + 0.01; band.mesh.bottom_radius = br + 0.02; band.mesh.height = 0.08
		band.mesh.material = cached_mat(Color8(255, 255, 255), 0.05, 0.8)
		band.position.y = by
		root.add_child(band)

	# Base plate
	var base := MeshInstance3D.new()
	base.mesh = BoxMesh.new()
	base.mesh.size = Vector3(1.1, 0.12, 1.1)
	base.mesh.material = tex_mat(Color8(200, 90, 25), 0.1, 0.0, 0.75, 23, 0.12)
	base.position.y = 0.06
	root.add_child(base)

	var col := CollisionShape3D.new()
	col.shape = CylinderShape3D.new()
	col.shape.radius = 0.5; col.shape.height = 2.0
	col.position.y = 1.0
	root.add_child(col)

func _build_crate(root: Node3D) -> void:
	# Wooden crate obstacle
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(1.8, 1.8, 1.8)
	body.mesh.material = _load_tex("res://assets/textures/ground/wood.png", Color8(160, 110, 60), 0.8, 0.8, 0.8)
	body.position.y = 0.9
	root.add_child(body)

	# Metal corner brackets
	for cx in [-0.9, 0.9]:
		for cy in [-0.5, 0.5]:
			var bracket := MeshInstance3D.new()
			bracket.mesh = BoxMesh.new()
			bracket.mesh.size = Vector3(0.12, 0.5, 1.85)
			bracket.mesh.material = cached_mat(Color8(120, 120, 120), 0.7, 0.3)
			bracket.position = Vector3(cx, 0.9 + cy, 0)
			root.add_child(bracket)

	# Cross straps
	for sy in [-0.7, 0.7]:
		var strap := MeshInstance3D.new()
		strap.mesh = BoxMesh.new()
		strap.mesh.size = Vector3(1.85, 0.08, 1.85)
		strap.mesh.material = cached_mat(Color8(140, 140, 140), 0.6, 0.3)
		strap.position.y = 0.9 + sy
		root.add_child(strap)

	# "FRAGILE" label on front
	var label := MeshInstance3D.new()
	label.mesh = BoxMesh.new()
	label.mesh.size = Vector3(0.8, 0.4, 0.02)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color8(255, 220, 180)
	lmat.emission_enabled = true
	lmat.emission = Color8(255, 200, 150)
	lmat.emission_energy_multiplier = 0.15
	label.mesh.material = lmat
	label.position = Vector3(0, 1.0, 0.91)
	root.add_child(label)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(1.8, 1.8, 1.8)
	col.position.y = 0.9
	root.add_child(col)

func _build_train(root: Node3D) -> void:
	if ResourceLoader.exists(TRAIN_MODEL):
		var train_model = load(TRAIN_MODEL)
		if train_model:
			var train_inst: Node3D = train_model.instantiate()
			train_inst.scale = TRAIN_BLOCKER_SCALE
			root.add_child(train_inst)
			var col := CollisionShape3D.new()
			col.shape = BoxShape3D.new()
			col.shape.size = Vector3(2.9, 3.6, 12.0)
			col.position.y = 1.8
			root.add_child(col)
			return
	_build_train_fallback(root, Vector3(2.9, 3.6, 12.0), 1.8)

func _build_roof_train(root: Node3D) -> void:
	root.set_meta(&"kind", "roof_train")
	if ResourceLoader.exists(TRAIN_MODEL):
		var train_model = load(TRAIN_MODEL)
		if train_model:
			var train_inst: Node3D = train_model.instantiate()
			train_inst.scale = TRAIN_ROOF_SCALE
			root.add_child(train_inst)
			var col := CollisionShape3D.new()
			col.shape = BoxShape3D.new()
			col.shape.size = Vector3(2.8, 2.9, 13.0)
			col.position.y = 1.45
			root.add_child(col)
			_add_roof_route_marker(root, 3.05)
			return
	_build_train_fallback(root, Vector3(2.8, 2.9, 13.0), 1.45)
	_add_roof_route_marker(root, 3.05)

func _build_moving_train(root: Node3D) -> void:
	root.set_meta(&"moving", true)
	root.set_meta(&"move_dir", 1.0 if randf() > 0.5 else -1.0)
	if ResourceLoader.exists(TRAIN_MODEL):
		var train_model = load(TRAIN_MODEL)
		if train_model:
			var train_inst: Node3D = train_model.instantiate()
			train_inst.scale = TRAIN_MOVING_SCALE
			root.add_child(train_inst)
			var col := CollisionShape3D.new()
			col.shape = BoxShape3D.new()
			col.shape.size = Vector3(2.7, 3.25, 9.5)
			col.position.y = 1.62
			root.add_child(col)
			return
	_build_train_fallback(root, Vector3(2.7, 3.25, 9.5), 1.62)

func _add_roof_route_marker(root: Node3D, y: float) -> void:
	var strip := MeshInstance3D.new()
	strip.mesh = BoxMesh.new()
	strip.mesh.size = Vector3(1.8, 0.035, 9.5)
	strip.mesh.material = pbr_mat(Color8(57, 240, 220), 0.0, 0.18, Color8(57, 240, 220), 1.1)
	strip.position.y = y
	root.add_child(strip)

	var arrow := MeshInstance3D.new()
	arrow.mesh = BoxMesh.new()
	arrow.mesh.size = Vector3(1.1, 0.08, 1.2)
	arrow.mesh.material = pbr_mat(Color8(255, 215, 70), 0.0, 0.22, Color8(255, 215, 70), 1.0)
	arrow.position = Vector3(0, y + 0.06, 3.8)
	arrow.rotation.y = PI
	root.add_child(arrow)

func _build_train_fallback(root: Node3D, col_size: Vector3, col_y: float) -> void:
	var car := MeshInstance3D.new()
	car.mesh = BoxMesh.new()
	car.mesh.size = Vector3(col_size.x, col_size.y * 0.85, col_size.z)
	car.mesh.material = pbr_mat(Color8(70, 170, 190), 0.25, 0.35, Color8(57, 200, 190), 0.25)
	car.position.y = col_y
	root.add_child(car)

	var window := MeshInstance3D.new()
	window.mesh = BoxMesh.new()
	window.mesh.size = Vector3(col_size.x * 0.75, 0.8, 0.08)
	window.mesh.material = pbr_mat(Color8(225, 255, 255), 0.0, 0.12, Color8(180, 255, 255), 0.8)
	window.position = Vector3(0, col_y + 0.45, col_size.z * 0.5 + 0.045)
	root.add_child(window)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = col_size
	col.position.y = col_y
	root.add_child(col)

func spawn_coins() -> void:
	var lane: int = randi() % 3
	var count: int = 8
	var pattern: int = randi() % 4
	var target_lane: int = clampi(lane + (-1 if randf() < 0.5 else 1), 0, 2)
	for i in count:
		var t: float = float(i) / float(count - 1)
		var x: float = LANE_X[lane]
		var y: float = 1.3
		match pattern:
			0:
				pass
			1:
				x += sin(t * PI) * 2.0 * (1.0 if randf() > 0.5 else -1.0)
				y = 1.25 + sin(t * PI) * 0.9
			2:
				x = lerpf(LANE_X[lane], LANE_X[target_lane], t)
				y = 1.25 + sin(t * PI) * 0.35
			3:
				y = 1.2 + sin(t * PI) * 1.5

		spawn_coin_at(Vector3(x, y, -40.0 - i * 1.35))

	# Spawn gem (rare)
	if randf() > 0.92:
		var gem := get_coin_node()
		gem.position = Vector3(LANE_X[randi() % 3], 1.5, -42.0)
		gem.visible = true
		gem.set_meta("coin", true)
		gem.set_meta("gem", true)
		var gm := MeshInstance3D.new()
		gm.mesh = SphereMesh.new()
		gm.mesh.radius = 0.35; gm.mesh.height = 0.7
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color8(255, 100, 255)
		gmat.metallic = 0.6; gmat.roughness = 0.1
		gmat.emission_enabled = true; gmat.emission = Color8(200, 80, 255); gmat.emission_energy_multiplier = 1.5
		gm.mesh.material = gmat
		gem.add_child(gm)
		var area := Area3D.new()
		var col := CollisionShape3D.new()
		col.shape = SphereShape3D.new()
		col.shape.radius = 0.8
		area.add_child(col)
		var gem_ref := gem
		area.body_entered.connect(func(_body: Node): _on_gem(gem_ref))
		gem.add_child(area)
		coin_items.append(gem)

func spawn_roof_coin_line(lane: int) -> void:
	for i in 9:
		var y := 3.55 + sin(float(i) / 8.0 * PI) * 0.35
		spawn_coin_at(Vector3(LANE_X[lane], y, -42.0 - i * 1.15))

func spawn_coin_at(pos: Vector3) -> Node3D:
	var coin := get_coin_node()
	coin.position = pos
	coin.visible = true
	coin.set_meta(&"coin", true)

	var mi := _coin_mesh.duplicate()
	coin.add_child(mi)
	var star := _coin_star.duplicate()
	coin.add_child(star)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.72
	area.add_child(col)
	var coin_ref := coin
	area.body_entered.connect(func(_body: Node): _on_coin(coin_ref))
	coin.add_child(area)

	coin_items.append(coin)
	return coin

func spawn_powerup() -> void:
	var lane: int = randi() % 3
	var kinds := ["shield", "magnet", "dash"]
	var kind: String = kinds[randi() % kinds.size()]
	var pw := get_coin_node()
	pw.set_meta(&"coin", true)
	pw.set_meta(&"powerup", kind)
	pw.position = Vector3(LANE_X[lane], 1.5, -42.0)
	pw.visible = true

	var mesh: Node = _powerup_meshes.get(kind, make_powerup_fallback(kind)).duplicate()
	pw.add_child(mesh)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.8
	area.add_child(col)
	var pw_ref := pw
	area.body_entered.connect(func(_body: Node): _on_powerup(pw_ref))
	pw.add_child(area)

	coin_items.append(pw)

func spawn_double_score() -> void:
	var lane: int = randi() % 3
	var pw := get_coin_node()
	pw.set_meta("coin", true)
	pw.set_meta("powerup", "double")
	pw.position = Vector3(LANE_X[lane], 1.5, -42.0)
	pw.visible = true
	var gm: Node = _powerup_meshes.get("double", make_powerup_fallback("double")).duplicate()
	pw.add_child(gm)
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.8
	area.add_child(col)
	var pw_ref := pw
	area.body_entered.connect(func(_body: Node): _on_powerup(pw_ref))
	pw.add_child(area)
	coin_items.append(pw)

func _on_gem(gem: Node3D) -> void:
	if not is_instance_valid(gem) or not gem.visible: return
	score += 500
	spawn_particles(gem.global_position, Color8(255, 100, 255), 16)
	if coin_sound: coin_sound.play()
	coin_items.erase(gem)
	return_coin_node(gem)


func spawn_atmosphere_train() -> void:
	var side: float = -5.5 if randf() > 0.5 else 5.5
	var train := Node3D.new()
	train.position = Vector3(side, 0, -55.0)
	if ResourceLoader.exists(TRAIN_MODEL):
		var train_model = load(TRAIN_MODEL)
		if train_model:
			var train_inst: Node3D = train_model.instantiate()
			train_inst.scale = TRAIN_AMBIENT_SCALE
			train.add_child(train_inst)
			add_child(train)
			atmosphere_trains.append(train)
			return

func _on_coin(coin: Node3D) -> void:
	if not is_instance_valid(coin) or not coin.visible: return
	coins += 1
	combo = mini(99, combo + 1)
	combo_timer = 2.5
	score += 25 * combo
	if coin_sound: coin_sound.play()
	spawn_particles(coin.global_position, Color8(57, 200, 190), 6)
	coin_items.erase(coin)
	return_coin_node(coin)

func _on_powerup(pw: Node3D) -> void:
	if not is_instance_valid(pw) or not pw.visible: return
	var kind: String = pw.get_meta(&"powerup", "shield")
	if kind == "double":
		double_score_timer = 10.0
		score += 200
		spawn_particles(pw.global_position, Color8(255, 215, 70), 12)
	elif kind == "shield":
		shield_time = 8.0
		score += 150
		spawn_particles(pw.global_position, Color8(57, 200, 190), 12)
	elif kind == "dash":
		dash_time = 4.0
		score += 180
		shake_amount = 0.55
		spawn_particles(pw.global_position, Color8(120, 180, 255), 16)
	else:
		magnet_time = 6.0
		score += 150
		spawn_particles(pw.global_position, Color8(255, 100, 150), 12)
	if coin_sound: coin_sound.play()
	coin_items.erase(pw)
	return_coin_node(pw)
func _on_player_landed() -> void:
	spawn_particles(player.global_position + Vector3(0, 0.05, 0), Color8(180, 190, 160), 5)

func _on_player_jumped() -> void:
	if jump_sound:
		jump_sound.stream = load("res://assets/audio/sfx/jump.mp3") if ResourceLoader.exists("res://assets/audio/sfx/jump.mp3") else make_sweep(380.0, 760.0, 0.12)
		jump_sound.play()
	if is_instance_valid(player):
		spawn_particles(player.global_position + Vector3(0, 0.2, 0), Color8(57, 200, 190), 5)

func _on_player_slid() -> void:
	if is_instance_valid(player):
		spawn_particles(player.global_position + Vector3(0, 0.15, 0), Color8(120, 180, 255), 4)

func on_player_hit(_kind: String) -> void:
	if _hit_cooldown > 0:
		return
	_hit_cooldown = 0.5
	if dash_time > 0 and _kind != "train" and _kind != "moving_train":
		shake_amount = 0.9
		score += 150
		spawn_particles(player.global_position + Vector3(0, 1, 0), Color8(120, 180, 255), 16)
		return
	if shield_time > 0:
		shield_time = maxf(0, shield_time - 4.0)
		shake_amount = 0.8
		flash_screen(0.3, 0.15)
		score += 100
		spawn_particles(player.global_position + Vector3(0, 1, 0), Color8(57, 200, 190), 12)
		return
	flash_screen(0.5, 0.3)
	end_run()

func cleanup_passed(list: Array) -> void:
	var i: int = 0
	while i < len(list):
		var node = list[i]
		if not is_instance_valid(node) or node.position.z > 10.0:
			if is_instance_valid(node):
				if node.get_meta(&"obstacle", false):
					return_obstacle(node)
				elif node.get_meta(&"coin", false):
					return_coin_node(node)
				else:
					node.queue_free()
			list.remove_at(i)
		else:
			i += 1

static func load_best() -> int:
	var file := FileAccess.open("user://save.dat", FileAccess.READ)
	if file:
		var val := file.get_32()
		file.close()
		return val
	return 0

static func save_best(val: int) -> void:
	var file := FileAccess.open("user://save.dat", FileAccess.WRITE)
	if file:
		file.store_32(val)
		file.close()
