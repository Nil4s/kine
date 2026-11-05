# CH16 reference: Sony a7 / ILCE-7 class full-frame mirrorless camera

Written 2026-11-05 before running any model number. **SEEN** means the cited page or search-result text was read in this lane; **MEMORY** is an un-refreshed engineering value; **ASSUMED** is a modelling choice, not a Sony measurement. The object is the original 2013 ILCE-7, without IBIS. The A7R teardown is used only where the same-generation construction is explicitly identified as a same-class stand-in.

## Sources read

- [S] Sony, **ILCE-7 Specifications**, `sony.com/electronics/support/e-mount-body-ilce-7-series/ilce-7/specifications` (search-result text; direct page returned HTTP 403). Dimensions, sensor, displays, battery and CIPA stills.
- [SE] Sony Estonia, **ILCE-7 / ILCE-7K Specifications**, `sony.ee/electronics/interchangeable-lens-cameras/ilce-7-body-kit/specifications` (search-result text): metric body and loaded masses.
- [SI] Sony Ireland, **ILCE-7 / ILCE-7K Specifications**, `sony.ie/electronics/interchangeable-lens-cameras/ilce-7-body-kit/specifications` (search-result text): EVF/LCD dot counts and tilt.
- [B] Sony, **NP-FW50 InfoLITHIUM W Series**, `electronics.sony.com/imaging/imaging-accessories/imaging-compact-camera-accessories/p/npfw50` (search-result text; direct page returned HTTP 403): mean output and minimum capacity.
- [BD] Texas Media Systems, **Sony NP-FW50**, `texasmediasystems.com/Sony-NP-FW50-Lithium-Ion-Rechargeable-Battery_p_787.html` (search-result text): package dimensions and mass.
- [F] Brian Smith, **Ultimate Guide to Flange Focal Distance**, `briansmith.com/flange-focal-distance-guide` (read in search results): Sony E mount 18.00 mm.
- [M] PhotoShelter, **An Optical Engineer Explains Lens Flange Distance and Mount Diameter**, `go.photoshelter.com/photographers/blog/an-optical-engineer-explains-lens-flange-distance-and-mount-diameter` (search-result table): E-mount inner diameter 46.1 mm.
- [T] Roger Cicala and Aaron Closz, Lensrentals, **The A7R teardown**, 2014-01-29, `lensrentals.com/blog/2014/01/the-a7r-teardown-a-look-inside-sonys-awesome-full-frame-mirrorless-camera` (full article and its captions read): board/flex layout, sensor/chassis/mount stack, cover glass and screw count.
- [I] iFixit, **Sony a7 Motherboard Replacement**, guide 130457, and **Sony a7 Shutter Replacement / Complete Disassembly**, guide 158234 (search-result steps): rear cover/LCD/main PCB/SD board/grip removal, M1.5 fasteners, separate sensor board and copper plate.

## 1. Published object values (bars 1–3)

| quantity | value used | status and source |
|---|---:|---|
| body envelope, excluding projections | 126.9 x 94.4 x 48.2 mm W/H/D | SEEN [S]; Sony also gives 54.8 mm maximum depth |
| model maximum depth including rear monitor | 54.8 mm | SEEN [S] |
| mass, body only | 416 g | SEEN [SE] |
| mass with battery and memory card | 474 g | SEEN [SE] |
| sensor active size | 35.8 x 23.9 mm | SEEN [S] |
| effective pixels | 24.3 MP, 6000 x 4000 | SEEN [S] |
| sensor plane from mount face | 18.00 mm | SEEN [F]; E-mount definition |
| mount clear throat diameter | 46.1 mm | SEEN [M], third-party optical-engineering table |
| processor | BIONZ X | SEEN [S] |
| EVF | XGA OLED, 2,359,296 dots, 0.71x | SEEN [SI] |
| LCD | 3.0-inch TFT, 921,600 dots; up 90 degrees/down 45 degrees | SEEN [SI] |
| battery type | NP-FW50 | SEEN [S][B] |
| battery mean voltage / minimum charge | 7.2 V / 1020 mAh = 1.020 Ah | SEEN [B] |
| battery nominal energy label | 7.3 Wh, rounded | SEEN [B] |
| hand energy | 7.2 x 1.020 = 7.344 Wh | calculated from SEEN [B] |
| CIPA still life used | 340 shots, LCD | SEEN [S] |
| hand energy per CIPA shot | 7.344 / 340 = 0.0216 Wh = 77.76 J | calculated from SEEN [B][S] |
| NP-FW50 package | 31.8 x 45.0 x 18.5 mm, 42 g | SEEN [BD] |
| sensor cover glass, same-generation A7R | about 1.5 mm | SEEN [T] addendum; **ASSUMED for ILCE-7**, not represented as an a7 measurement |
| A7R major screw count | 29 screws, three sizes | SEEN [T]; **ASSUMED count for this ILCE-7-class model** |
| observed small fasteners | M1.5 x 2, M1.5 x 4, M1.5 x 5 mm examples | SEEN [I]; model uses one M1.5 x 4 mm envelope for all 29, **ASSUMED simplification** |

