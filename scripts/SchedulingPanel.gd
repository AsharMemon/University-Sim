# SchedulingPanel.gd
class_name SchedulingPanel
extends PanelContainer

# --- Node References ---
@export var academic_manager: AcademicManager
@export var professor_manager: ProfessorManager

@export var unscheduled_courses_list_vbox: VBoxContainer
@export var professor_list_vbox: VBoxContainer
@export var classroom_tabs: TabContainer

# --- Scene Preloads ---
const UnscheduledCourseEntryScene: PackedScene = preload("res://scenes/UnscheduledCourseEntry.tscn")
const ProfessorListEntryScene: PackedScene = preload("res://scenes/ProfessorListEntry.tscn")
const TimetableGridScene: PackedScene = preload("res://scenes/TimetableGrid.tscn")

# --- State for Overlay ---
var _is_professor_being_dragged_for_overlay: bool = false
var _dragged_professor_id_for_overlay: String = ""

const DETAILED_LOGGING_ENABLED: bool = true

# --- Initialization ---
func _ready():
	if not is_instance_valid(unscheduled_courses_list_vbox):
		printerr("SchedulingPanel: UnscheduledCoursesListVBox node not found! Check path.")
	if not is_instance_valid(professor_list_vbox):
		printerr("SchedulingPanel: ProfessorListVBox node not found! Check path.")
	if not is_instance_valid(classroom_tabs):
		printerr("SchedulingPanel: ClassroomTabs node not found! Check path.")

	if not UnscheduledCourseEntryScene: printerr("SchedulingPanel: CRITICAL - UnscheduledCourseEntry.tscn not preloaded.")
	if not ProfessorListEntryScene: printerr("SchedulingPanel: CRITICAL - ProfessorListEntry.tscn not preloaded.")
	if not TimetableGridScene: printerr("SchedulingPanel: CRITICAL - TimetableGrid.tscn not preloaded.")

	if not is_instance_valid(academic_manager):
		printerr("SchedulingPanel: AcademicManager not assigned in editor. Attempting fallback.")
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager") # Adjust path
		if not is_instance_valid(academic_manager):
			printerr("SchedulingPanel: CRITICAL - AcademicManager still not found. UI cannot function.")
			return

	if not is_instance_valid(professor_manager):
		printerr("SchedulingPanel: ProfessorManager not assigned in editor. Attempting fallback.")
		professor_manager = get_node_or_null("/root/MainScene/ProfessorManager") # Adjust path
		if not is_instance_valid(professor_manager):
			printerr("SchedulingPanel: CRITICAL - ProfessorManager not found. Professor assignment will not work.")
	
	# Connect signals from AcademicManager
	if is_instance_valid(academic_manager):
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
	if DETAILED_LOGGING_ENABLED: print_debug("refresh_ui() called.")
	_refresh_unscheduled_courses_list()
	_populate_professor_list() 
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
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER # Make it look a bit better
		unscheduled_courses_list_vbox.add_child(empty_label)
		return

	for offering_data in unscheduled_offerings:
		var entry_instance = UnscheduledCourseEntryScene.instantiate()
		if is_instance_valid(entry_instance):
			unscheduled_courses_list_vbox.add_child(entry_instance)
			if entry_instance.has_method("setup"):
				entry_instance.setup(offering_data, academic_manager) # Pass academic_manager
			else:
				printerr("UnscheduledCourseEntry instance is missing setup() method.")
		else:
			printerr("Failed to instantiate UnscheduledCourseEntryScene.")


