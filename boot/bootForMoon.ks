@LAZYGLOBAL OFF.

// Warp To Value
// This function timewarps until the passed delegate returns a value that is less than the targetValue.
// This function keeps track of the rate of change of the value, and varies the warp speed to maintain 
// 10 seconds or less of realtime remaining for each warp speed.
// Note that the delegate passed must return a scalar, but can do other things as well.
// Passed the following:
//			delegate to function returning a scalar (delegate)
//			target value (scalar)
// Returns the following:
//			time that was warped through (scalar, seconds)
FUNCTION warpToValue
{
	PARAMETER delegate.
	PARAMETER targetValue IS 0.
	PARAMETER maxWarpRate IS 1000.

	LOCAL startTime IS TIME:SECONDS.
	LOCAL oldValue IS delegate().
	LOCAL oldTime IS TIME:SECONDS.
	
	LOCAL rate IS 1.
	LOCAL timeLeft IS 10.
	LOCAL firstTime IS TRUE.
	
	// continue waiting until there is five seconds or less of real time remaining
	UNTIL (timeLeft < 5) AND (KUNIVERSE:TIMEWARP:RATE = 1) {
		// if the rate is still changing, do nothing
		IF KUNIVERSE:TIMEWARP:ISSETTLED {
			IF NOT firstTime {
				// calculate the rate in terms of units per in-game second
				IF (oldTime <> TIME:SECONDS) SET rate TO ABS(delegate() - oldValue)/(TIME:SECONDS - oldTime).
				// calculate how long it will take to get to the target value in real-world seconds
				IF (rate <> 0) SET timeLeft TO (delegate() - targetValue) / (rate * KUNIVERSE:TIMEWARP:RATE).
			}
			
			// warp slower, if not at min rate
			IF (timeLeft < 1) AND (KUNIVERSE:TIMEWARP:RATE <> 1) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
			}
			
			// warp faster, if not at max rate - this assumes that the next rate is 10x faster than the current rate
			IF (timeLeft > 15) AND (KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) AND (KUNIVERSE:TIMEWARP:RATE <> maxWarpRate) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
			}
			
			// update the old values used in the rate calculations
			SET oldValue TO delegate().
			SET oldTime TO TIME:SECONDS.
			// if this is the first scan of this logic, reset the flag
			IF firstTime SET firstTime TO FALSE.
			WAIT 0.
			
		}
		PRINT "Rate " + ROUND(rate, 5) + "       " AT (0, 2).
		PRINT "Time Left " + ROUND(timeLeft, 2) + "       " AT (0, 3).
		PRINT "Time Rate " + ROUND(KUNIVERSE:TIMEWARP:RATE, 2) + "       " AT (0, 4).
		PRINT "Delegate " + ROUND(delegate(),2) + "       " AT (0, 5).
		WAIT 0.
	}
	
	SET KUNIVERSE:timewarp:warp TO 0.
	RETURN TIME:SECONDS - startTime.
}

// returns the number of kilometers from the orbital plane of the target
FUNCTION distanceToTargetOrbitalPlane {
	RETURN VCRS(TARGET:VELOCITY:ORBIT, TARGET:POSITION - SHIP:BODY:POSITION):NORMALIZED * (  SHIP:POSITION - SHIP:BODY:POSITION)/1000.
}

FUNCTION waitForTarget {
	CLEARSCREEN.
	PARAMETER offset IS 50.

	PRINT "Ship's target is " + TARGET:NAME.
	PRINT SHIP:NAME + " will wait until " + ROUND(offset,2) + " km from the instant launch window.".
	warpToValue({RETURN ABS(distanceToTargetOrbitalPlane).}, offset).
}

core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
SET TERMINAL:BRIGHTNESS TO 1.
SET TERMINAL:WIDTH TO 80.
SET TERMINAL:HEIGHT TO 50.

SET TARGET TO BODY("Moon").
waitForTarget().
CLEARSCREEN.
PRINT "The time is right! Launch!".
