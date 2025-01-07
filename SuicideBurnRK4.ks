@LAZYGLOBAL OFF.
CLEARSCREEN.

//SBbisectionSearch(0).
LOCAL burnInfo IS SBSecantSearch(10).

updateShipInfo().

SAS OFF.
RCS OFF.
SET globalThrottle TO 0.
setLockedThrottle(TRUE).
SET globalSteer TO -VELOCITY:SURFACE.
setLockedSteering(TRUE).
CLEARSCREEN.
UNTIL TIME:SECONDS >= burnInfo["startTime"] {
  PRINT "Burn will start in " + ROUND((burnInfo["startTime"] - TIME:SECONDS), 2) + " seconds              " AT (0, 0).
  WAIT 0.
}
GEAR ON.
UNTIL ((TIME:SECONDS >= burnInfo["startTime"] + burnInfo["burnTime"]) OR (VELOCITY:SURFACE:MAG < 1.0)) {
  PRINT "Burn will last " + ROUND((burnInfo["startTime"] + burnInfo["burnTime"] - TIME:SECONDS), 2) + " seconds              " AT (0, 1).
  SET globalThrottle TO 1.
  SET globalSteer TO -VELOCITY:SURFACE.
  WAIT 0.
}

SET globalThrottle TO 0.
setLockedThrottle(FALSE).
setLockedSteering(FALSE).
SET loopMessage TO "Stopped " + distanceToString(heightAboveGround()) + " above ground".

// find Universal Time of impact with the ground.
// returns UT in seconds.
FUNCTION findImpactUT {
  // returns estimated height above ground of given ship at given time.
  FUNCTION absHeightAtUT {
    PARAMETER utToInspect.
    PARAMETER shipToInspect IS SHIP.
    LOCAL positionOfShip IS POSITIONAT(shipToInspect, utToInspect) - shipToInspect:BODY:POSITION.
    LOCAL groundHeight IS shipToInspect:BODY:RADIUS + shipToInspect:BODY:GEOPOSITIONOF(positionOfShip):TERRAINHEIGHT.
    RETURN ABS(positionOfShip:MAG - groundHeight).
  }
  // FUNCTION hillClimb(delegate, initialGuess, initialStepSize, logFile, iterationMax, smallestStepRatio, cyclicalPeriod, cyclicalPeriodCutoff, deleteOldLogFile).
  RETURN hillClimb(absHeightAtUT@, TIME:SECONDS + 60, 64, "", 100, 20)["finalGuess"].
}

