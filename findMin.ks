@LAZYGLOBAL OFF.

CLEARSCREEN.

// NOTE: Throughout this file, North is the Y axis and East is the X axis.

LOCAL logFileName IS "0:terrainHeight.csv".

FUNCTION getTerrainData {
	PARAMETER distance.
	PARAMETER interval.
	LOCAL northOffset IS 0.
	LOCAL eastOffset IS 0.
	LOCAL dataToLog IS LEXICON().
	dataToLog:ADD("distance", distance).
	dataToLog:ADD("interval", interval).
	LOCAL east IS east_for(SHIP).

	SET northOffset TO -distance.
	SET eastOffset TO -distance.
	UNTIL eastOffset > distance {
		SET northOffset TO -distance.
		UNTIL northOffset > distance {
			dataToLog:ADD("" + eastOffset + "," + northOffset + "", LEXICON("northOffset", northOffset,
																																		 	"eastOffset",  eastOffset,
																																 			"downSlopeInfo", findDownSlopeInfo(northOffset, eastOffset, interval))).
			SET northOffset TO northOffset + interval.
		}
		SET eastOffset TO eastOffset + interval.
	}
	RETURN dataToLog.
}

FUNCTION logTerrainData {
	PARAMETER data.
	PARAMETER param IS "terrainHeight".
	PARAMETER logFileName IS "0:terrainHeight.csv".
	PARAMETER deleteFile IS FALSE.
	PARAMETER useRelativeHeight IS FALSE.
	IF deleteFile DELETEPATH(logFileName).

	// set up the headers
	LOCAL message IS  "":PADLEFT(data["distance"]/data["interval"] + 2):REPLACE(" ",",") + "North" + CHAR(10) + param + ",,".
	LOCAL northOffset IS 0.
	LOCAL eastOffset IS 0.
	SET northOffset TO -data["distance"].
	UNTIL northOffset > data["distance"] {
		SET message TO message + northOffset + ",".
		SET northOffset TO northOffset + data["interval"].
	}

	LOCAL relativeZero IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION):TERRAINHEIGHT.
	SET northOffset TO data["distance"].
	SET eastOffset TO -data["distance"].
	UNTIL northOffset < -data["distance"] {
		IF northOffset = 0 										SET message TO message + char(10) + "West," + northOffset + ",".
		ELSE IF northOffset = data["interval"] SET message TO message + "East" + char(10) + "," + northOffset + ",".
		ELSE 																	SET message TO message + char(10) + "," + northOffset + ",".
		SET eastOffset TO -data["distance"].
		UNTIL eastOffset > data["distance"] {
			IF useRelativeHeight SET message TO message + (data["" + eastOffset + "," + northOffset + ""]["downSlopeInfo"][param] - relativeZero) + ",".
			ELSE                 SET message TO message +  data["" + eastOffset + "," + northOffset + ""]["downSlopeInfo"][param] + ",".

			SET eastOffset TO eastOffset + data["interval"].
		}

		SET northOffset TO northOffset - data["interval"].
	}
	SET message TO message + CHAR(10) + "":PADLEFT(data["distance"]/data["interval"] + 2):REPLACE(" ",",") + "South" + CHAR(10) + ",,".
	LOG message TO logFileName.
}

LOCAL dataToLog IS getTerrainData(200, 20).
logTerrainData(dataToLog, "terrainHeight", logFileName,  TRUE, TRUE).
logTerrainData(dataToLog,         "slope", logFileName, FALSE).
logTerrainData(dataToLog,       "heading", logFileName, FALSE).
logData(dataToLog["0,0"]["downSlopeInfo"], logFileName).

FUNCTION aAlongB {
	PARAMETER a.
	PARAMETER b.
	RETURN VDOT(a, b)*b:NORMALIZED.
}

FUNCTION drawVecDraw {
	PARAMETER vec1.
	PARAMETER vec2.
	PARAMETER colorToUse.
	PARAMETER description.
	PARAMETER waitTime IS 5.
	LOCAL draw IS VECDRAW(vec1, vec2, colorToUse, description, 1.0, TRUE, 0.2).
	LOCAL startTime IS TIME:SECONDS.
	UNTIL TIME:SECONDS > startTime + waitTime {
		WAIT 0.
	}
}

