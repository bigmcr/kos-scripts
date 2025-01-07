@LAZYGLOBAL OFF.

CLEARSCREEN.

IF NOT HASTARGET {
    CLEARSCREEN.
    PRINT "Select a target.".
    PRINT "It must be an asteroid whose orbit intersects with the current SOI.".
    UNTIL HASTARGET {WAIT 0.}
}

// Find the list of all orbits the target will have over time.
LOCAL orbits IS LIST().
LOCAL targetOrbit IS TARGET:ORBIT.
UNTIL NOT targetOrbit:HASNEXTPATCH {
  orbits:ADD(targetOrbit).
  SET targetOrbit TO targetOrbit:NEXTPATCH.
}
orbits:ADD(targetOrbit).
logOrbit(orbits, "0:asteroidOrbits.csv").

// Scroll through the orbits and determine which orbits intersect the current SOI.
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

LOCAL tempChar IS "".
IF finalTargetOrbit:TYPENAME = "SCALAR" {
  PRINT "Chosen object does not enter current SOI - cannot find orbit to park in".
} ELSE {
  IF previousTargetOrbit = 0 SET tempChar TO TERMINAL:INPUT:ENTER.
  UNTIL (tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE) {
    PRINT "Waiting until target enters the current SOI.".
    PRINT "It will be " + timeToString(previousTargetOrbit:NEXTPATCHETA).
    PRINT "Press ENTER to continue or CTRL+C to abort launch".
    IF TERMINAL:INPUT:HASCHAR {
  		SET tempChar TO TERMINAL:INPUT:GETCHAR().
  	}
    WAIT 0.
  }
}
IF tempChar = TERMINAL:INPUT:ENTER {
  // let's make sure that the previous target orbit is valid (aka it is NOT in the current SOI)
  IF previousTargetOrbit <> 0 {
    KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + previousTargetOrbit:NEXTPATCHETA + 10).
    WAIT 0.
    UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE = 1 {WAIT 0.}
  }

  LOCAL finalAltitude IS 30000.
  IF SHIP:BODY:ATM:EXISTS SET finalAltitude TO SHIP:BODY:ATM:HEIGHT - 5000.
  RUNPATH("LaunchToOrbit", finalAltitude, finalTargetOrbit:INCLINATION, finalTargetOrbit:LAN).
} ELSE {
  PRINT "Launch aborted!".
  WAIT 1.
  SET loopMessage TO "Launch aborted".
}
