@LAZYGLOBAL OFF.
CLEARSCREEN.

LOCAL colorList IS LIST().
colorList:ADD(MAGENTA).
colorList:ADD(RED).
colorList:ADD(GREEN).
colorList:ADD(BLUE).
colorList:ADD(YELLOW).
colorList:ADD(CYAN).
colorList:ADD(WHITE).
colorList:ADD(BLACK).

LOCAL processorList IS LIST().
LIST PROCESSORS IN processorList.

LOCAL coreHighlight TO LIST().
FOR eachProcessor IN processorList {
  coreHighlight:ADD(HIGHLIGHT(eachProcessor, MAGENTA)).
}
PRINT "Now displaying all " + processorList:LENGTH + " processors, one at a time".
PRINT "Press AG1 to cycle through them until you are at the SOURCE processor".
PRINT "Then press AG2".

LOCAL index IS 0.
AG2 OFF.
UNTIL AG2 {
  FOR eachHighlight IN RANGE(0, coreHighlight:LENGTH) {
    SET coreHighlight[eachHighlight]:ENABLED TO eachHighlight = index.
  }
  IF AG1 {
    SET index TO index + 1.
    IF index >= coreHighlight:LENGTH SET index TO 0.
    AG1 OFF.
  }
}
LOCAL sourceIndex IS index.
SET index TO index + 1.

PRINT "Press AG1 to cycle through them until you are at the DESTINATION processor".
PRINT "Then press AG2".
AG2 OFF.
UNTIL AG2 {
  FOR eachHighlight IN RANGE(0, coreHighlight:LENGTH) {
    SET coreHighlight[eachHighlight]:ENABLED TO eachHighlight = index.
  }
  IF AG1 {
    SET index TO index + 1.
    IF index = sourceIndex SET index TO index + 1.
    IF index >= coreHighlight:LENGTH SET index TO 0.
    AG1 OFF.
  }
}
LOCAL destIndex IS index.
FOR eachHighlight IN RANGE(0, coreHighlight:LENGTH) {
  SET coreHighlight[eachHighlight]:ENABLED TO FALSE.
}
LOCAL sourceHighlight IS HIGHLIGHT(processorList[sourceIndex], RED).
LOCAL destHighlight IS HIGHLIGHT(processorList[destIndex], GREEN).
SET sourceHighlight:ENABLED TO TRUE.
SET destHighlight:ENABLED TO TRUE.
PRINT "Press AG2 to confirm and copy all scripts over.".
PRINT "Press AG1 to cancel.".
AG1 OFF.
AG2 OFF.
UNTIL AG1 OR AG2 {WAIT 0.}
IF AG2 {
  LOCAL source IS processorList[sourceIndex]:GETMODULE("kOSProcessor").
  LOCAL dest IS processorList[destIndex]:GETMODULE("kOSProcessor").
  PRINT "Source Volume has " + source:VOLUME:FILES:LENGTH + " files in it.".
  PRINT "Dest Volume has " + dest:VOLUME:FILES:LENGTH + " files in it.".
  COPYPATH(source:VOLUME, dest:VOLUME).
  SET dest:BOOTFILENAME TO source:BOOTFILENAME.
  PRINT "Source Volume has " + source:VOLUME:FILES:LENGTH + " files in it.".
  PRINT "Dest Volume has " + dest:VOLUME:FILES:LENGTH + " files in it.".

  SET loopMessage TO "Files copied".
} ELSE {SET loopMessage TO "Parts Highlighted!".}
WAIT 5.
SET sourceHighlight:ENABLED TO FALSE.
SET destHighlight:ENABLED TO FALSE.
