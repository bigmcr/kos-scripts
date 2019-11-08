@LAZYGLOBAL OFF.
CLEARSCREEN.
GLOBAL pitchPID TO PIDLOOP(2, 0.3, 0, -1, 1).
LOCK STEERING TO -VELOCITY:SURFACE.

LOCAL myVariable TO LIST().
LIST ENGINES IN myVariable.
LOCAL TWR IS 1.
LOCAL thrust is myVariable[0]:MAXTHRUST.
LOCAL ISP is myVariable[0]:VACUUMISP.
LOCAL t IS 1.
LOCAL MMHUse IS 6.5787.
LOCAL NTOUse IS 10.8262.
LOCAL MMHAmount IS 0.
LOCAL NTOAmount IS 0.

SET t TO 1.
LOCAL resList IS STAGE:RESOURCES.
FOR res IN resList {
	IF RES:NAME = "MMH" { SET MMHAmount TO RES:AMOUNT.}
	IF RES:NAME = "NTO" { SET NTOAmount TO RES:AMOUNT.}
}
SET t TO MIN (MMHAmount / MMHUse, NTOAmount / NTOUse).
LOCAL g0 IS BODY("Earth"):MU / ((BODY("Earth"):RADIUS)^2).
LOCAL g IS SHIP:BODY:MU / ((ALTITUDE + SHIP:BODY:RADIUS)^2).
LOCAL v0 IS SHIP:VELOCITY:ORBIT:MAG.
LOCAL m0 IS SHIP:MASS*1000.
LOCAL equation IS ALT:RADAR + 10.
LOG "MET,g,m0,t,v0,TWR,equation,ALT:RADAR,ALTITUDE,MMH Amount,MMH Time,NTO Amount,NTO Time" TO "SuicideBurn.csv".

UNTIL FALSE {
	SET g TO SHIP:BODY:MU / ((ALTITUDE + SHIP:BODY:RADIUS)^2).
	SET v0 TO SHIP:VELOCITY:ORBIT:MAG.
	SET m0 TO SHIP:MASS * 1000.
	SET TWR TO SHIP:MAXTHRUST / g.
	SET resList TO STAGE:RESOURCES.
	FOR res IN resList {
		IF RES:NAME = "MMH" { SET MMHAmount TO RES:AMOUNT.}
		IF RES:NAME = "NTO" { SET NTOAmount TO RES:AMOUNT.}
	}
	SET t TO MIN (MMHAmount / MMHUse, NTOAmount / NTOUse).
	SET equation TO (Isp*t)/g0 + (g*t^2)/2 + t*V0 + (m0*Isp^2*LN(m0*Isp - thrust*g0*t))/(thrust*g0^2).
	PRINT "g is " + ROUND(g, 4) + "      " AT (0, 5).
	PRINT "m0 is " + ROUND(m0, 4) + "      " AT (0, 6).
	PRINT "t is " + ROUND(t, 4) + "      " AT (0, 7).
	PRINT "v0 is " + ROUND(v0, 4) + "      " AT (0, 8).
	PRINT "TWR is " + ROUND(TWR, 4) + "      " AT (0, 9).
	PRINT "Equation is " + ROUND(equation, 2) + "     " AT (0, 10).
	PRINT "Radar Altitude is " + ROUND(ALT:RADAR, 2) + "     " AT (0, 11).
	PRINT "Pure Altitude is " + ROUND(ALTITUDE, 2) + "     " AT (0, 12).
	PRINT "There is " + ROUND(MMHAmount, 2) + ", or " + ROUND(MMHAmount / MMHUse, 2) + " second's worth of MMH   " AT (0, 16).
	PRINT "There is " + ROUND(NTOAmount, 2) + ", or " + ROUND(NTOAmount / NTOUse, 2) + " second's worth of NTO   " AT (0, 17).
	
	LOG MISSIONTIME + "," + g + "," + m0 + "," + t + "," + v0 + "," + TWR + "," + equation + "," + ALT:RADAR + "," + ALTITUDE + "," + MMHAmount + "," + MMHAmount / MMHUse + "," + NTOAmount + "," + NTOAmount / NTOUse TO "SuicideBurn.csv".

}
// use RCS to settle any ullage concerns.
RCS ON. 
SET SHIP:CONTROL:FORE TO 1.0.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.								// release all controls to the pilot

PRINT "Ullage starting".
WAIT 5.

LOCK THROTTLE TO 1.