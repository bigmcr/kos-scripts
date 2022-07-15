GLOBAL autoSteer IS "".
LOCAL autoSteerOld IS "".
GLOBAL runLocal TO TRUE.
IF runLocal {
	PRINT "Boot script running locally".
	SWITCH TO 1.
} ELSE {
	PRINT "Boot script running off the Archive".
	SWITCH TO 0.
}

GLOBAL loopMessage IS "".
GLOBAL errorValue IS -1234.
GLOBAL globalSteer IS SHIP:FACING.
GLOBAL globalThrottle IS 0.
GLOBAL bodList IS LIST().
LIST BODIES IN bodList.
// avoiding the use of a file extension allows RUNPATH to determine the file extension
RUNPATH("Library").
RUNPATH("loopCommands").
RUNPATH("loopTerminal").

FUNCTION functionCaller {
		PARAMETER func, minArguments, maxArguments, args.
		FOR arg IN args {
			PRINT "    " + arg.
		}
		LOCAL boundArgs IS 0.
		FOR arg IN args {
				LOCAL localArg IS arg.
				IF boundArgs < maxArguments SET func TO func@:BIND(localArg).
				ELSE BREAK.
				SET boundArgs TO boundArgs + 1.
		}
		IF boundArgs < minArguments {
			RETURN "Minimum number of arguments not met".
		}
		RETURN func().
}

// Stage Function
// This function activates a stage and updates the appropriate stage information
// If the rocket is below 75% of the way through the atmosphere, the rocket points prograde before and
// after staging. The reason is to allow the staged rocket parts to drop behind without colliding with
// the rocket. This prevents the spent stage from being pushed into the rocket by aerodynamic forces.
// Passed the following
//			waitTime (scalar, seconds rocket should point prograde before and after staging)
// Returns the following:
//			nothing
FUNCTION stageFunction {
	PARAMETER waitTime IS 0.5.
	PARAMETER forceLongWait IS SHIP:PARTS:LENGTH > 200.
	PARAMETER manualStage IS FALSE.
	IF not manualStage {
		LOCAL stageInAtm IS ((SHIP:BODY:ATM:EXISTS) AND
												 (SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) / SHIP:BODY:ATM:SEALEVELPRESSURE > 0.05) AND
												 (SHIP:VELOCITY:SURFACE:MAG > 10.0)).
		IF stageInAtm PRINT "Staging in atmosphere!".
		IF forceLongWait SET waitTime TO 5.0.

		LOCAL stageStartTime IS TIME:SECONDS.
		LOCAL facingVect IS SHIP:FACING.

		IF stageInAtm {
			SET globalSteer TO SHIP:VELOCITY:SURFACE.
			// this pause is to allow time for the rocket to face pure prograde (within 2.5 degrees)
			UNTIL VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE) < 2.5 WAIT 0.
		}
	}
	STAGE.
	IF not manualStage {
		SET stageStartTime TO TIME:SECONDS.
		SET facingVect TO SHIP:FACING:VECTOR.

		// this pause is to allow time for the spent stage to go past the rocket
		UNTIL TIME:SECONDS > stageStartTime + waitTime WAIT 0.
	}
	updateShipInfo().
}

LOCAL inputString IS "".
LOCAL previousCommands IS LIST().

LOCAL possibleCommands IS createCommandList().
LOCAL done IS FALSE.
LOCAL commandValid TO FALSE.
GLOBAL loopMode IS "Default".					// Global so the other loop scripts can access it.
LOCAL tempChar IS "".

SET globalSteer TO SHIP:FACING.
SET globalThrottle TO 0.

FUNCTION setLockedSteering {
	PARAMETER enable.
	IF enable {
		SAS OFF.
		LOCK STEERING TO globalSteer.
	} ELSE {
		UNLOCK STEERING.
	}
}

FUNCTION setLockedThrottle {
	PARAMETER enable.
	IF enable {
		LOCK THROTTLE TO globalThrottle.
	} ELSE {
		UNLOCK THROTTLE.
	}
}

