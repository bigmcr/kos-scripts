@LAZYGLOBAL OFF.

// multiPassBurn.ks - splits a long burn into several shorter burns, one per orbit, for a burn that is too long for its orbit.
//
// Why: a burn that is a large part of an orbit, held at a fixed direction, pushes the ship down toward the body in the first part of the
// burn (an ejection from an 80 km Kerbin orbit with a weak engine did that and the ship hit the atmosphere). The same delta V in several
// burns, each at the same place on the orbit and each short enough, does not. See BurnPlannerPlan.md for the whole design.
//
// How it works: the last maneuver node in the flight plan is the target: where (the node's position, P), when (its time) and with what
// velocity (the velocity after its burn) the ship has to leave. Every pass is a burn centered on P, in the direction of the whole delta V
// (the direction that Exec holds), so the ship is at P again after one period of whatever orbit it is then on. The passes are timed
// backward from the target's time, and the sizes of the passes are solved so that the first pass falls on a pass of P on the ship's orbit
// as it is now. A small first pass (a phasing burn, with the same delta V in total) widens the choices.
// The plan is checked: the lowest altitude of every pass (a quick estimate, then the same simulation that the burn solver uses), the
// periapsis and apoapsis of every orbit between the passes, the patches that the game predicts (no other body met, and no escape,
// before the final burn), the time in the shadow of the body (the sun direction is taken as fixed; all passes are at P, so they are
// in the shadow together, and only the length of the burns matters), and the limits of the schedule.
//
// The plan is also saved on the ship's own drive (1:multiPassBurn.json: the target's time, position and velocity, the settings, and the
// passes). That is what a replan reads, and there is no flag for it: the script replans when there is a valid saved plan (the file reads,
// is for this ship and body, its final burn is still ahead) that goes with the flight plan (no nodes at all, or the last node is at the
// time of the plan's last pass). Otherwise it plans from the last node, with the full search. A replan takes the target from the file,
// works out from the ship's real orbit what is left to burn (so the error of the pass that was flown is absorbed), and only
// re-solves the sizes of the passes that are left, keeping their number (it tries a few more only if it has to) and the final time. It does not
// search again, so it takes seconds. The flight plan is rebuilt with the passes that are left, and the file is updated. Exec deletes
// the file when it has flown the plan's last pass (finishMultiPassPlan in library.ks).
//
// Passed the following (all optional)
//			earliest start (s from now for the first burn, default 120)
//			longest span (s from the first burn to the last. 0, the default, is 128 periods of a circular orbit at the node's distance
//				from the body (worked out from the body's MU), or 6 periods of the ship's own orbit if that is longer)
//			number of passes (0 = choose, the default: this is an input only. The search finds the number itself, starting at the fewest that
//				the largest safe piece allows, and the plans that it lists say how many passes each has)
//			choice (which of the listed plans to use, default 1)
//			list only (TRUE shows the plans and changes nothing, default FALSE)
//			lowest allowed altitude (m, default: 2 km above the atmosphere, or 5 km if there is none; on a replan, the saved one)
//			full search (TRUE ignores the saved plan and plans from the last node, default FALSE. On a replan the longest span, if 0, is the
//				saved one; the earliest start counts from now, so a pass that is less than that away is not used)
// The names of the functions start with ppass so that they cannot meet those of the libraries.
PARAMETER earliestStart IS 120.
PARAMETER passes IS 0.
PARAMETER maxSpan IS 0.
PARAMETER choice IS 1.
PARAMETER listOnly IS FALSE.
PARAMETER lowestAltitude IS -1.
PARAMETER fullSearch IS FALSE.

CLEARSCREEN.
resetAbort().
PRINT "Press End to abort".

LOCAL planError IS "None".
LOCAL planMessage IS "".
LOCAL savedNodes IS LIST().													// LIST(time, radial, normal, prograde) of every node that was in the flight plan
LOCAL nodesCleared IS FALSE.
LOCAL nowUT IS TIME:SECONDS.
LOCAL centralBody IS SHIP:BODY.
LOCAL freshPlan IS TRUE.													// only the user's node in the plan, no passes yet
LOCAL targetUT IS 0.
LOCAL targetPosition IS V(0, 0, 0).											// P
LOCAL targetVelocity IS V(0, 0, 0).											// the velocity wanted after the final burn
LOCAL firstVelocity IS V(0, 0, 0).											// the velocity at P on the ship's orbit now
LOCAL firstPassUT IS 0.														// the first time at or after the earliest start that the ship is at P
LOCAL periodNow IS 0.
LOCAL context IS LEXICON().
LOCAL candidates IS LIST().
LOCAL passesLimit IS 0.
LOCAL planPath IS multiPassPlanPath.									// the saved plan, on the ship's own drive
LOCAL savedPlan IS LEXICON().
LOCAL remainingPlanned IS 0.												// replan: the passes of the saved plan that are still ahead
LOCAL finalSlipLimit IS 30.													// replan: s that the last pass may be off the planned final time

// Is there a saved plan that goes with the flight plan? Then this is a replan: it is valid (ppassPlanError), and the flight plan has no
// nodes, or its last node is at the time of the plan's last pass (a node that the user has made is not).
LOCAL replan IS FALSE.
IF NOT fullSearch AND EXISTS(planPath) {
	SET savedPlan TO READJSON(planPath).
	IF ppassPlanError(savedPlan) = "None" {
		SET replan TO TRUE.
		IF HASNODE {
			LOCAL lastPassTime IS savedPlan["passes"][savedPlan["passes"]:LENGTH - 1]["time"].
			LOCAL lastNodeTime IS 0.
			FOR nodeItem IN ALLNODES {
				IF nodeItem:TIME > lastNodeTime SET lastNodeTime TO nodeItem:TIME.
			}
			IF ABS(lastNodeTime - lastPassTime) > 5 SET replan TO FALSE.
		}
		IF NOT replan PRINT "The saved plan does not go with the flight plan: planning from the last node".
	}
	IF NOT replan SET savedPlan TO LEXICON().
}

IF NOT HASNODE AND NOT replan SET planError TO "No maneuver node present".

