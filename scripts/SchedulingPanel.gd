# SchedulingUI.gd
# Script for the main class scheduling panel.
extends PanelContainer

# --- Node References ---
@export var academic_manager: AcademicManager
@export var professor_manager: ProfessorManager # <<< NEW - Assign in Editor

# It's generally more robust to use @onready for nodes within this scene's direct tree
@onready var unscheduled_courses_list_vbox: VBoxContainer = $MainHSplit/UnscheduledCoursesArea/UnscheduledVBox/UnscheduledScroll/UnscheduledCoursesListVBox
@onready var classroom_tabs: TabContainer = $MainHSplit/ClassroomSchedulesArea/ClassroomSchedulesVBox/ClassroomTabs
@onready var instructor_dropdown: OptionButton = $MainHSplit/UnscheduledCoursesArea/UnscheduledVBox/InstructorSelectHBox/InstructorDropdown # <<< NEW - Add HBoxContainer with Label and OptionButton in your scene

# --- Scene Preloads ---
const UnscheduledCourseEntryScene: PackedScene = preload("res://scenes/UnscheduledCourseEntry.tscn")
const TimetableGridScene: PackedScene = preload("res://scenes/TimetableGrid.tscn")

# --- State ---
var _available_professors_for_dropdown: Array[Professor] = [] # To map dropdown index to Professor object

const DETAILED_LOGGING_ENABLED: bool = true # For this script's debug messages

# --- Initialization ---
func _ready():
	# Validate critical node references
	if not is_instance_valid(unscheduled_courses_list_vbox):
		printerr("SchedulingUI: UnscheduledCoursesListVBox node not found! Check path: MainHSplit/UnscheduledCoursesArea/UnscheduledVBox/UnscheduledScroll/UnscheduledCoursesListVBox")
	if not is_instance_valid(classroom_tabs):
		printerr("SchedulingUI: ClassroomTabs node not found! Check path: MainHSplit/ClassroomSchedulesArea/ClassroomSchedulesVBox/ClassroomTabs")
	if not is_instance_valid(instructor_dropdown): # NEW Check
		printerr("SchedulingUI: InstructorDropdown node not found! Check path (e.g., MainHSplit/UnscheduledCoursesArea/UnscheduledVBox/InstructorSelectHBox/InstructorDropdown)")

	if not UnscheduledCourseEntryScene: printerr("SchedulingUI: CRITICAL - UnscheduledCourseEntry.tscn not preloaded.")
	if not TimetableGridScene: printerr("SchedulingUI: CRITICAL - TimetableGrid.tscn not preloaded.")

	if not is_instance_valid(academic_manager):
		printerr("SchedulingUI: AcademicManager not assigned in editor. Attempting fallback.")
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager") # Adjust path
		if not is_instance_valid(academic_manager):
			printerr("SchedulingUI: CRITICAL - AcademicManager still not found. UI cannot function.")
			return # Cannot function without AcademicManager

	if not is_instance_valid(professor_manager): # NEW Fallback
		printerr("SchedulingUI: ProfessorManager not assigned in editor. Attempting fallback.")
		professor_manager = get_node_or_null("/root/MainScene/ProfessorManager") # Adjust path
		if not is_instance_valid(professor_manager):
			printerr("SchedulingUI: CRITICAL - ProfessorManager not found. Professor assignment will not work.")
			# Instructor dropdown will be disabled by _populate_instructor_dropdown if manager is missing

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
	_refresh_classroom_tabs_and_schedules()
	_populate_instructor_dropdown() # Populate/Repopulate professor dropdown

