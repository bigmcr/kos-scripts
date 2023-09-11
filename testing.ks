@LAZYGLOBAL OFF.
PARAMETER finalAltitude IS 55000.
PARAMETER printingAllowed IS TRUE.
PARAMETER adjustWithHeuristics IS TRUE.

LOCAL moonBody IS SHIP:BODY.
LOCAL planetBody IS SHIP:BODY:BODY.

// calculations for the return flight to the orbiting body.
LOCAL transferPeri IS BODY:BODY:RADIUS + finalAltitude.
LOCAL transferApo IS SHIP:BODY:ALTITUDE + planetBody:RADIUS - moonBody:SOIRADIUS.
LOCAL transferSMA IS (transferPeri + transferApo)/2.
LOCAL transferE IS 1 - transferPeri/transferSMA.
LOCAL transferStartV IS SQRT(planetBody:MU*(2/transferApo - 1/transferSMA)).
LOCAL v_inf TO planetBody:VELOCITY:ORBIT:MAG - transferStartV.

LOCAL burnInfo IS 0.
LOCAL estimateTimeFromNow IS ETA:APOAPSIS.

SET burnInfo TO getHyperbolicBurnInfo(v_inf, estimateTimeFromNow).

LOCAL newNode IS NODE(TIME:SECONDS + estimateTimeFromNow, 0, 0, burnInfo["v_delta"]).
ADD newNode.
IF printingAllowed {
  CLEARSCREEN.
  PRINT "Turning Angle: " + burnInfo["theta_turn"].
  PRINT "                Ellipse  Hyperbola   NextNode".
  PRINT "Eccentricity" + ROUND(SHIP:ORBIT:ECCENTRICITY,  4):TOSTRING:PADLEFT(11) + ROUND(burnInfo["e"], 4):TOSTRING:PADLEFT(11) + ROUND(NEXTNODE:ORBIT:ECCENTRICITY, 4):TOSTRING:PADLEFT(11).
  PRINT "SMA         " + ROUND(SHIP:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(11) + ROUND(burnInfo["a"]):TOSTRING:PADLEFT(11) + ROUND(NEXTNODE:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(11).
  PRINT "Velocity    " + ROUND(VELOCITYAT(SHIP, TIME:SECONDS + estimateTimeFromNow - 1):ORBIT:MAG):TOSTRING:PADLEFT(11) + ROUND(VELOCITYAT(SHIP, TIME:SECONDS + estimateTimeFromNow + 1):ORBIT:MAG):TOSTRING:PADLEFT(11) + " m/s".
  PRINT " ".
  PRINT "Velocity at infinity is          " + (distanceToString(v_inf, 4) + "/s"):PADLEFT(15).
//  PRINT "Adjust With Heuristics is        " + adjustWithHeuristics.
//  LOCAL radius IS moonBody:RADIUS * 3.
//  LOCAL shipLANVector TO (SOLARPRIMEVECTOR * ANGLEAXIS(-SHIP:ORBIT:LAN, NORTH:VECTOR)):NORMALIZED.
//  LOCAL shipNormVector TO VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - moonBody:POSITION):NORMALIZED.
//  LOCAL shipPeriVector TO (shipLANVector * ANGLEAXIS(-SHIP:ORBIT:ARGUMENTOFPERIAPSIS, shipNormVector)):NORMALIZED.
//  LOCAL MoonMotion IS VECDRAW(BODY:POSITION, radius * planetBody:VELOCITY:ORBIT:NORMALIZED, RED, "Moon Motion", 1, TRUE).
//  LOCAL periVecDraw IS VECDRAW(BODY:POSITION, radius * shipPeriVector, GREEN, "Periapsis", 1, TRUE).
//  LOCAL BurnPos IS VECDRAW(BODY:POSITION, radius * shipPeriVector * ANGLEAXIS(burnTrueAnomaly, shipNormVector), YELLOW, "BurnPos", 1, TRUE).
  IF NOT adjustWithHeuristics WAIT 5.
}


// assumes that you have a node that puts you on a trajectory that takes you out of this SOI.
// NEXTNODE:ORBIT is hyperbolic trajectory to current BODY SOI edge.
// NEXTNODE:ORBIT:NEXTPATCH is elliptical transfer orbit in parent's SOI.
FUNCTION apoOfTransferTrajectory {
  PARAMETER timeETA.
  IF NEXTNODE:ORBIT:HASNEXTPATCH {
    SET NEXTNODE:ETA TO timeETA.
    IF NEXTNODE:ORBIT:HASNEXTPATCH {
      RETURN ABS(0-NEXTNODE:ORBIT:NEXTPATCH:APOAPSIS).
    }
  }
  RETURN 1e15.
}

// assumes that you have a node that puts you on a trajectory that takes you out of this SOI.
// NEXTNODE:ORBIT is hyperbolic trajectory to current BODY SOI edge.
// NEXTNODE:ORBIT:NEXTPATCH is elliptical transfer orbit in parent's SOI.
FUNCTION periOfTransferTrajectory {
  PARAMETER pro.
  IF NEXTNODE:ORBIT:HASNEXTPATCH {
    SET NEXTNODE:PROGRADE TO pro.
    IF NEXTNODE:ORBIT:HASNEXTPATCH RETURN ABS(finalAltitude - NEXTNODE:ORBIT:NEXTPATCH:PERIAPSIS).
  }
  RETURN 1e15.
}
IF adjustWithHeuristics {
  LOCAL apoHillclimb IS hillClimb(apoOfTransferTrajectory@,   // Delegate, see function above.
                                  NEXTNODE:ETA,               // Initial Guess
                                  SHIP:ORBIT:PERIOD / 10,     // Initial Step Size
                                  CHOOSE "0:HillClimbTime.csv" IF printingAllowed ELSE "",      // LogFile path
                                  100,                        // Maximum iteration number
                                  15,                         // Ratio of smallest step size to initial step size (negative power of 2)
                                  SHIP:ORBIT:PERIOD,          // Cyclical Period
                                  60).                         // Cyclical Period Cutoff
  IF printingAllowed PRINT "Completed Apo Hill Climb".
  LOCAL periHillclimb IS hillClimb(periOfTransferTrajectory@,  // Delegate, see function above.
                         NEXTNODE:PROGRADE,          // Initial Guess
                         NEXTNODE:PROGRADE / 20,     // Initial Step Size
                         CHOOSE "0:HillClimbPrograde.csv" IF printingAllowed ELSE "",  // LogFile path
                         100,                        // Maximum iteration number
                         15,                         // Ratio of smallest step size to initial step size (negative power of 2)
                         -1,                         // Cyclical Period
                         0).                         // Cyclical Period Cutoff
  IF printingAllowed {
    PRINT "Completed periapsis hill climb".
    PRINT "Hill Climb        Iteration     Value_i     Value_f     Value_d".
    PRINT "Apoapsis          " + apoHillclimb["iteration"]:TOSTRING:PADLEFT(9) +
                                 distanceToString(apoHillclimb["initialValue"], 2):TOSTRING:PADLEFT(12) +
                                 distanceToString(apoHillclimb["finalValue"], 2):TOSTRING:PADLEFT(12) +
                                 distanceToString(apoHillclimb["deltaValue"], 2):TOSTRING:PADLEFT(12).
    PRINT "Periapsis         " + periHillclimb["iteration"]:TOSTRING:PADLEFT(9) +
                                distanceToString(periHillclimb["initialValue"], 2):TOSTRING:PADLEFT(12) +
                                distanceToString(periHillclimb["finalValue"], 2):TOSTRING:PADLEFT(12) +
                                distanceToString(periHillclimb["deltaValue"], 2):TOSTRING:PADLEFT(12).
    WAIT 5.
  }
} ELSE {
  LOCAL arg1 IS LEXICON().
  arg1:ADD("delegate", apoOfTransferTrajectory@).       // Delegate, see function above
  arg1:ADD("initialGuess", NEXTNODE:ETA).               // Initial Guess
  arg1:ADD("initialStepSize", SHIP:ORBIT:PERIOD / 10).  // Initial Step Size
  arg1:ADD("logFile", CHOOSE "0:HillClimbTime.csv" IF printingAllowed ELSE "").      // LogFile path
  arg1:ADD("iterationMax", 100).                        // Maximum iteration number
  arg1:ADD("smallestStepRatio", 15).                    // Ratio of smallest step size to initial step size (negative power of 2)
  arg1:ADD("cyclicalPeriod", SHIP:ORBIT:PERIOD).        // Cyclical Period
  arg1:ADD("cyclicalPeriodCutoff", 60).                 // Cyclical Period Cutoff

  LOCAL periHillclimb IS hillClimb(periOfTransferTrajectory@,  // Delegate, see function above.
                         NEXTNODE:PROGRADE,          // Initial Guess
                         NEXTNODE:PROGRADE / 20,     // Initial Step Size
                         CHOOSE "0:HillClimbPrograde.csv" IF printingAllowed ELSE "",  // LogFile path
                         100,                        // Maximum iteration number
                         15,                         // Ratio of smallest step size to initial step size (negative power of 2)
                         -1,                         // Cyclical Period
                         0).                         // Cyclical Period Cutoff
  LOCAL arg2 IS LEXICON().
  arg2:ADD("delegate", periOfTransferTrajectory@).      // Delegate, see function above
  arg2:ADD("initialGuess", NEXTNODE:PROGRADE).          // Initial Guess
  arg2:ADD("initialStepSize", NEXTNODE:PROGRADE / 20).  // Initial Step Size
  arg2:ADD("logFile", CHOOSE "0:HillClimbPrograde.csv" IF printingAllowed ELSE "").      // LogFile path
  arg2:ADD("iterationMax", 100).                        // Maximum iteration number
  arg2:ADD("smallestStepRatio", 15).                    // Ratio of smallest step size to initial step size (negative power of 2)
  arg2:ADD("cyclicalPeriod", -1).                       // Cyclical Period
  arg2:ADD("cyclicalPeriodCutoff", 0).                  // Cyclical Period Cutoff
  hillClimb2D(arg1, arg2).
}
SET loopMessage TO "Hyperbolic escape burn created".
