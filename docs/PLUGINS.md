# Plugins (plugin API, api 2)

A plugin adds commands to the S box (the command search). It can read the cards, propose edits to them, and keep its
own data files. It is written in GDScript and lives in a folder.

**Plugins run with the app's permissions. Only enable plugins you trust.** GDScript cannot be sandboxed: a plugin can do
anything this app can. The API below is the documented way in. It keeps a plugin away from the app's own code and from
files outside its data folder, but it is a door, not a wall.

## Where plugins live

- `user://plugins/<name>/` for your own and installed plugins. (On Windows, `user://` is
  `%APPDATA%\Godot\app_userdata\<project>\`; the Plugins panel shows the real folder.)
- `examples/plugins/` in the repo: shipped examples. The panel lists them too, and they are off by default.

Plugins are **off by default**. A plugin that is off is never loaded: its code is not compiled and its commands are not
in the S box. The switches are saved in `user://plugins.json`.

Open the panel from the S box: type `plugins`, then pick **Plugins: enable or disable plugins**.

## A plugin folder

```
mirror_all_cards/
  manifest.json      what the plugin is (read before anything runs)
  plugin.gd          the code
  data/              (optional, made by the plugin) its own files, see write_data
```

The folder name is the plugin's id: lower case letters, digits and `_`, starting with a letter.

### manifest.json

```json
{
  "name": "Mirror All Cards",
  "version": "1.0.0",
  "author": "Teschima Studios",
  "api": 1,
  "description": "Mirrors the pose of every card left <-> right in one undo step.",
  "commands": [
    {"id": "mirror_all", "name": "Mirror every card", "desc": "every card's pose reflected, one undo step"}
  ]
}
```

| field | meaning |
|---|---|
| `name` | the name people see. The S box shows each command as `<name>: <command name>` |
| `version` | free text, shown in the panel |
| `author` | free text |
| `api` | the API version the plugin was written for. Must be `1`. Any other number and the plugin is not loaded |
| `description` | optional, one line, shown in the panel |
| `commands` | at least one `{"id", "name", "desc"}`. `id` is what `command()` receives; `name` is the S box row; `desc` its tooltip |

A bad manifest is shown in the panel with what is wrong and the next step. The plugin stays off.

### plugin.gd

```gdscript
extends RefCounted

func command(api, id: String) -> void:
	if id == "mirror_all":
		mirror_all(api)
	else:
		api.fail("there is no command '%s' in this plugin" % id)
```

`command(api, id)` runs when the user picks one of the plugin's rows. `api` is the plugin API object (below). The
plugin must `extends RefCounted` (or nothing).

**A command must return `true` when it is done.** Any other return (`false`, nothing, or a value) disables the plugin
with a message. This is how a plain GDScript error is caught: GDScript has no try, but a command that hits an error
returns nothing, and that is not `true`. Return `false` after `api.fail(...)` for a failure you expect:

```gdscript
func command(api, id: String) -> bool:
	var r: Dictionary = api.set_joint(0, "lowerarm_l", Vector3(90, 0, 0))
	if not r["ok"]:
		api.fail(r["why"])
		return false
	return true
```

## What a command can do

Each command is **one undo step**. Its edits all join it, the step is named after the S box row, and one Ctrl+Z takes
back everything the command did.

### Reading (copies: changing them changes nothing)

| call | returns |
|---|---|
| `api.api_version()` | `2` |
| `api.has_permission("files")` | true when the manifest asked for it |
| `api.card_count()` | how many cards the scene has |
| `api.cards()` | every card as a copy: `{"name", "hold", "move", "joints": {joint: Vector3(bend, side, twist) in degrees}}`. `move` is -1 when automatic |
| `api.joint_names()` | the joint names the body has |
| `api.scene_info()` | `{"name", "cards", "length", "fps", "objects", "keyed_joints"}` |
| `api.objects()` | the set's objects: `[{"index", "kind", "pos": Vector3, "yaw"}]` |
| `api.keys(joint)` | the part keys of a joint: `[{"t", "v": Vector3}]` by time |
| `api.mesh_info()` | the mesh open on the MODEL page: `{"ok", "verts", "faces", "bounds_min", "bounds_max"}` (`ok` false when none is open) |
| `api.mesh_vertices(max_count := 5000)` | `{"ok", "vertices": PackedVector3Array, "truncated"}`, a copy |
| `api.selection()` | `{"card" (-1 = none), "joint", "object"}` |

### Editing (each returns `{"ok": bool, "why": String, ...}`; `why` says what went wrong)

| call | what it does |
|---|---|
| `api.set_joint(i, joint, Vector3(bend, side, twist))` | sets one joint of card `i`. **Clamped to the joint's limits**: `clamped` is true when the value was changed, and `value` is what was kept |
| `api.add_card(name, from := -1)` | a new card at the end, with card `from`'s pose (default: the last card). Returns its `index` |
| `api.remove_card(i)` | removes card `i` |
| `api.set_timing(i, hold, move := -1.0)` | card `i`'s hold and move in seconds, clamped to 0.05 .. 10. `move` -1 = automatic |
| `api.rename_card(i, name)` | renames card `i` |
| `api.add_object(kind, pos, yaw := 0.0)` | adds a set object (`box`, `crate`, `table`, ...). Returns its `index`. An unknown kind is refused |
| `api.move_object(i, pos)` | moves object `i` to `pos` (metres) |
| `api.remove_object(i)` | removes object `i` |
| `api.set_key(joint, t, Vector3)` | a part key at `t` seconds, **clamped to the joint's limits**; a key within 1 ms is replaced |
| `api.remove_key(joint, t)` | removes the key at `t` |
| `api.select_card(i)` / `api.select_joint(joint)` | pick a card or a joint (the selection is not an undo step) |

Card, object and key indices are 0-based.

### Needs a permission

A manifest lists what it needs: `"permissions": ["files", "export", "tools"]`. A plugin without a permission gets
`{"ok": false, "why": "needs the 'files' permission ..."}` and nothing happens. Unknown names make the manifest invalid.
The Plugins panel shows them before you switch a plugin on.

| permission | call | what it does |
|---|---|---|
| `tools` | `api.run_tool(line)` | one line of the app's tool language, e.g. `set=head:15,0,0` or `card=2` (the same lines as a saved script). Quit, open, new and save are refused |
| `export` | `api.export("bvh")` | writes `<scene>.bvh` into the plugin's own `exports/` folder. Returns `{"ok", "path", "bytes"}` |
| `files` | `api.write_file("exports/a.txt", text)`, `api.read_file(rel)` | files in the PROJECT, but only `exports/`, `scenes/`, `poses/` or `plugin_out/` (a folder, then a name). `..`, absolute paths, drives, `res://`, `user://`, backslashes and `scripts/` are refused |

### Settings and the plugin's own files

| call | what it does |
|---|---|
| `api.get_setting(key, default)` / `api.set_setting(key, value)` | values the plugin keeps (JSON types). **They survive restarts and updates** |
| `api.write_data("scores.txt", text)` | writes a file under `<plugins data>/<name>/data/` (no permission needed) |
| `api.read_data("scores.txt")` | returns `{"ok", "text"}` |

A path that leaves the data folder is refused (`ok` is false, nothing is written): `..`, a leading `/` or `\`, a drive
letter, a `\`, an empty part. Subfolders inside the data folder are fine (`sub/notes.txt`).

### Talking and failing

| call | what it does |
|---|---|
| `api.log(text)` | a line on the status bar, prefixed with the plugin's name |
| `api.fail(text)` | the command cannot go on. **The plugin is disabled**, the command's edits are taken back, and the message is shown with its name and a next step. The app keeps running |

Use `api.fail` for a failure you expect (a card that is not there, a file you cannot read). A GDScript runtime error (a
null value, a bad index) also disables the plugin: the command then does not return `true`, and the message says so
(Godot's console shows the line that failed). Check the results of the calls above, and call `fail` when they say no.

### Time limit and rollback

A command runs on a worker thread. If it is still running after 5 seconds the app stops waiting: the plugin is
disabled, the edits it made are **undone** (as if it never ran), and its api calls do nothing from then on. A loop
that never calls the api cannot be killed (GDScript has no way to stop a thread), so it may keep one CPU core busy until
Kine is restarted. The app stays usable. A command that fails or times out leaves no undo step.

## Installing, updating, removing

Plugins panel: **Install...** takes a plugin folder or a `.zip` (the zip holds `manifest.json` and `plugin.gd`, either at
the top or inside one folder). The package is checked first (manifest, api number, permissions, no entry that leaves the
folder, at most 20 MB); a bad one installs nothing and says why. A new plugin is **off**. Installing a plugin whose folder
name is already there is an **update**: it keeps the enable switch, the settings and the data, and refuses an older
version. **Uninstall** removes the folder (the data stays). The manifest's `license` line is shown in the panel.

### What a plugin cannot reach

- The app's own code (`main.gd`) and its scene objects. The API hands over copies and the few calls above, nothing else.
- Files outside `user://plugins/<name>/data/` and the project's `exports/ scenes/ poses/ plugin_out/`, through the API.
- Plugins that are off: they are not loaded at all.

These are the API's rules. Because GDScript cannot be sandboxed, a plugin that goes around the API (it can call engine
classes directly) is not stopped by the app. That is why the warning is in the panel.

