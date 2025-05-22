# ProfessorManager.gd
class_name ProfessorManager
extends Node

signal faculty_member_hired(professor_id: String, professor_data: Professor)
signal faculty_member_fired(professor_id: String, professor_data: Professor) # Or contract_ended
signal faculty_list_updated # Generic signal for UI refresh
signal professor_assigned_to_course(professor_id: String, offering_id: String)
signal professor_unassigned_from_course(professor_id: String, offering_id: String)

# References (assign in editor or find in _ready)
@export var university_data: UniversityData
@export var time_manager: TimeManager
@export var academic_manager: AcademicManager # To get course details, etc.
# @export var research_manager: ResearchManager # When you create it

# --- Data ---
var hired_professors: Dictionary = {} # student_id: Professor (object)
var applicant_pool: Array[Professor] = [] # Array of Professor objects
var next_professor_id: int = 1

const DETAILED_LOGGING_ENABLED: bool = true

func _ready():
	if not is_instance_valid(university_data): # Fallback if needed
		university_data = get_node_or_null("/root/MainScene/UniversityDataNode")
	if not is_instance_valid(time_manager): # Fallback if needed
		time_manager = get_node_or_null("/root/MainScene/TimeManager")
	if not is_instance_valid(academic_manager): # Fallback if needed
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager")
	
	if is_instance_valid(time_manager) and time_manager.has_signal("new_year_started"):
		if not time_manager.is_connected("new_year_started", Callable(self, "_on_new_year_started_faculty_updates")):
			time_manager.new_year_started.connect(Callable(self, "_on_new_year_started_faculty_updates"))
	
	_generate_initial_applicants(5) # Generate some initial applicants
	print_debug("ProfessorManager ready. Applicant pool size: %d" % applicant_pool.size())

func _generate_professor_id() -> String:
	var p_id = "prof_%04d" % next_professor_id
	next_professor_id += 1
	return p_id

func _generate_initial_applicants(count: int):
	if not is_instance_valid(university_data):
		printerr("ProfessorManager: UniversityData not valid, cannot generate applicants.") # Added specific error
		return
	if university_data.FIRST_NAMES.is_empty() or university_data.LAST_NAMES.is_empty():
		printerr("ProfessorManager: UniversityData FIRST_NAMES or LAST_NAMES is empty. Cannot generate applicants.")
		return

	if DETAILED_LOGGING_ENABLED: print_debug("Generating %d initial applicants..." % count) # Added log
	for i in range(count):
		var new_id = _generate_professor_id()
		var random_first_name = university_data.FIRST_NAMES.pick_random()
		var random_last_name = university_data.LAST_NAMES.pick_random()

		var spec_keys = Professor.Specialization.keys()
		var random_spec_name = ""
		if spec_keys.size() > 1: # Ensure there are specializations beyond GENERAL if that's index 0
			# Pick a random specialization name, excluding "GENERAL" if it's the first one
			var attempts = 0
			while attempts < 10 : # Safety break
				random_spec_name = spec_keys.pick_random()
				if random_spec_name != "GENERAL": # Example: Don't generate GENERAL applicants
					break
				attempts += 1
			if random_spec_name == "GENERAL" and spec_keys.size() > 1: # Fallback if only GENERAL was picked
				random_spec_name = spec_keys[1] if spec_keys[0] == "GENERAL" else spec_keys[0]

		var random_spec_enum_val = Professor.Specialization.GENERAL # Default
		if not random_spec_name.is_empty() and Professor.Specialization.has(random_spec_name.to_upper().replace(" ", "_")):
			random_spec_enum_val = Professor.Specialization[random_spec_name.to_upper().replace(" ", "_")]
		elif not random_spec_name.is_empty():
			print_debug("Warning: Could not map random_spec_name '%s' to enum. Defaulting specialization." % random_spec_name)


		var applicant = Professor.new(new_id, "%s %s" % [random_first_name, random_last_name], random_spec_enum_val)
		applicant_pool.append(applicant)
		if DETAILED_LOGGING_ENABLED: print_debug("Generated applicant: %s (%s), Spec: %s" % [applicant.professor_name, applicant.professor_id, applicant.get_specialization_string()])
	if DETAILED_LOGGING_ENABLED: print_debug("Applicant pool generation complete. New size: %d" % applicant_pool.size())

func get_applicants() -> Array[Professor]:
	var typed_applicant_array: Array[Professor] = []
	for applicant_object in applicant_pool: # applicant_pool should contain Professor objects
		if applicant_object is Professor:
			typed_applicant_array.append(applicant_object)
		# else: print_debug("Non-Professor object found in applicant_pool") # Optional debug
	return typed_applicant_array

