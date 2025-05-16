# UniversityData.gd (Attach to a Node in your scene)
class_name UniversityData 
extends Node

# --- Constants for Empty Typed Arrays ---
const EMPTY_STRING_ARRAY: Array[String] = [] 

# --- Student Names ---
const FIRST_NAMES: Array[String] = [
	"Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Jessie",
	"Chris", "Pat", "Sam", "Dana", "Kim", "Lee", "Max", "Quinn"
]
const LAST_NAMES: Array[String] = [
	"Smith", "Jones", "Williams", "Brown", "Davis", "Miller", "Wilson", "Moore",
	"Garcia", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Perez", "Lee"
]

# --- Course Definitions ---
# "progress_needed": An arbitrary unit representing the total effort to complete the course.
# "credits": The number of credits awarded upon completion.
const COURSES: Dictionary = {
	"CS101": {"name": "Introduction to Programming", "credits": 3, "description": "Fundamentals of programming using Python.", "progress_needed": 100},
	"CS102": {"name": "Data Structures", "credits": 3, "description": "Basic data structures and algorithms.", "progress_needed": 120},
	"CS201": {"name": "Advanced Programming", "credits": 4, "description": "Object-oriented programming and software design.", "progress_needed": 150},
	"CS202": {"name": "Computer Architecture", "credits": 3, "description": "How computers are built and operate.", "progress_needed": 130},
	"MA101": {"name": "Calculus I", "credits": 4, "description": "Differential calculus.", "progress_needed": 150},
	"MA102": {"name": "Linear Algebra", "credits": 3, "description": "Vectors, matrices, and linear transformations.", "progress_needed": 120},
	"EN101": {"name": "Academic Writing", "credits": 3, "description": "Essentials of effective academic writing.", "progress_needed": 90},
	"PH101": {"name": "General Physics I", "credits": 4, "description": "Mechanics, heat, and sound.", "progress_needed": 140},
	"HIST101": {"name": "World History I", "credits": 3, "description": "Survey of world history from ancient times to 1500.", "progress_needed": 100},
	"HIST102": {"name": "European History", "credits": 3, "description": "History of Europe from the Renaissance to the present.", "progress_needed": 110},
	"ART100": {"name": "Introduction to Art", "credits": 3, "description": "Basic concepts and appreciation of art.", "progress_needed": 80}
}

# --- Program/Degree Definitions ---
# "min_credits_for_graduation": The minimum total credits a student must earn to graduate from this program.
const PROGRAMS: Dictionary = {
	"BSC_CS": {"name": "Bachelor of Science in Computer Science", "min_credits_for_graduation": 120},
	"BA_HIST": {"name": "Bachelor of Arts in History", "min_credits_for_graduation": 100},
	"BSC_PHYS": {"name": "Bachelor of Science in Physics", "min_credits_for_graduation": 110}
}

# --- Program Requirements (Required Courses) ---
# Lists the course IDs that are mandatory for each program.
const PROGRAM_REQUIREMENTS: Dictionary = {
	"BSC_CS": ["CS101", "CS102", "MA101", "MA102", "EN101", "CS201", "CS202"],
	"BA_HIST": ["HIST101", "HIST102", "EN101", "ART100"],
	"BSC_PHYS": ["PH101", "MA101", "MA102", "EN101", "CS101"]
}

# --- Academic Periods/Time Slots (Example for future use) ---
# This enum is not actively used yet but can be for more detailed scheduling.
enum AcademicPeriod { DAY_START, MORNING, AFTERNOON, EVENING, DAY_END }


func _ready():
	print("UniversityData Node is ready. Name: " + self.name)
	# Validation checks to ensure data integrity at startup.
	for program_id in PROGRAM_REQUIREMENTS:
		for course_id in PROGRAM_REQUIREMENTS[program_id]:
			if not COURSES.has(course_id):
				printerr("UniversityData Validation Error: Required course '" + course_id + "' for program '" + program_id + "' does not exist in COURSES list.")
	
	for course_id in COURSES:
		if not COURSES[course_id].has("progress_needed"):
			printerr("UniversityData Validation Error: Course '" + course_id + "' is missing 'progress_needed' field.")
		if not COURSES[course_id].has("credits"):
			printerr("UniversityData Validation Error: Course '" + course_id + "' is missing 'credits' field.")
			
	for program_id in PROGRAMS:
		if not PROGRAMS[program_id].has("min_credits_for_graduation"):
			printerr("UniversityData Validation Error: Program '" + program_id + "' is missing 'min_credits_for_graduation' field.")


# --- Helper Functions ---

# Returns a random program ID from the defined programs.
func get_random_program_id() -> String:
	if PROGRAMS.keys().is_empty():
		printerr("UniversityData: No programs defined!")
		return ""
	return PROGRAMS.keys().pick_random()

# Returns an array of required course IDs for a given program ID.
# If the program ID is not found, it returns a predefined empty string array.
func get_required_courses_for_program(program_id: String) -> Array[String]:
	if PROGRAM_REQUIREMENTS.has(program_id):
		# Explicitly construct a new Array[String] to ensure type correctness.
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
		return EMPTY_STRING_ARRAY # Return the predefined constant empty typed array

# Returns a dictionary containing details for a given course ID.
# Returns an empty dictionary if the course ID is not found.
func get_course_details(course_id: String) -> Dictionary:
	if COURSES.has(course_id):
		return COURSES[course_id]
	else:
		printerr("UniversityData: Course ID '" + course_id + "' not found in COURSES.")
		return {} 
		
# Returns a dictionary containing details for a given program ID.
# Returns an empty dictionary if the program ID is not found.
func get_program_details(program_id: String) -> Dictionary:
	if PROGRAMS.has(program_id):
		return PROGRAMS[program_id]
	else:
		printerr("UniversityData: Program ID '" + program_id + "' not found in PROGRAMS.")
		return {}

# Generates and returns a random student name by combining a first and last name.
func generate_random_student_name() -> String:
	if FIRST_NAMES.is_empty() or LAST_NAMES.is_empty():
		printerr("UniversityData: First or Last names list is empty!")
		return "Student Unknown"
	var first_name = FIRST_NAMES.pick_random()
	var last_name = LAST_NAMES.pick_random()
	return first_name + " " + last_name
