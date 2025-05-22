# UniversityData.gd
class_name UniversityData
extends Node

# --- Constants for Empty Typed Arrays ---
const EMPTY_STRING_ARRAY: Array[String] = []

# --- Student Names ---
const FIRST_NAMES: Array[String] = [
	"Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Jessie",
	"Chris", "Pat", "Sam", "Dana", "Kim", "Lee", "Max", "Quinn",
	"River", "Skyler", "Dakota", "Avery", "Cameron", "Drew", "Blake", "Logan"
]

const LAST_NAMES: Array[String] = [
	"Smith", "Jones", "Williams", "Brown", "Davis", "Miller", "Wilson", "Moore",
	"Garcia", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Perez", "Lee",
	"Walker", "Hall", "Allen", "Young", "King", "Wright", "Scott", "Green"
]

# --- Course Definitions ---
# Ensure ALL course IDs used in PROGRAM_CURRICULUM_STRUCTURE are defined here.
const COURSES: Dictionary = {
	"CS101": {"name": "Intro to Programming", "credits": 3.0, "description": "Fundamentals of programming...", "progress_needed": 100, "prerequisites": []},
	"CS102": {"name": "Data Structures", "credits": 3.0, "description": "Study of fundamental data structures...", "progress_needed": 120, "prerequisites": ["CS101"]},
	"CS201": {"name": "Advanced Programming", "credits": 4.0, "description": "Object-oriented programming principles...", "progress_needed": 150, "prerequisites": ["CS102"]},
	"CS202": {"name": "Computer Architecture", "credits": 3.0, "description": "Organization and architecture of computer systems...", "progress_needed": 130, "prerequisites": ["CS102"]}, # Or CS101 depending on strictness
	"MA101": {"name": "Calculus I", "credits": 4.0, "description": "Introduction to differential calculus...", "progress_needed": 150, "prerequisites": []},
	"MA102": {"name": "Linear Algebra", "credits": 3.0, "description": "Vectors, matrices, systems of linear equations...", "progress_needed": 120, "prerequisites": ["MA101"]}, # Typically
	"EN101": {"name": "Academic Writing", "credits": 3.0, "description": "Development of effective academic writing skills...", "progress_needed": 90, "prerequisites": []},
	"PH101": {"name": "General Physics I", "credits": 4.0, "description": "Introduction to classical mechanics...", "progress_needed": 140, "prerequisites": ["MA101"]}, # Often Calc I is a co-req or pre-req
	"HIST101": {"name": "World History I", "credits": 3.0, "description": "Survey of world history...", "progress_needed": 100, "prerequisites": []},
	"HIST102": {"name": "European History", "credits": 3.0, "description": "Survey of European history...", "progress_needed": 110, "prerequisites": []}, # Could require HIST101 or be independent
	"ART100": {"name": "Introduction to Art", "credits": 3.0, "description": "Exploration of basic art concepts...", "progress_needed": 80, "prerequisites": []},
	
	"CS_ELECTIVE_EXAMPLE": {"name": "CS Elective", "credits": 3.0, "description": "A computer science elective...", "progress_needed": 100, "prerequisites": []}, # Electives might have prerequisites based on level
	"HIST_ELECTIVE_EXAMPLE": {"name": "History Elective", "credits": 3.0, "description": "A history elective...", "progress_needed": 100, "prerequisites": []},
	"PHYS_ELECTIVE_EXAMPLE": {"name": "Physics Elective", "credits": 3.0, "description": "A physics elective...", "progress_needed": 100, "prerequisites": []},
	"CS_ADV_TOPIC_1": {"name": "Adv. CS Algorithms", "credits": 3.0, "description": "In-depth study of advanced algorithms...", "progress_needed": 130, "prerequisites": ["CS201"]}, # Example
	"CS_ADV_TOPIC_2": {"name": "Operating Systems", "credits": 3.0, "description": "Principles of operating system design...", "progress_needed": 130, "prerequisites": ["CS202"]}, # Example
	"CS_CAPSTONE_1": {"name": "CS Capstone Design I", "credits": 3.0, "description": "First part of a senior design project...", "progress_needed": 150, "prerequisites": ["CS_ADV_TOPIC_1", "CS_ADV_TOPIC_2"]}, # Example, usually requires most core courses
	"CS_CAPSTONE_2": {"name": "CS Capstone Design II", "credits": 3.0, "description": "Second part of the senior design project...", "progress_needed": 150, "prerequisites": ["CS_CAPSTONE_1"]},
	"HIST_METHODS": {"name": "Historical Methods", "credits": 3.0, "description": "Introduction to historical research...", "progress_needed": 110, "prerequisites": ["HIST101", "HIST102"]}, # Example
}

