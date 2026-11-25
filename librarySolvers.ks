@LAZYGLOBAL OFF.

// ============================================================================
// librarySolvers.ks - solvers and numerical routines: the burn solver, the optimizers (hill climbing, gradient
// descent, golden section), the root finders, the Kepler equation and the orbit prediction helpers.
// loop.ks loads it (RUNPATH) after library.ks and libraryTransfer.ks, and it is one of the critical files that
// boot.ks keeps on the ship.
//
// The burn solver is built from two general parts and one configuration of them:
//   simulateTrajectory - integrates a powered flight (stages, staging times, spool, propellant, two body gravity). What the
//                        vehicle does is left to the delegates of a "model" lexicon: where it starts, its control (steering and
//                        throttle), an optional event that ends the flight, and the residual to minimize (see the description
//                        above simulateTrajectory).
//   fitTrajectory      - a Levenberg-Marquardt fit of any number of parameters to any number of residual numbers.
//   the node burn      - burnSolveSpec, nodeBurnInitial, nodeBurnControl, nodeBurnResidual, simulateBurn and solveBurnCorrection:
//                        the model that finds the ignition shift and thrust tilts that make a finite burn leave the orbit that
//                        the maneuver node predicted. Exec uses it. The rest of this comment is about that model.
//
// Why: Exec aims the thrust at the remaining delta V of the node, and ND:DELTAV is a velocity difference at
// the node time, so it cannot see the position the ship covers during a long burn. Flight logs of plane
// changes and ejections left the real orbit 1 to 20 km from the predicted one. A simulation of the burn in
// two body gravity reproduced those offsets to a few percent, and a two parameter fit of it cancelled them:
//   shift - the burn starts this many seconds LATER than the delta V centered ignition time (s).
//   tilt  - the thrust is tilted from the remaining delta V direction toward the local vertical (radians,
//           in the plane of that direction and the vertical).
// The shift is roughly 9E-6 * dV * burn time for the burns that were flown (about 7 s for a 3000 m/s,
// 250 s burn), the tilt is a fraction of a degree to about one degree.
//
// The model follows the burn control that Exec uses: steer at the remaining delta V (held below 1 m/s),
// full throttle, a proportional taper over the last taperTime seconds, and the burn ends when the remaining
// delta V is gone or, in the last energyPhaseDv, when the orbit energy reaches the node's orbit energy.
// It uses constant thrust and mass flow for each stage, and two body gravity. When a stage has burned all of its propellant the
// next stage starts after a time with no thrust (the staging time) and with the mass that the ship has then (see burnStageList).
// Engines that spool up, that
// take time to ignite or that have a minimum throttle (Real Fuels, Real Engines) are handled by the
// "spoolUp", "spoolDown", "ignitionDelay" and "minThrottle" options of burnSolveSpec.
//
// Frame: raw (non-rotating), relative to the central body, the same vectors as nodeOrbitSnapshot gives.
// Times are seconds, relative to the node time inside the simulation. Angles of the tilt are radians.
// ============================================================================

// Stumpff functions C2 and C3 of z, for the universal variable form of the Kepler problem
FUNCTION stumpffC2 {
	PARAMETER z.
	IF z > 1E-6 RETURN (1 - COS(SQRT(z) * CONSTANT:RADTODEG)) / z.
	IF z < -1E-6 {
		LOCAL root IS SQRT(-z).
		RETURN (CONSTANT:E ^ root + CONSTANT:E ^ (-root) - 2) / (2 * (-z)).
	}
	RETURN 0.5 - z / 24.
}

FUNCTION stumpffC3 {
	PARAMETER z.
	IF z > 1E-6 {
		LOCAL root IS SQRT(z).
		RETURN (root - SIN(root * CONSTANT:RADTODEG)) / (root * z).
	}
	IF z < -1E-6 {
		LOCAL root IS SQRT(-z).
		RETURN ((CONSTANT:E ^ root - CONSTANT:E ^ (-root)) / 2 - root) / (root * (-z)).
	}
	RETURN 1 / 6 - z / 120.
}

// Moves a position and velocity along their two body orbit by a time (universal variables, so it works for
// ellipses, parabolas and hyperbolas, forwards and backwards in time).
// Passed the following
//			position (vector, relative to the body)
//			velocity (vector)
//			deltaTime (scalar, s, negative goes back in time)
//			mu (scalar, m^3/s^2, of the body)
// Returns a LIST of the new position and the new velocity
FUNCTION keplerPropagate {
	PARAMETER startPosition.
	PARAMETER startVelocity.
	PARAMETER deltaTime.
	PARAMETER mu.

	IF deltaTime = 0 RETURN LIST(startPosition, startVelocity).
	LOCAL startRadius IS startPosition:MAG.
	LOCAL radialSpeed IS VDOT(startPosition, startVelocity) / startRadius.
	LOCAL alpha IS 2 / startRadius - startVelocity:SQRMAGNITUDE / mu.			// 1 / semi major axis
	LOCAL sqrtMu IS SQRT(mu).
	LOCAL chi IS sqrtMu * deltaTime / startRadius.
	IF alpha > 1E-12 SET chi TO sqrtMu * deltaTime * alpha.
	LOCAL z IS 0.
	LOCAL c2 IS 0.5.
	LOCAL c3 IS 1 / 6.
	FROM {LOCAL iteration IS 0.} UNTIL iteration >= 60 STEP {SET iteration TO iteration + 1.} DO {
		SET z TO alpha * chi ^ 2.
		SET c2 TO stumpffC2(z).
		SET c3 TO stumpffC3(z).
		LOCAL equation IS startRadius * radialSpeed / sqrtMu * chi ^ 2 * c2 + (1 - alpha * startRadius) * chi ^ 3 * c3 + startRadius * chi - sqrtMu * deltaTime.
		LOCAL equationSlope IS startRadius * radialSpeed / sqrtMu * chi * (1 - z * c3) + (1 - alpha * startRadius) * chi ^ 2 * c2 + startRadius.
		LOCAL change IS equation / equationSlope.
		SET chi TO chi - change.
		IF ABS(change) < 1E-9 BREAK.
	}
	SET z TO alpha * chi ^ 2.
	SET c2 TO stumpffC2(z).
	SET c3 TO stumpffC3(z).
	LOCAL lagrangeF IS 1 - chi ^ 2 / startRadius * c2.
	LOCAL lagrangeG IS deltaTime - chi ^ 3 / sqrtMu * c3.
	LOCAL newPosition IS lagrangeF * startPosition + lagrangeG * startVelocity.
	LOCAL newRadius IS newPosition:MAG.
	LOCAL lagrangeFDot IS sqrtMu / (newRadius * startRadius) * (z * c3 - 1) * chi.
	LOCAL lagrangeGDot IS 1 - chi ^ 2 / newRadius * c2.
	RETURN LIST(newPosition, lagrangeFDot * startPosition + lagrangeGDot * startVelocity).
}

// The thrust direction the model steers at: the remaining delta V direction, tilted by tilt1 toward the local
// vertical (the part of the position perpendicular to that direction) and by tilt2 toward the third axis.
FUNCTION burnSteering {
	PARAMETER shipPosition.
	PARAMETER holdVector.
	PARAMETER tilt1.
	PARAMETER tilt2.

	LOCAL burnDirection IS holdVector:NORMALIZED.
	IF tilt1 = 0 AND tilt2 = 0 RETURN burnDirection.
	LOCAL verticalPerp IS (shipPosition - burnDirection * VDOT(shipPosition, burnDirection)):NORMALIZED.
	RETURN (burnDirection + tilt1 * verticalPerp + tilt2 * VCRS(burnDirection, verticalPerp)):NORMALIZED.
}

// Gravity acceleration at a position
FUNCTION burnGravity {
	PARAMETER shipPosition.
	PARAMETER mu.
	RETURN shipPosition * (-mu / shipPosition:MAG ^ 3).
}

// Builds the node burn model (a model for simulateTrajectory and fitTrajectory). Call it before the burn, with everything about
// the burn's engines already known (shipInfo after updateShipInfo gives thrust, mass flow and mass).
// Passed the following
//			nodeSnapshot (lexicon, from nodeOrbitSnapshot(node): "Body", "NodePosition", "NodeVelocity")
//			burnVector (vector, ND:DELTAV before the burn, raw)
//			burnThrust (scalar, N, of the engines at full throttle)
//			flowRate (scalar, kg/s, of the same engines)
//			startMass (scalar, kg, of the whole ship)
//			options (lexicon, all optional):
//				"ignitionLead"  - s before the node that Exec ignites when the shift is 0. The default is the time to
//								  deliver half of the delta V (the delta V centered ignition).
//				"spoolUp", "spoolDown" - s for the thrust to go from 0 to full and back (0 = instant).
//				"ignitionDelay" - s from the ignition command to the first thrust (0 = none).
//				"minThrottle"   - the lowest throttle the engines can hold (0 = any).
//				"throttleable"  - FALSE for engines that cannot be throttled (no taper).
//				"stages"        - for a burn that uses several stages, a list in burn order of the lexicons that burnStageList makes
//								  (thrust, flowRate, wetMass, propellant, gap, throttleable, minThrottle). When it is given, burnThrust,
//								  flowRate and startMass only matter for the first stage's numbers in the result, and "throttleable" and
//								  "minThrottle" come from each stage.
//				"taperTime", "finishDv", "energyCutoff", "energyPhaseDv", "tickTime", "step" - the burn control
//				constants, which default to those of Exec. The default "step" (the longest step of the simulation, s) is 2 s,
//				or for a burn longer than 2000 s the burn time / 1000, so that the simulation (limited to 1500 steps) can
//				finish it, but never more than a fiftieth of the time scale of the orbit at the node, sqrt(r^3 / mu) (7.5 s at 780 km
//				from Kerbin), which keeps the integration accurate. The simulation of a burn too long for that still ends on its
//				step limit, and solverResultError does not accept it.
// Returns a lexicon that the other functions in this file take
FUNCTION burnSolveSpec {
	PARAMETER nodeSnapshot.
	PARAMETER burnVector.
	PARAMETER burnThrust.
	PARAMETER flowRate.
	PARAMETER startMass.
	PARAMETER options IS LEXICON().

	LOCAL mu IS nodeSnapshot["Body"]:MU.
	LOCAL exhaustSpeed IS burnThrust / flowRate.
	LOCAL totalDeltaV IS burnVector:MAG.
	LOCAL halfBurn IS burnTime(startMass, flowRate, totalDeltaV / 2, exhaustSpeed).
	LOCAL totalBurn IS burnTime(startMass, flowRate, totalDeltaV, exhaustSpeed).
	LOCAL stageList IS LIST().
	IF options:HASKEY("stages") {
		SET stageList TO options["stages"].
		LOCAL times IS stagedBurnTimes(stageList, totalDeltaV).
		SET totalBurn TO times[0].
		SET halfBurn TO times[1].
	} ELSE {
		// one stage with all the propellant that the burn could need
		stageList:ADD(LEXICON("thrust", burnThrust, "flowRate", flowRate, "wetMass", startMass, "propellant", 1E12, "gap", 0,
								"throttleable", TRUE, "minThrottle", 0)).
	}
	LOCAL nodePosition IS nodeSnapshot["NodePosition"].
	LOCAL nodeVelocity IS nodeSnapshot["NodeVelocity"].
	LOCAL targetVelocity IS nodeVelocity + burnVector.
	LOCAL evaluationTime IS totalBurn + 20.									// when the actual orbit and the predicted orbit are compared (s after the node)

	LOCAL spec IS LEXICON(
		"mu", mu,
		"nodePosition", nodePosition,
		"nodeVelocity", nodeVelocity,
		"burnVector", burnVector,
		"targetVelocity", targetVelocity,
		"thrust", burnThrust,
		"flowRate", flowRate,
		"mass", startMass,
		"halfBurn", halfBurn,
		"totalBurn", totalBurn,
		"evaluationTime", evaluationTime,
		"predicted", keplerPropagate(nodePosition, targetVelocity, evaluationTime, mu),
		"stages", stageList,
		"nodeEnergy", targetVelocity:SQRMAGNITUDE / 2 - mu / nodePosition:MAG,		// specific orbital energy of the node's orbit (J/kg)
		"initial", nodeBurnInitial@,											// the delegates of the node burn model (see simulateTrajectory)
		"control", nodeBurnControl@,
		"residual", nodeBurnResidual@,
		"shiftGuess", 9E-6 * totalDeltaV * totalBurn).							// from the flown burns: shift (s) = 9E-6 * dV (m/s) * burn time (s)

	// the longest step: 2 s, longer for a long burn (see the option "step")
	LOCAL orbitTimeScale IS SQRT(nodePosition:MAG ^ 3 / mu).
	LOCAL scaledStep IS MAX(2, MIN(totalBurn / 1000, orbitTimeScale / 50)).

	// the options and their defaults
	LOCAL defaults IS LEXICON("ignitionLead", halfBurn, "spoolUp", 0, "spoolDown", 0, "ignitionDelay", 0, "minThrottle", 0,
		"throttleable", TRUE, "taperTime", 0.5, "finishDv", 0.25, "energyCutoff", TRUE, "energyPhaseDv", 20, "tickTime", 0.05, "step", scaledStep,
		"abort", neverAbort@).													// a delegate that returns TRUE to stop the solver (abortKeyPressed@)
	FOR optionName IN defaults:KEYS {
		IF options:HASKEY(optionName) spec:ADD(optionName, options[optionName]).
		ELSE spec:ADD(optionName, defaults[optionName]).
	}
	IF NOT options:HASKEY("stages") {
		SET stageList[0]["throttleable"] TO spec["throttleable"].
		SET stageList[0]["minThrottle"] TO spec["minThrottle"].
	}
	RETURN spec.
}

// Solver Time Estimate
// About how long solveBurnCorrection takes for a burn spec, in game seconds: the 13 simulations of a solve that converges in 3 iterations,
// each of the steps at the spec's step size and about 100 short steps near the end, at about 15 ms a step. Flown solves: 5 simulations
// in 9 to 11 s, 13 in 25 to 31 s (for burns of 220 s, where this gives 41 s), and 23 (10 iterations) in 39 s for a 133 s burn.
// Passed the following
//			spec (lexicon, from burnSolveSpec)
// Returns a scalar, s
FUNCTION solverTimeEstimate {
	PARAMETER spec.
	RETURN 13 * (spec["totalBurn"] / spec["step"] + 100) * 0.015.
}

