# Student.gd
class_name Student
extends CharacterBody3D

# --- Debug Logging Control ---
const DETAILED_LOGGING_ENABLED: bool = false # Set to true for specific student logs

# --- Constants ---
const MAX_NEED_VALUE: float = 100.0
const MIN_NEED_VALUE: float = 0.0
const EXPECTED_NAVMESH_Y: float = 0.3
const MAX_TIME_STUCK_THRESHOLD: float = 15.0

# --- Core Student Information ---
var student_id: String = "default_id"
var student_name: String = "Default Student Name"
var current_program_id: String = ""
var academic_start_year: int = 0
var current_course_enrollments: Dictionary = {} # Stores details about courses student is enrolled in

# --- Degree Progression ---
var degree_progression: DegreeProgression

# --- State for Preventing Immediate Class Re-entry ---
var _last_attended_offering_id: String = ""
var _last_attended_in_visual_slot: String = ""

# --- Node References ---
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var label_3d: Label3D = $Label3D
@export var student_visuals: Node3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# --- Needs, Activity, Managers ---
var needs: Dictionary = { "energy": 100.0, "rest": 100.0, "study_urge": 0.0 }
var current_activity: String = "idle"
var current_activity_target_data: Variant = null
var time_spent_in_current_activity_visual: float = 0.0
var time_stuck_trying_to_reach_target: float = 0.0

var academic_manager_ref: AcademicManager
var university_data_ref: UniversityData
var time_manager_ref: TimeManager
var building_manager_ref: BuildingManager

# --- Movement ---
@export var base_move_speed: float = 3.0
var current_calculated_move_speed: float = 3.0
var current_target_position: Vector3

# --- Signals ---
signal student_despawn_data_for_manager(data: Dictionary)

# --- Functions (Your existing _ready, initialize_new_student, etc. up to _find_class_for_time) ---
# ... (Keep all your existing functions from _ready() down to just before _find_class_for_time)
func _ready():
	if not is_instance_valid(navigation_agent):
		printerr("[%s] CRITICAL: NavigationAgent3D node not found!" % self.name)
	else:
		navigation_agent.set_target_position(global_position)
		if not navigation_agent.is_connected("navigation_finished", Callable(self, "_on_navigation_agent_navigation_finished")):
			navigation_agent.navigation_finished.connect(Callable(self, "_on_navigation_agent_navigation_finished"))
			
	if is_instance_valid(label_3d):
		label_3d.text = student_name if not student_name.is_empty() else "Student"
	
	if not is_instance_valid(student_visuals):
		printerr("[%s] CRITICAL: Student visuals node not found!" % self.name)
	else:
		student_visuals.visible = true

	if not is_instance_valid(animation_player):
		print_debug_student("Warning: AnimationPlayer node not found.")

	current_calculated_move_speed = base_move_speed
	velocity = Vector3.ZERO

	if is_instance_valid(time_manager_ref):
		_connect_to_time_manager_speed_signal()

	if DETAILED_LOGGING_ENABLED: print_debug_student("Node _ready(). Initial global_position: " + str(global_position))
	call_deferred("check_spawn_position_on_navmesh")

func check_spawn_position_on_navmesh():
	await get_tree().physics_frame 
	if DETAILED_LOGGING_ENABLED: print_debug_student("check_spawn_position_on_navmesh (after 1 physics frame): global_position: " + str(global_position))
	if is_instance_valid(navigation_agent) and get_world_3d(): 
		var current_map = get_world_3d().navigation_map
		if current_map.is_valid():
			var closest_point_on_navmesh = NavigationServer3D.map_get_closest_point(current_map, global_position)
			var distance_to_navmesh = global_position.distance_to(closest_point_on_navmesh)
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Distance to NavMesh: " + str(distance_to_navmesh) + ". My Y: " + str(global_position.y) + ". Closest NavMesh Y: " + str(closest_point_on_navmesh.y))
			if distance_to_navmesh > 0.5 : 
				if DETAILED_LOGGING_ENABLED: print_debug_student("  WARNING: Student possibly spawned/settled too far from NavMesh!")
			if global_position.y < closest_point_on_navmesh.y - 0.1:
				if DETAILED_LOGGING_ENABLED: print_debug_student("  CRITICAL WARNING: Student is BELOW closest NavMesh point.")
		elif DETAILED_LOGGING_ENABLED: print_debug_student("  WARNING: Invalid navigation map RID in check_spawn_position_on_navmesh.")
	elif DETAILED_LOGGING_ENABLED: print_debug_student("  WARNING: NavigationAgent or World3D invalid in check_spawn_position_on_navmesh.")


func _connect_to_time_manager_speed_signal():
	if is_instance_valid(time_manager_ref):
		if time_manager_ref.has_signal("speed_changed"):
			if not time_manager_ref.is_connected("speed_changed", Callable(self, "_on_time_manager_speed_changed")):
				var err = time_manager_ref.speed_changed.connect(Callable(self, "_on_time_manager_speed_changed"))
				if err == OK and DETAILED_LOGGING_ENABLED:
					print_debug_student("Successfully connected to TimeManager.speed_changed.")
				elif err != OK:
					print_debug_student("ERROR connecting to TimeManager.speed_changed. Code: " + str(err))
		elif DETAILED_LOGGING_ENABLED:
			print_debug_student("WARNING: TimeManager is missing 'speed_changed' signal.")
		_on_time_manager_speed_changed(time_manager_ref.get_speed_multiplier())
	elif DETAILED_LOGGING_ENABLED:
		print_debug_student("WARNING: TimeManager reference not valid, cannot connect speed_changed or get initial speed.")

