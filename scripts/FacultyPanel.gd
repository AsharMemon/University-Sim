# FacultyPanel.gd
extends PanelContainer

# --- Node References ---
# Assign these in the Godot Editor Inspector
@export var professor_manager: ProfessorManager
@export var academic_manager: AcademicManager
# @export var research_manager: ResearchManager # Assign when implemented

# UI Elements - Ensure paths are correct for YOUR FacultyPanel.tscn scene
# It's generally more robust to use @onready with $PathToNode if these are direct children
# or within a consistent hierarchy, rather than full absolute paths from root.
# Example: @onready var tab_container: TabContainer = $MarginContainer/MainVBox/FacultyTabContainer

# Tabs & Lists
@export var tab_container: TabContainer
@export var hired_staff_list_vbox: VBoxContainer
@export var applicant_list_vbox: VBoxContainer

# Detail Panel Labels
@export var detail_name_label: Label
@export var detail_rank_label: Label
@export var detail_specialization_label: Label
@export var detail_salary_label: Label
@export var detail_teaching_skill_label: Label
@export var detail_research_skill_label: Label
@export var detail_morale_label: Label
@export var detail_tenure_label: Label
@export var detail_publications_label: Label
@export var detail_courses_label: Label
@export var detail_researching_label: Label

# Action Buttons
@export var hire_button: Button
@export var fire_button: Button
@export var assign_course_button: Button
@export var assign_research_button: Button
@export var promote_button: Button
@export var tenure_review_button: Button

@export var close_faculty_panel_button: Button

const ProfessorListItemScene: PackedScene = preload("res://scenes/ProfessorListItem.tscn")

var _selected_professor_object: Professor = null # Store the actual Professor object selected
var _is_selected_an_applicant: bool = false   # Flag to know if selection is from applicant list

const DETAILED_LOGGING_ENABLED : bool = true # For this script's debug messages

func _ready():
	# Validate crucial nodes obtained via get_node_or_null
	if not is_instance_valid(tab_container): printerr("FacultyPanel: TabContainer not found!")
	if not is_instance_valid(hired_staff_list_vbox): printerr("FacultyPanel: HiredStaffListVBox not found!")
	if not is_instance_valid(applicant_list_vbox): printerr("FacultyPanel: ApplicantListVBox not found!")
	# ... (add more checks for all @onready vars using get_node_or_null if they are critical)

	if not is_instance_valid(professor_manager):
		printerr("FacultyPanel: ProfessorManager not assigned in editor! UI will be non-functional.")
		set_process(false); return
	if not is_instance_valid(academic_manager):
		printerr("FacultyPanel: AcademicManager not assigned. Some functions (like listing courses for prof) might fail.")
		
	if not ProfessorListItemScene: 
		printerr("FacultyPanel: CRITICAL - ProfessorListItemScene not loaded!")
		return

	# Connect button signals
	if is_instance_valid(hire_button): hire_button.pressed.connect(_on_hire_button_pressed)
	else: printerr("FacultyPanel: HireButton not found!")

	if is_instance_valid(fire_button): fire_button.pressed.connect(_on_fire_button_pressed)
	else: printerr("FacultyPanel: FireButton not found!")
	
	if is_instance_valid(close_faculty_panel_button): close_faculty_panel_button.pressed.connect(hide_panel)
	else: printerr("FacultyPanel: CloseFacultyPanelButton not found!")
	
	# TODO: Connect other action buttons (assign_course_button, etc.) when their functionality is ready

	if is_instance_valid(tab_container) and not tab_container.is_connected("tab_changed", Callable(self, "_on_tab_changed")) :
		tab_container.tab_changed.connect(Callable(self, "_on_tab_changed"))
	
	if professor_manager.has_signal("faculty_list_updated"):
		if not professor_manager.is_connected("faculty_list_updated", Callable(self, "_on_faculty_list_updated")):
			professor_manager.faculty_list_updated.connect(Callable(self, "_on_faculty_list_updated"))
	
	self.visible = false # Start hidden

