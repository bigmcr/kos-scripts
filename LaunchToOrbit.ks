@LAZYGLOBAL OFF.
PARAMETER targetAltitude.
PARAMETER targetInclination IS SHIP:GEOPOSITION:LAT.
PARAMETER LAN IS SHIP:GEOPOSITION:LNG.
PARAMETER showVectors IS FALSE.

CLEARSCREEN.

LOCAL tempChar IS "".
LOCAL deltaLAN IS 0.
LOCAL deltaLAN_pos IS 0.
LOCAL deltaLAN_neg IS 0.
LOCAL inclinationOffset IS 0.
LOCAL timerStart IS 0.
LOCAL fudgeFactor IS 0.7*SIN(targetInclination).
LOCAL x_pos IS 0.
LOCAL x_neg IS 0.
LOCAL y_pos IS 0.
LOCAL y_neg IS 0.
LOCAL angle_pos IS 0.
LOCAL angle_neg IS 0.
LOCAL LAT IS SHIP:GEOPOSITION:LAT.
LOCAL LONG IS SHIP:GEOPOSITION:LNG.
LOCAL i_t IS targetInclination.
LOCAL launchN_pos IS FALSE.
LOCAL launchN_neg IS FALSE.
LOCAL useAlternate IS ABS(COS(LAN)) >= 0.1.

LOCAL northV IS 0.
LOCK northV TO -BODY:ANGULARVEL:NORMALIZED.
LOCAL radius IS BODY:RADIUS * 3.0.

LOCAL vecDraws IS LEXICON().

vecDraws:ADD("LAN",          VECDRAW(V(0,0,0), V(0,0,0),    BLUE, "Target LAN"     , 1.0, showVectors, 0.2, FALSE)).
SET vecDraws["LAN"]:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET vecDraws["LAN"]:VECUPDATER TO {RETURN radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-LAN, northV)):NORMALIZED.}.

vecDraws:ADD("LaunchSite",   VECDRAW(V(0,0,0), V(0,0,0),   WHITE, "Launch Site"  	 , 1.0, showVectors, 0.2, FALSE)).
SET vecDraws["LaunchSite"]:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET vecDraws["LaunchSite"]:VECUPDATER TO {RETURN radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-LONG - BODY:ROTATIONANGLE, northV)):NORMALIZED.}.

vecDraws:ADD("SolarPrime",   VECDRAW(V(0,0,0), V(0,0,0),     RED, "Solar Prime"  	 , 1.0, showVectors, 0.2, FALSE)).
SET vecDraws["SolarPrime"]:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET vecDraws["SolarPrime"]:VECUPDATER TO {RETURN radius * SOLARPRIMEVECTOR.}.

vecDraws:ADD("LaunchPos",    VECDRAW(V(0,0,0), V(0,0,0),   GREEN, "Launch Positive", 1.0, showVectors, 0.2, FALSE)).
SET vecDraws["LaunchPos"]:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET vecDraws["LaunchPos"]:VECUPDATER TO {RETURN radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-angle_pos, northV)):NORMALIZED.}.

vecDraws:ADD("LaunchNeg",    VECDRAW(V(0,0,0), V(0,0,0), MAGENTA, "Launch Negative", 1.0, showVectors, 0.2, FALSE)).
SET vecDraws["LaunchNeg"]:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET vecDraws["LaunchNeg"]:VECUPDATER TO {RETURN radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-angle_neg, northV)):NORMALIZED.}.

vecDraws:ADD("TargetNormal", VECDRAW(V(0,0,0), V(0,0,0),  YELLOW, "Target Normal"  , 1.0, showVectors, 0.2, FALSE)).
SET vecDraws["TargetNormal"]:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET vecDraws["TargetNormal"]:VECUPDATER TO {RETURN radius * (northV * ANGLEAXIS(-i_t, SOLARPRIMEVECTOR)):NORMALIZED * ANGLEAXIS(-LAN, northV).}.

IF (ABS(targetInclination) < ABS(SHIP:GEOPOSITION:LAT)) AND (timerStart = 0) AND (targetInclination <> 0) {
  SET timerStart TO TIME:SECONDS.
  PRINT "Launch site is too far from the equator to launch to that inclination.".
  PRINT "You cannot directly launch into that orbit from this launch site.".
  UNTIL TIME:SECONDS > timerStart + 10 {
    PRINT "Waiting " + ROUND(timerStart + 10 - TIME:SECONDS, 0) + " seconds, then aborting launch.  " AT (0, 2).
    WAIT 0.
  }
  SET tempChar TO TERMINAL:INPUT:BACKSPACE.
}

