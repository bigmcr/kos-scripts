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
	LOCAL northVector IS SHIP:NORTH:VECTOR.
	LOCAL east IS vcrs(centerPosition - SHIP:BODY:POSITION, northVector):NORMALIZED.

	LOCAL index IS 0.
	FOR northOffset IN RANGE(-radius, radius + 1, delta) {
		dataOriginal:ADD(LIST()).
		FOR eastOffset IN RANGE(-radius, radius + 1, delta) {
			dataOriginal[index]:ADD(SHIP:BODY:GEOPOSITIONOF(centerPosition + northOffset*northVector + eastOffset*east):TERRAINHEIGHT).
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
	RETURN SHIP:BODY:GEOPOSITIONOF(centerPosition + northVector * metersNorth + east * metersEast).
}

FUNCTION calculateFakeTerrain {
	PARAMETER X, Y.
	RETURN 100*((X/100)^3+(Y/100)^5).
}

// Return the vector pointing in the direction of downslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of downhill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of downhill in a vector with length of 1 meter.
FUNCTION findDownSlopeInfoFake {
	PARAMETER northOffset IS 0.0.
	PARAMETER eastOffset IS 0.0.
	PARAMETER distance IS 5.0.
	LOCAL terrainHeight IS calculateFakeTerrain(0, 0).
	LOCAL heightNorth IS calculateFakeTerrain(northOffset, 0) - terrainHeight.
	LOCAL heightEast  IS calculateFakeTerrain(0,  eastOffset) - terrainHeight.
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("heading", ARCTAN2(heightNorth, heightEast) + 90).
	returnMe:ADD("slope", ARCTAN2(V(heightNorth, heightEast, 0):MAG), distance).
  returnMe:ADD("vector", 10*(SHIP:NORTH:VECTOR*ANGLEAXIS(-returnMe["slope"], east_for(ship)))*ANGLEAXIS(returnMe["heading"], SHIP:UP:VECTOR)).
	RETURN returnMe.
}

CLEARSCREEN.
LOCAL downSlopeInfo IS findDownSlopeInfo().
LOCAL downSlopeVectorVD      TO VECDRAW(V(0,0,0), V(0,0,0),    RED, "Vector", 1.0, TRUE, 0.2).
LOCAL downSlopeVectorNorthVD TO VECDRAW(V(0,0,0), V(0,0,0),  GREEN,  "North", 1.0, TRUE, 0.2).
LOCAL downSlopeVectorEastVD  TO VECDRAW(V(0,0,0), V(0,0,0), YELLOW,   "East", 1.0, TRUE, 0.2).
LOCAL startTime IS MISSIONTIME.
AG1 OFF.
LOCAL northOffset IS 0.
LOCAL eastOffset IS 0.
LOCAL distance IS 1.
LOCAL logFileName IS "0:slopes.csv".
DELETEPATH(logFileName).
LOCAL logNow IS FALSE.
LOG "Mission Time (s),North Offset (m),East Offset (m),Distance (m),Terrain Height (m),Height North (m),Height East (m),Slope (deg),Heading (deg),Slope (Calc'd deg),Heading (Calc'd deg)" TO logFileName.
WHEN AG9 THEN { SET northOffset TO 0.	SET eastOffset TO 0. SET distance TO 1. SET logNow TO TRUE. AG9 OFF. RETURN TRUE.}
WHEN AG8 THEN { SET northOffset TO northOffset + distance/2.                  SET logNow TO TRUE. AG8 OFF. RETURN TRUE.}
WHEN AG7 THEN { SET northOffset TO northOffset - distance/2.                  SET logNow TO TRUE. AG7 OFF. RETURN TRUE.}
WHEN AG6 THEN { SET eastOffset TO eastOffset + distance/2.                    SET logNow TO TRUE. AG6 OFF. RETURN TRUE.}
WHEN AG5 THEN { SET eastOffset TO eastOffset - distance/2.                    SET logNow TO TRUE. AG5 OFF. RETURN TRUE.}
WHEN AG4 THEN { SET distance TO distance * 2.0.                               SET logNow TO TRUE. AG4 OFF. RETURN TRUE.}
WHEN AG3 THEN { SET distance TO distance / 2.0.                               SET logNow TO TRUE. AG3 OFF. RETURN TRUE.}

FOR northOffset IN RANGE(-100, 101, 1) {
	FOR eastOffset IN RANGE(-100, 101, 1) {
		PRINT "Coordinate (N, E): (" + ROUND(northOffset, 2) + ", " + ROUND(eastOffset, 2) + ")     " AT(0, 3).
		SET downSlopeInfo TO findDownSlopeInfo(northOffset, eastOffset, distance).
		LOG (MISSIONTIME - startTime) + "," + northOffset + "," + eastOffset + "," + distance + "," + downSlopeInfo["terrainHeight"] + "," + downSlopeInfo["heightNorth"] + "," + downSlopeInfo["heightEast"] + "," + downSlopeInfo["slope"] + "," + downSlopeInfo["heading"] TO logFileName.
	}
}

UNTIL TRUE {
	SET downSlopeInfo TO findDownSlopeInfo(northOffset, eastOffset, distance).
	SET downSlopeVectorVD:START      TO 2 * UP:VECTOR + SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (       0 + northOffset)*SHIP:NORTH:VECTOR + (       0 + eastOffset)*east_for(SHIP)):POSITION.
	SET downSlopeVectorNorthVD:START TO 2 * UP:VECTOR + SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (distance + northOffset)*SHIP:NORTH:VECTOR + (       0 + eastOffset)*east_for(SHIP)):POSITION.
	SET downSlopeVectorEastVD:START  TO 2 * UP:VECTOR + SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (       0 + northOffset)*SHIP:NORTH:VECTOR + (distance + eastOffset)*east_for(SHIP)):POSITION.

	SET downSlopeVectorNorthVD:VEC   TO 10 * UP:VECTOR.
	SET downSlopeVectorEastVD:VEC    TO 10 * UP:VECTOR.
	SET downSlopeVectorVD:VEC        TO 10 * downSlopeInfo["vector"]:NORMALIZED.

	PRINT "Slope " + ROUND(downSlopeInfo["slope"], 1) + " deg    " AT(0, 0).
	PRINT "Heading " + ROUND(downSlopeInfo["heading"], 1) + " deg    " AT(0, 1).
	PRINT "Time " + timeToString(MISSIONTIME - startTime) + "     " AT(0, 2).
	PRINT "Coordinate (N, E): (" + ROUND(northOffset, 2) + ", " + ROUND(eastOffset, 2) + ")     " AT(0, 3).
	PRINT "Distance: " + distanceToString(distance, 2) + "     " AT(0, 4).
	PRINT "Value at Coordinate " + ROUND(downSlopeInfo["terrainHeight"], 3) + "     " AT(0, 5).
	PRINT "Value at North "      + ROUND(downSlopeInfo["heightNorth"], 3) + "     " AT(0, 6).
	PRINT "Value at East "       + ROUND(downSlopeInfo["heightEast"], 3) + "     " AT(0, 7).
	IF logNow {
		LOG (MISSIONTIME - startTime) + "," + northOffset + "," + eastOffset + "," + distance + "," + downSlopeInfo["terrainHeight"] + "," + downSlopeInfo["heightNorth"] + "," + downSlopeInfo["heightEast"] + "," + downSlopeInfo["slope"] + "," + downSlopeInfo["heading"] TO logFileName.
		SET logNow TO FALSE.
	}
	WAIT 0.
}
