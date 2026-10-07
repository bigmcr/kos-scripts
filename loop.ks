@LAZYGLOBAL OFF.
GLOBAL autoSteer IS "".
LOCAL autoSteerOld IS "".
// previousCommandIndex is the place in previousCommands that is being shown in the input. When it equals the length
// of the list, the operator is typing a new command, and draftInput holds what was typed before browsing started.
LOCAL previousCommandIndex IS 0.
LOCAL draftInput IS "".
LOCAL forceScreenUpdate IS FALSE.
GLOBAL runLocal TO TRUE.
PRINT "Boot script running locally".
SWITCH TO 1.


GLOBAL loopMessage IS bootMessage.					// bootMessage is set in boot.ks, and may report that scripts are out of date.
GLOBAL errorValue IS -123456789.
GLOBAL globalSteer IS SHIP:FACING.
GLOBAL globalThrottle IS 0.
GLOBAL loopMode IS "Default".					// Global so the other loop scripts can access it.
// Names of the commands whose arguments are passed exactly as typed. Their "T" argument means "Toggle", so it must not
// be converted to the boolean TRUE the way arguments for scripts and the other commands are.
GLOBAL rawArgumentCommands IS LIST().
GLOBAL bodList IS LIST().
LIST BODIES IN bodList.
// avoiding the use of a file extension allows RUNPATH to determine the file extension
RUNPATH("library").
RUNPATH("libraryTransfer").
RUNPATH("loopCommands").
RUNPATH("loopTerminal").

FUNCTION functionCaller {
		PARAMETER func, minArguments, maxArguments, args.
		IF args:LENGTH > maxArguments RETURN "Too many arguments".
		LOCAL boundArgs IS 0.
		FOR arg IN args {
				LOCAL localArg IS arg.
				IF boundArgs < maxArguments SET func TO func:BIND(localArg).
				ELSE BREAK.
				SET boundArgs TO boundArgs + 1.
		}
		IF boundArgs < minArguments RETURN "Not enough arguments".
		RETURN func().
}

// Convert Argument
// Converts an argument the operator typed into the type a script or command most likely expects.
// Passed the following:
//			arg (string, one trimmed argument)
// Returns the following:
//			FALSE for "false" or "F", TRUE for "True" or "T", a scalar if arg is a number, otherwise arg unchanged.
FUNCTION convertArgument {
	PARAMETER arg.
	IF (arg = "false") OR (arg = "F") RETURN FALSE.
	IF (arg = "True") OR (arg = "T") RETURN TRUE.
	LOCAL number IS arg:TONUMBER(errorValue).
	IF number = errorValue RETURN arg.
	RETURN number.
}

// Is Resident Script
// The files that are already loaded while loop is running are the critical files that boot.ks keeps on the local
// drive (criticalFileNames, set in boot.ks). Running one of them again from the terminal reloads its functions into
// the running program, which causes "label already exists" errors and long freezes.
// "boot" is refused as well, because boot.ksm runs loop again (and reloads the library) if it is called from here.
// Passed the following:
//			name (whatever the operator typed as the first argument)
// Returns the following:
//			TRUE if name refers to one of the automatically loaded files (bool)
FUNCTION isResidentScript {
	PARAMETER name.
	IF name:TYPENAME <> "String" RETURN FALSE.
	IF name:ENDSWITH(".ksm") SET name TO name:SUBSTRING(0, name:LENGTH - 4).
	ELSE IF name:ENDSWITH(".ks") SET name TO name:SUBSTRING(0, name:LENGTH - 3).
	RETURN (name = "boot") OR criticalFileNames:CONTAINS(name).
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
	LOCAL stageStartTime IS TIME:SECONDS.
	LOCAL facingVect IS SHIP:FACING.

	IF not manualStage {
		LOCAL stageInAtm IS ((SHIP:BODY:ATM:EXISTS) AND
												 (SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) / SHIP:BODY:ATM:SEALEVELPRESSURE > 0.05) AND
												 (SHIP:VELOCITY:SURFACE:MAG > 10.0)).
		IF stageInAtm PRINT "Staging in atmosphere!".
		IF forceLongWait SET waitTime TO 5.0.


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

// The previous commands are kept in a JSON file on the local drive, so that they are still there after a reboot.
LOCAL historyPath IS "1:history.json".
LOCAL historyLoadingPath IS "1:history.loading".

// Save History
// Writes previousCommands to the local drive. If there is not room for it, the file is left out (the history
// is only a convenience, and a failed write would end loop).
// Passed the following:
//			no arguments
// Returns the following:
//			nothing
FUNCTION saveHistory {
	IF EXISTS(historyPath) DELETEPATH(historyPath).
	// the JSON file is larger than the text in it, so this is a generous estimate of its size
	LOCAL estimatedSize IS 300.
	FOR eachCommand IN previousCommands {
		SET estimatedSize TO estimatedSize + eachCommand:LENGTH * 2 + 50.
	}
	IF estimatedSize < CORE:VOLUME:FREESPACE WRITEJSON(previousCommands, historyPath).
}

// Reading a damaged JSON file would end loop every time it starts. So a marker file is made before the history is
// read and removed after, and if the marker is found at the start, the last read did not finish, and the history is
// thrown away instead of being read again.
IF EXISTS(historyLoadingPath) {
	IF EXISTS(historyPath) DELETEPATH(historyPath).
	DELETEPATH(historyLoadingPath).
} ELSE IF EXISTS(historyPath) {
	LOG "loading" TO historyLoadingPath.
	LOCAL savedHistory IS READJSON(historyPath).
	IF savedHistory:ISTYPE("List") SET previousCommands TO savedHistory.
	DELETEPATH(historyLoadingPath).
}
SET previousCommandIndex TO previousCommands:LENGTH.

LOCAL possibleCommands IS createCommandList().
LOCAL done IS FALSE.
LOCAL commandValid TO FALSE.
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
	UNLOCK WHEELSTEERING.
	UNLOCK WHEELTHROTTLE.
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
	SET forceScreenUpdate TO TRUE.
}

