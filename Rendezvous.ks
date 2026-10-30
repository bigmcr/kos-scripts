@LAZYGLOBAL OFF.
CLEARSCREEN.

// Rendezvous
// Launches from the ground, and ends with the ship within closeDistance of a target in a low, nearly circular and
// nearly equatorial orbit, with its velocity matched to the target's. The steps are
//   launch      GravTurnLaunch, with all of its default values.
//   phasing     A burn at apoapsis that puts the periapsis above the atmosphere, but below the target's periapsis.
//   inclination Inc, to take out any relative inclination.
//   wait        The ship stays in the phasing orbit. At each periapsis, the burn there that would bring the ship closest
//               to the target on the next orbit is searched for. When a small burn (at most maxFineBurn) brings the
//               predicted closest approach within acceptDistance, that burn is made.
//   match       MatchAtClosest makes the burn that zeros the relative velocity at the closest approach.
//
// Anything unusual stops the script and asks first. Press ENTER to go on anyway, or BACKSPACE to stop. The stage that
// the script is in is kept on the ship's drive, so after a stop or a crash the script can resume where it was.
//
// Passed the following:
//   targetName      (string, the vessel to meet. If it is blank, the target is used.)
//   startAt         (string, "auto" to resume where the last run stopped if there is one, or the name of a stage:
//                    launch, phasing, inclination, wait or match)
//   closeDistance   (scalar, meters, how close the ship must be when the velocities have been matched. 2000 is the default.)
//   periapsisMargin (scalar, meters above the top of the atmosphere for the periapsis of the phasing orbit)
//   maxFineBurn     (scalar, m/s, the largest correction burn at periapsis that is used to set up the approach)
//   acceptDistance  (scalar, meters, how close the predicted approach must be for the correction burn to be made)
PARAMETER targetName IS "".
PARAMETER startAt IS "auto".
PARAMETER closeDistance IS "Default".
PARAMETER periapsisMargin IS "Default".
PARAMETER maxFineBurn IS 20.
PARAMETER acceptDistance IS "Default".
SET closeDistance TO processScalarParameter(closeDistance, errorValue).
IF closeDistance = errorValue SET closeDistance TO 2000.
SET periapsisMargin TO processScalarParameter(periapsisMargin, errorValue).
IF periapsisMargin = errorValue SET periapsisMargin TO 10000.
SET acceptDistance TO processScalarParameter(acceptDistance, errorValue).
IF acceptDistance = errorValue SET acceptDistance TO 1000.

// Settings that can be changed here
LOCAL stageFile IS "1:rendezvous.stage".
LOCAL stageNames IS LIST("launch", "phasing", "inclination", "wait", "match").
LOCAL leadTime IS 120.					// A burn that is closer than this many seconds is left for the next orbit
LOCAL sampleCount IS 140.				// How many times the distance to the target is looked at when it is searched for its minimum
LOCAL biggestBurn IS 400.				// A single burn bigger than this many m/s is unusual
LOCAL maxTargetEccentricity IS 0.05.
LOCAL maxTargetInclination IS 0.5.

// Tell
// Prints a line.
FUNCTION tell {
	PARAMETER text.
	PRINT text.
}

// Ask Permission
// Stops what is happening, and waits for the operator to decide.
// Passed the following:
//			message (string, what is unusual)
// Returns the following:
//			TRUE if the operator pressed ENTER to go on, FALSE if BACKSPACE to stop (bool)
FUNCTION askPermission {
	PARAMETER message.
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
	HUDTEXT("Rendezvous needs a decision - see the terminal", 10, 2, 24, YELLOW, FALSE).
	PRINT " ".
	PRINT "UNUSUAL: " + message.
	PRINT "Press ENTER to go on anyway, or BACKSPACE to stop.".
	// keys that were typed earlier do not count
	TERMINAL:INPUT:CLEAR().
	LOCAL tempChar IS "".
	UNTIL tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE {
		IF TERMINAL:INPUT:HASCHAR SET tempChar TO TERMINAL:INPUT:GETCHAR().
		WAIT 0.
	}
	RETURN tempChar = TERMINAL:INPUT:ENTER.
}

FUNCTION saveStage {
	PARAMETER stageName.
	IF EXISTS(stageFile) DELETEPATH(stageFile).
	LOG stageName TO stageFile.
}

