# TimeSlotCell.gd
# Script for an individual cell in the timetable grid.
extends PanelContainer

# --- Node References ---
@export var content_label: Label
@export var instructor_name_label: Label # <<< NEW - Add this Label node in your .tscn
@onready var unschedule_button: Button = get_node_or_null("UnscheduleButton")

# --- Cell Data (set by TimetableGrid.gd) ---
var day: String = ""
var time_slot: String = ""
var classroom_id: String = ""
var academic_manager: AcademicManager = null
var professor_manager: ProfessorManager = null # <<< NEW
var current_offering_id_in_cell: String = ""

# --- Visual State ---
var is_valid_drop_target: bool = false
var default_stylebox: StyleBox
var drag_over_stylebox: StyleBoxFlat

const COLOR_DEFAULT_BG = Color(0.9, 0.9, 0.9, 0.1)
const COLOR_DRAG_OVER_VALID_BG = Color(0.6, 0.9, 0.6, 0.3)
const COLOR_SCHEDULED_BG = Color(0.7, 0.8, 1.0, 0.2)
const COLOR_FULL_BG = Color(0.95, 0.7, 0.7, 0.2)

const DETAILED_LOGGING_ENABLED: bool = false # Set to true for specific cell logs

# --- Initialization ---
func _ready():
	if not is_instance_valid(content_label):
		printerr("TimeSlotCell (%s): ContentLabel node not found!" % name)
	if not is_instance_valid(instructor_name_label): # NEW Check
		printerr("TimeSlotCell (%s): InstructorNameLabel node not found! Add it to TimeSlotCell.tscn." % name)
	if not is_instance_valid(unschedule_button):
		printerr("TimeSlotCell (%s): UnscheduleButton node not found!" % name)
	else:
		if not unschedule_button.is_connected("pressed", Callable(self, "_on_unschedule_button_pressed")):
			unschedule_button.pressed.connect(Callable(self, "_on_unschedule_button_pressed"))
		unschedule_button.visible = false

	var theme_panel_stylebox = get_theme_stylebox("panel")
	if theme_panel_stylebox:
		default_stylebox = theme_panel_stylebox.duplicate(true)
	else: # Fallback if no theme stylebox found
		default_stylebox = StyleBoxFlat.new()
		(default_stylebox as StyleBoxFlat).bg_color = COLOR_DEFAULT_BG
	
	drag_over_stylebox = StyleBoxFlat.new()
	drag_over_stylebox.bg_color = COLOR_DRAG_OVER_VALID_BG
	drag_over_stylebox.border_width_bottom = 1
	drag_over_stylebox.border_width_right = 1
	var border_ref_color = default_stylebox.get("border_color") if default_stylebox is StyleBoxFlat else Color.GRAY # More robust
	if border_ref_color is Color: drag_over_stylebox.border_color = border_ref_color
	
	mouse_filter = Control.MOUSE_FILTER_PASS

# --- Public Setup Function ---
# MODIFIED to accept ProfessorManager
func setup_cell(p_day: String, p_time_slot: String, p_classroom_id: String, p_academic_manager: AcademicManager, p_professor_manager: ProfessorManager):
	self.day = p_day
	self.time_slot = p_time_slot
	self.classroom_id = p_classroom_id
	self.academic_manager = p_academic_manager
	self.professor_manager = p_professor_manager # <<< STORE ProfessorManager

	self.name = "Cell_%s_%s_%s" % [p_classroom_id.right(3), day, time_slot] # More unique name
	
	set_meta("day", self.day)
	set_meta("time_slot", self.time_slot)
	set_meta("classroom_id", self.classroom_id)
	
	update_display({})