// The time with no thrust while a burn stages. The engines of the next stage light as soon as the STAGE command that fires them runs,
// so the time with no thrust is the reaction time of the control loop, plus the time of each STAGE command before that one (the
// stages in between that have no engines of their own are dropped first, one command per loop iteration).
// Passed the following
//			stage numbers dropped (scalar, the difference of the shipInfo stage numbers of the two stages; at least one command is used)
//			reactionTime (scalar, s)
//			commandTime (scalar, s, what each earlier command takes)
// Returns a scalar, s
FUNCTION stagingGap {
	PARAMETER stageCommands.
	PARAMETER reactionTime.
	PARAMETER commandTime.

	RETURN reactionTime + (MAX(1, stageCommands) - 1) * commandTime.
}

// Makes the stage list that burnSolveSpec takes (option "stages") from the stages of shipInfo that the burn uses.
// Passed the following
//			usedStages (list of shipInfo stage lexicons, in the order that they burn; Exec's usedStages)
//			firstIndex, lastIndex (scalars, the positions in usedStages of the first and last stage that the burn uses)
//			reactionTime (scalar, s, from the flameout of a stage to the STAGE command that starts the next one: the control loop's own
//				iteration. The engines of the next stage light as soon as that command runs. Flown burn: about 0.1 s.)
//			commandTime (scalar, s, what each further STAGE command takes: the wait of stageFunction and the rebuild of shipInfo. Flown
//				burns: 1.1 to 1.3 s each. Only matters when a stage in between has no engines of its own.)
// Returns a LIST of lexicons, one per stage, of
//			"thrust" (N), "flowRate" (kg/s), "wetMass" (kg, of the whole ship when the stage starts), "propellant" (kg, that the stage burns),
//			"gap" (s with no thrust before the stage starts, see stagingGap; 0 for the first stage), "throttleable" and
//			"minThrottle" (the fraction)
FUNCTION burnStageList {
	PARAMETER usedStages.
	PARAMETER firstIndex.
	PARAMETER lastIndex.
	PARAMETER reactionTime IS 0.15.
	PARAMETER commandTime IS 1.2.

	LOCAL stageList IS LIST().
	FROM {LOCAL index IS firstIndex.} UNTIL index > lastIndex STEP {SET index TO index + 1.} DO {
		LOCAL stageInfo IS usedStages[index].
		LOCAL gapTime IS 0.
		IF index > firstIndex SET gapTime TO stagingGap(usedStages[index - 1]["Number"] - stageInfo["Number"], reactionTime, commandTime).
		LOCAL lowestThrottle IS 0.
		IF stageInfo:HASKEY("HighestMinThrottle") SET lowestThrottle TO stageInfo["HighestMinThrottle"].
		stageList:ADD(LEXICON("thrust", stageInfo["Thrust"], "flowRate", stageInfo["mDot"], "wetMass", stageInfo["CurrentMass"],
								"propellant", stageInfo["FuelMass"], "gap", gapTime, "throttleable", stageInfo["Throttleable"],
								"minThrottle", lowestThrottle)).
	}
	RETURN stageList.
}

// How long a burn of several stages takes at full throttle, with the time of each staging included.
// Passed the following
//			stageList (list of lexicons, see burnStageList)
//			deltaV (scalar, m/s)
// Returns a LIST of the total time (s) and the time (s) at which half of the delta V has been delivered, both from the first thrust
FUNCTION stagedBurnTimes {
	PARAMETER stageList.
	PARAMETER deltaV.

	LOCAL elapsed IS 0.
	LOCAL deltaVDone IS 0.
	LOCAL halfTime IS -1.
	FOR eachStage IN stageList {
		IF deltaVDone >= deltaV BREAK.
		LOCAL exhaustSpeed IS eachStage["thrust"] / eachStage["flowRate"].
		LOCAL deltaVAvailable IS exhaustSpeed * LN(eachStage["wetMass"] / (eachStage["wetMass"] - eachStage["propellant"])).
		LOCAL deltaVStage IS MIN(deltaV - deltaVDone, deltaVAvailable).
		IF deltaVDone > 0 SET elapsed TO elapsed + eachStage["gap"].
		IF halfTime < 0 AND deltaVDone + deltaVStage >= deltaV / 2 {
			SET halfTime TO elapsed + burnTime(eachStage["wetMass"], eachStage["flowRate"], deltaV / 2 - deltaVDone, exhaustSpeed).
		}
		SET elapsed TO elapsed + burnTime(eachStage["wetMass"], eachStage["flowRate"], deltaVStage, exhaustSpeed).
		SET deltaVDone TO deltaVDone + deltaVStage.
	}
	IF halfTime < 0 SET halfTime TO elapsed.
	RETURN LIST(elapsed, halfTime).
}

// ============================================================================
// The general trajectory simulation. It integrates a powered flight (RK4 in two body gravity) with the stages, the staging
// times, the engine spool and the propellant, and leaves everything that is specific to one kind of flight to the delegates
// of a "model" lexicon, so that the same simulation and the same fit (fitTrajectory) can serve a node burn, a suicide burn,
// a landing at a target and so on. The node burn is one such model: see burnSolveSpec and nodeBurnInitial, nodeBurnControl
// and nodeBurnResidual below.
//
// A model is a lexicon with the following keys. Every delegate gets the model first, so a delegate can be a plain function
// (make it with name@), and everything it needs is kept in the model.
//   "mu"          scalar, m^3/s^2, of the body
//   "stages"      list of stage lexicons in burn order, see burnStageList
//   "step"        scalar, s, the longest integration step
//   "spoolUp", "spoolDown"  scalars, s for the thrust to go from 0 to full and back (0 = instant)
//   "initial"     delegate (model, parameters) -> LIST(position, velocity, clock, thrustStart)
//                 where the flight starts: the position (vector) and velocity (vector) relative to the body, the clock (s, any
//                 reference that the other delegates agree on) and the clock time of the first thrust (s, not before the clock)
//   "control"     delegate (model, parameters, state) -> LIST(direction, throttle, done, reason, stepLimit)
//                 what the vehicle does at this moment: the thrust direction (unit vector), the commanded throttle (0 to 1), whether
//                 the control has finished (the throttle is then cut and the thrust dies away), the reason for finishing
//                 (string), and the longest step that is accurate for now (s). The state is a lexicon of
//                   "position", "velocity" (vectors), "clock" (s), "mass" (kg, of the whole ship), "level" (the thrust now as a
//                   fraction of full), "fullAccel" (m/s^2 of the stage that is burning, at full throttle), "ending" (TRUE once the
//                   control has finished and the thrust is dying away; the throttle returned is then ignored), "throttleable" and
//                   "minThrottle" (of the stage that is burning), "stageIndex" (0 for the first stage) and "memory" (an empty
//                   lexicon that belongs to the control, to keep what it needs from one step to the next).
//                 The core takes care of the time before the first thrust, of the staging gaps, and of the end of the propellant.
//   "event"       optional delegate (model, parameters, state) -> string. Called after every step; any text other than "" ends
//                 the flight at once with that text as the reason (a surface contact, for example).
//   "abort"       optional delegate () -> boolean (abortKeyPressed@ in library.ks). Checked every 20 steps; when it returns TRUE
//                 the flight ends where it is with the reason "aborted", and fitTrajectory stops. The results are then not meaningful.
//   "residual"    delegate (model, parameters) -> LIST of numbers, the error that fitTrajectory drives to zero. It runs
//                 simulateTrajectory itself, and decides what is compared with what.
// The parameters are a LIST of numbers that the fit changes. The core does not look inside them.
// ============================================================================

// Simulates a flight of a model, with a list of parameters.
// Passed the following
//			model (lexicon, see above)
//			parameters (list of numbers, given to the delegates)
// Returns a lexicon of "position" and "velocity" (at the end of the flight, relative to the body), "clock" (s, the clock at the end),
//		"mass" (kg), "endTime" (s, the clock when the control finished or the event happened), "burnTime" (s from the first thrust to
//		endTime, including the time with no thrust while staging), "endReason", "steps", "stagesBurned" (how many stages thrusted)
//		and "lowestRadius" (m, the smallest distance from the body's center at the end of any step)
FUNCTION simulateTrajectory {
	PARAMETER model.
	PARAMETER parameters.

	LOCAL mu IS model["mu"].
	LOCAL stageList IS model["stages"].
	LOCAL controlDelegate IS model["control"].
	LOCAL hasEvent IS model:HASKEY("event").
	LOCAL eventDelegate IS 0.
	IF hasEvent SET eventDelegate TO model["event"].
	LOCAL stageIndex IS 0.
	LOCAL burnThrust IS stageList[0]["thrust"].									// of the stage that is burning now
	LOCAL flowRate IS stageList[0]["flowRate"].
	LOCAL propellantLeft IS stageList[0]["propellant"].							// what the stage still has to burn (kg)
	LOCAL gapEnd IS -1E9.														// no thrust until this time, while the stages separate
	LOCAL emptied IS FALSE.														// the last stage is out of propellant
	LOCAL bigStep IS model["step"].
	LOCAL riseRate IS 1E9.
	IF model["spoolUp"] > 0 SET riseRate TO 1 / model["spoolUp"].
	LOCAL fallRate IS 1E9.
	IF model["spoolDown"] > 0 SET fallRate TO 1 / model["spoolDown"].
	LOCAL spooling IS model["spoolUp"] > 0 OR model["spoolDown"] > 0.

	LOCAL initial IS model["initial"]:CALL(model, parameters).
	LOCAL shipPosition IS initial[0].
	LOCAL shipVelocity IS initial[1].
	LOCAL clock IS initial[2].
	LOCAL thrustStart IS initial[3].
	LOCAL shipMass IS stageList[0]["wetMass"].
	LOCAL level IS 0.															// the thrust now, as a fraction of full thrust
	LOCAL lowestRadius IS shipPosition:MAG.										// the smallest distance from the body's center that the flight reaches

	LOCAL ending IS FALSE.
	LOCAL endReason IS "step limit".
	LOCAL endTime IS clock.
	LOCAL steps IS 0.
	LOCAL state IS LEXICON("position", shipPosition, "velocity", shipVelocity, "clock", clock, "mass", shipMass, "level", 0,
							"fullAccel", 0, "ending", FALSE, "throttleable", stageList[0]["throttleable"],
							"minThrottle", stageList[0]["minThrottle"], "stageIndex", 0, "memory", LEXICON()).

	LOCAL abortDelegate IS neverAbort@.
	IF model:HASKEY("abort") SET abortDelegate TO model["abort"].

	UNTIL steps >= 1500 {
		// the abort check, every 20 steps (a step takes about 15 ms); the flight ends where it is, and its result is not meaningful
		IF MOD(steps, 20) = 0 AND abortDelegate:CALL() {
			SET endReason TO "aborted".
			SET endTime TO clock.
			BREAK.
		}

		// a stage that has burned all of its propellant is dropped: the next one starts after the time with no thrust, with the
		// mass that the whole ship has then
		IF (NOT ending) AND propellantLeft <= 0.001 {
			IF stageIndex >= stageList:LENGTH - 1 SET emptied TO TRUE.
			ELSE {
				SET stageIndex TO stageIndex + 1.
				LOCAL nextStage IS stageList[stageIndex].
				SET burnThrust TO nextStage["thrust"].
				SET flowRate TO nextStage["flowRate"].
				SET propellantLeft TO nextStage["propellant"].
				SET shipMass TO nextStage["wetMass"].
				SET gapEnd TO clock + nextStage["gap"].
				SET level TO 0.
				SET state["throttleable"] TO nextStage["throttleable"].
				SET state["minThrottle"] TO nextStage["minThrottle"].
				SET state["stageIndex"] TO stageIndex.
			}
		}

		// what the control wants now
		LOCAL fullAccel IS burnThrust / shipMass.
		SET state["position"] TO shipPosition.
		SET state["velocity"] TO shipVelocity.
		SET state["clock"] TO clock.
		SET state["mass"] TO shipMass.
		SET state["level"] TO level.
		SET state["fullAccel"] TO fullAccel.
		SET state["ending"] TO ending.
		LOCAL decision IS controlDelegate:CALL(model, parameters, state).
		LOCAL steerDirection IS decision[0].

		LOCAL commanded IS 0.
		IF NOT ending {
			LOCAL done IS decision[2].
			LOCAL doneReason IS decision[3].
			IF emptied {
				SET done TO TRUE.
				SET doneReason TO "propellant".
			}
			IF done {
				SET ending TO TRUE.
				SET endTime TO clock.
				SET endReason TO doneReason.
			} ELSE IF clock < thrustStart OR clock < gapEnd {					// the ignition sequence or the staging is still running
				SET commanded TO 0.
			} ELSE SET commanded TO decision[1].
		}
		IF ending AND level <= 1E-9 BREAK.

		// the step: what the control allows, short while the thrust is changing, and ending exactly when the thrust starts, when a
		// stage's thrust ends and when a stage's propellant does
		LOCAL stepSize IS bigStep.
		IF NOT ending SET stepSize TO MIN(stepSize, decision[4]).
		IF spooling AND ABS(commanded - level) > 0.001 SET stepSize TO MIN(stepSize, 0.25).
		IF (NOT ending) AND clock < thrustStart SET stepSize TO MIN(stepSize, MAX(thrustStart - clock, 0.000001)).
		IF (NOT ending) AND clock < gapEnd SET stepSize TO MIN(stepSize, MAX(gapEnd - clock, 0.000001)).
		IF (NOT ending) AND commanded > 0 SET stepSize TO MIN(stepSize, MAX(propellantLeft / (flowRate * MAX(commanded, level)), 0.000001)).
		LOCAL newLevel IS level + MAX(-fallRate * stepSize, MIN(riseRate * stepSize, commanded - level)).
		// the thrust used over the step: a jump is taken at once in a direction without spool, otherwise the average
		LOCAL usedLevel IS newLevel.
		IF commanded > level AND model["spoolUp"] > 0 SET usedLevel TO (level + newLevel) / 2.
		IF commanded <= level AND model["spoolDown"] > 0 SET usedLevel TO (level + newLevel) / 2.

		LOCAL accelFirst IS steerDirection * (usedLevel * burnThrust / shipMass).
		LOCAL velocity1 IS shipVelocity.
		LOCAL accel1 IS burnGravity(shipPosition, mu) + accelFirst.
		LOCAL position2 IS shipPosition + velocity1 * (stepSize / 2).
		LOCAL velocity2 IS shipVelocity + accel1 * (stepSize / 2).
		LOCAL midMass IS shipMass - flowRate * usedLevel * stepSize / 2.
		LOCAL accelMid IS steerDirection * (usedLevel * burnThrust / midMass).
		LOCAL accel2 IS burnGravity(position2, mu) + accelMid.
		LOCAL position3 IS shipPosition + velocity2 * (stepSize / 2).
		LOCAL velocity3 IS shipVelocity + accel2 * (stepSize / 2).
		LOCAL accel3 IS burnGravity(position3, mu) + accelMid.
		LOCAL position4 IS shipPosition + velocity3 * stepSize.
		LOCAL velocity4 IS shipVelocity + accel3 * stepSize.
		LOCAL lastMass IS shipMass - flowRate * usedLevel * stepSize.
		LOCAL accel4 IS burnGravity(position4, mu) + steerDirection * (usedLevel * burnThrust / lastMass).
		SET shipPosition TO shipPosition + (velocity1 + 2 * velocity2 + 2 * velocity3 + velocity4) * (stepSize / 6).
		SET shipVelocity TO shipVelocity + (accel1 + 2 * accel2 + 2 * accel3 + accel4) * (stepSize / 6).
		SET shipMass TO lastMass.
		SET propellantLeft TO propellantLeft - flowRate * usedLevel * stepSize.
		SET clock TO clock + stepSize.
		SET level TO newLevel.
		SET steps TO steps + 1.
		LOCAL stepRadius IS shipPosition:MAG.
		IF stepRadius < lowestRadius SET lowestRadius TO stepRadius.

		IF hasEvent {
			SET state["position"] TO shipPosition.
			SET state["velocity"] TO shipVelocity.
			SET state["clock"] TO clock.
			SET state["mass"] TO shipMass.
			SET state["level"] TO level.
			LOCAL eventReason IS eventDelegate:CALL(model, parameters, state).
			IF eventReason <> "" {
				SET endReason TO eventReason.
				SET endTime TO clock.
				SET ending TO TRUE.
				BREAK.
			}
		}
	}
	IF NOT ending SET endTime TO clock.

	RETURN LEXICON("position", shipPosition, "velocity", shipVelocity, "clock", clock, "mass", shipMass, "endTime", endTime,
					"burnTime", endTime - thrustStart, "endReason", endReason, "steps", steps, "stagesBurned", stageIndex + 1,
					"lowestRadius", lowestRadius).
}

