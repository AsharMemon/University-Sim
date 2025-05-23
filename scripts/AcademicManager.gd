# AcademicManager.gd
class_name AcademicManager
extends Node

signal program_unlocked(program_id: String)
signal course_offerings_updated()
# Old class_scheduled/unscheduled signals. Consider if they are still needed or if schedules_updated is enough.
signal class_scheduled(class_instance_id: String, details: Dictionary) # Retained for now
signal class_unscheduled(class_instance_id: String, details: Dictionary) # Retained for now
signal schedules_updated() # Central signal for UI refresh of timetable
signal enrollment_changed(offering_id: String, enrolled_count: int, max_capacity: int)
signal student_graduated(student_id: String, program_id: String, graduation_term: String)
# signal course_placed_pending(offering_id: String) # Can be added if specifically needed

const STUDENT_SCENE: PackedScene = preload("res://actors/student.tscn")
const DETAILED_LOGGING_ENABLED: bool = true

const ACADEMIC_MGR_STUDENT_MIN_NEED_VALUE: float = 0.0
const ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE: float = 100.0
const ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y: float = 0.3

@export var university_data: UniversityData
@export var building_manager: BuildingManager
@export var time_manager: TimeManager
@export var professor_manager: ProfessorManager # Make sure this is assigned in the editor

var program_states: Dictionary = {}
var course_offerings: Dictionary = {} # Central store for all offerings and their states/details
# { offering_id -> {
# 	"offering_id": String, "course_id": String, "course_name": String, "program_id": String,
# 	"status": "unscheduled" | "pending_professor" | "scheduled",
# 	"instructor_id": String (if scheduled),
# 	"classroom_id": String (if pending or scheduled),
# 	"primary_day": String (if pending or scheduled, e.g. "Mon" or "Tue"),
# 	"start_time_slot": String (if pending or scheduled),
# 	"pattern": String (e.g. "MWF", "TR", if pending or scheduled),
# 	"duration_slots": int (if pending or scheduled),
# 	"max_capacity": int (from classroom, if pending or scheduled),
# 	"enrolled_student_ids": Array (if pending or scheduled)
# } }
var scheduled_class_details: Dictionary = {} # Potentially redundant if course_offerings holds all, or used as a snapshot for fully scheduled ones.
										  # For now, we'll populate this when status becomes "scheduled".
var classroom_schedules: Dictionary = {} # classroom_id -> day -> time_slot -> offering_id

const DAYS_OF_WEEK: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"]
const HOURLY_TIME_SLOTS: Array[String] = [
	"0800", "0900", "1000", "1100", "1200",
	"1300", "1400", "1500", "1600", "1700"
]
const DURATION_MWF: int = 1 # Duration in slots for MWF pattern
const DURATION_TR: int = 2  # Duration in slots for TR pattern

const GRADE_PASS = "COMP"
const GRADE_FAIL = "F"
const GRADE_IN_PROGRESS = "IP"

var in_building_simulated_students: Array[Dictionary] = []
var _pending_respawn_queue: Array[Dictionary] = []
var _respawn_timer: Timer
const RESPAWN_INTERVAL: float = 0.3


func _ready():
	if not is_instance_valid(university_data):
		university_data = get_node_or_null("/root/MainScene/UniversityDataNode")
		if not is_instance_valid(university_data):
			printerr("AcademicManager: CRITICAL - UniversityData node not found!")
			get_tree().quit(); return
	
	if not is_instance_valid(building_manager):
		building_manager = get_node_or_null("/root/MainScene/BuildingManager")
		if not is_instance_valid(building_manager):
			printerr("AcademicManager: Warning - BuildingManager node not found.")

	if not is_instance_valid(time_manager):
		var time_manager_path = "/root/MainScene/TimeManager"
		time_manager = get_node_or_null(time_manager_path)
		if not is_instance_valid(time_manager):
			printerr("AcademicManager: CRITICAL - TimeManager node not found at '", time_manager_path, "'! Student simulation will not proceed.")
		else:
			if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: TimeManager found at fallback path:", time_manager_path])
			_connect_time_manager_signals()
	else:
		_connect_time_manager_signals()
		
	if not is_instance_valid(professor_manager): # Added check for ProfessorManager
		professor_manager = get_node_or_null("/root/MainScene/ProfessorManager") # Adjust path if needed
		if not is_instance_valid(professor_manager):
			printerr("AcademicManager: CRITICAL - ProfessorManager not found! Professor assignment features will be disabled.")


	_initialize_program_states()

	_respawn_timer = Timer.new()
	_respawn_timer.name = "StudentRespawnTimer"
	_respawn_timer.wait_time = RESPAWN_INTERVAL
	_respawn_timer.one_shot = false
	_respawn_timer.autostart = false
	_respawn_timer.timeout.connect(Callable(self, "_process_next_student_in_respawn_queue"))
	add_child(_respawn_timer)
	if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Respawn timer created and added to scene."])

	if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager ready."])


func _connect_time_manager_signals(): # [cite: 7]
	if is_instance_valid(time_manager):
		if time_manager.has_signal("visual_hour_slot_changed"):
			if not time_manager.is_connected("visual_hour_slot_changed", Callable(self, "_on_visual_hour_slot_changed_simulation_update")):
				var err_code_vh = time_manager.connect("visual_hour_slot_changed", Callable(self, "_on_visual_hour_slot_changed_simulation_update"))
				if err_code_vh == OK: 
					if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Connected to TimeManager's visual_hour_slot_changed."])
				else: printerr("AcademicManager: FAILED to connect visual_hour_slot_changed. Error: %s" % err_code_vh)
		else: printerr("AcademicManager: TimeManager missing 'visual_hour_slot_changed' signal.")

		if time_manager.has_signal("simulation_time_updated"):
			if not time_manager.is_connected("simulation_time_updated", Callable(self, "_on_simulation_time_ticked_for_student_checks")):
				var err_code_stu = time_manager.connect("simulation_time_updated", Callable(self, "_on_simulation_time_ticked_for_student_checks"))
				if err_code_stu == OK: 
					if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Connected to TimeManager's simulation_time_updated."]) 
				else: printerr("AcademicManager: FAILED to connect simulation_time_updated. Error: %s" % err_code_stu) 
		else: printerr("AcademicManager: TimeManager missing 'simulation_time_updated' signal.")
		
		if not time_manager.is_connected("fall_semester_starts", Callable(self, "_on_fall_semester_starts")):
			time_manager.fall_semester_starts.connect(Callable(self, "_on_fall_semester_starts"))
		if not time_manager.is_connected("spring_semester_starts", Callable(self, "_on_spring_semester_starts")):
			time_manager.spring_semester_starts.connect(Callable(self, "_on_spring_semester_starts"))
		if not time_manager.is_connected("summer_semester_starts", Callable(self, "_on_summer_semester_starts")):
			time_manager.summer_semester_starts.connect(Callable(self, "_on_summer_semester_starts"))
		
		if not time_manager.is_connected("academic_term_changed", Callable(self, "_on_academic_term_changed_for_progression")):
			time_manager.academic_term_changed.connect(Callable(self, "_on_academic_term_changed_for_progression")) 
			
	else:
		printerr("AcademicManager: Cannot connect TimeManager signals, TimeManager is not valid.")


# --- Program and Course Offering Management (Mostly as provided by user) ---
func _initialize_program_states(): # [cite: 1]
	if not is_instance_valid(university_data): return # [cite: 1]
	var all_defined_programs_dict = university_data.PROGRAMS # [cite: 1]
	for program_id_key_str in all_defined_programs_dict.keys(): # [cite: 1]
		if not program_states.has(program_id_key_str): # [cite: 1]
			program_states[program_id_key_str] = "locked" # [cite: 1]

func unlock_program(program_id: String) -> bool: # [cite: 1]
	if not is_instance_valid(university_data): # [cite: 1]
		printerr("AcademicManager: UniversityData not available for unlocking program.") # [cite: 1]
		return false # [cite: 1]
	if not university_data.PROGRAMS.has(program_id): # [cite: 1]
		printerr("AcademicManager: Attempted to unlock non-existent program '", program_id, "'.") # [cite: 1]
		return false # [cite: 1]
	
	if program_states.get(program_id) == "unlocked": # [cite: 1]
		print_debug(["Program '", program_id, "' is already unlocked."]) # [cite: 1]
		return true # [cite: 1]

	var program_details_copy = university_data.get_program_details(program_id) # [cite: 1]
	var cost_to_unlock = program_details_copy.get("unlock_cost", 0) # [cite: 1]

	if cost_to_unlock > 0: # [cite: 1]
		if not is_instance_valid(building_manager): # [cite: 1]
			printerr("AcademicManager: BuildingManager not available for processing unlock cost of '", program_id, "'.") # [cite: 1]
			return false # [cite: 9]
		
		if building_manager.current_endowment < cost_to_unlock: # [cite: 1]
			print_debug(["AcademicManager: Insufficient funds to unlock program '", program_id, "'. Need: $", cost_to_unlock, ", Have: $", building_manager.current_endowment]) # [cite: 10]
			return false # [cite: 1]
		
		building_manager.current_endowment -= cost_to_unlock # [cite: 1]
		if building_manager.has_method("update_financial_ui"): # [cite: 1]
			building_manager.update_financial_ui() # [cite: 1]
		print_debug(["AcademicManager: Deducted $", cost_to_unlock, " for unlocking program '", program_id, "'."]) # [cite: 1]
	
	program_states[program_id] = "unlocked" # [cite: 1]
	_generate_course_offerings_for_program(program_id) # [cite: 1]
	emit_signal("program_unlocked", program_id) # [cite: 1]
	print_debug(["Program '", program_id, "' unlocked."]) # [cite: 1]
	return true # [cite: 1]

func get_program_state(program_id: String) -> String: # [cite: 1]
	return program_states.get(program_id, "unknown") # [cite: 1]

func get_all_program_states() -> Dictionary: # [cite: 1]
	return program_states.duplicate(true) # [cite: 1]

func get_all_unlocked_program_ids() -> Array[String]: # [cite: 1]
	var unlocked_ids_arr: Array[String] = [] # [cite: 1]
	for program_id_key_str in program_states.keys(): # [cite: 1]
		if program_states[program_id_key_str] == "unlocked": # [cite: 1]
			unlocked_ids_arr.append(program_id_key_str) # [cite: 1]
	return unlocked_ids_arr # [cite: 1]

