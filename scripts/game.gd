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

# KayKit building model paths (already downloaded)
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
var building_nodes_left: Array[Node] = []
var building_nodes_right: Array[Node] = []
var atmos_timer: float = 10.0
var atmosphere_trains: Array[Node] = []
var world_poles: Array[Node] = []
var double_score_timer: float = 0.0
var last_milestone: int = 0
var bgm_cached: AudioStreamWAV = null

var _obstacle_pool: Array[StaticBody3D] = []
var _coin_node_pool: Array[Node3D] = []
var _coin_mesh: MeshInstance3D = null
var _coin_star: MeshInstance3D = null
var _powerup_meshes: Dictionary = {}

static var _mat_cache: Dictionary = {}

var _touch_start: Vector2 = Vector2.ZERO
var _touch_id: int = -1

var _flash_overlay: ColorRect = null
var _flash_timer: float = 0.0
var _clouds: Array[TextureRect] = []

const BGM_PATH := "res://bgm.mp3"


func _ready() -> void:
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
	var cmat := cached_mat(Color8(57, 200, 190), 0.7, 0.15)
	cmat.emission_enabled = true; cmat.emission = Color8(57, 200, 190); cmat.emission_energy_multiplier = 0.6
	cmesh.material = cmat
	_coin_mesh.mesh = cmesh
	_coin_mesh.rotation.x = PI / 2.0

	_coin_star = MeshInstance3D.new()
	var smesh := CylinderMesh.new()
	smesh.top_radius = 0.2; smesh.bottom_radius = 0.2; smesh.height = 0.09
	var smat := cached_mat(Color8(40, 170, 160), 0.8, 0.1)
	smesh.material = smat
	_coin_star.mesh = smesh
	_coin_star.rotation.x = PI / 2.0

	# Powerup meshes
	for key in ["shield", "magnet"]:
		var pw_mesh := MeshInstance3D.new()
		pw_mesh.mesh = SphereMesh.new()
		pw_mesh.mesh.radius = 0.5; pw_mesh.mesh.height = 1.0
		var pmat := cached_mat(Color8(57, 200, 190) if key == "shield" else Color8(255, 100, 150), 0.5, 0.2)
		pmat.emission_enabled = true
		pmat.emission = Color8(57, 200, 190) if key == "shield" else Color8(255, 100, 150)
		pmat.emission_energy_multiplier = 1.0
		pw_mesh.mesh.material = pmat
		_powerup_meshes[key] = pw_mesh

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
	# Avoid physics callback conflict - defer all child manipulation
	for c in obj.get_children():
		c.call_deferred("queue_free")

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
	# Defer to avoid physics callback conflict
	for child in c.get_children():
		child.call_deferred("queue_free")

func setup_environment() -> void:
	var we := WorldEnvironment.new()
	var sm := PanoramaSkyMaterial.new()
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.2
	env.fog_enabled = true
	env.fog_light_color = Color8(160, 210, 240)
	env.fog_density = 0.0015
	we.environment = env
	add_child(we)
	move_child(we, 0)

	build_world()

	if is_instance_valid(game_camera):
		game_camera.look_at(Vector3(0.0, 1.8, -10.0), Vector3.UP)

