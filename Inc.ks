@LAZYGLOBAL OFF.

PARAMETER desiredRelativeInclination IS 0.
// Chosen Node can be "Highest" (default), "nearest", "farthest", "AN" or "DN"
PARAMETER chosenNode IS "Highest".
PARAMETER useTargetPlane IS HASTARGET.
PARAMETER visualize IS FALSE.

// Determine if SHIP will be north of the given plane
FUNCTION isNorthOfPlane {
  PARAMETER timeOffset IS 0.
  PARAMETER useTarget IS HASTARGET.
  RETURN distanceFromPlane(timeOffset, useTarget) > 0.
}

LOCAL errorValue IS -1234.
LOCAL changeToNorth IS errorValue.
LOCAL changeToSouth IS errorValue.
LOCAL effectivePeriod IS 1.
// If this is not a final trajectory, use the time until the trajectory changes,
//   be that an SOI change or a maneuver.
IF (SHIP:ORBIT:TRANSITION <> "Final") {
  SET effectivePeriod TO ETA:TRANSITION - 10.0.
} ELSE {
  SET effectivePeriod TO SHIP:ORBIT:PERIOD.
}
LOCAL startTimeDelta IS effectivePeriod / 1000. // given the default period, this is 10 minutes
LOCAL timeDelta IS startTimeDelta.
LOCAL currentNorth IS isNorthOfPlane(0).
LOCAL nextNorth IS isNorthOfPlane(timeDelta).

LOCAL startTimeDeltaLoop IS startTimeDelta.
LOCAL loopDone IS FALSE.
LOCAL iterations IS 0.
LOCAL iterationsMax IS 1000.
LOCAL ANExists IS FALSE.
LOCAL DNExists IS TRUE.

LOCAL logFileName IS "0:incChange.csv".
IF visualize AND connectionToKSC() {
  CLEARSCREEN.
  IF EXISTS(logFileName) DELETEPATH(logFileName).
  LOG "Target's Orbit Normal Vector," + ROUNDV(VCRS(POSITIONAT(TARGET, TIME:SECONDS) - TARGET:BODY:POSITION, VELOCITYAT(TARGET, TIME:SECONDS):ORBIT):NORMALIZED, 11) TO logFileName.
  LOG "Body Angular Velocity Vector," + ROUNDV(SHIP:BODY:ANGULARVEL:NORMALIZED, 11) TO logFileName.
  LOG "Body Position Vector," + ROUNDV(-SHIP:BODY:POSITION, 11) TO logFileName.
  IF (SHIP:ORBIT:TRANSITION = "Escape") LOG "Transition," + SHIP:ORBIT:TRANSITION + ",Time to Transition (s)," + ETA:TRANSITION TO logFileName.
  ELSE LOG "Transition," + SHIP:ORBIT:TRANSITION TO logFileName.
  LOG "Loop,TimeGuess,Radial Distance,Current North,Next North,Current Distance,Next Distance,Time Delta,Iterations" TO logFileName.
  LOG "Test,0," + SHIP:BODY:DISTANCE + "," +
  (distanceFromPlane(0, useTargetPlane) > 0) + "," + (distanceFromPlane(startTimeDelta, useTargetPlane) > 0) + "," +
  distanceFromPlane(0, useTargetPlane) + "," + distanceFromPlane(startTimeDelta, useTargetPlane) + "," +
  startTimeDelta + ",0" TO logFileName.
}

SET iterations TO 0.
FROM {LOCAL timeGuess IS 0.}
  UNTIL timeGuess > effectivePeriod OR (changeToNorth <> errorValue AND changeToSouth <> errorValue) OR (iterations > iterationsMax)
  STEP {SET timeGuess TO timeGuess + timeDelta.}
  DO {
    SET currentNorth TO isNorthOfPlane(timeGuess).
    SET nextNorth TO isNorthOfPlane(timeGuess + timeDelta).
    IF currentNorth <> nextNorth {
      IF currentNorth AND NOT nextNorth {
        SET changeToSouth TO timeGuess.
        IF visualize AND connectionToKSC() LOG "Changing to South" TO logFileName.
      } ELSE {
        SET changeToNorth TO timeGuess.
        IF visualize AND connectionToKSC() LOG "Changing to North" TO logFileName.
      }
    }
    SET iterations TO iterations + 1.
    IF visualize AND connectionToKSC() LOG "Main," + timeGuess + "," + (POSITIONAT(SHIP, TIME:SECONDS + timeGuess) - SHIP:BODY:POSITION):MAG + "," + currentNorth + "," + nextNorth + "," + distanceFromPlane(timeGuess, useTargetPlane) + "," + distanceFromPlane(timeGuess + timeDelta, useTargetPlane) + "," + timeDelta + "," + iterations TO logFileName.
}