func initialize_new_student(s_id: String, s_name: String, prog_id: String, start_year_cal: int,
						 acad_man: AcademicManager, univ_data: UniversityData, time_man: TimeManager,
						 just_exited_offering_id: String = "", current_visual_slot_when_exited: String = "",
						 restored_degree_prog_summary: Dictionary = {}): 
	if DETAILED_LOGGING_ENABLED: print_debug_student("Initialize New Student START for: " + s_name + " ID: " + s_id)
	self.student_id = s_id
	self.student_name = s_name
	self.name = "Student_%s_%s" % [s_name.replace(" ", "_").to_lower(), s_id.right(4)]
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
				if err_code != OK:
					print_debug_student("ERROR connecting student_despawn_data_for_manager. Code: " + str(err_code))
	else:
		if DETAILED_LOGGING_ENABLED: print_debug_student("ERROR: academic_manager_ref is NOT a valid instance in initialize_new_student.")

	self._last_attended_offering_id = just_exited_offering_id
	self._last_attended_in_visual_slot = current_visual_slot_when_exited
	if DETAILED_LOGGING_ENABLED and not _last_attended_offering_id.is_empty():
		print_debug_student("Initialized after exiting offering " + _last_attended_offering_id + " during visual slot " + _last_attended_in_visual_slot)

	if not is_instance_valid(time_manager_ref):
		printerr("[%s] CRITICAL: TimeManager ref not passed or invalid in init!" % self.name)
	else:
		if not time_manager_ref.is_connected("speed_changed", Callable(self, "_on_time_manager_speed_changed")):
			_connect_to_time_manager_speed_signal()
		if time_manager_ref.has_signal("visual_hour_slot_changed"):
			if not time_manager_ref.is_connected("visual_hour_slot_changed", Callable(self, "_on_visual_hour_changed")):
				time_manager_ref.visual_hour_slot_changed.connect(Callable(self, "_on_visual_hour_changed"))

	if not is_instance_valid(building_manager_ref) and DETAILED_LOGGING_ENABLED:
		print_debug_student("Warning: BuildingManager ref not available after init.")

	if is_instance_valid(label_3d): label_3d.text = self.student_name
	
	needs["energy"] = MAX_NEED_VALUE
	needs["rest"] = MAX_NEED_VALUE
	needs["study_urge"] = randf_range(20.0, 50.0)
	
	if is_instance_valid(self.degree_progression): 
		if DETAILED_LOGGING_ENABLED: print_debug_student("DegreeProgression node already exists for " + s_name)
		if not restored_degree_prog_summary.is_empty():
			self.degree_progression.student_id = s_id 
			self.degree_progression.program_id = prog_id
			self.degree_progression.current_academic_year_in_program = restored_degree_prog_summary.get("current_academic_year", 1)
			self.degree_progression.current_semester_in_program = restored_degree_prog_summary.get("current_semester", 1)
			self.degree_progression.total_credits_earned = restored_degree_prog_summary.get("total_credits_earned", 0.0)
			self.degree_progression.is_graduated = restored_degree_prog_summary.get("is_graduated", false)
			self.degree_progression.course_records = restored_degree_prog_summary.get("course_records", {}).duplicate(true)
			if DETAILED_LOGGING_ENABLED: print_debug_student("Restored DegreeProgression for " + s_name + " from summary.")
	else: 
		var starting_academic_year_in_prog = 1
		var starting_semester_in_prog = 1
		if not restored_degree_prog_summary.is_empty():
			starting_academic_year_in_prog = restored_degree_prog_summary.get("current_academic_year", 1)
			starting_semester_in_prog = restored_degree_prog_summary.get("current_semester", 1)
			if DETAILED_LOGGING_ENABLED: print_debug_student("Using year/semester from restored summary for new DegreeProgression node for " + s_name)
		elif is_instance_valid(time_man): 
			var current_term_enum = time_man.get_current_academic_term_enum()
			if current_term_enum == TimeManager.AcademicTerm.SPRING:
				starting_semester_in_prog = 2
			elif current_term_enum == TimeManager.AcademicTerm.SUMMER:
				starting_semester_in_prog = 3
		
		self.degree_progression = DegreeProgression.new(s_id, prog_id, starting_academic_year_in_prog, starting_semester_in_prog)
		add_child(self.degree_progression)
		
		if not restored_degree_prog_summary.is_empty(): 
			self.degree_progression.total_credits_earned = restored_degree_prog_summary.get("total_credits_earned", 0.0)
			self.degree_progression.is_graduated = restored_degree_prog_summary.get("is_graduated", false)
			self.degree_progression.course_records = restored_degree_prog_summary.get("course_records", {}).duplicate(true)
			if DETAILED_LOGGING_ENABLED: print_debug_student("Populated new DegreeProgression for " + s_name + " with summary data.")
		elif DETAILED_LOGGING_ENABLED:
			print_debug_student("New DegreeProgression initialized for %s. Program Year: %d, Semester: %d" % [s_name, starting_academic_year_in_prog, starting_semester_in_prog])

	self.velocity = Vector3.ZERO
	if DETAILED_LOGGING_ENABLED: print_debug_student("Initialize New Student END for: " + s_name + ". TM valid: " + str(is_instance_valid(time_manager_ref)))

func on_fully_spawned_and_enrolled():
	if DETAILED_LOGGING_ENABLED: print_debug_student("Fully spawned and enrolled. Current activity: " + current_activity + ". Deferred decision pending.")
	if is_instance_valid(student_visuals) and not student_visuals.visible: 
		student_visuals.visible = true
	call_deferred("_decide_next_activity")

