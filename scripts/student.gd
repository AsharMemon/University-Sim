# Student.gd
class_name Student
extends CharacterBody3D

# --- Debug Logging Control ---
const DETAILED_LOGGING_ENABLED: bool = true 

# --- Constants ---
const MAX_NEED_VALUE: float = 100.0
const MIN_NEED_VALUE: float = 0.0
const EXPECTED_NAVMESH_Y: float = 0.3 
const MAX_TIME_STUCK_THRESHOLD: float = 4.0 # Reduced slightly from 15
const MAX_TIME_STUCK_AT_PATH_POINT_THRESHOLD: float = 3.0 # NEW: Time before trying to jolt from intermediate point

# --- Constants for Stuck/Arrival Logic ---
const DESPAWN_PROXIMITY_THRESHOLD: float = 3.0 # How close to be considered "at the door" (units) - slightly increased
const NEAR_DOOR_DESPAWN_DELAY: float = 1.0   # Seconds to be near door before forcing despawn
const SCATTER_DURATION_MIN: float = 2.0      
const SCATTER_DURATION_MAX: float = 3.5      # Reduced max scatter time slightly
const SCATTER_DISTANCE_MIN: float = 2.0      
const SCATTER_DISTANCE_MAX: float = 3.0      

# --- Core Student Information ---
var student_id: String = "default_id"
var student_name: String = "Default Student Name"
var current_program_id: String = ""
var academic_start_year: int = 0 
var current_course_enrollments: Dictionary = {}

var student_level: ProgramResource.ProgramLevel = ProgramResource.ProgramLevel.UNDERGRADUATE
var degree_progression: DegreeProgression

var _last_attended_offering_id: String = ""
var _last_attended_in_visual_slot: String = ""

# --- Node References ---
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var label_3d: Label3D = $Label3D
@export var student_visuals: Node3D 
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# --- Needs, Activity, Managers ---
var needs: Dictionary = { "energy": MAX_NEED_VALUE, "rest": MAX_NEED_VALUE, "study_urge": randf_range(20.0, 40.0) }
var current_activity: String = "idle"
var current_activity_target_data: Variant = null
var time_stuck_trying_to_reach_target: float = 0.0
var current_target_position: Vector3 # Stores the actual final *conceptual* destination

# --- State Variables for Stuck/Arrival Logic ---
var time_spent_near_door: float = 0.0
var time_stuck_at_path_point: float = 0.0 # NEW
var _scatter_timer: Timer = null 

var academic_manager_ref: AcademicManager
var university_data_ref: UniversityData
var time_manager_ref: TimeManager
var building_manager_ref: BuildingManager 

var time_spent_in_current_activity_visual: float = 0.0 # ADD THIS LINE

@export var base_move_speed: float = 2.8 # Slightly reduced base speed
var current_calculated_move_speed: float = 2.8

signal student_despawn_data_for_manager(data: Dictionary)

func _ready():
	if not is_instance_valid(navigation_agent):
		printerr("[%s] CRITICAL: NavigationAgent3D node not found!" % self.name)
	else:
		navigation_agent.set_target_position(global_position)
		if not navigation_agent.is_connected("navigation_finished", Callable(self, "_on_navigation_agent_navigation_finished")):
			navigation_agent.navigation_finished.connect(Callable(self, "_on_navigation_agent_navigation_finished"))
		# Consider setting some NavigationAgent3D properties here if not done in editor:
		# navigation_agent.path_desired_distance = 0.5
		# navigation_agent.target_desired_distance = 0.5 # Students might need to get closer
		# navigation_agent.avoidance_enabled = true
		# navigation_agent.radius = 0.4 # Example
		# navigation_agent.neighbor_dist = 3.0 # Example
		# navigation_agent.max_neighbors = 5 # Example
		# navigation_agent.time_horizon_agents = 1.0 # Example
		# navigation_agent.time_horizon_obstacles = 0.5 # Example
			
	if is_instance_valid(label_3d):
		label_3d.text = student_name if not student_name.is_empty() else "Student"
	
	if not is_instance_valid(student_visuals):
		printerr("[%s] CRITICAL: Student visuals node not found!" % self.name)
	else:
		student_visuals.visible = true

	if not is_instance_valid(animation_player):
		if DETAILED_LOGGING_ENABLED: print_debug_student("Warning: AnimationPlayer node not found.")

	current_calculated_move_speed = base_move_speed
	velocity = Vector3.ZERO
	call_deferred("check_spawn_position_on_navmesh")


func check_spawn_position_on_navmesh():
	await get_tree().physics_frame 
	if DETAILED_LOGGING_ENABLED: print_debug_student("check_spawn_position_on_navmesh: global_position: %s" % str(global_position))
	if is_instance_valid(navigation_agent) and get_world_3d(): 
		var current_map = get_world_3d().navigation_map
		if current_map.is_valid():
			var closest_point_on_navmesh = NavigationServer3D.map_get_closest_point(current_map, global_position)
			var distance_to_navmesh = global_position.distance_to(closest_point_on_navmesh)
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Distance to NavMesh: %.2f. My Y: %.2f. Closest NavMesh Y: %.2f" % [distance_to_navmesh, global_position.y, closest_point_on_navmesh.y])
			if distance_to_navmesh > 0.75 : 
				if DETAILED_LOGGING_ENABLED: print_debug_student("  WARNING: Student possibly spawned/settled too far from NavMesh!")
		elif DETAILED_LOGGING_ENABLED: print_debug_student("  WARNING: Invalid navigation map RID in check_spawn_position_on_navmesh.")
	elif DETAILED_LOGGING_ENABLED: print_debug_student("  WARNING: NavigationAgent or World3D invalid in check_spawn_position_on_navmesh.")


