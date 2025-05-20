# StudentManager.gd
# Manages student population, spawning, and initial enrollment into programs and courses.
class_name StudentManager
extends Node

signal student_spawned(student_node: Node)
signal all_students_cleared()
signal student_population_changed(new_count: int) # <<< NEW SIGNAL TO ADD at the top with other signals

# --- Node & Scene References (Assign in Editor) ---
@export var student_scene: PackedScene # Your Student.tscn
@export var university_data_node: UniversityData
@export var academic_manager_node: AcademicManager
@export var building_manager_node: BuildingManager
@export var time_manager_node: TimeManager
@export var navigation_region_node: NavigationRegion3D # For student pathfinding setup
@export var spawn_area_nodes: Array[Node3D] # Optional: Define areas where new students appear

# --- Student Management ---
var student_list: Dictionary = {} # Key: student_id (String), Value: student_node (Student)
var student_id_counter: int = 0   # For generating unique student IDs

# --- Enrollment Logic ---
const BASE_STUDENT_DEMAND_PER_YEAR = 15 # Configurable: Base number of applicants if reputation is minimal
var academic_year_enrollment_done: Dictionary = {} # Key: year (int), Value: bool (true if September intake done for that year)

var initial_navmesh_setup_done = false # To ensure NavMesh dependent setup happens once

func _ready():
	print_debug("_ready() called.")
	if not student_scene:
		printerr("CRITICAL - Student Scene not assigned in StudentManager! Cannot spawn students.")
		get_tree().quit(); return # Cannot function without student scene

	# Fallbacks for essential node references if not assigned in editor
	if not is_instance_valid(university_data_node):
		university_data_node = get_node_or_null("/root/MainScene/UniversityDataNode") # Adjust if your node name is different
	if is_instance_valid(university_data_node): print_debug("UniversityData node reference is SET.")
	else: printerr("CRITICAL - UniversityData node not found!")

	if not is_instance_valid(academic_manager_node):
		academic_manager_node = get_node_or_null("/root/MainScene/AcademicManager")
	if not is_instance_valid(academic_manager_node): printerr("CRITICAL - AcademicManager node not found!")
	
	if not is_instance_valid(building_manager_node):
		building_manager_node = get_node_or_null("/root/MainScene/BuildingManager")
	if not is_instance_valid(building_manager_node): printerr("CRITICAL - BuildingManager node not found!")
	
	if not is_instance_valid(time_manager_node):
		time_manager_node = get_node_or_null("/root/MainScene/TimeManager")
	if not is_instance_valid(time_manager_node): 
		printerr("CRITICAL - TimeManager node not found!")
	else: # Connect to TimeManager signals for enrollment cycle
		if time_manager_node.has_signal("september_enrollment_starts") and \
		   not time_manager_node.is_connected("september_enrollment_starts", Callable(self, "handle_september_enrollment")):
			var err_s = time_manager_node.connect("september_enrollment_starts", Callable(self, "handle_september_enrollment"))
			if err_s == OK: print_debug("Connected to TimeManager.september_enrollment_starts.")
			else: printerr("Failed to connect to september_enrollment_starts. Error: %s" % err_s)
		
		if time_manager_node.has_signal("new_year_started") and \
		   not time_manager_node.is_connected("new_year_started", Callable(self, "_on_new_game_year_started")):
			var err_y = time_manager_node.connect("new_year_started", Callable(self, "_on_new_game_year_started"))
			if err_y == OK: print_debug("Connected to TimeManager.new_year_started for enrollment flag reset.")
			else: printerr("Failed to connect to new_year_started. Error: %s" % err_y)
			
	if not is_instance_valid(navigation_region_node):
		navigation_region_node = get_node_or_null("/root/MainScene/NavigationRegion3D") # Attempt common path
		if not is_instance_valid(navigation_region_node):
			print_debug("NavigationRegion3D not found/set initially. Students may not navigate until it's available (e.g., after NavMesh bake).")
	
	print_debug("StudentManager fully initialized. Awaiting NavMesh and enrollment triggers.")


# Called by BuildingManager after the initial NavMesh bake is complete.
func on_initial_navmesh_baked():
	if initial_navmesh_setup_done : return # Run only once
	print_debug("Received initial NavMesh baked signal from BuildingManager.")
	
	if not is_instance_valid(navigation_region_node) and is_instance_valid(building_manager_node):
		if building_manager_node.has_method("get_navigation_region"):
			navigation_region_node = building_manager_node.get_navigation_region()
			print_debug("NavigationRegion obtained from BuildingManager.")
	
	if is_instance_valid(navigation_region_node):
		print_debug("NavigationRegion is now confirmed available for students.")
		# No automatic student spawn here anymore; new student intake is handled by September enrollment.
	else:
		printerr("NavMesh baked, but StudentManager still does not have a valid NavigationRegion reference!")
	initial_navmesh_setup_done = true


