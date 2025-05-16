# student.gd
# Represents an individual student in the university simulation.
# Manages their academic progress, needs, happiness, and navigation,
# including interaction with building capacities.
extends CharacterBody3D

# --- Exported Variables ---
@export var move_speed: float = 3.0 
@export var study_rate_per_update: float = 5.0 
@export var max_need_value: float = 100.0 # Ensure this is 100 in the Inspector if different from script default.
@export var study_need_decay_rate_per_day: float = 10.0 
@export var social_need_decay_rate_per_day: float = 12.0 
@export var rest_need_decay_rate_per_day: float = 15.0  
@export var need_seek_threshold: float = 40.0 
@export var need_fulfillment_interaction_time: float = 3.0 

# --- Constants ---
const TARGET_REACHED_THRESHOLD: float = 0.8 
const PATH_UPDATE_INTERVAL: float = 1.0 
const WANDER_PAUSE_DURATION: float = 2.0 

# --- Node References ---
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var path_update_timer: Timer = $PathUpdateTimer
@onready var interaction_timer: Timer = Timer.new() 
@onready var student_mesh: MeshInstance3D = $StudentMesh # Mesh for visual representation
@onready var wander_pause_timer: Timer = Timer.new() 

# --- Visuals ---
var default_albedo_color: Color = Color.WHITE
const INTERACTING_COLOR: Color = Color.GREEN # Will be mostly for debug as student is invisible
const SEEKING_STUDY_COLOR: Color = Color.LIGHT_BLUE
const SEEKING_SOCIAL_COLOR: Color = Color.YELLOW
const SEEKING_REST_COLOR: Color = Color.LAVENDER
const GENERIC_SEEKING_COLOR: Color = Color.ORANGE 
const GRADUATED_COLOR: Color = Color.GOLD


# --- Academic Properties ---
var student_name: String = "Unnamed Student"
var enrolled_program_id: String = ""
var enrolled_program_name: String = ""
var min_credits_for_graduation: int = 0
var current_courses: Array[String] = [] 
var course_progress: Dictionary = {} 
var completed_courses: Array[String] = [] 
var total_credits_earned: int = 0
var is_graduated: bool = false

# --- Needs & Happiness ---
var needs: Dictionary = { "study": 75.0, "social": 75.0, "rest": 75.0 } 
var happiness: float = 75.0

# --- State Machine ---
enum StudentState { IDLE_WANDERING, IDLE_PAUSED, SEEKING_NEED_LOCATION, MOVING_TO_NEED_LOCATION, USING_FACILITY } 
var current_state: StudentState = StudentState.IDLE_WANDERING

# --- Navigation & Interaction Targets ---
var current_target_building_node: Node3D = null 
var current_target_facility_script: BlockFacility = null # Reference to the BlockFacility script on the target
var current_need_to_fulfill: String = ""    
var has_target: bool = false 

# --- References ---
var university_data_ref: UniversityData 
var building_manager_ref: Node 
var main_navigation_region: NavigationRegion3D 
var effective_ground_y_ref: float = 0.0 

# --- Initialization Flags ---
var _is_physically_ready: bool = false
var _nav_references_are_set: bool = false
var _academic_info_set: bool = false


