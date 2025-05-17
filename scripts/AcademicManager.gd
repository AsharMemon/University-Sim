# AcademicManager.gd
class_name AcademicManager
extends Node

signal program_unlocked(program_id: String)
signal course_offerings_updated() 
signal class_scheduled(class_instance_id: String, details: Dictionary) 
signal class_unscheduled(class_instance_id: String, details: Dictionary) 
signal schedules_updated() 
signal enrollment_changed(offering_id: String, enrolled_count: int, max_capacity: int)

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

func _ready():
	if not is_instance_valid(university_data):
		university_data = get_node_or_null("/root/MainScene/UniversityDataNode") 
		if not is_instance_valid(university_data):
			printerr("AcademicManager: CRITICAL - UniversityData node not found!")
			get_tree().quit(); return
	
	if not is_instance_valid(building_manager): 
		building_manager = get_node_or_null("/root/MainScene/BuildingManager") 
		if not is_instance_valid(building_manager):
			printerr("AcademicManager: Warning - BuildingManager node not found. Program unlock costs and classroom capacities may not function.")

	_initialize_program_states()
	print_debug("AcademicManager ready.")

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
		print_debug("Program '", program_id, "' is already unlocked.")
		return true

	var program_details_copy = university_data.get_program_details(program_id) 
	var cost_to_unlock = program_details_copy.get("unlock_cost", 0)

	if cost_to_unlock > 0:
		if not is_instance_valid(building_manager):
			printerr("AcademicManager: BuildingManager not available for processing unlock cost of '", program_id, "'.")
			return false 
		
		if building_manager.current_endowment < cost_to_unlock:
			print_debug("AcademicManager: Insufficient funds to unlock program '", program_id, "'. Need: $", cost_to_unlock, ", Have: $", building_manager.current_endowment)
			return false 
		
		building_manager.current_endowment -= cost_to_unlock
		if building_manager.has_method("update_financial_ui"): 
			building_manager.update_financial_ui()
		print_debug("AcademicManager: Deducted $", cost_to_unlock, " for unlocking program '", program_id, "'.")
	
	program_states[program_id] = "unlocked"
	_generate_course_offerings_for_program(program_id) 
	emit_signal("program_unlocked", program_id)
	print_debug("Program '", program_id, "' unlocked.")
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
				print_debug("Warning: Details for course '", course_id_val_str, "' not found. Cannot create offering for program '", program_id, "'.")
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
			print_debug("Generated new course offering: '", new_offering_id_str, "' for course '", course_id_val_str, "' in program '", program_id, "'.")

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
			print_debug("AcademicManager: Building '", classroom_id_str, "' is not of type 'class'. Cannot get classroom capacity.")
	else:
		print_debug("AcademicManager: Classroom ID '", classroom_id_str, "' not found in functional buildings data.")
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

# --- MODIFIED schedule_class function ---
func schedule_class(offering_id: String, classroom_id: String, primary_day_arg: String, start_time_slot_str_arg: String, selected_instructor_id: String = "") -> bool:
	if not course_offerings.has(offering_id):
		printerr("Failed to schedule: Offering '", offering_id, "' not found.")
		return false
	
	# Determine day_pattern_str and duration_slots_val from primary_day_arg
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
	
	# Use the public is_slot_available for the check, which now matches the arguments UI is likely to have
	if not is_slot_available(classroom_id, primary_day_arg, start_time_slot_str_arg):
		print_debug("Failed to schedule (from schedule_class): Slot not available for offering '", offering_id, "' in '", classroom_id, "' on '", primary_day_arg, "' at '", start_time_slot_str_arg, "'.")
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
		"pattern": day_pattern_to_schedule_str, # Use derived pattern
		"day": primary_day_arg, # Store the primary day used for scheduling
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
	print_debug("Class '", offering_id, "' (", offering_data_ref.course_name, ") scheduled successfully in '", classroom_id, "' for pattern '", day_pattern_to_schedule_str, "'.")
	return true


