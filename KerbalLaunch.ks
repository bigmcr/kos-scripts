PARAMETER finalInclination IS 0.					// The initial heading to launch at
PARAMETER altitudeTarget IS 20000.			// The desired final altitude
PARAMETER maxGs IS 1.5.
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the stage function to start with

// If the body has an atmosphere and altitudeTarget is the default, set the
//   altitude target to 5km below the top of the atmosphere.
IF SHIP:BODY:ATM:EXISTS AND altitudeTarget = 20000 SET altitudeTarget TO SHIP:BODY:ATM:HEIGHT - 5000.

RUNPATH("GravTurnLaunch", finalInclination, FALSE, 10, altitudeTarget, initialStage, maxGs).
RUNPATH("Circ", "apo").
RUNPATH("Exec").
REMOVE NEXTNODE.

SET loopMessage TO "ship in " + distanceToString(APOAPSIS) + "x" + distanceToString(PERIAPSIS) + " orbit " + ROUND(ABS(SHIP:ORBIT:INCLINATION - finalInclination), 1) + " deg inc error".
