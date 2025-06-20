# TimeSlotCell.gd
# Script for an individual cell in the timetable grid.
class_name TimeSlotCell
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

var is_pending_schedule: bool = false # <<< NEW state variable
# current_offering_id_in_cell already exists and will hold the ID of pending/scheduled course

# --- Visual State Colors --- (add one for pending)
const COLOR_PENDING_PROF_BG = Color(1.0, 0.9, 0.6, 0.2) # Yellowish for pending

# --- NEW: StyleBoxes for Overlay ---
var overlay_prof_busy_style: StyleBoxFlat
var overlay_prof_available_style: StyleBoxFlat
var overlay_prof_valid_target_style: StyleBoxFlat # For pending course this prof can teach
var overlay_slot_taken_by_other_style: StyleBoxFlat # If cell has another prof's scheduled class

var is_displaying_overlay_mode: bool = false # To track if currently in overlay display mode

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
	
	# Initialize overlay styles
	overlay_prof_busy_style = StyleBoxFlat.new()
	overlay_prof_busy_style.bg_color = Color(1.0, 0.6, 0.6, 0.4) # Light Red tint
	overlay_prof_busy_style.border_width_bottom = 1; overlay_prof_busy_style.border_color = Color.DARK_RED

	overlay_prof_available_style = StyleBoxFlat.new()
	overlay_prof_available_style.bg_color = Color(0.6, 1.0, 0.6, 0.3) # Light Green tint
	overlay_prof_available_style.border_width_bottom = 1; overlay_prof_available_style.border_color = Color.DARK_GREEN
	
	overlay_prof_valid_target_style = StyleBoxFlat.new()
	overlay_prof_valid_target_style.bg_color = Color(0.5, 0.9, 1.0, 0.5) # Light Blue / Special Highlight
	overlay_prof_valid_target_style.border_width_left = 2
	overlay_prof_valid_target_style.border_width_right = 2
	overlay_prof_valid_target_style.border_color = Color.ROYAL_BLUE

	overlay_slot_taken_by_other_style = StyleBoxFlat.new()
	overlay_slot_taken_by_other_style.bg_color = Color(0.8, 0.8, 0.8, 0.3) # Greyish if taken by other scheduled class
	overlay_slot_taken_by_other_style.border_width_bottom = 1; overlay_slot_taken_by_other_style.border_color = Color.GRAY

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
	   not is_instance_valid(instructor_name_label):
		return

	var current_style: StyleBoxFlat = default_stylebox.duplicate(true) if default_stylebox is StyleBoxFlat else StyleBoxFlat.new()
	if not (default_stylebox is StyleBoxFlat): current_style.bg_color = COLOR_DEFAULT_BG

	current_offering_id_in_cell = "" # Reset
	is_pending_schedule = false      # Reset
	instructor_name_label.text = ""
	content_label.text = ""
	unschedule_button.visible = false

	if offering_details != null and not offering_details.is_empty():
		current_offering_id_in_cell = offering_details.get("offering_id", "")
		var course_name = offering_details.get("course_name", "N/A")
		var course_id_short = offering_details.get("course_id", "N/A").right(5)
		var enrolled_count = offering_details.get("enrolled_count", 0)
		var max_cap = offering_details.get("max_capacity", 0)
		var status = offering_details.get("status", "unknown")
		var instructor_id = offering_details.get("instructor_id", "")

		# Determine if this cell is the "primary" display cell for a multi-slot course
		var is_primary_display_slot = false
		var offering_pattern = offering_details.get("pattern", "")
		var offering_start_time = offering_details.get("start_time_slot", "")
		# This offering's main definition is at its start_time_slot on days defined by its pattern
		# This cell is a "primary" display if its time_slot matches the offering's start_time_slot
		# AND this cell's day is part of the offering's pattern.
		# A more robust check: get all (day,slot) occupied by this offering_id from AM.
		# If this cell's (day,slot) is the 'first' one (e.g. Mon 8am for MWF 8am), then it's primary.
		# For simplicity here, we'll assume if AM placed it here, it's relevant.
		# The unschedule button should ideally only appear on the "main" slot of the course.
		# Let's make it visible if the current cell's time slot is the start_time_slot of the course.
		if self.time_slot == offering_start_time:
			is_primary_display_slot = true


		if status == "scheduled":
			is_pending_schedule = false
			content_label.text = "%s (%s)\n%d/%d" % [course_name, course_id_short, enrolled_count, max_cap]
			unschedule_button.visible = is_primary_display_slot # Show on primary slot
			
			if not instructor_id.is_empty() and is_instance_valid(professor_manager):
				var prof: Professor = professor_manager.get_professor_by_id(instructor_id)
				if is_instance_valid(prof):
					var name_parts = prof.professor_name.split(" ")
					instructor_name_label.text = name_parts[-1] + ", " + name_parts[0].left(1) + "." if name_parts.size() > 1 else prof.professor_name
				else: instructor_name_label.text = "Prof. N/A"
			elif not instructor_id.is_empty(): instructor_name_label.text = "Prof. Sys N/A"
			else: instructor_name_label.text = "Error: Sched, No Prof!?" # Should not happen

			current_style.bg_color = COLOR_SCHEDULED_BG
			if max_cap > 0 and enrolled_count >= max_cap: current_style.bg_color = COLOR_FULL_BG

		elif status == "pending_professor":
			is_pending_schedule = true # Mark this cell as having a pending course
			content_label.text = "%s (%s)\n%d/%d" % [course_name, course_id_short, enrolled_count, max_cap]
			instructor_name_label.text = "PENDING PROF"
			instructor_name_label.modulate = Color.DARK_ORANGE # Make it stand out
			unschedule_button.visible = is_primary_display_slot # Show on primary slot
			current_style.bg_color = COLOR_PENDING_PROF_BG
		
		else: # Unscheduled or other status, effectively empty for this cell
			content_label.text = ""
			instructor_name_label.text = ""
			is_pending_schedule = false
			current_style.bg_color = COLOR_DEFAULT_BG
			unschedule_button.visible = false
			current_offering_id_in_cell = "" # Ensure it's cleared if not truly occupied by this cell
	else:
		content_label.text = ""
		instructor_name_label.text = ""
		is_pending_schedule = false
		current_style.bg_color = COLOR_DEFAULT_BG
		unschedule_button.visible = false
		current_offering_id_in_cell = ""

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

