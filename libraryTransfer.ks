@LAZYGLOBAL OFF.

// ============================================================================
// libraryTransfer.ks - total delta-V of an interplanetary transfer, in KSP's patched
// conic universe, plus the Lambert solvers and porkchop-plot tools it is built on. loop.ks loads it right after library.ks, which this
// file depends on (absolutePosition, absoluteVelocity, findZeroBrent, goldenSectionMinimum, ...).
// Moved here from library.ks: the Lambert solvers, solveBurnAtPoint and the departure-burn finders, the porkchop grid and CSV tools.
//
// The model, and what it approximates:
//   - Lambert (heliocentric) gives the velocity the ship needs when it LEAVES
//     the departure body's sphere of influence. That moment is tSOI ("T_SOI").
//     Relative to the departure body, that velocity (vExit) is the velocity at
//     the SOI edge - NOT the hyperbolic excess at infinity. The excess is
//     vInfinity = SQRT(|vExit|^2 - 2*mu/soiRadius), and the asymptote direction
//     differs a little from vExit's (the hyperbola is still turning at the edge).
//   - The burn happens EARLIER than tSOI, by the hyperbolic transit time from the
//     burn point to the SOI edge.
//   - Heliocentric position is taken at the body's centre (SOI-edge offset ignored).
//   - Arrival is treated the same way: the velocity at the destination SOI edge.
//
// Two cases for the departure orbit, both described by an "orbit spec":
//   "orbit"  - the ship is already in a parking orbit (orbitSpecFromVessel). The
//              ejection cost uses the real orbit - plane, shape and position.
//   "design" - the ship hasn't launched (designSpec). A circular parking orbit is
//              designed per transfer: plane chosen to contain the departure
//              asymptote, floored at the launch site latitude.
//
// Two ways to price the ejection:
//   phase-free (the default) - the cheapest burn point anywhere in one orbit. Smooth,
//              so it suits grid searches and hill climbs.
//   exact timing             - the burn point is dictated by tSOI (burn time = tSOI minus
//              transit). The cost then repeats with the parking-orbit period, so
//              use refineTransferTiming rather than a coarse search for this.
//
// All angles in kOS trig are degrees; times are seconds (UT where noted).
// ============================================================================

GLOBAL invalidDeltaV IS 1e15.

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
  IF NOT shortWay SET phaseAngle TO 360 - phaseAngle.
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
  LOCAL timeSeconds IS 0.
  LOCAL timeError IS timeTolerance + 1.0.
  IF motionType = "Ellipse" {
    SET deltaAngle TO CONSTANT:DegToRad * ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
    SET timeSeconds TO g + SQRT( a^3 / mu) * ( deltaAngle - SIN(deltaAngle)).
  } ELSE {
    SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
    SET timeSeconds TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngle).
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
    SET deltaAngle TO CONSTANT:DegToRad * ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
    SET timeSeconds TO g + SQRT( a^3 / mu) * ( deltaAngle - SIN(deltaAngle)).
  } ELSE {
    SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
    SET timeSeconds TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngle).
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
      SET deltaAngle TO CONSTANT:DegToRad * ARCTAN2( -r_1_mag * r_2_mag * f_dot / SQRT( mu * a ), 1 - r_1_mag / a * (1 - f)).
      SET timeSeconds TO g + SQRT( a^3 / mu) * ( deltaAngle - SIN(deltaAngle)).
    } ELSE {
      // Note that the hyperbolic functions don't really use traditional angles, so no unit conversion is needed.
      SET deltaAngle TO ACOSH( 1 - r_1_mag / a * ( 1 - f)).
      SET timeSeconds TO g + SQRT((-a)^3 / mu)*(SINH(deltaAngle) - deltaAngle).
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
  IF ABS(z) < 0.05 RETURN -1 / 120 + 2 * z / 5040 - 3 * z^2 / 362880 + 4 * z^3 / 39916800 - 5 * z^4 / 6227020800 + 6 * z^5 / 1.30767E+12.
  RETURN (C_of_Z-3*S_of_Z)/(2*z).
}