// Saved Stage
// Returns the name of the stage that was saved, or "" if there is none (string).
FUNCTION savedStage {
	IF NOT EXISTS(stageFile) RETURN "".
	RETURN OPEN(stageFile):READALL:STRING:TRIM.
}

// Atmosphere Top
// Returns the height of the top of the atmosphere, or 0 if there is no atmosphere (scalar).
FUNCTION atmosphereTop {
	IF SHIP:BODY:ATM:EXISTS RETURN SHIP:BODY:ATM:HEIGHT.
	RETURN 0.
}

// Relative Inclination
// Returns the angle between the orbital plane of the ship and the one of the target (scalar, degrees).
FUNCTION relativeInclination {
	RETURN VANG(getNormalVector(SHIP), getNormalVector(TARGET)).
}

// Relative Speed
// Returns the speed of the ship relative to the target (scalar).
FUNCTION relativeSpeed {
	RETURN (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT):MAG.
}

// Target Distance At
// Returns the distance between the ship and the target at a time, using the flight plan (including maneuver nodes).
FUNCTION targetDistanceAt {
	PARAMETER probeTime.
	RETURN (POSITIONAT(SHIP, probeTime) - POSITIONAT(TARGET, probeTime)):MAG.
}

// Approach Scan
// Finds the closest approach to the target in a window of time. The distance is looked at all through the window, and
// then the best place is narrowed down.
// Passed the following:
//			windowStart, windowEnd (scalars, UT seconds)
// Returns the following:
//			a lexicon with "time" (UT seconds) and "distance" (meters)
FUNCTION approachScan {
	PARAMETER windowStart, windowEnd.
	LOCAL stepSize IS (windowEnd - windowStart) / sampleCount.
	LOCAL bestTime IS windowStart.
	LOCAL bestDistance IS targetDistanceAt(windowStart).
	FROM {LOCAL index IS 1.} UNTIL index > sampleCount STEP {SET index TO index + 1.} DO {
		LOCAL sampleTime IS windowStart + index * stepSize.
		LOCAL sampleDistance IS targetDistanceAt(sampleTime).
		IF sampleDistance < bestDistance {
			SET bestDistance TO sampleDistance.
			SET bestTime TO sampleTime.
		}
	}
	LOCAL refinedTime IS goldenSectionMinimum({PARAMETER probeTime. RETURN targetDistanceAt(probeTime).},
		MAX(windowStart, bestTime - stepSize), MIN(windowEnd, bestTime + stepSize), 14).
	RETURN LEXICON("time", refinedTime, "distance", targetDistanceAt(refinedTime)).
}

// Clear Nodes
FUNCTION clearNodes {
	UNTIL NOT HASNODE {
		REMOVE NEXTNODE.
	}
}

// Execute Node
// Runs Exec on the next maneuver node, and removes the node afterward.
// Returns the following:
//			the delta-V that was left unburned (scalar, m/s)
FUNCTION executeNode {
	IF NOT HASNODE RETURN 0.
	RUNPATH("exec", 5, FALSE, FALSE, TRUE).
	LOCAL remaining IS 0.
	IF HASNODE {
		SET remaining TO NEXTNODE:DELTAV:MAG.
		REMOVE NEXTNODE.
	}
	RETURN remaining.
}

// Next Periapsis Time
// Returns the UT of the next periapsis that is at least leadTime seconds away (scalar).
FUNCTION nextPeriapsisTime {
	LOCAL periapsisTime IS TIME:SECONDS + ETA:PERIAPSIS.
	IF ETA:PERIAPSIS < leadTime SET periapsisTime TO periapsisTime + SHIP:ORBIT:PERIOD.
	RETURN periapsisTime.
}

