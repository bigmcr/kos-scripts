@LAZYGLOBAL OFF.

PARAMETER isActiveShip IS FALSE.	// IF true, this is the ship that matches orientation with the other.
PARAMETER useRCS IS TRUE.			// whether or not to use RCS for rotation while docking.

CLEARSCREEN.

LOCAL targetDistance IS V(0,0,0).
LOCK targetDistance TO TARGET:POSITION - SHIP:CONTROLPART:POSITION.

LOCAL targetVelocity IS V(0,0,0).
IF TARGET:TYPENAME = "DockingPort" LOCK targetVelocity TO TARGET:SHIP:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT.
ELSE LOCK targetVelocity TO TARGET:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT.

SET mySteer TO SHIP:FACING.
SET myThrottle TO 0.
SET useMySteer TO TRUE.
SET useMyThrottle TO TRUE.

SET RCS TO useRCS.
SAS OFF.

FUNCTION getDirDistance {
	IF NOT HASTARGET RETURN V(0,0,0).
	RETURN V(SHIP:FACING:FOREVECTOR * targetDistance, SHIP:FACING:TOPVECTOR * targetDistance, SHIP:FACING:STARVECTOR * targetDistance).
}

FUNCTION getDirVelocity {
	IF NOT HASTARGET RETURN V(0,0,0).
	RETURN V(SHIP:FACING:FOREVECTOR * targetVelocity, SHIP:FACING:TOPVECTOR * targetVelocity, SHIP:FACING:STARVECTOR * targetVelocity).
}

LOCAL foreVector IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), YELLOW, "Fore", 1.0, TRUE, 0.2).
LOCAL topVector  IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), RED, "Top" , 1.0, TRUE, 0.2).
LOCAL stbdVector IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), BLUE, "Stbd", 1.0, TRUE, 0.2).
LOCAL tgtVector  IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), GREEN, "Target", 1.0, TRUE, 0.2).
LOCAL tgtFacing  IS VECDRAW(V(0,0,0), V(0,0,0), PURPLE, "Target Facing", 1.0, TRUE, 0.2).
LOCAL velocityPID IS PIDLOOP(0.3, 0.01, 0.0625, -1, 1).
LOCAL positionPID IS PIDLOOP(0.03, 0.05, 0.625, -0.5, 0.5).
SET positionPID:SETPOINT TO 0.
// there are multiple modes
// Orientation - make sure you are pointed in the correct position
// Positioning - ensure you are exactly 10 meters in front of the target
//     Positioning Fore - go forward or backward until until 10 meters from the target in the fore direction
//     Positioning Starboard - go left or right until directly in front of the target
//	   Positioning Top - go up and down until directly in front of the target
// Final docking - final approach from directly in front, very slow
LOCAL mode IS "Orientation".
LOCAL startTime IS TIME:SECONDS.
LOCAL oldTime IS TIME:SECONDS.
LOCAL elapsedTime IS TIME:SECONDS - startTime.
LOCAL oldDistance IS getDirDistance().
LOCAL dirDistance IS getDirDistance().
LOCAL dirVelocity IS V(0,0,0).
LOCAL startPartCount TO SHIP:PARTS:LENGTH.
LOCAL logFileName IS "0:Docking.csv".
LOCK mySteer TO (-(TARGET:FACING:VECTOR)):DIRECTION.

ON (NOT HASTARGET) {
	SET mode TO "Done".
}

IF connectionToKSC() LOG "Elapsed Time,Position PID Setpoint,Position PID Input,Position PID Output,Velocity PID Setpoint,Velocity PID Input,Velocity PID Output" TO logFileName.

UNTIL mode = "Done" {
	SET dirDistance TO getDirDistance().
	SET elapsedTime TO TIME:SECONDS - startTime.
	SET dirVelocity TO getDirVelocity().
	IF (debug) {
		PRINT "      Distance  Velocity" AT (0, 0).
		PRINT "Fore  " + ROUND(dirDistance:X, 2):TOSTRING:PADRIGHT(8) + "  " + ROUND(dirVelocity:X, 3):TOSTRING:PADRIGHT(8) AT (0, 1).
		PRINT "Top   " + ROUND(dirDistance:Y, 2):TOSTRING:PADRIGHT(8) + "  " + ROUND(dirVelocity:Y, 3):TOSTRING:PADRIGHT(8) AT (0, 2).
		PRINT "Stbd  " + ROUND(dirDistance:Z, 2):TOSTRING:PADRIGHT(8) + "  " + ROUND(dirVelocity:Z, 3):TOSTRING:PADRIGHT(8) AT (0, 3).
		PRINT "Modes " + mode AT (0, 4).
		PRINT "Time Left " + ROUND(200 - elapsedTime, 1) + "  " AT (0, 5).
	}
	IF mode = "Orientation" {
		waitUntilFinishedRotating().
		SET mode TO "PositioningFore".
//		SET SHIP:CONTROL:FORE TO 0.0.
	}
	IF mode = "PositioningFore" {
		SET foreVector:START TO SHIP:CONTROLPART:POSITION.
		SET topVector:START TO SHIP:CONTROLPART:POSITION.
		SET stbdVector:START TO SHIP:CONTROLPART:POSITION.
		SET tgtVector:START TO SHIP:CONTROLPART:POSITION.

		SET positionPID:SETPOINT TO 10.
		SET velocityPID:SETPOINT TO positionPID:UPDATE(elapsedTime, dirDistance:X).
//		SET SHIP:CONTROL:FORE TO -velocityPID:UPDATE(elapsedTime, dirVelocity:X).
		IF connectionToKSC() LOG elapsedTime + "," + positionPID:Setpoint + "," + positionPID:Input + "," + positionPID:Output + "," + velocityPID:Setpoint + "," + velocityPID:Input + "," + -velocityPID:Output TO logFileName.
	}
	IF mode = "Final Docking" {
	}
	SET topVector:VEC TO SHIP:FACING:TOPVECTOR*5.0.
	SET foreVector:VEC TO SHIP:FACING:FOREVECTOR*5.0.
	SET stbdVector:VEC TO SHIP:FACING:STARVECTOR*5.0.
	SET tgtVector:VEC TO TARGET:POSITION - SHIP:CONTROLPART:POSITION.
	SET tgtFacing:START TO TARGET:POSITION.
	SET tgtFacing:VEC TO TARGET:FACING:VECTOR * 5.0.
	IF (TIME:SECONDS > startTime + 200) OR (SHIP:PARTS:LENGTH <> startPartCount) SET mode TO "Done".
	SET oldTime TO TIME:SECONDS.
	SET oldDistance TO getDirDistance().
	WAIT 0.
}
