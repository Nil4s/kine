# AI cost: building in Kine with an agent (measured 11-04)

How much it costs when an AI (OpenCode, Claude Code, an MCP client, or Kine's own Ask AI box) builds or
animates something in Kine, and how to keep it cheap.

## Measured

| Job | Route | Cost | Tool calls | Time |
|---|---|---|---|---|
| Syringe hydraulic arm, 28 bodies / 71 steps | agent + `kine_call.py part_build` (Opus) | **$0.36** | 2 | 2 min |
| Snake skin, 81 bodies / 480 scales + 40 belly plates | agent + `kine_call.py part_build` (Opus) | **$0.75** | 7 | 22 min * |
| Same two on Sonnet / Haiku (the same tokens, re-priced) | | $0.28 / $0.09 and $0.59 / $0.20 | | |
| CH14 syringe arm, lane that wrote a GDScript generator + test | Claude Code lane | $7.88 (unfinished) | 71 | |
| Graphics-card film / Anzani engine / Chinese hall | Claude Code + Blender MCP | $11.95 / $3.30 / $3.20 | 52-130 | |
| Median lane writing a Kine feature (344 lanes) | Claude Code lane | $4.09 (p90 $11.95) | ~60 | |

\* Most of the 22 minutes was Kine joining 720 spheres (2 runs timed out); the tokens were small.
Numbers: OpenCode's own session records (`~/.local/share/opencode/opencode.db`) and `python tools/token_cost.py` for
Claude Code logs. Prices are list prices (Opus 5/25, Sonnet 3/15, Haiku 1/5 USD per M tokens; cache read 0.1x).

## Where the money goes

Cost is roughly **number of model turns x context size**. Each turn re-reads everything before it (cheaply when cached,
but still paid).

- **Starting an agent costs about $0.15-0.25 on Opus** (its system prompt and tool list, about 30-40k tokens, written to
  the cache once). After that, each extra tool call is about $0.02-0.06.
- **Code generation is the expensive way to build.** Writing a GDScript generator, or Blender Python through MCP,
  means many turns, long outputs, and screenshots that stay in the context.
- **Data is the cheap way.** One JSON record of steps (`part_build`) replaces a 267-line generator: the arm took
  2 calls.

## The cheap routes

1. **Parts:** `python tools/kine_call.py part_build @part.json` (or the MCP tool `part_build` with `--math`).
   - The record format is `{"name", "features": [steps]}`. Copy from `data/part_examples/` (syringe_arm.json,
     snake_skin.json).
   - Add `"facts": true` to get one line per body back.
   - `append: true` adds only the new steps to the part on screen, so you never resend the whole part.
2. **Commands:** `commands {"find": "mirror pose"}` returns the 25 best matches (1.2 KB). Never ask for the whole list
   (148 KB, about 30k tokens that stay in the context for every later turn).
3. **Ask AI box (animation):** its prompt is cached now (99 % of each turn is reused), and the box shows
   `USED: ... about $0.0xx` after each question. Every question is also logged in `user://ai_usage.csv`.
   Ollama on this machine is free.

## Rules for an agent working in Kine

- Write the whole record in ONE file write, then make ONE `kine_call.py` call. Fix it and rerun at most twice.
- Chain shell steps into one call. Cap output with `| tail -n 40`. Never poll with sleep loops.
- Don't read Kine's source to build a part; the step grammar is in `tools/mcp/poser_mcp.py` (part_build) and
  `scripts/build/part.gd` lines 3-64.
- Use the cheapest model that can do the job: Haiku or Sonnet for builds from a clear spec, Opus for design decisions.

## Gaps found by the benchmark (worth fixing; they cost runs)

- `prim` cannot be rotated or scaled, so tilted or flattened shapes (overlapping snake scales, a raised arm at 30 deg)
  need a second "seed" body or come out blocky.
- Joining hundreds of bodies (a pattern of a pattern, joined) takes over 10 minutes: use separate bodies or the
  `instances` step for repeats.
- A circular pattern only turns about axes through the origin.
