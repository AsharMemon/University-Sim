# TimetableGrid.gd
# Script for the timetable grid of a single classroom.
extends PanelContainer

# --- Node References ---
@onready var header_row_hbox: HBoxContainer = get_node_or_null("GridVBox/HeaderRowHBox")
@onready var time_slots_grid: GridContainer = get_node_or_null("GridVBox/TimeSlotsScroll/TimeSlotsGrid")

# --- Injected Data ---
var classroom_id: String = ""
var academic_manager: AcademicManager = null 

# --- Scene Preloads ---
const TimeSlotCellScene: PackedScene = preload("res://scenes/TimeSlotCell.tscn") # ADJUST PATH

# --- Constants ---
const DAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri"] 
const TIME_SLOTS: Array[String] = [
	"0800", "0900", "1000", "1100", "1200", 
	"1300", "1400", "1500", "1600", "1700"
]

# --- State for Drag Feedback ---
var last_drag_over_cell: Control = null

# --- Initialization ---
func _ready():
	if not is_instance_valid(header_row_hbox) or not is_instance_valid(time_slots_grid):
		printerr("TimetableGrid: Critical child nodes (HeaderRowHBox or TimeSlotsGrid) not found!")
		return
	if not TimeSlotCellScene:
		printerr("TimetableGrid: CRITICAL - TimeSlotCell.tscn not preloaded. Check path.")
		return

# --- Public Setup Function ---
func setup_grid(p_classroom_id: String, p_academic_manager: AcademicManager):
	self.classroom_id = p_classroom_id
	self.academic_manager = p_academic_manager
	if not is_instance_valid(self.academic_manager):
		printerr("TimetableGrid: AcademicManager not provided during setup for classroom ", self.classroom_id); return
	if not TimeSlotCellScene:
		printerr("TimetableGrid: TimeSlotCellScene not loaded in setup_grid for classroom ", self.classroom_id); return
	_populate_grid()
	_display_scheduled_classes()

# --- Grid Population and Display (No major changes needed here from previous version) ---
func _populate_grid():
	# ... (same as your working version that instantiates TimeSlotCellScene) ...
	if not is_instance_valid(time_slots_grid) or not is_instance_valid(header_row_hbox) or not TimeSlotCellScene: return

	for child in time_slots_grid.get_children():
		child.queue_free()
	var header_children = header_row_hbox.get_children()
	if header_children.size() > 0: 
		for i in range(header_children.size() -1, 0, -1): 
			header_children[i].queue_free()

	if header_row_hbox.get_child_count() == 0: 
		var spacer = Control.new(); spacer.custom_minimum_size.x = 80 
		header_row_hbox.add_child(spacer)
		
	for day_name in DAYS:
		var day_label = Label.new(); day_label.text = day_name
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_row_hbox.add_child(day_label)

	time_slots_grid.columns = DAYS.size() + 1 

	for time_str in TIME_SLOTS:
		var time_label = Label.new(); time_label.text = time_str.insert(2, ":") 
		time_label.custom_minimum_size.x = 70 
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		time_slots_grid.add_child(time_label)

		for day_str in DAYS:
			var cell_instance = TimeSlotCellScene.instantiate()
			if is_instance_valid(cell_instance):
				time_slots_grid.add_child(cell_instance)
				if cell_instance.has_method("setup_cell"):
					cell_instance.setup_cell(day_str, time_str, classroom_id, academic_manager)
				else:
					printerr("TimetableGrid: TimeSlotCell instance is missing setup_cell() method.")
			else:
				printerr("TimetableGrid: Failed to instantiate TimeSlotCellScene for ", day_str, ", ", time_str)
	time_slots_grid.queue_redraw()

