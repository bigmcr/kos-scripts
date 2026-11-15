@LAZYGLOBAL OFF.

// ============================================================================
// transferCalc.ks - finds the cheapest transfer to a destination (a body or a vessel) and, for a ship in
// orbit, makes the maneuver node for it. Built on libraryTransfer.ks. porkchopplot.ks plots the same window.
//
// The source is worked out from where the ship is (resolveTransferEndpoints):
//   - a destination that orbits the ship's body: a SAME-SOI transfer from the ship (case 3)
//   - a destination that orbits that body's parent: a transfer from the ship's body (cases 1, 2 and 4)
//   - a VESSEL at a moon of the ship's body or of its parent: to that moon, capturing at the vessel's orbit size
//   - a MOON of another planet: to that planet, capturing at the moon's orbit size
//   - anything else is an error
//
//   Case 1 (on the ground): a circular parking orbit is designed for the winning transfer and its
//     inclination and LAN are printed as a launch target.
//   Case 2 (in a bound orbit around the departure body): the real orbit sets the ejection cost. The search
//     prices the best burn point anywhere in the orbit; the final stage uses the one the timing dictates.
//   Case 3 (same SOI): the ship burns straight onto a Lambert arc to the destination.
//   Case 4 (on an escape orbit around the departure body): a correction burn. tSOI is pinned to the ship's
//     own exit time, so only the flight time is searched (see escapeLockedDeparture).
//
// The steps:
//   1. buildTransferWindow picks the departure and flight-time samples.
//   2. porkchopGrid runs the coarse grid (transferDeltaV, or sameSOITransferDeltaV in case 3).
//   3. The best cell of each window is refined: a hill climb to 1/8 of the grid spacing, then two Newton
//      steps, with the quick ejection cost. The winner is re-priced at full precision.
//   4. Case 2: phaseLockedDeparture moves the departure to the best burn phase (case 4:
//      escapeLockedDeparture). Cases 2 to 4: addEjectionNode adds the node, and the game's own prediction
//      is compared with the plan.
//
// "tSOI" is the moment the ship leaves the departure body's sphere of influence: the departure time
// Lambert sees. The burn is earlier, by the transit time to the SOI edge.
//
// PARAMETERs:
//   destinationName  - a body or a vessel (a vessel wins a name clash); it becomes the ship's target.
//                      "Default" uses the current target
//   startOffset      - s from now to the start of the search window (>= 30)
//   departureWindows - how many departure windows to search (see buildTransferWindow)
//   samplesPerWindow - departure times per window (case 4: in all). -1 chooses a default
//   tofSamples       - flight times sampled. -1 chooses a default
//   parkingAltitude  - m, case 1 only: altitude of the orbit to design. -1 chooses 50 km, or 30 km above
//                      the atmosphere
//   captureAltitude  - m above the destination body's surface to capture into a circular orbit, which the
//                      trajectory is aimed at. -1 chooses 15 km, or 5 km above the atmosphere; or the orbit
//                      size of a destination vessel or moon
//   searchDays       - game days, the length of the departure range in place of departureWindows. -1: not used
// ============================================================================

PARAMETER destinationName IS "Default".
PARAMETER startOffset IS 120.
PARAMETER departureWindows IS 1.
PARAMETER samplesPerWindow IS -1.
PARAMETER tofSamples IS -1.
PARAMETER parkingAltitude IS "Default".
PARAMETER captureAltitude IS "Default".
PARAMETER searchDays IS -1.
// The source is always where the ship is: this script is run by the ship that will do the burn.
LOCAL sourceName IS "".
SET parkingAltitude TO processScalarParameter(parkingAltitude, errorValue).
IF parkingAltitude = errorValue SET parkingAltitude TO -1.
SET captureAltitude TO processScalarParameter(captureAltitude, errorValue).
IF captureAltitude = errorValue SET captureAltitude TO -1.

CLEARSCREEN.

// The current target is carried as the object, not its name: two vessels can share a name.
IF destinationName = "Default" {
	SET destinationName TO "None".
	LOCAL currentTarget IS currentTargetOrbitable().
	IF NOT currentTarget:ISTYPE("Scalar") SET destinationName TO currentTarget.
}

// With debug on (a global from library.ks), each step's results go to one CSV on the archive: the coarse
// grid first, then Section,Name,Value rows (held back until the grid is written).
GLOBAL transferGridFile IS "0:transferCalc porkchop.csv".
GLOBAL transferGridWritten IS FALSE.
GLOBAL transferPendingLog IS LIST().
// Real-world seconds each stage took (markTime), printed at the end and logged as "Timing" rows.
GLOBAL stageTimings IS LIST().
GLOBAL stageMark IS KUNIVERSE:REALWORLDTIME.
FUNCTION markTime {
	PARAMETER label.

	LOCAL nowTime IS KUNIVERSE:REALWORLDTIME.
	stageTimings:ADD(label + " " + ROUND(nowTime - stageMark, 1) + " s").
	SET stageMark TO nowTime.
}

