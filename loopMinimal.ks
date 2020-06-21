@LAZYGLOBAL OFF.

CLEARSCREEN.

GLOBAL runLocal TO NOT connectionToKSC().
IF runLocal {
	PRINT "Boot script running locally".
	SWITCH TO 1.
} ELSE {
	PRINT "Boot script running off the Archive".
	SWITCH TO 0.
}

GLOBAL loopMessage IS "".
GLOBAL debug IS TRUE.							// If TRUE, multiple functions will display or log extra info
GLOBAL mySteer IS SHIP:FACING.
GLOBAL myThrottle IS 0.
GLOBAL useMySteer IS FALSE.
GLOBAL useMyThrottle IS FALSE.

LOCAL inputString IS "".
LOCAL count IS 0.
LOCAL updateScreen IS TRUE.
LOCAL done IS FALSE.
LOCAL errorValue IS 999.
LOCAL commandValid TO FALSE.
LOCAL tempChar IS "".
LOCAL bodList IS LIST().
LOCAL foundBody IS "".
LIST BODIES IN bodList.

LOCK mySteer TO SHIP:FACING.

// End Script
// This function completely unlocks all control over the ship.
// Passed the following:
//			no arguments
// Returns the following:
//			null
FUNCTION endScript {
	SAS OFF.
	RCS OFF.
	UNLOCK useMySteer.
	SET useMySteer TO FALSE.
	UNLOCK mySteer.
	SET mySteer TO SHIP:FACING.

	UNLOCK useMyThrottle.
	SET useMyThrottle TO FALSE.
	UNLOCK myThrottle.
	SET myThrottle TO 0.0.

	SET SHIP:CONTROL:FORE TO 0.0.
	SET SHIP:CONTROL:STARBOARD TO 0.0.
	SET SHIP:CONTROL:PITCH TO 0.0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:MAINTHROTTLE TO 0.
	WAIT 0.25.
	SET SHIP:CONTROL:FORE TO 0.0.
	SET SHIP:CONTROL:STARBOARD TO 0.0.
	SET SHIP:CONTROL:PITCH TO 0.0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:MAINTHROTTLE TO 0.
	CLEARVECDRAWS().
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
}

// update the terminal screen
ON updateScreen {
	CLEARSCREEN.
//	PRINT "KSP CONN   FALSE   LOCAL      FALSE     " AT (0, 0).
//	PRINT "AUTO STEER FALSE   AUTO THROT FALSE     " AT (0, 1).
//	PRINT "LS DELAY   XXXXX                        " AT (0, 2).
//	PRINT "                                        " AT (0, 3).
//	PRINT "CURRENT INPUT                           " AT (0, 4).
//	PRINT "                                        " AT (0, 5).
//  PRINT "LOOP MESSAGE                            " AT (0, 6).
//	PRINT "                                        " AT (0, 7).
//	PRINT "----------------------------------------" AT (0, 8).
	PRINT "KSP Conn           Local                " AT (0, 0).
	PRINT "Auto Steer         Auto Throt           " AT (0, 1).
	PRINT "LS Delay                                " AT (0, 2).
	PRINT "                                        " AT (0, 3).
	PRINT "Current Input                           " AT (0, 4).
	PRINT "                                        " AT (0, 5).
	PRINT "Loop Message                            " AT (0, 6).
	PRINT "                                        " AT (0, 7).
	PRINT "----------------------------------------" AT (0, 8).

	PRINT connectionToKSC():TOSTRING:PADLEFT(5) AT (12, 0).
	PRINT runLocal:TOSTRING:PADLEFT(5) AT (30, 0).

	PRINT useMySteer:TOSTRING:PADLEFT(5) AT (12, 1).
	PRINT useMyThrottle:TOSTRING:PADLEFT(5) AT (30, 1).
	IF (connectionToKSC()) PRINT ROUND(HOMECONNECTION:DELAY, 0):TOSTRING:PADLEFT(5) AT (12, 2).
	ELSE PRINT "  N/A" AT (12, 2).

	// print the current input from the operator
	PRINT inputString AT (0, 5).

	// display any messages from the loop program
	PRINT loopMessage AT (0, 7).
	RETURN TRUE.
}

