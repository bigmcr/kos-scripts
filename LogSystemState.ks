@LAZYGLOBAL OFF.

LOCAL bodyList IS LIST().
LIST BODIES IN bodyList.
LOCAL bodiesFileName IS "0:bodies.csv".
IF EXISTS(bodiesFileName) DELETEPATH(bodiesFileName).
LOG "Name,Mass,Mu,Orbited Body Name,Epoch,Period,Inclination,Eccentricity,SMA,LAN,Argument Of Periapsis,True Anomaly,Mean Anomaly At Epoch,ANGULARVEL X,ANGULARVEL Y,ANGULARVEL Z" TO bodiesFileName.

FOR eachBody IN bodyList {
	IF eachBody:HASORBIT LOG eachBody:NAME + "," + eachBody:Mass + "," + eachBody:MU + "," + eachBody:ORBIT:BODY:NAME + "," + eachBody:ORBIT:EPOCH + "," + eachBody:ORBIT:PERIOD + "," + eachBody:ORBIT:INCLINATION + "," + eachBody:ORBIT:ECCENTRICITY + "," + eachBody:ORBIT:SEMIMAJORAXIS + "," + eachBody:ORBIT:LAN + "," + eachBody:ORBIT:ARGUMENTOFPERIAPSIS + "," + eachBody:ORBIT:TRUEANOMALY + "," + eachBody:ORBIT:MEANANOMALYATEPOCH + "," + eachBody:ANGULARVEL:X + "," + eachBody:ANGULARVEL:Y + "," + eachBody:ANGULARVEL:Z TO bodiesFileName.
	ELSE LOG eachBody:NAME + "," + eachBody:Mass + "," + eachBody:MU + ",No Orbit" TO bodiesFileName.
}

LOG SHIP:NAME + "," + SHIP:Mass + ",N/A," + SHIP:ORBIT:BODY:NAME + "," + SHIP:ORBIT:EPOCH + "," + SHIP:ORBIT:PERIOD + "," + SHIP:ORBIT:INCLINATION + "," + SHIP:ORBIT:ECCENTRICITY + "," + SHIP:ORBIT:SEMIMAJORAXIS + "," + SHIP:ORBIT:LAN + "," + SHIP:ORBIT:ARGUMENTOFPERIAPSIS + "," + SHIP:ORBIT:TRUEANOMALY + "," + SHIP:ORBIT:MEANANOMALYATEPOCH + ",N/A,N/A,N/A" TO bodiesFileName.

LOG "" TO bodiesFileName.
LOG "Body,Kerbin" TO bodiesFileName.
LOCAL pos IS absolutePosition(BODY("Kerbin"), TIME:SECONDS).
LOCAL vel IS absoluteVelocity(BODY("Kerbin"), TIME:SECONDS).
LOG ",X,Y,Z" TO bodiesFileName.
LOG "Absolute Position," + pos:X + "," + pos:Y + "," + pos:Z TO bodiesFileName.
LOG "Absolute Velocity," + vel:X + "," + vel:Y + "," + vel:Z TO bodiesFileName.
LOG "Solar Prime Vector," + SOLARPRIMEVECTOR:X + "," + SOLARPRIMEVECTOR:Y + "," + SOLARPRIMEVECTOR:Z TO bodiesFileName.
LOG "Time," + TIME:SECONDS TO bodiesFileName.