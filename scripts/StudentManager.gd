# StudentManager.gd
class_name StudentManager
extends Node

# --- Signals ---
signal student_spawned(student_node: Node) # Emitted when a new student NODE is temporarily created
signal student_record_updated(student_id: String) # Emitted when a student's persistent data in all_students_data is updated
signal all_students_cleared()
signal student_population_changed(new_count: int) # Emitted when the number of students in all_students_data changes

# --- Node & Scene References (Assign in Editor or find in _ready) ---
@export var student_scene: PackedScene
@export var university_data_node: UniversityData
@export var academic_manager_node: AcademicManager
@export var time_manager_node: TimeManager
# @export var building_manager_node: BuildingManager # Only if SM directly needs it; usually AM has a ref
@export var spawn_area_nodes: Array[Node3D]

# --- Student Data Management ---
# This dictionary stores persistent data for ALL students, keyed by student_id.
# Each value is a dictionary holding information like name, program, course enrollments,
# degree progression summary, etc. This data persists even if the student's visual node is freed.
var all_students_data: Dictionary = {}

# This dictionary temporarily caches active Student NODES in the scene tree, keyed by student_id.
# It's used by systems that need direct node interaction (e.g., AcademicManager before queue_free).
var active_student_nodes_cache: Dictionary = {}

var student_id_counter: int = 0
var academic_year_enrollment_done: Dictionary = {} # Tracks if fall enrollment is done for a given calendar year

const BASE_STUDENT_DEMAND_PER_YEAR = 15 # Configurable base new student intake

# --- Debugging ---
const DETAILED_LOGGING_ENABLED: bool = true


func _ready():
	print_debug("_ready() called.")
	if not student_scene:
		printerr("CRITICAL - Student Scene not assigned in StudentManager! Cannot spawn students.")
		get_tree().quit(); return

	# Fallbacks for essential node references
	if not is_instance_valid(university_data_node):
		university_data_node = get_node_or_null("/root/MainScene/UniversityDataNode") # Adjust path
	if not is_instance_valid(university_data_node): printerr("CRITICAL - UniversityDataNode not found!")

	if not is_instance_valid(academic_manager_node):
		academic_manager_node = get_node_or_null("/root/MainScene/AcademicManager") # Adjust path
	if not is_instance_valid(academic_manager_node): printerr("CRITICAL - AcademicManager node not found!")

	if not is_instance_valid(time_manager_node):
		time_manager_node = get_node_or_null("/root/MainScene/TimeManager") # Adjust path
	if not is_instance_valid(time_manager_node):
		printerr("CRITICAL - TimeManager node not found!")
	else:
		if time_manager_node.has_signal("fall_semester_starts"):
			if not time_manager_node.is_connected("fall_semester_starts", Callable(self, "handle_fall_enrollment")):
				var err_fall_enroll = time_manager_node.connect("fall_semester_starts", Callable(self, "handle_fall_enrollment"))
				if err_fall_enroll == OK: print_debug("Connected to TimeManager.fall_semester_starts.")
				else: printerr("FAILED to connect to TimeManager.fall_semester_starts. Error: %s" % err_fall_enroll)
		else: print_debug("TimeManager missing 'fall_semester_starts' signal.")

		if time_manager_node.has_signal("new_year_started"):
			if not time_manager_node.is_connected("new_year_started", Callable(self, "_on_new_game_year_started")):
				time_manager_node.new_year_started.connect(Callable(self, "_on_new_game_year_started"))
		else: print_debug("TimeManager missing 'new_year_started' signal.")
	
	print_debug("StudentManager fully initialized.")


func _on_new_game_year_started(year: int):
	print_debug("New game year %d. Resetting fall enrollment tracker." % year)
	academic_year_enrollment_done[year] = false


