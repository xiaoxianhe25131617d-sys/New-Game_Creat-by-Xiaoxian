extends Node

var failures: Array[String] = []

func _ready() -> void:
	if not ProfileManager.has_method("has_accepted_agreement") or not ProfileManager.has_method("accept_current_agreement"):
		_fail_and_quit("ProfileManager must expose versioned agreement helpers")
		return
	_test_legacy_profile_requires_agreement()
	_test_current_version_is_recognized()
	_test_acceptance_is_scoped_to_current_profile()
	if failures.is_empty():
		print("PASS: profile agreement contract")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _test_legacy_profile_requires_agreement() -> void:
	var state := GameData.default_state()
	state["play_time"] = 321.0
	var legacy_profile := {"id": "legacy", "state": state}
	_expect(not ProfileManager.has_accepted_agreement(legacy_profile), "Legacy profiles must require agreement")
	_expect(float((legacy_profile["state"] as Dictionary).get("play_time", 0.0)) == 321.0, "Agreement checks must not mutate progress")

func _test_current_version_is_recognized() -> void:
	var accepted_profile := {
		"agreement_version": ProfileManager.AGREEMENT_VERSION,
		"agreement_accepted_at": "2026-07-15T12:00:00",
	}
	_expect(ProfileManager.has_accepted_agreement(accepted_profile), "Current agreement version with timestamp must be accepted")
	accepted_profile["agreement_version"] = "older-version"
	_expect(not ProfileManager.has_accepted_agreement(accepted_profile), "Outdated agreement versions must require confirmation")

func _test_acceptance_is_scoped_to_current_profile() -> void:
	var first := {
		"id": "first",
		"display_name": "第一位",
		"state": GameData.default_state(),
		"stats": {},
	}
	var second := {
		"id": "second",
		"display_name": "第二位",
		"state": GameData.default_state(),
		"stats": {},
	}
	ProfileManager.profiles = [first, second]
	ProfileManager.current_profile_id = "first"
	ProfileManager.accept_current_agreement()
	_expect(ProfileManager.has_accepted_agreement(ProfileManager.profiles[0] as Dictionary), "Current profile must record acceptance")
	_expect(not ProfileManager.has_accepted_agreement(ProfileManager.profiles[1] as Dictionary), "Other profiles must remain unaccepted")
	ProfileManager.reset_current_profile()
	_expect(ProfileManager.has_accepted_agreement(ProfileManager.get_current_profile()), "Resetting game progress must preserve agreement metadata")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _fail_and_quit(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
