@LAZYGLOBAL OFF.
LOCAL estimateAltitude IS 0.
IF SHIP:BODY:BODY:ATM:EXISTS SET estimateAltitude TO SHIP:BODY:BODY:ATM:HEIGHT * 1.1.
ELSE SET estimateAltitude TO SHIP:BODY:BODY:RADIUS * 0.05.
PARAMETER finalAltitude IS estimateAltitude.
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
LOCAL r_burn IS 0.
LOCAL currentAngleFromRetrograde IS 0.
LOCAL meanAngularMotion IS 0.
LOCAL retrogradeTrueAnomaly IS 0.
LOCAL retrogradeMeanAnomaly IS 0.
LOCAL burnTrueAnomaly IS 0.
LOCAL burnMeanAnomaly IS 0.
LOCAL estimateTimeFromNow IS 10.
LOCAL estimateTimeFromNowOld IS 0.
LOCAL iteration IS 0.
LOCAL iterationMax IS 50.

UNTIL ABS(estimateTimeFromNow - estimateTimeFromNowOld) < 0.5 OR iteration > iterationMax {
  SET estimateTimeFromNowOld TO estimateTimeFromNow.
  SET burnInfo TO getHyperbolicBurnInfo(v_inf, estimateTimeFromNow).
  SET r_burn TO (POSITIONAT(SHIP, TIME:SECONDS + estimateTimeFromNow) - moonBody:POSITION):MAG.
  SET currentAngleFromRetrograde TO VANG(planetBody:VELOCITY:ORBIT, SHIP:POSITION - moonBody:POSITION).
  IF VDOT(planetBody:VELOCITY:ORBIT, -moonBody:POSITION) > 0 SET currentAngleFromRetrograde TO -currentAngleFromRetrograde.
  SET meanAngularMotion TO 360 / SHIP:ORBIT:PERIOD.
  SET retrogradeTrueAnomaly TO SHIP:ORBIT:TRUEANOMALY - currentAngleFromRetrograde.
  SET retrogradeMeanAnomaly TO trueToMeanAnomaly(retrogradeTrueAnomaly).
  SET burnTrueAnomaly TO retrogradeTrueAnomaly - 90 - burnInfo["theta_turn"].
  SET burnMeanAnomaly TO trueToMeanAnomaly(burnTrueAnomaly).
  SET estimateTimeFromNow TO normalizeAngle(burnMeanAnomaly - trueToMeanAnomaly(SHIP:ORBIT:TRUEANOMALY)) / meanAngularMotion.
  SET iteration TO iteration + 1.
}

LOCAL newNode IS NODE(TIME:SECONDS + estimateTimeFromNow, 0, 0, burnInfo["v_delta"]).
ADD newNode.
IF printingAllowed {
  CLEARSCREEN.
  PRINT "Iteration is " + iteration.
  PRINT "                    Ellipse      Hyperbola".
  PRINT "Eccentricity" + ROUND(SHIP:ORBIT:ECCENTRICITY,  4):TOSTRING:PADLEFT(15) + ROUND(burnInfo["e"], 4):TOSTRING:PADLEFT(15).
  PRINT "SMA         " + ROUND(SHIP:ORBIT:SEMIMAJORAXIS):TOSTRING:PADLEFT(15) + ROUND(burnInfo["a"]):TOSTRING:PADLEFT(15).
  PRINT " ".
  PRINT "Velocity at infinity is          " + (distanceToString(v_inf, 4) + "/s"):PADLEFT(15).
  PRINT "Radius at burn is                " + (distanceToString(r_burn, 4) + ""):PADLEFT(15).
  PRINT "Flight Path Angle at burn is     " + (ROUND(burnInfo["flightPathAngle"], 4) + " deg"):PADLEFT(15).
  PRINT "True Anomaly at burn is          " + (ROUND(burnInfo["trueAnomaly"], 4) + " deg"):PADLEFT(15).
  PRINT "Flight Path Angle at SOI is      " + (ROUND(burnInfo["flightPathAngleSOI"], 4) + " deg"):PADLEFT(15).
  PRINT "True Anomaly at SOI is           " + (ROUND(burnInfo["trueAnomalySOI"], 4) + " deg"):PADLEFT(15).
  PRINT "Hyperbolic Turning Angle is      " + (ROUND(burnInfo["theta_turn"], 4) + " deg"):PADLEFT(15).
  PRINT "Current Angle from retrograde is " + (ROUND(currentAngleFromRetrograde, 4) + " deg"):PADLEFT(15).
  PRINT "Mean Angular Motion is             " + (ROUND(meanAngularMotion, 4) + " deg/s"):PADLEFT(15).
  PRINT "Retrograde True Anomaly is       " + (ROUND(retrogradeTrueAnomaly, 4) + " deg"):PADLEFT(15).
  PRINT "Retrograde Mean Anomaly is       " + (ROUND(retrogradeMeanAnomaly, 4) + " deg"):PADLEFT(15).
  PRINT "Burn True Anomaly is             " + (ROUND(burnTrueAnomaly, 4) + " deg"):PADLEFT(15).
  PRINT "Burn Mean Anomaly is             " + (ROUND(burnMeanAnomaly, 4) + " deg"):PADLEFT(15).
  PRINT "Estimate Time from Now is      " + (ROUND(estimateTimeFromNow)):TOSTRING:PADLEFT(15) + " s".
  PRINT "Adjust With Heuristics is        " + adjustWithHeuristics.
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
}
SET loopMessage TO "Hyperbolic escape burn created".
