# BuildingManager.gd
# Manages building placement, game economy, NavMesh baking,
# and serves as a central point for UI interactions and game events.
class_name BuildingManager # Ensure this is present
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
		"capacity_per_block": 0 # Inherent capacity, will be overridden by intent for functional types
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
			"0":	{"Top":"TOP_STONE_FLAT", "Bottom":"BOTTOM_STONE", "Front":"SIDE_WINDOW",  "Back":"SIDE_STONE",   "Right":"SIDE_STONE",   "Left":"SIDE_STONE"}
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
@onready var time_manager: TimeManager = $TimeManager
@onready var navigation_region: NavigationRegion3D = get_node_or_null("NavigationRegion3D") as NavigationRegion3D
@onready var ground_node: StaticBody3D = get_node_or_null("NavigationRegion3D/Ground") as StaticBody3D
@onready var nav_mesh_block_parent: Node3D
@onready var student_manager: Node = null
@onready var capacity_labels_parent: Node3D = null

# UI Elements (General) - Paths based on user's last provided script
@onready var date_label: Label
@onready var speed_label: Label
@onready var pause_button: Button
@onready var play_button: Button
@onready var ff_button: Button
@onready var income_label: Label
@onready var expenses_label: Label
@onready var endowment_label: Label

# --- UI References for Student Roster ---
@export var view_students_button: Button # Path set in _ready
@onready var student_list_panel: PanelContainer = get_node_or_null("StudentListPanel") as PanelContainer # Adjust path if needed
@onready var student_list_vbox: VBoxContainer # Path set in _ready
@onready var close_student_panel_button: Button # Path set in _ready

# --- UI References for Program Management --- (NEW)
@export var view_programs_button: Button # Path set in _ready
@onready var program_management_panel: PanelContainer = get_node_or_null("ProgramManagementPanel") as PanelContainer # Adjust path if needed
# Assuming ProgramManagementPanel has its own close button handled by its own script (ProgramManagementUI.gd)

# --- UI References for Scheduling Panel --- (NEW SECTION)
@export var view_schedule_button: Button # Path set in _ready
@onready var scheduling_panel: PanelContainer = get_node_or_null("SchedulingPanel") as PanelContainer # Adjust path if needed

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

# Preload the BlockFacility script
const BlockFacilityScript = preload("res://scripts/BlockFacility.gd")