## Errors

| what happens | what you see |
|---|---|
| the manifest is missing a field, the api number is not 1 or 2, or a permission is unknown | the panel: the field or the number, and the step to take. The plugin is off |
| `plugin.gd` does not compile | the panel and the status bar name the plugin and say to fix the script. The plugin is off |
| `plugin.gd` has no `command(api, id)` | the same, with the function to add |
| a command calls `api.fail` | the status bar: `Plugin '<name>' stopped in command '<id>': <message>. It is disabled now. Next step: ...`. The plugin is off and its rows leave the S box |
| a command errors, or does not return `true` | the same, with `did not finish: it returned <value> instead of true`. The plugin is off |

## Examples (examples/plugins/)

| folder | what it does | uses |
|---|---|---|
| `mirror_all_cards/` | mirrors every card's pose left and right | `cards`, `set_joint` |
| `loop_cards/` | **Close the loop**: appends a copy of card 0 | `add_card` |
| `batch_rename/` | **Number the cards**: Take 01, Take 02, ... (setting `prefix`) | `rename_card`, `get_setting` |
| `export_counter/` | **Export BVH** and count the exports | permission `export`, `export`, `set_setting` |

Switch one on in the Plugins panel, then type its name in the S box.

## Versions

- `api` 1: the calls above.
- `api` 2: objects, keys, mesh read, selection, `rename_card`, permissions (`files`, `export`, `tools`), settings,
  install / update / uninstall, a time limit with rollback. An `api` 1 plugin still loads and runs unchanged.
