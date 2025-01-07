@LAZYGLOBAL OFF.

PARAMETER aimTarget IS HASTARGET.

CLEARSCREEN.

// This landing script uses multiple modes:
// Mode 1 - Pure surface retrograde for 10 seconds
// Mode 2 - Vertical Speed Setpoint

LOCAL v_i IS GROUNDSPEED.
LOCAL v_e IS shipInfo["CurrentStage"]["Isp"] * g_0.
LOCAL m_i IS SHIP:MASS * 1000.
LOCAL m_dot IS shipInfo["Maximum"]["mDot"].
LOCAL t IS burnTime(m_i, m_dot, v_i, v_e).
// Let's overestimate the landing distance by 15%
LOCAL approxLandingDistance IS 1.15 * burnDistance(0, 0, v_e, m_i, m_dot, t).

IF HASTARGET {
	// If you are already in a parking orbit, warp until the correct distance away from the target.
	IF (APOAPSIS - PERIAPSIS) < 10000 {
		PRINT "Warping until " + distanceToString(approxLandingDistance) + " from target.".
		LOCAL dist IS MAX(greatCircleDistance(SHIP:GEOPOSITION, TARGET:GEOPOSITION) - approxLandingDistance, 0).
		warpToTime(SHIP:ORBIT:PERIOD * dist / (SHIP:BODY:RADIUS * 2 * CONSTANT:PI) + TIME:SECONDS).
	}
}
PANELS OFF.
RADIATORS OFF.


LOCAL pitchPID IS PIDLOOP(1, 0.1, 0, 0, 75).						// PID loop to control pitch
LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0.05, 1).					// PID loop to control trottle during vertical descent phase

LOCAL oldTime IS ROUND( TIME:SECONDS, 1).
LOCAL oldVSpeed IS 0.
LOCAL oldHSpeed IS 0.
LOCAL oldDistance IS SHIP:BODY:RADIUS.
LOCAL velocityPitch IS pitch_for(-VELOCITY:SURFACE).
LOCAL hAccel IS 0.
LOCAL vAccel IS 0.
LOCAL timeToHSpeedZero IS 9999999.
LOCAL timeToVSpeedZero IS 9999999.
LOCAL aboveGround IS heightAboveGround().
LOCAL minPitch IS 45.
LOCAL mode TO 0.

SET globalSteer TO -VELOCITY:SURFACE.
SET globalThrottle TO 0.

setLockedSteering(TRUE).
setLockedThrottle(TRUE).
SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.

IF NOT isStockRockets() {
	PRINT "Ullage RCS burn starting".
	RCS ON.
	SET SHIP:CONTROL:FORE TO 1.
	WAIT 10.
	SET SHIP:CONTROL:FORE TO 0.
	RCS OFF.
}

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

SET globalThrottle TO 1.

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
LOCAL flatSpotArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, YELLOW, "Flat Spot", 1.0, FALSE, 0.2).
LOCAL loggingStarted IS FALSE.
LOCAL downslopeInfo IS findDownSlopeInfo().

