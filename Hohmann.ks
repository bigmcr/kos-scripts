@LAZYGLOBAL OFF.
CLEARSCREEN.

// calculate and create nodes for a Hohmann transfer orbit to the specified altitude,
// or to the current target (assumed to be in the same plane as the ship, but in an
// elliptical orbit).
// Creates nodes for the initial transfer burn only.
PARAMETER finalAltitude IS "Default".    // Final Altitude above sea level. Does NOT include BODY:RADIUS.
                            // Or the string "target" (or "tar") to transfer to the target.
PARAMETER acknowledge IS FALSE.

IF finalAltitude = "Default" {
	IF HASTARGET SET finalAltitude TO (TARGET:POSITION - BODY:POSITION):MAG - BODY:RADIUS.
	ELSE SET finalAltitude TO 150000.
}

LOCAL errorCode IS "None".
LOCAL transferToTarget IS FALSE.
IF finalAltitude:TYPENAME = "String" {
  IF finalAltitude = "target" OR finalAltitude = "tar" {
    IF HASTARGET SET transferToTarget TO TRUE.
    ELSE SET errorCode TO "No target selected".
  }
}

IF errorCode = "None" {
  IF transferToTarget {
    IF TARGET:BODY <> BODY SET errorCode TO "Target does not orbit " + BODY:NAME.
    ELSE IF TARGET:ORBIT:ECCENTRICITY >= 1 SET errorCode TO "Target orbit is not elliptical".
  } ELSE {
    SET finalAltitude TO processScalarParameter(finalAltitude, -1).
    IF finalAltitude <= 0 SET errorCode TO "Invalid final altitude".
    ELSE IF (finalAltitude > SHIP:ORBIT:PERIAPSIS) AND (finalAltitude < SHIP:ORBIT:APOAPSIS) SET errorCode TO "Apo > Final Alt > Peri".
  }
}
IF errorCode = "None" {
  IF SHIP:ORBIT:TRANSITION <> "Final" SET errorCode TO "Transition occures!".
  ELSE IF SHIP:ORBIT:ECCENTRICITY >= 1 SET errorCode TO "Ship orbit is not elliptical".
}

