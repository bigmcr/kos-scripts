@LAZYGLOBAL OFF.

PARAMETER coastToApo IS FALSE.				// Whether or not to turn off the main engine once desired apoapsis has been achieved
PARAMETER finalInclination IS 0.			// The desired final inclination of the orbit
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the initial stage

LOCAL launchAzimuth IS desiredAzimuth(SHIP:BODY:ATM:HEIGHT + 30000, finalInclination).

IF finalInclination < 0 SET finalInclination TO 180 + finalInclination.

LOCAL mode IS 0.
// Mode 0 - Prelaunch - may add pauses for orbital alignments later
// Mode 2 - Vertical climb
// Mode 3 - 
// Mode 3 - Roll East
// Mode 4 - Gravity turn
// Mode 5 - Burn horizontal only
// Mode 6 - Maintain vertical speed of 0 m/s

LOCAL PITCH_PID IS PIDLOOP(1, 0.5, 0.1).	// PID loop to control pitch
LOCAL YAW_PID IS PIDLOOP(1, 0.1, 50).		// PID loop to control yaw
LOCAL gravTurnStart TO 1000.				// The altitude of the start of the gravity turn
LOCAL gravTurnExponent TO 0.740740741.		// The exponent used in the calculation of the gravity turn
LOCAL endMessage IS "Blank".				// Used to determine the reason for exiting the loop
LOCAL YAW_PID_RESET IS FALSE.				// Turned TRUE when the Yaw PID has been reset

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad

SET mySteer TO SHIP:UP.						// Direction for cooked steering
SET myThrottle TO 1.0.

SET useMyThrottle TO TRUE.
SET useMySteer TO TRUE.

CLEARSCREEN.

// 90% of the way through the atmosphere is high enough that the antennae shouldn't break
WHEN ALTITUDE > MIN(140000, gravTurnEnd * 0.9) THEN {PANELS ON. activateAntenna().}

// when the periapsis gets above ground, set timewarp back to normal
WHEN PERIAPSIS > 0 AND physicsWarpPerm THEN {
	SET KUNIVERSE:timewarp:warp to 0.
}

LOCAL modeStartYaw TO 90.

