# BlockFacility.gd
# This script is attached to individual building blocks that provide capacity
# for students (e.g., a dorm bed, a classroom seat).
# It manages its own capacity and current user count.
# The BuildingManager will read this data to update a central label for the building cluster.
class_name BlockFacility
extends Node 

var max_capacity: int = 0
var current_users: int = 0
var fulfills_needs_data: Dictionary = {} 
var building_block_type: String = "generic" 

# Signal emitted when the user count changes.
# BuildingManager can connect to this if it needs to update the cluster label immediately.
signal user_count_changed_on_block(facility_script_instance, new_user_count, max_cap)


# Called by BuildingManager when the block is placed and this script is attached.
# No longer takes a label_node_ref.
func setup_facility(m_capacity: int, needs_data: Dictionary, b_block_type: String):
	max_capacity = m_capacity
	fulfills_needs_data = needs_data
	building_block_type = b_block_type
	current_users = 0
	# print_debug("Facility component setup. Capacity: " + str(max_capacity))


func can_accommodate() -> bool:
	return current_users < max_capacity

func add_user() -> bool:
	if can_accommodate():
		current_users += 1
		user_count_changed_on_block.emit(self, current_users, max_capacity) 
		# print_debug("User added. Current users: " + str(current_users) + "/" + str(max_capacity))
		return true
	# print_debug("Cannot add user, at max capacity.")
	return false

func remove_user():
	current_users = maxi(0, current_users - 1) 
	user_count_changed_on_block.emit(self, current_users, max_capacity) 
	# print_debug("User removed. Current users: " + str(current_users) + "/" + str(max_capacity))


func get_fulfillment_amount(need_type: String) -> float:
	return fulfills_needs_data.get(need_type, 0.0)

func get_building_block_type() -> String: return building_block_type
func get_current_users() -> int: return current_users
func get_max_capacity() -> int: return max_capacity

func get_parent_name() -> String:
	if is_instance_valid(get_parent()): return get_parent().name
	return "UnknownParent"

func print_debug(message: String): # Added type hint for consistency
	print("[BlockFacility on ", get_parent_name(), "]: ", message)
