# Poser: the next 100 upgrades (101–200)

Drafted 2026-10-16 with Nick, for after round 30. The first list (UPGRADES_100.md) built the TOOL: panels, undo,
tests, the AI side. This one aims at what the tool is FOR: combat animations that go into the ARPG and look good.
The 22 still open in UPGRADES_100.md stay there; they are not repeated here.
Same rules: gates in GATES.md first, a real test (and anti-vacuity) for each, tick only with evidence. Never write
scenes/, poses/ or data/ unless an item says so. All suites after each round.
Tags: [GAME] into the game · [CMB] combat authoring · [ANI] animation quality · [RIG] body and rig · [VIEW] viewport
· [FILE] files and workflow · [QA] testing and speed · [AI] AI and automation · [UX] easier to use
**NICK?** = needs Nick's decision before it is built.

## A. Into the game (101–112)
READ FIRST (checked in D:/arpg, 2026-10-16): the ARPG is Unity 6 with NO Animator and no clips (SKELETON.md §4.4).
Poses are data in C#: `PoseTable` → `PoseTrack(bone, PoseKey(t, pitch, yaw, roll))` (unity/Assets/Scripts/View/PoseTable.cs).
13 slots (`LimbRig.Bone`: Hips, Head, ArmL/R, ThighL/R, ShinL/R, ForeL/R, Chest, HockL/R) on 16 `B_*` bones; angles are
degrees from REST in the CHARACTER's frame (+pitch = limb forward, +yaw = turn left, +roll = right shoulder drops),
applied roll, then yaw, then pitch; t is a 0..1 fraction of the swing; every segment eased with smoothstep. The file
itself says a baked JSON table "drops straight into this sampler". So that is the export target, not .glb.
101. [GAME] Export a scene as a PoseTable: a C# block (paste-ready into `Skills`) AND a JSON table, 13 slots, keys at the cards.
102. [GAME] The bone fold: Poser's ~60 joints onto the game's 13 (spine_01..03 → Chest, clavicle+upperarm → Arm, neck+head → Head, hand dropped); each game bone's angle is the COMPOSED rotation of the Poser chain it covers, decomposed in the game's order and signs.
103. [GAME] Easing match: Poser's eases are not the game's smoothstep, so add in-between keys until the game's sampler (re-implemented in the test) stays within 1° of Poser on every frame.
104. [GAME] Round-trip test: the exported table sampled by a GDScript copy of `PoseTrack.Sample` + `Joint.Set` gives the same world directions per bone as Poser, at 60 frames (bar in degrees, measured).
105. [GAME] Sign and axis control: one known pose per axis (arm forward, body turned left, right shoulder down) must export as +pitch / +yaw / +roll; it fails if any sign flips. OPEN: PoseTable.cs says +yaw turns LEFT, yet MeleeSwing winds a right-hand blow up with hips yaw +16 (a right-hand wind-up turns RIGHT); and by Unity's maths AngleAxis(+, right) sends a hanging arm BACK, yet working knees use -pitch to fold. The signs come from one capture in the game (one bone, one axis at a time), not from the comments.
106. [GAME] Events: hit / footstep / swoosh markers on the timeline, exported as fractions of the swing beside the table (the sim drives ActorPose.Swing 0..1).
107. [GAME] Batch export: every scene in a folder in one command (CLI and button), with a report of bones dropped and the worst error.
108. [GAME] Write straight into the game: an option to put the table into `unity/Assets/.../PoseTable.cs` (or a JSON the game loads), behind a confirm, never by default. NICK? (file or JSON loader)
109. [GAME] The game's camera in Poser (FOV 25°, pitch 50°, 32.2 m out: ATMOSPHERE.md), so a clip is judged as the player sees it.
110. [GAME] Skill names checked against the game's (MeleeSwing, ...), so an export replaces the right table. NICK?
111. [GAME] Bones the game cannot show are flagged before export (wrist, fingers, neck, clavicle twist): "this card's hand pose will not reach the game".
112. [GAME] The game's 4 m/s walk and 0.22 s lunge as reference clips in Poser (rebuilt from LimbRig's numbers), to animate against.

