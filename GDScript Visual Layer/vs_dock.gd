@tool
extends VBoxContainer

var editor_interface: EditorInterface

var Parser = preload("res://addons/GDScript Visual Layer/vs_parser.gd")
var MetaStore = preload("res://addons/GDScript Visual Layer/vs_meta_store.gd")
var NodeFactory = preload("res://addons/GDScript Visual Layer/vs_node_factory.gd")
var ClassDBStore = preload("res://addons/GDScript Visual Layer/vs_classdb_store.gd")
var PaletteScene = preload("res://addons/GDScript Visual Layer/vs_palette.gd")
var WriterScript = preload("res://addons/GDScript Visual Layer/vs_writer.gd")
var writer: RefCounted


var current_script_path := ""
var parsed: Dictionary = {}
var meta: Dictionary = {}
var current_view := "overview"
var focused_function_id := ""
var script_paths := PackedStringArray()
var last_script_mtime := 0
var ignore_reload_until_msec := 0

var layout_dirty := false
var suppress_events := false

var graph: GraphEdit
var symbol_tree: Tree
var status_label: Label
var script_select: OptionButton
var info_label: RichTextLabel
var action_row: HBoxContainer
var file_dialog: FileDialog
var palette_popup: PopupPanel
var palette_search: LineEdit
var palette_tree: Tree
var palette_info: RichTextLabel
var palette_items: Array = []
var palette_position := Vector2.ZERO
var palette_context_type := ""
var palette_pending_connection := {}
var autosave_timer: Timer
var file_watch_timer: Timer
var sidebar: VBoxContainer
var sidebar_visible := true
var selected_node_name := ""


func _ready() -> void:
	writer = WriterScript.new(NodeFactory)
	name = "GDScript Visual Layer"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2.ZERO
	_load_modules()
	_build_ui()
	_start_timers()
	_refresh_script_list()


func _load_modules() -> void:
	return

func _build_ui() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var sidebar_button := Button.new()
	sidebar_button.text = "☰"
	sidebar_button.tooltip_text = "Toggle sidebar"
	sidebar_button.pressed.connect(func() -> void:
		sidebar_visible = not sidebar_visible
		sidebar.visible = sidebar_visible
	)
	toolbar.add_child(sidebar_button)

	var back_button := Button.new()
	back_button.text = "Overview"
	back_button.pressed.connect(_show_overview)
	toolbar.add_child(back_button)

	status_label = Label.new()
	status_label.text = "No script loaded"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(status_label)

	var use_selected := Button.new()
	use_selected.text = "Use Selected"
	use_selected.pressed.connect(_use_selected_file)
	toolbar.add_child(use_selected)

	var browse := Button.new()
	browse.text = "Browse"
	browse.pressed.connect(func() -> void:
		file_dialog.popup_centered_ratio(0.75)
	)
	toolbar.add_child(browse)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_reload_script)
	toolbar.add_child(refresh)

	var open_code := Button.new()
	open_code.text = "Script"
	open_code.pressed.connect(func() -> void:
		_open_script_at_line(1)
	)
	toolbar.add_child(open_code)

	var group_button := Button.new()
	group_button.text = "Group"
	group_button.tooltip_text = "Group selected nodes. Shortcut: Ctrl+G"
	group_button.pressed.connect(_group_selected_nodes)
	toolbar.add_child(group_button)

	var write_button := Button.new()
	write_button.text = "Write Function"
	write_button.pressed.connect(_write_function)
	toolbar.add_child(write_button)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(270, 360)
	split.add_child(sidebar)

	script_select = OptionButton.new()
	script_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_select.item_selected.connect(_on_script_selected)
	sidebar.add_child(script_select)

	var add_callback := Button.new()
	add_callback.text = "Add Callback"
	add_callback.pressed.connect(_show_callback_palette)
	sidebar.add_child(add_callback)

	symbol_tree = Tree.new()
	symbol_tree.hide_root = true
	symbol_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	symbol_tree.item_activated.connect(_on_symbol_activated)
	symbol_tree.item_selected.connect(_on_symbol_selected)
	sidebar.add_child(symbol_tree)

	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.custom_minimum_size = Vector2(0, 115)
	info_label.text = "Select a node. Details stay intentionally compact."
	sidebar.add_child(info_label)

	action_row = HBoxContainer.new()
	sidebar.add_child(action_row)

	graph = GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.show_grid = true
	graph.show_menu = true
	graph.minimap_enabled = true
	graph.right_disconnects = true
	graph.connection_lines_thickness = 3.0
	_register_connection_types()
	graph.connection_request.connect(_on_connection_request)
	graph.disconnection_request.connect(_on_disconnection_request)
	graph.connection_to_empty.connect(_on_connection_to_empty)
	graph.connection_from_empty.connect(_on_connection_from_empty)
	graph.end_node_move.connect(_mark_layout_dirty)
	graph.scroll_offset_changed.connect(func(_v: Vector2) -> void:
		_mark_layout_dirty()
	)
	graph.delete_nodes_request.connect(_on_delete_nodes_request)
	graph.gui_input.connect(_on_graph_gui_input)
	split.add_child(graph)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.gd ; GDScript")
	file_dialog.file_selected.connect(_load_script)
	add_child(file_dialog)

	_build_palette()


func _register_connection_types() -> void:
	graph.add_valid_connection_type(NodeFactory.PORT_EXEC, NodeFactory.PORT_EXEC)
	var value_types := [NodeFactory.PORT_ANY, NodeFactory.PORT_VALUE, NodeFactory.PORT_OBJECT, NodeFactory.PORT_BOOL, NodeFactory.PORT_NUMBER, NodeFactory.PORT_STRING, NodeFactory.PORT_VECTOR]
	for left_type in value_types:
		for right_type in value_types:
			graph.add_valid_connection_type(left_type, right_type)
	for port_type in value_types + [NodeFactory.PORT_EXEC]:
		graph.add_valid_left_disconnect_type(port_type)
		graph.add_valid_right_disconnect_type(port_type)


func _build_palette() -> void:
	palette_popup = PopupPanel.new()
	palette_popup.min_size = Vector2i(620, 650)
	add_child(palette_popup)

	var root := VBoxContainer.new()
	palette_popup.add_child(root)

	palette_search = LineEdit.new()
	palette_search.placeholder_text = "Search nodes, variables, functions, Godot methods..."
	palette_search.text_changed.connect(_filter_palette)
	root.add_child(palette_search)

	palette_tree = Tree.new()
	palette_tree.hide_root = true
	palette_tree.custom_minimum_size = Vector2(600, 430)
	palette_tree.item_selected.connect(_on_palette_selected)
	palette_tree.item_activated.connect(_on_palette_activated)
	root.add_child(palette_tree)

	palette_info = RichTextLabel.new()
	palette_info.bbcode_enabled = true
	palette_info.custom_minimum_size = Vector2(600, 100)
	root.add_child(palette_info)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)

	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(_add_selected_palette)
	buttons.add_child(add)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		palette_popup.hide()
	)
	buttons.add_child(cancel)


func _start_timers() -> void:
	autosave_timer = Timer.new()
	autosave_timer.wait_time = 0.6
	autosave_timer.one_shot = false
	autosave_timer.timeout.connect(flush_layout)
	add_child(autosave_timer)
	autosave_timer.start()

	file_watch_timer = Timer.new()
	file_watch_timer.wait_time = 0.7
	file_watch_timer.one_shot = false
	file_watch_timer.timeout.connect(_check_external_script_change)
	add_child(file_watch_timer)
	file_watch_timer.start()


func on_main_screen_visible() -> void:
	_check_external_script_change()


