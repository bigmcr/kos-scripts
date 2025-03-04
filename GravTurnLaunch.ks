@LAZYGLOBAL OFF.

// The altitude of the end of the gravity turn
// If there is an atmosphere, it defaults to 5km below the top.
// If there is not an atmosphere, it defaults to 25km.
IF SHIP:BODY:ATM:EXISTS PARAMETER gravTurnEnd IS SHIP:BODY:ATM:HEIGHT - 5000.
ELSE PARAMETER gravTurnEnd IS 25000.

// The desired final inclination of the orbit
// Negative values are allowed; the finalLAN will be adjusted to compensate
PARAMETER finalInclination IS 0.

// The desired final longitude of the ascending node
// Note that this is relative to the Solar Prime Vector
PARAMETER finalLAN IS 0.

// Whether or not to trigger the initial stage.
// For a launch from Kerbin/Earth, this is true, but it might not be from Luna/the Mun
PARAMETER initialStage IS TRUE.

// Maximum number of G's that the ship should go under
// For passenger comfort and safety
PARAMETER maxGs IS 3.

IF finalInclination < 0 {
	SET finalLAN TO normalizeAngle360(finalLAN + 180).
	SET finalInclination TO ABS(finalInclination).
}

LOCAL mode IS 0.
// Mode 0 - Prelaunch
// Mode 1 - LF rampup
// Mode 2 - Vertical climb
// Mode 3 - Roll East
// Mode 4 - Gravity turn
// Mode 5 - Burn horizontal only
// Mode 6 - Maintain vertical speed of 0 m/s

LOCAL yawValue IS 0.										// yaw adjustment factor for inclination tuning
LOCAL PITCH_PID IS PIDLOOP(2.0, 0.25, 2.0, -5, 5).	// PID loop to control pitch
LOCAL gravTurnStart TO 1000.						// The altitude of the start of the gravity turn
LOCAL gravTurnExponent TO 0.740740741.	// The exponent used in the calculation of the gravity turn
LOCAL endMessage IS "Blank".						// Used to determine the reason for exiting the loop
LOCAL engineList IS LIST().							// Used to list all of the engines for staging
LOCAL pitchValue IS 0.									// Used for calculating the desired pitch of the craft

LOCAL useYawPID IS (finalInclination <> 0).

// This is the position from the orbital plane PID. Input is the position from
// the orbital plane, output is speed toward or away from the plane.
// The default values assume an approach speed of 200 m/s for every 10 km of error.
LOCAL yawPos_PID IS PIDLOOP(0.01, 0.0, 0.15).
SET yawPos_PID:MAXOUTPUT TO 200.
SET yawPos_PID:MINOUTPUT TO -yawPos_PID:MAXOUTPUT.
SET yawPos_PID:SETPOINT TO 0.
LOCAL yawPos_PIDReset IS FALSE.

// This is the speed to/from the orbital plane PID. Input is the speed toward
// or away from the orbital plane, output is the acceleration to get there.
// The default values assume an acceleration of 10 m/s^2 for every 200 m/s speed error.
LOCAL yawSpeed_PID IS PIDLOOP(-0.05, -0.01, -0.1).
SET yawSpeed_PID:MAXOUTPUT TO 10.
SET yawSpeed_PID:MINOUTPUT TO -yawSpeed_PID:MAXOUTPUT.

