@LAZYGLOBAL OFF.

PARAMETER ullage IS 5.												// the number of seconds the RSC thrusters need to be firing forward to
																							//		make the main engine's fuel be stable
																							//		only applicable in RSS, so disabled if in stock universe
PARAMETER useRCSforRotation IS FALSE.
PARAMETER faceSun IS FALSE.										// during the waiting times, turn to face the sun
																							//		intended to ensure that probes' solar panels are exposed to the Sun.
PARAMETER suppressPrinting IS FALSE.

IF NOT suppressPrinting CLEARSCREEN.

LOCAL pointingError IS 1.0.										// Allowed pointing error, in degrees
LOCAL angularVelError IS SHIP:MASS / 100.			// Allowed angular velocity error, in megagrams-meters
LOCAL errorCode IS "None".
updateShipInfo().

IF (NOT HASNODE) SET errorCode TO "No Maneuver Node Present!".
IF (shipInfo["CurrentStage"]["ENGINES"]:LENGTH = 0) SET errorCode TO "Ship has no engines in current stage!".
IF (shipInfo["CurrentStage"]["Isp"] = 0) SET errorCode TO "Isp is Zero!".
IF (shipInfo["CurrentStage"]["Thrust"] = 0) SET errorCode TO "Maximum engine thrust is Zero!".
IF (shipInfo["CurrentStage"]["ENGINES"]:LENGTH <> 0) IF VANG(shipInfo["CurrentStage"]["Engines"][0]:FACING:VECTOR, SHIP:FACING:VECTOR) > 45 SET errorCode TO "Engines facing the wrong way!".