func build_world() -> void:
	var ground_body := StaticBody3D.new()
	var ground_col := CollisionShape3D.new()
	ground_col.shape = BoxShape3D.new()
	ground_col.shape.size = Vector3(40, 0.4, 120)
	ground_body.position = Vector3(0, -0.2, 0)
	ground_body.add_child(ground_col)
	add_child(ground_body)

	# Grass ground with texture
	var gnd := MeshInstance3D.new()
	gnd.mesh = BoxMesh.new()
	gnd.mesh.size = Vector3(40, 0.15, 120)
	gnd.mesh.material = _load_tex("res://assets/textures/kenney/green_01.png", Color8(70, 180, 70), 8, 24, 0.95)
	gnd.position = Vector3(0, -0.08, 0)
	add_child(gnd)

	# Track bed (gravel) with texture
	var bed_mat = _load_tex("res://assets/textures/kenney/green_03.png", Color8(150, 105, 65), 2, 24, 0.9)
	var bed := MeshInstance3D.new()
	bed.mesh = BoxMesh.new()
	bed.mesh.size = Vector3(10.0, 0.25, 120)
	bed.mesh.material = bed_mat
	bed.position = Vector3(0, 0.0, 0)
	add_child(bed)

	# Wooden sleepers with texture
	for i in 60:
		var sleeper := MeshInstance3D.new()
		sleeper.mesh = BoxMesh.new()
		sleeper.mesh.size = Vector3(9.5, 0.18, 0.35)
		sleeper.mesh.material = _load_tex("res://assets/textures/ground/wood.png", Color8(140, 90, 55), 0.5, 0.1, 0.95)
		sleeper.position = Vector3(0, 0.09, -i * 2.0 + 10)
		add_child(sleeper)

	for lane_i in 3:
		var lx: float = LANE_X[lane_i]
		for offset in [-0.6, 0.6]:
			var rail := MeshInstance3D.new()
			rail.mesh = BoxMesh.new()
			rail.mesh.size = Vector3(0.08, 0.12, 120)
			rail.mesh.material = cached_mat(Color8(170, 180, 190), 0.7, 0.25)
			rail.position = Vector3(lx + offset, 0.2, 0)
			add_child(rail)

	for div_x in [-1.5, 1.5]:
		var divider := MeshInstance3D.new()
		divider.mesh = BoxMesh.new()
		divider.mesh.size = Vector3(0.04, 0.01, 120)
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(1, 1, 1, 0.15)
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		divider.mesh.material = dmat
		divider.position = Vector3(div_x, 0.26, 0)
		add_child(divider)

	# Track edge curbs with concrete texture
	var curb_mat = _load_tex("res://assets/textures/kenney/green_08.png", Color8(180, 145, 110), 0.5, 0.1, 0.85)
	for side in [-1, 1]:
		var curb := MeshInstance3D.new()
		curb.mesh = BoxMesh.new()
		curb.mesh.size = Vector3(0.3, 0.35, 120)
		curb.mesh.material = curb_mat
		curb.position = Vector3(side * 5.0, 0.1, 0)
		add_child(curb)

	for wx in [-2.0, 0.0, 2.0]:
		var wire := MeshInstance3D.new()
		wire.mesh = CylinderMesh.new()
		wire.mesh.top_radius = 0.02; wire.mesh.bottom_radius = 0.02; wire.mesh.height = 120
		wire.mesh.material = cached_mat(Color8(60, 60, 60), 0.3, 0.5)
		wire.rotation.x = PI / 2.0
		wire.position = Vector3(wx, 6.0, 0)
		add_child(wire)
		world_poles.append(wire)

	for pz in range(0, -130, -12):
		for side in [-1, 1]:
			var pole := MeshInstance3D.new()
			pole.mesh = CylinderMesh.new()
			pole.mesh.top_radius = 0.06; pole.mesh.bottom_radius = 0.08; pole.mesh.height = 6.5
			pole.mesh.material = tex_mat(Color8(90, 90, 90), 0.15, 0.4, 0.45, pz, 0.12)
			pole.position = Vector3(side * 5.2, 3.25, pz)
			add_child(pole)
			world_poles.append(pole)
			var arm := MeshInstance3D.new()
			arm.mesh = BoxMesh.new()
			arm.mesh.size = Vector3(4.0, 0.1, 0.1)
			arm.mesh.material = cached_mat(Color8(80, 80, 80), 0.3, 0.5)
			arm.position = Vector3(side * 3.0, 6.3, pz)
			add_child(arm)

	build_buildings()