// The node burn model, part 1: where the flight starts. The parameters are LIST(shift, tilt1, tilt2). The ship is on the orbit
// that it has before the node, at the time of the ignition, which is the model's "ignitionLead" before the node moved later by the shift.
// The clock is the time (s) after the node.
FUNCTION nodeBurnInitial {
	PARAMETER model.
	PARAMETER parameters.

	LOCAL ignitionTime IS parameters[0] - model["ignitionLead"].
	LOCAL start IS keplerPropagate(model["nodePosition"], model["nodeVelocity"], ignitionTime, model["mu"]).
	RETURN LIST(start[0], start[1], ignitionTime, ignitionTime + model["ignitionDelay"]).
}

// The node burn model, part 2: the control, which is what Exec does. It steers at the remaining delta V (held below 1 m/s) tilted by
// tilt1 and tilt2 (burnSteering), at full throttle, with a proportional taper over the last taperTime seconds, and it finishes when
// the remaining delta V is gone or, in the last energyPhaseDv, when the orbit energy reaches the energy of the node's orbit. The
// remaining delta V is the velocity wanted at the node minus the velocity at the node time of the orbit that the ship is on now.
FUNCTION nodeBurnControl {
	PARAMETER model.
	PARAMETER parameters.
	PARAMETER state.

	LOCAL memory IS state["memory"].
	LOCAL shipPosition IS state["position"].
	LOCAL shipVelocity IS state["velocity"].
	LOCAL mu IS model["mu"].
	LOCAL atNode IS keplerPropagate(shipPosition, shipVelocity, -state["clock"], mu).
	LOCAL remaining IS model["targetVelocity"] - atNode[1].
	LOCAL remainingMag IS remaining:MAG.
	IF NOT memory:HASKEY("firstRemaining") {
		memory:ADD("firstRemaining", remaining).
		memory:ADD("holdVector", remaining).
		memory:ADD("energySide", 0).
	}
	IF remainingMag > 1 SET memory["holdVector"] TO remaining.
	LOCAL fullAccel IS state["fullAccel"].
	LOCAL timeToGo IS remainingMag / fullAccel.
	LOCAL steerDirection IS burnSteering(shipPosition, memory["holdVector"], parameters[1], parameters[2]).

	// the step: short near the end
	LOCAL stepLimit IS 1E9.
	IF timeToGo < 2 * model["step"] SET stepLimit TO MIN(model["step"], 0.1).
	IF timeToGo < 0.6 SET stepLimit TO 0.05.

	LOCAL commanded IS 0.
	LOCAL done IS FALSE.
	LOCAL reason IS "remaining delta V".
	IF NOT state["ending"] {
		SET done TO (VDOT(memory["firstRemaining"], remaining) < 0) OR (remainingMag < model["finishDv"]).
		IF (NOT done) AND model["energyCutoff"] AND remainingMag < model["energyPhaseDv"] {
			LOCAL energyError IS shipVelocity:SQRMAGNITUDE / 2 - mu / shipPosition:MAG - model["nodeEnergy"].
			// thrust that is still dying away after the cutoff adds (or removes) energy, so the burn ends early by that much
			IF model["spoolDown"] > 0 SET energyError TO energyError + VDOT(shipVelocity, steerDirection) * state["level"] * fullAccel * model["spoolDown"] / 2.
			IF memory["energySide"] = 0 {
				IF energyError > 20 SET memory["energySide"] TO 1.
				ELSE IF energyError < -20 SET memory["energySide"] TO -1.
			} ELSE IF energyError * memory["energySide"] <= 0 {
				SET done TO TRUE.
				SET reason TO "orbit energy reached".
			}
		}
		IF NOT done {
			SET commanded TO 1.
			IF state["throttleable"] AND timeToGo <= model["taperTime"] {
				SET commanded TO timeToGo / model["taperTime"].
				IF commanded < state["minThrottle"] {
					IF remainingMag <= state["minThrottle"] * fullAccel * model["tickTime"] * 2 SET done TO TRUE.
					ELSE SET commanded TO state["minThrottle"].
				}
			}
		}
	}
	RETURN LIST(steerDirection, commanded, done, reason, stepLimit).
}

// The node burn model, part 3: the residual. It is the error of the simulated burn against the predicted orbit at the evaluation
// time, as a LIST of six numbers: the position error (m) in x, y and z, then the velocity error (m/s) times 1000 in x, y and z.
// The parameters are LIST(shift, tilt1, tilt2).
FUNCTION nodeBurnResidual {
	PARAMETER model.
	PARAMETER parameters.

	LOCAL result IS simulateBurn(model, parameters[0], parameters[1], parameters[2]).
	LOCAL predicted IS model["predicted"].
	LOCAL positionError IS result["position"] - predicted[0].
	LOCAL velocityError IS (result["velocity"] - predicted[1]) * 1000.
	RETURN LIST(positionError:X, positionError:Y, positionError:Z, velocityError:X, velocityError:Y, velocityError:Z).
}

// Simulates the node burn: RK4 in two body gravity, steering and ending like Exec, with the ignition shifted and the
// thrust tilted. Returns the state at the spec's evaluation time.
// Passed the following
//			spec (lexicon, from burnSolveSpec)
//			shift (scalar, s, later ignition than Exec's own)
//			tilt1, tilt2 (scalars, radians, see burnSteering)
// Returns a lexicon of "position" and "velocity" (at the evaluation time), "endTime" (s after the node that the
//		burn ended), "burnTime" (s of the burn, including the time with no thrust while staging), "endReason", "steps",
//		"stagesBurned" (how many stages thrusted) and "lowestRadius" (m from the body's center, during the burn)
FUNCTION simulateBurn {
	PARAMETER spec.
	PARAMETER shift.
	PARAMETER tilt1 IS 0.
	PARAMETER tilt2 IS 0.

	LOCAL raw IS simulateTrajectory(spec, LIST(shift, tilt1, tilt2)).
	LOCAL final IS keplerPropagate(raw["position"], raw["velocity"], spec["evaluationTime"] - raw["clock"], spec["mu"]).
	RETURN LEXICON("position", final[0], "velocity", final[1], "endTime", raw["endTime"], "burnTime", raw["burnTime"],
					"endReason", raw["endReason"], "steps", raw["steps"], "stagesBurned", raw["stagesBurned"], "lowestRadius", raw["lowestRadius"]).
}

// The residual of a simulated node burn (see nodeBurnResidual), with the parameters as separate numbers
FUNCTION burnResidual {
	PARAMETER spec.
	PARAMETER shift.
	PARAMETER tilt1.
	PARAMETER tilt2 IS 0.
	RETURN nodeBurnResidual(spec, LIST(shift, tilt1, tilt2)).
}

// The sum of the squares of a residual: for a node burn, the position error (m) squared plus the velocity error (m/s) times 1000 squared.
FUNCTION residualCost {
	PARAMETER residual.
	LOCAL total IS 0.
	FOR eachValue IN residual SET total TO total + eachValue ^ 2.
	RETURN total.
}

// How far a simulated node burn ends from the predicted orbit, as the square root of its residualCost (m)
FUNCTION burnMiss {
	PARAMETER spec.
	PARAMETER shift.
	PARAMETER tilt1.
	PARAMETER tilt2 IS 0.
	RETURN SQRT(residualCost(burnResidual(spec, shift, tilt1, tilt2))).
}

// Solves a small square linear system, matrix * answer = vector, by Gaussian elimination with row swaps.
// Passed the following
//			matrix (list of lists, one list per row)
//			vector (list)
// Returns a LIST of the answer, or a list of zeros if the matrix is singular
FUNCTION solveLinearSystem {
	PARAMETER coefficients.
	PARAMETER constants.

	LOCAL systemSize IS constants:LENGTH.
	LOCAL rows IS LIST().
	FOR eachRow IN coefficients rows:ADD(eachRow:COPY).
	LOCAL rightSide IS constants:COPY.
	LOCAL zeros IS LIST().
	FROM {LOCAL index IS 0.} UNTIL index >= systemSize STEP {SET index TO index + 1.} DO zeros:ADD(0).

	FROM {LOCAL column IS 0.} UNTIL column >= systemSize STEP {SET column TO column + 1.} DO {
		LOCAL pivotRow IS column.
		FROM {LOCAL row IS column + 1.} UNTIL row >= systemSize STEP {SET row TO row + 1.} DO {
			IF ABS(rows[row][column]) > ABS(rows[pivotRow][column]) SET pivotRow TO row.
		}
		IF ABS(rows[pivotRow][column]) < 1E-30 RETURN zeros.
		IF pivotRow <> column {
			LOCAL swapRow IS rows[column].
			SET rows[column] TO rows[pivotRow].
			SET rows[pivotRow] TO swapRow.
			LOCAL swapValue IS rightSide[column].
			SET rightSide[column] TO rightSide[pivotRow].
			SET rightSide[pivotRow] TO swapValue.
		}
		FROM {LOCAL row IS column + 1.} UNTIL row >= systemSize STEP {SET row TO row + 1.} DO {
			LOCAL factor IS rows[row][column] / rows[column][column].
			LOCAL changedRow IS rows[row].
			LOCAL pivotList IS rows[column].
			FROM {LOCAL entry IS column.} UNTIL entry >= systemSize STEP {SET entry TO entry + 1.} DO {
				SET changedRow[entry] TO changedRow[entry] - factor * pivotList[entry].
			}
			SET rightSide[row] TO rightSide[row] - factor * rightSide[column].
		}
	}

	LOCAL answer IS zeros:COPY.
	FROM {LOCAL row IS systemSize - 1.} UNTIL row < 0 STEP {SET row TO row - 1.} DO {
		LOCAL total IS rightSide[row].
		FROM {LOCAL entry IS row + 1.} UNTIL entry >= systemSize STEP {SET entry TO entry + 1.} DO {
			SET total TO total - rows[row][entry] * answer[entry].
		}
		SET answer[row] TO total / rows[row][row].
	}
	RETURN answer.
}