func _generate_course_offerings_for_program(program_id: String): # [cite: 1]
	if not is_instance_valid(university_data): return # [cite: 1]
	if program_states.get(program_id) != "unlocked": return # [cite: 1]

	var required_courses_list: Array[String] = university_data.get_required_courses_for_program(program_id) # [cite: 1]
	var new_offerings_were_added = false # [cite: 1]
	for course_id_val_str in required_courses_list: # [cite: 1]
		var offering_already_exists_for_program = false # [cite: 1]
		for existing_offering_id in course_offerings.keys(): # [cite: 1]
			var existing_offering_details = course_offerings[existing_offering_id] # [cite: 1]
			if existing_offering_details.get("course_id") == course_id_val_str and \
				existing_offering_details.get("program_id") == program_id: # [cite: 1]
				offering_already_exists_for_program = true # [cite: 1]
				break # [cite: 1]
		
		if not offering_already_exists_for_program: # [cite: 1]
			var course_details_dict_copy = university_data.get_course_details(course_id_val_str) # [cite: 1]
			if course_details_dict_copy.is_empty(): # [cite: 1]
				print_debug(["Warning: Details for course '", course_id_val_str, "' not found. Cannot create offering for program '", program_id, "'."]) # [cite: 11]
				continue # [cite: 1]

			var unique_id_suffix = str(Time.get_unix_time_from_system()).right(5) + "_" + str(randi() % 10000) # [cite: 1]
			var new_offering_id_str = "offering_%s_%s_%s" % [program_id.uri_encode(), course_id_val_str.uri_encode(), unique_id_suffix] # [cite: 1]
			
			# NEW: Initialize offerings with more fields for pending/scheduled state
			course_offerings[new_offering_id_str] = {
				"offering_id": new_offering_id_str,
				"course_id": course_id_val_str,
				"course_name": course_details_dict_copy.get("name", "N/A Course Name"),
				"program_id": program_id,
				"status": "unscheduled", # Initial status
				"instructor_id": "",
				"classroom_id": "",
				"primary_day": "", # e.g. "Mon" or "Tue", set when placed pending
				"start_time_slot": "",
				"pattern": "", # e.g. "MWF" or "TR", set when placed pending
				"duration_slots": 0, # set when placed pending
				"max_capacity": course_details_dict_copy.get("default_capacity", 30), # Default from course, overridden by classroom later
				"enrolled_student_ids": []
			} # [cite: 1]
			new_offerings_were_added = true # [cite: 1]
			if DETAILED_LOGGING_ENABLED: print_debug(["Generated new course offering: '", new_offering_id_str, "' for course '", course_id_val_str, "' in program '", program_id, "'."]) # [cite: 1]

	if new_offerings_were_added: # [cite: 1]
		emit_signal("course_offerings_updated") # [cite: 1]

func get_unscheduled_course_offerings() -> Array[Dictionary]: # [cite: 1]
	var unscheduled_list: Array[Dictionary] = [] # [cite: 1]
	for offering_id_key_str in course_offerings.keys(): # [cite: 1]
		var offering_details = course_offerings[offering_id_key_str] # [cite: 1]
		# Ensure all relevant details are copied for the UI
		if offering_details.get("status") == "unscheduled": # [cite: 1]
			var display_details = offering_details.duplicate(true) # [cite: 1]
			# Add any missing default fields if not present from initial generation
			if not display_details.has("course_name"):
				var course_def = university_data.get_course_details(display_details.get("course_id"))
				display_details["course_name"] = course_def.get("name", "N/A")
			unscheduled_list.append(display_details) # [cite: 1]
	return unscheduled_list # [cite: 1]

func get_available_classrooms() -> Array[Dictionary]: # [cite: 1]
	var available_classrooms_list: Array[Dictionary] = [] # [cite: 1]
	if not is_instance_valid(building_manager): # [cite: 1]
		printerr("AcademicManager: BuildingManager not available to get classroom data.") # [cite: 1]
		return available_classrooms_list # [cite: 1]

	if building_manager.has_method("get_functional_buildings_data"): # [cite: 1]
		var functional_buildings: Dictionary = building_manager.get_functional_buildings_data() # [cite: 1]
		for cluster_id_str_key in functional_buildings.keys(): # [cite: 12]
			var cluster_data_dict = functional_buildings[cluster_id_str_key] # [cite: 1]
			if cluster_data_dict.get("building_type") == "class": # [cite: 1]
				available_classrooms_list.append({ # [cite: 1]
					"id": str(cluster_id_str_key), # [cite: 1]
					"name": "Classroom %s" % str(cluster_id_str_key).substr(0, min(5, str(cluster_id_str_key).length())), # [cite: 1]
					"capacity": cluster_data_dict.get("total_capacity", 0) # [cite: 1]
				}) # [cite: 1]
	else:
		printerr("AcademicManager: BuildingManager is missing 'get_functional_buildings_data' method.") # [cite: 1]
	return available_classrooms_list # [cite: 1]

func get_classroom_capacity(classroom_id_str: String) -> int: # [cite: 1]
	if not is_instance_valid(building_manager) or not building_manager.has_method("get_functional_buildings_data"): # [cite: 1]
		printerr("AcademicManager: BuildingManager not available to get capacity for classroom '", classroom_id_str, "'.") # [cite: 1]
		return 0 # [cite: 1]
	
	var functional_buildings: Dictionary = building_manager.get_functional_buildings_data() # [cite: 1]
	if functional_buildings.has(classroom_id_str): # [cite: 1]
		var cluster_data_dict = functional_buildings[classroom_id_str] # [cite: 1]
		if cluster_data_dict.get("building_type") == "class": # [cite: 1]
			return cluster_data_dict.get("total_capacity", 0) # [cite: 1]
		else:
			if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Building '", classroom_id_str, "' is not of type 'class'. Cannot get classroom capacity."]) # [cite: 13]
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Classroom ID '", classroom_id_str, "' not found in functional buildings data."]) # [cite: 13]
	return 0 # [cite: 1]


# --- NEW SCHEDULING LOGIC ---

func place_course_in_slot_pending(offering_id: String, p_classroom_id: String, p_primary_day: String, p_start_time_slot: String) -> bool:
	if not course_offerings.has(offering_id):
		printerr("AM: Offering %s not found for pending placement." % offering_id)
		return false
	
	var offering_data = course_offerings[offering_id]
	if offering_data.status != "unscheduled":
		printerr("AM: Offering %s is not unscheduled, cannot place pending. Status: %s" % [offering_id, offering_data.status])
		return false

	var pattern_to_use: String
	var duration_to_use: int

	if p_primary_day == "Mon":
		pattern_to_use = "MWF"
		duration_to_use = DURATION_MWF
	elif p_primary_day == "Tue":
		pattern_to_use = "TR"
		duration_to_use = DURATION_TR
	else:
		printerr("AM: Invalid primary_day '%s' for pending placement." % p_primary_day)
		return false

	# Check availability for ALL slots this course would occupy
	var days_for_pattern = get_days_for_pattern(pattern_to_use)
	if days_for_pattern.is_empty():
		print_debug("AM: Could not determine valid pattern days for %s from %s" % [pattern_to_use, p_primary_day])
		return false

	var start_slot_idx = HOURLY_TIME_SLOTS.find(p_start_time_slot)
	if start_slot_idx == -1:
		printerr("AM: Invalid start_time_slot '%s' for pending placement." % p_start_time_slot); return false

	for day_in_pattern in days_for_pattern:
		for i in range(duration_to_use):
			var current_slot_index = start_slot_idx + i
			if current_slot_index >= HOURLY_TIME_SLOTS.size():
				print_debug("AM: Course duration for %s exceeds timetable on %s." % [offering_id, day_in_pattern])
				return false
			var time_slot_to_check = HOURLY_TIME_SLOTS[current_slot_index]
			if not _is_single_day_slot_available_direct(p_classroom_id, day_in_pattern, time_slot_to_check, 1): # Check one slot at a time
				print_debug("AM: Slot %s %s in Classroom %s not available for pending placement of %s." % [day_in_pattern, time_slot_to_check, p_classroom_id, offering_id])
				return false
	
	# All slots are available, proceed to place
	offering_data.status = "pending_professor"
	offering_data.classroom_id = p_classroom_id
	offering_data.primary_day = p_primary_day # Store the primary day
	offering_data.start_time_slot = p_start_time_slot
	offering_data.pattern = pattern_to_use
	offering_data.duration_slots = duration_to_use
	offering_data.instructor_id = ""
	offering_data.max_capacity = get_classroom_capacity(p_classroom_id) # Update max capacity from classroom
	offering_data.enrolled_student_ids = [] # Reset enrollments if any were there (shouldn't be for unscheduled)


	# Update classroom_schedules for all affected slots
	for day_in_p in days_for_pattern:
		for i in range(duration_to_use):
			var actual_time_slot = HOURLY_TIME_SLOTS[start_slot_idx + i]
			if not classroom_schedules.has(p_classroom_id): classroom_schedules[p_classroom_id] = {}
			if not classroom_schedules[p_classroom_id].has(day_in_p): classroom_schedules[p_classroom_id][day_in_p] = {}
			classroom_schedules[p_classroom_id][day_in_p][actual_time_slot] = offering_id

	print_debug("AM: Placed %s in %s, %s %s (Pattern: %s) - PENDING PROFESSOR" % [offering_id, p_classroom_id, p_primary_day, p_start_time_slot, pattern_to_use])
	emit_signal("course_offerings_updated")
	emit_signal("schedules_updated")
	return true

func assign_instructor_to_pending_course(offering_id: String, p_professor_id: String) -> bool:
	if not course_offerings.has(offering_id):
		printerr("AM: Offering %s not found for instructor assignment." % offering_id)
		return false
	
	var offering_data = course_offerings[offering_id]
	if offering_data.status != "pending_professor":
		printerr("AM: Offering %s is not 'pending_professor'. Status: %s" % [offering_id, offering_data.status])
		return false

	if not is_instance_valid(professor_manager):
		printerr("AM: ProfessorManager is not available for assignment.")
		return false
	var prof_to_assign = professor_manager.get_professor_by_id(p_professor_id)
	if not is_instance_valid(prof_to_assign):
		printerr("AM: Professor %s not valid for assignment." % p_professor_id)
		return false

	# Check professor availability for ALL slots of THIS offering
	var days_for_pattern = get_days_for_pattern(offering_data.pattern)
	var start_slot_idx = HOURLY_TIME_SLOTS.find(offering_data.start_time_slot)
	if start_slot_idx == -1: printerr("AM: Corrupted start_time_slot in offering %s" % offering_id); return false

	for day_in_pattern in days_for_pattern:
		for i in range(offering_data.duration_slots):
			var time_slot_for_check = HOURLY_TIME_SLOTS[start_slot_idx + i]
			if is_professor_teaching_another_course_at(p_professor_id, day_in_pattern, time_slot_for_check, offering_id):
				print_debug("AM: Professor %s is already teaching another course at %s %s." % [p_professor_id, day_in_pattern, time_slot_for_check])
				return false
	
	var course_def = university_data.get_course_details(offering_data.course_id) # From UniversityData
	if course_def.has("specialization") and prof_to_assign.has_method("get_specialization_enum_direct"): # Ensure methods/keys exist
		var required_spec_enum = course_def.get("specialization") # Assuming this is the enum value from UniversityData.COURSES
		var prof_spec_enum = prof_to_assign.get_specialization_enum_direct() # Make sure Professor.gd has this getter
		
		# Allow GENERAL if either course is general or prof is general
		var course_is_general = (required_spec_enum == Professor.Specialization.GENERAL)
		var prof_is_general = (prof_spec_enum == Professor.Specialization.GENERAL)

		if not course_is_general and not prof_is_general and required_spec_enum != prof_spec_enum:
			print_debug("AM: Prof %s spec (%s) mismatch for course %s (req %s)" % [prof_to_assign.professor_name, prof_spec_enum, course_def.get("name"), required_spec_enum])
			# return false # Uncomment to strictly enforce specialization for non-general cases

	# All checks passed
	offering_data.instructor_id = p_professor_id
	offering_data.status = "scheduled"

	# Populate scheduled_class_details (as the old schedule_class did)
	scheduled_class_details[offering_id] = {
		"offering_id": offering_id,
		"course_id": offering_data.course_id,
		"course_name": offering_data.course_name,
		"program_id": offering_data.program_id,
		"classroom_id": offering_data.classroom_id,
		"pattern": offering_data.pattern,
		"day": offering_data.primary_day, # Primary day for pattern determination
		"start_time_slot": offering_data.start_time_slot,
		"start_time_slot_index": HOURLY_TIME_SLOTS.find(offering_data.start_time_slot),
		"duration_slots": offering_data.duration_slots,
		"instructor_id": p_professor_id,
		"max_capacity": offering_data.max_capacity,
		"enrolled_student_ids": offering_data.enrolled_student_ids.duplicate(true) # Copy
	}

	if is_instance_valid(professor_manager):
		professor_manager.assign_professor_to_course(p_professor_id, offering_id)

	print_debug("AM: Assigned Professor %s to Offering %s. Status: SCHEDULED" % [p_professor_id, offering_id])
	emit_signal("class_scheduled", offering_id, scheduled_class_details[offering_id]) # Use existing signal
	emit_signal("schedules_updated")
	emit_signal("course_offerings_updated") # Status changed
	emit_signal("enrollment_changed", offering_id, offering_data.enrolled_student_ids.size(), offering_data.max_capacity)
	return true