func build_buildings() -> void:
	# Try loading KayKit models (works in GUI editor)
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
		for i in 14:
			var bw: float = 2.5 + randf() * 3.5
			var bh: float = 4.0 + randf() * 10.0
			var bd: float = 2.5 + randf() * 3.0
			var bz: float = -i * 9.0 - 6.0 + randf() * 3.0
			var bx: float = side * (6.5 + bw / 2.0 + randf() * 1.5)

			# Use KayKit 3D model if available
			if not _kaykit_cache.is_empty():
				var bldg: Node3D = _kaykit_cache[randi() % _kaykit_cache.size()].instantiate()
				bldg.position = Vector3(bx, 0, bz)
				var s: float = randf_range(2.0, 4.0)
				bldg.scale = Vector3(s, s * randf_range(1.0, 2.0), s)
				add_child(bldg)
				list.append(bldg)
				# Add street decoration every 3 buildings
				if i % 3 == 0 and not _decor_cache.is_empty():
					var dec: Node3D = _decor_cache[randi() % _decor_cache.size()].instantiate()
					dec.position = Vector3(side * (6.0 + randf() * 4.0), 0, bz + 4.0)
					dec.scale = Vector3.ONE * randf_range(1.5, 3.0)
					add_child(dec)
					list.append(dec)
				continue

			var bldg_root := Node3D.new()
			bldg_root.position = Vector3(bx, 0, bz)

			# Main body with Miku-themed color
			var body := MeshInstance3D.new()
			body.mesh = BoxMesh.new()
			body.mesh.size = Vector3(bw, bh, bd if bd else bw)
			var bcol: Color = BUILD_COLORS[i % BUILD_COLORS.size()]
			var body_mat := StandardMaterial3D.new()
			body_mat.albedo_color = bcol
			body_mat.metallic = 0.05; body_mat.roughness = 0.8
			# Try to load building texture if available
			var tex_idx = (i % 5) + 1
			if ResourceLoader.exists("res://assets/textures/kenney/green_08.png"):
				body_mat.albedo_texture = load("res://assets/textures/kenney/green_08.png")
				body_mat.uv1_scale = Vector3(bw / 2, bh / 2, 1)
			body.mesh.material = body_mat
			body.position.y = bh / 2.0
			bldg_root.add_child(body)

			# Roof detail
			var roof := MeshInstance3D.new()
			roof.mesh = BoxMesh.new()
			roof.mesh.size = Vector3(bw + 0.3, 0.3, bd if bd else bw + 0.3)
			var roof_mat := StandardMaterial3D.new()
			roof_mat.albedo_color = bcol.darkened(0.3)
			roof_mat.roughness = 0.7
			roof.mesh.material = roof_mat
			roof.position.y = bh + 0.15
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
						wmat.emission = Color8(255, 230, 150)
						wmat.emission_energy_multiplier = 0.4
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

func setup_sounds() -> void:
	if coin_sound:
		coin_sound.stream = load("res://assets/audio/sfx/coin01.mp3")
	if jump_sound:
		jump_sound.stream = load("res://assets/audio/sfx/blip01.mp3")
	if hit_sound:
		hit_sound.stream = load("res://assets/audio/sfx/hit.mp3")

func setup_clouds() -> void:
	var cloud_layer := CanvasLayer.new()
	cloud_layer.layer = 1
	add_child(cloud_layer)
	for i in 6:
		var cloud := TextureRect.new()
		var tex_path := "res://assets/particles/cloud_" + str(i) + ".png"
		cloud.texture = load(tex_path)
		cloud.self_modulate = Color(1, 1, 1, 0.7)
		cloud.position = Vector2(randf() * 1200, randf() * 200 + 20)
		cloud.size = Vector2(250, 80)
		cloud.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud_layer.add_child(cloud)
		_clouds.append(cloud)
		_clouds.append(cloud_layer)


func setup_effects() -> void:
	# Screen flash overlay
	_flash_overlay = ColorRect.new()
	_flash_overlay.color = Color(1, 0, 0, 0)
	_flash_overlay.size = Vector2(1200, 800)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_overlay.show_behind_parent = true
	hud_node.add_child(_flash_overlay)

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