func show_panel():
	self.visible = true
	if DETAILED_LOGGING_ENABLED: print_debug("show_panel() called.")
	_refresh_all_lists()
	_clear_professor_details_panel() 
	_update_action_buttons_visibility()

func hide_panel():
	self.visible = false
	_selected_professor_object = null 
	_is_selected_an_applicant = false
	if DETAILED_LOGGING_ENABLED: print_debug("hide_panel() called.")


func _on_tab_changed(_tab_idx: int): # Parameter _tab_idx is provided by the signal
	_selected_professor_object = null
	# Assuming Tab 0 is "Hired Staff" and Tab 1 is "Applicants"
	_is_selected_an_applicant = (tab_container.current_tab == 1) 
	if DETAILED_LOGGING_ENABLED: print_debug("Tab changed. Is Applicant Tab: %s" % _is_selected_an_applicant)
	_clear_professor_details_panel()
	_update_action_buttons_visibility()
	# Lists are typically refreshed by _on_faculty_list_updated or when panel is first shown via _refresh_all_lists

func _on_faculty_list_updated():
	if DETAILED_LOGGING_ENABLED: print_debug("Signal 'faculty_list_updated' received. Refreshing lists and current selection.")
	_refresh_all_lists()
	
	# If a selected professor is no longer in the relevant list (e.g., hired from applicants, or fired from hired), clear details
	if is_instance_valid(_selected_professor_object):
		var still_exists_in_current_view = false
		var current_list_to_check: Array[Professor]
		if _is_selected_an_applicant:
			current_list_to_check = professor_manager.get_applicants()
		else:
			current_list_to_check = professor_manager.get_hired_professors()
		
		for prof_in_list in current_list_to_check:
			if is_instance_valid(prof_in_list) and prof_in_list.professor_id == _selected_professor_object.professor_id:
				still_exists_in_current_view = true
				break
		
		if not still_exists_in_current_view:
			if DETAILED_LOGGING_ENABLED: print_debug("Previously selected professor no longer in current list view. Clearing details.")
			_selected_professor_object = null
			_clear_professor_details_panel()
			_update_action_buttons_visibility()
	elif _selected_professor_object == null : 
		_clear_professor_details_panel() # Ensure details are cleared if nothing was selected
		_update_action_buttons_visibility()


func _refresh_all_lists():
	if not is_instance_valid(professor_manager):
		if DETAILED_LOGGING_ENABLED: print_debug("_refresh_all_lists: ProfessorManager is not valid. Cannot refresh.")
		return

	if DETAILED_LOGGING_ENABLED: print_debug("_refresh_all_lists: Refreshing hired staff and applicant lists.")
	
	var hired_profs_array: Array[Professor] = professor_manager.get_hired_professors()
	if DETAILED_LOGGING_ENABLED: print_debug("Hired professors count from PM for list: %d" % hired_profs_array.size())
	_populate_list_with_professors(hired_staff_list_vbox, hired_profs_array, false)

	var applicants_array: Array[Professor] = professor_manager.get_applicants()
	if DETAILED_LOGGING_ENABLED: print_debug("Applicants count from PM for list: %d" % applicants_array.size())
	_populate_list_with_professors(applicant_list_vbox, applicants_array, true)

