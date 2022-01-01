@LAZYGLOBAL OFF.
CLEARSCREEN.

// Large script designed to place communications satellites in an appropriate
// position in orbit.
// Assumes that eccentricity of the desired orbit is low.
PARAMETER constellationSize IS 4.
PARAMETER visualize IS TRUE.

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
  IF SHIP:ORBIT:ECCENTRICITY > 0.0001 {
    RUNPATH("circ","apo").
    RUNPATH("exec",0,false,false,true).
    REMOVE NEXTNODE.
  }

  IF SHIP:ORBIT:INCLINATION > 0.001 {
    RUNPATH("inc",0).
    RUNPATH("exec",0,false,false,true).
    REMOVE NEXTNODE.
  }

  SET loopMessage TO SHIP:NAME + " is the first Comm Sat around " + SHIP:BODY:NAME.
}
// If thisSatNumber is not 1, calculate the desired angular distance between the current ship and the previous.
IF thisSatNumber <> 1 {
  LOCAL leadVessel IS VESSEL(namePrefix + "I").
  LOCAL leadSMA IS leadVessel:ORBIT:SEMIMAJORAXIS.
  LOCAL leadPeriod IS leadVessel:ORBIT:PERIOD.
  LOCAL desiredAngle IS (thisSatNumber - 1) * 360 / constellationSize.
  LOCAL actualAngle IS normalizeAngle(leadVessel:GEOPOSITION:LNG - SHIP:GEOPOSITION:LNG).
  LOCAL deltaAngle IS normalizeAngle(actualAngle - desiredAngle).
  LOCAL ecc IS SHIP:ORBIT:ECCENTRICITY.
  LOCAL eccentricAnomalyDelta IS 2 * ARCTAN((1 - ecc)/(1 + ecc) * TAN((actualAngle - desiredAngle)/2)).
  LOCAL timeChangeNeeded IS SHIP:ORBIT:PERIOD / (2 * CONSTANT:PI) * (eccentricAnomalyDelta*CONSTANT:DegToRad - ecc * SIN(eccentricAnomalyDelta)).
  IF deltaAngle > 0 SET timeChangeNeeded TO - timeChangeNeeded.
  LOCAL phaseOrbitPeriod IS SHIP:ORBIT:PERIOD + timeChangeNeeded.

  LOCAL phaseOrbitSMA IS ((SQRT(SHIP:BODY:MU) * phaseOrbitPeriod / (2 * CONSTANT:PI)) ^ (2/3)).
  LOCAL nodeTime IS TIME:SECONDS + 60.
  LOCAL desiredPhaseOrbitSpeed IS SQRT(SHIP:BODY:MU * ( 2 / (POSITIONAT(SHIP, nodeTime) - SHIP:BODY:POSITION):MAG - 1 / phaseOrbitSMA)).
  LOCAL originalVAtBurn IS VELOCITYAT(SHIP, nodeTime):ORBIT.
  LOCAL desiredVAtBurn IS originalVAtBurn:NORMALIZED * desiredPhaseOrbitSpeed.
  LOCAL deltaV IS originalVAtBurn - desiredVAtBurn.

  IF timeChangeNeeded < 0 PRINT "Ship should move " + timeToString(-timeChangeNeeded) + " back in orbit".
  ELSE PRINT "Ship should move " + timeToString(timeChangeNeeded) + " forward in orbit".

  PRINT "Orbit      SMA (m)     Period (s)  Inc (deg)".
  PRINT "Initial" + ROUND(SHIP:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(11) + timeToString(SHIP:ORBIT:PERIOD):TOSTRING:PADLEFT(15) + ROUND(SHIP:ORBIT:INCLINATION,5):TOSTRING:PADLEFT(11).
  PRINT "Phase  " + ROUND(phaseOrbitSMA):TOSTRING:PADLEFT(11) + timeToString(phaseOrbitPeriod):TOSTRING:PADLEFT(15) + ROUND(SHIP:ORBIT:INCLINATION,5):TOSTRING:PADLEFT(11).
  PRINT "Final  " + ROUND(leadVessel:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(11) + timeToString(leadVessel:ORBIT:PERIOD):TOSTRING:PADLEFT(15) + ROUND(leadVessel:ORBIT:INCLINATION,5):TOSTRING:PADLEFT(11).

  LOCAL leadVecDraw    IS VECDRAW({RETURN SHIP:BODY:POSITION.},                    {RETURN leadVessel:POSITION - SHIP:BODY:POSITION.},    RED, "Lead Vessel", 1.0, FALSE).
  LOCAL currentVecDraw IS VECDRAW({RETURN SHIP:BODY:POSITION.},                                         {RETURN -SHIP:BODY:POSITION.},  GREEN, "Current Position", 1.0, FALSE).
  LOCAL desiredVecDraw IS VECDRAW({RETURN SHIP:BODY:POSITION.}, {RETURN leadVecDraw:VEC * ANGLEAXIS(desiredAngle, -BODY:ANGULARVEL).},   BLUE, "Desired Position", 1.0, FALSE).
  LOCAL deltaVecDraw   IS VECDRAW(                  V(0, 0, 0),                     {RETURN desiredVecDraw:VEC + SHIP:BODY:POSITION.}, YELLOW, ROUND(deltaAngle, 1) + " deg, " + timeToString(timeChangeNeeded), 1.0, FALSE).
  IF visualize {
    SET leadVecDraw:SHOW TO TRUE.
    SET currentVecDraw:SHOW TO TRUE.
    SET desiredVecDraw:SHOW TO TRUE.
    SET deltaVecDraw:SHOW TO TRUE.
    AG1 OFF.
    AG2 OFF.
    PRINT " ".
    PRINT "Activate AG1 to accept and execute".
    PRINT "Activate AG2 to abort".
    UNTIL AG1 OR AG2 {WAIT 0.1.}
  }

  IF AG1 {
    PRINT "Executing phasing orbit insertion burn".
    LOCAL orbitDirections IS getOrbitDirectionsAt(nodeTime).
    ADD NODE( nodeTime, 0, 0, deltaV*orbitDirections["Prograde"]).
    RUNPATH("exec",0,false,false,true).
    REMOVE NEXTNODE.

    PRINT "Now in phasing orbit.".
    IF (ETA:PERIAPSIS < ETA:APOAPSIS) {
      PRINT "Waiting until past periapsis".
      WARPTO(TIME:SECONDS + ETA:PERIAPSIS + 1).
    }
    PRINT "Executing circularization burn".

    IF deltaV*orbitDirections["Prograde"] < 0 RUNPATH("circ","APO").
    ELSE RUNPATH("circ","PERI").
    RUNPATH("exec",0,false,false,true).
    REMOVE NEXTNODE.

    PRINT "Orbit circularized".

    IF SHIP:ORBIT:INCLINATION > 0.001 {
      PRINT "Executing zero-inclination burn".
      RUNPATH("inc",0).
      RUNPATH("exec",0,false,false,true).
      REMOVE NEXTNODE.
    }
    PRINT "In final orbit".
    SET loopMessage TO SHIP:NAME + " is the " + thisSatNumber + " Comm Sat around " + SHIP:BODY:NAME.
    AG1 OFF.

    // Run the same script once again to see the results
    RUNPATH("CommSatOrbit", constellationSize, visualize).
  }
  IF AG2 {
    SET loopMessage TO "CommSatOrbit calculations complete".
    AG2 OFF.
  }
}
