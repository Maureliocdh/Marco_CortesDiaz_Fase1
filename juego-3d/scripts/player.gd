extends CharacterBody3D

# Movimiento estilo Crossy Road (por casillas)
@export var grid_size = 1.0
@export var hop_duration = 0.13
@export var hop_height = 0.35
@export var min_x = -8.5
@export var max_x = 8.5
@export var min_z = -9999.0
@export var max_z = 8.5
@export var player_color: Color = Color(1.0, 0.9, 0.35, 1.0)
@export var tint_imported_model = true
@export var character_scale = 0.7

# Referencia a la cámara
@onready var camera = $Camera3D
@onready var visual_root = $Visual
@onready var placeholder_mesh = $Visual/BodyMesh

# Posición inicial (para respawnar)
var spawn_position: Vector3
var base_y = 1.0
var is_hopping = false
var hop_from = Vector3.ZERO
var hop_to = Vector3.ZERO
var hop_progress = 0.0
var best_row = 0
var controls_enabled = false

signal row_advanced(rows: int)
signal hopped

func _ready():
	_ensure_input_actions()
	_attach_character_model()
	spawn_position = global_position
	base_y = global_position.y
	visual_root.scale = Vector3.ONE * character_scale
	_apply_placeholder_color()
	# Configurar cámara
	if camera:
		camera.current = true

func _attach_character_model():
	var candidate_paths := [
		"res://models/marco.gltf",
		"res://models/marco.glb",
		"res://marco.gltf",
		"res://marco.glb"
	]

	for candidate_path in candidate_paths:
		var model_resource = load(candidate_path)
		if model_resource is PackedScene:
			var model_instance = (model_resource as PackedScene).instantiate()
			visual_root.add_child(model_instance)
			if tint_imported_model:
				_apply_color_recursive(model_instance)
			if placeholder_mesh:
				placeholder_mesh.visible = false
			return

func _apply_placeholder_color():
	if not placeholder_mesh:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = player_color
	material.roughness = 0.65
	placeholder_mesh.material_override = material

func _apply_color_recursive(root: Node):
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.albedo_color = player_color
		material.roughness = 0.7
		mesh_instance.material_override = material

	for child in root.get_children():
		_apply_color_recursive(child)

func _ensure_input_actions():
	_bind_key("move_forward", KEY_W)
	_bind_key("move_forward", KEY_UP)
	_bind_key("move_back", KEY_S)
	_bind_key("move_back", KEY_DOWN)
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)

func _bind_key(action_name: String, keycode: Key):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	var event := InputEventKey.new()
	event.keycode = keycode

	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)

func _physics_process(delta):
	if not controls_enabled:
		return

	if is_hopping:
		_update_hop(delta)
		return

	var step_direction = _get_step_input()
	if step_direction == Vector3.ZERO:
		return

	_start_hop(step_direction)

func _get_step_input() -> Vector3:
	if Input.is_action_just_pressed("move_forward"):
		return Vector3(0, 0, -1)
	if Input.is_action_just_pressed("move_back"):
		return Vector3(0, 0, 1)
	if Input.is_action_just_pressed("move_left"):
		return Vector3(-1, 0, 0)
	if Input.is_action_just_pressed("move_right"):
		return Vector3(1, 0, 0)
	return Vector3.ZERO

func _start_hop(step_direction: Vector3):
	hop_from = global_position
	hop_to = hop_from + step_direction * grid_size
	hop_to.x = clamp(hop_to.x, min_x, max_x)
	hop_to.z = clamp(hop_to.z, min_z, max_z)
	hop_to.y = base_y

	if get_parent().has_method("can_player_move_to"):
		if not get_parent().can_player_move_to(hop_to):
			return

	if hop_from.is_equal_approx(hop_to):
		return

	hop_progress = 0.0
	is_hopping = true
	hopped.emit()

	var target_angle = atan2(step_direction.x, step_direction.z)
	visual_root.rotation.y = target_angle

func _update_hop(delta):
	hop_progress += delta / hop_duration
	var t = min(hop_progress, 1.0)
	var next_position = hop_from.lerp(hop_to, t)
	next_position.y += sin(t * PI) * hop_height
	global_position = next_position

	if t >= 1.0:
		global_position = hop_to
		is_hopping = false
		_update_rows()

func _update_rows():
	var rows = int(round((spawn_position.z - global_position.z) / grid_size))
	if rows > best_row:
		best_row = rows
		row_advanced.emit(best_row)

# Función para respawnar al jugador
func respawn():
	global_position = spawn_position
	is_hopping = false
	hop_progress = 0.0
	best_row = 0
	row_advanced.emit(0)

func set_controls_enabled(enabled: bool):
	controls_enabled = enabled
	if not controls_enabled:
		is_hopping = false
		hop_progress = 0.0
