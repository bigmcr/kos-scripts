@LAZYGLOBAL OFF.

CLEARSCREEN.

// This landing script uses multiple modes:
// Mode 1 - Burn surface retrograde until periapsis is 45% of the atmosphere's thickness above the ground
// Mode 2 - Activate warp to until altitude is below 45% of the atmosphere's thickness
// Mode 3 - Activate engines (full thrust) until surface speed is 25% of initial orbital speed
// Mode 4 - Maintain surface retrograde while enabling parachutes
// Mode 5 - When all parachutes are deployed or ALT < 100 m, maintain vertical speed
// Mode 6 - Kill engines, use RCS to stabilize

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
	CLEARSCREEN.
	SET mode TO mode + 1.
}

SET myThrottle TO 1.

LOCAL pitchValue IS 0.
LOCAL headingValue IS 90.
LOCAL startTime IS 0.
LOCAL startPosition IS SHIP:GEOPOSITION.
LOCAL headerCreated IS FALSE.
LOCAL gravityAccel TO 0.
LOCAL effectiveAccel TO 0.
LOCAL minTimeToStop TO 0.
LOCAL timeToFall TO 0.
LOCAL x_r TO 0.
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
		PRINT "Throttle at " + ROUND(THROTTLE * 100) + "%    " AT (0, 5).

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
				SET message TO message + "Height Above Ground,".
				SET message TO message + "Throttle Velocity Setpoint,".
				SET message TO message + "Throttle PID Output,".
				SET message TO message + "Pitch,".
				SET message TO message + "Mode,".
				LOG message TO "0:KerbalLandAir.csv".

				SET message TO "s,".
				SET message TO message + "m,".
				SET message TO message + "m/s^2,".
				SET message TO message + "m/s^2,".
				SET message TO message + "m/s^2,".
				SET message TO message + "s,".
				SET message TO message + "s,".
				SET message TO message + "m/s,".
				SET message TO message + "m/s^2,".
				SET message TO message + "m/s,".
				SET message TO message + "m/s^2,".
				SET message TO message + "m,".
				SET message TO message + "m/s,".
				SET message TO message + "%,".
				SET message TO message + "deg,".
				SET message TO message + ",".
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
			SET message TO message + "," + aboveGround.
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
		PRINT "Peri = " + distanceToString(PERIAPSIS, 2) AT (40, 1).
		PRINT "Peri < " + distanceToString(desiredPeri, 2) AT (40, 2).

		SET myThrottle TO 1.
		SET mySteer TO -VELOCITY:SURFACE.
		IF (SHIP:ORBIT:PERIAPSIS < desiredPeri) {advanceMode().}
	}

	// Mode 2 - Wait until altitude is below 45% of the atmosphere's thickness
	IF mode = 2 {
		PRINT "AGL = " + distanceToString(ALTITUDE, 2) + "        " AT (40, 1).
		PRINT "AGL < " + distanceToString(desiredPeri, 2) + "    " AT (40, 2).
		SET myThrottle TO 0.
		SET mySteer TO -VELOCITY:SURFACE.
		IF (ALTITUDE < desiredPeri) {advanceMode().}
		IF ALTITUDE > SHIP:BODY:ATM:HEIGHT + 2500 {
			SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
			SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.
		} ELSE {
			SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
			SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.
		}
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
	//   When all parachutes are deployed and ALT < 1000 m, go to next mode
	IF mode = 4 {
		PRINT "Chutes = " + CHUTES + "        " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 2).
		PRINT "AGL = 1000        " AT (40, 3).
		SET myThrottle TO 0.
		SET mySteer TO -VELOCITY:SURFACE.
		IF (CHUTES AND (aboveGround < 1000)) advanceMode().
	}
	// Mode 5 - Maintain Vertical Speed at setpoint until height above ground is less than 2 meters
	// Note that the steering is limited in patch based on height above ground. This cancels the last horizontal velocity
	IF mode = 5 {
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 1).
		PRINT "AGL < 2        " AT (40, 2).
		PRINT "VSpeed SP = " + distanceToString(T_PID:SETPOINT) + "/s        " AT (40, 3).
		IF (aboveGround > 50) {SET T_PID:SETPOINT TO -aboveGround/5. SET minPitch TO 70.}
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
		SET myThrottle TO 0.
		SET mySteer TO SHIP:UP.
		IF (TIME:SECONDS > startTime + 5) advanceMode().
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