// End Script
// This function completely unlocks all control over the ship.
// Passed the following:
//			no arguments
// Returns the following:
//			null
FUNCTION endScript {
	SAS OFF.
	RCS OFF.
	setLockedSteering(FALSE).
	setLockedThrottle(FALSE).
	SET autoSteer TO "".
	SET autoSteerOld TO "".

	SET SHIP:CONTROL:FORE TO 0.0.
	SET SHIP:CONTROL:STARBOARD TO 0.0.
	SET SHIP:CONTROL:PITCH TO 0.0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:MAINTHROTTLE TO 0.
	WAIT 0.0.
	SET SHIP:CONTROL:FORE TO 0.0.
	SET SHIP:CONTROL:STARBOARD TO 0.0.
	SET SHIP:CONTROL:PITCH TO 0.0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:MAINTHROTTLE TO 0.
	CLEARVECDRAWS().
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
}

GLOBAL dontKillAfterScript IS FALSE.

setLockedSteering(FALSE).
setLockedThrottle(FALSE).

UNTIL done {
	SET tempChar TO "".
	IF TERMINAL:INPUT:HASCHAR {
		SET tempChar TO TERMINAL:INPUT:GETCHAR().

		// if the operator entered the "Enter" key, attempt to interperet the input
		IF tempChar = TERMINAL:INPUT:ENTER {
			// for keeping track of if we sucessfully did something based on the command
			SET commandValid TO FALSE.

			// ignore the operator hitting the enter key if nothing is present in inputString
			IF inputString <> "" {
				LOCAL argList IS LIST().
//				CLEARSCREEN.
				// for each argument, if the operator entered a non-string, make the conversion
				FOR eachArg IN inputString:SPLIT(",") {
					IF (eachArg = FALSE) OR (eachArg = "F") {argList:ADD(FALSE).}
					ELSE IF (eachArg = TRUE) OR (eachArg = "T") {argList:ADD(TRUE).}
					ELSE IF eachArg:TONUMBER(errorValue) = errorValue {argList:ADD(eachArg).}
					ELSE {argList:ADD(eachArg:TONUMBER(errorValue)).}
				}
				// otherwise, leave the argument as a string
//				PRINT "argList has Length " + argList:LENGTH.
				debugString(inputString).

//				WAIT 1.
				// if there is a valid script, process the arguments for it
				IF EXISTS(argList[0]) {
//					CLEARSCREEN.
					FOR arg IN RANGE(0, argList:LENGTH) {
//						PRINT "Argument " + argList[arg] + " has the value of " + argList[arg] + " and is of type " + argList[arg]:TYPENAME.
						debugString("Argument " + (arg) + " has the value of " + argList[arg] + " and is of type " + argList[arg]:TYPENAME).
					}
//					PRINT "Running " + argList[0] + " with " + (argList:LENGTH - 1) + " arguments".
					debugString("Running " + argList[0] + " locally with " + (argList:LENGTH - 1) + " arguments").
					IF (argList:LENGTH = 1) RUNPATH(argList[0]).
					IF (argList:LENGTH = 2) RUNPATH(argList[0], argList[1]).
					IF (argList:LENGTH = 3) RUNPATH(argList[0], argList[1], argList[2]).
					IF (argList:LENGTH = 4) RUNPATH(argList[0], argList[1], argList[2], argList[3]).
					IF (argList:LENGTH = 5) RUNPATH(argList[0], argList[1], argList[2], argList[3], argList[4]).
					IF (argList:LENGTH = 6) RUNPATH(argList[0], argList[1], argList[2], argList[3], argList[4], argList[5]).
					IF (argList:LENGTH = 7) RUNPATH(argList[0], argList[1], argList[2], argList[3], argList[4], argList[5], argList[6]).
					IF NOT dontKillAfterScript endScript().
					SET dontKillAfterScript TO FALSE.
					SET commandValid TO TRUE.
				}
				// look up the first section to see if it is a valid command in the list.
				IF (possibleCommands:KEYS:CONTAINS(argList[0])) {
					debugString("Running command " + argList[0] + " with " + (argList:LENGTH - 1) + " arguments").
					LOCAL returnMessage IS "".
					SET returnMessage TO functionCaller(possibleCommands[argList[0]]["Delegate"], possibleCommands[argList[0]]["RequiredArgs"], possibleCommands[argList[0]]["PossibleArgs"], argList:SUBLIST(1, argList:LENGTH - 1)).
					IF returnMessage:FIND("invalid argument") <> -1 SET loopMessage TO returnMessage.
					ELSE IF returnMessage <> "" AND returnMessage <> "Minimum number of arguments not met" {
						SET loopMessage TO returnMessage.
						SET commandValid TO TRUE.
					}
				}
				IF argList[0] = "exit" OR argList[0] = "done" OR argList[0] = "quit" SET done TO TRUE.
			}
			// after processing the command, record then delete the command.
			IF (commandValid) {
				debugString("Command " + inputString + " completed").
				previousCommands:ADD(inputString).
				SET previousCommandIndex TO previousCommands:LENGTH - 1.
				SET inputString TO "".
			}
			// if the command was not processed correctly, display an error message
			ELSE IF loopMessage = "" SET loopMessage TO "Did not understand input!".
		} ELSE
		// if the operator entered the backspace key, delete one letter from the input string
		IF tempChar = TERMINAL:INPUT:BACKSPACE {
			IF inputString:LENGTH >= 1 {
				SET inputString TO inputString:SUBSTRING(0, inputString:LENGTH - 1).
			}
		} ELSE
		// if the operator entered the up arrow key, load the previous command
		IF tempChar = TERMINAL:INPUT:UPCURSORONE {
			SET previousCommandIndex TO previousCommandIndex - 1.
			IF previousCommandIndex > previousCommands:LENGTH - 1 SET previousCommandIndex TO previousCommands:LENGTH - 1.
			IF previousCommandIndex < 0 SET previousCommandIndex TO 0.
			IF (previousCommandIndex < previousCommands:LENGTH) SET inputString TO previousCommands[previousCommandIndex].
		} ELSE
		IF tempChar = TERMINAL:INPUT:DOWNCURSORONE {
			SET previousCommandIndex TO previousCommandIndex + 1.
			IF previousCommandIndex > previousCommands:LENGTH - 1 SET previousCommandIndex TO previousCommands:LENGTH - 1.
			IF previousCommandIndex < 0 SET previousCommandIndex TO 0.
			IF (previousCommandIndex < previousCommands:LENGTH) SET inputString TO previousCommands[previousCommandIndex].
		} ELSE
		IF tempChar = TERMINAL:INPUT:DELETERIGHT {
			SET inputString TO "".
		}
		// otherwise, add the character to the input string
		ELSE {
			SET inputString TO inputString + tempChar.
		}
	}
	IF autoSteer <> "" {
		IF autoSteer <> autoSteerOld setLockedSteering(TRUE).
		IF autoSteer = "hold" {LOCAL tempDirection IS SHIP:FACING. SET globalSteer TO tempDirection.}
		ELSE IF autoSteer = "up" SET globalSteer TO -SHIP:BODY:POSITION.
		ELSE IF autoSteer = "down" SET globalSteer TO SHIP:BODY:POSITION.
		ELSE IF autoSteer = "north" SET globalSteer TO SHIP:NORTH:VECTOR.
		ELSE IF autoSteer = "south" SET globalSteer TO -SHIP:NORTH:VECTOR.
		ELSE IF autoSteer = "prograde" SET globalSteer TO SHIP:PROGRADE:VECTOR.
		ELSE IF autoSteer = "retrograde" SET globalSteer TO -SHIP:PROGRADE:VECTOR.
		ELSE IF autoSteer = "radialin" SET globalSteer TO VCRS(SHIP:VELOCITY:ORBIT, VCRS(SHIP:VELOCITY:ORBIT, -SHIP:BODY:POSITION)).
		ELSE IF autoSteer = "radialout" SET globalSteer TO -VCRS(SHIP:VELOCITY:ORBIT, VCRS(SHIP:VELOCITY:ORBIT, -SHIP:BODY:POSITION)).
		ELSE IF autoSteer = "normal" SET globalSteer TO -VCRS(SHIP:VELOCITY:ORBIT, SHIP:BODY:POSITION).
		ELSE IF autoSteer = "antinormal" SET globalSteer TO VCRS(SHIP:VELOCITY:ORBIT, SHIP:BODY:POSITION).
		ELSE IF autoSteer = "surfaceprograde" SET globalSteer TO VELOCITY:SURFACE.
		ELSE IF autoSteer = "surfaceretrograde" SET globalSteer TO CHOOSE SHIP:UP:VECTOR IF (GROUNDSPEED < 0.25) ELSE -VELOCITY:SURFACE.
		ELSE IF autoSteer = "landliftnormal" SET globalSteer TO LOOKDIRUP(SHIP:FACING:VECTOR, SHIP:UP:VECTOR).
		ELSE IF autoSteer = "landliftreverse" SET globalSteer TO LOOKDIRUP(SHIP:FACING:VECTOR, -SHIP:UP:VECTOR).
		ELSE IF autoSteer:CONTAINS("maneuver") {
			IF NOT HASNODE {
				SET loopMessage TO "Has no NEXTNODE!".
				SET autoSteer TO "".
			} ELSE {
				IF autoSteer = "maneuverdirect"	SET globalSteer TO NEXTNODE:DELTAV:DIRECTION.
				ELSE IF autoSteer = "maneuverinverse" SET globalSteer TO -NEXTNODE:DELTAV.
			}
		} // maneuver
		ELSE IF autoSteer:CONTAINS("TARGET") {
			IF NOT HASTARGET {
				SET loopMessage TO "Target not assigned!".
				SET autoSteer TO "".
			} ELSE {
				IF autoSteer = "target," SET globalSteer TO TARGET:POSITION - SHIP:CONTROLPART:POSITION.
				ELSE IF autoSteer = "target,anti" SET globalSteer TO -TARGET:POSITION + SHIP:CONTROLPART:POSITION.
				ELSE IF autoSteer = "target,retrograde" {
					IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") SET globalSteer TO (TARGET:SHIP:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT).
					ELSE SET globalSteer TO (TARGET:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT).
				}
				ELSE IF autoSteer = "target,prograde" {
					IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") SET globalSteer TO (SHIP:VELOCITY:ORBIT - TARGET:SHIP:VELOCITY:ORBIT).
					ELSE SET globalSteer TO (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT).
				}
				ELSE IF autoSteer = "target,facing" SET globalSteer TO TARGET:FACING.
				ELSE IF autoSteer = "target,antifacing" SET globalSteer TO -TARGET:FACING:VECTOR.
			}
		} // target logic
		ELSE IF autoSteer:STARTSWITH("point") {
			LOCAL splitList IS autoSteer:SPLIT(",").
			SET globalSteer TO HEADING(splitList[1]:TONUMBER(90), splitList[2]:TONUMBER(0), splitList[3]:TONUMBER(0)).
		}
		// point toward each of the bodies in the solar system, if needed.
		FOR bod in bodList {LOCAL selectedBody IS bod. IF autoSteer = selectedBody:NAME SET globalSteer TO LOOKDIRUP(selectedBody:POSITION, SHIP:UP:VECTOR).}

		SET autoSteerOld TO autoSteer.
	} ELSE { // autoSteer = ""
		IF autoSteerOld <> "" {
			SET loopMessage TO "Autosteer turned off".
			setLockedSteering(FALSE).
			SET autoSteerOld TO autoSteer.
		}
	}
	updateScreen(inputString, previousCommands).
	WAIT 0.1.
}

CLEARSCREEN.
PRINT "Loop exited".
