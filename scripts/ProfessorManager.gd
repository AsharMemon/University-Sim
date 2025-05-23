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

const ProfessorActorScene: PackedScene = preload("res://actors/ProfessorActor.tscn") # Path to your new scene
var active_professor_nodes: Dictionary = {} # professor_id -> ProfessorActor node
var simulated_professors_data: Dictionary = {} # professor_id -> data for off-map simulation

func _ready():
	if not is_instance_valid(university_data): # Fallback if needed
		university_data = get_node_or_null("/root/MainScene/UniversityDataNode")
	if not is_instance_valid(time_manager): # Fallback if needed
		time_manager = get_node_or_null("/root/MainScene/TimeManager")
	if not is_instance_valid(academic_manager): # Fallback if needed
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager")
	
	if not ProfessorActorScene:
		printerr("ProfessorManager: CRITICAL - ProfessorActorScene not preloaded!")
	
	# Connect to TimeManager visual hour change if needed for simulated profs
	if is_instance_valid(time_manager) and time_manager.has_signal("visual_hour_slot_changed"):
		if not time_manager.is_connected("visual_hour_slot_changed", Callable(self, "_on_visual_hour_changed_for_simulation")):
			time_manager.visual_hour_slot_changed.connect(Callable(self, "_on_visual_hour_changed_for_simulation"))

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
	
	# --- NEW: Instantiate Professor Actor ---
	if ProfessorActorScene and ProfessorActorScene.can_instantiate():
		var actor_instance = ProfessorActorScene.instantiate() as ProfessorActor
		var prof_parent = get_parent().get_node_or_null("FacultyActors") # DESIGNATE A PARENT NODE FOR PROF ACTORS
		if not is_instance_valid(prof_parent):
			printerr("ProfessorManager: Cannot find parent node '/root/MainScene/FacultyActors' for ProfessorActor. Actor not spawned.")
		else:
			prof_parent.add_child(actor_instance)
			# Try to find a spawn point (e.g., near an admin building or a generic spawn)
			var spawn_pos = Vector3.ZERO # Default, or find a suitable spawn point
			if is_instance_valid(academic_manager) and is_instance_valid(academic_manager.building_manager):
				# Example: Try to get an entrance of an admin building or a default spawn
				# spawn_pos = academic_manager.building_manager_ref.get_random_building_entrance("admin")
				pass # Implement spawn point logic as needed

			actor_instance.global_position = spawn_pos
			actor_instance.initialize(hired_prof.professor_id, hired_prof.professor_name,
									  self, academic_manager, time_manager, 
									  academic_manager.building_manager if is_instance_valid(academic_manager) else null)
			
			active_professor_nodes[hired_prof.professor_id] = actor_instance
			
			# Connect to the actor's despawn signal
			if not actor_instance.is_connected("professor_despawn_data_for_manager", Callable(self, "_on_professor_actor_despawned")):
				actor_instance.professor_despawn_data_for_manager.connect(Callable(self, "_on_professor_actor_despawned"))

			if DETAILED_LOGGING_ENABLED: print_debug("Spawned ProfessorActor for %s" % hired_prof.professor_name)
	else:
		printerr("ProfessorManager: ProfessorActorScene not loaded or cannot be instantiated.")
	# --- END NEW ---
	
	emit_signal("faculty_member_hired", hired_prof.professor_id, hired_prof)
	emit_signal("faculty_list_updated")
	print_debug("Hired: %s (%s) as %s. Salary: $%.2f" % [hired_prof.professor_name, hired_prof.professor_id, hired_prof.get_rank_string(), hired_prof.annual_salary])
	return true

func fire_professor(professor_id: String):
	if hired_professors.has(professor_id):
		# --- NEW: Remove Professor Actor ---
		if active_professor_nodes.has(professor_id):
			var actor_node = active_professor_nodes[professor_id]
			if is_instance_valid(actor_node):
				actor_node.queue_free()
			active_professor_nodes.erase(professor_id)
			if DETAILED_LOGGING_ENABLED: print_debug("Removed ProfessorActor for %s" % professor_id)
		if simulated_professors_data.has(professor_id): # Also clear from simulation if they were teaching
			simulated_professors_data.erase(professor_id)
		# --- END NEW ---
		
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
		printerr("ProfManager: Cannot assign: Professor %s not found." % professor_id)
		return false
	
	# AcademicManager is now the source of truth for whether the offering is assignable.
	# This function's role is primarily to update the professor's internal list.
	if not prof.courses_teaching_ids.has(offering_id):
		prof.courses_teaching_ids.append(offering_id)
		# No need to call back to AM.set_instructor_for_offering here, as AM initiated this.
		emit_signal("professor_assigned_to_course", professor_id, offering_id)
		# faculty_list_updated might be too broad if only schedule display needs update,
		# but can be kept if professor's display card (e.g. teaching load) needs refresh.
		# emit_signal("faculty_list_updated") 
		print_debug("ProfManager: Linked Prof. %s (%s) to Offering %s" % [prof.professor_name, professor_id, offering_id])
		return true
	# print_debug("ProfManager: Prof. %s already linked to Offering %s" % [professor_id, offering_id])
	return true # Already assigned in professor's list

func unassign_professor_from_course(professor_id: String, offering_id: String):
	var prof: Professor = get_professor_by_id(professor_id)
	if is_instance_valid(prof) and prof.courses_teaching_ids.has(offering_id):
		prof.courses_teaching_ids.erase(offering_id)
		# No need to call back to AM.set_instructor_for_offering("", "")
		emit_signal("professor_unassigned_from_course", professor_id, offering_id)
		# emit_signal("faculty_list_updated")
		print_debug("ProfManager: Unlinked Prof. %s from Offering %s" % [prof.professor_name, offering_id])
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