static func cached_mat(color: Color, met: float = 0.0, rough: float = 0.8) -> StandardMaterial3D:
	var key := str(color) + "_" + str(met) + "_" + str(rough)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = met
	m.roughness = rough
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
	distance += dt * world_speed
	speed = minf(3.25, 1.0 + distance / 10000.0)
	world_speed = 8.0 + speed * 5.0
	score += int(dt * 22.0 * speed * combo * (2.0 if double_score_timer > 0 else 1.0))
	combo_timer -= dt
	if combo_timer <= 0:
		combo = 1
	shield_time = maxf(0, shield_time - dt)
	double_score_timer = maxf(0, double_score_timer - dt)
	shake_amount = maxf(0, shake_amount - dt * 10.0)
	update_hud()

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
		# Also spawn double-score sometimes
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
		if jump_sound: jump_sound.play()
	if Input.is_action_just_pressed(&"ui_down"):
		player.do_slide()

	var mz: float = world_speed * dt
	for o in obstacles:
		if is_instance_valid(o):
			o.position.z += mz
	for c in coin_items:
		if is_instance_valid(c):
			c.position.z += mz
			for child in c.get_children():
				if child is MeshInstance3D and child != c:
					child.rotation.y += dt * 5.0

	cleanup_passed(obstacles)
	cleanup_passed(coin_items)

	for b in building_nodes_left:
		if is_instance_valid(b):
			b.position.z += mz
			if b.position.z > 15.0:
				b.position.z -= 130.0

	# Scroll poles/wires with world
	for p in world_poles:
		if is_instance_valid(p):
			p.position.z += mz
			if p.position.z > 20.0:
				p.position.z -= 140.0

				p.position.z -= 140.0

	# Scroll buildings
	for b in building_nodes_right:
		if is_instance_valid(b):
			b.position.z += mz
			if b.position.z > 15.0:
				b.position.z -= 130.0

	for t in atmosphere_trains:
		if is_instance_valid(t):
			t.position.z += mz * 1.2
			if t.position.z > 20.0:
				t.queue_free()
	atmosphere_trains = atmosphere_trains.filter(func(n): return is_instance_valid(n))

	if is_instance_valid(game_camera) and is_instance_valid(player):
		var target_x: float = player.position.x * 0.25
		var target_y: float = 2.5 + player.velocity.y * 0.015
		game_camera.position.x = lerpf(game_camera.position.x, target_x, dt * 4.0)
		game_camera.position.y = lerpf(game_camera.position.y, target_y, dt * 3.0)
		# Per-frame look_at so camera always faces forward
		game_camera.look_at(Vector3(target_x, 1.5, -15.0), Vector3.UP)
		if shake_amount > 0.05:
			game_camera.position.x += (randf() - 0.5) * shake_amount * 0.3
			game_camera.position.y += (randf() - 0.5) * shake_amount * 0.2

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
						if jump_sound: jump_sound.play()
					else:
						player.do_slide()

func toggle_pause() -> void:
	if not running: return
	paused = not paused
	get_tree().paused = paused
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
		if hud_node.has_method(&"update_multiplier"):
			hud_node.update_multiplier(double_score_timer)

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
	speed = 1.0; distance = 0.0; world_speed = 8.0
	obst_timer = 1.5; coin_timer = 0.5; power_timer = 5.0
	atmosphere_trains.clear(); atmos_timer = 8.0
	shield_time = 0.0; shake_amount = 0.0; double_score_timer = 0.0; last_milestone = 0
	# Reset camera position (look_at is handled per-frame in _process)
	if is_instance_valid(game_camera):
		game_camera.position = Vector3(0, 2.5, 5.0)
	if is_instance_valid(player):
		player.position = Vector3(0, 1, 0)
		player.unfreeze()
		if not player.landed.is_connected(_on_player_landed):
			player.landed.connect(_on_player_landed)

	for o in _obstacle_pool:
		return_obstacle(o)
	obstacles.clear()
	for c in _coin_node_pool:
		return_coin_node(c)
	coin_items.clear()

	var bgm := AudioStreamPlayer.new()
	bgm.stream = load(BGM_PATH)
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

	if roll < 0.18 and speed > 1.5:
		var open_lane: int = randi() % 3
		for i in 3:
			if i != open_lane:
				make_obstacle(LANE_X[i], ["barrier", "gate"][randi() % 2])
		return
	elif roll < 0.32 and distance > 600:
		make_obstacle(LANE_X[lane], "train")
	elif roll < 0.55:
		make_obstacle(LANE_X[lane], "barrier")
	elif roll < 0.75:
		make_obstacle(LANE_X[lane], "gate")
	else:
		make_obstacle(LANE_X[lane], "cone")

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
		_: _build_barrier(root)

	obstacles.append(root)