func _refresh_unscheduled_courses_list():
	if not is_instance_valid(unscheduled_courses_list_vbox) or \
	   not is_instance_valid(academic_manager) or \
	   not UnscheduledCourseEntryScene:
		# printerr("SchedulingUI: Cannot refresh unscheduled courses list, component missing.") # Can be noisy
		return

	for child in unscheduled_courses_list_vbox.get_children():
		child.queue_free()

	var unscheduled_offerings = academic_manager.get_unscheduled_course_offerings()
	if unscheduled_offerings.is_empty():
		var empty_label = Label.new(); empty_label.text = "No courses to schedule."
		unscheduled_courses_list_vbox.add_child(empty_label)
		return

	for offering_data in unscheduled_offerings:
		var entry_instance = UnscheduledCourseEntryScene.instantiate()
		if is_instance_valid(entry_instance):
			unscheduled_courses_list_vbox.add_child(entry_instance)
			if entry_instance.has_method("setup"): # Pass AcademicManager for any actions on the entry
				entry_instance.setup(offering_data, academic_manager) # MODIFIED if setup needs AM
			# else: printerr("UnscheduledCourseEntry missing setup()")
		# else: printerr("Failed to instantiate UnscheduledCourseEntryScene.")

func _refresh_classroom_tabs_and_schedules():
	if not is_instance_valid(classroom_tabs) or \
	   not is_instance_valid(academic_manager) or \
	   not TimetableGridScene:
		printerr("SchedulingUI: Cannot refresh classroom tabs, critical component missing.")
		return

	var current_tab_idx = classroom_tabs.current_tab
	
	# Clear existing tabs
	var children_to_remove = classroom_tabs.get_children()
	for child in children_to_remove:
		classroom_tabs.remove_child(child)
		child.queue_free()

	var available_classrooms = academic_manager.get_available_classrooms()

	if available_classrooms.is_empty():
		var placeholder_panel = Panel.new()
		var no_classrooms_label = Label.new()
		no_classrooms_label.text = "No classrooms available. Build some 'Class' type rooms!"
		# ... (setup for no_classrooms_label) ...
		placeholder_panel.name = "Status"
		placeholder_panel.add_child(no_classrooms_label)
		classroom_tabs.add_child(placeholder_panel)
		return

	for classroom_data in available_classrooms:
		var classroom_id = classroom_data.id
		var timetable_grid_instance = TimetableGridScene.instantiate()
		if is_instance_valid(timetable_grid_instance):
			timetable_grid_instance.name = "Classroom %s" % classroom_id.right(5)
			classroom_tabs.add_child(timetable_grid_instance)
			
			if timetable_grid_instance.has_method("setup_grid"):
				# Ensure self.professor_manager is valid before passing
				if not is_instance_valid(self.professor_manager):
					printerr("SchedulingUI: ProfessorManager is INVALID when trying to setup TimetableGrid for classroom %s." % classroom_id)
				# Pass the SchedulingPanel's professor_manager reference
				timetable_grid_instance.setup_grid(classroom_id, academic_manager, self.professor_manager) # <<< CORRECTED: Pass professor_manager
			else:
				printerr("SchedulingUI: TimetableGrid instance for classroom '", classroom_id, "' is missing setup_grid() method.")
		else:
			printerr("SchedulingUI: Failed to instantiate TimetableGridScene for classroom ", classroom_id)

	# Try to restore previously selected tab
	if current_tab_idx >= 0 and current_tab_idx < classroom_tabs.get_tab_count():
		classroom_tabs.current_tab = current_tab_idx
	elif classroom_tabs.get_tab_count() > 0:
		classroom_tabs.current_tab = 0


func _populate_instructor_dropdown():
	if not is_instance_valid(instructor_dropdown):
		if DETAILED_LOGGING_ENABLED: print_debug("Instructor dropdown node not available for population.")
		return
	if not is_instance_valid(professor_manager):
		instructor_dropdown.clear()
		instructor_dropdown.add_item("Professor System N/A", -1) # Metadata -1 for unassigned/error
		instructor_dropdown.disabled = true
		if DETAILED_LOGGING_ENABLED: print_debug("ProfessorManager not available for instructor dropdown.")
		return

	instructor_dropdown.clear()
	_available_professors_for_dropdown.clear()
	instructor_dropdown.disabled = false
	
	# Add "Unassigned" option first, its metadata will be -1 (or another special value)
	instructor_dropdown.add_item("Unassigned / TBA", -1) 

	var hired_profs: Array[Professor] = professor_manager.get_hired_professors()
	var dropdown_item_id_counter = 0 # This will be the ID stored in OptionButton, mapping to _available_professors_for_dropdown index
	for prof in hired_profs:
		# TODO: Add filtering here based on course specialization if UnscheduledCourseEntry drag data provides course_id
		# For now, list all hired professors
		var display_text = "%s (%s)" % [prof.professor_name, prof.get_specialization_string()]
		instructor_dropdown.add_item(display_text, dropdown_item_id_counter) # Store index as metadata
		_available_professors_for_dropdown.append(prof) # Store the Professor object
		dropdown_item_id_counter += 1

	if instructor_dropdown.item_count > 0:
		instructor_dropdown.select(0) # Select "Unassigned" by default
	if DETAILED_LOGGING_ENABLED: print_debug("Instructor dropdown populated with %d professors." % _available_professors_for_dropdown.size())

