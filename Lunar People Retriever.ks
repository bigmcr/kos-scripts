CLEARSCREEN.

// Set the generic variables from the library
SET physicsWarpPerm TO 3.
SET debug TO FALSE.

RUNONCEPATH(waitForMoon.ks, 2).

RUNONCEPATH(GravTurnLaunch.ks, FALSE, 10, 150000, -TARGET:ORBIT:INCLINATION).

CLEARSCREEN.
PRINT "In orbit!".
