@LAZYGLOBAL OFF.

CLEARSCREEN.

LOCAL targetDistance IS V(0,0,0).
LOCK targetDistance TO TARGET:POSITION - SHIP:CONTROLPART:POSITION.

LOCAL targetVelocity IS V(0,0,0).
LOCAL oldControlTime IS TIME:SECONDS.
IF TARGET:TYPENAME = "DockingPort" LOCK targetVelocity TO TARGET:SHIP:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT.
ELSE LOCK targetVelocity TO TARGET:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT.

LOCAL foreDirectionVector IS -TARGET:FACING:FOREVECTOR.
LOCAL topDirectionVector IS TARGET:FACING:TOPVECTOR.
LOCAL starboardDirectionVector IS TARGET:FACING:STARVECTOR.

PRINT "Angle between Fore and Top: " + VANG(foreDirectionVector, topDirectionVector).
PRINT "Angle between Fore and Starboard: " + VANG(foreDirectionVector, starboardDirectionVector).
PRINT "Angle between Top and Starboard: " + VANG(topDirectionVector, starboardDirectionVector).

WAIT 1.

SET globalSteer TO -foreDirectionVector.
SET globalThrottle TO 0.
setLockedThrottle(TRUE).
setLockedSteering(TRUE).

SET RCS TO TRUE.
SAS OFF.

FUNCTION getDirDistance {
	IF NOT HASTARGET RETURN V(0,0,0).
	RETURN V(foreDirectionVector * targetDistance, topDirectionVector * targetDistance, starboardDirectionVector * targetDistance).
}

FUNCTION getDirVelocity {
	IF NOT HASTARGET RETURN V(0,0,0).
	RETURN V(foreDirectionVector * targetVelocity, topDirectionVector * targetVelocity, starboardDirectionVector * targetVelocity).
}

FUNCTION getRCSThrusts {
	LOCAL RCSThrusters IS LIST().
	LIST RCS IN RCSThrusters.
	LOCAL maxRCSThrust IS LEXICON("Fore", 0, "Top", 0, "Starboard", 0).
	FOR eachRCS IN RCSThrusters {
		IF eachRCS:ENABLED {
			IF eachRCS:FOREENABLED SET maxRCSThrust["Fore"] TO maxRCSThrust["Fore"] + eachRCS:AVAILABLETHRUST * 1000.
			IF eachRCS:TOPENABLED SET maxRCSThrust["Top"] TO maxRCSThrust["Top"] + eachRCS:AVAILABLETHRUST * 1000.
			IF eachRCS:STARBOARDENABLED SET maxRCSThrust["Starboard"] TO maxRCSThrust["Starboard"] + eachRCS:AVAILABLETHRUST * 1000.
		}
	}
	RETURN maxRCSThrust.
}

FUNCTION PWMOutput {
    PARAMETER magnitude.
    PARAMETER threshold.
    PARAMETER period IS 1.0.

    LOCAL dutyCycle IS magnitude / threshold.
    IF dutyCycle < 0 { SET dutyCycle TO 0. }
    IF dutyCycle > 1 { SET dutyCycle TO 1. }

    LOCAL phase IS MOD(TIME:SECONDS, period) / period.

    RETURN phase < dutyCycle.
}

FUNCTION modulateInput {
    PARAMETER input.
    PARAMETER threshold.
    PARAMETER period IS 1.
	
	IF threshold < 0 SET threshold TO -threshold.

    IF ABS(input) >= threshold RETURN input.

    LOCAL sign IS 1.
    IF input < 0 SET sign TO -1.

    IF PWMOutput(ABS(input), threshold, period) {
		RETURN threshold * sign.
    } ELSE RETURN 0.
}