func on_resource_saved(resource: Resource) -> void:
	if resource == null:
		return
	if current_script_path != "" and resource.resource_path == current_script_path:
		call_deferred("_reload_script_preserve_view")


func _refresh_script_list() -> void:
	script_paths.clear()
	_collect_scripts("res://")
	script_paths.sort()
	script_select.clear()
	for path in script_paths:
		script_select.add_item(path)
	if current_script_path == "" and script_paths.size() > 0:
		_load_script(script_paths[0])
	elif current_script_path != "":
		var index := script_paths.find(current_script_path)
		if index >= 0:
			script_select.select(index)


func _collect_scripts(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break
		if file_name.begins_with("."):
			continue
		var path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if file_name == "addons" or file_name == ".godot":
				continue
			_collect_scripts(path)
		elif file_name.ends_with(".gd"):
			script_paths.append(path)
	dir.list_dir_end()


func _on_script_selected(index: int) -> void:
	if index >= 0 and index < script_paths.size():
		_load_script(script_paths[index])


func _use_selected_file() -> void:
	if editor_interface == null or not editor_interface.has_method("get_selected_paths"):
		_set_status("Selected path access not available.")
		return
	var paths: PackedStringArray = editor_interface.call("get_selected_paths")
	for path in paths:
		if str(path).ends_with(".gd"):
			_load_script(str(path))
			return
	_set_status("No selected .gd file.")


func _load_script(path: String) -> void:
	if path == "" or not path.ends_with(".gd"):
		return
	flush_layout()
	current_script_path = path
	parsed = Parser.parse_script(path)
	meta = MetaStore.load_meta(path)
	current_view = "overview"
	focused_function_id = ""
	last_script_mtime = _mtime(path)
	_rebuild_all()
	_select_script_in_option(path)
	_set_status(path)


func _reload_script() -> void:
	if current_script_path == "":
		return
	_load_script(current_script_path)


func _reload_script_preserve_view() -> void:
	if current_script_path == "":
		return
	var old_view := current_view
	var old_function := focused_function_id
	flush_layout()
	parsed = Parser.parse_script(current_script_path)
	meta = MetaStore.load_meta(current_script_path)
	last_script_mtime = _mtime(current_script_path)
	if old_view != "overview" and not _function_by_id(old_function).is_empty():
		current_view = old_view
		focused_function_id = old_function
	else:
		current_view = "overview"
		focused_function_id = ""
	_rebuild_all()
	_set_status("Reloaded: " + current_script_path)


func _check_external_script_change() -> void:
	if current_script_path == "" or Time.get_ticks_msec() < ignore_reload_until_msec:
		return
	var new_mtime := _mtime(current_script_path)
	if last_script_mtime > 0 and new_mtime > 0 and new_mtime != last_script_mtime:
		_reload_script_preserve_view()


func _mtime(path: String) -> int:
	if path == "":
		return 0
	var global_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		return int(FileAccess.get_modified_time(global_path))
	return 0


func _select_script_in_option(path: String) -> void:
	var index := script_paths.find(path)
	if index >= 0:
		script_select.select(index)


func _rebuild_all() -> void:
	_rebuild_symbols()
	_rebuild_graph()


func _rebuild_symbols() -> void:
	symbol_tree.clear()
	var root := symbol_tree.create_item()

	var funcs := symbol_tree.create_item(root)
	funcs.set_text(0, "Functions")
	funcs.collapsed = false
	for function_data in parsed.get("functions", []):
		var item := symbol_tree.create_item(funcs)
		item.set_text(0, "%s()" % str(function_data.get("name", "")))
		item.set_metadata(0, {"kind": "function", "data": function_data})

	var vars := symbol_tree.create_item(root)
	vars.set_text(0, "Variables")
	vars.collapsed = false
	for variable_data in parsed.get("variables", []):
		var item := symbol_tree.create_item(vars)
		item.set_text(0, "%s: %s" % [str(variable_data.get("name", "")), str(variable_data.get("type", "Variant"))])
		item.set_metadata(0, {"kind": "variable", "data": variable_data})

	var missing := symbol_tree.create_item(root)
	missing.set_text(0, "Add Lifecycle")
	missing.collapsed = false
	var existing := {}
	for function_data in parsed.get("functions", []):
		existing[str(function_data.get("name", ""))] = true
	for callback_name in Parser.lifecycle_names():
		if not existing.has(str(callback_name)):
			var item := symbol_tree.create_item(missing)
			item.set_text(0, str(callback_name) + "()")
			item.set_metadata(0, {"kind": "callback", "name": str(callback_name)})


func _rebuild_graph() -> void:
	suppress_events = true
	for child in graph.get_children():
		if child is GraphNode:
			child.queue_free()
	await get_tree().process_frame

	if current_view == "overview":
		_build_overview_graph()
	else:
		_build_function_graph(focused_function_id)

	_restore_groups()
	_restore_saved_connections()
	graph.scroll_offset = MetaStore.get_scroll(meta, current_view)
	graph.zoom = MetaStore.get_zoom(meta, current_view)
	var needs_arrange := not MetaStore.view_has_saved_nodes(meta, current_view)
	suppress_events = false
	call_deferred("_sync_connected_input_fields")
	if needs_arrange:
		call_deferred("_auto_arrange_graph")


func _add_graph_node(node: GraphNode) -> GraphNode:
	graph.add_child(node)
	if str(node.get_meta("gdvl_type", "")) == "group":
		node.z_index = -100
		graph.move_child(node, 0)
	node.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
				_show_node_info(node)
	)
	_connect_node_edit_signals(node)
	return node


func _build_overview_graph() -> void:
	var y := 50.0
	for function_data in parsed.get("functions", []):
		var node_id := "func__" + NodeFactory.sanitize_id(str(function_data.get("id", "")))
		var pos := MetaStore.get_node_position(meta, current_view, node_id, Vector2(320, y))
		var function_node := NodeFactory.make_function_node(function_data, pos)
		_add_function_expand_button(function_node, str(function_data.get("id", "")))
		_add_graph_node(function_node)
		y += 108.0

	var y_var := 50.0
	for variable_data in parsed.get("variables", []):
		var node_id := "var__" + NodeFactory.sanitize_id(str(variable_data.get("name", "")))
		var pos := MetaStore.get_node_position(meta, current_view, node_id, Vector2(40, y_var))
		_add_graph_node(NodeFactory.make_variable_node(variable_data, pos))
		y_var += 76.0

	_connect_overview_call_edges()


func _connect_overview_call_edges() -> void:
	var function_by_name := {}
	for function_data in parsed.get("functions", []):
		function_by_name[str(function_data.get("name", ""))] = function_data

	for function_data in parsed.get("functions", []):
		var from_node := StringName("func__" + NodeFactory.sanitize_id(str(function_data.get("id", ""))))
		for statement in function_data.get("statements", []):
			_connect_overview_statement_call(from_node, statement, function_by_name)


func _connect_overview_statement_call(from_node: StringName, statement: Dictionary, function_by_name: Dictionary) -> void:
	if str(statement.get("kind", "")) == "script_call":
		var call_name := str(statement.get("call_name", ""))
		if function_by_name.has(call_name):
			var target: Dictionary = function_by_name[call_name]
			var to_node := StringName("func__" + NodeFactory.sanitize_id(str(target.get("id", ""))))
			if not graph.is_node_connected(from_node, 0, to_node, 0):
				graph.connect_node(from_node, 0, to_node, 0)
	elif str(statement.get("kind", "")) == "branch":
		for sub in statement.get("true_statements", []):
			_connect_overview_statement_call(from_node, sub, function_by_name)
		for sub in statement.get("false_statements", []):
			_connect_overview_statement_call(from_node, sub, function_by_name)


