# StudentManager.gd
# Manages the lifecycle of student instances, including spawning,
# providing necessary references, and triggering academic and needs updates.
extends Node

# --- Exported Variables (Set in Godot Editor Inspector) ---
# Scene for individual students.
@export var student_scene: PackedScene 
# Maximum number of students allowed in the simulation.
@export var max_students: int = 10
# Interval in seconds between attempts to spawn new students.
@export var spawn_interval: float = 5.0
# Reference to the UniversityData node in the scene.
@export var university_data_node: UniversityData 

# --- Internal Variables ---
# Timer for periodically spawning students.
var student_spawn_timer: Timer 
# Array to keep track of all active student instances.
var student_instances: Array[Node] = [] 
# Reference to the BuildingManager node (or main game controller).
var building_manager_node: Node 
# Reference to the NavigationRegion3D node for pathfinding.
var navigation_region_node: NavigationRegion3D
# Effective Y-coordinate for ground level, used for spawning and navigation queries.
var effective_ground_y: float = 2.4 
# Flag indicating if the initial NavMesh bake has completed.
var _initial_navmesh_ready: bool = false


func _ready():
	# Initialize the student spawn timer.
	student_spawn_timer = Timer.new()
	student_spawn_timer.name = "StudentSpawnTimerInternal" # For easier identification in remote inspector.
	add_child(student_spawn_timer) # Add timer to the scene tree to make it active.

	print_debug("StudentManager _ready() called.")

	# Critical check: Student scene must be assigned.
	if not student_scene:
		printerr("StudentManager: Student scene not assigned in the Inspector! StudentManager will not function correctly.")
		return # Stop further initialization if student scene is missing.

	# Critical check: UniversityData node must be assigned.
	if not is_instance_valid(university_data_node):
		printerr("StudentManager: CRITICAL - UniversityData node not assigned in the Inspector! Academic features will fail.")
	else:
		print_debug("StudentManager: UniversityData node reference is SET.")

	# Attempt to find the BuildingManager node.
	building_manager_node = get_tree().root.get_node_or_null("BuildingManager") 
	if not building_manager_node:
		building_manager_node = get_parent() # Fallback: try parent if StudentManager is a child.
		if not building_manager_node or not (building_manager_node.name == "BuildingManager" or building_manager_node.is_in_group("BuildingManager")):
			printerr("StudentManager: Could not find BuildingManager node. Ensure it's named 'BuildingManager' or in that group, or adjust path.")
		elif building_manager_node:
			print_debug("StudentManager: Found BuildingManager node.")

	# Get references and constants from BuildingManager if available.
	if building_manager_node:
		if building_manager_node.has_method("get_navigation_region"):
			navigation_region_node = building_manager_node.get_navigation_region()
		
		if "EFFECTIVE_GROUND_NAVMESH_Y_FOR_REFERENCE" in building_manager_node:
			effective_ground_y = building_manager_node.EFFECTIVE_GROUND_NAVMESH_Y_FOR_REFERENCE
		else:
			printerr("StudentManager: BuildingManager is missing 'EFFECTIVE_GROUND_NAVMESH_Y_FOR_REFERENCE'. Using default Y: " + str(effective_ground_y))
	else:
		printerr("StudentManager: BuildingManager node not found. Using default Y for ground reference: " + str(effective_ground_y))
	
	if not navigation_region_node:
		print_debug("StudentManager: NavigationRegion3D not found/set initially. It should be available before students need to navigate.")
	
	# Configure and connect the student spawn timer.
	student_spawn_timer.wait_time = spawn_interval
	student_spawn_timer.timeout.connect(_on_student_spawn_timer_timeout)
		
	print_debug("StudentManager fully initialized. Waiting for NavMesh signal from BuildingManager to start spawning students.")


