# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4.x GDScript project for `心灵视界 Mindscape`. Open `project.godot` as the project root; the main scene is `scenes/Main.tscn`.

- `scripts/` contains gameplay logic. Key files include `main.gd`, `player.gd`, `world.gd`, `game_data.gd`, puzzle scripts, and autoloads `profile_manager.gd` and `audio_manager.gd`.
- `scenes/` stores reusable Godot scenes.
- `map/` contains level scenes, tilesets, and map resources.
- `assets/` holds source game assets such as character SVGs and UI icons.
- `.godot/` is Godot editor/cache state; avoid hand-editing it unless a tracked file change is intentional.

## Build, Test, and Development Commands

- `godot --path .` launches the project from this directory when the Godot CLI is installed.
- `godot --path . --editor` opens the editor at this project.
- In the Godot editor, press `F5` to run `scenes/Main.tscn`.

No export presets or scripted build pipeline are currently present. Configure exports through Godot before adding release commands.

## Coding Style & Naming Conventions

Use idiomatic GDScript with tabs for indentation, `snake_case` for variables/functions/files, and `PascalCase` only for classes or named Godot types. Keep puzzle-specific behavior in `scripts/puzzle_*.gd`; shared state and constants belong in `game_data.gd` or the relevant autoload. Prefer Godot input actions defined in `project.godot` over hard-coded key checks.

## Testing Guidelines

There is no automated test framework in this repository yet. For changes, manually run the game and verify movement, interaction (`E`), special ability (`F`), view switching (`Q`, `R`, `TAB`), save/profile behavior, and any touched puzzle path. If tests are added later, place them in a clear `tests/` directory and document the runner command here.

## Commit & Pull Request Guidelines

Recent commits use short, informal summaries, often in Chinese, such as `关卡` or `改了点`. Keep commits concise but make them more descriptive when possible, for example `修复灯板谜题交互`. PRs should include a short change summary, manual test notes, screenshots or clips for visual/gameplay changes, and any affected scenes or scripts.

## Version Control Workflow

Treat the worktree as user-owned until changes have been reviewed and intentionally staged. Always inspect `git status --short` before Git operations; stage project files by path with `git add <paths>`, never with a blanket `git add .` in this Godot repository.

- Do not commit `.godot/`, `.DS_Store`, shader caches, editor layouts, or generated import cache files. Commit source assets, `.import` sidecars only when the project needs them, gameplay scripts, tests, and documentation deliberately.
- Before integrating remote work, run `git fetch origin main` and compare with `git rev-list --left-right --count HEAD...origin/main`. Commit or otherwise protect local work before a merge; do not pull into a dirty worktree.
- Use descriptive, focused commits such as `feat: add NPC sprite atlas` or `fix: align character feet to terrain`. Review `git diff --staged` and run the applicable Godot checks before each commit.
- Merge with `git merge origin/main`. If conflicts occur, list them with `git diff --name-only --diff-filter=U`, explain the local and remote intent, and ask the user whether each conflict should keep local, remote, or a combined resolution. Do not guess or use `git checkout --theirs/--ours` without that decision.
- After resolving conflicts, re-run checks, create the merge commit if needed, and push with `git push origin main`. Never use `git reset --hard`, force-push, or discard local work unless the user explicitly requests it.

## Repository Hygiene

Do not commit `.DS_Store`, temporary Godot cache churn, or unrelated editor layout changes. Review changes to `project.godot` carefully because it controls autoloads, inputs, display settings, and the main scene.

## Recommended Agent Skills

Before non-trivial work, check for an applicable skill instead of improvising. Use `using-agent-skills` as the routing reminder.

- `planning-and-task-breakdown`: use for multi-step gameplay, puzzle, world, save/profile, or asset integration changes before implementation.
- `debugging-and-error-recovery`: use when Godot behavior is wrong, a bug persists after a first fix, or runtime output contradicts the expected result. Reproduce, localize, fix, then verify.
- `test-driven-development`: use for behavior changes where a script-level or headless Godot check can prove the result. If no automated test exists, document the exact manual checks.
- `incremental-implementation`: use when touching more than one file; keep slices small and verify after each slice.
- `code-review-and-quality`: use before considering any change done, especially after AI-generated code or asset-processing scripts.
- `doubt-driven-development`: use when changing unfamiliar logic, collision, save data, puzzle progression, or anything where a confident mistake would be expensive.
- `documentation-and-adrs`: use when adding project conventions, workflow notes, or decisions that future contributors need to understand.
- `imagegen`: use for new bitmap game assets, sprites, portraits, or visual variants; always inspect and, if needed, post-process generated assets before wiring them into the game.
- `git-workflow-and-versioning`: use for pulls, commits, conflict handling, and protecting user changes in this dirty Godot working tree.

Outside Planning Mode, still ask the user when blocked by product intent or tradeoffs: unclear desired behavior, multiple plausible fixes, repeated failed attempts, or changes that would discard or overwrite local work. Ask a short concrete question, then continue once the answer is clear.
