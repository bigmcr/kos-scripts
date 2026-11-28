@LAZYGLOBAL OFF.

// ============================================================================
// libraryTransfer.ks - delta-V of a transfer in KSP's patched conics, with the Lambert solvers and
// porkchop tools it is built on. Loaded after library.ks, which it depends on.
//
// The model:
//   - Lambert (around the common parent) gives the velocity the ship needs as it LEAVES the departure
//     body's SOI, at tSOI. Relative to the body that is vExit, the velocity at the SOI edge, not the
//     excess at infinity: vInfinity = SQRT(|vExit|^2 - 2*mu/soiRadius).
//   - The burn is earlier than tSOI, by the hyperbola's transit time to the SOI edge.
//   - Arrival is the velocity at the destination's SOI edge.
//
// The departure orbit is an "orbit spec":
//   "orbit"  - the ship's real orbit (orbitSpecFromVessel).
//   "design" - not launched (designSpec): a circular orbit designed per transfer.
//
// The ejection is priced two ways:
//   phase-free   - the cheapest burn point anywhere in one orbit. Smooth, so it suits searches.
//   exact timing - the burn point is dictated by tSOI; the cost repeats with the orbit period
//                  (see phaseLockedDeparture).
//
// Angles are degrees; times are seconds (UT where noted).
// ============================================================================

GLOBAL invalidDeltaV IS 1e15.

FUNCTION porkchopDeltaV {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER departureTime.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER planeNormal IS V(0,0,0).
	PARAMETER parkSMA IS 0.
	PARAMETER parkEccentricity IS 0.
	// Optional out-parameter: the winning arc's lexicon is copied into it key by key (reassigning the
	// parameter would not reach the caller). If neither arc converges, only "Motion Type" ("Failed") and
	// "Failure Reason" are set.
	PARAMETER statsOut IS LEXICON("v_1", V(0,0,0),
									"v_2", V(0,0,0),
									"Motion Type", "Failed",
									"Iterations", 0,
									"Final Value", 0,
									"r_1", V(0,0,0),
									"r_2", V(0,0,0),
									"mu", 0,
									"Short Way", FALSE).

	LOCAL shortStartSeed IS 0.5.
	IF seed:HASKEY("shortSeed") SET shortStartSeed TO seed["shortSeed"].
	LOCAL longStartSeed IS 0.5.
	IF seed:HASKEY("longSeed") SET longStartSeed TO seed["longSeed"].

	// The arc ends at the destination's position at arrival.
	LOCAL arrivalTime IS departureTime + timeOfFlight.
	LOCAL r_1 IS absolutePosition(fromBody, departureTime) - absolutePosition(sunBody, departureTime).
	LOCAL r_2 IS absolutePosition(toBody, arrivalTime) - absolutePosition(sunBody, arrivalTime).

	LOCAL fromBodyVelocity IS absoluteVelocity(fromBody, departureTime) - absoluteVelocity(sunBody, departureTime).
	LOCAL toBodyVelocity IS absoluteVelocity(toBody, arrivalTime) - absoluteVelocity(sunBody, arrivalTime).

	LOCAL bestTotalDV IS invalidDeltaV.
	LOCAL winningTrajectory IS 0.
	LOCAL failureReason IS "Flight time not positive".

	// guard against a nonsensical (non-positive) time of flight from an out-of-range guess
	IF timeOfFlight > 0 {
		LOCAL shortTrajectory IS lambertGooding(r_1, r_2, timeOfFlight, sunBody:MU, TRUE, shortStartSeed).
		LOCAL longTrajectory IS lambertGooding(r_1, r_2, timeOfFlight, sunBody:MU, FALSE, longStartSeed).
		
		SET failureReason TO "No convergence".
		IF shortTrajectory:HASKEY("Failure Reason") SET failureReason TO shortTrajectory["Failure Reason"].
		IF longTrajectory:HASKEY("Failure Reason") SET failureReason TO longTrajectory["Failure Reason"].

		IF shortTrajectory["Motion Type"] <> "Failed" {
			LOCAL vInfDepartureShort IS shortTrajectory["v_1"] - fromBodyVelocity.
			LOCAL mismatchShort IS 0.
			IF parkSMA <> 0 SET mismatchShort TO planeMismatchAngle(vInfDepartureShort, planeNormal).
			LOCAL departureDVShort IS 0.
			IF parkSMA <> 0 SET departureDVShort TO combinedDepartureDeltaV(vInfDepartureShort:MAG, mismatchShort, fromBody:MU, parkSMA, parkEccentricity).
			LOCAL arrivalDVShort IS (toBodyVelocity - shortTrajectory["v_2"]):MAG.
			LOCAL dvShort IS departureDVShort + arrivalDVShort.
			IF parkSMA = 0 SET dvShort TO vInfDepartureShort:MAG + arrivalDVShort.
			SET seed["shortSeed"] TO shortTrajectory["Final Value"].
			IF dvShort < bestTotalDV {
				SET bestTotalDV TO dvShort.
				SET winningTrajectory TO shortTrajectory.
			}
		}
		IF longTrajectory["Motion Type"] <> "Failed" {
			LOCAL vInfDepartureLong IS longTrajectory["v_1"] - fromBodyVelocity.
			LOCAL mismatchLong IS 0.
			IF parkSMA <> 0 SET mismatchLong TO planeMismatchAngle(vInfDepartureLong, planeNormal).
			LOCAL departureDVLong IS 0.
			IF parkSMA <> 0 SET departureDVLong TO combinedDepartureDeltaV(vInfDepartureLong:MAG, mismatchLong, fromBody:MU, parkSMA, parkEccentricity).
			LOCAL arrivalDVLong IS (toBodyVelocity - longTrajectory["v_2"]):MAG.
			LOCAL dvLong IS departureDVLong + arrivalDVLong.
			IF parkSMA = 0 SET dvLong TO vInfDepartureLong:MAG + arrivalDVLong.
			SET seed["longSeed"] TO longTrajectory["Final Value"].
			IF dvLong < bestTotalDV {
				SET bestTotalDV TO dvLong.
				SET winningTrajectory TO longTrajectory.
			}
		}
	}

	// Copy into the caller's statsOut (never reassign it).
	IF winningTrajectory:ISTYPE("Lexicon") {
		FOR statKey IN winningTrajectory:KEYS {
			SET statsOut[statKey] TO winningTrajectory[statKey].
		}
	} ELSE {
		SET statsOut["Motion Type"] TO "Failed".
		SET statsOut["Failure Reason"] TO failureReason.
	}

	RETURN bestTotalDV.
}

// The same as porkchopDeltaV, but with the arguments reordered so that BIND can
// fill in everything that is fixed for a whole search (bodies, parking orbit),
// leaving (departureTime, timeOfFlight, seed, statsOut) for the caller.
// Pass parkSMA = 0 for "no parking orbit" (bare point-mass dV).
FUNCTION porkchopDeltaVPlaneAware {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER planeNormal.
	PARAMETER parkSMA.
	PARAMETER parkEccentricity.
	PARAMETER departureTime.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER statsOut IS LEXICON().

	RETURN porkchopDeltaV(fromBody, toBody, sunBody, departureTime, timeOfFlight, seed, planeNormal, parkSMA, parkEccentricity, statsOut).
}

// Returns a delegate f(departureTime, timeOfFlight, seed, statsOut) (the last
// two optional) that returns total dV, with everything else bound.
// Omit the parking-orbit arguments for the
// bare point-mass cost.
FUNCTION bindPorkchopDeltaV {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER sunBody.
	PARAMETER planeNormal IS V(0, 0, 0).
	PARAMETER parkSMA IS 0.
	PARAMETER parkEccentricity IS 0.

	LOCAL bound IS porkchopDeltaVPlaneAware@.
	SET bound TO bound:BIND(fromOrbitable).
	SET bound TO bound:BIND(toOrbitable).
	SET bound TO bound:BIND(sunBody).
	SET bound TO bound:BIND(planeNormal).
	SET bound TO bound:BIND(parkSMA).
	SET bound TO bound:BIND(parkEccentricity).
	RETURN bound.
}

// Runs the grid search over a window from buildTransferWindow.
//   dvDelegate - f(departureTime, timeOfFlight, seed, statsOut) -> total dV
//   window     - from buildTransferWindow
// Cells are computed departure by departure, so the solver's seed (fresh per departure) carries across
// that departure's flight times. The grid returned has one row per flight time, longest first.
// The abort key (abortKeyPressed) is looked at before each departure: after it the grid holds only the
// departures already finished, possibly none.
// Returns a LEXICON:
//   "dv"               - LIST of rows (one per "timeOfFlights"), each a LIST of dV per "departureTimes"; failed cells hold invalidDeltaV
//   "timeOfFlights"    - flight time (s) of each row, descending
//   "departureTimes"   - departure UT of each column
//   "departureBands"   - which window (0, 1, ...) each column falls in
//   "minDeltaV"        - LEXICON("value", "departureTime", "timeOfFlight"), the best cell
//   "motionTypeCounts" - cells per motion type, including "Failed"
//   "winningWay", "transferAngle", "rejectedArcs" - rows like "dv": the winning arc's way round
//                        ("Short"/"Long"/"N/A"), its sweep angle (deg), and how many arcs the cell rejected
//   "failureReasonCounts" - failed cells per statsOut["Failure Reason"]
//   "totalCells", "startClock", "endClock", "duration" (game s), "realDuration" (real s)
FUNCTION porkchopGrid {
	PARAMETER dvDelegate.
	PARAMETER window.

	LOCAL startClock IS TIME:SECONDS.
	LOCAL realStartTime IS KUNIVERSE:REALWORLDTIME.

	LOCAL dvRows IS LIST().
	LOCAL timeOfFlights IS LIST().
	LOCAL departureTimes IS LIST().
	LOCAL departureBands IS LIST().
	LOCAL motionTypeCounts IS LEXICON("Ellipse", 0, "Parabola", 0, "Hyperbola", 0, "Failed", 0).
	LOCAL failureReasonCounts IS LEXICON().
	// Per cell, laid out like dvRows.
	LOCAL wayRows IS LIST().
	LOCAL angleRows IS LIST().
	LOCAL rejectedRows IS LIST().
	LOCAL totalCells IS 0.
	LOCAL minDeltaV IS LEXICON("value", invalidDeltaV, "departureTime", window["startTime"], "timeOfFlight", 0).

	// One empty row per flight time, longest first.
	FROM {LOCAL flightIndex IS window["timeOfFlights"]:LENGTH - 1.} UNTIL flightIndex < 0 STEP {SET flightIndex TO flightIndex - 1.} DO {
		dvRows:ADD(LIST()).
		wayRows:ADD(LIST()).
		angleRows:ADD(LIST()).
		rejectedRows:ADD(LIST()).
		timeOfFlights:ADD(window["timeOfFlights"][flightIndex]).
	}

	FOR departureTime IN window["departureTimes"] {
		IF abortKeyPressed() BREAK.
		LOCAL periodsSinceStart IS (departureTime - window["departureStart"]) / window["windowLength"].
		PRINT "Calculating departure " + ROUND(periodsSinceStart, 3) + " windows in.".
		departureTimes:ADD(departureTime).
		// A hair of tolerance for a departure exactly on a window boundary.
		departureBands:ADD(FLOOR(periodsSinceStart + 1e-9)).

		// Filled in by the delegate; fresh per departure, shared across this departure's TOF sweep.
		LOCAL seed IS LEXICON().

		LOCAL tofIndex IS 0.
		FOR timeOfFlight IN timeOfFlights {
			LOCAL statsOut IS LEXICON().
			LOCAL dV IS dvDelegate(departureTime, timeOfFlight, seed, statsOut).

			SET totalCells TO totalCells + 1.
			LOCAL cellType IS statsOut["Motion Type"].
			IF NOT motionTypeCounts:HASKEY(cellType) SET motionTypeCounts[cellType] TO 0.
			SET motionTypeCounts[cellType] TO motionTypeCounts[cellType] + 1.
			IF cellType = "Failed" {
				LOCAL failureReason IS "Unknown".
				IF statsOut:HASKEY("Failure Reason") AND statsOut["Failure Reason"] <> "" SET failureReason TO statsOut["Failure Reason"].
				IF NOT failureReasonCounts:HASKEY(failureReason) SET failureReasonCounts[failureReason] TO 0.
				SET failureReasonCounts[failureReason] TO failureReasonCounts[failureReason] + 1.
			}

			IF minDeltaV["value"] > dV {
				SET minDeltaV["value"] TO dV.
				SET minDeltaV["departureTime"] TO departureTime.
				SET minDeltaV["timeOfFlight"] TO timeOfFlight.
			}
			dvRows[tofIndex]:ADD(dV).
			LOCAL cellWay IS "N/A".
			LOCAL cellAngle IS "N/A".
			IF cellType <> "Failed" AND statsOut:HASKEY("r_1") {
				LOCAL separation IS VANG(statsOut["r_1"], statsOut["r_2"]).
				IF statsOut["Short Way"] {
					SET cellWay TO "Short".
					SET cellAngle TO ROUND(separation, 2).
				} ELSE {
					SET cellWay TO "Long".
					SET cellAngle TO ROUND(360 - separation, 2).
				}
			}
			LOCAL cellRejected IS 0.
			IF statsOut:HASKEY("Rejected Arcs") SET cellRejected TO statsOut["Rejected Arcs"].
			wayRows[tofIndex]:ADD(cellWay).
			angleRows[tofIndex]:ADD(cellAngle).
			rejectedRows[tofIndex]:ADD(cellRejected).

			SET tofIndex TO tofIndex + 1.
			WAIT 0.
		}
	}

	LOCAL endClock IS TIME:SECONDS.
	RETURN LEXICON("dv", dvRows,
					"timeOfFlights", timeOfFlights,
					"departureTimes", departureTimes,
					"departureBands", departureBands,
					"minDeltaV", minDeltaV,
					"motionTypeCounts", motionTypeCounts,
					"failureReasonCounts", failureReasonCounts,
					"winningWay", wayRows,
					"transferAngle", angleRows,
					"rejectedArcs", rejectedRows,
					"totalCells", totalCells,
					"startClock", startClock,
					"endClock", endClock,
					"duration", endClock - startClock,
					"realDuration", KUNIVERSE:REALWORLDTIME - realStartTime).
}

// One line of a grid's motion-type counts (hideEmptyTypes leaves out zero counts).
FUNCTION motionTypeSummary {
	PARAMETER grid.
	PARAMETER hideEmptyTypes IS FALSE.

	LOCAL summary IS "".
	FOR typeName IN grid["motionTypeCounts"]:KEYS {
		LOCAL typeCount IS grid["motionTypeCounts"][typeName].
		IF NOT hideEmptyTypes OR typeCount <> 0 {
			SET summary TO summary + typeName + ": " + typeCount + " (" + ROUND(typeCount / MAX(grid["totalCells"], 1) * 100, 2) + "%)   ".
		}
	}
	RETURN summary.
}

// One line per failure reason of a grid (count and share of all cells), most common first.
FUNCTION failureReasonLines {
	PARAMETER grid.

	LOCAL remaining IS LEXICON().
	FOR reason IN grid["failureReasonCounts"]:KEYS {
		SET remaining[reason] TO grid["failureReasonCounts"][reason].
	}
	LOCAL lines IS LIST().
	UNTIL remaining:LENGTH = 0 {
		LOCAL topReason IS remaining:KEYS[0].
		FOR reason IN remaining:KEYS {
			IF remaining[reason] > remaining[topReason] SET topReason TO reason.
		}
		lines:ADD(topReason + ": " + remaining[topReason] + " (" + ROUND(remaining[topReason] / MAX(grid["totalCells"], 1) * 100, 2) + "%)").
		remaining:REMOVE(topReason).
	}
	RETURN lines.
}

// The lowest-dV cell in each departure window of a grid ("departureBands"). Returns LEXICON band ->
// LEXICON("dv", "departureTime", "flightTime").
FUNCTION porkchopBestPerBand {
	PARAMETER grid.

	LOCAL best IS LEXICON().
	FROM {LOCAL col IS 0.} UNTIL col >= grid["departureTimes"]:LENGTH STEP {SET col TO col + 1.} DO {
		LOCAL band IS grid["departureBands"][col].
		FROM {LOCAL row IS 0.} UNTIL row >= grid["timeOfFlights"]:LENGTH STEP {SET row TO row + 1.} DO {
			LOCAL dV IS grid["dv"][row][col].
			IF NOT best:HASKEY(band) OR dV < best[band]["dv"] {
				IF NOT best:HASKEY(band) best:ADD(band, LEXICON()).
				SET best[band]["dv"] TO dV.
				SET best[band]["departureTime"] TO grid["departureTimes"][col].
				SET best[band]["flightTime"] TO grid["timeOfFlights"][row].
			}
		}
	}
	RETURN best.
}

// Writes one more grid of cell values to a CSV, in the layout of the cost grid: a title line, a header
// row of departure times, then one row per flight time (longest first) with one value per departure.
//   cellRows - LIST of rows (one per entry of grid["timeOfFlights"]), each a LIST of values
FUNCTION writePorkchopBlock {
	PARAMETER fileName.
	PARAMETER title.
	PARAMETER grid.
	PARAMETER window.
	PARAMETER cellRows.

	LOG "" TO fileName.
	LOG title TO fileName.
	LOCAL headerRow IS "TOF (" + window["tofUnit"] + ") \ Departure (" + window["departureUnit"] + ")".
	FOR departureTime IN grid["departureTimes"] {
		SET headerRow TO headerRow + "," + ROUND((departureTime - window["startTime"]) / window["departureUnitSeconds"], 2).
	}
	LOG headerRow TO fileName.
	FOR rowIndex IN RANGE(0, cellRows:LENGTH) {
		LOCAL rowString IS ROUND(grid["timeOfFlights"][rowIndex] / window["tofUnitSeconds"], 2):TOSTRING.
		FOR cellValue IN cellRows[rowIndex] {
			SET rowString TO rowString + "," + cellValue.
		}
		LOG rowString TO fileName.
	}
}