FUNCTION SBSecantSearch {
  PARAMETER marginDistance IS 10.
  PARAMETER marginTime IS 0.02.
  IF marginDistance < 1 SET marginDistance TO 1.
  LOCAL coarseTime IS 1.0.
  LOCAL startTime IS TIME:SECONDS.
  IF EXISTS("0:RK4Search.csv") DELETEPATH("0:RK4Search.csv").
  LOG "Type,Time,iterations,x_n,x_n-1,x_n-2,f(x_n),f(x_n-1),f(x_n-2),Thrust,Mass Flow,Radius,Current Accel,Current Position,Current Velocity,Normalized Accel,Burn Time,Delta V" TO "0:RK4Search.csv".
  LOCAL estimatedBurnStartTime IS findImpactUT() - VELOCITY:SURFACE:MAG/shipInfo["Maximum"]["Accel"].
  LOCAL x_n_minus_2 IS estimatedBurnStartTime - 60.
  LOCAL f_x_n_minus_2 IS simulateSuicideBurnRK(x_n_minus_2, coarseTime, marginDistance, TRUE).
  LOCAL x_n_minus_1 IS estimatedBurnStartTime - 30.
  LOCAL f_x_n_minus_1 IS simulateSuicideBurnRK(x_n_minus_1, coarseTime, marginDistance, TRUE).
  LOCAL x_n IS estimatedBurnStartTime.
  LOCAL f_x_n IS simulateSuicideBurnRK(x_n, coarseTime, marginDistance, TRUE).
  LOCAL iterations IS 0.
  LOG "Secant coarse start," + TIME:SECONDS + "," + iterations + "," + (x_n - startTime) + "," + (x_n_minus_1 - startTime) + "," + (x_n_minus_2 - startTime) + "," + f_x_n["endHeight"] + "," + f_x_n_minus_1["endHeight"] + "," + f_x_n_minus_2["endHeight"] TO "0:RK4Search.csv".
  // Use the coarse calculations to get within 0.5 seconds and 1 meter of the ground
  UNTIL ((ABS(x_n - x_n_minus_1) <= 0.5) AND (ABS(f_x_n["endHeight"]) < 1)) {
    PRINT "Secant coarse - " + iterations + " iterations".
    SET x_n_minus_2 TO x_n_minus_1.
    SET f_x_n_minus_2 TO f_x_n_minus_1.
    SET x_n_minus_1 TO x_n.
    SET f_x_n_minus_1 TO f_x_n.
    SET x_n TO (x_n_minus_2*f_x_n_minus_1["endHeight"] - x_n_minus_1 * f_x_n_minus_2["endHeight"]) / (f_x_n_minus_1["endHeight"] - f_x_n_minus_2["endHeight"]).
    SET f_x_n TO simulateSuicideBurnRK(x_n, coarseTime, marginDistance, TRUE).
    SET iterations TO iterations + 1.
    LOG "Secant coarse," + TIME:SECONDS + "," + iterations + "," + (x_n - startTime) + "," + (x_n_minus_1 - startTime) + "," + (x_n_minus_2 - startTime) + "," + f_x_n["endHeight"] + "," + f_x_n_minus_1["endHeight"] + "," + f_x_n_minus_2["endHeight"] TO "0:RK4Search.csv".
  }
  SET iterations TO 0.
//  SET f_x_n TO simulateSuicideBurnRK(x_n, marginTime, marginDistance, TRUE).
//  LOG "Secant fine," + TIME:SECONDS + "," + iterations + "," + (x_n - startTime) + "," + (x_n_minus_1 - startTime) + "," + (x_n_minus_2 - startTime) + "," + f_x_n + "," + f_x_n_minus_1 + "," + f_x_n_minus_2 TO "0:RK4Search.csv".
//  // Use the precise calculations to figure things out
//  UNTIL ((ABS(x_n - x_n_minus_1) <= marginTime) AND (ABS(f_x_n["endHeight"]) < marginDistance)) {
//    PRINT "Secant fine - " + iterations + " iterations".
//    SET x_n_minus_2 TO x_n_minus_1.
//    SET f_x_n_minus_2 TO f_x_n_minus_1.
//    SET x_n_minus_1 TO x_n.
//    SET f_x_n_minus_1 TO f_x_n["endHeight"].
//    SET x_n TO (x_n_minus_2*f_x_n_minus_1 - x_n_minus_1 * f_x_n_minus_2) / (f_x_n_minus_1 - f_x_n_minus_2).
//    SET f_x_n TO simulateSuicideBurnRK(x_n, marginTime, marginDistance, TRUE).
//    SET iterations TO iterations + 1.
//    LOG "Secant fine," + TIME:SECONDS + "," + iterations + "," + (x_n - startTime) + "," + (x_n_minus_1 - startTime) + "," + (x_n_minus_2 - startTime) + "," + f_x_n + "," + f_x_n_minus_1 + "," + f_x_n_minus_2 TO "0:RK4Search.csv".
//  }
  LOG "Secant," + TIME:SECONDS + ",Solution," + (x_n - startTime) + ",value," + f_x_n["endHeight"] TO "0:RK4Search.csv".
  LOG "Secant," + TIME:SECONDS + ",Solution," + x_n + ",value," + f_x_n["endHeight"] TO "0:RK4Search.csv".
  LOG "Secant," + TIME:SECONDS + ",Duration," + (TIME:SECONDS - startTime) TO "0:RK4Search.csv".
  RETURN f_x_n.
}

