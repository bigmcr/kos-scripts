@LAZYGLOBAL OFF.

LOCAL fourPiSquared IS 4 * CONSTANT:PI^2.
LOCAL twoPi IS 2 * CONSTANT:PI.
LOCAL GM IS SHIP:BODY:MU.

// burnTime is time of the burn, in seconds from now
// Defaults to time to apoapsis.
PARAMETER burnTime IS ETA:APOAPSIS.
SET burnTime TO burnTime + TIME:SECONDS.

LOCAL pos IS (POSITIONAT(SHIP, burnTime) - SHIP:BODY:POSITION):MAG.

// periodFinal is the desired final period, in seconds
// Defaults to time for a circular orbit at the position of the burn.
PARAMETER periodFinal IS twoPi*SQRT(pos^3/GM).

PARAMETER interactive IS TRUE.

IF interactive CLEARSCREEN.
IF interactive PRINT "GM: " + ROUND(GM, 4).
LOCAL smaInitial IS SHIP:ORBIT:SEMIMAJORAXIS.
IF interactive PRINT "SMA Initial: " + distanceToString(smaInitial, 3).
IF interactive PRINT "Position: " + ROUND(pos).
LOCAL speedMeasured IS VELOCITYAT(SHIP, burnTime):ORBIT:MAG.
IF interactive PRINT "Speed Measured: " + distanceToString(speedMeasured, 2) + "/s".
LOCAL speedCalcdInitial IS SQRT(GM*(2/pos - 1/smaInitial)).
IF interactive PRINT "Speed Calc'd Initial: " + distanceToString(speedCalcdInitial, 2) + "/s".
LOCAL periodMeasured IS SHIP:ORBIT:PERIOD.
IF interactive PRINT "Period Measured: " + ROUND(periodMeasured, 2) + "  ".
LOCAL periodCalcdInitial IS twoPi * SQRT(smaInitial^3 / GM).
IF interactive PRINT "Period Calc'd Initial: " + ROUND(periodCalcdInitial, 2) + "  ".
IF interactive PRINT "Period Final: " + ROUND(periodFinal, 2) + "  ".
LOCAL smaCalcdFinal IS (GM*(periodFinal^2)/fourPiSquared)^(1.0/3.0).
IF interactive PRINT "SMA Calc'd Final: " + distanceToString(smaCalcdFinal).
LOCAL speedCalcdFinal IS SQRT(GM*(2/pos - 1/smaCalcdFinal)).
IF interactive PRINT "Speed Calc'd Final: " + distanceToString(speedCalcdFinal, 2) + "/s".
LOCAL deltaV IS speedCalcdFinal - speedCalcdInitial.
IF interactive PRINT "Delta V: " + distanceToString(deltaV, 2) + "/s".

LOCAL X TO NODE(burnTime, 0, 0, deltaV).
ADD X.            // adds maneuver to flight plan

IF interactive WAIT 5.

IF interactive SET loopMessage TO "Period change node created".