// Writes a grid to a CSV: the cost grid (flight time down, departure across, "N/A" for failed cells), the
// search parameters, the best cell, the motion-type and failure-reason counts, and three more grids.
// Replaces an existing file. Returns FALSE, writing nothing, if the archive is not reachable.
FUNCTION writePorkchopCsv {
	PARAMETER grid.
	PARAMETER window.
	PARAMETER fileName.
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.

	IF NOT connectionToKSC() RETURN FALSE.
	IF EXISTS(fileName) DELETEPATH(fileName).

	LOCAL synodicPeriod IS window["synodicPeriod"].
	LOCAL hohmannTime IS window["hohmannTime"].
	LOCAL startTime IS window["startTime"].
	LOCAL minDeltaV IS grid["minDeltaV"].

	LOCAL headerRow IS "TOF (" + window["tofUnit"] + ") \ Departure (" + window["departureUnit"] + ")".
	FOR departureTime IN grid["departureTimes"] {
		SET headerRow TO headerRow + "," + ROUND((departureTime - startTime) / window["departureUnitSeconds"], 2).
	}
	LOG headerRow TO fileName.

	FOR rowIndex IN RANGE(0, grid["dv"]:LENGTH) {
		LOCAL rowString IS ROUND(grid["timeOfFlights"][rowIndex] / window["tofUnitSeconds"], 2):TOSTRING.
		FOR cellValue IN grid["dv"][rowIndex] {
			IF cellValue = invalidDeltaV SET rowString TO rowString + ",N/A".
			ELSE SET rowString TO rowString + "," + cellValue.
		}
		LOG rowString TO fileName.
	}

	LOG "" TO fileName.
	LOG "Solver:,Gooding" TO fileName.
	LOG "Calculation Start Time:," + grid["startClock"] TO fileName.
	LOG "End Time:," + grid["endClock"] TO fileName.
	LOG "Duration:," + grid["duration"] + "," + timeToString(grid["duration"]) TO fileName.
	LOG "Real-World Duration:," + grid["realDuration"] + "," + realTimeToString(grid["realDuration"]) TO fileName.
	IF synodicPeriod > 0 LOG "Synodic Period:," + synodicPeriod + "," + timeToString(synodicPeriod) TO fileName.
	ELSE LOG "Synodic Period:,N/A,an escape orbit has no period" TO fileName.
	LOG "Hohmann Transfer Time:," + hohmannTime + "," + timeToString(hohmannTime) TO fileName.
	LOG "" TO fileName.

	LOG "Search Parameters:,s UT,duration" TO fileName.
	LOG "Departure Time Start:," + window["departureStart"] + "," + timeToString(window["departureStart"]) TO fileName.
	LOG "Departure Time End:," + window["departureEnd"] + "," + timeToString(window["departureEnd"]) TO fileName.
	LOG "Departure Time Step:," + window["departureStep"] + "," + timeToString(window["departureStep"]) TO fileName.
	LOG "Departure Samples:," + window["departureSamples"] TO fileName.

	LOG "Time of Flight Start:," + window["tofStart"] + "," + timeToString(window["tofStart"]) TO fileName.
	LOG "Time of Flight End:," + window["tofEnd"] + "," + timeToString(window["tofEnd"]) TO fileName.
	LOG "Time of Flight Step:," + window["tofStep"] + "," + timeToString(window["tofStep"]) TO fileName.
	LOG "Time of Flight Samples:," + window["tofSamples"] TO fileName.
	LOG "From Body," + fromOrbitable:NAME TO fileName.
	LOG "To Body," + toOrbitable:NAME TO fileName.

	LOG "" TO fileName.
	LOG "minDeltaV," + minDeltaV["value"] + ",m/s" TO fileName.
	LOG "Min Delta V Departure," + minDeltaV["departureTime"] + "," + timeToString(minDeltaV["departureTime"]) TO fileName.
	LOG "Min Delta V Time of Flight," + minDeltaV["timeOfFlight"] + "," + timeToString(minDeltaV["timeOfFlight"]) TO fileName.

	// "Failed" cells are the "N/A" cells in the grid above.
	LOG "" TO fileName.
	LOG "Motion Type Breakdown:,Count,Percent" TO fileName.
	FOR typeName IN grid["motionTypeCounts"]:KEYS {
		LOCAL typeCount IS grid["motionTypeCounts"][typeName].
		LOG typeName + "," + typeCount + "," + ROUND(typeCount / MAX(grid["totalCells"], 1) * 100, 2) + "%" TO fileName.
	}
	LOG "Total," + grid["totalCells"] + ",100%" TO fileName.

	// Why the failed cells failed.
	LOG "" TO fileName.
	LOG "Failure Reason Breakdown:,Count,Percent" TO fileName.
	FOR reason IN grid["failureReasonCounts"]:KEYS {
		LOCAL reasonCount IS grid["failureReasonCounts"][reason].
		LOG reason + "," + reasonCount + "," + ROUND(reasonCount / MAX(grid["totalCells"], 1) * 100, 2) + "%" TO fileName.
	}

	// Three more grids, laid out like the cost grid.
	writePorkchopBlock(fileName, "Winning way round (Short or Long; N/A = no valid arc)", grid, window, grid["winningWay"]).
	writePorkchopBlock(fileName, "Winning arc sweep angle (deg; N/A = no valid arc)", grid, window, grid["transferAngle"]).
	writePorkchopBlock(fileName, "Arcs rejected for hitting the central body or leaving its SOI (count)", grid, window, grid["rejectedArcs"]).
	RETURN TRUE.
}

// ----------------------------------------------------------------------------
// solveBurnAtPoint
// The velocity (relative to the body) a vessel must have at burnPosition to leave on the hyperbola whose
// asymptote velocity is vInfinity (direction and magnitude). The burn need not be tangential, at periapsis
// or in the parking plane: the plane is fixed by burnPosition and vInfinity, the speed by energy.
// With D the in-plane angle from burnPosition to the asymptote direction:
//     vt^2 - |vInf| * SIN(D) * vt - (mu/r) * (1 - COS(D)) = 0   (positive root)
//     vr   = |vInf| * COS(D) + mu * SIN(D) / (r * vt)
// D can go the short way round or the long way (360 minus it); each is a valid hyperbola.
//   tangentHint - the plane contains this if vInfinity is (anti)parallel to burnPosition
//   senses      - which sweep directions to return, in order: 1 = short way, 2 = long way
// Returns a LIST of velocity vectors, one per sense.
FUNCTION solveBurnAtPoint {
	PARAMETER burnPosition.
	PARAMETER vInfinity.
	PARAMETER mu.
	PARAMETER tangentHint IS V(0, 0, 0).
	PARAMETER senses IS LIST(1, 2).

	LOCAL burnRadius IS burnPosition:MAG.
	LOCAL radialUnit IS burnPosition / burnRadius.
	LOCAL vInfMag IS vInfinity:MAG.
	LOCAL vInfUnit IS vInfinity / vInfMag.
	LOCAL angleToAsymptote IS VANG(radialUnit, vInfUnit).

	// In-plane unit vector perpendicular to radialUnit, on the side vInfinity lies.
	LOCAL sideUnit IS vInfUnit - radialUnit * VDOT(vInfUnit, radialUnit).
	IF sideUnit:MAG < 1e-6 SET sideUnit TO tangentHint - radialUnit * VDOT(tangentHint, radialUnit).
	IF sideUnit:MAG < 1e-9 SET sideUnit TO VCRS(radialUnit, V(0, 1, 0)).
	SET sideUnit TO sideUnit:NORMALIZED.

	LOCAL options IS LIST().
	FOR sense IN senses {
		LOCAL sweepAngle IS angleToAsymptote.
		LOCAL sweepDirection IS sideUnit.
		IF sense = 2 {
			SET sweepAngle TO 360 - angleToAsymptote.
			SET sweepDirection TO -sideUnit.
		}
		LOCAL sinSweep IS SIN(sweepAngle).
		LOCAL cosSweep IS COS(sweepAngle).
		LOCAL tangentialSpeed IS (vInfMag * sinSweep + SQRT((vInfMag * sinSweep) ^ 2 + 4 * mu * (1 - cosSweep) / burnRadius)) / 2.
		// A purely radial burn (sweep 0): the radial speed comes from energy.
		LOCAL radialSpeed IS SQRT(vInfMag ^ 2 + 2 * mu / burnRadius).
		IF tangentialSpeed > 1e-6 SET radialSpeed TO vInfMag * cosSweep + mu * sinSweep / (burnRadius * tangentialSpeed).
		options:ADD(radialUnit * radialSpeed + sweepDirection * tangentialSpeed).
	}
	RETURN options.
}

// Angle between a v_infinity vector's direction and a parking orbit's plane.
// 0 = v_infinity lies exactly in the plane; 90 = v_infinity is normal to the plane.
FUNCTION planeMismatchAngle {
	PARAMETER vInfinityVector.
	PARAMETER planeNormal.
	RETURN 90 - VANG(vInfinityVector, planeNormal).
}

// Departure delta-V of one burn at the parking orbit's periapsis that reaches escape energy and
// absorbs the plane change (law of cosines).
FUNCTION combinedDepartureDeltaV {
	PARAMETER vInfinityMag.
	PARAMETER mismatchAngleDeg.
	PARAMETER mu.
	PARAMETER parkSMA.
	PARAMETER parkEccentricity IS 0.

	LOCAL rBurn IS parkSMA * (1 - parkEccentricity).
	LOCAL vPark IS SQRT(mu * (2 / rBurn - 1 / parkSMA)).
	LOCAL vHyperbola IS SQRT(vInfinityMag ^ 2 + 2 * mu / rBurn).
	RETURN SQRT(vPark ^ 2 + vHyperbola ^ 2 - 2 * vPark * vHyperbola * COS(mismatchAngleDeg)).
}

// Lambert's problem by Gooding's method (Celestial Mechanics 48 (1990) 145-165). The path parameter x is
// bounded (-1 to 1 for an ellipse, above 1 for a hyperbola), so the root is bracketed and solved with
// findZeroBrent.
// departureVector/arrivalVector are positions relative to the central body; shortWay picks the arc that
// sweeps under 180 degrees.
FUNCTION lambertGooding {
	PARAMETER departureVector.
	PARAMETER arrivalVector.
	PARAMETER timeOfFlight.
	PARAMETER mu.
	PARAMETER shortWay IS TRUE.
	PARAMETER xGuess IS "default".
	PARAMETER tolerance IS 5e-7.
	PARAMETER boundaryTolerance IS 5 * tolerance.

	LOCAL sqrtMu IS SQRT(mu).
	// The transfer angle: the angle between the two vectors the short way, 360 minus it the long way.
	LOCAL transferAngle IS VANG(departureVector, arrivalVector).
	IF NOT shortWay SET transferAngle TO 360 - transferAngle.

	LOCAL departureMag IS departureVector:MAG.
	LOCAL arrivalMag IS arrivalVector:MAG.
	LOCAL departureUnit IS departureVector / departureMag.
	LOCAL arrivalUnit IS arrivalVector / arrivalMag.
	LOCAL chordVector IS arrivalVector - departureVector.
	LOCAL chordLength IS chordVector:MAG.
	LOCAL chordUnit IS chordVector / chordLength.
	LOCAL perimeterSum IS departureMag + arrivalMag + chordLength.
	LOCAL perimeterDiff IS perimeterSum - 2 * chordLength.
	LOCAL invSqrtPerimeterSum IS 1 / SQRT(perimeterSum).
	LOCAL invSqrtPerimeterDiff IS 1 / SQRT(perimeterDiff).

	LOCAL normalizedTime IS 4 * timeOfFlight * sqrtMu / perimeterSum ^ 1.5.
	LOCAL pathSign IS 0.
	IF SIN(transferAngle) < 0 SET pathSign TO -1.
	IF SIN(transferAngle) > 0 SET pathSign TO 1.
	LOCAL pathParameter IS pathSign * SQRT(perimeterDiff / perimeterSum).
	LOCAL pathParameterSquared IS perimeterDiff / perimeterSum.
	LOCAL twoPathParameterCubed IS 2 * pathParameterSquared * pathParameter.
	LOCAL oneMinusPathParameterSquared IS 2 * chordLength / perimeterSum. // = 1 - pathParameter^2

	LOCAL parabolicTime IS (2 - twoPathParameterCubed) / 3.
	LOCAL minEnergyTime IS ARCCOS(pathParameter) * CONSTANT:DegToRad + pathParameter * SQRT(oneMinusPathParameterSquared).

	// Which regime this transfer falls in.
	LOCAL transferType IS 0. // 0 = ellipse, 1 = parabola, 2 = hyperbola
	IF ABS(normalizedTime - parabolicTime) < boundaryTolerance {
		SET transferType TO 1.
	} ELSE IF normalizedTime < parabolicTime {
		SET transferType TO 2.
	}

	LOCAL x IS 0.
	LOCAL z IS 0.
	LOCAL converged IS TRUE.
	LOCAL failReason IS "".

	IF transferType = 1 {
		// Exact parabola - a closed form, no root-finding needed at all.
		SET x TO 1.
		SET z TO 1. // sqrt(pathParameterSquared + oneMinusPathParameterSquared) = sqrt(1)
	} ELSE {
		// Gooding's analytic first guess seeds the bracket search, unless xGuess was given.
		IF xGuess = "default" {
			IF normalizedTime < minEnergyTime {
				SET xGuess TO minEnergyTime * (minEnergyTime / normalizedTime - 1).
			} ELSE {
				SET xGuess TO SQRT((normalizedTime - minEnergyTime) / (normalizedTime + 0.5 * minEnergyTime)).
			}
		}

		LOCAL domainLow IS -1 + boundaryTolerance.
		LOCAL domainHigh IS 1 - boundaryTolerance.
		IF transferType = 2 {
			SET domainLow TO 1 + boundaryTolerance.
			SET domainHigh TO 1e8. // generously far beyond any physically sensible transfer
		}

		LOCAL residualDelegate IS lambertTimeResidual@.
		SET residualDelegate TO residualDelegate:BIND(pathParameter).
		SET residualDelegate TO residualDelegate:BIND(pathParameterSquared).
		SET residualDelegate TO residualDelegate:BIND(oneMinusPathParameterSquared).
		SET residualDelegate TO residualDelegate:BIND(parabolicTime).
		SET residualDelegate TO residualDelegate:BIND(boundaryTolerance).
		SET residualDelegate TO residualDelegate:BIND(normalizedTime).

		LOCAL initialStep IS MAX(ABS(xGuess) * 0.5, boundaryTolerance * 10).
		LOCAL bracket IS bracketAroundGuess(residualDelegate, xGuess, domainLow, domainHigh, initialStep).

		// No sign change found: there is nothing valid to give findZeroBrent.
		IF bracket["low"] = bracket["high"] {
			SET converged TO FALSE.
			SET failReason TO "No bracket for root".
		}

		SET x TO findZeroBrent(residualDelegate, bracket["low"], bracket["high"], tolerance).
		SET z TO SQRT(pathParameterSquared * x * x + oneMinusPathParameterSquared).

		// findZeroBrent stops on bracket width, so check that x really solves the time equation.
		IF ABS(residualDelegate(x)) > boundaryTolerance {
			SET converged TO FALSE.
			IF failReason = "" SET failReason TO "Root not converged".
		}
	}

	LOCAL zVelocityFactor IS pathSign * z * invSqrtPerimeterDiff.
	LOCAL xVelocityFactor IS x * invSqrtPerimeterSum.
	LOCAL chordVelocity IS sqrtMu * (zVelocityFactor + xVelocityFactor) * chordUnit.
	LOCAL radialVelocityScale IS sqrtMu * (zVelocityFactor - xVelocityFactor).

	LOCAL motionType IS "Ellipse".
	IF transferType = 1 SET motionType TO "Parabola".
	IF transferType = 2 SET motionType TO "Hyperbola".
	IF NOT converged SET motionType TO "Failed".

	LOCAL v1Result IS chordVelocity + radialVelocityScale * departureUnit.
	LOCAL v2Result IS chordVelocity - radialVelocityScale * arrivalUnit.
	IF NOT converged {
		SET v1Result TO V(0, 0, 0).
		SET v2Result TO V(0, 0, 0).
	}

	RETURN LEXICON("v_1", v1Result,
					"v_2", v2Result,
					"Failure Reason", failReason,
					"Motion Type", motionType,
					"Iterations", 0,
					"Final Value", x,
					"r_1", departureVector,
					"r_2", arrivalVector,
					"mu", mu,
					"Short Way", shortWay).
}

// Normalized-time residual T(x) - normalizedTime; its root is the x that solves the Lambert problem.
// x is last so that everything else can be BIND-ed (see lambertGooding).
FUNCTION lambertTimeResidual {
	PARAMETER pathParameter.
	PARAMETER pathParameterSquared.
	PARAMETER oneMinusPathParameterSquared.
	PARAMETER parabolicTime.
	PARAMETER boundaryTolerance.
	PARAMETER normalizedTime.
	PARAMETER x.

	LOCAL u IS 1 - x * x.
	LOCAL timeValue IS parabolicTime. // fallback right at the ellipse/hyperbola boundary

	IF ABS(u) > boundaryTolerance {
		LOCAL z IS SQRT(pathParameterSquared * x * x + oneMinusPathParameterSquared).
		LOCAL y IS SQRT(ABS(u)).
		LOCAL f IS y * (z - pathParameter * x).
		LOCAL g IS x * z + pathParameter * u.
		LOCAL d IS 0.
		IF u > boundaryTolerance {
			SET d TO (90 - ARCTAN(g / f)) * CONSTANT:DegToRad.
			SET timeValue TO (pathParameter * z + d / y - x) / u.
		} ELSE IF f + g > 0 {
			SET d TO LN(f + g).
			SET timeValue TO (pathParameter * z + d / y - x) / u.
		} ELSE {
			// A hyperbola with a huge x: f + g can round to zero or below, and LN of that stops the script.
			// The time of flight tends to 0 there.
			SET timeValue TO 0.
		}
	}

	RETURN timeValue - normalizedTime.
}



// ----------------------------------------------------------------------------
// Orbit propagation
// ----------------------------------------------------------------------------

// The state (relative to the central body) of a spec's real orbit at a UT, from the game's prediction.
// Needs "orbitable" and "central" (attachLiveOrbit). POSITIONAT holds the central body at its position
// now, so that is what is subtracted. ut must be before the spec's "patchUT".
// Returns LEXICON("position", "velocity").
FUNCTION orbitStateAt {
	PARAMETER orbitSpec.
	PARAMETER ut.

	RETURN LEXICON("position", POSITIONAT(orbitSpec["orbitable"], ut) - orbitSpec["central"]:POSITION,
					"velocity", VELOCITYAT(orbitSpec["orbitable"], ut):ORBIT).
}


// ----------------------------------------------------------------------------
// Hyperbolic departure at one point
// ----------------------------------------------------------------------------

// The burn from one point that leaves the body's SOI with a given velocity.
//   burnPosition - relative to the body
//   vExit        - velocity (relative to the body) wanted AT the SOI edge
//   mu, soiRadius - of the body
//   tangentHint  - passed to solveBurnAtPoint; the parking-orbit velocity is a good choice
//   minPeriapsis - m from the body's centre; a hyperbola that dips below it is dropped
//   soiIterations - passes correcting the asymptote direction for the hyperbola still turning
//                  between the SOI edge and infinity (3-4 is enough)
//   senses       - which sweep directions to solve (1 = short way, 2 = long way)
// Returns a LIST of candidates, one per usable sense, each a LEXICON:
//   "burnVelocity" - velocity (relative to the body) right after the burn
//   "sense", "eccentricity", "periapsis", "vInfinity"
//   "trueAnomalyBurn", "trueAnomalySOI" - on the hyperbola, degrees
//   "transitTime"  - s from the burn to the SOI edge
// Empty if vExit is below escape speed at the SOI edge.
FUNCTION solveEjectionAtPoint {
	PARAMETER burnPosition.
	PARAMETER vExit.
	PARAMETER mu.
	PARAMETER soiRadius.
	PARAMETER tangentHint IS V(0, 0, 0).
	PARAMETER minPeriapsis IS 0.
	PARAMETER soiIterations IS 4.
	PARAMETER senses IS LIST(1, 2).

	LOCAL candidates IS LIST().
	LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * mu / soiRadius.
	IF vInfinitySquared <= 0 RETURN candidates.
	LOCAL vInfinity IS SQRT(vInfinitySquared).

	LOCAL edgeUnit IS vExit:NORMALIZED.
	LOCAL burnRadius IS burnPosition:MAG.
	LOCAL radialUnit IS burnPosition / burnRadius.

	FOR sense IN senses {
		LOCAL asymptoteUnit IS edgeUnit.
		LOCAL burnVelocity IS V(0, 0, 0).
		LOCAL eccentricity IS 0.
		LOCAL burnAnomaly IS 0.
		LOCAL soiAnomaly IS 0.
		LOCAL periapsisRadius IS 0.
		LOCAL usable IS TRUE.

		FROM {LOCAL pass IS 0.} UNTIL pass >= soiIterations STEP {SET pass TO pass + 1.} DO {
			SET burnVelocity TO solveBurnAtPoint(burnPosition, asymptoteUnit * vInfinity, mu, tangentHint, LIST(sense))[0].

			LOCAL radialSpeed IS VDOT(burnVelocity, radialUnit).
			LOCAL tangentialVector IS burnVelocity - radialUnit * radialSpeed.
			LOCAL tangentialSpeed IS tangentialVector:MAG.
			IF tangentialSpeed < 1e-6 {
				// a purely radial burn - no usable hyperbola plane here
				SET usable TO FALSE.
				BREAK.
			}
			LOCAL sideUnit IS tangentialVector / tangentialSpeed.

			// Elements of the hyperbola, in the plane of (radialUnit, sideUnit).
			LOCAL semiLatus IS (burnRadius * tangentialSpeed) ^ 2 / mu.
			LOCAL eccentricityRadial IS burnRadius * tangentialSpeed ^ 2 / mu - 1.
			LOCAL eccentricitySide IS -burnRadius * tangentialSpeed * radialSpeed / mu.
			SET eccentricity TO SQRT(eccentricityRadial ^ 2 + eccentricitySide ^ 2).
			SET burnAnomaly TO ARCTAN2(-eccentricitySide, eccentricityRadial).
			SET soiAnomaly TO ARCCOS(MAX(-1, MIN(1, (semiLatus / soiRadius - 1) / eccentricity))).
			SET periapsisRadius TO semiLatus / (1 + eccentricity).

			// The heading turns by headingGap between the SOI edge and the asymptote: rotate the target by it.
			LOCAL asymptoteAnomaly IS ARCCOS(MAX(-1, MIN(1, -1 / eccentricity))).
			LOCAL headingGap IS ARCTAN2(eccentricity + COS(asymptoteAnomaly), -SIN(asymptoteAnomaly))
				- ARCTAN2(eccentricity + COS(soiAnomaly), -SIN(soiAnomaly)).
			LOCAL perpendicularUnit IS radialUnit * (-VDOT(edgeUnit, sideUnit)) + sideUnit * VDOT(edgeUnit, radialUnit).
			SET asymptoteUnit TO edgeUnit * COS(headingGap) + perpendicularUnit * SIN(headingGap).
		}

		IF usable AND periapsisRadius >= minPeriapsis {
			candidates:ADD(LEXICON("burnVelocity", burnVelocity,
									"sense", sense,
									"eccentricity", eccentricity,
									"periapsis", periapsisRadius,
									"vInfinity", vInfinity,
									"trueAnomalyBurn", burnAnomaly,
									"trueAnomalySOI", soiAnomaly,
									"transitTime", hyperbolaTransitTime(mu, vInfinity, eccentricity, burnAnomaly, soiAnomaly))).
		}
	}
	RETURN candidates.
}