// Finds the parameters that make the residual of a model small. It is a damped Gauss-Newton (Levenberg-Marquardt) fit: each iteration
// measures how every residual number changes with each parameter (one simulation per parameter), solves for the move, and tries it
// (1 simulation). A move that makes the miss worse is not taken; the damping is raised and the move recalculated (1 simulation
// per try). It has converged when every parameter's move is smaller than its entry of smallMoves, or the miss is below costTolerance.
// If it has not converged after the planned iterations and it is still earlier than extendUntil, it carries on for up to as many
// iterations again, checking before each one. Whatever happens, it returns the best parameters found.
// Passed the following
//			model (lexicon, see simulateTrajectory: its "residual" delegate is what is minimized)
//			startParameters (list of numbers, the starting guess)
//			options (lexicon)
//				"probeSteps"    - list, one step for each parameter, for measuring the slopes (the same units as the parameter)
//				"largestMoves"  - list, the largest change of each parameter in one iteration
//				"smallMoves"    - list, a move of every parameter smaller than these is converged
//				"iterations"    - scalar, the planned number of iterations (default 5)
//				"extendUntil"   - scalar, UT in s, the extra iterations are only started before this (default: always)
//				"costTolerance" - scalar, the sum of the squares of the residual (default 1E4) below which the fit is good enough
// Returns a lexicon of "parameters" (list), "miss" (the square root of the sum of the squares of the residual), "startMiss" (the same
//		with the starting guess), "converged" (boolean), "iterations" (the number done), "extended" (boolean, whether it went past the
//		planned iterations), "evaluations" (simulations) and "seconds" (real time that it took)
FUNCTION fitTrajectory {
	PARAMETER model.
	PARAMETER startParameters.
	PARAMETER options.

	LOCAL startReal IS KUNIVERSE:REALTIME.
	LOCAL parameterCount IS startParameters:LENGTH.
	LOCAL probeSteps IS options["probeSteps"].
	LOCAL largestMoves IS options["largestMoves"].
	LOCAL smallMoves IS options["smallMoves"].
	LOCAL plannedIterations IS 5.
	IF options:HASKEY("iterations") SET plannedIterations TO options["iterations"].
	LOCAL extendUntil IS TIME:SECONDS + 1E9.
	IF options:HASKEY("extendUntil") SET extendUntil TO options["extendUntil"].
	LOCAL costTolerance IS 1E4.
	IF options:HASKEY("costTolerance") SET costTolerance TO options["costTolerance"].
	LOCAL residualDelegate IS model["residual"].
	LOCAL abortDelegate IS neverAbort@.											// the model's "abort" delegate stops the fit at once (see simulateTrajectory)
	IF model:HASKEY("abort") SET abortDelegate TO model["abort"].

	LOCAL current IS startParameters:COPY.
	LOCAL currentResidual IS residualDelegate:CALL(model, current).
	LOCAL residualCount IS currentResidual:LENGTH.
	LOCAL currentCost IS residualCost(currentResidual).
	LOCAL startCost IS currentCost.
	LOCAL evaluations IS 1.
	LOCAL damping IS 0.0001.
	LOCAL jacobian IS LIST().													// for each parameter, a list of the slopes of the residual numbers
	LOCAL jacobianCurrent IS FALSE.
	LOCAL converged IS currentCost < costTolerance.
	LOCAL extended IS FALSE.
	LOCAL iteration IS 0.

	UNTIL converged OR iteration >= 2 * plannedIterations {
		IF abortDelegate:CALL() BREAK.
		IF iteration >= plannedIterations {
			IF TIME:SECONDS >= extendUntil BREAK.
			SET extended TO TRUE.
		}
		SET iteration TO iteration + 1.

		IF NOT jacobianCurrent {
			SET jacobian TO LIST().
			FROM {LOCAL parameterIndex IS 0.} UNTIL parameterIndex >= parameterCount STEP {SET parameterIndex TO parameterIndex + 1.} DO {
				LOCAL probe IS current:COPY.
				SET probe[parameterIndex] TO probe[parameterIndex] + probeSteps[parameterIndex].
				LOCAL probeResidual IS residualDelegate:CALL(model, probe).
				SET evaluations TO evaluations + 1.
				LOCAL slopes IS LIST().
				FROM {LOCAL row IS 0.} UNTIL row >= residualCount STEP {SET row TO row + 1.} DO {
					slopes:ADD((probeResidual[row] - currentResidual[row]) / probeSteps[parameterIndex]).
				}
				jacobian:ADD(slopes).
			}
			SET jacobianCurrent TO TRUE.
			IF abortDelegate:CALL() BREAK.										// an aborted simulation gives slopes that mean nothing
		}

		// the normal equations, with the damping added to the diagonal (a parameter with no effect must not make them singular)
		LOCAL normalMatrix IS LIST().
		LOCAL normalVector IS LIST().
		FROM {LOCAL firstIndex IS 0.} UNTIL firstIndex >= parameterCount STEP {SET firstIndex TO firstIndex + 1.} DO {
			LOCAL matrixRow IS LIST().
			FROM {LOCAL secondIndex IS 0.} UNTIL secondIndex >= parameterCount STEP {SET secondIndex TO secondIndex + 1.} DO {
				LOCAL product IS 0.
				FROM {LOCAL row IS 0.} UNTIL row >= residualCount STEP {SET row TO row + 1.} DO {
					SET product TO product + jacobian[firstIndex][row] * jacobian[secondIndex][row].
				}
				matrixRow:ADD(product).
			}
			normalMatrix:ADD(matrixRow).
			LOCAL slope IS 0.
			FROM {LOCAL row IS 0.} UNTIL row >= residualCount STEP {SET row TO row + 1.} DO {
				SET slope TO slope + jacobian[firstIndex][row] * currentResidual[row].
			}
			normalVector:ADD(-slope).
		}
		LOCAL largestDiagonal IS 0.
		FROM {LOCAL diagonalIndex IS 0.} UNTIL diagonalIndex >= parameterCount STEP {SET diagonalIndex TO diagonalIndex + 1.} DO {
			SET largestDiagonal TO MAX(largestDiagonal, normalMatrix[diagonalIndex][diagonalIndex]).
		}
		FROM {LOCAL diagonalIndex IS 0.} UNTIL diagonalIndex >= parameterCount STEP {SET diagonalIndex TO diagonalIndex + 1.} DO {
			LOCAL diagonalRow IS normalMatrix[diagonalIndex].
			SET diagonalRow[diagonalIndex] TO diagonalRow[diagonalIndex] * (1 + damping) + 1E-9 * largestDiagonal.
		}
		LOCAL move IS solveLinearSystem(normalMatrix, normalVector).

		// the move, cut down if it is too big
		LOCAL moveScale IS 1.
		FROM {LOCAL parameterIndex IS 0.} UNTIL parameterIndex >= parameterCount STEP {SET parameterIndex TO parameterIndex + 1.} DO {
			IF ABS(move[parameterIndex]) > largestMoves[parameterIndex] SET moveScale TO MIN(moveScale, largestMoves[parameterIndex] / ABS(move[parameterIndex])).
		}
		LOCAL trial IS LIST().
		LOCAL small IS TRUE.
		FROM {LOCAL parameterIndex IS 0.} UNTIL parameterIndex >= parameterCount STEP {SET parameterIndex TO parameterIndex + 1.} DO {
			trial:ADD(current[parameterIndex] + move[parameterIndex] * moveScale).
			IF ABS(move[parameterIndex] * moveScale) >= smallMoves[parameterIndex] SET small TO FALSE.
		}
		LOCAL trialResidual IS residualDelegate:CALL(model, trial).
		SET evaluations TO evaluations + 1.
		LOCAL trialCost IS residualCost(trialResidual).

		IF trialCost < currentCost {
			SET current TO trial.
			SET currentResidual TO trialResidual.
			SET currentCost TO trialCost.
			SET jacobianCurrent TO FALSE.
			SET damping TO MAX(damping / 3, 1E-6).
			IF small OR currentCost < costTolerance SET converged TO TRUE.
		} ELSE {
			// no better: more damping and the same slopes, unless the move was already negligible
			SET damping TO damping * 10.
			IF small OR damping > 1E7 SET converged TO TRUE.
		}
	}

	RETURN LEXICON("parameters", current, "miss", SQRT(currentCost), "startMiss", SQRT(startCost), "converged", converged,
					"iterations", iteration, "extended", extended, "evaluations", evaluations, "seconds", KUNIVERSE:REALTIME - startReal).
}

// Finds the ignition shift and the two tilts that put the simulated node burn on the predicted orbit (fitTrajectory on the node burn
// model). It starts from the shift that the flown burns suggest and no tilt. It has converged when a move is smaller than 0.05 s
// and 0.03 degrees, or the miss is below costTolerance.
// If it has not converged after the planned iterations and there are still spareTime seconds before the ignition, it carries on
// for up to as many iterations again, checking before each one. Whatever happens, it returns the best parameters found.
// Passed the following
//			spec (lexicon, from burnSolveSpec)
//			ignitionUT (scalar, UT in s, when the burn is scheduled to start; the default is never)
//			iterations (scalar, the planned number of iterations)
//			spareTime (scalar, s, that must be left before the ignition for the extra iterations)
//			costTolerance (scalar, the miss squared (m^2) below which the fit is good enough)
// Returns a lexicon of "shift" (s), "tilt" and "tilt2" (rad), "miss" (m, the position error left plus 1000 times the velocity
//		error), "startMiss" (m, with the starting guess), "converged" (boolean), "iterations" (the number done), "extended"
//		(boolean, whether it went past the planned iterations), "evaluations" (simulations), "seconds" (real time that it took)
//		and "burn" (the simulated burn with those parameters, see simulateBurn)
FUNCTION solveBurnCorrection {
	PARAMETER spec.
	PARAMETER ignitionUT IS TIME:SECONDS + 1E9.
	PARAMETER iterations IS 5.
	PARAMETER spareTime IS 120.
	PARAMETER costTolerance IS 1E4.

	LOCAL fit IS fitTrajectory(spec, LIST(spec["shiftGuess"], 0, 0),
								LEXICON("probeSteps", LIST(0.2, 0.002, 0.002),						// s, rad, rad
										"largestMoves", LIST(5, 0.05, 0.05),
										"smallMoves", LIST(0.05, 0.0005, 0.0005),
										"iterations", iterations,
										"extendUntil", ignitionUT - spareTime,
										"costTolerance", costTolerance)).
	LOCAL solved IS fit["parameters"].
	RETURN LEXICON("shift", solved[0], "tilt", solved[1], "tilt2", solved[2], "miss", fit["miss"], "startMiss", fit["startMiss"],
					"converged", fit["converged"], "iterations", fit["iterations"], "extended", fit["extended"],
					"evaluations", fit["evaluations"], "seconds", fit["seconds"], "burn", simulateBurn(spec, solved[0], solved[1], solved[2])).
}

// ============================================================================
// Optimizers (moved from library.ks): hill climbing, gradient descent and minimum finders
// ============================================================================

// Generic hill climbing function
// Tries to minimize the value of the passed delegate.
// Passed the following
//			delegate, expecting a single scalar input and returns a single scalar
//			initialGuess - initial guess of the final value
//			initialStepSize - how much to start moving the initial guess by
//			logFileName - log file name. If blank, does not log. Defaults to blank.
//			iterationMax - maximum iteration number. Defaults to 100.
//			smallestStepRatio - Ratio of smallest step size to initial step size
//        (negative power of 2). Defaults to 15, so the smallest step size
//        would be initialStepSize / (2^15).
//			cyclicalPeriod - period of cyclical repition in the input of the delegate.
//        -1 is a special case that indicates input is not cyclical.
//        Defaults to -1.
//			cyclicalPeriodCutoff - value below which cyclicalPeriod should be added to the current guess.
//			deleteOldlogFileName - whether to delete the old version of the log file
//				or append to the end of the file.
// Returns the following:
//			Lexicon with the following members:
//				"iteration" - scalar - number of the final iteration
//				"initialValue" - scalar - value of the delegate given the initial guess
//				"initialGuess" - scalar - value of the initial guess
//				"finalValue" - scalar - value of the delegate given the final guess. This is minimized.
//				"finalGuess" - scalar - value of the final guess
//				"deltaValue" - scalar - how much the delegate changed
// A few notes about the delegate:
//    It is assumed that the delegate recieves a single scalar input and returns a single scalar.
//    This function is a minimization function; if you want it to maximimze instead, make the delegate return a negative.
FUNCTION hillClimb {
	PARAMETER delegate.
	PARAMETER initialGuess.
	PARAMETER initialStepSize.
	PARAMETER logFileName IS "".
	PARAMETER iterationMax IS 100.
	PARAMETER smallestStepRatio IS 15.
	PARAMETER cyclicalPeriod IS -1.
	PARAMETER cyclicalPeriodCutoff IS 0.
	PARAMETER deleteOldlogFileName IS TRUE.
	
	IF initialStepSize = 0 OR delegate:TYPENAME <> "UserDelegate" {
		RETURN LEXICON("iteration", -1,
										  "initialValue", delegate(initialGuess),
										  "initialGuess", initialGuess,
										  "finalValue", delegate(initialGuess),
										  "finalGuess", initialGuess,
										  "deltaValue", 0).
	}

	LOCAL logDataPerm IS (logFileName <> "").
	IF logFileName:STARTSWITH("0:") AND NOT connectionToKSC() SET logDataPerm TO FALSE.
	LOCAL stepSize IS initialStepSize.
	LOCAL smallestStep IS initialStepSize / (2^smallestStepRatio).
	LOCAL iteration IS 0.
	LOCAL currentDelegate IS 0.
	LOCAL currentPlusDelegate IS 0.
	LOCAL currentMinusDelegate IS 0.
	IF deleteOldlogFileName AND logDataPerm AND EXISTS(logFileName) DELETEPATH(logFileName).
	IF logDataPerm LOG "Iteration,Power of 2,Current Guess,Step Size,Delegate at Current Guess,Delegate at Current Guess + Step,Delegate at Current Guess - Step" TO logFileName.
	LOCAL currentGuess IS initialGuess.
	LOCAL currentDelegate IS delegate(currentGuess).
	LOCAL knownInitialValue IS currentDelegate.

	UNTIL (stepSize <= smallestStep) OR (iteration > iterationMax) {
		SET currentPlusDelegate TO delegate(currentGuess + stepSize).
		SET currentMinusDelegate TO delegate(currentGuess - stepSize).

		IF logDataPerm LOG iteration + "," + (LN(stepSize/initialStepSize)/LN(2)) + "," + currentGuess + "," + stepSize + "," + currentDelegate + "," + currentPlusDelegate + "," + currentMinusDelegate TO logFileName.

		IF currentPlusDelegate < currentDelegate {
			SET currentGuess TO currentGuess + stepSize.
			SET currentDelegate TO currentPlusDelegate.
		} ELSE IF currentMinusDelegate < currentDelegate {
			SET currentGuess TO currentGuess - stepSize.
			SET currentDelegate TO currentMinusDelegate.
		} ELSE {
			SET stepSize TO stepSize / 2.
		}
		SET iteration TO iteration + 1.
		IF cyclicalPeriod <> -1 {
			SET currentGuess TO MOD(currentGuess - cyclicalPeriodCutoff, cyclicalPeriod) + cyclicalPeriodCutoff.
			IF currentGuess < cyclicalPeriodCutoff SET currentGuess TO currentGuess + cyclicalPeriod.
		}
	}
	LOCAL initialValue IS knownInitialValue.
	LOCAL finalValue IS currentDelegate.
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("iteration", iteration - 1).
	returnMe:ADD("initialValue", initialValue).
	returnMe:ADD("initialGuess", initialGuess).
	returnMe:ADD("finalValue", finalValue).
	returnMe:ADD("finalGuess", currentGuess).
	returnMe:ADD("deltaValue", finalValue - initialValue).
	RETURN returnMe.
}

