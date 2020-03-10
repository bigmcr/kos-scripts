@LAZYGLOBAL OFF.

PARAMETER finalInclination IS 0.			// The desired final inclination of the orbit
PARAMETER delayForEngines IS TRUE.			// whether or not to delay for engines to spool up before launch
											// if enabled, stages the hold-down clamps and SRBs after LF engines have reached full thrust
PARAMETER gravTurnAngleEnd IS 10.			// The final angle of the end of the gravity turn
PARAMETER gravTurnEnd IS 150000.			// The altitude of the end of the gravity turn
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the initial stage
PARAMETER maxGs IS 2.						// maximum number of G's that the ship should go under

LOCAL steeringVectorsVisible IS NOT MAPVIEW.
LOCAL facingVector   IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN SHIP:FACING:VECTOR * 10.}           , RED,   "                 Facing", 1, steeringVectorsVisible).
LOCAL guidanceVector IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN STEERINGMANAGER:TARGET:VECTOR * 10.}, GREEN, "Guidance               ", 1, steeringVectorsVisible).

ON MAPVIEW {
	SET facingVector:SHOW TO NOT MAPVIEW AND NOT SHIP:CONTROL:NEUTRAL.
	SET guidanceVector:SHOW TO NOT MAPVIEW AND NOT SHIP:CONTROL:NEUTRAL.
	RETURN TRUE.
}

ON steeringVectorsVisible {
	SET facingVector:SHOW TO steeringVectorsVisible AND NOT SHIP:CONTROL:NEUTRAL.
	SET guidanceVector:SHOW TO steeringVectorsVisible AND NOT SHIP:CONTROL:NEUTRAL.
	RETURN TRUE.
}

LOCAL launchAzimuth IS desiredAzimuth(gravTurnEnd, finalInclination).

IF finalInclination < 0 SET finalInclination TO ABS(finalInclination).

LOCAL mode IS 0.
// Mode 0 - Prelaunch - may add pauses for orbital alignments later
// Mode 1 - LF rampup
// Mode 2 - Vertical climb
// Mode 3 - Roll East
// Mode 4 - Gravity turn
// Mode 5 - Burn horizontal only
// Mode 6 - Maintain vertical speed of 0 m/s

LOCAL yawValue IS 0.						// yaw adjustment factor for inclination tuning
LOCAL PITCH_PID IS PIDLOOP(0.1, 0.25, 0.5).	// PID loop to control pitch
LOCAL YAW_PID IS PIDLOOP(1, 0.1, 50).		// PID loop to control yaw
LOCAL gravTurnStart TO 1000.				// The altitude of the start of the gravity turn
LOCAL gravTurnExponent TO 0.740740741.		// The exponent used in the calculation of the gravity turn
LOCAL endMessage IS "Blank".				// Used to determine the reason for exiting the loop

LOCAL body_g IS CONSTANT:G * SHIP:BODY:MASS/(SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad

SET mySteer TO SHIP:UP.						// Direction for cooked steering
SET myThrottle TO 1.0.

SET useMyThrottle TO TRUE.
SET useMySteer TO TRUE.

CLEARSCREEN.

SAS OFF.
RCS OFF.
DEPLOYDRILLS OFF.
GEAR OFF.
LADDERS OFF.
IF SHIP:BODY:ATM:EXISTS {
	PANELS OFF.
	RADIATORS OFF.
}

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

	// Liquid Fuel ramp up
	IF mode = 1 {
		PRINT "Engine Ramp  " AT (40, 1).
		PRINT "Until 85% T  " AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Vertical climb
	IF mode = 2 {
		PRINT "Vertical     " AT (40, 1).
		PRINT "maxAOA = " + ROUND(maxAOA, 2) AT (40, 2).
		PRINT "             " AT (40, 3).
	}

	// Roll, continue climb
	IF mode = 3 {
		PRINT "Roll         " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
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
		SET modeStartYaw TO launchAzimuth.
	}

	// Maintain vertical speed
	IF mode = 6 {
		PRINT "V Speed      " AT (40, 1).
		PRINT "Setpoint = " + ROUND(PITCH_PID:SETPOINT) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).
		activateOmniAntennae().
	}

	RETURN TRUE.
}

