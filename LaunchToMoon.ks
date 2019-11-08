@LAZYGLOBAL OFF.

CLEARSCREEN.

PRINT "Select Target".

UNTIL HASTARGET WAIT 0.

// waitForTarget returns 1 or -1 depending on if we are approaching the ascending node or the descending node of the target.
LOCAL inclinationModifier IS waitForTarget(0.25).

LOCAL targetInclination IS TARGET:ORBIT:INCLINATION * inclinationModifier.
LOCAL finalAltitude IS 20000.
IF SHIP:BODY:ATM:EXISTS {
	SET finalAltitude TO SHIP:BODY:ATM:HEIGHT - 10000.
}
RUNPATH("1:gravturnlaunch", targetInclination, TRUE, 15, finalAltitude).

SET myThrottle TO 0.
WAIT 0.
endScript().

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