func _populate_list_with_professors(target_vbox: VBoxContainer, prof_array: Array[Professor], is_applicant_list: bool):
	var list_type = "Applicants" if is_applicant_list else "Hired Staff"
	if DETAILED_LOGGING_ENABLED: 
		print_debug("Attempting to populate list: '%s'. Received %d professor objects for VBox: %s" % [list_type, prof_array.size(), str(target_vbox)])

	if not is_instance_valid(target_vbox): 
		if DETAILED_LOGGING_ENABLED: print_debug("Target VBox for '%s' is invalid. Cannot populate." % list_type)
		return
	if not ProfessorListItemScene:
		if DETAILED_LOGGING_ENABLED: print_debug("ProfessorListItemScene not loaded for '%s' list." % list_type)
		return
			
	for child in target_vbox.get_children(): # Clear existing items
		child.queue_free()

	if prof_array.is_empty():
		var lbl = Label.new()
		lbl.text = "No one currently in this category." if not is_applicant_list else "No new applicants available."
		target_vbox.add_child(lbl)
		if DETAILED_LOGGING_ENABLED: print_debug("'%s' list is empty. Added placeholder label." % list_type)
		return

	for prof_object in prof_array: # prof_array should now be Array[Professor]
		if not is_instance_valid(prof_object) or not prof_object is Professor: # Double check
			if DETAILED_LOGGING_ENABLED: print_debug("Skipping invalid item in prof_array for '%s' list. Item: " % list_type + str(prof_object))
			continue

		var item_instance = ProfessorListItemScene.instantiate() as ProfessorListItem
		target_vbox.add_child(item_instance)
		item_instance.setup_item(prof_object, is_applicant_list) # Pass the Professor object
		if DETAILED_LOGGING_ENABLED: print_debug("Added list item for '%s': %s (ID: %s)" % [list_type, prof_object.professor_name, prof_object.professor_id])
		
		if not item_instance.is_connected("professor_selected", Callable(self, "_on_professor_list_item_selected")):
			item_instance.professor_selected.connect(Callable(self, "_on_professor_list_item_selected"))

func _on_professor_list_item_selected(professor_id: String):
	_is_selected_an_applicant = (tab_container.current_tab == 1) # Tab 0: Hired, Tab 1: Applicants

	var found_prof: Professor = null
	if _is_selected_an_applicant:
		var applicants_list = professor_manager.get_applicants() # Get fresh list
		for applicant in applicants_list:
			if applicant.professor_id == professor_id:
				found_prof = applicant
				break
	else: # Hired staff
		found_prof = professor_manager.get_professor_by_id(professor_id)

	_selected_professor_object = found_prof # Store the actual Professor object

	if is_instance_valid(_selected_professor_object):
		if DETAILED_LOGGING_ENABLED: print_debug("Selected professor: %s (ID: %s). Is Applicant: %s" % [_selected_professor_object.professor_name, _selected_professor_object.professor_id, str(_is_selected_an_applicant)])
		_populate_professor_details_panel(_selected_professor_object)
	else:
		if DETAILED_LOGGING_ENABLED: print_debug("Could not find professor object for ID: %s in the current list view." % professor_id)
		_clear_professor_details_panel() # Clear details if selection fails
	
	_update_action_buttons_visibility()
	
	# Visual feedback for selected item in the list
	var list_vbox_to_update = applicant_list_vbox if _is_selected_an_applicant else hired_staff_list_vbox
	for item_node in list_vbox_to_update.get_children():
		if item_node is ProfessorListItem: # Check if it's the correct type
			item_node.set_selected_visual(item_node.current_professor_id == professor_id)


func _clear_professor_details_panel():
	if DETAILED_LOGGING_ENABLED: print_debug("Clearing professor details panel.")
	if is_instance_valid(detail_name_label): detail_name_label.text = "Name: -" # Check validity before access
	if is_instance_valid(detail_rank_label): detail_rank_label.text = "Rank: -"
	# ... (clear all other detail labels similarly) ...
	if is_instance_valid(detail_specialization_label): detail_specialization_label.text = "Specialization: -"
	if is_instance_valid(detail_salary_label): detail_salary_label.text = "Salary: -"
	if is_instance_valid(detail_teaching_skill_label): detail_teaching_skill_label.text = "Teaching: -"
	if is_instance_valid(detail_research_skill_label): detail_research_skill_label.text = "Research: -"
	if is_instance_valid(detail_morale_label): detail_morale_label.text = "Morale: -"
	if is_instance_valid(detail_tenure_label): detail_tenure_label.text = "Tenure: -"
	if is_instance_valid(detail_publications_label): detail_publications_label.text = "Publications: -"
	if is_instance_valid(detail_courses_label): detail_courses_label.text = "Courses: -"
	if is_instance_valid(detail_researching_label): detail_researching_label.text = "Research: -"

