# ProgramManagementUI.gd
# Manages the three-panel layout for program and course information.
extends PanelContainer # Root of ProgramManagementPanel.tscn

# --- Node References (Ensure these paths match your .tscn structure) ---
@export var academic_manager: AcademicManager # Assign in editor

# Left Panel
@export var program_list_vbox: VBoxContainer # = get_node_or_null("MainMargin/MainHBox/LeftColumn/ProgramScroll/ProgramListVBox")

# Middle Panel
@export var selected_program_name_label: Label # = get_node_or_null("MainMargin/MainHBox/MiddleColumn/SelectedProgramNameLabel")
@export var course_viz_vbox: VBoxContainer # = get_node_or_null("MainMargin/MainHBox/MiddleColumn/CourseVizScroll/CourseVizVBox")

# Right Panel
@export var course_name_label: Label # = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseNameLabel")
@export var course_id_label: Label # = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseIDLabel")
@export var course_credits_label: Label # = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseCreditsLabel")
@export var course_description_label: RichTextLabel # = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseDescriptionScroll/CourseDescriptionLabel")

# --- Scene Preloads ---
const ProgramEntryRowScene: PackedScene = preload("res://scenes/ProgramEntryRow.tscn")

# --- State ---
var current_selected_program_id: String = ""
var current_selected_course_id: String = ""
var program_row_nodes: Array[Node] = []

# --- Debugging ---
const DETAILED_LOGGING_ENABLED: bool = true # For this script's debug messages

# --- Initialization ---
func _ready():
	# Attempt to find nodes if not exported, or validate if exported
	# Left Panel
	if not is_instance_valid(program_list_vbox):
		program_list_vbox = get_node_or_null("MainMargin/MainHBox/LeftColumn/ProgramScroll/ProgramListVBox")

	# Middle Panel
	if not is_instance_valid(selected_program_name_label):
		selected_program_name_label = get_node_or_null("MainMargin/MainHBox/MiddleColumn/SelectedProgramNameLabel")
	if not is_instance_valid(course_viz_vbox):
		course_viz_vbox = get_node_or_null("MainMargin/MainHBox/MiddleColumn/CourseVizScroll/CourseVizVBox")

	# Right Panel
	if not is_instance_valid(course_name_label):
		course_name_label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseNameLabel")
	if not is_instance_valid(course_id_label):
		course_id_label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseIDLabel")
	if not is_instance_valid(course_credits_label):
		course_credits_label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseCreditsLabel")
	if not is_instance_valid(course_description_label):
		course_description_label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseDescriptionScroll/CourseDescriptionLabel")

	if not _validate_nodes([program_list_vbox, selected_program_name_label, course_viz_vbox,
							course_name_label, course_id_label, course_credits_label, course_description_label]):
		printerr("ProgramManagementUI: One or more critical UI nodes are missing. UI may not function correctly.")
		# You might want to disable the panel or parts of it here
		return

	if not is_instance_valid(academic_manager):
		printerr("ProgramManagementUI: AcademicManager node not assigned in editor! Trying fallback.")
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager") # Adjust fallback
		if not is_instance_valid(academic_manager):
			printerr("ProgramManagementUI: CRITICAL - AcademicManager still not found. UI will not function.")
			return
	
	if not ProgramEntryRowScene:
		printerr("ProgramManagementUI: CRITICAL - ProgramEntryRow.tscn not preloaded or path is incorrect!")
		return

	# Ensure signal is connected only once
	if academic_manager.has_signal("program_unlocked"):
		if not academic_manager.is_connected("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked")):
			var err = academic_manager.connect("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked"))
			if err != OK: printerr("ProgramManagementUI: Failed to connect to program_unlocked signal. Error: ", err)
		#else: print_debug("Already connected to program_unlocked.") # Optional log
	else:
		print_debug("AcademicManager is missing 'program_unlocked' signal.")
	
	_populate_program_list()
	_clear_middle_panel()
	_clear_right_course_details_panel()


func _validate_nodes(nodes_to_check: Array) -> bool:
	var all_valid = true
	for i in range(nodes_to_check.size()):
		var node_ref = nodes_to_check[i]
		if not is_instance_valid(node_ref):
			# Try to provide a more useful error by guessing the intended variable name (if possible)
			var node_name_hint = "Unknown Node"
			if i == 0: node_name_hint = "program_list_vbox"
			elif i == 1: node_name_hint = "selected_program_name_label"
			# ... add more hints if needed ...
			printerr("ProgramManagementUI: Critical UI node ('%s') not found. Please check scene paths/exports." % node_name_hint)
			all_valid = false
	return all_valid

