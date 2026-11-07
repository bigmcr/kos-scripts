@LAZYGLOBAL OFF.

// ============================================================================
// porkchopplot.ks - writes a porkchop plot CSV (0:porkchopPlot.csv) for transfers to a
// destination: a fine search over one or more departure windows. It is a planning tool, so its
// parameters are not those of transferCalc.ks (which picks the cheapest transfer in a window and makes
// the node). The plot prices the bare transfer: between bodies, a point-mass departure
// and arrival (no parking orbit); in the same SOI, the real burn from the ship's orbit.
//
// With the source left at "Default", only the destination is needed: resolveTransferEndpoints works
// out the source from where the ship is (see transferCalc.ks). A destination in the ship's own SOI is a
// same-SOI transfer from the ship; one that orbits the ship's body's parent is a transfer from the ship's body.
//
// PARAMETERs:
//   destinationName  - the destination: a body, or a vessel (a vessel wins a name clash).
//                      "Default" (the default) uses the current target
//   sourceName       - "Default" (the default) takes the source from where the ship is. Otherwise the
//                      source to use instead: it must orbit the same body as the destination
//   departureWindows - how many departure windows to plot (a synodic period each between bodies;
//                      in the same SOI a synodic period or four ship orbits, whichever is shorter)
//   samplesPerWindow - departure times sampled in each window. -1 (the default) chooses:
//                      between bodies 24 per period of the quicker body in the window (40 to 120), 24 per ship orbit in the same SOI
//   tofSamples       - flight times sampled (1 to 4 times the Hohmann time). -1 (the default) chooses:
//                      41 between bodies, 31 in the same SOI
//   captureAltitude  - m above the destination's surface to capture into a circular orbit, for a
//                      destination body in the same SOI. -1 (the default) prices matching the arrival
//                      excess speed. Between bodies the arrival is always the bare relative speed.
//   searchDays       - game days, the length of the departure range, in place of departureWindows windows.
//                      -1 (the default) uses departureWindows. Needed when a vessel is on an escape orbit
//                      with no SOI change to end the search (see buildTransferWindow)
//   startDays        - game days from now to the start of the plotted window, added to the five minutes
//                      below. 0 (the default) starts five minutes from now. To plot a later window,
//                      or a particular range of dates, start there
// Fixed in the script (LOCALs): the plot starts 300 s (five minutes) from now (plus startDays), and the
// Lambert solver is "Gooding".
//
// The plot is written to the archive as "porkchop <source>-<destination>.csv", so each pair keeps its
// own file. The script stops at once, before the grid is calculated, if there is no archive connection.
// ============================================================================

PARAMETER destinationName IS "Default".
PARAMETER sourceName IS "Default".
PARAMETER departureWindows IS 1.
PARAMETER samplesPerWindow IS -1.
PARAMETER tofSamples IS -1.
PARAMETER captureAltitude IS "Default".
PARAMETER searchDays IS -1.
PARAMETER startDays IS 0.
// A planning tool is not used to burn straight away, so the plot starts five minutes from now, or later by startDays.
LOCAL startOffset IS 300 + MAX(0, startDays) * timeUnitSeconds("Days").
LOCAL solverType IS "Gooding".
IF sourceName = "Default" SET sourceName TO "".
SET captureAltitude TO processScalarParameter(captureAltitude, errorValue).
IF captureAltitude = errorValue SET captureAltitude TO -1.

CLEARSCREEN.

IF destinationName = "Default" {
	IF HASTARGET SET destinationName TO TARGET:NAME.
	ELSE SET destinationName TO "None".
}

// Wall-clock stopwatch (KUNIVERSE:REALWORLDTIME is real-world UNIX time, so it ignores time warp).
LOCAL scriptStartRealTime IS KUNIVERSE:REALWORLDTIME.

LOCAL endpoints IS resolveTransferEndpoints(destinationName, sourceName).
LOCAL errorCode IS endpoints["error"].
LOCAL fromOrbitable IS endpoints["from"].
LOCAL toOrbitable IS endpoints["to"].
LOCAL sameSOI IS endpoints["sameSOI"].
// The plot can only be saved on the archive, so there is no point calculating it without a connection.
IF errorCode = "None" AND NOT connectionToKSC() {
	SET errorCode TO "No archive connection: the plot could not be saved!".
}

