FUNCTION gravityTurn {
	PARAMETER START_HEIGHT TO 1000.
	PARAMETER END_HEIGHT TO SHIP:BODY:ATM:HEIGHT * 5/7.
	PARAMETER INITIAL_ANGLE TO 80.
	PARAMETER END_ANGLE TO 5.
	PARAMETER EXP TO 0.740740741.
	
	IF ALTITUDE < START_HEIGHT RETURN INITIAL_ANGLE.
	IF ALTITUDE > END_HEIGHT RETURN END_ANGLE.
	
	RETURN ( 1 - ( ( ALTITUDE - START_HEIGHT) / ( END_HEIGHT - START_HEIGHT) ) ^ EXP ) * ( INITIAL_ANGLE - END_ANGLE ) + END_ANGLE.
}.

PARAMETER initialStage IS TRUE.				// Whether or not to trigger the stage function to start with
PARAMETER numberOfSats IS 1.				// Number of sats being launched - used to determine the final orbital period

IF (numberOfSats < 1) SET numberOfSats TO 1.

LOCAL mode IS "Prelaunch".
// Mode 0 - Prelaunch
// Mode 1 - Vertical climb
// Mode 2 - Roll East
// Mode 3 - Gravity turn
// Mode 4 - Burn Prograde
// Mode 5 - Coast to Apoapsis
// Mode 6 - Maintain vertical speed of 0 m/s

LOCAL altitudeTarget IS 2863334.			// The desired final altitude
LOCAL launchAngle IS 0.						// The initial heading to launch at.
SET mySteer TO SHIP:UP.						// Direction for cooked steering
LOCAL PITCH_PID IS PIDLOOP(1, 0.5, 0.1).	// PID loop to control pitch
LOCAL YAW_PID IS PIDLOOP(1, 0.5, 0.1).		// PID loop to control yaw
LOCAL gravTurnStart TO 1000.				// The altitude of the start of the gravity turn
LOCAL gravTurnEnd TO 0.7 * altitudeTarget.	// The altitude of the end of the gravity turn
LOCAL gravTurnAngleEnd IS 0.				// The final angle of the end of the gravity turn
LOCAL gravTurnExponent TO 0.740740741.		// The exponent used in the calculation of the gravity turn
LOCAL endMessage IS "Blank".				// Used to determine the reason for exiting the loop

IF (SHIP:BODY:ATM:EXISTS) SET gravTurnEnd TO MIN(gravTurnEnd, SHIP:BODY:ATM:HEIGHT).

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad
SET maxAOA TO 5.							// Lower the allowable AOA for this ship

// Once we have cleared the tower, support struts, etc. set the ship to roll due east
WHEN ALT:RADAR > 100 THEN {
	// If allowed, set physics warp to the maximum value
	IF physicsWarpPerm {
		SET KUNIVERSE:timewarp:mode TO "PHYSICS".
		SET KUNIVERSE:timewarp:warp to physicsWarpPerm.
	}
	
	// 100 kilometers is high enough that the antennae doesn't break
	WHEN ALTITUDE > MIN(50000, gravTurnEnd * 0.9) THEN {
		PANELS ON.
		activateAntenna().
	
		// when the orbital period is the appropriate number, kill the engines and stop the program
		WHEN (SHIP:ORBIT:PERIOD > SHIP:BODY:ROTATIONPERIOD / numberOfSats) THEN {
			SET endMessage TO "Desired Period Met".
			SET mode TO "Complete".
		}
	}
}

// when the periapsis gets near the final altitude, set timewarp back to normal
WHEN PERIAPSIS > 2863334 * 0.95 AND physicsWarpPerm THEN {
	SET KUNIVERSE:timewarp:warp to 0.
}

LOCAL modeStartYaw TO 90.

