# AcademicManager.gd
class_name AcademicManager
extends Node

signal program_unlocked(program_id: String)
signal course_offerings_updated()
signal class_scheduled(class_instance_id: String, details: Dictionary)
signal class_unscheduled(class_instance_id: String, details: Dictionary)
signal schedules_updated()
signal enrollment_changed(offering_id: String, enrolled_count: int, max_capacity: int)

# !!! IMPORTANT: Update this path to your actual student scene file !!!
const STUDENT_SCENE: PackedScene = preload("res://actors/student.tscn") 

const DETAILED_LOGGING_ENABLED: bool = true # Set true for AcademicManager's detailed logs

# --- Student Constants (ensure these match Student.gd) ---
const ACADEMIC_MGR_STUDENT_MIN_NEED_VALUE: float = 0.0
const ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE: float = 100.0
const ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y: float = 0.3 # Must match Student.EXPECTED_NAVMESH_Y

@export var university_data: UniversityData
@export var building_manager: BuildingManager
@export var time_manager: TimeManager

var program_states: Dictionary = {}
var course_offerings: Dictionary = {}
var scheduled_class_details: Dictionary = {}
var classroom_schedules: Dictionary = {}

const DAYS_OF_WEEK: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"]
const HOURLY_TIME_SLOTS: Array[String] = [
	"0800", "0900", "1000", "1100", "1200",
	"1300", "1400", "1500", "1600", "1700"
]
const DURATION_MWF: int = 1
const DURATION_TR: int = 2

var in_building_simulated_students: Array[Dictionary] = []

# --- For Staggered Re-instantiation ---
var _pending_respawn_queue: Array[Dictionary] = []
var _respawn_timer: Timer
const RESPAWN_INTERVAL: float = 0.3 # Real seconds between each student respawn (adjust as needed)


func _ready():
	if not is_instance_valid(university_data):
		university_data = get_node_or_null("/root/MainScene/UniversityDataNode") # Adjust path if needed
		if not is_instance_valid(university_data):
			printerr("AcademicManager: CRITICAL - UniversityData node not found!")
			get_tree().quit(); return
	
	if not is_instance_valid(building_manager):
		building_manager = get_node_or_null("/root/MainScene/BuildingManager") # Adjust path if needed
		if not is_instance_valid(building_manager):
			printerr("AcademicManager: Warning - BuildingManager node not found.")

	if not is_instance_valid(time_manager):
		var time_manager_path = "/root/MainScene/TimeManager" # Adjust path if needed
		time_manager = get_node_or_null(time_manager_path)
		if not is_instance_valid(time_manager):
			printerr("AcademicManager: CRITICAL - TimeManager node not found at '", time_manager_path, "'! Student simulation will not proceed.")
		else:
			if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: TimeManager found at fallback path:", time_manager_path])
			_connect_time_manager_signals()
	else:
		_connect_time_manager_signals()

	_initialize_program_states()

	# Initialize Respawn Timer
	_respawn_timer = Timer.new()
	_respawn_timer.name = "StudentRespawnTimer"
	_respawn_timer.wait_time = RESPAWN_INTERVAL
	_respawn_timer.one_shot = false # Will keep firing if timer is started and queue has items
	_respawn_timer.autostart = false
	_respawn_timer.timeout.connect(Callable(self, "_process_next_student_in_respawn_queue"))
	add_child(_respawn_timer) # Timer must be in the scene tree to work
	if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Respawn timer created and added to scene."])

	if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager ready."])


func _connect_time_manager_signals():
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
	else:
		printerr("AcademicManager: Cannot connect TimeManager signals, TimeManager is not valid.")

# --- Your Existing AcademicManager Functions Start Here ---
func _initialize_program_states():
	if not is_instance_valid(university_data): return
	var all_defined_programs_dict = university_data.PROGRAMS
	for program_id_key_str in all_defined_programs_dict.keys():
		if not program_states.has(program_id_key_str):
			program_states[program_id_key_str] = "locked"

func unlock_program(program_id: String) -> bool:
	if not is_instance_valid(university_data):
		printerr("AcademicManager: UniversityData not available for unlocking program.")
		return false
	if not university_data.PROGRAMS.has(program_id):
		printerr("AcademicManager: Attempted to unlock non-existent program '", program_id, "'.")
		return false
	
	if program_states.get(program_id) == "unlocked":
		print_debug(["Program '", program_id, "' is already unlocked."])
		return true

	var program_details_copy = university_data.get_program_details(program_id)
	var cost_to_unlock = program_details_copy.get("unlock_cost", 0)

	if cost_to_unlock > 0:
		if not is_instance_valid(building_manager):
			printerr("AcademicManager: BuildingManager not available for processing unlock cost of '", program_id, "'.")
			return false
		
		if building_manager.current_endowment < cost_to_unlock:
			print_debug(["AcademicManager: Insufficient funds to unlock program '", program_id, "'. Need: $", cost_to_unlock, ", Have: $", building_manager.current_endowment])
			return false
		
		building_manager.current_endowment -= cost_to_unlock
		if building_manager.has_method("update_financial_ui"):
			building_manager.update_financial_ui()
		print_debug(["AcademicManager: Deducted $", cost_to_unlock, " for unlocking program '", program_id, "'."])
	
	program_states[program_id] = "unlocked"
	_generate_course_offerings_for_program(program_id)
	emit_signal("program_unlocked", program_id)
	print_debug(["Program '", program_id, "' unlocked."])
	return true

func get_program_state(program_id: String) -> String:
	return program_states.get(program_id, "unknown")

func get_all_program_states() -> Dictionary:
	return program_states.duplicate(true)

func get_all_unlocked_program_ids() -> Array[String]:
	var unlocked_ids_arr: Array[String] = []
	for program_id_key_str in program_states.keys():
		if program_states[program_id_key_str] == "unlocked":
			unlocked_ids_arr.append(program_id_key_str)
	return unlocked_ids_arr

