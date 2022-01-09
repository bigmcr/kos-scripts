@LAZYGLOBAL OFF.
PARAMETER waitPermission IS TRUE.

CLEARSCREEN.

RUNPATH("1:waitForTarget", 1.0).

LOCAL inclinationModifier IS 1.
IF distanceToTargetOrbitalPlane() < 0 SET inclinationModifier TO -1.

PRINT "inclinationModifier set to " + inclinationModifier.

LOCAL targetInclination IS TARGET:ORBIT:INCLINATION * inclinationModifier.
LOCAL finalAltitude IS 30000.
IF SHIP:BODY:ATM:EXISTS SET finalAltitude TO SHIP:BODY:ATM:HEIGHT + 5000.
RUNPATH("1:gravturnlaunch", targetInclination, TRUE, 10, finalAltitude).

// CLEARSCREEN.
// PRINT "Now using the remaining fuel in the launch stage, and aiming prograde.".

// SET myThrottle TO 1.
// SET useMyThrottle TO TRUE.

// SET useMySteer TO TRUE.
// LOCAL done IS FALSE.
// UNTIL done {
	// SET mySteer TO SHIP:VELOCITY:ORBIT.
	// IF MAXTHRUST = 0 SET done TO TRUE.
// }

// SET myThrottle TO 0.
// SET useMyThrottle TO FALSE.

// endScript().

// stageFunction().