LOCAL foreVector IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), YELLOW, "Fore", 1.0, TRUE, 0.2).
LOCAL topVector  IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), RED, "Top" , 1.0, TRUE, 0.2).
LOCAL StarboardVector IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), BLUE, "Starboard", 1.0, TRUE, 0.2).
LOCAL tgtVector  IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), GREEN, "Target", 1.0, TRUE, 0.2).
LOCAL tgtFacing  IS VECDRAW(V(0,0,0), V(0,0,0), PURPLE, "Target Facing", 1.0, TRUE, 0.2).
LOCAL driftVelocity IS 0.125.
LOCAL maxVelocity IS V(driftVelocity * 4, driftVelocity * 4, driftVelocity * 4).
LOCAL positionKp IS 0.06671.
LOCAL positionKi IS 0.00509.
LOCAL positionKd IS 0.5767.
LOCAL RCSdeadband IS 0.05.

LOCAL timeOutTime IS 400. // seconds.

LOCAL positionPID IS LEXICON().
positionPID:ADD("Fore",       	PIDLOOP(positionKp, positionKi, positionKd, -maxVelocity:X, maxVelocity:X)).
positionPID:ADD("Top",        	PIDLOOP(positionKp, positionKi, positionKd, -maxVelocity:Y, maxVelocity:Y)).
positionPID:ADD("Starboard", 	PIDLOOP(positionKp, positionKi, positionKd, -maxVelocity:Z, maxVelocity:Z)).

SET positionPID["Fore"]:SETPOINT TO 0.
SET positionPID["Top"]:SETPOINT TO 0.
SET positionPID["Starboard"]:SETPOINT TO 0.

LOCAL velocityKp IS 0.7958.
LOCAL velocityKi IS 1.2434.
LOCAL velocityKd IS 0.3361.
LOCAL velocityPID IS LEXICON().
velocityPID:ADD("Fore", 		PIDLOOP(velocityKp, velocityKi, velocityKd, -0.1, 0.1, driftVelocity)).
velocityPID:ADD("Top", 			PIDLOOP(velocityKp, velocityKi, velocityKd, -0.1, 0.1, driftVelocity)).
velocityPID:ADD("Starboard", 	PIDLOOP(velocityKp, velocityKi, velocityKd, -0.1, 0.1, driftVelocity)).

LOCAL velocityPIDAuto IS LEXICON().
velocityPIDAuto:ADD("Fore", TRUE).
velocityPIDAuto:ADD("Top", TRUE).
velocityPIDAuto:ADD("Starboard", TRUE).
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

ON (NOT HASTARGET) {
	SET mode TO "Done".
}

IF connectionToKSC() LOG "Elapsed Time,Position PID Setpoint,Position PID Input,Position PID Output,Velocity PID Setpoint,Velocity PID Input,Velocity PID Output" TO logFileName.