func _generate_course_offerings_for_program(program_id: String):
	if not is_instance_valid(university_data): return
	if program_states.get(program_id) != "unlocked": return

	var required_courses_list: Array[String] = university_data.get_required_courses_for_program(program_id)
	var new_offerings_were_added = false
	for course_id_val_str in required_courses_list:
		var offering_already_exists_for_program = false
		for existing_offering_id in course_offerings.keys():
			var existing_offering_details = course_offerings[existing_offering_id]
			if existing_offering_details.get("course_id") == course_id_val_str and \
				existing_offering_details.get("program_id") == program_id:
				offering_already_exists_for_program = true
				break
		
		if not offering_already_exists_for_program:
			var course_details_dict_copy = university_data.get_course_details(course_id_val_str)
			if course_details_dict_copy.is_empty():
				print_debug(["Warning: Details for course '", course_id_val_str, "' not found. Cannot create offering for program '", program_id, "'."])
				continue

			var unique_id_suffix = str(Time.get_unix_time_from_system()).right(5) + "_" + str(randi() % 10000)
			var new_offering_id_str = "offering_%s_%s_%s" % [program_id.uri_encode(), course_id_val_str.uri_encode(), unique_id_suffix]
			
			course_offerings[new_offering_id_str] = {
				"offering_id": new_offering_id_str,
				"course_id": course_id_val_str,
				"course_name": course_details_dict_copy.get("name", "N/A Course Name"),
				"program_id": program_id,
				"status": "unscheduled"
			}
			new_offerings_were_added = true
			if DETAILED_LOGGING_ENABLED: print_debug(["Generated new course offering: '", new_offering_id_str, "' for course '", course_id_val_str, "' in program '", program_id, "'."])

	if new_offerings_were_added:
		emit_signal("course_offerings_updated")

func get_unscheduled_course_offerings() -> Array[Dictionary]:
	var unscheduled_list: Array[Dictionary] = []
	for offering_id_key_str in course_offerings.keys():
		var offering_details = course_offerings[offering_id_key_str]
		if offering_details.get("status") == "unscheduled":
			unscheduled_list.append(offering_details.duplicate(true))
	return unscheduled_list

func get_available_classrooms() -> Array[Dictionary]:
	var available_classrooms_list: Array[Dictionary] = []
	if not is_instance_valid(building_manager):
		printerr("AcademicManager: BuildingManager not available to get classroom data.")
		return available_classrooms_list

	if building_manager.has_method("get_functional_buildings_data"):
		var functional_buildings: Dictionary = building_manager.get_functional_buildings_data()
		for cluster_id_str_key in functional_buildings.keys():
			var cluster_data_dict = functional_buildings[cluster_id_str_key]
			if cluster_data_dict.get("building_type") == "class":
				available_classrooms_list.append({
					"id": str(cluster_id_str_key),
					"name": "Classroom %s" % str(cluster_id_str_key).substr(0, min(5, str(cluster_id_str_key).length())),
					"capacity": cluster_data_dict.get("total_capacity", 0)
				})
	else:
		printerr("AcademicManager: BuildingManager is missing 'get_functional_buildings_data' method.")
	return available_classrooms_list

func get_classroom_capacity(classroom_id_str: String) -> int:
	if not is_instance_valid(building_manager) or not building_manager.has_method("get_functional_buildings_data"):
		printerr("AcademicManager: BuildingManager not available to get capacity for classroom '", classroom_id_str, "'.")
		return 0
	
	var functional_buildings: Dictionary = building_manager.get_functional_buildings_data()
	if functional_buildings.has(classroom_id_str):
		var cluster_data_dict = functional_buildings[classroom_id_str]
		if cluster_data_dict.get("building_type") == "class":
			return cluster_data_dict.get("total_capacity", 0)
		else:
			if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Building '", classroom_id_str, "' is not of type 'class'. Cannot get classroom capacity."])
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Classroom ID '", classroom_id_str, "' not found in functional buildings data."])
	return 0

func is_slot_available(classroom_id: String, primary_day: String, start_time_slot_str_val: String) -> bool:
	if not (primary_day == "Mon" or primary_day == "Tue"):
		printerr("AcademicManager: Invalid primary_day '", primary_day, "' for is_slot_available. Must be 'Mon' or 'Tue'.")
		return false
		
	var days_to_check_in_pattern: Array[String] = []
	var duration_for_this_pattern_slots: int = 0
	
	if primary_day == "Mon":
		days_to_check_in_pattern = ["Mon", "Wed", "Fri"]
		duration_for_this_pattern_slots = DURATION_MWF
	elif primary_day == "Tue":
		days_to_check_in_pattern = ["Tue", "Thu"]
		duration_for_this_pattern_slots = DURATION_TR
	
	for day_str_in_pattern in days_to_check_in_pattern:
		if not _is_single_day_slot_available(classroom_id, day_str_in_pattern, start_time_slot_str_val, duration_for_this_pattern_slots):
			return false
	return true

func _is_single_day_slot_available(classroom_id: String, day_to_check_str: String, start_time_slot_str_val: String, duration_in_slots_val: int) -> bool:
	if not DAYS_OF_WEEK.has(day_to_check_str) or not HOURLY_TIME_SLOTS.has(start_time_slot_str_val):
		printerr("AcademicManager (_is_single_day): Invalid day '", day_to_check_str, "' or time slot '", start_time_slot_str_val, "'.")
		return false

	var classroom_schedule_for_day: Dictionary = classroom_schedules.get(classroom_id, {}).get(day_to_check_str, {})
	var start_slot_idx_val = HOURLY_TIME_SLOTS.find(start_time_slot_str_val)

	if start_slot_idx_val == -1:
		printerr("AcademicManager (_is_single_day): Could not find index for start_time_slot '", start_time_slot_str_val, "'.")
		return false

	for i in range(duration_in_slots_val):
		var current_slot_index_to_check = start_slot_idx_val + i
		if current_slot_index_to_check >= HOURLY_TIME_SLOTS.size():
			return false
		
		var time_slot_key_to_check_str = HOURLY_TIME_SLOTS[current_slot_index_to_check]
		if classroom_schedule_for_day.has(time_slot_key_to_check_str):
			return false
			
	return true

