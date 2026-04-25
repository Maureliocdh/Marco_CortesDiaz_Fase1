extends Node3D

const SAVE_PATH = "user://crossy_marco_save.cfg"
const NPC_SCENE = preload("res://scenes/NPC.tscn")
const COLLECTIBLE_SCENE = preload("res://scenes/Collectible.tscn")

@onready var player = $Player
@onready var player_camera = $Player/Camera3D
@onready var ui_label = $UI/CollisionMessage
@onready var attempts_label = $UI/AttemptsLabel
@onready var score_label = $UI/ScoreLabel
@onready var best_label = $UI/BestLabel
@onready var collectible_label = $UI/CollectiblesLabel
@onready var api_label = $UI/ApiLabel
@onready var ui_root = $UI
@onready var start_menu = $UI/StartMenu
@onready var start_button = $UI/StartMenu/StartButton
@onready var pause_menu = $UI/PauseMenu
@onready var resume_button = $UI/PauseMenu/ResumeButton
@onready var restart_button = $UI/PauseMenu/RestartButton
@onready var music_slider = $UI/PauseMenu/MusicSlider
@onready var sfx_slider = $UI/PauseMenu/SfxSlider
@onready var difficulty_option = $UI/PauseMenu/DifficultyOption
@onready var game_over_menu = $UI/GameOverMenu
@onready var game_over_rows_label = $UI/GameOverMenu/RowsValue
@onready var game_over_best_label = $UI/GameOverMenu/BestValue
@onready var retry_button = $UI/GameOverMenu/RetryButton
@onready var api_request = $ApiHTTPRequest

@onready var sfx_root = $SFX
@onready var jump_sfx_player = $SFX/JumpSFX
@onready var hit_sfx_player = $SFX/HitSFX
@onready var ui_sfx_player = $SFX/UiSFX
@onready var bgm_player = $SFX/BgmPlayer

@export var jump_sfx_path = "res://assets/sfx/jump.wav"
@export var hit_sfx_path = "res://assets/sfx/hit.wav"
@export var ui_sfx_path = "res://assets/sfx/ui.wav"
@export var bgm_path = "res://assets/sfx/chill_bgm.wav"

@export var collectible_spawn_chance = 0.42
@export var sqlite_helper_path = "res://scripts/sqlite_helper.py"
@export var sqlite_db_path = "user://game_data.db"
@export var api_advice_url = "https://api.adviceslip.com/advice"

@export var lane_half_width = 12.0
@export var lane_size_z = 1.0
@export var ahead_rows = 80
@export var keep_behind_rows = 25

var hit_count = 0
var is_processing_hit = false
var game_started = false
var is_game_over = false
var camera_initial_position = Vector3.ZERO
var difficulty_multiplier = 1.0
var current_rows = 0
var best_rows = 0
var collected_count = 0
var api_speed_factor = 1.0
var api_pending = false
var api_last_text = ""
var music_volume_linear = 0.6
var sfx_volume_linear = 0.85
var difficulty_mode_index = 1

var lane_origin_z = 7.0
var generated_root: Node3D
var lane_materials = {}
var lane_data = {}
var generated_min_row = 0
var generated_max_row = -1
var blocked_cells = {}
var spawned_npcs = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_ensure_pause_action()
	if ui_root:
		ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
	if sfx_root:
		sfx_root.process_mode = Node.PROCESS_MODE_ALWAYS
	if api_request:
		api_request.request_completed.connect(_on_api_request_completed)

	if player:
		lane_origin_z = player.global_position.z
	if player_camera:
		camera_initial_position = player_camera.position

	_setup_audio()
	_setup_sqlite_db()
	_load_best_rows()
	_create_lane_materials()
	_prepare_generation_root()
	_remove_legacy_nodes()
	_generate_initial_world()

	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)
	if resume_button:
		resume_button.pressed.connect(_on_resume_button_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)
	if retry_button:
		retry_button.pressed.connect(_on_retry_button_pressed)
	if music_slider:
		music_slider.value_changed.connect(_on_music_slider_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	if difficulty_option:
		difficulty_option.item_selected.connect(_on_difficulty_option_selected)
		_setup_difficulty_option()

	if player and player.has_signal("row_advanced"):
		player.row_advanced.connect(_on_player_row_advanced)
	if player and player.has_signal("hopped"):
		player.hopped.connect(_on_player_hopped)
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)

	_update_attempts_label()
	_update_score_label(0)
	_update_best_label()
	_update_collectible_label()
	_update_api_label("API: lista")
	_show_start_menu()
	if game_over_menu:
		game_over_menu.visible = false