# This is your existing is_slot_available, checks pattern
func is_slot_available(classroom_id: String, primary_day: String, start_time_slot_str_val: String) -> bool: # [cite: 1]
	if not (primary_day == "Mon" or primary_day == "Tue"): # [cite: 1]
		# This function assumes primary_day is Mon (for MWF) or Tue (for TR) to determine pattern
		# If you want to check individual slots, use _is_single_day_slot_available_direct
		printerr("AcademicManager: Invalid primary_day '", primary_day, "' for is_slot_available (pattern check). Must be 'Mon' or 'Tue'.") # [cite: 1]
		return false # [cite: 1]
		
	var days_to_check_in_pattern: Array[String] = [] # [cite: 1]
	var duration_for_this_pattern_slots: int = 0 # [cite: 1]
	
	if primary_day == "Mon": # [cite: 1]
		days_to_check_in_pattern = ["Mon", "Wed", "Fri"] # [cite: 1]
		duration_for_this_pattern_slots = DURATION_MWF # [cite: 1]
	elif primary_day == "Tue": # [cite: 1]
		days_to_check_in_pattern = ["Tue", "Thu"] # [cite: 1]
		duration_for_this_pattern_slots = DURATION_TR # [cite: 1]
	
	for day_str_in_pattern in days_to_check_in_pattern: # [cite: 1]
		if not _is_single_day_slot_available_direct(classroom_id, day_str_in_pattern, start_time_slot_str_val, duration_for_this_pattern_slots): # [cite: 1]
			return false # [cite: 1]
	return true # [cite: 1]

# Renamed your _is_single_day_slot_available to avoid confusion and make it direct
func _is_single_day_slot_available_direct(classroom_id: String, day_to_check_str: String, start_time_slot_str_val: String, duration_in_slots_val: int) -> bool:
	if not DAYS_OF_WEEK.has(day_to_check_str) or not HOURLY_TIME_SLOTS.has(start_time_slot_str_val): # [cite: 1]
		printerr("AcademicManager (_is_single_day_direct): Invalid day '", day_to_check_str, "' or time slot '", start_time_slot_str_val, "'.") # [cite: 14]
		return false # [cite: 1]

	var classroom_schedule_for_day: Dictionary = classroom_schedules.get(classroom_id, {}).get(day_to_check_str, {}) # [cite: 1]
	var start_slot_idx_val = HOURLY_TIME_SLOTS.find(start_time_slot_str_val) # [cite: 1]

	if start_slot_idx_val == -1: # [cite: 1]
		printerr("AcademicManager (_is_single_day_direct): Could not find index for start_time_slot '", start_time_slot_str_val, "'.") # [cite: 1]
		return false # [cite: 1]

	for i in range(duration_in_slots_val): # [cite: 1]
		var current_slot_index_to_check = start_slot_idx_val + i # [cite: 1]
		if current_slot_index_to_check >= HOURLY_TIME_SLOTS.size(): # [cite: 1]
			return false # [cite: 1] # Slot exceeds timetable
		
		var time_slot_key_to_check_str = HOURLY_TIME_SLOTS[current_slot_index_to_check] # [cite: 1]
		if classroom_schedule_for_day.has(time_slot_key_to_check_str): # [cite: 1]
			return false # [cite: 1] # Slot is occupied
			
	return true # [cite: 1]

# The old schedule_class is now largely superseded by the two-step process.
# If you still need a way to directly schedule with an instructor in one go,
# this function would need to be adapted or you'd call place_course_in_slot_pending
# then immediately assign_instructor_to_pending_course.
# For now, I'll comment it out to avoid conflict with the new flow.
# func schedule_class(offering_id: String, classroom_id: String, primary_day_arg: String, start_time_slot_str_arg: String, selected_instructor_id: String = "") -> bool: ...

func unschedule_class(offering_id_to_remove: String) -> bool:
	if not course_offerings.has(offering_id_to_remove):
		printerr("Cannot unschedule: Offering '%s' not found in course_offerings." % offering_id_to_remove)
		return false

	var offering_data = course_offerings[offering_id_to_remove]
	var original_status = offering_data.status
	
	var classroom_id_val = offering_data.get("classroom_id", "")
	var day_pattern_val = offering_data.get("pattern", "")
	var start_time_slot_val = offering_data.get("start_time_slot", "")
	var duration_val = offering_data.get("duration_slots", 0)
	var instructor_id_was = offering_data.get("instructor_id", "")
	var enrolled_students_count = offering_data.get("enrolled_student_ids", []).size()
	var max_cap_was = offering_data.get("max_capacity", 0)

	var start_slot_index_val = -1
	if not start_time_slot_val.is_empty():
		start_slot_index_val = HOURLY_TIME_SLOTS.find(start_time_slot_val)

	# Clear from classroom_schedules if it was pending or scheduled
	if (original_status == "pending_professor" or original_status == "scheduled") and \
	   not classroom_id_val.is_empty() and not day_pattern_val.is_empty() and start_slot_index_val != -1:
		
		var days_to_clear_from_schedule = get_days_for_pattern(day_pattern_val)

		for day_str_key_val in days_to_clear_from_schedule:
			if classroom_schedules.has(classroom_id_val) and classroom_schedules[classroom_id_val].has(day_str_key_val):
				var day_schedule_map_ref = classroom_schedules[classroom_id_val][day_str_key_val]
				for i in range(duration_val):
					var current_slot_idx_to_clear = start_slot_index_val + i
					if current_slot_idx_to_clear < HOURLY_TIME_SLOTS.size():
						var time_slot_key_str = HOURLY_TIME_SLOTS[current_slot_idx_to_clear]
						if day_schedule_map_ref.get(time_slot_key_str) == offering_id_to_remove:
							day_schedule_map_ref.erase(time_slot_key_str)
				
				if day_schedule_map_ref.is_empty(): # Clean up empty day dict
					classroom_schedules[classroom_id_val].erase(day_str_key_val)
			
			if classroom_schedules.has(classroom_id_val) and classroom_schedules[classroom_id_val].is_empty(): # Clean up empty classroom dict
				classroom_schedules.erase(classroom_id_val)
	
	# If it was fully scheduled, also clear from scheduled_class_details and unassign professor
	var details_for_signal = {}
	if original_status == "scheduled":
		if scheduled_class_details.has(offering_id_to_remove):
			details_for_signal = scheduled_class_details[offering_id_to_remove].duplicate(true)
			scheduled_class_details.erase(offering_id_to_remove)
		if not instructor_id_was.is_empty() and is_instance_valid(professor_manager):
			professor_manager.unassign_professor_from_course(instructor_id_was, offering_id_to_remove)
		emit_signal("class_unscheduled", offering_id_to_remove, details_for_signal) # Use existing signal

	# Reset offering in course_offerings
	offering_data.status = "unscheduled"
	offering_data.instructor_id = ""
	offering_data.classroom_id = ""
	offering_data.primary_day = ""
	offering_data.start_time_slot = ""
	offering_data.pattern = "" # Or reset to default from course_def if applicable
	offering_data.duration_slots = 0 # Or reset to default
	# Keep enrolled_student_ids for now, or clear them:
	# offering_data.enrolled_student_ids.clear()
	
	emit_signal("schedules_updated")
	emit_signal("course_offerings_updated")
	if original_status == "scheduled" or original_status == "pending_professor": # If it was on the schedule
		emit_signal("enrollment_changed", offering_id_to_remove, 0, max_cap_was) # Reflect it's now 0 enrolled on schedule

	if DETAILED_LOGGING_ENABLED: print_debug(["Offering '", offering_id_to_remove, "' status changed to unscheduled. Original status was '", original_status, "'."])
	
	if enrolled_students_count > 0 and (original_status == "scheduled" or original_status == "pending_professor"):
		if DETAILED_LOGGING_ENABLED: print_debug(["Warning: Unscheduled class '", offering_id_to_remove, "' had ", enrolled_students_count, " students. They need to be handled."]) # [cite: 23]
	return true


func is_professor_teaching_another_course_at(p_professor_id: String, day_to_check: String, time_slot_to_check: String, offering_id_to_ignore: String) -> bool:
	if p_professor_id.is_empty(): return false

	for offering_id_iter in course_offerings:
		if offering_id_iter == offering_id_to_ignore:
			continue
			
		var iter_offering_data = course_offerings[offering_id_iter]
		if iter_offering_data.status == "scheduled" and iter_offering_data.instructor_id == p_professor_id:
			# This professor is teaching iter_offering_data. Check if day/time overlaps.
			var iter_days = get_days_for_pattern(iter_offering_data.pattern)
			if day_to_check in iter_days:
				var iter_start_idx = HOURLY_TIME_SLOTS.find(iter_offering_data.start_time_slot)
				var current_slot_idx = HOURLY_TIME_SLOTS.find(time_slot_to_check)

				if iter_start_idx != -1 and current_slot_idx != -1: # Both time slots are valid
					var iter_end_idx = iter_start_idx + iter_offering_data.duration_slots - 1
					if current_slot_idx >= iter_start_idx and current_slot_idx <= iter_end_idx:
						if DETAILED_LOGGING_ENABLED: print_debug("Prof %s busy at %s %s due to offering %s" % [p_professor_id, day_to_check, time_slot_to_check, offering_id_iter])
						return true
	return false

func get_offering_details(offering_id: String) -> Dictionary: # [cite: 1]
	if course_offerings.has(offering_id): # [cite: 1]
		var offering_data = course_offerings[offering_id] # This is the primary data source now
		var details = offering_data.duplicate(true) # [cite: 1]

		# Ensure course_name is present (might not be if generated without full UniversityData init)
		if not details.has("course_name") or details.course_name == "N/A Course Name":
			if is_instance_valid(university_data):
				var course_def = university_data.get_course_details(details.course_id)
				details.course_name = course_def.get("name", "N/A")
		
		# If it was fully scheduled, scheduled_class_details might have a more "canonical" version for some fields
		# However, course_offerings should now be the single source of truth for the current state.
		# The old version merged from scheduled_class_details. If that's still desired:
		# if details.status == "scheduled" and scheduled_class_details.has(offering_id):
		# 	details.merge(scheduled_class_details[offering_id], true) # Overwrite with scheduled_class_details if keys clash

		# Ensure enrollment and capacity are correctly reflected
		details["enrolled_count"] = details.get("enrolled_student_ids", []).size()
		if not details.has("max_capacity") or details.max_capacity == 0: # If pending, max_capacity is from classroom
			if not details.get("classroom_id", "").is_empty():
				details.max_capacity = get_classroom_capacity(details.classroom_id)
			elif is_instance_valid(university_data): # Fallback to course default if no classroom yet
				var course_def = university_data.get_course_details(details.course_id)
				details.max_capacity = course_def.get("default_capacity", 30)
			else:
				details.max_capacity = 30 # Absolute fallback

		# if DETAILED_LOGGING_ENABLED: print_debug(["AM.get_offering_details: Returning for", offering_id, "Status:", details.status, "Pattern:", details.get("pattern", "N/A")]) # [cite: 32]
		return details # [cite: 1]
	
	if DETAILED_LOGGING_ENABLED: print_debug(["AM.get_offering_details: Offering ID not found:", offering_id]) # [cite: 1]
	return {} # [cite: 1]

