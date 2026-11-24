extends Node
class_name PhysicsLoadSimulator

## Gestor centralizado de carga de física (PhysicsManager).
## Ejecuta cálculos matemáticos intensivos por pelota en modo:
## - Single-Core (use_multithreading = false): bucle secuencial en el hilo principal.
## - Multi-Core  (use_multithreading = true):  WorkerThreadPool.add_group_task en paralelo
##   repartido automáticamente entre todos los núcleos físicos de la CPU.

@export var use_multithreading: bool = false
@export var math_iterations: int = 50000
@export var turbulence_strength: float = 240.0
@export var balls_container_path: NodePath = NodePath("../BallsContainer")

var arena_center: Vector2 = Vector2(576.0, 324.0)
var last_compute_ms: float = 0.0

var _balls_container: Node = null
var _time: float = 0.0

# Buffers thread-safe preparados en el hilo principal antes de lanzar WorkerThreadPool:
# - _posiciones y _velocidades son de solo lectura durante el cálculo paralelo.
# - Cada hilo trabajador escribe únicamente en su índice exclusivo de _fuerzas_resultantes.
var _pelotas: Array[RigidBody2D] = []
var _posiciones: Array[Vector2] = []
var _velocidades: Array[float] = []
var _fuerzas_resultantes: Array[Vector2] = []

var _center_snapshot: Vector2 = Vector2(576.0, 324.0)
var _time_snapshot: float = 0.0
var _iterations_snapshot: int = 50000
var _turbulence_snapshot: float = 240.0


func _ready() -> void:
	_balls_container = get_node_or_null(balls_container_path)


func toggle_multithreading() -> bool:
	use_multithreading = not use_multithreading
	return use_multithreading


func _physics_process(delta: float) -> void:
	if _balls_container == null:
		_balls_container = get_node_or_null(balls_container_path)
		if _balls_container == null:
			return

	_time += delta * 2.5

	# 1. Fase segura en el Hilo Principal: recolectar pelotas y copiar posiciones/velocidades.
	_pelotas.clear()
	for child in _balls_container.get_children():
		if child is RigidBody2D and not child.is_queued_for_deletion():
			_pelotas.append(child as RigidBody2D)

	var count: int = _pelotas.size()
	if count == 0:
		last_compute_ms = 0.0
		return

	_posiciones.resize(count)
	_velocidades.resize(count)
	_fuerzas_resultantes.resize(count)

	for i in range(count):
		var body: RigidBody2D = _pelotas[i]
		_posiciones[i] = body.global_position
		_velocidades[i] = body.linear_velocity.length()

	# Congelar parámetros de solo lectura para los hilos trabajadores.
	_center_snapshot = arena_center
	_time_snapshot = _time
	_iterations_snapshot = math_iterations
	_turbulence_snapshot = turbulence_strength

	# 2. Fase de cálculo intensivo (Single-Core vs Multi-Core con WorkerThreadPool).
	var start_usec: int = Time.get_ticks_usec()

	if not use_multithreading:
		# Modo Single-Core: procesa todas las pelotas de forma secuencial en el hilo principal.
		for i in range(count):
			_procesar_pelota(i)
	else:
		# Modo Multi-Core: distribuye cada índice de pelota entre los núcleos con WorkerThreadPool.
		var task_id: int = WorkerThreadPool.add_group_task(
			Callable(self, "_procesar_pelota"),
			count,
			-1,
			true
		)
		WorkerThreadPool.wait_for_group_task_completion(task_id)

	last_compute_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0

	# 3. Fase segura en el Hilo Principal: aplicar las fuerzas calculadas a cada RigidBody2D.
	for i in range(count):
		_pelotas[i].apply_central_force(_fuerzas_resultantes[i])


func _procesar_pelota(index: int) -> void:
	# Esta función se ejecuta en paralelo en distintos núcleos cuando use_multithreading == true.
	# No accede ni modifica nodos del SceneTree; solo lee los arreglos de entrada y escribe en index.
	var pos: Vector2 = _posiciones[index]
	var speed: float = _velocidades[index]
	var center: Vector2 = _center_snapshot

	var dx: float = center.x - pos.x
	var dy: float = center.y - pos.y
	var dist: float = sqrt(dx * dx + dy * dy + 1.0)
	var inv_dist: float = 1.0 / dist

	var angle: float = atan2(dy, dx) + _time_snapshot + float(index) * 0.17
	var acc_x: float = 0.0
	var acc_y: float = 0.0
	var iters: int = _iterations_snapshot

	# Bucle matemático pesado de 50,000 iteraciones por pelota.
	for _i in range(iters):
		angle += 0.00073
		var s: float = sin(angle) * inv_dist
		acc_x += s
		acc_y += s * 0.5 - inv_dist * 0.25

	var turb_len: float = sqrt(acc_x * acc_x + acc_y * acc_y + 0.0001)
	var turb_x: float = acc_x / turb_len
	var turb_y: float = acc_y / turb_len

	# Combinar turbulencia calculada con un leve remolino tangencial alrededor del centro.
	var swirl_x: float = -dy * inv_dist
	var swirl_y: float = dx * inv_dist
	var strength: float = _turbulence_snapshot

	var force_x: float = (turb_x * 0.75 + swirl_x * 0.25) * strength
	var force_y: float = (turb_y * 0.75 + swirl_y * 0.25) * strength

	# Evitar que la pelota pierda impulso y se estanque en el suelo.
	if speed < 60.0:
		force_y -= strength * 0.85

	_fuerzas_resultantes[index] = Vector2(force_x, force_y)
