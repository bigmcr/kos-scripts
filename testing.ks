@LAZYGLOBAL OFF.

LOCAL maxGs IS 1.25.
LOCAL body_g IS CONSTANT:G * SHIP:BODY:MASS/(SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).

SET globalThrottle TO 1.0.

setLockedThrottle(TRUE).
setLockedSteering(TRUE).

UNTIL FALSE {
	SET globalSteer TO SHIP:UP.
	updateShipInfoCurrent(TRUE).
	PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"], 4) + " m/s^2    " AT (0, 11).
	PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"], 4) + " m/s^2    " AT (0, 12).
	PRINT "Current Accel " + ROUND(shipInfo["Current"]["Accel"]/body_g, 4) + " g's      " AT (0, 13).
	PRINT "Maximum Accel " + ROUND(shipInfo["Maximum"]["Accel"]/body_g, 4) + " g's      " AT (0, 14).
	
	// attempt at calculating the throttle to ensure maxGs acceleration at most
	// note that maxGs is relative to sea level on THIS BODY, not Earth/Kerbin.
	// desired throttle = (maxGs + body_g - accel from SRBs)/available accel from variable engines
	IF (shipInfo["Maximum"]["Variable"]["Accel"] <> 0) {
		SET globalThrottle TO (maxGs*body_g - shipInfo["Current"]["Constant"]["Accel"]) / shipInfo["Maximum"]["Variable"]["Accel"].
	} ELSE SET globalThrottle TO 1.
	SET globalThrottle TO MIN( MAX( globalThrottle, 0.05), 1.0).

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
}