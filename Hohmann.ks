CLEARSCREEN.

// calculate and create nodes for a Hohmann transfer orbit to the specified altitude.
// Creates nodes for the initial transfer burn and the circularization burn.
PARAMETER finalAltitude.    // Final Altitude above sea level. Does NOT include BODY:RADIUS
PARAMETER acknowledge IS FALSE.

IF (finalAltitude:TYPENAME = "String" AND (finalAltitude = "target" OR finalAltitude = "tar") AND HASTARGET SET finalAltitude TO TARGET:ORBIT:SEMIMAJORAXIS - TARGET:BODY:RADIUS.
ELSE SET finalAltitude TO processScalarParameter(finalAltitude, BODY:POSITION:MAG).

LOCAL errorCode IS "None".
IF (finalAltitude < SHIP:ORBIT:PERIAPSIS) AND (finalAltitude > SHIP:ORBIT:APOAPSIS) SET errorCode TO "Apo > Final Alt > Peri".
IF SHIP:ORBIT:TRANSITION <> "Final" SET errorCode TO "Transition occures!".

IF errorcode = "None" {
  LOCAL r_1 IS BODY:POSITION:MAG.
  LOCAL r_2 IS finalAltitude + BODY:RADIUS.
  LOCAL nodeTime IS TIME:SECONDS + 60.

  // If the final altitude is above the current orbit, set the burn to happen at the periapsis.
  IF finalAltitude < SHIP:ORBIT:PERIAPSIS {
    SET nodeTime TO TIME:SECONDS + ETA:PERIAPSIS.
    SET r_1 TO SHIP:ORBIT:PERIAPSIS + SHIP:BODY:RADIUS.
  }

  // If the final altitude is below the current orbit, set the burn to happen at the apoapsis.
  IF finalAltitude > SHIP:ORBIT:APOAPSIS {
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
    LOG "Body radius," + BODY:RADIUS + ",m" TO fileName.
    LOG "Current SMA," + currentSMA + ",m" TO fileName.
    LOG "Transfer SMA," + transferSMA + ",m" TO fileName.
    LOG "Orbital Speed Pre Transfer Burn Measured," + currentSpeed + ",m/s" TO fileName.
    LOG "Orbital Speed Pre Transfer Burn Calc'd," + orbitalSpeedPreTransferBurn + ",m/s" TO fileName.
    LOG "Orbital Speed Post Transfer Burn," + orbitalSpeedPostTransferBurn + ",m/s" TO fileName.
    LOG "Transfer Burn Delta V," + deltaV1 + ",m/s" TO fileName.
    LOG "" TO fileName.

  }
  LOCAL transferNode to NODE( nodeTime, 0, 0, deltaV1).
  ADD transferNode.

} ELSE {
  SET loopMessage TO errorCode.
}