# --- Program/Degree Definitions ---
const PROGRAMS: Dictionary = {
	"BSC_CS": {"name": "Bachelor of Science in Computer Science", "credits_to_graduate": 120.0, "unlock_cost": 5000, "semesters_per_year": 2}, # NEW: semesters_per_year
	"BA_HIST": {"name": "Bachelor of Arts in History", "credits_to_graduate": 100.0, "unlock_cost": 3000, "semesters_per_year": 2},
	"BSC_PHYS": {"name": "Bachelor of Science in Physics", "credits_to_graduate": 110.0, "unlock_cost": 4500, "semesters_per_year": 2}
}

# --- Program Requirements (Flat list - useful for overall graduation checks) ---
# This list should ideally be derivable from the curriculum structure or be a very strict "must pass these" list.
# For simplicity, keeping it separate but ensure it aligns with curriculum.
const PROGRAM_REQUIREMENTS: Dictionary = {
	"BSC_CS": ["CS101", "CS102", "MA101", "MA102", "EN101", "PH101", "CS201", "CS202", "CS_ADV_TOPIC_1", "CS_ADV_TOPIC_2", "CS_CAPSTONE_1", "CS_CAPSTONE_2"], # Added PH101 as it was in curriculum
	"BA_HIST": ["HIST101", "HIST102", "EN101", "ART100", "HIST_METHODS", "HIST_ELECTIVE_EXAMPLE"], # HIST_ELECTIVE_EXAMPLE might be replaced by choices
	"BSC_PHYS": ["PH101", "MA101", "MA102", "EN101", "CS101", "PHYS_ELECTIVE_EXAMPLE"]
}

# --- Program Curriculum Structure (For structured display and progression) ---
# Defines years, then semesters, then a list of course_ids for that semester.
# Semester keys like "First Semester", "Second Semester" are used by DegreeProgression.
# You could also use "Fall Semester", "Spring Semester" if you want to be more explicit
# and ensure your DegreeProgression logic can map to them.
const PROGRAM_CURRICULUM_STRUCTURE: Dictionary = {
	"BSC_CS": {
		"Year 1": { # Using "Year X" for easier numeric access in DegreeProgression
			"Semester 1": ["CS101", "MA101", "EN101"],
			"Semester 2": ["CS102", "MA102", "PH101"]
		},
		"Year 2": {
			"Semester 1": ["CS201", "CS_ELECTIVE_EXAMPLE"], # Note: Electives need a system for choice
			"Semester 2": ["CS202"]
		},
		"Year 3": {
			"Semester 1": ["CS_ADV_TOPIC_1"],
			"Semester 2": ["CS_ADV_TOPIC_2"]
		},
		"Year 4": {
			"Semester 1": ["CS_CAPSTONE_1"],
			"Semester 2": ["CS_CAPSTONE_2"]
		}
	},
	"BA_HIST": {
		"Year 1": {
			"Semester 1": ["HIST101", "EN101"],
			"Semester 2": ["HIST102", "ART100"]
		},
		"Year 2": {
			"Semester 1": ["HIST_METHODS"],
			"Semester 2": ["HIST_ELECTIVE_EXAMPLE"] # History might be a 2 or 3 year program in some models
		}
		# Add "Year 3", "Year 4" if it's a 4-year BA program.
	},
	"BSC_PHYS": {
		"Year 1": {
			"Semester 1": ["PH101", "MA101"],
			"Semester 2": ["EN101", "MA102"]
		},
		"Year 2": {
			"Semester 1": ["CS101"],
			"Semester 2": ["PHYS_ELECTIVE_EXAMPLE"]
		}
		# Add "Year 3", "Year 4" for a full Physics BSc.
	}
}

const PROFESSOR_RANKS_DATA: Dictionary = {
	Professor.Rank.LECTURER: {"base_salary_min": 35000, "base_salary_max": 55000, "tenure_possible": false},
	Professor.Rank.ASSISTANT_PROFESSOR: {"base_salary_min": 50000, "base_salary_max": 70000, "tenure_possible": true, "years_to_tenure_review": 6},
	Professor.Rank.ASSOCIATE_PROFESSOR: {"base_salary_min": 65000, "base_salary_max": 90000, "tenure_possible": true}, # Often tenured upon promotion
	Professor.Rank.FULL_PROFESSOR: {"base_salary_min": 80000, "base_salary_max": 120000, "tenure_possible": true}, # Often tenured
	Professor.Rank.ADJUNCT: {"base_salary_min": 3000, "base_salary_max": 6000, "per_course": true, "tenure_possible": false} # Example: paid per course
}

