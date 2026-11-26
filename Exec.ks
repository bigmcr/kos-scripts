@LAZYGLOBAL OFF.

PARAMETER ullage IS 5.												// the number of seconds the RCS thrusters need to be firing forward to
																							//		make the main engine's fuel be stable
																							//		only applicable when isStock is FALSE (engines that need ullage or have limited ignitions), so disabled otherwise
PARAMETER useRCSforRotation IS FALSE.
PARAMETER faceSun IS FALSE.										// during the waiting times, turn to face the sun
																							//		intended to ensure that probes' solar panels are exposed to the Sun.
PARAMETER suppressPrinting IS FALSE.
PARAMETER useRCSforThrust IS FALSE.								// burn with the RCS thrusters, firing forward, instead of the main engines (ExecRCS runs Exec like this).
																								//		The RCS is on for the whole run, there is no staging and no ullage, and the plan comes from the thrusters that fire
																								//		forward and the RCS propellant (rcsBurnStage in library.ks).

IF NOT suppressPrinting CLEARSCREEN.

// The kind of burn (burnWithRCS, burnLevel, setBurnThrottle, executeStop, stopReason and executeStopOrSample are in library.ks: this script
// defines no named labels, so that it can be loaded again under another name, as ExecRCS does). In an RCS burn the thrust is the forward
// translation control of the ship and the main throttle stays 0, and the RCS is on, so there is no ullage and the rotation may use it too.
SET burnWithRCS TO useRCSforThrust.
SET burnLevel TO 0.
IF burnWithRCS {
	SET useRCSforRotation TO TRUE.
	SET ullage TO 0.
}

LOCAL pointingError IS 1.0.										// Allowed pointing error, in degrees
LOCAL errorCode IS "None".
updateShipInfo().

IF (NOT HASNODE) SET errorCode TO "No Maneuver Node Present!".
IF NOT burnWithRCS {
	IF (shipInfo["CurrentStage"]["ENGINES"]:LENGTH = 0) SET errorCode TO "Ship has no engines in current stage!".
	IF (shipInfo["CurrentStage"]["Isp"] = 0) SET errorCode TO "Isp is Zero!".
	IF (shipInfo["CurrentStage"]["Thrust"] = 0) SET errorCode TO "Maximum engine thrust is Zero!".
}

// the stages that could be used for the burn, in the order that they would burn (the highest numbered stage burns first)
// For an RCS burn there is one: the RCS thrusters that fire forward, with the RCS propellant (rcsBurnStage, library.ks, which also checks
// that there are such thrusters and enough delta V for the node)
LOCAL usedStages IS LIST().
IF burnWithRCS {
	IF HASNODE {
		LOCAL rcsStage IS rcsBurnStage(NEXTNODE:DELTAV:MAG).
		usedStages:ADD(rcsStage["Stage"]).
		IF errorCode = "None" SET errorCode TO rcsStage["Error"].
	}
} ELSE {
	FOR stageNumber IN RANGE(shipInfo["NumberOfStages"] - 1, -1) {
		IF shipInfo["Stage " + stageNumber]["Isp"] <> 0 usedStages:ADD(shipInfo["Stage " + stageNumber]).
	}
}

// Check that the burn can be done at all (enough delta V, engines that can ignite, engines facing forward) before anything starts
IF errorCode = "None" AND NOT burnWithRCS SET errorCode TO burnFeasibilityError(usedStages, NEXTNODE:DELTAV:MAG).

// Thrust limiters (engine burns). The limiters of the engines of every used stage are first set to 100 % for the highest, with the others in
// the same ratio, each on a multiple of 0.5 % (normalizeThrustLimits, library.ks). A burn that is short at full thrust is then stretched by
// lowering the limiters of the engines that fire first, to take limitedBurnTime: a burn of a few seconds is a burn that is a few tenths of a
// second off at the end, and a small delta V is delivered more precisely over a longer time. That is only done when the whole burn is in one
// stage. The limiters are put back to 100 % when the script ends (limitFraction is the highest limit that was used, as a fraction).
LOCAL limitedBurnTime IS 10.												// s, the duration that a short burn is stretched to
LOCAL limitFraction IS 1.
IF errorCode = "None" AND NOT burnWithRCS AND usedStages:LENGTH > 0 {
	LOCAL burnScale IS 1.
	LOCAL highestLimit IS 0.
	FOR eng IN usedStages[0]["Engines"] {
		IF eng:THRUSTLIMIT > highestLimit SET highestLimit TO eng:THRUSTLIMIT.
	}
	IF highestLimit > 0 AND usedStages[0]["mDot"] > 0 {
		LOCAL firstExhaustVelocity IS usedStages[0]["Isp"] * g_0.
		LOCAL firstMassWet IS usedStages[0]["CurrentMass"].
		LOCAL firstMassDry IS firstMassWet - usedStages[0]["FuelMass"].
		LOCAL nodeDv IS NEXTNODE:DELTAV:MAG.
		IF nodeDv <= firstExhaustVelocity * LN(firstMassWet / firstMassDry) {
			// the burn time at the limiters' normalized setting (100 % for the highest)
			LOCAL fullBurnTime IS firstMassWet * (1 - CONSTANT:E^(-nodeDv / firstExhaustVelocity)) / (usedStages[0]["mDot"] * 100 / highestLimit).
			IF fullBurnTime < limitedBurnTime SET burnScale TO fullBurnTime / limitedBurnTime.
		}
	}
	LOCAL limitsChanged IS FALSE.
	// the first stage is last, so that engines that it shares with a later stage keep its limits
	FOR stageIndex IN RANGE(usedStages:LENGTH - 1, -1) {
		LOCAL stageScale IS 1.
		IF stageIndex = 0 SET stageScale TO burnScale.
		IF normalizeThrustLimits(usedStages[stageIndex]["Engines"], stageScale) SET limitsChanged TO TRUE.
	}
	IF limitsChanged {
		// the thrust, the mass flow and the rest of what shipInfo holds come from the limits
		updateShipInfo().
		usedStages:CLEAR().
		FOR stageNumber IN RANGE(shipInfo["NumberOfStages"] - 1, -1) {
			IF shipInfo["Stage " + stageNumber]["Isp"] <> 0 usedStages:ADD(shipInfo["Stage " + stageNumber]).
		}
	}
	IF burnScale < 1 {
		SET highestLimit TO 0.
		FOR eng IN usedStages[0]["Engines"] {
			IF eng:THRUSTLIMIT > highestLimit SET highestLimit TO eng:THRUSTLIMIT.
		}
		SET limitFraction TO highestLimit / 100.
		// (reported with the other statuses below)
	}
}

