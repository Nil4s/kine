#!/bin/sh
# ALL SUITES, one line each (GATES O1). From the poser folder:   sh tools/run_all.sh [name ...]
# A suite FAILS on a non-zero exit, on any "FAIL" line, or on a SCRIPT ERROR in its log (an exit 0 is not enough:
# a script error can skip the checks after it). Logs: $LOGS (default $TMP/poser_suites). Exit code = suites failed.
G=${G:-/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe}
LOGS=${LOGS:-${TMP:-/tmp}/poser_suites}
mkdir -p "$LOGS"
# name:mode   (h = headless, w = needs a window)
ALL="actors_file:h math:h spline:h tween:h rules:h fix:h mirror:h flip_survey:h tween_undo:w monkey:w fix_window:w tools_window:w
timeline:w hand_drag:w command_search:w view_cube:w browser:w ring:w empty_state:w ribbon:w drag_any:w units:h euler:h"
EXTRA="readpose:w undo_audit_s0:w undo_audit_s1:w undo_audit_s2:w undo_audit_s3:w undo_fuzz:w undo_tree:w cli:h scene_list:w theme:w status_bar:w icons:w paste:w ease:w plant:w pole:w fix_preview:w search_forgive:w history:w confirm:w hover_hint:w ui_scale:w why:w say_next:h examples:w tour:w schema:h diff:h pose_words:h serve:h agent:h dummy_async:w names:w determinism:h keyboard:w mcp:h measure:h clicks:w autosave:h loop:h balance:h retime:w keys_overlay:w names_disk:h edge_counts:h scrub_bounds:w check_all:h mirror_list:h popup_leak:w ghosts_follow:h search_one_list:w browser_place:w empty_back:w small_window:w ring_edges:w symmetry:w cube_views:w greyed_why:w onion_fade:h graph_read:w timeline_marks:w floor_fade:h side_colours:h feedback:w weapon_picker:w type_scale:h empty_paths:w hover:w lock_part:w num_entry:w nav_bar:w multi_select:w sel_sets:w versions:w grip_mirror:h browser_eye:w hover_sync:w game_fold:h game_table:h plant_edges:h dual_wield:w glb_export:h bvh_export:h engine_names:h hints:w fold:w launcher:h drag_stop:w toolbar:w inspector:w browser_tree:w strip:w quiet:w view_share:w props:h importer:h set:w stand_set:h prop_check:h use_set:w carry:w carry_form:h jump:h jump_ui:w part_keys:h part_keys_ui:w curves:h inbetween:h preview_range:w markers:h playblast:w playblast_export:w bvh_import:h throw:h jump_physics:h lift_form:h people_doc:h decompose:h walk_arm:h walk_legs:h balance_view:h plant_all:h hand_curl:h back_bend:h shoulder_follow:w breath:h gait_band:h stage:w layer:h key_interp:h curve_editor:w curve_multi:w key_blend:w curve_mods:h bake:h curve_views:w curve_why:w dope_copy:w layers:h layer_fix:h layer_merge:h drag_speed:h dope_sheet:w breakdowner:h foot_roll:h look_at:h mocap_clean:h usd_export:h shading:w gait:h walk_people:h video_import:h video_ui:w video_grip:h grip_save:h grip_wrap:h grip_types:h grip_magnet:h agent_tools:h llm_client:h ai_box:w ik_pin:h cross_contact:h actors_main:h audio_track:w actors_view:w actors_hit:w actors_export:h ik_handles:w graph_editor:w constraints:h shot_camera:w proportions:h fighter_hover:w camera_gizmo:w graph_range:w drivers:h grip_scale:h sets:h engine_export:h foot_plant:h pose_library:w anim_import:h props_generic:h easy_mode:w easy_overlap:w journal:w hotkeys:w clips:w toes_walk:h human_limits:h humancheck_shot:w foot_handles:w frame_data:h ease_presets:h foot_joints:h critique:h twinning:h video_cleanup:h choreo:w hit_reaction:w style_transfer:h any_grip:h line_of_action:w live_puppet:w play_perf:w stunt_load:h version_diff:w motion_match:h lip_sync:h beat_track:h secondary_motion:h weapon_trail:h co_edit:h text_blocking:h weapon_clash:h hit_boxes:w ragdoll:h range_rings:h whywrong:w fatigue:w review:w floorsnap:h retime_handles:w autokey:w play_speed:w undonames:w scene_thumbs:w weight_feel:w save_prompt:w easeslider:h mirror_inplace:w tip_video:w searchall:w templates:w pose_copy:h export_dialog:h themescale:w recent:w ikfk:h space:h tangents:w spine_ik:w key_reduce:h onion_parts:w retimerange:h keytypes:h trail_edit:w weightpaint:w hand_pose:h hand_pose_ui:w camshake:w camseq:w corrective:h face:w gentle:w fbx_export:h usd_layers:h precise_pick:w macros:w batch_export:w customattr:w clipwarp:w posematch:w hair:w dummyview:w contactik:w cloth:w rigid_drop:w handcap:h multicam:h multicam_ui:w multicam_app:w audiotracks:w rootpath:w scene_diff:w assetstore:w crowd:w stairs:w marker_notes:w plugins:w limit_tint:w rise:h rise_ui:w perf4:w pathwalk:w pathrun:h pathwalk_ui:w feasible:h feasible_shot:w pages:w cardstrip:w videoiq:w retarget:h vroot:h bodypage:w r2:w r17:w r3:w r12:w r5:w r6:w r18:w r13:w r1:w r10:h r4:w r26:w r14:h r11:w r9:w r8:w r20:w r15:w r19:w r16:w r22:w r7:w r21:w r27:w i4:w i2:w i10:w i5:w i7:w i12:w i9:w i1:w i6:w i11:w r25:w r23:w r24:w i8:w i13:w i15:w i14:w i16:w i3:w i17:w i18:w i21:w i19:w i22:w i23:w i20:w i26:w i24:w i27:w i25:w i31:w i29:w i28:w i32:w i30:w perf1:w i35:w i34:w i33:w i38:w i36:w i43:w i42:w i39:w i37:w i41:w i40:w i44:w i46:w i45:w i47:w i48:w live_layer:w grip_switch:h gen_move:w weapon_kinds:w grip_book:w cheat_sheet:h kmesh:h archetypes:w thumbpick:w body5:w meshsel:h turntable:w keytrans:w silsheet:w shading_modes:w arccheck:w objio:w histscript:w perfdoc:w nexttool:w recents:w judgerender:w meshfile:h kmesh_undo:h kmesh_validate:h page_soon:w meshview:w refimg:w viewx:w packzip:w sharelink:h kmesh_attrs:h blkeys:w faceword:w meshsearch:w meshstats:w wbroke:w subdiv:h mousehint:w shapekeys:h prims:h kmeshmeasure:w dissolve:h extrude:h fill:h topotools:w sculpt:h sculpt_ui:w uvunwrap:h uvshade:w deform:w pagetour:w photomat:w rigword:w proportional:w mask:w bevel:h uvexport:h bodymesh:w kmesh_cut:h meshwords:w modstack:w uvpack:w uvgame:w sculptsym:h meshfilter:h uveditor:w autoweights:h pbrmat:w eyelife:w anatomy:w matlib:w kwpaint:w basebody:w vpaint:w decimate:h lod:w dqskin:w boneedit:w bodyfile:w bodyexport:w facesets:w realsize:w refplanes:w alphas:w shrinkwrap:w sepjoin:h rigretopo:w topomirror:w edgeflow:h meshcurves:w sculptpose:w romclash:w asserts:h events:h bodyframe:h humanfacts:h brief:h dryrun:h frameadv:h lint:h intro:w textview:h rangesweep:h conflict:h knobs:h tryn:h posepath:h recognize:h coupled:h supports:h fixloop:h livebal:w redspots:w explain:h hitharder:h bench:h whocould:h spec:h weightxfer:h ouch:w trunk:w easyhome:w freename:h monkey_beginner:w meshpages:w vidspeed:h bodycaps:h boot:w"
EXTRA="$EXTRA body_cache:h"   # BODY CACHE (scripts/body_cache.gd): cold and warm builds byte-identical; a corrupt cache falls back
EXTRA="$EXTRA snap:w pivot:w"   # B08 / B14
EXTRA="$EXTRA matcap:w brushpreset:w"   # C12 / C14
EXTRA="$EXTRA modelcheck:w"   # B30
EXTRA="$EXTRA boolean:h"   # B10
EXTRA="$EXTRA deformscene:w"   # ROADMAP_400 H17
case " $EXTRA " in *" bodymesh:"*) ;; *) EXTRA="$EXTRA bodymesh:w" ;; esac   # A18: lost when the EXTRA line above was re-set; H17 runs it with deformscene
EXTRA="$EXTRA anatomy:w autoweights:h basebody:w bevel:h bodymesh:w eyelife:w fill:h kmesh_cut:h kwpaint:w mask:w matlib:w meshfilter:h meshwords:w modstack:w pbrmat:w proportional:w sculptsym:h uveditor:w uvexport:h uvgame:w uvpack:w vpaint:w snap:w pivot:w"   # the suites the w2-decimate merge's line above dropped
EXTRA="$EXTRA kmesh_grs:h"   # round 2 walk: G R S with the Blender layer off, Alt+click loop, Ctrl+1 subdivide
EXTRA="$EXTRA armour:w"   # B23
EXTRA="$EXTRA meshsbox:w"   # mesh edit: F3 opens the S box (S is Scale there); the status line wraps clear of the mesh readout
EXTRA="$EXTRA modelfix4:w"   # walk-through 4: S box undo, library focus, view click, SURFACE Paint
EXTRA="$EXTRA paintfix:w"   # paint fixes: the paint panel beside Materials (Library clickable), a press on a low-poly face paints it
EXTRA="$EXTRA stagelib:w"   # the STAGE page's own Library button, the library listing my models, no overlap with STAGE panels
EXTRA="$EXTRA groundspeed:h"   # GROUNDSPEED: Body.ground() cached sole / seat helpers, legacy_ground equality + speed
EXTRA="$EXTRA persist2:w"   # the armour, the body and the autosave (tests/persist2_test.gd)
EXTRA="$EXTRA library:w"   # object library (scripts/object_library.gd)
EXTRA="$EXTRA easybar:w"   # Easy bar: 7 buttons, More holds the rest (scripts/easy_mode.gd)
EXTRA="$EXTRA userpaths:w"   # an exported build writes the user's files to Documents/Kine (scripts/user_paths.gd)
EXTRA="$EXTRA easycam:w"   # Easy camera: the body framed in the free rect under the Easy bar / strip (scripts/easy_mode.gd frame_clip)
EXTRA="$EXTRA easyvid:w"
EXTRA="$EXTRA easygen:w"   # Easy: Copy a video (More): the Expert import, one undo step, plain sentences (tests/easyvid_test.gd)
EXTRA="$EXTRA easytweak:w"   # Easy: the strip's Faster / Slower / Bigger / Smaller (tests/easytweak_test.gd)
EXTRA="$EXTRA walk_model4:w"   # WALK-THROUGH 4: the expert model / sculpt / surface walk (tests/walk_model4_test.gd)
EXTRA="$EXTRA easysave:w"   # Easy: Save video: the progress, the plain done message, Cancel, the empty-scene hint (tests/easysave_test.gd)
EXTRA="$EXTRA children:w"   # the child programs end with the app (scripts/children.gd; tests/children_test.gd)
EXTRA="$EXTRA drafts:w"   # the scene list: saved scenes first, one Drafts group (tests/drafts_test.gd)
EXTRA="$EXTRA easyvid:w"   # Easy: Copy a video (More): the Expert import, one undo step, plain sentences (tests/easyvid_test.gd)
EXTRA="$EXTRA meshexport:h"   # round 2 walk: Apply body no-op, Export model (GLB / OBJ)
EXTRA="$EXTRA lostspan:w"   # lost spans: a lost hand or foot filled by joint angles (tests/lostspan_test.gd)
EXTRA="$EXTRA objexport:w"   # EXPORT DIALOG "What to export": the mesh objects in the scene (tests/objexport_test.gd)
EXTRA="$EXTRA nickbugs:w"   # NICK'S BUGS (tests/nickbugs_test.gd): Scene menu New, Undo / Reset clicks, browser scroll kept on hover
EXTRA="$EXTRA p068hingebycli:w"   # p068 Friday 68: Hinge by click on the Easy Part page (tests/p068hingebycli_test.gd)
# suites that are slow BY DESIGN (name=seconds): text_blocking fits both hands on every card of every phrase (~0.25 s per arm fit, ~700 s alone),
# gentle runs every one of 450+ commands from 7 hostile states (~2600+ cells); the default cap would stop them while they are still working
SLOW="text_blocking=1800 gentle=2400 brief=1500 dryrun=900 lint=600 tryn=1800 recognize=900 fixloop=1500"
pick=${*:-$ALL $EXTRA}
# OFF SCREEN (Windows): Godot pulls a --position that is off every screen back to 0,0 (measured 10-23), so window suites
# are parented (--wid) to one host window at -30000,-30000 (tools/offscreen_host.ps1: never activated, no taskbar
# button), with no sound. TOPLEVEL suites resize their own window, which an embedded one cannot: --position only (they
# show at 0,0). SHOW=1: every window on screen, as before. Parallel runs: tools/run_par.py.
TOPLEVEL="small_window r25 ring_edges easy_overlap"   # as tools/run_par.py TOPLEVEL
HOSTWID=""; hf="$LOGS/.host.$$.hwnd"
if [ -z "$SHOW" ] && command -v powershell >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  rm -f "$hf"
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/offscreen_host.ps1)" -HwndFile "$(cygpath -w "$hf")"     -Owner "$(cat /proc/$$/winpid 2>/dev/null || echo 0)" >/dev/null 2>&1 &
  k=0; while [ ! -s "$hf" ] && [ $k -lt 40 ]; do sleep 0.5; k=$((k + 1)); done
  HOSTWID=$(tr -dc 0-9 < "$hf" 2>/dev/null); [ -n "$HOSTWID" ] && export KINE_TEST_WID=$HOSTWID   # tests' own child Godots use it
  trap 'rm -f "$hf"' EXIT
fi
n=0; bad=0
for s in $pick; do
  case $s in *:*) ;; *) s=$(echo "$ALL $EXTRA" | tr ' \n' '\n\n' | grep "^$s:" | head -1) ;; esac
  name=${s%%:*}; mode=${s##*:}
  f=tests/${name}_test.gd; [ -f "$f" ] || f=tests/$name.gd
  if [ ! -f "$f" ]; then echo "MISSING $name"; n=$((n+1)); bad=$((bad+1)); continue; fi
  flag=""; [ "$mode" = h ] && flag=--headless
  if [ "$mode" != h ] && [ -z "$SHOW" ]; then
    flag="--position -30000,-30000 --audio-driver Dummy"
    case $name in audio_track|audiotracks) flag="--position -30000,-30000" ;; esac   # their sync bars need the real driver
    case " $TOPLEVEL " in *" $name "*) ;; *) [ -n "$HOSTWID" ] && flag="--wid $HOSTWID $flag" ;; esac
  fi
  log="$LOGS/$name.log"
  t0=$(date +%s)
  lim=${TIMEOUT:-400}; sl=$(echo " $SLOW " | grep -o " $name=[0-9]*" | cut -d= -f2); [ -n "$sl" ] && [ "$sl" -gt "$lim" ] && lim=$sl
  # a SCRIPT ERROR inside a test's _init stops the script before quit(): Godot would sit there until the timeout.
  # So: watch the log; on a script error give it 5 s, then stop it (the suite FAILS either way); past $TIMEOUT, stop it
  "$G" $flag --path . -s "$f" > "$log" 2>&1 &
  pid=$!; why=""; seen=0
  while kill -0 $pid 2>/dev/null; do
    sleep 1
    el=$(( $(date +%s) - t0 ))
    if [ $seen -eq 0 ] && grep -q "SCRIPT ERROR" "$log"; then seen=$el; fi
    if [ $seen -gt 0 ] && [ $((el - seen)) -ge 5 ]; then why="stopped after a script error"; kill $pid 2>/dev/null; break; fi
    if [ $el -ge $lim ]; then why="TIMEOUT ${lim}s"; kill $pid 2>/dev/null; break; fi
  done
  wait $pid 2>/dev/null
  code=$?
  [ -n "$why" ] && code=124
  t=$(( $(date +%s) - t0 ))
  oks=$(grep -c "^ok" "$log"); fails=$(grep -cE "^FAIL([^S]|$)|^[A-Z_ ]+ FAIL" "$log"); errs=$(grep -c "SCRIPT ERROR" "$log")
  verdict=PASS
  if [ $code -ne 0 ] || [ "$fails" -gt 0 ] || [ "$errs" -gt 0 ]; then verdict=FAIL; bad=$((bad+1)); fi
  n=$((n+1))
  printf "%-4s %-15s ok %-4s fail %-3s script-errors %-3s exit %-3s %4ss %s\n" $verdict "$name" "$oks" "$fails" "$errs" $code $t "$why"