const RESEARCH_PROJECT_TEMPLATES: Dictionary = {
	"RP_CS_BASIC_ALGO": {
		"name": "Basic Algorithm Exploration", "field": Professor.Specialization.COMPUTER_SCIENCE,
		"duration_days": 90, "cost_range": [500, 2000], "difficulty": 30, # 0-100
		"potential_outcomes": ["small_publication", "minor_grant_chance"]
	},
	"RP_HIST_ARCHIVAL": {
		"name": "Archival Document Study", "field": Professor.Specialization.HISTORY,
		"duration_days": 120, "cost_range": [1000, 3000], "difficulty": 40,
		"potential_outcomes": ["medium_publication", "reputation_boost_small"]
	}
	# Add more templates
}


func _ready():
	print("UniversityData Node is ready. Name: " + self.name)
	# Validation checks
	for program_id in PROGRAM_REQUIREMENTS:
		if not PROGRAMS.has(program_id):
			printerr("Validation Error: Program ID '", program_id, "' in PROGRAM_REQUIREMENTS does not exist in PROGRAMS list.")
		for course_id in PROGRAM_REQUIREMENTS[program_id]:
			if not COURSES.has(course_id):
				printerr("Validation Error: Required course '", course_id, "' for program '", program_id, "' (from PROGRAM_REQUIREMENTS) does not exist in COURSES list.")
	
	for program_id in PROGRAM_CURRICULUM_STRUCTURE:
		if not PROGRAMS.has(program_id):
			printerr("Validation Error: Program ID '", program_id, "' in PROGRAM_CURRICULUM_STRUCTURE does not exist in PROGRAMS list.")
		var year_data : Dictionary = PROGRAM_CURRICULUM_STRUCTURE[program_id]
		for year_name in year_data: # e.g., "Year 1"
			var semester_data : Dictionary = year_data[year_name]
			for semester_name in semester_data: # e.g., "Semester 1"
				var course_list : Array = semester_data[semester_name]
				for course_id in course_list:
					if not course_id is String:
						printerr("Validation Error: Non-string course ID '", course_id, "' found in PROGRAM_CURRICULUM_STRUCTURE for '", program_id, "/", year_name, "/", semester_name, "'.")
						continue
					if not COURSES.has(course_id):
						printerr("Validation Error: Course '", course_id, "' in PROGRAM_CURRICULUM_STRUCTURE for '", program_id, "/", year_name, "/", semester_name, "' does not exist in COURSES list.")

	for course_id in COURSES:
		if not COURSES[course_id].has("progress_needed"):
			printerr("Validation Error: Course '", course_id, "' is missing 'progress_needed' field.")
		if not COURSES[course_id].has("credits"):
			printerr("Validation Error: Course '", course_id, "' is missing 'credits' field.")
		if not COURSES[course_id].has("prerequisites"): # Added check for prerequisites
			printerr("Validation Warning: Course '", course_id, "' is missing 'prerequisites' field (should be an empty array [] if none).")


	for program_id in PROGRAMS:
		if not PROGRAMS[program_id].has("credits_to_graduate"): # Changed from min_credits_for_graduation for consistency
			printerr("Validation Error: Program '", program_id, "' is missing 'credits_to_graduate' field.")
		if not PROGRAMS[program_id].has("unlock_cost"):
			printerr("Validation Warning: Program '", program_id, "' is missing 'unlock_cost' field. Will default to 0.")
		if not PROGRAMS[program_id].has("semesters_per_year"): # Added check
			printerr("Validation Error: Program '", program_id, "' is missing 'semesters_per_year' field.")


# --- Helper Functions ---

