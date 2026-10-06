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
//      orbit. Cases 2 and 3: addEjectionNode adds the maneuver node (radial + normal + prograde).
//
// "tSOI" below is the moment the ship leaves the departure body's sphere of influence - the
// departure time Lambert sees. The ejection burn itself happens earlier, by the hyperbolic
// transit time from the burn to the SOI edge.
//
// PARAMETERs:
//   destinationName  - the destination: a body, or a vessel (a vessel wins a name clash)
//   startOffset      - s from now to the start of the search window (>= 30)
//   departureWindows - how many departure windows to search. Between bodies a window is a synodic
//                      period; in the same SOI it is a synodic period or four ship orbits, whichever is shorter
//   samplesPerWindow - departure times sampled in each window; the grid covers
//                      departureWindows x samplesPerWindow departure times in all. -1 (the default) chooses:
//                      4 between bodies, 12 per ship orbit in the same SOI
//   tofSamples       - flight times sampled (1 to 4 times the Hohmann time). -1 (the default) chooses:
//                      5 between bodies, 7 in the same SOI
//   sourceName       - "" (the default) takes the source from where the ship is. Otherwise the source to
//                      use instead: it must orbit the same body as the destination, and the ship must be
//                      it or be in orbit around it
//   parkingAltitude  - m, case 1 only: altitude of the parking orbit to design. -1 (the default) chooses
//                      50 km, or 30 km above the atmosphere if there is one.
//   captureAltitude  - m above the destination's surface to capture into a circular orbit.
//                      -1 (the default) prices only matching the arrival excess speed.
// ============================================================================

PARAMETER destinationName IS "Minmus".
PARAMETER startOffset IS 120.
PARAMETER departureWindows IS 1.
PARAMETER samplesPerWindow IS -1.
PARAMETER tofSamples IS -1.
PARAMETER sourceName IS "".
PARAMETER parkingAltitude IS -1.
PARAMETER captureAltitude IS -1.

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
	} ELSE IF key = "finalguess1" {
		SET unit TO "s (UT)".
	} ELSE IF key = "finalguess2" {
		SET unit TO "s".
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
	LOCAL line IS quote + section + quote + "," + quote + name + quote + "," + quote + value:TOSTRING + quote + "," + quote + debugUnits(section, name, value) + quote.
	IF transferGridWritten {
		LOG line TO transferGridFile.
	} ELSE {
		transferPendingLog:ADD(line).
	}
}

// Writes the held-back rows after whatever the file holds, and writes straight to it from then on.
FUNCTION debugFlush {
	IF transferGridWritten RETURN.
	SET transferGridWritten TO TRUE.
	LOG "" TO transferGridFile.
	LOG "Section,Name,Value,Units" TO transferGridFile.
	FOR line IN transferPendingLog {
		LOG line TO transferGridFile.
	}
	transferPendingLog:CLEAR().
}

// Adds a lexicon's contents, one row per key. A lexicon inside it is listed one level deep.
FUNCTION debugLogValues {
	PARAMETER section.
	PARAMETER data.

	FOR dataKey IN data:KEYS {
		LOCAL dataValue IS data[dataKey].
		IF dataValue:ISTYPE("Lexicon") {
			FOR innerKey IN dataValue:KEYS {
				debugLine(section, dataKey + "." + innerKey, dataValue[innerKey]).
			}
		} ELSE {
			debugLine(section, dataKey, dataValue).
		}
	}
}
IF debug {
	IF EXISTS(transferGridFile) DELETEPATH(transferGridFile).
	debugLine("Run", "start", "UT " + TIME:SECONDS + ", " + SHIP:NAME + " in " + SHIP:BODY:NAME + "'s SOI, " + SHIP:STATUS).
	debugLogValues("Parameters", LEXICON("destinationName", destinationName, "startOffset", startOffset, "departureWindows", departureWindows,
		"samplesPerWindow", samplesPerWindow, "tofSamples", tofSamples, "sourceName", sourceName,
		"parkingAltitude", parkingAltitude, "captureAltitude", captureAltitude)).
}
LOCAL errorCode IS "None".