done
echo "SUITES $((n-bad))/$n PASS   (logs: $LOGS)"
exit $bad
EXTRA="$EXTRA modelfix3:w"   # round 3 walk: UV editor / Materials / ViewCube layout, knife misses, mirror centre, Z readout, export as a prop
EXTRA="$EXTRA walk8_beginner:w"   # walk-through round 8: eight beginner goals in Easy mode, real clicks (tests/walk8_beginner_test.gd)
EXTRA="$EXTRA walk9_beginner:w"   # walk-through round 9: six beginner goals in Easy mode, real clicks (tests/walk9_beginner_test.gd)
EXTRA="$EXTRA extrudeflow:w"   # walk 4 friction 7: Extrude / Inset buttons apply at once; E drag confirms on release
EXTRA="$EXTRA modelview4:w"   # walk-through 4 goal 1: MODEL orbit under the floor, Ctrl+Numpad7 bottom view, Numpad . frame selected
EXTRA="$EXTRA realism_lazy:w"   # I16 lazy gains: the panel predicts no gain until "Find the biggest gain" (tests/realism_lazy_test.gd)
EXTRA="$EXTRA walk_model5:w"   # walk-through 5: chair, mirror, subdivide + decimate, knife, UV, fill, separate / join, rename + save + reopen (tests/walk_model5_test.gd)
EXTRA="$EXTRA modelfix5:w"   # walk-through 5 friction 1: Enter in the search box runs the shown top row (Model row names it), not the typed words (tests/modelfix5_test.gd)
EXTRA="$EXTRA modelfix6:w"   # walk-through 5 frictions A + B: Alt+F / F / Alt+F with nothing selected close the hole in one undo step; F2 name box gives the keys back on Enter / Esc (tests/modelfix6_test.gd)
EXTRA="$EXTRA meshsave:w"   # MODEL mesh file: Ctrl+S saves the mesh (name box once, then silent), Open... loads one, F3 "save mesh" (tests/meshsave_test.gd)
EXTRA="$EXTRA walk10_beginner:w"   # monkey test round 10: wave, chair + sit, colour/look, play, save scene + video in Easy mode (tests/walk10_beginner_test.gd)
EXTRA="$EXTRA walk11_beginner:w"   # monkey test round 11: typed moves in Easy (jump twice, turn around, slower, typo, punch left, undo twice) (tests/walk11_beginner_test.gd)
EXTRA="$EXTRA walk_model6:w"   # walk-through 6: table (flatten, legs), bevel the top rim, wood material from the library, cylinder onto the table, undo x3 / redo x3, the table as a prop (tests/walk_model6_test.gd)
EXTRA="$EXTRA longplay:w"   # LONG PLAY: the 61-card axe clip at 30 ms median, the playhead in real time, served frames = live (tests/longplay_test.gd)
EXTRA="$EXTRA meshprop:w"   # MESH AS A PROP: MODEL > Use in scene (one undo step, POSE shows it), the scene saved and loaded with it, a saved mesh under Add prop and My models (tests/meshprop_test.gd)
EXTRA="$EXTRA turn:h"   # the turns on the spot: turn around 180, left / right 90 bars on templates/turn_*.json (tests/turn_test.gd)
EXTRA="$EXTRA fixall:w"   # FIX ALL: one button applies every Check fix in order, one undo step (tests/fixall_test.gd)
EXTRA="$EXTRA testfiles:h"   # TEST FILES: a run removes its own zz_* / autosave_test_* / pid-named leftovers under user:// (scripts/test_files.gd; tests/testfiles_test.gd)
EXTRA="$EXTRA handlock:w"   # HANDS: the weapon's hands row, Only the part I drag, Lock this part, the Easy side panel; a real mouse on the axe (tests/handlock_test.gd)
EXTRA="$EXTRA bladeturn:w"   # BLADE TURN / HEAD TILT: the weapon turned inside its hand, the Expert sliders and buttons, the Easy side slider (tests/bladeturn_test.gd)
EXTRA="$EXTRA scenecat:w"   # EASY MY SCENES CATALOG (scripts/scene_cat.gd, scripts/easy_scenes.gd): chips, quality badges, Hide weird ones, stars
EXTRA="$EXTRA expertcat:w"   # EXPERT "Open a scene" = the Easy catalog (scripts/easy_scenes.gd expert view): chips, badges, stars, List view (tests/expertcat_test.gd)
EXTRA="$EXTRA meshclean:w"   # MESH CLEAN-UP (Expert MODEL / SCULPT / SURFACE): hands strip on pose pages only, MODEL panels on MODEL, the body opens by itself and is applied on leaving (tests/meshclean_test.gd)
EXTRA="$EXTRA screenlimits:w"   # SCREEN LIMITS (tests/screenlimits_test.gd): every visible control inside 1280 x 720, 1024 x 600 and 1024 x 576 on each page, the Help panel and Got it, the page bar, the Weight paint popover
EXTRA="$EXTRA startscreen:w"   # THE START SCREEN: New project cards (art from the real body), Open tiles, filters, search, Resume, fit at 1280 x 720 and 1024 x 600 (tests/startscreen_test.gd)

EXTRA="$EXTRA sculptnative:w"   # first GDExtension pilot: native KineSculptNative vs GDScript sculpt (tests/sculptnative_test.gd; SKIPs the native bars without the DLL)
EXTRA="$EXTRA perfpresets:w"   # GRAPHICS QUALITY: Auto/Low/Medium/High presets, auto-detect, override.cfg, survives a restart (scripts/quality.gd; tests/perfpresets_test.gd)
EXTRA="$EXTRA cad:w"   # CAD kernel pilot: KineCAD (Open CASCADE) via scripts/kcad.gd: box - hole, fillet, shell, tessellate, STEP (tests/cad_test.gd; SKIPs without the DLL)
EXTRA="$EXTRA crashcheck:w"   # CRASH CHECK: every realism option + every Fix + Fix all on the owner scene, real clicks, 0 script errors, one undo step each, no stale timeline index (tests/crashcheck_test.gd)
EXTRA="$EXTRA lookd:w"   # THE BODY LOOK "D": clay token, sky outline, soft lights + SSAO, pick tint over the outline, FPS (tests/lookd_test.gd)
EXTRA="$EXTRA crashrep:w"   # CRASH REPORT (CG8, P25): the last 20 palette commands with their page in a scrubbed text file; kill -> offered at next start; clean quit -> nothing kept (tests/crashrep_test.gd)