func _connect_to_time_manager_signals():
	if not is_instance_valid(time_manager_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_student("Cannot connect TimeManager signals, time_manager_ref is invalid.")
		return

	if time_manager_ref.has_signal("speed_changed"):
		if not time_manager_ref.is_connected("speed_changed", Callable(self, "_on_time_manager_speed_changed")):
			time_manager_ref.speed_changed.connect(Callable(self, "_on_time_manager_speed_changed"))
		_on_time_manager_speed_changed(time_manager_ref.get_speed_multiplier())
	
	if time_manager_ref.has_signal("visual_hour_slot_changed"):
		if not time_manager_ref.is_connected("visual_hour_slot_changed", Callable(self, "_on_visual_hour_changed")):
			time_manager_ref.visual_hour_slot_changed.connect(Callable(self, "_on_visual_hour_changed"))


func initialize_new_student(s_id: String, s_name: String, prog_id: String, start_year_cal: int,
						 acad_man: AcademicManager, univ_data: UniversityData, time_man: TimeManager,
						 restored_persistent_data: Dictionary = {}):
						 
	if DETAILED_LOGGING_ENABLED: print_debug_student("Initialize Student START for: %s ID: %s, Program: %s" % [s_name, s_id, prog_id])
	self.student_id = s_id
	self.student_name = s_name
	self.name = "Student_%s_%s" % [s_name.replace(" ", "_").to_lower().left(10), s_id.right(4)]
	self.current_program_id = prog_id 
	self.academic_start_year = start_year_cal 
	self.academic_manager_ref = acad_man
	self.university_data_ref = univ_data
	self.time_manager_ref = time_man
	if is_instance_valid(self.academic_manager_ref):
		self.building_manager_ref = self.academic_manager_ref.building_manager
		if self.academic_manager_ref.has_method("_on_student_despawned"):
			if not self.is_connected("student_despawn_data_for_manager", Callable(self.academic_manager_ref, "_on_student_despawned")):
				var err_code = self.student_despawn_data_for_manager.connect(Callable(self.academic_manager_ref, "_on_student_despawned"))
				if err_code != OK: print_debug_student("ERROR connecting student_despawn_data_for_manager. Code: %s" % err_code)
	_connect_to_time_manager_signals()
	if is_instance_valid(label_3d): label_3d.text = self.student_name
	if not restored_persistent_data.is_empty():
		if DETAILED_LOGGING_ENABLED: print_debug_student("Restoring student from persistent data.")
		self.current_program_id = restored_persistent_data.get("current_program_id", prog_id) 
		self.academic_start_year = restored_persistent_data.get("academic_start_year", start_year_cal)
		self.student_level = restored_persistent_data.get("student_level", ProgramResource.ProgramLevel.UNDERGRADUATE)
		self.needs = restored_persistent_data.get("needs", { "energy": MAX_NEED_VALUE, "rest": MAX_NEED_VALUE, "study_urge": randf_range(20.0, 50.0) }).duplicate(true)
		self._last_attended_offering_id = restored_persistent_data.get("_last_attended_offering_id", "")
		self._last_attended_in_visual_slot = restored_persistent_data.get("_last_attended_in_visual_slot", "")
		self.current_course_enrollments.clear()
		var restored_enrollments = restored_persistent_data.get("current_course_enrollments", {})
		for offering_id_key in restored_enrollments:
			if restored_enrollments[offering_id_key] is Dictionary:
				confirm_course_enrollment(offering_id_key, restored_enrollments[offering_id_key]) 
	else: 
		if DETAILED_LOGGING_ENABLED: print_debug_student("No persistent data, initializing as new.")
		self.student_level = ProgramResource.ProgramLevel.UNDERGRADUATE 
		self.needs = { "energy": MAX_NEED_VALUE, "rest": MAX_NEED_VALUE, "study_urge": randf_range(20.0, 50.0) }
		self._last_attended_offering_id = ""
		self._last_attended_in_visual_slot = ""
	if is_instance_valid(university_data_ref) and not self.current_program_id.is_empty():
		var prog_details_for_level = university_data_ref.get_program_details(self.current_program_id)
		if not prog_details_for_level.is_empty() and prog_details_for_level.has("level"):
			self.student_level = prog_details_for_level.get("level")
		if DETAILED_LOGGING_ENABLED: 
				print_debug_student("Student %s (%s) assigned/confirmed for program %s, level %s." % [s_id, s_name, self.current_program_id, ProgramResource.ProgramLevel.keys()[self.student_level]])
	var restored_degree_prog_summary: Dictionary = restored_persistent_data.get("degree_progression_summary", {})
	var dp_advisor_id = restored_degree_prog_summary.get("faculty_advisor_id", "")
	var dp_thesis_status_val = restored_degree_prog_summary.get("thesis_status", 0) 
	if is_instance_valid(self.degree_progression): 
		self.degree_progression.student_id = s_id 
		self.degree_progression.program_id = self.current_program_id
		self.degree_progression.current_academic_year_in_program = restored_degree_prog_summary.get("current_academic_year", 1)
		self.degree_progression.current_semester_in_program = restored_degree_prog_summary.get("current_semester", 1)
		self.degree_progression.total_credits_earned = restored_degree_prog_summary.get("total_credits_earned", 0.0)
		self.degree_progression.is_graduated = restored_degree_prog_summary.get("is_graduated", false)
		self.degree_progression.graduation_date_str = restored_degree_prog_summary.get("graduation_date_str", "")
		self.degree_progression.course_records = restored_degree_prog_summary.get("course_records", {}).duplicate(true)
		self.degree_progression.faculty_advisor_id = dp_advisor_id
		self.degree_progression.thesis_status = dp_thesis_status_val
	else: 
		var start_year_in_prog = restored_degree_prog_summary.get("current_academic_year", 1)
		var start_sem_in_prog = restored_degree_prog_summary.get("current_semester", 1)
		if restored_persistent_data.is_empty() and is_instance_valid(time_man): 
			var current_term_enum = time_man.get_current_academic_term_enum()
			if current_term_enum == TimeManager.AcademicTerm.SPRING: start_sem_in_prog = 2
			elif current_term_enum == TimeManager.AcademicTerm.SUMMER: start_sem_in_prog = 3 
		self.degree_progression = DegreeProgression.new(s_id, self.current_program_id, start_year_in_prog, start_sem_in_prog)
		self.degree_progression.faculty_advisor_id = dp_advisor_id
		self.degree_progression.thesis_status = dp_thesis_status_val
		add_child(self.degree_progression)
		if not restored_degree_prog_summary.is_empty(): 
			self.degree_progression.total_credits_earned = restored_degree_prog_summary.get("total_credits_earned", 0.0)
			self.degree_progression.is_graduated = restored_degree_prog_summary.get("is_graduated", false)
			self.degree_progression.graduation_date_str = restored_degree_prog_summary.get("graduation_date_str", "")
			self.degree_progression.course_records = restored_degree_prog_summary.get("course_records", {}).duplicate(true)
		if DETAILED_LOGGING_ENABLED: print_debug_student("New DegreeProgression initialized. Program Year: %d, Sem: %d. AdvisorID: %s" % [start_year_in_prog, start_sem_in_prog, dp_advisor_id])
	self.velocity = Vector3.ZERO
	if DETAILED_LOGGING_ENABLED: print_debug_student("Initialize Student END for: %s. Student Level: %s. TM valid: %s" % [s_name, ProgramResource.ProgramLevel.keys()[student_level], str(is_instance_valid(time_manager_ref))])


func on_fully_spawned_and_enrolled():
	if DETAILED_LOGGING_ENABLED: print_debug_student("Fully spawned/enrolled. Current activity: %s. Deferred decision." % current_activity)
	if is_instance_valid(student_visuals) and not student_visuals.visible: 
		student_visuals.visible = true
	call_deferred("_decide_next_activity")

# In Student.gd - Replace the entire function with this corrected version.

func _decide_next_activity():
	print_debug_student("--- DECIDE NEXT ACTIVITY CALLED --- Current Activity: %s, GlobalPos: %s" % [current_activity, str(global_position.round())])

	if not is_instance_valid(self):
		printerr("STUDENT ERROR: _decide_next_activity called on an invalid student instance (self is invalid).")
		return

	if not is_instance_valid(time_manager_ref) or \
	   not is_instance_valid(academic_manager_ref) or \
	   not is_instance_valid(navigation_agent) or \
	   not is_instance_valid(university_data_ref):
		print_debug_student("CRITICAL ERROR in _decide_next_activity: One or more manager refs (Time, Academic, NavAgent, UniversityData) are NULL or invalid. Cannot proceed.")
		set_activity("idle")
		return

	var action_taken: bool = false

	if DETAILED_LOGGING_ENABLED:
		print_debug_student("  Full _decide_next_activity START --- Current Activity: " + current_activity +
							", Energy:%.1f, Rest:%.1f, StudyUrge:%.1f" % [needs.energy, needs.rest, needs.study_urge])

	# 1. Check for current class
	var current_class_offering_id = _get_current_visual_class_offering()
	if not current_class_offering_id.is_empty():
		print_debug_student("  DECISION: Found CURRENT class offering: %s" % current_class_offering_id)
		var class_details = current_course_enrollments.get(current_class_offering_id, {})
		var schedule_info = class_details.get("schedule_info", {})
		
		var classroom_id = schedule_info.get("classroom_id") # Get the ID as a Variant
		var course_name = class_details.get("course_name", "N/A Course")

		print_debug_student("    Class Details: Name='%s', ClassroomID (from student's record)='%s'" % [course_name, str(classroom_id)])

		if classroom_id == null or (classroom_id is String and classroom_id.is_empty()):
			if DETAILED_LOGGING_ENABLED: print_debug_student("    Action: Class '%s' has a missing classroom_id." % course_name)
		else:
			var classroom_location: Vector3 = academic_manager_ref.get_classroom_location(classroom_id) # Pass the Variant ID
			print_debug_student("    Classroom Location for '%s' (ID: %s) from AcademicManager: %s" % [course_name, str(classroom_id), str(classroom_location.round())])
			
			if classroom_location != Vector3.ZERO:
				var target_data_for_class = {
					"offering_id": current_class_offering_id,
					"classroom_id": classroom_id,
					"destination_name": "Class: " + course_name,
					"course_name": course_name
				}
				set_activity("going_to_class", target_data_for_class)
				navigate_to_target(classroom_location)
				action_taken = true
			else:
				if DETAILED_LOGGING_ENABLED: print_debug_student("    Action: Class '%s' classroom location for ID '%s' was not found." % [course_name, str(classroom_id)])
		
		if action_taken: return

	# 2. Check for upcoming class if late in the current hour
	if not action_taken and is_instance_valid(time_manager_ref) and time_manager_ref.get_current_simulation_minute() >= 45:
		if DETAILED_LOGGING_ENABLED: print_debug_student("  No current class. Checking for UPCOMING class (minute >= 45)...")
		var upcoming_data: Dictionary = _get_next_class_to_prepare_for()

		if not upcoming_data.is_empty():
			var upcoming_offering_id = upcoming_data.get("offering_id")
			var upcoming_enrollment_details = upcoming_data.get("details", {})
			var schedule_info_upcoming = upcoming_enrollment_details.get("schedule_info", {})
			
			var classroom_id_up = schedule_info_upcoming.get("classroom_id") # Get the ID as a Variant
			var course_name_up = upcoming_enrollment_details.get("course_name", "N/A Upcoming")
			
			print_debug_student("    Upcoming Class Details: Name='%s', ClassroomID='%s'" % [course_name_up, str(classroom_id_up)])

			if classroom_id_up == null or (classroom_id_up is String and classroom_id_up.is_empty()):
				if DETAILED_LOGGING_ENABLED: print_debug_student("    Action: Found UPCOMING class '%s' but classroom_id is missing/invalid ('%s'). Cannot prepare." % [course_name_up, str(classroom_id_up)])
			else:
				var classroom_loc_up: Vector3 = academic_manager_ref.get_classroom_location(classroom_id_up) # Pass the Variant ID
				print_debug_student("    Upcoming Classroom Location for '%s' (ID: %s) from AM: %s" % [course_name_up, str(classroom_id_up), str(classroom_loc_up.round())])
				
				if classroom_loc_up != Vector3.ZERO:
					var target_data_for_upcoming_class = {
						"offering_id": upcoming_offering_id,
						"classroom_id": classroom_id_up,
						"destination_name": "Next Class: " + course_name_up,
						"course_name": course_name_up
					}
					set_activity("going_to_class", target_data_for_upcoming_class)
					navigate_to_target(classroom_loc_up)
					action_taken = true
				else:
					if DETAILED_LOGGING_ENABLED: print_debug_student("    Action: Found UPCOMING class '%s' but classroom location for ID '%s' was ZERO. Cannot prepare." % [course_name_up, str(classroom_id_up)])
		elif DETAILED_LOGGING_ENABLED:
			print_debug_student("  No UPCOMING class found by _get_next_class_to_prepare_for for this hour.")
		
		if action_taken: return

	# 3. Address Needs (Energy/Rest)
	if not action_taken and (needs.get("energy", MAX_NEED_VALUE) < 25.0 or needs.get("rest", MAX_NEED_VALUE) < 30.0):
		if current_activity != "resting" and current_activity != "going_to_rest":
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: Low Energy (%.1f) or Rest (%.1f). Attempting to find dorm." % [needs.energy, needs.rest])
			if _find_and_go_to_functional_building("going_to_rest", "dorm"):
				if DETAILED_LOGGING_ENABLED: print_debug_student("    ACTION TAKEN: Going to REST (Low Energy/Rest).")
				action_taken = true
			elif current_activity != "wandering_tired":
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: Critically need rest but no available dorm. Setting to 'wandering_tired'.")
				set_activity("wandering_tired")
				action_taken = false
			else:
				action_taken = false
		if action_taken and current_activity == "going_to_rest": return

	# 4. Address Study Urge
	if not action_taken and needs.get("study_urge", MIN_NEED_VALUE) > 75.0:
		if current_activity != "studying" and current_activity != "going_to_study":
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: High Study Urge (%.1f). Attempting to find library/study spot." % needs.study_urge)
			if _find_and_go_to_functional_building("going_to_study", "library"):
				if DETAILED_LOGGING_ENABLED: print_debug_student("    ACTION TAKEN: Going to STUDY (High Urge).")
				action_taken = true
			elif current_activity != "wandering_anxious":
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: High urge to study but no available study location. Setting to 'wandering_anxious'.")
				set_activity("wandering_anxious")
				action_taken = false
			else:
				action_taken = false
		if action_taken and current_activity == "going_to_study": return

	# 5. Fallback to Wandering or re-evaluating current wander
	if not action_taken:
		var wandering_states = ["idle", "wandering_campus", "wandering_tired", "wandering_anxious", "scattering_from_class"]
		var needs_new_wander_target = false

		if current_activity == "idle":
			needs_new_wander_target = true
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Fallback: Was idle, requires new wander target.")
		elif wandering_states.has(current_activity):
			if not is_instance_valid(navigation_agent) or \
			   navigation_agent.is_navigation_finished() or \
			   navigation_agent.get_target_position() == global_position or \
			   not navigation_agent.is_target_reachable():
				needs_new_wander_target = true
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Wander state ('%s') needs new target (finished path, at current target, or target unreachable)." % current_activity)
		else:
			needs_new_wander_target = true
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Fallback: Current activity '%s' did not result in pathing action. Requires new wander target." % current_activity)
		
		if needs_new_wander_target:
			var wander_activity_to_set = current_activity
			if wander_activity_to_set == "idle" or wander_activity_to_set == "scattering_from_class":
				wander_activity_to_set = "wandering_campus"
				if needs.get("energy", MAX_NEED_VALUE) < 35.0 or needs.get("rest", MAX_NEED_VALUE) < 40.0:
					wander_activity_to_set = "wandering_tired"
				elif needs.get("study_urge", MIN_NEED_VALUE) > 65.0:
					wander_activity_to_set = "wandering_anxious"
			
			set_activity(wander_activity_to_set)
			
			var wander_offset_base_magnitude = randf_range(8.0, 15.0)
			var wander_offset_direction = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
			if wander_offset_direction == Vector3.ZERO:
				wander_offset_direction = Vector3.FORWARD if randf() < 0.5 else Vector3.BACK
			var wander_offset = wander_offset_direction * wander_offset_base_magnitude
			
			var new_wander_target = global_position + wander_offset
			
			if DETAILED_LOGGING_ENABLED:
				print_debug_student("    ACTION TAKEN: Setting NEW '%s' target to: %s (from global_pos: %s + offset: %s)" % [wander_activity_to_set, str(new_wander_target.round()), str(global_position.round()), str(wander_offset.round())])
			navigate_to_target(new_wander_target)
			action_taken = true
		elif DETAILED_LOGGING_ENABLED:
			print_debug_student("  Continuing current activity: '%s' towards %s. No new action decided." % [current_activity, str(navigation_agent.get_target_position().round())])
			action_taken = true
	
	if not action_taken and DETAILED_LOGGING_ENABLED:
		print_debug_student("  ULTIMATE FALLBACK: _decide_next_activity FINISHED WITH NO ACTION TAKEN! Current activity: %s. Forcing idle and re-decision deferred." % current_activity)
		if current_activity != "idle":
			set_activity("idle")
		call_deferred("_decide_next_activity")

	if DETAILED_LOGGING_ENABLED: print_debug_student("--- DECIDE NEXT ACTIVITY END --- Final Activity Set: %s ---" % current_activity)

# In Student.gd - Replace the entire function with this corrected version

func confirm_course_enrollment(offering_id: String, course_offering_details: Dictionary):
	if DETAILED_LOGGING_ENABLED:
		print_debug_student("Confirming enrollment for offering: %s" % offering_id)

	var course_id_to_use = course_offering_details.get("course_id", "N/A")
	var course_name_to_use = course_offering_details.get("course_name", "N/A Course Name")
	var offering_current_status = course_offering_details.get("status", "unknown")
	var base_course_data = {}
	if is_instance_valid(university_data_ref):
		base_course_data = university_data_ref.get_course_details(course_id_to_use)
		if course_name_to_use == "N/A Course Name" and base_course_data.has("name"):
			course_name_to_use = base_course_data.get("name")

	# --- START OF FIX ---
	# This logic now handles both the "flat" data from AcademicManager and the
	# "nested" schedule_info data that comes from the student's own saved state
	# during a respawn.
	var schedule_data_source = course_offering_details
	if course_offering_details.has("schedule_info") and course_offering_details["schedule_info"] is Dictionary:
		# If the nested structure exists (from a respawn), use it as the source.
		schedule_data_source = course_offering_details["schedule_info"]
	# --- END OF FIX ---

	# Now, read the schedule details from the correct source dictionary.
	var final_classroom_id = schedule_data_source.get("classroom_id")
	var final_pattern = schedule_data_source.get("pattern")
	var final_start_time_slot = schedule_data_source.get("start_time_slot")
	var final_duration_slots = schedule_data_source.get("duration_slots", 1)

	# Rebuild the enrollment entry with the now-correct data.
	current_course_enrollments[offering_id] = {
		"offering_id": offering_id, "course_id": course_id_to_use,
		"course_name": course_name_to_use, "status": offering_current_status,
		"credits": base_course_data.get("credits", course_offering_details.get("credits",0.0)),
		"progress_needed_for_completion": base_course_data.get("progress_needed", 100),
		"schedule_info": {
			"classroom_id": final_classroom_id,
			"pattern": str(final_pattern) if final_pattern != null else "",
			"start_time_slot": str(final_start_time_slot) if final_start_time_slot != null else "",
			"duration_slots": int(final_duration_slots) if final_duration_slots is int else 1
		}
	}
	if DETAILED_LOGGING_ENABLED: print_debug_student("Enrollment confirmed/updated for: %s (%s) with classroom '%s' and pattern '%s'" % [offering_id, course_name_to_use, str(final_classroom_id), str(final_pattern)])
	
func navigate_to_target(target_pos_from_ai: Vector3):
	print_debug_student("NAVIGATE_TO_TARGET called with target_pos_from_ai: %s" % str(target_pos_from_ai.round())) # DEBUG

	if not is_instance_valid(navigation_agent): 
		printerr("[%s] No NavAgent! Cannot navigate." % self.name)
		return

	current_target_position = Vector3(target_pos_from_ai.x, EXPECTED_NAVMESH_Y, target_pos_from_ai.z)
	print_debug_student("  Set current_target_position (conceptual destination) to: %s" % str(current_target_position.round())) # DEBUG
	
	var final_nav_target_for_agent = current_target_position 
	
	if get_world_3d() and get_world_3d().navigation_map.is_valid(): 
		var nav_map_rid = get_world_3d().navigation_map
		var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map_rid, current_target_position)
		print_debug_student("  NavMesh snapped conceptual target %s to: %s" % [str(current_target_position.round()), str(snapped_pos.round())]) # DEBUG
		
		if snapped_pos.distance_to(current_target_position) > 5.0 and DETAILED_LOGGING_ENABLED: 
			print_debug_student("  WARNING: Nav target snapped to a very distant point. Using original conceptual target for agent to avoid extreme jumps.")
			# final_nav_target_for_agent remains current_target_position
		else:
			final_nav_target_for_agent = snapped_pos 
	elif DETAILED_LOGGING_ENABLED: 
		print_debug_student("  Warning: No World3D/NavMap for navigation snapping. Using conceptual target for agent: %s" % str(current_target_position.round()))
		
	navigation_agent.set_target_position(final_nav_target_for_agent)
	print_debug_student("  NavigationAgent3D.set_target_position called with: %s" % str(final_nav_target_for_agent.round())) # DEBUG

	time_stuck_trying_to_reach_target = 0.0 
	time_spent_near_door = 0.0 
	time_stuck_at_path_point = 0.0
	
	if DETAILED_LOGGING_ENABLED: print_debug_student("Navigation target process finished. Agent's actual target: %s" % str(navigation_agent.get_target_position().round()))