func _ready():
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


	if not time_manager:
		printerr("CRITICAL: TimeManager node not found!")
		get_tree().quit(); return

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

	if not student_manager:
		student_manager = get_node_or_null("StudentManager") # Adjust path if needed
	
	if not student_manager:
		printerr("BuildingManager: StudentManager node not found!")
	elif not student_manager.has_method("on_initial_navmesh_baked"):
		printerr("BuildingManager: Assigned StudentManager node incorrect type.")
		student_manager = null

	wfc_solver = WfcSolverClass.new()
	if not wfc_solver.initialize(Vector3i.ONE, module_data):
		printerr("Failed to initialize WFC Solver!");

	if time_manager:
		if not time_manager.date_changed.is_connected(_on_time_manager_date_changed):
			time_manager.date_changed.connect(_on_time_manager_date_changed)
		if not time_manager.pause_state_changed.is_connected(_on_time_manager_pause_state_changed):
			time_manager.pause_state_changed.connect(_on_time_manager_pause_state_changed)
		if not time_manager.speed_changed.is_connected(_on_time_manager_speed_changed):
			time_manager.speed_changed.connect(_on_time_manager_speed_changed)
		if not time_manager.new_year_started.is_connected(_on_time_manager_new_year_started):
			time_manager.new_year_started.connect(_on_time_manager_new_year_started)
		if time_manager.has_signal("new_day_has_started") and \
		   not time_manager.new_day_has_started.is_connected(_on_time_manager_new_day_has_started):
			time_manager.new_day_has_started.connect(_on_time_manager_new_day_has_started)
			# print_debug("Connected BuildingManager to TimeManager.new_day_has_started signal.")
	else:
		printerr("TimeManager is null, cannot connect signals.")

	var top_ui_node_for_hud = get_node_or_null("TopUI") # Assuming TopUI is at a known path
	if top_ui_node_for_hud:
		var main_hud_panel_hbox = top_ui_node_for_hud.get_node_or_null("Panel/HBoxContainer") # Common container for HUD buttons
		if main_hud_panel_hbox:
			date_label = main_hud_panel_hbox.get_node_or_null("DateLabel") as Label
			speed_label = main_hud_panel_hbox.get_node_or_null("SpeedLabel") as Label
			pause_button = main_hud_panel_hbox.get_node_or_null("PauseButton") as Button
			play_button = main_hud_panel_hbox.get_node_or_null("PlayButton") as Button
			ff_button = main_hud_panel_hbox.get_node_or_null("FastForwardButton") as Button
			
			view_students_button = get_node_or_null("Panel/HBoxContainer/ViewStudentsButton") as Button # (NEW PATH)
			view_programs_button = get_node_or_null("Panel/HBoxContainer/ViewProgramsButton") as Button # (NEW)
			view_schedule_button = get_node_or_null("Panel/HBoxContainer/ViewScheduleButton") as Button
			
			var finance_vbox = main_hud_panel_hbox.get_node_or_null("VBoxContainer") # Assuming this is still within the HBox
			if finance_vbox:
				income_label = finance_vbox.get_node_or_null("IncomeLabel") as Label
				expenses_label = finance_vbox.get_node_or_null("ExpensesLabel") as Label
				endowment_label = finance_vbox.get_node_or_null("EndowmentLabel") as Label
		else:
			print_debug("Warning: HBoxContainer for HUD elements not found under TopUI/Panel.")

		# Building type selection buttons (assuming they are direct children of TopUI or similar)
		var select_dorm_button = top_ui_node_for_hud.get_node_or_null("SelectDormButton") as Button
		var select_class_button = top_ui_node_for_hud.get_node_or_null("SelectClassButton") as Button
		var select_generic_button = top_ui_node_for_hud.get_node_or_null("SelectGenericButton") as Button

		# Connect signals for time controls and building selection
		if pause_button and not pause_button.is_connected("pressed", Callable(self, "_on_pause_button_pressed")): pause_button.pressed.connect(Callable(self, "_on_pause_button_pressed"))
		if play_button and not play_button.is_connected("pressed", Callable(self, "_on_play_button_pressed")): play_button.pressed.connect(Callable(self, "_on_play_button_pressed"))
		if ff_button and not ff_button.is_connected("pressed", Callable(self, "_on_ff_button_pressed")): ff_button.pressed.connect(Callable(self, "_on_ff_button_pressed"))
		if select_dorm_button and not select_dorm_button.is_connected("pressed", Callable(self, "_on_select_dorm_pressed")): select_dorm_button.pressed.connect(Callable(self, "_on_select_dorm_pressed"))
		if select_class_button and not select_class_button.is_connected("pressed", Callable(self, "_on_select_class_pressed")): select_class_button.pressed.connect(Callable(self, "_on_select_class_pressed"))
		if select_generic_button and not select_generic_button.is_connected("pressed", Callable(self, "_on_select_generic_pressed")): select_generic_button.pressed.connect(Callable(self, "_on_select_generic_pressed"))
		
		# Connect Student Roster Button
		if is_instance_valid(view_students_button):
			if not view_students_button.is_connected("pressed", Callable(self, "_on_view_students_button_pressed")):
				view_students_button.pressed.connect(Callable(self, "_on_view_students_button_pressed"))
		else: 
			printerr("BuildingManager: ViewStudentsButton not found at 'TopUI/Panel/HBoxContainer/ViewStudentsButton'.")

		# Connect Program Management Button (NEW)
		if is_instance_valid(view_programs_button):
			if not view_programs_button.is_connected("pressed", Callable(self, "_on_view_programs_button_pressed")):
				view_programs_button.pressed.connect(Callable(self, "_on_view_programs_button_pressed"))
		else:
			printerr("BuildingManager: ViewProgramsButton not found at 'TopUI/Panel/HBoxContainer/ViewProgramsButton'.")
		
		if is_instance_valid(view_schedule_button):
			if not view_schedule_button.is_connected("pressed", Callable(self, "_on_view_schedule_button_pressed")):
				view_schedule_button.pressed.connect(Callable(self, "_on_view_schedule_button_pressed"))
		else:
			printerr("BuildingManager: ViewScheduleButton not found at 'Panel/HBoxContainer/ViewScheduleButton'.")
	
	else: 
		print_debug("Warning: TopUI node not found. Main HUD UI might not function.")
		# Fallback paths for panels if TopUI is not found (less ideal)
		student_list_panel = get_node_or_null("StudentListPanel") as PanelContainer 
		program_management_panel = get_node_or_null("ProgramManagementPanel") as PanelContainer


	# Student List Panel setup
	if is_instance_valid(student_list_panel):
		student_list_vbox = student_list_panel.get_node_or_null("MarginContainer/VBoxContainer/StudentScrollContainer/StudentListVBox") as VBoxContainer
		close_student_panel_button = student_list_panel.get_node_or_null("MarginContainer/VBoxContainer/CloseStudentPanelButton") as Button
		if is_instance_valid(close_student_panel_button):
			if not close_student_panel_button.is_connected("pressed", Callable(self, "_on_close_student_panel_button_pressed")):
				close_student_panel_button.pressed.connect(Callable(self, "_on_close_student_panel_button_pressed"))
		else:
			printerr("BuildingManager: CloseStudentPanelButton not found.")
		student_list_panel.visible = false # Default to hidden
	else:
		printerr("BuildingManager: StudentListPanel not found (path: 'StudentListPanel' or from TopUI).")
		
	# Program Management Panel setup (NEW)
	if is_instance_valid(program_management_panel):
		program_management_panel.visible = false # Default to hidden
		# Assuming ProgramManagementPanel has its own close button handled by ProgramManagementUI.gd
	else:
		printerr("BuildingManager: ProgramManagementPanel not found (path: 'ProgramManagementPanel' or from TopUI).")

	# Schedules Panel setup
	if is_instance_valid(scheduling_panel):
		scheduling_panel.visible = false
	else:
	# Fallback attempt if not a direct child
		scheduling_panel = get_tree().root.get_node_or_null("MainScene/SchedulingPanel") # ADJUST THIS FALLBACK PATH
	if is_instance_valid(scheduling_panel):
		scheduling_panel.visible = false
	else:
		printerr("BuildingManager: SchedulingPanel not found. Please check its path.")

	if time_manager:
		_on_time_manager_date_changed(time_manager.get_current_day(), time_manager.get_current_month(), time_manager.get_current_year())
		_on_time_manager_pause_state_changed(time_manager.get_is_paused())
		_on_time_manager_speed_changed(time_manager.get_speed_multiplier())
	update_financial_ui()
		
	if not student_list_item_scene:
		printerr("BuildingManager: CRITICAL - Failed to preload StudentListItem.tscn.")
	if not capacity_label_scene:
		printerr("BuildingManager: CRITICAL - Failed to preload CapacityLabel3D.tscn.")


	if navigation_region and navigation_region.navigation_mesh and not _initial_bake_done:
		call_deferred("perform_initial_bake")
		_initial_bake_done = true
	elif _initial_bake_done and student_manager and student_manager.has_method("on_initial_navmesh_baked"):
		student_manager.on_initial_navmesh_baked()

	print("BuildingManager ready. Select building type, Left Click to place/expand. 'C' to clear.")


