# Kine: the next 400, road to Maya / Blender (2026-10-20)

Nick 10-20: "lets make the plan for the next 400 upgrades road to maya/blender, i want a set of innovations this time,
plan it and lets start w the cheap ones".

Where Kine stands: the animation side is deep (cards, curves, mocap, physics judges, combat). What Maya / Blender have
and Kine has NOTHING of yet is the mesh: modeling, sculpting, UVs, materials, rendering, rigging your own characters.
So this 400 is weighted to the pages greyed out on the page bar today (BODY, MODEL, SCULPT, SURFACE) and to the parity
gaps around them, with **119 innovations** (★) that only Kine can do because its mesh KNOWS IT IS A BODY: joint
limits, mass, ANSUR proportions, the animation and the motion checks are already there.

Order inside each track = build order. Cost: **$** one agent hour, no new core needed; **$$** one wave, needs the
track's core; **$$$** several waves. Mark `[x]` only when the item's test bars pass and the screenshot was looked at.

Rules carried over: features first, tests light (one test per item, real numbers, a placement bar for anything drawn);
human claims cited (ANSUR II, NIOSH, gait papers); Blender is GPL, ideas only; no Maya reverse engineering; full suite
once per 25 merged.

Merged: 56 / 400 (★ 17 / 119)

## The tracks

| track | items | ★ | what it buys |
|---|---|---|---|
| A Mesh core | 20 | 3 | the data everything below edits: half-edge mesh, selection, undo, symmetry |
| B MODEL page | 30 | 8 | Blender-level poly modeling, easier |
| C SCULPT page | 30 | 11 | brushes, multires, dyntopo, sculpt ON the posed body |
| D SURFACE: UVs | 15 | 4 | unwrap, seams, packing, checker |
| E SURFACE: materials + paint | 20 | 5 | PBR materials, texture paint, bake |
| F Retopology + topology | 15 | 6 | animation-ready loops placed where the rig bends |
| G BODY page | 25 | 13 | parametric humans from real measurements, auto-rigged |
| H Skinning + deformation | 25 | 10 | weights, correctives, muscles, deformation checked in every pose |
| I Face as geometry | 20 | 8 | real lids, lips, jaw (FACS), replaces the painted face |
| J Rigging your own | 25 | 7 | custom rigs, constraints, drivers, rig any mesh |
| K Viewport + render | 30 | 8 | shading modes, lights, shadows, a real offline render, turntables |
| L Animation parity | 30 | 9 | the remaining Maya graph / dope / NLA gaps |
| M Physics + sim | 20 | 8 | soft body, cloth on the mesh, muscles jiggle, rigid bodies |
| N Pipeline + files | 25 | 4 | OBJ/FBX/USD mesh in and out, assets, versions |
| O Scripting + addons | 15 | 3 | Python-free GDScript API, macros, addon store |
| P Workflow + UX | 25 | 8 | onboarding per page, search everything, crash-proof |
| Q Performance | 15 | 2 | 1M-poly sculpt, 60 fps playback of heavy scenes |
| R Hair, cloth design, props | 15 | 2 | grooms, garment patterns, prop modeling kits |
| **total** | **400** | **119** | |

---

## A. Mesh core (the foundation: nothing in B–F starts before A01–A06)

- [x] A01 $ `KMesh` (scripts/kmesh.gd): verts, faces (n-gons), half-edge adjacency, per-face normals, built from / to ArrayMesh; round trip of the mannequin mesh exact
- [x] A02 $ Selection model: verts / edges / faces sets, grow / shrink, select linked, select loop, select ring
- [x] A03 $ Mesh undo: one undo step per mesh edit, a diff not a copy (100k-vert edit undo under 5 MB)
- [x] A04 $ Symmetry map: x-mirror pairs found once (tolerance 0.1 mm), every edit mirrored
- [x] A05 $ Mesh draw in the viewport: wire over shaded, selected elements highlighted, back-face culled pick
- [x] A06 $ Pick: ray to vert / edge / face under the mouse, box and lasso select, x-ray select-through
- [x] A07 $ Mesh file: .kmesh JSON inside the .kine scene; loads in under 1 s for 200k verts
- [x] A08 $ Normals: smooth / flat / auto by angle, custom split normals kept on export
- [x] A09 $$ Attributes: per-vert / per-corner channels (colour, weight, mask, crease) on the half-edge
- [x] A10 $$ Mesh validate + repair: non-manifold, zero-area faces, flipped normals, holes, with a next step each
- [ ] A11 $$ Modifier stack (non-destructive): mirror, subdivide, solidify, array, displace; live in the viewport
- [x] A12 $$ Catmull-Clark subdivision with creases (own implementation from the 1978 paper)
- [x] A13 $$ Shape keys on KMesh (absolute + relative), driven by anything
- [x] A14 $ Mesh stats in the status line: verts / faces / tris / n-gons / poles
- [ ] A15 $$ Instancing: one mesh many objects (props, crowds) without copying
- [ ] A16 $$ Mesh layers in the Browser: objects, parenting, visibility, lock
- [ ] A17 $$ GPU skinning path for KMesh (so A–F meshes animate like the mannequin)
- [ ] A18 ★ $$ Body-aware mesh: every vertex knows its nearest bone and body region (UE5 names) from the first second
- [ ] A19 ★ $$ Anatomy tags: regions (deltoid, patella, knuckle...) painted once on the base body, carried through every edit
- [ ] A20 ★ $$ Pose-aware edit: edit a mesh while the character is POSED; the edit is mapped back to rest pose (inverse skinning)

