@LAZYGLOBAL OFF.

// OrbitalRez: cancels the velocity of the ship relative to the target in a single burn, ending a little short of the
// point of closest approach. It is meant for two vessels on a near-collision course. (OrbitalApproach closes on a target
// that is not on a collision course, and brakes along a profile.)
//
// The burn is planned with the rocket equation and starts when the distance left to the stop point equals the braking
// distance. A ship with throttleable engines plans the burn at 90% of its maximum acceleration, so that there is thrust in
// reserve to correct the course. A ship with engines that cannot be throttled down plans it at 100%.
//
// Gravity bends the relative path of the two ships, so the straight line of the relative velocity is not used. The closest
// approach is predicted along the orbits (POSITIONAT), and the chord from the ship to the predicted point of closest approach
// takes the place of the relative velocity direction. This is also why a burn started late in a long coast is still aimed right.
//
// The ship is steered like the landing script (EqualTimeLand) does: the thrust is retrograde, offset away from the line to
// the target by tiltGain times the angle between the path and the line to the target, which curves the path back onto the
// target. During the burn the throttle is the deceleration that stops the ship at the stop point, divided by the part of the
// acceleration that points along the braking direction.
//
// Engines: nothing is switched off and on during the burn, and a variable throttle is only used when the engines can be
// throttled down. A lit engine with limited ignitions stays lit at no less than its minimum throttle until the burn is over, even
// if the ship is pointing badly for a moment, so a single-start engine only has the one ignition used. Where ullage is needed
// (not the stock universe), RCS fires forward for the ullage time before the main engines start.
//
// Press AG1 or the ENTER key to abort. (The long warp at the start cannot be interrupted.)
//
// Passed the following:
//   ullage       (scalar, seconds the RCS thrusters fire forward before ignition. Only used outside the stock universe.)
//   standoff     (scalar, meters before the point of closest approach where the ship is brought to a stop.)
//   trimWithRCS  (boolean, at the end, RCS thrusters (if the ship has any) null the last of the velocity.)
PARAMETER ullage IS 5.
PARAMETER standoff IS 100.
PARAMETER trimWithRCS IS TRUE.

LOCAL mode IS "Error".

// Constants of the guidance
LOCAL thrustFraction IS 0.9.			// fraction of the maximum acceleration that the burn is planned with, if the throttle can be varied
LOCAL tiltGain IS 2.					// the thrust is offset from retrograde by this multiple of the angle between the path and the target
LOCAL maxTilt IS 60.					// degrees, the most that the thrust is offset from retrograde
LOCAL alignLimit IS 5.					// degrees, the throttle is held at zero while the ship points further than this from the burn direction
LOCAL controlTime IS 1.					// s, near the end of the burn the throttle is the one that would cancel the speed in this long
LOCAL stopSpeed IS 0.2.					// m/s, the burn is over when the relative speed is this small
LOCAL deadband IS 0.05.					// m/s, a speed smaller than this is ignored
LOCAL approachInterval IS 3.			// s of game time between searches for the closest approach, which takes a while
LOCAL warpLead IS MAX(90, ullage).		// s, the warp at the start stops this long before the burn (or the ullage) is to start

// Distance and time that a burn at a constant thrust takes to cancel a speed, from the rocket equation. They need no mass,
// because the ratio of the mass to the mass flow is the exhaust velocity divided by the acceleration.
LOCAL FUNCTION brakeDistance {
	PARAMETER speed.
	PARAMETER v_e.
	PARAMETER acceleration.
	IF speed < 0.01 RETURN speed^2 / (2 * acceleration).
	RETURN v_e / acceleration * (speed - v_e * (1 - CONSTANT:e^(-speed / v_e))).
}

LOCAL FUNCTION brakeTime {
	PARAMETER speed.
	PARAMETER v_e.
	PARAMETER acceleration.
	RETURN v_e / acceleration * (1 - CONSTANT:e^(-speed / v_e)).
}

IF shipInfo["Maximum"]["Accel"] = 0 {SET mode TO "Done". SET loopMessage TO "Error! Max accel is zero!".}
IF shipInfo["Maximum"]["mDot"] = 0 {SET mode TO "Done". SET loopMessage TO "Error! Max mDot is zero!".}
IF NOT HASTARGET {SET mode TO "Done". SET loopMessage TO "Error! No target selected!".}

// The orbitable whose velocity is used.
LOCAL targetOrbitable IS SHIP.

