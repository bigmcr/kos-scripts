@LAZYGLOBAL OFF.

PARAMETER finalInclination IS 0.			// The desired final inclination of the orbit
PARAMETER delayForEngines IS TRUE.			// whether or not to delay for engines to spool up before launch
											// if enabled, stages the hold-down clamps and SRBs after LF engines have reached full thrust
PARAMETER gravTurnAngleEnd IS 10.			// The final angle of the end of the gravity turn
PARAMETER gravTurnEnd IS 150000.			// The altitude of the end of the gravity turn
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the initial stage
PARAMETER maxGs IS 2.						// maximum number of local g's that the ship should go under

LOCAL launchAzimuth IS desiredAzimuth(gravTurnEnd, finalInclination).

IF finalInclination < 0 SET finalInclination TO ABS(finalInclination).

LOCAL mode IS 0.
// Mode 0 - Prelaunch - may add pauses for orbital alignments later
// Mode 1 - Vertical climb
// Mode 2 - Burn horizontal only

LOCAL yawValue IS 0.						// yaw adjustment factor for inclination tuning
LOCAL PITCH_PID IS PIDLOOP(1, 0.5, 0.1).	// PID loop to control pitch
LOCAL gravTurnStart TO 1000.				// The altitude of the start of the gravity turn
LOCAL gravTurnExponent TO 0.740740741.		// The exponent used in the calculation of the gravity turn
LOCAL endMessage IS "Blank".				// Used to determine the reason for exiting the loop
LOCAL pitchSetpoint IS 90.

LOCAL body_g IS CONSTANT:G * SHIP:BODY:MASS/(SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad

SET globalSteer TO SHIP:UP.						// Direction for cooked steering
SET globalThrottle TO 1.0.

setLockedThrottle(TRUE).
setLockedSteering(TRUE).

CLEARSCREEN.

SAS OFF.
RCS OFF.

// when the periapsis gets above ground, set timewarp back to normal
WHEN PERIAPSIS > 0 AND physicsWarpPerm THEN {
	SET KUNIVERSE:timewarp:warp to 0.
}

LOCAL modeStartYaw TO launchAzimuth.

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

	// Vertical climb
	IF mode = 1 {
		PRINT "Vertical     " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		GEAR OFF.
		LADDERS OFF.
		LIGHTS OFF.
		IF SHIP:BODY:ATM:EXISTS {
			PANELS OFF.
			RADIATORS OFF.
		}
	}

	// Horizontal flight
	IF mode = 2 {
		PRINT "Horizontal   " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		SET modeStartYaw TO launchAzimuth.
	}

	// Maintain vertical speed
	IF mode = 3 {
		PRINT "V Speed      " AT (40, 1).
		PRINT "Setpoint = " + ROUND(PITCH_PID:SETPOINT) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).
		SET PITCH_PID:MAXOUTPUT TO 45.
		SET PITCH_PID:MINOUTPUT TO 0.
		activateOmniAntennae().
	}

	RETURN TRUE.
}

UNTIL mode > 3 {
	engineInfo(0, 20, TRUE).
	// Prelaunch - stage the LF engines
	IF mode = 0 {
		IF initialStage {PRINT "Initial Stage!". stageFunction().}
		SET mode TO 1.
	}
	
	// Vertical climb
	IF mode = 1 {
		SET globalSteer TO HEADING(0, 90).
		// If there is no atmosphere on this body, start the grav turn more quickly
		IF ALT:RADAR > 100 {
			SET mode TO 2.
			// If allowed, set physics warp to the maximum value
			IF physicsWarpPerm {
				SET KUNIVERSE:timewarp:mode TO "PHYSICS".
				SET KUNIVERSE:timewarp:warp TO physicsWarpPerm.
			}
		}
	}
	
	// there are several things that apply to all of the "in flight" modes
	IF (mode >= 2) {
		IF debug {
			PRINT "Pitch Setpoint " + ROUND (pitchSetpoint, 2) + "    " AT(0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + "    " AT (0, 6).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) + "    " AT (0, 7).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"], 4) + " m/s^2    " AT (0, 8).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"], 4) + " m/s^2    " AT (0, 9).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"]/body_g, 4) + " g's      " AT (0, 10).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"]/body_g, 4) + " g's      " AT (0, 11).
		}
		
		// attempt at calculating the throttle to ensure maxGs acceleration at most
		// note that maxGs is relative to sea level on THIS BODY, not Earth/Kerbin.
		// desired throttle = (maxGs + body_g - accel from SRBs)/available accel from variable engines
		IF (shipInfo["Maximum"]["Variable"]["Accel"] <> 0) {
			SET globalThrottle TO ((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]).
		} ELSE SET globalThrottle TO 1.
