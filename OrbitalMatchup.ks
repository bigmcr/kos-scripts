@LAZYGLOBAL OFF.

// returns a list
// list[0] time until closest approach (seconds)
// list[1] distance of closest approach (meters)
FUNCTION closestApproach {
	PARAMETER initialGuess IS TIME:SECONDS.
	PARAMETER initialStepSize IS 10.
	IF (initialGuess < TIME:SECONDS) SET initialGuess TO TIME:SECONDS.
	
	LOCAL stepSize is initialStepSize.

	FUNCTION distanceAtTime {
	  PARAMETER t.
	  RETURN (POSITIONAT(SHIP, t) - POSITIONAT(TARGET, t)):MAG.
	}

	LOCAL iteration IS 0.
	
//	LOG "Approach Time,Step Size,Distance At Approach,Distance At Approach + Step,Distance At Approach - Step,Iteration" TO "HillClimb.csv".
	// Do the hill climbing
	LOCAL approachTime is initialGuess.
	UNTIL (stepSize = (initialStepSize / (2^10))) OR (iteration > 100) {
//		LOG approachTime + "," + stepSize + "," + distanceAtTime(approachTime) + "," + distanceAtTime(approachTime + stepSize) + "," + distanceAtTime(approachTime - stepSize) + "," + iteration TO "HillClimb.csv".
		IF distanceAtTime(approachTime + stepSize) < distanceAtTime(approachTime) {
			SET approachTime TO approachTime + stepSize.
		} ELSE IF distanceAtTime(approachTime - stepSize) < distanceAtTime(approachTime) {
			SET approachTime TO approachTime - stepSize.
		} ELSE {
			SET stepSize TO (stepSize/2).
		}
		SET iteration TO iteration + 1.
	}

//	PRINT "Closest approach is at UT " + ROUND(approachTime, 0) + " (" + ROUND(approachTime - TIME:SECONDS, 0) + ") seconds from now, distance will be " + ROUND(distanceAtTime(approachTime), 0) + " meters".
	RETURN LIST(approachTime, distanceAtTime(approachTime)).
}

LOCAL mode IS "Error".

IF shipInfo["Maximum"]["Accel"] = 0 {SET mode TO "Done". SET loopMessage TO "Error! Max accel is zero!".}
IF shipInfo["Maximum"]["mDot"] = 0 {SET mode TO "Done". SET loopMessage TO "Error! Max mDot is zero!".}
IF NOT HASTARGET {SET mode TO "Done". SET loopMessage TO "Error! No target selected!".}

IF (mode <> "Done") {
	LOCAL closestApproachTime IS closestApproach().
	SET mySteer TO SHIP:FACING.
	SET myThrottle TO 0.
	SET useMySteer TO TRUE.
	SET useMyThrottle TO TRUE.
	
	SAS OFF.
	RCS OFF.

	CLEARSCREEN.
	PRINT "Now warping close to the burn time.".
	warpToTime(closestApproach()[0] - 30).
	CLEARSCREEN.
	
	LOCAL targetVelocity IS V(0,0,0).
	LOCK targetVelocity TO (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT).

	LOCAL tgtPos IS VECDRAW(SHIP:POSITION, V(0,0,0), YELLOW, "Tgt Pos", 1.0, TRUE, 0.2).
	LOCAL tgtVel IS VECDRAW(SHIP:POSITION, V(0,0,0), RED, "Tgt Vel", 1.0, TRUE, 0.2).
	LOCAL shipFacing IS VECDRAW(SHIP:POSITION, V(0,0,0), BLUE, "Ship Facing", 1.0, TRUE, 0.2).
	LOCAL v_e IS (g_0 * shipInfo["CurrentStage"]["Isp"]).
	LOCAL burnTime IS 0.
	LOCAL startTime IS TIME:SECONDS.
	LOCAL elapsedTime TO TIME:SECONDS - startTime.
	LOCAL finalVelocity IS 0.

	LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0, 1).			// PID loop to control trottle when burnTime and timeToRez are close to each other

	LOCAL timeToRez TO 0.

	LOG "Elapsed Time,Timewarp Rate,Target Velocity,Target Distance,Mode,Burn Time (s),Time To Rez (s),Closest Approach (m),Throttle,Tgt Pos & Vel Angle" TO "0:OrbitalMatching.csv".

	SET mode TO "Waiting".
	UNTIL mode = "Done" {
		updateShipInfoCurrent().
		SET closestApproachTime TO closestApproach().
		SET burnTime TO shipInfo["CurrentStage"]["CurrentMass"]*(1-CONSTANT:e^(-targetVelocity:MAG/v_e))/shipInfo["CurrentStage"]["mDot"].
		SET timeToRez TO closestApproachTime[0] - TIME:SECONDS.
		PRINT "Mode " + mode + "     " AT (0, 0).
		PRINT "Burn Time: " + timeToString(burnTime) + "    " AT (0, 1).
		PRINT "Closest Approach Time: " + timeToString(timeToRez) + " from now    " AT (0, 2).
		PRINT "Closest Approach Distance: " + ROUND(closestApproachTime[1], 2) + " m  " AT (0, 3).
		PRINT "Target Velocity: " + ROUND(targetVelocity:MAG, 2) + " m/s  " AT (0, 4).
		PRINT "Target Distance: " + ROUND(TARGET:POSITION:MAG, 2) + " m  " AT (0, 5).
		
		IF (mode = "Waiting") {
			SET myThrottle TO 0.
			IF (timeToRez - burnTime < 5) {
				SET mode TO "Throttling".
				SET KUNIVERSE:TIMEWARP:WARP TO 0.
				WAIT 0.
				SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
				SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
			}
		}
		IF (mode = "Throttling") {
			SET T_PID:SETPOINT TO burnTime.
			SET myThrottle TO T_PID:UPDATE(TIME:SECONDS, timeToRez).
			SET mySteer TO ((-targetVelocity) * ROTATEFROMTO(-TARGET:POSITION, -targetVelocity)) * ROTATEFROMTO(-TARGET:POSITION, -targetVelocity).
			IF TARGET:POSITION:MAG < 1000 {
				SET mode TO "Final".
				SET KUNIVERSE:TIMEWARP:WARP TO 0.
				SET finalVelocity TO targetVelocity:MAG.
			}
		}
		IF (mode = "Final") {
			SET mySteer TO -targetVelocity.
			IF (isStockRockets()) {
				SET myThrottle TO MIN(1, MAX(targetVelocity:MAG / finalVelocity, 0.1)).
			}
			IF (targetVelocity:MAG < 1) {SET mode TO "Done". SET loopMessage TO "Sucessfully zeroed out target velocity".}
		}

		SET tgtPos:VEC TO TARGET:POSITION:NORMALIZED * 10.
		SET tgtVel:VEC TO -targetVelocity:NORMALIZED * 10.
		SET shipFacing:VEC TO SHIP:FACING:FOREVECTOR * 10.

		LOG elapsedTime + "," + KUNIVERSE:TIMEWARP:RATE + "," + targetVelocity:MAG + "," + TARGET:POSITION:MAG + "," + mode + "," + burnTime + "," + timeToRez + "," + closestApproachTime[1] + "," + throttle + "," + VANG(targetVelocity, TARGET:POSITION) TO "0:OrbitalMatching.csv".

		SET elapsedTime TO TIME:SECONDS - startTime.
		WAIT 0.
	}
}
SET useMySteer TO FALSE.
SET useMyThrottle TO FALSE.
endScript().
