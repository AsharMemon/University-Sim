# ProgramManagementUI.gd
# Script for the panel that displays university programs and allows unlocking them.
# Uses a separate scene (ProgramEntryRow.tscn) for each program entry.
extends PanelContainer

# --- Node References ---
@export var academic_manager: AcademicManager 

@onready var program_list_vbox: VBoxContainer = get_node_or_null("VBoxContainer/ProgramListVBox") # Adjust if your VBox is named differently or nested deeper

# --- Scene Preloads ---
const ProgramEntryRowScene: PackedScene = preload("res://scenes/ProgramEntryRow.tscn") # ADJUST PATH AS NEEDED

# --- Initialization ---
func _ready():
	if not is_instance_valid(program_list_vbox):
		printerr("ProgramManagementUI: ProgramListVBox node not found! UI will not populate.")
		return

	if not is_instance_valid(academic_manager):
		printerr("ProgramManagementUI: AcademicManager node not assigned or found! UI will not function correctly.")
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager") # Adjust path
		if not is_instance_valid(academic_manager):
			printerr("ProgramManagementUI: CRITICAL - AcademicManager still not found after fallback.")
			return
			
	if not ProgramEntryRowScene:
		printerr("ProgramManagementUI: CRITICAL - ProgramEntryRow.tscn not preloaded or path is incorrect!")
		return

	# Connect to signals from AcademicManager to refresh UI when states change
	if not academic_manager.is_connected("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked")):
		var err = academic_manager.connect("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked"))
		if err != OK:
			printerr("ProgramManagementUI: Failed to connect to program_unlocked signal. Error: ", err)
	# Consider connecting to other signals if needed, e.g., if programs can be locked again.

	# Initial population of the UI
	refresh_program_list()


# --- UI Population and Refresh ---
func refresh_program_list():
	if not is_instance_valid(program_list_vbox) or \
	   not is_instance_valid(academic_manager) or \
	   not is_instance_valid(academic_manager.university_data) or \
	   not ProgramEntryRowScene:
		printerr("ProgramManagementUI: Cannot refresh, critical component missing.")
		return

	# Clear existing entries
	for child in program_list_vbox.get_children():
		child.queue_free()

	var all_programs_definitions = academic_manager.university_data.PROGRAMS
	var current_program_states = academic_manager.get_all_program_states()

	if all_programs_definitions.is_empty():
		var no_programs_label = Label.new()
		no_programs_label.text = "No university programs defined yet."
		program_list_vbox.add_child(no_programs_label)
		return

	for program_id in all_programs_definitions:
		var program_def = all_programs_definitions[program_id]
		var program_name = program_def.get("name", "Unknown Program")
		var program_state = current_program_states.get(program_id, "locked")

		var program_row_instance = ProgramEntryRowScene.instantiate() as HBoxContainer 
		if not is_instance_valid(program_row_instance):
			printerr("ProgramManagementUI: Failed to instantiate ProgramEntryRowScene for ", program_id)
			continue
			
		program_list_vbox.add_child(program_row_instance)
		
		# Call setup on the row's script
		if program_row_instance.has_method("setup"):
			program_row_instance.setup(program_id, program_name, program_state)
		else:
			printerr("ProgramManagementUI: Instantiated ProgramEntryRow for '", program_id, "' does not have a setup() method.")
			continue # Skip connecting signal if setup failed

		# Connect to the row's unlock_requested signal
		if not program_row_instance.is_connected("unlock_requested", Callable(self, "_on_program_row_unlock_requested")):
			var err = program_row_instance.connect("unlock_requested", Callable(self, "_on_program_row_unlock_requested"))
			if err != OK:
				printerr("ProgramManagementUI: Failed to connect to unlock_requested signal from row for '", program_id, "'. Error: ", err)


# --- Signal Handlers ---
func _on_program_row_unlock_requested(program_id_from_row: String):
	if not is_instance_valid(academic_manager): return

	if program_id_from_row.is_empty():
		printerr("ProgramManagementUI: Received unlock request from row but no program_id provided.")
		return

	print_debug("ProgramManagementUI: Unlock request received from row for program '", program_id_from_row, "'.")
	# Here you might add logic for cost or prerequisites before calling unlock
	var success = academic_manager.unlock_program(program_id_from_row)
	if success:
		print_debug("ProgramManagementUI: Unlock successful for '", program_id_from_row, "'.")
		# The refresh_program_list will be called via the _on_academic_manager_program_unlocked signal
	else:
		print_debug("ProgramManagementUI: Unlock failed for '", program_id_from_row, "'.")
		# Optionally, display a message to the player (e.g., not enough funds)


func _on_academic_manager_program_unlocked(program_id: String):
	print_debug("ProgramManagementUI: Received program_unlocked signal from AcademicManager for '", program_id, "'. Refreshing UI.")
	refresh_program_list()

# --- Helper Functions ---
func print_debug(message_parts):
	var final_message = "[ProgramManagementUI]: "
	if typeof(message_parts) == TYPE_STRING:
		final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY or typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : Array = message_parts
		final_message += " ".join(temp_array)
	else:
		final_message += str(message_parts)
	print(final_message)
