@LAZYGLOBAL OFF.

PARAMETER desiredRelativeInclination IS 0.
// Chosen Node can be "Highest" (default), "nearest", "farthest", "AN" or "DN"
PARAMETER chosenNode IS "Highest".
PARAMETER useTargetPlane IS HASTARGET.
PARAMETER visualize IS TRUE.

LOCAL bodyPosition IS SHIP:POSITION - SHIP:BODY:POSITION.
LOCAL targetNormal IS getNormalVector(CHOOSE TARGET IF useTargetPlane ELSE "Equator").
LOCAL normalVector IS getNormalVector(SHIP).
LOCAL relativeLANVector IS VCRS(normalVector, targetNormal).
LOCAL relativeInclination IS VANG(normalVector, targetNormal).

LOCAL angleDelta IS LEXICON().
angleDelta:ADD("AN", VANGSigned(bodyPosition:NORMALIZED, relativeLANVector, -SHIP:BODY:ANGULARVEL:NORMALIZED)).
angleDelta:ADD("DN", normalizeAngle360(angleDelta["AN"] + 180)).

LOCAL ANExists IS TRUE.
LOCAL DNExists IS TRUE.

IF SHIP:ORBIT:TRANSITION <> "Final" {
  angleDelta:ADD("Transition", VANGSigned(bodyPosition, POSITIONAT(SHIP, TIME:SECONDS + ETA:TRANSITION - 10) - SHIP:BODY:POSITION, -SHIP:BODY:ANGULARVEL:NORMALIZED)).
} ELSE angleDelta:ADD("Transition", 360).

SET ANExists TO (angleDelta["AN"] < angleDelta["Transition"]).
SET DNExists TO (angleDelta["DN"] < angleDelta["Transition"]).

// Now convert the determined mean anomalies to delay times.
LOCAL delay IS LEXICON().
IF ANExists delay:ADD("AN", trueAnomalyDeltaToTime(SHIP:ORBIT, SHIP:ORBIT:TRUEANOMALY + angleDelta["AN"])).
IF DNExists delay:ADD("DN", trueAnomalyDeltaToTime(SHIP:ORBIT, SHIP:ORBIT:TRUEANOMALY + angleDelta["DN"])).

LOCAL rValues IS LEXICON().
IF ANExists rValues:ADD("AN", (POSITIONAT(SHIP, TIME:SECONDS + delay["AN"]) - SHIP:BODY:POSITION):MAG).
IF DNExists rValues:ADD("DN", (POSITIONAT(SHIP, TIME:SECONDS + delay["DN"]) - SHIP:BODY:POSITION):MAG).

// Determine which node to use
LOCAL usedNode IS "None".
IF ANExists AND DNExists {
  IF (chosenNode = "AN") OR (chosenNode = "asc") OR (chosenNode = "ascending") {
    SET usedNode TO "Ascending".
  }
  IF (chosenNode = "DN") OR (chosenNode = "desc") OR (chosenNode = "descending")  {
    SET usedNode TO "Descending".
  }
  IF chosenNode = "Nearest" {
    SET usedNode TO (CHOOSE "Ascending" IF (delay["AN"] < delay["DN"]) ELSE "Descending").
  }
  IF chosenNode = "Farthest" {
    SET usedNode TO (CHOOSE "Ascending" IF (delay["AN"] > delay["DN"]) ELSE "Descending").
  }
  IF chosenNode = "Highest" {
    IF rValues["AN"] > rValues["DN"] {
      SET usedNode TO "Highest - Ascending".
    } ELSE {
      SET usedNode TO "Highest - Descending".
    }
  }
  IF chosenNode = "Lowest" {
    IF rValues["AN"] <= rValues["DN"] {
      SET usedNode TO "Lowest - Ascending".
    } ELSE {
      SET usedNode TO "Lowest - Descending".
    }
  }
} ELSE IF ANExists AND NOT DNExists {SET usedNode TO "Ascending".}
ELSE IF NOT ANExists AND DNExists {SET usedNode TO "Descending".}

LOCAL chosenTime IS "None".
IF usedNode:CONTAINS("Ascending") SET chosenTime TO delay["AN"].
IF usedNode:CONTAINS("Descending") SET chosenTime TO delay["DN"].

LOCAL iDelta IS relativeInclination - desiredRelativeInclination.

