@LAZYGLOBAL OFF.
CLEARSCREEN.

FUNCTION firstCommonBody {
  PARAMETER objectOne.
  PARAMETER objectTwo.
  LOCAL object1Bodies IS LIST().
  UNTIL NOT objectOne:HASBODY {object1Bodies:ADD(objectOne:NAME). SET objectOne TO objectOne:BODY.}
  UNTIL NOT objectTwo:HASBODY {
    FOR eachBodyName IN object1Bodies {
      IF object1Bodies:CONTAINS(objectTwo:NAME) RETURN BODY(objectTwo:NAME).
    }
    SET objectTwo TO objectTwo:BODY.
  }
  RETURN BODY("Sun").
}

FUNCTION gaussProblemPIteration {
  PARAMETER r_1.
  PARAMETER r_2.
  PARAMETER timeOfFlight.
  PARAMETER mu.
  PARAMETER shortWay IS TRUE.
  PARAMETER timeTolerance IS 0.001.         // Default tolerance of 0.001 second
  PARAMETER maxIterations IS 20.
  PARAMETER logAllowed IS FALSE.
  PARAMETER pStart1 IS 0.05.
  PARAMETER pStart2 IS 0.2.

  // Start off by calculating the various constants associated with the problem.
  LOCAL phaseAngle IS VANG(r_1, r_2).
  IF phaseAngle > 180 SET phaseAngle TO 360 - phaseAngle.
  IF NOT shortWay SET phaseAngle TO 360 - phaseAngle.
  LOCAL phaseAngleRad IS phaseAngle * CONSTANT:RadToDeg.
  LOCAL r_1_mag IS r_1:MAG.
  LOCAL r_2_mag IS r_2:MAG.
  LOCAL k IS r_1_mag*r_2_mag*(1-COS(phaseAngle)).
  LOCAL l IS r_1_mag+r_2_mag.
  LOCAL m IS r_1_mag*r_2_mag*(1+COS(phaseAngle)).
  LOCAL p_i IS k/(l+SQRT(2*m)).
  LOCAL p_ii IS k/(l-SQRT(2*m)).

  LOCAL logMe IS LIST().
  IF logAllowed {
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
  }

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
  LOCAL timeSeconds IS 0.
  LOCAL timeError IS timeTolerance + 1.0.
  IF motionType = "Ellipse" {
    SET deltaAngle TO ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET timeSeconds TO g + SQRT( a^3 / mu) * ( deltaAngleRad - SIN(deltaAngle)).
  } ELSE {
    SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET timeSeconds TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngleRad).
  }
  SET timeError TO timeOfFlight - timeSeconds.
  pList:ADD(p).
  tList:ADD(timeSeconds).

  LOCAL iterations IS 0.
  LOCAL timeNMinusOne IS 0.
  LOCAL timeNMinusTwo IS timeSeconds.
  LOCAL pNMinusOne IS 0.
  LOCAL pNMinusTwo IS p.

  IF logAllowed {
    SET logMe[12] TO logMe[12] + p + ",".
    SET logMe[13] TO logMe[13] + a + ",".
    SET logMe[14] TO logMe[14] + motionType + ",".
    SET logMe[15] TO logMe[15] + f + ",".
    SET logMe[16] TO logMe[16] + g + ",".
    SET logMe[17] TO logMe[17] + f_dot + ",".
    SET logMe[18] TO logMe[18] + deltaAngle*CONSTANT:DegToRad + ",".
    SET logMe[19] TO logMe[19] + timeSeconds + ",".
    SET logMe[20] TO logMe[20] + timeError + ",".
    SET logMe[21] TO logMe[21] + "-1,".
  }

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
    SET timeSeconds TO g + SQRT( a^3 / mu) * ( deltaAngleRad - SIN(deltaAngle)).
  } ELSE {
    SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
    SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
    SET timeSeconds TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngleRad).
  }

  SET timeError TO timeOfFlight - timeSeconds.
  pList:ADD(p).
  tList:ADD(timeSeconds).
  SET timeNMinusOne TO timeSeconds.
  SET pNMinusOne TO p.

  IF logAllowed {
    SET logMe[12] TO logMe[12] + p + ",".
    SET logMe[13] TO logMe[13] + a + ",".
    SET logMe[14] TO logMe[14] + motionType + ",".
    SET logMe[15] TO logMe[15] + f + ",".
    SET logMe[16] TO logMe[16] + g + ",".
    SET logMe[17] TO logMe[17] + f_dot + ",".
    SET logMe[18] TO logMe[18] + deltaAngle*CONSTANT:DegToRad + ",".
    SET logMe[19] TO logMe[19] + timeSeconds + ",".
    SET logMe[20] TO logMe[20] + timeError + ",".
    SET logMe[21] TO logMe[21] + "0,".
  }

  LOCAL pStep IS 0.

  UNTIL (ABS(timeError) < timeTolerance) OR (iterations >= maxIterations) {
    SET timeNMinusOne TO tList[tList:LENGTH - 1].
    SET timeNMinusTwo TO tList[tList:LENGTH - 2].
    SET pNMinusOne TO pList[pList:LENGTH - 1].
    SET pNMinusTwo TO pList[pList:LENGTH - 2].
    SET pStep TO (timeOfFlight - timeNMinusOne) * (pNMinusOne - pNMinusTwo) / (timeNMinusOne - timeNMinusTwo).
    SET p TO pNMinusOne + pStep.
    IF (phaseAngle >= 180) AND ((p > p_ii) OR (p < 0))
      RETURN gaussProblemPIteration(r_1, r_2, timeOfFlight, mu, shortWay, timeTolerance, maxIterations - 1, logAllowed, MIN(pStart1 + 0.1, 1), pStart2).
    IF (phaseAngle < 180) AND (p < p_i)
      RETURN gaussProblemPIteration(r_1, r_2, timeOfFlight, mu, shortWay, timeTolerance, maxIterations - 1, logAllowed, pStart1, MIN(pStart2 + 0.1, 1)).
    SET a TO m * k * p / (( 2 * m - l^2) * p^2 + 2 * k * l * p - k^2).
    IF a < 0 SET motionType TO "Hyperbola".
    ELSE SET motionType TO "Ellipse".
    SET f TO 1 - r_2_mag / p * ( 1 - COS(phaseAngle)).
    SET g TO r_1_mag * r_2_mag * SIN(phaseAngle) / SQRT(mu * p).
    SET f_dot TO SQRT(mu / p) * TAN(phaseAngle / 2) * ((1 - COS(phaseAngle)) / p - 1 / r_1_mag - 1 / r_2_mag).
    IF motionType = "Ellipse" {
      SET deltaAngle TO ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
      SET deltaAngleRad TO deltaAngle * CONSTANT:DegToRad.
      SET timeSeconds TO g + SQRT( a^3 / mu) * ( deltaAngleRad - SIN(deltaAngle)).
    } ELSE {
      // Note that the hyperbolic functions don't really use traditional angles, so no unit conversion is needed.
      SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
      SET deltaAngleRad TO deltaAngle * 1.
      SET timeSeconds TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngleRad).
    }
    SET timeError TO timeOfFlight - timeSeconds.
    pList:ADD(p).
    tList:ADD(timeSeconds).
    SET iterations TO iterations + 1.

    IF logAllowed {
      SET logMe[12] TO logMe[12] + p + ",".
      SET logMe[13] TO logMe[13] + a + ",".
      SET logMe[14] TO logMe[14] + motionType + ",".
      SET logMe[15] TO logMe[15] + f + ",".
      SET logMe[16] TO logMe[16] + g + ",".
      SET logMe[17] TO logMe[17] + f_dot + ",".
      SET logMe[18] TO logMe[18] + deltaAngle*CONSTANT:DegToRad + ",".
      SET logMe[19] TO logMe[19] + timeSeconds + ",".
      SET logMe[20] TO logMe[20] + timeError + ",".
      SET logMe[21] TO logMe[21] + iterations + ",".
      FOR message IN logMe {
        LOG message TO logFileName.
      }
    }
  }
  LOCAL g_dot IS 1 - a / r_2_mag * ( 1 - COS( deltaAngle )).
  LOCAL v_1 IS (r_2 - f * r_1) / g.
  LOCAL v_2 IS f_dot * r_1 + g_dot * v_1.
  RETURN LEXICON("v_1", v_1,
                 "v_2", v_2,
                 "Motion Type", motionType,
                 "Iterations", iterations,
                 "Final Value", p,
                 "r_1", r_1,
                 "r_2", r_2,
                 "mu", mu,
                 "Short Way", shortWay).
}

