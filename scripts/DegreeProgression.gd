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

# --- ENSURE THESE ARE PRESENT ---
var faculty_advisor_id: String = ""
enum ThesisStatusEnum { NOT_STARTED, PROPOSAL_APPROVED, IN_PROGRESS, SUBMITTED_FOR_DEFENSE, COMPLETED_PASS, COMPLETED_FAIL }
var thesis_status: ThesisStatusEnum = ThesisStatusEnum.NOT_STARTED
# --- END ENSURE ---

func _init(s_id: String, p_id: String, start_year: int, start_semester: int = 1):
	self.student_id = s_id
	self.program_id = p_id
	self.current_academic_year_in_program = start_year
	self.current_semester_in_program = start_semester
	self.name = "DegreeProgression_%s" % s_id # Set node name

func record_course_completion(course_id: String, grade: String, credits: float, semester_string: String, course_details_ref: Dictionary):
	if course_records.has(course_id) and course_records[course_id].get("grade") != "IP": # IP = In Progress
		print_debug("Student %s already has a final record for course %s." % [student_id, course_id])
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
	
	print_debug("Student %s recorded %s for %s. Total Credits: %.1f" % [student_id, grade, course_id, total_credits_earned])
	# Optional: Recalculate GPA here

func has_completed_course(course_id: String) -> bool:
	if course_records.has(course_id):
		var record = course_records[course_id]
		# Consider a course completed if it has a grade and it's not "In Progress" (IP) or failed (F)
		# Adjust this logic if "F" should still count as "attempted but not successfully completed for prereq purposes"
		return record.has("grade") and record.grade != "IP" and record.grade != "F" # Example: F does not count as completed
	return false

func get_credits_for_course(course_id: String) -> float:
	if course_records.has(course_id) and has_completed_course(course_id): # Check if actually completed with passing grade
		return course_records[course_id].get("credits_earned", 0.0)
	return 0.0

func advance_semester(university_data: UniversityData):
	current_semester_in_program += 1
	
	var semesters_per_year = university_data.get_semesters_per_academic_year(program_id)
	if semesters_per_year == 0: semesters_per_year = 2 # Fallback
	
	if current_semester_in_program > semesters_per_year:
		current_semester_in_program = 1
		current_academic_year_in_program += 1
	
	print_debug("Student %s advanced to Year %d, Semester %d of program %s." % [student_id, current_academic_year_in_program, current_semester_in_program, program_id])

func check_for_graduation(university_data: UniversityData) -> bool:
	if is_graduated: return true
	if not is_instance_valid(university_data):
		printerr("DegreeProgression: UniversityData not valid for graduation check for student %s." % student_id)
		return false

	var program_details = university_data.get_program_details(program_id)
	if program_details.is_empty():
		printerr("DegreeProgression: Program details not found for %s." % program_id)
		return false

	var required_credits = program_details.get("credits_to_graduate", 120.0)
	var required_courses: Array = university_data.get_required_courses_for_program(program_id)

	if total_credits_earned < required_credits:
		#print_debug("Graduation Check (%s): Not enough credits. Has %.1f, Needs %.1f" % [student_id, total_credits_earned, required_credits])
		return false

	for course_id in required_courses:
		if not has_completed_course(course_id): # Uses updated has_completed_course
			#print_debug("Graduation Check (%s): Missing required course %s." % [student_id, course_id])
			return false

	is_graduated = true
	# graduation_date_str = "Somehow get current term/year string here" # TODO
	print_debug("CONGRATULATIONS! Student %s has met graduation requirements for program %s!" % [student_id, program_id])
	return true

func get_summary() -> Dictionary:
	return {
		"student_id": student_id,
		"program_id": program_id,
		"current_academic_year": current_academic_year_in_program,
		"current_semester": current_semester_in_program,
		"total_credits_earned": total_credits_earned,
		"is_graduated": is_graduated,
		"course_records": course_records.duplicate(true)
	}

