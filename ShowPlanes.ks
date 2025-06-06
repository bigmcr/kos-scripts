@LAZYGLOBAL OFF.
// draw several vectors - from target to body, from position to body, from position to velocity, from target to target velocity,
// from LAN of ship to body, from LAN of target to body
PARAMETER radiusMultiplier IS 2.5.
PARAMETER showEcliptic IS FALSE.
LOCAL vecDraws IS LEXICON().
LOCAL startedWithTarget IS HASTARGET.
LOCAL done IS FALSE.
LOCAL vecDrawWidth IS 0.1.
LOCAL arrowsInPlane IS 16.
IF NOT SHIP:BODY:HASBODY SET showEcliptic TO FALSE.

MAPVIEW ON.

ON AG1 {
	SET done TO TRUE.
}

ON AG2 {
	SET showEcliptic TO NOT showEcliptic AND SHIP:BODY:HASBODY.
	RETURN TRUE.
}

LOCAL orbits IS LIST().
LOCAL targetOrbit IS 0.
IF HASTARGET {
	SET targetOrbit TO TARGET:ORBIT.
	UNTIL NOT targetOrbit:HASNEXTPATCH {
	  orbits:ADD(targetOrbit).
	  SET targetOrbit TO targetOrbit:NEXTPATCH.
	}
	orbits:ADD(targetOrbit).
}
LOCAL finalTargetOrbit IS 0.
LOCAL previousTargetOrbit IS 0.
FOR eachOrbit IN orbits {
  IF eachOrbit:HASNEXTPATCH AND eachOrbit:NEXTPATCH:BODY:NAME = SHIP:BODY:NAME {
    SET previousTargetOrbit TO eachOrbit.
  }
  IF eachOrbit:BODY:NAME = SHIP:BODY:NAME {
    SET finalTargetOrbit TO eachOrbit.
  }
}
LOCAL targetPositionTime IS TIME:SECONDS.
IF HASTARGET AND (TARGET:BODY:NAME <> SHIP:BODY:NAME) {
	SET targetPositionTime TO (finalTargetOrbit:NEXTPATCHETA + previousTargetOrbit:NEXTPATCHETA)/2.
} ELSE SET targetPositionTime TO TIME:SECONDS.

LOCAL radius IS (SHIP:BODY:RADIUS + SHIP:BODY:ATM:HEIGHT) * radiusMultiplier.

LOCAL northV IS NORTH:VECTOR.
LOCAL bodyPos IS SHIP:BODY:POSITION.

LOCAL targetLANVector TO V(0,0,0).
LOCAL targetNormVector TO V(0,0,0).
LOCAL targetPeriVector TO V(0,0,0).
IF startedWithTarget {
	SET targetLANVector TO (SOLARPRIMEVECTOR * ANGLEAXIS(-finalTargetOrbit:LAN, northV)):NORMALIZED.
	SET targetNormVector TO VCRS(TARGET:VELOCITY:ORBIT, POSITIONAT(TARGET, targetPositionTime) - bodyPos):NORMALIZED.
	SET targetPeriVector TO (targetLANVector * ANGLEAXIS(-finalTargetOrbit:ARGUMENTOFPERIAPSIS, targetNormVector)):NORMALIZED.
}

LOCAL eclipticNormVector TO V(0, 0, 0).
IF showEcliptic SET eclipticNormVector TO radius * 2 * VCRS(SHIP:BODY:VELOCITY:ORBIT, SHIP:BODY:POSITION - SHIP:BODY:BODY:POSITION):NORMALIZED.

LOCAL shipLANVector TO (SOLARPRIMEVECTOR * ANGLEAXIS(-SHIP:ORBIT:LAN, northV)):NORMALIZED.
LOCAL shipNormVector TO VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - bodyPos):NORMALIZED.
LOCAL shipPeriVector TO (shipLANVector * ANGLEAXIS(-SHIP:ORBIT:ARGUMENTOFPERIAPSIS, shipNormVector)):NORMALIZED.

