CLEARSCREEN.
PRINT "Now logging resources".

LOCAL startTime IS TIME:SECONDS.

SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
SET KUNIVERSE:TIMEWARP:RATE TO 10000.

UNTIL KUNIVERSE:TIMEWARP:ISSETTLED WAIT 0.

createResourcesHeader().

AG1 OFF.
UNTIL(AG1 OR (TIME:SECONDS > startTime + 60*60*24)) {
	updateShipInfoResources(TRUE).
	WAIT 0.
}

SET KUNIVERSE:TIMEWARP:RATE TO 1.

SET loopMessage TO "Resources logged".