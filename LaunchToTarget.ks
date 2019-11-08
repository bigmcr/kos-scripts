@LAZYGLOBAL OFF.
PARAMETER waitPermission IS TRUE.

CLEARSCREEN.

PRINT "Select a target".

UNTIL HASTARGET { WAIT 0.}

LOCAL inclinationModifier IS 1.
// waitForTarget returns 1 or -1 depending on if we are approaching the ascending node or the descending node of the target.
IF NOT SHIP:BODY:NAME = "Moon" {
	IF waitPermission SET inclinationModifier TO waitForTarget(0.25).
}

LOCAL targetInclination IS TARGET:ORBIT:INCLINATION * inclinationModifier.
LOCAL finalAltitude IS 30000.
IF SHIP:BODY:ATM:EXISTS {
	SET finalAltitude TO SHIP:BODY:ATM:HEIGHT - 10000.
	RUNPATH("1:gravturnlaunch", targetInclination, TRUE, 10, finalAltitude).
} ELSE {
//	RUNPATH("1:VacLaunch", targetInclination, TRUE, 10, finalAltitude).
	RUNPATH("1:gravturnlaunch", targetInclination, TRUE, 10, finalAltitude).
}

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
