@LAZYGLOBAL OFF.

PARAMETER finalInclination IS 0.			// The desired final inclination of the orbit
PARAMETER delayForEngines IS FALSE.			// whether or not to delay for engines to spool up before launch
											// if enabled, stages the hold-down clamps and SRBs after LF engines have reached full thrust
PARAMETER targetAltitude IS 30000.			// The altitude of the end of the gravity turn
PARAMETER initialStage IS FALSE.				// Whether or not to trigger the initial stage
PARAMETER maxGs IS 1.5.						// maximum number of G's that the ship should go under

LOCAL launchAzimuth IS desiredAzimuth(targetAltitude, finalInclination).

SET finalInclination TO ABS(finalInclination).

LOCAL mode IS 0.
// Mode 0 - Prelaunch - may add pauses for orbital alignments later
// Mode 1 - LF rampup
// Mode 2 - Vertical Ascent per formulas

LOCAL mu IS SHIP:BODY:MU.

LOCAL body_g IS mu/SHIP:BODY:RADIUS^2.

// Set the initial acceleration to the maximum accel minus local gravity OR
//     maxGs (in m/s^2), whichever is lower
LOCAL constInitialAccel IS MIN(maxGs * body_g, shipInfo["Maximum"]["Accel"]) - mu/(SHIP:POSITION - SHIP:BODY:POSITION):SQRMAGNITUDE.
// Set the constant ascent time to the formula from Matlab.
LOCAL constAscentTime IS 3/2*CONSTANT:pi*SQRT(2*targetAltitude/(constInitialAccel * (CONSTANT:pi + 2))).
LOCAL yawValue IS 0.										// yaw adjustment factor for inclination tuning
LOCAL endMessage IS "Blank".						// Used to determine the reason for exiting the loop
LOCAL pitchValue IS 0.									// Used for calculating the desired pitch of the craft

AG1 OFF.
CLEARSCREEN.
PRINT "Initial Accel: " + distanceToString(constInitialAccel, 6) + "/s".
PRINT "Vertical Travel Time: " + timeToString(constAscentTime, 6).
PRINT "Vertical Travel Time: " + ROUND(constAscentTime, 6) + " seconds".
PRINT "body g: " + distanceToString(body_g, 6) + " ".
PRINT "local g: " + distanceToString(mu/(SHIP:POSITION - SHIP:BODY:POSITION):SQRMAGNITUDE, 6) + " ".
PRINT "Max Accel: " + distanceToString(shipInfo["Maximum"]["Accel"], 6) + "/s".
PRINT "Max Accel allowed: " + maxGs + " g's".
UNTIL AG1 WAIT 0.

SET missionTimeOffset TO MISSIONTIME.		// Used to offset MISSIONTIME to account for time waiting on the pad

SET globalSteer TO SHIP:UP.									// Direction for cooked steering
SET globalThrottle TO 1.0.

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

LOCAL modeStartYaw TO launchAzimuth.

IF connectionToKSC() AND EXISTS("0:precisionCalcs.csv") DELETEPATH("0:precisionCalcs.csv").
IF connectionToKSC() LOG "Time,Mode,Stage,Mass (kg),Ship Facing Pitch (deg),Prograde Pitch (deg),Pitch Setpoint (deg),Horizontal Speed (m/s),Altitude (m),Current Accel (m/s^2),Centripital Accel (m/s^2),Local g (m/s^2),Vertical Accel Req'd (m/s^2),Max Allowed Accel (m/s^2),Required Pitch (deg),Predicted Accel (m/s^2),Predicted Velocity (m/s),Predicted Position (m),Vertical Speed (m/s),Throttle,Raw Ship Accel (m/s^2),Current Constant Accel (m/s^2),Max Variable Accel (m/s^2)" TO "0:precisionCalcs.csv".

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

	// Vertical Ascent per formulas
	IF mode = 2 {
		PRINT "V Speed      " AT (40, 1).
		PRINT "             " AT (40, 2).
		PRINT "             " AT (40, 3).
		activateOmniAntennae().
	}

	RETURN TRUE.
}