EXTRA="$EXTRA animcpu:w"   # ANIMATE CPU (tests/animcpu_test.gd): a playing 6-clip scene <= 12 ms of main thread a frame, 50 clips >= 40 fps, poses bit for bit (tests/animcpu_golden.json), the timeline pixels equal a full redraw
EXTRA="$EXTRA build:h"   # BUILD mode phase 1 skeleton: the parametric Building record -> closed solid (4x3 room, door volume, scene save/load, collision boxes, mirror) (scripts/build/building.gd; tests/build_test.gd)
EXTRA="$EXTRA buildpage:w"   # BUILD page phase 1b: start card -> BUILD, drag a 4x3 room (live label), typed 4 Tab 3 Enter, door by click, slide, Delete, panel numbers, one undo step each, save + reopen (scripts/build/build_ui.gd; tests/buildpage_test.gd)
EXTRA="$EXTRA buildwords:w"   # BUILD WORDS phase 1e: a sentence -> plan cards -> Build it (30+ sentences, 8 edit phrases, refusals with Did you mean, one undo step each, real clicks and typing) (scripts/build/build_words.gd, build_words_ui.gd; tests/buildwords_test.gd)
EXTRA="$EXTRA blueprint:w"   # BUILD BLUEPRINTS phase 1g: plan per floor, front + side elevation, dimension strings, title block, SVG (exact, mm) / PNG (300 dpi) / DXF export; real clicks on the sheet (scripts/build/blueprint.gd, blueprint_ui.gd, blueprint_view.gd; tests/blueprint_test.gd)
EXTRA="$EXTRA libcat:w"   # OBJECT LIBRARY BY CATEGORY: left column (Recent, 6 built-in + 4 BUILD categories), big cards, search across all, BUILD pieces and the house, Easy text has no key names, reopen < 150 ms (scripts/object_library.gd, scripts/build/build_piece_kinds.gd; tests/libcat_test.gd)
EXTRA="$EXTRA houses:w"   # MY HOUSES: BUILD saves houses by name (JSON + picture under user://houses/), overwrite asks in-panel, the library lists them with pictures and a click puts one in the set (one undo step), Open house to edit, Rename, Delete to _trash, corrupt files skipped (scripts/build/houses.gd, houses_ui.gd; tests/houses_test.gd)
EXTRA="$EXTRA easybuild:w"   # EASY BUILDING: start screen Building -> Easy, big bar + left column (Room, Door, Window, + Floor, Roof, Stairs, Use in a scene), real clicks, no key names, no Expert ribbon, 1280x720 fit, Switch to Expert keeps the house (scripts/easy_build.gd; tests/easybuild_test.gd)
EXTRA="$EXTRA modelcards:w"   # MODEL TASK CARDS: "What do you want to do?" over MODEL (4 cards, Start reaches the tool, Show all the tools, Expert first open only, 1280x720 fit) (scripts/model_cards.gd; tests/modelcards_test.gd)
EXTRA="$EXTRA smoothbody:w"   # BODY: SMOOTH, the second body option (assets/body_smooth.glb): one undo step, mannequin byte-identical, pose / pick / paint, soles, elbow volume, the drawn face, Easy click
EXTRA="$EXTRA startbugs:w"   # start screen: modeling lands on MODEL, Home button, Easy/Expert start at once, Esc, Help in front, one save question
EXTRA="$EXTRA partws:w"   # EXPERT PART WORKSPACE phase 1 (Fusion style) on BUILD: Part button, sketch on a plane (rectangle 100x20 by clicks + typed dims), Extrude 5 mm = 1e-5 m3, Fillet one picked edge, timeline edit to 120 mm replays (fillet survives), Revolve analytic, undo/redo each step, save + reopen, 1280x720 layout, no-DLL greyed, sword shots (scripts/build/part.gd, part_ui.gd; needs the CAD DLL)
EXTRA="$EXTRA buildchoose:w"   # WHAT DO YOU WANT TO BUILD?: chooser over BUILD (6 cards, Easy / Expert start in one click, greyed cards say why, Prop pack opens the library, reopen button, fit) (scripts/build_choose.gd; tests/buildchoose_test.gd)
EXTRA="$EXTRA checkhunt:w"   # CHECK PAGE FREEZE HUNT: real clicks on the CHECK tools with frame times; Check in time slices (cancel on re-click), the timing database read a few scenes per frame, Polish on a worker thread, a 60 s scene; findings identical to the plain Rulebook.check (tests/checkhunt_test.gd; driver tests/checkhunt_drv.gd)
EXTRA="$EXTRA mocapq:h"   # MOCAP QUALITY: jitter / skate / pen / flips / speed bars on fixed keypoint fixtures
EXTRA="$EXTRA easypart:w"   # EASY PART: templates sword/axe/shield/chair/crate as parametric Part records, "Change your sword" panel (chips, sliders throttled 100 ms, one undo step per release), amber drag dots, six big buttons, Expert opens the same record, no key names, 1280x720 fit, no-DLL greyed (scripts/easy_part.gd, scripts/build/part_templates.gd; tests/easypart_test.gd; needs the CAD DLL)
EXTRA="$EXTRA cadmass:w"   # PART -> WEAPON: a Part becomes the fighter's weapon (Give it to the fighter, Easy and Expert): steel bar mass and centre, the sword's numbers, the torque judge follows the Part, the hand on the grip, a shot (tests/cadmass_test.gd; needs the CAD DLL)
EXTRA="$EXTRA checkribbon:w"   # CHECK ribbon: 8 captioned groups, <= 20 icons, every one of the 40 tools by real clicks (icon or caption menu), 1280x720 + 1600x900 (tests/checkribbon_test.gd)
EXTRA="$EXTRA walk6_beginner:w"   # BEGINNER WALK 6: start screen -> 3D BUILDING -> chooser -> house in Easy, Part in Easy, Part in Expert, Use in a scene, back; 10 goals by real clicks on visible controls, KNOWN goals reported (not failed), FAIL only on regression; shots C:/Temp/claude/walk6/ (tests/walk6_beginner_test.gd)
EXTRA="$EXTRA doorfit:w"   # BUILD B2: a doorway shorter than the fighter (stature + 5 cm) is flagged on STAGE: the walk is refused and the button says "(too low)"; tests/doorfit_test.gd
EXTRA="$EXTRA realismslice:w"   # REALISM / TIMING COACH SLICES: the scene database and the coach suggestions in slices (window keeps drawing, longest frame < 100 ms on combo3), the score in stages, same numbers as the blocking call, a second click cancels (tests/realismslice_test.gd)
EXTRA="$EXTRA vehicle:w"   # B3 VEHICLE: a car body (box) + four wheels (revolve of a tyre about the axle); wheel angle = distance / r on a straight 10 m and a curved path, pivots read back, wheels and body share no KCad volume, 5 cm overlap control, wheelbase axles; the Easy car screen (scripts/easy_vehicle.gd): sliders with one undo step per release, Drive it (wheels turn, contact), Use in a scene, 1280x720 (scripts/vehicle.gd; tests/vehicle_test.gd; needs the CAD DLL)
EXTRA="$EXTRA starters:w"   # B1 starter buildings in the Template card (scripts/build/build_starters.gd)
EXTRA="$EXTRA ribbonmesh:w"   # RIBBON STANDARD on MODEL / SCULPT / SURFACE: icon-only groups with captions, <= 20 icons, nothing in More, every old tool by real clicks at 1280x720 + 1600x900 (tests/ribbonmesh_test.gd)
EXTRA="$EXTRA ribbonsd:w"   # STAGE + DELIVER ribbons: the POSE/ANIMATE standard (captioned groups, 9-20 icons, nothing in More, every tool by real clicks), 1280x720 + 1600x900 (tests/ribbonsd_test.gd)
EXTRA="$EXTRA remesh:h"   # M1 VOXEL REMESH: a closed mesh to an even quad mesh (surface nets + QEF on the banded field): volume within 2 % (sphere, torus, block ring), closed and manifold, quad count within 10 % of 1.5 A / h^2, undo (tests/remesh_test.gd)
EXTRA="$EXTRA constraints_breadth:h"   # A2 CONSTRAINT BREADTH: copy location, copy rotation (Offset), damped track, limit location; the bars and the file round trip (tests/constraints_breadth_test.gd)
EXTRA="$EXTRA hdri:w"   # CG2: a .hdr / .exr picture as the sky and the light (scripts/shading.gd; tests/hdri_test.gd)
EXTRA="$EXTRA bodydims:w"   # C2 BODY-DRIVEN DIMENSIONS: a sketch dimension typed =forearm+4 reads the body (forearm length + 4 mm), the solid follows a taller body, no body / unknown measure = an error; a 190 cm body on the BUILD page moves the sketch (tests/bodydims_test.gd; needs the CAD DLL)
EXTRA="$EXTRA instancing:w"   # M3 INSTANCING: 200 still copies of a 5k-face model drawn as one MultiMeshInstance3D (>= 60 fps, 1 draw call, memory <= 1.5x), the app's "Copies in a row" (scripts/prop_instances.gd; tests/instancing_test.gd)
EXTRA="$EXTRA physlane:w"   # A1 MAKE IT PHYSICAL lane: a priority card ("Keep this pose") is untouched by Make it physical and kept by Accept span, a fix drops the red span count, blue = edited since the judge, gray = not processed (tests/physlane_test.gd)
EXTRA="$EXTRA renderq:w"   # CG4 render queue: scene files in order (glb/bvh/fbx), each job timed in its log line, a broken job named and skipped, the batch dialog shows the times; tests/renderq_test.gd
EXTRA="$EXTRA hinge:w"   # C3 HINGE: a Part hinge turns a leaf about an axis by a curve; hinge_sweep reports the first frame it meets the stop (tests/hinge_test.gd; needs the CAD DLL, no-DLL bar still runs)
EXTRA="$EXTRA arenafit:w"   # ARENA FIT (ROADMAP I1): a 3 m and a 5 m ring against a measured 3.40 m fight: the wall, the room in metres and steps, the panel words (tests/arenafit_test.gd)
EXTRA="$EXTRA impactcurve:w"   # I3 IMPACT FEEL CURVES: each blow of two fighters (its impulse J) exports a rumble event beside the .glb (<name>_impact_feel.json): strength = J/25 N s clamped to 0..1, length = the impact shake; the status line names the hit count
EXTRA="$EXTRA carpkg:w"   # VEHICLE STEP 1 PACKAGE + STEP 6 COMPARE: hard points (sliders / typed mm), side + top layout, 3D preview, tyre 225/45R17 -> diameter, class start from real cars, Yours vs real cars (nearest car, red rows) (scripts/car_package.gd, car_plan.gd, package_screen.gd; tests/carpkg_test.gd)
EXTRA="$EXTRA carchassis:w"   # VEHICLE STEP 2 CHASSIS: step bar (1 Package, 2 Chassis, rest greyed), steel floor structure from the package (sills, rails, crossmembers as box sections), mass / I / E I readouts, materials, drawn over the views and in 3D (scripts/car_chassis.gd; tests/carchassis_test.gd)
EXTRA="$EXTRA carsusp:w"   # VEHICLE STEP 3 SUSPENSION: front MacPherson or double wishbone, rear twist beam or multilink; hard points, readouts (camber, KPI, scrub, caster, trail, roll centre) with typical ranges, Bounce +-80 mm (links kept), clearance to the chassis; step 3 live in the step bar (scripts/car_susp.gd, car_susp_plan.gd, package_screen.gd; tests/carsusp_test.gd)
EXTRA="$EXTRA carweight:w"   # VEHICLE STEP 4 WEIGHT AND BALANCE: parts as blocks on the side and top views (drag, one undo step each), axle loads, left / right, CG height, corners, compare with real cars (red), estimates in data/car_parts.json, 3D blocks and CG sphere (scripts/car_weight.gd, car_weight_plan.gd, package_screen.gd; tests/carweight_test.gd)
EXTRA="$EXTRA monkeywalk:w"   # MONKEY WALK (Easy): real clicks through the start screen, BUILD cards, vehicle steps, Easy bar; errors, key words, back, fit, overlap, dead buttons; FINDINGS in C:/Temp/claude/monkeywalk (tests/monkeywalk_test.gd)
EXTRA="$EXTRA mocapspeed:h"   # MOCAP SPEED: the linear card sample memo + the plants-stage timing, same tracks as the old path (tests/mocapspeed_test.gd)
EXTRA="$EXTRA pspline:h"   # GAP 1 SPLINE: a sketch Spline (click points, close on the first, drag a point) in the Part record and the Expert SKETCH ribbon; closed ring extrudes closed, one undo step, file round trip (tests/pspline_test.gd; needs the CAD DLL)
EXTRA="$EXTRA psplit:h"   # GAP 4 + 7: split by a plane, intersect op, shell (open face), extrude taper (tests/psplit_test.gd)
EXTRA="$EXTRA ploft:w"   # GAP 2 LOFT: a loft of two sketches (one on an Offset plane typed 50 mm) by real ribbon clicks, one undo step, closed mesh, smooth 3-profile record, save and reload (tests/ploft_test.gd; needs the CAD DLL)
EXTRA="$EXTRA pcanvas:w"   # GAP 3 CANVAS: a reference picture on the Front plane in Part (Canvas, two clicks + typed mm, OK = one undo, drag, hide, opacity, saved in the record, 1 mm line-up at 1280x720); tests/pcanvas_test.gd; needs the CAD DLL
EXTRA="$EXTRA pappear:w"   # GAP 5 APPEARANCE: per-body colour chips, picker and Paint / Metal / Glass / Rubber / Plastic in the record (appear step) and the Appearance tool; glass shows the body behind it, split bodies differ (tests/pappear_test.gd; needs the CAD DLL)
EXTRA="$EXTRA pmeasure:w"   # GAP 8 MEASURE + SECTION: measure distance, edge length and face area by real clicks (no undo), section cut with a filled cap on the Part solid (tests/pmeasure_test.gd)
EXTRA="$EXTRA psweep:w"   # GAP 6 SWEEP: a 20 mm circle along a line + tangent arc path (volume = pi r^2 L within 1 percent), straight equals extrude, kinked path, closed mesh, real ribbon clicks, one undo, save and reload (tests/psweep_test.gd)
EXTRA="$EXTRA peasy2:w"   # EASY PEASY2: Easy Part gets Curvy line (drag a loop = closed spline), Blend two shapes (loft of the two last sketches), Cut in two (split across the middle, drag slider), Colour (5 chips + Glass / Metal): real clicks, one undo step each, no key names (tests/peasy2_test.gd)
EXTRA="$EXTRA ppattern:w"   # GAP 30 PATTERN: a linear row (count, spacing mm, X/Y/Z) or a circular pattern (count, axis X/Y/Z through the origin, total angle) of a body, Join or New bodies, live preview; 100 mm cube x3 = 3 bodies 3e-3 m3, 6 copies of a 20 mm cube round Y 100 mm off the axis, one undo, save and reload, real clicks (tests/ppattern_test.gd; needs the CAD DLL)
EXTRA="$EXTRA pcombine:w"   # GAP COMBINE (Fusion Combine): a target body and tool bodies, Join / Cut / Intersect, keep tools, by view clicks and browser rows; record step combine, one undo step, save and reload (tests/pcombine_test.gd; needs the CAD DLL)
EXTRA="$EXTRA pconstr:w"   # GAP 9 CONSTRAINTS: sketch Horizontal, Vertical, Coincident, Parallel, Perpendicular, Equal and Angle from the Constrain row; a square stays square on a drag, the angle holds, a conflict is refused in words (tests/pconstr_test.gd; needs the CAD DLL)
EXTRA="$EXTRA peasy3:w"   # EASY PEASY3: Easy Part gets Repeat it (a row or ring of the newest solid, How many 2..12 and Gap sliders, one undo step each) and Stick together (click two pieces, Join / Cut away / Keep the overlap; refused in words): real clicks, no key names, layout at 1280x720 (tests/peasy3_test.gd; needs the CAD DLL)
EXTRA="$EXTRA pcube:w"   # PCUBE: Part side panels (Extrude, Pattern, Combine, Sweep, Appearance, Measure) never under the ViewCube or its menus at 1280x720 and 1600x900; the cube turns the view by a click (tests/pcube_test.gd)
EXTRA="$EXTRA ewalk:w"   # EWALK: a first-time walk of Easy Part, all twelve MAKE buttons by real clicks at 1280x720: the animate panel is not over Easy Part, the solid-first refusals say to Pull it up, Spin it round says to draw a new shape, every button answers (tests/ewalk_test.gd; needs the CAD DLL)
EXTRA="$EXTRA pface:w"   # GAP 10 OFFSET FACE + DRAFT: Offset face (+2 mm on a 100 mm cube top = 102 mm, 1.02e-3 m3; -2 = 98 mm) and Draft (5 deg on a side wall of a 100x60x40 extrude) from the Part MODIFY caption, picked by real clicks, one undo each, save and reload (tests/pface_test.gd; needs the CAD DLL)
EXTRA="$EXTRA epick:w"   # EPICK: Easy Part Stick together picks a piece within 12 px of a click (a 3 mm plate hit 8 px off picks it, glow + "Now click the other piece"); Mirror that with a gap says "Push them together with Stick together" (tests/epick_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eframe:w"   # EFRAME: Easy Part frames a small part: a 3 mm x 20 mm plate fills 40-70% of the free view after it is made (the camera eases, never moves on a small nudge or in Expert) (tests/eframe_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ewalk2:w"   # EWALK2: Easy Part mirror with a gap shows its whole words clear of the Change your part panel, Cut a hole says "straight through", the gap status says "Stick together joins them" (tests/ewalk2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eface:w"   # EFACE: Easy Part draws on a flat face of a solid (a press with Draw shape or Curvy line on a face within 5 deg of +-X/+-Y/+-Z puts the sketch on it: one plane feature, one undo step); Pull it up goes outward from the face and joins (tests/eface_test.gd; needs the CAD DLL)
EXTRA="$EXTRA efloor:w"   # EFLOOR: Easy Part empty-space sketches (Draw shape, Curvy line) go on the FLOOR: Pull it up goes UP (box y 0 .. pull), Cut a hole goes down through it, Spin / Blend / Repeat / Mirror / Cut in two still make valid solids, a leg on the floor top pulls DOWN (tests/efloor_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ehollow:w"   # EHOLLOW: Easy Part Cut a hole offers Through (default) or Hollow inside (Part shell, open at the top, Wall slider 1-10 mm; a too-thin body refuses in words, no undo step) (tests/ehollow_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ewalk3:w"   # EWALK3: Easy Part refusals name the next press: Pull it up on an open curve says drag back to the start to close it, Round the edges on a body too small says Pull it up taller, Blend two shapes that cannot loft says draw both as closed shapes (tests/ewalk3_test.gd; needs the CAD DLL)
EXTRA="$EXTRA etri:w"   # ETRI: Easy Part Draw shape has a Pointy chip (a triangle: the drag is the box corner to corner, the point at the far edge middle); on the floor it pulls to half the box area x 20 mm, and a Pointy on a box front face pulled into the house makes a house (tests/etri_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eside:w"   # ESIDE: Easy Part draws UPRIGHT through the middle when the camera looks side-on (|pitch| < 25): a closed Curvy loop on the wall makes a handle, Pull it up goes both ways and joins, centred; looking down still draws on the floor (tests/eside_test.gd; needs the CAD DLL)
EXTRA="$EXTRA myparts:w"   # MY PARTS: a part made in Easy Part, Use in a scene saves it to My parts (user://parts store, picture), the library card puts it in the set (one undo step), Use in a scene again replaces it (tests/myparts_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ehandle:w"   # EHANDLE: Cut a hole goes THROUGH the newest piece (a handle pulled upright or on a face): centred on its sticking-out part, the mug wall untouched, one undo, the slider; a plain floor body keeps its vertical hole (tests/ehandle_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ebowl:w"   # EBOWL: Easy Part bowl by clicks (a closed Curvy profile on the middle line spins into a bowl on the floor, hollow), Draw shape starts on Box, a drag under the words bar draws (tests/ebowl_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eempty:w"
EXTRA="$EXTRA efar:w"   # EFAR: Easy Part far-floor presses: a drag that starts on the words pill (under the far floor) still draws a box or a curve; a press that goes off Mirror and back is no click, a plain click still mirrors (tests/efar_test.gd; needs the CAD DLL)
EXTRA="$EXTRA edoor:w"   # EDOOR: Cut a hole cuts the DRAWN shape (a Box on a face, not yet pulled) through its wall: a door or window, depth by the slider, one undo (tests/edoor_test.gd; needs the CAD DLL)
EXTRA="$EXTRA erepeat:w"   # EREPEAT: Easy Part Repeat it gets a Corners chip: the newest piece goes to the four corners of the seat it sits on, one body, one undo step (tests/erepeat_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eround:w"   # EROUND: Easy Part Round the edges on a part of 25+ steps (real clicks): the press takes under 2 s, no failed step, one undo step (tests/eround_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nfillet:w"   # NFILLET: Easy Part rounds and blends survive a size change: a round too big for its edges shrinks and says so (3), a blend is not overwritten by a slider (4, 5) (tests/nfillet_test.gd; needs the CAD DLL)
EXTRA="$EXTRA xfix:w"   # XFIX: EXPERT Part frictions: a short Circle drag cancels in words (Drag further to set the size, no half circle); a new Extrude on a body face with its shape inside opens on Cut and says why; two separate loops in one sketch extrude / cut as two profiles at once (tests/xfix_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eseat:w"   # ESEAT: Easy Part dead ends from the ewalk5 walk: a seat on the leg tops pulls UP 4 cm (440 mm), an upright Pointy above a box is a roof, a Curvy line on the middle line says Spin it round (tests/eseat_test.gd; needs the CAD DLL)
EXTRA="$EXTRA clash_stall:w"   # STALL: the B24 clash job split into one-step set-up slices gives the same result (a digest of every frame and part) on the elbow scene and the ROM test (tests/clash_stall_test.gd)
EXTRA="$EXTRA corners:w"   # CORNERS: Easy Part Repeat it, Corners: the leg goes to the four corners of a seat not at the origin, and the How many / Gap sliders hide for Corners (tests/corners_test.gd; needs the CAD DLL)
EXTRA="$EXTRA xfix2:w"   # XFIX2: EXPERT Part readouts and refusals: a drawn line / rectangle / circle reads its snapped size next to the cursor ("snapped to 5 mm"); a click on a greyed tool or Finish says why; a flat rectangle, a line onto its own start, a Fillet click on no edge each say why; the Undid toast goes at the next action (tests/xfix2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA xwalk2:w"   # XWALK2: a beginner walk of EXPERT Part from the start screen: a phone stand (angled slot, fillet), a gear blank (circular pattern of a pin, Combine by clicks, hub), a hinge leaf (plate, three holes in a row, chamfer); KNOWN dead ends: slot opens on Join, a 2 mm circle snaps away, Combine picks (tests/xwalk2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nchaos2:w"   # nchaos2: minimal repros of the Easy Part chaos monkey (empty part record {} crash)
EXTRA="$EXTRA ecolour:w"   # ECOLOUR: Easy Part colour: Red on one piece, Blue on the whole part, Ctrl+Z steps back through both; the red survives Use in a scene (the prop is drawn red) and My parts (the record reopens red, the picture is reddish) (tests/ecolour_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ewords:w"   # EWORDS: every string Easy Part shows in a 40-press session is plain words (no sketch, profile, extrude, fillet, body ...): real clicks on every button (tests/ewords_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eblend:w"   # EBLEND: Easy Part Blend two shapes for a beginner: a round base and a square top blend into ONE solid (vase); two shapes on faces at an angle are refused in words, no empty loft (tests/eblend_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ecut2:w"   # ECUT2: Easy Part Cut in two keeps ONE half: Keep the lower half / Keep the upper half chips after a Cut in two (one undo step each), Keep both halves back, the cut slider still moves it (tests/ecut2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA emirror:w"   # EMIRROR: Easy Part Mirror that on a piece off the middle line: the mirror goes across the middle of the PART, one body, the piece keeps its place, no Stick together words (tests/emirror_test.gd; needs the CAD DLL)
EXTRA="$EXTRA estick:w"   # ESTICK: Easy Part Stick together on two pieces made apart: touching pieces join to one solid (one undo step, undo and redo), pieces that do not touch are refused in words that say to move one (tests/estick_test.gd; needs the CAD DLL)
EXTRA="$EXTRA esave:w"   # ESAVE: a mug made in Easy Part, Use in a scene saves it, a new Empty part, the mug reopened from My parts (Change the part): identical, and its slider works (tests/esave_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eundo:w"   # EUNDO: Easy Part: every MAKE button and chip pressed once (real clicks): each press is one undo step, Undo all and Redo all restore each part identically (tests/eundo_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ekeys:w"   # EKEYS: Easy Part keyboard: Ctrl+Z / Ctrl+Y undo and redo, Escape cancels a drag or a half-drawn shape, Delete removes the newest piece as one undo step (tests/ekeys_test.gd; needs the CAD DLL)
EXTRA="$EXTRA escene:w"   # ESCENE: an Easy Part made by clicks, Use in a scene: a part prop on the floor at its real size, selected and moved by real clicks, and back after a scene save and load (tests/escene_test.gd; needs the CAD DLL)
EXTRA="$EXTRA xdim:w"   # XDIM: EXPERT Part typed exact sizes: a typed 40x30 rectangle and a typed radius 12 circle (Enter), a length typed before a start says so, "0" says above 0, the sketch size field says what to type and reads 4 cm (tests/xdim_test.gd; needs the CAD DLL)
EXTRA="$EXTRA xtime:w"   # XTIME: EXPERT Part timeline: edit an earlier extrude depth (the later steps replay), Suppress a step (skipped, Undo brings it back), Delete a step in the middle (the later step says in plain words that its sketch was deleted), Undo (tests/xtime_test.gd; needs the CAD DLL)
EXTRA="$EXTRA xchaos:w"   # XCHAOS: chaos monkey for EXPERT Part: 600 seeded real inputs (tools, sketch clicks and drags, dialogs, timeline, undo, keys) x seeds 1-5; no SCRIPT ERROR, no push_error, no negative volume (tests/xchaos_test.gd; needs the CAD DLL)
EXTRA="$EXTRA startwalk:w"   # STARTWALK: a beginner from the start screen to a first saved scene (real clicks at 1280x720; dead ends listed) (tests/startwalk_test.gd)
EXTRA="$EXTRA checkwalk:w"   # CHECKWALK: a beginner walk of the CHECK page from the start screen (ANIMATION card), every one of the 41 tools by real clicks: each says a line, KNOWN dead ends pinned (silent Dummy / Frame data / Frame boxes, Check says Enter to add the body, Escape leaves MY COMBOS up) (tests/checkwalk_test.gd)
EXTRA="$EXTRA stagewalk:w"   # STAGEWALK: a beginner walk on the STAGE page at 1280x720 from the real start screen (Expert > Animation): a second fighter typed into Search, a chair from Library, a shot camera, Play; KNOWN dead ends are bars that print KNOWN until fixed (tests/stagewalk_test.gd)
EXTRA="$EXTRA nchaos3:w"   # NCHAOS3: Easy Part chaos monkey repro (seed 17): Cut a hole, Undo, an Expert rectangle takes the hole's id; back on Easy the stale hole slider is dropped, no script error, its rows follow the record (tests/nchaos3_test.gd; needs the CAD DLL)
EXTRA="$EXTRA etable:w"   # ETABLE: a top drawn from the TOP view on the leg tops (press on the leg top) is pulled UP and stands on the legs: 440 mm, not pulled into them (tests/etable_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eblade:w"   # EBLADE: a 60 cm x 5 mm blade drawn on the floor by real drags draws (its 5 mm side snaps to one grid line, the raw side is kept), a 2 cm wide retry draws, a refused drag says "at least 2 mm" (tests/eblade_test.gd; needs the CAD DLL)
EXTRA="$EXTRA elamp:w"   # ELAMP: a lamp from the ewalk6 walk: a Curvy shade drawn on a stick top (400 mm) and Spin it round stays at its drawn height (520 mm lamp), not pushed to the floor (tests/elamp_test.gd; needs the CAD DLL)
EXTRA="$EXTRA eback:w"   # EBACK: the ewalk6 walk from the start screen: Round the edges default is not below the slider (1 mm+), Use in a scene goes to STAGE with a "Back to your part" button that reopens Easy Part on the same part (tests/eback_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ehelp:w"   # EHELP: Easy Part first steps: Empty says one line (Draw shape, then drag); Pull it up, Spin, Round, Cut a hole, Mirror, Blend name the next button (tests/ehelp_test.gd)
EXTRA="$EXTRA ehelp2:w"   # EHELP2: the same first steps in plain words (no body / sketch / profile / extrude / fillet): Pull it up and Mirror that name the next button (tests/ehelp2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA deadcode:w"   # DEADCODE: Easy Part still works after its unused functions were removed: opens from the start screen, one template chip makes a part as one undo step, undo and redo restore it (tests/deadcode_test.gd; needs the CAD DLL)
EXTRA="$EXTRA animwalk:w"   # ANIMWALK: a beginner, real clicks from the start screen: Easy, type a punch, drag the time slider, type a left punch, one Undo (tests/animwalk_test.gd)
EXTRA="$EXTRA deliverwalk:w"   # DELIVERWALK: the chair set piece as OBJ and GLB, and the posed fighter as OBJ, from the DELIVER page by real clicks: sizes and vertex counts match on re-import; the body in the export list carries the held weapon at its place (tests/deliverwalk_test.gd)
EXTRA="$EXTRA efighter:w"   # EFIGHTER: Easy Part "Give to fighter" with the sword template: in the right hand, grip in the palm, blade forward, through a punch clip (tests/efighter_test.gd; needs the CAD DLL)
EXTRA="$EXTRA efighter2:w"   # EFIGHTER2: the sword given to the fighter and thrown through the Easy punch: the blade stays in front (no backward tip, sampled every 0.05 s), at rest forward, and out of the body (tests/efighter2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA replaygap2:w"   # REPLAYGAP2: real Easy Part presses (30 steps from the start screen): no record is replayed twice in one press; volume, bodies, errors and features equal the baseline recorded before the fix (tests/replaygap2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA freebuild:w"   # FREEBUILD: the BUILDING card opens a free Easy Part (an empty part, Part N), no chooser and no House name; a house is in What to build (tests/freebuild_test.gd)
EXTRA="$EXTRA videowalk:w"   # VIDEOWALK: a beginner makes a move from a video by real clicks: a card click names its words, + Add pose keeps names unique, Cut end while playing is refused (tests/videowalk_test.gd)
EXTRA="$EXTRA bodywalk:w"   # BODYWALK: a beginner from the start screen: MODELING, BODY tall thin and short heavy by track clicks, a visible Face button (the panel fits 1280 x 720, no clips needed), a visible Hair button, the body-only fighter saves; 14 presses at most (tests/bodywalk_test.gd)
EXTRA="$EXTRA exportwalk:w"   # EXPORTWALK: a fighter walk from the start screen by real clicks (Easy, build walk, Expert, DELIVER, Export...): the FBX and the GLB (Unreal Engine 5, root motion) written to user:// and re-imported: bones, frames and root travel match, and the pre-flight drift is the file's (tests/exportwalk_test.gd)
EXTRA="$EXTRA scenewalk:w"   # SCENEWALK: a beginner saves three scenes from Easy, renames one, duplicates one, deletes one to the trash and puts it back, reopens each (tests/scenewalk_test.gd)
EXTRA="$EXTRA libchaos:w"   # LIBCHAOS: the object library chaos monkey, seeds 1..5 x 600 real inputs (clicks, drags, wheel, keys) from the start screen: no script error, undo depth not negative, the app answers; bars: loop-seam names (rulebook nice), AI address refused in words (tests/libchaos_test.gd)
EXTRA="$EXTRA freegrid:w"   # FREEGRID: the BUILDING card opens an empty Easy Part whose floor grid is centred in the free view and fills most of it, from a 3/4 view (GRIDFRAME; tests/freegrid_test.gd)
EXTRA="$EXTRA freewalk:w"   # FREEWALK: a beginner from the BUILDING card (Easy, empty part): the empty grid is on screen at open (D1), a drag with no tool names Draw shape (D3), after Cut a hole the solid is still on screen (D2) (tests/freewalk_test.gd)
EXTRA="$EXTRA freestart:w"   # FREESTART: a blank Easy Part starts EMPTY; the Start from row (Box, Cylinder, Sphere, Tube, Plate) by real clicks, each one closed solid; More examples opens What to build, the weapons are there (tests/freestart_test.gd)
EXTRA="$EXTRA fshelf:w"   # FSHELF: a wall shelf by real clicks from the BUILDING card (Easy, blank): a plate, two brackets, Repeat it for three shelves, Round the edges; jargon and hints checked (tests/fshelf_test.gd)
EXTRA="$EXTRA froom:w"   # FROOM: a beginner builds a small room from the BUILDING card by real clicks: floor plate, two 2 m walls, a table, a door cut and a window cut; dead ends are bars (tests/froom_test.gd)
EXTRA="$EXTRA fwords:w"   # FWORDS: on a blank part every shown word and tooltip is plain (no house/sword/weapon/fighter unless chosen, no sketch/extrude/fillet/boolean) (tests/fwords_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fexport:w"   # FEXPORT: a free BUILDING part (Easy Part, Draw shape, Pull it up) from the start screen, then DELIVER > Export...: the part is in the list, its OBJ and GLB sizes equal the part in mm (tests/fexport_test.gd)
EXTRA="$EXTRA fspeed:w"   # FSPEED: each Easy Part step (Draw, Pull, Round, Cut a hole, Cut in two, Repeat, Blend, Mirror) on a blank part: click to painted frame, median of 5 under 300 ms (tests/fspeed_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fpipe:w"   # FPIPE: a beginner from the BUILDING card: Round disc, Pull it up, Cut a hole (flange ring), an open Curvy line names the pipe step, Expert one click, Sweep tool dialog (tests/fpipe_test.gd)
EXTRA="$EXTRA fwrench:w"   # FWRENCH: a beginner builds a wrench from the BUILDING card by real clicks: a bar (draw, pull, round), a ring (round chip, pull, cut a hole), Join the ring, a jaw slot Cut away; each press says a line (tests/fwrench_test.gd)
EXTRA="$EXTRA fknob:w"   # FKNOB: a beginner from the BUILDING card (one click, Easy opens): a box plate on the grid, a round knob drawn on its top face and pulled up onto it, Mirror that makes the second knob; the card body opens Easy (tests/fknob_test.gd)
EXTRA="$EXTRA fkey:w"   # FKEY: a beginner from the BUILDING card builds a house key by real clicks: a head with a hole, a long blade, three teeth (tests/fkey_test.gd; needs the CAD DLL)
EXTRA="$EXTRA aundo3:w"   # AUNDO3: Easy undo from the start screen: 10 real-click edits (pose drags, cards, Faster/Slower, Bigger, card pick + Cut end, colour), Undo all and Redo all: each step comes back exactly (tests/aundo3_test.gd)
EXTRA="$EXTRA fsave:w"   # FSAVE: a free part from the BUILDING card, saved, Home, reopened from My parts, Undo/Redo across it, given to the fighter (tests/fsave_test.gd)
EXTRA="$EXTRA flamp4:w"   # FLAMP4: a beginner from the BUILDING card builds a floor lamp by real clicks: a round base (60 mm, 3 cm up), a pole 40 cm up on it, a Curvy shade spun round on the pole top; F4 Tilt it (20 degrees) is a dead end: no Tilt step in Easy Part (tests/flamp4_test.gd)
EXTRA="$EXTRA fbox:w"   # FBOX: a beginner from the BUILDING card: a floor box pulled up and hollowed open at the top, a lid on the rim that is a separate body slightly larger, a finger hole through the lid (tests/fbox_test.gd)
EXTRA="$EXTRA erepeatup:w"   # EREPEATUP: Easy Part Repeat it has Up and Forward beside Row: a plate repeated 3 times Up is three plates stacked (box 300 x 65 x 120 mm), by real clicks from the BUILDING card (tests/erepeatup_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fsign:w"   # FSIGN: a beginner from the BUILDING card builds a door sign by real clicks: a rounded plate, a screw hole, Mirror that = the second hole (tests/fsign_test.gd)
EXTRA="$EXTRA ftable2:w"   # FTABLE2: a beginner from the BUILDING card builds a round dining table by real clicks: round top, central post, cross foot, top coloured Wood (tests/ftable2_test.gd)
EXTRA="$EXTRA fphone:w"   # FPHONE: a beginner builds a phone stand from the BUILDING card: base plate, angled back (Blend), lip, cable cut, one Undo (tests/fphone_test.gd)
EXTRA="$EXTRA fchaos2:w"   # FCHAOS2: chaos monkey for EXPERT Part building from the BUILDING card: seeds 41..50 x 600 real inputs (clicks on every visible control, tools, sketch clicks and drags, typed numbers, Finish, undo / redo, keys, wheel, timeline); no script error, volume and undo depth never negative (tests/fchaos2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fbracket:w"   # FBRACKET: a beginner from the BUILDING card builds an L bracket by real clicks (plate, flange on the top face, Round the edges, Cut a hole); the second screw hole is refused in words that name Expert (tests/fbracket_test.gd)
EXTRA="$EXTRA fdelete:w"   # FDELETE: a beginner clicks one piece of a multi-piece part (a click picks it; Remove or the Delete key takes it out; Undo brings it back), and a joined piece on top of another (tests/fdelete_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fbowl2:w"   # FBOWL2: a beginner builds a salad bowl from the BUILDING card by real clicks: a closed profile with a foot ring and a wide rim spun round (one body, stands, rim 180+ mm, foot ring, hollow), Colour Wood (tests/fbowl2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fkettle:w"   # FKETTLE: a beginner builds a kettle from the BUILDING card by real clicks: Curvy loop, Spin it round (body), Curvy line spout + round disc + Sweep, a lid pulled up apart; the sweep dialog starts on the round shape and the open line (tests/fkettle_test.gd)
EXTRA="$EXTRA flamp:w"   # FLAMP: a beginner builds a desk lamp from the BUILDING card by real clicks: base, arm, shade; each part coloured on its own (tests/flamp_test.gd)
EXTRA="$EXTRA fwheel:w"   # FWHEEL: a beginner builds a wheel from the BUILDING card by real clicks: a spoke, Repeat it Ring round the middle, a disc, a hub, a tyre spun round (tests/fwheel_test.gd)
EXTRA="$EXTRA fundo2:w"   # FUNDO2: a beginner from the BUILDING card makes a 10-step part by real clicks; Undo all 10 and Redo all 10 by keys and by the bar buttons: each step comes back exactly (tests/fundo2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA ajump:w"   # AJUMP: a beginner from the start screen: a crate from Library, typed "jump over the crate" builds a run-up and a jump past it (the typed line was refused before); the clearance and the sinking feet are KNOWN dead ends (tests/ajump_test.gd)
EXTRA="$EXTRA fhelp3:w"   # FHELP3: a beginner from the BUILDING card presses every shown Easy Part button once on a blank part and once on a one-part state: each press changes something or says a line, no jargon (tests/fhelp3_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fdesk:w"   # FDESK: a beginner from the BUILDING card builds an office desk by real clicks: two side panels, a top on them, a drawer box (its own piece), a handle (tests/fdesk_test.gd)
EXTRA="$EXTRA fplanter:w"   # FPLANTER: a plant pot with a saucer, free building: round body drawn and pulled up, Hollow inside, a drain hole through the floor, a tapered pot, a separate saucer (tests/fplanter_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fcomb:w"   # FCOMB: a beginner builds a comb from the BUILDING card by real clicks: a tooth, Repeat it Row of 20 (How many reaches 20), a bar across the tooth bases, Round the edges (tests/fcomb_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fdup:w"   # FDUP: Easy Part Duplicate (a MAKE button, plain words): a second copy of the whole part beside it, one undo step, Undo takes it back (tests/fdup_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fcandle:w"   # FCANDLE: a beginner from the BUILDING card builds a candle holder by real clicks: a round base, a cup (Cut a hole, Hollow inside), a curved arm (Curvy line, Pull it up), Repeat it Ring for three (tests/fcandle_test.gd)
EXTRA="$EXTRA fmobile:w"   # FMOBILE: a beginner from the start screen (real clicks at 1280x720): the BUILDING card and every Easy Part panel at 1280x720, 1024x600, 1920x1080: no overlap, no cut-off, every button reachable (tests/fmobile_test.gd)
EXTRA="$EXTRA fmeasure:w"   # FMEASURE: a beginner builds a box from the BUILDING card by real clicks and reads its size on screen: a plain "Size: W x D x H cm" label under the part, no Expert (tests/fmeasure_test.gd)
EXTRA="$EXTRA fexpert2:w"   # FEXPERT2: the BUILDING card's blank part: Easy -> Expert (one click, same record), an exact 40 mm Pull in Expert, back to Easy with every step, plain words, keep editing, Undo (tests/fexpert2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fchaos1:w"   # FCHAOS1: chaos monkey on the BUILDING card's blank part, seeds 31-40, 600 real inputs each: no freeze over 2 s, the view never lost (tests/fchaos1_test.gd)
EXTRA="$EXTRA fdrone:w"   # FDRONE: free 3D building from the BUILDING card: a beginner builds a toy drone (flat body, an arm, a motor on its end, Repeat it Ring x5, Mirror that), real clicks at 1280x720 (tests/fdrone_test.gd)
EXTRA="$EXTRA awave:w"   # AWAVE: a beginner makes a wave from the start screen by real clicks (ANIMATION, the Wave picture), Play / Stop, Faster then Slower, Save video (an mp4 or frames), then types "wave" in a new scene; 7 bars (tests/awave_test.gd)
EXTRA="$EXTRA ascene2:w"   # ASCENE2: a beginner makes three scenes, renames one, duplicates one, deletes one to the trash and puts it back, reopens each; the text and card count of each scene survive every move (tests/ascene2_test.gd)
EXTRA="$EXTRA abody2:w"   # ABODY2: an easy body by real clicks from the start screen: height, build, face, hair, save, reopen from My scenes: every change kept (tests/abody2_test.gd)
EXTRA="$EXTRA fglasses:w"   # FGLASSES: a beginner from the BUILDING card builds a pair of glasses by real clicks: bridge, ring, Cut a hole, arm, Mirror that (tests/fglasses_test.gd)
EXTRA="$EXTRA fhandle:w"   # FHANDLE: a beginner from the BUILDING card builds a door handle by real clicks: a back plate, a closed Curvy loop pulled up as the lever (10 mm, from the plate top), Round the edges, Mirror that; one undo step (tests/fhandle_test.gd)
EXTRA="$EXTRA fmug3:w"   # FMUG3: a beginner from the BUILDING card builds a mug by real clicks: a round body, Cut a hole + Hollow inside, a handle box; the walk is counted in clicks, each step at most 3 (tests/fmug3_test.gd)
EXTRA="$EXTRA fspoon:w"   # FSPOON: a beginner from the BUILDING card builds a spoon by real clicks: an oval bowl (Blend two round shapes, Hollow inside), a long tapered handle (Blend), Round the edges on the whole (tests/fspoon_test.gd)
EXTRA="$EXTRA fglasses:w"   # FGLASSES: a beginner from the BUILDING card builds a pair of glasses by real clicks: bridge, ring, Cut a hole, arm, Mirror that (tests/fglasses_test.gd)
EXTRA="$EXTRA fflat:w"   # FFLAT: a beginner builds a flat-pack shelf unit from the BUILDING card: base shelf, Repeat it Up x4, two sides and a back pulled beside it, Stick together to one body (tests/fflat_test.gd)
EXTRA="$EXTRA fnamechange:w"   # FNAMECHANGE: the BUILDING card's blank part is named Part N; a click on its title opens a name box, Bracket + Enter renames it (undo / redo), Use in a scene puts Bracket in My parts (tests/fnamechange_test.gd)
EXTRA="$EXTRA fsnap:w"   # FSNAP: Draw shape snaps box corners to the 1 cm grid (plain drag = whole cm sides); Alt held = free; the snap words say once (tests/fsnap_test.gd)
EXTRA="$EXTRA aprop:w"   # APROP: a cup built in Easy Part (round, Pull, Cut a hole > Hollow inside), given to the character, used in a scene; it stays in the hand through a Walk card and in the scene; the hand panel names it; dead ends: a typed drink, Pick up in Easy (tests/aprop_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fbench:w"   # FBENCH: a park bench from the BUILDING card by real clicks: a base strip, a side frame, Mirror that copies it, a slat on the frames, Repeat it Forward (five slats), Round the edges (tests/fbench_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fframe:w"   # FFRAME: a picture frame from the BUILDING card by real clicks: outer rectangle pulled up, inner rectangle cut (Cut a hole), Round the edges, a stand under the back edge (tests/fframe_test.gd)
EXTRA="$EXTRA alib2:w"   # ALIB2: a beginner from the start screen (ANIMATION, Easy): Library, type chair, Furniture tile, drag the chair to the floor, Colour it, Ctrl+Z (tests/alib2_test.gd)
EXTRA="$EXTRA fruler:w"   # FRULER: a ruler 300 mm by real clicks from the BUILDING card: a tick cut into its top, Repeat it Row of the cut (12 copies, a pattern over the cut), then Expert: the same record, 300 mm (tests/fruler_test.gd)
EXTRA="$EXTRA epanelview:w"   # EPANELVIEW: free building, a tool panel at the left of Easy Part never covers the part: real clicks from the BUILDING card at 1280 x 720, every make tool (tests/epanelview_test.gd)
EXTRA="$EXTRA fbolt:w"   # FBOLT: a beginner from the BUILDING card builds a bolt and a nut by real clicks: a round shaft, a hex head (Hex chip), a hex nut apart from the bolt, a hole; Expert shows the hex as six lines (tests/fbolt_test.gd)
EXTRA="$EXTRA npoly2:w"   # NPOLY2: a beginner makes a regular prism: the Sides slider (3-12) next to Hex, a 5-sided and a 12-sided prism by real clicks, Pulled up, measured in mm, Ctrl+Z (tests/npoly2_test.gd)
EXTRA="$EXTRA nopentop:w"   # NOPENTOP: Hollow inside, then one click on a flat face makes that side the open one (a tray); the Wall slider still works, one undo step per action (tests/nopentop_test.gd)
EXTRA="$EXTRA nrounddrag:w"   # NROUNDDRAG: Easy Part, drag an edge outward rounds it: the drag distance is the radius (mm, beside the cursor), release = one undo step; measured from the built volume (tests/nrounddrag_test.gd)
EXTRA="$EXTRA nroundfilter:w"   # NROUNDFILTER: Easy Part Round the edges with three plain-word filters (All edges, Only the outside, Only the top): a box rounded on its top edges only, by real clicks; the bars are measured from the built mesh (tests/nroundfilter_test.gd)
EXTRA="$EXTRA nscrew2:w"   # NSCREW2: Easy Part Parts category: sixteen ISO 4762 screws (M3 M4 M5 M6 x 10 16 20 30 mm) dropped on the floor by a click, sized after placing, one undo step each, measured from the built mesh (tests/nscrew2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nthick:w"   # NTHICK: a Thickness slider on a flat piece (a plate pulled up, thin plate 2 mm to thick block 400 mm): a click and drags change its built height without redrawing the shape; one undo step each, Ctrl+Z (tests/nthick_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nlid:w"   # NLID: a beginner builds a box, Cut a hole > Hollow with a lid: two pieces, the lid 8 mm tall (5 mm plate + 3 mm lip inside the box), measured from the built result (tests/nlid_test.gd)
EXTRA="$EXTRA nsnaplip:w"   # NSNAPLIP: Hollow with a lid + the Snap-fit lip chip: a ridge on the lid lip and a groove in the box wall, measured from the built result; one undo step (tests/nsnaplip_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nscrew2:w"   # NSCREW2: Easy Part Parts category: sixteen ISO 4762 screws (M3 M4 M5 M6 x 10 16 20 30 mm) dropped on the floor by a click, sized after placing, one undo step each, measured from the built mesh (tests/nscrew2_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nnutwasher:w"   # NNUTWASHER: a screw on the floor offers its nut (ISO 4032) and washer (ISO 7089) in one click: one undo step, three solids measured in mm at M3..M6, a size change follows all three (tests/nnutwasher_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nfixit:w"   # NFIXIT: Easy Part Fix it (top bar): one press takes out a loose piece that floats apart from the solid (plain words, one undo step, Ctrl+Z puts it back); measured from the built mesh (tests/nfixit_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nwhycant:w"   # NWHYCANT: Easy Part "Why can't I?": every greyed button on the page says in one line what to do first (a blank part, a sketch, one solid), read from the built scene (tests/nwhycant_test.gd)
EXTRA="$EXTRA nedgechip:w"   # NEDGECHIP: hover an edge of the built solid: one small chip (Round, Bevel) and a see-through ghost of the result; a click makes that one edge rounded or bevelled, one undo step (tests/nedgechip_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nsteplist:w"   # NSTEPLIST: Easy Part step list on the side (Pulled up 3 cm, Rounded 4 edges 2 mm): a click on a step reopens it, the change replays the later steps, one undo step; measured from the built result (tests/nsteplist_test.gd)
EXTRA="$EXTRA ngear:w"   # NGEAR: a Gear from the Easy Part chips by real drags: Teeth 8..60, Small / Medium / Big teeth (module 1/2/3), tip, root, hole and pitch measured from the built mesh (tests/ngear_test.gd)
EXTRA="$EXTRA nlibpage:w"   # NLIBPAGE: the Easy Part Parts button opens a library page by category (ten chips, Screws and Gears work, eight say coming soon); a beginner walk by real clicks, one undo step per build, measured from the mesh (tests/nlibpage_test.gd)
EXTRA="$EXTRA nautosave:w"   # NAUTOSAVE: Easy Part saves every step to user://nautosave/part.json; the next start's empty Easy Part offers 'Bring back your part' (one undo step, step list and mm intact) (tests/nautosave_test.gd; needs the CAD DLL)
EXTRA="$EXTRA nslidelod:w"   # NSLIDELOD: Easy Part, a size slider dragged on a rounded hollow part shows a coarse preview (fewer triangles, quicker frames); full detail on release, one undo step (tests/nslidelod_test.gd)
EXTRA="$EXTRA p021draftangle:w"   # P021DRAFTANGLE: Easy Part Draft angle chip: a box pulled up, one click leans its four side walls 2 degrees (top narrower, base fixed), one undo step; measured from the built result (tests/p021draftangle_test.gd)
EXTRA="$EXTRA p026pullalonga:w"   # P026 PULL ALONG: Easy Part, a round disc and an open Curvy line, then Pull along makes the pipe in one press (no Expert step): mm bounds and volume measured from the built result, one undo step (tests/p026pullalonga_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fstairs:w"   # FSTAIRS: a beginner from the BUILDING card: a 300 x 250 x 175 mm block, Repeat it > Up and Forward = 8 steps (one body, no failed step); the handrail is open (tests/fstairs_test.gd)
EXTRA="$EXTRA p022shellwalls:w"   # p022shellwalls (Friday plan 22): after Hollow inside, Thicker wall: one side wall gets its own thickness (Extra wall slider); measured from the built mesh (tests/p022shellwalls_test.gd)
EXTRA="$EXTRA p027loftbetwee:w"   # P027 (Friday plan 27): Easy Part Blend two shapes gets a Twist slider (the top shape turns, -90 to +90 deg); a round on the floor and a square on the floor, real clicks, bars on the built solid (tests/p027loftbetwee_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p030countersun:w"   # P030 COUNTERSUN: Easy Part, Cut a hole offers M3/M4/M5/M6 screw holes: a clearance hole + a counterbore for the head, volume within 3 % of the ISO numbers, one undo step (tests/p030countersun_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p024twistapull:w"   # P024: Twist a pulled shape: a Twist slider under How far turns a pulled square (a twisted post), measured from the built mesh (tests/p024twistapull_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p034yourownpic:w"   # P034 YOUR OWN PICTURE: Draw shape row Picture chip: a picture file becomes a raised 2 mm logo, one step, Undo, refusals in words (tests/p034yourownpic_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p035filletinsi:w"   # P035 FILLET INSIDE: Easy Part Stick together then Smooth the joints rounds the inside corners where two pieces join (one fillet step, one undo step, undo and redo) (tests/p035filletinsi_test.gd; needs the CAD DLL)

