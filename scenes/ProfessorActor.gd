# ProfessorActor.gd
class_name ProfessorActor
extends CharacterBody3D

const DETAILED_LOGGING_ENABLED: bool = true
const EXPECTED_NAVMESH_Y: float = 0.3 # Match your student's if they share the same navmesh plane
const MAX_TIME_STUCK_PROF_THRESHOLD: float = 12.0 # How long to try before giving up (seconds)

# --- Core Professor Information ---
var professor_id: String = "default_prof_id"
var professor_name: String = "Default Professor"
var professor_data_ref: Professor # Reference to the Professor data object

# --- Node References ---
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var label_3d: Label3D = $Label3D
@onready var visuals: Node3D = $Visuals # Ensure this child node is named "Visuals" in your .tscn
@onready var animation_player: AnimationPlayer = $AnimationPlayer # If you have one

# --- State & Managers ---
var current_activity: String = "idle" # e.g., "idle", "going_to_class", "teaching", "going_to_office", "wandering"
var current_activity_target_data: Variant = null
var time_stuck_trying_to_reach_target: float = 0.0 # For stuck detection

var academic_manager_ref: AcademicManager
var university_data_ref: UniversityData
var time_manager_ref: TimeManager
var professor_manager_ref: ProfessorManager
var building_manager_ref: BuildingManager

# --- Movement ---
@export var base_move_speed: float = 2.5
var current_calculated_move_speed: float = 2.5

# --- Signals ---
signal professor_despawn_data_for_manager(data: Dictionary)

func _ready():
	if not is_instance_valid(navigation_agent):
		printerr("[%s] CRITICAL: NavigationAgent3D node not found!" % self.name)
	else:
		navigation_agent.set_target_position(global_position)
		if not navigation_agent.is_connected("navigation_finished", Callable(self, "_on_navigation_agent_navigation_finished")):
			navigation_agent.navigation_finished.connect(Callable(self, "_on_navigation_agent_navigation_finished"))

	if is_instance_valid(label_3d):
		label_3d.text = professor_name if not professor_name.is_empty() else "Professor" # Default if name not set yet
	
	if not is_instance_valid(visuals):
		printerr("[%s] CRITICAL: Professor 'Visuals' child node NOT FOUND in _ready! Check scene tree and name." % self.name)
	else:
		visuals.visible = true # Ensure visible at start

	if not is_instance_valid(animation_player):
		if DETAILED_LOGGING_ENABLED: print_debug_professor("Warning: AnimationPlayer node not found.")

	current_calculated_move_speed = base_move_speed
	velocity = Vector3.ZERO
	
	if is_instance_valid(time_manager_ref): # time_manager_ref is set in initialize
		_connect_to_time_manager_signals() # Connect to speed and visual hour change

	if DETAILED_LOGGING_ENABLED: print_debug_professor("Node _ready(). Name: %s. Initial global_position: %s" % [self.name, str(global_position)])
	# Initial decision is often better after initialize sets up manager refs
	# call_deferred("_decide_next_activity") # Moved to end of initialize

func _connect_to_time_manager_signals():
	if not is_instance_valid(time_manager_ref): return

	if time_manager_ref.has_signal("speed_changed"):
		if not time_manager_ref.is_connected("speed_changed", Callable(self, "_on_time_manager_speed_changed")):
			time_manager_ref.speed_changed.connect(Callable(self, "_on_time_manager_speed_changed"))
		_on_time_manager_speed_changed(time_manager_ref.get_speed_multiplier()) # Get initial speed

	if time_manager_ref.has_signal("visual_hour_slot_changed"):
		if not time_manager_ref.is_connected("visual_hour_slot_changed", Callable(self, "_on_visual_hour_changed")):
			time_manager_ref.visual_hour_slot_changed.connect(Callable(self, "_on_visual_hour_changed"))


