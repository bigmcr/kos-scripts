@LAZYGLOBAL OFF.
LOCAL oldTime IS TIME:SECONDS.
LOCAL timeDelta IS TIME:SECONDS - oldTime.
LOCAL pointing IS LEXICON().
pointing:ADD("pitch",0).
pointing:ADD("roll",0).
pointing:ADD("yaw",0).
LOCAL resourceMasses IS LIST().
LOCAL emptyLinesToPrintDynamic IS LIST(LEXICON("string", "", "xCoord", 0, "yCoord", 0)).

// screenModes will be a lexicon, where each entry will contain the data needed for a single screen mode.
// Examples will be "static text" that is a list of strings to be printed after the main system.
// "dynamic text" will include a delegate function to call that will return the dynamic text.
LOCAL screenModes IS LEXICON().

FUNCTION createScreenModes {
	SET screenModes TO LEXICON().

	LOCAL tempMode IS LEXICON().
	LOCAL tempDelegate IS {RETURN.}.
	LOCAL staticText IS "".

// Printing of the basic UI is the first screen mode, called "Main".
//	PRINT "      VALUE     KSP CONN FALSE  Auto Steer Target PREVIOUS COMMANDS             " AT (0, 0).
//	PRINT "PIT  -00.00     LOCAL    FALSE  XXXXXXXXXXXXXXXX   PREVIOUS COMMAND 1 HERE      " AT (0, 1).
//	PRINT "ROL -000.00     MODE  XXXXXXXX  A Throttle XXXXX   PREVIOUS COMMAND 2 HERE      " AT (0, 2).
//	PRINT "YAW  000.00     dV Left  XXXXX  LS DELAY   XXXXX   PREVIOUS COMMAND 3 HERE      " AT (0, 3).
//	PRINT "                                                                                " AT (0, 4).
//	PRINT "INC  000.000 deg                                                                " AT (0, 5).
//	PRINT "PER 9999.000 sec                                                                " AT (0, 6).
//	PRINT "SMA 999.9999 km                                                                 " AT (0, 7).
//	PRINT "ECC 0.000000                                                                    " AT (0, 8).
//	PRINT "                                                                                " AT (0, 9).
//	PRINT "CURRENT INPUT                           LOOP MESSAGE                            " AT (0, 10).
//	PRINT "                                                                                " AT (0, 11).
//	PRINT "--------------------------------------------------------------------------------" AT (0, 12).
	SET staticText TO staticText + "      Value     KSP Conn        Auto Steer Target Previous Commands             " + CHAR(10).
	SET staticText TO staticText + "PIT             Local                                                           " + CHAR(10).
	SET staticText TO staticText + "ROL             Mode            A Throttle                                      " + CHAR(10).
	SET staticText TO staticText + "YAW             dV Left         LS Delay                                        " + CHAR(10).
	SET staticText TO staticText + "                                                                                " + CHAR(10).
	SET staticText TO staticText + "INC          deg                                                                " + CHAR(10).
	SET staticText TO staticText + "PER                                                                             " + CHAR(10).
	SET staticText TO staticText + "LAN          deg                                                                " + CHAR(10).
	SET staticText TO staticText + "ECC                                                                             " + CHAR(10).
	SET staticText TO staticText + "                                                                                " + CHAR(10).
	SET staticText TO staticText + "Current Input                           Loop Message                            " + CHAR(10).
	SET staticText TO staticText + "                                                                                " + CHAR(10).
	SET staticText TO staticText + "--------------------------------------------------------------------------------" + CHAR(10).
	
	SET tempDelegate TO {
		PARAMETER inputString.
		PARAMETER previousCommands.
		LOCAL linesToPrintDynamic IS LIST().
		LOCAL tempString TO "".
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(pointing["pitch"], 2):TOSTRING:PADLEFT(7), "xCoord", 4, "yCoord", 1)).
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(pointing["roll"], 2):TOSTRING:PADLEFT(7), "xCoord", 4, "yCoord", 2)).
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(pointing["yaw"], 2):TOSTRING:PADLEFT(7), "xCoord", 4, "yCoord", 3)).
		linesToPrintDynamic:ADD(LEXICON("string", connectionToKSC():TOSTRING:PADLEFT(5), "xCoord", 25, "yCoord", 0)).
		linesToPrintDynamic:ADD(LEXICON("string", runLocal:TOSTRING:PADLEFT(5), "xCoord", 25, "yCoord", 1)).
		linesToPrintDynamic:ADD(LEXICON("string", loopMode:PADLEFT(10), "xCoord", 20, "yCoord", 2)).
		IF (shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"] <> 0) {
			SET tempString TO ROUND(shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"], 0):TOSTRING:PADLEFT(5).
		} ELSE {
			SET tempString TO ROUND(shipInfo["Stage 0"]["DeltaVRCS"], 0):TOSTRING:PADLEFT(5).
		}
		linesToPrintDynamic:ADD(LEXICON("string", tempString, "xCoord", 25, "yCoord", 3)).
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(SHIP:ORBIT:INCLINATION, 3):TOSTRING:PADLEFT(8), "xCoord", 4, "yCoord", 5)).
		IF SHIP:ORBIT:SEMIMAJORAXIS > 0 SET tempString TO "PER " + timeToString(SHIP:ORBIT:PERIOD, 0):PADLEFT(12).
		ELSE							SET tempString TO "TTP " + timeToString(ETA:PERIAPSIS, 0):PADLEFT(12).
		linesToPrintDynamic:ADD(LEXICON("string", tempString, "xCoord", 0, "yCoord", 6)).
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(SHIP:ORBIT:LAN, 2):TOSTRING:PADLEFT(8), "xCoord", 4, "yCoord", 7)).
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(SHIP:ORBIT:ECCENTRICITY, 6):TOSTRING:PADLEFT(8), "xCoord", 4, "yCoord", 8)).
		IF autoSteer = "" SET tempString TO "None".
		ELSE SET tempString TO autoSteer.
		linesToPrintDynamic:ADD(LEXICON("string", tempString, "xCoord", 32, "yCoord", 1)).
		linesToPrintDynamic:ADD(LEXICON("string", globalThrottle:TOSTRING:PADLEFT(5), "xCoord", 43, "yCoord", 2)).
		IF (connectionToKSC()) {
			IF HOMECONNECTION:DELAY < 0.1 SET tempString TO "<0.1s".
			ELSE SET tempString TO timeToString(HOMECONNECTION:DELAY, 1):TOSTRING:PADLEFT(5).
		} ELSE SET tempString TO "  N/A".
		linesToPrintDynamic:ADD(LEXICON("string", tempString, "xCoord", 43, "yCoord", 3)).
		// print the current input from the operator
		linesToPrintDynamic:ADD(LEXICON("string", inputString, "xCoord", 0, "yCoord", 11)).
		// display any messages from the loop program
		linesToPrintDynamic:ADD(LEXICON("string", loopMessage, "xCoord", 40, "yCoord", 11)).
		FOR index IN RANGE(1, 8, 1) {
			IF previousCommands:LENGTH >= index linesToPrintDynamic:ADD(LEXICON("string", previousCommands[previousCommands:LENGTH - index]:PADRIGHT(29), "xCoord", 51, "yCoord", index)).
		}
		RETURN linesToPrintDynamic.
	}.

	tempMode:ADD("name", "Main").
	tempMode:ADD("labels", LIST("")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", tempDelegate).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays all resources and related data.
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".

	SET staticText TO staticText + "Name              Quantity            Mass       Prod/Cons Rate" + CHAR(10).
	SET staticText TO staticText + "                    Liters              kg          kg/s or u/s" + CHAR(10).
	
	FOR eachResource IN SHIP:RESOURCES {
		SET staticText TO staticText + eachResource:NAME:PADLEFT(15) + CHAR(10).
	}
	
	SET tempDelegate TO {
		LOCAL rowNumber IS + screenModes["Main"]["lineCount"] + 2.
		LOCAL tempString IS "".
		LOCAL linesToPrintDynamic IS LIST().
		FOR eachResource IN SHIP:RESOURCES {
			SET tempString TO ROUND(resourceList[eachResource:NAME]["Quantity"], 3):TOSTRING:PADLEFT(11) +
							 (ROUND(resourceList[eachResource:NAME]["Mass"], 3)):TOSTRING:PADLEFT(16) +
							 (ROUND(resourceList[eachResource:NAME]["Quantity Use"], 4)):TOSTRING:PADLEFT(21).
			linesToPrintDynamic:ADD(LEXICON("string", tempString, "xCoord", 15, "yCoord", rowNumber)).
			SET rowNumber TO rowNumber + 1.
		}
		RETURN linesToPrintDynamic.
	}.
	
	tempMode:ADD("name", "Resources").
	tempMode:ADD("labels", LIST("Resources", "Resource")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", tempDelegate).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays information about the selected orbit.	
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".

	LOCAL localOrbit IS SHIP:ORBIT.
	IF loopMode = "OrbitNext" AND ORBIT:HASNEXTPATCH {
		SET localOrbit TO ORBIT:NEXTPATCH.
		SET staticText TO staticText + "Name " + localOrbit:NAME + CHAR(10).
	}
	IF loopMode = "OrbitTarget" AND HASTARGET {
		SET localOrbit TO TARGET:ORBIT.
		SET staticText TO staticText + "Name " + localOrbit:NAME + CHAR(10).
	}
	IF loopMode = "OrbitTargetNext" AND HASTARGET AND TARGET:ORBIT:HASNEXTPATCH {
		IF HASTARGET AND TARGET:ORBIT:HASNEXTPATCH SET localOrbit TO TARGET:ORBIT:NEXTPATCH.
		SET staticText TO staticText + "Name " + localOrbit:NAME + CHAR(10).
	}
	IF loopMode = "OrbitNode" AND HASNODE {
		IF HASNODE SET localOrbit TO NEXTNODE:ORBIT.
		SET staticText TO staticText + "Name " + localOrbit:NAME + CHAR(10).
	}
	SET staticText TO staticText + "Apoapsis " + CHAR(10).
	SET staticText TO staticText + "Periapsis " + CHAR(10).
	IF localOrbit:ECCENTRICITY > 1 {
		SET staticText TO staticText + "Period N/A s" + CHAR(10).
	} ELSE {
		SET staticText TO staticText + "Period " + CHAR(10).
		SET staticText TO staticText + "Period " + CHAR(10).
	}
	SET staticText TO staticText + "Inclination " + CHAR(10).
	SET staticText TO staticText + "Eccentricity " + CHAR(10).
	SET staticText TO staticText + "Semi-Major Axis " + CHAR(10).
	SET staticText TO staticText + "Semi-Minor Axis " + CHAR(10).
	SET staticText TO staticText + "Longitude of Ascending Node " + CHAR(10).
	SET staticText TO staticText + "Argument of Periapsis " + CHAR(10).
	SET staticText TO staticText + "True Anomaly " + CHAR(10).
	SET staticText TO staticText + "Mean Anomaly " + CHAR(10).
	SET staticText TO staticText + "Transition " + CHAR(10).
	SET staticText TO staticText + "Flight path angle " + CHAR(10).
	SET staticText TO staticText + "Position (r) " + CHAR(10).
	SET staticText TO staticText + "Velocity " + CHAR(10).
	SET staticText TO staticText + "Has Next Patch " + CHAR(10).
	IF localOrbit:HASNEXTPATCH {
		SET staticText TO staticText + "Next Patch ETA " + CHAR(10).
	}

	tempMode:ADD("name", "Orbit").
	tempMode:ADD("labels", LIST("Orbit", "OrbitNext", "OrbitTarget", "OrbitTargetNext", "OrbitNode")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {
		LOCAL rowNumber IS + screenModes["Main"]["lineCount"].
		LOCAL linesToPrintDynamic IS LIST().
		LOCAL localOrbit IS SHIP:ORBIT.
		IF loopMode = "OrbitNext" AND ORBIT:HASNEXTPATCH {
			SET localOrbit TO ORBIT:NEXTPATCH.
			SET rowNumber TO rowNumber + 1.
		}
		IF loopMode = "OrbitTarget" AND HASTARGET {
			SET localOrbit TO TARGET:ORBIT.
			SET rowNumber TO rowNumber + 1.
		}
		IF loopMode = "OrbitTargetNext" AND HASTARGET AND TARGET:ORBIT:HASNEXTPATCH {
			IF HASTARGET AND TARGET:ORBIT:HASNEXTPATCH {
				SET localOrbit TO TARGET:ORBIT:NEXTPATCH.
				SET rowNumber TO rowNumber + 1.
			}
		}
		IF loopMode = "OrbitNode" AND HASNODE {
			IF HASNODE {
				SET localOrbit TO NEXTNODE:ORBIT.
				SET rowNumber TO rowNumber + 1.
			}
		}
		linesToPrintDynamic:ADD(LEXICON("string", distanceToString(localOrbit:APOAPSIS, 4), "xCoord", 9, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", distanceToString(localOrbit:PERIAPSIS, 4), "xCoord", 10, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		IF localOrbit:ECCENTRICITY <= 1 {
			linesToPrintDynamic:ADD(LEXICON("string", timeToString(localOrbit:PERIOD, 4), "xCoord", 7, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
			linesToPrintDynamic:ADD(LEXICON("string", localOrbit:PERIOD + " s", "xCoord", 7, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		} ELSE SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(localOrbit:INCLINATION, 4) + " deg", "xCoord", 12, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(localOrbit:ECCENTRICITY, 4) + " deg", "xCoord", 13, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", distanceToString(localOrbit:SEMIMAJORAXIS, 4), "xCoord", 16, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", distanceToString(localOrbit:SEMIMINORAXIS, 4), "xCoord", 16, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(localOrbit:LAN, 4) + " deg", "xCoord", 28, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(localOrbit:ARGUMENTOFPERIAPSIS, 4) + " deg", "xCoord", 22, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(localOrbit:TRUEANOMALY, 4) + " deg", "xCoord", 13, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(trueToMeanAnomaly(localOrbit:TRUEANOMALY, localOrbit:ECCENTRICITY), 4) + " deg", "xCoord", 13, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", localOrbit:TRANSITION, "xCoord", 11, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(flightPathAngle(localOrbit:TRUEANOMALY, localOrbit:ECCENTRICITY), 4) + " deg", "xCoord", 18, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", distanceToString((localOrbit:POSITION - localOrbit:BODY:POSITION):MAG, 4), "xCoord", 13, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", distanceToString(localOrbit:VELOCITY:ORBIT:MAG, 4) + "/s", "xCoord", 9, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", localOrbit:HASNEXTPATCH, "xCoord", 15, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		IF localOrbit:HASNEXTPATCH {
			linesToPrintDynamic:ADD(LEXICON("string", timeToString(localOrbit:NEXTPATCHETA), "xCoord", 15, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		}
		RETURN linesToPrintDynamic.
	}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays information about the body being orbited.
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".
	
	SET staticText TO staticText + "Orbited Body " + SHIP:BODY:NAME + CHAR(10).
	SET staticText TO staticText + "Mass " + SHIP:BODY:MASS + " kg" + CHAR(10).
	SET staticText TO staticText + "Has Ocean " + SHIP:BODY:HASOCEAN + CHAR(10).
	SET staticText TO staticText + "Has Solid Surface " + SHIP:BODY:HASSOLIDSURFACE + CHAR(10).
	SET staticText TO staticText + "Has Children " + (SHIP:BODY:ORBITINGCHILDREN:LENGTH<>0) + CHAR(10).
	IF SHIP:BODY:ORBITINGCHILDREN:LENGTH <> 0 {
		SET staticText TO staticText + "Children Names: ".
		FOR eachChild IN SHIP:BODY:ORBITINGCHILDREN {
			SET staticText TO staticText + eachChild:NAME + " ".
		}
		SET staticText TO staticText + CHAR(10).
	}
	SET staticText TO staticText + "Rotation Period " + timeToString(SHIP:BODY:ROTATIONPERIOD) + CHAR(10).
	SET staticText TO staticText + "Rotation Period " + SHIP:BODY:ROTATIONPERIOD + " s" + CHAR(10).
	SET staticText TO staticText + "Radius " + distanceToString(SHIP:BODY:Radius, 4) + CHAR(10).
	SET staticText TO staticText + "MU " + SHIP:BODY:MU + " m^3/s^2" + CHAR(10).
	SET staticText TO staticText + "Atmosphere " + SHIP:BODY:ATM:EXISTS + CHAR(10).
	IF SHIP:BODY:HASBODY SET staticText TO staticText + "SOI Radius " + distanceToString(SHIP:BODY:SOIRADIUS) + CHAR(10).
	ELSE SET staticText TO staticText + "SOI Radius infinite" + CHAR(10).
	SET staticText TO staticText + "Rotation Angle " + CHAR(10).
	
	tempMode:ADD("name", "Body").
	tempMode:ADD("labels", LIST("Body")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {
		LOCAL linesToPrintDynamic IS LIST().
		LOCAL rowNumber IS + screenModes["Main"]["lineCount"] + countCharacters(screenModes["Body"]["staticText"], CHAR(10)) - 1.
		linesToPrintDynamic:ADD(LEXICON("string", ROUND(SHIP:BODY:ROTATIONANGLE, 4) + " deg    ", "xCoord", 15, "yCoord", rowNumber)).
		RETURN linesToPrintDynamic.
	}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays information about the kOS processors on the ship
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".
	
	{
		LOCAL names IS "".
		LOCAL capacities IS "".
		LOCAL freeSpaces IS "".
		LOCAL fileCounts IS "".
		LOCAL powerReqs IS "".
		LOCAL bootFiles IS "".
		LOCAL processorList IS LIST().
		LIST PROCESSORS IN processorList.
		FOR eachProc IN processorList {
			IF eachProc:VOLUME:NAME <> "" SET names TO names + eachProc:VOLUME:NAME:PADLEFT(10).
			ELSE SET names TO names + "      None".
			SET capacities TO capacities + eachProc:VOLUME:CAPACITY:TOSTRING:PADLEFT(10).
			SET freeSpaces TO freeSpaces + eachProc:VOLUME:FREESPACE:TOSTRING:PADLEFT(10).
			SET fileCounts TO fileCounts + eachProc:VOLUME:FILES:LENGTH:TOSTRING:PADLEFT(10).
			SET powerReqs TO powerReqs + ROUND(eachProc:VOLUME:POWERREQUIREMENT, 2):TOSTRING:PADLEFT(10).
			SET bootFiles TO bootFiles + eachProc:BOOTFILENAME:PADLEFT(10).
		}
		SET staticText TO staticText + "Processor count           " + processorList:LENGTH:TOSTRING:PADLEFT(10) + CHAR(10).
		SET staticText TO staticText + "Volume Name               " + names + CHAR(10).
		SET staticText TO staticText + "Volume Capacity           " + capacities + " bytes" + CHAR(10).
		SET staticText TO staticText + "Volume Free Space         " + freeSpaces + " bytes" + CHAR(10).
		SET staticText TO staticText + "Volume File Count         " + fileCounts + CHAR(10).
		SET staticText TO staticText + "Volume Power Requirement  " + powerReqs + " E/s" + CHAR(10).
		SET staticText TO staticText + "Core Boot File            " + bootFiles + CHAR(10).
	}
	
	tempMode:ADD("name", "Processors").
	tempMode:ADD("labels", LIST("Processor", "Processors", "kOS", "CPU")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {RETURN emptyLinesToPrintDynamic.}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays information about the ship itself - part number and dV and similar info.
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".
	
	SET staticText TO staticText + "Part Count         " + SHIP:PARTS:LENGTH:TOSTRING:PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "DeltaV             " + (ROUND(SHIP:DELTAV:CURRENT, 2) + " m/s"):PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "DeltaV Custom      " + (ROUND(shipInfo["CurrentStage"]["DeltaV"], 2) + " m/s"):PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "DeltaV RCS         " + (ROUND(shipInfo["CurrentStage"]["DeltaVRCS"], 2) + " m/s"):PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "Stage Number       " + SHIP:STAGENUM:TOSTRING:PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "Current Stage      " + shipInfo["NumberOfStages"]:TOSTRING:PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "Type               " + SHIP:TYPE:PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "Crew Capacity      " + SHIP:CREWCAPACITY:TOSTRING:PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "Current Crew Count " + SHIP:CREW:LENGTH:TOSTRING:PADLEFT(10) + CHAR(10).
	SET staticText TO staticText + "Resource Count     " + SHIP:RESOURCES:LENGTH:TOSTRING:PADLEFT(10) + CHAR(10).

	tempMode:ADD("name", "Ship").
	tempMode:ADD("labels", LIST("Ship", "deltaV", "dV")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {
		LOCAL linesToPrintDynamic IS LIST().
		LOCAL rowNumber IS + screenModes["Main"]["lineCount"].
		linesToPrintDynamic:ADD(LEXICON("string", SHIP:PARTS:LENGTH:TOSTRING:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", (ROUND(SHIP:DELTAV:CURRENT, 2) + " m/s"):PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", (ROUND(shipInfo["CurrentStage"]["DeltaV"], 2) + " m/s"):PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", (ROUND(shipInfo["CurrentStage"]["DeltaVRCS"], 2) + " m/s"):PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", SHIP:STAGENUM:TOSTRING:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", shipInfo["NumberOfStages"]:TOSTRING:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", SHIP:TYPE:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", SHIP:CREWCAPACITY:TOSTRING:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", SHIP:CREW:LENGTH:TOSTRING:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		linesToPrintDynamic:ADD(LEXICON("string", SHIP:RESOURCES:LENGTH:TOSTRING:PADLEFT(10), "xCoord", 19, "yCoord", rowNumber)). SET rowNumber TO rowNumber + 1.
		RETURN linesToPrintDynamic.
	}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays information about the RCS thrusters
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".
	
	SET staticText TO staticText + "Thruster       Enabled    Yaw  Pitch   Roll   Fore   Stbd    Top    ISP  " + CHAR(10).
	FOR eachRCS IN shipInfo["CurrentStage"]["RCS"] {
		SET staticText TO staticText + eachRCS:TITLE:SUBSTRING(0, eachRCS:TITLE:FIND(" ")):PADRIGHT(15) + CHAR(10).
	}

	tempMode:ADD("name", "RCS").
	tempMode:ADD("labels", LIST("RCS", "Thrusters", "Thruster")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {
		LOCAL linesToPrintDynamic IS LIST().
		LOCAL rowNumber IS + screenModes["Main"]["lineCount"] + 1.
		FOR eachRCS IN shipInfo["CurrentStage"]["RCS"] {
			linesToPrintDynamic:ADD(LEXICON("string",
				eachRCS:ENABLED:TOSTRING:PADLEFT(6) +
				eachRCS:YAWENABLED:TOSTRING:PADLEFT(7) +
				eachRCS:PITCHENABLED:TOSTRING:PADLEFT(7) +
				eachRCS:ROLLENABLED:TOSTRING:PADLEFT(7) +
				eachRCS:FOREENABLED:TOSTRING:PADLEFT(7) +
				eachRCS:STARBOARDENABLED:TOSTRING:PADLEFT(7) +
				eachRCS:TOPENABLED:TOSTRING:PADLEFT(7) +
				ROUND(eachRCS:ISP, 0):TOSTRING:PADLEFT(7), "xCoord", 16, "yCoord", rowNumber)).
			SET rowNumber TO rowNumber + 1.
		}
		linesToPrintDynamic:ADD(LEXICON("string", "Total dV from RCS in current stage: " + ROUND(shipInfo["CurrentStage"]["deltaVRCS"], 2) + " m/s", "xCoord", 0, "yCoord", rowNumber)).
		RETURN linesToPrintDynamic.
	}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This screen mode displays information about the engines on the current stage
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".
	
	SET staticText TO staticText + "Engine       Thrust  ISP  M Dot    Ign    Gimbal   Min Throttle Stab" + CHAR(10).
	SET staticText TO staticText + "Name         Newton    s   kg/s              Deg              %" + CHAR(10).
	FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
		SET staticText TO staticText + (CHOOSE eachEngine:TITLE:PADRIGHT(13) IF eachEngine:TITLE:FIND(" ") = -1 ELSE eachEngine:TITLE:SUBSTRING(0, eachEngine:TITLE:FIND(" ")):PADRIGHT(13)) + CHAR(10).
	}

	tempMode:ADD("name", "Engines").
	tempMode:ADD("labels", LIST("Engines", "Engine")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {
		LOCAL linesToPrintDynamic IS LIST().
		LOCAL rowNumber IS + screenModes["Main"]["lineCount"] + 2.
		FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
			linesToPrintDynamic:ADD(LEXICON("string",
				ROUND(eachEngine:MAXTHRUST * 1000):TOSTRING:PADLEFT(5) +
				ROUND(eachEngine:ISP):TOSTRING:PADLEFT(5) +
				ROUND(eachEngine:MAXMASSFLOW * 1000):TOSTRING:PADLEFT(7) +
				(CHOOSE "    inf" IF eachEngine:IGNITIONS = -1 ELSE eachEngine:IGNITIONS:TOSTRING:PADLEFT(7)) +
				(CHOOSE ("0":PADLEFT(10)) IF NOT eachEngine:HASGIMBAL ELSE eachEngine:GIMBAL:RANGE:TOSTRING:PADLEFT(10)) +
				(eachEngine:MINTHROTTLE*100):TOSTRING:PADLEFT(15) +
				ROUND(eachEngine:FUELSTABILITY * 100):TOSTRING:PADLEFT(5), 
				"xCoord", 14, "yCoord", rowNumber)).
			SET rowNumber TO rowNumber + 1.
		}
		RETURN linesToPrintDynamic.
	}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// This very simple screen mode displays information about the universe and rocket part types that kOS has loaded.
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".
	
	SET staticText TO staticText + "Stock Rockets: " + isStockRockets() + CHAR(10).
	SET staticText TO staticText + "Stock World: " + isStockWorld() + CHAR(10).

	tempMode:ADD("name", "Universe").
	tempMode:ADD("labels", LIST("Universe", "World", "settings")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {RETURN emptyLinesToPrintDynamic.}).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).
	
// This screen mode displays what modes are avaialble.
	SET tempMode TO LEXICON().
	SET tempDelegate TO {RETURN.}.
	SET staticText TO "".

	SET staticText TO staticText + "The following are all valid options for LoopMode" + CHAR(10).
	SET staticText TO staticText + "Anything else will be treated the same as Default:" + CHAR(10).
	
	FOR modeName IN screenModes:KEYS {
		IF modeName <> "Main" {
			SET staticText TO staticText + "   ".
			FOR eachLabel IN screenModes[modeName]["labels"] {
				SET staticText TO staticText + " " + eachLabel.
			}
			SET staticText TO staticText + CHAR(10).
		}
	}

	tempMode:ADD("name", "Info").
	tempMode:ADD("labels", LIST("info", "help")).
	tempMode:ADD("staticText", staticText).
	tempMode:ADD("delegate", {RETURN emptyLinesToPrintDynamic.} ).
	tempMode:ADD("lineCount", countCharacters(staticText, CHAR(10))).
	screenModes:ADD(tempMode["Name"], tempMode).

// Return all screen modes.
	RETURN screenModes.
}

FUNCTION updateScreenDynamic {
	PARAMETER inputString.
	PARAMETER previousCommands.
	SET timeDelta TO TIME:SECONDS - oldTime.
	IF timeDelta > 0 {
		SET pointing["pitch"] TO pitch_for(SHIP).
		SET pointing["roll"] TO roll_for(SHIP).
		SET pointing["yaw"] TO yaw_for(SHIP).
		FOR resource IN SHIP:RESOURCES {
			SET resourceList[resource:NAME]["Quantity Use"] TO (resource:AMOUNT - resourceList[resource:NAME]["Quantity"]) / timeDelta.
			SET resourceList[resource:NAME]["Mass Use"] TO (resource:AMOUNT * densityLookUp[resource:NAME] - resourceList[resource:NAME]["Mass"]) / timeDelta.
			SET resourceList[resource:NAME]["Quantity"] TO resource:AMOUNT.
			SET resourceList[resource:NAME]["Mass"] TO resource:AMOUNT * densityLookUp[resource:NAME].
		}
		SET oldTime TO TIME:SECONDS.
	}
	printDynamicLines(screenModes["Main"]["delegate"](inputString, previousCommands)).
	FOR modeName IN screenModes:KEYS {
		FOR eachLabel IN screenModes[modeName]["labels"] {
			IF loopMode = eachLabel {
				printDynamicLines(screenModes[modeName]["delegate"]()).
			}
		}
	}
	updateFacingVectors().
}

FUNCTION updateScreenStatic {
	CLEARSCREEN.
	PRINT screenModes["Main"]["staticText"].
	FOR modeName IN screenModes:KEYS {
		FOR eachLabel IN screenModes[modeName]["labels"] {
			IF loopMode = eachLabel PRINT screenModes[modeName]["staticText"].
		}
	}
}

LOCAL oldScreenUpdateTime IS TIME:SECONDS.
LOCAL firstScan IS TRUE.
LOCAL oldLoopMode IS loopMode.

FUNCTION updateScreen {
	PARAMETER inputString, previousCommands, forceUpdate IS FALSE.
	IF firstScan OR oldLoopMode <> loopMode{
		createScreenModes().
		updateScreenStatic().
		SET firstScan TO FALSE.
		SET oldLoopMode TO loopMode.
	}
	updateScreenDynamic(inputString, previousCommands).

	IF (TIME:SECONDS - oldScreenUpdateTime > 60) OR firstScan OR forceUpdate {
		SET oldScreenUpdateTime TO TIME:SECONDS.
		SET firstScan TO TRUE.
		SET forceUpdate TO FALSE.
	}
	RETURN.
}
