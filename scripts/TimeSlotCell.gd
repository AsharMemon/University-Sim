# TimeSlotCell.gd
# Script for an individual cell in the timetable grid.
extends PanelContainer

# --- Node References ---
@onready var content_label: Label = get_node_or_null("ContentLabel")
@onready var unschedule_button: Button = get_node_or_null("UnscheduleButton")

# --- Cell Data (set by TimetableGrid.gd) ---
var day: String = ""
var time_slot: String = ""
var classroom_id: String = ""
var academic_manager: AcademicManager = null # Will be injected
var current_offering_id_in_cell: String = "" # Store the ID of the offering in this cell

# --- Visual State ---
var is_valid_drop_target: bool = false 
var default_stylebox: StyleBox
var drag_over_stylebox: StyleBoxFlat 

const COLOR_DEFAULT_BG = Color(0.9, 0.9, 0.9, 0.1)
const COLOR_DRAG_OVER_VALID_BG = Color(0.6, 0.9, 0.6, 0.3) 
const COLOR_SCHEDULED_BG = Color(0.7, 0.8, 1.0, 0.2) 
const COLOR_FULL_BG = Color(0.95, 0.7, 0.7, 0.2) # Light red tint for full classes

# --- Initialization ---
func _ready():
	if not is_instance_valid(content_label):
		printerr("TimeSlotCell: ContentLabel node not found!")
	if not is_instance_valid(unschedule_button):
		printerr("TimeSlotCell: UnscheduleButton node not found!")
	else:
		unschedule_button.pressed.connect(_on_unschedule_button_pressed)
		unschedule_button.visible = false # Ensure it's hidden initially

	default_stylebox = get_theme_stylebox("panel").duplicate(true) 

	drag_over_stylebox = StyleBoxFlat.new()
	drag_over_stylebox.bg_color = COLOR_DRAG_OVER_VALID_BG
	drag_over_stylebox.border_width_bottom = 1
	drag_over_stylebox.border_width_right = 1
	drag_over_stylebox.border_color = default_stylebox.border_color if default_stylebox is StyleBoxFlat else Color.GRAY
	
	mouse_filter = Control.MOUSE_FILTER_PASS 

# --- Public Setup Function ---
func setup_cell(p_day: String, p_time_slot: String, p_classroom_id: String, p_academic_manager: AcademicManager):
	self.day = p_day
	self.time_slot = p_time_slot
	self.classroom_id = p_classroom_id
	self.academic_manager = p_academic_manager
	
	self.name = "Cell_%s_%s" % [day, time_slot] 
	
	set_meta("day", self.day)
	set_meta("time_slot", self.time_slot)
	set_meta("classroom_id", self.classroom_id)
	
	update_display({}) 

# --- Display Logic ---
func update_display(offering_details: Dictionary): 
	if not is_instance_valid(content_label) or not is_instance_valid(unschedule_button): return

	var current_style = default_stylebox.duplicate(true) as StyleBoxFlat # Assume it's StyleBoxFlat for bg_color
	current_offering_id_in_cell = "" 

	if offering_details != null and not offering_details.is_empty():
		var course_name = offering_details.get("course_name", "N/A")
		var course_id = offering_details.get("course_id", "N/A")
		current_offering_id_in_cell = offering_details.get("offering_id", "")
		
		var enrolled_count = 0
		if offering_details.has("enrolled_student_ids") and offering_details.enrolled_student_ids is Array:
			enrolled_count = offering_details.enrolled_student_ids.size()
		elif offering_details.has("enrolled_count"): # Fallback if count is directly provided
			enrolled_count = offering_details.get("enrolled_count", 0)
			
		var max_cap = offering_details.get("max_capacity", 0)

		var is_start_slot = false
		if is_instance_valid(academic_manager) and not current_offering_id_in_cell.is_empty():
			# The 'day' in offering_details is the primary day of the pattern.
			# We need to check if self.time_slot is the start_time_slot of the offering.
			var main_schedule_info = academic_manager.scheduled_class_details.get(current_offering_id_in_cell)
			if main_schedule_info and main_schedule_info.start_time_slot == self.time_slot:
				# And also check if self.day is part of the pattern's active days
				var pattern = main_schedule_info.get("pattern", "")
				if (pattern == "MWF" and (self.day == "Mon" or self.day == "Wed" or self.day == "Fri")) or \
				   (pattern == "TR" and (self.day == "Tue" or self.day == "Thu")):
					is_start_slot = true # This specific cell instance is a starting slot for one of the pattern days
		
		var display_text = ""
		if is_start_slot:
			display_text = "%s (%s)\n%d/%d" % [course_name, course_id, enrolled_count, max_cap]
			unschedule_button.visible = true 
		else: 
			display_text = "(%s)\n%d/%d" % [course_id, enrolled_count, max_cap] # Show enrollment for continuation slots too
			unschedule_button.visible = false 
		
		content_label.text = display_text
		
		if current_style is StyleBoxFlat:
			if max_cap > 0 and enrolled_count >= max_cap:
				current_style.bg_color = COLOR_FULL_BG # Class is full
			else:
				current_style.bg_color = COLOR_SCHEDULED_BG
	else:
		content_label.text = "" 
		unschedule_button.visible = false 
		if current_style is StyleBoxFlat:
			current_style.bg_color = COLOR_DEFAULT_BG 
			
	add_theme_stylebox_override("panel", current_style)


# --- Drag Over Visual Feedback ---
func set_drag_over_feedback(can_drop: bool):
	if is_valid_drop_target == can_drop:
		return 

	is_valid_drop_target = can_drop
	if is_valid_drop_target:
		add_theme_stylebox_override("panel", drag_over_stylebox)
	else:
		if is_instance_valid(academic_manager):
			var offering_id_in_slot = academic_manager.classroom_schedules.get(classroom_id, {}).get(day, {}).get(time_slot)
			if offering_id_in_slot:
				var details = academic_manager.get_offering_details(offering_id_in_slot)
				update_display(details if details else {}) 
			else:
				update_display({}) 
		else: 
			add_theme_stylebox_override("panel", default_stylebox) 

# --- Signal Handlers ---
func _on_unschedule_button_pressed():
	if not is_instance_valid(academic_manager):
		printerr("TimeSlotCell: AcademicManager not available to unschedule.")
		return
	if current_offering_id_in_cell.is_empty():
		# This can happen if the button was visible but data changed before click
		# For safety, re-fetch from classroom_schedules based on cell's day/time
		var offering_id_now = academic_manager.classroom_schedules.get(classroom_id, {}).get(day, {}).get(time_slot)
		if offering_id_now and not offering_id_now.is_empty():
			current_offering_id_in_cell = offering_id_now
		else:
			printerr("TimeSlotCell: No offering ID to unschedule (current_offering_id_in_cell was empty and no offering found now).")
			unschedule_button.visible = false # Hide button if state is inconsistent
			return
		
	print("TimeSlotCell: Requesting unschedule for offering: ", current_offering_id_in_cell)
	academic_manager.unschedule_class(current_offering_id_in_cell)
	# UI refresh will be triggered by signals from AcademicManager