# Called by BuildingManager after the initial NavMesh bake is complete.
func on_initial_navmesh_baked():
	print_debug("StudentManager: Received initial NavMesh baked signal.")
	if not is_instance_valid(student_spawn_timer):
		printerr("StudentManager: CRITICAL - student_spawn_timer is null or invalid in on_initial_navmesh_baked! Cannot start timer.")
		return

	_initial_navmesh_ready = true # Mark NavMesh as ready.
	
	# Ensure NavigationRegion reference is up-to-date if it wasn't available during _ready.
	if not navigation_region_node and building_manager_node and building_manager_node.has_method("get_navigation_region"):
		navigation_region_node = building_manager_node.get_navigation_region()
		if not navigation_region_node:
			printerr("StudentManager: NavMesh baked, but still couldn't get NavigationRegion from BuildingManager. Student navigation might fail.")
	
	# Start spawning students if conditions are met.
	if student_instances.is_empty() and max_students > 0 : 
		print_debug("StudentManager: Starting student_spawn_timer for initial student spawn.")
		student_spawn_timer.start()
		_on_student_spawn_timer_timeout() # Attempt to spawn one student immediately.
	elif is_instance_valid(student_spawn_timer) and student_spawn_timer.is_stopped() and student_instances.size() < max_students :
		print_debug("StudentManager: Starting student_spawn_timer (timer was previously stopped and students are below max).")
		student_spawn_timer.start()


# Called by the student_spawn_timer when its interval elapses.
func _on_student_spawn_timer_timeout():
	if not _initial_navmesh_ready:
		#print_debug("StudentManager: NavMesh not ready yet (timer timeout), deferring student spawn.") # Can be verbose
		return
	if not navigation_region_node:
		#print_debug("StudentManager: NavigationRegion not available (timer timeout), cannot find spawn points.") # Can be verbose
		return 
	
	if not is_instance_valid(university_data_node):
		printerr("StudentManager: UniversityData node not available (timer timeout). Cannot spawn student with academic info.")
		return
		
	# Spawn a new student if below the maximum limit.
	if student_instances.size() < max_students and student_scene:
		spawn_student()

# Handles the instantiation and setup of a new student.
func spawn_student():
	# Pre-condition checks.
	if not student_scene:
		printerr("StudentManager: student_scene is not set (spawn_student). Cannot spawn.")
		return
	if not navigation_region_node or \
	   not navigation_region_node.navigation_mesh or \
	   not NavigationServer3D.map_is_active(navigation_region_node.get_navigation_map()):
		#print_debug("StudentManager: Cannot spawn student, navigation map not ready or NavRegion not set (spawn_student).") # Can be verbose
		return
	if not is_instance_valid(university_data_node):
		printerr("StudentManager: UniversityData node not accessible right before spawning student! Aborting spawn.")
		return

	# Instantiate the student scene.
	var student_node_instance = student_scene.instantiate() 
	if not student_node_instance is CharacterBody3D: # Ensure it's the expected type.
		printerr("StudentManager: Spawned student is not a CharacterBody3D! Check student.tscn root node type.")
		if is_instance_valid(student_node_instance): student_node_instance.queue_free() # Clean up.
		return
	
	# Get academic info from UniversityData.
	var new_student_name = university_data_node.generate_random_student_name() 
	var random_program_id = university_data_node.get_random_program_id() 

	if random_program_id == "":
		printerr("StudentManager: Could not get a random program ID for new student. Student will have no program.")
	
	# Set up the student with academic and navigation references.
	if student_node_instance.has_method("set_academic_info"):
		student_node_instance.set_academic_info(new_student_name, random_program_id, university_data_node)
	else:
		print_debug("StudentManager: Spawned student instance is missing 'set_academic_info' method.")
		
	if student_node_instance.has_method("set_navigation_references"):
		student_node_instance.set_navigation_references(navigation_region_node, effective_ground_y)
	else:
		print_debug("StudentManager: Spawned student instance is missing 'set_navigation_references' method.")

	# Find a valid spawn position on the NavMesh.
	var spawn_pos = _get_random_navigable_point() 
	if spawn_pos == Vector3.INF: # Vector3.INF indicates failure to find a point.
		print_debug("StudentManager: Failed to find valid spawn point on NavMesh. Spawning at world origin as fallback.")
		spawn_pos = Vector3(0, effective_ground_y + 0.5, 0) # Fallback spawn position.
	
	student_node_instance.global_position = spawn_pos # Set student's position.
	
	add_child(student_node_instance) # Add student to the StudentManager node in the scene tree.
	student_instances.append(student_node_instance) # Add to the list of active students.
	# print_debug("StudentManager: Spawned student '" + new_student_name + "' (Program: " + random_program_id + ") at " + str(spawn_pos)) # Can be verbose


