@LAZYGLOBAL OFF.
CLEARSCREEN.

PARAMETER desiredBody IS "Minmus".
PARAMETER desiredOrbitAlt IS 100.

LOCAL logFileName IS "0:gaussProblem.csv".
IF EXISTS(logFileName) DELETEPATH(logFileName).

FUNCTION gaussProblemPIteration {
  PARAMETER r_1.
  PARAMETER r_2.
  PARAMETER timeOfFlight.
  PARAMETER mu.
  PARAMETER shortWay IS TRUE.
  PARAMETER timeTolerance IS 0.001.         // Default tolerance of 0.001 second
  PARAMETER maxIterations IS 20.
  PARAMETER pStart1 IS 0.05.
  PARAMETER pStart2 IS 0.2.

  // Start off by calculating the various constants associated with the problem.
  LOCAL phaseAngle IS VANG(r_1, r_2).
  PRINT "Phase Angle Raw: " + phaseAngle.
  LOG "Phase Angle Raw," + phaseAngle TO logFileName.
  IF phaseAngle > 180 SET phaseAngle TO 360 - phaseAngle.
  PRINT "Phase Angle 1: " + phaseAngle.
  LOG "Phase Angle 1," + phaseAngle TO logFileName.
  IF NOT shortWay SET phaseAngle TO 360 - phaseAngle.
  PRINT "Phase Angle Final: " + phaseAngle.
  LOG "Phase Angle Final," + phaseAngle TO logFileName.
  LOCAL phaseAngleRad IS phaseAngle * CONSTANT:RadToDeg.
  LOCAL r_1_mag IS r_1:MAG.
  LOCAL r_2_mag IS r_2:MAG.
  LOCAL k IS r_1_mag*r_2_mag*(1-COS(phaseAngle)).
  LOCAL l IS r_1_mag+r_2_mag.
  LOCAL m IS r_1_mag*r_2_mag*(1+COS(phaseAngle)).
  LOCAL p_i IS k/(l+SQRT(2*m)).
  LOCAL p_ii IS k/(l-SQRT(2*m)).

  LOCAL logMe IS LIST().
  logMe:ADD(",X,Y,Z,Magnitude,Units,Short Way," + shortWay + ",pStart1," + pStart1 + ",pStart2," + pStart2).
  logMe:ADD("R_1," + r_1:X + "," + r_1:y + "," + r_1:z + "," + r_1_mag + ",meters").
  logMe:ADD("R_2," + r_2:X + "," + r_2:y + "," + r_2:z + "," + r_2_mag + ",meters").
  logMe:ADD("Desired Time," + timeOfFlight + ",s," + timeToString(timeOfFlight)).
  logMe:ADD("mu," + mu).
  logMe:ADD("phaseAngle," + phaseAngle*CONSTANT:DegToRad + "," + phaseAngle).
  logMe:ADD("k," + k).
  logMe:ADD("l," + l).
  logMe:ADD("m," + m).
  logMe:ADD("p_i," + p_i).
  logMe:ADD("p_ii," + p_ii).
  logMe:ADD("").

  logMe:ADD("p,").              //12
  logMe:ADD("a,").              //13
  logMe:ADD("Motion Type,").    //14
  logMe:ADD("f,").              //15
  logMe:ADD("g,").              //16
  logMe:ADD("f_dot,").          //17
  logMe:ADD("deltaAngle,").     //18
  logMe:ADD("Time,").           //19
  logMe:ADD("Time Error,").     //20
  logMe:ADD("Iteration,").      //21
  logMe:ADD(",").               //22
  logMe:ADD(",").               //23
  logMe:ADD("delta_v," + phaseAngle*CONSTANT:DegToRad + "," + phaseAngle).

  LOCAL pList IS LIST().
  LOCAL tList IS LIST().

  LOCAL p IS (p_ii - p_i) * pStart1 + p_i.
  LOCAL a IS m*k*p/((2*m-l^2)*p^2+2*k*l*p-k^2).
  LOCAL motionType IS "Ellipse".
  IF a < 0 SET motionType TO "Hyperbola".
  ELSE SET motionType TO "Ellipse".
  LOCAL f IS 1 - r_2_mag / p * ( 1 - COS(phaseAngle)).
  LOCAL g IS r_1_mag * r_2_mag * SIN(phaseAngle) / SQRT(mu * p).
  LOCAL f_dot IS SQRT(mu / p) * TAN(phaseAngle / 2) * ((1 - COS(phaseAngle)) / p - 1 / r_1_mag - 1 / r_2_mag).
  LOCAL deltaAngle IS 0.
  LOCAL deltaAngleRad IS deltaAngle * CONSTANT:DegToRad.
  LOCAL time IS 0.
  LOCAL timeError IS timeTolerance + 1.0.
  IF motionType = "Ellipse" {
    SET deltaAngle TO ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET time TO g + SQRT( a^3 / mu) * ( deltaAngleRad - SIN(deltaAngle)).
  } ELSE {
    SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET time TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngleRad).
  }
  SET timeError TO timeOfFlight - time.
  pList:ADD(p).
  tList:ADD(time).

  LOCAL iterations IS 0.
  LOCAL timeNMinusOne IS 0.
  LOCAL timeNMinusTwo IS time.
  LOCAL pNMinusOne IS 0.
  LOCAL pNMinusTwo IS p.

  SET logMe[12] TO logMe[12] + p + ",".
  SET logMe[13] TO logMe[13] + a + ",".
  SET logMe[14] TO logMe[14] + motionType + ",".
  SET logMe[15] TO logMe[15] + f + ",".
  SET logMe[16] TO logMe[16] + g + ",".
  SET logMe[17] TO logMe[17] + f_dot + ",".
  SET logMe[18] TO logMe[18] + deltaAngle*CONSTANT:DegToRad + ",".
  SET logMe[19] TO logMe[19] + time + ",".
  SET logMe[20] TO logMe[20] + timeError + ",".
  SET logMe[21] TO logMe[21] + "-1,".

  SET p TO (p_ii - p_i) * pStart2 + p_i.
  SET a TO m * k * p / (( 2 * m - l^2) * p^2 + 2 * k * l * p - k^2).
  IF a < 0 SET motionType TO "Hyperbola".
  ELSE SET motionType TO "Ellipse".
  SET f TO 1 - r_2_mag / p * ( 1 - COS(phaseAngle)).
  SET g TO r_1_mag * r_2_mag * SIN(phaseAngle) / SQRT(mu * p).
  SET f_dot TO SQRT(mu / p) * TAN(phaseAngle / 2) * ((1 - COS(phaseAngle)) / p - 1 / r_1_mag - 1 / r_2_mag).
  IF motionType = "Ellipse" {
    SET deltaAngle TO ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET time TO g + SQRT( a^3 / mu) * ( deltaAngleRad - SIN(deltaAngle)).
  } ELSE {
    SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET time TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngleRad).
  }

  SET timeError TO timeOfFlight - time.
  pList:ADD(p).
  tList:ADD(time).
  SET timeNMinusOne TO time.
  SET pNMinusOne TO p.

  SET logMe[12] TO logMe[12] + p + ",".
  SET logMe[13] TO logMe[13] + a + ",".
  SET logMe[14] TO logMe[14] + motionType + ",".
  SET logMe[15] TO logMe[15] + f + ",".
  SET logMe[16] TO logMe[16] + g + ",".
  SET logMe[17] TO logMe[17] + f_dot + ",".
  SET logMe[18] TO logMe[18] + deltaAngle*CONSTANT:DegToRad + ",".
  SET logMe[19] TO logMe[19] + time + ",".
  SET logMe[20] TO logMe[20] + timeError + ",".
  SET logMe[21] TO logMe[21] + "0,".

  LOCAL pStep IS 0.

  UNTIL (ABS(timeError) < timeTolerance) OR (iterations >= maxIterations) {
    SET timeNMinusOne TO tList[tList:LENGTH - 1].
    SET timeNMinusTwo TO tList[tList:LENGTH - 2].
    SET pNMinusOne TO pList[pList:LENGTH - 1].
    SET pNMinusTwo TO pList[pList:LENGTH - 2].
    PRINT " ".
    PRINT "P: " + p.
    PRINT "Time Of Flight: " + timeOfFlight.
    PRINT "Time N Minus One: " + timeNMinusOne.
    PRINT "Time N Minus Two: " + timeNMinusTwo.
    PRINT "P N Minus One: " + pNMinusOne.
    PRINT "P N Minus Two: " + pNMinusTwo.
    PRINT "Starting Iteration " + iterations + " timeError: " + ROUND(ABS(timeError)).
    SET pStep TO (timeOfFlight - timeNMinusOne) * (pNMinusOne - pNMinusTwo) / (timeNMinusOne - timeNMinusTwo).
    SET p TO pNMinusOne + pStep.
    IF (phaseAngle >= 180) AND ((p > p_ii) OR (p < 0))
      RETURN gaussProblemPIteration(r_1, r_2, timeOfFlight, mu, shortWay, timeTolerance, maxIterations - 1, MIN(pStart1 + 0.1, 1), pStart2).
    IF (phaseAngle < 180) AND (p < p_i)
      RETURN gaussProblemPIteration(r_1, r_2, timeOfFlight, mu, shortWay, timeTolerance, maxIterations - 1, pStart1, MIN(pStart2 + 0.1, 1)).
    PRINT "New P: " + p.
    SET a TO m * k * p / (( 2 * m - l^2) * p^2 + 2 * k * l * p - k^2).
    IF a < 0 SET motionType TO "Hyperbola".
    ELSE SET motionType TO "Ellipse".
    SET f TO 1 - r_2_mag / p * ( 1 - COS(phaseAngle)).
    SET g TO r_1_mag * r_2_mag * SIN(phaseAngle) / SQRT(mu * p).
    SET f_dot TO SQRT(mu / p) * TAN(phaseAngle / 2) * ((1 - COS(phaseAngle)) / p - 1 / r_1_mag - 1 / r_2_mag).
    IF motionType = "Ellipse" {
      SET deltaAngle TO ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
      SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
      SET time TO g + SQRT( a^3 / mu) * ( deltaAngleRad - SIN(deltaAngle)).
    } ELSE {
      // Note that the hyperbolic functions don't really use traditional angles, so no unit conversion is needed.
      SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
      SET deltaAngleRad TO deltaAngle * 1.
      SET time TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngleRad).
    }
    SET timeError TO timeOfFlight - time.
    pList:ADD(p).
    tList:ADD(time).
    SET iterations TO iterations + 1.

    SET logMe[12] TO logMe[12] + p + ",".
    SET logMe[13] TO logMe[13] + a + ",".
    SET logMe[14] TO logMe[14] + motionType + ",".
    SET logMe[15] TO logMe[15] + f + ",".
    SET logMe[16] TO logMe[16] + g + ",".
    SET logMe[17] TO logMe[17] + f_dot + ",".
    SET logMe[18] TO logMe[18] + deltaAngle*CONSTANT:DegToRad + ",".
    SET logMe[19] TO logMe[19] + time + ",".
    SET logMe[20] TO logMe[20] + timeError + ",".
    SET logMe[21] TO logMe[21] + iterations + ",".
    FOR message IN logMe {
      LOG message TO logFileName.
    }
  }
  LOCAL g_dot IS 1 - a / r_2_mag * ( 1 - COS( deltaAngle )).
  LOCAL v_1 IS (r_2 - f * r_1) / g.
  LOCAL v_2 IS f_dot * r_1 + g_dot * v_1.
  RETURN LIST(v_1, v_2, motionType, iterations, p).
}