func perform_initial_bake():
	rebake_navigation_mesh(true)
	if student_manager and student_manager.has_method("on_initial_navmesh_baked"):
		student_manager.on_initial_navmesh_baked()

func rebake_navigation_mesh(synchronous_bake: bool = false):
	if not navigation_region or not navigation_region.navigation_mesh is NavigationMesh: return
	navigation_region.bake_navigation_mesh(synchronous_bake)
	if synchronous_bake:
		await get_tree().physics_frame
		await get_tree().process_frame

# --- UI Callbacks & TimeManager Signal Handlers ---
func _on_select_dorm_pressed(): current_selected_building_type = "dorm"; print("Selected: DORM (Capacity per block: 2)")
func _on_select_class_pressed(): current_selected_building_type = "class"; print("Selected: CLASS (Capacity per block: 5)")
func _on_select_generic_pressed(): current_selected_building_type = "generic"; print("Selected: GENERIC (Capacity per block: 0)")
func _on_pause_button_pressed(): if time_manager: time_manager.set_paused(true)
func _on_play_button_pressed(): if time_manager: time_manager.set_speed(1.0)
func _on_ff_button_pressed():
	if time_manager:
		if time_manager.get_is_paused() or time_manager.get_speed_multiplier() < 2.0: time_manager.set_speed(2.0)
		elif time_manager.get_speed_multiplier() < 5.0: time_manager.set_speed(5.0)
		else: time_manager.set_speed(1.0)

func _on_time_manager_date_changed(day: int, month: int, year: int):
	if date_label: date_label.text = "Day: %d, Month: %d, Year: %d" % [day, month, year]

func _on_time_manager_new_day_has_started(day: int, month: int, year: int):
	if is_instance_valid(student_manager) and student_manager.has_method("update_all_students_daily_activities"):
		student_manager.update_all_students_daily_activities()

func _on_time_manager_pause_state_changed(is_paused: bool):
	if speed_label:
		if is_paused: speed_label.text = "Speed: PAUSED"
		else: speed_label.text = "Speed: %.1fx" % time_manager.get_speed_multiplier() if time_manager else "Speed: N/A"
	if play_button: play_button.disabled = not is_paused and (time_manager.get_speed_multiplier() == 1.0 if time_manager else false)
	if pause_button: pause_button.disabled = is_paused
	if ff_button: ff_button.disabled = is_paused

func _on_time_manager_speed_changed(new_speed: float):
	if speed_label:
		if time_manager and time_manager.get_is_paused(): speed_label.text = "Speed: PAUSED"
		else: speed_label.text = "Speed: %.1fx" % new_speed
	if time_manager: _on_time_manager_pause_state_changed(time_manager.get_is_paused())

