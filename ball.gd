extends RigidBody2D

## Script ligero de la pelota: únicamente dibuja el círculo brillante con _draw()
## y aplica el impulso inicial aleatorio al instanciarse.
## Toda la carga matemática pesada la centraliza el nodo PhysicsManager.

@export var ball_radius: float = 12.0
@export var initial_impulse_min: float = 280.0
@export var initial_impulse_max: float = 560.0

var ball_color: Color = Color.CYAN


func _ready() -> void:
	# Evitar que las pelotas duerman para mantener la simulación siempre activa.
	can_sleep = false

	# Color aleatorio brillante en espacio HSV.
	ball_color = Color.from_hsv(randf(), randf_range(0.80, 1.0), randf_range(0.90, 1.0))

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape and collision_shape.shape is CircleShape2D:
		ball_radius = (collision_shape.shape as CircleShape2D).radius

	queue_redraw()

	# Aplicar impulso inicial aleatorio al instanciarse.
	var random_dir := Vector2.from_angle(randf() * TAU)
	var impulse_magnitude := randf_range(initial_impulse_min, initial_impulse_max)
	apply_central_impulse(random_dir * impulse_magnitude)


func _draw() -> void:
	draw_circle(Vector2.ZERO, ball_radius, ball_color)
	draw_circle(
		Vector2(-ball_radius * 0.28, -ball_radius * 0.28),
		ball_radius * 0.24,
		Color(1.0, 1.0, 1.0, 0.45)
	)