FUNCTION C_Z {
  PARAMETER z.
  IF z = 0 RETURN 0.5.
  IF z < 0 RETURN (COSH(SQRT(-z))-1)/(-z).
  RETURN (1-COS(CONSTANT:RadToDeg * SQRT(z)))/z.
}

FUNCTION S_Z {
  PARAMETER z.
  IF z = 0 RETURN 1.0/6.0.
  IF z < 0 RETURN (SINH(SQRT(-z))-SQRT(-z))/(-z)^1.5.
  RETURN (SQRT(z)-SIN(CONSTANT:RadToDeg * SQRT(z)))/z^1.5.
}

FUNCTION C_Z_prime {
  PARAMETER z.
  PARAMETER C_of_Z IS C_Z(z).
  PARAMETER S_of_Z IS S_Z(z).
  IF ABS(z) < 0.05 RETURN -1/24 + 2 * z / 720 - 3 * z^2 / 40320 + 4 * z^3 / 3628800 - 5 * z^2 / 479001600 + 6 * z^3 / 87178291200.
  RETURN (1 - z * S_of_Z - 2 * C_of_Z) / ( 2 * z ).
}

FUNCTION S_Z_prime {
  PARAMETER z.
  PARAMETER C_of_Z IS C_Z(z).
  PARAMETER S_of_Z IS S_Z(z).
  IF ABS(z) < 0.05 RETURN -1 / 120 + 2 * z / 5040 - 3 * z^2 / 362880 + 4 * z^3 / 39916800 - 5 * z^2 / 6227020800 + 6 * z^3 / 1.30767E+12.
  RETURN (C_of_Z-3*S_of_Z)/(2*z).
}