// only run the script if there is a node to execute
IF errorCode = "None" {
	updateShipInfoCurrent(FALSE).
	updateShipInfoResources().									// update the shipInfo structure with current status of the ship
	LOCAL oldRCS IS RCS.												// record the current status of RCS
	LOCAL oldSAS IS SAS.												// record the current status of SAS

	SET RCS TO useRCSforRotation.								// set RCS to the allowed state for the rotations
	SAS OFF.																		// always turn SAS off, as it interferes with steering control

	setLockedSteering(FALSE).
	SET globalSteer TO SHIP:FACING.
	setLockedSteering(TRUE).

	LOCAL ND TO NEXTNODE.
	LOCK ND TO NEXTNODE.
	LOCAL dV_req TO ND:DELTAV:MAG.

	LOCAL Isp_stg IS LIST().
	LOCAL T_stg IS LIST().
	LOCAL m_dry_stg IS LIST().									// Mass of the empty stage (kg)
	LOCAL m_wet_stg IS LIST().									// Mass of the fuelled stage (kg)
	LOCAL v_e_stg IS LIST().										// Exhaust velocity (m/s)
	LOCAL dV_avail_stg IS LIST().								// Delta V available in this stage (m/s)
	LOCAL m_dot_stg IS LIST().									// Rate of change of mass for the engine (kg/s)
	LOCAL dv_prev_stg IS LIST().
	LOCAL dv_req_stage_stg IS LIST().
	LOCAL stage_req_stg IS LIST().
	LOCAL ign_after_t_0_stg IS LIST().
	LOCAL dv_before_t_0_stg IS LIST().
	LOCAL t_burn_req_stg IS LIST().
	LOCAL t_ign IS 0.														// the burn delay before nominal time (s)
	LOCAL t_total IS 0.													// the total burn duration (s)

	LOCAL e IS CONSTANT():E.            				// Base of natural log
	LOCAL g_0 IS 9.80665.            						// Gravitational acceleration constant (m/s²)
	LOCAL a_i IS 0.															// initial acceleration at the start of the burn (m/s^2)
	LOCAL a_f IS 0.															// final acceleration at the end of the burn (m/s^2)

	LOCAL usedStages IS LIST().
	FOR stageNumber IN RANGE(shipInfo["NumberOfStages"] - 1, -1) {
		IF shipInfo["Stage " + stageNumber]["Isp"] <> 0 usedStages:ADD(shipInfo["Stage " + stageNumber]).
	}
	IF NOT suppressPrinting {
		IF usedStages:LENGTH <> 0 AND debug PRINT "There are a total of " + usedStages:LENGTH + " stages that can be used".
		ELSE PRINT "There are a total of " + usedStages:LENGTH + " stage that can be used".
	}

	LOCAL startTime IS MISSIONTIME.
	LOCAL startStage IS STAGE:NUMBER.
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

	SET a_i TO usedStages[lowestUsedStage]["Thrust"] / usedStages[lowestUsedStage]["CurrentMass"].
	SET a_f TO usedStages[highestUsedStage]["Thrust"]/(usedStages[highestUsedStage]["CurrentMass"]*e^(-dV_req_stage_stg[highestUsedStage]/v_e_stg[highestUsedStage])).

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
		logMe:ADD("t_total," + t_total + ",s").
		logMe:ADD("t_ign," + t_ign + ",s").
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
//  ign_after_t_0
		SET logMe[11] TO logMe[11] + "m/s,".
		SET logMe[12] TO logMe[12] + "m/s,".
		FOR message IN logMe {
			LOG message TO "0:Maneuver.csv".
		}
	}

	// print out the paramters of the rocket - thrust, m_0, m_f, m_part, Isp and mDot
	IF debug AND NOT suppressPrinting {
		PRINT "Node in: " + timeToString(ND:ETA) + ", DeltaV: " + distanceToString(ND:DELTAV:MAG, 3) + "/s".
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
			IF faceSun PRINT "Will turn to face the Sun".
			ELSE PRINT "Will not turn to face the Sun".
			PRINT "Burn duration: " + timeToString(t_total , 2).
		}
	}

	// if called to face the sun and the node is more than 60 minutes away, turn to face the primary.
	// turn on physics warp for the rotation if allowed
	IF physicsWarpPerm {
		SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
		SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
	}
	IF faceSun AND ND:ETA > 60*60 {
		LOCAL faceBody IS BODY("Sun").
		IF debug AND NOT suppressPrinting PRINT "Aligning with the Sun. Burn ETA: " + timeToString(ND:ETA - t_ign , 2).
		SET globalSteer TO faceBody:POSITION.
		//now we need to wait until the body's position vector and ship's facing are aligned
		WAIT UNTIL ((VANG(FACING:VECTOR, ND:DELTAV) < pointingError ) AND SHIP:ANGULARVEL:MAG < 0.1) OR (ND:ETA <= t_ign + ullage).
	} ELSE {
		SET globalSteer TO ND:DELTAV.
		IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node. Burn ETA: " + timeToString(ND:ETA - t_ign , 2).
		//now we need to wait until the burn vector and ship's facing are aligned
		WAIT UNTIL (VANG(FACING:VECTOR, ND:DELTAV) < pointingError AND SHIP:ANGULARVEL:MAG < 0.1) OR (ND:ETA <= t_ign + ullage).
	}
	// if the node is more than 5 minutes away, pause for twice as long as the steering manager's stopping time to allow all roll rotation to be damped out
	IF ND:ETA > 5*60 WAIT STEERINGMANAGER:MAXSTOPPINGTIME*2.
	// always turn off physics warp
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
	SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

	// if ullage is not a concern, warp to 30 seconds before burntime
	IF (isStockRockets() OR (ullage = 0)) {
		warpToTime(TIME:SECONDS + ND:ETA - MAX(1.5*t_ign, 30)).
		IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node (again). Burn ETA: " + timeToString(ND:ETA - t_ign, 2).
		SET globalSteer TO ND:DELTAV.
		IF physicsWarpPerm {
			SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
			SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
		}
		WAIT UNTIL (ND:ETA <= t_ign).
	} ELSE {
	// if ullage is a concern, warp to MAX(90, ullage) seconds before burntime
		IF debug AND NOT suppressPrinting PRINT "Warping to " + timeToString(ND:ETA - t_ign - MAX(90, ullage), 2).
		warpToTime(TIME:SECONDS + ND:ETA - t_ign - MAX(90, ullage)).

		IF faceSun {
			IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node. Burn ETA: " + timeToString(ND:ETA - t_ign, 2).
			SET globalSteer TO ND:DELTAV.
		} ELSE {IF debug AND NOT suppressPrinting PRINT "Aligning with the maneuver node (again). Burn ETA: " + timeToString(ND:ETA - t_ign, 2).}

		IF physicsWarpPerm {
			SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
			SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
		}
		//now we need to wait until the burn vector and ship's facing are aligned
		WAIT UNTIL ((ND:ETA <= t_ign + ullage) OR (VANG(FACING:VECTOR, ND:DELTAV) < pointingError)).

		IF debug AND NOT suppressPrinting PRINT "Waiting until the ullage time, " + timeToString(ND:ETA - t_ign - ullage).
		warpToTime(TIME:SECONDS + ND:ETA - t_ign - ullage).

		// use RCS to settle any ullage concerns.
		IF (ullage <> 0) {
			RCS ON.
			SET SHIP:CONTROL:FORE TO 1.0.
			IF debug AND NOT suppressPrinting PRINT "Ullage starting".
			IF debug AND NOT suppressPrinting PRINT "Waiting until the burn time, " + timeToString(ND:ETA - t_ign).
			WAIT ullage.												// wait for the burn to start
		}.

		// the main engines are starting, so turn off RCS for ullage
		IF (ullage <> 0) {
			RCS OFF.
			SET SHIP:CONTROL:FORE TO 0.0.
			IF debug AND NOT suppressPrinting PRINT "Ullage over, main engines starting".
		}
	}

	IF physicsWarpPerm AND t_total > 30 {								// only actually use physics warp if the burn duration is greater than 30 seconds
		SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
		SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
	}

	LOCAL maxStages IS 20.
	LOCAL executedStages IS 0.
	LOCAL done TO FALSE.
	//initial deltav
	LOCAL DV0 TO ND:DELTAV.
	SET globalThrottle TO 0.
	setLockedThrottle(TRUE).
	UNTIL done
	{
		SET globalSteer TO ND:DELTAV.
		updateShipInfoCurrent(FALSE).
		IF (MAXTHRUST = 0) {SET executedStages TO executedStages + 1. PRINT "Staging from maxthrust". stageFunction().}

		// This drops any empty fuel tanks
		IF (shipInfo["CurrentStage"]["ResourceMass"] < 1.0 ) {
			PRINT "Staging from resources".
			SET executedStages TO executedStages + 1.
			IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
			ELSE stageFunction().
		}


		SET dV_req TO ND:DELTAV.
		// cut the throttle as soon as our nd:deltaV and initial deltaV start facing opposite directions
		IF (VDOT(DV0, ND:DELTAV) < 0) OR (executedStages >= maxStages)
		{
			IF debug AND NOT suppressPrinting PRINT "End burn, remaining dV " + distanceToString(ND:DELTAV:MAG, 1) + "/s, vdot: " + ROUND(VDOT(DV0, ND:DELTAV),1).
			SET done TO TRUE.
		}

		// If we are nearing the end of the burn (less than 1 second), stop physics warp to allow for more precision
		IF ND:DELTAV:MAG <= a_f AND physicsWarpPerm {
			SET KUNIVERSE:TIMEWARP:WARP TO 0.
			IF (isStockRockets()) {
				SET globalThrottle TO MAX(ND:DELTAV:MAG / a_f, 0.1).
			}
		} ELSE {
			SET globalThrottle TO  1.
		}
		WAIT 0.
	}
	SET globalThrottle TO 0.
	WAIT 0.

	updateShipInfo().
	IF connectionToKSC() {
		LOCAL logMe IS LIST().
		logMe:ADD("actual burn time," + (MISSIONTIME - startTime) + ",s").
		logMe:ADD("stages used," + (STAGE:NUMBER - startStage + 1)).
		logMe:ADD("dV left in burn," + ND:DELTAV:MAG + ",m/s").
		logMe:ADD("dV left in ship," + ND:DELTAV:MAG + ",m/s").
		logMe:ADD("final mass," + SHIP:MASS * 1000 + ",kg").
		FOR message IN logMe {
			LOG message TO "0:Maneuver.csv".
		}
	}

	updateShipInfo().													// update the shipInfo structure with current status of the ship

	SET RCS TO oldRCS.													// restore the previous RCS state
	SET SAS TO oldSAS.													// restore the previous SAS state
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
	SET loopMessage TO "Node executed correctly! " + distanceToString(ND:DELTAV:MAG, 1) + "/s left.".
} ELSE {
	SET loopMessage TO errorCode.
	PRINT errorCode.
}