# Connected to TimeManager.new_year_started (assumed Jan 1st)
func _on_new_game_year_started(year: int):
	print_debug("New game year %d has begun (Jan 1st). Resetting September enrollment tracker for this year." % year)
	# academic_year_enrollment_done.erase(year - 1) # Optional: Clean up entry for the year that just passed
	academic_year_enrollment_done[year] = false # Mark that for this *new calendar year*, September enrollment hasn't happened


# Connected to TimeManager.september_enrollment_starts
func handle_september_enrollment(current_game_year: int):
	print_debug("Handling September enrollment for game year: ", current_game_year) # Ensure you have print_debug or use print()
	if not (is_instance_valid(building_manager_node) and \
			is_instance_valid(academic_manager_node) and \
			is_instance_valid(university_data_node)):
		printerr("StudentManager: Missing critical manager references for enrollment.")
		return
	
	if academic_year_enrollment_done.get(current_game_year, false) == true:
		print_debug("September enrollment for year %d already completed. Skipping." % current_game_year)
		return

	# 1. Update and Get University Reputation (existing logic)
	if building_manager_node.has_method("update_reputation_and_ui"):
		building_manager_node.update_reputation_and_ui() 
	var reputation = building_manager_node.get_university_reputation()

	# 2. Calculate Student Demand (existing logic)
	var demand_multiplier = 1.0 + (reputation / 100.0) * 2.0 
	var student_demand = floori(float(BASE_STUDENT_DEMAND_PER_YEAR) * demand_multiplier)
	student_demand = maxi(student_demand, 0) # Changed from 5 to 0 for cases with no capacity/demand

	# 3. Calculate University Capacity (existing logic)
	var enrollment_capacity = academic_manager_node.calculate_new_student_intake_capacity()

	# 4. Determine Number of New Students (existing logic)
	var num_new_students_to_admit = mini(student_demand, enrollment_capacity)

	print_debug("--- September Enrollment Process (Year %d) ---" % current_game_year)
	print_debug("Reputation: %.1f/100" % reputation)
	print_debug("Calculated Student Demand: %d" % student_demand)
	print_debug("University Intake Capacity: %d seats" % enrollment_capacity)
	print_debug("ADMITTING: %d new students." % num_new_students_to_admit)

	if num_new_students_to_admit > 0:
		_spawn_and_process_new_students(num_new_students_to_admit, current_game_year) # Existing function
	else:
		print_debug("No new students admitted this September.")
	
	academic_year_enrollment_done[current_game_year] = true
	emit_signal("student_population_changed", get_total_student_count()) # <<< ADD THIS LINE
	print_debug("--- September Enrollment Process Finished for Year %d ---" % current_game_year)


