@LAZYGLOBAL OFF.

// ============================================================================
// porkchopplot.ks - writes a porkchop plot CSV (one per Lambert solver) for transfers to a
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
//                      40 between bodies, 24 per ship orbit in the same SOI
//   tofSamples       - flight times sampled (1 to 4 times the Hohmann time). -1 (the default) chooses:
//                      41 between bodies, 31 in the same SOI
//   sourceName       - "" (the default) takes the source from where the ship is. Otherwise the source
//                      to use instead: it must orbit the same body as the destination
//   parkingAltitude  - accepted so the parameters match transferCalc.ks; not used (no parking orbit is priced)
//   captureAltitude  - m above the destination's surface to capture into a circular orbit, for a
//                      destination body in the same SOI. -1 (the default) prices matching the arrival
//                      excess speed. Between bodies the arrival is always the bare relative speed.
// ============================================================================

PARAMETER destinationName IS "Comm Sat - Active Ship".
PARAMETER startOffset IS 120.
PARAMETER departureWindows IS 1.
PARAMETER samplesPerWindow IS -1.
PARAMETER tofSamples IS -1.
PARAMETER sourceName IS "".
PARAMETER parkingAltitude IS -1.
PARAMETER captureAltitude IS -1.

// Wall-clock stopwatch (KUNIVERSE:REALWORLDTIME is real-world UNIX time, so it ignores time warp).
LOCAL scriptStartRealTime IS KUNIVERSE:REALWORLDTIME.

LOCAL endpoints IS resolveTransferEndpoints(destinationName, sourceName).
LOCAL errorCode IS endpoints["error"].
LOCAL fromOrbitable IS endpoints["from"].
LOCAL toOrbitable IS endpoints["to"].
LOCAL sameSOI IS endpoints["sameSOI"].

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

	// Run the exact same search once per solver, so their results can be
	// compared directly - same geometry, same grid, same warm-starting; the
	// only thing that differs between the two passes is which Lambert solver
	// the cost function dispatches to. Each pass gets its own CSV (named after the
	// solver) so neither run overwrites the other's output.
	LOCAL solverTypesToTest IS LIST("Gauss", "Gooding").
	LOCAL minDeltaV IS LEXICON("value", invalidDeltaV, "departureTime", startTime, "timeOfFlight", 0).
	LOCAL solverRealTimes IS LEXICON().

	FOR solverType IN solverTypesToTest {
		PRINT "".
		PRINT "=== Solver: " + solverType + " ===".

		LOCAL logFileName IS "0:porkchopPlot " + solverType + ".csv".

		LOCAL dvDelegate IS 0.
		IF sameSOI {
			SET dvDelegate TO bindSameSOIDeltaV(fromOrbitable, toOrbitable, solverType, captureRadius, startTime).
		} ELSE {
			SET dvDelegate TO bindPorkchopDeltaV(fromOrbitable, toOrbitable, window["sunBody"], solverType).
		}
		LOCAL grid IS porkchopGrid(dvDelegate, window, solverType).
		SET minDeltaV TO grid["minDeltaV"].
		SET solverRealTimes[solverType] TO grid["realDuration"].

		writePorkchopCsv(grid, window, logFileName, solverType, fromOrbitable, toOrbitable).

		PRINT "[" + solverType + "] " + grid["totalCells"] + " cells in " + realTimeToString(grid["realDuration"]) + ".".
		PRINT "[" + solverType + "] " + motionTypeSummary(grid, TRUE).
		PRINT "[" + solverType + "] Min dV " + distanceToString(minDeltaV["value"]) + "/s.".
		PRINT "  Depart +" + timeToString(minDeltaV["departureTime"] - startTime) + ", TOF " + timeToString(minDeltaV["timeOfFlight"]) + ".".
		PRINT "  Saved: porkchopPlot " + solverType + ".csv".
	} // closes "FOR solverType IN solverTypesToTest" - the per-solver comparison loop

	PRINT "".
	PRINT "Complete".
	// Where the wall-clock time went.
	LOCAL timeSummary IS "Run time:".
	FOR solverName IN solverRealTimes:KEYS {
		SET timeSummary TO timeSummary + " " + solverName + " " + realTimeToString(solverRealTimes[solverName]) + ",".
	}
	PRINT timeSummary + " total " + realTimeToString(KUNIVERSE:REALWORLDTIME - scriptStartRealTime) + ".".
	WAIT 5.
	SET loopMessage TO "Min dV: " + distanceToString(minDeltaV["value"]) + "/s at " + durationToUnitString(minDeltaV["departureTime"] - startTime).
} ELSE SET loopMessage TO "Error: " + errorCode.
