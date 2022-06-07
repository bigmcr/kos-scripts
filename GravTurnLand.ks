PARAMETER ullage IS 7.									// the number of seconds the RCS thrusters need to be firing forward for ullage concerns

CLEARSCREEN.

LOCAL mode IS 0.
// Mode 0 - Maintain Vertical Speed at 0 m/s until horizontal speed is 30% of initial
// Mode 1 - Maintain Vertical Speed at -50 m/s until horizontal speed is 5% of initial
// Mode 3 - Suicide Burn until vertical speed is -10 m/s
// Mode 4 - Maintain Vertical Speed at setpoint until height above ground is less than 10 meters
// Mode 5 - Drop to the surface and use RCS to stabilize

LOCAL pitchPID IS PIDLOOP(10, 1, 0, 0, 70).				// PID loop to control pitch
LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0.11, 1).			// PID loop to control trottle during vertical descent phase

LOCAL timeToGround IS 10.								// seconds until contact with the ground
LOCAL aboveGround IS heightAboveGround().				// current height above ground, in meters
LOCAL timeToSuicideBurn IS SuicideBurnCountdown(50).	// current time to suicide burn, in seconds
LOCAL minThrottle TO 0.11.

SET initialSpeed TO GROUNDSPEED.

SET pitchPID:SETPOINT TO 0.

// Once we have lost 70% of the initial horizontal speed, lower the vertical speed setpoint
WHEN GROUNDSPEED < initialSpeed * 0.30 THEN {
	SET mode TO 1.
	SET pitchPID:SETPOINT TO -50.

	// Once total surface velocity is less than 5% of the initial horizontal speed, wait for the suicide burn
	WHEN GROUNDSPEED < initialSpeed * 0.05 THEN {
		SET mode TO 3.

		// Once the countdown to the suicide burn is 0, start the burn
//		WHEN timeToSuicideBurn < 0.1 THEN {
			SET mode TO 3.

			// once the suicide burn is mostly over (less than 10 m/s of vertical velocity), switch to the constant speed descent
			WHEN VELOCITY:SURFACE:MAG < 10 THEN {
				SET mode TO 4.
				SET T_PID:SETPOINT TO -10.
				GEAR ON.

				IF aboveGround < 100 SET T_PID:SETPOINT TO -2.

				// when the ship is 10 meters above the ground, drop to the surface.
				WHEN aboveGround < 10 THEN {
					SET mode TO 5.

					// when the surface velocity is gone, exit the program
					WHEN VELOCITY:SURFACE:MAG < 0.1 THEN {
						SET mode TO 6.
					}
				}
			}
//		}
	}
}

// If allowed, set physics warp to the maximum value
IF physicsWarpPerm {
	SET KUNIVERSE:timewarp:mode TO "PHYSICS".
	SET KUNIVERSE:timewarp:warp TO physicsWarpPerm.
}

// when we are less than 500 meters above the ground, set timewarp back to normal
WHEN aboveGround <= 500 THEN {
	SET KUNIVERSE:timewarp:warp to 0.
}

RCS ON.
SAS OFF.
SET SHIP:CONTROL:FORE TO 1.0.
IF debug PRINT "Ullage starting".
WAIT ullage.											// wait for the burn to start
IF debug PRINT "Main Engines Starting!".
SET SHIP:CONTROL:FORE TO 0.0.
RCS OFF.

SET globalThrottle TO 1.
setLockedThrottle(TRUE).

SET globalSteer TO -VELOCITY:SURFACE.
setLockedSteering(TRUE).

// Engine staging - this should drop any used stage
WHEN MAXTHRUST = 0 THEN {
	PRINT "Staging from max thrust".
	stageFunction().
}

LOG "Time,Horizontal Distance,Altitude,Height Above Ground,Mode,Vertical Speed,Horizontal Speed,TWR,Engine Burn Time,Pitch,Thrust,Mass" TO "altitude.csv".

LOCAL oldTime IS ROUND(TIME:SECONDS, 1).
LOCAL thrust IS 0.
LOCAL startPosition IS SHIP:GEOPOSITION.
LOCAL suicideBurnActive IS FALSE.

