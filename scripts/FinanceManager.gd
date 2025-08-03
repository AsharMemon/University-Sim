# FinanceManager.gd
# This script manages all financial aspects of the university.
# It operates as a regular node and needs references to other managers.
extends Node

# --- EXPORTED NODE REFERENCES ---
# By using class_name in your other scripts, you can use them as types here.
# This fixes the error by telling Godot what kind of node to expect.
@export var time_manager: TimeManager
@export var student_manager: StudentManager
@export var faculty_manager: ProfessorManager

# --- SIGNALS ---
# Signals to notify other parts of the game about financial changes.
signal balance_updated(new_balance: float)
signal financials_updated(income: float, expenses: float)

# --- FINANCIAL STATE ---
var current_balance: float = 250000.00 # Starting money
var last_term_income: float = 0.0
var last_term_expenses: float = 0.0

# --- CONFIGURATION ---
const UNDERGRADUATE_TUITION: float = 10000.0
const GRADUATE_TUITION: float = 12000.0


func _ready() -> void:
	# We connect to the TimeManager's year_passed signal via our reference.
	if time_manager:
		# This line now works because Godot knows time_manager is a TimeManager
		# and has the year_passed signal.
		time_manager.year_passed.connect(_on_year_passed)
	else:
		push_error("FinanceManager is missing its reference to TimeManager!")

# This is the main function that drives the economy each year.
func _on_year_passed() -> void:
	print("FinanceManager: Calculating end-of-year finances.")
	
	# 1. Calculate Income from student tuition
	last_term_income = _calculate_tuition_income()
	
	# 2. Calculate Expenses from faculty salaries
	last_term_expenses = _calculate_salary_expenses()
	
	# 3. Calculate the net change and update the balance
	var net_change = last_term_income - last_term_expenses
	current_balance += net_change
	
	# 4. Emit signals to update the UI and other game systems
	balance_updated.emit(current_balance)
	financials_updated.emit(last_term_income, last_term_expenses)
	print("Income: %d, Expenses: %d, Net: %d, New Balance: %d" % [last_term_income, last_term_expenses, net_change, current_balance])


# --- Private Helper Functions ---

func _calculate_tuition_income() -> float:
	var total_tuition: float = 0.0
	
	# Check if the StudentManager reference is set
	if not student_manager:
		push_error("FinanceManager is missing its reference to StudentManager!")
		return 0.0
		
	# Loop through all students and add their tuition to the total.
	for student in student_manager.student_list:
		match student.student_type:
			"Undergraduate":
				total_tuition += UNDERGRADUATE_TUITION
			"Graduate":
				total_tuition += GRADUATE_TUITION
				
	return total_tuition


func _calculate_salary_expenses() -> float:
	var total_salaries: float = 0.0
	
	# Check if the FacultyManager reference is set
	if not faculty_manager:
		push_error("FinanceManager is missing its reference to FacultyManager!")
		return 0.0

	# Loop through all faculty and add their salary to the total.
	for faculty_member in faculty_manager.faculty_list:
		if "salary" in faculty_member:
			total_salaries += faculty_member.salary
		else:
			print("WARNING: Faculty member %s is missing a salary property." % faculty_member.name)
			
	return total_salaries
