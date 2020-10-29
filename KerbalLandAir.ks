@LAZYGLOBAL OFF.

CLEARSCREEN.

// This landing script uses multiple modes:
// Mode 1 - Burn surface retrograde until periapsis is 45% of the atmosphere's thickness above the ground
// Mode 2 - Activate physics warp to until altitude is below 45% of the atmosphere's thickness
// Mode 3 - Activate engines (full thrust) until surface speed is 25% of initial orbital speed
// Mode 4 - Maintain surface retrograde while enabling parachutes
// Mode 5 - When all parachutes are deployed or ALT < 100 m, maintain vertical speed
// Mode 6 - Kill engines, use RCS to stabilize

SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.

LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0, 1).			// PID loop to control trottle during vertical descent phase

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
LOCAL cancelHoriz IS TRUE.

UNLOCK mySteer.
UNLOCK myThrottle.
SET mySteer TO -VELOCITY:SURFACE.
SET myThrottle TO 0.

SET useMySteer TO TRUE.
SET useMyThrottle TO TRUE.
SAS OFF.
RCS OFF.
PANELS OFF.

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
LOCAL groundSlope TO 0.
LOCAL groundSlopeHeading TO 0.
LOCAL headerCreated IS FALSE.
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
LOCAL minPitch IS 70.

LOCAL desiredPeri IS SHIP:BODY:ATM:HEIGHT * 0.45.
LOCAL initialSpeed IS SHIP:VELOCITY:ORBIT:MAG.


// This should deploy all parachutes as soon as it is safe to do so
WHEN (NOT CHUTESSAFE) THEN {
    CHUTESSAFE ON.
    RETURN (NOT CHUTES).
}

UNTIL mode > 6 {
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
				SET message TO message + "Pitch,".
				SET message TO message + "Mode,".
				LOG message TO "0:KerbalLandAir.csv".
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
			SET message TO message + "," + pitch_for(SHIP).
			SET message TO message + "," + mode.
			LOG message TO "0:KerbalLandAir.csv".
		}

		SET oldHSpeed TO GROUNDSPEED.
		SET oldVSpeed TO VERTICALSPEED.
		SET oldTime TO TIME:SECONDS.
	}
	// Mode 1 - Burn surface retrograde until periapsis is 45% of the atmosphere's thickness above the ground
	IF (mode = 1) {
		PRINT "Peri < " + distanceToString(desiredPeri, 2) AT (40, 2).

		SET myThrottle TO 1.
		SET mySteer TO -VELOCITY:SURFACE.
		IF (SHIP:ORBIT:PERIAPSIS < desiredPeri) {advanceMode().}
	}

	// Mode 2 - Wait until altitude is below 45% of the atmosphere's thickness
	IF mode = 2 {
		PRINT "AGL = " + distanceToString(aboveGround, 2) + "        " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "AGL < " + distanceToString(desiredPeri, 2) + "    " AT (40, 4).
		SET myThrottle TO 0.
		SET mySteer TO -VELOCITY:SURFACE.
		IF (aboveGround < desiredPeri) {advanceMode().}
	}
	// Mode 3 - Activate engines (full thrust) until surface speed is 25% of initial orbital speed
	IF mode = 3 {
		PRINT "Speed SP = " + distanceToString(initialSpeed * 0.25, 2) + "/s    " AT (40, 1).
		PRINT "Speed = " + distanceToString(VELOCITY:SURFACE:MAG, 2) + "/s     " AT (40, 2).
	  SET myThrottle TO 1.
		SET mySteer TO -VELOCITY:SURFACE.

		IF (VELOCITY:SURFACE:MAG < initialSpeed * 0.25) advanceMode().
	}
	// Mode 4 - Maintain surface retrograde while enabling parachutes
	//   When all parachutes are deployed or ALT < 100 m, go to next mode
	IF mode = 4 {
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 1).
		PRINT "Slope = " + ROUND(groundSlope,2) + "     " AT (40, 2).
		PRINT "minPitch = " + minPitch + "     " AT (40, 3).
		PRINT "AGL < 5        " AT (40, 4).
		SET myThrottle TO 0.
		SET mySteer TO -VELOCITY:SURFACE.
		IF ((NOT CHUTES) OR (aboveGround < 100)) advanceMode().
	}
	// Mode 5 - Maintain Vertical Speed at setpoint until height above ground is less than 2 meters
	// Note that the steering is limited in patch based on height above ground. This cancels the last horizontal velocity
	IF mode = 5 {
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 1).
		PRINT "Slope = " + ROUND(groundSlope,2) + "     " AT (40, 2).
		PRINT "minPitch = " + minPitch + "     " AT (40, 3).
		PRINT "AGL < 5        " AT (40, 4).
		IF (aboveGround > 50) {SET T_PID:SETPOINT TO -10. SET minPitch TO 70.}
		ELSE IF (aboveGround > 25) {SET T_PID:SETPOINT TO -1. SET KUNIVERSE:TIMEWARP:WARP TO 0. SET minPitch TO 85.}
		ELSE IF (aboveGround < 2) {advanceMode().}
		SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF cancelHoriz AND GROUNDSPEED < 0.25 SET cancelHoriz TO FALSE.
		IF NOT cancelHoriz AND GROUNDSPEED > 0.5 SET cancelHoriz TO TRUE.

		IF NOT cancelHoriz SET mySteer TO HEADING (0, 90).
		ELSE SET mySteer TO HEADING (yaw_vector(-VELOCITY:SURFACE), MAX(minPitch, velocityPitch)).

		GEAR ON.
		LIGHTS ON.
	}
	// Mode 6 - Kill engines, use RCS to stabilize
	IF mode = 6 {
		IF startTime = 0 {SET startTime TO TIME:SECONDS.}
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