// The file for this pair of orbitables, with the characters a file name cannot hold taken out of their names.
LOCAL plotFile IS "".
IF errorCode = "None" {
	LOCAL pairName IS fromOrbitable:NAME + "-" + toOrbitable:NAME.
	FOR badCharacter IN LIST("/", "\", ":", "*", "?", CHAR(34), "<", ">", "|") {
		SET pairName TO pairName:REPLACE(badCharacter, "").
	}
	SET plotFile TO "0:porkchop " + pairName + ".csv".
}

// Inside one SOI the ship (if it is the source) has to be in orbit to have an orbit to burn from.
IF errorCode = "None" AND sameSOI {
	IF fromOrbitable:NAME = SHIP:NAME AND (SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" OR SHIP:STATUS = "SUB_ORBITAL") {
		SET errorCode TO "A transfer to " + toOrbitable:NAME + " inside " + SHIP:BODY:NAME + "'s sphere of influence needs the ship in orbit!".
	}
}

LOCAL window IS 0.
IF errorCode = "None" {
	LOCAL searchSpan IS -1.
	IF searchDays > 0 SET searchSpan TO searchDays * timeUnitSeconds("Days").
	SET window TO buildTransferWindow(endpoints, startOffset, departureWindows, samplesPerWindow, tofSamples, FALSE, searchSpan).
	SET errorCode TO window["error"].
}

IF errorCode = "None" {
	LOCAL startTime IS window["startTime"].
	LOCAL captureRadius IS 0.
	IF captureAltitude >= 0 AND toOrbitable:ISTYPE("Body") SET captureRadius TO toOrbitable:RADIUS + captureAltitude.

	IF sameSOI {
		PRINT fromOrbitable:NAME + " -> " + toOrbitable:NAME + " (same SOI).".
		PRINT "Window " + timeToString(window["windowLength"]) + ", " + window["samplesPerWindow"] + " departures each.".
	} ELSE {
		PRINT fromOrbitable:NAME + " -> " + toOrbitable:NAME + " (around " + window["sunBody"]:NAME + ").".
	}

	PRINT "Solver: " + solverType + ".".

	LOCAL dvDelegate IS 0.
	IF sameSOI {
		SET dvDelegate TO bindSameSOIDeltaV(fromOrbitable, toOrbitable, solverType, captureRadius, startTime).
	} ELSE {
		SET dvDelegate TO bindPorkchopDeltaV(fromOrbitable, toOrbitable, window["sunBody"], solverType).
	}
	LOCAL grid IS porkchopGrid(dvDelegate, window).
	LOCAL minDeltaV IS grid["minDeltaV"].

	LOCAL csvSaved IS writePorkchopCsv(grid, window, plotFile, solverType, fromOrbitable, toOrbitable).

	PRINT grid["totalCells"] + " cells in " + realTimeToString(grid["realDuration"]) + ".".
	PRINT motionTypeSummary(grid, TRUE).
	FOR reasonLine IN failureReasonLines(grid) {
		PRINT "Failed - " + reasonLine.
	}
	PRINT "Min dV " + distanceToString(minDeltaV["value"]) + "/s.".
	PRINT "  Depart +" + timeToString(minDeltaV["departureTime"] - startTime) + ", TOF " + timeToString(minDeltaV["timeOfFlight"]) + ".".
	IF csvSaved {
		PRINT "  Saved: " + plotFile:SUBSTRING(2, plotFile:LENGTH - 2).
	} ELSE {
		PRINT "  Not saved: no archive connection.".
	}

	PRINT "".
	PRINT "Complete".
	PRINT "Run time: " + realTimeToString(KUNIVERSE:REALWORLDTIME - scriptStartRealTime) + ".".
	WAIT 5.
	SET loopMessage TO "Min dV: " + distanceToString(minDeltaV["value"]) + "/s at " + durationToUnitString(minDeltaV["departureTime"] - startTime).
} ELSE {
	SET loopMessage TO "Error: " + errorCode.
}