## B. Combat authoring (113–128)
113. [CMB] Frame data: mark startup / active / recovery on the timeline; the counts shown in frames at 60 fps, like a fighting game.
114. [CMB] The weapon's hitbox swept per frame during the active frames, drawn as a ribbon and exported with the clip.
115. [CMB] Cancel windows: a range where another move may start, shown on the timeline and exported.
116. [CMB] Combo chains: link clips (light, light, heavy) and play the chain end to end with its blends.
117. [CMB] Hit-stop preview: freeze a few frames at the contact, with a slider for how long.
118. [CMB] The dummy reacts: a flinch or knockback pose from the hit's direction and strength.
119. [CMB] Reach meter: how far the weapon's tip reaches from the body at each frame, the furthest marked.
120. [CMB] A weapon trail (a fading ribbon from the tip) during play, its colour by speed.
121. [CMB] Tip speed readout at the contact frame (m/s), against a target range per weapon. NICK? (ranges)
122. [CMB] Block and parry poses: a library per weapon, with a "held" flag.
123. [CMB] Two-hand grip changes mid-clip (one hand to two and back) without the bat jumping.
124. [CMB] Weapon swap mid-clip (bat to staff) for a draw or a pick-up animation.
125. [CMB] A second, posable character (the opponent) instead of the static dummy, for trades and grapples.
126. [CMB] Hit reaction set: generate front / back / left / right flinches from one base pose.
127. [CMB] Dodge distances: the root travel of a roll or step, shown on the floor in metres.
128. [CMB] A combat checklist per clip (anticipation present, contact on a card, recovery long enough), as a rule group.

