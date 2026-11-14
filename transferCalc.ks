@LAZYGLOBAL OFF.

// ============================================================================
// transferCalc.ks - finds the cheapest transfer to a destination (a body or a vessel) and, for a
// ship in orbit, makes the maneuver node for it. Built on libraryTransfer.ks, in patched-conic
// terms. porkchopplot.ks takes the same parameters in the same order and plots the same window.
//
// Only the destination is needed: resolveTransferEndpoints works out the source from where the ship is.
//   - A destination that orbits the body the ship is in (a satellite, or a moon) is a SAME-SOI
//     transfer: from the ship, with no sphere of influence to leave (case 3 below).
//   - A destination that orbits that body's parent (Duna from Kerbin orbit; Minmus from Mun orbit)
//     is a transfer from the body the ship is in (cases 1 and 2 below).
//   - A destination VESSEL at a moon of the ship's body, or of its body's parent (a vessel at Minmus, from
//     Kerbin or Mun orbit), plans the transfer to that moon, aimed at a periapsis equal to the vessel's
//     orbit size (semi-major axis) unless captureAltitude says otherwise. The vessel stays the target.
//   - Anything else (Kerbin from Mun orbit, Duna from Mun orbit) is reported as an error.
//
//   Case 1 (ship on the pad, or landed): a circular parking orbit is designed for the winning
//     transfer and its inclination and LAN are printed as a launch target. The grid prices the
//     best burn point anywhere in that orbit.
//   Case 2 (ship in a bound orbit around the departure body): the real orbit - both plane angles,
//     its shape, and where the ship is in it - sets the ejection cost. The grid prices the best
//     burn point anywhere in the orbit; the final stage then uses the burn point the timing
//     actually dictates, which can cost more.
//   Case 3 (same SOI): the ship burns straight onto a Lambert arc to the destination and matches its
//     velocity there. The burn time is the departure time, so there is no exit-time or phase logic.
//   Case 4 (ship on an escape orbit around the departure body, e.g. after the main ejection burn): a
//     correction burn. It does not repeat, so there is no burn phase to lock to, and its exit time can
//     only move by minutes, so exit time is not searched. Every price is for the cheapest burn, between
//     now and a few minutes before the ship's own SOI exit, that reaches the wanted exit velocity
//     (ejectionFreeExit), whenever it then exits, and tSOI is pinned to the ship's own exit time, so only
//     the flight time is searched. The winner's departure is then moved to the burn's real exit time and
//     its flight time searched once more there (escapeLockedDeparture).
//
// The steps:
//   1. buildTransferWindow picks the departure and flight-time samples: a COARSE search over
//      departureWindows windows (see the PARAMETERs). For a fine search over a window see porkchopplot.ks.
//   2. porkchopGrid runs the coarse grid. Cases 1 and 2: each cell is priced by transferDeltaV (Lambert's
//      short-way and long-way solutions, the ejection from the departure orbit onto the velocity wanted
//      at the departure body's SOI edge, and the arrival). Case 3: by sameSOITransferDeltaV.
//   3. The best cell of each departure window is refined: a hill climb (hillClimb2D) down to 1/8 of the
//      grid spacing, then two Newton steps (newtonRefine2D, in library.ks). With several windows there
//      are several refinements, and the cheapest of them wins. Cases 1 and 2 use the quick ejection
//      cost here; the winner is then re-priced at full precision.
//   4. Case 2 only: phaseLockedDeparture moves the departure to the best burn phase of the ship's
//      orbit (case 4: escapeLockedDeparture moves it to the correction burn's exit time). Cases 2, 3
//      and 4: addEjectionNode adds the maneuver node (radial + normal + prograde).
//
// "tSOI" below is the moment the ship leaves the departure body's sphere of influence - the
// departure time Lambert sees. The ejection burn itself happens earlier, by the hyperbolic
// transit time from the burn to the SOI edge.
//
// PARAMETERs:
//   destinationName  - the destination: a body, or a vessel (a vessel wins a name clash). If it is valid
//                      it also becomes the ship's target. "Default" uses the current target
//   startOffset      - s from now to the start of the search window (>= 30)
//   departureWindows - how many departure windows to search. Between bodies a window is a synodic
//                      period; in the same SOI it is a synodic period or four ship orbits, whichever is shorter
//   samplesPerWindow - departure times sampled in each window; the grid covers
//                      departureWindows x samplesPerWindow departure times in all (in case 4, the total, 1 by default: the departure is pinned there). -1 (the default) chooses:
//                      between bodies 8 per period of the quicker body in the window (4 to 24), 12 per ship orbit in the same SOI
//   tofSamples       - flight times sampled (1 to 4 times the Hohmann time). -1 (the default) chooses:
//                      5 between bodies, 7 in the same SOI
//   parkingAltitude  - m, case 1 only: altitude of the parking orbit to design. -1 (the default) chooses
//                      50 km, or 30 km above the atmosphere if there is one.
//   captureAltitude  - m above the destination body's surface to capture into a circular orbit.
//                      -1 (the default) chooses 15 km, or 5 km above the atmosphere if there is one; or, for
//                      a destination vessel at a moon (see below), the vessel's orbit size (semi-major axis).
//                      The trajectory is aimed at this periapsis, not at the body's centre (arrivalAimOffset:
//                      the impact parameter, on the side of a prograde capture). A vessel in the ship's own SOI has
//                      no capture: only its arrival excess speed is priced.
//   solverType       - the Lambert solver: "Gooding" (the default) or "Gauss"
//   searchDays       - game days, the length of the departure range, in place of departureWindows windows.
//                      -1 (the default) uses departureWindows. Searches only the departures soon, instead of
//                      a whole synodic period; also needed when a vessel is on an escape orbit with no SOI
//                      change to end the search (see buildTransferWindow)
// ============================================================================