func _build_barrier(root: Node3D) -> void:
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(2.0, 2.5, 1.2)
	body.mesh.material = tex_mat(Color8(240, 130, 55), 0.12, 0.1, 0.65, 42, 0.12)
	body.position.y = 1.25
	root.add_child(body)
	var stripe := MeshInstance3D.new()
	stripe.mesh = BoxMesh.new()
	stripe.mesh.size = Vector3(2.05, 0.3, 1.25)
	stripe.mesh.material = tex_mat(Color8(255, 255, 255), 0.15, 0.0, 0.9, 7, 0.08)
	stripe.position.y = 1.5
	root.add_child(stripe)
	var stripe2 := MeshInstance3D.new()
	stripe2.mesh = BoxMesh.new()
	stripe2.mesh.size = Vector3(2.05, 0.3, 1.25)
	stripe2.mesh.material = cached_mat(Color8(220, 50, 50), 0.0, 0.7)
	stripe2.position.y = 0.9
	root.add_child(stripe2)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(2.0, 2.5, 1.2)
	col.position.y = 1.25
	root.add_child(col)

func _build_gate(root: Node3D) -> void:
	var post_mat = tex_mat(Color8(230, 60, 60), 0.1, 0.15, 0.5, 14, 0.1)
	for px in [-1.2, 1.2]:
		var post := MeshInstance3D.new()
		post.mesh = CylinderMesh.new()
		post.mesh.top_radius = 0.12; post.mesh.bottom_radius = 0.14; post.mesh.height = 3.5
		post.mesh.material = post_mat
		post.position = Vector3(px, 1.75, 0)
		root.add_child(post)
	var bar := MeshInstance3D.new()
	bar.mesh = BoxMesh.new()
	bar.mesh.size = Vector3(2.6, 0.2, 0.2)
	bar.mesh.material = stripe_mat(Color8(255, 210, 60), Color8(230, 60, 60), 8.0, 0.2, 0.4)
	bar.position.y = 1.8; root.add_child(bar)
	var ws := MeshInstance3D.new()
	ws.mesh = BoxMesh.new()
	ws.mesh.size = Vector3(2.65, 0.08, 0.22)
	ws.mesh.material = cached_mat(Color8(230, 60, 60), 0.0, 0.5)
	ws.position.y = 1.65; root.add_child(ws)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(2.4, 2.0, 0.8)
	col.position.y = 1.5; root.add_child(col)