## B. MODEL page

- [ ] B01 $$ Move / rotate / scale with the existing gizmo on a selection, numeric entry
- [x] B02 $$ Extrude (faces, edges, verts), individual and region
- [ ] B03 $$ Inset, bevel (edges with segments + profile), bridge edge loops  (inset + bridge merged; bevel still to do)
- [ ] B04 $$ Loop cut + slide, knife (cut along a stroke), edge split
- [x] B05 $$ Merge (at centre, by distance), dissolve (verts / edges / faces), delete
- [ ] B06 $$ Fill / grid fill holes, make face from selection
- [ ] B07 $$ Proportional editing (falloff curves, connected-only)
- [ ] B08 $$ Snapping: to verts, edges, faces, grid, the body's surface
- [x] B09 $$ Primitives: cube, cylinder, sphere (UV / ico), torus, plane, capsule, with live parameters
- [ ] B10 $$ Booleans (union / difference / intersect) on closed meshes
- [ ] B11 $$ Spin, screw, lathe from a profile curve
- [ ] B12 $$ Curves → mesh: bezier curves with bevel / taper (belts, straps, cables)
- [ ] B13 $$ Shrinkwrap / project onto the body (armour plates that fit)
- [ ] B14 $$ Pivot modes: median, active, cursor, individual origins; 3D cursor
- [ ] B15 $$ Edit history panel per object (the mesh steps, click to go back)
- [x] B16 $ Hotkeys like Blender's (G R S E I K) as an optional layer, Kine's plain ones by default
- [ ] B17 $$ Separate / join objects, set origin
- [ ] B18 $$ Edge flow tools: relax loop, straighten, set flow
- [ ] B19 $$ Poly build (draw quads on a surface)
- [x] B20 $$ Measure tool: distance, angle, area, volume (in cm, kg if a density is set)
- [ ] B21 $$ Reference images on planes (front / side), with opacity
- [ ] B22 $$ Mirror axis choice + topological mirror for asymmetric meshes
- [ ] B23 ★ $$ Armour from the body: select a body region (A19) → a plate shell offset 4 mm, edge-bevelled, already skinned
- [ ] B24 ★ $$ Range-of-motion clash: while modeling armour, play the ROM test; parts that cut into the body or each other light up per frame
- [ ] B25 ★ $$ Clothes-safe modeling: any mesh within 1 cm of the skin gets a collision warning across the whole animation, not just rest pose
- [ ] B26 ★ $$ Prop-from-hand: model a grip (handle) by closing the hand around a cylinder; the handle's diameter measured from the hand (Nick's grips)
- [ ] B27 ★ $$ Real-size sanity: a mesh's size against the body (a sword 3 m long, a helmet smaller than the head) flagged with the reference length
- [ ] B28 ★ $$ Weapon parts on a model: tag a modeled weapon's parts (grip / guard / blade) and it joins the grip book (I50) with mass + com computed from volume × material density
- [ ] B29 ★ $ Plain-words modeling: "make the shoulder pad 2 cm thicker", "bevel the edges of the helmet" through the existing words box
- [ ] B30 ★ $$ Model checks page: one button grades a model for animation (poles at joints, n-gons on deforming areas, thin parts)

## C. SCULPT page

- [x] C01 $$ Sculpt core: brush stroke → vertex displacement with falloff, radius, strength, pressure (tablet)
- [x] C02 $$ Brushes: draw, clay strips, inflate, smooth, flatten, pinch, crease, grab, snake hook
- [ ] C03 $$ Masking: paint mask, invert, blur, mask by cavity; masked areas frozen
- [ ] C04 $$ Multires levels (subdivide for detail, sculpt at any level, details kept when the base moves)
- [ ] C05 $$ Dynamic topology (local remesh under the brush)
- [ ] C06 $$ Voxel remesh (uniform resolution), keep volume
- [ ] C07 $$ Symmetry + radial symmetry in sculpt
- [ ] C08 $$ Alphas / stamps (skin pores, scales, fabric), drag rect, spray
- [ ] C09 $$ Face sets: group regions, hide / show, sculpt only one
- [ ] C10 $$ Layer brush and sculpt layers (on / off / strength)
- [ ] C11 $$ Stroke methods: space, dots, line, curve, anchored
- [ ] C12 $$ Matcaps for sculpting (clay, red wax, skin)
- [ ] C13 $$ Detail transfer: bake multires detail to a normal + displacement map
- [ ] C14 $ Brush presets panel with thumbnails, favourites
- [ ] C15 $$ Cloth brush (wrinkles that behave like fabric)
- [ ] C16 $$ Trim tools (box / lasso cut and fill)
- [ ] C17 $$ Pose brush (bend a sculpt along a chain)
- [ ] C18 $$ Mesh filters: inflate / smooth / sharpen whole mesh
- [ ] C19 ★ $$ Sculpt in pose: sculpt on the character in any frame of the animation; the stroke lands in rest pose (A20)
- [ ] C20 ★ $$ Muscle brush: strokes follow real muscle fibre directions (anatomy atlas per region, A19)
- [ ] C21 ★ $$ Anatomy-aware inflate: grow a muscle and its volume, origin and insertion stay on the right bones
- [ ] C22 ★ $$ Fat / muscle / bone sliders as brushes: "lean", "bulk", "soft" applied by region, bounded by ANSUR-plausible ranges
- [ ] C23 ★ $$ Sculpt checked in motion: after a stroke, the 8 hardest poses of the scene play as thumbnails so you see it bend
- [ ] C24 ★ $$ Wrinkle from motion: the sculpt suggests crease lines where the animation compresses the skin most
- [x] C25 ★ $ Sculpt-to-reference: overlay a photo / video frame of a real person, opacity + match
- [ ] C26 ★ $$ Age / sex / build morph brushes from measured populations (ANSUR II men + women, percentiles shown)
- [ ] C27 ★ $$ Symmetry that allows asymmetry: a real body is 1–3 % asymmetric; a "natural asymmetry" pass with the measured spread
- [ ] C28 ★ $$ Wound / scar / bruise stamps that also mark the body (the hit-reaction system knows where it hurts)
- [ ] C29 ★ $$ Sculpt from my hit habits: where the fighter is hit most (hit_habits) gets the armour / callus suggestion
- [ ] C30 $$ Sculpt on 1M polys at 60 fps (BVH + partial GPU updates) — see Q

