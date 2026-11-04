# CH2 reference: a seconds-beating regulator (longcase) movement

What was checked online and what was not (said plainly):

| Fact | Value used | Source |
|---|---|---|
| Seconds pendulum, one beat per second, period 2 s | length to the centre of oscillation 0.9936 m (g = 9.80665: L = g / pi^2); built at **994 mm** | standard pendulum physics T = 2 pi sqrt(L/g); Firgelli "Escapement Mechanism Explained" (firgelliauto.com/blogs/mechanisms/escapement) quotes about 994 mm |
| Escape wheel of a seconds-pendulum clock | **30 teeth**, one revolution per minute, each tooth gives two beats (tick, tock) | hobby-machinist forum post on a 1-second pendulum clock with a 30-tooth wheel (hobby-machinist.com/goto/post?id=365073); Timex 61 manual p.9 (two beats per escape tooth) |
| Going-train rule: wheel teeth / pinion leaves multiply along the train | ratio = product of (wheel / pinion) | Firgelli "Going Train Mechanism Explained" (firgelliauto.com/es/blogs/mechanisms/going-train; its worked example uses an 80-tooth centre wheel with an 8-leaf pinion, a different train from ours) |
| Motion work (minute hand to hour hand) is 12:1 | **12/36 x 10/40 = 1/12** (cannon pinion 12 to minute wheel 36, minute-wheel pinion 10 to hour wheel 40) | textbook arrangement; the tooth counts are the common ones, not copied from one named clock |

**Not found:** a published tooth list for one named museum regulator. The train below is a REPRESENTATIVE train that satisfies the published invariants
(escape wheel 1 rev/min, centre wheel 1 rev/hour, 30-tooth escape wheel, 994 mm pendulum). It is not a copy of a specific clock, and this document
does not claim it is.

## Tooth counts used (every wheel and pinion)

| Part | Teeth / leaves | Module (mm) | Turns per hour |
|---|---|---|---|
| Centre wheel C64 (carries the minute hand) | 64 | 1.00 | 1 |
| Third pinion T8 (on the third arbor) | 8 | 1.00 | 8 |
| Third wheel T60 (same arbor) | 60 | 1.00 | 8 |
| Escape pinion E8 (on the escape arbor) | 8 | 1.00 | 60 |
| Escape wheel (carries the seconds hand) | 30 | tip R 40 mm | 60 |
| Cannon pinion CAN12 (on the centre arbor) | 12 | 1.00 | 1 |
| Minute wheel M36 | 36 | 1.00 | 1/3 |
| Minute-wheel pinion M10 | 10 | 0.96 | 1/3 |
| Hour wheel H40 (hollow arbor, hour hand) | 40 | 0.96 | 1/12 |

Check: C64/T8 x T60/E8 = 8 x 7.5 = 60, so the escape wheel (seconds hand) goes 60 times round while the minute hand goes once. Motion work 12/36 x 10/40 = 1/12.
Centre distances: C-T 36 mm, T-E 34 mm, cannon-minute wheel 24 mm, minute pinion-hour wheel 0.96 x 50 / 2 = 24 mm (the second pair is cut at module 0.96 so both
pairs close on the same minute-wheel arbor).

Turns per hour, seconds : minute : hour = 60 : 1 : 1/12 = **720 : 12 : 1**. The task text said 3600:60:1; that is the ratio of the angular
SPEEDS of a seconds hand to a minute hand to an hour hand only if the hour hand took 60 hours per turn. A 12-hour hand gives 60:1 (seconds to minute) and 12:1
(minute to hour); the test bars use these (and print 720:12:1).

## Escapement and pendulum

Deadbeat-style: an anchor with two pallet blades spans 7.5 teeth (90 degrees) of the 30-tooth wheel, pivot at R x sqrt(2) = 56.6 mm from the wheel centre.
The pendulum swings 2.5 degrees each side, integrated with RK4 from theta'' = -(g/L) sin(theta).
