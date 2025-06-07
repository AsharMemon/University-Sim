extends Node3D

# Camera control speeds and limits
@export_category("Movement Speeds")
@export var pan_speed: float = 20.0  # Increased default for potentially larger maps
@export var rotation_speed: float = 90.0 # Degrees per second

@export_category("Zoom")
@export var zoom_speed_multiplier: float = 0.85 # Multiplier for zoom (e.g., 0.85 for zoom in, 1/0.85 for zoom out)
@export var min_cam_distance: float = 4.0  # Closest the camera can be
@export var max_cam_distance: float = 60.0 # Furthest the camera can be

# Pitch (X rotation of the rig) limits for "eye-level" effect
@export var pitch_at_min_zoom_deg: float = -10.0 # Angle when fully zoomed in (closer to eye-level)
@export var pitch_at_max_zoom_deg: float = -45.0 # Angle when fully zoomed out (more diagonal, less top-down)

# Height (Y position of the rig above pivot) limits based on zoom
@export var height_at_min_zoom: float = 2.0   # Rig height when fully zoomed in
@export var height_at_max_zoom: float = 35.0  # Rig height when fully zoomed out

@export_category("Panning & Edge Scroll")
@export var enable_edge_scroll: bool = true
@export var edge_scroll_margin: int = 30 # Pixels from the edge to trigger scroll
# Panning limits (map boundaries)
@export var map_min_x: float = -150.0
@export var map_max_x: float = 150.0
@export var map_min_z: float = -150.0
@export var map_max_z: float = 150.0

@onready var camera_3d: Camera3D = $Camera3D 

var target_pivot_point: Vector3 = Vector3.ZERO
const RAY_LENGTH: float = 1000.0

func _ready():
	# Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN) # Optional: Keeps mouse in window
	await get_tree().physics_frame 
	update_target_pivot_point()
	if target_pivot_point == Vector3.ZERO: 
		target_pivot_point = global_position * Vector3(1, 0, 1) # Project to ground
	
	# Ensure initial camera distance is within bounds
	camera_3d.position.z = clamp(camera_3d.position.z, min_cam_distance, max_cam_distance)
	_update_pitch_and_height_based_on_zoom()
	
	# Initial look_at to ensure correct orientation if pitch was just set
	if target_pivot_point != global_position:
		look_at(target_pivot_point, Vector3.UP)
		# Re-apply pitch after look_at, as look_at can also change pitch
		var current_zoom_t = inverse_lerp(min_cam_distance, max_cam_distance, camera_3d.position.z)
		var target_x_rot_deg = lerp(pitch_at_min_zoom_deg, pitch_at_max_zoom_deg, current_zoom_t)
		var current_rotation = rotation_degrees
		current_rotation.x = target_x_rot_deg
		rotation_degrees = current_rotation

# In your Camera Script
func zoom(amount_multiplier: float):
	var initial_z = camera_3d.position.z
	var target_z = initial_z * amount_multiplier
	
	# Clamp the zoom level
	# Note the min/max values the clamp is using!
	camera_3d.position.z = clamp(target_z, min_cam_distance, max_cam_distance)
	
	_update_pitch_and_height_based_on_zoom()

func _update_pitch_and_height_based_on_zoom():
	# Ensure camera_3d.position.z is within bounds for inverse_lerp to work as expected
	var current_cam_z_clamped = clamp(camera_3d.position.z, min_cam_distance, max_cam_distance)
	
	# Calculate normalized zoom factor (0.0 = min_cam_distance (zoomed in), 1.0 = max_cam_distance (zoomed out))
	var zoom_t: float = 0.5 # Default if min_cam_distance == max_cam_distance
	if (max_cam_distance - min_cam_distance) > 0.001: # Avoid division by zero
		zoom_t = inverse_lerp(min_cam_distance, max_cam_distance, current_cam_z_clamped)

	# 1. Interpolate X rotation (pitch) of the CameraRig (self)
	var target_x_rot_deg = lerp(pitch_at_min_zoom_deg, pitch_at_max_zoom_deg, zoom_t)
	
	# 2. Interpolate Y position (height) of the CameraRig (self) above the target_pivot_point
	var target_y_offset = lerp(height_at_min_zoom, height_at_max_zoom, zoom_t)
	
	var new_global_pos = global_position
	new_global_pos.y = target_pivot_point.y + target_y_offset
	global_position = new_global_pos

	# 3. Apply new pitch and ensure rig looks at pivot
	if target_pivot_point != global_position: 
		look_at(target_pivot_point, Vector3.UP) 
		var current_rotation = rotation_degrees
		current_rotation.x = target_x_rot_deg # Enforce our zoom-based pitch
		rotation_degrees = current_rotation
		