LOCAL endpoints IS resolveTransferEndpoints(destinationName, sourceName).
SET errorCode TO endpoints["error"].
LOCAL fromOrbitable IS endpoints["from"].
LOCAL toOrbitable IS endpoints["to"].
LOCAL sameSOI IS endpoints["sameSOI"].
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

LOCAL window IS 0.
IF errorCode = "None" {
	SET window TO buildTransferWindow(endpoints, startOffset, departureWindows, samplesPerWindow, tofSamples, TRUE).
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
	} ELSE IF SHIP:BODY:NAME = fromOrbitable:NAME AND SHIP:ORBIT:ECCENTRICITY < 1 {
		SET orbitSpec TO orbitSpecFromVessel(SHIP).
		SET shipInParkingOrbit TO TRUE.
		PRINT "In orbit at " + fromOrbitable:NAME + ": using that orbit.".
	} ELSE {
		SET errorCode TO "The ship must be on the ground, or in a bound orbit around " + fromOrbitable:NAME + "!".
	}
}

IF errorCode = "None" {
	LOCAL solverType IS "Gauss".
	// Burns earlier than this (the next minute) can't be flown.
	LOCAL minimumBurnLead IS 60.

	LOCAL captureRadius IS 0.
	IF captureAltitude >= 0 AND toOrbitable:ISTYPE("Body") SET captureRadius TO toOrbitable:RADIUS + captureAltitude.

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

	// The best coarse cell in each window is what gets refined.
	LOCAL coarseCandidates IS porkchopBestPerBand(grid).

	IF debug {
		writePorkchopCsv(grid, window, transferGridFile, solverType, fromOrbitable, toOrbitable).
		debugFlush().
		debugLogValues("Coarse grid", LEXICON("cells", grid["totalCells"], "motionTypes", motionTypeSummary(grid),
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
		} ELSE IF shipInParkingOrbit {
			// The search priced the best burn point anywhere in the orbit. The orbit repeats every
			// period, so the cheapest burn the ship can really make is that same point at the repeat
			// nearest the grid's departure: lock tSOI to the best burn phase (burn time + transit time,
			// shifted by whole periods), recompute Lambert there, and repeat until it settles.
			PRINT "Locking to the best burn phase.".
			LOCAL timed IS phaseLockedDeparture(fromOrbitable, toOrbitable, window["sunBody"], solverType, orbitSpec, captureRadius,
				reportTSOI, reportTimeOfFlight, TIME:SECONDS + minimumBurnLead).
			PRINT "Phase lock: " + timed["passes"] + " passes. Any phase " + ROUND(timed["phaseFreeDeltaV"], 1) +
				" m/s, timed " + ROUND(timed["deltaV"], 1) + " m/s.".
			IF debug {
				debugLogValues("Phase lock", LEXICON("passes", timed["passes"], "phaseFreeDeltaV", timed["phaseFreeDeltaV"],
					"timedDeltaV", timed["deltaV"], "tSOI", timed["tSOI"])).
				IF timed["deltaV"] < invalidDeltaV debugLogValues("Timed pricing", timed["stats"]).
			}
			IF timed["deltaV"] < invalidDeltaV {
				SET reportTSOI TO timed["tSOI"].
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
			} ELSE {
				PRINT "No burn in this orbit reaches it: no node.".
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
		}

		PRINT "".
		IF sameSOI {
			PRINT "Departure " + distanceToString(reportStats["Ejection"]["deltaV"]) + "/s + arrival " + distanceToString(reportStats["Arrival Delta V"]) + "/s.".
		} ELSE {
			PRINT "Ejection " + distanceToString(reportStats["Ejection"]["deltaV"]) + "/s + arrival " + distanceToString(reportStats["Arrival Delta V"]) + "/s.".
		}
		PRINT "Complete".
		WAIT 0.5.

		SET loopMessage TO fromOrbitable:NAME + " -> " + toOrbitable:NAME + " " + ROUND(reportDV) + "m/s in " + durationToUnitString(reportTimeOfFlight).
	}
}

IF errorCode <> "None" SET loopMessage TO "Error: " + errorCode.
IF debug {
	debugLogValues("Result", LEXICON("errorCode", errorCode, "loopMessage", loopMessage)).
	debugFlush().
}
PRINT "Complete!".