func _populate_program_list():
	if not is_instance_valid(program_list_vbox):
		printerr("ProgramListVBox is not valid.")
		return
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("AcademicManager or UniversityData not valid for populating program list.")
		return
	if not ProgramEntryRowScene:
		printerr("ProgramEntryRowScene not loaded.")
		return

	for child in program_list_vbox.get_children():
		child.queue_free()
	program_row_nodes.clear()

	var univ_data: UniversityData = academic_manager.university_data
	var all_progs = univ_data.PROGRAMS # This is const PROGRAMS from UniversityData
	var prog_states = academic_manager.get_all_program_states()
	var sorted_prog_ids = all_progs.keys()
	sorted_prog_ids.sort() # Sort for consistent display order

	if sorted_prog_ids.is_empty():
		var lbl = Label.new(); lbl.text = "No programs defined."
		program_list_vbox.add_child(lbl)
		return

	for prog_id in sorted_prog_ids:
		var prog_details = all_progs[prog_id]
		if not prog_details is Dictionary:
			printerr("Program details for '", prog_id, "' is not a dictionary. Skipping.")
			continue
			
		var prog_name = prog_details.get("name", "Unnamed Program (" + prog_id + ")")
		var prog_status = prog_states.get(prog_id, "locked")

		var row_instance_node = ProgramEntryRowScene.instantiate()
		if not is_instance_valid(row_instance_node):
			printerr("Failed to instantiate ProgramEntryRowScene for program '", prog_id, "'. Skipping.")
			continue

		program_list_vbox.add_child(row_instance_node)
		program_row_nodes.append(row_instance_node)
		
		if row_instance_node.has_method("setup"):
			row_instance_node.setup(prog_id, prog_name, prog_status, academic_manager) # Pass academic_manager
			
			if row_instance_node.has_signal("unlock_requested"): # Check before connecting
				if not row_instance_node.is_connected("unlock_requested", Callable(self, "_on_program_row_unlock_requested")):
					row_instance_node.unlock_requested.connect(Callable(self, "_on_program_row_unlock_requested"))
			else: print_debug("ProgramEntryRow missing 'unlock_requested' signal for " + prog_id)
			
			if row_instance_node.has_signal("program_selected"): # Check before connecting
				if not row_instance_node.is_connected("program_selected", Callable(self, "_on_program_row_selected")):
					row_instance_node.program_selected.connect(Callable(self, "_on_program_row_selected"))
			else: print_debug("ProgramEntryRow missing 'program_selected' signal for " + prog_id)
		else:
			printerr("Instantiated ProgramEntryRow for '", prog_id, "' does not have setup(). Node: ", row_instance_node)
			row_instance_node.queue_free()
			program_row_nodes.pop_back()
	
	_update_program_selection_visuals()

func _on_program_row_unlock_requested(program_id: String): # Removed _row_instance as it's not used
	# The debug print from previous response was:
	# print_debug(">>>> ProgramManagementUI: _on_program_row_selected entered. Program ID: '", program_id, "' <<<<")
	# This should be for _on_program_row_selected. For unlock:
	print_debug("Unlock request received for program ID: '", program_id, "'")
	if not is_instance_valid(academic_manager): return
	var success = academic_manager.unlock_program(program_id)
	if not success: print_debug("Unlock failed for '", program_id, "' (e.g., insufficient funds or already unlocked).")
	# Refresh is handled by _on_academic_manager_program_unlocked

func _on_academic_manager_program_unlocked(program_id_unlocked: String): # Parameter name changed for clarity
	print_debug("Program unlocked signal received for: %s. Refreshing program list." % program_id_unlocked)
	_populate_program_list()
	if program_id_unlocked == current_selected_program_id:
		_populate_middle_course_viz(current_selected_program_id) # Refresh middle panel if the selected one was just unlocked

func _on_program_row_selected(program_id: String):
	if DETAILED_LOGGING_ENABLED: print_debug("Program row selected. Program ID: '%s'" % program_id)

	current_selected_program_id = program_id
	current_selected_course_id = ""
	
	_update_program_selection_visuals()
	_populate_middle_course_viz(program_id)
	_clear_right_course_details_panel()