// A replan takes the target from the saved plan, not from the flight plan (the last node there has moved with the error of the passes
// that were flown). The nodes are kept to be put back, as for any other failure.
IF planError = "None" AND replan {
	IF planError = "None" {
		FOR nodeItem IN ALLNODES {
			savedNodes:ADD(LIST(nodeItem:TIME, nodeItem:RADIALOUT, nodeItem:NORMAL, nodeItem:PROGRADE)).
		}
		SET freshPlan TO FALSE.
		SET targetUT TO savedPlan["targetUT"].
		SET targetPosition TO ppassVector(savedPlan["targetPosition"]).
		SET targetVelocity TO ppassVector(savedPlan["targetVelocity"]).
		IF lowestAltitude < 0 SET lowestAltitude TO savedPlan["lowestAltitude"].
		IF maxSpan <= 0 SET maxSpan TO savedPlan["maxSpan"].
		FOR savedPass IN savedPlan["passes"] {
			IF savedPass["time"] > nowUT SET remainingPlanned TO remainingPlanned + 1.
		}
		SET remainingPlanned TO MAX(remainingPlanned, 1).
		IF targetUT - nowUT < earliestStart SET planError TO "The final burn of the saved plan is less than " + earliestStart + " s away".
	}
}

// The target: the last node, read with the other nodes in place (its velocity before the burn is that of the passes before it, if any)
IF planError = "None" AND NOT replan {
	LOCAL lastNode IS ALLNODES[0].
	FOR nodeItem IN ALLNODES {
		IF nodeItem:TIME > lastNode:TIME SET lastNode TO nodeItem.
		savedNodes:ADD(LIST(nodeItem:TIME, nodeItem:RADIALOUT, nodeItem:NORMAL, nodeItem:PROGRADE)).
	}
	SET freshPlan TO (savedNodes:LENGTH = 1).
	LOCAL targetSnapshot IS nodeOrbitSnapshot(lastNode).
	IF targetSnapshot["Body"]:NAME <> centralBody:NAME SET planError TO "The last node is not around " + centralBody:NAME.
	ELSE IF targetSnapshot["Period"] <= 0 SET planError TO "The orbit at the last node is not a closed orbit".
	ELSE IF freshPlan AND targetSnapshot["PatchStart"] > nowUT + 1 SET planError TO "The node is after a sphere of influence change".
	ELSE IF targetSnapshot["StateError"] > 0.001 SET planError TO "The position and velocity at the node do not agree with its orbit".
	IF planError = "None" {
		SET targetUT TO targetSnapshot["NodeUT"].
		SET targetPosition TO targetSnapshot["NodePosition"].
		SET firstVelocity TO targetSnapshot["NodeVelocity"].
		SET targetVelocity TO firstVelocity + lastNode:DELTAV.
		IF targetUT - nowUT < earliestStart SET planError TO "The node is less than " + earliestStart + " s away".
	}
}

// The flight plan is emptied from here on (the ship's own orbit is then what it really is), and put back if there is no plan
IF planError = "None" {
	ppassClearNodes().
	SET nodesCleared TO TRUE.
	WAIT 0.2.
	IF SHIP:ORBIT:ECCENTRICITY >= 1 OR SHIP:ORBIT:HASNEXTPATCH SET planError TO "The ship leaves the sphere of influence before the node".
}