UNTIL mode > 5 {
	updateShipInfoCurrent().
//	SET timeToSuicideBurn TO SuicideBurnCountdown(50).
	SET aboveGround TO heightAboveGround().
	SET thrust TO shipInfo["Current"]["Thrust"].
	IF (VERTICALSPEED < 0) SET timeToGround TO aboveGround / ABS(VERTICALSPEED).
	PRINT "Mode: " + mode AT (40, 0).

	IF (ROUND(TIME:SECONDS, 1) <> oldTime) {
		LOCAL message IS "".
		SET message TO message + missionTime.
		SET message TO message + "," + greatCircleDistance(startPosition).
		SET message TO message + "," + ALTITUDE.
		SET message TO message + "," + aboveGround.
		SET message TO message + "," + mode.
		SET message TO message + "," + VERTICALSPEED.
		SET message TO message + "," + GROUNDSPEED.
		SET message TO message + "," + shipInfo["Current"]["TWR"].
		SET message TO message + "," + shipInfo["Current"]["burnTime"].
		SET message TO message + "," + pitch_for(SHIP).
		SET message TO message + "," + thrust.
		SET message TO message + "," + MASS * 1000.
//		SET message TO message + "," + timeToSuicideBurn.
		LOG message TO "altitude.csv".
		SET oldTime TO ROUND(TIME:SECONDS, 1).
	}

	// Mode 0 - Maintain Vertical Velocity at 0 m/s until horizontal speed is 30% of initial
	IF mode = 0 {
		PRINT "VSpeed SP = 0" AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "HSpd <= " + ROUND(initialSpeed * 0.30) + "  " AT (40, 4).
		LOCAL pitchValue IS pitchPID:UPDATE( TIME:SECONDS, VERTICALSPEED).

		// make the heading the same direction as surface retrograde
		SET globalSteer TO HEADING (yaw_for(-VELOCITY:SURFACE), pitchValue).
		IF debug {LOGPID(pitchPID, "GravTurnLandPitchPID.csv", TRUE).}
	}

	// Mode 1 - Maintain Vertical Velocity at -50 m/s until horizontal speed is 5% of initial
	IF mode = 1 {
		PRINT "VSpeed SP " + ROUND(pitchPID:SETPOINT, 0) AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "HSpd <= " + ROUND(initialSpeed * 0.05) + "  " AT (40, 4).
		LOCAL pitchValue IS pitchPID:UPDATE( TIME:SECONDS, VERTICALSPEED).
		// make the heading the same direction as surface retrograde
		SET globalSteer TO HEADING (yaw_for(-VELOCITY:SURFACE), pitchValue).
		IF debug {LOGPID(pitchPID, "GravTurnLandPitchPID.csv", TRUE).}
	}

	// Mode 2 - Wait for suicide burn
	IF mode = 2 {
		PRINT "Wait on Suicide Burn" AT (40, 1).
//		PRINT "Time to SB " + timeToString(timeToSuicideBurn) AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "ETA SB < 0.1 " AT (40, 4).
		SET throt TO minThrottle.
		SET globalSteer TO -VELOCITY:SURFACE.
	}

	// Mode 3 - Suicide Burn until vertical speed is -10 m/s
	IF mode = 3 {
		PRINT "Suicide Burn  " AT (40, 1).
		PRINT "VSrf = " + ROUND(VELOCITY:SURFACE:MAG, 0) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "VSrf < 10    " AT (40, 4).
		SET globalThrottle TO 1.
		SET globalSteer TO -VELOCITY:SURFACE.
		RUNONCEPATH("SBOnline.ks").
	}

	// Mode 4 - Maintain Vertical Speed at setpoint until height above ground is less than 10 meters
	IF mode = 4 {
		PRINT "VSpeed SP = " + T_PID:SETPOINT + "    " AT (40, 1).
		PRINT "AGL = " + ROUND(aboveGround) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).
		PRINT "AGL < 10     " AT (40, 4).
		SET globalThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF debug {LOGPID(T_PID, "GravTurnLandThrottlePID.csv", TRUE).}
		SET globalSteer TO -VELOCITY:SURFACE.
	}

	// Mode 5 - Drop to the surface and use RCS to stabilize
	IF mode = 3 {
		PRINT "Vertical Drop " AT (40, 1).
		PRINT "              " AT (40, 2).
		PRINT "              " AT (40, 3).
		PRINT "SVel <= 1.0   " AT (40, 4).
		SET globalSteer TO SHIP:UP.
		SET globalThrottle TO 0.
		RCS ON.
	}

	IF debug {
		PRINT "Initial Horizontal Speed " + ROUND( initialSpeed, 2) + " m/s    " AT(0, 5).
		PRINT "Current Vertical Speed " + ROUND( VERTICALSPEED, 2) + " m/s    " AT(0, 6).
		PRINT "Current Horizontal Speed " + ROUND( GROUNDSPEED, 2) + " m/s    " AT(0, 7).
		PRINT "Vertical Speed Setpoint " + ROUND( pitchPID:SETPOINT, 2) + " m/s    " AT(0, 8).
		PRINT "Vertical Speed " + ROUND( VERTICALSPEED, 2) + "     " AT (0, 9).
		PRINT "Height Above Ground " + ROUND( aboveGround) + " m   " AT (0, 10).
		IF (VERTICALSPEED < 0) PRINT timeToString(timeToGround) + " to ground           " AT (0, 12).
		ELSE PRINT "Not headed down at the moment       " AT (0, 12).
	}
	WAIT 0.
}

setLockedThrottle(FALSE).
setLockedSteering(FALSE).

SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
WAIT 0.1.
SET SHIP:CONTROL:MAINTHROTTLE TO 0.

WAIT 0.5.
IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Sucessfully landed on " + SHIP:BODY:NAME.
ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
