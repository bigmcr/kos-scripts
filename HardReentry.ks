@LAZYGLOBAL OFF.

CLEARSCREEN.

LOCAL desiredPeri IS 60000.
LOCAL facePrograde IS false.

setLockedSteering(TRUE).

SAS OFF.
RCS ON.

// If the current periapsis is not within 1km of the desired periapsis, use RCS to adjust periapsis
IF (ABS(PERIAPSIS - desiredPeri) > 1000) {
	PRINT "Periapsis Incorrect, adjusting using RCS".
	SET globalSteer TO SHIP:VELOCITY:ORBIT.
	PRINT "Pointing Prograde".
	waitUntilFinishedRotating().
	PRINT "Raising Periapsis".
	UNTIL PERIAPSIS < desiredPeri {
		IF (PERIAPSIS > desiredPeri + 20000) SET SHIP:CONTROL:FORE TO -1.
		ELSE SET SHIP:CONTROL:FORE TO -0.25.
	}

	PRINT "Lowering Periapsis".
	UNTIL PERIAPSIS > desiredPeri {
		IF (PERIAPSIS < desiredPeri - 5000) SET SHIP:CONTROL:FORE TO 1.
		ELSE SET SHIP:CONTROL:FORE TO 0.25.
	}

	// After periapsis adjustment, kill all FORE control
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
}

RCS OFF.

PRINT "Locking steering to the primary".
SET globalSteer TO BODY("Sun"):DIRECTION.

waitUntilFinishedRotating().

PRINT "Warping to 5 minutes before periapsis".
warpToTime(TIME:SECONDS + ETA:PERIAPSIS - 5 * 60).

IF NOT facePrograde {
	PRINT "Locking steering to surface retrograde".
	// for the first part, set steering to surface retrograde
	SET globalSteer TO -SHIP:VELOCITY:SURFACE.
} ELSE {
	PRINT "Locking steering to surface prograde".
	// for the first part, set steering to surface retrograde
	SET globalSteer TO SHIP:VELOCITY:SURFACE.
}

SAS OFF.
RCS ON.

waitUntilFinishedRotating().

SET SHIP:CONTROL:PITCH TO 0.
SET SHIP:CONTROL:YAW TO 0.

LOCAL prevVelocity IS 0.
LOCAL prevTime IS 0.

UNTIL ALTITUDE < 20000 AND SHIP:VELOCITY:SURFACE:MAG < 1000 {
	SAS OFF.
	IF (prevTime <> 0) PRINT "Current Accel: " + ROUND((prevVelocity - SHIP:VELOCITY:SURFACE):MAG/(prevTime - TIME:SECONDS),2) + "     " AT (0, 10).
	SET prevVelocity TO SHIP:VELOCITY:SURFACE.
	SET prevTime TO TIME:SECONDS.
	WAIT 0.1.
}
stageFunction().													// this is supposed to trigger the parachutes
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