func get_hired_professors() -> Array[Professor]: # Your explicit return type
	var typed_professor_array: Array[Professor] = [] # Create an explicitly typed array
	for prof_object in hired_professors.values():
		if prof_object is Professor: # Good practice to check the type
			typed_professor_array.append(prof_object)
		elif is_instance_valid(prof_object): # It's valid but not a Professor object
			printerr("ProfessorManager: Non-Professor object found in hired_professors for ID: ", prof_object.professor_id if prof_object.has_method("get") and prof_object.get("professor_id") else "Unknown")
		# else: prof_object might be null or invalid, is_instance_valid would handle it too
	return typed_professor_array

func get_professor_by_id(prof_id: String) -> Professor:
	return hired_professors.get(prof_id, null)

func hire_professor(applicant_professor: Professor, offered_salary: float = -1.0, tenure_track_offered: bool = false) -> bool:
	if not applicant_professor in applicant_pool:
		printerr("ProfessorManager: Attempted to hire professor not in applicant pool.")
		return false
	
	# Basic acceptance logic (can be expanded)
	# For now, assume they always accept if offered their asking salary or more.
	var final_salary = applicant_professor.annual_salary
	if offered_salary >= applicant_professor.annual_salary:
		final_salary = offered_salary
	
	var hired_prof: Professor = applicant_professor # Transfer object
	hired_prof.annual_salary = final_salary
	
	if tenure_track_offered and hired_prof.rank == Professor.Rank.ASSISTANT_PROFESSOR:
		hired_prof.tenure_status = Professor.TenureStatus.TENURE_TRACK
	elif hired_prof.rank >= Professor.Rank.ASSOCIATE_PROFESSOR: # Auto-tenure for higher ranks (example)
		hired_prof.tenure_status = Professor.TenureStatus.TENURED
	else:
		hired_prof.tenure_status = Professor.TenureStatus.NOT_ELIGIBLE

	applicant_pool.erase(hired_prof)
	hired_professors[hired_prof.professor_id] = hired_prof
	
	emit_signal("faculty_member_hired", hired_prof.professor_id, hired_prof)
	emit_signal("faculty_list_updated")
	print_debug("Hired: %s (%s) as %s. Salary: $%.2f" % [hired_prof.professor_name, hired_prof.professor_id, hired_prof.get_rank_string(), hired_prof.annual_salary])
	return true

func fire_professor(professor_id: String):
	if hired_professors.has(professor_id):
		var prof_to_fire: Professor = hired_professors[professor_id]
		
		# Unassign from all courses they are teaching
		for offering_id in prof_to_fire.courses_teaching_ids.duplicate(): # Iterate a copy
			unassign_professor_from_course(professor_id, offering_id)
			
		# TODO: Unassign from research projects via ResearchManager

		hired_professors.erase(professor_id)
		# Optionally add them back to a "fired" or "available elsewhere" pool
		emit_signal("faculty_member_fired", professor_id, prof_to_fire)
		emit_signal("faculty_list_updated")
		print_debug("Fired professor: %s (%s)" % [prof_to_fire.professor_name, professor_id])
		return true
	print_debug("Could not fire professor: ID %s not found." % professor_id)
	return false

func assign_professor_to_course(professor_id: String, offering_id: String) -> bool:
	var prof: Professor = get_professor_by_id(professor_id)
	if not is_instance_valid(prof):
		printerr("Cannot assign: Professor %s not found." % professor_id)
		return false
	
	if not is_instance_valid(academic_manager):
		printerr("Cannot assign course: AcademicManager not available.")
		return false

	# Check if offering exists and is not already assigned (or handle multiple instructors if your system allows)
	var offering_details = academic_manager.get_offering_details(offering_id) # Needs to be comprehensive
	if offering_details.is_empty() or offering_details.get("status") != "scheduled":
		printerr("Cannot assign: Offering %s not found or not scheduled." % offering_id)
		return false
	
	var current_instructor_id = offering_details.get("instructor_id", "")
	if not current_instructor_id.is_empty() and current_instructor_id != professor_id:
		printerr("Cannot assign: Offering %s already taught by %s." % [offering_id, current_instructor_id])
		return false # Or unassign previous first

	# TODO: Check if professor is qualified (specialization matches course) and not overloaded

	if not prof.courses_teaching_ids.has(offering_id):
		prof.courses_teaching_ids.append(offering_id)
		# AcademicManager needs to update its scheduled_class_details
		if academic_manager.has_method("set_instructor_for_offering"):
			academic_manager.set_instructor_for_offering(offering_id, professor_id)
			emit_signal("professor_assigned_to_course", professor_id, offering_id)
			emit_signal("faculty_list_updated") # Or a more specific signal for schedule changes
			print_debug("Assigned Prof. %s (%s) to Offering %s" % [prof.professor_name, professor_id, offering_id])
			return true
		else:
			printerr("AcademicManager missing 'set_instructor_for_offering' method.")
			prof.courses_teaching_ids.erase(offering_id) # Rollback
			return false
	return true # Already assigned