func schedule_class(offering_id: String, classroom_id: String, primary_day_arg: String, start_time_slot_str_arg: String, selected_instructor_id: String = "") -> bool:
	if not course_offerings.has(offering_id):
		printerr("Failed to schedule: Offering '", offering_id, "' not found.")
		return false
	
	var day_pattern_to_schedule_str = ""
	var duration_slots_for_pattern = 0
	if primary_day_arg == "Mon":
		day_pattern_to_schedule_str = "MWF"
		duration_slots_for_pattern = DURATION_MWF
	elif primary_day_arg == "Tue":
		day_pattern_to_schedule_str = "TR"
		duration_slots_for_pattern = DURATION_TR
	else:
		printerr("Failed to schedule: Invalid primary_day '", primary_day_arg, "'. Must be 'Mon' or 'Tue'.")
		return false

	var start_time_slot_idx_val = HOURLY_TIME_SLOTS.find(start_time_slot_str_arg)
	if start_time_slot_idx_val == -1:
		printerr("Failed to schedule: Invalid start_time_slot string '", start_time_slot_str_arg, "'.")
		return false
		
	if start_time_slot_idx_val + duration_slots_for_pattern > HOURLY_TIME_SLOTS.size():
		printerr("Failed to schedule: Class duration for pattern '", day_pattern_to_schedule_str, "' exceeds available time slots for offering '", offering_id, "'.")
		return false
	
	if not is_slot_available(classroom_id, primary_day_arg, start_time_slot_str_arg):
		print_debug(["Failed to schedule (from schedule_class): Slot not available for offering '", offering_id, "' in '", classroom_id, "' on '", primary_day_arg, "' at '", start_time_slot_str_arg, "'."])
		return false

	var offering_data_ref = course_offerings[offering_id]
	var course_data_copy = university_data.get_course_details(offering_data_ref.course_id)
	var class_actual_max_capacity = get_classroom_capacity(classroom_id)

	if class_actual_max_capacity <= 0:
		printerr("Failed to schedule: Classroom '", classroom_id, "' has zero or invalid capacity (", class_actual_max_capacity, ").")
		return false

	scheduled_class_details[offering_id] = {
		"offering_id": offering_id,
		"course_id": offering_data_ref.course_id,
		"course_name": course_data_copy.get("name", "N/A"),
		"program_id": offering_data_ref.get("program_id"),
		"classroom_id": classroom_id,
		"pattern": day_pattern_to_schedule_str, 
		"day": primary_day_arg, 
		"start_time_slot": start_time_slot_str_arg,
		"start_time_slot_index": start_time_slot_idx_val,
		"duration_slots": duration_slots_for_pattern,
		"instructor_id": selected_instructor_id,
		"max_capacity": class_actual_max_capacity,
		"enrolled_student_ids": []
	}
	
	var days_to_book_on_schedule: Array[String] = []
	if day_pattern_to_schedule_str == "MWF": days_to_book_on_schedule = ["Mon", "Wed", "Fri"]
	elif day_pattern_to_schedule_str == "TR": days_to_book_on_schedule = ["Tue", "Thu"]

	for day_str_schedule_key in days_to_book_on_schedule:
		if not classroom_schedules.has(classroom_id): classroom_schedules[classroom_id] = {}
		if not classroom_schedules[classroom_id].has(day_str_schedule_key): classroom_schedules[classroom_id][day_str_schedule_key] = {}
		for i in range(duration_slots_for_pattern):
			var current_slot_idx = start_time_slot_idx_val + i
			classroom_schedules[classroom_id][day_str_schedule_key][HOURLY_TIME_SLOTS[current_slot_idx]] = offering_id

	offering_data_ref.status = "scheduled"
	
	emit_signal("class_scheduled", offering_id, scheduled_class_details[offering_id])
	emit_signal("schedules_updated")
	emit_signal("course_offerings_updated")
	emit_signal("enrollment_changed", offering_id, 0, class_actual_max_capacity)
	if DETAILED_LOGGING_ENABLED: print_debug(["Class '", offering_id, "' (", offering_data_ref.course_name, ") scheduled successfully in '", classroom_id, "' for pattern '", day_pattern_to_schedule_str, "'."])
	return true

func unschedule_class(offering_id_to_remove: String) -> bool: 
	if not scheduled_class_details.has(offering_id_to_remove):
		printerr("Cannot unschedule: Offering '", offering_id_to_remove, "' not found in scheduled classes.")
		if course_offerings.has(offering_id_to_remove) and course_offerings[offering_id_to_remove].status == "scheduled":
			course_offerings[offering_id_to_remove].status = "unscheduled"
			emit_signal("course_offerings_updated")
			if DETAILED_LOGGING_ENABLED: print_debug(["Corrected status for offering '", offering_id_to_remove, "' to unscheduled as details were missing."])
		return false 

	var sch_details_copy = scheduled_class_details[offering_id_to_remove].duplicate(true)
	var classroom_id_val = sch_details_copy.classroom_id
	var day_pattern_val = sch_details_copy.pattern
	var start_slot_index_val = sch_details_copy.start_time_slot_index
	var duration_val = sch_details_copy.duration_slots
	var enrolled_students_count = sch_details_copy.enrolled_student_ids.size()

	var days_to_clear_from_schedule: Array[String] = []
	if day_pattern_val == "MWF": days_to_clear_from_schedule = ["Mon", "Wed", "Fri"]
	elif day_pattern_val == "TR": days_to_clear_from_schedule = ["Tue", "Thu"]

	if start_slot_index_val != -1:
		for day_str_key_val in days_to_clear_from_schedule:
			if classroom_schedules.has(classroom_id_val) and classroom_schedules[classroom_id_val].has(day_str_key_val):
				var day_schedule_map_ref = classroom_schedules[classroom_id_val][day_str_key_val]
				for i in range(duration_val):
					var current_slot_idx_to_clear = start_slot_index_val + i
					if current_slot_idx_to_clear < HOURLY_TIME_SLOTS.size():
						var time_slot_key_str = HOURLY_TIME_SLOTS[current_slot_idx_to_clear]
						if day_schedule_map_ref.get(time_slot_key_str) == offering_id_to_remove:
							day_schedule_map_ref.erase(time_slot_key_str)
				
				if day_schedule_map_ref.is_empty():
					classroom_schedules[classroom_id_val].erase(day_str_key_val)
			
			if classroom_schedules.has(classroom_id_val) and classroom_schedules[classroom_id_val].is_empty():
				classroom_schedules.erase(classroom_id_val)
	
	if course_offerings.has(offering_id_to_remove):
		course_offerings[offering_id_to_remove].status = "unscheduled"
	
	scheduled_class_details.erase(offering_id_to_remove)
	
	emit_signal("class_unscheduled", offering_id_to_remove, sch_details_copy)
	emit_signal("schedules_updated")
	emit_signal("course_offerings_updated")
	emit_signal("enrollment_changed", offering_id_to_remove, 0, sch_details_copy.get("max_capacity", 0))
	if DETAILED_LOGGING_ENABLED: print_debug(["Class '", offering_id_to_remove, "' unscheduled successfully."])
	
	if enrolled_students_count > 0:
		if DETAILED_LOGGING_ENABLED: print_debug(["Warning: Unscheduled class '", offering_id_to_remove, "' had ", enrolled_students_count, " students. They need to be handled (e.g., auto-dropped, informed)."])
	return true