FUNCTION valuesPrediction {
	PARAMETER t_ascent.
	PARAMETER a_y_0.
	PARAMETER timeValue.
	LOCAL pi IS CONSTANT:PI.
	LOCAL RadToDeg IS CONSTANT:RadToDeg.
	LOCAL returnMe IS LEXICON().
	LOCAL phi IS COS(RadToDeg*3*CONSTANT:PI*timeValue/(2*t_ascent)).
	LOCAL phiS IS SIN(RadToDeg*3*CONSTANT:PI*timeValue/(2*t_ascent)).
	returnMe:ADD("accel", 0).
	returnMe:ADD("velocity", 0).
	returnMe:ADD("position", 0).
	IF timeValue >= 0 AND timeValue < t_ascent/3 {
		SET returnMe["accel"] TO a_y_0 * phi.
		SET returnMe["velocity"] TO 2 * a_y_0 * t_ascent * (phiS + 0) / (3 * pi).
		SET returnMe["position"] TO -4 * a_y_0 * t_ascent^2 * (phi - 1) / (9 * pi^2).
	}
	IF timeValue >= t_ascent/3 AND timeValue <= t_ascent {
		SET returnMe["accel"] TO a_y_0/2*phi.
		SET returnMe["velocity"] TO     a_y_0 * t_ascent * (phiS + 1) / (3 * pi).
		SET returnMe["position"] TO a_y_0 * t_ascent * (4 * t_ascent - pi * t_ascent + 3 * pi * timeValue - 2 * t_ascent * phi) / (9 * pi^2).
	}
	IF timeValue >= t_ascent {
		SET returnMe["accel"] TO 0.
		SET returnMe["velocity"] TO 0.
		SET returnMe["position"] TO a_y_0 * t_ascent * (4 * t_ascent + 2 * pi * t_ascent) / (9 * pi^2).
	}
	RETURN returnMe.
}

LOCAL centripitalAccel IS 0.
LOCAL local_g IS 0.
LOCAL requiredVerticalAccel IS 0.
LOCAL accelRatios IS 0.
LOCAL startTime IS TIME:SECONDS.
LOCAL runTime IS 0.
LOCAL startAltitude IS ALTITUDE.
LOCAL currentAltitudeDelta IS 0.
LOCAL currentValuesPredition IS valuesPrediction(constAscentTime, constInitialAccel, runTime).


// when the periapsis gets above ground, set timewarp back to normal
WHEN PERIAPSIS > 0 AND physicsWarpPerm THEN {
	SET KUNIVERSE:timewarp:warp to 0.
}

WHEN currentAltitudeDelta > 100 AND physicsWarpPerm THEN {
	SET KUNIVERSE:timewarp:warp TO physicsWarpPerm.
}