FUNCTION gaussProblemUniversalVariables {
  PARAMETER r_1.
  PARAMETER r_2.
  PARAMETER timeOfFlight.
  PARAMETER mu.
  PARAMETER shortWay IS TRUE.
  PARAMETER timeTolerance IS 0.001.         // Default tolerance of 0.001 second
  PARAMETER maxIterations IS 50.

  LOCAL iterations IS 0.
  LOCAL r_1_mag IS r_1:MAG.
  LOCAL r_2_mag IS r_2:MAG.
  LOCAL phaseAngle IS VANG(r_1, r_2).
  IF phaseAngle > 180 SET phaseAngle TO 360 - phaseAngle.
  IF NOT shortWay SET phaseAngle TO 360 - phaseAngle.
  LOCAL phaseAngleRad IS phaseAngle * CONSTANT:RadToDeg.
  LOCAL A IS SQRT( r_1_mag * r_2_mag * ( 1 + COS(phaseAngle))).
  IF NOT shortWay SET A TO -A.

  LOCAL logMe IS LIST().
  logMe:ADD(",X,Y,Z,Magnitude,Units,Short Way," + shortWay).
  logMe:ADD("R_1," + r_1:X + "," + r_1:y + "," + r_1:z + "," + r_1_mag + ",meters").
  logMe:ADD("R_2," + r_2:X + "," + r_2:y + "," + r_2:z + "," + r_2_mag + ",meters").
  logMe:ADD("Desired Time," + timeOfFlight + ",s," + timeToString(timeOfFlight)).
  logMe:ADD("mu," + mu).
  logMe:ADD("phaseAngle," + phaseAngle*CONSTANT:DegToRad + "," + phaseAngle).
  logMe:ADD("").
  logMe:ADD("z,").              //07
  logMe:ADD("C(z),").           //08
  logMe:ADD("S(z),").           //09
  logMe:ADD("y,").              //10
  logMe:ADD("x,").              //11
  logMe:ADD("Time,").           //12
  logMe:ADD("dt/dz,").          //13
  logMe:ADD("C'(z),").          //14
  logMe:ADD("S'(z),").          //15
  logMe:ADD("Time Error,").     //16
  logMe:ADD("Iterations,").     //17
  logMe:ADD("f,").              //18
  logMe:ADD("g,").              //19
  logMe:ADD("g_dot,").          //20
  logMe:ADD("A," + A).          //21
  logMe:ADD("delta_v," + phaseAngle*CONSTANT:DegToRad + "," + phaseAngle).
  logMe:ADD(",X,Y,Z,Mag").      //23
  logMe:ADD("v_1,").            //24
  logMe:ADD("v_2,").            //25

  LOCAL startZ IS 0.5.
  LOCAL z IS 0.
  LOCAL S IS 0.
  LOCAL C IS 0.
  LOCAL y IS 0.
  LOCAL x IS 0.
  LOCAL time IS 0.
  LOCAL C_prime IS 0.
  LOCAL S_prime IS 0.
  LOCAL dt_dz IS 0.
  LOCAL timeError IS timeTolerance + 1.
  LOCAL firstTime IS TRUE.
  LOCAL failed IS FALSE.

  UNTIL (ABS(timeError) < timeTolerance) OR (iterations >= maxIterations) OR failed {
    IF firstTime {
      SET z TO startZ.
      SET firstTime TO FALSE.
    } ELSE SET z TO z - ( time - timeOfFlight) / dt_dz.
    SET S TO S_Z(z).
    SET C TO C_Z(z).
    SET y TO r_1_mag + r_2_mag - A*(1 - z * S ) / SQRT( C ).
    IF y > 0 {
      SET x TO SQRT( y / C ).
      SET time TO (( x^3 ) * S + A * SQRT( y )) / SQRT( mu ).
      SET C_prime TO C_Z_prime(z, C, S).
      SET S_prime TO S_Z_prime(z, C, S).
      SET dt_dz TO (x^3 * (S_prime - 3 * S * C_prime / ( 2 * C) ) + A / 8 * ( 3 * S * SQRT( y ) / C + A / x)) / SQRT(mu).
      SET timeError TO timeOfFlight - time.
      SET logMe[07] TO logMe[07] + z + ",".
      SET logMe[08] TO logMe[08] + C + ",".
      SET logMe[09] TO logMe[09] + S + ",".
      SET logMe[10] TO logMe[10] + y + ",".
      SET logMe[11] TO logMe[11] + x + ",".
      SET logMe[12] TO logMe[12] + time + ",".
      SET logMe[13] TO logMe[13] + dt_dz + ",".
      SET logMe[14] TO logMe[14] + C_prime + ",".
      SET logMe[15] TO logMe[15] + S_prime + ",".
      SET logMe[16] TO logMe[16] + timeError + ",".
      SET logMe[17] TO logMe[17] + iterations + ",".
      SET iterations TO iterations + 1.
    } ELSE SET failed TO TRUE.
  }

  IF failed OR (iterations >= maxIterations) RETURN LIST(V(0,0,0), V(0,0,0), "Failed", iterations, 0).

  LOCAL f IS 1 - y / r_1_mag.
  LOCAL g IS A * SQRT( y / mu).
  LOCAL g_dot IS 1 - y / r_2_mag.
  LOCAL v_1 IS (r_2 - f * r_1) / g.
  LOCAL v_2 IS (g_dot * r_2 - r_1) / g.
  LOCAL ecc IS (((v_1:SQRMAGNITUDE - mu / r_1_mag) * r_1 - VDOT( r_1 , v_1 ) * v_1 ) / mu):MAG.
  LOCAL motionType IS "none".
  IF ecc >= 1 SET motionType TO "Hyperbola".
  ELSE SET motionType TO "Ellipse".
  SET logMe[18] TO logMe[18] + f + ",".
  SET logMe[19] TO logMe[19] + g + ",".
  SET logMe[20] TO logMe[20] + g_dot + ",".
  SET logMe[24] TO logMe[24] + v_1:X + "," + v_1:Y + "," + v_1:Z + "," + v_1:MAG.
  SET logMe[25] TO logMe[25] + v_2:X + "," + v_2:Y + "," + v_2:Z + "," + v_2:MAG.
//  FOR message IN logMe {
//    LOG message TO logFileName.
//  }
  RETURN LEXICON(v_1, v_2, motionType, iterations, z).
}