SET useMySteer TO FALSE.
SET useMyThrottle TO FALSE.

ON useMySteer {
	IF useMySteer LOCK STEERING TO mySteer.
	ELSE UNLOCK STEERING.
	RETURN TRUE.
}

ON useMyThrottle {
	IF useMyThrottle LOCK THROTTLE TO myThrottle.
	ELSE UNLOCK THROTTLE.
	RETURN TRUE.
}

UNTIL done {
	SET tempChar TO "".
	SET count TO count + 1.
	IF TERMINAL:INPUT:HASCHAR {
		SET tempChar TO TERMINAL:INPUT:GETCHAR().

		// if the operator entered the "Enter" key, attempt to interperet the input
		IF tempChar = TERMINAL:INPUT:ENTER {
			// for keeping track of if we sucessfully did something based on the command
			SET commandValid TO FALSE.

			// ignore the operator hitting the enter key if nothing is present in inputString
			IF inputString <> "" {
				// if the operator entered a script name followed by arguments, handle the arguments correctly, up to six arguments
				IF (inputString:SPLIT(","):LENGTH > 1) {
					LOCAL inputStringList TO inputString:SPLIT(",").
					LOCAL argList IS LIST().
					// for each argument, if the operator entered a non-string, make the conversion
					// otherwise, leave the argument as a string
					PRINT "InputStringList has Length " + inputStringList:LENGTH.
					debugString(inputString).

					// if the first item in inputStringList is one of the statuses of the ship (debug, RCS, solar, etc) toggle it
					IF inputStringList[0] = "debug" {
						IF inputStringList[1] = "On" SET debug TO TRUE.
						IF inputStringList[1] = "Off" SET debug TO FALSE.
						IF (inputStringList[1] = "Toggle") OR (inputStringList[1] = "T") SET debug TO NOT debug.
						SET loopMessage TO "Debug is currently " + debug.
						SET commandValid TO TRUE.
					} ELSE IF ((inputStringList[0] = "solar") OR (inputStringList[0] = "panels")) {
						IF inputStringList[1] = "On" SET PANELS TO TRUE.
						IF inputStringList[1] = "Off" SET PANELS TO FALSE.
						IF (inputStringList[1] = "Toggle") OR (inputStringList[1] = "T") SET PANELS TO NOT PANELS.
						WAIT 1.0.
						SET loopMessage TO "Panels is currently " + PANELS.
						SET commandValid TO TRUE.
					} ELSE IF inputStringList[0] = "RCS" {
						IF inputStringList[1] = "On" SET RCS TO TRUE.
						IF inputStringList[1] = "Off" SET RCS TO FALSE.
						IF (inputStringList[1] = "Toggle") OR (inputStringList[1] = "T") SET RCS TO NOT RCS.
						SET loopMessage TO "RCS is currently " + RCS.
						SET commandValid TO TRUE.
					} ELSE IF inputStringList[0] = "SAS" {
						SET useMySteer TO FALSE.
						IF inputStringList[1] = "On" SET SAS TO TRUE.
						IF inputStringList[1] = "Off" SET SAS TO FALSE.
						IF (inputStringList[1] = "Toggle") OR (inputStringList[1] = "T") SET SAS TO NOT SAS.
						SET loopMessage TO "SAS is currently " + SAS.
						SET commandValid TO TRUE.
					} ELSE IF inputStringList[0] = "stopTime" {
						IF inputStringList[1] = "" SET loopMessage TO "Max Stopping time is " + STEERINGMANAGER:MAXSTOPPINGTIME.
						ELSE {
							SET STEERINGMANAGER:MAXSTOPPINGTIME TO inputStringList[1]:TONUMBER(2).
							SET loopMessage TO "Changed Max Stopping time to " + STEERINGMANAGER:MAXSTOPPINGTIME.
						}
						SET commandValid TO TRUE.
					} ELSE IF inputStringList[0] = "LIGHTS" {
						IF inputStringList[1] = "On" SET LIGHTS TO TRUE.
						IF inputStringList[1] = "Off" SET LIGHTS TO FALSE.
						IF (inputStringList[1] = "Toggle") OR (inputStringList[1] = "T") SET LIGHTS TO NOT LIGHTS.
						SET loopMessage TO "Lights are currently " + LIGHTS.
						SET commandValid TO TRUE.
					} ELSE IF (inputStringList[0] = "node") {
						IF inputStringList:LENGTH = 2 {ADD NODE(TIME:SECONDS + 60,								0,								0, inputStringList[1]:TONUMBER(0)).}
						IF inputStringList:LENGTH = 3 {ADD NODE(TIME:SECONDS + 60,								0, inputStringList[2]:TONUMBER(0), inputStringList[1]:TONUMBER(0)).}
						IF inputStringList:LENGTH = 4 {ADD NODE(TIME:SECONDS + 60, inputStringList[3]:TONUMBER(0), inputStringList[2]:TONUMBER(0), inputStringList[1]:TONUMBER(0)).}
						SET loopMessage TO "Added a node" + ISRU.
						SET commandValid TO TRUE.
					} ELSE IF (inputStringList[0] = "copyscript") {
						IF connectionToKSC() {
							IF EXISTS("1:" + inputStringList[1] + ".ks") DELETEPATH("1:" + inputStringList[1] + ".ks").
							IF EXISTS("1:" + inputStringList[1] + ".ksm") DELETEPATH("1:" + inputStringList[1] + ".ksm").
							COMPILE "0:" + inputStringList[1] + ".ks" TO "1:" + inputStringList[1] + ".ksm".
							IF EXISTS("1:" + inputStringList[1] + ".ksm") SET loopMessage TO "File compiled and copied.".
							ELSE SET loopMessage TO "File was not copied correctly!".
						} SET loopMessage TO "No connection to KSC, cannot copy script".
						SET commandValid TO TRUE.
					} ELSE IF ((inputStringList[0] = "ANTENNA") OR (inputStringList[0] = "ANTENNAS") OR (inputStringList[0] = "OMNI") OR (inputStringList[0] = "OMNIS")) {
						IF inputStringList[1] = "On" {activateOmniAntennae(). SET loopMessage TO "Omni antennae have been activated.".}
						IF inputStringList[1] = "Off" {deactivateOmniAntennae(). SET loopMessage TO "Omni antennae have been deactivated.".}
						SET commandValid TO TRUE.
					} ELSE IF ((inputStringList[0] = "DISH") OR (inputStringList[0] = "DISHES")) {
						IF inputStringList[1] = "On" {activateDishAntennae(). SET loopMessage TO "Dish antennae have been activated.".}
						IF inputStringList[1] = "Off" {deactivateDishAntennae(). SET loopMessage TO "Dish antennae have been deactivated.".}
						SET commandValid TO TRUE.
					} ELSE IF (inputStringList[0] = "warpToAltitude") {
						IF ((inputStringList[1]:TONUMBER(-1) <> -1) OR (inputStringList[1] = "")) {
							LOCAL warpAltitude IS inputStringList[1]:TONUMBER(10000).
							IF (inputStringList[1] = "") SET warpAltitude TO 10000.
							IF (SHIP:BODY:ATM:EXISTS) SET warpAltitude TO MAX(SHIP:BODY:ATM:HEIGHT + 10000, inputStringList[1]:TONUMBER(-1)).
							warpToTime(TIME:SECONDS + timeToAltitude(warpAltitude)).
							SET loopMessage TO "Warped to altitude of " + ROUND(ALTITUDE).
							SET commandValid TO TRUE.
						}
					} ELSE IF (inputStringList[0] = "target") {
						IF HASTARGET {
							IF inputStringList[1] = "" {
								SET useMySteer TO TRUE.
								SAS OFF.
								LOCK mySteer TO TARGET:POSITION.
								SET commandValid TO TRUE.
								IF TARGET:TYPENAME = "Part" OR TARGET:TYPENAME = "DockingPort" SET loopMessage TO "Steering locked to " + TARGET:TITLE + " on " + TARGET:SHIP:NAME.
								ELSE SET loopMessage TO "Steering locked to " + TARGET:NAME.
							}
							IF inputStringList[1] = "anti" {
								SET useMySteer TO TRUE.
								SAS OFF.
								LOCK mySteer TO -TARGET:POSITION.
								SET commandValid TO TRUE.
								SET loopMessage TO "Steering locked to anti target".
							}
							IF inputStringList[1] = "retro" OR inputStringList[0] = "retrograde" {
								SET useMySteer TO TRUE.
								SAS OFF.
								LOCK mySteer TO (TARGET:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT).
								SET commandValid TO TRUE.
								SET loopMessage TO "Steering locked to target retrograde".
							}
							IF inputStringList[1] = "pro" OR inputStringList[0] = "prograde" {
								SET useMySteer TO TRUE.
								SAS OFF.
								LOCK mySteer TO (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT).
								SET commandValid TO TRUE.
								SET loopMessage TO "Steering locked to target prograde".
							}
							IF inputStringList[1] = "facing" {
								SET useMySteer TO TRUE.
								SAS OFF.
								LOCK mySteer TO (-TARGET:FACING:VECTOR):DIRECTION.
								SET commandValid TO TRUE.
								SET loopMessage TO "Steering locked to target facing".
							}
							IF inputStringList[1] = "antifacing" {
								SET useMySteer TO TRUE.
								SAS OFF.
								LOCK mySteer TO (TARGET:FACING:VECTOR):DIRECTION.
								SET commandValid TO TRUE.
								SET loopMessage TO "Steering locked to target facing".
							}
						} ELSE {SET commandValid TO TRUE. SET loopMessage TO "Must have a target set.".}

					// if there is a valid script, process the arguments for it
					} ELSE IF EXISTS(inputStringList[0]) {
						FOR arg IN RANGE(1, inputStringList:LENGTH) {
							IF (inputStringList[arg] = FALSE) OR (inputStringList[arg] = "F") {argList:ADD(FALSE). PRINT "Boolean False".}
							ELSE IF (inputStringList[arg] = TRUE) OR (inputStringList[arg] = "T") {argList:ADD(TRUE). PRINT "Boolean True".}
							ELSE IF inputStringList[arg]:TONUMBER(errorValue) = errorValue {argList:ADD(inputStringList[arg]). PRINT "String " + inputStringList[arg].}
							ELSE {argList:ADD(inputStringList[arg]:TONUMBER(errorValue)). PRINT "Scalar " + inputStringList[arg].}
						}
						CLEARSCREEN.
						FOR arg IN RANGE(0, argList:LENGTH) {
							PRINT "Argument " + argList[arg] + " has the value of " + argList[arg] + " and is of type " + argList[arg]:TYPENAME.
							debugString("Argument " + (arg) + " has the value of " + argList[arg] + " and is of type " + argList[arg]:TYPENAME).
						}
						IF runLocal {
							PRINT "Running " + inputStringList[0] + " with " + argList:LENGTH + " arguments".
							WAIT 1.0.		// pause long enough for the operator to see that there is something on screen
							debugString("Running " + inputStringList[0] + " locally with " + argList:LENGTH + " arguments").
							IF (argList:LENGTH = 1) RUNPATH(inputStringList[0] + ".ksm", argList[0]).
							IF (argList:LENGTH = 2) RUNPATH(inputStringList[0] + ".ksm", argList[0], argList[1]).
							IF (argList:LENGTH = 3) RUNPATH(inputStringList[0] + ".ksm", argList[0], argList[1], argList[2]).
							IF (argList:LENGTH = 4) RUNPATH(inputStringList[0] + ".ksm", argList[0], argList[1], argList[2], argList[3]).
							IF (argList:LENGTH = 5) RUNPATH(inputStringList[0] + ".ksm", argList[0], argList[1], argList[2], argList[3], argList[4]).
							IF (argList:LENGTH = 6) RUNPATH(inputStringList[0] + ".ksm", argList[0], argList[1], argList[2], argList[3], argList[4], argList[5]).
						} ELSE {
							debugString("Compiling " + inputStringList[0]).
							compileScript(inputStringList[0]).
							PRINT "Compiling and running " + inputStringList[0] + " with " + argList:LENGTH + " arguments".
							WAIT 1.0.		// pause long enough for the operator to see that there is something on screen
							debugString("Running compiled " + inputStringList[0] + " off the archive with " + argList:LENGTH + " arguments").
							FOR arg IN RANGE(0, argList:LENGTH) {
								debugString("Argument " + (arg) + " has the value of " + argList[arg] + " and is of type " + argList[arg]:TYPENAME).
							}
							IF (argList:LENGTH = 1) RUNPATH("KSM Files/" + inputStringList[0] + ".ksm", argList[0]).
							IF (argList:LENGTH = 2) RUNPATH("KSM Files/" + inputStringList[0] + ".ksm", argList[0], argList[1]).
							IF (argList:LENGTH = 3) RUNPATH("KSM Files/" + inputStringList[0] + ".ksm", argList[0], argList[1], argList[2]).
							IF (argList:LENGTH = 4) RUNPATH("KSM Files/" + inputStringList[0] + ".ksm", argList[0], argList[1], argList[2], argList[3]).
							IF (argList:LENGTH = 5) RUNPATH("KSM Files/" + inputStringList[0] + ".ksm", argList[0], argList[1], argList[2], argList[3], argList[4]).
							IF (argList:LENGTH = 6) RUNPATH("KSM Files/" + inputStringList[0] + ".ksm", argList[0], argList[1], argList[2], argList[3], argList[4], argList[5]).
						}
						endScript().
						SET commandValid TO TRUE.
					}
				}
				// if the operator entered a single command, interperet and execute it
				ELSE {
					// if inputString is the name of a script, run the script
					IF (NOT connectionToKSC() AND (CORE:VOLUME:EXISTS(inputString) OR CORE:VOLUME:EXISTS("KSM Files/" + inputString))) {
						debugString("Running " + inputString + " locally").
						RUNPATH("1:" + inputString + ".ksm").
						endScript().
						SET commandValid TO TRUE.
					} ELSE
					IF (connectionToKSC() AND (ARCHIVE:EXISTS(inputString) OR ARCHIVE:EXISTS("KSM Files/" + inputString))) {
						debugString("Compiling 0:" + inputString + ".ks").
						compileScript(inputString).
						debugString("Running 0:" + inputString + ".ksm off the archive").
						RUNPATH("0:KSM Files/" + inputString + ".ksm").
						endScript().
						SET commandValid TO TRUE.
					}
					// if inputString is any of the orbital directions, turn to face that direction
					IF inputString = "hold" 						{SET useMySteer TO TRUE. SAS OFF. SET mySteer TO SHIP:FACING. 																	SET commandValid TO TRUE. SET loopMessage TO "Steering held at current".} ELSE
					IF inputString = "up" 							{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO LOOKDIRUP(SHIP:UP:VECTOR, -SHIP:NORTH:VECTOR). 								SET commandValid TO TRUE. SET loopMessage TO "Steering locked to up".} ELSE
					IF inputString = "down" 						{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO -SHIP:UP:VECTOR. 																SET commandValid TO TRUE. SET loopMessage TO "Steering locked to down".} ELSE
					IF inputString = "north" 						{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO SHIP:NORTH:VECTOR. 															SET commandValid TO TRUE. SET loopMessage TO "Steering locked to north".} ELSE
					IF inputString = "south" 						{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO -(SHIP:NORTH:VECTOR). 														SET commandValid TO TRUE. SET loopMessage TO "Steering locked to south".} ELSE
					IF inputString = "prograde" 					{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO SHIP:PROGRADE:VECTOR. 														SET commandValid TO TRUE. SET loopMessage TO "Steering locked to orbit prograde".} ELSE
					IF inputString = "retrograde" 					{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO -(SHIP:PROGRADE:VECTOR). 														SET commandValid TO TRUE. SET loopMessage TO "Steering locked to orbit retrograde".} ELSE
					IF inputString = "radialin" 					{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO VCRS(SHIP:PROGRADE:VECTOR, VCRS(SHIP:NORTH:VECTOR, SHIP:PROGRADE:VECTOR)). 	SET commandValid TO TRUE. SET loopMessage TO "Steering locked to radial in".} ELSE
					IF inputString = "radialout" 					{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO VCRS(-SHIP:PROGRADE:VECTOR, VCRS(SHIP:NORTH:VECTOR, SHIP:PROGRADE:VECTOR)). 	SET commandValid TO TRUE. SET loopMessage TO "Steering locked to radial out".} ELSE
					IF inputString = "normal" 						{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO VCRS(SHIP:VELOCITY:ORBIT, SHIP:BODY:POSITION). 									SET commandValid TO TRUE. SET loopMessage TO "Steering locked to normal".} ELSE
					IF inputString = "antinormal" 					{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO -VCRS(SHIP:VELOCITY:ORBIT, SHIP:BODY:POSITION). 								SET commandValid TO TRUE. SET loopMessage TO "Steering locked to antinormal".} ELSE
					IF inputString = "srfPrograde" OR inputString = "srfPro" 		{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO VELOCITY:SURFACE. 			SET commandValid TO TRUE. SET loopMessage TO "Steering locked to surface prograde".} ELSE
					IF inputString = "srfRetrograde" OR inputString = "srfRetro" {
							SET useMySteer TO TRUE.
							SAS OFF.
							LOCAL srfRetro IS {
								IF (GROUNDSPEED < 1.0)
									RETURN SHIP:UP:VECTOR.
								ELSE
									RETURN -VELOCITY:SURFACE.
								}.
							LOCK mySteer TO srfRetro().
							SET commandValid TO TRUE.
							SET loopMessage TO "Steering locked to surface retrograde".
					} ELSE IF inputString = "landLift"										{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO HEADING(yaw_vector(-SHIP:VELOCITY:SURFACE), pitch_for(SHIP)). SET commandValid TO TRUE. SET loopMessage TO "Steering locked to 15 degrees above horizon.".} ELSE
					IF inputString = "maneuver" AND HASNODE 						{SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO NEXTNODE:DELTAV:DIRECTION. 	SET commandValid TO TRUE. SET loopMessage TO "Steering locked to maneuver".} ELSE
					// if inputString is DistanceToTargetOrbitalPlane
					IF inputString = "distTgtPlane" {SET loopMessage TO ROUND(distanceToTargetOrbitalPlane(), 4) + " km to target's orbital plane". SET commandValid TO TRUE.} ELSE

					// if inputString is "exit", leave the loop
					IF inputString = "exit" {endScript(). SET done TO TRUE.} ELSE

					// if inputString is "reboot", reboot the processor
					IF inputString = "reboot" OR inputString = "reboot." {debugString("Reboot"). REBOOT.} ELSE

					// if inputString is "updateScripts", delete all scripts on the local drive and update them from KSC
					IF inputString = "updateScripts" {
						SET commandValid TO TRUE.
						IF (connectionToKSC()) {
							copyToLocal().
							SET loopMessage TO "Updated all scripts from the archive".
						} ELSE SET loopMessage TO "Not connected to KSC - cannot update scripts".
					} ELSE

					// if inputString is "listfiles", display a list of all files on the current volume
					if inputString = "listfiles" OR inputString = "listfile" {
						SET commandValid TO TRUE.
						listFiles().
					} ELSE

					// if inputString is apoapsis, periapsis or transition, timewarp to the appropriate place in orbit
					IF inputString = "apoapsis" OR inputString = "apo" {
						SET commandValid TO TRUE.
						IF (NOT ORBIT:HASNEXTPATCH) OR (ORBIT:HASNEXTPATCH AND ETA:APOAPSIS < ORBIT:NEXTPATCHETA) {
							warpToTime(TIME:SECONDS + ETA:APOAPSIS - 10).
							SET loopMessage TO "Warped to apoapsis - 10 seconds".
						} ELSE SET loopMessage TO "Orbit transitions before apoapsis!".
					} ELSE
					IF inputString = "periapsis" OR inputString = "peri" {
						SET commandValid TO TRUE.
						IF (NOT ORBIT:HASNEXTPATCH) OR (ORBIT:HASNEXTPATCH AND ETA:PERIAPSIS < ORBIT:NEXTPATCHETA) {
							warpToTime(TIME:SECONDS + ETA:PERIAPSIS - 10).
							SET loopMessage TO "Warped to periapsis - 10 seconds".
						} ELSE SET loopMessage TO "Orbit transitions before periapsis!".
					} ELSE
					IF inputString = "transition" OR inputString = "trans" {
						SET commandValid TO TRUE.
						IF (ORBIT:HASNEXTPATCH) {
							warpToTime(TIME:SECONDS + ETA:TRANSITION - 10).
							SET loopMessage TO "Warped to transition - 10 seconds".
						} ELSE SET loopMessage TO "Orbit has no transition!".
					} ELSE

					// if inputString is stage, trigger the staging function
					IF inputString = "stage" {
						stageFunction().
						SET commandValid TO TRUE.
						SET loopMessage TO "Manually Staged!".
					} ELSE

					IF inputString = "local" {
						SET commandValid TO TRUE.
						IF connectionToKSC() {
							copyToLocal().
							SET loopMessage TO "Updated all scripts, running locally".
						} ELSE SET loopMessage TO "Running locally".
						SWITCH TO 1.
						SET runLocal TO TRUE.
					} ELSE

					IF inputString = "remote" OR inputString = "archive" {
						SET commandValid TO TRUE.
						IF connectionToKSC() {
							SWITCH TO 0.
							SET runLocal TO FALSE.
							SET loopMessage TO "Switched to running on the archive".
						} ELSE SET loopMessage TO "KSC not accessible".
					} ELSE

					// if inputString is "lock" or "unlock", perform the appropriate command on mySteer.
					IF inputString = "lock" OR inputString = "lockS" {
						SET useMySteer TO TRUE.
						SET loopMessage TO "Steering locked to mySteer".
						SET commandValid TO TRUE.
					} ELSE
					IF inputString = "unlock" OR inputString = "unlockS" {
						SET useMySteer TO FALSE.
						SET loopMessage TO "Steering unlocked".
						SET commandValid TO TRUE.
					} ELSE
					// if inputString is "lockT" or "unlockT", perform the appropriate command on myThrottle.
					IF inputString = "lockT" {
						SET useMyThrottle TO TRUE.
						SET loopMessage TO "Throttle locked to myThrottle".
						SET commandValid TO TRUE.
					} ELSE
					IF inputString = "unlockT" {
						SET useMyThrottle TO FALSE.
						SET loopMessage TO "Throttle unlocked".
						SET commandValid TO TRUE.
					} ELSE

					IF inputString = "hide" {
						core:part:getmodule("kOSProcessor"):doevent("Close Terminal").
						SET loopMessage TO "Terminal Hidden".
						SET commandValid TO TRUE.
					}

					// is inputString is "logActions", "log actions" or "actions", trigger the log all actions function
					IF inputString = "logAction" OR inputString = "log actions" OR inputString = "actions" {
						LogAllActions().
						SET commandValid TO TRUE.
						SET loopMessage TO "Action file created!".
					} ELSE

					// is inputString is "logParts", "log parts" or "parts", trigger the log all parts function
					IF inputString = "logParts" OR inputString = "log parts" OR inputString = "parts" {
						LogAllParts().
						SET commandValid TO TRUE.
						SET loopMessage TO "Part file created!".
					} ELSE

					// if inputString is any of the planet names, point toward that planet
					SET foundBody TO "".
					FOR bod in bodList {
						IF inputString = bod:NAME AND foundBody = "" {SET foundBody TO bod.}
					}
					IF foundBody <> "" {
						SET useMySteer TO TRUE.
						SAS OFF.
						LOCK mySteer TO LOOKDIRUP(foundBody:DIRECTION:VECTOR, SHIP:UP:VECTOR).
						SET commandValid TO TRUE.
						SET loopMessage TO "Steering locked to facing the " + foundBody:NAME.
					} ELSE

					// if inputString is "List Bodies", create and log to a file on the archive a list of all bodies and their properties.
					IF inputString = "List bodies" {
						LOG "Name,Description,Mass,Radius,Rotation Period,MU,SOI Radius" TO "Bodies.csv".
						FOR bod in bodList {
							IF (bod:NAME = "Sun" OR bod:NAME = "Kerbol") {LOG bod:NAME + "," + bod:DESCRIPTION:REPLACE(",","") + "," + bod:MASS + "," + bod:RADIUS + "," + bod:ROTATIONPERIOD + "," + bod:MU + ",infinite" TO "Bodies.csv".}
							ELSE LOG bod:NAME + "," + bod:DESCRIPTION:REPLACE(",","") + "," + bod:MASS + "," + bod:RADIUS + "," + bod:ROTATIONPERIOD + "," + bod:MU + "," + bod:SOIRADIUS TO "Bodies.csv".
						}
						SET commandValid TO TRUE.
						SET loopMessage TO "Bodies.csv file created!".
					} ELSE

					// if inputString is "body" point toward the body you are orbiting
					IF inputString = "body" {SET useMySteer TO TRUE. SAS OFF. LOCK mySteer TO SHIP:BODY:DIRECTION. SET commandValid TO TRUE. SET loopMessage TO "Steering locked to facing " + SHIP:BODY:NAME.} ELSE

					// Kill command - stops all control of the vehicle
					// intended to allow the operator to stop after entering one of the above commands
					IF inputString = "kill" {endScript(). SET commandValid TO TRUE. SET loopMessage TO "Steering unlocked".} ELSE

					IF inputString = "release" {
						IF (core:part:getmodule("kOSProcessor"):HASACTION("Open Terminal")) {
							CLEARSCREEN. PRINT "Opening the terminal". WAIT 0.5.
							core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
						}
						ELSE {
							CLEARSCREEN. PRINT "Closing the terminal". WAIT 0.5.
							core:part:getmodule("kOSProcessor"):doevent("Close Terminal").
						}
						SET done TO TRUE.
					}
				}
			}
			// after processing the command, delete the command.
			IF (commandValid) {
				debugString("Command " + inputString + " completed").
				SET inputString TO "".
			}
			// if the command was not processed correctly, display an error message
			ELSE SET loopMessage TO "Did not understand input!".
		} ELSE
		// if the operator entered the backspace key, delete one letter from the input string
		IF tempChar = TERMINAL:INPUT:BACKSPACE {
			IF inputString:LENGTH >= 1 {
				SET inputString TO inputString:SUBSTRING(0, inputString:LENGTH - 1).
			}
			TOGGLE updateScreen.
		} ELSE {
		// otherwise, add the character to the input string
			SET inputString TO inputString + tempChar.
			TOGGLE updateScreen.
		}
	}
	IF count > 50 {
		SET count TO 1.
		TOGGLE updateScreen.
	}
	IF useMyThrottle SET myThrottle TO 0.
	WAIT 0.
}

CLEARSCREEN.
PRINT "Loop exited".
