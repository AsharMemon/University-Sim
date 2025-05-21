# DegreeProgression.gd
class_name DegreeProgression
extends Node

var student_id: String
var program_id: String
var current_academic_year_in_program: int = 1 # e.g., 1 for Freshman, 2 for Sophomore
var current_semester_in_program: int = 1 # e.g., 1 or 2 (or more if summer is distinct)

# Structure: { "course_id": {"grade": "A/B/F/IP/COMP", "credits_earned": 3, "semester_taken": "Fall 2025"} }
var course_records: Dictionary = {}
var total_credits_earned: float = 0.0
var gpa: float = 0.0 # Optional: Implement if you want GPA calculation

var is_graduated: bool = false
var graduation_date_str: String = "" # e.g., "Spring 2029"

func _init(s_id: String, p_id: String, start_year: int, start_semester: int = 1):
	self.student_id = s_id
	self.program_id = p_id
	self.current_academic_year_in_program = start_year
	self.current_semester_in_program = start_semester
	self.name = "DegreeProgression_%s" % s_id # Set node name

func record_course_completion(course_id: String, grade: String, credits: float, semester_string: String, course_details_ref: Dictionary):
	if course_records.has(course_id) and course_records[course_id].get("grade") != "IP": # IP = In Progress
		print("DegreeProgression: Student %s already has a final record for course %s." % [student_id, course_id])
		return

	course_records[course_id] = {
		"grade": grade,
		"credits_earned": credits if grade != "F" else 0.0, # No credits for failing
		"semester_taken": semester_string,
		"name": course_details_ref.get("name", "Unknown Course")
	}
	
	# Recalculate total credits
	total_credits_earned = 0.0
	for cr_id in course_records:
		total_credits_earned += course_records[cr_id].get("credits_earned", 0.0)
	
	print("DegreeProgression: Student %s recorded %s for %s. Total Credits: %.1f" % [student_id, grade, course_id, total_credits_earned])
	# Optional: Recalculate GPA here

func has_completed_course(course_id: String) -> bool:
	return course_records.has(course_id) and course_records[course_id].get("grade") != "IP"

func get_credits_for_course(course_id: String) -> float:
	if course_records.has(course_id):
		return course_records[course_id].get("credits_earned", 0.0)
	return 0.0

func advance_semester(university_data: UniversityData):
	# This needs to be more robust, considering program length, curriculum structure etc.
	current_semester_in_program += 1
	
	# Example: 2 semesters per academic year
	var semesters_per_year = university_data.get_semesters_per_academic_year(program_id) # Assume this method exists in UniversityData
	if semesters_per_year == 0: semesters_per_year = 2 # Fallback
	
	if current_semester_in_program > semesters_per_year:
		current_semester_in_program = 1
		current_academic_year_in_program += 1
	
	print("DegreeProgression: Student %s advanced to Year %d, Semester %d of program %s." % [student_id, current_academic_year_in_program, current_semester_in_program, program_id])

func check_for_graduation(university_data: UniversityData) -> bool:
	if is_graduated: return true
	if not is_instance_valid(university_data):
		printerr("DegreeProgression: UniversityData not valid for graduation check for student %s." % student_id)
		return false

	var program_details = university_data.get_program_details(program_id)
	if program_details.is_empty():
		printerr("DegreeProgression: Program details not found for %s." % program_id)
		return false

	var required_credits = program_details.get("credits_to_graduate", 120.0) # Get from UniversityData
	var required_courses: Array = university_data.get_required_courses_for_program(program_id) # Get from UniversityData

	if total_credits_earned < required_credits:
		#print("Graduation Check (%s): Not enough credits. Has %.1f, Needs %.1f" % [student_id, total_credits_earned, required_credits])
		return false

	for course_id in required_courses:
		if not has_completed_course(course_id):
			#print("Graduation Check (%s): Missing required course %s." % [student_id, course_id])
			return false
		# Optionally check for minimum grade in required courses if your game has that rule

	is_graduated = true
	# graduation_date_str = "Somehow get current term/year string here" # TODO
	print("CONGRATULATIONS! Student %s has met graduation requirements for program %s!" % [student_id, program_id])
	# Emit a signal or notify a manager
	return true

func get_summary() -> Dictionary:
	return {
		"student_id": student_id,
		"program_id": program_id,
		"current_academic_year": current_academic_year_in_program,
		"current_semester": current_semester_in_program,
		"total_credits_earned": total_credits_earned,
		"is_graduated": is_graduated,
		"course_records": course_records.duplicate(true) # Send a copy
	}

func get_next_courses_to_take(university_data: UniversityData) -> Array[String]:
	if not is_instance_valid(university_data): return []
	
	var program_curriculum = university_data.get_program_curriculum_structure(program_id) # This needs to be robust
	if program_curriculum.is_empty(): return []

	# Determine current year/semester string for curriculum lookup
	# Example: "Year 1, Semester 2" or "Freshman Year, Spring Semester"
	# This is highly dependent on how your UniversityData stores curriculum.
	# For now, let's assume a simple numeric lookup for demonstration.
	
	var year_key = "Year %d" % current_academic_year_in_program # Simplified
	var semester_key = "Semester %d" % current_semester_in_program # Simplified
	
	# Fallback for common naming
	if current_academic_year_in_program == 1 and program_curriculum.has("Freshman Year"): year_key = "Freshman Year"
	if current_academic_year_in_program == 2 and program_curriculum.has("Sophomore Year"): year_key = "Sophomore Year"
	# ... etc.
	
	if semester_key == "Semester 1" and program_curriculum.get(year_key, {}).has("Fall Semester"): semester_key = "Fall Semester"
	if semester_key == "Semester 1" and program_curriculum.get(year_key, {}).has("First Semester"): semester_key = "First Semester"
	if semester_key == "Semester 2" and program_curriculum.get(year_key, {}).has("Spring Semester"): semester_key = "Spring Semester"
	if semester_key == "Semester 2" and program_curriculum.get(year_key, {}).has("Second Semester"): semester_key = "Second Semester"


	var courses_for_this_term: Array = program_curriculum.get(year_key, {}).get(semester_key, [])
	var courses_to_take: Array[String] = []
	
	for course_id_or_obj in courses_for_this_term:
		var course_id_str : String
		if course_id_or_obj is String:
			course_id_str = course_id_or_obj
		elif course_id_or_obj is Dictionary and course_id_or_obj.has("id"): # If curriculum stores more complex objects
			course_id_str = course_id_or_obj.id
		else:
			continue

		if not has_completed_course(course_id_str):
			# Also check prerequisites from UniversityData if that's a feature
			# var course_data = university_data.get_course_details(course_id_str)
			# var prereqs = course_data.get("prerequisites", [])
			# var can_take = true
			# for prereq_id in prereqs:
			#   if not has_completed_course(prereq_id): can_take = false; break
			# if can_take: courses_to_take.append(course_id_str)
			courses_to_take.append(course_id_str)
			
	return courses_to_take