No IBIS mass or mechanism is included: the brief identifies that as a7 II equipment.

## 2. Mechanical layout and stack (bars 1, 2, 4)

Coordinate system: millimetres in Part records, X right, Y up, Z toward the lens; rear is negative Z. Mount datum face Z = 0 and sensor front plane Z = -18.00 are **ASSUMED modelling datums** implementing SEEN [F]. The shell occupies X = -63.45…63.45, Y = 0…94.4 and Z = -48.2…0; the tilted-monitor projection reaches Z = -54.8. These derive directly from SEEN [S].

The internal order follows [T]: mount on one side of a metal chassis; sensor shimmed to the other side, not to the shutter; shutter in front of the sensor; LCD and large main PCB at the rear; short flexes; SD board near the grip; top assembly and EVF above. **SEEN layout, ASSUMED dimensions.** The block stack, front to rear, is:

| item | model dimensions / placement | status |
|---|---|---|
| mount ring | 56.0 mm OD, 46.1 mm clear ID, 3.0 mm axial ring; face Z=0 | ID SEEN [M]; OD/thickness ASSUMED |
| shutter frame | 48 x 34 x 1.2 mm with 38 x 26 mm opening; Z=-23.5…-22.3 | ASSUMED block envelope |
| two shutter curtains | 37.0 x 25.0 x 0.12 mm each, separate Z layers behind frame | ASSUMED block leaves, larger than SEEN sensor |
| cover glass | 38.0 x 26.0 x 1.5 mm; Z=-21.5…-20.0 | thickness SEEN A7R [T] / ASSUMED a7; plan size ASSUMED |
| sensor die | 35.8 x 23.9 x 0.35 mm; front plane Z=-18.0 | active size SEEN [S]; thickness ASSUMED; a 1.65 mm carrier gap behind glass is ASSUMED |
| sensor carrier | 46 x 34 x 1.0 mm ring with 37 x 25 mm opening, immediately behind die | ASSUMED |
| sensor flex | 18 x 12 x 0.18 mm routed block to the main PCB region | ASSUMED; flex route exists in [T] |
| main PCB | 78 x 58 x 1.2 mm, Z=-31.2…-30.0 | ASSUMED envelope, rear-board position SEEN [T][I] |
| battery cavity | battery at right/grip, separate from board and sensor | position SEEN [I], exact coordinates ASSUMED |
| EVF module | 28 x 22 x 30 mm inside the top hump | ASSUMED block; hump is filled by EVF in [T] |
| LCD module | 76 x 54 x 4.0 mm plus separate hinge | 3.0-inch class SEEN [SI]; envelope ASSUMED |
| SD card | 24 x 32 x 2.1 mm | MEMORY standard SD full-size envelope; slot/card location SEEN [T][I] |
| USB/HDMI block | 18 x 22 x 8 mm on left side | ASSUMED; side input connectors visible in [T] |
| Wi-Fi/NFC antenna | 24 x 12 x 0.4 mm at left shell | ASSUMED dimensions; [T] blue coax/PCB antenna discussion supports separate antenna |

The full-frame cone check is deliberately geometric and independent of any lens claim: the sensor corner radius is `sqrt(35.8^2 + 23.9^2)/2 = 21.63529 mm`; the throat radius is `46.1/2 = 23.05 mm`. Linear interpolation from the sensor corners to the mount opening therefore clears at every Z. The 18.00 mm check is `0 - (-18.00)` exactly, not a tessellation measurement.

### Shells, supports and fasteners

Front and rear shells, top and bottom plates and grip are separate thin-wall Part records with apertures cut for mount, EVF, LCD, battery and screws. Wall values of 1.2 mm (shells), 1.5 mm (chassis), 0.8 mm (small brackets), 0.1 mm assembly-contact tolerance and 0.001 mm3 fit-volume threshold are **ASSUMED**. The threshold is a numerical contact allowance, not permission to bury a PCB in a shell. Declared `hang` links represent hidden screw/bracket attachments for stage support; no press-fit overlap is declared.

All 29 fastener cylinders are individual Assembly parts so AssemblyBom counts and prices them. Their 0.75 mm shaft radius is SEEN M1.5 [I] / 2 by hand; 4.0 mm length is SEEN as one observed length [I] but **ASSUMED for every fastener**. Hole radius 0.90 mm and placement are **ASSUMED**.

## 3. Materials, masses and bought prices (bar 1 and BOM)