IF (mode <> "Done") {
	updateShipInfo().

	SET targetOrbitable TO TARGET.

	// Checks before anything is moved
	LOCAL errorMessage IS "".
	IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") SET errorMessage TO "Error! Target must be a vessel or a body, not a part!".
	ELSE {
		IF targetOrbitable:BODY:NAME <> SHIP:BODY:NAME SET errorMessage TO "Error! Target is not orbiting " + SHIP:BODY:NAME + "!".
		IF shipInfo["CurrentStage"]["Isp"] = 0 SET errorMessage TO "Error! Isp is zero!".
		IF shipInfo["CurrentStage"]["ENGINES"]:LENGTH = 0 SET errorMessage TO "Error! Ship has no engines in the current stage!".
	}
	IF errorMessage = "" {
		LOCAL relativeSpeed IS (SHIP:VELOCITY:ORBIT - targetOrbitable:VELOCITY:ORBIT):MAG.
		IF VANG(shipInfo["CurrentStage"]["Engines"][0]:FACING:VECTOR, SHIP:FACING:VECTOR) > 45 SET errorMessage TO "Error! Engines are facing the wrong way!".
		IF relativeSpeed * 1.1 > shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"] SET errorMessage TO "Error! Not enough delta V to cancel the relative velocity!".
		IF relativeSpeed < stopSpeed SET errorMessage TO "Error! Already at rest relative to the target!".
	}
	IF errorMessage <> "" {
		SET mode TO "Done".
		SET loopMessage TO errorMessage.
	}
}

