@LAZYGLOBAL OFF.

CLEARSCREEN.

// This landing script uses multiple modes:
// Mode 1 - Pure surface retrograde for 10 seconds
// Mode 2 - Vertical Speed Setpoint

LOCAL pitchValue IS 0.
LOCAL headingValue IS 90.
LOCAL startTime IS TIME:SECONDS.
LOCAL startPosition IS SHIP:GEOPOSITION.
LOCAL flatSpot IS SHIP:GEOPOSITION.
LOCAL flatSpotDistance IS 0.
LOCAL flatSpotDistancePrev IS -1.
LOCAL coastDistance IS 0.

LOCAL landingArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, BLUE, "Landing Direction", 1.0, FALSE, 0.2).
SET landingArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, BLUE, "Landing Direction", 1.0, TRUE, 0.2).
SET landingArrow:VECUPDATER TO {RETURN VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):NORMALIZED * 10.}.

LOCAL velocityArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, RED, "Velocity", 1.0, FALSE, 0.2).
SET velocityArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, RED, "Velocity", 1.0, TRUE, 0.2).
SET velocityArrow:VECUPDATER TO {RETURN VXCL(SHIP:UP:VECTOR, VELOCITY:SURFACE):NORMALIZED * 10.}.

LOCAL aimingArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, GREEN, "Aiming", 1.0, FALSE, 0.2).
SET aimingArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, GREEN, "Aiming", 1.0, TRUE, 0.2).
SET aimingArrow:VECUPDATER TO {RETURN VXCL(SHIP:UP:VECTOR, -SHIP:FACING:VECTOR):NORMALIZED * 10.}.

LOCAL flatSpotArrow IS VECDRAW(V(0,0,0), flatSpot:POSITION, YELLOW, "Flat Spot", 1.0, FALSE, 0.2).
SET flatSpotArrow TO VECDRAW(V(0,0,0), flatSpot:POSITION, YELLOW, "Flat Spot", 1.0, TRUE, 0.2).
SET flatSpotArrow:VECUPDATER TO {RETURN flatSpot:POSITION.}.

LOCAL loggingStarted IS FALSE.

LOCAL mu IS SHIP:BODY:MU.
LOCAL centripitalAccel IS VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE):SQRMAGNITUDE/(SHIP:POSITION - SHIP:BODY:POSITION):MAG.
LOCAL local_g IS mu/(SHIP:POSITION - SHIP:BODY:POSITION):SQRMAGNITUDE.
LOCAL requiredVerticalAccel IS 0.
LOCAL accelRatios IS 0.
LOCAL maxAccel IS shipInfo["Maximum"]["Accel"].
LOCAL requiredAccel IS maxAccel.

LOCAL positiveDirectionVector IS VXCL(SHIP:UP:VECTOR, -SHIP:VELOCITY:SURFACE):NORMALIZED.

LOCAL hAccelInitial IS SQRT(shipInfo["Maximum"]["Accel"]^2 - (centripitalAccel - local_g)^2).//shipInfo["Maximum"]["Accel"].
LOCAL timeElapsed IS 0.
LOCAL hSpeed IS VDOT(VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), positiveDirectionVector).
LOCAL hSpeedInitial IS hSpeed.
LOCAL hSpeedPredicted IS hSpeedInitial + hAccelInitial * timeElapsed.
LOCAL hPosition IS VDOT(flatSpot:POSITION, positiveDirectionVector).
LOCAL hPositionInitial IS hPosition.
LOCAL hPositionPredicted IS hPositionInitial + hSpeedInitial * timeElapsed + 0.5 * hAccelInitial * timeElapsed^2.

// PID loop to control trottle during horizontal speed cancellation phase
// Input is measured horizontal acceleration (m/s^2)
// Setpoint is initial max horizontal acceleration plus a velocity-based trim (m/s^2)
// Output is a trim on the throttle controls (plus or minus 0.2, no units)
// PIDLOOP(Kp, Ki, Kd, min output, max output, epsilon)
LOCAL T_PID_Accel IS PIDLOOP(0.025, 0.05, 0.0025, -0.1, 0.1, 0.001).