// Find the time at which a suicide burn needs to start to end at the ground.
FUNCTION SBbisectionSearch {
  PARAMETER marginDistance IS 10.
  PARAMETER marginTime IS 0.02.
  IF marginDistance < 1 SET marginDistance TO 1.
  LOCAL coarseTime IS 1.0.
  LOCAL mediumTime IS coarseTime / 20.
  LOCAL startTime IS TIME:SECONDS.
  PRINT "Now calculating the bisection search".
  LOG "Type,Time,iterations,a,b,c,f_a,f_b,f_c,Thrust,Mass Flow,Radius,Current Accel,Current Position,Current Velocity,Normalized Accel,Burn Time,Delta V" TO "0:RK4Search.csv".
  LOCAL minTime IS startTime + 0.
  LOCAL maxTime IS startTime + (heightAboveGround() / ABS(VERTICALSPEED)).
  LOCAL f_a IS simulateSuicideBurnRK(minTime, coarseTime, marginDistance).
  LOCAL f_b IS simulateSuicideBurnRK(maxTime, coarseTime, marginDistance).

  LOCAL iterations IS 0.
  LOCAL a IS minTime.
  LOCAL b IS maxTime.
  LOCAL c IS (a + b)/2.
  LOCAL f_c IS simulateSuicideBurnRK(c, coarseTime, marginDistance).
  UNTIL iterations >= 1000 {
    PRINT "Bisection coarse - " + iterations + " iterations".
    LOG "Bisection coarse," + TIME:SECONDS + "," + iterations + "," + (a - startTime) + "," + (b - startTime) + "," + (c - startTime) + "," + f_a + "," + f_b + "," + f_c TO "0:RK4Search.csv".
    SET c TO (a + b)/2. // new midpoint
    SET f_c TO simulateSuicideBurnRK(c, coarseTime, marginDistance).
    IF ABS(b - a) / 2 < coarseTime {SET iterations TO 1000.}
    SET iterations TO iterations + 1.
    IF ((f_c < 0) = (f_a < 0)) {SET a TO c. SET f_a TO f_c.}
    ELSE {SET b TO c. SET f_b TO f_c.}
  }

  SET iterations TO 0.
  SET f_a TO simulateSuicideBurnRK(a, coarseTime/20, marginDistance).
  SET f_b TO simulateSuicideBurnRK(b, coarseTime/20, marginDistance).
  UNTIL iterations >= 1000 {
    PRINT "Bisection medium - " + iterations + " iterations".
    LOG "Bisection medium," + TIME:SECONDS + iterations + "," + (a - startTime) + "," + (b - startTime) + "," + (c - startTime) + "," + f_a + "," + f_b + "," + f_c TO "0:RK4Search.csv".
    SET c TO (a + b)/2. // new midpoint
    SET f_c TO simulateSuicideBurnRK(c, coarseTime/2, marginDistance).
    IF ABS(b - a) / 2 < coarseTime/20 {SET iterations TO 1000.}
    SET iterations TO iterations + 1.
    IF ((f_c < 0) = (f_a < 0)) {SET a TO c. SET f_a TO f_c.}
    ELSE {SET b TO c. SET f_b TO f_c.}
  }

  SET iterations TO 0.
  SET f_a TO simulateSuicideBurnRK(a, marginTime, marginDistance).
  SET f_b TO simulateSuicideBurnRK(b, marginTime, marginDistance).
  UNTIL iterations >= 1000 {
    PRINT "Bisection fine - " + iterations + " iterations".
    LOG "Bisection fine," + TIME:SECONDS + iterations + "," + (a - startTime) + "," + (b - startTime) + "," + (c - startTime) + "," + f_a + "," + f_b + "," + f_c TO "0:RK4Search.csv".
    SET c TO (a + b)/2. // new midpoint
    SET f_c TO simulateSuicideBurnRK(c, marginTime, marginDistance).
    IF ABS(b - a) / 2 < marginTime {SET iterations TO 1000.}
    SET iterations TO iterations + 1.
    IF ((f_c < 0) = (f_a < 0)) {SET a TO c. SET f_a TO f_c.}
    ELSE {SET b TO c. SET f_b TO f_c.}
  }
  LOG "Bisection," + TIME:SECONDS + ",Solution," + (a - startTime) + ",value," + f_a TO "0:RK4Search.csv".
  LOG "Bisection," + TIME:SECONDS + ",Solution," + a + ",value," + f_a TO "0:RK4Search.csv".
  LOG "Bisection," + TIME:SECONDS + ",Duration," + (TIME:SECONDS - startTime) TO "0:RK4Search.csv".
  RETURN simulateSuicideBurnRK(a, marginTime, marginDistance, TRUE).
}

