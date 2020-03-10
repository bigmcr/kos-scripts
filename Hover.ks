LOCAL b IS VECDRAW(V(0,0,0), 10*   east_for(SHIP), GREEN, "East", 1.0, TRUE, 0.2).
LOCAL downhillDirectionVector IS V(0,0,0).
LOCAL C IS VECDRAW(V(0,0,0), downhillDirectionVector, RED, "Downhill", 1.0, TRUE, 0.2).

//UNLOCK mySteer.
//UNLOCK myThrottle.
//SET mySteer TO -VELOCITY:SURFACE.
//SET myThrottle TO 0.

//SET useMySteer TO TRUE.
//SET useMyThrottle TO TRUE.
//SAS OFF.
//RCS OFF.

LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0, 1).			// PID loop to control trottle during vertical descent phase
LOCAL H_PID IS PIDLOOP(1.0, 5.0, 0, -15, 15).		// PID loop to control heading during hover phase
LOCAL groundSlope TO 0.
LOCAL groundSlopeHeading TO 0.
LOCAL downslopeDirection IS V(0,0,0).
LOCAL downslopeSpeed     IS 0.
LOCAL sideDirection      IS V(0,0,0).
LOCAL sideSpeed 	       IS 0.
LOCAL groundSlopeVector  IS 0.
LOCAL downSlopeInfo      IS LEXICON().
LOCAL downslopeDirectionVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Direction" , 1.0, TRUE, 0.2).
LOCAL downslopeSpeedVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Down Speed", 1.0, FALSE, 0.2).
LOCAL sideSpeedVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Side Speed", 1.0, FALSE, 0.2).
LOCAL northVecDraw IS VECDRAW(V(0,0,0), SHIP:NORTH:VECTOR * 10, YELLOW, "North", 1.0, TRUE, 0.2).

SET T_PID:SETPOINT TO 0.
SET H_PID:SETPOINT TO 10.0.
LOCAL done IS FALSE.
LOCAL startTime is TIME:SECONDS.
LOCAL elapsedTime IS TIME:SECONDS - startTime.
LOCAL headerCreated IS FALSE.
LOCAL oldTime IS 0.
LOCAL aboveGround IS 0.

CLEARSCREEN.

UNTIL done {
  SET elapsedTime TO TIME:SECONDS - startTime.
	SET aboveGround TO heightAboveGround().
  SET downSlopeInfo TO findDownSlopeInfo().
	SET groundSlope TO downSlopeInfo["slope"].
	SET groundSlopeHeading TO downSlopeInfo["heading"].
  SET groundSlopeVector TO downSlopeInfo["Vector"].
  SET downslopeDirection TO HEADING(groundSlopeHeading +  0, 0):VECTOR:NORMALIZED.
  SET sideDirection      TO HEADING(groundSlopeHeading + 90, 0):VECTOR:NORMALIZED.
  SET downslopeSpeed  TO VELOCITY:SURFACE * downslopeDirection.
  SET sideSpeed       TO VELOCITY:SURFACE * sideDirection.
	SET velocityPitch   TO pitch_vector(-VELOCITY:SURFACE).
  SET aboveGround TO heightAboveGround().

  IF (TIME:SECONDS <> oldTime) {
    SET oldTime TO TIME:SECONDS.
    IF connectionToKSC() {
      LOCAL message IS "".
      IF NOT headerCreated {
        SET headerCreated TO TRUE.

        SET message TO "Elapsed Time,".
        SET message TO message + "Above Ground,".
        SET message TO message + "Ground Slope,".
      	SET message TO message + "Ground Slope Heading,".
        SET message TO message + "Ground Speed,".
        SET message TO message + "Downslope Speed,".
        SET message TO message + "Side Speed,".
        LOG message TO "0:Hover.csv".
      }
      SET message TO elapsedTime.
      SET message TO message + "," + aboveGround.
    	SET message TO message + "," + groundSlope.
    	SET message TO message + "," + groundSlopeHeading.
      SET message TO message + "," + GROUNDSPEED.
      SET message TO message + "," + downslopeSpeed.
      SET message TO message + "," + sideSpeed.
      LOG message TO "0:Hover.csv".
    }
  }

  PRINT "Slope = " + ROUND(groundSlope, 1) + " deg     " AT (4, 2).
  PRINT "Slope = " + distanceToString(TAN(groundSlope) * 100, 1) + "/ 100 m     " AT (4, 3).
  PRINT "Down Slope Speed = " + distanceToString(downslopeSpeed, 3) + "/s     " AT (4, 4).
  PRINT "Side Speed = " + distanceToString(sideSpeed, 3) + "/s     " AT (4, 5).
  PRINT "Ground Speed = " + distanceToString(SHIP:GROUNDSPEED, 3) + "/s     " AT (4, 6).
  PRINT "Above Ground = " + distanceToString(aboveGround, 3) + "     " AT (4, 7).
  PRINT "Vertical Velocity = " + distanceToString(SHIP:VERTICALSPEED, 3) + "     " AT (4, 8).
  PRINT "Ground Slope Heading = " + ROUND(groundSlopeHeading, 2) + " deg from North     " AT (4, 9).
  PRINT "Throttle at " + ROUND(THROTTLE * 100) + "%    " AT (4, 10).
  PRINT "H_PID at " + ROUND(H_PID:OUTPUT, 2) + " deg from vertical    " AT (4, 11).
//  SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
//  SET mySteer TO HEADING (groundSlopeHeading - 5 * sideSpeed, 90 - H_PID:UPDATE(TIME:SECONDS, downslopeSpeed)).

  SET b:VEC TO 10*   east_for(SHIP).
  SET C:VEC TO groundSlopeVector.
  SET downslopeDirectionVecDraw:VEC TO 10*HEADING(groundSlopeHeading, 0):VECTOR.
  SET downslopeSpeedVecDraw:VEC TO MIN(3, ABS(downslopeSpeed))*downslopeDirection.
  SET sideSpeedVecDraw:VEC TO MIN(3, ABS(sideSpeed))*sideDirection.
//(groundSlope < 0.5)
  IF (1 AND (elapsedTime > 300.0)) SET done TO TRUE.
}

//SET useMySteer TO FALSE.
//SET useMyThrottle TO FALSE.
