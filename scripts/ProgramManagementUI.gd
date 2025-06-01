# ProgramManagementUI.gd
# Manages the three-panel layout for program and course information.
extends PanelContainer # Root of ProgramManagementPanel.tscn

# --- Node References (Ensure these paths match your .tscn structure) ---
@export var academic_manager: AcademicManager # Assign in editor

# Left Panel
@export var program_list_vbox: VBoxContainer

# Middle Panel
@export var selected_program_name_label: Label
@export var course_viz_scroll: ScrollContainer 
@export var course_viz_content_parent: Container # This will be the HBoxContainer for years
@export var legend_container_parent: Container # Parent for the legend, e.g., VBox of middle panel

# Right Panel
@export var course_name_label: Label
@export var course_id_label: Label
@export var course_credits_label: Label
@export var course_description_label: RichTextLabel

# --- Scene Preloads ---
const ProgramEntryRowScene: PackedScene = preload("res://scenes/ProgramEntryRow.tscn")

# --- State ---
var current_selected_program_id: String = ""
var current_selected_course_id_for_details: String = ""
var program_row_nodes: Array[Node] = []
var all_course_cell_nodes: Dictionary = {} 
var currently_highlighted_course_id: String = ""
var legend_hbox: HBoxContainer # Dynamically created legend

# --- Debugging ---
const DETAILED_LOGGING_ENABLED: bool = true

# --- Styling Constants for Grid ---
var COLOR_SELECTED_BG: Color = Color.from_string("#007bff", Color.WHITE)
var COLOR_PREREQ_BG: Color = Color.from_string("#28a745", Color.WHITE)
var COLOR_UNLOCKS_BG: Color = Color.from_string("#9b59b6", Color.WHITE)
var COLOR_CELL_NORMAL_BG: Color = Color.from_string("#e9ecef", Color.WHITE)
var COLOR_CELL_HOVER_BG: Color = Color.from_string("#d1d9e0", Color.WHITE)

var COLOR_CELL_NORMAL_FG: Color = Color.from_string("#212529", Color.BLACK)
var COLOR_CELL_ID_FG: Color = Color.from_string("#6c757d", Color.DARK_GRAY)
var COLOR_CELL_HIGHLIGHT_FG: Color = Color.WHITE

const DIM_MODULATE: Color = Color(1,1,1, 0.4)
const NORMAL_MODULATE: Color = Color(1,1,1, 1)

const YEAR_COLUMN_MIN_WIDTH: float = 220.0
const LEGEND_SWATCH_SIZE: Vector2 = Vector2(16, 16)

# --- Initialization ---
func _ready():
	# Node path validation and fallback (condensed)
	if not is_instance_valid(program_list_vbox):
		program_list_vbox = get_node_or_null("MainMargin/MainHBox/LeftColumn/ProgramScroll/ProgramListVBox")
	if not is_instance_valid(selected_program_name_label):
		selected_program_name_label = get_node_or_null("MainMargin/MainHBox/MiddleColumn/SelectedProgramNameLabel")
	if not is_instance_valid(course_viz_scroll): 
		course_viz_scroll = get_node_or_null("MainMargin/MainHBox/MiddleColumn/CourseVizScroll")
	
	# Parent for legend (e.g., the VBox containing selected_program_name_label and course_viz_scroll)
	if not is_instance_valid(legend_container_parent):
		if is_instance_valid(selected_program_name_label) and is_instance_valid(course_viz_scroll) and \
		   selected_program_name_label.get_parent() == course_viz_scroll.get_parent() and \
		   is_instance_valid(selected_program_name_label.get_parent()):
			legend_container_parent = selected_program_name_label.get_parent() 
			print_debug("Auto-assigned legend_container_parent to parent of selected_program_name_label.")
		elif is_instance_valid(course_viz_scroll) and is_instance_valid(course_viz_scroll.get_parent()):
			legend_container_parent = course_viz_scroll.get_parent() # Fallback if only scroll is found
			print_debug("Auto-assigned legend_container_parent to parent of course_viz_scroll.")
		else:
			printerr("ProgramManagementUI: legend_container_parent not assigned and could not be auto-determined. Legend will not be created.")

	if not is_instance_valid(course_viz_content_parent): 
		if is_instance_valid(course_viz_scroll): 
			course_viz_content_parent = HBoxContainer.new()
			course_viz_content_parent.name = "YearColumnsHBox"
			course_viz_content_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			course_viz_content_parent.size_flags_vertical = Control.SIZE_EXPAND_FILL
			course_viz_scroll.add_child(course_viz_content_parent)
		else:
			printerr("ProgramManagementUI: CourseVizScroll not found, cannot create content parent for grid.")

	# ... (rest of node validations as before) ...
	if not _validate_nodes([program_list_vbox, selected_program_name_label, course_viz_content_parent,
							course_name_label, course_id_label, course_credits_label, course_description_label]):
		printerr("ProgramManagementUI: One or more critical UI nodes are missing.")
		return

	if not is_instance_valid(academic_manager):
		academic_manager = get_node_or_null("/root/MainScene/AcademicManager")
		if not is_instance_valid(academic_manager):
			printerr("ProgramManagementUI: CRITICAL - AcademicManager not found.")
			return
	
	if not ProgramEntryRowScene:
		printerr("ProgramManagementUI: CRITICAL - ProgramEntryRow.tscn not preloaded.")
		return

	if academic_manager.has_signal("program_unlocked"):
		if not academic_manager.is_connected("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked")):
			academic_manager.connect("program_unlocked", Callable(self, "_on_academic_manager_program_unlocked"))
	
	get_viewport().gui_focus_changed.connect(_on_global_focus_changed)

	_setup_color_legend() # Call to create the legend
	_populate_program_list()
	_clear_middle_panel_grid()
	_clear_right_course_details_panel()