// Plan Fine Burn
// Searches for the burn along the orbit at a time that brings the ship closest to the target in the following orbit and
// a half. Trial burns are made as a maneuver node, whose effect is included when the distance is calculated. The
// node is left in place, set to the best burn.
// Passed the following:
//			burnTime (scalar, UT seconds)
// Returns the following:
//			a lexicon with "node" (the maneuver node), "burn" (m/s along the orbit, negative is retrograde), "distance"
//			(meters, the closest approach to expect) and "time" (the burn time)
FUNCTION planFineBurn {
	PARAMETER burnTime.
	LOCAL windowStart IS burnTime + 30.
	LOCAL windowEnd IS burnTime + 1.5 * SHIP:ORBIT:PERIOD.
	LOCAL fineNode IS NODE(burnTime, 0, 0, 0).
	ADD fineNode.
	WAIT 0.
	// a burn of 1 m/s moves the closest approach by a few kilometers, so look at every m/s first, and then narrow it down
	LOCAL bestBurn IS 0.
	LOCAL bestDistance IS 1000000000.
	FROM {LOCAL burn IS -maxFineBurn.} UNTIL burn > maxFineBurn STEP {SET burn TO burn + 1.} DO {
		SET fineNode:PROGRADE TO burn.
		WAIT 0.
		LOCAL distanceFound IS approachScan(windowStart, windowEnd)["distance"].
		IF distanceFound < bestDistance {
			SET bestDistance TO distanceFound.
			SET bestBurn TO burn.
		}
	}
	SET bestBurn TO goldenSectionMinimum({
		PARAMETER probeBurn.
		SET fineNode:PROGRADE TO probeBurn.
		WAIT 0.
		RETURN approachScan(windowStart, windowEnd)["distance"].
	}, MAX(-maxFineBurn, bestBurn - 1), MIN(maxFineBurn, bestBurn + 1), 12).
	SET fineNode:PROGRADE TO bestBurn.
	WAIT 0.
	SET bestDistance TO approachScan(windowStart, windowEnd)["distance"].
	RETURN LEXICON("node", fineNode, "burn", bestBurn, "distance", bestDistance, "time", burnTime).
}

// Find Target
// Sets the target from the name, or checks that there is one.
FUNCTION findTarget {
	PARAMETER wantedName.
	IF wantedName <> "" {
		LOCAL candidates IS LIST().
		LIST TARGETS IN candidates.
		FOR eachVessel IN candidates {
			IF eachVessel:NAME = wantedName {
				SET TARGET TO eachVessel.
				RETURN TRUE.
			}
		}
		tell("There is no vessel named " + wantedName + ".").
		RETURN FALSE.
	}
	IF HASTARGET RETURN TRUE.
	tell("Set a target, or give the name of the vessel to meet.").
	RETURN FALSE.
}

// Check Target
// Looks for anything about the target that is not as expected.
// Returns the following:
//			TRUE if the target is as expected, or if the operator said to go on (bool)
FUNCTION checkTarget {
	IF NOT TARGET:ISTYPE("Vessel") {
		tell("The target is not a vessel.").
		RETURN FALSE.
	}
	IF TARGET:BODY:NAME <> SHIP:BODY:NAME {
		tell("The target is around " + TARGET:BODY:NAME + ", not " + SHIP:BODY:NAME + ".").
		RETURN FALSE.
	}
	LOCAL targetOrbit IS TARGET:ORBIT.
	IF targetOrbit:ECCENTRICITY > maxTargetEccentricity {
		IF NOT askPermission("The target's orbit is not nearly circular (eccentricity " + ROUND(targetOrbit:ECCENTRICITY, 3) + ").") RETURN FALSE.
	}
	IF targetOrbit:INCLINATION > maxTargetInclination AND targetOrbit:INCLINATION < 180 - maxTargetInclination {
		IF NOT askPermission("The target's orbit is not equatorial (inclination " + ROUND(targetOrbit:INCLINATION, 2) + " degrees).") RETURN FALSE.
	}
	IF targetOrbit:PERIAPSIS < atmosphereTop() + periapsisMargin + 5000 {
		IF NOT askPermission("The target's periapsis is too low to leave room for a phasing orbit below it.") RETURN FALSE.
	}
	RETURN TRUE.
}

// Delta-V Needed
// A rough amount of delta-V for the whole trip to a low orbit and the rendezvous (scalar, m/s).
FUNCTION deltaVNeeded {
	RETURN 1.55 * SQRT(SHIP:BODY:MU / (SHIP:BODY:RADIUS + TARGET:ORBIT:PERIAPSIS)) + 150.
}

// Delta-V Available
// The delta-V of the whole ship, from the stage information (scalar, m/s).
FUNCTION deltaVAvailable {
	updateShipInfo().
	RETURN shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"].
}

// ---- The stages -------------------------------------------------------------------------------------------

