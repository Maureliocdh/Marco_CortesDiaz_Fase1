extends Area3D

signal picked(value: int)

@export var value := 1
@export var spin_speed := 2.0
@export var bob_height := 0.12
@export var bob_speed := 3.0

@onready var visual = $Visual

var _base_y := 0.0
var _time := 0.0

func _ready():
	_base_y = global_position.y
	add_to_group("collectible")
	body_entered.connect(_on_body_entered)

func _process(delta):
	_time += delta
	if visual:
		visual.rotation.y += spin_speed * delta
		visual.position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body):
	if body.is_in_group("player"):
		collect()

func collect():
	picked.emit(value)
	queue_free()
