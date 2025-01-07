@LAZYGLOBAL OFF.
CLEARSCREEN.

LOCAL processorList IS LIST().
LOCAL processorPartList IS LIST().
LIST PROCESSORS IN processorList.
FOR eachProcessor IN processorList {
  processorPartList:ADD(eachProcessor:PART).
}

LOCAL coreHighlight IS LIST().
LOCAL sourceHighlight IS HIGHLIGHT(CORE:PART, RED).
LOCAL destHighlight IS LIST().
SET sourceHighlight:ENABLED TO FALSE.

LOCAL sourceCore IS 0.
LOCAL destCore IS LIST().

FOR eachPart IN processorPartList {
  coreHighlight:ADD(HIGHLIGHT(eachPart, MAGENTA)).
}

LOCAL mode IS "Source".
LOCAL tempChar IS "".
LOCAL index IS 0.
LOCAL sourceIndex IS 0.
LOCAL destIndex IS 0.
LOCAL allFlag IS FALSE.
UNTIL mode = "done" {
  CLEARSCREEN.
  IF TERMINAL:INPUT:HASCHAR {
    SET tempChar TO TERMINAL:INPUT:GETCHAR().
  }
  IF mode = "Source" {
    PRINT "Now displaying all " + processorPartList:LENGTH + " processors, one at a time".
    PRINT "Press arrows to cycle through them until you are at the SOURCE processor".
    PRINT "Then press Enter".
    PRINT "Current processor selected: " + (index + 1).
    PRINT "Processor Count: " + coreHighlight:LENGTH.
    IF tempChar = TERMINAL:INPUT:LEFTCURSORONE {SET index TO index - 1. SET tempChar TO "".}
    IF index < 0 SET index TO coreHighlight:LENGTH - 1.

    IF tempChar = TERMINAL:INPUT:RIGHTCURSORONE {SET index TO index + 1. SET tempChar TO "".}
    IF index >= coreHighlight:LENGTH SET index TO 0.

    FOR eachHighlight IN RANGE(0, coreHighlight:LENGTH) {
      SET coreHighlight[eachHighlight]:ENABLED TO eachHighlight = index.
    }
    IF tempChar = TERMINAL:INPUT:ENTER {
      SET sourceCore TO processorPartList[index].
      SET mode TO "Dest".
      SET tempChar TO "".
    }
  }
  IF mode = "Dest" {
    PRINT "Now displaying all " + processorPartList:LENGTH + " processors, one at a time".
    PRINT "Press arrows to cycle through them until you are at the DESTINATION processor".
    PRINT "Or press A to select all other processors".
    PRINT "Then press Enter".
    PRINT "Current processor selected: " + (index + 1).
    IF processorPartList[index]:UID = processorPartList[sourceIndex]:UID SET index TO index + 1.

    IF tempChar = "A" {SET index TO -1. SET allFlag TO TRUE. SET tempChar TO "".}

    IF tempChar = TERMINAL:INPUT:LEFTCURSORONE {SET index TO index - 1. SET tempChar TO "".}
    IF index < 0 SET index TO processorPartList:LENGTH - 1.

    IF tempChar = TERMINAL:INPUT:RIGHTCURSORONE {SET index TO index + 1. SET tempChar TO "".}
    IF index >= processorPartList:LENGTH SET index TO 0.

    FOR eachIndex IN RANGE(0, processorPartList:LENGTH) {
      SET coreHighlight[eachIndex]:ENABLED TO (eachIndex = index) OR (allFlag AND (index <> sourceIndex)).
    }
    IF tempChar = TERMINAL:INPUT:ENTER {
      SET mode TO "Confirm".
      SET tempChar TO "".

      // if the allFlag is set, add all non-source processors to the destination lists.
      IF allFlag {
        FOR eachProcessorPart IN processorPartList {
          IF eachProcessorPart:UID <> sourceCore:UID {
            destCore:ADD(eachProcessorPart).
            destHighlight:ADD(HIGHLIGHT(eachProcessorPart, RED)).
          }
        }
        FOR eachHighlight IN destHighlight {
          SET eachHighlight:ENABLED TO TRUE.
        }
      } ELSE { // if allFlag is not set, add the single core and highlight to the lists.
        destCore:ADD(processorPartList[index]).
        destHighlight:ADD(HIGHLIGHT(destCore[0], RED)).
        SET destHighlight[0]:ENABLED TO TRUE.
      }
      // turn off highlighting for all other processors.
      FOR eachHighlight IN RANGE(0, coreHighlight:LENGTH) {
        SET coreHighlight[eachHighlight]:ENABLED TO FALSE.
      }
    }
  }
  IF mode = "Confirm" {
    PRINT "Press Enter to confirm and copy all scripts over.".
    PRINT "The red core is the source, green is the destination.".
    PRINT "Press Backspace to cancel.".
    SET sourceHighlight TO HIGHLIGHT(sourceCore, RED).
    SET sourceHighlight:ENABLED TO TRUE.
    IF tempChar = TERMINAL:INPUT:ENTER {
      LOCAL volumesCopiedTo IS 0.
      FOR eachProcessor IN destCore {
        LOCAL dest IS eachProcessor:GETMODULE("kOSProcessor").
        COPYPATH(sourceCore:GETMODULE("kOSProcessor"):VOLUME, dest:VOLUME).
        SET dest:BOOTFILENAME TO sourceCore:GETMODULE("kOSProcessor"):BOOTFILENAME.
        SET volumesCopiedTo TO volumesCopiedTo + 1.
      }
      SET mode TO "done".
      SET loopMessage TO sourceCore:GETMODULE("kOSProcessor"):VOLUME:FILES:LENGTH + " files copied to " + volumesCopiedTo + " cores".
    }
    IF tempChar = TERMINAL:INPUT:BACKSPACE {
      SET mode TO "done".
      SET loopMessage TO "Parts Highlighted!".
    }
  }
  SET tempChar TO "".
  WAIT 0.
}
SET sourceHighlight:ENABLED TO FALSE.
FOR eachHighlight IN destHighlight SET eachHighlight:ENABLED TO FALSE.