func handle_fall_enrollment(current_game_year: int): # Renamed for clarity
	print_debug("handle_fall_enrollment CALLED for game year: %d." % current_game_year)
	if not (is_instance_valid(academic_manager_node) and is_instance_valid(university_data_node)):
		printerr("Missing critical manager references for enrollment.")
		return
	if academic_year_enrollment_done.get(current_game_year, false):
		print_debug("Fall enrollment for year %d already completed. Skipping." % current_game_year)
		return

	var building_manager_ref = get_node_or_null("/root/MainScene/BuildingManager") # Adjust path if needed for reputation
	var reputation = 50.0 # Default if BM not found
	if is_instance_valid(building_manager_ref) and building_manager_ref.has_method("get_university_reputation"):
		reputation = building_manager_ref.get_university_reputation()

	var demand_multiplier = 1.0 + (reputation / 100.0) * 2.0
	var student_demand = floori(float(BASE_STUDENT_DEMAND_PER_YEAR) * demand_multiplier)
	student_demand = maxi(student_demand, 0)
	var enrollment_capacity = academic_manager_node.calculate_new_student_intake_capacity()
	var num_new_students_to_admit = mini(student_demand, enrollment_capacity)

	print_debug("--- Fall Enrollment Process (Year %d) ---" % current_game_year)
	print_debug("Reputation: %.1f/100" % reputation)
	print_debug("Calculated Student Demand: %d" % student_demand)
	print_debug("University Intake Capacity: %d seats" % enrollment_capacity)
	print_debug("ADMITTING: %d new students." % num_new_students_to_admit)

	if num_new_students_to_admit > 0:
		_spawn_and_process_new_students(num_new_students_to_admit, current_game_year)
	else:
		print_debug("No new students admitted this Fall.")
	
	academic_year_enrollment_done[current_game_year] = true
	emit_signal("student_population_changed", get_total_student_count())
	print_debug("--- Fall Enrollment Process Finished for Year %d ---" % current_game_year)


func _spawn_and_process_new_students(count: int, academic_calendar_year: int):
	if not student_scene: printerr("student_scene not set!"); return
	if not is_instance_valid(academic_manager_node): printerr("academic_manager_node not valid!"); return
	if not is_instance_valid(university_data_node): printerr("university_data_node not valid!"); return

	var unlocked_programs_ids: Array[String] = academic_manager_node.get_all_unlocked_program_ids()
	if unlocked_programs_ids.is_empty():
		print_debug("No unlocked programs. New students cannot be assigned.")
		return

	print_debug("Spawning and processing %d new students for academic calendar year %d." % [count, academic_calendar_year])

	for i in range(count):
		student_id_counter += 1
		var new_student_id = "stud_%d_%04d" % [academic_calendar_year, student_id_counter]
		var student_name = university_data_node.generate_random_student_name()
		var chosen_program_id = unlocked_programs_ids.pick_random()

		var student_node_instance = student_scene.instantiate() as Student
		if not is_instance_valid(student_node_instance):
			printerr("Failed to instantiate student scene for student #%d. Skipping." % (i + 1))
			continue

		# Initialize the temporary student node
		student_node_instance.initialize_new_student(
			new_student_id, student_name, chosen_program_id, academic_calendar_year,
			academic_manager_node, university_data_node, time_manager_node
			# No restored_degree_prog_summary for brand new students
		)
		
		# Create initial persistent data record in all_students_data
		var initial_data_record: Dictionary
		if student_node_instance.has_method("get_info_summary"):
			initial_data_record = student_node_instance.get_info_summary()
			if is_instance_valid(student_node_instance.degree_progression) and student_node_instance.degree_progression.has_method("get_summary"):
				initial_data_record["degree_progression_summary"] = student_node_instance.degree_progression.get_summary()
			else:
				initial_data_record["degree_progression_summary"] = {}
		else: # Basic fallback
			initial_data_record = {
				"name": student_name, "student_name": student_name, "student_id": new_student_id,
				"program_id": chosen_program_id, "program_name": "N/A",
				"current_courses_list": [], "status": "Enrolled",
				"credits_earned": 0.0, "credits_needed_for_program": 0.0,
				"degree_progression_summary": { # Populate with defaults for DegreeProgression
					"student_id": new_student_id, "program_id": chosen_program_id,
					"current_academic_year": 1, "current_semester": 1,
					"total_credits_earned": 0.0, "is_graduated": false, "course_records": {}
				}
			}
		all_students_data[new_student_id] = initial_data_record
		active_student_nodes_cache[new_student_id] = student_node_instance

		# Connect to this specific student's despawn signal to update our persistent record
		if student_node_instance.has_signal("student_despawn_data_for_manager"):
			if not student_node_instance.is_connected("student_despawn_data_for_manager", Callable(self, "_on_student_node_data_update_requested")):
				student_node_instance.student_despawn_data_for_manager.connect(Callable(self, "_on_student_node_data_update_requested"))
		else:
			printerr("Student scene is missing 'student_despawn_data_for_manager' signal!")


		var student_parent_node = get_parent().get_node_or_null("Students") # Assumes "Students" is sibling of StudentManager
		if not is_instance_valid(student_parent_node):
			printerr("Could not find 'Students' node as parent for student %s. Spawning aborted." % new_student_id)
			student_node_instance.queue_free()
			all_students_data.erase(new_student_id) # Clean up record
			active_student_nodes_cache.erase(new_student_id)
			continue
		
		var spawn_position = Vector3(randf_range(-10, 10), 0.3, randf_range(-10, 10)) # Default spawn
		if spawn_area_nodes and not spawn_area_nodes.is_empty():
			var random_spawn_area_node = spawn_area_nodes.pick_random() as Node3D
			if is_instance_valid(random_spawn_area_node): spawn_position = random_spawn_area_node.global_position
		
		student_parent_node.add_child(student_node_instance)
		student_node_instance.global_position = spawn_position
		
		print_debug("Spawned node: %s (%s), Program: %s. Initial data record created." % [student_name, new_student_id, chosen_program_id])
		emit_signal("student_spawned", student_node_instance)

		var initial_courses_for_program: Array[String] = []
		if is_instance_valid(university_data_node) and university_data_node.has_method("get_initial_curriculum_courses"):
			initial_courses_for_program = university_data_node.get_initial_curriculum_courses(chosen_program_id)
		
		if initial_courses_for_program.is_empty():
			print_debug("Warning - No INITIAL curriculum courses for program '%s'. Student '%s' not auto-enrolled." % [chosen_program_id, new_student_id])
		
		var courses_successfully_enrolled_count = 0
		for course_id_str_to_enroll in initial_courses_for_program:
			var enrolled_in_offering_id = academic_manager_node.find_and_enroll_student_in_offering(new_student_id, course_id_str_to_enroll)
			if not enrolled_in_offering_id.is_empty():
				if student_node_instance.has_method("confirm_course_enrollment"):
					var full_offering_details = academic_manager_node.get_offering_details(enrolled_in_offering_id)
					if not full_offering_details.is_empty():
						student_node_instance.confirm_course_enrollment(enrolled_in_offering_id, full_offering_details)
						courses_successfully_enrolled_count +=1
		
		print_debug("Student '%s' processed for enrollment in %d initial courses." % [new_student_id, courses_successfully_enrolled_count])
		
		if student_node_instance.has_method("on_fully_spawned_and_enrolled"):
			student_node_instance.on_fully_spawned_and_enrolled()

	print_debug("Finished spawning batch of %d new students." % count)

