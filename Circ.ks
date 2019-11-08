CLEARSCREEN.

PARAMETER passedArgument IS "Apo".
PARAMETER timeOffset IS 0.

SET offset TO timeOffset + getOffset(passedArgument).

LOCAL VEL IS VELOCITYAT(SHIP, TIME:SECONDS + OFFSET):ORBIT.
LOCAL POS IS POSITIONAT(SHIP, TIME:SECONDS + OFFSET) - SHIP:BODY:POSITION.
LOCAL angle IS 90 - vang(POS, VEL).

LOCAL pro IS VELOCITYAT(SHIP, TIME:SECONDS + OFFSET):ORBIT:NORMALIZED.
LOCAL rad IS (POSITIONAT(SHIP, TIME:SECONDS + OFFSET) - SHIP:BODY:POSITION):NORMALIZED.
LOCAL speed IS SQRT(SHIP:BODY:MU/POS:MAG).

LOCAL horiz IS VXCL(POS, VEL):NORMALIZED * -speed.

LOCAL delta IS (VEL - horiz):NORMALIZED * (speed - VEL:MAG).

PRINT "Position (r): " + ROUNDV(POS, 0).
PRINT "Altitude: " + ROUND(POS:MAG - SHIP:BODY:RADIUS,4).
PRINT "Orbital Velocity: " + ROUND(SQRT(SHIP:BODY:MU/POS:MAG),4) + " m/s Horizontal".
PRINT "Calc'd Velocity: " + ROUND(VEL:MAG,4) + " m/s Prograde".
PRINT "Flight path angle: " + ROUND(angle ,4).
PRINT "Delta " + ROUND(delta:mag ,4) + " m/s".
PRINT "Horiz " + ROUND(horiz:mag, 4) + " m/s".

// Create the circularization node at the APOAPSIS
// time since start of game, radial, normal, prograde
LOCAL X TO NODE(TIME:SECONDS + OFFSET, delta*rad, 0, delta*pro ).
ADD X.            // adds maneuver to flight plan

FUNCTION getOffset {
	PARAMETER argument.
	IF argument:TYPENAME = "Scalar" RETURN argument.
	IF argument:TYPENAME = "String" {
		IF argument = "Apo" OR argument = "Apoapsis" RETURN ETA:APOAPSIS.
		IF argument = "Peri" OR argument = "Periapsis" RETURN ETA:PERIAPSIS.
		// IF argument = "LAN" OR argument = "Ascending" {
			// RETURN ETA:PERIAPSIS.
		// }
		// IF argument = "LDN" OR argument = "Descending" {
			// RETURN ETA:PERIAPSIS.
		// }
	}
}