func enroll_student_in_offering(offering_id: String, student_id: String) -> bool:
	if not scheduled_class_details.has(offering_id):
		printerr("AcademicManager: Cannot enroll student '", student_id, "'. Offering '", offering_id, "' is not scheduled or does not exist.")
		return false
	var sch_details_ref = scheduled_class_details[offering_id]
	if not sch_details_ref.has("enrolled_student_ids") or not sch_details_ref.has("max_capacity"):
		printerr("AcademicManager: Offering '", offering_id, "' has malformed schedule details. Cannot enroll student.")
		return false
	if sch_details_ref.enrolled_student_ids.size() >= sch_details_ref.max_capacity:
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Cannot enroll student '", student_id, "'. Offering '", offering_id, "' is full."])
		return false
	if sch_details_ref.enrolled_student_ids.has(student_id):
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' is already enrolled in offering '", offering_id, "'."])
		return true
	sch_details_ref.enrolled_student_ids.append(student_id)
	emit_signal("enrollment_changed", offering_id, sch_details_ref.enrolled_student_ids.size(), sch_details_ref.max_capacity)
	emit_signal("schedules_updated") 
	if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' enrolled in offering '", offering_id, "'. Total: ", sch_details_ref.enrolled_student_ids.size()])
	return true

func drop_student_from_offering(offering_id: String, student_id: String) -> bool:
	if not scheduled_class_details.has(offering_id):
		printerr("AcademicManager: Cannot drop student '", student_id, "'. Offering '", offering_id, "' is not scheduled.")
		return false
	var sch_details_ref = scheduled_class_details[offering_id]
	if not sch_details_ref.has("enrolled_student_ids"):
		printerr("AcademicManager: Offering '", offering_id, "' has malformed schedule details. Cannot drop.")
		return false
	if sch_details_ref.enrolled_student_ids.has(student_id):
		sch_details_ref.enrolled_student_ids.erase(student_id)
		emit_signal("enrollment_changed", offering_id, sch_details_ref.enrolled_student_ids.size(), sch_details_ref.max_capacity)
		emit_signal("schedules_updated")
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' dropped from '", offering_id, "'. Total: ", sch_details_ref.enrolled_student_ids.size()])
		return true
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["AcademicManager: Student '", student_id, "' not found in '", offering_id, "'. Cannot drop."])
		return false

func get_offering_enrollment(offering_id: String) -> Dictionary:
	if scheduled_class_details.has(offering_id):
		var details = scheduled_class_details[offering_id]
		if details.has("enrolled_student_ids") and details.has("max_capacity"):
			return {
				"enrolled_count": details.enrolled_student_ids.size(),
				"max_capacity": details.max_capacity,
				"student_ids": details.enrolled_student_ids.duplicate(true)
			}
	return {"enrolled_count": 0, "max_capacity": 0, "student_ids": []}

func calculate_new_student_intake_capacity() -> int:
	if not is_instance_valid(university_data): printerr("Capacity Calc: UniversityData not valid."); return 0
	var total_available_seats: int = 0
	var unlocked_prog_ids_list = get_all_unlocked_program_ids()
	var unique_freshman_first_sem_courses_dict: Dictionary = {}
	for prog_id_val in unlocked_prog_ids_list:
		var curriculum_data = university_data.get_program_curriculum_structure(prog_id_val)
		if curriculum_data.has("Freshman Year"):
			var freshman_year_dict: Dictionary = curriculum_data["Freshman Year"]
			if freshman_year_dict.has("First Semester"):
				var first_sem_course_id_list: Array = freshman_year_dict["First Semester"]
				for course_id_item_val in first_sem_course_id_list:
					if course_id_item_val is String: unique_freshman_first_sem_courses_dict[course_id_item_val] = true
	if unique_freshman_first_sem_courses_dict.is_empty(): 
		if DETAILED_LOGGING_ENABLED: print_debug(["Capacity Calc: No unique Freshman/1st Sem courses in curricula."])
		return 0
	for course_id_for_calc in unique_freshman_first_sem_courses_dict.keys():
		for offering_id_sch_key in scheduled_class_details.keys():
			var sch_details_dict = scheduled_class_details[offering_id_sch_key]
			if sch_details_dict.get("course_id") == course_id_for_calc:
				var enrolled_students_array: Array = sch_details_dict.get("enrolled_student_ids", [])
				var available_in_this_one = sch_details_dict.get("max_capacity", 0) - enrolled_students_array.size()
				if available_in_this_one > 0: total_available_seats += available_in_this_one
	if DETAILED_LOGGING_ENABLED: print_debug(["Total intake capacity: %d seats." % total_available_seats])
	return total_available_seats

func get_freshman_first_semester_courses(program_id: String) -> Array[String]:
	if not is_instance_valid(university_data): return []
	var curriculum_data = university_data.get_program_curriculum_structure(program_id)
	var courses_to_return_list: Array[String] = []
	if curriculum_data.has("Freshman Year"):
		var freshman_year_dict: Dictionary = curriculum_data["Freshman Year"]
		if freshman_year_dict.has("First Semester"):
			var course_list_from_structure: Array = freshman_year_dict["First Semester"]
			for item_val in course_list_from_structure:
				if item_val is String: courses_to_return_list.append(item_val)
	if courses_to_return_list.is_empty() and program_states.get(program_id) == "unlocked":
		if DETAILED_LOGGING_ENABLED: print_debug(["Warning: No Freshman/1st Sem courses in curriculum for '", program_id, "'."])
	return courses_to_return_list

func find_and_enroll_student_in_offering(student_id: String, course_id_to_enroll: String) -> String:
	var best_offering_id_to_enroll: String = ""
	var max_available_seats_in_best_offering = 0
	for offering_id_candidate in scheduled_class_details.keys():
		var offering_sch_details_dict = scheduled_class_details[offering_id_candidate]
		if offering_sch_details_dict.get("course_id") == course_id_to_enroll:
			var enrolled_students_list: Array = offering_sch_details_dict.get("enrolled_student_ids", [])
			var current_available_seats = offering_sch_details_dict.get("max_capacity", 0) - enrolled_students_list.size()
			if current_available_seats > 0:
				if current_available_seats > max_available_seats_in_best_offering: # Prioritize offerings with more seats
					max_available_seats_in_best_offering = current_available_seats
					best_offering_id_to_enroll = offering_id_candidate
				elif best_offering_id_to_enroll.is_empty(): # If no best yet, take the first available
					best_offering_id_to_enroll = offering_id_candidate


	if not best_offering_id_to_enroll.is_empty():
		var enrollment_success = enroll_student_in_offering(best_offering_id_to_enroll, student_id)
		if enrollment_success:
			if DETAILED_LOGGING_ENABLED: print_debug(["Student '", student_id, "' auto-enrolled in '", course_id_to_enroll, "' (Offering: '", best_offering_id_to_enroll, "')."])
			return best_offering_id_to_enroll
		else:
			printerr("Student '", student_id, "' FAILED auto-enroll in '", course_id_to_enroll, "' (Offering: '", best_offering_id_to_enroll, "').")
	else:
		if DETAILED_LOGGING_ENABLED: print_debug(["No available offering for student '", student_id, "' in course '", course_id_to_enroll, "'."])
	return ""

