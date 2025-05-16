# ProgramEntryRow.gd
# Script for a single row in the program management list.
extends HBoxContainer

# --- Signals ---
# Emitted when the unlock button for this specific program row is pressed.
signal unlock_requested(program_id: String)

# --- Node References ---
@onready var info_label: Label = get_node_or_null("InfoLabel")
@onready var unlock_button: Button = get_node_or_null("UnlockButton")

# --- State ---
var current_program_id: String = ""

# --- Initialization ---
func _ready():
	if not is_instance_valid(info_label):
		printerr("ProgramEntryRow: InfoLabel node not found!")
	if not is_instance_valid(unlock_button):
		printerr("ProgramEntryRow: UnlockButton node not found!")
	else:
		unlock_button.pressed.connect(_on_unlock_button_pressed)

# --- Public Functions ---
# Call this to set up the row with specific program data.
func setup(program_id: String, program_name: String, program_status: String):
	current_program_id = program_id

	if is_instance_valid(info_label):
		info_label.text = "%s: %s" % [program_name, program_status.capitalize()]
	
	if is_instance_valid(unlock_button):
		if program_status == "locked":
			unlock_button.visible = true
			unlock_button.disabled = false # Ensure it's enabled
		else: # "unlocked" or other statuses
			unlock_button.visible = false 
			# Alternatively, you could change button text to "View" or disable it
			# unlock_button.text = "Unlocked"
			# unlock_button.disabled = true

# --- Signal Handlers ---
func _on_unlock_button_pressed():
	if current_program_id.is_empty():
		printerr("ProgramEntryRow: Unlock button pressed, but no program_id is set for this row.")
		return
	
	print("ProgramEntryRow: Unlock requested for program: ", current_program_id)
	emit_signal("unlock_requested", current_program_id)