func _on_time_manager_new_year_started(year: int):
	print_debug("New Year Started: " + str(year) + ". Processing yearly events.")
	var income_from_blocks: float = 0.0; var expenses_from_blocks: float = 0.0
	for coord_key in occupied_cells:
		var block_data = occupied_cells[coord_key]
		var module_key_val = block_data.get("module_key") # Get the actual module placed
		if module_key_val and module_data.has(module_key_val):
			var m_info = module_data[module_key_val] # Get actual module's data for costs/income
			income_from_blocks += m_info.get("base_annual_income", 0.0)
			expenses_from_blocks += m_info.get("base_annual_expense", 0.0)
	var base_income = 500.0; var base_expenses = 200.0
	total_annual_income = base_income + income_from_blocks
	total_annual_expenses = base_expenses + expenses_from_blocks
	var surplus_deficit = total_annual_income - total_annual_expenses
	current_endowment += surplus_deficit
	update_financial_ui()
	if is_instance_valid(student_manager) and student_manager.has_method("update_all_students_daily_activities"):
		student_manager.update_all_students_daily_activities()


func update_financial_ui():
	if income_label: income_label.text = "Income (Annual): $" + str(snappedf(total_annual_income, 0.01))
	if expenses_label: expenses_label.text = "Expenses (Annual): $" + str(snappedf(total_annual_expenses, 0.01))
	if endowment_label: endowment_label.text = "Endowment: $" + str(snappedf(current_endowment, 0.01))

# --- Input Handling & Placement Logic ---
func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		var clicked_on_ui = false
		# Check TopUI Panel itself
		var top_ui_panel_node = get_node_or_null("TopUI/Panel")
		if top_ui_panel_node and top_ui_panel_node is Control and top_ui_panel_node.visible:
			if top_ui_panel_node.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
		
		# Check specific buttons within TopUI if not already caught by panel
		var top_ui_node = get_node_or_null("TopUI")
		if not clicked_on_ui and top_ui_node and top_ui_node is Control and top_ui_node.visible:
			var select_buttons = ["SelectDormButton", "SelectClassButton", "SelectGenericButton"] # Add other top-level buttons if needed
			for btn_name in select_buttons:
				var btn = top_ui_node.get_node_or_null(btn_name)
				if is_instance_valid(btn) and btn is Control and btn.get_global_rect().has_point(get_viewport().get_mouse_position()):
					clicked_on_ui = true; break
		
		# Check StudentListPanel
		if not clicked_on_ui and is_instance_valid(student_list_panel) and student_list_panel.visible:
			if student_list_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
		
		# Check ProgramManagementPanel (NEW)
		if not clicked_on_ui and is_instance_valid(program_management_panel) and program_management_panel.visible:
			if program_management_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				clicked_on_ui = true
				
		if not clicked_on_ui:
			handle_placement_click(event.position)
	if event.is_action_pressed("clear_blocks") and event.is_pressed() and not event.is_echo():
		clear_all_blocks()

func handle_placement_click(mouse_pos: Vector2):
	if not camera_3d: return
	var ray_origin = camera_3d.project_ray_origin(mouse_pos)
	var ray_direction = camera_3d.project_ray_normal(mouse_pos)
	var space_state = get_world_3d().direct_space_state
	if not space_state: return
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	query.collision_mask = 3 # Layer 1 (Ground) and Layer 2 (Blocks)
	var result: Dictionary = space_state.intersect_ray(query)
	if result:
		var hit_collider_object = result.get("collider", null)
		var hit_position: Vector3 = result.get("position", Vector3.ZERO)
		var hit_normal_raw: Vector3 = result.get("normal", Vector3.ZERO)
		var hit_normal = hit_normal_raw.round()
		var target_coord: Vector3i; var can_place_here = false; var is_expansion = false
		var source_building_type_for_wfc = "" 
		if hit_collider_object and hit_collider_object is CollisionObject3D:
			if hit_collider_object.get_collision_layer_value(1): 
				target_coord = Vector3i(floori(hit_position.x / GRID_CELL_SIZE), 0, floori(hit_position.z / GRID_CELL_SIZE))
				if not occupied_cells.has(target_coord): can_place_here = true; is_expansion = false
			elif hit_collider_object.get_collision_layer_value(2): 
				if hit_collider_object.has_meta("grid_coord"):
					var source_coord: Vector3i = hit_collider_object.get_meta("grid_coord")
					var source_block_data = occupied_cells.get(source_coord)
					if source_block_data:
						var source_block_assigned_type = source_block_data.get("building_type_assigned")
						
						if source_block_assigned_type == current_selected_building_type or \
						   source_block_assigned_type == "generic" or \
						   current_selected_building_type == "generic":
							target_coord = source_coord + Vector3i(hit_normal.x, hit_normal.y, hit_normal.z)
							if target_coord.y < 0: pass
							elif not occupied_cells.has(target_coord):
								can_place_here = true
								is_expansion = true
								source_building_type_for_wfc = source_block_assigned_type 
						
		if can_place_here:
			var placement_intent_type = current_selected_building_type
			if is_expansion and source_building_type_for_wfc != "generic" and current_selected_building_type == "generic":
				placement_intent_type = source_building_type_for_wfc
			
			if is_expansion:
				var wfc_selection_context_type = placement_intent_type 
				var valid_choices = wfc_solver.get_valid_states_for_coord(target_coord, occupied_cells, wfc_selection_context_type, source_building_type_for_wfc)
				if not valid_choices.is_empty():
					var chosen_state = valid_choices.pick_random()
					place_specific_block(target_coord, chosen_state.module_key, chosen_state.rotation, placement_intent_type)
			else: 
				var starter_module_key = ""
				for key in module_data:
					if module_data[key].get("building_type") == placement_intent_type:
						starter_module_key = key; break
				if starter_module_key.is_empty(): 
					for key in module_data:
						if module_data[key].get("building_type") == "generic":
							if key == "Block_Solid": starter_module_key = key; break
							elif starter_module_key.is_empty(): starter_module_key = key
				if starter_module_key.is_empty() and not module_data.is_empty():
					starter_module_key = module_data.keys()[0]

				if starter_module_key.is_empty():
					printerr("No suitable starter module for type '" + placement_intent_type + "'."); return
				place_specific_block(target_coord, starter_module_key, 0, placement_intent_type)

