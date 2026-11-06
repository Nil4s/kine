# LOOK4D: wiring the module into the MCP later

Nothing here is wired. `scripts/build/look4d.gd` (class `Look4D`) is a stand-alone module; tools/mcp/* and scripts/build/mcp_cad.gd are owned by MCPFAST and were not edited.

## What to call
`Look4D.produce(host, scene, out_dir)` (async) returns `{A, B, C (Images, 768x432), digest (D), d_text, meas, kin, contacts, ms}` and writes A.png B.png C.png D.json truth_data.json timing.json. A scene is the dictionary built in `scripts/build/look4d_scenes.gd` (`ids`, `build(world)`, `set_time(t)`, `camera`, `t0`, `h`, optional `named`, `arrow_t`, `contacts`, `shapes`). For the live session a scene wrapper has to be made from the current assembly: ids = part names, `set_time` = the assembly's pose at t (AssemblyAnim.pose_at), `contacts` = `look4d_scenes.asm_contacts(asm, xfs, named)`.

## Where a `look4d` tool would go (origin 6254e061, MCPFAST #222)
- `scripts/build/mcp_cad.gd`: `serve(m, method, p)` has a `match method:` (cad_part, cad_asm, cad_reset ...). Add `"look4d": return await Look4D.serve_tool(p)` next to them, and a `look4d(p)` function beside `check_fit`/`bom` that builds the scene wrapper from `_poses()` (the live assembly poses; `_poses_raw()` has the transforms), calls `Look4D.produce`, and returns `good({"d": digest, "c_path": ..., "tokens": ...})` (use `rnd(v, prec)` for the rounding it already has). Return D as the compact text first; return a PNG path only when `format` asks for C.
- `tools/mcp/poser_mcp.py`: add a `"look4d": ("look4d", "<description>", <schema>)` entry to the table that holds `cad_part`/`cad_asm` (the `--cad` set, line ~102) and let `call_cad` forward it; `batch` already chains cad tools.
- The tool must stay behind `--cad` (off the default tool list: every advertised tool costs tokens each turn).

## Shipping decision
Per docs/LOOK4D_DESIGN.md bars P1/P2: wire D first (text, cheapest); wire C only if P2 says C+D beats D on the spatial-reasoning types by 5 points or more; B is the fallback if P1 fails.