# ... (constants and variables, including DESPAWN_PROXIMITY_THRESHOLD, NEAR_DOOR_DESPAWN_DELAY) ...
# Add a new constant for checking if movement is very slow (stalled)
const STALLED_VELOCITY_THRESHOLD_SQR: float = 0.01 * 0.01 # Square of 0.01 m/s

# ...

func _physics_process(delta: float):
	if not is_instance_valid(navigation_agent): return

	if navigation_agent.is_navigation_finished():
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO 
		# _on_navigation_agent_navigation_finished handles arrival logic
		return

	if is_instance_valid(student_visuals) and not student_visuals.visible: 
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		return

	var target_is_reachable = navigation_agent.is_target_reachable()
	var nav_agent_internal_target = navigation_agent.get_target_position()

	# Intermediate path point stuck check (keep this)
	if navigation_agent.is_target_reached() and not navigation_agent.is_navigation_finished():
		if velocity.length_squared() < STALLED_VELOCITY_THRESHOLD_SQR: 
			time_stuck_at_path_point += delta
			if time_stuck_at_path_point > MAX_TIME_STUCK_AT_PATH_POINT_THRESHOLD:
				print_debug_student("Stuck at intermediate path point for activity: %s. Forcing nav target refresh to final conceptual target." % current_activity)
				navigation_agent.set_target_position(current_target_position) 
				time_stuck_at_path_point = 0.0 
		else:
			time_stuck_at_path_point = 0.0
	else:
		time_stuck_at_path_point = 0.0

	if target_is_reachable:
		var next_path_pos = navigation_agent.get_next_path_position()
		var direction_to_next = global_position.direction_to(next_path_pos)
		
		if direction_to_next.length_squared() > (navigation_agent.path_desired_distance * 0.5) * (navigation_agent.path_desired_distance * 0.5) : # Only move if not very close
			velocity = direction_to_next.normalized() * current_calculated_move_speed
			# ... (animation logic) ...
		else: 
			velocity = Vector3.ZERO 
			# ... (animation logic) ...
		
		if velocity.length_squared() > 0.01: 
			look_at(global_position + velocity.normalized() * Vector3(1,0,1), Vector3.UP) 
		
		time_stuck_trying_to_reach_target = 0.0 
		if has_meta("has_repathed_to_class"): remove_meta("has_repathed_to_class")

		# --- Modified Proximity Despawn Logic for "going_to_class" ---
		if current_activity == "going_to_class":
			var distance_to_final_conceptual_target = global_position.distance_to(current_target_position) 
			if distance_to_final_conceptual_target < DESPAWN_PROXIMITY_THRESHOLD:
				time_spent_near_door += delta
				# If velocity is very low (stalled by others) AND near door, despawn quicker
				var stalled_near_door = (velocity.length_squared() < STALLED_VELOCITY_THRESHOLD_SQR)
				if DETAILED_LOGGING_ENABLED and int(time_spent_near_door * 2) % 2 == 0 and time_spent_near_door > 0.1:
					print_debug_student("Near classroom door (dist: %.2f) for %.1fs. Stalled: %s" % [distance_to_final_conceptual_target, time_spent_near_door, str(stalled_near_door)])
				
				if time_spent_near_door > NEAR_DOOR_DESPAWN_DELAY or \
				  (stalled_near_door and time_spent_near_door > NEAR_DOOR_DESPAWN_DELAY / 2.0): # Quicker despawn if stalled
					print_debug_student("Close to classroom door (Dist: %.2f, TimeNear: %.1f, Stalled: %s). Forcing arrival for: %s" % [distance_to_final_conceptual_target, time_spent_near_door, str(stalled_near_door), str(current_activity_target_data.get("course_name"))])
					_on_navigation_agent_navigation_finished() 
					return 
			else:
				time_spent_near_door = 0.0 
		else: # Not going to class
			time_spent_near_door = 0.0 
		# --- End Modified Proximity Despawn ---
	else: # Target not reachable
		# ... (existing stuck logic with repath and scatter - this part remains important) ...
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO 
		# ... (animation logic for idle) ...
		
		var activity_can_get_stuck = current_activity in ["going_to_class", "going_to_rest", "going_to_study", "wandering_campus", "wandering_tired", "wandering_anxious", "scattering_from_class"]
		if activity_can_get_stuck:
			time_stuck_trying_to_reach_target += delta
			if DETAILED_LOGGING_ENABLED and int(time_stuck_trying_to_reach_target * 2) % 6 == 0 and time_stuck_trying_to_reach_target > 0.5: 
				print_debug_student("Physics: TARGET UNREACHABLE for '%s' (%.1fs stuck). NavAgent Target: %s, Final Conceptual Target: %s" % [current_activity, time_stuck_trying_to_reach_target, str(nav_agent_internal_target.round()), str(current_target_position.round())])

			if time_stuck_trying_to_reach_target > MAX_TIME_STUCK_THRESHOLD:
				if DETAILED_LOGGING_ENABLED: print_debug_student("GIVING UP on current target for '%s' after %.1fs." % [current_activity, time_stuck_trying_to_reach_target])
				var did_special_stuck_action = false
				if current_activity == "going_to_class" and current_activity_target_data is Dictionary:
					var class_target_data_on_stuck = current_activity_target_data 
					if not get_meta("has_repathed_to_class", false):
						set_meta("has_repathed_to_class", true)
						var classroom_id_stuck = class_target_data_on_stuck.get("classroom_id")
						if not str(classroom_id_stuck).is_empty():
							var new_classroom_location = academic_manager_ref.get_classroom_location(str(classroom_id_stuck))
							if new_classroom_location != Vector3.ZERO:
								print_debug_student("Stuck going to class. Attempting ONE repath to classroom %s" % str(classroom_id_stuck))
								navigate_to_target(new_classroom_location)
								did_special_stuck_action = true
							# ...
					else: 
						print_debug_student("Already tried repath for this class. Attempting to 'scatter'.")
						var stuck_at_pos = global_position 
						var scatter_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
						if scatter_dir == Vector3.ZERO: scatter_dir = Vector3.RIGHT if randf() < 0.5 else Vector3.LEFT
						var scatter_dist = randf_range(SCATTER_DISTANCE_MIN, SCATTER_DISTANCE_MAX)
						var temp_scatter_target = stuck_at_pos + scatter_dir * scatter_dist
						set_activity("scattering_from_class", {"original_target_data": class_target_data_on_stuck.duplicate(true)}) # Duplicate data
						navigate_to_target(temp_scatter_target)
						if is_instance_valid(_scatter_timer) and not _scatter_timer.is_stopped(): _scatter_timer.stop() 
						if not is_instance_valid(_scatter_timer):
							_scatter_timer = Timer.new()
							_scatter_timer.name = "StudentScatterTimer_%s" % student_id 
							add_child(_scatter_timer) 
							_scatter_timer.one_shot = true 
							_scatter_timer.timeout.connect(Callable(self, "_on_scatter_timer_timeout").bind(class_target_data_on_stuck.duplicate(true)), CONNECT_ONE_SHOT)
						_scatter_timer.wait_time = randf_range(SCATTER_DURATION_MIN, SCATTER_DURATION_MAX)
						_scatter_timer.start()
						did_special_stuck_action = true
				if not did_special_stuck_action:
					set_activity("idle"); call_deferred("_decide_next_activity") 
				return 
				
	move_and_slide()