func _physics_process(delta):
	if not game_started or is_game_over or get_tree().paused:
		return

	_update_logs_and_river(delta)
	_check_collectibles_proximity()
	_ensure_rows_for_progress(current_rows)
	_cleanup_rows_behind(current_rows)

func _unhandled_input(event):
	if not game_started or is_game_over:
		return

	if event.is_action_pressed("game_pause"):
		_toggle_pause_menu()

func _ensure_pause_action():
	if not InputMap.has_action("game_pause"):
		InputMap.add_action("game_pause")

	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	if not InputMap.action_has_event("game_pause", event):
		InputMap.action_add_event("game_pause", event)

func _show_start_menu():
	if start_menu:
		start_menu.visible = true
	if pause_menu:
		pause_menu.visible = false
	if game_over_menu:
		game_over_menu.visible = false
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)
	get_tree().paused = true

func _on_start_button_pressed():
	_play_ui_sfx()
	game_started = true
	if start_menu:
		start_menu.visible = false
	if pause_menu:
		pause_menu.visible = false
	if game_over_menu:
		game_over_menu.visible = false
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)
	get_tree().paused = false

func _toggle_pause_menu():
	if get_tree().paused:
		_on_resume_button_pressed()
		return

	if pause_menu:
		pause_menu.visible = true
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)
	_play_ui_sfx()
	get_tree().paused = true

func _on_resume_button_pressed():
	_play_ui_sfx()
	if pause_menu:
		pause_menu.visible = false
	if player and player.has_method("set_controls_enabled") and not is_game_over:
		player.set_controls_enabled(true)
	get_tree().paused = false

func _on_restart_button_pressed():
	_play_ui_sfx()
	_reset_run_state()
	_on_resume_button_pressed()

func _on_retry_button_pressed():
	_play_ui_sfx()
	if game_over_menu:
		game_over_menu.visible = false
	is_game_over = false
	_reset_run_state()
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)
	get_tree().paused = false

func _reset_run_state():
	hit_count = 0
	_update_attempts_label()
	_update_score_label(0)
	current_rows = 0
	difficulty_multiplier = _difficulty_factor()
	_apply_difficulty_to_npcs()
	if player:
		player.respawn()
	if player_camera:
		player_camera.position = camera_initial_position

func _trigger_player_fail(reason: String):
	if is_processing_hit or is_game_over or not game_started:
		return
	is_processing_hit = true

	hit_count += 1
	_update_attempts_label()
	_register_best_rows(collected_count)
	_play_hit_sfx()
	_show_game_over(current_rows)

	if ui_label:
		ui_label.text = reason
		ui_label.show()
		await get_tree().create_timer(1.0).timeout
		ui_label.hide()

	is_processing_hit = false

func _on_npc_hit_player(_npc):
	_trigger_player_fail("Choque! Vuelves al inicio")

func _on_player_row_advanced(rows: int):
	current_rows = rows
	_update_score_label(rows)
	_update_difficulty(rows)
	_update_camera_follow(rows)
	_ensure_rows_for_progress(rows)
	_cleanup_rows_behind(rows)

func _update_attempts_label():
	if attempts_label:
		attempts_label.text = "Intentos: %d" % hit_count

func _update_score_label(rows: int):
	if score_label:
		score_label.text = "Filas: %d" % rows

func _update_best_label():
	if best_label:
		best_label.text = "Mejor historico: %d" % best_rows

func _update_collectible_label():
	if collectible_label:
		collectible_label.text = "Monedas: %d" % collected_count

func _update_api_label(text: String):
	api_last_text = text
	if api_label:
		api_label.text = text