LOCAL body_g IS CONSTANT:G * SHIP:BODY:MASS/(SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad

SET globalSteer TO SHIP:UP.							// Direction for cooked steering
SET globalThrottle TO 0.0.							// Throttle for auto throttle control

setLockedThrottle(TRUE).
setLockedSteering(TRUE).

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

LOCAL defaultYaw TO 0.

IF connectionToKSC() {
	IF EXISTS("0:pitchCalcs.csv") DELETEPATH("0:pitchCalcs.csv").
	IF connectionToKSC() LOG "Time,Mode,Stage,Mass (kg),Actual Pitch (deg),"+
	"Prograde Pitch (deg),Pitch Value (deg),Horizontal Speed (m/s),"+
	"Current Accel (m/s^2),Centripital Accel (m/s^2),Altitude (m),"+
	"Local g (m/s^2),Vertical Accel Req'd (m/s^2),Required Pitch (deg),"+
	"Horizontal Accel Req'd (m/s^2),Horizontal Accel Available (m/s^2),"+
	"Vertical Speed (m/s),Default Yaw (deg),LAN (deg),SMA (m),Arg Pe (deg),"+
	"True Anomaly,e,Inclination (deg),Distance from Plane (m),"+
	"Speed to Plane (m/s),Accel Vertical (m/s^2),Accel Lateral (m/s^2),"+
	"Accel Down Range (m/s^2),Accel Ratio Horizontal" TO "0:pitchCalcs.csv".
}

// whenever the mode changes, initialize things for the new mode.
ON mode {
	CLEARSCREEN.
	LOCAL modeX IS 45.

	PRINT "Mode: " + mode AT (modeX, 0).

	// Prelaunch - stage the LF engines
	IF mode = 0 {
		PRINT "Prelaunch    " AT (modeX, 1).
		PRINT "             " AT (modeX, 2).
		PRINT "             " AT (modeX, 3).
	}

	// Liquid Fuel ramp up
	IF mode = 1 {
		PRINT "Engine Ramp  " AT (modeX, 1).
		PRINT "Until 85% T  " AT (modeX, 2).
		PRINT "             " AT (modeX, 3).
	}

	// Vertical climb
	IF mode = 2 {
		PRINT "Vertical     " AT (modeX, 1).
		PRINT "maxAOA = " + ROUND(maxAOA, 2) AT (modeX, 2).
		PRINT "             " AT (modeX, 3).
	}

	// Roll, continue climb
	IF mode = 3 {
		PRINT "Roll         " AT (modeX, 1).
		PRINT "             " AT (modeX, 2).
		PRINT "             " AT (modeX, 3).
	}

	// Gravity turn
	IF mode = 4 {
		PRINT "Gravity Turn " AT (modeX, 1).
		PRINT "Start at " + ROUND(gravTurnStart) + "   " AT (modeX, 2).
		PRINT "End at " + ROUND(gravTurnEnd, 0) + " " AT (modeX, 3).
	}

	// Horizontal flight
	IF mode = 5 {
		PRINT "Horizontal   " AT (modeX, 1).
		PRINT "             " AT (modeX, 2).
		PRINT "             " AT (modeX, 3).
	}

	// Maintain vertical speed
	IF mode = 6 {
		PRINT "V Speed      " AT (modeX, 1).
		PRINT "Setpoint = " + distanceToString(PITCH_PID:SETPOINT) + "   " AT (modeX, 2).
		PRINT "             " AT (modeX, 3).
		activateOmniAntennae().
	}

	RETURN TRUE.
}

FUNCTION getTargetNormalVector {
	PARAMETER inclination IS 0.
	PARAMETER LAN IS 0.
	// Note that the V(0,1,0) is an invariant version of the NORTH vector.
	RETURN ((V(0,1,0) * ANGLEAXIS(-inclination, SOLARPRIMEVECTOR)) * ANGLEAXIS(-LAN, V(0,1,0))):NORMALIZED.
}

LOCAL availableHorizontalAccel IS 0.
LOCAL accelRatiosHorizontal IS 0.
LOCAL centripitalAccel IS 0.
LOCAL local_g IS 0.
LOCAL requiredVerticalAccel IS 0.
LOCAL accelRatiosVertical IS 0.
LOCAL mu IS SHIP:BODY:MU.
LOCAL targetNormal IS getTargetNormalVector(finalInclination, finalLAN).
LOCAL targetPlaneDistance IS 0.
LOCAL targetPlaneSpeed IS 0.
LOCAL targetNormalVecDraw IS VECDRAW(V(0,0,0), V(0,0,0),  YELLOW, "Target Normal"  , 1.0, TRUE, 0.2, FALSE).
SET targetNormalVecDraw:STARTUPDATER TO {RETURN BODY:POSITION.}.
SET targetNormalVecDraw:VECUPDATER TO {RETURN 3*BODY:RADIUS * targetNormal.}.

LOCAL actualAccel IS 0.
LOCAL accelVertical IS 0.
LOCAL accelLateral IS 0.
LOCAL accelDownRange IS 0.

// Prelaunch - wait for launch window, then stage the LF engines
// Note that this is outside the main control loop because of the chance
// of the operator aborting the launch during the wait period.
IF mode = 0 {
	PRINT "Mode 0".
	GLOBAL abortLaunch IS FALSE.
	RUNPATH("waitForLaunchWindow", finalInclination, finalLAN, FALSE).
	IF abortLaunch {
		SET mode TO 10.
		SET endMessage TO "Launch aborted".
	} ELSE {
		WAIT 1.
		stageFunction().
		PRINT "Initial Stage!".
		SET mode TO 1.
	}
}

UNTIL mode > 6 {
	IF useYawPID AND NOT yawPos_PIDReset AND ABS(yawPos_PID:ERROR) < 1000 {
		yawPos_PID:RESET().
		SET yawPos_PIDReset TO TRUE.
	}
	updateFacingVectors().
	SET defaultYaw TO yaw_for(-VCRS(targetNormal, SHIP:POSITION - BODY:POSITION)).
	SET centripitalAccel TO VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:ORBIT):SQRMAGNITUDE/(SHIP:POSITION - SHIP:BODY:POSITION):MAG.
	SET local_g TO mu/(SHIP:POSITION - SHIP:BODY:POSITION):SQRMAGNITUDE.
	SET requiredVerticalAccel TO local_g - centripitalAccel.
	SET actualAccel TO shipInfo["Current"]["Accel"] * SHIP:FACING:VECTOR + (local_g - centripitalAccel) * (SHIP:POSITION - SHIP:BODY:POSITION):NORMALIZED.
	SET accelVertical TO actualAccel * UP:VECTOR.
	SET accelLateral TO actualAccel * targetNormal.
	SET accelDownRange TO actualAccel * -VCRS(targetNormal, UP:VECTOR):NORMALIZED.
	IF (shipInfo["Current"]["Accel"] <> 0) SET accelRatiosVertical TO requiredVerticalAccel / shipInfo["Current"]["Accel"].
	IF accelRatiosVertical > SIN(85) SET accelRatiosVertical TO SIN(85).
	IF accelRatiosVertical < 0 SET accelRatiosVertical TO 0.
	IF shipInfo["Current"]["Accel"] > requiredVerticalAccel	{
		SET availableHorizontalAccel TO SQRT(shipInfo["Current"]["Accel"]*shipInfo["Current"]["Accel"] - requiredVerticalAccel*requiredVerticalAccel).
	} ELSE {
		SET availableHorizontalAccel TO 0.
	}
	IF (availableHorizontalAccel <> 0) {SET accelRatiosHorizontal TO yawSpeed_PID:OUTPUT / availableHorizontalAccel.}
	IF accelRatiosHorizontal > SIN(30) SET accelRatiosHorizontal TO SIN(30).
	IF accelRatiosHorizontal < -SIN(30) SET accelRatiosHorizontal TO -SIN(30).

	SET targetNormal TO getTargetNormalVector(finalInclination, finalLAN).
	SET targetPlaneDistance TO targetNormal * (SHIP:POSITION - BODY:POSITION).
	SET targetPlaneSpeed TO targetNormal * VELOCITY:ORBIT.
	IF connectionToKSC() LOG MISSIONTIME + "," + mode + "," + (shipInfo["NumberOfStages"] - 1) + "," +
			SHIP:MASS*1000 + "," + (90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR)) + "," +
			(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)) + "," + pitchValue + "," +
			GROUNDSPEED + "," + shipInfo["Current"]["Accel"] + "," + centripitalAccel + "," +
			ALTITUDE + "," + local_g + "," + requiredVerticalAccel + "," +
			ARCSIN(accelRatiosVertical) + "," + yawSpeed_PID:OUTPUT + "," +
			availableHorizontalAccel + "," + VERTICALSPEED + "," + defaultYaw + "," +
			ORBIT:LAN + "," + ORBIT:SEMIMAJORAXIS + "," + ORBIT:ARGUMENTOFPERIAPSIS + "," +
			ORBIT:TRUEANOMALY + "," + ORBIT:ECCENTRICITY + "," + ORBIT:INCLINATION + "," +
			targetPlaneDistance + "," + targetPlaneSpeed + "," + accelVertical + "," +
			accelLateral + "," + accelDownRange + "," + accelRatiosHorizontal TO "0:pitchCalcs.csv".
	engineInfo(0, 23, TRUE).

	// Engine ramp up
	IF mode = 1 {
		SET pitchValue TO 90.
		// if the active engines have reached full thrust, stage and switch modes
		SET globalSteer TO HEADING(0, pitchValue).
		IF isLFFullThrust() {
			SET mode TO 2.
			stageFunction().
		}
	}

	// Vertical climb
	IF mode = 2 {
		SET pitchValue TO 90.
		SET globalSteer TO HEADING(0, pitchValue).
		IF ALT:RADAR > 100 {
			SET gravTurnStart TO ALTITUDE.

			// If there is no atmosphere on this body, start the grav turn more quickly
			IF NOT SHIP:BODY:ATM:EXISTS {
				PITCH_PID:RESET().
				SET mode TO 4.
			}
			ELSE SET mode TO 3.

			SET PITCH_PID:MAXOUTPUT TO maxAOA.
			SET PITCH_PID:MINOUTPUT TO -maxAOA.

			// When the atmosphere isn't really a concern anymore, let the PID have a little more freedom
			WHEN ((SHIP:BODY:ATM:EXISTS) AND (SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) < 0.05)) THEN {
				PRINT "Loosening PID!".
				SET PITCH_PID:MAXOUTPUT TO 15.
				SET PITCH_PID:MINOUTPUT TO -15.
			}

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
		SET globalSteer TO HEADING(defaultYaw,pitchValue).
		IF ALT:RADAR > 500 {
			SET mode TO 4.
		}
	}

	// there are several things that apply to all of the "in flight" modes
	IF (mode >= 4) {
		IF useYawPID {
			logPID(yawPos_PID, "0:yawPos_PID.csv", TRUE).
			logPID(yawSpeed_PID, "0:yawSpeed_PID.csv", TRUE).
		}
		updateShipInfoCurrent(FALSE).
		IF debug {
			PRINT "Ship Facing To North Vector: " + ROUND(normalizeAngle180(yaw_for(SHIP)), 3) + " deg      " AT (0, 4).
			IF (mode = 6) PRINT "Pitch Setpoint " + distanceToString( PITCH_PID:SETPOINT, 2) + "/s      " AT(0, 5).
			ELSE					 PRINT "Pitch Setpoint " + ROUND( PITCH_PID:SETPOINT, 2) + " deg      " AT(0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + " deg    " AT (0, 6).
			PRINT "Vertical Speed: " + distanceToString(VERTICALSPEED, 2) + "/s    " AT (0, 7).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) + "    " AT (0, 8).
			PRINT "Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 4) + " deg    " AT (0, 9).
			PRINT "Facing Yaw " + ROUND(yaw_for(SHIP), 2) + "    " AT (0, 10).
			PRINT "Default Yaw " + ROUND(defaultYaw, 3) + " deg" AT (0, 11).
			PRINT "Yaw Delta: " + ROUND(ARCSIN(accelRatiosHorizontal), 3) + " deg    " AT (0, 12).
			PRINT "Target Plane Distance: " + distanceToString(targetPlaneDistance, 3) + "    " AT (0, 13).
			PRINT "Target Plane Speed: " + distanceToString(targetPlaneSpeed, 3) + "/s    " AT (0, 14).
			PRINT "Target Plane Speed Setpoint: " + distanceToString(yawSpeed_PID:SETPOINT, 3) + "/s    " AT (0, 15).
			PRINT "Centripital Accel " + distanceToString(centripitalAccel, 4) + "/s^2     " AT (0, 16).
			PRINT "Local g Accel " + distanceToString(local_g, 4) + "/s^2     " AT (0, 17).
			PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"]/body_g, 4) + " g's      " AT (0, 18).
			PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"]/body_g, 4) + " g's      " AT (0, 19).
		}

		// attempt at calculating the throttle to ensure maxGs acceleration at most
		// note that maxGs is relative to sea level on THIS BODY, not Earth/Kerbin.
		// desired throttle = (maxGs * body_g - accel from SRBs)/available accel from variable engines
		IF (shipInfo["Maximum"]["Variable"]["Accel"] <> 0) {
			SET globalThrottle TO ((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]).
		} ELSE SET globalThrottle TO 1.0.
		SET globalThrottle TO MIN( MAX( globalThrottle, 0.05), 1.0).

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

		IF useYawPID {
			SET yawSpeed_PID:SETPOINT TO yawPos_PID:UPDATE(TIME:SECONDS, targetPlaneDistance).
			yawSpeed_PID:UPDATE(TIME:SECONDS, targetPlaneSpeed).
			SET yawValue TO ARCSIN(accelRatiosHorizontal).
		} ELSE {
			SET yawValue TO 0.
		}

		// Gravity turn
		// Note that this gravity turn uses a PID to maintain the prograde vector at the correct pitch
		IF mode = 4 {
			// note that this has hardcoded initial and end angles (90 and 10 degrees).
			SET PITCH_PID:SETPOINT TO gravityTurn(gravTurnStart, gravTurnEnd, 90, 10, gravTurnExponent).
			SET pitchValue TO PITCH_PID:SETPOINT + PITCH_PID:UPDATE( TIME:SECONDS, 90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)).
			IF pitchValue < 0 SET pitchValue TO 0.
			IF pitchValue > 90 SET pitchValue TO 90.

			// Start off the gravity turn going the direction given, then follow the current heading
			SET globalSteer TO HEADING(defaultYaw + yawValue, pitchValue).
			// when the gravity turn is done, start burning strictly horizontal and let the vertical speed drop
			IF ALTITUDE > gravTurnEnd {
				SET mode TO 5.
			}
		}

		// Horizontal flight
		IF mode = 5 {
			SET pitchValue TO 0.0.
			// This needs to be updated every scan to keep the pitch at 0 as the craft moves around the planet
			SET globalSteer TO HEADING(defaultYaw + yawValue, pitchValue).

			// when vertical speed is within one second of falling below zero, start controlling pitch to maintain 0 vertical speed
			IF VERTICALSPEED < local_g {
				PITCH_PID:RESET().
				SET PITCH_PID:MAXOUTPUT TO 5.
				SET PITCH_PID:MINOUTPUT TO -5.
				SET mode to 6.
			}
		}

		// Maintain vertical speed
		IF mode = 6 {
			IF SHIP:BODY:ATM:EXISTS {
				IF (ALTITUDE > SHIP:BODY:ATM:HEIGHT + 10000) SET PITCH_PID:SETPOINT TO 0.
				ELSE IF (ALTITUDE > SHIP:BODY:ATM:HEIGHT + 5000) SET PITCH_PID:SETPOINT TO (SHIP:BODY:ATM:HEIGHT + 5000 - ALTITUDE) / 500.0.
				ELSE SET PITCH_PID:SETPOINT TO (SHIP:BODY:ATM:HEIGHT + 5000 - ALTITUDE) / 250.0.
			} ELSE {
				SET PITCH_PID:SETPOINT TO 0.
			}
			SET PITCH_PID:KD TO MAX(4.0 * (1 - GROUNDSPEED/ABS(SQRT(BODY:MU/(ALTITUDE + BODY:RADIUS)))), 0.0).
			SET pitchValue TO MIN(80, ARCSIN(accelRatiosVertical) + PITCH_PID:UPDATE( TIME:SECONDS, VERTICALSPEED)).
			SET globalSteer TO HEADING(defaultYaw + yawValue, pitchValue).
		}

		// when any of the following conditions are met, kill the engine and stop the program
		// current orbital velocity is greater than the orbital velocity for a circular orbit at this altitude
		// periapsis is within 1 km of current altitude (burn is complete)
		// apoapsis is greater than 10 minutes away AND periapsis is greater than 10 minutes away
		//		AND altitude is greater than end altitiude AND vertical speed is positive
		//		AND periapsis is above ground
		IF (SHIP:VELOCITY:ORBIT:SQRMAGNITUDE*0.999 > MU/(SHIP:POSITION - SHIP:BODY:POSITION):MAG) {
			SET endMessage TO "Final orbital velocity met".
			SET mode TO 7.
		}
		IF (PERIAPSIS > ALTITUDE - 1000) {
			SET endMessage TO "Peri > Alt - 1km".
			SET mode TO 7.
		}
		IF (ETA:APOAPSIS > 10*60 AND ETA:PERIAPSIS > 10*60 AND ALTITUDE > gravTurnEnd AND VERTICALSPEED > 0 AND PERIAPSIS > 0) {
			SET endMessage TO "Complicated exit".
			SET mode to 7.
		}
	}
	printPID(PITCH_PID, "Pitch PID", 45, 5).
	IF useYawPID {
		printPID(yawPos_PID, "Yaw Position PID", 0, 30).
		printPID(yawSpeed_PID, "Yaw Speed PID", 45, 30).
	} ELSE {
		PRINT "Yaw PIDs not being used" AT (0, 30).
	}
	WAIT 0.
}

SET dontKillAfterScript TO NOT isStockRockets().
SET loopMessage TO endMessage.
activateOmniAntennae().