func _on_navigation_agent_navigation_finished():
	if DETAILED_LOGGING_ENABLED: print_debug_student("Navigation FINISHED. Activity: '%s'. Target Pos: %s. My Pos: %s" % [current_activity, str(navigation_agent.get_target_position().round()), str(global_position.round())])
	velocity = Vector3.ZERO
	time_stuck_trying_to_reach_target = 0.0
	time_spent_near_door = 0.0 
	time_stuck_at_path_point = 0.0
	if has_meta("has_repathed_to_class"): remove_meta("has_repathed_to_class")
	
	if is_instance_valid(_scatter_timer) and not _scatter_timer.is_stopped():
		_scatter_timer.stop()
		_scatter_timer.queue_free() 
		_scatter_timer = null
		if DETAILED_LOGGING_ENABLED: print_debug_student("Scatter timer stopped and freed due to navigation_finished.")

	var previous_activity_on_arrival = current_activity
	var target_data_on_arrival = current_activity_target_data # This is a shallow copy for variants, deep for dict/array if it was duplicated when set
	
	var despawn_activity_type = ""
	var building_id_for_despawn = "" 
	var can_enter_and_despawn = true 

	match previous_activity_on_arrival:
		"going_to_class":
			despawn_activity_type = "in_class"
			if target_data_on_arrival is Dictionary:
				building_id_for_despawn = str(target_data_on_arrival.get("classroom_id", "UNKNOWN_CLASS_ID"))
				_last_attended_offering_id = target_data_on_arrival.get("offering_id", "")
				if is_instance_valid(time_manager_ref):
					_last_attended_in_visual_slot = time_manager_ref.get_current_visual_time_slot_string()
			if is_instance_valid(building_manager_ref) and not building_id_for_despawn.begins_with("UNKNOWN"):
				if not building_manager_ref.student_entered_functional_building(building_id_for_despawn):
					can_enter_and_despawn = false
					if DETAILED_LOGGING_ENABLED: print_debug_student("Classroom %s full or entry issue on arrival." % building_id_for_despawn)
			elif not is_instance_valid(building_manager_ref):
				if DETAILED_LOGGING_ENABLED: print_debug_student("BuildingManager invalid on class arrival, assuming entry for %s." % building_id_for_despawn)

		"going_to_rest":
			despawn_activity_type = "resting"
			if target_data_on_arrival is Dictionary:
				building_id_for_despawn = str(target_data_on_arrival.get("building_id", "UNKNOWN_DORM_ID"))
			if is_instance_valid(building_manager_ref) and not building_id_for_despawn.begins_with("UNKNOWN"):
				if not building_manager_ref.student_entered_functional_building(building_id_for_despawn):
					can_enter_and_despawn = false
					if DETAILED_LOGGING_ENABLED: print_debug_student("Dorm %s full or entry issue on arrival." % building_id_for_despawn)

		"going_to_study":
			despawn_activity_type = "studying"
			if target_data_on_arrival is Dictionary:
				building_id_for_despawn = str(target_data_on_arrival.get("building_id", "UNKNOWN_STUDY_ID"))
			if is_instance_valid(building_manager_ref) and not building_id_for_despawn.begins_with("UNKNOWN"):
				if not building_manager_ref.student_entered_functional_building(building_id_for_despawn):
					can_enter_and_despawn = false
					if DETAILED_LOGGING_ENABLED: print_debug_student("Study loc %s full or entry issue on arrival." % building_id_for_despawn)
		_: 
			set_activity("idle") 
			call_deferred("_decide_next_activity")
			return 

	if not despawn_activity_type.is_empty() and can_enter_and_despawn:
		var despawn_data_package = get_info_summary() 
		despawn_data_package["activity_after_despawn"] = despawn_activity_type
		# Ensure activity_target_data in the package is a deep copy if it's a dict/array
		despawn_data_package["activity_target_data"] = target_data_on_arrival.duplicate(true) if target_data_on_arrival is Dictionary or target_data_on_arrival is Array else target_data_on_arrival
		despawn_data_package["building_id"] = building_id_for_despawn 
		emit_signal("student_despawn_data_for_manager", despawn_data_package)
		if is_instance_valid(student_visuals): student_visuals.visible = false
		self.process_mode = Node.PROCESS_MODE_DISABLED 
		navigation_agent.set_target_position(global_position) 
		velocity = Vector3.ZERO
		if DETAILED_LOGGING_ENABLED: print_debug_student("Despawned for '%s'. Awaiting re-activation." % despawn_activity_type)
		return 
		
	elif not despawn_activity_type.is_empty() and not can_enter_and_despawn: 
		print_debug_student("Entry to %s at %s DENIED (e.g. full). Setting to idle." % [despawn_activity_type, building_id_for_despawn])
		set_activity("idle") 
		call_deferred("_decide_next_activity")
		return

	set_activity("idle") 
	call_deferred("_decide_next_activity")


