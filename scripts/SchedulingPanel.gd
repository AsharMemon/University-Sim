# SchedulingUI.gd
# Script for the main class scheduling panel.
extends PanelContainer

# --- Node References ---
@export var academic_manager: AcademicManager

@onready var unscheduled_courses_list_vbox: VBoxContainer = get_node_or_null("MainHSplit/UnscheduledCoursesArea/UnscheduledVBox/UnscheduledScroll/UnscheduledCoursesListVBox")
@onready var classroom_tabs: TabContainer = get_node_or_null("MainHSplit/ClassroomSchedulesArea/ClassroomSchedulesVBox/ClassroomTabs")

# --- Scene Preloads ---
const UnscheduledCourseEntryScene: PackedScene = preload("res://scenes/UnscheduledCourseEntry.tscn") # ADJUST PATH if different
const TimetableGridScene: PackedScene = preload("res://scenes/TimetableGrid.tscn") # ADJUST PATH if different

# --- Initialization ---
func _ready():
	# Validate critical node references
	if not is_instance_valid(unscheduled_courses_list_vbox):
		printerr("SchedulingUI: UnscheduledCoursesListVBox node not found! Check path.")
		return
	if not is_instance_valid(classroom_tabs):
		printerr("SchedulingUI: ClassroomTabs node not found! Check path.")
		return
	if not UnscheduledCourseEntryScene:
		printerr("SchedulingUI: CRITICAL - UnscheduledCourseEntry.tscn not preloaded. Check path.")
		return
	if not TimetableGridScene:
		printerr("SchedulingUI: CRITICAL - TimetableGrid.tscn not preloaded. Check path.")
		return

	# Get AcademicManager if not assigned in editor (fallback)
	if not is_instance_valid(academic_manager):
		printerr("SchedulingUI: AcademicManager not assigned in editor. Attempting fallback.")
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager") # Adjust path if needed
		if not is_instance_valid(academic_manager):
			printerr("SchedulingUI: CRITICAL - AcademicManager not found. UI cannot function.")
			return

	# Connect to signals from AcademicManager to refresh UI when data changes
	# Ensure signals are connected only once.
	if not academic_manager.is_connected("course_offerings_updated", Callable(self, "_on_academic_manager_course_offerings_updated")):
		var err_co = academic_manager.connect("course_offerings_updated", Callable(self, "_on_academic_manager_course_offerings_updated"))
		if err_co != OK: printerr("SchedulingUI: Failed to connect to course_offerings_updated. Error: ", err_co)
	
	if not academic_manager.is_connected("schedules_updated", Callable(self, "_on_academic_manager_schedules_updated")):
		var err_su = academic_manager.connect("schedules_updated", Callable(self, "_on_academic_manager_schedules_updated"))
		if err_su != OK: printerr("SchedulingUI: Failed to connect to schedules_updated. Error: ", err_su)
	
	# Initial population
	call_deferred("refresh_ui") # Use call_deferred to ensure AcademicManager is fully ready

	# This panel should probably be hidden by default and shown by another button
	# self.visible = false 

# --- UI Refresh Functions ---
func refresh_ui():
	_refresh_unscheduled_courses_list()
	_refresh_classroom_tabs_and_schedules()

func _refresh_unscheduled_courses_list():
	if not is_instance_valid(unscheduled_courses_list_vbox) or \
	   not is_instance_valid(academic_manager) or \
	   not UnscheduledCourseEntryScene:
		printerr("SchedulingUI: Cannot refresh unscheduled courses list, critical component missing.")
		return

	# Clear existing entries
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
				entry_instance.setup(offering_data)
			else:
				printerr("SchedulingUI: UnscheduledCourseEntry instance is missing setup() method.")
		else:
			printerr("SchedulingUI: Failed to instantiate UnscheduledCourseEntryScene.")


func _refresh_classroom_tabs_and_schedules():
	if not is_instance_valid(classroom_tabs) or \
	   not is_instance_valid(academic_manager) or \
	   not TimetableGridScene:
		printerr("SchedulingUI: Cannot refresh classroom tabs, critical component missing.")
		return

	var current_tab_idx = classroom_tabs.current_tab
	
	# Clear existing tabs by removing their content nodes
	var children_to_remove = classroom_tabs.get_children()
	for child in children_to_remove:
		classroom_tabs.remove_child(child) 
		child.queue_free() 

	var available_classrooms = academic_manager.get_available_classrooms()

	if available_classrooms.is_empty():
		var placeholder_panel = Panel.new() 
		var no_classrooms_label = Label.new()
		no_classrooms_label.text = "No classrooms available. Build some 'Class' type rooms!"
		no_classrooms_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_classrooms_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_classrooms_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		no_classrooms_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		placeholder_panel.add_child(no_classrooms_label)
		# Set the name of the placeholder_panel, TabContainer uses this for the tab title
		placeholder_panel.name = "Status" 
		classroom_tabs.add_child(placeholder_panel)
		return

	for classroom_data in available_classrooms:
		var classroom_id = classroom_data.id
		# var classroom_capacity = classroom_data.capacity # Capacity not used in grid display yet

		var timetable_grid_instance = TimetableGridScene.instantiate()
		if is_instance_valid(timetable_grid_instance):
			# Set the name of the root node of TimetableGridScene instance for the tab title
			timetable_grid_instance.name = "Classroom %s" % classroom_id.right(5) # Shorten ID for tab name
			classroom_tabs.add_child(timetable_grid_instance)
			
			if timetable_grid_instance.has_method("setup_grid"):
				timetable_grid_instance.setup_grid(classroom_id, academic_manager)
			else:
				printerr("SchedulingUI: TimetableGrid instance for classroom '", classroom_id, "' is missing setup_grid() method.")
		else:
			printerr("SchedulingUI: Failed to instantiate TimetableGridScene for classroom ", classroom_id)

	# Try to restore previously selected tab if possible
	if current_tab_idx >= 0 and current_tab_idx < classroom_tabs.get_tab_count():
		classroom_tabs.current_tab = current_tab_idx
	elif classroom_tabs.get_tab_count() > 0:
		classroom_tabs.current_tab = 0

# --- Signal Handlers from AcademicManager ---
func _on_academic_manager_course_offerings_updated():
	print_debug("Received course_offerings_updated. Refreshing unscheduled courses list.")
	_refresh_unscheduled_courses_list()

func _on_academic_manager_schedules_updated():
	print_debug("Received schedules_updated. Refreshing classroom tabs and schedules.")
	# This will re-create the timetable grids, which will in turn call their _display_scheduled_classes
	_refresh_classroom_tabs_and_schedules() 

# --- Public functions to control visibility (called by e.g., BuildingManager) ---
func show_panel():
	self.visible = true
	call_deferred("refresh_ui") # Refresh content when shown, deferred to ensure all nodes are ready

func hide_panel():
	self.visible = false

# --- Helper Functions ---
func print_debug(message_parts):
	var final_message = "[SchedulingUI]: "
	if typeof(message_parts) == TYPE_STRING:
		final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY or typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : Array = message_parts
		final_message += " ".join(temp_array)
	else:
		final_message += str(message_parts)
	print(final_message)