func _update_difficulty(rows: int):
	var base_multiplier = min(1.0 + float(rows) * 0.035, 2.0)
	difficulty_multiplier = clamp(base_multiplier * _difficulty_factor(), 0.6, 2.4)
	_apply_difficulty_to_npcs()

func _apply_difficulty_to_npcs():
	var effective_multiplier = difficulty_multiplier * api_speed_factor
	for npc in spawned_npcs:
		if is_instance_valid(npc) and npc.has_method("set_speed_multiplier"):
			npc.set_speed_multiplier(effective_multiplier)

func _update_camera_follow(rows: int):
	if not player_camera:
		return
	player_camera.position.z = camera_initial_position.z - min(float(rows) * 0.08, 24.0)

func _show_game_over(rows: int):
	is_game_over = true
	_save_highscore_to_db(collected_count)
	if pause_menu:
		pause_menu.visible = false
	if game_over_menu:
		game_over_menu.visible = true
	if game_over_rows_label:
		game_over_rows_label.text = "Monedas recogidas: %d" % collected_count
	if game_over_best_label:
		game_over_best_label.text = "Mejor historico: %d" % best_rows
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)
	get_tree().paused = true

func _register_best_rows(rows: int):
	if rows <= best_rows:
		return
	best_rows = rows
	_update_best_label()
	_save_best_rows()

func _load_best_rows():
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		music_volume_linear = float(config.get_value("audio", "music_volume_linear", 0.6))
		sfx_volume_linear = float(config.get_value("audio", "sfx_volume_linear", 0.85))
		difficulty_mode_index = int(config.get_value("game", "difficulty_mode_index", 1))

	best_rows = _db_get_best_score()

	music_volume_linear = clamp(music_volume_linear, 0.0, 1.0)
	sfx_volume_linear = clamp(sfx_volume_linear, 0.0, 1.0)
	difficulty_mode_index = clamp(difficulty_mode_index, 0, 2)

	if music_slider:
		music_slider.set_value_no_signal(music_volume_linear)
	if sfx_slider:
		sfx_slider.set_value_no_signal(sfx_volume_linear)
	if difficulty_option:
		difficulty_option.select(difficulty_mode_index)

func _save_best_rows():
	var config := ConfigFile.new()
	config.set_value("game", "difficulty_mode_index", difficulty_mode_index)
	config.set_value("audio", "music_volume_linear", music_volume_linear)
	config.set_value("audio", "sfx_volume_linear", sfx_volume_linear)
	config.save(SAVE_PATH)

func _setup_sqlite_db():
	var result = _run_python_db_command(["init", ProjectSettings.globalize_path(sqlite_db_path)])
	if not result.is_empty() and result.has("best"):
		best_rows = int(result["best"].get("max_score", 0))
	_update_best_label()

func _db_get_best_score() -> int:
	var result = _run_python_db_command(["get_best", ProjectSettings.globalize_path(sqlite_db_path)])
	if result.is_empty():
		return 0
	return int(result.get("max_score", 0))

func _save_highscore_to_db(score_value: int):
	if score_value <= best_rows:
		return
	var result = _run_python_db_command([
		"save_highscore",
		ProjectSettings.globalize_path(sqlite_db_path),
		"Jugador",
		str(score_value),
		Time.get_datetime_string_from_system(false, true)
	])
	if not result.is_empty():
		best_rows = int(result.get("max_score", score_value))
		_update_best_label()
		_save_best_rows()