func initialize(p_id: String, p_name: String,
				prof_man: ProfessorManager, acad_man: AcademicManager, time_man: TimeManager, build_man: BuildingManager):
	self.professor_id = p_id
	self.professor_name = p_name
	self.name = "ProfActor_%s_%s" % [p_name.replace(" ", "_").to_lower().left(10), p_id.right(4)] # Ensure unique enough

	self.professor_manager_ref = prof_man
	self.academic_manager_ref = acad_man
	self.time_manager_ref = time_man
	self.building_manager_ref = build_man

	if is_instance_valid(professor_manager_ref):
		self.professor_data_ref = professor_manager_ref.get_professor_by_id(p_id)
		if not is_instance_valid(self.professor_data_ref):
			printerr("[%s] CRITICAL: Could not get Professor data object for ID %s from ProfessorManager!" % [self.name, p_id])
	else:
		printerr("[%s] CRITICAL: ProfessorManager reference not valid in initialize!" % self.name)

	if is_instance_valid(label_3d):
		label_3d.text = self.professor_name
	
	_connect_to_time_manager_signals() # Connect signals after time_manager_ref is set

	if DETAILED_LOGGING_ENABLED: print_debug_professor("Initialized. Name: %s, ID: %s. Visuals valid: %s. GlobalPos: %s" % [professor_name, professor_id, str(is_instance_valid(visuals)), str(global_position)])
	call_deferred("_decide_next_activity") # Make first decision after full initialization


func _physics_process(delta: float):
	if not is_instance_valid(navigation_agent): return

	if navigation_agent.is_navigation_finished():
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		# time_stuck_trying_to_reach_target is reset in _on_navigation_agent_navigation_finished
		return

	if not is_instance_valid(visuals) or not visuals.visible:
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		return

	var target_nav_pos = navigation_agent.get_target_position()
	if target_nav_pos == global_position and not navigation_agent.is_target_reachable():
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		time_stuck_trying_to_reach_target += delta
		if time_stuck_trying_to_reach_target > MAX_TIME_STUCK_PROF_THRESHOLD / 2.0: # Shorter timeout if stuck at self
			if DETAILED_LOGGING_ENABLED: print_debug_professor("Stuck at own global_position with unreachable target. Resetting to idle.")
			set_activity("idle") # This will reset time_stuck_trying_to_reach_target
			call_deferred("_decide_next_activity")
		return

	if navigation_agent.is_target_reachable():
		var next_path_pos = navigation_agent.get_next_path_position()
		var direction_to_next = global_position.direction_to(next_path_pos)
		var distance_to_next = global_position.distance_to(next_path_pos)

		if distance_to_next > navigation_agent.target_desired_distance * 0.5 : # Check if still need to move towards next point
			velocity = direction_to_next * current_calculated_move_speed
			if velocity.length() > 0.05:
				look_at(global_position + velocity.normalized() * Vector3(1,0,1), Vector3.UP)
		else: # Very close to the current path point, or it's the final target
			if navigation_agent.is_target_reached(): # Check if final target is reached
				velocity = Vector3.ZERO # Stop precisely at target
				# Navigation finished signal will handle next steps
			else: # Still more path points to go, but close to current one
				velocity = direction_to_next * current_calculated_move_speed # Keep moving towards it

		time_stuck_trying_to_reach_target = 0.0
	else: # Target not reachable
		if velocity.length_squared() > 0.01: velocity = Vector3.ZERO
		
		var activity_can_get_stuck = current_activity in ["going_to_class", "going_to_office", "wandering"]
		if activity_can_get_stuck:
			time_stuck_trying_to_reach_target += delta
			if DETAILED_LOGGING_ENABLED and int(time_stuck_trying_to_reach_target) % 3 == 0 :
				print_debug_professor("TARGET NOT REACHABLE for '%s' (%.1fs stuck). NavTarget: %s." % [current_activity, time_stuck_trying_to_reach_target, str(target_nav_pos.round())])

			if time_stuck_trying_to_reach_target > MAX_TIME_STUCK_PROF_THRESHOLD:
				if DETAILED_LOGGING_ENABLED: print_debug_professor("GIVING UP on current target for '%s' after %.1fs. Setting to idle." % [current_activity, time_stuck_trying_to_reach_target])
				set_activity("idle") # This will reset time_stuck_trying_to_reach_target
				call_deferred("_decide_next_activity")
				return

	move_and_slide()


