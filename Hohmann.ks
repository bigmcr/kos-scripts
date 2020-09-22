CLEARSCREEN.

// calculate and create nodes for a Hohmann transfer orbit to the specified altitude.
// Creates nodes for the initial transfer burn and the circularization burn.
PARAMETER finalAltitude.    // Final Altitude above sea level. Does NOT include BODY:RADIUS
PARAMETER acknowledge IS FALSE.

LOCAL errorCode IS "None".
IF (finalAltitude < SHIP:ORBIT:PERIAPSIS) AND (finalAltitude > SHIP:ORBIT:APOAPSIS) SET errorCode TO "Apo > Final Alt > Peri".
IF SHIP:ORBIT:TRANSITION <> "Final" SET errorCode TO "Transition occures!".

LOCAL r_1 IS BODY:POSITION:MAG.
LOCAL r_2 IS finalAltitude.

// If the final altitude is above the current orbit, set the burn to happen at the periapsis.
IF finalAltitude < SHIP:ORBIT:PERIAPSIS SET r_1 TO SHIP:ORBIT:APOAPSIS + SHIP:BODY:RADIUS.

// If the final altitude is below the current orbit, set the burn to happen at the apoapsis.
IF finalAltitude > SHIP:ORBIT:AOPAPSIS SET r_1 TO SHIP:ORBIT:PERIAPSIS + SHIP:BODY:RADIUS.

SET finalAltitude TO finalAltitude + BODY:RADIUS.

IF errorcode = "None" {
  LOCAL mu IS BODY:GM.
  LOCAL currentSMA IS SHIP:ORBIT:SMA.
  LOCAL transferSMA IS (r_1 + r_2) / 2.
  LOCAL orbitalSpeedPostTransferBurn IS SQRT((mu/r_2)*(1 - sqrt(2*r_1/(r_1+r_2)))).
  LOCAL deltaV1 IS VELOCITY:ORBIT:MAG - orbitalSpeedPostTransferBurn.

  PRINT "r_1: " + distanceToString(r_1, 4).
  PRINT "r_2: " + distanceToString(r_2, 4).
  PRINT "Current SMA: " + distanceToString(currentSMA, 4).
  PRINT "Transfer SMA: " + distanceToString(transferSMA, 4).
  PRINT "Orbital Speed Pre Transfer Burn: " + distanceToString(VELOCITY:ORBIT:MAG, 4) + "/s".
  PRINT "Orbital Speed Post Transfer Burn: " + distanceToString(orbitalSpeedPostTransferBurn, 4) + "/s".
  PRINT "Transfer Burn Delta V: " + distanceToString(deltaV1, 4) + "/s".

} ELSE {
  SET loopMessage TO errorCode.
}