func get_schedule_for_classroom(classroom_id: String) -> Dictionary: # [cite: 1]
	if classroom_schedules.has(classroom_id): # [cite: 1]
		return classroom_schedules[classroom_id].duplicate(true) # [cite: 1]
	return {} # [cite: 1]

func get_days_for_pattern(pattern_str: String) -> Array[String]: # [cite: 1]
	if pattern_str == "MWF": return ["Mon", "Wed", "Fri"] # [cite: 1]
	if pattern_str == "TR": return ["Tue", "Thu"] # [cite: 1]
	# Add more patterns if you have them (e.g., "M", "T", "W", "R", "F" for single-day occurrences)
	if pattern_str == "M": return ["Mon"]
	if pattern_str == "T": return ["Tue"]
	if pattern_str == "W": return ["Wed"]
	if pattern_str == "R": return ["Thu"] # Common abbreviation for Thursday
	if pattern_str == "F": return ["Fri"]
	if DETAILED_LOGGING_ENABLED and not pattern_str.is_empty(): print_debug(["Warning: Unknown pattern '", pattern_str, "' in get_days_for_pattern."]) # [cite: 1]
	return [] # [cite: 1]


# --- Student Enrollment, Simulation, and Progression (Existing User Code - largely untouched) ---
# Make sure any references to scheduled_class_details within these functions are still valid
# or are adapted if course_offerings is now the primary source of schedule truth.
# For example, if student enrollment functions look up course capacity or schedule times,
# they should get it from course_offerings[offering_id] if status is "pending" or "scheduled".

# MODIFIED: This function will now search course_offerings
func find_and_enroll_student_in_offering(student_id: String, course_id_to_enroll: String) -> String:
	var best_offering_id_to_enroll: String = ""
	var max_available_seats_in_best_offering = -1 # Initialize to take any offering with seats

	if DETAILED_LOGGING_ENABLED: print_debug(["Finding offering for course '%s' for student '%s'." % [course_id_to_enroll, student_id]])

	for offering_id_candidate in course_offerings.keys():
		var offering_data = course_offerings[offering_id_candidate]

		# Check if it's the correct course_id AND if it's on the timetable (pending or fully scheduled)
		if offering_data.get("course_id") == course_id_to_enroll and \
		   (offering_data.get("status") == "scheduled" or offering_data.get("status") == "pending_professor"):
			
			var enrolled_students_list: Array = offering_data.get("enrolled_student_ids", [])
			# max_capacity in course_offerings should be updated from classroom when placed/scheduled
			var current_max_capacity = offering_data.get("max_capacity", 0) 
			var current_available_seats = current_max_capacity - enrolled_students_list.size()

			if DETAILED_LOGGING_ENABLED:
				print_debug(["  Checking offering candidate '%s' for course '%s'. Status: '%s', Capacity: %d, Enrolled: %d, Available: %d" % \
					[offering_id_candidate, course_id_to_enroll, offering_data.get("status"), current_max_capacity, enrolled_students_list.size(), current_available_seats]])

			if current_available_seats > 0:
				# Prioritize offerings with more available seats
				if current_available_seats > max_available_seats_in_best_offering:
					max_available_seats_in_best_offering = current_available_seats
					best_offering_id_to_enroll = offering_id_candidate
				# If no "best" yet (max_available_seats_in_best_offering is still -1), take the first one with available seats
				elif best_offering_id_to_enroll.is_empty() and max_available_seats_in_best_offering == -1 : 
					best_offering_id_to_enroll = offering_id_candidate
					max_available_seats_in_best_offering = current_available_seats
		
	if not best_offering_id_to_enroll.is_empty():
		# enroll_student_in_offering is AM's own method, now modified below
		var enrollment_success = enroll_student_in_offering(best_offering_id_to_enroll, student_id)
		if enrollment_success:
			if DETAILED_LOGGING_ENABLED: print_debug(["Student '", student_id, "' CAN BE ENROLLED in '", course_id_to_enroll, "' (Found and attempting enrollment in Offering: '", best_offering_id_to_enroll, "')."])
			return best_offering_id_to_enroll
		# else: # enroll_student_in_offering will log its own errors
			# printerr("Student '", student_id, "' FAILED internal enrollment call for '", course_id_to_enroll, "' (Offering: '", best_offering_id_to_enroll, "').")
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["No available offering (scheduled or pending with capacity) found for student '", student_id, "' to enroll in course '", course_id_to_enroll, "'."])
	return ""

# MODIFIED: This function will now use course_offerings as the source of truth
func enroll_student_in_offering(offering_id: String, student_id: String) -> bool:
	if not course_offerings.has(offering_id):
		printerr("AcademicManager: Cannot enroll. Offering '%s' not found in course_offerings." % offering_id)
		return false

	var offering_data = course_offerings[offering_id] # This is a dictionary from course_offerings
	
	# Students can be enrolled in classes that are on the timetable, even if pending a professor.
	# They just won't attend until it's fully "scheduled".
	if offering_data.status != "scheduled" and offering_data.status != "pending_professor":
		printerr("AcademicManager: Offering '%s' is not in a schedulable state (must be 'scheduled' or 'pending_professor'). Current status: '%s'. Cannot enroll." % [offering_id, offering_data.status])
		return false
		
	if not offering_data.has("enrolled_student_ids") or not offering_data.has("max_capacity"):
		printerr("AcademicManager: Offering '", offering_id, "' has malformed details (missing enrolled_student_ids or max_capacity field). Cannot enroll student.")
		return false
	
	var current_max_capacity = offering_data.get("max_capacity", 0)
	# max_capacity should have been set when the course was placed pending, based on classroom capacity.
	if current_max_capacity <= 0 :
		printerr("AcademicManager: Offering '", offering_id, "' has zero or invalid max_capacity (%s) according to its data. Cannot enroll." % str(current_max_capacity))
		return false # Cannot enroll if capacity isn't properly set from classroom

	if offering_data.enrolled_student_ids.size() >= current_max_capacity:
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Cannot enroll student '", student_id, "'. Offering '", offering_id, "' is full (", offering_data.enrolled_student_ids.size(), "/", current_max_capacity, ")."])
		return false
		
	if offering_data.enrolled_student_ids.has(student_id):
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' is already enrolled in offering '", offering_id, "'."])
		return true
		
	offering_data.enrolled_student_ids.append(student_id)
	
	# If the offering was already fully "scheduled" and thus had an entry in scheduled_class_details,
	# update that entry's enrollment list as well for consistency with systems that might still use it.
	if offering_data.status == "scheduled" and scheduled_class_details.has(offering_id):
		if scheduled_class_details[offering_id].has("enrolled_student_ids"):
			if not scheduled_class_details[offering_id].enrolled_student_ids.has(student_id): # Ensure not duplicating
				scheduled_class_details[offering_id].enrolled_student_ids.append(student_id)
		else: # Should ideally not happen if scheduled_class_details entries are well-formed
			scheduled_class_details[offering_id]["enrolled_student_ids"] = [student_id]

	emit_signal("enrollment_changed", offering_id, offering_data.enrolled_student_ids.size(), current_max_capacity)
	emit_signal("schedules_updated") # UI might show enrollment counts
	if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' enrolled in offering '", offering_id, "'. Status: ", offering_data.status, ". Total enrolled: ", offering_data.enrolled_student_ids.size()])
	return true

func drop_student_from_offering(offering_id: String, student_id: String) -> bool: # [cite: 1]
	if not course_offerings.has(offering_id): # [cite: 1]
		printerr("AcademicManager: Cannot drop. Offering '%s' not found." % offering_id) # [cite: 1]
		return false # [cite: 1]

	var offering_data = course_offerings[offering_id]
	if not offering_data.has("enrolled_student_ids"): # [cite: 1]
		printerr("AcademicManager: Offering '", offering_id, "' has malformed details. Cannot drop.") # [cite: 1]
		return false # [cite: 1]
		
	if offering_data.enrolled_student_ids.has(student_id): # [cite: 1]
		offering_data.enrolled_student_ids.erase(student_id) # [cite: 1]
		# If using scheduled_class_details as a live mirror
		if scheduled_class_details.has(offering_id) and scheduled_class_details[offering_id].has("enrolled_student_ids"):
			if scheduled_class_details[offering_id].enrolled_student_ids.has(student_id):
				scheduled_class_details[offering_id].enrolled_student_ids.erase(student_id)

		emit_signal("enrollment_changed", offering_id, offering_data.enrolled_student_ids.size(), offering_data.max_capacity) # [cite: 1]
		emit_signal("schedules_updated") # [cite: 1]
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' dropped from '", offering_id, "'. Total: ", offering_data.enrolled_student_ids.size()]) # [cite: 1]
		return true # [cite: 1]
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' not found in '", offering_id, "'. Cannot drop."]) # [cite: 25]
		return false # [cite: 1]

func get_offering_enrollment(offering_id: String) -> Dictionary: # [cite: 1]
	if course_offerings.has(offering_id): # [cite: 1]
		var data = course_offerings[offering_id] # [cite: 1]
		if data.has("enrolled_student_ids") and data.has("max_capacity"): # [cite: 1]
			return { # [cite: 1]
				"enrolled_count": data.enrolled_student_ids.size(), # [cite: 1]
				"max_capacity": data.max_capacity, # [cite: 1]
				"student_ids": data.enrolled_student_ids.duplicate(true) # [cite: 1]
			} # [cite: 1]
	return {"enrolled_count": 0, "max_capacity": 0, "student_ids": []} # [cite: 1]

func calculate_new_student_intake_capacity() -> int:
	if not is_instance_valid(university_data):
		printerr("AcademicManager: Capacity Calc - UniversityData not valid.")
		return 0

	var total_available_seats: int = 0
	var unlocked_prog_ids_list: Array[String] = get_all_unlocked_program_ids()

	if unlocked_prog_ids_list.is_empty():
		if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: No unlocked programs. Intake capacity is 0."])
		return 0

	if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: Unlocked programs for capacity check: ", str(unlocked_prog_ids_list)])

	var unique_initial_semester_courses_dict: Dictionary = {}

	for prog_id_val in unlocked_prog_ids_list:
		var program_curriculum_structure = university_data.get_program_curriculum_structure(prog_id_val)
		if program_curriculum_structure.has("Year 1"):
			var year1_data: Dictionary = program_curriculum_structure["Year 1"]
			if year1_data.has("Semester 1"):
				var first_sem_course_id_list: Array = year1_data["Semester 1"]
				if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: For program '", prog_id_val, "', Year 1/Semester 1 courses: ", str(first_sem_course_id_list)])
				for course_id_item_val in first_sem_course_id_list:
					if course_id_item_val is String:
						unique_initial_semester_courses_dict[course_id_item_val] = true
			elif DETAILED_LOGGING_ENABLED:
				print_debug(["Capacity Calc: Program '", prog_id_val, "' has 'Year 1' but no 'Semester 1' defined."])
		elif DETAILED_LOGGING_ENABLED:
			print_debug(["Capacity Calc: Program '", prog_id_val, "' has no 'Year 1' defined."])

	if unique_initial_semester_courses_dict.is_empty():
		if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: No unique initial semester courses found."])
		return 0
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: Unique initial semester courses to check: ", str(unique_initial_semester_courses_dict.keys())])

	# MODIFIED: Iterate course_offerings instead of scheduled_class_details
	for course_id_for_calc in unique_initial_semester_courses_dict.keys():
		var found_offering_for_this_course_type = false
		for offering_id_key in course_offerings.keys(): # Iterate all course offerings
			var offering_data: Dictionary = course_offerings[offering_id_key]
			
			# Only consider offerings that are on the timetable (scheduled or pending) and match the initial course ID
			if (offering_data.get("status") == "scheduled" or offering_data.get("status") == "pending_professor") and \
			   offering_data.get("course_id") == course_id_for_calc:
				found_offering_for_this_course_type = true
				var enrolled_students_array: Array = offering_data.get("enrolled_student_ids", [])
				var max_cap: int = offering_data.get("max_capacity", 0) # Max capacity from classroom
				var available_in_this_one = max_cap - enrolled_students_array.size()
				
				if available_in_this_one > 0:
					total_available_seats += available_in_this_one
					if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: Offering '", offering_id_key, "' (Course: '", course_id_for_calc, "', Status: '", offering_data.get("status"),"') has ", available_in_this_one, " available seats. Total so far: ", total_available_seats])
				elif DETAILED_LOGGING_ENABLED:
					print_debug(["Capacity Calc: Offering '", offering_id_key, "' (Course: '", course_id_for_calc, "', Status: '", offering_data.get("status"),"') is full or has no capacity (", enrolled_students_array.size() , "/", max_cap, ")."])
		
		if not found_offering_for_this_course_type and DETAILED_LOGGING_ENABLED:
			print_debug(["Capacity Calc: No scheduled/pending offerings found for initial course type '", course_id_for_calc, "'. This will limit intake."])

	if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: Final calculated total intake capacity based on initial course offerings: %d seats." % total_available_seats])
	return total_available_seats

