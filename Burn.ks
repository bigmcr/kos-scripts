@LAZYGLOBAL OFF.

PARAMETER burnTime.
PARAMETER throt IS 1.

endScript().
SET mySteer TO SHIP:FACING.
SET useMySteer TO TRUE.
SET useMyThrottle TO TRUE.
SET myThrottle TO throt.
CLEARSCREEN.
LOCAL startTime IS MISSIONTIME.
UNTIL MISSIONTIME - startTime >= burnTime {
	PRINT "There are " + timeToString(burnTime - (MISSIONTIME - startTime), 2) + " left in the burn     " AT (0,0).
	WAIT 0.
}
endScript().

SET SHIP:CONTROL:MAINTHROTTLE TO 0.