// Adds one Section,Name,Value row (each quoted, since values such as vectors contain commas).
FUNCTION debugLine {
	PARAMETER section.
	PARAMETER name.
	PARAMETER value.

	LOCAL quote IS CHAR(34).
	// A list is written as its items joined by semicolons (TOSTRING on a list lists each one over several lines).
	LOCAL valueText IS value:TOSTRING.
	IF value:ISTYPE("List") {
		SET valueText TO "".
		FOR item IN value {
			IF valueText <> "" SET valueText TO valueText + "; ".
			SET valueText TO valueText + item:TOSTRING.
		}
	}
	LOCAL line IS quote + section + quote + "," + quote + name + quote + "," + quote + valueText + quote.
	IF transferGridWritten {
		IF connectionToKSC() LOG line TO transferGridFile.
	} ELSE {
		transferPendingLog:ADD(line).
	}
}

// Writes the held-back rows after whatever the file holds, and writes straight to it from then on.
FUNCTION debugFlush {
	IF transferGridWritten RETURN.
	SET transferGridWritten TO TRUE.
	// No archive connection: nothing is written, and the rows are dropped rather than saved elsewhere.
	IF NOT connectionToKSC() {
		transferPendingLog:CLEAR().
		PRINT "No archive connection: debug log not saved.".
		RETURN.
	}
	LOG "" TO transferGridFile.
	LOG "Section,Name,Value" TO transferGridFile.
	FOR line IN transferPendingLog {
		LOG line TO transferGridFile.
	}
	transferPendingLog:CLEAR().
}

// Adds a lexicon's contents, one row per key. A lexicon inside it is listed too, its keys prefixed
// with the outer key and a dot.
FUNCTION debugLogValues {
	PARAMETER section.
	PARAMETER data.
	PARAMETER prefix IS "".

	FOR dataKey IN data:KEYS {
		LOCAL dataValue IS data[dataKey].
		IF dataValue:ISTYPE("Lexicon") {
			debugLogValues(section, dataValue, prefix + dataKey + ".").
		} ELSE {
			debugLine(section, prefix + dataKey, dataValue).
		}
	}
}
// Prints the predicted SOI path after the node just made and anything wrong with it (checkTransferSOIPath).
// Returns the number of problems.
FUNCTION reportSOIPath {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER sameSOI.
	PARAMETER arrivalUT IS 0.

	LOCAL soiCheck IS checkTransferSOIPath(fromOrbitable, toOrbitable, sameSOI, arrivalUT).
	PRINT "SOI path: " + soiCheck["text"] + ".".
	FOR problem IN soiCheck["problems"] {
		PRINT "WARNING: " + problem + ".".
	}
	IF debug {
		LOCAL problemText IS "".
		FOR problem IN soiCheck["problems"] {
			IF problemText <> "" SET problemText TO problemText + "; ".
			SET problemText TO problemText + problem.
		}
		debugLogValues("SOI path", LEXICON("path", soiCheck["text"], "problems", problemText)).
	}
	RETURN soiCheck["problems"]:LENGTH.
}
// Prints how the game's prediction for a same-SOI node compares with the plan (checkNodeEncounter).
// Returns the number of disagreements: an orbit more than 1 km from the plan's, and either a periapsis at a
// destination body that is unsafe or more than half the capture radius from the plan, or (a vessel) an
// arrival more than 1 km from where the plan aimed.
FUNCTION reportNodeEncounter {
	PARAMETER nodeCheck.

	LOCAL disagreements IS 0.
	PRINT "Game's orbit after the node: Pe " + distanceToString(nodeCheck["gamePeriapsis"]) + " (plan " + distanceToString(nodeCheck["planPeriapsis"]) + ").".
	IF ABS(nodeCheck["gamePeriapsis"] - nodeCheck["planPeriapsis"]) > 1000 SET disagreements TO disagreements + 1.
	IF nodeCheck:HASKEY("gameApoapsis") {
		PRINT "  Ap " + distanceToString(nodeCheck["gameApoapsis"]) + " (plan " + distanceToString(nodeCheck["planApoapsis"]) + ").".
		IF ABS(nodeCheck["gameApoapsis"] - nodeCheck["planApoapsis"]) > 1000 SET disagreements TO disagreements + 1.
	}
	IF nodeCheck:HASKEY("captureAimed") {
		// A body with a capture radius: its gravity bends the path, so the periapsis there is what counts.
		IF nodeCheck:HASKEY("gameCapture") {
			PRINT "The game predicts a periapsis of " + distanceToString(nodeCheck["gameCapture"]) + " at the destination (plan " + distanceToString(nodeCheck["planCapture"]) + ").".
			// The plan's periapsis is only good to a few tens of percent (the game hands over to the destination's
			// gravity at its SOI edge), so only a pass that hits it, or one far from the plan, is a disagreement.
			IF nodeCheck["gameCapture"] < nodeCheck["captureFloor"] {
				PRINT "  That is below its surface or inside its atmosphere!".
				SET disagreements TO disagreements + 1.
			} ELSE IF ABS(nodeCheck["gameCapture"] - nodeCheck["planCapture"]) > nodeCheck["captureTolerance"] {
				PRINT "  That is more than " + distanceToString(nodeCheck["captureTolerance"]) + " from the plan!".
				SET disagreements TO disagreements + 1.
			}
		} ELSE {
			PRINT "The game predicts no encounter with the destination: its periapsis there is not checked.".
		}
	} ELSE IF nodeCheck["available"] {
		PRINT "At arrival the game puts the ship " + distanceToString(nodeCheck["miss"]) + " from the destination.".
		IF nodeCheck["deviation"] > 1000 {
			PRINT "  That is " + distanceToString(nodeCheck["deviation"]) + " from where the plan aimed!".
			SET disagreements TO disagreements + 1.
		}
	} ELSE {
		PRINT "The game's position prediction does not follow the node: arrival not checked.".
	}
	IF disagreements > 0 PRINT "WARNING: the game disagrees with the plan.".
	IF debug debugLogValues("Node check", nodeCheck).
	RETURN disagreements.
}
IF debug {
	IF connectionToKSC() AND EXISTS(transferGridFile) DELETEPATH(transferGridFile).
	debugLine("Run", "start", "UT " + TIME:SECONDS + ", " + SHIP:NAME + " in " + SHIP:BODY:NAME + "'s SOI, " + SHIP:STATUS).
	debugLogValues("Parameters", LEXICON("destinationName", destinationName, "startOffset", startOffset, "departureWindows", departureWindows,
		"samplesPerWindow", samplesPerWindow, "tofSamples", tofSamples, "sourceName", sourceName,
		"parkingAltitude", parkingAltitude, "captureAltitude", captureAltitude, "searchDays", searchDays)).
}
LOCAL errorCode IS "None".