func _build_function_graph(function_id: String) -> void:
	var function_data := _function_by_id(function_id)
	if function_data.is_empty():
		_show_overview()
		return

	_set_status("Function: " + str(function_data.get("name", function_id)))
	var entry_name := "entry__" + NodeFactory.sanitize_id(function_id)
	var entry_pos := MetaStore.get_node_position(meta, current_view, entry_name, Vector2(40, 120))
	var entry := _add_graph_node(NodeFactory.make_entry_node(function_data, entry_pos))

	var cursor := Vector2(330, 80)
	var sequence := _build_statement_sequence(function_data.get("statements", []), cursor, 0)
	if sequence.has("first") and sequence["first"] is GraphNode:
		_connect_nodes(entry, 0, sequence["first"], 0)


func _build_statement_sequence(statements: Array, start_pos: Vector2, branch_depth: int) -> Dictionary:
	var first_node: GraphNode = null
	var previous_node: GraphNode = null
	var y := start_pos.y
	var x := start_pos.x

	for statement in statements:
		if typeof(statement) != TYPE_DICTIONARY:
			continue

		var kind := str(statement.get("kind", "statement"))
		if kind == "branch":
			var branch_node := _add_statement_node(statement, Vector2(x, y))
			_build_value_expression(str(statement.get("condition", "true")), statement.get("condition_expr", {}), Vector2(x - 250, y + 72), branch_node, 1)
			if first_node == null:
				first_node = branch_node
			if previous_node != null:
				_connect_nodes(previous_node, 0, branch_node, 0)

			var true_seq := _build_statement_sequence(statement.get("true_statements", []), Vector2(x + 290, y - 65), branch_depth + 1)
			if true_seq.has("first") and true_seq["first"] is GraphNode:
				_connect_nodes(branch_node, 0, true_seq["first"], 0)

			var false_seq := _build_statement_sequence(statement.get("false_statements", []), Vector2(x + 290, y + 105), branch_depth + 1)
			if false_seq.has("first") and false_seq["first"] is GraphNode:
				_connect_nodes(branch_node, 1, false_seq["first"], 0)

			previous_node = branch_node
			y += 230.0
			continue

		var node := _add_statement_node(statement, Vector2(x, y))
		if first_node == null:
			first_node = node
		if previous_node != null:
			_connect_nodes(previous_node, 0, node, 0)
		_build_expression_helpers_for_statement(statement, node, Vector2(x - 250, y))
		if kind == "return":
			previous_node = null
		else:
			previous_node = node
		y += 118.0

	return {"first": first_node, "last": previous_node, "height": y - start_pos.y}


func _add_statement_node(statement: Dictionary, fallback_position: Vector2) -> GraphNode:
	var expected_name := _expected_statement_node_name(statement)
	var position := MetaStore.get_node_position(meta, current_view, expected_name, fallback_position)
	var kind := str(statement.get("kind", "statement"))
	match kind:
		"local_assign":
			return _add_graph_node(NodeFactory.make_local_assign_node(statement, position))
		"set_property":
			return _add_graph_node(NodeFactory.make_set_property_node(statement, position))
		"assignment":
			return _add_graph_node(NodeFactory.make_assignment_node(statement, position))
		"branch":
			return _add_graph_node(NodeFactory.make_branch_node(statement, position))
		"return":
			return _add_graph_node(NodeFactory.make_return_node(statement, position))
		"script_call":
			var function_data := _function_by_name(str(statement.get("call_name", "")))
			if not function_data.is_empty():
				return _add_graph_node(NodeFactory.make_script_call_node(function_data, position, str(statement.get("id", "")), _arg_default_texts(statement.get("args", []))))
		"method_call":
			return _add_graph_node(_method_node_from_statement(statement, position, true))
		"builtin_call":
			var builtin_name := str(statement.get("method_name", "print"))
			var args: Array = statement.get("args", [])
			var global_data := ClassDBStore.get_global_method_data(builtin_name)
			return _add_graph_node(NodeFactory.make_builtin_call_node(builtin_name, position, true, max(args.size(), 1), _arg_default_texts(args), global_data))
	return _add_graph_node(NodeFactory.make_statement_node(statement, position))


func _add_function_expand_button(function_node: GraphNode, function_id: String) -> void:
	var row := HBoxContainer.new()
	var graph_button := Button.new()
	graph_button.text = "Open Graph"
	graph_button.tooltip_text = "Open function graph"
	graph_button.pressed.connect(func() -> void:
		_expand_function(function_id)
	)
	row.add_child(graph_button)
	function_node.add_child(row)


func _arg_default_texts(args: Array) -> Array:
	var result: Array = []
	for arg in args:
		if typeof(arg) == TYPE_DICTIONARY:
			result.append(_default_text_for_expression(arg))
		else:
			result.append("")
	return result


func _default_text_for_expression(expression: Dictionary) -> String:
	var text := str(expression.get("text", ""))
	if _is_quoted_text(text):
		return text.substr(1, text.length() - 2)
	return text


func _can_inline_arg(arg) -> bool:
	if typeof(arg) != TYPE_DICTIONARY:
		return false
	var kind := str(arg.get("kind", ""))
	var text := str(arg.get("text", ""))
	return kind == "expression" and (_is_quoted_text(text) or text.is_valid_int() or text.is_valid_float() or text == "true" or text == "false")


func _is_quoted_text(text: String) -> bool:
	var clean := text.strip_edges()
	if clean.length() < 2:
		return false
	var first := clean[0]
	var last := clean[clean.length() - 1]
	return (first == "\"" and last == "\"") or (first == "'" and last == "'")


func _method_node_from_statement(statement: Dictionary, position: Vector2, exec_enabled: bool) -> GraphNode:
	var target_type := str(statement.get("target_type", ""))
	var method_name := str(statement.get("method_name", "method"))
	var method_data := ClassDBStore.get_method_data(target_type, method_name)
	if method_data.is_empty():
		method_data = _synthetic_method_data(method_name, statement.get("args", []), str(statement.get("value_type", "Variant")))
	return NodeFactory.make_method_node(target_type, method_data, position, str(statement.get("id", "")), str(statement.get("target_expr", "")), exec_enabled, _arg_default_texts(statement.get("args", [])))


func _synthetic_method_data(method_name: String, args: Array, return_type: String) -> Dictionary:
	var arg_defs: Array = []
	var index := 0
	for arg in args:
		var arg_type := "Variant"
		if typeof(arg) == TYPE_DICTIONARY:
			arg_type = str(arg.get("value_type", "Variant"))
		arg_defs.append({"name": "arg%s" % index, "type": _variant_constant_for_type(arg_type)})
		index += 1
	return {"name": method_name, "args": arg_defs, "return": {"type": _variant_constant_for_type(return_type)}}


func _variant_constant_for_type(type_name: String) -> int:
	match type_name:
		"bool": return TYPE_BOOL
		"int": return TYPE_INT
		"float": return TYPE_FLOAT
		"String", "StringName", "NodePath": return TYPE_STRING
		"Vector2": return TYPE_VECTOR2
		"Vector3": return TYPE_VECTOR3
		"Vector4": return TYPE_VECTOR4
		"Color": return TYPE_COLOR
		"Callable": return TYPE_CALLABLE
		"Array": return TYPE_ARRAY
		"Dictionary": return TYPE_DICTIONARY
		"void": return TYPE_NIL
		_: return TYPE_NIL if type_name == "void" else TYPE_OBJECT


