# ProgramResource.gd
class_name ProgramResource
extends Resource

@export var program_id: String = ""
@export var program_name: String = ""
@export var credits_to_graduate: float = 120.0
@export var unlock_cost: int = 5000
# semesters_per_year can be removed if we hardcode 2, or kept for future flexibility
@export_range(1, 3, 1) var semesters_per_year: int = 2 # Default to 2, max 3 if you want summer

# --- MODIFIED LINES ---
# List of CourseResources belonging to this program
@export var courses_in_program_resources: Array[CourseResource] = [] 
# Flat list of mandatory CourseResources for easy graduation checks
@export var mandatory_courses_resources: Array[CourseResource] = []  
# --- END MODIFIED LINES ---
