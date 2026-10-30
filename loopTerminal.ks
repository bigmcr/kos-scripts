@LAZYGLOBAL OFF.

// loopTerminal - the screen that loop shows on the terminal.
//
// The screen is the "Main" area (the top 13 rows, always shown), and below it the area of one "mode",
// chosen by loopMode. Everything on the screen is described by a list of CELLS. A cell is a LEXICON with
//			"x", "y"      where its label starts. The y is counted from the top of the area it is in.
//			"label"       text printed once, when the screen is laid out.
//			"value"       a delegate that returns the text printed right after the label every update,
//			              or FALSE if the cell only has a label.
//			"width"       the most characters the value may use, or 0 for the rest of the line.
// The value is always padded or cut to its width, so a short value completely replaces a long one.
// Labels and values come from the same cell, so they cannot get out of step with each other.
//
// Each mode is a LEXICON with
//			"name", "labels" (the loopMode values that select it), "build" (a delegate returning its cells),
//			optionally "help" (a short text for the Info mode to show instead of the labels), and
//			optionally "signature" (a delegate returning a string that changes whenever "build" would give
//			different cells - the screen is laid out again when it does) and
//			"update" (a delegate that is called once per update, before the values are printed).
// Only the active mode is built, and only when the layout is needed.

LOCAL oldTime IS TIME:SECONDS.
LOCAL timeDelta IS TIME:SECONDS - oldTime.
LOCAL pointing IS LEXICON("pitch", 0, "roll", 0, "yaw", 0).

// The terminal row where the area of the active mode starts, which is just below the Main area.
LOCAL mainScreenHeight IS 13.

// The latest input from loop, for the cells in the Main area.
LOCAL screenInput IS LEXICON("input", "", "commands", LIST()).

// The orbit that Orbit mode is currently displaying. The "update" delegate of the Orbit mode refreshes it
// once per screen update, and the value delegates of the Orbit cells read it.
LOCAL orbitView IS LEXICON("orbit", SHIP:ORBIT).

LOCAL screenModeList IS LIST().
LOCAL mainCells IS LIST().
LOCAL modeCells IS LIST().
LOCAL oldScreenUpdateTime IS KUNIVERSE:REALWORLDTIME.       // real time, so time warp does not make the screen lay out again every update
LOCAL oldScreenSignature IS "".

// Fit To Width
// Passed the following:
//			text (string), width (scalar, characters)
// Returns the following:
//			text cut or padded with spaces to exactly width characters
FUNCTION fitToWidth {
	PARAMETER text, width.
	IF width <= 0 RETURN "".
	IF text:LENGTH > width RETURN text:SUBSTRING(0, width).
	RETURN text:PADRIGHT(width).
}

// Screen Cell
// Passed the following:
//			xCoord, yCoord (scalars), label (string), valueDelegate (delegate returning the value, or FALSE),
//			width (scalar, the most characters the value may use, or 0 for the rest of the line)
// Returns the following:
//			a cell (LEXICON), as described at the top of the file
FUNCTION screenCell {
	PARAMETER xCoord, yCoord, label, valueDelegate IS FALSE, width IS 0.
	RETURN LEXICON("x", xCoord, "y", yCoord, "label", label, "value", valueDelegate, "width", width).
}

// Add Screen Row
// Adds a cell at the start of the next free row of the list, which is how most modes are laid out.
// Passed the following:
//			cells (list of cells), label (string), valueDelegate (delegate returning the value, or FALSE)
FUNCTION addScreenRow {
	PARAMETER cells, label, valueDelegate IS FALSE.
	cells:ADD(screenCell(0, cells:LENGTH, label, valueDelegate)).
}

// First Word
// Passed the following:
//			title (string), width (scalar)
// Returns the following:
//			the part of title before its first space, padded on the right to width characters
FUNCTION firstWord {
	PARAMETER title.
	PARAMETER width.
	LOCAL spaceIndex IS title:FIND(" ").
	IF spaceIndex <> -1 SET title TO title:SUBSTRING(0, spaceIndex).
	RETURN title:PADRIGHT(width).
}

// Print Screen Labels
// Prints the labels of the cells. Labels that would run off the end of the line are cut.
// Passed the following:
//			cells (list of cells), originRow (scalar, the terminal row where the y of the cells is zero)
FUNCTION printScreenLabels {
	PARAMETER cells, originRow.
	FOR eachCell IN cells {
		LOCAL text IS eachCell["label"].
		LOCAL room IS TERMINAL:WIDTH - eachCell["x"] - 1.
		IF text:LENGTH > room SET text TO text:SUBSTRING(0, MAX(0, room)).
		IF text <> "" PRINT text AT (eachCell["x"], originRow + eachCell["y"]).
	}
}

// Cells To Dynamic Lines
// Passed the following:
//			cells (list of cells), originRow (scalar, the terminal row where the y of the cells is zero)
// Returns the following:
//			the lines to give to printDynamicLines. Each value is placed right after its label.
FUNCTION cellsToDynamicLines {
	PARAMETER cells, originRow.
	LOCAL linesToPrintDynamic IS LIST().
	FOR eachCell IN cells {
		IF NOT eachCell["value"]:ISTYPE("Boolean") {
			LOCAL xCoord IS eachCell["x"] + eachCell["label"]:LENGTH.
			LOCAL room IS TERMINAL:WIDTH - xCoord - 1.
			IF eachCell["width"] > 0 SET room TO MIN(room, eachCell["width"]).
			linesToPrintDynamic:ADD(LEXICON("string", fitToWidth(eachCell["value"]():TOSTRING, room), "xCoord", xCoord, "yCoord", originRow + eachCell["y"])).
		}
	}
	RETURN linesToPrintDynamic.
}

// Reboot Pending Text
// Returns the text for the Main area while a reboot is needed (string): the first two scripts that were updated after
// they were loaded, and how many more there are. Returns "" if no reboot is needed. rebootPending is set in boot.ks.
FUNCTION rebootPendingText {
	IF rebootPending:LENGTH = 0 RETURN "".
	LOCAL pendingText IS "Reboot pending: " + rebootPending[0].
	IF rebootPending:LENGTH > 1 SET pendingText TO pendingText + ", " + rebootPending[1].
	IF rebootPending:LENGTH > 2 SET pendingText TO pendingText + ", and " + (rebootPending:LENGTH - 2) + " more".
	RETURN pendingText.
}

