@LAZYGLOBAL OFF.

PARAMETER finalInclination IS 0.			// The desired final inclination of the orbit
PARAMETER delayForEngines IS TRUE.			// whether or not to delay for engines to spool up before launch
											// if enabled, stages the hold-down clamps and SRBs after LF engines have reached full thrust
PARAMETER gravTurnAngleEnd IS 10.			// The final angle of the end of the gravity turn
PARAMETER gravTurnEnd IS 150000.			// The altitude of the end of the gravity turn
PARAMETER initialStage IS TRUE.				// Whether or not to trigger the initial stage
PARAMETER maxGs IS 2.						// maximum number of G's that the ship should go under

endScript().

ON MAPVIEW {
	SET facingVector:SHOW TO useMySteer AND NOT MAPVIEW.
	SET guidanceVector:SHOW TO useMySteer AND NOT MAPVIEW.
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

LOCAL yawValue IS 0.										// yaw adjustment factor for inclination tuning
LOCAL PITCH_PID IS PIDLOOP(2.0, 0.25, 2.0).	// PID loop to control pitch
LOCAL YAW_PID IS PIDLOOP(1, 0.1, 50).		// PID loop to control yaw
LOCAL gravTurnStart TO 1000.						// The altitude of the start of the gravity turn
LOCAL gravTurnExponent TO 0.740740741.	// The exponent used in the calculation of the gravity turn
LOCAL endMessage IS "Blank".						// Used to determine the reason for exiting the loop
LOCAL engineList IS LIST().							// Used to list all of the engines for staging
LOCAL pitchValue IS 0.									// Used for calculating the desired pitch of the craft

LOCAL body_g IS CONSTANT:G * SHIP:BODY:MASS/(SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad

SET mySteer TO SHIP:UP.									// Direction for cooked steering
SET myThrottle TO 1.0.

SET useMyThrottle TO TRUE.
SET useMySteer TO TRUE.

CLEARSCREEN.

SAS OFF.
RCS OFF.
IF DEPLOYDRILLS DEPLOYDRILLS OFF.
IF GEAR GEAR OFF.
LADDERS OFF.
ISRU OFF.

IF SHIP:BODY:ATM:EXISTS {
	IF PANELS PANELS OFF.
	IF RADIATORS RADIATORS OFF.
}

// when the periapsis gets above ground, set timewarp back to normal
WHEN PERIAPSIS > 0 AND physicsWarpPerm THEN {
	SET KUNIVERSE:timewarp:warp to 0.
}

LOCAL modeStartYaw TO launchAzimuth.

//LOG "Time,Mode,Stage,Mass (kg),Actual Pitch (deg),Prograde Pitch (deg),Pitch Value (deg),Horizontal Speed (m/s),Current Accel (m/s^2),Centripital Accel (m/s^2),Altitude (m),Local g (m/s^2),Vertical Accel Req'd (m/s^2),Required Pitch (deg),Vertical Speed (m/s)" TO "0:pitchCalcs.csv".

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
		PRINT "Setpoint = " + distanceToString(PITCH_PID:SETPOINT) + "   " AT (40, 2).
		PRINT "             " AT (40, 3).
		activateOmniAntennae().
	}

	RETURN TRUE.
}

LOCAL centripitalAccel IS 0.
LOCAL local_g IS 0.
LOCAL required_vertical_accel IS 0.
LOCAL accelRatios IS 0.