func unschedule_class(offering_id_to_remove: String) -> bool: # Added bool return
	if not scheduled_class_details.has(offering_id_to_remove):
		printerr("Cannot unschedule: Offering '", offering_id_to_remove, "' not found in scheduled classes.")
		if course_offerings.has(offering_id_to_remove) and course_offerings[offering_id_to_remove].status == "scheduled":
			course_offerings[offering_id_to_remove].status = "unscheduled" 
			emit_signal("course_offerings_updated")
			print_debug("Corrected status for offering '", offering_id_to_remove, "' to unscheduled as details were missing.")
		return false # Was not properly scheduled or data inconsistent

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
	print_debug("Class '", offering_id_to_remove, "' unscheduled successfully.")
	
	if enrolled_students_count > 0:
		print_debug("Warning: Unscheduled class '", offering_id_to_remove, "' had ", enrolled_students_count, " students. They need to be handled (e.g., auto-dropped, informed).")
	return true


func enroll_student_in_offering(offering_id: String, student_id: String) -> bool:
	# (This function was already good from response #17, ensure it's this version)
	if not scheduled_class_details.has(offering_id):
		printerr("AcademicManager: Cannot enroll student '", student_id, "'. Offering '", offering_id, "' is not scheduled or does not exist.")
		return false
	var sch_details_ref = scheduled_class_details[offering_id]
	if not sch_details_ref.has("enrolled_student_ids") or not sch_details_ref.has("max_capacity"):
		printerr("AcademicManager: Offering '", offering_id, "' has malformed schedule details. Cannot enroll student.")
		return false
	if sch_details_ref.enrolled_student_ids.size() >= sch_details_ref.max_capacity:
		print_debug("AcademicManager: Cannot enroll student '", student_id, "'. Offering '", offering_id, "' is full.")
		return false
	if sch_details_ref.enrolled_student_ids.has(student_id):
		print_debug("AcademicManager: Student '", student_id, "' is already enrolled in offering '", offering_id, "'.")
		return true 
	sch_details_ref.enrolled_student_ids.append(student_id)
	emit_signal("enrollment_changed", offering_id, sch_details_ref.enrolled_student_ids.size(), sch_details_ref.max_capacity)
	emit_signal("schedules_updated")
	print_debug("AcademicManager: Student '", student_id, "' enrolled in offering '", offering_id, "'. Total: ", sch_details_ref.enrolled_student_ids.size())
	return true

func drop_student_from_offering(offering_id: String, student_id: String) -> bool:
	# (This function was already good from response #17)
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
		print_debug("AcademicManager: Student '", student_id, "' dropped from '", offering_id, "'. Total: ", sch_details_ref.enrolled_student_ids.size())
		return true
	else:
		print_debug("AcademicManager: Student '", student_id, "' not found in '", offering_id, "'. Cannot drop.")
		return false

func get_offering_enrollment(offering_id: String) -> Dictionary:
	# (This function was already good from response #17)
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
	# (This function was already good from response #17)
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
	if unique_freshman_first_sem_courses_dict.is_empty(): print_debug("Capacity Calc: No unique Freshman/1st Sem courses in curricula."); return 0
	for course_id_for_calc in unique_freshman_first_sem_courses_dict.keys():
		for offering_id_sch_key in scheduled_class_details.keys(): 
			var sch_details_dict = scheduled_class_details[offering_id_sch_key]
			if sch_details_dict.get("course_id") == course_id_for_calc: 
				var enrolled_students_array: Array = sch_details_dict.get("enrolled_student_ids", [])
				var available_in_this_one = sch_details_dict.get("max_capacity", 0) - enrolled_students_array.size()
				if available_in_this_one > 0: total_available_seats += available_in_this_one
	print_debug("Total intake capacity: %d seats." % total_available_seats)
	return total_available_seats

func get_freshman_first_semester_courses(program_id: String) -> Array[String]:
	# (This function was already good from response #17)
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
		print_debug("Warning: No Freshman/1st Sem courses in curriculum for '", program_id, "'.")
	return courses_to_return_list

func find_and_enroll_student_in_offering(student_id: String, course_id_to_enroll: String) -> String:
	# (This function was already good from response #17)
	var best_offering_id_to_enroll: String = ""
	var max_available_seats_in_best_offering = 0 
	for offering_id_candidate in scheduled_class_details.keys():
		var offering_sch_details_dict = scheduled_class_details[offering_id_candidate]
		if offering_sch_details_dict.get("course_id") == course_id_to_enroll:
			var enrolled_students_list: Array = offering_sch_details_dict.get("enrolled_student_ids", [])
			var current_available_seats = offering_sch_details_dict.get("max_capacity", 0) - enrolled_students_list.size()
			if current_available_seats > 0:
				if current_available_seats > max_available_seats_in_best_offering:
					max_available_seats_in_best_offering = current_available_seats
					best_offering_id_to_enroll = offering_id_candidate
	if not best_offering_id_to_enroll.is_empty():
		var enrollment_success = enroll_student_in_offering(best_offering_id_to_enroll, student_id)
		if enrollment_success:
			print_debug("Student '%s' auto-enrolled in '%s' (Offering: '%s')." % [student_id, course_id_to_enroll, best_offering_id_to_enroll])
			return best_offering_id_to_enroll
		else:
			printerr("Student '%s' FAILED auto-enroll in '%s' (Offering: '%s')." % [student_id, course_id_to_enroll, best_offering_id_to_enroll])
	else:
		print_debug("No available offering for student '%s' in course '%s'." % [student_id, course_id_to_enroll])
	return ""

