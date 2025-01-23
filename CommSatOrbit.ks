@LAZYGLOBAL OFF.
CLEARSCREEN.

// Large script designed to place communications satellites in an appropriate
// position in orbit.
// Assumes that eccentricity and inclination of the desired orbit is low.
PARAMETER constellationSize IS 4.
PARAMETER visualize IS TRUE.
PARAMETER interactive IS TRUE.

FUNCTION numberToRoman {
  PARAMETER number.
  PARAMETER errorString IS number:TOSTRING.
  IF number = 1 RETURN "I".
  IF number = 2 RETURN "II".
  IF number = 3 RETURN "III".
  IF number = 4 RETURN "IV".
  IF number = 5 RETURN "V".
  IF number = 6 RETURN "VI".
  IF number = 7 RETURN "VII".
  IF number = 8 RETURN "VIII".
  IF number = 9 RETURN "IX".
  IF number = 10 RETURN "X".
  RETURN errorString.
}

FUNCTION romanToNumber {
  PARAMETER roman.
  PARAMETER errorNumber IS -1.
  IF roman = "I" RETURN 1.
  IF roman = "II" RETURN 2.
  IF roman = "III" RETURN 3.
  IF roman = "IV" RETURN 4.
  IF roman = "V" RETURN 5.
  IF roman = "VI" RETURN 6.
  IF roman = "VII" RETURN 7.
  IF roman = "VIII" RETURN 8.
  IF roman = "IX" RETURN 9.
  IF roman = "X" RETURN 10.
  RETURN roman:TONUMBER(errorNumber).
}

// To my knowledge, there isn't a way to determine the type of vessel - IE probe, communications relay, rover, etc.
// Because of this, determine if there are relays solely based on names.
LOCAL possibleVessels IS LIST().
LOCAL foundSats IS 0.
LOCAL thisSatNumber IS 1.
LIST TARGETS IN possibleVessels.
LOCAL namePrefix IS "Comm Sat - " + SHIP:BODY:NAME + " ".
FOR eachTarget IN possibleVessels {
  IF eachTarget:NAME:STARTSWITH(namePrefix) AND (NOT eachTarget:NAME:CONTAINS("Prime")) SET foundSats TO foundSats + 1.
}

// If this ship is already named to be in the constellation, don't rename it.
IF (SHIP:NAME:LENGTH > namePrefix:LENGTH) AND (romanToNumber(SHIP:NAME:SUBSTRING(namePrefix:LENGTH, SHIP:NAME:LENGTH - namePrefix:LENGTH), -1) <> -1) {
  SET thisSatNumber TO romanToNumber(SHIP:NAME:SUBSTRING(namePrefix:LENGTH, SHIP:NAME:LENGTH - namePrefix:LENGTH)).
} ELSE {
  SET thisSatNumber TO foundSats + 1.
  SET SHIP:NAME TO namePrefix + numberToRoman(thisSatNumber).
}