func place_specific_block(coord: Vector3i, module_key: String, rotation_y: int, assigned_building_type: String) -> bool:
	if occupied_cells.has(coord): return false
	if not module_data.has(module_key):
		printerr("Error: Module_key '", module_key, "' not found in module_data.")
		return false

	var block_info = module_data[module_key] 
	var actual_module_type_of_this_block = block_info.get("building_type", "generic") 
	var fulfills_needs_of_block = block_info.get("fulfills_needs", {})

	var capacity_for_this_block_in_this_structure = 0
	if assigned_building_type == "dorm":
		capacity_for_this_block_in_this_structure = 2
	elif assigned_building_type == "class":
		capacity_for_this_block_in_this_structure = 5
	elif assigned_building_type == "generic":
		capacity_for_this_block_in_this_structure = 0
	
	var block_scene_path = block_info.get("path", "")
	if block_scene_path.is_empty() or not FileAccess.file_exists(block_scene_path):
		printerr("GLB missing for module key '", module_key, "' (path: '", block_scene_path, "').")
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
	static_body.collision_layer = 2; static_body.collision_mask = 0
	var collision_shape_node = CollisionShape3D.new(); var box_shape_resource = BoxShape3D.new()
	box_shape_resource.size = Vector3(GRID_CELL_SIZE, GRID_CELL_SIZE, GRID_CELL_SIZE)
	collision_shape_node.shape = box_shape_resource; collision_shape_node.position = Vector3(0, GRID_CELL_SIZE / 2.0, 0)
	static_body.add_child(visual_instance); static_body.add_child(collision_shape_node)
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
	elif navigation_region: navigation_region.add_child(static_body); printerr("Warning: Added block directly to NavRegion.")
	else: add_child(static_body); printerr("CRITICAL: No NavRegion.")
	
	placed_block_nodes.append(static_body)
	var placement_position = Vector3((float(coord.x) + 0.5) * GRID_CELL_SIZE, float(coord.y) * GRID_CELL_SIZE, (float(coord.z) + 0.5) * GRID_CELL_SIZE)
	static_body.global_position = placement_position; static_body.rotation_degrees.y = float(rotation_y)
	
	occupied_cells[coord] = {
		"module_key": module_key,                            
		"rotation": rotation_y,
		"building_type_assigned": assigned_building_type,    
		"node_ref": static_body,
		"capacity_per_block": capacity_for_this_block_in_this_structure, 
		"actual_module_type": actual_module_type_of_this_block           
	}
	static_body.set_meta("grid_coord", coord)
	
	# print_debug("Placed Block: Coord=", str(coord), ", ModuleKey=", module_key, 
	# 			", AssignedStructType=", assigned_building_type, 
	# 			", ActualBlockType=", actual_module_type_of_this_block,
	# 			", CapacityAdded=", str(capacity_for_this_block_in_this_structure))

	if assigned_building_type != "generic":
		_update_functional_building_clusters(coord, assigned_building_type)

	if navigation_region and navigation_region.navigation_mesh: rebake_navigation_mesh(true)
	return true