# --- Color Legend Setup ---
func _setup_color_legend():
	if not is_instance_valid(legend_container_parent):
		print_debug("Legend container parent is not valid. Cannot create legend.")
		return

	if is_instance_valid(legend_hbox): # Clear if already exists
		legend_hbox.queue_free()
		legend_hbox = null

	legend_hbox = HBoxContainer.new()
	legend_hbox.name = "ColorLegendHBox"
	legend_hbox.alignment = BoxContainer.ALIGNMENT_CENTER # Center items in HBox
	legend_hbox.add_theme_constant_override("separation", 20) # Space between legend items
	
	# Add legend title
	var legend_title_label = Label.new()
	legend_title_label.text = "Legend:"
	legend_title_label.add_theme_font_size_override("font_size", 14)
	legend_title_label.self_modulate = Color.DARK_SLATE_GRAY
	legend_hbox.add_child(legend_title_label)

	# Add legend items
	_add_legend_item(legend_hbox, COLOR_SELECTED_BG, "Selected")
	_add_legend_item(legend_hbox, COLOR_PREREQ_BG, "Prerequisite")
	_add_legend_item(legend_hbox, COLOR_UNLOCKS_BG, "Unlocks")

	# Insert the legend HBox into the parent container
	# Place it after selected_program_name_label and before course_viz_scroll if possible
	var target_index = 1 # Default index
	if is_instance_valid(selected_program_name_label) and selected_program_name_label.get_parent() == legend_container_parent:
		target_index = selected_program_name_label.get_index() + 1
	
	legend_container_parent.add_child(legend_hbox)
	if legend_container_parent.has_method("move_child"): # VBoxContainer, GridContainer have this
		legend_container_parent.move_child(legend_hbox, target_index)
	
	var spacer = Control.new() # Add some space below legend
	spacer.custom_minimum_size.y = 10
	legend_container_parent.add_child(spacer)
	if legend_container_parent.has_method("move_child"):
		legend_container_parent.move_child(spacer, target_index + 1)


func _add_legend_item(parent_container: Container, color: Color, text: String):
	var item_hbox = HBoxContainer.new()
	item_hbox.add_theme_constant_override("separation", 5)

	var color_rect = ColorRect.new()
	color_rect.color = color
	color_rect.custom_minimum_size = LEGEND_SWATCH_SIZE
	item_hbox.add_child(color_rect)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.self_modulate = Color.DIM_GRAY
	item_hbox.add_child(label)

	parent_container.add_child(item_hbox)