IF errorCode = "None" {
  LOCAL mu IS BODY:MU.
  LOCAL minLeadTime IS 60.
  LOCAL nodeTime IS TIME:SECONDS + minLeadTime.
  LOCAL r_1 IS 0.
  LOCAL r_2 IS 0.

  IF transferToTarget {
    // Departure at ship radius r_1 puts the transfer orbit's near apsis at the burn and its
    // far apsis, radius r_2, on the opposite side of the body, 180 degrees of travel later.
    // Both radii depend on the departure time (the orbits are elliptical), and r_2 depends on
    // the flight time, which depends on r_2, so for each departure time iterate to resolve it.
    // The ship's orbital direction (plane normal) is fixed, so compute it once.
    LOCAL planeNormal IS VCRS(-BODY:POSITION, SHIP:VELOCITY:ORBIT):NORMALIZED.

    // Returns LIST(r_1, r_2, flightTime, angleError) for a departure dt seconds from now.
    // angleError is how far (degrees) the target is from the arrival point at the arrival time.
    LOCAL transferAt IS {
      PARAMETER dt.
      LOCAL departTime IS TIME:SECONDS + dt.
      LOCAL shipVector IS POSITIONAT(SHIP, departTime) - BODY:POSITION.
      LOCAL r1 IS shipVector:MAG.
      LOCAL r2 IS TARGET:ORBIT:SEMIMAJORAXIS.
      LOCAL flightTime IS 0.
      LOCAL targetVector IS V(0, 0, 0).
      FROM {LOCAL pass IS 0.} UNTIL pass >= 5 STEP {SET pass TO pass + 1.} DO {
        SET flightTime TO CONSTANT:PI * SQRT(((r1 + r2) / 2) ^ 3 / mu).
        SET targetVector TO POSITIONAT(TARGET, departTime + flightTime) - BODY:POSITION.
        SET r2 TO targetVector:MAG.
      }
      LOCAL arrivalAngle IS VANGSigned(shipVector, VXCL(planeNormal, targetVector), planeNormal).
      RETURN LIST(r1, r2, flightTime, normalizeAngle180(arrivalAngle - 180)).
    }.
    LOCAL angleErrorAt IS {PARAMETER dt. RETURN transferAt(dt)[3].}.

    // Search one synodic period (plus margin) for the first time the target is where the transfer arrives.
    LOCAL shipRate IS 1 / SHIP:ORBIT:PERIOD.
    LOCAL targetRate IS 1 / TARGET:ORBIT:PERIOD.
    LOCAL synodicPeriod IS 1 / MAX(ABS(shipRate - targetRate), 1e-12).
    IF synodicPeriod > 100 * MAX(SHIP:ORBIT:PERIOD, TARGET:ORBIT:PERIOD) SET errorCode TO "Orbital periods too similar".
    ELSE {
      LOCAL samples IS 240.
      LOCAL span IS 1.1 * synodicPeriod.
      LOCAL sampleStep IS span / samples.
      LOCAL foundWindow IS FALSE.
      LOCAL lowTime IS minLeadTime.
      LOCAL lowError IS angleErrorAt(lowTime).
      LOCAL index IS 0.
      UNTIL foundWindow OR index >= samples {
        LOCAL highTime IS lowTime + sampleStep.
        LOCAL highError IS angleErrorAt(highTime).
        // A sign change with both errors small is a real root; a sign change near +-180 is just the angle wrapping.
        IF lowError * highError <= 0 AND ABS(lowError) < 90 AND ABS(highError) < 90 {
          SET foundWindow TO TRUE.
          SET nodeTime TO TIME:SECONDS + findZeroBrent(angleErrorAt, lowTime, highTime, 0.01).
        } ELSE {
          SET lowTime TO highTime.
          SET lowError TO highError.
          SET index TO index + 1.
        }
      }
      IF NOT foundWindow SET errorCode TO "No transfer window found".
      ELSE {
        LOCAL solution IS transferAt(nodeTime - TIME:SECONDS).
        SET r_1 TO solution[0].
        SET r_2 TO solution[1].
        PRINT "Flight time: " + timeToString(solution[2]).
        PRINT "Residual angle error: " + ROUND(solution[3], 4) + " deg".
      }
    }
  } ELSE {
    // Burn at the apsis on the opposite side of the orbit from the final altitude.
    SET r_2 TO finalAltitude + BODY:RADIUS.
    IF finalAltitude > SHIP:ORBIT:APOAPSIS SET nodeTime TO TIME:SECONDS + ETA:PERIAPSIS.
    ELSE SET nodeTime TO TIME:SECONDS + ETA:APOAPSIS.
    SET r_1 TO (POSITIONAT(SHIP, nodeTime) - BODY:POSITION):MAG.
  }

  IF errorCode = "None" {
    LOCAL shipPosition IS POSITIONAT(SHIP, nodeTime) - BODY:POSITION.
    LOCAL shipVelocity IS VELOCITYAT(SHIP, nodeTime):ORBIT.
    LOCAL burn IS hohmannBurn(shipPosition, shipVelocity, r_2, SHIP:BODY).
    LOCAL currentSMA IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL transferSMA IS burn["transferSMA"].
    LOCAL orbitalSpeedPreTransferBurn IS SQRT(mu * (2 / r_1 - 1 / currentSMA)).
    LOCAL orbitalSpeedPreTransferBurnMeasured IS shipVelocity:MAG.
    LOCAL orbitalSpeedPostTransferBurn IS burn["speedAfter"].
    LOCAL deltaV1 IS burn["prograde"].
    LOCAL deltaVRadial IS burn["radial"].

    PRINT "r_1: " + distanceToString(r_1, 4).
    PRINT "r_2: " + distanceToString(r_2, 4).
    PRINT "Current SMA: " + distanceToString(currentSMA, 4).
    PRINT "Transfer SMA: " + distanceToString(transferSMA, 4).
    PRINT "Orbital Speed Pre Transfer Burn Measured: " + distanceToString(orbitalSpeedPreTransferBurnMeasured, 4) + "/s".
    PRINT "Orbital Speed Pre Transfer Burn Calc'd: " + distanceToString(orbitalSpeedPreTransferBurn, 4) + "/s".
    PRINT "Orbital Speed Post Transfer Burn: " + distanceToString(orbitalSpeedPostTransferBurn, 4) + "/s".
    PRINT "Transfer Burn Delta V (prograde): " + distanceToString(deltaV1, 4) + "/s".
    PRINT "Transfer Burn Delta V (radial): " + distanceToString(deltaVRadial, 4) + "/s".

    IF connectionToKSC() {
      LOCAL fileName IS "0:Hohmann Transfers.csv".
      LOG "TIME:SECONDS," + TIME:SECONDS + ",s" TO fileName.
      LOG "ETA:PERIAPSIS," + ETA:PERIAPSIS + ",s" TO fileName.
      LOG "ETA:APOAPSIS," + ETA:APOAPSIS + ",s" TO fileName.
      LOG "nodeTime," + nodeTime + ",s" TO fileName.
      LOG "r_1," + r_1 + ",m" TO fileName.
      LOG "r_2," + r_2 + ",m" TO fileName.
      LOG "Body mu," + mu + ",m^3/s^2" TO fileName.
      LOG "Current Ship True Anomaly," + ORBIT:TRUEANOMALY + ",deg" TO fileName.
      IF transferToTarget LOG "Current Target True Anomaly," + TARGET:ORBIT:TRUEANOMALY + ",deg" TO fileName.
      LOG "Current SMA," + currentSMA + ",m" TO fileName.
      LOG "Transfer SMA," + transferSMA + ",m" TO fileName.
      LOG "Orbital Speed Pre Transfer Burn Measured," + orbitalSpeedPreTransferBurnMeasured + ",m/s" TO fileName.
      LOG "Orbital Speed Pre Transfer Burn Calc'd," + orbitalSpeedPreTransferBurn + ",m/s" TO fileName.
      LOG "Orbital Speed Post Transfer Burn," + orbitalSpeedPostTransferBurn + ",m/s" TO fileName.
      LOG "Transfer Burn Delta V (prograde)," + deltaV1 + ",m/s" TO fileName.
      LOG "Transfer Burn Delta V (radial)," + deltaVRadial + ",m/s" TO fileName.
      LOG "" TO fileName.
    }

    ADD NODE(nodeTime, deltaVRadial, 0, deltaV1).

    SET loopMessage TO "Node created for Hohmann transfer".
  }
}

IF errorCode <> "None" {
  SET loopMessage TO errorCode.
}