func _build_expression_helpers_for_statement(statement: Dictionary, node: GraphNode, base_pos: Vector2) -> void:
	var kind := str(statement.get("kind", ""))
	if ["local_assign", "assignment"].has(kind):
		_build_value_expression(str(statement.get("text", "")), statement.get("value_expr", {}), base_pos, node, 1)
	elif kind == "set_property":
		_build_target_expression(str(statement.get("target_expr", "")), Vector2(base_pos.x, base_pos.y - 42), node, 1)
		_build_value_expression(str(statement.get("text", "")), statement.get("value_expr", {}), Vector2(base_pos.x, base_pos.y + 42), node, 2)
	elif kind == "return":
		var value_text := str(statement.get("value_text", ""))
		if value_text != "":
			_build_value_expression(value_text, statement.get("value_expr", {}), base_pos, node, 1)
	elif kind == "script_call" or kind == "builtin_call" or kind == "method_call":
		var input_start := 1
		if kind == "method_call" and str(statement.get("target_expr", "")) != "":
			_build_target_expression(str(statement.get("target_expr", "")), Vector2(base_pos.x, base_pos.y - 42), node, 1)
			input_start = 2
		var args: Array = statement.get("args", [])
		for i in range(args.size()):
			if _can_inline_arg(args[i]):
				continue
			_build_value_expression("", args[i], Vector2(base_pos.x, base_pos.y + i * 76.0), node, input_start + i)


func _is_global_call(function_name: String) -> bool:
	return ClassDBStore.has_global_method(function_name) or function_name in ["Callable"]


func _build_value_expression(source_text: String, expression_data, position: Vector2, target_node: GraphNode, target_port: int) -> GraphNode:
	var expression: Dictionary = expression_data if typeof(expression_data) == TYPE_DICTIONARY else {"kind": "expression", "text": source_text, "value_type": "Variant"}
	var expr_kind := str(expression.get("kind", "expression"))
	var text := str(expression.get("text", source_text))
	var node: GraphNode

	if expr_kind == "call_expr":
		var call_name := str(expression.get("call_name", ""))
		var target_expr := str(expression.get("target_expr", ""))
		var method_name := str(expression.get("method_name", call_name))
		var stable_prefix := "builtin_value" if target_expr == "" and _is_global_call(call_name) else "value_call"
		var call_stable_name := _stable_helper_name(stable_prefix, text, target_node, target_port)
		var call_stable_position := MetaStore.get_node_position(meta, current_view, call_stable_name, position)
		if target_expr == "" and bool(expression.get("script_function", false)):
			var function_data := _function_by_name(method_name)
			if function_data.is_empty():
				function_data = _function_by_id(str(expression.get("function_id", "")))
			if function_data.is_empty():
				function_data = {"name": method_name, "params": [], "return_type": str(expression.get("value_type", "Variant"))}
			node = _add_graph_node(NodeFactory.make_script_call_node(function_data, call_stable_position, call_stable_name, _arg_default_texts(expression.get("args", [])), false))
		elif target_expr == "" and _is_global_call(call_name):
			var expression_args: Array = expression.get("args", [])
			var global_data := ClassDBStore.get_global_method_data(call_name)
			node = _add_graph_node(NodeFactory.make_builtin_call_node(call_name, call_stable_position, false, max(expression_args.size(), 1), _arg_default_texts(expression_args), global_data))
		else:
			var target_type := str(expression.get("target_type", ""))
			var method_data := ClassDBStore.get_method_data(target_type, method_name)
			if method_data.is_empty():
				method_data = _synthetic_method_data(method_name, expression.get("args", []), str(expression.get("value_type", "Variant")))
			node = _add_graph_node(NodeFactory.make_method_node(target_type, method_data, call_stable_position, call_stable_name, target_expr, false, _arg_default_texts(expression.get("args", []))))
			node.name = call_stable_name
			if target_expr != "":
				_build_target_expression(target_expr, call_stable_position + Vector2(-230, -40), node, 0)

		if node.name != call_stable_name:
			node.name = call_stable_name
		node.position_offset = call_stable_position

		var args: Array = expression.get("args", [])
		var first_arg_port := 1 if target_expr != "" else 0
		for i in range(args.size()):
			if _can_inline_arg(args[i]):
				continue
			_build_value_expression("", args[i], call_stable_position + Vector2(-230, i * 70), node, first_arg_port + i)
	else:
		if _is_simple_name(text):
			node = _build_target_expression(text, position, target_node, target_port)
			return node
		var prefix := "literal" if _is_literal_expression(text) else "expr"
		var value_stable_name := _stable_helper_name(prefix, text, target_node, target_port)
		var value_stable_position := MetaStore.get_node_position(meta, current_view, value_stable_name, position)
		if _is_literal_expression(text):
			node = _add_graph_node(NodeFactory.make_literal_node(text, value_stable_position, str(expression.get("value_type", "Variant"))))
		else:
			node = _add_graph_node(NodeFactory.make_expression_node(text, value_stable_position, str(expression.get("value_type", "Variant"))))
		node.name = value_stable_name
		node.position_offset = value_stable_position

	if target_node != null:
		_connect_nodes(node, 0, target_node, target_port)
	return node

func _build_target_expression(expression_text: String, position: Vector2, target_node: GraphNode, target_port: int) -> GraphNode:
	var clean := expression_text.strip_edges()
	var node: GraphNode
	var variable_data := _variable_or_local_data(clean)
	if not variable_data.is_empty():
		var node_name := "local__" + NodeFactory.sanitize_id(clean) if str(variable_data.get("kind", "")) == "local" else "var__" + NodeFactory.sanitize_id(clean)
		var existing = graph.get_node_or_null(NodePath(node_name))
		if existing is GraphNode:
			node = existing
		else:
			var pos := MetaStore.get_node_position(meta, current_view, node_name, position)
			node = _add_graph_node(NodeFactory.make_variable_node(variable_data, pos, str(variable_data.get("kind", "")) == "local"))
	else:
		var stable_name := _stable_helper_name("expr", clean, target_node, target_port)
		var stable_position := MetaStore.get_node_position(meta, current_view, stable_name, position)
		node = _add_graph_node(NodeFactory.make_expression_node(clean, stable_position, "Variant"))
		node.name = stable_name
		node.position_offset = stable_position

	if target_node != null:
		_connect_nodes(node, 0, target_node, target_port)
	return node


func _stable_helper_name(prefix: String, text: String, target_node: GraphNode, target_port: int) -> String:
	var target_name := "free"
	if target_node != null:
		target_name = str(target_node.name)
	var raw := "%s__p%s__%s" % [target_name, target_port, text]
	return prefix + "__" + NodeFactory.sanitize_id(raw)


func _variable_or_local_data(name_text: String) -> Dictionary:
	if focused_function_id != "":
		var local_maps: Dictionary = parsed.get("local_maps", {})
		var local_map: Dictionary = local_maps.get(focused_function_id, {})
		if local_map.has(name_text):
			return local_map[name_text]
	var variable_map: Dictionary = parsed.get("variable_map", {})
	if variable_map.has(name_text):
		return variable_map[name_text]
	return {}


func _is_literal_expression(text: String) -> bool:
	var clean := text.strip_edges()
	return _is_quoted_text(clean) or clean.is_valid_int() or clean.is_valid_float() or clean == "true" or clean == "false"