func _run_python_db_command(args: Array) -> Dictionary:
	var helper_path = ProjectSettings.globalize_path(sqlite_helper_path)
	var full_args: Array = [helper_path]
	for arg in args:
		full_args.append(str(arg))
	var output: Array = []
	var code = OS.execute("python", full_args, output, true, false)
	if code != 0 or output.is_empty():
		return {}
	var parsed = JSON.parse_string(String(output[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _setup_audio():
	_try_set_stream(jump_sfx_player, jump_sfx_path)
	_try_set_stream(hit_sfx_player, hit_sfx_path)
	_try_set_stream(ui_sfx_player, ui_sfx_path)
	_try_set_stream(bgm_player, bgm_path)
	_apply_audio_volumes()
	if bgm_player and bgm_player.stream and not bgm_player.playing:
		bgm_player.play()

func _try_set_stream(player_node: AudioStreamPlayer, path: String):
	if not player_node:
		return
	if ResourceLoader.exists(path):
		player_node.stream = load(path)

func _on_player_hopped():
	_play_jump_sfx()

func _play_jump_sfx():
	if jump_sfx_player and jump_sfx_player.stream:
		jump_sfx_player.play()

func _play_hit_sfx():
	if hit_sfx_player and hit_sfx_player.stream:
		hit_sfx_player.play()

func _play_ui_sfx():
	if ui_sfx_player and ui_sfx_player.stream:
		ui_sfx_player.play()

func _apply_audio_volumes():
	if bgm_player:
		bgm_player.volume_db = linear_to_db(max(music_volume_linear, 0.001))
	if jump_sfx_player:
		jump_sfx_player.volume_db = linear_to_db(max(sfx_volume_linear, 0.001))
	if hit_sfx_player:
		hit_sfx_player.volume_db = linear_to_db(max(sfx_volume_linear, 0.001))
	if ui_sfx_player:
		ui_sfx_player.volume_db = linear_to_db(max(sfx_volume_linear, 0.001))

func _on_music_slider_changed(value: float):
	music_volume_linear = clamp(value, 0.0, 1.0)
	_apply_audio_volumes()
	_save_best_rows()

func _on_sfx_slider_changed(value: float):
	sfx_volume_linear = clamp(value, 0.0, 1.0)
	_apply_audio_volumes()
	_play_ui_sfx()
	_save_best_rows()

func _setup_difficulty_option():
	difficulty_option.clear()
	difficulty_option.add_item("Facil", 0)
	difficulty_option.add_item("Normal", 1)
	difficulty_option.add_item("Dificil", 2)
	difficulty_option.select(clamp(difficulty_mode_index, 0, 2))

func _difficulty_factor() -> float:
	match difficulty_mode_index:
		0:
			return 0.8
		1:
			return 1.0
		2:
			return 1.2
		_:
			return 1.0

func _on_difficulty_option_selected(index: int):
	difficulty_mode_index = clamp(index, 0, 2)
	_update_difficulty(current_rows)
	_play_ui_sfx()
	_save_best_rows()

func _on_collectible_picked(value: int):
	collected_count += value
	_update_collectible_label()
	_play_ui_sfx()
	_fetch_advice_from_api()
	_register_best_rows(collected_count)

func _fetch_advice_from_api():
	if api_pending or not api_request:
		return
	api_pending = true
	_update_api_label("API: buscando consejo...")
	var url = "%s?t=%s" % [api_advice_url, str(Time.get_ticks_msec())]
	api_request.request(url)

func _on_api_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	api_pending = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_update_api_label("API: no disponible")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("slip"):
		_update_api_label("API: respuesta invalida")
		return
	var advice = str(parsed["slip"].get("advice", ""))
	_update_api_label("Consejo: %s" % advice)
	api_speed_factor = 1.12 if advice.length() % 2 == 0 else 0.9
	_apply_difficulty_to_npcs()
	await get_tree().create_timer(8.0).timeout
	api_speed_factor = 1.0
	_apply_difficulty_to_npcs()
	_update_api_label("Consejo: %s" % advice)

func _prepare_generation_root():
	generated_root = Node3D.new()
	generated_root.name = "GeneratedWorld"
	add_child(generated_root)

func _remove_legacy_nodes():
	var prefixes = ["RoadLane", "LaneMark", "Car_", "Obstacle"]
	for child in get_children():
		if child == player or child == $UI or child == $SFX or child == $WorldEnvironment or child == $DirectionalLight3D:
			continue
		for prefix in prefixes:
			if child.name.begins_with(prefix):
				child.queue_free()
				break

func _create_lane_materials():
	lane_materials["grass"] = _make_material(Color(0.35, 0.7, 0.33, 1.0))
	lane_materials["road"] = _make_material(Color(0.16, 0.18, 0.23, 1.0))
	lane_materials["train"] = _make_material(Color(0.3, 0.18, 0.18, 1.0))
	lane_materials["river"] = _make_material(Color(0.2, 0.5, 0.86, 1.0))
	lane_materials["rail"] = _make_material(Color(0.74, 0.72, 0.66, 1.0))
	lane_materials["tree_trunk"] = _make_material(Color(0.45, 0.26, 0.14, 1.0))
	lane_materials["tree_leaf"] = _make_material(Color(0.18, 0.58, 0.2, 1.0))
	lane_materials["log"] = _make_material(Color(0.52, 0.33, 0.18, 1.0))

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _generate_initial_world():
	generated_min_row = -12
	generated_max_row = -13
	for row in range(generated_min_row, ahead_rows):
		_generate_row(row)

	_spawn_start_collectibles()

func _ensure_rows_for_progress(rows: int):
	var wanted_max = rows + ahead_rows
	while generated_max_row < wanted_max:
		_generate_row(generated_max_row + 1)

	var wanted_min = rows - keep_behind_rows
	while generated_min_row > wanted_min:
		_generate_row(generated_min_row - 1)

func _cleanup_rows_behind(rows: int):
	var min_keep = rows - keep_behind_rows
	var max_keep = rows + ahead_rows + 2
	var to_remove = []
	for row_key in lane_data.keys():
		if row_key < min_keep or row_key > max_keep:
			to_remove.append(row_key)

	for row_key in to_remove:
		_remove_row(row_key)

	generated_min_row = min_keep

func _generate_row(row: int):
	if lane_data.has(row):
		return

	var lane_type = _pick_lane_type(row)
	var lane_z = _z_from_row(row)
	var lane_root = Node3D.new()
	lane_root.name = "Lane_%d" % row
	generated_root.add_child(lane_root)

	_spawn_lane_strip(lane_root, lane_type, lane_z)

	var data = {
		"type": lane_type,
		"row": row,
		"z": lane_z,
		"root": lane_root,
		"logs": [],
		"blocked": []
	}
	lane_data[row] = data

	if lane_type == "grass":
		_spawn_trees_for_row(data)
		_spawn_collectible_for_row(data)
	elif lane_type == "road":
		_spawn_traffic_for_row(data, false)
	elif lane_type == "train":
		_spawn_traffic_for_row(data, true)
	elif lane_type == "river":
		_spawn_logs_for_row(data)

	generated_max_row = max(generated_max_row, row)
	generated_min_row = min(generated_min_row, row)

func _remove_row(row: int):
	if not lane_data.has(row):
		return
	var data = lane_data[row]
	for cell_key in data["blocked"]:
		blocked_cells.erase(cell_key)
	if is_instance_valid(data["root"]):
		data["root"].queue_free()
	lane_data.erase(row)

func _spawn_lane_strip(lane_root: Node3D, lane_type: String, lane_z: float):
	var mesh_node = MeshInstance3D.new()
	mesh_node.position = Vector3(0, 0.52, lane_z)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(lane_half_width * 2.0, 0.08, lane_size_z)
	mesh_node.mesh = mesh
	mesh_node.material_override = lane_materials.get(lane_type, lane_materials["grass"])
	lane_root.add_child(mesh_node)

	if lane_type == "train":
		var rail_left = MeshInstance3D.new()
		rail_left.position = Vector3(0, 0.58, lane_z - 0.24)
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(lane_half_width * 2.0, 0.06, 0.1)
		rail_left.mesh = rail_mesh
		rail_left.material_override = lane_materials["rail"]
		lane_root.add_child(rail_left)

		var rail_right = rail_left.duplicate()
		rail_right.position.z = lane_z + 0.24
		lane_root.add_child(rail_right)

func _spawn_trees_for_row(data):
	var tree_count = randi_range(1, 3)
	for _i in range(tree_count):
		var x_cell = randi_range(-10, 10)
		if abs(x_cell) <= 1:
			continue
		var cell_key = _cell_key(data["row"], x_cell)
		if blocked_cells.has(cell_key):
			continue
		blocked_cells[cell_key] = true
		data["blocked"].append(cell_key)

		var tree_root = Node3D.new()
		tree_root.position = Vector3(float(x_cell), 0.55, data["z"])
		data["root"].add_child(tree_root)

		var trunk_body = StaticBody3D.new()
		tree_root.add_child(trunk_body)

		var trunk_collision = CollisionShape3D.new()
		var trunk_shape := CylinderShape3D.new()
		trunk_shape.height = 0.7
		trunk_shape.radius = 0.16
		trunk_collision.shape = trunk_shape
		trunk_collision.position.y = 0.35
		trunk_body.add_child(trunk_collision)

		var trunk_mesh = MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 0.7
		cylinder.top_radius = 0.16
		cylinder.bottom_radius = 0.16
		trunk_mesh.mesh = cylinder
		trunk_mesh.position.y = 0.35
		trunk_mesh.material_override = lane_materials["tree_trunk"]
		tree_root.add_child(trunk_mesh)

		var leaves_mesh = MeshInstance3D.new()
		var leaves := BoxMesh.new()
		leaves.size = Vector3(0.8, 0.7, 0.8)
		leaves_mesh.mesh = leaves
		leaves_mesh.position.y = 0.95
		leaves_mesh.material_override = lane_materials["tree_leaf"]
		tree_root.add_child(leaves_mesh)

func _spawn_traffic_for_row(data, is_train: bool):
	var direction = 1 if randi() % 2 == 0 else -1
	var count = randi_range(2, 3) if is_train else randi_range(1, 3)
	var train_segment_gap = 6.2
	for i in range(count):
		var npc = NPC_SCENE.instantiate()
		npc.name = "LaneNpc_%d_%d" % [data["row"], i]
		if is_train:
			var start_x = (-lane_half_width - 5.0) - float(i) * train_segment_gap if direction > 0 else (lane_half_width + 5.0) + float(i) * train_segment_gap
			npc.position = Vector3(start_x, 1, data["z"])
		else:
			npc.position = Vector3(randf_range(-lane_half_width, lane_half_width), 1, data["z"])
		npc.set("movement_type", "lane_loop")
		npc.set("lane_direction", direction)
		npc.set("lane_min_x", -lane_half_width - 8.0)
		npc.set("lane_max_x", lane_half_width + 8.0)
		if is_train:
			npc.set("speed", randf_range(10.0, 14.0))
			var visual = npc.get_node_or_null("Visual")
			if visual:
				# El tren queda largo en Z para que, al rotar en lane_loop, apunte largo sobre X.
				visual.scale = Vector3(1.25, 1.0, 6.2)

			var hit_area = npc.get_node_or_null("HitArea")
			if hit_area:
				hit_area.scale = Vector3(0.5, 0.8, 0.75)

			var body_collision = npc.get_node_or_null("CollisionShape3D")
			if body_collision:
				body_collision.scale = Vector3(0.65, 1.0, 0.8)

			npc.set("speed", randf_range(7.0, 10.0))
			npc.set("body_color", Color(0.75, 0.75, 0.78, 1.0))
		else:
			npc.set("speed", randf_range(3.0, 6.5))
			npc.set("body_color", Color.from_hsv(randf(), 0.75, 0.98))

		data["root"].add_child(npc)
		spawned_npcs.append(npc)
		if npc.has_signal("player_hit"):
			npc.player_hit.connect(_on_npc_hit_player.bind(npc))
		if npc.has_method("set_speed_multiplier"):
			npc.set_speed_multiplier(difficulty_multiplier)

func _spawn_logs_for_row(data):
	var direction = 1 if randi() % 2 == 0 else -1
	var log_count = randi_range(2, 3)
	for _i in range(log_count):
		var length = randf_range(1.8, 3.2)
		var speed = randf_range(1.1, 2.0) * float(direction)
		var node = Node3D.new()
		node.position = Vector3(randf_range(-lane_half_width, lane_half_width), 0.82, data["z"])
		data["root"].add_child(node)

		var mesh_node = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length, 0.35, 0.72)
		mesh_node.mesh = mesh
		mesh_node.material_override = lane_materials["log"]
		node.add_child(mesh_node)

		var area = Area3D.new()
		node.add_child(area)
		var collision = CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(length * 0.92, 0.6, 0.78)
		collision.shape = shape
		area.add_child(collision)

		data["logs"].append({
			"node": node,
			"length": length,
			"speed": speed
		})

func _spawn_collectible_for_row(data):
	if randf() > collectible_spawn_chance:
		return
	var collectible = COLLECTIBLE_SCENE.instantiate()
	collectible.name = "Collectible_%d" % data["row"]
	collectible.position = Vector3(randf_range(-lane_half_width + 1.5, lane_half_width - 1.5), 0.8, data["z"])
	if collectible.has_signal("picked"):
		collectible.picked.connect(_on_collectible_picked)
	data["root"].add_child(collectible)

func _spawn_start_collectibles():
	for offset in range(0, 5):
		var row = offset
		if not lane_data.has(row):
			continue
		var data = lane_data[row]
		if data["type"] != "grass":
			continue
		var collectible = COLLECTIBLE_SCENE.instantiate()
		collectible.name = "StartCollectible_%d" % row
		collectible.position = Vector3(0, 0.8, data["z"])
		if collectible.has_signal("picked"):
			collectible.picked.connect(_on_collectible_picked)
		data["root"].add_child(collectible)

func _check_collectibles_proximity():
	if not player:
		return
	for collectible in get_tree().get_nodes_in_group("collectible"):
		if not is_instance_valid(collectible):
			continue
		if collectible.global_position.distance_to(player.global_position) <= 0.75:
			if collectible.has_method("collect"):
				collectible.collect()
			else:
				collectible.queue_free()

func _update_logs_and_river(delta):
	for row_key in lane_data.keys():
		var data = lane_data[row_key]
		if data["type"] != "river":
			continue
		for log_data in data["logs"]:
			var node: Node3D = log_data["node"]
			if not is_instance_valid(node):
				continue
			node.position.x += log_data["speed"] * delta
			if node.position.x > lane_half_width + 2.5:
				node.position.x = -lane_half_width - 2.5
			elif node.position.x < -lane_half_width - 2.5:
				node.position.x = lane_half_width + 2.5

	var player_row = _row_from_z(player.global_position.z)
	if not lane_data.has(player_row):
		return
	var lane = lane_data[player_row]
	if lane["type"] != "river":
		return

	var standing_log = _find_log_under_player(player_row)
	if standing_log == null:
		_trigger_player_fail("Te caes al rio")
		return

	player.global_position.x += standing_log["speed"] * delta
	if abs(player.global_position.x) > lane_half_width + 1.2:
		_trigger_player_fail("La corriente te arrastra")

func _find_log_under_player(row: int):
	if not lane_data.has(row):
		return null
	var data = lane_data[row]
	for log_data in data["logs"]:
		var node: Node3D = log_data["node"]
		if not is_instance_valid(node):
			continue
		if abs(node.position.z - player.global_position.z) > 0.5:
			continue
		if abs(node.position.x - player.global_position.x) <= (log_data["length"] * 0.5):
			return log_data
	return null

func can_player_move_to(target_pos: Vector3) -> bool:
	var row = _row_from_z(target_pos.z)
	if not lane_data.has(row):
		return true
	var lane = lane_data[row]
	if lane["type"] == "grass":
		var x_cell = int(round(target_pos.x))
		return not blocked_cells.has(_cell_key(row, x_cell))
	if lane["type"] == "river":
		# Permitir saltar al agua; si no cae en tronco, la logica de rio lo mata.
		return true
	return true

func _pick_lane_type(row: int) -> String:
	if row <= 0:
		return "grass"
	if row <= 2:
		return "grass"

	var r = randf()
	if r < 0.28:
		return "grass"
	if r < 0.62:
		return "road"
	if r < 0.82:
		return "river"
	return "train"

func _z_from_row(row: int) -> float:
	return lane_origin_z - float(row)

func _row_from_z(z: float) -> int:
	return int(round(lane_origin_z - z))

func _cell_key(row: int, x_cell: int) -> String:
	return "%d:%d" % [row, x_cell]