UNTIL mode > 6 {
	SET centripitalAccel TO GROUNDSPEED^2/(ALTITUDE + SHIP:BODY:RADIUS).
	SET local_g TO SHIP:BODY:MU/(ALTITUDE + SHIP:BODY:RADIUS)^2.
	SET required_vertical_accel TO local_g - centripitalAccel.
	IF (shipInfo["Current"]["Accel"] <> 0) SET accelRatios TO required_vertical_accel / shipInfo["Current"]["Accel"].
	IF accelRatios > SIN(85) SET accelRatios TO SIN(85).
	IF accelRatios < 0 SET accelRatios TO 0.
//	LOG MISSIONTIME + "," + mode + "," + (shipInfo["NumberOfStages"] - 1) + "," + SHIP:MASS*1000 + "," + (90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR)) + "," + (90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)) + "," + pitchValue + "," + GROUNDSPEED + "," +
//			shipInfo["Current"]["Accel"] + "," + centripitalAccel + "," + ALTITUDE + "," + local_g + "," + required_vertical_accel + "," + ARCSIN(accelRatios) + "," + VERTICALSPEED TO "0:pitchCalcs.csv".
	engineInfo(0, 20, TRUE).
	// Prelaunch - stage the LF engines
	IF mode = 0 {
		IF initialStage {PRINT "Initial Stage!". stageFunction().}
		IF (delayForEngines) SET mode TO 1.
		ELSE SET mode TO 2.
	}

	// Engine ramp up
	IF mode = 1 {
		SET pitchValue TO 90.
		// if the active engines have reached full thrust, stage and switch modes
		SET mySteer TO HEADING(0, pitchValue).
		IF isLFFullThrust() {
			SET mode TO 2.
			stageFunction().
		}
	}

	// Vertical climb
	IF mode = 2 {
		SET pitchValue TO 90.
		SET mySteer TO HEADING(0, pitchValue).
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
		SET pitchValue TO 90.
		SET mySteer TO HEADING(launchAzimuth,pitchValue).
		IF ALT:RADAR > 500 {
			PITCH_PID:RESET().
			SET PITCH_PID:MAXOUTPUT TO maxAOA.
			SET PITCH_PID:MINOUTPUT TO -maxAOA.

			YAW_PID:RESET().
			SET YAW_PID:MAXOUTPUT TO 20.
			SET YAW_PID:MINOUTPUT TO -YAW_PID:MAXOUTPUT.
			SET YAW_PID:SETPOINT TO finalInclination.

			// reset the integral on the Yaw PID when the ship crosses the equator
			WHEN (ABS(SHIP:GEOPOSITION:LAT) < 0.1) THEN {
				SET modeStartYaw TO launchAzimuth.
				YAW_PID:RESET().
			}

			// When the atmosphere isn't really a concern anymore, let the PID have a little more freedom
			WHEN ((SHIP:BODY:ATM:EXISTS) AND (SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) < 0.05)) THEN {
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
			IF (mode = 6) PRINT "Pitch Setpoint " + distanceToString( PITCH_PID:SETPOINT, 2) + "/s      " AT(0, 5).
			ELSE					 PRINT "Pitch Setpoint " + ROUND( PITCH_PID:SETPOINT, 2) + " deg      " AT(0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + "    " AT (0, 6).
			PRINT "Verical Speed: " + distanceToString(VERTICALSPEED, 2) + "/s    " AT (0, 7).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) + "    " AT (0, 8).
			PRINT "Yaw PID Setpoint " + ROUND(YAW_PID:SETPOINT, 4) + "    " AT (0, 9).
			PRINT "Yaw PID Input " + ROUND(SHIP:ORBIT:INCLINATION, 4) + "    " AT (0, 10).
			PRINT "Facing Yaw " + ROUND(yaw_for(SHIP), 2) + "    " AT (0, 11).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"], 4) + " m/s^2    " AT (0, 12).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"], 4) + " m/s^2    " AT (0, 13).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"]/body_g, 4) + " g's      " AT (0, 14).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"]/body_g, 4) + " g's      " AT (0, 15).
		}

		// attempt at calculating the throttle to ensure maxGs acceleration at most
		// note that maxGs is relative to sea level on THIS BODY, not Earth/Kerbin.
		// desired throttle = (maxGs + body_g - accel from SRBs)/available accel from variable engines
		IF (shipInfo["Maximum"]["Variable"]["Accel"] <> 0) {
			IF minThrottle <> 1	SET myThrottle TO (((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]) - minThrottle)/(1-minThrottle).
			ELSE				SET myThrottle TO  ((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]).
		} ELSE SET myThrottle TO 1.0.
		SET myThrottle TO MIN( MAX( myThrottle, 0.05), 1.0).

		// Engine staging
		// this should drop any LF main stage and allow the final orbiter to take off
		IF (MAXTHRUST = 0) {
			PRINT "Staging from max thrust".
			IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
			ELSE stageFunction().
		}

		// this should drop any spent boosters
		SET engineList TO LIST().
		LIST ENGINES IN engineList.
		FOR eng IN engineList {
			IF eng:FLAMEOUT AND eng:IGNITION {
				PRINT "Staging from flameout".
				IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
				ELSE stageFunction().
				BREAK.
			}
		}

		// This drops any empty fuel tanks
		IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
			PRINT "Staging from resources".
			IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
			ELSE stageFunction().
		}

		// only call the PID if the ship is through a large portion of the gravity turn and the final inclination is not zero
		IF (pitch_vector(SHIP:VELOCITY:SURFACE) < 45) AND (finalInclination = 0) {
			IF (SHIP:GEOPOSITION:LAT > 0.0) SET yawValue TO YAW_PID:UPDATE( TIME:SECONDS, SHIP:ORBIT:INCLINATION).
			IF (SHIP:GEOPOSITION:LAT < 0.0) SET yawValue TO -YAW_PID:UPDATE( TIME:SECONDS, SHIP:ORBIT:INCLINATION).
		}
		IF (finalInclination = 0) SET yawValue TO 0.

		// Gravity turn
		// Note that this gravity turn uses a PID to maintain the prograde vector at the correct pitch
		IF mode = 4 {
			SET PITCH_PID:SETPOINT TO gravityTurn(gravTurnStart, gravTurnEnd, 90, gravTurnAngleEnd, gravTurnExponent).
			SET pitchValue TO PITCH_PID:SETPOINT + PITCH_PID:UPDATE( TIME:SECONDS, 90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)).
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
			SET pitchValue TO 0.0.
			// This needs to be updated every scan to keep the pitch at 0 as the craft moves around the planet
			SET mySteer TO HEADING(modeStartYaw + yawValue, pitchValue).

			// when vertical speed is below 0.5 m/s, start controlling pitch to maintain 0 vertical speed
			IF VERTICALSPEED < 0.5 {
				PITCH_PID:RESET().
				SET PITCH_PID:MAXOUTPUT TO 15.
				SET PITCH_PID:MINOUTPUT TO -15.
				SET mode to 6.
			}
		}

		// Maintain vertical speed
		IF mode = 6 {
			IF SHIP:BODY:ATM:EXISTS {
				IF (ALTITUDE > SHIP:BODY:ATM:HEIGHT + 10000) SET PITCH_PID:SETPOINT TO 0.
				ELSE IF (ALTITUDE > SHIP:BODY:ATM:HEIGHT + 5000) SET PITCH_PID:SETPOINT TO (ALTITUDE - SHIP:BODY:ATM:HEIGHT) / 500.0.
				ELSE SET PITCH_PID:SETPOINT TO (ALTITUDE - SHIP:BODY:ATM:HEIGHT) / 250.0.
			} ELSE {
				SET PITCH_PID:SETPOINT TO 0.
			}
			SET PITCH_PID:KD TO MAX(4.0 * (1 - GROUNDSPEED/ABS(SQRT(BODY:MU/(ALTITUDE + BODY:RADIUS)))), 0.0).
			SET pitchValue TO ARCSIN(accelRatios) + PITCH_PID:UPDATE( TIME:SECONDS, VERTICALSPEED).
			SET mySteer TO HEADING (modeStartYaw + yawValue, pitchValue).
		}

		// when any of the following conditions are met, kill the engine and stop the program
		// current orbital velocity is greater than the orbital velocity for a circular orbit at this altitude
		// periapsis is within 1 km of current altitude (burn is complete)
		// apoapsis is greater than 10 minutes away AND periapsis is greater than 10 minutes away
		//		AND altitude is greater than 100,000 meters AND vertical speed is positive
		//		AND periapsis is above ground
		IF (SHIP:VELOCITY:ORBIT:SQRMAGNITUDE*0.999 > SHIP:BODY:MU/(ALTITUDE + SHIP:BODY:RADIUS)) {
			SET endMessage TO "Final orbital velocity met".
			SET mode TO 7.
		}
		IF (PERIAPSIS > ALTITUDE - 1000) {
			SET endMessage TO "Peri > Alt - 1km".
			SET mode TO 7.
		}
		LOCAL endAltitude IS 100000.
		IF SHIP:BODY:ATM:EXISTS SET endAltitude TO SHIP:BODY:ATM:HEIGHT.
		IF (ETA:APOAPSIS > 10*60 AND ETA:PERIAPSIS > 10*60 AND ALTITUDE > endAltitude AND VERTICALSPEED > 0 AND PERIAPSIS > 0) {
			SET endMessage TO "Complicated exit".
			SET mode to 7.
		}
	}
	logPID(PITCH_PID, "0:PITCH_PID.csv", TRUE, 0).
}
SET myThrottle TO 0.0.

SET useMyThrottle TO FALSE.
SET useMySteer TO FALSE.

SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
WAIT 0.1.
SET SHIP:CONTROL:MAINTHROTTLE TO 0.
SET loopMessage TO endMessage.
activateOmniAntennae().