PARAMETER destinationName IS "Default".
PARAMETER startOffset IS 120.
PARAMETER departureWindows IS 1.
PARAMETER samplesPerWindow IS -1.
PARAMETER tofSamples IS -1.
PARAMETER parkingAltitude IS "Default".
PARAMETER captureAltitude IS "Default".
PARAMETER solverType IS "Gooding".
PARAMETER searchDays IS -1.
// The source is always where the ship is: this script is run by the ship that will do the burn.
LOCAL sourceName IS "".
SET parkingAltitude TO processScalarParameter(parkingAltitude, errorValue).
IF parkingAltitude = errorValue SET parkingAltitude TO -1.
SET captureAltitude TO processScalarParameter(captureAltitude, errorValue).
IF captureAltitude = errorValue SET captureAltitude TO -1.

CLEARSCREEN.

IF destinationName = "Default" {
	IF HASTARGET SET destinationName TO TARGET:NAME.
	ELSE SET destinationName TO "None".
}

// With debug on (a global from library.ks), the script writes what each step produced to one CSV
// on the archive: first the coarse porkchop grid (writePorkchopCsv, which replaces the file), then
// everything else as Section,Name,Value rows. Rows produced before the grid exists are held back
// and added after it. With debug off none of this runs and nothing is written.
GLOBAL transferGridFile IS "0:transferCalc porkchop.csv".
GLOBAL transferGridWritten IS FALSE.
GLOBAL transferPendingLog IS LIST().