IF (mode <> "Done") {
	LOCAL oldRCS IS RCS.
	LOCAL oldSAS IS SAS.
	LOCAL needUllage IS ullage > 0 AND NOT isStockRockets().

	SET globalSteer TO SHIP:FACING.
	SET globalThrottle TO 0.
	setLockedSteering(TRUE).
	setLockedThrottle(TRUE).

	SAS OFF.
	RCS OFF.
	AG1 OFF.

	LOCAL startTime IS TIME:SECONDS.
	LOCAL elapsedTime IS 0.

	// The prediction of the closest approach, along the orbits. The miss vector goes from the target to the ship at that time.
	LOCAL approach IS LEXICON("Time", TIME:SECONDS, "Distance", 0).
	LOCAL missVector IS V(0,0,0).
	LOCAL lastApproachUT IS TIME:SECONDS - 1000.

	// Relative motion of the ship to the target, and the geometry of the approach. They are refreshed each pass.
	LOCAL targetPosition IS TARGET:POSITION.
	LOCAL targetVelocity IS SHIP:VELOCITY:ORBIT - targetOrbitable:VELOCITY:ORBIT.
	LOCAL targetSpeed IS targetVelocity:MAG.
	LOCAL targetDistance IS targetPosition:MAG.
	LOCAL chord IS targetPosition.					// from the ship to the predicted point of closest approach, relative to the target
	LOCAL distanceToStop IS 0.
	LOCAL missAngle IS 0.
	LOCAL tilt IS 0.

	// Ship performance. They are refreshed each pass, so a change of engine thrust limit, or a stage, is taken into account.
	LOCAL v_e IS g_0 * shipInfo["CurrentStage"]["Isp"].
	LOCAL aMax IS shipInfo["Maximum"]["Accel"].
	LOCAL aPlanned IS aMax.
	LOCAL brakeDist IS 0.
	LOCAL burnTime IS 0.
	LOCAL timeToIgnite IS 0.
	LOCAL currentMass IS shipInfo["CurrentStage"]["CurrentMass"].

	LOCAL steerVector IS -targetVelocity.
	LOCAL alignError IS 0.
	LOCAL throttleCommand IS 0.
	LOCAL limiterNote IS "".

	LOCAL engineLit IS FALSE.					// whether the main engines have been commanded on and are producing thrust
	LOCAL limitedIgnitions IS FALSE.			// whether any engine in use has a limited number of ignitions
	LOCAL minThrottle IS 0.						// the highest minimum throttle of the engines in use
	LOCAL throttleFloor IS 0.05.				// the lowest throttle that is commanded when burning
	LOCAL fixedThrust IS FALSE.					// whether the engines cannot be throttled down to the planned thrust
	LOCAL engineList IS LIST().					// for finding engines that have flamed out
	LOCAL everThrust IS FALSE.					// whether the engines of the current stage have been seen producing thrust
	LOCAL noThrustSince IS -1.
	LOCAL railsWarped IS FALSE.
	LOCAL warpOn IS FALSE.
	LOCAL ullageStart IS 0.
	LOCAL burnStartVelocity IS V(0,0,0).
	LOCAL trimFacing IS SHIP:FACING.
	LOCAL trimStart IS 0.
	LOCAL settledSince IS -1.
	LOCAL abortRequested IS FALSE.
	LOCAL previousMode IS "".
	LOCAL lastLogUT IS TIME:SECONDS - 1000.

	CLEARSCREEN.

	// the arrows start at the kOS processor, not at the ship's reference position, which is a few meters away from it
	LOCAL tgtPos IS VECDRAW(CORE:PART:POSITION, V(0,0,0), YELLOW, "Tgt Pos", 1.0, TRUE, 0.2).
	LOCAL tgtVel IS VECDRAW(CORE:PART:POSITION, V(0,0,0), RED, "Tgt Vel", 1.0, TRUE, 0.2).
	LOCAL shipFacing IS VECDRAW(CORE:PART:POSITION, V(0,0,0), BLUE, "Ship Facing", 1.0, TRUE, 0.2).
	LOCAL steerArrow IS VECDRAW(CORE:PART:POSITION, V(0,0,0), GREEN, "Steer", 1.0, TRUE, 0.2).

	IF connectionToKSC() LOG "Elapsed Time,Mode,Target Distance,Target Speed,Distance To Stop,Braking Distance,Time To Ignite,Miss Angle,Tilt,Throttle,Alignment Error,Max Accel,Mass,Closest Approach,,Ullage," + ullage + ",Standoff," + standoff TO "0:OrbitalRez.csv".

	SET mode TO "Waiting".

	UNTIL mode = "Done" {
		// stop if the operator asks, or if the target has been lost
		IF AG1 {
			SET abortRequested TO TRUE.
		} ELSE IF TERMINAL:INPUT:HASCHAR {
			IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:ENTER SET abortRequested TO TRUE.
		}
		IF abortRequested {
			SET mode TO "Done".
			SET loopMessage TO "Aborted. " + distanceToString(targetDistance, 1) + " from the target at " + ROUND(targetSpeed, 2) + " m/s".
		} ELSE IF NOT HASTARGET {
			SET mode TO "Done".
			SET loopMessage TO "Target lost!".
		}

		IF mode <> "Done" {
			updateShipInfoCurrent().

			// the ship: these follow staging and a change of the thrust limit
			SET currentMass TO shipInfo["CurrentStage"]["CurrentMass"].
			SET v_e TO g_0 * shipInfo["CurrentStage"]["Isp"].
			SET aMax TO MAX(shipInfo["Maximum"]["Accel"], 0.001).
			LOCAL lowestLimit IS 100.
			SET limitedIgnitions TO FALSE.
			SET minThrottle TO 0.
			FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
				IF eachEngine:THRUSTLIMIT < lowestLimit SET lowestLimit TO eachEngine:THRUSTLIMIT.
				IF eachEngine:IGNITIONS <> -1 SET limitedIgnitions TO TRUE.
				IF eachEngine:MINTHROTTLE > minThrottle SET minThrottle TO eachEngine:MINTHROTTLE.
			}
			SET fixedThrust TO minThrottle >= thrustFraction.
			SET throttleFloor TO MAX(minThrottle, 0.05).
			// an engine that cannot be throttled down plans the burn at its full acceleration, the others leave some for control
			IF fixedThrust SET aPlanned TO aMax.
			ELSE SET aPlanned TO thrustFraction * aMax.
			SET limiterNote TO "".
			IF lowestLimit < 100 SET limiterNote TO "Engine thrust limit is " + ROUND(lowestLimit, 1) + "%".

			// the geometry of the approach
			SET targetPosition TO TARGET:POSITION.
			SET targetVelocity TO SHIP:VELOCITY:ORBIT - targetOrbitable:VELOCITY:ORBIT.
			SET targetSpeed TO targetVelocity:MAG.
			SET targetDistance TO targetPosition:MAG.

			// the closest approach is searched for every so often and not on every pass, because the search is slow. It starts from
			// the previous result, or from where a straight line would have the closest approach.
			IF mode <> "Trim" AND TIME:SECONDS - lastApproachUT >= approachInterval {
				LOCAL guess IS TIME:SECONDS.
				IF approach["Time"] > TIME:SECONDS SET guess TO approach["Time"].
				ELSE IF targetSpeed > deadband SET guess TO TIME:SECONDS + MAX(VDOT(targetPosition, targetVelocity) / targetSpeed^2, 0).
				SET approach TO closestApproach(guess, 10).
				SET missVector TO POSITIONAT(SHIP, approach["Time"]) - POSITIONAT(targetOrbitable, approach["Time"]).
				SET lastApproachUT TO TIME:SECONDS.
			}
			SET chord TO missVector + targetPosition.
			SET distanceToStop TO MAX(chord:MAG - standoff, 0).

			// the burn: how far it takes, and when it has to start
			SET brakeDist TO brakeDistance(targetSpeed, v_e, aPlanned).
			SET burnTime TO brakeTime(targetSpeed, v_e, aPlanned).
			SET timeToIgnite TO 0.
			IF targetSpeed > deadband SET timeToIgnite TO (distanceToStop - brakeDist) / targetSpeed.

			// the direction of the burn: retrograde, offset by tiltGain times the angle between the (gravity-bent) path and the target
			SET steerVector TO -targetVelocity.
			SET missAngle TO 0.
			SET tilt TO 0.
			IF targetSpeed > deadband AND chord:MAG > 1 AND targetDistance > 1 {
				SET missAngle TO VANG(chord, targetPosition).
				IF missAngle > 0.01 {
					SET tilt TO MIN(tiltGain * missAngle, maxTilt).
					// ANGLEAXIS follows the left-handed coordinates, so the sense of the rotation is found by trying it: the
					// right one carries the direction away from the target toward the retrograde direction of the path.
					LOCAL tiltAxis IS VCRS(targetPosition, chord):NORMALIZED.
					IF VANG(ANGLEAXIS(missAngle / 2, tiltAxis) * (-targetPosition), -chord) > missAngle SET tiltAxis TO -tiltAxis.
					SET steerVector TO ANGLEAXIS(tilt, tiltAxis) * (-targetVelocity).
				}
			}

			SET throttleCommand TO 0.

			IF (mode = "Waiting") {
				SET globalSteer TO steerVector.
				IF NOT railsWarped {
					// warp close to the time of the burn
					SET railsWarped TO TRUE.
					IF timeToIgnite > warpLead + 10 {
						CLEARSCREEN.
						PRINT "Now warping close to the burn time.".
						warpToTime(TIME:SECONDS + timeToIgnite - warpLead).
						CLEARSCREEN.
						SET lastApproachUT TO TIME:SECONDS - 1000.
					}
				} ELSE IF timeToIgnite <= 0 AND NOT needUllage {
					SET mode TO "Burning".
					SET burnStartVelocity TO targetVelocity.
				} ELSE IF timeToIgnite <= ullage AND needUllage {
					SET mode TO "Ullage".
					SET ullageStart TO TIME:SECONDS.
					RCS ON.
					SET SHIP:CONTROL:FORE TO 1.
				}
			}

			// RCS fires forward to settle the propellant, then the main engines start
			IF (mode = "Ullage") {
				SET globalSteer TO steerVector.
				IF TIME:SECONDS - ullageStart >= ullage {
					SET SHIP:CONTROL:FORE TO 0.
					RCS OFF.
					SET mode TO "Burning".
					SET burnStartVelocity TO targetVelocity.
				}
			}

			IF (mode = "Burning") {
				SET globalSteer TO steerVector.
				// the throttle is the deceleration that stops the ship at the stop point, less what the tilt costs along the braking direction.
				// An engine that cannot be throttled down burns at full thrust.
				IF fixedThrust SET throttleCommand TO 1.
				ELSE {
					LOCAL decelerationNeeded IS targetSpeed^2 / (2 * MAX(distanceToStop, 1)).
					SET throttleCommand TO decelerationNeeded / (aMax * MAX(COS(tilt), 0.3)).
					// near the end the speed is cancelled smoothly, so that the burn does not overshoot zero
					SET throttleCommand TO MIN(throttleCommand, targetSpeed / (aMax * controlTime)).
					SET throttleCommand TO MAX(MIN(throttleCommand, 1), throttleFloor).
				}

				// start the burn only once the ship is pointing the right way. An engine that is already lit and has limited
				// ignitions is not shut down for a pointing error, and is kept at its minimum throttle or more.
				SET alignError TO VANG(SHIP:FACING:VECTOR, steerVector).
				IF alignError > alignLimit AND NOT (engineLit AND limitedIgnitions) SET throttleCommand TO 0.
				IF engineLit AND limitedIgnitions AND throttleCommand < throttleFloor SET throttleCommand TO throttleFloor.

				// drop spent stages. The checks are the ones that the launch script (GravTurnLaunch) makes: no thrust at all,
				// an engine that has flamed out, and empty tanks. The two that depend on the engines having worked wait until
				// the engines of the current stage have been seen producing thrust, so that a stage that has not started yet
				// is not dropped. The throttle is not touched, because shutting an engine down can use up an ignition.
				IF throttleCommand > 0 {
					LOCAL stageNow IS FALSE.
					LOCAL stageReason IS "".
					IF MAXTHRUST > 0 {
						SET everThrust TO TRUE.
						SET engineLit TO TRUE.
						SET noThrustSince TO -1.
					} ELSE IF everThrust {
						SET stageNow TO TRUE.
						SET stageReason TO "Staging from max thrust".
					}
					IF NOT stageNow {
						SET engineList TO LIST().
						LIST ENGINES IN engineList.
						FOR eng IN engineList {
							IF eng:FLAMEOUT AND eng:IGNITION {
								SET stageNow TO TRUE.
								SET stageReason TO "Staging from flameout".
								BREAK.
							}
						}
					}
					IF NOT stageNow AND everThrust AND shipInfo["CurrentStage"]["ResourceMass"] < 1.0 {
						SET stageNow TO TRUE.
						SET stageReason TO "Staging from resources".
					}
					IF stageNow {
						PRINT stageReason AT (0, 15).
						stageFunction().
						PRINT "                            " AT (0, 15).
						// the engines of the new stage have to be seen working before the next stage can be dropped
						SET everThrust TO FALSE.
						SET noThrustSince TO -1.
					} ELSE IF MAXTHRUST = 0 AND NOT everThrust {
						IF noThrustSince < 0 SET noThrustSince TO TIME:SECONDS.
						ELSE IF TIME:SECONDS - noThrustSince > 5 {
							SET mode TO "Done".
							SET loopMessage TO "Engines are not producing thrust!".
						}
					}
				}

				// finished: the relative speed is nearly zero, or it has turned around
				IF mode = "Burning" AND (targetSpeed < stopSpeed OR VDOT(targetVelocity, burnStartVelocity) < 0) {
					IF trimWithRCS AND targetSpeed > deadband AND shipInfo["CurrentStage"]["RCS"]:LENGTH > 0 {
						SET mode TO "Trim".
						SET trimFacing TO SHIP:FACING.
						SET trimStart TO TIME:SECONDS.
						SET settledSince TO -1.
					} ELSE {
						SET mode TO "Done".
						SET loopMessage TO "Relative velocity cancelled: " + distanceToString(targetDistance, 1) + " from the target, " + ROUND(targetSpeed, 2) + " m/s relative".
					}
				}
			}

			// the last of the velocity is nulled with RCS thrusters, along the ship's axes
			IF (mode = "Trim") {
				SET globalSteer TO trimFacing.
				RCS ON.
				SET SHIP:CONTROL:FORE TO MAX(-1, MIN(1, -VDOT(targetVelocity, SHIP:FACING:FOREVECTOR))).
				SET SHIP:CONTROL:STARBOARD TO MAX(-1, MIN(1, -VDOT(targetVelocity, SHIP:FACING:STARVECTOR))).
				SET SHIP:CONTROL:TOP TO MAX(-1, MIN(1, -VDOT(targetVelocity, SHIP:FACING:TOPVECTOR))).
				IF targetSpeed < deadband {
					IF settledSince < 0 SET settledSince TO TIME:SECONDS.
				} ELSE SET settledSince TO -1.
				IF (settledSince >= 0 AND TIME:SECONDS - settledSince > 2) OR TIME:SECONDS - trimStart > 30 {
					SET mode TO "Done".
					SET loopMessage TO "Relative velocity cancelled: " + distanceToString(targetDistance, 1) + " from the target, " + ROUND(targetSpeed, 2) + " m/s relative".
				}
			}

			// physics warp while the burn is a long way off, or a long one
			IF physicsWarpPerm {
				LOCAL wantWarp IS FALSE.
				IF mode = "Waiting" SET wantWarp TO railsWarped AND timeToIgnite > 20 + ullage.
				ELSE IF mode = "Burning" SET wantWarp TO burnTime > 10.
				IF wantWarp AND NOT warpOn {
					SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
					SET KUNIVERSE:TIMEWARP:WARP TO physicsWarpPerm.
					SET warpOn TO TRUE.
				} ELSE IF NOT wantWarp AND warpOn {
					SET KUNIVERSE:TIMEWARP:WARP TO 0.
					SET warpOn TO FALSE.
				}
			}

			IF mode <> "Burning" SET throttleCommand TO 0.
			IF throttleCommand = 0 SET engineLit TO FALSE.
			IF mode = "Done" SET globalSteer TO steerVector.
			SET globalThrottle TO throttleCommand.

			PRINT "Mode " + mode + "     " AT (0, 0).
			PRINT "Burn Time: " + timeToString(burnTime) + "    " AT (0, 1).
			PRINT "Time To Ignition: " + timeToString(timeToIgnite) + "    " AT (0, 2).
			PRINT "Closest Approach: " + distanceToString(approach["Distance"], 2) + " in " + timeToString(approach["Time"] - TIME:SECONDS) + "   " AT (0, 3).
			PRINT "Braking Distance: " + distanceToString(brakeDist, 2) + "    " AT (0, 4).
			PRINT "Distance To Stop: " + distanceToString(distanceToStop, 2) + "    " AT (0, 5).
			PRINT "Target Velocity: " + distanceToString(targetSpeed, 1) + "/s  " AT (0, 6).
			PRINT "Target Distance: " + distanceToString(targetDistance, 2) + "   " AT (0, 7).
			PRINT "Path Angle / Tilt: " + ROUND(missAngle, 2) + " / " + ROUND(tilt, 1) + " deg    " AT (0, 8).
			PRINT "Throttle: " + ROUND(throttleCommand, 2) + "  Pointing Error: " + ROUND(alignError, 1) + " deg    " AT (0, 9).
			IF needUllage PRINT "Ullage: " + ullage + " s with RCS      " AT (0, 10).
			ELSE PRINT "No ullage                    " AT (0, 10).
			IF fixedThrust PRINT "Burn planned at 100% thrust    " AT (0, 11).
			ELSE PRINT "Burn planned at " + ROUND(100 * thrustFraction) + "% thrust    " AT (0, 11).
			PRINT limiterNote + "                              " AT (0, 12).
			PRINT "AG1 or ENTER aborts." AT (0, 13).

			SET tgtPos:START TO CORE:PART:POSITION.
			SET tgtVel:START TO CORE:PART:POSITION.
			SET shipFacing:START TO CORE:PART:POSITION.
			SET steerArrow:START TO CORE:PART:POSITION.
			SET tgtPos:VEC TO targetPosition:NORMALIZED * 10.
			IF targetSpeed > 0.001 SET tgtVel:VEC TO -targetVelocity:NORMALIZED * 10.
			SET shipFacing:VEC TO SHIP:FACING:FOREVECTOR * 10.
			SET steerArrow:VEC TO steerVector:NORMALIZED * 10.

			// log once a second, and when the mode changes
			IF connectionToKSC() AND (TIME:SECONDS - lastLogUT >= 1 OR mode <> previousMode) {
				LOG elapsedTime + "," + mode + "," + targetDistance + "," + targetSpeed + "," + distanceToStop + "," + brakeDist + "," + timeToIgnite + "," + missAngle + "," + tilt + "," + throttleCommand + "," + alignError + "," + aMax + "," + currentMass + "," + approach["Distance"] TO "0:OrbitalRez.csv".
				SET lastLogUT TO TIME:SECONDS.
			}
			SET previousMode TO mode.
			SET elapsedTime TO TIME:SECONDS - startTime.
		}
		WAIT 0.
	}

	// let go of everything, and put the ship's switches back as they were
	SET globalThrottle TO 0.
	SET SHIP:CONTROL:FORE TO 0.
	SET SHIP:CONTROL:STARBOARD TO 0.
	SET SHIP:CONTROL:TOP TO 0.
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
	SET RCS TO oldRCS.
	SET SAS TO oldSAS.
	SET tgtPos:SHOW TO FALSE.
	SET tgtVel:SHOW TO FALSE.
	SET shipFacing:SHOW TO FALSE.
	SET steerArrow:SHOW TO FALSE.
}
setLockedSteering(FALSE).
setLockedThrottle(FALSE).