UNTIL mode > 6 {
	engineInfo(0, 20, TRUE).
	// Prelaunch - stage the LF engines
	IF mode = 0 {
		IF initialStage {PRINT "Initial Stage!". stageFunction().}
		IF (delayForEngines) SET mode TO 1.
		ELSE SET mode TO 2.
	}

	// Engine ramp up
	IF mode = 1 {
		// if the active engines have reached full thrust, stage and switch modes
		SET mySteer TO HEADING(0, 90).
		IF isLFFullThrust() {
			SET mode TO 2.
			stageFunction().
		}
	}

	// Vertical climb
	IF mode = 2 {
		SET mySteer TO HEADING(0, 90).
		IF ALT:RADAR > 100 {
			SET gravTurnStart TO ALTITUDE.

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
		IF ALT:RADAR > 500 {
			PITCH_PID:RESET().
			SET PITCH_PID:MAXOUTPUT TO maxAOA.
			SET PITCH_PID:MINOUTPUT TO -maxAOA.

			YAW_PID:RESET().
			SET YAW_PID:MAXOUTPUT TO 20.
			SET YAW_PID:MINOUTPUT TO -YAW_PID:MAXOUTPUT.
			SET YAW_PID:SETPOINT TO finalInclination.
//			IF connectionToKSC() LOG "Mission Time,Mode,Surface Velocity Pitch,Inclination,Latitude,yawValue,Mode Start Yaw,Ship Yaw,YAW_PID:OUTPUT,YAW_PID:SETPOINT" TO "0:YawPID.csv".

			// reset the integral on the Yaw PID when the ship crosses the equator
			WHEN (ABS(SHIP:GEOPOSITION:LAT) < 0.1) THEN {
				SET modeStartYaw TO launchAzimuth.
				YAW_PID:RESET().
			}

			// When the atmosphere isn't really a concern anymore, let the PID have a little more freedom
			WHEN ((SHIP:BODY:ATM:EXISTS) AND (SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) < 0.25)) THEN {
				PRINT "Loosening PID!".
				SET PITCH_PID:MAXOUTPUT TO 15.
				SET PITCH_PID:MINOUTPUT TO -15.

//				FOR f IN SHIP:MODULESNAMED("ProceduralFairingDecoupler") { f:DOEVENT("jettison fairing"). }
			}
			SET mode TO 4.
		}
	}

	// there are several things that apply to all of the "in flight" modes
	IF (mode >= 4) {
		updateShipInfoCurrent(FALSE).
		IF debug {
			PRINT "Pitch Setpoint " + ROUND ( PITCH_PID:SETPOINT, 2) + "    " AT(0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + "    " AT (0, 6).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) + "    " AT (0, 7).
			PRINT "Yaw PID Setpoint " + ROUND(YAW_PID:SETPOINT, 4) + "    " AT (0, 8).
			PRINT "Yaw PID Input " + ROUND(SHIP:ORBIT:INCLINATION, 4) + "    " AT (0, 9).
			PRINT "Facing Yaw " + ROUND(yaw_for(SHIP), 2) + "    " AT (0, 10).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"], 4) + " m/s^2    " AT (0, 11).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"], 4) + " m/s^2    " AT (0, 12).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"]/body_g, 4) + " g's      " AT (0, 13).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"]/body_g, 4) + " g's      " AT (0, 14).
		}

		// attempt at calculating the throttle to ensure maxGs acceleration at most
		// note that maxGs is relative to sea level on THIS BODY, not Earth/Kerbin.
		// desired throttle = (maxGs + body_g - accel from SRBs)/available accel from variable engines
		IF (shipInfo["Maximum"]["Variable"]["Accel"] <> 0) {
			IF minThrottle <> 1	SET myThrottle TO (((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]) - minThrottle)/(1-minThrottle).
			ELSE				SET myThrottle TO  ((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]).
		} ELSE SET myThrottle TO 1.