func get_offering_details(offering_id: String) -> Dictionary:
	# (This function was already good from response #17)
	if course_offerings.has(offering_id):
		var base_details = course_offerings[offering_id].duplicate(true)
		if scheduled_class_details.has(offering_id): 
			var sch_details_copy = scheduled_class_details[offering_id].duplicate(true)
			base_details.merge(sch_details_copy) 
			base_details.status = "scheduled" 
		return base_details
	return {}

func get_schedule_for_classroom(classroom_id: String) -> Dictionary:
	# (This function was already good from response #17)
	if classroom_schedules.has(classroom_id):
		return classroom_schedules[classroom_id].duplicate(true)
	return {}

func get_days_for_pattern(pattern_str: String) -> Array[String]: # Helper for Student.gd
	if pattern_str == "MWF": return ["Mon", "Wed", "Fri"]
	if pattern_str == "TR": return ["Tue", "Thu"]
	return []
	
## In AcademicManager.gd

func get_classroom_location(classroom_id_str: String) -> Vector3:
	print_debug("AM: get_classroom_location CALLED for classroom_id: '%s'" % classroom_id_str)
	if not is_instance_valid(building_manager):
		printerr("AM: BuildingManager not available to get classroom location for ID: ", classroom_id_str)
		return Vector3.ZERO 

	if building_manager.has_method("get_functional_buildings_data"):
		var functional_buildings: Dictionary = building_manager.get_functional_buildings_data()
		if functional_buildings.has(classroom_id_str):
			var classroom_cluster_data = functional_buildings[classroom_id_str]
			print_debug("AM: Found cluster data for '%s': %s" % [classroom_id_str, str(classroom_cluster_data)])

			if classroom_cluster_data.get("building_type") == "class":
				var rep_node = classroom_cluster_data.get("representative_block_node")
				if is_instance_valid(rep_node) and rep_node is Node3D:
					var base_position = rep_node.global_position
					
					# --- ADJUST Y-COORDINATE HERE ---
					# Set the Y to match the students' typical navigation height (e.g., 1.0)
					# Or, ideally, a height known to be on the NavMesh near the building entrance.
					var navigation_target_y = 1.0 # Target Y for navigation
					var navigation_target_position = Vector3(base_position.x, navigation_target_y, base_position.z) 
					# --- END OF ADJUSTMENT ---
					
					print_debug("AM: Rep node for classroom '%s' base pos: %s. Nav target (Y adjusted to %.1f): %s" % [classroom_id_str, str(base_position), navigation_target_y, str(navigation_target_position)])
					return navigation_target_position
				else:
					print_debug("AM: Classroom cluster '%s' has NO valid representative_block_node for location." % classroom_id_str)
			else:
				print_debug("AM: Building cluster '%s' is NOT of type 'class'. Actual type: %s" % [classroom_id_str, classroom_cluster_data.get("building_type")])
		else:
			print_debug("AM: Classroom ID '", classroom_id_str, "' NOT FOUND in functional_buildings keys. Available keys: %s" % str(functional_buildings.keys()))
	else:
		printerr("AM: BuildingManager is missing 'get_functional_buildings_data' method.")
			
	print_debug("AM: get_classroom_location returning Vector3.ZERO for classroom_id: '%s'" % classroom_id_str)
	return Vector3.ZERO

func print_debug(message_parts):
	var final_message = "[AcademicManager]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY:
		var string_array : Array[String] = []
		for item in message_parts: string_array.append(str(item))
		final_message += String(" ").join(string_array)
	elif typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : PackedStringArray = message_parts
		final_message += " ".join(temp_array)
	else: final_message += str(message_parts)
	print(final_message)