func _spawn_and_process_new_students(count: int, academic_year: int):
	if not is_instance_valid(academic_manager_node) or not is_instance_valid(university_data_node):
		printerr("Cannot spawn students: AcademicManager or UniversityData not available.")
		return

	var unlocked_programs_ids: Array[String] = academic_manager_node.get_all_unlocked_program_ids()
	if unlocked_programs_ids.is_empty():
		print_debug("No unlocked programs available. New students cannot be assigned to a program.")
		return

	print_debug("Spawning and processing %d new students for academic year %d." % [count, academic_year])
	for i in range(count):
		student_id_counter += 1
		var new_student_id = "stud_%d_%03d" % [academic_year, student_id_counter] # e.g., stud_2025_001
		var student_name = university_data_node.generate_random_student_name()
		var chosen_program_id = unlocked_programs_ids.pick_random() # Randomly assign to an unlocked program

		var student_node_instance = student_scene.instantiate() as Student # Cast to your Student class
		if not is_instance_valid(student_node_instance):
			printerr("Failed to instantiate student scene for student #%d. Skipping." % (i + 1))
			continue

		# Initialize student's academic and personal data
		# Pass manager references if student needs them for complex behaviors later
		if student_node_instance.has_method("initialize_new_student"):
			student_node_instance.initialize_new_student(new_student_id, student_name, chosen_program_id, academic_year, academic_manager_node, university_data_node, time_manager_node)
		else: # Fallback if a comprehensive init method is missing
			printerr("Student script for %s missing 'initialize_new_student' method. Attempting partial setup." % new_student_id)
			student_node_instance.student_id = new_student_id
			student_node_instance.student_name = student_name
			student_node_instance.name = "Student_%s" % new_student_id # Set Node name
			if student_node_instance.has_method("assign_program"): student_node_instance.assign_program(chosen_program_id, academic_year)


		# Physical spawn - find a spawn point
		var spawn_position = Vector3.ZERO
		if spawn_area_nodes and not spawn_area_nodes.is_empty():
			var random_spawn_area_node = spawn_area_nodes.pick_random() as Node3D
			if is_instance_valid(random_spawn_area_node):
				# For a more distributed spawn, you might get bounds of a CSGBox or Area3D
				spawn_position = random_spawn_area_node.global_position 
		else: # Fallback spawn position if no areas defined
			spawn_position = Vector3(randf_range(-10, 10), 0.3, randf_range(-10, 10)) # Example random pos

		add_child(student_node_instance) # Add to StudentManager node in scene tree
		student_node_instance.global_position = spawn_position
		
		student_list[new_student_id] = student_node_instance # Track student
		print_debug("Spawned: %s (%s), Program: %s, at %s" % [student_name, new_student_id, chosen_program_id, spawn_position])
		emit_signal("student_spawned", student_node_instance)

		# Enroll student in their first semester courses for the chosen program
		var first_semester_course_ids: Array[String] = academic_manager_node.get_freshman_first_semester_courses(chosen_program_id)
		if first_semester_course_ids.is_empty():
			print_debug("Warning: No Freshman/First Semester courses defined in curriculum for program '%s'. Student '%s' will not be enrolled in initial courses automatically." % [chosen_program_id, new_student_id])
		
		var courses_successfully_enrolled_count = 0
		for course_id_str_to_enroll in first_semester_course_ids:
			# AcademicManager tries to find an offering and enroll the student
			var enrolled_in_offering_id = academic_manager_node.find_and_enroll_student_in_offering(new_student_id, course_id_str_to_enroll)
			
			if not enrolled_in_offering_id.is_empty():
				# Notify the student instance about this enrollment for its internal tracking
				if student_node_instance.has_method("confirm_course_enrollment"):
					var full_offering_details = academic_manager_node.get_offering_details(enrolled_in_offering_id)
					if not full_offering_details.is_empty():
						student_node_instance.confirm_course_enrollment(enrolled_in_offering_id, full_offering_details)
						courses_successfully_enrolled_count +=1
					else:
						printerr("Could not get full details for offering '%s' to confirm with student '%s'." % [enrolled_in_offering_id, new_student_id])
				else:
					printerr("Student instance '%s' lacks 'confirm_course_enrollment' method." % new_student_id)
			else: # Failed to enroll in this specific required course
				printerr("CRITICAL FAILURE: Student '%s' could NOT be enrolled in required Freshman course '%s' for program '%s'. University capacity/scheduling issue!" % [new_student_id, course_id_str_to_enroll, chosen_program_id])
				# This is a major issue: indicates not enough scheduled offerings or space.
		
		print_debug("Student '%s' processed for enrollment in %d first-semester courses for program '%s'." % [new_student_id, courses_successfully_enrolled_count, chosen_program_id])
		
		# Trigger any final student setup that depends on being in the scene tree
		if student_node_instance.has_method("on_fully_spawned_and_enrolled"):
			student_node_instance.on_fully_spawned_and_enrolled()


# --- Helper Functions ---
func get_all_student_nodes() -> Array[Node]: # Used by BuildingManager for roster UI
	var nodes_array: Array[Node] = []
	for student_node in student_list.values(): # student_list values are the student nodes
		if is_instance_valid(student_node): # Ensure node hasn't been freed
			nodes_array.append(student_node)
	return nodes_array

# NEW FUNCTION to get total student count
func get_total_student_count() -> int:
	return student_list.size()
	
func get_student_by_id(s_id: String) -> Student: # Return type Student
	if student_list.has(s_id):
		return student_list[s_id] as Student # Cast to Student
	return null

func clear_all_students(): 
	print_debug("Clearing all students...")
	for s_id in student_list.keys(): 
		var student_node_to_remove = student_list[s_id]
		if is_instance_valid(student_node_to_remove):
			student_node_to_remove.queue_free()
	student_list.clear()
	student_id_counter = 0 
	academic_year_enrollment_done.clear() 
	emit_signal("all_students_cleared") # If you have this signal
	emit_signal("student_population_changed", 0) # <<< ADD THIS LINE (or get_total_student_count())
	print_debug("All students cleared and counters reset.")

# --- Daily Updates (Example, if StudentManager coordinates this) ---
func update_all_students_daily_activities(): # Called by BuildingManager on new day
	# print_debug("Updating daily activities for all students...")
	for student_node_val in student_list.values():
		if is_instance_valid(student_node_val) and student_node_val.has_method("process_daily_update"):
			student_node_val.process_daily_update()


func print_debug(message_parts):
	var final_message = "[StudentManager]: "
	if typeof(message_parts) == TYPE_STRING:
		final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY:
		var string_array : Array[String] = []
		for item in message_parts: string_array.append(str(item))
		final_message += " ".join(string_array)
	elif typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : PackedStringArray = message_parts
		final_message += " ".join(temp_array)
	else:
		final_message += str(message_parts)
	print(final_message)
