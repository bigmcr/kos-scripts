CLEARSCREEN.

// Set the generic variables from the library
SET physicsWarpPerm TO 2.
SET debug TO TRUE.

RUNONCEPATH(waitForMoon.ks, -2).

RUNONCEPATH(GravTurnLaunch.ks, TRUE, 10, 150000, -TARGET:ORBIT:INCLINATION).

CLEARSCREEN.
PRINT "In orbit!".