func _populate_professor_list(filter_course_id: String = ""): # filter_course_id is still conceptual
	if not is_instance_valid(professor_list_vbox):
		if DETAILED_LOGGING_ENABLED: print_debug("ProfessorListVBox not valid for populating.")
		return
		
	for child in professor_list_vbox.get_children():
		child.queue_free()

	if not is_instance_valid(professor_manager) or not ProfessorListEntryScene:
		var error_label = Label.new()
		error_label.text = "Professor system N/A."
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		professor_list_vbox.add_child(error_label)
		if DETAILED_LOGGING_ENABLED: print_debug("Cannot populate professor list: ProfessorManager or Scene missing.")
		return

	var hired_profs: Array[Professor] = professor_manager.get_hired_professors() # This returns Array[Professor]
	
	# Conceptual filtering logic - currently not active
	var filter_by_specialization = false 
	# if not filter_course_id.is_empty():
	#	 # Logic to get course_target_spec and set filter_by_specialization = true
	#	 pass

	if hired_profs.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No professors hired."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		professor_list_vbox.add_child(empty_label)
		return

	var professors_added_count = 0
	for prof_data_object in hired_profs: # prof_data_object is a Professor data object
		# Conceptual filter application
		# if filter_by_specialization:
		#     # ... (your filter logic here) ...
		#     continue # Skip if professor doesn't match filter

		var entry_instance = ProfessorListEntryScene.instantiate()
		if is_instance_valid(entry_instance):
			professor_list_vbox.add_child(entry_instance)
			if entry_instance.has_method("setup"):
				entry_instance.setup(prof_data_object) # Pass the Professor data object
				professors_added_count += 1
				# Connect to drag signals from ProfessorListEntry
				if entry_instance.has_signal("professor_drag_started"):
					if not entry_instance.is_connected("professor_drag_started", Callable(self, "_on_professor_drag_started_for_overlay")):
						entry_instance.professor_drag_started.connect(Callable(self, "_on_professor_drag_started_for_overlay"))
				if entry_instance.has_signal("professor_drag_ended"):
					if not entry_instance.is_connected("professor_drag_ended", Callable(self, "_on_professor_drag_ended_for_overlay")):
						entry_instance.professor_drag_ended.connect(Callable(self, "_on_professor_drag_ended_for_overlay"))
			else:
				printerr("ProfessorListEntry instance is missing setup() method.")
		else:
			printerr("Failed to instantiate ProfessorListEntryScene.")
	
	if professors_added_count == 0: # If loop ran but nothing added (e.g., due to filtering or no hired profs initially)
		var no_match_label = Label.new()
		if filter_by_specialization : # If filtering was active
			no_match_label.text = "No professors match filter."
		elif hired_profs.size() > 0 : # Hired profs exist but none were added (should not happen without filter)
			no_match_label.text = "Error populating professor list."
		# else: # This case means hired_profs was empty, already handled above.
		if not no_match_label.text.is_empty():
			no_match_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			professor_list_vbox.add_child(no_match_label)

	if DETAILED_LOGGING_ENABLED: print_debug("Professor list populated with %d professors." % professors_added_count)