FUNCTION C_Z {
  PARAMETER z.
  IF z = 0 RETURN 0.5.
  IF z < 0 RETURN (COSH(SQRT(-z))-1)/(-z).
  IF z > 1e10 RETURN 1.99936080743821e-10.
  RETURN (1-COS(CONSTANT:RadToDeg * SQRT(z)))/z.
}

FUNCTION S_Z {
  PARAMETER z.
  IF z = 0 RETURN 1.0/6.0.
  IF z < 0 RETURN (SINH(SQRT(-z)) - SQRT(-z)) / (-z)^1.5.
  RETURN (SQRT(z) - SIN(CONSTANT:RadToDeg * SQRT(z))) / z^1.5.
}

FUNCTION C_Z_prime {
  PARAMETER z.
  PARAMETER C_of_Z IS C_Z(z).
  PARAMETER S_of_Z IS S_Z(z).
  IF ABS(z) < 0.05 RETURN -1/24 + 2 * z / 720 - 3 * z^2 / 40320 + 4 * z^3 / 3628800 - 5 * z^4 / 479001600 + 6 * z^5 / 87178291200.
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
  PARAMETER timeTolerance IS 0.001.         // Default tolerance in seconds
  PARAMETER maxIterations IS 40.
  PARAMETER logAllowed IS FALSE.
  PARAMETER startZ IS 0.5.

  IF startZ > 10 RETURN LEXICON("v_1", V(0, 0, 0),
                                "v_2", V(0, 0, 0),
                                "Motion Type", "Failed",
                                "Iterations", 0,
                                "Final Value", 0,
                                "r_1", r_1,
                                "r_2", r_2,
                                "mu", mu,
                                "Short Way", shortWay).


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
  IF logAllowed {
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
  }

  LOCAL z IS 0.
  LOCAL S IS 0.
  LOCAL C IS 0.
  LOCAL y IS 0.
  LOCAL x IS 0.
  LOCAL timeSeconds IS 0.
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
    } ELSE {
      IF dt_dz = 0 SET z TO z + 1.
      ELSE SET z TO z - ( timeSeconds - timeOfFlight) / dt_dz.
      IF z > (4*CONSTANT:PI)^2 SET failed TO TRUE.
    }
    SET S TO S_Z(z).
    SET C TO C_Z(z).
    IF SQRT(C) <> 0 SET y TO r_1_mag + r_2_mag - A*(1 - z * S ) / SQRT( C ).
    ELSE SET y TO -1.
    IF (y > 0) AND (C < 1e10) AND (S < 1e10) {
      SET x TO SQRT( y / C ).
      SET timeSeconds TO (( x^3 ) * S + A * SQRT( y )) / SQRT( mu ).
      SET C_prime TO C_Z_prime(z, C, S).
      SET S_prime TO S_Z_prime(z, C, S).
      SET dt_dz TO (x^3 * (S_prime - 3 * S * C_prime / ( 2 * C) ) + A / 8 * ( 3 * S * SQRT( y ) / C + A / x)) / SQRT(mu).
      SET timeError TO timeOfFlight - timeSeconds.
      IF logAllowed {
        SET logMe[07] TO logMe[07] + z + ",".
        SET logMe[08] TO logMe[08] + C + ",".
        SET logMe[09] TO logMe[09] + S + ",".
        SET logMe[10] TO logMe[10] + y + ",".
        SET logMe[11] TO logMe[11] + x + ",".
        SET logMe[12] TO logMe[12] + timeSeconds + ",".
        SET logMe[13] TO logMe[13] + dt_dz + ",".
        SET logMe[14] TO logMe[14] + C_prime + ",".
        SET logMe[15] TO logMe[15] + S_prime + ",".
        SET logMe[16] TO logMe[16] + timeError + ",".
        SET logMe[17] TO logMe[17] + iterations + ",".
      }
      SET iterations TO iterations + 1.
    } ELSE SET failed TO TRUE.
  }

  IF (failed OR (iterations >= maxIterations)) RETURN gaussProblemUniversalVariables(r_1,
                                                                                     r_2,
                                                                                     timeOfFlight,
                                                                                     mu,
                                                                                     shortWay,
                                                                                     timeTolerance,
                                                                                     maxIterations,
                                                                                     logAllowed,
                                                                                     startZ + 1).

  LOCAL f IS 1 - y / r_1_mag.
  LOCAL g IS A * SQRT( y / mu).
  LOCAL g_dot IS 1 - y / r_2_mag.
  LOCAL v_1 IS (r_2 - f * r_1) / g.
  LOCAL v_2 IS (g_dot * r_2 - r_1) / g.
  LOCAL ecc IS (((v_1:SQRMAGNITUDE - mu / r_1_mag) * r_1 - VDOT( r_1 , v_1 ) * v_1 ) / mu):MAG.
  LOCAL motionType IS "none".
  IF ecc >= 1 SET motionType TO "Hyperbola".
  ELSE SET motionType TO "Ellipse".
  IF logAllowed {
    SET logMe[18] TO logMe[18] + f + ",".
    SET logMe[19] TO logMe[19] + g + ",".
    SET logMe[20] TO logMe[20] + g_dot + ",".
    SET logMe[24] TO logMe[24] + v_1:X + "," + v_1:Y + "," + v_1:Z + "," + v_1:MAG.
    SET logMe[25] TO logMe[25] + v_2:X + "," + v_2:Y + "," + v_2:Z + "," + v_2:MAG.
    FOR message IN logMe {
      LOG message TO logFileName.
    }
  }
  RETURN LEXICON("v_1", v_1,
                 "v_2", v_2,
                 "Motion Type", motionType,
                 "Iterations", iterations,
                 "Final Value", z,
                 "r_1", r_1,
                 "r_2", r_2,
                 "mu", mu,
                 "Short Way", shortWay).
}