func confirm_course_enrollment(offering_id: String, course_offering_details: Dictionary):
	if DETAILED_LOGGING_ENABLED:
		print_debug_student("Confirming enrollment for offering: " + offering_id)
		print_debug_student("  Received course_offering_details for " + offering_id + " (Type: " + str(typeof(course_offering_details)) + "): " + str(course_offering_details))

	if current_course_enrollments.has(offering_id):
		var existing_schedule_info = current_course_enrollments[offering_id].get("schedule_info", {})
		if existing_schedule_info.get("pattern") != null and not str(existing_schedule_info.get("pattern")).is_empty():
			# Potentially update the status if it has changed
			var new_status = course_offering_details.get("status", "unknown")
			if current_course_enrollments[offering_id].get("status") != new_status:
				current_course_enrollments[offering_id]["status"] = new_status
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Updated status for already tracked enrollment %s to %s" % [offering_id, new_status])
			elif DETAILED_LOGGING_ENABLED: print_debug_student("  Already fully tracking enrollment with schedule for: %s. Pattern: %s. Status: %s" % [offering_id, str(existing_schedule_info.get("pattern")), current_course_enrollments[offering_id].get("status")])
			return # Already confirmed with schedule details

	var base_course_data = {} 
	var course_id_to_use = course_offering_details.get("course_id", "N/A")
	var course_name_to_use = course_offering_details.get("course_name", "N/A Course Name")
	var offering_current_status = course_offering_details.get("status", "unknown") # Get status from AM

	if is_instance_valid(university_data_ref) and not course_id_to_use.is_empty() and course_id_to_use != "N/A":
		base_course_data = university_data_ref.get_course_details(course_id_to_use)
		if course_name_to_use == "N/A Course Name" and base_course_data.has("name"):
				course_name_to_use = base_course_data.get("name")

	var final_classroom_id = null
	var final_pattern = null
	var final_start_time_slot = null
	var final_duration_slots = course_offering_details.get("duration_slots", 1) 

	var schedule_details_source = course_offering_details 
	if course_offering_details.has("schedule_info") and course_offering_details.schedule_info is Dictionary:
		schedule_details_source = course_offering_details.schedule_info
		if DETAILED_LOGGING_ENABLED: print_debug_student("  Using NESTED 'schedule_info' from received details as schedule source: " + str(schedule_details_source))
	elif DETAILED_LOGGING_ENABLED:
		print_debug_student("  Using TOP-LEVEL keys from received details as schedule source.")
	
	final_classroom_id = schedule_details_source.get("classroom_id")
	final_pattern = schedule_details_source.get("pattern")
	final_start_time_slot = schedule_details_source.get("start_time_slot")
	if schedule_details_source.has("duration_slots") and schedule_details_source.duration_slots > 0:
		final_duration_slots = schedule_details_source.duration_slots
	elif course_offering_details.has("duration_slots") and course_offering_details.duration_slots > 0:
		final_duration_slots = course_offering_details.duration_slots


	if DETAILED_LOGGING_ENABLED:
		print_debug_student("  Resolved schedule parts for " + offering_id + ": Pattern=" + str(final_pattern) + ", Classroom=" + str(final_classroom_id) + ", StartSlot=" + str(final_start_time_slot) + ", Duration=" + str(final_duration_slots))
		if final_pattern == null: print_debug_student("    WARNING (confirm_enrollment): 'final_pattern' is null for " + offering_id)

	current_course_enrollments[offering_id] = {
		"course_id": course_id_to_use,
		"course_name": course_name_to_use,
		"status": offering_current_status, 
		"progress": course_offering_details.get("progress", 0.0), 
		"credits": base_course_data.get("credits", course_offering_details.get("credits",0)),
		"progress_needed_for_completion": base_course_data.get("progress_needed", course_offering_details.get("progress_needed_for_completion",100)),
		"schedule_info": { 
			"classroom_id": final_classroom_id,
			"pattern": final_pattern,
			"start_time_slot": final_start_time_slot,
			"duration_slots": final_duration_slots
		}
	}
	if DETAILED_LOGGING_ENABLED: print_debug_student("Enrollment confirmed/updated for: %s (%s). Stored Status: %s, Schedule_info.pattern: %s" % [offering_id, course_name_to_use, offering_current_status, str(current_course_enrollments[offering_id].schedule_info.get("pattern"))])

func _physics_process(delta: float):
	if not is_instance_valid(navigation_agent):
		return

	if navigation_agent.is_navigation_finished():
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO 
		time_stuck_trying_to_reach_target = 0.0 
		return

	if is_instance_valid(student_visuals) and not student_visuals.visible: 
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		return

	var target_nav_pos = navigation_agent.get_target_position()
	if target_nav_pos == global_position and not navigation_agent.is_target_reachable(): 
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		return

	if navigation_agent.is_target_reachable():
		var next_path_pos = navigation_agent.get_next_path_position()
		var direction = (next_path_pos - global_position)
		if direction.length_squared() > 0.01: 
			velocity = direction.normalized() * current_calculated_move_speed
		else:
			velocity = Vector3.ZERO 
		
		if velocity.length() > 0.1:
			look_at(global_position + velocity.normalized() * Vector3(1,0,1), Vector3.UP) 

		time_stuck_trying_to_reach_target = 0.0
	else: 
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO 
		
		var activity_can_get_stuck = current_activity in ["going_to_class", "going_to_rest", "going_to_study", "wandering_campus"]
		if activity_can_get_stuck and target_nav_pos != global_position:
			time_stuck_trying_to_reach_target += delta
			if DETAILED_LOGGING_ENABLED and int(time_stuck_trying_to_reach_target) % 3 == 0 : 
				print_debug_student("Physics: TARGET NOT REACHABLE for '%s' (%.1fs stuck). NavT: %s. MyPos: %s." % [current_activity, time_stuck_trying_to_reach_target, str(target_nav_pos.round()), str(global_position.round())])

			if time_stuck_trying_to_reach_target > MAX_TIME_STUCK_THRESHOLD:
				if DETAILED_LOGGING_ENABLED: print_debug_student("GIVING UP on current target for '%s' after %.1fs. Setting to idle." % [current_activity, time_stuck_trying_to_reach_target])
				set_activity("idle") 
				call_deferred("_decide_next_activity") 
				return 
		elif activity_can_get_stuck and DETAILED_LOGGING_ENABLED and int(time_stuck_trying_to_reach_target) % 5 == 0 : 
			print_debug_student("Physics: Target not reachable for '%s', but no distinct target or at target. Vel ZERO." % current_activity)

	move_and_slide()

func _on_visual_hour_changed(_day_str: String, _time_slot_str: String): 
	if not is_instance_valid(time_manager_ref): return 
	
	if DETAILED_LOGGING_ENABLED: print_debug_student("Visual hour changed callback. Current activity: " + current_activity)

	_update_needs_based_on_activity(time_manager_ref.seconds_per_visual_hour_slot)
	
	var re_evaluation_states = ["idle", "wandering_campus", "wandering_tired", "wandering_anxious"]
	if re_evaluation_states.has(current_activity) or \
	   needs.energy < MIN_NEED_VALUE + 10 or needs.rest < MIN_NEED_VALUE + 10: 
		call_deferred("_decide_next_activity")