IF planError = "None" {
	SET periodNow TO SHIP:ORBIT:PERIOD.
	LOCAL mu IS centralBody:MU.
	LOCAL pointRadius IS targetPosition:MAG.
	// the default longest span: 128 periods of a circular orbit at the node's distance (from the body's MU), or 6 periods of the ship's own
	// orbit if that is longer (a node at the periapsis of a high orbit, whose period is much longer than the circular one)
	IF maxSpan <= 0 SET maxSpan TO MAX(128 * 2 * CONSTANT:PI * SQRT(pointRadius ^ 3 / mu), 6 * periodNow).
	IF lowestAltitude < 0 {
		IF centralBody:ATM:EXISTS SET lowestAltitude TO centralBody:ATM:HEIGHT + 2000.
		ELSE SET lowestAltitude TO 5000.
	}

	// when the ship is at P: exactly one or more periods before the node for the user's own node, otherwise by solving for it
	LOCAL shipPosition IS -centralBody:POSITION.
	LOCAL shipVelocity IS SHIP:VELOCITY:ORBIT.
	IF freshPlan {
		LOCAL periodsBack IS FLOOR((targetUT - (nowUT + earliestStart)) / periodNow).
		SET firstPassUT TO targetUT - periodsBack * periodNow.
	} ELSE {
		SET firstPassUT TO ppassPassTime(shipPosition, shipVelocity, nowUT, nowUT + earliestStart, targetPosition, mu).
		SET firstVelocity TO keplerPropagate(shipPosition, shipVelocity, firstPassUT - nowUT, mu)[1].
		IF firstPassUT > targetUT + (CHOOSE finalSlipLimit IF replan ELSE 1) SET planError TO "The ship does not get back to the node's position before the node".
		// a replan starts from a place that the flown passes were made at: it has to be on the ship's orbit now (this also catches a
		// plan that was saved in another frame of reference or for another burn)
		IF replan AND planError = "None" {
			LOCAL orbitNormal IS VCRS(shipPosition, shipVelocity):NORMALIZED.
			IF ABS(VDOT(orbitNormal, targetPosition:NORMALIZED)) > 0.02 SET planError TO "The place of the saved plan is not on the ship's orbit: plan again without the replan flag".
		}
	}

	// the stages, as Exec makes them
	updateShipInfo().
	LOCAL usedStages IS LIST().
	FOR stageNumber IN RANGE(shipInfo["NumberOfStages"] - 1, -1) {
		IF shipInfo["Stage " + stageNumber]["Isp"] <> 0 usedStages:ADD(shipInfo["Stage " + stageNumber]).
	}
	LOCAL totalDv IS (targetVelocity - firstVelocity):MAG.
	IF planError = "None" AND totalDv < 1 SET planError TO "There is almost no delta V to burn".
	IF planError = "None" SET planError TO burnFeasibilityError(usedStages, totalDv).

	IF planError = "None" {
		LOCAL sunDirection IS V(0, 0, 0).
		IF centralBody:NAME <> "Sun" SET sunDirection TO (BODY("Sun"):POSITION - centralBody:POSITION):NORMALIZED.
		LOCAL soiLimit IS 1E15.
		IF centralBody:HASBODY SET soiLimit TO 0.95 * centralBody:SOIRADIUS.
		SET context TO LEXICON(
			"mu", mu,
			"body", centralBody,
			"bodyRadius", centralBody:RADIUS,
			"P", targetPosition,
			"v0", firstVelocity,
			"u", (targetVelocity - firstVelocity):NORMALIZED,
			"total", totalDv,
			"stageList", burnStageList(usedStages, 0, usedStages:LENGTH - 1, 0.15, 1.2),
			"rLimit", centralBody:RADIUS + lowestAltitude,
			"sunDirection", sunDirection,
			"soiLimit", soiLimit,
			"v0Squared", firstVelocity:SQRMAGNITUDE,
			"v0u", VDOT(firstVelocity, (targetVelocity - firstVelocity):NORMALIZED),
			"pointRadius", pointRadius).

		PRINT "Planning " + ROUND(totalDv, 1) + " m/s at " + ROUND((pointRadius - centralBody:RADIUS) / 1000, 1) + " km altitude, in " + timeToString(targetUT - nowUT).
		PRINT "Lowest altitude " + ROUND(lowestAltitude / 1000, 1) + " km, longest span " + timeToString(maxSpan) + ", period " + timeToString(periodNow).
		IF replan PRINT "Replanning: " + remainingPlanned + " of the " + savedPlan["passes"]:LENGTH + " passes of plan " + savedPlan["revision"] + " were still ahead".
		IF NOT ppassIsLit(context["P"], sunDirection, centralBody:RADIUS) PRINT "The node's position is in the shadow of " + centralBody:NAME + " (nothing here can move it, only shorten the burns in it)".

		// is one burn safe? Then there is nothing to split
		LOCAL remainder IS MOD(targetUT - firstPassUT, periodNow).
		IF NOT replan AND (remainder < 5 OR periodNow - remainder < 5) {
			LOCAL singleCheck IS ppassBuild(context, 1, 0, 0, targetUT).
			IF singleCheck["problem"] = "None" {
				SET planMessage TO "One burn is safe (lowest " + ROUND((singleCheck["lowest"] - centralBody:RADIUS) / 1000, 1) + " km): no passes needed".
				SET planError TO "Nothing to do".
			}
		}
	}

	// the biggest first piece that keeps its lowest altitude above the limit (a bisection of the quick estimate)
	LOCAL pieceCap IS totalDv.
	IF planError = "None" {
		IF ppassQuick(context, 0, 0.5) < context["rLimit"] SET planError TO "Even a tiny burn here goes below the lowest altitude".
		ELSE IF ppassQuick(context, 0, totalDv) >= context["rLimit"] SET pieceCap TO totalDv.
		ELSE {
			LOCAL capLow IS 0.5.
			LOCAL capHigh IS totalDv.
			FROM {LOCAL iteration IS 0.} UNTIL iteration >= 24 STEP {SET iteration TO iteration + 1.} DO {
				LOCAL capMid IS (capLow + capHigh) / 2.
				IF ppassQuick(context, 0, capMid) >= context["rLimit"] SET capLow TO capMid.
				ELSE SET capHigh TO capMid.
			}
			SET pieceCap TO capLow.
		}
	}

	// the choices
	IF planError = "None" {
		PRINT "Largest safe first burn about " + ROUND(pieceCap, 1) + " m/s. Searching".
		LOCAL deltaTime IS targetUT - firstPassUT.
		// The number of passes is not a parameter that is filled in: the search itself finds it. With equal pieces the fewest that can work
		// is the delta V over the largest safe piece, so the search starts there and goes up from it (or uses only the number that was asked for).
		LOCAL firstCount IS MAX(2, CEILING(totalDv / pieceCap)).
		LOCAL lastCount IS MIN(firstCount + 8, 40).
		IF passes > 0 {
			SET firstCount TO MAX(passes, 2).
			SET lastCount TO MAX(passes, 2).
		}
		IF replan AND passes <= 0 {
			// the passes that were left in the saved plan, or more if the sizes do not fit (an error of the last pass can need that)
			SET firstCount TO MAX(MAX(remainingPlanned, 2), firstCount).
			SET lastCount TO MIN(firstCount + 4, 40).
			// one pass left: the whole of what is left in one burn at the next pass, if it is safe and the pass is near the final time
			IF remainingPlanned = 1 {
				LOCAL singleBuilt IS ppassBuild(context, 1, 0, 0, firstPassUT).
				IF singleBuilt["problem"] = "None" AND ABS(targetUT - firstPassUT) <= finalSlipLimit candidates:ADD(singleBuilt).
			}
		}
		LOCAL notes IS LIST().													// why plans were rejected, for the message if there are none
		LOCAL noSizes IS 0.
		LOCAL noTiming IS 0.
		LOCAL tooLong IS 0.
		LOCAL phaseFractions IS LIST(-1, 0.5, 0.25, 0.1).						// -1: equal pieces. Otherwise the first piece is this fraction of the largest safe piece
		IF replan SET phaseFractions TO LIST(-1).									// the small first piece of the plan has been flown already
		LOCAL count IS firstCount.
		UNTIL count > lastCount OR candidates:LENGTH >= 24 OR (replan AND candidates:LENGTH > 0) OR abortKeyPressed() {
			FOR fraction IN phaseFractions {
				LOCAL fixedFirst IS -1.
				IF fraction > 0 SET fixedFirst TO fraction * pieceCap.
				LOCAL solveRange IS ppassBounds(count, fixedFirst, totalDv, pieceCap).
				IF solveRange:LENGTH < 2 SET noSizes TO noSizes + 1.
				IF solveRange:LENGTH = 2 {
					LOCAL lowSum IS ppassSumForX(context, count, fixedFirst, solveRange[0]).
					LOCAL highSum IS ppassSumForX(context, count, fixedFirst, solveRange[1]).
					LOCAL jFirst IS MAX(CEILING((deltaTime - MIN(highSum, maxSpan)) / periodNow), 0).
					LOCAL jLast IS FLOOR((deltaTime - lowSum) / periodNow).
					IF jFirst > jLast {
						SET noTiming TO noTiming + 1.
						IF fixedFirst < 0 AND notes:LENGTH < 12 {
							LOCAL reason IS "the passes need " + timeToString(lowSum) + " to " + timeToString(highSum) + " from the first burn to the last".
							IF lowSum > maxSpan SET reason TO reason + ", more than the longest span, " + timeToString(maxSpan).
							ELSE IF lowSum > deltaTime SET reason TO reason + ", and the node is only " + timeToString(deltaTime) + " after the first pass that is possible".
							ELSE SET reason TO reason + " (" + timeToString(deltaTime) + " are available, longest span " + timeToString(maxSpan) + ")".
							notes:ADD(count + " passes: " + reason).
						}
					}
					// a replan goes on with the next pass that the ship makes (the earliest first burn that fits), not the latest
					IF replan AND jFirst <= jLast SET jLast TO jFirst.
					// the shortest span (the latest first burn) first
					LOCAL jIndex IS jLast.
					UNTIL jIndex < jFirst OR candidates:LENGTH >= 24 {
						LOCAL wantedSum IS deltaTime - jIndex * periodNow.
						IF wantedSum <= maxSpan AND wantedSum >= lowSum - 0.001 AND wantedSum <= highSum + 0.001 {
							LOCAL solvedX IS ppassSolve(context, count, fixedFirst, wantedSum, solveRange[0], solveRange[1]).
							LOCAL firstPiece IS solvedX.
							LOCAL nextPiece IS solvedX.
							IF fixedFirst > 0 SET firstPiece TO fixedFirst.
							LOCAL built IS ppassBuild(context, count, firstPiece, nextPiece, targetUT).
							IF built["problem"] <> "None" {
								IF notes:LENGTH < 12 notes:ADD(count + " passes: " + built["problem"]).
							} ELSE IF built["span"] > maxSpan + 1 SET tooLong TO tooLong + 1.
							ELSE candidates:ADD(built).
						}
						SET jIndex TO jIndex - 1.
					}
				}
			}
			SET count TO count + 1.
		}
		IF abortRequested SET planError TO "Aborted".
		ELSE IF candidates:LENGTH = 0 {
			SET planError TO "No safe plan inside the limits (try a longer span, a lower altitude limit or another number of passes)".
				IF replan SET planError TO "No replan found that keeps the final time (plan again without the replan flag for a full search)".
			PRINT "Looked at " + firstCount + " to " + lastCount + " passes, largest safe piece " + ROUND(pieceCap, 1) + " m/s of " + ROUND(totalDv, 1) + " m/s.".
			PRINT "No pieces of a safe size: " + noSizes + ", no timing that fits: " + noTiming + ", too long: " + tooLong + ".".
			PRINT "Time from the first possible pass to the node: " + timeToString(deltaTime) + ", longest span: " + timeToString(maxSpan) + ".".
			FOR noteText IN notes { PRINT "  " + noteText. }
		}
	}

	// the best first
	IF planError = "None" {
		FROM {LOCAL index IS 1.} UNTIL replan OR index >= candidates:LENGTH STEP {SET index TO index + 1.} DO {
			LOCAL moving IS candidates[index].
			LOCAL place IS index - 1.
			UNTIL place < 0 OR ppassBetter(candidates[place], moving) {
				SET candidates[place + 1] TO candidates[place].
				SET place TO place - 1.
			}
			SET candidates[place + 1] TO moving.
		}
		PRINT candidates:LENGTH + " plans (best first):".
		FROM {LOCAL index IS 0.} UNTIL index >= MIN(candidates:LENGTH, 8) STEP {SET index TO index + 1.} DO {
			PRINT ppassRow(candidates[index], index + 1, nowUT, context).
		}
		IF listOnly SET planError TO "Listed only".
	}

	// the chosen plan, checked with the real simulation and the patches that the game predicts, and put in the flight plan
	IF planError = "None" {
		LOCAL chosenIndex IS MIN(MAX(choice, 1), candidates:LENGTH) - 1.
		LOCAL accepted IS FALSE.
		UNTIL accepted OR chosenIndex >= candidates:LENGTH OR abortRequested {
			LOCAL candidate IS candidates[chosenIndex].
			PRINT "Checking plan " + (chosenIndex + 1) + " (" + candidate["count"] + " passes)".
			LOCAL checkProblem IS ppassSimulate(context, candidate).
			IF checkProblem = "None" {
				ppassAddNodes(context, candidate).
				WAIT 0.3.
				SET checkProblem TO ppassScan(candidate["count"]).
				IF checkProblem <> "None" {
					ppassClearNodes().
					WAIT 0.3.
				}
			}
			IF checkProblem = "None" {
				SET accepted TO TRUE.
				SET planMessage TO candidate["count"] + " passes planned, " + ROUND(context["total"], 1) + " m/s in all, first in " + timeToString(candidate["times"][0] - nowUT).
				PRINT "Plan " + (chosenIndex + 1) + " is in the flight plan:".
					ppassSavePlan(planPath, savedPlan, replan, nowUT, targetUT, targetPosition, targetVelocity, lowestAltitude, maxSpan, context["total"], candidate).
				FROM {LOCAL index IS 0.} UNTIL index >= candidate["count"] STEP {SET index TO index + 1.} DO {
					PRINT "  " + (index + 1) + ": in " + timeToString(candidate["times"][index] - nowUT) + ", " + ROUND(candidate["pieces"][index], 1) + " m/s, burn " + timeToString(candidate["burns"][index]).
				}
				IF candidate["unlit"] > 1 PRINT "  about " + ROUND(candidate["unlit"]) + " s of the burns are in the shadow of " + centralBody:NAME.
			} ELSE {
				PRINT "Plan " + (chosenIndex + 1) + " not used: " + checkProblem.
				SET chosenIndex TO chosenIndex + 1.
			}
		}
		IF NOT accepted {
			IF abortRequested SET planError TO "Aborted".
			ELSE SET planError TO "None of the listed plans passed the checks".
		}
	}
}

