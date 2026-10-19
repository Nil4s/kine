# Line of action: what the animation books say, and what Kine builds

For docs/ROADMAP.md item 23 (top-25 #9). Code: `scripts/line_of_action.gd`; test: `tests/line_of_action_test.gd`.

## Sources

- **Preston Blair, *Cartoon Animation*** (revised edition). Has a "Line of Action" section in the basic character
  movement chapter (Chapter 4 in the publisher's listing), next to its sections on rhythm and design. Listing:
  https://quarto.com/books/9781633227736/X.html (read 2026-10-18, the contents only, not the text).
- **Preston Blair, *Cartoon Animation 1*** (Walter Foster, shorter book). Its contents include a "Line of Action"
  section, next to "The Stretch & Squash Principle". Listing: https://quarto.com/books/9781633227736/cartooning-animation-1-with-preston-blair
- **Richard Williams, *The Animator's Survival Kit*** (2001). Named in the brief as the other source for the line of
  action. NOT checked: the search turned up no text on its line-of-action discussion, so nothing here is quoted from it.
- The principle is not one of the twelve in Thomas and Johnston, *The Illusion of Life*. A handout listing those
  principles: https://icg.gwu.edu/sites/g/files/zaxdzs6126/files/downloads/12principles_2.pdf

## The idea, as Kine uses it

One curve through the body's gesture: head, spine, pelvis, and the planted leg. The pose follows the curve; a C or an
S shows at a glance whether the gesture has a clear shape. Kine does two things with it:

1. **Overlay** (View toggle "Line of action", POSE tab): the current curve head centre -> neck -> spine -> pelvis ->
   support knee -> ankle, drawn faint.
2. **Sketch** ("Pose: draw a line of action"): one drag on the view is a stroke, cast onto the plane through the
   pelvis that faces the camera, smoothed and resampled, and moved to pass through the pelvis. The pelvis tilt, the
   spine, neck, head and the support thigh and knee are fitted so their joint points lie on the curve. Limits are the
   body's own; the planted ankle is held. Arms are not touched.

## What the fit can and cannot do (measured, not promised)

- A 10 cm C bow from the planted ankle through the pelvis to the head: spine, neck and head within 1.4-11 mm of the
  curve; spine_01 reached its side limit at 11 mm.
- The support knee stays about 9 cm off the curve in that test: the support leg is straight and its knee's lower limit
  is straight, so the hip cannot move away from the ankle. Reported as a limit, not hidden.
- Where a straight planted leg blocks the hip tilt, the planted ankle is put back by moving the whole body the few mm
  it drifted (the pelvis then sits a few mm off the curve).