# --- Functional Building Cluster Management ---
func _update_functional_building_clusters(changed_coord: Vector3i, intended_functional_type: String):
	if intended_functional_type == "generic": return

	var component_coords: Array[Vector3i] = _get_connected_functional_blocks(changed_coord, intended_functional_type)
	
	if component_coords.is_empty():
		var affected_cluster_id_to_reprocess: String = ""
		var cluster_to_remove_entirely: String = ""
		for cluster_id_key in functional_buildings.keys():
			var cluster = functional_buildings[cluster_id_key]
			if cluster.building_type == intended_functional_type and cluster.blocks_coords.has(changed_coord):
				cluster.blocks_coords.erase(changed_coord)
				if cluster.blocks_coords.is_empty():
					cluster_to_remove_entirely = str(cluster_id_key)
				else:
					affected_cluster_id_to_reprocess = str(cluster_id_key)
				break
		if cluster_to_remove_entirely != "":
			if is_instance_valid(functional_buildings[cluster_to_remove_entirely].label_node_instance):
				functional_buildings[cluster_to_remove_entirely].label_node_instance.queue_free()
			functional_buildings.erase(cluster_to_remove_entirely)
		elif affected_cluster_id_to_reprocess != "":
			var remaining_block_coord = functional_buildings[affected_cluster_id_to_reprocess].blocks_coords[0]
			var old_label = functional_buildings[affected_cluster_id_to_reprocess].label_node_instance
			functional_buildings.erase(affected_cluster_id_to_reprocess)
			if is_instance_valid(old_label): old_label.queue_free()
			_update_functional_building_clusters(remaining_block_coord, intended_functional_type)
		return

	var representative_coord = component_coords[0]
	for c_idx in range(1, component_coords.size()):
		var c = component_coords[c_idx]
		if c.x < representative_coord.x or \
		   (c.x == representative_coord.x and c.z < representative_coord.z) or \
		   (c.x == representative_coord.x and c.z == representative_coord.z and c.y < representative_coord.y):
			representative_coord = c
	
	var new_cluster_id_str = str(representative_coord)
	var new_total_capacity = 0
	var cluster_block_nodes: Array[Node3D] = []
	var current_total_users = 0 

	var final_cluster_coords_set: Dictionary = {}
	for c_coord in component_coords:
		final_cluster_coords_set[c_coord] = true

	var existing_cluster_ids_to_remove: Array[String] = []
	for existing_id_key_variant in functional_buildings.keys():
		var existing_id = str(existing_id_key_variant)
		var existing_cluster = functional_buildings[existing_id_key_variant]
		if existing_cluster.building_type == intended_functional_type:
			var intersects = false
			for existing_block_coord in existing_cluster.blocks_coords:
				if final_cluster_coords_set.has(existing_block_coord):
					intersects = true; break
			if intersects:
				if not existing_cluster_ids_to_remove.has(existing_id):
					existing_cluster_ids_to_remove.append(existing_id)
	
	var final_cluster_coords_array: Array[Vector3i] = component_coords.duplicate()

	if not existing_cluster_ids_to_remove.is_empty():
		var temp_merged_coords_set: Dictionary = {}
		for c_coord in final_cluster_coords_array:
			temp_merged_coords_set[c_coord] = true

		for id_to_merge_variant in existing_cluster_ids_to_remove:
			var id_to_merge = str(id_to_merge_variant)
			if functional_buildings.has(id_to_merge):
				var cluster_to_merge = functional_buildings[id_to_merge]
				current_total_users += cluster_to_merge.current_users
				for block_coord_to_merge in cluster_to_merge.blocks_coords:
					temp_merged_coords_set[block_coord_to_merge] = true
				if is_instance_valid(cluster_to_merge.label_node_instance):
					cluster_to_merge.label_node_instance.queue_free()
				functional_buildings.erase(id_to_merge)
		
		final_cluster_coords_array.clear()
		for mc_coord in temp_merged_coords_set.keys():
			final_cluster_coords_array.append(mc_coord)

		if not final_cluster_coords_array.is_empty():
			representative_coord = final_cluster_coords_array[0]
			for c_idx in range(1, final_cluster_coords_array.size()):
				var c = final_cluster_coords_array[c_idx]
				if c.x < representative_coord.x or \
				   (c.x == representative_coord.x and c.z < representative_coord.z) or \
				   (c.x == representative_coord.x and c.z == representative_coord.z and c.y < representative_coord.y):
					representative_coord = c
			new_cluster_id_str = str(representative_coord)
		else:
			# print_debug("  ERROR: Merged cluster resulted in empty coordinates. Aborting update for this cluster.")
			return

	new_total_capacity = 0 
	cluster_block_nodes.clear() 
	for c_coord in final_cluster_coords_array: 
		if occupied_cells.has(c_coord):
			var cell_data = occupied_cells[c_coord]
			new_total_capacity += cell_data.get("capacity_per_block", 0)
			
			if cell_data.has("node_ref") and is_instance_valid(cell_data.node_ref):
				cluster_block_nodes.append(cell_data.node_ref)

	if final_cluster_coords_array.is_empty() or cluster_block_nodes.is_empty():
		# print_debug("  ERROR: Final cluster coords or block nodes are empty. Cannot create/update cluster.")
		if functional_buildings.has(new_cluster_id_str) and is_instance_valid(functional_buildings[new_cluster_id_str].get("label_node_instance")):
			functional_buildings[new_cluster_id_str].label_node_instance.queue_free()
		if functional_buildings.has(new_cluster_id_str): functional_buildings.erase(new_cluster_id_str)
		return

	var label_node_3d_instance: Node3D = null
	var users_to_set_in_cluster = current_total_users 

	if functional_buildings.has(new_cluster_id_str):
		var existing_data = functional_buildings[new_cluster_id_str]
		label_node_3d_instance = existing_data.label_node_instance
		if existing_cluster_ids_to_remove.is_empty(): 
			users_to_set_in_cluster = existing_data.current_users
		
		existing_data.blocks_coords = final_cluster_coords_array
		existing_data.total_capacity = new_total_capacity
		existing_data.current_users = min(users_to_set_in_cluster, new_total_capacity) 
		existing_data.representative_block_node = occupied_cells[representative_coord].node_ref if occupied_cells.has(representative_coord) else null
	else:
		if capacity_label_scene:
			label_node_3d_instance = capacity_label_scene.instantiate() as Node3D
			if is_instance_valid(label_node_3d_instance) and is_instance_valid(capacity_labels_parent):
				capacity_labels_parent.add_child(label_node_3d_instance)
			else: label_node_3d_instance = null
		
		functional_buildings[new_cluster_id_str] = {
			"building_type": intended_functional_type,
			"blocks_coords": final_cluster_coords_array,
			"total_capacity": new_total_capacity,
			"current_users": min(users_to_set_in_cluster, new_total_capacity), 
			"label_node_instance": label_node_3d_instance,
			"representative_block_node": occupied_cells[representative_coord].node_ref if occupied_cells.has(representative_coord) else null
		}
	
	if is_instance_valid(label_node_3d_instance) and not cluster_block_nodes.is_empty():
		var sum_pos = Vector3.ZERO
		for bn in cluster_block_nodes: sum_pos += bn.global_position
		var centroid = sum_pos / cluster_block_nodes.size()
		label_node_3d_instance.global_position = Vector3(centroid.x, centroid.y + GRID_CELL_SIZE * 0.75, centroid.z)
		
		var actual_label = label_node_3d_instance.get_node_or_null("CapacityTextLabel") as Label3D
		if is_instance_valid(actual_label):
			actual_label.text = str(functional_buildings[new_cluster_id_str].current_users) + "/" + str(new_total_capacity)
			actual_label.visible = new_total_capacity > 0
	elif is_instance_valid(label_node_3d_instance):
		var actual_label = label_node_3d_instance.get_node_or_null("CapacityTextLabel") as Label3D
		if is_instance_valid(actual_label): actual_label.visible = false

	# print_debug("  Functional building cluster '", new_cluster_id_str, 
	# 			"' (", intended_functional_type, ") updated. Capacity: ", 
	# 			functional_buildings[new_cluster_id_str].current_users, "/", new_total_capacity, 
	# 			". Blocks: ", str(final_cluster_coords_array.size()))