// whenever the mode changes, initialize things for the new mode.
ON mode {
	CLEARSCREEN.
	SET modeStartYaw TO yaw_for(SHIP).
	
	PRINT "Mode: " + mode AT (40, 0).

	// Prelaunch - stage the LF engines
	IF mode = "Prelaunch" {
		PRINT "Prelaunch    " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Vertical climb
	IF mode = "climb" {
		PRINT "Vertical     " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Roll, continue climb
	IF mode = "Roll" {
		PRINT "Roll         " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		GEAR OFF.
	}

	// Gravity turn
	IF mode = "Gravity Turn" {
		PRINT "Gravity Turn " AT (40, 1).
		PRINT "Start at " + ROUND(gravTurnStart) + "   " AT (40, 2).
		PRINT "End at " + ROUND(gravTurnEnd, 0) + " " AT (40, 3).

		SET gravTurnStart TO ALTITUDE.
		PITCH_PID:RESET().
		SET PITCH_PID:MAXOUTPUT TO maxAOA.
		SET PITCH_PID:MINOUTPUT TO -maxAOA.
		
		YAW_PID:RESET().
		SET YAW_PID:MAXOUTPUT TO 10.
		SET YAW_PID:MINOUTPUT TO -10.
		SET YAW_PID:SETPOINT TO ABS(launchAngle).
	}
	
	// Horizontal flight
	IF mode = "Prograde" {
		PRINT "Maintain Apo " AT (40, 1).
		PRINT "Coast to Apo " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Maintain vertical speed
	IF mode = "Maintain V Speed" {
		PRINT "V Speed      " AT (40, 1).
		PRINT "Setpoint = " + ROUND(PITCH_PID:SETPOINT) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).

		PITCH_PID:RESET().
		SET PITCH_PID:SETPOINT TO 0.
		SET PITCH_PID:MAXOUTPUT TO 45.
		SET PITCH_PID:MINOUTPUT TO -PITCH_PID:MAXOUTPUT.
	}

	RETURN TRUE.
}

SET myThrottle TO 1.0.

UNTIL mode = "Complete" {
	// Prelaunch - stage the LF engines
	IF mode = "Prelaunch" {
		SET mode TO "Climb".
		IF initialStage stageFunction().
	}.
	
	// Vertical climb
	IF mode = "Climb" {
		SET mySteer TO HEADING(0, 90).
		SET myThrottle TO 1.0.
		
		IF ALT:RADAR > 100
			SET mode TO "Roll".
	}
	
	// Roll, continue climb
	IF mode = "Roll" {
		SET mySteer TO HEADING(90 + launchAngle,90).
		SET myThrottle TO 1.0.
		IF ALT:RADAR > 1000 {
			SET mode TO "Gravity Turn".
		}
	}
	
	// there are several things that apply to all of the "in flight" modes
	IF (mode <> "Prelaunch" AND mode <> "Climb" AND mode <> "Roll") {
		IF debug {
			PRINT "Pitch Setpoint " + ROUND ( PITCH_PID:SETPOINT, 2) AT(0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) AT (0, 6).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) AT (0, 7).
			PRINT "Yaw PID Setpoint " + ROUND(YAW_PID:SETPOINT, 4) AT (0, 8).
			PRINT "Yaw PID Input " + ROUND(SHIP:ORBIT:INCLINATION, 4) AT (0, 9).
			PRINT "Facing Yaw " + ROUND(yaw_for(SHIP), 2) AT (0, 10).
			engineInfo(0, 35, TRUE).
		}

		// Engine staging
		// this should drop any LF main stage and allow the final orbiter to take off
		IF (MAXTHRUST = 0) {PRINT "Staging from max thrust". stageFunction().}
		
		// this should drop any boosters
		FOR eng IN shipInfo["Stage " + STAGE:NUMBER]["Engines"] {
			IF eng:FLAMEOUT AND eng:IGNITION {
				PRINT "Staging from flameout".
				stageFunction(). BREAK.
			}
		}

		LOCAL yawValue IS -YAW_PID:UPDATE( TIME:SECONDS, ABS(SHIP:ORBIT:INCLINATION)).
		IF (ABS(SHIP:GEOPOSITION:LNG) > ABS(YAW_PID:SETPOINT)) SET yawValue TO 0.
		
		// Gravity turn
		// Note that this gravity turn uses a PID to maintain the prograde vector at the correct pitch
		IF mode = "Gravity Turn" {
			SET PITCH_PID:SETPOINT TO gravityTurn(gravTurnStart, gravTurnEnd, 90, gravTurnAngleEnd, gravTurnExponent).
			LOCAL pitchValue IS gravityTurn(gravTurnStart, gravTurnEnd, 90, gravTurnAngleEnd, gravTurnExponent) + PITCH_PID:UPDATE( TIME:SECONDS, 90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)).
			
			// Start off the gravity turn going the direction given, then follow the current heading
			IF ALTITUDE < 0.25 * gravTurnEnd {
				SET mySteer TO HEADING (90 + launchAngle, pitchValue).
			} ELSE {
				SET mySteer TO HEADING (90 + launchAngle + yawValue, pitchValue).
			}
			SET myThrottle TO 1.0.
			IF (ALTITUDE > gravTurnEnd) OR (APOAPSIS > altitudeTarget) SET mode TO "Prograde".
		}
		
		// Prograde until altitude is reached
		IF mode = "Prograde" {
			// This needs to be updated every scan to keep the pitch at 0 as the craft moves around the planet
			SET mySteer TO VELOCITY:ORBIT.
			IF (APOAPSIS < altitudeTarget) SET myThrottle TO 1.0.
			ELSE SET myThrottle TO 0.0.
			
			IF VERTICALSPEED < 0.5 {SET mode TO "Maintain V Speed".}
		}
		
		// Maintain vertical speed
		IF mode = "Maintain V Speed" {
			LOCAL pitchValue IS PITCH_PID:UPDATE( TIME:SECONDS, VERTICALSPEED).

			SET mySteer TO HEADING (modeStartYaw + yawValue, pitchValue).
			SET myThrottle TO 1.0.
			IF debug {
				PRINT "Pitching over to " + ROUND ( pitchValue, 2) + "    " AT(0,11).
				PRINT "V Speed: " + ROUND(VERTICALSPEED, 2) + "    " AT (0,12).
				PRINT "V Speed Target: " + ROUND(PITCH_PID:SETPOINT, 0) + "    " AT (0,13).
				PRINT "Period " + ROUND(SHIP:ORBIT:PERIOD, 0) + " s  " AT (0, 14).
				PRINT "Period SP " + ROUND(SHIP:BODY:ROTATIONPERIOD / numberOfSats, 0) + " s  " AT (0, 14).
			}
		}
	}
}.
killEngines().
endScript().
SET loopMessage TO endMessage.