# --- Display Logic ---
# MODIFIED to display instructor name
func update_display(offering_details: Dictionary):
	if not is_instance_valid(content_label) or \
	   not is_instance_valid(unschedule_button) or \
	   not is_instance_valid(instructor_name_label): # Check new label
		if DETAILED_LOGGING_ENABLED: print_debug("A label is missing, cannot update display fully.")
		# Allow partial update if content_label exists
		if not is_instance_valid(content_label): return
	
	var current_style: StyleBoxFlat = default_stylebox.duplicate(true) if default_stylebox is StyleBoxFlat else StyleBoxFlat.new()
	if not default_stylebox is StyleBoxFlat: current_style.bg_color = COLOR_DEFAULT_BG # Ensure it has a base color

	current_offering_id_in_cell = ""
	instructor_name_label.text = "" # Clear instructor name by default

	if offering_details != null and not offering_details.is_empty():
		var course_name = offering_details.get("course_name", "N/A")
		var course_id = offering_details.get("course_id", "N/A")
		current_offering_id_in_cell = offering_details.get("offering_id", "")
		
		var enrolled_count = offering_details.get("enrolled_count", 0) # Prefer direct count if available
		if offering_details.has("enrolled_student_ids") and offering_details.enrolled_student_ids is Array:
			enrolled_count = offering_details.enrolled_student_ids.size()
			
		var max_cap = offering_details.get("max_capacity", 0)

		var is_start_slot = false
		if is_instance_valid(academic_manager) and not current_offering_id_in_cell.is_empty():
			var main_schedule_info = academic_manager.scheduled_class_details.get(current_offering_id_in_cell)
			if main_schedule_info and main_schedule_info.start_time_slot == self.time_slot:
				var pattern = main_schedule_info.get("pattern", "")
				if (pattern == "MWF" and (self.day in ["Mon", "Wed", "Fri"])) or \
				   (pattern == "TR" and (self.day in ["Tue", "Thu"])):
					is_start_slot = true
		
		var display_text = ""
		if is_start_slot:
			display_text = "%s (%s)\n%d/%d" % [course_name, course_id.right(5), enrolled_count, max_cap] # Shorten course_id if long
			unschedule_button.visible = true
		else:
			display_text = "(%s)\n%d/%d" % [course_id.right(5), enrolled_count, max_cap]
			unschedule_button.visible = false
		
		content_label.text = display_text
		
		# <<< NEW: Display Instructor Name >>>
		var instructor_id = offering_details.get("instructor_id", "")
		if not instructor_id.is_empty() and is_instance_valid(professor_manager):
			var prof: Professor = professor_manager.get_professor_by_id(instructor_id)
			if is_instance_valid(prof):
				# Displaying initials or a short form of the name: "LName, F."
				var name_parts = prof.professor_name.split(" ")
				if name_parts.size() > 1:
					instructor_name_label.text = name_parts[-1] + ", " + name_parts[0].left(1) + "."
				else:
					instructor_name_label.text = prof.professor_name # Full name if only one part
			else:
				instructor_name_label.text = "Prof. ID N/A" # Instructor ID was there but no prof found
		elif not instructor_id.is_empty():
			instructor_name_label.text = "Prof. System N/A" # ID was there but no prof manager
		else:
			instructor_name_label.text = "TBA" # To Be Announced / Unassigned
		
		# Set background color based on status
		if max_cap > 0 and enrolled_count >= max_cap:
			current_style.bg_color = COLOR_FULL_BG
		else:
			current_style.bg_color = COLOR_SCHEDULED_BG
	else:
		content_label.text = ""
		instructor_name_label.text = "" # Clear instructor if no offering
		unschedule_button.visible = false
		current_style.bg_color = COLOR_DEFAULT_BG
			
	add_theme_stylebox_override("panel", current_style)


# --- Drag Over Visual Feedback ---
func set_drag_over_feedback(can_drop: bool):
	if is_valid_drop_target == can_drop: return

	is_valid_drop_target = can_drop
	if is_valid_drop_target:
		add_theme_stylebox_override("panel", drag_over_stylebox)
	else:
		# Revert to normal display (which re-evaluates if a class is scheduled)
		var offering_id_currently_in_slot = ""
		if is_instance_valid(academic_manager) and not classroom_id.is_empty() and not day.is_empty() and not time_slot.is_empty():
			offering_id_currently_in_slot = academic_manager.classroom_schedules.get(classroom_id, {}).get(day, {}).get(time_slot, "")
		
		if not offering_id_currently_in_slot.is_empty() and is_instance_valid(academic_manager):
			var details = academic_manager.get_offering_details(offering_id_currently_in_slot)
			update_display(details if not details.is_empty() else {})
		else:
			update_display({}) # Clears the cell if no offering

# --- Signal Handlers ---
func _on_unschedule_button_pressed():
	if not is_instance_valid(academic_manager):
		printerr("TimeSlotCell (%s): AcademicManager not available to unschedule." % name)
		return
		
	var offering_to_unschedule = current_offering_id_in_cell
	if offering_to_unschedule.is_empty(): # Safety: re-fetch from authoritative source
		offering_to_unschedule = academic_manager.classroom_schedules.get(classroom_id, {}).get(day, {}).get(time_slot, "")

	if offering_to_unschedule.is_empty():
		printerr("TimeSlotCell (%s): No offering ID to unschedule." % name)
		unschedule_button.visible = false
		return
		
	if DETAILED_LOGGING_ENABLED: print_debug("Requesting unschedule for offering: " + offering_to_unschedule)
	academic_manager.unschedule_class(offering_to_unschedule)
	# UI refresh is handled by signals from AcademicManager that SchedulingUI listens to

# --- Getters for TimetableGrid Drag & Drop ---
func get_cell_day() -> String:
	return day

func get_cell_time_slot() -> String:
	return time_slot

# Helper for logging
func print_debug(message: String):
	if not DETAILED_LOGGING_ENABLED: return
	print("[TimeSlotCell %s-%s C:%s]: %s" % [day, time_slot, classroom_id.right(3), message])