// ---- Main -------------------------------------------------------------------------------------------
// The Main area is 13 rows:
//      Value     KSP Conn        Auto Steer Target Previous Commands
// PIT                                                    (previous commands, newest first)
// ROL             Mode            A Throttle
// YAW             dV Left         LS Delay
//
// INC          deg               Auto Stopping Time
// PER
// LAN          deg
// ECC
//
// Current Input                           Loop Message
// (the input)                             (the message)
// --------------------------------------------------------------------------------
FUNCTION mainScreenCells {
	LOCAL cells IS LIST().
	cells:ADD(screenCell(6, 0, "Value")).
	cells:ADD(screenCell(16, 0, "KSP Conn ", {RETURN connectionToKSC():TOSTRING:PADLEFT(5).}, 5)).
	cells:ADD(screenCell(32, 0, "Auto Steer Target")).
	cells:ADD(screenCell(50, 0, "Previous Commands")).

	cells:ADD(screenCell(0, 1, "PIT ", {RETURN ROUND(pointing["pitch"], 2):TOSTRING:PADLEFT(7).}, 7)).
	cells:ADD(screenCell(16, 1, "Debug    ", {RETURN debug:TOSTRING:PADLEFT(5).}, 5)).

	cells:ADD(screenCell(32, 1, "", {RETURN CHOOSE "None" IF autoSteer = "" ELSE autoSteer.}, 17)).

	cells:ADD(screenCell(0, 2, "ROL ", {RETURN ROUND(pointing["roll"], 2):TOSTRING:PADLEFT(7).}, 7)).
	cells:ADD(screenCell(16, 2, "Mode", {RETURN loopMode:PADLEFT(10).}, 10)).
	cells:ADD(screenCell(32, 2, "A Throttle ", {RETURN globalThrottle:TOSTRING:PADLEFT(5).}, 5)).

	cells:ADD(screenCell(0, 3, "YAW ", {RETURN ROUND(pointing["yaw"], 2):TOSTRING:PADLEFT(7).}, 7)).
	cells:ADD(screenCell(16, 3, "dV Left  ", {
		IF (shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"] <> 0) {
			RETURN ROUND(shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"], 0):TOSTRING:PADLEFT(5).
		}
		RETURN ROUND(shipInfo["Stage 0"]["DeltaVRCS"], 0):TOSTRING:PADLEFT(5).
	}, 5)).
	cells:ADD(screenCell(32, 3, "LS Delay   ", {
		IF connectionToKSC() {
			IF HOMECONNECTION:DELAY < 0.1 RETURN "<0.1s".
			RETURN timeToString(HOMECONNECTION:DELAY, 1):TOSTRING:PADLEFT(5).
		}
		RETURN "  N/A".
	}, 5)).

	cells:ADD(screenCell(0, 5, "INC ", {RETURN ROUND(SHIP:ORBIT:INCLINATION, 3):TOSTRING:PADLEFT(8).}, 8)).
	cells:ADD(screenCell(20, 5, "Auto Stopping Time")).
	cells:ADD(screenCell(20, 6, "", {RETURN timeToString(STEERINGMANAGER:MAXSTOPPINGTIME):PADLEFT(18).}, 18)).
	cells:ADD(screenCell(13, 5, "deg")).
	cells:ADD(screenCell(0, 6, "", {
		IF SHIP:ORBIT:SEMIMAJORAXIS > 0 RETURN "PER " + timeToString(SHIP:ORBIT:PERIOD, 0):PADLEFT(12).
		RETURN "TTP " + timeToString(ETA:PERIAPSIS, 0):PADLEFT(12).
	}, 16)).
	cells:ADD(screenCell(0, 7, "LAN ", {RETURN ROUND(SHIP:ORBIT:LAN, 2):TOSTRING:PADLEFT(8).}, 8)).
	cells:ADD(screenCell(13, 7, "deg")).
	cells:ADD(screenCell(0, 8, "ECC ", {RETURN ROUND(SHIP:ORBIT:ECCENTRICITY, 6):TOSTRING:PADLEFT(8).}, 8)).
	// shows the names of the scripts that have been updated after they were loaded, until the next reboot
	cells:ADD(screenCell(0, 9, "", {RETURN rebootPendingText().}, 79)).

	cells:ADD(screenCell(0, 10, "Current Input")).
	cells:ADD(screenCell(40, 10, "Loop Message")).
	// when the input is longer than its room, show the end of it, where the operator is typing
	cells:ADD(screenCell(0, 11, "", {
		LOCAL typed IS screenInput["input"].
		IF typed:LENGTH > 39 RETURN typed:SUBSTRING(typed:LENGTH - 39, 39).
		RETURN typed.
	}, 39)).
	cells:ADD(screenCell(40, 11, "", {RETURN loopMessage.}, 39)).
	cells:ADD(screenCell(0, 12, "":PADLEFT(TERMINAL:WIDTH - 1):REPLACE(" ", "-"))).

	// the previous commands, newest first
	FOR index IN RANGE(1, 8) {
		LOCAL slot IS index.
		cells:ADD(screenCell(51, slot, "", {
			LOCAL commands IS screenInput["commands"].
			IF commands:LENGTH >= slot RETURN commands[commands:LENGTH - slot].
			RETURN "".
		}, 28)).
	}
	RETURN cells.
}

// ---- Orbit mode -------------------------------------------------------------------------------------
// Orbit Selection
// Chooses the orbit that Orbit mode displays, from the current loopMode.
// Returns the following:
//			a LEXICON with "orbit" (the orbit), and "showName" (TRUE if it is not the ship's own orbit,
//			in which case the display starts with a row naming it)
FUNCTION orbitSelection {
	LOCAL selectedOrbit IS SHIP:ORBIT.
	LOCAL showName IS FALSE.
	LOCAL targetOrbit IS SHIP:ORBIT.
	IF HASTARGET {
		// parts and docking ports do not have an orbit of their own, but the ship they are on does.
		IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") SET targetOrbit TO TARGET:SHIP:ORBIT.
		ELSE SET targetOrbit TO TARGET:ORBIT.
	}
	IF loopMode = "OrbitNext" AND SHIP:ORBIT:HASNEXTPATCH {
		SET selectedOrbit TO SHIP:ORBIT:NEXTPATCH.
		SET showName TO TRUE.
	} ELSE IF loopMode = "OrbitTarget" AND HASTARGET {
		SET selectedOrbit TO targetOrbit.
		SET showName TO TRUE.
	} ELSE IF loopMode = "OrbitTargetNext" AND HASTARGET AND targetOrbit:HASNEXTPATCH {
		SET selectedOrbit TO targetOrbit:NEXTPATCH.
		SET showName TO TRUE.
	} ELSE IF loopMode = "OrbitNode" AND HASNODE {
		SET selectedOrbit TO NEXTNODE:ORBIT.
		SET showName TO TRUE.
	}
	RETURN LEXICON("orbit", selectedOrbit, "showName", showName).
}

// Orbit Cells
// Which rows exist depends on the selected orbit, and orbitSignature changes whenever that does.
FUNCTION orbitCells {
	LOCAL selection IS orbitSelection().
	LOCAL cells IS LIST().
	IF selection["showName"] addScreenRow(cells, "Name ", {RETURN orbitView["orbit"]:NAME.}).
	addScreenRow(cells, "Apoapsis ", {RETURN distanceToString(orbitView["orbit"]:APOAPSIS, 4).}).
	addScreenRow(cells, "Periapsis ", {RETURN distanceToString(orbitView["orbit"]:PERIAPSIS, 4).}).
	IF selection["orbit"]:ECCENTRICITY > 1 {
		addScreenRow(cells, "Period N/A s").
	} ELSE {
		addScreenRow(cells, "Period ", {RETURN timeToString(orbitView["orbit"]:PERIOD, 4).}).
		addScreenRow(cells, "Period ", {RETURN orbitView["orbit"]:PERIOD + " s".}).
	}
	addScreenRow(cells, "Inclination ", {RETURN ROUND(orbitView["orbit"]:INCLINATION, 4) + " deg".}).
	addScreenRow(cells, "Eccentricity ", {RETURN ROUND(orbitView["orbit"]:ECCENTRICITY, 4).}).
	addScreenRow(cells, "Semi-Major Axis ", {RETURN distanceToString(orbitView["orbit"]:SEMIMAJORAXIS, 4).}).
	addScreenRow(cells, "Semi-Minor Axis ", {RETURN distanceToString(orbitView["orbit"]:SEMIMINORAXIS, 4).}).
	addScreenRow(cells, "Longitude of Ascending Node ", {RETURN ROUND(orbitView["orbit"]:LAN, 4) + " deg".}).
	addScreenRow(cells, "Argument of Periapsis ", {RETURN ROUND(orbitView["orbit"]:ARGUMENTOFPERIAPSIS, 4) + " deg".}).
	addScreenRow(cells, "True Anomaly ", {RETURN ROUND(orbitView["orbit"]:TRUEANOMALY, 4) + " deg".}).
	addScreenRow(cells, "Mean Anomaly ", {RETURN ROUND(trueToMeanAnomaly(orbitView["orbit"]:TRUEANOMALY, orbitView["orbit"]:ECCENTRICITY), 4) + " deg".}).
	addScreenRow(cells, "Transition ", {RETURN orbitView["orbit"]:TRANSITION.}).
	addScreenRow(cells, "Flight path angle ", {RETURN ROUND(flightPathAngle(orbitView["orbit"]:TRUEANOMALY, orbitView["orbit"]:ECCENTRICITY), 4) + " deg".}).
	addScreenRow(cells, "Position (r) ", {RETURN distanceToString((orbitView["orbit"]:POSITION - orbitView["orbit"]:BODY:POSITION):MAG, 4).}).
	addScreenRow(cells, "Velocity ", {RETURN distanceToString(orbitView["orbit"]:VELOCITY:ORBIT:MAG, 4) + "/s".}).
	addScreenRow(cells, "Has Next Patch ", {RETURN orbitView["orbit"]:HASNEXTPATCH.}).
	IF selection["orbit"]:HASNEXTPATCH {
		addScreenRow(cells, "Next Patch ETA ", {RETURN timeToString(orbitView["orbit"]:NEXTPATCHETA).}).
	}
	RETURN cells.
}

// Orbit Signature
// Returns a string that changes whenever the cells that orbitCells would create change.
FUNCTION orbitSignature {
	LOCAL selection IS orbitSelection().
	RETURN "" + selection["showName"] + "|" + (selection["orbit"]:ECCENTRICITY > 1) + "|" + selection["orbit"]:HASNEXTPATCH.
}

// ---- Resources mode ---------------------------------------------------------------------------------
FUNCTION resourcesCells {
	LOCAL cells IS LIST().
	cells:ADD(screenCell(0, 0, "Name              Quantity            Mass       Prod/Cons Rate")).
	cells:ADD(screenCell(0, 1, "                    Liters              kg          kg/s or u/s")).
	LOCAL rowNumber IS 2.
	FOR eachResource IN SHIP:RESOURCES {
		LOCAL resourceName IS eachResource:NAME.
		cells:ADD(screenCell(0, rowNumber, resourceName:PADLEFT(15), {
			IF NOT resourceList:HASKEY(resourceName) RETURN "".
			RETURN ROUND(resourceList[resourceName]["Quantity"], 3):TOSTRING:PADLEFT(11) +
			       ROUND(resourceList[resourceName]["Mass"], 3):TOSTRING:PADLEFT(16) +
			       ROUND(resourceList[resourceName]["Quantity Use"], 4):TOSTRING:PADLEFT(21).
		})).
		SET rowNumber TO rowNumber + 1.
	}
	RETURN cells.
}

// ---- Body mode --------------------------------------------------------------------------------------
// Almost everything about a body never changes, so it is part of the label. The layout is built again
// when the ship changes its body (see the signature), and the rotation angle is the only live value.
FUNCTION bodyCells {
	LOCAL cells IS LIST().
	LOCAL orbitedBody IS SHIP:BODY.
	addScreenRow(cells, "Orbited Body " + orbitedBody:NAME).
	addScreenRow(cells, "Mass " + orbitedBody:MASS + " kg").
	addScreenRow(cells, "Has Ocean " + orbitedBody:HASOCEAN).
	addScreenRow(cells, "Has Solid Surface " + orbitedBody:HASSOLIDSURFACE).
	addScreenRow(cells, "Has Children " + (orbitedBody:ORBITINGCHILDREN:LENGTH <> 0)).
	IF orbitedBody:ORBITINGCHILDREN:LENGTH <> 0 {
		LOCAL childNames IS "Children Names: ".
		FOR eachChild IN orbitedBody:ORBITINGCHILDREN {
			SET childNames TO childNames + eachChild:NAME + " ".
		}
		addScreenRow(cells, childNames).
	}
	addScreenRow(cells, "Rotation Period " + timeToString(orbitedBody:ROTATIONPERIOD)).
	addScreenRow(cells, "Rotation Period " + orbitedBody:ROTATIONPERIOD + " s").
	addScreenRow(cells, "Radius " + distanceToString(orbitedBody:RADIUS, 4)).
	addScreenRow(cells, "MU " + orbitedBody:MU + " m^3/s^2").
	addScreenRow(cells, "Atmosphere " + orbitedBody:ATM:EXISTS).
	IF orbitedBody:HASBODY addScreenRow(cells, "SOI Radius " + distanceToString(orbitedBody:SOIRADIUS)).
	ELSE addScreenRow(cells, "SOI Radius infinite").
	addScreenRow(cells, "Rotation Angle ", {RETURN ROUND(SHIP:BODY:ROTATIONANGLE, 4) + " deg".}).
	RETURN cells.
}

// ---- Processors mode --------------------------------------------------------------------------------
// One row for each kOS processor on the ship.
FUNCTION processorsCells {
	LOCAL cells IS LIST().
	LOCAL processorList IS LIST().
	LIST PROCESSORS IN processorList.
	addScreenRow(cells, "Processor count " + processorList:LENGTH + "   (capacity and free space in bytes, power in E/s)").
	addScreenRow(cells, "Volume":PADRIGHT(12) + " " + "Capacity":PADLEFT(8) + " " + "Free":PADLEFT(8) + " " + "Files":PADLEFT(5) + " " + "Power":PADLEFT(6) + " Boot file").
	FOR eachProc IN processorList {
		LOCAL proc IS eachProc.
		addScreenRow(cells, "", {
			// the one that is running this code is marked
			LOCAL thisMarker IS "".
			IF proc:PART:UID = CORE:PART:UID SET thisMarker TO "  <- this one".
			LOCAL volumeName IS "None".
			IF proc:VOLUME:NAME <> "" SET volumeName TO proc:VOLUME:NAME.
			RETURN volumeName:PADRIGHT(12) + " " +
			       proc:VOLUME:CAPACITY:TOSTRING:PADLEFT(8) + " " +
			       proc:VOLUME:FREESPACE:TOSTRING:PADLEFT(8) + " " +
			       proc:VOLUME:FILES:LENGTH:TOSTRING:PADLEFT(5) + " " +
			       ROUND(proc:VOLUME:POWERREQUIREMENT, 2):TOSTRING:PADLEFT(6) + " " +
			       proc:BOOTFILENAME + thisMarker.
		}).
	}
	RETURN cells.
}

FUNCTION processorCountSignature {
	LOCAL processorList IS LIST().
	LIST PROCESSORS IN processorList.
	RETURN "" + processorList:LENGTH.
}

// ---- Ship mode --------------------------------------------------------------------------------------
// Information about the ship itself - part count, dV and similar info.
FUNCTION shipCells {
	LOCAL cells IS LIST().
	addScreenRow(cells, "Part Count":PADRIGHT(19), {RETURN SHIP:PARTS:LENGTH:TOSTRING:PADLEFT(10).}).
	addScreenRow(cells, "DeltaV":PADRIGHT(19), {RETURN (ROUND(SHIP:DELTAV:CURRENT, 2) + " m/s"):PADLEFT(10).}).
	addScreenRow(cells, "DeltaV Custom":PADRIGHT(19), {RETURN (ROUND(shipInfo["CurrentStage"]["DeltaV"], 2) + " m/s"):PADLEFT(10).}).
	addScreenRow(cells, "DeltaV RCS":PADRIGHT(19), {RETURN (ROUND(shipInfo["CurrentStage"]["DeltaVRCS"], 2) + " m/s"):PADLEFT(10).}).
	addScreenRow(cells, "Stage Number":PADRIGHT(19), {RETURN SHIP:STAGENUM:TOSTRING:PADLEFT(10).}).
	addScreenRow(cells, "Current Stage":PADRIGHT(19), {RETURN shipInfo["NumberOfStages"]:TOSTRING:PADLEFT(10).}).
	addScreenRow(cells, "Type":PADRIGHT(19), {RETURN SHIP:TYPE:PADLEFT(10).}).
	addScreenRow(cells, "Crew Capacity":PADRIGHT(19), {RETURN SHIP:CREWCAPACITY:TOSTRING:PADLEFT(10).}).
	addScreenRow(cells, "Current Crew Count":PADRIGHT(19), {RETURN SHIP:CREW:LENGTH:TOSTRING:PADLEFT(10).}).
	addScreenRow(cells, "Resource Count":PADRIGHT(19), {RETURN SHIP:RESOURCES:LENGTH:TOSTRING:PADLEFT(10).}).
	RETURN cells.
}

// ---- ShipInfo mode ----------------------------------------------------------------------------------
// The totals that are kept in shipInfo: for the whole ship, for the engines of the current stage (at the current
// throttle, and at full throttle), and for the current stage itself. The library updates shipInfo when the ship
// stages, but the engine totals depend on the throttle, so this mode refreshes them itself, every two seconds of real time.

LOCAL shipInfoRefreshTime IS 0.

FUNCTION refreshShipInfoTotals {
	IF KUNIVERSE:REALWORLDTIME - shipInfoRefreshTime < 2 RETURN.
	SET shipInfoRefreshTime TO KUNIVERSE:REALWORLDTIME.
	updateShipInfoCurrent(FALSE).
}

// Force Text
// Returns a force given in newtons as kilonewtons (string).
FUNCTION forceText {
	PARAMETER newtons.
	RETURN ROUND(newtons / 1000, 2):TOSTRING + " kN".
}

// Mass Text
// Returns a mass given in kilograms as kilograms, or as tonnes if it is large (string).
FUNCTION massText {
	PARAMETER kilograms.
	IF ABS(kilograms) >= 10000 RETURN ROUND(kilograms / 1000, 2):TOSTRING + " t".
	RETURN ROUND(kilograms, 1):TOSTRING + " kg".
}

// Sum Over Stages
// Passed the following:
//			stageKey (string, a key that each stage of shipInfo has, such as "DryMass")
// Returns the following:
//			the total of that value for all of the stages (scalar)
FUNCTION sumOverStages {
	PARAMETER stageKey.
	LOCAL total IS 0.
	FROM {LOCAL index IS 0.} UNTIL index >= shipInfo["NumberOfStages"] STEP {SET index TO index + 1.} DO {
		SET total TO total + shipInfo["Stage " + index][stageKey].
	}
	RETURN total.
}

// Engine Total
// Passed the following:
//			whichTotal ("Current" for the throttle as it is, or "Maximum" for full throttle)
//			group ("" for all of the engines of the stage, "Variable" for the throttleable ones, or "Constant" for the rest)
//			valueName (string, such as "Thrust", "mDot", "Accel", "TWR" or "burnTime")
// Returns the following:
//			that total from shipInfo (scalar)
FUNCTION engineTotal {
	PARAMETER whichTotal, group, valueName.
	IF group = "" RETURN shipInfo[whichTotal][valueName].
	RETURN shipInfo[whichTotal][group][valueName].
}

// Format Engine Value
// Passed the following:
//			kind (string, "force", "flow", "accel", "time" or "ratio"), value (scalar)
// Returns the following:
//			the value with its unit (string)
FUNCTION formatEngineValue {
	PARAMETER kind, value.
	IF kind = "force" RETURN forceText(value).
	IF kind = "flow" RETURN ROUND(value, 2) + " kg/s".
	IF kind = "accel" RETURN ROUND(value, 2) + " m/s^2".
	IF kind = "time" RETURN timeToString(value, 0).
	RETURN ROUND(value, 2):TOSTRING.
}

// Add Value Pair
// Adds a row with one value at the left and, if a second label and delegate are given, another at the middle.
FUNCTION addValuePair {
	PARAMETER cells, rowNumber, leftLabel, leftDelegate, rightLabel IS "", rightDelegate IS FALSE.
	cells:ADD(screenCell(0, rowNumber, leftLabel:PADRIGHT(24), leftDelegate, 14)).
	IF NOT rightDelegate:ISTYPE("Boolean") cells:ADD(screenCell(40, rowNumber, rightLabel:PADRIGHT(22), rightDelegate, 17)).
}

FUNCTION shipInfoCells {
	LOCAL cells IS LIST().
	LOCAL rowNumber IS 0.

	// the whole ship
	cells:ADD(screenCell(0, rowNumber, "Whole ship")).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Stages", {RETURN shipInfo["NumberOfStages"]:TOSTRING.},
		"Total delta-V", {RETURN ROUND(shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"], 1) + " m/s".}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Mass", {RETURN massText(SHIP:MASS * 1000).},
		"Parts", {RETURN SHIP:PARTS:LENGTH:TOSTRING.}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Dry mass, all stages", {RETURN massText(sumOverStages("DryMass")).},
		"Resource mass, all stages", {RETURN massText(sumOverStages("ResourceMass")).}).
	SET rowNumber TO rowNumber + 2.

	// the engines of the current stage
	cells:ADD(screenCell(0, rowNumber, "Engines of the current stage (" + shipInfo["CurrentStage"]["Engines"]:LENGTH + ")")).
	SET rowNumber TO rowNumber + 1.
	cells:ADD(screenCell(0, rowNumber, "":PADRIGHT(24) + "Current":PADRIGHT(17) + "Maximum")).
	SET rowNumber TO rowNumber + 1.
	LOCAL engineRows IS LIST(
		LIST("Thrust", "", "Thrust", "force"),
		LIST("  throttleable", "Variable", "Thrust", "force"),
		LIST("  not throttleable", "Constant", "Thrust", "force"),
		LIST("Mass flow", "", "mDot", "flow"),
		LIST("Acceleration", "", "Accel", "accel"),
		LIST("Thrust to weight ratio", "", "TWR", "ratio"),
		LIST("  throttleable", "Variable", "TWR", "ratio"),
		LIST("  not throttleable", "Constant", "TWR", "ratio"),
		LIST("Burn time", "", "burnTime", "time")).
	FOR eachRow IN engineRows {
		LOCAL rowDefinition IS eachRow.
		cells:ADD(screenCell(0, rowNumber, rowDefinition[0]:PADRIGHT(24))).
		cells:ADD(screenCell(24, rowNumber, "", {RETURN formatEngineValue(rowDefinition[3], engineTotal("Current", rowDefinition[1], rowDefinition[2])).}, 16)).
		cells:ADD(screenCell(41, rowNumber, "", {RETURN formatEngineValue(rowDefinition[3], engineTotal("Maximum", rowDefinition[1], rowDefinition[2])).}, 17)).
		SET rowNumber TO rowNumber + 1.
	}
	SET rowNumber TO rowNumber + 1.

	// the current stage
	cells:ADD(screenCell(0, rowNumber, "Current stage (" + (shipInfo["NumberOfStages"] - 1) + ")")).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Isp", {RETURN ROUND(shipInfo["CurrentStage"]["Isp"], 1) + " s".},
		"RCS Isp", {RETURN ROUND(shipInfo["CurrentStage"]["IspRCS"], 1) + " s".}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Maximum thrust", {RETURN forceText(shipInfo["CurrentStage"]["Thrust"]).},
		"Maximum mass flow", {RETURN ROUND(shipInfo["CurrentStage"]["mDot"], 2) + " kg/s".}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Fuel mass", {RETURN massText(shipInfo["CurrentStage"]["FuelMass"]).},
		"Unused fuel mass", {RETURN massText(shipInfo["CurrentStage"]["FuelMassUnused"]).}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "RCS fuel mass", {RETURN massText(shipInfo["CurrentStage"]["FuelRCSMass"]).},
		"Unused RCS fuel mass", {RETURN massText(shipInfo["CurrentStage"]["FuelRCSMassUnused"]).}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Resource mass", {RETURN massText(shipInfo["CurrentStage"]["ResourceMass"]).},
		"Dry mass", {RETURN massText(shipInfo["CurrentStage"]["DryMass"]).}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Mass below this stage", {RETURN massText(shipInfo["CurrentStage"]["PreviousMass"]).},
		"Mass with this stage", {RETURN massText(shipInfo["CurrentStage"]["CurrentMass"]).}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Delta-V", {RETURN ROUND(shipInfo["CurrentStage"]["DeltaV"], 1) + " m/s".},
		"RCS delta-V", {RETURN ROUND(shipInfo["CurrentStage"]["DeltaVRCS"], 1) + " m/s".}).
	SET rowNumber TO rowNumber + 1.
	addValuePair(cells, rowNumber, "Delta-V below this stage", {RETURN ROUND(shipInfo["CurrentStage"]["DeltaVPrev"], 1) + " m/s".},
		"Parts, engines, RCS", {RETURN shipInfo["CurrentStage"]["Parts"]:LENGTH + ", " + shipInfo["CurrentStage"]["Engines"]:LENGTH + ", " + shipInfo["CurrentStage"]["RCS"]:LENGTH.}).
	RETURN cells.
}
// ---- RCS and Engines modes --------------------------------------------------------------------------
// These list the parts of the current stage, which are replaced when the ship stages.
// Returns a string that changes when the current stage, or the parts in it, change.
FUNCTION stageSignature {
	RETURN "" + SHIP:STAGENUM + "|" + shipInfo["NumberOfStages"] + "|" + shipInfo["CurrentStage"]["Engines"]:LENGTH + "|" + shipInfo["CurrentStage"]["RCS"]:LENGTH.
}

FUNCTION rcsCells {
	LOCAL cells IS LIST().
	cells:ADD(screenCell(0, 0, "Thruster       Enabled    Yaw  Pitch   Roll   Fore   Stbd    Top    ISP  ")).
	LOCAL rowNumber IS 1.
	FOR eachRCS IN shipInfo["CurrentStage"]["RCS"] {
		LOCAL thruster IS eachRCS.
		cells:ADD(screenCell(0, rowNumber, firstWord(thruster:TITLE, 16), {
			RETURN thruster:ENABLED:TOSTRING:PADLEFT(6) +
			       thruster:YAWENABLED:TOSTRING:PADLEFT(7) +
			       thruster:PITCHENABLED:TOSTRING:PADLEFT(7) +
			       thruster:ROLLENABLED:TOSTRING:PADLEFT(7) +
			       thruster:FOREENABLED:TOSTRING:PADLEFT(7) +
			       thruster:STARBOARDENABLED:TOSTRING:PADLEFT(7) +
			       thruster:TOPENABLED:TOSTRING:PADLEFT(7) +
			       ROUND(thruster:ISP, 0):TOSTRING:PADLEFT(7).
		})).
		SET rowNumber TO rowNumber + 1.
	}
	cells:ADD(screenCell(0, rowNumber, "Total dV from RCS in current stage: ", {RETURN ROUND(shipInfo["CurrentStage"]["deltaVRCS"], 2) + " m/s".})).
	RETURN cells.
}

// The thrust is shown in kN (it used to be newtons), because six figures of newtons did not fit its column.
FUNCTION enginesCells {
	LOCAL cells IS LIST().
	cells:ADD(screenCell(0, 0, "Engine       Thrust  ISP  M Dot    Ign    Gimbal   Min Throttle Stab")).
	cells:ADD(screenCell(0, 1, "Name             kN    s   kg/s              Deg              %")).
	LOCAL rowNumber IS 2.
	FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
		LOCAL engine IS eachEngine.
		cells:ADD(screenCell(0, rowNumber, firstWord(engine:TITLE, 13), {
			LOCAL ignitions IS "    inf".
			IF engine:IGNITIONS <> -1 SET ignitions TO engine:IGNITIONS:TOSTRING:PADLEFT(7).
			LOCAL gimbalRange IS "0".
			IF engine:HASGIMBAL SET gimbalRange TO ROUND(engine:GIMBAL:RANGE, 1):TOSTRING.
			RETURN ROUND(engine:MAXTHRUST, 1):TOSTRING:PADLEFT(6) +
			       ROUND(engine:ISP):TOSTRING:PADLEFT(5) +
			       ROUND(engine:MAXMASSFLOW * 1000):TOSTRING:PADLEFT(7) +
			       ignitions +
			       gimbalRange:PADLEFT(10) +
			       ROUND(engine:MINTHROTTLE * 100, 1):TOSTRING:PADLEFT(15) +
			       ROUND(engine:FUELSTABILITY * 100):TOSTRING:PADLEFT(5).
		})).
		SET rowNumber TO rowNumber + 1.
	}
	RETURN cells.
}

