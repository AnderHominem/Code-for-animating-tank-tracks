extends MeshInstance3D

@export var target_mesh: MeshInstance3D

@export var rotation_axis: Vector3 = Vector3(1, 0, 0) # local axis to rotate around (default +X)
@export var aim_axis: Vector3 = Vector3(0, 0, -1) # local axis that should point to target (default -Z)
@export var max_turn_speed: float = 0.0 # radians/sec (0 = instant)

const EPS = 1e-6

func _process(delta: float) -> void:
	if not target_mesh:
		return
	var ang_rotated = _aim_at(target_mesh.global_transform.origin, delta)
	


# returns the angle rotated this frame
func _aim_at(target_pos: Vector3, delta: float) -> float:
	if rotation_axis.length() < EPS or aim_axis.length() < EPS:
		return 0.0

	var basis = global_transform.basis.orthonormalized()
	var axis_local = rotation_axis.normalized()
	var axis_world = (basis * axis_local).normalized()

	var to_target = target_pos - global_transform.origin
	if to_target.length() < EPS:
		return 0.0
	to_target = to_target.normalized()

	var proj_target = to_target - axis_world * to_target.dot(axis_world)
	var lt = proj_target.length()
	if lt < EPS:
		return 0.0
	proj_target /= lt

	var aim_world = (basis * aim_axis).normalized()
	var proj_aim = aim_world - axis_world * aim_world.dot(axis_world)
	var la = proj_aim.length()
	if la < EPS:
		return 0.0
	proj_aim /= la

	var d = clamp(proj_aim.dot(proj_target), -1.0, 1.0)
	var ang = acos(d)
	var sign = axis_world.dot(proj_aim.cross(proj_target))
	if sign < 0.0:
		ang = -ang

	if max_turn_speed > 0.0:
		var max_delta = max_turn_speed * delta
		ang = clamp(ang, -max_delta, max_delta)

	if abs(ang) < EPS:
		return 0.0

	var rot_basis = Basis(axis_world, ang)
	global_transform.basis = (rot_basis * basis).orthonormalized()
	
	return ang