# --- Middle Panel: NEW Interactive Curriculum Grid ---
func _populate_middle_course_viz_grid(program_id: String):
	print_debug("Populating grid for program: '%s'" % program_id)
	_clear_middle_panel_grid()

	# ... (rest of the data validation as before) ...
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("Grid: AcademicManager or UniversityData not valid.")
		if is_instance_valid(selected_program_name_label): selected_program_name_label.text = "Error: Data System Missing"
		return

	var univ_data: UniversityData = academic_manager.university_data
	var prog_main_details = univ_data.get_program_details(program_id)

	if prog_main_details.is_empty():
		if is_instance_valid(selected_program_name_label): selected_program_name_label.text = "Program '%s' Not Found" % program_id
		return
	
	if is_instance_valid(selected_program_name_label):
		selected_program_name_label.text = prog_main_details.get("name", program_id) + " - Curriculum Grid"

	var program_curriculum_structure: Dictionary = univ_data.PROGRAM_CURRICULUM_STRUCTURE.get(program_id, {})
	if program_curriculum_structure.is_empty():
		var lbl = Label.new(); lbl.text = "No structured curriculum defined for this program."
		if is_instance_valid(course_viz_content_parent): course_viz_content_parent.add_child(lbl)
		return

	if not course_viz_content_parent is HBoxContainer:
		printerr("course_viz_content_parent is not an HBoxContainer. Grid layout might be incorrect.")

	var year_keys = program_curriculum_structure.keys()
	year_keys.sort() 

	for year_key in year_keys:
		var year_data: Dictionary = program_curriculum_structure[year_key]
		
		var year_column_vbox = VBoxContainer.new()
		year_column_vbox.name = year_key.replace(" ", "_") + "_Column"
		year_column_vbox.custom_minimum_size.x = YEAR_COLUMN_MIN_WIDTH
		year_column_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL 
		year_column_vbox.add_theme_constant_override("separation", 10)
		course_viz_content_parent.add_child(year_column_vbox)

		var year_header_label = Label.new()
		year_header_label.text = year_key
		year_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		year_header_label.add_theme_font_size_override("font_size", 18) 
		year_header_label.self_modulate = Color.DARK_SLATE_GRAY # Use a more readable color
		# Add some padding to the year header using a MarginContainer or by setting margins
		var year_header_margin = MarginContainer.new()
		year_header_margin.add_theme_constant_override("margin_top", 5)
		year_header_margin.add_theme_constant_override("margin_bottom", 5)
		year_header_margin.add_child(year_header_label)
		year_column_vbox.add_child(year_header_margin)
		
		var h_sep = HSeparator.new()
		h_sep.self_modulate = Color(0.8, 0.8, 0.8) # Make separator lighter
		year_column_vbox.add_child(h_sep)


		var semester_keys = year_data.keys()
		semester_keys.sort() 

		for semester_key in semester_keys:
			var semester_courses_list: Array = year_data[semester_key]
			
			var semester_header_label = Label.new()
			semester_header_label.text = semester_key
			semester_header_label.add_theme_font_size_override("font_size", 14) 
			semester_header_label.self_modulate = Color.SLATE_GRAY # Slightly darker than DIM_GRAY
			var semester_header_margin = MarginContainer.new() # Add margin for semester header too
			semester_header_margin.add_theme_constant_override("margin_top", 8)
			semester_header_margin.add_theme_constant_override("margin_bottom", 4)
			semester_header_margin.add_child(semester_header_label)
			year_column_vbox.add_child(semester_header_margin)

			for course_id_str in semester_courses_list:
				var course_cell_node = _create_course_cell(course_id_str)
				if is_instance_valid(course_cell_node):
					year_column_vbox.add_child(course_cell_node)
					all_course_cell_nodes[course_id_str] = course_cell_node
					print_debug("      Added cell for '%s' to year_column_vbox. Cell valid: %s. Parent: %s" % [course_id_str, str(is_instance_valid(course_cell_node)), str(year_column_vbox.name)])
					
	print_debug("Grid populated for '%s'." % program_id)

