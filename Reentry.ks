@LAZYGLOBAL OFF.

CLEARSCREEN.

PARAMETER desiredPeri IS 55000.
PARAMETER facePrograde IS FALSE.
PARAMETER hardReentry IS FALSE.

SAS OFF.
RCS ON.

setLockedSteering(TRUE).

// If the current periapsis is not within 1km of the desired periapsis, use RCS to adjust periapsis
IF (ABS(PERIAPSIS - desiredPeri) > 1000) {
	PRINT "Periapsis Incorrect, adjusting using RCS".
	SET globalSteer TO SHIP:VELOCITY:ORBIT.
	PRINT "Pointing Prograde".
	waitUntilFinishedRotating().
	PRINT "Lowering Periapsis".
	UNTIL PERIAPSIS < desiredPeri {
		IF (PERIAPSIS > desiredPeri + 20000) SET SHIP:CONTROL:FORE TO -1.
		ELSE SET SHIP:CONTROL:FORE TO -0.25.
	}

	PRINT "Raising Periapsis".
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

IF NOT hardReentry {
	PRINT "Cooked Steering, Level" AT(0,0).
//	WAIT UNTIL ALTITUDE < 110000 {

	SET globalSteer TO HEADING(yaw_for(SHIP), 30).

	PRINT "Cooked Steering, Angled" AT(0,0).
//	WAIT UNTIL ALTITUDE < 100000 {

	PRINT "Manual Steering" AT (0,0).

	setLockedSteering(FALSE).

	GLOBAL rollTorquePID TO PIDLOOP(2, 0.3, 0, -1, 1).
	GLOBAL rollVelocityPID TO PIDLOOP(0.03, 0.01, 0.0625, -0.5, 0.5).
	GLOBAL rollVelocity TO SHIP:ANGULARVEL * SHIP:FACING:VECTOR.
	SET rollVelocityPID:SETPOINT TO 0.

	// set the first three action groups to substitute for the first PID

	CLEARSCREEN.

	SET SHIP:CONTROL:ROLL TO 0.
	SET SHIP:CONTROL:PITCH TO 0.
	SET SHIP:CONTROL:YAW TO 0.

	// this function assumes that you have an appropriate heatshield and that the "descent mode" on the pod is turned on
	// this function solely controls roll to maintain the lift vector pointing up
	SAS OFF.
	RCS OFF.

	SET SHIP:CONTROL:PITCH TO 0.
	SET SHIP:CONTROL:YAW TO 0.
} ELSE {
	SET globalSteer TO -SHIP:VELOCITY:SURFACE.
}

UNTIL ALTITUDE < 20000 AND SHIP:VELOCITY:SURFACE:MAG < 1000 {
	SAS OFF.
	SET rollVelocityPID:SETPOINT TO 0.
	SET rollVelocity TO SHIP:ANGULARVEL * SHIP:FACING:VECTOR.		// set the roll velocity to the angular velocity around FACING.
	SET rollTorquePID:SETPOINT TO -rollVelocityPID:Update(time:seconds, roll_for(SHIP)).
	SET SHIP:CONTROL:ROLL TO -rollTorquePID:Update(time:seconds, rollVelocity).
	WAIT 0.
}
stageFunction().																// this is supposed to trigger the parachutes
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot

UNTIL heightAboveGround() < 100 {
	SET globalSteer TO -SHIP:VELOCITY:SURFACE.
	WAIT 0.1.
	IF (NOT CHUTESSAFE) {CHUTESSAFE ON.}
}