Mass is summed by AssemblyBom from exact solid volume x density x fill. No total-mass correction line is used. Battery and SD masses come from their CAD solids using the densities below, so the cited 42 g battery and loaded 474 g are comparisons, not hidden overrides.

| material / item | density or price | status |
|---|---:|---|
| magnesium alloy chassis | 1740 kg/m3 | MEMORY AZ91-class |
| aluminium mount / heat spreader | 2700 kg/m3 | MEMORY 6061 class; price already in `data/prices.json` |
| engineering-plastic shells | 1200 kg/m3 | MEMORY PC/ABS class |
| steel mount fasteners / shutter | 7850 kg/m3 | MEMORY; price already in price table |
| FR4 PCB | 1850 kg/m3 | MEMORY populated-board-equivalent bulk value |
| silicon sensor / IC blocks | 2330 kg/m3 | MEMORY silicon |
| optical glass | 2500 kg/m3 | MEMORY glass class |
| copper flex / heat spreader | 8960 kg/m3 | MEMORY copper |
| LCD/EVF module equivalent | 900 kg/m3 | ASSUMED equivalent including glass, frame and air |
| battery equivalent | 1856.48 kg/m3 | ASSUMED density chosen so the SEEN 31.8 x 45.0 x 18.5 mm [BD] solid is about 42 g |
| SD card plastic equivalent | 950 kg/m3 | ASSUMED |
| M1.5 x 4 camera screw | USD 0.02 each | ASSUMED small-pack replacement-hardware price, 2026-11-05 |
| replacement NP-FW50 | USD 94.99 | SEEN current Sony store result [B], used as bought-price alternative view |
| replacement SD card | USD 8.00 | ASSUMED 2026-11-05 small-card retail |
| bought module allowances (main PCB, sensor, shutter, EVF, LCD, controls, ports, antenna) | individual prices in `data/prices.json` | all ASSUMED 2026-11-05 estimates, not Sony service quotations |
| generic shell material cheaper alternative | ABS USD 19/kg vs engineering plastic USD 24/kg | ASSUMED 2026-11-05; ABS density already SEEN in repo price table |

The cheaper view changes only declared material/bought-item alternatives. It is a costing exercise, not a claim that an arbitrary replacement module is electrically or mechanically interchangeable.

## 4. Electrical estimates (bar 3)

Sony does not publish rail voltages or rail loads in the cited consumer specification. The following are **ASSUMED same-class engineering estimates**, explicitly not a7 measurements. Battery and CIPA values above are SEEN.

| rail / regulator | voltage | estimated maximum load | destination |
|---|---:|---:|---|
| protection / ideal-diode input | 7.2 V nominal | 8.0 W input budget | battery to PMIC |
| buck core | 1.1 V | 1.10 W | BIONZ X core |
| buck sensor | 1.8 V | 0.85 W | sensor analogue/digital |
| buck I/O | 3.3 V | 1.20 W total | DRAM, SD, USB, HDMI, Wi-Fi/NFC |
| boost display | 5.0 V | 0.65 W total | EVF and LCD |
| direct motor rail | 7.2 V | 0.80 W | shutter driver |
| **sum of named rail loads** | — | **4.60 W** | hand sum 1.10+0.85+1.20+0.65+0.80 |
| regulator input at assumed 90% efficiency | — | **5.11111 W** | hand 4.60/0.90; efficiency ASSUMED |
| input protection/regulator budget | — | **8.00 W** | ASSUMED, above computed input |
| CIPA-equivalent active interval | — | **12.0 s/shot** | ASSUMED duty cycle; 5.11111 x 12 = 61.3333 J < 77.76 J |

Signal model: sensor MIPI/LVDS image data to BIONZ X; BIONZ X to DRAM, SD, EVF, LCD and HDMI; USB and Wi-Fi/NFC bidirectional to BIONZ X; BIONZ X control to shutter driver and sensor; protection/PMIC power to every IC. Each IC has at least one named power edge and one named signal edge. Removing a regulator in the planted control leaves its loads unsupplied and fails the budget/connectivity check; it is never silently removed from the load sum.

## 5. Drawing, render and cost conventions

A3 blueprint scale 1:2 and paper-space text sizes follow the CH15 drawing helpers: **ASSUMED presentation values**. The front/top/section geometry uses the model constants above, with explicit 126.9, 94.4, 48.2, 54.8, 18.00, 35.8 and 23.9 mm callouts. The electronics sheet is NTS. Six build stages, 1.0 s each at 2 fps, a 40 mm drop-in and 640 x 360 render frames are **ASSUMED animation/presentation values**. Section plane Z=-26 mm is **ASSUMED** between the sensor/shutter and the rear main PCB so the cut exposes the internal stack.