LOCAL endpoints IS resolveTransferEndpoints(destinationName, sourceName).
SET errorCode TO endpoints["error"].
LOCAL fromOrbitable IS endpoints["from"].
LOCAL toOrbitable IS endpoints["to"].
LOCAL sameSOI IS endpoints["sameSOI"].
// A destination vessel at a moon: the transfer goes to the moon (toOrbitable); the vessel stays the target.
LOCAL destinationVessel IS endpoints["destinationVessel"].
// A destination moon of another planet: the transfer goes to its planet; the moon stays the target.
LOCAL destinationMoon IS endpoints["destinationMoon"].
LOCAL captureOrbitable IS destinationVessel.
IF destinationMoon:ISTYPE("Body") SET captureOrbitable TO destinationMoon.
LOCAL targetOrbitable IS toOrbitable.
IF errorCode = "None" AND destinationVessel:ISTYPE("Vessel") SET targetOrbitable TO destinationVessel.
IF errorCode = "None" AND destinationMoon:ISTYPE("Body") SET targetOrbitable TO destinationMoon.
// A valid destination becomes the ship's target (the one named, or the one already targeted).
IF errorCode = "None" {
	IF HASTARGET {
		// By object, not name: a different vessel with the same name is not the target.
		IF TARGET <> targetOrbitable SET TARGET TO targetOrbitable.
	} ELSE {
		SET TARGET TO targetOrbitable.
	}
}
IF debug {
	IF errorCode = "None" {
		debugLogValues("Endpoints", LEXICON("from", fromOrbitable:NAME, "to", toOrbitable:NAME, "sameSOI", sameSOI)).
	} ELSE {
		debugLine("Endpoints", "error", errorCode).
	}
}

// A node can only be made for the ship, so a vessel source has to be the ship, in orbit.
IF errorCode = "None" AND sameSOI {
	IF fromOrbitable:NAME <> SHIP:NAME {
		SET errorCode TO "A maneuver node can only be planned for the ship, but the source is " + fromOrbitable:NAME + "!".
	} ELSE IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
		SET errorCode TO "A transfer to " + toOrbitable:NAME + " inside " + SHIP:BODY:NAME + "'s sphere of influence needs the ship in orbit!".
	}
}

// Burns earlier than this (the next minute) can't be flown.
LOCAL minimumBurnLead IS 60.

// Case 4, a ship already on an escape orbit: tSOI is pinned to the ship's own exit (orbitSpec["pinExit"]),
// the departure axis is one sample, and the window is exitSpread seconds before that exit.
LOCAL exitSpread IS 1800.
LOCAL shipEscaping IS FALSE.
LOCAL searchSpan IS -1.
IF searchDays > 0 SET searchSpan TO searchDays * timeUnitSeconds("Days").
LOCAL departureCount IS -1.
IF errorCode = "None" AND NOT sameSOI AND SHIP:BODY:NAME = fromOrbitable:NAME
		AND SHIP:STATUS <> "PRELAUNCH" AND SHIP:STATUS <> "LANDED" AND SHIP:STATUS <> "SPLASHED" {
	LOCAL shipOrbitSpec IS orbitSpecFromVessel(SHIP).
	IF SHIP:ORBIT:ECCENTRICITY >= 1 OR shipOrbitSpec["period"] = 0 SET shipEscaping TO TRUE.
}
IF shipEscaping {
	LOCAL shipExitUT IS orbitPatchUT(SHIP).
	LOCAL searchStartUT IS TIME:SECONDS + startOffset.
	IF shipExitUT = 0 {
		SET errorCode TO "No SOI exit is predicted for the ship's escape orbit!".
	} ELSE IF shipExitUT <= searchStartUT {
		SET errorCode TO "The ship leaves " + fromOrbitable:NAME + "'s sphere of influence before the search could start!".
	} ELSE {
		IF shipExitUT - exitSpread > searchStartUT SET startOffset TO shipExitUT - exitSpread - TIME:SECONDS.
		IF searchSpan <= 0 SET searchSpan TO shipExitUT - (TIME:SECONDS + startOffset).
		SET departureCount TO 1.
		IF samplesPerWindow >= 1 SET departureCount TO samplesPerWindow.
	}
}