// ----------------------------------------------------------------------------
// Parking orbits ("orbit specs")
// ----------------------------------------------------------------------------

// Radius from a body's centre below which an orbit would hit the ground or
// its atmosphere.
FUNCTION bodyClearanceRadius {
	PARAMETER centralBody.

	LOCAL clearance IS centralBody:RADIUS.
	IF centralBody:ATM:EXISTS SET clearance TO clearance + centralBody:ATM:HEIGHT.
	RETURN clearance.
}

// An "orbit"-mode spec from a state vector (relative to the central body, at UT epoch). An escape orbit has
// "period" 0 and a negative "sma"; the searches that need a repeating orbit must not be given one. A parabola
// is treated as the mildest hyperbola ("parabolic" is TRUE), so nothing divides by zero.
FUNCTION makeOrbitSpec {
	PARAMETER parkPosition.
	PARAMETER parkVelocity.
	PARAMETER epoch.
	PARAMETER mu.
	PARAMETER minPeriapsis IS 0.

	LOCAL inverseSMA IS 2 / parkPosition:MAG - parkVelocity:MAG ^ 2 / mu.
	LOCAL parabolicLimit IS 1e-9 * 2 / parkPosition:MAG.
	LOCAL parabolic IS ABS(inverseSMA) < parabolicLimit.
	IF parabolic SET inverseSMA TO -parabolicLimit.
	LOCAL sma IS 1 / inverseSMA.
	// h^2 = mu * sma * (1 - e^2); the periapsis radius is what ejectionLowerBound needs.
	LOCAL momentumSize IS VCRS(parkPosition, parkVelocity):MAG.
	LOCAL eccentricity IS SQRT(MAX(0, 1 - momentumSize ^ 2 / (mu * sma))).
	// An escape orbit has no period: 0 marks that.
	LOCAL orbitPeriod IS 0.
	IF sma > 0 SET orbitPeriod TO 2 * CONSTANT:PI * SQRT(sma ^ 3 / mu).
	RETURN LEXICON("mode", "orbit",
					"parabolic", parabolic,
					"position", parkPosition,
					"velocity", parkVelocity,
					"epoch", epoch,
					"mu", mu,
					"sma", sma,
					"eccentricity", eccentricity,
					"periapsisRadius", sma * (1 - eccentricity),
					"period", orbitPeriod,
					"minPeriapsis", minPeriapsis).
}

// Marks a spec as the orbit of a real orbitable, for orbitStateAt: adds "orbitable", "central" and
// "patchUT" (the UT its orbit changes patch, 0 for none). Returns the spec.
FUNCTION attachLiveOrbit {
	PARAMETER orbitSpec.
	PARAMETER orbitable.
	PARAMETER centralBody.

	SET orbitSpec["orbitable"] TO orbitable.
	SET orbitSpec["central"] TO centralBody.
	SET orbitSpec["patchUT"] TO orbitPatchUT(orbitable).
	RETURN orbitSpec.
}

// Case 2: the spec of a vessel in its parking orbit, as of now.
FUNCTION orbitSpecFromVessel {
	PARAMETER vesselObject IS SHIP.

	LOCAL parentBody IS vesselObject:BODY.
	LOCAL liveSpec IS attachLiveOrbit(makeOrbitSpec(vesselObject:POSITION - parentBody:POSITION, vesselObject:VELOCITY:ORBIT,
											TIME:SECONDS, parentBody:MU, bodyClearanceRadius(parentBody)),
							vesselObject, parentBody).
	// Size and period come from the game's own orbit: from one state vector the period is off by parts per
	// million, which is tens of seconds of burn phase over the thousands of orbits before a departure.
	IF liveSpec["period"] > 0 AND vesselObject:ORBIT:ECCENTRICITY < 1 {
		SET liveSpec["sma"] TO vesselObject:ORBIT:SEMIMAJORAXIS.
		SET liveSpec["period"] TO vesselObject:ORBIT:PERIOD.
	}
	RETURN liveSpec.
}

// Case 1: the spec for a ship that has not launched yet. A circular parking orbit
// at parkingAltitude is designed for each transfer (see designParkingOrbit).
//   launchLatitude - degrees; defaults to the ship's current latitude (the pad)
FUNCTION designSpec {
	PARAMETER centralBody.
	PARAMETER parkingAltitude.
	PARAMETER launchLatitude IS SHIP:LATITUDE.

	RETURN LEXICON("mode", "design",
					"body", centralBody,
					"radius", centralBody:RADIUS + parkingAltitude,
					"latitude", launchLatitude,
					"mu", centralBody:MU,
					"minPeriapsis", bodyClearanceRadius(centralBody)).
}

// Position and velocity on a circular orbit in a given plane.
//   planeNormal - unit vector normal to the plane; the orbit goes round it in the
//                 direction given by VCRS(planeNormal, position)
//   phase       - degrees round the orbit from an arbitrary reference direction
FUNCTION circularOrbitState {
	PARAMETER planeNormal.
	PARAMETER radius.
	PARAMETER mu.
	PARAMETER phase IS 0.

	LOCAL referenceVector IS V(1, 0, 0).
	IF ABS(VDOT(referenceVector, planeNormal)) > 0.9 SET referenceVector TO V(0, 0, 1).
	LOCAL firstUnit IS (referenceVector - planeNormal * VDOT(referenceVector, planeNormal)):NORMALIZED.
	LOCAL secondUnit IS VCRS(planeNormal, firstUnit).

	LOCAL circularSpeed IS SQRT(mu / radius).
	RETURN LEXICON("position", (firstUnit * COS(phase) + secondUnit * SIN(phase)) * radius,
					"velocity", (secondUnit * COS(phase) - firstUnit * SIN(phase)) * circularSpeed).
}

// Case 1: designs the parking orbit for a departure: the plane that contains the departure direction,
// raised to the launch site's latitude if that binds (computeRecommendedParkingPlane).
//   designSpecification - from designSpec
//   vExit               - velocity wanted at the SOI edge (relative to the body)
// Returns an "orbit"-mode spec (epoch 0) with "inclination", "lan", "alternateLan",
// "latitudeConstraintBinding", "pureMinimumInclination", "verificationResidual" and "planeNormal".
FUNCTION designParkingOrbit {
	PARAMETER designSpecification.
	PARAMETER vExit.

	LOCAL plane IS computeRecommendedParkingPlane(designSpecification["body"], vExit, designSpecification["latitude"]).
	LOCAL planeNormal IS getOrbitPlaneNormal(designSpecification["body"], plane["inclination"], plane["lan"]).
	LOCAL state IS circularOrbitState(planeNormal, designSpecification["radius"], designSpecification["mu"], 0).

	LOCAL spec IS makeOrbitSpec(state["position"], state["velocity"], 0, designSpecification["mu"], designSpecification["minPeriapsis"]).
	SET spec["inclination"] TO plane["inclination"].
	SET spec["lan"] TO plane["lan"].
	SET spec["alternateLan"] TO plane["alternateLan"].
	SET spec["latitudeConstraintBinding"] TO plane["latitudeConstraintBinding"].
	SET spec["pureMinimumInclination"] TO plane["pureMinimumInclination"].
	SET spec["verificationResidual"] TO plane["verificationResidual"].
	SET spec["planeNormal"] TO planeNormal.
	RETURN spec.
}


// ----------------------------------------------------------------------------
// Ejection cost from an orbit
// ----------------------------------------------------------------------------

// How hard the ejection search works; it dominates the cost of a transfer search.
//   "full"  - 48 burn-point samples, 4 SOI-correction passes, 8 polish steps. For anything reported.
//   "quick" - 24 samples, 2 passes, 6 polish steps. For the coarse grid and the hill climb.
// The best point is then priced with the exact solver (solveEjectionAtPoint).
// "exitPasses" and "exactExit" set how carefully transferDeltaV places the start of the Lambert arc at
// the SOI-exit point (see there).
// Returns a LEXICON: "samples", "soiIterations", "polishIterations", "exitPasses", "exactExit".
FUNCTION ejectionPrecision {
	PARAMETER precisionName.

	IF precisionName = "quick" RETURN LEXICON("samples", 24, "soiIterations", 2, "polishIterations", 6, "exitPasses", 1, "exactExit", FALSE).
	RETURN LEXICON("samples", 48, "soiIterations", 4, "polishIterations", 8, "exitPasses", 2, "exactExit", TRUE).
}

// A rigorous lower bound on the ejection delta-V for an orbit spec and an excess speed vInfinity:
// |vBurn - vPark| >= |vBurn| - |vPark|, smallest at periapsis. For a "design" spec whose plane contains
// the departure direction it is the exact cost (a tangential burn at periapsis).
FUNCTION ejectionLowerBound {
	PARAMETER orbitSpec.
	PARAMETER vInfinity.

	LOCAL mu IS orbitSpec["mu"].
	LOCAL burnRadius IS 0.
	LOCAL parkSpeed IS 0.
	IF orbitSpec["mode"] = "design" {
		SET burnRadius TO orbitSpec["radius"].
		SET parkSpeed TO SQRT(mu / burnRadius).
	} ELSE {
		SET burnRadius TO orbitSpec["periapsisRadius"].
		SET parkSpeed TO SQRT(mu * (2 / burnRadius - 1 / orbitSpec["sma"])).
	}
	RETURN SQRT(vInfinity ^ 2 + 2 * mu / burnRadius) - parkSpeed.
}

// The cheapest ejection burn anywhere around an "orbit"-mode spec ("phase-free"): a search over true
// anomaly with a scalar model of the cost, then the exact solver at the best point.
// With the exit direction resolved into the orbit's axes (A along periapsis, B along the motion at
// periapsis), the cost at true anomaly nu needs no vectors:
//     cos D = A*cos(nu) + B*sin(nu)                   (D: the sweep angle of solveBurnAtPoint)
//     cos(tilt) = (B*cos(nu) - A*sin(nu)) / sin D     (between the two tangent directions)
//     cost^2 = (vr - vParkRadial)^2 + vt^2 + vParkTangential^2 - 2*vt*vParkTangential*cos(tilt)
// The SOI-edge heading correction only changes the sweep angle, so it is scalar too.
// A burn that cannot clear the planet costs invalidDeltaV plus how far its periapsis is below the
// clearance, so the search is still led toward the feasible region.
//   vExit     - velocity wanted at the SOI edge, relative to the body
//   soiRadius - of the body
//   precision - from ejectionPrecision
// Returns a LEXICON: "deltaV" (invalidDeltaV if no valid burn), "trueAnomaly" (deg) and "offset" (s after
// the spec's epoch) of the burn point, "burnPosition", "parkVelocity", "dvVector", "burnVelocity" and the
// winning "ejection" candidate from solveEjectionAtPoint.
FUNCTION bestEjectionFromOrbit {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER soiRadius.
	PARAMETER precision IS ejectionPrecision("full").

	LOCAL mu IS orbitSpec["mu"].
	LOCAL best IS LEXICON("deltaV", invalidDeltaV, "ejection", 0).
	LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * mu / soiRadius.
	IF vInfinitySquared <= 0 RETURN best.
	LOCAL vInfinity IS SQRT(vInfinitySquared).
	LOCAL correctionPasses IS precision["soiIterations"].

	// The orbit's own axes. Only the in-plane part of the eccentricity vector is kept; below 1e-5 the orbit
	// is treated as circular, with true anomaly measured from the ship.
	LOCAL startPosition IS orbitSpec["position"].
	LOCAL momentumVector IS VCRS(startPosition, orbitSpec["velocity"]).
	LOCAL momentumSize IS momentumVector:MAG.
	LOCAL normalUnit IS momentumVector / momentumSize.
	LOCAL eccentricityVector IS VCRS(orbitSpec["velocity"], momentumVector) / mu - startPosition:NORMALIZED.
	SET eccentricityVector TO eccentricityVector - normalUnit * VDOT(eccentricityVector, normalUnit).
	LOCAL eccentricity IS eccentricityVector:MAG.
	LOCAL periapsisUnit IS startPosition:NORMALIZED.
	IF eccentricity > 1e-5 {
		SET periapsisUnit TO eccentricityVector / eccentricity.
	} ELSE {
		SET eccentricity TO 0.
	}
	LOCAL motionUnit IS VCRS(normalUnit, periapsisUnit).
	LOCAL semiLatus IS momentumSize ^ 2 / mu.
	LOCAL speedScale IS mu / momentumSize.
	LOCAL minPeriapsis IS orbitSpec["minPeriapsis"].

	// The exit direction resolved into those axes.
	LOCAL exitUnit IS vExit:NORMALIZED.
	LOCAL exitAlongPeriapsis IS VDOT(periapsisUnit, exitUnit).
	LOCAL exitAlongMotion IS VDOT(motionUnit, exitUnit).
	LOCAL senseSigns IS LIST(1, -1).

	// The scalar model: ejection cost at true anomaly trueAnomaly (degrees), the cheaper of the two
	// sweep directions. Above invalidDeltaV means no sweep direction clears minPeriapsis.
	FUNCTION costAtAnomaly {
		PARAMETER trueAnomaly.

		LOCAL cosNu IS COS(trueAnomaly).
		LOCAL sinNu IS SIN(trueAnomaly).
		LOCAL radius IS semiLatus / (1 + eccentricity * cosNu).
		LOCAL parkRadialSpeed IS speedScale * eccentricity * sinNu.
		LOCAL parkTangentialSpeed IS speedScale * (1 + eccentricity * cosNu).
		LOCAL cosSweep IS MAX(-1, MIN(1, exitAlongPeriapsis * cosNu + exitAlongMotion * sinNu)).
		LOCAL sinSweep IS SQRT(MAX(0, 1 - cosSweep ^ 2)).
		LOCAL shortSweep IS ARCTAN2(sinSweep, cosSweep).
		LOCAL cosTilt IS 1.
		IF sinSweep > 1e-9 SET cosTilt TO MAX(-1, MIN(1, (exitAlongMotion * cosNu - exitAlongPeriapsis * sinNu) / sinSweep)).

		LOCAL bestCost IS 2 * invalidDeltaV.
		FOR senseSign IN senseSigns {
			LOCAL baseSweep IS shortSweep.
			IF senseSign < 0 SET baseSweep TO 360 - shortSweep.
			LOCAL sweep IS baseSweep.
			LOCAL tangentialSpeed IS 0.
			LOCAL radialSpeed IS 0.
			LOCAL hyperbolaEccentricity IS 1.

			FROM {LOCAL pass IS 1.} UNTIL pass > correctionPasses STEP {SET pass TO pass + 1.} DO {
				LOCAL sinOfSweep IS SIN(sweep).
				LOCAL cosOfSweep IS COS(sweep).
				SET tangentialSpeed TO (vInfinity * sinOfSweep + SQRT((vInfinity * sinOfSweep) ^ 2 + 4 * mu * (1 - cosOfSweep) / radius)) / 2.
				SET radialSpeed TO SQRT(vInfinitySquared + 2 * mu / radius).
				IF tangentialSpeed > 1e-6 SET radialSpeed TO vInfinity * cosOfSweep + mu * sinOfSweep / (radius * tangentialSpeed).
				LOCAL eccentricityRadial IS radius * tangentialSpeed ^ 2 / mu - 1.
				LOCAL eccentricitySide IS radius * tangentialSpeed * radialSpeed / mu.
				SET hyperbolaEccentricity TO SQRT(eccentricityRadial ^ 2 + eccentricitySide ^ 2).
				IF pass < correctionPasses {
					// How far the asymptote lies beyond the SOI-edge heading, added to the sweep.
					LOCAL hyperbolaSemiLatus IS (radius * tangentialSpeed) ^ 2 / mu.
					LOCAL edgeAnomaly IS ARCCOS(MAX(-1, MIN(1, (hyperbolaSemiLatus / soiRadius - 1) / hyperbolaEccentricity))).
					LOCAL asymptoteAnomaly IS ARCCOS(MAX(-1, MIN(1, -1 / hyperbolaEccentricity))).
					SET sweep TO baseSweep + ARCTAN2(hyperbolaEccentricity + COS(asymptoteAnomaly), -SIN(asymptoteAnomaly))
						- ARCTAN2(hyperbolaEccentricity + COS(edgeAnomaly), -SIN(edgeAnomaly)).
				}
			}

			// The hyperbola this burn puts the ship on must clear the planet and its atmosphere.
			LOCAL hyperbolaPeriapsis IS radius ^ 2 * tangentialSpeed ^ 2 / mu / (1 + hyperbolaEccentricity).
			LOCAL candidateCost IS invalidDeltaV + (minPeriapsis - hyperbolaPeriapsis).
			IF hyperbolaPeriapsis >= minPeriapsis {
				SET candidateCost TO SQRT(MAX(0, (radialSpeed - parkRadialSpeed) ^ 2 + tangentialSpeed ^ 2 + parkTangentialSpeed ^ 2
					- 2 * tangentialSpeed * parkTangentialSpeed * senseSign * cosTilt)).
			}
			IF candidateCost < bestCost SET bestCost TO candidateCost.
		}
		RETURN bestCost.
	}

	// The exact ejection (the vector solve) at true anomaly trueAnomaly.
	FUNCTION exactAtAnomaly {
		PARAMETER trueAnomaly.

		LOCAL radius IS semiLatus / (1 + eccentricity * COS(trueAnomaly)).
		LOCAL burnPosition IS (periapsisUnit * COS(trueAnomaly) + motionUnit * SIN(trueAnomaly)) * radius.
		LOCAL parkVelocity IS (periapsisUnit * (-SIN(trueAnomaly)) + motionUnit * (eccentricity + COS(trueAnomaly))) * speedScale.
		LOCAL options IS solveEjectionAtPoint(burnPosition, vExit, mu, soiRadius, parkVelocity, minPeriapsis, correctionPasses).
		LOCAL bestOption IS 0.
		LOCAL bestDV IS invalidDeltaV.
		FOR option IN options {
			LOCAL optionDV IS (option["burnVelocity"] - parkVelocity):MAG.
			IF optionDV < bestDV {
				SET bestDV TO optionDV.
				SET bestOption TO option.
			}
		}
		LOCAL result IS LEXICON("deltaV", bestDV, "trueAnomaly", trueAnomaly, "burnPosition", burnPosition,
								"parkVelocity", parkVelocity, "ejection", bestOption).
		IF bestDV < invalidDeltaV {
			SET result["burnVelocity"] TO bestOption["burnVelocity"].
			SET result["dvVector"] TO bestOption["burnVelocity"] - parkVelocity.
		}
		RETURN result.
	}

	// Coarse scan around the whole orbit, then polish the best sample.
	LOCAL samples IS precision["samples"].
	LOCAL stepDegrees IS 360 / samples.
	LOCAL bestAnomaly IS 0.
	LOCAL bestSampleCost IS 4 * invalidDeltaV.
	FROM {LOCAL sampleIndex IS 0.} UNTIL sampleIndex >= samples STEP {SET sampleIndex TO sampleIndex + 1.} DO {
		LOCAL sampleCost IS costAtAnomaly(sampleIndex * stepDegrees).
		IF sampleCost < bestSampleCost {
			SET bestSampleCost TO sampleCost.
			SET bestAnomaly TO sampleIndex * stepDegrees.
		}
	}
	LOCAL polishedAnomaly IS goldenSectionMinimum(costAtAnomaly@, bestAnomaly - stepDegrees, bestAnomaly + stepDegrees, precision["polishIterations"]).

	// Price the winner exactly, at the polished point and at the best sample.
	SET best TO exactAtAnomaly(polishedAnomaly).
	IF bestSampleCost < invalidDeltaV {
		LOCAL sampleResult IS exactAtAnomaly(bestAnomaly).
		IF sampleResult["deltaV"] < best["deltaV"] SET best TO sampleResult.
	}
	IF best["deltaV"] >= invalidDeltaV {
		// Both fell just outside the feasible region once priced exactly; look a little either side.
		FOR nudge IN LIST(1, -1, 3, -3) {
			IF best["deltaV"] >= invalidDeltaV {
				LOCAL nudged IS exactAtAnomaly(polishedAnomaly + nudge).
				IF nudged["deltaV"] < best["deltaV"] SET best TO nudged.
			}
		}
	}
	IF best["deltaV"] >= invalidDeltaV RETURN best.

	// How long after the spec's epoch the ship reaches that burn point: true anomaly to mean
	// anomaly now and then, over the mean motion.
	LOCAL startAnomaly IS ARCTAN2(VDOT(startPosition, motionUnit), VDOT(startPosition, periapsisUnit)).
	LOCAL burnEccentricAnomaly IS 2 * ARCTAN2(SQRT(1 - eccentricity) * SIN(best["trueAnomaly"] / 2), SQRT(1 + eccentricity) * COS(best["trueAnomaly"] / 2)).
	LOCAL startEccentricAnomaly IS 2 * ARCTAN2(SQRT(1 - eccentricity) * SIN(startAnomaly / 2), SQRT(1 + eccentricity) * COS(startAnomaly / 2)).
	LOCAL burnMeanAnomaly IS burnEccentricAnomaly * CONSTANT:DegToRad - eccentricity * SIN(burnEccentricAnomaly).
	LOCAL startMeanAnomaly IS startEccentricAnomaly * CONSTANT:DegToRad - eccentricity * SIN(startEccentricAnomaly).
	LOCAL meanMotion IS SQRT(mu / orbitSpec["sma"] ^ 3).
	LOCAL timeToBurn IS (burnMeanAnomaly - startMeanAnomaly) / meanMotion.
	SET best["offset"] TO timeToBurn - FLOOR(timeToBurn / orbitSpec["period"]) * orbitSpec["period"].
	RETURN best.
}