func _build_cone(root: Node3D) -> void:
	var cone := MeshInstance3D.new()
	cone.mesh = CylinderMesh.new()
	cone.mesh.top_radius = 0.05; cone.mesh.bottom_radius = 0.5; cone.mesh.height = 2.0
	cone.mesh.material = tex_mat(Color8(255, 140, 40), 0.15, 0.0, 0.6, 22, 0.1)
	cone.position.y = 1.0; root.add_child(cone)
	var ws := MeshInstance3D.new()
	ws.mesh = CylinderMesh.new()
	ws.mesh.top_radius = 0.2; ws.mesh.bottom_radius = 0.35; ws.mesh.height = 0.3
	ws.mesh.material = cached_mat(Color8(255, 255, 255), 0.0, 0.9)
	ws.position.y = 1.0; root.add_child(ws)
	var base := MeshInstance3D.new()
	base.mesh = BoxMesh.new()
	base.mesh.size = Vector3(1.0, 0.15, 1.0)
	base.mesh.material = tex_mat(Color8(200, 100, 30), 0.1, 0.0, 0.8, 23, 0.12)
	base.position.y = 0.08; root.add_child(base)
	var col := CollisionShape3D.new()
	col.shape = CylinderShape3D.new()
	col.shape.radius = 0.5; col.shape.height = 2.0
	col.position.y = 1.0; root.add_child(col)

func _build_train(root: Node3D) -> void:
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(2.6, 3.2, 5.0)
	body.mesh.material = tex_mat(Color8(200, 215, 210), 0.08, 0.3, 0.4, 50, 0.1)
	body.position.y = 1.8; root.add_child(body)
	var roof := MeshInstance3D.new()
	roof.mesh = BoxMesh.new()
	roof.mesh.size = Vector3(2.7, 0.3, 5.1)
	roof.mesh.material = tex_mat(Color8(40, 55, 55), 0.1, 0.2, 0.5, 51, 0.1)
	roof.position.y = 3.5; root.add_child(roof)
	var accent := MeshInstance3D.new()
	accent.mesh = BoxMesh.new()
	accent.mesh.size = Vector3(2.65, 0.1, 5.05)
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color8(100, 160, 255)
	amat.emission_enabled = true; amat.emission = Color8(100, 160, 255); amat.emission_energy_multiplier = 0.4
	accent.mesh.material = amat
	accent.position.y = 3.35; root.add_child(accent)
	var wind := MeshInstance3D.new()
	wind.mesh = BoxMesh.new()
	wind.mesh.size = Vector3(1.8, 0.8, 0.05)
	wind.mesh.material = cached_mat(Color8(20, 35, 45), 0.5, 0.2)
	wind.position = Vector3(0, 2.6, 2.53); root.add_child(wind)
	for hx in [-0.9, 0.9]:
		var hl := MeshInstance3D.new()
		hl.mesh = SphereMesh.new()
		hl.mesh.radius = 0.2; hl.mesh.height = 0.4
		var hlmat := StandardMaterial3D.new()
		hlmat.albedo_color = Color8(255, 240, 180)
		hlmat.emission_enabled = true; hlmat.emission = Color8(255, 235, 60); hlmat.emission_energy_multiplier = 1.5
		hl.mesh.material = hlmat
		hl.position = Vector3(hx, 2.0, 2.55); root.add_child(hl)
	var rs := MeshInstance3D.new()
	rs.mesh = BoxMesh.new()
	rs.mesh.size = Vector3(2.65, 0.15, 5.05)
	rs.mesh.material = cached_mat(Color8(230, 70, 70), 0.1, 0.5)
	rs.position.y = 1.5; root.add_child(rs)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(2.6, 3.2, 5.0)
	col.position.y = 1.8; root.add_child(col)

func spawn_coins() -> void:
	var lane: int = randi() % 3
	var count: int = 7
	var arc: bool = randf() > 0.45
	for i in count:
		var x: float = LANE_X[lane]
		if arc:
			var t: float = float(i) / float(count - 1)
			x += sin(t * PI) * 2.0 * (1.0 if randf() > 0.5 else -1.0)

		var coin := get_coin_node()
		coin.position = Vector3(x, 1.3, -40.0 - i * 1.3)
		coin.visible = true

		var mi := _coin_mesh.duplicate()
		coin.add_child(mi)
		var star := _coin_star.duplicate()
		coin.add_child(star)

		var area := Area3D.new()
		var col := CollisionShape3D.new()
		col.shape = SphereShape3D.new()
		col.shape.radius = 0.7
		area.add_child(col)
		var coin_ref := coin
		area.body_entered.connect(func(_body: Node): _on_coin(coin_ref))
		coin.add_child(area)

		coin_items.append(coin)

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