// the flight plan is put back as it was if there is no plan
IF planError <> "None" {
	IF nodesCleared {
		ppassClearNodes().
		WAIT 0.2.
		FOR nodeValues IN savedNodes {
			ADD NODE(nodeValues[0], nodeValues[1], nodeValues[2], nodeValues[3]).
		}
	}
	IF planMessage = "" SET planMessage TO planError.
	PRINT planMessage.
}
SET loopMessage TO planMessage.

// ============================================================================
// Functions
// ============================================================================

// A vector as a list of its three components (for the saved plan), and back
FUNCTION ppassList {
	PARAMETER inVector.
	RETURN LIST(inVector:X, inVector:Y, inVector:Z).
}
FUNCTION ppassVector {
	PARAMETER components.
	RETURN V(components[0], components[1], components[2]).
}

// Whether a saved plan (READJSON of the file) can be replanned from: "None" or why not
FUNCTION ppassPlanError {
	PARAMETER savedData.
	IF NOT savedData:ISTYPE("Lexicon") RETURN "The saved plan cannot be read".
	FOR eachKey IN LIST("version", "ship", "body", "revision", "targetUT", "targetPosition", "targetVelocity", "lowestAltitude", "maxSpan", "passes") {
		IF NOT savedData:HASKEY(eachKey) RETURN "The saved plan has no " + eachKey.
	}
	IF NOT savedData["passes"]:ISTYPE("List") RETURN "The saved plan has no passes".
	IF savedData["passes"]:LENGTH = 0 RETURN "The saved plan has no passes".
	IF savedData["version"] <> 1 RETURN "The saved plan is of a version that this script does not know".
	IF savedData["ship"] <> SHIP:NAME RETURN "The saved plan is for " + savedData["ship"].
	IF savedData["body"] <> SHIP:BODY:NAME RETURN "The saved plan is around " + savedData["body"].
	IF savedData["targetUT"] <= TIME:SECONDS RETURN "The final burn of the saved plan is in the past".
	RETURN "None".
}

