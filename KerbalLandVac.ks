@LAZYGLOBAL OFF.

CLEARSCREEN.

// This landing script uses multiple modes:
// Mode 1 - Burn surface retrograde until velocity angle below horizon is 45 degrees
// Mode 2 - Maintain Vertical Speed at setpoint until height above ground is less than 1000 meters
// Mode 3 - Hover at 10 m/s horizontal speed in the downslope direction until slope is less than 7.5 degrees
// Mode 4 - Maintain Vertical Speed at setpoint until height above ground is less than 5 meters
// Mode 5 - Vertical Drop to the ground

SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.

LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0, 1).			// PID loop to control trottle during vertical descent phase
LOCAL H_PID IS PIDLOOP(2.5, 2.5, 1, -15, 15).		// PID loop to control heading during hover phase

LOCAL oldTime IS ROUND(TIME:SECONDS, 1).
LOCAL oldVSpeed IS 0.
LOCAL oldHSpeed IS 0.
LOCAL oldDistance IS SHIP:BODY:RADIUS.
LOCAL velocityPitch IS pitch_vector(-VELOCITY:SURFACE).
LOCAL hAccel IS 0.
LOCAL vAccel IS 0.
LOCAL aboveGround IS heightAboveGround().
LOCAL update IS 0.
LOCAL mode TO 1.

UNLOCK mySteer.
UNLOCK myThrottle.
SET mySteer TO -VELOCITY:SURFACE.
SET myThrottle TO 0.

SET useMySteer TO TRUE.
SET useMyThrottle TO TRUE.
SAS OFF.
RCS OFF.
PANELS OFF.

// Engine staging - this should drop any used stage
WHEN MAXTHRUST = 0 THEN {
	PRINT "Staging from max thrust".
	stageFunction().
}


FUNCTION advanceMode {
	SET mode TO mode + 1.
}

SET myThrottle TO 1.

LOCAL pitchValue IS 0.
LOCAL headingValue IS 90.
LOCAL startTime IS 0.
LOCAL startPosition IS SHIP:GEOPOSITION.
LOCAL flatSpot IS SHIP:GEOPOSITION.
LOCAL flatSpotDistancePrev IS -1.
LOCAL coastDistance IS 0.
LOCAL landingArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, BLUE, "Landing Direction", 1.0, FALSE, 0.2).
LOCAL velocityArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, RED, "Velocity", 1.0, FALSE, 0.2).
LOCAL aimingArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, GREEN, "Aiming", 1.0, FALSE, 0.2).
LOCAL groundSlope TO 0.
LOCAL groundSlopeHeading TO 0.
LOCAL headerCreated IS FALSE.
LOCAL downslopeDirectionVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Direction" , 1.0, FALSE, 0.2).
LOCAL downslopeSpeedVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Down Speed", 1.0, FALSE, 0.2).
LOCAL sideSpeedVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Side Speed", 1.0, FALSE, 0.2).
LOCAL gravityAccel TO 0.
LOCAL effectiveAccel TO 0.
LOCAL minTimeToStop TO 0.
LOCAL timeToFall TO 0.
LOCAL downSlopeInfo IS LEXICON().
LOCAL x_r TO 0.
LOCAL downSlopeVector IS V(0,0,0).
LOCAL downslopeDirection IS 0.
LOCAL sideDirection IS 0.
LOCAL downslopeSpeed IS 0.
LOCAL sideSpeed IS 0.
LOCAL headingSteeringAdjust IS 0.

LOCAL downslopeVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Down Slope Direction", 1.0, TRUE, 0.2).

