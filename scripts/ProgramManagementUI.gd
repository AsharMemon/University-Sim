# ProgramManagementUI.gd
# Manages the three-panel layout for program and course information.
extends PanelContainer # Root of ProgramManagementPanel.tscn

# --- Node References (Ensure these paths match your .tscn structure) ---
@export var academic_manager: AcademicManager # Assign in editor

# Left Panel
@export var program_list_vbox: VBoxContainer = get_node_or_null("MainMargin/MainHBox/LeftColumn/ProgramScroll/ProgramListVBox")

# Middle Panel
@export var selected_program_name_label: Label = get_node_or_null("MainMargin/MainHBox/MiddleColumn/SelectedProgramNameLabel")
@export var course_viz_vbox: VBoxContainer = get_node_or_null("MainMargin/MainHBox/MiddleColumn/CourseVizScroll/CourseVizVBox")

# Right Panel
@export var course_name_label: Label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseNameLabel")
@export var course_id_label: Label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseIDLabel")
@export var course_credits_label: Label = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseCreditsLabel")
@export var course_description_label: RichTextLabel = get_node_or_null("MainMargin/MainHBox/RightColumn/CourseDescriptionScroll/CourseDescriptionLabel")

# --- Scene Preloads ---
const ProgramEntryRowScene: PackedScene = preload("res://scenes/ProgramEntryRow.tscn") # Path to your adapted ProgramEntryRow.tscn

# --- State ---
var current_selected_program_id: String = ""
var current_selected_course_id: String = ""
var program_row_nodes: Array[Node] = [] # To manage selection visuals

# --- Initialization ---
func _ready():
	# Validate essential node references
	if not _validate_nodes([program_list_vbox, selected_program_name_label, course_viz_vbox, 
							course_name_label, course_id_label, course_credits_label, course_description_label]):
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

	if academic_manager.is_connected("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked")):
		print_debug("Already connected to program_unlocked.")
	else:
		var err = academic_manager.connect("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked"))
		if err != OK: printerr("ProgramManagementUI: Failed to connect to program_unlocked signal. Error: ", err)
	
	# Initial UI population
	_populate_program_list()
	_clear_middle_panel()
	_clear_right_course_details_panel()


func _validate_nodes(nodes_to_check: Array) -> bool:
	for node_ref in nodes_to_check:
		if not is_instance_valid(node_ref):
			printerr("ProgramManagementUI: Critical UI node not found. Please check scene paths. Missing: ", node_ref)
			return false
	return true

# In ProgramManagementUI.gd

# --- Left Panel: Program List ---
func _populate_program_list():
	if not is_instance_valid(program_list_vbox):
		printerr("ProgramManagementUI: ProgramListVBox is not valid.")
		return
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("ProgramManagementUI: AcademicManager or UniversityData not valid.")
		return
	if not ProgramEntryRowScene:
		printerr("ProgramManagementUI: ProgramEntryRowScene not loaded.")
		return

	# Clear existing entries
	for child in program_list_vbox.get_children():
		child.queue_free()
	program_row_nodes.clear() # Clear the array of node references

	var univ_data: UniversityData = academic_manager.university_data
	var all_progs = univ_data.PROGRAMS
	var prog_states = academic_manager.get_all_program_states()
	var sorted_prog_ids = all_progs.keys()
	sorted_prog_ids.sort()

	if sorted_prog_ids.is_empty():
		var lbl = Label.new()
		lbl.text = "No programs defined in UniversityData."
		program_list_vbox.add_child(lbl)
		return

	for prog_id in sorted_prog_ids:
		var prog_details = all_progs[prog_id]
		if not prog_details is Dictionary: # Basic check for data integrity
			printerr("ProgramManagementUI: Program details for '", prog_id, "' is not a dictionary. Skipping.")
			continue
			
		var prog_name = prog_details.get("name", "Unnamed Program")
		var prog_status = prog_states.get(prog_id, "locked")

		# MODIFIED INSTANTIATION:
		# 1. Instantiate without a specific cast first.
		#    instantiate() returns the root node of the scene.
		var row_instance_node = ProgramEntryRowScene.instantiate() 

		# 2. Check if instantiation was successful.
		if not is_instance_valid(row_instance_node):
			printerr("ProgramManagementUI: Failed to instantiate ProgramEntryRowScene for program '", prog_id, "'. Scene might be corrupt or empty. Skipping.")
			continue # Skip this iteration

		# At this point, row_instance_node is a valid Node (or a type derived from it)
		program_list_vbox.add_child(row_instance_node)
		program_row_nodes.append(row_instance_node) # Add to our list for managing selection visuals
		
		# 3. Now, check for the method. row_instance_node is guaranteed not to be null here.
		if row_instance_node.has_method("setup"):
			row_instance_node.setup(prog_id, prog_name, prog_status, academic_manager)
			
			# Connect signals (ensure signal names match those in ProgramEntryRow.gd)
			if not row_instance_node.is_connected("unlock_requested", Callable(self, "_on_program_row_unlock_requested")):
				# Using .bind(row_instance_node) is optional here if the callback doesn't strictly need the row instance passed by signal
				# but can be useful. The prog_id is the primary data.
				row_instance_node.unlock_requested.connect(Callable(self, "_on_program_row_unlock_requested"))
			
			if not row_instance_node.is_connected("program_selected", Callable(self, "_on_program_row_selected")):
				row_instance_node.program_selected.connect(Callable(self, "_on_program_row_selected"))
		else:
			# This means the script attached to the root of ProgramEntryRow.tscn (or the script itself) is missing the setup method,
			# or ProgramEntryRow.tscn does not have ProgramEntryRow.gd attached to its root.
			printerr("ProgramManagementUI: Instantiated ProgramEntryRow for '", prog_id, "' does not have a setup() method. Node type: ", row_instance_node.get_class(), ", Script: ", row_instance_node.get_script())
			row_instance_node.queue_free() # Clean up the problematic instance
			program_row_nodes.pop_back() # Remove it from our list
	
	_update_program_selection_visuals() # Update visuals after repopulating