func _get_connected_functional_blocks(start_coord: Vector3i, intended_type: String) -> Array[Vector3i]:
	var component: Array[Vector3i] = []
	var queue: Array[Vector3i] = [start_coord]
	var visited: Dictionary = {start_coord: true}

	while not queue.is_empty():
		var current_coord = queue.pop_front()
		
		if not occupied_cells.has(current_coord): continue
		var cell_data = occupied_cells[current_coord]
		
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
				if neighbor_cell_data.get("building_type_assigned") == intended_type:
					visited[neighbor_coord] = true
					queue.append(neighbor_coord)
	return component


func student_entered_functional_building(cluster_id_str_or_coord: Variant) -> bool:
	var cluster_id_to_use = str(cluster_id_str_or_coord)

	if functional_buildings.has(cluster_id_to_use):
		var cluster = functional_buildings[cluster_id_to_use]
		if cluster.current_users < cluster.total_capacity:
			cluster.current_users += 1
			_update_cluster_label(cluster_id_to_use)
			return true
		else: return false
	return false

func student_left_functional_building(cluster_id_str_or_coord: Variant):
	var cluster_id_to_use = str(cluster_id_str_or_coord)
	if functional_buildings.has(cluster_id_to_use):
		var cluster = functional_buildings[cluster_id_to_use]
		cluster.current_users = maxi(0, cluster.current_users - 1)
		_update_cluster_label(cluster_id_to_use)

func _update_cluster_label(cluster_id_str: String):
	if functional_buildings.has(cluster_id_str):
		var cluster = functional_buildings[cluster_id_str]
		if is_instance_valid(cluster.label_node_instance):
			var actual_label = cluster.label_node_instance.get_node_or_null("CapacityTextLabel") as Label3D
			if is_instance_valid(actual_label):
				actual_label.text = str(cluster.current_users) + "/" + str(cluster.total_capacity)
				actual_label.visible = cluster.total_capacity > 0


func get_all_occupied_cells_data() -> Dictionary: return occupied_cells.duplicate(true)
func get_functional_buildings_data() -> Dictionary: return functional_buildings.duplicate(true)


