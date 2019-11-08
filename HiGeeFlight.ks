SET useMySteer TO TRUE.
SET useMyThrottle TO TRUE.

LOCK mySteer TO SHIP:UP.
LOCAL startTime IS TIME:SECONDS.

CLEARSCREEN.

// start the engines
PRINT "Starting engines!".
SET myThrottle TO 1.
stageFunction().
WAIT 4.
PRINT "Starting engines!".
SET myThrottle TO 0.
WHEN (VERTICALSPEED < 0) THEN {stageFunction(). PRINT "Deploying parachutes".}

UNTIL ALT:RADAR < 10 {
	PRINT "Vertical Speed: " + ROUND(VERTICALSPEED, 2) + "        " AT(0, 3).
}
PRINT "Script Done.".