# --- (Rest of the script: _create_course_cell, interaction handlers, recursive functions, right panel, etc. unchanged) ---
# ... (Keep all the other functions from the previous version)
# Ensure _validate_nodes, _populate_program_list, _on_program_row_*, _update_program_selection_visuals,
# _clear_middle_panel_grid, _create_course_cell, _on_course_cell_mouse_entered, _on_course_cell_mouse_exited,
# _on_course_cell_gui_input, _apply_highlights, _clear_all_cell_visual_states,
# _get_all_prerequisites_recursive, _get_all_unlocked_by_recursive,
# _clear_right_course_details_panel, _populate_right_course_details_panel,
# show_panel, hide_panel, _on_global_focus_changed, print_debug remain the same.
# The only new functions are _setup_color_legend and _add_legend_item.
# The _populate_middle_course_viz_grid has changes for year/semester headers.
# The _ready function has changes for legend_container_parent and calling _setup_color_legend.

# --- Helper Functions (from previous correct version) ---
func _validate_nodes(nodes_to_check: Array) -> bool: # Simplified
	for node_ref in nodes_to_check:
		if not is_instance_valid(node_ref): return false
	return true

func _on_program_row_unlock_requested(program_id: String):
	print_debug("Unlock request for program ID: '%s'" % program_id)
	if not is_instance_valid(academic_manager): return
	academic_manager.unlock_program(program_id)

func _on_academic_manager_program_unlocked(program_id_unlocked: String):
	print_debug("Program unlocked: %s. Refreshing list." % program_id_unlocked)
	_populate_program_list()
	if program_id_unlocked == current_selected_program_id:
		_populate_middle_course_viz_grid(current_selected_program_id)

# --- Left Panel Logic (Mostly unchanged, ensure signals are connected correctly) ---
func _populate_program_list():
	if not is_instance_valid(program_list_vbox) or \
	   not is_instance_valid(academic_manager) or \
	   not is_instance_valid(academic_manager.university_data) or \
	   not ProgramEntryRowScene:
		printerr("Cannot populate program list due to missing dependencies.")
		return

	# Clear existing rows
	for child in program_list_vbox.get_children():
		child.queue_free()
	program_row_nodes.clear()

	var univ_data: UniversityData = academic_manager.university_data
	var all_progs = univ_data.PROGRAMS # This is const PROGRAMS from UniversityData
	var prog_states = academic_manager.get_all_program_states()
	var sorted_prog_ids = all_progs.keys()
	sorted_prog_ids.sort() # Sort for consistent display order

	if sorted_prog_ids.is_empty():
		var lbl = Label.new()
		lbl.text = "No programs defined."
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
			
			if row_instance_node.has_signal("unlock_requested"): 
				if not row_instance_node.is_connected("unlock_requested", Callable(self, "_on_program_row_unlock_requested")):
					row_instance_node.unlock_requested.connect(Callable(self, "_on_program_row_unlock_requested"))
			else: print_debug("ProgramEntryRow missing 'unlock_requested' signal for " + prog_id)
			
			if row_instance_node.has_signal("program_selected"): 
				if not row_instance_node.is_connected("program_selected", Callable(self, "_on_program_row_selected")):
					row_instance_node.program_selected.connect(Callable(self, "_on_program_row_selected"))
			else: print_debug("ProgramEntryRow missing 'program_selected' signal for " + prog_id)
		else:
			printerr("Instantiated ProgramEntryRow for '", prog_id, "' does not have setup(). Node: ", row_instance_node)
			row_instance_node.queue_free()
			program_row_nodes.pop_back()
	
	_update_program_selection_visuals()
	
func _on_program_row_selected(program_id: String):
	print_debug("Program selected: '%s'" % program_id)
	current_selected_program_id = program_id
	current_selected_course_id_for_details = ""
	currently_highlighted_course_id = "" 
	
	_update_program_selection_visuals()
	_populate_middle_course_viz_grid(program_id) 
	_clear_right_course_details_panel()

func _update_program_selection_visuals():
	for row_node in program_row_nodes:
		if row_node.has_method("set_selected") and row_node.has_method("get_program_id"):
			row_node.set_selected(row_node.get_program_id() == current_selected_program_id)

func _clear_middle_panel_grid():
	if is_instance_valid(selected_program_name_label):
		selected_program_name_label.text = "Select a Program"
	if is_instance_valid(course_viz_content_parent):
		for child in course_viz_content_parent.get_children():
			child.queue_free()
	all_course_cell_nodes.clear()

# In ProgramManagementUI.gd

# ... (ensure your styling constants like COLOR_CELL_NORMAL_BG, etc., are defined above) ...