func _on_program_row_unlock_requested(program_id: String, _row_instance = null): # _row_instance can be used if bound
	print_debug(">>>> ProgramManagementUI: _on_program_row_selected entered. Program ID: '", program_id, "' <<<<") # VERY VISIBLE PRINT
	if not is_instance_valid(academic_manager): return
	print_debug("ProgramManagementUI: Unlock request for program '", program_id, "'.")
	var success = academic_manager.unlock_program(program_id) # This should emit "program_unlocked"
	if not success: print_debug("ProgramManagementUI: Unlock failed for '", program_id, "'.")
	# UI refresh is handled by _on_academic_manager_program_unlocked

func _on_academic_manager_program_unlocked(_program_id: String):
	print_debug("ProgramManagementUI: Program unlocked signal received. Refreshing program list.")
	_populate_program_list() # Re-populates and re-connects signals
	# If the unlocked program was the currently selected one, refresh middle panel
	if _program_id == current_selected_program_id:
		_populate_middle_course_viz(current_selected_program_id)
	elif current_selected_program_id.is_empty() and program_row_nodes.size() > 0:
		# If nothing was selected, and now there are programs, maybe auto-select first unlocked?
		pass


# In ProgramManagementUI.gd

func _on_program_row_selected(program_id: String):
	print_debug("CALLBACK: _on_program_row_selected CALLED. Program ID: '", program_id, "'") # Ensure this prints

	if current_selected_program_id == program_id:
		print_debug("Program '", program_id, "' was already selected. Refreshing selection visuals.")
		_update_program_selection_visuals() # Ensure it's visually marked
		# Optionally, you could force a re-population of the middle panel if desired,
		# but typically not needed if it's already selected and displayed.
		# _populate_middle_course_viz(program_id) # Uncomment if you want to refresh middle on re-click
		return

	current_selected_program_id = program_id
	current_selected_course_id = "" # Clear selected course when program changes
	
	print_debug("Program selection CHANGED to: '", program_id, "'. Updating UI panels.")
	_update_program_selection_visuals()
	_populate_middle_course_viz(program_id)
	_clear_right_course_details_panel()


# --- Middle Panel: Course Visualization ---
func _clear_middle_panel():
	if is_instance_valid(selected_program_name_label):
		selected_program_name_label.text = "Select a Program to View Courses"
	if is_instance_valid(course_viz_vbox):
		print_debug("Clearing middle panel (course_viz_vbox). Children count: ", course_viz_vbox.get_child_count())
		for child in course_viz_vbox.get_children():
			child.queue_free()
	else:
		printerr("ProgramManagementUI: course_viz_vbox is NULL in _clear_middle_panel.")


# In ProgramManagementUI.gd

# ... (other parts of the script, _clear_middle_panel remains the same) ...