// Saves the plan that is now in the flight plan to the ship's own drive, for a replan. A replan keeps the revision count and the target;
// the passes are the ones that are in the flight plan now.
// Passed the following
//			file path, the plan that was read (empty unless replanning), whether this is a replan, now (UT), the target's time, position and
//			velocity, the lowest altitude (m), the longest span (s), the delta V of the plan (m/s), the plan (from ppassBuild)
FUNCTION ppassSavePlan {
	PARAMETER filePath.
	PARAMETER oldPlan.
	PARAMETER isReplan.
	PARAMETER nowTime.
	PARAMETER finalTime.
	PARAMETER finalPosition.
	PARAMETER finalVelocity.
	PARAMETER altitudeLimit.
	PARAMETER spanLimit.
	PARAMETER planDv.
	PARAMETER plan.
	LOCAL passList IS LIST().
	FROM {LOCAL k IS 0.} UNTIL k >= plan["count"] STEP {SET k TO k + 1.} DO {
		passList:ADD(LEXICON("time", plan["times"][k], "piece", plan["pieces"][k], "burn", plan["burns"][k])).
	}
	LOCAL revisionNumber IS 0.
	IF isReplan SET revisionNumber TO oldPlan["revision"] + 1.
	LOCAL data IS LEXICON(
		"version", 1,
		"ship", SHIP:NAME,
		"body", SHIP:BODY:NAME,
		"createdUT", nowTime,
		"revision", revisionNumber,
		"targetUT", finalTime,
		"targetPosition", ppassList(finalPosition),
		"targetVelocity", ppassList(finalVelocity),
		"lowestAltitude", altitudeLimit,
		"maxSpan", spanLimit,
		"totalDv", planDv,
		"passes", passList).
	IF EXISTS(filePath) DELETEPATH(filePath).
	// the file is about 3.8 kB, plus 1.25 kB for each pass
	LOCAL neededBytes IS 4500 + 1300 * passList:LENGTH.
	IF CORE:VOLUME:FREESPACE < neededBytes {
		PRINT "Local disk full (" + neededBytes + " bytes needed): the plan is not saved, so it cannot be replanned".
		RETURN.
	}
	WRITEJSON(data, filePath).
	PRINT "Plan saved to " + filePath + " (revision " + revisionNumber + ")".
}

// Removes every maneuver node from the flight plan
FUNCTION ppassClearNodes {
	LOCAL nodeCopy IS LIST().
	FOR nodeItem IN ALLNODES { nodeCopy:ADD(nodeItem). }
	FOR nodeItem IN nodeCopy { REMOVE nodeItem. }
}

// The time at which a ship on an orbit is next in the direction of a position (as seen from the body, in the orbit plane), at or after a time
// Passed the following
//			ship position and velocity (vectors, relative to the body) at the time nowUT
//			nowUT (s), startUT (s, not before this)
//			target position (vector, relative to the body)
//			mu (m^3/s^2)
// Returns the time (UT, s)
FUNCTION ppassPassTime {
	PARAMETER shipPosition.
	PARAMETER shipVelocity.
	PARAMETER nowUT.
	PARAMETER startUT.
	PARAMETER targetPosition.
	PARAMETER mu.

	LOCAL planeNormal IS VCRS(shipPosition, shipVelocity):NORMALIZED.
	LOCAL targetFlat IS targetPosition - planeNormal * VDOT(planeNormal, targetPosition).
	LOCAL passUT IS startUT.
	FROM {LOCAL iteration IS 0.} UNTIL iteration >= 14 STEP {SET iteration TO iteration + 1.} DO {
		LOCAL passState IS keplerPropagate(shipPosition, shipVelocity, passUT - nowUT, mu).
		LOCAL angleAhead IS ARCTAN2(VDOT(planeNormal, VCRS(passState[0], targetFlat)), VDOT(passState[0], targetFlat)).
		IF iteration = 0 AND angleAhead < 0 SET angleAhead TO angleAhead + 360.
		IF ABS(angleAhead) < 0.000001 BREAK.
		LOCAL angularRate IS VCRS(passState[0], passState[1]):MAG / passState[0]:SQRMAGNITUDE.
		SET passUT TO passUT + angleAhead * CONSTANT:DEGTORAD / angularRate.
	}
	RETURN passUT.
}

// Whether a position (relative to the body) is in the sunlight: not behind the body in a cylinder of the body's radius.
// A zero sun direction (no sun to look at) is always lit.
FUNCTION ppassIsLit {
	PARAMETER pointPosition.
	PARAMETER sunDirection.
	PARAMETER bodyRadius.
	IF sunDirection:MAG < 0.5 RETURN TRUE.
	IF VDOT(pointPosition, sunDirection) >= 0 RETURN TRUE.
	LOCAL sideways IS pointPosition - sunDirection * VDOT(pointPosition, sunDirection).
	RETURN sideways:MAG >= bodyRadius.
}

// The period (s) of the orbit through P with the velocity that is the first velocity plus a delta V along the burn direction, or a huge
// number for one that does not close (so that sums of periods stay in order)
FUNCTION ppassPeriodAt {
	PARAMETER context.
	PARAMETER cumulative.
	LOCAL speedSquared IS context["v0Squared"] + 2 * cumulative * context["v0u"] + cumulative ^ 2.
	LOCAL inverseA IS 2 / context["pointRadius"] - speedSquared / context["mu"].
	IF inverseA <= 1E-10 RETURN 1E12.
	RETURN 2 * CONSTANT:PI * SQRT((1 / inverseA) ^ 3 / context["mu"]).
}

