FUNCTION logArray2Dim {
	PARAMETER array.
	PARAMETER logFileName.
	LOCAL startTime IS MISSIONTIME.
	LOCAL string IS "".
	FOR i IN RANGE(0, array[0]:LENGTH) {
		SET string TO string + "," + i.
	}
	LOG string TO logFileName.

	FOR i IN RANGE(0, array:LENGTH) {
		SET string TO i.
		FOR j IN RANGE(0, array[i]:LENGTH) {
			SET string TO string + "," + array[i][j].
		}
		LOG string TO logFileName.
	}
	LOG "" TO logFileName.
	LOG "Total logging duration:," + (MISSIONTIME - startTime) TO logFileName.
}

FUNCTION findMinSlope {
	PARAMETER centerPosition.
	PARAMETER radius.
	PARAMETER delta.
	LOCAL dataOriginal IS LIST().
	LOCAL north IS SHIP:NORTH:VECTOR.
	LOCAL east IS vcrs(centerPosition - SHIP:BODY:POSITION, north):NORMALIZED.
	
	LOCAL index IS 0.
	FOR northOffset IN RANGE(-radius, radius + 1, delta) {
		dataOriginal:ADD(LIST()).
		FOR eastOffset IN RANGE(-radius, radius + 1, delta) {
			dataOriginal[index]:ADD(SHIP:BODY:GEOPOSITIONOF(centerPosition + northOffset*north + eastOffset*east):TERRAINHEIGHT).
		}
		SET index TO index + 1.
	}

	LOCAL dataShiftedNorth IS LIST().
	FOR i IN RANGE(0, dataOriginal:LENGTH - 1) {
		dataShiftedNorth:ADD(LIST()).
		FOR j IN RANGE(0, dataOriginal:LENGTH) {
			dataShiftedNorth[i]:ADD(dataOriginal[i + 1][j]).
		}
	}
	dataShiftedNorth:ADD(dataShiftedNorth[dataShiftedNorth:LENGTH - 1]).

	LOCAL dataShiftedEast IS LIST().
	FOR i IN RANGE(0, dataOriginal:LENGTH) {
		dataShiftedEast:ADD(LIST()).
		FOR j IN RANGE(0, dataOriginal:LENGTH - 1) {
			dataShiftedEast[i]:ADD(dataOriginal[i][j + 1]).
		}
		dataShiftedEast[i]:ADD(dataOriginal[i][dataOriginal:LENGTH - 1]).
	}
	LOCAL metersNorth IS "".
	LOCAL metersEast IS "".
	LOCAL currentMin IS 10000.
	
	LOCAL derivative IS 0.
	FOR i IN RANGE(0, dataOriginal:LENGTH - 2) {
		FOR j IN RANGE(0, dataOriginal:LENGTH - 2) {
			SET derivative TO (SQRT((dataOriginal[i][j] - dataShiftedNorth[i][j])^2 + (dataOriginal[i][j] - dataShiftedEast[i][j])^2 ) / delta).
			IF derivative < currentMin {
				SET metersNorth TO ((i - dataOriginal:LENGTH/2) * delta).
				SET metersEast TO ((j - dataOriginal:LENGTH/2) * delta).
				SET currentMin TO derivative.
			}
		}
	}
//	logArray2Dim(dataOriginal, "dataOriginal.csv").
//	logArray2Dim(dataShiftedNorth, "dataShiftedNorth.csv").
//	logArray2Dim(dataShiftedEast, "dataShiftedEast.csv").
//	PRINT "Minimum slope spot found at " + metersNorth + " meters north and " + metersEast + " meters east of the target".
//	PRINT "Min slope is " + ROUND(currentMin, 6) + " meters per meter".
	RETURN SHIP:BODY:GEOPOSITIONOF(centerPosition + north * metersNorth + east * metersEast).
}
CLEARSCREEN.
LOCAL startTime IS MISSIONTIME.
LOCAL flatSpot TO findMinSlope(SHIP:POSITION, 1000, 100).
PRINT "First calc: " + ROUND(MISSIONTIME - startTime, 2).
SET startTime TO MISSIONTIME.
SET flatSpot TO findMinSlope(flatSpot:POSITION, 100, 10).
PRINT "Second calc: " + ROUND(MISSIONTIME - startTime, 2).
AG1 OFF.
SET FACING_VD TO VECDRAW(V(0,0,0), flatSpot:POSITION, BLUE, "Flat Spot", 1.0, TRUE, 0.2).
SET FACING_VD:VECUPDATER TO {RETURN flatSpot:POSITION. }.
UNTIL AG1 {
	PRINT "Active " AT (0, 0).
	WAIT 0.
}
PRINT "Inactive " AT (0, 0).