func clear_all_blocks():
	for block_node in placed_block_nodes:
		if is_instance_valid(block_node):
			if block_node.get_parent(): block_node.get_parent().remove_child(block_node)
			block_node.queue_free()
	placed_block_nodes.clear(); occupied_cells.clear()

	for cluster_id in functional_buildings:
		var cluster_data = functional_buildings[cluster_id]
		if is_instance_valid(cluster_data.label_node_instance):
			cluster_data.label_node_instance.queue_free()
	functional_buildings.clear()

	if is_instance_valid(nav_mesh_block_parent):
		for child in nav_mesh_block_parent.get_children():
			nav_mesh_block_parent.remove_child(child); child.queue_free()
	total_annual_income = 500.0; total_annual_expenses = 200.0
	update_financial_ui()
	if wfc_solver: wfc_solver.initialize(Vector3i.ONE, module_data)
	if student_manager and student_manager.has_method("clear_all_students"): student_manager.clear_all_students()
	if navigation_region and navigation_region.navigation_mesh: call_deferred("rebake_navigation_mesh", false)

# --- Student Roster UI Functions ---
func _on_view_students_button_pressed():
	if not is_instance_valid(student_list_panel): 
		printerr("BuildingManager: StudentListPanel is not valid. Cannot show.")
		return
	# Hide Program panel if it's open, to avoid overlap
	if is_instance_valid(program_management_panel) and program_management_panel.visible:
		program_management_panel.visible = false
		
	populate_student_roster()
	student_list_panel.visible = true

func _on_close_student_panel_button_pressed():
	if is_instance_valid(student_list_panel): 
		student_list_panel.visible = false

func populate_student_roster():
	if not is_instance_valid(student_list_vbox) or not is_instance_valid(student_manager) or not student_list_item_scene:
		printerr("BuildingManager: Cannot populate student roster due to missing components (VBox, StudentManager, or ItemScene).")
		return
	for child in student_list_vbox.get_children(): child.queue_free()
	if student_manager.has_method("get_all_student_nodes"):
		var students: Array[Node] = student_manager.get_all_student_nodes()
		if students.is_empty():
			var empty_label = Label.new(); empty_label.text = "No students enrolled yet."
			student_list_vbox.add_child(empty_label)
		else:
			for student_node in students:
				if is_instance_valid(student_node):
					var item_instance = student_list_item_scene.instantiate()
					if not is_instance_valid(item_instance): continue
					student_list_vbox.add_child(item_instance)
					if item_instance.has_method("set_student_data"): item_instance.set_student_data(student_node)

# --- Program Management UI Functions --- (NEW)
func _on_view_programs_button_pressed():
	if not is_instance_valid(program_management_panel):
		printerr("BuildingManager: ProgramManagementPanel is not valid. Cannot show.")
		return

	var new_visibility = not program_management_panel.visible
	# scheduling_panel.visible = new_visibility # Visibility will be handled by show_panel/hide_panel

	if new_visibility:
		if is_instance_valid(program_management_panel) and program_management_panel.visible:
			program_management_panel.visible = false


		if program_management_panel.has_method("show_panel"):
			program_management_panel.show_panel()
		else: # Fallback if show_panel isn't defined, directly set visible and refresh
			program_management_panel.visible = true
			if program_management_panel.has_method("refresh_ui"):
				program_management_panel.refresh_ui()
		print_debug("Showing Management Panel.")
	else:
		if program_management_panel.has_method("hide_panel"):
			program_management_panel.hide_panel()
		else: # Fallback
			program_management_panel.visible = false
		print_debug("Hiding Management Panel Panel.")

func _on_view_schedule_button_pressed():
	if not is_instance_valid(scheduling_panel):
		printerr("BuildingManager: SchedulingPanel is not valid. Cannot show.")
		return

	var new_visibility = not scheduling_panel.visible
	# scheduling_panel.visible = new_visibility # Visibility will be handled by show_panel/hide_panel

	if new_visibility:
		if is_instance_valid(student_list_panel) and student_list_panel.visible:
			student_list_panel.visible = false
		if is_instance_valid(program_management_panel) and program_management_panel.visible:
			program_management_panel.visible = false

		if scheduling_panel.has_method("show_panel"):
			scheduling_panel.show_panel()
		else: # Fallback if show_panel isn't defined, directly set visible and refresh
			scheduling_panel.visible = true
			if scheduling_panel.has_method("refresh_ui"):
				scheduling_panel.refresh_ui()
		print_debug("Showing Scheduling Panel.")
	else:
		if scheduling_panel.has_method("hide_panel"):
			scheduling_panel.hide_panel()
		else: # Fallback
			scheduling_panel.visible = false
		print_debug("Hiding Scheduling Panel.")
		
# --- Helper Functions ---
func get_navigation_region() -> NavigationRegion3D: return navigation_region
func print_debug(message_parts):
	var output_message = "[BuildingManager]: "
	if typeof(message_parts) == TYPE_STRING:
		output_message += message_parts
	elif typeof(message_parts) == TYPE_ARRAY or typeof(message_parts) == TYPE_PACKED_STRING_ARRAY:
		var temp_array : Array = message_parts
		output_message += " ".join(temp_array) 
	else:
		output_message += str(message_parts)
	print(output_message)
