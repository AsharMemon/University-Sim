# BuildingManager.gd
# Manages building placement, game economy, NavMesh baking, UI interactions, game events, and university reputation.
class_name BuildingManager
extends Node3D

# --- Constants ---
const GRID_CELL_SIZE: float = 2.0
const EFFECTIVE_GROUND_NAVMESH_Y_FOR_REFERENCE: float = 2.4

# --- Module Data (Defines properties of different building modules) ---
var module_data = {
	"Block_Solid": {
		"path": "res://Modules/Block_Solid.glb", "weight": 15, "building_type": "generic",
		"base_annual_income": 0, "base_annual_expense": 10,
		"rotations": {
			"0": {"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE", "Back":"SIDE_STONE", "Right":"SIDE_STONE", "Left":"SIDE_STONE"}
		},
		"fulfills_needs": {},
		"capacity_per_block": 0
	},
	"Dorm_Wall": {
		"path": "res://Modules/Block_Solid.glb", "weight": 10, "building_type": "dorm", # This is its actual_module_type
		"base_annual_income": 50, "base_annual_expense": 20,
		"rotations": {
			"0": {"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE", "Back":"SIDE_STONE", "Right":"SIDE_STONE", "Left":"SIDE_STONE"}
		},
		"fulfills_needs": {"rest": 25},
		"provides_need_satisfaction_radius": 3.0,
		"capacity_per_block": 2 # Inherent capacity
	},
	"Class_Window": {
		"path": "res://Modules/Block_Decor_WindowSlit.glb", "weight": 8, "building_type": "class", # This is its actual_module_type
		"base_annual_income": 10, "base_annual_expense": 30,
		"rotations": {
			"0":	{"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_WINDOW",  "Back":"SIDE_STONE",    "Right":"SIDE_STONE",    "Left":"SIDE_STONE"}
		},
		"fulfills_needs": {"study": 20},
		"provides_need_satisfaction_radius": 3.0,
		"capacity_per_block": 5 # Inherent capacity
	},
	"Block_Corner_Outer_Sharp": {
		"path": "res://Modules/Block_Corner_Outer_Sharp.glb", "weight": 5, "building_type": "generic",
		"base_annual_income": 0, "base_annual_expense": 5, "rotations": {
			"0":	{"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"CORNER_SHARP_A", "Back":"SIDE_STONE",	  "Right":"CORNER_SHARP_B", "Left":"SIDE_STONE"},
			"90":	{"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE",	  "Back":"CORNER_SHARP_A", "Right":"SIDE_STONE", "Left":"CORNER_SHARP_B"},
			"180":  {"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE",	  "Back":"CORNER_SHARP_A", "Right":"SIDE_STONE",	  "Left":"CORNER_SHARP_B"},
			"270":  {"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"CORNER_SHARP_A", "Back":"SIDE_STONE",	  "Right":"SIDE_STONE",	  "Left":"CORNER_SHARP_B"}
		}, "fulfills_needs": {}, "capacity_per_block": 0
	},
	"Block_Corner_Outer_Round": {
		"path": "res://Modules/Block_Corner_Outer_Round.glb", "weight": 4, "building_type": "generic",
		"base_annual_income": 0, "base_annual_expense": 5, "rotations": {
			"0":	{"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"CORNER_ROUND", "Back":"SIDE_STONE",    "Right":"CORNER_ROUND", "Left":"SIDE_STONE"},
			"90":	{"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE",    "Back":"CORNER_ROUND", "Right":"SIDE_STONE", "Left":"CORNER_ROUND"},
			"180":  {"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE",    "Back":"CORNER_ROUND", "Right":"SIDE_STONE",    "Left":"CORNER_ROUND"},
			"270":  {"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"CORNER_ROUND", "Back":"SIDE_STONE",    "Right":"SIDE_STONE",    "Left":"CORNER_ROUND"}
		}, "fulfills_needs": {}, "capacity_per_block": 0
	},
	"Block_Top_Battlement": {
		"path": "res://Modules/Block_Top_Battlement.glb", "weight": 2, "building_type": "generic",
		"base_annual_income": 0, "base_annual_expense": 2, "rotations": {
			"0": {"Top":"TOP_BATTLEMENT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE", "Back":"SIDE_STONE", "Right":"SIDE_STONE", "Left":"SIDE_STONE"}
		}, "fulfills_needs": {}, "capacity_per_block": 0
	},
	"Block_Top_Slope": {
		"path": "res://Modules/Block_Top_Slope.glb", "weight": 2, "building_type": "generic",
		"base_annual_income": 0, "base_annual_expense": 2, "rotations": {
			"0": {"Top":"TOP_SLOPE", "Bottom":"BOTTOM_STONE", "Front":"SIDE_STONE", "Back":"SIDE_STONE", "Right":"SIDE_STONE", "Left":"SIDE_STONE"}
		}, "fulfills_needs": {}, "capacity_per_block": 0
	}
}

# --- Node References ---
@onready var camera_3d: Camera3D = $CameraRig/Camera3D
@export var time_manager: TimeManager # Found in _ready
@onready var navigation_region: NavigationRegion3D = get_node_or_null("NavigationRegion3D") as NavigationRegion3D
@onready var ground_node: StaticBody3D = get_node_or_null("NavigationRegion3D/Ground") as StaticBody3D
@onready var nav_mesh_block_parent: Node3D
@onready var student_manager: Node = null # Found by path in _ready
@onready var capacity_labels_parent: Node3D = null

# --- Academic Manager Reference (NEW for Reputation) ---
@export var academic_manager_node: AcademicManager # Assign in Godot Editor

# UI Elements (General) - Paths based on user's last provided script
@export var date_label: Label
@export var speed_label: Label
@export var pause_button: Button
@export var play_button: Button
@export var ff_button: Button
@export var income_label: Label
@export var expenses_label: Label
@export var endowment_label: Label
@export var reputation_label: Label # NEW for Reputation display
@export var total_students_label: Label # <<< NEW VARIABLE (add with other UI @onready vars)

# --- UI References for Student Roster ---
@export var view_students_button: Button # Path set in _ready
@export var student_list_panel: PanelContainer # Adjust path if needed
@export var student_list_vbox: VBoxContainer # Path set in _ready
@export var close_student_panel_button: Button # Path set in _ready

# --- UI References for Program Management --- (NEW)
@export var view_programs_button: Button # Path set in _ready
@export var program_management_panel: PanelContainer # Adjust path if needed

# --- UI References for Scheduling Panel --- (NEW SECTION)
@export var view_schedule_button: Button # Path set in _ready
@export var scheduling_panel: PanelContainer # Adjust path if needed

var student_list_item_scene: PackedScene = preload("res://scenes/StudentListItem.tscn")
var capacity_label_scene: PackedScene = preload("res://scenes/CapacityLabel3D.tscn")


# --- WFC Solver ---
const WfcSolverClass = preload("res://scripts/WfcSolver.gd")
var wfc_solver: WfcSolver

# --- State Variables ---
var occupied_cells: Dictionary = {}
var placed_block_nodes: Array[Node3D] = []
var current_selected_building_type: String = "generic" # This is the player's INTENT
var current_endowment: float = 10000.0
var total_annual_income: float = 500.0
var total_annual_expenses: float = 200.0
var _initial_bake_done: bool = false

# --- Functional Building Management ---
var functional_buildings: Dictionary = {}
const BlockFacilityScript = preload("res://scripts/BlockFacility.gd")

# --- NEW: University Reputation ---
var university_reputation: float = 40.0 # Initial reputation (0-100 scale)


func _ready():
	# Find TimeManager (critical)
	time_manager = get_node_or_null("TimeManager") 
	if not is_instance_valid(time_manager):
		time_manager = get_node_or_null("/root/MainScene/TimeManager") # Fallback path
		if not is_instance_valid(time_manager):
			printerr("CRITICAL: BuildingManager: TimeManager node not found! Game may not function.")
			get_tree().quit(); return
	
	# Find AcademicManager (for reputation)
	if not is_instance_valid(academic_manager_node): # If not assigned in editor
		academic_manager_node = get_node_or_null("/root/MainScene/AcademicManager") # Fallback path
		if not is_instance_valid(academic_manager_node):
			print_debug("Warning: BuildingManager: AcademicManager node not found. Reputation calculations will be limited.")

	var editor_blocks_organizational_node = get_node_or_null("PlacedBlocksOrganizational_EditorOnly")
	if not editor_blocks_organizational_node:
		editor_blocks_organizational_node = Node3D.new()
		editor_blocks_organizational_node.name = "PlacedBlocksOrganizational_EditorOnly"
		add_child(editor_blocks_organizational_node)

	capacity_labels_parent = get_node_or_null("CapacityLabels") as Node3D
	if not is_instance_valid(capacity_labels_parent):
		capacity_labels_parent = Node3D.new()
		capacity_labels_parent.name = "CapacityLabels"
		add_child(capacity_labels_parent)
		print_debug("Created 'CapacityLabels' node to hold 3D capacity displays.")

	if not navigation_region:
		printerr("CRITICAL: NavigationRegion3D node not found.")
	else:
		if not navigation_region.navigation_mesh:
			printerr("CRITICAL: NavigationRegion3D missing NavigationMesh resource!")
		
		nav_mesh_block_parent = navigation_region.get_node_or_null("RuntimeBakedBlocks") as Node3D
		if not nav_mesh_block_parent:
			nav_mesh_block_parent = Node3D.new()
			nav_mesh_block_parent.name = "RuntimeBakedBlocks"
			navigation_region.add_child(nav_mesh_block_parent)

	if not ground_node:
		printerr("CRITICAL: Ground node not found.")
	elif not ground_node is StaticBody3D:
		printerr("CRITICAL: Ground node is not a StaticBody3D!")

	student_manager = get_node_or_null("StudentManager") # Adjust path if needed
	if not student_manager:
		print_debug("Warning: BuildingManager: StudentManager node not found!")
	elif not student_manager.has_method("on_initial_navmesh_baked"):
		print_debug("Warning: BuildingManager: Assigned StudentManager node incorrect type.")
		student_manager = null

	wfc_solver = WfcSolverClass.new()
	if not wfc_solver.initialize(Vector3i.ONE, module_data):
		printerr("Failed to initialize WFC Solver!");

	# Connect TimeManager signals
	if time_manager:
		if not time_manager.date_changed.is_connected(_on_time_manager_date_changed):
			time_manager.date_changed.connect(_on_time_manager_date_changed)
		if not time_manager.pause_state_changed.is_connected(_on_time_manager_pause_state_changed):
			time_manager.pause_state_changed.connect(_on_time_manager_pause_state_changed)
		if not time_manager.speed_changed.is_connected(_on_time_manager_speed_changed):
			time_manager.speed_changed.connect(_on_time_manager_speed_changed)
		# Connect new_year_started for financial updates
		if time_manager.has_signal("new_year_started") and \
		   not time_manager.new_year_started.is_connected(_on_time_manager_new_year_started):
			time_manager.new_year_started.connect(_on_time_manager_new_year_started)
		# Connect new_year_started for reputation updates (can connect multiple Callables to one signal)
		if time_manager.has_signal("new_year_started") and \
		   not time_manager.is_connected("new_year_started", Callable(self, "update_reputation_and_ui")):
			var err = time_manager.connect("new_year_started", Callable(self, "update_reputation_and_ui"))
			if err == OK: print_debug("BuildingManager connected to TimeManager.new_year_started for reputation updates.")
			else: printerr("Failed to connect BM to TimeManager.new_year_started for reputation. Error: %s" % err)

		if time_manager.has_signal("new_day_has_started") and \
		   not time_manager.new_day_has_started.is_connected(_on_time_manager_new_day_has_started):
			time_manager.new_day_has_started.connect(_on_time_manager_new_day_has_started)
	else:
		printerr("BuildingManager: TimeManager is null in _ready, cannot connect crucial signals.")

	var top_ui_node_for_hud = get_node_or_null("TopUI") 
	if top_ui_node_for_hud:
		var main_hud_panel_hbox = top_ui_node_for_hud.get_node_or_null("Panel/HBoxContainer") 
		if main_hud_panel_hbox:
			date_label = main_hud_panel_hbox.get_node_or_null("DateLabel") as Label
			speed_label = main_hud_panel_hbox.get_node_or_null("SpeedLabel") as Label
			pause_button = main_hud_panel_hbox.get_node_or_null("PauseButton") as Button
			play_button = main_hud_panel_hbox.get_node_or_null("PlayButton") as Button
			ff_button = main_hud_panel_hbox.get_node_or_null("FastForwardButton") as Button
			
			var finance_vbox = main_hud_panel_hbox.get_node_or_null("VBoxContainer") 
			if finance_vbox:
				income_label = finance_vbox.get_node_or_null("IncomeLabel") as Label
				expenses_label = finance_vbox.get_node_or_null("ExpensesLabel") as Label
				endowment_label = finance_vbox.get_node_or_null("EndowmentLabel") as Label
				reputation_label = finance_vbox.get_node_or_null("ReputationLabel") as Label
				total_students_label = finance_vbox.get_node_or_null("TotalStudentsLabel") as Label # <<< ADD THIS LINE

				if not is_instance_valid(reputation_label):
					print_debug("Warning: ReputationLabel node not found in UI (expected path: TopUI/Panel/HBoxContainer/VBoxContainer/ReputationLabel).")
					
				if not is_instance_valid(total_students_label):
					print_debug("Warning: TotalStudentsLabel node not found in UI (expected at TopUI/Panel/HBoxContainer/VBoxContainer/TotalStudentsLabel).")
					
			# ... (else for finance_vbox not found) ...
		else:
			print_debug("Warning: HBoxContainer for HUD elements not found under TopUI/Panel.")

		var select_dorm_button = top_ui_node_for_hud.get_node_or_null("SelectDormButton") as Button
		var select_class_button = top_ui_node_for_hud.get_node_or_null("SelectClassButton") as Button
		var select_generic_button = top_ui_node_for_hud.get_node_or_null("SelectGenericButton") as Button

		if pause_button and not pause_button.is_connected("pressed", Callable(self, "_on_pause_button_pressed")): pause_button.pressed.connect(Callable(self, "_on_pause_button_pressed"))
		if play_button and not play_button.is_connected("pressed", Callable(self, "_on_play_button_pressed")): play_button.pressed.connect(Callable(self, "_on_play_button_pressed"))
		if ff_button and not ff_button.is_connected("pressed", Callable(self, "_on_ff_button_pressed")): ff_button.pressed.connect(Callable(self, "_on_ff_button_pressed"))
		if select_dorm_button and not select_dorm_button.is_connected("pressed", Callable(self, "_on_select_dorm_pressed")): select_dorm_button.pressed.connect(Callable(self, "_on_select_dorm_pressed"))
		if select_class_button and not select_class_button.is_connected("pressed", Callable(self, "_on_select_class_pressed")): select_class_button.pressed.connect(Callable(self, "_on_select_class_pressed"))
		if select_generic_button and not select_generic_button.is_connected("pressed", Callable(self, "_on_select_generic_pressed")): select_generic_button.pressed.connect(Callable(self, "_on_select_generic_pressed"))
		
		if is_instance_valid(view_students_button):
			if not view_students_button.is_connected("pressed", Callable(self, "_on_view_students_button_pressed")):
				view_students_button.pressed.connect(Callable(self, "_on_view_students_button_pressed"))
		else: 
			print_debug("Warning: ViewStudentsButton not found at 'TopUI/Panel/HBoxContainer/ViewStudentsButton'.")

		if is_instance_valid(view_programs_button):
			if not view_programs_button.is_connected("pressed", Callable(self, "_on_view_programs_button_pressed")):
				view_programs_button.pressed.connect(Callable(self, "_on_view_programs_button_pressed"))
		else:
			print_debug("Warning: ViewProgramsButton not found at 'TopUI/Panel/HBoxContainer/ViewProgramsButton'.")
		
		if is_instance_valid(view_schedule_button):
			if not view_schedule_button.is_connected("pressed", Callable(self, "_on_view_schedule_button_pressed")):
				view_schedule_button.pressed.connect(Callable(self, "_on_view_schedule_button_pressed"))
		else:
			print_debug("Warning: ViewScheduleButton not found at 'TopUI/Panel/HBoxContainer/ViewScheduleButton'.")
	
	else: 
		print_debug("Warning: TopUI node not found. Main HUD UI might not function.")
		# Fallback paths for panels if TopUI is not found (less ideal)
		student_list_panel = get_node_or_null("StudentListPanel") as PanelContainer 
		program_management_panel = get_node_or_null("ProgramManagementPanel") as PanelContainer
		scheduling_panel = get_node_or_null("SchedulingPanel") as PanelContainer

	# Connect to StudentManager's new signal
	if is_instance_valid(student_manager): # Make sure student_manager is valid first
		if student_manager.has_signal("student_population_changed"): # Check if signal exists
			if not student_manager.is_connected("student_population_changed", Callable(self, "_on_student_population_changed")):
				var err = student_manager.connect("student_population_changed", Callable(self, "_on_student_population_changed"))
				if err == OK: 
					print_debug("BuildingManager connected to StudentManager.student_population_changed.")
				else: 
					printerr("BuildingManager: Failed to connect to student_population_changed. Error: %s" % err)
		else:
			print_debug("Warning: StudentManager does not have 'student_population_changed' signal. Student count UI may not update reactively.")
		
		# Initial update for student count right after connecting (if possible)
		if student_manager.has_method("get_total_student_count"):
			_update_total_students_label(student_manager.get_total_student_count())
		else: # Fallback if method not ready or doesn't exist
			_update_total_students_label(0) 
			print_debug("Warning: StudentManager missing get_total_student_count for initial UI setup.")
	else:
		print_debug("Warning: StudentManager not found in _ready. Cannot connect student_population_changed signal or get initial count.")
		_update_total_students_label(0) # Default to 0 if no student manager

	# Student List Panel setup
	if is_instance_valid(student_list_panel):
		student_list_vbox = student_list_panel.get_node_or_null("MarginContainer/VBoxContainer/StudentScrollContainer/StudentListVBox") as VBoxContainer
		close_student_panel_button = student_list_panel.get_node_or_null("MarginContainer/VBoxContainer/CloseStudentPanelButton") as Button
		if is_instance_valid(close_student_panel_button):
			if not close_student_panel_button.is_connected("pressed", Callable(self, "_on_close_student_panel_button_pressed")):
				close_student_panel_button.pressed.connect(Callable(self, "_on_close_student_panel_button_pressed"))
		else:
			print_debug("Warning: CloseStudentPanelButton not found.")
		student_list_panel.visible = false 
	else:
		print_debug("Warning: StudentListPanel not found.")
		
	# Program Management Panel setup
	if is_instance_valid(program_management_panel):
		program_management_panel.visible = false
	else:
		print_debug("Warning: ProgramManagementPanel not found.")

	# Schedules Panel setup
	if is_instance_valid(scheduling_panel):
		scheduling_panel.visible = false
	else: # Fallback attempt if not a direct child
		scheduling_panel = get_tree().root.get_node_or_null("MainScene/SchedulingPanel") # ADJUST THIS FALLBACK PATH
		if is_instance_valid(scheduling_panel):
			scheduling_panel.visible = false
		else:
			print_debug("Warning: SchedulingPanel not found. Please check its path.")

	if time_manager: # Ensure time_manager is valid before calling
		_on_time_manager_date_changed(time_manager.get_current_day(), time_manager.get_current_month(), time_manager.get_current_year())
		_on_time_manager_pause_state_changed(time_manager.get_is_paused())
		_on_time_manager_speed_changed(time_manager.get_speed_multiplier())
	
	update_reputation_and_ui() # Initial reputation calc and full UI update
		
	if not student_list_item_scene: printerr("CRITICAL - Failed to preload StudentListItem.tscn.")
	if not capacity_label_scene: printerr("CRITICAL - Failed to preload CapacityLabel3D.tscn.")

	if navigation_region and navigation_region.navigation_mesh and not _initial_bake_done:
		call_deferred("perform_initial_bake")
		_initial_bake_done = true
	elif _initial_bake_done and student_manager and student_manager.has_method("on_initial_navmesh_baked"):
		student_manager.on_initial_navmesh_baked() # Call if bake already done

	print_debug("BuildingManager ready. Select building type, Left Click to place/expand. 'C' to clear.")

# --- NEW function to specifically update the student count label ---
func _update_total_students_label(count: int):
	if is_instance_valid(total_students_label):
		total_students_label.text = "Students: %d" % count
	else:
		# This print is useful for debugging if the label isn't found in the scene
		# print_debug("(UI TotalStudentsLabel not found) Actual Total Students: %d" % count) 
		pass # Avoid spamming if label is intentionally not there

# --- NEW Signal Handler from StudentManager ---
func _on_student_population_changed(new_count: int):
	print_debug("Received student_population_changed signal. New count: %d. Updating UI." % new_count)
	_update_total_students_label(new_count)
	
func perform_initial_bake():
	rebake_navigation_mesh(true) # Synchronous bake
	if student_manager and student_manager.has_method("on_initial_navmesh_baked"):
		student_manager.on_initial_navmesh_baked()

func rebake_navigation_mesh(synchronous_bake: bool = false):
	if not navigation_region or not navigation_region.navigation_mesh is NavigationMesh: return
	#print_debug("Rebaking navigation mesh... Synchronous: %s" % synchronous_bake)
	navigation_region.bake_navigation_mesh(synchronous_bake)
	if synchronous_bake:
		await get_tree().physics_frame # Wait for physics server
		await get_tree().process_frame # Wait for visual server
		print_debug("Synchronous NavMesh bake complete.")


# --- UI Callbacks & TimeManager Signal Handlers ---
func _on_select_dorm_pressed(): current_selected_building_type = "dorm"; print_debug("Selected: DORM (Capacity per block: 2)")
func _on_select_class_pressed(): current_selected_building_type = "class"; print_debug("Selected: CLASS (Capacity per block: 5)")
func _on_select_generic_pressed(): current_selected_building_type = "generic"; print_debug("Selected: GENERIC (Capacity per block: 0)")

func _on_pause_button_pressed(): if time_manager: time_manager.set_paused(true)
func _on_play_button_pressed(): if time_manager: time_manager.set_speed(1.0) # This also unpauses
func _on_ff_button_pressed():
	if time_manager:
		if time_manager.get_is_paused() or time_manager.get_speed_multiplier() < 2.0: time_manager.set_speed(2.0)
		elif time_manager.get_speed_multiplier() < 5.0: time_manager.set_speed(5.0)
		else: time_manager.set_speed(1.0) # Cycle back to 1x

func _on_time_manager_date_changed(day: int, month: int, year: int):
	if date_label: date_label.text = "Day: %d, Month: %d, Year: %d" % [day, month, year]

func _on_time_manager_new_day_has_started(day: int, month: int, year: int): # Parameters provided by TimeManager
	if is_instance_valid(student_manager) and student_manager.has_method("update_all_students_daily_activities"):
		student_manager.update_all_students_daily_activities()

func _on_time_manager_pause_state_changed(is_paused: bool):
	if speed_label:
		if is_paused: speed_label.text = "Speed: PAUSED"
		else: speed_label.text = "Speed: %.1fx" % time_manager.get_speed_multiplier() if time_manager else "Speed: N/A"
	if play_button: play_button.disabled = not is_paused and (time_manager.get_speed_multiplier() == 1.0 if time_manager else false)
	if pause_button: pause_button.disabled = is_paused
	if ff_button: ff_button.disabled = is_paused # Fast forward button usually disabled when paused

func _on_time_manager_speed_changed(new_speed: float):
	if speed_label:
		if time_manager and time_manager.get_is_paused(): speed_label.text = "Speed: PAUSED"
		else: speed_label.text = "Speed: %.1fx" % new_speed
	if time_manager: _on_time_manager_pause_state_changed(time_manager.get_is_paused()) # Update related button states

func _on_time_manager_new_year_started(year: int): # This is for Jan 1st usually
	print_debug("New Financial Year Started: " + str(year) + ". Processing annual finances.")
	var income_from_blocks: float = 0.0
	var expenses_from_blocks: float = 0.0
	for coord_key in occupied_cells:
		var block_data = occupied_cells[coord_key]
		var module_key_val = block_data.get("module_key")
		if module_key_val and module_data.has(module_key_val):
			var m_info = module_data[module_key_val]
			income_from_blocks += m_info.get("base_annual_income", 0.0)
			expenses_from_blocks += m_info.get("base_annual_expense", 0.0)
	
	var base_income = 500.0 # Your original base income
	var base_expenses = 200.0 # Your original base expenses
	total_annual_income = base_income + income_from_blocks
	total_annual_expenses = base_expenses + expenses_from_blocks
	var surplus_deficit = total_annual_income - total_annual_expenses
	current_endowment += surplus_deficit
	
	# Reputation is updated via update_reputation_and_ui(), also connected to new_year_started.
	# We just need to ensure the financial UI (which now includes reputation text) is updated.
	update_financial_ui() 
	
	# The student daily updates are better suited for _on_time_manager_new_day_has_started
	# if is_instance_valid(student_manager) and student_manager.has_method("update_all_students_daily_activities"):
	# 	student_manager.update_all_students_daily_activities()


func update_financial_ui(): # Renamed from original, now updates all relevant financial and reputation UI
	if income_label: income_label.text = "Income (Annual): $" + str(snappedf(total_annual_income, 0.01))
	if expenses_label: expenses_label.text = "Expenses (Annual): $" + str(snappedf(total_annual_expenses, 0.01))
	if endowment_label: endowment_label.text = "Endowment: $" + str(snappedf(current_endowment, 0.01))
	# NEW: Update reputation display
	if is_instance_valid(reputation_label): 
		reputation_label.text = "Reputation: %.1f / 100" % university_reputation
	# else: # Optional: print if label not found, but can be noisy.
		# print_debug("(UI Rep Label not found) Current Reputation: %.1f / 100" % university_reputation)


# --- NEW: University Reputation Functions ---
func update_reputation_and_ui(_year_for_signal_compatibility = 0): # Parameter for signal if TimeManager sends it
	var base_rep: float = 30.0  # Base reputation value for a new university
	var rep_from_progs: float = 0.0
	var rep_from_finance: float = 0.0
	# Future factors could include: student graduation rates, research output, campus beauty, etc.

	if is_instance_valid(academic_manager_node):
		if academic_manager_node.has_method("get_all_unlocked_program_ids"):
			var unlocked_programs_list: Array[String] = academic_manager_node.get_all_unlocked_program_ids()
			rep_from_progs = float(unlocked_programs_list.size()) * 4.0 # Example: 4 reputation points per unlocked program
			rep_from_progs = clampi(rep_from_progs, 0.0, 40.0) # Cap contribution from programs (e.g., max 40 points from 10 programs)
		else:
			print_debug("Warning: AcademicManager is missing 'get_all_unlocked_program_ids' method. Reputation from programs not calculated.")
	else:
		print_debug("BuildingManager: AcademicManager reference not set. Cannot calculate reputation from programs.")

	# Endowment contribution (example: logarithmic scaling, capped)
	if current_endowment > 10000: # Check for a minimum endowment to avoid math errors with log(0) or very small numbers
		# Adjust the divisor (10000.0) and multiplier (6.0) to scale the effect of endowment on reputation
		rep_from_finance = log(current_endowment / 10000.0) * 6.0 
		rep_from_finance = clampi(rep_from_finance, 0.0, 30.0) # Cap contribution from finances
	
	university_reputation = clampi(base_rep + rep_from_progs + rep_from_finance, 0.0, 100.0) # Clamp reputation between 0 and 100
	print_debug("University reputation calculated and updated to: %.1f / 100" % university_reputation)
	
	update_financial_ui() # This will refresh all financial UI elements, including the reputation label


func get_university_reputation() -> float:
	return university_reputation


# --- Input Handling & Placement Logic ---
func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		var clicked_on_ui = false
		# Check TopUI Panel itself
		var top_ui_panel_node = get_node_or_null("TopUI/Panel") # Ensure this path is correct for your TopUI panel
		if top_ui_panel_node and top_ui_panel_node is Control and top_ui_panel_node.visible:
			if top_ui_panel_node.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
		
		# Check specific buttons within TopUI if not already caught by panel
		var top_ui_node = get_node_or_null("TopUI") # Your main UI node
		if not clicked_on_ui and top_ui_node and top_ui_node is Control and top_ui_node.visible:
			# Add any other top-level buttons here if needed for UI click detection
			var select_buttons = ["SelectDormButton", "SelectClassButton", "SelectGenericButton", 
								  "PauseButton", "PlayButton", "FastForwardButton", 
								  "ViewStudentsButton", "ViewProgramsButton", "ViewScheduleButton"] 
			for btn_name in select_buttons:
				var btn = top_ui_node.get_node_or_null("Panel/HBoxContainer/" + btn_name) # Assuming common path prefix
				if not is_instance_valid(btn): # Fallback for buttons directly under TopUI
					btn = top_ui_node.get_node_or_null(btn_name)
				if is_instance_valid(btn) and btn is Control and btn.get_global_rect().has_point(get_viewport().get_mouse_position()):
					clicked_on_ui = true; break
		
		# Check StudentListPanel
		if not clicked_on_ui and is_instance_valid(student_list_panel) and student_list_panel.visible:
			if student_list_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
		
		# Check ProgramManagementPanel
		if not clicked_on_ui and is_instance_valid(program_management_panel) and program_management_panel.visible:
			if program_management_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
		
		# Check SchedulingPanel
		if not clicked_on_ui and is_instance_valid(scheduling_panel) and scheduling_panel.visible:
			if scheduling_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
				
		if not clicked_on_ui:
			handle_placement_click(event.position)
			
	if event.is_action_pressed("clear_blocks") and event.is_pressed() and not event.is_echo(): # Assuming "clear_blocks" is an InputMap action
		clear_all_blocks()

func handle_placement_click(mouse_pos: Vector2):
	if not camera_3d: print_debug("Camera3D not found for placement click."); return
	var ray_origin = camera_3d.project_ray_origin(mouse_pos)
	var ray_direction = camera_3d.project_ray_normal(mouse_pos)
	var space_state = get_world_3d().direct_space_state
	if not space_state: print_debug("DirectSpaceState not available."); return
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	query.collision_mask = 3 # Assumes Layer 1 for Ground and Layer 2 for Blocks (binary 01 | 10 = 11 which is 3)
	
	var result: Dictionary = space_state.intersect_ray(query)
	if result:
		var hit_collider_object = result.get("collider", null)
		var hit_position: Vector3 = result.get("position", Vector3.ZERO)
		var hit_normal_raw: Vector3 = result.get("normal", Vector3.ZERO)
		var hit_normal = hit_normal_raw.round() # Get a grid-aligned normal
		
		var target_coord: Vector3i
		var can_place_here = false
		var is_expansion = false
		var source_building_type_for_wfc = "" 

		if hit_collider_object and hit_collider_object is CollisionObject3D:
			if hit_collider_object.get_collision_layer_value(1): # Hit Ground (Layer 1)
				target_coord = Vector3i(floori(hit_position.x / GRID_CELL_SIZE), 0, floori(hit_position.z / GRID_CELL_SIZE))
				if not occupied_cells.has(target_coord): 
					can_place_here = true
					is_expansion = false
			elif hit_collider_object.get_collision_layer_value(2): # Hit an existing Block (Layer 2)
				if hit_collider_object.has_meta("grid_coord"):
					var source_coord: Vector3i = hit_collider_object.get_meta("grid_coord")
					var source_block_data = occupied_cells.get(source_coord)
					if source_block_data:
						var source_block_assigned_type = source_block_data.get("building_type_assigned")
						
						# Allow expansion if types match, or if one is generic
						if source_block_assigned_type == current_selected_building_type or \
						   source_block_assigned_type == "generic" or \
						   current_selected_building_type == "generic":
							target_coord = source_coord + Vector3i(hit_normal.x, hit_normal.y, hit_normal.z)
							if target_coord.y < 0: # Don't allow building below y=0
								pass # Or print_debug("Cannot build below ground")
							elif not occupied_cells.has(target_coord):
								can_place_here = true
								is_expansion = true
								source_building_type_for_wfc = source_block_assigned_type 
						# else: print_debug("Cannot expand: Building type mismatch and neither is generic.")
				# else: print_debug("Clicked block has no grid_coord meta.")
			# else: print_debug("Clicked non-ground, non-block object.")
		# else: print_debug("Raycast did not hit a CollisionObject3D.")
				
		if can_place_here:
			var placement_intent_type = current_selected_building_type
			# If expanding a functional building with a generic block, inherit the functional type
			if is_expansion and source_building_type_for_wfc != "generic" and current_selected_building_type == "generic":
				placement_intent_type = source_building_type_for_wfc
			
			if is_expansion:
				var wfc_selection_context_type = placement_intent_type 
				var valid_choices = wfc_solver.get_valid_states_for_coord(target_coord, occupied_cells, wfc_selection_context_type, source_building_type_for_wfc)
				if not valid_choices.is_empty():
					var chosen_state = valid_choices.pick_random() # Or use weighted pick
					place_specific_block(target_coord, chosen_state.module_key, chosen_state.rotation, placement_intent_type)
				# else: print_debug("WFC: No valid choices for expansion at ", target_coord)
			else: # Placing a new building foundation
				var starter_module_key = ""
				# Try to find a starter module matching the intent
				for key in module_data:
					if module_data[key].get("building_type") == placement_intent_type:
						starter_module_key = key; break 
				if starter_module_key.is_empty(): # Fallback to a generic starter if intent-specific not found
					for key in module_data:
						if module_data[key].get("building_type") == "generic":
							if key == "Block_Solid": starter_module_key = key; break # Prefer Block_Solid
							elif starter_module_key.is_empty(): starter_module_key = key # Take first generic
				if starter_module_key.is_empty() and not module_data.is_empty(): # Absolute fallback
					starter_module_key = module_data.keys()[0]

				if starter_module_key.is_empty():
					printerr("No suitable starter module found for type '", placement_intent_type, "'. No modules defined?"); return
				
				place_specific_block(target_coord, starter_module_key, 0, placement_intent_type) # Default rotation 0
	# else: print_debug("Placement raycast missed.")


# In BuildingManager.gd

func place_specific_block(coord: Vector3i, module_key: String, rotation_y: int, assigned_building_type: String) -> bool:
	if occupied_cells.has(coord): 
		print_debug("Cell ", coord, " already occupied. Cannot place block.")
		return false
	if not module_data.has(module_key):
		printerr("Error: Module_key '", module_key, "' not found in module_data.")
		return false

	var block_info = module_data[module_key] 
	var actual_module_type_of_this_block = block_info.get("building_type", "generic") 
	var fulfills_needs_of_block = block_info.get("fulfills_needs", {})

	# --- THIS IS THE CORRECTED CAPACITY LOGIC ---
	# Determine capacity based PURELY on the INTENDED assigned_building_type of the structure.
	# Any block that is part of a "dorm" structure contributes 'dorm capacity points', etc.
	var capacity_for_this_block_in_this_structure = 0
	if assigned_building_type == "dorm":
		capacity_for_this_block_in_this_structure = 2 # All blocks in a dorm structure give 2 capacity
	elif assigned_building_type == "class":
		capacity_for_this_block_in_this_structure = 5 # All blocks in a class structure give 5 capacity
	elif assigned_building_type == "generic":
		capacity_for_this_block_in_this_structure = 0
	# --- END OF CORRECTED CAPACITY LOGIC ---
	
	var block_scene_path = block_info.get("path", "")
	if block_scene_path.is_empty() or not FileAccess.file_exists(block_scene_path):
		printerr("GLB missing or path invalid for module key '", module_key, "' (path: '", block_scene_path, "').")
		return false
	
	var visual_block_scene: PackedScene = load(block_scene_path)
	if not visual_block_scene:
		printerr("Failed to load PackedScene for '", module_key, "' from path '", block_scene_path, "'.")
		return false
		
	var visual_instance = visual_block_scene.instantiate()
	if not visual_instance is Node3D:
		printerr("Instantiated scene for '", module_key, "' is not a Node3D.")
		if is_instance_valid(visual_instance): visual_instance.queue_free()
		return false
		
	var static_body = StaticBody3D.new(); static_body.name = "Block_%d_%d_%d" % [coord.x, coord.y, coord.z]
	static_body.collision_layer = 2 
	static_body.collision_mask = 0 
	
	var collision_shape_node = CollisionShape3D.new()
	var box_shape_resource = BoxShape3D.new()
	box_shape_resource.size = Vector3(GRID_CELL_SIZE, GRID_CELL_SIZE, GRID_CELL_SIZE)
	collision_shape_node.shape = box_shape_resource
	collision_shape_node.position = Vector3(0, GRID_CELL_SIZE / 2.0, 0) # Centered vertically relative to static_body's origin

	static_body.add_child(visual_instance)
	static_body.add_child(collision_shape_node)
	visual_instance.position = Vector3.ZERO 
	
	if BlockFacilityScript:
		if capacity_for_this_block_in_this_structure > 0 or not fulfills_needs_of_block.is_empty():
			var facility_script_instance = BlockFacilityScript.new()
			static_body.add_child(facility_script_instance)
			facility_script_instance.name = "FacilityData"
			if facility_script_instance.has_method("setup_facility"):
				facility_script_instance.setup_facility(
					capacity_for_this_block_in_this_structure, 
					fulfills_needs_of_block,             
					actual_module_type_of_this_block
				)
			else:
				printerr("BlockFacility.gd script is missing setup_facility method!")
	
	if nav_mesh_block_parent: nav_mesh_block_parent.add_child(static_body)
	elif navigation_region: navigation_region.add_child(static_body); print_debug("Warning: Added block directly to NavRegion.")
	else: add_child(static_body); printerr("CRITICAL: No NavRegion for block placement.")
	
	placed_block_nodes.append(static_body)
	
	# Place static_body origin at the center of the grid cell base, then collision shape is relative
	static_body.global_position = Vector3(
		(float(coord.x) + 0.5) * GRID_CELL_SIZE, 
		float(coord.y) * GRID_CELL_SIZE,      # Y is at the bottom of the cell for this block
		(float(coord.z) + 0.5) * GRID_CELL_SIZE
	)
	static_body.rotation_degrees.y = float(rotation_y)
	
	occupied_cells[coord] = {
		"module_key": module_key,             
		"rotation": rotation_y,
		"building_type_assigned": assigned_building_type, # This is the key: the INTENDED type   
		"node_ref": static_body,
		"capacity_per_block": capacity_for_this_block_in_this_structure, # Uses the corrected logic above
		"actual_module_type": actual_module_type_of_this_block 
	}
	static_body.set_meta("grid_coord", coord)
	
	if assigned_building_type != "generic":
		_update_functional_building_clusters(coord, assigned_building_type)

	if navigation_region and navigation_region.navigation_mesh: 
		rebake_navigation_mesh(true) # Rebake after placement, synchronously
	return true


# --- Functional Building Cluster Management ---
func _update_functional_building_clusters(changed_coord: Vector3i, intended_functional_type: String):
	if intended_functional_type == "generic": return

	var component_coords: Array[Vector3i] = _get_connected_functional_blocks(changed_coord, intended_functional_type)
	
	if component_coords.is_empty(): # The changed_coord is no longer part of this functional type (or was isolated and removed)
		var affected_cluster_id_to_reprocess: String = ""
		var cluster_to_remove_entirely: String = ""
		# Check if this coord was part of an existing cluster and needs removal
		for cluster_id_key in functional_buildings.keys():
			var cluster = functional_buildings[cluster_id_key]
			if cluster.building_type == intended_functional_type and cluster.blocks_coords.has(changed_coord):
				cluster.blocks_coords.erase(changed_coord)
				if cluster.blocks_coords.is_empty():
					cluster_to_remove_entirely = str(cluster_id_key)
				else: # Cluster still exists, re-calculate its properties from a remaining block
					affected_cluster_id_to_reprocess = str(cluster_id_key)
				break # Found the cluster, stop searching
		
		if not cluster_to_remove_entirely.is_empty():
			if is_instance_valid(functional_buildings[cluster_to_remove_entirely].label_node_instance):
				functional_buildings[cluster_to_remove_entirely].label_node_instance.queue_free()
			functional_buildings.erase(cluster_to_remove_entirely)
		elif not affected_cluster_id_to_reprocess.is_empty():
			# This cluster shrunk, re-process it using one of its remaining blocks
			var remaining_block_coord = functional_buildings[affected_cluster_id_to_reprocess].blocks_coords[0]
			var old_label_instance = functional_buildings[affected_cluster_id_to_reprocess].label_node_instance
			functional_buildings.erase(affected_cluster_id_to_reprocess) # Remove old entry
			if is_instance_valid(old_label_instance): old_label_instance.queue_free() # Remove old label
			_update_functional_building_clusters(remaining_block_coord, intended_functional_type) # Re-trigger for a remaining block
		return # No component means no cluster to form/update from changed_coord

	# Find the canonical representative coordinate for the new/merged cluster ID (min x, then min z, then min y)
	var representative_coord = component_coords[0]
	for c_idx in range(1, component_coords.size()):
		var c = component_coords[c_idx]
		if c.x < representative_coord.x or \
		   (c.x == representative_coord.x and c.z < representative_coord.z) or \
		   (c.x == representative_coord.x and c.z == representative_coord.z and c.y < representative_coord.y):
			representative_coord = c
	
	var new_cluster_id_str = str(representative_coord)
	var new_total_capacity = 0
	var cluster_block_nodes: Array[Node3D] = [] # For centroid calculation
	var current_total_users_from_merged_clusters = 0 

	# Create a set of all coords in the newly found component for efficient lookup
	var final_cluster_coords_set: Dictionary = {}
	for c_coord in component_coords:
		final_cluster_coords_set[c_coord] = true

	# Identify existing clusters that overlap with this new component and need to be merged/removed
	var existing_cluster_ids_to_remove_or_merge: Array[String] = []
	for existing_id_key_variant in functional_buildings.keys():
		var existing_id_str = str(existing_id_key_variant) # Ensure string key
		var existing_cluster = functional_buildings[existing_id_key_variant]
		if existing_cluster.building_type == intended_functional_type:
			var intersects_with_new_component = false
			for existing_block_coord_in_cluster in existing_cluster.blocks_coords:
				if final_cluster_coords_set.has(existing_block_coord_in_cluster):
					intersects_with_new_component = true; break
			if intersects_with_new_component:
				if not existing_cluster_ids_to_remove_or_merge.has(existing_id_str):
					existing_cluster_ids_to_remove_or_merge.append(existing_id_str)
	
	# Merge coordinates and data from clusters being removed/merged
	var final_cluster_coords_array: Array[Vector3i] = component_coords.duplicate() # Start with the current component

	if not existing_cluster_ids_to_remove_or_merge.is_empty():
		# Use a temporary set to avoid duplicates during merge
		var temp_merged_coords_set: Dictionary = {}
		for c_coord in final_cluster_coords_array: # Add current component coords first
			temp_merged_coords_set[c_coord] = true

		for id_to_merge_str in existing_cluster_ids_to_remove_or_merge:
			if functional_buildings.has(id_to_merge_str): # Check if key exists
				var cluster_to_merge_data = functional_buildings[id_to_merge_str]
				current_total_users_from_merged_clusters += cluster_to_merge_data.get("current_users", 0)
				for block_coord_to_add in cluster_to_merge_data.blocks_coords:
					temp_merged_coords_set[block_coord_to_add] = true # Add to set
				
				if is_instance_valid(cluster_to_merge_data.label_node_instance):
					cluster_to_merge_data.label_node_instance.queue_free()
				functional_buildings.erase(id_to_merge_str) # Erase the old merged cluster
		
		# Rebuild final_cluster_coords_array from the merged set
		final_cluster_coords_array.clear()
		for merged_coord_key in temp_merged_coords_set.keys():
			final_cluster_coords_array.append(merged_coord_key)

		# Re-calculate representative_coord if merging occurred and the array is not empty
		if not final_cluster_coords_array.is_empty():
			representative_coord = final_cluster_coords_array[0] # Reset for re-calculation
			for c_idx in range(1, final_cluster_coords_array.size()):
				var c = final_cluster_coords_array[c_idx]
				if c.x < representative_coord.x or \
				   (c.x == representative_coord.x and c.z < representative_coord.z) or \
				   (c.x == representative_coord.x and c.z == representative_coord.z and c.y < representative_coord.y):
					representative_coord = c
			new_cluster_id_str = str(representative_coord) # Update cluster ID based on new representative
		else:
			print_debug("Error: Merged cluster resulted in empty coordinates. Aborting update for this cluster.")
			return # Cannot proceed if no coords left

	# Calculate total capacity and collect block nodes for the final cluster
	new_total_capacity = 0 
	cluster_block_nodes.clear() 
	for c_coord_final in final_cluster_coords_array: 
		if occupied_cells.has(c_coord_final):
			var cell_data_final = occupied_cells[c_coord_final]
			# Ensure capacity is added only if the block's assigned type matches the intended functional type
			if cell_data_final.get("building_type_assigned") == intended_functional_type:
				new_total_capacity += cell_data_final.get("capacity_per_block", 0)
			
			if cell_data_final.has("node_ref") and is_instance_valid(cell_data_final.node_ref):
				cluster_block_nodes.append(cell_data_final.node_ref)

	if final_cluster_coords_array.is_empty() or cluster_block_nodes.is_empty():
		print_debug("Error: Final cluster coords or block nodes are empty. Cannot create/update cluster '", new_cluster_id_str, "'.")
		# If an old cluster with this ID existed due to merge logic, ensure its label is cleaned up
		if functional_buildings.has(new_cluster_id_str) and is_instance_valid(functional_buildings[new_cluster_id_str].get("label_node_instance")):
			functional_buildings[new_cluster_id_str].label_node_instance.queue_free()
		if functional_buildings.has(new_cluster_id_str): functional_buildings.erase(new_cluster_id_str)
		return

	var label_node_3d_instance: Node3D = null
	var users_to_set_in_final_cluster = current_total_users_from_merged_clusters 

	# Update or create the cluster entry
	if functional_buildings.has(new_cluster_id_str): # This cluster ID (new representative) already exists (e.g. no merge, just update)
		var existing_data_for_cluster = functional_buildings[new_cluster_id_str]
		label_node_3d_instance = existing_data_for_cluster.label_node_instance # Reuse existing label
		# If no merging happened, users count should be from this existing cluster, not current_total_users_from_merged_clusters
		if existing_cluster_ids_to_remove_or_merge.is_empty(): 
			users_to_set_in_final_cluster = existing_data_for_cluster.current_users
		
		existing_data_for_cluster.blocks_coords = final_cluster_coords_array
		existing_data_for_cluster.total_capacity = new_total_capacity
		existing_data_for_cluster.current_users = mini(users_to_set_in_final_cluster, new_total_capacity) # Cap users by new capacity
		existing_data_for_cluster.representative_block_node = occupied_cells[representative_coord].node_ref if occupied_cells.has(representative_coord) else null
	else: # Create a new cluster entry
		if capacity_label_scene: # Assuming capacity_label_scene is preloaded
			label_node_3d_instance = capacity_label_scene.instantiate() as Node3D
			if is_instance_valid(label_node_3d_instance) and is_instance_valid(capacity_labels_parent):
				capacity_labels_parent.add_child(label_node_3d_instance)
			else: 
				print_debug("Failed to instantiate or parent capacity label for cluster '", new_cluster_id_str, "'.")
				label_node_3d_instance = null # Ensure it's null if failed
		
		functional_buildings[new_cluster_id_str] = {
			"building_type": intended_functional_type,
			"blocks_coords": final_cluster_coords_array,
			"total_capacity": new_total_capacity,
			"current_users": mini(users_to_set_in_final_cluster, new_total_capacity), 
			"label_node_instance": label_node_3d_instance,
			"representative_block_node": occupied_cells[representative_coord].node_ref if occupied_cells.has(representative_coord) else null
		}
	
	# Update label position and text
	if is_instance_valid(label_node_3d_instance) and not cluster_block_nodes.is_empty():
		var sum_pos = Vector3.ZERO
		for bn_node in cluster_block_nodes: sum_pos += bn_node.global_position
		var centroid = sum_pos / float(cluster_block_nodes.size()) # Ensure float division
		label_node_3d_instance.global_position = Vector3(centroid.x, centroid.y + GRID_CELL_SIZE * 0.75, centroid.z) # Position above centroid
		
		var actual_label_control = label_node_3d_instance.get_node_or_null("CapacityTextLabel") as Label3D # Path to Label3D in scene
		if is_instance_valid(actual_label_control):
			actual_label_control.text = str(functional_buildings[new_cluster_id_str].current_users) + "/" + str(new_total_capacity)
			actual_label_control.visible = new_total_capacity > 0 # Hide label if no capacity
	elif is_instance_valid(label_node_3d_instance): # If label exists but no blocks (should not happen if logic above is correct)
		var actual_label_control = label_node_3d_instance.get_node_or_null("CapacityTextLabel") as Label3D
		if is_instance_valid(actual_label_control): actual_label_control.visible = false


func _get_connected_functional_blocks(start_coord: Vector3i, intended_type: String) -> Array[Vector3i]:
	var component: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start_coord]
	var visited: Dictionary = {start_coord: true}

	while not queue.is_empty():
		var current_coord = queue.pop_front()
		
		if not occupied_cells.has(current_coord): continue # Should not happen if called on an occupied cell
		var cell_data = occupied_cells[current_coord]
		
		# Only include blocks whose ASSIGNED type matches the intended_type for this cluster
		if cell_data.get("building_type_assigned") != intended_type:
			continue

		component.append(current_coord)

		var neighbor_offsets = [
			Vector3i.LEFT, Vector3i.RIGHT,
			Vector3i.FORWARD, Vector3i.BACK,
			Vector3i.UP, Vector3i.DOWN
		]
		for offset in neighbor_offsets:
			var neighbor_coord = current_coord + offset
			if not visited.has(neighbor_coord) and occupied_cells.has(neighbor_coord):
				var neighbor_cell_data = occupied_cells[neighbor_coord]
				# Check if neighbor is also part of the same functional building type
				if neighbor_cell_data.get("building_type_assigned") == intended_type:
					visited[neighbor_coord] = true
					queue.append(neighbor_coord)
	return component


func student_entered_functional_building(cluster_id_str_or_coord: Variant) -> bool:
	var cluster_id_to_use = str(cluster_id_str_or_coord) # Ensure string key

	if functional_buildings.has(cluster_id_to_use):
		var cluster = functional_buildings[cluster_id_to_use]
		if cluster.current_users < cluster.total_capacity:
			cluster.current_users += 1
			_update_cluster_label(cluster_id_to_use)
			return true
		else: # print_debug("Cluster '", cluster_id_to_use, "' is full. Cannot enter.")
			return false
	# else: print_debug("Cluster '", cluster_id_to_use, "' not found for student entry.")
	return false

func student_left_functional_building(cluster_id_str_or_coord: Variant):
	var cluster_id_to_use = str(cluster_id_str_or_coord) # Ensure string key
	if functional_buildings.has(cluster_id_to_use):
		var cluster = functional_buildings[cluster_id_to_use]
		cluster.current_users = maxi(0, cluster.current_users - 1) # Ensure not negative
		_update_cluster_label(cluster_id_to_use)
	# else: print_debug("Cluster '", cluster_id_to_use, "' not found for student exit.")


func _update_cluster_label(cluster_id_str: String):
	if functional_buildings.has(cluster_id_str):
		var cluster = functional_buildings[cluster_id_str]
		if is_instance_valid(cluster.label_node_instance):
			var actual_label = cluster.label_node_instance.get_node_or_null("CapacityTextLabel") as Label3D # Path in CapacityLabel3D.tscn
			if is_instance_valid(actual_label):
				actual_label.text = str(cluster.current_users) + "/" + str(cluster.total_capacity)
				actual_label.visible = cluster.total_capacity > 0 # Show only if capacity > 0

# BuildingManager.gd
# ... (your existing BuildingManager code) ...

# IMPORTANT: Ensure this Y-value matches what's used for student navigation 
# (e.g., Student.EXPECTED_NAVMESH_Y or AcademicManager.ACADEMIC_MGR_STUDENT_EXPECTED_NAVMESH_Y)
const BUILDING_EXIT_NAVMESH_Y: float = 0.3 # !!! ADJUST THIS TO YOUR PROJECT'S NAVMESH Y-LEVEL !!!

# This is the new function you need to add:
func get_building_exit_location(building_id_str: String) -> Vector3:
	# This print is for your debugging, you can remove it later
	print("[BuildingManager]: get_building_exit_location called for ID: '" + building_id_str + "'")

	# 'functional_buildings' is assumed to be the dictionary holding your building data,
	# similar to how it's accessed in AcademicManager's get_available_classrooms()
	# If your main data structure has a different name, use that here.
	if not functional_buildings.has(building_id_str):
		printerr("[BuildingManager]: Building ID '", building_id_str, "' not found in functional_buildings data. Cannot determine exit location.")
		return Vector3.ZERO # Return ZERO to indicate failure; AcademicManager will use its own fallback.

	var building_data: Dictionary = functional_buildings[building_id_str]
	
	# Attempt to get the representative node, which is likely the building's main visual/anchor
	var rep_node = building_data.get("representative_block_node")

	if not is_instance_valid(rep_node) or not rep_node is Node3D:
		printerr("[BuildingManager]: Representative node for building '", building_id_str, "' is not a valid Node3D. Cannot determine exit location.")
		return Vector3.ZERO # Indicate failure

	var building_origin_pos: Vector3 = rep_node.global_position

	# BuildingManager.gd - inside get_building_exit_location, for the offset fallback

	var building_transform: Transform3D = rep_node.global_transform # rep_node.global_transform is correct

			# --- Determine global forward direction based on building's local forward ---
			# Option A: If your building models have their "front door" pointing along their local -Z axis:
	var global_front_direction: Vector3 = -building_transform.basis.z
			
			# Option B: If their "front door" points along their local +Z axis:
			# var global_front_direction: Vector3 = building_transform.basis.z

			# Option C: If their "front door" points along their local +X axis:
			# var global_front_direction: Vector3 = building_transform.basis.x
			
			# Option D: If their "front door" points along their local -X axis:
			# var global_front_direction: Vector3 = -building_transform.basis.x

			# !!! IMPORTANT: Choose only ONE of the above options (A, B, C, or D) 
			# based on how your building models are oriented.
			# -Z (Option A) is a common convention for "forward".

	var offset_distance: float = 3.0 # Adjust this distance as needed to clear the building
										   # This value might need to be larger (e.g., 4.0 or 5.0)
										   # depending on the size of your buildings from their origin.

	var exit_offset: Vector3 = global_front_direction.normalized() * offset_distance 
			
	var calculated_exit_pos: Vector3 = building_transform.origin + exit_offset # Add offset to building's origin
	var final_exit_position: Vector3 = Vector3(calculated_exit_pos.x, BUILDING_EXIT_NAVMESH_Y, calculated_exit_pos.z)
	
	# Ensure the Y-coordinate is at the correct navmesh level
	
	print("[BuildingManager]: Calculated exit for '", building_id_str, "' at ", str(final_exit_position))
	return final_exit_position
	
# --- Data Accessors ---
func get_all_occupied_cells_data() -> Dictionary: return occupied_cells.duplicate(true)
func get_functional_buildings_data() -> Dictionary: return functional_buildings.duplicate(true)


func clear_all_blocks():
	for block_node_instance in placed_block_nodes: # Use a different variable name
		if is_instance_valid(block_node_instance):
			if block_node_instance.get_parent(): block_node_instance.get_parent().remove_child(block_node_instance)
			block_node_instance.queue_free()
	placed_block_nodes.clear()
	occupied_cells.clear()

	for cluster_id_key in functional_buildings: # Iterate keys
		var cluster_data_val = functional_buildings[cluster_id_key] # Use different variable name
		if is_instance_valid(cluster_data_val.get("label_node_instance")): # Use .get for safety
			cluster_data_val.label_node_instance.queue_free()
	functional_buildings.clear()

	# Also clear any dynamically added children to nav_mesh_block_parent if they weren't in placed_block_nodes
	if is_instance_valid(nav_mesh_block_parent):
		for child_node in nav_mesh_block_parent.get_children(): # Use different variable name
			nav_mesh_block_parent.remove_child(child_node)
			child_node.queue_free()
			
	total_annual_income = 500.0 # Reset to base
	total_annual_expenses = 200.0 # Reset to base
	# university_reputation = 40.0 # Optionally reset reputation to initial or let it persist/recalculate
	update_reputation_and_ui() # Recalculate and update UI
	
	if wfc_solver: wfc_solver.initialize(Vector3i.ONE, module_data) # Reinitialize WFC
	
	if student_manager and student_manager.has_method("clear_all_students"): 
		student_manager.clear_all_students()
		
	if navigation_region and navigation_region.navigation_mesh: 
		call_deferred("rebake_navigation_mesh", false) # Non-synchronous bake on clear
	print_debug("All blocks cleared from the university.")


# --- Student Roster UI Functions ---
func _on_view_students_button_pressed():
	if not is_instance_valid(student_list_panel): 
		print_debug("StudentListPanel is not valid. Cannot show.")
		return
	# Hide other main panels to avoid overlap
	if is_instance_valid(program_management_panel) and program_management_panel.visible:
		program_management_panel.visible = false
	if is_instance_valid(scheduling_panel) and scheduling_panel.visible :
		scheduling_panel.visible = false
		
	populate_student_roster()
	student_list_panel.visible = true

func _on_close_student_panel_button_pressed():
	if is_instance_valid(student_list_panel): 
		student_list_panel.visible = false

func populate_student_roster():
	if not is_instance_valid(student_list_vbox) or not is_instance_valid(student_manager) or not student_list_item_scene:
		print_debug("Cannot populate student roster due to missing components (VBox, StudentManager, or ItemScene).")
		return
	for child in student_list_vbox.get_children(): child.queue_free() # Clear old items
	
	if student_manager.has_method("get_all_student_nodes"):
		var students_array: Array[Node] = student_manager.get_all_student_nodes() # Ensure this returns Array[Node]
		if students_array.is_empty():
			var empty_label = Label.new(); empty_label.text = "No students enrolled yet."
			student_list_vbox.add_child(empty_label)
		else:
			for student_node_item in students_array: # Use different variable name
				if is_instance_valid(student_node_item): # student_node_item should be the Student node itself
					var item_instance = student_list_item_scene.instantiate()
					if not is_instance_valid(item_instance): continue # Skip if instantiation failed
					student_list_vbox.add_child(item_instance)
					if item_instance.has_method("set_student_data"): 
						item_instance.set_student_data(student_node_item) # Pass the Student node
					# else: print_debug("StudentListItem scene's script missing set_student_data().")
	# else: print_debug("StudentManager missing get_all_student_nodes().")


# --- Program Management UI Functions ---
func _on_view_programs_button_pressed():
	if not is_instance_valid(program_management_panel):
		print_debug("ProgramManagementPanel is not valid. Cannot show.")
		return

	var new_visibility = not program_management_panel.visible
	
	if new_visibility:
		# Hide other panels
		if is_instance_valid(student_list_panel) and student_list_panel.visible: student_list_panel.visible = false
		if is_instance_valid(scheduling_panel) and scheduling_panel.visible : scheduling_panel.visible = false

		if program_management_panel.has_method("show_panel"): # Ideal: panel handles its own refresh
			program_management_panel.show_panel()
		else: # Fallback
			program_management_panel.visible = true
			if program_management_panel.has_method("refresh_program_list"): # Common refresh method name
				program_management_panel.refresh_program_list()
			elif program_management_panel.has_method("refresh_ui"): # Generic fallback
				program_management_panel.refresh_ui()
		print_debug("Showing Program Management Panel.")
	else: # Hiding the panel
		if program_management_panel.has_method("hide_panel"):
			program_management_panel.hide_panel()
		else: # Fallback
			program_management_panel.visible = false
		print_debug("Hiding Program Management Panel.")


# --- Scheduling Panel UI Functions ---
func _on_view_schedule_button_pressed():
	if not is_instance_valid(scheduling_panel):
		print_debug("SchedulingPanel is not valid. Cannot show.")
		return

	var new_visibility = not scheduling_panel.visible

	if new_visibility:
		# Hide other panels
		if is_instance_valid(student_list_panel) and student_list_panel.visible: student_list_panel.visible = false
		if is_instance_valid(program_management_panel) and program_management_panel.visible: program_management_panel.visible = false
		
		if scheduling_panel.has_method("show_panel"):
			scheduling_panel.show_panel()
		else: # Fallback
			scheduling_panel.visible = true
			if scheduling_panel.has_method("refresh_ui"): # Assuming it might have a general refresh
				scheduling_panel.refresh_ui()
		print_debug("Showing Scheduling Panel.")
	else: # Hiding the panel
		if scheduling_panel.has_method("hide_panel"):
			scheduling_panel.hide_panel()
		else: # Fallback
			scheduling_panel.visible = false
		print_debug("Hiding Scheduling Panel.")

		
# --- Helper Functions ---
func get_navigation_region() -> NavigationRegion3D: return navigation_region

# Using a more robust print_debug for arrays with non-string elements
func print_debug(message_parts):
	var output_message = "[BuildingManager]: "
	if typeof(message_parts) == TYPE_STRING:
		output_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY: # Check if it's a generic array
		var string_array : Array[String] = []
		for item in message_parts: # Convert each item to string
			string_array.append(str(item))
		output_message += " ".join(string_array)
	elif typeof(message_parts) == TYPE_PACKED_STRING_ARRAY: # If it's already a string array
		var temp_array : PackedStringArray = message_parts # Explicit type
		output_message += " ".join(temp_array) # PackedStringArray can be joined directly
	else:
		output_message += str(message_parts)
	print(output_message)