## C. Animation quality (129–144)
129. [ANI] Arcs: draw the path of ANY joint (not only the tip) over the clip, with its frame ticks.
130. [ANI] Overlap / follow-through: children (forearm, hand, head) lag their parent by a set number of frames, as a toggle.
131. [ANI] Breakdown tool: make the in-between of two cards with a favour slider (closer to A or to B).
132. [ANI] Pops: find frames where any joint's speed jumps (a velocity spike), listed and clickable. FOUND (round 31, measuring the export): FOOT PLANTING makes the legs jump: the worst leg turn in one 60 fps frame, planting on / off: combo3 38.9 / 10.7, thrust 37.4 / 14.2, bo_spin 38.4 / 31.8, swing_fore 23.3 / 10.7, strike_legs 24.4 / 9.6, walk_bat 9.5 / 2.5 degrees. The game export copies it faithfully (and pays keys for it). combo3's worst frame reports span -1 at 1.700 s. FIX FIRST, round 32. TRACED in swing_fore (card 2 steps the left foot 14 cm in a 0.15 s move): (1) A SNAP: the last hold frame (0.750 s) has thigh_l twist -15.9, the first stepping frame (0.767 s) 0.1: the step's leg re-solve (Body.plant) throws the card's thigh twist away. That is a bug. (2) SPEED: the 8 cm lift arc in 0.15 s swings the thigh 4 -> 40 degrees in 2 frames; true to the card, not a bug, but it costs keys.
133. [ANI] Contact detection: find the frames where a foot is planted, from the clip itself, for foot locking.
134. [ANI] Walk / run cycle generator from a contact pose and a passing pose, with stride and speed.
135. [ANI] Idle breathing: a small loop added on top of any held pose (chest and shoulders), with a strength slider.
136. [ANI] Weight shift helper: the centre of mass's path drawn on the floor, with the support area per frame.
137. [ANI] Anticipation helper: add a small wind-up before a selected card, opposite to the move.
138. [ANI] Spacing chart per card (the classic animator's chart), editable by dragging the ticks.
139. [ANI] Additive layers: a second layer of changes over the base clip (a head turn over a walk), with a blend weight.
140. [ANI] Per-joint easing (the spine slower than the arm in the same card).
141. [ANI] Timing presets: snappy, heavy, floaty, which retime a whole clip.
142. [ANI] Twist distribution: a forearm twist spread along the arm, so the skin does not fold.
143. [ANI] Silhouette view: the body as a flat black shape, to read the pose at a glance.
144. [ANI] Thumbnail strip: a small picture of every card along the timeline.

## D. Body and rig (145–156)
145. [RIG] Head look-at: point the head (and eyes) at a target that can move.
146. [RIG] Foot roll: heel, ball and toe pivots for walks and lunges.
147. [RIG] Spine as one curve: bend the three spine joints together with one drag.
148. [RIG] Hand pose library: fist, open, grip, point, relaxed, mixed per finger.
149. [RIG] Hips height kept on the ground automatically (the lowest foot touches the floor).
150. [RIG] Body proportions: taller, shorter, broader characters, with the clips adapting.
151. [RIG] Joint limit editor (finishes old #64): see and change each joint's ranges, a soft warn and a hard clamp. NICK? (defaults)
152. [RIG] Hide a part takes its children too (a hidden arm hides its fingers), as an option on the eye.
153. [RIG] Collision tuning: see and adjust each capsule's size, saved per character.
154. [RIG] More weapons: sword, axe, shield, spear, with their own grips. NICK? (which ones the ARPG needs)
155. [RIG] A shield on the other arm, with its own block poses.
155a. [CMB] DUAL WIELD (Nick 2026-10-16: "weapons like double dagger, so mirrored would help in making the scenes easier, like for combos"): a weapon in EACH hand (a new "dagger" kind, ~0.30 m, one-hand grip), each with its own grip, saved per card; collisions for both.
155b. [CMB] Mirror carries the weapons: Mirror pose / Mirror the scene swap the two hands' weapons, each mirrored into the other hand (one weapon: it changes hands, as today); and PASTE MIRRORED now carries the weapon(s) too (Nick 2026-10-16 overrides round 10's "a copied pose carries the body, not the weapon").
155c. [CMB] Mirror a combo: "the next hit, mirrored": copy the last card(s) as a new card mirrored, so left-right-left chains are built from one side.
156. [RIG] Clothing silhouette shapes (a coat, a cape) to check readable poses with the ARPG's outfit. NICK?

## E. Viewport and camera (157–166)
157. [VIEW] J / K / L playback (back, pause, forward; tap again for faster) and frame-by-frame with , and .
158. [VIEW] Playback speed: 0.25x / 0.5x / 1x / 2x.
159. [VIEW] Reference images on planes (front and side) behind the body, with opacity.
160. [VIEW] A side-by-side view: Poser's full body next to the 13-bone game fold of the same frame (what is lost).
161. [VIEW] Contact shadow under the feet, so floor contact reads.
162. [VIEW] X-ray: see the skeleton through the body.
163. [VIEW] Isolate: show only the selected parts (uses the new hiding).
164. [VIEW] Measure tool: the distance between two points on the body or the floor.
165. [VIEW] Motion blur preview on fast frames.
166. [VIEW] Turntable: the camera circles the paused pose, for a review GIF.

## F. Files and workflow (167–178)
167. [FILE] Project view: every scene in folders with tags (weapon, move type), searchable.
168. [FILE] Copy cards between scenes (copy a wind-up into another swing).
169. [FILE] Scene templates: start a new swing from a template with anticipation, contact and recovery cards.
170. [FILE] Import mocap (BVH), retargeted onto the mannequin, as cards.
171. [FILE] Versions: compare two versions side by side (ghost of one over the other), and prune old ones.
172. [FILE] "New empty scene" asks whether to keep the current pose or start from the rest pose (today it silently keeps the pose).
173. [FILE] Clip notes: a text note per card and per scene, for "why this timing".
174. [FILE] Export a review sheet: every card as a picture plus its timing, in one PNG or PDF.
175. [FILE] Keyboard shortcuts editable, saved per user.
176. [FILE] Recent scenes list on the empty state.
177. [FILE] Scene merge: join two scenes' cards into one clip.
178. [FILE] Corrupted-file recovery: a broken scene file opens what it can and says what was lost.

## G. Testing, speed and polish (179–188)
179. [QA] Golden-image tests: the viewport of 5 key scenes against stored pictures (shots/), noise measured first.
180. [QA] Performance budget: 60 fps with 30 cards, ghosts and trail on; measured, and failed if it drops.
181. [QA] Startup time measured and kept under a budget (today unknown).
182. [QA] The full test run in parallel (headless suites at once): today ~25 min; target under 10.
183. [QA] Input recorder: record a session's input, replay it exactly, for bug reports.
184. [QA] Corrupt-file fuzz: random broken scene files never crash the app.
185. [QA] Contrast audit of both themes (text against background, a minimum ratio).
186. [UX] Rename the three mirror tools so their names say what they do: "Flip left ↔ right", "Copy right side to left", "Symmetry (live)". NICK? (names)
187. [UX] Portuguese (PT-BR) interface, switchable, every label and message.
188. [UX] A 2-minute "first swing" tutorial that builds a real bat swing with the user, step by step.

## H. AI and automation (189–200)
189. [AI] The MCP server exposes every registry command, plus render a frame and read the warnings, so Claude can work in a live Poser.
190. [AI] Text to clip: "a heavy overhead hammer slam with a long wind-up" builds draft cards.
191. [AI] Video to clip: a reference video's frames to a tracked pose per frame (finishes old #61–62), snapped to cards.
192. [AI] Critique: an AI review of a clip against the combat checklist and animation principles, as notes on the cards.
193. [AI] Pose search: "find poses like this one" across every scene, by joint-angle similarity.
194. [AI] Style transfer: the timing of clip A applied to the poses of clip B.
195. [AI] Auto-polish loop: run the checks, apply safe fixes, re-check, and stop when nothing improves; report every change.
196. [AI] Variation generator: 3 versions of a clip (faster, heavier, wider), for picking.
197. [AI] Describe a clip in plain words (what happens, when, how fast), for the game's design notes.
198. [AI] An agent regression: every example scene rebuilt from its description via the CLI, and compared.
199. [AI] Random valid poses within the joint limits, for testing and for inspiration.
200. [AI] A Claude panel inside Poser: ask "why does this swing look weak?" and get an answer with the cards marked. NICK? (needs an API key)