LOCAL targetBody IS BODY(desiredBody).
LOCAL synodicPeriod IS 1 / ABS((1 / targetBody:ORBIT:PERIOD) - (1 / BODY:ORBIT:PERIOD)).
LOCAL startTravelTime IS BODY:ORBIT:PERIOD / 2.0.
LOCAL endTravelTime IS startTravelTime + synodicPeriod / 4.
LOCAL travelTimeInterval IS synodicPeriod / 400.

LOCAL sunBody IS BODY("Kerbin").
LOCAL sunPos IS sunBody:POSITION.
LOCAL sunMU IS sunBody:MU.
LOCAL r_1 IS SHIP:BODY:POSITION - sunPos.
LOCAL r_2 IS targetBody:POSITION - sunPos.
LOCAL phaseAngle IS VANG(r_1, r_2).
LOCAL phaseAngleRad IS phaseAngle * CONSTANT:RadToDeg.
LOCAL mu IS 1.
LOCAL timeOfFlight IS 1.
LOCAL vectors IS 0.

LOCAL timeStamp IS TIME(116941814.5).
LOCAL startTime IS TIME(116941814.5).

SET r_1 TO POSITIONAT(SHIP:BODY, timeStamp) - POSITIONAT(sunBody, timeStamp).
SET r_2 TO POSITIONAT(targetBody, timeStamp) - POSITIONAT(sunBody, timeStamp).
SET mu TO sunMU.
SET timeOfFlight TO synodicPeriod.