# --- NEW: Overlay Display Logic ---
func show_availability_for_professor(p_id_being_dragged: String, acad_man_ref: AcademicManager):
	if not is_instance_valid(acad_man_ref): return

	is_displaying_overlay_mode = true
	var style_to_apply = default_stylebox # Fallback

	var offering_details_in_this_cell = {}
	if not current_offering_id_in_cell.is_empty():
		offering_details_in_this_cell = acad_man_ref.get_offering_details(current_offering_id_in_cell)

	if not offering_details_in_this_cell.is_empty():
		var status = offering_details_in_this_cell.get("status")
		var instructor_id = offering_details_in_this_cell.get("instructor_id", "")

		if status == "pending_professor":
			# Check if p_id_being_dragged can teach THIS pending course
			var can_assign = true # Assume true initially
			# 1. Check availability for all slots of this pending course
			var pattern_days = acad_man_ref.get_days_for_pattern(offering_details_in_this_cell.get("pattern", ""))
			var start_slot_idx = acad_man_ref.HOURLY_TIME_SLOTS.find(offering_details_in_this_cell.get("start_time_slot", ""))
			var duration = offering_details_in_this_cell.get("duration_slots", 1)

			if start_slot_idx != -1:
				for day_in_pattern in pattern_days:
					for i in range(duration):
						var slot_index_to_check = start_slot_idx + i
						if slot_index_to_check < acad_man_ref.HOURLY_TIME_SLOTS.size():
							var time_slot_to_check = acad_man_ref.HOURLY_TIME_SLOTS[slot_index_to_check]
							# Pass current_offering_id_in_cell to ignore self when checking availability
							if acad_man_ref.is_professor_teaching_another_course_at(p_id_being_dragged, day_in_pattern, time_slot_to_check, current_offering_id_in_cell):
								can_assign = false; break
					if not can_assign: break
			else: can_assign = false # Invalid start slot for pending course

			# 2. (Optional but good) Specialization Check
			# if can_assign and is_instance_valid(professor_manager):
			# 	var prof_object = professor_manager.get_professor_by_id(p_id_being_dragged)
			# 	var course_def = acad_man_ref.university_data_ref.get_course_details(offering_details_in_this_cell.get("course_id")) # Path to your course definitions
			# 	if is_instance_valid(prof_object) and not course_def.is_empty():
			# 		var required_spec = course_def.get("specialization") # Assuming your course_def has this
			# 		var prof_spec = prof_object.specialization # Assuming Professor object has this
			# 		if required_spec != prof_spec and required_spec != Professor.Specialization.GENERAL and prof_spec != Professor.Specialization.GENERAL:
			# 			can_assign = false
			
			if can_assign:
				style_to_apply = overlay_prof_valid_target_style
			else: # Cannot assign this prof to this specific pending course
				style_to_apply = overlay_prof_busy_style # Or a different "cannot assign here" style
		
		elif status == "scheduled":
			if instructor_id == p_id_being_dragged: # Dragging prof over their own scheduled class
				style_to_apply = overlay_prof_available_style # Or a "this is your class" style
			else: # Taken by another professor
				style_to_apply = overlay_slot_taken_by_other_style
		else: # "unscheduled" status but somehow has details (should be rare for a cell)
			style_to_apply = overlay_prof_available_style # Treat as available if not clearly busy

	else: # Cell is empty
		if acad_man_ref.is_professor_teaching_another_course_at(p_id_being_dragged, self.day, self.time_slot, ""):
			style_to_apply = overlay_prof_busy_style
		else:
			style_to_apply = overlay_prof_available_style
			
	add_theme_stylebox_override("panel", style_to_apply)

func revert_display_from_overlay():
	if not is_displaying_overlay_mode: return # Only revert if it was in overlay mode
	is_displaying_overlay_mode = false
	
	# Call update_display to restore based on actual cell content
	var details_to_restore = {}
	if not current_offering_id_in_cell.is_empty() and is_instance_valid(academic_manager):
		details_to_restore = academic_manager.get_offering_details(current_offering_id_in_cell)
	update_display(details_to_restore)
	
# --- Getters for TimetableGrid Drag & Drop ---
func get_cell_day() -> String:
	return day

func get_cell_time_slot() -> String:
	return time_slot

# Helper for logging
func print_debug(message: String):
	if not DETAILED_LOGGING_ENABLED: return
	print("[TimeSlotCell %s-%s C:%s]: %s" % [day, time_slot, classroom_id.right(3), message])
