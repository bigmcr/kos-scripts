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
	PRINT "Time remaining in burn:" AT (0,0).
	PRINT timeToString(burnTime - (MISSIONTIME - startTime), 2):PADLEFT(23) + "     " AT (0, 1). 
	WAIT 0.
}
endScript().

SET SHIP:CONTROL:MAINTHROTTLE TO 0.