// The sum of the periods between the passes: the orbits after the first pass up to the one before the last
// Passed the following
//			context, the number of passes, the size of the first piece (m/s), the size of each other piece but the last (m/s)
FUNCTION ppassSumT {
	PARAMETER context.
	PARAMETER count.
	PARAMETER firstPiece.
	PARAMETER nextPiece.
	LOCAL sumT IS 0.
	FROM {LOCAL k IS 1.} UNTIL k > count - 1 STEP {SET k TO k + 1.} DO {
		SET sumT TO sumT + ppassPeriodAt(context, firstPiece + (k - 1) * nextPiece).
	}
	RETURN sumT.
}

// The same for the number x that is solved for: the equal pieces (fixedFirst < 0), or the pieces after a fixed first piece
FUNCTION ppassSumForX {
	PARAMETER context.
	PARAMETER count.
	PARAMETER fixedFirst.
	PARAMETER x.
	IF fixedFirst < 0 RETURN ppassSumT(context, count, x, x).
	RETURN ppassSumT(context, count, fixedFirst, x).
}

// The range of x (m/s) for which every piece is between 1 m/s and the largest safe piece, or an empty list if there is none
FUNCTION ppassBounds {
	PARAMETER count.
	PARAMETER fixedFirst.
	PARAMETER total.
	PARAMETER pieceCap.
	LOCAL smallest IS 1.
	LOCAL lowX IS 0.
	LOCAL highX IS 0.
	IF fixedFirst < 0 {
		IF count < 2 RETURN LIST().
		SET lowX TO MAX(smallest, (total - pieceCap) / (count - 1)).
		SET highX TO MIN(pieceCap, (total - smallest) / (count - 1)).
	} ELSE {
		IF count < 3 OR fixedFirst > pieceCap OR fixedFirst >= total - smallest RETURN LIST().
		SET lowX TO MAX(smallest, (total - fixedFirst - pieceCap) / (count - 2)).
		SET highX TO MIN(pieceCap, (total - fixedFirst - smallest) / (count - 2)).
	}
	IF lowX > highX RETURN LIST().
	RETURN LIST(lowX, highX).
}

// Solves for x so that the sum of the periods is the wanted number (the sum grows with x)
FUNCTION ppassSolve {
	PARAMETER context.
	PARAMETER count.
	PARAMETER fixedFirst.
	PARAMETER wantedSum.
	PARAMETER lowX.
	PARAMETER highX.
	LOCAL lowValue IS lowX.
	LOCAL highValue IS highX.
	FROM {LOCAL iteration IS 0.} UNTIL iteration >= 45 STEP {SET iteration TO iteration + 1.} DO {
		LOCAL midValue IS (lowValue + highValue) / 2.
		IF ppassSumForX(context, count, fixedFirst, midValue) < wantedSum SET lowValue TO midValue.
		ELSE SET highValue TO midValue.
	}
	RETURN (lowValue + highValue) / 2.
}

// The stages that are left after some of the delta V has been burned
// Passed the following
//			stage list (see burnStageList), delta V already burned (m/s)
// Returns a stage list
FUNCTION ppassStagesAfter {
	PARAMETER stageList.
	PARAMETER usedDv.
	LOCAL remaining IS LIST().
	LOCAL toConsume IS usedDv.
	FOR eachStage IN stageList {
		IF toConsume <= 0 remaining:ADD(eachStage).
		ELSE {
			LOCAL exhaustSpeed IS eachStage["thrust"] / eachStage["flowRate"].
			LOCAL available IS exhaustSpeed * LN(eachStage["wetMass"] / (eachStage["wetMass"] - eachStage["propellant"])).
			IF toConsume >= available SET toConsume TO toConsume - available.
			ELSE {
				LOCAL massAfter IS eachStage["wetMass"] * CONSTANT:E ^ (-toConsume / exhaustSpeed).
				remaining:ADD(LEXICON("thrust", eachStage["thrust"], "flowRate", eachStage["flowRate"], "wetMass", massAfter,
					"propellant", eachStage["propellant"] - (eachStage["wetMass"] - massAfter), "gap", 0,
					"throttleable", eachStage["throttleable"], "minThrottle", eachStage["minThrottle"])).
				SET toConsume TO 0.
			}
		}
	}
	RETURN remaining.
}

// The time of a piece of the burn: from the first thrust to the end, and to the time that half of its delta V is done (the ignition lead)
// Passed the following
//			context, delta V burned before the piece (m/s), the piece (m/s)
// Returns LIST(burn time, half time) (s)
FUNCTION ppassBurnTimes {
	PARAMETER context.
	PARAMETER cumulative.
	PARAMETER piece.
	LOCAL burnedAtStart IS stagedBurnTimes(context["stageList"], cumulative)[0].
	LOCAL burnedAtEnd IS stagedBurnTimes(context["stageList"], cumulative + piece)[0].
	LOCAL burnedAtHalf IS stagedBurnTimes(context["stageList"], cumulative + piece / 2)[0].
	RETURN LIST(burnedAtEnd - burnedAtStart, burnedAtHalf - burnedAtStart).
}