# NEW: Get initial courses for a brand new student in a program
func get_initial_curriculum_courses(program_id: String) -> Array[String]:
	if not PROGRAM_CURRICULUM_STRUCTURE.has(program_id):
		printerr("UniversityData: Program '", program_id, "' not in PROGRAM_CURRICULUM_STRUCTURE for initial courses.")
		return EMPTY_STRING_ARRAY
	
	var program_struct = PROGRAM_CURRICULUM_STRUCTURE[program_id]
	# Assuming the first year is "Year 1" and first semester is "Semester 1"
	if program_struct.has("Year 1") and program_struct["Year 1"].has("Semester 1"):
		var courses: Array = program_struct["Year 1"]["Semester 1"]
		var string_courses: Array[String] = []
		for c_id in courses:
			if c_id is String: string_courses.append(c_id)
		return string_courses
	else:
		printerr("UniversityData: Program '", program_id, "' curriculum missing 'Year 1/Semester 1' for initial courses.")
		return EMPTY_STRING_ARRAY

# NEW: Get how many semesters are considered a full academic year for a program
func get_semesters_per_academic_year(program_id: String) -> int:
	if PROGRAMS.has(program_id) and PROGRAMS[program_id].has("semesters_per_year"):
		return PROGRAMS[program_id].semesters_per_year
	printerr("UniversityData: 'semesters_per_year' not defined for program '", program_id, "'. Defaulting to 2.")
	return 2 # Default to 2 (e.g., Fall/Spring)

# Get the structured curriculum (Year -> Semester -> Courses)
func get_program_curriculum_structure(program_id: String) -> Dictionary:
	if PROGRAM_CURRICULUM_STRUCTURE.has(program_id):
		return PROGRAM_CURRICULUM_STRUCTURE[program_id] # No need to duplicate this const structure usually
	else:
		printerr("UniversityData: Program ID '", program_id, "' not found in PROGRAM_CURRICULUM_STRUCTURE.")
		return {}

func get_random_program_id() -> String:
	if PROGRAMS.keys().is_empty():
		printerr("UniversityData: No programs defined!")
		return ""
	return PROGRAMS.keys().pick_random()

# Returns the FLAT list of all mandatory courses for graduation checks.
func get_required_courses_for_program(program_id: String) -> Array[String]:
	if PROGRAM_REQUIREMENTS.has(program_id):
		var courses_from_dict: Array = PROGRAM_REQUIREMENTS[program_id]
		var typed_courses_array: Array[String] = []
		for course_code in courses_from_dict:
			if course_code is String:
				typed_courses_array.append(course_code)
			else:
				printerr("UniversityData: Non-string element found in PROGRAM_REQUIREMENTS for program '" + program_id + "'. Course code: " + str(course_code))
		return typed_courses_array
	else:
		printerr("UniversityData: Program ID '" + program_id + "' not found in PROGRAM_REQUIREMENTS.")
		return EMPTY_STRING_ARRAY

func get_course_details(course_id: String) -> Dictionary:
	if COURSES.has(course_id):
		return COURSES[course_id].duplicate(true)
	else:
		# Only log error if this is unexpected.
		# print_debug("UniversityData: Course ID '" + course_id + "' not found in COURSES. This might be an elective placeholder.")
		return {}

func get_program_details(program_id: String) -> Dictionary:
	if PROGRAMS.has(program_id):
		return PROGRAMS[program_id].duplicate(true)
	else:
		printerr("UniversityData: Program ID '" + program_id + "' not found in PROGRAMS.")
		return {}

func generate_random_student_name() -> String:
	if FIRST_NAMES.is_empty() or LAST_NAMES.is_empty():
		printerr("UniversityData: First or Last names list is empty!")
		return "Student Unknown"
	var first_name = FIRST_NAMES.pick_random()
	var last_name = LAST_NAMES.pick_random()
	return first_name + " " + last_name

# Optional: Helper to check prerequisites for a course
func check_prerequisites_met(course_id_to_check: String, completed_course_ids: Array[String]) -> bool:
	var course_data = get_course_details(course_id_to_check)
	if course_data.is_empty() or not course_data.has("prerequisites"):
		return true # No data or no prerequisites defined, so assume met

	var prereqs: Array[String] = course_data.get("prerequisites", [])
	if prereqs.is_empty():
		return true # Explicitly no prerequisites

	for req_id in prereqs:
		if not req_id in completed_course_ids:
			return false # Missing a prerequisite
	return true

func print_debug(message: String): # Simple debug print for this class
	print("[UniversityData]: %s" % message)

func get_rank_data(rank_enum: Professor.Rank) -> Dictionary:
	return PROFESSOR_RANKS_DATA.get(rank_enum, {}).duplicate(true)

func get_research_project_template(template_id: String) -> Dictionary:
	return RESEARCH_PROJECT_TEMPLATES.get(template_id, {}).duplicate(true)