## D. SURFACE: UVs

- [ ] D01 $$ UV editor panel: the 2D view, select / move / rotate / scale islands
- [ ] D02 $$ Seams: mark / clear, seam by angle, seam from face sets
- [x] D03 $$ Unwrap: angle-based (LSCM from the 2002 paper), conformal, projection (cube / cylinder / sphere)
- [ ] D04 $$ Island packing (with margin, rotate, texel density equalised)
- [x] D05 $ Checker texture + stretch heat map
- [ ] D06 $$ UV sync with 3D selection, pin, live unwrap
- [ ] D07 $$ UDIMs (multi-tile)
- [ ] D08 $$ Straighten / align / stitch islands
- [ ] D09 $$ Texel density tool (px / cm, matched across objects)
- [ ] D10 $$ UV layers (several sets per mesh)
- [ ] D11 $$ Export UV layout as PNG / SVG
- [ ] D12 ★ $$ Body seams by default: the base body ships with seams where a tailor / a game artist hides them (inner arm, inner leg, back of the head)
- [ ] D13 ★ $$ Seams that avoid motion: a seam crossing a high-stretch area of the animation is flagged (stretch measured over the scene)
- [ ] D14 ★ $$ Texel priority by camera: face and hands get more texels if the shots look at them (from the shot list)
- [ ] D15 ★ $ One-click "game ready UVs": unwrap + pack + density for a named engine budget (1 × 2k / 4 × 1k)

## E. SURFACE: materials, texture paint, bake

- [ ] E01 $$ Materials: PBR (base colour, metal, rough, normal, AO, emission, SSS), assign by face set
- [ ] E02 $$ Material library (skin, cloth, leather, steel, wood) with thumbnails
- [ ] E03 $$ Texture paint: brushes on the model, layers, blend modes
- [ ] E04 $$ Vertex paint
- [ ] E05 $$ Bake: normal, AO, curvature, cavity, thickness from high → low
- [ ] E06 $$ Smart masks (edges wear, cavity dirt) from the bakes
- [ ] E07 $$ Node material editor (simple: images, mix, ramp, noise)
- [ ] E08 $$ Procedural textures: noise, voronoi, gradient, wave
- [ ] E09 $$ Image projection paint (stencil a photo onto the model)
- [ ] E10 $$ Texture export per engine (packed ORM for UE5, separate for Unity / Godot)
- [ ] E11 $$ Decals (logos, tattoos) projected and movable
- [ ] E12 $$ Skin shader: SSS, pores detail, oily / dry roughness map
- [ ] E13 $$ Eye shader (cornea refraction, iris depth)
- [ ] E14 $$ Hair cards material
- [x] E15 $ Material from a photo (a picture → base colour + estimated roughness / normal)
- [ ] E16 ★ $$ Wear from motion: edges that the animation rubs (contact, cloth slide, grip) get worn paint / polished metal
- [ ] E17 ★ $$ Sweat / flush from exertion: the exertion & fatigue models drive a skin wetness + redness map over the scene
- [ ] E18 ★ $$ Real skin tones from measured data (colorimetric skin datasets, Fitzpatrick I–VI), not a colour picker guess
- [ ] E19 ★ $$ Grip wear: the grip book's hand spots wear the handle's texture exactly where the hands go
- [ ] E20 ★ $$ Blood / dirt from the hit list: hits leave marks where they landed, frame by frame, exported as a texture sequence

## F. Retopology + topology