func _update_needs_based_on_activity(duration_seconds: float):
	var energy_change_rate = -0.05 
	var rest_increase_rate = 0.5 
	var study_urge_increase_rate = 0.02 
	var study_urge_decrease_rate = 0.2 

	match current_activity:
		"going_to_class": energy_change_rate = -0.06 
		"going_to_rest": energy_change_rate = -0.04 
		"going_to_study": energy_change_rate = -0.06
		"wandering_tired": energy_change_rate = -0.03
		"wandering_anxious": energy_change_rate = -0.04; needs["study_urge"] = clampf(needs.study_urge + study_urge_increase_rate * 0.5 * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE) 

	needs.energy = clampf(needs.energy + energy_change_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	
	if not ["in_class", "studying", "going_to_class", "going_to_study"].has(current_activity): 
		needs.study_urge = clampf(needs.study_urge + study_urge_increase_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	
	if needs.energy < 10.0 and not ["resting", "going_to_rest"].has(current_activity):
		needs.rest = clampf(needs.rest - 0.05 * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)


func navigate_to_target(target_pos_from_ai: Vector3):
	if not is_instance_valid(navigation_agent): 
		printerr("[%s] No NavAgent! Cannot navigate." % self.name)
		return
	
	var projected_target_pos = Vector3(target_pos_from_ai.x, EXPECTED_NAVMESH_Y, target_pos_from_ai.z)
	if abs(target_pos_from_ai.y - EXPECTED_NAVMESH_Y) > 0.05 and DETAILED_LOGGING_ENABLED:
		print_debug_student("Nav target Y %.2f from AI projected to EXPECTED_NAVMESH_Y %.2f. Original: %s" % [target_pos_from_ai.y, EXPECTED_NAVMESH_Y, str(target_pos_from_ai.round())])
	
	var final_nav_target = projected_target_pos
	if get_world_3d(): 
		var nav_map_rid = get_world_3d().navigation_map
		if nav_map_rid.is_valid():
			var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map_rid, projected_target_pos)
			if abs(snapped_pos.y - EXPECTED_NAVMESH_Y) > 0.1 and DETAILED_LOGGING_ENABLED: 
				print_debug_student("WARNING: NavMesh snap for target XZ(%.1f, %.1f) resulted in Y=%.2f, expected plane Y=%.2f. NavMesh might not be flat." % [projected_target_pos.x, projected_target_pos.z, snapped_pos.y, EXPECTED_NAVMESH_Y])
			
			var snap_distance_overall = snapped_pos.distance_to(projected_target_pos)
			if snap_distance_overall > 1.0 and DETAILED_LOGGING_ENABLED: 
				print_debug_student("Nav target %s (proj. Y=%.2f) snapped to %s (dist: %.2f)." % [str(projected_target_pos.round()), EXPECTED_NAVMESH_Y, str(snapped_pos.round()), snap_distance_overall])
			final_nav_target = snapped_pos
		elif DETAILED_LOGGING_ENABLED: 
			print_debug_student("Warning: No valid nav map RID. Using projected target: %s" % str(projected_target_pos.round()))
	else:
		if DETAILED_LOGGING_ENABLED: print_debug_student("Warning: No World3D for navigation. Using projected target.")
		
	if final_nav_target.distance_squared_to(navigation_agent.get_target_position()) < 0.01 and not navigation_agent.is_navigation_finished():
		return 
		
	current_target_position = final_nav_target 
	navigation_agent.set_target_position(current_target_position)
	time_stuck_trying_to_reach_target = 0.0 
	
	if DETAILED_LOGGING_ENABLED: print_debug_student("Navigation target set to: " + str(current_target_position.round()))

	if abs(global_position.y - EXPECTED_NAVMESH_Y) > 0.25 and DETAILED_LOGGING_ENABLED : 
		print_debug_student("Warning: Student Y %.2f far from EXPECTED_NAVMESH_Y %.2f when pathing to %s." % [global_position.y, EXPECTED_NAVMESH_Y, str(current_target_position.round())])

func _on_navigation_agent_navigation_finished():
	if DETAILED_LOGGING_ENABLED: print_debug_student("Navigation FINISHED. Reached target for activity: '%s'." % current_activity)
	velocity = Vector3.ZERO

	var previous_activity_on_arrival = current_activity
	var target_data_on_arrival = current_activity_target_data
	
	var despawn_activity_type = ""
	var building_id_for_despawn = "" 
	var can_enter_and_despawn = true 

	match previous_activity_on_arrival:
		"going_to_class":
			despawn_activity_type = "in_class"
			if target_data_on_arrival is Dictionary:
				building_id_for_despawn = target_data_on_arrival.get("classroom_id", "UNKNOWN_CLASS_ID")
			
			if is_instance_valid(building_manager_ref) and not building_id_for_despawn.begins_with("UNKNOWN"):
				if not building_manager_ref.student_entered_functional_building(building_id_for_despawn):
					can_enter_and_despawn = false
					if DETAILED_LOGGING_ENABLED: print_debug_student("Classroom " + building_id_for_despawn + " full. Cannot enter. Will idle.")
			elif not is_instance_valid(building_manager_ref) and DETAILED_LOGGING_ENABLED:
				print_debug_student("BM invalid while going to class, assuming entry for " + building_id_for_despawn)


		"going_to_rest":
			despawn_activity_type = "resting"
			if target_data_on_arrival is Dictionary:
				building_id_for_despawn = target_data_on_arrival.get("building_id", "UNKNOWN_DORM_ID")

			if is_instance_valid(building_manager_ref) and not building_id_for_despawn.begins_with("UNKNOWN"):
				if not building_manager_ref.student_entered_functional_building(building_id_for_despawn):
					can_enter_and_despawn = false
					if DETAILED_LOGGING_ENABLED: print_debug_student("Dorm " + building_id_for_despawn + " full. Cannot enter. Will idle.")
			elif not is_instance_valid(building_manager_ref) and DETAILED_LOGGING_ENABLED:
				print_debug_student("BM invalid while going to rest, assuming entry for " + building_id_for_despawn)


		"going_to_study":
			despawn_activity_type = "studying"
			if target_data_on_arrival is Dictionary:
				building_id_for_despawn = target_data_on_arrival.get("building_id", "UNKNOWN_STUDY_ID")

			if is_instance_valid(building_manager_ref) and not building_id_for_despawn.begins_with("UNKNOWN"):
				if not building_manager_ref.student_entered_functional_building(building_id_for_despawn):
					can_enter_and_despawn = false
					if DETAILED_LOGGING_ENABLED: print_debug_student("Study location " + building_id_for_despawn + " full. Cannot enter. Will idle.")
			elif not is_instance_valid(building_manager_ref) and DETAILED_LOGGING_ENABLED:
				print_debug_student("BM invalid while going to study, assuming entry for " + building_id_for_despawn)
		_:
			if DETAILED_LOGGING_ENABLED and not (previous_activity_on_arrival in ["idle", "wandering_campus", "wandering_tired", "wandering_anxious"]):
				print_debug_student("Reached target for non-despawn activity '" + previous_activity_on_arrival + "'. Setting to idle and re-deciding.")
			set_activity("idle")
			call_deferred("_decide_next_activity")
			return 

	if not despawn_activity_type.is_empty() and can_enter_and_despawn:
		if DETAILED_LOGGING_ENABLED: print_debug_student("Preparing to emit despawn data for " + student_name + " (" + previous_activity_on_arrival + "). Building: " + building_id_for_despawn)
		
		var full_despawn_data: Dictionary = {}
		if self.has_method("get_info_summary"):
			full_despawn_data = get_info_summary()
		else: 
			full_despawn_data = {
				"name": student_name, "student_name": student_name, "student_id": student_id,
				"program_id": current_program_id, "program_name": "N/A",
				"current_courses_list": [], "status": "Enrolled",
				"credits_earned": 0.0, "credits_needed_for_program": 0.0
			}

		full_despawn_data["student_id"] = student_id 
		full_despawn_data["current_program_id"] = current_program_id
		full_despawn_data["academic_start_year"] = academic_start_year
		full_despawn_data["current_course_enrollments"] = current_course_enrollments.duplicate(true)
		full_despawn_data["needs"] = needs.duplicate(true)
		full_despawn_data["activity_after_despawn"] = despawn_activity_type
		full_despawn_data["activity_target_data"] = target_data_on_arrival.duplicate(true) if target_data_on_arrival is Dictionary else target_data_on_arrival
		full_despawn_data["building_id"] = building_id_for_despawn 
		
		if is_instance_valid(degree_progression) and degree_progression.has_method("get_summary"):
			full_despawn_data["degree_progression_summary"] = degree_progression.get_summary()
		else:
			full_despawn_data["degree_progression_summary"] = {} 
			if DETAILED_LOGGING_ENABLED: print_debug_student("WARNING: DegreeProgression node or get_summary method invalid for student " + student_id + " during despawn prep.")
			
		if DETAILED_LOGGING_ENABLED: print_debug_student("PRE-EMIT student_despawn_data_for_manager. Data Keys: " + str(full_despawn_data.keys()))
		emit_signal("student_despawn_data_for_manager", full_despawn_data)
		
		if is_instance_valid(student_visuals):
			student_visuals.visible = false
		self.process_mode = Node.PROCESS_MODE_DISABLED 
		navigation_agent.set_target_position(global_position) 
		velocity = Vector3.ZERO
		
		if DETAILED_LOGGING_ENABLED: print_debug_student("Node hidden/disabled. Awaiting queue_free() from AcademicManager after data processing.")
		return 
		
	elif not despawn_activity_type.is_empty() and not can_enter_and_despawn:
		if DETAILED_LOGGING_ENABLED: print_debug_student("Entry to " + despawn_activity_type + " at " + building_id_for_despawn + " denied. Setting to idle.")
		set_activity("idle") 
		call_deferred("_decide_next_activity")
		return

	if DETAILED_LOGGING_ENABLED: print_debug_student("Navigation finished for activity '" + previous_activity_on_arrival + "', not a despawn type or entry denied. Setting to idle.")
	set_activity("idle")
	call_deferred("_decide_next_activity")


func set_activity(new_activity_name: String, target_info: Variant = null):
	var old_activity = current_activity
	var visuals_state_before = "N/A"
	if is_instance_valid(student_visuals):
		visuals_state_before = "Visible" if student_visuals.visible else "Hidden"
	
	if DETAILED_LOGGING_ENABLED:
		print_debug_student("set_activity: old='%s', new='%s'. Visuals valid: %s, currently: %s. Target: %s" % [old_activity, new_activity_name, str(is_instance_valid(student_visuals)), visuals_state_before, str(target_info)])

	if current_activity == new_activity_name and current_activity_target_data == target_info:
		if is_instance_valid(student_visuals):
			var should_be_visible_now = not (new_activity_name in ["in_class", "resting", "studying"]) 
			if student_visuals.visible != should_be_visible_now and not (new_activity_name in ["going_to_class", "going_to_rest", "going_to_study"]): 
				student_visuals.visible = should_be_visible_now
				if DETAILED_LOGGING_ENABLED: print_debug_student("Visibility corrected for ongoing activity '%s' to: %s" % [new_activity_name, "SHOWN" if should_be_visible_now else "HIDDEN"])
	
	current_activity = new_activity_name
	current_activity_target_data = target_info
	
	time_spent_in_current_activity_visual = 0.0 

	if old_activity != new_activity_name or \
	   (new_activity_name in ["going_to_class", "going_to_rest", "going_to_study", "wandering_campus"]):
		time_stuck_trying_to_reach_target = 0.0
		if DETAILED_LOGGING_ENABLED and old_activity != new_activity_name: print_debug_student("Resetting time_stuck_trying_to_reach_target due to new activity.")

	var visibility_changed_msg = ""
	if is_instance_valid(student_visuals):
		var should_be_visible_now = true 
		if student_visuals.visible != should_be_visible_now:
			student_visuals.visible = should_be_visible_now
			visibility_changed_msg = " Visuals %s." % ("SHOWN" if should_be_visible_now else "HIDDEN")
	
	if DETAILED_LOGGING_ENABLED:
		if old_activity != new_activity_name or current_activity_target_data != target_info or visibility_changed_msg != "": 
			print_debug_student("Activity changed from '%s' to '%s'. Target Data: %s.%s" % [old_activity, current_activity, str(target_info), visibility_changed_msg])


func _find_and_go_to_functional_building(activity_name_for_state_when_going: String, building_type_target: String) -> bool:
	if not is_instance_valid(building_manager_ref): 
		printerr("[%s] No BuildingManager for finding '%s'." % [self.name, building_type_target])
		return false
	if not building_manager_ref.has_method("get_functional_buildings_data"): 
		printerr("[%s] BuildingManager missing 'get_functional_buildings_data'." % [self.name])
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
					potential_target_nodes_positions.append(Vector3(building_pos.x, EXPECTED_NAVMESH_Y, building_pos.z))
					potential_target_ids.append(str(cluster_id_key))
			elif DETAILED_LOGGING_ENABLED:
				print_debug_student("Building type '%s', ID '%s' is full. current: %s, capacity: %s" % [building_type_target, cluster_id_key, building_data.get("current_users",0), building_data.get("total_capacity",0)])

	if not potential_target_nodes_positions.is_empty():
		var random_index = randi() % potential_target_nodes_positions.size()
		var chosen_location_pos = potential_target_nodes_positions[random_index]
		var chosen_building_id = potential_target_ids[random_index]
		
		set_activity(activity_name_for_state_when_going, {"building_id": chosen_building_id, "destination_name": "%s %s" % [building_type_target.capitalize(), chosen_building_id]})
		navigate_to_target(chosen_location_pos)
		if DETAILED_LOGGING_ENABLED: print_debug_student("Found available '%s' at '%s'. Navigating to %s." % [building_type_target, chosen_building_id, str(chosen_location_pos.round())])
		return true
	
	if DETAILED_LOGGING_ENABLED: print_debug_student("No *available* location of type '%s' found for activity '%s'." % [building_type_target, activity_name_for_state_when_going])
	return false


func _on_time_manager_speed_changed(new_speed_multiplier: float):
	current_calculated_move_speed = base_move_speed * new_speed_multiplier
	if DETAILED_LOGGING_ENABLED:
		print_debug_student("Game speed changed to " + str(new_speed_multiplier) + "x. My calculated move speed is now: " + str(current_calculated_move_speed))
	
	if is_instance_valid(animation_player) and animation_player.has_method("set_speed_scale"): 
		animation_player.set_speed_scale(new_speed_multiplier)
	elif is_instance_valid(animation_player) and animation_player.has_meta("speed_scale"): 
		animation_player.speed_scale = new_speed_multiplier


func print_debug_student(message: String):
	var id_str = student_id if not student_id.is_empty() else "NO_ID"
	var name_str = student_name if not student_name.is_empty() else self.name 
	print("[%s - %s]: %s" % [name_str, id_str.right(6), message]) 


# --- MODIFIED CLASS FINDING LOGIC ---
func _find_class_for_time(day_to_check: String, slot_to_check: String) -> String:
	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_student("_find_class_for_time: Manager refs invalid.")
		return ""
		
	if day_to_check == "InvalidDay" or slot_to_check == "InvalidTime" or \
	   (is_instance_valid(time_manager_ref) and time_manager_ref.has_method("get_end_of_academic_day_slot") and slot_to_check == time_manager_ref.get_end_of_academic_day_slot()):
		if DETAILED_LOGGING_ENABLED: print_debug_student("_find_class_for_time: Invalid day/slot or end of day. Day: %s, Slot: %s" % [day_to_check, slot_to_check])
		return ""

	for offering_id_key in current_course_enrollments:
		var enrollment_data = current_course_enrollments[offering_id_key]
		
		# --- MODIFIED PART: Fetch fresh status from AcademicManager ---
		var fresh_offering_details: Dictionary = {}
		if is_instance_valid(academic_manager_ref) and academic_manager_ref.has_method("get_offering_details"):
			fresh_offering_details = academic_manager_ref.get_offering_details(offering_id_key)
		
		var current_offering_status = fresh_offering_details.get("status", "unknown") # Use fresh status
		# --- END MODIFIED PART ---

		if current_offering_status != "scheduled": # Check against the fresh status
			if DETAILED_LOGGING_ENABLED:
				print_debug_student("  Skipping offering '%s' (ID: %s) in _find_class_for_time because its status is '%s' (freshly checked), not 'scheduled'." % [enrollment_data.get("course_name", "N/A"), offering_id_key, current_offering_status])
			continue
			
		var schedule_info = enrollment_data.get("schedule_info", {}) # Still use local schedule_info for time/pattern matching
		var course_name_for_log = enrollment_data.get("course_name", "N/A_Course")

		if schedule_info.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_student("Warning (_find_class_for_time): schedule_info IS EMPTY for VALIDLY SCHEDULED offering: '" + course_name_for_log + "' (ID: " + offering_id_key + "). Skipping for time match.")
			continue

		var class_pattern_str = schedule_info.get("pattern")
		var class_start_slot_str = schedule_info.get("start_time_slot")

		if class_pattern_str == null or class_pattern_str.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_student("Warning (_find_class_for_time): class_pattern_str is NULL or EMPTY for VALIDLY SCHEDULED offering: '" + course_name_for_log + "' (ID: " + offering_id_key + "). Pattern: '" + str(class_pattern_str) + "'. Skipping for time match.")
			continue
		
		if class_start_slot_str == null or class_start_slot_str.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_student("Warning (_find_class_for_time): class_start_slot_str is NULL or EMPTY for VALIDLY SCHEDULED offering: '" + course_name_for_log + "' (ID: " + offering_id_key + "). StartSlot: '" + str(class_start_slot_str) + "'. Skipping for time match.")
			continue
		
		# Re-entry prevention for the current visual slot
		var current_visual_slot_from_tm = time_manager_ref.get_current_visual_time_slot_string()
		if offering_id_key == _last_attended_offering_id and \
		   slot_to_check == _last_attended_in_visual_slot and \
		   current_visual_slot_from_tm == _last_attended_in_visual_slot:
			if DETAILED_LOGGING_ENABLED:
				print_debug_student("  Skipping re-check of recently exited offering '" + course_name_for_log + "' (ID: " + offering_id_key + ") in current actual slot " + slot_to_check)
			continue

		var days_class_occurs_on: Array[String] = []
		if academic_manager_ref.has_method("get_days_for_pattern"): # Guarding the call
			days_class_occurs_on = academic_manager_ref.get_days_for_pattern(class_pattern_str)
		else:
			if DETAILED_LOGGING_ENABLED: print_debug_student("ERROR: academic_manager_ref missing get_days_for_pattern method!")
			continue # Cannot determine if it's the right day

		var is_day_match: bool = days_class_occurs_on.has(day_to_check)
		var is_slot_match: bool = (class_start_slot_str == slot_to_check)

		if DETAILED_LOGGING_ENABLED:
			print_debug_student("  Checking offering %s (ID: %s). Fresh status: %s. Stored local status: %s" % [
			enrollment_data.get("course_name", "N/A"),
			offering_id_key,
			current_offering_status, # This is from fresh_offering_details
			enrollment_data.get("status", "N/A_local") # This is from student's current_course_enrollments
	])

		if is_day_match and is_slot_match: # And status is already confirmed "scheduled" from above
			return offering_id_key
			
	return ""

func _get_current_visual_class_offering() -> String:
	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref): return ""
	
	var current_day = time_manager_ref.get_current_visual_day_string()
	var current_slot = time_manager_ref.get_current_visual_time_slot_string()
	
	if DETAILED_LOGGING_ENABLED:
		print_debug_student("Decision Check: _get_current_visual_class_offering for SimTime: Day='" + current_day + "', Slot='" + current_slot + "'")
	
	return _find_class_for_time(current_day, current_slot)

