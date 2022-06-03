@LAZYGLOBAL OFF.
PARAMETER margin IS 10.
PARAMETER useVelocity IS TRUE.
LOCAL burnInfo IS SuicideBurnInfo().
LOCAL aboveGround IS heightAboveGround().
LOCAL burnStartTime IS 0.
LOCAL RTTimeToBurn IS 0.
IF useVelocity SET margin TO 1.

// List of constants to apply to a polynomial to correct the burn distance.
// Empirically derived based on testing on the Moon, in RSS.
// Might well need changes based on planet's local g value.
// For f(x) = ax^2+bx+b,                        c,           b,           a
LOCAL burnDistanceCorrections IS LIST(-23.9625505, 1.033597489, 8.32543E-07).

LOCAL T_PID_Spd IS PIDLOOP(0.1, 0.3, 0.1, 0, 1).			// PID loop to control trottle during vertical descent phase

updateShipInfo().

SAS OFF.
RCS OFF.
SET globalThrottle TO 0.
setLockedThrottle(TRUE).
SET globalSteer TO -VELOCITY:SURFACE.
setLockedSteering(TRUE).
LOCAL mode IS 0.
LOCAL currentMargin IS 0.
LOCAL requiredVerticalVelocity IS 0.
LOCAL recordedData IS LEXICON().
recordedData:ADD("Apoapsis", APOAPSIS).
recordedData:ADD("Start TWR", shipInfo["Maximum"]["TWR"]).
recordedData:ADD("End TWR", 0).
recordedData:ADD("Start Altitude", 0).
recordedData:ADD("End Altitude", 0).
recordedData:ADD("Burn Time", 0).
recordedData:ADD("Burn Distance", 0).
recordedData:ADD("Safety Margin", margin).

FUNCTION advanceMode {
	SET mode TO mode + 1.
}

// When we are close to landing, prep the craft and stop time warp
WHEN aboveGround < 1000 THEN {
	GEAR ON.
	PANELS OFF.
	LIGHTS ON.
	KUNIVERSE:TIMEWARP:CANCELWARP().
}

CLEARSCREEN.
//LOCAL startTime IS MISSIONTIME.
//IF EXISTS("0:altitude.csv") DELETEPATH("0:altitude.csv").
//IF connectionToKSC() LOG "Time,mode,Altitude,Height Above Ground,Vertical Speed,Horizontal Speed,Ground Speed Magnitude,Pitch,Thrust,Mass,Suicide Burn Distance," +
//												 "Suicide Burn Time,Suicide Burn Delta V,Warp Rate,Warp Type,Throttle,RTTimeToBurn,Required Vertical Velocity" TO "0:altitude.csv".
//FUNCTION logInfo {
//	LOCAL message IS "".
//	SET message TO message + (missionTime - startTime).
//	SET message TO message + "," + mode.
//	SET message TO message + "," + ALTITUDE.
//	SET message TO message + "," + aboveGround.
//	SET message TO message + "," + VERTICALSPEED.
//	SET message TO message + "," + GROUNDSPEED.
//	IF VERTICALSPEED < 0 SET message TO message + "," + -VELOCITY:SURFACE:MAG.
//	ELSE                 SET message TO message + "," +  VELOCITY:SURFACE:MAG.
//	SET message TO message + "," + pitch_for(SHIP).
//	SET message TO message + "," + shipInfo["Current"]["Thrust"]..
//	SET message TO message + "," + MASS * 1000.
//	SET message TO message + "," + burnInfo["distance"].
//	SET message TO message + "," + burnInfo["time"].
//	SET message TO message + "," + burnInfo["deltaV"].
//	SET message TO message + "," + KUNIVERSE:TIMEWARP:RATE.
//	SET message TO message + "," + KUNIVERSE:TIMEWARP:MODE.
//	SET message TO message + "," + THROTTLE.
//	SET message TO message + "," + RTTimeToBurn.
//	SET message TO message + "," + requiredVerticalVelocity.
//	IF connectionToKSC() LOG message TO "0:altitude.csv".
//}

