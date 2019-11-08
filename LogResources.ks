@LAZYGLOBAL OFF.

PARAMETER fileName IS "0:" + SHIP:NAME + " Resources.csv".

CLEARSCREEN.

updateShipInfoCurrent(FALSE).

LOCAL keyPress is "".
LOCAL startTime IS TIME:SECONDS.

LOCAL message IS "Time,Total Mass,Timewarp,".
FOR eachResource IN SHIP:RESOURCES {
	SET message TO message + eachResource:NAME + ",".
}
LOG message TO fileName.

LOCAL message IS "s,kg,,".
FOR eachResource IN SHIP:RESOURCES {
	SET message TO message + "kg,".
}

LOG message TO fileName.

UNTIL (keyPress = "q") {
	SET message TO (TIME:SECONDS - startTime) + "," + (SHIP:MASS * 1000) + "," + KUNIVERSE:TIMEWARP:RATE + ",".
	FOR eachResource IN SHIP:RESOURCES {
		SET message TO message + eachResource:AMOUNT*eachResource:DENSITY*1000 + ",".
	}
	LOG message TO fileName.
	WAIT 0.
}