EXTRA="$EXTRA p038makeitstro:w"   # P038 MAKE IT STRONGER: Easy Part, a thin plate pulled up, then Make it stronger adds a 4 mm x 10 mm rib along its long side on the top (one undo step, a Rib height slider); bars on the built solid (tests/p038makeitstro_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p039edgeloopsm:w"   # p039edgeloopsm (Friday plan 39): Curvy line gets a Smooth slider (0 = as drawn, 100 = wobble gone, corners kept); a wobbly hand line by real clicks, bars on the saved curve points (tests/p039edgeloopsm_test.gd)
EXTRA="$EXTRA p082librarypar:w"   # P082 LIBRARY PARTS STAY PARAMETRIC: a screw hole and a library screw keep their size after Change the part (M4 -> M5: the hole and the nut follow); the hole, the screw and the nut measured from the built result (tests/p082librarypar_test.gd)
EXTRA="$EXTRA p103explodedvi:w"   # P103 EXPLODED VIEW (Friday plan 103): Easy Part Pull apart slider on two or more pieces: one click at 30 % pulls the pieces apart along the joint line (gap = 100 + 2 x mm within 0.5 mm, no sideways drift), view only (no step, no undo), together at the left end (tests/p103explodedvi_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p106oneclickin:w"   # P106 ONE-CLICK INSTRUCTION SHEET (Friday plan 106): Easy Part Instruction sheet button writes one printable page: the parts list (volumes from the built result) and each step with its picture + plain words (tests/p106oneclickin_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p123driveit:w"   # p123driveit (Friday plan 123, Drive it): Easy Part, two pieces, Swing it swings the newest piece on a hinge step (90 deg in 2 s, a step on the timeline); bars on the built result (tests/p123driveit_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p069bearingswi:w"   # P069 BEARINGS (Friday plan 69): Easy Part Parts gets a Bearings category (608, 625, 688 rings with real bore / outside / width), Make a seat for it cuts a holder with a pocket the bearing fits (tests/p069bearingswi_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p040drawshape:w"   # P040 (Friday plan 40): Easy Part Draw shape gets a Line chip: a drag is straight, a stretch held with Shift bends (a curve joined to the line); bars on the built sketch (tests/p040drawshape_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p073brackets:w"   # p073brackets (Friday plan 73): Easy Part Brackets page: L-bracket, T-bracket, Corner brace with two screw holes, one undo step each, box and volume measured from the built mesh (tests/p073brackets_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p075ziptieslot:w"   # P075 ZIPTIESLOT: Easy Part Parts > Clips and feet: a rubber foot (16 x 4 mm disc), a cable clip (14 mm ring with an opening) and a zip-tie slot (26 x 10 x 3 mm plate, 14 mm slot), one undo step each, measured from the built result (tests/p075ziptieslot_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p071handles:w"   # P071 HANDLES (Friday plan 71): Parts -> Handles: drawer pull, knob, D-handle at three sizes each; mm and volume measured from the built part, one undo step per pick (tests/p071handles_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p072wheelsandc:w"   # p072wheelsandc (Friday plan 72): Parts > Wheels gives a Wheel (80 mm, axle hole 8 mm) and a Castor (50 mm, hole 6 mm); measured from the built mesh and volume, one undo step each (tests/p072wheelsandc_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p066rackandpin:w"   # p066rackandpin (Friday plan 66): Easy Part Rack chip, a straight row of teeth (Teeth, Teeth size, Thickness); tooth pitch = pi x module measured from the built mesh (tests/p066rackandpin_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p074magnetsapo:w"   # p074magnetsapo (Friday plan 74): Easy Part Cut a hole gets a Magnet chip: a round pocket for a 6 mm x 3 mm magnet (6.2 mm across, 3.2 mm deep), real clicks, measured on the built mesh (tests/p074magnetsapo_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p078makeacasef:w"   # p078makeacasef (Friday plan 78): Parts > Boards > Raspberry Pi / Arduino Uno: a box with standoffs, port holes and a lid; mm from the built mesh and replay volume (tests/p078makeacasef_test.gd)
EXTRA="$EXTRA p089scrubthehi:w"   # P089SCRUBTHEHI: Easy Part Scrub the history: a slider in the step list replays the build step by step (a view only: no undo step, the record unchanged); the shown part is measured from the built result (tests/p089scrubthehi_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p091ghostprevi:w"   # p091ghostprevi (Friday plan 91): hover a shape chip on Easy Part: a see-through ghost of the shape it builds, no record change; a click builds it, one undo (tests/p091ghostprevi_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p113overhangpa:w"   # p113OVERHANGPA (Friday 113): Easy Part Show overhangs paints red the faces that need printing support; Lay it flat turns the part onto its least-overhang face (one step, one undo) (tests/p113overhangpa_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p133weightawar:w"   # p133weightawar (Friday plan 133): a typed move (words box) is slowed by the weight of the weapon it holds (WeightFeel, slow only); bars on the built scene (tests/p133weightawar_test.gd)
EXTRA="$EXTRA p085typetobuil:w"   # p085typetobuil (Friday plan 85): Parts > Type it: "a box 20 by 10 by 5 cm, hollow, 2 mm walls, lid" builds a box with a 2 mm wall and a lid, the Wall slider editable; mm from the built result (tests/p085typetobuil_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p110realsizech:w"   # p110realsizech (Friday plan 110, ★): Easy Part For scale: a hand, a coin or a phone laid beside the part at its real size, a view aid (no record change, no undo step); bars on the built result (tests/p110realsizech_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p117flatpatter:w"   # p117flatpatter (Friday plan 117): Easy Part Cut a hole gets a Flat pattern chip: the box unfolds into a laser-cut cross of six panels with finger joints (3 mm sheet); drawn in a sheet, no model change (tests/p117flatpatter_test.gd)
EXTRA="$EXTRA p108measuregri:w"   # p108measuregri (Friday plan 108): Easy Part floor grid numbers in cm, the step follows the zoom (70 px min gap); view only, measured from the built scene (tests/p108measuregri_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p083favourites:w"   # p083favourites (Friday plan 83): Parts page Favourites row: the parts used lately and a star for favourites (favourites first); a chip puts the part back on the floor (one undo step), the star makes no undo step; a beginner walk by real clicks, measured from the mesh and the favourites file (tests/p083favourites_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p092suggestnex:w"   # P092 SUGGEST NEXT: after Pull it up, Round the edges? and Hollow it? chips under the solid (one press, one undo step each); measured from the built result (tests/p092suggestnex_test.gd)
EXTRA="$EXTRA p076whatfitshe:w"   # P076 WHAT FITS HERE? (Friday plan 76): Easy Part, an M4 screw hole, What fits here? names the saved parts that go through it (diagonal of the two smallest sides <= hole - 0.4 mm), M3 says nothing fits and to make the hole bigger; one step is not an undo step (tests/p076whatfitshe_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p121jointsinwo:w"   # p121 JOINTS IN WORDS (Friday plan 121): Easy Part, two pieces picked in Stick together show This turns here / This slides here; the joint is saved on the part (one undo step), pieces that do not touch are refused in words (tests/p121jointsinwo_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p122jointlimit:w"   # P122 JOINT LIMIT: a hinge gets a Joint limit slider (0-90 deg); the swing stops at it (tests/p122jointlimit_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p044sketchdime:w"   # p044sketchdime (Friday plan 44): Easy Part Draw shape, held on the grid: each side shows its length in mm, live, gone on release (tests/p044sketchdime_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p095showmehowp:w"   # P095 SHOW ME HOW: Easy Part Show me how plays the steps as a see-through ghost, one Next at a time; nothing on the model changes (tests/p095showmehowp_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p046equalandst:w"   # P046 SMART GUIDES: while a sketch Line is drawn, Equal (same length as a line there), Straight (level or upright) and Right angle (square to the line before) light up in words and on the lit line; real clicks (tests/p046equalandst_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p057weightread:w"   # P057 WEIGHT READOUT: Easy Part Colour shows the whole part's weight in wood, metal and plastic (volume x density, a readout only); real clicks, bars on the built volume (tests/p057weightread_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p037bosschip:w"   # FRIDAY 37 BOSS CHIP: a screw on the floor takes a round post beside it, sized by the screw (outside head + 4 mm, hole screw + 0.5 mm, height = length), one click, one undo step; measured from the built result (tests/p037bosschip_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p067hinges:w"   # p067hinges (Friday plan 67): Easy Part Hinge chip: a Butt, Piano or Living hinge sized to the Door height, measured from the built mesh (tests/p067hinges_test.gd)
EXTRA="$EXTRA p070springswit:w"   # p070springswit (Friday plan 70): Easy Part Spring chip: a compression spring, Turns and Wire sliders by real drags, sizes measured from the built mesh (tests/p070springswit_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p107fitviewfro:w"   # P107 FITVIEW: Easy Part view row (Fit view, Front, Top, Side, 3/4) under the panel title: camera only, no step (tests/p107fitviewfro_test.gd)
EXTRA="$EXTRA p059printtimee:w"   # p059printtimee (Friday plan 59): the size label on Easy Part also says the print time ("about 3 h 39 min to print"), worked out from the built volume and surface (tests/p059printtimee_test.gd)
EXTRA="$EXTRA p141walkcycles:w"   # p141walkcycles (Friday plan 141): Easy walk: a Walk style button opens three sliders (Speed, Swagger, Bounce) on the built clip; one undo a drag; measured from the cards (tests/p141walkcycles_test.gd)
EXTRA="$EXTRA p145scenelibra:w"   # p145scenelibra (Friday plan 145): the From a template list has a Room (one 4 x 3 m room, door, window, flat roof) and a Yard (outdoor set: a 30 cm edge, fence, table, 2 benches, no door or roof); measured from the built record (tests/p145scenelibra_test.gd)
EXTRA="$EXTRA p028spinangle:w"   # P028 SPIN ANGLE (Friday plan 28): Easy Part Spin it round has an Angle slider 30..360 degrees (half a spin = a half bowl), kept when the step is reopened; measured from the built result (tests/p028spinangle_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p045typelength:w"   # P045 TYPELENGTH (Friday 45): a Line takes a typed length while drawn: Easy Part Line (digits, Backspace, Enter; a stretch of that length, one undo step) and Expert Line (click, 40, Enter); measured from the built sketch (tests/p045typelength_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p052scalepiece:w"   # p052scalepiece (Friday plan 52): Easy Part, a picked piece pulled up from a shape gets a Size % slider (50 to 200 %) and a Taller only chip, one undo step per release, measured from the built block (tests/p052scalepiece_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p090tryanother:w"   # P090 TRY ANOTHER WAY (Friday plan 90): History gets a Try another way button (the picked earlier step, then the next change starts a new way) and a Ways list back to any way, the first included; real clicks, bars on the built state (tests/p090tryanother_test.gd)
EXTRA="$EXTRA p101sectioneasy:w"   # p101sectioneasy (Friday plan 101): Easy Part Cut view chip (view column): the built part cut in half across Front, orange cap, camera to the cut side; view only, no undo (tests/p101sectioneasy_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p131grippoint:w"   # p131grippoint (Friday plan 131): Easy Part Colour page: Hold here, a click on the part sets the grip; Give to a character holds it there (tests/p131grippoint_test.gd)
EXTRA="$EXTRA p045lineshow:w"   # P045 LINE SHOW: a Line drawn with a typed length stays on the grid after release (Tok accent, 3 px, its mm label); bar counts the accent pixels in the rendered picture (tests/p045lineshow_test.gd)
EXTRA="$EXTRA p080woodboards:w"   # P080 WOOD BOARDS (Friday plan 80): Easy Part Parts > Wood boards: a 2x4 board (89 x 38 x 2438 mm) and an MDF sheet 15 mm (1220 x 15 x 2440), flat on the floor; three sliders; a readout of how many one MDF sheet cuts; mm from the built mesh (tests/p080woodboards_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p084mypartsapp:w"   # p084mypartsapp (Friday 84): a part file someone shared (.json, picture beside it) dropped on the window goes into My parts (a name already saved becomes "<name> 1"); the library lists it next to the standard ones; a .json that is not a part is refused with the next step (tests/p084mypartsapp_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p101cutframe:w"   # p101cutframe (Friday plan 101 follow-up): Cut view frames the whole cut part in the free view (not under the side panel); bar: the orange cap covers 2 % of the clear view (tests/p101cutframe_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p131heldshow:w"   # p131heldshow (Friday plan 131): Easy Part Give to a character frames him and the Part in his hand (tests/p131heldshow_test.gd)
EXTRA="$EXTRA p032slotasitso:w"   # P032SLOTASITSO: Easy Part Slot chip: one click makes a plate with a long rounded hole cut through (one body, one undo step), Length drag stretches it; mm box and volume measured from the built result (tests/p032slotasitso_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p054alignchips:w"   # P054 ALIGN CHIPS: Easy Part Line them up / Centre on that / Same height on two picked pieces (the second moves, one undo step each, measured from the built faces; tests/p054alignchips_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p067framefix:w"   # p067framefix: the Hinge chip frames the hinge (a Piano hinge fills at least 30 % of the clear view) and a Butt hinge is two leaves with a gap and a knuckle (tests/p067framefix_test.gd)
EXTRA="$EXTRA p139mocapmix:w"   # p139mocapmix (Friday plan 139): Easy Walk style's neighbour, a Mood button on the clip strip: a typed mood word (angry, tired, heavy, sneaky; a bit = half) blends the Style dial onto the built clip, one undo step; measured from the built cards (tests/p139mocapmix_test.gd)
EXTRA="$EXTRA p129linkages:w"   # p129linkages (Friday plan 129): Easy Part Parts > Hinges shows a Linkage panel: a 4-bar linkage, a drag knob on the crank (a real drag), + and - lengths, Full turn words; measured from the panel text (tests/p129linkages_test.gd)
EXTRA="$EXTRA p201physicalto:w"   # P201 PHYSICAL TO DIGITAL (Friday plan 201): Easy Part Photo size chip, a phone photo with a coin, six clicks, the mm make a plate (tests/p201physicalto_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p152sculptbrus:w"   # p152sculptbrus (Friday plan 152): SCULPT page Size and Strength sliders under the readout (plain words, small/big, soft/firm); measured from the sphere mesh after real strokes (tests/p152sculptbrus_test.gd)
EXTRA="$EXTRA p118fingerjoin:w"   # p118fingerjoin (Friday plan 118): Easy Part Cut a hole > Finger joints: a comb of notches along the top edge of a pulled-up box, measured from the built result (tests/p118fingerjoin_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p127springsand:w"   # P127 DOES IT FALL OVER (Friday plan 127, springs and gravity light physics): Easy Part Colour chip reads whether the built part stands on its feet (its middle over the lowest surface), a readout only; real clicks, bars on the mesh (tests/p127springsand_test.gd; needs the CAD DLL)