func _ready():
	if student_name == "Unnamed Student": 
		student_name = "Student@" + str(self.get_instance_id())

	print_debug("_ready: Initializing with actual CLASS MEMBER max_need_value = " + str(self.max_need_value) + ".")

	if not is_instance_valid(navigation_agent): 
		printerr(student_name + ": CRITICAL - NavigationAgent3D node not found!")
		set_physics_process(false); return
		
	navigation_agent.path_desired_distance = TARGET_REACHED_THRESHOLD * 0.8
	navigation_agent.target_desired_distance = TARGET_REACHED_THRESHOLD 
	navigation_agent.path_changed.connect(_on_path_changed)
	navigation_agent.target_reached.connect(_on_target_reached) 

	if is_instance_valid(path_update_timer):
		path_update_timer.wait_time = PATH_UPDATE_INTERVAL 
		path_update_timer.one_shot = false 
		path_update_timer.timeout.connect(_on_path_update_timer_timeout)
	else:
		printerr(student_name + ": CRITICAL - PathUpdateTimer node not found!")

	interaction_timer.name = "InteractionTimer"
	interaction_timer.one_shot = true 
	interaction_timer.wait_time = need_fulfillment_interaction_time
	interaction_timer.timeout.connect(_on_interaction_timer_timeout)
	add_child(interaction_timer)

	wander_pause_timer.name = "WanderPauseTimer"
	wander_pause_timer.one_shot = true
	wander_pause_timer.wait_time = WANDER_PAUSE_DURATION
	wander_pause_timer.timeout.connect(_on_wander_pause_timer_timeout)
	add_child(wander_pause_timer)

	building_manager_ref = get_tree().root.get_node_or_null("BuildingManager")
	if not is_instance_valid(building_manager_ref):
		printerr(student_name + ": Could not find BuildingManager node!")
	elif not building_manager_ref.has_method("get_all_occupied_cells_data"): # Or new method for functional buildings
		printerr(student_name + ": BuildingManager node is missing 'get_all_occupied_cells_data' or equivalent method!")
		building_manager_ref = null 

	if is_instance_valid(student_mesh):
		student_mesh.visible = true # Ensure mesh is visible on ready
		var current_material = student_mesh.get_active_material(0) 
		if current_material is StandardMaterial3D:
			default_albedo_color = current_material.albedo_color
		else: 
			default_albedo_color = Color.WHITE 
			var new_mat = StandardMaterial3D.new()
			new_mat.albedo_color = default_albedo_color
			student_mesh.material_override = new_mat 
	else:
		printerr(student_name + ": StudentMesh node NOT FOUND! Path needs to be '$StudentMesh' or similar. Color changes/visibility will not work.")

	_is_physically_ready = true
	_attempt_full_initialization()


func set_navigation_references(nav_region: NavigationRegion3D, ground_y: float):
	main_navigation_region = nav_region
	effective_ground_y_ref = ground_y
	_nav_references_are_set = true
	_attempt_full_initialization()

func set_academic_info(s_name: String, prog_id: String, u_data_node: UniversityData):
	student_name = s_name 
	enrolled_program_id = prog_id
	university_data_ref = u_data_node 
	
	if not is_instance_valid(university_data_ref):
		printerr(student_name + ": UniversityData reference not valid in set_academic_info!")
		_academic_info_set = true; _attempt_full_initialization(); return

	if enrolled_program_id != "":
		var program_details = university_data_ref.get_program_details(enrolled_program_id)
		if not program_details.is_empty():
			enrolled_program_name = program_details.get("name", "Unknown Program")
			min_credits_for_graduation = program_details.get("min_credits_for_graduation", 120) 
			
		var required_program_courses = university_data_ref.get_required_courses_for_program(enrolled_program_id)
		for course_id in required_program_courses:
			if not current_courses.has(course_id) and university_data_ref.COURSES.has(course_id): 
				current_courses.append(course_id)
				course_progress[course_id] = 0 
			elif not university_data_ref.COURSES.has(course_id):
				printerr(student_name + ": Tried to enroll in non-existent required course '" + course_id + "' for program '" + enrolled_program_id + "'")
		print_debug("Enrolled in program: '" + enrolled_program_name + "'. Taking " + str(current_courses.size()) + " initial courses.")
	else:
		printerr(student_name + ": Program ID empty in set_academic_info.")
		
	_academic_info_set = true
	_attempt_full_initialization()


func _attempt_full_initialization():
	if _is_physically_ready and _nav_references_are_set and _academic_info_set:
		print_debug("Fully initialized.")
		self.name = student_name 
		
		if is_instance_valid(path_update_timer): path_update_timer.start()
		else: printerr(student_name + ": PathUpdateTimer is invalid, cannot start.")

		if main_navigation_region: 
			call_deferred("set_new_behavior_or_target") 
		else: 
			printerr(student_name + ": Cannot set initial target because main_navigation_region is not set.")
		
		update_happiness() 
		update_visual_state() 


