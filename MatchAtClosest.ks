@LAZYGLOBAL OFF.

PARAMETER useOrbitingBody IS FALSE.
// Whether or not to wait for the operator to adjust the closest approach, and to press ENTER or AG1. If it is FALSE, the burn is planned once, from the closest approach that is found.
PARAMETER interactive IS TRUE.
// A time (UT seconds) to start the search for the closest approach from. If it is not in the future, the search starts a quarter orbit ahead.
PARAMETER guessTime IS TIME:SECONDS - 1.

CLEARSCREEN.
PRINT "Now matching velocity at closest position to target.".
IF interactive PRINT "Adjust closest approach using RCS if desired.".
IF interactive PRINT "Activate AG1 or press the ENTER key to end.".

LOCAL approach IS 0.
LOCAL shipToIntercept   IS VECDRAW(V(0,0,0), V(0,0,0), RED,   "Facing", 1, MAPVIEW).
LOCAL interceptToTarget IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Guidance", 1, MAPVIEW).
LOCAL tempChar IS "".
LOCAL passes IS 0.

AG1 OFF.

UNTIL AG1 OR (tempChar = TERMINAL:INPUT:ENTER) OR ((NOT interactive) AND passes > 0) {
	SET passes TO passes + 1.
	IF SHIP:ORBIT:HASNEXTPATCH {
		SET approach TO closestApproach(TIME:SECONDS + SHIP:ORBIT:NEXTPATCHETA / 2, SHIP:ORBIT:NEXTPATCHETA / 8).
	} ELSE {
		IF guessTime > TIME:SECONDS SET approach TO closestApproach(guessTime, 10).
		ELSE IF useOrbitingBody	SET approach TO closestApproach(TIME:SECONDS + SHIP:BODY:ORBIT:PERIOD / 4, SHIP:BODY:ORBIT:PERIOD / 8).
		ELSE 								SET approach TO closestApproach(TIME:SECONDS + SHIP:ORBIT:PERIOD / 4, SHIP:ORBIT:PERIOD / 8).
	}
	// If the target is a body, show closest approach distance relative to surface, not center.
	IF TARGET:TYPENAME = "Body" PRINT "Closest approach: " + distanceToString(approach["Distance"] - TARGET:RADIUS, 3) + "     " AT (0, 3).
	ELSE                        PRINT "Closest approach: " + distanceToString(approach["Distance"], 3) + "     " AT (0, 3).
	SET shipToIntercept:SHOW TO MAPVIEW.
	SET interceptToTarget:SHOW TO MAPVIEW.
	IF MAPVIEW {
		SET shipToIntercept:VEC TO POSITIONAT(SHIP, approach["Time"]).
		SET interceptToTarget:START TO shipToIntercept:VEC.
		SET interceptToTarget:VEC TO POSITIONAT(TARGET, approach["Time"]) - shipToIntercept:VEC.
	}
	IF TERMINAL:INPUT:HASCHAR {
		SET tempChar TO TERMINAL:INPUT:GETCHAR().
	}
}


LOCAL shipV IS VELOCITYAT(SHIP, approach["Time"]):ORBIT.
LOCAL targetV IS VELOCITYAT(TARGET, approach["Time"]):ORBIT.
LOCAL deltaVel IS targetV - shipV.

PRINT "Angle between velocities: " + ROUND(VANG(shipV, targetV), 2) + " degrees" AT (0, 3).

LOCAL normalVector IS VCRS(shipV, POSITIONAT(SHIP, approach["Time"]) - SHIP:BODY:POSITION):NORMALIZED.
LOCAL radialVector IS VCRS(normalVector, shipV):NORMALIZED.

LOCAL proDv IS VECTORDOTPRODUCT(deltaVel, shipV:NORMALIZED).
LOCAL normDv IS VECTORDOTPRODUCT(deltaVel, normalVector).
LOCAL radDv IS VECTORDOTPRODUCT(deltaVel, radialVector).

LOCAL newNode IS NODE(approach["Time"], radDv, normDv, proDv).
ADD newNode.

SET loopMessage TO "x_f: " + distanceToString(approach["Distance"], 2) + " v_f: " + distanceToString(deltaVel:MAG, 2) + "/s".
WAIT 1.