// 2D hill climb: minimizes delegate(guess1, guess2) by moving to the best of the 8 neighbours of the
// current guess, halving the step when none improves. A point already priced at the current step size is
// not priced again.
//   delegate - two scalar inputs, one scalar output (return a negative to maximize)
//   initialGuess1/2, initialStepSize1/2 - the starting point and step on each axis
//   logFileName - log file ("" for none)
//   iterationMax - defaults to 100
//   smallestStepRatio - the smallest step is initialStepSize / 2^smallestStepRatio (default 15)
//   cyclicalPeriod1/2, cyclicalPeriodCutoff1/2 - wrap an axis into [cutoff, cutoff + period); -1 for not cyclical
//   deleteOldlogFileName - delete the old log file, or append to it
// Returns a LEXICON: "iteration", "initialValue", "initialGuess1", "initialGuess2", "finalValue",
// "finalGuess1", "finalGuess2", "deltaValue".
FUNCTION hillClimb2D {
	PARAMETER delegate.
	PARAMETER initialGuess1.
	PARAMETER initialGuess2.
	PARAMETER initialStepSize1.
	PARAMETER initialStepSize2.
	PARAMETER logFileName IS "".
	PARAMETER iterationMax IS 100.
	PARAMETER smallestStepRatio IS 15.
	PARAMETER cyclicalPeriod1 IS -1.
	PARAMETER cyclicalPeriodCutoff1 IS 0.
	PARAMETER cyclicalPeriod2 IS -1.
	PARAMETER cyclicalPeriodCutoff2 IS 0.
	PARAMETER deleteOldlogFileName IS TRUE.

	LOCAL logDataPerm IS (logFileName <> "").
	IF logFileName:STARTSWITH("0:") AND NOT connectionToKSC() SET logDataPerm TO FALSE.

	// guard against a zero step size on either axis, which would otherwise
	// make the smallest-step floor zero and exit the loop before it starts.
	IF initialStepSize1 = 0 SET initialStepSize1 TO 0.001.
	IF initialStepSize2 = 0 SET initialStepSize2 TO 0.001.

	LOCAL stepSize1 IS initialStepSize1.
	LOCAL stepSize2 IS initialStepSize2.
	LOCAL smallestStep1 IS initialStepSize1 / (2^smallestStepRatio).
	LOCAL smallestStep2 IS initialStepSize2 / (2^smallestStepRatio).
	LOCAL iteration IS 0.

	IF deleteOldlogFileName AND logDataPerm AND EXISTS(logFileName) DELETEPATH(logFileName).
	IF logDataPerm LOG "Iteration,Guess1,Guess2,Step1,Step2,Current Delegate,Neighbor,Neighbor Delegate,Moved" TO logFileName.

	LOCAL currentGuess1 IS initialGuess1.
	LOCAL currentGuess2 IS initialGuess2.
	LOCAL currentDelegate IS delegate(currentGuess1, currentGuess2).
	LOCAL initialValue IS currentDelegate.

	// 3x3 grid of (offset1, offset2) labels, skipping the center (0,0).
	// Ordered N, NE, E, SE, S, SW, W, NW purely for readable logs.
	LOCAL neighborLabels IS LIST("N", "NE", "E", "SE", "S", "SW", "W", "NW").
	// The same neighbours in steps (-1, 0 or 1) on each axis, and the values already priced at this step size,
	// keyed by position in steps from where the step size last changed (index1, index2).
	LOCAL neighborSteps IS LIST(LIST(0, 1), LIST(1, 1), LIST(1, 0), LIST(1, -1), LIST(0, -1), LIST(-1, -1), LIST(-1, 0), LIST(-1, 1)).
	LOCAL priced IS LEXICON("0,0", currentDelegate).
	LOCAL index1 IS 0.
	LOCAL index2 IS 0.

	UNTIL ((stepSize1 <= smallestStep1) AND (stepSize2 <= smallestStep2)) OR (iteration > iterationMax) {
		LOCAL neighborOffsets IS LIST(
			LIST(       0,  stepSize2), 	// N
			LIST( stepSize1,  stepSize2),	// NE
			LIST( stepSize1,        0),		// E
			LIST( stepSize1, -stepSize2),	// SE
			LIST(       0, -stepSize2),		// S
			LIST(-stepSize1, -stepSize2),	// SW
			LIST(-stepSize1,        0),		// W
			LIST(-stepSize1,  stepSize2)	// NW
		).

		LOCAL bestValue IS currentDelegate.
		LOCAL bestGuess1 IS currentGuess1.
		LOCAL bestGuess2 IS currentGuess2.
		LOCAL bestLabel IS "None".
		LOCAL bestNeighbor IS 0.
		LOCAL neighborValue IS 0.
		LOCAL testGuess1 IS 0.
		LOCAL testGuess2 IS 0.

		FOR neighborIndex IN RANGE(0, neighborOffsets:LENGTH) {
			SET testGuess1 TO currentGuess1 + neighborOffsets[neighborIndex][0].
			SET testGuess2 TO currentGuess2 + neighborOffsets[neighborIndex][1].
			LOCAL pricedKey IS (index1 + neighborSteps[neighborIndex][0]) + "," + (index2 + neighborSteps[neighborIndex][1]).
			IF priced:HASKEY(pricedKey) {
				SET neighborValue TO priced[pricedKey].
			} ELSE {
				SET neighborValue TO delegate(testGuess1, testGuess2).
				SET priced[pricedKey] TO neighborValue.
				// This is present because kOS has odd results when complex calculations are spread across different physics ticks.
				WAIT 0.
			}

			IF logDataPerm LOG iteration + "," + testGuess1 + "," + testGuess2 + "," + stepSize1 + "," + stepSize2 + "," + currentDelegate + "," + neighborLabels[neighborIndex] + "," + neighborValue + "," + (neighborValue < bestValue) TO logFileName.

			IF neighborValue < bestValue {
				SET bestValue TO neighborValue.
				SET bestGuess1 TO testGuess1.
				SET bestGuess2 TO testGuess2.
				SET bestLabel TO neighborLabels[neighborIndex].
				SET bestNeighbor TO neighborIndex.
			}
		}

		IF bestLabel = "None" {
			// no neighbor improved on the current point; shrink whichever
			// axis step size(s) haven't hit their floor yet, and try again.
			IF stepSize1 > smallestStep1 SET stepSize1 TO stepSize1 / 2.
			IF stepSize2 > smallestStep2 SET stepSize2 TO stepSize2 / 2.
			// Nothing priced so far is a neighbour at the new step size.
			priced:CLEAR().
			SET index1 TO 0.
			SET index2 TO 0.
			SET priced["0,0"] TO currentDelegate.
		} ELSE {
			SET currentGuess1 TO bestGuess1.
			SET currentGuess2 TO bestGuess2.
			SET currentDelegate TO bestValue.
			SET index1 TO index1 + neighborSteps[bestNeighbor][0].
			SET index2 TO index2 + neighborSteps[bestNeighbor][1].
		}

		// symmetric cyclical wraparound, applied independently per axis
		IF cyclicalPeriod1 <> -1 {
			SET currentGuess1 TO MOD(currentGuess1 - cyclicalPeriodCutoff1, cyclicalPeriod1).
			IF currentGuess1 < 0 SET currentGuess1 TO currentGuess1 + cyclicalPeriod1.
			SET currentGuess1 TO currentGuess1 + cyclicalPeriodCutoff1.
		}
		IF cyclicalPeriod2 <> -1 {
			SET currentGuess2 TO MOD(currentGuess2 - cyclicalPeriodCutoff2, cyclicalPeriod2).
			IF currentGuess2 < 0 SET currentGuess2 TO currentGuess2 + cyclicalPeriod2.
			SET currentGuess2 TO currentGuess2 + cyclicalPeriodCutoff2.
		}
		// A wrapped guess is no longer where its index says, so start the priced points again.
		IF cyclicalPeriod1 <> -1 OR cyclicalPeriod2 <> -1 {
			priced:CLEAR().
			SET index1 TO 0.
			SET index2 TO 0.
			SET priced["0,0"] TO currentDelegate.
		}

		SET iteration TO iteration + 1.
	}

	LOCAL returnMe IS LEXICON().
	returnMe:ADD("iteration", iteration).
	returnMe:ADD("initialValue", initialValue).
	returnMe:ADD("initialGuess1", initialGuess1).
	returnMe:ADD("initialGuess2", initialGuess2).
	returnMe:ADD("finalValue", currentDelegate).
	returnMe:ADD("finalGuess1", currentGuess1).
	returnMe:ADD("finalGuess2", currentGuess2).
	returnMe:ADD("deltaValue", currentDelegate - initialValue).
	RETURN returnMe.
}

// ============================================================================
// Gradient ascent / descent for a 2-input scalar delegate.
//
// This is intentionally written to sit alongside hillClimb2D in librarySolvers.ks and
// share its calling convention (a 2-argument delegate, a LEXICON result with
// the same key names) so the two can be swapped for one another easily.
//
// See the accompanying explanation for how this differs from hillClimb2D:
// hillClimb2D is a derivative-free "compass search" (it only ever asks
// "is this neighbor better or worse?" at 8 fixed points a fixed step away),
// while gradientDescent2D estimates the actual slope of the delegate via
// finite differences and moves continuously along it, with a step size that
// naturally shrinks as the slope flattens out near an optimum.
// ============================================================================

// Estimates the partial derivatives of a 2-argument delegate at (guess1, guess2)
// using a central finite difference: (f(x+h) - f(x-h)) / (2h). Central
// differences are used instead of forward differences (f(x+h) - f(x)) / h)
// because they're second-order accurate rather than first-order - i.e. the
// error shrinks with h^2 instead of just h, which matters a lot here since
// gradientStepSize (h) also has to be small enough not to blur out real
// curvature in the delegate's surface.
// Passed the following:
//			delegate, expecting two scalar inputs and returning a single scalar
//			guess1, guess2 - the point to estimate the gradient at
//			gradientStepSize - h, the finite-difference offset
// Returns a LEXICON with "d1" (partial derivative w.r.t. input 1) and
// "d2" (partial derivative w.r.t. input 2).
FUNCTION estimateGradient2D {
	PARAMETER delegate.
	PARAMETER guess1.
	PARAMETER guess2.
	PARAMETER gradientStepSize.

	LOCAL d1 IS (delegate(guess1 + gradientStepSize, guess2) - delegate(guess1 - gradientStepSize, guess2)) / (2 * gradientStepSize).
	LOCAL d2 IS (delegate(guess1, guess2 + gradientStepSize) - delegate(guess1, guess2 - gradientStepSize)) / (2 * gradientStepSize).

	RETURN LEXICON("d1", d1, "d2", d2).
}

// Generic 2D gradient ascent / descent function.
// Minimizes (or maximizes, if ascend is TRUE) the value of the passed delegate,
// which takes two scalar inputs and returns a single scalar, by repeatedly
// estimating the local gradient and stepping along it (downhill to minimize,
// uphill to maximize), scaled by learningRate.
//
// Includes simple backtracking: if a proposed step does not actually improve
// the delegate's value (which can happen if learningRate is too large for the
// local curvature - the classic gradient descent failure mode is overshooting
// past a minimum), learningRate is halved and the same gradient is retried,
// rather than taking the bad step. This is a much cheaper stand-in for a full
// line search, and is the direct analog of hillClimb2D halving its step size
// when no neighbor improves on the current point.
//
// Passed the following:
//			delegate - expects two scalar inputs, returns a single scalar
//			initialGuess1, initialGuess2 - starting point
//			initialLearningRate - initial multiplier applied to the gradient
//        each step (this is the "step size" of gradient descent - unlike
//        hillClimb2D's fixed compass-direction step, the actual distance
//        moved is learningRate * |gradient|, so it shrinks on its own as
//        the surface flattens out near an optimum)
//			gradientStepSize - h used for the finite-difference gradient estimate.
//        Defaults to a small fraction of the learning rate; pass this
//        explicitly if the delegate's inputs are on a very different scale
//        than its output.
//			gradientTolerance - stop once the gradient's magnitude drops below
//        this value (i.e. the surface is locally ~flat - an optimum).
//        Defaults to a small number; tune to the scale of the delegate.
//			iterationMax - maximum number of accepted steps. Defaults to 100.
//			maxBacktracks - maximum number of learningRate halvings to try in a
//        single iteration before giving up and treating the search as
//        converged (learningRate has become negligible). Defaults to 30.
//			ascend - IF TRUE, maximizes the delegate instead of minimizing it.
//        Defaults to FALSE (minimize), matching hillClimb2D's convention.
//			logFileName - log file name. If blank, does not log. Defaults to blank.
//			cyclicalPeriod1 / cyclicalPeriodCutoff1 - as in hillClimb2D: if axis 1
//        wraps around (e.g. an angle or an orbital phase), pass the period
//        here so the guess gets wrapped back into range each iteration.
//        -1 means "not cyclical". Defaults to -1.
//			cyclicalPeriod2 / cyclicalPeriodCutoff2 - as above, for axis 2.
//			deleteOldlogFileName - whether to delete the old version of the log
//        file or append to the end of it. Defaults to TRUE.
// Returns the following:
//			Lexicon with the following members (same shape as hillClimb2D's return,
//      so the two are interchangeable at the call site):
//				"iteration" - scalar - number of accepted steps taken
//				"initialValue" - scalar - delegate's value at the initial guess
//				"initialGuess1" / "initialGuess2" - the starting point
//				"finalValue" - scalar - delegate's value at the final guess
//				"finalGuess1" / "finalGuess2" - the final point
//				"deltaValue" - scalar - how much the delegate's value changed
//				"finalGradientMagnitude" - scalar - |gradient| at the final guess;
//        useful for confirming whether the search actually converged
//        (small) or bailed out on exhausted backtracks (still large)
FUNCTION gradientDescent2D {
	PARAMETER delegate.
	PARAMETER initialGuess1.
	PARAMETER initialGuess2.
	PARAMETER initialLearningRate.
	PARAMETER gradientStepSize IS initialLearningRate / 100.
	PARAMETER gradientTolerance IS 1e-6.
	PARAMETER iterationMax IS 100.
	PARAMETER maxBacktracks IS 30.
	PARAMETER ascend IS FALSE.
	PARAMETER logFileName IS "".
	PARAMETER cyclicalPeriod1 IS -1.
	PARAMETER cyclicalPeriodCutoff1 IS 0.
	PARAMETER cyclicalPeriod2 IS -1.
	PARAMETER cyclicalPeriodCutoff2 IS 0.
	PARAMETER deleteOldlogFileName IS TRUE.

	IF (initialLearningRate = 0) OR (NOT delegate:ISTYPE("UserDelegate")) {
		LOCAL fallbackValue IS delegate(initialGuess1, initialGuess2).
		RETURN LEXICON("iteration", -1,
									  "initialValue", fallbackValue,
									  "initialGuess1", initialGuess1,
									  "initialGuess2", initialGuess2,
									  "finalValue", fallbackValue,
									  "finalGuess1", initialGuess1,
									  "finalGuess2", initialGuess2,
									  "deltaValue", 0,
									  "finalGradientMagnitude", 0).
	}

	LOCAL logDataPerm IS (logFileName <> "").
	IF logFileName:STARTSWITH("0:") AND NOT connectionToKSC() SET logDataPerm TO FALSE.
	IF deleteOldlogFileName AND logDataPerm AND EXISTS(logFileName) DELETEPATH(logFileName).
	IF logDataPerm LOG "Iteration,Guess1,Guess2,Value,Gradient1,Gradient2,GradientMag,LearningRate,Backtracks" TO logFileName.

	// ascending and descending are the same algorithm with the sign of the step
	// flipped - climb the gradient uphill instead of stepping downhill against it.
	LOCAL directionSign IS 1.
	IF ascend SET directionSign TO -1.

	LOCAL currentGuess1 IS initialGuess1.
	LOCAL currentGuess2 IS initialGuess2.
	LOCAL currentValue IS delegate(currentGuess1, currentGuess2).
	LOCAL knownInitialValue IS currentValue.
	LOCAL learningRate IS initialLearningRate.

	LOCAL iteration IS 0.
	LOCAL gradientMagnitude IS gradientTolerance + 1. // anything > tolerance, just to enter the loop

	UNTIL (gradientMagnitude <= gradientTolerance) OR (iteration >= iterationMax) {
		LOCAL gradient IS estimateGradient2D(delegate, currentGuess1, currentGuess2, gradientStepSize).
		SET gradientMagnitude TO SQRT(gradient["d1"]^2 + gradient["d2"]^2).

		IF gradientMagnitude <= gradientTolerance {
			IF logDataPerm LOG iteration + "," + currentGuess1 + "," + currentGuess2 + "," + currentValue + "," +
				gradient["d1"] + "," + gradient["d2"] + "," + gradientMagnitude + "," + learningRate + ",converged" TO logFileName.
			BREAK.
		}

		// backtracking: try the full learning rate first, halving it until the
		// step actually improves on currentValue (or we give up on this iteration)
		LOCAL backtracks IS 0.
		LOCAL stepAccepted IS FALSE.
		LOCAL testGuess1 IS currentGuess1.
		LOCAL testGuess2 IS currentGuess2.
		LOCAL testValue IS currentValue.

		UNTIL stepAccepted OR (backtracks >= maxBacktracks) {
			SET testGuess1 TO currentGuess1 - directionSign * learningRate * gradient["d1"].
			SET testGuess2 TO currentGuess2 - directionSign * learningRate * gradient["d2"].
			SET testValue TO delegate(testGuess1, testGuess2).

			LOCAL improved IS FALSE.
			IF ascend SET improved TO (testValue > currentValue).
			ELSE SET improved TO (testValue < currentValue).

			IF improved {
				SET stepAccepted TO TRUE.
			} ELSE {
				SET learningRate TO learningRate / 2.
				SET backtracks TO backtracks + 1.
			}
		}

		IF logDataPerm LOG iteration + "," + currentGuess1 + "," + currentGuess2 + "," + currentValue + "," +
			gradient["d1"] + "," + gradient["d2"] + "," + gradientMagnitude + "," + learningRate + "," + backtracks TO logFileName.

		IF NOT stepAccepted {
			// learningRate has been halved maxBacktracks times and still can't find
			// an improving step - the gradient estimate is unreliable this close in
			// (often floating-point noise at the scale of gradientStepSize), so stop.
			BREAK.
		}

		SET currentGuess1 TO testGuess1.
		SET currentGuess2 TO testGuess2.
		SET currentValue TO testValue.

		IF cyclicalPeriod1 <> -1 {
			SET currentGuess1 TO MOD(currentGuess1 - cyclicalPeriodCutoff1, cyclicalPeriod1) + cyclicalPeriodCutoff1.
			IF currentGuess1 < cyclicalPeriodCutoff1 SET currentGuess1 TO currentGuess1 + cyclicalPeriod1.
		}
		IF cyclicalPeriod2 <> -1 {
			SET currentGuess2 TO MOD(currentGuess2 - cyclicalPeriodCutoff2, cyclicalPeriod2) + cyclicalPeriodCutoff2.
			IF currentGuess2 < cyclicalPeriodCutoff2 SET currentGuess2 TO currentGuess2 + cyclicalPeriod2.
		}

		SET iteration TO iteration + 1.
	}

	LOCAL returnMe IS LEXICON().
	returnMe:ADD("iteration", iteration).
	returnMe:ADD("initialValue", knownInitialValue).
	returnMe:ADD("initialGuess1", initialGuess1).
	returnMe:ADD("initialGuess2", initialGuess2).
	returnMe:ADD("finalValue", currentValue).
	returnMe:ADD("finalGuess1", currentGuess1).
	returnMe:ADD("finalGuess2", currentGuess2).
	returnMe:ADD("deltaValue", currentValue - knownInitialValue).
	returnMe:ADD("finalGradientMagnitude", gradientMagnitude).
	RETURN returnMe.
}