func _get_next_class_to_prepare_for() -> Dictionary:
	if DETAILED_LOGGING_ENABLED: print_debug_student("Attempting _get_next_class_to_prepare_for...")

	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_student("  _get_next_class_to_prepare_for: Manager refs invalid. TM: " + str(time_manager_ref) + " AM: " + str(academic_manager_ref))
		return {}

	var next_period_info: Variant = time_manager_ref.get_next_academic_slot_info() 
	if DETAILED_LOGGING_ENABLED: print_debug_student("  _get_next_class_to_prepare_for: next_period_info from TimeManager: " + str(next_period_info))

	if not next_period_info is Dictionary or next_period_info.is_empty() or \
	   not next_period_info.has("day") or not next_period_info.has("slot") or \
	   next_period_info.get("day") == null or next_period_info.get("slot") == null or \
	   next_period_info.get("day") == "InvalidDay" or next_period_info.get("slot") == "InvalidTime":
		if DETAILED_LOGGING_ENABLED: print_debug_student("  PREP CHECK: Invalid or incomplete next_period_info from TimeManager. Data: " + str(next_period_info))
		return {}

	var next_slot_day_str: String = next_period_info.day
	var next_slot_time_str: String = next_period_info.slot
		
	if DETAILED_LOGGING_ENABLED: print_debug_student("  PREP CHECK: Min >= 50. Checking for class at Next Period: Day='" + next_slot_day_str + "', Slot='" + next_slot_time_str + "'")
	
	var found_upcoming_offering_id: String = _find_class_for_time(next_slot_day_str, next_slot_time_str) 
	
	if not found_upcoming_offering_id.is_empty():
		# We need the locally stored enrollment_data for course_name, etc. even if status is fresh
		if current_course_enrollments.has(found_upcoming_offering_id):
			var class_details = current_course_enrollments[found_upcoming_offering_id] 
			# We've already confirmed it's "scheduled" by _find_class_for_time fetching fresh status.
			if DETAILED_LOGGING_ENABLED: print_debug_student("    PREP CHECK: Found upcoming class offering: '" + class_details.get("course_name","N/A") + "' (ID: " + found_upcoming_offering_id + ")")
			return {"offering_id": found_upcoming_offering_id, "details": class_details} 
		else:
			if DETAILED_LOGGING_ENABLED: print_debug_student("    PREP CHECK ERROR: Found upcoming offering ID '" + found_upcoming_offering_id + "' but no enrollment data exists for it locally.")
			return {} 
	elif DETAILED_LOGGING_ENABLED:
		print_debug_student("  PREP CHECK: No class found for next period (" + next_slot_day_str + " " + next_slot_time_str + ")")
		
	return {}