func get_offering_details(offering_id: String) -> Dictionary:
	if course_offerings.has(offering_id):
		var base_details = course_offerings[offering_id].duplicate(true)
		var is_scheduled = false
		if scheduled_class_details.has(offering_id):
			var sch_details_copy = scheduled_class_details[offering_id].duplicate(true)
			if DETAILED_LOGGING_ENABLED: print_debug(["AM.get_offering_details: Merging scheduled details for", offering_id, ". Pattern in sch_details_copy:", sch_details_copy.get("pattern", "NOT FOUND IN SCH_DETAILS")])
			base_details.merge(sch_details_copy, true) 
			base_details.status = "scheduled"
			is_scheduled = true
		
		if DETAILED_LOGGING_ENABLED: print_debug(["AM.get_offering_details: Returning for", offering_id, "Is Scheduled:", is_scheduled, "Final pattern value:", base_details.get("pattern", "NOT FOUND IN FINAL")])
		return base_details
	
	if DETAILED_LOGGING_ENABLED: print_debug(["AM.get_offering_details: Offering ID not found:", offering_id])
	return {}

func get_schedule_for_classroom(classroom_id: String) -> Dictionary:
	if classroom_schedules.has(classroom_id):
		return classroom_schedules[classroom_id].duplicate(true)
	return {}

func get_days_for_pattern(pattern_str: String) -> Array[String]: 
	if pattern_str == "MWF": return ["Mon", "Wed", "Fri"]
	if pattern_str == "TR": return ["Tue", "Thu"]
	if DETAILED_LOGGING_ENABLED and not pattern_str.is_empty(): print_debug(["Warning: Unknown pattern '", pattern_str, "' in get_days_for_pattern."])
	return []
	
func get_classroom_location(classroom_id_str: String) -> Vector3:
	var nav_y = ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y

	# if DETAILED_LOGGING_ENABLED: print_debug(["AM: get_classroom_location CALLED for classroom_id: '", classroom_id_str, "'."]) # Can be too spammy
	if not is_instance_valid(building_manager):
		printerr("AM: BuildingManager not available for classroom location: ", classroom_id_str)
		return Vector3.ZERO

	if building_manager.has_method("get_functional_buildings_data"):
		var functional_buildings: Dictionary = building_manager.get_functional_buildings_data()
		if functional_buildings.has(classroom_id_str):
			var classroom_cluster_data = functional_buildings[classroom_id_str]

			if classroom_cluster_data.get("building_type") == "class":
				var current_physical_users = classroom_cluster_data.get("current_users", 0)
				var total_physical_capacity = classroom_cluster_data.get("total_capacity", 0)
				
				if total_physical_capacity > 0 and current_physical_users >= total_physical_capacity:
					if DETAILED_LOGGING_ENABLED: print_debug(["AM: Classroom '", classroom_id_str, "' is PHYSICALLY FULL (BM users: ", current_physical_users, "/", total_physical_capacity, "). Returning no location."])
					return Vector3.ZERO 
				
				var rep_node = classroom_cluster_data.get("representative_block_node")
				if is_instance_valid(rep_node) and rep_node is Node3D:
					var base_position = rep_node.global_position
					
					var random_offset_x: float = randf_range(-0.4, 0.4) # Small jitter for entry points
					var random_offset_z: float = randf_range(-0.4, 0.4)
					var student_specific_target = Vector3(base_position.x + random_offset_x,
														nav_y, 
														base_position.z + random_offset_z)
					# This log was identified as spammy, ensure it's off if not needed for this specific debug:
					# if DETAILED_LOGGING_ENABLED: print_debug(["AM: Rep node for classroom '", classroom_id_str, "'. Student-specific Nav target (Y: ", nav_y, ", offset): ", str(student_specific_target.round()), "."])
					return student_specific_target
				else:
					if DETAILED_LOGGING_ENABLED: print_debug(["AM: Classroom cluster '", classroom_id_str, "' has NO valid representative_block_node."])
			else:
				if DETAILED_LOGGING_ENABLED: print_debug(["AM: Building cluster '", classroom_id_str, "' is NOT 'class'. Actual: ", classroom_cluster_data.get("building_type")])
		else:
			if DETAILED_LOGGING_ENABLED: print_debug(["AM: Classroom ID '", classroom_id_str, "' NOT FOUND in functional_buildings. Keys: ", str(functional_buildings.keys())])
	else:
		printerr("AM: BuildingManager missing 'get_functional_buildings_data'.")

	if DETAILED_LOGGING_ENABLED: print_debug(["AM: get_classroom_location returning Vector3.ZERO for classroom_id: '", classroom_id_str, "'."])
	return Vector3.ZERO

func print_debug(message_parts):
	var final_message = "[AcademicManager]: "
	if message_parts is String: # Check type directly
		final_message += message_parts
	elif message_parts is Array: # Godot 4 uses 'Array' for generic arrays
		var string_array : Array = [] # Can be Array or Array[String]
		for item in message_parts:
			string_array.append(str(item))
		final_message += String(" ").join(string_array)
	else:
		final_message += str(message_parts)
	print(final_message)
# --- END OF YOUR EXISTING AcademicManager FUNCTIONS ---

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# --- LOGIC FOR MANAGING DESPAWNED (IN-BUILDING) STUDENTS (With Staggered Respawn) ---
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

func _on_student_despawned(data: Dictionary):
	if DETAILED_LOGGING_ENABLED: 
		print_debug(["_on_student_despawned CALLED. Student ID:", data.get("student_id", "N/A_ID"), 
					 "Activity:", data.get("activity_after_despawn", "N/A_Activity")])
					 # Removed full data print for brevity, can be re-added if needed: ", Data received:", data
	data["time_spent_in_activity_simulated"] = 0.0 
	in_building_simulated_students.append(data)

