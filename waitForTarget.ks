@LAZYGLOBAL OFF.
CLEARSCREEN.
PARAMETER offset IS 5.

FUNCTION helperFunction
{
	LOCAL targetDistance IS offset.
	LOCAL maxWarpRate IS 10000.

	LOCAL startTime IS TIME:SECONDS.
	LOCAL startNegative IS FALSE.
	LOCAL newDistance IS distanceToTargetOrbitalPlane().
	LOCAL newTime IS TIME:SECONDS.
	LOCAL oldDistance IS newDistance.
	LOCAL oldTime IS newTime.

	IF newDistance < 0 SET targetDistance TO -targetDistance.

	LOCAL distanceRate IS 1.
	LOCAL realTimeLeft IS 10.
	LOCAL completedScans IS 0.
	LOCAL startPower IS 0.
	LOCAL RESLIST IS 0.
	LIST RESOURCES IN RESLIST.
	FOR RES IN RESLIST {
		IF RES:NAME = "ElectricCharge" SET startPower TO RES:AMOUNT/RES:CAPACITY.
	}
	LOCAL currentPower IS 1.
//	LOG "Time,Old Time,New Distance,Old Distance,distanceToTargetOrbitalPlane Rate,Real Time Left" TO "0:Warping.csv".
//	LOG "s,s,km,km,km/s,s" TO "0:Warping.csv".

	// continue waiting until there are five seconds or less of real time remaining AND at least 10 seconds has passed
	UNTIL ((realTimeLeft < 5) AND (KUNIVERSE:TIMEWARP:RATE = 1)) AND newTime > startTime + 10 {
		LIST RESOURCES IN RESLIST.
		FOR RES IN RESLIST {
			IF RES:NAME = "ElectricCharge" SET currentPower TO RES:AMOUNT/RES:CAPACITY.
		}
		// if the rate is still changing, do nothing
		IF KUNIVERSE:TIMEWARP:ISSETTLED {
			SET newTime TO TIME:SECONDS.
			SET newDistance TO distanceToTargetOrbitalPlane().

			// once we have at least two sets of reliable data, start calculating.
			IF completedScans >= 2 {
				// calculate the rate in terms of units per in-game second
				IF (oldTime <> newTime) SET distanceRate TO (newDistance - oldDistance)/(newTime - oldTime).

				// If distanceRate isn't 0, calculate how much real time is left
				IF (distanceRate <> 0) {
					// calculate how long it will take to get to the target Distance in real-world seconds
					SET realTimeLeft TO (targetDistance - newDistance) / (distanceRate * KUNIVERSE:TIMEWARP:RATE).

					// Now that we have both an accurate newDistance and oldDistance, determine which quadrant the warp is starting in.
					IF completedScans = 2 {
						SET startNegative TO realTimeLeft < 0.
					}

					// if we started negative and are still negative, swap the sign of realTimeLeft.
					IF startNegative AND realTimeLeft < 0 {
						SET realTimeLeft TO -realTimeLeft.
					}
				}
			}

			// warp slower, if not at min rate
			IF (realTimeLeft < 2) AND (KUNIVERSE:TIMEWARP:RATE <> 1) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
			}

			// warp faster, if not at max rate - this assumes that the next rate is 10x faster than the current rate
			IF (realTimeLeft > 30) AND
				(KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) AND
				(KUNIVERSE:TIMEWARP:RATE <> maxWarpRate) AND
				(currentPower > 0.2 * startPower) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
			}

//			LOG newTime + "," + oldTime + "," + newDistance + "," + oldDistance + "," + distanceRate + "," + realTimeLeft TO "0:Warping.csv".

			// update the old Distances used in the rate calculations
			SET oldDistance TO newDistance.
			SET oldTime TO newTime.
			SET completedScans TO completedScans + 1.
		}
		PRINT "Current Power: " + ROUND(currentPower*100, 2) + "%       "  							      AT (0, 18).
		PRINT "Completed Scans: " + completedScans + "       " 													      AT (0, 19).
		PRINT "Speed Relative to Plane " + distanceToString(distanceRate * 1000, 1) + "/s   " AT (0, 20).
		PRINT "Distance from Plane " + distanceToString(newDistance * 1000, 1) + "    "  			AT (0, 21).
		PRINT "Real Time Left " + timeToString(realTimeLeft, 2) + " s     "              			AT (0, 22).
		PRINT "Real Time Rate " + ROUND(KUNIVERSE:TIMEWARP:RATE, 2) + " s/s   "          			AT (0, 23).
		WAIT 0.
	}

	SET KUNIVERSE:TIMEWARP:WARP TO 0.
	RETURN TIME:SECONDS - startTime.
}

IF NOT HASTARGET PRINT "Please select a target vessel or body in the same SOI.".

UNTIL HASTARGET WAIT 0.1.

LOCAL hasError TO FALSE.
IF TARGET:BODY <> SHIP:BODY {
	SET loopMessage TO "Target is not in the same SOI as the ship".
	SET hasError TO TRUE.
}

IF TARGET:ORBIT:INCLINATION < SHIP:GEOPOSITION:LAT {
	SET loopMessage TO "Launch site does not intersect orbital plane of target!".
	SET hasError TO TRUE.
}


IF NOT hasError {
	PRINT SHIP:NAME + " will wait until " + ROUND(offset,2) + " km from the instant launch window.".
	helperFunction().
	IF distanceToTargetOrbitalPlane() < 0 {
		SET loopMessage TO "Dist: " + ROUND(-distanceToTargetOrbitalPlane()) + " km south. Inc: " + ROUND(-TARGET:ORBIT:INCLINATION, 4).
	} ELSE SET loopMessage TO "Dist: " + ROUND(distanceToTargetOrbitalPlane()) + " km north. Inc: " + ROUND(TARGET:ORBIT:INCLINATION, 4).
}