FUNCTION lambertGauss {
  PARAMETER r_1.
  PARAMETER r_2.
  PARAMETER timeOfFlight.
  PARAMETER mu.
  PARAMETER shortWay IS TRUE.
  PARAMETER startZ IS 0.5.
  PARAMETER timeTolerance IS 0.001.         // Default tolerance in seconds
  PARAMETER maxIterations IS 40.
  PARAMETER logAllowed IS FALSE.
  // startZ is the ANCHOR for the whole retry ladder below and stays fixed
  // across every retry. attemptNumber drives a zig-zag offset from that
  // fixed anchor: 0, +1, -1, +2, -2, +3, ... - trying the seed itself
  // first, then alternating outward in both directions, so a root on
  // either side of the seed is reachable.
  PARAMETER attemptNumber IS 0.

  IF attemptNumber >= 10 RETURN LEXICON("v_1", V(0, 0, 0),
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
  IF NOT shortWay SET phaseAngle TO 360 - phaseAngle.
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

  // The actual z this attempt starts Newton's method from - see the comment
  // on attemptNumber above for the zig-zag pattern this produces.
  LOCAL zToTry IS startZ.
  IF attemptNumber > 0 {
    LOCAL magnitude IS CEILING(attemptNumber / 2).
    LOCAL direction IS 1.
    IF MOD(attemptNumber, 2) = 0 SET direction TO -1.
    SET zToTry TO startZ + direction * magnitude.
  }

  UNTIL (ABS(timeError) < timeTolerance) OR (iterations >= maxIterations) OR failed {
    IF firstTime {
      SET z TO zToTry.
      SET firstTime TO FALSE.
    } ELSE {
      IF dt_dz = 0 SET z TO z + 1.
      ELSE SET z TO z - ( timeSeconds - timeOfFlight) / dt_dz.
      // z >= (2 pi)^2 is where the universal-variable equation moves on to its multi-revolution
      // branches (z between (2 pi)^2 and (4 pi)^2 is the one-revolution family: an arc that takes
      // a whole orbit plus part of another). This solver is for zero-revolution arcs, so that is a failure.
      IF z >= (2*CONSTANT:PI)^2 SET failed TO TRUE.
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

  IF (failed OR (iterations >= maxIterations)) RETURN lambertGauss(r_1,
                                                                                     r_2,
                                                                                     timeOfFlight,
                                                                                     mu,
                                                                                     shortWay,
                                                                                     startZ,
                                                                                     timeTolerance,
                                                                                     maxIterations,
                                                                                     logAllowed,
																					 attemptNumber + 1).

  LOCAL f IS 1 - y / r_1_mag.
  LOCAL g IS A * SQRT( y / mu).
  LOCAL g_dot IS 1 - y / r_2_mag.
  LOCAL v_1 IS (r_2 - f * r_1) / g.
  LOCAL v_2 IS (g_dot * r_2 - r_1) / g.
  LOCAL ecc IS (((v_1:SQRMAGNITUDE - mu / r_1_mag) * r_1 - VDOT( r_1 , v_1 ) * v_1 ) / mu):MAG.
  // Classify from the true eccentricity. This used to be two independent IFs
  // followed by an IF/ELSE, so the ELSE (which fires for every ecc <= 1,
  // including ecc = 1) immediately overwrote "Parabola" with "Ellipse" - it
  // could never survive. Braced here as a proper chain, and the parabola check
  // now uses a small tolerance since floating-point ecc essentially never lands
  // on exactly 1.0.
  LOCAL motionType IS "Ellipse".
  IF ABS(ecc - 1) < 1e-6 {
    SET motionType TO "Parabola".
  } ELSE IF ecc > 1 {
    SET motionType TO "Hyperbola".
  }
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

GLOBAL invalidDeltaV IS 1e15.

FUNCTION porkchopDeltaV {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER solverType.
	PARAMETER departureTime.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER planeNormal IS V(0,0,0).
	PARAMETER parkSMA IS 0.
	PARAMETER parkEccentricity IS 0.
	// Optional mutable out-parameter, same pass-by-reference pattern as "seed":
	// if the caller passes its own LEXICON here, every key from the winning
	// leg's own trajectory lexicon ("v_1", "v_2", "Motion Type", "Iterations",
	// "Final Value", "r_1", "r_2", "mu", "Short Way") is COPIED into it - key
	// by key, mutating the caller's existing LEXICON in place, since reassigning
	// a parameter itself (SET statsOut TO someLexicon) would only repoint this
	// function's own local copy of the reference and never be visible to the
	// caller. If neither leg converges, only "Motion Type" is set (to "Failed"),
	// so a caller can always safely read statsOut["Motion Type"]. Sits last so
	// every existing positional call keeps working unchanged; callers that don't
	// care simply omit it and it defaults to a throwaway LEXICON.
	PARAMETER statsOut IS LEXICON("v_1", V(0,0,0),
									"v_2", V(0,0,0),
									"Motion Type", "Failed",
									"Iterations", 0,
									"Final Value", 0,
									"r_1", V(0,0,0),
									"r_2", V(0,0,0),
									"mu", 0,
									"Short Way", FALSE).

	LOCAL shortStartSeed IS 0.5.
	IF seed:HASKEY("shortSeed") SET shortStartSeed TO seed["shortSeed"].
	LOCAL longStartSeed IS 0.5.
	IF seed:HASKEY("longSeed") SET longStartSeed TO seed["longSeed"].

	// The transfer leaves the departure body at departureTime and meets the destination timeOfFlight
	// later, so the second end point of the Lambert problem is the destination's position then.
	LOCAL arrivalTime IS departureTime + timeOfFlight.
	LOCAL r_1 IS absolutePosition(fromBody, departureTime) - absolutePosition(sunBody, departureTime).
	LOCAL r_2 IS absolutePosition(toBody, arrivalTime) - absolutePosition(sunBody, arrivalTime).

	LOCAL fromBodyVelocity IS absoluteVelocity(fromBody, departureTime) - absoluteVelocity(sunBody, departureTime).
	LOCAL toBodyVelocity IS absoluteVelocity(toBody, arrivalTime) - absoluteVelocity(sunBody, arrivalTime).

	LOCAL bestTotalDV IS invalidDeltaV.
	LOCAL winningTrajectory IS 0.

	// guard against a nonsensical (non-positive) time of flight from an out-of-range guess
	IF timeOfFlight > 0 {
		LOCAL shortTrajectory IS 0.
		LOCAL longTrajectory IS 0.
		IF solverType = "Gooding" {
			SET shortTrajectory TO lambertGooding(r_1, r_2, timeOfFlight, sunBody:MU, TRUE, shortStartSeed).
			SET longTrajectory TO lambertGooding(r_1, r_2, timeOfFlight, sunBody:MU, FALSE, longStartSeed).
		} ELSE {
			SET shortTrajectory TO lambertGauss(r_1, r_2, timeOfFlight, sunBody:MU, TRUE, shortStartSeed).
			SET longTrajectory TO lambertGauss(r_1, r_2, timeOfFlight, sunBody:MU, FALSE, longStartSeed).
		}
		
		IF shortTrajectory["Motion Type"] <> "Failed" {
			// departure leg: combined injection + plane-change cost against the actual parking orbit, instead of a bare vector magnitude difference.
			LOCAL vInfDepartureShort IS shortTrajectory["v_1"] - fromBodyVelocity.
			LOCAL mismatchShort IS 0.
			IF parkSMA <> 0 SET mismatchShort TO planeMismatchAngle(vInfDepartureShort, planeNormal).
			LOCAL departureDVShort IS 0.
			IF parkSMA <> 0 SET departureDVShort TO combinedDepartureDeltaV(vInfDepartureShort:MAG, mismatchShort, fromBody:MU, parkSMA, parkEccentricity).
			LOCAL arrivalDVShort IS (toBodyVelocity - shortTrajectory["v_2"]):MAG.
			LOCAL dvShort IS departureDVShort + arrivalDVShort.
			IF parkSMA = 0 SET dvShort TO vInfDepartureShort:MAG + arrivalDVShort.
			SET seed["shortSeed"] TO shortTrajectory["Final Value"].
			IF dvShort < bestTotalDV {
				SET bestTotalDV TO dvShort.
				SET winningTrajectory TO shortTrajectory.
			}
		}
		IF longTrajectory["Motion Type"] <> "Failed" {
			LOCAL vInfDepartureLong IS longTrajectory["v_1"] - fromBodyVelocity.
			LOCAL mismatchLong IS 0.
			IF parkSMA <> 0 SET mismatchLong TO planeMismatchAngle(vInfDepartureLong, planeNormal).
			LOCAL departureDVLong IS 0.
			IF parkSMA <> 0 SET departureDVLong TO combinedDepartureDeltaV(vInfDepartureLong:MAG, mismatchLong, fromBody:MU, parkSMA, parkEccentricity).
			LOCAL arrivalDVLong IS (toBodyVelocity - longTrajectory["v_2"]):MAG.
			LOCAL dvLong IS departureDVLong + arrivalDVLong.
			IF parkSMA = 0 SET dvLong TO vInfDepartureLong:MAG + arrivalDVLong.
			SET seed["longSeed"] TO longTrajectory["Final Value"].
			IF dvLong < bestTotalDV {
				SET bestTotalDV TO dvLong.
				SET winningTrajectory TO longTrajectory.
			}
		}
	}

	// Mutate the caller's actual statsOut object (never reassign it - see the
	// comment on the parameter above for why that wouldn't propagate back).
	IF winningTrajectory:ISTYPE("Lexicon") {
		FOR statKey IN winningTrajectory:KEYS {
			SET statsOut[statKey] TO winningTrajectory[statKey].
		}
	} ELSE {
		SET statsOut["Motion Type"] TO "Failed".
	}

	RETURN bestTotalDV.
}

// The same as porkchopDeltaV, but with the arguments reordered so that BIND can
// fill in everything that is fixed for a whole search (bodies, parking orbit,
// solver), leaving (departureTime, timeOfFlight, seed, statsOut) for the caller.
// Pass parkSMA = 0 for "no parking orbit" (bare point-mass dV).
FUNCTION porkchopDeltaVPlaneAware {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER planeNormal.
	PARAMETER parkSMA.
	PARAMETER parkEccentricity.
	PARAMETER solver.
	PARAMETER departureTime.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER statsOut IS LEXICON().

	RETURN porkchopDeltaV(fromBody, toBody, sunBody, solver, departureTime, timeOfFlight, seed, planeNormal, parkSMA, parkEccentricity, statsOut).
}

// Returns a delegate f(departureTime, timeOfFlight, seed, statsOut) (the last
// two optional) that returns total dV, with everything else bound.
// solverType is "Gauss" or "Gooding". Omit the parking-orbit arguments for the
// bare point-mass cost.
FUNCTION bindPorkchopDeltaV {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER sunBody.
	PARAMETER solverType.
	PARAMETER planeNormal IS V(0, 0, 0).
	PARAMETER parkSMA IS 0.
	PARAMETER parkEccentricity IS 0.

	LOCAL bound IS porkchopDeltaVPlaneAware@.
	SET bound TO bound:BIND(fromOrbitable).
	SET bound TO bound:BIND(toOrbitable).
	SET bound TO bound:BIND(sunBody).
	SET bound TO bound:BIND(planeNormal).
	SET bound TO bound:BIND(parkSMA).
	SET bound TO bound:BIND(parkEccentricity).
	SET bound TO bound:BIND(solverType).
	RETURN bound.
}

// Chooses the departure and time-of-flight samples for a transfer between two orbitables
// that share a parent body. Everything is absolute: departure times are UT, flight times are
// seconds - nothing is a fraction of a synodic period or of the Hohmann time (except the
// defaults, which are chosen that way).
//
// Passed:
//   fromOrbitable, toOrbitable - bodies or vessels (see resolveOrbitable)
//   departureSamples - how many departure times to sample (>= 1). They are evenly spaced
//       starting at departureStart and stop short of departureEnd, so the end itself is not
//       sampled and consecutive windows tile without repeating a time. Passing 5 gives 5
//       departure times.
//   tofSamples       - how many flight times to sample (>= 1), evenly spaced from tofStart to
//       tofEnd inclusive (a count of 1 gives just tofStart)
//   departureWindows - how many synodic periods the departure range covers when departureEnd
//       is not given (default 1; a bigger number searches several launch windows)
//   departureStart   - UT of the first departure, which must be in the future. -1 (the default)
//       means 120 s from now.
//   departureEnd     - UT where the departure range ends. -1 (the default) means
//       departureStart + departureWindows synodic periods.
//   tofStart, tofEnd - s, the shortest and longest flight time. -1 (the defaults) mean one
//       and four times the Hohmann transfer time.
// Returns a LEXICON. "error" is "None" if everything is fine; otherwise it holds a message
// and no other key is set. Otherwise:
//   "sunBody", "synodicPeriod", "hohmannTime" (s)
//   "startTime", "departureStart", "departureEnd" - UT (startTime is the same as departureStart)
//   "tofStart", "tofEnd" - s
//   "departureSamples", "tofSamples" - as passed
//   "departureTimes" - LIST of departure UTs; "timeOfFlights" - LIST of flight times (s), ascending
//   "departureStep", "tofStep" - the spacing between samples, in seconds (handy as the
//       starting step for a hill climb)
//   "departureUnit", "tofUnit" - "Days"/"Hours"/"Minutes", for labelling
//   "departureUnitSeconds", "tofUnitSeconds" - seconds per label unit
FUNCTION transferSearchWindow {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER departureSamples IS 20.
	PARAMETER tofSamples IS 21.
	PARAMETER departureWindows IS 1.
	PARAMETER departureStart IS -1.
	PARAMETER departureEnd IS -1.
	PARAMETER tofStart IS -1.
	PARAMETER tofEnd IS -1.

	LOCAL window IS LEXICON("error", "None").
	IF fromOrbitable:BODY:NAME <> toOrbitable:BODY:NAME {
		SET window["error"] TO "Bodies must have the same parent!".
		RETURN window.
	}
	IF fromOrbitable:ORBIT:PERIOD = toOrbitable:ORBIT:PERIOD {
		SET window["error"] TO "Bodies have identical orbital periods - no synodic period!".
		RETURN window.
	}
	IF departureSamples < 1 OR tofSamples < 1 {
		SET window["error"] TO "There must be at least one departure sample and one time-of-flight sample!".
		RETURN window.
	}
	IF departureWindows <= 0 {
		SET window["error"] TO "The number of departure windows must be positive!".
		RETURN window.
	}

	LOCAL sunBody IS firstCommonBody(fromOrbitable, toOrbitable).
	LOCAL synodicPeriod IS 1 / ABS((1 / fromOrbitable:ORBIT:PERIOD) - (1 / toOrbitable:ORBIT:PERIOD)).
	LOCAL hohmannTime IS CONSTANT:PI * SQRT(((fromOrbitable:ORBIT:SEMIMAJORAXIS + toOrbitable:ORBIT:SEMIMAJORAXIS) / 2) ^ 3 / sunBody:MU).

	// Fill in the defaults.
	LOCAL firstDeparture IS departureStart.
	IF firstDeparture < 0 SET firstDeparture TO TIME:SECONDS + 120.
	LOCAL lastDeparture IS departureEnd.
	IF lastDeparture < 0 SET lastDeparture TO firstDeparture + departureWindows * synodicPeriod.
	LOCAL shortestFlight IS tofStart.
	IF shortestFlight < 0 SET shortestFlight TO 0.5 * hohmannTime.
	LOCAL longestFlight IS tofEnd.
	IF longestFlight < 0 SET longestFlight TO 4 * hohmannTime.

	IF firstDeparture <= TIME:SECONDS {
		SET window["error"] TO "The first departure must be in the future!".
		RETURN window.
	}
	IF lastDeparture <= firstDeparture {
		SET window["error"] TO "The departure range must end after it starts!".
		RETURN window.
	}
	IF shortestFlight <= 0 OR longestFlight < shortestFlight {
		SET window["error"] TO "The time-of-flight range must be positive, and end no earlier than it starts!".
		RETURN window.
	}

	LOCAL departureStep IS (lastDeparture - firstDeparture) / departureSamples.
	// With a single flight time there is no spacing to speak of; give a hill climb something sensible.
	LOCAL tofStep IS MAX(longestFlight - shortestFlight, 0.1 * shortestFlight).
	IF tofSamples > 1 SET tofStep TO (longestFlight - shortestFlight) / (tofSamples - 1).

	LOCAL departureTimes IS LIST().
	FROM {LOCAL index IS 0.} UNTIL index >= departureSamples STEP {SET index TO index + 1.} DO {
		departureTimes:ADD(firstDeparture + index * departureStep).
	}
	LOCAL timeOfFlights IS LIST().
	FROM {LOCAL index IS 0.} UNTIL index >= tofSamples STEP {SET index TO index + 1.} DO {
		timeOfFlights:ADD(shortestFlight + index * tofStep).
	}

	// Departure labels are sized by the whole departure range; flight-time labels by the shortest flight.
	LOCAL departureUnit IS timeUnitFor(lastDeparture - firstDeparture).
	LOCAL tofUnit IS timeUnitFor(shortestFlight).

	SET window["sunBody"] TO sunBody.
	SET window["synodicPeriod"] TO synodicPeriod.
	SET window["hohmannTime"] TO hohmannTime.
	SET window["startTime"] TO firstDeparture.
	SET window["departureStart"] TO firstDeparture.
	SET window["departureEnd"] TO lastDeparture.
	// How long one "window" is: a synodic period here (a same-SOI window, see sameSOISearchWindow, is shorter).
	SET window["windowLength"] TO synodicPeriod.
	SET window["tofStart"] TO shortestFlight.
	SET window["tofEnd"] TO longestFlight.
	SET window["departureSamples"] TO departureSamples.
	SET window["tofSamples"] TO tofSamples.
	SET window["departureTimes"] TO departureTimes.
	SET window["timeOfFlights"] TO timeOfFlights.
	SET window["departureStep"] TO departureStep.
	SET window["tofStep"] TO tofStep.
	SET window["departureUnit"] TO departureUnit.
	SET window["tofUnit"] TO tofUnit.
	SET window["departureUnitSeconds"] TO timeUnitSeconds(departureUnit).
	SET window["tofUnitSeconds"] TO timeUnitSeconds(tofUnit).
	RETURN window.
}

// Runs the coarse porkchop grid search over a window from transferSearchWindow.
//
// Passed:
//   dvDelegate - f(departureTime, timeOfFlight, seed, statsOut) -> total dV; see bindPorkchopDeltaV
//   window     - LEXICON from transferSearchWindow
//   label      - optional text shown in the progress lines, e.g. the solver name
// Computation runs departure-outer, TOF-inner so the solver's warm-start seed
// (fresh per departure) stays valid across a departure's whole TOF sweep. The
// returned grid is TOF-major, with TOF in DESCENDING order (the window's flight times
// reversed), as the CSV expects.
// Returns a LEXICON:
//   "dv"                - LIST of rows, one per entry of "timeOfFlights"; each row a LIST of dV across "departureTimes". Failed cells hold invalidDeltaV.
//   "timeOfFlights"     - LIST - flight time (s) of each row, descending
//   "departureTimes"    - LIST - departure UT (s) of each column
//   "departureBands"    - LIST - which synodic period (0 for the first, 1 for the next, ...) each column's departure falls in
//   "minDeltaV"         - LEXICON("value", "departureTime", "timeOfFlight") - best cell
//   "motionTypeCounts"  - LEXICON - cells per motion type, including "Failed"
//   "totalCells", "startClock", "endClock", "duration" (game seconds), "realDuration" (wall-clock
//   seconds, from KUNIVERSE:REALWORLDTIME - unaffected by time warp)
FUNCTION porkchopGrid {
	PARAMETER dvDelegate.
	PARAMETER window.
	PARAMETER label IS "".

	LOCAL startClock IS TIME:SECONDS.
	LOCAL realStartTime IS KUNIVERSE:REALWORLDTIME.
	LOCAL logPrefix IS "".
	IF label <> "" SET logPrefix TO "[" + label + "] ".

	LOCAL dvRows IS LIST().
	LOCAL timeOfFlights IS LIST().
	LOCAL departureTimes IS LIST().
	LOCAL departureBands IS LIST().
	LOCAL motionTypeCounts IS LEXICON("Ellipse", 0, "Parabola", 0, "Hyperbola", 0, "Failed", 0).
	LOCAL totalCells IS 0.
	LOCAL minDeltaV IS LEXICON("value", invalidDeltaV, "departureTime", window["startTime"], "timeOfFlight", 0).

	// One empty row per TOF value, up front, so cells can be filled in departure-major order.
	// The window lists flight times ascending; rows run longest first.
	FROM {LOCAL flightIndex IS window["timeOfFlights"]:LENGTH - 1.} UNTIL flightIndex < 0 STEP {SET flightIndex TO flightIndex - 1.} DO {
		dvRows:ADD(LIST()).
		timeOfFlights:ADD(window["timeOfFlights"][flightIndex]).
	}

	FOR departureTime IN window["departureTimes"] {
		LOCAL periodsSinceStart IS (departureTime - window["departureStart"]) / window["windowLength"].
		PRINT logPrefix + "Calculating departure " + ROUND(periodsSinceStart, 3) + " windows in.".
		departureTimes:ADD(departureTime).
		// A hair of tolerance so a departure that lands exactly on a window boundary is not
		// pushed into the previous window by roundoff.
		departureBands:ADD(FLOOR(periodsSinceStart + 1e-9)).

		// Filled in by the delegate; fresh per departure, shared across this departure's TOF sweep.
		LOCAL seed IS LEXICON().

		LOCAL tofIndex IS 0.
		FOR timeOfFlight IN timeOfFlights {
			LOCAL statsOut IS LEXICON().
			LOCAL dV IS dvDelegate(departureTime, timeOfFlight, seed, statsOut).

			SET totalCells TO totalCells + 1.
			LOCAL cellType IS statsOut["Motion Type"].
			IF NOT motionTypeCounts:HASKEY(cellType) SET motionTypeCounts[cellType] TO 0.
			SET motionTypeCounts[cellType] TO motionTypeCounts[cellType] + 1.

			IF minDeltaV["value"] > dV {
				SET minDeltaV["value"] TO dV.
				SET minDeltaV["departureTime"] TO departureTime.
				SET minDeltaV["timeOfFlight"] TO timeOfFlight.
			}
			dvRows[tofIndex]:ADD(dV).

			SET tofIndex TO tofIndex + 1.
			WAIT 0.
		}
	}

	LOCAL endClock IS TIME:SECONDS.
	RETURN LEXICON("dv", dvRows,
					"timeOfFlights", timeOfFlights,
					"departureTimes", departureTimes,
					"departureBands", departureBands,
					"minDeltaV", minDeltaV,
					"motionTypeCounts", motionTypeCounts,
					"totalCells", totalCells,
					"startClock", startClock,
					"endClock", endClock,
					"duration", endClock - startClock,
					"realDuration", KUNIVERSE:REALWORLDTIME - realStartTime).
}

// One line summarizing a grid's motion-type counts (hideEmptyTypes TRUE leaves out types with a zero count), e.g. "Ellipse: 120 (60%)   Failed: 80 (40%)   "
FUNCTION motionTypeSummary {
	PARAMETER grid.
	PARAMETER hideEmptyTypes IS FALSE.

	LOCAL summary IS "".
	FOR typeName IN grid["motionTypeCounts"]:KEYS {
		LOCAL typeCount IS grid["motionTypeCounts"][typeName].
		IF NOT hideEmptyTypes OR typeCount <> 0 {
			SET summary TO summary + typeName + ": " + typeCount + " (" + ROUND(typeCount / MAX(grid["totalCells"], 1) * 100, 2) + "%)   ".
		}
	}
	RETURN summary.
}

// The lowest-dV cell in each synodic-period band of a grid (a band is one synodic period of
// departure dates, as recorded in the grid's "departureBands"). Returns LEXICON band ->
// LEXICON("dv", "departureTime", "flightTime").
FUNCTION porkchopBestPerBand {
	PARAMETER grid.

	LOCAL best IS LEXICON().
	FROM {LOCAL col IS 0.} UNTIL col >= grid["departureTimes"]:LENGTH STEP {SET col TO col + 1.} DO {
		LOCAL band IS grid["departureBands"][col].
		FROM {LOCAL row IS 0.} UNTIL row >= grid["timeOfFlights"]:LENGTH STEP {SET row TO row + 1.} DO {
			LOCAL dV IS grid["dv"][row][col].
			IF NOT best:HASKEY(band) OR dV < best[band]["dv"] {
				IF NOT best:HASKEY(band) best:ADD(band, LEXICON()).
				SET best[band]["dv"] TO dV.
				SET best[band]["departureTime"] TO grid["departureTimes"][col].
				SET best[band]["flightTime"] TO grid["timeOfFlights"][row].
			}
		}
	}
	RETURN best.
}

// Writes a grid to a CSV: the classic porkchop layout (TOF down the rows,
// departure across the columns, "N/A" for failed cells), followed by the
// search parameters, best cell and motion-type breakdown. Replaces any
// existing file of that name.
FUNCTION writePorkchopCsv {
	PARAMETER grid.
	PARAMETER window.
	PARAMETER fileName.
	PARAMETER solverType.
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.

	IF EXISTS(fileName) DELETEPATH(fileName).

	LOCAL synodicPeriod IS window["synodicPeriod"].
	LOCAL hohmannTime IS window["hohmannTime"].
	LOCAL startTime IS window["startTime"].
	LOCAL minDeltaV IS grid["minDeltaV"].

	LOCAL headerRow IS "TOF (" + window["tofUnit"] + ") \ Departure (" + window["departureUnit"] + ")".
	FOR departureTime IN grid["departureTimes"] {
		SET headerRow TO headerRow + "," + ROUND((departureTime - startTime) / window["departureUnitSeconds"], 2).
	}
	LOG headerRow TO fileName.

	FOR rowIndex IN RANGE(0, grid["dv"]:LENGTH) {
		LOCAL rowString IS ROUND(grid["timeOfFlights"][rowIndex] / window["tofUnitSeconds"], 2):TOSTRING.
		FOR cellValue IN grid["dv"][rowIndex] {
			IF cellValue = invalidDeltaV SET rowString TO rowString + ",N/A".
			ELSE SET rowString TO rowString + "," + cellValue.
		}
		LOG rowString TO fileName.
	}

	LOG "" TO fileName.
	LOG "Solver:," + solverType TO fileName.
	LOG "Calculation Start Time:," + grid["startClock"] TO fileName.
	LOG "End Time:," + grid["endClock"] TO fileName.
	LOG "Duration:," + grid["duration"] + "," + timeToString(grid["duration"]) TO fileName.
	LOG "Real-World Duration:," + grid["realDuration"] + "," + realTimeToString(grid["realDuration"]) TO fileName.
	LOG "Synodic Period:," + synodicPeriod + "," + timeToString(synodicPeriod) TO fileName.
	LOG "Hohmann Transfer Time:," + hohmannTime + "," + timeToString(hohmannTime) TO fileName.
	LOG "" TO fileName.

	LOG "Search Parameters:,s UT,duration" TO fileName.
	LOG "Departure Time Start:," + window["departureStart"] + "," + timeToString(window["departureStart"]) TO fileName.
	LOG "Departure Time End:," + window["departureEnd"] + "," + timeToString(window["departureEnd"]) TO fileName.
	LOG "Departure Time Step:," + window["departureStep"] + "," + timeToString(window["departureStep"]) TO fileName.
	LOG "Departure Samples:," + window["departureSamples"] TO fileName.

	LOG "Time of Flight Start:," + window["tofStart"] + "," + timeToString(window["tofStart"]) TO fileName.
	LOG "Time of Flight End:," + window["tofEnd"] + "," + timeToString(window["tofEnd"]) TO fileName.
	LOG "Time of Flight Step:," + window["tofStep"] + "," + timeToString(window["tofStep"]) TO fileName.
	LOG "Time of Flight Samples:," + window["tofSamples"] TO fileName.
	LOG "From Body," + fromOrbitable:NAME TO fileName.
	LOG "To Body," + toOrbitable:NAME TO fileName.

	LOG "" TO fileName.
	LOG "minDeltaV," + minDeltaV["value"] + ",m/s" TO fileName.
	LOG "Min Delta V Departure," + minDeltaV["departureTime"] + "," + timeToString(minDeltaV["departureTime"]) TO fileName.
	LOG "Min Delta V Time of Flight," + minDeltaV["timeOfFlight"] + "," + timeToString(minDeltaV["timeOfFlight"]) TO fileName.

	// "Failed" cells are the "N/A" cells in the grid above.
	LOG "" TO fileName.
	LOG "Motion Type Breakdown:,Count,Percent" TO fileName.
	FOR typeName IN grid["motionTypeCounts"]:KEYS {
		LOCAL typeCount IS grid["motionTypeCounts"][typeName].
		LOG typeName + "," + typeCount + "," + ROUND(typeCount / MAX(grid["totalCells"], 1) * 100, 2) + "%" TO fileName.
	}
	LOG "Total," + grid["totalCells"] + ",100%" TO fileName.
}

// findPlaneMatchedDeparture
//
// Passed:
//   v_infinity        - Vector (m/s) - required hyperbolic excess velocity, expressed in the SAME frame as SHIP:VELOCITY:ORBIT
//   vesselObject       - the vessel to plan the burn for. Defaults to SHIP.
//   targetDepartureUT  - scalar (s, absolute UT), or -1. If given, the search window is centered on this epoch instead of "now" - use this to pass in the desired departure time. If -1 (default), searches forward from right now.
//   searchWindowPeriods - scalar - width of the search window, in parking-orbit periods, centered on targetDepartureUT (or starting just after "now" if targetDepartureUT is -1). Default 1.2.
//   coarseSteps        - scalar - number of samples used to bracket root(s) before polishing with the secant method. Increase for very eccentric parking orbits, where the achievable exit direction can swing quickly near periapsis.
//   minBurnETA         - scalar (s) - earliest allowed burn time from now, so you don't get handed a solution seconds away.
//   createManeuverNode - boolean - if TRUE (default), adds a maneuver node at the best candidate found. If FALSE, only computes and returns the result.
//   clearExistingNodes - boolean - if TRUE (default) and createManeuverNode is also TRUE, removes any maneuver nodes already in the flight plan before adding the new one, so repeated calls don't pile up stale nodes.
//
// Returns a LEXICON:
//   "planeMismatchAngle"  - scalar (deg) - angle between v_infinity and the parking orbit's plane. 0 = perfectly achievable with a pure prograde burn. This number is fixed for this parking orbit; it does not change with time.
//   "outOfPlaneDVPenalty" - scalar (m/s) - approximate extra delta-v if the mismatch above is handled as a SEPARATE plane-change burn. A single combined (non-tangential) burn at the same epoch would generally cost somewhat less than this simple estimate -- treat this as an upper bound and a diagnostic, not a final number.
//   "requiredArgOfLatitude" - scalar (deg) - in-plane direction (in this function's own arbitrary reference frame) that the departure asymptote needs to point along.
//   "candidates"          - LIST of LEXICONs, one per burn opportunity found in the search window, each with "burnETA", "burnUT", "deltaV", "trueAnomalyBurn", "trueAnomalySOI", "flightPathAngle", "angleResidual" (deg, should be ~0).
//   "best"                - the entry of "candidates" with the lowest deltaV, or the string "none found - widen searchWindowPeriods" if the scan turned up nothing.
//   "nodeCreated"         - boolean - TRUE if a maneuver node was actually added.
FUNCTION findPlaneMatchedDeparture {
	PARAMETER v_infinity.
	PARAMETER vesselObject IS SHIP.
	PARAMETER targetDepartureUT IS -1.
	PARAMETER searchWindowPeriods IS 1.2.
	PARAMETER coarseSteps IS 90.
	PARAMETER minBurnETA IS 60.
	PARAMETER createManeuverNode IS TRUE.
	PARAMETER clearExistingNodes IS TRUE.

	LOCAL v_inf_mag IS v_infinity:MAG.
	LOCAL nowUT IS TIME:SECONDS.

	LOCAL posRef IS POSITIONAT(vesselObject, nowUT) - vesselObject:BODY:POSITION.
	LOCAL velRef IS VELOCITYAT(vesselObject, nowUT):ORBIT.
	LOCAL hHat IS VCRS(posRef, velRef):NORMALIZED.
	LOCAL n1Hat IS posRef:NORMALIZED.
	LOCAL n2Hat IS VCRS(hHat, n1Hat):NORMALIZED.

	LOCAL planeAngleDelta IS 90 - VANG(v_infinity, hHat).

	LOCAL vInfInPlane IS v_infinity - hHat * VDOT(v_infinity, hHat).
	IF vInfInPlane:MAG < (v_inf_mag * 0.001) {
		// v_infinity is almost exactly along the plane normal: essentially no
		// phasing choice helps here, the whole vector is an out-of-plane cost.
		LOCAL degenerateResult IS LEXICON().
		degenerateResult:ADD("planeMismatchAngle", planeAngleDelta).
		degenerateResult:ADD("outOfPlaneDVPenalty", 2 * v_inf_mag * SIN(planeAngleDelta / 2)).
		degenerateResult:ADD("requiredArgOfLatitude", "undefined - v_infinity nearly normal to orbit plane").
		degenerateResult:ADD("candidates", LIST()).
		degenerateResult:ADD("best", "none found - v_infinity nearly normal to the parking orbit plane").
		degenerateResult:ADD("nodeCreated", FALSE).
		RETURN degenerateResult.
	}
	LOCAL uTarget IS normalizeAngle360(ARCTAN2(VDOT(vInfInPlane, n2Hat), VDOT(vInfInPlane, n1Hat))).

	// exitAngleError(burnETA): the signed angular error (degrees, -180..180)
	// between where a purely prograde burn at burnETA would actually send the
	// ship's departure asymptote, and where it needs to go (uTarget).
	//   uBurn  = in-plane direction of the vessel's position at burnETA
	//   uExit  = uBurn + flightPathAngle + theta_turn
	//            (flightPathAngle rotates the position direction to the actual
	//             velocity direction at burn; theta_turn is the additional
	//             rotation of the velocity direction from the burn point out to
	//             the SOI edge, both already computed by the library function)
	FUNCTION exitAngleError {
		PARAMETER burnETA.
		LOCAL hbi IS getHyperbolicBurnInfo(v_inf_mag, burnETA, vesselObject).
		LOCAL posBurn IS POSITIONAT(vesselObject, TIME:SECONDS + burnETA) - vesselObject:BODY:POSITION.
		LOCAL uBurn IS ARCTAN2(VDOT(posBurn, n2Hat), VDOT(posBurn, n1Hat)).
		LOCAL uExit IS uBurn + hbi["flightPathAngle"] + hbi["theta_turn"].
		RETURN normalizeAngle180(uExit - uTarget).
	}

	// Coarse scan across the search window to bracket every sign change of the
	// error function, then polish each bracket with the secant method. This is
	// deliberately a grid-then-refine search rather than a descent: it cannot
	// get stuck on the wrong side of the orbit, which is exactly the failure
	// mode a nested gradient descent risks for higher-inclination orbits.
	LOCAL period IS vesselObject:ORBIT:PERIOD.
	LOCAL scanStart IS 0.
	LOCAL scanEnd IS 0.
	IF targetDepartureUT >= 0 {
		LOCAL halfWindow IS (period * searchWindowPeriods) / 2.
		SET scanStart TO MAX(minBurnETA, (targetDepartureUT - halfWindow) - nowUT).
		SET scanEnd TO MAX(scanStart + minBurnETA, (targetDepartureUT + halfWindow) - nowUT).
	} ELSE {
		SET scanStart TO minBurnETA.
		SET scanEnd TO MAX(minBurnETA * 2, period * searchWindowPeriods).
	}
	LOCAL stepSize IS (scanEnd - scanStart) / coarseSteps.

	LOCAL brackets IS LIST().
	LOCAL previousETA IS scanStart.
	LOCAL previousError IS exitAngleError(previousETA).
	LOCAL sampleETA IS 0.
	LOCAL sampleError IS 0.
	FOR stepIndex IN RANGE(1, coarseSteps + 1) {
		SET sampleETA TO scanStart + stepIndex * stepSize.
		SET sampleError TO exitAngleError(sampleETA).
		// The ABS(...) < 180 guard rejects the false "sign change" that shows up
		// when the error simply wraps from +180 to -180 without ever crossing
		// zero; a genuine root has a small step-to-step change when stepSize is
		// fine enough.
		IF (sampleError * previousError < 0) AND (ABS(sampleError - previousError) < 180) {
			brackets:ADD(LIST(previousETA, sampleETA)).
		}
		SET previousETA TO sampleETA.
		SET previousError TO sampleError.
	}

	LOCAL candidates IS LIST().
	FOR eachBracket IN brackets {
		LOCAL refinedETA IS findZeroSecant(exitAngleError@, eachBracket[0], eachBracket[1], 0.0005).
		LOCAL hbiFinal IS getHyperbolicBurnInfo(v_inf_mag, refinedETA, vesselObject).
		LOCAL candidate IS LEXICON().
		candidate:ADD("burnETA", refinedETA).
		candidate:ADD("burnUT", TIME:SECONDS + refinedETA).
		candidate:ADD("deltaV", hbiFinal["v_delta"]).
		candidate:ADD("trueAnomalyBurn", hbiFinal["trueAnomaly"]).
		candidate:ADD("trueAnomalySOI", hbiFinal["trueAnomalySOI"]).
		candidate:ADD("flightPathAngle", hbiFinal["flightPathAngle"]).
		candidate:ADD("angleResidual", exitAngleError(refinedETA)).
		candidates:ADD(candidate).
	}

	LOCAL bestIndex IS -1.
	LOCAL bestDeltaV IS 0.
	FOR candidateIndex IN RANGE(0, candidates:LENGTH) {
		IF (bestIndex = -1) OR (candidates[candidateIndex]["deltaV"] < bestDeltaV) {
			SET bestIndex TO candidateIndex.
			SET bestDeltaV TO candidates[candidateIndex]["deltaV"].
		}
	}

	LOCAL outOfPlaneDV IS 2 * v_inf_mag * SIN(planeAngleDelta / 2).

	LOCAL result IS LEXICON().
	result:ADD("planeMismatchAngle", planeAngleDelta).
	result:ADD("outOfPlaneDVPenalty", outOfPlaneDV).
	result:ADD("requiredArgOfLatitude", uTarget).
	result:ADD("candidates", candidates).
	result:ADD("nodeCreated", FALSE).

	IF bestIndex <> -1 {
		LOCAL best IS candidates[bestIndex].
		result:ADD("best", best).

		IF createManeuverNode {
			IF clearExistingNodes {
				clearManeuverNodes().
			}
			LOCAL burnNode IS NODE(best["burnUT"], 0, 0, best["deltaV"]).
			ADD burnNode.
			SET result["nodeCreated"] TO TRUE.
			PRINT "Departure burn node created: burn in " + ROUND(best["burnETA"], 1) + " s, dV " + ROUND(best["deltaV"], 1) + " m/s.".
		}
	} ELSE {
		result:ADD("best", "none found - widen searchWindowPeriods").
	}
	RETURN result.
}

// ----------------------------------------------------------------------------
// printPlaneMatchResults
// Small convenience printer for a result LEXICON from findPlaneMatchedDeparture,
// in the same spirit as the library's other print* helpers. 
FUNCTION printPlaneMatchResults {
	PARAMETER result.
	PRINT "Plane mismatch angle:     " + ROUND(result["planeMismatchAngle"], 3) + " deg".
	PRINT "Out-of-plane dV penalty:  " + ROUND(result["outOfPlaneDVPenalty"], 1) + " m/s (separate-burn estimate)".
	IF result["best"]:ISTYPE("String") {
		PRINT result["best"].
	} ELSE {
		LOCAL best IS result["best"].
		PRINT "Best burn in:             " + ROUND(best["burnETA"], 1) + " s".
		PRINT "Delta-V (prograde):       " + ROUND(best["deltaV"], 1) + " m/s".
		PRINT "True anomaly at burn:     " + ROUND(best["trueAnomalyBurn"], 2) + " deg".
		PRINT "True anomaly at SOI edge: " + ROUND(best["trueAnomalySOI"], 2) + " deg".
		PRINT "Angle residual (check):   " + ROUND(best["angleResidual"], 4) + " deg".
		PRINT "Candidates found in window: " + result["candidates"]:LENGTH.
		PRINT "Maneuver node created:    " + result["nodeCreated"].
	}
}

// ----------------------------------------------------------------------------
// solveBurnAtPoint
// The exact departure burn from a single point: returns the velocity (relative
// to the body) a vessel must have at burnPosition to leave on the hyperbola
// whose asymptote velocity is exactly vInfinity (direction AND magnitude).
// No assumption that the burn is tangential, at periapsis, or in the parking
// plane - the hyperbola's plane is fixed by burnPosition and vInfinity's
// direction, and the speed by energy: |v|^2 = |vInfinity|^2 + 2*mu/r.
//
// With sweep angle D = the in-plane angle the vessel travels from burnPosition to
// the asymptote direction, the tangential and radial speeds are
//     vt^2 - |vInf| * SIN(D) * vt - (mu/r) * (1 - COS(D)) = 0   (positive root)
//     vr   = |vInf| * COS(D) + mu * SIN(D) / (r * vt)
// D can be measured either way round the plane: the short way (the angle
// between burnPosition and vInfinity) or the long way (360 minus that). Each
// gives a valid hyperbola, going round in opposite directions - this returns
// both, as a LIST of two velocity vectors, so the caller can take the cheaper.
// (Checked numerically against orbital elements: asymptote direction and speed
// reproduced to ~1e-13 for random positions, directions and speeds.)
//
//   tangentHint - only used if vInfinity is (anti)parallel to burnPosition, where
//                 the plane is otherwise undefined: the plane then contains this vector.
//   senses      - which sweep directions to return, in order: 1 = short way, 2 = long way.
FUNCTION solveBurnAtPoint {
	PARAMETER burnPosition.
	PARAMETER vInfinity.
	PARAMETER mu.
	PARAMETER tangentHint IS V(0, 0, 0).
	PARAMETER senses IS LIST(1, 2).

	LOCAL burnRadius IS burnPosition:MAG.
	LOCAL radialUnit IS burnPosition / burnRadius.
	LOCAL vInfMag IS vInfinity:MAG.
	LOCAL vInfUnit IS vInfinity / vInfMag.
	LOCAL angleToAsymptote IS VANG(radialUnit, vInfUnit).

	// In-plane unit vector perpendicular to radialUnit, on the side vInfinity lies.
	LOCAL sideUnit IS vInfUnit - radialUnit * VDOT(vInfUnit, radialUnit).
	IF sideUnit:MAG < 1e-6 SET sideUnit TO tangentHint - radialUnit * VDOT(tangentHint, radialUnit).
	IF sideUnit:MAG < 1e-9 SET sideUnit TO VCRS(radialUnit, V(0, 1, 0)).
	SET sideUnit TO sideUnit:NORMALIZED.

	LOCAL options IS LIST().
	FOR sense IN senses {
		LOCAL sweepAngle IS angleToAsymptote.
		LOCAL sweepDirection IS sideUnit.
		IF sense = 2 {
			SET sweepAngle TO 360 - angleToAsymptote.
			SET sweepDirection TO -sideUnit.
		}
		LOCAL sinSweep IS SIN(sweepAngle).
		LOCAL cosSweep IS COS(sweepAngle).
		LOCAL tangentialSpeed IS (vInfMag * sinSweep + SQRT((vInfMag * sinSweep) ^ 2 + 4 * mu * (1 - cosSweep) / burnRadius)) / 2.
		// tangentialSpeed = 0 only for a purely radial burn (sweep angle 0), where the
		// radial-speed formula is 0/0 - take it straight from energy instead.
		LOCAL radialSpeed IS SQRT(vInfMag ^ 2 + 2 * mu / burnRadius).
		IF tangentialSpeed > 1e-6 SET radialSpeed TO vInfMag * cosSweep + mu * sinSweep / (burnRadius * tangentialSpeed).
		options:ADD(radialUnit * radialSpeed + sweepDirection * tangentialSpeed).
	}
	RETURN options.
}

// ----------------------------------------------------------------------------
// findDepartureBurn
// Finds when, within the vessel's current orbit, a single burn reaches v_infinity
// at the lowest delta-v, and creates the maneuver node for it. Unlike
// findPlaneMatchedDeparture, the burn is NOT restricted to prograde: the node
// gets the full radial / normal / prograde vector, so it contains the plane
// change and any non-tangential component, and its delta-v is the cost of
// actually arriving on the requested asymptote (see solveBurnAtPoint).
//
// Passed: as findPlaneMatchedDeparture (same parameters, same meanings).
//   v_infinity - Vector (m/s) in the same frame as the vessel's :ORBIT velocity
// Returns a LEXICON:
//   "planeMismatchAngle" - scalar (deg) - angle between v_infinity and the orbit plane
//   "candidates"         - LIST of LEXICONs, the local delta-v minima found in the window
//   "best"               - the cheapest candidate, or a string if none found. Each candidate has
//                          "burnETA", "burnUT", "deltaV" (m/s, magnitude), "dvVector",
//                          "prograde", "normal", "radial" (m/s node components), "position", "velocity".
//   "nodeCreated"        - boolean
//   "nodeVerified"       - boolean - TRUE if the created node's :DELTAV matches the intended vector
//                          (this also settles the sign convention of the node's normal axis)
FUNCTION findDepartureBurn {
	PARAMETER v_infinity.
	PARAMETER vesselObject IS SHIP.
	PARAMETER targetDepartureUT IS -1.
	PARAMETER searchWindowPeriods IS 1.2.
	PARAMETER coarseSteps IS 90.
	PARAMETER minBurnETA IS 60.
	PARAMETER createManeuverNode IS TRUE.
	PARAMETER clearExistingNodes IS TRUE.

	// Existing nodes would bend the predicted orbit that everything below samples.
	IF createManeuverNode AND clearExistingNodes {
		clearManeuverNodes().
	}

	LOCAL nowUT IS TIME:SECONDS.
	LOCAL bodyMu IS vesselObject:BODY:MU.
	LOCAL period IS vesselObject:ORBIT:PERIOD.

	LOCAL posNow IS POSITIONAT(vesselObject, nowUT) - vesselObject:BODY:POSITION.
	LOCAL velNow IS VELOCITYAT(vesselObject, nowUT):ORBIT.
	LOCAL planeAngleDelta IS 90 - VANG(v_infinity, VCRS(posNow, velNow)).

	// The cheapest exact burn at one ETA: the better of the two sweep directions.
	FUNCTION burnAt {
		PARAMETER burnETA.
		LOCAL burnUT IS nowUT + burnETA.
		LOCAL burnPos IS POSITIONAT(vesselObject, burnUT) - vesselObject:BODY:POSITION.
		LOCAL burnVel IS VELOCITYAT(vesselObject, burnUT):ORBIT.
		LOCAL options IS solveBurnAtPoint(burnPos, v_infinity, bodyMu, burnVel).
		LOCAL dvVector IS options[0] - burnVel.
		IF (options[1] - burnVel):MAG < dvVector:MAG SET dvVector TO options[1] - burnVel.
		RETURN LEXICON("burnETA", burnETA, "burnUT", burnUT, "position", burnPos, "velocity", burnVel,
						"dvVector", dvVector, "deltaV", dvVector:MAG).
	}

	LOCAL scanStart IS 0.
	LOCAL scanEnd IS 0.
	IF targetDepartureUT >= 0 {
		LOCAL halfWindow IS (period * searchWindowPeriods) / 2.
		SET scanStart TO MAX(minBurnETA, (targetDepartureUT - halfWindow) - nowUT).
		SET scanEnd TO MAX(scanStart + minBurnETA, (targetDepartureUT + halfWindow) - nowUT).
	} ELSE {
		SET scanStart TO minBurnETA.
		SET scanEnd TO MAX(minBurnETA * 2, period * searchWindowPeriods).
	}
	LOCAL stepSize IS (scanEnd - scanStart) / coarseSteps.

	// Coarse scan of delta-v against burn time, then a golden-section polish
	// around every local minimum (a cheap, derivative-free bracket search, same
	// grid-then-refine idea as findPlaneMatchedDeparture).
	LOCAL sampleDV IS LIST().
	FOR stepIndex IN RANGE(0, coarseSteps + 1) {
		sampleDV:ADD(burnAt(scanStart + stepIndex * stepSize)["deltaV"]).
	}

	LOCAL candidates IS LIST().
	LOCAL inversePhi IS (SQRT(5) - 1) / 2.
	FOR stepIndex IN RANGE(0, coarseSteps + 1) {
		LOCAL isMinimum IS TRUE.
		IF stepIndex > 0 AND sampleDV[stepIndex - 1] < sampleDV[stepIndex] SET isMinimum TO FALSE.
		IF stepIndex < coarseSteps AND sampleDV[stepIndex + 1] < sampleDV[stepIndex] SET isMinimum TO FALSE.
		IF isMinimum {
			LOCAL lowETA IS MAX(scanStart, scanStart + (stepIndex - 1) * stepSize).
			LOCAL highETA IS MIN(scanEnd, scanStart + (stepIndex + 1) * stepSize).
			LOCAL probeLow IS highETA - inversePhi * (highETA - lowETA).
			LOCAL probeHigh IS lowETA + inversePhi * (highETA - lowETA).
			LOCAL probeLowDV IS burnAt(probeLow)["deltaV"].
			LOCAL probeHighDV IS burnAt(probeHigh)["deltaV"].
			LOCAL iterations IS 0.
			UNTIL (highETA - lowETA < 0.05) OR (iterations >= 60) {
				IF probeLowDV < probeHighDV {
					SET highETA TO probeHigh.
					SET probeHigh TO probeLow.
					SET probeHighDV TO probeLowDV.
					SET probeLow TO highETA - inversePhi * (highETA - lowETA).
					SET probeLowDV TO burnAt(probeLow)["deltaV"].
				} ELSE {
					SET lowETA TO probeLow.
					SET probeLow TO probeHigh.
					SET probeLowDV TO probeHighDV.
					SET probeHigh TO lowETA + inversePhi * (highETA - lowETA).
					SET probeHighDV TO burnAt(probeHigh)["deltaV"].
				}
				SET iterations TO iterations + 1.
			}
			candidates:ADD(burnAt((lowETA + highETA) / 2)).
		}
	}

	// Express each candidate's burn in the node's own axes (prograde along the
	// velocity, normal along the orbit normal, radial the remaining outward axis).
	FOR candidate IN candidates {
		LOCAL progradeUnit IS candidate["velocity"]:NORMALIZED.
		LOCAL normalUnit IS VCRS(candidate["position"], candidate["velocity"]):NORMALIZED.
		LOCAL radialUnit IS VCRS(progradeUnit, normalUnit):NORMALIZED.
		IF VDOT(radialUnit, candidate["position"]) < 0 SET radialUnit TO -radialUnit.
		candidate:ADD("prograde", VDOT(candidate["dvVector"], progradeUnit)).
		candidate:ADD("normal", VDOT(candidate["dvVector"], normalUnit)).
		candidate:ADD("radial", VDOT(candidate["dvVector"], radialUnit)).
	}

	LOCAL bestIndex IS -1.
	FOR candidateIndex IN RANGE(0, candidates:LENGTH) {
		IF (bestIndex = -1) OR (candidates[candidateIndex]["deltaV"] < candidates[bestIndex]["deltaV"]) SET bestIndex TO candidateIndex.
	}

	LOCAL result IS LEXICON("planeMismatchAngle", planeAngleDelta,
							"candidates", candidates,
							"nodeCreated", FALSE,
							"nodeVerified", FALSE).

	IF bestIndex = -1 {
		result:ADD("best", "none found - widen searchWindowPeriods").
		RETURN result.
	}
	LOCAL best IS candidates[bestIndex].
	result:ADD("best", best).

	IF createManeuverNode {
		// The sign of the node's normal axis depends on the coordinate handedness, so
		// check each choice against the node's own :DELTAV and keep the one that matches.
		LOCAL tolerance IS best["deltaV"] * 0.01.
		LOCAL burnNode IS NODE(best["burnUT"], best["radial"], best["normal"], best["prograde"]).
		ADD burnNode.
		LOCAL nodeError IS (burnNode:DELTAV - best["dvVector"]):MAG.
		IF nodeError > tolerance {
			REMOVE burnNode.
			LOCAL flippedNode IS NODE(best["burnUT"], best["radial"], -best["normal"], best["prograde"]).
			ADD flippedNode.
			LOCAL flippedError IS (flippedNode:DELTAV - best["dvVector"]):MAG.
			IF flippedError > nodeError {
				// Neither matches; fall back to the original and let nodeVerified say so.
				REMOVE flippedNode.
				ADD NODE(best["burnUT"], best["radial"], best["normal"], best["prograde"]).
			} ELSE {
				SET nodeError TO flippedError.
			}
		}
		SET result["nodeCreated"] TO TRUE.
		SET result["nodeVerified"] TO nodeError <= tolerance.
		PRINT "Departure burn node created: burn in " + ROUND(best["burnETA"], 1) + " s, dV " + ROUND(best["deltaV"], 1) + " m/s" +
			" (prograde " + ROUND(best["prograde"], 1) + ", normal " + ROUND(best["normal"], 1) + ", radial " + ROUND(best["radial"], 1) + ").".
		IF NOT result["nodeVerified"] PRINT "WARNING: node :DELTAV does not match the intended burn vector (off by " + ROUND(nodeError, 2) + " m/s).".
	}
	RETURN result.
}

// Angle between a v_infinity vector's direction and a parking orbit's plane.
// 0 = v_infinity lies exactly in the plane; 90 = v_infinity is normal to the plane.
FUNCTION planeMismatchAngle {
	PARAMETER vInfinityVector.
	PARAMETER planeNormal.
	RETURN 90 - VANG(vInfinityVector, planeNormal).
}

// Realistic departure delta-v: a single burn that both reaches escape energy
// AND absorbs the unavoidable plane-change component, via the standard
// combined-maneuver law of cosines (correct for any speed ratio). Assumes
// burn at parking-orbit periapsis.
FUNCTION combinedDepartureDeltaV {
	PARAMETER vInfinityMag.
	PARAMETER mismatchAngleDeg.
	PARAMETER mu.
	PARAMETER parkSMA.
	PARAMETER parkEccentricity IS 0.

	LOCAL rBurn IS parkSMA * (1 - parkEccentricity).
	LOCAL vPark IS SQRT(mu * (2 / rBurn - 1 / parkSMA)).
	LOCAL vHyperbola IS SQRT(vInfinityMag ^ 2 + 2 * mu / rBurn).
	RETURN SQRT(vPark ^ 2 + vHyperbola ^ 2 - 2 * vPark * vHyperbola * COS(mismatchAngleDeg)).
}

// Following: Gooding, A procedure for the solution of Lambert's orbital
// boundary-value problem, Celestial Mechanics and Astronomy 48 (1990),
// 145-165; Der, The Superior Lambert Algorithm. Uses Sun/Gooding's bounded
// path parameter x (x in (-1,1) for ellipses, x>1 for hyperbolas, x=1 exactly
// at the parabolic limit) rather than the unbounded universal-variable z used
// elsewhere in this project (see lambertGauss in
// this file) - x's bounded domain is what makes it possible to bracket a
// root and solve it with findZeroBrent (in library.ks), instead of a derivative-based
// iteration with no convergence guarantee.
//
// departureVector/arrivalVector are positions relative to the same central
// body; timeOfFlight is in seconds; shortWay controls which way (short
// way/long way) the transfer angle is measured.
FUNCTION lambertGooding {
	PARAMETER departureVector.
	PARAMETER arrivalVector.
	PARAMETER timeOfFlight.
	PARAMETER mu.
	PARAMETER shortWay IS TRUE.
	PARAMETER xGuess IS "default".
	PARAMETER tolerance IS 5e-7.
	PARAMETER boundaryTolerance IS 5 * tolerance.

	LOCAL sqrtMu IS SQRT(mu).
	// The transfer angle is geometric, as in lambertGauss: the angle between the two vectors for
	// the short way (the arc that sweeps under 180 degrees), and 360 minus it for the long way.
	// (This used to take the sense from the Y component of VCRS(arrival, departure), which only
	// means something for transfers near the XZ plane - the ecliptic - and mislabelled the two
	// arcs for an orbit such as a polar one. Together the two arcs are the same set as before.)
	LOCAL transferAngle IS VANG(departureVector, arrivalVector).
	IF NOT shortWay SET transferAngle TO 360 - transferAngle.

	LOCAL departureMag IS departureVector:MAG.
	LOCAL arrivalMag IS arrivalVector:MAG.
	LOCAL departureUnit IS departureVector / departureMag.
	LOCAL arrivalUnit IS arrivalVector / arrivalMag.
	LOCAL chordVector IS arrivalVector - departureVector.
	LOCAL chordLength IS chordVector:MAG.
	LOCAL chordUnit IS chordVector / chordLength.
	LOCAL perimeterSum IS departureMag + arrivalMag + chordLength.
	LOCAL perimeterDiff IS perimeterSum - 2 * chordLength.
	LOCAL invSqrtPerimeterSum IS 1 / SQRT(perimeterSum).
	LOCAL invSqrtPerimeterDiff IS 1 / SQRT(perimeterDiff).

	LOCAL normalizedTime IS 4 * timeOfFlight * sqrtMu / perimeterSum ^ 1.5.
	LOCAL pathSign IS 0.
	IF SIN(transferAngle) < 0 SET pathSign TO -1.
	IF SIN(transferAngle) > 0 SET pathSign TO 1.
	LOCAL pathParameter IS pathSign * SQRT(perimeterDiff / perimeterSum).
	LOCAL pathParameterSquared IS perimeterDiff / perimeterSum.
	LOCAL twoPathParameterCubed IS 2 * pathParameterSquared * pathParameter.
	LOCAL oneMinusPathParameterSquared IS 2 * chordLength / perimeterSum. // = 1 - pathParameter^2

	LOCAL parabolicTime IS (2 - twoPathParameterCubed) / 3.
	LOCAL minEnergyTime IS ARCCOS(pathParameter) * CONSTANT:DegToRad + pathParameter * SQRT(oneMinusPathParameterSquared).

	// Which regime this transfer falls in.
	LOCAL transferType IS 0. // 0 = ellipse, 1 = parabola, 2 = hyperbola
	IF ABS(normalizedTime - parabolicTime) < boundaryTolerance {
		SET transferType TO 1.
	} ELSE IF normalizedTime < parabolicTime {
		SET transferType TO 2.
	}

	LOCAL x IS 0.
	LOCAL z IS 0.
	LOCAL converged IS TRUE.

	IF transferType = 1 {
		// Exact parabola - a closed form, no root-finding needed at all.
		SET x TO 1.
		SET z TO 1. // sqrt(pathParameterSquared + oneMinusPathParameterSquared) = sqrt(1)
	} ELSE {
		// Gooding/Der's own analytic initial guess - used here as the seed
		// for a bracket search rather than for a derivative-based iteration.
		// If xGuess was passed in externally, use that instead of these estimates.
		IF xGuess = "default" {
			IF normalizedTime < minEnergyTime {
				SET xGuess TO minEnergyTime * (minEnergyTime / normalizedTime - 1).
			} ELSE {
				SET xGuess TO SQRT((normalizedTime - minEnergyTime) / (normalizedTime + 0.5 * minEnergyTime)).
			}
		}

		LOCAL domainLow IS -1 + boundaryTolerance.
		LOCAL domainHigh IS 1 - boundaryTolerance.
		IF transferType = 2 {
			SET domainLow TO 1 + boundaryTolerance.
			SET domainHigh TO 1e8. // generously far beyond any physically sensible transfer
		}

		LOCAL residualDelegate IS lambertTimeResidual@.
		SET residualDelegate TO residualDelegate:BIND(pathParameter).
		SET residualDelegate TO residualDelegate:BIND(pathParameterSquared).
		SET residualDelegate TO residualDelegate:BIND(oneMinusPathParameterSquared).
		SET residualDelegate TO residualDelegate:BIND(parabolicTime).
		SET residualDelegate TO residualDelegate:BIND(boundaryTolerance).
		SET residualDelegate TO residualDelegate:BIND(normalizedTime).

		LOCAL initialStep IS MAX(ABS(xGuess) * 0.5, boundaryTolerance * 10).
		LOCAL bracket IS bracketAroundGuess(residualDelegate, xGuess, domainLow, domainHigh, initialStep).

		// A degenerate bracket (bracketAroundGuess never found a sign change) means
		// there's nothing valid to hand findZeroBrent - flag it now rather than
		// letting findZeroBrent's own graceful fallback silently report a
		// plausible-looking but unconverged x as if it were a real solution.
		IF bracket["low"] = bracket["high"] SET converged TO FALSE.

		SET x TO findZeroBrent(residualDelegate, bracket["low"], bracket["high"], tolerance).
		SET z TO SQRT(pathParameterSquared * x * x + oneMinusPathParameterSquared).

		// findZeroBrent's own stopping criterion is on bracket WIDTH, not residual
		// size, so also directly check that x actually solves the time equation
		// to within a reasonable tolerance before trusting it - this is what lets
		// "Motion Type" here mean the same thing it does in
		// lambertGauss ("Failed" really means failed), which
		// matters for comparing the two solvers' reliability fairly.
		IF ABS(residualDelegate(x)) > boundaryTolerance SET converged TO FALSE.
	}

	LOCAL zVelocityFactor IS pathSign * z * invSqrtPerimeterDiff.
	LOCAL xVelocityFactor IS x * invSqrtPerimeterSum.
	LOCAL chordVelocity IS sqrtMu * (zVelocityFactor + xVelocityFactor) * chordUnit.
	LOCAL radialVelocityScale IS sqrtMu * (zVelocityFactor - xVelocityFactor).

	LOCAL motionType IS "Ellipse".
	IF transferType = 1 SET motionType TO "Parabola".
	IF transferType = 2 SET motionType TO "Hyperbola".
	IF NOT converged SET motionType TO "Failed".

	LOCAL v1Result IS chordVelocity + radialVelocityScale * departureUnit.
	LOCAL v2Result IS chordVelocity - radialVelocityScale * arrivalUnit.
	IF NOT converged {
		SET v1Result TO V(0, 0, 0).
		SET v2Result TO V(0, 0, 0).
	}

	RETURN LEXICON("v_1", v1Result,
					"v_2", v2Result,
					"Motion Type", motionType,
					"Iterations", 0,
					"Final Value", x,
					"r_1", departureVector,
					"r_2", arrivalVector,
					"mu", mu,
					"Short Way", shortWay).
}

// Normalized-time residual T(x) - normalizedTime, whose root (for a fixed
// transfer geometry) is the x that solves the Lambert problem. All arguments
// except x are meant to be BIND-ed ahead of time (see lambertGooding), leaving a
// single-argument delegate suitable for findZeroBrent - x has to be last so
// BIND can fix every other argument first and leave x as the one thing that
// varies from call to call during root-finding.
FUNCTION lambertTimeResidual {
	PARAMETER pathParameter.
	PARAMETER pathParameterSquared.
	PARAMETER oneMinusPathParameterSquared.
	PARAMETER parabolicTime.
	PARAMETER boundaryTolerance.
	PARAMETER normalizedTime.
	PARAMETER x.

	LOCAL u IS 1 - x * x.
	LOCAL timeValue IS parabolicTime. // fallback right at the ellipse/hyperbola boundary

	IF ABS(u) > boundaryTolerance {
		LOCAL z IS SQRT(pathParameterSquared * x * x + oneMinusPathParameterSquared).
		LOCAL y IS SQRT(ABS(u)).
		LOCAL f IS y * (z - pathParameter * x).
		LOCAL g IS x * z + pathParameter * u.
		LOCAL d IS 0.
		IF u > boundaryTolerance {
			SET d TO (90 - ARCTAN(g / f)) * CONSTANT:DegToRad.
			SET timeValue TO (pathParameter * z + d / y - x) / u.
		} ELSE IF f + g > 0 {
			SET d TO LN(f + g).
			SET timeValue TO (pathParameter * z + d / y - x) / u.
		} ELSE {
			// A hyperbola with a huge x (the bracket search probes out to 1e8): f and g are
			// differences of nearly equal huge numbers, so f + g can come out zero or negative
			// from roundoff, and LN of that is NaN, which stops the script. The time of flight
			// tends to 0 as x grows without limit, so use that.
			SET timeValue TO 0.
		}
	}

	RETURN timeValue - normalizedTime.
}



// ----------------------------------------------------------------------------
// Orbit propagation
// ----------------------------------------------------------------------------

// Propagates a bound (elliptical) two-body orbit from a state vector.
//   startPosition, startVelocity - relative to the central body (any inertial frame)
//   deltaTime - s, may be negative or longer than a period
//   mu        - gravitational parameter of the central body
// Returns LEXICON("position", "velocity"). Not valid for parabolic/hyperbolic orbits.
// (Checked against a numerical integration: ~1e-6 m position error.)
FUNCTION propagateKepler {
	PARAMETER startPosition.
	PARAMETER startVelocity.
	PARAMETER deltaTime.
	PARAMETER mu.

	LOCAL radToDeg IS CONSTANT:RadToDeg.
	LOCAL startRadius IS startPosition:MAG.
	LOCAL sma IS 1 / (2 / startRadius - startVelocity:MAG ^ 2 / mu).
	LOCAL meanMotion IS SQRT(mu / sma ^ 3).
	LOCAL period IS 2 * CONSTANT:PI / meanMotion.

	// A whole number of periods changes nothing, so keep the time small.
	LOCAL reducedTime IS deltaTime - FLOOR(deltaTime / period) * period.
	LOCAL meanAnomalyChange IS meanMotion * reducedTime.

	// Kepler's equation in the change in eccentric anomaly (radians), by Newton's method.
	LOCAL radialTerm IS VDOT(startPosition, startVelocity) / SQRT(mu).
	LOCAL coefficientOne IS radialTerm / SQRT(sma).
	LOCAL coefficientTwo IS 1 - startRadius / sma.
	LOCAL eccentricAnomalyChange IS meanAnomalyChange.
	LOCAL pass IS 0.
	UNTIL pass >= 30 {
		LOCAL sineValue IS SIN(eccentricAnomalyChange * radToDeg).
		LOCAL cosineValue IS COS(eccentricAnomalyChange * radToDeg).
		LOCAL residual IS eccentricAnomalyChange + coefficientOne * (1 - cosineValue) - coefficientTwo * sineValue - meanAnomalyChange.
		LOCAL slope IS 1 + coefficientOne * sineValue - coefficientTwo * cosineValue.
		LOCAL correction IS residual / slope.
		SET eccentricAnomalyChange TO eccentricAnomalyChange - correction.
		IF ABS(correction) < 1e-12 BREAK.
		SET pass TO pass + 1.
	}

	LOCAL sineFinal IS SIN(eccentricAnomalyChange * radToDeg).
	LOCAL cosineFinal IS COS(eccentricAnomalyChange * radToDeg).
	LOCAL endRadius IS sma + (startRadius - sma) * cosineFinal + radialTerm * SQRT(sma) * sineFinal.
	LOCAL positionScale IS 1 - (sma / startRadius) * (1 - cosineFinal).
	LOCAL positionVelocityScale IS reducedTime - SQRT(sma ^ 3 / mu) * (eccentricAnomalyChange - sineFinal).
	LOCAL velocityPositionScale IS -SQRT(mu * sma) / (endRadius * startRadius) * sineFinal.
	LOCAL velocityScale IS 1 - (sma / endRadius) * (1 - cosineFinal).

	RETURN LEXICON("position", startPosition * positionScale + startVelocity * positionVelocityScale,
					"velocity", startPosition * velocityPositionScale + startVelocity * velocityScale).
}


// ----------------------------------------------------------------------------
// Hyperbolic departure at one point
// ----------------------------------------------------------------------------

// Time (s) to fly a hyperbola from true anomaly startAnomaly to endAnomaly (degrees).
//   vInfinity - hyperbolic excess speed (m/s); eccentricity - of the hyperbola.
FUNCTION hyperbolaTransitTime {
	PARAMETER mu.
	PARAMETER vInfinity.
	PARAMETER eccentricity.
	PARAMETER startAnomaly.
	PARAMETER endAnomaly.

	LOCAL sqrtTerm IS SQRT(eccentricity ^ 2 - 1).
	LOCAL semiMajorAbs IS mu / vInfinity ^ 2.
	LOCAL meanMotion IS SQRT(mu / semiMajorAbs ^ 3).

	// sinh of the hyperbolic anomaly at each end, then the hyperbolic mean anomaly.
	LOCAL startSinh IS sqrtTerm * SIN(startAnomaly) / (1 + eccentricity * COS(startAnomaly)).
	LOCAL endSinh IS sqrtTerm * SIN(endAnomaly) / (1 + eccentricity * COS(endAnomaly)).
	LOCAL startMean IS eccentricity * startSinh - ASINH(startSinh).
	LOCAL endMean IS eccentricity * endSinh - ASINH(endSinh).
	RETURN (endMean - startMean) / meanMotion.
}

// The exact burn from one point that leaves the body's SOI with a given velocity.
//   burnPosition - relative to the body
//   vExit        - the velocity (relative to the body) wanted AT the SOI edge, e.g.
//                  the Lambert departure velocity minus the body's own velocity
//   mu, soiRadius - of the body
//   tangentHint  - passed to solveBurnAtPoint (used if the geometry is degenerate); the
//                  parking-orbit velocity is a good choice
//   minPeriapsis - m from the body's centre; burns whose hyperbola dips below it
//                  (e.g. into the planet or its atmosphere) are dropped
//   soiIterations - how many times the asymptote direction is corrected for the
//                  hyperbola still turning between the SOI edge and infinity
//                  (3-4 is enough: ~0.005 deg on the Mun, less on Kerbin)
//   senses       - which sweep directions to solve (1 = short way, 2 = long way)
// Returns a LIST of candidate burns - one per sweep direction (short way / long way),
// minus any rejected - each a LEXICON with:
//   "burnVelocity" - velocity (relative to the body) right after the burn
//   "sense", "eccentricity", "periapsis", "vInfinity"
//   "trueAnomalyBurn", "trueAnomalySOI" - on the hyperbola, degrees
//   "transitTime"  - s from the burn to the SOI edge (so tSOI = burn time + transitTime)
// Empty if vExit is below escape speed at the SOI edge.
// (Checked against a numerical integration to the SOI edge: speed to ~1e-4,
// heading to ~0.005 deg, transit time to ~1e-7.)
FUNCTION solveEjectionAtPoint {
	PARAMETER burnPosition.
	PARAMETER vExit.
	PARAMETER mu.
	PARAMETER soiRadius.
	PARAMETER tangentHint IS V(0, 0, 0).
	PARAMETER minPeriapsis IS 0.
	PARAMETER soiIterations IS 4.
	PARAMETER senses IS LIST(1, 2).

	LOCAL candidates IS LIST().
	LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * mu / soiRadius.
	IF vInfinitySquared <= 0 RETURN candidates.
	LOCAL vInfinity IS SQRT(vInfinitySquared).

	LOCAL edgeUnit IS vExit:NORMALIZED.
	LOCAL burnRadius IS burnPosition:MAG.
	LOCAL radialUnit IS burnPosition / burnRadius.

	FOR sense IN senses {
		LOCAL asymptoteUnit IS edgeUnit.
		LOCAL burnVelocity IS V(0, 0, 0).
		LOCAL eccentricity IS 0.
		LOCAL burnAnomaly IS 0.
		LOCAL soiAnomaly IS 0.
		LOCAL periapsisRadius IS 0.
		LOCAL usable IS TRUE.

		FROM {LOCAL pass IS 0.} UNTIL pass >= soiIterations STEP {SET pass TO pass + 1.} DO {
			SET burnVelocity TO solveBurnAtPoint(burnPosition, asymptoteUnit * vInfinity, mu, tangentHint, LIST(sense))[0].

			LOCAL radialSpeed IS VDOT(burnVelocity, radialUnit).
			LOCAL tangentialVector IS burnVelocity - radialUnit * radialSpeed.
			LOCAL tangentialSpeed IS tangentialVector:MAG.
			IF tangentialSpeed < 1e-6 {
				// a purely radial burn - no usable hyperbola plane here
				SET usable TO FALSE.
				BREAK.
			}
			LOCAL sideUnit IS tangentialVector / tangentialSpeed.

			// Elements of the hyperbola this burn puts the ship on, in the plane of
			// (radialUnit, sideUnit): eccentricity vector components, true anomaly
			// of the burn, and of the SOI-edge crossing.
			LOCAL semiLatus IS (burnRadius * tangentialSpeed) ^ 2 / mu.
			LOCAL eccentricityRadial IS burnRadius * tangentialSpeed ^ 2 / mu - 1.
			LOCAL eccentricitySide IS -burnRadius * tangentialSpeed * radialSpeed / mu.
			SET eccentricity TO SQRT(eccentricityRadial ^ 2 + eccentricitySide ^ 2).
			SET burnAnomaly TO ARCTAN2(-eccentricitySide, eccentricityRadial).
			SET soiAnomaly TO ARCCOS(MAX(-1, MIN(1, (semiLatus / soiRadius - 1) / eccentricity))).
			SET periapsisRadius TO semiLatus / (1 + eccentricity).

			// The velocity heading keeps turning, by headingGap, between the SOI edge
			// and the asymptote. The asymptote therefore lies headingGap beyond the
			// wanted exit heading, in the direction of travel - rotate the target by it.
			LOCAL asymptoteAnomaly IS ARCCOS(-1 / eccentricity).
			LOCAL headingGap IS ARCTAN2(eccentricity + COS(asymptoteAnomaly), -SIN(asymptoteAnomaly))
				- ARCTAN2(eccentricity + COS(soiAnomaly), -SIN(soiAnomaly)).
			LOCAL perpendicularUnit IS radialUnit * (-VDOT(edgeUnit, sideUnit)) + sideUnit * VDOT(edgeUnit, radialUnit).
			SET asymptoteUnit TO edgeUnit * COS(headingGap) + perpendicularUnit * SIN(headingGap).
		}

		IF usable AND periapsisRadius >= minPeriapsis {
			candidates:ADD(LEXICON("burnVelocity", burnVelocity,
									"sense", sense,
									"eccentricity", eccentricity,
									"periapsis", periapsisRadius,
									"vInfinity", vInfinity,
									"trueAnomalyBurn", burnAnomaly,
									"trueAnomalySOI", soiAnomaly,
									"transitTime", hyperbolaTransitTime(mu, vInfinity, eccentricity, burnAnomaly, soiAnomaly))).
		}
	}
	RETURN candidates.
}


// ----------------------------------------------------------------------------
// Parking orbits ("orbit specs")
// ----------------------------------------------------------------------------

// Radius from a body's centre below which an orbit would hit the ground or
// its atmosphere.
FUNCTION bodyClearanceRadius {
	PARAMETER centralBody.

	LOCAL clearance IS centralBody:RADIUS.
	IF centralBody:ATM:EXISTS SET clearance TO clearance + centralBody:ATM:HEIGHT.
	RETURN clearance.
}

// Builds an "orbit"-mode spec from a state vector (relative to the central body, at
// time epoch UT). The orbit must be bound.
FUNCTION makeOrbitSpec {
	PARAMETER parkPosition.
	PARAMETER parkVelocity.
	PARAMETER epoch.
	PARAMETER mu.
	PARAMETER minPeriapsis IS 0.

	LOCAL sma IS 1 / (2 / parkPosition:MAG - parkVelocity:MAG ^ 2 / mu).
	// h^2 = mu * sma * (1 - e^2); the periapsis radius is what ejectionLowerBound needs.
	LOCAL momentumSize IS VCRS(parkPosition, parkVelocity):MAG.
	LOCAL eccentricity IS SQRT(MAX(0, 1 - momentumSize ^ 2 / (mu * sma))).
	RETURN LEXICON("mode", "orbit",
					"position", parkPosition,
					"velocity", parkVelocity,
					"epoch", epoch,
					"mu", mu,
					"sma", sma,
					"eccentricity", eccentricity,
					"periapsisRadius", sma * (1 - eccentricity),
					"period", 2 * CONSTANT:PI * SQRT(sma ^ 3 / mu),
					"minPeriapsis", minPeriapsis).
}

// Case 2: the spec for a vessel that is already in its parking orbit, as of right now.
// This captures the whole orbit - both angles of its plane, its shape, and where the
// ship is in it.
FUNCTION orbitSpecFromVessel {
	PARAMETER vesselObject IS SHIP.

	LOCAL parentBody IS vesselObject:BODY.
	RETURN makeOrbitSpec(vesselObject:POSITION - parentBody:POSITION, vesselObject:VELOCITY:ORBIT,
							TIME:SECONDS, parentBody:MU, bodyClearanceRadius(parentBody)).
}

// Case 1: the spec for a ship that has not launched yet. A circular parking orbit
// at parkingAltitude is designed for each transfer (see designParkingOrbit).
//   launchLatitude - degrees; defaults to the ship's current latitude (the pad)
FUNCTION designSpec {
	PARAMETER centralBody.
	PARAMETER parkingAltitude.
	PARAMETER launchLatitude IS SHIP:LATITUDE.

	RETURN LEXICON("mode", "design",
					"body", centralBody,
					"radius", centralBody:RADIUS + parkingAltitude,
					"latitude", launchLatitude,
					"mu", centralBody:MU,
					"minPeriapsis", bodyClearanceRadius(centralBody)).
}

// Position and velocity on a circular orbit in a given plane.
//   planeNormal - unit vector normal to the plane; the orbit goes round it in the
//                 direction given by VCRS(planeNormal, position)
//   phase       - degrees round the orbit from an arbitrary reference direction
FUNCTION circularOrbitState {
	PARAMETER planeNormal.
	PARAMETER radius.
	PARAMETER mu.
	PARAMETER phase IS 0.

	LOCAL referenceVector IS V(1, 0, 0).
	IF ABS(VDOT(referenceVector, planeNormal)) > 0.9 SET referenceVector TO V(0, 0, 1).
	LOCAL firstUnit IS (referenceVector - planeNormal * VDOT(referenceVector, planeNormal)):NORMALIZED.
	LOCAL secondUnit IS VCRS(planeNormal, firstUnit).

	LOCAL circularSpeed IS SQRT(mu / radius).
	RETURN LEXICON("position", (firstUnit * COS(phase) + secondUnit * SIN(phase)) * radius,
					"velocity", (secondUnit * COS(phase) - firstUnit * SIN(phase)) * circularSpeed).
}

// Case 1: designs the parking orbit for a given departure. The plane is the one that
// contains the departure direction (minimum inclination), raised to the launch site's
// latitude if that is the binding floor (see computeRecommendedParkingPlane) - so
// if the latitude does not bind there is no plane-change cost at all.
//   designSpecification - from designSpec
//   vExit               - velocity wanted at the SOI edge (relative to the body)
// Returns an "orbit"-mode spec (epoch 0) with extra keys "inclination", "lan",
// "alternateLan" (a second node that does equally well when latitude binds),
// "latitudeConstraintBinding", "pureMinimumInclination" (before the latitude floor),
// "verificationResidual" (should be ~0) and "planeNormal".
FUNCTION designParkingOrbit {
	PARAMETER designSpecification.
	PARAMETER vExit.

	LOCAL plane IS computeRecommendedParkingPlane(designSpecification["body"], vExit, designSpecification["latitude"]).
	LOCAL planeNormal IS getOrbitPlaneNormal(designSpecification["body"], plane["inclination"], plane["lan"]).
	LOCAL state IS circularOrbitState(planeNormal, designSpecification["radius"], designSpecification["mu"], 0).

	LOCAL spec IS makeOrbitSpec(state["position"], state["velocity"], 0, designSpecification["mu"], designSpecification["minPeriapsis"]).
	SET spec["inclination"] TO plane["inclination"].
	SET spec["lan"] TO plane["lan"].
	SET spec["alternateLan"] TO plane["alternateLan"].
	SET spec["latitudeConstraintBinding"] TO plane["latitudeConstraintBinding"].
	SET spec["pureMinimumInclination"] TO plane["pureMinimumInclination"].
	SET spec["verificationResidual"] TO plane["verificationResidual"].
	SET spec["planeNormal"] TO planeNormal.
	RETURN spec.
}


// ----------------------------------------------------------------------------
// Ejection cost from an orbit
// ----------------------------------------------------------------------------

// How hard the ejection search works. The cost of a transfer search is dominated by this: every
// cell of a grid, and every step of a hill climb, runs an ejection search for each Lambert
// solution.
//   "full"  - 48 burn-point samples, 4 SOI-correction passes in the cost model, 8 polish steps.
//             Use for anything that is reported.
//   "quick" - 24 samples, 2 passes, 6 polish steps. Use for the coarse grid and hill climb, then
//             re-price the winner with "full".
// Either way the best point found is then priced with the exact solver (solveEjectionAtPoint with
// the same number of passes), both at the polished point and at the best sample.
// Measured offline against a dense search (720 burn points, exact solver) on random orbits and
// exit directions at the Mun - the hard case, because its small SOI makes the heading correction
// large and the circular orbit only 30 km above the clearance radius makes the feasible region a
// narrow sliver: quick lands within 0.3% of the true minimum in 96% of cases and within 1% in 97%;
// full is within 0.3% in 98% and within 1% in 99%. For comparison, sampling the orbit in time and
// solving every sample exactly (what this replaced) managed 88% / 95% (8 samples) and 97.5% / 98%
// (16 samples, twice the solves). Kerbin-like orbits are easier. The misses that remain are cases
// where the cost is nearly flat across two separate regions.
// Returns a LEXICON: "samples", "soiIterations", "polishIterations".
FUNCTION ejectionPrecision {
	PARAMETER precisionName.

	IF precisionName = "quick" RETURN LEXICON("samples", 24, "soiIterations", 2, "polishIterations", 6).
	RETURN LEXICON("samples", 48, "soiIterations", 4, "polishIterations", 8).
}

// A cheap, rigorous lower bound on the ejection delta-V for an orbit spec ("orbit" or "design")
// and a hyperbolic excess speed vInfinity. Whatever the burn, |vBurn - vPark| >= | |vBurn| - |vPark| |,
// with |vBurn| = SQRT(vInfinity^2 + 2*mu/r) by energy. That gap grows with the burn radius r, so it is
// smallest at periapsis. (Checked on 588 random searches: never violated.)
// For a "design" spec (a circular orbit in a plane that contains the departure direction) the bound
// is not just a bound - it is the exact cost, since a tangential burn at periapsis is then possible.
FUNCTION ejectionLowerBound {
	PARAMETER orbitSpec.
	PARAMETER vInfinity.

	LOCAL mu IS orbitSpec["mu"].
	LOCAL burnRadius IS 0.
	LOCAL parkSpeed IS 0.
	IF orbitSpec["mode"] = "design" {
		SET burnRadius TO orbitSpec["radius"].
		SET parkSpeed TO SQRT(mu / burnRadius).
	} ELSE {
		SET burnRadius TO orbitSpec["periapsisRadius"].
		SET parkSpeed TO SQRT(mu * (2 / burnRadius - 1 / orbitSpec["sma"])).
	}
	RETURN SQRT(vInfinity ^ 2 + 2 * mu / burnRadius) - parkSpeed.
}

// The cheapest ejection burn anywhere around an "orbit"-mode spec ("phase-free"), found by a
// search over TRUE ANOMALY using a scalar model of the cost.
//
// Why this is cheap. For a burn at a point of the parking orbit, the exact burn (solveBurnAtPoint)
// lies in the plane of that point and the exit direction, and its radial and tangential speeds
// depend only on the sweep angle between them (cos D = r-hat . exit-hat, for the short way round,
// or 360 - D the long way). The parking velocity has a radial part (mu/h)*e*sin(nu) and a
// tangential part (mu/h)*(1 + e*cos(nu)). The only geometry left is the angle between the two
// tangent directions (the hyperbola plane's and the parking orbit's), and that is also a scalar:
// cos(tilt) = (exit . motion-hat at nu) / sin D. So with the exit direction resolved once into the
// orbit's own axes (A along periapsis, B along the motion at periapsis), the cost at any true
// anomaly is scalar arithmetic:
//     cos D = A*cos(nu) + B*sin(nu)
//     cost^2 = (vr - vParkRadial)^2 + vt^2 + vParkTangential^2 - 2*vt*vParkTangential*cos(tilt)
// with vt and vr from the quadratic in solveBurnAtPoint. No Kepler solve and no vectors per sample.
//
// The SOI-edge heading correction (the hyperbola is still turning at the SOI edge, so the asymptote
// lies a little beyond the exit direction) is only a change of the sweep angle, so it is scalar too:
// each pass computes the hyperbola's eccentricity and true anomalies and adds the heading gap to the
// sweep, exactly as solveEjectionAtPoint does. It matters little at Kerbin (0.03 degrees) and a lot
// at a small moon (about 2 degrees at the Mun), where leaving it out misplaces the best burn and the
// edge of the feasible region. (Checked against the vector solve at 3,695 random Mun burn points:
// equal to 1e-9 at all but 3, which sit at a sweep of about 179 degrees where the burn plane is
// degenerate.)
//
// A cost that cannot clear the planet is not a flat "invalid": it is invalidDeltaV plus how far the
// hyperbola's periapsis is below the clearance, so a scan with no feasible sample still points
// toward the feasible sliver and the polish can walk into it.
//
// For a circular orbit in a plane containing the exit direction this reduces to the hyperbolic
// turning-angle picture (the best burn is the asymptote angle behind the exit direction), which is
// exact there but poor once the plane is tilted - the best burn then stops being tangential - so it
// is not used on its own.
//
//   vExit        - velocity wanted at the SOI edge, relative to the body
//   soiRadius    - of the body
//   precision    - from ejectionPrecision: samples around the orbit, correction passes, polish steps
// Returns a LEXICON with "deltaV" (invalidDeltaV if there is no valid burn), "trueAnomaly" (degrees)
// and "offset" (s after the spec's epoch) of the burn point, "burnPosition", "parkVelocity",
// "dvVector", "burnVelocity" and the "ejection" candidate from solveEjectionAtPoint that won.
FUNCTION bestEjectionFromOrbit {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER soiRadius.
	PARAMETER precision IS ejectionPrecision("full").

	LOCAL mu IS orbitSpec["mu"].
	LOCAL best IS LEXICON("deltaV", invalidDeltaV, "ejection", 0).
	LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * mu / soiRadius.
	IF vInfinitySquared <= 0 RETURN best.
	LOCAL vInfinity IS SQRT(vInfinitySquared).
	LOCAL correctionPasses IS precision["soiIterations"].

	// The orbit's own axes: periapsis direction, the direction of motion at periapsis, and the
	// scalars that give position and velocity at any true anomaly. Only the part of the
	// eccentricity vector in the orbit plane is kept: rounding noise has an out-of-plane part, and
	// for a (near) circular orbit that noise is all there is. Below 1e-5 the orbit is treated as
	// circular and any in-plane direction (here, toward the ship) is the zero of true anomaly.
	LOCAL startPosition IS orbitSpec["position"].
	LOCAL momentumVector IS VCRS(startPosition, orbitSpec["velocity"]).
	LOCAL momentumSize IS momentumVector:MAG.
	LOCAL normalUnit IS momentumVector / momentumSize.
	LOCAL eccentricityVector IS VCRS(orbitSpec["velocity"], momentumVector) / mu - startPosition:NORMALIZED.
	SET eccentricityVector TO eccentricityVector - normalUnit * VDOT(eccentricityVector, normalUnit).
	LOCAL eccentricity IS eccentricityVector:MAG.
	LOCAL periapsisUnit IS startPosition:NORMALIZED.
	IF eccentricity > 1e-5 {
		SET periapsisUnit TO eccentricityVector / eccentricity.
	} ELSE {
		SET eccentricity TO 0.
	}
	LOCAL motionUnit IS VCRS(normalUnit, periapsisUnit).
	LOCAL semiLatus IS momentumSize ^ 2 / mu.
	LOCAL speedScale IS mu / momentumSize.
	LOCAL minPeriapsis IS orbitSpec["minPeriapsis"].

	// The exit direction resolved into those axes.
	LOCAL exitUnit IS vExit:NORMALIZED.
	LOCAL exitAlongPeriapsis IS VDOT(periapsisUnit, exitUnit).
	LOCAL exitAlongMotion IS VDOT(motionUnit, exitUnit).
	LOCAL senseSigns IS LIST(1, -1).

	// The scalar model: ejection cost at true anomaly trueAnomaly (degrees), the cheaper of the two
	// sweep directions. Above invalidDeltaV means no sweep direction clears minPeriapsis.
	FUNCTION costAtAnomaly {
		PARAMETER trueAnomaly.

		LOCAL cosNu IS COS(trueAnomaly).
		LOCAL sinNu IS SIN(trueAnomaly).
		LOCAL radius IS semiLatus / (1 + eccentricity * cosNu).
		LOCAL parkRadialSpeed IS speedScale * eccentricity * sinNu.
		LOCAL parkTangentialSpeed IS speedScale * (1 + eccentricity * cosNu).
		LOCAL cosSweep IS MAX(-1, MIN(1, exitAlongPeriapsis * cosNu + exitAlongMotion * sinNu)).
		LOCAL sinSweep IS SQRT(MAX(0, 1 - cosSweep ^ 2)).
		LOCAL shortSweep IS ARCTAN2(sinSweep, cosSweep).
		LOCAL cosTilt IS 1.
		IF sinSweep > 1e-9 SET cosTilt TO MAX(-1, MIN(1, (exitAlongMotion * cosNu - exitAlongPeriapsis * sinNu) / sinSweep)).

		LOCAL bestCost IS 2 * invalidDeltaV.
		FOR senseSign IN senseSigns {
			LOCAL baseSweep IS shortSweep.
			IF senseSign < 0 SET baseSweep TO 360 - shortSweep.
			LOCAL sweep IS baseSweep.
			LOCAL tangentialSpeed IS 0.
			LOCAL radialSpeed IS 0.
			LOCAL hyperbolaEccentricity IS 1.

			FROM {LOCAL pass IS 1.} UNTIL pass > correctionPasses STEP {SET pass TO pass + 1.} DO {
				LOCAL sinOfSweep IS SIN(sweep).
				LOCAL cosOfSweep IS COS(sweep).
				SET tangentialSpeed TO (vInfinity * sinOfSweep + SQRT((vInfinity * sinOfSweep) ^ 2 + 4 * mu * (1 - cosOfSweep) / radius)) / 2.
				SET radialSpeed TO SQRT(vInfinitySquared + 2 * mu / radius).
				IF tangentialSpeed > 1e-6 SET radialSpeed TO vInfinity * cosOfSweep + mu * sinOfSweep / (radius * tangentialSpeed).
				LOCAL eccentricityRadial IS radius * tangentialSpeed ^ 2 / mu - 1.
				LOCAL eccentricitySide IS radius * tangentialSpeed * radialSpeed / mu.
				SET hyperbolaEccentricity TO SQRT(eccentricityRadial ^ 2 + eccentricitySide ^ 2).
				IF pass < correctionPasses {
					// How far the asymptote lies beyond the SOI-edge heading, added to the sweep.
					LOCAL hyperbolaSemiLatus IS (radius * tangentialSpeed) ^ 2 / mu.
					LOCAL edgeAnomaly IS ARCCOS(MAX(-1, MIN(1, (hyperbolaSemiLatus / soiRadius - 1) / hyperbolaEccentricity))).
					LOCAL asymptoteAnomaly IS ARCCOS(MAX(-1, MIN(1, -1 / hyperbolaEccentricity))).
					SET sweep TO baseSweep + ARCTAN2(hyperbolaEccentricity + COS(asymptoteAnomaly), -SIN(asymptoteAnomaly))
						- ARCTAN2(hyperbolaEccentricity + COS(edgeAnomaly), -SIN(edgeAnomaly)).
				}
			}

			// The hyperbola this burn puts the ship on must clear the planet and its atmosphere.
			LOCAL hyperbolaPeriapsis IS radius ^ 2 * tangentialSpeed ^ 2 / mu / (1 + hyperbolaEccentricity).
			LOCAL candidateCost IS invalidDeltaV + (minPeriapsis - hyperbolaPeriapsis).
			IF hyperbolaPeriapsis >= minPeriapsis {
				SET candidateCost TO SQRT(MAX(0, (radialSpeed - parkRadialSpeed) ^ 2 + tangentialSpeed ^ 2 + parkTangentialSpeed ^ 2
					- 2 * tangentialSpeed * parkTangentialSpeed * senseSign * cosTilt)).
			}
			IF candidateCost < bestCost SET bestCost TO candidateCost.
		}
		RETURN bestCost.
	}

	// The exact ejection (the vector solve) at true anomaly trueAnomaly.
	FUNCTION exactAtAnomaly {
		PARAMETER trueAnomaly.

		LOCAL radius IS semiLatus / (1 + eccentricity * COS(trueAnomaly)).
		LOCAL burnPosition IS (periapsisUnit * COS(trueAnomaly) + motionUnit * SIN(trueAnomaly)) * radius.
		LOCAL parkVelocity IS (periapsisUnit * (-SIN(trueAnomaly)) + motionUnit * (eccentricity + COS(trueAnomaly))) * speedScale.
		LOCAL options IS solveEjectionAtPoint(burnPosition, vExit, mu, soiRadius, parkVelocity, minPeriapsis, correctionPasses).
		LOCAL bestOption IS 0.
		LOCAL bestDV IS invalidDeltaV.
		FOR option IN options {
			LOCAL optionDV IS (option["burnVelocity"] - parkVelocity):MAG.
			IF optionDV < bestDV {
				SET bestDV TO optionDV.
				SET bestOption TO option.
			}
		}
		LOCAL result IS LEXICON("deltaV", bestDV, "trueAnomaly", trueAnomaly, "burnPosition", burnPosition,
								"parkVelocity", parkVelocity, "ejection", bestOption).
		IF bestDV < invalidDeltaV {
			SET result["burnVelocity"] TO bestOption["burnVelocity"].
			SET result["dvVector"] TO bestOption["burnVelocity"] - parkVelocity.
		}
		RETURN result.
	}

	// Coarse scan around the whole orbit, then polish the best sample.
	LOCAL samples IS precision["samples"].
	LOCAL stepDegrees IS 360 / samples.
	LOCAL bestAnomaly IS 0.
	LOCAL bestSampleCost IS 4 * invalidDeltaV.
	FROM {LOCAL sampleIndex IS 0.} UNTIL sampleIndex >= samples STEP {SET sampleIndex TO sampleIndex + 1.} DO {
		LOCAL sampleCost IS costAtAnomaly(sampleIndex * stepDegrees).
		IF sampleCost < bestSampleCost {
			SET bestSampleCost TO sampleCost.
			SET bestAnomaly TO sampleIndex * stepDegrees.
		}
	}
	LOCAL polishedAnomaly IS goldenSectionMinimum(costAtAnomaly@, bestAnomaly - stepDegrees, bestAnomaly + stepDegrees, precision["polishIterations"]).

	// Price the winner exactly, at the polished point and at the best sample.
	SET best TO exactAtAnomaly(polishedAnomaly).
	IF bestSampleCost < invalidDeltaV {
		LOCAL sampleResult IS exactAtAnomaly(bestAnomaly).
		IF sampleResult["deltaV"] < best["deltaV"] SET best TO sampleResult.
	}
	IF best["deltaV"] >= invalidDeltaV {
		// Both fell just outside the feasible region once priced exactly; look a little either side.
		FOR nudge IN LIST(1, -1, 3, -3) {
			IF best["deltaV"] >= invalidDeltaV {
				LOCAL nudged IS exactAtAnomaly(polishedAnomaly + nudge).
				IF nudged["deltaV"] < best["deltaV"] SET best TO nudged.
			}
		}
	}
	IF best["deltaV"] >= invalidDeltaV RETURN best.

	// How long after the spec's epoch the ship reaches that burn point: true anomaly to mean
	// anomaly now and then, over the mean motion.
	LOCAL startAnomaly IS ARCTAN2(VDOT(startPosition, motionUnit), VDOT(startPosition, periapsisUnit)).
	LOCAL burnEccentricAnomaly IS 2 * ARCTAN2(SQRT(1 - eccentricity) * SIN(best["trueAnomaly"] / 2), SQRT(1 + eccentricity) * COS(best["trueAnomaly"] / 2)).
	LOCAL startEccentricAnomaly IS 2 * ARCTAN2(SQRT(1 - eccentricity) * SIN(startAnomaly / 2), SQRT(1 + eccentricity) * COS(startAnomaly / 2)).
	LOCAL burnMeanAnomaly IS burnEccentricAnomaly * CONSTANT:DegToRad - eccentricity * SIN(burnEccentricAnomaly).
	LOCAL startMeanAnomaly IS startEccentricAnomaly * CONSTANT:DegToRad - eccentricity * SIN(startEccentricAnomaly).
	LOCAL meanMotion IS SQRT(mu / orbitSpec["sma"] ^ 3).
	LOCAL timeToBurn IS (burnMeanAnomaly - startMeanAnomaly) / meanMotion.
	SET best["offset"] TO timeToBurn - FLOOR(timeToBurn / orbitSpec["period"]) * orbitSpec["period"].
	RETURN best.
}

// The ejection burn when the SOI exit time tSOI is fixed ("exact timing"): the burn
// happens transitTime before tSOI, and transitTime depends on where in the orbit the
// burn is, so the burn time is the root of
//     burnUT + transitTime(burnUT) - tSOI = 0
// found separately for each sweep direction (a plain fixed-point iteration on this
// is NOT safe - the transit time changes by up to ~1 s per second of burn time, so
// it can diverge). The transit-time range over one orbit sets the search window; the
// window is sampled for sign changes, each bracket is polished with findZeroBrent, and
// the cheapest valid root over both directions wins.
//   orbitSpec - "orbit" mode (a real orbit; the burn point is then dictated)
//   vExit     - velocity wanted at the SOI edge, relative to the body
//   tSOI      - UT the ship should cross the SOI edge
//   earliestBurnUT - UT before which the burn is impossible (e.g. now + a margin); a burn
//                    earlier than this is flagged ("tooEarly"), not moved
//   scanSamples - samples for the transit-time range, and again for the root bracketing
// Returns a LEXICON with "deltaV", "burnUT", "dvVector", "burnVelocity", "burnPosition",
// "parkVelocity", "transitTime", "tooEarly" and the "ejection" candidate; "deltaV" is
// invalidDeltaV if there is no valid burn.
// (Checked on an eccentric, inclined orbit: the cost swings from ~1200 to ~4800 m/s as
// tSOI moves through one parking period, and its minimum matches the phase-free minimum.)
FUNCTION ejectionForExitTime {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER tSOI.
	PARAMETER soiRadius.
	PARAMETER earliestBurnUT IS 0.
	PARAMETER soiIterations IS 4.
	PARAMETER scanSamples IS 12.

	LOCAL result IS LEXICON("deltaV", invalidDeltaV, "ejection", 0, "tooEarly", FALSE).

	// The ejection candidate for one sweep direction at one burn time. The periapsis
	// limit is left off here (it would make the residual below jump) and is checked
	// on the final answer instead.
	FUNCTION candidateAt {
		PARAMETER senseNumber.
		PARAMETER burnUT.

		LOCAL state IS propagateKepler(orbitSpec["position"], orbitSpec["velocity"], burnUT - orbitSpec["epoch"], orbitSpec["mu"]).
		LOCAL options IS solveEjectionAtPoint(state["position"], vExit, orbitSpec["mu"], soiRadius, state["velocity"], 0, soiIterations, LIST(senseNumber)).
		IF options:LENGTH = 0 RETURN LEXICON("valid", FALSE, "state", state).
		RETURN LEXICON("valid", TRUE, "state", state, "option", options[0]).
	}

	// How far the SOI exit time that a burn at burnUT leads to is from tSOI.
	FUNCTION exitTimeResidual {
		PARAMETER senseNumber.
		PARAMETER burnUT.

		LOCAL candidate IS candidateAt(senseNumber, burnUT).
		IF NOT candidate["valid"] RETURN burnUT - tSOI.
		RETURN burnUT + candidate["option"]["transitTime"] - tSOI.
	}

	FOR senseNumber IN LIST(1, 2) {
		// The range of transit times this sweep direction has around the orbit.
		LOCAL transitMin IS 1e15.
		LOCAL transitMax IS -1e15.
		FROM {LOCAL sampleIndex IS 0.} UNTIL sampleIndex >= scanSamples STEP {SET sampleIndex TO sampleIndex + 1.} DO {
			LOCAL probe IS candidateAt(senseNumber, orbitSpec["epoch"] + sampleIndex * orbitSpec["period"] / scanSamples).
			IF probe["valid"] {
				SET transitMin TO MIN(transitMin, probe["option"]["transitTime"]).
				SET transitMax TO MAX(transitMax, probe["option"]["transitTime"]).
			}
		}

		// Any burn that exits at tSOI lies in this window, and the residual changes sign across it.
		IF transitMax >= transitMin {
			LOCAL windowStart IS tSOI - transitMax - 1.
			LOCAL windowEnd IS tSOI - transitMin + 1.
			LOCAL residualDelegate IS exitTimeResidual@:BIND(senseNumber).
			LOCAL previousUT IS windowStart.
			LOCAL previousResidual IS residualDelegate(windowStart).

			FROM {LOCAL sampleIndex IS 1.} UNTIL sampleIndex > scanSamples STEP {SET sampleIndex TO sampleIndex + 1.} DO {
				LOCAL sampleUT IS windowStart + (windowEnd - windowStart) * sampleIndex / scanSamples.
				LOCAL sampleResidual IS residualDelegate(sampleUT).
				IF previousResidual * sampleResidual < 0 {
					LOCAL rootUT IS findZeroBrent(residualDelegate, previousUT, sampleUT, 0.01).
					LOCAL root IS candidateAt(senseNumber, rootUT).
					IF root["valid"] AND root["option"]["periapsis"] >= orbitSpec["minPeriapsis"] {
						LOCAL rootDV IS (root["option"]["burnVelocity"] - root["state"]["velocity"]):MAG.
						IF rootDV < result["deltaV"] {
							SET result TO LEXICON("deltaV", rootDV,
													"burnUT", rootUT,
													"dvVector", root["option"]["burnVelocity"] - root["state"]["velocity"],
													"burnVelocity", root["option"]["burnVelocity"],
													"burnPosition", root["state"]["position"],
													"parkVelocity", root["state"]["velocity"],
													"transitTime", root["option"]["transitTime"],
													"tooEarly", rootUT < earliestBurnUT,
													"ejection", root["option"]).
						}
					}
				}
				SET previousUT TO sampleUT.
				SET previousResidual TO sampleResidual.
			}
		}
	}
	RETURN result.
}

// The ejection cost for a given exit velocity, for either kind of orbit spec.
//   exactTiming - for an "orbit" spec only: fix the burn point by tSOI instead of
//                 taking the best point in the orbit. A "design" spec has no real
//                 orbit to be timed against, so it is always phase-free.
//   precision   - from ejectionPrecision; how hard the phase-free search works
// For a "design" spec whose plane is not forced by the launch-site latitude, the designed
// plane contains the departure direction, so the cheapest burn is a tangential one at periapsis
// and the cost is the closed form of ejectionLowerBound - no search is run. Only when the
// latitude floor binds (so the plane cannot contain the departure direction) is there a search.
// Returns the LEXICON of bestEjectionFromOrbit / ejectionForExitTime (or, for the closed form,
// just "deltaV" and "closedForm"); for a "design" spec it also carries "inclination", "lan",
// "alternateLan", "latitudeConstraintBinding", "pureMinimumInclination",
// "verificationResidual" and "planeNormal" - the parking orbit to launch into.
FUNCTION ejectionDeltaVForExit {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER fromBody.
	PARAMETER tSOI.
	PARAMETER exactTiming IS FALSE.
	PARAMETER precision IS ejectionPrecision("full").
	PARAMETER earliestBurnUT IS 0.

	LOCAL soiRadius IS fromBody:SOIRADIUS.
	LOCAL isDesign IS orbitSpec["mode"] = "design".
	LOCAL workingSpec IS orbitSpec.
	IF isDesign SET workingSpec TO designParkingOrbit(orbitSpec, vExit).

	LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * workingSpec["mu"] / soiRadius.
	LOCAL result IS 0.
	IF vInfinitySquared <= 0 {
		// Below escape speed at the SOI edge: no burn gets out.
		SET result TO LEXICON("deltaV", invalidDeltaV, "ejection", 0).
	} ELSE IF isDesign AND NOT workingSpec["latitudeConstraintBinding"] AND workingSpec["periapsisRadius"] >= workingSpec["minPeriapsis"] {
		SET result TO LEXICON("deltaV", ejectionLowerBound(workingSpec, SQRT(vInfinitySquared)), "ejection", 0, "closedForm", TRUE).
	} ELSE IF exactTiming AND NOT isDesign {
		SET result TO ejectionForExitTime(workingSpec, vExit, tSOI, soiRadius, earliestBurnUT, precision["soiIterations"]).
	} ELSE {
		SET result TO bestEjectionFromOrbit(workingSpec, vExit, soiRadius, precision).
	}

	IF isDesign {
		SET result["inclination"] TO workingSpec["inclination"].
		SET result["lan"] TO workingSpec["lan"].
		SET result["alternateLan"] TO workingSpec["alternateLan"].
		SET result["latitudeConstraintBinding"] TO workingSpec["latitudeConstraintBinding"].
		SET result["pureMinimumInclination"] TO workingSpec["pureMinimumInclination"].
		SET result["verificationResidual"] TO workingSpec["verificationResidual"].
		SET result["planeNormal"] TO workingSpec["planeNormal"].
	}
	RETURN result.
}


// ----------------------------------------------------------------------------
// Arrival and the total
// ----------------------------------------------------------------------------

// Delta-V to finish the transfer at the destination.
//   arrivalVelocity - transfer velocity relative to the destination, as Lambert gives it
//                     (the velocity at the destination's SOI edge)
//   captureRadius   - m from the destination's centre. If > 0, the cost of capturing into
//                     a circular orbit of that radius, burning at its periapsis; if 0, the
//                     hyperbolic excess (the cost of matching the destination's velocity
//                     far from it).
// A vessel has no SOI, so for one the cost is just the relative speed. If the arrival
// velocity is below escape speed at the SOI edge the body captures the ship on its
// own, and the cost is 0.
FUNCTION arrivalDeltaV {
	PARAMETER arrivalVelocity.
	PARAMETER targetOrbitable.
	PARAMETER captureRadius IS 0.

	IF NOT targetOrbitable:ISTYPE("Body") RETURN arrivalVelocity:MAG.

	LOCAL excessSquared IS arrivalVelocity:MAG ^ 2 - 2 * targetOrbitable:MU / targetOrbitable:SOIRADIUS.
	IF excessSquared <= 0 RETURN 0.
	IF captureRadius <= 0 RETURN SQRT(excessSquared).
	RETURN SQRT(excessSquared + 2 * targetOrbitable:MU / captureRadius) - SQRT(targetOrbitable:MU / captureRadius).
}

// Total delta-V (ejection + arrival, m/s) of the transfer that crosses the departure
// body's SOI edge at tSOI and flies for timeOfFlight, taking the better of Lambert's
// short-way and long-way solutions.
//   fromBody  - must be a body (an SOI is needed); toBody - a body or a vessel
//   solverType - "Gauss" or "Gooding", as for porkchopDeltaV
//   orbitSpec - from orbitSpecFromVessel (case 2) or designSpec (case 1)
//   captureRadius - see arrivalDeltaV
//   precision - from ejectionPrecision: how hard each ejection search works
//   tSOI, timeOfFlight, seed, statsOut - as the departure time, time of flight, seed and
//                statsOut of porkchopDeltaV; statsOut also gets "Ejection" (the LEXICON
//                from ejectionDeltaVForExit) and "Arrival Delta V"
//   exactTiming, earliestBurnUT - see ejectionDeltaVForExit
// The leading arguments (through precision) are in the order bindTransferDeltaV binds
// them, leaving (tSOI, timeOfFlight, seed, statsOut) for a porkchopGrid delegate.
// Both Lambert solutions are costed, but cheaply first: the arrival is exact and the ejection
// has a rigorous lower bound (ejectionLowerBound), so the solution that looks cheaper is searched
// first and the other one's ejection search is skipped if its lower bound can't beat the first.
// Returns invalidDeltaV if neither solution works.
FUNCTION transferDeltaV {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER solverType.
	PARAMETER orbitSpec.
	PARAMETER captureRadius.
	PARAMETER precision.
	PARAMETER tSOI.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER statsOut IS LEXICON().
	PARAMETER exactTiming IS FALSE.
	PARAMETER earliestBurnUT IS 0.

	LOCAL shortStartSeed IS 0.5.
	IF seed:HASKEY("shortSeed") SET shortStartSeed TO seed["shortSeed"].
	LOCAL longStartSeed IS 0.5.
	IF seed:HASKEY("longSeed") SET longStartSeed TO seed["longSeed"].

	// The destination's position and velocity are those at ARRIVAL (tSOI + timeOfFlight), which is
	// where the Lambert arc has to end.
	LOCAL arrivalTime IS tSOI + timeOfFlight.
	LOCAL departurePosition IS absolutePosition(fromBody, tSOI) - absolutePosition(sunBody, tSOI).
	LOCAL arrivalPosition IS absolutePosition(toBody, arrivalTime) - absolutePosition(sunBody, arrivalTime).
	LOCAL fromBodyVelocity IS absoluteVelocity(fromBody, tSOI) - absoluteVelocity(sunBody, tSOI).
	LOCAL toBodyVelocity IS absoluteVelocity(toBody, arrivalTime) - absoluteVelocity(sunBody, arrivalTime).

	LOCAL bestTotalDV IS invalidDeltaV.
	LOCAL winningTrajectory IS 0.
	LOCAL winningEjection IS 0.
	LOCAL winningArrivalDV IS 0.

	// A transfer around a body that has a sphere of influence (not the Sun) must stay inside it.
	LOCAL parentLimit IS 0.
	IF sunBody:NAME <> "Sun" SET parentLimit TO sunBody:SOIRADIUS.

	IF timeOfFlight > 0 {
		LOCAL shortTrajectory IS 0.
		LOCAL longTrajectory IS 0.
		IF solverType = "Gooding" {
			SET shortTrajectory TO lambertGooding(departurePosition, arrivalPosition, timeOfFlight, sunBody:MU, TRUE, shortStartSeed).
			SET longTrajectory TO lambertGooding(departurePosition, arrivalPosition, timeOfFlight, sunBody:MU, FALSE, longStartSeed).
		} ELSE {
			SET shortTrajectory TO lambertGauss(departurePosition, arrivalPosition, timeOfFlight, sunBody:MU, TRUE, shortStartSeed).
			SET longTrajectory TO lambertGauss(departurePosition, arrivalPosition, timeOfFlight, sunBody:MU, FALSE, longStartSeed).
		}

		// The cheap part: for each usable solution, the exit velocity, the arrival cost, and a
		// lower bound on the total.
		LOCAL candidates IS LIST().
		FOR trajectory IN LIST(shortTrajectory, longTrajectory) {
			IF trajectory["Motion Type"] <> "Failed" {
				IF trajectory["Short Way"] SET seed["shortSeed"] TO trajectory["Final Value"].
				ELSE SET seed["longSeed"] TO trajectory["Final Value"].

				LOCAL vExit IS trajectory["v_1"] - fromBodyVelocity.
				LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * orbitSpec["mu"] / fromBody:SOIRADIUS.
				LOCAL sweepAngle IS VANG(departurePosition, arrivalPosition).
				IF NOT trajectory["Short Way"] SET sweepAngle TO 360 - sweepAngle.
				IF vInfinitySquared > 0 AND transferArcClears(departurePosition, trajectory["v_1"], sweepAngle, sunBody:MU, 0, parentLimit) {
					LOCAL arrivalDV IS arrivalDeltaV(trajectory["v_2"] - toBodyVelocity, toBody, captureRadius).
					candidates:ADD(LEXICON("trajectory", trajectory, "vExit", vExit, "arrivalDV", arrivalDV,
											"lowerBound", ejectionLowerBound(orbitSpec, SQRT(vInfinitySquared)) + arrivalDV)).
				}
			}
		}

		// Search the one that looks cheaper first.
		IF candidates:LENGTH = 2 {
			IF candidates[1]["lowerBound"] < candidates[0]["lowerBound"] {
				LOCAL firstCandidate IS candidates[0].
				SET candidates[0] TO candidates[1].
				SET candidates[1] TO firstCandidate.
			}
		}

		FOR candidate IN candidates {
			// Skip the expensive ejection search if even the best case can't beat what we have.
			IF candidate["lowerBound"] < bestTotalDV {
				LOCAL ejection IS ejectionDeltaVForExit(orbitSpec, candidate["vExit"], fromBody, tSOI, exactTiming, precision, earliestBurnUT).
				IF ejection["deltaV"] < invalidDeltaV AND ejection["deltaV"] + candidate["arrivalDV"] < bestTotalDV {
					SET bestTotalDV TO ejection["deltaV"] + candidate["arrivalDV"].
					SET winningTrajectory TO candidate["trajectory"].
					SET winningEjection TO ejection.
					SET winningArrivalDV TO candidate["arrivalDV"].
				}
			}
		}
	}

	// Mutate the caller's statsOut in place (see the note in porkchopDeltaV on why).
	IF winningTrajectory:ISTYPE("Lexicon") {
		FOR statKey IN winningTrajectory:KEYS {
			SET statsOut[statKey] TO winningTrajectory[statKey].
		}
		SET statsOut["Ejection"] TO winningEjection.
		SET statsOut["Arrival Delta V"] TO winningArrivalDV.
	} ELSE {
		SET statsOut["Motion Type"] TO "Failed".
	}
	RETURN bestTotalDV.
}

// Returns a delegate f(tSOI, timeOfFlight, seed, statsOut) -> total dV (phase-free), with
// everything fixed for a whole search bound in - suitable for porkchopGrid and hillClimb2D.
// precision (from ejectionPrecision) sets how hard each ejection search works: "quick" for a
// coarse search, "full" for anything that is reported.
FUNCTION bindTransferDeltaV {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER solverType.
	PARAMETER orbitSpec.
	PARAMETER captureRadius IS 0.
	PARAMETER precision IS ejectionPrecision("full").

	LOCAL bound IS transferDeltaV@.
	SET bound TO bound:BIND(fromBody).
	SET bound TO bound:BIND(toBody).
	SET bound TO bound:BIND(sunBody).
	SET bound TO bound:BIND(solverType).
	SET bound TO bound:BIND(orbitSpec).
	SET bound TO bound:BIND(captureRadius).
	SET bound TO bound:BIND(precision).
	RETURN bound.
}


// ----------------------------------------------------------------------------
// Exact timing, and the node
// ----------------------------------------------------------------------------

// Final stage for a ship already in orbit: takes the (tSOI, timeOfFlight) a grid search
// settled on and finds the exact tSOI, within a parking period of it, at which the burn
// point the orbit forces is cheapest. The Lambert solution is recomputed at every trial
// tSOI, so the exit velocity follows along. (Lambert changes only slightly across one
// parking period, but the burn's position in the orbit sweeps all the way round.)
//   windowLength - s, centred on tSOI; defaults to one parking period
//   samples      - trial tSOI values across the window before polishing
//   earliestBurnUT - burns earlier than this (e.g. now + a margin) are ruled out
// Returns a LEXICON: "tSOI", "deltaV" (invalidDeltaV if nothing works), and "stats"
// (the statsOut of transferDeltaV at that tSOI; stats["Ejection"] has the burn).
FUNCTION refineTransferTiming {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER solverType.
	PARAMETER orbitSpec.
	PARAMETER captureRadius.
	PARAMETER tSOI.
	PARAMETER timeOfFlight.
	PARAMETER windowLength IS -1.
	PARAMETER samples IS 24.
	PARAMETER earliestBurnUT IS 0.

	LOCAL searchLength IS windowLength.
	IF searchLength < 0 SET searchLength TO orbitSpec["period"].
	LOCAL stepLength IS searchLength / samples.

	// One trial: the exact-timing cost at trialTSOI, with burns that are too early ruled out.
	FUNCTION trialAt {
		PARAMETER trialTSOI.

		LOCAL trialStats IS LEXICON().
		// Always full precision: this stage produces the answer that gets reported and flown.
		LOCAL trialDV IS transferDeltaV(fromBody, toBody, sunBody, solverType, orbitSpec, captureRadius, ejectionPrecision("full"),
										trialTSOI, timeOfFlight, LEXICON(), trialStats, TRUE, earliestBurnUT).
		IF trialStats:HASKEY("Ejection") {
			IF trialStats["Ejection"]["tooEarly"] SET trialDV TO invalidDeltaV.
		}
		RETURN LEXICON("tSOI", trialTSOI, "deltaV", trialDV, "stats", trialStats).
	}
	FUNCTION costAt {
		PARAMETER trialTSOI.
		RETURN trialAt(trialTSOI)["deltaV"].
	}

	LOCAL best IS LEXICON("tSOI", tSOI, "deltaV", invalidDeltaV, "stats", LEXICON()).
	FOR sampleIndex IN RANGE(0, samples + 1) {
		LOCAL trial IS trialAt(tSOI - searchLength / 2 + sampleIndex * stepLength).
		IF trial["deltaV"] < best["deltaV"] SET best TO trial.
	}
	IF best["deltaV"] >= invalidDeltaV RETURN best.

	// Polish around the best sample; keep it only if it actually is better.
	LOCAL polished IS trialAt(goldenSectionMinimum(costAt@, best["tSOI"] - stepLength, best["tSOI"] + stepLength, 12)).
	IF polished["deltaV"] < best["deltaV"] SET best TO polished.
	RETURN best.
}

// A much faster route to the same answer as refineTransferTiming, for a ship already in orbit:
// lock the departure to the best burn PHASE instead of scanning departure times.
//
// The parking orbit repeats every period, so every burn phase occurs once per period. The
// cheapest exact-timing burn is therefore the phase-free best burn point (bestEjectionFromOrbit),
// moved to whichever repeat lies nearest the grid's departure time: that fixes the SOI exit
// time as burn time + transit time + a whole number of periods. Lambert then has to be recomputed
// at that new exit time (it changes only slightly, so this settles in a pass or two); each pass
// re-prices at full precision and moves tSOI to the phase it finds. One exact-timing solve at the
// end gives the burn the node needs.
// (Checked offline at a fixed exit velocity: pricing at tSOI = best phase's exit time gives the
// phase-free minimum. What this ignores, against refineTransferTiming, is the tiny variation of the
// Lambert cost across at most half a parking period, which is a second-order effect at a minimum.)
//   tSOI, timeOfFlight - from the grid / hill climb
//   earliestBurnUT     - burns earlier than this (e.g. now + a margin) are not allowed; the departure
//                        moves a period later instead
//   maxPasses          - at most this many phase-lock passes (it stops early once tSOI moves less than
//                        0.2% of the orbit period, which is about the resolution of the burn-point search,
//                        or once the price agrees with the previous pass to 0.1 m/s)
// Returns a LEXICON like refineTransferTiming: "tSOI", "deltaV" (invalidDeltaV if nothing works),
// "stats" (stats["Ejection"] has the burn), plus "phaseFreeDeltaV" (the price of the best burn point
// anywhere in the orbit, for comparison) and "passes".
FUNCTION phaseLockedDeparture {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER solverType.
	PARAMETER orbitSpec.
	PARAMETER captureRadius.
	PARAMETER tSOI.
	PARAMETER timeOfFlight.
	PARAMETER earliestBurnUT IS 0.
	PARAMETER maxPasses IS 4.

	LOCAL period IS orbitSpec["period"].
	LOCAL currentTSOI IS tSOI.
	LOCAL phaseFreeDeltaV IS invalidDeltaV.
	LOCAL previousDeltaV IS invalidDeltaV.
	LOCAL passesUsed IS 0.

	UNTIL passesUsed >= maxPasses {
		LOCAL stats IS LEXICON().
		LOCAL totalDV IS transferDeltaV(fromBody, toBody, sunBody, solverType, orbitSpec, captureRadius, ejectionPrecision("full"),
										currentTSOI, timeOfFlight, LEXICON(), stats, FALSE, 0).
		IF totalDV >= invalidDeltaV BREAK.
		SET phaseFreeDeltaV TO totalDV.
		SET passesUsed TO passesUsed + 1.

		// When the best burn point is reached, and when the ship then crosses the SOI edge.
		LOCAL ejection IS stats["Ejection"].
		LOCAL transit IS ejection["ejection"]["transitTime"].
		LOCAL exitUT IS orbitSpec["epoch"] + ejection["offset"] + transit.

		// The repeat of that moment nearest the current tSOI, and no burn before earliestBurnUT.
		LOCAL lockedTSOI IS exitUT + ROUND((currentTSOI - exitUT) / period) * period.
		UNTIL lockedTSOI - transit >= earliestBurnUT {
			SET lockedTSOI TO lockedTSOI + period.
		}
		LOCAL movement IS ABS(lockedTSOI - currentTSOI).
		SET currentTSOI TO lockedTSOI.
		// The burn-point search places the best burn to about 0.3 degrees of orbit, so the locked time
		// jitters by a couple of seconds from pass to pass; a tenth of a percent of the period is
		// as settled as it can get (about 5 s for a 45-minute orbit). It can also move more than that
		// while the price has stopped changing (a flat optimum, or two near-equal burn phases), and
		// then further passes only cost time, so a price that agrees with the previous pass to
		// 0.1 m/s counts as settled too.
		IF movement < 0.002 * period BREAK.
		IF passesUsed >= 2 AND ABS(totalDV - previousDeltaV) < 0.1 BREAK.
		SET previousDeltaV TO totalDV.
	}

	LOCAL result IS LEXICON("tSOI", currentTSOI, "deltaV", invalidDeltaV, "stats", LEXICON(),
							"phaseFreeDeltaV", phaseFreeDeltaV, "passes", passesUsed).
	IF phaseFreeDeltaV >= invalidDeltaV RETURN result.

	// The exact-timing solve at the locked departure: its burn is the one the node needs.
	LOCAL finalStats IS LEXICON().
	LOCAL finalDV IS transferDeltaV(fromBody, toBody, sunBody, solverType, orbitSpec, captureRadius, ejectionPrecision("full"),
									currentTSOI, timeOfFlight, LEXICON(), finalStats, TRUE, earliestBurnUT).
	IF finalDV < invalidDeltaV AND finalStats:HASKEY("Ejection") {
		IF NOT finalStats["Ejection"]["tooEarly"] {
			SET result["deltaV"] TO finalDV.
			SET result["stats"] TO finalStats.
		}
	}
	RETURN result.
}

// Adds a maneuver node for an exact-timing ejection (the "Ejection" LEXICON from
// refineTransferTiming / ejectionForExitTime), carrying the whole burn vector - radial,
// normal and prograde - so the node's delta-V is the true cost, plane change included.
// The sign of the node's normal axis depends on coordinate handedness, so each choice is
// checked against the node's own :DELTAV and the one that matches is kept.
// Returns LEXICON("created", "verified", "prograde", "normal", "radial", "nodeError").
FUNCTION addEjectionNode {
	PARAMETER ejection.
	PARAMETER clearExistingNodes IS TRUE.

	IF clearExistingNodes {
		clearManeuverNodes().
	}

	// The node's own axes at the burn: prograde along the velocity, normal along the
	// orbit normal, radial the remaining outward axis.
	LOCAL dvVector IS ejection["dvVector"].
	LOCAL progradeUnit IS ejection["parkVelocity"]:NORMALIZED.
	LOCAL normalUnit IS VCRS(ejection["burnPosition"], ejection["parkVelocity"]):NORMALIZED.
	LOCAL radialUnit IS VCRS(progradeUnit, normalUnit):NORMALIZED.
	IF VDOT(radialUnit, ejection["burnPosition"]) < 0 SET radialUnit TO -radialUnit.
	LOCAL progradeDV IS VDOT(dvVector, progradeUnit).
	LOCAL normalDV IS VDOT(dvVector, normalUnit).
	LOCAL radialDV IS VDOT(dvVector, radialUnit).

	LOCAL tolerance IS dvVector:MAG * 0.01.
	LOCAL firstNode IS NODE(ejection["burnUT"], radialDV, normalDV, progradeDV).
	ADD firstNode.
	LOCAL nodeError IS (firstNode:DELTAV - dvVector):MAG.
	IF nodeError > tolerance {
		REMOVE firstNode.
		LOCAL flippedNode IS NODE(ejection["burnUT"], radialDV, -normalDV, progradeDV).
		ADD flippedNode.
		LOCAL flippedError IS (flippedNode:DELTAV - dvVector):MAG.
		IF flippedError > nodeError {
			// Neither matches; fall back to the first and let "verified" say so.
			REMOVE flippedNode.
			ADD NODE(ejection["burnUT"], radialDV, normalDV, progradeDV).
		} ELSE {
			SET nodeError TO flippedError.
		}
	}
	RETURN LEXICON("created", TRUE, "verified", nodeError <= tolerance,
					"prograde", progradeDV, "normal", normalDV, "radial", radialDV, "nodeError", nodeError).
}


// ----------------------------------------------------------------------------
// Parking-plane design (moved here from transferCalc.ks)
// ----------------------------------------------------------------------------

// -- PLANE-AWARE -- (new) ----------------------------------------------------
// Builds the normal vector of a (possibly not-yet-flown) parking orbit purely
// from inclination and LAN, by rotating the body's own equatorial normal (its
// spin axis -- the same reference KSP measures inclination against). Usable at
// the design stage, before any vessel exists in that orbit.
//
// Handedness: KSP's (Unity's) coordinates are left-handed, so a rotation by a positive angle
// and VCRS both turn the opposite way to the usual right-handed picture. The ascending node
// rotated from the prime vector by +LAN about the spin axis is right as it stands, but the
// plane must tilt by -inclination about that node, not +inclination. (Confirmed in-game against
// the ship's own orbit and nine bodies, measured from POSITIONAT samples: every normal matched.
// A normal measured from :VELOCITY:ORBIT was wrong for several far-away bodies, so that is not
// a reliable way to measure one.)
// Written with the documented Direction * Vector form; the old Vector * Direction form was
// checked in-game and does the same thing, so this does not change the result.
FUNCTION getOrbitPlaneNormal {
	PARAMETER centralBody.
	PARAMETER inclinationDeg.
	PARAMETER lanDeg.

	LOCAL equatorialNormal IS centralBody:ANGULARVEL:NORMALIZED.
	LOCAL primeInPlane IS VXCL(equatorialNormal, SOLARPRIMEVECTOR):NORMALIZED.
	LOCAL ascendingNodeDir IS ANGLEAXIS(lanDeg, equatorialNormal) * primeInPlane.
	RETURN (ANGLEAXIS(-inclinationDeg, ascendingNodeDir) * equatorialNormal):NORMALIZED.
}


// -- PLANE-AWARE -- (new) ----------------------------------------------------
// For the not-yet-launched case: there's no real parking orbit yet, so instead
// of checking a plane mismatch, this computes the plane that WOULD give zero
// mismatch, so it can be printed as a launch target. Among every plane that
// contains v_infinity's direction, the minimum-inclination one is found by
// projecting the body's spin axis onto the plane perpendicular to v_infinity
// (VXCL does exactly this) - a standard result: the minimum achievable
// inclination for a departure plane equals the declination of v_infinity
// above the body's equator, and this constructs it directly as a vector
// operation instead of via that trig identity, so it doesn't depend on getting
// a separate declination/right-ascension formula's sign conventions right.
//
// Uses the SAME primeInPlane/eastInPlane construction as getOrbitPlaneNormal,
// so it's self-consistent with it by construction; the verificationResidual
// field feeds the computed (inclination, lan) back through getOrbitPlaneNormal
// and reports the leftover mismatch, which should come back at ~0. Print it -
// if it's not close to zero, the two functions' conventions have diverged
// somehow and the recommendation shouldn't be trusted until that's found.
FUNCTION computeMinimumInclinationPlane {
	PARAMETER centralBody.
	PARAMETER vInfinityVector.

	LOCAL equatorialNormal IS centralBody:ANGULARVEL:NORMALIZED.
	LOCAL primeInPlane IS VXCL(equatorialNormal, SOLARPRIMEVECTOR):NORMALIZED.
	LOCAL eastInPlane IS VCRS(equatorialNormal, primeInPlane):NORMALIZED.

	LOCAL vHat IS vInfinityVector:NORMALIZED.
	LOCAL minNormal IS VXCL(vHat, equatorialNormal):NORMALIZED.
	LOCAL inclination IS VANG(minNormal, equatorialNormal).
	// The ascending node is VCRS(minNormal, pole) (not VCRS(pole, minNormal)) because of the
	// left-handed tilt described at getOrbitPlaneNormal.
	LOCAL ascendingNodeDir IS VCRS(minNormal, equatorialNormal):NORMALIZED.
	LOCAL lan IS normalizeAngle360(ARCTAN2(VDOT(ascendingNodeDir, eastInPlane), VDOT(ascendingNodeDir, primeInPlane))).

	LOCAL checkNormal IS getOrbitPlaneNormal(centralBody, inclination, lan).
	LOCAL verificationResidual IS 90 - VANG(vInfinityVector, checkNormal).

	RETURN LEXICON("inclination", inclination, "lan", lan, "verificationResidual", verificationResidual).
}

// -- PLANE-AWARE -- (new) ----------------------------------------------------
// A direct-ascent launch can never reach an inclination LOWER than the launch
// site's latitude (that needs a dogleg); it can always reach any inclination
// AT OR ABOVE it. So if the pure minimum-inclination plane above sits below
// the launch site's latitude, that plane isn't actually reachable - the real
// floor on achievable inclination is whichever of the two is further from the
// equator. This solves for the ascending node(s) that keep the plane
// containing v_infinity exactly once the inclination is raised to that floor.
//
// Derivation: writing v_infinity in the (primeInPlane, eastInPlane,
// equatorialNormal) basis as (vx, vy, vz), the zero-mismatch condition
// VDOT(h_hat(i,LAN), v_infinity) = 0 reduces to
//     vx*SIN(LAN) - vy*COS(LAN) = vz*COS(i)/SIN(i)
// (the plane's normal is (-SIN(i)*SIN(LAN), SIN(i)*COS(LAN), COS(i)) in that basis, because of
// the left-handed tilt described at getOrbitPlaneNormal)
// whose left side is R*SIN(LAN - phi) with R = SQRT(vx^2+vy^2), phi =
// ARCTAN2(vy,vx) - giving zero, one, or two solutions for LAN depending on
// whether the right-hand side's magnitude is above, at, or below 1.
FUNCTION solveLANForInclination {
	PARAMETER centralBody.
	PARAMETER vInfinityVector.
	PARAMETER inclinationDeg.

	LOCAL equatorialNormal IS centralBody:ANGULARVEL:NORMALIZED.
	LOCAL primeInPlane IS VXCL(equatorialNormal, SOLARPRIMEVECTOR):NORMALIZED.
	LOCAL eastInPlane IS VCRS(equatorialNormal, primeInPlane):NORMALIZED.
	LOCAL vHat IS vInfinityVector:NORMALIZED.

	LOCAL vx IS VDOT(vHat, primeInPlane).
	LOCAL vy IS VDOT(vHat, eastInPlane).
	LOCAL vz IS VDOT(vHat, equatorialNormal).

	IF (inclinationDeg <= 0.0001) OR (inclinationDeg >= 179.9999) RETURN LIST().

	LOCAL pos IS SQRT(vx ^ 2 + vy ^ 2).
	LOCAL phi IS ARCTAN2(vy, vx).
	LOCAL rhs IS vz * COS(inclinationDeg) / (SIN(inclinationDeg) * pos).
	IF ABS(rhs) > 1.0001 RETURN LIST(). // this inclination is below the true minimum - shouldn't happen if the caller respects it
	LOCAL clampedRhs IS MAX(-1, MIN(1, rhs)).
	LOCAL asinVal IS ARCSIN(clampedRhs).

	RETURN LIST(normalizeAngle360(phi + asinVal), normalizeAngle360(phi + 180 - asinVal)).
}

// -- PLANE-AWARE -- (new) ----------------------------------------------------
// Top-level recommendation used by the not-launched branch: the pure
// minimum-inclination plane, raised to the launch site's latitude if that's
// the more restrictive (further-from-equator) floor, with the ascending node
// re-solved so the plane still contains v_infinity exactly either way.
FUNCTION computeRecommendedParkingPlane {
	PARAMETER centralBody.
	PARAMETER vInfinityVector.
	PARAMETER launchLatitude.

	LOCAL pureMin IS computeMinimumInclinationPlane(centralBody, vInfinityVector).
	LOCAL latitudeFloor IS ABS(launchLatitude).
	LOCAL binding IS latitudeFloor > pureMin["inclination"].

	LOCAL finalInclination IS MAX(pureMin["inclination"], latitudeFloor).
	LOCAL finalLan IS pureMin["lan"].
	LOCAL alternateLan IS pureMin["lan"].

	IF binding {
		LOCAL lanOptions IS solveLANForInclination(centralBody, vInfinityVector, finalInclination).
		IF lanOptions:LENGTH = 2 {
			// Pick whichever of the two valid nodes is the smaller angular
			// change from the pure-minimum-inclination LAN, so the "primary"
			// answer stays as close as possible to the unconstrained one; the
			// other is still reported as a valid alternate.
			LOCAL diff1 IS ABS(normalizeAngle180(lanOptions[0] - pureMin["lan"])).
			LOCAL diff2 IS ABS(normalizeAngle180(lanOptions[1] - pureMin["lan"])).
			IF diff1 <= diff2 {
				SET finalLan TO lanOptions[0].
				SET alternateLan TO lanOptions[1].
			} ELSE {
				SET finalLan TO lanOptions[1].
				SET alternateLan TO lanOptions[0].
			}
		}
		// else: solveLANForInclination came back empty, meaning finalInclination
		// was somehow still below the true minimum (shouldn't happen since
		// finalInclination = MAX(pureMin, latitudeFloor) >= pureMin) - fall
		// through and leave finalLan/alternateLan at the pure-minimum values,
		// which the verificationResidual below will then correctly flag as
		// nonzero, rather than silently claiming a clean match.
	}

	LOCAL checkNormal IS getOrbitPlaneNormal(centralBody, finalInclination, finalLan).
	LOCAL verificationResidual IS 90 - VANG(vInfinityVector, checkNormal).

	RETURN LEXICON("inclination", finalInclination,
	               "lan", finalLan,
	               "alternateLan", alternateLan,
	               "latitudeConstraintBinding", binding,
	               "pureMinimumInclination", pureMin["inclination"],
	               "verificationResidual", verificationResidual).
}


// ============================================================================
// Choosing the endpoints of a transfer, and transfers inside a single SOI
// ============================================================================

// Works out what a transfer goes from and to, from the destination alone.
//   destinationName - a body or a vessel (resolveOrbitable: a vessel wins a name clash)
//   sourceName      - "" (the default) to infer the source from where the ship is; otherwise the
//                     name of the source to use instead
// With no source given, the source is
//   - the SHIP, when the destination orbits the body the ship is in (a vessel or a moon in the
//     same sphere of influence). This is a same-SOI transfer: no sphere of influence is left.
//   - the body the ship is in, when the destination orbits that body's parent (Duna from Kerbin
//     orbit, Minmus from Mun orbit, a vessel in solar orbit from Kerbin orbit). The ship leaves
//     that body's SOI.
// Anything else (the destination's parent is the body the ship is in, or it is in a different
// system altogether, like Kerbin from Mun orbit or Duna from Mun orbit) is an error.
// A given source must orbit the same body as the destination.
// Returns a LEXICON: "error" ("None", or a message), "from", "to" (orbitables), and "sameSOI"
// (TRUE if the source is a vessel, i.e. the transfer stays inside one SOI).
FUNCTION resolveTransferEndpoints {
	PARAMETER destinationName.
	PARAMETER sourceName IS "".

	LOCAL endpoints IS LEXICON("error", "None", "from", 0, "to", 0, "sameSOI", FALSE).

	LOCAL toOrbitable IS resolveOrbitable(destinationName).
	IF toOrbitable:ISTYPE("Scalar") {
		SET endpoints["error"] TO destinationName + " does not exist!".
		RETURN endpoints.
	}

	LOCAL here IS SHIP:BODY.
	LOCAL hereParent IS "".
	IF here:HASBODY SET hereParent TO here:BODY:NAME.
	LOCAL toParent IS "".
	IF toOrbitable:HASBODY SET toParent TO toOrbitable:BODY:NAME.
	LOCAL fromOrbitable IS 0.
	IF sourceName <> "" {
		SET fromOrbitable TO resolveOrbitable(sourceName).
		IF fromOrbitable:ISTYPE("Scalar") {
			SET endpoints["error"] TO sourceName + " does not exist!".
			RETURN endpoints.
		}
	} ELSE {
		IF toOrbitable:ISTYPE("Vessel") AND toOrbitable:NAME = SHIP:NAME {
			SET endpoints["error"] TO destinationName + " is the ship itself!".
			RETURN endpoints.
		}
		IF toOrbitable:NAME = here:NAME {
			SET endpoints["error"] TO "The ship is already in " + here:NAME + "'s sphere of influence!".
			RETURN endpoints.
		}
		IF toParent = here:NAME {
			SET fromOrbitable TO SHIP.
		} ELSE IF toParent <> "" AND toParent = hereParent {
			SET fromOrbitable TO here.
		} ELSE {
			SET endpoints["error"] TO destinationName + " (orbiting " + toParent + ") is in a different system from the ship (in " + here:NAME + "'s sphere of influence)!".
			RETURN endpoints.
		}
	}

	IF fromOrbitable:NAME = toOrbitable:NAME {
		SET endpoints["error"] TO "The source and the destination are the same!".
		RETURN endpoints.
	}
	LOCAL fromParent IS "".
	IF fromOrbitable:HASBODY SET fromParent TO fromOrbitable:BODY:NAME.
	IF fromParent = "" OR fromParent <> toParent {
		SET endpoints["error"] TO fromOrbitable:NAME + " and " + toOrbitable:NAME + " do not orbit the same body!".
		RETURN endpoints.
	}

	SET endpoints["from"] TO fromOrbitable.
	SET endpoints["to"] TO toOrbitable.
	SET endpoints["sameSOI"] TO fromOrbitable:ISTYPE("Vessel").
	RETURN endpoints.
}

// The search window for either kind of transfer, with default sample counts chosen to suit it.
//   endpoints        - from resolveTransferEndpoints
//   startOffset      - s from now to the start of the first window (>= 30)
//   departureWindows - how many windows to search, back to back. Between two bodies a window is a
//                      synodic period. In the same SOI it is shorter (see below).
//   samplesPerWindow - departure times per window; below 1 (-1) chooses a default
//   tofSamples       - flight times; below 1 (-1) chooses a default
//   coarse           - TRUE for a coarse search that is refined afterwards (transferCalc), FALSE for
//                      a fine one that is plotted (porkchopplot): only affects the defaults
// A same-SOI window is one synodic period of the two orbits, or four orbits of the ship if that is
// shorter (the cost repeats with the ship's orbit, so the departure axis needs a dozen or two
// samples per ship orbit; two nearly-equal orbits have a synodic period of thousands of orbits).
// Defaults: between bodies 4 x 5 (coarse) or 40 x 41 (fine); in the same SOI 12 (coarse) or 24
// (fine) departures per ship orbit and 7 or 31 flight times.
// Returns a window LEXICON as for transferSearchWindow ("error" set if something is wrong), with
// "windowLength" (s) and "samplesPerWindow" added.
FUNCTION buildTransferWindow {
	PARAMETER endpoints.
	PARAMETER startOffset.
	PARAMETER departureWindows.
	PARAMETER samplesPerWindow.
	PARAMETER tofSamples.
	PARAMETER coarse IS TRUE.

	IF startOffset < 30 RETURN LEXICON("error", "Start time offset must be >= 30 seconds!").
	LOCAL fromOrbitable IS endpoints["from"].
	LOCAL toOrbitable IS endpoints["to"].
	LOCAL startUT IS TIME:SECONDS + startOffset.

	LOCAL window IS 0.
	LOCAL perWindow IS samplesPerWindow.
	LOCAL flightSamples IS tofSamples.

	IF endpoints["sameSOI"] {
		IF fromOrbitable:ORBIT:ECCENTRICITY >= 1 OR toOrbitable:ORBIT:ECCENTRICITY >= 1 {
			RETURN LEXICON("error", "Both orbits must be bound (not escape trajectories) for a transfer inside one SOI!").
		}
		LOCAL shipPeriod IS fromOrbitable:ORBIT:PERIOD.
		LOCAL targetPeriod IS toOrbitable:ORBIT:PERIOD.
		IF ABS(1 / shipPeriod - 1 / targetPeriod) < 1e-9 {
			RETURN LEXICON("error", "The two orbits have the same period - there is no relative motion to plan around!").
		}
		LOCAL windowLength IS MIN(1 / ABS(1 / shipPeriod - 1 / targetPeriod), 4 * shipPeriod).
		LOCAL perOrbit IS 24.
		IF coarse SET perOrbit TO 12.
		IF perWindow < 1 SET perWindow TO MAX(12, MIN(240, ROUND(windowLength / shipPeriod * perOrbit))).
		IF flightSamples < 1 {
			SET flightSamples TO 31.
			IF coarse SET flightSamples TO 7.
		}
		SET window TO transferSearchWindow(fromOrbitable, toOrbitable, MAX(1, ROUND(departureWindows * perWindow)), flightSamples,
			departureWindows, startUT, startUT + departureWindows * windowLength).
		IF window["error"] = "None" SET window["windowLength"] TO windowLength.
	} ELSE {
		IF perWindow < 1 {
			SET perWindow TO 40.
			IF coarse SET perWindow TO 4.
		}
		IF flightSamples < 1 {
			SET flightSamples TO 41.
			IF coarse SET flightSamples TO 5.
		}
		SET window TO transferSearchWindow(fromOrbitable, toOrbitable, MAX(1, ROUND(departureWindows * perWindow)), flightSamples,
			departureWindows, startUT).
	}
	IF window["error"] = "None" SET window["samplesPerWindow"] TO perWindow.
	RETURN window.
}

// The orbit of an orbitable around centralBody, as an orbit spec (see makeOrbitSpec), as of now.
// The ship's own state is read directly; for anything else the position is taken relative to the
// central body and the velocity from VELOCITYAT (:VELOCITY:ORBIT is not parent-relative for an
// orbitable that is not the ship).
FUNCTION orbitSpecAround {
	PARAMETER orbitable.
	PARAMETER centralBody.

	IF orbitable:ISTYPE("Vessel") AND orbitable:NAME = SHIP:NAME RETURN orbitSpecFromVessel(SHIP).
	RETURN makeOrbitSpec(orbitable:POSITION - centralBody:POSITION, VELOCITYAT(orbitable, TIME:SECONDS):ORBIT,
							TIME:SECONDS, centralBody:MU, bodyClearanceRadius(centralBody)).
}

// Whether a Lambert arc stays clear of the central body and inside its sphere of influence. The arc
// starts at startPosition with startVelocity and sweeps sweepAngle degrees round the central body.
// Its lowest point is an end (which are above minRadius) or the periapsis of its orbit, if the arc
// passes it; its highest is an end or, for a bound orbit, the apoapsis, if the arc passes that.
//   minRadius - m from the centre; an arc whose periapsis is lower (and reached) is rejected
//   maxRadius - m from the centre, normally the SOI radius; an arc that reaches an apoapsis higher than
//               this is rejected (the real path would leave the sphere of influence). 0 means no limit.
FUNCTION transferArcClears {
	PARAMETER startPosition.
	PARAMETER startVelocity.
	PARAMETER sweepAngle.
	PARAMETER mu.
	PARAMETER minRadius.
	PARAMETER maxRadius IS 0.

	LOCAL startRadius IS startPosition:MAG.
	LOCAL momentum IS VCRS(startPosition, startVelocity):MAG.
	LOCAL semiLatus IS momentum ^ 2 / mu.
	LOCAL eccentricity IS SQRT(MAX(0, 1 + (startVelocity:MAG ^ 2 - 2 * mu / startRadius) * momentum ^ 2 / mu ^ 2)).
	IF eccentricity < 1e-6 RETURN startRadius >= minRadius.

	LOCAL tooLow IS semiLatus / (1 + eccentricity) < minRadius.
	LOCAL tooHigh IS FALSE.
	IF maxRadius > 0 AND eccentricity < 1 SET tooHigh TO semiLatus / (1 - eccentricity) > maxRadius.
	IF NOT tooLow AND NOT tooHigh RETURN TRUE.

	// An extreme is only a problem if the arc gets there. The true anomaly grows along the arc: the
	// periapsis is at 360 degrees and the apoapsis at 180 or 540.
	LOCAL startAnomaly IS ARCCOS(MAX(-1, MIN(1, (semiLatus / startRadius - 1) / eccentricity))).
	IF VDOT(startPosition, startVelocity) < 0 SET startAnomaly TO 360 - startAnomaly.
	LOCAL endAnomaly IS startAnomaly + sweepAngle.
	IF tooLow AND endAnomaly >= 360 RETURN FALSE.
	IF tooHigh AND ((startAnomaly < 180 AND endAnomaly > 180) OR endAnomaly > 540) RETURN FALSE.
	RETURN TRUE.
}
// Total delta-V (m/s) of a transfer that stays inside one SOI: a burn at departureTime on the
// ship's own orbit onto a Lambert arc that meets the target timeOfFlight later, and a burn to match
// the target's velocity (arrivalDeltaV) there. There is no sphere of influence to leave, so the burn
// time IS the departure time and no exit hyperbola is involved. The better of Lambert's short-way and
// long-way arcs is taken; an arc that dips below the central body's surface (or atmosphere) is
// rejected, and so is a transfer angle within 0.05 degrees of 0 or 180 where Lambert's plane is
// undefined. Both orbits are propagated as Kepler orbits from the specs.
//   fromSpec, toSpec  - orbit specs of the ship and the target (orbitSpecAround)
//   toOrbitable       - the target (a vessel: arrival matches its velocity; a body: see arrivalDeltaV)
//   solverType        - "Gauss" or "Gooding"
//   captureRadius     - see arrivalDeltaV
//   earliestDeparture - UT; an earlier departure is invalid (a burn in the past cannot be flown)
//   maxRadius         - m, the central body's SOI radius (0 for none): an arc whose apoapsis is higher is rejected
//   departureTime, timeOfFlight, seed, statsOut - as for transferDeltaV. statsOut gets the winning
//                       Lambert data, "Arrival Delta V" and "Ejection": a LEXICON with "deltaV",
//                       "dvVector", "burnPosition", "parkVelocity" and "burnUT", the keys addEjectionNode needs
// The leading arguments are in the order bindSameSOIDeltaV binds them.
FUNCTION sameSOITransferDeltaV {
	PARAMETER fromSpec.
	PARAMETER toSpec.
	PARAMETER toOrbitable.
	PARAMETER solverType.
	PARAMETER captureRadius.
	PARAMETER earliestDeparture.
	PARAMETER maxRadius.
	PARAMETER departureTime.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER statsOut IS LEXICON().

	LOCAL shortStartSeed IS 0.5.
	IF seed:HASKEY("shortSeed") SET shortStartSeed TO seed["shortSeed"].
	LOCAL longStartSeed IS 0.5.
	IF seed:HASKEY("longSeed") SET longStartSeed TO seed["longSeed"].

	LOCAL mu IS fromSpec["mu"].
	LOCAL bestTotalDV IS invalidDeltaV.
	LOCAL winningTrajectory IS 0.
	LOCAL winningDeparture IS 0.
	LOCAL winningArrivalDV IS 0.

	IF timeOfFlight > 0 AND departureTime >= earliestDeparture {
		LOCAL departureState IS propagateKepler(fromSpec["position"], fromSpec["velocity"], departureTime - fromSpec["epoch"], mu).
		LOCAL arrivalState IS propagateKepler(toSpec["position"], toSpec["velocity"], departureTime + timeOfFlight - toSpec["epoch"], mu).
		LOCAL separation IS VANG(departureState["position"], arrivalState["position"]).

		IF separation > 0.05 AND separation < 179.95 {
			LOCAL shortTrajectory IS 0.
			LOCAL longTrajectory IS 0.
			IF solverType = "Gooding" {
				SET shortTrajectory TO lambertGooding(departureState["position"], arrivalState["position"], timeOfFlight, mu, TRUE, shortStartSeed).
				SET longTrajectory TO lambertGooding(departureState["position"], arrivalState["position"], timeOfFlight, mu, FALSE, longStartSeed).
			} ELSE {
				SET shortTrajectory TO lambertGauss(departureState["position"], arrivalState["position"], timeOfFlight, mu, TRUE, shortStartSeed).
				SET longTrajectory TO lambertGauss(departureState["position"], arrivalState["position"], timeOfFlight, mu, FALSE, longStartSeed).
			}

			FOR trajectory IN LIST(shortTrajectory, longTrajectory) {
				IF trajectory["Motion Type"] <> "Failed" {
					LOCAL sweepAngle IS separation.
					IF trajectory["Short Way"] {
						SET seed["shortSeed"] TO trajectory["Final Value"].
					} ELSE {
						SET seed["longSeed"] TO trajectory["Final Value"].
						SET sweepAngle TO 360 - separation.
					}

					IF transferArcClears(departureState["position"], trajectory["v_1"], sweepAngle, mu, fromSpec["minPeriapsis"], maxRadius) {
						LOCAL burnVector IS trajectory["v_1"] - departureState["velocity"].
						LOCAL arrivalDV IS arrivalDeltaV(trajectory["v_2"] - arrivalState["velocity"], toOrbitable, captureRadius).
						IF burnVector:MAG + arrivalDV < bestTotalDV {
							SET bestTotalDV TO burnVector:MAG + arrivalDV.
							SET winningTrajectory TO trajectory.
							SET winningArrivalDV TO arrivalDV.
							SET winningDeparture TO LEXICON("deltaV", burnVector:MAG, "dvVector", burnVector,
															"burnPosition", departureState["position"], "parkVelocity", departureState["velocity"],
															"burnUT", departureTime).
						}
					}
				}
			}
		}
	}

	// Mutate the caller's statsOut in place (see the note in porkchopDeltaV on why).
	IF winningTrajectory:ISTYPE("Lexicon") {
		FOR statKey IN winningTrajectory:KEYS {
			SET statsOut[statKey] TO winningTrajectory[statKey].
		}
		SET statsOut["Ejection"] TO winningDeparture.
		SET statsOut["Arrival Delta V"] TO winningArrivalDV.
	} ELSE {
		SET statsOut["Motion Type"] TO "Failed".
	}
	RETURN bestTotalDV.
}

// Returns a delegate f(departureTime, timeOfFlight, seed, statsOut) -> total dV for a transfer
// from fromOrbitable (the ship, or another vessel) to toOrbitable inside the SOI of the body they
// both orbit, with everything else bound - suitable for porkchopGrid and hillClimb2D. Both must
// be in bound orbits.
FUNCTION bindSameSOIDeltaV {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER solverType.
	PARAMETER captureRadius IS 0.
	PARAMETER earliestDeparture IS 0.

	LOCAL centralBody IS fromOrbitable:BODY.
	LOCAL bound IS sameSOITransferDeltaV@.
	SET bound TO bound:BIND(orbitSpecAround(fromOrbitable, centralBody)).
	SET bound TO bound:BIND(orbitSpecAround(toOrbitable, centralBody)).
	SET bound TO bound:BIND(toOrbitable).
	SET bound TO bound:BIND(solverType).
	SET bound TO bound:BIND(captureRadius).
	SET bound TO bound:BIND(earliestDeparture).
	SET bound TO bound:BIND(centralBody:SOIRADIUS).
	RETURN bound.
}