func _on_visual_hour_changed(_day_str: String, _time_slot_str: String):
	# Only re-evaluate if idle or wandering, or if a critical need arises (not implemented for profs yet)
	if current_activity == "idle" or current_activity == "wandering":
		if DETAILED_LOGGING_ENABLED: print_debug_professor("Visual hour changed. Re-evaluating activity from: " + current_activity)
		call_deferred("_decide_next_activity")


func _decide_next_activity():
	if not is_instance_valid(self): return
	if not is_instance_valid(academic_manager_ref) or \
	   not is_instance_valid(time_manager_ref) or \
	   not is_instance_valid(professor_data_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_professor("Cannot decide activity: Missing manager refs or professor_data_ref.")
		set_activity("idle")
		return

	if DETAILED_LOGGING_ENABLED: print_debug_professor("Deciding next activity. Current: %s. Courses teaching: %s" % [current_activity, str(professor_data_ref.courses_teaching_ids)])

	var current_day_str = time_manager_ref.get_current_visual_day_string()
	var current_slot_str = time_manager_ref.get_current_visual_time_slot_string()
	var offering_to_attend_now: String = _find_class_for_professor_at_time(current_day_str, current_slot_str)
	var next_slot_offering_id: String = ""

	if is_instance_valid(time_manager_ref) and time_manager_ref.get_current_simulation_minute() >= 45: # Check if late in the hour
		var next_academic_slot = time_manager_ref.get_next_academic_slot_info()
		if next_academic_slot.has("day") and next_academic_slot.has("slot") and \
		   next_academic_slot.day != "InvalidDay" and next_academic_slot.slot != "InvalidTime":
			next_slot_offering_id = _find_class_for_professor_at_time(next_academic_slot.day, next_academic_slot.slot)

	var target_offering_id = ""
	var reason_for_going = ""
	if not offering_to_attend_now.is_empty():
		target_offering_id = offering_to_attend_now
		reason_for_going = "Class starting now"
	elif not next_slot_offering_id.is_empty():
		target_offering_id = next_slot_offering_id
		reason_for_going = "Class starting next slot, preparing"
	
	if not target_offering_id.is_empty():
		var offering_details = academic_manager_ref.get_offering_details(target_offering_id)
		if DETAILED_LOGGING_ENABLED: print_debug_professor("Potential class: %s. Reason: %s. Details: %s" % [target_offering_id, reason_for_going, str(offering_details)])

		if not offering_details.is_empty() and offering_details.get("status") == "scheduled":
			var classroom_id = offering_details.get("classroom_id")
			var course_name = offering_details.get("course_name", "Class")
			if not classroom_id.is_empty():
				var classroom_location = academic_manager_ref.get_classroom_location(classroom_id)
				if DETAILED_LOGGING_ENABLED: print_debug_professor("Targeting %s '%s' in classroom '%s'. Location from AM: %s" % [reason_for_going, course_name, classroom_id, str(classroom_location.round())])
				
				if classroom_location != Vector3.ZERO:
					set_activity("going_to_class", {"offering_id": target_offering_id, "classroom_id": classroom_id, "course_name": course_name})
					navigate_to_target(classroom_location)
					if DETAILED_LOGGING_ENABLED: print_debug_professor("ACTION: Going to class: %s in %s" % [course_name, classroom_id])
					return
				elif DETAILED_LOGGING_ENABLED: print_debug_professor("Classroom '%s' location from AM was ZERO or Building Manager reported full. Cannot go to class." % classroom_id)
			elif DETAILED_LOGGING_ENABLED: print_debug_professor("Classroom ID missing for offering '%s'." % target_offering_id)
		elif DETAILED_LOGGING_ENABLED: print_debug_professor("Offering '%s' found but not fully 'scheduled' (Status: %s) or details missing." % [target_offering_id, offering_details.get("status","N/A")])
	
	# Fallback: Wander or Idle
	# Only wander if truly idle or if a "going_to_class" failed and it reset to idle.
	# If currently "wandering" and navigation finished, _on_navigation_agent_navigation_finished would set to idle, then this is called.
	if current_activity == "idle" or (current_activity == "wandering" and navigation_agent.is_navigation_finished()):
		var wander_target = global_position + Vector3(randf_range(-12,12), 0, randf_range(-12,12)) # Slightly larger wander range
		set_activity("wandering")
		navigate_to_target(wander_target)
		if DETAILED_LOGGING_ENABLED: print_debug_professor("ACTION: Fallback to Wandering near " + str(wander_target.round()))
	elif DETAILED_LOGGING_ENABLED:
		print_debug_professor("No immediate class or other high-priority task. Current activity: " + current_activity + ". Will not change yet.")


func _find_class_for_professor_at_time(day_to_check: String, slot_to_check: String) -> String:
	if not is_instance_valid(professor_data_ref) or not is_instance_valid(academic_manager_ref):
		if DETAILED_LOGGING_ENABLED: print_debug_professor("_find_class: Professor data or AM ref invalid.")
		return ""
	if professor_data_ref.courses_teaching_ids.is_empty():
		if DETAILED_LOGGING_ENABLED: print_debug_professor("_find_class: No courses assigned to teach.")
		return ""
	if not is_instance_valid(time_manager_ref): # Added check
		if DETAILED_LOGGING_ENABLED: print_debug_professor("_find_class: TimeManager ref invalid.")
		return ""


	for offering_id in professor_data_ref.courses_teaching_ids:
		var offering_details = academic_manager_ref.get_offering_details(offering_id) # Fetches fresh details including status
		
		if offering_details.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_professor("  _find_class: Skipping offering %s, details empty." % offering_id)
			continue
			
		var current_offering_status = offering_details.get("status", "unknown")
		if current_offering_status != "scheduled":
			if DETAILED_LOGGING_ENABLED: print_debug_professor("  _find_class: Skipping offering %s (Course: %s), status is %s, not 'scheduled'." % [offering_id, offering_details.get("course_name","N/A"), current_offering_status])
			continue

		var pattern = offering_details.get("pattern")
		var start_slot = offering_details.get("start_time_slot")

		if pattern == null or pattern.is_empty() or start_slot == null or start_slot.is_empty():
			if DETAILED_LOGGING_ENABLED: print_debug_professor("  _find_class: Skipping offering %s, missing pattern ('%s') or start_slot ('%s')." % [offering_id, str(pattern), str(start_slot)])
			continue

		var days_for_class = academic_manager_ref.get_days_for_pattern(pattern)
		if days_for_class.has(day_to_check) and start_slot == slot_to_check:
			# TODO: Add re-entry prevention like in Student.gd if a professor might leave and re-enter class too quickly
			if DETAILED_LOGGING_ENABLED: print_debug_professor("  _find_class: Found match! Offering: %s for Day: %s, Slot: %s" % [offering_id, day_to_check, slot_to_check])
			return offering_id
	
	if DETAILED_LOGGING_ENABLED: print_debug_professor("_find_class: No class found for Day: %s, Slot: %s" % [day_to_check, slot_to_check])
	return ""


func _on_navigation_agent_navigation_finished():
	if DETAILED_LOGGING_ENABLED: print_debug_professor("Navigation FINISHED. Reached target for activity: '%s'." % current_activity)
	velocity = Vector3.ZERO
	time_stuck_trying_to_reach_target = 0.0

	var previous_activity = current_activity
	var target_data = current_activity_target_data

	# Default to idle, then specific arrival logic can override or lead to despawn
	set_activity("idle") 

	if previous_activity == "going_to_class":
		if target_data is Dictionary and target_data.has("offering_id") and target_data.has("classroom_id"):
			var arrived_offering_id = target_data.get("offering_id")
			var arrived_classroom_id = target_data.get("classroom_id")
			if DETAILED_LOGGING_ENABLED: print_debug_professor("Arrived at classroom %s for offering %s. Preparing to 'teach' (despawn)." % [arrived_classroom_id, arrived_offering_id])
			
			set_activity("teaching", target_data) # Set activity to teaching for clarity before despawn
			if is_instance_valid(visuals): visuals.visible = false
			self.process_mode = Node.PROCESS_MODE_DISABLED # Stop physics, decisions
			
			var current_tm_day = ""
			var current_tm_slot = ""
			if is_instance_valid(time_manager_ref):
				current_tm_day = time_manager_ref.get_current_visual_day_string()
				current_tm_slot = time_manager_ref.get_current_visual_time_slot_string()

			var despawn_data = {
				"professor_id": professor_id,
				"activity_after_despawn": "teaching", # The state they enter upon despawn
				"activity_target_data": target_data, # Contains offering_id, classroom_id, course_name
				"current_day_of_despawn": current_tm_day, # Day teaching started
				"current_slot_of_despawn": current_tm_slot  # Slot teaching started
			}
			emit_signal("professor_despawn_data_for_manager", despawn_data)
			return # Important: Professor is now simulated by ProfessorManager, do not run _decide_next_activity
	
	# If not despawned (e.g. finished wandering, or going_to_class failed before despawn logic)
	call_deferred("_decide_next_activity")


func set_activity(new_activity: String, data: Variant = null):
	# Only log if something actually changes to reduce spam
	if current_activity != new_activity or current_activity_target_data != data:
		if DETAILED_LOGGING_ENABLED:
			print_debug_professor("Activity changed from '%s' to '%s'. Target: %s" % [current_activity, new_activity, str(data)])
	current_activity = new_activity
	current_activity_target_data = data
	time_stuck_trying_to_reach_target = 0.0 # Reset stuck timer on any activity change
	
	# Basic Animation Control (Example)
	if is_instance_valid(animation_player):
		if new_activity == "wandering" or new_activity.begins_with("going_to_"):
			if animation_player.has_animation("Walk"): # Check if animation exists
				animation_player.play("Walk")
			elif animation_player.has_animation("walk"):
				animation_player.play("walk")
		else: # idle, teaching (before despawn), etc.
			if animation_player.has_animation("Idle"):
				animation_player.play("Idle")
			elif animation_player.has_animation("idle"):
				animation_player.play("idle")


func navigate_to_target(target_pos: Vector3):
	if not is_instance_valid(navigation_agent):
		if DETAILED_LOGGING_ENABLED: print_debug_professor("Navigate_to_target: NavigationAgent is invalid.")
		return
	
	var projected_target_y = Vector3(target_pos.x, EXPECTED_NAVMESH_Y, target_pos.z)
	var final_nav_target = projected_target_y
	
	if get_world_3d() and get_world_3d().navigation_map.is_valid():
		var nav_map_rid = get_world_3d().navigation_map
		var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map_rid, projected_target_y)
		if snapped_pos.distance_to(projected_target_y) > 1.0: # If snap is significant, log it
			if DETAILED_LOGGING_ENABLED: print_debug_professor("Nav target %s (projected Y) snapped to %s on NavMesh." % [str(projected_target_y.round()), str(snapped_pos.round())])
		final_nav_target = snapped_pos # Use snapped position
	elif DETAILED_LOGGING_ENABLED:
		print_debug_professor("Navigate_to_target: World3D or NavMap invalid, using projected Y target: %s" % str(projected_target_y.round()))

	navigation_agent.set_target_position(final_nav_target)
	time_stuck_trying_to_reach_target = 0.0 # Reset stuck timer for new target attempt
	
	if DETAILED_LOGGING_ENABLED:
		var is_reachable_str = "UNKNOWN (NavAgent invalid)"
		if is_instance_valid(navigation_agent): is_reachable_str = str(navigation_agent.is_target_reachable())
		print_debug_professor("Navigation target set to: %s. Is Reachable: %s" % [str(final_nav_target.round()), is_reachable_str])