// A quick estimate of the smallest distance from the body's center during a piece of the burn: a short integration in two body gravity
// with constant thrust along the burn direction, from the ignition (half the burn before the pass at P) to the end of the burn.
FUNCTION ppassQuickLowest {
	PARAMETER startPosition.
	PARAMETER startVelocity.
	PARAMETER burnDirection.
	PARAMETER pieceDv.
	PARAMETER burnSeconds.
	PARAMETER halfSeconds.
	PARAMETER mu.
	IF burnSeconds <= 0 RETURN startPosition:MAG.
	LOCAL startState IS keplerPropagate(startPosition, startVelocity, -halfSeconds, mu).
	LOCAL pos IS startState[0].
	LOCAL vel IS startState[1].
	LOCAL thrustAccel IS burnDirection * (pieceDv / burnSeconds).
	LOCAL stepCount IS 24.
	LOCAL stepSize IS burnSeconds / stepCount.
	LOCAL lowestRadius IS pos:MAG.
	FROM {LOCAL k IS 0.} UNTIL k >= stepCount STEP {SET k TO k + 1.} DO {
		LOCAL a1 IS burnGravity(pos, mu) + thrustAccel.
		LOCAL p2 IS pos + vel * (stepSize / 2).
		LOCAL v2 IS vel + a1 * (stepSize / 2).
		LOCAL a2 IS burnGravity(p2, mu) + thrustAccel.
		LOCAL p3 IS pos + v2 * (stepSize / 2).
		LOCAL v3 IS vel + a2 * (stepSize / 2).
		LOCAL a3 IS burnGravity(p3, mu) + thrustAccel.
		LOCAL p4 IS pos + v3 * stepSize.
		LOCAL v4 IS vel + a3 * stepSize.
		LOCAL a4 IS burnGravity(p4, mu) + thrustAccel.
		SET pos TO pos + (vel + 2 * v2 + 2 * v3 + v4) * (stepSize / 6).
		SET vel TO vel + (a1 + 2 * a2 + 2 * a3 + a4) * (stepSize / 6).
		IF pos:MAG < lowestRadius SET lowestRadius TO pos:MAG.
	}
	RETURN lowestRadius.
}

// The quick estimate for a piece (m from the body's center), given the delta V that has been burned before it
FUNCTION ppassQuick {
	PARAMETER context.
	PARAMETER cumulative.
	PARAMETER piece.
	LOCAL times IS ppassBurnTimes(context, cumulative, piece).
	RETURN ppassQuickLowest(context["P"], context["v0"] + context["u"] * cumulative, context["u"], piece, times[0], times[1], context["mu"]).
}

// The time of a piece of the burn that is in the shadow (s), from nine points along the burn
FUNCTION ppassUnlitTime {
	PARAMETER context.
	PARAMETER cumulative.
	PARAMETER piece.
	PARAMETER times.
	IF context["sunDirection"]:MAG < 0.5 RETURN 0.
	LOCAL middleVelocity IS context["v0"] + context["u"] * (cumulative + piece / 2).
	LOCAL unlitSamples IS 0.
	FROM {LOCAL k IS 0.} UNTIL k > 8 STEP {SET k TO k + 1.} DO {
		LOCAL samplePosition IS keplerPropagate(context["P"], middleVelocity, -times[1] + times[0] * k / 8, context["mu"])[0].
		IF NOT ppassIsLit(samplePosition, context["sunDirection"], context["bodyRadius"]) SET unlitSamples TO unlitSamples + 1.
	}
	RETURN times[0] * unlitSamples / 9.
}

// The periapsis and apoapsis radius (m) of the orbit of a position and velocity, as a list (the apoapsis is huge if the orbit is open)
FUNCTION ppassApsides {
	PARAMETER pos.
	PARAMETER vel.
	PARAMETER mu.
	LOCAL radiusNow IS pos:MAG.
	LOCAL inverseA IS 2 / radiusNow - vel:SQRMAGNITUDE / mu.
	LOCAL eccVector IS (pos * (vel:SQRMAGNITUDE - mu / radiusNow) - vel * VDOT(pos, vel)) / mu.
	LOCAL ecc IS eccVector:MAG.
	LOCAL semiLatus IS VCRS(pos, vel):SQRMAGNITUDE / mu.
	LOCAL apoapsisRadius IS 1E15.
	IF inverseA > 1E-12 AND ecc < 1 SET apoapsisRadius TO semiLatus / (1 - ecc).
	RETURN LIST(semiLatus / (1 + ecc), apoapsisRadius).
}

// Builds a plan from the sizes of its passes and checks what can be checked without the simulation: the quick estimate of the lowest
// altitude of every piece, the periapsis and apoapsis of every orbit between the passes, and the time in the shadow.
// The times of the passes are worked out backward from the target time.
// Passed the following
//			context
//			number of passes
//			first piece (m/s), each piece after it but the last (m/s)
//			time of the final pass (UT, s)
// Returns a lexicon of "count", "pieces" (m/s), "cumulative" (m/s burned before each), "times" (UT of each pass), "periods" (s of the orbit after each pass),
//		"burns" (s), "halves" (s), "span" (s), "lowest" (m from the body's center), "unlit" (s), "largest" (m/s) and "problem" ("None" or why not)
FUNCTION ppassBuild {
	PARAMETER context.
	PARAMETER count.
	PARAMETER firstPiece.
	PARAMETER nextPiece.
	PARAMETER finalTime.

	LOCAL total IS context["total"].
	LOCAL pieces IS LIST().
	LOCAL cumulatives IS LIST().
	LOCAL burns IS LIST().
	LOCAL halves IS LIST().
	LOCAL periods IS LIST().
	LOCAL problem IS "None".
	LOCAL lowestSeen IS 1E15.
	LOCAL unlitTotal IS 0.
	LOCAL largestPiece IS 0.
	LOCAL cumulative IS 0.
	FROM {LOCAL k IS 1.} UNTIL k > count STEP {SET k TO k + 1.} DO {
		LOCAL piece IS total - cumulative.
		IF k = 1 AND count > 1 SET piece TO firstPiece.
		ELSE IF k > 1 AND k < count SET piece TO nextPiece.
		LOCAL times IS ppassBurnTimes(context, cumulative, piece).
		LOCAL vBefore IS context["v0"] + context["u"] * cumulative.
		LOCAL lowestRadius IS ppassQuickLowest(context["P"], vBefore, context["u"], piece, times[0], times[1], context["mu"]).
		IF lowestRadius < lowestSeen SET lowestSeen TO lowestRadius.
		IF lowestRadius < context["rLimit"] AND problem = "None" SET problem TO "pass " + k + " goes down to " + ROUND((lowestRadius - context["bodyRadius"]) / 1000, 1) + " km".
		SET unlitTotal TO unlitTotal + ppassUnlitTime(context, cumulative, piece, times).
		IF piece > largestPiece SET largestPiece TO piece.
		pieces:ADD(piece).
		cumulatives:ADD(cumulative).
		burns:ADD(times[0]).
		halves:ADD(times[1]).
		SET cumulative TO cumulative + piece.
		IF k < count {
			// the orbit that the ship is on between this pass and the next
			LOCAL vAfter IS context["v0"] + context["u"] * cumulative.
			LOCAL apsides IS ppassApsides(context["P"], vAfter, context["mu"]).
			IF apsides[0] < context["rLimit"] AND problem = "None" SET problem TO "the orbit after pass " + k + " has its periapsis at " + ROUND((apsides[0] - context["bodyRadius"]) / 1000, 1) + " km".
			IF apsides[1] > context["soiLimit"] AND problem = "None" SET problem TO "the orbit after pass " + k + " leaves the sphere of influence".
			periods:ADD(ppassPeriodAt(context, cumulative)).
		}
	}
	LOCAL passTimes IS LIST().
	FROM {LOCAL k IS 0.} UNTIL k >= count STEP {SET k TO k + 1.} DO { passTimes:ADD(0). }
	SET passTimes[count - 1] TO finalTime.
	FROM {LOCAL k IS count - 2.} UNTIL k < 0 STEP {SET k TO k - 1.} DO {
		SET passTimes[k] TO passTimes[k + 1] - periods[k].
	}
	RETURN LEXICON("count", count, "pieces", pieces, "cumulative", cumulatives, "times", passTimes, "periods", periods, "burns", burns,
					"halves", halves, "span", finalTime - passTimes[0], "lowest", lowestSeen, "unlit", unlitTotal, "largest", largestPiece, "problem", problem).
}