// The unit of a logged value, from its type and its name (the part after any "." is what counts).
// Anything that is just a number with no unit is "unitless"; counts are "count".
FUNCTION debugUnits {
	PARAMETER section.
	PARAMETER name.
	PARAMETER value.

	IF value:ISTYPE("Boolean") RETURN "boolean".
	IF value:ISTYPE("String") RETURN "text".
	IF NOT (value:ISTYPE("Scalar") OR value:ISTYPE("Vector") OR value:ISTYPE("List")) RETURN "text".
	IF name:STARTSWITH("failureReasons.") RETURN "count".

	LOCAL key IS name.
	IF name:CONTAINS(".") SET key TO name:SUBSTRING(name:FINDLAST(".") + 1, name:LENGTH - name:FINDLAST(".") - 1).
	SET key TO key:TOLOWER.
	LOCAL unit IS "unitless".

	IF key = "final value" {
		SET unit TO "unitless".
	} ELSE IF key = "mu" {
		SET unit TO "m^3/s^2".
	} ELSE IF key:CONTAINS("unitseconds") {
		SET unit TO "s per unit".
	} ELSE IF key = "finalguess1" OR key = "initialguess1" {
		SET unit TO "s (UT)".
	} ELSE IF key = "finalguess2" OR key = "initialguess2" {
		SET unit TO "s".
	} ELSE IF key = "initialvalue" OR key = "deltavalue" OR key = "vinfinity" {
		SET unit TO "m/s".
	} ELSE IF key:CONTAINS("anomaly") {
		SET unit TO "deg".
	} ELSE IF key:CONTAINS("exit offset") {
		SET unit TO "m".
	} ELSE IF key:CONTAINS("rejected") {
		SET unit TO "count".
	} ELSE IF key:CONTAINS("deltav") OR key:CONTAINS("delta v") OR key = "dv" OR key = "finalvalue" OR key:CONTAINS("velocity") OR key = "v_1" OR key = "v_2" OR key = "dvvector" OR key = "prograde" OR key = "normal" OR key = "radial" OR key = "nodeerror" {
		SET unit TO "m/s".
	} ELSE IF key:CONTAINS("position") OR key = "r_1" OR key = "r_2" OR key:CONTAINS("altitude") OR key:CONTAINS("radius") OR key = "sma" OR key:CONTAINS("periapsis") {
		SET unit TO "m".
	} ELSE IF key:CONTAINS("latitude") OR key:CONTAINS("inclination") OR key:ENDSWITH("lan") OR key:CONTAINS("residual") {
		SET unit TO "deg".
	} ELSE IF key:CONTAINS("flighttime") OR key:CONTAINS("timeofflight") OR key:CONTAINS("tofstart") OR key:CONTAINS("tofend") OR key:CONTAINS("period") OR key:CONTAINS("hohmann")
			OR key:CONTAINS("step") AND NOT key:CONTAINS("steps") OR key:CONTAINS("windowlength") OR key:CONTAINS("startoffset") OR key:CONTAINS("transit") OR key = "offset"
			OR key:CONTAINS("seconds") OR key = "timeofflights" OR key = "tof" {
		SET unit TO "s".
	} ELSE IF key:CONTAINS("departuretime") OR key:CONTAINS("starttime") OR key:CONTAINS("departurestart") OR key:CONTAINS("departureend") OR key = "epoch" OR key = "tsoi" OR key = "burnut" {
		SET unit TO "s (UT)".
	} ELSE IF key = "dv" OR key = "mindeltav" {
		SET unit TO "m/s".
	} ELSE IF key:CONTAINS("samples") OR key:CONTAINS("windows") OR key:CONTAINS("cells") OR key:CONTAINS("iteration") OR key:CONTAINS("evaluations") OR key = "steps" OR key = "passes" OR key:CONTAINS("sense") {
		SET unit TO "count".
	}
	IF value:ISTYPE("List") RETURN unit + " (each item)".
	RETURN unit.
}