// ---- Scripts mode -----------------------------------------------------------------------------------
// One row for each script that is in the archive's build, in the manifest, or on the local drive, with whether the
// local copy is up to date, and some information about the files. The scripts that need attention come first. There
// is only room for some of them on the screen, so a page number can be added to the mode: "Scripts 2".

// Scripts Page
// Returns the page number at the end of loopMode, such as 2 for "Scripts 2", or 1 if there is none (scalar).
FUNCTION scriptsPage {
	LOCAL pieces IS loopMode:SPLIT(" ").
	RETURN MAX(1, ROUND(pieces[pieces:LENGTH - 1]:TONUMBER(1))).
}

// Scripts Labels
// Returns the loopMode values that show this mode (list): each name, alone and with a page number from 1 to 9.
FUNCTION scriptsLabels {
	LOCAL modeNames IS LIST().
	FOR eachBase IN LIST("Scripts", "Script", "Files", "Library") {
		modeNames:ADD(eachBase).
		FROM {LOCAL pageNumber IS 1.} UNTIL pageNumber > 9 STEP {SET pageNumber TO pageNumber + 1.} DO {
			modeNames:ADD(eachBase + " " + pageNumber).
		}
	}
	RETURN modeNames.
}

// Script Line
// Makes one line of the table, so that the heading and the rows have their columns in the same places.
// Passed the following:
//			marker (string, one character), scriptName, statusText, form, localSize, archiveSize, loadedText (strings)
// Returns the following:
//			the line (string)
FUNCTION scriptLine {
	PARAMETER marker, scriptName, statusText, form, localSize, archiveSize, loadedText.
	LOCAL shownName IS scriptName.
	IF shownName:LENGTH > 23 SET shownName TO shownName:SUBSTRING(0, 23).
	RETURN marker + shownName:PADRIGHT(23) + " " + statusText:PADRIGHT(10) + " " + form:PADRIGHT(5) + " " +
	       localSize:PADLEFT(7) + " " + archiveSize:PADLEFT(8) + " " + loadedText.
}