# --- State Machine & Behavior ---
func set_new_behavior_or_target():
	if is_graduated: update_visual_state(); return
	if current_state == StudentState.USING_FACILITY or current_state == StudentState.IDLE_PAUSED:
		update_visual_state(); return

	var most_pressing_need = get_most_pressing_need() 

	if (current_state == StudentState.MOVING_TO_NEED_LOCATION) and \
	   current_need_to_fulfill != "" and is_instance_valid(current_target_building_node):
		var committed_need_value = needs.get(current_need_to_fulfill, max_need_value + 1.0)
		if committed_need_value < need_seek_threshold: 
			if has_target and navigation_agent.target_position == current_target_building_node.global_position:
				update_visual_state()
				return 
		else: 
			print_debug("Committed need '" + current_need_to_fulfill + "' is now satisfied. Clearing commitment.")
			current_target_building_node = null
			current_target_facility_script = null 
			current_need_to_fulfill = ""
			
	if most_pressing_need != "" and needs.get(most_pressing_need, max_need_value + 1.0) < need_seek_threshold:
		if not (current_state == StudentState.MOVING_TO_NEED_LOCATION and current_need_to_fulfill == most_pressing_need and is_instance_valid(current_target_building_node)):
			current_state = StudentState.SEEKING_NEED_LOCATION 
			current_need_to_fulfill = most_pressing_need 
			print_debug("New top need is '" + most_pressing_need + "' (" + str(needs[most_pressing_need]) + "). Setting state to SEEKING_NEED_LOCATION.")
			find_location_for_need(most_pressing_need) 
			# update_visual_state() is called within find_location_for_need or if it falls back
			return 
	
	# print_debug("No pressing needs or find_location failed. Setting state to IDLE_WANDERING.")
	current_state = StudentState.IDLE_WANDERING
	current_target_building_node = null 
	current_target_facility_script = null 
	current_need_to_fulfill = ""     
	set_random_wander_target() 
	update_visual_state() 


func get_most_pressing_need() -> String:
	var lowest_value_found = self.max_need_value + 1.0 
	var most_pressing_type = ""
	if needs.is_empty(): return ""
	for need_key in needs.keys():
		var current_need_value = needs[need_key]
		if current_need_value < lowest_value_found:
			lowest_value_found = current_need_value
			most_pressing_type = need_key
		elif current_need_value == lowest_value_found and most_pressing_type == "": 
			most_pressing_type = need_key 
	return most_pressing_type


func find_location_for_need(need_type: String):
	if not is_instance_valid(building_manager_ref) or not is_instance_valid(university_data_ref):
		current_state = StudentState.IDLE_WANDERING 
		set_random_wander_target(); update_visual_state(); return 

	var all_buildings_data: Dictionary = building_manager_ref.get_all_occupied_cells_data()
	var suitable_locations: Array[Dictionary] = [] # Will store {"node": Node3D, "facility_script": BlockFacility}

	for coord_key in all_buildings_data:
		var block_cell_data = all_buildings_data[coord_key]
		var module_key = block_cell_data.get("module_key")
		var building_node_ref: Node3D = block_cell_data.get("node_ref") 

		if module_key and is_instance_valid(building_node_ref):
			# Get the BlockFacility script attached to the building_node_ref (StaticBody3D)
			var facility_script = building_node_ref.get_node_or_null("FacilityData") as BlockFacility 
			
			if is_instance_valid(facility_script):
				if facility_script.can_accommodate() and facility_script.fulfills_needs_data.has(need_type):
					suitable_locations.append({"node": building_node_ref, "facility_script": facility_script})
			# else: printerr("Block " + building_node_ref.name + " does not have FacilityData script or it's invalid.")
	
	if not suitable_locations.is_empty():
		var closest_loc_data: Dictionary = {}
		var min_dist_sq = INF
		for loc_data in suitable_locations:
			var loc_node: Node3D = loc_data.node
			var dist_sq = global_position.distance_squared_to(loc_node.global_position)
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
				closest_loc_data = loc_data
		
		if not closest_loc_data.is_empty():
			current_target_building_node = closest_loc_data.node
			current_target_facility_script = closest_loc_data.facility_script # Store the script reference
			set_new_target_position(current_target_building_node.global_position) 
			current_state = StudentState.MOVING_TO_NEED_LOCATION
			print_debug("FIND_LOCATION: SUCCESS! Target set for '" + need_type + "' at " + current_target_building_node.name + ". State: MOVING_TO_NEED_LOCATION. has_target: " + str(has_target))
			update_visual_state()
			return 
	
	print_debug("FIND_LOCATION: FAILURE: Could not find any location with capacity for need: '" + need_type + "'. Wandering.")
	current_state = StudentState.IDLE_WANDERING 
	current_need_to_fulfill = "" 
	current_target_building_node = null
	current_target_facility_script = null # Clear facility script ref
	set_random_wander_target() 
	update_visual_state()


