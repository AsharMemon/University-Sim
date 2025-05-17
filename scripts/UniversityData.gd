# UniversityData.gd
class_name UniversityData
extends Node

# --- Constants for Empty Typed Arrays ---
const EMPTY_STRING_ARRAY: Array[String] = []

# --- Student Names ---
# IMPORTANT: Replace these example lists with your own more extensive lists of names!
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
	"CS101": {"name": "Intro to Programming", "credits": 3, "description": "Fundamentals of programming using a modern language. Covers variables, control flow, functions, and basic data structures.", "progress_needed": 100},
	"CS102": {"name": "Data Structures", "credits": 3, "description": "Study of fundamental data structures including lists, stacks, queues, trees, and graphs. Algorithm analysis and design.", "progress_needed": 120},
	"CS201": {"name": "Advanced Programming", "credits": 4, "description": "Object-oriented programming principles, software design patterns, and advanced language features.", "progress_needed": 150},
	"CS202": {"name": "Computer Architecture", "credits": 3, "description": "Organization and architecture of computer systems, including CPU design, memory hierarchy, and I/O systems.", "progress_needed": 130},
	"MA101": {"name": "Calculus I", "credits": 4, "description": "Introduction to differential calculus. Limits, continuity, derivatives, and applications.", "progress_needed": 150},
	"MA102": {"name": "Linear Algebra", "credits": 3, "description": "Vectors, matrices, systems of linear equations, determinants, eigenvalues, and eigenvectors.", "progress_needed": 120},
	"EN101": {"name": "Academic Writing", "credits": 3, "description": "Development of effective academic writing skills, focusing on argumentation, research, and critical analysis.", "progress_needed": 90},
	"PH101": {"name": "General Physics I", "credits": 4, "description": "Introduction to classical mechanics, including kinematics, dynamics, work, energy, and momentum. Includes lab component.", "progress_needed": 140},
	"HIST101": {"name": "World History I", "credits": 3, "description": "Survey of world history from ancient civilizations to approximately 1500 CE.", "progress_needed": 100},
	"HIST102": {"name": "European History", "credits": 3, "description": "Survey of European history from the Renaissance to the modern era.", "progress_needed": 110},
	"ART100": {"name": "Introduction to Art", "credits": 3, "description": "Exploration of basic art concepts, history, and appreciation across various media.", "progress_needed": 80},
	
	# Example placeholders for curriculum structure - ensure these have actual details
	"CS_ELECTIVE_EXAMPLE": {"name": "CS Elective", "credits": 3, "description": "A computer science elective focusing on a specialized topic.", "progress_needed": 100},
	"HIST_ELECTIVE_EXAMPLE": {"name": "History Elective", "credits": 3, "description": "A history elective exploring a specific period or theme.", "progress_needed": 100},
	"PHYS_ELECTIVE_EXAMPLE": {"name": "Physics Elective", "credits": 3, "description": "A physics elective on an advanced topic.", "progress_needed": 100},
	"CS_ADV_TOPIC_1": {"name": "Adv. CS Algorithms", "credits": 3, "description": "In-depth study of advanced algorithms and complexity.", "progress_needed": 130},
	"CS_ADV_TOPIC_2": {"name": "Operating Systems", "credits": 3, "description": "Principles of operating system design and implementation.", "progress_needed": 130},
	"CS_CAPSTONE_1": {"name": "CS Capstone Design I", "credits": 3, "description": "First part of a culminating senior design project in computer science.", "progress_needed": 150},
	"CS_CAPSTONE_2": {"name": "CS Capstone Design II", "credits": 3, "description": "Second part and implementation of the senior design project.", "progress_needed": 150},
	"HIST_METHODS": {"name": "Historical Methods", "credits": 3, "description": "Introduction to the methods and theories of historical research and writing.", "progress_needed": 110},
}

# --- Program/Degree Definitions ---
const PROGRAMS: Dictionary = {
	"BSC_CS": {"name": "Bachelor of Science in Computer Science", "min_credits_for_graduation": 120, "unlock_cost": 5000},
	"BA_HIST": {"name": "Bachelor of Arts in History", "min_credits_for_graduation": 100, "unlock_cost": 3000},
	"BSC_PHYS": {"name": "Bachelor of Science in Physics", "min_credits_for_graduation": 110, "unlock_cost": 4500}
}

