# SchedulingUI.gd
class_name SchedulingPanel
extends PanelContainer

# --- Node References ---
@export var academic_manager: AcademicManager
@export var professor_manager: ProfessorManager

# Adjust these paths precisely to match your new scene tree structure (e.g., inside MainHBox)
@export var unscheduled_courses_list_vbox: VBoxContainer
@export var professor_list_vbox: VBoxContainer
@export var classroom_tabs: TabContainer

# --- Scene Preloads ---
const UnscheduledCourseEntryScene: PackedScene = preload("res://scenes/UnscheduledCourseEntry.tscn")
const ProfessorListEntryScene: PackedScene = preload("res://scenes/ProfessorListEntry.tscn") # New
const TimetableGridScene: PackedScene = preload("res://scenes/TimetableGrid.tscn")

# --- State ---
# var _current_drag_type: String = "" # Example for more advanced overlay
# var _dragged_professor_id: String = "" # Example for more advanced overlay

const DETAILED_LOGGING_ENABLED: bool = true

# --- Initialization ---
func _ready():
	# Validate critical node references
	if not is_instance_valid(unscheduled_courses_list_vbox):
		printerr("SchedulingUI: UnscheduledCoursesListVBox node not found! Check path.")
	if not is_instance_valid(professor_list_vbox):
		printerr("SchedulingUI: ProfessorListVBox node not found! Check path.")
	if not is_instance_valid(classroom_tabs):
		printerr("SchedulingUI: ClassroomTabs node not found! Check path.")

	if not UnscheduledCourseEntryScene: printerr("SchedulingUI: CRITICAL - UnscheduledCourseEntry.tscn not preloaded.")
	if not ProfessorListEntryScene: printerr("SchedulingUI: CRITICAL - ProfessorListEntry.tscn not preloaded.")
	if not TimetableGridScene: printerr("SchedulingUI: CRITICAL - TimetableGrid.tscn not preloaded.")

	if not is_instance_valid(academic_manager):
		printerr("SchedulingUI: AcademicManager not assigned in editor. Attempting fallback.")
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager") # Adjust path
		if not is_instance_valid(academic_manager):
			printerr("SchedulingUI: CRITICAL - AcademicManager still not found. UI cannot function.")
			return

	if not is_instance_valid(professor_manager):
		printerr("SchedulingUI: ProfessorManager not assigned in editor. Attempting fallback.")
		professor_manager = get_node_or_null("/root/MainScene/ProfessorManager") # Adjust path
		if not is_instance_valid(professor_manager):
			printerr("SchedulingUI: CRITICAL - ProfessorManager not found. Professor assignment will not work.")
			# Professor list will show an error if manager is missing

	# Connect signals from AcademicManager
	if academic_manager.has_signal("course_offerings_updated"):
		if not academic_manager.is_connected("course_offerings_updated", Callable(self, "_on_academic_manager_course_offerings_updated")):
			academic_manager.course_offerings_updated.connect(Callable(self, "_on_academic_manager_course_offerings_updated"))
	if academic_manager.has_signal("schedules_updated"):
		if not academic_manager.is_connected("schedules_updated", Callable(self, "_on_academic_manager_schedules_updated")):
			academic_manager.schedules_updated.connect(Callable(self, "_on_academic_manager_schedules_updated"))
	
	# Connect to ProfessorManager signal
	if is_instance_valid(professor_manager) and professor_manager.has_signal("faculty_list_updated"):
		if not professor_manager.is_connected("faculty_list_updated", Callable(self, "_on_faculty_list_updated")):
			professor_manager.faculty_list_updated.connect(Callable(self, "_on_faculty_list_updated"))

	call_deferred("refresh_ui")

func refresh_ui():
	_refresh_unscheduled_courses_list()
	_populate_professor_list() # Populate/Repopulate professor list
	_refresh_classroom_tabs_and_schedules()

func _refresh_unscheduled_courses_list():
	if not is_instance_valid(unscheduled_courses_list_vbox) or \
	   not is_instance_valid(academic_manager) or \
	   not UnscheduledCourseEntryScene:
		if DETAILED_LOGGING_ENABLED: print_debug("Cannot refresh unscheduled courses: component missing.")
		return

	for child in unscheduled_courses_list_vbox.get_children():
		child.queue_free()

	var unscheduled_offerings = academic_manager.get_unscheduled_course_offerings()
	if unscheduled_offerings.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No courses to schedule."
		unscheduled_courses_list_vbox.add_child(empty_label)
		return

	for offering_data in unscheduled_offerings:
		var entry_instance = UnscheduledCourseEntryScene.instantiate()
		if is_instance_valid(entry_instance):
			unscheduled_courses_list_vbox.add_child(entry_instance)
			if entry_instance.has_method("setup"):
				entry_instance.setup(offering_data, academic_manager)
				# Optional: connect to a signal from entry_instance if you want to filter professor list
				# when an UnscheduledCourseEntry is selected or its drag starts.
				# Example:
				# if not entry_instance.is_connected("course_interaction_started", Callable(self, "_on_unscheduled_course_interaction")):
				# 	entry_instance.course_interaction_started.connect(Callable(self, "_on_unscheduled_course_interaction"))
		else:
			printerr("Failed to instantiate UnscheduledCourseEntryScene.")