# --- Needs & Happiness Logic ---
func update_needs_and_happiness():
	if is_graduated: return
	var needs_changed = false
	if needs.has("study"):
		needs.study -= self.study_need_decay_rate_per_day 
		needs.study = clampf(needs.study, 0.0, self.max_need_value); needs_changed = true
	if needs.has("social"):
		needs.social -= self.social_need_decay_rate_per_day 
		needs.social = clampf(needs.social, 0.0, self.max_need_value); needs_changed = true
	if needs.has("rest"):
		needs.rest -= self.rest_need_decay_rate_per_day 
		needs.rest = clampf(needs.rest, 0.0, self.max_need_value); needs_changed = true
	if needs_changed: update_happiness()

func update_happiness():
	var total_needs_score = 0.0; var num_needs = 0
	for need_type in needs.keys(): total_needs_score += needs[need_type]; num_needs += 1
	if num_needs > 0: happiness = (total_needs_score / num_needs)
	else: happiness = 50.0 
	happiness = clampf(happiness, 0.0, 100.0) 

func fulfill_need(need_type: String, amount: float):
	if needs.has(need_type):
		needs[need_type] += amount
		needs[need_type] = clampf(needs[need_type], 0.0, self.max_need_value) 
		print_debug("Fulfilled " + need_type + " by " + str(amount) + ". New value: " + str(needs[need_type]))
		update_happiness()

# --- Academic Progress Logic ---
func update_academic_progress():
	if is_graduated or not is_instance_valid(university_data_ref): return 
	var courses_to_remove_from_current: Array[String] = [] 
	for course_id in current_courses:
		if not university_data_ref.COURSES.has(course_id): continue
		var course_data = university_data_ref.COURSES[course_id]
		var progress_needed = course_data.get("progress_needed", 100) 
		if not course_progress.has(course_id): course_progress[course_id] = 0
		course_progress[course_id] += study_rate_per_update
		if course_progress[course_id] >= progress_needed:
			print_debug("COMPLETED course: " + course_data.get("name", course_id))
			completed_courses.append(course_id)
			courses_to_remove_from_current.append(course_id) 
			total_credits_earned += course_data.get("credits", 0) 
			course_progress.erase(course_id) 
	for course_id in courses_to_remove_from_current: current_courses.erase(course_id)
	check_for_graduation()
func check_for_graduation():
	if is_graduated or not is_instance_valid(university_data_ref) or enrolled_program_id == "": return
	if total_credits_earned >= min_credits_for_graduation:
		var all_required_courses_completed = true
		var required_program_courses = university_data_ref.get_required_courses_for_program(enrolled_program_id)
		for req_course_id in required_program_courses:
			if not completed_courses.has(req_course_id): all_required_courses_completed = false; break 
		if all_required_courses_completed:
			is_graduated = true
			print_debug("CONGRATULATIONS! " + student_name + " has GRADUATED from " + enrolled_program_name)
			current_courses.clear(); 
			if is_instance_valid(path_update_timer): path_update_timer.stop()
			velocity = Vector3.ZERO; set_physics_process(false) 
			update_visual_state() 

