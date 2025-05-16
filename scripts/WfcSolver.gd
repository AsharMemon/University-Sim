# WfcSolver.gd
class_name WfcSolver
extends RefCounted

var module_data: Dictionary = {} 
var all_possible_initial_states: Array = [] # Will store all {module_key, rotation} combinations

const DIRECTIONS = {
	Vector3i.FORWARD: {"face_a": "Front", "face_b": "Back",   "opposite": Vector3i.BACK},
	Vector3i.BACK:    {"face_a": "Back",  "face_b": "Front",  "opposite": Vector3i.FORWARD},
	Vector3i.UP:      {"face_a": "Top",   "face_b": "Bottom", "opposite": Vector3i.DOWN},
	Vector3i.DOWN:    {"face_a": "Bottom","face_b": "Top",    "opposite": Vector3i.UP},
	Vector3i.RIGHT:   {"face_a": "Right", "face_b": "Left",   "opposite": Vector3i.LEFT},
	Vector3i.LEFT:    {"face_a": "Left",  "face_b": "Right",  "opposite": Vector3i.RIGHT}
}

func initialize(_grid_dimensions_ignored: Vector3i, _module_data: Dictionary) -> bool:
	print("DEBUG: WfcSolver initialize (for interactive mode)")
	module_data = _module_data 
	all_possible_initial_states.clear()
	
	for module_key in module_data:
		var m_data = module_data[module_key]
		if not m_data.has("rotations"): 
			print("DEBUG Init Warning: Module ", module_key, " missing 'rotations' data.")
			continue
		# Ensure building_type exists, default to "generic" if not specified
		if not m_data.has("building_type"):
			print("DEBUG Init Warning: Module ", module_key, " missing 'building_type', defaulting to 'generic'.")
			m_data["building_type"] = "generic" # Add it if missing for safety

		for rotation_str in m_data["rotations"]:
			all_possible_initial_states.append({
				"module_key": module_key, 
				"rotation": int(rotation_str),
				"building_type": m_data.get("building_type", "generic") # Store type here
			})

	if all_possible_initial_states.is_empty():
		printerr("WFC Error: No possible initial states found in module data during init!")
		return false
	print("WFC Solver Initialized with ", all_possible_initial_states.size(), " total base states.")
	return true


