@LAZYGLOBAL OFF.
CLEARSCREEN.
RCS ON. 
LOCK mySteer TO -VELOCITY:SURFACE.

LOCAL myVariable TO LIST().
LIST ENGINES IN myVariable.
LOCAL thrust is myVariable[0]:MAXTHRUST*1000.
LOCAL ISP is myVariable[0]:VACUUMISP.
LOCAL t IS 1.
LOCAL MMHUse IS 6.5787.
LOCAL NTOUse IS 10.8262.
LOCAL MMHAmount IS 0.
LOCAL NTOAmount IS 0.

SET t TO 1.
LOCAL resList IS STAGE:RESOURCES.
FOR res IN resList {
	IF RES:NAME = "MMH" { SET MMHAmount TO RES:AMOUNT.}
	IF RES:NAME = "NTO" { SET NTOAmount TO RES:AMOUNT.}
}
SET t TO MIN (MMHAmount / MMHUse, NTOAmount / NTOUse).
LOCAL g IS SHIP:BODY:MU / ((ALTITUDE + SHIP:BODY:RADIUS)^2).
LOCAL v0 IS SHIP:VELOCITY:SURFACE:MAG.
LOCAL m0 IS SHIP:MASS*1000.
LOCAL equation IS ALT:RADAR + 10.
LOCAL a IS 1.
LOCAL H is 1.
LOG "MET,v0,a,t,H,g,Altitude,Time Estimate" TO "SuicideBurnSimple1.csv".

SET a TO thrust/(SHIP:MASS*1000) - g.
SET t TO v0/a.
SET H TO 0.5 * v0 ^ 2 / a.

UNTIL ALTITUDE <= H + 7 * VELOCITY:SURFACE:MAG {
	SET g TO SHIP:BODY:MU / ((ALTITUDE + SHIP:BODY:RADIUS)^2).
	SET v0 TO SHIP:VELOCITY:SURFACE:MAG.
	SET a TO thrust/(SHIP:MASS*1000) - g.
	SET t TO v0 / a.
	SET H TO 0.5 * v0 ^ 2 / a.
	PRINT "v0 is " + ROUND(v0, 4) + "      " AT (0, 5).
	PRINT "a is " + ROUND(a, 4) + "      " AT (0, 6).
	PRINT "t is " + ROUND(t, 4) + "      " AT (0, 7).
	PRINT "H is " + ROUND(H, 4) + "      " AT (0, 8).
	PRINT "g is " + ROUND(g, 4) + "      " AT (0, 9).
	PRINT "Time Estimate " + ROUND((ALTITUDE - 7 * VELOCITY:SURFACE:MAG - H)/VELOCITY:SURFACE:MAG, 2) + "      " AT (0, 10).
	LOG MISSIONTIME + "," + v0 + "," + a + "," + t + "," + H + "," + g + "," + Altitude + "," + (ALTITUDE - 7 * VELOCITY:SURFACE:MAG - H)/VELOCITY:SURFACE:MAG TO "SuicideBurnSimple1.csv".
	WAIT 0.
}

// use RCS to settle any ullage concerns.
SET SHIP:CONTROL:FORE TO 1.0.
PRINT "Ullage starting".
WAIT 7.
SET SHIP:CONTROL:FORE TO 0.0.

UNTIL VELOCITY:SURFACE:MAG < 10 {
	LOCK THROTTLE TO 1.
}

LOCK THROTTLE TO 0.

WAIT 5.

SET g TO SHIP:BODY:MU / ((ALT:RADAR + SHIP:BODY:RADIUS)^2).
SET v0 TO SHIP:VELOCITY:SURFACE:MAG.
SET a TO thrust/(SHIP:MASS*1000) - g.
SET t TO v0 / a.
SET H TO 0.5 * v0 ^ 2 / a.
LOG "MET,v0,a,t,H,g,ALT:RADAR" TO "SuicideBurnSimple2.csv".

UNTIL ALT:RADAR <= H + 7 * VELOCITY:SURFACE:MAG {
	SET g TO SHIP:BODY:MU / ((ALT:RADAR + SHIP:BODY:RADIUS)^2).
	SET v0 TO SHIP:VELOCITY:SURFACE:MAG.
	SET a TO thrust/(SHIP:MASS*1000) - g.
	SET t TO v0 / a.
	SET H TO 0.5 * v0 ^ 2 / a.
	PRINT "v0 is " + ROUND(v0, 4) + "      " AT (0, 5).
	PRINT "a is " + ROUND(a, 4) + "      " AT (0, 6).
	PRINT "t is " + ROUND(t, 4) + "      " AT (0, 7).
	PRINT "H is " + ROUND(H, 4) + "      " AT (0, 8).
	PRINT "g is " + ROUND(g, 4) + "      " AT (0, 9).
	PRINT "Time Estimate " + ROUND((ALTITUDE - 7 * VELOCITY:SURFACE:MAG - H)/VELOCITY:SURFACE:MAG, 2) + "      " AT (0, 10).
	LOG MISSIONTIME + "," + v0 + "," + a + "," + t + "," + H + "," + g + "," + Altitude + "," + (ALTITUDE - 7 * VELOCITY:SURFACE:MAG - H)/VELOCITY:SURFACE:MAG TO "SuicideBurnSimple2.csv".
	WAIT 0.
}

// use RCS to settle any ullage concerns.
SET SHIP:CONTROL:FORE TO 1.0.
PRINT "Ullage starting".
WAIT 7.
SET SHIP:CONTROL:FORE TO 0.0.

UNTIL VELOCITY:SURFACE:MAG < 10 {
	LOCK THROTTLE TO 1.
}

UNLOCK mySteer.
UNLOCK MYTHROTTLE.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
