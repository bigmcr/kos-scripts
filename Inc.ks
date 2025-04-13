@LAZYGLOBAL OFF.

PARAMETER desiredRelativeInclination IS 0.
// Chosen Node can be "Highest" (default), "nearest", "farthest", "Lowest", "AN" or "DN"
PARAMETER chosenNode IS "Highest".
PARAMETER useTargetPlane IS HASTARGET.
PARAMETER visualize IS TRUE.

IF visualize CLEARSCREEN.

LOCAL bodyPosition IS SHIP:POSITION - SHIP:BODY:POSITION.
LOCAL targetNormal IS getNormalVector(CHOOSE TARGET IF useTargetPlane ELSE "Equator").
LOCAL normalVector IS getNormalVector(SHIP).
LOCAL relativeLANVector IS VCRS(normalVector, targetNormal).
LOCAL relativeInclination IS VANG(normalVector, targetNormal).
LOCAL iDelta IS relativeInclination - desiredRelativeInclination.

LOCAL angleDelta IS LEXICON().
angleDelta:ADD("AN", VANGSigned(bodyPosition:NORMALIZED, relativeLANVector, normalVector)).
angleDelta:ADD("DN", normalizeAngle360(angleDelta["AN"] + 180)).

IF SHIP:ORBIT:TRANSITION <> "Final" {
  angleDelta:ADD("Transition", VANGSigned(bodyPosition, POSITIONAT(SHIP, TIME:SECONDS + ETA:TRANSITION - 10) - SHIP:BODY:POSITION, normalVector)).
} ELSE angleDelta:ADD("Transition", 360).

LOCAL ANExists IS (angleDelta["AN"] < angleDelta["Transition"]).
LOCAL DNExists IS (angleDelta["DN"] < angleDelta["Transition"]).

// Now convert the determined true anomalies to UT times.
LOCAL UTTime IS LEXICON().
IF ANExists UTTime:ADD("AN", TIME:SECONDS + trueAnomalyDeltaToTime(SHIP:ORBIT, SHIP:ORBIT:TRUEANOMALY, SHIP:ORBIT:TRUEANOMALY + angleDelta["AN"])).
IF DNExists UTTime:ADD("DN", TIME:SECONDS + trueAnomalyDeltaToTime(SHIP:ORBIT, SHIP:ORBIT:TRUEANOMALY, SHIP:ORBIT:TRUEANOMALY + angleDelta["DN"])).

LOCAL rValues IS LEXICON().
IF ANExists rValues:ADD("AN", (POSITIONAT(SHIP, UTTime["AN"]) - SHIP:BODY:POSITION):MAG).
IF DNExists rValues:ADD("DN", (POSITIONAT(SHIP, UTTime["DN"]) - SHIP:BODY:POSITION):MAG).

LOCAL nodeVelocity IS LEXICON().
IF ANExists nodeVelocity:ADD("AN", VELOCITYAT(SHIP, UTTime["AN"]):ORBIT).
IF DNExists nodeVelocity:ADD("DN", VELOCITYAT(SHIP, UTTime["DN"]):ORBIT).

LOCAL directionsAtNode IS LEXICON().
IF ANExists directionsAtNode:ADD("AN", getOrbitDirectionsAt(UTTime["AN"], SHIP)).
IF DNExists directionsAtNode:ADD("DN", getOrbitDirectionsAt(UTTime["DN"], SHIP)).

LOCAL deltaV IS LEXICON().
IF ANExists deltaV:ADD("AN", (nodeVelocity["AN"] * ANGLEAXIS(iDelta, relativeLANVector)) - nodeVelocity["AN"]).
IF DNExists deltaV:ADD("DN", (nodeVelocity["DN"] * ANGLEAXIS(iDelta, relativeLANVector)) - nodeVelocity["DN"]).

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
    SET usedNode TO (CHOOSE "Ascending" IF (UTTime["AN"] < UTTime["DN"]) ELSE "Descending").
  }
  IF chosenNode = "Farthest" {
    SET usedNode TO (CHOOSE "Ascending" IF (UTTime["AN"] > UTTime["DN"]) ELSE "Descending").
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

IF usedNode:CONTAINS("Ascending") SET usedNode TO "AN".
IF usedNode:CONTAINS("Descending") SET usedNode TO "DN".

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

  LOCAL UTTimeDigits IS 9.
  IF ANExists SET UTTimeDigits TO MAX(UTTimeDigits, timeToString(UTTime["AN"] - TIME:SECONDS, 0):LENGTH + 2).
  IF DNExists SET UTTimeDigits TO MAX(UTTimeDigits, timeToString(UTTime["DN"] - TIME:SECONDS, 0):LENGTH + 2).
  PRINT "Node       True Anomaly     Altitude  Exists  Chosen" + "Delay":PADLEFT(UTTimeDigits) + "  Delta V".
  PRINT "Ascending  " + (ROUND(angleDelta["AN"], 3) + " deg"):PADLEFT(12) +
                        (CHOOSE distanceToString(rValues["AN"], 2) IF ANExists ELSE "N/A"):PADLEFT(13) +
                        (CHOOSE "Yes" IF ANExists ELSE "No"):PADLEFT(8) +
                        (CHOOSE "Yes" IF usedNode = "AN" ELSE "No"):PADLEFT(8) +
                        (CHOOSE timeToString(UTTime["AN"] - TIME:SECONDS, 0) IF ANExists ELSE "N/A"):PADLEFT(UTTimeDigits) +
                        (CHOOSE distanceToString(deltaV["AN"]:MAG) + "/s" IF ANExists ELSE "N/A"):PADLEFT(9).
  PRINT "Descending " + (ROUND(angleDelta["DN"], 3) + " deg"):PADLEFT(12) +
                        (CHOOSE distanceToString(rValues["DN"], 2) IF DNExists ELSE "N/A"):PADLEFT(13) +
                        (CHOOSE "Yes" IF DNExists ELSE "No"):PADLEFT(8) +
                        (CHOOSE "Yes" IF usedNode = "DN" ELSE "No"):PADLEFT(8) +
                        (CHOOSE timeToString(UTTime["DN"] - TIME:SECONDS, 0) IF DNExists ELSE "N/A"):PADLEFT(UTTimeDigits) +
                        (CHOOSE distanceToString(deltaV["DN"]:MAG) + "/s" IF DNExists ELSE "N/A"):PADLEFT(9).
  IF angleDelta["Transition"] <> 360 PRINT "Transition " + (ROUND(angleDelta["Transition"], 3) + " deg"):PADLEFT(12).
  PRINT " ".
  PRINT "Relative Inclination: " + ROUND(relativeInclination, 3) + " degrees".
  PRINT "Inclination Delta is " + ROUND(iDelta, 3) + " degrees".
  PRINT " ".

  IF usedNode <> "AN" AND usedNode <> "DN" {
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

  IF tempChar = TERMINAL:INPUT:BACKSPACE SET usedNode TO "None".
}

IF usedNode = "AN" OR usedNode = "DN" {
  ADD NODE(UTTime[usedNode], deltaV[usedNode] * directionsAtNode[usedNode]["radial"], deltaV[usedNode] * directionsAtNode[usedNode]["normal"], deltaV[usedNode] * directionsAtNode[usedNode]["prograde"]).
}

IF ANExists OR DNExists {
  IF usedNode <> "None" SET loopMessage TO "Node created at " + usedNode.
  ELSE SET loopMessage TO "No inclination change node created".
} ELSE SET loopMessage TO "Neither node exists!".
