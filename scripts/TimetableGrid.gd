# TimetableGrid.gd
# Script for the timetable grid of a single classroom.
extends PanelContainer

# --- Node References ---
@onready var header_row_hbox: HBoxContainer = get_node_or_null("GridVBox/HeaderRowHBox")
@onready var time_slots_grid: GridContainer = get_node_or_null("GridVBox/TimeSlotsScroll/TimeSlotsGrid")

# --- Injected Data ---
var classroom_id: String = ""
var academic_manager: AcademicManager = null
var professor_manager: ProfessorManager = null # <<< NEW - To pass to cells

# --- Scene Preloads ---
const TimeSlotCellScene: PackedScene = preload("res://scenes/TimeSlotCell.tscn")

# --- Constants ---
const DAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"]
const TIME_SLOTS: Array[String] = [
	"0800", "0900", "1000", "1100", "1200",
	"1300", "1400", "1500", "1600", "1700"
]
# --- State for Drag Feedback ---
var last_drag_over_cell: Control = null # Should be TimeSlotCell type if that's what _get_cell_at_position returns
const DETAILED_LOGGING_ENABLED: bool = true # For this script's debug messages

# --- Initialization ---
func _ready():
	if not is_instance_valid(header_row_hbox) or not is_instance_valid(time_slots_grid):
		printerr("TimetableGrid: Critical child nodes not found!")
	if not TimeSlotCellScene:
		printerr("TimetableGrid: CRITICAL - TimeSlotCell.tscn not preloaded.")

# --- Public Setup Function ---
# MODIFIED to accept ProfessorManager
func setup_grid(p_classroom_id: String, p_academic_manager: AcademicManager, p_professor_manager: ProfessorManager):
	self.classroom_id = p_classroom_id
	self.academic_manager = p_academic_manager
	self.professor_manager = p_professor_manager # <<< STORE ProfessorManager

	if not is_instance_valid(self.academic_manager):
		printerr("TimetableGrid: AcademicManager not provided for classroom ", self.classroom_id); return
	# ProfessorManager can be optional for basic grid display if cells don't show prof names initially
	if not is_instance_valid(self.professor_manager):
		print_debug("ProfessorManager not provided to TimetableGrid. Instructor names in cells may not display.")

	_populate_grid() # This will now pass professor_manager to cells
	_display_scheduled_classes()

func _populate_grid():
	if not is_instance_valid(time_slots_grid) or not is_instance_valid(header_row_hbox) or not TimeSlotCellScene: return

	# Clear previous grid
	for child in time_slots_grid.get_children(): child.queue_free()
	var header_children = header_row_hbox.get_children()
	for i in range(header_children.size() -1, -1, -1): # Iterate backwards when removing
		if header_children[i].name != "TimeHeaderSpacer": # Keep the initial spacer if you have one named that
			header_children[i].queue_free()
	
	# Ensure the first spacer for time column header exists if not already there
	if header_row_hbox.get_child_count() == 0 or header_row_hbox.get_child(0).name != "TimeHeaderSpacer":
		var spacer = Control.new(); spacer.custom_minimum_size.x = 70 # Match time_label width
		spacer.name = "TimeHeaderSpacer"
		header_row_hbox.add_child(spacer)
		header_row_hbox.move_child(spacer, 0) # Ensure it's first
		
	for day_name in DAYS: # Populate day headers
		var day_label = Label.new(); day_label.text = day_name
		# ... (styling) ...
		header_row_hbox.add_child(day_label)

	time_slots_grid.columns = DAYS.size() + 1

	for time_str in TIME_SLOTS:
		var time_label = Label.new(); time_label.text = time_str.insert(2, ":")
		# ... (styling) ...
		time_slots_grid.add_child(time_label)

		for day_str in DAYS:
			var cell_instance = TimeSlotCellScene.instantiate() # Should be TimeSlotCell
			if is_instance_valid(cell_instance):
				time_slots_grid.add_child(cell_instance)
				if cell_instance.has_method("setup_cell"):
					# <<< PASS ProfessorManager to each cell >>>
					cell_instance.setup_cell(day_str, time_str, classroom_id, academic_manager, professor_manager)
				# else: printerr("TimeSlotCell missing setup_cell()")
			# else: printerr("Failed to instantiate TimeSlotCellScene")