// If thisSatNumber is 1, circularize at the apoapsis and set the inclination to 0.
IF thisSatNumber = 1 {
  IF interactive {
    PRINT "This is the first satellite in the constellation.".
    PRINT " ".
    PRINT "Activate AG1 to accept and execute".
    PRINT "Activate AG2 to abort".
  }
  AG1 OFF.
  AG2 OFF.
  IF interactive UNTIL AG1 OR AG2 {WAIT 0.1.}

  IF AG1 OR NOT interactive {
    IF interactive PRINT "AG1 Activated!".
    IF SHIP:ORBIT:ECCENTRICITY > 0.0001 {
      IF interactive PRINT "Circularizing at apoapsis".
      RUNPATH("circ","apo").
      RUNPATH("exec",0,false,false,true).
      REMOVE NEXTNODE.
    }

    IF SHIP:ORBIT:INCLINATION > 0.001 {
      IF interactive PRINT "Executing zero-inclination burn".
      RUNPATH("inc",0).
      RUNPATH("exec",0,false,false,true).
      REMOVE NEXTNODE.
    }

    SET loopMessage TO SHIP:NAME + " is the first Comm Sat around " + SHIP:BODY:NAME.
  }
  IF AG2 {
    SET loopMessage TO "CommSatOrbit calculations complete".
    AG2 OFF.
  }
}
// If thisSatNumber is not 1, calculate the desired angular distance between the current ship and the previous.
IF thisSatNumber <> 1 {
  LOCAL errorCode IS "None".
  LOCAL leadVessel IS VESSEL(namePrefix + "I").
  LOCAL leadSMA IS leadVessel:ORBIT:SEMIMAJORAXIS.
  LOCAL desiredFinalAltitude IS leadSMA - SHIP:BODY:RADIUS.
  LOCAL nodeTime IS timeToAltitude(desiredFinalAltitude).
  IF nodeTime = -1 {
    IF interactive PRINT "Current orbit does not cross desired orbit!".
    IF desiredFinalAltitude < SHIP:PERIAPSIS SET errorCode TO "Periapsis > final altitude".
    IF desiredFinalAltitude > SHIP:APOAPSIS SET errorCode TO "Apoapsis < final altitude".
  }
  SET nodeTime TO nodeTime + TIME:SECONDS.
  LOCAL leadPeriod IS leadVessel:ORBIT:PERIOD.
  LOCAL desiredAngle IS (thisSatNumber - 1) * 360 / constellationSize.
  LOCAL actualAngle IS normalizeAngle360(SHIP:BODY:GEOPOSITIONOF(POSITIONAT(leadVessel, nodeTime)):LNG - SHIP:BODY:GEOPOSITIONOF(POSITIONAT(SHIP, nodeTime)):LNG).
  LOCAL deltaAngle IS normalizeAngle360(actualAngle - desiredAngle).
  LOCAL ecc IS SHIP:ORBIT:ECCENTRICITY.
  LOCAL eccentricAnomalyDelta IS 2 * ARCTAN((1 - ecc)/(1 + ecc) * TAN((actualAngle - desiredAngle)/2)).
  LOCAL timeChangeNeeded IS SHIP:ORBIT:PERIOD / (2 * CONSTANT:PI) * (eccentricAnomalyDelta*CONSTANT:DegToRad - ecc * SIN(eccentricAnomalyDelta)).

  IF ABS(timeChangeNeeded) < 60 SET errorCode TO "Time change too small!".

  IF errorCode = "None" {
    // Phase orbit period is timeChangeNeeded SHORTER than the period of the lead satellite.
    // If you want to move 15 minutes back in orbit, increase the period for one orbit.
    LOCAL phaseOrbitPeriod IS leadPeriod - timeChangeNeeded.
    LOCAL phaseOrbitSMA IS ((SQRT(SHIP:BODY:MU) * phaseOrbitPeriod / (2 * CONSTANT:PI)) ^ (2/3)).

    IF interactive {
      IF timeChangeNeeded < 0 PRINT "Ship should move " + timeToString(-timeChangeNeeded) + " back in orbit".
      ELSE PRINT "Ship should move " + timeToString(timeChangeNeeded) + " forward in orbit".
      PRINT "Orbit      SMA (m)     Period (format)   Period (s)  Inc (deg)".
      PRINT "Initial" + ROUND(SHIP:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(11) + timeToString(SHIP:ORBIT:PERIOD):TOSTRING:PADLEFT(20) + ROUND(SHIP:ORBIT:PERIOD, 2):TOSTRING:PADLEFT(13) + ROUND(SHIP:ORBIT:INCLINATION,5):TOSTRING:PADLEFT(11).
      PRINT "Phase  " + ROUND(phaseOrbitSMA):TOSTRING:PADLEFT(11) + timeToString(phaseOrbitPeriod):TOSTRING:PADLEFT(20) + ROUND(phaseOrbitPeriod, 2):TOSTRING:PADLEFT(13)  + ROUND(SHIP:ORBIT:INCLINATION,5):TOSTRING:PADLEFT(11).
      PRINT "Final  " + ROUND(leadVessel:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(11) + timeToString(leadVessel:ORBIT:PERIOD):TOSTRING:PADLEFT(20) + ROUND(leadVessel:ORBIT:PERIOD, 2):TOSTRING:PADLEFT(13)  + ROUND(leadVessel:ORBIT:INCLINATION,5):TOSTRING:PADLEFT(11).
    }

    LOCAL leadVecDraw    IS VECDRAW({        RETURN SHIP:BODY:POSITION.},        {RETURN POSITIONAT(leadVessel, nodeTime) - SHIP:BODY:POSITION.},    RED, "Lead Vessel", 1.0, FALSE).
    LOCAL currentVecDraw IS VECDRAW({        RETURN SHIP:BODY:POSITION.},              {RETURN POSITIONAT(SHIP, nodeTime) - SHIP:BODY:POSITION.},  GREEN, "Current Position", 1.0, FALSE).
    LOCAL desiredVecDraw IS VECDRAW({        RETURN SHIP:BODY:POSITION.}, {RETURN leadVecDraw:VEC * ANGLEAXIS(desiredAngle, - BODY:ANGULARVEL).},   BLUE, "Desired Position", 1.0, FALSE).
    LOCAL deltaVecDraw   IS VECDRAW({RETURN POSITIONAT(SHIP, nodeTime).},                      {RETURN desiredVecDraw:VEC - currentVecDraw:VEC.}, YELLOW, ROUND(deltaAngle, 1) + " deg, " + timeToString(timeChangeNeeded), 1.0, FALSE).
    IF visualize {
      SET leadVecDraw:SHOW TO TRUE.
      SET currentVecDraw:SHOW TO TRUE.
      SET desiredVecDraw:SHOW TO TRUE.
      SET deltaVecDraw:SHOW TO TRUE.

      IF interactive {
        AG1 OFF.
        AG2 OFF.
        PRINT " ".
        PRINT "Activate AG1 to accept and execute".
        PRINT "Activate AG2 to abort".
        UNTIL AG1 OR AG2 {WAIT 0.1.}
      }
    }

    IF AG1 OR NOT interactive {
      IF interactive {
        IF AG1 PRINT "AG1 Activated!".
        PRINT "Executing phasing orbit insertion burn".
      }
      LOCAL timeAtPhaseStart IS TIME:SECONDS.
      RUNPATH("ChangePeriod", nodeTime - TIME:SECONDS, phaseOrbitPeriod, False).
      RUNPATH("exec",0,false,false,true).
      REMOVE NEXTNODE.
      IF interactive PRINT "Now in phasing orbit with period of " + timeToString(SHIP:ORBIT:PERIOD).

      IF SHIP:ORBIT:INCLINATION > 0.001 {
        PRINT "Executing zero-inclination burn".
        RUNPATH("inc",0).
        RUNPATH("exec",0,false,false,true).
        REMOVE NEXTNODE.
      }

      IF TIME:SECONDS < timeAtPhaseStart + 0.75 * phaseOrbitPeriod {
        IF interactive PRINT "Now waiting to pass final altitude.".
        WARPTO(timeAtPhaseStart + 0.75 * phaseOrbitPeriod).
      }
      IF interactive PRINT "Executing circularization burn".
      RUNPATH("circ", timeToAltitude(desiredFinalAltitude)).
      RUNPATH("exec",0,false,false,true).
      REMOVE NEXTNODE.
      IF interactive PRINT "In final orbit".
      SET loopMessage TO SHIP:NAME + " is the " + thisSatNumber + " Comm Sat around " + SHIP:BODY:NAME.
      AG1 OFF.

      // Run the same script once again to see the results
      IF interactive RUNPATH("CommSatOrbit", constellationSize, visualize).
    }
    IF AG2 {
      SET loopMessage TO "CommSatOrbit calculations complete".
      AG2 OFF.
    }
  } ELSE {
    SET loopMessage TO errorCode.
  }
}