func _process(delta: float):
	update_target_pivot_point() 
	handle_keyboard_panning(delta)
	if enable_edge_scroll:
		handle_edge_scroll(delta)
	handle_rotation(delta)

func handle_keyboard_panning(delta: float):
	var input_dir = Input.get_vector("pan_left", "pan_right", "pan_forward", "pan_backward")
	if input_dir == Vector2.ZERO:
		return
	
	_execute_pan(input_dir, delta)

func handle_edge_scroll(delta: float):
	var focused_control = get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused_control) and \
	   (focused_control.mouse_filter == Control.MOUSE_FILTER_STOP or focused_control.get_parent_control_with_mouse_filter_stop() != null):
		# If a control has focus and it (or its parent that stops mouse) is set to MOUSE_FILTER_STOP,
		# it's likely a UI element (like a popup or panel) that should prevent edge scrolling.
		# print_debug("Edge scroll paused due to focused UI element: %s" % focused_control.name) # Optional debug
		return
	
	# Fallback: Check if input was handled by GUI (though for edge scroll, this might not always trigger as expected)
	if get_viewport().is_input_handled():
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var input_dir_edge = Vector2.ZERO

	if mouse_pos.x < edge_scroll_margin:
		input_dir_edge.x = -1.0
	elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
		input_dir_edge.x = 1.0
	
	if mouse_pos.y < edge_scroll_margin:
		input_dir_edge.y = -1.0 # Corresponds to "pan_forward"
	elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
		input_dir_edge.y = 1.0  # Corresponds to "pan_backward"

	if input_dir_edge == Vector2.ZERO:
		return
		
	_execute_pan(input_dir_edge, delta)

func _execute_pan(input_direction: Vector2, delta: float):
	# Pan relative to the rig's horizontal orientation (ignoring its pitch)
	var forward_no_tilt = (global_transform.basis.z * Vector3(1, 0, 1)).normalized()
	var right_no_tilt = (global_transform.basis.x * Vector3(1, 0, 1)).normalized()
	
	# If forward_no_tilt is near zero (e.g., camera looking straight down/up), use global axes
	if forward_no_tilt.length_squared() < 0.01:
		forward_no_tilt = -Vector3.FORWARD # Global Z-
		right_no_tilt = Vector3.RIGHT    # Global X+
		
	var pan_direction = (forward_no_tilt * input_direction.y + right_no_tilt * input_direction.x)

	if pan_direction.length_squared() > 0:
		pan_direction = pan_direction.normalized()
		var new_pos = global_position + pan_direction * pan_speed * delta
		
		new_pos.x = clamp(new_pos.x, map_min_x, map_max_x)
		new_pos.z = clamp(new_pos.z, map_min_z, map_max_z)
		# Y position is controlled by zoom, so we don't clamp it here during panning.
		# However, we need to ensure the height above the NEW target_pivot_point is maintained.
		# For now, this keeps Y as is during pure XZ pan, zoom will adjust Y.
		# A more robust solution would re-calculate Y based on the new pivot point after panning XZ,
		# but that can feel a bit like sticking to terrain. We'll let zoom handle Y.
		
		global_position = new_pos

