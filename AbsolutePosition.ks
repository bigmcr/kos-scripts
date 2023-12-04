@LAZYGLOBAL OFF.
CLEARSCREEN.

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

LOCAL logFileName2 IS "0:absolutePositionAndVelocityData.csv".
IF EXISTS(logFileName2) DELETEPATH(logFileName2).

PRINT "Logging all position and velocity data".
LOG "Time Offset (s),Universal Time (s),R1 X,R1 Y,R1 Z,R1 Mag,R2 X,R2 Y,R2 Z,R2 Mag,R3 X,R3 Y,R3 Z,R3 Mag,V1 X,V1 Y,V1 Z,V1 Mag,V2 X,V2 Y,V2 Z,V2 Mag,V3 X,V3 Y,V3 Z,V3 Mag," TO logFileName2.
LOCAL startTime IS TIME.
LOCAL fromBody IS BODY("Kerbin").
LOCAL toBody IS BODY("Duna").
LOCAL sunBody IS BODY("Sun").
LOCAL period IS MIN(fromBody:ORBIT:PERIOD, toBody:ORBIT:PERIOD).
LOCAL timeStampNew IS 0.
LOCAL r_1 IS V(0,0,0).
LOCAL r_2 IS V(0,0,0).
LOCAL r_3 IS V(0,0,0).
LOCAL v_1 IS V(0,0,0).
LOCAL v_2 IS V(0,0,0).
LOCAL v_3 IS V(0,0,0).
// Time Offset is offset in time from now, in units tenths of the synodic period of the two bodies
FOR timeOffset IN RANGE(0, 30 * 16, 1) {
  SET timeStampNew TO startTime + (timeOffset / 16) * period.
  SET r_1 TO absolutePosition(fromBody, timeStampNew).
  SET r_2 TO absolutePosition(toBody, timeStampNew).
  SET r_3 TO absolutePosition(sunBody, timeStampNew).
  SET v_1 TO absoluteVelocity(fromBody, timeStampNew).
  SET v_2 TO absoluteVelocity(toBody, timeStampNew).
  SET v_3 TO absoluteVelocity(sunBody, timeStampNew).
  LOG ((timeOffset / 16) * period) + "," +
      timeStampNew:SECONDS + "," +
      r_1:X + "," +
      r_1:Y + "," +
      r_1:Z + "," +
      r_1:mag + "," +
      r_2:X + "," +
      r_2:Y + "," +
      r_2:Z + "," +
      r_2:mag + "," +
      r_3:X + "," +
      r_3:Y + "," +
      r_3:Z + "," +
      r_3:mag + "," +
      v_1:X + "," +
      v_1:Y + "," +
      v_1:Z + "," +
      v_1:mag + "," +
      v_2:X + "," +
      v_2:Y + "," +
      v_2:Z + "," +
      v_2:mag + "," +
      v_3:X + "," +
      v_3:Y + "," +
      v_3:Z + "," +
      v_3:mag + "," TO logFileName2.
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
