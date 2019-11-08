function yaw_vector {
  parameter vect.

  local trig_x is vdot(SHIP:north:vector, vect).
  local trig_y is vdot(east_for(SHIP), vect).

  local result is arctan2(trig_y, trig_x).

  if result < 0 { 
    return 360 + result.
  } else {
    return result.
  }
}

function east_for {
  parameter ves.

  return vcrs(ves:up:vector, ves:north:vector).
}

// Find the slope of the ground the given number of meters north and east of the ship.
FUNCTION findSlopeOfGround {
	PARAMETER samplePos.
	PARAMETER distNorth IS 0.5.
	PARAMETER distEast  IS 0.5.
	IF distNorth = 0 SET distNorth TO 0.5.
	IF distEast  = 0 SET distEast  TO 0.5.
	LOCAL heightNorth IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + distNorth*SHIP:NORTH:VECTOR):TERRAINHEIGHT - SHIP:GEOPOSITION:TERRAINHEIGHT.
	LOCAL heightEast  IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + distEast *   east_for(SHIP)):TERRAINHEIGHT - SHIP:GEOPOSITION:TERRAINHEIGHT.
	LOCAL NSVector IS distNorth*SHIP:NORTH:VECTOR + heightNorth * SHIP:UP:VECTOR.
	LOCAL EWVector IS distEast *east_for(SHIP)    + heightEast  * SHIP:UP:VECTOR.
	LOCAL angleVector IS VCRS(NSVector, EWVector).
	LOCAL tilt IS VANG( angleVector, SHIP:UP:VECTOR).
	LOCAL compass IS yaw_vector(angleVector).
	LOCAL pointHeight IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + distNorth*SHIP:NORTH:VECTOR + distEast*east_for(SHIP)):TERRAINHEIGHT - SHIP:GEOPOSITION:TERRAINHEIGHT.
	IF tilt > 90 SET tilt TO 180 - tilt.
//	LOG MISSIONTIME + "," + distNorth + "," + distEast + "," + heightNorth + "," + heightEast + "," + tilt + "," + NSVector + "," + EWVector + "," + angleVector + "," + SHIP:UP:VECTOR TO "LatLong.csv".
	RETURN LIST(distNorth, distEast, pointHeight, tilt, compass).
}

//LOG "Mission Time,North,East,Height North,Height East,tilt,NS Vector X,NS Vector Y,NS Vector Z,EW Vector X,EW Vector Y,EW Vector Z,Angle Vector X,Angle Vector Y,Angle Vector Z,Up Vector X,Up Vector Y,Up Vector Z" TO "LatLong.csv".

FUNCTION logData {
	PARAMETER data.
	PARAMETER componenet.
	PARAMETER logFileName.
	LOG "Start at:," + MISSIONTIME TO logFileName.
	LOG "" TO logFileName.
	LOG "" TO logFileName.

	LOCAL dist IS 100.
	LOCAL spacing IS 10.

	LOCAL string IS "".
	LOCAL count IS SQRT(data:LENGTH).

	FOR eastOffset IN RANGE(-dist, dist + 1, spacing) {
		SET string TO string + "," + eastOffset.
	}
	LOG string TO logFileName.

	FOR northOffset IN RANGE(0, count) {
		SET string TO northOffset.
		FOR eastOffset IN RANGE(0, count) {
			SET string TO string + "," + dataList[count * northOffset + eastOffset][componenet].
		}
		LOG string TO logFileName.
	}
	LOG "" TO logFileName.
	LOG "End at:," + MISSIONTIME TO logFileName.
}

//UNTIL AG1 {
LOCAL dist IS 100.
LOCAL spacing IS 10.

LOCAL dataList IS LIST().

FOR northOffset IN RANGE(-dist, dist + 1, spacing) {
	FOR eastOffset IN RANGE(-dist, dist + 1, spacing) {
		dataList:ADD(findSlopeOfGround(northOffset, eastOffset)).
	}
}

PRINT "Data has " + dataList:LENGTH + " points of data in it.".
logData(dataList, 2, "MapDataHeight.csv").
logData(dataList, 3, "MapDataSlope.csv").
logData(dataList, 4, "MapDataCompass.csv").
//}