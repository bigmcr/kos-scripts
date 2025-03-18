@LAZYGLOBAL OFF.
PARAMETER targetInclination IS 0.
PARAMETER targetLAN IS 0.
PARAMETER showVectors IS FALSE.

CLEARSCREEN.

// if either the inclination or the target LAN are non-default, proceed to the
// calculations
IF (targetInclination <> 0) OR (targetLAN <> 0) {

  // This function calculates how long to wait until the given Lat/Long position
  // on a given body is in the target orbital plane.
  // It is intended to be used for waiting until the launch window is open.
  // Passed the following
  //			Inclination of desired orbit (scalar, degrees)
  //      Longitude of the ascending node or desired orbit (scalar, degrees)
  //      Offset (scalar, degrees, it will rotate until this many degrees early)
  //      Body being launched from (BODY, defaults to SHIP:BODY)
  //      Longitude on that body to observe (scalar, degrees)
  //      Latitude on that body to observe (scalar, degrees)
  // Returns a lexicon of the following:
  //			"positive" (LEXICON, with data types of Solution)
  //			"negative" (LEXICON, with data types of Solution)
  //			"closest" (LEXICON, with data types of Solution)
  //      each argument passed to it (see above)
  //      "error" (string) states the error encountered, or "None"
  //      "useAlternate" (boolean, TRUE if using alternate formulae)
  //
  //      Each lexicon called out with Solutions has the following data points
  //        "angle" (scalar, degrees) angle between the solar prime vector and the desired launch site.
  //        "longitude", (scalar, degrees) longitude of the point on the body under this solution at the current time.
  //        "deltaLAN" (scalar, degrees) angle between the current launch site location and the desired orbital plane.
  //        "launchN" (boolean) TRUE if the rocket should launch north at the given time.
  //        "waitTime" (scalar, seconds) number of seconds to wait for the given location to be in the desired orbital plane
  //        "waitTimeDays" (scalar, days) number of rotations of the selected BODY until the launch site is in the desired orbital plane.
  FUNCTION launchWindowTimes {
    PARAMETER i_t.
    PARAMETER LAN.
    PARAMETER offset IS 0.7*SIN(i_t).
    PARAMETER launchBody IS SHIP:BODY.
    PARAMETER LNG IS SHIP:GEOPOSITION:LNG.
    PARAMETER LAT IS SHIP:GEOPOSITION:LAT.

    // Note that the coordinate system this assumes is X along the SOLARPRIMEVECTOR,
    //    Z in the direction of the rotation of the planet ("north", in normal terminology)
    //    and Y as the cross product of those two things ("east", in normal terminology).
    //    Given that coordinate system, a launch site will move in a circle with a
    //    constant distance from the equator each day, and will have 0, 1 or 2
    //    launch windows to hit the target orbital plane, depending on the relative
    //    values of the inclination and the latitude of the launch site.
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

    LOCAL deltaLAN_pos IS 0.
    LOCAL deltaLAN_neg IS 0.
    LOCAL x_pos IS 0.
    LOCAL x_neg IS 0.
    LOCAL y_pos IS 0.
    LOCAL y_neg IS 0.
    LOCAL angle_pos IS 0.
    LOCAL angle_neg IS 0.
    LOCAL launchN_pos IS FALSE.
    LOCAL launchN_neg IS FALSE.
    LOCAL useAlternate IS ABS(COS(LAN)) >= 0.1.
    LOCAL error IS "None".
    LOCAL solutionType IS "None".
    IF (ABS(i_t) < ABS(LAT)) AND (i_t <> 0) SET error TO "Inclination too low for launch site".
    IF (error = "None") AND (i_t <> 0) AND ABS(LAT - i_t) >= 0.1 {
      IF useAlternate {
        SET y_pos TO -(sin(LAN)*(cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - sin(LAN)*sin(LAT)*cos(i_t)) + sin(LAT)*cos(i_t))/(cos(LAN)*sin(i_t)).
        SET x_pos TO  (cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - sin(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
      } ELSE {
        SET y_pos TO  (sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - cos(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
        SET x_pos TO -(cos(LAN)*(sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) - cos(LAN)*sin(LAT)*cos(i_t)) + sin(LAT)*cos(i_t))/(sin(LAN)*sin(i_t)).
      }
      SET angle_pos TO normalizeAngle360(-ARCTAN2(y_pos, x_pos) - offset).
      SET deltaLAN_pos TO normalizeAngle360(angle_pos - LNG - launchBody:ROTATIONANGLE).
      SET launchN_pos TO (ABS(normalizeAngle180(angle_pos - LAN)) < 90).

      IF useAlternate {
        SET y_neg TO  (sin(LAN)*(cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + sin(LAN)*sin(LAT)*cos(i_t)) - sin(LAT)*cos(i_t))/(cos(LAN)*sin(i_t)).
        SET x_neg TO -(cos(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + sin(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
      } ELSE {
        SET y_neg TO -(sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + cos(LAN)*sin(LAT)*cos(i_t))/sin(i_t).
        SET x_neg TO  (cos(LAN)*(sin(LAN)*sqrt(cos(LAT)^2 - cos(i_t)^2) + cos(LAN)*sin(LAT)*cos(i_t)) - sin(LAT)*cos(i_t))/(sin(LAN)*sin(i_t)).
      }
      SET angle_neg TO normalizeAngle360(-ARCTAN2(y_neg, x_neg) - offset).
      SET deltaLAN_neg TO normalizeAngle360(angle_neg - LNG - launchBody:ROTATIONANGLE).
      SET launchN_neg TO (ABS(normalizeAngle180(angle_neg - LAN)) < 90).

      SET solutionType TO "Double".
    } ELSE {  // something is non-standard
      SET solutionType TO "Non-standard".
      IF error <> "None" SET solutionType TO "Error".
      IF i_t = 0 { //target inclination is zero, so launch now.
        SET y_pos TO 0.
        SET x_pos TO 0.
        SET angle_pos TO LNG - launchBody:ROTATIONANGLE.
        SET deltaLAN_pos TO 0.
        SET launchN_pos TO (ABS(normalizeAngle180(angle_pos - LAN)) < 90).

        SET y_neg TO 0.
        SET x_neg TO 0.
        SET angle_neg TO LNG - launchBody:ROTATIONANGLE.
        SET deltaLAN_neg TO 0.
        SET launchN_neg TO (ABS(normalizeAngle180(angle_pos - LAN)) < 90).

        SET solutionType TO "Inclination is zero".
      }

      IF ABS(LAT - i_t) < 0.01 {
        // if the inclination is equal to the latitude of the launch
        // site, there will be only one fairly simple solution.
        SET x_pos TO -sin(LAN)*cos(i_t).
        SET y_pos TO -cos(LAN)*cos(i_t).
        SET angle_pos TO normalizeAngle360(-ARCTAN2(y_pos, x_pos) - offset).
        SET deltaLAN_pos TO normalizeAngle360(angle_pos - LNG - launchBody:ROTATIONANGLE).
        SET launchN_pos TO (ABS(normalizeAngle180(angle_pos - LAN)) < 90).

        SET y_neg TO y_pos.
        SET x_neg TO y_pos.
        SET angle_neg TO angle_pos.
        SET deltaLAN_neg TO deltaLAN_pos.
        SET launchN_neg TO launchN_pos.

        SET solutionType TO "Inclination equals latitude".
      }
    }


    LOCAL solution IS 0.
    LOCAL returnMe IS LEXICON().
    IF error = "None" {
      SET solution TO LEXICON().
      solution:ADD("angle", angle_pos).
      solution:ADD("longitude", angle_pos - launchBody:ROTATIONANGLE).
      solution:ADD("deltaLAN", deltaLAN_pos).
      solution:ADD("launchN", launchN_pos).
      solution:ADD("waitTime", deltaLAN_pos / 360 * launchBody:ROTATIONPERIOD).
      solution:ADD("waitTimeDays", deltaLAN_pos / 360).
      returnMe:ADD("positive", solution).

      SET solution TO LEXICON().
      solution:ADD("angle", angle_neg).
      solution:ADD("longitude", angle_neg - launchBody:ROTATIONANGLE).
      solution:ADD("deltaLAN", deltaLAN_neg).
      solution:ADD("launchN", launchN_neg).
      solution:ADD("waitTime", deltaLAN_neg / 360 * launchBody:ROTATIONPERIOD).
      solution:ADD("waitTimeDays", deltaLAN_neg / 360).
      returnMe:ADD("negative", solution).

      IF returnMe["negative"]["waitTime"] < returnMe["positive"]["waitTime"] returnMe:ADD("closest", returnMe["negative"]).
      ELSE returnMe:ADD("closest", returnMe["positive"]).

      IF ABS(normalizeAngle180(BODY:GEOPOSITIONOF(BODY("Sun"):POSITION):LNG - returnMe["positive"]["longitude"])) < 90 {
        returnMe:ADD("daylight", returnMe["positive"]).
      } ELSE {
        returnMe:ADD("daylight", returnMe["negative"]).
      }

    } ELSE {  // If there is an error, add a bunch of blank solutions. This
      //  that the references to soltions["positive"] for example are still valid.
      SET solution TO LEXICON().
      solution:ADD("angle", 0).
      solution:ADD("longitude", 0).
      solution:ADD("deltaLAN", 0).
      solution:ADD("launchN", 0).
      solution:ADD("waitTime", 0).
      solution:ADD("waitTimeDays", 0).

      returnMe:ADD("positive", solution).
      returnMe:ADD("negative", solution).
      returnMe:ADD("closest", solution).
    }

    returnMe:ADD("useAlternate", useAlternate).
    returnMe:ADD("Inclination", i_t).
    returnMe:ADD("LAN", LAN).
    returnMe:ADD("offset", offset).
    returnMe:ADD("launchBody", launchBody:NAME).
    returnMe:ADD("LNG", LNG).
    returnMe:ADD("LAT", LAT).
    returnMe:ADD("Error", error).
    returnMe:ADD("solutionType", solutionType).
    RETURN returnMe.
  }

  FUNCTION launchWindowVectorsUpdate {
    PARAMETER launchVecDraws.
    PARAMETER solutions.
    LOCAL localBody IS BODY(solutions["launchBody"]).
    LOCAL northV IS -localBody:ANGULARVEL:NORMALIZED.
    LOCAL radius IS localBody:RADIUS * 3.0.
    SET launchVecDraws["LAN"]:START TO localBody:POSITION.
    SET launchVecDraws["LAN"]:VEC TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-solutions["LAN"], northV)):NORMALIZED.
    SET launchVecDraws["LaunchSite"]:START TO localBody:POSITION.
    SET launchVecDraws["LaunchSite"]:VEC TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-solutions["LNG"] - localBody:ROTATIONANGLE, northV)):NORMALIZED.
    SET launchVecDraws["SolarPrime"]:START TO localBody:POSITION.
    SET launchVecDraws["SolarPrime"]:VEC TO radius * SOLARPRIMEVECTOR.
    SET launchVecDraws["LaunchPos"]:START TO localBody:POSITION.
    SET launchVecDraws["LaunchPos"]:VEC TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-solutions["positive"]["angle"], northV)):NORMALIZED.
    SET launchVecDraws["LaunchNeg"]:START TO localBody:POSITION.
    SET launchVecDraws["LaunchNeg"]:VEC TO radius * (SOLARPRIMEVECTOR * ANGLEAXIS(-solutions["negative"]["angle"], northV)):NORMALIZED.
    SET launchVecDraws["TargetNormal"]:START TO localBody:POSITION.
    SET launchVecDraws["TargetNormal"]:VEC TO radius * (northV * ANGLEAXIS(-solutions["Inclination"], SOLARPRIMEVECTOR)):NORMALIZED * ANGLEAXIS(-solutions["LAN"], northV).
  }

  FUNCTION launchWindowVectorsCreate {
    LOCAL launchVecDraws IS LEXICON().
    launchVecDraws:ADD("LAN",          VECDRAW(V(0,0,0), V(0,0,0),    BLUE, "Target LAN"     , 1.0, showVectors, 0.2, FALSE)).
    launchVecDraws:ADD("LaunchSite",   VECDRAW(V(0,0,0), V(0,0,0),   WHITE, "Launch Site"  	 , 1.0, showVectors, 0.2, FALSE)).
    launchVecDraws:ADD("SolarPrime",   VECDRAW(V(0,0,0), V(0,0,0),     RED, "Solar Prime"  	 , 1.0, showVectors, 0.2, FALSE)).
    launchVecDraws:ADD("LaunchPos",    VECDRAW(V(0,0,0), V(0,0,0),   GREEN, "Launch Positive", 1.0, showVectors, 0.2, FALSE)).
    launchVecDraws:ADD("LaunchNeg",    VECDRAW(V(0,0,0), V(0,0,0), MAGENTA, "Launch Negative", 1.0, showVectors, 0.2, FALSE)).
    launchVecDraws:ADD("TargetNormal", VECDRAW(V(0,0,0), V(0,0,0),  YELLOW, "Target Normal"  , 1.0, showVectors, 0.2, FALSE)).
    RETURN launchVecDraws.
  }

  LOCAL tempChar IS "".
  LOCAL deltaLAN IS 0.
  LOCAL timerStart IS TIME:SECONDS.
  LOCAL fudgeFactor IS 0.35*SIN(targetInclination).
  LOCAL finalLaunchDirectionIsNorth IS FALSE.
  LOCAL extendedView IS FALSE.
  LOCAL delayBeforeAuto IS 30.

  LOCAL vecDraws IS launchWindowVectorsCreate().

  LOCAL solutions IS 0.

  UNTIL (tempChar = TERMINAL:INPUT:ENTER OR     // accept the daylight solutions
         tempChar = TERMINAL:INPUT:BACKSPACE OR // abort launch
         tempChar = "+" OR                      // go with the positive solution
         tempChar = "-" OR                      // go with the negative solution
         tempChar = "C") {                      // go with the closest solution
    CLEARSCREEN.

    SET solutions TO launchWindowTimes(targetInclination, targetLAN, fudgeFactor).
    launchWindowVectorsUpdate(vecDraws, solutions).

    PRINT "Target Inclination:     " + ROUND(solutions["Inclination"], 3) + " deg".
    PRINT "Ship Latitude:          " + ROUND(solutions["LAT"], 3) + " deg".
    PRINT "Ship Longitude:         " + ROUND(solutions["LNG"], 3) + " deg".
    PRINT "Rotation Angle:         " + ROUND(BODY(solutions["launchBody"]):ROTATIONANGLE, 3) + " deg".
    PRINT "Desired LAN:            " + ROUND(solutions["LAN"], 3) + " deg".
    PRINT "Alternate Calcs Active: " + solutions["useAlternate"].
    PRINT "Fudge Factor:           " + ROUND(solutions["Offset"], 3) + " deg".
    PRINT "Error:                  " + solutions["Error"].
    PRINT "Solution type:          " + solutions["solutionType"].

    PRINT " ".
    PRINT "                 Positive    Negative    Closest     Daylight     Units".
    IF extendedView {
      PRINT "Angle            " + ROUND(solutions["positive"]["angle"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["negative"]["angle"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["closest"]["angle"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["daylight"]["angle"], 3):TOSTRING:PADRIGHT(12) + " deg".
      PRINT "Delta LAN        "  + ROUND(solutions["positive"]["deltaLAN"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["negative"]["deltaLAN"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["closest"]["deltaLAN"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["daylight"]["deltaLAN"], 3):TOSTRING:PADRIGHT(12) + " deg".
    }
    PRINT "Launch Direction " + (CHOOSE "North" IF solutions["Positive"]["launchN"] ELSE "South") + "       " + (CHOOSE "North" IF solutions["negative"]["launchN"] ELSE "South") + "       " + (CHOOSE "North" IF solutions["closest"]["launchN"] ELSE "South") + "       " + (CHOOSE "North" IF solutions["daylight"]["launchN"] ELSE "South").
    PRINT "Wait Time        " + timeToString(solutions["positive"]["waitTime"], 0):PADRIGHT(12) + timeToString(solutions["negative"]["waitTime"], 0):PADRIGHT(12) + timeToString(solutions["closest"]["waitTime"], 0):PADRIGHT(12) + timeToString(solutions["daylight"]["waitTime"], 0):PADRIGHT(12).
    IF extendedView PRINT "Local Day        " + ROUND(solutions["positive"]["waitTimeDays"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["negative"]["waitTimeDays"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["closest"]["waitTimeDays"], 3):TOSTRING:PADRIGHT(12) + ROUND(solutions["daylight"]["waitTimeDays"], 3):TOSTRING:PADRIGHT(12) + " local days".
    PRINT " ".
    PRINT "Press ENTER to accept the launch chance in daylight.".
    PRINT "Press C to accept the closest launch chance.".
    PRINT "Press + to accept the positive solution.".
    PRINT "Press - to accept the negative solution.".
    PRINT "Press 4 to toggle extended launch window data.".
    PRINT "Press 5 to toggle arrows showing the various angles.".
    PRINT "Press 7 to lower the fudge factor by 0.1 degrees.".
    PRINT "Press 8 to set the fudge factor to 0 degrees.".
    PRINT "Press 9 to raise the fudge factor by 0.1 degrees.".
    PRINT "Press backspace to abort launch".
    PRINT "In " + ROUND(timerStart + delayBeforeAuto - TIME:SECONDS, 0) + " seconds, launch in daylight will be selected".

    IF TERMINAL:INPUT:HASCHAR {
  		SET tempChar TO TERMINAL:INPUT:GETCHAR().
      IF tempChar = "4" {
        SET extendedView TO NOT extendedView.
        SET tempChar TO "".
      }
      IF tempChar = "5" {
        FOR eachKey IN vecDraws:KEYS SET vecDraws[eachKey]:SHOW TO NOT vecDraws[eachKey]:SHOW.
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
    IF (solutions["solutionType"] = "Error") AND (targetInclination <> 0) {
      CLEARSCREEN.
      PRINT "Launch site is too far from the equator to launch to that inclination.".
      PRINT "You cannot directly launch into that orbit from this launch site.".
      PRINT "Waiting " + ROUND(timerStart + 10 - TIME:SECONDS, 0) + " seconds, then aborting launch.  " AT (0, 2).
      IF TIME:SECONDS > timerStart + 10 {
        SET tempChar TO TERMINAL:INPUT:BACKSPACE.
      }
    }
    IF TIME:SECONDS > timerStart + delayBeforeAuto {
      SET tempChar TO TERMINAL:INPUT:ENTER.
    }
    WAIT 0.
  }
  IF tempChar = "+" {
    PRINT "Using the positive solution".
    SET deltaLAN TO solutions["positive"]["deltaLAN"].
    SET finalLaunchDirectionIsNorth TO solutions["positive"]["launchN"].
    SET tempChar TO "Launch".
  }
  IF tempChar = "-" {
    PRINT "Using the negative solution".
    SET deltaLAN TO solutions["negative"]["deltaLAN"].
    SET finalLaunchDirectionIsNorth TO solutions["negative"]["launchN"].
    SET tempChar TO "Launch".
  }
  IF tempChar = TERMINAL:INPUT:ENTER {
    PRINT "Using the daylight solution".
    SET deltaLAN TO solutions["daylight"]["deltaLAN"].
    SET finalLaunchDirectionIsNorth TO solutions["daylight"]["launchN"].
    SET tempChar TO "Launch".
  }
  IF tempChar = "C" {
    PRINT "Using the closest solution".
    SET deltaLAN TO solutions["closest"]["deltaLAN"].
    SET finalLaunchDirectionIsNorth TO solutions["closest"]["launchN"].
    SET tempChar TO "Launch".
  }
  CLEARVECDRAWS().
  IF tempChar = "Launch" {
    PRINT "Now waiting until lined up correctly for launch".
    LOCAL launchTime IS TIME:SECONDS + deltaLAN / 360 * BODY:ROTATIONPERIOD.
    // The reason for the loop is because if the timewarp is interrupted, it should auto-resume.
    UNTIL TIME:SECONDS >= launchTime {
      KUNIVERSE:TIMEWARP:WARPTO(launchTime).
      WAIT 0.20.
      UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE = 1 {WAIT 0.}
      WAIT 0.20.
    }
  } ELSE {
    SET abortLaunch TO TRUE.
  }
}