func _on_scatter_timer_timeout(original_class_target_data_copy: Dictionary): # original_class_target_data is now a copy
	if DETAILED_LOGGING_ENABLED: print_debug_student("Scatter timer timeout. Original class target data: %s" % str(original_class_target_data_copy))

	if is_instance_valid(_scatter_timer): # Should be valid if timeout signal connected
		_scatter_timer.queue_free() 
		_scatter_timer = null
	
	# If current activity is still scattering, means we should try to go back to class
	if current_activity == "scattering_from_class":
		if has_meta("has_repathed_to_class"): # This meta should have been set before scattering
			remove_meta("has_repathed_to_class") # Allow a fresh repath attempt if needed now
		
		var classroom_id = original_class_target_data_copy.get("classroom_id")
		var course_name = original_class_target_data_copy.get("course_name", "Class")

		if not str(classroom_id).is_empty() and original_class_target_data_copy.has("offering_id"):
			set_activity("going_to_class", original_class_target_data_copy) # Restore original target data
			var classroom_location = academic_manager_ref.get_classroom_location(str(classroom_id))
			if classroom_location != Vector3.ZERO:
				print_debug_student("Scatter complete. Re-attempting navigation to class: %s" % course_name)
				navigate_to_target(classroom_location)
			else:
				print_debug_student("Scatter complete. Classroom %s still not locatable. Going idle." % str(classroom_id))
				set_activity("idle"); call_deferred("_decide_next_activity")
		else:
			print_debug_student("Scatter complete. Original class target data was invalid. Going idle.")
			set_activity("idle"); call_deferred("_decide_next_activity")
	elif DETAILED_LOGGING_ENABLED:
		print_debug_student("Scatter timer timeout, but current activity is '%s', not 'scattering_from_class'. No action to re-attempt class." % current_activity)