func _refresh_classroom_tabs_and_schedules():
	if not is_instance_valid(classroom_tabs) or \
	   not is_instance_valid(academic_manager) or \
	   not TimetableGridScene:
		printerr("SchedulingPanel: Cannot refresh classroom tabs, critical component missing.")
		return

	var current_tab_idx = classroom_tabs.current_tab
	
	for i in range(classroom_tabs.get_tab_count() - 1, -1, -1):
		var tab_child = classroom_tabs.get_tab_control(i)
		if is_instance_valid(tab_child):
			classroom_tabs.remove_child(tab_child) 
			tab_child.queue_free()

	var available_classrooms = academic_manager.get_available_classrooms() # This returns Array[Dictionary]

	if available_classrooms.is_empty():
		var placeholder_panel = PanelContainer.new() # Use PanelContainer for better default appearance
		var no_classrooms_label = Label.new()
		no_classrooms_label.text = "No classrooms available. Build some!"
		no_classrooms_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_classrooms_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_classrooms_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		placeholder_panel.add_child(no_classrooms_label)
		# Make label fill the panel
		no_classrooms_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		no_classrooms_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		classroom_tabs.add_child(placeholder_panel)
		classroom_tabs.set_tab_title(0, "Status") # Set a title for the placeholder tab
		return

	for classroom_data in available_classrooms: # classroom_data is a Dictionary
		var classroom_id = classroom_data.get("id", "") 
		var classroom_name = classroom_data.get("name", "Classroom %s" % classroom_id.right(5))

		if classroom_id.is_empty():
			printerr("SchedulingPanel: Classroom data found with empty ID. Skipping.")
			continue

		var timetable_grid_instance = TimetableGridScene.instantiate() as TimetableGrid
		if is_instance_valid(timetable_grid_instance):
			timetable_grid_instance.name = classroom_name # Node name for the tab title
			classroom_tabs.add_child(timetable_grid_instance)
			
			if timetable_grid_instance.has_method("setup_grid"):
				if not is_instance_valid(self.professor_manager): # Check self.professor_manager
					printerr("SchedulingPanel: ProfessorManager is INVALID when setting up TimetableGrid for %s." % classroom_id)
				timetable_grid_instance.setup_grid(classroom_id, academic_manager, self.professor_manager)
			else:
				printerr("SchedulingPanel: TimetableGrid for '%s' missing setup_grid()." % classroom_id)
		else:
			printerr("SchedulingPanel: Failed to instantiate TimetableGridScene for %s" % classroom_id)

	if current_tab_idx >= 0 and current_tab_idx < classroom_tabs.get_tab_count():
		classroom_tabs.current_tab = current_tab_idx
	elif classroom_tabs.get_tab_count() > 0:
		classroom_tabs.current_tab = 0
	
	if _is_professor_being_dragged_for_overlay and not _dragged_professor_id_for_overlay.is_empty():
		var current_tab_node = classroom_tabs.get_current_tab_control()
		if is_instance_valid(current_tab_node) and current_tab_node is TimetableGrid:
			current_tab_node.display_professor_availability_overlay(_dragged_professor_id_for_overlay)


# --- Signal Handlers ---
func _on_academic_manager_course_offerings_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received course_offerings_updated. Refreshing unscheduled courses list.")
	_refresh_unscheduled_courses_list()

func _on_academic_manager_schedules_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received schedules_updated. Refreshing classroom schedules.")
	_refresh_classroom_tabs_and_schedules()

func _on_faculty_list_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received faculty_list_updated. Refreshing professor list.")
	_populate_professor_list()

# --- UI Visibility ---
func show_panel():
	self.visible = true
	call_deferred("refresh_ui") 

func hide_panel():
	self.visible = false
	if _is_professor_being_dragged_for_overlay:
		_on_professor_drag_ended_for_overlay() # Clear overlay if panel is hidden mid-drag

# --- Professor Drag Overlay Signal Handlers ---
func _on_professor_drag_started_for_overlay(professor_id: String):
	if DETAILED_LOGGING_ENABLED: print_debug(["Professor drag started for overlay. Prof ID:", professor_id])
	_is_professor_being_dragged_for_overlay = true
	_dragged_professor_id_for_overlay = professor_id
	
	var current_tab_node = classroom_tabs.get_current_tab_control()
	if is_instance_valid(current_tab_node) and current_tab_node is TimetableGrid:
		var current_timetable_grid: TimetableGrid = current_tab_node
		if current_timetable_grid.has_method("display_professor_availability_overlay"):
			current_timetable_grid.display_professor_availability_overlay(_dragged_professor_id_for_overlay)

func _on_professor_drag_ended_for_overlay():
	if not _is_professor_being_dragged_for_overlay: return
	if DETAILED_LOGGING_ENABLED: print_debug(["Professor drag ended for overlay. Clearing."])
	
	var current_tab_node = classroom_tabs.get_current_tab_control()
	if is_instance_valid(current_tab_node) and current_tab_node is TimetableGrid:
		var current_timetable_grid: TimetableGrid = current_tab_node
		if current_timetable_grid.has_method("clear_professor_availability_overlay"):
			current_timetable_grid.clear_professor_availability_overlay()

	_is_professor_being_dragged_for_overlay = false
	_dragged_professor_id_for_overlay = ""

# --- Debug Utility ---
func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[SchedulingPanel]: " 
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: 
		var string_array : Array[String] = [] # Explicit typing for map lambda
		for item in message_parts: string_array.append(str(item))
		final_message += String(" ").join(string_array)
	else: final_message += str(message_parts)
	print(final_message)
