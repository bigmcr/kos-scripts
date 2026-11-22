@LAZYGLOBAL OFF.

// ExecRCS.ks - executes the next maneuver node with the RCS thrusters, firing forward, instead of the main engines.
// It is Exec (Exec.ks) run in its RCS mode (the parameter useRCSforThrust): the plan is made from the thrusters that fire forward and
// the RCS propellant, the RCS is on for the whole run (so the ship turns with it as well), there is no staging and no ullage, and the
// rest is as for Exec: the burn solver, the alignment and warps, the abort key (End), the node checks and the logs (Maneuver.csv
// says "RCS" in its "thrust source" line).
// Passed the following (both optional, as for Exec):
//			face the Sun while waiting (boolean)
//			suppress printing (boolean)
PARAMETER faceSun IS FALSE.
PARAMETER suppressPrinting IS FALSE.

// Exec's parameters are: ullage (0, there is none), use RCS for rotation (TRUE), face the Sun, suppress printing, use RCS for thrust (TRUE)
RUNPATH("Exec", 0, TRUE, faceSun, suppressPrinting, TRUE).
