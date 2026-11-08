@LAZYGLOBAL OFF.

// OrbitalRez: cancels the velocity relative to the target in a single burn, for two vessels on a near-collision course. The
// ship is stopped a standoff distance from the target. The burn is refused if the geometry or the ship cannot manage it.
//
// Passed the following:
//   ullage       (scalar, seconds the RCS fires forward before ignition. Only used when isStock is FALSE (an engine needs ullage or has limited ignitions).)
//   standoff     (scalar, meters from the target where the ship is brought to a stop.)
PARAMETER ullage IS 5.
PARAMETER standoff IS 50.

LOCAL mode IS "Error".

// Constants of the guidance
LOCAL thrustFraction IS 0.95.			// of the maximum acceleration, what the burn is planned with when the throttle can vary
LOCAL tiltGain IS 2.					// the thrust is offset from retrograde by this times the angle between the path and the target
LOCAL maxTilt IS 60.					// degrees, the most the thrust is offset from retrograde
LOCAL tiltMinSpeed IS 5.				// m/s, no offset at or below this relative speed, it would only jitter
LOCAL tiltMinDistance IS 150.			// m, no offset at or closer than this to the target
LOCAL tiltFullDistance IS 300.			// m, the offset fades in from tiltMinDistance to here (and from tiltMinSpeed to twice it)
LOCAL alignLimit IS 5.					// degrees, no engine start while pointing further than this from the burn direction
LOCAL finalAlignLimit IS 30.			// degrees, once burning, a larger pointing error reduces the throttle but never cuts it
LOCAL controlTime IS 1.					// s, near the end the throttle is the one that cancels the speed in this long
LOCAL stopSpeed IS 0.2.					// m/s, the burn is over below this relative speed
LOCAL deadband IS 0.05.					// m/s, smaller speeds are ignored
LOCAL approachInterval IS 3.			// s between searches for the closest approach, which is slow
LOCAL warpLead IS MAX(90, ullage).		// s, the first warp stops this long before the burn (or ullage) starts
LOCAL refuseSlack IS 1.05.			// ratio, how far past what is possible a burn can be planned before it is refused
LOCAL maxScanTime IS 1000000.			// s, how far ahead the closest approach is searched for on an orbit that does not repeat (a hyperbolic one)
LOCAL stagePause IS 2.				// s, how long the ship coasts while a spent stage is dropped and the next one starts
LOCAL needUllage IS ullage > 0 AND NOT isStock().	// whether RCS settles the propellant before each ignition, the first and those after staging
LOCAL awaySpeed IS 2.				// m/s, at or below this relative speed the ship is not counted as moving away from the target, which would only be noise

// Finds the closest approach to the target within one orbit (maxScanTime on a hyperbolic one),
// or until the next change of orbit of either ship. The distance has a dip each
// time the two ships are near one another, so refining from now would settle on the nearest dip. So the distance is sampled
// first, the earliest dip nearly as deep as the deepest is taken, and only that is refined.
// Passed the following:
//   relativeSpeed (scalar, m/s, the present relative speed. It sets what counts as nearly as deep as the deepest dip.)
// Returns the same lexicon as closestApproach, and "Found" (FALSE if the distance is still falling when the search ends, so that
// the end of the search is not a closest approach) and "Horizon" (s, how far ahead the search looked).
LOCAL FUNCTION scanForApproach {
	PARAMETER relativeSpeed.
	LOCAL horizon IS maxScanTime.
	IF SHIP:ORBIT:ECCENTRICITY < 1 SET horizon TO SHIP:ORBIT:PERIOD.
	IF SHIP:ORBIT:HASNEXTPATCH SET horizon TO MIN(horizon, SHIP:ORBIT:NEXTPATCHETA).
	IF TARGET:ORBIT:HASNEXTPATCH SET horizon TO MIN(horizon, TARGET:ORBIT:NEXTPATCHETA).
	SET horizon TO MAX(horizon, 10).
	// whether the search stops short of a whole orbit. A bound orbit that is searched all the way round has nowhere to run out.
	LOCAL windowCut IS TRUE.
	IF SHIP:ORBIT:ECCENTRICITY < 1 SET windowCut TO horizon < SHIP:ORBIT:PERIOD.
	// a long search gets more samples, which are then far apart in time
	LOCAL samples IS MAX(300, MIN(600, ROUND(horizon / 600))).
	LOCAL step IS horizon / samples.
	LOCAL startUT IS TIME:SECONDS.
	LOCAL distances IS LIST().
	LOCAL smallest IS -1.
	FROM {LOCAL index IS 0.} UNTIL index > samples STEP {SET index TO index + 1.} DO {
		LOCAL separation IS (POSITIONAT(SHIP, startUT + index * step) - POSITIONAT(TARGET, startUT + index * step)):MAG.
		distances:ADD(separation).
		IF smallest < 0 OR separation < smallest SET smallest TO separation.
	}
	// the samples are a step apart, so a dip can be missed by as much as the ships move in half of it
	LOCAL acceptable IS 1.5 * smallest + relativeSpeed * step.
	LOCAL chosen IS 0.
	FROM {LOCAL index IS 0.} UNTIL index > samples STEP {SET index TO index + 1.} DO {
		LOCAL isDip IS (index = 0 OR distances[index] <= distances[index - 1]) AND (index = samples OR distances[index] <= distances[index + 1]).
		IF isDip AND distances[index] <= acceptable {
			SET chosen TO index.
			BREAK.
		}
	}
	// still falling at the end of the search: the dip is the edge of the search, and the real closest approach is further out
	IF windowCut AND chosen = samples AND distances[samples] < distances[samples - 1] {
		RETURN LEXICON("Time", startUT + horizon, "Distance", distances[samples], "Found", FALSE, "Horizon", horizon).
	}
	LOCAL result IS closestApproach(startUT + chosen * step, step / 4).
	SET result["Found"] TO TRUE.
	SET result["Horizon"] TO horizon.
	RETURN result.
}