IF visualize {
  LOCAL vecDraws IS LEXICON().
  LOCAL RADIUS IS SHIP:BODY:RADIUS * 3.
  LOCAL localBody IS SHIP:BODY.

  vecDraws:ADD("TargetNormal", VECDRAW(V(0,0,0), V(0,0,0),  YELLOW, "Target Normal"  , 1.0, TRUE, 0.2, FALSE)).
  SET vecDraws["TargetNormal"]:START TO localBody:POSITION.
  SET vecDraws["TargetNormal"]:VEC TO radius * targetNormal.

  vecDraws:ADD("ShipNormal", VECDRAW(V(0,0,0), V(0,0,0),  RED, "Ship Normal"  , 1.0, TRUE, 0.2, FALSE)).
  SET vecDraws["ShipNormal"]:START TO localBody:POSITION.
  SET vecDraws["ShipNormal"]:VEC TO radius * normalVector.

  vecDraws:ADD("LAN", VECDRAW(V(0,0,0), V(0,0,0),  GREEN, "LAN"  , 1.0, TRUE, 0.2, FALSE)).
  SET vecDraws["LAN"]:START TO localBody:POSITION.
  SET vecDraws["LAN"]:VEC TO radius * relativeLANVector:NORMALIZED.

  vecDraws:ADD("bodyToShip", VECDRAW(V(0,0,0), V(0,0,0),  WHITE, "Body to SHIP"  , 1.0, TRUE, 0.2, TRUE)).
  SET vecDraws["bodyToShip"]:START TO localBody:POSITION.
  SET vecDraws["bodyToShip"]:VEC TO bodyPosition.

  vecDraws:ADD("bodyToNode", VECDRAW(V(0,0,0), V(0,0,0),  WHITE, "Body to AN"  , 1.0, TRUE, 0.2, TRUE)).
  SET vecDraws["bodyToNode"]:START TO localBody:POSITION.
  LOCAL bodyToNodeLength IS bodyPosition:MAG.
  IF ANExists SET bodyToNodeLength TO rValues["AN"].
  SET vecDraws["bodyToNode"]:VEC TO (bodyPosition*ANGLEAXIS(angleDelta["AN"], normalVector)):NORMALIZED * bodyToNodeLength.

  CLEARSCREEN.

  LOCAL delayDigits IS 9.
  IF ANExists SET delayDigits TO MAX(delayDigits, timeToString(delay["AN"], 0):LENGTH + 2).
  IF DNExists SET delayDigits TO MAX(delayDigits, timeToString(delay["DN"], 0):LENGTH + 2).
  PRINT "Node       True Anomaly     Altitude  Exists  Chosen" + "Delay":PADLEFT(delayDigits).
  PRINT "Ascending  " + (ROUND(angleDelta["AN"], 3) + " deg"):PADLEFT(12) +
                        (CHOOSE distanceToString(rValues["AN"], 4) IF ANExists ELSE "N/A"):PADLEFT(13) +
                        (CHOOSE "Yes" IF ANExists ELSE "No"):PADLEFT(8) +
                        (CHOOSE "Yes" IF usedNode:CONTAINS("Ascending") ELSE "No"):PADLEFT(8) +
                        (CHOOSE timeToString(delay["AN"], 0) IF ANExists ELSE "N/A"):PADLEFT(delayDigits).
  PRINT "Descending " + (ROUND(angleDelta["DN"], 3) + " deg"):PADLEFT(12) +
                        (CHOOSE distanceToString(rValues["DN"], 4) IF DNExists ELSE "N/A"):PADLEFT(13) +
                        (CHOOSE "Yes" IF DNExists ELSE "No"):PADLEFT(8) +
                        (CHOOSE "Yes" IF usedNode:CONTAINS("Descending") ELSE "No"):PADLEFT(8) +
                        (CHOOSE timeToString(delay["DN"], 0) IF DNExists ELSE "N/A"):PADLEFT(delayDigits).
  IF angleDelta["Transition"] <> 360 PRINT "Transition " + (ROUND(angleDelta["Transition"], 3) + " deg"):PADLEFT(12).
  PRINT " ".
  PRINT "Relative Inclination: " + ROUND(relativeInclination, 3) + " degrees".
  PRINT "Inclination Delta is " + ROUND(iDelta, 3) + " degrees".
  PRINT " ".

  IF chosenTime = "None" {
    PRINT "No time has been chosen!".
    PRINT "No node will be used.".
  }

  PRINT "Press ENTER to create the indicated maneuver node.".
  PRINT "Press BACKSPACE to exit without making a maneuver node.".
  LOCAL tempChar IS "".
  UNTIL (tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE) {
    IF TERMINAL:INPUT:HASCHAR SET tempChar TO TERMINAL:INPUT:GETCHAR().
    WAIT 0.
  }

  IF tempChar = TERMINAL:INPUT:BACKSPACE SET chosenTime TO "None".
}

IF chosenTime <> "None" {
  LOCAL nodeVelocity IS VELOCITYAT(SHIP, TIME:SECONDS + chosenTime):ORBIT.
  LOCAL directionsAtNode IS getOrbitDirectionsAt(chosenTime, SHIP).
  LOCAL deltaV IS (nodeVelocity * ANGLEAXIS(iDelta, relativeLANVector)) - nodeVelocity.
  ADD NODE(TIME:SECONDS + chosenTime, deltaV * directionsAtNode["radial"], deltaV * directionsAtNode["normal"], deltaV * directionsAtNode["prograde"]).
}

IF ANExists OR DNExists {
  IF chosenTime <> "None" SET loopMessage TO "Node created at " + usedNode.
  ELSE SET loopMessage TO "No inclination change node created".
} ELSE SET loopMessage TO "Neither node exists!".