func _create_course_cell(course_id: String) -> PanelContainer:
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data):
		printerr("Cannot create course cell: AcademicManager or UniversityData is not valid.")
		return null

	var course_data = academic_manager.university_data.COURSES.get(course_id)
	if course_data == null:
		printerr("Course data not found for ID: %s. Cannot create cell." % course_id)
		return null

	# Root of the cell
	var cell = PanelContainer.new()
	cell.name = course_id + "_Cell" # Unique name for the cell PanelContainer
	cell.custom_minimum_size.y = 70 # Adjusted minimum height for better readability
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Default styling for the cell panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = COLOR_CELL_NORMAL_BG
	style_box.border_width_top = 1
	style_box.border_width_bottom = 1
	style_box.border_width_left = 1
	style_box.border_width_right = 1
	style_box.border_color = Color.LIGHT_GRAY 
	style_box.corner_radius_top_left = 4     # Slightly more rounded corners
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	cell.add_theme_stylebox_override("panel", style_box)

	# VBoxContainer for centering content within the cell
	var vbox = VBoxContainer.new()
	vbox.name = "InfoVBox" # Crucial for consistent path access later
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER # Center content vertically
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Make VBox fill Panel
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL   # Make VBox fill Panel
	vbox.add_theme_constant_override("separation", 2) # Small separation between labels
	cell.add_child(vbox)

	# Course Name Label
	var name_label = Label.new()
	name_label.name = "NameLabel" # Crucial for consistent path access
	name_label.text = course_data.get("name", course_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.clip_text = true # Clip text if it overflows
	name_label.add_theme_color_override("font_color", COLOR_CELL_NORMAL_FG)
	name_label.add_theme_font_size_override("font_size", 13) # Ensure this is readable
	vbox.add_child(name_label)

	# Course ID Label
	var id_label = Label.new()
	id_label.name = "IDLabel" # Crucial for consistent path access
	id_label.text = "(%s)" % course_id
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	id_label.add_theme_color_override("font_color", COLOR_CELL_ID_FG)
	id_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(id_label)
	
	# Ensure the PanelContainer (cell) can receive mouse events
	cell.mouse_filter = Control.MOUSE_FILTER_STOP 

	# Connect signals for interaction
	# Using Callable to ensure connections are robust
	if not cell.is_connected("mouse_entered", Callable(self, "_on_course_cell_mouse_entered")):
		cell.mouse_entered.connect(Callable(self, "_on_course_cell_mouse_entered").bind(course_id))
	
	if not cell.is_connected("mouse_exited", Callable(self, "_on_course_cell_mouse_exited")):
		cell.mouse_exited.connect(Callable(self, "_on_course_cell_mouse_exited").bind(course_id))
	
	if not cell.is_connected("gui_input", Callable(self, "_on_course_cell_gui_input")):
		cell.gui_input.connect(Callable(self, "_on_course_cell_gui_input").bind(course_id))
	
	return cell

func _on_course_cell_mouse_entered(course_id: String):
	_apply_highlights(course_id)
	var cell = all_course_cell_nodes.get(course_id)
	if is_instance_valid(cell) and not cell.get_meta("is_selected", false): 
		var style_box: StyleBoxFlat = cell.get_theme_stylebox("panel").duplicate()
		style_box.bg_color = COLOR_CELL_HOVER_BG
		cell.add_theme_stylebox_override("panel", style_box)

func _on_course_cell_mouse_exited(course_id: String):
	if currently_highlighted_course_id.is_empty() or currently_highlighted_course_id != course_id:
		_clear_all_cell_visual_states() 
		if not currently_highlighted_course_id.is_empty():
			_apply_highlights(currently_highlighted_course_id) 

func _on_course_cell_gui_input(event: InputEvent, course_id: String):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		current_selected_course_id_for_details = course_id 
		_populate_right_course_details_panel(course_id)
		
		if currently_highlighted_course_id == course_id: 
			currently_highlighted_course_id = ""
			_clear_all_cell_visual_states()
		else:
			currently_highlighted_course_id = course_id
			_apply_highlights(course_id) 
		get_viewport().set_input_as_handled()

func _apply_highlights(selected_course_id: String):
	print_debug("--- Applying highlights for: %s ---" % selected_course_id) # DEBUG
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data): return

	_clear_all_cell_visual_states(true) 

	var univ_data: UniversityData = academic_manager.university_data
	var selected_course_data = univ_data.COURSES.get(selected_course_id)
	if selected_course_data == null:
		print_debug("No data found for selected course: %s" % selected_course_id) # DEBUG
		return

	var all_prereqs = _get_all_prerequisites_recursive(selected_course_id, univ_data)
	var all_unlocks = _get_all_unlocked_by_recursive(selected_course_id, univ_data)

	print_debug("Selected: %s | Prerequisites found: %s" % [selected_course_id, str(all_prereqs)]) # DEBUG
	print_debug("Selected: %s | Unlocks found: %s" % [selected_course_id, str(all_unlocks)]) # DEBUG

	for c_id in all_course_cell_nodes:
		var cell_node: PanelContainer = all_course_cell_nodes[c_id]
		if not is_instance_valid(cell_node): continue
		
		var is_dimmed = true
		var bg_color = COLOR_CELL_NORMAL_BG
		var fg_color = COLOR_CELL_NORMAL_FG
		var id_fg_color = COLOR_CELL_ID_FG
		cell_node.set_meta("is_selected", false)

		var log_reason = "normal" # DEBUG

		if c_id == selected_course_id:
			bg_color = COLOR_SELECTED_BG; fg_color = COLOR_CELL_HIGHLIGHT_FG; id_fg_color = COLOR_CELL_HIGHLIGHT_FG
			is_dimmed = false; cell_node.set_meta("is_selected", true)
			log_reason = "selected" # DEBUG
		elif all_prereqs.has(c_id):
			bg_color = COLOR_PREREQ_BG; fg_color = COLOR_CELL_HIGHLIGHT_FG; id_fg_color = COLOR_CELL_HIGHLIGHT_FG
			is_dimmed = false
			log_reason = "prereq" # DEBUG
		elif all_unlocks.has(c_id):
			bg_color = COLOR_UNLOCKS_BG; fg_color = COLOR_CELL_HIGHLIGHT_FG; id_fg_color = COLOR_CELL_HIGHLIGHT_FG
			is_dimmed = false
			log_reason = "unlock" # DEBUG
		
		# DEBUG: Print what's being applied to each cell
		# print_debug("Cell: %s, Reason: %s, Dimmed: %s" % [c_id, log_reason, str(is_dimmed)])

		var style_box: StyleBoxFlat = cell_node.get_theme_stylebox("panel").duplicate() 
		style_box.bg_color = bg_color
		cell_node.add_theme_stylebox_override("panel", style_box)
		
		var name_label : Label = cell_node.get_node_or_null("InfoVBox/NameLabel")
		var id_label_node : Label = cell_node.get_node_or_null("InfoVBox/IDLabel")
		if is_instance_valid(name_label): name_label.add_theme_color_override("font_color", fg_color)
		if is_instance_valid(id_label_node): id_label_node.add_theme_color_override("font_color", id_fg_color)
		cell_node.modulate = DIM_MODULATE if is_dimmed else NORMAL_MODULATE
		
