extends MeshInstance3D

@export var target_marker: Marker3D
@export var rotation_axis: Vector3 = Vector3(1, 0, 0) # local axis to rotate around
@export var aim_axis: Vector3 = Vector3(0, 0, -1) # local axis that should point to target
@export var max_turn_speed: float = 0.0 # radians/sec (0 = instant)
@export var mesh_length: float = 1.0 # original length of the mesh along aim_axis
@export var min_length: float = 0.1 # prevent zero scale

const EPS = 1e-6

func _process(delta: float) -> void:
	if not target_marker:
		return
	_aim_and_stretch(target_marker.global_transform.origin, delta)

func _aim_and_stretch(target_pos: Vector3, delta: float) -> void:
	if rotation_axis.length() < EPS or aim_axis.length() < EPS:
		return

	# --- Rotation ---
	var basis = global_transform.basis.orthonormalized()
	var axis_local = rotation_axis.normalized()
	var axis_world = (basis * axis_local).normalized()

	var to_target = target_pos - global_transform.origin
	var distance = to_target.length()
	if distance < EPS:
		return
	var to_target_dir = to_target / distance

	var proj_target = to_target_dir - axis_world * to_target_dir.dot(axis_world)
	var lt = proj_target.length()
	if lt < EPS:
		return
	proj_target /= lt

	var aim_world = (basis * aim_axis).normalized()
	var proj_aim = aim_world - axis_world * aim_world.dot(axis_world)
	var la = proj_aim.length()
	if la < EPS:
		return
	proj_aim /= la

	var d = clamp(proj_aim.dot(proj_target), -1.0, 1.0)
	var ang = acos(d)
	var sign = axis_world.dot(proj_aim.cross(proj_target))
	if sign < 0.0:
		ang = -ang

	if max_turn_speed > 0.0:
		var max_delta = max_turn_speed * delta
		ang = clamp(ang, -max_delta, max_delta)

	if abs(ang) > 1e-5:
		var rot_basis = Basis(axis_world, ang)
		global_transform.basis = (rot_basis * basis).orthonormalized()

	# --- Stretch along local aim_axis ---
	var final_length = max(distance, min_length)
	var scale_factor = final_length / max(mesh_length, EPS)

	var new_scale = scale
	new_scale.x = scale_factor if aim_axis.x != 0 else scale.x
	new_scale.y = scale_factor if aim_axis.y != 0 else scale.y
	new_scale.z = scale_factor if aim_axis.z != 0 else scale.z
	scale = new_scale
