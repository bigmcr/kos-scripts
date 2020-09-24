@LAZYGLOBAL OFF.

PARAMETER aimTarget IS HASTARGET.

CLEARSCREEN.

// This landing script uses multiple modes:
// Mode 1 - Pure surface retrograde for 10 seconds
// Mode 2 - Vertical Speed Setpoint

LOCAL approxLandingDistance IS 763228.

IF HASTARGET {
	IF TARGET:VELOCITY:ORBIT:SQRMAGNITUDE*0.999 > SHIP:BODY:MU/(TARGET:ALTITUDE + SHIP:BODY:RADIUS)
	PRINT "Warping to the correct point in orbit".
	LOCAL dist IS MAX(greatCircleDistance(SHIP:GEOPOSITION, TARGET:GEOPOSITION) - approxLandingDistance, 0).
	warpToTime(SHIP:ORBIT:PERIOD * dist / (SHIP:BODY:RADIUS * 2 * 3.14159) + TIME:SECONDS).
}

PRINT "Ullage RCS burn starting".

SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.

LOCAL pitchPID IS PIDLOOP(1, 0.1, 0, 0, 60).						// PID loop to control pitch
LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0.05, 1).					// PID loop to control trottle during vertical descent phase

LOCAL oldTime IS ROUND( TIME:SECONDS, 1).
LOCAL oldVSpeed IS 0.
LOCAL oldHSpeed IS 0.
LOCAL oldDistance IS SHIP:BODY:RADIUS.
LOCAL velocityPitch IS pitch_vector(-VELOCITY:SURFACE).
LOCAL hAccel IS 0.
LOCAL vAccel IS 0.
LOCAL timeToHSpeedZero IS 9999999.
LOCAL timeToVSpeedZero IS 9999999.
LOCAL aboveGround IS heightAboveGround().
LOCAL mode TO 0.

UNLOCK mySteer.
UNLOCK myThrottle.
SET mySteer TO -VELOCITY:SURFACE.
SET myThrottle TO 0.

SET useMySteer TO TRUE.
SET useMyThrottle TO TRUE.

RCS ON.
SET SHIP:CONTROL:FORE TO 1.
WAIT 10.
SET SHIP:CONTROL:FORE TO 0.
RCS OFF.

// Engine staging - this should drop any used stage
WHEN MAXTHRUST = 0 THEN {
	PRINT "Staging from max thrust".
	stageFunction().
}

// Note that staging on resources is intentionally not implemented.
// Often, the landing legs are on the external tanks which run dry, so we shouldn't jetison the landing legs

FUNCTION advanceMode {
	SET mode TO mode + 1.
}

SET myThrottle TO 1.

IF connectionToKSC() LOG "Mission Time,Horizontal Distance,Horizontal Speed,Horizontal Acceleration,Vertical Speed,Vertical Acceleration,Time to Horizontal Zero,Height Above Ground,Ground Pitch,Pitch Velocity Setpoint,Throttle Velocity Setpoint,Pitch,Distance to Target,Mode,,aimTarget," + aimTarget TO "0:EqualTime.csv".

LOCAL pitchValue IS 0.
LOCAL headingValue IS 90.
LOCAL timerStartTime IS 0.
LOCAL startPosition IS SHIP:GEOPOSITION.
LOCAL flatSpot IS SHIP:GEOPOSITION.
LOCAL flatSpotDistance IS 0.
LOCAL flatSpotDistancePrev IS -1.
LOCAL coastDistance IS 0.
LOCAL landingArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, BLUE, "Landing Direction", 1.0, FALSE, 0.2).
LOCAL velocityArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, RED, "Velocity", 1.0, FALSE, 0.2).
LOCAL aimingArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, GREEN, "Aiming", 1.0, FALSE, 0.2).
LOCAL loggingStarted IS FALSE.
LOCAL downslopeInfo IS findDownSlopeInfo().