# Called when a Student node emits its data before being (typically) hidden/disabled
func _on_student_node_data_update_requested(data_from_student: Dictionary):
	var s_id = data_from_student.get("student_id")
	if s_id == null: # Check for null s_id
		printerr("StudentManager: Received student data update request with null student_id.")
		return

	if all_students_data.has(s_id):
		# Merge/Update the persistent record with the latest data from the node
		all_students_data[s_id] = data_from_student.duplicate(true) # Store a copy
		
		# IMPORTANT CHANGE: Do NOT remove from active_student_nodes_cache if the student node
		# is just being disabled for in-building simulation and will be re-used.
		# Only remove it from the cache if StudentManager is explicitly freeing the node
		# (e.g., in a new `remove_student_and_free_node` function for graduation).
		# if active_student_nodes_cache.has(s_id):
		# 	 active_student_nodes_cache.erase(s_id) # KEEP THIS COMMENTED OUT for re-use strategy

		emit_signal("student_record_updated", s_id)
		if DETAILED_LOGGING_ENABLED: print_debug("Updated persistent data record for student %s. Node remains cached if active/disabled." % s_id)
	elif DETAILED_LOGGING_ENABLED:
		# This case might occur if a student is being removed entirely (e.g. graduated) and their persistent record was already handled.
		print_debug("StudentManager: Received despawn data for student ID %s, but no persistent record found in all_students_data. This might be normal if student was fully removed." % str(s_id))

# You would then have a separate function, perhaps called by AcademicManager upon graduation:
func fully_remove_student(student_id: String):
	if active_student_nodes_cache.has(student_id):
		var node_to_free = active_student_nodes_cache[student_id]
		if is_instance_valid(node_to_free):
			node_to_free.queue_free() # Actually free the node
		active_student_nodes_cache.erase(student_id) # Now remove from cache

	if all_students_data.has(student_id):
		all_students_data.erase(student_id)
		emit_signal("student_population_changed", get_total_student_count())
	
	if DETAILED_LOGGING_ENABLED: print_debug("Fully removed student (node and data) for ID: %s" % student_id)