LOCAL window IS 0.
IF errorCode = "None" {
	SET window TO buildTransferWindow(endpoints, startOffset, departureWindows, samplesPerWindow, tofSamples, TRUE, searchSpan, departureCount).
	SET errorCode TO window["error"].
}

// Which case: on the ground (1), in a bound orbit around the departure body (2), or same SOI (3).
LOCAL orbitSpec IS 0.
LOCAL shipInParkingOrbit IS FALSE.
LOCAL launchLatitude IS 0.
LOCAL designAltitude IS parkingAltitude.

IF errorCode = "None" AND NOT sameSOI {
	IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
		// The launch site's latitude, if the ship is on the departure body.
		IF SHIP:BODY:NAME = fromOrbitable:NAME SET launchLatitude TO SHIP:LATITUDE.
		ELSE PRINT "Ship not on " + fromOrbitable:NAME + ": no latitude floor.".
		IF designAltitude < 0 {
			SET designAltitude TO 50000.
			IF fromOrbitable:ATM:EXISTS SET designAltitude TO fromOrbitable:ATM:HEIGHT + 30000.
		}
		SET orbitSpec TO designSpec(fromOrbitable, designAltitude, launchLatitude).
		PRINT "On the ground: designing " + ROUND(designAltitude / 1000, 1) + " km orbit at " + fromOrbitable:NAME + ".".
	} ELSE IF SHIP:BODY:NAME = fromOrbitable:NAME {
		SET orbitSpec TO orbitSpecFromVessel(SHIP).
		IF shipEscaping {
			// No burn before the earliest one that can be flown; ejectionDeltaVForExit reads this.
			SET orbitSpec["earliestBurnUT"] TO TIME:SECONDS + minimumBurnLead.
			// Price every cell at the ship's own exit time (transferDeltaV): its exit time is not a free variable.
			SET orbitSpec["pinExit"] TO TRUE.
			PRINT "On an escape orbit at " + fromOrbitable:NAME + ": pricing a correction burn from it.".
		} ELSE {
			SET shipInParkingOrbit TO TRUE.
			PRINT "In orbit at " + fromOrbitable:NAME + ": using that orbit.".
		}
	} ELSE {
		SET errorCode TO "The ship must be on the ground, or in orbit around " + fromOrbitable:NAME + "!".
	}
}