UNTIL mode > 5 {
	PRINT "Mode " + mode AT (40, 0).
	SET aboveGround TO heightAboveGround().
	SET downSlopeInfo TO findDownSlopeInfo().
	SET groundSlope TO downSlopeInfo["slope"].
	SET groundSlopeHeading TO downSlopeInfo["heading"].
	SET downSlopeVector TO downSlopeInfo["Vector"].
	SET downslopeDirection TO HEADING(groundSlopeHeading +  0, 0):VECTOR:NORMALIZED.
	SET sideDirection      TO HEADING(groundSlopeHeading + 90, 0):VECTOR:NORMALIZED.
	SET downslopeSpeed  TO VELOCITY:SURFACE * downslopeDirection.
	SET sideSpeed       TO VELOCITY:SURFACE * sideDirection.
	SET velocityPitch   TO pitch_vector(-VELOCITY:SURFACE).

	SET downslopeVecDraw:VEC TO downSlopeVector.

	IF (TIME:SECONDS <> oldTime) {
		SET hAccel TO (GROUNDSPEED - oldHSpeed)/(TIME:SECONDS - oldTime).
		SET vAccel TO (VERTICALSPEED - oldVSpeed)/(TIME:SECONDS - oldTime).
		SET gravityAccel TO BODY:MU/(ALTITUDE + BODY:RADIUS)^2.
		SET effectiveAccel TO shipInfo["Maximum"]["Accel"] - gravityAccel.
		IF effectiveAccel <> 0 SET minTimeToStop TO VERTICALSPEED / effectiveAccel.
		SET minTimeToStop TO -VERTICALSPEED / effectiveAccel.
		SET x_r TO (SHIP:GEOPOSITION:TERRAINHEIGHT + SHIP:BODY:RADIUS) / (ALTITUDE + SHIP:GEOPOSITION:TERRAINHEIGHT + SHIP:BODY:RADIUS).
		SET timeToFall TO ((CONSTANT:DegToRad*ARCCOS(SQRT(x_r))+((x_r)*(1-x_r)))/SQRT(2*BODY:MU))*(SHIP:GEOPOSITION:TERRAINHEIGHT + SHIP:BODY:RADIUS)^1.5.

		PRINT "Horizontal Speed " + distanceToString(GROUNDSPEED, 2) + "/s     " AT (0, 0).
		PRINT "Horizontal Acceleration " + distanceToString(hAccel, 2) + "/s^2    " AT (0, 1).
		PRINT "Vertical Speed " + distanceToString(VERTICALSPEED, 2) + "/s    " AT (0, 2).
		PRINT "Vertical Acceleration " + distanceToString(vAccel, 2) + "/s^2    " AT (0, 3).
		PRINT "Ground Speed = " + distanceToString(SHIP:GROUNDSPEED, 3) + "/s     " AT (0, 4).
		PRINT "Slope of Ground " + ROUND(groundSlope, 2) + " deg    " AT (0, 5).
		PRINT "Slope of Ground " + distanceToString(TAN(groundSlope) * 100, 1) + "/100 m     " AT (0, 6).
		PRINT "Ground Slope Heading = " + ROUND(groundSlopeHeading, 2) + " deg from North     " AT (0, 7).
		PRINT "Down-Slope Speed " + distanceToString(downslopeSpeed, 2) + "/s      " AT (0, 8).
		PRINT "Side-Slope Speed " + distanceToString(sideSpeed, 2) + "/s      " AT (0, 9).
		PRINT "Throttle at " + ROUND(THROTTLE * 100) + "%    " AT (0, 10).
	  PRINT "H_PID at " + ROUND(H_PID:OUTPUT, 2) + " deg from vertical    " AT (0, 11).

		IF connectionToKSC() {
			LOCAL message IS "".
			IF NOT headerCreated {
				SET headerCreated TO TRUE.
				SET message TO "Mission Time,".
				SET message TO message + "Horizontal Distance,".
				SET message TO message + "Maximum Accel,".
				SET message TO message + "Effective Accel,".
				SET message TO message + "Gravity Accel,".
				SET message TO message + "Min Time To Stop,".
				SET message TO message + "Time to fall,".
				SET message TO message + "Horizontal Speed,".
				SET message TO message + "Horizontal Acceleration,".
				SET message TO message + "Vertical Speed,".
				SET message TO message + "Vertical Acceleration,".
				SET message TO message + "Downslope Speed,".
				SET message TO message + "Side Speed,".
				SET message TO message + "Height Above Ground,".
				SET message TO message + "Ground Slope,".
				SET message TO message + "Ground Slope Heading,".
				SET message TO message + "Throttle Velocity Setpoint,".
				SET message TO message + "Throttle PID Output,".
				SET message TO message + "Heading PID Output,".
				SET message TO message + "Heading Steering Adjust,".
				SET message TO message + "Pitch,".
				SET message TO message + "Mode,".
				LOG message TO "0:EqualTime.csv".
			}
			SET message TO missionTime.
			SET message TO message + "," + greatCircleDistance(SHIP:GEOPOSITION, startPosition).
			SET message TO message + "," + shipInfo["Maximum"]["Accel"].
			SET message TO message + "," + effectiveAccel.
			SET message TO message + "," + gravityAccel.
			SET message TO message + "," + minTimeToStop.
			SET message TO message + "," + timeToFall.
			SET message TO message + "," + GROUNDSPEED.
			SET message TO message + "," + hAccel.
			SET message TO message + "," + VERTICALSPEED.
			SET message TO message + "," + vAccel.
			SET message TO message + "," + downslopeSpeed.
			SET message TO message + "," + sideSpeed.
			SET message TO message + "," + aboveGround.
			SET message TO message + "," + groundSlope.
			SET message TO message + "," + groundSlopeHeading.
			SET message TO message + "," + T_PID:SETPOINT.
			SET message TO message + "," + T_PID:OUTPUT.
			SET message TO message + "," + H_PID:OUTPUT.
			SET message TO message + "," + headingSteeringAdjust.
			SET message TO message + "," + pitch_for(SHIP).
			SET message TO message + "," + mode.
			LOG message TO "0:EqualTime.csv".
		}

		SET oldHSpeed TO GROUNDSPEED.
		SET oldVSpeed TO VERTICALSPEED.
		SET oldTime TO TIME:SECONDS.
	}
	// Mode 1 - Surface Retrograde until velocityPitch is greater than 45
	IF (mode = 1) {
		PRINT "VSpeed SP = N/A  " AT (40, 1).
		PRINT "SrfVel Pitch > 45" AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "SrfVel Pitch " + ROUND(velocityPitch, 2) + "      " AT (40, 4).
		SET mySteer TO -VELOCITY:SURFACE.
		IF (velocityPitch > 45) {
			advanceMode().
		}
	}
	// Mode 2 - Maintain Vertical Speed at setpoint until height above ground is less than 1000 meters
	// Note that the steering is limited to a pitch of 70 degrees at minimum. This cancels the last horizontal velocity
	IF mode = 2 {
		PRINT "VSpeed SP = " + ROUND(T_PID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "AGL < 1000     " AT (40, 4).
//		IF (aboveGround > 1000) SET T_PID:SETPOINT TO aboveGround / -200.
		IF (aboveGround > 50000) SET T_PID:SETPOINT TO -1000.
		ELSE IF (aboveGround > 10000) SET T_PID:SETPOINT TO -200.
		ELSE IF (aboveGround > 1000) SET T_PID:SETPOINT TO -50.
		ELSE {advanceMode().}
		SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF GROUNDSPEED < 0.1 SET mySteer TO HEADING (0, 90).
		ELSE SET mySteer TO HEADING (yaw_vector(-VELOCITY:SURFACE), MAX(70, velocityPitch)).
	}
	// Mode 3 - Maintain height above ground with 10 m/s horizontal speed in the direction of downslope until slope is less than 7.5 degrees
	// Note that the steering is limited to a pitch of 85 degrees at minimum. This limits the remaining horizontal velocity
	IF mode = 3 {
		PRINT "VSpeed SP = " + ROUND(T_PID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "Slope = " + ROUND(groundSlope, 2) + "     " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "Slope < 5.0    " AT (40, 4).
		SET T_PID:SETPOINT TO 0.0.
		SET H_PID:SETPOINT TO 10.0.

	  SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		SET headingSteeringAdjust TO - 2 * sideSpeed.
		IF headingSteeringAdjust > 30 SET headingSteeringAdjust TO 30.
		IF headingSteeringAdjust < 30 SET headingSteeringAdjust TO -30.
	  SET mySteer TO HEADING (groundSlopeHeading + headingSteeringAdjust, 90 - H_PID:UPDATE(TIME:SECONDS, downslopeSpeed)).

		SET downslopeDirectionVecDraw:SHOW TO TRUE.
		SET downslopeSpeedVecDraw:SHOW TO TRUE.
		SET sideSpeedVecDraw:SHOW TO TRUE.
	  SET downslopeDirectionVecDraw:VEC TO 10*HEADING(groundSlopeHeading, 0):VECTOR.
	  SET downslopeSpeedVecDraw:VEC TO MIN(3, ABS(downslopeSpeed))*downslopeDirection.
	  SET sideSpeedVecDraw:VEC TO MIN(3, ABS(sideSpeed))*sideDirection.

		IF (aboveGround < 500 OR groundSlope < 5.0) advanceMode().
	}
	// Mode 4 - Maintain Vertical Speed at setpoint until height above ground is less than 5 meters
	// Note that the steering is limited to a pitch of 70 degrees at minimum. This cancels the last horizontal velocity
	IF mode = 4 {
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 1).
		PRINT "Slope = " + ROUND(groundSlope,2) + "     " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "AGL < 5        " AT (40, 4).
//		SET T_PID:SETPOINT TO aboveGround / -200.
		IF (aboveGround > 1000) SET T_PID:SETPOINT TO -20.
		ELSE IF (aboveGround > 50) SET T_PID:SETPOINT TO -10.
		ELSE IF (aboveGround > 25) {SET T_PID:SETPOINT TO -1. SET KUNIVERSE:TIMEWARP:WARP TO 0.}
		ELSE IF (aboveGround < 2) {advanceMode().}
		SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF GROUNDSPEED < 0.1 SET mySteer TO HEADING (0, 90).
		ELSE SET mySteer TO HEADING (yaw_vector(-VELOCITY:SURFACE), MAX(70, velocityPitch)).
		GEAR ON.
		SET downslopeDirectionVecDraw:SHOW TO FALSE.
		SET downslopeSpeedVecDraw:SHOW TO FALSE.
		SET sideSpeedVecDraw:SHOW TO FALSE.
	}
	// Mode 5 - Vertical Drop to the ground - use RCS for stabilization
	IF mode = 5 {
		IF startTime = 0 {
			SET startTime TO TIME:SECONDS.
		}
		RCS ON.
		PRINT "Vertical Drop    " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "       " AT (40, 2).
		PRINT "SrfSpd " + ROUND(VELOCITY:SURFACE:MAG, 3) + "     " AT (40, 3).
		PRINT "SrfSpd < 0.5     " AT (40, 4).
		SET myThrottle TO 0.
		SET mySteer TO SHIP:UP.
		IF (TIME:SECONDS > startTime + 5) AND (VELOCITY:SURFACE:MAG < 0.5) advanceMode().
	}
	WAIT 0.
}

SET myThrottle TO 0.
SET mySteer TO SHIP:UP.
SET useMySteer TO FALSE.
SET useMyThrottle TO FALSE.

endScript().

IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Landed on " + SHIP:BODY:NAME.
ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
