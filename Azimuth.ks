@LAZYGLOBAL OFF.
CLEARSCREEN.
PARAMETER targetInclination IS 45.
PARAMETER targetAltitude IS 70000.

PRINT "Launch Site Latitude: " + ROUND(SHIP:GEOPOSITION:LAT, 3) + " deg".
PRINT "Desired Inclination: " + ROUND(targetInclination, 3) + " deg".
PRINT "Sophisticated Launch Azimuth: " + ROUND(desiredAzimuth(targetAltitude, targetInclination), 3) + " deg".

WAIT 5.
