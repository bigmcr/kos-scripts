CLEARSCREEN.
PARAMETER bodySet IS "Moon".
PARAMETER offset IS 2.
SET TARGET TO BODY(bodySet).
PRINT SHIP:NAME + " will wait and launch to a rendezvous.".
IF (offset = 1) PRINT SHIP:NAME + " will allow 1 degree of longitude to get into orbit.".
ELSE PRINT SHIP:NAME + " will allow " + ROUND(offset, 2) + " degrees of longitude to get into orbit.".
PRINT "Waiting until " + TARGET:NAME + " is in the appropriate position.".

// allow the specified degrees of longitude for the rocket to get into orbit
PRINT timeToString(timeToLongitude(TARGET:ORBIT:LAN - SHIP:BODY:ROTATIONANGLE + offset) - TIME:SECONDS) + " until launch".
warpToTime(timeToLongitude(TARGET:ORBIT:LAN - SHIP:BODY:ROTATIONANGLE + offset)).

SET loopMessage TO "Inclination is " + TARGET:ORBIT:INCLINATION.
