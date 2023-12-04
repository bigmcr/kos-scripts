@LAZYGLOBAL OFF.

setLockedThrottle(FALSE).
setLockedSteering(TRUE).

LOCAL head IS ROUND(yaw_for(ship)).
SET globalSteer TO HEADING(head, 0, 0).
LOCK WHEELSTEERING TO head.
LOCAL SPEED_PID IS PIDLOOP(2.0, 1, 2.0, -1, 1).	// PID loop to control ground speed
SET SPEED_PID:SETPOINT TO ROUND(GROUNDSPEED).
LOCK WHEELTHROTTLE TO SPEED_PID:UPDATE(TIME:SECONDS, SHIP:VELOCITY:SURFACE * SHIP:FACING:VECTOR).
AG1 OFF. AG2 OFF. AG3 OFF. AG4 OFF. AG5 OFF.
WHEN AG2 THEN {AG2 OFF. SET SPEED_PID:SETPOINT TO SPEED_PID:SETPOINT + 1. RETURN TRUE.}
WHEN AG3 THEN {AG3 OFF. SET SPEED_PID:SETPOINT TO SPEED_PID:SETPOINT - 1. RETURN TRUE.}
WHEN AG4 THEN {AG4 OFF. SET head TO head + 5. IF head >= 360 SET head TO head - 360. RETURN TRUE.}
WHEN AG5 THEN {AG5 OFF. SET head TO head - 5. IF head < 0 SET head TO head + 360. RETURN TRUE.}
UNTIL AG1 {
  CLEARSCREEN.
  PRINT "Heading Direction " + head + "     ".
  PRINT "Pointing Direction " + ROUND(yaw_for(SHIP), 3) + "     ".
  PRINT "Groundspeed PV " + distanceToString(GROUNDSPEED, 2) + "/s     ".
  PRINT "Groundspeed SP " + distanceToString(SPEED_PID:SETPOINT, 2) + "/s     ".
  PRINT "Pointing Slope " + ROUND(90 - VANG(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + " deg     ".
  PRINT "Velocity Slope " + ROUND(90 - VANG(SHIP:UP:VECTOR, SHIP:FACING:VECTOR), 2) + " deg     ".
  PRINT "Press AG1 to end     ".
  WAIT 0.
}
