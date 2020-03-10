CLEARSCREEN.

LOCAL maxTraces IS 50.
LOCAL traceIndex IS 0.
LOCAL slopeInfo IS LIST().
LOCAL vecDrawList IS LIST().
LOCAL startVector IS V(0,0,0).
LOCAL metersNorth IS 0.
LOCAL metersEast IS 0.
LOCAL east IS east_for(SHIP).

UNTIL traceIndex > maxTraces {
  SET slopeInfo TO findUpSlopeInfo(SHIP:NORTH:VECTOR * startVector, east * startVector).
  vecDrawList:ADD(VECDRAW(startVector, slopeInfo["vector"], RED, traceIndex , 1.5, TRUE, 0.2)).
  SET startVector TO startVector + slopeInfo["vector"].
  SET traceIndex TO traceIndex + 1.
}

SET traceIndex TO 0.
SET startVector TO V(0,0,0).
UNTIL traceIndex > maxTraces {
  SET slopeInfo TO findDownSlopeInfo(SHIP:NORTH:VECTOR * startVector, east * startVector).
  vecDrawList:ADD(VECDRAW(startVector, slopeInfo["vector"], GREEN, traceIndex , 1.5, TRUE, 0.2)).
  SET startVector TO startVector + slopeInfo["vector"].
  SET traceIndex TO traceIndex + 1.
}

AG1 OFF.
UNTIL AG1 {WAIT 0.}