UNTIL (tempChar = TERMINAL:INPUT:ENTER OR     // accept the closest of the two solutions
       tempChar = TERMINAL:INPUT:BACKSPACE OR // abort launch
       tempChar = "+" OR                      // go with the positive solution
       tempChar = "-") {                      // go with the negative solution
  CLEARSCREEN.

  // These equations come from setting the equation of a plane equal to the
  //    equation of a circle and finding the two locations that they match each
  //    other. The result of those equations is a quadratic, and the two
  //    solutions of the quadratic are the positive and negative solutions.
  // The reason for useAlternate is because depending on if you solve for x or y
  //    first, you end up with either a SIN(LAN) or a COS(LAN) on the bottom of
  //    a fraction. Dividing by too small of a number is bad, so if the bottom
  //    is less than 0.1, the system uses the alternate version of the equations.
  //    Note that using the alternate version of the equations results in the
  //    same answers, but the values of the positive and negative solutions are
  //    swapped.
  IF useAlternate {
    SET y_pos TO -(sin(LAN)*(cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - sin(LAN)*sin(LAT)*cos(i_t)) + sin(LAT)*cos(i_t))/(cos(LAN)*sin(i_t)).
    SET x_pos TO  (cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - sin(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
  } ELSE {
    SET y_pos TO  (sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - cos(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
    SET x_pos TO -(cos(LAN)*(sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - cos(LAN)*sin(LAT)*cos(i_t)) + sin(LAT)*cos(i_t))/(sin(LAN)*sin(i_t)).
  }
  SET angle_pos TO -normalizeAngle360(ARCTAN2(y_pos, x_pos)) - fudgeFactor.
  SET deltaLAN_pos TO normalizeAngle360(angle_pos - LONG - BODY:ROTATIONANGLE).
  SET launchN_pos TO (ABS(normalizeAngle180(angle_pos - LAN)) < 90).

  IF useAlternate {
    SET x_neg TO -(cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + sin(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
    SET y_neg TO (sin(LAN)*(cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + sin(LAN)*sin(LAT)*cos(i_t)) - sin(LAT)*cos(i_t))/(cos(LAN)*sin(i_t)).
  } ELSE {
    SET y_neg TO -(sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + cos(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
    SET x_neg TO  (cos(LAN)*(sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + cos(LAN)*sin(LAT)*cos(i_t)) - sin(LAT)*cos(i_t))/(sin(LAN)*sin(i_t)).
  }
  SET angle_neg TO -normalizeAngle360(ARCTAN2(y_neg, x_neg)) - fudgeFactor.
  SET deltaLAN_neg TO normalizeAngle360(angle_neg - LONG - BODY:ROTATIONANGLE).
  SET launchN_neg TO (ABS(normalizeAngle180(angle_neg - LAN)) < 90).

  PRINT "Target Inclination:     " + ROUND(i_t, 3) + " deg".
  PRINT "Ship Latitude:          " + ROUND(LAT, 3) + " deg".
  PRINT "Ship Longitude:         " + ROUND(LONG, 3) + " deg".
  PRINT "Rotation Angle:         " + ROUND(BODY:ROTATIONANGLE, 3) + " deg".
  PRINT "Desired LAN:            " + ROUND(LAN, 3) + " deg".
  PRINT "Alternate Calcs Active: " + useAlternate.
  PRINT "Fudge Factor:           " + ROUND(fudgeFactor, 3) + " deg".

  PRINT " ".
  PRINT "                 Positive    Negative     Units".
  PRINT "X Coord          " + ROUND(x_pos, 6):TOSTRING:PADRIGHT(12) + ROUND(x_neg, 6):TOSTRING:PADRIGHT(12) + " ".
  PRINT "Y Coord          " + ROUND(y_pos, 6):TOSTRING:PADRIGHT(12) + ROUND(y_neg, 6):TOSTRING:PADRIGHT(12) + " ".
  PRINT "Angle            " + ROUND(angle_pos, 6):TOSTRING:PADRIGHT(12) + ROUND(angle_neg, 6):TOSTRING:PADRIGHT(12) + " deg".
  PRINT "Delta LAN        " + ROUND(deltaLAN_pos, 3):TOSTRING:PADRIGHT(12) + ROUND(deltaLAN_neg, 3):TOSTRING:PADRIGHT(12) + " deg".
  PRINT "Launch Direction " + (CHOOSE "North" IF launchN_pos ELSE "South") + "       " + (CHOOSE "North" IF launchN_neg ELSE "South").
  PRINT "Wait Time        " + timeToString(deltaLAN_pos / 360 * BODY:ROTATIONPERIOD, 0):PADRIGHT(12) + timeToString(deltaLAN_neg / 360 * BODY:ROTATIONPERIOD, 0):PADRIGHT(12).
  PRINT "Local Day        " + ROUND(deltaLAN_pos / 360, 3):TOSTRING:PADRIGHT(12) + ROUND(deltaLAN_neg / 360, 3):TOSTRING:PADRIGHT(12) + " local days".
  PRINT " ".
  PRINT "Press ENTER to accept the first launch chance.".
  PRINT "Press + to accept the positive solution.".
  PRINT "Press - to accept the negative solution.".
  PRINT "Press 4 to toggle between the different calculation methods.".
  PRINT "Press 5 to toggle arrows showing the various angles.".
  PRINT "Press 7 to lower the fudge factor by 0.1 degrees.".
  PRINT "Press 8 to set the fudge factor to 0 degrees.".
  PRINT "Press 9 to raise the fudge factor by 0.1 degrees.".
  PRINT "Press backspace to abort launch".

  IF TERMINAL:INPUT:HASCHAR {
		SET tempChar TO TERMINAL:INPUT:GETCHAR().
    IF tempChar = "5" {
      FOR eachKey IN vecDraws:KEYS SET vecDraws[eachKey]:SHOW TO NOT vecDraws[eachKey]:SHOW.
      SET tempChar TO "".
    }
    IF tempChar = "4" {
      SET useAlternate TO NOT useAlternate.
      SET tempChar TO "".
    }
    IF tempChar = "7" {
      SET fudgeFactor TO fudgeFactor - 0.1.
      SET tempChar TO "".
    }
    IF tempChar = "8" {
      SET fudgeFactor TO 0.
      SET tempChar TO "".
    }
    IF tempChar = "9" {
      SET fudgeFactor TO fudgeFactor + 0.1.
      SET tempChar TO "".
    }
	}
  WAIT 0.
}
IF tempChar = "+" {
  SET deltaLAN TO deltaLAN_pos.
  SET tempChar TO "Launch".
}
IF tempChar = "-" {
  SET deltaLAN TO deltaLAN_neg.
  SET tempChar TO "Launch".
}
IF tempChar = TERMINAL:INPUT:ENTER {
  IF deltaLAN_neg < deltaLAN_pos SET deltaLAN TO deltaLAN_neg.
  ELSE SET deltaLAN TO deltaLAN_pos.
  SET tempChar TO "Launch".
}
IF tempChar = "Launch" {
  FOR eachKey IN vecDraws:KEYS {
    SET vecDraws[eachKey]:SHOW TO FALSE.
  }
  IF (deltaLAN = deltaLAN_pos AND NOT launchN_pos) OR
     (deltaLAN = deltaLAN_neg AND NOT launchN_neg)
  {
    SET i_t TO -i_t.
    PRINT "Launching Southerly".
  } ELSE PRINT "Launching Northerly".
  PRINT "Now waiting until lined up correctly for launch".
  LOCAL launchTime IS TIME:SECONDS + deltaLAN / 360 * BODY:ROTATIONPERIOD.
  // The reason for the loop is because if the timewarp is interrupted, it should auto-resume.
  UNTIL TIME:SECONDS >= launchTime {
    KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + deltaLAN / 360 * BODY:ROTATIONPERIOD).
  }
  WAIT 0.
  UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE = 1 {WAIT 0.}
  WAIT 1.
  PRINT "Launching".
  WAIT 1.
  RUNPATH("gravturnlaunch", i_t, TRUE, 10, targetAltitude, TRUE, 2.5).
  SET loopMessage TO SHIP:NAME + " should be in parking orbit".
  SET loopMessage TO "INC Error: " + ROUND(normalizeAngle180(SHIP:ORBIT:INCLINATION - targetInclination), 1) + " LAN Error " + ROUND(normalizeAngle180(SHIP:ORBIT:LAN - LAN), 1) + " deg".
} ELSE IF tempChar = TERMINAL:INPUT:BACKSPACE {
  CLEARSCREEN.
  SET loopMessage TO "Launch to Orbit aborted".
}