// The cheapest correction burn for a ship on an escape orbit, with the SOI exit time left free: the burn
// time on its own orbit that reaches vExit at the SOI edge for the least delta-V (the escape orbit's
// counterpart of bestEjectionFromOrbit). Burn times run from earliestBurnUT to exitMargin before the
// ship's own SOI exit: a coarse scan, then a golden-section polish.
//   orbitSpec      - "orbit" mode, an escape orbit (period 0), with "patchUT"
//   vExit          - velocity wanted at the SOI edge, relative to the body
//   earliestBurnUT - burns earlier than this are not allowed
// Returns a LEXICON like ejectionForExitTime's, plus "exitUT" (burnUT + transitTime): where the burn
// really leaves the SOI (see escapeLockedDeparture).
FUNCTION ejectionFreeExit {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER soiRadius.
	PARAMETER earliestBurnUT IS 0.
	PARAMETER precision IS ejectionPrecision("full").

	LOCAL result IS LEXICON("deltaV", invalidDeltaV, "ejection", 0).
	IF NOT orbitSpec:HASKEY("patchUT") RETURN result.
	IF orbitSpec["patchUT"] <= 0 RETURN result.

	// How long before the ship's own exit the last burn can be (the burn has a length of its own).
	LOCAL exitMargin IS 300.
	LOCAL probeStart IS MAX(earliestBurnUT, orbitSpec["epoch"]).
	LOCAL lastBurnUT IS orbitSpec["patchUT"] - exitMargin.
	IF lastBurnUT <= probeStart RETURN result.

	// The cheapest valid burn at one burn time, over both sweep directions. The periapsis limit applies
	// only ahead of the burn: past the new hyperbola's periapsis (a positive true anomaly) it is never flown.
	FUNCTION bestAt {
		PARAMETER burnUT.

		LOCAL state IS orbitStateAt(orbitSpec, burnUT).
		LOCAL best IS LEXICON("deltaV", invalidDeltaV).
		FOR option IN solveEjectionAtPoint(state["position"], vExit, orbitSpec["mu"], soiRadius, state["velocity"], 0, precision["soiIterations"], LIST(1, 2)) {
			IF option["periapsis"] >= orbitSpec["minPeriapsis"] OR option["trueAnomalyBurn"] >= 0 {
				LOCAL optionDV IS (option["burnVelocity"] - state["velocity"]):MAG.
				IF optionDV < best["deltaV"] {
					SET best TO LEXICON("deltaV", optionDV,
										"burnUT", burnUT,
										"dvVector", option["burnVelocity"] - state["velocity"],
										"burnVelocity", option["burnVelocity"],
										"burnPosition", state["position"],
										"parkVelocity", state["velocity"],
										"transitTime", option["transitTime"],
										"exitUT", burnUT + option["transitTime"],
										"ejection", option).
				}
			}
		}
		RETURN best.
	}

	FUNCTION costAt {
		PARAMETER burnUT.

		RETURN bestAt(burnUT)["deltaV"].
	}

	LOCAL samples IS precision["samples"].
	LOCAL stepSeconds IS (lastBurnUT - probeStart) / samples.
	LOCAL bestSampleUT IS probeStart.
	LOCAL bestSampleCost IS 4 * invalidDeltaV.
	FROM {LOCAL sampleIndex IS 0.} UNTIL sampleIndex > samples STEP {SET sampleIndex TO sampleIndex + 1.} DO {
		LOCAL sampleUT IS probeStart + sampleIndex * stepSeconds.
		LOCAL sampleCost IS costAt(sampleUT).
		IF sampleCost < bestSampleCost {
			SET bestSampleCost TO sampleCost.
			SET bestSampleUT TO sampleUT.
		}
	}
	IF bestSampleCost >= invalidDeltaV RETURN result.

	LOCAL polishedUT IS goldenSectionMinimum(costAt@, MAX(probeStart, bestSampleUT - stepSeconds), MIN(lastBurnUT, bestSampleUT + stepSeconds), precision["polishIterations"]).
	SET result TO bestAt(polishedUT).
	LOCAL sampleResult IS bestAt(bestSampleUT).
	IF sampleResult["deltaV"] < result["deltaV"] SET result TO sampleResult.
	IF result["deltaV"] >= invalidDeltaV RETURN LEXICON("deltaV", invalidDeltaV, "ejection", 0).
	RETURN result.
}

// The ejection burn when the SOI exit time tSOI is fixed ("exact timing"). The burn is transitTime before
// tSOI and transitTime depends on the burn point, so the burn time is the root of
//     burnUT + transitTime(burnUT) - tSOI = 0
// for each sweep direction. The transit-time range over one orbit sets the search window; it is sampled
// for sign changes, each bracket is solved with findZeroBrent, and the cheapest valid root wins.
// For an escape orbit (period 0) the burn times run from earliestBurnUT to the ship's SOI exit or tSOI.
//   orbitSpec - "orbit" mode
//   vExit     - velocity wanted at the SOI edge, relative to the body
//   tSOI      - UT the ship should cross the SOI edge
//   earliestBurnUT - an earlier burn is ignored
//   scanSamples - samples for the transit-time range, and again for the root bracketing
// Returns a LEXICON: "deltaV" (invalidDeltaV if no valid burn), "burnUT", "dvVector", "burnVelocity",
// "burnPosition", "parkVelocity", "transitTime" and the "ejection" candidate.
FUNCTION ejectionForExitTime {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER tSOI.
	PARAMETER soiRadius.
	PARAMETER earliestBurnUT IS 0.
	PARAMETER soiIterations IS 4.
	PARAMETER scanSamples IS 12.

	LOCAL result IS LEXICON("deltaV", invalidDeltaV, "ejection", 0).

	// The burn times to look at: one orbit from the spec's epoch or, for an escape orbit, from the earliest
	// burn to the last moment a burn can help.
	LOCAL escapeOrbit IS orbitSpec["period"] = 0.
	LOCAL probeStart IS orbitSpec["epoch"].
	LOCAL probeSpan IS orbitSpec["period"].
	LOCAL probeCount IS scanSamples.
	IF escapeOrbit {
		SET probeStart TO MAX(earliestBurnUT, orbitSpec["epoch"]).
		LOCAL lastBurnUT IS tSOI.
		// A second short of the SOI exit, so the prediction is still on this patch.
		IF orbitSpec["patchUT"] > 0 AND orbitSpec["patchUT"] - 1 < lastBurnUT SET lastBurnUT TO orbitSpec["patchUT"] - 1.
		SET probeSpan TO lastBurnUT - probeStart.
		SET probeCount TO scanSamples + 1.
		IF probeSpan <= 0 RETURN result.
	}

	// The ejection candidate for one sweep direction at one burn time. The periapsis
	// limit is left off here (it would make the residual below jump) and is checked
	// on the final answer instead.
	FUNCTION candidateAt {
		PARAMETER senseNumber.
		PARAMETER burnUT.

		LOCAL state IS orbitStateAt(orbitSpec, burnUT).
		LOCAL options IS solveEjectionAtPoint(state["position"], vExit, orbitSpec["mu"], soiRadius, state["velocity"], 0, soiIterations, LIST(senseNumber)).
		IF options:LENGTH = 0 RETURN LEXICON("valid", FALSE, "state", state).
		RETURN LEXICON("valid", TRUE, "state", state, "option", options[0]).
	}

	// How far the SOI exit time that a burn at burnUT leads to is from tSOI.
	FUNCTION exitTimeResidual {
		PARAMETER senseNumber.
		PARAMETER burnUT.

		LOCAL candidate IS candidateAt(senseNumber, burnUT).
		IF NOT candidate["valid"] RETURN burnUT - tSOI.
		RETURN burnUT + candidate["option"]["transitTime"] - tSOI.
	}

	FOR senseNumber IN LIST(1, 2) {
		// The range of transit times this sweep direction has around the orbit.
		LOCAL transitMin IS 1e15.
		LOCAL transitMax IS -1e15.
		FROM {LOCAL sampleIndex IS 0.} UNTIL sampleIndex >= probeCount STEP {SET sampleIndex TO sampleIndex + 1.} DO {
			LOCAL probe IS candidateAt(senseNumber, probeStart + sampleIndex * probeSpan / scanSamples).
			IF probe["valid"] {
				SET transitMin TO MIN(transitMin, probe["option"]["transitTime"]).
				SET transitMax TO MAX(transitMax, probe["option"]["transitTime"]).
			}
		}

		// Any burn that exits at tSOI lies in this window, and the residual changes sign across it.
		LOCAL windowStart IS tSOI - transitMax - 1.
		LOCAL windowEnd IS tSOI - transitMin + 1.
		IF escapeOrbit {
			SET windowStart TO MAX(windowStart, probeStart).
			SET windowEnd TO MIN(windowEnd, probeStart + probeSpan).
		}
		IF transitMax >= transitMin AND windowEnd > windowStart {
			LOCAL residualDelegate IS exitTimeResidual@:BIND(senseNumber).
			LOCAL previousUT IS windowStart.
			LOCAL previousResidual IS residualDelegate(windowStart).

			FROM {LOCAL sampleIndex IS 1.} UNTIL sampleIndex > scanSamples STEP {SET sampleIndex TO sampleIndex + 1.} DO {
				LOCAL sampleUT IS windowStart + (windowEnd - windowStart) * sampleIndex / scanSamples.
				LOCAL sampleResidual IS residualDelegate(sampleUT).
				IF previousResidual * sampleResidual < 0 {
					LOCAL rootUT IS findZeroBrent(residualDelegate, previousUT, sampleUT, 0.01).
					LOCAL root IS candidateAt(senseNumber, rootUT).
					// On an escape orbit a burn past the hyperbola's periapsis (a positive true anomaly) never
					// flies it, so a periapsis below the clearance only matters ahead of the burn.
					IF root["valid"] AND (root["option"]["periapsis"] >= orbitSpec["minPeriapsis"] OR (escapeOrbit AND root["option"]["trueAnomalyBurn"] >= 0)) {
						LOCAL rootDV IS (root["option"]["burnVelocity"] - root["state"]["velocity"]):MAG.
						IF rootDV < result["deltaV"] AND rootUT >= earliestBurnUT {
							SET result TO LEXICON("deltaV", rootDV,
													"burnUT", rootUT,
													"dvVector", root["option"]["burnVelocity"] - root["state"]["velocity"],
													"burnVelocity", root["option"]["burnVelocity"],
													"burnPosition", root["state"]["position"],
													"parkVelocity", root["state"]["velocity"],
													"transitTime", root["option"]["transitTime"],
													"ejection", root["option"]).
						}
					}
				}
				SET previousUT TO sampleUT.
				SET previousResidual TO sampleResidual.
			}
		}
	}
	RETURN result.
}

// Where the ship crosses the departure body's SOI edge, relative to the body's centre, for an ejection
// from bestEjectionFromOrbit or ejectionForExitTime: the burn direction turned through the true anomaly
// from the burn to the edge, at the SOI radius. V(0, 0, 0) if there is no hyperbola to read it from.
FUNCTION soiExitOffset {
	PARAMETER ejection.
	PARAMETER soiRadius.

	IF NOT ejection:HASKEY("ejection") OR NOT ejection:HASKEY("burnPosition") RETURN V(0, 0, 0).
	LOCAL hyperbola IS ejection["ejection"].
	IF NOT hyperbola:ISTYPE("Lexicon") RETURN V(0, 0, 0).

	LOCAL radialUnit IS ejection["burnPosition"]:NORMALIZED.
	LOCAL burnVelocity IS hyperbola["burnVelocity"].
	LOCAL tangentialVector IS burnVelocity - radialUnit * VDOT(burnVelocity, radialUnit).
	IF tangentialVector:MAG < 1e-6 RETURN V(0, 0, 0).

	LOCAL sweep IS hyperbola["trueAnomalySOI"] - hyperbola["trueAnomalyBurn"].
	RETURN (radialUnit * COS(sweep) + tangentialVector:NORMALIZED * SIN(sweep)) * soiRadius.
}

// The ejection cost for an exit velocity, for either kind of orbit spec.
//   exactTiming - "orbit" spec only: fix the burn point by tSOI instead of taking the best in the orbit
//   precision   - from ejectionPrecision
// A "design" spec whose plane is not forced by the latitude uses the closed form of ejectionLowerBound.
// Returns the LEXICON of bestEjectionFromOrbit / ejectionForExitTime / ejectionFreeExit (the closed form:
// just "deltaV" and "closedForm"); a "design" spec also carries the designed plane (see designParkingOrbit).
FUNCTION ejectionDeltaVForExit {
	PARAMETER orbitSpec.
	PARAMETER vExit.
	PARAMETER fromBody.
	PARAMETER tSOI.
	PARAMETER exactTiming IS FALSE.
	PARAMETER precision IS ejectionPrecision("full").
	PARAMETER earliestBurnUT IS 0.

	LOCAL soiRadius IS fromBody:SOIRADIUS.
	LOCAL isDesign IS orbitSpec["mode"] = "design".
	LOCAL workingSpec IS orbitSpec.
	IF isDesign SET workingSpec TO designParkingOrbit(orbitSpec, vExit).

	// An escape orbit has no burn phase: its burn is the cheapest before its SOI exit (ejectionFreeExit) or,
	// with exactTiming, the one that exits at tSOI.
	LOCAL escapeOrbit IS NOT isDesign AND workingSpec["period"] = 0.
	LOCAL burnNotBefore IS earliestBurnUT.
	IF escapeOrbit AND workingSpec:HASKEY("earliestBurnUT") SET burnNotBefore TO MAX(earliestBurnUT, workingSpec["earliestBurnUT"]).

	LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * workingSpec["mu"] / soiRadius.
	LOCAL result IS 0.
	IF vInfinitySquared <= 0 {
		// Below escape speed at the SOI edge: no burn gets out.
		SET result TO LEXICON("deltaV", invalidDeltaV, "ejection", 0).
	} ELSE IF isDesign AND NOT workingSpec["latitudeConstraintBinding"] AND workingSpec["periapsisRadius"] >= workingSpec["minPeriapsis"] {
		SET result TO LEXICON("deltaV", ejectionLowerBound(workingSpec, SQRT(vInfinitySquared)), "ejection", 0, "closedForm", TRUE).
	} ELSE IF escapeOrbit AND NOT exactTiming {
		SET result TO ejectionFreeExit(workingSpec, vExit, soiRadius, burnNotBefore, precision).
	} ELSE IF (exactTiming OR escapeOrbit) AND NOT isDesign {
		SET result TO ejectionForExitTime(workingSpec, vExit, tSOI, soiRadius, burnNotBefore, precision["soiIterations"]).
	} ELSE {
		SET result TO bestEjectionFromOrbit(workingSpec, vExit, soiRadius, precision).
	}

	IF isDesign {
		SET result["inclination"] TO workingSpec["inclination"].
		SET result["lan"] TO workingSpec["lan"].
		SET result["alternateLan"] TO workingSpec["alternateLan"].
		SET result["latitudeConstraintBinding"] TO workingSpec["latitudeConstraintBinding"].
		SET result["pureMinimumInclination"] TO workingSpec["pureMinimumInclination"].
		SET result["verificationResidual"] TO workingSpec["verificationResidual"].
		SET result["planeNormal"] TO workingSpec["planeNormal"].
	}
	RETURN result.
}


// ----------------------------------------------------------------------------
// Arrival and the total
// ----------------------------------------------------------------------------

// Delta-V to finish the transfer at the destination.
//   arrivalVelocity - transfer velocity relative to the destination, as Lambert gives it
//                     (the velocity at the destination's SOI edge)
//   captureRadius   - m from the destination's centre. If > 0, the cost of capturing into
//                     a circular orbit of that radius, burning at its periapsis; if 0, the
//                     hyperbolic excess (the cost of matching the destination's velocity
//                     far from it).
// A vessel has no SOI, so for one the cost is just the relative speed. If the arrival
// velocity is below escape speed at the SOI edge the body captures the ship on its
// own, and the cost is 0.
FUNCTION arrivalDeltaV {
	PARAMETER arrivalVelocity.
	PARAMETER targetOrbitable.
	PARAMETER captureRadius IS 0.

	IF NOT targetOrbitable:ISTYPE("Body") RETURN arrivalVelocity:MAG.

	LOCAL excessSquared IS arrivalVelocity:MAG ^ 2 - 2 * targetOrbitable:MU / targetOrbitable:SOIRADIUS.
	IF excessSquared <= 0 RETURN 0.
	IF captureRadius <= 0 RETURN SQRT(excessSquared).
	RETURN SQRT(excessSquared + 2 * targetOrbitable:MU / captureRadius) - SQRT(targetOrbitable:MU / captureRadius).
}