func get_freshman_first_semester_courses(program_id: String) -> Array[String]: # [cite: 1]
	if not is_instance_valid(university_data): return [] # [cite: 1]
	var curriculum_data = university_data.get_program_curriculum_structure(program_id) # [cite: 1]
	var courses_to_return_list: Array[String] = [] # [cite: 1]
	if curriculum_data.has("Freshman Year"): # [cite: 1]
		var freshman_year_dict: Dictionary = curriculum_data["Freshman Year"] # [cite: 1]
		if freshman_year_dict.has("First Semester"): # [cite: 1]
			var course_list_from_structure: Array = freshman_year_dict["First Semester"] # [cite: 1]
			for item_val in course_list_from_structure: # [cite: 1]
				if item_val is String: courses_to_return_list.append(item_val) # [cite: 1]
	if courses_to_return_list.is_empty() and program_states.get(program_id) == "unlocked": # [cite: 1]
		if DETAILED_LOGGING_ENABLED: print_debug(["Warning: No Freshman/1st Sem courses in curriculum for '", program_id, "'."]) # [cite: 1]
	return courses_to_return_list # [cite: 1]

func get_classroom_location(classroom_id_str: String) -> Vector3: # [cite: 1]
	var nav_y = ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y # [cite: 1]

	if not is_instance_valid(building_manager): # [cite: 33]
		printerr("AM: BuildingManager not available for classroom location: ", classroom_id_str) # [cite: 1]
		return Vector3.ZERO # [cite: 1]

	if building_manager.has_method("get_functional_buildings_data"): # [cite: 1]
		var functional_buildings: Dictionary = building_manager.get_functional_buildings_data() # [cite: 1]
		if functional_buildings.has(classroom_id_str): # [cite: 1]
			var classroom_cluster_data = functional_buildings[classroom_id_str] # [cite: 1]

			if classroom_cluster_data.get("building_type") == "class": # [cite: 1]
				var current_physical_users = classroom_cluster_data.get("current_users", 0) # [cite: 1]
				var total_physical_capacity = classroom_cluster_data.get("total_capacity", 0) # [cite: 1]
				
				if total_physical_capacity > 0 and current_physical_users >= total_physical_capacity: # [cite: 1]
					if DETAILED_LOGGING_ENABLED: print_debug(["AM: Classroom '", classroom_id_str, "' is PHYSICALLY FULL (BM users: ", current_physical_users, "/", total_physical_capacity, "). Returning no location."]) # [cite: 34]
					return Vector3.ZERO # [cite: 1]
				
				var rep_node = classroom_cluster_data.get("representative_block_node") # [cite: 1]
				if is_instance_valid(rep_node) and rep_node is Node3D: # [cite: 1]
					var base_position = rep_node.global_position # [cite: 1]
					
					var random_offset_x: float = randf_range(-0.4, 0.4) # [cite: 1]
					var random_offset_z: float = randf_range(-0.4, 0.4) # [cite: 1]
					var student_specific_target = Vector3(base_position.x + random_offset_x, # [cite: 1]
														nav_y,  # [cite: 1]
														base_position.z + random_offset_z) # [cite: 1]
					return student_specific_target # [cite: 1]
				else:
					if DETAILED_LOGGING_ENABLED: print_debug(["AM: Classroom cluster '", classroom_id_str, "' has NO valid representative_block_node."]) # [cite: 1]
			else:
				if DETAILED_LOGGING_ENABLED: print_debug(["AM: Building cluster '", classroom_id_str, "' is NOT 'class'. Actual: ", classroom_cluster_data.get("building_type")]) # [cite: 35]
		else:
			if DETAILED_LOGGING_ENABLED: print_debug(["AM: Classroom ID '", classroom_id_str, "' NOT FOUND in functional_buildings. Keys: ", str(functional_buildings.keys())]) # [cite: 1]
	else:
		printerr("AM: BuildingManager missing 'get_functional_buildings_data'.") # [cite: 1]

	if DETAILED_LOGGING_ENABLED: print_debug(["AM: get_classroom_location returning Vector3.ZERO for classroom_id: '", classroom_id_str, "'."]) # [cite: 1]
	return Vector3.ZERO # [cite: 1]

# --- Student Simulation Logic (Existing User Code - Largely Untouched Below) ---
func _on_student_despawned(data: Dictionary): # [cite: 1]
	var student_id = data.get("student_id") # [cite: 1]
	if DETAILED_LOGGING_ENABLED: # [cite: 1]
		print_debug(["_on_student_despawned CALLED (AcademicManager). Student ID:", student_id, "Activity:", data.get("activity_after_despawn", "N/A_Activity")]) # [cite: 37]

	var sim_data_entry = data.duplicate(true)  # [cite: 1]
	sim_data_entry["time_spent_in_activity_simulated"] = 0.0 # [cite: 1]
	in_building_simulated_students.append(sim_data_entry) # [cite: 1]

	if DETAILED_LOGGING_ENABLED: # [cite: 1]
		print_debug(["AcademicManager: Student %s data processed for simulation list. Node is expected to self-free." % student_id]) # [cite: 1]

func _on_visual_hour_slot_changed_simulation_update(day_str: String, time_slot_str: String): # [cite: 1]
	if DETAILED_LOGGING_ENABLED:  # [cite: 1]
		print_debug(["_on_visual_hour_slot_changed_simulation_update (TOP OF HOUR) CALLED. Day:", day_str, "Slot:", time_slot_str, "In-building students count:", in_building_simulated_students.size()]) # [cite: 38]
	if not is_instance_valid(time_manager): # [cite: 1]
		printerr("AcademicManager: TimeManager invalid in _on_visual_hour_slot_changed_simulation_update.") # [cite: 1]
		return # [cite: 1]
	
	var seconds_per_slot = time_manager.seconds_per_visual_hour_slot # [cite: 1]
	var current_sim_hour = time_manager.time_slot_str_to_hour_int(time_slot_str)  # [cite: 1]
	var current_sim_minute = 0  # [cite: 1]

	var students_to_queue_indices: Array[int] = [] # [cite: 1]

	for i in range(in_building_simulated_students.size()): # [cite: 1]
		var student_data: Dictionary = in_building_simulated_students[i] # [cite: 1]
		var student_id_for_log = student_data.get("student_id", "N/A_ID") # [cite: 1]
		
		_simulate_student_needs_update_off_map(student_data, seconds_per_slot)  # [cite: 1]
		student_data["time_spent_in_activity_simulated"] += seconds_per_slot # [cite: 1]
		if DETAILED_LOGGING_ENABLED: print_debug(["  Needs & TimeSim updated for:", student_id_for_log, "New TimeSim:", student_data["time_spent_in_activity_simulated"]]) # [cite: 1]
		
		var activity_type = student_data.get("activity_after_despawn") # [cite: 1]
		var should_check_exit_this_hour = false # [cite: 1]
		if activity_type != "in_class":  # [cite: 1]
			should_check_exit_this_hour = true # [cite: 1]
		elif activity_type == "in_class":  # [cite: 1]
			var target_data: Dictionary = student_data.get("activity_target_data", {}) # [cite: 1]
			var offering_id: String = target_data.get("offering_id", "") # [cite: 1]
			var sch_info: Dictionary = {} # [cite: 1]
			var student_enrollments = student_data.get("current_course_enrollments") # [cite: 1]
			
			if student_enrollments is Dictionary and student_enrollments.has(offering_id) : # [cite: 1]
				var enrollment_entry = student_enrollments.get(offering_id) # [cite: 39]
				if enrollment_entry is Dictionary and enrollment_entry.has("schedule_info"): # [cite: 1]
					sch_info = enrollment_entry.get("schedule_info") # [cite: 1]
			
			if not sch_info.is_empty(): # [cite: 1]
				var class_start_hour_val = time_manager.time_slot_str_to_hour_int(sch_info.get("start_time_slot","0000")) # [cite: 1]
				var class_duration_val = sch_info.get("duration_slots",1) # [cite: 1]
				if class_start_hour_val != -1 and current_sim_hour > (class_start_hour_val + class_duration_val - 1) :  # [cite: 1]
					should_check_exit_this_hour = true # [cite: 1]
			elif DETAILED_LOGGING_ENABLED:  # [cite: 1]
				print_debug(["AM: Hourly check for class ", offering_id if not offering_id.is_empty() else "Unknown Offering", " - could not get valid schedule_info for failsafe."]) # [cite: 1]

		if should_check_exit_this_hour: # [cite: 1]
			if _should_student_exit_building_simulation(student_data, current_sim_hour, current_sim_minute, day_str): # [cite: 1]
				students_to_queue_indices.append(i) # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["    Student (hourly check) MARKED for respawn queue:", student_id_for_log]) # [cite: 1]
	
	if not students_to_queue_indices.is_empty(): # [cite: 1]
		_add_students_to_respawn_queue(students_to_queue_indices) # [cite: 1]


func _on_simulation_time_ticked_for_student_checks(day_str: String, hour_int: int, minute_int: int, visual_slot_str: String): # [cite: 1]
	if DETAILED_LOGGING_ENABLED and minute_int % 15 == 0 and minute_int != 0 : # [cite: 40]
		print_debug(["AM: Time ticked to Day:", day_str, "Time:", str(hour_int).pad_zeros(2) + ":" + str(minute_int).pad_zeros(2), "Slot:", visual_slot_str, "Checking class exits for",in_building_simulated_students.size(), "students."]) # [cite: 1]

	if in_building_simulated_students.is_empty(): # [cite: 1]
		return # [cite: 1]

	var students_to_queue_indices: Array[int] = [] # [cite: 1]
	for i in range(in_building_simulated_students.size()): # [cite: 1]
		var student_data: Dictionary = in_building_simulated_students[i] # [cite: 1]
		
		if student_data.get("activity_after_despawn") == "in_class": # [cite: 1]
			if _should_student_exit_building_simulation(student_data, hour_int, minute_int, day_str): # [cite: 1]
				students_to_queue_indices.append(i) # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["    Student (minute check for class exit) MARKED for respawn queue:", student_data.get("student_id", "N/A_ID")]) # [cite: 1]
	
	if not students_to_queue_indices.is_empty(): # [cite: 1]
		_add_students_to_respawn_queue(students_to_queue_indices) # [cite: 1]

