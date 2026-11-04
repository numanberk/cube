#!/usr/bin/env python3
"""Claude Code hooks for Cube Idle: make sessions use the project subagents at the right moments.

Wired up in .claude/settings.json. One script, one sub-command per hook event:

  gate       PreToolUse (Bash): notes when a check (run_tests.sh, simulate.sh, screenshot.sh) starts, and
             blocks `git commit` until the CLAUDE.md finish checklist is done for the current change set:
             tests passed after the last code change, the balance bot ran after the last content.gd/game.gd
             change, screenshots were taken after the last UI change, and diff-reviewer reviewed every changed
             code file. A change set with no code (only docs/, .claude/agents/ and *.md) is never gated.
  record     PostToolUse (Bash, Agent/Task) and SubagentStop: notes which checks passed (dated by when they
             *started*, so edits made while one runs aren't counted as checked) and which agents finished.
             Hooks also fire for a subagent's own Bash calls, which is how test-runner's and
             balance-analyst's runs are seen. SubagentStop carries agent_type but not the agent's report, so
             any diff-reviewer stop counts as a review (even one cut off by a usage limit: re-run it then),
             and its file list is taken when it stops.
             Known misses (fail open): commits behind `time`/`sudo`/`if`/`{ }`, inside "$(...)", `git -P`.
  remind     PostToolUse (Edit/Write): once per session, says which agent a file change calls for
             (balance-analyst after content.gd/game.gd, screenshot-checker after UI files).
  aftercommit PostToolUse (Bash): after a commit that completes a roadmap phase, asks for a fun-designer pass.

State lives in .git/cube-workflow.json: per clone, never committed, empty in every new cloud session.
Escape hatch (only when the owner says so, or the gate is wrong): start the command with CUBE_SKIP_GATE=1,
and say why in the CHANGELOG.

Test by hand:  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | python3 tools/hooks/workflow.py gate
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Paths (relative to ROOT) by what they call for.
DOCS_ONLY = re.compile(r"^(docs/|\.claude/agents/)|\.md$")
BALANCE_FILES = ("scripts/data/content.gd", "scripts/autoload/game.gd")
VISUAL = re.compile(r"^(scenes/|ui/|scripts/ui/|assets/(icons|fonts|images)/)")
GENERATED = re.compile(r"\.(uid|import)$")
# `git [-C dir | -c k=v | --flag]... commit`, at the start of a command (after ; & | ( or a newline).
COMMIT_CMD = re.compile(r"(^|[;&|(\n])\s*(\w+=\S*\s+)*(\S*/)?git(\s+-[cC]\s+\S+|\s+--[\w-]+(=\S+)?)*\s+commit(?![-\w])")
CHECKS = {"tests": "run_tests.sh", "balance": "simulate.sh", "screens": "screenshot.sh"}
AGENTS = ("diff-reviewer", "balance-analyst", "screenshot-checker", "test-runner", "fun-designer")


# ---------------------------------------------------------------- helpers

def git(*args: str) -> str:
	try:
		out = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, timeout=20)
		return out.stdout.strip() if out.returncode == 0 else ""
	except (OSError, subprocess.SubprocessError):
		return ""


def state_path() -> str:
	git_dir = git("rev-parse", "--absolute-git-dir") or os.path.join(ROOT, ".git")
	return os.path.join(git_dir, "cube-workflow.json")


def load_state() -> dict:
	try:
		with open(state_path(), encoding="utf-8") as f:
			data = json.load(f)
			return data if isinstance(data, dict) else {}
	except (OSError, ValueError):
		return {}


def save_state(state: dict) -> None:
	path = state_path()
	tmp = "%s.%d.tmp" % (path, os.getpid())  # one temp file per process: hooks can run at the same time
	try:
		with open(tmp, "w", encoding="utf-8") as f:
			json.dump(state, f, indent=1, sort_keys=True)
		os.replace(tmp, path)
	except OSError:
		pass


def base() -> str:
	"""Where this change set starts: the merge-base with origin/main, else with local main, else HEAD."""
	for ref in ("origin/main", "main"):
		b = git("merge-base", "HEAD", ref)
		if b:
			return b
	return git("rev-parse", "HEAD") or "none"


def changed_files() -> list[str]:
	"""Changed paths, minus the .uid/.import files Godot writes during every check's import step
	(their source files are checked; counting them would make each passing run look stale)."""
	b = base()
	files: set[str] = set()
	if b != "none":
		files.update(f for f in git("diff", "--name-only", b).splitlines() if f)
	files.update(f for f in git("ls-files", "--others", "--exclude-standard").splitlines() if f)
	return sorted(f for f in files if not GENERATED.search(f))


def code_files(files: list[str]) -> list[str]:
	return [f for f in files if not DOCS_ONLY.search(f)]


def last_mtime(files: list[str]) -> float:
	"""Newest change among files. A deleted (or moved-away) file counts as changed when its folder last changed."""
	newest = 0.0
	for f in files:
		path = os.path.join(ROOT, f)
		while path and not os.path.exists(path) and os.path.dirname(path) != path:
			path = os.path.dirname(path)
		try:
			newest = max(newest, os.path.getmtime(path))
		except OSError:
			pass
	return newest


def text_of(value) -> str:
	"""Flattens a tool_response (string, dict or list of content blocks) to plain text."""
	if isinstance(value, str):
		return value
	if isinstance(value, dict):
		return "\n".join(text_of(v) for v in value.values())
	if isinstance(value, list):
		return "\n".join(text_of(v) for v in value)
	return ""


def is_commit(command: str) -> bool:
	"""True for a real `git commit`, not one that is only mentioned in quotes or in a heredoc body."""
	shell = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?([^\n]*)\n.*?\n\1(?=\n|$)", r"\2", command, flags=re.S)
	shell = re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", "Q", shell)
	return bool(COMMIT_CMD.search(shell))


def check_in(command: str) -> str:
	for name, script in CHECKS.items():
		if script in command:
			return name
	return ""


def emit(obj: dict) -> None:
	print(json.dumps(obj))


def context(event: str, text: str) -> None:
	emit({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}})


# ---------------------------------------------------------------- record

def cmd_record(payload: dict) -> None:
	state = load_state()
	before = json.dumps(state, sort_keys=True)
	event = payload.get("hook_event_name", "")
	tool = payload.get("tool_name", "")
	tin = payload.get("tool_input") or {}
	out = text_of(payload.get("tool_response"))

	name = ""
	if event == "SubagentStop":
		name = payload.get("agent_type") or ""
	elif tool in ("Agent", "Task"):
		# A background agent's PostToolUse fires at launch; only a finished agent counts (SubagentStop covers those).
		if not tin.get("run_in_background") and not re.search(r"agent launched|working in the background", out, re.I):
			name = tin.get("subagent_type") or ""
	if name in AGENTS:
		entry = {"time": time.time(), "base": base()}
		if name == "diff-reviewer":
			entry["files"] = code_files(changed_files())
		state.setdefault("agents", {})[name] = entry
	elif tool == "Bash" and not tin.get("run_in_background"):
		command = tin.get("command", "")
		started = (state.get("started") or {}).pop(payload.get("tool_use_id", ""), None) or time.time()
		check = check_in(command)
		ok = False
		if check == "tests":
			ok = bool(re.search(r"(^|:)All good\.\s*$", out, re.M))
		elif check == "balance":
			ok = "--out" not in command and bool(re.search(r"Wrote \S*docs/BALANCE\.md", out))
		elif check == "screens":
			ok = "Saved " in out and "FAILED" not in out
		if ok:
			state[check + "_ok"] = started
	if json.dumps(state, sort_keys=True) != before:
		save_state(state)


# ---------------------------------------------------------------- remind

def cmd_remind(payload: dict) -> None:
	tin = payload.get("tool_input") or {}
	path = tin.get("file_path") or tin.get("notebook_path") or ""
	try:
		rel = os.path.relpath(os.path.abspath(path), ROOT).replace(os.sep, "/") if path else ""
	except ValueError:  # another drive on Windows
		return
	kinds = []
	if rel in BALANCE_FILES:
		kinds.append(("balance", "You changed %s. When the content/rule edits are done, run the `balance-analyst` "
			"agent (it can run in the background while you write tests) and commit the new docs/BALANCE.md." % rel))
	if VISUAL.match(rel):
		kinds.append(("visual", "You changed %s (UI). When the visual work is done, run the `screenshot-checker` "
			"agent with what changed, and commit a screenshot to docs/screenshots/<task>/." % rel))
	if not kinds:
		return
	state = load_state()
	session = payload.get("session_id", "?")
	seen = state.setdefault("reminded", {})
	if list(seen) and session not in seen:
		seen.clear()  # a new session: forget the old one's reminders
	done = seen.setdefault(session, [])
	todo = [(k, msg) for k, msg in kinds if k not in done]
	if not todo:
		return
	done.extend(k for k, _ in todo)
	save_state(state)
	context("PostToolUse", " ".join(msg for _, msg in todo) +
		" Before committing, the tests must pass (`test-runner`) and `diff-reviewer` must review the change.")


# ---------------------------------------------------------------- gate

def missing_steps() -> list[str]:
	files = changed_files()
	code = code_files(files)
	if not code:
		return []
	state = load_state()
	missing = []
	if state.get("tests_ok", 0) < last_mtime(code):
		missing.append("Tests haven't passed since the last code change. Run the `test-runner` agent "
			"(or `bash tools/run_tests.sh` in the foreground, with its `All good.` line in the output) and fix any failures.")
	balance = [f for f in files if f in BALANCE_FILES]
	if balance and state.get("balance_ok", 0) < last_mtime(balance):
		missing.append("%s changed since the balance bot last ran. Run the `balance-analyst` agent (or "
			"`bash tools/simulate.sh`) and commit docs/BALANCE.md." % ", ".join(balance))
	visual = [f for f in files if VISUAL.match(f)]
	if visual and state.get("screens_ok", 0) < last_mtime(visual):
		shown = ", ".join(visual[:3]) + ("…" if len(visual) > 3 else "")
		missing.append("UI files changed (%s) since the last screenshots. Run the `screenshot-checker` agent "
			"(or tools/screenshot.sh) and commit a shot to docs/screenshots/<task>/." % shown)
	review = (state.get("agents") or {}).get("diff-reviewer") or {}
	unreviewed = [f for f in code if f not in (review.get("files") or [])] if review.get("base") == base() else code
	if unreviewed:
		shown = ", ".join(unreviewed[:3]) + ("…" if len(unreviewed) > 3 else "")
		missing.append("`diff-reviewer` hasn't reviewed %s. Run it once the steps above are done, and fix what it "
			"finds (or say in the CHANGELOG why not). Fixing its findings doesn't need a second review." % shown)
	return missing


def cmd_gate(payload: dict) -> None:
	command = (payload.get("tool_input") or {}).get("command", "")
	if check_in(command) and payload.get("tool_use_id"):
		state = load_state()
		started = state.setdefault("started", {})
		for key in [k for k, t in started.items() if t < time.time() - 86400]:
			del started[key]  # forget runs that never finished
		started[payload["tool_use_id"]] = time.time()
		save_state(state)
	if not is_commit(command) or "CUBE_SKIP_GATE=1" in command:
		return
	missing = missing_steps()
	if not missing:
		return
	reason = ("Commit blocked by the Cube Idle finish checklist (CLAUDE.md, \"Before you finish\"):\n- "
		+ "\n- ".join(missing)
		+ "\nThen commit again. Only if the owner asked to skip this, or the check is wrong, prefix the command "
		"with CUBE_SKIP_GATE=1 and say why in the CHANGELOG.")
	emit({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
		"permissionDecisionReason": reason}})


# ---------------------------------------------------------------- aftercommit

def phases(text: str) -> dict[str, tuple[int, int]]:
	"""Roadmap phase heading -> (open tasks, done tasks)."""
	result: dict[str, tuple[int, int]] = {}
	current = ""
	for line in text.splitlines():
		if line.startswith("## "):
			current = line[3:].strip()
			result.setdefault(current, (0, 0))
		elif current:
			m = re.match(r"\s*- \[( |x)\]", line)
			if m:
				open_, done = result[current]
				result[current] = (open_ + 1, done) if m.group(1) == " " else (open_, done + 1)
	return result


def phase_key(heading: str) -> str:
	m = re.match(r"(Phase \S+|Milestone \S+)", heading)
	return m.group(1) if m else heading


def completed_phases(before: str, after: str) -> list[str]:
	"""Phases with open tasks before and none after (a phase split over two headings counts as one)."""
	def by_key(text: str) -> dict[str, list[int]]:
		merged: dict[str, list[int]] = {}
		for heading, (open_, done) in phases(text).items():
			m = merged.setdefault(phase_key(heading), [0, 0])
			m[0] += open_
			m[1] += done
		return merged
	old, new = by_key(before), by_key(after)
	return [k for k, (open_, done) in new.items() if open_ == 0 and done > 0 and old.get(k, [0, 0])[0] > 0]


def cmd_aftercommit(payload: dict) -> None:
	if not is_commit((payload.get("tool_input") or {}).get("command", "")):
		return
	if "docs/ROADMAP.md" not in git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD").splitlines():
		return
	done = completed_phases(git("show", "HEAD~1:docs/ROADMAP.md"), git("show", "HEAD:docs/ROADMAP.md"))
	if done:
		context("PostToolUse", "This commit completes %s of the roadmap. Run the `fun-designer` agent for a fun pass "
			"and show its ranked ideas to the owner; only the ones they pick become ROADMAP tasks "
			"(marked \"(fun pass, date)\")." % " and ".join(done))


# ---------------------------------------------------------------- main

def main() -> int:
	if len(sys.argv) < 2:
		print(__doc__)
		return 0
	try:
		payload = json.load(sys.stdin)
	except ValueError:
		return 0
	handler = {"record": cmd_record, "remind": cmd_remind, "gate": cmd_gate, "aftercommit": cmd_aftercommit}.get(sys.argv[1])
	if handler:
		handler(payload if isinstance(payload, dict) else {})
	return 0


if __name__ == "__main__":
	sys.exit(main())