func spawn_powerup() -> void:
	var lane: int = randi() % 3
	var is_shield: bool = randf() > 0.5
	var pw := get_coin_node()
	pw.set_meta(&"coin", true)
	pw.set_meta(&"powerup", "shield" if is_shield else "magnet")
	pw.position = Vector3(LANE_X[lane], 1.5, -42.0)
	pw.visible = true

	var mesh: Node = _powerup_meshes["shield" if is_shield else "magnet"].duplicate()
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
	var gm := MeshInstance3D.new()
	gm.mesh = SphereMesh.new()
	gm.mesh.radius = 0.4; gm.mesh.height = 0.8
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color8(255, 215, 70)
	gmat.metallic = 0.6; gmat.roughness = 0.1
	gmat.emission_enabled = true; gmat.emission = Color8(255, 200, 50); gmat.emission_energy_multiplier = 1.5
	gm.mesh.material = gmat
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
	var side: float = -5.0 if randf() > 0.5 else 5.0
	var train := Node3D.new()
	train.position = Vector3(side, 0, -55.0)

	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(2.6, 3.0, 8.0)
	body.mesh.material = tex_mat(Color8(60, 130, 190), 0.08, 0.3, 0.4, 60, 0.1)
	body.position.y = 1.8; train.add_child(body)
	var roof := MeshInstance3D.new()
	roof.mesh = BoxMesh.new()
	roof.mesh.size = Vector3(2.7, 0.2, 8.1)
	roof.mesh.material = tex_mat(Color8(40, 55, 55), 0.1, 0.2, 0.5, 61, 0.1)
	roof.position.y = 3.3; train.add_child(roof)
	for i in 5:
		var win := MeshInstance3D.new()
		win.mesh = BoxMesh.new()
		win.mesh.size = Vector3(0.6, 0.7, 0.05)
		win.mesh.material = cached_mat(Color8(180, 220, 255), 0.1, 0.3)
		win.position = Vector3(0, 2.2, -3.0 + i * 1.5)
		train.add_child(win)
	var hl := MeshInstance3D.new()
	hl.mesh = SphereMesh.new()
	hl.mesh.radius = 0.18; hl.mesh.height = 0.36
	var hlmat := StandardMaterial3D.new()
	hlmat.albedo_color = Color8(255, 240, 180)
	hlmat.emission_enabled = true; hlmat.emission = Color8(255, 235, 60); hlmat.emission_energy_multiplier = 2.0
	hl.mesh.material = hlmat
	hl.position = Vector3(0, 1.8, 4.05); train.add_child(hl)
	var tl := MeshInstance3D.new()
	tl.mesh = SphereMesh.new()
	tl.mesh.radius = 0.12; tl.mesh.height = 0.24
	var tlmat := StandardMaterial3D.new()
	tlmat.albedo_color = Color8(255, 60, 60)
	tlmat.emission_enabled = true; tlmat.emission = Color8(255, 60, 60); tlmat.emission_energy_multiplier = 1.0
	tl.mesh.material = tlmat
	tl.position = Vector3(0, 1.8, -4.05); train.add_child(tl)

	add_child(train)
	atmosphere_trains.append(train)

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
	else:
		score += 150
		spawn_particles(pw.global_position, Color8(255, 100, 150), 12)
	if coin_sound: coin_sound.play()
	coin_items.erase(pw)
	return_coin_node(pw)

func _on_player_landed() -> void:
	spawn_particles(player.global_position + Vector3(0, 0.1, 0), Color8(180, 190, 160), 4)

func on_player_hit(kind: String) -> void:
	if shield_time > 0:
		shield_time = maxf(0, shield_time - 4.0)
		shake_amount = 0.8
		flash_screen(0.3, 0.15)
		score += 100
		spawn_particles(player.global_position + Vector3(0, 1, 0), Color8(57, 200, 190), 10)
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