UNTIL mode > 3 {
	SET runTime TO TIME:SECONDS - startTime.
	SET currentAltitudeDelta TO ALTITUDE - startAltitude.
	SET currentValuesPredition TO valuesPrediction(constAscentTime, constInitialAccel, runTime).
	updateFacingVectors().
	SET centripitalAccel TO VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:ORBIT):SQRMAGNITUDE/(SHIP:POSITION - SHIP:BODY:POSITION):MAG.
	SET local_g TO mu/(SHIP:POSITION - SHIP:BODY:POSITION):SQRMAGNITUDE.
	SET requiredVerticalAccel TO currentValuesPredition["accel"] + local_g - centripitalAccel.
	IF (shipInfo["Current"]["Accel"] <> 0) SET accelRatios TO requiredVerticalAccel / shipInfo["Current"]["Accel"].
	IF accelRatios > SIN(90) SET accelRatios TO SIN(90).
	IF accelRatios < -SIN(90) SET accelRatios TO -SIN(90).
	IF connectionToKSC() LOG runTime + "," +
													 mode + "," +
													 (shipInfo["NumberOfStages"] - 1) + "," +
													 SHIP:MASS*1000 + "," +
													 (90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR)) + "," +
													 (90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE)) + "," +
													 pitchValue + "," +
													 GROUNDSPEED + "," +
													 currentAltitudeDelta + "," +
													 shipInfo["Current"]["Accel"] + "," +
													 centripitalAccel + "," +
													 local_g + "," +
													 requiredVerticalAccel + "," +
													 (body_g * maxGs) + "," +
													 ARCSIN(accelRatios) + "," +
													 currentValuesPredition["accel"] + "," +
													 currentValuesPredition["velocity"] + "," +
													 currentValuesPredition["position"] + "," +
													 VERTICALSPEED + "," +
													 THROTTLE + "," +
													 (SHIP:THRUST / SHIP:MASS) + "," +
													 shipInfo["Current"]["Constant"]["Accel"]  + "," +
													 shipInfo["Maximum"]["Variable"]["Accel"] TO "0:precisionCalcs.csv".
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
		SET globalSteer TO HEADING(0, pitchValue).
		IF isLFFullThrust() {
			SET mode TO 2.
			stageFunction().
		}
	}

	// there are several things that apply to all of the "in flight" modes
	IF (mode >= 2) {
		updateShipInfoCurrent(FALSE).
		IF debug {
			PRINT "Predicted Accel: " + distanceToString(currentValuesPredition["accel"], 2) + "/s^2    " AT (0, 3).
			PRINT "Predicted Velocity: " + distanceToString(currentValuesPredition["velocity"], 2) + "/s    " AT (0, 4).
			PRINT "Predicted Position: " + distanceToString(currentValuesPredition["position"], 2) + "    " AT (0, 5).
			PRINT "Prograde Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), 2) + " deg    " AT (0, 6).
			PRINT "Vertical Speed: " + distanceToString(VERTICALSPEED, 2) + "/s    " AT (0, 7).
			PRINT "Facing Pitch: " + ROUND(90 - vang(SHIP:UP:VECTOR, SHIP:FACING:FOREVECTOR), 2) + "    " AT (0, 8).

			PRINT "Centripital Accel " + distanceToString(centripitalAccel, 4) + "/s^2     " AT (0, 12).
			PRINT "Local g     Accel " + distanceToString(local_g, 4) + "/s^2     " AT (0, 13).
			PRINT "Current     Accel " + distanceToString(shipInfo["Current"]["Accel"], 4) + "/s^2      " AT (0, 14).
			PRINT "Maximum     Accel " + distanceToString(shipInfo["Maximum"]["Accel"], 4) + "/s^2      " AT (0, 15).
			PRINT "Required    Accel " + distanceToString(requiredVerticalAccel, 4) + "/s^2      " AT (0, 16).
			PRINT "Runtime " + timeToString(runTime) + "    " AT(0, 17).
			PRINT "Runtime left " + timeToString(constAscentTime - runTime) + " s    " AT(0, 18).


			PRINT "Setpoint " + distanceToString(currentValuesPredition["velocity"], 3) + "/s   " AT (40, 2).
			PRINT "Actual " + distanceToString(VERTICALSPEED, 3) + "/s   " AT (40, 3).
		}

		// attempt at calculating the throttle to ensure maxGs acceleration at most
		// note that maxGs is relative to sea level on THIS BODY, not Earth/Kerbin.
		// desired throttle = (maxGs * body_g - accel from SRBs)/available accel from variable engines
		IF (shipInfo["Maximum"]["Variable"]["Accel"] <> 0) {
			SET globalThrottle TO   ((maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"]).
		} ELSE SET globalThrottle TO 1.0.
		SET globalThrottle TO  MIN( MAX( globalThrottle, 0.0), 1.0).

		SET yawValue TO 0.

		// Maintain vertical speed
		IF mode = 2 {
			SET pitchValue TO ARCSIN(accelRatios).
			SET globalSteer TO HEADING(modeStartYaw + yawValue, pitchValue).
		}

		// when any of the following conditions are met, kill the engine and stop the program
		// current orbital velocity is greater than the orbital velocity for a circular orbit at this altitude
		// periapsis is within 1 km of current altitude (burn is complete)
		// apoapsis is greater than 10 minutes away AND periapsis is greater than 10 minutes away
		//		AND altitude is greater than 100,000 meters AND vertical speed is positive
		//		AND periapsis is above ground
		IF (SHIP:VELOCITY:ORBIT:SQRMAGNITUDE*0.999 > MU/(SHIP:POSITION - SHIP:BODY:POSITION):MAG) {
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
}

SET dontKillAfterScript TO NOT isStockRockets().
SET loopMessage TO endMessage.
activateOmniAntennae().
