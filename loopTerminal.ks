@LAZYGLOBAL OFF.
LOCAL oldTime IS MISSIONTIME.
LOCAL timeDelta IS MISSIONTIME - oldTime.
LOCAL pointing IS LEXICON().
pointing:ADD("pitch",0).
pointing:ADD("roll",0).
pointing:ADD("yaw",0).
LOCAL resourceMasses IS LIST().

FUNCTION updateScreen {
  PARAMETER inputString, previousCommands.
	CLEARSCREEN.
//	PRINT "      VALUE     KSP CONN FALSE  Auto Steer Target PREVIOUS COMMANDS             " AT (0, 0).
//	PRINT "PIT  -00.00     LOCAL    FALSE  XXXXXXXXXXXXXXXX   PREVIOUS COMMAND 1 HERE      " AT (0, 1).
//	PRINT "ROL -000.00     MODE  XXXXXXXX  dV Left    XXXXX   PREVIOUS COMMAND 2 HERE      " AT (0, 2).
//	PRINT "YAW  000.00                     LS DELAY   XXXXX   PREVIOUS COMMAND 3 HERE      " AT (0, 3).
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
	PRINT "ROL             Mode            dV Left                                         " AT (0, 2).
	PRINT "YAW                             LS Delay                                        " AT (0, 3).
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

	PRINT ROUND(SHIP:ORBIT:INCLINATION, 3):TOSTRING:PADLEFT(8) AT (4, 5).
	IF SHIP:ORBIT:SEMIMAJORAXIS > 0 PRINT timeToString(SHIP:ORBIT:PERIOD, 0):PADLEFT(12) AT (4, 6).
	ELSE							PRINT "TTP " + timeToString(ETA:PERIAPSIS, 0):PADLEFT(12) AT (0,6).
	PRINT distanceToString(SHIP:ORBIT:SEMIMAJORAXIS, 4):PADLEFT(11) AT (4, 7).
	PRINT ROUND(SHIP:ORBIT:ECCENTRICITY, 6):TOSTRING:PADLEFT(8) AT (4, 8).

  IF autoSteer = "" PRINT "None" AT (32, 1).
  ELSE PRINT autoSteer AT (32, 1).
	PRINT ROUND(shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"], 0):TOSTRING:PADLEFT(5) AT (43, 2).
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


	IF loopMode = "Resources" OR loopMode = "Resource" {
		PRINT "Name              Quantity         Mass     Prod/Cons Rate" AT (0, 13).
		LOCAL index IS 0.
		FOR eachResource IN SHIP:RESOURCES {
			IF eachResource:DENSITY = 0
				PRINT eachResource:NAME:PADLEFT(15) +
							ROUND(resourceList[eachResource:NAME]["Quantity"], 3):TOSTRING:PADLEFT(11) +
							(ROUND(resourceList[eachResource:NAME]["Mass"], 3) + " kg"):PADLEFT(16) +
							(ROUND(resourceList[eachResource:NAME]["Quantity Use"], 4) + "  u/s"):PADLEFT(21) AT (0, 14 + index).
			ELSE
				PRINT eachResource:NAME:PADLEFT(15) +
							ROUND(resourceList[eachResource:NAME]["Quantity"], 3):TOSTRING:PADLEFT(11) +
							(ROUND(resourceList[eachResource:NAME]["Mass"], 3) + " kg"):PADLEFT(16) +
							(ROUND(resourceList[eachResource:NAME]["Mass Use"], 4) + " kg/s"):PADLEFT(21) AT (0, 14 + index).
			SET index TO index + 1.
		}
	} ELSE IF loopMode = "Orbit" OR loopMode = "targetorbit" {
		LOCAL localOrbit IS SHIP:ORBIT.
		IF loopMode = "targetorbit" AND HASTARGET SET localOrbit TO TARGET:ORBIT.
		PRINT "Name " + localOrbit:NAME + "     " AT (0, 13).
		PRINT "Apoapsis " + distanceToString(localOrbit:APOAPSIS, 4) + "     " AT (0, 14).
		PRINT "Periapsis " + distanceToString(localOrbit:PERIAPSIS, 4) + "     " AT (0, 15).
		PRINT "Orbited Body " + localOrbit:BODY:NAME + "     " AT (0, 16).
		PRINT "Orbited Body MU " + BODY:MU + " m^3/s^2     " AT (0, 17).
		PRINT "Orbited Body Radius " + distanceToString(BODY:Radius, 4) + "     " AT (0, 18).
		PRINT "Period " + timeToString(localOrbit:PERIOD, 4) + "     " AT (0, 19).
		PRINT "Period " + localOrbit:PERIOD + " s     " AT (0, 20).
		PRINT "Inclination " + ROUND(localOrbit:INCLINATION, 4) + " deg     " AT (0, 21).
		PRINT "Eccentricity " + ROUND(localOrbit:ECCENTRICITY, 4) + "     " AT (0, 22).
		PRINT "Semi-Major Axis " + distanceToString(localOrbit:SEMIMAJORAXIS, 4) + "     " AT (0, 23).
		PRINT "Semi-Minor Axis " + distanceToString(localOrbit:SEMIMINORAXIS, 4) + "     " AT (0, 24).
		PRINT "Longitude of Ascending Node " + ROUND(localOrbit:LAN, 4) + " deg     " AT (0, 25).
		PRINT "Argument of Periapsis " + ROUND(localOrbit:ARGUMENTOFPERIAPSIS, 4) + " deg     " AT (0, 26).
		PRINT "True Anomaly  " + ROUND(localOrbit:TRUEANOMALY, 4) + " deg     " AT (0, 27).
		PRINT "Mean Anomaly at Epoch " + ROUND(localOrbit:MEANANOMALYATEPOCH, 4) + " deg     " AT (0, 28).
		PRINT "Epoch " + localOrbit:EPOCH + "     " AT (0, 29).
		PRINT "Transition " + localOrbit:TRANSITION + "     " AT (0, 30).
		PRINT "Position (r) " + distanceToString(SHIP:BODY:POSITION:MAG, 4) + "     " AT (0, 31).
		PRINT "Velocity " + distanceToString(localOrbit:VELOCITY:ORBIT:MAG, 4) + "/s     " AT (0, 32).
		PRINT "Has Next Patch " + localOrbit:HASNEXTPATCH + "     " AT (0, 33).
		IF localOrbit:HASNEXTPATCH {
		  PRINT "Next Patch ETA " + timeToString(localOrbit:NEXTPATCHETA) + "     " AT (0, 34).
		}
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
    PRINT "Processor count           " + processorList:LENGTH:TOSTRING:PADLEFT(10) AT (0, 13).
    PRINT "Volume Name               " + names AT (0, 14).
    PRINT "Volume Capacity           " + capacities + " bytes" AT (0, 15).
    PRINT "Volume Free Space         " + freeSpaces + " bytes" AT (0, 16).
    PRINT "Volume File Count         " + fileCounts AT (0, 17).
    PRINT "Volume Power Requirement  " + powerReqs + " E/s" AT (0, 18).
    PRINT "Core Boot File            " + bootFiles AT (0, 19).
  }

	SET timeDelta TO MISSIONTIME - oldTime.
	IF timeDelta > 0 {
		SET pointing["pitch"] TO pitch_for(SHIP).
		SET pointing["roll"] TO roll_for(SHIP).
		SET pointing["yaw"] TO yaw_for(SHIP).
		FOR resource IN SHIP:RESOURCES {
			SET resourceList[resource:NAME]["Quantity Use"] TO (resource:AMOUNT - resourceList[resource:NAME]["Quantity"]) / timeDelta.
			SET resourceList[resource:NAME]["Mass Use"] TO (resource:AMOUNT * resource:DENSITY * 1000 - resourceList[resource:NAME]["Mass"]) / timeDelta.
			SET resourceList[resource:NAME]["Quantity"] TO resource:AMOUNT.
			SET resourceList[resource:NAME]["Mass"] TO resource:AMOUNT * resource:DENSITY * 1000.
		}
		SET oldTime TO MISSIONTIME.
	}
  updateFacingVectors().
	RETURN TRUE.
}
