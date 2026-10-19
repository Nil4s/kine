# Plugins (plugin API, api 1)

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
| `api.card_count()` | how many cards the scene has |
| `api.cards()` | every card as a copy: `{"name", "hold", "move", "joints": {joint: Vector3(bend, side, twist) in degrees}}`. `move` is -1 when automatic |
| `api.joint_names()` | the joint names the body has |
| `api.api_version()` | `1` |

### Editing (each returns `{"ok": bool, "why": String, ...}`; `why` says what went wrong)

| call | what it does |
|---|---|
| `api.set_joint(i, joint, Vector3(bend, side, twist))` | sets one joint of card `i`. **Clamped to the joint's limits**: `clamped` is true when the value was changed, and `value` is what was kept |
| `api.add_card(name, from := -1)` | a new card at the end, with card `from`'s pose (default: the last card). Returns its `index` |
| `api.remove_card(i)` | removes card `i` |
| `api.set_timing(i, hold, move := -1.0)` | card `i`'s hold and move in seconds, clamped to 0.05 .. 10. `move` -1 = automatic |

Card indices are 0-based.

### Files

| call | what it does |
|---|---|
| `api.write_data("scores.txt", text)` | writes a file under `user://plugins/<name>/data/` |
| `api.read_data("scores.txt")` | returns `{"ok", "text"}` |

A path that leaves the data folder is refused (`ok` is false, nothing is written): `..`, a leading `/` or `\`, a drive
letter, a `\`, an empty part. Subfolders inside the data folder are fine (`sub/notes.txt`).

### Talking and failing

| call | what it does |
|---|---|
| `api.log(text)` | a line on the status bar, prefixed with the plugin's name |
| `api.fail(text)` | the command cannot go on. **The plugin is disabled** and the message is shown with its name and a next step. The app keeps running |

Use `api.fail` for a failure you expect (a card that is not there, a file you cannot read). A GDScript runtime error (a
null value, a bad index) also disables the plugin: the command then does not return `true`, and the message says so
(Godot's console shows the line that failed). Check the results of the calls above, and call `fail` when they say no.

### What a plugin cannot reach

- The app's own code (`main.gd`) and its scene objects. The API hands over copies and the few calls above, nothing else.
- Files outside `user://plugins/<name>/data/`, through the API.
- Plugins that are off: they are not loaded at all.

These are the API's rules. Because GDScript cannot be sandboxed, a plugin that goes around the API (it can call engine
classes directly) is not stopped by the app. That is why the warning is in the panel.

## Errors

| what happens | what you see |
|---|---|
| the manifest is missing a field, or the api number is not 1 | the panel: the field or the number, and the step to take. The plugin is off |
| `plugin.gd` does not compile | the panel and the status bar name the plugin and say to fix the script. The plugin is off |
| `plugin.gd` has no `command(api, id)` | the same, with the function to add |
| a command calls `api.fail` | the status bar: `Plugin '<name>' stopped in command '<id>': <message>. It is disabled now. Next step: ...`. The plugin is off and its rows leave the S box |
| a command errors, or does not return `true` | the same, with `did not finish: it returned <value> instead of true`. The plugin is off |

## Example

`examples/plugins/mirror_all_cards/` mirrors every card's pose left and right. Switch it on in the Plugins panel, then
type `mirror all` in the S box and pick **Mirror All Cards: Mirror every card**. The rule is the app's own for the
pairs (the twin takes bend, side and minus twist); the hips' sideways offset and the weapon are not changed.

## Versions

- `api` 1: the calls above.