func get_next_courses_to_take(university_data: UniversityData) -> Array[String]:
	if not is_instance_valid(university_data): 
		printerr("DegreeProgression (%s): UniversityData is not valid in get_next_courses_to_take." % student_id)
		return []
	
	var program_curriculum = university_data.get_program_curriculum_structure(program_id)
	if program_curriculum.is_empty(): 
		print_debug("Student %s: Program curriculum for '%s' is empty." % [student_id, program_id])
		return []

	var year_key = "Year %d" % current_academic_year_in_program
	var semester_key = "Semester %d" % current_semester_in_program
	
	# Fallback for common naming in curriculum structure (UniversityData uses "Year X", "Semester Y")
	if program_curriculum.has(year_key):
		var year_data = program_curriculum[year_key]
		if not year_data.has(semester_key):
			# Try common alternative semester names if primary "Semester X" not found
			if semester_key == "Semester 1":
				if year_data.has("First Semester"): semester_key = "First Semester"
				elif year_data.has("Fall Semester"): semester_key = "Fall Semester"
			elif semester_key == "Semester 2":
				if year_data.has("Second Semester"): semester_key = "Second Semester"
				elif year_data.has("Spring Semester"): semester_key = "Spring Semester"
	else:
		print_debug("Student %s: Curriculum for program '%s' does not have year key '%s'." % [student_id, program_id, year_key])
		return []


	var courses_for_this_term: Array = program_curriculum.get(year_key, {}).get(semester_key, [])
	if courses_for_this_term.is_empty():
		print_debug("Student %s: No courses found in curriculum for '%s', '%s/%s'." % [student_id, program_id, year_key, semester_key])

	var courses_to_take: Array[String] = []
	
	# --- PREREQUISITE LOGIC ---
	# 1. Get a list of all truly completed course IDs for the student
	var student_completed_course_ids: Array[String] = []
	for record_course_id in course_records.keys():
		if has_completed_course(record_course_id): # Uses the updated has_completed_course
			student_completed_course_ids.append(record_course_id)
	# --- END PREREQUISITE LOGIC ---
	
	for course_id_or_obj in courses_for_this_term:
		var course_id_str : String
		if course_id_or_obj is String:
			course_id_str = course_id_or_obj
		elif course_id_or_obj is Dictionary and course_id_or_obj.has("id"):
			course_id_str = course_id_or_obj.id
		else:
			print_debug("Student %s: Encountered invalid course item in curriculum: %s" % [student_id, str(course_id_or_obj)])
			continue

		if not has_completed_course(course_id_str): # Student hasn't already passed this course
			# --- PREREQUISITE LOGIC ---
			# 2. Check if prerequisites for this course_id_str are met by student_completed_course_ids
			var prerequisites_met = university_data.check_prerequisites_met(course_id_str, student_completed_course_ids)
			
			if prerequisites_met:
				courses_to_take.append(course_id_str)
			else:
				print_debug("Student %s: Cannot take '%s' for %s/%s. Prerequisites not met. Student has completed: %s. '%s' needs: %s" % \
					[student_id, course_id_str, year_key, semester_key, str(student_completed_course_ids), course_id_str, str(university_data.get_course_details(course_id_str).get("prerequisites",[]))])
			# --- END PREREQUISITE LOGIC ---
		#else:
			#print_debug("Student %s: Already completed '%s'." % [student_id, course_id_str]) # Optional: log if skipping completed
			
	if not courses_to_take.is_empty():
		print_debug("Student %s: Next courses to take for %s/%s: %s" % [student_id, year_key, semester_key, str(courses_to_take)])
	#else:
		#print_debug("Student %s: No new courses to take for %s/%s (either completed, or prereqs not met for remaining)." % [student_id, year_key, semester_key])

	return courses_to_take

# Helper for consistent debug messages from this class
func print_debug(message: String):
	print("[DegreeProgression %s]: %s" % [student_id if student_id else "NO_ID", message])
