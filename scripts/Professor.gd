# Professor.gd
class_name Professor
extends RefCounted # Use RefCounted for classes that are primarily data containers

enum Rank { LECTURER, ASSISTANT_PROFESSOR, ASSOCIATE_PROFESSOR, FULL_PROFESSOR, ADJUNCT }
enum TenureStatus { NOT_ELIGIBLE, TENURE_TRACK, TENURED, DENIED_TENURE }
enum Specialization { GENERAL, COMPUTER_SCIENCE, HISTORY, PHYSICS, MATHEMATICS, ARTS, HUMANITIES } # Expand as needed

var professor_id: String
var professor_name: String
var rank: Rank = Rank.LECTURER
var tenure_status: TenureStatus = TenureStatus.NOT_ELIGIBLE
var specialization: Specialization = Specialization.GENERAL

var teaching_skill: float = 50.0 # 0-100
var research_skill: float = 30.0 # 0-100
var morale: float = 75.0       # 0-100

var annual_salary: float = 40000.0
var years_at_university: int = 0
var years_in_rank: int = 0 # For promotion/tenure tracking

var is_on_sabbatical: bool = false
var courses_teaching_ids: Array[String] = [] # List of offering_ids
var current_research_project_id: String = "" # If actively researching

var office_location_id: String = "" # Optional: link to a building/room

# Stats for tenure/promotion
var publications_count: int = 0
var grant_money_earned: float = 0.0
var student_evaluation_avg: float = -1.0 # -1 if no evaluations yet, 0-5 or 0-100 scale

func _init(p_id: String, p_name: String, p_spec: Specialization = Specialization.GENERAL, p_rank: Rank = Rank.LECTURER, p_salary: float = 40000.0):
	self.professor_id = p_id
	self.professor_name = p_name
	self.specialization = p_spec
	self.rank = p_rank
	self.annual_salary = p_salary
	
	# Initial skill randomization (example)
	self.teaching_skill = randf_range(30.0, 70.0)
	self.research_skill = randf_range(10.0, 50.0)
	if p_rank == Rank.FULL_PROFESSOR or p_rank == Rank.ASSOCIATE_PROFESSOR:
		self.teaching_skill = randf_range(50.0, 90.0)
		self.research_skill = randf_range(40.0, 85.0)
		self.publications_count = randi_range(5, 30)
		self.tenure_status = TenureStatus.TENURED # Assume higher ranks start tenured for simplicity here
	elif p_rank == Rank.ASSISTANT_PROFESSOR:
		self.tenure_status = TenureStatus.TENURE_TRACK

func get_rank_string() -> String:
	match rank:
		Rank.LECTURER: return "Lecturer"
		Rank.ASSISTANT_PROFESSOR: return "Assistant Professor"
		Rank.ASSOCIATE_PROFESSOR: return "Associate Professor"
		Rank.FULL_PROFESSOR: return "Full Professor"
		Rank.ADJUNCT: return "Adjunct Professor"
	return "Unknown Rank"

func get_tenure_status_string() -> String:
	match tenure_status:
		TenureStatus.NOT_ELIGIBLE: return "Not Eligible"
		TenureStatus.TENURE_TRACK: return "Tenure Track"
		TenureStatus.TENURED: return "Tenured"
		TenureStatus.DENIED_TENURE: return "Tenure Denied"
	return "Unknown"

func get_specialization_string() -> String:
	return Specialization.keys()[specialization].replace("_", " ").capitalize()

func get_info_summary() -> Dictionary:
	return {
		"id": professor_id,
		"name": professor_name,
		"rank": get_rank_string(),
		"tenure_status": get_tenure_status_string(),
		"specialization": get_specialization_string(),
		"teaching_skill": teaching_skill,
		"research_skill": research_skill,
		"morale": morale,
		"salary": annual_salary,
		"years_at_university": years_at_university,
		"courses_teaching_count": courses_teaching_ids.size(),
		"researching": not current_research_project_id.is_empty(),
		"publications": publications_count,
	}

# Add more methods as needed:
# - update_for_new_year() (increment years, check promotion/tenure eligibility)
# - assign_course(offering_id)
# - remove_course(offering_id)
# - assign_research(project_id)
# - complete_research_project(outcome) -> for ResearchManager to call
# - calculate_next_salary() -> based on rank, performance
# - update_morale(change_amount, reason_string)