// Adds one Section,Name,Value,Units row (each quoted, since values such as vectors contain commas).
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
	LOCAL line IS quote + section + quote + "," + quote + name + quote + "," + quote + valueText + quote + "," + quote + debugUnits(section, name, value) + quote.
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
	LOG "Section,Name,Value,Units" TO transferGridFile.
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
// Prints where the ship's predicted path goes after the node just made, and anything wrong with it (see
// checkTransferSOIPath). Returns the number of problems.
FUNCTION reportSOIPath {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER sameSOI.

	LOCAL soiCheck IS checkTransferSOIPath(fromOrbitable, toOrbitable, sameSOI).
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
IF debug {
	IF connectionToKSC() AND EXISTS(transferGridFile) DELETEPATH(transferGridFile).
	debugLine("Run", "start", "UT " + TIME:SECONDS + ", " + SHIP:NAME + " in " + SHIP:BODY:NAME + "'s SOI, " + SHIP:STATUS).
	debugLogValues("Parameters", LEXICON("destinationName", destinationName, "startOffset", startOffset, "departureWindows", departureWindows,
		"samplesPerWindow", samplesPerWindow, "tofSamples", tofSamples, "sourceName", sourceName,
		"parkingAltitude", parkingAltitude, "captureAltitude", captureAltitude, "solverType", solverType, "searchDays", searchDays)).
}
LOCAL errorCode IS "None".

LOCAL endpoints IS resolveTransferEndpoints(destinationName, sourceName).
SET errorCode TO endpoints["error"].
LOCAL fromOrbitable IS endpoints["from"].
LOCAL toOrbitable IS endpoints["to"].
LOCAL sameSOI IS endpoints["sameSOI"].
// A destination vessel at a moon of the ship's body (or of its body's parent): the transfer goes to the moon
// (toOrbitable), and the vessel (or the target itself) is what the ship ends up near.
LOCAL destinationVessel IS endpoints["destinationVessel"].
LOCAL targetOrbitable IS toOrbitable.
IF errorCode = "None" AND destinationVessel:ISTYPE("Vessel") SET targetOrbitable TO destinationVessel.
// A valid destination becomes the ship's target (the one named, or the one already targeted).
IF errorCode = "None" {
	IF HASTARGET {
		IF TARGET:NAME <> targetOrbitable:NAME SET TARGET TO targetOrbitable.
	} ELSE {
		SET TARGET TO targetOrbitable.
	}
}
IF errorCode = "None" AND solverType <> "Gauss" AND solverType <> "Gooding" {
	SET errorCode TO "solverType must be Gauss or Gooding, not " + solverType + "!".
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

// A ship already leaving the departure body on an escape orbit (case 4, a correction burn after the main
// ejection burn): there is no parking orbit to burn from, and its own SOI exit is already close to the
// wanted one: a burn can move the exit by minutes, not hours. So exit time is not searched: every price
// pins tSOI to the ship's own exit (orbitSpec["pinExit"], see transferDeltaV), the departure axis is a
// single sample (searchDays and samplesPerWindow, here the total, can change that, to no effect), and the
// flight time carries the search. The window is only exitSpread seconds before the ship's own exit.
// escapeLockedDeparture then moves the winner's tSOI to the correction burn's real exit time and searches
// the flight time once more there.
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

// Which case is this? On the ground (case 1): there is no orbit yet, so one is designed.
// In a bound orbit around the departure body (case 2): that orbit is used as it is.
// Inside one SOI (case 3): the ship's orbit is read by the cost function itself.
LOCAL orbitSpec IS 0.
LOCAL shipInParkingOrbit IS FALSE.
LOCAL launchLatitude IS 0.
LOCAL designAltitude IS parkingAltitude.

IF errorCode = "None" AND NOT sameSOI {
	IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
		// SHIP:LATITUDE on the ground is the launch site's latitude - but only if the ship is
		// actually on the departure body.
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
			IF destinationVessel:ISTYPE("Vessel") {
				// Captured into the destination vessel's own orbit size: its semi-major axis (the distance from the
				// moon's centre, for a vessel that is not on a closed orbit).
				SET captureAltitude TO orbitSizeRadius(destinationVessel, toOrbitable) - toOrbitable:RADIUS.
				PRINT destinationVessel:NAME + " orbits " + toOrbitable:NAME + ": capturing at its orbit size, " + ROUND(captureAltitude / 1000, 1) + " km up.".
			} ELSE {
				// The default: 15 km up with no atmosphere, 5 km above the top of one.
				SET captureAltitude TO 15000.
				IF toOrbitable:ATM:EXISTS SET captureAltitude TO toOrbitable:ATM:HEIGHT + 5000.
			}
		}
		SET captureRadius TO toOrbitable:RADIUS + captureAltitude.
	}

	IF debug {
		debugLogValues("Setup", LEXICON("solver", solverType, "captureRadius", captureRadius, "shipInParkingOrbit", shipInParkingOrbit,
			"launchLatitude", launchLatitude, "designAltitude", designAltitude)).
		debugLogValues("Window", window).
		IF orbitSpec:ISTYPE("Lexicon") debugLogValues("Orbit spec", orbitSpec).
	}

	// Between bodies, the coarse stages (the grid, then the hill climbs) use a quick ejection search
	// (24 burn points instead of 48, fewer polish steps, a lighter exact check - see ejectionPrecision
	// for its measured accuracy). The winner is then re-priced with the full one, and that is what
	// gets reported. Inside one SOI there is no ejection search, so one delegate does it all.
	LOCAL quickDelegate IS 0.
	LOCAL fullDelegate IS 0.
	IF sameSOI {
		PRINT fromOrbitable:NAME + " -> " + toOrbitable:NAME + " (same SOI).".
		PRINT "Window " + timeToString(window["windowLength"]) + ", " + window["samplesPerWindow"] + " departures each.".
		SET quickDelegate TO bindSameSOIDeltaV(fromOrbitable, toOrbitable, solverType, captureRadius, window["startTime"]).
		SET fullDelegate TO quickDelegate.
	} ELSE {
		PRINT fromOrbitable:NAME + " -> " + toOrbitable:NAME + " (around " + window["sunBody"]:NAME + ").".
		SET quickDelegate TO bindTransferDeltaV(fromOrbitable, toOrbitable, window["sunBody"], solverType, orbitSpec, captureRadius, ejectionPrecision("quick")).
		SET fullDelegate TO bindTransferDeltaV(fromOrbitable, toOrbitable, window["sunBody"], solverType, orbitSpec, captureRadius, ejectionPrecision("full")).
	}

	// Coarse grid over the whole search window. Only benefits from the Lambert warm-start
	// seed here: hillClimb2D below always calls its delegate with exactly two arguments, so
	// seed falls back to its default on every evaluation during the refinement pass.
	LOCAL grid IS porkchopGrid(quickDelegate, window).
	PRINT "Grid: " + grid["totalCells"] + " cells.".
	PRINT motionTypeSummary(grid, TRUE).
	FOR reasonLine IN failureReasonLines(grid) {
		PRINT "Failed - " + reasonLine.
	}

	// The best coarse cell in each window is what gets refined.
	LOCAL coarseCandidates IS porkchopBestPerBand(grid).

	IF debug {
		writePorkchopCsv(grid, window, transferGridFile, solverType, fromOrbitable, toOrbitable).
		debugFlush().
		debugLogValues("Coarse grid", LEXICON("cells", grid["totalCells"], "motionTypes", motionTypeSummary(grid), "failureReasons", grid["failureReasonCounts"],
			"minDeltaV", grid["minDeltaV"]["value"], "minDepartureTime", grid["minDeltaV"]["departureTime"],
			"minTimeOfFlight", grid["minDeltaV"]["timeOfFlight"], "gameSeconds", grid["duration"], "realSeconds", grid["realDuration"],
			"csv", transferGridFile)).
		FOR band IN coarseCandidates:KEYS {
			debugLogValues("Best coarse cell, window " + band, coarseCandidates[band]).
		}
	}

	// --- Refine each band's best coarse point: hill climb, then Newton steps ---
	// Step sizes are in seconds: the hill climb starts at the coarse grid's own spacing on each axis
	// (departure spacing is a fraction of the window, TOF spacing a fraction of the Hohmann
	// time). It prices 8 neighbours per iteration and only halves its step when none improves, so its
	// long tail of halvings is the expensive part. It is therefore stopped at 1/8 of the grid spacing
	// (hillClimbRatio = 3 halvings) and finished with two Newton steps (newtonRefine2D), which fit the
	// local bowl and jump to its bottom: fewer evaluations and a more precise minimum. (The exact-timing
	// stage re-optimizes tSOI afterwards in any case.)
	LOCAL hillClimbRatio IS 3.
	LOCAL bestOverall IS LEXICON("finalValue", invalidDeltaV).
	FOR band IN coarseCandidates:KEYS {
		PRINT "Refining window " + band + ".".
		LOCAL seed IS coarseCandidates[band].
		LOCAL climbed IS hillClimb2D(quickDelegate,			// already-bound delegate
			seed["departureTime"], seed["flightTime"],		// initial guesses, from the coarse pass - both absolute (seconds)
			window["departureStep"], window["tofStep"],		// initial step size, in seconds
			"", 20, hillClimbRatio).						// log, iterationMax, smallestStepRatio
		LOCAL refined IS newtonRefine2D(quickDelegate, climbed["finalGuess1"], climbed["finalGuess2"], climbed["finalValue"],
			window["departureStep"] / 2 ^ hillClimbRatio, window["tofStep"] / 2 ^ hillClimbRatio, 2).
		PRINT "  " + climbed["iteration"] + " climb steps + " + refined["steps"] + " Newton steps.".
		IF debug {
			debugLogValues("Hill climb, window " + band, climbed).
			debugLogValues("Newton refinement, window " + band, refined).
		}
		IF refined["finalValue"] < bestOverall["finalValue"] SET bestOverall TO refined.
	}

	IF bestOverall["finalValue"] >= invalidDeltaV {
		SET errorCode TO "No valid transfer was found in the search window.".
	} ELSE {
		// finalGuess1 is an absolute UT (seconds) - the SOI exit time, tSOI (case 3: the burn time);
		// finalGuess2 is an absolute flight duration (seconds).
		LOCAL reportTSOI IS bestOverall["finalGuess1"].
		LOCAL reportTimeOfFlight IS bestOverall["finalGuess2"].
		LOCAL reportStats IS LEXICON().
		// Re-price the winner with the full ejection search - the hill climb only saw the quick one.
		LOCAL reportDV IS fullDelegate(reportTSOI, reportTimeOfFlight, LEXICON(), reportStats).
		LOCAL soiProblems IS 0.
		IF debug {
			debugLogValues("Winner", LEXICON("departureTime", reportTSOI, "flightTime", reportTimeOfFlight, "deltaV", reportDV)).
			debugLogValues("Full-precision pricing of the winner", reportStats).
		}

		IF sameSOI {
			// Case 3: the burn is at the departure time itself.
			LOCAL departure IS reportStats["Ejection"].
			LOCAL nodeResult IS addEjectionNode(departure).
			IF debug debugLogValues("Node (same SOI)", nodeResult).
			PRINT "Node set: burn in " + timeToString(departure["burnUT"] - TIME:SECONDS) + ", " + ROUND(departure["deltaV"], 1) + " m/s.".
			PRINT "  pro " + ROUND(nodeResult["prograde"], 1) + ", norm " + ROUND(nodeResult["normal"], 1) + ", rad " + ROUND(nodeResult["radial"], 1) + " m/s.".
			IF NOT nodeResult["verified"] {
				PRINT "WARNING: node dV off by " + ROUND(nodeResult["nodeError"], 2) + " m/s.".
			}
			SET soiProblems TO reportSOIPath(fromOrbitable, toOrbitable, sameSOI).
		} ELSE IF shipInParkingOrbit OR shipEscaping {
			LOCAL timed IS 0.
			IF shipEscaping {
				// An escape orbit does not repeat, so there is no burn phase to lock to. Every price in the
				// search was for the cheapest correction burn whenever it exits, so what is left is to move
				// tSOI to the exit time that burn really has and price again.
				PRINT "Moving the departure to the correction burn's exit time.".
				SET timed TO escapeLockedDeparture(fromOrbitable, toOrbitable, window["sunBody"], solverType, orbitSpec, captureRadius,
					reportTSOI, reportTimeOfFlight).
				PRINT "Exit time lock: " + timed["passes"] + " passes, " + ROUND(timed["deltaV"], 1) + " m/s.".
			} ELSE {
				// The search priced the best burn point anywhere in the orbit. The orbit repeats every
				// period, so the cheapest burn the ship can really make is that same point at the repeat
				// nearest the grid's departure: lock tSOI to the best burn phase (burn time + transit time,
				// shifted by whole periods), recompute Lambert there, and repeat until it settles.
				PRINT "Locking to the best burn phase.".
				SET timed TO phaseLockedDeparture(fromOrbitable, toOrbitable, window["sunBody"], solverType, orbitSpec, captureRadius,
					reportTSOI, reportTimeOfFlight, TIME:SECONDS + minimumBurnLead).
				PRINT "Phase lock: " + timed["passes"] + " passes. Any phase " + ROUND(timed["phaseFreeDeltaV"], 1) +
					" m/s, timed " + ROUND(timed["deltaV"], 1) + " m/s.".
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
			} ELSE {
				IF shipEscaping PRINT "No correction burn on this escape orbit reaches it: no node.".
				ELSE PRINT "No burn in this orbit reaches it: no node.".
			}
		} ELSE {
			// Case 1: no real orbit to check a plane mismatch against, so report the parking
			// orbit that was designed for the winning transfer: the minimum-inclination plane
			// that contains the departure direction, raised to the launch site's latitude if
			// that is the more restrictive floor (a direct-ascent launch can't reach an
			// inclination below its own latitude without a dogleg).
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

			// Save the plan on the ship's own disk (volume 1, never the archive) for a launch script to read
			// back with READJSON. The ejection burn leaves the parking orbit one transit time before the
			// ship crosses the SOI edge at tSOI. In the closed-form case (the designed plane contains the exit
			// direction) that is a tangential burn at the orbit's own radius, so the hyperbola is rebuilt
			// here from the orbit radius and the excess speed; otherwise the search result already has it.
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
				"solverType", solverType,
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
	}
}

IF errorCode <> "None" SET loopMessage TO "Error: " + errorCode.
IF debug {
	debugLogValues("Result", LEXICON("errorCode", errorCode, "loopMessage", loopMessage)).
	debugFlush().
}
PRINT "Complete!".