// The offset from the destination's centre the Lambert arc must be aimed at to pass it at captureRadius:
// the impact parameter, b = r * SQRT(1 + 2 * mu / (r * vInfinity^2)), perpendicular to the arrival velocity
// on the side of a prograde capture. Zero (aim at the centre) with no capture radius, or for a vessel.
//   arrivalVelocity - relative to the destination, as for arrivalDeltaV
//   orbitNormal     - the destination's own orbit normal
FUNCTION arrivalAimOffset {
	PARAMETER arrivalVelocity.
	PARAMETER targetOrbitable.
	PARAMETER captureRadius.
	PARAMETER orbitNormal.

	IF captureRadius <= 0 OR NOT targetOrbitable:ISTYPE("Body") RETURN V(0, 0, 0).
	LOCAL excessSquared IS arrivalVelocity:MAG ^ 2 - 2 * targetOrbitable:MU / targetOrbitable:SOIRADIUS.
	IF excessSquared <= 0 RETURN V(0, 0, 0).

	LOCAL impactParameter IS captureRadius * SQRT(1 + 2 * targetOrbitable:MU / (captureRadius * excessSquared)).
	LOCAL approachDirection IS arrivalVelocity:NORMALIZED.
	LOCAL side IS VCRS(approachDirection, orbitNormal).
	// An approach along the orbit normal has no in-plane side: take any perpendicular.
	IF side:MAG < 0.01 {
		SET side TO VCRS(approachDirection, V(0, 1, 0)).
		IF side:MAG < 0.01 SET side TO VCRS(approachDirection, V(1, 0, 0)).
	}
	RETURN side:NORMALIZED * impactParameter.
}

// Total delta-V (ejection + arrival, m/s) of the transfer that crosses the departure body's SOI edge at
// tSOI and flies for timeOfFlight: the better of Lambert's short-way and long-way arcs.
//   fromBody  - a body; toBody - a body or a vessel
//   orbitSpec - from orbitSpecFromVessel or designSpec
//   captureRadius - see arrivalDeltaV; the full stage also aims the arc at it (statsOut["Aim Offset"])
//   precision - from ejectionPrecision
//   tSOI, timeOfFlight, seed, statsOut - as for porkchopDeltaV; statsOut also gets "Ejection",
//                "Arrival Delta V", "Exit Offset", "Exit Velocity" and "Rejected Arcs"
//   exactTiming, earliestBurnUT - see ejectionDeltaVForExit
// The leading arguments are in the order bindTransferDeltaV binds them.
// The arc that looks cheaper (exact arrival plus ejectionLowerBound) is searched first, and the other's
// ejection search is skipped if its lower bound cannot beat it.
// The arc starts where the ship leaves the SOI, not at the body's centre: each arc is re-solved from the
// body's position plus an offset along the exit heading (precision["exitPasses"] times), then, in the full
// stage, from the exit point the ejection hyperbola reaches (soiExitOffset).
// Returns invalidDeltaV if neither arc works.
FUNCTION transferDeltaV {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER orbitSpec.
	PARAMETER captureRadius.
	PARAMETER precision.
	PARAMETER tSOI.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER statsOut IS LEXICON().
	PARAMETER exactTiming IS FALSE.
	PARAMETER earliestBurnUT IS 0.

	// orbitSpec["pinExit"]: a ship on an escape orbit leaves at about its own exit time whatever tSOI says,
	// so tSOI is pinned to it (the spec's "patchUT") and only the flight time is searched.
	IF orbitSpec:HASKEY("pinExit") AND orbitSpec:HASKEY("patchUT") {
		IF orbitSpec["pinExit"] AND orbitSpec["patchUT"] > 0 SET tSOI TO orbitSpec["patchUT"].
	}

	LOCAL shortStartSeed IS 0.5.
	IF seed:HASKEY("shortSeed") SET shortStartSeed TO seed["shortSeed"].
	LOCAL longStartSeed IS 0.5.
	IF seed:HASKEY("longSeed") SET longStartSeed TO seed["longSeed"].

	// The arc ends at the destination's position at arrival. The departure body's state is kept in seed, so the
	// cells of one departure (which share a seed) look it up once.
	LOCAL arrivalTime IS tSOI + timeOfFlight.
	LOCAL haveDeparture IS FALSE.
	IF seed:HASKEY("departureUT") SET haveDeparture TO seed["departureUT"] = tSOI.
	IF NOT haveDeparture {
		SET seed["departureUT"] TO tSOI.
		SET seed["departurePosition"] TO absolutePosition(fromBody, tSOI) - absolutePosition(sunBody, tSOI).
		SET seed["departureVelocity"] TO absoluteVelocity(fromBody, tSOI) - absoluteVelocity(sunBody, tSOI).
	}
	LOCAL departurePosition IS seed["departurePosition"].
	LOCAL arrivalPosition IS absolutePosition(toBody, arrivalTime) - absolutePosition(sunBody, arrivalTime).
	LOCAL fromBodyVelocity IS seed["departureVelocity"].
	LOCAL toBodyVelocity IS absoluteVelocity(toBody, arrivalTime) - absoluteVelocity(sunBody, arrivalTime).

	LOCAL bestTotalDV IS invalidDeltaV.
	LOCAL winningTrajectory IS 0.
	LOCAL winningEjection IS 0.
	LOCAL winningArrivalDV IS 0.
	// The exit velocity of the cheapest-looking candidate searched, reported when none worked.
	LOCAL lastExitVelocity IS V(0, 0, 0).
	LOCAL lowestBound IS 4 * invalidDeltaV.
	// With exact timing the arc is still chosen, moved and aimed with the phase-free ejection (the exit times
	// a fixed exit velocity can reach are narrow, so an early guess can fail); the timed burn is priced once,
	// at the end, for the arc that won.
	LOCAL stageTiming IS exactTiming AND NOT precision["exactExit"].
	LOCAL soiRadius IS fromBody:SOIRADIUS.

	// A transfer around a body that has a sphere of influence (not the Sun) must stay inside it.
	LOCAL parentLimit IS 0.
	IF sunBody:NAME <> "Sun" SET parentLimit TO sunBody:SOIRADIUS.

	// Why the cell failed if it does: the reason from the furthest stage any solution got to
	// (1 Lambert, 2 escape, 3 flight path, 4 ejection).
	LOCAL failureReason IS "Flight time not positive".
	LOCAL failureRank IS 0.
	LOCAL rejectedArcs IS 0.

	// One Lambert solve from startPosition to aimPosition.
	FUNCTION solveLambert {
		PARAMETER startPosition.
		PARAMETER shortWay.
		PARAMETER startSeed.
		PARAMETER aimPosition.
	
		RETURN lambertGooding(startPosition, aimPosition, timeOfFlight, sunBody:MU, shortWay, startSeed).
	}
	
	// Re-solves the winning arc from startPosition to aimPosition and re-prices it (ejection and arrival).
	// Returns FALSE, leaving the winner as it was, if the new arc fails at any step.
	FUNCTION repriceWinner {
		PARAMETER startPosition.
		PARAMETER aimPosition.
	
		LOCAL movedTrajectory IS solveLambert(startPosition, winningTrajectory["Short Way"], winningTrajectory["Final Value"], aimPosition).
		IF movedTrajectory["Motion Type"] = "Failed" RETURN FALSE.
		LOCAL movedExit IS movedTrajectory["v_1"] - fromBodyVelocity.
		IF movedExit:MAG ^ 2 - 2 * orbitSpec["mu"] / soiRadius <= 0 RETURN FALSE.
		LOCAL movedSweep IS VANG(movedTrajectory["r_1"], aimPosition).
		IF NOT movedTrajectory["Short Way"] SET movedSweep TO 360 - movedSweep.
		IF transferArcProblem(movedTrajectory["r_1"], movedTrajectory["v_1"], movedSweep, sunBody:MU, bodyClearanceRadius(sunBody), parentLimit) <> "" RETURN FALSE.
		LOCAL movedEjection IS ejectionDeltaVForExit(orbitSpec, movedExit, fromBody, tSOI, stageTiming, precision, earliestBurnUT).
		IF movedEjection["deltaV"] >= invalidDeltaV RETURN FALSE.
		SET winningArrivalDV TO arrivalDeltaV(movedTrajectory["v_2"] - toBodyVelocity, toBody, captureRadius).
		SET winningTrajectory TO movedTrajectory.
		SET winningEjection TO movedEjection.
		SET bestTotalDV TO movedEjection["deltaV"] + winningArrivalDV.
		RETURN TRUE.
	}

	IF timeOfFlight > 0 {
		// The cheap part: for each usable solution, the exit velocity, the arrival cost, and a lower bound on the total.
		LOCAL candidates IS LIST().
		FOR shortWay IN LIST(TRUE, FALSE) {
			LOCAL startSeed IS longStartSeed.
			IF shortWay SET startSeed TO shortStartSeed.
			LOCAL trajectory IS solveLambert(departurePosition, shortWay, startSeed, arrivalPosition).

			// Move the start of the arc from the body's centre to where the ship leaves its SOI (estimated
			// along the exit heading), and again from that arc's own exit heading.
			FROM {LOCAL pass IS 1.} UNTIL pass > precision["exitPasses"] STEP {SET pass TO pass + 1.} DO {
				IF trajectory["Motion Type"] = "Failed" BREAK.
				LOCAL headingOffset IS (trajectory["v_1"] - fromBodyVelocity):NORMALIZED * soiRadius.
				LOCAL movedTrajectory IS solveLambert(departurePosition + headingOffset, shortWay, trajectory["Final Value"], arrivalPosition).
				IF movedTrajectory["Motion Type"] = "Failed" BREAK.
				SET trajectory TO movedTrajectory.
			}

			IF trajectory["Motion Type"] <> "Failed" {
				IF shortWay SET seed["shortSeed"] TO trajectory["Final Value"].
				ELSE SET seed["longSeed"] TO trajectory["Final Value"].

				LOCAL vExit IS trajectory["v_1"] - fromBodyVelocity.
				LOCAL vInfinitySquared IS vExit:MAG ^ 2 - 2 * orbitSpec["mu"] / soiRadius.
				LOCAL sweepAngle IS VANG(trajectory["r_1"], arrivalPosition).
				IF NOT shortWay SET sweepAngle TO 360 - sweepAngle.
				LOCAL arcProblem IS transferArcProblem(trajectory["r_1"], trajectory["v_1"], sweepAngle, sunBody:MU, bodyClearanceRadius(sunBody), parentLimit).
				IF vInfinitySquared <= 0 {
					IF failureRank < 2 {
						SET failureRank TO 2.
						SET failureReason TO "Cannot escape the departure SOI".
					}
				} ELSE IF arcProblem <> "" {
					SET rejectedArcs TO rejectedArcs + 1.
					IF failureRank < 3 {
						SET failureRank TO 3.
						SET failureReason TO arcProblem.
					}
				} ELSE {
					LOCAL arrivalDV IS arrivalDeltaV(trajectory["v_2"] - toBodyVelocity, toBody, captureRadius).
					candidates:ADD(LEXICON("trajectory", trajectory, "vExit", vExit, "arrivalDV", arrivalDV,
											"lowerBound", ejectionLowerBound(orbitSpec, SQRT(vInfinitySquared)) + arrivalDV)).
				}
			} ELSE IF failureRank < 1 {
				SET failureRank TO 1.
				SET failureReason TO "No convergence".
				IF trajectory:HASKEY("Failure Reason") SET failureReason TO trajectory["Failure Reason"].
			}
		}

		// Search the one that looks cheaper first.
		IF candidates:LENGTH = 2 {
			IF candidates[1]["lowerBound"] < candidates[0]["lowerBound"] {
				LOCAL firstCandidate IS candidates[0].
				SET candidates[0] TO candidates[1].
				SET candidates[1] TO firstCandidate.
			}
		}

		FOR candidate IN candidates {
			// Skip the expensive ejection search if even the best case can't beat what we have.
			IF candidate["lowerBound"] < bestTotalDV {
				IF candidate["lowerBound"] < lowestBound {
					SET lowestBound TO candidate["lowerBound"].
					SET lastExitVelocity TO candidate["vExit"].
				}
				LOCAL ejection IS ejectionDeltaVForExit(orbitSpec, candidate["vExit"], fromBody, tSOI, stageTiming, precision, earliestBurnUT).
				IF ejection["deltaV"] >= invalidDeltaV AND failureRank < 4 {
					SET failureRank TO 4.
					SET failureReason TO "No valid ejection burn".
				}
				IF ejection["deltaV"] < invalidDeltaV AND ejection["deltaV"] + candidate["arrivalDV"] < bestTotalDV {
					SET bestTotalDV TO ejection["deltaV"] + candidate["arrivalDV"].
					SET winningTrajectory TO candidate["trajectory"].
					SET winningEjection TO ejection.
					SET winningArrivalDV TO candidate["arrivalDV"].
				}
			}
		}

		// The exact exit point (full stage): re-solve from where the winning ejection really crosses the SOI
		// edge and re-price, twice at most.
		IF precision["exactExit"] AND winningTrajectory:ISTYPE("Lexicon") {
			FROM {LOCAL pass IS 1.} UNTIL pass > 2 STEP {SET pass TO pass + 1.} DO {
				LOCAL exactOffset IS soiExitOffset(winningEjection, soiRadius).
				IF exactOffset:MAG = 0 BREAK.
				IF (exactOffset - (winningTrajectory["r_1"] - departurePosition)):MAG < 0.005 * soiRadius BREAK.
				IF NOT repriceWinner(departurePosition + exactOffset, arrivalPosition) BREAK.
			}
		}
	
		// The aim stage (full stage, a body with a capture radius): move the arc's end from the destination's
		// centre to the aim point (arrivalAimOffset) and re-price, twice at most.
		IF precision["exactExit"] AND winningTrajectory:ISTYPE("Lexicon") AND captureRadius > 0 AND toBody:ISTYPE("Body") {
			LOCAL orbitNormal IS VCRS(arrivalPosition, toBodyVelocity).
			FROM {LOCAL pass IS 1.} UNTIL pass > 2 STEP {SET pass TO pass + 1.} DO {
				LOCAL aimOffset IS arrivalAimOffset(winningTrajectory["v_2"] - toBodyVelocity, toBody, captureRadius, orbitNormal).
				IF aimOffset:MAG = 0 BREAK.
				IF winningTrajectory:HASKEY("Aim Offset") {
					IF (aimOffset - winningTrajectory["Aim Offset"]):MAG < 0.002 * aimOffset:MAG BREAK.
				}
				IF NOT repriceWinner(winningTrajectory["r_1"], arrivalPosition + aimOffset) BREAK.
				SET winningTrajectory["Aim Offset"] TO aimOffset.
			}
		}
	}

	// The exact-timed burn for the exit velocity of the arc that won.
	IF exactTiming AND precision["exactExit"] AND winningTrajectory:ISTYPE("Lexicon") {
		LOCAL timedEjection IS ejectionDeltaVForExit(orbitSpec, winningTrajectory["v_1"] - fromBodyVelocity, fromBody, tSOI, TRUE, precision, earliestBurnUT).
		IF timedEjection["deltaV"] >= invalidDeltaV {
			SET lastExitVelocity TO winningTrajectory["v_1"] - fromBodyVelocity.
			SET winningTrajectory TO 0.
			SET bestTotalDV TO invalidDeltaV.
			SET failureReason TO "No valid ejection burn".
		} ELSE {
			SET winningEjection TO timedEjection.
			SET bestTotalDV TO timedEjection["deltaV"] + winningArrivalDV.
		}
	}

	// Copy into the caller's statsOut (never reassign it).
	IF winningTrajectory:ISTYPE("Lexicon") {
		FOR statKey IN winningTrajectory:KEYS {
			SET statsOut[statKey] TO winningTrajectory[statKey].
		}
		IF statsOut:HASKEY("Aim Offset") AND NOT winningTrajectory:HASKEY("Aim Offset") statsOut:REMOVE("Aim Offset").
		SET statsOut["Ejection"] TO winningEjection.
		SET statsOut["Arrival Delta V"] TO winningArrivalDV.
		SET statsOut["Exit Offset"] TO winningTrajectory["r_1"] - departurePosition.
	} ELSE {
		SET statsOut["Motion Type"] TO "Failed".
		SET statsOut["Failure Reason"] TO failureReason.
	}
	SET statsOut["Rejected Arcs"] TO rejectedArcs.
	IF winningTrajectory:ISTYPE("Lexicon") {
		// The exit velocity of the arc that won (bestExitShift in phaseLockedDeparture uses it).
		SET statsOut["Exit Velocity"] TO winningTrajectory["v_1"] - fromBodyVelocity.
	} ELSE {
		SET statsOut["Exit Velocity"] TO lastExitVelocity.
	}
	RETURN bestTotalDV.
}

// Returns a delegate f(tSOI, timeOfFlight, seed, statsOut) -> total dV (phase-free), for porkchopGrid
// and hillClimb2D. precision is from ejectionPrecision.
FUNCTION bindTransferDeltaV {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER orbitSpec.
	PARAMETER captureRadius IS 0.
	PARAMETER precision IS ejectionPrecision("full").

	LOCAL bound IS transferDeltaV@.
	SET bound TO bound:BIND(fromBody).
	SET bound TO bound:BIND(toBody).
	SET bound TO bound:BIND(sunBody).
	SET bound TO bound:BIND(orbitSpec).
	SET bound TO bound:BIND(captureRadius).
	SET bound TO bound:BIND(precision).
	RETURN bound.
}


// ----------------------------------------------------------------------------
// Exact timing, and the node
// ----------------------------------------------------------------------------