// Plans the braking from a speed, with the stages burning in turn. Each stage burns its remaining delta V, and what is left of the
// speed goes to the next stage, with that stage's own thrust, exhaust velocity and mass. The ship coasts for stagePause between stages,
// and for the ullage as well when needUllage.
// burnTime and burnDistance are the library's. They use the mass and the mass flow only as a ratio, v_e / acceleration, so those two
// are passed in their place. burnDistance is for thrust along the direction of travel, so v_e is negated for braking.
// Assumes that updateShipInfoCurrent has been run recently.
// Passed the following:
//   speed (scalar, m/s, the relative speed to cancel)
//   tiltFactor (scalar, the cosine of the tilt, the part of the thrust that brakes)
//   fraction (scalar, the part of the maximum thrust to plan with. -1 uses thrustFraction, or 1 for stages that cannot be throttled down.)
// Returns a lexicon of the following:
//   "Distance" (scalar, m, travelled while braking)
//   "Time" (scalar, s)
//   "Stages" (scalar, the number of stages that burn)
//   "Fixed" (boolean, whether any stage that burns cannot be throttled down)
//   "SpeedLeft" (scalar, m/s, what the stages cannot cancel)
LOCAL FUNCTION brakePlan {
	PARAMETER speed.
	PARAMETER tiltFactor IS 1.
	PARAMETER fraction IS -1.
	LOCAL speedLeft IS speed.
	LOCAL distance IS 0.
	LOCAL duration IS 0.
	LOCAL stagesUsed IS 0.
	LOCAL anyFixed IS FALSE.
	LOCAL gap IS stagePause.
	IF needUllage SET gap TO stagePause + ullage.
	FROM {LOCAL stageNumber IS shipInfo["NumberOfStages"] - 1.} UNTIL stageNumber < 0 OR speedLeft <= deadband STEP {SET stageNumber TO stageNumber - 1.} DO {
		LOCAL info IS shipInfo["Stage " + stageNumber].
		IF info["Thrust"] > 0 AND info["Isp"] > 0 AND info["DeltaV"] > deadband {
			LOCAL stageFixed IS NOT info["Throttleable"] OR info["HighestMinThrottle"] >= thrustFraction.
			LOCAL planned IS thrustFraction.
			IF stageFixed SET planned TO 1.
			IF fraction >= 0 SET planned TO fraction.
			IF stageFixed SET anyFixed TO TRUE.
			LOCAL exhaustVelocity IS g_0 * info["Isp"].
			LOCAL acceleration IS planned * info["Thrust"] / info["CurrentMass"] * tiltFactor.
			LOCAL brakeSpeed IS MIN(speedLeft, info["DeltaV"] * tiltFactor).
			LOCAL stageTime IS burnTime(exhaustVelocity, acceleration, brakeSpeed, exhaustVelocity).
			SET distance TO distance + burnDistance(0, speedLeft, -exhaustVelocity, exhaustVelocity, acceleration, stageTime).
			SET duration TO duration + stageTime.
			SET speedLeft TO speedLeft - brakeSpeed.
			SET stagesUsed TO stagesUsed + 1.
			IF speedLeft > deadband {
				SET distance TO distance + speedLeft * gap.
				SET duration TO duration + gap.
			}
		}
	}
	RETURN LEXICON("Distance", distance, "Time", duration, "Stages", stagesUsed, "Fixed", anyFixed, "SpeedLeft", speedLeft).
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
	IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") SET errorMessage TO "Error! Target is a part, not a vessel or body.".
	ELSE {
		IF targetOrbitable:BODY:NAME <> SHIP:BODY:NAME SET errorMessage TO "Error! Target orbits " + targetOrbitable:BODY:NAME + ", not " + SHIP:BODY:NAME + ".".
		IF shipInfo["CurrentStage"]["Isp"] = 0 SET errorMessage TO "Error! Isp is zero!".
		IF shipInfo["CurrentStage"]["ENGINES"]:LENGTH = 0 SET errorMessage TO "Error! No engines in the current stage.".
	}
	IF errorMessage = "" {
		LOCAL relativeSpeed IS (SHIP:VELOCITY:ORBIT - targetOrbitable:VELOCITY:ORBIT):MAG.
		IF VANG(shipInfo["CurrentStage"]["Engines"][0]:FACING:VECTOR, SHIP:FACING:VECTOR) > 45 SET errorMessage TO "Error! Engines point " + ROUND(VANG(shipInfo["CurrentStage"]["Engines"][0]:FACING:VECTOR, SHIP:FACING:VECTOR)) + " deg off the ship's facing.".
		IF relativeSpeed < stopSpeed SET errorMessage TO "Error! Already at rest: " + ROUND(relativeSpeed, 2) + " m/s relative.".
	}
	IF errorMessage <> "" {
		SET mode TO "Done".
		SET loopMessage TO errorMessage.
	}
}