EXTRA="$EXTRA p147physicsrag:w"   # p147physicsrag (Friday plan 147): Ragdoll: hit, fall, get back up: the body at the playhead is pushed, falls limp for 2 s, blends back onto its own pose over 1 s; baked as cards into a NEW scene (tests/p147physicsrag_test.gd)
EXTRA="$EXTRA p082libframe:w"   # P082LIBFRAME: after a Parts library pick (M4 x 16) the camera frames the part: its bigger side fills at least 20 % of the view (tests/p082libframe_test.gd)
EXTRA="$EXTRA p150shotlist:w"   # p150shotlist (Friday plan 150): Shot list on the CHECK row: a typed story, one line per shot, makes a card per shot (camera size, lens, low or high angle, move); Keep all writes the shots, one undo step (scripts/shot_list.gd, shot_list_ui.gd; tests/p150shotlist_test.gd)
EXTRA="$EXTRA p130camandfoll:w"   # p130camandfoll (Friday plan item 130): Easy Part Parts > Gears: a Cam and follower button drops a cam (a disc off its axle, lift + thickness sliders) with its follower rod on the floor; 2 solids, mm measured from the built mesh (tests/p130camandfoll_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p206threadgene:w"   # p206threadgene (Friday plan 206): Parts > Screws: a threaded rod chip (M8, M10, M12 rod, ring thread for printing, crest 0.15 mm under) drops on the floor, one undo step (tests/p206threadgene_test.gd)
EXTRA="$EXTRA p192makeitlike:w"   # p192makeitlike (Friday plan 192): Parts > Type it > Like a photo: Mug or Chair from steps after a picture is chosen; bars on the built part (tests/p192makeitlike_test.gd)
EXTRA="$EXTRA p151modelfromw:w"   # p151modelfromw (Friday plan 151): MODEL page "Model from words" steps: typed phrases as editable rows (Enter reruns from a row, x removes, Ctrl+Z takes the newest back); measured from the built mesh (tests/p151modelfromw_test.gd)
EXTRA="$EXTRA p156solidmesht:w"   # p156solidmesht (Friday plan 156): Easy Part Sculpt details? chip under a pulled-up solid: the solid becomes a sculpt mesh (a copy) on the Sculpt page, a real drag moves it, Esc leaves (tests/p156solidmesht_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p197kidsmode:w"   # p197kidsmode (Friday plan item 197, small version): Easy Part Parts library: a Kids chip makes the category chips big (40 px), 15 px words, radius 14; off = 34 px (tests/p197kidsmode_test.gd)
EXTRA="$EXTRA p204livinghing:w"   # p204livinghing (Friday plan 204): Parts > Hinges Living cuts: a strip with slots, one click, sliders for length, slot spacing and thickness, measured from the built mesh (tests/p204livinghing_test.gd)
EXTRA="$EXTRA p208latticeinf:w"   # p208latticeinf (Friday plan 208): Easy Part, Hollow inside then Lattice inside: thin bars fill the box hollow, the Gap slider sets the spacing; mm from the built volume and rays (tests/p208latticeinf_test.gd)
EXTRA="$EXTRA p203screwholea:w"   # p203screwholea (Friday plan 203): Easy Part Cut a hole: a Printer chip (any, resin = tight 4.3 mm, FDM = loose 4.8 mm for M4); the M4 hole measured from the built mesh, one undo step per press (tests/p203screwholea_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p205snapfitcli:w"   # P205 SNAP-FIT CLIP: Easy Part Parts > Clips and feet > Snap-fit clip: a 26 x 19.6 x 4.5 mm plate with a U gap (the matching slot) round a 16 mm tongue and a hook; one body, volume, one undo step (tests/p205snapfitcli_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p065gearpairpi:w"   # p065gearpairpi (Friday plan item 65): Easy Part Parts > Gears: a Gear pair button drops two meshing gears (small + big, Ratio 1..3 : 1), centre distance = module x (small + big) / 2; mm measured from the built mesh (tests/p065gearpairpi_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p207knurlingon:w"   # p207knurlingon (Friday plan 207): Parts > Handles: a Knurled grip row (24, 32, 40 mm), flutes spaced 3.5 mm round, a Grip texture slider (mm), one undo step per action; measured from the built ring (tests/p207knurlingon_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p163collection:w"   # p163collection (Friday plan 163): My parts cards go into the collections My workshop or My game props (right-click a card); the column entry shows when it holds a part (tests/p163collection_test.gd)
EXTRA="$EXTRA p153symmetryon:w"   # p153symmetryon (Friday plan 153): Easy Part shape row: Symmetry on by default (a box drawn on one side gets its copy in the same step), One side only chip turns it off; measured from the built result (tests/p153symmetryon_test.gd)
EXTRA="$EXTRA p_stl3mf:w"   # p_stl3mf: STL + 3MF export of a Part for 3D printing: the Easy Part Export button opens the dialog on 3D printing; binary STL and a 3MF package (mm, Z up, deduplicated vertices, colour, one object per body) read back from disk; open-edge warning in plain words (tests/p_stl3mf_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p149animglb:w"   # p149animglb (Friday plan 149): the edited character + its animation as one .glb from the Export dialog (new target once a body is applied); skeleton, skin, clip length/keys, pose at mid-clip and Y-up metres read back with GLTFDocument; FBX said plainly to go through Blender (tests/p149animglb_test.gd)
EXTRA="$EXTRA p199storymode:w"   # p199storymode (Friday plan 199): More > Make a story, a three-step card: Open BUILD (draw and pull a box), Give it to the fighter, Save video; each step reads To do / Done from the built state (tests/p199storymode_test.gd; needs the CAD DLL)
EXTRA="$EXTRA p172layouts:w"   # p172layouts (Friday plan 172): the layout at 1024x600 to 3840x2160 (Easy Part with a box, Parts, Export, Pose): no control cut off, overlapping or under the ViewCube; a screenshot per size (tests/p172layouts_test.gd)
EXTRA="$EXTRA p156redtext:w"   # p156redtext (the #138 contact sheet): no text over 40 px on the Sculpt page (the floor's X axis name was a world-sized Label3D, drawn huge as "is left"; tests/p156redtext_test.gd)
EXTRA="$EXTRA p190feedback:w"   # p190feedback (Friday plan 190): Send feedback in the Help panel (and Help: send feedback): one local JSON line + a screenshot, nothing sent (tests/p190feedback_test.gd)
EXTRA="$EXTRA p061screwheads:w"   # P061SCREWHEADS: Screws page head chips: Socket, Button (ISO 7380) and Flat (ISO 10642 countersunk) heads, one solid each, M5 x 20 measured to the tables (tests/p061screwheads_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s033:w"   # FRIDAY 33: text on a face (Parts > Type it): KINE cut in / stand out, volume, bbox, one undo
EXTRA="$EXTRA s142:w"   # s142 (Friday plan 142): Style slider (realistic <-> cartoon) under the scrub on a built clip: joints move from the clip mean by 0.5..2.0, feet re-planted, length unchanged, one undo step a drag (tests/s142_test.gd)
EXTRA="$EXTRA s116:w"   # s116 (Friday plan 116): Export dialog > Laser cutting (SVG, DXF): outline of a flat face (outer + holes) in mm; 100x50 plate with a 20 mm hole parsed back from both files; a curved face says so (tests/s116_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s093:w"   # s093 (Friday plan 93): Beginner / Comfortable / Expert slider opened by the Easy button on Easy Part; Beginner hides Spin it round, Curvy line, Blend two shapes, Stick together, Repeat it; remembered in user://; record untouched (tests/s093_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s115:w"   # s115 (Friday plans 115 + 112): Export dialog "CAD program (STEP)" target (re-imported through the kernel: volume 0.1 pct, bbox 0.01 mm) and the "Ready to print?" checklist before STL/3MF: thin walls, overhangs in cm2, floating pieces (tests/s115_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s114:w"   # s114 (Friday plan 114): Export dialog > 3D printing: Printer bed (220 x 220 x 250) + Split to fit; a 400x100x20 plate becomes 2 pieces <= 220 with 2 dowel holes (5 mm, 10 deep) per cut face matching within 0.05 mm; a part that fits is not split (tests/s114_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s099:w"   # FRIDAY 99: Portuguese UI (pt_BR translation, Settings > Language, remembered)
EXTRA="$EXTRA s119:w"   # Send to slicer (Friday plan 119)
EXTRA="$EXTRA s161:w"   # My parts: thumbnails, tags + tag chips, part versions + compare slider (161/164)
EXTRA="$EXTRA s124:w"   # s124 (Friday plan 124): Gear pair > Turn it: the small gear turns, the big one turns -N1/N2 times as far (20:40 pair, ten angles within 0.5 deg, gap between meshes >= -0.05 mm), 2:1 chain signs, only Save pose changes the record (tests/s124_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s102:w"   # s102 + s104 (Friday plan): X-ray and Turntable view toggles under the ViewCube (hidden holes show, material alpha < 1, off restores; camera yaw 36 deg per second at 10 s/rev; record and undo untouched) (tests/s102_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s055:w"   # s055 (Friday plan 55 + 56): Easy Part view column > Measure: two corner clicks read mm (40.0, diagonal 53.85), two face clicks read degrees (90.0, 30.0); record and undo unchanged; Esc leaves (tests/s055_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s209:w"   # s209 + s210 (Friday plans 209, 210): Make it stackable (lip 0.3 mm inside the rim, no common volume of two stacked copies) and the Label maker (BOLTS tag, raised or cut in, Parts > Type it; tests/s209_test.gd; needs the CAD DLL)