// Exact timing for a ship in a BOUND orbit: lock the departure to the best burn phase.
// The orbit repeats, so the cheapest timed burn is the phase-free best burn point at the repeat nearest
// the search's departure: tSOI = burn time + transit time + whole periods. Lambert is re-priced at that
// tSOI and the lock repeated until it settles; one exact-timing solve then gives the node's burn.
//   tSOI, timeOfFlight - from the search
//   earliestBurnUT     - no burn before this; the departure moves a period later instead
//   maxPasses          - at most this many lock passes
//   firstDeltaV, firstStats - the full-precision phase-free price at tSOI and its statsOut, if the caller
//                        already has them: they are used as the first lock pass
// Returns a LEXICON: "tSOI", "deltaV" (invalidDeltaV if nothing works), "stats" (stats["Ejection"] has
// the burn), "phaseFreeDeltaV", "passes" and "timings" (real seconds per stage, as text).
FUNCTION phaseLockedDeparture {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER orbitSpec.
	PARAMETER captureRadius.
	PARAMETER tSOI.
	PARAMETER timeOfFlight.
	PARAMETER earliestBurnUT IS 0.
	PARAMETER maxPasses IS 4.
	PARAMETER firstDeltaV IS invalidDeltaV.
	PARAMETER firstStats IS 0.

	LOCAL period IS orbitSpec["period"].
	LOCAL currentTSOI IS tSOI.
	LOCAL phaseFreeDeltaV IS invalidDeltaV.
	LOCAL previousDeltaV IS invalidDeltaV.
	LOCAL passesUsed IS 0.
	// Real-world seconds each stage took, as text, for the caller to print and log.
	LOCAL timingNotes IS LIST().
	LOCAL lapStart IS KUNIVERSE:REALWORLDTIME.
	FUNCTION lap {
		PARAMETER label.

		LOCAL nowTime IS KUNIVERSE:REALWORLDTIME.
		timingNotes:ADD(label + " " + ROUND(nowTime - lapStart, 1) + " s").
		SET lapStart TO nowTime.
	}

	// The SOI exit time of the burn a phase-free pricing found, at the repeat nearest nearTSOI with no burn
	// before earliestBurnUT.
	FUNCTION lockedExit {
		PARAMETER stats.
		PARAMETER nearTSOI.

		LOCAL ejection IS stats["Ejection"].
		LOCAL transit IS ejection["ejection"]["transitTime"].
		LOCAL exitUT IS orbitSpec["epoch"] + ejection["offset"] + transit.
		LOCAL locked IS exitUT + ROUND((nearTSOI - exitUT) / period) * period.
		UNTIL locked - transit >= earliestBurnUT {
			SET locked TO locked + period.
		}
		RETURN locked.
	}

	UNTIL passesUsed >= maxPasses {
		LOCAL stats IS LEXICON().
		LOCAL totalDV IS invalidDeltaV.
		IF passesUsed = 0 AND firstStats:ISTYPE("Lexicon") {
			SET stats TO firstStats.
			SET totalDV TO firstDeltaV.
			lap("Lock pass 1 (reused)").
		} ELSE {
			SET totalDV TO transferDeltaV(fromBody, toBody, sunBody, orbitSpec, captureRadius, ejectionPrecision("full"),
											currentTSOI, timeOfFlight, LEXICON(), stats, FALSE, 0).
			lap("Lock pass " + (passesUsed + 1)).
		}
		IF totalDV >= invalidDeltaV BREAK.
		SET phaseFreeDeltaV TO totalDV.
		SET passesUsed TO passesUsed + 1.

		// When the best burn point is reached, and when the ship then crosses the SOI edge.
		LOCAL lockedTSOI IS lockedExit(stats, currentTSOI).
		LOCAL movement IS ABS(lockedTSOI - currentTSOI).
		SET currentTSOI TO lockedTSOI.
		// Settled when tSOI moves under 0.2% of the period (the burn-point search's resolution), or when the
		// price agrees with the last pass to 0.1 m/s and tSOI moved under 0.5%: the exact-timing solve fails
		// if tSOI is tens of seconds from where the best burn really exits.
		IF movement < 0.002 * period BREAK.
		IF passesUsed >= 2 AND ABS(totalDV - previousDeltaV) < 0.1 AND movement < 0.005 * period BREAK.
		SET previousDeltaV TO totalDV.
	}

	LOCAL result IS LEXICON("tSOI", currentTSOI, "deltaV", invalidDeltaV, "stats", LEXICON(),
							"phaseFreeDeltaV", phaseFreeDeltaV, "passes", passesUsed, "timings", timingNotes).
	IF phaseFreeDeltaV >= invalidDeltaV RETURN result.

	// The shift (s) from aroundTSOI to the exit time where the exact-timed burn for an exit velocity costs
	// least, by the game's own prediction: a coarse scan of +-100 s, then a finer one. Returns the shift and
	// the burn's price there (invalidDeltaV if none).
	FUNCTION bestExitShift {
		PARAMETER exitVelocity.
		PARAMETER aroundTSOI.

		LOCAL bestShift IS 0.
		LOCAL bestShiftDV IS invalidDeltaV.
		LOCAL soiPasses IS ejectionPrecision("full")["soiIterations"].
		FOR scanRange IN LIST(LIST(-100, 100, 10), LIST(-8, 8, 2)) {
			LOCAL centre IS bestShift.
			IF scanRange[2] = 10 SET centre TO 0.
			FROM {LOCAL shift IS centre + scanRange[0].} UNTIL shift > centre + scanRange[1] STEP {SET shift TO shift + scanRange[2].} DO {
				LOCAL shiftedDV IS ejectionForExitTime(orbitSpec, exitVelocity, aroundTSOI + shift, fromBody:SOIRADIUS, earliestBurnUT, soiPasses)["deltaV"].
				IF shiftedDV < bestShiftDV {
					SET bestShiftDV TO shiftedDV.
					SET bestShift TO shift.
				}
			}
		}
		RETURN LEXICON("shift", bestShift, "deltaV", bestShiftDV).
	}

	// The exact-timing solve at the locked departure: its burn is the node's. If it finds no burn, move tSOI
	// to the best exit time (bestExitShift) and try again, up to three solves.
	LOCAL finalStats IS LEXICON().
	LOCAL finalDV IS invalidDeltaV.
	FROM {LOCAL attempt IS 1.} UNTIL attempt > 3 STEP {SET attempt TO attempt + 1.} DO {
		SET finalStats TO LEXICON().
		SET finalDV TO transferDeltaV(fromBody, toBody, sunBody, orbitSpec, captureRadius, ejectionPrecision("full"),
										currentTSOI, timeOfFlight, LEXICON(), finalStats, TRUE, earliestBurnUT).
		lap("Exact solve " + attempt).
		IF finalDV < invalidDeltaV AND finalStats:HASKEY("Ejection") BREAK.
		IF attempt < 3 {
			// Use the best exit time a little early: later exit times fail first.
			IF NOT finalStats:HASKEY("Exit Velocity") BREAK.
			LOCAL found IS bestExitShift(finalStats["Exit Velocity"], currentTSOI).
			lap("Retry scan " + attempt).
			IF found["deltaV"] >= invalidDeltaV BREAK.
			SET currentTSOI TO currentTSOI + found["shift"] - 4.
			SET result["tSOI"] TO currentTSOI.
			SET result["passes"] TO result["passes"] + 1.
		}
	}
	IF finalDV < invalidDeltaV AND finalStats:HASKEY("Ejection") {
		SET result["deltaV"] TO finalDV.
		SET result["stats"] TO finalStats.
	}
	RETURN result.
}

// The departure for a ship on an escape orbit (phaseLockedDeparture's counterpart). The search priced with
// the exit time free and tSOI pinned to the ship's own exit, so this moves tSOI to the burn's real exit time
// and prices again until they agree, then searches the flight time again there and settles once more.
//   tSOI, timeOfFlight - from the search
//   maxPasses          - at most this many passes per settling (it stops within 2 s)
// Returns a LEXICON: "tSOI", "flightTime", "deltaV" (invalidDeltaV if nothing works), "stats",
// "phaseFreeDeltaV" (the same price) and "passes".
FUNCTION escapeLockedDeparture {
	PARAMETER fromBody.
	PARAMETER toBody.
	PARAMETER sunBody.
	PARAMETER orbitSpec.
	PARAMETER captureRadius.
	PARAMETER tSOI.
	PARAMETER timeOfFlight.
	PARAMETER maxPasses IS 5.

	// The search prices with the exit pinned to the ship's own (orbitSpec["pinExit"]); here tSOI is the one given.
	LOCAL freeSpec IS orbitSpec:COPY.
	SET freeSpec["pinExit"] TO FALSE.

	LOCAL currentTSOI IS tSOI.
	LOCAL flight IS timeOfFlight.
	LOCAL passesUsed IS 0.
	LOCAL best IS LEXICON("tSOI", tSOI, "deltaV", invalidDeltaV, "stats", LEXICON(),
							"phaseFreeDeltaV", invalidDeltaV, "passes", 0, "flightTime", timeOfFlight).

	// The price of a flight time at the departure the lock has settled on (quick precision: it is only searched).
	FUNCTION costAtFlight {
		PARAMETER flightTime.

		RETURN transferDeltaV(fromBody, toBody, sunBody, freeSpec, captureRadius, ejectionPrecision("quick"),
								currentTSOI, flightTime, LEXICON(), LEXICON(), FALSE, 0).
	}

	// Phase 1 settles the departure for the search's flight time; phase 2 searches the flight time again
	// there (+-10%) and settles again. The cheaper result wins.
	FOR phase IN LIST(1, 2) {
		IF phase = 2 {
			IF best["deltaV"] >= invalidDeltaV BREAK.
			SET currentTSOI TO best["tSOI"].
			SET flight TO goldenSectionMinimum(costAtFlight@, flight * 0.9, flight * 1.1, 10).
		}

		LOCAL phaseResult IS LEXICON("deltaV", invalidDeltaV).
		LOCAL passesInPhase IS 0.
		UNTIL passesInPhase >= maxPasses {
			LOCAL stats IS LEXICON().
			LOCAL totalDV IS transferDeltaV(fromBody, toBody, sunBody, freeSpec, captureRadius, ejectionPrecision("full"),
											currentTSOI, flight, LEXICON(), stats, FALSE, 0).
			SET passesInPhase TO passesInPhase + 1.
			SET passesUsed TO passesUsed + 1.
			IF totalDV >= invalidDeltaV OR NOT stats:HASKEY("Ejection") BREAK.
			LOCAL ejection IS stats["Ejection"].
			IF NOT ejection:HASKEY("exitUT") BREAK.

			// Each pass is priced at the tSOI it used, so the last one is the settled one; the first one need not be.
			SET phaseResult TO LEXICON("tSOI", currentTSOI, "deltaV", totalDV, "stats", stats,
										"phaseFreeDeltaV", totalDV, "passes", passesUsed, "flightTime", flight).
			IF ABS(ejection["exitUT"] - currentTSOI) < 2 BREAK.
			SET currentTSOI TO ejection["exitUT"].
		}
		IF phaseResult["deltaV"] < best["deltaV"] SET best TO phaseResult.
	}
	SET best["passes"] TO passesUsed.
	RETURN best.
}

// The bodies whose SOIs the ship's predicted path passes through after the maneuver node, in order.
// Empty if there is no node. Only as many patches as KSP predicts show up.
//   patchStarts - a LIST that gets the UT each patch after the first begins
FUNCTION predictedSOIPath {
	PARAMETER patchStarts IS LIST().

	LOCAL soiPath IS LIST().
	// A tick, so KSP has re-solved the flight plan for a node that was only just added.
	WAIT 0.
	IF NOT HASNODE RETURN soiPath.

	LOCAL patch IS NEXTNODE:ORBIT.
	soiPath:ADD(patch:BODY:NAME).
	UNTIL NOT patch:HASNEXTPATCH {
		patchStarts:ADD(TIME:SECONDS + patch:NEXTPATCHETA).
		SET patch TO patch:NEXTPATCH.
		soiPath:ADD(patch:BODY:NAME).
	}
	RETURN soiPath.
}

// Checks the predicted SOI path of the node just made. It should be the departure body (same SOI: the
// central body), the central body, then the destination body's SOI. Before the destination, another
// body's SOI, the departure body again, or never reaching a destination body is a problem.
//   fromOrbitable - the source (the departure body, or the ship in a same-SOI transfer)
//   toOrbitable   - the destination
//   sameSOI       - TRUE for a transfer inside one SOI
//   arrivalUT     - same SOI: the planned arrival (0 for none); a patch that begins after it is not a problem
// Returns a LEXICON: "path" (LIST of body names), "text" (the path joined by " > ") and "problems" (LIST of messages).
FUNCTION checkTransferSOIPath {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER sameSOI.
	PARAMETER arrivalUT IS 0.

	LOCAL centralName IS fromOrbitable:BODY:NAME.
	LOCAL leadingName IS fromOrbitable:NAME.
	IF sameSOI SET leadingName TO centralName.

	LOCAL patchStarts IS LIST().
	LOCAL soiPath IS predictedSOIPath(patchStarts).
	LOCAL problems IS LIST().
	LOCAL pathText IS "".
	LOCAL targetIsBody IS toOrbitable:ISTYPE("Body").
	LOCAL reachedTarget IS FALSE.

	FOR index IN RANGE(0, soiPath:LENGTH) {
		LOCAL bodyName IS soiPath[index].
		IF index > 0 { SET pathText TO pathText + " > ". }
		SET pathText TO pathText + bodyName.

		IF NOT reachedTarget AND index > 0 {
			LOCAL problem IS "".
			IF targetIsBody AND bodyName = toOrbitable:NAME {
				SET reachedTarget TO TRUE.
			} ELSE IF bodyName = centralName {
				// back in (or still in) the central body's SOI: expected
			} ELSE IF bodyName = leadingName {
				SET problem TO "returns to " + bodyName + "'s SOI before the target".
			} ELSE {
				SET problem TO "crosses " + bodyName + "'s SOI before the target".
			}
			// A patch that begins after the planned arrival is after the target, not before it.
			IF problem <> "" AND sameSOI AND arrivalUT > 0 AND index - 1 < patchStarts:LENGTH {
				IF patchStarts[index - 1] >= arrivalUT SET problem TO "".
			}
			IF problem <> "" AND NOT problems:CONTAINS(problem) problems:ADD(problem).
		}
	}

	IF soiPath:LENGTH = 0 {
		problems:ADD("no predicted path (no node?)").
	} ELSE IF targetIsBody AND NOT reachedTarget {
		problems:ADD("no " + toOrbitable:NAME + " encounter predicted").
	}
	RETURN LEXICON("path", soiPath, "text", pathText, "problems", problems).
}

// Adds a maneuver node for an ejection (an "Ejection" LEXICON) with the whole burn vector. The sign of the
// node's normal axis depends on handedness, so both are tried against the node's own :DELTAV.
// Returns LEXICON("created", "verified", "prograde", "normal", "radial", "nodeError").
FUNCTION addEjectionNode {
	PARAMETER ejection.
	PARAMETER clearExistingNodes IS TRUE.

	IF clearExistingNodes {
		clearManeuverNodes().
	}

	// The node's own axes at the burn: prograde along the velocity, normal along the
	// orbit normal, radial the remaining outward axis.
	LOCAL dvVector IS ejection["dvVector"].
	LOCAL progradeUnit IS ejection["parkVelocity"]:NORMALIZED.
	LOCAL normalUnit IS VCRS(ejection["burnPosition"], ejection["parkVelocity"]):NORMALIZED.
	LOCAL radialUnit IS VCRS(progradeUnit, normalUnit):NORMALIZED.
	IF VDOT(radialUnit, ejection["burnPosition"]) < 0 SET radialUnit TO -radialUnit.
	LOCAL progradeDV IS VDOT(dvVector, progradeUnit).
	LOCAL normalDV IS VDOT(dvVector, normalUnit).
	LOCAL radialDV IS VDOT(dvVector, radialUnit).

	LOCAL tolerance IS dvVector:MAG * 0.01.
	LOCAL firstNode IS NODE(ejection["burnUT"], radialDV, normalDV, progradeDV).
	ADD firstNode.
	LOCAL nodeError IS (firstNode:DELTAV - dvVector):MAG.
	IF nodeError > tolerance {
		REMOVE firstNode.
		LOCAL flippedNode IS NODE(ejection["burnUT"], radialDV, -normalDV, progradeDV).
		ADD flippedNode.
		LOCAL flippedError IS (flippedNode:DELTAV - dvVector):MAG.
		IF flippedError > nodeError {
			// Neither matches; fall back to the first and let "verified" say so.
			REMOVE flippedNode.
			ADD NODE(ejection["burnUT"], radialDV, normalDV, progradeDV).
		} ELSE {
			SET nodeError TO flippedError.
		}
	}
	RETURN LEXICON("created", TRUE, "verified", nodeError <= tolerance,
					"prograde", progradeDV, "normal", normalDV, "radial", radialDV, "nodeError", nodeError).
}

// Checks a same-SOI transfer's node against the game's prediction: (1) the periapsis and apoapsis of the
// orbit after the node against the plan's arc; (2) the ship's distance from the destination at the planned
// arrival, from POSITIONAT. (2) only counts if the prediction follows the node: the ship's position at
// arrival must have moved from shipBefore.
//   ejection     - the node's burn, as addEjectionNode took it
//   toOrbitable  - the destination; centralBody - the body both orbit
//   arrivalUT    - the planned arrival
//   shipBefore   - POSITIONAT(SHIP, arrivalUT), taken before the node was added
//   aimOffset    - statsOut["Aim Offset"], or V(0, 0, 0)
//   captureRadius - m from the destination body's centre the plan passes it at (0 for none, or a vessel). With
//                  one, the destination's gravity bends the path away from the aim point, so the game's
//                  periapsis at the destination is what is compared, not the position at arrival
// Returns a LEXICON: "available", "miss" (m from the destination at arrival), "deviation" (m from where the
// plan aimed), "nodeMoved" (m), "planPeriapsis", "gamePeriapsis" and, for a bound orbit, "planApoapsis",
// "gameApoapsis" (altitudes, m). With a capture radius: "captureAimed" (TRUE), and, if the game predicts an
// encounter, "planCapture" and "gameCapture" (periapsis altitudes at the destination, m) and
// "captureTolerance" (m: half the capture radius) and "captureFloor" (m: the lowest safe periapsis altitude,
// the top of the atmosphere or 0).
FUNCTION checkNodeEncounter {
	PARAMETER ejection.
	PARAMETER toOrbitable.
	PARAMETER centralBody.
	PARAMETER arrivalUT.
	PARAMETER shipBefore.
	PARAMETER aimOffset IS V(0, 0, 0).
	PARAMETER captureRadius IS 0.

	LOCAL result IS LEXICON("available", FALSE, "miss", 0, "deviation", 0, "nodeMoved", 0).
	// A tick, so KSP has re-solved the flight plan for a node that was only just added.
	WAIT 0.
	IF NOT HASNODE RETURN result.

	LOCAL planSpec IS makeOrbitSpec(ejection["burnPosition"], ejection["parkVelocity"] + ejection["dvVector"],
									ejection["burnUT"], centralBody:MU, 0).
	LOCAL nodeOrbit IS NEXTNODE:ORBIT.
	SET result["planPeriapsis"] TO planSpec["periapsisRadius"] - centralBody:RADIUS.
	SET result["gamePeriapsis"] TO nodeOrbit:PERIAPSIS.
	IF planSpec["eccentricity"] < 1 {
		SET result["planApoapsis"] TO planSpec["sma"] * (1 + planSpec["eccentricity"]) - centralBody:RADIUS.
		SET result["gameApoapsis"] TO nodeOrbit:APOAPSIS.
	}

	LOCAL shipAfter IS POSITIONAT(SHIP, arrivalUT).
	SET result["nodeMoved"] TO (shipAfter - shipBefore):MAG.
	IF result["nodeMoved"] > 1 {
		LOCAL targetPosition IS POSITIONAT(toOrbitable, arrivalUT).
		SET result["miss"] TO (shipAfter - targetPosition):MAG.
		SET result["deviation"] TO (shipAfter - targetPosition - aimOffset):MAG.
		SET result["available"] TO TRUE.
	}
	IF captureRadius > 0 AND toOrbitable:ISTYPE("Body") {
		SET result["captureAimed"] TO TRUE.
		LOCAL patch IS nodeOrbit.
		LOCAL foundPatch IS FALSE.
		UNTIL foundPatch OR NOT patch:HASNEXTPATCH {
			SET patch TO patch:NEXTPATCH.
			IF patch:BODY:NAME = toOrbitable:NAME SET foundPatch TO TRUE.
		}
		IF foundPatch {
			SET result["planCapture"] TO captureRadius - toOrbitable:RADIUS.
			SET result["gameCapture"] TO patch:PERIAPSIS.
			SET result["captureTolerance"] TO 0.5 * captureRadius.
			SET result["captureFloor"] TO bodyClearanceRadius(toOrbitable) - toOrbitable:RADIUS.
		}
	}
	RETURN result.
}


// ----------------------------------------------------------------------------
// Parking-plane design
// ----------------------------------------------------------------------------

// The normal of an orbit plane from its inclination and LAN, by rotating the body's spin axis.
// KSP's coordinates are left-handed: the node is the prime vector turned by +LAN about the spin axis,
// and the plane tilts by -inclination about the node.
FUNCTION getOrbitPlaneNormal {
	PARAMETER centralBody.
	PARAMETER inclinationDeg.
	PARAMETER lanDeg.

	LOCAL equatorialNormal IS centralBody:ANGULARVEL:NORMALIZED.
	LOCAL primeInPlane IS VXCL(equatorialNormal, SOLARPRIMEVECTOR):NORMALIZED.
	LOCAL ascendingNodeDir IS ANGLEAXIS(lanDeg, equatorialNormal) * primeInPlane.
	RETURN (ANGLEAXIS(-inclinationDeg, ascendingNodeDir) * equatorialNormal):NORMALIZED.
}