func _add_students_to_respawn_queue(indices_from_active_list: Array[int]): # [cite: 1]
	if indices_from_active_list.is_empty(): # [cite: 1]
		return # [cite: 1]

	indices_from_active_list.sort_custom(Callable(self, "_sort_indices_descending")) # [cite: 1]

	var actually_added_to_queue_count = 0 # [cite: 1]
	for student_index_in_main_array in indices_from_active_list: # [cite: 1]
		if student_index_in_main_array >= in_building_simulated_students.size() or student_index_in_main_array < 0: # [cite: 1]
			printerr("AcademicManager: Stale or invalid index in _add_students_to_respawn_queue. Index: ", student_index_in_main_array, " List size: ", in_building_simulated_students.size()) # [cite: 41]
			continue # [cite: 1]
		
		var student_data_to_queue: Dictionary = in_building_simulated_students[student_index_in_main_array] # [cite: 1]
		var student_id_to_check = student_data_to_queue.get("student_id") # [cite: 1]
		
		var already_in_queue = false # [cite: 1]
		for queued_student_data in _pending_respawn_queue: # [cite: 1]
			if queued_student_data.get("student_id") == student_id_to_check: # [cite: 1]
				already_in_queue = true # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["AM: Student ", student_id_to_check, " already in respawn queue. Not adding again."]) # [cite: 1]
				break # [cite: 1]
		
		if not already_in_queue: # [cite: 1]
			_pending_respawn_queue.append(student_data_to_queue) # [cite: 1]
			in_building_simulated_students.remove_at(student_index_in_main_array)  # [cite: 1]
			if DETAILED_LOGGING_ENABLED: print_debug(["AM: Student ", student_id_to_check, " moved to respawn queue. Active students: ", in_building_simulated_students.size(), ", Respawn Queue: ", _pending_respawn_queue.size()]) # [cite: 1]
			actually_added_to_queue_count +=1 # [cite: 1]
		
	if actually_added_to_queue_count > 0 and is_instance_valid(_respawn_timer) and _respawn_timer.is_stopped(): # [cite: 1]
		_respawn_timer.start() # [cite: 1]
		if DETAILED_LOGGING_ENABLED: print_debug(["AM: Respawn timer started. Queue size: ", _pending_respawn_queue.size()]) # [cite: 42]

func _sort_indices_descending(a: int, b: int) -> bool: # [cite: 1]
	return a > b # [cite: 1]

func _process_next_student_in_respawn_queue(): # [cite: 1]
	if _pending_respawn_queue.is_empty(): # [cite: 1]
		if is_instance_valid(_respawn_timer) and not _respawn_timer.is_stopped():  # [cite: 1]
			_respawn_timer.stop() # [cite: 1]
		return # [cite: 1]

	var student_data_to_respawn: Dictionary = _pending_respawn_queue.pop_front() # [cite: 1]
	if student_data_to_respawn == null:  # [cite: 1]
		printerr("AM: Popped null student_data from respawn queue.") # [cite: 1]
		if _pending_respawn_queue.is_empty() and is_instance_valid(_respawn_timer) and not _respawn_timer.is_stopped(): _respawn_timer.stop() # [cite: 1]
		return # [cite: 1]
			
	if DETAILED_LOGGING_ENABLED: print_debug(["AM: Processing respawn for student: ", student_data_to_respawn.get("student_id", "N/A_ID"), " from queue. Remaining: ", _pending_respawn_queue.size()]) # [cite: 1]
	_reinstantiate_student_from_simulation(student_data_to_respawn) # [cite: 1]

	if _pending_respawn_queue.is_empty() and is_instance_valid(_respawn_timer) and not _respawn_timer.is_stopped(): # [cite: 1]
		_respawn_timer.stop() # [cite: 1]
		if DETAILED_LOGGING_ENABLED: print_debug(["AM: Respawn queue now empty after processing. Timer stopped."]) # [cite: 43]
	elif not _pending_respawn_queue.is_empty() and is_instance_valid(_respawn_timer) and _respawn_timer.is_stopped(): # [cite: 1]
		_respawn_timer.start() # [cite: 1]


func _simulate_student_needs_update_off_map(student_data: Dictionary, duration_seconds: float): # [cite: 1]
	var activity: String = student_data.get("activity_after_despawn", "idle") # [cite: 1]
	var needs: Dictionary = student_data.get("needs")  # [cite: 1]
	var student_id_for_log = student_data.get("student_id", "N/A_ID") # [cite: 1]

	var min_need_val = ACADEMIC_MGR_STUDENT_MIN_NEED_VALUE # [cite: 1]
	var max_need_val = ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE # [cite: 1]
	
	var energy_change_rate = -0.05  # [cite: 1]
	var rest_increase_rate = 0.5 # [cite: 1]
	var study_urge_increase_rate = 0.02 # [cite: 1]
	var study_urge_decrease_rate = 0.2 # [cite: 1]

	match activity: # [cite: 1]
		"resting": # [cite: 1]
			needs["rest"] = clampf(needs.get("rest", 0.0) + rest_increase_rate * duration_seconds, min_need_val, max_need_val) # [cite: 1]
			needs["energy"] = clampf(needs.get("energy", 0.0) + rest_increase_rate * duration_seconds * 0.5, min_need_val, max_need_val) # [cite: 44]
		"studying": # [cite: 1]
			energy_change_rate = -0.1 # [cite: 1]
			needs["study_urge"] = clampf(needs.get("study_urge", 0.0) - study_urge_decrease_rate * duration_seconds, min_need_val, max_need_val) # [cite: 1]
		"in_class": # [cite: 1]
			energy_change_rate = -0.08 # [cite: 1]
			needs["study_urge"] = clampf(needs.get("study_urge", 0.0) - (study_urge_decrease_rate * 0.5) * duration_seconds, min_need_val, max_need_val) # [cite: 1]
		_:  # [cite: 1]
			if activity != "studying": # [cite: 1]
				needs["study_urge"] = clampf(needs.get("study_urge", 0.0) + study_urge_increase_rate * duration_seconds, min_need_val, max_need_val) # [cite: 1]

	if activity != "resting": # [cite: 1]
		needs["energy"] = clampf(needs.get("energy", max_need_val) + energy_change_rate * duration_seconds, min_need_val, max_need_val) # [cite: 1]

	if needs.get("energy", max_need_val) < 10.0 and activity != "resting": # [cite: 1]
		needs["rest"] = clampf(needs.get("rest", max_need_val) - 0.05 * duration_seconds, min_need_val, max_need_val) # [cite: 1]
	

func _should_student_exit_building_simulation(student_data: Dictionary, current_sim_hour: int, current_sim_minute: int, current_sim_day_str: String) -> bool: # [cite: 1]
	var activity: String = student_data.get("activity_after_despawn", "idle") # [cite: 1]
	var student_id_for_log = student_data.get("student_id", "N/A_ID") # [cite: 45]
	
	if not is_instance_valid(time_manager) and activity == "in_class": # [cite: 1]
		printerr("AM (Sim Exit Check - Modified): TimeManager is not valid for helpers needed by 'in_class' check!") # [cite: 1]
		return false  # [cite: 1]

	match activity: # [cite: 1]
		"in_class": # [cite: 1]
			var activity_target_data: Dictionary = student_data.get("activity_target_data", {}) # [cite: 1]
			var offering_id: String = activity_target_data.get("offering_id", "") # [cite: 1]
			var enrollments: Dictionary = student_data.get("current_course_enrollments", {}) # [cite: 1]

			if offering_id.is_empty() or not enrollments.has(offering_id): # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["      SIM ERROR (Exit Check M): Invalid offering_id ('", offering_id, "') or enrollment data for 'in_class' student:", student_id_for_log]) # [cite: 1]
				return true  # [cite: 1]

			var schedule_info: Dictionary = enrollments.get(offering_id, {}).get("schedule_info", {}) # [cite: 1]
			var class_start_slot_str: String = schedule_info.get("start_time_slot", "") # [cite: 1]
			var class_duration_slots: int = schedule_info.get("duration_slots", -1) # [cite: 1]
			var class_pattern_str: String = schedule_info.get("pattern", "") # [cite: 1]

			if class_start_slot_str.is_empty() or class_duration_slots <= 0 or class_pattern_str.is_empty(): # [cite: 46]
				if DETAILED_LOGGING_ENABLED: print_debug(["      SIM ERROR (Exit Check M): Invalid schedule_info (start:'", class_start_slot_str, "', duration:", class_duration_slots, ", pattern:'", class_pattern_str, "') for offering:", offering_id, "student:", student_id_for_log]) # [cite: 1]
				return true  # [cite: 1]

			var days_class_occurs_on: Array[String] = get_days_for_pattern(class_pattern_str) # [cite: 1]
			
			var class_start_hour_int: int = time_manager.time_slot_str_to_hour_int(class_start_slot_str) # [cite: 1]
			if class_start_hour_int == -1: # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["      SIM ERROR (Exit Check M): Could not parse start hour from '", class_start_slot_str, "' for student:", student_id_for_log]) # [cite: 1]
				return true # [cite: 1]

			var last_slot_hour_int = class_start_hour_int + class_duration_slots - 1 # [cite: 1]
			var target_exit_minute = 50 # [cite: 1]

			if DETAILED_LOGGING_ENABLED: # [cite: 1]
				print_debug([ # [cite: 1]
					"      EXIT CHECK (in_class) - Student:", student_id_for_log, " Offering:", offering_id, # [cite: 47]
					"Class Day Check: Current=", current_sim_day_str, "vs Scheduled=", str(days_class_occurs_on), "Match=", str(days_class_occurs_on.has(current_sim_day_str)), # [cite: 1]
					"Class Start:", class_start_slot_str, "(",class_start_hour_int, "h)", "Duration Slots:", class_duration_slots, # [cite: 1]
					"Last Slot Hour of Class:", last_slot_hour_int, "h", "Target Exit Minute:", target_exit_minute, # [cite: 1]
					"Current Sim Time:", str(current_sim_hour).pad_zeros(2) + ":" + str(current_sim_minute).pad_zeros(2) # [cite: 1]
				]) # [cite: 1]

			var should_exit = false # [cite: 1]
			if days_class_occurs_on.has(current_sim_day_str): # [cite: 1]
				if current_sim_hour == last_slot_hour_int and current_sim_minute >= target_exit_minute: # [cite: 1]
					should_exit = true # [cite: 1]
					if DETAILED_LOGGING_ENABLED: print_debug(["        DECISION (Exit @ Minute 50 Rule): Student", student_id_for_log, "for offering", offering_id, "at", str(current_sim_hour).pad_zeros(2) + ":" + str(current_sim_minute).pad_zeros(2)]) # [cite: 1]
				elif current_sim_hour > last_slot_hour_int:  # [cite: 1]
					should_exit = true # [cite: 1]
					if DETAILED_LOGGING_ENABLED: print_debug(["        DECISION (Exit Post-Hour Rule): Student", student_id_for_log, "for offering", offering_id, ". Current hour",current_sim_hour,"is past last slot hour", last_slot_hour_int]) # [cite: 49]
			
			return should_exit # [cite: 1]
		
		"resting": # [cite: 1]
			var needs: Dictionary = student_data.get("needs") # [cite: 1]
			if needs.get("rest", 0.0) >= ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE * 0.95 and \
			   needs.get("energy", 0.0) >= ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE * 0.90: # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["      DECISION (Exit Check M): Student finished resting:", student_id_for_log]) # [cite: 1]
				return true # [cite: 1]
		"studying": # [cite: 1]
			var needs: Dictionary = student_data.get("needs") # [cite: 1]
			var time_spent_simulated: float = student_data.get("time_spent_in_activity_simulated", 0.0) # [cite: 1]
			var study_duration_hours = 2  # [cite: 50]
			var max_study_time_seconds = study_duration_hours * (time_manager.seconds_per_visual_hour_slot if is_instance_valid(time_manager) else 360.0) # [cite: 1]

			if needs.get("study_urge", ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE) <= ACADEMIC_MGR_STUDENT_MIN_NEED_VALUE + 10.0 or \
			   time_spent_simulated >= max_study_time_seconds: # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["      DECISION (Exit Check M): Student finished studying:", student_id_for_log]) # [cite: 1]
				return true # [cite: 1]
	return false # [cite: 1]