UNTIL mode > 4 {
	updateShipInfoCurrent(FALSE).
	// This drops any empty fuel tanks
	IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
		PRINT "Staging from resources".
		IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
		ELSE stageFunction().
	}

	PRINT "Mode " + mode AT (40, 0).
	SET aboveGround TO heightAboveGround().
	SET velocityPitch TO pitch_for(-VELOCITY:SURFACE).
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
		SET globalSteer TO -VELOCITY:SURFACE.
		IF (timerStartTime = 0) SET timerStartTime TO TIME:SECONDS.
		IF (TIME:SECONDS > timerStartTime + 10) {
			pitchPID:UPDATE(TIME:SECONDS, VERTICALSPEED).
			SET pitchPID:SETPOINT TO (heightPrediction(timeToHSpeedZero)["max"] + 500 - ALTITUDE) / 600.
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
			SET pitchPID:SETPOINT TO (heightPrediction(timeToHSpeedZero)["max"] + 500 - ALTITUDE) / 600.
			SET timerStartTime TO TIME:SECONDS.
		}
		SET pitchValue TO pitchPID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF (aimTarget AND HASTARGET AND (TARGET:POSITION:MAG < oldDistance)) {
			SET headingValue TO 180 + 4 * yaw_for(VELOCITY:SURFACE) - 3 * yaw_for(TARGET:POSITION).
			SET oldDistance TO TARGET:POSITION:MAG.
		} ELSE SET headingValue TO yaw_for(-VELOCITY:SURFACE).
		SET globalSteer TO HEADING (headingValue, pitchValue).
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

				SET flatSpotArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, YELLOW, "Flat Spot", 1.0, TRUE, 0.2).
				SET flatSpotArrow:VECUPDATER TO {RETURN flatSpot:POSITION.}.
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
		SET pitchPID:SETPOINT TO (heightPrediction(timeToHSpeedZero)["max"] + 500 - ALTITUDE) / 600.
		SET pitchValue TO pitchPID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF (aimTarget AND HASTARGET AND (TARGET:POSITION:MAG < oldDistance)) {
			SET headingValue TO 180 + 4 * yaw_for(VELOCITY:SURFACE) - 3 * yaw_for(TARGET:POSITION).
			SET oldDistance TO TARGET:POSITION:MAG.
		} ELSE SET headingValue TO yaw_for(-VELOCITY:SURFACE).
		SET globalSteer TO HEADING ( headingValue, pitchValue).
		IF velocityPitch > 20 {
			LOCAL v_i_2 IS GROUNDSPEED.
			LOCAL v_e IS shipInfo["CurrentStage"]["Isp"] * g_0.
			LOCAL m_i IS SHIP:MASS * 1000.
			// Assume we are at 50% throttle and pitching over at minPitch degrees.
			// This calculates the "horizontal m_dot", if there is such a thing.
			LOCAL m_dot IS 0.5 * COS(velocityPitch) * shipInfo["Maximum"]["mDot"].
			LOCAL t IS burnTime(m_i, m_dot, v_i_2, v_e).
			// Let's overestimate the landing distance by 20%
			SET coastDistance TO 1.2 * burnDistance(0, 0, v_e, m_i, m_dot, t).
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
		SET globalThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		SET globalSteer TO HEADING (0, 90).
		IF ((flatSpotDistance < coastDistance) OR (flatSpotDistance > flatSpotDistancePrev) OR (NOT aimTarget)) advanceMode().
	}
	// Mode 4 - Burn surface retrograde until only 5% of initial speed remains.
	IF (mode = 4)
	{
		PRINT "Ground Speed = " + distanceToString(GROUNDSPEED) + "    " AT (40, 1).
		PRINT "Ground Speed < " + distanceToString(0.05 * v_i) + "  " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "Land Dist: " + ROUND(VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):MAG) + "    " AT (40, 4).
		SET T_PID:SETPOINT TO -aboveGround/180.
		SET globalThrottle TO 1.//T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		SET globalSteer TO -VELOCITY:SURFACE.
		IF (GROUNDSPEED < 0.05 * v_i) advanceMode().
	}
	// Mode 5 - Suicide burn to the ground
	IF mode = 5 {
		PRINT "VSpeed SP = " + ROUND(T_PID:SETPOINT, 2) + "    " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "        " AT (40, 2).
		PRINT "               " AT (40, 3).
		PRINT "AGL < 5        " AT (40, 4).
		RUNONCEPATH("Suicide Burn").
		SET mode TO 6.
	}
	WAIT 0.
}

SET globalSteer TO SHIP:FACING.
SET globalThrottle TO 0.

WAIT 10.

RCS OFF.
LADDERS ON.

IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Landed on the " + SHIP:BODY:NAME + " " + ROUND( flatSpot:POSITION:MAG) + " meters away from the target".
ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