SET ANExists TO changeToNorth <> errorValue.
SET DNExists TO changeToSouth <> errorValue.

IF ANExists {
  SET timeDelta TO startTimeDelta.
  SET startTimeDeltaLoop TO startTimeDelta.
  SET iterations TO 0.
  UNTIL ((timeDelta < startTimeDelta / 2^15) AND (timeDelta < 0.01)) OR (iterations > iterationsMax) {
    SET startTimeDeltaLoop TO timeDelta.
    SET timeDelta TO timeDelta / 2.
    SET loopDone TO FALSE.
    FROM {LOCAL timeGuess IS changeToNorth.}
      UNTIL ((timeGuess >= changeToNorth + startTimeDeltaLoop) OR loopDone)
      STEP {SET timeGuess TO timeGuess + timeDelta.}
      DO {
        SET currentNorth TO isNorthOfPlane(timeGuess).
        SET nextNorth TO isNorthOfPlane(timeGuess + timeDelta).
        IF currentNorth <> nextNorth {
          SET loopDone TO TRUE.
          SET changeToNorth TO timeGuess.
          IF visualize AND connectionToKSC() LOG "Changing to North" TO logFileName.
        }
        SET iterations TO iterations + 1.
        IF visualize AND connectionToKSC() LOG "North," + timeGuess + "," + (POSITIONAT(SHIP, TIME:SECONDS + timeGuess) - SHIP:BODY:POSITION):MAG + "," + currentNorth + "," + nextNorth + "," + distanceFromPlane(timeGuess, useTargetPlane) + "," + distanceFromPlane(timeGuess + timeDelta, useTargetPlane) + "," + timeDelta + "," + iterations TO logFileName.
    }
  }
}

IF DNExists {
  SET timeDelta TO startTimeDelta.
  SET startTimeDeltaLoop TO startTimeDelta.
  SET iterations TO 0.
  UNTIL ((timeDelta < startTimeDelta / 2^15) AND (timeDelta < 0.01)) OR (iterations > iterationsMax) {
    SET startTimeDeltaLoop TO timeDelta.
    SET timeDelta TO timeDelta / 2.
    SET loopDone TO FALSE.
    FROM {LOCAL timeGuess IS changeToSouth.}
      UNTIL (timeGuess >= changeToSouth + startTimeDeltaLoop) OR loopDone
      STEP {SET timeGuess TO timeGuess + timeDelta.}
      DO {
        SET currentNorth TO isNorthOfPlane(timeGuess).
        SET nextNorth TO isNorthOfPlane(timeGuess + timeDelta).
        IF currentNorth <> nextNorth {
          SET loopDone TO TRUE.
          SET changeToSouth TO timeGuess.
          IF visualize AND connectionToKSC() LOG "Changing to South" TO logFileName.
        }
        SET iterations TO iterations + 1.
        IF visualize AND connectionToKSC() LOG "South," + timeGuess + "," + (POSITIONAT(SHIP, TIME:SECONDS + timeGuess) - SHIP:BODY:POSITION):MAG + "," + currentNorth + "," + nextNorth + "," + distanceFromPlane(timeGuess, useTargetPlane) + "," + distanceFromPlane(timeGuess + timeDelta, useTargetPlane) + "," + timeDelta + "," + iterations TO logFileName.
    }
  }
}