UNTIL mode > 3 {
	updateShipInfoCurrent().
	SET burnInfo TO SuicideBurnInfo().
	SET aboveGround TO heightAboveGround().
	SET currentMargin TO aboveground - evaluatePolynomial(burnInfo["distance"], burnDistanceCorrections) - margin.
	// If we are using the partial version, overestimate the distance it takes to stop.
	// Adding 1/9 of the burn distance should result in ~90% throttle during most of the burn.
	IF useVelocity SET currentMargin TO currentMargin - burnInfo["distance"] / 9.
	LOCAL v_e IS shipInfo["CurrentStage"]["Isp"] * g_0.
	LOCAL m_dot IS shipInfo["Maximum"]["mDot"].
	LOCAL m_i IS SHIP:MASS * 1000.
	LOCAL t IS burnInfo["time"].
	LOCAL x_i IS aboveGround.
	LOCAL x_f IS margin.
	LOCAL g_avg IS burnInfo["g_avg"].
	SET requiredVerticalVelocity TO 0.9*((x_f - v_e*(t - m_i/m_dot)*LN(m_i/(m_i - m_dot*t)) - x_i)/t - v_e + g_avg * t / 2.0).

	SET RTTimeToBurn TO currentMargin/(-VERTICALSPEED*KUNIVERSE:TIMEWARP:RATE).
//	IF useVelocity logPID(T_PID_Spd, "0:T_PID_Spd logfile.csv", TRUE, 2).
	IF VERTICALSPEED > 0 {
		SET RTTimeToBurn TO 10.
		PRINT "SB Mode: " + mode + "    Real Time to Burn: NA     " AT (0, 0).
	} ELSE {
		PRINT "SB Mode: " + mode + "    Real Time to Burn: " + timeToString(RTTimeToBurn) + "     " AT (0, 0).
	}
	PRINT "           Suicide Burn      Available        " AT (0, 1).
	PRINT "Distance:  " + ROUND(burnInfo["distance"]):TOSTRING:PADLEFT(12) + ROUND(aboveGround):TOSTRING:PADLEFT(15) + " m       " AT (0, 2).
	PRINT "Time:      " + ROUND(burnInfo["time"]):TOSTRING:PADLEFT(12) + ROUND(ABS(aboveGround/VERTICALSPEED)):TOSTRING:PADLEFT(15) +     " s       " AT (0, 3).
	PRINT "Delta V:   " + ROUND(burnInfo["deltaV"]):TOSTRING:PADLEFT(12) + ROUND(shipInfo["CurrentStage"]["DeltaV"]):TOSTRING:PADLEFT(15) +   " m/s     " AT (0, 4).
//	logInfo().

	IF recordedData["Apoapsis"] < APOAPSIS SET recordedData["Apoapsis"] TO APOAPSIS.

	// coast to close to ignition time. (within 1 second at current velocity)
	IF mode = 0 {
		SET globalSteer TO -VELOCITY:SURFACE.
		IF VERTICALSPEED < 0 AND KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE <> 0 AND RTTimeToBurn < 10 SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
		IF RTTimeToBurn < 10 AND VERTICALSPEED < -10 AND KUNIVERSE:TIMEWARP:RATE = 1 {
			SET KUNIVERSE:timewarp:warp TO 0.
			SET KUNIVERSE:timewarp:mode TO "PHYSICS".
			advanceMode().
		}
	}
	// wait for ignition time.
	IF mode = 1 {
		IF (GROUNDSPEED < 0.25) SET globalSteer TO SHIP:UP:VECTOR.
		ELSE SET globalSteer TO -VELOCITY:SURFACE.
		IF KUNIVERSE:TimeWarp:WARP <> 0 {
			SET KUNIVERSE:timewarp:mode TO "PHYSICS".
			SET KUNIVERSE:timewarp:warp TO 0.
		}
		IF currentMargin < 0.0 OR useVelocity AND (VERTICALSPEED) {
			advanceMode().
			SET recordedData["Burn Time"] TO burnInfo["time"].
			SET recordedData["Burn Distance"] TO burnInfo["distance"].
			SET recordedData["Start Altitude"] TO aboveGround.
			SET burnStartTime TO MISSIONTIME.
			IF useVelocity T_PID_Spd:RESET().
			IF KUNIVERSE:TimeWarp:WARP <> physicsWarpPerm {
				SET KUNIVERSE:timewarp:mode TO "PHYSICS".
				SET KUNIVERSE:timewarp:warp TO physicsWarpPerm.
			}
		}
	}
	// suicide burn
	IF mode = 2 {
		IF useVelocity {
			SET T_PID_Spd:SETPOINT TO requiredVerticalVelocity.
			IF VERTICALSPEED < 0 SET globalThrottle TO T_PID_Spd:UPDATE(TIME:SECONDS, -VELOCITY:SURFACE:MAG).
			ELSE                 SET globalThrottle TO T_PID_Spd:UPDATE(TIME:SECONDS, VELOCITY:SURFACE:MAG).
		} ELSE {
			SET globalThrottle TO 1.
			PRINT "Time remaining in burn:" AT (0, 5).
			PRINT timeToString(recordedData["Burn Time"] - (MISSIONTIME - burnStartTime), 2):PADLEFT(23) + "     " AT (0, 6).
		}
		IF (GROUNDSPEED < 0.1) SET globalSteer TO SHIP:UP:VECTOR.
		ELSE {
			LOCAL pitchOffset IS 0.
			IF GROUNDSPEED < 1 					SET pitchOffset TO 1.
			ELSE IF GROUNDSPEED < 10 		SET pitchOffset TO 2.
			ELSE IF GROUNDSPEED < 100		SET pitchOffset TO 5.
			ELSE 												SET pitchOffset TO 10.
			SET globalSteer TO HEADING(yaw_for(-VELOCITY:SURFACE), pitch_for(-VELOCITY:SURFACE) - pitchOffset).
		}
		IF VERTICALSPEED > 0 OR aboveGround < 0.5 OR (NOT useVelocity AND ABS(recordedData["Burn Time"] - (MISSIONTIME - burnStartTime)) < 0.1) {
			advanceMode().
			SET recordedData["End TWR"] TO shipInfo["Maximum"]["TWR"].
			SET recordedData["End Altitude"] TO aboveGround.
			IF connectionToKSC() LOG "" + recordedData["Apoapsis"] + "," + recordedData["Start TWR"] + "," + recordedData["End TWR"] +
			                         "," + recordedData["Start Altitude"] + "," + recordedData["End Altitude"] + "," + recordedData["Burn Time"] +
															 "," + recordedData["Burn Distance"] + "," + recordedData["Safety Margin"] + "," + SHIP:GEOPOSITION:TERRAINHEIGHT +
															 "," + BODY:NAME + "," + useVelocity TO "0:suicideBurnCalcs.csv".
			SET globalThrottle TO 0.
			WAIT 0.
		}
	}
	// constant speed descent
	IF mode = 3 {
		IF useVelocity advanceMode().
		IF aboveGround > 5 SET T_PID_Spd:SETPOINT TO -1.
		IF aboveGround > 50 SET T_PID_Spd:SETPOINT TO -10.
		IF aboveGround > 500 SET T_PID_Spd:SETPOINT TO -25.
		IF aboveGround > 1000 SET T_PID_Spd:SETPOINT TO -50.
		PRINT "Vertical Velocity Setpoint: " + ROUND(T_PID_Spd:SETPOINT, 2) AT (0, 6).
		SET globalThrottle TO T_PID_Spd:UPDATE(TIME:SECONDS, VERTICALSPEED).
		IF (GROUNDSPEED < 0.1) SET globalSteer TO SHIP:UP:VECTOR.
		ELSE SET globalSteer TO -VELOCITY:SURFACE.
		IF aboveGround < 0.5 advanceMode().
	}
}
SET globalSteer TO HEADING(90, 90).
SET globalThrottle TO 0.
WAIT 5.
PANELS ON.
SET loopMessage TO "SB Ended: " + distanceToString(recordedData["End Altitude"]) + " above ground".