FUNCTION scriptsCells {
	LOCAL cells IS LIST().
	LOCAL state IS compareWithArchive().
	LOCAL manifest IS readManifest().
	LOCAL buildFiles IS LEXICON().
	IF state["hasBuild"] SET buildFiles TO state["build"]["files"].
	LOCAL manifestFiles IS LEXICON().
	IF manifest:ISTYPE("Lexicon") SET manifestFiles TO manifest["files"].
	// scripts that were compiled by another version of kOS than the one that is running are replaced by an update
	LOCAL kosChanged IS FALSE.
	IF state["hasBuild"] AND manifest:ISTYPE("Lexicon") SET kosChanged TO manifest["kos"] <> state["build"]["kos"].

	// every script that is in the build, in the manifest, or on the local drive
	LOCAL names IS LIST().
	FOR eachName IN buildFiles:KEYS {
		names:ADD(eachName).
	}
	FOR eachName IN manifestFiles:KEYS {
		IF NOT names:CONTAINS(eachName) names:ADD(eachName).
	}
	FOR eachFile IN CORE:VOLUME:FILES:KEYS {
		IF eachFile:ENDSWITH(".ks") OR eachFile:ENDSWITH(".ksm") {
			IF NOT names:CONTAINS(baseName(eachFile)) names:ADD(baseName(eachFile)).
		}
	}

	// how each one compares to the build
	LOCAL groups IS LIST("CHANGED", "NEW", "REMOVED", "local only", "installed", "current").
	LOCAL counts IS LEXICON().
	FOR eachGroup IN groups {
		SET counts[eachGroup] TO 0.
	}
	LOCAL statusOf IS LEXICON().
	FOR eachName IN names {
		LOCAL statusText IS "local only".
		IF NOT state["hasBuild"] {
			// without the build (not connected, or it has not been made) there is nothing to compare to
			IF manifestFiles:HASKEY(eachName) SET statusText TO "installed".
		} ELSE IF buildFiles:HASKEY(eachName) {
			IF NOT manifestFiles:HASKEY(eachName) {
				SET statusText TO "NEW".
			} ELSE IF manifestFiles[eachName] <> buildFiles[eachName]["fingerprint"] {
				SET statusText TO "CHANGED".
			} ELSE IF kosChanged AND buildFiles[eachName]["form"] = "ksm" {
				SET statusText TO "CHANGED".
			} ELSE SET statusText TO "current".
		} ELSE IF manifestFiles:HASKEY(eachName) {
			SET statusText TO "REMOVED".
		}
		SET statusOf[eachName] TO statusText.
		SET counts[statusText] TO counts[statusText] + 1.
	}
	// the ones that need attention first, and otherwise in the order that they are on the archive
	LOCAL ordered IS LIST().
	FOR eachGroup IN groups {
		FOR eachName IN names {
			IF statusOf[eachName] = eachGroup ordered:ADD(eachName).
		}
	}

	// the part of the list that is on this page
	LOCAL rowsPerPage IS MAX(1, TERMINAL:HEIGHT - mainScreenHeight - 5).
	LOCAL pageCount IS MAX(1, CEILING(ordered:LENGTH / rowsPerPage)).
	LOCAL page IS MIN(scriptsPage(), pageCount).
	LOCAL firstIndex IS (page - 1) * rowsPerPage.

	LOCAL archiveText IS "not connected".
	IF state["connected"] SET archiveText TO "connected".
	LOCAL buildText IS "unknown".
	IF state["connected"] {
		IF NOT state["hasBuild"] SET buildText TO "none".
		ELSE IF state["buildStale"] = "" SET buildText TO "current".
		ELSE SET buildText TO state["buildStale"].
	}
	cells:ADD(screenCell(0, 0, "Archive: " + archiveText + "   Build: " + buildText + "   kOS " + kosVersionText)).
	cells:ADD(screenCell(0, 1, "Scripts: " + ordered:LENGTH + "   changed " + counts["CHANGED"] + "   new " + counts["NEW"] +
	                           "   removed " + counts["REMOVED"] + "   reboot pending " + rebootPending:LENGTH)).
	cells:ADD(screenCell(0, 2, "Local drive: ", {RETURN CORE:VOLUME:FREESPACE + " of " + CORE:VOLUME:CAPACITY + " bytes free".}, 31)).
	cells:ADD(screenCell(46, 2, "Page " + page + " of " + pageCount + "  (mode,Scripts 2)")).
	cells:ADD(screenCell(0, 3, scriptLine(" ", "Name", "Status", "Form", "Local", "Archive", "Loaded"))).

	LOCAL rowNumber IS 4.
	LOCAL lastIndex IS MIN(firstIndex + rowsPerPage, ordered:LENGTH).
	FROM {LOCAL index IS firstIndex.} UNTIL index >= lastIndex STEP {SET index TO index + 1.} DO {
		LOCAL eachName IS ordered[index].
		LOCAL localFiles IS installedFiles(eachName).
		LOCAL localSize IS "-".
		LOCAL form IS "-".
		IF localFiles:LENGTH > 0 {
			LOCAL totalSize IS 0.
			FOR eachFile IN localFiles {
				SET totalSize TO totalSize + OPEN(eachFile):SIZE.
			}
			SET localSize TO totalSize:TOSTRING.
			SET form TO localFiles[0]:SUBSTRING(localFiles[0]:FINDLAST("."), localFiles[0]:LENGTH - localFiles[0]:FINDLAST(".")).
			IF form = ".settings" SET form TO "set".
			// a plus means that there is a .ks and a .ksm, and the .ksm is the one that runs
			IF localFiles:LENGTH > 1 SET form TO form + "+".
		}
		LOCAL archiveSize IS "-".
		IF buildFiles:HASKEY(eachName) SET archiveSize TO buildFiles[eachName]["size"]:TOSTRING.
		LOCAL loadedText IS "".
		IF rebootPending:CONTAINS(eachName) SET loadedText TO "REBOOT".
		ELSE IF loadedVersions:HASKEY(eachName) SET loadedText TO "loaded".
		LOCAL marker IS " ".
		IF isCriticalFile(eachName) SET marker TO "*".
		cells:ADD(screenCell(0, rowNumber, scriptLine(marker, eachName, statusOf[eachName], form, localSize, archiveSize, loadedText))).
		SET rowNumber TO rowNumber + 1.
	}
	cells:ADD(screenCell(0, rowNumber, "* critical file    loaded = in memory    REBOOT = updated since it was loaded")).
	RETURN cells.
}

