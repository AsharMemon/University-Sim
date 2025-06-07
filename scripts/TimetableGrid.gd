# TimetableGrid.gd
# Script for the timetable grid of a single classroom.
class_name TimetableGrid
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
	if not (data is Dictionary): return false # Basic check

	var cell: Control = _get_cell_at_position(at_position) # Should be TimeSlotCell
	if not is_instance_valid(cell) or not cell.has_method("get_cell_day"): # Ensure it's a valid cell
		if is_instance_valid(last_drag_over_cell): last_drag_over_cell.set_drag_over_feedback(false)
		last_drag_over_cell = null
		return false

	var can_drop_flag = false
	var drag_type = data.get("type", "")

	if drag_type == "course_offering":
		var offering_id = data.get("offering_id")
		var primary_day = cell.get_cell_day()
		var time_slot = cell.get_cell_time_slot()
		
		# Check if the primary slot itself is available. AM will check pattern.
		# More advanced: check pattern availability here for immediate feedback.
		if is_instance_valid(academic_manager) and academic_manager.is_slot_available(classroom_id, primary_day, time_slot):
			# Further check: is this course already scheduled or pending?
			var offering_details = academic_manager.get_offering_details(offering_id)
			if offering_details.get("status", "unscheduled") == "unscheduled":
				can_drop_flag = true
		
	elif drag_type == "professor":
		var professor_id = data.get("professor_id")
		# Check if the cell contains a "pending_professor" course
		if cell.is_pending_schedule: # is_pending_schedule is a new var in TimeSlotCell
			var pending_offering_id = cell.current_offering_id_in_cell # Assuming this stores the ID of pending/scheduled course
			var pending_details = academic_manager.get_offering_details(pending_offering_id)

			if pending_details.get("status") == "pending_professor":
				# Check if professor is available for the entire duration of this pending course
				# This is a simplified check for the primary slot; AM's assign will do the full check.
				if not academic_manager.is_professor_teaching_another_course_at(professor_id, cell.get_cell_day(), cell.get_cell_time_slot(), pending_offering_id):
					# TODO: Add specialization check here for better feedback if desired
					can_drop_flag = true
	
	# Manage drag over feedback (as before)
	if is_instance_valid(last_drag_over_cell) and last_drag_over_cell != cell:
		if last_drag_over_cell.has_method("set_drag_over_feedback"):
			last_drag_over_cell.set_drag_over_feedback(false)
	
	if cell.has_method("set_drag_over_feedback"):
		cell.set_drag_over_feedback(can_drop_flag)
	last_drag_over_cell = cell
	
	return can_drop_flag


func _drop_data(at_position: Vector2, data: Variant):
	var cell: Control = _get_cell_at_position(at_position) # Should be TimeSlotCell
	
	if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
		last_drag_over_cell.set_drag_over_feedback(false)
		last_drag_over_cell = null

	if not (data is Dictionary and is_instance_valid(cell) and cell.has_method("get_cell_day")):
		return

	var drag_type = data.get("type", "")

	if drag_type == "course_offering":
		var primary_day = cell.get_cell_day()
		var time_slot = cell.get_cell_time_slot()
		var offering_id = data.get("offering_id")
		
		if DETAILED_LOGGING_ENABLED: print_debug("Attempting to drop COURSE '%s' on %s at %s in classroom %s" % [offering_id, primary_day, time_slot, classroom_id])
		
		if is_instance_valid(academic_manager):
			var success = academic_manager.place_course_in_slot_pending(offering_id, classroom_id, primary_day, time_slot)
			if success:
				if DETAILED_LOGGING_ENABLED: print_debug("Successfully initiated PENDING scheduling for %s." % offering_id)
			else:
				if DETAILED_LOGGING_ENABLED: print_debug("Failed to place course %s in pending state." % offering_id)
				# Optionally show a user message here (e.g., "Slots conflict or invalid pattern.")

	elif drag_type == "professor":
		var professor_id = data.get("professor_id")
		# Ensure the cell has a pending course
		if cell.is_pending_schedule: # is_pending_schedule is a new var in TimeSlotCell
			var pending_offering_id = cell.current_offering_id_in_cell # Get ID from cell
			var offering_details = academic_manager.get_offering_details(pending_offering_id)

			if offering_details.get("status") == "pending_professor":
				if DETAILED_LOGGING_ENABLED: print_debug("Attempting to assign PROFESSOR '%s' to PENDING offering '%s' in cell %s %s" % [professor_id, pending_offering_id, cell.get_cell_day(), cell.get_cell_time_slot()])
				
				if is_instance_valid(academic_manager):
					var success = academic_manager.assign_instructor_to_pending_course(pending_offering_id, professor_id)
					if success:
						if DETAILED_LOGGING_ENABLED: print_debug("Successfully assigned Professor %s to %s." % [professor_id, pending_offering_id])
					else:
						if DETAILED_LOGGING_ENABLED: print_debug("Failed to assign Professor %s to %s (availability/specialization issue)." % [professor_id, pending_offering_id])
						# Optionally show a user message
			else:
				if DETAILED_LOGGING_ENABLED: print_debug("Drop of professor on cell, but course %s is not pending. Status: %s" % [pending_offering_id, offering_details.get("status")])
		else:
			if DETAILED_LOGGING_ENABLED: print_debug("Professor dropped on cell that does not have a pending course.")

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

func set_scheduling_ui_parent(ui_parent: SchedulingPanel): # Called by SchedulingUI
	self.scheduling_ui_parent = ui_parent

# --- NEW: Overlay Management Functions ---
func display_professor_availability_overlay(professor_id_to_check: String):
	if not is_instance_valid(time_slots_grid) or not is_instance_valid(academic_manager):
		if DETAILED_LOGGING_ENABLED: print_debug("Cannot display prof availability overlay: time_slots_grid or AM invalid.")
		return
	if DETAILED_LOGGING_ENABLED: print_debug(["TimetableGrid: Displaying overlay for professor:", professor_id_to_check])

	for child_node in time_slots_grid.get_children():
		if child_node is PanelContainer and child_node.has_method("show_availability_for_professor"): # Assuming TimeSlotCell is PanelContainer
			var cell: TimeSlotCell = child_node as TimeSlotCell # Cast for type safety if TimeSlotCell.gd is class_name
			cell.show_availability_for_professor(professor_id_to_check, academic_manager)

func clear_professor_availability_overlay():
	if not is_instance_valid(time_slots_grid):
		if DETAILED_LOGGING_ENABLED: print_debug("Cannot clear prof availability overlay: time_slots_grid invalid.")
		return
	if DETAILED_LOGGING_ENABLED: print_debug(["TimetableGrid: Clearing professor availability overlay."])

	for child_node in time_slots_grid.get_children():
		if child_node is PanelContainer and child_node.has_method("revert_display_from_overlay"):
			var cell: TimeSlotCell = child_node as TimeSlotCell
			cell.revert_display_from_overlay()

func refresh_display():
	if DETAILED_LOGGING_ENABLED: print_debug("refresh_display() called for classroom: %s" % classroom_id)
	if not is_instance_valid(academic_manager):
		print_debug("Cannot refresh_display, AcademicManager is invalid.")
		return
	# No need to call _populate_grid() again unless the days/time_slots change
	_display_scheduled_classes()
	
func print_debug(message_parts): # Copied from your script
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[TimetableGrid C:%s]: " % classroom_id.right(4) if not classroom_id.is_empty() else "[TimetableGrid]: "
	# ... (your print_debug formatting) ...
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: final_message += String(" ").join(message_parts.map(func(x):return str(x)))
	else: final_message += str(message_parts)
	print(final_message)
