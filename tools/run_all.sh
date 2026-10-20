#!/bin/sh
# ALL SUITES, one line each (GATES O1). From the poser folder:   sh tools/run_all.sh [name ...]
# A suite FAILS on a non-zero exit, on any "FAIL" line, or on a SCRIPT ERROR in its log (an exit 0 is not enough:
# a script error can skip the checks after it). Logs: $LOGS (default $TMP/poser_suites). Exit code = suites failed.
G=${G:-/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe}
LOGS=${LOGS:-${TMP:-/tmp}/poser_suites}
mkdir -p "$LOGS"
# name:mode   (h = headless, w = needs a window)
ALL="actors_file:h math:h spline:h tween:h rules:h fix:h mirror:h flip_survey:h tween_undo:w monkey:w fix_window:w tools_window:w
timeline:w hand_drag:w command_search:w view_cube:w browser:w ring:w empty_state:w ribbon:w drag_any:w units:h actors_file:h math:h spline:h tween:h rules:h fix:h mirror:h flip_survey:h tween_undo:w monkey:w fix_window:w tools_window:w euler:h"
EXTRA="undo_audit_s0:w undo_audit_s1:w undo_audit_s2:w undo_audit_s3:w undo_fuzz:w undo_tree:w cli:h scene_list:w theme:w status_bar:w icons:w paste:w ease:w plant:w pole:w fix_preview:w search_forgive:w history:w confirm:w hover_hint:w ui_scale:w why:w say_next:h examples:w tour:w schema:h diff:h pose_words:h serve:h agent:h dummy_async:w names:w determinism:h keyboard:w mcp:h measure:h clicks:w autosave:h loop:h balance:h retime:w keys_overlay:w names_disk:h edge_counts:h scrub_bounds:w check_all:h mirror_list:h popup_leak:w ghosts_follow:h search_one_list:w browser_place:w empty_back:w small_window:w ring_edges:w symmetry:w cube_views:w greyed_why:w onion_fade:h graph_read:w timeline_marks:w floor_fade:h side_colours:h feedback:w weapon_picker:w type_scale:h empty_paths:w hover:w lock_part:w num_entry:w nav_bar:w multi_select:w sel_sets:w versions:w grip_mirror:h browser_eye:w hover_sync:w game_fold:h game_table:h plant_edges:h dual_wield:w glb_export:h bvh_export:h engine_names:h hints:w fold:w launcher:h drag_stop:w toolbar:w inspector:w browser_tree:w strip:w quiet:w view_share:w props:h importer:h set:w stand_set:h prop_check:h use_set:w carry:w carry_form:h jump:h jump_ui:w part_keys:h part_keys_ui:w curves:h inbetween:h preview_range:w markers:h playblast:w playblast_export:w bvh_import:h throw:h jump_physics:h lift_form:h people_doc:h decompose:h walk_arm:h walk_legs:h balance_view:h plant_all:h hand_curl:h back_bend:h shoulder_follow:w breath:h gait_band:h stage:w layer:h key_interp:h curve_editor:w curve_multi:w key_blend:w curve_mods:h bake:h curve_views:w curve_why:w dope_copy:w layers:h layer_fix:h layer_merge:h drag_speed:h dope_sheet:w breakdowner:h foot_roll:h look_at:h mocap_clean:h usd_export:h shading:w gait:h walk_people:h video_import:h video_ui:w video_grip:h grip_save:h grip_wrap:h grip_types:h grip_magnet:h agent_tools:h llm_client:h ai_box:w ik_pin:h cross_contact:h actors_main:h audio_track:w actors_view:w actors_hit:w actors_export:h ik_handles:w graph_editor:w constraints:h shot_camera:w proportions:h fighter_hover:w camera_gizmo:w graph_range:w drivers:h grip_scale:h sets:h engine_export:h foot_plant:h pose_library:w anim_import:h props_generic:h easy_mode:w journal:w hotkeys:w clips:w toes_walk:h human_limits:h humancheck_shot:w foot_handles:w frame_data:h ease_presets:h foot_joints:h critique:h twinning:h video_cleanup:h choreo:w hit_reaction:w style_transfer:h any_grip:h line_of_action:w live_puppet:w play_perf:w stunt_load:h version_diff:w motion_match:h lip_sync:h beat_track:h secondary_motion:h weapon_trail:h co_edit:h text_blocking:h weapon_clash:h hit_boxes:w ragdoll:h range_rings:h whywrong:w fatigue:w review:w floorsnap:h retime_handles:w autokey:w play_speed:w undonames:w scene_thumbs:w weight_feel:w save_prompt:w easeslider:h mirror_inplace:w tip_video:w searchall:w templates:w pose_copy:h export_dialog:h themescale:w recent:w ikfk:h space:h tangents:w spine_ik:w key_reduce:h onion_parts:w retimerange:h keytypes:h trail_edit:w weightpaint:w hand_pose:h hand_pose_ui:w camshake:w camseq:w corrective:h face:w gentle:w fbx_export:h usd_layers:h precise_pick:w macros:w batch_export:w customattr:w clipwarp:w posematch:w hair:w dummyview:w contactik:w cloth:w rigid_drop:w handcap:h multicam:h multicam_ui:w multicam_app:w audiotracks:w rootpath:w scene_diff:w assetstore:w crowd:w stairs:w marker_notes:w plugins:w limit_tint:w rise:h rise_ui:w perf4:w pathwalk:w pathrun:h pathwalk_ui:w feasible:h feasible_shot:w pages:w cardstrip:w videoiq:w retarget:h vroot:h bodypage:w r2:w r17:w r3:w r12:w r5:w r6:w r18:w r13:w r1:w r10:h r4:w"
pick=${*:-$ALL $EXTRA}
n=0; bad=0
for s in $pick; do
  case $s in *:*) ;; *) s=$(echo "$ALL $EXTRA" | tr ' \n' '\n\n' | grep "^$s:" | head -1) ;; esac
  name=${s%%:*}; mode=${s##*:}
  f=tests/${name}_test.gd; [ -f "$f" ] || f=tests/$name.gd
  if [ ! -f "$f" ]; then echo "MISSING $name"; n=$((n+1)); bad=$((bad+1)); continue; fi
  flag=""; [ "$mode" = h ] && flag=--headless
  log="$LOGS/$name.log"
  t0=$(date +%s)
  # a SCRIPT ERROR inside a test's _init stops the script before quit(): Godot would sit there until the timeout.
  # So: watch the log; on a script error give it 5 s, then stop it (the suite FAILS either way); past $TIMEOUT, stop it
  "$G" $flag --path . -s "$f" > "$log" 2>&1 &
  pid=$!; why=""; seen=0
  while kill -0 $pid 2>/dev/null; do
    sleep 1
    el=$(( $(date +%s) - t0 ))
    if [ $seen -eq 0 ] && grep -q "SCRIPT ERROR" "$log"; then seen=$el; fi
    if [ $seen -gt 0 ] && [ $((el - seen)) -ge 5 ]; then why="stopped after a script error"; kill $pid 2>/dev/null; break; fi
    if [ $el -ge ${TIMEOUT:-400} ]; then why="TIMEOUT ${TIMEOUT:-400}s"; kill $pid 2>/dev/null; break; fi
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