func _display_scheduled_classes():
	if not is_instance_valid(academic_manager) or not is_instance_valid(time_slots_grid):
		if DETAILED_LOGGING_ENABLED: print_debug("_display_scheduled_classes: Aborting, AM or time_slots_grid invalid.")
		return

	var classroom_schedule_for_this_grid = academic_manager.get_schedule_for_classroom(classroom_id)
	if DETAILED_LOGGING_ENABLED:
		print_debug("--- _display_scheduled_classes for Classroom: %s ---" % classroom_id)
		print_debug("Fetched classroom_schedule_for_this_grid: %s" % str(classroom_schedule_for_this_grid))

	var found_any_scheduled_class_for_this_grid = false # For logging

	for i in range(TIME_SLOTS.size()):
		var current_time_slot = TIME_SLOTS[i]
		for j in range(DAYS.size()):
			var current_day = DAYS[j]
			var cell_node_index = i * (time_slots_grid.columns) + (j + 1)
			
			if cell_node_index < time_slots_grid.get_child_count():
				var cell_node = time_slots_grid.get_child(cell_node_index) # Should be TimeSlotCell
				if is_instance_valid(cell_node) and cell_node.has_method("update_display"):
					var offering_id_in_slot = classroom_schedule_for_this_grid.get(current_day, {}).get(current_time_slot)
					
					var offering_details_for_cell = {} # Default to empty
					if offering_id_in_slot:
						found_any_scheduled_class_for_this_grid = true
						if DETAILED_LOGGING_ENABLED: 
							print_debug("  Cell %s %s (Node: %s): Found offering_id '%s'. Fetching details..." % [current_day, current_time_slot, cell_node.name, offering_id_in_slot])
						offering_details_for_cell = academic_manager.get_offering_details(offering_id_in_slot)
						if DETAILED_LOGGING_ENABLED and offering_details_for_cell.is_empty():
							print_debug("  WARNING for Cell %s %s: get_offering_details for ID '%s' returned EMPTY." % [current_day, current_time_slot, offering_id_in_slot])
						elif DETAILED_LOGGING_ENABLED:
							print_debug("  Cell %s %s: Passing details to update_display: %s" % [current_day, current_time_slot, str(offering_details_for_cell).left(100)]) # Log part of details
					
					cell_node.update_display(offering_details_for_cell) # Pass details or empty dict
				# else:
					# if DETAILED_LOGGING_ENABLED: print_debug("  Cell at index %d is not a valid TimeSlotCell with update_display." % cell_node_index)
			# else:
				# if DETAILED_LOGGING_ENABLED: print_debug("  Cell node index %d out of bounds (child count %d)." % [cell_node_index, time_slots_grid.get_child_count()])
	
	if DETAILED_LOGGING_ENABLED and not found_any_scheduled_class_for_this_grid:
		print_debug("--- _display_scheduled_classes for Classroom: %s --- No scheduled classes found in fetched schedule to display." % classroom_id)
	elif DETAILED_LOGGING_ENABLED:
		print_debug("--- _display_scheduled_classes for Classroom: %s --- Finished." % classroom_id)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if DETAILED_LOGGING_ENABLED: print_debug("_can_drop_data CALLED. Data type")
	var can_drop_flag = false
	var current_cell_under_mouse: Control = _get_cell_at_position(at_position) # Should return TimeSlotCell

	if DETAILED_LOGGING_ENABLED: print_debug("Cell under mouse for can_drop_data: %s" % (current_cell_under_mouse.name if current_cell_under_mouse else "None"))

	if data is Dictionary and data.get("type") == "course_offering":
		if is_instance_valid(current_cell_under_mouse) and current_cell_under_mouse.has_method("set_drag_over_feedback"):
			var primary_day = current_cell_under_mouse.day # Assuming cell has 'day' property
			var time_slot = current_cell_under_mouse.time_slot # Assuming cell has 'time_slot'
			
			if not (primary_day == "Mon" or primary_day == "Tue"):
				can_drop_flag = false
			elif is_instance_valid(academic_manager) and \
				 academic_manager.is_slot_available(classroom_id, primary_day, time_slot):
				can_drop_flag = true
	
	if is_instance_valid(last_drag_over_cell) and last_drag_over_cell != current_cell_under_mouse and \
	   last_drag_over_cell.has_method("set_drag_over_feedback"):
		last_drag_over_cell.set_drag_over_feedback(false)

	if is_instance_valid(current_cell_under_mouse) and current_cell_under_mouse.has_method("set_drag_over_feedback"):
		current_cell_under_mouse.set_drag_over_feedback(can_drop_flag)
		last_drag_over_cell = current_cell_under_mouse
	else:
		last_drag_over_cell = null

	return can_drop_flag