//		SET myThrottle TO (maxGs * body_g) / shipInfo["Maximum"]["Accel"].
		SET myThrottle TO MIN( MAX( myThrottle, 0.05), 1.0).

//		logPhysics("0:" + SHIP:NAME + " GravTurnLaunch Physics.csv").

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

		// only call the PID if the ship is through a large portion of the gravity turn and the final inclination is not zero
		IF (pitch_vector(SHIP:VELOCITY:SURFACE) < 45) AND (finalInclination = 0) {
			IF (SHIP:GEOPOSITION:LAT > 0.0) SET yawValue TO YAW_PID:UPDATE( TIME:SECONDS, SHIP:ORBIT:INCLINATION).
			IF (SHIP:GEOPOSITION:LAT < 0.0) SET yawValue TO -YAW_PID:UPDATE( TIME:SECONDS, SHIP:ORBIT:INCLINATION).
		}
		IF (finalInclination = 0) SET yawValue TO 0.

//		IF connectionToKSC() LOG TIME:SECONDS + "," + mode + "," + pitch_vector(SHIP:VELOCITY:SURFACE) + "," + SHIP:ORBIT:INCLINATION + "," + SHIP:GEOPOSITION:LAT + "," + yawValue + "," + modeStartYaw + "," + yaw_for(SHIP) + "," + YAW_PID:OUTPUT + "," + YAW_PID:SETPOINT TO "0:YawPID.csv".

		IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
			PRINT "Staging from resources".
			stageFunction().
		}

		// Gravity turn
		// Note that this gravity turn uses a PID to maintain the prograde vector at the correct pitch
		IF mode = 4 {
			SET PITCH_PID:SETPOINT TO gravityTurn(gravTurnStart, gravTurnEnd, 90, gravTurnAngleEnd, gravTurnExponent).
			LOCAL pitchValue IS PITCH_PID:SETPOINT + PITCH_PID:UPDATE( TIME:SECONDS, 90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)).
//			logPID(PITCH_PID, "0:PitchPID.csv").
			IF pitchValue < 0 SET pitchValue TO 0.
			IF pitchValue > 90 SET pitchValue TO 90.

			// Start off the gravity turn going the direction given, then follow the current heading
			SET mySteer TO HEADING (modeStartYaw + yawValue, pitchValue).
			// when the gravity turn is done, start burning strictly horizontal and let the vertical speed drop
			IF ALTITUDE > gravTurnEnd {
				SET mode TO 5.
			}
		}

		// Horizontal flight
		IF mode = 5 {
			// This needs to be updated every scan to keep the pitch at 0 as the craft moves around the planet
			SET mySteer TO HEADING(modeStartYaw + yawValue, 0).

			// when vertical speed is below 0.5 m/s, start controlling pitch to maintain 0 vertical speed
			IF VERTICALSPEED < 0.5 {
				PITCH_PID:RESET().
				SET PITCH_PID:MAXOUTPUT TO 45.
				SET PITCH_PID:MINOUTPUT TO 0.
				SET mode to 6.
			}
		}

		// Maintain vertical speed
		IF mode = 6 {
			IF SHIP:BODY:ATM:EXISTS {
				IF (ALTITUDE > SHIP:BODY:ATM:HEIGHT + 10000) SET PITCH_PID:SETPOINT TO 0.
				ELSE IF (ALTITUDE > SHIP:BODY:ATM:HEIGHT + 5000) SET PITCH_PID:SETPOINT TO (ALTITUDE-SHIP:BODY:ATM:HEIGHT)/5000.
			} ELSE {
				SET PITCH_PID:SETPOINT TO 0.
			}
			LOCAL pitchValue IS PITCH_PID:UPDATE( TIME:SECONDS, VERTICALSPEED).

			SET mySteer TO HEADING (modeStartYaw + yawValue, pitchValue).
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
		IF (ETA:APOAPSIS > 10*60 AND ETA:PERIAPSIS > 10*60 AND ALTITUDE > 100000 AND VERTICALSPEED > 0) {
			SET endMessage TO "Complicated exit".
			SET mode to 7.
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
activateOmniAntennae().
