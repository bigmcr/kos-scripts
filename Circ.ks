@LAZYGLOBAL OFF.
PARAMETER passedArgument IS "Apo".
PARAMETER visualize IS FALSE.

LOCAL offset TO getOffset(passedArgument).

LOCAL directions IS getOrbitDirectionsAt(offset + TIME:SECONDS, SHIP).
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

FUNCTION getOffset {
	PARAMETER argument.
	IF argument:TYPENAME = "Scalar" RETURN argument.
	IF argument:TYPENAME = "String" {
		IF argument = "Apo" OR argument = "Apoapsis" RETURN ETA:APOAPSIS.
		IF argument = "Peri" OR argument = "Periapsis" RETURN ETA:PERIAPSIS.
		RETURN processScalarParameter(argument).
	}
}

SET loopMessage TO "Circularization burn created".