func _drop_data(at_position: Vector2, data: Variant):
	var cell: Control = _get_cell_at_position(at_position) # Should be TimeSlotCell
	
	if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
		last_drag_over_cell.set_drag_over_feedback(false)
		last_drag_over_cell = null

	if data is Dictionary and data.get("type") == "course_offering":
		if is_instance_valid(cell) and cell.has_method("get_cell_day") and cell.has_method("get_cell_time_slot"): # Assuming TimeSlotCell has these getters
			var primary_day = cell.get_cell_day()
			var time_slot = cell.get_cell_time_slot()
			var offering_id = data.get("offering_id")

			if not (primary_day == "Mon" or primary_day == "Tue"):
				print_debug("Invalid drop day. Can only initiate schedule on Mon or Tue. Attempted: ", primary_day)
				return

			# --- Get selected instructor from parent SchedulingUI ---
			var selected_instructor_id: String = ""
			var scheduling_ui_node = _get_scheduling_ui_ancestor() # Helper to find the SchedulingUI panel

			if is_instance_valid(scheduling_ui_node) and scheduling_ui_node.has_method("get_selected_instructor_id_for_scheduling"):
				selected_instructor_id = scheduling_ui_node.get_selected_instructor_id_for_scheduling()
				if DETAILED_LOGGING_ENABLED: print_debug("Instructor selected via dropdown: %s" % (selected_instructor_id if not selected_instructor_id.is_empty() else "Unassigned"))
			else:
				if DETAILED_LOGGING_ENABLED: print_debug("Could not get selected instructor from parent SchedulingUI. Scheduling as Unassigned.")
			
			if DETAILED_LOGGING_ENABLED: print_debug("Attempting to drop '%s' (ID: %s) on %s at %s in classroom %s with instructor: %s" % [data.get("course_name","N/A"), offering_id, primary_day, time_slot, classroom_id, selected_instructor_id])
			
			if is_instance_valid(academic_manager):
				var success = academic_manager.schedule_class(
					offering_id,
					classroom_id,
					primary_day,
					time_slot,
					selected_instructor_id # <<< PASS INSTRUCTOR ID
				)
				if success:
					if DETAILED_LOGGING_ENABLED: print_debug("Successfully initiated scheduling via drop.")
					# AcademicManager will emit "schedules_updated", which SchedulingUI listens to for refresh.
				else:
					if DETAILED_LOGGING_ENABLED: print_debug("Failed to schedule via drop (pattern slot unavailable or other issue).")
		else:
			if DETAILED_LOGGING_ENABLED: print_debug("Drop occurred outside a valid cell or cell is not a TimeSlotCell.")

# Helper to find the SchedulingUI panel ancestor
func _get_scheduling_ui_ancestor() -> Node:
	var current_node = self
	var safety_count = 0
	while is_instance_valid(current_node) and safety_count < 10: # Max 10 levels up
		# Check if the script attached to current_node is SchedulingPanel.gd
		if current_node.get_script() == preload("res://scripts/SchedulingPanel.gd"): # Ensure this path is correct
			if DETAILED_LOGGING_ENABLED: print_debug("Found SchedulingUI ancestor: " + current_node.name)
			return current_node
		current_node = current_node.get_parent()
		safety_count += 1
	if DETAILED_LOGGING_ENABLED: print_debug("SchedulingUI ancestor NOT found after %d tries." % safety_count)
	return null

# ... (_notification, _get_cell_at_position using global mouse pos, print_debug) ...
# Ensure _get_cell_at_position is robust as in your original file.
func _notification(what: int): # Copied from your script
	if what == NOTIFICATION_MOUSE_EXIT:
		if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
			last_drag_over_cell.set_drag_over_feedback(false); last_drag_over_cell = null
	elif what == NOTIFICATION_DRAG_END:
		if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
			last_drag_over_cell.set_drag_over_feedback(false); last_drag_over_cell = null

func _get_cell_at_position(p_pos_local_to_timetable_grid: Vector2) -> Control:
	if not is_instance_valid(time_slots_grid): return null
	var global_mouse_pos = get_global_mouse_position()
	# if DETAILED_LOGGING_ENABLED: print_debug("get_cell_at_position: Global mouse: %s, My global_rect: %s" % [str(global_mouse_pos), str(get_global_rect())])

	for i in range(time_slots_grid.get_child_count()):
		var child = time_slots_grid.get_child(i)
		# Ensure it's a TimeSlotCell, not a time label
		if child is PanelContainer and child.has_method("setup_cell"): # Assuming your TimeSlotCell root is PanelContainer
			var cell_rect = child.get_global_rect()
			# if DETAILED_LOGGING_ENABLED and i < 15 : # Log for first few cells for brevity
				# print_debug("Checking cell %s: %s, Rect: %s" % [i, child.name, str(cell_rect)])
			if cell_rect.has_point(global_mouse_pos):
				if DETAILED_LOGGING_ENABLED: print_debug("Mouse is OVER cell: %s" % child.name)
				return child
	if DETAILED_LOGGING_ENABLED: print_debug("Mouse is NOT over any valid cell in this grid.")
	return null

func print_debug(message_parts): # Copied from your script
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[TimetableGrid C:%s]: " % classroom_id.right(4) if not classroom_id.is_empty() else "[TimetableGrid]: "
	# ... (your print_debug formatting) ...
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: final_message += String(" ").join(message_parts.map(func(x):return str(x)))
	else: final_message += str(message_parts)
	print(final_message)