# --- Program Requirements (Flat list - useful for overall graduation checks) ---
# Ensure this list contains all courses that are absolutely mandatory for graduation in the program.
const PROGRAM_REQUIREMENTS: Dictionary = {
	"BSC_CS": ["CS101", "CS102", "MA101", "MA102", "EN101", "CS201", "CS202", "CS_ADV_TOPIC_1", "CS_ADV_TOPIC_2", "CS_CAPSTONE_1", "CS_CAPSTONE_2", "CS_ELECTIVE_EXAMPLE"],
	"BA_HIST": ["HIST101", "HIST102", "EN101", "ART100", "HIST_METHODS", "HIST_ELECTIVE_EXAMPLE"],
	"BSC_PHYS": ["PH101", "MA101", "MA102", "EN101", "CS101", "PHYS_ELECTIVE_EXAMPLE"]
}

# --- Program Curriculum Structure (For structured display in middle panel) ---
# Defines years, then semesters, then a list of course_ids for that semester.
const PROGRAM_CURRICULUM_STRUCTURE: Dictionary = {
	"BSC_CS": {
		"Freshman Year": {
			"First Semester": ["CS101", "MA101", "EN101"],
			"Second Semester": ["CS102", "MA102", "PH101"] 
		},
		"Sophomore Year": {
			"First Semester": ["CS201", "CS_ELECTIVE_EXAMPLE"],
			"Second Semester": ["CS202"] 
		},
		"Junior Year": { 
			"First Semester": ["CS_ADV_TOPIC_1"], # e.g., Advanced Algorithms
			"Second Semester": ["CS_ADV_TOPIC_2"]  # e.g., Operating Systems
		},
		"Senior Year": { 
			"First Semester": ["CS_CAPSTONE_1"],
			"Second Semester": ["CS_CAPSTONE_2"]
		}
	},
	"BA_HIST": {
		"Freshman Year": {
			"First Semester": ["HIST101", "EN101"],
			"Second Semester": ["HIST102", "ART100"]
		},
		"Sophomore Year": {
			"First Semester": ["HIST_METHODS"],
			"Second Semester": ["HIST_ELECTIVE_EXAMPLE"] 
		}
		# Add Junior/Senior years for BA_HIST if your curriculum defines them
	},
	"BSC_PHYS": {
		"Freshman Year": {
			"First Semester": ["PH101", "MA101"],
			"Second Semester": ["EN101", "MA102"] 
		},
		"Sophomore Year": {
			"First Semester": ["CS101"], # Physics majors might take CS later
			"Second Semester": ["PHYS_ELECTIVE_EXAMPLE"]
		}
		# Add Junior/Senior years for BSC_PHYS
	}
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
		for year_name in year_data:
			var semester_data : Dictionary = year_data[year_name]
			for semester_name in semester_data:
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
			
	for program_id in PROGRAMS:
		if not PROGRAMS[program_id].has("min_credits_for_graduation"):
			printerr("Validation Error: Program '", program_id, "' is missing 'min_credits_for_graduation' field.")
		if not PROGRAMS[program_id].has("unlock_cost"):
			printerr("Validation Warning: Program '", program_id, "' is missing 'unlock_cost' field. Will default to 0.")


# --- Helper Functions ---

func get_program_curriculum_structure(program_id: String) -> Dictionary:
	if PROGRAM_CURRICULUM_STRUCTURE.has(program_id):
		return PROGRAM_CURRICULUM_STRUCTURE[program_id]
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
		return COURSES[course_id].duplicate(true) # Return a copy to prevent accidental modification
	else:
		# This can be noisy if checking for electives that might not be defined yet,
		# so only print error if it's unexpected.
		# printerr("UniversityData: Course ID '" + course_id + "' not found in COURSES.")
		return {}

func get_program_details(program_id: String) -> Dictionary:
	if PROGRAMS.has(program_id):
		return PROGRAMS[program_id].duplicate(true) # Return a copy
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