# --- MODIFIED FUNCTION SIGNATURE AND LOGIC ---
func get_valid_states_for_coord(target_coord: Vector3i, 
								current_occupied_cells: Dictionary, 
								selected_building_type: String,
								source_building_type_for_expansion: String = "") -> Array: # source can be empty if not expansion
	
	print("DEBUG: WFC Getting valid states for target_coord: ", target_coord, 
		  " | Selected Type: ", selected_building_type, 
		  " | Source Type (if expanding): ", source_building_type_for_expansion)
		  
	if all_possible_initial_states.is_empty():
		printerr("WFC Error: Solver not initialized or no modules loaded for get_valid_states_for_coord.")
		return []

	var candidate_initial_states: Array = []
	# 1. Filter initial states by selected building type
	for state in all_possible_initial_states:
		var module_btype = state.get("building_type", "generic")
		# A module is a candidate if:
		# - It's "generic"
		# - OR its type matches the selected_building_type
		if module_btype == "generic" or module_btype == selected_building_type:
			candidate_initial_states.append(state.duplicate(true))
	
	if candidate_initial_states.is_empty():
		print("DEBUG: No initial states match selected building type '", selected_building_type, "' or 'generic'.")
		return []

	var potential_states_for_target: Array = candidate_initial_states
	
	# 2. Filter against each existing neighbor based on sockets AND building type compatibility
	for direction_from_target_to_neighbor in DIRECTIONS: 
		var actual_neighbor_coord = target_coord + direction_from_target_to_neighbor
		
		if current_occupied_cells.has(actual_neighbor_coord): 
			var existing_neighbor_full_data: Dictionary = current_occupied_cells[actual_neighbor_coord]
			var existing_neighbor_state = {
				"module_key": existing_neighbor_full_data.get("module_key"),
				"rotation": existing_neighbor_full_data.get("rotation"),
				"building_type": existing_neighbor_full_data.get("building_type", "generic")
			}
			
			var states_still_valid_after_this_neighbor: Array = []
			
			for candidate_target_state in potential_states_for_target:
				var candidate_target_btype = candidate_target_state.get("building_type", "generic")
				var existing_neighbor_btype = existing_neighbor_state.get("building_type", "generic")

				# Building Type Compatibility Check with Neighbor:
				# - Generic can connect to anything.
				# - Specific type can connect to generic.
				# - Specific type can connect to same specific type.
				var types_compatible = false
				if candidate_target_btype == "generic" or existing_neighbor_btype == "generic" or \
				   candidate_target_btype == existing_neighbor_btype:
					types_compatible = true
				
				# If expanding, the new piece must also be compatible with the overall selected building type
				# This is implicitly handled by initial filtering, but ensure new piece aligns with desired structure.
				# If candidate_target_btype != "generic" and candidate_target_btype != selected_building_type:
				# types_compatible = false # Stricter: new piece must be generic or the selected type

				if types_compatible and check_compatibility(candidate_target_state, direction_from_target_to_neighbor, existing_neighbor_state):
					states_still_valid_after_this_neighbor.append(candidate_target_state)
			
			potential_states_for_target = states_still_valid_after_this_neighbor 
			if potential_states_for_target.is_empty():
				break 
		
		else: # Neighbor cell is empty/boundary/AIR
			var states_still_valid_after_air_check: Array = []
			for candidate_target_state in potential_states_for_target:
				var face_of_candidate = DIRECTIONS[direction_from_target_to_neighbor]["face_a"]
				var socket_of_candidate = get_socket_id(candidate_target_state.module_key, candidate_target_state.rotation, face_of_candidate)
				
				var can_face_air_boundary = true 
				if socket_of_candidate == "BOTTOM_STONE":
					if target_coord.y > 0 and direction_from_target_to_neighbor == Vector3i.DOWN:
						can_face_air_boundary = false
				# Add more rules here if TOP_STONE_FLAT shouldn't face up into air, etc.
				# For example, if it's not the max height of the current building type.

				if can_face_air_boundary:
					states_still_valid_after_air_check.append(candidate_target_state)
			
			potential_states_for_target = states_still_valid_after_air_check
			if potential_states_for_target.is_empty():
				break

	print("DEBUG: WFC Found ", potential_states_for_target.size(), " final valid states for ", target_coord, " of type '", selected_building_type, "'")
	return potential_states_for_target