UNTIL mode > 5 {
	PRINT "Mode " + mode AT (40, 0).
	SET aboveGround TO heightAboveGround().
	SET velocityPitch TO pitch_vector(-VELOCITY:SURFACE).
	IF (TIME:SECONDS <> oldTime) {
		SET downslopeInfo TO findDownSlopeInfo(10, 10).
		SET hAccel TO (GROUNDSPEED - oldHSpeed)/(TIME:SECONDS - oldTime).
		SET vAccel TO (VERTICALSPEED - oldVSpeed)/(TIME:SECONDS - oldTime).
		SET flatSpotDistancePrev TO flatSpotDistance.
		IF (mode < 2) {
			IF HASTARGET SET flatSpotDistance TO VXCL(SHIP:UP:VECTOR, TARGET:POSITION):MAG.
			ELSE SET flatSpotDistance TO 0.
		}
		ELSE SET flatSpotDistance TO VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):MAG.
		IF (ABS(hAccel) > 0.05) AND (GROUNDSPEED > 1.0) {
			SET timeToHSpeedZero TO ABS (GROUNDSPEED / hAccel).
		} ELSE SET timeToHSpeedZero TO 0.

		IF (ABS(vAccel) > 0.05) {
			SET timeToVSpeedZero TO ABS (VERTICALSPEED / vAccel).
		} ELSE SET timeToVSpeedZero TO 0.

		IF hAccel < 0 SET loggingStarted TO TRUE.

		PRINT "Horizontal Speed " + ROUND(GROUNDSPEED, 2) + " m/s     " AT (0, 0).
		PRINT "Horizontal Acceleration " + ROUND(hAccel, 2) + " m/s^2    " AT (0, 1).
		PRINT "Vertical Speed " + ROUND(VERTICALSPEED, 2) + " m/s    " AT (0, 2).
		PRINT "Vertical Acceleration " + ROUND(vAccel, 2) + " m/s^2    " AT (0, 3).
		PRINT "Time to Horizontal Zero " + ROUND(timeToHSpeedZero, 2) + " s    " AT (0, 4).
		PRINT "Slope of Ground " + ROUND(downslopeInfo["slope"], 2) + " deg     " AT (0, 5).
		PRINT "Distance to Target " + distanceToString(flatSpot:POSITION:MAG) + "       " AT (0, 6).

		LOCAL message IS missionTime.
		SET message TO message + "," + greatCircleDistance(SHIP:GEOPOSITION, startPosition).
		SET message TO message + "," + GROUNDSPEED.
		SET message TO message + "," + hAccel.
		SET message TO message + "," + VERTICALSPEED.
		SET message TO message + "," + vAccel.
		SET message TO message + "," + timeToHSpeedZero.
		SET message TO message + "," + aboveGround.
		SET message TO message + "," + downslopeInfo["slope"].
		SET message TO message + "," + pitchPID:SETPOINT.
		SET message TO message + "," + T_PID:SETPOINT.
		SET message TO message + "," + pitch_for(SHIP).
		SET message TO message + "," + flatSpotDistance.
		SET message TO message + "," + mode.
		IF connectionToKSC() AND loggingStarted LOG message TO "0:EqualTime.csv".

		SET oldHSpeed TO GROUNDSPEED.
		SET oldVSpeed TO VERTICALSPEED.
		SET oldTime TO TIME:SECONDS.
	}
	// surface retrograde for 10 seconds
	IF (mode = 0) {
		PRINT "Surface Retro  " AT (40, 1).
		PRINT "10 seconds   " AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "Time: " + ROUND(TIME:SECONDS - timerStartTime, 2) + "      " AT (40, 4).
		SET mySteer TO -VELOCITY:SURFACE.
		IF (timerStartTime = 0) SET timerStartTime TO TIME:SECONDS.
		IF (TIME:SECONDS > timerStartTime + 10) {
			pitchPID:UPDATE(TIME:SECONDS, VERTICALSPEED).
			SET pitchPID:SETPOINT TO (heightPrediction(120)["max"] + 500 - ALTITUDE) / 600.
			advanceMode().
		}
	}
	// Mode 1 - Maintain vertical speed setpoint by varying pitch
	IF (mode = 1) {
		PRINT "VSpeed SP = " + ROUND(pitchPID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "SrfVel Pitch > 3 " AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "SrfVel Pitch " + ROUND(velocityPitch, 2) + "      " AT (40, 4).
		IF (timerStartTime = 0) SET timerStartTime TO TIME:SECONDS.
		IF (TIME:SECONDS > timerStartTime + 60) {
			SET pitchPID:SETPOINT TO (heightPrediction(120)["max"] + 500 - ALTITUDE) / 600.
			SET timerStartTime TO TIME:SECONDS.
		}
		SET pitchValue TO pitchPID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF (aimTarget AND HASTARGET AND (TARGET:POSITION:MAG < oldDistance)) {
			SET headingValue TO 180 + 4 * yaw_vector(VELOCITY:SURFACE) - 3 * yaw_vector(TARGET:POSITION).
			SET oldDistance TO TARGET:POSITION:MAG.
		} ELSE SET headingValue TO yaw_vector(-VELOCITY:SURFACE).
		SET mySteer TO HEADING (headingValue, pitchValue).
		IF (velocityPitch > 3) {
			// if we are aiming at a setpoint, find a flat spot near the setpoint to land. Also make arrows pointing in relevant direction.
			IF aimTarget {
				IF HASTARGET SET flatSpot TO findMinSlope(TARGET:GEOPOSITION:POSITION, 1000, 100).
				ELSE 		 SET flatSpot TO findMinSlope(SHIP:POSITION + VELOCITY:SURFACE * (timeToHSpeedZero + 60.0)/ 2.0, 1000, 100).
				SET flatSpot TO findMinSlope(flatSpot:POSITION, 100, 10).
				SET landingArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, BLUE, "Landing Direction", 1.0, aimTarget, 0.2).
				SET landingArrow:VECUPDATER TO {RETURN VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):NORMALIZED * 10.}.

				SET velocityArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, RED, "Velocity", 1.0, aimTarget, 0.2).
				SET velocityArrow:VECUPDATER TO {RETURN VXCL(SHIP:UP:VECTOR, VELOCITY:SURFACE):NORMALIZED * 10.}.

				SET aimingArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, GREEN, "Aiming", 1.0, aimTarget, 0.2).
				SET aimingArrow:VECUPDATER TO {RETURN VXCL(SHIP:UP:VECTOR, -SHIP:FACING:VECTOR):NORMALIZED * 10.}.
			}

			// set the pitch PID setpoint to the vertical speed that descends to 5000 meters with 60 seconds to spare.
			SET pitchPID:SETPOINT TO -(aboveGround - 5000) / (timeToHSpeedZero + 60).
			// ensure that the speed setpoint is at most -5 m/s.
			SET pitchPID:SETPOINT TO MIN( pitchPID:SETPOINT, -5).
			advanceMode().
		}
	}
	// Mode 2 - Maintain vertical speed setpoint by varying pitch while aiming at the landing zone
	IF (mode = 2) {
		PRINT "VSpeed SP = " + ROUND(pitchPID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "SrfVel Pitch > 20" AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "SrfVel Pitch " + ROUND(velocityPitch, 2) + "      " AT (40, 4).
		SET pitchValue TO pitchPID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF (aimTarget AND HASTARGET AND (TARGET:POSITION:MAG < oldDistance)) {
			SET headingValue TO 180 + 4 * yaw_vector(VELOCITY:SURFACE) - 3 * yaw_vector(TARGET:POSITION).
			SET oldDistance TO TARGET:POSITION:MAG.
		} ELSE SET headingValue TO yaw_vector(-VELOCITY:SURFACE).
		SET mySteer TO HEADING ( headingValue, pitchValue).
		IF velocityPitch > 20 {
			SET coastDistance TO GROUNDSPEED * 100.
			advanceMode().
		}
	}
	// Mode 3 - Maintain Vertical Speed at setpoint (varying throttle) until
	// close to above the landing zone OR getting farther from the landing zone.
	IF (mode = 3)
	{
		PRINT "VSpeed SP = " + ROUND(T_PID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "Land Dist < " + ROUND(coastDistance) + "  " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "Land Dist: " + ROUND(VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):MAG) + "    " AT (40, 4).
		SET T_PID:SETPOINT TO -aboveGround/180.
		SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		SET mySteer TO HEADING (0, 90).
		IF ((flatSpotDistance < coastDistance) OR (flatSpotDistance > flatSpotDistancePrev) OR (NOT aimTarget)) advanceMode().
	}
	// Mode 4 - Maintain Vertical Speed at setpoint until height above ground is less than 5 meters
	// Note that the steering is limited to a pitch of 70 degrees at minimum. This cancels the last horizontal velocity
	IF mode = 4 {
		PRINT "VSpeed SP = " + ROUND(T_PID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "AGL < 5        " AT (40, 4).
		IF (aboveGround > 10000) SET T_PID:SETPOINT TO -200.
		ELSE IF (aboveGround > 5000) SET T_PID:SETPOINT TO -75.
		ELSE IF (aboveGround > 1000) SET T_PID:SETPOINT TO -25.
		ELSE IF (aboveGround > 100) SET T_PID:SETPOINT TO -10.
		ELSE IF (aboveGround > 25) SET T_PID:SETPOINT TO -1.
		ELSE IF (aboveGround < 5) advanceMode().
		SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF GROUNDSPEED < 0.1 SET mySteer TO HEADING (0, 90).
		ELSE SET mySteer TO HEADING (yaw_vector(-VELOCITY:SURFACE), MAX(70, velocityPitch)).
		GEAR ON.
		LIGHTS ON.
	}
	// Mode 5 - Vertical Drop to the ground - use RCS for stabilization
	IF mode = 5 {
		RCS ON.
		SET KUNIVERSE:TIMEWARP:WARP TO 0.
		PRINT "Vertical Drop    " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "       " AT (40, 2).
		PRINT "SrfSpd " + ROUND(VELOCITY:SURFACE:MAG, 3) + "     " AT (40, 3).
		PRINT "SrfSpd < 0.5     " AT (40, 4).
		SET myThrottle TO 0.
		SET mySteer TO SHIP:UP.
		IF (VELOCITY:SURFACE:MAG < 0.5) advanceMode().
	}
	WAIT 0.
}

SET useMySteer TO FALSE.
SET useMyThrottle TO FALSE.

WAIT 10.

endScript().

RCS OFF.
LADDERS ON.

IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Landed on the " + SHIP:BODY:NAME + " " + ROUND( flatSpot:POSITION:MAG) + " meters away from the target".
ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
