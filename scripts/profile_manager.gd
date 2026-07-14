extends Node

const SAVE_VERSION: int = 1
const STORAGE_PATH: String = "user://mindscape_profiles.json"
const TEST_STORAGE_PATH: String = "user://mindscape_profiles_test.json"
const TOTAL_COLLECTIBLES: float = 27.0

var profiles: Array = []
var current_profile_id: String = ""
var pending_cloud_adapter: Object = null
var storage_path: String = STORAGE_PATH

func _ready() -> void:
	for argument in OS.get_cmdline_args():
		if str(argument).contains("tests/"):
			storage_path = TEST_STORAGE_PATH
			break
	load_profiles()
	if profiles.is_empty():
		create_profile("旅行者", "sun")

func load_profiles() -> void:
	if not FileAccess.file_exists(storage_path):
		profiles = []
		return
	var file := FileAccess.open(storage_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		profiles = []
		return
	profiles = _restore_vectors(parsed.get("profiles", [])) as Array
	current_profile_id = str(parsed.get("current_profile_id", ""))
	var migrated := false
	for profile in profiles:
		var state: Dictionary = profile.get("state", {}) as Dictionary
		if GameData.migrate_state(state):
			profile["state"] = state
			profile["stats"] = compute_stats(state)
			migrated = true
	if migrated:
		flush()

func flush() -> void:
	var file := FileAccess.open(storage_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"current_profile_id": current_profile_id,
		"profiles": _pack_vectors(profiles),
	}, "\t"))

func create_profile(display_name: String, avatar: String) -> Dictionary:
	var id: String = "%s_%d" % [display_name.to_lower().replace(" ", "_"), Time.get_unix_time_from_system()]
	var state: Dictionary = GameData.default_state()
	var profile: Dictionary = {
		"id": id,
		"display_name": display_name,
		"avatar": avatar,
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system(),
		"state": state,
		"stats": compute_stats(state),
	}
	profiles.append(profile)
	current_profile_id = id
	flush()
	return profile

func list_profiles() -> Array:
	return profiles

func get_current_profile() -> Dictionary:
	for profile in profiles:
		if profile.get("id", "") == current_profile_id:
			return profile
	if not profiles.is_empty():
		current_profile_id = profiles[0].get("id", "")
		return profiles[0]
	return create_profile("旅行者", "sun")

func set_current_profile(id: String) -> void:
	for profile in profiles:
		if profile.get("id", "") == id:
			current_profile_id = id
			flush()
			return

func save_state(state: Dictionary) -> void:
	for i in range(profiles.size()):
		if profiles[i].get("id", "") == current_profile_id:
			profiles[i]["state"] = state.duplicate(true)
			profiles[i]["stats"] = compute_stats(state)
			profiles[i]["updated_at"] = Time.get_datetime_string_from_system()
			flush()
			if pending_cloud_adapter != null and pending_cloud_adapter.has_method("queue_upload"):
				pending_cloud_adapter.queue_upload(profiles[i])
			return

func reset_current_profile() -> Dictionary:
	var profile: Dictionary = get_current_profile()
	profile["state"] = GameData.default_state()
	profile["stats"] = compute_stats(profile["state"])
	profile["updated_at"] = Time.get_datetime_string_from_system()
	flush()
	return profile

func is_current_profile_debug() -> bool:
	var profile := get_current_profile()
	return bool(profile.get("is_debug_profile", false)) or bool((profile.get("state", {}) as Dictionary).get("is_debug_profile", false))

static func make_debug_clone(source_profile: Dictionary, source_state: Dictionary = {}) -> Dictionary:
	var source_id := str(source_profile.get("id", "profile"))
	var cloned_state: Dictionary = source_state.duplicate(true) if not source_state.is_empty() else (source_profile.get("state", GameData.default_state()) as Dictionary).duplicate(true)
	cloned_state["is_debug_profile"] = true
	cloned_state["debug_preset"] = ""
	cloned_state["debug_spawn_target"] = ""
	var source_name := str(source_profile.get("display_name", "旅行者")).trim_suffix(" [TEST]")
	return {
		"id": "debug_%s_%d" % [source_id, Time.get_ticks_msec()],
		"display_name": "%s [TEST]" % source_name,
		"avatar": source_profile.get("avatar", "sun"),
		"created_at": Time.get_datetime_string_from_system(),
		"updated_at": Time.get_datetime_string_from_system(),
		"is_debug_profile": true,
		"debug_source_profile_id": source_id,
		"state": cloned_state,
		"stats": {},
	}

func create_debug_clone(source_state: Dictionary = {}) -> Dictionary:
	var source := get_current_profile()
	if is_current_profile_debug():
		return source
	var clone := make_debug_clone(source, source_state)
	clone["stats"] = compute_stats(clone["state"] as Dictionary)
	profiles.append(clone)
	current_profile_id = str(clone["id"])
	flush()
	return clone

func compute_stats(state: Dictionary) -> Dictionary:
	var fragment_list: Array = state.get("fragments", []) as Array
	var collectible_list: Array = state.get("collectibles", []) as Array
	var view_list: Array = state.get("unlocked_views", []) as Array
	var album_list: Array = state.get("album", []) as Array
	var fragments: int = fragment_list.size()
	var collectibles: int = collectible_list.size()
	var extra_views: int = maxi(view_list.size() - 1, 0)
	var finished: bool = bool(state.get("finished", false))
	var completion: int = int(round(((fragments / 8.0) * 45.0) + ((collectibles / TOTAL_COLLECTIBLES) * 25.0) + ((extra_views / 4.0) * 20.0) + (10.0 if finished else 0.0)))
	return {
		"completion": clamp(completion, 0, 100),
		"play_time": state.get("play_time", 0.0),
		"album_count": album_list.size(),
		"fragment_count": fragments,
		"collectible_count": collectibles,
	}

func register_cloud_adapter(adapter: Object) -> void:
	pending_cloud_adapter = adapter

func export_local_snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"current_profile_id": current_profile_id,
		"profiles": profiles.duplicate(true),
	}

func _pack_vectors(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var vector_value: Vector2 = value
			return {"__vector2": [vector_value.x, vector_value.y]}
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key in value.keys():
				out[key] = _pack_vectors(value[key])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_pack_vectors(item))
			return out
		_:
			return value

func _restore_vectors(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			if value.has("__vector2"):
				var pair: Array = value["__vector2"]
				return Vector2(float(pair[0]), float(pair[1]))
			var out: Dictionary = {}
			for key in value.keys():
				out[key] = _restore_vectors(value[key])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for item in value:
				out.append(_restore_vectors(item))
			return out
		_:
			return value