LOCAL plotData IS LIST().
LOCAL startPlanetMotion IS VELOCITYAT(SHIP:BODY, timeStamp):ORBIT.
LOCAL endPlanetMotion IS VELOCITYAT(BODY("Minmus"), timeStamp):ORBIT.
LOCAL timeOfFlight IS 0.
LOCAL singleTrajectoryData IS LIST().
FOR timeOffset IN RANGE(0, 25, 1) {
  SET timeStamp TO startTime + (timeOffset / 10) * synodicPeriod.
  SET r_1 TO POSITIONAT(SHIP:BODY, timeStamp) - POSITIONAT(sunBody, timeStamp).
  SET r_2 TO POSITIONAT(targetBody, timeStamp) - POSITIONAT(sunBody, timeStamp).
  SET startPlanetMotion TO VELOCITYAT(SHIP:BODY, timeStamp):ORBIT.
  SET endPlanetMotion TO VELOCITYAT(BODY("Minmus"), timeStamp):ORBIT.
  FOR number IN RANGE(0, 120) {
    PRINT "Calculating flight number " + number + " for time offset " + timeToString(timeOffset / 10 * synodicPeriod).
    SET timeOfFlight TO synodicPeriod * (number / 8 + 1).
    SET singleTrajectoryData TO gaussProblemUniversalVariables(r_1, r_2, timeOfFlight, mu).
    // Index 0 - v_1
    // Index 1 - v_2
    // Index 2 - motionType
    // Index 3 - iterations
    // Index 4 - z
    singleTrajectoryData:ADD((startPlanetMotion - singleTrajectoryData[0]):MAG).              //Index 5 is start DeltaV
    singleTrajectoryData:ADD((endPlanetMotion - singleTrajectoryData[1]):MAG).                //Index 6 is end DeltaV
    IF singleTrajectoryData[]
    singleTrajectoryData:ADD(timeStamp).                                                      //Index 7 is timeStamp
    singleTrajectoryData:ADD(timeOfFlight).                                                   //Index 8 is timeOfFlight
    plotData:ADD(singleTrajectoryData).
  }
}