PARAMETER fromBodyName IS "Kerbin".
PARAMETER toBodyName IS "Duna".
PARAMETER desiredOrbitAlt IS 100.

IF desiredOrbitAlt < 0 SET desiredOrbitAlt TO 0.

LOCAL errorCode IS "None".

IF NOT BODYEXISTS(fromBodyName) SET errorCode TO fromBodyName + " does not exist!".
IF NOT BODYEXISTS(toBodyName) SET errorCode TO toBodyName + " does not exist!".

IF errorCode = "None" {IF BODY(fromBodyName):BODY:NAME <> BODY(toBodyName):BODY:NAME SET errorCode TO "Bodies must have the same parent!".}

IF errorCode = "None" {
  LOCAL fromBody IS BODY(fromBodyName).
  LOCAL toBody IS BODY(toBodyName).
  LOCAL sunBody IS firstCommonBody(fromBody, toBody).

  LOCAL logFileName IS "0:gaussProblem.csv".
  IF EXISTS(logFileName) DELETEPATH(logFileName).


  LOCAL synodicPeriod IS 1 / ABS((1 / fromBody:ORBIT:PERIOD) - (1 / toBody:ORBIT:PERIOD)).

  LOCAL sunPos IS sunBody:POSITION.
  LOCAL sunMU IS sunBody:MU.
  LOCAL r_1 IS V(0, 0, 0).
  LOCAL r_2 IS V(0, 0, 0).

  LOCAL timeStampNew IS TIME(116941814.5).
  LOCAL startTime IS TIME. //TIME(TIME:SECONDS).

  LOCAL plotData IS LIST().
  LOCAL fromBodyVelocity IS 0.
  LOCAL toBodyVelocity IS 0.
  LOCAL timeOfFlight IS 0.
  LOCAL singleTrajectoryData IS LEXICON().
  LOCAL successRate IS LEXICON().
  LOCAL totalFlights TO 0.
  LOCAL maxDeltaV IS 0.
  LOCAL minDeltaV IS 1000000000.
  LOCAL shortWay IS TRUE.
  LOCAL shortTrajectory IS 0.
  LOCAL longTrajectory IS 0.
  LOCAL motionTypeNumber IS 0.

  LOG "Time from Now,Universal Time,Time of Flight,From X Pos,From Y Pos,From Z Pos,From Pos Mag,To X Pos,To Y Pos,To Z Pos,R2 Pos Mag,From X Vel,From Y Vel,From Z Vel,From Vel Mag,To X Vel,To Y Vel,To Z Vel,To Vel Mag,TimeOfFlight,mu,V1 X,V1 Y,V1 Z,V1 Mag,V2 X,V2 Y,V2 Z,V2 Mag,z,Starting dV,End dV,Total dV,Motion Type,Motion Type Number,Iterations,TimeStamp,TimeOfFlight,Short Way" TO logFileName.

  // Time Offset is offset in time from now, in units hundredths of the synodic period of the two bodies
  FOR timeOffset IN RANGE(0, 301, 5) {
    SET timeStampNew TO startTime + (timeOffset / 100) * synodicPeriod.
    SET r_1 TO absolutePosition(fromBody, timeStampNew) - absolutePosition(sunBody, timeStampNew).
    SET r_2 TO absolutePosition(toBody, timeStampNew) - absolutePosition(sunBody, timeStampNew).
    SET fromBodyVelocity TO absoluteVelocity(fromBody, timeStampNew) - absoluteVelocity(sunBody, timeStampNew).
    SET toBodyVelocity TO absoluteVelocity(toBody, timeStampNew) - absoluteVelocity(sunBody, timeStampNew).
    // Number is time of flight in hundredths of the synodic period
    FOR number IN RANGE(30, 151, 5) {
      SET timeOfFlight TO synodicPeriod * ((number) / 100).
      PRINT "Calculating departure " + (timeOffset / 100) + " periods, flight time " + ((number) / 100) + " periods.".
      SET shortWay TO VCRS(r_1, r_2):Z < 0.
      SET shortTrajectory TO gaussProblemUniversalVariables(r_1, r_2, timeOfFlight, sunMU, TRUE).
      SET longTrajectory TO gaussProblemUniversalVariables(r_1, r_2, timeOfFlight, sunMU, FALSE).
      IF (shortTrajectory["Motion Type"] = "Failed") OR (((fromBodyVelocity - shortTrajectory["v_1"]):MAG + (toBodyVelocity - shortTrajectory["v_2"]):MAG) < ((fromBodyVelocity - longTrajectory["v_1"]):MAG + (toBodyVelocity - longTrajectory["v_2"]):MAG)) {
        SET singleTrajectoryData TO shortTrajectory.
      } ELSE SET singleTrajectoryData TO longTrajectory.
  //    SET singleTrajectoryData TO gaussProblemPIteration(r_1, r_2, timeOfFlight, sunMU).
      SET maxDeltaV TO MAX(maxDeltaV, (fromBodyVelocity - singleTrajectoryData["v_1"]):MAG + (toBodyVelocity - singleTrajectoryData["v_2"]):MAG).
      SET minDeltaV TO MIN(minDeltaV, (fromBodyVelocity - singleTrajectoryData["v_1"]):MAG + (toBodyVelocity - singleTrajectoryData["v_2"]):MAG).
      IF singleTrajectoryData["Motion Type"] = "Failed" {
        singleTrajectoryData:ADD("Start Delta V", "").
        singleTrajectoryData:ADD("End Delta V", "").
        singleTrajectoryData:ADD("Total Delta V", "").
        singleTrajectoryData:ADD("Time Stamp", timeStampNew:SECONDS).
        singleTrajectoryData:ADD("Time Of Flight", timeOfFlight).
      } ELSE {
        singleTrajectoryData:ADD("Start Delta V", (fromBodyVelocity - singleTrajectoryData["v_1"]):MAG).
        singleTrajectoryData:ADD("End Delta V", (toBodyVelocity - singleTrajectoryData["v_2"]):MAG).
        singleTrajectoryData:ADD("Total Delta V", singleTrajectoryData["Start Delta V"] + singleTrajectoryData["End Delta V"]).
        singleTrajectoryData:ADD("Time Stamp", timeStampNew:SECONDS).
        singleTrajectoryData:ADD("Time Of Flight", timeOfFlight).
      }
      singleTrajectoryData:ADD("Time Offset", (timeOffset / 10) * synodicPeriod).
      singleTrajectoryData:ADD("Universal Time", timeStampNew:SECONDS).
      singleTrajectoryData:ADD("From Velocity", fromBodyVelocity).
      singleTrajectoryData:ADD("To Velocity", toBodyVelocity).
      IF NOT successRate:KEYS:CONTAINS(singleTrajectoryData["Motion Type"]) {
        successRate:ADD(singleTrajectoryData["Motion Type"], 1).
      } ELSE SET successRate[singleTrajectoryData["Motion Type"]] TO successRate[singleTrajectoryData["Motion Type"]] + 1.
      SET totalFlights TO totalFlights + 1.
//      plotData:ADD(singleTrajectoryData).

      SET motionTypeNumber TO 0.
      IF singleTrajectoryData["Motion Type"] = "Failed" SET motionTypeNumber TO 0.
      IF singleTrajectoryData["Motion Type"] = "Hyperbola" SET motionTypeNumber TO 1.
      IF singleTrajectoryData["Motion Type"] = "Ellipse" SET motionTypeNumber TO -1.
      LOG singleTrajectoryData["Time Offset"] + "," +
          singleTrajectoryData["Universal Time"] + "," +
          singleTrajectoryData["Time of Flight"] + "," +
          singleTrajectoryData["r_1"]:X + "," +
          singleTrajectoryData["r_1"]:Y + "," +
          singleTrajectoryData["r_1"]:Z + "," +
          singleTrajectoryData["r_1"]:mag + "," +
          singleTrajectoryData["r_2"]:X + "," +
          singleTrajectoryData["r_2"]:Y + "," +
          singleTrajectoryData["r_2"]:Z + "," +
          singleTrajectoryData["r_2"]:mag + "," +
          singleTrajectoryData["From Velocity"]:X + "," +
          singleTrajectoryData["From Velocity"]:Y + "," +
          singleTrajectoryData["From Velocity"]:Z + "," +
          singleTrajectoryData["From Velocity"]:mag + "," +
          singleTrajectoryData["To Velocity"]:X + "," +
          singleTrajectoryData["To Velocity"]:Y + "," +
          singleTrajectoryData["To Velocity"]:Z + "," +
          singleTrajectoryData["To Velocity"]:mag + "," +
          singleTrajectoryData["Time Of Flight"] + "," +
          singleTrajectoryData["mu"] + "," +
          singleTrajectoryData["v_1"]:X + "," +
          singleTrajectoryData["v_1"]:Y + "," +
          singleTrajectoryData["v_1"]:Z + "," +
          singleTrajectoryData["v_1"]:mag + "," +
          singleTrajectoryData["v_2"]:X + "," +
          singleTrajectoryData["v_2"]:Y + "," +
          singleTrajectoryData["v_2"]:Z + "," +
          singleTrajectoryData["v_2"]:mag + "," +
          singleTrajectoryData["Final Value"] + "," +
          singleTrajectoryData["Start Delta V"] + "," +
          singleTrajectoryData["End Delta V"] + "," +
          singleTrajectoryData["Total Delta V"] + "," +
          singleTrajectoryData["Motion Type"] + "," +
          motionTypeNumber + "," +
          singleTrajectoryData["Iterations"] + "," +
          ROUND((singleTrajectoryData["Time Stamp"] - startTime):SECONDS / synodicPeriod, 5) + "," +
          ROUND(singleTrajectoryData["Time Of Flight"] / synodicPeriod, 5) + "," +
          singleTrajectoryData["Short Way"] + "," TO logFileName.
        }
  }

  PRINT "Finished calculating trajectories, now logging them".

  LOG ",Count,Rate" TO logFileName.
  FOR motionType IN successRate:KEYS {
    LOG motionType + "," + successRate[motionType] + "," + (successRate[motionType] / totalFlights * 100) + "%" TO logFileName.
  }
  LOG "," + totalFlights + ",100%" TO logFileName.
  LOG "" TO logFileName.
  LOG "Synodic Period," + synodicPeriod + ",seconds,is," + timeToString(synodicPeriod) TO logFileName.
  LOG "Time Elapsed," + (time - startTime):SECONDS + ",seconds" TO logFileName.
  LOG "From," + fromBody:NAME + ",to," + toBody:NAME + ",going past," + sunBody:NAME TO logFileName.
  LOG "" TO logFileName.

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
  WAIT 0.5.
  SET loopMessage TO "Min dV between " + toBody:NAME + " and " + fromBody:NAME + " is " + distanceToString(minDeltaV) + "/s".
} ELSE SET loopMessage TO errorCode.