func check_compatibility(state_a: Dictionary, direction_a_to_b: Vector3i, state_b: Dictionary, debug_print: bool = false) -> bool:
	if not state_a or not state_b: 
		if debug_print: print("        CheckCompat -> FAIL (Invalid State Input A or B is null)")
		return false

	var module_key_a = state_a.get("module_key", null)
	var rotation_a = state_a.get("rotation", -1) 
	var module_key_b = state_b.get("module_key", null)
	var rotation_b = state_b.get("rotation", -1)
	
	if module_key_a == null or rotation_a == -1 or module_key_b == null or rotation_b == -1:
		if debug_print: print("        CheckCompat -> FAIL (Invalid state format A=", state_a, " B=", state_b, ")")
		return false

	if not DIRECTIONS.has(direction_a_to_b): 
		if debug_print: print("        CheckCompat -> FAIL (Invalid direction ", direction_a_to_b, ")")
		return false 
		
	var face_a = DIRECTIONS[direction_a_to_b]["face_a"] 
	var face_b = DIRECTIONS[direction_a_to_b]["face_b"] 

	var socket_a = get_socket_id(module_key_a, rotation_a, face_a)
	var socket_b = get_socket_id(module_key_b, rotation_b, face_b)

	var debug_prefix_str = "" 
	if debug_print: 
		debug_prefix_str = "        CheckCompat: A=" + str(module_key_a) + ":" + str(rotation_a) + ":" + face_a + "(" + str(socket_a) + ") vs B=" + str(module_key_b) + ":" + str(rotation_b) + ":" + face_b + "(" + str(socket_b) + ")"

	if socket_a == null or socket_b == null: 
		if debug_print: print(debug_prefix_str + " -> FAIL (Null Socket)")
		return false 

	# Rule 1: Direct Match (Sides Only)
	if socket_a == socket_b and (face_a == "Left" or face_a == "Right" or face_a == "Front" or face_a == "Back"):
		if debug_print: print(debug_prefix_str + " -> OK (Rule 1: Side Match)")
		return true
		
	# Rule 2: Vertical Connections (Flat Top/Bottom)
	if (socket_a == "TOP_STONE_FLAT" and socket_b == "BOTTOM_STONE") or \
	   (socket_a == "BOTTOM_STONE" and socket_b == "TOP_STONE_FLAT"):
		if debug_print: print(debug_prefix_str + " -> OK (Rule 2: Vertical Match)")
		return true
		
	# Rule 3a: Special Tops can't have things placed ON their top face 
	if face_a == "Top" and (socket_a == "TOP_BATTLEMENT" or socket_a == "TOP_SLOPE"):
		if debug_print: print(debug_prefix_str + " -> FAIL (Rule 3a: A is Special Top, B cannot connect to its Top face)")
		return false 

	# Rule 4: Corner connections 
	if (socket_a == "CORNER_SHARP_A" or socket_a == "CORNER_SHARP_B" or socket_a == "CORNER_ROUND") and socket_b == "SIDE_STONE":
		if debug_print: print(debug_prefix_str + " -> OK (Rule 4a: Corner A to Side B)")
		return true
	if socket_a == "SIDE_STONE" and (socket_b == "CORNER_SHARP_A" or socket_b == "CORNER_SHARP_B" or socket_b == "CORNER_ROUND"):
		if debug_print: print(debug_prefix_str + " -> OK (Rule 4b: Side A to Corner B)")
		return true
		
	# Rule 5: Window connections 
	if (socket_a == "SIDE_WINDOW") and socket_b == "SIDE_STONE":
		if debug_print: print(debug_prefix_str + " -> OK (Rule 5a: Window A to Side B)")
		return true
	if socket_a == "SIDE_STONE" and (socket_b == "SIDE_WINDOW"):
		if debug_print: print(debug_prefix_str + " -> OK (Rule 5b: Side A to Window B)")
		return true

	# Default: No match
	if debug_print: print(debug_prefix_str + " -> FAIL (No Rule Match)")
	return false


func get_socket_id(module_key: String, rotation: int, face_name: String) -> Variant: 
	if not module_data.has(module_key): 
		printerr("get_socket_id Error: Module key '", module_key, "' not found in module_data.") 
		return null
	var m_data = module_data[module_key]
	if not m_data.has("rotations"): 
		printerr("get_socket_id Error: Module '", module_key, "' has no 'rotations' dictionary.") 
		return null 

	var rotation_str = str(rotation)
	var rot_data = null

	if m_data["rotations"].has(rotation_str):
		rot_data = m_data["rotations"][rotation_str]
	elif m_data["rotations"].has("0"): 
		rot_data = m_data["rotations"]["0"]
	else: 
		printerr("get_socket_id Error: No rotation data found for ", module_key, " (checked ", rotation, " and 0).") 
		return null 

	if not rot_data.has(face_name): 
		printerr("get_socket_id Error: Face '", face_name, "' not defined for ", module_key, " Rot '", rotation_str, "' (or fallback '0'). Data: ", rot_data) 
		return null 

	var socket_value = rot_data[face_name]
	return socket_value