// Whether plan a is better than plan b: less time in the shadow (by a second or more), then the shorter span, then fewer passes
FUNCTION ppassBetter {
	PARAMETER planA.
	PARAMETER planB.
	IF ABS(planA["unlit"] - planB["unlit"]) >= 1 RETURN planA["unlit"] < planB["unlit"].
	IF ABS(planA["span"] - planB["span"]) >= 1 RETURN planA["span"] < planB["span"].
	RETURN planA["count"] <= planB["count"].
}

// One line about a plan, for the list
FUNCTION ppassRow {
	PARAMETER plan.
	PARAMETER number.
	PARAMETER nowUT.
	PARAMETER context.
	RETURN number + ": " + plan["count"] + " passes, start in " + timeToString(plan["times"][0] - nowUT) + ", span " + timeToString(plan["span"]) + ", largest " + ROUND(plan["largest"], 0) + " m/s, low "
		+ ROUND((plan["lowest"] - context["bodyRadius"]) / 1000, 1) + " km, shadow " + ROUND(plan["unlit"]) + " s".
}

// Checks every pass of a plan with the burn solver's simulation, from the state that the plan gives before the pass, with the stages that
// are left then. The lowest altitude must be above the limit, and the simulated burn must end properly.
// Returns "None" or the reason that the plan is no good
FUNCTION ppassSimulate {
	PARAMETER context.
	PARAMETER plan.
	FROM {LOCAL k IS 0.} UNTIL k >= plan["count"] STEP {SET k TO k + 1.} DO {
		PRINT "  simulating pass " + (k + 1) + " of " + plan["count"].
		LOCAL cumulative IS plan["cumulative"][k].
		LOCAL stageListNow IS ppassStagesAfter(context["stageList"], cumulative).
		IF stageListNow:LENGTH = 0 RETURN "the stages cannot deliver pass " + (k + 1).
		LOCAL beforeState IS LEXICON("Body", context["body"], "NodePosition", context["P"], "NodeVelocity", context["v0"] + context["u"] * cumulative).
		LOCAL spec IS burnSolveSpec(beforeState, context["u"] * plan["pieces"][k], stageListNow[0]["thrust"], stageListNow[0]["flowRate"], stageListNow[0]["wetMass"],
			LEXICON("stages", stageListNow, "abort", abortKeyPressed@)).
		LOCAL sim IS simulateBurn(spec, 0, 0, 0).
		IF sim["endReason"] = "aborted" RETURN "aborted".
		IF sim["endReason"] <> "remaining delta V" AND sim["endReason"] <> "orbit energy reached" RETURN "the simulation of pass " + (k + 1) + " ended on " + sim["endReason"].
		IF sim["lowestRadius"] < context["rLimit"] RETURN "the simulation of pass " + (k + 1) + " goes down to " + ROUND((sim["lowestRadius"] - context["bodyRadius"]) / 1000, 1) + " km".
	}
	RETURN "None".
}

// Adds the nodes of a plan to the flight plan, each with the components (radial, normal, prograde) of its own delta V in the frame of the orbit
// that the ship is on before it
FUNCTION ppassAddNodes {
	PARAMETER context.
	PARAMETER plan.
	FROM {LOCAL k IS 0.} UNTIL k >= plan["count"] STEP {SET k TO k + 1.} DO {
		LOCAL vBefore IS context["v0"] + context["u"] * plan["cumulative"][k].
		LOCAL progradeDirection IS vBefore:NORMALIZED.
		LOCAL normalDirection IS VCRS(progradeDirection, context["P"]):NORMALIZED.
		LOCAL radialDirection IS VCRS(normalDirection, progradeDirection):NORMALIZED.
		LOCAL burnVector IS context["u"] * plan["pieces"][k].
		ADD NODE(plan["times"][k], VDOT(burnVector, radialDirection), VDOT(burnVector, normalDirection), VDOT(burnVector, progradeDirection)).
	}
}

// Looks at the patches that the game predicts for the flight plan: each of the orbits before the last node must end at a maneuver node, not
// at an encounter with another body or an escape. If the game predicts fewer patches than there are nodes (the limit of conic patches) the
// rest cannot be looked at.
// Passed the following
//			number of nodes
// Returns "None" or the problem
FUNCTION ppassScan {
	PARAMETER nodeCount.
	LOCAL patchCursor IS SHIP:ORBIT.
	LOCAL maneuvers IS 0.
	LOCAL problem IS "None".
	UNTIL maneuvers >= nodeCount OR problem <> "None" {
		IF patchCursor:TRANSITION = "MANEUVER" SET maneuvers TO maneuvers + 1.
		ELSE IF patchCursor:TRANSITION = "FINAL" BREAK.
		ELSE SET problem TO "an orbit between the passes ends in " + patchCursor:TRANSITION + " (another body or an escape) before the final burn".
		IF problem = "None" AND maneuvers < nodeCount {
			IF NOT patchCursor:HASNEXTPATCH BREAK.
			SET patchCursor TO patchCursor:NEXTPATCH.
		}
	}
	IF problem = "None" AND maneuvers < nodeCount PRINT "  (the game predicts " + maneuvers + " of the " + nodeCount + " passes: the later ones cannot be checked)".
	RETURN problem.
}