// Scripts Signature
// Returns a string that changes when something that this mode shows changes, other than the free space.
FUNCTION scriptsSignature {
	LOCAL manifest IS readManifest().
	LOCAL manifestCount IS 0.
	IF manifest:ISTYPE("Lexicon") SET manifestCount TO manifest["files"]:LENGTH.
	RETURN loopMode + "|" + rebootPending:LENGTH + "|" + loadedVersions:LENGTH + "|" + manifestCount + "|" + connectionToKSC().
}
// ---- Universe and Info modes ------------------------------------------------------------------------
// Information about the universe and rocket part types that kOS has loaded.
FUNCTION universeCells {
	LOCAL cells IS LIST().
	addScreenRow(cells, "Stock Rockets: " + isStockRockets()).
	addScreenRow(cells, "Stock World: " + isStockWorld()).
	RETURN cells.
}

// What modes are available.
FUNCTION infoCells {
	LOCAL cells IS LIST().
	addScreenRow(cells, "The following are all valid options for LoopMode").
	addScreenRow(cells, "Anything else will be treated the same as Default:").
	FOR eachMode IN screenModeList {
		LOCAL modeLine IS "   ".
		IF eachMode:HASKEY("help") {
			SET modeLine TO modeLine + " " + eachMode["help"].
		} ELSE {
			FOR eachLabel IN eachMode["labels"] {
				SET modeLine TO modeLine + " " + eachLabel.
			}
		}
		addScreenRow(cells, modeLine).
	}
	RETURN cells.
}