func _populate_middle_course_viz(program_id: String):
	print_debug("MIDDLE PANEL (Structured): Attempting to populate for program_id: '", program_id, "'")
	_clear_middle_panel() # Clears previous courses and resets title in selected_program_name_label

	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("MIDDLE PANEL (Structured): AcademicManager or UniversityData not valid. Cannot populate.")
		if is_instance_valid(selected_program_name_label): selected_program_name_label.text = "Error: System data unavailable."
		return

	var univ_data: UniversityData = academic_manager.university_data
	var prog_details = univ_data.get_program_details(program_id) # From PROGRAMS dict

	if prog_details.is_empty():
		if is_instance_valid(selected_program_name_label): selected_program_name_label.text = "Program '%s' Details Not Found." % program_id
		printerr("MIDDLE PANEL (Structured): Program details not found for '", program_id, "'.")
		return
	
	var program_name_for_label = prog_details.get("name", program_id)
	if is_instance_valid(selected_program_name_label):
		selected_program_name_label.text = "%s - Curriculum Overview" % program_name_for_label
	print_debug("MIDDLE PANEL (Structured): Set program name label to: '", selected_program_name_label.text if is_instance_valid(selected_program_name_label) else "N/A", "'")

	# Get the new structured curriculum
	var program_curriculum: Dictionary = univ_data.get_program_curriculum_structure(program_id)
	print_debug("MIDDLE PANEL (Structured): Curriculum structure for '", program_id, "': ", program_curriculum)

	if program_curriculum.is_empty():
		var lbl = Label.new(); lbl.text = "No structured curriculum defined for this program."
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(lbl)
		print_debug("MIDDLE PANEL (Structured): No curriculum structure found for '", program_id, "'.")
		return

	# Define order of years for display (dictionaries don't guarantee order)
	var year_display_order = ["Freshman Year", "Sophomore Year", "Junior Year", "Senior Year"] # Add more if your programs go longer

	for year_key_name in year_display_order:
		if not program_curriculum.has(year_key_name):
			continue # Skip if this year isn't defined for the program (e.g. a 2-year program)

		var year_semesters_data: Dictionary = program_curriculum[year_key_name]

		# --- Add Year Title Label ---
		var year_title_lbl = Label.new()
		year_title_lbl.text = year_key_name.to_upper()
		year_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		year_title_lbl.add_theme_font_size_override("font_size", 20) # Larger for year
		year_title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7)) # Light yellow/gold
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(year_title_lbl)
		
		# --- Create an HBoxContainer for the semesters of this year ---
		var semesters_layout_hbox = HBoxContainer.new()
		semesters_layout_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		semesters_layout_hbox.add_theme_constant_override("separation", 15) # Space between semester columns
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(semesters_layout_hbox)

		var semester_display_order = ["First Semester", "Second Semester"] # Can be extended

		var semester_content_exists_for_year = false
		for semester_key_name in semester_display_order:
			# --- VBox for this semester's courses ---
			var semester_courses_vbox = VBoxContainer.new()
			semester_courses_vbox.name = year_key_name.replace(" ", "") + "_" + semester_key_name.replace(" ", "") # For debugging
			semester_courses_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Each semester column shares space
			semester_courses_vbox.custom_minimum_size.x = 150 # Ensure columns have some width
			semesters_layout_hbox.add_child(semester_courses_vbox) # Add to HBox

			if not year_semesters_data.has(semester_key_name):
				# Add placeholder if semester data is missing to maintain layout
				var empty_sem_label = Label.new(); empty_sem_label.text = "(%s not defined)" % semester_key_name
				empty_sem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				semester_courses_vbox.add_child(empty_sem_label)
				continue

			semester_content_exists_for_year = true
			var semester_course_ids: Array = year_semesters_data[semester_key_name]

			# --- Add Semester Title Label ---
			var semester_title_lbl = Label.new()
			semester_title_lbl.text = semester_key_name
			semester_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			semester_title_lbl.add_theme_font_size_override("font_size", 16)
			semester_courses_vbox.add_child(semester_title_lbl)
			
			var semester_hr_separator = HSeparator.new()
			semester_courses_vbox.add_child(semester_hr_separator)

			if semester_course_ids.is_empty():
				var no_courses_lbl = Label.new()
				no_courses_lbl.text = "(No courses this semester)"
				no_courses_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				no_courses_lbl.modulate = Color(0.7, 0.7, 0.7) # Dim text
				semester_courses_vbox.add_child(no_courses_lbl)
			else:
				var total_credits_this_semester = 0
				for course_id_val in semester_course_ids:
					if not course_id_val is String: # Basic type check
						printerr("MIDDLE PANEL: Non-string course ID found: ", course_id_val, " in ", program_id, "/", year_key_name, "/", semester_key_name)
						continue

					var course_data_dict = univ_data.get_course_details(course_id_val)
					var course_name_val = course_id_val # Default to ID if details are missing
					var course_credits_val = 0
					
					if not course_data_dict.is_empty():
						course_name_val = course_data_dict.get("name", course_id_val)
						course_credits_val = course_data_dict.get("credits", 0)
						total_credits_this_semester += course_credits_val
					else:
						print_debug("MIDDLE PANEL: Details not found for course '", course_id_val, "'. Displaying ID only.")


					var course_item_button = Button.new()
					course_item_button.text = "%s - %s (%s cr)" % [course_id_val, course_name_val, course_credits_val]
					if course_data_dict.is_empty(): # Highlight if data is missing
						course_item_button.add_theme_color_override("font_color", Color.ORANGE_RED)
						course_item_button.tooltip_text = "Course data missing in UniversityData.COURSES for ID: %s" % course_id_val
					else:
						course_item_button.tooltip_text = course_data_dict.get("description", "No description available.")

					course_item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					
					var connect_callable = Callable(self, "_on_course_viz_item_selected").bind(course_id_val)
					if not course_item_button.is_connected("pressed", connect_callable):
						var err_code = course_item_button.pressed.connect(connect_callable)
						if err_code != OK:
							printerr("MIDDLE PANEL: Failed to connect course button for '", course_id_val, "'. Error: ", err_code)
					semester_courses_vbox.add_child(course_item_button)
				
				# --- Add Total Credits for Semester ---
				var total_credits_label = Label.new()
				total_credits_label.text = "Total hours: %s" % total_credits_this_semester
				total_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				total_credits_label.add_theme_font_size_override("font_size", 12)
				total_credits_label.modulate = Color(0.8, 0.8, 0.8)
				semester_courses_vbox.add_child(total_credits_label)


		if not semester_content_exists_for_year: # If both semesters were missing for this year
			var no_sem_data_label = Label.new()
			no_sem_data_label.text = "(No semester data defined for this year)"
			no_sem_data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			semesters_layout_hbox.add_child(no_sem_data_label)

		# --- Separator after each year's content ---
		var year_end_separator = HSeparator.new()
		year_end_separator.custom_minimum_size.y = 10 # Make it a bit thicker for year division
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(year_end_separator)
		
		var year_bottom_spacer_ctrl = Control.new() # Use Control for pure spacing
		year_bottom_spacer_ctrl.custom_minimum_size.y = 15 # Space before next year title
		if is_instance_valid(course_viz_vbox): course_viz_vbox.add_child(year_bottom_spacer_ctrl)

	print_debug("MIDDLE PANEL (Structured): Finished populating for '", program_id, "'. Children in course_viz_vbox: ", course_viz_vbox.get_child_count() if is_instance_valid(course_viz_vbox) else "N/A")

