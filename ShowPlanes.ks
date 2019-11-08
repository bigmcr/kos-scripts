@LAZYGLOBAL OFF.
// draw several vectors - from target to body, from position to body, from position to velocity, from target to target velocity,
// from LAN of ship to body, from LAN of target to body

LOCAL vecDraws IS LEXICON().

LOCAL done IS FALSE.

ON AG1 {
	SET done TO TRUE.
}

vecDraws:ADD("Target", 			VECDRAW(V(0,0,0), V(0,0,0), RED, "Target"     , 1.0, TRUE, 0.2)).
vecDraws:ADD("TargetVel", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target Vel"  , 1.0, TRUE, 0.2)).
vecDraws:ADD("TargetLAN", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target LAN"  , 1.0, TRUE, 0.2)).
vecDraws:ADD("TargetNorm", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target Normal"  , 1.0, TRUE, 0.2)).
vecDraws:ADD("TargetPlane",		LIST()).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).
vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, 0.2)).

vecDraws:ADD("Prime Vector", 	VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Prime Vector", 1.0, TRUE, 0.2)).

vecDraws:ADD("Ship", 			VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship"     , 1.0, TRUE, 0.2)).
vecDraws:ADD("ShipVel", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship Vel"  , 1.0, TRUE, 0.2)).
vecDraws:ADD("ShipLAN", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship LAN"  , 1.0, TRUE, 0.2)).
vecDraws:ADD("ShipNorm", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship Normal"  , 1.0, TRUE, 0.2)).
vecDraws:ADD("ShipPlane",		LIST()).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).
vecDraws["ShipPlane"]:ADD(		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, 0.2)).

LOCAL radius IS (SHIP:BODY:RADIUS + SHIP:BODY:ATM:HEIGHT) * 1.2.

LOCAL northV IS NORTH:VECTOR.
LOCAL bodyPos IS SHIP:BODY:POSITION.

LOCAL targetLANVector TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-TARGET:ORBIT:LAN, northV)):NORMALIZED.
LOCAL targetNormVector TO radius * VCRS(TARGET:VELOCITY:ORBIT, TARGET:POSITION - bodyPos):NORMALIZED.

LOCAL shipLANVector TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-SHIP:ORBIT:LAN, northV)):NORMALIZED.
LOCAL shipNormVector TO radius * VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - bodyPos):NORMALIZED.

CLEARSCREEN.
UNTIL done
{
	printOrbit(SHIP:ORBIT, "Ship Orbit", 0, 0).
	printOrbit(TARGET:ORBIT, "Target Orbit", 40, 0).
	SET bodyPos TO SHIP:BODY:POSITION.
	PRINT "The ship is " + ROUND(targetNormVector * (  SHIP:POSITION - bodyPos)/1000, 1):TOSTRING:PADLEFT(7) + " kilometers from the target plane.        " AT (0, 9).
	PRINT "The target is " + ROUND(shipNormVector * (TARGET:POSITION - bodyPos)/1000, 1):TOSTRING:PADLEFT(7) + " kilometers from the ship plane.        " AT (0, 10).
	SET targetLANVector TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-TARGET:ORBIT:LAN, northV)):NORMALIZED.
	SET targetNormVector TO VCRS(TARGET:VELOCITY:ORBIT, TARGET:POSITION - bodyPos):NORMALIZED.
	SET shipLANVector TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-SHIP:ORBIT:LAN, northV)):NORMALIZED.
	SET shipNormVector TO VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - bodyPos):NORMALIZED.
	// draw several vectors - from target to body, from position to body, from position to velocity, from target to target velocity,
	// from LAN of ship to body, from LAN of target to body
	SET vecDraws["Target"]:START TO bodyPos.
	SET vecDraws["Target"]:VEC TO (TARGET:POSITION - bodyPos):NORMALIZED * RADIUS.
	SET vecDraws["TargetVel"]:START TO TARGET:POSITION.
	SET vecDraws["TargetVel"]:VEC TO TARGET:VELOCITY:ORBIT:NORMALIZED * RADIUS * 0.5.
	SET vecDraws["TargetLAN"]:START TO bodyPos.
	SET vecDraws["TargetLAN"]:VEC TO targetLANVector.
	SET vecDraws["TargetNorm"]:START TO bodyPos.
	SET vecDraws["TargetNorm"]:VEC TO radius * targetNormVector.
	FOR vecNumber IN RANGE(0, vecDraws["TargetPlane"]:LENGTH) {
		SET vecDraws["TargetPlane"][vecNumber]:START TO targetLANVector * ANGLEAXIS(-45 * vecNumber, targetNormVector) + bodyPos.
		SET vecDraws["TargetPlane"][vecNumber]:VEC   TO targetLANVector * ANGLEAXIS(-45 * (vecNumber + 1), targetNormVector) - targetLANVector * ANGLEAXIS(-45 * vecNumber, targetNormVector).
	}

	SET vecDraws["Prime Vector"]:START TO bodyPos.
	SET vecDraws["Prime Vector"]:VEC TO SOLARPRIMEVECTOR * radius.

	SET vecDraws["Ship"]:START TO bodyPos.
	SET vecDraws["Ship"]:VEC TO (SHIP:POSITION - bodyPos):NORMALIZED * RADIUS.
	SET vecDraws["ShipVel"]:START TO V(0,0,0).
	SET vecDraws["ShipVel"]:VEC TO SHIP:VELOCITY:ORBIT:NORMALIZED * RADIUS * 0.5.
	SET vecDraws["ShipLAN"]:START TO bodyPos.
	SET vecDraws["ShipLAN"]:VEC TO shipLANVector.
	SET vecDraws["ShipNorm"]:START TO bodyPos.
	SET vecDraws["ShipNorm"]:VEC TO radius * shipNormVector.
	FOR vecNumber IN RANGE(0, vecDraws["ShipPlane"]:LENGTH) {
		SET vecDraws["ShipPlane"][vecNumber]:START TO shipLANVector * ANGLEAXIS(-45 * vecNumber, shipNormVector) + bodyPos.
		SET vecDraws["ShipPlane"][vecNumber]:VEC   TO shipLANVector * ANGLEAXIS(-45 * (vecNumber + 1), shipNormVector) - shipLANVector * ANGLEAXIS(-45 * vecNumber, shipNormVector).
	}
	WAIT 0.
}