func _populate_professor_details_panel(prof: Professor): # Expects a Professor object
	if not is_instance_valid(prof):
		if DETAILED_LOGGING_ENABLED: print_debug("Populate details: Invalid professor object received.")
		_clear_professor_details_panel()
		return

	if DETAILED_LOGGING_ENABLED: print_debug("Populating details for: %s" % prof.professor_name)
	# Use Professor object's properties and methods directly
	if is_instance_valid(detail_name_label): detail_name_label.text = "Name: " + prof.professor_name
	if is_instance_valid(detail_rank_label): detail_rank_label.text = "Rank: " + prof.get_rank_string()
	if is_instance_valid(detail_specialization_label): detail_specialization_label.text = "Specialization: " + prof.get_specialization_string()
	if is_instance_valid(detail_salary_label): detail_salary_label.text = "Salary: $%.0f" % prof.annual_salary
	if is_instance_valid(detail_teaching_skill_label): detail_teaching_skill_label.text = "Teaching Skill: %.1f / 100" % prof.teaching_skill
	if is_instance_valid(detail_research_skill_label): detail_research_skill_label.text = "Research Skill: %.1f / 100" % prof.research_skill
	if is_instance_valid(detail_morale_label): detail_morale_label.text = "Morale: %.1f / 100" % prof.morale
	if is_instance_valid(detail_tenure_label): detail_tenure_label.text = "Tenure: " + prof.get_tenure_status_string()
	if is_instance_valid(detail_publications_label): detail_publications_label.text = "Publications: %d" % prof.publications_count
	
	var course_names_display : Array[String] = []
	if is_instance_valid(academic_manager) and prof.courses_teaching_ids.size() > 0 :
		for offering_id in prof.courses_teaching_ids:
			var offering_details = academic_manager.get_offering_details(offering_id)
			course_names_display.append(offering_details.get("course_name", offering_id.right(6) + "(ID)")) # Show course name or fallback
	if is_instance_valid(detail_courses_label): detail_courses_label.text = "Courses: " + (", ".join(course_names_display) if not course_names_display.is_empty() else "None")
	
	if is_instance_valid(detail_researching_label): detail_researching_label.text = "Research: " + ("Yes - " + prof.current_research_project_id if not prof.current_research_project_id.is_empty() else "No")

func _update_action_buttons_visibility():
	var prof_is_selected = is_instance_valid(_selected_professor_object)
	
	if is_instance_valid(hire_button): hire_button.visible = prof_is_selected and _is_selected_an_applicant
	if is_instance_valid(fire_button): fire_button.visible = prof_is_selected and not _is_selected_an_applicant
	
	var show_other_actions = prof_is_selected and not _is_selected_an_applicant
	if is_instance_valid(assign_course_button): assign_course_button.visible = show_other_actions
	if is_instance_valid(assign_research_button): assign_research_button.visible = show_other_actions
	if is_instance_valid(promote_button): promote_button.visible = show_other_actions
	if is_instance_valid(tenure_review_button): tenure_review_button.visible = show_other_actions

	# Disable based on state (example logic)
	if prof_is_selected and not _is_selected_an_applicant:
		var prof: Professor = _selected_professor_object # Safe to cast/use as Professor
		if is_instance_valid(fire_button):
			fire_button.disabled = (prof.tenure_status == Professor.TenureStatus.TENURED) # Example: can't easily fire tenured
		if is_instance_valid(tenure_review_button):
			tenure_review_button.disabled = not (prof.tenure_status == Professor.TenureStatus.TENURE_TRACK and prof.years_in_rank >= 3) # Example: 3 years for review
		if is_instance_valid(promote_button):
			promote_button.disabled = (prof.rank == Professor.Rank.FULL_PROFESSOR) 
	else: # No prof selected or applicant selected
		if is_instance_valid(fire_button): fire_button.disabled = true
		if is_instance_valid(tenure_review_button): tenure_review_button.disabled = true
		if is_instance_valid(promote_button): promote_button.disabled = true