IF errorCode = "None" {
	IF HASNODE AND (shipEscaping OR shipInParkingOrbit OR sameSOI) {
		PRINT "Note: " + ALLNODES:LENGTH + " maneuver node(s) exist; they may change the predicted orbit.".
	}

	LOCAL captureRadius IS 0.
	IF toOrbitable:ISTYPE("Body") {
		IF captureAltitude < 0 {
			IF captureOrbitable:ISTYPE("Vessel") OR captureOrbitable:ISTYPE("Body") {
				// The destination vessel's or moon's orbit size.
				SET captureAltitude TO orbitSizeRadius(captureOrbitable, toOrbitable) - toOrbitable:RADIUS.
				PRINT captureOrbitable:NAME + " orbits " + toOrbitable:NAME + ": capturing at its orbit size, " + ROUND(captureAltitude / 1000, 1) + " km up.".
			} ELSE {
				// The default: 15 km up with no atmosphere, 5 km above the top of one.
				SET captureAltitude TO 15000.
				IF toOrbitable:ATM:EXISTS SET captureAltitude TO toOrbitable:ATM:HEIGHT + 5000.
			}
		}
		SET captureRadius TO toOrbitable:RADIUS + captureAltitude.
	}

	IF debug {
		debugLogValues("Setup", LEXICON("captureRadius", captureRadius, "shipInParkingOrbit", shipInParkingOrbit,
			"launchLatitude", launchLatitude, "designAltitude", designAltitude)).
		debugLogValues("Window", window).
		IF orbitSpec:ISTYPE("Lexicon") debugLogValues("Orbit spec", orbitSpec).
	}

	// Between bodies the coarse stages use the quick ejection search; the winner is re-priced with the full one.
	LOCAL quickDelegate IS 0.
	LOCAL fullDelegate IS 0.
	IF sameSOI {
		PRINT fromOrbitable:NAME + " -> " + toOrbitable:NAME + " (same SOI).".
		SET quickDelegate TO bindSameSOIDeltaV(fromOrbitable, toOrbitable, captureRadius, window["startTime"]).
		SET fullDelegate TO quickDelegate.
	} ELSE {
		PRINT fromOrbitable:NAME + " -> " + toOrbitable:NAME + " (around " + window["sunBody"]:NAME + ").".
		SET quickDelegate TO bindTransferDeltaV(fromOrbitable, toOrbitable, window["sunBody"], orbitSpec, captureRadius, ejectionPrecision("quick")).
		SET fullDelegate TO bindTransferDeltaV(fromOrbitable, toOrbitable, window["sunBody"], orbitSpec, captureRadius, ejectionPrecision("full")).
	}

	PRINT searchWindowLine(window).

	// Coarse grid over the whole search window.
	markTime("Setup").
	LOCAL grid IS porkchopGrid(quickDelegate, window).
	markTime("Coarse grid").
	PRINT "Grid: " + grid["totalCells"] + " cells.".
	PRINT motionTypeSummary(grid, TRUE).
	FOR reasonLine IN failureReasonLines(grid) {
		PRINT "Failed - " + reasonLine.
	}

	// The best coarse cell in each window is what gets refined.
	LOCAL coarseCandidates IS porkchopBestPerBand(grid).

	IF debug {
		writePorkchopCsv(grid, window, transferGridFile, fromOrbitable, toOrbitable).
		debugFlush().
		debugLogValues("Coarse grid", LEXICON("cells", grid["totalCells"], "motionTypes", motionTypeSummary(grid), "failureReasons", grid["failureReasonCounts"],
			"minDeltaV", grid["minDeltaV"]["value"], "minDepartureTime", grid["minDeltaV"]["departureTime"],
			"minTimeOfFlight", grid["minDeltaV"]["timeOfFlight"], "gameSeconds", grid["duration"], "realSeconds", grid["realDuration"],
			"csv", transferGridFile)).
		FOR band IN coarseCandidates:KEYS {
			debugLogValues("Best coarse cell, window " + band, coarseCandidates[band]).
		}
	}

	// Refine each window's best cell: a hill climb stopped at 1/8 of the grid spacing (hillClimbRatio
	// halvings), then two Newton steps.
	LOCAL hillClimbRatio IS 3.
	// The departure is clamped to the window: a refinement that leaves it finds a plan that cannot be flown.
	// Outside the window the price also rises a little with the distance outside (0.001 m/s per second), so
	// the refinement is led back in: a flat price there lets it drift away on rounding noise, and from a
	// step or more outside it no longer sees the departures inside.
	LOCAL windowStartUT IS window["departureStart"].
	LOCAL windowEndUT IS window["departureEnd"].
	LOCAL boundedDelegate IS {
		PARAMETER departureUT.
		PARAMETER flightTime.

		LOCAL heldUT IS MAX(windowStartUT, MIN(windowEndUT, departureUT)).
		RETURN quickDelegate(heldUT, flightTime) + 0.001 * ABS(departureUT - heldUT).
	}.
	LOCAL bestOverall IS LEXICON("finalValue", invalidDeltaV).
	FOR band IN coarseCandidates:KEYS {
		PRINT "Refining window " + band + ".".
		LOCAL seed IS coarseCandidates[band].
		LOCAL climbed IS hillClimb2D(boundedDelegate,		// already-bound delegate, held to the window
			seed["departureTime"], seed["flightTime"],		// initial guesses, from the coarse pass - both absolute (seconds)
			window["departureStep"], window["tofStep"],		// initial step size, in seconds
			"", 20, hillClimbRatio).						// log, iterationMax, smallestStepRatio
		LOCAL refined IS newtonRefine2D(boundedDelegate, climbed["finalGuess1"], climbed["finalGuess2"], climbed["finalValue"],
			window["departureStep"] / 2 ^ hillClimbRatio, window["tofStep"] / 2 ^ hillClimbRatio, 2).
		PRINT "  " + climbed["iteration"] + " climb steps + " + refined["steps"] + " Newton steps.".
		IF debug {
			debugLogValues("Hill climb, window " + band, climbed).
			debugLogValues("Newton refinement, window " + band, refined).
		}
		IF refined["finalValue"] < bestOverall["finalValue"] SET bestOverall TO refined.
	}

	markTime("Hill climb and Newton").
	IF bestOverall["finalValue"] >= invalidDeltaV {
		SET errorCode TO "No valid transfer was found in the search window.".
	} ELSE {
		// finalGuess1 is tSOI (case 3: the burn time), a UT; finalGuess2 is the flight time.
		LOCAL reportTSOI IS MAX(windowStartUT, MIN(windowEndUT, bestOverall["finalGuess1"])).
		LOCAL reportTimeOfFlight IS bestOverall["finalGuess2"].
		LOCAL reportStats IS LEXICON().
		// Re-price the winner with the full ejection search - the hill climb only saw the quick one.
		LOCAL reportDV IS fullDelegate(reportTSOI, reportTimeOfFlight, LEXICON(), reportStats).
		markTime("Full-precision pricing").
		LOCAL soiProblems IS 0.
		LOCAL nodeDisagreements IS 0.
		IF debug {
			debugLogValues("Winner", LEXICON("departureTime", reportTSOI, "flightTime", reportTimeOfFlight, "deltaV", reportDV)).
			debugLogValues("Full-precision pricing of the winner", reportStats).
		}

		IF sameSOI {
			// Case 3: the burn is at the departure time itself.
			LOCAL departure IS reportStats["Ejection"].
			// The ship's predicted position at arrival before the node, for checkNodeEncounter.
			LOCAL plannedArrival IS departure["burnUT"] + reportTimeOfFlight.
			LOCAL shipBeforeNode IS POSITIONAT(SHIP, plannedArrival).
			LOCAL nodeResult IS addEjectionNode(departure).
			IF debug debugLogValues("Node (same SOI)", nodeResult).
			PRINT "Node set: burn in " + timeToString(departure["burnUT"] - TIME:SECONDS) + ", " + ROUND(departure["deltaV"], 1) + " m/s.".
			PRINT "  pro " + ROUND(nodeResult["prograde"], 1) + ", norm " + ROUND(nodeResult["normal"], 1) + ", rad " + ROUND(nodeResult["radial"], 1) + " m/s.".
			IF NOT nodeResult["verified"] {
				PRINT "WARNING: node dV off by " + ROUND(nodeResult["nodeError"], 2) + " m/s.".
			}
			SET soiProblems TO reportSOIPath(fromOrbitable, toOrbitable, sameSOI, plannedArrival).
			LOCAL aimOffset IS V(0, 0, 0).
			IF reportStats:HASKEY("Aim Offset") SET aimOffset TO reportStats["Aim Offset"].
			SET nodeDisagreements TO reportNodeEncounter(checkNodeEncounter(departure, toOrbitable, fromOrbitable:BODY, plannedArrival, shipBeforeNode, aimOffset, captureRadius)).
		} ELSE IF shipInParkingOrbit OR shipEscaping {
			LOCAL timed IS 0.
			IF shipEscaping {
				// No burn phase to lock to: move tSOI to the correction burn's real exit time and price again.
				PRINT "Moving the departure to the correction burn's exit time.".
				SET timed TO escapeLockedDeparture(fromOrbitable, toOrbitable, window["sunBody"], orbitSpec, captureRadius,
					reportTSOI, reportTimeOfFlight).
				PRINT "Exit time lock: " + timed["passes"] + " passes, " + ROUND(timed["deltaV"], 1) + " m/s.".
			} ELSE {
				// Lock tSOI to the best burn phase of the ship's orbit. The full-precision price just made is its first pass.
				PRINT "Locking to the best burn phase.".
				SET timed TO phaseLockedDeparture(fromOrbitable, toOrbitable, window["sunBody"], orbitSpec, captureRadius,
					reportTSOI, reportTimeOfFlight, TIME:SECONDS + minimumBurnLead, 4, reportDV, reportStats).
				PRINT "Phase lock: " + timed["passes"] + " passes. Any phase " + ROUND(timed["phaseFreeDeltaV"], 1) +
					" m/s, timed " + ROUND(timed["deltaV"], 1) + " m/s.".
				// The phase lock's own stages (library timings), in place of one lump.
				IF timed:HASKEY("timings") {
					FOR lapNote IN timed["timings"] {
						stageTimings:ADD("  " + lapNote).
					}
				}
				markTime("Phase lock total (incl. the above)").
			}
			IF debug {
				debugLogValues("Phase lock", LEXICON("passes", timed["passes"], "phaseFreeDeltaV", timed["phaseFreeDeltaV"],
					"timedDeltaV", timed["deltaV"], "tSOI", timed["tSOI"])).
				IF timed["deltaV"] < invalidDeltaV debugLogValues("Timed pricing", timed["stats"]).
			}
			IF timed["deltaV"] < invalidDeltaV {
				SET reportTSOI TO timed["tSOI"].
				IF timed:HASKEY("flightTime") SET reportTimeOfFlight TO timed["flightTime"].
				SET reportDV TO timed["deltaV"].
				SET reportStats TO timed["stats"].
				LOCAL ejection IS reportStats["Ejection"].
				LOCAL nodeResult IS addEjectionNode(ejection).
				IF debug debugLogValues("Node", nodeResult).
				PRINT "Node set: burn in " + timeToString(ejection["burnUT"] - TIME:SECONDS) + ", " + ROUND(ejection["deltaV"], 1) + " m/s.".
				PRINT "  pro " + ROUND(nodeResult["prograde"], 1) + ", norm " + ROUND(nodeResult["normal"], 1) + ", rad " + ROUND(nodeResult["radial"], 1) + " m/s.".
				IF NOT nodeResult["verified"] {
					PRINT "WARNING: node dV off by " + ROUND(nodeResult["nodeError"], 2) + " m/s.".
				}
				SET soiProblems TO reportSOIPath(fromOrbitable, toOrbitable, sameSOI).
				// Compare the game's own prediction with the plan.
				IF NOT shipEscaping {
					LOCAL aimOffsetSize IS 0.
					IF reportStats:HASKEY("Aim Offset") SET aimOffsetSize TO reportStats["Aim Offset"]:MAG.
					// The game's orbit after the SOI exit against the plan's arc there. If they match, a missing encounter
					// is more likely the game's prediction than the plan.
					LOCAL solarOrbitMatches IS FALSE.
					IF HASNODE {
						LOCAL ejectionPatch IS NEXTNODE:ORBIT.
						IF ejectionPatch:HASNEXTPATCH AND reportStats:HASKEY("r_1") AND reportStats:HASKEY("v_1") {
							LOCAL gameExitUT IS TIME:SECONDS + ejectionPatch:NEXTPATCHETA.
							// The game's velocity one second after the exit against the plan's (v_1 advanced under the central body's pull).
							LOCAL checkAfter IS 1.
							LOCAL gameVelocity IS VELOCITYAT(SHIP, reportTSOI + checkAfter):ORBIT.
							LOCAL planPull IS reportStats["r_1"]:NORMALIZED * (-window["sunBody"]:MU / reportStats["r_1"]:MAG ^ 2).
							LOCAL planVelocity IS reportStats["v_1"] + planPull * checkAfter.
							LOCAL velocityError IS gameVelocity - planVelocity.
							// Within 0.05 m/s and the same exit time.
							IF velocityError:MAG < 0.05 AND ABS(gameExitUT - reportTSOI) < 2 SET solarOrbitMatches TO TRUE.
							PRINT "Solar velocity just after the exit: the game's differs from the plan's by " + ROUND(velocityError:MAG, 3) + " m/s,".
							PRINT "  " + ROUND(VANG(gameVelocity, planVelocity), 4) + " deg apart in direction (speed " + ROUND(gameVelocity:MAG - planVelocity:MAG, 3) + " m/s).".
							IF debug debugLogValues("Solar velocity check", LEXICON("gameVelocity", gameVelocity, "planVelocity", planVelocity,
								"velocityError", velocityError:MAG, "directionError", VANG(gameVelocity, planVelocity), "speedError", gameVelocity:MAG - planVelocity:MAG)).
						}
					}
					// The game's patch at the destination, and its periapsis there.
					IF toOrbitable:ISTYPE("Body") AND HASNODE {
						LOCAL planPeriapsisAltitude IS captureRadius - toOrbitable:RADIUS.
						LOCAL patch IS NEXTNODE:ORBIT.
						LOCAL foundPatch IS FALSE.
						UNTIL foundPatch OR NOT patch:HASNEXTPATCH {
							SET patch TO patch:NEXTPATCH.
							IF patch:BODY:NAME = toOrbitable:NAME SET foundPatch TO TRUE.
						}
						IF foundPatch {
							PRINT "The game predicts a capture at " + toOrbitable:NAME + ": periapsis " + distanceToString(patch:PERIAPSIS) + " (plan " + distanceToString(planPeriapsisAltitude) + ").".
							PRINT "  Aimed " + distanceToString(aimOffsetSize) + " off its centre; its sphere of influence is " + distanceToString(toOrbitable:SOIRADIUS) + ".".
							IF debug debugLogValues("Node check", LEXICON("gamePeriapsisAtDestination", patch:PERIAPSIS, "planPeriapsisAtDestination", planPeriapsisAltitude, "soiRadius", toOrbitable:SOIRADIUS, "aimOffsetMagnitude", aimOffsetSize)).
						} ELSE {
							PRINT "The game predicts no encounter with " + toOrbitable:NAME + " (its sphere of influence is " + distanceToString(toOrbitable:SOIRADIUS) + ", the aim " + distanceToString(aimOffsetSize) + " off centre).".
							IF solarOrbitMatches AND soiProblems = 1 {
								PRINT "  The game's solar orbit matches the plan's, so this is probably the game's prediction, not the plan: not counted as a warning.".
								SET soiProblems TO 0.
							}
							IF debug debugLogValues("Node check", LEXICON("soiRadius", toOrbitable:SOIRADIUS, "aimOffsetMagnitude", aimOffsetSize, "solarOrbitMatches", solarOrbitMatches)).
						}
					}
				}
			} ELSE {
				IF shipEscaping PRINT "No correction burn on this escape orbit reaches it: no node.".
				ELSE PRINT "No burn in this orbit reaches it: no node.".
				SET errorCode TO "No maneuver node was made: the exact-timed burn was not found".
			}
		} ELSE {
			// Case 1: report the parking orbit designed for the winning transfer.
			LOCAL designed IS reportStats["Ejection"].
			IF debug debugLogValues("Designed parking orbit", designed).
			PRINT "".
			PRINT "Launch target (no orbit yet):".
			PRINT "  Latitude:     " + ROUND(launchLatitude, 2) + " deg".
			PRINT "  Altitude:     " + ROUND(designAltitude / 1000, 1) + " km".
			PRINT "  Min incl.:    " + ROUND(designed["pureMinimumInclination"], 2) + " deg".
			PRINT "  Inclination:  " + ROUND(designed["inclination"], 2) + " deg".
			PRINT "  LAN:          " + ROUND(designed["lan"], 2) + " deg".
			IF designed["latitudeConstraintBinding"] {
				PRINT "  Latitude binds; alt. LAN " + ROUND(designed["alternateLan"], 2) + " deg.".
			}
			PRINT "  (check residual " + ROUND(designed["verificationResidual"], 6) + " deg)".

			// Save the plan on the ship's own disk for a launch script (READJSON). The burn is one transit time
			// before tSOI; in the closed-form case the hyperbola is rebuilt from the orbit radius and the excess speed.
			LOCAL planMu IS fromOrbitable:MU.
			LOCAL planRadius IS orbitSpec["radius"].
			LOCAL planVInfinity IS 0.
			LOCAL planTransit IS 0.
			IF designed["ejection"]:ISTYPE("Lexicon") {
				SET planVInfinity TO designed["ejection"]["vInfinity"].
				SET planTransit TO designed["ejection"]["transitTime"].
			} ELSE {
				LOCAL parkSpeed IS SQRT(planMu / planRadius).
				SET planVInfinity TO SQRT(MAX(0, (designed["deltaV"] + parkSpeed) ^ 2 - 2 * planMu / planRadius)).
				IF planVInfinity > 0 {
					LOCAL planEccentricity IS 1 + planRadius * planVInfinity ^ 2 / planMu.
					LOCAL planSemiLatus IS planRadius * (1 + planEccentricity).
					LOCAL planEdgeAnomaly IS ARCCOS(MAX(-1, MIN(1, (planSemiLatus / fromOrbitable:SOIRADIUS - 1) / planEccentricity))).
					SET planTransit TO hyperbolaTransitTime(planMu, planVInfinity, planEccentricity, 0, planEdgeAnomaly).
				}
			}
			LOCAL planBurnUT IS reportTSOI - planTransit.
			LOCAL launchPlan IS LEXICON(
				"version", 1,
				"createdUT", TIME:SECONDS,
				"departureBody", fromOrbitable:NAME,
				"destination", toOrbitable:NAME,
				"burnUT", planBurnUT,
				"burnCalendar", TIME(planBurnUT):CALENDAR,
				"burnClock", TIME(planBurnUT):CLOCK,
				"soiExitUT", reportTSOI,
				"transitTime", planTransit,
				"flightTime", reportTimeOfFlight,
				"arrivalUT", reportTSOI + reportTimeOfFlight,
				"ejectionDeltaV", designed["deltaV"],
				"arrivalDeltaV", reportStats["Arrival Delta V"],
				"totalDeltaV", reportDV,
				"vInfinity", planVInfinity,
				"inclination", designed["inclination"],
				"lan", designed["lan"],
				"alternateLan", designed["alternateLan"],
				"latitudeConstraintBinding", designed["latitudeConstraintBinding"],
				"parkingAltitude", designAltitude,
				"parkingRadius", planRadius,
				"launchLatitude", launchLatitude).
			IF debug debugLogValues("Launch plan", launchPlan).

			LOCAL planFile IS "1:transferPlan.json".
			IF VOLUME(1):FREESPACE < 4000 {
				PRINT "Local disk full: plan not saved.".
			} ELSE {
				IF EXISTS(planFile) DELETEPATH(planFile).
				WRITEJSON(launchPlan, planFile).
				PRINT "Saved launch plan: " + planFile.
			}
		}

		PRINT "".
		IF sameSOI {
			PRINT "Departure " + distanceToString(reportStats["Ejection"]["deltaV"]) + "/s + arrival " + distanceToString(reportStats["Arrival Delta V"]) + "/s.".
		} ELSE IF shipEscaping {
			PRINT "Correction " + distanceToString(reportStats["Ejection"]["deltaV"]) + "/s + arrival " + distanceToString(reportStats["Arrival Delta V"]) + "/s.".
		} ELSE {
			PRINT "Ejection " + distanceToString(reportStats["Ejection"]["deltaV"]) + "/s + arrival " + distanceToString(reportStats["Arrival Delta V"]) + "/s.".
		}
		IF reportStats:HASKEY("Aim Offset") {
			PRINT "Aimed " + distanceToString(reportStats["Aim Offset"]:MAG) + " off " + toOrbitable:NAME + "'s centre, for a " + distanceToString(captureRadius - toOrbitable:RADIUS) + " periapsis altitude.".
		}
		PRINT "Complete".
		WAIT 0.5.

		SET loopMessage TO fromOrbitable:NAME + " -> " + toOrbitable:NAME + " " + ROUND(reportDV) + "m/s in " + durationToUnitString(reportTimeOfFlight).
		IF soiProblems > 0 SET loopMessage TO loopMessage + " (SOI WARNING)".
		IF nodeDisagreements > 0 SET loopMessage TO loopMessage + " (NODE CHECK WARNING)".
	}
}

IF errorCode <> "None" SET loopMessage TO "Error: " + errorCode.
markTime("Node and checks").
PRINT "Time taken:".
FOR timingLine IN stageTimings {
	PRINT "  " + timingLine.
}
IF debug {
	debugLine("Timing", "stages", stageTimings).
	debugLogValues("Result", LEXICON("errorCode", errorCode, "loopMessage", loopMessage)).
	debugFlush().
}
PRINT "Complete!".
// Whether it made a node or stopped on an error, tell the operator it is done (a beep, then a 5 s wait).
alertOperator().