func _is_simple_name(text: String) -> bool:
	if text == "":
		return false
	for i in text.length():
		var c := text[i]
		if not (c == "_" or (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return not (text[0] >= "0" and text[0] <= "9")


func _expected_statement_node_name(statement: Dictionary) -> String:
	var kind := str(statement.get("kind", "statement"))
	var id := NodeFactory.sanitize_id(str(statement.get("id", "item")))
	match kind:
		"local_assign": return "local_assign__" + id
		"set_property": return "set__" + id
		"assignment": return "assign__" + id
		"branch": return "branch__" + id
		"return": return "return__" + id
		"script_call": return "call__" + NodeFactory.sanitize_id(str(statement.get("call_name", "call"))) + "__" + id
		"method_call": return "method__" + NodeFactory.sanitize_id(str(statement.get("target_type", ""))) + "__" + NodeFactory.sanitize_id(str(statement.get("method_name", "method"))) + "__" + id
		"builtin_call": return "builtin__" + NodeFactory.sanitize_id(str(statement.get("method_name", "print"))) + "__" + id
	return "stmt__" + id


func _connect_nodes(from_node: GraphNode, from_port: int, to_node: GraphNode, to_port: int) -> void:
	if from_node == null or to_node == null:
		return
	if not graph.is_node_connected(StringName(from_node.name), from_port, StringName(to_node.name), to_port):
		graph.connect_node(StringName(from_node.name), from_port, StringName(to_node.name), to_port)


func _restore_saved_connections() -> void:
	if current_view == "overview":
		return
	if not MetaStore.view_has_saved_nodes(meta, current_view):
		return
	for connection in MetaStore.get_connections(meta, current_view):
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		var from_name := str(connection.get("from_node", ""))
		var to_name := str(connection.get("to_node", ""))
		if graph.get_node_or_null(NodePath(from_name)) == null or graph.get_node_or_null(NodePath(to_name)) == null:
			continue
		if not graph.is_node_connected(StringName(from_name), int(connection.get("from_port", 0)), StringName(to_name), int(connection.get("to_port", 0))):
			graph.connect_node(StringName(from_name), int(connection.get("from_port", 0)), StringName(to_name), int(connection.get("to_port", 0)))


func _auto_arrange_graph() -> void:
	var nodes: Array = []
	for child in graph.get_children():
		if child is GraphNode:
			nodes.append(child)
			child.selected = true
	if graph.has_method("arrange_nodes"):
		graph.call("arrange_nodes")
	else:
		_fallback_arrange(nodes)
	for node in nodes:
		node.selected = false
	_mark_layout_dirty()


func _fallback_arrange(nodes: Array) -> void:
	var y := 60.0
	for node in nodes:
		if str(node.get_meta("gdvl_type", "")) == "entry":
			node.position_offset = Vector2(40, 120)
		elif str(node.get_meta("gdvl_type", "")) in ["variable", "literal", "expression", "value_call", "builtin_value", "math"]:
			pass
		else:
			node.position_offset = Vector2(330, y)
			y += 110.0


func _on_graph_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.ctrl_pressed and key.keycode == KEY_G:
			_group_selected_nodes()
			accept_event()
			return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if graph.has_method("get_closest_connection_at_point"):
				var connection = graph.call("get_closest_connection_at_point", mouse.position, 14.0)
				if typeof(connection) == TYPE_DICTIONARY and not connection.is_empty():
					graph.disconnect_node(StringName(str(connection.get("from_node", ""))), int(connection.get("from_port", 0)), StringName(str(connection.get("to_node", ""))), int(connection.get("to_port", 0)))
					_mark_layout_dirty()
					_sync_connected_input_fields()
					accept_event()
					return
			_open_palette(graph.scroll_offset + mouse.position / max(graph.zoom, 0.01), "", {})
			accept_event()


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if not graph.is_node_connected(from_node, from_port, to_node, to_port):
		graph.connect_node(from_node, from_port, to_node, to_port)
	_mark_layout_dirty()
	_sync_connected_input_fields()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph.disconnect_node(from_node, from_port, to_node, to_port)
	_mark_layout_dirty()
	_sync_connected_input_fields()


func _on_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2) -> void:
	palette_pending_connection = {"mode": "from", "from_node": str(from_node), "from_port": from_port}
	_open_palette(graph.scroll_offset + release_position / max(graph.zoom, 0.01), _output_type_for_node(str(from_node), from_port), palette_pending_connection)


func _on_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	palette_pending_connection = {"mode": "to", "to_node": str(to_node), "to_port": to_port}
	_open_palette(graph.scroll_offset + release_position / max(graph.zoom, 0.01), _input_type_for_node(str(to_node), to_port), palette_pending_connection)


func _open_palette(graph_position: Vector2, context_type: String, pending_connection: Dictionary) -> void:
	palette_position = graph_position
	palette_context_type = context_type
	palette_pending_connection = pending_connection
	palette_search.text = ""
	_build_palette_items("")
	_draw_palette("")
	var screen_pos := Vector2i(graph.global_position + (graph_position - graph.scroll_offset) * graph.zoom)
	palette_popup.popup(Rect2i(screen_pos, Vector2i(620, 650)))
	palette_search.grab_focus()


func _show_callback_palette() -> void:
	palette_position = graph.scroll_offset + Vector2(140, 140)
	palette_context_type = "callback"
	palette_pending_connection = {}
	palette_search.text = ""
	_build_palette_items("")
	_draw_palette("")
	palette_popup.popup_centered(Vector2i(620, 650))
	palette_search.grab_focus()


func _build_palette_items(filter_text: String) -> void:
	palette_items.clear()

	if palette_context_type == "callback":
		var existing := {}
		for function_data in parsed.get("functions", []):
			existing[str(function_data.get("name", ""))] = true
		for callback_name in Parser.lifecycle_names():
			if not existing.has(str(callback_name)):
				_add_palette_item("Lifecycle", str(callback_name), "Add Godot callback", {"type": "callback", "name": str(callback_name)})
		return

	_add_palette_item("Core", "Code Statement", "Raw GDScript fallback.", {"type": "code"})
	_add_palette_item("Core", "Return", "return value", {"type": "return"})
	_add_palette_item("Core", "Math", "Configurable math node.", {"type": "math"})
	_add_palette_item("Core/Literals", "Text Literal", "Direct text value, writes \"...\".", {"type": "literal", "value": "\"\"", "value_type": "String"})
	_add_palette_item("Core/Literals", "Int", "Integer literal with editable value.", {"type": "literal", "value": "0", "value_type": "int"})
	_add_palette_item("Core/Literals", "Float", "Float literal with editable value.", {"type": "literal", "value": "0.0", "value_type": "float"})
	_add_palette_item("Core/Literals", "Bool", "Boolean literal with editable value.", {"type": "literal", "value": "true", "value_type": "bool"})
	for global_item in ClassDBStore.search_global_methods(filter_text, 120):
		var method_data: Dictionary = global_item.get("method_data", {}) as Dictionary
		_add_palette_item(str(global_item.get("category", "Global")), str(global_item.get("title", "function")), str(global_item.get("description", "")), {"type": "builtin", "name": str(global_item.get("name", "function")), "method_data": method_data})

	for variable_data in parsed.get("variables", []):
		_add_palette_item("Script/Variables", str(variable_data.get("name", "var")), "%s: %s" % [str(variable_data.get("name", "")), str(variable_data.get("type", "Variant"))], {"type": "variable", "data": variable_data})

	if focused_function_id != "":
		var local_maps: Dictionary = parsed.get("local_maps", {})
		var local_map: Dictionary = local_maps.get(focused_function_id, {})
		for local_name in local_map.keys():
			_add_palette_item("Script/Locals", str(local_name), "%s: %s" % [str(local_name), str(local_map[local_name].get("type", "Variant"))], {"type": "variable", "data": local_map[local_name], "local": true})

	for function_data in parsed.get("functions", []):
		_add_palette_item("Script/Functions", str(function_data.get("name", "function")), NodeFactory.function_signature(function_data), {"type": "script_call", "data": function_data})

	var method_type := palette_context_type
	if method_type == "" or method_type == "exec" or method_type == "Variant":
		method_type = str(parsed.get("extends", "Node"))

	if ClassDB.class_exists(method_type):
		for item in ClassDBStore.get_methods_for_type(method_type, filter_text, 140):
			_add_palette_item("Godot/%s/%s" % [method_type, str(item.get("category", "Methods"))], str(item.get("title", "")), str(item.get("description", "")), {"type": "method", "target_type": method_type, "method_data": item.get("method_data", {})})
	elif filter_text.strip_edges().length() >= 2:
		for item in ClassDBStore.search_common_methods(filter_text, 140):
			_add_palette_item("Godot/%s/%s" % [str(item.get("class", "Object")), str(item.get("category", "Methods"))], "%s.%s" % [str(item.get("class", "Object")), str(item.get("title", ""))], str(item.get("description", "")), {"type": "method", "target_type": str(item.get("class", "Object")), "method_data": item.get("method_data", {})})


func _add_palette_item(category: String, title: String, description: String, data: Dictionary) -> void:
	palette_items.append({"category": category, "title": title, "description": description, "data": data})


func _filter_palette(text: String) -> void:
	_build_palette_items(text)
	_draw_palette(text)


func _draw_palette(filter_text: String) -> void:
	palette_tree.clear()
	var root := palette_tree.create_item()
	var categories := {}
	var search := filter_text.to_lower().strip_edges()
	for item in palette_items:
		var haystack := (str(item.get("category", "")) + " " + str(item.get("title", "")) + " " + str(item.get("description", ""))).to_lower()
		if search != "" and not ClassDBStore.matches_tokens(haystack, search):
			continue
		var parent := _category_item(root, categories, str(item.get("category", "Other")))
		var tree_item := palette_tree.create_item(parent)
		tree_item.set_text(0, str(item.get("title", "")))
		tree_item.set_metadata(0, item)


func _category_item(root: TreeItem, categories: Dictionary, path: String) -> TreeItem:
	if categories.has(path):
		return categories[path]
	var current := ""
	var parent := root
	for part in path.split("/", false):
		current = str(part) if current == "" else current + "/" + str(part)
		if categories.has(current):
			parent = categories[current]
		else:
			var item := palette_tree.create_item(parent)
			item.set_text(0, str(part))
			item.collapsed = false
			categories[current] = item
			parent = item
	return parent


func _on_palette_selected() -> void:
	var item := palette_tree.get_selected()
	if item == null:
		return
	var metadata = item.get_metadata(0)
	if typeof(metadata) == TYPE_DICTIONARY:
		palette_info.text = "[b]%s[/b]\n%s\n%s" % [str(metadata.get("title", "")), str(metadata.get("category", "")), str(metadata.get("description", ""))]


func _on_palette_activated() -> void:
	_add_selected_palette()


func _add_selected_palette() -> void:
	var item := palette_tree.get_selected()
	if item == null:
		return
	var metadata = item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	_add_node_from_palette_item(metadata)
	palette_popup.hide()


func _add_node_from_palette_item(item: Dictionary) -> void:
	var data: Dictionary = item.get("data", {})
	var item_type := str(data.get("type", ""))

	if item_type == "callback":
		_add_callback(str(data.get("name", "")))
		return

	var node: GraphNode = null
	match item_type:
		"code": node = NodeFactory.make_statement_node({"id": "manual_%s" % randi(), "text": "pass"}, palette_position)
		"return": node = NodeFactory.make_return_node({"id": "manual_%s" % randi(), "value_text": ""}, palette_position)
		"math": node = NodeFactory.make_math_node(palette_position)
		"literal": node = NodeFactory.make_literal_node(str(data.get("value", "0")), palette_position, str(data.get("value_type", "Variant")))
		"builtin":
			var builtin_data: Dictionary = data.get("method_data", ClassDBStore.get_global_method_data(str(data.get("name", "print")))) as Dictionary
			node = NodeFactory.make_builtin_call_node(str(data.get("name", "print")), palette_position, _palette_wants_exec_node(), 1, [], builtin_data)
		"variable": node = NodeFactory.make_variable_node(data.get("data", {}), palette_position, bool(data.get("local", false)))
		"script_call": node = NodeFactory.make_script_call_node(data.get("data", {}), palette_position, "", [], _palette_wants_exec_node())
		"method":
			var selected_method_data: Dictionary = data.get("method_data", {}) as Dictionary
			node = NodeFactory.make_method_node(str(data.get("target_type", "Object")), selected_method_data, palette_position, "", "", _palette_wants_exec_node())

	if node == null:
		return
	_add_graph_node(node)
	_auto_connect_new_node(node)
	_show_node_info(node)
	_mark_layout_dirty()


func _palette_wants_exec_node() -> bool:
	if palette_pending_connection.is_empty():
		return true
	var mode := str(palette_pending_connection.get("mode", ""))
	if mode == "to":
		return _input_type_for_node(str(palette_pending_connection.get("to_node", "")), int(palette_pending_connection.get("to_port", 0))) == "exec"
	if mode == "from":
		return _output_type_for_node(str(palette_pending_connection.get("from_node", "")), int(palette_pending_connection.get("from_port", 0))) == "exec"
	return true


func _auto_connect_new_node(node: GraphNode) -> void:
	if palette_pending_connection.is_empty():
		return
	var mode := str(palette_pending_connection.get("mode", ""))
	if mode == "from":
		var from_node := str(palette_pending_connection.get("from_node", ""))
		var from_port := int(palette_pending_connection.get("from_port", 0))
		var wanted := _output_type_for_node(from_node, from_port)
		var to_port := _best_input_port(node, wanted)
		graph.connect_node(StringName(from_node), from_port, StringName(node.name), to_port)
	elif mode == "to":
		var to_node := str(palette_pending_connection.get("to_node", ""))
		var to_port := int(palette_pending_connection.get("to_port", 0))
		var wanted := _input_type_for_node(to_node, to_port)
		var from_port := _best_output_port(node, wanted)
		graph.connect_node(StringName(node.name), from_port, StringName(to_node), to_port)
	palette_pending_connection = {}

	_sync_connected_input_fields()


func _best_input_port(node: GraphNode, wanted_type: String) -> int:
	var ports: Array = node.get_meta("input_ports", [])
	for i in range(ports.size()):
		if typeof(ports[i]) == TYPE_DICTIONARY and str(ports[i].get("type", "")) == wanted_type:
			return i
	for i in range(ports.size()):
		if typeof(ports[i]) == TYPE_DICTIONARY and str(ports[i].get("type", "")) != "exec":
			return i
	return 0


func _best_output_port(node: GraphNode, wanted_type: String) -> int:
	var ports: Array = node.get_meta("output_ports", [])
	for i in range(ports.size()):
		if typeof(ports[i]) == TYPE_DICTIONARY and str(ports[i].get("type", "")) == wanted_type:
			return i
	for i in range(ports.size()):
		if typeof(ports[i]) == TYPE_DICTIONARY and str(ports[i].get("type", "")) != "exec":
			return i
	return 0


func _on_symbol_selected() -> void:
	var item := symbol_tree.get_selected()
	if item == null:
		return
	var metadata = item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	_clear_actions()
	var kind := str(metadata.get("kind", ""))
	if kind == "function":
		var function_data: Dictionary = metadata.get("data", {})
		info_label.text = "[b]%s()[/b]\n%s\nLine %s" % [str(function_data.get("name", "")), NodeFactory.function_signature(function_data), int(function_data.get("line_start", 1))]
		_add_action_button("Open", func() -> void: _open_script_at_line(int(function_data.get("line_start", 1))))
		_add_action_button("Graph", func() -> void: _expand_function(str(function_data.get("id", ""))))
	elif kind == "variable":
		var variable_data: Dictionary = metadata.get("data", {})
		info_label.text = "[b]%s[/b]\n%s · %s\nLine %s" % [str(variable_data.get("name", "")), str(variable_data.get("type", "Variant")), str(variable_data.get("kind", "member")), int(variable_data.get("line", 0))]
	elif kind == "callback":
		var callback_name := str(metadata.get("name", ""))
		info_label.text = "[b]%s()[/b]\nAdd callback" % callback_name
		_add_action_button("Add", func() -> void: _add_callback(callback_name))


func _on_symbol_activated() -> void:
	var item := symbol_tree.get_selected()
	if item == null:
		return
	var metadata = item.get_metadata(0)
	if typeof(metadata) != TYPE_DICTIONARY:
		return
	var kind := str(metadata.get("kind", ""))
	if kind == "function":
		_expand_function(str((metadata.get("data", {}) as Dictionary).get("id", "")))
	elif kind == "callback":
		_add_callback(str(metadata.get("name", "")))


func _group_selected_nodes() -> void:
	if graph == null:
		return
	var selected := _selected_graph_nodes()
	if selected.size() < 2:
		_set_status("Select at least two nodes, then use Group or Ctrl+G.")
		return
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var names: Array = []
	for node in selected:
		if str(node.get_meta("gdvl_type", "")) in ["entry", "function", "group"]:
			continue
		names.append(str(node.name))
		min_pos.x = min(min_pos.x, node.position_offset.x)
		min_pos.y = min(min_pos.y, node.position_offset.y)
		max_pos.x = max(max_pos.x, node.position_offset.x + max(node.size.x, node.custom_minimum_size.x))
		max_pos.y = max(max_pos.y, node.position_offset.y + max(node.size.y, node.custom_minimum_size.y))
	if names.size() < 2:
		return
	var group_pos := min_pos - Vector2(28, 42)
	var group_size := (max_pos - min_pos) + Vector2(56, 84)
	var group_node := NodeFactory.make_group_node("Group", group_pos, group_size, names)
	_add_graph_node(group_node)
	_show_node_info(group_node)
	_mark_layout_dirty()


func _selected_graph_nodes() -> Array:
	var result: Array = []
	if graph.has_method("get_selected_nodes"):
		var selected_names = graph.call("get_selected_nodes")
		for selected_name in selected_names:
			var node = graph.get_node_or_null(NodePath(str(selected_name)))
			if node is GraphNode:
				result.append(node)
		return result
	for child in graph.get_children():
		if child is GraphNode:
			var is_selected := false
			if child.has_method("is_selected"):
				is_selected = bool(child.call("is_selected"))
			else:
				var selected_value = child.get("selected")
				if selected_value != null:
					is_selected = bool(selected_value)
			if is_selected:
				result.append(child)
	return result


func _connect_node_edit_signals(node: GraphNode) -> void:
	for child in node.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is LineEdit:
					var edit := sub as LineEdit
					if not edit.text_changed.is_connected(_on_node_edit_text_changed):
						edit.text_changed.connect(_on_node_edit_text_changed)


func _on_node_edit_text_changed(_text: String) -> void:
	# Keep value fields in sync with graph connections without writing code.
	_sync_connected_input_fields()


func _sync_connected_input_fields() -> void:
	if graph == null:
		return
	var connected_inputs := {}
	for connection in graph.get_connection_list():
		if typeof(connection) != TYPE_DICTIONARY:
			continue
		connected_inputs["%s:%s" % [str(connection.get("to_node", "")), int(connection.get("to_port", -1))]] = true
	for child in graph.get_children():
		if not (child is GraphNode):
			continue
		var node := child as GraphNode
		for row in node.get_children():
			if row is HBoxContainer:
				for sub in row.get_children():
					if sub is LineEdit:
						var edit := sub as LineEdit
						var port := _port_index_from_input_name(edit.name)
						if port < 0:
							continue
						var is_connected := connected_inputs.has("%s:%s" % [str(node.name), port])
						edit.visible = not is_connected
						edit.editable = not is_connected
						edit.tooltip_text = "Input ist verbunden. Der verbundene Node gewinnt." if is_connected else ""


func _port_index_from_input_name(input_name: String) -> int:
	var text := str(input_name)
	var prefix := "gdvl_input_"
	if not text.begins_with(prefix):
		return -1
	return int(text.substr(prefix.length()))


func _restore_groups() -> void:
	for group_data in MetaStore.get_groups(meta, current_view):
		if typeof(group_data) != TYPE_DICTIONARY:
			continue
		var name_text := str(group_data.get("name", ""))
		if name_text == "" or graph.get_node_or_null(NodePath(name_text)) != null:
			continue
		var pos := Vector2(float(group_data.get("x", 0)), float(group_data.get("y", 0)))
		var size_hint := Vector2(float(group_data.get("w", 260)), float(group_data.get("h", 140)))
		var group_node := NodeFactory.make_group_node(str(group_data.get("title", "Group")), pos, size_hint, group_data.get("grouped_nodes", []))
		group_node.name = name_text
		_add_graph_node(group_node)


func _show_node_info(node: GraphNode) -> void:
	selected_node_name = node.name
	_clear_actions()
	var node_type := str(node.get_meta("gdvl_type", ""))
	info_label.text = "[b]%s[/b]\n%s" % [node.title, _short_node_info(node)]

	if node_type == "function":
		var function_id := str(node.get_meta("function_id", ""))
		_add_action_button("Graph", func() -> void: _expand_function(function_id))
		_add_action_button("Open", func() -> void: _open_script_at_line(int(node.get_meta("line", 1))))
	elif node_type in ["statement", "set_property", "assignment", "local_assign", "script_call", "script_value_call", "method_call", "builtin", "branch", "return"]:
		_add_action_button("Open", func() -> void: _open_script_at_line(int(node.get_meta("line", 1))))
	elif node_type == "group":
		_add_action_button("Ungroup", func() -> void:
			node.queue_free()
			_mark_layout_dirty()
		)


func _short_node_info(node: GraphNode) -> String:
	var node_type := str(node.get_meta("gdvl_type", ""))
	match node_type:
		"function": return str(node.get_meta("signature", ""))
		"variable": return "%s: %s" % [str(node.get_meta("variable_name", "")), str(node.get_meta("value_type", "Variant"))]
		"set_property": return "%s.%s" % [str(node.get_meta("target_expr", "")), str(node.get_meta("property_name", ""))]
		"branch": return "if " + str(node.get_meta("condition", "true"))
		"return": return "return " + str(node.get_meta("value_text", ""))
		"statement": return str(node.get_meta("statement_text", ""))
		"method_call": return "%s.%s" % [str(node.get_meta("target_expression", "")), str(node.get_meta("method_name", ""))]
		"script_call": return str(node.get_meta("function_name", "")) + "()"
		"script_value_call": return str(node.get_meta("function_name", "")) + "() result"
		"builtin": return str(node.get_meta("builtin_name", "")) + "()"
		"group": return "Visual group. Does not write code by itself."
	return node_type


func _clear_actions() -> void:
	for child in action_row.get_children():
		child.queue_free()


func _add_action_button(text: String, callable: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callable)
	action_row.add_child(button)


func _show_overview() -> void:
	flush_layout()
	current_view = "overview"
	focused_function_id = ""
	_rebuild_all()


func _expand_function(function_id: String) -> void:
	if _function_by_id(function_id).is_empty():
		return
	flush_layout()
	focused_function_id = function_id
	current_view = "func__" + NodeFactory.sanitize_id(function_id)
	_rebuild_all()


func _get_editable_script_text() -> String:
	if editor_interface == null or current_script_path == "":
		return ""

	var script_editor = editor_interface.get_script_editor()
	if script_editor != null:
		var open_scripts: Array = script_editor.get_open_scripts()
		var open_editors: Array = []
		if script_editor.has_method("get_open_script_editors"):
			open_editors = script_editor.get_open_script_editors()

		for index in range(open_scripts.size()):
			var open_script = open_scripts[index]
			if not (open_script is Script) or str(open_script.resource_path) != current_script_path:
				continue

			if index < open_editors.size():
				var script_base = open_editors[index]
				if script_base != null and script_base.has_method("get_base_editor"):
					var base_editor = script_base.call("get_base_editor")
					if base_editor is TextEdit:
						return str((base_editor as TextEdit).text)

			var source_code = open_script.get("source_code")
			if typeof(source_code) == TYPE_STRING and str(source_code) != "":
				return str(source_code)

	return _read_text(current_script_path)


func _apply_script_preview(text: String, line: int) -> bool:
	if editor_interface == null or current_script_path == "" or text == "":
		return false

	var script = _find_open_script_resource()
	if script == null:
		script = ResourceLoader.load(current_script_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if not (script is Script):
		return false

	(script as Script).set("source_code", text)
	editor_interface.edit_script(script, max(line, 1), 0, true)
	_switch_to_script_screen()
	call_deferred("_apply_text_to_open_script_editor", text, line)
	return true


func _find_open_script_resource() -> Script:
	if editor_interface == null:
		return null
	var script_editor = editor_interface.get_script_editor()
	if script_editor == null:
		return null
	for open_script in script_editor.get_open_scripts():
		if open_script is Script and str(open_script.resource_path) == current_script_path:
			return open_script
	return null


func _apply_text_to_open_script_editor(text: String, line: int) -> void:
	if editor_interface == null:
		return
	var script_editor = editor_interface.get_script_editor()
	if script_editor == null:
		return

	var open_scripts: Array = script_editor.get_open_scripts()
	var open_editors: Array = []
	if script_editor.has_method("get_open_script_editors"):
		open_editors = script_editor.get_open_script_editors()

	for index in range(open_scripts.size()):
		var open_script = open_scripts[index]
		if not (open_script is Script) or str(open_script.resource_path) != current_script_path:
			continue

		open_script.set("source_code", text)
		if index < open_editors.size():
			var script_base = open_editors[index]
			if script_base != null and script_base.has_method("get_base_editor"):
				var base_editor = script_base.call("get_base_editor")
				if base_editor is TextEdit:
					var text_edit := base_editor as TextEdit
					text_edit.text = text
					text_edit.set_caret_line(clamp(line - 1, 0, max(text_edit.get_line_count() - 1, 0)))
					text_edit.set_caret_column(0)
					text_edit.grab_focus()
					text_edit.queue_redraw()
		if script_editor.has_method("goto_line"):
			script_editor.goto_line(max(line - 1, 0))
		break


func _switch_to_script_screen() -> void:
	if editor_interface != null and editor_interface.has_method("set_main_screen_editor"):
		editor_interface.call("set_main_screen_editor", "Script")


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _open_script_at_line(line: int) -> void:
	if editor_interface == null or current_script_path == "":
		return
	var script = ResourceLoader.load(current_script_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if script is Script:
		editor_interface.edit_script(script, max(line, 1), 0, true)
		if editor_interface.has_method("set_main_screen_editor"):
			editor_interface.call("set_main_screen_editor", "Script")


func _write_function() -> void:
	if current_view == "overview" or focused_function_id == "" or writer == null:
		return

	var function_data := _function_by_id(focused_function_id)
	if function_data.is_empty():
		return

	var body: PackedStringArray = writer.generate_function_body(graph)
	var original_text := _get_editable_script_text()
	var preview_text: String = writer.build_replaced_function_text(original_text, function_data, body)
	var line_start := int(function_data.get("line_start", 1))
	if preview_text != "" and writer.has_method("find_function_line"):
		line_start = int(writer.find_function_line(preview_text, function_data))

	if preview_text != "" and _apply_script_preview(preview_text, line_start):
		_set_status("Preview written to Script tab: " + str(function_data.get("name", "function")) + ". Save the script to apply it.")
	else:
		_set_status("Could not write function preview.")


func _add_callback(callback_name: String) -> void:
	if current_script_path == "" or writer == null or callback_name == "":
		return

	var original_text := _get_editable_script_text()
	var preview_text: String = writer.build_appended_callback_text(original_text, Parser.callback_template(callback_name))
	if preview_text != "" and _apply_script_preview(preview_text, 1):
		_set_status("Callback preview added: " + callback_name + ". Save the script to apply it.")
	else:
		_set_status("Could not add callback preview.")


func flush_layout() -> void:
	if current_script_path == "" or not layout_dirty or graph == null:
		return
	_capture_current_layout()
	if MetaStore.save_meta(current_script_path, meta):
		layout_dirty = false


func _capture_current_layout() -> void:
	var groups: Array = []
	for child in graph.get_children():
		if child is GraphNode:
			MetaStore.set_node_position(meta, current_view, child.name, child.position_offset)
			if str(child.get_meta("gdvl_type", "")) == "group":
				groups.append({
					"name": str(child.name),
					"title": str(child.get_meta("title_text", "Group")),
					"x": child.position_offset.x,
					"y": child.position_offset.y,
					"w": max(child.size.x, child.custom_minimum_size.x),
					"h": max(child.size.y, child.custom_minimum_size.y),
					"grouped_nodes": child.get_meta("grouped_nodes", [])
				})
	MetaStore.set_groups(meta, current_view, groups)
	if current_view != "overview":
		MetaStore.set_connections(meta, current_view, graph.get_connection_list())
	MetaStore.set_camera(meta, current_view, graph.scroll_offset, graph.zoom)


func _mark_layout_dirty() -> void:
	if not suppress_events:
		layout_dirty = true


func _on_delete_nodes_request(nodes) -> void:
	for node_name in nodes:
		var node = graph.get_node_or_null(NodePath(str(node_name)))
		if node == null:
			continue
		if str(node.get_meta("gdvl_type", "")) in ["function", "entry"]:
			continue
		_disconnect_all_for_node(str(node_name))
		node.queue_free()
	_mark_layout_dirty()


func _disconnect_all_for_node(node_name: String) -> void:
	for connection in graph.get_connection_list():
		if str(connection.get("from_node", "")) == node_name or str(connection.get("to_node", "")) == node_name:
			graph.disconnect_node(StringName(str(connection.get("from_node", ""))), int(connection.get("from_port", 0)), StringName(str(connection.get("to_node", ""))), int(connection.get("to_port", 0)))


func _output_type_for_node(node_name: String, port: int) -> String:
	var node = graph.get_node_or_null(NodePath(node_name))
	if node == null:
		return ""
	var ports: Array = node.get_meta("output_ports", [])
	if port >= 0 and port < ports.size() and typeof(ports[port]) == TYPE_DICTIONARY:
		return str(ports[port].get("type", ""))
	return ""


func _input_type_for_node(node_name: String, port: int) -> String:
	var node = graph.get_node_or_null(NodePath(node_name))
	if node == null:
		return ""
	var ports: Array = node.get_meta("input_ports", [])
	if port >= 0 and port < ports.size() and typeof(ports[port]) == TYPE_DICTIONARY:
		return str(ports[port].get("type", ""))
	return ""


func _function_by_id(function_id: String) -> Dictionary:
	for function_data in parsed.get("functions", []):
		if str(function_data.get("id", "")) == function_id:
			return function_data
	return {}


func _function_by_name(function_name: String) -> Dictionary:
	for function_data in parsed.get("functions", []):
		if str(function_data.get("name", "")) == function_name:
			return function_data
	return {}


func _set_status(text: String) -> void:
	status_label.text = text