# StudentManager.gd
func get_all_student_info_for_ui() -> Array[Dictionary]:
	var ui_student_list: Array[Dictionary] = []
	if DETAILED_LOGGING_ENABLED:
		print_debug("get_all_student_info_for_ui: Starting. Total records in all_students_data: %d" % all_students_data.size())
		if all_students_data.size() < 5 and not all_students_data.is_empty(): # Log first few records if list is small
			print_debug("First few records in all_students_data: " + str(all_students_data))


	for student_id in all_students_data: # Iterates through keys of the dictionary
		var student_data_record: Dictionary = all_students_data[student_id] # Get the data dictionary
		
		if not student_data_record is Dictionary or student_data_record.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug("get_all_student_info_for_ui: Skipping empty or invalid record for student_id: " + str(student_id))
			continue

		# Construct the summary dictionary expected by StudentListItem
		var program_name_str = student_data_record.get("program_name", "N/A_Prog") # Check if program_name is already in the record
		var prog_id = student_data_record.get("current_program_id", student_data_record.get("program_id"))

		if program_name_str == "N/A_Prog" and is_instance_valid(university_data_node) and prog_id and not str(prog_id).is_empty():
			var prog_details = university_data_node.get_program_details(str(prog_id))
			program_name_str = prog_details.get("name", "Unknown Program")

		var course_names_list: Array[String] = student_data_record.get("current_courses_list", [])
		# If current_courses_list is not directly in student_data_record, you might need to build it
		# from student_data_record.get("current_course_enrollments", {}) as done previously.
		# For simplicity, assuming current_courses_list is directly available or accurately prepared
		# when the record in all_students_data is created/updated.

		var student_status = student_data_record.get("status", "Enrolled")
		var credits_e = 0.0
		var credits_n = 0.0
		
		# Use the 'degree_progression_summary' nested dictionary
		var deg_prog_summary = student_data_record.get("degree_progression_summary", {})
		if not deg_prog_summary.is_empty():
			credits_e = deg_prog_summary.get("total_credits_earned", 0.0)
			var actual_program_id_for_credits = deg_prog_summary.get("program_id", prog_id) # Use program_id from degree summary if available
			if is_instance_valid(university_data_node) and actual_program_id_for_credits and not str(actual_program_id_for_credits).is_empty():
				var pd = university_data_node.get_program_details(str(actual_program_id_for_credits))
				credits_n = pd.get("credits_to_graduate", 0.0)
			if deg_prog_summary.get("is_graduated", false):
				student_status = "Graduated!"
		
		var ui_summary_entry = {
			"name": student_data_record.get("student_name", student_data_record.get("name", "N/A Name")),
			"program_name": program_name_str,
			"current_courses_list": course_names_list,
			"status": student_status,
			"credits_earned": credits_e,
			"credits_needed_for_program": credits_n,
			"student_id": student_id
		}
		ui_student_list.append(ui_summary_entry)
		if DETAILED_LOGGING_ENABLED and ui_student_list.size() <= 3: # Log first few constructed summaries
			print_debug("get_all_student_info_for_ui: Constructed UI summary for %s: %s" % [student_id, str(ui_summary_entry)])
			
	if DETAILED_LOGGING_ENABLED:
		print_debug("get_all_student_info_for_ui: COMPLETED. Returning %d student summaries for UI." % ui_student_list.size())
	return ui_student_list

# Returns the actual Student node if it's currently active in the scene
func get_student_node_by_id(s_id: String) -> Student: # Renamed for clarity
	if active_student_nodes_cache.has(s_id):
		var node = active_student_nodes_cache[s_id]
		if is_instance_valid(node):
			return node as Student
		else:
			active_student_nodes_cache.erase(s_id) # Clean up stale reference
			if DETAILED_LOGGING_ENABLED: print_debug("Cleaned stale node from active_student_nodes_cache for: %s" % s_id)
	return null

# Returns the persistent data dictionary for a student
func get_student_persistent_data(s_id: String) -> Dictionary:
	return all_students_data.get(s_id, {}).duplicate(true) # Return a copy

func get_total_student_count() -> int:
	return all_students_data.size()

func clear_all_students():
	for s_id in active_student_nodes_cache:
		var student_node = active_student_nodes_cache[s_id]
		if is_instance_valid(student_node):
			student_node.queue_free()
	active_student_nodes_cache.clear()
	
	all_students_data.clear()
	student_id_counter = 0
	academic_year_enrollment_done.clear()
	emit_signal("all_students_cleared")
	emit_signal("student_population_changed", 0)
	print_debug("All students cleared (active nodes and persistent data).")

func print_debug(message_parts):
	var final_message = "[StudentManager]: "
	if typeof(message_parts) == TYPE_STRING:
		final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY:
		var string_array : Array[String] = []
		for item in message_parts: string_array.append(str(item))
		final_message += " ".join(string_array)
	else:
		final_message += str(message_parts)
	print(final_message)
