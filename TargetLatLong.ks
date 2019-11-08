PARAMETER offset IS 0.5.

CLEARSCREEN.
IF NOT HASTARGET PRINT "Please select a target vessel or body in the same SOI.".

UNTIL HASTARGET WAIT 0.1.

IF TARGET:BODY = SHIP:BODY {
	PRINT SHIP:NAME + " will wait until " + ROUND(offset,2) + " longitude degrees from the instant launch window.".

	LOCAL targetLAN IS SIN(TARGET:ORBIT:LAN + SHIP:BODY:ROTATIONANGLE).
	LOCAL maxWarpRate IS 10000.

	LOCAL startTime IS TIME:SECONDS.
	LOCAL startNegative IS FALSE.
	LOCAL newLongitude IS SIN(SHIP:GEOPOSITION:LNG).
	LOCAL newTime IS TIME:SECONDS.
	LOCAL oldLongitude IS newLongitude.
	LOCAL oldTime IS newTime.

	LOCAL longitudeRate IS 1.
	LOCAL realTimeLeft IS 10.
	LOCAL completedScans IS 0.
	
	// Attempt 5
	LOCAL vectorLength IS SHIP:BODY:RADIUS * 1.5.
	LOCAL rotationPeriod IS SHIP:BODY:ROTATIONPERIOD.
	LOCAL currentLongitude IS SHIP:GEOPOSITION:LNG.
	SET targetLAN TO TARGET:ORBIT:LAN.
	PRINT "Rotation Period: " + rotationPeriod + " s".
	PRINT "Current Longitude " + currentLongitude + " deg ".
	PRINT "Target LAN: " + targetLAN + " deg".
	PRINT "Body Rotation Angle: " + SHIP:BODY:ROTATIONANGLE + " deg".
	LOCAL primeVector       IS VECDRAW(SHIP:BODY:POSITION, vectorLength * SOLARPRIMEVECTOR,                                                               RED,    "Solar Prime Vector",  1, TRUE).
	LOCAL targetLANVector   IS VECDRAW(SHIP:BODY:POSITION, vectorLength * SOLARPRIMEVECTOR * ANGLEAXIS(targetLAN, SHIP:BODY:ANGULARVEL),                  GREEN,  "Target LAN Vector",   1, TRUE).
	LOCAL bodyRotation      IS VECDRAW(SHIP:BODY:POSITION, vectorLength * SOLARPRIMEVECTOR * ANGLEAXIS(SHIP:BODY:ROTATIONANGLE, SHIP:BODY:ANGULARVEL),    YELLOW, "Body Rotation Angle", 1, TRUE).
	LOCAL shipPosition      IS VECDRAW(SHIP:BODY:POSITION, - SHIP:BODY:POSITION,                                                                          BLUE,   "Ship Position", 1, TRUE).
WAIT 30.

//	LOG "Time,Old Time,New Longitude,Old Longitude,Longitude Rate,Real Time Left" TO "0:Warping.csv".
//	LOG "s,s,,,1/s,s" TO "0:Warping.csv".

	// continue waiting until there is five seconds or less of real time remaining, or the targetLAN is less than the target longitude
	UNTIL (((SIN(offset) < (targetLAN - newLongitude)) OR (realTimeLeft < 5)) AND (KUNIVERSE:TIMEWARP:RATE = 1)) AND newTime > startTime + 10 {
		// if the rate is still changing, do nothing
		IF KUNIVERSE:TIMEWARP:ISSETTLED {
			SET newTime TO TIME:SECONDS.
			SET newLongitude TO SIN(SHIP:GEOPOSITION:LNG - SHIP:BODY:ROTATIONANGLE).
			
			// once we have at least two sets of reliable data, start calculating.
			IF completedScans >= 2 {
				// calculate the rate in terms of units per in-game second
				IF (oldTime <> newTime) SET longitudeRate TO (newLongitude - oldLongitude)/(newTime - oldTime).
				
				// If longitudeRate isn't 0, calculate how much real time is left
				IF (longitudeRate <> 0) {
					// calculate how long it will take to get to the target longitude in real-world seconds
					SET realTimeLeft TO (targetLAN - newLongitude) / (longitudeRate * KUNIVERSE:TIMEWARP:RATE).

					// Now that we have both an accurate newLongitude and oldLongitude, determine which quadrant the warp is starting in.
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
			IF (realTimeLeft > 15) AND (KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) AND (KUNIVERSE:TIMEWARP:RATE <> maxWarpRate) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
			}
			
//			LOG newTime + "," + oldTime + "," + newLongitude + "," + oldLongitude + "," + longitudeRate + "," + realTimeLeft TO "0:Warping.csv".

			// update the old values used in the rate calculations
			SET oldLongitude TO newLongitude.
			SET oldTime TO newTime.
			SET completedScans TO completedScans + 1.
		}
		PRINT "Completed Scans: " + completedScans + "       " AT (0, 19).
		PRINT "Speed Toward Plane " + ROUND(longitudeRate, 5) + "        " AT (0, 20).
		PRINT "Real Time Left " + timeToString(realTimeLeft, 2) + " s     " AT (0, 21).
		PRINT "Real Time Rate " + ROUND(KUNIVERSE:TIMEWARP:RATE, 2) + " s/s   " AT (0, 22).
		PRINT "Longitude " + ROUND(ARCSIN(newLongitude), 1) + " deg     " AT (0, 23).
		PRINT "Target LAN " + ROUND(ARCSIN(targetLAN), 1) + " deg     " AT (0, 24).
		WAIT 0.
	}
	IF distanceToTargetOrbitalPlane() < 0 {
		SET loopMessage TO "Dist: " + ROUND(-distanceToTargetOrbitalPlane()) + " km south. Inc: " + ROUND(-TARGET:ORBIT:INCLINATION, 4).
	} ELSE SET loopMessage TO "Dist: " + ROUND(distanceToTargetOrbitalPlane()) + " km north. Inc: " + ROUND(TARGET:ORBIT:INCLINATION, 4).
} ELSE {
	SET loopMessage TO "Target is not in the same SOI as the ship".
}
