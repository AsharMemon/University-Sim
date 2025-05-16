# AcademicManager.gd
# Manages university programs, course offerings, class scheduling, and enrollment.
class_name AcademicManager
extends Node

# --- Signals ---
signal program_unlocked(program_id: String)
signal course_offerings_updated() 
signal class_scheduled(class_instance_id: String, details: Dictionary) 
signal class_unscheduled(class_instance_id: String, details: Dictionary) 
signal schedules_updated() 
signal enrollment_changed(offering_id: String, enrolled_count: int, max_capacity: int) # NEW

# --- Node References ---
@export var university_data: UniversityData 
@export var building_manager: BuildingManager 
@export var time_manager: TimeManager 

# --- Program Management ---
var program_states: Dictionary = {}

# --- Course Offerings & Scheduling ---
var course_offerings: Dictionary = {} # Key: offering_id

# Stores the actual schedule details for offerings that are scheduled.
# Key: offering_id, Value: { 
# "classroom_id": "xyz", "day": "Mon" or "Tue" (primary day), 
# "start_time_slot": "0900", "duration_slots": 1 or 2, 
# "course_id": "CS101", "pattern": "MWF" or "TR",
# "max_capacity": 30, # NEW: From the classroom
# "enrolled_student_ids": ["student_id_1", "student_id_2"] # NEW
# }
var scheduled_class_details: Dictionary = {}

var classroom_schedules: Dictionary = {}

# --- Time Definitions ---
const DAYS_OF_WEEK: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"]
const HOURLY_TIME_SLOTS: Array[String] = [
	"0800", "0900", "1000", "1100", "1200", 
	"1300", "1400", "1500", "1600", "1700" 
]
const DURATION_MWF: int = 1 
const DURATION_TR: int = 2  

# --- Initialization ---
func _ready():
	if not is_instance_valid(university_data):
		university_data = get_node_or_null("/root/MainScene/UniversityData") 
		if not is_instance_valid(university_data):
			printerr("AcademicManager: UniversityData node not found or not assigned!")
			get_tree().quit(); return
	
	if not is_instance_valid(building_manager):
		building_manager = get_node_or_null("/root/MainScene/BuildingManager") 
		if not is_instance_valid(building_manager):
			printerr("AcademicManager: BuildingManager node not found or not assigned!")
	
	if not is_instance_valid(time_manager):
		time_manager = get_node_or_null("/root/MainScene/TimeManager")

	_initialize_program_states()
	print("AcademicManager ready.")

func _initialize_program_states():
	# ... (same as before) ...
	if not is_instance_valid(university_data): return
	var all_programs = university_data.PROGRAMS
	for program_id in all_programs:
		if not program_states.has(program_id):
			program_states[program_id] = "locked"
	# Example:
	# if program_states.has("BSC_CS"): unlock_program("BSC_CS")


# --- Program Management Functions (Largely Unchanged) ---
# ... (unlock_program, get_program_state, get_all_program_states, _generate_course_offerings_for_program) ...
# (Make sure _generate_course_offerings_for_program doesn't add enrollment fields; those are for scheduled classes)
func unlock_program(program_id: String):
	if not is_instance_valid(university_data): return false
	if not university_data.PROGRAMS.has(program_id):
		printerr("AcademicManager: Attempted to unlock non-existent program '", program_id, "'.")
		return false
	if program_states.get(program_id) == "unlocked": return true

	program_states[program_id] = "unlocked"
	_generate_course_offerings_for_program(program_id)
	emit_signal("program_unlocked", program_id)
	emit_signal("course_offerings_updated")
	return true

func get_program_state(program_id: String) -> String:
	return program_states.get(program_id, "unknown")

func get_all_program_states() -> Dictionary:
	return program_states.duplicate(true)

func _generate_course_offerings_for_program(program_id: String):
	if not is_instance_valid(university_data): return
	if program_states.get(program_id) != "unlocked": return

	var required_courses: Array[String] = university_data.get_required_courses_for_program(program_id)
	for course_id in required_courses:
		var already_exists = false
		for offering_id_key in course_offerings:
			var o = course_offerings[offering_id_key]
			if o.course_id == course_id and o.program_id == program_id:
				already_exists = true; break
		if not already_exists:
			var course_details = university_data.get_course_details(course_id)
			if course_details.is_empty(): continue
			var new_offering_id = "offering_%s_%s_%s" % [program_id, course_id, str(Time.get_unix_time_from_system()) + str(randi() % 1000)]
			course_offerings[new_offering_id] = {
				"offering_id": new_offering_id, "course_id": course_id,
				"course_name": course_details.get("name", "N/A"), "program_id": program_id,
				"status": "unscheduled" 
				# DO NOT add max_capacity or enrolled_student_ids here
			}
	emit_signal("course_offerings_updated")