IF startedWithTarget {
	//                            start,            vec,      color, label,        scale, show, width, pointy
	vecDraws:ADD("Target", 				VECDRAW(V(0,0,0), V(0,0,0), RED, "Target"     	, 1.0, TRUE, 0.2, TRUE)).
	SET vecDraws["Target"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET vecDraws["Target"]:VECUPDATER TO {RETURN (POSITIONAT(TARGET, targetPositionTime) - bodyPos):NORMALIZED * RADIUS.}.
	vecDraws:ADD("TargetVel", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target Vel"  	, 1.0, TRUE, 0.2, TRUE)).
	SET vecDraws["TargetVel"]:STARTUPDATER TO {RETURN POSITIONAT(TARGET, targetPositionTime).}.
	SET vecDraws["TargetVel"]:VECUPDATER TO {RETURN TARGET:VELOCITY:ORBIT:NORMALIZED * RADIUS * 0.5.}.
	vecDraws:ADD("TargetLAN", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target LAN"  	, 1.0, TRUE, 0.2, FALSE)).
	SET vecDraws["TargetLAN"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET vecDraws["TargetLAN"]:VECUPDATER TO {RETURN radius * targetLANVector.}.
	vecDraws:ADD("TargetNorm", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target Normal", 1.0, TRUE, 0.2, TRUE)).
	SET vecDraws["TargetNorm"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET vecDraws["TargetNorm"]:VECUPDATER TO {RETURN radius * targetNormVector.}.
	vecDraws:ADD("TargetPeri", 		VECDRAW(V(0,0,0), V(0,0,0), RED, "Target Periapsis", 1.0, TRUE, 0.2, TRUE)).
	SET vecDraws["TargetPeri"]:STARTUPDATER TO {RETURN bodyPos.}.
	SET vecDraws["TargetPeri"]:VECUPDATER TO {RETURN radius * targetPeriVector.}.
	vecDraws:ADD("TargetPlane",		LIST()).
	FOR vecNumber IN RANGE(0, arrowsInPlane) {
		vecDraws["TargetPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), RED, "", 1.0, TRUE, vecDrawWidth, FALSE)).
	}
	// the plane vectors are updated in the loop rather than with updater functions.
}
vecDraws:ADD("EclipticNorm", 		VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Ecliptic Normal", 1.0, TRUE, 0.2, TRUE)).
SET vecDraws["EclipticNorm"]:STARTUPDATER TO {RETURN bodyPos.}.
SET vecDraws["EclipticNorm"]:VECUPDATER TO {RETURN radius * eclipticNormVector.}.
vecDraws:ADD("EclipticPlane",		LIST()).
FOR vecNumber IN RANGE(0, arrowsInPlane) {
	vecDraws["EclipticPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), GREEN, "", 1.0, TRUE, vecDrawWidth, FALSE)).
}
// the plane vectors are updated in the loop rather than with updater functions.

vecDraws:ADD("Prime Vector", 	VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Prime Vector", 1.0, TRUE, 0.2, FALSE)).
SET vecDraws["Prime Vector"]:STARTUPDATER TO {RETURN bodyPos.}.
SET vecDraws["Prime Vector"]:VECUPDATER TO {RETURN SOLARPRIMEVECTOR * radius.}.

vecDraws:ADD("Ship", 		  	VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship"     		, 1.0, TRUE, 0.2, TRUE)).
SET vecDraws["Ship"]:STARTUPDATER TO {RETURN bodyPos.}.
SET vecDraws["Ship"]:VECUPDATER TO {RETURN (SHIP:POSITION - bodyPos):NORMALIZED * RADIUS.}.

vecDraws:ADD("ShipVel", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship Vel"  	, 1.0, TRUE, 0.2, TRUE)).
SET vecDraws["ShipVel"]:START TO V(0,0,0).
SET vecDraws["ShipVel"]:VECUPDATER TO {RETURN SHIP:VELOCITY:ORBIT:NORMALIZED * RADIUS * 0.5.}.

vecDraws:ADD("ShipLAN", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship LAN"  	, 1.0, TRUE, 0.2, FALSE)).
SET vecDraws["ShipLAN"]:STARTUPDATER TO {RETURN bodyPos.}.
SET vecDraws["ShipLAN"]:VECUPDATER TO {RETURN radius * shipLANVector.}.

vecDraws:ADD("ShipNorm", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship Normal" , 1.0, TRUE, 0.2, TRUE)).
SET vecDraws["ShipNorm"]:STARTUPDATER TO {RETURN bodyPos.}.
SET vecDraws["ShipNorm"]:VECUPDATER TO {RETURN radius * shipNormVector.}.

vecDraws:ADD("ShipPeri", 		VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Ship Periapsis" , 1.0, TRUE, 0.2, TRUE)).
SET vecDraws["ShipPeri"]:STARTUPDATER TO {RETURN bodyPos.}.
SET vecDraws["ShipPeri"]:VECUPDATER TO {RETURN radius * shipPeriVector.}.

vecDraws:ADD("ShipPlane",		LIST()).
FOR vecNumber IN RANGE(0, arrowsInPlane) {
	vecDraws["ShipPlane"]:ADD(	VECDRAW(V(0,0,0), V(0,0,0), BLUE, "", 1.0, TRUE, vecDrawWidth, FALSE)).
}
// the plane vectors are updated in the loop rather than with updater functions.

CLEARSCREEN.
UNTIL done OR NOT MAPVIEW
{
	printOrbit(SHIP:ORBIT, "Ship Orbit", 0, 0).
	IF startedWithTarget printOrbit(finalTargetOrbit, "Target Orbit", 40, 0).
	SET bodyPos TO SHIP:BODY:POSITION.
	PRINT "The ship is " + distanceToString(targetNormVector * (  SHIP:POSITION - bodyPos), 2):TOSTRING:PADLEFT(10) + " from the target plane.        " AT (0, 10).
	IF showEcliptic {
		PRINT "The ship is " + distanceToString(eclipticNormVector * (  SHIP:POSITION - bodyPos), 2):PADLEFT(10) + " from the ecliptic plane.        " AT (0, 11).
		PRINT "The ship's inclination is " + ROUND(VANG(shipNormVector, eclipticNormVector), 4) + " degrees from the ecliptic.        " AT (0, 12).
	} ELSE {
		PRINT "                                                                 " AT (0, 11).
		PRINT "                                                                 " AT (0, 12).
	}
	IF startedWithTarget {
		PRINT "The ship's inclination is " + ROUND(VANG(shipNormVector, targetNormVector), 4) + " degrees from the target's inclination.        " AT (0, 13).
		PRINT "Activate AG1 or leave map view to end script.        " AT (0, 15).
		PRINT "Activate AG2 to toggle ecliptic plane data.        "   AT (0, 16).
	} ELSE {
		PRINT "Activate AG1 or leave map view to end script.        " AT (0, 14).
		PRINT "Activate AG2 to toggle ecliptic plane data.        "   AT (0, 15).
	}
	IF startedWithTarget {
		SET targetLANVector  TO (SOLARPRIMEVECTOR * ANGLEAXIS(-finalTargetOrbit:LAN, northV)):NORMALIZED.
		SET targetNormVector TO VCRS(TARGET:VELOCITY:ORBIT, POSITIONAT(TARGET, targetPositionTime) - bodyPos):NORMALIZED.
		SET targetPeriVector TO (targetLANVector * ANGLEAXIS(-finalTargetOrbit:ARGUMENTOFPERIAPSIS, targetNormVector)):NORMALIZED.
	} ELSE {
		SET targetLANVector  TO V(0, 0, 0).
		SET targetNormVector TO V(0, 0, 0).
		SET targetPeriVector TO V(0, 0, 0).
	}
	SET shipLANVector TO (SOLARPRIMEVECTOR * ANGLEAXIS(-SHIP:ORBIT:LAN, northV)):NORMALIZED.
	SET shipNormVector TO VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - bodyPos):NORMALIZED.
	SET shipPeriVector TO (shipLANVector * ANGLEAXIS(-SHIP:ORBIT:ARGUMENTOFPERIAPSIS, shipNormVector)):NORMALIZED.
	IF showEcliptic	SET eclipticNormVector TO VCRS(-SHIP:BODY:BODY:VELOCITY:ORBIT, SHIP:BODY:POSITION - SHIP:BODY:BODY:POSITION):NORMALIZED.

	// draw several vectors - from target to body, from position to body, from position to velocity, from target to target velocity,
	// from LAN of ship to body, from LAN of target to body
	IF startedWithTarget {
		FOR vecNumber IN RANGE(0, vecDraws["TargetPlane"]:LENGTH) {
			SET vecDraws["TargetPlane"][vecNumber]:START TO radius * targetLANVector * ANGLEAXIS(-45 * vecNumber, targetNormVector) + bodyPos.
			SET vecDraws["TargetPlane"][vecNumber]:VEC   TO radius * (targetLANVector * ANGLEAXIS(-45 * (vecNumber + 1), targetNormVector) - targetLANVector * ANGLEAXIS(-45 * vecNumber, targetNormVector)).
		}
	}

	FOR vecNumber IN RANGE(0, vecDraws["ShipPlane"]:LENGTH) {
		SET vecDraws["ShipPlane"][vecNumber]:START TO radius * shipLANVector * ANGLEAXIS(-45 * vecNumber, shipNormVector) + bodyPos.
		SET vecDraws["ShipPlane"][vecNumber]:VEC   TO radius * (shipLANVector * ANGLEAXIS(-45 * (vecNumber + 1), shipNormVector) - shipLANVector * ANGLEAXIS(-45 * vecNumber, shipNormVector)).
	}

	SET vecDraws["EclipticNorm"]:SHOW TO showEcliptic.
	FOR vecNumber IN RANGE(0, vecDraws["EclipticPlane"]:LENGTH) {
		SET vecDraws["EclipticPlane"][vecNumber]:SHOW  TO showEcliptic.
		SET vecDraws["EclipticPlane"][vecNumber]:START TO radius * SOLARPRIMEVECTOR * ANGLEAXIS(-45 * vecNumber, eclipticNormVector) + bodyPos.
		SET vecDraws["EclipticPlane"][vecNumber]:VEC   TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-45 * (vecNumber + 1), eclipticNormVector) - SOLARPRIMEVECTOR * ANGLEAXIS(-45 * vecNumber, eclipticNormVector)).
	}

	SET orbits TO LIST().
	IF HASTARGET {
		SET targetOrbit TO TARGET:ORBIT.
		UNTIL NOT targetOrbit:HASNEXTPATCH {
		  orbits:ADD(targetOrbit).
		  SET targetOrbit TO targetOrbit:NEXTPATCH.
		}
		orbits:ADD(targetOrbit).
	}
	SET finalTargetOrbit TO 0.
	SET previousTargetOrbit TO 0.
	FOR eachOrbit IN orbits {
	  IF eachOrbit:HASNEXTPATCH AND eachOrbit:NEXTPATCH:BODY:NAME = SHIP:BODY:NAME {
	    SET previousTargetOrbit TO eachOrbit.
	  }
	  IF eachOrbit:BODY:NAME = SHIP:BODY:NAME {
	    SET finalTargetOrbit TO eachOrbit.
	  }
	}
	IF HASTARGET AND (TARGET:BODY:NAME <> SHIP:BODY:NAME) {
		SET targetPositionTime TO (finalTargetOrbit:NEXTPATCHETA + previousTargetOrbit:NEXTPATCHETA)/2.
	} ELSE SET targetPositionTime TO TIME:SECONDS.
	WAIT 0.
}

SET loopMessage TO "Planes displayed".