func _decide_next_activity():
	if not is_instance_valid(self):
		print("STUDENT ERROR: _decide_next_activity called on an invalid student instance: " + self.name if self else "Unnamed/Freed Student")
		return

	if not is_instance_valid(time_manager_ref):
		print_debug_student("CRITICAL ERROR in _decide_next_activity: time_manager_ref is NULL or invalid. Cannot proceed.")
		return 
	if not is_instance_valid(academic_manager_ref):
		print_debug_student("CRITICAL ERROR in _decide_next_activity: academic_manager_ref is NULL or invalid. Cannot proceed.")
		return
	if not is_instance_valid(navigation_agent):
		print_debug_student("CRITICAL ERROR in _decide_next_activity: navigation_agent is NULL or invalid. Cannot navigate.")
		return

	var action_taken: bool = false

	if DETAILED_LOGGING_ENABLED:
		print_debug_student("--- FULL _decide_next_activity START --- Current Activity: " + current_activity +
							", Pos: " + str(global_position.round()) +
							", Energy:%.1f, Rest:%.1f, StudyUrge:%.1f" % [needs.energy, needs.rest, needs.study_urge])

	var current_class_id = _get_current_visual_class_offering()
	if not current_class_id.is_empty():
		var class_details = current_course_enrollments.get(current_class_id, {})
		var schedule_info = class_details.get("schedule_info", {})
		var classroom_id = schedule_info.get("classroom_id")
		var course_name = class_details.get("course_name", "N/A Course")

		if classroom_id == null or str(classroom_id).is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Action: Found CURRENT class '" + course_name + "' but classroom_id is missing/invalid. Will not attend.")
		else:
			var classroom_location: Vector3 = academic_manager_ref.get_classroom_location(str(classroom_id))
			if classroom_location != Vector3.ZERO:
				set_activity("going_to_class", {"offering_id": current_class_id, "classroom_id": str(classroom_id), "destination_name": "Class: " + course_name})
				navigate_to_target(classroom_location)
				if DETAILED_LOGGING_ENABLED: print_debug_student("  ACTION TAKEN: Going to CURRENT CLASS - " + course_name + " in " + str(classroom_id))
				action_taken = true 
			else:
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Action: Found CURRENT class '" + course_name + "' but classroom location (ID: " + str(classroom_id) + ") unknown or full. Will not attend.")
		if action_taken: return 

	if not action_taken and is_instance_valid(time_manager_ref) and time_manager_ref.get_current_simulation_minute() >= 50 :
		if DETAILED_LOGGING_ENABLED: print_debug_student("  No current class. Checking for UPCOMING class (minute >= 50)...")
		var upcoming_data: Dictionary = _get_next_class_to_prepare_for()

		if not upcoming_data.is_empty():
			var upcoming_offering_id = upcoming_data.get("offering_id")
			var upcoming_details = upcoming_data.get("details", {})
			var schedule_info_upcoming = upcoming_details.get("schedule_info", {})
			var classroom_id_up = schedule_info_upcoming.get("classroom_id")
			var course_name_up = upcoming_details.get("course_name", "N/A Upcoming")

			if classroom_id_up == null or str(classroom_id_up).is_empty():
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Action: Found UPCOMING class '" + course_name_up + "' but classroom_id is missing/invalid. Cannot prepare.")
			else:
				var classroom_loc_up: Vector3 = academic_manager_ref.get_classroom_location(str(classroom_id_up))
				if classroom_loc_up != Vector3.ZERO:
					set_activity("going_to_class", {"offering_id": upcoming_offering_id, "classroom_id": str(classroom_id_up), "destination_name": "Next Class: " + course_name_up})
					navigate_to_target(classroom_loc_up)
					if DETAILED_LOGGING_ENABLED: print_debug_student("  ACTION TAKEN: Going to UPCOMING CLASS - " + course_name_up + " in " + str(classroom_id_up))
					action_taken = true
				else:
					if DETAILED_LOGGING_ENABLED: print_debug_student("  Action: Found UPCOMING class '" + course_name_up + "' but classroom location (ID: " + str(classroom_id_up) + ") unknown or full. Cannot prepare.")
		elif DETAILED_LOGGING_ENABLED:
			print_debug_student("  No UPCOMING class found by _get_next_class_to_prepare_for.")
		if action_taken: return

	if not action_taken and (needs.get("energy", MAX_NEED_VALUE) < 25.0 or needs.get("rest", MAX_NEED_VALUE) < 30.0):
		if current_activity != "resting" and current_activity != "going_to_rest":
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: Low Energy/Rest. Attempting to find dorm.")
			if _find_and_go_to_functional_building("going_to_rest", "dorm"):
				if DETAILED_LOGGING_ENABLED: print_debug_student("  ACTION TAKEN: Going to REST (Low Energy/Rest).")
				action_taken = true
			elif current_activity != "wandering_tired": 
					if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: Critically need rest but no dorm. Setting to 'wandering_tired'.")
					set_activity("wandering_tired") 
					action_taken = true 
		if action_taken: return

	if not action_taken and needs.get("study_urge", MIN_NEED_VALUE) > 75.0:
		if current_activity != "studying" and current_activity != "going_to_study":
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: High Study Urge. Attempting to find library/study spot.")
			if _find_and_go_to_functional_building("going_to_study", "library"):
				if DETAILED_LOGGING_ENABLED: print_debug_student("  ACTION TAKEN: Going to STUDY (High Urge).")
				action_taken = true
			elif current_activity != "wandering_anxious": 
					if DETAILED_LOGGING_ENABLED: print_debug_student("  Needs: High urge to study but no study loc. Setting to 'wandering_anxious'.")
					set_activity("wandering_anxious")
					action_taken = true
		if action_taken: return

	if not action_taken:
		var wandering_states = ["idle", "wandering_campus", "wandering_tired", "wandering_anxious"] 
		var needs_new_wander_target = false

		if current_activity == "idle": 
			needs_new_wander_target = true
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Fallback: Was idle, deciding to WANDER.")
		elif wandering_states.has(current_activity): 
			if not is_instance_valid(navigation_agent) or \
			   navigation_agent.is_navigation_finished() or \
			   navigation_agent.get_target_position() == global_position or \
			   not navigation_agent.is_target_reachable():
				needs_new_wander_target = true
				if DETAILED_LOGGING_ENABLED: print_debug_student("  Wander state (" + current_activity + ") needs new target (finished, at target, or unreachable).")
		else: 
			needs_new_wander_target = true
			if DETAILED_LOGGING_ENABLED: print_debug_student("  Fallback: Current activity '" + current_activity + "' not a priority, deciding to WANDER.")


		if needs_new_wander_target:
			var wander_activity_to_set = "wandering_campus"
			if needs.get("energy", MAX_NEED_VALUE) < 35.0 or needs.get("rest", MAX_NEED_VALUE) < 40.0:
				wander_activity_to_set = "wandering_tired"
			elif needs.get("study_urge", MIN_NEED_VALUE) > 65.0: 
				wander_activity_to_set = "wandering_anxious"

			set_activity(wander_activity_to_set)

			var wander_offset_x = randf_range(-15.0, 15.0)
			var wander_offset_z = randf_range(-15.0, 15.0)
			if abs(wander_offset_x) < 2.0 and abs(wander_offset_z) < 2.0: 
				var r_sign_x = 1.0 if randf() > 0.5 else -1.0
				var r_sign_z = 1.0 if randf() > 0.5 else -1.0
				wander_offset_x = r_sign_x * randf_range(5.0, 10.0)
				wander_offset_z = r_sign_z * randf_range(5.0, 10.0)

			var nav_y = EXPECTED_NAVMESH_Y
			var new_wander_target = Vector3(global_position.x + wander_offset_x, nav_y, global_position.z + wander_offset_z)

			if DETAILED_LOGGING_ENABLED: print_debug_student("  ACTION TAKEN: Setting NEW " + wander_activity_to_set + " target to: %s (from current pos %s)" % [str(new_wander_target.round()), str(global_position.round())])
			navigate_to_target(new_wander_target)
			action_taken = true 

	if not action_taken and DETAILED_LOGGING_ENABLED: 
		print_debug_student("  WARNING: _decide_next_activity FINISHED WITH NO ACTION TAKEN! Current activity: " + current_activity + ". Forcing idle and re-decision.")
		if current_activity != "idle": 
			set_activity("idle")
		call_deferred("_decide_next_activity") 
		action_taken = true 

	if DETAILED_LOGGING_ENABLED: print_debug_student("--- DECIDE NEXT ACTIVITY END --- Action Taken This Cycle: " + str(action_taken) + " Final Activity: " + current_activity)

