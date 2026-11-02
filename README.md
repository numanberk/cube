# Cube Idle

An idle game about solving Rubik's cubes. Built with Godot 4.7 for PC.

## Run it
1. Install **Godot 4.7** (standard version, not .NET): https://godotengine.org/download
2. Open Godot → **Import** → pick this folder's `project.godot` → **Import & Edit**.
3. Press **F5** to play.

## Test it
```bash
bash tools/run_tests.sh
```
On Windows (Git Bash), point it at Godot's console executable first:
```bash
GODOT="/c/path/to/Godot_v4.7.2-stable_win64_console.exe" bash tools/run_tests.sh
```

## Build a Windows .exe
1. In Godot: **Editor → Manage Export Templates → Download and Install**.
2. **Project → Export → Add… → Windows Desktop**.
3. Click **Export Project** and choose a `builds/` folder (it's git-ignored).

## Working on it with Claude
See `CLAUDE.md`. Any Claude session can pick up where the last one stopped by reading
`CLAUDE.md`, `docs/ROADMAP.md` and `docs/CHANGELOG.md`.