// Golden-section search for the minimum of costDelegate(x) on [lowBound, highBound].
// Returns the x of the minimum. Derivative-free; assumes the cost is unimodal
// there, which holds for the narrow brackets this file uses.
FUNCTION goldenSectionMinimum {
	PARAMETER costDelegate.
	PARAMETER lowBound.
	PARAMETER highBound.
	PARAMETER iterations IS 14.

	LOCAL inversePhi IS (SQRT(5) - 1) / 2.
	LOCAL low IS lowBound.
	LOCAL high IS highBound.
	LOCAL probeLow IS high - inversePhi * (high - low).
	LOCAL probeHigh IS low + inversePhi * (high - low).
	LOCAL costLow IS costDelegate(probeLow).
	LOCAL costHigh IS costDelegate(probeHigh).

	FROM {LOCAL pass IS 0.} UNTIL pass >= iterations STEP {SET pass TO pass + 1.} DO {
		IF costLow < costHigh {
			SET high TO probeHigh.
			SET probeHigh TO probeLow.
			SET costHigh TO costLow.
			SET probeLow TO high - inversePhi * (high - low).
			SET costLow TO costDelegate(probeLow).
		} ELSE {
			SET low TO probeLow.
			SET probeLow TO probeHigh.
			SET costLow TO costHigh.
			SET probeHigh TO low + inversePhi * (high - low).
			SET costHigh TO costDelegate(probeHigh).
		}
	}
	RETURN (low + high) / 2.
}

// Newton refinement of a minimum in two variables, to finish a hill climb. Each step prices a 3x3 patch
// around the current point (8 new points), fits slope and curvature, and moves to the bottom of the fitted
// bowl (capped at two patch widths) if that beats every point priced; otherwise to the best patch point.
// Each later step halves the patch.
//   costDelegate - f(guess1, guess2) -> value, to be minimized
//   startGuess1/2, startValue - the point to refine and its value
//   startStep1/2 - the patch half-width on each axis for the first step
//   newtonSteps  - how many steps to take
// Returns a LEXICON: "finalValue", "finalGuess1", "finalGuess2", "evaluations" and "steps" (steps that
// moved to a better point).
FUNCTION newtonRefine2D {
	PARAMETER costDelegate.
	PARAMETER startGuess1.
	PARAMETER startGuess2.
	PARAMETER startValue.
	PARAMETER startStep1.
	PARAMETER startStep2.
	PARAMETER newtonSteps IS 2.

	LOCAL guess1 IS startGuess1.
	LOCAL guess2 IS startGuess2.
	LOCAL currentValue IS startValue.
	LOCAL step1 IS startStep1.
	LOCAL step2 IS startStep2.
	LOCAL evaluations IS 0.
	LOCAL stepsTaken IS 0.

	FROM {LOCAL newtonStep IS 1.} UNTIL newtonStep > newtonSteps STEP {SET newtonStep TO newtonStep + 1.} DO {
		// The 3x3 patch, stored flat: position 3*i + j is the point at (guess1 + (i-1)*step1, guess2 + (j-1)*step2).
		LOCAL patch IS LIST(0, 0, 0, 0, currentValue, 0, 0, 0, 0).
		LOCAL bestPatchValue IS currentValue.
		LOCAL bestPatch1 IS guess1.
		LOCAL bestPatch2 IS guess2.
		FOR patchIndex IN LIST(0, 1, 2, 3, 5, 6, 7, 8) {
			LOCAL point1 IS guess1 + (FLOOR(patchIndex / 3) - 1) * step1.
			LOCAL point2 IS guess2 + (MOD(patchIndex, 3) - 1) * step2.
			LOCAL pointValue IS costDelegate(point1, point2).
			SET evaluations TO evaluations + 1.
			SET patch[patchIndex] TO pointValue.
			IF pointValue < bestPatchValue {
				SET bestPatchValue TO pointValue.
				SET bestPatch1 TO point1.
				SET bestPatch2 TO point2.
			}
			WAIT 0.
		}

		LOCAL slope1 IS (patch[7] - patch[1]) / (2 * step1).
		LOCAL slope2 IS (patch[5] - patch[3]) / (2 * step2).
		LOCAL curvature11 IS (patch[7] - 2 * patch[4] + patch[1]) / step1 ^ 2.
		LOCAL curvature22 IS (patch[5] - 2 * patch[4] + patch[3]) / step2 ^ 2.
		LOCAL curvature12 IS (patch[8] - patch[6] - patch[2] + patch[0]) / (4 * step1 * step2).
		LOCAL determinant IS curvature11 * curvature22 - curvature12 ^ 2.

		// Where this step ends up: the best patch point, unless the fitted bowl's bottom does better.
		LOCAL nextValue IS bestPatchValue.
		LOCAL next1 IS bestPatch1.
		LOCAL next2 IS bestPatch2.
		IF curvature11 > 0 AND determinant > 0 {
			LOCAL move1 IS -(curvature22 * slope1 - curvature12 * slope2) / determinant.
			LOCAL move2 IS -(curvature11 * slope2 - curvature12 * slope1) / determinant.
			LOCAL overshoot IS MAX(ABS(move1) / (2 * step1), ABS(move2) / (2 * step2)).
			IF overshoot > 1 {
				SET move1 TO move1 / overshoot.
				SET move2 TO move2 / overshoot.
			}
			LOCAL bowlValue IS costDelegate(guess1 + move1, guess2 + move2).
			SET evaluations TO evaluations + 1.
			WAIT 0.
			IF bowlValue < nextValue {
				SET nextValue TO bowlValue.
				SET next1 TO guess1 + move1.
				SET next2 TO guess2 + move2.
			}
		}

		IF nextValue < currentValue {
			SET currentValue TO nextValue.
			SET guess1 TO next1.
			SET guess2 TO next2.
			SET stepsTaken TO stepsTaken + 1.
		}
		SET step1 TO step1 / 2.
		SET step2 TO step2 / 2.
	}

	RETURN LEXICON("finalValue", currentValue, "finalGuess1", guess1, "finalGuess2", guess2, "evaluations", evaluations, "steps", stepsTaken).
}

// ============================================================================
// Root finders and equation solvers (moved from library.ks)
// ============================================================================

// Using the Secant method, iterate until the function returns the chosen value
//   within tolerance, or the maximum iteration number is reached.
FUNCTION findZeroSecant {
  PARAMETER delegate.
  PARAMETER X1.
  PARAMETER X2.
  PARAMETER tolerance.
  PARAMETER iteration IS 0.

  IF ((iteration = 10) OR (delegate:TYPENAME <> "UserDelegate")) RETURN X1.

  LOCAL F1 IS delegate(X1).
  LOCAL F2 IS delegate(X2).
  IF F1 = F2 RETURN X1.
  LOCAL X3 IS 0.
  IF (F1 <> 0) OR (F2 <> 0) SET X3 TO (X2 * F1 - X1 * F2) / (F1 - F2).
  LOCAL F3 IS delegate(X3).

  IF ABS(F3) < tolerance RETURN X3.
  RETURN  findZeroSecant(delegate, X2, X3, tolerance, iteration + 1).
}

// Using the Newton method, iterate until the function returns the chosen value
//   within tolerance, or the maximum iteration number is reached.
FUNCTION findZeroNewton {
	PARAMETER delegateFunction.
	PARAMETER delegateSlope.
	PARAMETER initialGuess.
	PARAMETER tolerance.
	PARAMETER desiredValue IS 0.
	PARAMETER iteration IS 0.
	PARAMETER maxIteration IS 100.

	IF ((iteration >= maxIteration) OR (NOT delegateFunction:ISTYPE("UserDelegate")) OR (NOT delegateSlope:ISTYPE("UserDelegate"))) RETURN initialGuess.

	LOCAL slope IS delegateSlope(initialGuess).
	LOCAL X2 IS initialGuess.
	IF slope <> 0 SET X2 TO initialGuess - (delegateFunction(initialGuess) - desiredValue)/slope.
	IF ABS(delegateFunction(X2) - desiredValue) < tolerance RETURN X2.
	RETURN findZeroNewton(delegateFunction, delegateSlope, X2, tolerance, desiredValue, iteration + 1, maxIteration).
}

// Given a single-argument delegate f(x) and a starting guess, searches
// outward from the guess in both directions (doubling the step each attempt,
// clamped to [domainLow, domainHigh]) until it finds two x-values where f
// changes sign - suitable as a bracket for findZeroBrent.
FUNCTION bracketAroundGuess {
	PARAMETER residualDelegate.
	PARAMETER guess.
	PARAMETER domainLow.
	PARAMETER domainHigh.
	PARAMETER initialStep.
	PARAMETER maxDoublings IS 40.

	LOCAL clampedGuess IS MAX(domainLow, MIN(domainHigh, guess)).
	LOCAL guessResidual IS residualDelegate(clampedGuess).
	LOCAL step IS initialStep.
	LOCAL attempt IS 0.

	UNTIL attempt >= maxDoublings {
		LOCAL highCandidate IS MIN(clampedGuess + step, domainHigh).
		IF residualDelegate(highCandidate) * guessResidual <= 0 RETURN LEXICON("low", clampedGuess, "high", highCandidate).

		LOCAL lowCandidate IS MAX(clampedGuess - step, domainLow).
		IF residualDelegate(lowCandidate) * guessResidual <= 0 RETURN LEXICON("low", lowCandidate, "high", clampedGuess).

		IF (highCandidate = domainHigh) AND (lowCandidate = domainLow) BREAK.

		SET step TO step * 2.
		SET attempt TO attempt + 1.
	}

	// No bracket in the domain: return a degenerate one, which findZeroBrent handles.
	RETURN LEXICON("low", clampedGuess, "high", clampedGuess).
}

