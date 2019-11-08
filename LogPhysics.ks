@LAZYGLOBAL OFF.

PARAMETER fileName IS "0:" + SHIP:NAME + ".csv".

CLEARSCREEN.

updateShipInfoCurrent(FALSE).

LOCAL keyPress is "".

LOG "Time,Mass,Position X,Position Y,Position Z,Velocity X,Velocity Y,Velocity Z,Fore" TO fileName.

UNTIL AG1 {
	LOG TIME:SECONDS + "," + SHIP:MASS * 1000 + "," + BODY:POSITION:X + "," + BODY:POSITION:Y + "," + BODY:POSITION:Z + "," + VELOCITY:ORBIT:X + "," + VELOCITY:ORBIT:Y + "," + VELOCITY:ORBIT:Z + "," + SHIP:CONTROL:FORE TO fileName.
	WAIT 0.
}