func _on_time_manager_speed_changed(new_speed_multiplier: float):
	current_calculated_move_speed = base_move_speed * new_speed_multiplier
	if is_instance_valid(animation_player):
		if animation_player.has_method("set_speed_scale"): # Godot 3
			animation_player.set_speed_scale(new_speed_multiplier)
		elif animation_player.has_meta("speed_scale"): # Godot 4
			animation_player.speed_scale = new_speed_multiplier
	if DETAILED_LOGGING_ENABLED: print_debug_professor("Speed multiplier set to %.1fx. Move speed: %.2f" % [new_speed_multiplier, current_calculated_move_speed])


func print_debug_professor(message: String):
	if not DETAILED_LOGGING_ENABLED: return
	var id_str = professor_id if not professor_id.is_empty() else "NO_ID"
	var name_str = professor_name if not professor_name.is_empty() else self.name
	print("[%s - %s]: %s" % [name_str, id_str.right(4), message])


# ProfessorActor.gd

func finish_activity_and_respawn(p_exit_location: Vector3):
	if not is_instance_valid(self):
		printerr("ProfessorActor finish_activity_and_respawn called on invalid instance!")
		return

	if DETAILED_LOGGING_ENABLED: print_debug_professor("START finish_activity_and_respawn. Current global_pos: %s. Target exit_location: %s" % [str(global_position.round()), str(p_exit_location.round())])
	
	if is_instance_valid(visuals):
		visuals.visible = true
		if DETAILED_LOGGING_ENABLED: print_debug_professor("  Visuals.visible set to true. Is now: %s" % str(visuals.visible))
	else:
		if DETAILED_LOGGING_ENABLED: print_debug_professor("  CRITICAL: Visuals node is NULL during respawn!")
		# Attempt to get it again if it was somehow nulled, though this is unusual
		visuals = get_node_or_null("Visuals")
		if is_instance_valid(visuals):
			visuals.visible = true
			if DETAILED_LOGGING_ENABLED: print_debug_professor("  Visuals re-fetched and set to true.")
		else:
			printerr("[%s] Visuals node still null after re-fetch in respawn!" % self.name)


	self.process_mode = Node.PROCESS_MODE_INHERIT # Re-enable physics and _process
	if DETAILED_LOGGING_ENABLED: print_debug_professor("  Process_mode set to INHERIT. Is now: %s" % str(self.process_mode))
	
	# Set position BEFORE clearing navigation agent target, to avoid agent immediately trying to path from old pos
	global_position = p_exit_location
	if DETAILED_LOGGING_ENABLED: print_debug_professor("  Global_position set to: %s" % str(global_position.round()))
	
	if is_instance_valid(navigation_agent):
		# It's often good to force the agent to re-evaluate its position relative to the navmesh
		# This can be done by briefly setting its target to its new current position or by other agent-specific means.
		# Forcing a velocity clear and setting target to current position helps reset its state.
		navigation_agent.set_velocity(Vector3.ZERO) # Clear any residual velocity
		navigation_agent.set_target_position(global_position) # Clear old nav target by setting to current
		velocity = Vector3.ZERO # Clear CharacterBody3D velocity
		if DETAILED_LOGGING_ENABLED: print_debug_professor("  Navigation_agent target cleared, velocity zeroed.")
	else:
		if DETAILED_LOGGING_ENABLED: print_debug_professor("  NavigationAgent is NULL during respawn!")

	set_activity("idle") # Default to idle; _decide_next_activity will be called
	if DETAILED_LOGGING_ENABLED: print_debug_professor("  Activity set to 'idle'. Calling _decide_next_activity deferred.")
	call_deferred("_decide_next_activity") # Let the professor decide what to do next from their new position
	if DETAILED_LOGGING_ENABLED: print_debug_professor("END finish_activity_and_respawn.")