// Brent's method: a bracketed, derivative-free root finder (bisection with secant and inverse quadratic
// steps). X1 and X2 should bracket a root; if they do not, bracketAroundGuess looks for a bracket, up to
// recursionLevel times.
FUNCTION findZeroBrent {
	PARAMETER delegate.
	PARAMETER X1.
	PARAMETER X2.
	PARAMETER tolerance.
	PARAMETER maxIterations IS 100.
	PARAMETER recursionLevel IS 10.

	LOCAL a IS X1.
	LOCAL b IS X2.
	LOCAL fa IS delegate(a).
	LOCAL fb IS delegate(b).

	// If we have reached the limit of recursion, return whichever input
	// results in the smallest function value.
	IF recursionLevel <= 0 {
		IF ABS(fa) < ABS(fb) RETURN a.
		RETURN b.
	}

	// Not actually bracketed - Brent's method can't guarantee anything here, so
	// use the bracketAroundGuess function to generate a bracket and try again.
	IF fa * fb > 0 {
		LOCAL results IS 0.
		IF ABS(fa) < ABS(fb) SET results TO bracketAroundGuess(delegate, a, -1e12, 1e12, MAX(ABS(a), ABS(b)) * 0.5 + 1).
		ELSE SET results TO bracketAroundGuess(delegate, b, -1e12, 1e12, MAX(ABS(a), ABS(b)) * 0.5 + 1).
		return findZeroBrent(delegate, results["low"], results["high"], tolerance, maxIterations, recursionLevel - 1).
	}

	// Keep b as the current best estimate: |f(b)| <= |f(a)| is an invariant
	// maintained by re-checking and re-swapping after every update below.
	IF ABS(fa) < ABS(fb) {
		LOCAL swapValue IS a. SET a TO b. SET b TO swapValue.
		SET swapValue TO fa. SET fa TO fb. SET fb TO swapValue.
	}

	LOCAL c IS a.
	LOCAL fc IS fa.
	LOCAL useBisection IS TRUE.
	LOCAL d IS a. // unused until useBisection is cleared for the first time
	LOCAL s IS b.
	LOCAL fs IS fb.
	LOCAL iteration IS 0.

	UNTIL (fb = 0) OR (fs = 0) OR (ABS(b - a) < tolerance) OR (iteration >= maxIterations) {
		IF (fa <> fc) AND (fb <> fc) {
			// inverse quadratic interpolation
			SET s TO a * fb * fc / ((fa - fb) * (fa - fc))
				+ b * fa * fc / ((fb - fa) * (fb - fc))
				+ c * fa * fb / ((fc - fa) * (fc - fb)).
		} ELSE {
			// secant method
			SET s TO b - fb * (b - a) / (fb - fa).
		}

		// Reject an interpolated step that lands outside the bracket or shrinks it too slowly.
		LOCAL lowBound IS MIN((3 * a + b) / 4, b).
		LOCAL highBound IS MAX((3 * a + b) / 4, b).
		LOCAL fallBackToBisection IS FALSE.
		IF (s < lowBound) OR (s > highBound) SET fallBackToBisection TO TRUE.
		IF useBisection AND (ABS(s - b) >= ABS(b - c) / 2) SET fallBackToBisection TO TRUE.
		IF (NOT useBisection) AND (ABS(s - b) >= ABS(c - d) / 2) SET fallBackToBisection TO TRUE.
		IF useBisection AND (ABS(b - c) < tolerance) SET fallBackToBisection TO TRUE.
		IF (NOT useBisection) AND (ABS(c - d) < tolerance) SET fallBackToBisection TO TRUE.

		IF fallBackToBisection {
			SET s TO (a + b) / 2.
			SET useBisection TO TRUE.
		} ELSE {
			SET useBisection TO FALSE.
		}

		SET fs TO delegate(s).
		SET d TO c.
		SET c TO b.
		SET fc TO fb.

		IF fa * fs < 0 {
			SET b TO s.
			SET fb TO fs.
		} ELSE {
			SET a TO s.
			SET fa TO fs.
		}

		IF ABS(fa) < ABS(fb) {
			LOCAL swapValue2 IS a. SET a TO b. SET b TO swapValue2.
			SET swapValue2 TO fa. SET fa TO fb. SET fb TO swapValue2.
		}

		SET iteration TO iteration + 1.
	}

	RETURN b.
}

// Find Quadratic Roots
// Given the three values A, B and C, return the solutions to the quadratic Ax^2 + Bx + C = 0
// Returns a LEXICON with up to three entries.
//    Roots will be the number of solutions, scalar with value 0, 1 or 2.
//    Positive will be the positive solution, if it exists (or the only solution, if there is only one)
//		Negative will be the negative solution, if it exists.
FUNCTION solveQuadratic {
	PARAMETER A.
	PARAMETER B.
	PARAMETER C.
  LOCAL discriminant IS B*B-4*A*C.
  IF discriminant < 0 RETURN LEXICON("Roots", 0).
  IF discriminant = 0 RETURN LEXICON("Roots", 1, "Positive", -B/(2*A)).
  RETURN LEXICON("Roots", 2, "Positive", (-B+SQRT(discriminant))/(2*A), "Negative", (-B-SQRT(discriminant))/(2*A)).
}

// ============================================================================
// Kepler equation (moved from library.ks): mean and true anomaly
// ============================================================================

// given the mean anomaly (in degrees), returns true anomaly (in degrees)
FUNCTION meanToTrueAnomaly {
  PARAMETER meanAnomaly.
  PARAMETER eccentricity IS SHIP:ORBIT:ECCENTRICITY.

  // If eccentricity is 0, mean, true and eccentric anomaly are all the same thing, so return mean anomaly.
  IF eccentricity = 0 RETURN meanAnomaly.

  // Convert to radians for calculations.
  SET meanAnomaly TO CONSTANT:DegToRad * meanAnomaly.

  // Note that this function requires angles to be in radians
  LOCAL functionDelegate IS {PARAMETER E. RETURN E - eccentricity*SIN(CONSTANT:RadToDeg * E) - meanAnomaly.}.

  LOCAL eccentricAnomaly IS findZeroSecant(functionDelegate, meanAnomaly, meanAnomaly + CONSTANT:PI/32, 0.0000001).
  LOCAL trueAnomaly IS ARCTAN2(SQRT(1-eccentricity*eccentricity)*SIN(CONSTANT:RadToDeg * eccentricAnomaly), COS(CONSTANT:RadToDeg * eccentricAnomaly) - eccentricity).
  UNTIL trueAnomaly >= 0 {
    SET trueAnomaly TO trueAnomaly + 360.0.
  }

  RETURN normalizeAngle360(trueAnomaly).
}

// given the true anomaly (in degrees), returns mean anomaly (in degrees)
FUNCTION trueToMeanAnomaly {
  PARAMETER trueAnomaly.
  PARAMETER eccentricity IS SHIP:ORBIT:ECCENTRICITY.

  // If eccentricity is 0, mean, true and eccentric anomaly are all the same thing, so return true anomaly.
  IF eccentricity = 0 RETURN trueAnomaly.

	IF eccentricity < 1 { // elliptical case
		// note that eccentric anomaly is in radians
		LOCAL eccentricAnomaly IS CONSTANT:DegToRad * 2 * ARCTAN(TAN(trueAnomaly / 2) / SQRT((1 + eccentricity) / (1 - eccentricity))).
		//PRINT "eccentric anomaly: " + (eccentricAnomaly * CONSTANT:RadToDeg).

	//  This method also calculates eccentric anomaly equally well, but it is much more processor intensive than the other one.
	//	LOCAL cosE IS (eccentricity + COS(trueAnomaly))/(1 + eccentricity * COS(trueAnomaly)).
	//	LOCAL sinE IS SQRT(1 - eccentricity^2) * SIN(trueAnomaly)/(1 + eccentricity * COS(trueAnomaly)).
	//  LOCAL eccentricAnomaly IS CONSTANT:DegToRad * ARCTAN2(sinE, cosE).
		LOCAL meanAnomaly IS CONSTANT:RadToDeg * (eccentricAnomaly - eccentricity * SIN(eccentricAnomaly * CONSTANT:RadToDeg)).
		RETURN normalizeAngle360(meanAnomaly).
	} ELSE { // hyperbolic case
		// Note: equations taken from https://en.wikipedia.org/wiki/Hyperbolic_trajectory, section "Equations of Motion"
		// Hyperbolic Eccentric Anomaly
		LOCAL bigE IS ACOSH((eccentricity + COS(trueAnomaly))/(1 + eccentricity * COS(trueAnomaly))).
		IF trueAnomaly < 0 SET bigE TO -bigE.

		LOCAL meanAnomaly IS eccentricity * SINH(bigE) - bigE.
		RETURN CONSTANT:RadToDeg * meanAnomaly.
	}
}

// ============================================================================
// Orbit prediction helpers (moved from library.ks): what the orbit after a node looks like
// ============================================================================

// Orbit Elements Lexicon
// The elements of an orbit that are compared by nodeOrbitComparison.
// Passed the following
//			orbit (orbit)
// Returns a lexicon of "inc" (deg), "lan" (deg), "aop" (deg), "ecc" and "sma" (m)
FUNCTION orbitElementsLexicon {
	PARAMETER eachOrbit.
	RETURN LEXICON("inc", eachOrbit:INCLINATION,
					"lan", eachOrbit:LAN,
					"aop", eachOrbit:ARGUMENTOFPERIAPSIS,
					"ecc", eachOrbit:ECCENTRICITY,
					"sma", eachOrbit:SEMIMAJORAXIS).
}

// Node Patch
// Finds the patch of the ship's flight plan (the part of it between two sphere of influence changes) that a time falls in. A node can be
// on a later patch than the one that the ship is on, around another body, when the ship will leave this sphere of influence before it.
// Passed the following
//			time (scalar, UT in s)
// Returns a lexicon of "Orbit" (the patch), "Body" (the body that it is around), "Start" (UT in s, now for the ship's own patch) and
//		"End" (UT in s of the next sphere of influence change, 1E15 if there is none)
FUNCTION nodePatch {
	PARAMETER patchTime.
	LOCAL patch IS SHIP:ORBIT.
	LOCAL patchStart IS TIME:SECONDS.
	UNTIL NOT patch:HASNEXTPATCH {
		LOCAL patchEnd IS TIME:SECONDS + patch:NEXTPATCHETA.
		IF patchEnd > patchTime BREAK.
		SET patchStart TO patchEnd.
		SET patch TO patch:NEXTPATCH.
	}
	LOCAL endTime IS 1E15.
	IF patch:HASNEXTPATCH SET endTime TO TIME:SECONDS + patch:NEXTPATCHETA.
	RETURN LEXICON("Orbit", patch, "Body", patch:BODY, "Start", patchStart, "End", endTime).
}

// Node Orbit Snapshot
// Records the orbit that the ship is in at the node, the orbit that the maneuver node predicts, and where the node is. Call it before the
// burn, and give the result to nodeOrbitComparison after the burn. When the node is on a later patch (around another body), everything
// is relative to that body and its patch, which is what the burn solver needs to start from before the ship has got there.
// Passed the following
//			maneuver node (node)
// Returns a lexicon of "Body" (the body that the node's patch is around), "NodeUT" (s), "Period" (s, of that patch, 0 if it is not a closed
//		orbit), "Old" and "Predicted"
//		(orbitElementsLexicon), "OldNormal" and "PredictedNormal" (unit vectors, the normals of the old and the predicted orbit planes),
//		"NodePosition" and "NodeVelocity" (vectors, raw, body-relative position and orbital velocity on that patch at the node),
//		"PatchStart" and "PatchEnd" (UT in s of the sphere of influence changes around the node's patch), and
//		"StateError" (scalar, how far the position and velocity at the node are from agreeing with the energy of the patch, as a fraction
//		of that energy. About 1E-5 or less when the state is right, and large if the position or velocity is relative to the wrong body.
//		Nothing has checked the frame across a sphere of influence change in flight, so burnSnapshotError uses it)
FUNCTION nodeOrbitSnapshot {
	PARAMETER maneuverNode.
	LOCAL nodeUT IS TIME:SECONDS + maneuverNode:ETA.
	LOCAL patchInfo IS nodePatch(nodeUT).
	LOCAL patchOrbit IS patchInfo["Orbit"].
	LOCAL patchBody IS patchInfo["Body"].
	// Sampled a hair BEFORE the node: at the node time itself VELOCITYAT returns the velocity after the burn (the next patch), which
	// made the "old" plane the new one (planes 26.6 degrees from the truth in a flight log) and the crossing sign arbitrary.
	LOCAL beforeNode IS 0.02.
	LOCAL nodePosition IS POSITIONAT(SHIP, nodeUT - beforeNode) - patchBody:POSITION.
	LOCAL nodeVelocity IS VELOCITYAT(SHIP, nodeUT - beforeNode):ORBIT.
	// the energy of a conic is -mu / (2 sma), the same everywhere on it (vis-viva): a check of the position and velocity
	LOCAL stateError IS 0.
	IF ABS(patchOrbit:SEMIMAJORAXIS) < 1E14 {
		LOCAL patchEnergy IS -patchBody:MU / (2 * patchOrbit:SEMIMAJORAXIS).
		LOCAL stateEnergy IS nodeVelocity:SQRMAGNITUDE / 2 - patchBody:MU / nodePosition:MAG.
		SET stateError TO ABS(stateEnergy - patchEnergy) / ABS(patchEnergy).
	}
	// The period of an orbit that is not closed (a hyperbola, as a node that is before a capture burn is on) is infinite, and kOS does not
	// let an infinite value be used at all ("Tried to push Infinity into the stack"), so it is 0 for those.
	LOCAL patchPeriod IS 0.
	IF patchOrbit:ECCENTRICITY < 1 SET patchPeriod TO patchOrbit:PERIOD.
	RETURN LEXICON("Body", patchBody,
					"NodeUT", nodeUT,
					"PatchStart", patchInfo["Start"],
					"PatchEnd", patchInfo["End"],
					"StateError", stateError,
					"Period", patchPeriod,
					"Old", orbitElementsLexicon(patchOrbit),
					"Predicted", orbitElementsLexicon(maneuverNode:ORBIT),
					"OldNormal", VCRS(nodePosition, nodeVelocity):NORMALIZED,
					"PredictedNormal", VCRS(nodePosition, nodeVelocity + maneuverNode:DELTAV):NORMALIZED,
					"NodePosition", nodePosition,
					"NodeVelocity", nodeVelocity).
}

