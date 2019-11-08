CLEARSCREEN.

SAS OFF.
RCS ON.

// for the first part, lock steering to surface retrograde

LOCK mySteer TO -SHIP:VELOCITY:SURFACE.

UNTIL ALTITUDE < 110000 {
	PRINT "Cooked Steering, Level" AT(0,0).
	WAIT 0.5.
}

LOCK mySteer TO HEADING(yaw_for(SHIP), 30).

UNTIL ALTITUDE < 100000 {
	PRINT "Cooked Steering, Angled" AT(0,0).
	WAIT 0.5.
}

PRINT "Manual Steering" AT (0,0).

UNLOCK mySteer.

GLOBAL rollTorquePID TO PIDLOOP(2, 0.3, 0, -1, 1).
GLOBAL rollVelocityPID TO PIDLOOP(0.03, 0.01, 0.0625, -0.5, 0.5).
GLOBAL rollVelocity TO SHIP:ANGULARVEL * SHIP:FACING:VECTOR.
SET rollVelocityPID:SETPOINT TO 0.

// set the first three action groups to substitute for the first PID
// this is solely for testing
ON AG1 {SET rollVelocityPID:Setpoint TO rollVelocityPID:Setpoint + 5. RETURN TRUE.}
ON AG2 {SET rollVelocityPID:Setpoint TO rollVelocityPID:Setpoint - 5. RETURN TRUE.}
ON AG3 {rollVelocityPID:RESET(). RETURN TRUE.}
ON AG4 {SET rollTorquePID:Kp TO rollTorquePID:Kp + 0.25. RETURN TRUE.}
ON AG5 {SET rollTorquePID:Kp TO rollTorquePID:Kp - 0.25. RETURN TRUE.}
ON AG6 {SET rollTorquePID:Ki TO rollTorquePID:Ki + 0.02. RETURN TRUE.}
ON AG7 {SET rollTorquePID:Ki TO rollTorquePID:Ki - 0.02. RETURN TRUE.}
ON AG8 {SET rollTorquePID:Kd TO rollTorquePID:Kd + 0.02. RETURN TRUE.}
ON AG9 {SET rollTorquePID:Kd TO rollTorquePID:Kd - 0.02. RETURN TRUE.}

CLEARSCREEN.

SET SHIP:CONTROL:ROLL TO 0.
SET SHIP:CONTROL:PITCH TO 0.
SET SHIP:CONTROL:YAW TO 0.

GLOBAL COUNT IS 0.

// this function assumes that you have an appropriate heatshield and that the "descent mode" on the pod is turned on
// this function solely controls roll to maintain the lift vector pointing up
SAS OFF.
RCS OFF.

SET SHIP:CONTROL:PITCH TO 0.
SET SHIP:CONTROL:YAW TO 0.

UNTIL ALTITUDE < 20000 AND SHIP:VELOCITY:SURFACE:MAG < 1000 {
	SAS OFF.
	SET rollVelocityPID:SETPOINT TO 0.
	SET rollVelocity TO SHIP:ANGULARVEL * SHIP:FACING:VECTOR.		// set the roll velocity to the angular velocity around FACING.
	SET rollTorquePID:SETPOINT TO -rollVelocityPID:Update(time:seconds, roll_for(SHIP)).
	SET SHIP:CONTROL:ROLL TO -rollTorquePID:Update(time:seconds, rollVelocity).
	printPID(rollTorquePID, "Roll Torque", 0, 2).
	printPID(rollVelocityPID, "Roll Velocity", 20, 2).
	logPID(rollTorquePID, "logs/rollTorquePID.csv", 0).
	logPID(rollVelocityPID, "logs/rollVelocityPID.csv", 1).
	PRINT "Logged " + COUNT + " data sets." AT (0, 1).
	WAIT 0.
	SET COUNT TO COUNT + 1.
}.
stageFunction().																// this is supposed to trigger the parachutes
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot


UNTIL heightAboveGround() < 100 {
	SET mySteer TO -SHIP:VELOCITY:SURFACE.
	WAIT 0.1.
	IF (NOT CHUTESSAFE) {CHUTESSAFE ON.}
}