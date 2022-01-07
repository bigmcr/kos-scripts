@LAZYGLOBAL OFF.
CLEARSCREEN.

PARAMETER desiredAltitude.
RUNPATH("circ", timeToAltitude(desiredAltitude)).
AG1 OFF. AG2 OFF.
PRINT " ".
PRINT "Activate AG1 to execute the node".
PRINT "Activate AG2 to not execute the node".
UNTIL AG1 OR AG2 WAIT 0.0.
IF AG1 {
  RUNPATH("exec").
  REMOVE NEXTNODE.
  AG1 OFF.
  SET loopMessage TO "Now circularized at " + distanceToString(desiredAltitude, 2) + " altitude".
}

IF AG2 {
  SET loopMessage TO "Circularization node created " + distanceToString(desiredAltitude, 2) + " altitude".
  AG2 OFF.
}