UNTIL mode = "Done" {
	SET foreVector:VEC TO foreDirectionVector*5.0.
	SET topVector:VEC TO topDirectionVector*5.0.
	SET starboardVector:VEC TO starboardDirectionVector*5.0.
	SET tgtVector:VEC TO TARGET:POSITION - SHIP:CONTROLPART:POSITION.
	SET tgtFacing:START TO TARGET:POSITION.
	SET tgtFacing:VEC TO TARGET:FACING:VECTOR * 5.0.

	SET dirDistance TO getDirDistance().
	SET dirVelocity TO getDirVelocity().
	SET elapsedTime TO TIME:SECONDS - startTime.
	SET foreVector:START TO SHIP:CONTROLPART:POSITION.
	SET topVector:START TO SHIP:CONTROLPART:POSITION.
	SET StarboardVector:START TO SHIP:CONTROLPART:POSITION.
	SET tgtVector:START TO SHIP:CONTROLPART:POSITION.

	PRINT "        Distance  Velocity    Output   In Auto" AT (0, 0).
	PRINT "Fore  " + ROUND(dirDistance:X, 2):TOSTRING:PADLEFT(10) + ROUND(dirVelocity:X, 3):TOSTRING:PADLEFT(10) + ROUND(velocityPID["Fore"]:OUTPUT, 3):TOSTRING:PADLEFT(10) + velocityPIDAuto["Fore"]:TOSTRING:PADLEFT(10) AT (0, 1).
	PRINT "Top   " + ROUND(dirDistance:Y, 2):TOSTRING:PADLEFT(10) + ROUND(dirVelocity:Y, 3):TOSTRING:PADLEFT(10) + ROUND(velocityPID["Top"]:OUTPUT, 3):TOSTRING:PADLEFT(10) + velocityPIDAuto["Top"]:TOSTRING:PADLEFT(10) AT (0, 2).
	PRINT "Stbd  " + ROUND(dirDistance:Z, 2):TOSTRING:PADLEFT(10) + ROUND(dirVelocity:Z, 3):TOSTRING:PADLEFT(10) + ROUND(velocityPID["Starboard"]:OUTPUT, 3):TOSTRING:PADLEFT(10) + velocityPIDAuto["Starboard"]:TOSTRING:PADLEFT(10) AT (0, 3).
	PRINT "Mode " + mode:PADRIGHT(20) AT (0, 4).
	PRINT "Time Left " + ROUND(timeOutTime - elapsedTime, 1) + "  " AT (0, 5).
	logPID(positionPID["Fore"], "0:Position - Fore.csv").
	logPID(positionPID["Top"], "0:Position - Top.csv").
	logPID(positionPID["Starboard"], "0:Position - Starboard.csv").
	logPID(velocityPID["Fore"], "0:Velocity - Fore.csv").
	logPID(velocityPID["Top"], "0:Velocity - Top.csv").
	logPID(velocityPID["Starboard"], "0:Velocity - Starboard.csv").
	printPID(positionPID["Fore"], "Fore Position", 0, 15).
	printPID(positionPID["Top"], "Top Position", 25, 15).
	printPID(positionPID["Starboard"], "Starboard Position", 50, 15).
	printPID(velocityPID["Fore"], "Fore Velocity", 0, 30).
	printPID(velocityPID["Top"], "Top Velocity", 25, 30).
	printPID(velocityPID["Starboard"], "Starboard Velocity", 50, 30).
	IF mode = "Orientation" {
		SET velocityPIDAuto["Fore"] TO FALSE.
		SET velocityPID["Fore"]:SETPOINT TO 0.
		SET velocityPIDAuto["Top"] TO FALSE.
		SET velocityPID["Top"]:SETPOINT TO 0.
		SET velocityPIDAuto["Starboard"] TO FALSE.
		SET velocityPID["Starboard"]:SETPOINT TO 0.
		CLEARSCREEN.
		PRINT "Starting WaitUntilFinishedRotating".
		waitUntilFinishedRotating().
		PRINT "WaitUntilFinishedRotating is complete".
		WAIT 1.
		SET mode TO "PositioningFore".
		SET mode TO "Stabilize".
		SET velocityPIDAuto["Fore"] TO TRUE.
		SET velocityPIDAuto["Top"] TO FALSE.
		SET velocityPID["Top"]:SETPOINT TO 0.
		SET velocityPIDAuto["Starboard"] TO FALSE.
		SET velocityPID["Starboard"]:SETPOINT TO 0.
	}
	IF mode = "Stabilize" {
		SET velocityPIDAuto["Fore"] TO FALSE.
		SET velocityPID["Fore"]:SETPOINT TO 0.
		SET velocityPIDAuto["Top"] TO FALSE.
		SET velocityPID["Top"]:SETPOINT TO 0.
		SET velocityPIDAuto["Starboard"] TO FALSE.
		SET velocityPID["Starboard"]:SETPOINT TO 0.

		IF ABS(dirVelocity:MAG) < 0.1 {
			SET velocityPIDAuto["Fore"] TO TRUE.
			SET velocityPIDAuto["Top"] TO TRUE.
			SET velocityPIDAuto["Starboard"] TO TRUE.
			SET mode TO "PositioningFore".
		}
	}
	IF mode = "PositioningFore" {
		SET positionPID["Fore"]:SETPOINT TO 10.
		SET positionPID["Top"]:SETPOINT TO dirDistance:Y.
		SET positionPID["Starboard"]:SETPOINT TO dirDistance:Z.
		
		IF ABS(dirDistance:X - positionPID["Fore"]:SETPOINT) < 1.0 AND ABS(dirVelocity:X) < 0.1 {
			SET velocityPIDAuto["Fore"] TO TRUE.
			SET velocityPIDAuto["Top"] TO TRUE.
			SET velocityPIDAuto["Starboard"] TO TRUE.
			SET mode TO "Positioning Starboard and Top".
		}
	}
	IF mode = "Positioning Starboard and Top" {
		SET positionPID["Fore"]:SETPOINT TO 10.
		SET positionPID["Top"]:SETPOINT TO 0.
		SET positionPID["Starboard"]:SETPOINT TO 0.
		
		IF ABS(dirDistance:MAG - 10) < 1.0 AND dirVelocity:MAG < 0.1 {
			SET velocityPIDAuto["Fore"] TO FALSE.
			SET velocityPID["Fore"]:SETPOINT TO -driftVelocity.
			SET velocityPIDAuto["Top"] TO TRUE.
			SET velocityPIDAuto["Starboard"] TO TRUE.
			SET mode TO "Final Docking".
		}
	}
	IF mode = "Final Docking" {
		SET positionPID["Fore"]:SETPOINT TO 0.25.
		SET positionPID["Top"]:SETPOINT TO 0.
		SET positionPID["Starboard"]:SETPOINT TO 0.
		IF ABS(dirDistance:MAG - 0.5) < 0.1 AND dirVelocity:MAG < 0.1 {
			SET velocityPIDAuto["Fore"] TO FALSE.
			SET velocityPIDAuto["Top"] TO FALSE.
			SET velocityPIDAuto["Starboard"] TO FALSE.
			SET mode TO "Done".
		}
	}

	IF velocityPIDAuto["Fore"] 			SET velocityPID["Fore"]:SETPOINT 		TO positionPID["Fore"]:UPDATE(elapsedTime, dirDistance:X).
	IF velocityPIDAuto["Top"] 			SET velocityPID["Top"]:SETPOINT 		TO positionPID["Top"]:UPDATE(elapsedTime, dirDistance:Y).
	IF velocityPIDAuto["Starboard"] 	SET velocityPID["Starboard"]:SETPOINT  TO positionPID["Starboard"]:UPDATE(elapsedTime, dirDistance:Z).

	velocityPID["Fore"]:UPDATE(elapsedTime, dirVelocity:X).
	velocityPID["Top"]:UPDATE(elapsedTime, dirVelocity:Y).
	velocityPID["Starboard"]:UPDATE(elapsedTime, dirVelocity:Z).
	SET SHIP:CONTROL:FORE 		TO modulateInput(-velocityPID["Fore"]:OUTPUT, RCSdeadband).
	SET SHIP:CONTROL:TOP 		TO modulateInput(-velocityPID["Top"]:OUTPUT, RCSdeadband).
	SET SHIP:CONTROL:STARBOARD 	TO modulateInput(-velocityPID["Starboard"]:OUTPUT, RCSdeadband).

	IF connectionToKSC() LOG elapsedTime + "," + positionPID["Fore"]:Setpoint + "," + positionPID["Fore"]:Input + "," + positionPID["Fore"]:Output + "," + velocityPID["Fore"]:Setpoint + "," + velocityPID["Fore"]:Input + "," + -velocityPID["Fore"]:Output + "," + SHIP:CONTROL:FORE + "," + SHIP:CONTROL:TOP + "," + SHIP:CONTROL:STARBOARD TO logFileName.

	IF (TIME:SECONDS > startTime + timeOutTime) OR (SHIP:PARTS:LENGTH <> startPartCount) {
		SET mode TO "Done".
	}
	SET oldTime TO TIME:SECONDS.
	SET oldDistance TO getDirDistance().
	WAIT 0.
}

IF (TIME:SECONDS > startTime + timeOutTime) {
	SET loopMessage TO "Docking timed out after " + timeToString(TIME:SECONDS - startTime).
}
IF (SHIP:PARTS:LENGTH <> startPartCount) OR dirDistance:MAG < 1.0 {
	SET loopMessage TO "Sucessfully docked!".
}