// If we were to start a full-throttle surface-retrograde burn at "startTime",
// how far off the surface would we be when velocity hits 0?
//
// Uses a fourth-order Runge-Kutta integrator
//
// Calculations are done in the SOI-RAW reference frame, using the MKS system
// of units.  This requires conversion from KSP's meter-ton-second system.
FUNCTION simulateSuicideBurnRK {
  PARAMETER startTime.  // universal time
  PARAMETER timeStepCoarse IS 1.0.
  PARAMETER margin IS 0.0.
  PARAMETER returnDetails IS FALSE.
  PARAMETER timeStepFine IS 0.1.

  // Static parameters:
  LOCAL thrust IS SHIP:AVAILABLETHRUST * 1000.
  LOCAL massFlow IS shipInfo["CurrentStage"]["mDot"].
  LOCAL mu IS SHIP:BODY:MU.
  LOCAL radius IS SHIP:BODY:RADIUS + margin.
  LOCAL bod IS SHIP:BODY.

  // Timing parameters
  LOCAL timeStepOver2 IS timeStepCoarse / 2.
  LOCAL timeStepOver6 IS timeStepCoarse / 6.
  LOCAL timeStep IS timeStepCoarse.

  // Initial parameters
  LOCAL currentMass IS ship:mass * 1000.
  LOCAL startpos IS POSITIONAT(SHIP, startTime) - SHIP:BODY:POSITION.
  LOCAL currentPosition IS startpos.
  LOCAL currentVelocity IS VELOCITYAT(SHIP, startTime):SURFACE.
  LOCAL burnTime IS 0.

  // Statistic-gathering parameters
  LOCAL deltaV IS 0.

  // Calculate the acceleration vector under given conditions
  // fa(time, pos, vel) = g(pos) + F(vel)/(m0 - f*time)
  LOCAL FUNCTION fa {
    PARAMETER t.
    PARAMETER pos.
    PARAMETER vel.

    RETURN ((-mu / pos:SQRMAGNITUDE) * pos:NORMALIZED) + ((-thrust * vel:NORMALIZED)/(currentMass - massFlow * t)).
  }
// Simulation loop:
  LOCAL done IS false.
  LOCAL iterations IS 0.
  LOG "RK4," + TIME:SECONDS + "," + iterations + ",,,,,,," + thrust + "," + massFlow + "," + radius + "," + 0 + "," + currentPosition:MAG + "," + currentVelocity:MAG + "," + burnTime + "," + deltaV TO "0:RK4Search.csv".

  UNTIL done {
    SET iterations TO iterations + 1.
    LOCAL k1x IS currentVelocity.
    LOCAL k1v IS fa(burnTime, currentPosition, currentVelocity).
    LOCAL k2x IS currentVelocity + timeStepOver2 * k1v.
    LOCAL k2v IS fa(burnTime + timeStepOver2, currentPosition + timeStepOver2 * k1x, k2x).
    LOCAL k3x IS currentVelocity + timeStepOver2 * k2v.
    LOCAL k3v IS fa(burnTime + timeStepOver2, currentPosition + timeStepOver2 * k2x, k3x).
    LOCAL k4x IS currentVelocity + timeStep * k3v.
    LOCAL k4v IS fa(burnTime + timeStep, currentPosition + timeStep * k3x, k4x).
    LOCAL accel IS timeStepOver6*(k1v + 2*k2v + 2*k3v + k4v).

    SET currentPosition TO currentPosition + timeStepOver6*(k1x + 2*k2x + 2*k3x + k4x).
    SET currentVelocity TO currentVelocity + accel.
    SET deltaV TO deltaV + accel:mag.
    SET burnTime TO burnTime + timeStep.

    LOG "RK4," + TIME:SECONDS + "," + iterations + ",,,,,,," + thrust + "," + massFlow + "," + radius + "," + accel:MAG + "," + currentPosition:MAG + "," + currentVelocity:MAG + "," + (accel:MAG / timeStep) + "," + burnTime + "," + deltaV TO "0:RK4Search.csv".

    // Check for ending conditions
    IF (currentVelocity:MAG < accel:MAG) {
      // If our current velocity is less than one simulation tick's
      // acceleration, and we are already using the fine timestep,
      // we're close enough to stopped.
      IF ((timeStep = timeStepCoarse) AND (timeStepCoarse <> 0.02)) {
        SET timeStep TO timeStepFine.
        SET timeStepOver2 TO timeStepFine / 2.
        SET timeStepOver6 TO timeStepFine / 6.
      } ELSE SET done TO true.
    }
  }
  LOCAL endpos IS SHIP:BODY:GEOPOSITIONOF(currentPosition + ship:body:position).
  LOCAL endheight IS currentPosition:MAG - endpos:TERRAINHEIGHT - SHIP:BODY:RADIUS.
  IF NOT returnDetails RETURN endheight.
  RETURN LEXICON("endHeight", endHeight,
                 "BurnTime", burnTime,
                 "deltaV", deltaV,
                 "startTime", startTime,
                 "iterations", iterations).
}