GLOBAL dontKillAfterScript IS FALSE.

setLockedSteering(FALSE).
setLockedThrottle(FALSE).

UNTIL done {
	SET forceScreenUpdate TO FALSE.
	SET tempChar TO "".
	UNTIL NOT TERMINAL:INPUT:HASCHAR {
		SET tempChar TO TERMINAL:INPUT:GETCHAR().

		// if the operator entered the "Enter" key, attempt to interperet the input
		IF tempChar = TERMINAL:INPUT:ENTER {
			// for keeping track of if we sucessfully did something based on the command
			SET commandValid TO FALSE.

			// ignore the operator hitting the enter key if nothing is present in inputString
			IF inputString <> "" {
				// the previous message is stale once a new command is entered
				SET loopMessage TO "".
				// split the input into trimmed, unconverted strings. The first one is the script or command name.
				LOCAL rawArgs IS LIST().
				FOR eachArg IN inputString:SPLIT(",") {rawArgs:ADD(eachArg:TRIM).}
				LOCAL commandName IS rawArgs[0].
				// argList holds the name followed by the arguments after type conversion
				LOCAL argList IS LIST(commandName).
				debugString(inputString).

				// refuse to re-run files that loop has already loaded
				IF isResidentScript(commandName) {
					SET loopMessage TO commandName + " is already loaded!".
				}
				// if there is a valid script, process the arguments for it
				ELSE IF commandName <> "" AND EXISTS(commandName) {
					FOR index IN RANGE(1, rawArgs:LENGTH) {argList:ADD(convertArgument(rawArgs[index])).}
					FOR arg IN RANGE(0, argList:LENGTH) {
						debugString("Argument " + (arg) + " has the value of " + argList[arg] + " and is of type " + argList[arg]:TYPENAME).
					}
					debugString("Running " + argList[0] + " locally with " + (argList:LENGTH - 1) + " arguments").
					IF (argList:LENGTH = 1) RUNPATH(argList[0]).
					IF (argList:LENGTH = 2) RUNPATH(argList[0], argList[1]).
					IF (argList:LENGTH = 3) RUNPATH(argList[0], argList[1], argList[2]).
					IF (argList:LENGTH = 4) RUNPATH(argList[0], argList[1], argList[2], argList[3]).
					IF (argList:LENGTH = 5) RUNPATH(argList[0], argList[1], argList[2], argList[3], argList[4]).
					IF (argList:LENGTH = 6) RUNPATH(argList[0], argList[1], argList[2], argList[3], argList[4], argList[5]).
					IF (argList:LENGTH = 7) RUNPATH(argList[0], argList[1], argList[2], argList[3], argList[4], argList[5], argList[6]).
					IF (argList:LENGTH <= 7) {
						IF NOT dontKillAfterScript endScript().
						SET dontKillAfterScript TO FALSE.
						// the script may have printed on the screen, so lay it out again (endScript does this too)
						SET forceScreenUpdate TO TRUE.
						SET commandValid TO TRUE.
						debugString("LoopMessage from command: " + loopMessage).
					} ELSE {
						SET loopMessage TO "Too many arguments!".
					}
				}
				// look up the first section to see if it is a valid command in the list.
				ELSE IF (possibleCommands:KEYS:CONTAINS(commandName)) {
					// the toggle commands get the arguments as typed, everything else gets converted arguments
					LOCAL convertArgs IS NOT rawArgumentCommands:CONTAINS(commandName).
					FOR index IN RANGE(1, rawArgs:LENGTH) {
						IF convertArgs argList:ADD(convertArgument(rawArgs[index])).
						ELSE argList:ADD(rawArgs[index]).
					}
					debugString("Running command " + commandName + " with " + (argList:LENGTH - 1) + " arguments").
					LOCAL returnMessage IS "".
					SET returnMessage TO functionCaller(possibleCommands[commandName]["Delegate"], possibleCommands[commandName]["RequiredArgs"], possibleCommands[commandName]["PossibleArgs"], argList:SUBLIST(1, argList:LENGTH - 1)).
					// a command can print on the terminal (local, update, listFiles and so on), so lay the screen out again
					SET forceScreenUpdate TO TRUE.
					IF returnMessage:FIND("invalid argument") <> -1 OR returnMessage = "Not enough arguments" OR returnMessage = "Too many arguments" {
						SET loopMessage TO returnMessage.
					} ELSE IF returnMessage <> "" {
						SET loopMessage TO returnMessage.
						SET commandValid TO TRUE.
					}
				}
				IF commandName = "exit" OR commandName = "done" OR commandName = "quit" {
					SET done TO TRUE.
					SET commandValid TO TRUE.
					SET loopMessage TO "Exiting terminal".
				}
			}
			// after processing the command, record then delete the command.
			IF (commandValid) {
				debugString("Command " + inputString + " completed").
				// do not record the same command twice in a row, and keep only the most recent 50
				LOCAL isRepeat IS FALSE.
				IF previousCommands:LENGTH > 0 {
					IF previousCommands[previousCommands:LENGTH - 1] = inputString SET isRepeat TO TRUE.
				}
				IF NOT isRepeat {
					previousCommands:ADD(inputString).
					IF previousCommands:LENGTH > 50 previousCommands:REMOVE(0).
					saveHistory().
				}
				SET previousCommandIndex TO previousCommands:LENGTH.
				SET draftInput TO "".
				SET inputString TO "".
			}
			// if the command was not processed correctly, display an error message
			ELSE IF inputString <> "" AND loopMessage = "" SET loopMessage TO "Did not understand input!".
		} ELSE
		// if the operator entered the backspace key, delete one letter from the input string
		IF tempChar = TERMINAL:INPUT:BACKSPACE {
			IF inputString:LENGTH >= 1 {
				SET inputString TO inputString:SUBSTRING(0, inputString:LENGTH - 1).
			}
		} ELSE
		// if the operator entered the up arrow key, load the previous command. What was being typed is kept, to come back to.
		IF tempChar = TERMINAL:INPUT:UPCURSORONE {
			IF previousCommandIndex > 0 {
				IF previousCommandIndex = previousCommands:LENGTH SET draftInput TO inputString.
				SET previousCommandIndex TO previousCommandIndex - 1.
				SET inputString TO previousCommands[previousCommandIndex].
			}
		} ELSE
		// the down arrow key moves toward the newest command, and then back to what was being typed
		IF tempChar = TERMINAL:INPUT:DOWNCURSORONE {
			IF previousCommandIndex < previousCommands:LENGTH {
				SET previousCommandIndex TO previousCommandIndex + 1.
				IF previousCommandIndex = previousCommands:LENGTH SET inputString TO draftInput.
				ELSE SET inputString TO previousCommands[previousCommandIndex].
			}
		} ELSE
		IF tempChar = TERMINAL:INPUT:DELETERIGHT {
			SET inputString TO "".
			SET draftInput TO "".
			SET previousCommandIndex TO previousCommands:LENGTH.
		}
		// otherwise, add the character to the input string. Only printable ASCII is kept, because the other
		// special keys (left/right arrows, home, end, tab, etc.) would add invisible characters to the input.
		ELSE {
			IF UNCHAR(tempChar) >= 32 AND UNCHAR(tempChar) <= 126 SET inputString TO inputString + tempChar.
		}
	}
	IF autoSteer <> "" {
		IF autoSteer <> autoSteerOld setLockedSteering(TRUE).
		IF autoSteer = "damp" {LOCAL tempDirection IS SHIP:FACING. SET globalSteer TO tempDirection.}
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
		ELSE IF autoSteer:CONTAINS("target") {
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
	updateScreen(inputString, previousCommands, forceScreenUpdate).
	WAIT 0.1.
}

CLEARSCREEN.
PRINT "Loop exited".
