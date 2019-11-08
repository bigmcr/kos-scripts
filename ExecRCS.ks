@LAZYGLOBAL OFF.

CLEARSCREEN.

LOCAL errorCode IS "None".
updateShipInfoCurrent(FALSE).

LOCAL RCSEngines IS LIST().

FOR eachPart IN SHIP:PARTS {
	FOR eachModule IN eachPart:MODULES {
		IF eachPart:GETMODULE(eachModule):HASFIELD("rcs isp") {
			RCSEngines:ADD(eachPart).
		}
	}
}
LOCAL engineStats IS engineStatsRCS(RCSEngines).
LOCAL RCSIsp IS RCSEngines[0]:GETMODULE("ModuleRCSFX"):GETFIELD("rcs isp").
LOCAL RCSThrust IS 0.
FOR eachEngine IN RCSEngines {
	IF  eachEngine:TITLE:CONTAINS("RCS Quad") 	SET RCSThrust TO eachEngine:TITLE:SUBSTRING(14, 3):TONUMBER(0) * RCSEngines:LENGTH.
	ELSE 										SET RCSThrust TO eachEngine:TITLE:SUBSTRING(18, 3):TONUMBER(0) * RCSEngines:LENGTH.
}

CLEARSCREEN. PRINT "Total Thrust: " + ROUND(RCSThrust, 0) + " kN, Engine Count: " + RCSEngines:LENGTH.

IF (NOT HASNODE) SET errorCode TO "No Maneuver Node Present!".
IF (RCSEngines:LENGTH = 0) SET errorCode TO "Ship has no RCS thrusters in current stage".
IF (RCSIsp = 0) SET errorCode TO "RCS Isp is Zero!".
IF (RCSThrust = 0) SET errorCode TO "Maximum engine thrust is Zero!".

