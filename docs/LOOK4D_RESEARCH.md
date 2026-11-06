# LOOK4D research: letting an AI "see" a Kine scene in 3D + time

Lane LOOK4D, 2026-11-05. No app code. Companion: `docs/LOOK4D_DESIGN.md`.
Method note: sources were found by web search and read at abstract/snippet level, not full text. Numbers I did not verify are marked UNVERIFIED and are not relied on. Peer-reviewed = journal or conference proceedings; PREPRINT = arXiv only (as far as I could see).

## 0. Hypothesis under test
For an LLM the gain comes from the **encoding** (labels, glyphs, trails, exact numbers), not from a new sense. The pilot (4 balls) supports this weakly: text depth labels were right, arrows 3/4 right, colour-as-number misread, plain screenshot gave no depth/motion and merged overlapping balls. n=1 scene, one reader: it is an anecdote, not evidence.

## 1. 4D representations (what "4D" means in the literature)
| Representation | What it stores | Relevance to Kine | Status | Source |
|---|---|---|---|---|
| Light field | radiance over (u,v,s,t): the *other* 4D, no time | irrelevant (no time axis) | peer-reviewed | Levoy & Hanrahan, SIGGRAPH 1996 https://graphics.stanford.edu/papers/light/ |
| 4D Gaussian splatting (deformation field) | Gaussians + time-conditioned deformation, 30-82 FPS (figures vary by version) | reconstruction from video; Kine already has exact geometry, so nothing to reconstruct | peer-reviewed (CVPR 2024) | https://arxiv.org/abs/2310.08528 |
| Native-4D-primitive splatting | 4D ellipsoids | same | preprint/extended | https://arxiv.org/abs/2412.20720 |
| Dynamic 3D Gaussians | persistent Gaussians with 6-DoF tracks; tracking emerges with no flow input | the idea "persistent identity + per-element pose track" is exactly what Kine has natively (part ids, drives) | peer-reviewed (3DV 2024) | https://arxiv.org/abs/2308.09713 |
| Scene flow | per-point 3D motion vectors between frames | our per-object velocity IS ground-truth scene flow, free from the pose at t-dt, t+dt | peer-reviewed surveys | https://diglib.eg.org/handle/10.1111/cgf14795 ; https://www.pubmed.gov/37751348/ |
| RGB-D + optical flow | colour, depth, 2D motion per pixel | what a renderer can emit; flow-as-image is a *colour-coded quantity* (risk, see section 2) | peer-reviewed (RAFT, ECCV 2020) | https://arxiv.org/abs/2003.12039 |
| Event cameras | asynchronous per-pixel brightness-change stream, microsecond timing, 140 dB | models motion edges without frames; no analogue needed, we have exact motion | peer-reviewed (TPAMI 2022) | https://arxiv.org/abs/1904.08405 |
| 4D radar | range, azimuth, elevation, Doppler velocity; sparse, noisy | direct velocity measurement per point; confirms "velocity as a first-class channel" | PREPRINT survey | https://arxiv.org/abs/2306.04242 |
| Ultrasound 4D | volume + time | no evidence gathered; I found nothing worth citing. Thin. | n/a | n/a |

Take-away: every serious 4D representation carries **explicit per-element state over time** (pose track, velocity), not just pixels. Kine can emit that exactly, with no estimation, which is the opposite of the reconstruction literature's problem.