# --- NEW: Handle Professor Actor Despawn (e.g., when starting to teach) ---
func _on_professor_actor_despawned(data: Dictionary):
	var prof_id = data.get("professor_id")
	if DETAILED_LOGGING_ENABLED: print_debug(["ProfessorActor %s despawned. Activity: %s" % [prof_id, data.get("activity_after_despawn")]])
	
	if prof_id and active_professor_nodes.has(prof_id):
		if data.get("activity_after_despawn") == "teaching":
			var offering_details = academic_manager.get_offering_details(data.activity_target_data.offering_id)
			var sim_data_entry = data.duplicate(true) # Create a mutable copy to add to

			# Ensure sim_activity_day gets the correct day teaching started on
			sim_data_entry["sim_activity_day"] = data.get("current_day_of_despawn", "") # Crucial fix
			
			sim_data_entry["sim_activity_end_time_slot"] = time_manager.get_time_slot_after_duration(
				offering_details.get("start_time_slot"), 
				offering_details.get("duration_slots", 1)
			)
			simulated_professors_data[prof_id] = sim_data_entry # Store the modified data
			if DETAILED_LOGGING_ENABLED:
				print_debug(["  Prof %s now teaching. Despawn Day: %s, Offering Start Slot: %s, Duration: %s slots, Calculated End Slot: %s" % \
					[prof_id, sim_data_entry.sim_activity_day, offering_details.get("start_time_slot"), \
					 offering_details.get("duration_slots", 1), sim_data_entry.sim_activity_end_time_slot]])
		# else handle other despawn activities
	else:
		printerr("ProfessorManager: Received despawn data for unknown or non-active prof_id: %s" % str(prof_id))
		
# --- NEW: Simulate off-map professors (e.g., teaching duration) ---
func _on_visual_hour_changed_for_simulation(day_str: String, time_slot_str: String):
	if simulated_professors_data.is_empty(): return

	var prof_ids_to_respawn: Array[String] = []
	for prof_id in simulated_professors_data:
		var sim_data = simulated_professors_data[prof_id]
		if sim_data.get("activity_after_despawn") == "teaching":
			var teaching_day = sim_data.get("sim_activity_day", "") # Use the stored day
			var class_end_slot = sim_data.get("sim_activity_end_time_slot", "")

			if DETAILED_LOGGING_ENABLED:
				print_debug("Sim check for Prof %s: Current Time: %s %s. Stored Teaching Day: %s. Stored Class End Slot: %s" % [prof_id, day_str, time_slot_str, teaching_day, class_end_slot])

			if day_str == teaching_day and \
			   (time_slot_str == class_end_slot or \
				(is_instance_valid(time_manager) and time_manager.has_method("is_time_slot_after") and \
				 time_manager.is_time_slot_after(day_str, time_slot_str, teaching_day, class_end_slot))):
				
				prof_ids_to_respawn.append(prof_id)
				if DETAILED_LOGGING_ENABLED: print_debug("Prof %s finished teaching. Queued for respawn." % prof_id)
	
	for prof_id_to_respawn in prof_ids_to_respawn:
		if active_professor_nodes.has(prof_id_to_respawn):
			var actor_node = active_professor_nodes[prof_id_to_respawn]
			if is_instance_valid(actor_node) and actor_node.has_method("finish_activity_and_respawn"):
				var sim_prof_data = simulated_professors_data[prof_id_to_respawn]
				var target_data_dict = sim_prof_data.get("activity_target_data", {})
				var classroom_id_of_class = target_data_dict.get("classroom_id", "")
				
				var exit_loc = Vector3.ZERO 
				if not classroom_id_of_class.is_empty() and is_instance_valid(academic_manager) and \
				   is_instance_valid(academic_manager.building_manager) and \
				   academic_manager.building_manager.has_method("get_building_exit_location"): # Check for actual BuildingManager
					
					exit_loc = academic_manager.building_manager.get_building_exit_location(classroom_id_of_class)
					if exit_loc == Vector3.ZERO and DETAILED_LOGGING_ENABLED:
						print_debug("BuildingManager returned ZERO for exit of classroom '%s'. Professor might spawn at map origin or fallback." % classroom_id_of_class)
						# Fallback to classroom center if exit point fails
						var classroom_center = academic_manager.get_classroom_location(classroom_id_of_class)
						if classroom_center != Vector3.ZERO:
							exit_loc = classroom_center # Using center, Y will be adjusted by ProfessorActor
							if DETAILED_LOGGING_ENABLED: print_debug("Fallback exit for %s: using classroom location %s" % [classroom_id_of_class, str(exit_loc.round())])
				else:
					if DETAILED_LOGGING_ENABLED: print_debug("Could not get specific exit location for classroom %s via BuildingManager. Using ZERO or classroom center as fallback." % classroom_id_of_class)
					if is_instance_valid(academic_manager) and not classroom_id_of_class.is_empty() and academic_manager.has_method("get_classroom_location"):
						exit_loc = academic_manager.get_classroom_location(classroom_id_of_class)
					
				if DETAILED_LOGGING_ENABLED: print_debug("Final calculated exit_loc for prof %s: %s" % [prof_id_to_respawn, str(exit_loc.round())])
				
				(actor_node as ProfessorActor).finish_activity_and_respawn(exit_loc)
				simulated_professors_data.erase(prof_id_to_respawn)
		else:
			printerr("ProfessorManager: Tried to respawn prof %s, but no active node found in cache." % prof_id_to_respawn)
