extends Node3D

# Camera control speeds and limits
@export var pan_speed: float = 15.0
@export var zoom_speed: float = 0.9 # Multiplier for zoom
@export var rotation_speed: float = 90.0 # Degrees per second

# Get reference to the actual Camera3D node
@onready var camera_3d: Camera3D = $Camera3D 

# Zoom limits (adjust based on your camera's initial Z position)
@export var min_zoom: float = 5.0
@export var max_zoom: float = 50.0

var target_pivot_point: Vector3 = Vector3.ZERO # Point on ground to orbit
const RAY_LENGTH: float = 1000.0 # How far the ray should check

func _ready():
	# Optional: Hide the mouse cursor
	# Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	# Attempt initial raycast to set starting pivot
	await get_tree().physics_frame # Wait one physics frame for physics server setup
	update_target_pivot_point()
	# If raycast missed initially (e.g., looking at sky), default to point below rig
	if target_pivot_point == Vector3.ZERO:
		target_pivot_point = global_position * Vector3(1, 0, 1)
	pass

func _process(delta):
	update_target_pivot_point() # <--- ADD THIS LINE
	handle_panning(delta)
	handle_rotation(delta)
	# Zoom is handled in _input

func handle_panning(delta):
	# Get input direction vector using project input actions
	var input_dir = Input.get_vector("pan_left", "pan_right", "pan_forward", "pan_backward")
	
	# Calculate movement direction based on camera rig's orientation
	# We use the rig's basis vectors to move relative to where the camera is facing horizontally
	var direction = (transform.basis.z * input_dir.y + transform.basis.x * input_dir.x).normalized()
	
	# Apply movement
	if direction:
		# Optional: Keep camera at a fixed height or allow flying
		# direction.y = 0 # Uncomment this line to prevent moving up/down
		
		# Normalize again in case Y was changed
		# direction = direction.normalized() 

		global_translate(direction * pan_speed * delta)


# Previous functions (extends, @export vars, @onready, _ready, _process, handle_panning) remain the same...

func handle_rotation(delta):
	# Determine rotation direction based on input actions
	var rotation_dir = 0.0
	if Input.is_action_pressed("rotate_left"):
		rotation_dir += 1.0
	if Input.is_action_pressed("rotate_right"):
		rotation_dir -= 1.0
		
	# Only perform rotation if there's input	
	if rotation_dir != 0.0:
		# 1. Calculate the rotation angle for this frame
		var rotation_angle = deg_to_rad(rotation_dir * rotation_speed * delta)
		
		# 2. Use the target_pivot_point calculated by the raycast function
		#    (Ensure update_target_pivot_point() is called in _process)
		var pivot_point = target_pivot_point 
		
		# 3. Calculate the CameraRig's current position relative to the pivot point
		var relative_pos = global_position - pivot_point
		
		# 4. Rotate this relative position vector around the world's Y-axis
		#    to find where the offset should be after rotation
		var rotated_relative_pos = relative_pos.rotated(Vector3.UP, rotation_angle)
		
		# 5. Calculate the new target global position for the CameraRig
		var new_global_position = pivot_point + rotated_relative_pos
		
		# 6. Apply the calculated new position to the CameraRig
		global_position = new_global_position
		
		# 7. *** CHANGE: Instead of rotate_y, use look_at ***
		#    Make the CameraRig look back at the pivot point after its position is updated.
		#    The Vector3.UP argument prevents unwanted tilting.
		look_at(pivot_point, Vector3.UP)


func _input(event):
	
	# Handle Zooming with Mouse Wheel / Trackpad Swipe
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.is_pressed():
			# --- DEBUG ---
			var calculated_amount = 1.0 / zoom_speed
			# --- END DEBUG ---
			zoom(calculated_amount) 
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.is_pressed():
			# --- DEBUG ---
			var calculated_amount = zoom_speed
			# --- END DEBUG ---
			zoom(calculated_amount) 

	# Optional: Handle Rotation with Middle Mouse Drag
	# if event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MIDDLE:
	#	rotate_y(deg_to_rad(-event.relative.x * 0.5)) # Adjust sensitivity (0.5) as needed


func zoom(amount):
	# Adjust the camera's local Z position for zooming
	var target_z = camera_3d.position.z * amount
	# Clamp the zoom level
	camera_3d.position.z = clamp(target_z, min_zoom, max_zoom)

	# Alternative: Move camera along its local forward axis
	# var direction = camera_3d.global_transform.basis.z
	# camera_3d.global_translate(direction * zoom_speed * (1.0 if amount < 1.0 else -1.0)) # Simplified amount logic
	# Need more robust clamping if using this method

func update_target_pivot_point():
	# Get necessary nodes and viewport info
	var viewport = get_viewport()
	if not viewport: return # Exit if viewport not ready

	# Ray starts at camera position
	var ray_origin = camera_3d.global_position
	
	# Calculate ray direction from camera through the center of the viewport
	var viewport_center = viewport.get_visible_rect().size * 0.5
	var ray_direction = camera_3d.project_ray_normal(viewport_center)

	# Get physics space state for raycasting
	var space_state = get_world_3d().direct_space_state
	if not space_state: return # Exit if physics space not ready

	# Set up the raycast query
	# IMPORTANT: Make sure your Ground mesh is on physics layer 1
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * RAY_LENGTH)
	query.collision_mask = 1 # Only check against layer 1

	# Perform the raycast
	var result = space_state.intersect_ray(query)

	# If the ray hit something, update our target pivot point
	if result:
		target_pivot_point = result.position
	# Optional: If the ray *misses* (e.g., looking at the sky), we keep the last valid
	# target_pivot_point, so the orbit continues around the last known ground position.
