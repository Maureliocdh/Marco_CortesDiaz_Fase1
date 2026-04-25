extends CharacterBody3D

# Tipo de movimiento: "linear", "random" o "lane_loop"
@export var movement_type = "linear"

# Para movimiento lineal
@export var point_a = Vector3(-5, 0, 0)
@export var point_b = Vector3(5, 0, 0)
@export var speed = 3.0
@export var body_color: Color = Color(0.95, 0.45, 0.2)
@export var lane_direction = 1
@export var lane_min_x = -10.0
@export var lane_max_x = 10.0

# Para movimiento aleatorio
@export var random_area = 5.0
@export var change_direction_interval = 2.0

# Variables internas
var current_target = Vector3.ZERO
var moving_to_b = true
var change_direction_timer = 0.0
var current_direction = Vector3.ZERO
var spawn_position: Vector3
var base_speed = 0.0
@onready var body_mesh = $Visual/BodyMesh
@onready var visual_root = $Visual

# Señal de colisión con el jugador
signal player_hit

func _ready():
	randomize()
	spawn_position = global_position
	base_speed = speed
	_apply_visual_color()
	
	if movement_type == "linear":
		current_target = point_b
		point_a = global_position + point_a
		point_b = global_position + point_b
	elif movement_type == "lane_loop":
		lane_direction = 1 if lane_direction >= 0 else -1
	else:
		current_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()

func _apply_visual_color():
	if not body_mesh:
		return
	
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	body_mesh.material_override = material

func _physics_process(delta):
	if movement_type == "linear":
		move_linear(delta)
	elif movement_type == "lane_loop":
		move_lane_loop()
	else:
		move_random(delta)
	
	move_and_slide()

func move_linear(delta):
	# Mover hacia el objetivo actual
	var direction = (current_target - global_position).normalized()
	velocity = direction * speed
	velocity.y = 0  # Sin movimiento vertical
	
	# Rotación hacia la dirección
	if velocity.length() > 0:
		var target_angle = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 0.1)
	
	# Cambiar objetivo al llegar
	if global_position.distance_to(current_target) < 0.5:
		moving_to_b = !moving_to_b
		current_target = point_b if moving_to_b else point_a

func move_lane_loop():
	velocity = Vector3(float(lane_direction) * speed, 0, 0)
	if visual_root:
		visual_root.rotation.y = PI * 0.5 if lane_direction > 0 else -PI * 0.5

	if global_position.x > lane_max_x:
		global_position.x = lane_min_x
	elif global_position.x < lane_min_x:
		global_position.x = lane_max_x

func move_random(delta):
	change_direction_timer -= delta
	
	if change_direction_timer <= 0:
		current_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		change_direction_timer = change_direction_interval
	
	velocity = current_direction * speed
	velocity.y = 0
	
	# Rotación hacia la dirección
	if velocity.length() > 0:
		var target_angle = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 0.1)
	
	# Mantener dentro del área de movimiento
	var distance = global_position.distance_to(spawn_position)
	if distance > random_area:
		var direction_to_center = (spawn_position - global_position).normalized()
		velocity = direction_to_center * speed

func _on_hit_area_body_entered(body):
	if body.is_in_group("player"):
		player_hit.emit()

func set_speed_multiplier(multiplier: float):
	speed = base_speed * multiplier