func _clear_all_cell_visual_states(keep_dim_for_sticky_highlight: bool = false):
	for course_id_key in all_course_cell_nodes:
		var cell_node: PanelContainer = all_course_cell_nodes[course_id_key]
		if not is_instance_valid(cell_node): continue
		var style_box: StyleBoxFlat = cell_node.get_theme_stylebox("panel").duplicate()
		style_box.bg_color = COLOR_CELL_NORMAL_BG
		cell_node.add_theme_stylebox_override("panel", style_box)
		cell_node.set_meta("is_selected", false)
		var name_label : Label = cell_node.get_node_or_null("InfoVBox/NameLabel")
		var id_label_node : Label = cell_node.get_node_or_null("InfoVBox/IDLabel")
		if is_instance_valid(name_label): name_label.add_theme_color_override("font_color", COLOR_CELL_NORMAL_FG)
		if is_instance_valid(id_label_node): id_label_node.add_theme_color_override("font_color", COLOR_CELL_ID_FG)
		if not (keep_dim_for_sticky_highlight and not currently_highlighted_course_id.is_empty()):
			cell_node.modulate = NORMAL_MODULATE

func _get_all_prerequisites_recursive(course_id: String, univ_data: UniversityData, processed: PackedStringArray = []) -> PackedStringArray:
	if processed.has(course_id): return PackedStringArray() 
	processed.append(course_id)
	var course = univ_data.COURSES.get(course_id)
	if course == null or not course.has("prerequisites") or course.prerequisites.is_empty():
		return PackedStringArray()
	var all_prereqs_arr = PackedStringArray()
	for prereq_id_item in course.prerequisites:
		if not prereq_id_item is String : continue
		all_prereqs_arr.append(prereq_id_item)
		var indirect_prereqs = _get_all_prerequisites_recursive(prereq_id_item, univ_data, processed)
		for indirect_p in indirect_prereqs:
			if not all_prereqs_arr.has(indirect_p):
				all_prereqs_arr.append(indirect_p)
	return all_prereqs_arr