# --- Course Offering & Scheduling Functions (MODIFIED) ---
# ... (get_unscheduled_course_offerings is same) ...
func get_unscheduled_course_offerings() -> Array[Dictionary]:
	var unscheduled: Array[Dictionary] = []
	for offering_id_key in course_offerings:
		var offering = course_offerings[offering_id_key]
		if offering.status == "unscheduled":
			unscheduled.append(offering.duplicate(true))
	return unscheduled

func get_available_classrooms() -> Array[Dictionary]:
	# ... (same as before, ensuring it returns 'id' and 'capacity') ...
	if not is_instance_valid(building_manager):
		printerr("AcademicManager: BuildingManager not available to get classrooms.")
		return []
	var functional_buildings_data = building_manager.get_functional_buildings_data()
	var classrooms: Array[Dictionary] = []
	for cluster_id_key in functional_buildings_data:
		var cluster_data = functional_buildings_data[cluster_id_key]
		if cluster_data.get("building_type") == "class":
			classrooms.append({
				"id": str(cluster_id_key), 
				"capacity": cluster_data.get("total_capacity", 0), # This is the crucial part
				"current_users": cluster_data.get("current_users", 0), # BuildingManager's general user count
			})
	return classrooms

# ... (is_slot_available, _is_single_day_slot_available are same) ...
func is_slot_available(classroom_id: String, primary_day: String, start_time_slot: String) -> bool:
	if not (primary_day == "Mon" or primary_day == "Tue"):
		return false 
	var days_to_check: Array[String] = []
	var duration_for_pattern: int = 0
	if primary_day == "Mon":
		days_to_check = ["Mon", "Wed", "Fri"]; duration_for_pattern = DURATION_MWF
	elif primary_day == "Tue":
		days_to_check = ["Tue", "Thu"]; duration_for_pattern = DURATION_TR
	else: return false
	for day_to_check in days_to_check:
		if not _is_single_day_slot_available(classroom_id, day_to_check, start_time_slot, duration_for_pattern):
			return false
	return true

func _is_single_day_slot_available(classroom_id: String, day: String, start_time_slot: String, duration_slots: int) -> bool:
	if not DAYS_OF_WEEK.has(day) or not HOURLY_TIME_SLOTS.has(start_time_slot): return false
	var classroom_day_schedule = classroom_schedules.get(classroom_id, {}).get(day, {})
	var start_slot_index = HOURLY_TIME_SLOTS.find(start_time_slot)
	if start_slot_index == -1: return false
	for i in range(duration_slots):
		var current_slot_index = start_slot_index + i
		if current_slot_index >= HOURLY_TIME_SLOTS.size(): return false 
		var slot_to_check = HOURLY_TIME_SLOTS[current_slot_index]
		if classroom_day_schedule.has(slot_to_check): return false
	return true