func unassign_professor_from_course(professor_id: String, offering_id: String):
	var prof: Professor = get_professor_by_id(professor_id)
	if is_instance_valid(prof) and prof.courses_teaching_ids.has(offering_id):
		prof.courses_teaching_ids.erase(offering_id)
		if is_instance_valid(academic_manager) and academic_manager.has_method("set_instructor_for_offering"):
			academic_manager.set_instructor_for_offering(offering_id, "") # Clear instructor
			emit_signal("professor_unassigned_from_course", professor_id, offering_id)
			emit_signal("faculty_list_updated")
			print_debug("Unassigned Prof. %s from Offering %s" % [prof.professor_name, offering_id])
		return true
	return false

func _on_new_year_started_faculty_updates(year: int):
	if DETAILED_LOGGING_ENABLED: print_debug("Processing annual faculty updates for year: %d" % year)
	var did_anything_change = false
	for prof_id in hired_professors:
		var prof: Professor = hired_professors[prof_id]
		prof.years_at_university += 1
		prof.years_in_rank += 1
		
		# TODO: Tenure decisions
		if prof.tenure_status == Professor.TenureStatus.TENURE_TRACK:
			if _check_tenure_eligibility_and_grant(prof): # Implement this logic
				did_anything_change = true
		
		# TODO: Promotion decisions
		if _check_promotion_eligibility_and_promote(prof): # Implement this logic
			did_anything_change = true
			
		# TODO: Sabbatical requests/returns
		
		# TODO: Morale changes based on workload, salary, research etc.
		
		# TODO: Salary adjustments (e.g. cost of living, merit raises)
		# prof.annual_salary *= 1.02 # Example 2% COLA
		
	_generate_initial_applicants(randi_range(2,5)) # Replenish applicant pool
	
	if did_anything_change:
		emit_signal("faculty_list_updated")
	print_debug("Applicant pool refreshed. Size: %d" % applicant_pool.size())

func _check_tenure_eligibility_and_grant(prof: Professor) -> bool:
	# Example Logic: Tenure after 6 years as Assistant Prof with good performance
	if prof.rank == Professor.Rank.ASSISTANT_PROFESSOR and prof.years_in_rank >= 6:
		# Check performance (simplified)
		if prof.publications_count > 10 and (prof.student_evaluation_avg > 3.5 or prof.student_evaluation_avg == -1.0):
			prof.tenure_status = Professor.TenureStatus.TENURED
			prof.morale = clampf(prof.morale + 20.0, 0.0, 100.0)
			print_debug("Professor %s (%s) GRANTED TENURE!" % [prof.professor_name, prof.professor_id])
			return true
		else:
			# Potentially deny tenure if performance is consistently poor after several years
			# prof.tenure_status = Professor.TenureStatus.DENIED_TENURE (handle consequences)
			pass 
	return false

func _check_promotion_eligibility_and_promote(prof: Professor) -> bool:
	# Example Logic:
	var promoted = false
	match prof.rank:
		Professor.Rank.ASSISTANT_PROFESSOR:
			if prof.tenure_status == Professor.TenureStatus.TENURED and prof.years_in_rank >= 6 and prof.publications_count > 15:
				prof.rank = Professor.Rank.ASSOCIATE_PROFESSOR
				promoted = true
		Professor.Rank.ASSOCIATE_PROFESSOR:
			if prof.years_in_rank >= 5 and prof.publications_count > 25: # And other criteria
				prof.rank = Professor.Rank.FULL_PROFESSOR
				promoted = true
	
	if promoted:
		prof.years_in_rank = 0
		prof.annual_salary *= 1.15 # Example promotion raise
		prof.morale = clampf(prof.morale + 15.0, 0.0, 100.0)
		print_debug("Professor %s (%s) PROMOTED to %s!" % [prof.professor_name, prof.professor_id, prof.get_rank_string()])
		return true
	return false

func get_total_faculty_salary_expense() -> float:
	var total_salaries: float = 0.0
	for prof_id in hired_professors:
		total_salaries += hired_professors[prof_id].annual_salary
	return total_salaries

func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[ProfManager]: " # Changed prefix
	# ... (same as your print_debug in ProgramManagementUI) ...
	print(final_message)