LOCAL northVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), WHITE, "North", 1.0, TRUE, 0.2).
LOCAL eastVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), BLACK, "East", 1.0, TRUE, 0.2).
LOCAL velocityVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Velocity", 1.0, TRUE, 0.2).
LOCAL velocityDownslopeVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Velocity Downslope", 1.0, TRUE, 0.2).
LOCAL velocitySideslopeVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Velocity Sideslope", 1.0, TRUE, 0.2).
LOCAL downslopeVecDraw1 IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Down Slope Vector", 1.0, TRUE, 0.2).

LOCAL downslopeVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Down Slope Vector", 1.0, TRUE, 0.2).
LOCAL downslopeVecDraw2 IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Down Slope Heading", 1.0, TRUE, 0.2).

LOCAL northVec IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Down Slope Vector", 1.0, TRUE, 0.2).


CLEARSCREEN.
PRINT "Press AG1 when done".
AG1 OFF.
AG2 OFF.
AG3 OFF.
LOCAL slopeInfo IS 0.
SET slopeInfo TO findDownSlopeInfo(0, 0, 10).
LOCAL downSlopeVelocity IS 0.
LOCAL sideSlopeVelocity IS 0.

LOCAL minPitch IS 80.

LOCAL T_PID IS PIDLOOP(0.5, 0.1, 0, 0, 1).			// PID loop to control trottle during vertical descent phase
LOCAL H_PID IS PIDLOOP(2.5, 2.5, 1, -(90 - minPitch), (90 - minPitch)).			// PID loop to control heading during hover phase
LOCAL headingSteeringAdjust IS 0.
LOCAL aboveGround IS 0.
LOCAL downSlopeSpeed IS 0.
setLockedSteering(TRUE).
setLockedThrottle(TRUE).
UNTIL (AG2 OR AG3) {
	CLEARSCREEN.
	PRINT "Press AG2 to start moving, or AG3 to end script".
	PRINT "ARCTAN2( Y,  X)".
	PRINT "ARCTAN2( 0,  1): " + ARCTAN2( 0,  1).
	PRINT "ARCTAN2( 1,  1): " + ARCTAN2( 1,  1).
	PRINT "ARCTAN2( 1,  0): " + ARCTAN2( 1,  0).
	PRINT "ARCTAN2( 1, -1): " + ARCTAN2( 1, -1).
	PRINT "ARCTAN2( 0, -1): " + ARCTAN2( 0, -1).
	PRINT "ARCTAN2(-1, -1): " + ARCTAN2(-1, -1).
	PRINT "ARCTAN2(-1,  0): " + ARCTAN2(-1,  0).
	SET aboveGround TO heightAboveGround().
	SET slopeInfo TO findDownSlopeInfo(0, 0, 10).
	SET downSlopeVelocity TO aAlongB(SHIP:VELOCITY:SURFACE, slopeInfo["vectorFlat"]).
	SET sideSlopeVelocity TO VXCL(SHIP:UP:VECTOR,VXCL(downSlopeVelocity, SHIP:VELOCITY:SURFACE)).
	SET northVecDraw:VEC TO 10 * NORTH:VECTOR.
	SET eastVecDraw:VEC TO 10 * east_for(SHIP).
	SET downslopeVecDraw:VEC TO 10*slopeInfo["vectorFlat"].
	SET velocityVecDraw:VEC TO SHIP:VELOCITY:SURFACE.
	SET velocityDownslopeVecDraw:VEC TO downSlopeVelocity.
	SET velocitySideslopeVecDraw:VEC TO sideSlopeVelocity.

	SET downslopeVecDraw:VEC TO 10*slopeInfo["vector"].
	SET downslopeVecDraw2:VEC TO 10*slopeInfo["vectorFlat"].

	WAIT 0.
}