# MODIFIED: schedule_class now fetches and stores classroom capacity
func schedule_class(offering_id: String, classroom_id: String, primary_day: String, start_time_slot: String) -> bool:
	if not course_offerings.has(offering_id): return false
	var offering_data = course_offerings[offering_id]
	if offering_data.status == "scheduled": return false
	if not (primary_day == "Mon" or primary_day == "Tue"): return false

	var days_to_schedule: Array[String] = []; var duration_for_pattern: int = 0; var pattern_name: String = ""
	if primary_day == "Mon":
		days_to_schedule = ["Mon", "Wed", "Fri"]; duration_for_pattern = DURATION_MWF; pattern_name = "MWF"
	elif primary_day == "Tue":
		days_to_schedule = ["Tue", "Thu"]; duration_for_pattern = DURATION_TR; pattern_name = "TR"
	
	if not is_slot_available(classroom_id, primary_day, start_time_slot): return false

	# Get classroom capacity
	var classroom_capacity = 0
	if is_instance_valid(building_manager):
		var functional_buildings = building_manager.get_functional_buildings_data()
		if functional_buildings.has(classroom_id): # classroom_id is the cluster_id
			classroom_capacity = functional_buildings[classroom_id].get("total_capacity", 0)
		else:
			printerr("AcademicManager: Could not find classroom '", classroom_id, "' in BuildingManager data to get capacity.")
	else:
		printerr("AcademicManager: BuildingManager not available to get classroom capacity.")

	for day_to_schedule in days_to_schedule:
		if not classroom_schedules.has(classroom_id): classroom_schedules[classroom_id] = {}
		if not classroom_schedules[classroom_id].has(day_to_schedule): classroom_schedules[classroom_id][day_to_schedule] = {}
		var start_slot_index = HOURLY_TIME_SLOTS.find(start_time_slot)
		for i in range(duration_for_pattern):
			var current_slot_to_fill = HOURLY_TIME_SLOTS[start_slot_index + i]
			classroom_schedules[classroom_id][day_to_schedule][current_slot_to_fill] = offering_id
			
	offering_data.status = "scheduled"
	scheduled_class_details[offering_id] = {
		"classroom_id": classroom_id, "day": primary_day, "start_time_slot": start_time_slot,
		"duration_slots": duration_for_pattern, "course_id": offering_data.course_id,
		"pattern": pattern_name,
		"max_capacity": classroom_capacity, # STORED
		"enrolled_student_ids": [] # STORED - Initialize as empty
	}
	
	print_debug("Scheduled '", offering_id, "' as ", pattern_name, " in classroom '", classroom_id, "' (Cap: ", classroom_capacity,")")
	emit_signal("class_scheduled", offering_id, scheduled_class_details[offering_id])
	emit_signal("course_offerings_updated")
	emit_signal("schedules_updated")
	emit_signal("enrollment_changed", offering_id, 0, classroom_capacity) # Emit initial enrollment state
	return true

# MODIFIED: unschedule_class now also clears enrollment
func unschedule_class(offering_id_to_remove: String) -> bool:
	# ... (existing logic to find schedule_info and clear classroom_schedules) ...
	if not course_offerings.has(offering_id_to_remove): return false
	var offering_data = course_offerings[offering_id_to_remove]
	if offering_data.status == "unscheduled": return true 
	var schedule_info = scheduled_class_details.get(offering_id_to_remove)
	if not schedule_info:
		offering_data.status = "unscheduled"; emit_signal("course_offerings_updated"); emit_signal("schedules_updated")
		return false
	var classroom_id = schedule_info.classroom_id; var primary_day = schedule_info.day 
	var start_time_slot = schedule_info.start_time_slot; var pattern = schedule_info.pattern 
	var duration_per_instance = schedule_info.duration_slots
	var days_to_clear: Array[String] = []
	if pattern == "MWF": days_to_clear = ["Mon", "Wed", "Fri"]
	elif pattern == "TR": days_to_clear = ["Tue", "Thu"]
	else: days_to_clear.append(primary_day) 
	for day_to_clear in days_to_clear:
		if classroom_schedules.has(classroom_id) and classroom_schedules[classroom_id].has(day_to_clear):
			var start_slot_index = HOURLY_TIME_SLOTS.find(start_time_slot)
			if start_slot_index != -1:
				for i in range(duration_per_instance):
					var current_slot_to_clear_idx = start_slot_index + i
					if current_slot_to_clear_idx < HOURLY_TIME_SLOTS.size():
						var slot_key = HOURLY_TIME_SLOTS[current_slot_to_clear_idx]
						if classroom_schedules[classroom_id][day_to_clear].has(slot_key) and \
						   classroom_schedules[classroom_id][day_to_clear][slot_key] == offering_id_to_remove:
							classroom_schedules[classroom_id][day_to_clear].erase(slot_key)
			if classroom_schedules[classroom_id][day_to_clear].is_empty(): classroom_schedules[classroom_id].erase(day_to_clear)
		if classroom_schedules.has(classroom_id) and classroom_schedules[classroom_id].is_empty(): classroom_schedules.erase(classroom_id)
	
	offering_data.status = "unscheduled"
	var old_details = scheduled_class_details.erase(offering_id_to_remove) 
	
	print_debug("Unscheduled offering '", offering_id_to_remove, "'. Enrolled students (if any) are now unassigned from this.")
	emit_signal("class_unscheduled", offering_id_to_remove, old_details) 
	emit_signal("course_offerings_updated")
	emit_signal("schedules_updated")
	# Emit enrollment changed to reflect 0 enrolled, perhaps with old capacity or 0.
	emit_signal("enrollment_changed", offering_id_to_remove, 0, old_details.get("max_capacity", 0) if old_details else 0)
	return true

