# Student.gd
class_name Student
extends CharacterBody3D

# --- Constants ---
const MAX_NEED_VALUE: float = 100.0
const MIN_NEED_VALUE: float = 0.0
const EXPECTED_NAVMESH_Y: float = 0.3 # IMPORTANT: Verify and set this to your game's single intended NavMesh Y-level!

# --- Core Student Information ---
var student_id: String = "default_id"
var student_name: String = "Default Student Name"
var current_program_id: String = ""
var academic_start_year: int = 0
var current_course_enrollments: Dictionary = {}

# --- Needs System ---
var needs: Dictionary = {
	"energy": 100.0,
	"rest": 100.0,
	"study_urge": 0.0,
}

# --- Activity & State ---
var current_activity: String = "idle"
var current_activity_target_data: Variant = null
var current_target_node_id: String = ""
var time_spent_in_current_activity_visual: float = 0.0

# --- Node References ---
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var label_3d: Label3D = $Label3D

# --- Manager References ---
var academic_manager_ref: AcademicManager
var university_data_ref: UniversityData
var time_manager_ref: TimeManager
var building_manager_ref: BuildingManager

# --- Movement ---
@export var move_speed: float = 3.0
var current_target_position: Vector3 # For navigation_agent target (after snapping)


func _ready():
	if not is_instance_valid(navigation_agent):
		printerr("[%s] NavigationAgent3D node not found!" % self.name)
	else:
		if not navigation_agent.is_connected("navigation_finished", Callable(self, "_on_navigation_agent_navigation_finished")):
			navigation_agent.navigation_finished.connect(Callable(self, "_on_navigation_agent_navigation_finished"))
			
	if is_instance_valid(label_3d): label_3d.text = student_name if not student_name.is_empty() else "Student"
	print_debug_student("Node _ready(). Awaiting full initialization.")
	# Ensure student starts at the expected Y level, or configure NavigationAgent3D.navigation_height_offset
	# This is better handled at spawn time by the spawner.
	# global_position.y = EXPECTED_NAVMESH_Y


func initialize_new_student(s_id: String, s_name: String, prog_id: String, start_year: int,
						  acad_man: AcademicManager, univ_data: UniversityData, time_man: TimeManager):
	self.student_id = s_id
	self.student_name = s_name
	self.name = "Student_%s_%s" % [s_name.replace(" ", "_").to_lower(), s_id.right(4)]
	self.current_program_id = prog_id
	self.academic_start_year = start_year
	
	self.academic_manager_ref = acad_man
	self.university_data_ref = univ_data
	self.time_manager_ref = time_man
	if is_instance_valid(academic_manager_ref):
		self.building_manager_ref = academic_manager_ref.building_manager

	if not is_instance_valid(time_manager_ref): printerr("[%s] CRITICAL: TimeManager ref not passed!" % self.name)
	if not is_instance_valid(building_manager_ref): print_debug_student("Warning: BuildingManager ref not available (e.g., for finding dorms).")

	if is_instance_valid(label_3d): label_3d.text = self.student_name
	
	needs["energy"] = MAX_NEED_VALUE
	needs["rest"] = MAX_NEED_VALUE
	needs["study_urge"] = randf_range(20.0, 50.0)

	print_debug_student("Initialized. Program: '%s', Start Year: %d." % [current_program_id, academic_start_year])
	if is_instance_valid(time_manager_ref) and time_manager_ref.has_signal("visual_hour_slot_changed"):
		if not time_manager_ref.is_connected("visual_hour_slot_changed", Callable(self, "_on_visual_hour_changed")):
			time_manager_ref.visual_hour_slot_changed.connect(Callable(self, "_on_visual_hour_changed"))