func _on_visual_hour_slot_changed_simulation_update(day_str: String, time_slot_str: String):
	if DETAILED_LOGGING_ENABLED: 
		print_debug(["_on_visual_hour_slot_changed_simulation_update (TOP OF HOUR) CALLED. Day:", day_str, "Slot:", time_slot_str,
					 "In-building students count:", in_building_simulated_students.size()])
	if not is_instance_valid(time_manager):
		printerr("AcademicManager: TimeManager invalid in _on_visual_hour_slot_changed_simulation_update.")
		return
	
	var seconds_per_slot = time_manager.seconds_per_visual_hour_slot
	var current_sim_hour = time_manager.time_slot_str_to_hour_int(time_slot_str) 
	var current_sim_minute = 0 

	var students_to_queue_indices: Array[int] = []

	for i in range(in_building_simulated_students.size()):
		var student_data: Dictionary = in_building_simulated_students[i]
		var student_id_for_log = student_data.get("student_id", "N/A_ID")
		
		_simulate_student_needs_update_off_map(student_data, seconds_per_slot) 
		student_data["time_spent_in_activity_simulated"] += seconds_per_slot
		if DETAILED_LOGGING_ENABLED: print_debug(["  Needs & TimeSim updated for:", student_id_for_log, "New TimeSim:", student_data["time_spent_in_activity_simulated"]])
		
		var activity_type = student_data.get("activity_after_despawn")
		var should_check_exit_this_hour = false
		if activity_type != "in_class": 
			should_check_exit_this_hour = true
		elif activity_type == "in_class": 
			var target_data: Dictionary = student_data.get("activity_target_data", {})
			var offering_id: String = target_data.get("offering_id", "")
			var sch_info: Dictionary = {}
			var student_enrollments = student_data.get("current_course_enrollments") # This is a Dictionary
			
			if student_enrollments is Dictionary and student_enrollments.has(offering_id) :
				var enrollment_entry = student_enrollments.get(offering_id) # Get value for offering_id
				if enrollment_entry is Dictionary and enrollment_entry.has("schedule_info"):
					sch_info = enrollment_entry.get("schedule_info")
			
			if not sch_info.is_empty():
				var class_start_hour_val = time_manager.time_slot_str_to_hour_int(sch_info.get("start_time_slot","0000"))
				var class_duration_val = sch_info.get("duration_slots",1)
				if class_start_hour_val != -1 and current_sim_hour > (class_start_hour_val + class_duration_val - 1) : 
					should_check_exit_this_hour = true
			elif DETAILED_LOGGING_ENABLED: 
				print_debug(["AM: Hourly check for class ", offering_id if not offering_id.is_empty() else "Unknown Offering", " - could not get valid schedule_info for failsafe."])

		if should_check_exit_this_hour:
			if _should_student_exit_building_simulation(student_data, current_sim_hour, current_sim_minute, day_str):
				students_to_queue_indices.append(i)
				if DETAILED_LOGGING_ENABLED: print_debug(["    Student (hourly check) MARKED for respawn queue:", student_id_for_log])
	
	if not students_to_queue_indices.is_empty():
		_add_students_to_respawn_queue(students_to_queue_indices)


func _on_simulation_time_ticked_for_student_checks(day_str: String, hour_int: int, minute_int: int, visual_slot_str: String):
	if DETAILED_LOGGING_ENABLED and minute_int % 15 == 0 and minute_int != 0 : # Log less frequently, not at top of hour
		print_debug(["AM: Time ticked to Day:", day_str, "Time:", str(hour_int).pad_zeros(2) + ":" + str(minute_int).pad_zeros(2), "Slot:", visual_slot_str, "Checking class exits for",in_building_simulated_students.size(), "students."])

	if in_building_simulated_students.is_empty():
		return

	var students_to_queue_indices: Array[int] = []
	for i in range(in_building_simulated_students.size()):
		var student_data: Dictionary = in_building_simulated_students[i]
		
		if student_data.get("activity_after_despawn") == "in_class":
			if _should_student_exit_building_simulation(student_data, hour_int, minute_int, day_str):
				students_to_queue_indices.append(i)
				if DETAILED_LOGGING_ENABLED: print_debug(["    Student (minute check for class exit) MARKED for respawn queue:", student_data.get("student_id", "N/A_ID")])
	
	if not students_to_queue_indices.is_empty():
		_add_students_to_respawn_queue(students_to_queue_indices)

func _add_students_to_respawn_queue(indices_from_active_list: Array[int]):
	if indices_from_active_list.is_empty():
		return

	indices_from_active_list.sort_custom(Callable(self, "_sort_indices_descending"))

	var actually_added_to_queue_count = 0
	for student_index_in_main_array in indices_from_active_list:
		if student_index_in_main_array >= in_building_simulated_students.size() or student_index_in_main_array < 0:
			printerr("AcademicManager: Stale or invalid index in _add_students_to_respawn_queue. Index: ", student_index_in_main_array, " List size: ", in_building_simulated_students.size())
			continue
		
		var student_data_to_queue: Dictionary = in_building_simulated_students[student_index_in_main_array]
		var student_id_to_check = student_data_to_queue.get("student_id")
		
		var already_in_queue = false
		for queued_student_data in _pending_respawn_queue:
			if queued_student_data.get("student_id") == student_id_to_check:
				already_in_queue = true
				if DETAILED_LOGGING_ENABLED: print_debug(["AM: Student ", student_id_to_check, " already in respawn queue. Not adding again."])
				break
		
		if not already_in_queue:
			_pending_respawn_queue.append(student_data_to_queue)
			in_building_simulated_students.remove_at(student_index_in_main_array) 
			if DETAILED_LOGGING_ENABLED: print_debug(["AM: Student ", student_id_to_check, " moved to respawn queue. Active students: ", in_building_simulated_students.size(), ", Respawn Queue: ", _pending_respawn_queue.size()])
			actually_added_to_queue_count +=1
		
	if actually_added_to_queue_count > 0 and is_instance_valid(_respawn_timer) and _respawn_timer.is_stopped():
		_respawn_timer.start()
		if DETAILED_LOGGING_ENABLED: print_debug(["AM: Respawn timer started. Queue size: ", _pending_respawn_queue.size()])

func _sort_indices_descending(a: int, b: int) -> bool:
	return a > b

func _process_next_student_in_respawn_queue():
	if _pending_respawn_queue.is_empty():
		if is_instance_valid(_respawn_timer) and not _respawn_timer.is_stopped(): 
			_respawn_timer.stop()
		return

	var student_data_to_respawn: Dictionary = _pending_respawn_queue.pop_front()
	if student_data_to_respawn == null: 
		printerr("AM: Popped null student_data from respawn queue.")
		if _pending_respawn_queue.is_empty() and is_instance_valid(_respawn_timer) and not _respawn_timer.is_stopped(): _respawn_timer.stop()
		return
			
	if DETAILED_LOGGING_ENABLED: print_debug(["AM: Processing respawn for student: ", student_data_to_respawn.get("student_id", "N/A_ID"), " from queue. Remaining: ", _pending_respawn_queue.size()])
	_reinstantiate_student_from_simulation(student_data_to_respawn)

	if _pending_respawn_queue.is_empty() and is_instance_valid(_respawn_timer) and not _respawn_timer.is_stopped():
		_respawn_timer.stop()
		if DETAILED_LOGGING_ENABLED: print_debug(["AM: Respawn queue now empty after processing. Timer stopped."])
	elif not _pending_respawn_queue.is_empty() and is_instance_valid(_respawn_timer) and _respawn_timer.is_stopped():
		_respawn_timer.start() # Ensure timer keeps running if there's more in queue