// Determine which node to use
LOCAL chosenTime IS changeToNorth.
LOCAL usedNode IS "None".
IF ANExists AND DNExists {
  IF (chosenNode = "AN") OR (chosenNode = "asc") {
    SET chosenTime TO changeToNorth.
    SET usedNode TO "ascending".
  }
  IF (chosenNode = "DN") OR (chosenNode = "desc") {
    SET chosenTime TO changeToSouth.
    SET usedNode TO "descending".
  }
  IF chosenNode = "Nearest" {
    SET chosenTime TO MIN(changeToNorth, changeToSouth).
    SET usedNode TO "nearest".
  }
  IF chosenNode = "Farthest" {
    SET chosenTime TO MAX(changeToNorth, changeToSouth).
    SET usedNode TO "farthest".
  }
  IF chosenNode = "Highest" {
    LOCAL positionAtNorth IS (POSITIONAT(SHIP, TIME:SECONDS + changeToNorth) - SHIP:BODY:POSITION):MAG.
    LOCAL positionAtSouth IS (POSITIONAT(SHIP, TIME:SECONDS + changeToSouth) - SHIP:BODY:POSITION):MAG.
    IF visualize {
      PRINT "Altitude at North: " + distanceToString(positionAtNorth, 4).
      PRINT "Altitude at South: " + distanceToString(positionAtSouth, 4).
    }
    IF positionAtNorth > positionAtSouth {
      IF visualize PRINT "Choosing North".
      SET chosenTime TO changeToNorth.
      SET usedNode TO "highest - north".
    } ELSE {
      IF visualize PRINT "Choosing South".
      SET chosenTime TO changeToSouth.
      SET usedNode TO "highest - south".
    }
  }
} ELSE IF ANExists AND NOT DNExists {SET chosenTime TO changeToNorth. SET usedNode TO "north".}
ELSE IF NOT ANExists AND DNExists {SET chosenTime TO changeToSouth. SET usedNode TO "south".}

LOCAL vectorToNode IS POSITIONAT(SHIP, TIME:SECONDS + chosenTime) - SHIP:BODY:POSITION.
LOCAL nodeVelocity IS VELOCITYAT(SHIP, TIME:SECONDS + chosenTime):ORBIT.
LOCAL directionsAtNode IS getOrbitDirectionsAt(chosenTime, SHIP).
LOCAL iDelta IS angleFromPlane(useTargetPlane) - desiredRelativeInclination.
IF useTargetPlane { IF ((TARGET:ORBIT:INCLINATION > 90.0) <> (SHIP:ORBIT:INCLINATION > 90.0)) {SET iDelta TO 0-iDelta. PRINT "Reversing inclination change".}}
IF chosenTime = changeToSouth {SET iDelta TO 0 - iDelta. PRINT "DN - reversing inclination change".}
LOCAL desiredVelocity IS nodeVelocity * ANGLEAXIS(iDelta, vectorToNode).
LOCAL deltaV IS desiredVelocity - nodeVelocity.
ADD NODE(TIME:SECONDS + chosenTime, deltaV * directionsAtNode["radial"], deltaV * directionsAtNode["normal"], deltaV * directionsAtNode["prograde"]).
IF visualize {
  PRINT "Current Relative Inclination: " + ROUND(angleFromPlane(useTargetPlane), 4) + " degrees".
  PRINT "Desired Relative Inclination: " + ROUND(desiredRelativeInclination, 4) + " degrees".
  PRINT "Inc Change Required: " + ROUND(iDelta, 4) + " degrees".
  PRINT "        radial    normal    prograde    mag".
  PRINT "Node: " + ROUND(nodeVelocity * directionsAtNode["radial"]):TOSTRING:PADLEFT(8) + ROUND(nodeVelocity * directionsAtNode["normal"]):TOSTRING:PADLEFT(10) + ROUND(nodeVelocity * directionsAtNode["prograde"]):TOSTRING:PADLEFT(12) + ROUND(nodeVelocity:MAG):TOSTRING:PADLEFT(7).
  PRINT "Want: " + ROUND(desiredVelocity * directionsAtNode["radial"]):TOSTRING:PADLEFT(8) + ROUND(desiredVelocity * directionsAtNode["normal"]):TOSTRING:PADLEFT(10) + ROUND(desiredVelocity * directionsAtNode["prograde"]):TOSTRING:PADLEFT(12) + ROUND(desiredVelocity:MAG):TOSTRING:PADLEFT(7).
  PRINT "Delt: " + ROUND(deltaV * directionsAtNode["radial"]):TOSTRING:PADLEFT(8) + ROUND(deltaV * directionsAtNode["normal"]):TOSTRING:PADLEFT(10) + ROUND(deltaV * directionsAtNode["prograde"]):TOSTRING:PADLEFT(12) + ROUND(deltaV:MAG):TOSTRING:PADLEFT(7).
  WAIT 10.
}

IF ANExists OR DNExists {
  SET loopMessage TO "Node created at " + usedNode + " node".
} ELSE SET loopMessage TO "Neither node exists!".