# func _on_unscheduled_course_interaction(course_id: String):
# 	# Called when an unscheduled course is clicked or drag starts (if you implement that signal)
# 	if DETAILED_LOGGING_ENABLED: print_debug("Interaction with course_id: %s. Refreshing professor list (filtered)." % course_id)
# 	_populate_professor_list(course_id) # Pass course_id for filtering

func _populate_professor_list(filter_course_id: String = ""):
	if not is_instance_valid(professor_list_vbox):
		if DETAILED_LOGGING_ENABLED: print_debug("ProfessorListVBox not valid for populating.")
		return
		
	for child in professor_list_vbox.get_children():
		child.queue_free()

	if not is_instance_valid(professor_manager) or not ProfessorListEntryScene:
		var error_label = Label.new()
		error_label.text = "Professor system N/A."
		professor_list_vbox.add_child(error_label)
		if DETAILED_LOGGING_ENABLED: print_debug("Cannot populate professor list: ProfessorManager or Scene missing.")
		return

	var hired_profs: Array[Professor] = professor_manager.get_hired_professors()
	
	# --- Start Advanced Filtering Logic (Optional) ---
	var course_target_spec: Professor.Specialization # Using uninitialized type for later check
	var filter_by_specialization = false
	if not filter_course_id.is_empty() and is_instance_valid(academic_manager):
		# You'd need a method in AcademicManager like get_course_details_by_course_id(filter_course_id)
		# that returns a dictionary or object with course's required specialization.
		# For now, this part is conceptual. Assume academic_manager can provide specialization enum.
		# var course_details = academic_manager.get_course_definition(filter_course_id) # Example method
		# if course_details and course_details.has("required_specialization_enum"):
		# 	course_target_spec = course_details.required_specialization_enum
		# 	filter_by_specialization = true
		# 	if DETAILED_LOGGING_ENABLED: print_debug("Filtering prof list for spec: %s" % Professor.Specialization.keys()[course_target_spec])
		pass # Placeholder for filter activation
	# --- End Advanced Filtering Logic ---

	if hired_profs.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No professors hired."
		professor_list_vbox.add_child(empty_label)
		return

	var professors_added_count = 0
	for prof in hired_profs:
		# if filter_by_specialization:
		# 	# Professor must match specific course spec, or be a generalist if course allows,
		# 	# or course must be general if prof is generalist.
		# 	var prof_spec = prof.specialization
		# 	if prof_spec != course_target_spec and \
		# 	   prof_spec != Professor.Specialization.GENERAL and \
		# 	   course_target_spec != Professor.Specialization.GENERAL:
		# 		continue # Skip this professor if specializations don't align strictly

		var entry_instance = ProfessorListEntryScene.instantiate()
		if is_instance_valid(entry_instance):
			professor_list_vbox.add_child(entry_instance)
			if entry_instance.has_method("setup"):
				entry_instance.setup(prof)
				# Optional: Connect to signals from ProfessorListEntry for advanced overlay control
				# if not entry_instance.is_connected("professor_drag_started", Callable(self, "_on_professor_drag_started")):
				# 	entry_instance.professor_drag_started.connect(Callable(self, "_on_professor_drag_started"))
				professors_added_count += 1
		else:
			printerr("Failed to instantiate ProfessorListEntryScene.")
	
	if professors_added_count == 0 and filter_by_specialization: # Only show if filtering was active
		var no_match_label = Label.new(); no_match_label.text = "No professors match specialization."
		professor_list_vbox.add_child(no_match_label)
	elif professors_added_count == 0 and hired_profs.size() > 0: # Should mean all were filtered out
		var empty_filter_label = Label.new(); empty_filter_label.text = "No professors match filter."
		professor_list_vbox.add_child(empty_filter_label)


	if DETAILED_LOGGING_ENABLED: print_debug("Professor list populated with %d professors." % professors_added_count)