func _update_program_selection_visuals():
	for row_node in program_row_nodes:
		if row_node.has_method("set_selected") and row_node.has_method("get_program_id"): # Check if it has get_program_id
			var row_prog_id = row_node.get_program_id() # Assumes ProgramEntryRow stores and provides this
			row_node.set_selected(row_prog_id == current_selected_program_id)
		elif DETAILED_LOGGING_ENABLED:
			print_debug("Row node missing set_selected or get_program_id method: " + str(row_node))


# --- Middle Panel: Course Visualization ---
func _clear_middle_panel():
	if is_instance_valid(selected_program_name_label):
		selected_program_name_label.text = "Select a Program"
	if is_instance_valid(course_viz_vbox):
		for child in course_viz_vbox.get_children():
			child.queue_free()
	# else: printerr("course_viz_vbox is NULL in _clear_middle_panel.") # Can be noisy


func _populate_middle_course_viz(program_id: String):
	if DETAILED_LOGGING_ENABLED: print_debug("Populating middle course viz for program_id: '%s'" % program_id)
	_clear_middle_panel()

	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("Middle Panel: AcademicManager or UniversityData not valid.")
		if is_instance_valid(selected_program_name_label): selected_program_name_label.text = "Error: Data System Missing"
		return

	var univ_data: UniversityData = academic_manager.university_data
	var prog_main_details = univ_data.get_program_details(program_id)

	if prog_main_details.is_empty():
		if is_instance_valid(selected_program_name_label): selected_program_name_label.text = "Program '%s' Not Found" % program_id
		printerr("Middle Panel: Program details not found for '", program_id, "'.")
		return
	
	if is_instance_valid(selected_program_name_label):
		selected_program_name_label.text = prog_main_details.get("name", program_id) + " - Curriculum"

	var program_curriculum: Dictionary = univ_data.get_program_curriculum_structure(program_id)
	if DETAILED_LOGGING_ENABLED: print_debug("Middle Panel: Curriculum for '%s': %s" % [program_id, str(program_curriculum)])

	if program_curriculum.is_empty():
		var lbl = Label.new(); lbl.text = "No structured curriculum defined for this program."
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(lbl)
		return

	# --- UPDATED YEAR AND SEMESTER KEYS FOR DISPLAY ITERATION ---
	var year_display_order = ["Year 1", "Year 2", "Year 3", "Year 4"] # Match keys in UniversityData
	var semester_display_order = ["Semester 1", "Semester 2"]       # Match keys in UniversityData
	# If you add a 3rd semester (e.g., "Summer Semester") to your curriculum structure, add it here too.

	var found_any_year_content = false
	for year_key_name in year_display_order:
		if not program_curriculum.has(year_key_name):
			continue # Skip if this year isn't defined for the program

		found_any_year_content = true
		var year_semesters_data: Dictionary = program_curriculum[year_key_name]

		var year_title_lbl = Label.new()
		year_title_lbl.text = year_key_name # Use the key name directly (e.g., "Year 1")
		year_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# ... (styling for year_title_lbl) ...
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(year_title_lbl)
		
		var semesters_layout_hbox = HBoxContainer.new()
		# ... (styling for semesters_layout_hbox) ...
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(semesters_layout_hbox)

		var semester_content_exists_for_year = false
		for semester_key_name in semester_display_order:
			var semester_courses_vbox = VBoxContainer.new()
			# ... (styling and naming for semester_courses_vbox) ...
			semesters_layout_hbox.add_child(semester_courses_vbox)

			if not year_semesters_data.has(semester_key_name):
				# ... (add placeholder label if semester data missing) ...
				continue

			semester_content_exists_for_year = true
			var semester_course_ids: Array = year_semesters_data[semester_key_name]

			var semester_title_lbl = Label.new()
			semester_title_lbl.text = semester_key_name # Use the key name (e.g., "Semester 1")
			# ... (styling for semester_title_lbl and separator) ...
			semester_courses_vbox.add_child(semester_title_lbl)
			semester_courses_vbox.add_child(HSeparator.new())

			if semester_course_ids.is_empty():
				# ... (add "No courses this semester" label) ...
				continue
			else:
				var total_credits_this_semester = 0.0 # Use float
				for course_id_val in semester_course_ids:
					if not course_id_val is String:
						printerr("Non-string course ID: ", course_id_val, " in ", program_id, "/", year_key_name, "/", semester_key_name)
						continue

					var course_data_dict = univ_data.get_course_details(course_id_val)
					var course_name_val = course_id_val
					var course_credits_val = 0.0 # Use float
					
					if not course_data_dict.is_empty():
						course_name_val = course_data_dict.get("name", course_id_val)
						course_credits_val = course_data_dict.get("credits", 0.0) # Ensure float from data
						total_credits_this_semester += course_credits_val
					# ... (create course_item_button, set text with "%.1f cr" % course_credits_val, connect signal) ...
					var course_item_button = Button.new()
					course_item_button.text = "%s - %s (%.1f cr)" % [course_id_val, course_name_val, course_credits_val]
					# ... (tooltip, size_flags, connect pressed signal to _on_course_viz_item_selected.bind(course_id_val)) ...
					var connect_callable = Callable(self, "_on_course_viz_item_selected").bind(course_id_val)
					if not course_item_button.is_connected("pressed", connect_callable):
						course_item_button.pressed.connect(connect_callable)
					semester_courses_vbox.add_child(course_item_button)
				
				var total_credits_label = Label.new()
				total_credits_label.text = "Semester Credits: %.1f" % total_credits_this_semester # Format as float
				# ... (styling for total_credits_label) ...
				semester_courses_vbox.add_child(total_credits_label)
		
		if not semester_content_exists_for_year:
			# ... (add placeholder if no semesters had content for this year) ...
			pass # Or add a label to semesters_layout_hbox

		if is_instance_valid(course_viz_vbox): # Add some spacing after each year block
			var year_spacer = Control.new()
			year_spacer.custom_minimum_size.y = 20
			course_viz_vbox.add_child(year_spacer)

	if not found_any_year_content and is_instance_valid(course_viz_vbox):
		var no_year_data_label = Label.new()
		no_year_data_label.text = "Curriculum structure for '%s', \nbut no year data (e.g., 'Year 1', 'Year 2') found." % program_id
		no_year_data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		course_viz_vbox.add_child(no_year_data_label)


	if DETAILED_LOGGING_ENABLED: print_debug("Middle Panel: Populated for '%s'." % program_id)


