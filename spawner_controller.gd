extends Node2D
class_name SpawnerController

## Script 1: Hilo de Renderizado / Input.
## Gestiona la entrada del usuario (clic izquierdo, Espacio mantenido, tecla M para alternar
## Single-Core / Multi-Core y tecla R / botón para reiniciar) y actualiza el HUD en tiempo real.

@export var ball_scene: PackedScene = preload("res://ball.tscn")
@export var balls_per_click: int = 10
@export var space_spawn_rate: float = 120.0
@export var wall_thickness: float = 200.0
@export var spawn_margin: float = 24.0

@onready var background: ColorRect = $Background
@onready var balls_container: Node2D = $BallsContainer
@onready var physics_manager: Node = $PhysicsManager
@onready var wall_left: StaticBody2D = $Walls/WallLeft
@onready var wall_right: StaticBody2D = $Walls/WallRight
@onready var wall_top: StaticBody2D = $Walls/WallTop
@onready var wall_bottom: StaticBody2D = $Walls/WallBottom
@onready var stats_label: Label = $CanvasLayer/HudPanel/MarginContainer/VBoxContainer/StatsLabel
@onready var toggle_mode_button: Button = $CanvasLayer/HudPanel/MarginContainer/VBoxContainer/ButtonsRow/ToggleModeButton
@onready var reset_button: Button = $CanvasLayer/HudPanel/MarginContainer/VBoxContainer/ButtonsRow/ResetButton

var _space_spawn_accumulator: float = 0.0
var _arena_size: Vector2 = Vector2(1152.0, 648.0)
var _cpu_cores: int = 1


func _ready() -> void:
	_cpu_cores = OS.get_processor_count()

	# Evitar que la tecla Espacio active botones de la UI por foco.
	toggle_mode_button.focus_mode = Control.FOCUS_NONE
	reset_button.focus_mode = Control.FOCUS_NONE

	toggle_mode_button.pressed.connect(_on_toggle_multithreading)
	reset_button.pressed.connect(reset_benchmark)

	get_viewport().size_changed.connect(_update_arena_bounds)
	_update_arena_bounds()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	# Clic izquierdo del mouse: instanciar 10 pelotas nuevas en la posición del cursor.
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			spawn_balls(get_global_mouse_position(), balls_per_click)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			# Tecla M: alternar en tiempo real entre Single-Thread y Multi-Thread (WorkerThreadPool).
			if key_event.keycode == KEY_M:
				_on_toggle_multithreading()
				get_viewport().set_input_as_handled()
				return

			# Tecla R: reiniciar la prueba eliminando todas las pelotas activas.
			if key_event.keycode == KEY_R:
				reset_benchmark()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Mantener Espacio presionado: generar pelotas continuamente para saturar la CPU.
	if Input.is_key_pressed(KEY_SPACE):
		_space_spawn_accumulator += delta * space_spawn_rate
		var to_spawn: int = int(_space_spawn_accumulator)
		if to_spawn > 0:
			_space_spawn_accumulator -= float(to_spawn)
			var mouse_pos := get_global_mouse_position()
			var target_pos := mouse_pos if Rect2(Vector2.ZERO, _arena_size).has_point(mouse_pos) else (_arena_size * 0.5)
			spawn_balls(target_pos, to_spawn)
	else:
		_space_spawn_accumulator = 0.0

	_update_hud()


func _on_toggle_multithreading() -> void:
	if physics_manager and physics_manager.has_method("toggle_multithreading"):
		physics_manager.toggle_multithreading()
	_update_hud()


func spawn_balls(origin: Vector2, count: int) -> void:
	if ball_scene == null or count <= 0:
		return

	var min_pos := Vector2(spawn_margin, spawn_margin)
	var max_pos := Vector2(
		maxf(spawn_margin, _arena_size.x - spawn_margin),
		maxf(spawn_margin, _arena_size.y - spawn_margin)
	)

	for _i in range(count):
		var ball := ball_scene.instantiate() as RigidBody2D
		if ball == null:
			continue

		var jitter := Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
		ball.position = (origin + jitter).clamp(min_pos, max_pos)
		balls_container.add_child(ball)


func reset_benchmark() -> void:
	_space_spawn_accumulator = 0.0
	for child in balls_container.get_children():
		child.queue_free()


func _update_arena_bounds() -> void:
	_arena_size = get_viewport_rect().size
	if _arena_size.x <= 0.0 or _arena_size.y <= 0.0:
		_arena_size = Vector2(1152.0, 648.0)

	background.size = _arena_size

	var half_w: float = _arena_size.x * 0.5
	var half_h: float = _arena_size.y * 0.5
	var half_t: float = wall_thickness * 0.5

	var vertical_size := Vector2(wall_thickness, _arena_size.y + wall_thickness * 2.0)
	var horizontal_size := Vector2(_arena_size.x + wall_thickness * 2.0, wall_thickness)

	_configure_wall(wall_left, Vector2(-half_t, half_h), vertical_size)
	_configure_wall(wall_right, Vector2(_arena_size.x + half_t, half_h), vertical_size)
	_configure_wall(wall_top, Vector2(half_w, -half_t), horizontal_size)
	_configure_wall(wall_bottom, Vector2(half_w, _arena_size.y + half_t), horizontal_size)

	if physics_manager:
		physics_manager.arena_center = _arena_size * 0.5

	queue_redraw()


func _configure_wall(wall: StaticBody2D, wall_pos: Vector2, rect_size: Vector2) -> void:
	wall.position = wall_pos
	var shape_node := wall.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		(shape_node.shape as RectangleShape2D).size = rect_size


func _draw() -> void:
	draw_rect(Rect2(Vector2(2.0, 2.0), _arena_size - Vector2(4.0, 4.0)), Color(0.26, 0.42, 0.68, 0.85), false, 4.0)

	var center := _arena_size * 0.5
	var marker_color := Color(0.35, 0.55, 0.85, 0.30)
	draw_arc(center, 18.0, 0.0, TAU, 32, marker_color, 2.0)
	draw_line(center + Vector2(-10.0, 0.0), center + Vector2(10.0, 0.0), marker_color, 1.5)
	draw_line(center + Vector2(0.0, -10.0), center + Vector2(0.0, 10.0), marker_color, 1.5)


func _update_hud() -> void:
	var fps: int = int(Engine.get_frames_per_second())
	var active_balls: int = balls_container.get_child_count()
	var is_multithread: bool = bool(physics_manager.use_multithreading) if physics_manager else false
	var compute_ms: float = float(physics_manager.last_compute_ms) if physics_manager else 0.0

	var mode_text: String = (
		"MULTI-THREAD (Todos los núcleos - WorkerThreadPool)"
		if is_multithread
		else "SINGLE-THREAD (1 Núcleo)"
	)

	stats_label.text = (
		"BENCHMARK MULTINÚCLEO (CPU)\n"
		+ "FPS: %d\n" % fps
		+ "Pelotas en pantalla: %d\n" % active_balls
		+ "Modo activo: %s\n" % mode_text
		+ "Tiempo de cálculo: %.2f ms  |  Hilos CPU: %d\n" % [compute_ms, _cpu_cores]
		+ "────────────────────────────────────────────────────\n"
		+ "[M] Alternar Single-Thread / Multi-Thread\n"
		+ "[Clic Izq] +10 pelotas  |  [Espacio] Continuo  |  [R] Reiniciar"
	)