func _display_scheduled_classes():
	# ... (same as your working version that calls update_display on each cell) ...
	if not is_instance_valid(academic_manager) or not is_instance_valid(time_slots_grid): return

	var classroom_schedule = academic_manager.get_schedule_for_classroom(classroom_id)
	
	for i in range(TIME_SLOTS.size()):
		var current_time_slot = TIME_SLOTS[i]
		for j in range(DAYS.size()):
			var current_day = DAYS[j]
			var cell_node_index = i * (DAYS.size() + 1) + (j + 1) 
			
			if cell_node_index < time_slots_grid.get_child_count():
				var cell_node = time_slots_grid.get_child(cell_node_index)
				if is_instance_valid(cell_node) and cell_node.has_method("update_display"):
					var offering_id_in_slot = classroom_schedule.get(current_day, {}).get(current_time_slot)
					if offering_id_in_slot:
						var offering_details = academic_manager.get_offering_details(offering_id_in_slot)
						cell_node.update_display(offering_details if offering_details else {})
					else:
						cell_node.update_display({}) 
# --- Drag and Drop Handling (MODIFIED) ---
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var can_drop_flag = false
	var current_cell_under_mouse = _get_cell_at_position(at_position)

	if data is Dictionary and data.get("type") == "course_offering":
		if is_instance_valid(current_cell_under_mouse) and current_cell_under_mouse.has_method("set_drag_over_feedback"):
			var primary_day = current_cell_under_mouse.day # This is the day the mouse is over
			var time_slot = current_cell_under_mouse.time_slot
			# var duration = data.get("default_duration_slots", AcademicManager.DURATION_MWF) # Duration is now implicit by day
			
			# Allow initiating drop only on Mon or Tue
			if not (primary_day == "Mon" or primary_day == "Tue"):
				can_drop_flag = false
			elif is_instance_valid(academic_manager) and \
			   academic_manager.is_slot_available(classroom_id, primary_day, time_slot): # is_slot_available now checks pattern
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
	var cell = _get_cell_at_position(at_position)
	
	if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
		last_drag_over_cell.set_drag_over_feedback(false)
		last_drag_over_cell = null

	if data is Dictionary and data.get("type") == "course_offering":
		if is_instance_valid(cell): 
			var primary_day = cell.day 
			var time_slot = cell.time_slot
			var offering_id = data.get("offering_id")
			# Duration is now handled by AcademicManager based on primary_day

			if not (primary_day == "Mon" or primary_day == "Tue"):
				print_debug("Invalid drop day. Can only initiate schedule on Mon or Tue. Attempted: ", primary_day)
				return

			print_debug("Attempting to drop '", data.get("course_name"), "' (ID: ", offering_id, ") starting on ", primary_day, " at ", time_slot, " in classroom ", classroom_id)
			
			if is_instance_valid(academic_manager):
				# schedule_class now only needs the primary day and start time
				var success = academic_manager.schedule_class(offering_id, classroom_id, primary_day, time_slot)
				if success:
					print_debug("Successfully initiated scheduling via drop.")
				else:
					print_debug("Failed to schedule via drop (pattern slot likely unavailable or other issue).")
		else:
			print_debug("Drop occurred outside a valid cell.")

# ... (_notification, _get_cell_at_position, print_debug remain the same as your working version) ...
func _notification(what: int):
	if what == NOTIFICATION_MOUSE_EXIT:
		if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
			last_drag_over_cell.set_drag_over_feedback(false); last_drag_over_cell = null
	elif what == NOTIFICATION_DRAG_END: 
		if is_instance_valid(last_drag_over_cell) and last_drag_over_cell.has_method("set_drag_over_feedback"):
			last_drag_over_cell.set_drag_over_feedback(false); last_drag_over_cell = null

func _get_cell_at_position(p_pos_local_to_timetable_grid: Vector2) -> Control: 
	if not is_instance_valid(time_slots_grid): return null
	var global_mouse_pos = get_global_mouse_position()
	for i in range(time_slots_grid.get_child_count()):
		var child = time_slots_grid.get_child(i)
		if i % (DAYS.size() + 1) == 0: continue 
		if child is PanelContainer and child.has_method("setup_cell"): 
			if child.get_global_rect().has_point(global_mouse_pos):
				return child 
	return null

func print_debug(message_parts):
	var final_message = "[TimetableGrid C:%s]: " % classroom_id.right(4) if not classroom_id.is_empty() else "[TimetableGrid]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY or typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : Array = message_parts; final_message += " ".join(temp_array)
	else: final_message += str(message_parts)
	print(final_message)