LOG "z,Starting dV,Ending dV,Total dV,Motion Type,Iterations,TimeStamp,TimeOfFlight" TO logFileName.
FOR singleTrajectory IN plotData {
  LOG singleTrajectory[4] + "," +
      singleTrajectory[5] + "," +
      singleTrajectory[6] + "," +
      (singleTrajectory[5] + singleTrajectory[6]) + "," +
      singleTrajectory[2] + "," +
      singleTrajectory[3] + "," +
      singleTrajectory[7] + "," +
      singleTrajectory[8] + "," TO logFileName.
}

//PRINT "".
//PRINT "Starting book problem".
//SET r_1 TO V(0.5, 0.6, 0.7).
//SET r_2 TO V(0, 1, 0).
//SET mu TO 1.
//SET timeOfFlight TO 0.96692456.
//gaussProblemPIteration(r_1, r_2, timeOfFlight, mu).

//PRINT "".
//PRINT "Starting Braeunig problem".
//SET r_1 TO V(0.473265, -0.899215, 0).
//SET r_2 TO V(0.066842, 1.561256, 0.030948).
//SET mu TO 3.964016E-14.
//SET timeOfFlight TO 17884800.
//gaussProblemPIteration(r_1, r_2, timeOfFlight, mu).
PRINT "Complete".
WAIT 1.