// PID loop to control horizontal acceleration horizontal speed cancellation phase
// Input is measured horizontal velocity
// Setpoint is calculated horizontal velocity (m/s)
// Output is desired trim on horizontal acceleration (-1 to 1 m/s^2)
// PIDLOOP(Kp, Ki, Kd, min output, max output, epsilon)
LOCAL T_PID_Vel IS PIDLOOP(0.02, 0.0005, 0.02, -0.5, 0.5, 0.05).
//LOCAL T_PID_Vel IS PIDLOOP(0.001, 0.005, 0.0, -1.0, 1.0, 1.0).

LOCAL approxLandingTime IS ABS(hSpeedInitial) / shipInfo["Maximum"]["Accel"].
LOCAL approxLandingDistance IS ABS(hSpeedInitial) * approxLandingTime + 0.5 * (-ABS(hAccelInitial)) * approxLandingTime^2.
PRINT "It will take " + timeToString(approxLandingTime) + " to zero out horizontal velocity" AT (0, 0).
PRINT "During that time, the ship will travel approximately " + distanceToString(approxLandingDistance, 3) AT (0, 1).

updateShipInfoCurrent(FALSE).

// find a flat spot near the setpoint to land. Also make arrows pointing in relevant direction.
IF HASTARGET SET flatSpot TO findMinSlope(TARGET:GEOPOSITION:POSITION, 1000, 100).
ELSE 		 SET flatSpot TO findMinSlope(SHIP:POSITION + SHIP:VELOCITY:SURFACE:NORMALIZED * approxLandingDistance, 1000, 100).
SET flatSpot TO findMinSlope(flatSpot:POSITION, 100, 10).

// If you are already in a parking orbit and there is a target, warp until the correct distance away from the target.
IF HASTARGET AND ((APOAPSIS - PERIAPSIS) < 10000) {
	PRINT "Warping until " + distanceToString(approxLandingDistance) + " from flat spot near target." AT (0, 2).
	LOCAL dist IS MAX(greatCircleDistance(SHIP:GEOPOSITION, flatSpot) - approxLandingDistance, 0).
	warpToTime(SHIP:ORBIT:PERIOD * dist / (SHIP:BODY:RADIUS * 2 * CONSTANT:PI) + TIME:SECONDS).
}
PANELS OFF.
RADIATORS OFF.

LOCAL oldTime IS -1.
LOCAL vSpeedOld IS 0.
LOCAL hSpeedOld IS 0.
LOCAL oldDistance IS SHIP:BODY:RADIUS.
LOCAL hAccel IS 0.
LOCAL vAccel IS 0.
LOCAL aboveGround IS heightAboveGround().
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

LOCAL logFileName IS "0:precision.csv".
IF connectionToKSC() {
	IF EXISTS(logFileName) DELETEPATH(logFileName).
	LOG "Initial Velocity X (Horizontal),v_x_i," + hSpeed + ",m/s" TO logFileName.
	LOG "Initial Velocity Y (Vertical),v_y_i," + VERTICALSPEED + ",m/s" TO logFileName.
	LOG "Initial Position X (Horizontal),x_x_i," + hPosition + ",m/s" TO logFileName.
	LOG "Initial Position Y (Vertical),x_y_i," + ALTITUDE + ",m/s" TO logFileName.
	LOG "Initial Mass,m_0," + shipInfo["CurrentStage"]["CurrentMass"] + ",kg" TO logFileName.
	LOG "Mass Rate of Change,m_dot," + shipInfo["Maximum"]["mDot"] + ",kg/s" TO logFileName.
	LOG "Exhaust Velocity,v_e," + (shipInfo["CurrentStage"]["Isp"] * g_0) + ",m/s" TO logFileName.
	LOG "Time,Mass,Horizontal Distance,Horizontal Distance Prediction,Horizontal Speed,Horizontal Speed Prediction,Horizontal Acceleration,Vertical Speed,Vertical Acceleration,Height Above Ground,Pitch,Distance to Flat Spot,Required Vertical Accel,Required Total Accel,Velocity PID Output,Accel PID Output,Throttle,Mode" TO logFileName.
}

