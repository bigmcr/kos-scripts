@LAZYGLOBAL OFF.
PARAMETER targetName IS "".

CLEARSCREEN.

LOCAL possibleVessels IS "".
LIST TARGETS IN possibleVessels.
FOR eachTarget IN possibleVessels {
  IF eachTarget:NAME = targetName {
    PRINT "Setting target to " + targetName.
    SET TARGET TO eachTarget.
    BREAK.
  }
}

IF NOT HASTARGET {
    CLEARSCREEN.
    PRINT "Select a target.".
    PRINT "It must be in the current SOI.".
    UNTIL HASTARGET AND TARGET:ORBIT:BODY:NAME = SHIP:BODY:NAME {WAIT 0.}
}

LOCAL finalTargetOrbit IS TARGET:ORBIT.

LOCAL tempChar IS "".
LOCAL finalAltitude IS 30000.
IF SHIP:BODY:ATM:EXISTS SET finalAltitude TO SHIP:BODY:ATM:HEIGHT - 5000.
RUNPATH("LaunchToOrbit", finalAltitude, finalTargetOrbit:INCLINATION, finalTargetOrbit:LAN).
