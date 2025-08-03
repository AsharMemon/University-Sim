# FinancialsUI.gd
extends HBoxContainer

# --- EXPORTED NODE REFERENCE ---
# Drag your FinanceManager node onto this slot in the Godot Inspector.
@export var finance_manager: Node

# --- Node References ---
@onready var balance_label: Label = $PanelContainer/HBoxContainer/BalanceValueLabel
@onready var income_label: Label = $PanelContainer/HBoxContainer/IncomeValueLabel
@onready var expenses_label: Label = $PanelContainer/HBoxContainer/ExpensesValueLabel


func _ready() -> void:
	# Check if the reference has been set in the editor.
	if finance_manager:
		# Connect to the FinanceManager's signals to receive updates.
		finance_manager.balance_updated.connect(_on_balance_updated)
		finance_manager.financials_updated.connect(_on_financials_updated)
		
		# Set the initial display values from the reference when the game starts.
		_on_balance_updated(finance_manager.current_balance)
		_on_financials_updated(finance_manager.last_term_income, finance_manager.last_term_expenses)
	else:
		push_error("FinancialsUI is missing its reference to the FinanceManager node!")
		# Optionally disable the UI if the manager is missing
		self.visible = false


# --- Signal Handlers ---

func _on_balance_updated(new_balance: float) -> void:
	# Format the balance as currency with commas.
	balance_label.text = "$%s" % _format_number(new_balance)

func _on_financials_updated(income: float, expenses: float) -> void:
	# Format income and expenses as currency.
	income_label.text = "$%s" % _format_number(income)
	expenses_label.text = "$%s" % _format_number(expenses)

# Helper function to add commas to large numbers for readability.
func _format_number(num: float) -> String:
	var s = "%.2f" % num
	var parts = s.split(".")
	var integer_part = parts[0]
	var decimal_part = parts[1]
	
	var c = len(integer_part) % 3
	if c == 0:
		c = 3
	
	var result = ""
	while integer_part != "":
		result += integer_part.substr(0, c)
		integer_part = integer_part.substr(c)
		c = 3
		if integer_part != "":
			result += ","
			
	return result + "." + decimal_part
