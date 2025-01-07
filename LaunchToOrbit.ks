@LAZYGLOBAL OFF.
PARAMETER targetAltitude.
PARAMETER targetInclinationParameter IS SHIP:GEOPOSITION:LAT.
PARAMETER targetLAN IS SHIP:GEOPOSITION:LNG.

CLEARSCREEN.

LOCAL tempChar IS "".
LOCAL deltaLAN IS 0.
LOCAL deltaLANPlus IS 0.
LOCAL deltaLANMinus IS 0.
LOCAL inclinationOffset IS 0.
LOCAL targetInclination IS targetInclinationParameter.
UNTIL (tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE) {
  IF (SHIP:GEOPOSITION:LAT = 0) OR (targetInclinationParameter = 90) SET inclinationOffset TO 0.
  ELSE IF (targetInclinationParameter < SHIP:GEOPOSITION:LAT) SET inclinationOffset TO 90.
  ELSE SET inclinationOffset TO ARCSIN( TAN(SHIP:GEOPOSITION:LAT) / TAN(targetInclinationParameter)).
  SET deltaLANPlus  TO normalizeAngle(      targetLAN - SHIP:GEOPOSITION:LNG - SHIP:BODY:ROTATIONANGLE + inclinationOffset).
  SET deltaLANMinus TO normalizeAngle(180 + targetLAN - SHIP:GEOPOSITION:LNG - SHIP:BODY:ROTATIONANGLE - inclinationOffset).
  CLEARSCREEN.
  IF deltaLANMinus < deltaLANPlus {
    SET deltaLAN TO deltaLANMinus.
    SET targetInclination TO -targetInclinationParameter.
  } ELSE {
    SET deltaLAN TO deltaLANPlus.
  }
  PRINT "Ship Latitude: " + ROUND(SHIP:GEOPOSITION:LAT, 3) + " deg".
  PRINT "Ship Longitude: " + ROUND(SHIP:GEOPOSITION:LNG, 3) + " deg".
  PRINT "Rotation Angle: " + ROUND(SHIP:BODY:ROTATIONANGLE, 3) + " deg".
  PRINT "Desired longitude of ascending node " + ROUND(targetLAN, 3) + " deg".
  PRINT "Current longitude of ascending node " + ROUND(SHIP:GEOPOSITION:LNG + inclinationOffset, 3) + " deg".
  PRINT "Desired inclination " + ROUND(targetInclination, 3) + " deg".
  PRINT "Delta LAN Offset " + ROUND(inclinationOffset, 3) + " deg".
  PRINT "Delta LAN " + ROUND(deltaLAN, 3) + " deg".
  PRINT "Delta LAN Plus " + ROUND(deltaLANPlus, 3) + " deg".
  PRINT "Delta LAN Minus " + ROUND(deltaLANMinus, 3) + " deg".
  PRINT "Will need to wait for " + timeToString(deltaLAN / 360 * SHIP:BODY:ROTATIONPERIOD, 0) + " to be lined up".
  PRINT "That corresponds to " + ROUND(deltaLAN / 360, 3) + " rotations of the planet".
  PRINT "Press ENTER to continue or backspace to abort launch".
  IF TERMINAL:INPUT:HASCHAR {
		SET tempChar TO TERMINAL:INPUT:GETCHAR().
	}
  WAIT 0.
}
IF tempChar = TERMINAL:INPUT:ENTER {
  PRINT "Now waiting until lined up correctly for launch".
  KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + deltaLAN / 360 * SHIP:BODY:ROTATIONPERIOD).
  WAIT 0.
  UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE = 1 {WAIT 0.}
  PRINT "Launching".
  WAIT 1.
  RUNPATH("gravturnlaunch", targetInclination, TRUE, 10, targetAltitude, TRUE, 2.5).
  SET loopMessage TO SHIP:NAME + " should be in parking orbit".
  SET loopMessage TO "INC Error: " + ROUND(SHIP:ORBIT:INCLINATION - targetInclination, 1) + " LAN Error " + ROUND(SHIP:ORBIT:LAN - targetLAN, 1) + " deg".
} ELSE IF tempChar = TERMINAL:INPUT:BACKSPACE {
  CLEARSCREEN.
  PRINT "Exiting.".
  WAIT 1.
  SET loopMessage TO "Launch to Orbit aborted".
}
