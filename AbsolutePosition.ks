@LAZYGLOBAL OFF.
CLEARSCREEN.

FUNCTION absolutePosition {
  PARAMETER thing.
  PARAMETER timeStamp IS TIME:SECONDS.

  LOCAL originalThing IS thing.
  LOCAL removals IS 0.
  LOCAL finalPosition IS V(0, 0, 0).
  UNTIL NOT thing:HASBODY {
    SET finalPosition TO finalPosition + POSITIONAT(thing, timeStamp).
    SET thing TO thing:BODY.
    SET removals TO removals + 1.
  }
  SET finalPosition TO finalPosition - BODY("Sun"):POSITION.
  IF removals = 2 RETURN finalPosition - originalThing:BODY:POSITION.
  IF removals = 3 {PRINT "3 Removals". RETURN finalPosition - originalThing:BODY:BODY:POSITION.}
  RETURN finalPosition.
}

FUNCTION absoluteVelocity {
  PARAMETER thing.
  PARAMETER timeStamp IS TIME:SECONDS.

  LOCAL removals IS 0.
  LOCAL finalVelocity IS V(0, 0, 0).
  UNTIL NOT thing:HASBODY {
    SET finalVelocity TO finalVelocity + VELOCITYAT(thing, timeStamp):ORBIT.
    SET thing TO thing:BODY.
  }
  RETURN finalVelocity.
}

IF NOT HASTARGET PRINT "Select a target".
UNTIL HASTARGET {WAIT 0.0.}

LOCAL vectorCount IS 5.
LOCAL oldName IS "".
LOCAL thingPeriod IS TARGET:ORBIT:PERIOD / vectorCount.

LOCAL vecDraws IS LIST().
FOR number IN RANGE(0, vectorCount, 1) {
  vecDraws:ADD(VECDRAW(V(0, 0, 0), V(0, 0, 0),   YELLOW, "", 1, TRUE)).
}
FOR number IN RANGE(0, vectorCount, 1) {
  vecDraws:ADD(VECDRAW(V(0, 0, 0), V(0, 0, 0),   BLUE, "", 1, TRUE)).
}

AG1 OFF.
UNTIL AG1 OR NOT HASTARGET {
  IF TARGET:NAME <> oldName {
    SET oldName TO TARGET:NAME.
    CLEARSCREEN.
    PRINT "AG1 to end script".
    PRINT "AG2 to change how period is defined".
    PRINT "Showing future positions of " + TARGET:NAME.
    FOR number IN RANGE(0, vectorCount, 1) {
      PRINT TARGET:NAME + " will be moving at " + distanceToString(absoluteVelocity(TARGET, TIME:SECONDS + number * thingPeriod):MAG, 3) + "/s " + timeToString(number * thingPeriod) + " from now".
      PRINT "".
    }
  }
  SET thingPeriod TO TARGET:ORBIT:PERIOD / vectorCount.
  IF AG2 AND TARGET:HASBODY {IF TARGET:BODY:NAME <> "Sun" SET thingPeriod TO TARGET:BODY:ORBIT:PERIOD / vectorCount.}
  IF AG3 AND TARGET:HASBODY {IF TARGET:BODY:HASBODY {IF TARGET:BODY:BODY:NAME <> "Sun" SET thingPeriod TO TARGET:BODY:BODY:ORBIT:PERIOD / vectorCount.}}
  FOR number IN RANGE(0, vectorCount, 1) {
    SET vecDraws[number]:START TO BODY("Sun"):POSITION.
    SET vecDraws[number]:LABEL TO TARGET:NAME + " Absolute Position " + number.
    SET vecDraws[number]:VEC TO absolutePosition(TARGET, TIME:SECONDS + number * thingPeriod).

    SET vecDraws[vectorCount + number]:START TO absolutePosition(TARGET, TIME:SECONDS + number * thingPeriod) + BODY("Sun"):POSITION.
    SET vecDraws[vectorCount + number]:LABEL TO TARGET:NAME + " Absolute Velocity " + number + " - " + distanceToString(absoluteVelocity(TARGET, TIME:SECONDS + number * thingPeriod):MAG, 3) + "/s".
    SET vecDraws[vectorCount + number]:VEC TO absoluteVelocity(TARGET, TIME:SECONDS + number * thingPeriod):NORMALIZED * absolutePosition(TARGET, TIME:SECONDS + number * thingPeriod):MAG / 8.
  }
  WAIT 0.0.
}