func _reinstantiate_student_from_simulation(student_data_from_simulation_list: Dictionary): # [cite: 1]
	var student_id_for_log = student_data_from_simulation_list.get("student_id", "N/A_ID") # [cite: 1]
	if DETAILED_LOGGING_ENABLED: print_debug(["ATTEMPTING RE-ACTIVATION for student:", student_id_for_log]) # [cite: 1]

	if not is_instance_valid(building_manager): # [cite: 1]
		printerr("AcademicManager: BuildingManager invalid, cannot get exit position for student:", student_id_for_log) # [cite: 1]
		return # [cite: 1]
	if not is_instance_valid(time_manager): # [cite: 1]
		printerr("AcademicManager: TimeManager invalid, cannot properly re-initialize student:", student_id_for_log) # [cite: 1]
		return # [cite: 1]
	if not is_instance_valid(university_data): # [cite: 1]
		printerr("AcademicManager: UniversityData invalid, cannot properly re-initialize student:", student_id_for_log) # [cite: 1]
		return # [cite: 1]

	var student_manager_ref = get_parent().get_node_or_null("StudentManager") # [cite: 1]
	if not is_instance_valid(student_manager_ref): # [cite: 1]
		printerr("AcademicManager: StudentManager not found for re-activating student " + student_id_for_log) # [cite: 51]
		return # [cite: 1]

	var existing_student_node: Student = student_manager_ref.get_student_node_by_id(student_id_for_log) # [cite: 1]

	if not is_instance_valid(existing_student_node): # [cite: 1]
		printerr("AcademicManager: Failed to find existing student node for ID '%s'. Instantiating new." % student_id_for_log) # [cite: 52]
		if not STUDENT_SCENE or not STUDENT_SCENE.can_instantiate(): # [cite: 1]
			printerr("AcademicManager: STUDENT_SCENE is null or cannot be instantiated! Cannot create student.") # [cite: 1]
			return # [cite: 1]
		existing_student_node = STUDENT_SCENE.instantiate() as Student # [cite: 1]
		if not is_instance_valid(existing_student_node): # [cite: 1]
			printerr("AcademicManager: Fallback instantiation failed for " + student_id_for_log) # [cite: 1]
			return # [cite: 1]
		var student_parent = get_parent().get_node_or_null("Students") # [cite: 1]
		if is_instance_valid(student_parent): # [cite: 1]
			student_parent.add_child(existing_student_node) # [cite: 1]
			if DETAILED_LOGGING_ENABLED: print_debug(["Fallback: Instantiated and parented new student node for %s" % student_id_for_log]) # [cite: 1]
		else:
			printerr("AcademicManager: Fallback - Cannot find parent for new student node.") # [cite: 1]
			existing_student_node.queue_free() # [cite: 1]
			return # [cite: 1]
	
	var new_student: Student = existing_student_node # [cite: 1]

	var building_id_exited: String = student_data_from_simulation_list.get("building_id", "") # [cite: 1]
	var exit_position: Vector3 = Vector3(0, ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y, 0) # [cite: 1]

	if not building_id_exited.is_empty() and building_manager.has_method("get_building_exit_location"): # [cite: 1]
		var calculated_exit = building_manager.get_building_exit_location(building_id_exited) # [cite: 53]
		if calculated_exit != Vector3.ZERO: # [cite: 1]
			exit_position = calculated_exit # [cite: 1]
	
	new_student.global_position = exit_position # [cite: 1]
	
	var offering_id_just_finished: String = "" # [cite: 1]
	var activity_target_data = student_data_from_simulation_list.get("activity_target_data", {}) # [cite: 1]
	if student_data_from_simulation_list.get("activity_after_despawn") == "in_class" and activity_target_data is Dictionary: # [cite: 1]
		offering_id_just_finished = activity_target_data.get("offering_id", "") # [cite: 1]
	
	var current_visual_slot_when_exited: String = "" # [cite: 1]
	if is_instance_valid(time_manager): # [cite: 1]
		current_visual_slot_when_exited = time_manager.get_current_visual_time_slot_string() # [cite: 1]
	
	var restored_degree_prog_summary = student_data_from_simulation_list.get("degree_progression_summary", {}) # [cite: 1]

	new_student.initialize_new_student( # [cite: 1]
		student_data_from_simulation_list.get("student_id"), # [cite: 1]
		student_data_from_simulation_list.get("student_name"), # [cite: 1]
		student_data_from_simulation_list.get("current_program_id"), # [cite: 1]
		student_data_from_simulation_list.get("academic_start_year"), # [cite: 1]
		self, university_data, time_manager, # [cite: 1]
		offering_id_just_finished, current_visual_slot_when_exited, # [cite: 1]
		restored_degree_prog_summary # [cite: 1]
	) # [cite: 1]
	
	if is_instance_valid(student_manager_ref) and new_student.has_signal("student_despawn_data_for_manager"): # [cite: 1]
		if not new_student.is_connected("student_despawn_data_for_manager", Callable(student_manager_ref, "_on_student_node_data_update_requested")): # [cite: 1]
			new_student.student_despawn_data_for_manager.connect(Callable(student_manager_ref, "_on_student_node_data_update_requested")) # [cite: 1]
	if is_instance_valid(student_manager_ref): # [cite: 1]
		student_manager_ref.active_student_nodes_cache[new_student.student_id] = new_student # [cite: 1]

	new_student.needs = student_data_from_simulation_list.get("needs", {}).duplicate(true) # [cite: 1]
	
	var enrollments_from_data: Dictionary = student_data_from_simulation_list.get("current_course_enrollments", {}) # [cite: 55]
	
	if DETAILED_LOGGING_ENABLED: print_debug(["Re-activating student %s - Enrollments to re-confirm: %s" % [student_id_for_log, str(enrollments_from_data)]]) # [cite: 1]
	
	if is_instance_valid(new_student): # [cite: 1]
		new_student.current_course_enrollments.clear() # [cite: 1]
		for offering_id_key in enrollments_from_data: # [cite: 1]
			if enrollments_from_data[offering_id_key] is Dictionary: # [cite: 1]
				new_student.confirm_course_enrollment(offering_id_key, enrollments_from_data[offering_id_key]) # [cite: 1]
			else:
				printerr("Malformed enrollment data for offering '%s' during re-activation of student '%s'" % [offering_id_key, student_id_for_log]) # [cite: 1]

	if is_instance_valid(new_student.student_visuals): # [cite: 1]
		new_student.student_visuals.visible = true # [cite: 1]
	new_student.process_mode = Node.PROCESS_MODE_INHERIT # [cite: 1]

	if not building_id_exited.is_empty() and is_instance_valid(building_manager): # [cite: 1]
		if building_manager.has_method("student_left_functional_building"): # [cite: 1]
			building_manager.student_left_functional_building(building_id_exited) # [cite: 1]
	
	if DETAILED_LOGGING_ENABLED: print_debug(["RE-ACTIVATION COMPLETE for student: %s. Activity set to idle." % new_student.student_name]) # [cite: 56]
	new_student.set_activity("idle") # [cite: 1]
	new_student.call_deferred("on_fully_spawned_and_enrolled") # [cite: 1]
	
func ensure_student_removed_from_simulation_list(s_id: String): # [cite: 1]
	for i in range(in_building_simulated_students.size() - 1, -1, -1): # [cite: 1]
		if in_building_simulated_students[i].get("student_id") == s_id: # [cite: 1]
			in_building_simulated_students.remove_at(i) # [cite: 1]
			if DETAILED_LOGGING_ENABLED: print_debug(["Ensured removal of %s from in_building_sim_list." % s_id]) # [cite: 1]
			break # [cite: 1]
			
func _on_fall_semester_starts(year: int): # [cite: 1]
	if DETAILED_LOGGING_ENABLED: print_debug(["Fall semester started for year %d. Student enrollment/course selection should occur." % year]) # [cite: 1]
	_process_student_course_registration_for_new_semester(year, "Fall") # [cite: 1]

func _on_spring_semester_starts(year: int): # [cite: 1]
	if DETAILED_LOGGING_ENABLED: print_debug(["Spring semester started for year %d." % year]) # [cite: 1]
	_process_student_course_registration_for_new_semester(year, "Spring") # [cite: 1]

func _on_summer_semester_starts(year: int): # [cite: 1]
	if DETAILED_LOGGING_ENABLED: print_debug(["Summer semester started for year %d." % year]) # [cite: 1]
	_process_student_course_registration_for_new_semester(year, "Summer") # [cite: 1]

func _process_student_course_registration_for_new_semester(year: int, semester_name: String): # [cite: 57]
	var student_manager = get_node_or_null("/root/MainScene/StudentManager") # [cite: 1]
	if not is_instance_valid(student_manager): return # [cite: 1]
	
	for student_node in student_manager.get_all_student_nodes(): # [cite: 1]
		var student: Student = student_node as Student # [cite: 1]
		if is_instance_valid(student) and is_instance_valid(student.degree_progression): # [cite: 1]
			if student.degree_progression.is_graduated: continue # [cite: 1]

			var courses_to_take_ids: Array[String] = student.get_courses_for_current_term_from_progression() # [cite: 1]
			if DETAILED_LOGGING_ENABLED: print_debug(["Student %s needs to enroll in for %s %d: %s" % [student.student_id, semester_name, year, str(courses_to_take_ids)]]) # [cite: 1]

			for course_id_to_enroll in courses_to_take_ids: # [cite: 1]
				var already_enrolled_in_offering_for_course = false # [cite: 1]
				for existing_offering_id in student.current_course_enrollments: # [cite: 1]
					var enrollment_details = student.current_course_enrollments[existing_offering_id] # [cite: 1]
					if enrollment_details.get("course_id") == course_id_to_enroll: # [cite: 1]
						already_enrolled_in_offering_for_course = true # [cite: 1]
						break # [cite: 1]
				if already_enrolled_in_offering_for_course: # [cite: 1]
					if DETAILED_LOGGING_ENABLED: print_debug([" Student %s already has an enrollment for course %s." % [student.student_id, course_id_to_enroll]]) # [cite: 59]
					continue # [cite: 1]


				var enrolled_offering_id = find_and_enroll_student_in_offering(student.student_id, course_id_to_enroll) # [cite: 1]
				if not enrolled_offering_id.is_empty(): # [cite: 1]
					var offering_details = get_offering_details(enrolled_offering_id) # [cite: 1]
					if student.has_method("confirm_course_enrollment"): # [cite: 1]
						student.confirm_course_enrollment(enrolled_offering_id, offering_details) # [cite: 1]
					if DETAILED_LOGGING_ENABLED: print_debug([" Student %s enrolled in %s (Offering: %s) for %s %d" % [student.student_id, course_id_to_enroll, enrolled_offering_id, semester_name, year]]) # [cite: 1]
				else:
					printerr("AcademicManager: Student %s FAILED to find/enroll in %s for %s %d." % [student.student_id, course_id_to_enroll, semester_name, year]) # [cite: 1]
			
			if student.has_method("call_deferred") and student.has_method("_decide_next_activity"): # [cite: 1]
				student.call_deferred("_decide_next_activity") # [cite: 1]


