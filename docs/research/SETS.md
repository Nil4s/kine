# Selection sets and keying sets: what Blender and Maya do, what Kine matches

GAP_ANALYSIS rows 9 ("Select: presets only; no user-named sets") and 6 ("no named groups of channels to key together").
Read from the manuals (no code copied):

- Blender manual, Add-ons > Animation > Selection Sets (`docs.blender.org/manual/en/latest/addons/animation/selection_sets.html`)
- Blender manual, Animation > Keyframes > Keying Sets (`docs.blender.org/manual/en/latest/animation/keyframes/keying_sets.html`)
  and Scene Properties > Keying Sets panel
- Maya help, Basics > Selecting > Quick select sets (Create > Sets > Quick Select Set; Edit > Quick Select Sets)
- Maya help, Animation > Character sets (Key > Create Character Set; the current character menu by the range slider)

## Blender

**Selection Sets** (bundled add-on, Pose Mode, Armature tab):
a list of named sets on the armature; `+` makes a set, `-` deletes it; **Assign** adds the selected bones,
**Remove** takes them out; **Select** / **Deselect** act on the set's bones; double-click renames; Alt+W pie menu,
Shift+Alt+W "add selected to a set"; copy / paste a set through the clipboard. Stored on the armature object, so
it travels with the .blend file.

**Keying Sets** (Scene tab):
named lists of animatable paths; one is the scene's **Active Keying Set** (also picked in the Timeline's header).
**I** (Insert Keyframe) with an active set keys every path in it at the current frame; Alt+I deletes them. Built-in sets
(Location, Rotation, Whole Character, Available) exist besides the user's. Stored on the scene.

## Maya

**Quick Select Sets**: Create > Sets > Quick Select Set names the current selection; Edit > Quick Select Sets > name
selects its members again (an option adds a shelf button). Members can be added / removed in the Outliner or the
Relationship Editor. Saved in the scene.

**Character sets**: Key > Create Character Set gathers attributes of many objects; the **current character set** is
picked in the menu next to the range slider; **S** (Set Key) then keys every attribute of the current set at the
current time. No current set: S keys the selected objects only. Subcharacters nest. Saved in the scene.

## What Kine matches

| Idea | Blender | Maya | Kine (scripts/part_sets.gd) |
|---|---|---|---|
| Name a group of parts from the selection | Selection Sets `+` / Assign | Quick Select Set | "Selection set: new from the selected parts" (auto-named `set 1`, with `_l` / `_r` when one-sided) |
| Select exactly its members | Select | Edit > Quick Select Sets > name | click its row under **Sets** in the browser, or "Sets: select the picked set's parts" |
| Add / remove the selected | Assign / Remove | Relationship Editor | "Sets: add / remove the selected parts" (an emptied set is deleted) |
| Rename / delete | double-click / `-` | rename / delete the set node | "Sets: rename the picked set..." (a box), "Sets: delete the picked set" |
| Saved with the work | on the armature | in the scene | scene file `"sets"`, written only when there is one |
| A named group keyed together | Keying Set | Character set | "Keying set: new from the selected parts" |
| One active choice; key it with the key-key | Active Keying Set + I | current character + S | active keying set + **K**: every body part in it at the playhead, ONE undo step |
| No active choice: key-key as before | I keys the selection | S keys the selection | K keys the picked part only (unchanged) |
| Left / right | (none built in) | (none built in) | Mirror the scene swaps every part to its twin and a set named `_l` / `_r` to the other name; "Sets: mirror the picked set" makes the twin set |

## What Kine does not do (yet)

- Channels: a Kine keying set keys a part's 3 angles; Blender / Maya can key single channels (only X rotation, say).
- Built-in keying sets (Whole Character); nested subcharacters; Alt+W pie; clipboard copy / paste of sets.
- Deleting keys through a keying set (Blender's Alt+I).
- Fingers can sit in a selection set, but a keying set keys body parts only (fingers are posed by their shapes,
  and K never keyed a finger).
