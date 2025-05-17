# ProgramEntryRow.gd
# Represents a single program in the left-hand list of ProgramManagementUI.
extends PanelContainer # Or Button, depending on your tscn root choice
class_name ProgramEntryRow # <--- ADD THIS

signal unlock_requested(program_id: String)
signal program_selected(program_id: String) # Emitted when an unlocked program is clicked/selected

# Adjust paths based on your ProgramEntryRow.tscn structure
@onready var program_name_status_label: Label = get_node_or_null("ListItemHBox/ProgramNameStatusLabel")
@onready var unlock_button: Button = get_node_or_null("ListItemHBox/UnlockButton")
# If using a separate select button:
# @onready var select_button: Button = get_node_or_null("ListItemHBox/SelectButton")


var current_program_id: String = ""
var current_program_name: String = ""
var current_program_status: String = "" # "locked" or "unlocked"
var academic_manager_ref: AcademicManager # To get unlock_cost

# --- Initialization ---
func _ready():
	if not is_instance_valid(program_name_status_label):
		printerr("ProgramEntryRow: ProgramNameStatusLabel not found!")
	if not is_instance_valid(unlock_button):
		printerr("ProgramEntryRow: UnlockButton not found!")
	else:
		unlock_button.pressed.connect(_on_unlock_button_pressed)


	# --- NEW CHECK if you added class_name ProgramEntryRow ---
	if get_script() == ProgramEntryRow: # More robust if class_name is defined
		if not is_connected("gui_input", Callable(self, "_on_panel_gui_input")):
			gui_input.connect(Callable(self, "_on_panel_gui_input"))
			print("[%s] Connected panel gui_input signal." % self.name)
		else:
			print("[%s] Panel gui_input signal already connected." % self.name)
	else:
		var script_resource_path = ""
		if get_script() and get_script().resource_path: # Check if get_script() is not null
			script_resource_path = get_script().resource_path
		printerr("[%s] Script on this node is NOT ProgramEntryRow (or path mismatch). Path is '%s'. Panel click won't work." % [self.name, script_resource_path])


# Called by ProgramManagementUI
func setup(prog_id: String, prog_name: String, prog_status: String, acad_manager: AcademicManager):
	current_program_id = prog_id
	current_program_name = prog_name
	current_program_status = prog_status
	academic_manager_ref = acad_manager

	var display_text = "%s (%s)" % [current_program_name, current_program_status.capitalize()]
	if is_instance_valid(program_name_status_label):
		program_name_status_label.text = display_text
	
	_update_ui_elements()

func _update_ui_elements():
	if is_instance_valid(unlock_button):
		if current_program_status == "locked":
			unlock_button.visible = true
			unlock_button.disabled = false
			# Display cost on unlock button if academic_manager_ref and university_data are valid
			if is_instance_valid(academic_manager_ref) and is_instance_valid(academic_manager_ref.university_data):
				var prog_details = academic_manager_ref.university_data.get_program_details(current_program_id)
				var cost = prog_details.get("unlock_cost", 0)
				if cost > 0:
					unlock_button.text = "Unlock ($%s)" % cost
				else:
					unlock_button.text = "Unlock"
			else:
				unlock_button.text = "Unlock"
		else: # "unlocked" or other
			unlock_button.visible = false
			unlock_button.disabled = true
	
	# Modulate self if selected (ProgramManagementUI will call a method like set_selected)
	# For now, just ensure button states are correct.
	if current_program_status == "unlocked":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW


func _on_unlock_button_pressed():
	if current_program_id.is_empty() or current_program_status != "locked":
		return
	emit_signal("unlock_requested", current_program_id)

# In ProgramEntryRow.gd

func _on_panel_gui_input(event: InputEvent):
	# Existing print for all gui_input events:
	print("[%s] _on_panel_gui_input triggered. Program: '%s', Status: %s. Event type: %s, Event class: %s" % [self.name, current_program_name, current_program_status, event.as_text(), event.get_class()])

	if current_program_status == "unlocked":
		print("[%s] Status is UNLOCKED. Checking event..." % self.name) # Confirm status check
		if event is InputEventMouseButton:
			var mb_event := event as InputEventMouseButton
			print("[%s] MouseButton event detected. Button: %s, Pressed: %s, Released: %s, Doubleclick: %s" % [self.name, mb_event.button_index, mb_event.is_pressed(), mb_event.is_released(), mb_event.is_double_click()])
			if mb_event.button_index == MOUSE_BUTTON_LEFT and mb_event.is_pressed():
				print("[%s] CORRECT CLICK! Panel clicked for program selection. Program ID: %s. Emitting 'program_selected'." % [self.name, current_program_id])
				emit_signal("program_selected", current_program_id)
				get_viewport().set_input_as_handled() # Try handling the event
			elif mb_event.button_index == MOUSE_BUTTON_LEFT and mb_event.is_released():
				print("[%s] MouseButton LEFT RELEASED event." % self.name) # Check if release is seen
		elif event is InputEventScreenTouch: # For touch devices
			var touch_event := event as InputEventScreenTouch
			print("[%s] ScreenTouch event detected. Pressed: %s" % [self.name, touch_event.is_pressed()])
			if touch_event.is_pressed(): # is_pressed() equivalent for touch
				print("[%s] CORRECT TOUCH! Panel touched for program selection. Program ID: %s. Emitting 'program_selected'." % [self.name, current_program_id])
				emit_signal("program_selected", current_program_id)
				get_viewport().set_input_as_handled() # Try handling the event
	else:
		if event is InputEventMouseButton and (event as InputEventMouseButton).is_pressed():
			print("[%s] Panel clicked, but status is '%s', not 'unlocked'." % [self.name, current_program_status])

# Called by ProgramManagementUI to visually indicate selection
func set_selected(is_selected: bool):
	if is_selected:
		# Example: Change background color using a StyleBoxFlat
		var style_box = self.get_theme_stylebox("panel", "PanelContainer") # Get current or default
		if style_box is StyleBoxFlat:
			var new_style_box = style_box.duplicate() as StyleBoxFlat
			new_style_box.bg_color = Color.DARK_CYAN # Or your selection color
			self.add_theme_stylebox_override("panel", new_style_box)
		else: # Fallback or create a new one
			var new_style_box = StyleBoxFlat.new()
			new_style_box.bg_color = Color.DARK_CYAN
			new_style_box.border_width_bottom = 2
			new_style_box.border_color = Color.LIGHT_BLUE
			self.add_theme_stylebox_override("panel", new_style_box)
	else:
		# Revert to default style
		self.remove_theme_stylebox_override("panel")