// The minimum-inclination plane that contains v_infinity's direction: its normal is the spin axis
// projected perpendicular to v_infinity. "verificationResidual" feeds the result back through
// getOrbitPlaneNormal and should be ~0.
FUNCTION computeMinimumInclinationPlane {
	PARAMETER centralBody.
	PARAMETER vInfinityVector.

	LOCAL equatorialNormal IS centralBody:ANGULARVEL:NORMALIZED.
	LOCAL primeInPlane IS VXCL(equatorialNormal, SOLARPRIMEVECTOR):NORMALIZED.
	LOCAL eastInPlane IS VCRS(equatorialNormal, primeInPlane):NORMALIZED.

	LOCAL vHat IS vInfinityVector:NORMALIZED.
	LOCAL minNormal IS VXCL(vHat, equatorialNormal).
	IF minNormal:MAG < 1e-6 {
		// v_infinity lies along the spin axis, so every plane that contains the axis qualifies (all are
		// polar, inclination 90). Any of them will do; use the one whose normal is the prime vector.
		SET minNormal TO primeInPlane.
	} ELSE SET minNormal TO minNormal:NORMALIZED.
	LOCAL inclination IS VANG(minNormal, equatorialNormal).
	// The ascending node is VCRS(minNormal, pole) (not VCRS(pole, minNormal)) because of the
	// left-handed tilt described at getOrbitPlaneNormal.
	LOCAL ascendingNodeDir IS VCRS(minNormal, equatorialNormal).
	// If v_infinity lies in the equatorial plane the best orbit is equatorial (inclination 0), where the
	// ascending node is undefined (the plane is the same for any LAN), so use a LAN of 0.
	LOCAL lan IS 0.
	IF ascendingNodeDir:MAG > 1e-6 {
		SET ascendingNodeDir TO ascendingNodeDir:NORMALIZED.
		SET lan TO normalizeAngle360(ARCTAN2(VDOT(ascendingNodeDir, eastInPlane), VDOT(ascendingNodeDir, primeInPlane))).
	}

	LOCAL checkNormal IS getOrbitPlaneNormal(centralBody, inclination, lan).
	LOCAL verificationResidual IS 90 - VANG(vInfinityVector, checkNormal).

	RETURN LEXICON("inclination", inclination, "lan", lan, "verificationResidual", verificationResidual).
}

// The ascending node(s) of the plane of a given inclination that contains v_infinity (for a launch-site
// latitude above the minimum inclination). With v_infinity as (vx, vy, vz) in the (prime, east, spin axis)
// basis, the condition is
//     vx*SIN(LAN) - vy*COS(LAN) = vz*COS(i)/SIN(i)
// which has zero, one or two solutions. Returns them as a LIST.
FUNCTION solveLANForInclination {
	PARAMETER centralBody.
	PARAMETER vInfinityVector.
	PARAMETER inclinationDeg.

	LOCAL equatorialNormal IS centralBody:ANGULARVEL:NORMALIZED.
	LOCAL primeInPlane IS VXCL(equatorialNormal, SOLARPRIMEVECTOR):NORMALIZED.
	LOCAL eastInPlane IS VCRS(equatorialNormal, primeInPlane):NORMALIZED.
	LOCAL vHat IS vInfinityVector:NORMALIZED.

	LOCAL vx IS VDOT(vHat, primeInPlane).
	LOCAL vy IS VDOT(vHat, eastInPlane).
	LOCAL vz IS VDOT(vHat, equatorialNormal).

	IF (inclinationDeg <= 0.0001) OR (inclinationDeg >= 179.9999) RETURN LIST().

	LOCAL pos IS SQRT(vx ^ 2 + vy ^ 2).
	IF pos < 1e-9 {
		// v_infinity lies along the spin axis. The plane contains it only if the plane is polar
		// (inclination 90), and then every LAN works; report two opposite ones. Any other inclination has no solution.
		IF ABS(COS(inclinationDeg)) < 1e-6 RETURN LIST(0, 180).
		RETURN LIST().
	}
	LOCAL phi IS ARCTAN2(vy, vx).
	LOCAL rhs IS vz * COS(inclinationDeg) / (SIN(inclinationDeg) * pos).
	IF ABS(rhs) > 1.0001 RETURN LIST(). // this inclination is below the true minimum - shouldn't happen if the caller respects it
	LOCAL clampedRhs IS MAX(-1, MIN(1, rhs)).
	LOCAL asinVal IS ARCSIN(clampedRhs).

	RETURN LIST(normalizeAngle360(phi + asinVal), normalizeAngle360(phi + 180 - asinVal)).
}

// The parking plane to launch into: the minimum-inclination plane, raised to the launch site's latitude
// if that is higher, with the node re-solved so the plane still contains v_infinity.
FUNCTION computeRecommendedParkingPlane {
	PARAMETER centralBody.
	PARAMETER vInfinityVector.
	PARAMETER launchLatitude.

	LOCAL pureMin IS computeMinimumInclinationPlane(centralBody, vInfinityVector).
	LOCAL latitudeFloor IS ABS(launchLatitude).
	LOCAL binding IS latitudeFloor > pureMin["inclination"].

	LOCAL finalInclination IS MAX(pureMin["inclination"], latitudeFloor).
	LOCAL finalLan IS pureMin["lan"].
	LOCAL alternateLan IS pureMin["lan"].

	IF binding {
		LOCAL lanOptions IS solveLANForInclination(centralBody, vInfinityVector, finalInclination).
		IF lanOptions:LENGTH = 2 {
			// Take the node nearer the unconstrained one; the other is the alternate.
			LOCAL diff1 IS ABS(normalizeAngle180(lanOptions[0] - pureMin["lan"])).
			LOCAL diff2 IS ABS(normalizeAngle180(lanOptions[1] - pureMin["lan"])).
			IF diff1 <= diff2 {
				SET finalLan TO lanOptions[0].
				SET alternateLan TO lanOptions[1].
			} ELSE {
				SET finalLan TO lanOptions[1].
				SET alternateLan TO lanOptions[0].
			}
		}
		// No solution leaves the pure-minimum values, and verificationResidual shows it.
	}

	LOCAL checkNormal IS getOrbitPlaneNormal(centralBody, finalInclination, finalLan).
	LOCAL verificationResidual IS 90 - VANG(vInfinityVector, checkNormal).

	RETURN LEXICON("inclination", finalInclination,
	               "lan", finalLan,
	               "alternateLan", alternateLan,
	               "latitudeConstraintBinding", binding,
	               "pureMinimumInclination", pureMin["inclination"],
	               "verificationResidual", verificationResidual).
}


// ============================================================================
// Choosing the endpoints of a transfer, and transfers inside a single SOI
// ============================================================================

// Works out what a transfer goes from and to, from the destination alone.
//   destinationName - a body or a vessel, by name or as the object (see resolveOrbitable)
//   sourceName      - "" to infer the source from where the ship is; otherwise its name
// With no source given:
//   - the destination orbits the ship's body: from the SHIP (a same-SOI transfer)
//   - it orbits that body's parent: from the ship's body
//   - a VESSEL at a moon of the ship's body or of its parent: to that moon ("destinationVessel" is the vessel)
//   - a MOON of another planet, or of a moon of the ship's body: to the moon's planet ("destinationMoon" is
//     the moon); reaching the moon is a second transfer from there
// Anything else is an error. A given source must orbit the same body as the destination.
// Returns a LEXICON: "error" ("None", or a message), "from", "to", "sameSOI" (the source is a vessel),
// "destinationVessel" and "destinationMoon" (0 if not used).
FUNCTION resolveTransferEndpoints {
	PARAMETER destinationName.
	PARAMETER sourceName IS "".

	LOCAL endpoints IS LEXICON("error", "None", "from", 0, "to", 0, "sameSOI", FALSE, "destinationVessel", 0, "destinationMoon", 0).

	LOCAL toOrbitable IS resolveOrbitable(destinationName).
	IF toOrbitable:ISTYPE("Scalar") {
		SET endpoints["error"] TO destinationName + " does not exist!".
		RETURN endpoints.
	}

	LOCAL here IS SHIP:BODY.
	LOCAL hereParent IS "".
	IF here:HASBODY SET hereParent TO here:BODY:NAME.
	LOCAL toParent IS "".
	IF toOrbitable:HASBODY SET toParent TO toOrbitable:BODY:NAME.
	LOCAL fromOrbitable IS 0.
	IF sourceName <> "" {
		SET fromOrbitable TO resolveOrbitable(sourceName).
		IF fromOrbitable:ISTYPE("Scalar") {
			SET endpoints["error"] TO sourceName + " does not exist!".
			RETURN endpoints.
		}
	} ELSE {
		// Two vessels can share a name, so a vessel with the ship's name is the ship only if it is the ship.
		IF toOrbitable:ISTYPE("Vessel") {
			IF toOrbitable:NAME = SHIP:NAME AND toOrbitable = SHIP {
				SET endpoints["error"] TO toOrbitable:NAME + " is the ship itself!".
				RETURN endpoints.
			}
		}
		IF toOrbitable:ISTYPE("Body") AND toOrbitable:NAME = here:NAME {
			SET endpoints["error"] TO "The ship is already in " + here:NAME + "'s sphere of influence!".
			RETURN endpoints.
		}
		// The parent of the body a vessel orbits (in steps: AND does not short-circuit).
		LOCAL vesselBodyParent IS "".
		IF toOrbitable:ISTYPE("Vessel") {
			IF toOrbitable:BODY:HASBODY SET vesselBodyParent TO toOrbitable:BODY:BODY:NAME.
		}
		// The parent of a moon's planet.
		LOCAL moonPlanetParent IS "".
		IF toOrbitable:ISTYPE("Body") AND toParent <> "" {
			IF toOrbitable:BODY:HASBODY SET moonPlanetParent TO toOrbitable:BODY:BODY:NAME.
		}
		IF toParent = here:NAME {
			SET fromOrbitable TO SHIP.
		} ELSE IF toParent <> "" AND toParent = hereParent {
			SET fromOrbitable TO here.
		} ELSE IF vesselBodyParent <> "" AND vesselBodyParent = here:NAME {
			// A vessel at a moon of the ship's body.
			SET endpoints["destinationVessel"] TO toOrbitable.
			SET toOrbitable TO toOrbitable:BODY.
			SET toParent TO here:NAME.
			SET fromOrbitable TO SHIP.
		} ELSE IF vesselBodyParent <> "" AND vesselBodyParent = hereParent {
			// A vessel at a moon of the ship's body's parent.
			SET endpoints["destinationVessel"] TO toOrbitable.
			SET toOrbitable TO toOrbitable:BODY.
			SET toParent TO hereParent.
			SET fromOrbitable TO here.
		} ELSE IF moonPlanetParent <> "" AND moonPlanetParent = here:NAME {
			// A moon of a moon of the ship's body.
			SET endpoints["destinationMoon"] TO toOrbitable.
			SET toOrbitable TO toOrbitable:BODY.
			SET toParent TO here:NAME.
			SET fromOrbitable TO SHIP.
		} ELSE IF moonPlanetParent <> "" AND moonPlanetParent = hereParent {
			// A moon of another planet.
			SET endpoints["destinationMoon"] TO toOrbitable.
			SET toOrbitable TO toOrbitable:BODY.
			SET toParent TO hereParent.
			SET fromOrbitable TO here.
		} ELSE {
			SET endpoints["error"] TO toOrbitable:NAME + " (orbiting " + toParent + ") is in a different system from the ship (in " + here:NAME + "'s sphere of influence)!".
			RETURN endpoints.
		}
	}

	// Names are not unique: the same name is the same orbitable only if the objects are equal too.
	IF fromOrbitable:NAME = toOrbitable:NAME AND fromOrbitable = toOrbitable {
		SET endpoints["error"] TO "The source and the destination are the same!".
		RETURN endpoints.
	}
	LOCAL fromParent IS "".
	IF fromOrbitable:HASBODY SET fromParent TO fromOrbitable:BODY:NAME.
	IF fromParent = "" OR fromParent <> toParent {
		SET endpoints["error"] TO fromOrbitable:NAME + " and " + toOrbitable:NAME + " do not orbit the same body!".
		RETURN endpoints.
	}

	SET endpoints["from"] TO fromOrbitable.
	SET endpoints["to"] TO toOrbitable.
	SET endpoints["sameSOI"] TO fromOrbitable:ISTYPE("Vessel").
	RETURN endpoints.
}

// The UT at which an orbitable's orbit changes patch (an SOI change), or 0 if it has no next patch.
FUNCTION orbitPatchUT {
	PARAMETER orbitable.

	IF orbitable:ORBIT:HASNEXTPATCH RETURN TIME:SECONDS + orbitable:ORBIT:NEXTPATCHETA.
	RETURN 0.
}

// A size for an orbit around centralBody: the semi-major axis if it is bound, else (an escape
// orbit has no semi-major axis to speak of) the orbitable's distance from the central body now.
FUNCTION orbitSizeRadius {
	PARAMETER orbitable.
	PARAMETER centralBody.

	IF orbitable:ORBIT:ECCENTRICITY < 1 RETURN orbitable:ORBIT:SEMIMAJORAXIS.
	RETURN (orbitable:POSITION - centralBody:POSITION):MAG.
}

// A time scale for an orbit around centralBody: its period if it is bound, else (an escape orbit has
// no period) the period of a circular orbit at the orbitable's distance from the central body now.
FUNCTION orbitTimeScale {
	PARAMETER orbitable.
	PARAMETER centralBody.

	IF orbitable:ORBIT:ECCENTRICITY < 1 RETURN orbitable:ORBIT:PERIOD.
	RETURN 2 * CONSTANT:PI * SQRT(orbitSizeRadius(orbitable, centralBody) ^ 3 / centralBody:MU).
}

// How far out, as a fraction of the central body's SOI radius, an arrival may be in a same-SOI transfer.
// Further out the real path changes patch, so the two-body arc stops being the orbit the ship flies.
// sameSOITransferDeltaV rejects a later arrival and buildTransferWindow ends its flight times there.
FUNCTION soiEdgeFraction {
	RETURN 0.95.
}

// Seconds from now until an orbitable, on its escape orbit around centralBody, is next at the given
// distance from the central body's centre on its way out (radius, m). 0 if it is already further out
// than that on the way out, -1 if the orbit never gets that close (a periapsis above the radius) or is
// not an escape orbit. Uses the orbit's own elements, so it holds past a patch change.
FUNCTION orbitTimeToRadius {
	PARAMETER orbitable.
	PARAMETER centralBody.
	PARAMETER radius.

	LOCAL eccentricity IS orbitable:ORBIT:ECCENTRICITY.
	IF eccentricity <= 1 RETURN -1.
	LOCAL semiMajorAbs IS ABS(orbitable:ORBIT:SEMIMAJORAXIS).
	LOCAL semiLatus IS semiMajorAbs * (eccentricity ^ 2 - 1).
	LOCAL cosAnomaly IS (semiLatus / radius - 1) / eccentricity.
	IF ABS(cosAnomaly) > 1 RETURN -1.
	LOCAL wantedAnomaly IS ARCCOS(cosAnomaly).
	LOCAL nowAnomaly IS orbitable:ORBIT:TRUEANOMALY.
	IF nowAnomaly > 180 SET nowAnomaly TO nowAnomaly - 360.
	IF nowAnomaly >= wantedAnomaly RETURN 0.
	RETURN hyperbolaTransitTime(centralBody:MU, SQRT(centralBody:MU / semiMajorAbs), eccentricity, nowAnomaly, wantedAnomaly).
}

// The search window for a transfer between two orbitables that orbit the same body: the departure and
// flight-time samples. Either orbit may be an escape orbit.
//   endpoints        - from resolveTransferEndpoints
//   startOffset      - s from now to the start of the first window (>= 30)
//   departureWindows - how many windows to search, back to back
//   samplesPerWindow - departure times per window; below 1 chooses a default
//   tofSamples       - flight times; below 1 chooses a default
//   coarse           - TRUE for a search that is refined afterwards, FALSE for a plot: only affects the defaults
//   searchSpan       - s, the length of the departure range in place of departureWindows windows (-1: not used)
//   departureCount   - the number of departure times in all (-1: from samplesPerWindow and the range)
// A window: between bodies, a synodic period. In the same SOI, a synodic period or four ship orbits,
// whichever is shorter. With an escape orbit, the time to the first SOI change of either orbit, or searchSpan.
// The search stops where no flight could arrive: the destination's last usable moment is its SOI change or,
// in the same SOI, the time it reaches soiEdgeFraction of the SOI radius.
// Defaults ("period": of a bound orbit, or see orbitTimeScale):
//   - between bodies: 8 (coarse) or 24 (fine) departures per period of the quicker orbit, within 4 to 24
//     (coarse) or 40 to 120 (fine); 5 or 41 flight times
//   - same SOI: 12 (coarse) or 24 (fine) departures per ship orbit (12 to 240); 7 or 31 flight times
// Flight times run from 0.5 to 4 times the Hohmann time.
// Returns a LEXICON. "error" is "None", or a message with no other key set. Otherwise:
//   "sunBody"                          - the body both orbit
//   "synodicPeriod", "hohmannTime" (s) - the synodic period is 0 with an escape orbit
//   "hyperbolic"                       - TRUE if either orbit is an escape orbit
//   "windowLength" (s), "samplesPerWindow"
//   "startTime", "departureStart", "departureEnd" - UT; departures are evenly spaced from the start and stop short of the end
//   "tofStart", "tofEnd" - s, both sampled
//   "departureSamples", "tofSamples", "departureTimes" (UT), "timeOfFlights" (s, ascending)
//   "departureStep", "tofStep" - the spacing, s
//   "departureUnit", "tofUnit" - "Days"/"Hours"/"Minutes"; "departureUnitSeconds", "tofUnitSeconds"
FUNCTION buildTransferWindow {
	PARAMETER endpoints.
	PARAMETER startOffset.
	PARAMETER departureWindows.
	PARAMETER samplesPerWindow.
	PARAMETER tofSamples.
	PARAMETER coarse IS TRUE.
	PARAMETER searchSpan IS -1.
	PARAMETER departureCount IS -1.

	IF startOffset < 30 RETURN LEXICON("error", "Start time offset must be >= 30 seconds!").
	IF departureWindows <= 0 RETURN LEXICON("error", "The number of departure windows must be positive!").
	LOCAL fromOrbitable IS endpoints["from"].
	LOCAL toOrbitable IS endpoints["to"].
	IF fromOrbitable:BODY:NAME <> toOrbitable:BODY:NAME RETURN LEXICON("error", "Bodies must have the same parent!").

	LOCAL sameSOI IS endpoints["sameSOI"].
	LOCAL startUT IS TIME:SECONDS + startOffset.
	LOCAL sunBody IS firstCommonBody(fromOrbitable, toOrbitable).
	LOCAL hyperbolic IS fromOrbitable:ORBIT:ECCENTRICITY >= 1 OR toOrbitable:ORBIT:ECCENTRICITY >= 1.
	LOCAL fromScale IS orbitTimeScale(fromOrbitable, sunBody).
	LOCAL toScale IS orbitTimeScale(toOrbitable, sunBody).

	// The last UT the source can depart (its SOI change) and the last the destination can be met. 0 for none.
	LOCAL fromPatchUT IS orbitPatchUT(fromOrbitable).
	LOCAL toCapUT IS orbitPatchUT(toOrbitable).
	IF sameSOI AND sunBody:HASBODY AND toOrbitable:ORBIT:ECCENTRICITY >= 1 {
		LOCAL edgeTime IS orbitTimeToRadius(toOrbitable, sunBody, soiEdgeFraction() * sunBody:SOIRADIUS).
		IF edgeTime >= 0 AND (toCapUT = 0 OR TIME:SECONDS + edgeTime < toCapUT) SET toCapUT TO TIME:SECONDS + edgeTime.
	}
	// The earliest of those, for the length of a window.
	LOCAL patchLimit IS fromPatchUT.
	IF toCapUT > 0 AND (patchLimit = 0 OR toCapUT < patchLimit) SET patchLimit TO toCapUT.

	// How long one window is.
	LOCAL synodicPeriod IS 0.
	LOCAL windowLength IS 0.
	IF hyperbolic {
		IF searchSpan > 0 {
			SET windowLength TO searchSpan.
		} ELSE IF patchLimit > startUT {
			SET windowLength TO patchLimit - startUT.
		} ELSE IF patchLimit = 0 {
			RETURN LEXICON("error", "An escape orbit has no period to size the search window from, and no SOI change to end it - give a search span!").
		}
	} ELSE {
		LOCAL tooClose IS 1e-12.
		IF sameSOI SET tooClose TO 1e-9.
		IF ABS(1 / fromScale - 1 / toScale) < tooClose {
			IF sameSOI RETURN LEXICON("error", "The two orbits have the same period - there is no relative motion to plan around!").
			RETURN LEXICON("error", "Bodies have identical orbital periods - no synodic period!").
		}
		SET synodicPeriod TO 1 / ABS(1 / fromScale - 1 / toScale).
		SET windowLength TO synodicPeriod.
		IF sameSOI SET windowLength TO MIN(synodicPeriod, 4 * fromScale).
	}

	// The flight times: 0.5 to 4 times the Hohmann time, ended by the destination's last usable moment.
	LOCAL hohmannTime IS CONSTANT:PI * SQRT(((orbitSizeRadius(fromOrbitable, sunBody) + orbitSizeRadius(toOrbitable, sunBody)) / 2) ^ 3 / sunBody:MU).
	LOCAL shortestFlight IS 0.5 * hohmannTime.
	LOCAL longestFlight IS 4 * hohmannTime.
	IF toCapUT > 0 {
		LOCAL flightLimit IS toCapUT - startUT.
		IF flightLimit <= 0 RETURN LEXICON("error", "The destination changes SOI or leaves the usable part of the SOI before the search window starts!").
		IF flightLimit < longestFlight {
			SET longestFlight TO flightLimit.
			IF shortestFlight >= longestFlight SET shortestFlight TO 0.1 * longestFlight.
		}
	}

	// The departure range, ended by the source's SOI change or the last departure that can still arrive.
	LOCAL departureRange IS departureWindows * windowLength.
	IF searchSpan > 0 SET departureRange TO searchSpan.
	LOCAL lastDeparture IS startUT + departureRange.
	IF fromPatchUT > 0 AND fromPatchUT < lastDeparture SET lastDeparture TO fromPatchUT.
	IF toCapUT > 0 AND toCapUT - shortestFlight < lastDeparture SET lastDeparture TO toCapUT - shortestFlight.
	IF lastDeparture <= startUT RETURN LEXICON("error", "An orbit changes SOI, or the destination leaves the usable part of the SOI, before the search window starts!").
	LOCAL searchLength IS lastDeparture - startUT.

	// The sample counts.
	LOCAL perWindow IS samplesPerWindow.
	LOCAL fewestSamples IS 1.
	LOCAL flightSamples IS tofSamples.
	IF sameSOI {
		IF perWindow < 1 {
			LOCAL perOrbit IS 24.
			IF coarse SET perOrbit TO 12.
			SET perWindow TO MAX(12, MIN(240, ROUND(windowLength / fromScale * perOrbit))).
			SET fewestSamples TO 12.
		}
		IF flightSamples < 1 {
			SET flightSamples TO 31.
			IF coarse SET flightSamples TO 7.
		}
	} ELSE {
		IF perWindow < 1 {
			// Scale with how many periods of the quicker orbit the window covers.
			LOCAL perPeriod IS 24.
			LOCAL most IS 120.
			SET fewestSamples TO 40.
			IF coarse {
				SET perPeriod TO 8.
				SET fewestSamples TO 4.
				SET most TO 24.
			}
			SET perWindow TO MAX(fewestSamples, MIN(most, ROUND(windowLength / MIN(fromScale, toScale) * perPeriod))).
		}
		IF flightSamples < 1 {
			SET flightSamples TO 41.
			IF coarse SET flightSamples TO 5.
		}
	}
	LOCAL departureSamples IS MAX(1, ROUND(searchLength / windowLength * perWindow)).
	IF samplesPerWindow < 1 SET departureSamples TO MAX(fewestSamples, departureSamples).
	IF departureCount > 0 SET departureSamples TO departureCount.

	LOCAL departureStep IS searchLength / departureSamples.
	// With a single flight time there is no spacing to speak of; give a hill climb something sensible.
	LOCAL tofStep IS MAX(longestFlight - shortestFlight, 0.1 * shortestFlight).
	IF flightSamples > 1 SET tofStep TO (longestFlight - shortestFlight) / (flightSamples - 1).

	LOCAL departureTimes IS LIST().
	FROM {LOCAL index IS 0.} UNTIL index >= departureSamples STEP {SET index TO index + 1.} DO {
		departureTimes:ADD(startUT + index * departureStep).
	}
	LOCAL timeOfFlights IS LIST().
	FROM {LOCAL index IS 0.} UNTIL index >= flightSamples STEP {SET index TO index + 1.} DO {
		timeOfFlights:ADD(shortestFlight + index * tofStep).
	}

	// Departure labels are sized by the whole departure range; flight-time labels by the shortest flight.
	LOCAL departureUnit IS timeUnitFor(searchLength).
	LOCAL tofUnit IS timeUnitFor(shortestFlight).

	RETURN LEXICON("error", "None",
					"sunBody", sunBody,
					"synodicPeriod", synodicPeriod,
					"hohmannTime", hohmannTime,
					"hyperbolic", hyperbolic,
					"windowLength", windowLength,
					"samplesPerWindow", perWindow,
					"startTime", startUT,
					"departureStart", startUT,
					"departureEnd", lastDeparture,
					"tofStart", shortestFlight,
					"tofEnd", longestFlight,
					"departureSamples", departureSamples,
					"tofSamples", flightSamples,
					"departureTimes", departureTimes,
					"timeOfFlights", timeOfFlights,
					"departureStep", departureStep,
					"tofStep", tofStep,
					"departureUnit", departureUnit,
					"tofUnit", tofUnit,
					"departureUnitSeconds", timeUnitSeconds(departureUnit),
					"tofUnitSeconds", timeUnitSeconds(tofUnit)).
}