# ... (The rest of ProgramManagementUI.gd: _on_course_viz_item_selected, _clear_right_course_details_panel, 
#      _populate_right_course_details_panel, show_panel, hide_panel, print_debug) ...
# These functions should still work as they did before.

func _update_program_selection_visuals():
	for row_node in program_row_nodes:
		if row_node.has_method("set_selected") and row_node.has_method("setup"): # crude check
			var row_prog_id = row_node.current_program_id # Assumes ProgramEntryRow stores this
			row_node.set_selected(row_prog_id == current_selected_program_id)

func _on_course_viz_item_selected(course_id: String):
	current_selected_course_id = course_id
	print_debug("Course selected for details: ", course_id)
	_populate_right_course_details_panel(course_id)
	# TODO: Highlight selected course_button in middle panel


# --- Right Panel: Course Details ---
func _clear_right_course_details_panel():
	if is_instance_valid(course_name_label): course_name_label.text = "Course Name: -"
	if is_instance_valid(course_id_label): course_id_label.text = "ID: -"
	if is_instance_valid(course_credits_label): course_credits_label.text = "Credits: -"
	if is_instance_valid(course_description_label): course_description_label.text = "Select a course to see details."

func _populate_right_course_details_panel(course_id: String):
	_clear_right_course_details_panel()
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data): return

	var univ_data: UniversityData = academic_manager.university_data
	var course_details = univ_data.get_course_details(course_id)

	if course_details.is_empty():
		course_name_label.text = "Course details not found."
		course_id_label.text = "ID: %s (Not Found)" % course_id
		return

	course_name_label.text = "Course Name: %s" % course_details.get("name", "N/A")
	course_id_label.text = "ID: %s" % course_id
	course_credits_label.text = "Credits: %s" % course_details.get("credits", "N/A")
	course_description_label.text = course_details.get("description", "No description available.")


# --- Panel Visibility (Called by BuildingManager) ---
func show_panel():
	self.visible = true
	_populate_program_list() # Refresh program list when shown
	# If a program was previously selected, re-select it, otherwise clear middle/right
	if not current_selected_program_id.is_empty():
		_on_program_row_selected(current_selected_program_id) # This will refresh middle/right
	else:
		_clear_middle_panel()
		_clear_right_course_details_panel()


func hide_panel():
	self.visible = false
	# current_selected_program_id and current_selected_course_id can be retained or cleared
	# Clearing them means the panel resets its view next time it's opened.
	# current_selected_program_id = ""
	# current_selected_course_id = ""


# --- Helper ---
func print_debug(message_parts):
	var final_message = "[ProgramManagementUI]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: final_message += String(" ").join(message_parts.map(func(x):return str(x)))
	else: final_message += str(message_parts)
	print(final_message)