func set_activity(new_activity_name: String, target_info: Variant = null):
	var old_activity = current_activity
	var old_target_info = current_activity_target_data
	
	if old_activity == "going_to_class" and \
	  (new_activity_name != "going_to_class" or (target_info != old_target_info and target_info is Dictionary and old_target_info is Dictionary and target_info.get("offering_id") != old_target_info.get("offering_id"))):
		if has_meta("has_repathed_to_class"): 
			remove_meta("has_repathed_to_class")
			if DETAILED_LOGGING_ENABLED: print_debug_student("Cleared 'has_repathed_to_class' due to activity/target change from 'going_to_class'.")
	
	if new_activity_name != "scattering_from_class" and is_instance_valid(_scatter_timer):
		_scatter_timer.stop()
		_scatter_timer.queue_free()
		_scatter_timer = null
		if DETAILED_LOGGING_ENABLED: print_debug_student("Activity changed from/to non-scatter, scatter timer cleared.")

	current_activity = new_activity_name
	current_activity_target_data = target_info.duplicate(true) if target_info is Dictionary or target_info is Array else target_info # Deep copy target data if dict/array
	
	time_spent_in_current_activity_visual = 0.0 # For non-simulated activities
	time_stuck_trying_to_reach_target = 0.0 
	time_spent_near_door = 0.0 
	time_stuck_at_path_point = 0.0

	if DETAILED_LOGGING_ENABLED and (old_activity != current_activity or old_target_info != current_activity_target_data):
		print_debug_student("Activity changed from '%s' to '%s'. Target: %s" % [old_activity, current_activity, str(current_activity_target_data)])

	if is_instance_valid(animation_player):
		var anim_to_play = "Idle"
		if new_activity_name == "wandering_campus" or \
		   new_activity_name.begins_with("going_to_") or \
		   new_activity_name == "scattering_from_class" or \
		   new_activity_name == "wandering_tired" or \
		   new_activity_name == "wandering_anxious":
			anim_to_play = "Walk" # Ensure you have "Walk" and "Idle" animations
		
		if animation_player.has_animation(anim_to_play) and (not animation_player.is_playing() or animation_player.current_animation != anim_to_play):
			animation_player.play(anim_to_play)
		elif not animation_player.has_animation(anim_to_play) and DETAILED_LOGGING_ENABLED:
			print_debug_student("Animation '%s' not found for activity '%s'." % [anim_to_play, new_activity_name])

