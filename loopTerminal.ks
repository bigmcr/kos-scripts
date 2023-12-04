@LAZYGLOBAL OFF.
LOCAL oldTime IS TIME:SECONDS.
LOCAL timeDelta IS TIME:SECONDS - oldTime.
LOCAL pointing IS LEXICON().
pointing:ADD("pitch",0).
pointing:ADD("roll",0).
pointing:ADD("yaw",0).
LOCAL resourceMasses IS LIST().

FUNCTION updateScreen {
  PARAMETER inputString, previousCommands.
	CLEARSCREEN.
  // Printing of the basic UI and related data is done using the PRINT AT command.
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
	PRINT "      Value     KSP Conn        Auto Steer Target Previous Commands             " AT (0, 0).
	PRINT "PIT             Local                                                           " AT (0, 1).
	PRINT "ROL             Mode            A Throttle                                      " AT (0, 2).
	PRINT "YAW             dV Left         LS Delay                                        " AT (0, 3).
	PRINT "                                                                                " AT (0, 4).
	PRINT "INC          deg                                                                " AT (0, 5).
	PRINT "PER                                                                             " AT (0, 6).
	PRINT "SMA                                                                             " AT (0, 7).
	PRINT "ECC                                                                             " AT (0, 8).
	PRINT "                                                                                " AT (0, 9).
	PRINT "Current Input                           Loop Message                            " AT (0, 10).
	PRINT "                                                                                " AT (0, 11).
	PRINT "--------------------------------------------------------------------------------" AT (0, 12).

	PRINT ROUND(pointing["pitch"], 2):TOSTRING:PADLEFT(7) AT (4, 1).
	PRINT ROUND(pointing["roll"], 2):TOSTRING:PADLEFT(7) AT (4, 2).
	PRINT ROUND(pointing["yaw"], 2):TOSTRING:PADLEFT(7) AT (4, 3).
	PRINT connectionToKSC():TOSTRING:PADLEFT(5) AT (25, 0).
	PRINT runLocal:TOSTRING:PADLEFT(5) AT (25, 1).
	PRINT loopMode:PADLEFT(10) AT (20, 2).
  IF (shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"] <> 0) {
    PRINT ROUND(shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"], 0):TOSTRING:PADLEFT(5) AT (25, 3).
  } ELSE {
    PRINT ROUND(shipInfo["Stage 0"]["DeltaVRCS"], 0):TOSTRING:PADLEFT(5) AT (25, 3).
  }

	PRINT ROUND(SHIP:ORBIT:INCLINATION, 3):TOSTRING:PADLEFT(8) AT (4, 5).
	IF SHIP:ORBIT:SEMIMAJORAXIS > 0 PRINT timeToString(SHIP:ORBIT:PERIOD, 0):PADLEFT(12) AT (4, 6).
	ELSE							PRINT "TTP " + timeToString(ETA:PERIAPSIS, 0):PADLEFT(12) AT (0,6).
	PRINT distanceToString(SHIP:ORBIT:SEMIMAJORAXIS, 4):PADLEFT(11) AT (4, 7).
	PRINT ROUND(SHIP:ORBIT:ECCENTRICITY, 6):TOSTRING:PADLEFT(8) AT (4, 8).

  IF autoSteer = "" PRINT "None" AT (32, 1).
  ELSE PRINT autoSteer AT (32, 1).
  PRINT globalThrottle:TOSTRING:PADLEFT(5) AT (43, 2).
	IF (connectionToKSC()) PRINT timeToString(HOMECONNECTION:DELAY, 0):TOSTRING:PADLEFT(5) AT (43, 3).
	ELSE PRINT "  N/A" AT (43, 3).

	// print the current input from the operator
	PRINT inputString AT (0, 11).

	// display any messages from the loop program
	PRINT loopMessage AT (40, 11).
	IF previousCommands:LENGTH > 0 PRINT previousCommands[previousCommands:LENGTH - 1]:PADRIGHT(29) AT (51, 1).
	IF previousCommands:LENGTH > 1 PRINT previousCommands[previousCommands:LENGTH - 2]:PADRIGHT(29) AT (51, 2).
	IF previousCommands:LENGTH > 2 PRINT previousCommands[previousCommands:LENGTH - 3]:PADRIGHT(29) AT (51, 3).
	IF previousCommands:LENGTH > 3 PRINT previousCommands[previousCommands:LENGTH - 4]:PADRIGHT(29) AT (51, 4).
	IF previousCommands:LENGTH > 4 PRINT previousCommands[previousCommands:LENGTH - 5]:PADRIGHT(29) AT (51, 5).
	IF previousCommands:LENGTH > 5 PRINT previousCommands[previousCommands:LENGTH - 6]:PADRIGHT(29) AT (51, 6).
	IF previousCommands:LENGTH > 6 PRINT previousCommands[previousCommands:LENGTH - 7]:PADRIGHT(29) AT (51, 7).


  // Printing of the mode commands is done via a function.
  LOCAL linesToPrint IS LIST().
	IF loopMode = "Resources" OR loopMode = "Resource" {
    linesToPrint:ADD("Name              Quantity         Mass     Prod/Cons Rate").
    linesToPrint:ADD("                    Liters           kg        kg/s or u/s").
		LOCAL index IS 0.
		FOR eachResource IN SHIP:RESOURCES {
			linesToPrint:ADD(eachResource:NAME:PADLEFT(15) +
						ROUND(resourceList[eachResource:NAME]["Quantity"], 3):TOSTRING:PADLEFT(11) +
						(ROUND(resourceList[eachResource:NAME]["Mass"], 3)):TOSTRING:PADLEFT(16) +
						(ROUND(resourceList[eachResource:NAME]["Quantity Use"], 4)):TOSTRING:PADLEFT(21)).
			SET index TO index + 1.
		}
	} ELSE IF loopMode = "Orbit" OR loopMode = "targetorbit" {
		LOCAL localOrbit IS SHIP:ORBIT.
		IF loopMode = "targetorbit" AND HASTARGET SET localOrbit TO TARGET:ORBIT.
		linesToPrint:ADD("Name " + localOrbit:NAME).
		linesToPrint:ADD("Apoapsis " + distanceToString(localOrbit:APOAPSIS, 4)).
		linesToPrint:ADD("Periapsis " + distanceToString(localOrbit:PERIAPSIS, 4)).
		linesToPrint:ADD("Period " + timeToString(localOrbit:PERIOD, 4)).
		linesToPrint:ADD("Period " + localOrbit:PERIOD + " s").
		linesToPrint:ADD("Inclination " + ROUND(localOrbit:INCLINATION, 4) + " deg").
		linesToPrint:ADD("Eccentricity " + ROUND(localOrbit:ECCENTRICITY, 4)).
		linesToPrint:ADD("Semi-Major Axis " + distanceToString(localOrbit:SEMIMAJORAXIS, 4)).
		linesToPrint:ADD("Semi-Minor Axis " + distanceToString(localOrbit:SEMIMINORAXIS, 4)).
		linesToPrint:ADD("Longitude of Ascending Node " + ROUND(localOrbit:LAN, 4) + " deg").
		linesToPrint:ADD("Argument of Periapsis " + ROUND(localOrbit:ARGUMENTOFPERIAPSIS, 4) + " deg").
		linesToPrint:ADD("True Anomaly  " + ROUND(localOrbit:TRUEANOMALY, 4) + " deg").
		linesToPrint:ADD("Mean Anomaly at Epoch " + ROUND(localOrbit:MEANANOMALYATEPOCH, 4) + " deg").
    linesToPrint:ADD("Mean Anomaly " + ROUND(trueToMeanAnomaly(localOrbit:TRUEANOMALY, localOrbit:ECCENTRICITY), 4) + " deg").
		linesToPrint:ADD("Epoch " + localOrbit:EPOCH).
		linesToPrint:ADD("Transition " + localOrbit:TRANSITION).
    IF VERTICALSPEED < 0 linesToPrint:ADD("Flight path angle -" + ROUND(ABS(90 - VANG(-BODY:POSITION, SHIP:VELOCITY:ORBIT)), 4) + " deg").
    ELSE linesToPrint:ADD("Flight path angle " + ROUND(ABS(90 - VANG(-BODY:POSITION, SHIP:VELOCITY:ORBIT)), 4) + " deg").
		linesToPrint:ADD("Position (r) " + distanceToString(SHIP:BODY:POSITION:MAG, 4)).
		linesToPrint:ADD("Velocity " + distanceToString(localOrbit:VELOCITY:ORBIT:MAG, 4) + "/s").
		linesToPrint:ADD("Has Next Patch " + localOrbit:HASNEXTPATCH).
		IF localOrbit:HASNEXTPATCH {
		  linesToPrint:ADD("Next Patch ETA " + timeToString(localOrbit:NEXTPATCHETA)).
		}
  } ELSE IF loopMode = "Body" {
    linesToPrint:ADD("Orbited Body " + SHIP:ORBIT:BODY:NAME).
    linesToPrint:ADD("Orbited Body MU " + SHIP:ORBIT:BODY:MU + " m^3/s^2").
    linesToPrint:ADD("Orbited Body Radius " + distanceToString(SHIP:ORBIT:BODY:Radius, 4)).
	} ELSE IF loopMode = "Processor" OR loopMode = "kOS" {
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
      SET fileCounts TO fileCounts + CORE:VOLUME:FILES:LENGTH:TOSTRING:PADLEFT(10).
      SET powerReqs TO powerReqs + ROUND(CORE:VOLUME:POWERREQUIREMENT, 2):TOSTRING:PADLEFT(10).
      SET bootFiles TO bootFiles + CORE:BOOTFILENAME:PADLEFT(10).
    }
    linesToPrint:ADD("Processor count           " + processorList:LENGTH:TOSTRING:PADLEFT(10)).
    linesToPrint:ADD("Volume Name               " + names).
    linesToPrint:ADD("Volume Capacity           " + capacities + " bytes").
    linesToPrint:ADD("Volume Free Space         " + freeSpaces + " bytes").
    linesToPrint:ADD("Volume File Count         " + fileCounts).
    linesToPrint:ADD("Volume Power Requirement  " + powerReqs + " E/s").
    linesToPrint:ADD("Core Boot File            " + bootFiles).
  } ELSE IF loopMode = "Ship" {
    linesToPrint:ADD("Part Count         " + SHIP:PARTS:LENGTH:TOSTRING:PADLEFT(10)).
    linesToPrint:ADD("DeltaV             " + (ROUND(SHIP:DELTAV:CURRENT, 2) + "m/s"):PADLEFT(10)).
    linesToPrint:ADD("DeltaV Custom      " + (ROUND(shipInfo["CurrentStage"]["DeltaV"], 2) + "m/s"):PADLEFT(10)).
    linesToPrint:ADD("Stage Number       " + SHIP:STAGENUM:TOSTRING:PADLEFT(10)).
    linesToPrint:ADD("Current Stage      " + shipInfo["NumberOfStages"]:TOSTRING:PADLEFT(10)).
    linesToPrint:ADD("Type               " + SHIP:TYPE:PADLEFT(10)).
    linesToPrint:ADD("Crew Capacity      " + SHIP:CREWCAPACITY:TOSTRING:PADLEFT(10)).
    linesToPrint:ADD("Current Crew Count " + SHIP:CREW:LENGTH:TOSTRING:PADLEFT(10)).
    linesToPrint:ADD("Resource Count     " + SHIP:RESOURCES:LENGTH:TOSTRING:PADLEFT(10)).
  } ELSE IF loopMode = "RCS" {
    linesToPrint:ADD("Thruster       Enabled    Yaw  Pitch   Roll   Fore   Stbd    Top    ISP  ").
    FOR eachRCS IN shipInfo["CurrentStage"]["RCS"] {
      linesToPrint:ADD(eachRCS:TITLE:SUBSTRING(0, eachRCS:TITLE:FIND(" ")):PADRIGHT(15) +
            eachRCS:ENABLED:TOSTRING:PADLEFT(7) +
            eachRCS:YAWENABLED:TOSTRING:PADLEFT(7) +
            eachRCS:PITCHENABLED:TOSTRING:PADLEFT(7) +
            eachRCS:ROLLENABLED:TOSTRING:PADLEFT(7) +
            eachRCS:FOREENABLED:TOSTRING:PADLEFT(7) +
            eachRCS:STARBOARDENABLED:TOSTRING:PADLEFT(7) +
            eachRCS:TOPENABLED:TOSTRING:PADLEFT(7) +
            ROUND(eachRCS:ISP, 0):TOSTRING:PADLEFT(7)).
    }
  } ELSE IF loopMode = "engines" {
    linesToPrint:ADD("Engine       Thrust  ISP  M Dot    Ign    Gimbal   Min Throttle Stab").
    linesToPrint:ADD("Name         Newton    s   kg/s              Deg              %").
    FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
      linesToPrint:ADD(
        (CHOOSE eachEngine:TITLE:PADRIGHT(13) IF eachEngine:TITLE:FIND(" ") = -1 ELSE eachEngine:TITLE:SUBSTRING(0, eachEngine:TITLE:FIND(" ")):PADRIGHT(13)) +
        ROUND(eachEngine:MAXTHRUST * 1000):TOSTRING:PADLEFT(6) +
        ROUND(eachEngine:ISP):TOSTRING:PADLEFT(5) +
        ROUND(eachEngine:MAXMASSFLOW * 1000):TOSTRING:PADLEFT(7) +
        eachEngine:IGNITIONS:TOSTRING:PADLEFT(7) +
        (CHOOSE ("0":PADLEFT(10)) IF NOT eachEngine:HASGIMBAL ELSE eachEngine:GIMBAL:RANGE:TOSTRING:PADLEFT(10)) +
        (eachEngine:MINTHROTTLE*100):TOSTRING:PADLEFT(15) +
        ROUND(eachEngine:FUELSTABILITY * 100):TOSTRING:PADLEFT(5)).
    }
  } ELSE IF loopMode = "Universe" OR loopMode = "World" {
    linesToPrint:ADD("Stock Rockets: " + isStockRockets()).
    linesToPrint:ADD("Stock World: " + isStockWorld()).
  }
  printLines(linesToPrint, 13).

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
  updateFacingVectors().
	RETURN TRUE.
}
