@LAZYGLOBAL OFF.

PARAMETER desiredHeight IS 1000.
PARAMETER maxVelocity IS 50.

SET maxVelocity TO ABS(maxVelocity).

SET globalSteer TO -VELOCITY:SURFACE.
SET globalThrottle TO 0.

setLockedSteering(TRUE).
setLockedThrottle(TRUE).
SAS OFF.
RCS OFF.

LOCAL V_PID IS PIDLOOP(0.5, 0.1, 0, 0, 1).			// PID loop to control trottle based on speed
LOCAL X_PID IS PIDLOOP(0.05, 0.01, 0.05, -maxVelocity, maxVelocity).			// PID loop to control V_PID based on position
LOCAL surfaceVelocityVecDraw IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN SHIP:VELOCITY:SURFACE:NORMALIZED * 10.}, BLUE, "Surface Velocity" , 1.0, TRUE, 0.2).

LOCAL done IS FALSE.
LOCAL startTime is TIME:SECONDS.
LOCAL elapsedTime IS TIME:SECONDS - startTime.
LOCAL headerCreated IS FALSE.
LOCAL oldTime IS 0.
LOCAL aboveGround IS 0.

LOCAL minPitch TO 70.
LOCAL cancelHoriz IS TRUE.
LOCAL velocityPitch IS 0.

SET X_PID:SETPOINT TO desiredHeight.

CLEARSCREEN.

ON AG1 {
  SET X_PID:SETPOINT TO X_PID:SETPOINT + 10.
  RETURN TRUE.
}

ON AG2 {
  SET X_PID:SETPOINT TO X_PID:SETPOINT - 10.
  RETURN TRUE.
}

UNTIL done {
  SET elapsedTime TO TIME:SECONDS - startTime.
	SET aboveGround TO heightAboveGround().
	SET velocityPitch   TO pitch_for(-VELOCITY:SURFACE).
  SET aboveGround TO heightAboveGround().

  IF (TIME:SECONDS <> oldTime) {
    SET oldTime TO TIME:SECONDS.
    IF connectionToKSC() {
      LOCAL message IS "".
      IF NOT headerCreated {
        SET headerCreated TO TRUE.

        SET message TO "Elapsed Time,".
        SET message TO message + "Above Ground,".
        SET message TO message + "Above Ground SP,".
        SET message TO message + "Above Ground PID Output,".
        SET message TO message + "Vertical Speed,".
        SET message TO message + "Vertical Speed SP,".
        SET message TO message + "Vertical Speed PID Output,".
        SET message TO message + "Horizontal Speed,".
        LOG message TO "0:Hover.csv".
      }
      SET message TO elapsedTime.
      SET message TO message + "," + aboveGround.
      SET message TO message + "," + X_PID:SETPOINT.
      SET message TO message + "," + X_PID:OUTPUT.
      SET message TO message + "," + VERTICALSPEED.
      SET message TO message + "," + V_PID:SETPOINT.
      SET message TO message + "," + V_PID:OUTPUT.
      SET message TO message + "," + GROUNDSPEED.
      LOG message TO "0:Hover.csv".
    }
  }

  PRINT "Ground Speed = " + distanceToString(SHIP:GROUNDSPEED, 3) + "/s     " AT (0, 0).
  PRINT "Above Ground = " + distanceToString(aboveGround, 3) + "     " AT (0, 1).
  PRINT "Above Ground SP = " + distanceToString(X_PID:SETPOINT, 3) + "     " AT (0, 2).
  PRINT "Vertical Velocity = " + distanceToString(SHIP:VERTICALSPEED, 3) + "     " AT (0, 3).
  PRINT "Vertical Velocity SP = " + distanceToString(V_PID:SETPOINT, 3) + "/s     " AT (0, 4).
  PRINT "Throttle at " + ROUND(THROTTLE * 100, 2) + "%    " AT (0, 5).
  PRINT "Groundspeed = " + distanceToString(GROUNDSPEED, 2) + "/s     " AT (0, 6).
  SET V_PID:SETPOINT TO X_PID:UPDATE(TIME:SECONDS, aboveGround).
  SET globalThrottle TO V_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).

  IF cancelHoriz AND GROUNDSPEED < 0.25 SET cancelHoriz TO FALSE.
  IF NOT cancelHoriz AND GROUNDSPEED > 0.5 SET cancelHoriz TO TRUE.

  IF NOT cancelHoriz SET globalSteer TO HEADING (0, 90).
  ELSE {
    IF VERTICALSPEED > 0 SET globalSteer TO HEADING (yaw_for(-VELOCITY:SURFACE), MAX(minPitch, velocityPitch)).
    ELSE SET globalSteer TO HEADING (yaw_for(VELOCITY:SURFACE), MAX(minPitch, velocityPitch)).
  }

  IF (elapsedTime > 300.0) SET done TO TRUE.
}

setLockedSteering(FALSE).
setLockedThrottle(FALSE).
