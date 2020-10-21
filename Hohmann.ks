@LAZYGLOBAL OFF.
CLEARSCREEN.

FUNCTION phaseAngleOfOrbits {
  PARAMETER orbit1.
  PARAMETER orbit2.
  PARAMETER timeFromNow IS 0.

  LOCAL shipEcc IS orbit1:ECCENTRICITY.
  LOCAL targetEcc IS orbit2:ECCENTRICITY.

  LOCAL shipTrueAnomaly IS orbit1:LAN + orbit1:ARGUMENTOFPERIAPSIS + orbit1:TRUEANOMALY.
  LOCAL targetTrueAnomaly IS orbit2:LAN + orbit2:ARGUMENTOFPERIAPSIS + orbit2:TRUEANOMALY.

  LOCAL shipMeanAnomaly IS trueToMeanAnomaly(shipTrueAnomaly, shipEcc).
  LOCAL targetMeanAnomaly IS trueToMeanAnomaly(targetTrueAnomaly, targetEcc).

  LOCAL shipMeanMotion IS 360.0 / orbit1:PERIOD.
  LOCAL targetMeanMotion IS 360.0 / orbit1:PERIOD.

  LOCAL shipFinalMeanAnomaly IS shipMeanAnomaly + timeFromNow * shipMeanMotion.
  LOCAL targetFinalMeanAnomaly IS targetMeanAnomaly + timeFromNow * targetMeanMotion.

  LOCAL shipFinalTrueAnomaly IS meanToTrueAnomaly(shipFinalMeanAnomaly, shipEcc).
  LOCAL targetFinalTrueAnomaly IS meanToTrueAnomaly(targetFinalMeanAnomaly, targetEcc).

  LOCAL relativePhase IS (targetFinalTrueAnomaly - shipFinalTrueAnomaly) - 360 * floor((targetFinalTrueAnomaly - shipFinalTrueAnomaly)/360).

  RETURN relativePhase.
}

// calculate and create nodes for a Hohmann transfer orbit to the specified altitude.
// Creates nodes for the initial transfer burn only.
PARAMETER finalAltitude.    // Final Altitude above sea level. Does NOT include BODY:RADIUS
PARAMETER acknowledge IS FALSE.

LOCAL transferToTarget IS (finalAltitude:TYPENAME = "String" AND (finalAltitude = "target" OR finalAltitude = "tar")) AND HASTARGET.

IF transferToTarget SET finalAltitude TO TARGET:ORBIT:SEMIMAJORAXIS - TARGET:BODY:RADIUS.
ELSE SET finalAltitude TO processScalarParameter(finalAltitude, BODY:POSITION:MAG).

LOCAL errorCode IS "None".
IF (finalAltitude < SHIP:ORBIT:PERIAPSIS) AND (finalAltitude > SHIP:ORBIT:APOAPSIS) SET errorCode TO "Apo > Final Alt > Peri".
IF SHIP:ORBIT:TRANSITION <> "Final" SET errorCode TO "Transition occures!".

