# Kine: the app roadmap (2026-10-23)

Nick 10-23: "we dont have an roadmap for the app". The feature lists (`ROADMAP.md`, `ROADMAP_400.md`,
`INNOVATIONS.md`) say WHAT to build. This file says where Kine is going as a product, in what order, and
what has to be true before each step. Features are slotted into these milestones; a milestone is done
when its gates pass, not when a number of items is ticked.

## What Kine is

**The animation tool that knows it is animating a human.** Pose, animate, model and check a fighting
character in one app, and every step is checked against the real body: joint limits, balance, mass,
reaction time, human speed. Because the app can say what is wrong in numbers and words, it works for
three kinds of user nobody else serves well:

| who | what they get |
|---|---|
| Indie game devs (fighting / action games) | a character and its moveset, human-possible, frame data and hitboxes, straight into Godot / Unity / Unreal |
| Vibe coders and AI agents | an animation tool they can drive blind (MCP / CLI / local API): the body is the ground truth, not the picture |
| Beginners | an app that tells them why a move looks wrong and fixes it in one click, instead of years of eye training |

Not the goal: film VFX, general modeling for architecture or products, replacing Blender for everything.

## Where it stands (2026-10-23)

- 0.1.0, private repo, Windows main platform, runs from the Godot editor or `pose.bat`.
- About 380 scripts, about 500 test suites.
- Animation side deep: `ROADMAP.md` 66 / 77 items, innovations I1–I49 mostly done.
- Mesh side started: `ROADMAP_400.md` 56 / 400 ticked, plus 50 built this week on `w2-integ`
  (not yet merged into `poser-ui-rounds`).
- No installer, no website, no users outside Nick. Licence: MIT (to decide before going public, see below).

## Milestones

### M0. Solid ground (now, about 1 week)

Everything built so far merged, tested and trusted.

- [ ] `w2-integ` (wave 2 + 3, 50 items) merged into `poser-ui-rounds` through a PR
- [ ] the 29 suites that fail on the base branch fixed or put on a written skip list with a reason
- [ ] CI green: the PR job (`--changed`) and the 8-shard full run, each under 60 min
- [ ] tests never open a window on Nick's screen (done except 4 suites, see `tools/run_par.py`)
- [ ] timing bars sized for the real machine (romclash elbow stall and the other flaky ones)

Gate: a full CI run green twice in a row.

### M1. One fighter, start to finish (alpha, about 4–6 weeks)

The whole pipeline works for ONE character, without Nick's help:
BODY (make the body) → MODEL (armour, props) → SURFACE (UVs, materials) → rig + weights →
POSE / ANIMATE (a combo) → CHECK → DELIVER (glb into a Godot test scene that plays it).

- [ ] the four mesh pages un-greyed and usable end to end (ROADMAP_400 tracks A–H, the $ and $$ items in the way)
- [ ] save / load everything: bodies, armour, curves, modifiers in scene autosave (known gaps today)
- [ ] FBX body export, boolean in the modifier stack, origin used by pivot and export
- [ ] P19 task coach: "make a fighter" walks the user through every page with checks
- [ ] P21 mistake catcher, P03 redo panel, P25 crash report (local)

Gate, two parts (Nick 10-23: "not going public until I can make an animation without a tutorial... I'll
ask random people to try it out"):
1. Nick makes a fighter with a 3-hit combo and plays it in Godot with no tutorial, no docs, no asking.
2. Random people Nick picks, NOT from tech, do the same from one sentence of task. Kine records where each
   one gets stuck (local log of the last commands + the page + time spent), and every stuck point
   becomes a fix before the next tester. Nick being from tech does not count as proof: the outsiders do.

### M2. Agent-first (about 4 weeks, can overlap M1)

Kine becomes the animation tool an AI can use blind. The headline feature for launch.

- [ ] INNOVATIONS wave 1–2 (the agent foundation: possible-or-not, one score, text view, landmarks,
      make-it-possible, dry run)
- [ ] MCP server documented with a 5-minute "your agent makes a punch" guide (README_AI.md)
- [ ] one public demo: an agent, given only words, makes a combo that passes every check; the command
      log and the video side by side

Gate: Claude (any current model) given only the MCP tools and the sentence "make a jab-cross-hook for
this fighter" produces a clip with score above a bar set before the run, in 3 out of 3 tries.

### M3. Public beta (about 4 weeks)

Nothing goes public before M1's gate passes with outside, non-tech testers.

- [ ] Windows installer (exported build, no Godot install needed), auto-update check (opt-in)
- [ ] first-run: a 2-minute tour, a sample fighter, the task coach
- [ ] docs site: getting started, the pages, the agent guide, the checks and their sources
- [ ] crash report and feedback in the app (local file the user chooses to send)
- [ ] performance: 60 fps playback with two fighters on a mid-range GPU (Q track)
- [ ] the decisions below made

Gate: 20 outside testers, at least 10 finish the M1 task, crash-free sessions above 99 %.

### M4. 1.0

- [ ] the INNOVATIONS ★★★ items, the ROADMAP_400 items users asked for most in the beta
- [ ] Linux and macOS builds tested
- [ ] engine plug-ins: Godot add-on first (moveset + frame data import), then Unity, Unreal
- [ ] pricing live (if paid)

Gate: set from beta data, not now.

## Decisions Nick has to make (before M3)

| decision | options | why it matters |
|---|---|---|
| licence | keep MIT / source-available / closed | MIT lets anyone sell a copy of Kine; fine if free, a problem if Kine is the product |
| price | free / one-time / subscription / free + paid agent features | sets what the beta tests |
| name and site | Kine + Teschima Studios (current) | a domain and a store page take weeks |
| public repo | stay private / open after 1.0 | ties to the licence |

## How the lists feed this

| list | what it is | milestone |
|---|---|---|
| `ROADMAP.md` (R items, I1–I49) | the animation side, mostly done | finish the open I-items in M1–M2 |
| `ROADMAP_400.md` (400, 119 ★) | the mesh side, road to Maya / Blender | the $ / $$ items in M1, the rest after 1.0 by demand |
| `INNOVATIONS.md` (100) | only-Kine, body-aware, agent-first | waves 1–2 in M2, ★★★ by 1.0 |

Rules carried over: features first, one test per item with real numbers, the full suite once per 25
merged items (now in CI), human claims cited, Blender ideas only (GPL).
