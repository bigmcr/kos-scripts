@LAZYGLOBAL OFF.
PARAMETER targetName IS "".
PARAMETER waitPermission IS TRUE.
PARAMETER invertInclination IS FALSE.

CLEARSCREEN.

LOCAL possibleVessels IS "".
LIST TARGETS IN possibleVessels.
FOR eachTarget IN possibleVessels {
  IF eachTarget:NAME = targetName {
    SET TARGET TO eachTarget.
    BREAK.
  }
}

IF waitPermission RUNPATH("waitForTarget", 1.0).

IF NOT HASTARGET {
    CLEARSCREEN.
    PRINT "Select a target.".
    UNTIL HASTARGET {WAIT 0.}
}

LOCAL inclinationModifier IS 1.
IF distanceToTargetOrbitalPlane() < 0 SET inclinationModifier TO -1.
IF invertInclination SET inclinationModifier TO -1 * inclinationModifier.

LOCAL targetInclination IS TARGET:ORBIT:INCLINATION * inclinationModifier.
LOCAL finalAltitude IS 30000.
IF SHIP:BODY:ATM:EXISTS SET finalAltitude TO SHIP:BODY:ATM:HEIGHT + 5000.
RUNPATH("gravturnlaunch", targetInclination, TRUE, 10, finalAltitude).

// CLEARSCREEN.
// PRINT "Now using the remaining fuel in the launch stage, and aiming prograde.".

// SET globalThrottle TO 1.
// setLockedThrottle(TRUE).

// setLockedSteering(TRUE).
// LOCAL done IS FALSE.
// UNTIL done {
	// SET globalSteer TO SHIP:VELOCITY:ORBIT.
	// IF MAXTHRUST = 0 SET done TO TRUE.
// }

// SET globalThrottle TO 0.
// setLockedThrottle(FALSE).

// stageFunction().