EXTRA="$EXTRA s029:w"   # s029 (Friday plan 29): Holes in a pattern: Cut a hole > Row / Around / Grid of holes (count, spacing, radius, rows x columns, Pick centre); 100x60x10 plate, 6 mm holes: volume within 1 pct, centres 20 mm / 60 deg / 15 mm apart (tests/s029_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s128:w"   # s128 (Friday plan 128): Easy Part centre of mass: red dot (after Does it fall over?, always while tipping) and "It will tip over: its weight is N mm outside its feet" in the size line; cube/L analytic, leaning box within 1 mm (tests/s128_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s013:w"   # s013 (Friday plans 13 + 36): Soft/Medium/Sharp round presets (r 5.0/2.4/0.8 on a 40x40x20 box, measured from the top face and the volume) and the Rib chip on the Brackets page (+600 mm3 for 20x20x3, one solid)
EXTRA="$EXTRA s157:w"   # s157 + s154 (Friday plans 157, 154): Export dialog Triangle budget on a 13.8k sculpt sphere (2k: <= 2000 triangles re-read from the .glb, volume 3 pct, bbox 1 pct, Full = full count, screen mesh unchanged) and the Sculpt Remesh slider lighter / smoother (half within 10 pct, volume 2 pct, one undo each) (tests/s157_test.gd)
EXTRA="$EXTRA s048:w"   # s048: Repeat it Around an axis/edge, Along a line, With growth
EXTRA="$EXTRA s135:w"   # Friday plan 135+136: Scene lines (two characters with then/while/after, camera words)
EXTRA="$EXTRA s096:w"   # P096 templates as recipes: phone stand / shelf bracket / box with lid open as named steps, edited from the step list

EXTRA="$EXTRA s023:w"   # s023 (Friday plans 23 + 109): Pinch / Bulge a face (chip under the step list, slider -1..1, 40x40x20 box top centre +-4 mm at 0.5, rim at 20 mm, 0 = original) and Light / Dark for the Easy Part boxes (popup under Easy, contrast, remembered) (tests/s023_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s081:w"   # s081 (Friday plans 81 + 58): Cut list CSV from wood boards in the Export dialog (2 rows, counts 2 and 1, 2.1 m) and the BRL cost on the Size line (20 cm3 PLA = R$ 2,98; price edit changes it)
EXTRA="$EXTRA s047:w"   # s047 Mirror while drawing: Mirror chip, clicked mirrored Line (Easy Part)
EXTRA="$EXTRA s134:w"   # s134 (Friday plan 134): typed moves with props: "pick up the box" (hand on the grip point within 3 cm, the box follows the hand), "throw the ball" (>= 1 m), "open the door"; a missing prop is said in plain words, one undo step
EXTRA="$EXTRA s051:w"   # s051 (Friday plan 51): Array fill: Cut a hole > Fill the face (Round / Square / Hex, size, spacing, edge margin): 100x60x3 plate, 5 mm round holes 10 mm apart 5 mm margin = 45 holes (analytic), volume within 0.5 pct, staggered 54, hex 48, too-small face = message and no step (tests/s051_test.gd; needs the CAD DLL)

EXTRA="$EXTRA s195:w"   # s195 (Friday plan 195): Cut a hole > Make it lighter (rule of thumb, not a stress test): Held / Pushed chips, How much lighter slider; 120x40x10 bracket drops 20-50 pct, 3 mm rim probed solid (tests/s195_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s194:w"   # s194 (Friday plan 194): Parametric families: My parts right-click > Make a family; a stool (400 mm legs + 30 mm seat, 6 mm hole) at 30/45/60 cm: heights within 0.05, seat 30.00 and hole 6.00 unchanged (replayed, not scaled), 3 entries re-read from disk, no undo step (tests/s194_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s051:w"   # s051 (Friday plan 51): Array fill: Cut a hole > Fill the face (Round / Square / Hex, size, spacing, edge margin): 100x60x3 plate, 5 mm round holes 10 mm apart 5 mm margin = 45 holes (analytic), volume within 0.5 pct, staggered 54, hex 48, too-small face = message and no step (tests/s051_test.gd; needs the CAD DLL)

EXTRA="$EXTRA s168:w"   # s168+s169: incremental replay (a slider change rebuilds only the changed steps) and background tessellation of the slider preview

EXTRA="$EXTRA s202:w"   # s202 (Friday plan 202): Smart tolerances: Fit chip on Cut a hole (Tight 0.0 / Snug 0.1 / Slides 0.2 / Loose 0.4 mm per side): 10 mm peg hole measures 10.40 at Slides, lid lip gap per side, one undo step
EXTRA="$EXTRA s146:w"   # F146: a part built in Easy Part becomes a prop with a grip; Pick up goes to the grip (tests/s146_test.gd)
EXTRA="$EXTRA n04:w"   # N04: native cape sim (KineClothNative, scripts/cloth.gd): native vs GDScript capes equal, timing
EXTRA="$EXTRA n02:w"   # n02 native port KineMeshCheckNative (Ready to print scans, closed-edge count, signed volume, size box, tip-over feet hull): GDScript vs native on the 45-hole plate + gear pair + s115 cases (tests/n02_test.gd; needs the CAD DLL)
EXTRA="$EXTRA n01:w"   # profile.
EXTRA="$EXTRA s158:w"   # Friday plan 158: vertex-colour paint with a hard/soft round brush, colour picker popup, eyedropper, star/heart/logo/PNG stickers (size + turn), undo, .kmesh + GLB COLOR_0
EXTRA="$EXTRA s165:w"   # s165 (Friday plan 165): Build-along Challenges (Parts page): 5 targets with picture + sizes in words, "How close am I?" score = 100 x IoU (kernel intersect volume) x size fit; exact target >= 98, stand with no slot < 90 (hint names the slot), twice as tall < 60 ("too tall", 40 mm) (tests/s165_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s166:w"   # s166 (Friday plans 43 + 166): Trace a picture into a sketch (Draw shape row: width in mm + Trace it; 80x40 rectangle with a 20 mm hole = 80.0 x 40.0 bbox, volume within 2 pct) and Draw to search in the Parts library (real mouse drag: circle -> round part, hexagon -> hex nut, L -> L-bracket in the top 3)
EXTRA="$EXTRA s173:w"   # s173 (Friday plans 173 + 174): touch (one finger draws, two fingers orbit / pinch / tap = undo), pen pressure and gamepad (left stick orbit, triggers zoom, right stick pan, A fit, B back) (tests/s173_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s175:w"   # Friday 175: undo memory budget (old steps packed, oldest forgotten with a note)
EXTRA="$EXTRA s167:w"   # Friday 167: Easy Part start under 1 s from the BUILDING card (median of 5)
EXTRA="$EXTRA s176:w"   # S176: one walk per Parts library category (read from LIB_CATS): first and last chip, real clicks; a solid, bbox inside 1 m (wood stock 2.5 m), one undo step, chip on screen and not under the view column (tests/s176_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s200:w"   # s200 (Friday plan 200): Export dialog > Godot 4 > Playable game (Godot project folder): project.godot + main.tscn, run headless with Godot (tests/s200_test.gd + s200_sim.gd)
EXTRA="$EXTRA n03:w"   # n03: KineMeshOpsNative, native decimate / voxel remesh / STL, 3MF, OBJ packing, byte-identical to the GDScript writers (tests/n03_test.gd)
EXTRA="$EXTRA s191:w"   # Friday 191: Sketch with sizes (AI): Trace box option, recorded model reply (no network), schema refusals, no-key words + Trace offer (tests/s191_test.gd; needs the CAD DLL)


EXTRA="$EXTRA s193:w"   # s193 (Friday plan 193): Fit to an object, Parts > Boards: a phone scan (.obj, 1/1000 scale, noisy, tumbled) -> real size -> Holder / Case by the CAD kernel; ray-cast pocket, wall and enclosure bars (tests/s193_test.gd)
EXTRA="$EXTRA s077:w"   # s077 (Friday plan 77): Parts > Boards real-board boxes (Arduino Uno R3, ESP32 51/55 x 28, Raspberry Pi 4B): standoffs at the datasheet holes (rays: 4 found, dia 0.1, centres 0.05), port cut-outs escape, Wall and Gap sliders


EXTRA="$EXTRA s063:w"   # s063 FASTEN THESE TWO (Friday plan 63): Stick together, two plates picked: Fasten these two picks the screw size and length and two hole places, cuts clearance and pilot holes, places the screws; the instruction sheet lists 2x M3 x 10 (tests/s063_test.gd; needs the CAD DLL)



EXTRA="$EXTRA s031:w"   # s031 (Friday plan 31): Thread look on a round hole: a helix drawn in the bore at the ISO pitch (radius / pitch / same-STL / sheet line / one undo bars; tests/s031_test.gd)


EXTRA="$EXTRA s012:w"   # s012 (Friday plan 12): Bevel chip beside Round the edges: 45-degree chamfer planes, top face 40 -> 38 -> 36 mm, volume vs the analytic chamfered box, one undo step (tests/s012_test.gd)


EXTRA="$EXTRA s053:w"   # s053 Friday 53: drag a piece onto another piece's face, it lands flush (snap 1 mm, ghost, one undo step "Moved a piece"); real drags (tests/s053_test.gd)


EXTRA="$EXTRA s042:w"   # s042 (Friday plan 42): Draw shape > More shapes: star, gear outline (Teeth slider), heart, arrow drawn by clicks, pulled up 10 mm; tips/radii/mirror/angle measured from the mesh (tests/s042_test.gd)


EXTRA="$EXTRA s079:w"   # s079 (Friday plan 79): Parts > Pipes: PVC pipe by real outside width, elbows 90 and 45, T-piece, sleeve with the Fit clearance; ray-cast widths, opening angles, Stick together (tests/s079_test.gd)


EXTRA="$EXTRA s125:w"   # s125 (Friday plan 125): Easy Part Swing it checks every step against the other pieces; at the first touch the turn stops at the last free angle, both flash red 0.3 s, words say what hit; lid 0-120 deg analytic; 2k-triangle timing (tests/s125_test.gd; needs the CAD DLL)


EXTRA="$EXTRA n05:w"   # N05: slicer lookup cache, build_banded reuse + C++ (KineFieldNative)


EXTRA="$EXTRA s097:w"   # s097 (Friday plan 97): Ctrl+K / the bar icon opens one box for any Easy Part action: hole, round, m3 screw hole, screw m4 16; arrows + Enter = the click, Esc closes