func _on_hire_button_pressed():
	if not is_instance_valid(_selected_professor_object) or not _is_selected_an_applicant: return
	if not is_instance_valid(professor_manager): return

	var prof_to_hire: Professor = _selected_professor_object # Should be a Professor object
	
	var offered_salary = prof_to_hire.annual_salary # Default to their current salary (as applicant)
	var offer_tenure_track = (prof_to_hire.rank == Professor.Rank.ASSISTANT_PROFESSOR) # Example logic

	var success = professor_manager.hire_professor(prof_to_hire, offered_salary, offer_tenure_track)
	if success:
		if DETAILED_LOGGING_ENABLED: print_debug("Hired %s via UI." % prof_to_hire.professor_name)
		_selected_professor_object = null 
		_is_selected_an_applicant = false 
		_clear_professor_details_panel()
		# _refresh_all_lists() will be called by ProfessorManager's "faculty_list_updated" signal
	else:
		if DETAILED_LOGGING_ENABLED: print_debug("Hiring %s failed (check ProfessorManager logs for reason)." % prof_to_hire.professor_name)
		# TODO: Show an error popup to the player
	_update_action_buttons_visibility()


func _on_fire_button_pressed():
	if not is_instance_valid(_selected_professor_object) or _is_selected_an_applicant: return
	if not is_instance_valid(professor_manager): return

	var prof_to_fire: Professor = _selected_professor_object
	
	# TODO: Add a confirmation dialog: "Are you sure you want to fire Prof. X? This may affect morale/reputation."
	
	var success = professor_manager.fire_professor(prof_to_fire.professor_id)
	if success:
		if DETAILED_LOGGING_ENABLED: print_debug("Fired %s via UI." % prof_to_fire.professor_name)
		_selected_professor_object = null
		_clear_professor_details_panel()
	else:
		if DETAILED_LOGGING_ENABLED: print_debug("Firing %s failed (e.g., tenured, or check PM logs)." % prof_to_fire.professor_name)
		# TODO: Show an error popup
	_update_action_buttons_visibility()

# TODO: Implement _on_assign_course_button_pressed()
# This would likely involve:
# 1. Getting the selected professor (_selected_professor_object).
# 2. Opening/switching to the SchedulingPanel.
# 3. Pre-selecting this professor in the SchedulingPanel's instructor_dropdown.
# 4. Or, opening a dedicated dialog listing unscheduled courses that this professor is qualified for.

# TODO: Implement _on_assign_research_button_pressed()
# This would involve:
# 1. Getting the selected professor.
# 2. Opening a ResearchPanel or dialog.
# 3. Listing available research projects the professor is qualified for.
# 4. Calling ResearchManager.start_new_project(...)

# TODO: Implement _on_promote_button_pressed() & _on_tenure_review_button_pressed()
# These will call methods on ProfessorManager like:
# professor_manager.initiate_promotion_review(_selected_professor_object.professor_id)
# professor_manager.initiate_tenure_review(_selected_professor_object.professor_id)
# ProfessorManager would then handle the logic and emit signals on success/failure.

func print_debug(message_parts):
	if not DETAILED_LOGGING_ENABLED: return
	var final_message = "[FacultyPanel]: "
	if typeof(message_parts) == TYPE_STRING: final_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: 
		var temp_arr: Array = message_parts
		var string_parts: Array[String] = []
		for item in temp_arr: string_parts.append(str(item))
		final_message += String(" ").join(string_parts)
	else: final_message += str(message_parts)
	print(final_message)