func _on_academic_term_changed_for_progression(new_term_string: String, year: int): # [cite: 1]
	if DETAILED_LOGGING_ENABLED: print_debug(["Academic term changed to: %s (%d). Checking for end-of-semester processing." % [new_term_string, year]]) # [cite: 60]
	
	var term_just_ended: TimeManager.AcademicTerm = TimeManager.AcademicTerm.NONE # [cite: 1]
	var current_term_enum_from_tm = time_manager.get_current_academic_term_enum() # [cite: 1]
	
	var semester_to_process_grades_for: String = "" # [cite: 1]
	var year_of_ended_semester = year # [cite: 1]
	
	if new_term_string == "Winter Break": # [cite: 1]
		semester_to_process_grades_for = "Fall" # [cite: 1]
		if time_manager.get_current_month() == 1: year_of_ended_semester = year -1 # [cite: 73]
	elif new_term_string.begins_with("Summer Break Main"): # After Spring or potential early summer session
		# This needs to be precise based on your TimeManager's term definitions
		# Example: If Summer Break Main *always* follows Spring, and Summer Session is distinct
		semester_to_process_grades_for = "Spring" # Assuming Spring just ended
		# year_of_ended_semester would be 'year' if Spring ends in the same calendar year
	elif new_term_string == "Fall" and time_manager.get_previous_academic_term_enum() == TimeManager.AcademicTerm.SUMMER: # Fall starts after Summer session
		semester_to_process_grades_for = "Summer"
	# Add other transitions if necessary, e.g., if Summer Session leads to a different break before Fall.
	
	if not semester_to_process_grades_for.is_empty(): # [cite: 1]
		if DETAILED_LOGGING_ENABLED: print_debug(["Processing end of %s Semester, %d." % [semester_to_process_grades_for, year_of_ended_semester]]) # [cite: 1]
		_process_end_of_semester_for_all_students(semester_to_process_grades_for, year_of_ended_semester) # [cite: 1]


func _process_end_of_semester_for_all_students(ended_semester_name: String, academic_year_calendar: int): # [cite: 1]
	if DETAILED_LOGGING_ENABLED: print_debug(["--- Processing End of %s Semester, Year %d ---" % [ended_semester_name, academic_year_calendar]]) # [cite: 74]
	
	var student_manager_node = get_node_or_null("/root/MainScene/StudentManager") # Adjust path if needed
	if not is_instance_valid(student_manager_node): # [cite: 1]
		printerr("AcademicManager: StudentManager not found for end-of-semester processing.") # [cite: 1]
		return # [cite: 1]

	var all_student_data_to_process: Array[Dictionary] = [] # [cite: 1]

	# Process active student nodes
	for student_node_from_loop in student_manager_node.get_all_student_nodes(): # [cite: 1]
		var student_script: Student = student_node_from_loop as Student # [cite: 1]
		if is_instance_valid(student_script) and is_instance_valid(student_script.degree_progression): # [cite: 1]
			all_student_data_to_process.append({ # [cite: 1]
				"student_id": student_script.student_id, # [cite: 1]
				"degree_progression_node": student_script.degree_progression, # [cite: 1]
				"enrollments": student_script.current_course_enrollments.duplicate(true) # [cite: 1]
			}) # [cite: 1]
			
	# Process simulated students
	for sim_student_data_entry in in_building_simulated_students: # [cite: 1]
		var s_id_sim = sim_student_data_entry.get("student_id") # [cite: 1]
		# Check if this student was already processed (if they also had an active node temporarily)
		var already_added = false
		for processed_entry in all_student_data_to_process:
			if processed_entry.student_id == s_id_sim:
				already_added = true
				break
		if already_added: continue

		var student_instance_from_sm_sim = student_manager_node.get_student_by_id(s_id_sim) # [cite: 77]
		if is_instance_valid(student_instance_from_sm_sim) and is_instance_valid(student_instance_from_sm_sim.degree_progression): # [cite: 1]
			all_student_data_to_process.append({ # [cite: 1]
				"student_id": s_id_sim, # [cite: 1]
				"degree_progression_node": student_instance_from_sm_sim.degree_progression, # [cite: 1]
				"enrollments": sim_student_data_entry.get("current_course_enrollments", {}).duplicate(true) # [cite: 1]
			}) # [cite: 1]
		else:
			printerr("AcademicManager: Could not find degree progression for simulated student %s during end-of-semester." % s_id_sim) # [cite: 1]


	for student_entry_item in all_student_data_to_process: # [cite: 1]
		var s_id_item = student_entry_item.student_id # [cite: 1]
		var prog_node_item: DegreeProgression = student_entry_item.degree_progression_node # [cite: 1]
		var enrollments_item: Dictionary = student_entry_item.enrollments # [cite: 1]
		
		if prog_node_item.is_graduated: continue # [cite: 1]

		if DETAILED_LOGGING_ENABLED: print_debug([" Processing student: %s for end of %s %d" % [s_id_item, ended_semester_name, academic_year_calendar]]) # [cite: 1]

		var semester_string_for_record_item = "%s %d" % [ended_semester_name, academic_year_calendar] # [cite: 1]

		for offering_id_item in enrollments_item: # [cite: 1]
			var enrollment_details_item = enrollments_item[offering_id_item] # [cite: 1]
			var course_id_item = enrollment_details_item.get("course_id") # [cite: 1]
			
			# TODO: A robust check if this offering_id_item was indeed for the ended_semester_name.
			# This might involve checking offering_data.term and year if those are stored.
			# For now, assume all current enrollments are for the semester being processed if not yet graded.

			if course_id_item and not prog_node_item.has_completed_course(course_id_item): # [cite: 81]
				var grade_val = GRADE_PASS # [cite: 1]
				var course_data_from_univ_item = university_data.get_course_details(course_id_item) # [cite: 1]
				var credits_val = course_data_from_univ_item.get("credits", 0.0) # [cite: 1]
				
				prog_node_item.record_course_completion(course_id_item, grade_val, credits_val, semester_string_for_record_item, course_data_from_univ_item) # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug(["  Student %s: %s for %s (%s credits)" % [s_id_item, grade_val, course_id_item, credits_val]]) # [cite: 1]

		if prog_node_item.check_for_graduation(university_data): # [cite: 1]
			emit_signal("student_graduated", s_id_item, prog_node_item.program_id, semester_string_for_record_item) # [cite: 1]
			var student_node_to_remove_grad = student_manager_node.get_student_by_id(s_id_item) # [cite: 83]
			if is_instance_valid(student_node_to_remove_grad): # [cite: 1]
				if DETAILED_LOGGING_ENABLED: print_debug([" Student %s has graduated! Despawning." % s_id_item]) # [cite: 1]
				student_manager_node.remove_student_record_and_node(s_id_item) # Assuming a method that handles all cleanup in StudentManager
			# Also remove from in_building_simulated_students if they were there
			for i in range(in_building_simulated_students.size() -1, -1, -1): # [cite: 1]
				if in_building_simulated_students[i].get("student_id") == s_id_item: # [cite: 1]
					in_building_simulated_students.remove_at(i) # [cite: 1]
					break # [cite: 1]
		else:
			prog_node_item.advance_semester(university_data) # [cite: 1]
			
func get_courses_for_student_current_term(student: Student) -> Array[String]: # [cite: 1]
	if is_instance_valid(student) and is_instance_valid(student.degree_progression): # [cite: 1]
		return student.degree_progression.get_next_courses_to_take(university_data) # [cite: 1]
	return [] # [cite: 1]
	
# This method might be called by ProfessorManager if it has its own UI for assigning professors.
# For the new drag-and-drop UI, assign_instructor_to_pending_course is the primary path.
func set_instructor_for_offering(offering_id: String, professor_id: String): # [cite: 1]
	if course_offerings.has(offering_id): # [cite: 1]
		var offering_data = course_offerings[offering_id]
		var old_instructor = offering_data.get("instructor_id", "") # [cite: 1]
		offering_data["instructor_id"] = professor_id # [cite: 1]
		
		# If the offering becomes "scheduled" through this direct set, update status
		# and potentially populate scheduled_class_details if it wasn't already.
		if not professor_id.is_empty() and offering_data.status == "pending_professor":
			offering_data.status = "scheduled"
			# Populate scheduled_class_details if this is the final step
			if not scheduled_class_details.has(offering_id):
				scheduled_class_details[offering_id] = {
					"offering_id": offering_id,
					"course_id": offering_data.course_id,
					"course_name": offering_data.course_name,
					"program_id": offering_data.program_id,
					"classroom_id": offering_data.classroom_id,
					"pattern": offering_data.pattern,
					"day": offering_data.primary_day,
					"start_time_slot": offering_data.start_time_slot,
					"start_time_slot_index": HOURLY_TIME_SLOTS.find(offering_data.start_time_slot),
					"duration_slots": offering_data.duration_slots,
					"instructor_id": professor_id,
					"max_capacity": offering_data.max_capacity,
					"enrolled_student_ids": offering_data.enrolled_student_ids.duplicate(true)
				}
				emit_signal("class_scheduled", offering_id, scheduled_class_details[offering_id])
		elif professor_id.is_empty() and offering_data.status == "scheduled":
			# If instructor is removed, it should probably become "pending_professor" or "unscheduled"
			# This path needs careful thought - for now, assume set_instructor only sets if one is provided
			# and unassignment goes through unschedule_class or a dedicated unassign method.
			offering_data.status = "pending_professor" # Or unscheduled if all schedule info is wiped
			if scheduled_class_details.has(offering_id):
				var details_for_signal_un = scheduled_class_details.get(offering_id)
				scheduled_class_details.erase(offering_id)
				emit_signal("class_unscheduled", offering_id, details_for_signal_un)


		if DETAILED_LOGGING_ENABLED: print_debug(["Instructor for offering '%s' changed from '%s' to '%s'. Status: %s" % [offering_id, old_instructor, professor_id, offering_data.status]]) # [cite: 1]
		emit_signal("schedules_updated") # [cite: 1]
	elif DETAILED_LOGGING_ENABLED: # [cite: 1]
		print_debug(["Attempted to set instructor for non-existent/unscheduled offering '%s'" % offering_id]) # [cite: 1]

func get_instructor_for_offering(offering_id: String) -> String: # [cite: 1]
	if course_offerings.has(offering_id): # [cite: 1]
		return course_offerings[offering_id].get("instructor_id", "") # [cite: 1]
	return "" # [cite: 1]

func print_debug(message_parts): # [cite: 1]
	var final_message = "[AcademicManager]: " # [cite: 1]
	if message_parts is String: # [cite: 1]
		final_message += message_parts # [cite: 1]
	elif message_parts is Array: # [cite: 1]
		var string_array : Array = [] # [cite: 1]
		for item in message_parts: # [cite: 1]
			string_array.append(str(item)) # [cite: 1]
		final_message += String(" ").join(string_array) # [cite: 1]
	else:
		final_message += str(message_parts) # [cite: 1]
	print(final_message) # [cite: 1]