func confirm_course_enrollment(offering_id: String, course_offering_details: Dictionary):
	if current_course_enrollments.has(offering_id): print_debug_student("Already tracking: %s" % offering_id); return
	var base_course_data = {}
	if is_instance_valid(university_data_ref) and course_offering_details.has("course_id"):
		base_course_data = university_data_ref.get_course_details(course_offering_details.get("course_id"))
	current_course_enrollments[offering_id] = {
		"course_id": course_offering_details.get("course_id", "N/A"), "course_name": course_offering_details.get("course_name", "N/A"),
		"status": "enrolled", "progress": 0.0, "credits": base_course_data.get("credits", 0),
		"progress_needed_for_completion": base_course_data.get("progress_needed", 100),
		"schedule_info": { "classroom_id": course_offering_details.get("classroom_id"), "pattern": course_offering_details.get("pattern"),
						   "start_time_slot": course_offering_details.get("start_time_slot"), "duration_slots": course_offering_details.get("duration_slots", 1)}
	}
	print_debug_student("Confirmed enrollment in: %s (%s)." % [offering_id, course_offering_details.get("course_name")])


func on_fully_spawned_and_enrolled():
	print_debug_student("Fully spawned. Initial AI decision deferred.")
	call_deferred("_decide_next_activity")


func _physics_process(delta: float):
	if not is_instance_valid(navigation_agent): return

	if navigation_agent.is_navigation_finished():
		if velocity != Vector3.ZERO: velocity = Vector3.ZERO
		return

	var target_is_reachable = navigation_agent.is_target_reachable()

	if target_is_reachable:
		var next_path_pos = navigation_agent.get_next_path_position()
		# Ensure movement primarily on the XZ plane if NavMesh is flat.
		# Agent should provide next_path_pos.y on the NavMesh.
		var direction = next_path_pos - global_position
		# If EXPECTED_NAVMESH_Y is strictly enforced and NavMesh is perfectly flat,
		# student_y and next_path_pos.y should be very similar.
		# Forcing direction.y = 0 can prevent slight "bobbing" on imperfectly flat NavMeshes
		# but might interfere if there are slight intentional slopes.
		# direction.y = 0 # Uncomment if you want to strictly enforce XZ movement plane
		
		velocity = direction.normalized() * move_speed
		
		# Uncomment for very detailed movement logs if actively debugging 'going_to_class'
		# if current_activity == "going_to_class":
		# 	print_debug_student("Physics: MOVING to class. Vel: %s, TargetReachable: true, NextPathPos: %s, CurrentPos: %s" % [str(velocity.round()), str(next_path_pos.round()), str(global_position.round())])
	else:
		velocity = Vector3.ZERO
		if current_activity == "going_to_class": # This log is crucial for diagnosing stuck students
			print_debug_student("Physics: TARGET NOT REACHABLE for 'going_to_class'. NavAgentTarget: %s. MyPos: %s. Velocity ZERO." % [str(navigation_agent.get_target_position().round()), str(global_position.round())])

	move_and_slide()
	# Optional: After move_and_slide, ensure student Y stays at expected level if NavMesh is flat.
	# This is a bit of a forceful correction; ideally, physics/NavAgent handles it.
	# if abs(global_position.y - EXPECTED_NAVMESH_Y) > 0.05:
	#    global_position.y = EXPECTED_NAVMESH_Y


# --- AI and Activity Logic ---

func _on_visual_hour_changed(_day_str: String, _time_slot_str: String):
	# print_debug_student("Visual hour changed to %s, %s. Re-evaluating activity." % [_day_str, _time_slot_str]) # Often too verbose
	
	if is_instance_valid(time_manager_ref):
		_update_needs_based_on_activity(time_manager_ref.seconds_per_visual_hour_slot)
	
	if current_activity == "in_class" or current_activity == "resting" or current_activity == "studying":
		time_spent_in_current_activity_visual += time_manager_ref.seconds_per_visual_hour_slot if is_instance_valid(time_manager_ref) else 10.0
		if _check_if_current_activity_should_end():
			set_activity("idle")
			call_deferred("_decide_next_activity")
			return
	
	if current_activity == "idle" or current_activity == "wandering_campus":
		call_deferred("_decide_next_activity")