func _get_all_unlocked_by_recursive(target_course_id: String, univ_data: UniversityData, processed: PackedStringArray = []) -> PackedStringArray:
	# Base case: If we've already fully processed this target_course_id's unlocks, stop.
	if processed.has(target_course_id) and target_course_id != "":
		return PackedStringArray()

	var unlocked_courses_arr = PackedStringArray()
	var direct_unlocks_found_this_iteration = PackedStringArray()

	# Find courses that have target_course_id as a direct prerequisite
	for other_course_key in univ_data.COURSES:
		var other_course_data = univ_data.COURSES[other_course_key]
		if other_course_data.has("prerequisites") and other_course_data.prerequisites is Array and other_course_data.prerequisites.has(target_course_id):
			if not direct_unlocks_found_this_iteration.has(other_course_key): # Avoid adding duplicates if found multiple ways (not typical here)
					direct_unlocks_found_this_iteration.append(other_course_key)

	# Create a new processed list for the children's recursive calls.
	# This list should include the current target_course_id to prevent A->B->A cycles
	# where A's children are processed again via B.
	var processed_for_children_recursion = processed.duplicate()
	if target_course_id != "" and not processed_for_children_recursion.has(target_course_id):
		processed_for_children_recursion.append(target_course_id)

	for unlocked_course_id_item in direct_unlocks_found_this_iteration:
		# Add direct unlock to results if not already there
		if not unlocked_courses_arr.has(unlocked_course_id_item): 
			unlocked_courses_arr.append(unlocked_course_id_item)

		# Recursively find what this direct unlock further unlocks
		# Pass the 'processed_for_children_recursion' list which includes the current parent
		var indirect_unlocks = _get_all_unlocked_by_recursive(unlocked_course_id_item, univ_data, processed_for_children_recursion)
		for indirect_u in indirect_unlocks:
			if not unlocked_courses_arr.has(indirect_u): # Avoid duplicates in final result
				unlocked_courses_arr.append(indirect_u)

	return unlocked_courses_arr
	
func _clear_right_course_details_panel():
	if is_instance_valid(course_name_label): course_name_label.text = "Course: -"
	if is_instance_valid(course_id_label): course_id_label.text = "ID: -"
	if is_instance_valid(course_credits_label): course_credits_label.text = "Credits: -"
	if is_instance_valid(course_description_label): course_description_label.text = "Hover over or click a course in the grid to see details."

func _populate_right_course_details_panel(course_id: String):
	_clear_right_course_details_panel()
	if not is_instance_valid(academic_manager) or not is_instance_valid(academic_manager.university_data): return
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
		_populate_middle_course_viz_grid(current_selected_program_id)
		if not current_selected_course_id_for_details.is_empty():
			_populate_right_course_details_panel(current_selected_course_id_for_details)
		else: _clear_right_course_details_panel()
	else:
		_clear_middle_panel_grid()
		_clear_right_course_details_panel()

func hide_panel():
	self.visible = false
	currently_highlighted_course_id = "" 
	_clear_all_cell_visual_states()

func _on_global_focus_changed(_control_node_with_focus):
	pass # Logic for clearing sticky highlights on outside click can be refined here if needed

func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[ProgramMgmtUI]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY:
		var temp_arr: Array = message_parts
		var string_parts: Array[String] = []
		for item in temp_arr: string_parts.append(str(item))
		final_message += String(" ").join(string_parts)
	else: final_message += str(message_parts)
	print(final_message)
