@LAZYGLOBAL OFF.

// ============================================================================
// porkchopplot.ks - writes a porkchop plot CSV (0:porkchopPlot.csv) for transfers to a
// destination: a fine search over one or more departure windows. Takes the same parameters, in
// the same order, as transferCalc.ks, which picks the cheapest transfer in the same window and
// makes the node. The plot prices the bare transfer: between bodies, a point-mass departure
// and arrival (no parking orbit); in the same SOI, the real burn from the ship's orbit.
//
// Only the destination is needed: resolveTransferEndpoints works out the source from where the
// ship is (see transferCalc.ks). A destination in the ship's own SOI is a same-SOI transfer from
// the ship; one that orbits the ship's body's parent is a transfer from the ship's body.
//
// PARAMETERs:
//   destinationName  - the destination: a body, or a vessel (a vessel wins a name clash)
//   startOffset      - s from now to the start of the plotted window (>= 30)
//   departureWindows - how many departure windows to plot (a synodic period each between bodies;
//                      in the same SOI a synodic period or four ship orbits, whichever is shorter)
//   samplesPerWindow - departure times sampled in each window. -1 (the default) chooses:
//                      between bodies 24 per period of the quicker body in the window (40 to 120), 24 per ship orbit in the same SOI
//   tofSamples       - flight times sampled (1 to 4 times the Hohmann time). -1 (the default) chooses:
//                      41 between bodies, 31 in the same SOI
//   sourceName       - "" (the default) takes the source from where the ship is. Otherwise the source
//                      to use instead: it must orbit the same body as the destination
//   parkingAltitude  - accepted so the parameters match transferCalc.ks; not used (no parking orbit is priced)
//   captureAltitude  - m above the destination's surface to capture into a circular orbit, for a
//                      destination body in the same SOI. -1 (the default) prices matching the arrival
//                      excess speed. Between bodies the arrival is always the bare relative speed.
//   solverType       - the Lambert solver: "Gooding" (the default) or "Gauss"
// ============================================================================

PARAMETER destinationName IS "Default".
PARAMETER startOffset IS 120.
PARAMETER departureWindows IS 1.
PARAMETER samplesPerWindow IS -1.
PARAMETER tofSamples IS -1.
PARAMETER sourceName IS "".
PARAMETER parkingAltitude IS "Default".
PARAMETER captureAltitude IS "Default".
PARAMETER solverType IS "Gooding".
SET parkingAltitude TO processScalarParameter(parkingAltitude, errorValue).
IF parkingAltitude = errorValue SET parkingAltitude TO -1.
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
IF errorCode = "None" AND solverType <> "Gauss" AND solverType <> "Gooding" {
	SET errorCode TO "solverType must be Gauss or Gooding, not " + solverType + "!".
}

// Inside one SOI the ship (if it is the source) has to be in orbit to have an orbit to burn from.
IF errorCode = "None" AND sameSOI {
	IF fromOrbitable:NAME = SHIP:NAME AND (SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" OR SHIP:STATUS = "SUB_ORBITAL") {
		SET errorCode TO "A transfer to " + toOrbitable:NAME + " inside " + SHIP:BODY:NAME + "'s sphere of influence needs the ship in orbit!".
	}
}

LOCAL window IS 0.
IF errorCode = "None" {
	SET window TO buildTransferWindow(endpoints, startOffset, departureWindows, samplesPerWindow, tofSamples, FALSE).
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

	LOCAL csvSaved IS writePorkchopCsv(grid, window, "0:porkchopPlot.csv", solverType, fromOrbitable, toOrbitable).

	PRINT grid["totalCells"] + " cells in " + realTimeToString(grid["realDuration"]) + ".".
	PRINT motionTypeSummary(grid, TRUE).
	FOR reasonLine IN failureReasonLines(grid) {
		PRINT "Failed - " + reasonLine.
	}
	PRINT "Min dV " + distanceToString(minDeltaV["value"]) + "/s.".
	PRINT "  Depart +" + timeToString(minDeltaV["departureTime"] - startTime) + ", TOF " + timeToString(minDeltaV["timeOfFlight"]) + ".".
	IF csvSaved {
		PRINT "  Saved: porkchopPlot.csv".
	} ELSE {
		PRINT "  Not saved: no archive connection.".
	}

	PRINT "".
	PRINT "Complete".
	PRINT "Run time: " + realTimeToString(KUNIVERSE:REALWORLDTIME - scriptStartRealTime) + ".".
	WAIT 5.
	SET loopMessage TO "Min dV: " + distanceToString(minDeltaV["value"]) + "/s at " + durationToUnitString(minDeltaV["departureTime"] - startTime).} ELSE SET loopMessage TO "Error: " + errorCode.
