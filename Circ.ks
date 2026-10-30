@LAZYGLOBAL OFF.
PARAMETER passedArgument IS "Apo".
PARAMETER visualize IS FALSE.

LOCAL offset TO getOffset(passedArgument).

LOCAL directions IS getOrbitDirectionsAt(SHIP, TIME:SECONDS + offset).
SET directions["position"] TO directions["position"] - SHIP:BODY:POSITION.

LOCAL desiredSpeed IS SQRT(SHIP:BODY:MU/directions["position"]:MAG).
LOCAL flightPathAngle IS 90 - VANG(directions["velocity"], directions["position"]).
LOCAL desiredVelocity IS directions["velocity"] * ANGLEAXIS(-flightPathAngle, directions["normal"]).
SET desiredVelocity TO desiredVelocity:NORMALIZED * desiredSpeed.
LOCAL deltaV IS desiredVelocity - directions["velocity"].
ADD NODE(TIME:SECONDS + offset, deltaV * directions["radial"], deltaV * directions["normal"], deltaV * directions["prograde"]).

IF visualize {
	CLEARSCREEN.
	PRINT "Offset: " + timeToString(offset).
	PRINT "Actual Speed: " + distanceToString(directions["velocity"]:MAG) + "/s".
	PRINT "Desired Speed: " + distanceToString(desiredSpeed) + "/s".
	PRINT "Flight Path Angle: " + ROUND(flightPathAngle) + " degrees".
	PRINT "Delta V: " + distanceToString(deltaV:MAG) + "/s".

	LOCAL positionVecDraw IS        VECDRAW(SHIP:BODY:POSITION, V(0,0,0),   RED,       "Position", 1.0, TRUE).
	LOCAL velocityVecDraw IS        VECDRAW(SHIP:BODY:POSITION, V(0,0,0), GREEN,       "Velocity", 1.0, TRUE).
	LOCAL finalVelocityVecDraw IS   VECDRAW(SHIP:BODY:POSITION, V(0,0,0),  BLUE, "Final Velocity", 1.0, TRUE).

	SET positionVecDraw:VECTOR       TO directions["position"] + SHIP:BODY:POSITION.
	SET velocityVecDraw:VECTOR       TO directions["velocity"]:NORMALIZED * SHIP:BODY:RADIUS.
	SET finalVelocityVecDraw:VECTOR  TO desiredVelocity:NORMALIZED * SHIP:BODY:RADIUS.

	SET positionVecDraw:START        TO V(0,0,0).
	SET velocityVecDraw:START        TO directions["position"] + SHIP:BODY:POSITION.
	SET finalVelocityVecDraw:START   TO directions["position"] + SHIP:BODY:POSITION.

	WAIT 10.
}

// String To Time Offset
// Converts a description of when something should happen into a number of seconds from now.
// Passed the following:
//			description (string), which is one of
//				a number, which is already the time in seconds, such as "120"
//				"apo" or "apoapsis", for the time until apoapsis
//				"peri" or "periapsis", for the time until periapsis
//				a distance that ends in "m", for the time until the ship is next at that altitude above sea level.
//				Examples are "80000m", "80km" and "2Mm". The "k", "M" and "G" prefixes are the ones that
//				processScalarParameter understands.
// Returns the following:
//			the time from now in seconds (scalar), or -1 if the description cannot be understood or has no answer.
//			Because -1 is also the failure value, a description of "-1" cannot be told apart from a failure.
//			kOS cannot catch errors, so every case that would cause one is checked for first.
FUNCTION getOffset {
	PARAMETER description.
	LOCAL failed IS -1.
	// a number is already a time. This also lets a number that was converted before it got here through.
	IF description:ISTYPE("Scalar") RETURN description.
	IF NOT description:ISTYPE("String") RETURN failed.
	LOCAL text IS description:TRIM.
	IF text = "" RETURN failed.

	// A string that is a number gives the same result with two different defaults. One that is not gives the defaults.
	LOCAL firstTry IS text:TONUMBER(0).
	IF firstTry = text:TONUMBER(1) RETURN firstTry.

	IF text = "apo" OR text = "apoapsis" {
		// there is no apoapsis on an orbit that escapes
		IF SHIP:ORBIT:ECCENTRICITY >= 1 RETURN failed.
		RETURN ETA:APOAPSIS.
	}
	IF text = "peri" OR text = "periapsis" RETURN ETA:PERIAPSIS.

	// a distance
	IF text:ENDSWITH("m") {
		LOCAL remainder IS text:SUBSTRING(0, text:LENGTH - 1):TRIM.
		IF remainder = "" RETURN failed.
		// a plain number, or one with a k, M or G on the end
		LOCAL desiredAltitude IS remainder:TONUMBER(0).
		IF desiredAltitude <> remainder:TONUMBER(1) {
			SET desiredAltitude TO processScalarParameter(remainder, 0).
			IF desiredAltitude <> processScalarParameter(remainder, 1) RETURN failed.
		}
		// timeToAltitude only works for an orbit that comes back around
		LOCAL timeToIt IS timeToAltitude(desiredAltitude).
		RETURN timeToIt.
	}
	RETURN failed.
}

SET loopMessage TO "Circularization burn created".

