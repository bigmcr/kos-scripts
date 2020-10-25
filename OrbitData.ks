CLEARSCREEN.
PARAMETER logToFile IS FALSE.
PARAMETER localOrbit IS SHIP:ORBIT.

PRINT "Name " + localOrbit:NAME.
PRINT "Apoapsis " + distanceToString(localOrbit:APOAPSIS, 4).
PRINT "Periapsis " + distanceToString(localOrbit:PERIAPSIS, 4).
PRINT "Orbited Body " + localOrbit:BODY:NAME.
PRINT "Orbited Body MU " + BODY:MU + " m^3/s^2".
PRINT "Orbited Body Radius " + distanceToString(BODY:Radius, 4).
PRINT "Period " + timeToString(localOrbit:PERIOD, 4).
PRINT "Period " + localOrbit:PERIOD + " s".
PRINT "Inclination " + ROUND(localOrbit:INCLINATION, 4).
PRINT "Eccentricity " + ROUND(localOrbit:ECCENTRICITY, 4).
PRINT "Semi-Major Axis " + distanceToString(localOrbit:SEMIMAJORAXIS, 4).
PRINT "Semi-Minor Axis " + distanceToString(localOrbit:SEMIMINORAXIS, 4).
PRINT "Longitude of Ascending Node " + ROUND(localOrbit:LAN, 4).
PRINT "Argument of Periapsis " + ROUND(localOrbit:ARGUMENTOFPERIAPSIS, 4).
PRINT "True Anomaly  " + ROUND(localOrbit:TRUEANOMALY, 4).
PRINT "Mean Anomaly at Epoch " + ROUND(localOrbit:MEANANOMALYATEPOCH, 4).
PRINT "Epoch " + localOrbit:EPOCH.
PRINT "Transition " + localOrbit:TRANSITION.
PRINT "Position (r) " + distanceToString(SHIP:BODY:POSITION:MAG, 4).
PRINT "Velocity " + distanceToString(localOrbit:VELOCITY:ORBIT:MAG, 4) + "/s".
PRINT "Has Next Patch " + localOrbit:HASNEXTPATCH.
IF localOrbit:HASNEXTPATCH {
  PRINT "Next Patch ETA " + timeToString(localOrbit:NEXTPATCHETA).
}

IF connectionToKSC() AND logToFile {
  LOCAL fileName IS "0:Orbits.csv".
  LOG SHIP:NAME TO fileName.
  LOG "Name," + localOrbit:NAME TO fileName.
  LOG "Apoapsis," + localOrbit:APOAPSIS + ",m" TO fileName.
  LOG "Periapsis," + localOrbit:PERIAPSIS + ",m"  TO fileName.
  LOG "Orbited Body," + localOrbit:BODY:NAME TO fileName.
  LOG "Orbited Body MU," + BODY:MU + ",m^3/s^2" TO fileName.
  LOG "Orbited Body Radius," + BODY:Radius + ",m" TO fileName.
  LOG "Period," + localOrbit:PERIOD + ",s"  TO fileName.
  LOG "Inclination," + localOrbit:INCLINATION + ",deg" TO fileName.
  LOG "Eccentricity," + localOrbit:ECCENTRICITY TO fileName.
  LOG "Semi-Major Axis," + localOrbit:SEMIMAJORAXIS + ",m" TO fileName.
  LOG "Semi-Minor Axis," + localOrbit:SEMIMINORAXIS + ",m" TO fileName.
  LOG "Longitude of Ascending Node," + localOrbit:LAN + ",deg" TO fileName.
  LOG "Argument of Periapsis," + localOrbit:ARGUMENTOFPERIAPSIS + ",m" TO fileName.
  LOG "True Anomaly ," + localOrbit:TRUEANOMALY + ",m" TO fileName.
  LOG "Mean Anomaly at Epoch," + localOrbit:MEANANOMALYATEPOCH + ",m" TO fileName.
  LOG "Epoch," + localOrbit:EPOCH + ",s" TO fileName.
  LOG "Transition," + localOrbit:TRANSITION TO fileName.
  LOG "Position (r)," + SHIP:BODY:POSITION:MAG + ",m" TO fileName.
  LOG "Velocity," + localOrbit:VELOCITY:ORBIT:MAG + ",m/s" TO fileName.
  LOG "Has Next Patch," + localOrbit:HASNEXTPATCH TO fileName.
  IF localOrbit:HASNEXTPATCH {
    LOG "Next Patch ETA," + localOrbit:NEXTPATCHETA + ",s" TO fileName.
  }
}
WAIT 5.
SET loopMessage TO "Orbital Parameters displayed".