// The line every transfer script prints about its search window (a buildTransferWindow result).
FUNCTION searchWindowLine {
	PARAMETER window.

	RETURN "Search window " + timeToString(window["departureEnd"] - window["departureStart"]) + ", " + window["departureSamples"] + " departures.".
}

// The orbit of an orbitable around centralBody as an orbit spec, as of now. For anything but the ship the
// velocity is from VELOCITYAT (:VELOCITY:ORBIT is relative to SHIP:BODY).
FUNCTION orbitSpecAround {
	PARAMETER orbitable.
	PARAMETER centralBody.

	IF orbitable:ISTYPE("Vessel") AND orbitable:NAME = SHIP:NAME AND orbitable = SHIP RETURN orbitSpecFromVessel(SHIP).
	RETURN attachLiveOrbit(makeOrbitSpec(orbitable:POSITION - centralBody:POSITION, VELOCITYAT(orbitable, TIME:SECONDS):ORBIT,
											TIME:SECONDS, centralBody:MU, bodyClearanceRadius(centralBody)),
							orbitable, centralBody).
}

// Why a Lambert arc is not flyable, or "": it must stay clear of the central body and inside its SOI.
// The arc starts at startPosition with startVelocity and sweeps sweepAngle degrees; a periapsis or apoapsis
// only counts if the arc passes it.
//   minRadius - m from the centre; maxRadius - m, normally the SOI radius (0: no limit)
// Returns "Intercepts the central body", "Leaves the central body's SOI", or "".
FUNCTION transferArcProblem {
	PARAMETER startPosition.
	PARAMETER startVelocity.
	PARAMETER sweepAngle.
	PARAMETER mu.
	PARAMETER minRadius.
	PARAMETER maxRadius IS 0.

	LOCAL startRadius IS startPosition:MAG.
	LOCAL momentum IS VCRS(startPosition, startVelocity):MAG.
	LOCAL semiLatus IS momentum ^ 2 / mu.
	LOCAL eccentricity IS SQRT(MAX(0, 1 + (startVelocity:MAG ^ 2 - 2 * mu / startRadius) * momentum ^ 2 / mu ^ 2)).
	IF eccentricity < 1e-6 {
		IF startRadius >= minRadius RETURN "".
		RETURN "Intercepts the central body".
	}

	LOCAL tooLow IS semiLatus / (1 + eccentricity) < minRadius.
	LOCAL tooHigh IS FALSE.
	IF maxRadius > 0 AND eccentricity < 1 SET tooHigh TO semiLatus / (1 - eccentricity) > maxRadius.
	IF NOT tooLow AND NOT tooHigh RETURN "".

	// An extreme is only a problem if the arc gets there. The true anomaly grows along the arc: the
	// periapsis is at 360 degrees and the apoapsis at 180 or 540.
	LOCAL startAnomaly IS ARCCOS(MAX(-1, MIN(1, (semiLatus / startRadius - 1) / eccentricity))).
	IF VDOT(startPosition, startVelocity) < 0 SET startAnomaly TO 360 - startAnomaly.
	LOCAL endAnomaly IS startAnomaly + sweepAngle.
	IF tooLow AND endAnomaly >= 360 RETURN "Intercepts the central body".
	IF tooHigh AND ((startAnomaly < 180 AND endAnomaly > 180) OR endAnomaly > 540) RETURN "Leaves the central body's SOI".
	RETURN "".
}

// Total delta-V (m/s) of a transfer inside one SOI: a burn at departureTime on the ship's orbit onto a
// Lambert arc that meets the target timeOfFlight later, plus the arrival (arrivalDeltaV). The better of the
// short-way and long-way arcs. Rejected: an arc that hits the central body or leaves its SOI, a transfer
// angle within 0.05 degrees of 0 or 180, a time after either orbit's SOI change, and an arrival beyond
// soiEdgeFraction of the SOI radius.
//   fromSpec, toSpec  - orbit specs of the ship and the target (orbitSpecAround)
//   toOrbitable       - the target
//   captureRadius     - see arrivalDeltaV; the winner is aimed at it (statsOut["Aim Offset"])
//   earliestDeparture - UT; an earlier departure is invalid
//   maxRadius         - m, the central body's SOI radius (0 for none)
//   departureTime, timeOfFlight, seed, statsOut - as for transferDeltaV. statsOut["Ejection"] has "deltaV",
//                       "dvVector", "burnPosition", "parkVelocity" and "burnUT" (for addEjectionNode)
// The leading arguments are in the order bindSameSOIDeltaV binds them.
FUNCTION sameSOITransferDeltaV {
	PARAMETER fromSpec.
	PARAMETER toSpec.
	PARAMETER toOrbitable.
	PARAMETER captureRadius.
	PARAMETER earliestDeparture.
	PARAMETER maxRadius.
	PARAMETER departureTime.
	PARAMETER timeOfFlight.
	PARAMETER seed IS LEXICON().
	PARAMETER statsOut IS LEXICON().

	LOCAL shortStartSeed IS 0.5.
	IF seed:HASKEY("shortSeed") SET shortStartSeed TO seed["shortSeed"].
	LOCAL longStartSeed IS 0.5.
	IF seed:HASKEY("longSeed") SET longStartSeed TO seed["longSeed"].

	LOCAL mu IS fromSpec["mu"].
	// An arrival further out than this fraction of the SOI radius is rejected (see arrivesAtEdge).
	LOCAL soiEdgeMargin IS soiEdgeFraction().
	LOCAL bestTotalDV IS invalidDeltaV.
	LOCAL winningTrajectory IS 0.
	LOCAL winningDeparture IS 0.
	LOCAL winningArrivalDV IS 0.

	// Why the cell failed if it does (rank: 1 Lambert, 3 flight path).
	LOCAL failureReason IS "Flight time not positive".
	LOCAL failureRank IS 0.
	LOCAL rejectedArcs IS 0.

	// The predictions follow each orbit's patches, so a time after an SOI change is not on the orbit.
	LOCAL leavesPatch IS (fromSpec["patchUT"] > 0 AND departureTime > fromSpec["patchUT"])
						OR (toSpec["patchUT"] > 0 AND departureTime + timeOfFlight > toSpec["patchUT"]).

	// Prices one arc, to endPosition: if it is flyable and costs less than mustBeat it becomes the winner.
	// Returns transferArcProblem's text ("" for a flyable arc).
	FUNCTION tryArc {
		PARAMETER trajectory.
		PARAMETER endPosition.
		PARAMETER mustBeat.
		PARAMETER departureState.
		PARAMETER arrivalState.
	
		LOCAL sweepAngle IS VANG(departureState["position"], endPosition).
		IF NOT trajectory["Short Way"] SET sweepAngle TO 360 - sweepAngle.
		LOCAL arcProblem IS transferArcProblem(departureState["position"], trajectory["v_1"], sweepAngle, mu, fromSpec["minPeriapsis"], maxRadius).
		IF arcProblem <> "" RETURN arcProblem.
		LOCAL burnVector IS trajectory["v_1"] - departureState["velocity"].
		LOCAL arrivalDV IS arrivalDeltaV(trajectory["v_2"] - arrivalState["velocity"], toOrbitable, captureRadius).
		IF burnVector:MAG + arrivalDV < mustBeat {
			SET bestTotalDV TO burnVector:MAG + arrivalDV.
			SET winningTrajectory TO trajectory.
			SET winningArrivalDV TO arrivalDV.
			SET winningDeparture TO LEXICON("deltaV", burnVector:MAG, "dvVector", burnVector,
										"burnPosition", departureState["position"], "parkVelocity", departureState["velocity"],
										"burnUT", departureTime).
		}
		RETURN "".
	}

	IF timeOfFlight > 0 AND departureTime >= earliestDeparture AND NOT leavesPatch {
		LOCAL departureState IS orbitStateAt(fromSpec, departureTime).
		LOCAL arrivalState IS orbitStateAt(toSpec, departureTime + timeOfFlight).
		LOCAL separation IS VANG(departureState["position"], arrivalState["position"]).
		// Out at the SOI edge the two-body arc is not what the ship flies.
		LOCAL arrivesAtEdge IS maxRadius > 0 AND arrivalState["position"]:MAG > soiEdgeMargin * maxRadius.

		IF separation > 0.05 AND separation < 179.95 AND NOT arrivesAtEdge {
			FOR shortWay IN LIST(TRUE, FALSE) {
				LOCAL startSeed IS longStartSeed.
				IF shortWay SET startSeed TO shortStartSeed.
				LOCAL trajectory IS lambertGooding(departureState["position"], arrivalState["position"], timeOfFlight, mu, shortWay, startSeed).
				IF trajectory["Motion Type"] <> "Failed" {
					IF shortWay SET seed["shortSeed"] TO trajectory["Final Value"].
					ELSE SET seed["longSeed"] TO trajectory["Final Value"].
					LOCAL arcProblem IS tryArc(trajectory, arrivalState["position"], bestTotalDV, departureState, arrivalState).
					IF arcProblem <> "" {
						SET rejectedArcs TO rejectedArcs + 1.
						IF failureRank < 3 {
							SET failureRank TO 3.
							SET failureReason TO arcProblem.
						}
					}
				} ELSE IF failureRank < 1 {
					SET failureRank TO 1.
					SET failureReason TO "No convergence".
					IF trajectory:HASKEY("Failure Reason") SET failureReason TO trajectory["Failure Reason"].
				}
			}
	
			// The aim stage: move the winner's end to the aim point (arrivalAimOffset) and re-price, twice at most.
			IF winningTrajectory:ISTYPE("Lexicon") AND captureRadius > 0 AND toOrbitable:ISTYPE("Body") {
				LOCAL orbitNormal IS VCRS(arrivalState["position"], arrivalState["velocity"]).
				FROM {LOCAL pass IS 1.} UNTIL pass > 2 STEP {SET pass TO pass + 1.} DO {
					LOCAL aimOffset IS arrivalAimOffset(winningTrajectory["v_2"] - arrivalState["velocity"], toOrbitable, captureRadius, orbitNormal).
					IF aimOffset:MAG = 0 BREAK.
					IF winningTrajectory:HASKEY("Aim Offset") {
						IF (aimOffset - winningTrajectory["Aim Offset"]):MAG < 0.002 * aimOffset:MAG BREAK.
					}
	
					LOCAL aimPosition IS arrivalState["position"] + aimOffset.
					LOCAL aimedTrajectory IS lambertGooding(departureState["position"], aimPosition, timeOfFlight, mu, winningTrajectory["Short Way"], winningTrajectory["Final Value"]).
					IF aimedTrajectory["Motion Type"] = "Failed" BREAK.
					IF tryArc(aimedTrajectory, aimPosition, 4 * invalidDeltaV, departureState, arrivalState) <> "" BREAK.
					SET winningTrajectory["Aim Offset"] TO aimOffset.
				}
			}
		} ELSE IF arrivesAtEdge {
			SET failureReason TO "Meets the target at the SOI edge".
		} ELSE {
			SET failureReason TO "Transfer angle near 0 or 180".
		}
	} ELSE IF timeOfFlight > 0 {
		IF departureTime < earliestDeparture SET failureReason TO "Departure before window start".
		ELSE SET failureReason TO "Orbit changes SOI first".
	}

	// Copy into the caller's statsOut (never reassign it).
	IF winningTrajectory:ISTYPE("Lexicon") {
		FOR statKey IN winningTrajectory:KEYS {
			SET statsOut[statKey] TO winningTrajectory[statKey].
		}
		IF statsOut:HASKEY("Aim Offset") AND NOT winningTrajectory:HASKEY("Aim Offset") statsOut:REMOVE("Aim Offset").
		SET statsOut["Ejection"] TO winningDeparture.
		SET statsOut["Arrival Delta V"] TO winningArrivalDV.
	} ELSE {
		SET statsOut["Motion Type"] TO "Failed".
		SET statsOut["Failure Reason"] TO failureReason.
	}
	SET statsOut["Rejected Arcs"] TO rejectedArcs.
	RETURN bestTotalDV.
}

// Returns a delegate f(departureTime, timeOfFlight, seed, statsOut) -> total dV for a transfer inside the
// SOI of the body both orbit, for porkchopGrid and hillClimb2D.
FUNCTION bindSameSOIDeltaV {
	PARAMETER fromOrbitable.
	PARAMETER toOrbitable.
	PARAMETER captureRadius IS 0.
	PARAMETER earliestDeparture IS 0.

	LOCAL centralBody IS fromOrbitable:BODY.
	LOCAL bound IS sameSOITransferDeltaV@.
	SET bound TO bound:BIND(orbitSpecAround(fromOrbitable, centralBody)).
	SET bound TO bound:BIND(orbitSpecAround(toOrbitable, centralBody)).
	SET bound TO bound:BIND(toOrbitable).
	SET bound TO bound:BIND(captureRadius).
	SET bound TO bound:BIND(earliestDeparture).
	// A central body with no parent (the Sun) has no SOI to leave, so no apoapsis limit applies.
	LOCAL soiLimit IS 0.
	IF centralBody:HASBODY SET soiLimit TO centralBody:SOIRADIUS.
	SET bound TO bound:BIND(soiLimit).
	RETURN bound.
}

// Given the ship's position and velocity (relative to the body) at the burn,
// and the radius of the far apsis of the transfer orbit, return the burn needed
// to enter a transfer ellipse whose apsis is the current radius and whose other
// apsis is r_2.  The burn point is the transfer orbit's apsis, so the velocity
// right after the burn is purely horizontal.
// Returns a LEXICON: "prograde", "radial" (node components, normal is always 0),
// "speedAfter" and "transferSMA".
FUNCTION hohmannBurn {
  PARAMETER positionVector.
  PARAMETER velocityVector.
  PARAMETER r_2.
  PARAMETER centralBody IS SHIP:BODY.

  LOCAL r_1 IS positionVector:MAG.
  LOCAL transferSMA IS (r_1 + r_2) / 2.
  LOCAL speedAfter IS SQRT(centralBody:MU * (2 / r_1 - 1 / transferSMA)).

  LOCAL upDir IS positionVector:NORMALIZED.
  LOCAL planeNormal IS VCRS(positionVector, velocityVector):NORMALIZED.
  // Horizontal direction of travel (velocity with its radial component removed).
  LOCAL horizontal IS VCRS(planeNormal, upDir):NORMALIZED.
  LOCAL deltaVVector IS horizontal * speedAfter - velocityVector.

  // Maneuver node axes: prograde along the velocity, radial out perpendicular to it in the orbit plane.
  LOCAL progradeDir IS velocityVector:NORMALIZED.
  LOCAL radialDir IS VCRS(planeNormal, progradeDir):NORMALIZED.
  IF VDOT(radialDir, upDir) < 0 SET radialDir TO -radialDir.

  RETURN LEXICON(
    "prograde", VDOT(deltaVVector, progradeDir),
    "radial", VDOT(deltaVVector, radialDir),
    "speedAfter", speedAfter,
    "transferSMA", transferSMA).
}