// whenever the mode changes, initialize things for the new mode.
ON mode {
	CLEARSCREEN.
	
	PRINT "Mode: " + mode AT (40, 0).

	// Prelaunch - stage the LF engines
	IF mode = 0 {
		PRINT "Prelaunch    " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Liquid Fuel ramp up
	IF mode = 1 {
		PRINT "Engine Ramp  " AT (40, 1).
		PRINT "Until 85% T  " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Vertical climb
	IF mode = 2 {
		PRINT "Vertical     " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Roll, continue climb
	IF mode = 3 {
		PRINT "Roll         " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		GEAR OFF.
	}

	// Gravity turn
	IF mode = 4 {
		PRINT "Gravity Turn " AT (40, 1).
		PRINT "Start at " + ROUND(gravTurnStart) + "   " AT (40, 2).
		PRINT "End at " + ROUND(gravTurnEnd, 0) + " " AT (40, 3).
	}
	
	// Horizontal flight
	IF mode = 5 {
		PRINT "Horizontal   " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		SET modeStartYaw TO yaw_for(SHIP).
	}

	// Maintain vertical speed
	IF mode = 6 {
		PRINT "V Speed      " AT (40, 1).
		PRINT "Setpoint = " + ROUND(PITCH_PID:SETPOINT) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	RETURN TRUE.
}

UNTIL mode > 6 {
	// Prelaunch - stage the LF engines
	IF mode = 0 {
		IF initialStage {PRINT "Initial Stage!". stageFunction().}
		SET mode TO 2.
	}
	
	// Vertical climb
	IF mode = 2 {
		SET mySteer TO HEADING(0, 90).
		IF ALT:RADAR > 100 {
			// If there is no atmosphere on this body, start the grav turn more quickly
			IF NOT SHIP:BODY:ATM:EXISTS SET mode TO 4.
			ELSE SET mode TO 3.

			// If allowed, set physics warp to the maximum value
			IF physicsWarpPerm {
				SET KUNIVERSE:timewarp:mode TO "PHYSICS".
				SET KUNIVERSE:timewarp:warp TO physicsWarpPerm.
			}
		}
	}
	
	// Roll, continue climb
	IF mode = 3 {
		SET mySteer TO HEADING(launchAzimuth,90).
		IF ALT:RADAR > 1000 {
			SET mode TO 4.
			SET gravTurnStart TO ALTITUDE.
			PITCH_PID:RESET().
			SET PITCH_PID:MAXOUTPUT TO maxAOA.
			SET PITCH_PID:MINOUTPUT TO -maxAOA.
		}
	}
	
	// there are several things that apply to all of the "in flight" modes
	IF (mode >= 4) {
		IF debug {
			PRINT "Pitch Setpoint " + ROUND ( PITCH_PID:SETPOINT, 2) + "    " AT(0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + "    " AT (0, 6).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) + "    " AT (0, 7).
			PRINT "Yaw PID Setpoint " + ROUND(YAW_PID:SETPOINT, 4) + "    " AT (0, 8).
			PRINT "Yaw PID Input " + ROUND(SHIP:ORBIT:INCLINATION, 4) + "    " AT (0, 9).
			PRINT "Facing Yaw " + ROUND(yaw_for(SHIP), 2) + "    " AT (0, 10).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"], 4) + " m/s^2    " AT (0, 11).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"], 4) + " m/s^2    " AT (0, 12).
			engineInfo(0, 20, TRUE).
		}
		updateShipInfoResources().
		updateShipInfoCurrent(FALSE, FALSE).//TRUE,TRUE).
		
		// attempt at calculating the throttle to ensure maxGs acceleration at most
		IF (shipInfo["Maximum"]["Accel"] <> 0) SET myThrottle TO maxGs * g_0 / shipInfo["Maximum"]["Accel"].
		SET myThrottle TO MIN( MAX( myThrottle, 0.05), 1.0).

		// Engine staging
		// this should drop any LF main stage and allow the final orbiter to take off
		IF (MAXTHRUST = 0) {PRINT "Staging from max thrust". stageFunction().}
		
		// this should drop any boosters
		LOCAL myVariable TO LIST().
		LIST ENGINES IN myVariable.
		FOR eng IN myVariable {
			IF eng:FLAMEOUT AND eng:IGNITION {
				PRINT "Staging from flameout".
				stageFunction(). BREAK.
			}
		}
		
		IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
			PRINT "Staging from resources".
			stageFunction().
		}

		// Gravity turn
		// Note that this gravity turn uses a PID to maintain the prograde vector at the correct pitch
		IF mode = 4 {
			SET PITCH_PID:SETPOINT TO gravityTurn(gravTurnStart, gravTurnEnd, 90, gravTurnAngleEnd, gravTurnExponent).
			LOCAL pitchValue IS gravityTurn(gravTurnStart, gravTurnEnd, 90, gravTurnAngleEnd, gravTurnExponent) + PITCH_PID:UPDATE( TIME:SECONDS, 90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)).
			
			// Start off the gravity turn going the direction given, then follow the current heading
			SET mySteer TO HEADING (launchAzimuth, pitchValue).
			// when the gravity turn is done, start burning strictly horizontal and let the vertical speed drop
			IF ALTITUDE > gravTurnEnd {
				SET mode TO 5.
				YAW_PID:RESET().
				SET YAW_PID:MAXOUTPUT TO 10.
				SET YAW_PID:MINOUTPUT TO -YAW_PID:MAXOUTPUT.
				SET YAW_PID:SETPOINT TO finalInclination.
			}
		}
		
		IF (mode >= 5) {
			LOCAL yawValue IS 0.
			IF (SHIP:GEOPOSITION:LAT > 0.0) SET yawValue TO -YAW_PID:UPDATE( TIME:SECONDS, SHIP:ORBIT:INCLINATION).
			IF (SHIP:GEOPOSITION:LAT < 0.0) SET yawValue TO YAW_PID:UPDATE( TIME:SECONDS, SHIP:ORBIT:INCLINATION).
			IF (ABS(SHIP:GEOPOSITION:LAT) > ABS(YAW_PID:SETPOINT)) SET yawValue TO 0.
			
			logPID(YAW_PID, "GravTurnLaunch Yaw PID.csv").
			
			// Horizontal flight
			IF mode = 5 {
				// This needs to be updated every scan to keep the pitch at 0 as the craft moves around the planet
				SET mySteer TO HEADING(modeStartYaw + yawValue, 0).

				IF YAW_PID:ERROR < 0.25 AND NOT YAW_PID_RESET {YAW_PID:RESET(). SET YAW_PID_RESET TO TRUE.}
				
				// when vertical speed is below 0.5 m/s, start controlling pitch to maintain 0 vertical speed
				IF VERTICALSPEED < 0.5 {
					PITCH_PID:RESET().
					SET PITCH_PID:SETPOINT TO 0.
					SET PITCH_PID:MAXOUTPUT TO 45.
					SET PITCH_PID:MINOUTPUT TO -PITCH_PID:MAXOUTPUT.
					SET mode to 6.
				}
			}
			
			// Maintain vertical speed
			IF mode = 6 {
				LOCAL pitchValue IS PITCH_PID:UPDATE( TIME:SECONDS, VERTICALSPEED).

				SET mySteer TO HEADING (modeStartYaw + yawValue, pitchValue).
			}

			// when any of the following conditions are met, kill the engine and stop the program
			// current orbital velocity is greater than the orbital velocity for a circular orbit at this altitude
			// periapsis is within 1 km of current altitude (burn is complete)
			// apoapsis is greater than 10 minutes away AND periapsis is greater than 10 minutes away
			//		AND altitude is greater than 100,000 meters AND vertical speed is positive
			IF (SHIP:VELOCITY:ORBIT:SQRMAGNITUDE*0.99 > SHIP:BODY:MU/(ALTITUDE + SHIP:BODY:RADIUS)) {
				SET endMessage TO "Final orbital velocity met".
				SET mode TO 7.
			}
			IF (PERIAPSIS > ALTITUDE - 1000) {
				SET endMessage TO "Peri > Alt - 1km".
				SET mode TO 7.
			}
			IF (ETA:APOAPSIS > 10*60 AND ETA:PERIAPSIS > 10*60 AND ALTITUDE > 100000 AND VERTICALSPEED > 0) {
				SET endMessage TO "Complicated exit".
				SET mode to 7.
			}
		}
	}
}
SET myThrottle TO 0.0.

SET useMyThrottle TO FALSE.
SET useMySteer TO FALSE.

SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
WAIT 0.1.
SET SHIP:CONTROL:MAINTHROTTLE TO 0.
SET loopMessage TO endMessage.