# --- Info Summary for UI ---
func get_info_summary() -> Dictionary:
	var current_course_names_list: Array[String] = []
	if is_instance_valid(university_data_ref):
		for course_id in current_courses:
			if university_data_ref.COURSES.has(course_id):
				current_course_names_list.append(university_data_ref.COURSES[course_id].get("name", course_id))
			else: current_course_names_list.append(course_id + " (Unknown)")
	var student_status = "Enrolled"; if is_graduated: student_status = "Graduated!"
	return {
		"name": student_name, "program_id": enrolled_program_id, "program_name": enrolled_program_name,
		"status": student_status, "credits_earned": total_credits_earned,
		"credits_needed_for_program": min_credits_for_graduation,
		"current_courses_list": current_course_names_list, "courses_count": current_courses.size(),
		"happiness": happiness, "needs": needs.duplicate(true) 
	}

# --- Movement and Navigation Logic ---
func _physics_process(delta: float):
	if is_graduated: velocity = Vector3.ZERO; return
	if current_state == StudentState.USING_FACILITY or current_state == StudentState.IDLE_PAUSED: 
		velocity = Vector3.ZERO; move_and_slide(); return
	
	var should_move = true 
	var no_move_reason = ""

	if not is_instance_valid(navigation_agent):
		should_move = false; no_move_reason = "NavigationAgent invalid"
	elif not has_target: 
		should_move = false; no_move_reason = "No target (has_target is false)"
	elif navigation_agent.is_navigation_finished(): 
		should_move = false; no_move_reason = "Navigation FINISHED. Target was: " + str(navigation_agent.target_position)
		if has_target: _on_target_reached() 
	elif not navigation_agent.is_target_reachable(): 
		var current_path = navigation_agent.get_current_navigation_path()
		if current_path.is_empty() and has_target: 
			should_move = false; no_move_reason = "Target NOT REACHABLE and current path is EMPTY: " + str(navigation_agent.target_position)
			print_debug("_physics_process: " + no_move_reason)
			has_target = false 
			call_deferred("set_new_behavior_or_target")
	
	if should_move and has_target: 
		var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
		if next_path_pos == Vector3.ZERO and global_position.length_squared() > 0.1: pass
		else:
			var direction = (next_path_pos - global_position).normalized() 
			velocity = direction * move_speed 
			if velocity.length_squared() > 0.01: 
				look_at(next_path_pos, Vector3.UP)
	else: velocity = Vector3.ZERO

	move_and_slide()

	if current_state == StudentState.MOVING_TO_NEED_LOCATION and \
	   is_instance_valid(current_target_building_node) and \
	   is_instance_valid(building_manager_ref) and \
	   has_target: 
		var building_grid_coord = current_target_building_node.get_meta("grid_coord")
		var all_occupied_cells = building_manager_ref.get_all_occupied_cells_data()
		if all_occupied_cells.has(building_grid_coord):
			var cell_data = all_occupied_cells[building_grid_coord]
			if cell_data.has("module_key"):
				var module_key = cell_data.module_key
				if building_manager_ref.module_data.has(module_key):
					var module_info = building_manager_ref.module_data[module_key]
					var satisfaction_radius = module_info.get("provides_need_satisfaction_radius", TARGET_REACHED_THRESHOLD) 
					if global_position.distance_to(current_target_building_node.global_position) < satisfaction_radius:
						_on_reached_need_location()


func set_new_target_position(target_pos: Vector3): 
	if is_graduated: return 
	if not is_instance_valid(navigation_agent): 
		printerr(student_name + ": NavigationAgent invalid in set_new_target_position.")
		has_target = false 
		return
	navigation_agent.target_position = target_pos
	has_target = true 


