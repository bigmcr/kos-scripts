PARAMETER finalInclination IS 0.					// The initial heading to launch at
PARAMETER altitudeTarget IS 20000.			// The desired final altitude
PARAMETER maxGs IS 1.5.
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the stage function to start with

IF SHIP:BODY:ATM:EXISTS {
	SET altitudeTarget TO SHIP:BODY:ATM:HEIGHT - 5000.
}

IF VELOCITY:SURFACE:MAG > 1.0 SET loopMessage TO "Already moving over the surface!".
ELSE {
	RUNPATH("GravTurnLaunch", finalInclination, FALSE, 10, altitudeTarget, initialStage, maxGs).
	RUNPATH("Circ", "apo").
	RUNPATH("Exec").
}
