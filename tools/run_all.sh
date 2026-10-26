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
