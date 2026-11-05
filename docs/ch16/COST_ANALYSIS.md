# CH16 AI cost analysis (lead, 11-05)

Source: the lane's own `tool_calls.csv` (150 calls) joined with the standard token model (bytes/4 = tokens; every tool result stays in context and is re-read on every later turn). Prices: Sonnet input $3/M, cache write 1.25x = $3.75/M, cache read 0.1x = $0.30/M. This is an estimate of the RESULT-token cost, not the agent's generated output.

| tool | calls | result tokens | cache-read token-turns | est. write $ | est. read $ | est. $ per call |
|---|---:|---:|---:|---:|---:|---:|
| read | 54 | 87,034 | 11.55 M | 0.326 | 3.464 | 0.0702 |
| write | 7 | 31,500 | 2.40 M | 0.118 | 0.719 | 0.1196 |
| websearch | 10 | 13,725 | 1.77 M | 0.051 | 0.532 | 0.0583 |
| webfetch | 6 | 9,135 | 1.11 M | 0.034 | 0.332 | 0.0610 |
| edit | 45 | 5,487 | 0.39 M | 0.021 | 0.118 | 0.0031 |
| shell | 19 | 20,600 | 0.25 M | 0.077 | 0.076 | 0.0081 |
| grep | 7 | 1,400 | 0.14 M | 0.005 | 0.041 | 0.0066 |
| glob | 2 | 1,050 | 0.04 M | 0.004 | 0.011 | 0.0075 |
| **total** | **150** | **169,914** | **17.64 M** | **0.637** | **5.293** | **0.0395** |

- **Reading files is 64% of the measured result-token cost** ($3.79 of $5.93 including its cache write). One average `read` costs about 23x an `edit`.
- Only 1 of 54 reads was marked unneeded in hindsight, and only 4 re-reads: the problem is not waste, it is that necessary context is expensive.
- **5 of 6 webfetches were unneeded**; websearch was always needed. Prefer search snippets, fetch only the chosen source.
- The app's new tools did their job: no new grab loop, no new BOM, no custom staging. GDScript was still needed for Assembly drawings, the electronics diagram, the mount-cone check, clash reporting and camera-parametric parts.

## Where to make Kine cheaper for AI
1. **Machine-readable API summaries.** A `docs/API_FOR_AGENTS.md` (or `kine --api-digest`) with the signatures and one-line semantics of Part, Assembly, AssemblyStage/Render/Bom, SectionLook, KCad. The lane read ~150 KB of source to learn those APIs; a 10 KB digest would have cut the read cost by an order of magnitude.
2. **A challenge scaffold command.** `tools/new_challenge.gd CH17` writes the reference doc, the test header with planted-control slots, the build/scene/stage/render/BOM wiring and the feedback doc. Most `write` bytes were this boilerplate.
3. **Return summaries, not files.** Test runners should print only failing bars plus a 10-line summary by default (wtest already greps; keep direct runs equally terse).
4. **Drawing from the Assembly** (G30) and **schematics** (G31) are now the top two remaining hand-written chunks; closing them removes both code and the reads needed to write it.
5. **Price external data once.** Cache spec sheets/teardown facts in the reference doc on first use; avoid webfetch unless the snippet is insufficient.
