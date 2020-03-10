CLEARSCREEN.

LOCAL interval IS 50.
LOCAL sideSamples IS 10.
LOCAL indexNorth IS 0.
LOCAL indexEast IS 0.
LOCAL vectors IS LIST().
LOCAL slopes IS LIST().
LOCAL headings IS LIST().
LOCAL vecDraws IS LIST().
LOCAL slopeInfo IS LIST().
LOCAL headingList IS LIST().
LOCAL slopeList IS LIST().
LOCAL vectorList is LIST().
LOCAL vecDrawList IS LIST().
LOCAL startVector IS V(0,0,0).

FOR indexNorth IN RANGE( -sideSamples, sideSamples + 1, 1) {
  SET headingList TO LIST().
  SET slopeList TO LIST().
  SET vectorList TO LIST().
  SET vecDrawList TO LIST().
  FOR indexEast IN RANGE( -sideSamples, sideSamples + 1, 1) {
    SET slopeInfo TO findDownSlopeInfo(indexNorth * interval, indexEast * interval).
    SET startVector TO SHIP:NORTH:VECTOR * (indexNorth * interval) + east_for(SHIP) *(indexEast * interval).

    headingList:ADD(slopeInfo["heading"]).
    slopeList:ADD(slopeInfo["slope"]).
    vectorList:ADD(slopeInfo["vector"]).
    vecDrawList:ADD(VECDRAW(startVector, interval * 0.75 * slopeInfo["vector"], BLUE, "(" + indexNorth + "," + indexEast + ")" , 2.0, TRUE, 0.2)).

    PRINT "(" + indexNorth + "," + indexEast + ") Slope " + slopeInfo["slope"] + ", heading " + slopeInfo["heading"].
//    LOG "(" + indexNorth + "," + indexEast + ")" TO "0:Local Slope.csv".
//    WAIT 0.05.
  }
  headings:ADD(headingList).
  slopes:ADD(slopeList).
  vectors:ADD(vectorList).
}

LOCAL message IS "".
FOR eachLine IN headings {
  SET message TO "".
  FOR eachHeading IN eachLine {
    SET message TO message + "," + eachHeading.
  }
  LOG message TO "0:Local Slopes.csv".
}

LOG "" TO "0:Local Slopes.csv".

LOCAL message IS "".
FOR eachLine IN slopes {
  SET message TO "".
  FOR eachSlope IN eachLine {
    SET message TO message + "," + eachSlope.
  }
  LOG message TO "0:Local Slopes.csv".
}
AG1 OFF.
UNTIL AG1 {WAIT 0.}