func _update_needs_based_on_activity(duration_seconds: float):
	var energy_change_rate = -0.05 
	var rest_increase_rate = 0.5
	var study_urge_increase_rate = 0.02
	var study_urge_decrease_rate = 0.2

	match current_activity:
		"resting":
			needs["rest"] = clampf(needs.get("rest", 0.0) + rest_increase_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
			needs["energy"] = clampf(needs.get("energy", 0.0) + rest_increase_rate * duration_seconds * 0.5, MIN_NEED_VALUE, MAX_NEED_VALUE)
		"studying":
			energy_change_rate = -0.1
			needs["study_urge"] = clampf(needs.get("study_urge", 0.0) - study_urge_decrease_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
		"in_class":
			energy_change_rate = -0.08
			needs["study_urge"] = clampf(needs.get("study_urge", 0.0) - (study_urge_decrease_rate * 0.5) * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
		_: 
			if current_activity != "studying":
				needs["study_urge"] = clampf(needs.get("study_urge", 0.0) + study_urge_increase_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	
	needs["energy"] = clampf(needs.get("energy", MAX_NEED_VALUE) + energy_change_rate * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	if needs.get("energy", MAX_NEED_VALUE) < 10.0 and current_activity != "resting":
		needs["rest"] = clampf(needs.get("rest", MAX_NEED_VALUE) - 0.05 * duration_seconds, MIN_NEED_VALUE, MAX_NEED_VALUE)
	# print_debug_student("Needs updated: Energy:%.1f, Rest:%.1f, StudyUrge:%.1f" % [needs.energy, needs.rest, needs.study_urge]) # Very verbose


func _check_if_current_activity_should_end() -> bool:
	if current_activity == "in_class" and current_activity_target_data is Dictionary:
		var offering_id = current_activity_target_data.get("offering_id")
		if current_course_enrollments.has(offering_id):
			var schedule_info = current_course_enrollments[offering_id].schedule_info
			var class_duration_slots = schedule_info.get("duration_slots", 1)
			var class_duration_visual_seconds = class_duration_slots * (time_manager_ref.seconds_per_visual_hour_slot if is_instance_valid(time_manager_ref) else 10.0)
			if time_spent_in_current_activity_visual >= class_duration_visual_seconds * 0.95:
				print_debug_student("Class duration ended for %s." % offering_id)
				return true
	elif current_activity == "resting":
		if needs.get("rest", 0.0) >= 95.0 and needs.get("energy", 0.0) >= 90.0 :
			print_debug_student("Finished resting.")
			return true
	elif current_activity == "studying":
		if needs.get("study_urge", 100.0) <= 10.0 or time_spent_in_current_activity_visual > 3600: # Max 1 visual hour (3600 game seconds if 1s=1s)
			print_debug_student("Finished studying.")
			return true
	return false


func _decide_next_activity():
	# Only log "Deciding next activity..." if not in a common repetitive state.
	if not (current_activity in ["idle", "wandering_campus", "wandering_tired", "wandering_anxious"]):
		print_debug_student("Deciding next activity... Current: %s, Energy:%.1f, Rest:%.1f, StudyUrge:%.1f" % [current_activity, needs.energy, needs.rest, needs.study_urge])
	
	if (current_activity == "in_class" or current_activity == "resting" or current_activity == "studying") and \
	   not _check_if_current_activity_should_end():
		# print_debug_student("Continuing current timed activity: %s" % current_activity)
		return

	var next_class_offering_id = _get_current_visual_class_offering()
	if not next_class_offering_id.is_empty():
		var class_details = current_course_enrollments[next_class_offering_id]
		var classroom_id = class_details.schedule_info.classroom_id
		
		if current_activity == "in_class" and current_activity_target_data.get("offering_id") == next_class_offering_id:
			print_debug_student("Continuing class: %s" % class_details.course_name)
			return

		var classroom_location_from_manager = Vector3.ZERO # Should already have Y at EXPECTED_NAVMESH_Y from AcademicManager
		if is_instance_valid(academic_manager_ref):
			classroom_location_from_manager = academic_manager_ref.get_classroom_location(classroom_id)

		if classroom_location_from_manager != Vector3.ZERO:
			# Ensure Y is at expected level, though AcademicManager should handle this
			if abs(classroom_location_from_manager.y - EXPECTED_NAVMESH_Y) > 0.05:
				print_debug_student("Warning: Classroom location Y %.2f from AcademicManager differs from EXPECTED_NAVMESH_Y %.2f. Adjusting." % [classroom_location_from_manager.y, EXPECTED_NAVMESH_Y])
				classroom_location_from_manager.y = EXPECTED_NAVMESH_Y

			set_activity("going_to_class", {"offering_id": next_class_offering_id, "classroom_id": classroom_id, "destination_name": "Classroom " + classroom_id})
			navigate_to_target(classroom_location_from_manager) # This will project Y and snap
			print_debug_student("Decided to GO TO CLASS: %s in classroom %s. Target: %s" % [class_details.course_name, classroom_id, str(classroom_location_from_manager.round())])
			return
		else:
			print_debug_student("Scheduled class %s found, but classroom '%s' location unknown." % [class_details.course_name, classroom_id])

	if needs.get("energy", MAX_NEED_VALUE) < 25.0 or needs.get("rest", MAX_NEED_VALUE) < 30.0:
		if current_activity != "resting":
			if _find_and_go_to_functional_building("going_to_rest", "dorm"):
				return
			else:
				print_debug_student("Critically need rest but no dorm found/available. Will wander tiredly.")
				set_activity("wandering_tired")
				return

	if needs.get("study_urge", MIN_NEED_VALUE) > 75.0:
		if current_activity != "studying":
			if _find_and_go_to_functional_building("going_to_study", "class"):
				return
			else:
				print_debug_student("High urge to study but no study location found. Will wander anxiously.")
				set_activity("wandering_anxious")
				return

	if not (current_activity in ["wandering_campus", "wandering_tired", "wandering_anxious"]): # Avoid re-setting if already in a wander state
		# print_debug_student("No pressing classes or needs. Deciding to wander campus.") # Kept commented
		set_activity("wandering_campus")
		var wander_target_xz = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		# Wander target Y should be on the expected NavMesh level
		var wander_target = Vector3(wander_target_xz.x, EXPECTED_NAVMESH_Y, wander_target_xz.y) 
		navigate_to_target(wander_target)


func _get_current_visual_class_offering() -> String:
	if not is_instance_valid(time_manager_ref) or not is_instance_valid(academic_manager_ref): return ""
	
	var visual_day_str = time_manager_ref.get_current_visual_day_string()
	var visual_time_slot_str = time_manager_ref.get_current_visual_time_slot_string()

	if visual_day_str == "InvalidDay" or visual_time_slot_str == "InvalidTime" or visual_time_slot_str == time_manager_ref.END_OF_ACADEMIC_DAY_SLOT: return ""

	for offering_id_key in current_course_enrollments:
		var enrollment_data = current_course_enrollments[offering_id_key]
		var schedule_info = enrollment_data.get("schedule_info", {})
		if schedule_info.is_empty(): continue

		var class_pattern_str = schedule_info.get("pattern")
		var class_start_slot_str = schedule_info.get("start_time_slot")
		var days_class_occurs_on: Array[String] = academic_manager_ref.get_days_for_pattern(class_pattern_str)

		if days_class_occurs_on.has(visual_day_str):
			if class_start_slot_str == visual_time_slot_str:
				print_debug_student("Found current class: %s (Offering: %s) at %s, %s" % [enrollment_data.course_name, offering_id_key, visual_day_str, visual_time_slot_str])
				return offering_id_key
	return ""


func navigate_to_target(target_pos_from_ai: Vector3): # Renamed param for clarity
	if not is_instance_valid(navigation_agent):
		printerr("[%s] Cannot navigate: NavigationAgent3D not found." % self.name)
		return

	# Project the incoming target Y to the single expected NavMesh Y-level
	var projected_target_pos = Vector3(target_pos_from_ai.x, EXPECTED_NAVMESH_Y, target_pos_from_ai.z)
	if abs(target_pos_from_ai.y - EXPECTED_NAVMESH_Y) > 0.05: # Log if original Y was different
		print_debug_student("Nav target Y %.2f from AI was projected to EXPECTED_NAVMESH_Y %.2f. Original AI target: %s" % [target_pos_from_ai.y, EXPECTED_NAVMESH_Y, str(target_pos_from_ai.round())])

	var final_nav_target = projected_target_pos
	var nav_map_rid = get_world_3d().navigation_map

	if nav_map_rid.is_valid():
		var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map_rid, projected_target_pos)
		
		# Check if snapping significantly changed the Y from our expected single level
		if abs(snapped_pos.y - EXPECTED_NAVMESH_Y) > 0.1: # More than 10cm Y difference
			print_debug_student("CRITICAL NAVMESH WARNING: Target XZ(%.1f, %.1f) was aimed at Y=%.2f (EXPECTED_NAVMESH_Y), but NavMesh snapped to Y=%.2f. Your NavMesh is NOT single-level at this XZ location, or EXPECTED_NAVMESH_Y is wrong!" % [projected_target_pos.x, projected_target_pos.z, EXPECTED_NAVMESH_Y, snapped_pos.y])
			# The script will use the snapped_pos.y as that's where the NavMesh actually is for pathfinding.
			# If this happens for classrooms, they won't be reachable if the rest of the NavMesh is at EXPECTED_NAVMESH_Y.
		
		var snap_distance_overall = snapped_pos.distance_to(projected_target_pos)
		if snap_distance_overall > 0.5: # If snapped more than 0.5 units overall
			print_debug_student("Nav target %s (projected to Y=%.2f) was snapped to %s (distance: %.2f). Original might be off NavMesh or NavMesh is uneven." % [str(projected_target_pos.round()), EXPECTED_NAVMESH_Y, str(snapped_pos.round()), snap_distance_overall])
		
		final_nav_target = snapped_pos # Use the (potentially Y-deviant) snapped position as the true nav point
	else:
		print_debug_student("Warning: Could not get valid navigation map RID for snapping target. Using projected target: %s" % str(projected_target_pos.round()))


	if final_nav_target == current_target_position and not navigation_agent.is_navigation_finished():
		# print_debug_student("Already navigating to this exact target: %s" % str(final_nav_target.round())) # Verbose
		return 

	current_target_position = final_nav_target # This is the actual target for the agent
	navigation_agent.set_target_position(current_target_position)
	
	# Check if student's current Y is significantly off the expected plane when starting navigation
	if abs(global_position.y - EXPECTED_NAVMESH_Y) > 0.25 : # If student is more than 25cm off expected Y
		print_debug_student("Warning: Student current Y is %.2f, potentially far from EXPECTED_NAVMESH_Y %.2f when pathing to %s. May affect path start." % [global_position.y, EXPECTED_NAVMESH_Y, str(current_target_position.round())])

	# print_debug_student("Navigation NEW target set: %s (Original AI target: %s, Projected: %s)" % [str(current_target_position.round()), str(target_pos_from_ai.round()), str(projected_target_pos.round())]) # Verbose


func _on_navigation_agent_navigation_finished():
	print_debug_student("Navigation FINISHED. Reached target for activity: '%s'." % current_activity)
	velocity = Vector3.ZERO
	time_spent_in_current_activity_visual = 0.0

	match current_activity:
		"going_to_class":
			set_activity("in_class", current_activity_target_data)
			print_debug_student("Arrived at class for offering: %s. Now 'in_class'." % str(current_activity_target_data))
		"going_to_rest":
			set_activity("resting", current_activity_target_data)
			print_debug_student("Arrived at dorm %s. Now 'resting'." % str(current_activity_target_data))
		"going_to_study":
			set_activity("studying", current_activity_target_data)
			print_debug_student("Arrived at study location %s. Now 'studying'." % str(current_activity_target_data))
		_: 
			if not (current_activity in ["wandering_campus", "idle", "wandering_tired", "wandering_anxious"]):
				print_debug_student("Reached target for '%s'. Deciding next action." % current_activity)
			set_activity("idle")
			call_deferred("_decide_next_activity")


func set_activity(new_activity_name: String, target_info: Variant = null):
	if current_activity == new_activity_name and current_activity_target_data == target_info:
		return
		
	var old_activity = current_activity
	current_activity = new_activity_name
	current_activity_target_data = target_info
	current_target_node_id = ""
	if target_info is Dictionary:
		current_target_node_id = target_info.get("classroom_id", target_info.get("building_id", ""))

	time_spent_in_current_activity_visual = 0.0
	# Only log if it's a meaningful change or a new target for an ongoing important activity
	if old_activity != new_activity_name or (target_info != null and current_activity_target_data != target_info):
		print_debug_student("Activity changed to: '%s'. Target Data: %s" % [current_activity, str(target_info)])


func _find_and_go_to_functional_building(activity_name_for_state_when_going: String, building_type_target: String) -> bool:
	if not is_instance_valid(building_manager_ref):
		printerr("[%s] Cannot find '%s': BuildingManager reference missing." % [self.name, building_type_target])
		return false
	if not building_manager_ref.has_method("get_functional_buildings_data"):
		printerr("[%s] BuildingManager missing 'get_functional_buildings_data'." % self.name)
		return false

	var functional_buildings: Dictionary = building_manager_ref.get_functional_buildings_data()
	var potential_target_nodes_positions: Array[Vector3] = [] # Store positions directly
	var potential_target_ids: Array[String] = []

	for cluster_id_key in functional_buildings:
		var building_data = functional_buildings[cluster_id_key]
		if building_data.get("building_type") == building_type_target:
			var rep_node = building_data.get("representative_block_node")
			if is_instance_valid(rep_node) and rep_node is Node3D:
				# Get position and ensure Y is at the expected NavMesh level
				var building_pos = rep_node.global_position
				potential_target_nodes_positions.append(Vector3(building_pos.x, EXPECTED_NAVMESH_Y, building_pos.z))
				potential_target_ids.append(str(cluster_id_key))

	if not potential_target_nodes_positions.is_empty():
		var random_index = randi() % potential_target_nodes_positions.size()
		var chosen_location_pos = potential_target_nodes_positions[random_index] # This is already Y-projected
		var chosen_building_id = potential_target_ids[random_index]
		
		set_activity(activity_name_for_state_when_going, {"building_id": chosen_building_id, "destination_name": "%s %s" % [building_type_target.capitalize(), chosen_building_id]})
		navigate_to_target(chosen_location_pos) # Pass the Y-projected position
		print_debug_student("Found '%s' at '%s'. Navigating to %s." % [building_type_target, chosen_building_id, str(chosen_location_pos.round())])
		return true
	
	print_debug_student("Could not find any location of type '%s' for activity '%s'." % [building_type_target, activity_name_for_state_when_going])
	return false


func print_debug_student(message: String):
	var id_str = student_id if not student_id.is_empty() else "UNINIT"
	var name_str = student_name if not student_name.is_empty() else self.name
	print("[%s - %s]: %s" % [name_str, id_str, message])