// Empty Orbit Snapshot
// A snapshot with the same keys as nodeOrbitSnapshot and nothing in them (zero vectors, an orbit with every element 0 and a semi-major
// axis of 1E9 m), for a script that has lost its maneuver node before it could take the snapshot (the node was deleted while it waited) and
// has to get to its end without reading the node. Nothing should be computed from it.
// Returns a lexicon, see nodeOrbitSnapshot
FUNCTION emptyOrbitSnapshot {
	LOCAL emptyElements IS LEXICON("inc", 0, "lan", 0, "aop", 0, "ecc", 0, "sma", 1E9).
	RETURN LEXICON("Body", SHIP:BODY,
					"NodeUT", TIME:SECONDS,
					"PatchStart", TIME:SECONDS,
					"PatchEnd", TIME:SECONDS,
					"StateError", 1E9,
					"Period", 0,
					"Old", emptyElements,
					"Predicted", emptyElements,
					"OldNormal", V(0, 0, 0),
					"PredictedNormal", V(0, 0, 0),
					"NodePosition", V(0, 0, 0),
					"NodeVelocity", V(0, 0, 0)).
}

// Burn Snapshot Error
// Works out whether a snapshot of the node (nodeOrbitSnapshot) is one that the burn solver can start from. The node can be on a later
// patch than the ship's own, around another body (the snapshot is then relative to that body), but the whole burn has to be on it, and the
// position and velocity that came from the game have to agree with its orbit, which is the check of the frame across a sphere of influence
// change that nothing has flown yet.
// Passed the following
//			snapshot (lexicon, from nodeOrbitSnapshot)
//			ignitionLead (scalar, s, how long before the node the burn starts)
//			planned burn time (scalar, s)
//			largest state error (scalar, see "StateError" of nodeOrbitSnapshot; the default is a thousand times what a right state gives)
//			margin (scalar, s, kept between the burn and the sphere of influence change on each side)
// Returns "None" if the solver can run, otherwise the reason that it cannot (string)
FUNCTION burnSnapshotError {
	PARAMETER snapshot.
	PARAMETER ignitionLead.
	PARAMETER plannedBurn.
	PARAMETER largestStateError IS 1E-3.
	PARAMETER margin IS 20.

	IF snapshot["StateError"] > largestStateError RETURN "the node's position and velocity do not agree with its orbit (energy error " + ROUND(snapshot["StateError"], 6) + ")".
	LOCAL nodeUT IS snapshot["NodeUT"].
	// the ship's own patch starts now; a later one starts at a sphere of influence change that has to be before the ignition
	IF snapshot["PatchStart"] > TIME:SECONDS + 1 AND snapshot["PatchStart"] > nodeUT - ignitionLead - margin RETURN "the burn starts too close to the sphere of influence change before the node".
	// the solver also looks 20 s past the end of the burn
	IF snapshot["PatchEnd"] < nodeUT + plannedBurn + 20 + margin RETURN "the burn runs into the sphere of influence change after the node".
	RETURN "None".
}

// Solver Result Error
// Checks a result of solveBurnCorrection before it is used, since it is only the best that the fit found: it can be wrong if the simulation
// could not finish the burn (too long for its step limit, out of propellant), if it did not get close to the node's orbit, or if the
// numbers are outside anything that a real burn needs. The checks are
//   - the simulated burn ended on the remaining delta V or on the orbit energy, not on the step limit, the propellant or an abort,
//   - the miss is under the larger of maxMiss and a thousandth of the node's distance from the body, and it is under 0.3 of the miss at the
//     start (the fit has improved on the guess) unless it is under 300 m (a short burn starts with a small miss that cannot improve by much:
//     a flown one went from 229 m to 172 m, and the 100 m that this was refused that result, which was the better of the two),
//   - the shift is under maxShiftFraction of the planned burn time, both tilts are under maxTilt (rad), and none of them is huge,
//   - the simulated burn time is within burnTimeTolerance (a fraction) plus 5 s of the planned burn time.
// Flown burns had misses of 16 to 197 m (3000 to 5400 m at the guess), shifts of 1 to 7 s in 130 to 220 s burns (0.7 to 3 percent) and
// tilts of 0.007 to 0.014 rad.
// Passed the following
//			solution (lexicon, from solveBurnCorrection)
//			spec (lexicon, the burnSolveSpec that it was solved for)
//			planned burn time (scalar, s)
//			largest miss (scalar, m, default 500)
//			largest shift (scalar, fraction of the planned burn time, default 0.2)
//			largest tilt (scalar, rad, default 0.1)
//			burn time tolerance (scalar, fraction, default 0.1)
// Returns "None" if the result can be used, otherwise the reason that it cannot (string)
FUNCTION solverResultError {
	PARAMETER solution.
	PARAMETER spec.
	PARAMETER plannedBurn.
	PARAMETER maxMiss IS 500.
	PARAMETER maxShiftFraction IS 0.2.
	PARAMETER maxTilt IS 0.1.
	PARAMETER burnTimeTolerance IS 0.1.

	LOCAL simulated IS solution["burn"].
	IF simulated["endReason"] <> "remaining delta V" AND simulated["endReason"] <> "orbit energy reached" RETURN "the simulated burn ended on " + simulated["endReason"].
	FOR eachValue IN LIST(solution["shift"], solution["tilt"], solution["tilt2"], solution["miss"], simulated["burnTime"]) {
		IF ABS(eachValue) > 1E9 RETURN "a result is not a sensible number".
	}
	LOCAL missLimit IS MAX(maxMiss, spec["nodePosition"]:MAG / 1000).
	IF solution["miss"] > missLimit RETURN "the miss, " + ROUND(solution["miss"], 0) + " m, is over " + ROUND(missLimit, 0) + " m".
	IF solution["miss"] > 300 AND solution["miss"] > 0.3 * solution["startMiss"] RETURN "the miss, " + ROUND(solution["miss"], 0) + " m, is not much better than at the guess, " + ROUND(solution["startMiss"], 0) + " m".
	IF ABS(solution["shift"]) > maxShiftFraction * plannedBurn RETURN "the shift, " + ROUND(solution["shift"], 1) + " s, is over " + ROUND(maxShiftFraction * 100) + "% of the burn".
	IF ABS(solution["tilt"]) > maxTilt OR ABS(solution["tilt2"]) > maxTilt RETURN "a tilt, " + ROUND(solution["tilt"], 3) + " or " + ROUND(solution["tilt2"], 3) + " rad, is over " + maxTilt + " rad".
	IF ABS(simulated["burnTime"] - plannedBurn) > burnTimeTolerance * plannedBurn + 5 RETURN "the simulated burn time, " + ROUND(simulated["burnTime"], 1) + " s, is far from the planned " + ROUND(plannedBurn, 1) + " s".
	RETURN "None".
}

// Plane Crossing Angle
// The angle, along the old orbit, from the node to the line where a new orbit plane crosses the old plane. That line is where
// the plane change really took effect. Positive is ahead of the node in the direction of travel (later), negative is behind (earlier).
// Passed the following
//			normal of the old orbit plane (vector, unit)
//			normal of the new orbit plane (vector, unit)
//			position of the node (vector, body-relative)
//			velocity at the node (vector)
// Returns the angle (scalar, deg), or 0 if the planes are (nearly) the same, as in a burn that does not change the plane
FUNCTION planeCrossingAngle {
	PARAMETER oldNormal.
	PARAMETER newNormal.
	PARAMETER nodePosition.
	PARAMETER nodeVelocity.
	LOCAL crossLine IS VCRS(oldNormal, newNormal).
	// the planes cross along a line only if they differ by more than a hair (1E-4 is about 0.006 degrees), otherwise it is noise
	IF crossLine:MAG < 1E-4 RETURN 0.
	SET crossLine TO crossLine:NORMALIZED.
	IF VDOT(crossLine, nodePosition) < 0 SET crossLine TO -crossLine.
	LOCAL crossAngle IS VANG(crossLine, nodePosition).
	IF VDOT(crossLine, nodeVelocity) < 0 SET crossAngle TO -crossAngle.
	RETURN crossAngle.
}

// Node Orbit Comparison
// Compares the orbit that the ship is in now with the orbit that the node predicted, using a snapshot from before the burn.
// The plane normals come from position and velocity (VCRS), not from inclination and LAN. The element based normals gave a
// final plane crossing with the opposite sign to an independent reconstruction from the logged state (+0.295 against -0.272 deg).
// Passed the following
//			snapshot (lexicon, from nodeOrbitSnapshot)
// Returns a lexicon of "Predicted", "Actual" (orbitElementsLexicon), "Old" (the orbit before the burn), "PlaneAngle" (deg, between the
//		predicted and actual orbit planes), "PredictedCrossing", "ActualCrossing" (deg, see planeCrossingAngle),
//		"ActualCrossingTime" (s of the old orbit), "NodeUT" (s)
FUNCTION nodeOrbitComparison {
	PARAMETER snapshot.
	LOCAL centralBody IS snapshot["Body"].
	LOCAL actual IS orbitElementsLexicon(SHIP:ORBIT).
	LOCAL oldNormal IS snapshot["OldNormal"].
	LOCAL predNormal IS snapshot["PredictedNormal"].
	LOCAL actualNormal IS VCRS(-SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT):NORMALIZED.
	LOCAL actualCrossing IS planeCrossingAngle(oldNormal, actualNormal, snapshot["NodePosition"], snapshot["NodeVelocity"]).
	RETURN LEXICON("Predicted", snapshot["Predicted"],
					"Actual", actual,
					"Old", snapshot["Old"],
					"PlaneAngle", VANG(predNormal, actualNormal),
					"PredictedCrossing", planeCrossingAngle(oldNormal, predNormal, snapshot["NodePosition"], snapshot["NodeVelocity"]),
					"ActualCrossing", actualCrossing,
					"ActualCrossingTime", actualCrossing * snapshot["Period"] / 360,
					"NodeUT", snapshot["NodeUT"]).
}

// Node Orbit Check Lines
// Formats the result of nodeOrbitComparison as comma separated lines for a log file.
// Passed the following
//			comparison (lexicon, from nodeOrbitComparison)
// Returns a list of strings
FUNCTION nodeOrbitCheckLines {
	PARAMETER comparison.
	LOCAL lines IS LIST().
	LOCAL predicted IS comparison["Predicted"].
	LOCAL actual IS comparison["Actual"].
	lines:ADD("Orbit check after the burn (actual orbit compared with the orbit predicted by the node)").
	lines:ADD("Node UT," + comparison["NodeUT"] + ",s,check UT," + TIME:SECONDS + ",s").
	lines:ADD("element,before burn,predicted,actual,actual-predicted").
	lines:ADD("inc deg," + comparison["Old"]["inc"] + "," + predicted["inc"] + "," + actual["inc"] + "," + (actual["inc"] - predicted["inc"])).
	lines:ADD("LAN deg," + comparison["Old"]["lan"] + "," + predicted["lan"] + "," + actual["lan"] + "," + normalizeAngle180(actual["lan"] - predicted["lan"])).
	lines:ADD("argPe deg," + comparison["Old"]["aop"] + "," + predicted["aop"] + "," + actual["aop"] + "," + normalizeAngle180(actual["aop"] - predicted["aop"])).
	lines:ADD("ecc," + comparison["Old"]["ecc"] + "," + predicted["ecc"] + "," + actual["ecc"] + "," + (actual["ecc"] - predicted["ecc"])).
	lines:ADD("SMA m," + comparison["Old"]["sma"] + "," + predicted["sma"] + "," + actual["sma"] + "," + (actual["sma"] - predicted["sma"])).
	lines:ADD("Angle between predicted and actual orbit planes," + comparison["PlaneAngle"] + ",deg").
	lines:ADD("Plane crossing from node (+ later / - earlier) predicted," + comparison["PredictedCrossing"] + ",deg").
	lines:ADD("Plane crossing from node (+ later / - earlier) actual," + comparison["ActualCrossing"] + ",deg," + comparison["ActualCrossingTime"] + ",s").
	RETURN lines.
}

// ============================================================================
// More numerical routines (moved from libraryPID.ks and libraryTransfer.ks)
// ============================================================================

// linearRegression
// Inputs:
//   samples (List of Lexicon("t","pos"), both Scalar) - data points to
//        fit; needs at least 2 elements for a non-degenerate result.
// Outputs:
//   Lexicon with "slope" (Scalar) and "intercept" (Scalar) of the
//   least-squares line pos = slope*t + intercept. Both 0 if samples has
//   fewer than 2 elements or all "t" values are identical.
// Side Effects:
//   None.
FUNCTION linearRegression {
    PARAMETER samples.

    LOCAL n IS samples:LENGTH.
    IF n < 2 { RETURN LEXICON("slope", 0, "intercept", 0). }

    LOCAL sumT IS 0. LOCAL sumPos IS 0. LOCAL sumTT IS 0. LOCAL sumTPos IS 0.
    FOR s IN samples {
        SET sumT TO sumT + s["t"].
        SET sumPos TO sumPos + s["pos"].
        SET sumTT TO sumTT + s["t"]^2.
        SET sumTPos TO sumTPos + s["t"] * s["pos"].
    }

    LOCAL denom IS n * sumTT - sumT^2.
    IF denom = 0 { RETURN LEXICON("slope", 0, "intercept", sumPos / n). }

    LOCAL slope IS (n * sumTPos - sumT * sumPos) / denom.
    LOCAL intercept IS (sumPos - slope * sumT) / n.
    RETURN LEXICON("slope", slope, "intercept", intercept).
}

// Time (s) to fly a hyperbola from true anomaly startAnomaly to endAnomaly (degrees).
//   vInfinity - hyperbolic excess speed (m/s); eccentricity - of the hyperbola.
FUNCTION hyperbolaTransitTime {
	PARAMETER mu.
	PARAMETER vInfinity.
	PARAMETER eccentricity.
	PARAMETER startAnomaly.
	PARAMETER endAnomaly.

	// (Rounding can put a near-parabolic eccentricity a hair below 1; that is a parabola, not an error.)
	LOCAL sqrtTerm IS SQRT(MAX(0, eccentricity ^ 2 - 1)).
	LOCAL semiMajorAbs IS mu / vInfinity ^ 2.
	LOCAL meanMotion IS SQRT(mu / semiMajorAbs ^ 3).

	// sinh of the hyperbolic anomaly at each end, then the hyperbolic mean anomaly.
	LOCAL startSinh IS sqrtTerm * SIN(startAnomaly) / (1 + eccentricity * COS(startAnomaly)).
	LOCAL endSinh IS sqrtTerm * SIN(endAnomaly) / (1 + eccentricity * COS(endAnomaly)).
	LOCAL startMean IS eccentricity * startSinh - ASINH(startSinh).
	LOCAL endMean IS eccentricity * endSinh - ASINH(endSinh).
	RETURN (endMean - startMean) / meanMotion.
}