// ---- The modes --------------------------------------------------------------------------------------
FUNCTION registerScreenModes {
	SET screenModeList TO LIST().
	screenModeList:ADD(LEXICON("name", "Orbit",
		"labels", LIST("Orbit", "OrbitNext", "OrbitTarget", "OrbitTargetNext", "OrbitNode"),
		"build", {RETURN orbitCells().},
		"signature", {RETURN orbitSignature().},
		"update", {SET orbitView["orbit"] TO orbitSelection()["orbit"].})).
	screenModeList:ADD(LEXICON("name", "Resources",
		"labels", LIST("Resources", "Resource"),
		"build", {RETURN resourcesCells().},
		"signature", {RETURN "" + SHIP:RESOURCES:LENGTH.})).
	screenModeList:ADD(LEXICON("name", "Body",
		"labels", LIST("Body"),
		"build", {RETURN bodyCells().},
		"signature", {RETURN SHIP:BODY:NAME.})).
	screenModeList:ADD(LEXICON("name", "Processors",
		"labels", LIST("Processor", "Processors", "kOS", "CPU"),
		"build", {RETURN processorsCells().},
		"signature", {RETURN processorCountSignature().})).
	screenModeList:ADD(LEXICON("name", "Ship",
		"labels", LIST("Ship", "deltaV", "dV"),
		"build", {RETURN shipCells().})).
	screenModeList:ADD(LEXICON("name", "ShipInfo",
		"labels", LIST("ShipInfo", "Stage", "Thrust", "TWR"),
		"build", {RETURN shipInfoCells().},
		"signature", {RETURN stageSignature().},
		"update", {refreshShipInfoTotals().})).
	screenModeList:ADD(LEXICON("name", "RCS",
		"labels", LIST("RCS", "Thrusters", "Thruster"),
		"build", {RETURN rcsCells().},
		"signature", {RETURN stageSignature().})).
	screenModeList:ADD(LEXICON("name", "Engines",
		"labels", LIST("Engines", "Engine"),
		"build", {RETURN enginesCells().},
		"signature", {RETURN stageSignature().})).
	screenModeList:ADD(LEXICON("name", "Scripts",
		"labels", scriptsLabels(),
		"help", "Scripts Script Files Library (add a page number: Scripts 2)",
		"build", {RETURN scriptsCells().},
		"signature", {RETURN scriptsSignature().})).
	screenModeList:ADD(LEXICON("name", "Universe",
		"labels", LIST("Universe", "World", "settings"),
		"build", {RETURN universeCells().})).
	screenModeList:ADD(LEXICON("name", "Info",
		"labels", LIST("info", "help"),
		"build", {RETURN infoCells().})).
}