IF AG2 {
	LOCAL mode IS 0.
	LOCAL startTime IS 0.
	UNTIL mode > 2 {
		CLEARSCREEN.
		SET northVecDraw:VEC TO 10 * NORTH:VECTOR.
		SET eastVecDraw:VEC TO 10 * east_for(SHIP).
		SET aboveGround TO heightAboveGround().
		SET slopeInfo TO findDownSlopeInfo(0, 0, 10).
		SET downSlopeVelocity TO aAlongB(SHIP:VELOCITY:SURFACE, slopeInfo["vectorFlat"]).
		SET sideSlopeVelocity TO VXCL(SHIP:UP:VECTOR,VXCL(downSlopeVelocity, SHIP:VELOCITY:SURFACE)).
		SET downSlopeSpeed TO VDOT(downSlopeVelocity, slopeInfo["vectorFlat"]).
		SET northVecDraw:VEC TO 10 * NORTH:VECTOR.
		SET eastVecDraw:VEC TO 10 * east_for(SHIP).
		SET downslopeVecDraw:VEC TO 10*slopeInfo["Vector"].
		SET downslopeVecDraw2:VEC TO 10*slopeInfo["vectorFlat"].
		SET velocityVecDraw:VEC TO SHIP:VELOCITY:SURFACE.
		SET velocityDownslopeVecDraw:VEC TO downSlopeVelocity.
		SET velocitySideslopeVecDraw:VEC TO sideSlopeVelocity.
		PRINT "Downslope Heading:     " + ROUND(slopeInfo["Heading"], 3) + " deg from North".
		PRINT "Velocity:              " + distanceToString(SHIP:VELOCITY:SURFACE:MAG, 3) + "/s".
		PRINT "Velocity Downslope:    " + distanceToString(downSlopeSpeed, 3) + "/s".
		PRINT "Velocity Side:         " + distanceToString(sideSlopeVelocity:MAG, 3) + "/s".
		PRINT "Velocity Vertical:     " + distanceToString(VERTICALSPEED, 3) + "/s".
		PRINT "Velocity Vertical SP:  " + distanceToString(T_PID:SETPOINT, 3) + "/s".
		PRINT "Distance Above Ground: " + distanceToString(aboveGround, 3).
		PRINT "H_PID Output:          " + ROUND(H_PID:OUTPUT, 3).
		PRINT "Slope:                 " + ROUND(slopeInfo["slope"], 2) + " deg".

		PRINT "Mode    " + mode AT (40, 0).
		PRINT "AGL = " + ROUND(aboveGround) + "       " AT (40, 2).
		PRINT "SrfSpd " + ROUND(VELOCITY:SURFACE:MAG, 3) + "     " AT (40, 3).
		PRINT "SrfSpd < 0.5     " AT (40, 4).

		IF mode = 0 {
			SET T_PID:SETPOINT TO (112.5 - aboveGround) / 12.5.
			SET H_PID:SETPOINT TO 5.0.

			SET globalThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
			IF H_PID:OUTPUT < 0 SET headingSteeringAdjust TO -2 * sideSlopeVelocity:MAG.
			ELSE SET headingSteeringAdjust TO 2 * sideSlopeVelocity:MAG.
			IF headingSteeringAdjust > 30 SET headingSteeringAdjust TO 30.
			IF headingSteeringAdjust < 30 SET headingSteeringAdjust TO -30.
			SET globalSteer TO HEADING (slopeInfo["Heading"] + headingSteeringAdjust, 90 - H_PID:UPDATE(TIME:SECONDS, downSlopeSpeed)).
			IF (AG1 OR (slopeInfo["Slope"] < 5.0)) SET mode TO mode + 1.
		}

		IF mode = 1 {
			SET T_PID:SETPOINT TO MIN(-2, MIN(-aboveGround/25.0, (25 - aboveGround) / 12.5)).
			SET globalThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
			SET globalSteer TO HEADING(yaw_for(-VELOCITY:SURFACE), MAX(minPitch, pitch_for(-VELOCITY:SURFACE))).
			IF (AG1 OR aboveGround < 2) SET mode TO mode + 1.
		}

		IF mode = 2 {
			IF startTime = 0 {
				SET startTime TO TIME:SECONDS.
			}
			RCS ON.
			SET globalThrottle TO 0.
			SET globalSteer TO HEADING (yaw_for(-VELOCITY:SURFACE), MAX(minPitch, pitch_for(-VELOCITY:SURFACE))).
			IF (TIME:SECONDS > startTime + 5) AND (VELOCITY:SURFACE:MAG < 0.5) SET mode TO MODE + 1.
		}
		WAIT 0.
	}
}
RCS OFF.
SET globalThrottle TO 0.
SET globalSteer TO SHIP:UP.
setLockedSteering(FALSE).
setLockedThrottle(FALSE).

IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Landed on " + SHIP:BODY:NAME.
ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
