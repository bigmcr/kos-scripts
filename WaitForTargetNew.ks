@LAZYGLOBAL OFF.
// draw several vectors - from target to body, from position to body, from position to velocity, from target to target velocity,
// from LAN of ship to body, from LAN of target to body
PARAMETER radiusMultiplier IS 2.5.

FUNCTION visualizeOrbitCreate {
	PARAMETER orbitToVis.
	PARAMETER objectName.
	PARAMETER vectorColor IS RED.
	PARAMETER length IS orbitToVis:BODY:RADIUS.
	PARAMETER arrowsInPlane IS 8.

	LOCAL orbitColor IS RGBA(vectorColor:R, vectorColor:G, vectorColor:B, 0.5).
	LOCAL bodyPos IS orbitToVis:BODY:POSITION.
	LOCAL LANVector TO (SOLARPRIMEVECTOR * ANGLEAXIS(-orbitToVis:LAN, NORTH:VECTOR)):NORMALIZED.
	LOCAL NormVector TO VCRS(orbitToVis:VELOCITY:ORBIT, orbitToVis:POSITION - bodyPos):NORMALIZED.
	LOCAL PeriVector TO (LANVector * ANGLEAXIS(-orbitToVis:ARGUMENTOFPERIAPSIS, NormVector)):NORMALIZED.

	LOCAL visualization IS LEXICON().
	visualization:ADD("Orbit", orbitToVis).
	visualization:ADD("LANVector", LANVector).
	visualization:ADD("NormVector", NormVector).
	visualization:ADD("PeriVector", PeriVector).
	visualization:ADD("Name", objectName).

	visualization:ADD(objectName,	VECDRAW(V(0,0,0), V(0,0,0), vectorColor, objectName     	, 1.0, TRUE, 0.2, TRUE)).
	SET visualization[objectName]:STARTUPDATER TO {RETURN bodyPos.}.
	SET visualization[objectName]:VECUPDATER TO {RETURN (orbitToVis:POSITION - bodyPos):NORMALIZED * length.}.

	visualization:ADD("Vel", 		  VECDRAW(V(0,0,0), V(0,0,0), vectorColor, objectName + " Vel"  	, 1.0, TRUE, 0.2, TRUE)).
	SET visualization["Vel"]:STARTUPDATER TO {RETURN orbitToVis:POSITION.}.
	SET visualization["Vel"]:VECUPDATER TO {RETURN orbitToVis:VELOCITY:ORBIT:NORMALIZED * length * 0.5.}.

	visualization:ADD("LAN", 		  VECDRAW(V(0,0,0), V(0,0,0), vectorColor, objectName + " LAN"  	, 1.0, TRUE, 0.2, FALSE)).
	SET visualization["LAN"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET visualization["LAN"]:VECUPDATER TO {RETURN length * LANVector.}.

	visualization:ADD("Norm", 		VECDRAW(V(0,0,0), V(0,0,0), vectorColor, objectName + " Normal", 1.0, TRUE, 0.2, TRUE)).
	SET visualization["Norm"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET visualization["Norm"]:VECUPDATER TO {RETURN length * normVector.}.

	visualization:ADD("Peri", 		VECDRAW(V(0,0,0), V(0,0,0), vectorColor, objectName + " Periapsis", 1.0, TRUE, 0.2, TRUE)).
	SET visualization["Peri"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET visualization["Peri"]:VECUPDATER TO {RETURN length * periVector.}.

	visualization:ADD("Plane",		LIST()).
	LOCAL angleOffset IS 360 / arrowsInPlane.
	IF orbitToVis:ECCENTRICITY > 1.0 SET angleOffset TO angleOffset / 2.0.
	FOR vecNumber IN RANGE(0, arrowsInPlane) {
		visualization["Plane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), orbitColor, "", 1.0, TRUE, 0.2, FALSE)).
		// these must be updated using the visualizeOrbitUpdate function.
	}
	FOR vecNumber IN RANGE(0, arrowsInPlane) {
		SET visualization["Plane"][vecNumber]:WIPING TO FALSE.
	}
	RETURN visualization.
}

FUNCTION visualizeOrbitUpdate {
	PARAMETER visualization.

	LOCAL bodyPos IS visualization["Orbit"]:BODY:POSITION.
	LOCAL LANVector TO (SOLARPRIMEVECTOR * ANGLEAXIS(-visualization["Orbit"]:LAN, NORTH:VECTOR)):NORMALIZED.
	LOCAL normVector TO VCRS(visualization["Orbit"]:VELOCITY:ORBIT, visualization["Orbit"]:POSITION - bodyPos):NORMALIZED.
	LOCAL PeriVector TO (LANVector * ANGLEAXIS(-visualization["Orbit"]:ARGUMENTOFPERIAPSIS, NormVector)):NORMALIZED.

	LOCAL arrowsInPlane IS visualization["Plane"]:LENGTH.
	LOCAL angleOffset IS 360 / arrowsInPlane.
	LOCAL semilatusRectum IS visualization["Orbit"]:SEMIMAJORAXIS * (1 - visualization["Orbit"]:ECCENTRICITY ^ 2).
	IF visualization["Orbit"]:ECCENTRICITY > 1.0 SET semilatusRectum TO -semilatusRectum.
	LOCAL radius1 IS semilatusRectum / (1 + visualization["Orbit"]:ECCENTRICITY * COS(visualization["Orbit"]:TRUEANOMALY)).
	LOCAL radius2 IS semilatusRectum / (1 + visualization["Orbit"]:ECCENTRICITY * COS(visualization["Orbit"]:TRUEANOMALY)).
	FOR vecNumber IN RANGE(0, arrowsInPlane) {
		SET radius1 TO semilatusRectum / (1 + visualization["Orbit"]:ECCENTRICITY * COS(angleOffset * (vecNumber + 0))).
		SET radius2 TO semilatusRectum / (1 + visualization["Orbit"]:ECCENTRICITY * COS(angleOffset * (vecNumber + 1))).
		SET visualization["Plane"][vecNumber]:START TO radius1 * LANVector * ANGLEAXIS(-angleOffset * vecNumber, normVector) + bodyPos.
		SET visualization["Plane"][vecNumber]:VEC   TO (
			radius2 * LANVector * ANGLEAXIS(-angleOffset * (vecNumber + 1), normVector) - radius1 * LANVector * ANGLEAXIS(-angleOffset * vecNumber, normVector)).
	}
}

FUNCTION visualizeOrbitSetShow {
	PARAMETER visualization.
	PARAMETER showVecDraws.
	SET visualization[visualization["Name"]]:SHOW TO showVecDraws.
	SET visualization["Vel"]:SHOW TO showVecDraws.
	SET visualization["LAN"]:SHOW TO showVecDraws.
	SET visualization["Norm"]:SHOW TO showVecDraws.
	SET visualization["Peri"]:SHOW TO showVecDraws.
	FOR vecNumber IN RANGE(0, visualization["Plane"]:LENGTH) {
		SET visualization["Plane"][vecnumber]:SHOW TO showVecDraws.
	}
}

MAPVIEW ON.

LOCAL radius IS (SHIP:BODY:RADIUS + SHIP:BODY:ATM:HEIGHT) * radiusMultiplier.

LOCAL equatorialOrbit IS CREATEORBIT(0, 0, radius, 0, 0, 0, TIME:SECONDS, SHIP:BODY).
LOCAL testOrbit IS CREATEORBIT(45, 1.75, -radius*2, 0, 0, 0, TIME:SECONDS, SHIP:BODY).

// Create an orbit that is in the plane of the ecliptic for this body.
// Position is RADIUS away from the body in the opposite direction of BODY:BODY.
// Velocity is in the same direction as the BODY is currently moving, but normalized to make the orbit.
LOCAL eclipticPos IS (SHIP:BODY:POSITION - SHIP:BODY:BODY:POSITION):NORMALIZED * radius.
LOCAL eclipticVel IS VXCL(eclipticPos, SHIP:BODY:BODY:VELOCITY:ORBIT):NORMALIZED * SQRT(SHIP:BODY:MU/radius).
LOCAL eclipticOrbit IS CREATEORBIT(eclipticPos, eclipticVel, SHIP:BODY, TIME:SECONDS).

LOCAL shipOrbitViz IS     visualizeOrbitCreate(SHIP:ORBIT,      "Ship",          RED, radius, 16).
LOCAL targetOrbitViz IS   visualizeOrbitCreate(TARGET:ORBIT,    "Target",      GREEN, radius, 16).
LOCAL EquatorOrbitViz IS  visualizeOrbitCreate(equatorialOrbit, "Equator",    PURPLE, radius, 16).
LOCAL testOrbitViz IS     visualizeOrbitCreate(testOrbit,       "Test Orbit",  WHITE, radius, 16).
LOCAL EclipticOrbitViz IS visualizeOrbitCreate(eclipticOrbit,   "Ecliptic",     BLUE, radius, 16).

LOCAL eclipticPosVecDraw IS VECDRAW(SHIP:BODY:POSITION, eclipticPos, YELLOW, "Position", 1.0, TRUE, 0.2, TRUE).
LOCAL eclipticVelVecDraw IS VECDRAW(eclipticPos, eclipticVel*1000, CYAN, "Velocity", 1.0, TRUE, 0.2, TRUE).

AG1 OFF. AG2 OFF. AG3 OFF. AG4 OFF. AG5 OFF. AG6 OFF.

CLEARSCREEN.
UNTIL AG1
{
	visualizeOrbitSetShow(shipOrbitViz, AG2).
	visualizeOrbitSetShow(targetOrbitViz, AG3).
	visualizeOrbitSetShow(EquatorOrbitViz, AG4).
	visualizeOrbitSetShow(testOrbitViz, AG5).
	visualizeOrbitSetShow(EclipticOrbitViz, AG6).
	visualizeOrbitUpdate(shipOrbitViz).
	visualizeOrbitUpdate(targetOrbitViz).
	visualizeOrbitUpdate(EquatorOrbitViz).
	visualizeOrbitUpdate(testOrbitViz).
	visualizeOrbitUpdate(EclipticOrbitViz).
	PRINT "Orbit       Color        Distance          Velocity  " AT (0, 0).
	PRINT "Ship        Red    " + distanceToString(shipOrbitViz["NormVector"] * shipOrbitViz["Orbit"]:POSITION):PADLEFT(14) + distanceToString(shipOrbitViz["NormVector"] * SHIP:VELOCITY:ORBIT):PADLEFT(14) + "/s       " AT (0, 1).
	PRINT "Target    Green    " + distanceToString(targetOrbitViz["NormVector"] * targetOrbitViz["Orbit"]:POSITION):PADLEFT(14) + distanceToString(targetOrbitViz["NormVector"] * SHIP:VELOCITY:ORBIT):PADLEFT(14) + "/s       " AT (0, 2).
	PRINT "Equator  Purple    " + distanceToString(EquatorOrbitViz["NormVector"] * EquatorOrbitViz["Orbit"]:POSITION):PADLEFT(14) + distanceToString(EquatorOrbitViz["NormVector"] * SHIP:VELOCITY:ORBIT):PADLEFT(14) + "/s       " AT (0, 3).
	PRINT "Test      White    " + distanceToString(testOrbitViz["NormVector"] * testOrbitViz["Orbit"]:POSITION):PADLEFT(14) + distanceToString(testOrbitViz["NormVector"] * SHIP:VELOCITY:ORBIT):PADLEFT(14) + "/s       " AT (0, 4).
	PRINT "Ecliptic   Blue    " + distanceToString(EclipticOrbitViz["NormVector"] * EclipticOrbitViz["Orbit"]:POSITION):PADLEFT(14) + distanceToString(EclipticOrbitViz["NormVector"] * SHIP:VELOCITY:ORBIT):PADLEFT(14) + "/s       " AT (0, 5).
	WAIT 0.
}

SET loopMessage TO "Planes displayed".