func _simulate_student_needs_update_off_map(student_data: Dictionary, duration_seconds: float):
	var activity: String = student_data.get("activity_after_despawn", "idle")
	var needs: Dictionary = student_data.get("needs") 
	var student_id_for_log = student_data.get("student_id", "N/A_ID")

	var min_need_val = ACADEMIC_MGR_STUDENT_MIN_NEED_VALUE
	var max_need_val = ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE
	
	# Removed per-call detailed logging for needs before/after as it's very spammy
	# if DETAILED_LOGGING_ENABLED: print_debug(["    SIMULATE NEEDS (BEFORE) - Student:", student_id_for_log, "Activity:", activity, "Needs:", needs.duplicate(true)])

	var energy_change_rate = -0.05 
	var rest_increase_rate = 0.5
	var study_urge_increase_rate = 0.02
	var study_urge_decrease_rate = 0.2

	match activity:
		"resting":
			needs["rest"] = clampf(needs.get("rest", 0.0) + rest_increase_rate * duration_seconds, min_need_val, max_need_val)
			needs["energy"] = clampf(needs.get("energy", 0.0) + rest_increase_rate * duration_seconds * 0.5, min_need_val, max_need_val)
		"studying":
			energy_change_rate = -0.1
			needs["study_urge"] = clampf(needs.get("study_urge", 0.0) - study_urge_decrease_rate * duration_seconds, min_need_val, max_need_val)
		"in_class":
			energy_change_rate = -0.08
			needs["study_urge"] = clampf(needs.get("study_urge", 0.0) - (study_urge_decrease_rate * 0.5) * duration_seconds, min_need_val, max_need_val)
		_: 
			if activity != "studying":
				needs["study_urge"] = clampf(needs.get("study_urge", 0.0) + study_urge_increase_rate * duration_seconds, min_need_val, max_need_val)

	if activity != "resting":
		needs["energy"] = clampf(needs.get("energy", max_need_val) + energy_change_rate * duration_seconds, min_need_val, max_need_val)

	if needs.get("energy", max_need_val) < 10.0 and activity != "resting":
		needs["rest"] = clampf(needs.get("rest", max_need_val) - 0.05 * duration_seconds, min_need_val, max_need_val)
	
	# if DETAILED_LOGGING_ENABLED: print_debug(["    SIMULATE NEEDS (AFTER) - Student:", student_id_for_log, "Needs:", needs.duplicate(true)])


func _should_student_exit_building_simulation(student_data: Dictionary, current_sim_hour: int, current_sim_minute: int, current_sim_day_str: String) -> bool:
	var activity: String = student_data.get("activity_after_despawn", "idle")
	var student_id_for_log = student_data.get("student_id", "N/A_ID")
	
	if not is_instance_valid(time_manager) and activity == "in_class": # TimeManager is needed for time_slot_str_to_hour_int
		printerr("AM (Sim Exit Check - Modified): TimeManager is not valid for helpers needed by 'in_class' check!")
		return false 

	match activity:
		"in_class":
			var activity_target_data: Dictionary = student_data.get("activity_target_data", {})
			var offering_id: String = activity_target_data.get("offering_id", "")
			var enrollments: Dictionary = student_data.get("current_course_enrollments", {})

			if offering_id.is_empty() or not enrollments.has(offering_id):
				if DETAILED_LOGGING_ENABLED: print_debug(["      SIM ERROR (Exit Check M): Invalid offering_id ('", offering_id, "') or enrollment data for 'in_class' student:", student_id_for_log])
				return true 

			var schedule_info: Dictionary = enrollments.get(offering_id, {}).get("schedule_info", {})
			var class_start_slot_str: String = schedule_info.get("start_time_slot", "")
			var class_duration_slots: int = schedule_info.get("duration_slots", -1)
			var class_pattern_str: String = schedule_info.get("pattern", "")

			if class_start_slot_str.is_empty() or class_duration_slots <= 0 or class_pattern_str.is_empty():
				if DETAILED_LOGGING_ENABLED: print_debug(["      SIM ERROR (Exit Check M): Invalid schedule_info (start:'", class_start_slot_str, "', duration:", class_duration_slots, ", pattern:'", class_pattern_str, "') for offering:", offering_id, "student:", student_id_for_log])
				return true 

			var days_class_occurs_on: Array[String] = get_days_for_pattern(class_pattern_str)
			
			var class_start_hour_int: int = time_manager.time_slot_str_to_hour_int(class_start_slot_str)
			if class_start_hour_int == -1: # Indicates parsing error from helper
				if DETAILED_LOGGING_ENABLED: print_debug(["      SIM ERROR (Exit Check M): Could not parse start hour from '", class_start_slot_str, "' for student:", student_id_for_log])
				return true

			var last_slot_hour_int = class_start_hour_int + class_duration_slots - 1
			var target_exit_minute = 50

			if DETAILED_LOGGING_ENABLED:
				print_debug([
					"      EXIT CHECK (in_class) - Student:", student_id_for_log, " Offering:", offering_id,
					"Class Day Check: Current=", current_sim_day_str, "vs Scheduled=", str(days_class_occurs_on), "Match=", str(days_class_occurs_on.has(current_sim_day_str)),
					"Class Start:", class_start_slot_str, "(",class_start_hour_int, "h)", "Duration Slots:", class_duration_slots,
					"Last Slot Hour of Class:", last_slot_hour_int, "h", "Target Exit Minute:", target_exit_minute,
					"Current Sim Time:", str(current_sim_hour).pad_zeros(2) + ":" + str(current_sim_minute).pad_zeros(2)
				])

			var should_exit = false
			if days_class_occurs_on.has(current_sim_day_str): # Only apply specific exit rules if it's a class day
				if current_sim_hour == last_slot_hour_int and current_sim_minute >= target_exit_minute:
					should_exit = true
					if DETAILED_LOGGING_ENABLED: print_debug(["        DECISION (Exit @ Minute 50 Rule): Student", student_id_for_log, "for offering", offering_id, "at", str(current_sim_hour).pad_zeros(2) + ":" + str(current_sim_minute).pad_zeros(2)])
				elif current_sim_hour > last_slot_hour_int: 
					should_exit = true # Class time block has entirely passed
					if DETAILED_LOGGING_ENABLED: print_debug(["        DECISION (Exit Post-Hour Rule): Student", student_id_for_log, "for offering", offering_id, ". Current hour",current_sim_hour,"is past last slot hour", last_slot_hour_int])
			# If it's NOT a class day, but student is "in_class" for this offering, they shouldn't be.
			# This might indicate they got stuck. The hourly check's failsafe for current_sim_hour > last_slot_hour_int should eventually get them out.
			# Or add a more explicit "stuck too long" check elsewhere if needed.
			
			return should_exit
		
		"resting":
			var needs: Dictionary = student_data.get("needs")
			if needs.get("rest", 0.0) >= ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE * 0.95 and \
			   needs.get("energy", 0.0) >= ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE * 0.90:
				if DETAILED_LOGGING_ENABLED: print_debug(["      DECISION (Exit Check M): Student finished resting:", student_id_for_log])
				return true
		"studying":
			var needs: Dictionary = student_data.get("needs")
			var time_spent_simulated: float = student_data.get("time_spent_in_activity_simulated", 0.0)
			var study_duration_hours = 2 
			var max_study_time_seconds = study_duration_hours * (time_manager.seconds_per_visual_hour_slot if is_instance_valid(time_manager) else 360.0)

			if needs.get("study_urge", ACADEMIC_MGR_STUDENT_MAX_NEED_VALUE) <= ACADEMIC_MGR_STUDENT_MIN_NEED_VALUE + 10.0 or \
			   time_spent_simulated >= max_study_time_seconds:
				if DETAILED_LOGGING_ENABLED: print_debug(["      DECISION (Exit Check M): Student finished studying:", student_id_for_log])
				return true
	return false