## 2. What VLMs read well or badly
- **Spatiotemporal / "4D":** VLM4D (translation, rotation, perspective, motion continuity) reports large gaps to humans and says models fail at integrating several cues and keeping temporal coherence. PREPRINT with ICCV 2025 poster listing; numbers UNVERIFIED. https://arxiv.org/abs/2508.02095
- **Motion in video LLMs:** TempCompass uses conflicting video pairs with identical static content; models do fine on action (static cue) but poorly on speed, direction, event order; video models did not beat their image counterparts in the original paper. PREPRINT; leaderboard numbers UNVERIFIED. https://arxiv.org/abs/2403.00476 . Implication: giving more frames is not enough; frames must be arranged so that the difference is visible (trails/arrows) or given as numbers.
- **Spatial relations:** What'sUp (EMNLP 2023, peer-reviewed): VLMs struggle with left/right/above/under even when object identity is fixed; pretraining data has little reliable spatial signal. https://aclanthology.org/2023.emnlp-main.568
- **Metric depth / quantities:** SpatialVLM (CVPR 2024, peer-reviewed): lack of quantitative 3D (distances, sizes) attributed to missing training data; fixed by training on synthetic metric VQA. https://arxiv.org/abs/2401.12168 . The "99% vs 1% valid numbers vs GPT-4V" figure is from a third-party site: UNVERIFIED.
- **Depth ordering / occlusion:** DepthCues (CVPR 2025, peer-reviewed) is about vision backbones, not VLMs: https://arxiv.org/abs/2411.17385 . VLM occlusion: CAPTURe (amodal counting) found models do worse with occlusion https://arxiv.org/abs/2504.15485 (PREPRINT). A 2026 preprint reports depth-ordered occlusion reasoning "collapses to 6-45%" https://arxiv.org/abs/2605.20448 (UNVERIFIED, abstract only).
- **Low-level perception:** "Vision language models are blind" (BlindTest): overlapping circles, line intersections, counting; average ~58% across 4 models, best (Claude 3.5 Sonnet) ~74-75%, figures change across versions. Near 100% when shapes are spaced apart. PREPRINT. https://arxiv.org/abs/2407.06581 . Directly explains the pilot's merged-blob failure: overlap is a known weakness; separate or label.
- **Charts / small text / colour:** ChartQAPro: Claude 3.5 Sonnet falls from 90.5% on ChartQA to 55.81% on the harder set; common error is misreading data values. PREPRINT. https://arxiv.org/abs/2504.05506 . MultiChartQA error analysis: ~9% of failures are colour/legend misreads (37% perceptual, 45% reasoning). PREPRINT. https://arxiv.org/abs/2410.14179 . No study I found isolates "continuous quantity encoded as colour"; the pilot's colour-velocity failure is consistent with this but is one case.
- **Marks and arrows:** Set-of-Mark (numbered marks on segmented regions) makes GPT-4V ground regions better, beating a fine-tuned model on RefCOCOg zero-shot. PREPRINT. https://arxiv.org/abs/2310.11441 . ViP-LLaVA (CVPR 2024, peer-reviewed) shows arrows and boxes drawn on the image are usable prompts, and beat numeric coordinates, but the model was *fine-tuned* for it and arrow-*direction* reading is only a posed question in what I read. https://arxiv.org/abs/2312.00784 . So: id labels = good evidence; velocity arrows = thin evidence beyond our pilot.
- **Multi-frame grids vs single image:** I found no clean benchmark comparing a filmstrip with a single annotated image for a general VLM. Thin. That is exactly the gap the design doc fills (arms B vs C).
- **Image cost:** Anthropic docs: about width*height/750 tokens per image; long edge over 1568 px is downscaled on older models; higher caps on newer ones. https://platform.claude.com/docs/en/build-with-claude/vision

## 3. Visualisation practice for motion
- **Chronophotography (Marey):** several exposures of one subject superposed in a single frame; the shared context shows spatial relations as the object moves, whereas Muybridge's separate frames do not. Korsakov, InfoVis 2009 poster https://ivlab.cs.umn.edu/static/data/pubs/downloads/Korsakov-2009-InfoVisPoster.pdf ; Friendly history of dynamic graphics https://www.datavis.ca/papers/history-dynamic-graphics-2x2.pdf (both non-peer-reviewed posters/slides; thin).
- **Small multiples (Tufte):** repeated panels for comparison; same poster reports small multiples sped analytic tasks with fewer errors (secondary claim). This is arm B.
- **Onion skins:** semi-transparent previous/next frames, from cel animation; today a standard animator tool (vendor docs only, e.g. https://www.adobe.com/uk/creativecloud/animation/discover/onion-skinning). This is the ghost trail in arm C. Evidence that it helps an *LLM* reader: none found.
- **Perceptual ranking (human):** Cleveland & McGill 1984, JASA 79(387): position on a common scale is judged most accurately, then length, direction, angle; area next; shading and colour saturation last. https://doi.org/10.1080/01621459.1984.10478080 (ranking taken from secondary summaries; I did not retrieve the paper). It is about humans; the pilot suggests the same order holds for a VLM (text > arrows > colour), untested.
- Streamlines and motion blur: no source retrieved; not relied on.

## 4. What the evidence supports, plainly
1. Strong: VLMs are weak at depth, speed/direction, occlusion and overlap from raw pixels (WhatsUp, TempCompass, BlindTest, VLM4D).
2. Moderate: explicit marks/ids and metric text help (Set-of-Mark, ViP-LLaVA, SpatialVLM's premise).
3. Thin or absent: whether velocity arrows, ghost trails and outline-for-occluded help a non-fine-tuned frontier LLM; whether a filmstrip beats one annotated frame; whether digest-only beats image. Those are the experiment.
4. Selection risk: benchmarks above use real video and older models; Kine scenes are synthetic and clean, and a new frontier model may already read some of this. Hence the pre-registration in the design doc rather than trust in the literature.