FUNCTION stageLaunch {
	IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" {
		IF deltaVAvailable() < deltaVNeeded() {
			IF NOT askPermission("The ship has " + ROUND(deltaVAvailable()) + " m/s of delta-V, and about " + ROUND(deltaVNeeded()) + " m/s is needed.") RETURN FALSE.
		}
		tell("Launching.").
		RUNPATH("GravTurnLaunch").
		endScript().
		IF SHIP:ALTITUDE < atmosphereTop() {
			RETURN askPermission("The launch ended inside the atmosphere, at " + distanceToString(SHIP:ALTITUDE, 1) + ".").
		}
		RETURN TRUE.
	}
	IF SHIP:ALTITUDE > atmosphereTop() {
		tell("The ship is not on the ground, so there is no launch.").
		RETURN TRUE.
	}
	tell("The ship is flying in the atmosphere. It is not safe to go on from here.").
	RETURN FALSE.
}

FUNCTION stagePhasing {
	clearNodes().
	LOCAL desiredPeriapsis IS atmosphereTop() + periapsisMargin.
	// below the target's periapsis, but never in the atmosphere
	IF desiredPeriapsis > TARGET:ORBIT:PERIAPSIS - 5000 {
		IF NOT askPermission("There is no room for a phasing orbit between the atmosphere and the target.") RETURN FALSE.
		SET desiredPeriapsis TO MAX(atmosphereTop() + 2000, TARGET:ORBIT:PERIAPSIS - 5000).
	}
	IF SHIP:ORBIT:APOAPSIS < TARGET:ORBIT:PERIAPSIS {
		IF NOT askPermission("The ship's apoapsis, " + distanceToString(SHIP:ORBIT:APOAPSIS, 1) + ", is below the target's periapsis.") RETURN FALSE.
	}
	IF SHIP:ORBIT:PERIAPSIS >= desiredPeriapsis - 500 {
		tell("The periapsis is already high enough, so there is no phasing burn.").
		RETURN TRUE.
	}
	IF ETA:APOAPSIS < 45 {
		IF NOT askPermission("The apoapsis is only " + ROUND(ETA:APOAPSIS) + " seconds away, which is hardly enough time to prepare the burn.") RETURN FALSE.
	}

	// The burn is made at apoapsis, so the new apoapsis is where it is now and the new periapsis is the one wanted.
	LOCAL apoapsisRadius IS SHIP:BODY:RADIUS + SHIP:ORBIT:APOAPSIS.
	LOCAL newSMA IS (apoapsisRadius + SHIP:BODY:RADIUS + desiredPeriapsis) / 2.
	LOCAL newPeriod IS 2 * CONSTANT:PI * SQRT(newSMA^3 / SHIP:BODY:MU).
	LOCAL periodDifference IS ABS(newPeriod - TARGET:ORBIT:PERIOD) / TARGET:ORBIT:PERIOD.
	IF periodDifference < 0.01 {
		IF NOT askPermission("The phasing orbit's period is within 1% of the target's, so it would take very long to catch up.") RETURN FALSE.
	}
	tell("Phasing orbit: " + distanceToString(desiredPeriapsis, 1) + " by " + distanceToString(SHIP:ORBIT:APOAPSIS, 1) + ", period " + timeToString(newPeriod) + " against " + timeToString(TARGET:ORBIT:PERIOD) + ".").

	RUNPATH("ChangePeriod", ETA:APOAPSIS, newPeriod, FALSE).
	IF NOT HASNODE {
		RETURN askPermission("No burn was planned for the phasing orbit.").
	}
	IF NEXTNODE:DELTAV:MAG > biggestBurn {
		IF NOT askPermission("The phasing burn is " + ROUND(NEXTNODE:DELTAV:MAG) + " m/s.") {
			clearNodes().
			RETURN FALSE.
		}
	}
	LOCAL remaining IS executeNode().
	IF remaining > 2 {
		IF NOT askPermission("The phasing burn left " + ROUND(remaining, 1) + " m/s unburned.") RETURN FALSE.
	}
	IF ABS(SHIP:ORBIT:PERIAPSIS - desiredPeriapsis) > 3000 {
		IF NOT askPermission("The periapsis is " + distanceToString(SHIP:ORBIT:PERIAPSIS, 1) + ", and " + distanceToString(desiredPeriapsis, 1) + " was wanted.") RETURN FALSE.
	}
	RETURN TRUE.
}

