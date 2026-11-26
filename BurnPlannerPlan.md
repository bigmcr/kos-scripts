# Multi-pass burn planner (multiPassBurn.ks): design notes

These notes explain why the script works the way it does. How to run it is in the script's header comment and README.md. Nothing reads this file.

## Purpose
A burn that is a large part of an orbit, held at a fixed direction, pushes the ship down toward the body early in the burn (an ejection from an
80 km Kerbin orbit with a weak engine hit the atmosphere). The same delta V split into several burns, one per orbit, each short enough, does
not. The script takes the last maneuver node as the target (its place, time and the velocity after it) and replaces it with a chain of nodes
that ends in the same place, at the same time, with the same velocity. Exec only has a guard (below).

## Geometry
Every pass is centered on the same point P (the node's position), in the same fixed direction u (the unit vector of the total delta V, which
is also the direction Exec holds). After k passes the state is (P, v0 + S_k u), exactly, for any direction of u, because the ship is back at P
after one period of whatever orbit it is then on. The period of each intermediate orbit comes from vis-viva. For a prograde burn P is the
periapsis of the intermediate orbits; with a normal or radial part it is not, so the periapsis of every intermediate orbit is checked.

## Timing
The final time T_f is fixed, so the passes are timed backward from it: t_k = t_(k+1) - T_k, which makes the first pass t_1 = T_f - (sum of the
intermediate periods). That sum grows with the delta V spent, and the first pass must also be at a pass of P on the current orbit (t_1 =
first pass + j x the current period). With the pieces equal except the last (which takes the rest), the sum is monotone in the piece size, so
a bisection finds the size for each count and each j. A "phased" family has a small first piece (a fraction of the largest safe piece, at
least three passes) that widens the choices without extra delta V. A phasing burn anywhere else would not pass through P again, so it is not used.
The search starts at the fewest passes the largest safe piece allows and tries a few more. Choices are ranked by time in the shadow, then
span, then number of passes.

## Checks
- A quick integration gives each piece's lowest altitude during the search; the chosen plan is then simulated with the burn solver's
  simulation (the same stages), and the lowest altitude must stay above the limit.
- Every intermediate orbit: periapsis above the limit, no escape from the sphere of influence.
- The nodes are added and the game's predicted patches are scanned: an orbit before the last node must end at a node, not at an encounter
  or an escape. The game's limit of conic patches can hide the later passes; the script says so.
- Any failure drops the plan, and the flight plan is put back as it was.
- Shadow: all passes are at P, so they are in the shadow together; nothing can move it, and the plan only prefers shorter burns in it.

## Replanning
Every accepted plan is saved to 1:multiPassBurn.json, because the last node in the flight plan moves with the error of the passes that were flown. The saved
target is what a replan uses. The script replans by itself when a valid saved plan goes with the flight plan (see the header comment),
and it only re-solves the passes that are left, from the ship's real orbit, so the error of the last pass is absorbed:
- it counts the saved passes that are still ahead (M) and solves equal pieces (the last takes the rest) for M passes from the next pass of
  P, trying M+1 to M+4 if the sizes do not fit;
- with one pass left it is the whole remainder at the next pass, if that is safe and within 30 s of the final time;
- the place must lie on the ship's orbit (within 0.02 of the orbit plane), which also catches a plan saved in another frame or for another burn.
Exec deletes the file after the plan's last pass (finishMultiPassPlan in library.ks).

## Exec guard
The solver's simulated burn records its lowest altitude (also logged to Maneuver.csv). If the burn is predicted to go into the atmosphere
or the surface, Exec does not start it: it stops before the ignition as the abort key does, and says why. This is a check of the plan made
before ignition, not an abort of a burn under way, and it does not apply when the ship's orbit already goes that low before the node. It
only runs when the solver runs (burns of 30 s or more with enough lead time).

## Limits and open questions
- Passes must precede the final time by the sum of the intermediate periods, so a node that is too near has no multi-pass plan.
  Delaying the whole thing by whole orbits is not offered (not safe for an interplanetary window).
- The final pass of a replan may be up to 30 s off the final time.
- The saved positions assume the kOS inertial frame stays fixed between sessions; the orbit-plane check is the guard.
- The default longest span is 128 periods of a circular orbit at the node's distance (from the body's MU), or 6 periods of the ship's own
  orbit if that is longer.
- Not done: a replan inside the LoopCommands terminal, a throttle cap for very small burns.