func set_random_wander_target():
	if is_graduated: return 
	if not main_navigation_region: has_target = false; return
	var nav_map_rid = main_navigation_region.get_navigation_map()
	if not NavigationServer3D.map_is_active(nav_map_rid): has_target = false; return
	var query_point: Vector3; var closest_nav_point: Vector3 = Vector3.INF 
	for _i in range(10): 
		var random_x = randf_range(-40.0, 40.0); var random_z = randf_range(-40.0, 40.0)
		query_point = Vector3(random_x, effective_ground_y_ref, random_z)
		var test_point = NavigationServer3D.map_get_closest_point(nav_map_rid, query_point)
		if test_point == Vector3.ZERO and query_point.length_squared() > 1.0: continue
		else: closest_nav_point = test_point; break 
	if closest_nav_point == Vector3.INF or (closest_nav_point == Vector3.ZERO and query_point.length_squared() > 1.0) : 
		has_target = false; 
		print_debug("Could not find random wander target.")
		return
	set_new_target_position(closest_nav_point) 
	current_state = StudentState.IDLE_WANDERING 


func _on_path_changed():
	if is_graduated or current_state == StudentState.USING_FACILITY or current_state == StudentState.IDLE_PAUSED: return
	if not is_instance_valid(navigation_agent): return

	var new_path = navigation_agent.get_current_navigation_path()
	if new_path.is_empty():
		if has_target: 
			print_debug("PATH_CHANGED: Path became invalid or target " + str(navigation_agent.target_position) + " unreachable. Clearing has_target.")
			has_target = false 
			if not (current_state == StudentState.MOVING_TO_NEED_LOCATION and is_instance_valid(current_target_building_node)):
				print_debug("  PATH_CHANGED: Not committed to a need target, or target invalid. Re-evaluating behavior.")
				call_deferred("set_new_behavior_or_target") 
	elif not new_path.is_empty():
		has_target = true 


func _on_target_reached(): 
	if is_graduated or current_state == StudentState.USING_FACILITY or current_state == StudentState.IDLE_PAUSED: return
	has_target = false 
	
	if current_state == StudentState.MOVING_TO_NEED_LOCATION: 
		_on_reached_need_location()
	elif current_state == StudentState.IDLE_WANDERING:
		print_debug("TARGET_REACHED: Wander target reached. Pausing.")
		current_state = StudentState.IDLE_PAUSED
		update_visual_state()
		wander_pause_timer.start() 
	else: 
		print_debug("TARGET_REACHED: Reached target in unexpected state: " + StudentState.keys()[current_state] + ". Re-evaluating.")
		set_new_behavior_or_target() 

func _on_wander_pause_timer_timeout():
	print_debug("WANDER_PAUSE_TIMEOUT: Pause finished. Current state was IDLE_PAUSED.")
	current_state = StudentState.IDLE_WANDERING 
	print_debug("WANDER_PAUSE_TIMEOUT: State changed to IDLE_WANDERING. Re-evaluating behavior.")
	set_new_behavior_or_target()


func _on_reached_need_location():
	if not is_instance_valid(current_target_building_node) or current_need_to_fulfill == "":
		print_debug("REACHED_NEED_LOCATION: Target building/need unclear. Reverting to wander.")
		set_new_behavior_or_target(); return
	
	current_target_facility_script = current_target_building_node.get_node_or_null("FacilityData") as BlockFacility
	if is_instance_valid(current_target_facility_script):
		if current_target_facility_script.add_user():
			print_debug("REACHED_NEED_LOCATION: Successfully occupied slot at " + current_target_building_node.name + " for need '" + current_need_to_fulfill + "'. Starting interaction.")
			current_state = StudentState.USING_FACILITY
			velocity = Vector3.ZERO 
			if is_instance_valid(student_mesh): student_mesh.visible = false # Hide student
			interaction_timer.start() 
			update_visual_state() 
		else:
			print_debug("REACHED_NEED_LOCATION: Facility " + current_target_building_node.name + " is full for need '" + current_need_to_fulfill + "'. Re-evaluating.")
			current_target_building_node = null 
			current_target_facility_script = null
			current_state = StudentState.SEEKING_NEED_LOCATION 
			set_new_behavior_or_target() 
	else:
		printerr("REACHED_NEED_LOCATION: Target building " + current_target_building_node.name + " does not have a FacilityData script! Reverting.")
		set_new_behavior_or_target()


