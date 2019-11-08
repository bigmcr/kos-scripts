@LAZYGLOBAL OFF.

CLEARSCREEN.

// Set the generic variables from  the library
SET physicsWarpPerm TO 3.
SET debug TO FALSE.

PRINT "Select a target in LEO to rendezvous with.".
PRINT SHIP:NAME + " will wait and launch to a rendezvous.".

WAIT UNTIL HASTARGET.

// calculate the slope and intercept points for the regression
LOCAL targetAltitude IS TARGET:PERIAPSIS.

LOCAL gravTurnAngleEnd TO 10.	// The final angle of the end of the gravity turn

LOCAL slope IS evaluatePolynomial(gravTurnAngleEnd, LIST(1.327056511, -0.033722212, 0.001591872, -1.81648E-05)).
LOCAL intercept IS evaluatePolynomial(gravTurnAngleEnd, LIST(-46515.60547, 5344.870526, -137.9040413, 1.507210193)).

// Set the generic variables from "Library.ks".
SET isTesting TO FALSE.
LOCAL gravTurnEnd TO (targetAltitude - intercept)/slope.	// The altitude of the end of the gravity turn

PRINT "Target aquired".
PRINT "Waiting until " + TARGET:NAME + " is in the appropriate position.".

LOCAL targetLongitudeDifference TO evaluatePolynomial(targetAltitude, LIST(10.24280763, 4.05195E-06)) + 7.
LOCAL longitudeError TO 10.

SET KUNIVERSE:timewarp:mode TO "RAILS".

UNTIL longitudeError < 0.1 {
	IF longitudeError > 10 {
		SET KUNIVERSE:timewarp:warp TO 3.
	} ELSE IF longitudeError < 10.0 AND longitudeError > 2.5 {
		SET KUNIVERSE:timewarp:warp TO 2.
	} ELSE IF longitudeError < 2.5 AND longitudeError > 0.5 {
		SET KUNIVERSE:timewarp:warp TO 1.
	} ELSE IF longitudeError < 0.5 {
		SET KUNIVERSE:timewarp:warp TO 0.
	}
	PRINT "Longitude error: " + ROUND(longitudeError, 5) + "    " AT (0, 4).
	SET longitudeError TO ABS(SHIP:GEOPOSITION:LNG - TARGET:GEOPOSITION:LNG) - targetLongitudeDifference.
	WAIT 0.
}

RUNPATH("GravTurnLaunch.ks", TRUE, 10, MAX(TARGET:PERIAPSIS, 145000), 0).

CLEARSCREEN.
PRINT "In orbit!".
//	LOG timeSinceLaunch + "," + PERIAPSIS + "," + APOAPSIS + "," + SHIP:MASS + "," + ROUNDV(SHIP:VELOCITY:ORBIT,10) TO "logs/LEO People Retriever Records.csv".