EXTRA="$EXTRA s016:w"   # s016: Wall slider shows the part cut in half (a contrasting band) while held and 1.5 s after


EXTRA="$EXTRA s018:w"   # S018 (Friday 18): Thinner / thicker everywhere slider under How far offsets every face of the whole part (box +-1 mm, plate hole 10 -> 8 mm); one undo step; Pull it up still edits (tests/s018_test.gd; needs the CAD DLL)
EXTRA="$EXTRA s018:w"   # S018 (Friday 18): Thinner / thicker everywhere slider under How far offsets every face of the whole part (box +-1 mm, plate hole 10 -> 8 mm); one undo step; Pull it up still edits (tests/s018_test.gd; needs the CAD DLL)



EXTRA="$EXTRA s126:w"   # s126 (Friday plan 126, Motion study to video): Easy Part, Swing it, then Save the motion as a video films the swing into a 1280 x 720 30 fps h264 .mp4; size, ffprobe, decoded frames and a half-angle still measured from the file (tests/s126_test.gd); needs the CAD DLL and ffmpeg


EXTRA="$EXTRA s132:w"   # Hold it here: grip spot + Long axis / Face axis chips, the palm on the spot, kept in the scene file


EXTRA="$EXTRA s105:w"   # S105 Nice picture button in the Export dialog: 1920x1080 PNG, shadow, reflection, gradient


EXTRA="$EXTRA s120:w"   # s120: a part with hinges is one moving prop on STAGE, its joints keyed (Friday plan 120)


EXTRA="$EXTRA s100:w"   # s100 (Friday plan 100): Easy Part keyboard shortcuts card: 3 clicks on a button with a key show "Tip: Ctrl+Z does Undo" once (remembered in settings), at most one per 2 minutes, never during a drag; Shortcuts list in the Easy popup, each key tested (tests/s100_test.gd; needs the CAD DLL)


EXTRA="$EXTRA s137:w"   # plan 137: impact frames on a strike (hit-stop slider, 2-frame target flash, 0.25 s camera shake, toggle off = original)


EXTRA="$EXTRA s140:w"   # s140 (Friday plan 140): Pose library by mood: moods measured from the body (tired/proud/scared/happy/angry/sad/calm/excited), Poses search words + synonyms, mood chips in the Pose library; tests/s140_test.gd


EXTRA="$EXTRA s094:w"   # p094: Easy Part MAKE buttons show a looping 14-frame clip tooltip (assets/tips/easy, made by tools/make_easy_tips.gd)
EXTRA="$EXTRA s155:w"   # s155: Sculpt page Make it a solid part (needs KineCAD v4)
EXTRA="$EXTRA s155b:w"   # s155b: KineCAD 5 kernel solid offset (volumes vs closed forms, hole 8.00/12.00, timing vs the 26-copy path; tests/s155b_test.gd; needs the CAD DLL)



EXTRA="$EXTRA s211:w"   # s211: Draw on a curved face (cylinder, sphere): the sketch sits on the tangent plane at the click; tests/s211_test.gd

EXTRA="$EXTRA fpen:w"   # FPEN: a beginner builds a pen from the BUILDING card by real clicks (parked test from w4-fpenyrfix; bars 5 CLIP and 7 UNDO need Draw on a curved face, s211); tests/fpen_test.gd



EXTRA="$EXTRA bug3:w"   # bug3: a metal block is lit by a studio reflection sky, not black


EXTRA="$EXTRA bug7:w"   # bug7: Examples only lists examples on the start screen (no mode switch), Back to my projects, 15 Building examples built by the app's own builders (scenes/examples, tools/gen_start_examples.gd)



EXTRA="$EXTRA bug4:w"   # bug4 (Nick 11-01 "no access to our library"): a Library button in the Easy Part bar (2 clicks from the start screen), a Parts library button on the 3D BUILDING start card; tests/bug4_test.gd


EXTRA="$EXTRA bug2:w"   # bug2: Easy Part opens with its floor grid at least 15 pct of the frame (looking down at -45 deg), Top / Side unchanged



EXTRA="$EXTRA fdice:w"   # FDICE: a beginner builds a 40 mm die from the BUILDING card by real clicks: cube, Round the edges, 21 pips (round drawn on each face, Cut a hole, 2 mm deep); one Undo takes a pip away (tests/fdice_test.gd; needs the CAD DLL)
EXTRA="$EXTRA fmonitor:w"   # FMONITOR: a beginner from the BUILDING card builds a computer monitor by real clicks: a thin screen, Round the edges, Dark colour, a neck, a base; the oval base is drawn with the Oval chip (tests/fmonitor_test.gd)
EXTRA="$EXTRA fhanger:w"   # FHANGER: a beginner from the BUILDING card builds a clothes hanger by real clicks: a round disc, a Curvy line wire, Pull along, a Curvy hook, Pull along, one Undo (tests/fhanger_test.gd)
EXTRA="$EXTRA fstool:w"   # FSTOOL: a beginner from the BUILDING card builds a three-legged stool by real clicks: a round seat, a leg under it, Repeat it in a Ring (three legs), a ring brace (bar 4b is a recorded dead end: no way to lower it to leg height) (tests/fstool_test.gd)



EXTRA="$EXTRA bug6:w"   # bug6: animation-only UI (grip panel, facing label) never shows in 3D BUILDING; no stray divider bars / empty buttons; top rows clear at 3 sizes; tests/bug6_test.gd


EXTRA="$EXTRA s219:w"   # s219: every Part step kind has a timeline icon; unknown names fall back to a generic icon


EXTRA="$EXTRA s215:w"   # s215: Pipe through points (Parts > Pipes): a tube swept along 3D points with smooth bends



EXTRA="$EXTRA s218:w"   # s218: section colour: per-body cap colours on Section view, Split results and Nice picture


EXTRA="$EXTRA s216:w"   # s216 SWEEP BEND RADIUS: Pull along has a Bend radius control (slider + typed mm, default 1.5 x tube width, least the tube radius); L path, 30 mm tube at 60 mm: one solid, mesh circle-fit radius 60 +-1, Pappus volume, slider/typed changes, undo (tests/s216_test.gd; needs the CAD DLL)


EXTRA="$EXTRA s213:w"   # s213: multi-part Assembly (BUILD chooser New assembly): insert, place, edit, save/open, export STL/GLB/STEP; tests/s213_test.gd


EXTRA="$EXTRA s220:w"   # s220: MODELING VIEW WITH MATHS: part_facts (a part as text: volume, box, axis, contact graph) + part_assert (one-line checks, miss in mm / deg / mm3), agent_tools + poser_cli + AI box; tests/s220_test.gd


EXTRA="$EXTRA s214:w"   # s214: pattern a GROUP of bodies in one step (Expert Pattern ticks/Ctrl-click/box, Easy Repeat it > Group)


EXTRA="$EXTRA s224:w"   # s224: Realistic render (sky, sun, soft shadows, AO, reflections): Nice picture preset + VIEW > Realistic
EXTRA="$EXTRA s217:w"   # Metal reads as metal in Expert, Easy Part, Nice picture and STAGE (same studio reflection sky as bug3)


EXTRA="$EXTRA s223:w"   # LOOKS: the material library made in code, material words, Part materials (Friday plan 223)


EXTRA="$EXTRA s229:w"   # s229: primitives by numbers (Part.prim, Expert Primitive dialog, Easy By numbers), planes from 3 points / angle / edge / face, scoped intersect, bow-tie refused; tests/s229_test.gd


EXTRA="$EXTRA s228:w"   # s228: patterns along paths and grids: Part pattern kinds grid + route (corners, fit, follow, jitter, skip, group); Expert Pattern Grid / Along a path, Easy Repeat it > Grid / Round edge


EXTRA="$EXTRA s230:w"   # s230: GPU tiers: adapter -> tier (RTX30 here), NVENC video export vs libx264, Fast view (FSR 2) fps; tests/s230_test.gd


EXTRA="$EXTRA s227:w"   # s227: ornaments library + sculpt-into-part road


EXTRA="$EXTRA sbug2:w"   # sbug2: a broken painted-weights sidecar (right forearm weight over the whole body) tore the body apart in every clip; refused at load now; per-clip stretch bar x4, planted control must fail it (tests/sbug2_test.gd; run with APPDATA on a temp dir)


EXTRA="$EXTRA s212:w"   # s212: name bodies (browser double-click / right-click Rename, Easy name field; names in record, undo, 3MF/GLB/OBJ/STEP); tests/s212_test.gd


EXTRA="$EXTRA s225:w"   # FRIDAY 225 NATURE + SCATTER: trees, hedges, shrubs, grass, flowers, scatter; Nature tool + Words + agent "nature"
EXTRA="$EXTRA s221:w"   # s221: WARNING LEVELS (Off / Look / Print / Engineering; per-part and per-warning mutes; same list in the Part panel and agent_tools part_warn); tests/s221_test.gd


EXTRA="$EXTRA s226:w"   # s226: ROOF feature (hip/gable/xieshan/pyramid/shed/flat, sag, corner lift, open top, trims) as a thin closed shell; kernel ray/volume bars, Expert Roof tool, Easy Roofs page, agent part_roof; tests/s226_test.gd
EXTRA="$EXTRA s232:w"   # s232: TEMPLE LIGHT: sky with clouds, sun by time of day, haze, GI, exposure, camera by numbers, FINAL SHOT with no UI; tests/s232_test.gd


EXTRA="$EXTRA s231:w"   # TEMPLE LOOK: default materials by piece kind, words and chips, gravel and oak fixes (Friday plan 231)


EXTRA="$EXTRA s227b:w"   # s227b: the Easy Part library page fits the panel scroll area at 1280x720 (a chip that adds a row fails here)


EXTRA="$EXTRA s234:w"   # s234: PART TEXT AND NAMING: nested loops in one sketch (holes, islands, crossing named), CJK text from the bundled OFL font, step names reach piece kinds; tests/s234_test.gd


EXTRA="$EXTRA s222:w"   # s222: WORDS FOR MORE THAN HOUSES (hall_words.gd, trade_words.gd), tests/s222_test.gd


EXTRA="$EXTRA s233:w"   # BIG PARTS: 300 bodies drawn (256-surface limit), shared replay shapes, broad phase, one-pass counts (item 233)
EXTRA="$EXTRA s235:w"   # s235: TEMPLE LOOK ROUND 3 (light contrast, red/paving/tile colours, frame_width), tests/s235_test.gd
EXTRA="$EXTRA s236:w"   # s236: TEMPLE ROUND 4 (amber dense ginkgo, ridge_dragon + corner_sprite shapes, roof lift_pow, mountains), tests/s236_test.gd
EXTRA="$EXTRA s237:w"   # s237: gold ornaments seated on the roof + floats check, tests/s237_test.gd


EXTRA="$EXTRA s240:w"   # s240: FRAMED FLOOR OVERLAP (Fit view frames the grid in the free view; Challenges card closes), tests/s240_test.gd


EXTRA="$EXTRA s239:w"   # s239: GROUPED LIBRARY (group tabs, every chip readable, any number of categories fits), tests/s239_test.gd
EXTRA="$EXTRA s241:w"   # s241: WHAT A STEP DID (body-making calls return created / changed / removed with stable keys), tests/s241_test.gd


EXTRA="$EXTRA s244:w"   # s244: CHECKPOINT + REPLAY FROM STEP, tests/s244_test.gd


EXTRA="$EXTRA s242:w"   # s242: LOOK FACTS (agent look_facts: per-piece colour, coverage, contrast, visibility from an ID pass + the final light), tests/s242_test.gd




EXTRA="$EXTRA s243:w"   # s243: FRAMING FACTS FROM THE SILHOUETTE (frame_facts, frame_to), tests/s243_test.gd

EXTRA="$EXTRA s247:w"   # s247: THE LIBRARY GROUP TABS ARE PINNED above the scrolling chip area, tests/s247_test.gd


EXTRA="$EXTRA s248:w"   # s248: STATUS LINE vs THE PAGE BAR (BUILD tab) at 1024 x 600 .. 2560 x 1440, tests/s248_test.gd
EXTRA="$EXTRA s250:w"   # s250: Easy Part panel title on its own row (not under Empty/Slot/Examples) + page tab icons whole and opaque, tests/s250_test.gd
EXTRA="$EXTRA s251:w"   # s251: tool labels never split a word, top bar buttons never an ellipsis (1024 x 600 .. 2560 x 1440, Easy + Expert), tests/s251_test.gd
EXTRA="$EXTRA s252:w"   # s252: undo/redo toasts name the step (never "Redid:"), toasts never cover a button, tests/s252_test.gd
EXTRA="$EXTRA s253:w"   # s253: a slow frame never loses a drag or an undo state (exact playhead on Undo/Redo, drag after the camera ease), tests/s253_test.gd
EXTRA="$EXTRA w09:w"   # W09: pick through overlapping pieces (repeat click cycles, list of plain names), tests/w09_test.gd
EXTRA="$EXTRA w01:w"   # w01: camera navigation settings (remap, zoom to cursor, orbit pivot, presets), tests/w01_test.gd


EXTRA="$EXTRA w04:w"   # w04: retarget bone-map screen, tests/w04_test.gd
EXTRA="$EXTRA w04m:w"   # w04m: bone-map screen through main._import_anim_picked, tests/w04m_test.gd


EXTRA="$EXTRA w08:w"   # w08: In place / travelling toggle on a clip, applied live, tests/w08_test.gd


EXTRA="$EXTRA w10:w"   # w10: join/cut failure helper, tests/w10_test.gd


EXTRA="$EXTRA w13:w"   # w13: GIF export, per-clip palette, loops, tests/w13_test.gd


EXTRA="$EXTRA w16:w"   # w16: test-print fit strip (5 pegs, 5 holes, clearances engraved, manifold STL/3MF, volumes within 1 %), tests/w16_test.gd


EXTRA="$EXTRA w14:w"   # W14: GPU in use + integrated-GPU warning with Windows Graphics steps, tests/w14_test.gd


EXTRA="$EXTRA w05:w"   # w05: export mesh quality Coarse/Normal/Fine/Custom, live triangle count and file size, tests/w05_test.gd


EXTRA="$EXTRA w06:w"   # W06: project unit (mm/cm/in), typed units in length fields, dual labels, saved with the part, tests/w06_test.gd


EXTRA="$EXTRA w07:w"   # w07: arithmetic in number fields (25*2+3), scripts/num_expr.gd, tests/w07_test.gd


EXTRA="$EXTRA w02:w"   # w02: sketch health free / fully defined / over-constrained by colour + the clashing pair named, tests/w02_test.gd


EXTRA="$EXTRA w03:w"   # W03: stable references: hinge pivot follows the body box after a step-1 resize, tests/w03_test.gd


EXTRA="$EXTRA w06b:w"   # W06b: units in type-while-drawing, dialog defaults in project unit, tests/w06b_test.gd


EXTRA="$EXTRA w02b:w"   # w02b: health text fully visible + UI-dimensioned rectangle fully defined, tests/w02b_test.gd
EXTRA="$EXTRA w09b:w"   # w09b: pick-through list shows body names / the making feature, tests/w09b_test.gd


EXTRA="$EXTRA w05b:w"   # w05b: checklist triangles, Split to fit, OBJ and GLB follow the mesh quality, tests/w05b_test.gd


EXTRA="$EXTRA w10b:w"   # w10b: the app piece counter _lumps counts edge-touching boxes as 2, tests/w10b_test.gd


EXTRA="$EXTRA s257:w"   # s257: frame_to finds a body by its bname name AND its stable body key, tests/s257_test.gd


EXTRA="$EXTRA s258:w"   # s258: a look that glows (emission colour + strength on an appear step, saved, drawn as emission), tests/s258_test.gd


EXTRA="$EXTRA s259:w"   # s259: playblast motion blur shutter/steps options, shots render blur, scripts/blast_blur.gd, tests/s259_test.gd


EXTRA="$EXTRA s260:w"   # s260 CURVE EXTRAPOLATION: constant / linear / cycle on a hinge curve (tests/s260_test.gd; needs the CAD DLL for the UI bars)


EXTRA="$EXTRA w10c:w"   # W10c: Easy Pull it up says line-touch and offers the nudge, tests/w10c_test.gd


EXTRA="$EXTRA w02c:w"   # w02c: Dimension tool on a rectangle corner gives x / y from the origin, tests/w02c_test.gd


EXTRA="$EXTRA w03b:w"


EXTRA="$EXTRA s262:w"   # s262: Exploded view, scripts/build/explode_view.gd, tests/s262_test.gd
EXTRA="$EXTRA s262ui:w"   # s262: Exploded view in the app (clicks, camera, strip), tests/s262ui_test.gd


EXTRA="$EXTRA w09c:w"


EXTRA="$EXTRA w03c:w"   # w03c: body keys on the steps that point at a body; insert_step / delete_step on the 297-step temple, tests/w03c_test.gd


EXTRA="$EXTRA s263:w"   # s263: dark product studio + continuous ring band, tests/s263_test.gd
EXTRA="$EXTRA s269:w"   # s269: film keys (look/emission hue cycle, spin rpm + extrapolation, move) + Film mode in the dark studio, tests/s269_test.gd
EXTRA="$EXTRA s269b:w"   # s269b: film panel opaque + view fills it, reflective floor follows keyed materials, tests/s269b_test.gd


EXTRA="$EXTRA w03e:w"   # w03e: key-aware incremental cache + nested face.body keys, tests/w03e_test.gd


EXTRA="$EXTRA s277:w"   # s277/s273: glossy blurred floor, wide bloom, preset levels, aluminium + nickel, face-scaled brush, tests/s277_test.gd


EXTRA="$EXTRA s261:w"   # s261: Part feature instances: N copies of a body on a face as one MultiMesh, scatter with no-overlap + seed, baked at export, tests/s261_test.gd


EXTRA="$EXTRA w10d:w"   # W10d: the Pull it up hover card stays clear of the line-touch note, tests/w10d_test.gd




EXTRA="$EXTRA s262b:w"   # s262b: exploded view v2 (visible area, timeline keys, 256+ bodies), tests/s262b_test.gd


EXTRA="$EXTRA s265:w"   # s265: lane of small Part fixes from the GPU build, tests/s265_test.gd




EXTRA="$EXTRA s262b:w"   # s262b: exploded view v2 (visible area, timeline keys, 256+ bodies), tests/s262b_test.gd
EXTRA="$EXTRA s277:w"   # s277/s273: glossy blurred floor, wide bloom, preset levels, aluminium + nickel, face-scaled brush, tests/s277_test.gd
EXTRA="$EXTRA s262c:w"   # s262c: GPU explode v2 layout, tests/s262c_test.gd