# This function will be called by TimetableGrid when a drop happens
func get_selected_instructor_id_for_scheduling() -> String:
	if not is_instance_valid(instructor_dropdown) or instructor_dropdown.disabled:
		if DETAILED_LOGGING_ENABLED: print_debug("Instructor dropdown not valid or disabled, returning no instructor.")
		return ""

	var selected_idx_in_dropdown = instructor_dropdown.selected 
	if selected_idx_in_dropdown < 0: # No item selected in the OptionButton
		if DETAILED_LOGGING_ENABLED: print_debug("No item selected in instructor dropdown, returning no instructor.")
		return ""

	var selected_metadata = instructor_dropdown.get_item_metadata(selected_idx_in_dropdown)
	
	# --- ADD THIS CHECK FOR NULL METADATA ---
	if selected_metadata == null:
		if DETAILED_LOGGING_ENABLED: 
			print_debug("Selected item in dropdown (index %d) has null metadata. Returning no instructor." % selected_idx_in_dropdown)
		return "" # Treat as unassigned or error

	# Now selected_metadata is guaranteed not to be null
	if selected_metadata == -1: # Our special value for "Unassigned / TBA"
		if DETAILED_LOGGING_ENABLED: print_debug("Instructor dropdown: 'Unassigned / TBA' selected.")
		return "" 
	
	# If metadata is not -1, it should be a valid index for _available_professors_for_dropdown
	if selected_metadata >= 0 and selected_metadata < _available_professors_for_dropdown.size():
		if is_instance_valid(_available_professors_for_dropdown[selected_metadata]):
			if DETAILED_LOGGING_ENABLED: 
				print_debug("Instructor selected: %s" % _available_professors_for_dropdown[selected_metadata].professor_name)
			return _available_professors_for_dropdown[selected_metadata].professor_id
		else:
			if DETAILED_LOGGING_ENABLED: 
				print_debug("Error: Stored professor object at metadata index %d is invalid." % selected_metadata)
			return ""
	
	if DETAILED_LOGGING_ENABLED: 
		print_debug("Instructor dropdown selection metadata (%s) out of range for _available_professors_for_dropdown (size %d)." % [str(selected_metadata), _available_professors_for_dropdown.size()])
	return "" # Default to unassigned if something is wrong


# --- Signal Handlers ---
func _on_academic_manager_course_offerings_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received course_offerings_updated. Refreshing unscheduled courses list.")
	_refresh_unscheduled_courses_list()

func _on_academic_manager_schedules_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Received schedules_updated. Refreshing classroom schedules.")
	_refresh_classroom_tabs_and_schedules()

func _on_faculty_list_updated(): # NEW
	if DETAILED_LOGGING_ENABLED: print_debug("Received faculty_list_updated. Refreshing instructor dropdown.")
	_populate_instructor_dropdown()

func show_panel():
	self.visible = true
	call_deferred("refresh_ui")

func hide_panel():
	self.visible = false

func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return # Add this check if you define the const
	var final_message = "[SchedulingUI]: "
	# ... (your existing print_debug logic) ...
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: final_message += String(" ").join(message_parts.map(func(x):return str(x)))
	else: final_message += str(message_parts)
	print(final_message)

# Helper for TimetableGrid to get ProfessorManager ref (alternative to complex get_parent chains)
func get_professor_manager_ref() -> ProfessorManager:
	return professor_manager
