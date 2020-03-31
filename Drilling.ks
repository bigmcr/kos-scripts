CLEARSCREEN.
PRINT "Now Starting Drilling".
RADIATORS ON.
PRINT "Radiators On".
PANELS ON.
PRINT "Panels On".
FUELCELLS ON.
PRINT "Fuelcells On".
DEPLOYDRILLS ON.
PRINT "Deploying Drills".
ISRU ON.
PRINT "Starting ISRUs".
WAIT 0.
DRILLS ON.
PRINT "Starting Drills".

LOCAL resourceList IS SHIP:RESOURCES.
LOCAL deltaT IS 0.
LOCAL timeElapsed IS 0.
LOCAL oldTime IS TIME:SECONDS.
LOCAL startTime IS TIME:SECONDS.
LOCAL sensingDelay IS 10.

LOCAL targetTime IS TIME:SECONDS + 60.

LOCAL startTime IS TIME:SECONDS.
LOCAL timeLeft IS targetTime - TIME:SECONDS.

LOCAL liquidFuelRemainingStart TO 0.0.
LOCAL oxidizerRemainingStart TO 0.0.
LOCAL monopropRemainingStart TO 0.0.

LOCAL liquidFuelRemainingEnd TO 0.0.
LOCAL oxidizerRemainingEnd TO 0.0.
LOCAL monopropRemainingEnd TO 0.0.

LOCAL liquidFuelTime TO 0.
LOCAL oxidizerTime TO 0.
LOCAL monopropTime TO 0.

LOCAL liquidFuelRate TO 0.
LOCAL oxidizerRate TO 0.
LOCAL monopropRate TO 0.

PRINT "Waiting for equipment to be deployed".
WAIT 10.
PRINT "Equipment deployed and running".
PRINT "Monitoring resource usage".
FOR eachResource IN resourceList {
  IF eachResource:NAME = "LiquidFuel" {SET liquidFuelRemainingStart TO eachResource:CAPACITY - eachResource:AMOUNT.}
  IF eachResource:NAME = "Oxidizer" {SET oxidizerRemainingStart TO eachResource:CAPACITY - eachResource:AMOUNT.}
  IF eachResource:NAME = "MonoProp" {SET monopropRemainingStart TO eachResource:CAPACITY - eachResource:AMOUNT.}
}

UNTIL timeElapsed > sensingDelay {
  WAIT 0.
  SET timeElapsed TO TIME:SECONDS - startTime.
}

FOR eachResource IN resourceList {
  IF eachResource:NAME = "LiquidFuel" {SET liquidFuelRemainingEnd TO eachResource:CAPACITY - eachResource:AMOUNT.}
  IF eachResource:NAME = "Oxidizer" {SET oxidizerRemainingEnd TO eachResource:CAPACITY - eachResource:AMOUNT.}
  IF eachResource:NAME = "MonoProp" {SET monopropRemainingEnd TO eachResource:CAPACITY - eachResource:AMOUNT.}
}

SET liquidFuelRate TO (liquidFuelRemainingStart - liquidFuelRemainingEnd) / sensingDelay.
SET oxidizerRate TO (oxidizerRemainingStart - oxidizerRemainingEnd) / sensingDelay.
SET monopropRate TO (monopropRemainingStart - monopropRemainingEnd) / sensingDelay.

IF liquidFuelRate <> 0 SET liquidFuelTime TO liquidFuelRemainingEnd / liquidFuelRate.
IF oxidizerRate <> 0 SET oxidizerTime TO oxidizerRemainingEnd / oxidizerRate.
IF monopropRate <> 0 SET monopropTime TO monopropRemainingEnd / monopropRate.

SET timeRemaining TO MAX(MAX(liquidFuelTime, oxidizerTime), monopropTime).

PRINT "             Start   End   Rate    Time   ".
PRINT "Liquid Fuel  " + ROUND(liquidFuelRemainingStart) + "   " + ROUND(liquidFuelRemainingEnd) + "   " + ROUND(liquidFuelRate, 2) + "    " + ROUND(liquidFuelTime).
PRINT "Oxidizer     " + ROUND(oxidizerRemainingStart  ) + "   " + ROUND(oxidizerRemainingEnd  ) + "   " + ROUND(oxidizerRate,   2) + "    " + ROUND(oxidizerTime  ).
PRINT "MonoProp     " + ROUND(monopropRemainingStart  ) + "   " + ROUND(monopropRemainingEnd  ) + "   " + ROUND(monopropRate,   2) + "    " + ROUND(monopropTime  ).

PRINT "".
PRINT "Waiting until " + timeToString(timeRemaining) + " from now.".

SET targetTime TO TIME:SECONDS + timeRemaining.
SET KUNIVERSE:TIMEWARP:RATE TO 0.
WAIT 0.1.
SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

// continue waiting until there is five seconds or less of real time remaining
UNTIL (timeLeft < 0.5) AND (KUNIVERSE:TIMEWARP:RATE = 1) {
	// if the rate is still changing, do nothing
	IF KUNIVERSE:TIMEWARP:ISSETTLED {
		// calculate how long it will take to get to the target value in real-world seconds
		SET timeLeft TO (targetTime - TIME:SECONDS) / (KUNIVERSE:TIMEWARP:RATE).

		// warp slower, if not at min rate
		IF (timeLeft < 1) AND (KUNIVERSE:TIMEWARP:RATE <> 1) {
			SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
		}

		// warp faster, if not at max rate - this assumes that the next rate is 10x faster than the current rate
		IF (timeLeft > 15) AND (KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) {
			SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
		}
	}
	WAIT 0.
}

SET KUNIVERSE:timewarp:warp TO 0.

PRINT "Now Stopping Drilling".

RADIATORS OFF.
PRINT "Radiators Off".

PANELS OFF.
PRINT "Panels Off".

FUELCELLS OFF.
PRINT "Fuelcells Off".

DEPLOYDRILLS OFF.
PRINT "Retracting Drills".

ISRU OFF.
PRINT "Stopping ISRUs".

WAIT 1.
SET loopMessage TO "Fuel should be full now!".