EXTRA="$EXTRA w03d:w"   # w03d: fillet face pair for hole rims (cylinder half), corner, body keys, tests/w03d_test.gd
EXTRA="$EXTRA s269c:w"   # s269c: film framing includes the reflection, film keys past 256 bodies, spin/move curve strip, tests/s269c_test.gd


EXTRA="$EXTRA s277b:w"

EXTRA="$EXTRA c03:w"   # C03: Join / New body choice, mirror across any plane, printer tolerance presets, tests/c03_test.gd
EXTRA="$EXTRA c01:w"   # c01: view history, invert orbit/pan, the cube Top per scene, tests/c01_test.gd


EXTRA="$EXTRA c02:w"   # c02: pose library update, multi-delete, rename, tests/c02_test.gd


EXTRA="$EXTRA c04:w"   # c04: clip import checks and Stay in place, tests/c04_test.gd



EXTRA="$EXTRA c05:w"   # c05: bad spots panel, hand shape check, finger bleed check, tests/c05_test.gd


EXTRA="$EXTRA c06:h"   # C06 agent math for building + pictures: part_facts fields, frame_facts light block, MCP advertises them, tests/c06_test.gd
EXTRA="$EXTRA c06mcp:h"   # C06: MCP round trip of the maths tools (tests/py/c06_drive.py)


EXTRA="$EXTRA s277b:w"
EXTRA="$EXTRA s277c:w"   # s277c/s262d: card body brightness in a fixed box, explode film camera margin + ring halo, tests/s277c_test.gd
EXTRA="$EXTRA s277c2:w"   # s277c2/s262d round 2 readers (grey-body mean, edge pixels), tests/s277c2_test.gd
EXTRA="$EXTRA c07:w"   # c07: own-axis shot camera orbit, pivot ball, joint dot + axis keep (opt-in), tests/c07_test.gd


EXTRA="$EXTRA c08:w"   # c08/C08: sides from geometry, facing axis, hand-bend check, tests/c08_test.gd


EXTRA="$EXTRA c09:w"   # c09: export name template, FBX shot camera, lightmap UV2


EXTRA="$EXTRA c10:w"   # C10: print honesty: minimum-layer-time note, export read-back, M2..M10 screw fit table + Fit chip (tests/c10_test.gd; needs the CAD DLL)


EXTRA="$EXTRA c13:w"   # C13: pose IK/FK state, prop attach/detach frame, cape stretch readout (tests/c13_test.gd)


EXTRA="$EXTRA c14:w"   # c14: rig pre-check, footage pre-check, cut-list CSV locale, tests/c14_test.gd

EXTRA="$EXTRA c24:w"   # C24: hinge second axis, pivot on a visible feature (tests/c24_test.gd)

EXTRA="$EXTRA c15:w"   # C15: sketch re-plane preview, SVG import scale check, assembly degrees of freedom, tests/c15_test.gd


EXTRA="$EXTRA c16:w"   # C16: guided first pose (opt-in command) + clip licence line from repo data (tests/c16_test.gd)


EXTRA="$EXTRA c18:w"   # C18 door hinge edge, one-time Join undo note, scaled Join touch tolerance, tests/c18_test.gd


EXTRA="$EXTRA c19:w"   # C19: bone-map unmapped list, gpu notice, no-network scan, tests/c19_test.gd


EXTRA="$EXTRA c21:w"   # C21: how-to-fix on every failed step, free shapes ringed, 1.75 m fix (tests/c21_test.gd)


EXTRA="$EXTRA c22:w"   # C22: attach to either hand, grip by the handle, IK/FK joint-position snap (tests/c22_test.gd)


EXTRA="$EXTRA c12:w"   # c12: blueprint callouts, dim style presets, custom 1:1 sheets, tests/c12_test.gd


EXTRA="$EXTRA c20:w"   # C20: print fit: hinge clearance from the printer preset + knuckle fuse check, export tessellation = fit/4 (opt-in), support anchor width check (tests/c20_test.gd; needs the CAD DLL)


EXTRA="$EXTRA c17:w"   # C17 mesh print safety: internal-shell check, repair list + undo, reload check of written STL/3MF (tests/c17_test.gd; needs the CAD DLL)


EXTRA="$EXTRA c11:w"   # c11: pt_BR missing-string scanner, sticky keys, bad GPU driver list


EXTRA="$EXTRA c26:w"   # C26: pick-hit check (pick_check.gd) + per-character cost line (char_cost.gd), tests/c26_test.gd
EXTRA="$EXTRA c29:w"   # C29: one-click body pick, no panel over the body (tests/c29_test.gd)


EXTRA="$EXTRA c25:w"   # C25: one Move rule in/out of sketch, render time estimate (tests/c25_test.gd)


EXTRA="$EXTRA c23:w"   # c23: 3MF colour read-back + auto format, FBX unit/axis presets, GIF ordered dither + Smooth GIF button (tests/c23_test.gd)
EXTRA="$EXTRA c28:w"   # c28: FBX For choice in the Export dialog (tests/c28_test.gd)


EXTRA="$EXTRA c27:w"   # C27: support removal choice in the 3D-print export (tests/c27_test.gd)


EXTRA="$EXTRA c31:w"   # c31: pt_BR 447 strings, placeholders, CRLF, review list, fit at 1280x720
EXTRA="$EXTRA c35:w"   # c35: pt_BR fit across pages, popups, Export, 1280x720 and 1024x600




EXTRA="$EXTRA c30:w"


EXTRA="$EXTRA c32:w"   # C32: support gap/interface in the slicers settings files (tests/c32_test.gd)


EXTRA="$EXTRA c33:w"   # C33: free ring vs yellow selection, hovered label contrast (tests/c33_test.gd)


EXTRA="$EXTRA c36:w"   # C36: grip a prop by its handle, wrist solved from the handle axis (tests/c36_test.gd)


EXTRA="$EXTRA c38:w"   # C38: coincident faces nudged 0.01 mm in words, heavy boolean in steps with progress + Cancel (tests/c38_test.gd)


EXTRA="$EXTRA c39:w"   # c39: FBX materials (tests/c39_test.gd)


EXTRA="$EXTRA c41:w"   # c41: #184 invert orbit X / Y apart, #311 bad spots (built by C05) checked
EXTRA="$EXTRA c54:w"   # c54: cloth self-collision (tests/c54_test.gd)

EXTRA="$EXTRA c53:w"   # c53: SVG/DXF import into a Part sketch (tests/c53_test.gd)

EXTRA="$EXTRA c42:w"   # C42 stay-in-place export toggle + lightmap UV1 Blender readback (tests/c42_test.gd)


EXTRA="$EXTRA c43:w"   # C43: Printer row in Export (saved preset the fit tools read) + the written STL/3MF re-read as the preview (tests/c43_test.gd)


EXTRA="$EXTRA c44:w"   # C44: Extrude up to a face or edge with an offset, tests/c44_test.gd


EXTRA="$EXTRA c37:w"   # C37: Rounded rectangle + Slot sketch shapes, typed Radius for Circle/corners, Size first (tests/c37_test.gd; needs the CAD DLL)


EXTRA="$EXTRA c46:w"   # c46: the Combine dialog runs a many-tool combine stepwise with progress and Cancel (tests/c46_test.gd)


EXTRA="$EXTRA c45:w"   # c45: Alt+click through to the hidden face; sketch stack picker


EXTRA="$EXTRA c47:w"   # c47: mirror you can trust: facing axis from geometry (#273), side from geometry (#274), mirror seam kink (#251) (tests/c47_test.gd)
EXTRA="$EXTRA c51:w"
EXTRA="$EXTRA c48:w"   # c48: joints leave the app (tests/c48_test.gd, c48_blender.py)
EXTRA="$EXTRA c48ui:w"   # c48ui: joints export + frame row by real clicks (tests/c48ui_test.gd)
EXTRA="$EXTRA c50:w"   # c50: sketch reference geometry + item labels (tests/c50_test.gd)


EXTRA="$EXTRA c58:w"   # C58: Part side dialogs keep OK/Cancel reachable, tests/c58_test.gd


EXTRA="$EXTRA c52:w"   # c52: Gear template Rack and pinion mode (pitch, centre distance, backlash, roll overlap measured on the mesh), Gear pair byte-identical, pt_BR (tests/c52_test.gd; needs the CAD DLL)


EXTRA="$EXTRA s245:w"   # s245: look-table kinds window back / window grid / door panel / tree / grass (tests/s245_test.gd)



EXTRA="$EXTRA c55:w"   # c55: one SVG parser, 16 recorded output hashes unchanged (tests/c55_test.gd)


EXTRA="$EXTRA b07:w"   # b07: no two visible buttons overlap in Easy Part at 1600x900 / 1280x720 / 1024x600 (tests/b07_test.gd)


EXTRA="$EXTRA c56:w"   # c56: English ANIMATE/SURFACE tabs fit their cell at 1280 and 1920 (tests/c56_test.gd)



EXTRA="$EXTRA c57:w"   # c57: slicer-like print estimate (walls + infill, time from flow, bigger-than-bed scale models, 5 kg sanity) against Bambu Studio on a cube and Benchy (tests/c57_test.gd)
EXTRA="$EXTRA ch1a:w"   # ch1a: one-storey house from a real reference, tests/ch1a_test.gd
EXTRA="$EXTRA ch1b:w"   # ch1b: house check, IRC spans/headers/studs/bracing/uplift/footing + first-principles cross-check (tests/ch1b_test.gd)


EXTRA="$EXTRA c59:w"   # c59: Easy Part left column: no button/label overlap and no edge chip cut below 4 letters at 1024/1280/1600 (tests/c59_test.gd)


EXTRA="$EXTRA c54n:w"   # c54n: C++ cloth self-collision (tests/c54n_test.gd; SKIPs without the DLL)


EXTRA="$EXTRA c49b:w"   # C49b: Off/Look/Print strip clear of Part dialogs, browser, timeline, cube; tests/c49b_test.gd
EXTRA="$EXTRA c60:w"   # C60: Part browser and side dialogs hold a stable size over 60 idle frames, tests/c60_test.gd



EXTRA="$EXTRA c63:w"   # c63: the no-printer print estimate lands on a measured flow and names the printer it assumes (tests/c63_test.gd)


EXTRA="$EXTRA c65:w"   # c65: over 256 bodies the look-merge ignores the body name: 600 named boxes in 6 materials each keep their own (tests/c65_test.gd)


EXTRA="$EXTRA c62:w"   # C62: no bone end under the toolbar or a panel in the opening view / Fit / Home at 1024, 1280, 1920

EXTRA="$EXTRA ch7:w"   # CH7: the 8 s chained parkour run on a built course; hand plants, speed continuity, landing knee flex, foot skate, penetration (tests/ch7_test.gd)




EXTRA="$EXTRA c70:w"   # C70: involute Gear sketch tool + a pattern fused in one boolean (tests/c70_test.gd)
EXTRA="$EXTRA ch10:w"   # ch10: the house under wind and El Centro, 3D frame solver (native KineFrameNative + GDScript twin), tests/ch10_test.gd


EXTRA="$EXTRA s249:w"
EXTRA="$EXTRA s249n:w"



EXTRA="$EXTRA c64:w"   # c64: C++ conjugate gradient of the heat weights equals GDScript (1e-6), 5x faster (tests/c64_test.gd)
EXTRA="$EXTRA c64_prof:w"   # c64: hot-loop profile table (tests/c64_prof_test.gd)


EXTRA="$EXTRA c68:w"   # c68: Easy Part step hint fully visible (not overlapped or clipped) at 1024/1280/1600 (tests/c68_test.gd)




EXTRA="$EXTRA ch2:w"   # ch2: the regulator clock: 720:12:1 train, 994 mm pendulum period, 0 mm3 clearance over 60 s at 60 fps, backlash < 5 % module, minute hand 6 deg per 60 s, C++ = GDScript (tests/ch2_test.gd)


EXTRA="$EXTRA c66:w"   # C66: the hands card overlaps no button or status text and sits inside the 3D view at 1024, 1280, 1920


EXTRA="$EXTRA c69:w"   # C69: every tooltip in Easy Part / Pose is wrapped to <= 440 px and fits the window at 1024 and 1280 (scripts/tooltip_fit.gd; tests/c69_test.gd)


EXTRA="$EXTRA c70:w"   # C70: involute Gear sketch tool + a pattern fused in one boolean (tests/c70_test.gd)


EXTRA="$EXTRA c72:w"   # C72: the tooltip popup (TooltipPanel) is opaque with a 1 px border


EXTRA="$EXTRA c73:w"   # C73: no CR inside any .gd string literal (.gitattributes *.gd eol=lf); GREY_TAG hints match (tests/c73_test.gd)


EXTRA="$EXTRA ch4:w"   # ch4: solid oak grain, dovetailed box (docs/CH4_REFERENCE.md, tests/ch4_test.gd)


EXTRA="$EXTRA ch1f:w"   # ch1f: soil-structure interaction + masonry / light steel / wood on the CH1 plan, heave and wind (physics model, NOT an NBR check), tests/ch1f_test.gd

EXTRA="$EXTRA ch1e:w"   # ch1e: real fasteners on the CH1 house (docs/CH1e_REFERENCE.md, tests/ch1e_test.gd)
EXTRA="$EXTRA c78:w"   # c78: installer unit bars (docs/C78_INSTALLER.md); the installer run itself is tests/c78_test.sh
EXTRA="$EXTRA c79:w"   # c79: slicer lookup no longer holds the quit (docs/C79_FEEDBACK.md); the quit-time bars are tests/c79_test.sh
EXTRA="$EXTRA c75:w"   # C75: KineSkinNative.correct, the DQ/LBS skinning pre-correction in C++ (equal to GDScript within 1e-5, >=10x, fallback, ulp control) (tests/c75_test.gd)
EXTRA="$EXTRA c77:w"   # C77: exit-hang guard: no ungated OCCT parallel switch, every Thread.start joined, planted controls caught (tests/c77_test.gd)
EXTRA="$EXTRA ch12:w"   # ch12: footbridge sway under a phase-locking crowd (Dallard 2001), tests/ch12_test.gd
EXTRA="$EXTRA sretopo:w"   # sretopo (lane I11): stroke-guided retopology after Takayama et al. 2013, C++ KineRetopoNative + GDScript fill twin (tests/sretopo_test.gd)
EXTRA="$EXTRA ch14:w"   # ch14: water-syringe arm builds a 3-2-1 can pyramid: reach, 180 deg rack base, torque, grip, compliance backlash, stack stability, materials, build sweep, BOM cost (docs/CH14_REFERENCE.md), tests/ch14_test.gd
EXTRA="$EXTRA ch13:w"   # ch13: single-cylinder engine (Honda C50 class): ISO 286 fits, thermal clearance, stack-up, slider-crank torque, FDM compensation, 7 Parts animated + section (docs/CH13_REFERENCE.md), tests/ch13_test.gd
EXTRA="$EXTRA aicost:w"   # AI COST (11-04): Ask AI caches its prompt (scene moved after the cache mark), counts tokens per question (user://ai_usage.csv), commands {find} (tests/aicost_test.gd)
EXTRA="$EXTRA scalefix:w"   # scalefix: Part at building scale: size-scaled meshing, a split half-space sized to the bodies, a refused cut is an error (CH15 gaps G27-G29), tests/scalefix_test.gd
EXTRA="$EXTRA ch15:w"   # ch15: Angra 2 class PWR plant: primary heat balance, IF97 Rankine, electrical one-line, decay heat, containment sphere, layout overlaps, build sequence + section video, blueprints (docs/CH15_REFERENCE.md), tests/ch15_test.gd
EXTRA="$EXTRA g1motion:w"   # G1MOTION: Assembly Check motion: drives + links, exact-solid clash sweep with a box prefilter, contact vs clash, scrub slider, one undo step (gap G1, tests/g1motion_test.gd)
EXTRA="$EXTRA hand:w"   # HAND (G23/G38): HandShape palm slab + finger capsules (ANSUR II sizes), palm_flat within the wrist limits, hook over an edge, close_on a 10 mm rope; Rulebook.prop_hits uses it (tests/hand_test.gd)
EXTRA="$EXTRA g2loop:w"   # G2LOOP: Assembly joints (revolute / slider / fixed) with a planar closed-loop Newton solver: slider-crank and four-bar vs closed forms, the CH13 engine driven from its own record, check_motion along the loop (gap G2, tests/g2loop_test.gd)
EXTRA="$EXTRA g7time:w"   # G7TIME: Assembly drives keyed on a timeline (linear / smooth / hold), played through the loop solver, Check motion along the animation with clash times, the shared render helper (frames, contact sheet, mp4), the timeline strip in Check motion (gaps G7 / G11, tests/g7time_test.gd)
EXTRA="$EXTRA g8bom:w"   # G8BOM: Assembly bill of materials: mass from the exact solids x density (data/prices.json, every price with a source + date), identical parts grouped, CH14 reproduced line by line, the cheaper view + cheapest whole design under a named check, CSV, the BOM panel with one-step undo (gap G8, tests/g8bom_test.gd)
EXTRA="$EXTRA g33stage:w"   # G33STAGE: Assembly build stages: ordered stages add parts, an exact-solid support check (contact within tol, ground, declared hangs; collisions with built parts in mm3), drop-in poses, the staged video with a section cut (AssemblyRender steps), the Stages panel with one-step undo (gap G33, tests/g33stage_test.gd)
EXTRA="$EXTRA g45dist:w"   # G45DIST: KCad.distance (OCCT BRepExtrema_DistShapeShape, KineCAD 6): boxes / spheres vs hand to 1e-9 m, the G33 support check on one distance per pair (same verdict as the seven-boolean test on every g33stage fixture and CH15, >= 5x faster), tests/g45dist_test.gd
EXTRA="$EXTRA ch16:w"   # ch16: Sony a7 / ILCE-7 class camera, separate Parts, mount/sensor stack, electronics, staged movie, sheets and AssemblyBom (docs/CH16_REFERENCE.md), tests/ch16_test.gd
EXTRA="$EXTRA g30draw:w"   # G30DRAW: Assembly exact-solid plan/front/section drawing + rated power/signal schematic, SVG/PNG and UI export (gaps G30/G31)
EXTRA="$EXTRA g21compare:w"   # g21compare: shared render-vs-reference stats and side-by-side (CompareShot)