# Helper function to find a random navigable point on the NavMesh.
func _get_random_navigable_point() -> Vector3:
	if not navigation_region_node: 
		printerr("StudentManager: _get_random_navigable_point - navigation_region_node is null.")
		return Vector3.INF
	var nav_map_rid = navigation_region_node.get_navigation_map()
	if not NavigationServer3D.map_is_active(nav_map_rid): 
		printerr("StudentManager: _get_random_navigable_point - nav_map is not active.")
		return Vector3.INF

	# Try several times to find a point.
	for _i in range(10): 
		var random_x = randf_range(-40.0, 40.0) # Adjust these ranges based on your map size.
		var random_z = randf_range(-40.0, 40.0)
		var query_point = Vector3(random_x, effective_ground_y, random_z) 
		var closest_nav_point = NavigationServer3D.map_get_closest_point(nav_map_rid, query_point)
		
		if closest_nav_point == Vector3.ZERO and query_point.length_squared() > 1.0:
			continue # Try again.
		return closest_nav_point # Valid point found.
	
	# printerr("StudentManager: _get_random_navigable_point failed to find a point after 10 tries.") # Can be verbose
	return Vector3.INF # Indicate failure.

# Removes all student instances from the game.
func clear_all_students():
	print_debug("StudentManager: Clearing all " + str(student_instances.size()) + " students.")
	for student_node_inst in student_instances: 
		if is_instance_valid(student_node_inst):
			student_node_inst.queue_free() # Remove from scene and memory.
	student_instances.clear() # Clear the list.
	if is_instance_valid(student_spawn_timer): 
		student_spawn_timer.stop() # Stop spawning new students.

# Returns an array of all currently active and valid student nodes.
func get_all_student_nodes() -> Array[Node]:
	var valid_students: Array[Node] = []
	for student_node in student_instances:
		if is_instance_valid(student_node): 
			valid_students.append(student_node)
	student_instances = valid_students 
	return student_instances

# Iterates through all students and calls their update methods.
# This should be called periodically by a time management system (e.g., end of day/week/year).
func update_all_students_daily_activities(): 
	# print_debug("Updating daily activities for all students...") # Can be verbose if called frequently.
	for student_node in student_instances:
		if is_instance_valid(student_node):
			# CORRECTED ACCESS to is_graduated:
			if not student_node.is_graduated: # Directly access the public variable
				# Update Academic Progress (might be less frequent in a real game, e.g., per semester)
				if student_node.has_method("update_academic_progress"):
					student_node.update_academic_progress()
				else:
					printerr("StudentManager: Student node " + student_node.name + " is missing 'update_academic_progress' method.")
				
				# Update Needs and Happiness (could be called daily)
				if student_node.has_method("update_needs_and_happiness"):
					student_node.update_needs_and_happiness()
				else:
					printerr("StudentManager: Student node " + student_node.name + " is missing 'update_needs_and_happiness' method.")
		# else: # If student_node is not valid (e.g., was queue_freed but list not updated yet)
			# print_debug("StudentManager: Attempted to update an invalid student node.") # Can be verbose

# Helper function for consistent debug printing.
func print_debug(message):
	print("[StudentManager]: " + str(message))