FUNCTION stageInclination {
	clearNodes().
	LOCAL relative IS relativeInclination().
	IF relative < 0.05 {
		tell("The relative inclination is " + ROUND(relative, 3) + " degrees, so there is no inclination burn.").
		RETURN TRUE.
	}
	IF relative > 1 {
		IF NOT askPermission("The relative inclination is " + ROUND(relative, 2) + " degrees, which is a lot for an equatorial target.") RETURN FALSE.
	}
	tell("Relative inclination " + ROUND(relative, 3) + " degrees.").
	RUNPATH("Inc", 0, "Highest", TRUE, FALSE).
	IF NOT HASNODE {
		RETURN askPermission("No inclination burn was planned.").
	}
	IF NEXTNODE:DELTAV:MAG > biggestBurn / 2 {
		IF NOT askPermission("The inclination burn is " + ROUND(NEXTNODE:DELTAV:MAG) + " m/s.") {
			clearNodes().
			RETURN FALSE.
		}
	}
	LOCAL remaining IS executeNode().
	IF remaining > 1 {
		IF NOT askPermission("The inclination burn left " + ROUND(remaining, 1) + " m/s unburned.") RETURN FALSE.
	}
	IF relativeInclination() > 0.1 {
		RETURN askPermission("The relative inclination is still " + ROUND(relativeInclination(), 3) + " degrees.").
	}
	RETURN TRUE.
}

FUNCTION stageWait {
	clearNodes().
	LOCAL periodDifference IS ABS(SHIP:ORBIT:PERIOD - TARGET:ORBIT:PERIOD) / TARGET:ORBIT:PERIOD.
	IF periodDifference < 0.005 {
		IF NOT askPermission("The ship's period is within 0.5% of the target's, so it is not going to catch up.") RETURN FALSE.
	}
	// The ship gains periodDifference of an orbit each time around, so it should have caught up within about this many orbits.
	LOCAL orbitLimit IS 3 + 2 * CEILING(1 / MAX(periodDifference, 0.001)).
	LOCAL orbitsWaited IS 0.
	LOCAL found IS FALSE.
	UNTIL found {
		LOCAL burnTime IS nextPeriapsisTime().
		tell("Looking at the burn at periapsis, " + timeToString(burnTime - TIME:SECONDS) + " from now.").
		LOCAL plan IS planFineBurn(burnTime).
		LOCAL planNode IS plan["node"].
		tell("  Best burn " + ROUND(plan["burn"], 2) + " m/s, giving a closest approach of " + distanceToString(plan["distance"], 1) + ".").
		IF plan["distance"] <= acceptDistance {
			SET found TO TRUE.
			IF ABS(plan["burn"]) < 0.05 {
				tell("No burn is needed.").
				REMOVE planNode.
			} ELSE {
				LOCAL remaining IS executeNode().
				IF remaining > 1 {
					IF NOT askPermission("The correction burn left " + ROUND(remaining, 1) + " m/s unburned.") RETURN FALSE.
				}
			}
		} ELSE {
			REMOVE planNode.
			SET orbitsWaited TO orbitsWaited + 1.
			IF orbitsWaited > orbitLimit {
				IF NOT askPermission("There has been no opportunity in " + orbitsWaited + " orbits, and about " + ROUND(orbitLimit / 2) + " were expected to be enough.") RETURN FALSE.
				SET orbitLimit TO orbitLimit + 10.
			}
			warpToTime(burnTime + 60).
		}
	}
	// what the orbit gives now
	LOCAL approach IS approachScan(TIME:SECONDS + 30, TIME:SECONDS + 1.5 * SHIP:ORBIT:PERIOD).
	tell("Closest approach to expect: " + distanceToString(approach["distance"], 1) + " in " + timeToString(approach["time"] - TIME:SECONDS) + ".").
	IF approach["distance"] > 3 * acceptDistance {
		RETURN askPermission("After the correction burn, the closest approach is " + distanceToString(approach["distance"], 1) + ".").
	}
	RETURN TRUE.
}

