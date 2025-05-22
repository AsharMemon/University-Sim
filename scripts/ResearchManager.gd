# ResearchManager.gd
class_name ResearchManager
extends Node

signal research_project_started(project_id: String, professor_id: String)
signal research_project_completed(project_id: String, outcome: Dictionary) # outcome can include publications, grants, reputation_change

@export var university_data: UniversityData
@export var time_manager: TimeManager
@export var professor_manager: ProfessorManager

var active_research_projects: Dictionary = {} # project_id: {details, prof_id, progress, budget_spent}

func _ready():
	# TODO: Connect to TimeManager signals for daily/monthly progress updates
	print("ResearchManager ready.")

func start_new_project(project_template_id: String, assigned_professor_id: String, allocated_budget: float) -> bool:
	if not is_instance_valid(university_data) or not is_instance_valid(professor_manager):
		printerr("ResearchManager: Missing UniversityData or ProfessorManager.")
		return false
		
	var prof: Professor = professor_manager.get_professor_by_id(assigned_professor_id)
	if not is_instance_valid(prof) or not prof.current_research_project_id.is_empty():
		printerr("ResearchManager: Professor %s not found or already on a project." % assigned_professor_id)
		return false

	# TODO: Get project_template_details from UniversityData
	# var project_details = university_data.get_research_project_template(project_template_id)
	# if project_details.is_empty(): printerr("..."); return false
	
	var new_project_id = "research_%s_%s" % [assigned_professor_id, str(Time.get_unix_time_from_system()).right(6)]
	active_research_projects[new_project_id] = {
		"template_id": project_template_id,
		# "name": project_details.get("name"),
		"professor_id": assigned_professor_id,
		# "duration_days": project_details.get("duration_days"),
		"progress_days": 0,
		"budget_allocated": allocated_budget,
		"budget_spent": 0.0
	}
	prof.current_research_project_id = new_project_id
	emit_signal("research_project_started", new_project_id, assigned_professor_id)
	print("ResearchManager: Professor %s started project %s." % [prof.professor_name, new_project_id])
	return true
	
# TODO:
# - func _update_research_progress(delta_days_or_sim_time)
# - func complete_project(project_id, success_level) -> emits outcome
# - func request_research_budget(project_id, amount)