//		SET globalThrottle TO (maxGs * body_g) / shipInfo["Maximum"]["Accel"].
		SET globalThrottle TO MIN( MAX( globalThrottle, 0.05), 1.0).

		logPhysics("0:" + SHIP:NAME + " VacLaunch Physics.csv").

		// Engine staging
		// this should drop any LF main stage and allow the final orbiter to take off
		IF (MAXTHRUST = 0) {
			PRINT "Staging from max thrust".
			IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
			ELSE stageFunction().
		}
		
		// this should drop any boosters
		LOCAL myVariable TO LIST().
		LIST ENGINES IN myVariable.
		FOR eng IN myVariable {
			IF eng:FLAMEOUT AND eng:IGNITION {
				PRINT "Staging from flameout".
				IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
				ELSE stageFunction().
				BREAK.
			}
		}
		
		IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
			PRINT "Staging from resources".
			stageFunction().
		}

		// Horizontal flight
		IF mode = 2 {
			IF ALT:RADAR > 250 SET pitchSetpoint TO 80.
			IF ALT:RADAR > 1000 SET pitchSetpoint TO 60.
			IF ALT:RADAR > 2500 SET pitchSetpoint TO 40.
			IF ALT:RADAR > 5000 SET pitchSetpoint TO 20.
			IF ALT:RADAR > 7500 SET mode TO 3.

			// This needs to be updated every scan to keep the pitch at 0 as the craft moves around the planet
			SET globalSteer TO HEADING(modeStartYaw, pitchSetpoint).
		}
		
		// Maintain vertical speed
		IF mode = 3 {
			SET PITCH_PID:SETPOINT TO 0.
			LOCAL pitchValue IS PITCH_PID:UPDATE( TIME:SECONDS, VERTICALSPEED).

			SET globalSteer TO HEADING (modeStartYaw, pitchValue).
		}

		// when any of the following conditions are met, kill the engine and stop the program
		// current orbital velocity is greater than the orbital velocity for a circular orbit at this altitude
		// periapsis is within 1 km of current altitude (burn is complete)
		// apoapsis is greater than 10 minutes away AND periapsis is greater than 10 minutes away
		//		AND altitude is greater than 100,000 meters AND vertical speed is positive
		IF (SHIP:VELOCITY:ORBIT:SQRMAGNITUDE*0.999 > SHIP:BODY:MU/(ALTITUDE + SHIP:BODY:RADIUS)) {
			SET endMessage TO "Final orbital velocity met".
			SET mode TO 7.
		}
		IF (PERIAPSIS > ALTITUDE - 1000) {
			SET endMessage TO "Peri > Alt - 1km".
			SET mode TO 7.
		}
		IF (ETA:APOAPSIS > 10*60 AND ETA:PERIAPSIS > 10*60 AND ALTITUDE > SHIP:BODY:ATM:HEIGHT AND VERTICALSPEED > 0) {
			SET endMessage TO "Complicated exit".
			SET mode to 7.
		}
	}
}
SET globalThrottle TO 0.0.

setLockedThrottle(FALSE).
setLockedSteering(FALSE).

SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
WAIT 0.1.
SET SHIP:CONTROL:MAINTHROTTLE TO 0.
SET loopMessage TO endMessage.
activateOmniAntennae().