- [ ] F01 $$ Quad remesh (field-aligned, quad dominant)
- [ ] F02 $$ Retopo tools: draw quads on a sculpt, snap to surface, relax
- [ ] F03 $$ Decimate (collapse / planar) keeping UVs
- [ ] F04 $$ LODs (3–4 levels with targets)
- [ ] F05 $$ Edge loop guides (draw where loops must go, remesher follows)
- [x] F06 $$ Triangulate / quadrangulate
- [ ] F07 $$ Shrinkwrap retopo onto high poly
- [x] F08 $$ Topology heat map: poles, triangles, stretched quads
- [ ] F09 $$ Project details low ← high (re-bake)
- [ ] F10 ★ $$ Rig-aware retopo: loops placed where the skeleton bends (3 loops at elbow / knee, radial around shoulder), from the joint positions
- [ ] F11 ★ $$ Topology graded in motion: each joint region's quad stretch measured over the scene's poses, worst first
- [ ] F12 ★ $$ Loop count from the motion: joints that bend further (Nick's deep stances) get more loops automatically
- [ ] F13 ★ $$ Face loops for FACS: eye and mouth rings placed for the action units I needs
- [x] F14 ★ $ "Will this deform?" one-click verdict before rigging, with the 3 worst spots shown
- [ ] F15 ★ $$ LOD by screen size of the shots (camera distance per shot decides each LOD's budget)

## G. BODY page (make the character)

- [ ] G01 $$ Base body mesh (CC0 / own), quad topology, rigged to the UE5 skeleton Kine uses
- [ ] G02 $$ ANSUR II sliders: stature, mass, 30 measured dimensions as percentiles, men and women
- [ ] G03 $$ Proportions solve: a slider moves the skeleton AND the mesh (bones resized, limits kept)
- [ ] G04 $$ Head shapes: skull width, jaw, brow, nose, ears (from 3D head surveys' ranges)
- [ ] G05 $$ Hands and feet sizes (ANSUR hand length / breadth, foot length)
- [ ] G06 $$ Body presets: fighter, heavyweight, lean runner, child, elder
- [ ] G07 $$ Save / load bodies (.kbody), thumbnails in the Browser
- [ ] G08 $$ Body to the current scene: re-fit an animation to the new proportions (retarget, contacts kept)
- [ ] G09 $$ Muscle definition and body fat as separate controls
- [ ] G10 $$ Clothes base set (shirt, trousers, gi, boots) fitted to any body
- [ ] G11 $$ Teeth, tongue, eyes, eyelashes as parts
- [ ] G12 $$ Export the body as glb / fbx with skin weights
- [x] G13 ★ $ Body from 5 numbers: height, weight, sex, age, build → a whole plausible body (regression on ANSUR)
- [ ] G14 ★ $$ Body from a photo (front + side) → measurements → body (pose estimation already in Kine)
- [ ] G15 ★ $$ Body from a video clip: the tracked limb lengths give the body (VideoIQ lengths)
- [ ] G16 ★ $$ Percentile readout: every body says where it sits ("shoulders 92nd percentile of men")
- [ ] G17 ★ $$ Impossible body warning: combinations outside measured populations flagged, with the nearest real one
- [ ] G18 ★ $$ Mass properties from the mesh: segment masses and inertia from volume × tissue density (replaces table guesses; checked against Dempster / de Leva)
- [ ] G19 ★ $$ The body changes the physics: a heavier body really moves slower in the judges (balance, exertion, hit reactions use G18)
- [ ] G20 ★ $$ Joint limits by body type: flexibility ranges by age / sex from measured ROM studies
- [ ] G21 ★ $$ Matching opponent: "make his opponent 10 cm taller, 15 kg heavier" and the fight's distances re-fit
- [ ] G22 ★ $$ Body families: siblings / variations around one body for crowds, each still plausible
- [x] G23 ★ $ Fighter archetypes from real athletes' published measurements (boxer reach / height ratios by weight class)
- [ ] G24 ★ $$ Growth / aging over a timeline (a character at 12, 25, 60) from growth curves
- [ ] G25 ★ $$ Body ↔ grip: hand size changes the grip book's hand spots (a small hand chokes higher)

## H. Skinning + deformation

- [ ] H01 $$ Auto weights (heat diffusion / geodesic voxel, own implementation)
- [ ] H02 $$ Weight paint: brush, smooth, normalise, mirror, lock bones
- [ ] H03 $$ Weight tools: transfer from another mesh, limit 4 influences, clean small
- [ ] H04 $$ Dual-quaternion skinning option (no candy-wrapper wrists)
- [ ] H05 $$ Corrective shape keys driven by joint angle (pose space deformation)
- [ ] H06 $$ Lattice / cage deformers
- [ ] H07 $$ Delta mush (smooth deformation)
- [ ] H08 $$ Wrap deformer (clothes follow the body)
- [ ] H09 $$ Helper bones (twist, elbow volume) auto-added
- [ ] H10 $$ Weight preview in pose (scrub the animation while painting)
- [ ] H11 $$ Mirror weights by topology
- [ ] H12 $$ Bind pose / rest pose tools
- [ ] H13 $$ Blend shape editor (sculpt a shape in pose, it becomes a corrective)
- [ ] H14 $$ Skin export check: weights survive glb / fbx in UE5 / Unity / Godot (round trip test)
- [ ] H15 $$ Muscle system: simple fibre muscles that bulge on contraction
- [ ] H16 ★ $$ Weights from anatomy: regions (A19) start with anatomically sensible weights before any painting
- [ ] H17 ★ $$ Deformation graded over the scene: volume loss per joint in every frame, worst frames listed (like the human check)
- [ ] H18 ★ $$ Auto correctives from the scene: the worst-deforming poses of THIS animation get corrective shapes generated
- [ ] H19 ★ $$ Muscle bulge driven by effort: exertion (torque per joint) drives the bulge, not just the angle
- [ ] H20 ★ $$ Skin slide: skin slides over bone landmarks (elbow, knee, scapula) as measured, not stretched
- [ ] H21 ★ $$ Breathing: chest / belly volume follows a breathing rate from exertion (rest 12–20 / min, effort up to 40–60)
- [ ] H22 ★ $$ Contact deformation: a hand gripping, a fist landing, a foot on the floor flattens the soft tissue it presses
- [ ] H23 ★ $$ Jiggle by tissue: fat / muscle secondary motion with damping from measured soft-tissue studies
- [x] H24 ★ $ "Weights broke here" one click: shows the vert with the worst weight problem in the worst frame
- [ ] H25 ★ $$ Weight paint by moving: drag the skin in a pose and the weights change to make it go there

## I. Face as geometry (replaces the painted face)

- [ ] I01 $$ Head mesh with eyelids, lips, jaw, brows as real geometry, eyes as separate balls
- [ ] I02 $$ Jaw and eye bones, eyelid follow-the-eye
- [ ] I03 $$ FACS action units as blendshapes (AU1..AU28 core set)
- [ ] I04 $$ Expression presets built from AUs (joy, anger, fear, effort, pain)
- [ ] I05 $$ Face controls on the face (on-surface handles), and a slider panel
- [ ] I06 $$ Visemes from AUs; lip-sync drives the geometry
- [ ] I07 $$ Teeth and tongue visible and animatable
- [ ] I08 $$ Eye look-at with saccades and blinks (blink rate from studies, 15–20 / min)
- [ ] I09 $$ Wrinkle maps driven by AUs (forehead, crow's feet)
- [ ] I10 $$ Face capture from webcam → AUs (MediaPipe face landmarks, already allowed)
- [ ] I11 $$ ARKit 52 blendshape export (for engines)
- [ ] I12 $$ Face retarget to any head made in G
- [ ] I13 ★ $$ Effort face: the exertion model sets the face (clenched jaw at peak torque, AU4 + AU7 + AU24)
- [ ] I14 ★ $$ Pain face from hit reactions: the hit's force picks the pain expression and its timing
- [ ] I15 ★ $$ Breath on the face: nostrils, mouth open on hard breathing (H21)
- [ ] I16 ★ $$ Gaze from the fight: eyes track the opponent's weapon / shoulders as fighters do (gaze studies)
- [ ] I17 ★ $$ Face checks: AU combinations that are anatomically impossible flagged (FACS rules)
- [ ] I18 ★ $$ Kiai / shout timing: the shout lands on the strike frame (impact frames) with the mouth shape
- [ ] I19 ★ $$ Micro-expressions between beats (FACS durations 1/25–1/5 s)
- [x] I20 ★ $ Face from words: "tired and angry" → AU mix through the words box

## J. Rigging your own

- [ ] J01 $$ Bone editor: add / delete / parent bones, edit rest pose, roll
- [ ] J02 $$ Rig any mesh: auto-place a humanoid skeleton from mesh landmarks
- [ ] J03 $$ Constraints: copy location / rotation / scale, limit, track-to, damped track, stretch-to, child-of
- [ ] J04 $$ Drivers with expressions (exists for body; extend to mesh shapes / any property)
- [ ] J05 $$ IK chains on any bones (tails, tentacles), pole targets
- [ ] J06 $$ Spline IK (spines, tails, ropes)
- [ ] J07 $$ Custom control shapes, colours, bone groups
- [ ] J08 $$ Rig picker panel (click shapes on a 2D chart)
- [ ] J09 $$ Quadruped / creature templates
- [ ] J10 $$ Prop rigs: bow (string pull), nunchaku chain, whip, shield straps
- [ ] J11 $$ Space switching (hand in world / chest / weapon)
- [ ] J12 $$ Rig layers: deform, mechanism, controls
- [ ] J13 $$ Rig export: bake constraints to bones for engines
- [ ] J14 $$ Retarget between any two rigs (bone mapping UI, auto-guess by name and shape)
- [ ] J15 $$ Mechanical rigs: pistons, hinges, gears (weapons with moving parts)
- [ ] J16 $$ Rig validate: missing parents, scale on bones, flipped rolls
- [ ] J17 $$ Facial rig controls bound to I's AUs
- [ ] J18 $$ Finger rig with curl / spread / fist
- [ ] J19 ★ $$ Limits from the body: a new rig's joint limits come from body_limits by bone name / position, not left open
- [ ] J20 ★ $$ Creature limits by analogy: a quadruped's joints get limits from measured animal ROM (dog / horse studies)
- [ ] J21 ★ $$ Rig checked by motion: play the scene's moves on a new rig; joints that hit limits or flip show per frame
- [ ] J22 ★ $$ Auto mass for a creature rig (G18 on any mesh) so the physics judges work on monsters too
- [ ] J23 ★ $$ Weapon rigs from the grip book: a modeled weapon's holdable parts become the hand constraints
- [x] J24 ★ $ Rig from words: "add a tail with 8 bones" through the words box
- [ ] J25 ★ $$ Rig diff: two rig versions compared bone by bone (rest, limits, weights) before re-rigging an animated character

## K. Viewport + render

- [x] K01 $ Shading modes: wire, solid, matcap, material, rendered; per-viewport
- [x] K02 $ Studio lights presets (3-point, rim, top) with HDRI backgrounds
- [ ] K03 $$ Real-time shadows, SSAO, SSR, bloom toggles (Godot's renderer)
- [ ] K04 $$ Depth of field from the shot camera (rack focus exists: render it)
- [ ] K05 $$ Motion blur in the render
- [ ] K06 $$ Offline render: high samples, PNG sequence / MP4, alpha
- [ ] K07 $$ Render queue (several shots overnight)
- [x] K08 $ Turntable render (360° of the character / prop, any length)
- [ ] K09 $$ Light editor: point, spot, area, sun; temperature in kelvin
- [ ] K10 $$ Volumetrics / fog
- [ ] K11 $$ Toon / outline shading mode (fighting game look)
- [ ] K12 $$ Render passes: beauty, depth, normal, mask (for compositing)
- [x] K13 $ Viewport overlays: face orientation, normals, stats
- [x] K14 $ Quad view (front / side / top / persp)
- [x] K15 $ Local view (isolate the selection), frame selected
- [x] K16 $ Clipping planes / section view
- [ ] K17 $$ Grease-pencil style drawing over the viewport, kept per frame
- [ ] K18 $$ Camera views with lens mm, sensor size, safe areas
- [ ] K19 $$ Environment: ground with reflections, sky, simple sets
- [ ] K20 $$ Render farm-free: render shots on the local GPU in parallel processes
- [ ] K21 $$ Colour management (Filmic / AgX-like tone map, own LUTs)
- [ ] K22 $$ Viewport capture with UI stripped (clean playblast)
- [x] K23 ★ $ Render the judge: overlays (balance, force, hit boxes) rendered into the final video as a breakdown pass
- [ ] K24 ★ $$ Breakdown reel: auto video of a move as blocking → splined → physics check → final, side by side
- [ ] K25 ★ $$ Lighting from the fight: key light follows the attacker, rim on the defender, cut on impacts
- [x] K26 ★ $ Silhouette check render: every key pose as a black silhouette sheet (readability, the animators' test)
- [ ] K27 ★ $$ Impact flash + hit-stop in the render from impact frames (game feel preview)
- [ ] K28 ★ $$ Sport-science overlays: joint angles, speeds, centre of mass trail in a broadcast style
- [x] K29 ★ $ Thumbnail picker: the most readable frame of each clip chosen by silhouette area + line of action
- [ ] K30 ★ $$ Real-camera match: render with the lens + height of a phone / GoPro for side-by-side with reference

## L. Animation parity (gaps left after the first 400)

- [ ] L01 $$ Non-linear editor polish: strips with blend curves, scale, repeat, mute per strip
- [ ] L02 $$ Animation layers with masks per bone and additive / override modes in the dope sheet
- [ ] L03 $$ Graph editor: weighted tangents, buffer curves, curve snapshot compare
- [ ] L04 $$ Euler filter + quaternion curves view
- [ ] L05 $$ Time warp curve per clip
- [ ] L06 $$ Motion paths editable for any bone (drag the path)
- [ ] L07 $$ Onion skin per part with colours, ghosts every N frames
- [ ] L08 $$ Pose library thumbnails rendered, blend from library at %
- [ ] L09 $$ Breakdown slider (tween machine) on any selection
- [ ] L10 $$ Retime tool (drag keys in time with ripple)
- [ ] L11 $$ Keying sets with names, auto key on a set
- [ ] L12 $$ Graph editor modifiers: noise, cycles, stepped, limits
- [ ] L13 $$ Shape key animation in the dope sheet
- [ ] L14 $$ Sound waveform in the graph editor
- [ ] L15 $$ Mesh / material property animation (any property keyable)
- [ ] L16 $$ Bake to keys from anything (constraints, physics, drivers)
- [ ] L17 $$ Animation on custom rigs (J) with all the same tools
- [ ] L18 $$ Mirror animation on custom rigs by name / position
- [ ] L19 $$ Frame-rate conversion with sub-frame keys
- [ ] L20 $$ Sequencer: shots, cuts, transitions, audio on one timeline, export an edit
- [ ] L21 ★ $$ Style transfer between clips: Nick's timing on someone else's poses (curve shape statistics per joint)
- [ ] L22 ★ $$ Auto anticipation / follow-through proposals from the physics (how much wind-up the torque needs)
- [ ] L23 ★ $$ "Make it heavier / lighter" one slider, mass-correct (timing and arcs from the momentum model)
- [ ] L24 ★ $$ Spacing chart from a real reference: overlay a tracked video's spacing on your curves
- [ ] L25 ★ $$ Motion stitching: two clips joined at the most compatible frame (pose + velocity + contacts)
- [x] L26 ★ $ Arc checker: joints whose paths break an arc (a kink) listed with the frame
- [ ] L27 ★ $$ Clip personality fingerprint: compare two animators' clips (speed, holds, overlap) as numbers
- [ ] L28 ★ $$ Interpolation that respects limits: splines never pass through an impossible pose between keys
- [ ] L29 ★ $$ Reaction auto-timing: a defender's block is placed at human reaction time (≥ 150–200 ms) after the cue
- [ ] L30 $$ Graph editor for mesh shape keys and face AUs (same tools)

## M. Physics + sim

- [ ] M01 $$ Soft body on any mesh (mass-spring / XPBD)
- [ ] M02 $$ Cloth on modeled garments (pinning, sewing from patterns R)
- [ ] M03 $$ Rigid bodies for props with collision shapes from the mesh (convex decomposition)
- [ ] M04 $$ Ragdoll on custom rigs (J) using G18 masses
- [ ] M05 $$ Particles (dust, sparks, debris) with simple forces
- [ ] M06 $$ Fracture (break a prop / wall on impact)
- [ ] M07 $$ Cache and scrub any sim; bake to keys / mesh cache
- [ ] M08 $$ Wind / turbulence fields
- [ ] M09 $$ Ropes / chains (nunchaku, kusarigama)
- [ ] M10 $$ Collision between characters' meshes (not just capsules)
- [ ] M11 $$ Water splash / footstep puddles (simple)
- [ ] M12 $$ Sim LOD (cheap for preview, full for render)
- [ ] M13 ★ $$ Sparks on weapon clash: from the weapon rebound model's contact point, velocity and material
- [ ] M14 ★ $$ Dust from footwork: the floor-plan stamps and foot slides kick dust by speed
- [ ] M15 ★ $$ Prop break by real material strength (wood / steel numbers) when the hit force exceeds it
- [ ] M16 ★ $$ Cloth that answers the fight: gi sleeves snap on a punch (speed from the move), belt follows the hips
- [ ] M17 ★ $$ Soft-tissue on impact: the hit spot ripples by the hit's force (H23)
- [ ] M18 ★ $$ Weapon flex: a staff / spear bends by its length, material and the swing's speed
- [ ] M19 ★ $$ Sim judge: a sim that explodes / tunnels is flagged with the frame and the cause
- [ ] M20 ★ $$ Physics from the mesh everywhere: every modeled thing gets mass / inertia from its volume + material

## N. Pipeline + files

- [x] N01 $ OBJ import / export (mesh, UVs, normals)
- [ ] N02 $$ FBX mesh + skin export (own writer; extend the animation fbx)
- [ ] N03 $$ glTF mesh + materials + skin + shape keys export (extend gltf_export)
- [ ] N04 $$ USD export (mesh, skel, anim)
- [ ] N05 $$ STL / 3MF export for 3D printing (watertight check)
- [ ] N06 $$ Alembic-like mesh cache export
- [ ] N07 $$ Import meshes from Blender / Maya via glTF / FBX with skin
- [ ] N08 $$ Asset library: characters, props, materials, bodies, thumbnails, tags
- [ ] N09 $$ Project folders and linking (a prop used by 10 scenes, edited once)
- [ ] N10 $$ Version history per asset (save points with thumbnails)
- [ ] N11 $$ Texture / image management (missing files, relink)
- [ ] N12 $$ Per-engine presets for meshes (UE5 scale / axes, Unity, Godot)
- [ ] N13 $$ Import MakeHuman-style / CC0 bodies as bases
- [ ] N14 $$ Engine round-trip test: export → load in Godot headless → compare (automated)
- [x] N15 $ Pack project (all files into one zip)
- [ ] N16 $$ Mesh diff between versions (verts moved, highlighted)
- [ ] N17 $$ VRM export (avatars)
- [ ] N18 $$ Mixamo-compatible export (skeleton names map)
- [ ] N19 $$ Point cloud / photogrammetry mesh import (cleanup to a usable base)
- [ ] N20 $$ Lossless autosave of meshes (crash-proof, extends I-crash work)
- [ ] N21 ★ $$ Character card: one file with body, mesh, rig, grips, moves and its physics numbers, drop into any engine
- [ ] N22 ★ $$ Engine-side checks: export reports what the target engine will break (bone count, influences, scale)
- [x] N23 ★ $ Share a character as a link (glb + a viewer page)
- [ ] N24 ★ $$ Moveset export: the fighter's moves with frame data + hitboxes in one game-ready bundle
- [ ] N25 $$ Godot / UE5 / Unity plugin to live-link Kine (send pose / mesh over 127.0.0.1)

## O. Scripting + addons

- [ ] O01 $$ Script console (GDScript) with the Kine API: scene, body, mesh, commands
- [ ] O02 $$ Addon format: a folder with a manifest; enable / disable; sandboxed file access
- [ ] O03 $$ API docs generated from the code
- [ ] O04 $$ Record macro → script
- [ ] O05 $$ Custom panels from addons
- [ ] O06 $$ Custom brushes / modifiers from addons
- [ ] O07 $$ Headless batch: run a script on many files
- [ ] O08 $$ Local HTTP API extended to mesh ops (local_api exists)
- [ ] O09 $$ Addon store page (list, install from a folder / zip, licence shown)
- [ ] O10 $$ Event hooks (on save, on export, on frame)
- [ ] O11 $$ Python bridge for pipelines (subprocess, JSON)
- [ ] O12 $$ Example addons: crowd randomiser, prop scatter, auto LOD
- [ ] O13 ★ $$ Judges as addons: anyone can add a new physics / anatomy check that the CHECK page runs
- [ ] O14 ★ $$ Words → script: the words box writes a small script, shows it, runs it on yes
- [x] O15 ★ $ Every command is a script line: the history panel can be saved as a re-runnable script

## P. Workflow + UX

- [x] P01 $ Page onboarding: each new page (BODY / MODEL / SCULPT / SURFACE) has a 5-step first-use tour
- [x] P02 $ Search finds mesh tools too, with hotkeys shown
- [ ] P03 $$ Tool settings panel (last-op redo panel: change a bevel's width after doing it)
- [ ] P04 $$ Pie menus (optional), radial for brushes
- [x] P05 $ Status bar shows what the mouse buttons do now
- [ ] P06 $$ Customisable hotkeys per page
- [ ] P07 $$ Workspaces: save a layout per page
- [ ] P08 $ Theme: light / dark / high contrast for the new pages (Tok tokens)
- [ ] P09 $$ Tablet support (pressure, tilt) everywhere
- [ ] P10 $$ Multi-object editing
- [x] P11 $ "Why can't I?" explainer: any greyed tool tells why and the fix
- [ ] P12 $$ Undo across pages (sculpt then animate, Ctrl+Z walks back both)
- [x] P13 $ Recent files with thumbnails on the start screen
- [ ] P14 $$ Unit system (cm / m / in) everywhere
- [ ] P15 $$ Large-file safety: saves in the background, never blocks
- [ ] P16 $$ Accessibility: font scaling, colour-blind palettes for selection
- [x] P17 ★ $ Next suggested tool: the page suggests the next step from what you just did (modeling's "next pose")
- [ ] P18 ★ $$ Learn-from-me hotkeys: the commands you use most get offered a hotkey
- [ ] P19 ★ $$ Task coach: "make a fighter" walks BODY → MODEL → SURFACE → POSE with checks at each step
- [x] P20 ★ $ Blender / Maya keymap translator: press a Blender key, Kine tells you its own name for it
- [ ] P21 ★ $$ Mistake catcher: common beginner mesh mistakes (doubled verts, inside-out normals, unapplied scale) caught as they happen
- [x] P22 ★ $ One-page cheat sheet per page, printable, generated from the commands
- [ ] P23 ★ $$ Time-lapse of a session (the edits replayed as a video)
- [ ] P24 ★ $$ Undo by region: undo only the edits on the left hand, keep the rest
- [ ] P25 $$ Crash report with the last 20 commands (local file, no upload)

## Q. Performance

- [ ] Q01 $$ Mesh BVH for picking and sculpt (10× faster picks on 1M tris)
- [ ] Q02 $$ Partial GPU buffer updates (only touched verts)
- [ ] Q03 $$ Threaded subdivision / normals (WorkerThreadPool)
- [ ] Q04 $$ Viewport LOD while orbiting
- [ ] Q05 $$ Lazy evaluation of the modifier stack
- [ ] Q06 $$ 60 fps playback of a skinned 100k-vert character
- [ ] Q07 $$ Memory budget display + warnings
- [ ] Q08 $$ GDExtension (C++) path for the hot loops (sculpt, skin, subdiv), with a GDScript fallback
- [ ] Q09 $$ Profiling page (frame time by system)
- [ ] Q10 $$ Benchmarks in the suite (perf regressions fail the run)
- [ ] Q11 $$ Async texture loading
- [ ] Q12 $$ Instanced crowds 200 at 60 fps
- [ ] Q13 $$ Sculpt stroke latency under 16 ms at 1M polys
- [ ] Q14 ★ $$ Perf by what you see: only shots' visible meshes evaluate at full detail
- [x] Q15 ★ $ Perf doctor: "why is it slow" names the heaviest thing with the fix

## R. Hair, garment design, props

- [ ] R01 $$ Hair guides (comb, cut, length, clump) on the head mesh
- [ ] R02 $$ Hair cards generation from guides (game-ready)
- [ ] R03 $$ Hair dynamics on guides (extends hair.gd)
- [ ] R04 $$ Garment patterns (2D panels sewn onto the body, like a tailor)
- [ ] R05 $$ Garment fitting to any G body, with ease (looseness) in cm
- [ ] R06 $$ Gi / hakama / boxing shorts / gloves pattern presets
- [ ] R07 $$ Prop kits: blades, hafts, guards, pommels to assemble weapons (feeds B28)
- [ ] R08 $$ Shoes from the foot mesh (last-based)
- [ ] R09 $$ Belts, straps, buckles along curves (B12)
- [ ] R10 $$ Armour kits (plates, mail, padding) fitted to regions
- [ ] R11 $$ Accessories (headband, wraps, tape) along the body
- [ ] R12 $$ Eyebrows / beard / stubble
- [ ] R13 $$ Hair export (cards + curves) per engine
- [ ] R14 ★ $$ Garment ease from the motion: the pattern gets looser where the moves stretch it most (deep stance → wider hakama)
- [ ] R15 ★ $$ Weapon from real specs: blade length / mass / balance point from historical measured weapons → a model + its grip book entry

---

## Wave 1: the cheap ones ($), started 2026-10-20

Cheap and independent of the mesh core first, then the mesh core itself (A01–A06) so the $$ tracks can start.

| wave 1 | item | why first |
|---|---|---|
| 1 | A01 KMesh core | everything in B–F stands on it |
| 2 | G13 Body from 5 numbers ★ | ANSUR regression; drives the existing body's proportions now |
| 3 | K26 Silhouette sheet ★ | readability check on today's scenes |
| 4 | K29 Thumbnail picker ★ | best frame per clip by silhouette + line of action |
| 5 | L26 Arc checker ★ | kinks in joint paths, from today's curves |
| 6 | K08 Turntable render | 360° video of the character / prop |
| 7 | K01 + K02 Shading modes + light presets | viewport parity, cheap |
| 8 | N01 OBJ export / import | first mesh file format, test bed for A01 |
| 9 | G23 Fighter archetypes ★ | published athletes' measurements → body presets |
| 10 | P20 Blender / Maya key translator ★ | lowers the first week for Blender users |

Next cheap ones (wave 2): A02–A06 (after A01), K13–K16, D05, P01, P05, P11, P13, P17 ★, P22 ★, Q15 ★, O15 ★, B16, C14, C25 ★, E15, F14 ★, H24 ★, I20 ★, J24 ★, B29 ★, N15, N23 ★, K23 ★, D15 ★.