func _on_course_viz_item_selected(course_id: String):
	current_selected_course_id = course_id
	if DETAILED_LOGGING_ENABLED: print_debug("Course selected for details panel: ", course_id)
	_populate_right_course_details_panel(course_id)

func _clear_right_course_details_panel():
	if is_instance_valid(course_name_label): course_name_label.text = "Course: -"
	if is_instance_valid(course_id_label): course_id_label.text = "ID: -"
	if is_instance_valid(course_credits_label): course_credits_label.text = "Credits: -"
	if is_instance_valid(course_description_label): course_description_label.text = "Select a course from the curriculum to see details."

func _populate_right_course_details_panel(course_id: String):
	_clear_right_course_details_panel() # Clear first
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("Right Panel: AcademicManager or UniversityData not valid.")
		return

	var univ_data: UniversityData = academic_manager.university_data
	var course_details = univ_data.get_course_details(course_id)

	if course_details.is_empty():
		if is_instance_valid(course_name_label): course_name_label.text = "Course Details Not Found"
		if is_instance_valid(course_id_label): course_id_label.text = "ID: %s (Not Found)" % course_id
		return

	if is_instance_valid(course_name_label): course_name_label.text = "Course: %s" % course_details.get("name", "N/A")
	if is_instance_valid(course_id_label): course_id_label.text = "ID: %s" % course_id
	if is_instance_valid(course_credits_label): course_credits_label.text = "Credits: %.1f" % course_details.get("credits", 0.0)
	if is_instance_valid(course_description_label): course_description_label.text = course_details.get("description", "No description available.")

func show_panel():
	self.visible = true
	_populate_program_list()
	if not current_selected_program_id.is_empty():
		_populate_middle_course_viz(current_selected_program_id) # Refresh middle if a program was selected
		if not current_selected_course_id.is_empty():
			_populate_right_course_details_panel(current_selected_course_id) # Refresh right if a course was selected
		else:
			_clear_right_course_details_panel()
	else:
		_clear_middle_panel()
		_clear_right_course_details_panel()

func hide_panel():
	self.visible = false

func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[ProgramMgmtUI]: " # Changed prefix
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY:
		var temp_arr: Array = message_parts # Temporary variable for type hint
		var string_parts: Array[String] = []
		for item in temp_arr: string_parts.append(str(item))
		final_message += String(" ").join(string_parts)
	else: final_message += str(message_parts)
	print(final_message)
