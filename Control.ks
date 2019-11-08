RUNONCEPATH("library.ks").

GLOBAL rollTorquePID TO PIDLOOP(20, 3, 0, -1, 1).
GLOBAL rollVelocityPID TO PIDLOOP(0.003, 0.1, 0.8625, -0.5, 0.5).
GLOBAL rollVelocity TO SHIP:ANGULARVEL * SHIP:FACING:VECTOR.
SET rollVelocityPID:SETPOINT TO 0.

// set the first three action groups to substitute for the first PID
// this is solely for testing
ON AG1 {SET rollVelocityPID:Setpoint TO rollVelocityPID:Setpoint + 5. RETURN TRUE.}
ON AG2 {SET rollVelocityPID:Setpoint TO rollVelocityPID:Setpoint - 5. RETURN TRUE.}
ON AG3 {rollVelocityPID:RESET(). RETURN TRUE.}
ON AG4 {SET rollTorquePID:Kp TO rollTorquePID:Kp + 0.025. RETURN TRUE.}
ON AG5 {SET rollTorquePID:Kp TO rollTorquePID:Kp - 0.025. RETURN TRUE.}
ON AG6 {SET rollTorquePID:Ki TO rollTorquePID:Ki + 0.02. RETURN TRUE.}
ON AG7 {SET rollTorquePID:Ki TO rollTorquePID:Ki - 0.02. RETURN TRUE.}
ON AG8 {SET rollTorquePID:Kd TO rollTorquePID:Kd + 0.02. RETURN TRUE.}
ON AG9 {SET rollTorquePID:Kd TO rollTorquePID:Kd - 0.02. RETURN TRUE.}

CLEARSCREEN.

SAS OFF.
RCS OFF.

SET SHIP:CONTROL:ROLL TO 0.
SET SHIP:CONTROL:PITCH TO 0.
SET SHIP:CONTROL:YAW TO 0.

GLOBAL COUNT IS 0.

UNTIL FALSE {
	SAS OFF.
	SET rollVelocity TO SHIP:ANGULARVEL * SHIP:FACING:VECTOR.		// set the roll velocity to the angular velocity around FACING.
	SET rollTorquePID:SETPOINT TO -rollVelocityPID:Update(time:seconds, roll_for(SHIP)).
	SET SHIP:CONTROL:ROLL TO -rollTorquePID:Update(time:seconds, rollVelocity).
	printPID(rollTorquePID, "Roll Torque", 0, 1).
	printPID(rollVelocityPID, "Roll Velocity", 20, 1).
	logPID(rollTorquePID, "logs/rollTorquePID.csv", 0).
	logPID(rollVelocityPID, "logs/rollVelocityPID.csv", 1).
	PRINT "Logged " + COUNT + " data sets." AT (0, 0).
	SET COUNT TO COUNT + 1.
}.
