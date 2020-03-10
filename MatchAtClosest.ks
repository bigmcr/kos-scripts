@LAZYGLOBAL OFF.

PARAMETER useOrbitingBody IS FALSE.

CLEARSCREEN.
PRINT "Now matching velocity at closest position to target.".
PRINT "Adjust closest approach using RCS if desired. Activate AG1 to end.".

LOCAL approach IS 0.
LOCAL shipToIntercept   IS VECDRAW(V(0,0,0), V(0,0,0), RED,   "Facing", 1, MAPVIEW).
LOCAL interceptToTarget IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Guidance", 1, MAPVIEW).

AG1 OFF.

UNTIL AG1 {
	IF useOrbitingBody	SET approach TO closestApproach(TIME:SECONDS + SHIP:BODY:ORBIT:PERIOD / 4, SHIP:BODY:ORBIT:PERIOD / 10).
	ELSE 				SET approach TO closestApproach(TIME:SECONDS + SHIP:ORBIT:PERIOD / 4, SHIP:ORBIT:PERIOD / 10).
	PRINT "Closest approach: " + distanceToString(approach[1], 3) + "     " AT (0, 2).
	SET shipToIntercept:SHOW TO MAPVIEW.
	SET interceptToTarget:SHOW TO MAPVIEW.
	IF MAPVIEW {
		SET shipToIntercept:VEC TO POSITIONAT(SHIP, approach[0]).
		SET interceptToTarget:START TO shipToIntercept:VEC.
		SET interceptToTarget:VEC TO POSITIONAT(TARGET, approach[0]) - shipToIntercept:VEC.
	}
}


LOCAL shipV IS VELOCITYAT(SHIP, approach[0]):ORBIT.
LOCAL targetV IS VELOCITYAT(TARGET, approach[0]):ORBIT.
LOCAL deltaVel IS targetV - shipV.

PRINT "Angle between velocities: " + ROUND(VANG(shipV, targetV), 2) + " degrees" AT (0, 3).

LOCAL normalVector IS VCRS(shipV, POSITIONAT(SHIP, approach[0]) - SHIP:BODY:POSITION):NORMALIZED.
LOCAL radialVector IS VCRS(normalVector, shipV):NORMALIZED.

LOCAL proDv IS VECTORDOTPRODUCT(deltaVel, shipV:NORMALIZED).
LOCAL normDv IS VECTORDOTPRODUCT(deltaVel, normalVector).
LOCAL radDv IS VECTORDOTPRODUCT(deltaVel, radialVector).

LOCAL newNode IS NODE(approach[0], radDv, normDv, proDv).
ADD newNode.

SET loopMessage TO "x_f: " + distanceToString(approach[1], 2) + " v_f: " + distanceToString(deltaVel:MAG, 2) + "/s".
WAIT 1.
