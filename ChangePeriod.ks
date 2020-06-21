@LAZYGLOBAL OFF.

CLEARSCREEN.

LOCAL fourPiSquared IS 4 * CONSTANT:PI^2.
LOCAL twoPi IS 2 * CONSTANT:PI.
LOCAL GM IS SHIP:BODY:MU.

PARAMETER burnTime IS ETA:APOAPSIS.
SET burnTime TO burnTime + TIME:SECONDS.

LOCAL pos IS POSITIONAT(SHIP, burnTime):MAG - SHIP:BODY:POSITION:MAG.

PARAMETER periodFinal IS twoPi*SQRT(pos^3/GM).

LOCAL smaInitial IS SHIP:ORBIT:SEMIMAJORAXIS.
LOCAL speedMeasured IS VELOCITYAT(SHIP, burnTime):ORBIT:MAG.
LOCAL speedCalcdInitial IS SQRT(GM*(2/pos - 1/smaInitial)).
LOCAL periodMeasured IS SHIP:ORBIT:PERIOD.
LOCAL periodCalcdInitial IS twoPi * SQRT(smaInitial^3 / GM).
LOCAL smaCalcdFinal IS (GM*(periodFinal^2)/fourPiSquared)^(1.0/3.0).
LOCAL speedCalcdFinal IS SQRT(GM*(2/pos - 1/smaCalcdFinal)).
LOCAL deltaV IS speedCalcdInitial - speedCalcdFinal.

PRINT "GM: " + ROUND(GM, 4).
PRINT "SMA Initial: " + distanceToString(smaInitial, 3).
PRINT "Position: " + ROUND(pos).
PRINT "Speed Measured: " + distanceToString(speedMeasured, 2) + "/s".
PRINT "Speed Calc'd Initial: " + distanceToString(speedCalcdInitial, 2) + "/s".
PRINT "Period Measured: " + ROUND(periodMeasured, 2) + "  ".
PRINT "Period Calc'd Initial: " + ROUND(periodCalcdInitial, 2) + "  ".
PRINT "Period Final: " + ROUND(periodFinal, 2) + "  ".
PRINT "SMA Calc'd Final: " + distanceToString(smaCalcdFinal).
PRINT "Speed Calc'd Final: " + distanceToString(speedCalcdFinal, 2).
PRINT "Delta V: " + distanceToString(deltaV, 2) + "/s".

LOCAL X TO NODE(burnTime, 0, 0, deltaV).
ADD X.            // adds maneuver to flight plan

WAIT 5.

endScript().