# AcademicManager.gd

func _reinstantiate_student_from_simulation(student_data: Dictionary):
	var student_id_for_log = student_data.get("student_id", "N/A_ID")
	if DETAILED_LOGGING_ENABLED: print_debug(["  ATTEMPTING REINSTANTIATION for student:", student_id_for_log])

	if not STUDENT_SCENE or not STUDENT_SCENE.can_instantiate():
		printerr("AcademicManager: STUDENT_SCENE is null or cannot be instantiated! Path correct? Cannot reinstantiate student.")
		return
	if not is_instance_valid(building_manager):
		printerr("AcademicManager: BuildingManager invalid, cannot get exit position for student:", student_id_for_log)
		return 
	if not is_instance_valid(time_manager):
		printerr("AcademicManager: TimeManager invalid, cannot properly re-initialize student:", student_id_for_log)
		return
	if not is_instance_valid(university_data):
		printerr("AcademicManager: UniversityData invalid, cannot properly re-initialize student:", student_id_for_log)
		return

	var student_node = STUDENT_SCENE.instantiate()
	if not is_instance_valid(student_node):
		printerr("AcademicManager: Failed to INSTANTIATE student scene for ID:", student_id_for_log)
		return
	
	if DETAILED_LOGGING_ENABLED: print_debug(["    Student scene instantiated for:", student_id_for_log])
	var new_student: Student = student_node as Student

	var building_id: String = student_data.get("building_id", "")
	var exit_position: Vector3 = Vector3(0, ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y, 0) 

	if not building_id.is_empty() and building_manager.has_method("get_building_exit_location"):
		var calculated_exit = building_manager.get_building_exit_location(building_id)
		if calculated_exit != Vector3.ZERO: 
			exit_position = calculated_exit
		elif DETAILED_LOGGING_ENABLED: 
			print_debug(["    BuildingManager returned ZERO for exit position. Using fallback for student:", student_id_for_log])
		if DETAILED_LOGGING_ENABLED: print_debug(["    Exit position for building '", building_id, "' is: ", exit_position, "for student:", student_id_for_log])
	else:
		if DETAILED_LOGGING_ENABLED: printerr("AcademicManager: Could not get exit location for building '", building_id, "' (or BM missing method) for student '", student_id_for_log, "'. Using default.")

	var student_parent = get_tree().current_scene 
	if not is_instance_valid(student_parent):
		printerr("AcademicManager: Cannot get current_scene to parent re-instantiated student:", student_id_for_log)
		new_student.queue_free() 
		return
		
	student_parent.add_child(new_student)
	new_student.global_position = exit_position 
	if DETAILED_LOGGING_ENABLED: print_debug(["    Student node '",new_student.name,"' added to scene '", student_parent.name ,"' at global pos:", new_student.global_position])
	
	# --- Prepare details for "just exited class" logic ---
	var offering_id_just_finished: String = ""
	var activity_target_data_for_despawn = student_data.get("activity_target_data", {})
	if student_data.get("activity_after_despawn") == "in_class" and activity_target_data_for_despawn is Dictionary:
		offering_id_just_finished = activity_target_data_for_despawn.get("offering_id", "")
	
	# Get the visual time slot string AT THE MOMENT OF RE-INSTANTIATION
	var current_visual_slot_when_exited: String = ""
	if is_instance_valid(time_manager): # Ensure time_manager is valid before calling
		current_visual_slot_when_exited = time_manager.get_current_visual_time_slot_string()
	else:
		printerr("AcademicManager: TimeManager became invalid before getting current_visual_slot_when_exited for student:", student_id_for_log)


	new_student.initialize_new_student(
		student_data.get("student_id"),
		student_data.get("student_name"),
		student_data.get("current_program_id"),
		student_data.get("academic_start_year"),
		self, 
		university_data, 
		time_manager,
		offering_id_just_finished,       # New argument
		current_visual_slot_when_exited  # New argument
	)
	
	new_student.needs = student_data.get("needs").duplicate(true)
	
	var enrollments: Dictionary = student_data.get("current_course_enrollments", {})
	if DETAILED_LOGGING_ENABLED: print_debug(["AM Re-instantiating ", student_id_for_log, " - Enrollments to re-confirm: ", enrollments])
	for offering_id_key in enrollments:
		if enrollments[offering_id_key] is Dictionary:
			new_student.confirm_course_enrollment(offering_id_key, enrollments[offering_id_key])
		else:
			printerr("AM: Malformed enrollment data for offering '", offering_id_key, "' during re-instantiation of student '", student_id_for_log, "'")

	if not building_id.is_empty() and is_instance_valid(building_manager):
		building_manager.student_left_functional_building(building_id)
	
	if DETAILED_LOGGING_ENABLED: print_debug(["  REINSTANTIATION COMPLETE for student:", new_student.student_name, ". Activity set to idle."])
	new_student.set_activity("idle") 
	new_student.call_deferred("on_fully_spawned_and_enrolled")
