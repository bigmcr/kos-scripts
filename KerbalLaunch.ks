PARAMETER finalInclination IS 0.					// The initial heading to launch at
PARAMETER altitudeTarget IS 30000.			// The desired final altitude
PARAMETER maxGs IS 3.
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the stage function to start with

// If the body has an atmosphere and altitudeTarget is the default, set the
//   altitude target to 5km below the top of the atmosphere.
IF SHIP:BODY:ATM:EXISTS AND altitudeTarget = 30000 SET altitudeTarget TO SHIP:BODY:ATM:HEIGHT - 5000.

setLockedThrottle(FALSE).
setLockedSteering(FALSE).

RUNPATH("GravTurnLaunch", finalInclination, altitudeTarget, initialStage, maxGs).
endScript().
RUNPATH("Circ", "apo").
RUNPATH("Exec").
REMOVE NEXTNODE.

SET finalInclination TO ABS(finalInclination).
SET loopMessage TO distanceToString(APOAPSIS) + "x" + distanceToString(PERIAPSIS) + " orbit " + ROUND(ABS(SHIP:ORBIT:INCLINATION - finalInclination), 1) + " deg inc error".