func handle_rotation(delta: float):
	var rotation_dir = 0.0
	if Input.is_action_pressed("rotate_left"):
		rotation_dir += 1.0
	if Input.is_action_pressed("rotate_right"):
		rotation_dir -= 1.0
		
	if rotation_dir != 0.0:
		var rotation_angle = deg_to_rad(rotation_dir * rotation_speed * delta)
		var pivot = target_pivot_point 
		
		var relative_pos = global_position - pivot
		var rotated_relative_pos = relative_pos.rotated(Vector3.UP, rotation_angle)
		var new_global_position = pivot + rotated_relative_pos
		
		global_position = new_global_position
		
		# Maintain look_at and desired pitch
		if pivot != global_position:
			look_at(pivot, Vector3.UP)
			# Re-apply the calculated pitch because look_at will also set X rotation
			var current_zoom_t = inverse_lerp(min_cam_distance, max_cam_distance, camera_3d.position.z)
			var target_x_rot_deg = lerp(pitch_at_min_zoom_deg, pitch_at_max_zoom_deg, current_zoom_t)
			var current_rotation = rotation_degrees
			current_rotation.x = target_x_rot_deg
			rotation_degrees = current_rotation


# In your Camera Script (the Node3D that controls the camera)

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			zoom(zoom_speed_multiplier) 
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			zoom(1.0 / zoom_speed_multiplier)

	# --- NEW: Handle Trackpad Pinch-to-Zoom (Magnify Gesture) ---
	elif event is InputEventMagnifyGesture:
		# event.factor is > 1.0 for zooming out (spreading fingers)
		# and < 1.0 for zooming in (pinching fingers).
		# This is the opposite of how your current zoom_speed_multiplier works with the wheel amount.
		# If zoom_speed_multiplier is < 1.0 (e.g., 0.85 for zooming in with wheel up):
		# - To zoom IN with pinch (event.factor < 1.0), we want a multiplier < 1.0.
		# - To zoom OUT with pinch (event.factor > 1.0), we want a multiplier > 1.0.
		
		# Let's define how much the gesture influences the zoom.
		# A factor of 1.0 means no change. A factor of 1.1 is a 10% zoom out.
		# A factor of 0.9 is a 10% zoom in.
		# We need to scale this factor to be similar to your wheel zoom steps.
		
		var gesture_zoom_amount: float
		if event.factor > 1.0: # Zooming out (spreading fingers)
			# We want amount_multiplier > 1.0. event.factor is already > 1.0.
			# Let's scale it to be similar to (1.0 / zoom_speed_multiplier)
			# If zoom_speed_multiplier = 0.85, then 1/0.85 = ~1.176
			# If event.factor is e.g. 1.1, we can use it directly or scale it.
			# A simple approach: make it proportional.
			gesture_zoom_amount = 1.0 + (event.factor - 1.0) * 0.5 # Scale down the effect of magnify
		else: # Zooming in (pinching fingers, event.factor < 1.0)
			# We want amount_multiplier < 1.0. event.factor is already < 1.0.
			# If event.factor is e.g. 0.9
			gesture_zoom_amount = 1.0 - (1.0 - event.factor) * 0.5 # Scale down the effect of magnify

		# Ensure the amount is not too extreme
		gesture_zoom_amount = clamp(gesture_zoom_amount, 0.5, 1.5) # Clamp to avoid excessive jumps

		zoom(gesture_zoom_amount)
		
		# Accept the event so other controls don't process it if not needed
		get_viewport().set_input_as_handled()


	# Optional: Handle Rotation with Middle Mouse Drag (your existing commented-out code)
	# if event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MIDDLE:
	#	rotate_y(deg_to_rad(-event.relative.x * 0.5))

func update_target_pivot_point():
	var viewport = get_viewport()
	if not is_instance_valid(viewport): return

	# Raycast from the center of the camera's view
	var cam_transform = camera_3d.global_transform
	var ray_origin = cam_transform.origin
	var ray_direction = -cam_transform.basis.z # Camera looks along its local -Z

	var space_state = get_world_3d().direct_space_state
	if not is_instance_valid(space_state): return

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * RAY_LENGTH)
	query.collision_mask = 1 # Assume ground is on layer 1

	var result = space_state.intersect_ray(query)
	if result:
		target_pivot_point = result.position
	# else: keep the last valid target_pivot_point
