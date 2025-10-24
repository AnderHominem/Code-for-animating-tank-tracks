#@tool
extends Path3D

@export var wheels: Array[RayCast3D] = []
@export var target_roller: MeshInstance3D
@export var distance_per_rotation = 0.5
@export var link_count: int = 10
@export var links_inertia := 8.0  # higher = faster response
@export var links_inertia_on_x := 0.4 

# Movable points logic
@export var movable_points: Array[int] = []  # indices of points that should move
@export var point_move_distance: = 0.1
@export var front_sproket: = false  # true = forward moves points down, backward moves points up
@export var rotation_threshold := 0.01
@export var point_smoothing_speed := 4.0

@export var front_roller: MeshInstance3D
@export var front_roller_coef: = 0.0
@export var ground_rollers: Array[MeshInstance3D] = []
@export var ground_rollers_coef: = 0.0
@export var top_rollers: Array[MeshInstance3D] = []
@export var top_rollers_coef: = 0.0

var is_dirty = false
var track_offset = 0.0
var last_roller_rotation: float = 0.0  # store roller rotation around local X

# Store previous positions for smoothing
var smoothed_wheel_positions: Array = []
var original_point_positions: Array = []
var current_point_offsets: Array = []
var link_distances: Array = []

func _ready():
	if target_roller:
		last_roller_rotation = target_roller.rotation.x
	
	# Initialize smoothed wheel positions
	smoothed_wheel_positions.resize(wheels.size())
	for i in range(wheels.size()):
		smoothed_wheel_positions[i] = Vector3.ZERO
	
	# Store original positions of points for movable points
	if curve:
		original_point_positions.resize(curve.get_point_count())
		current_point_offsets.resize(curve.get_point_count())
		for i in range(curve.get_point_count()):
			original_point_positions[i] = curve.get_point_position(i)
			current_point_offsets[i] = 0.0  # start at 0 offset

	# Initialize link distances
	if curve:
		link_distances.resize(link_count)
		var path_length = curve.get_baked_length()
		for i in range(link_count):
			link_distances[i] = i * (path_length / link_count)


func _physics_process(delta):
	_update_path_to_wheels(delta)
	if is_dirty:
		_update_multimesh()
		is_dirty = false

	var delta_rotation = _compute_rotation_delta()
	_move_track_links(delta_rotation)
	_rotate_rollers(delta_rotation)
	_move_points_by_rotation(delta_rotation, delta)

func _update_path_to_wheels(delta):
	if wheels.is_empty() or curve == null:
		return

	var pcnt = curve.get_point_count()
	for i in range(min(wheels.size(), pcnt)):
		var wheel = wheels[i]
		var world_point: Vector3

		if wheel.is_colliding():
			world_point = wheel.get_collision_point()
		else:
			world_point = wheel.to_global(wheel.target_position)

		# Convert current smoothed position and target to local space
		var local_smoothed = to_local(smoothed_wheel_positions[i])
		var local_target = to_local(world_point)

		# Apply smoothing per axis
		local_smoothed.x = lerp(local_smoothed.x, local_target.x, links_inertia_on_x)  # low smoothing along X
		var smooth_factor_yz = links_inertia * delta
		local_smoothed.y = lerp(local_smoothed.y, local_target.y, smooth_factor_yz)
		local_smoothed.z = lerp(local_smoothed.z, local_target.z, smooth_factor_yz)

		# Convert back to world space
		smoothed_wheel_positions[i] = to_global(local_smoothed)

		# Set the curve point
		curve.set_point_position(i, local_smoothed)

	# Update movable points that are NOT under wheels
	for point_idx in movable_points:
		if point_idx < wheels.size() or point_idx >= pcnt:
			continue

		var default_pos = original_point_positions[point_idx]
		var new_pos = default_pos + Vector3(0, current_point_offsets[point_idx], 0)
		curve.set_point_position(point_idx, new_pos)

	is_dirty = true

# --- Move track offset based on roller rotation ---
func _move_track_links(delta_rotation: float):
	if target_roller == null or curve == null:
		return
	var moved_distance = -delta_rotation / TAU * distance_per_rotation
	track_offset = fposmod(track_offset + moved_distance, curve.get_baked_length())
	is_dirty = true

# --- Update MultiMesh along path, evenly spaced links ---
func _update_multimesh():
	if curve == null:
		return

	var mm_instance = $MultiMeshInstance3D
	if mm_instance.multimesh == null:
		mm_instance.multimesh = MultiMesh.new()
	var mm: MultiMesh = mm_instance.multimesh
	mm.instance_count = link_count

	var path_length = curve.get_baked_length()
	if path_length <= 0.01:
		return

	var spacing = path_length / link_count

	for i in range(link_count):
		var curve_distance = fposmod(track_offset + spacing * i, path_length)
		var position = curve.sample_baked(curve_distance, true)
		var next_position = curve.sample_baked(curve_distance + 0.1, true)
		var forward = (next_position - position).normalized()
		var up = curve.sample_baked_up_vector(curve_distance, true)

		var right = forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		var basis = Basis()
		basis.x = right
		basis.y = up
		basis.z = -forward

		var transform = Transform3D(basis, position)
		mm.set_instance_transform(i, transform)


func _compute_rotation_delta() -> float:
	if target_roller == null:
		return 0.0
	var current_rotation = target_roller.rotation.x
	var delta_rotation = fposmod(current_rotation - last_roller_rotation + PI, TAU) - PI
	last_roller_rotation = current_rotation
	return delta_rotation



func _rotate_rollers(delta_rotation: float):
	if target_roller == null:
		return
	if front_roller:
		front_roller.rotation.x += delta_rotation * front_roller_coef
	for roller in ground_rollers:
		if roller:
			roller.rotation.x += delta_rotation * ground_rollers_coef
	for roller in top_rollers:
		if roller:
			roller.rotation.x += delta_rotation * top_rollers_coef

func _move_points_by_rotation(delta_rotation: float, delta: float):
	if curve == null or movable_points.is_empty():
		return

	var target_direction = 0
	if abs(delta_rotation) >= rotation_threshold:
		if delta_rotation > 0:
			target_direction = -1 if front_sproket else 1
		elif delta_rotation < 0:
			target_direction = 1 if front_sproket else -1

	var target_offset = target_direction * point_move_distance

	for point_idx in movable_points:
		if point_idx >= curve.get_point_count():
			continue
		# Smoothly move current offset toward target offset using a slower smoothing factor
		current_point_offsets[point_idx] = lerp(
			current_point_offsets[point_idx],
			target_offset,
			point_smoothing_speed * delta
		)

	is_dirty = true

func _on_curve_changed():
	is_dirty = true