func _on_visual_hour_changed(_day_str: String, _time_slot_str: String): 
	if not is_instance_valid(time_manager_ref): return 
	if DETAILED_LOGGING_ENABLED: print_debug_student("Visual hour changed callback. Current activity: %s. Energy: %.1f" % [current_activity, needs.get("energy", MAX_NEED_VALUE)])

	# --- NEW LOGIC TO CLEAR STALE ATTENDANCE MEMORY ---
	var current_visual_slot_str = time_manager_ref.get_current_visual_time_slot_string()
	# If we have a memory of attending a class, and that class was in a *previous* hour, clear the memory.
	if not _last_attended_in_visual_slot.is_empty() and _last_attended_in_visual_slot != current_visual_slot_str:
		if DETAILED_LOGGING_ENABLED:
			print_debug_student("New hour. Clearing last attended memory (was for slot %s, now is %s)." % [_last_attended_in_visual_slot, current_visual_slot_str])
		_last_attended_offering_id = ""
		_last_attended_in_visual_slot = ""
		# If you implemented my previous (incorrect) fix, clear the day variable here too:
		# _last_attended_day = "" 
	# --- END OF NEW LOGIC ---

	_update_needs_based_on_activity(time_manager_ref.seconds_per_visual_hour_slot)
	
	var re_evaluation_activities = ["idle", "wandering_campus", "wandering_tired", "wandering_anxious", "scattering_from_class"]
	var low_energy_or_rest = needs.get("energy", MAX_NEED_VALUE) < MIN_NEED_VALUE + 20.0 or needs.get("rest", MAX_NEED_VALUE) < MIN_NEED_VALUE + 25.0
	
	if re_evaluation_activities.has(current_activity) or low_energy_or_rest:
		if DETAILED_LOGGING_ENABLED: print_debug_student("Re-evaluating activity due to hour change/low needs. Activity: %s, LowNeeds: %s" % [current_activity, str(low_energy_or_rest)])
		call_deferred("_decide_next_activity")