func _refresh_classroom_tabs_and_schedules():
	if not is_instance_valid(classroom_tabs) or \
	   not is_instance_valid(academic_manager) or \
	   not TimetableGridScene:
		printerr("SchedulingUI: Cannot refresh classroom tabs, critical component missing.")
		return

	var current_tab_idx = classroom_tabs.current_tab
	
	var children_to_remove = classroom_tabs.get_children()
	for child in children_to_remove:
		classroom_tabs.remove_child(child)
		child.queue_free()

	var available_classrooms = academic_manager.get_available_classrooms()

	if available_classrooms.is_empty():
		var placeholder_panel = Panel.new()
		var no_classrooms_label = Label.new()
		no_classrooms_label.text = "No classrooms available. Build some!"
		no_classrooms_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_classrooms_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_classrooms_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		no_classrooms_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		no_classrooms_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		placeholder_panel.name = "Status"
		placeholder_panel.add_child(no_classrooms_label)
		placeholder_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		classroom_tabs.add_child(placeholder_panel)
		return

	for classroom_data in available_classrooms:
		var classroom_id = classroom_data.id
		var timetable_grid_instance = TimetableGridScene.instantiate()
		if is_instance_valid(timetable_grid_instance):
			timetable_grid_instance.name = "Classroom %s" % classroom_id.right(5) # Shorten ID for tab name
			
			# For advanced overlay: Pass reference to this SchedulingUI instance
			# if timetable_grid_instance.has_method("set_scheduling_ui_parent"):
			# 	timetable_grid_instance.set_scheduling_ui_parent(self)

			classroom_tabs.add_child(timetable_grid_instance)
			
			if timetable_grid_instance.has_method("setup_grid"):
				if not is_instance_valid(self.professor_manager):
					printerr("SchedulingUI: ProfessorManager is INVALID when trying to setup TimetableGrid for classroom %s." % classroom_id)
				# Pass the SchedulingPanel's professor_manager reference
				timetable_grid_instance.setup_grid(classroom_id, academic_manager, self.professor_manager)
			else:
				printerr("SchedulingUI: TimetableGrid instance for classroom '", classroom_id, "' is missing setup_grid() method.")
		else:
			printerr("SchedulingUI: Failed to instantiate TimetableGridScene for classroom ", classroom_id)

	if current_tab_idx >= 0 and current_tab_idx < classroom_tabs.get_tab_count():
		classroom_tabs.current_tab = current_tab_idx
	elif classroom_tabs.get_tab_count() > 0:
		classroom_tabs.current_tab = 0

# --- Signal Handlers ---
func _on_academic_manager_course_offerings_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received course_offerings_updated. Refreshing unscheduled courses list.")
	_refresh_unscheduled_courses_list()
	# If professor list is filtered by selected unscheduled course, it might need refresh too:
	# _populate_professor_list() # Or with a specific filter_course_id if one is "active"

func _on_academic_manager_schedules_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received schedules_updated. Refreshing classroom schedules.")
	_refresh_classroom_tabs_and_schedules() # This makes TimetableGrid redraw its cells

func _on_faculty_list_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received faculty_list_updated. Refreshing professor list.")
	_populate_professor_list() # Refresh with current filter (if any)

# --- Overlay Management Functions (Advanced - called by draggable items if they emit signals) ---
# func _on_professor_drag_started(professor_id: String):
# 	_current_drag_type = "professor"
# 	_dragged_professor_id = professor_id
# 	var current_grid = classroom_tabs.get_current_tab_control()
# 	if is_instance_valid(current_grid) and current_grid.has_method("show_professor_availability_overlay"):
# 		current_grid.show_professor_availability_overlay(_dragged_professor_id)
#
# func _on_drag_ended_anywhere(): # Needs a more robust global drag end signal
# 	if _current_drag_type == "professor":
# 		var current_grid = classroom_tabs.get_current_tab_control()
# 		if is_instance_valid(current_grid) and current_grid.has_method("clear_professor_availability_overlay"):
# 			current_grid.clear_professor_availability_overlay()
# 	_current_drag_type = ""
# 	_dragged_professor_id = ""

# --- UI Visibility ---
func show_panel():
	self.visible = true
	call_deferred("refresh_ui") # Refresh when shown

func hide_panel():
	self.visible = false
	# Optional: clear any drag states if panel is hidden mid-drag
	# _on_drag_ended_anywhere()


# --- Debug Utility ---
func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[SchedulingUI]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: final_message += String(" ").join(message_parts.map(func(x):return str(x)))
	else: final_message += str(message_parts)
	print(final_message)

# Helper for TimetableGrid to get ProfessorManager ref (if needed, though it's passed in setup_grid)
# func get_professor_manager_ref() -> ProfessorManager:
# 	return professor_manager