func get_courses_for_current_term_from_progression() -> Array[String]:
	if is_instance_valid(degree_progression) and is_instance_valid(university_data_ref):
		return degree_progression.get_next_courses_to_take(university_data_ref)
	if DETAILED_LOGGING_ENABLED:
		if not is_instance_valid(degree_progression):
			print_debug_student("get_courses_for_current_term: DegreeProgression node invalid.")
		if not is_instance_valid(university_data_ref):
			print_debug_student("get_courses_for_current_term: UniversityData ref invalid.")
	return []
	
func get_info_summary() -> Dictionary:
	var summary: Dictionary = {}
	summary["student_name"] = student_name
	summary["student_id"] = student_id 

	var program_name_str = "N/A"
	if is_instance_valid(university_data_ref) and not current_program_id.is_empty():
		var prog_details = university_data_ref.get_program_details(current_program_id)
		program_name_str = prog_details.get("name", "Unknown Program")
	summary["program_name"] = program_name_str

	var course_names: Array[String] = []
	for offering_id in current_course_enrollments:
		var enrollment_data = current_course_enrollments[offering_id]
		course_names.append(enrollment_data.get("course_name", "Unknown Course in Enrollment"))
	summary["current_courses_list"] = course_names

	var student_status = "Enrolled"
	var credits_e = 0.0
	var credits_n = 0.0

	if is_instance_valid(degree_progression):
		if degree_progression.is_graduated:
			student_status = "Graduated!"
		credits_e = degree_progression.total_credits_earned
		if is_instance_valid(university_data_ref) and not current_program_id.is_empty():
			var prog_details_for_credits = university_data_ref.get_program_details(current_program_id)
			credits_n = prog_details_for_credits.get("credits_to_graduate", 0.0)
	else:
		student_status = "Progression N/A"


	summary["status"] = student_status
	summary["credits_earned"] = credits_e
	summary["credits_needed_for_program"] = credits_n

	if DETAILED_LOGGING_ENABLED:
		print_debug_student("get_info_summary() returning: " + str(summary))
	return summary