func _on_interaction_timer_timeout():
	print_debug("INTERACTION_TIMEOUT: Interaction finished.")
	if is_instance_valid(student_mesh): student_mesh.visible = true # Make student reappear

	if is_instance_valid(current_target_facility_script) and current_need_to_fulfill != "":
		var amount = current_target_facility_script.get_fulfillment_amount(current_need_to_fulfill)
		fulfill_need(current_need_to_fulfill, amount)
		current_target_facility_script.remove_user() 
	elif not is_instance_valid(current_target_facility_script):
		printerr("  INTERACTION_TIMEOUT: current_target_facility_script was null!")
	elif current_need_to_fulfill == "":
		printerr("  INTERACTION_TIMEOUT: current_need_to_fulfill was empty!")


	current_target_building_node = null
	current_target_facility_script = null
	current_need_to_fulfill = ""
	current_state = StudentState.IDLE_WANDERING 
	print_debug("INTERACTION_TIMEOUT: State changed to IDLE_WANDERING. Re-evaluating behavior.")
	set_new_behavior_or_target() 


func _on_path_update_timer_timeout():
	if is_graduated or current_state == StudentState.USING_FACILITY or current_state == StudentState.IDLE_PAUSED: return
	if not main_navigation_region: return

	if current_state == StudentState.MOVING_TO_NEED_LOCATION:
		if is_instance_valid(current_target_building_node) and is_instance_valid(navigation_agent):
			navigation_agent.target_position = current_target_building_node.global_position 
		else:
			print_debug("Path update timer: Committed target invalid while MOVING_TO_NEED_LOCATION. Re-evaluating.")
			current_target_building_node = null
			current_target_facility_script = null
			current_need_to_fulfill = ""
			has_target = false 
			set_new_behavior_or_target()
	elif not has_target: 
		set_new_behavior_or_target()


# --- Visual State Update ---
func update_visual_state():
	if not is_instance_valid(student_mesh): return
	
	if current_state == StudentState.USING_FACILITY:
		if student_mesh.visible: student_mesh.visible = false 
		return 
	elif not student_mesh.visible: 
		student_mesh.visible = true

	var target_color = default_albedo_color 
	if is_graduated: target_color = GRADUATED_COLOR 
	else:
		match current_state:
			# USING_FACILITY handled by visibility above
			StudentState.IDLE_PAUSED: target_color = Color.GRAY 
			StudentState.SEEKING_NEED_LOCATION, StudentState.MOVING_TO_NEED_LOCATION:
				if current_need_to_fulfill == "study": target_color = SEEKING_STUDY_COLOR
				elif current_need_to_fulfill == "social": target_color = SEEKING_SOCIAL_COLOR
				elif current_need_to_fulfill == "rest": target_color = SEEKING_REST_COLOR
				else: target_color = GENERIC_SEEKING_COLOR 
			StudentState.IDLE_WANDERING: target_color = default_albedo_color
	
	var current_material_override = student_mesh.material_override
	if not is_instance_valid(current_material_override):
		var base_material = student_mesh.get_active_material(0) 
		var new_mat_override = StandardMaterial3D.new() 
		if base_material is StandardMaterial3D: new_mat_override.albedo_color = (base_material as StandardMaterial3D).albedo_color 
		else: new_mat_override.albedo_color = default_albedo_color 
		student_mesh.material_override = new_mat_override
		current_material_override = new_mat_override
	if current_material_override is StandardMaterial3D:
		if (current_material_override as StandardMaterial3D).albedo_color != target_color:
			(current_material_override as StandardMaterial3D).albedo_color = target_color


func print_debug(message):
	var name_prefix = student_name if student_name != "Unnamed Student" else "Student@" + str(self.get_instance_id())
	if is_instance_valid(self): print("[" + name_prefix + "]: " + str(message))
	else: print("[Student (invalid instance)]: " + str(message))