// Active Screen Mode
// Returns the mode (LEXICON) that loopMode selects, or FALSE if it selects none of them.
FUNCTION activeScreenMode {
	FOR eachMode IN screenModeList {
		FOR eachLabel IN eachMode["labels"] {
			IF loopMode = eachLabel RETURN eachMode.
		}
	}
	RETURN FALSE.
}

FUNCTION modeSignature {
	PARAMETER mode.
	IF mode:ISTYPE("Boolean") RETURN "".
	IF mode:HASKEY("signature") RETURN mode["signature"]().
	RETURN "".
}

// Lay Out Screen
// Builds the cells of the Main area and of the given mode, clears the terminal, and prints all the labels.
FUNCTION layoutScreen {
	PARAMETER mode.
	SET mainCells TO mainScreenCells().
	IF mode:ISTYPE("Boolean") SET modeCells TO LIST().
	ELSE SET modeCells TO mode["build"]().
	CLEARSCREEN.
	printScreenLabels(mainCells, 0).
	printScreenLabels(modeCells, mainScreenHeight).
}

FUNCTION updateScreenDynamic {
	PARAMETER inputString, previousCommands, mode.
	SET timeDelta TO TIME:SECONDS - oldTime.
	IF timeDelta > 0 {
		SET pointing["pitch"] TO pitch_for(SHIP).
		SET pointing["roll"] TO roll_for(SHIP).
		SET pointing["yaw"] TO yaw_for(SHIP).
		FOR resource IN SHIP:RESOURCES {
			// a resource that was not on the ship when the library loaded (after docking, for example) has no entry in resourceList yet
			IF NOT resourceList:HASKEY(resource:NAME) {
				resourceList:ADD(resource:NAME, LEXICON("Quantity", resource:AMOUNT,
				                                        "Mass", resource:AMOUNT * resourceDensity(resource:NAME),
				                                        "Density", resourceDensity(resource:NAME),
				                                        "Quantity Use", 0,
				                                        "Mass Use", 0)).
			}
			SET resourceList[resource:NAME]["Quantity Use"] TO (resource:AMOUNT - resourceList[resource:NAME]["Quantity"]) / timeDelta.
			SET resourceList[resource:NAME]["Mass Use"] TO (resource:AMOUNT * resourceDensity(resource:NAME) - resourceList[resource:NAME]["Mass"]) / timeDelta.
			SET resourceList[resource:NAME]["Quantity"] TO resource:AMOUNT.
			SET resourceList[resource:NAME]["Mass"] TO resource:AMOUNT * resourceDensity(resource:NAME).
		}
		SET oldTime TO TIME:SECONDS.
	}
	SET screenInput["input"] TO inputString.
	SET screenInput["commands"] TO previousCommands.
	IF NOT mode:ISTYPE("Boolean") {
		IF mode:HASKEY("update") mode["update"]().
	}
	printDynamicLines(cellsToDynamicLines(mainCells, 0)).
	printDynamicLines(cellsToDynamicLines(modeCells, mainScreenHeight)).
	updateFacingVectors().
}

// Update Screen
// Called by loop about ten times a second. The screen is laid out again when loopMode or the mode's signature
// changes, when the caller forces it, and at least once a minute. Otherwise only the values are printed.
FUNCTION updateScreen {
	PARAMETER inputString, previousCommands, forceUpdate IS FALSE.
	IF screenModeList:LENGTH = 0 registerScreenModes().
	LOCAL mode IS activeScreenMode().
	LOCAL signature IS loopMode + "|" + modeSignature(mode).
	IF forceUpdate OR (signature <> oldScreenSignature) OR (KUNIVERSE:REALWORLDTIME - oldScreenUpdateTime > 60) {
		SET oldScreenUpdateTime TO KUNIVERSE:REALWORLDTIME.
		layoutScreen(mode).
		SET oldScreenSignature TO signature.
	}
	updateScreenDynamic(inputString, previousCommands, mode).
}