// only run the script if there is a node to execute
IF errorCode = "None" {
	updateShipInfoCurrent(FALSE).
	LOCAL oldRCS IS RCS.												// record the current status of RCS
	LOCAL oldSAS IS SAS.												// record the current status of SAS

	SET RCS TO useRCSforRotation.								// set RCS to the allowed state for the rotations (on for an RCS burn)
	SAS OFF.																		// always turn SAS off, as it interferes with steering control

	setLockedSteering(FALSE).
	SET globalSteer TO SHIP:FACING.
	setLockedSteering(TRUE).

	// The End key aborts the script (see abortKeyPressed in library.ks). It is looked at in every wait, in the warps, in the solver
	// and in the burn loop, and once it is pressed everything after it that waits or burns is skipped. The burn is cut at once.
	resetAbort().
	IF NOT suppressPrinting PRINT "Press End to abort".
	// Every run prints the same status lines, in the same order (when printing is not suppressed): the limiters, the stages, the node's
	// sphere of influence, the ullage, the turn, the burn solver, the burn altitude check, the alignment, the ignition, and the end of the
	// burn. A step that is not done in this run prints a line that says so (the solver and the altitude check share one line), and
	// warnings and the debug detail come in addition to them.
	IF NOT suppressPrinting {
		IF burnWithRCS PRINT "Thrust limiters: not used (RCS burn)".
		ELSE IF limitFraction < 1 PRINT "Thrust limiters: short burn, at " + ROUND(limitFraction * 100, 1) + " %".
		ELSE PRINT "Thrust limiters: 100 % (not a short burn)".
	}

	// The node is read through the safe accessors nodeETA() and nodeDeltaV() (library.ks), which give a fallback instead of the error that
	// kOS cannot catch when the node has been deleted while the script waits or burns, and executeStop() (library.ks) makes a missing node a
	// stop. NEXTNODE itself is only used where the node is known to be there. Nothing is remembered about the node, so a node that was moved or
	// edited is not noticed: the script goes on with what it reads from it now.
	LOCAL dV_req TO nodeDeltaV():MAG.

	// Physics warp (the level that library.ks allows, physicsWarpPerm) changes the direction and sometimes the size of the node a little,
	// which matters for a small burn, so there is no physics warp at all (not for the turns, the waits or the burn) when the node's delta V
	// is under physicsWarpMinDv. Time warp on rails is not affected.
	LOCAL physicsWarpMinDv IS 2.												// m/s
	LOCAL physicsWarpLevel IS physicsWarpPerm.
	IF dV_req < physicsWarpMinDv SET physicsWarpLevel TO 0.

	LOCAL ullageStatus IS "not needed".

	LOCAL Isp_stg IS LIST().
	LOCAL T_stg IS LIST().
	LOCAL m_dry_stg IS LIST().									// Mass of the empty stage (kg)
	LOCAL m_wet_stg IS LIST().									// Mass of the fuelled stage (kg)
	LOCAL v_e_stg IS LIST().										// Exhaust velocity (m/s)
	LOCAL dV_avail_stg IS LIST().								// Delta V available in this stage (m/s)
	LOCAL m_dot_stg IS LIST().									// Rate of change of mass for the engine (kg/s)
	LOCAL dv_prev_stg IS LIST().
	LOCAL dv_req_stage_stg IS LIST().
	LOCAL ign_after_t_0_stg IS LIST().
	LOCAL dv_before_t_0_stg IS LIST().
	LOCAL t_burn_req_stg IS LIST().
	LOCAL t_ign IS 0.														// the burn delay before nominal time (s)
	LOCAL t_total IS 0.													// the total burn duration (s)

	LOCAL e IS CONSTANT():E.            				// Base of natural log
	LOCAL g_0 IS 9.80665.            						// Gravitational acceleration constant (m/s²)
	LOCAL a_i IS 0.															// initial acceleration at the start of the burn (m/s^2)
	LOCAL a_f IS 0.															// final acceleration at the end of the burn (m/s^2)

	IF NOT suppressPrinting PRINT "Stages that can be used: " + usedStages:LENGTH.

	LOCAL Isp IS 0.
	LOCAL T IS 0.
	LOCAL m_dry IS 0.
	LOCAL m_wet IS 0.
	LOCAL v_e IS 0.
	LOCAL dV_avail IS 0.
	LOCAL m_dot IS 0.
	LOCAL dv_prev IS 0.
	LOCAL dV_req_stage IS 0.
	LOCAL ign_after_t_0 IS 0.
	LOCAL dv_before_t_0 IS 0.
	LOCAL t_burn_req IS 0.
	LOCAL highestUsedStage IS 0.
	LOCAL lowestUsedStage IS -1.
	// The time with no thrust while staging. The engines of the next stage light when the STAGE command that fires them runs, so the gap
	// is the time that the burn loop takes to notice the flameout, about 0.1 s (stageReactionTime), plus stageCommandTime for each STAGE command before the one that lights
	// the engines (stages in between with no engines of their own). stageFunction waits 0.5 s and then rebuilds shipInfo for each command,
	// and that is stageCommandTime (the measured loop time of every staging is written to Maneuver.csv, "stage loop time measured").
	LOCAL stageReactionTime IS 0.15.
	LOCAL stageCommandTime IS 1.2.

	FOR stageNumber IN RANGE(0, usedStages:LENGTH) {
		SET Isp TO usedStages[stageNumber]["Isp"].
		SET T TO usedStages[stageNumber]["Thrust"].
		SET m_dry TO usedStages[stageNumber]["CurrentMass"] - usedStages[stageNumber]["FuelMass"].
		SET m_wet TO usedStages[stageNumber]["CurrentMass"].
		SET v_e TO Isp * g_0.
		SET dV_avail TO v_e*LN(m_wet/m_dry).
		SET m_dot TO usedStages[stageNumber]["mDot"].
		SET dv_prev TO usedStages[stageNumber]["DeltaVPrev"].
		SET dV_req_stage TO MIN(MAX(dV_req-dV_prev,0),dV_avail).
		SET ign_after_t_0 TO dV_prev>dV_req/2.
		SET dv_before_t_0 TO MIN( dV_avail, dV_req / 2 - dv_Prev).
		IF ign_after_t_0 SET dv_before_t_0 TO 0.
		SET t_burn_req TO m_wet*(1-e^(-dV_req_stage/v_e))/m_dot.

		SET t_total TO t_total + t_burn_req.
		SET t_ign TO t_ign + m_wet*(1-e^(-dV_before_t_0/v_e))/m_dot.

		// the time with no thrust while the ship stages
		IF stageNumber > 0 AND dV_req_stage > 0 {
			LOCAL stageGapTime IS stagingGap(usedStages[stageNumber - 1]["Number"] - usedStages[stageNumber]["Number"], stageReactionTime, stageCommandTime).
			SET t_total TO t_total + stageGapTime.
			IF dV_before_t_0 > 0 SET t_ign TO t_ign + stageGapTime.				// the staging happens before the node
		}

		Isp_stg:ADD(Isp).
		T_stg:ADD(T).
		m_dry_stg:ADD(m_dry).
		m_wet_stg:ADD(m_wet).
		v_e_stg:ADD(v_e).
		dV_avail_stg:ADD(dV_avail).
		m_dot_stg:ADD(m_dot).
		dv_prev_stg:ADD(dv_prev).
		dV_req_stage_stg:ADD(dV_req_stage).
		ign_after_t_0_stg:ADD(ign_after_t_0).
		dV_before_t_0_stg:ADD(dV_before_t_0).
		t_burn_req_stg:ADD(t_burn_req).
		IF dv_req_stage > 0 SET highestUsedStage TO stageNumber.
		IF dv_req_stage > 0 AND lowestUsedStage = -1 SET lowestUsedStage TO stageNumber.
	}

	IF lowestUsedStage = -1 SET lowestUsedStage TO 0.

	// The end of the burn is throttled down, so that the burn can stop on the remaining delta V instead of overshooting it.
	// While the remaining delta V is less than taperTime seconds of full thrust, the throttle is the remaining time divided by
	// taperTime, so the remaining delta V decays exponentially, and it is finished when less than finishDv is left.
	// The throttle never goes back up: the delta V that the ship reads lags the thrust by about an iteration, so a final
	// throttle step sized to the remaining delta V gets delivered twice and overshoots.
	// With the throttle proportional to what is left, the thrust already in flight at the end is negligible.
	// Compared with full thrust until the end, that takes taperTime * (LN(taperTime * a_f / finishDv) - 1) longer.
	// Engines that cannot be throttled do not taper. The extra time is only added to the burn duration. The delta V centered
	// ignition time is not changed, since the taper happens after the middle of the delta V.
	LOCAL taperTime IS 0.5.														// seconds of full thrust left when the taper starts
	// Chosen so that the taper does not run
	// on for a second or more for thrust that is smaller than the burn's own error. The solver's simulation uses the same value.
	LOCAL finishDv IS 0.25.														// the burn is finished when less than this is left (m/s)
	// With the thrust limiters lowered (a short burn that is stretched, see limitFraction) the burn is finished on a smaller remaining delta
	// V, in proportion to the thrust (not below finishDvFloor, which is about what the thrust delivers in a few iterations), and the taper
	// takes longer. The end of the burn is off by about finishDv * (the delay of the delta V reading) / taperTime, so a longer taper is a
	// smaller error. (The taper's own length in delta V already follows the thrust: it is taperTime seconds of the thrust that is there.)
	LOCAL finishDvFloor IS 0.001.												// m/s
	IF limitFraction < 1 {
		SET finishDv TO MAX(finishDv * limitFraction, finishDvFloor).
		SET taperTime TO 1.
	}

	SET a_i TO usedStages[lowestUsedStage]["Thrust"] / usedStages[lowestUsedStage]["CurrentMass"].
	SET a_f TO usedStages[highestUsedStage]["Thrust"]/(usedStages[highestUsedStage]["CurrentMass"]*e^(-dV_req_stage_stg[highestUsedStage]/v_e_stg[highestUsedStage])).

	LOCAL taperExtra IS 0.
	IF usedStages[highestUsedStage]["Throttleable"] AND taperTime * a_f > finishDv SET taperExtra TO taperTime * (LN(taperTime * a_f / finishDv) - 1).
	SET t_total TO t_total + taperExtra.

	// A node on a later patch (around another body: the ship will change sphere of influence before the node) is not prepared from here. What
	// the game gives for such a node cannot be used yet: the burn solver's snapshot of one does not agree with its orbit (the position or
	// the velocity is not in the frame that was assumed), and its burn vector turns while the ship turns toward it,
	// where the vector of a node in the ship's own sphere of influence stays fixed. So the script first warps
	// on rails to the change of sphere of influence, and then carries on with the node in the ship's own sphere of influence, where all of
	// what follows is known to work (the solver included, if there is time left). The ship's attitude is left alone until then.
	LOCAL laterPatchWarps IS 0.
	UNTIL laterPatchWarps >= 5 OR executeStop() {
		LOCAL nodePatchInfo IS nodePatch(TIME:SECONDS + nodeETA()).
		IF nodePatchInfo["Start"] <= TIME:SECONDS + 1 BREAK.
		IF NOT suppressPrinting PRINT "The node is in another sphere of influence (" + nodePatchInfo["Body"]:NAME + "): waiting for the ship to get there".
		warpToTime(nodePatchInfo["Start"] + 20, executeStop@).
		SET laterPatchWarps TO laterPatchWarps + 1.
	}
	IF NOT suppressPrinting {
		IF laterPatchWarps = 0 PRINT "Node sphere of influence: the ship's own".
		ELSE PRINT "Node sphere of influence: reached".
	}

	// The orbits before the burn and where the node is, taken once, now. It is where the burn solver starts from, and it is compared with the
	// orbit that the burn made. It is the same orbit whenever it is taken, and taking it here means that the node does not have to be read
	// for it at the ignition. (If the node has been deleted by now, while the ship was warping to its sphere of influence, there is nothing
	// to take it from: NEXTNODE would fail with "No maneuver nodes present", so the snapshot is an empty one, and the script goes on to its end
	// as a stopped script, since executeStop has made the missing node a stop.)
	LOCAL orbitSnapshot IS emptyOrbitSnapshot().
	IF HASNODE SET orbitSnapshot TO nodeOrbitSnapshot(NEXTNODE).
	LOCAL burnNodeUT IS TIME:SECONDS + nodeETA().									// when the node is, for the hook at the end (finishMultiPassPlan)

	// The ullage (RealFuels, see the parameter ullage) needs the RCS to fire forward, with propellant for it: it is checked now, while there is
	// time to do something about it. A burn does not have to be stopped for it, since not every engine needs the ullage, but one that
	// does may not ignite without it.
	IF NOT (isStock() OR ullage = 0) {
		LOCAL ullageCheck IS ullageFuelCheck(ullage).
		IF ullageCheck["Message"] = "None" SET ullageStatus TO "ok".
		ELSE {
			SET ullageStatus TO "WARNING: " + ullageCheck["Message"].
		}
	}
	IF NOT suppressPrinting {
		IF ullageStatus = "not needed" PRINT "Ullage: not needed".
		ELSE IF ullageStatus = "ok" PRINT "Ullage: the RCS can fire for " + ullage + " s".
		ELSE PRINT ullageStatus + "; an engine that needs the ullage may not ignite".
	}

	// The turn to the burn direction. A ship with little control authority can take a very long time to turn, so the
	// turn starts now, before the solver (the ship keeps turning while the solver runs). The time that it needs comes from
	// shipInfo["Rotation"] (library.ks, updateStoppingTime): the measured angular acceleration and the steering manager's stopping time,
	// which turnTimeFor turns into the time for this angle. That is the ideal time (no lag in the steering controller), so the planned
	// time is turnMargin times it, plus turnSettle for the rotation to damp out. The angle left when
	// the solver finishes and the time to be aligned are written to Maneuver.csv, to check the margin.
	// If the rotation was measured with RCS on and the turn is done without it, the ship turns slower than measured, and the margin is doubled.
	LOCAL turnSettle IS 5.														// s allowed for the rotation to damp out after the turn
	LOCAL turnMargin IS 1.5.													// planned turn time / ideal turn time
	LOCAL rotationInfo IS shipInfo["Rotation"].
	LOCAL turnKnown IS rotationInfo["Accel"] > 0.
	LOCAL turnToSun IS faceSun AND nodeETA() > 60*60.								// the first turn is to face the Sun, not the burn direction
	LOCAL turnVector IS nodeDeltaV().
	IF turnToSun SET turnVector TO BODY("Sun"):POSITION.
	LOCAL turnAngle IS VANG(SHIP:FACING:VECTOR, turnVector).
	LOCAL turnStartUT IS TIME:SECONDS.
	LOCAL turnAlignedAfter IS -1.												// s from the start of the turn to being aligned, -1 if not aligned before the ignition
	LOCAL turnAngleAfterSolver IS -1.											// deg still to turn when the solver finished
	LOCAL turnIdealTime IS -1.													// s, -1 if the rotation has not been measured
	LOCAL turnPlannedTime IS -1.
	LOCAL turnLead IS 0.														// s that the second alignment (just before the burn) is given, for a turn of up to 180 degrees
	// The rotation rate (rad/s) that counts as stopped when waiting to be aligned (settledRate), and the tighter one for the damping wait
	// after it (dampRate). Both are for the pitch and yaw rate, without any roll about the ship's axis (rotationSettled in library.ks). A fixed rate does not work for a ship that turns slowly, which is under it
	// all the time, so the test says nothing. With the ship's measured rates they are fractions of the fastest rotation that the steering
	// manager allows (MaxRate), never more than 0.1 rad/s, and not below a floor:
	//   stock:     settled at 10% of MaxRate (floor 0.0005 rad/s, about 0.03 deg/s, which the steering's own wobble can exceed),
	//              damped at 2% of MaxRate (floor 0.0005).
	//   RealFuels: (isStock() is FALSE) stricter: settled at 1% of MaxRate (floor 0.0002 rad/s), damped at 0.4% (floor 0.0001).
	//              Those installations almost always have PersistentRotation too, so the rotation that is left when the ship goes on
	//              rails carries on through the long warp to the node (0.0002 rad/s is 40 degrees in an hour). That drift is why the
	//              ship is aligned again just before the burn. The steering's own wobble may keep the rate above these limits, so the
	//              first wait gives up alignGiveUp after the ship was first aligned, and the damping wait is limited in time.
	// The rate when the wait ended is written to Maneuver.csv.
	LOCAL settleFraction IS 0.1.
	LOCAL settleFloor IS 0.0005.
	LOCAL dampFraction IS 0.02.
	LOCAL dampFloor IS 0.0005.
	IF NOT isStock() {
		SET settleFraction TO 0.01.
		SET settleFloor TO 0.0002.
		SET dampFraction TO 0.004.
		SET dampFloor TO 0.0001.
	}
	LOCAL settledRate IS 0.1.
	LOCAL dampRate IS 0.														// 0 when the rates are not known: only the time limit of the damping wait is used
	LOCAL settleLimit IS 120.													// s after the start of the turn that an aligned ship is given to get under settledRate
	IF turnKnown {
		IF rotationInfo["RCS"] AND NOT useRCSforRotation {
			SET turnMargin TO turnMargin * 2.
			IF NOT suppressPrinting PRINT "The rotation was measured with RCS on and RCS is off for the turn: the turn time is a guess".
		}
		SET turnIdealTime TO turnTimeFor(rotationInfo["Accel"], rotationInfo["StoppingTime"], turnAngle).
		SET turnPlannedTime TO turnIdealTime * turnMargin + turnSettle.
		SET turnLead TO rotationInfo["TurnTime"] * turnMargin + turnSettle.
		SET settledRate TO MIN(0.1, MAX(rotationInfo["MaxRate"] * settleFraction, settleFloor)).
		SET dampRate TO MIN(settledRate, MAX(rotationInfo["MaxRate"] * dampFraction, dampFloor)).
		SET settleLimit TO 2 * MAX(turnPlannedTime, 30) + 60.
	}
	// How long the first wait goes on for a rotation that does not settle, counted from the first time that the ship was aligned. A ship with
	// little control authority can keep rotating slowly through the target for minutes,
	// so that is no reason to wait for the
	// ignition. After this time the wait ends if the ship is within 5 times the pointing error, whatever its rotation.
	LOCAL alignGiveUp IS MAX(30, 2 * STEERINGMANAGER:MAXSTOPPINGTIME).
	IF NOT abortRequested SET globalSteer TO turnVector.						// (not for a stop: with the node gone the vector is a zero vector)
	// The rotation monitor (library.ks) keeps a history of the pointing error and the pitch and yaw rate from now on, including while the
	// solver runs (abortOrSample), so that the wait for the ship to settle knows how it has been rotating (no log file: "")
	startRotationMonitor(turnVector, TIME:SECONDS + nodeETA(), turnStartUT, "", pointingError).
	IF NOT suppressPrinting {
		IF turnKnown {
			PRINT "Turn: " + ROUND(turnAngle, 1) + " deg, planned " + timeToString(turnPlannedTime, 1) + ", " + timeToString(MAX(nodeETA() - t_ign, 0), 1) + " before the ignition".
			IF debug PRINT "Turn: ideal time " + timeToString(turnIdealTime, 1).
			IF turnPlannedTime > nodeETA() - t_ign PRINT "WARNING: the turn is planned to take longer than the time before the ignition".
		} ELSE PRINT "Turn: " + ROUND(turnAngle, 1) + " deg, the ship's turn rate is not known".
	}

	// The burn solver (librarySolvers.ks, loaded by loop) simulates the burn and finds the ignition shift (later than the delta V centered
	// ignition time) and the two tilts of the thrust (away from the remaining delta V direction: toward the local vertical, and
	// sideways from that) that put the orbit on the node's orbit. A long burn covers a lot of orbit, which NEXTNODE:DELTAV cannot see,
	// and a burn that starts at the delta V centered time with the thrust along the remaining delta V misses the node's orbit.
	// It simulates every stage that the burn uses (thrust, mass flow and mass of each, the mass that is dropped, and the time with no
	// thrust at each staging). It runs only when the burn is at least solverMinBurn long (the offset grows quickly with the burn
	// time, so a short burn is not worth the simulations), and at least solverMinTime is left before the
	// ignition. If it has not converged after its planned iterations and 120 s or more are left before the ignition, it goes on for
	// up to as many iterations again, and then the best result found is used. When it does not run (a short burn, too little time,
	// or useBurnSolver FALSE) the burn has: ignition at the delta V centered time, thrust at the
	// remaining delta V.
	LOCAL useBurnSolver IS TRUE.
	LOCAL solverMinTime IS 120.													// the least time (s) before the ignition that the solver is started with
	LOCAL solverMinBurn IS 30.												// the solver is skipped for burns shorter than this (s)
	LOCAL ignitionShift IS 0.													// s later than the delta V centered ignition time
	LOCAL steerTilt IS 0.														// rad, thrust tilted from the remaining delta V toward the local vertical
	LOCAL steerTilt2 IS 0.														// rad, thrust tilted sideways from that (see burnSteering)
	// The snapshot of the node that the solver starts from is relative to the patch of the flight plan that the node is on, which is around
	// another body when the ship will change sphere of influence before the node (nodeOrbitSnapshot). The solver is skipped, and the shift
	// and tilts stay 0, if the burn is not all on that patch, or if the position and velocity at the node do not agree with its orbit.
	// A long burn makes a long simulation (its step grows with the burn time, see burnSolveSpec), so the solver is also skipped if it would
	// not be done well before the ignition: it has to finish in two thirds of the time that is left (solverTimeEstimate).
	LOCAL solverSnapshot IS LEXICON().
	LOCAL solverSpec IS LEXICON().
	LOCAL solverSkip IS "None".
	LOCAL solverReport IS LIST().												// lines for Maneuver.csv about what the solver predicted for the end of the burn
	LOCAL solverUsed IS FALSE.													// whether the solver's shift and tilts are used for the burn
	IF NOT useBurnSolver SET solverSkip TO "it is turned off".
	ELSE IF abortRequested SET solverSkip TO "the script was stopped".
	ELSE IF t_total < solverMinBurn SET solverSkip TO "the burn is " + ROUND(t_total, 1) + " s, under " + solverMinBurn + " s".
	ELSE IF nodeETA() - t_ign <= solverMinTime SET solverSkip TO "only " + ROUND(nodeETA() - t_ign) + " s before the ignition, under " + solverMinTime + " s".
	ELSE {
		SET solverSnapshot TO orbitSnapshot.
		SET solverSkip TO burnSnapshotError(solverSnapshot, t_ign, t_total).
		IF solverSkip = "None" {
			LOCAL solverOptions IS LEXICON("ignitionLead", t_ign, "taperTime", taperTime, "finishDv", finishDv, "abort", executeStopOrSample@, "stages", burnStageList(usedStages, lowestUsedStage, highestUsedStage, stageReactionTime, stageCommandTime)).
			SET solverSpec TO burnSolveSpec(solverSnapshot, nodeDeltaV(), usedStages[lowestUsedStage]["Thrust"], usedStages[lowestUsedStage]["mDot"], usedStages[lowestUsedStage]["CurrentMass"], solverOptions).
			LOCAL solverTime IS solverTimeEstimate(solverSpec).
			IF nodeETA() - t_ign < 1.5 * solverTime SET solverSkip TO "it needs about " + ROUND(solverTime) + " s and the ignition is " + ROUND(nodeETA() - t_ign) + " s away".
		}
	}
	IF solverSkip <> "None" AND NOT suppressPrinting PRINT "Burn solver and burn altitude check skipped: " + solverSkip.
	IF solverSpec:LENGTH > 0 AND solverSkip = "None" {
		IF NOT suppressPrinting PRINT "Burn solver running".
		LOCAL solution IS solveBurnCorrection(solverSpec, TIME:SECONDS + nodeETA() - t_ign).
		// an aborted solver has results that mean nothing
		IF NOT abortRequested {
			// and so can a result that did not finish the burn, did not get close to the node's orbit, or has numbers that a burn does not need.
			// The shift and tilts are then left at 0, as they are when the solver does not run.
			LOCAL solverRejection IS solverResultError(solution, solverSpec, t_total).
			// What the solver's simulated burn ends with, compared with the node's orbit, to check it against the orbit that the burn really
			// made (the same comparison, "actual minus predicted", is at the end of BurnLog.csv): the semi-major axis and eccentricity of the
			// orbit from the simulated end state, and its position and velocity errors against the node's state at the evaluation time.
			LOCAL simBurn IS solution["burn"].
			LOCAL simPosition IS simBurn["position"].
			LOCAL simVelocity IS simBurn["velocity"].
			LOCAL simMu IS solverSpec["mu"].
			LOCAL simSMA IS 1 / (2 / simPosition:MAG - simVelocity:SQRMAGNITUDE / simMu).
			LOCAL simEccentricity IS ((simPosition * (simVelocity:SQRMAGNITUDE - simMu / simPosition:MAG) - simVelocity * VDOT(simPosition, simVelocity)) / simMu):MAG.
			LOCAL simNodeState IS solverSpec["predicted"].
			solverReport:ADD("solver result used," + (solverRejection = "None") + "," + solverRejection).
			solverReport:ADD("solver simulated end SMA minus node orbit SMA," + (simSMA - orbitSnapshot["Predicted"]["sma"]) + ",m").
			solverReport:ADD("solver simulated end eccentricity minus node orbit," + (simEccentricity - orbitSnapshot["Predicted"]["ecc"])).
			solverReport:ADD("solver simulated end position error and velocity error," + (simPosition - simNodeState[0]):MAG + "," + (simVelocity - simNodeState[1]):MAG + ",m and m/s").
			solverReport:ADD("solver miss (position + 1000 x velocity) and at the guess," + solution["miss"] + "," + solution["startMiss"] + ",m").
			solverReport:ADD("solver iterations, converged, time," + solution["iterations"] + "," + solution["converged"] + "," + ROUND(solution["seconds"], 1) + ",s").
			solverReport:ADD("solver simulated burn time and end reason," + simBurn["burnTime"] + "," + simBurn["endReason"] + ",s").
			// The guard: where the simulated burn goes lowest. This is a check of the plan, made before the ignition (the stop is the same as the
			// abort key before the burn: the burn is skipped), not an abort of a burn that is under way. A burn that is a large part of an orbit and
			// is held at a fixed direction pushes the ship down early in the burn, and should be split into passes (the burn planner). It does not
			// apply to a ship whose orbit already goes into the atmosphere (or the surface) before the node, which is a deliberate burn (a landing
			// or an aerobraking burn). Only the burn itself is simulated, not the orbit after it.
			LOCAL guardBody IS solverSnapshot["Body"].
			LOCAL lowestAltitude IS simBurn["lowestRadius"] - guardBody:RADIUS.
			LOCAL guardHeight IS 0.
			IF guardBody:ATM:EXISTS SET guardHeight TO guardBody:ATM:HEIGHT.
			LOCAL oldPeriapsisAltitude IS solverSnapshot["Old"]["sma"] * (1 - solverSnapshot["Old"]["ecc"]) - guardBody:RADIUS.
			solverReport:ADD("solver simulated lowest altitude during the burn and the atmosphere height," + lowestAltitude + "," + guardHeight + ",m").
			IF lowestAltitude < guardHeight AND oldPeriapsisAltitude >= guardHeight {
				LOCAL guardText IS "the burn is predicted to go down to " + ROUND(lowestAltitude / 1000, 1) + " km altitude (inside the " + ROUND(guardHeight / 1000, 1) + " km atmosphere)".
				IF lowestAltitude < 0 SET guardText TO "the burn is predicted to hit the surface of " + guardBody:NAME.
				ELSE IF guardHeight <= 0 SET guardText TO "the burn is predicted to go below the surface of " + guardBody:NAME.
				SET abortNote TO guardText + "; split it into passes".
				SET abortRequested TO TRUE.
				solverReport:ADD("burn not started," + abortNote).
				IF NOT suppressPrinting PRINT "Burn not started: " + abortNote.
			}
			IF NOT abortRequested AND NOT suppressPrinting {
				IF lowestAltitude < guardHeight PRINT "Burn altitude check: not applied, the orbit already goes into the atmosphere".
				ELSE PRINT "Burn altitude check: passed, lowest point " + ROUND(lowestAltitude / 1000, 1) + " km".
			}
			IF solverRejection = "None" {
				IF NOT suppressPrinting PRINT "Burn solver result: used".
				SET solverUsed TO TRUE.
				SET ignitionShift TO solution["shift"].
				SET t_ign TO t_ign - ignitionShift.								// a smaller delay means a later ignition
				SET steerTilt TO solution["tilt"].
				SET steerTilt2 TO solution["tilt2"].
			} ELSE IF NOT suppressPrinting PRINT "Burn solver result not used: " + solverRejection.
			IF debug AND NOT suppressPrinting {
				PRINT "Burn solver: shift " + ROUND(solution["shift"], 2) + " s, tilts " + ROUND(solution["tilt"] * CONSTANT:RADTODEG, 3) + " and " + ROUND(solution["tilt2"] * CONSTANT:RADTODEG, 3) + " deg, miss " + ROUND(solution["miss"], 0) + " m (" + ROUND(solution["startMiss"], 0) + " m before), " + solution["iterations"] + " iterations, " + ROUND(solution["seconds"], 1) + " s".
				IF NOT solution["converged"] PRINT "Burn solver did not converge, using the best result found".
			}
		}
	}

	SET turnAngleAfterSolver TO VANG(SHIP:FACING:VECTOR, turnVector).						// how far the turn got while the solver was running

	IF connectionToKSC() {
		LOCAL logMe IS LIST().
		logMe:ADD(SHIP:NAME + ",").					// 0
		logMe:ADD("Isp,").							// 1
		logMe:ADD("T,").							// 2
		logMe:ADD("m_dry,").						// 3
		logMe:ADD("m_wet,").						// 4
		logMe:ADD("v_e,").							// 5
		logMe:ADD("dV_avail,").						// 6
		logMe:ADD("m_dot,").						// 7
		logMe:ADD("dv_prev,").						// 8
		logMe:ADD("dV_req_stage,").					// 9
		logMe:ADD("ign_after_t_0,").				// 10
		logMe:ADD("dV_before_t_0,").				// 11
		logMe:ADD("t_burn_req,").					// 12
		logMe:ADD("thrust limit (highest engine)," + ROUND(limitFraction * 100, 1) + ",%").
		logMe:ADD("taperTime," + taperTime + ",s").
		logMe:ADD("finishDv," + finishDv + ",m/s").
		logMe:ADD("t_total," + t_total + ",s").
		logMe:ADD("t_ign," + t_ign + ",s").
		IF solverSkip <> "None" solverReport:ADD("solver skipped," + solverSkip).
		ELSE IF solverReport:LENGTH = 0 solverReport:ADD("solver not run").
		FOR solverLine IN solverReport logMe:ADD(solverLine).
		logMe:ADD("ignitionShift," + ignitionShift + ",s").
		logMe:ADD("steerTilt," + steerTilt + ",rad").
		logMe:ADD("steerTilt2," + steerTilt2 + ",rad").
		logMe:ADD("highestUsedStage," + highestUsedStage).
		logMe:ADD("lowestUsedStage," + lowestUsedStage).
		logMe:ADD("usedStages:LENGTH,"+ usedStages:LENGTH).
		logMe:ADD("a_i," + a_i + ",m/s^2").
		logMe:ADD("a_f," + a_f + ",m/s^2").
		logMe:ADD("dV_req," + dV_req + ",m/s").
		FOR stageNumber IN RANGE(usedStages:LENGTH - 1, -1) {
			SET logMe[0] TO logMe[0] + "Stage " + stageNumber + ",".
			SET logMe[1] TO logMe[1] + Isp_stg[stageNumber] + ",".
			SET logMe[2] TO logMe[2] + T_stg[stageNumber] + ",".
			SET logMe[3] TO logMe[3] + m_dry_stg[stageNumber] + ",".
			SET logMe[4] TO logMe[4] + m_wet_stg[stageNumber] + ",".
			SET logMe[5] TO logMe[5] + v_e_stg[stageNumber] + ",".
			SET logMe[6] TO logMe[6] + dV_avail_stg[stageNumber] + ",".
			SET logMe[7] TO logMe[7] + m_dot_stg[stageNumber] + ",".
			SET logMe[8] TO logMe[8] + dv_prev_stg[stageNumber] + ",".
			SET logMe[9] TO logMe[9] + dV_req_stage_stg[stageNumber] + ",".
			SET logMe[10] TO logMe[10] + ign_after_t_0_stg[stageNumber] + ",".
			SET logMe[11] TO logMe[11] + dV_before_t_0_stg[stageNumber] + ",".
			SET logMe[12] TO logMe[12] + t_burn_req_stg[stageNumber] + ",".
		}
		SET logMe[1] TO logMe[1] + "s,".
		SET logMe[2] TO logMe[2] + "N,".
		SET logMe[3] TO logMe[3] + "kg,".
		SET logMe[4] TO logMe[4] + "kg,".
		SET logMe[5] TO logMe[5] + "m/s,".
		SET logMe[6] TO logMe[6] + "m/s,".
		SET logMe[7] TO logMe[7] + "kg/s,".
		SET logMe[8] TO logMe[8] + "m/s,".
		SET logMe[9] TO logMe[9] + "m/s,".
		SET logMe[11] TO logMe[11] + "m/s,".
		SET logMe[12] TO logMe[12] + "s,".
		FOR message IN logMe {
			LOG message TO "0:Maneuver.csv".
		}
	}

	// print out the parameters of the rocket - thrust, m_0, m_f, m_part, Isp and mDot
	IF debug AND NOT suppressPrinting {
		PRINT "Node in: " + timeToString(nodeETA()) + ", DeltaV: " + distanceToString(nodeDeltaV():MAG, 3) + "/s".
		PRINT "Stage  m_dry  m_wet   v_e  dV_avail  m_dot  dv_Prev  dv_Req  t_burn".
		PRINT "          kg     kg   m/s       m/s   kg/s      m/s     m/s       s".
		FOR stageNumber IN RANGE(usedStages:LENGTH - 1, -1) {
			PRINT stageNumber:TOSTRING:PADLEFT(5) + ROUND(m_dry_stg[stageNumber], 0):TOSTRING:PADLEFT(7) + ROUND(m_wet_stg[stageNumber], 0):TOSTRING:PADLEFT(7) + ROUND(v_e_stg[stageNumber], 0):TOSTRING:PADLEFT(6) + ROUND(dV_avail_stg[stageNumber], 0):TOSTRING:PADLEFT(10) + ROUND(m_dot_stg[stageNumber], 1):TOSTRING:PADLEFT(7) + ROUND(dv_Prev_stg[stageNumber], 0):TOSTRING:PADLEFT(9) + ROUND(dV_req_stage_stg[stageNumber], 0):TOSTRING:PADLEFT(8) + ROUND(t_burn_req_stg[stageNumber], 2):TOSTRING:PADLEFT(8).
		}
		PRINT "Burn Delay, " + timeToString(t_ign, 2).
		PRINT "Total Burntime, " + timeToString(t_total, 2).
		PRINT "initial accel " + distanceToString(a_i, 2 ) + "/s^2   final accel " + distanceToString(a_f, 2) + "/s^2".
	} ELSE {
		IF NOT suppressPrinting {
			PRINT "Running Execute Next Node".
			IF useRCSforRotation PRINT "Will use RCS for rotation".
			ELSE PRINT "Will not use RCS for rotation".
			IF ullage <> 0 PRINT "Will fire RCS for " + ullage + " seconds for ullage".
			ELSE PRINT "Will not fire RCS for ullage".
			IF faceSun PRINT "Will turn to face the Sun".
			ELSE PRINT "Will not turn to face the Sun".
			PRINT "Burn duration: " + timeToString(t_total , 2).
		}
	}

	// if called to face the sun and the node is more than 60 minutes away, turn to face the primary.
	// turn on physics warp for the rotation if allowed
	IF physicsWarpLevel {
		SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
		SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpLevel.
	}
	IF turnToSun {
		LOCAL faceBody IS BODY("Sun").
		IF debug AND NOT suppressPrinting PRINT "Aligning with the Sun. Burn ETA: " + timeToString(nodeETA() - t_ign , 2).
		SET globalSteer TO faceBody:POSITION.
	} ELSE {
		IF NOT abortRequested SET globalSteer TO nodeDeltaV().
		IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node. Burn ETA: " + timeToString(nodeETA() - t_ign , 2).
	}

	// Now wait until the ship's facing is aligned with the burn vector (or the Sun) and it has stopped rotating. The wait ends when
	//   "aligned"       - (stock only, see below) the ship is within railsAlignError,
	//   "settled"       - the ship is within the pointing error now and, for the whole of the last alignWindow s (rotationSettled, which has
	//                     been watching since the turn started, solver included), its pitch and yaw rate was under settledRate and its
	//                     pointing error under twice the pointing error. The roll about the ship's axis does not count (see the rotation
	//                     monitor in library.ks), and one reading does not either, since a ship with little control authority oscillates,
	//   "gave up"       - alignGiveUp has passed since the ship was first within the pointing error, and it is within 5 times it,
	//   "ignition time" - it is time to ignite (the ship is then not aligned and settled),
	//   "aborted"       - the abort key.
	// The window is about a cycle of the slow oscillation of a ship with little control authority and
	// shorter for a ship that turns quickly. A time warp that was started by hand is ended in time for the ignition.
	// In stock the warp on rails freezes the ship's rotation, so there is nothing to wait for: the wait ends as soon as the ship is within
	// railsAlignError of the target ("aligned"), however it is rotating, and the second alignment before the ignition corrects what is left.
	// With PersistentRotation (which RealFuels installations almost always have) the rotation goes on through the warp, so they wait for it
	// to settle. isStock() is what tells them apart here, as everywhere in this script.
	LOCAL stockShip IS isStock().
	LOCAL railsAlignError IS 3.													// deg
	LOCAL alignWindow IS MAX(10, MIN(30, 10 + STEERINGMANAGER:MAXSTOPPINGTIME / 2)).
	LOCAL alignFirstUT IS -1.													// UT when the ship was first within the pointing error
	LOCAL alignEnd IS "waiting".
	UNTIL alignEnd <> "waiting" {
		sampleRotation().
		LOCAL alignVector IS nodeDeltaV().
		IF turnToSun SET alignVector TO BODY("Sun"):POSITION.
		LOCAL alignError IS VANG(SHIP:FACING:VECTOR, alignVector).
		LOCAL alignNow IS TIME:SECONDS.
		SET alignFirstUT TO rotationMonitor["FirstAligned"].						// seen by the monitor, which was watching during the solver too
		IF executeStop() SET alignEnd TO "aborted".					// first: with the node gone the vectors and times below are fallbacks
		ELSE IF stockShip AND alignError < railsAlignError SET alignEnd TO "aligned".
		ELSE IF alignError < pointingError AND rotationSettled(alignWindow, settledRate, 2 * pointingError) SET alignEnd TO "settled".
		ELSE IF alignFirstUT >= 0 AND alignNow - alignFirstUT >= alignGiveUp AND alignError < 5 * pointingError SET alignEnd TO "gave up".
		ELSE IF nodeETA() <= t_ign + ullage SET alignEnd TO "ignition time".

		IF alignEnd = "waiting" {
			stopWarpBefore(nodeETA() - t_ign).
			WAIT 0.
		}
	}
	stopRotationMonitor().
	LOCAL firstAlignedAfter IS -1.												// s from the start of the turn to the ship first being within the pointing error
	IF alignFirstUT >= 0 SET firstAlignedAfter TO alignFirstUT - turnStartUT.
	IF VANG(SHIP:FACING:VECTOR, globalSteer) < pointingError SET turnAlignedAfter TO TIME:SECONDS - turnStartUT.
	LOCAL rateAtAlignment IS SHIP:ANGULARVEL:MAG.								// rad/s (all of it, the roll too) when the first wait ended, for Maneuver.csv
	LOCAL turnRateAtAlignment IS VXCL(SHIP:FACING:FOREVECTOR, SHIP:ANGULARVEL):MAG.	// the same without the roll about the ship's axis
	IF NOT suppressPrinting {
		IF alignEnd = "aligned" OR alignEnd = "settled" PRINT "Aligned with the burn direction (" + alignEnd + ")".
		IF alignEnd = "gave up" PRINT "The rotation (" + ROUND(rateAtAlignment * CONSTANT:RADTODEG, 3) + " deg/s) did not fall under " + ROUND(settledRate * CONSTANT:RADTODEG, 3) + " deg/s in " + ROUND(alignGiveUp) + " s of being aligned, going on".
		IF alignEnd = "ignition time" PRINT "WARNING: the ship was not aligned and settled by the ignition time (" + ROUND(VANG(SHIP:FACING:VECTOR, globalSteer), 2) + " deg off, " + ROUND(rateAtAlignment * CONSTANT:RADTODEG, 3) + " deg/s)".
	}

	// if the node is more than 5 minutes away, pause to allow all roll rotation to be damped out: until the rotation is under dampRate
	// (see settledRate), or for twice the steering manager's stopping time, which is how long it takes to stop from the fastest rate,
	// and is all that is waited when the ship's turn rate is not known
	// (not in stock: the warp freezes the rotation, see the first wait)
	IF nodeETA() > 5*60 AND NOT stockShip {
		LOCAL dampStart IS TIME:SECONDS.
		LOCAL dampLimit IS STEERINGMANAGER:MAXSTOPPINGTIME * 2.
		// (the pitch and yaw rate, as for the first wait: a roll about the ship's axis that the steering does not remove would keep this
		// wait to its time limit, and a ship that oscillates slowly passes the limit when its rate is near zero, the moment to go on rails)
		WAIT UNTIL (TIME:SECONDS - dampStart >= dampLimit) OR (dampRate > 0 AND VXCL(SHIP:FACING:FOREVECTOR, SHIP:ANGULARVEL):MAG < dampRate) OR executeStop().
	}
	// The time that the second alignment (just before the burn) is given, which sets how long before the ignition the warp on rails ends,
	// and so how long the rest is waited at normal speed or in physics warp. The angle that it has to turn is not 180 degrees: it is what the
	// ship may have moved by then, which is twice the pointing error that it has now (at least 5 degrees), and, where the rotation goes on
	// through the warp (PersistentRotation, see the first wait), what its rotation takes it through in the time until the ignition.
	// (A larger allowance ends the warp on rails earlier, which leaves more of the wait to be spent at a slower warp.)
	LOCAL reTurnAngle IS 180.													// deg, 180 when the ship's turn rate is not known
	IF turnKnown {
		SET reTurnAngle TO MAX(2 * VANG(SHIP:FACING:VECTOR, nodeDeltaV()), 5).
		IF NOT stockShip SET reTurnAngle TO reTurnAngle + VXCL(SHIP:FACING:FOREVECTOR, SHIP:ANGULARVEL):MAG * CONSTANT:RADTODEG * MAX(nodeETA() - t_ign, 0).
		SET reTurnAngle TO MIN(reTurnAngle, 180).
		SET turnLead TO turnTimeFor(rotationInfo["Accel"], rotationInfo["StoppingTime"], reTurnAngle) * turnMargin + turnSettle.
	}
	// The burn is prepared (the logs, the orbit snapshot, the energy target) prepTime seconds before the ignition, at normal speed, and then the
	// script waits for the ignition itself, so that nothing but the wait is left to do when the time comes. Any warp, rails or physics, is
	// ended before that (stopWarpBefore: physics warp 10 s before the ignition, rails more according to its rate). Work that is
	// done after the wait delays the ignition, and a late ignition shifts the orbit that the burn makes.
	LOCAL prepTime IS 3.
	// always turn off physics warp
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
	SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

	// if ullage is not a concern, warp to 30 seconds before burntime, or earlier if the turn to the burn direction (up to 180 degrees,
	// since the burn direction has moved while the ship waited) needs more time than that before the ignition
	IF (isStock() OR (ullage = 0)) {
		warpToTime(TIME:SECONDS + nodeETA() - MAX(MAX(1.5*t_ign, 30), t_ign + turnLead), executeStop@).
		IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node (again). Burn ETA: " + timeToString(nodeETA() - t_ign, 2).
		IF NOT abortRequested SET globalSteer TO nodeDeltaV().
		IF physicsWarpLevel {
			SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
			SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpLevel.
		}
		// when turned to face the Sun, the ship now has to turn back to the burn direction before the burn starts
		// (a warp that was started by hand is ended in time for the ignition, in this wait and the next: stopWarpBefore)
		LOCAL returnDeadline IS TIME:SECONDS + settleLimit.
		IF faceSun {
			UNTIL (VANG(FACING:VECTOR, nodeDeltaV()) < pointingError AND (SHIP:ANGULARVEL:MAG < settledRate OR TIME:SECONDS >= returnDeadline)) OR (nodeETA() <= t_ign + prepTime) OR executeStop() {
				stopWarpBefore(nodeETA() - t_ign).
				WAIT 0.
			}
		}
		UNTIL (nodeETA() <= t_ign + prepTime) OR executeStop() {
			stopWarpBefore(nodeETA() - t_ign).
			WAIT 0.
		}
	} ELSE {
	// if ullage is a concern, warp to MAX(90, ullage) seconds before burntime (more if the turn needs it)
		LOCAL ullageWarpLead IS MAX(MAX(90, ullage), turnLead).
		IF debug AND NOT suppressPrinting PRINT "Warping to " + timeToString(nodeETA() - t_ign - ullageWarpLead, 2).
		warpToTime(TIME:SECONDS + nodeETA() - t_ign - ullageWarpLead, executeStop@).

		IF faceSun {
			IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node. Burn ETA: " + timeToString(nodeETA() - t_ign, 2).
			IF NOT abortRequested SET globalSteer TO nodeDeltaV().
		} ELSE {IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node (again). Burn ETA: " + timeToString(nodeETA() - t_ign, 2).}

		IF physicsWarpLevel {
			SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
			SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpLevel.
		}
		//now we need to wait until the burn vector and ship's facing are aligned
		// (the ullage starts a second earlier than it needs to, and the burn is prepared after this wait, so that the RCS is not started
		// until the preparation is done and still fires for the whole ullage time)
		UNTIL ((nodeETA() <= t_ign + ullage + 1) OR (VANG(FACING:VECTOR, nodeDeltaV()) < pointingError)) OR executeStop() {
			stopWarpBefore(nodeETA() - t_ign - ullage - 1).						// a warp started by hand is ended in time for the ullage
			WAIT 0.
		}

		IF debug AND NOT suppressPrinting PRINT "Waiting until the ullage time, " + timeToString(nodeETA() - t_ign - ullage - 1).
		warpToTime(TIME:SECONDS + nodeETA() - t_ign - ullage - 1, executeStop@).
		// the ullage itself, and the wait for the ignition, are below, after the preparation of the burn
	}

	// The engines do nothing on rails, and the game runs fast while a warp comes down, and a physics warp makes the time to the ignition
	// coarse. If any warp is still running now (stopWarpBefore only ends it when it is asked in time), end it and wait for the normal speed
	// before the burn is prepared. (Physics warp for the burn itself is started at the ignition, below.)
	IF KUNIVERSE:TIMEWARP:RATE > 1 {
		SET KUNIVERSE:TIMEWARP:WARP TO 0.
		LOCAL warpWaitStart IS KUNIVERSE:REALTIME.
		WAIT UNTIL KUNIVERSE:TIMEWARP:RATE = 1 OR KUNIVERSE:REALTIME - warpWaitStart > 5.
		IF NOT suppressPrinting PRINT "WARNING: the ship was still warping when the burn was prepared".
	}

	LOCAL maxStages IS 20.
	LOCAL executedStages IS 0.
	LOCAL done TO abortRequested.										// aborted before the burn: the burn loop is skipped
	//initial deltav
	LOCAL DV0 TO nodeDeltaV().
	SET globalThrottle TO 0.
	setLockedThrottle(TRUE).
	LOCAL resetWarp IS FALSE.

	executeStop().													// notices a node that is gone, which the log reads below
	// Burn motion log, for analysing how the ship moves during the burn (see burnFrame in library.ks for the frame used)
	LOCAL burnLogging IS connectionToKSC() AND NOT abortRequested.			// no burn log for a script that was aborted before the burn
	LOCAL burnLogFile IS "0:BurnLog.csv".								// the same file every run: the log of the last run is replaced
	IF burnLogging AND EXISTS(burnLogFile) DELETEPATH(burnLogFile).
	LOCAL burnLogInterval IS 0.1.										// minimum time between samples (s)
	LOCAL postBurnLogTime IS 3.											// how long to keep logging after the throttle is cut (s)
	LOCAL burnLogBuffer IS LIST().
	LOCAL lastLogUT IS 0.
	LOCAL lastTickUT IS TIME:SECONDS.
	LOCAL dvThrustEst IS 0.
	LOCAL burnLogFrame IS burnFrame().
	// the header is only put in the buffer, and is written with the first samples, so that no file writing delays the ignition
	IF burnLogging FOR headerLine IN burnLogHeader(burnLogFrame, NEXTNODE, DV0, t_total) burnLogBuffer:ADD(headerLine).

	LOCAL steerHoldDv IS 1.0.												// below this remaining delta V, the steering is held (m/s)
	LOCAL steerVector IS DV0.
	LOCAL thrustSeen IS FALSE.												// whether the engines of the current stage have been seen producing thrust
	LOCAL burnStartTime IS MISSIONTIME.										// when the burn loop starts (s), for the duration in Maneuver.csv
	LOCAL burnEndTime IS burnStartTime.
	LOCAL lastThrustUT IS TIME:SECONDS.										// the last time that the engines were seen thrusting
	LOCAL stageGapStart IS -1.												// when the thrust stopped for the staging in progress, -1 if none
	LOCAL stageGaps IS LIST().												// the measured time with no thrust at each staging (s)

	// Energy cutoff. The remaining delta V that the node reports is a velocity difference at the node time, so it also contains the
	// position (phase) error of the finite burn and does not go to zero when the orbit is right. The orbit energy
	// can reach the node's value while some delta V still shows as remaining, and burning the rest of it
	// leaves the orbit too big. So in the last energyPhaseDv of the burn, the burn
	// ends as soon as the orbit energy crosses the energy of the node's orbit. The side it starts from tells which way to cross.
	// Not when the solver's result is used: the solver simulates the whole burn, phase error included, and its thrust direction and ignition
	// time already put the orbit on the node's. The orbit energy of a long, low thrust burn swings a long way from the node's value in the
	// middle of it (a plane change), and crosses it before the burn is done, so the cutoff would end such a burn early.
	LOCAL energyCutoff IS NOT solverUsed.									// FALSE ends the burn on the remaining delta V only
	LOCAL energyPhaseDv IS 20.												// the energy test is only used when less than this is left (m/s)
	LOCAL energyMinError IS 20.												// an energy error smaller than this (J/kg, about 0.01 m/s) is noise
	LOCAL bodyMu IS SHIP:BODY:MU.
	LOCAL energyTarget IS -bodyMu / (2 * orbitSnapshot["Predicted"]["sma"]).	// specific orbital energy of the node's orbit (J/kg)
	LOCAL energySide IS 0.													// side of the target energy at the start of the last phase: 1 above, -1 below, 0 not known
	LOCAL endReason IS "remaining delta V".
	IF abortRequested SET endReason TO stopReason().

	// The ullage (RealFuels, see the parameter ullage): the RCS fires forward until the ignition, and is turned off when the engines start.
	LOCAL ullageRCS IS (NOT (isStock() OR ullage = 0)) AND ullage <> 0 AND NOT abortRequested.
	IF ullageRCS {
		RCS ON.
		SET SHIP:CONTROL:FORE TO 1.0.
		IF debug AND NOT suppressPrinting PRINT "Ullage starting, " + timeToString(nodeETA() - t_ign) + " before the ignition".
	}
	// Now wait for the ignition at normal speed, with nothing else to do, and light the engines in the same pass that finds the time: the
	// throttle is set here, not by the burn loop, which would start them one pass of its own later.
	UNTIL (nodeETA() <= t_ign) OR executeStop() {
		WAIT 0.
	}
	IF ullageRCS {
		RCS OFF.
		SET SHIP:CONTROL:FORE TO 0.0.
		IF debug AND NOT suppressPrinting PRINT "Ullage over, main engines starting".
	}
	IF abortRequested {
		SET done TO TRUE.
		SET endReason TO stopReason().
	} ELSE {
		setBurnThrottle(1).
		SET burnStartTime TO MISSIONTIME.
		SET lastTickUT TO TIME:SECONDS.
		SET lastThrustUT TO TIME:SECONDS.
		IF NOT suppressPrinting PRINT "Ignition, " + ROUND(t_ign - nodeETA(), 2) + " s after the planned time".
		IF physicsWarpLevel AND t_total > 30 {									// only actually use physics warp if the burn duration is greater than 30 seconds
			SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
			SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpLevel.
		}
	}

	UNTIL done
	{
		// the abort check comes first, and the staging below is skipped once it is pressed. The throttle is cut at the end of this iteration.
		IF executeStop() {
			SET done TO TRUE.
			SET endReason TO stopReason().
		}
		LOCAL remaining IS nodeDeltaV().
		// Once little is left, the direction of the remaining delta V is dominated by small sideways residuals and can swing
		// quickly, so the last good direction is held instead of chasing it.
		IF remaining:MAG > steerHoldDv SET steerVector TO remaining.
		IF steerTilt = 0 AND steerTilt2 = 0 {
			SET globalSteer TO steerVector.
		} ELSE {
			// the same steering that the solver simulated (burnSteering, librarySolvers.ks)
			SET globalSteer TO burnSteering(-SHIP:BODY:POSITION, steerVector, steerTilt, steerTilt2) * steerVector:MAG.
		}
		// the mass and the resources change as the burn goes on. The engines' thrust (shipInfo["Maximum"]) is refreshed whenever the
		// ship stages, since that runs updateShipInfo. For an RCS burn the thrust is that of the forward thrusters that was planned (they
		// do not stage) and the mass is the ship's.
		LOCAL shipMass IS SHIP:MASS * 1000.									// the mass of the whole ship (kg)
		LOCAL burnThrust IS usedStages[0]["Thrust"].							// N
		IF NOT burnWithRCS {
			updateShipInfoResources(FALSE).
			SET shipMass TO shipInfo["CurrentStage"]["CurrentMass"].
			SET burnThrust TO shipInfo["Maximum"]["Thrust"].
		}

		LOCAL nowUT IS TIME:SECONDS.
		LOCAL tickTime IS MAX(nowUT - lastTickUT, 0.02).
		SET dvThrustEst TO dvThrustEst + burnLevel * burnThrust / shipMass * (nowUT - lastTickUT).
		SET lastTickUT TO nowUT.
		IF burnLogging AND HASNODE AND nowUT - lastLogUT >= burnLogInterval {		// (the sample reads the node itself)
			burnLogBuffer:ADD(burnLogSample(burnLogFrame, NEXTNODE, burnLevel, dvThrustEst, orbitSnapshot)).
			SET lastLogUT TO nowUT.
			burnLogFlush(burnLogFile, burnLogBuffer).
		}
		// Drop the stage if it is time to (no thrust, a flameout or empty tanks), at most once per iteration. The no thrust and
		// empty tank checks wait until the stage has been seen producing thrust, so that a stage that has not started is not dropped.
		// stageIfNeeded runs updateShipInfo after staging, so shipInfo is current for the new stage. (Not for an RCS burn: no engines.)
		IF NOT burnWithRCS {
			IF burnLevel > 0 AND MAXTHRUST > 0 {
				SET thrustSeen TO TRUE.
				IF stageGapStart >= 0 AND AVAILABLETHRUST > 0 {						// the new stage is thrusting: how long was there no thrust
					stageGaps:ADD(ROUND(nowUT - stageGapStart, 2)).
					SET stageGapStart TO -1.
				}
				IF AVAILABLETHRUST > 0 SET lastThrustUT TO nowUT.
			}
			LOCAL stageReason IS "None".
			IF NOT done SET stageReason TO stageIfNeeded(thrustSeen).
			IF stageReason <> "None" {
				SET executedStages TO executedStages + 1.
				SET thrustSeen TO FALSE.											// the engines of the new stage have to be seen working
				IF stageGapStart < 0 SET stageGapStart TO lastThrustUT.				// a second STAGE command in a row belongs to the same gap
				PRINT "Staging from " + stageReason.
			}
		}

		// the staging above can take a while, so the remaining delta V is read again
		SET remaining TO nodeDeltaV().
		LOCAL remainingMag IS remaining:MAG.
		SET dV_req TO remaining.

		// the acceleration at full throttle now (N / kg = m/s^2), which is right after any staging, and the time left at full throttle
		LOCAL thrustAccel IS burnThrust / shipMass.
		LOCAL burnThrottleable IS TRUE.
		LOCAL burnMinThrottle IS 0.
		IF NOT burnWithRCS {
			SET thrustAccel TO shipInfo["Maximum"]["Thrust"] / shipInfo["CurrentStage"]["CurrentMass"].
			SET burnThrottleable TO shipInfo["CurrentStage"]["Throttleable"].
			SET burnMinThrottle TO shipInfo["CurrentStage"]["HighestMinThrottle"].
		}
		LOCAL timeToGo IS 9999.
		IF thrustAccel > 0 SET timeToGo TO remainingMag / thrustAccel.

		// stop physics warp a few seconds before the end, so that the iteration time is steady for the end of the burn
		IF NOT resetWarp AND timeToGo <= 3 {
			SET KUNIVERSE:TIMEWARP:WARP TO 0.
			SET resetWarp TO TRUE.
		}

		// cut the throttle as soon as our nd:deltaV and initial deltaV start facing opposite directions, or when it is finished
		IF (VDOT(DV0, remaining) < 0) OR remainingMag < finishDv OR (executedStages >= maxStages) SET done TO TRUE.

		IF energyCutoff AND NOT done AND remainingMag < energyPhaseDv {
			LOCAL shipVelocity IS SHIP:VELOCITY:ORBIT.
			LOCAL energyError IS VDOT(shipVelocity, shipVelocity) / 2 - bodyMu / SHIP:BODY:POSITION:MAG - energyTarget.
			IF energySide = 0 {
				IF energyError > energyMinError SET energySide TO 1.
				ELSE IF energyError < -energyMinError SET energySide TO -1.
			} ELSE IF energyError * energySide <= 0 {
				SET done TO TRUE.
				SET endReason TO "orbit energy reached".
			}
		}

		LOCAL newThrottle IS 1.
		IF NOT done AND burnThrottleable AND timeToGo <= taperTime {
			// proportional taper: the remaining delta V decays exponentially and the throttle never goes back up
			SET newThrottle TO timeToGo / taperTime.
			// Engines have a minimum throttle. Below it, hold the minimum until the thrust in flight (about two iterations,
			// because the delta V reading lags) would use up what is left, and then stop. (RCS thrusters have none.)
			LOCAL throttleFloor IS burnMinThrottle.
			IF newThrottle < throttleFloor {
				IF remainingMag <= throttleFloor * thrustAccel * tickTime * 2 SET done TO TRUE.
				ELSE SET newThrottle TO throttleFloor.
			}
		}

		// The throttle is cut in the same iteration that finds the end, so that there is no more thrust after the end.
		IF done {
			IF debug AND NOT suppressPrinting PRINT "End burn (" + endReason + "), remaining dV " + distanceToString(remainingMag, 1) + "/s, vdot: " + ROUND(VDOT(DV0, remaining),1).
			setBurnThrottle(0).
		} ELSE setBurnThrottle(newThrottle).
		WAIT 0.
	}
	setBurnThrottle(0).
	WAIT 0.
	SET burnEndTime TO MISSIONTIME.

	// keep logging for a few seconds after the throttle is cut, to see where the ship ends up relative to the node (not when aborted:
	// the samples that were taken are written and that is all)
	IF burnLogging AND abortRequested {
		burnLogFlush(burnLogFile, burnLogBuffer, TRUE).
	}
	IF burnLogging AND NOT abortRequested {
		SET KUNIVERSE:TIMEWARP:WARP TO 0.
		SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
		LOCAL postBurnEnd IS TIME:SECONDS + postBurnLogTime.
		UNTIL TIME:SECONDS >= postBurnEnd {
			IF TIME:SECONDS - lastLogUT >= burnLogInterval AND HASNODE {		// (a node that was deleted as soon as the burn ended is not read)
				burnLogBuffer:ADD(burnLogSample(burnLogFrame, NEXTNODE, burnLevel, dvThrustEst, orbitSnapshot)).
				SET lastLogUT TO TIME:SECONDS.
				burnLogFlush(burnLogFile, burnLogBuffer).
			}
			WAIT 0.
		}
		burnLogFlush(burnLogFile, burnLogBuffer, TRUE).
	}

	// Compare the orbit that the burn produced with the orbit that the node predicted, and add that to the end of the burn log
	LOCAL orbitCheck IS nodeOrbitComparison(orbitSnapshot).
	IF burnLogging {
		FOR checkLine IN nodeOrbitCheckLines(orbitCheck) burnLogBuffer:ADD(checkLine).
		burnLogFlush(burnLogFile, burnLogBuffer, TRUE).
	}
	IF debug AND NOT suppressPrinting {
		PRINT "Orbit vs node: inc " + ROUND(orbitCheck["Actual"]["inc"] - orbitCheck["Predicted"]["inc"], 4) + ", LAN " + ROUND(normalizeAngle180(orbitCheck["Actual"]["lan"] - orbitCheck["Predicted"]["lan"]), 4) + " deg, plane angle " + ROUND(orbitCheck["PlaneAngle"], 4) + " deg".
		PRINT "Plane change crossed " + ROUND(orbitCheck["ActualCrossing"], 3) + " deg from the node (" + ROUND(orbitCheck["ActualCrossingTime"], 1) + " s)".
	}

	updateShipInfo().
	LOCAL deltaVLeft IS "".														// what is left of the node's delta V, blank if the node is gone (nothing to read it from)
	IF HASNODE SET deltaVLeft TO ROUND(nodeDeltaV():MAG, 3).
	IF connectionToKSC() {
		LOCAL logMe IS LIST().
		logMe:ADD("actual burn time," + (burnEndTime - burnStartTime) + ",s").		// from the start of the burn loop to the end of the burn
		logMe:ADD("STAGE commands," + executedStages).
		// the turn to the burn direction, to calibrate turnMargin: the planned time is the ideal time (shipInfo["Rotation"]) times the
		// margin plus the settling time. The turn runs while the solver does, so if it was aligned when the solver finished,
		// "turn aligned after" is only an upper bound on the time that it took (and the angle left is 0).
		logMe:ADD("turn angle at start," + ROUND(turnAngle, 3) + ",deg").
		logMe:ADD("turn time ideal (-1 unknown)," + ROUND(turnIdealTime, 2) + ",s").
		logMe:ADD("turn time planned (margin " + turnMargin + ", settle " + turnSettle + ")," + ROUND(turnPlannedTime, 2) + ",s").
		logMe:ADD("turn angle left after the solver," + ROUND(turnAngleAfterSolver, 3) + ",deg").
		logMe:ADD("turn aligned after (-1 not aligned)," + ROUND(turnAlignedAfter, 2) + ",s").
		// how the first wait ended when the ship was first aligned, and the
		// time that it was given to settle after that
		logMe:ADD("alignment wait ended by," + alignEnd).
		logMe:ADD("second alignment: angle allowed for and time given (lead)," + ROUND(reTurnAngle, 1) + "," + ROUND(turnLead, 1) + ",deg and s").
		logMe:ADD("ullage check," + ullageStatus).
		logMe:ADD("first aligned after (-1 never), give up time," + ROUND(firstAlignedAfter, 2) + "," + ROUND(alignGiveUp, 1) + ",s").
		logMe:ADD("rotation rate when the first wait ended (total, without the roll), settled and damped limits (on the rate without the roll)," + ROUND(rateAtAlignment, 6) + "," + ROUND(turnRateAtAlignment, 6) + "," + ROUND(settledRate, 6) + "," + ROUND(dampRate, 6) + ",rad/s").
		logMe:ADD("rotation accel and stopping time," + ROUND(rotationInfo["Accel"] * CONSTANT:RADTODEG, 5) + "," + ROUND(rotationInfo["StoppingTime"], 3) + ",deg/s^2 and s").
		logMe:ADD("rotation measured with RCS and turned with RCS," + rotationInfo["RCS"] + "," + useRCSforRotation).
		// the time that the loop was busy staging (the engines of the new stage are already thrusting during most of it)
		LOCAL gapLine IS "stage loop time measured".
		FOR eachGap IN stageGaps SET gapLine TO gapLine + "," + eachGap.
		logMe:ADD(gapLine + ",s").
		logMe:ADD("stage gap planned (reaction time and command time)," + stageReactionTime + "," + stageCommandTime + ",s").
		logMe:ADD("dV left in burn," + deltaVLeft + ",m/s").
		logMe:ADD("end reason," + endReason).
		LOCAL deltaVInShip IS shipInfo["CurrentStage"]["DeltaV"].
		IF burnWithRCS SET deltaVInShip TO rcsBurnStage(0)["Stage"]["DeltaV"].			// what the RCS propellant that is left can still do
		logMe:ADD("thrust source," + (CHOOSE "RCS" IF burnWithRCS ELSE "engines")).
		logMe:ADD("dV left in ship," + deltaVInShip + ",m/s").
		logMe:ADD("final mass," + shipInfo["CurrentStage"]["CurrentMass"] + ",kg").
		FOR message IN logMe {
			LOG message TO "0:Maneuver.csv".
		}
	}

	updateShipInfo().													// update the shipInfo structure with current status of the ship

	// The thrust limiters go back to 100 % for the highest (they keep their ratio). Not if the ship staged: the engines may be gone.
	IF limitFraction < 1 AND executedStages = 0 normalizeThrustLimits(usedStages[0]["Engines"]).

	SET RCS TO oldRCS.													// restore the previous RCS state
	SET SAS TO oldSAS.													// restore the previous SAS state
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
	IF abortRequested {
		setBurnThrottle(0).
		SET KUNIVERSE:TIMEWARP:WARP TO 0.
		IF HASNODE SET loopMessage TO "Aborted, " + distanceToString(nodeDeltaV():MAG, 1) + "/s left.".
		ELSE SET loopMessage TO "Node removed.".											// (a node that is gone has none left to report)
		IF NOT suppressPrinting PRINT "Burn stopped: " + stopReason().
	} ELSE IF endReason = "orbit energy reached" {
		SET loopMessage TO "Orbit energy reached, " + distanceToString(nodeDeltaV():MAG, 1) + "/s left.".
	} ELSE SET loopMessage TO "Done, " + distanceToString(nodeDeltaV():MAG, 1) + "/s left.".
	IF NOT abortRequested AND NOT suppressPrinting PRINT "Burn ended (" + endReason + "): " + loopMessage.
	// a saved multiPassBurn plan is finished when its last pass has been flown (library.ks)
	IF NOT abortRequested AND finishMultiPassPlan(burnNodeUT) {
		IF NOT suppressPrinting PRINT "That was the last pass of the multi-pass plan: the saved plan is deleted".
	}
} ELSE {
	SET loopMessage TO errorCode.
	PRINT errorCode.
}