IF (mode <> "Done") {
	LOCAL oldRCS IS RCS.
	LOCAL oldSAS IS SAS.

	SET globalSteer TO SHIP:FACING.
	SET globalThrottle TO 0.
	setLockedSteering(TRUE).
	setLockedThrottle(TRUE).

	SAS OFF.
	RCS OFF.
	AG1 OFF.

	LOCAL startTime IS TIME:SECONDS.
	LOCAL elapsedTime IS 0.

	// the predicted closest approach, along the orbits. The miss vector goes from the target to the ship then.
	LOCAL approach IS LEXICON("Time", TIME:SECONDS, "Distance", 0).
	LOCAL missVector IS V(0,0,0).
	LOCAL lastApproachUT IS TIME:SECONDS - 1000.
	LOCAL scanned IS FALSE.							// whether the whole orbit has been searched yet
	LOCAL approachFound IS TRUE.					// whether the last full search found a closest approach, and not just the end of the search
	LOCAL scanHorizon IS 0.							// s, how far ahead the last full search looked
	LOCAL approachSpeed IS 0.						// the speed relative to the target at the closest approach
	LOCAL ignitionUT IS TIME:SECONDS.				// when the burn has to start
	LOCAL ignitionSpeed IS 0.						// the speed relative to the target then

	// relative motion and the geometry of the approach, refreshed each pass
	LOCAL targetPosition IS TARGET:POSITION.
	LOCAL targetVelocity IS SHIP:VELOCITY:ORBIT - targetOrbitable:VELOCITY:ORBIT.
	LOCAL targetSpeed IS targetVelocity:MAG.
	LOCAL targetDistance IS targetPosition:MAG.
	LOCAL chord IS targetPosition.					// from the ship to the predicted point of closest approach, relative to the target
	LOCAL distanceToStop IS 0.
	LOCAL missAngle IS 0.
	LOCAL tilt IS 0.

	// ship performance, refreshed each pass to follow staging and thrust limit changes
	LOCAL aMax IS shipInfo["Maximum"]["Accel"].
	LOCAL plan IS LEXICON("Distance", 0, "Time", 0, "Stages", 1, "Fixed", FALSE, "SpeedLeft", 0).	// the braking plan from brakePlan
	LOCAL expectedTilt IS 0.					// degrees, the tilt that the plan expects at ignition
	LOCAL movingAway IS FALSE.					// whether the burn has started and the ship is going away from the target, which it has passed
	LOCAL brakeDist IS 0.
	LOCAL burnDuration IS 0.						// s, how long the burn takes
	LOCAL timeToIgnite IS 0.
	LOCAL currentMass IS shipInfo["CurrentStage"]["CurrentMass"].

	LOCAL steerVector IS -targetVelocity.
	LOCAL alignError IS 0.
	LOCAL throttleCommand IS 0.
	LOCAL limiterNote IS "".

	LOCAL engineLit IS FALSE.					// whether the main engines have been commanded on and are producing thrust
	LOCAL minThrottle IS 0.						// the highest minimum throttle of the engines in use
	LOCAL throttleFloor IS 0.05.				// the lowest throttle that is commanded when burning
	LOCAL fixedThrust IS FALSE.					// whether the engines cannot be throttled down to the planned thrust
	LOCAL everThrust IS FALSE.					// whether the engines of the current stage have been seen producing thrust
	LOCAL noThrustSince IS -1.
	LOCAL railsWarped IS FALSE.
	LOCAL warpOn IS FALSE.
	LOCAL ullageStart IS 0.
	LOCAL stageUllageStart IS -1.				// UT when the ullage before staging began, -1 when there is none
	LOCAL burnStartVelocity IS V(0,0,0).
	LOCAL ignited IS FALSE.						// whether the engines have been started, after which the pointing error no longer cuts the throttle
	LOCAL abortRequested IS FALSE.
	LOCAL previousMode IS "".
	LOCAL lastLogUT IS TIME:SECONDS - 1000.

	CLEARSCREEN.

	// the arrows start at the kOS processor, not the ship's reference position, a few meters away
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
			SET aMax TO MAX(shipInfo["Maximum"]["Accel"], 0.001).
			LOCAL lowestLimit IS shipInfo["CurrentStage"]["LowestThrustLimit"].
			SET minThrottle TO shipInfo["CurrentStage"]["HighestMinThrottle"].
			SET fixedThrust TO NOT shipInfo["CurrentStage"]["Throttleable"] OR minThrottle >= thrustFraction.
			SET throttleFloor TO MAX(minThrottle, 0.05).
			SET limiterNote TO "".
			IF lowestLimit < 100 SET limiterNote TO "Engine thrust limit is " + ROUND(lowestLimit, 1) + "%".

			// the geometry of the approach
			SET targetPosition TO TARGET:POSITION.
			SET targetVelocity TO SHIP:VELOCITY:ORBIT - targetOrbitable:VELOCITY:ORBIT.
			SET targetSpeed TO targetVelocity:MAG.
			SET targetDistance TO targetPosition:MAG.
			SET movingAway TO mode = "Burning" AND VDOT(targetPosition, targetVelocity) < 0 AND targetSpeed > awaySpeed.

			// the closest approach is searched for every so often, because the search is slow. The first search covers the whole orbit.
			// After that it refines the previous result, unless that has gone by before the burn, which searches again.
			IF TIME:SECONDS - lastApproachUT >= approachInterval {
				IF NOT scanned OR (approach["Time"] < TIME:SECONDS AND mode <> "Burning") {
					SET approach TO scanForApproach(targetSpeed).
					SET scanned TO TRUE.
						SET approachFound TO approach["Found"].
						SET scanHorizon TO approach["Horizon"].
				} ELSE {
					// the last answer is close, by about as much as it can have moved since, so the search starts with a smaller step and ends sooner
					LOCAL refineStep IS MAX(1, MIN(10, 2 * (TIME:SECONDS - lastApproachUT))).
					SET approach TO closestApproach(MAX(approach["Time"], TIME:SECONDS), refineStep, "", 12).
				}
				SET lastApproachUT TO TIME:SECONDS.

				// when the burn has to start: planDistance before the closest approach, at the speed the ships will have then. The time comes
				// from the predicted time of the closest approach, not from the distance and the present speed, which is only right for a
				// short straight path. planDistance is the larger of what the thrust needs (the standoff plus the braking distance from brakePlan,
				// which burns the stages in turn and allows for the tilt) and what the tilt needs (the path must be long enough that tiltGain
				// times the miss angle stays within maxTilt).
				SET approachSpeed TO (VELOCITYAT(SHIP, approach["Time"]):ORBIT - VELOCITYAT(targetOrbitable, approach["Time"]):ORBIT):MAG.
				SET ignitionSpeed TO approachSpeed.
				SET ignitionUT TO approach["Time"].
				SET expectedTilt TO 0.
				LOCAL tiltDistance IS approach["Distance"] / TAN(maxTilt / tiltGain).
				LOCAL thrustDistance IS standoff.
				LOCAL planDistance IS standoff.
				FROM {LOCAL pass IS 0.} UNTIL pass >= 3 STEP {SET pass TO pass + 1.} DO {
					SET plan TO brakePlan(ignitionSpeed, COS(expectedTilt)).
					SET planDistance TO MAX(standoff + plan["Distance"], tiltDistance).
					SET expectedTilt TO MIN(tiltGain * ARCTAN(approach["Distance"] / planDistance), maxTilt).
					SET plan TO brakePlan(ignitionSpeed, COS(expectedTilt)).
					SET thrustDistance TO standoff + plan["Distance"].
					SET planDistance TO MAX(thrustDistance, tiltDistance).
					SET ignitionUT TO approach["Time"] - planDistance / MAX((ignitionSpeed + approachSpeed) / 2, deadband).
					LOCAL ignitionTime IS MAX(ignitionUT, TIME:SECONDS).
					SET ignitionSpeed TO (VELOCITYAT(SHIP, ignitionTime):ORBIT - VELOCITYAT(targetOrbitable, ignitionTime):ORBIT):MAG.
				}

				// whether the burn can be done at all. It is checked before the burn starts, while it can still be refused.
				IF mode = "Waiting" {
					LOCAL refusal IS "".
					IF NOT approachFound SET refusal TO "No closest approach within " + timeToString(scanHorizon) + ", still closing.".
					ELSE IF approach["Time"] <= TIME:SECONDS SET refusal TO "Closest approach has passed, moving apart.".
					ELSE IF ignitionUT < TIME:SECONDS {
						// the burn should have started already, so the path that is left has to be stopped in with all of the thrust there is
						LOCAL pathLeft IS MAX((approach["Time"] - TIME:SECONDS) * (targetSpeed + approachSpeed) / 2, 1).
						LOCAL lateTilt IS tiltGain * ARCTAN(approach["Distance"] / pathLeft).
						LOCAL lateBrake IS brakePlan(targetSpeed, COS(MIN(lateTilt, maxTilt)), 1).
						IF lateTilt > maxTilt SET refusal TO "Too late: a " + distanceToString(approach["Distance"], 1) + " miss in " + distanceToString(pathLeft, 1) + " needs over " + maxTilt + " deg tilt.".
						ELSE IF lateBrake["Distance"] > MAX(pathLeft - standoff, 1) * refuseSlack SET refusal TO "Too late: stopping from " + ROUND(targetSpeed, 1) + " m/s needs " + distanceToString(lateBrake["Distance"], 1) + " at full thrust, " + distanceToString(pathLeft, 1) + " left.".
					} ELSE IF plan["Fixed"] {
						// full thrust cannot be reduced, so a burn that has to start earlier than it needs would stop short
						IF planDistance > thrustDistance * refuseSlack SET refusal TO "Cannot throttle down: the miss needs a start " + distanceToString(planDistance, 1) + " out, full thrust needs " + distanceToString(thrustDistance, 1) + ".".
					} ELSE {
						LOCAL neededThrottle IS thrustFraction * plan["Distance"] / MAX(planDistance - standoff, 1).
						IF neededThrottle < throttleFloor SET refusal TO "Cannot throttle down: burn needs " + ROUND(100 * neededThrottle, 1) + "% throttle, engines go to " + ROUND(100 * throttleFloor) + "%.".
					}
					// the tilt makes the burn cost 1 / COS(tilt) times the speed
					IF refusal = "" AND ignitionSpeed * 1.1 / COS(expectedTilt) > shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"] SET refusal TO "Delta V: burn needs " + ROUND(ignitionSpeed * 1.1 / COS(expectedTilt)) + " m/s (with tilt, 10%), have " + ROUND(shipInfo["Stage 0"]["DeltaVPrev"] + shipInfo["Stage 0"]["DeltaV"]) + ".".
					IF refusal = "" AND plan["SpeedLeft"] > 1 SET refusal TO "Engine stages leave " + ROUND(plan["SpeedLeft"], 1) + " m/s uncancelled.".
					IF refusal <> "" {
						SET mode TO "Done".
						SET loopMessage TO refusal.
					}
				}
			}
			// the search gives only the time of the closest approach. The miss then is worked out every pass, because the burn changes it
			// continuously and a held value makes the steering jump when it updates.
			IF approach["Time"] > TIME:SECONDS SET missVector TO POSITIONAT(SHIP, approach["Time"]) - POSITIONAT(targetOrbitable, approach["Time"]).
			SET chord TO missVector + targetPosition.
			// the distance left is the distance to the target less the standoff. The chord to the predicted closest approach is not used,
			// because that point moves back toward the ship as it brakes, which made the throttle swing. The steering brings the miss to
			// zero, so the burn ends at the standoff from the target.
			SET distanceToStop TO MAX(targetDistance - standoff, 0).

			// the burn: how far it takes. Once the engines are lit it is planned again on each pass, from what is left of the speed and of the stages.
			IF mode = "Burning" SET plan TO brakePlan(targetSpeed, COS(tilt)).
			SET burnDuration TO plan["Time"].
			SET brakeDist TO plan["Distance"].
			SET timeToIgnite TO ignitionUT - TIME:SECONDS.

			// the direction of the burn: retrograde, offset by tiltGain times the angle between the (gravity-bent) path and the target
			SET steerVector TO -targetVelocity.
			SET missAngle TO 0.
			SET tilt TO 0.
			// the offset fades out toward the end, where the direction of the relative velocity changes faster than the ship can turn,
			// and losing it suddenly would be a sudden turn.
			LOCAL distanceFade IS MAX(MIN((targetDistance - tiltMinDistance) / (tiltFullDistance - tiltMinDistance), 1), 0).
			LOCAL speedFade IS MAX(MIN((targetSpeed - tiltMinSpeed) / tiltMinSpeed, 1), 0).
			IF MIN(distanceFade, speedFade) > 0 AND chord:MAG > 1 AND NOT movingAway {
				SET missAngle TO VANG(chord, targetPosition).
				IF missAngle > 0.01 {
					SET tilt TO MIN(tiltGain * missAngle, maxTilt) * MIN(distanceFade, speedFade).
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
						// show what was found for a few seconds before the warp, which cannot be interrupted, so that a wrong
						// closest approach can be caught
						CLEARSCREEN.
						PRINT "Closest approach found: " + distanceToString(approach["Distance"], 2) + ", in " + timeToString(approach["Time"] - TIME:SECONDS) + "   " AT (0, 0).
						PRINT "Relative speed then: " + distanceToString(approachSpeed, 1) + "/s   " AT (0, 1).
						PRINT "The burn starts in " + timeToString(timeToIgnite) + " and takes " + timeToString(burnDuration) + "   " AT (0, 2).
						PRINT "Warping in 5 seconds. AG1 or ENTER aborts." AT (0, 4).
						LOCAL showUntil IS TIME:SECONDS + 5.
						UNTIL TIME:SECONDS >= showUntil OR AG1 OR abortRequested {
							IF TERMINAL:INPUT:HASCHAR {
								IF TERMINAL:INPUT:GETCHAR() = TERMINAL:INPUT:ENTER SET abortRequested TO TRUE.
							}
							WAIT 0.
						}
						IF AG1 OR abortRequested SET abortRequested TO TRUE.
						ELSE {
							CLEARSCREEN.
							PRINT "Now warping close to the burn time.".
							warpToTime(TIME:SECONDS + timeToIgnite - warpLead).
							CLEARSCREEN.
							SET lastApproachUT TO TIME:SECONDS - 1000.
						}
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
				// the throttle is the planned part of the thrust, scaled by how the distance that the plan needs (the stages in turn, and the tilt)
				// compares with the distance left. An engine that cannot be throttled down burns at full thrust, and so does a ship that is
				// moving away from the target, which has gone past it.
				IF fixedThrust OR movingAway SET throttleCommand TO 1.
				ELSE {
					SET throttleCommand TO thrustFraction * brakeDist / MAX(distanceToStop, 1).
					// near the end the speed is cancelled smoothly, so that the burn does not overshoot zero
					SET throttleCommand TO MIN(throttleCommand, targetSpeed / (aMax * controlTime)).
					SET throttleCommand TO MAX(MIN(throttleCommand, 1), throttleFloor).
				}

				// start only once the ship points the right way. After that a pointing error only reduces the throttle, because an engine
				// that has been shut down may not start again. A lit engine with limited ignitions stays at its minimum throttle or more.
				SET alignError TO VANG(SHIP:FACING:VECTOR, steerVector).
				IF ignited {
					IF alignError > finalAlignLimit SET throttleCommand TO MAX(throttleCommand * MAX(COS(alignError), 0), throttleFloor).
				} ELSE IF alignError > alignLimit SET throttleCommand TO 0.
				IF throttleCommand > 0 SET ignited TO TRUE.
				IF engineLit AND shipInfo["CurrentStage"]["LimitedIgnitions"] AND throttleCommand < throttleFloor SET throttleCommand TO throttleFloor.

				// drop spent stages (stageIfNeeded). The no-thrust and empty-tank checks wait until the stage has been seen producing
				// thrust, so that a stage that has not started is not dropped. The throttle is not touched, because shutting an engine
				// down can use up an ignition. With ullage, the ship coasts with RCS firing forward first, and the stage is dropped
				// (and the next one lit) with the RCS still on.
				IF stageUllageStart >= 0 {
					SET throttleCommand TO 0.
					IF TIME:SECONDS - stageUllageStart >= ullage {
						LOCAL stageReason IS stageIfNeeded(everThrust).
						SET SHIP:CONTROL:FORE TO 0.
						RCS OFF.
						SET stageUllageStart TO -1.
						IF stageReason <> "None" PRINT "Staged from " + stageReason + "          " AT (0, 15).
						SET everThrust TO FALSE.
						SET noThrustSince TO -1.
					}
				} ELSE IF throttleCommand > 0 {
					IF MAXTHRUST > 0 {
						SET everThrust TO TRUE.
						SET engineLit TO TRUE.
						SET noThrustSince TO -1.
					}
					LOCAL stageReason IS stageIfNeeded(everThrust, NOT needUllage).
					IF stageReason <> "None" AND needUllage {
						SET stageUllageStart TO TIME:SECONDS.
						RCS ON.
						SET SHIP:CONTROL:FORE TO 1.
						SET throttleCommand TO 0.
					} ELSE IF stageReason <> "None" {
						PRINT "Staged from " + stageReason + "          " AT (0, 15).
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
					SET mode TO "Done".
					SET loopMessage TO "Relative velocity cancelled: " + distanceToString(targetDistance, 1) + " from the target, " + ROUND(targetSpeed, 2) + " m/s relative".
				}
			}

			// physics warp while the burn is a long way off, or a long one
			IF physicsWarpPerm {
				LOCAL wantWarp IS FALSE.
				IF mode = "Waiting" SET wantWarp TO railsWarped AND timeToIgnite > 20 + ullage.
				ELSE IF mode = "Burning" SET wantWarp TO burnDuration > 10.
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
			PRINT "Burn Time: " + timeToString(burnDuration) + "    " AT (0, 1).
			PRINT "Time To Ignition: " + timeToString(timeToIgnite) + "    " AT (0, 2).
			PRINT "Closest Approach: " + distanceToString(missVector:MAG, 2) + " in " + timeToString(approach["Time"] - TIME:SECONDS) + "   " AT (0, 3).
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
			PRINT "Speed At Closest Approach: " + distanceToString(approachSpeed, 1) + "/s    " AT (0, 14).
			PRINT "Braking stages: " + plan["Stages"] + "    " AT (0, 16).
			IF stageUllageStart >= 0 PRINT "Ullage before staging          " AT (0, 17).
			ELSE PRINT "                                " AT (0, 17).

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
				LOG elapsedTime + "," + mode + "," + targetDistance + "," + targetSpeed + "," + distanceToStop + "," + brakeDist + "," + timeToIgnite + "," + missAngle + "," + tilt + "," + throttleCommand + "," + alignError + "," + aMax + "," + currentMass + "," + missVector:MAG TO "0:OrbitalRez.csv".
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
