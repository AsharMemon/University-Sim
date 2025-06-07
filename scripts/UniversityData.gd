# UniversityData.gd
class_name UniversityData
extends Node

@export var course_resource_files: Array[CourseResource] = []
@export var program_resource_files: Array[ProgramResource] = []

var COURSES: Dictionary = {}
var PROGRAMS: Dictionary = {}
var PROGRAM_CURRICULUM_STRUCTURE: Dictionary = {} # This will be dynamically built
var PROGRAM_REQUIREMENTS: Dictionary = {}

const FIRST_NAMES: Array[String] = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Jessie", "Chris", "Pat", "Sam", "Dana", "Kim", "Lee", "Max", "Quinn", "River", "Skyler", "Dakota", "Avery", "Cameron", "Drew", "Blake", "Logan"]
const LAST_NAMES: Array[String] = ["Smith", "Jones", "Williams", "Brown", "Davis", "Miller", "Wilson", "Moore", "Garcia", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Perez", "Lee", "Walker", "Hall", "Allen", "Young", "King", "Wright", "Scott", "Green"]
const EMPTY_STRING_ARRAY: Array[String] = []
const DETAILED_LOGGING_ENABLED: bool = true

func _ready():
	_load_data_from_resources()
	_validate_loaded_data()
	print_debug("UniversityData Node is ready. Name: " + self.name)

func _load_data_from_resources():
	COURSES.clear()
	PROGRAMS.clear()
	PROGRAM_CURRICULUM_STRUCTURE.clear()
	PROGRAM_REQUIREMENTS.clear()

	print_debug("Starting to load data from resources...")

	# Pass 1: Load all Course Definitions into COURSES dictionary
	print_debug("--- Pass 1: Loading Course Resources ---")
	if course_resource_files.is_empty():
		print_debug("No CourseResource files assigned to 'course_resource_files' array.")
	
	for course_res in course_resource_files:
		if not is_instance_valid(course_res):
			printerr("UniversityData: Invalid CourseResource (null entry) in course_resource_files. Skipping.")
			continue
		if course_res.course_id.is_empty():
			printerr("UniversityData: CourseResource (path: '%s') has an empty course_id. Skipping." % course_res.resource_path if course_res.resource_path else "Unknown Path")
			continue
		
		print_debug("  Loading Course: %s (ID: %s)" % [course_res.course_name, course_res.course_id])

		if COURSES.has(course_res.course_id):
			printerr("UniversityData: Duplicate course_id '%s'. Overwriting with data from '%s'." % [course_res.course_id, course_res.resource_path])
		
		var prereq_ids_array: Array[String] = []
		
		# --- DETAILED PREREQUISITE DEBUGGING ---
		print_debug("    Processing prerequisites for course: '%s' (Name: %s)" % [course_res.course_id, course_res.course_name])
		if course_res.prerequisites == null:
			print_debug("      Course '%s': 'prerequisites' property is null." % course_res.course_id)
		elif not course_res.prerequisites is Array:
			print_debug("      Course '%s': 'prerequisites' property is NOT AN ARRAY. GDScript Type Enum: %s. Is it an Array? %s" % [course_res.course_id, typeof(course_res.prerequisites), str(course_res.prerequisites is Array)])
		elif course_res.prerequisites.is_empty():
			print_debug("      Course '%s': 'prerequisites' array IS EMPTY." % course_res.course_id)
		else:
			print_debug("      Course '%s': 'prerequisites' array has %d entries. Iterating..." % [course_res.course_id, course_res.prerequisites.size()])
			var entry_index = 0
			for prereq_obj in course_res.prerequisites: # prereq_obj is a CourseResource
				print_debug("        Entry %d: Is valid instance? %s" % [entry_index, str(is_instance_valid(prereq_obj))])
				if is_instance_valid(prereq_obj):
					print_debug("          Prereq_obj Course ID: '%s', Name: '%s', Path: '%s'" % [prereq_obj.course_id, prereq_obj.course_name, prereq_obj.resource_path if prereq_obj.resource_path else "Inline/Not Saved"])
					if not prereq_obj.course_id.is_empty():
						prereq_ids_array.append(prereq_obj.course_id)
						print_debug("          SUCCESS: Added prerequisite ID '%s' for course '%s'" % [prereq_obj.course_id, course_res.course_id])
					else:
						printerr("          ERROR: CourseResource linked as a prerequisite for '%s' (from '%s') has an empty course_id. Skipping." % [course_res.course_id, prereq_obj.resource_path if prereq_obj.resource_path else "inline resource"])
				else:
					printerr("          ERROR: Null or invalid CourseResource entry found at index %d in prerequisites array for course '%s'." % [entry_index, course_res.course_id])
				entry_index += 1
		# --- END DETAILED PREREQUISITE DEBUGGING ---
		
		COURSES[course_res.course_id] = {
			"name": course_res.course_name,
			"credits": course_res.credits,
			"description": course_res.description,
			"progress_needed": course_res.progress_needed,
			"prerequisites": prereq_ids_array,
			"default_program_year": course_res.default_program_year,
			"default_program_semester": course_res.default_program_semester,
			"course_level": course_res.course_level # Stores the enum value (int)

		}
		print_debug("    Course '%s' loaded into COURSES dictionary with %d prerequisites. Default Year: %d, Sem: %d" % [course_res.course_id, prereq_ids_array.size(), course_res.default_program_year, course_res.default_program_semester])

	print_debug("--- Pass 1 Complete. Total courses loaded into COURSES dict: %d ---" % COURSES.size())

	# Pass 2: Load Programs and build their curriculum structure
	print_debug("--- Pass 2: Loading Program Resources and Building Curricula ---")
	if program_resource_files.is_empty():
		print_debug("No ProgramResource files assigned to 'program_resource_files' array.")
		
	for program_res in program_resource_files:
		if not is_instance_valid(program_res):
			printerr("UniversityData: Invalid ProgramResource (null entry) in program_resource_files. Skipping.")
			continue
		if program_res.program_id.is_empty():
			printerr("UniversityData: ProgramResource (path: '%s') has an empty program_id. Skipping." % program_res.resource_path if program_res.resource_path else "Unknown Path")
			continue
		
		print_debug("Processing Program Resource: ID='%s', Name='%s', Path='%s', TypeFromScript='%s'" % [program_res.program_id, program_res.program_name, program_res.resource_path, program_res.get_class()])

		# --- DETAILED DEBUGGING FOR THE PROGRAM RESOURCE ITSELF ---
		if not "courses_in_program_resources" in program_res: # Check if property exists by name
			print_debug("  ERROR: ProgramResource for '%s' does NOT have the property 'courses_in_program_resources' AT ALL." % program_res.program_id)
			var props = []
			for p_item in program_res.get_property_list(): props.append(p_item.name)
			print_debug("    Available properties on this resource object: %s" % str(props))
			continue 
		else:
			print_debug("  ProgramResource for '%s' HAS the property 'courses_in_program_resources'." % program_res.program_id)
		
		var loaded_courses_array = program_res.get("courses_in_program_resources") # Get property value

		if loaded_courses_array == null:
			print_debug("  Program '%s': 'courses_in_program_resources' property is NULL." % program_res.program_id)
		elif not loaded_courses_array is Array:
			print_debug("  Program '%s': 'courses_in_program_resources' is NOT AN ARRAY. Actual Type: %s. Is it an Array? %s" % [program_res.program_id, typeof(loaded_courses_array), str(loaded_courses_array is Array)])
		else:
			print_debug("  Program '%s': 'courses_in_program_resources' IS an Array with %d elements." % [program_res.program_id, loaded_courses_array.size()])
			if loaded_courses_array.is_empty():
				print_debug("    The 'courses_in_program_resources' array is empty for program '%s'." % program_res.program_id)
			else:
				for i in range(loaded_courses_array.size()):
					var course_entry_check = loaded_courses_array[i]
					if is_instance_valid(course_entry_check) and course_entry_check is CourseResource:
						print_debug("      Entry %d in 'courses_in_program_resources': Course ID '%s' (Name: %s, Path: %s)" % [i, course_entry_check.course_id, course_entry_check.course_name, course_entry_check.resource_path if course_entry_check.resource_path else "Inline/Not Saved"])
					else:
						print_debug("      Entry %d in 'courses_in_program_resources': Invalid, null, or not a CourseResource. Type: %s" % [i, typeof(course_entry_check) if course_entry_check != null else "null"])
		# --- END DETAILED DEBUGGING ---

		if PROGRAMS.has(program_res.program_id):
			printerr("UniversityData: Duplicate program_id '%s'. Overwriting." % program_res.program_id)

		PROGRAMS[program_res.program_id] = {
			"name": program_res.program_name, "credits_to_graduate": program_res.credits_to_graduate,
			"unlock_cost": program_res.unlock_cost, "semesters_per_year": program_res.semesters_per_year,
			"level": program_res.level, # Stores the enum value (int)
			"typical_duration_years": program_res.typical_duration_years,
			"requires_thesis_or_dissertation": program_res.requires_thesis_or_dissertation
		}

		var curriculum_for_program: Dictionary = {}
		for year_num in range(1, 5): 
			var year_key = "Year %d" % year_num
			curriculum_for_program[year_key] = {}
			for semester_num in range(1, program_res.semesters_per_year + 1):
				var semester_key = "Semester %d" % semester_num
				curriculum_for_program[year_key][semester_key] = []
		
		print_debug("  Program '%s': Initialized empty curriculum structure (Years 1-4, %d Semesters/Year)." % [program_res.program_id, program_res.semesters_per_year])

		if loaded_courses_array != null and loaded_courses_array is Array:
			for course_resource_entry in loaded_courses_array: 
				if not is_instance_valid(course_resource_entry) or not (course_resource_entry is CourseResource) or course_resource_entry.course_id.is_empty():
					continue 
				
				var course_id_in_prog = course_resource_entry.course_id
				
				if not COURSES.has(course_id_in_prog):
					printerr("Program '%s': Course ID '%s' (from program list) not found in master COURSES. Skipping placement." % [program_res.program_id, course_id_in_prog])
					continue
				
				var course_data_from_dict = COURSES[course_id_in_prog]
				var target_year = course_data_from_dict.get("default_program_year", -1)
				var target_semester = course_data_from_dict.get("default_program_semester", -1)
				
				print_debug("    Attempting to place Course ID '%s' (default_year=%s, default_semester=%s) for program '%s'." % [course_id_in_prog, str(target_year), str(target_semester), program_res.program_id])

				var year_key_to_add = "Year %d" % target_year
				var semester_key_to_add = "Semester %d" % target_semester

				if curriculum_for_program.has(year_key_to_add) and \
				   curriculum_for_program[year_key_to_add].has(semester_key_to_add):
					curriculum_for_program[year_key_to_add][semester_key_to_add].append(course_id_in_prog)
					print_debug("      Successfully placed '%s' in %s, %s for program '%s'" % [course_id_in_prog, year_key_to_add, semester_key_to_add, program_res.program_id])
				else:
					printerr("Program '%s': Course '%s' has invalid year/sem (%s/%s) for keys ('%s', '%s'). Check data or logic." % [program_res.program_id, course_id_in_prog, str(target_year), str(target_semester), year_key_to_add, semester_key_to_add])
		
		PROGRAM_CURRICULUM_STRUCTURE[program_res.program_id] = curriculum_for_program
		print_debug("  Program '%s': Final curriculum structure built: %s" % [program_res.program_id, str(curriculum_for_program)])
		
		var valid_mandatory_course_ids: Array[String] = []
		if is_instance_valid(program_res.mandatory_courses_resources):
			for mandatory_course_resource_entry in program_res.mandatory_courses_resources:
				if not is_instance_valid(mandatory_course_resource_entry) or not (mandatory_course_resource_entry is CourseResource) or mandatory_course_resource_entry.course_id.is_empty():
					continue
				var mandatory_course_id = mandatory_course_resource_entry.course_id
				if COURSES.has(mandatory_course_id): 
					valid_mandatory_course_ids.append(mandatory_course_id)
				else:
					printerr("Mandatory course ID '%s' for Program '%s' NOT FOUND. Skipping." % [mandatory_course_id, program_res.program_id])
		PROGRAM_REQUIREMENTS[program_res.program_id] = valid_mandatory_course_ids
		print_debug("  Program '%s': Mandatory graduation requirements: %s" % [program_res.program_id, str(valid_mandatory_course_ids)])
		
	print_debug("--- Pass 2 Complete. Total programs processed: %d ---" % program_resource_files.size())
	
	if PROGRAM_CURRICULUM_STRUCTURE.has("CS"): 
		print_debug("FINAL 'CS' Program Curriculum Structure in UniversityData: %s" % str(PROGRAM_CURRICULUM_STRUCTURE["CS"]))
	else:
		print_debug("FINAL 'CS' Program Curriculum Structure NOT FOUND in UniversityData (Program ID 'CS' might not exist or wasn't processed).")

func _validate_loaded_data():
	print_debug("Starting data validation...")
	for course_id in COURSES:
		var course_data = COURSES[course_id]
		if course_data.has("prerequisites"):
			for prereq_id in course_data.prerequisites:
				if not COURSES.has(prereq_id):
					printerr("Validation Error: Prerequisite '%s' for course '%s' does not exist." % [prereq_id, course_id])
		
		var d_year = course_data.get("default_program_year", -1)
		var d_sem = course_data.get("default_program_semester", -1)

		if not (d_year >= 1 and d_year <= 4): # Assuming 4 years max
			printerr("Validation Warning: Course '%s' has invalid default_program_year: %s" % [course_id, str(d_year)])
		# Assuming semesters_per_year is 2 for this validation, or fetch from a general config
		if not (d_sem >= 1 and d_sem <= 2): 
			printerr("Validation Warning: Course '%s' has invalid default_program_semester: %s" % [course_id, str(d_sem)])

	for prog_id in PROGRAM_CURRICULUM_STRUCTURE:
		if not PROGRAMS.has(prog_id):
			printerr("Validation Error: Program '%s' in curriculum structure but not in PROGRAMS list." % prog_id)
		var prog_curriculum = PROGRAM_CURRICULUM_STRUCTURE[prog_id]
		for year_key in prog_curriculum:
			var year_semesters = prog_curriculum[year_key]
			for sem_key in year_semesters:
				var course_list_in_sem = year_semesters[sem_key]
				if not course_list_in_sem is Array:
					printerr("Validation Error: Curriculum for %s/%s/%s is not an array." % [prog_id, year_key, sem_key])
					continue
				for c_id_in_curric in course_list_in_sem:
					if not COURSES.has(c_id_in_curric):
						printerr("Validation Error: Course '%s' in curriculum for %s/%s/%s not found in master COURSES." % [c_id_in_curric, prog_id, year_key, sem_key])

	print_debug("Data validation complete.")

func get_course_details(course_id: String) -> Dictionary:
	if COURSES.has(course_id):
		return COURSES[course_id].duplicate(true)
	return {}

func get_program_details(program_id: String) -> Dictionary:
	if PROGRAMS.has(program_id):
		return PROGRAMS[program_id].duplicate(true)
	return {}

func get_program_curriculum_structure(program_id: String) -> Dictionary:
	if PROGRAM_CURRICULUM_STRUCTURE.has(program_id):
		return PROGRAM_CURRICULUM_STRUCTURE[program_id]
	else:
		# printerr("Program ID '%s' not found in PROGRAM_CURRICULUM_STRUCTURE." % program_id) # Can be noisy if called often for non-existent
		return {}

func get_required_courses_for_program(program_id: String) -> Array[String]:
	if PROGRAM_REQUIREMENTS.has(program_id):
		var courses_array: Array = PROGRAM_REQUIREMENTS[program_id]
		var string_array: Array[String] = []
		for item in courses_array:
			if item is String: string_array.append(item)
		return string_array
	return EMPTY_STRING_ARRAY.duplicate() # Ensure it returns a new empty array
	
func generate_random_student_name() -> String:
	if FIRST_NAMES.is_empty() or LAST_NAMES.is_empty(): return "Student Unknown"
	return "%s %s" % [FIRST_NAMES.pick_random(), LAST_NAMES.pick_random()]

func check_prerequisites_met(course_id_to_check: String, completed_course_ids: Array[String]) -> bool:
	var course_data = get_course_details(course_id_to_check)
	if course_data.is_empty() or not course_data.has("prerequisites"): return true 
	var prereqs: Array = course_data.get("prerequisites", []) 
	if prereqs.is_empty(): return true 
	for req_id in prereqs:
		if not req_id in completed_course_ids: return false 
	return true

func get_all_course_ids_in_program_curriculum(program_id: String) -> Array[String]:
	var course_ids: Array[String] = []
	# PROGRAM_CURRICULUM_STRUCTURE is a member variable of UniversityData
	if PROGRAM_CURRICULUM_STRUCTURE.has(program_id):
		var program_curriculum: Dictionary = PROGRAM_CURRICULUM_STRUCTURE[program_id]
		for year_key in program_curriculum: # e.g., "Year 1", "Year 2"
			var year_data: Dictionary = program_curriculum[year_key]
			for semester_key in year_data: # e.g., "Semester 1", "Semester 2"
				var semester_courses: Array = year_data[semester_key]
				for course_id_str in semester_courses:
					if course_id_str is String and not course_ids.has(course_id_str):
						course_ids.append(course_id_str)
	else:
		printerr("UniversityData: No curriculum structure found for program '%s' when getting all course IDs." % program_id)
	return course_ids

# In UniversityData.gd
func get_initial_curriculum_courses(program_id: String) -> Array[String]:
	if not PROGRAM_CURRICULUM_STRUCTURE.has(program_id):
		printerr("UniversityData: Program '%s' not found in PROGRAM_CURRICULUM_STRUCTURE for initial courses." % program_id) # DEBUG
		return EMPTY_STRING_ARRAY # Ensure EMPTY_STRING_ARRAY is defined or use []
	
	var program_struct = PROGRAM_CURRICULUM_STRUCTURE[program_id]
	# Assuming the first year is "Year 1" and first semester is "Semester 1"
	if program_struct.has("Year 1") and program_struct["Year 1"].has("Semester 1"):
		var courses: Array = program_struct["Year 1"]["Semester 1"]
		var string_courses: Array[String] = []
		for c_id in courses:
			if c_id is String: string_courses.append(c_id)
		print_debug("get_initial_curriculum_courses for '%s' IS RETURNING: %s" % [program_id, str(string_courses)]) # Ensure this debug print is active
		return string_courses
	else:
		printerr("UniversityData: Program '%s' curriculum missing 'Year 1/Semester 1' for initial courses." % program_id)
		print_debug("get_initial_curriculum_courses for '%s' IS RETURNING EMPTY (Year1/Sem1 missing)." % program_id) # Ensure this debug print is active
		return EMPTY_STRING_ARRAY # Ensure EMPTY_STRING_ARRAY is defined or use []
		
func print_debug(message: String):
	if DETAILED_LOGGING_ENABLED:
		print("[UniversityData]: %s" % message)