# --- NEW Enrollment Functions ---
func can_enroll_in_offering(offering_id: String) -> bool:
	if not scheduled_class_details.has(offering_id):
		# print_debug("Cannot check enrollment: Offering '", offering_id, "' not scheduled.")
		return false
	var details = scheduled_class_details[offering_id]
	return details.enrolled_student_ids.size() < details.max_capacity

func enroll_student_in_offering(offering_id: String, student_id: String) -> bool:
	if not scheduled_class_details.has(offering_id):
		printerr("AcademicManager: Cannot enroll. Offering '", offering_id, "' is not scheduled.")
		return false
	
	var details = scheduled_class_details[offering_id]
	if details.enrolled_student_ids.has(student_id):
		print_debug("Student '", student_id, "' already enrolled in offering '", offering_id, "'.")
		return true # Or false if you want to indicate "no change made"
		
	if details.enrolled_student_ids.size() >= details.max_capacity:
		print_debug("Offering '", offering_id, "' is full. Cannot enroll student '", student_id, "'. (", details.enrolled_student_ids.size(), "/", details.max_capacity, ")")
		return false
		
	details.enrolled_student_ids.append(student_id)
	print_debug("Student '", student_id, "' enrolled in offering '", offering_id, "'. (", details.enrolled_student_ids.size(), "/", details.max_capacity, ")")
	emit_signal("enrollment_changed", offering_id, details.enrolled_student_ids.size(), details.max_capacity)
	emit_signal("schedules_updated") # For UI to potentially refresh cell display
	return true

func drop_student_from_offering(offering_id: String, student_id: String) -> bool:
	if not scheduled_class_details.has(offering_id):
		printerr("AcademicManager: Cannot drop. Offering '", offering_id, "' is not scheduled.")
		return false
		
	var details = scheduled_class_details[offering_id]
	if not details.enrolled_student_ids.has(student_id):
		print_debug("Student '", student_id, "' not found in offering '", offering_id, "' for dropping.")
		return false # Student wasn't enrolled
		
	details.enrolled_student_ids.erase(student_id)
	print_debug("Student '", student_id, "' dropped from offering '", offering_id, "'. (", details.enrolled_student_ids.size(), "/", details.max_capacity, ")")
	emit_signal("enrollment_changed", offering_id, details.enrolled_student_ids.size(), details.max_capacity)
	emit_signal("schedules_updated") # For UI to potentially refresh cell display
	return true

func get_offering_enrollment(offering_id: String) -> Dictionary:
	if scheduled_class_details.has(offering_id):
		var details = scheduled_class_details[offering_id]
		return {
			"enrolled_count": details.enrolled_student_ids.size(),
			"max_capacity": details.max_capacity,
			"student_ids": details.enrolled_student_ids.duplicate() # Return a copy
		}
	return {"enrolled_count": 0, "max_capacity": 0, "student_ids": []}

# ... (get_schedule_for_classroom, get_all_classroom_schedules, get_offering_details, print_debug are same) ...
func get_offering_details(offering_id: String) -> Dictionary: # Ensure this merges new enrollment data
	if course_offerings.has(offering_id):
		var offering = course_offerings[offering_id].duplicate(true)
		if offering.status == "scheduled" and scheduled_class_details.has(offering_id):
			var schedule_data = scheduled_class_details[offering_id]
			for key in schedule_data: # Merge all schedule data including new enrollment fields
				offering[key] = schedule_data[key]
			# Ensure enrollment count is also easily accessible if not directly in schedule_data root
			if offering.has("enrolled_student_ids"):
				offering["enrolled_count"] = offering.enrolled_student_ids.size()
		return offering
	return {}

func get_schedule_for_classroom(classroom_id: String) -> Dictionary:
	return classroom_schedules.get(classroom_id, {}).duplicate(true)

func get_all_classroom_schedules() -> Dictionary:
	return classroom_schedules.duplicate(true)

func print_debug(message_parts): 
	var final_message = "[AcademicManager]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY or typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : Array = message_parts; final_message += " ".join(temp_array)
	else: final_message += str(message_parts)
	print(final_message)