func _update_needs_based_on_activity(duration_seconds: float):
	var energy_change_rate = -0.05 
	var study_urge_increase_rate = 0.02 
	var current_energy = needs.get("energy", MAX_NEED_VALUE)
	var current_rest = needs.get("rest", MAX_NEED_VALUE)
	var current_study_urge = needs.get("study_urge", MIN_NEED_VALUE)

	match current_activity:
		"going_to_class": energy_change_rate = -0.06 
		"going_to_rest": energy_change_rate = -0.04 
		"going_to_study": energy_change_rate = -0.06
		"wandering_tired": energy_change_rate = -0.03
		"wandering_anxious": 
			energy_change_rate = -0.04
			current_study_urge = clampf(current_study_urge + study_urge_increase_rate * 0.5 * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
		"scattering_from_class": energy_change_rate = -0.05
	
	needs["energy"] = clampf(current_energy + energy_change_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	if not (current_activity in ["in_class", "studying", "going_to_class", "going_to_study"]): 
		needs["study_urge"] = clampf(current_study_urge + study_urge_increase_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	if needs.get("energy", MAX_NEED_VALUE) < 10.0 and not (current_activity in ["resting", "going_to_rest"]):
		needs["rest"] = clampf(current_rest - 0.05 * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)


func _find_and_go_to_functional_building(activity_name_for_state_when_going: String, building_type_target: String) -> bool:
	if not is_instance_valid(building_manager_ref) or not building_manager_ref.has_method("get_functional_buildings_data"): 
		printerr("[%s] No BuildingManager or missing method for finding '%s'." % [self.name, building_type_target])
		return false
	
	var functional_buildings: Dictionary = building_manager_ref.get_functional_buildings_data()
	var potential_target_nodes_positions: Array[Vector3] = []
	var potential_target_ids: Array[String] = []

	for cluster_id_key in functional_buildings:
		var building_data = functional_buildings[cluster_id_key]
		if building_data.get("building_type") == building_type_target:
			if building_data.get("current_users", 0) < building_data.get("total_capacity", 0):
				var rep_node = building_data.get("representative_block_node")
				if is_instance_valid(rep_node) and rep_node is Node3D:
					var building_pos = rep_node.global_position 
					# TODO: BuildingManager should ideally provide an actual ENTRY POINT on NavMesh
					# For now, using building_pos + small random offset as a heuristic
					var random_offset = Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
					potential_target_nodes_positions.append(Vector3(building_pos.x, EXPECTED_NAVMESH_Y, building_pos.z) + random_offset)
					potential_target_ids.append(str(cluster_id_key))
	
	if not potential_target_nodes_positions.is_empty():
		var random_index = randi() % potential_target_nodes_positions.size()
		var chosen_location_pos = potential_target_nodes_positions[random_index]
		var chosen_building_id = potential_target_ids[random_index]
		
		set_activity(activity_name_for_state_when_going, {"building_id": chosen_building_id, "destination_name": "%s %s" % [building_type_target.capitalize(), chosen_building_id.right(4)]})
		navigate_to_target(chosen_location_pos)
		return true
	
	if DETAILED_LOGGING_ENABLED: print_debug_student("No *available* location of type '%s' found for activity '%s'." % [building_type_target, activity_name_for_state_when_going])
	return false


func _on_time_manager_speed_changed(new_speed_multiplier: float):
	current_calculated_move_speed = base_move_speed * new_speed_multiplier
	if DETAILED_LOGGING_ENABLED: print_debug_student("Game speed changed to %.1fx. My move speed: %.2f" % [new_speed_multiplier, current_calculated_move_speed])
	if is_instance_valid(animation_player): 
		if animation_player.has_method("set_speed_scale"): animation_player.set_speed_scale(new_speed_multiplier) # Godot 3
		elif animation_player.has_meta("speed_scale"): animation_player.speed_scale = new_speed_multiplier # Godot 4 (usually)


func print_debug_student(message: String):
	if not DETAILED_LOGGING_ENABLED: return
	var id_str = student_id if not student_id.is_empty() else "NO_ID"
	var name_str = student_name if not student_name.is_empty() else self.name 
	print("[%s - %s]: %s" % [name_str.left(15), id_str.right(6), message]) 


func _find_class_for_time(day_to_check: String, slot_to_check: String) -> String:
	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_student("_find_class_for_time: Manager refs invalid.")
		return ""
		
	if day_to_check == "InvalidDay" or slot_to_check == "InvalidTime" or \
	   (is_instance_valid(time_manager_ref) and time_manager_ref.has_method("get_end_of_academic_day_slot") and slot_to_check == time_manager_ref.get_end_of_academic_day_slot()):
		# if DETAILED_LOGGING_ENABLED: print_debug_student("_find_class_for_time: Invalid day/slot or end of day. Day: %s, Slot: %s" % [day_to_check, slot_to_check])
		return ""

	for offering_id_key in current_course_enrollments:
		var enrollment_data = current_course_enrollments[offering_id_key]
		var fresh_offering_details: Dictionary = academic_manager_ref.get_offering_details(offering_id_key) if is_instance_valid(academic_manager_ref) else {}
		var current_offering_status = fresh_offering_details.get("status", "unknown") 

		if DETAILED_LOGGING_ENABLED and current_course_enrollments.size() < 5: 
			print_debug_student("  Checking offering %s (ID: %s). Fresh status: %s." % [enrollment_data.get("course_name", "N/A"), offering_id_key, current_offering_status])

		if current_offering_status != "scheduled": 
			if DETAILED_LOGGING_ENABLED and current_course_enrollments.size() < 5: print_debug_student("    Skipping: status is '%s'." % current_offering_status)
			continue
			
		var schedule_info = enrollment_data.get("schedule_info", {}) 
		var course_name_for_log = enrollment_data.get("course_name", "N/A_Course")
		if schedule_info.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_student("Warning (_find_class_for_time): schedule_info EMPTY for '%s'." % course_name_for_log)
			continue

		var class_pattern_str = schedule_info.get("pattern", "") 
		var class_start_slot_str = schedule_info.get("start_time_slot", "") 
		if class_pattern_str.is_empty() or class_start_slot_str.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_student("Warning (_find_class_for_time): pattern/start_slot EMPTY for '%s'." % course_name_for_log)
			continue
		
		var current_visual_slot_from_tm = time_manager_ref.get_current_visual_time_slot_string()
		if offering_id_key == _last_attended_offering_id and slot_to_check == _last_attended_in_visual_slot:
			if DETAILED_LOGGING_ENABLED: 
				print_debug_student("  Skipping recently attended offering '%s' for its original slot '%s'" % [course_name_for_log, slot_to_check])
			continue

		var days_class_occurs_on: Array[String] = academic_manager_ref.get_days_for_pattern(class_pattern_str)
		var formatted_slot_to_check = slot_to_check.replace(":", "")

		var is_day_match: bool = days_class_occurs_on.has(day_to_check)
		var is_slot_match: bool = (class_start_slot_str == formatted_slot_to_check)

		if DETAILED_LOGGING_ENABLED and (current_course_enrollments.size() < 3 or is_day_match and is_slot_match): 
			print_debug_student(
				"    For offering '%s' (ID: %s) Status: %s" % [course_name_for_log, offering_id_key, current_offering_status] +
				"\n      Student's Sched: Pattern='%s' (Days: %s), Start='%s'" % [class_pattern_str, str(days_class_occurs_on), class_start_slot_str] +
				"\n      Checking Against: Day='%s', Slot='%s'"% [day_to_check, slot_to_check] +
				" -> DayMatch=%s, SlotMatch=%s" % [str(is_day_match), str(is_slot_match)]
			)

		if is_day_match and is_slot_match: return offering_id_key
	return ""


func _get_current_visual_class_offering() -> String:
	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref): return ""
	var current_day = time_manager_ref.get_current_visual_day_string()
	var current_slot = time_manager_ref.get_current_visual_time_slot_string()
	# if DETAILED_LOGGING_ENABLED: print_debug_student("Decision Check: _get_current_visual_class_offering for SimTime: Day='%s', Slot='%s'" % [current_day, current_slot])
	return _find_class_for_time(current_day, current_slot)


func _get_next_class_to_prepare_for() -> Dictionary:
	if DETAILED_LOGGING_ENABLED: print_debug_student("Attempting _get_next_class_to_prepare_for...")
	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref): return {}
	
	var next_period_info: Variant = time_manager_ref.get_next_academic_slot_info() 
	if DETAILED_LOGGING_ENABLED: print_debug_student("  _get_next_class_to_prepare_for: next_period_info from TM: " + str(next_period_info))

	if not next_period_info is Dictionary or next_period_info.is_empty() or \
	   not next_period_info.has("day") or not next_period_info.has("slot") or \
	   next_period_info.get("day") == null or next_period_info.get("slot") == null or \
	   str(next_period_info.get("day")) == "InvalidDay" or str(next_period_info.get("slot")) == "InvalidTime":
		if DETAILED_LOGGING_ENABLED: print_debug_student("  PREP CHECK: Invalid/incomplete next_period_info: " + str(next_period_info))
		return {}

	var next_slot_day_str: String = str(next_period_info.day)
	var next_slot_time_str: String = str(next_period_info.slot)
		
	if DETAILED_LOGGING_ENABLED: print_debug_student("  PREP CHECK: Checking for class at Next Period: Day='%s', Slot='%s'" % [next_slot_day_str, next_slot_time_str])
	
	var found_upcoming_offering_id: String = _find_class_for_time(next_slot_day_str, next_slot_time_str) 
	
	if not found_upcoming_offering_id.is_empty():
		if current_course_enrollments.has(found_upcoming_offering_id):
			var class_details = current_course_enrollments[found_upcoming_offering_id] 
			if DETAILED_LOGGING_ENABLED: print_debug_student("    PREP CHECK: Found upcoming class: '%s' (ID: %s)" % [class_details.get("course_name","N/A"), found_upcoming_offering_id])
			return {"offering_id": found_upcoming_offering_id, "details": class_details.duplicate(true)} # Return a copy
		elif DETAILED_LOGGING_ENABLED: print_debug_student("    PREP CHECK ERROR: Found ID '%s' but no local enrollment data." % found_upcoming_offering_id)
	elif DETAILED_LOGGING_ENABLED:
		print_debug_student("  PREP CHECK: No class found for next period (%s %s)" % [next_slot_day_str, next_slot_time_str])
	return {}


func get_courses_for_current_term_from_progression() -> Array[String]:
	if is_instance_valid(degree_progression) and is_instance_valid(university_data_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_student("Calling degree_progression.get_next_courses_to_take.")
		var courses = degree_progression.get_next_courses_to_take(university_data_ref)
		if DETAILED_LOGGING_ENABLED: print_debug_student("DegreeProgression returned courses for current term: %s" % str(courses))
		return courses
	if DETAILED_LOGGING_ENABLED: 
		print_debug_student("Cannot get courses for current term: DegreeProgression (%s) or UniversityData (%s) invalid." % [str(is_instance_valid(degree_progression)), str(is_instance_valid(university_data_ref))])
	return []

# In Student.gd

func update_enrollment_details(offering_id: String, new_details: Dictionary):
	"""
	Called by a manager to update the details of a course the student is already
	enrolled in. This is crucial for when a course gets scheduled *after* the
	student has already enrolled.
	"""
	if current_course_enrollments.has(offering_id):
		if DETAILED_LOGGING_ENABLED:
			print_debug_student("Received schedule UPDATE for offering: %s" % offering_id)
		# confirm_course_enrollment already handles overwriting, so we can just reuse it.
		confirm_course_enrollment(offering_id, new_details)
		
func get_info_summary() -> Dictionary:
	var summary: Dictionary = {}
	summary["student_name"] = student_name
	summary["student_id"] = student_id
	summary["current_program_id"] = current_program_id
	summary["academic_start_year"] = academic_start_year
	summary["student_level"] = self.student_level

	var program_name_str = "N/A"
	if is_instance_valid(university_data_ref) and not current_program_id.is_empty():
		var prog_details = university_data_ref.get_program_details(current_program_id)
		program_name_str = prog_details.get("name", "Unknown Program")
	summary["program_name"] = program_name_str

	summary["current_course_enrollments"] = current_course_enrollments.duplicate(true)
	summary["needs"] = needs.duplicate(true)
	summary["_last_attended_offering_id"] = _last_attended_offering_id
	summary["_last_attended_in_visual_slot"] = _last_attended_in_visual_slot

	if is_instance_valid(degree_progression) and degree_progression.has_method("get_summary"):
		summary["degree_progression_summary"] = degree_progression.get_summary()
	else: 
		summary["degree_progression_summary"] = {}
		if DETAILED_LOGGING_ENABLED: 
			print_debug_student("WARNING: DegreeProgression node or get_summary method invalid when creating info summary.")

	# Convenience fields (can be derived from degree_progression_summary by consumer if preferred)
	var student_status = "Enrolled"
	if is_instance_valid(degree_progression) and degree_progression.is_graduated:
		student_status = "Graduated!"
	summary["status"] = student_status

	var credits_e = 0.0
	if is_instance_valid(degree_progression):
		credits_e = degree_progression.total_credits_earned
	summary["credits_earned"] = credits_e

	var credits_n = 0.0
	if is_instance_valid(university_data_ref) and not current_program_id.is_empty():
		var prog_details_for_credits = university_data_ref.get_program_details(current_program_id)
		credits_n = prog_details_for_credits.get("credits_to_graduate", 0.0)
	summary["credits_needed_for_program"] = credits_n

	# if DETAILED_LOGGING_ENABLED: # Kept this commented as your log was very long
	#     print_debug_student("get_info_summary() returning (keys: %s)" % str(summary.keys()))
	return summary