FUNCTION stageMatch {
	clearNodes().
	LOCAL approach IS approachScan(TIME:SECONDS + 30, TIME:SECONDS + 1.5 * SHIP:ORBIT:PERIOD).
	tell("Closest approach: " + distanceToString(approach["distance"], 1) + " in " + timeToString(approach["time"] - TIME:SECONDS) + ".").
	IF approach["distance"] > closeDistance {
		IF NOT askPermission("The closest approach, " + distanceToString(approach["distance"], 1) + ", is farther than " + distanceToString(closeDistance, 1) + ".") RETURN FALSE.
	}
	// MatchAtClosest, not asking anything, and starting its search at the time that was found
	RUNPATH("MatchAtClosest", FALSE, FALSE, approach["time"]).
	IF NOT HASNODE {
		RETURN askPermission("No velocity matching burn was planned.").
	}
	IF NEXTNODE:DELTAV:MAG > biggestBurn / 2 {
		IF NOT askPermission("Matching the velocity takes " + ROUND(NEXTNODE:DELTAV:MAG) + " m/s.") {
			clearNodes().
			RETURN FALSE.
		}
	}
	tell("Matching velocity with a " + ROUND(NEXTNODE:DELTAV:MAG, 1) + " m/s burn.").
	LOCAL remaining IS executeNode().
	IF remaining > 0.5 {
		IF NOT askPermission("The velocity matching burn left " + ROUND(remaining, 1) + " m/s unburned.") RETURN FALSE.
	}
	RETURN TRUE.
}

// ---- Main -------------------------------------------------------------------------------------------------

LOCAL startIndex IS 0.
LOCAL proceed IS findTarget(targetName).
IF proceed SET proceed TO checkTarget().

IF proceed {
	IF startAt = "auto" {
		LOCAL savedName IS savedStage().
		IF savedName <> "" AND stageNames:CONTAINS(savedName) {
			tell("The last run stopped in the " + savedName + " stage.").
			tell("Press ENTER to resume there, or BACKSPACE to start from the beginning.").
			TERMINAL:INPUT:CLEAR().
			LOCAL tempChar IS "".
			UNTIL tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE {
				IF TERMINAL:INPUT:HASCHAR SET tempChar TO TERMINAL:INPUT:GETCHAR().
				WAIT 0.
			}
			IF tempChar = TERMINAL:INPUT:ENTER SET startIndex TO stageNames:FIND(savedName).
		}
	} ELSE IF stageNames:CONTAINS(startAt) {
		SET startIndex TO stageNames:FIND(startAt).
	} ELSE {
		tell(startAt + " is not a stage. The stages are launch, phasing, inclination, wait and match.").
		SET proceed TO FALSE.
	}
}

LOCAL stageIndex IS startIndex.
LOCAL stoppedAt IS "".
UNTIL stageIndex >= stageNames:LENGTH OR NOT proceed {
	LOCAL currentStageName IS stageNames[stageIndex].
	saveStage(currentStageName).
	tell(" ").
	tell("---- " + currentStageName + " ----").
	IF currentStageName = "launch" SET proceed TO stageLaunch().
	ELSE IF currentStageName = "phasing" SET proceed TO stagePhasing().
	ELSE IF currentStageName = "inclination" SET proceed TO stageInclination().
	ELSE IF currentStageName = "wait" SET proceed TO stageWait().
	ELSE IF currentStageName = "match" SET proceed TO stageMatch().
	IF proceed SET stageIndex TO stageIndex + 1.
	ELSE SET stoppedAt TO currentStageName.
}

IF stageIndex >= stageNames:LENGTH AND proceed {
	IF EXISTS(stageFile) DELETEPATH(stageFile).
	tell(" ").
	tell("Distance " + distanceToString(TARGET:POSITION:MAG, 1) + ", relative speed " + distanceToString(relativeSpeed(), 2) + "/s.").
	IF TARGET:POSITION:MAG > closeDistance {
		tell("That is farther than " + distanceToString(closeDistance, 1) + ".").
		SET loopMessage TO "Matched velocity, but too far: " + distanceToString(TARGET:POSITION:MAG, 1).
	} ELSE SET loopMessage TO "Rendezvous: " + distanceToString(TARGET:POSITION:MAG, 1) + ", " + distanceToString(relativeSpeed(), 2) + "/s".
} ELSE IF stoppedAt <> "" {
	tell(" ").
	tell("Stopped in the " + stoppedAt + " stage. Run Rendezvous again to resume.").
	SET loopMessage TO "Rendezvous stopped in " + stoppedAt.
} ELSE SET loopMessage TO "Rendezvous not started".