IF errorcode = "None" {
  LOCAL r_1 IS BODY:POSITION:MAG.
  LOCAL r_2 IS finalAltitude + BODY:RADIUS.
  LOCAL nodeTime IS TIME:SECONDS + 60.

  // If the final altitude is above the current orbit, set the burn to happen at the periapsis.
  IF NOT transferToTarget AND finalAltitude < SHIP:ORBIT:PERIAPSIS {
    SET nodeTime TO TIME:SECONDS + ETA:PERIAPSIS.
    SET r_1 TO SHIP:ORBIT:PERIAPSIS + SHIP:BODY:RADIUS.
  }

  // If the final altitude is below the current orbit, set the burn to happen at the apoapsis.
  IF NOT transferToTarget AND finalAltitude > SHIP:ORBIT:APOAPSIS {
    SET nodeTime TO TIME:SECONDS + ETA:APOAPSIS.
    SET r_1 TO SHIP:ORBIT:APOAPSIS + SHIP:BODY:RADIUS.
  }

  LOCAL mu IS BODY:MU.
  LOCAL currentSMA IS SHIP:ORBIT:SEMIMAJORAXIS.
  LOCAL transferSMA IS (r_1 + r_2) / 2.
  LOCAL orbitalSpeedPreTransferBurn IS SQRT(mu * (2/r_1 - 1 / currentSMA)).
  LOCAL orbitalSpeedPostTransferBurn IS SQRT(mu * (2/r_1 - 1 / transferSMA)).
  LOCAL deltaV1 IS orbitalSpeedPostTransferBurn - VELOCITY:ORBIT:MAG.
  LOCAL currentSpeed IS VELOCITYAT(SHIP, nodeTime):ORBIT:MAG.

  LOCAL relativePhase IS 0.
  LOCAL desiredPhase IS (180.0 * (1-sqrt(((r_1/r_2 + 1)^3)/8))).
  PRINT "Desired phase: " + ROUND(desiredPhase, 4) AT (0, 3).

  // If we are transferring to the target, set the burn to happen at the appropriate phase angle
  IF transferToTarget {
    LOCAL smallerPeriod IS MIN(SHIP:ORBIT:PERIOD, TARGET:ORBIT:PERIOD).

    LOCAL bestYetTime IS SHIP:ORBIT:PERIOD.
    LOCAL bestYetPhase IS 360.

    SET desiredPhase TO (180.0 * (1-sqrt(((r_1/r_2 + 1)^3)/8))).
    FROM {LOCAL timeGuess IS 0.} UNTIL timeGuess > 1.02 STEP {SET timeGuess TO timeGuess + 0.2.} DO {
      SET relativePhase TO phaseAngleOfOrbits(SHIP:ORBIT, TARGET:ORBIT, timeGuess * smallerPeriod).
      IF ABS( desiredPhase - relativePhase) < bestYetPhase {
        SET bestYetTime TO timeGuess.
        SET bestYetPhase TO ABS( desiredPhase - relativePhase).
      }
    }
    SET r_1 TO (POSITIONAT(SHIP, TIME:SECONDS + bestYetTime * smallerPeriod) - SHIP:BODY:POSITION):MAG.
    SET desiredPhase TO (180.0 * (1-sqrt(((r_1/r_2 + 1)^3)/8))).

    LOCAL bestYetTime2 IS SHIP:ORBIT:PERIOD.
    LOCAL bestYetPhase2 IS 360.
    FROM {LOCAL timeGuess IS bestYetTime - 0.2.} UNTIL timeGuess > bestYetTime + 0.2 STEP {SET timeGuess TO timeGuess + 0.025.} DO {
      SET relativePhase TO phaseAngleOfOrbits(SHIP:ORBIT, TARGET:ORBIT, timeGuess * smallerPeriod).
      IF ABS( desiredPhase - relativePhase) < bestYetPhase2 {
        SET bestYetTime2 TO timeGuess.
        SET bestYetPhase2 TO ABS( desiredPhase - relativePhase).
      }
    }
    SET r_1 TO (POSITIONAT(SHIP, TIME:SECONDS + bestYetTime2 * smallerPeriod) - SHIP:BODY:POSITION):MAG.
    SET desiredPhase TO (180.0 * (1-sqrt(((r_1/r_2 + 1)^3)/8))).

    LOCAL bestYetTime3 IS SHIP:ORBIT:PERIOD.
    LOCAL bestYetPhase3 IS 360.
    FROM {LOCAL timeGuess IS bestYetTime2 - 0.025.} UNTIL timeGuess > bestYetTime2 + 0.025 STEP {SET timeGuess TO timeGuess + 0.001.} DO {
      SET relativePhase TO phaseAngleOfOrbits(SHIP:ORBIT, TARGET:ORBIT, timeGuess * smallerPeriod).
      IF ABS( desiredPhase - relativePhase) < bestYetPhase3 {
        SET bestYetTime3 TO timeGuess.
        SET bestYetPhase3 TO ABS( desiredPhase - relativePhase).
      }
    }
    SET r_1 TO (POSITIONAT(SHIP, TIME:SECONDS + bestYetTime3 * smallerPeriod) - SHIP:BODY:POSITION):MAG.
    SET desiredPhase TO (180.0 * (1-sqrt(((r_1/r_2 + 1)^3)/8))).

    SET nodeTime TO TIME:SECONDS + bestYetTime3 * smallerPeriod.
  }

  PRINT "r_1: " + distanceToString(r_1, 4).
  PRINT "r_2: " + distanceToString(r_2, 4).
  PRINT "Current SMA: " + distanceToString(currentSMA, 4).
  PRINT "Transfer SMA: " + distanceToString(transferSMA, 4).
  PRINT "Orbital Speed Pre Transfer Burn Measured: " + distanceToString(currentSpeed, 4) + "/s".
  PRINT "Orbital Speed Pre Transfer Burn Calc'd: " + distanceToString(orbitalSpeedPreTransferBurn, 4) + "/s".
  PRINT "Orbital Speed Post Transfer Burn: " + distanceToString(orbitalSpeedPostTransferBurn, 4) + "/s".
  PRINT "Transfer Burn Delta V: " + distanceToString(deltaV1, 4) + "/s".

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
    IF transferToTarget LOG "Current Target True Anomaly," + TARGET:ORBIT:TRUEANOMALY +",deg" TO fileName.
    LOG "Desired phase," + desiredPhase +",deg" TO fileName.
    LOG "Current SMA," + currentSMA + ",m" TO fileName.
    LOG "Transfer SMA," + transferSMA + ",m" TO fileName.
    LOG "Orbital Speed Pre Transfer Burn Measured," + currentSpeed + ",m/s" TO fileName.
    LOG "Orbital Speed Pre Transfer Burn Calc'd," + orbitalSpeedPreTransferBurn + ",m/s" TO fileName.
    LOG "Orbital Speed Post Transfer Burn," + orbitalSpeedPostTransferBurn + ",m/s" TO fileName.
    LOG "Transfer Burn Delta V," + deltaV1 + ",m/s" TO fileName.
    LOG "" TO fileName.

  }

  ADD NODE( nodeTime, 0, 0, deltaV1).

  SET loopMessage TO "Node created for Hohmann transfer".
} ELSE {
  SET loopMessage TO errorCode.
}
