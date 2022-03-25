@LAZYGLOBAL OFF.

LOCAL mode IS "Error".

IF shipInfo["Maximum"]["Accel"] = 0 {SET mode TO "Done". SET loopMessage TO "Error! Max accel is zero!".}
IF shipInfo["Maximum"]["mDot"] = 0 {SET mode TO "Done". SET loopMessage TO "Error! Max mDot is zero!".}
IF NOT HASTARGET {SET mode TO "Done". SET loopMessage TO "Error! No target selected!".}

IF (mode <> "Done") {
	updateShipInfo().
	LOCAL closestApproachTime IS closestApproach().
	SET mySteer TO SHIP:FACING.
	SET myThrottle TO 0.
	SET useMySteer TO TRUE.
	SET useMyThrottle TO TRUE.

	SAS OFF.
	RCS OFF.

	LOCAL targetVelocity IS V(0,0,0).
	LOCK targetVelocity TO (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT).
	LOCAL v_e IS (g_0 * shipInfo["CurrentStage"]["Isp"]).
	LOCAL startTime IS TIME:SECONDS.
	LOCAL finalVelocity IS 0.
	LOCAL timeToRez IS 0.
	LOCAL targetSpeed IS targetVelocity:MAG.
	LOCAL targetDistance IS TARGET:POSITION:MAG.
	LOCAL currentMass IS shipInfo["CurrentStage"]["CurrentMass"].
	LOCAL mDot IS shipInfo["CurrentStage"]["mDot"].
	LOCAL burnTime IS currentMass*(1-CONSTANT:e^(-targetSpeed/v_e))/mDot.
	LOCAL burnDistance IS 1.05*((burnTime - currentMass/mDot)*targetSpeed + burnTime*v_e).

	CLEARSCREEN.
	PRINT "Now warping close to the burn time.".
	// warp until the target is approximately 10 km from the burnDistance away
	warpToTime((targetDistance - (burnDistance + 10000) ) / targetSpeed + TIME:SECONDS).
	CLEARSCREEN.

	LOCAL elapsedTime TO TIME:SECONDS - startTime.

	LOCAL tgtPos IS VECDRAW(SHIP:POSITION, V(0,0,0), YELLOW, "Tgt Pos", 1.0, TRUE, 0.2).
	LOCAL tgtVel IS VECDRAW(SHIP:POSITION, V(0,0,0), RED, "Tgt Vel", 1.0, TRUE, 0.2).
	LOCAL shipFacing IS VECDRAW(SHIP:POSITION, V(0,0,0), BLUE, "Ship Facing", 1.0, TRUE, 0.2).

	LOG "Elapsed Time,Timewarp Rate,Current Mass,Target Speed,Target Distance,Burn Distance,Mode,Burn Time (s),Time To Rez (s),Closest Approach (m),Throttle,Tgt Pos & Vel Angle,Tgt Vel & Facing Angle,,mDot," + mDot + ",,v_e," + v_e TO "0:OrbitalRez.csv".

	SET mode TO "Waiting".
	SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
	SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
	UNTIL mode = "Done" {
		updateShipInfoCurrent().
		SET currentMass TO shipInfo["CurrentStage"]["CurrentMass"].
		SET targetSpeed TO targetVelocity:MAG.
		SET targetDistance TO TARGET:POSITION:MAG.
		SET closestApproachTime TO closestApproach().
		SET burnTime TO currentMass*(1-CONSTANT:e^(-targetSpeed / v_e))/mDot.
		SET timeToRez TO closestApproachTime[0] - TIME:SECONDS.
		SET burnDistance TO 1.05*((burnTime - currentMass/mDot)*targetSpeed + burnTime*v_e).
		PRINT "Mode " + mode + "     " AT (0, 0).
		PRINT "Burn Time: " + timeToString(burnTime) + "    " AT (0, 1).
		PRINT "Closest Approach Time: " + timeToString(timeToRez) + " from now    " AT (0, 2).
		PRINT "Closest Approach Distance: " + distanceToString(closestApproachTime[1], 2) + "   " AT (0, 3).
		PRINT "Burn Distance: " + distanceToString(burnDistance, 2) + "    " AT (0, 4).
		PRINT "Target Velocity: " + distanceToString(targetSpeed, 1) + "/s  " AT (0, 5).
		PRINT "Target Distance: " + distanceToString(targetDistance, 2) + "   " AT (0, 6).

		IF (mode = "Waiting") {
			SET myThrottle TO 0.
			IF (burnDistance >= targetDistance - 1000) {
				SET mode TO "Burning".
			}
		}
		IF (mode = "Burning") {
			SET myThrottle TO 1.
			IF VANG(targetVelocity, TARGET:POSITION) < 10 SET mySteer TO ((-targetVelocity) * ROTATEFROMTO(-TARGET:POSITION, -targetVelocity)) * ROTATEFROMTO(-TARGET:POSITION, -targetVelocity).
			ELSE IF VANG(targetVelocity, TARGET:POSITION) > 160 SET mySteer TO ((targetVelocity) * ROTATEFROMTO(-TARGET:POSITION, targetVelocity)) * ROTATEFROMTO(-TARGET:POSITION, targetVelocity).
			ELSE SET mySteer TO -targetVelocity.
			IF targetSpeed < 5*shipInfo["Current"]["Accel"] {
				SET mode TO "Final".
				SET finalVelocity TO targetSpeed.
				SET KUNIVERSE:TIMEWARP:WARP TO 0.
			}
		}
		IF (mode = "Final") {
			SET mySteer TO -targetVelocity.
			IF (isStockRockets()) {
				SET myThrottle TO MIN(1, MAX(targetSpeed / finalVelocity, 0.1)).
			}
			IF (targetSpeed < 1) {SET mode TO "Done". SET loopMessage TO "Sucessfully zeroed out target velocity".}
		}

		SET tgtPos:VEC TO TARGET:POSITION:NORMALIZED * 10.
		SET tgtVel:VEC TO -targetVelocity:NORMALIZED * 10.
		SET shipFacing:VEC TO SHIP:FACING:FOREVECTOR * 10.

		LOG elapsedTime + "," + KUNIVERSE:TIMEWARP:RATE + "," + currentMass + "," + targetSpeed + "," + targetDistance + "," + burnDistance + "," + mode + "," + burnTime + "," + timeToRez + "," + closestApproachTime[1] + "," + throttle + "," + VANG(targetVelocity, TARGET:POSITION) + "," + VANG(-targetVelocity, SHIP:FACING:VECTOR) TO "0:OrbitalRez.csv".

		SET elapsedTime TO TIME:SECONDS - startTime.
		WAIT 0.
	}
}
SET useMySteer TO FALSE.
SET useMyThrottle TO FALSE.