UNTIL mode > 4 {
	updateShipInfoCurrent(FALSE).
	// This drops any empty fuel tanks
	IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
		PRINT "Staging from resources".
		IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
		ELSE stageFunction().
	}

	PRINT "Mode " + mode AT (40, 3).
	SET aboveGround TO heightAboveGround().
	SET positiveDirectionVector TO VXCL(SHIP:UP:VECTOR, -SHIP:VELOCITY:SURFACE):NORMALIZED.
	SET hSpeed TO VDOT(VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), positiveDirectionVector).
	SET centripitalAccel TO hSpeed^2/(SHIP:POSITION - SHIP:BODY:POSITION):MAG.
	SET local_g TO mu/(SHIP:POSITION - SHIP:BODY:POSITION):SQRMAGNITUDE.
	SET requiredVerticalAccel TO local_g - centripitalAccel - VERTICALSPEED / 10.
	IF (shipInfo["Current"]["Accel"] <> 0) SET accelRatios TO requiredVerticalAccel / shipInfo["Current"]["Accel"].
	IF accelRatios > SIN(85) SET accelRatios TO SIN(85).
	IF accelRatios < 0 SET accelRatios TO 0.
	SET maxAccel TO shipInfo["Maximum"]["Accel"].
	SET requiredAccel TO SQRT((centripitalAccel - local_g)^2 + (hAccelInitial + T_PID_Vel:OUTPUT)^2).
	SET hPosition TO VDOT(flatSpot:POSITION, positiveDirectionVector).// greatCircleDistance(SHIP:GEOPOSITION, startPosition).

	SET timeElapsed TO TIME:SECONDS - startTime.
	SET hSpeedPredicted TO hSpeedInitial + hAccelInitial * timeElapsed.
	SET hPositionPredicted TO hPositionInitial + hSpeedInitial * timeElapsed + 0.5 * hAccelInitial * timeElapsed^2.

	IF (timeElapsed <> oldTime) {
		SET hAccel TO (hSpeed - hSpeedOld)/(timeElapsed - oldTime).
		SET vAccel TO (VERTICALSPEED - vSpeedOld)/(timeElapsed - oldTime).
		SET flatSpotDistancePrev TO flatSpotDistance.
		SET flatSpotDistance TO VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):MAG.

		IF hAccel < 0 AND connectionToKSC() SET loggingStarted TO TRUE.

		PRINT "Horizontal Speed " + distanceToString(hSpeed, 2) + "/s     " AT (0, 3).
		PRINT "Horizontal Acceleration " + distanceToString(hAccel, 2) + "/s^2    " AT (0, 4).
		PRINT "Vertical Speed " + distanceToString(VERTICALSPEED, 2) + "/s    " AT (0, 5).
		PRINT "Vertical Acceleration " + distanceToString(vAccel, 2) + "/s^2    " AT (0, 6).
		PRINT "Distance to Flat Spot " + distanceToString(flatSpot:POSITION:MAG) + "       " AT (0, 7).
		PRINT "Throttle " + ROUND(globalThrottle, 4) + "       " AT (0, 8).

		PRINT "PID                  Output     Output (%)          Error" AT (0, 10).
		PRINT "Velocity    " + ROUND(T_PID_Vel:OUTPUT, 3):TOSTRING():PADLEFT(15)   + ROUND((T_PID_Vel:OUTPUT - T_PID_Vel:MINOUTPUT) * 100 / (T_PID_Vel:MAXOUTPUT - T_PID_Vel:MINOUTPUT), 3):TOSTRING():PADLEFT(15)         + ROUND(T_PID_Vel:ERROR, 3):TOSTRING():PADLEFT(15) AT (0, 11).
		PRINT "Acceleration" + ROUND(T_PID_Accel:OUTPUT, 3):TOSTRING():PADLEFT(15) + ROUND((T_PID_Accel:OUTPUT - T_PID_Accel:MINOUTPUT) * 100 / (T_PID_Accel:MAXOUTPUT - T_PID_Accel:MINOUTPUT), 3):TOSTRING():PADLEFT(15) + ROUND(T_PID_Accel:ERROR, 3):TOSTRING():PADLEFT(15) AT (0, 12).

		PRINT "            Prediction    Actual     Delta " AT (0, 15).
		PRINT "H Position  " + ROUND(hPositionPredicted, 0):TOSTRING():PADLEFT(10) + ROUND(hPosition, 0):TOSTRING():PADLEFT(10) + ROUND(hPositionPredicted - hPosition, 0):TOSTRING():PADLEFT(10) + " m       " AT (0, 16).
		PRINT "H Velocity  " + ROUND(hSpeedPredicted, 2):TOSTRING():PADLEFT(10) + ROUND(hSpeed, 2):TOSTRING():PADLEFT(10) + ROUND(hSpeedPredicted - hSpeed, 2):TOSTRING():PADLEFT(10) + " m/s      " AT (0, 17).
		PRINT "H Accel     " + ROUND(hAccelInitial, 4):TOSTRING():PADLEFT(10) + ROUND(hAccel, 4):TOSTRING():PADLEFT(10) + ROUND(hAccelInitial - hAccel, 4):TOSTRING():PADLEFT(10) + " m/s^2      " AT (0, 18).

		LOCAL message IS timeElapsed.
		SET message TO message + "," + shipInfo["CurrentStage"]["CurrentMass"].
		SET message TO message + "," + hPosition.
		SET message TO message + "," + hPositionPredicted.
		SET message TO message + "," + hSpeed.
		SET message TO message + "," + hSpeedPredicted.
		SET message TO message + "," + hAccel.
		SET message TO message + "," + VERTICALSPEED.
		SET message TO message + "," + vAccel.
		SET message TO message + "," + aboveGround.
		SET message TO message + "," + pitch_for(SHIP).
		SET message TO message + "," + flatSpotDistance.
		SET message TO message + "," + requiredVerticalAccel.
		SET message TO message + "," + requiredAccel.
		SET message TO message + "," + T_PID_Vel:OUTPUT.
		SET message TO message + "," + T_PID_Accel:OUTPUT.
		SET message TO message + "," + globalThrottle.
		SET message TO message + "," + mode.
		IF connectionToKSC() AND loggingStarted LOG message TO logFileName.

		SET hSpeedOld TO hSpeed.
		SET vSpeedOld TO VERTICALSPEED.
		SET oldTime TO timeElapsed.
	}
	// Mode 0 - Maintain vertical speed setpoint by varying pitch and throttle
	IF (mode = 0) {
		PRINT "VSpeed SP = 0    " AT (40, 4).
		PRINT "Groundspeed < 10 " AT (40, 5).
		PRINT "                 " AT (40, 6).
		PRINT "Groundspeed " + ROUND(hSpeed, 2) + "      " AT (40, 4).
		SET pitchValue TO ARCSIN(accelRatios).
		IF flatSpot:POSITION:MAG < oldDistance {
			SET headingValue TO 180 + 4 * yaw_for(VELOCITY:SURFACE) - 3 * yaw_for(flatSpot:POSITION).
			SET oldDistance TO flatSpot:POSITION:MAG.
		} ELSE SET headingValue TO yaw_for(-VELOCITY:SURFACE).
		SET globalSteer TO HEADING (headingValue, pitchValue).
		SET T_PID_Vel:SETPOINT TO hSpeedPredicted.
		T_PID_Vel:UPDATE(TIME:SECONDS, hSpeed).
		SET T_PID_Accel:SETPOINT TO hAccelInitial + T_PID_Vel:OUTPUT.
		T_PID_Accel:UPDATE( TIME:SECONDS, hAccel).
		SET globalThrottle TO MAX(MIN(requiredAccel/maxAccel + T_PID_Accel:OUTPUT, 1), 0).
		IF (ABS(hSpeed) < 1) {
			advanceMode().
		}
	}
	logPID(T_PID_Accel, "0:T_PID_Accel logfile.csv", TRUE).
	logPID(T_PID_Vel,   "0:T_PID_Vel logfile.csv", TRUE).
	// Mode 1 - Suicide burn to the ground
	IF mode = 1 {
		SET globalThrottle TO 0.
		RUNONCEPATH("SuicideBurnRK4").
		SET mode TO 6.
	}
	WAIT 0.
}

SET globalSteer TO SHIP:FACING.
SET globalThrottle TO 0.

WAIT 5.

RCS OFF.
LADDERS ON.
SET loopMessage TO "Landed on the " + SHIP:BODY:NAME + " " + ROUND( VXCL(SHIP:UP:VECTOR, flatSpot:POSITION):MAG) + " horizontal meters away from the flat spot".
//IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Landed on the " + SHIP:BODY:NAME + " " + ROUND( flatSpot:POSITION:MAG) + " meters away from the flat spot".
//ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