// only run the script if there are not any errors
IF errorCode = "None" {
	RCS ON.																// as the script requires RCS, turn it on
	SAS OFF.															// always turn SAS off, as it interferes with steering control
	
	SET mySteer TO SHIP:FACING.
	SET useMySteer TO TRUE.
	
	LOCAL ND TO NEXTNODE.
	LOCK ND TO NEXTNODE.

	LOCAL e IS CONSTANT():E.            								// Base of natural log
	LOCAL g_0 IS 9.80665.               								// Gravitational acceleration constant (m/s²)
	LOCAL m_i IS SHIP:MASS * 1000.										// Ship's mass (kg)

	LOCAL dV_req TO ND:DELTAV:MAG.
	LOCAL v_e IS RCSIsp * g_0.
	LOCAL m_dot IS RCSThrust / v_e.
	LOCAL burnTime IS m_i * (1 - e ^ (- dV_req / v_e ) ) / m_dot.
	LOCAL m_f IS m_i - burnTime*m_dot.
	LOCAL a_i IS RCSThrust / m_i.										// initial acceleration at the start of the burn (m/s^2)
	LOCAL a_f IS RCSThrust / m_f.										// final acceleration at the end of the burn (m/s^2)
	LOCAL m_dry TO SHIP:DRYMASS * 1000.									// mass of the ship with all fuel used (kg)
	LOCAL m_wet TO SHIP:MASS * 1000.									// mass of the ship without all fuel used (kg)
	
	// move all Ablator mass from wetmass to drymass.
	// assumes that ablator cannot be used as RCS fuel.
	FOR eachPart IN SHIP:PARTS {
		FOR eachResource IN eachPart:RESOURCES {
			IF eachResource:NAME:CONTAINS("Ablator") {
				SET m_dry TO m_dry + (eachResource:AMOUNT * eachResource:DENSITY) * 1000.
//				SET m_wet TO m_wet - (eachResource:AMOUNT * eachResource:DENSITY) * 1000.
			}
		}
	}
	
	LOCAL dV_avail TO v_e*LN(m_wet/m_dry).
	LOCAL dv_prev TO 0.
	LOCAL dV_req_stage TO MIN(MAX(dV_req-dV_prev,0),dV_avail).
	LOCAL ign_after_t_0 TO TRUE.
	LOCAL dv_before_t_0 TO MIN( dV_avail, dV_req / 2 - dv_Prev).
	LOCAL t_burn_req TO m_wet*(1-e^(-dV_req_stage/v_e))/m_dot.

	LOCAL t_total TO t_burn_req.
	LOCAL t_ign TO m_wet*(1-e^(-dV_before_t_0/v_e))/m_dot.

	IF connectionToKSC() {
		LOCAL logMe IS LIST().
		logMe:ADD(SHIP:NAME + " RCS burn,Stage N/A,").		// 0
		logMe:ADD("Isp," + RCSIsp + ",").					// 1
		logMe:ADD("T," + RCSThrust + ",").					// 2
		logMe:ADD("m_dry," + m_dry + ",").					// 3
		logMe:ADD("m_wet," + m_wet + ",").					// 4
		logMe:ADD("v_e," + v_e + ",").						// 5
		logMe:ADD("dV_avail," + dV_avail + ",").			// 6
		logMe:ADD("m_dot," + m_dot + ",").					// 7
		logMe:ADD("dv_prev," + dv_prev + ",").				// 8
		logMe:ADD("dV_req_stage," + dV_req_stage + ",").	// 9
		logMe:ADD("ign_after_t_0," + ign_after_t_0 + ",").	// 10
		logMe:ADD("dV_before_t_0," + dv_before_t_0 + ",").	// 11
		logMe:ADD("t_burn_req," + t_burn_req + ",").			// 12
		logMe:ADD("t_total," + t_total).
		logMe:ADD("t_ign," + t_ign).
		logMe:ADD("highestUsedStage,N/A").
		logMe:ADD("lowestUsedStage,N/A").
		logMe:ADD("usedStages:LENGTH,N/A").
		logMe:ADD("a_i," + a_i).
		logMe:ADD("a_f," + a_f).
		logMe:ADD("dV_req," + dV_req).
		FOR message IN logMe {
			LOG message TO "Maneuver.csv".
		}
	}

	// print out the paramters of the rocket - thrust, m_0, m_f, m_part, Isp and mDot
	IF debug {
		PRINT "Node in: " + timeToString(ND:ETA) + ", DeltaV: " + distanceToString(ND:DELTAV:MAG, 3) + "/s".
		PRINT "Stage  m_dry  m_wet   v_e  dV_avail  m_dot  dv_Prev  dv_Req  t_burn".
		PRINT "          kg     kg   m/s       m/s   kg/s      m/s     m/s       s".
		PRINT STAGE:NUMBER:TOSTRING:PADLEFT(5) + ROUND(m_dry, 0):TOSTRING:PADLEFT(7) + ROUND(m_wet, 0):TOSTRING:PADLEFT(7) + ROUND(v_e, 0):TOSTRING:PADLEFT(6) + ROUND(dV_avail, 0):TOSTRING:PADLEFT(10) + ROUND(m_dot, 1):TOSTRING:PADLEFT(7) + ROUND(dv_Prev, 0):TOSTRING:PADLEFT(9) + ROUND(dV_req_stage, 0):TOSTRING:PADLEFT(8) + ROUND(t_burn_req, 2):TOSTRING:PADLEFT(8).
		PRINT "Burn Delay, " + timeToString(t_ign, 2).
		PRINT "Total Burntime, " + timeToString(t_total, 2).
		PRINT "initial accel " + ROUND(a_i, 2 ) + " m/s   final accel " + ROUND(a_f, 2) + " m/s".
	}

	// if called to face the sun and the node is more than 60 minutes away, turn to face the primary.
	// turn on physics warp for the rotation if allowed
	IF physicsWarpPerm {
		SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
		SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
	}

	LOCK mySteer TO ND:DELTAV.
	IF debug PRINT "Aligning with the maneuver node. Burn ETA: " + timeToString(ND:ETA - t_ign , 2).
	//now we need to wait until the burn vector and ship's facing are aligned
	WAIT UNTIL (ABS(ND:DELTAV:DIRECTION:PITCH - FACING:PITCH) < 0.15 AND ABS(ND:DELTAV:DIRECTION:YAW - FACING:YAW) < 0.15 AND SHIP:ANGULARVEL:MAG < 0.01).

	// if the node is more than 5 minutes away, pause for twice as long as the steering manager's stopping time to allow all roll rotation to be damped out
	IF ND:ETA > 5*60 WAIT STEERINGMANAGER:MAXSTOPPINGTIME*2.
	// always turn off physics warp
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
	SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
	
	// if ullage is not a concern, warp to 15 seconds before burntime
	warpToTime(TIME:SECONDS + ND:ETA - t_ign - 15).
	IF debug PRINT "Aligning with the maneuver node (again). Burn ETA: " + timeToString(ND:ETA - t_ign, 2).
	LOCK mySteer TO ND:DELTAV.
	IF physicsWarpPerm {
		SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
		SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
	}
	WAIT UNTIL (ND:ETA <= t_ign).
	
	IF debug PRINT "Starting the burn!".
	
	SET SHIP:CONTROL:FORE TO 1.											// set the throttle to max
	LOCK mySteer TO ND:DELTAV.
	
	IF physicsWarpPerm AND t_total > 30 {								// only actually use physics warp if the burn duration is greater than 30 seconds
		SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
		SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
	}
	
	// If we are nearing the end of the burn (less than 1 second), stop physics warp to allow for more precision
	WHEN ((ND:DELTAV:MAG <= a_f) AND physicsWarpPerm) THEN {
		SET KUNIVERSE:TIMEWARP:WARP TO 0.
	}
	LOCAL done TO FALSE.
	//initial deltav
	LOCAL DV0 TO ND:DELTAV.
	UNTIL done
	{
		SET dV_req TO ND:DELTAV.
		// cut the throttle as soon as our nd:deltaV and initial deltaV start facing opposite directions
		IF VDOT(DV0, ND:DELTAV) < 0
		{
			IF debug PRINT "End burn, remaining dV " + ROUND(ND:DELTAV:MAG,1) + "m/s, vdot: " + ROUND(VDOT(DV0, ND:DELTAV),1).
			SET done TO TRUE.
		}
		// If we are nearing the end of the burn (less than 1 second), stop physics warp to allow for more precision
		IF ND:DELTAV:MAG <= a_f AND physicsWarpPerm {
			SET KUNIVERSE:TIMEWARP:WARP TO 0.
			SET SHIP:CONTROL:FORE TO MAX(ND:DELTAV:MAG / a_f, 0.1).
		}
		WAIT 0.
	}
	UNLOCK mySteer.

	SET useMySteer TO FALSE.
	
	SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
	
	endScript().
	updateShipInfo().													// update the shipInfo structure with current status of the ship
	
	SET SHIP:CONTROL:FORE TO 0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot
	SET loopMessage TO "Node executed correctly! " + ROUND(ND:DELTAV:MAG, 1) + " m/s left.".
} ELSE {
	SET loopMessage TO errorCode.
	PRINT errorCode.
}
