@LAZYGLOBAL OFF.

CLEARSCREEN.

FUNCTION findLowestSpot {
	PARAMETER params.
	PARAMETER detailed IS FALSE.
	LOCAL east IS east_for(SHIP).
	LOCAL testTerrainHeight IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION):TERRAINHEIGHT.
	LOCAL eastInterval IS 1.
	FOR northOffset IN RANGE (-params["distance"], params["distance"] + 1, params["interval"]) {
		IF (detailed OR (ABS(northOffset) = params["distance"])) SET eastInterval TO params["interval"].
		ELSE SET eastInterval TO 2 * params["distance"].
		FOR eastOffset IN RANGE (-params["distance"], params["distance"] + 1, eastInterval) {
			SET testTerrainHeight TO SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + northOffset * northVector + eastOffset * east):TERRAINHEIGHT.
//			PRINT "(N, E) = (" + ROUND(northOffset) + "," + ROUND(eastOffset) + ")".
			IF testTerrainHeight > params["terrainHeight"] {
				SET params["terrainHeight"] TO testTerrainHeight.
				SET params["northOffset"] TO northOffset.
				SET params["eastOffset"] TO eastOffset.
				SET params["verticalOffset"] TO ALTITUDE - testTerrainHeight.
			}
		}
	}
}

//PIDLOOP(Kp, Ki, Kd, min_output, max_output, epsilon).
LOCAL T_PID   IS PIDLOOP(0.5, 0.1,   0,   0,  1).			// PID loop to control vertical velocity
LOCAL ALT_PID IS PIDLOOP(0.2, 0.0, 0.5, -15, 15).			// PID loop to control vertical position
LOCAL H_PID   IS PIDLOOP(2.5, 2.5,   1, -15, 15).     // PID loop to control heading during hover phase

SET ALT_PID:SETPOINT TO 500.
ALT_PID:RESET.

LOCAL oldTime IS ROUND(TIME:SECONDS, 1).
LOCAL oldVSpeed IS 0.
LOCAL oldHSpeed IS 0.
LOCAL oldDistance IS SHIP:BODY:RADIUS.
LOCAL velocityPitch IS pitch_for(-VELOCITY:SURFACE).
LOCAL hAccel IS 0.
LOCAL vAccel IS 0.
LOCAL aboveGround IS heightAboveGround().
LOCAL update IS 0.
LOCAL mode TO 1.
LOCAL cancelHoriz IS TRUE.

SET globalSteer TO -VELOCITY:SURFACE.
SET globalThrottle TO 0.
setLockedSteering(TRUE).
setLockedThrottle(TRUE).
RCS OFF.
PANELS OFF.

// Engine staging - this should drop any used stage
WHEN MAXTHRUST = 0 THEN {
	PRINT "Staging from max thrust".
	stageFunction().
}

SET globalThrottle TO 1.

LOCAL pitchValue IS 0.
LOCAL headingValue IS 90.
LOCAL startTime IS 0.
LOCAL headerCreated IS FALSE.
LOCAL gravityAccel TO 0.
LOCAL effectiveAccel TO 0.
LOCAL minTimeToStop TO 0.
LOCAL downSlopeInfo IS LEXICON().
LOCAL headingSteeringAdjust IS 0.
LOCAL logFileName IS "0:findBottom.csv".

AG1 OFF.

LOCAL downslopeVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Down Slope Direction", 1.0, FALSE, 0.2).
LOCAL velocityVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Velocity", 1.0, TRUE, 0.2).

LOCAL counter IS 0.
LOCAL rangeData IS LEXICON().
rangeData:ADD("long",LEXICON()).
rangeData["long"]:ADD("northOffset", 0).
rangeData["long"]:ADD("eastOffset", 0).
rangeData["long"]:ADD("verticalOffset", 0).
rangeData["long"]:ADD("terrainHeight", SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION):TERRAINHEIGHT).
rangeData["long"]:ADD("distance", 1000).
rangeData["long"]:ADD("interval", 100).

rangeData:ADD("medium",LEXICON()).
rangeData["medium"]:ADD("northOffset", 0).
rangeData["medium"]:ADD("eastOffset", 0).
rangeData["medium"]:ADD("verticalOffset", 0).
rangeData["medium"]:ADD("terrainHeight", SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION):TERRAINHEIGHT).
rangeData["medium"]:ADD("distance", 500).
rangeData["medium"]:ADD("interval", 50).

rangeData:ADD("short",LEXICON()).
rangeData["short"]:ADD("northOffset", 0).
rangeData["short"]:ADD("eastOffset", 0).
rangeData["short"]:ADD("verticalOffset", 0).
rangeData["short"]:ADD("terrainHeight", SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION):TERRAINHEIGHT).
rangeData["short"]:ADD("distance", 100).
rangeData["short"]:ADD("interval", 10).

LOCAL longVD IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Long Distance", 1.0, TRUE, 0.2).
LOCAL mediumVD IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Medium Distance", 1.0, TRUE, 0.2).
LOCAL shortVD IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Short Distance", 1.0, TRUE, 0.2).
LOCAL desiredHeading IS 0.
LOCAL east IS east_for(SHIP).
LOCAL northVector IS northVector:VECTOR.

LOCAL boundaryVDs IS LEXICON().
boundaryVDs:ADD("long",LIST()).
boundaryVDs["Long"]:ADD(VECDRAW( rangeData["long"]["distance"]*northVector + rangeData["long"]["distance"]*east, -2*rangeData["long"]["distance"]* east, YELLOW, "north", 1.0, TRUE, 0.2)).
boundaryVDs["Long"]:ADD(VECDRAW(-rangeData["long"]["distance"]*northVector + rangeData["long"]["distance"]*east,  2*rangeData["long"]["distance"]*northVector, YELLOW,  "EAST", 1.0, TRUE, 0.2)).
boundaryVDs["Long"]:ADD(VECDRAW( rangeData["long"]["distance"]*northVector - rangeData["long"]["distance"]*east, -2*rangeData["long"]["distance"]*northVector, YELLOW,  "WEST", 1.0, TRUE, 0.2)).
boundaryVDs["Long"]:ADD(VECDRAW(-rangeData["long"]["distance"]*northVector - rangeData["long"]["distance"]*east,  2*rangeData["long"]["distance"]* east, YELLOW, "SOUTH", 1.0, TRUE, 0.2)).
boundaryVDs:ADD("medium",LIST()).
boundaryVDs["medium"]:ADD(VECDRAW( rangeData["medium"]["distance"]*northVector + rangeData["medium"]["distance"]*east, -2*rangeData["medium"]["distance"]* east, BLUE, "north", 1.0, TRUE, 0.2)).
boundaryVDs["medium"]:ADD(VECDRAW(-rangeData["medium"]["distance"]*northVector + rangeData["medium"]["distance"]*east,  2*rangeData["medium"]["distance"]*northVector, BLUE,  "EAST", 1.0, TRUE, 0.2)).
boundaryVDs["medium"]:ADD(VECDRAW( rangeData["medium"]["distance"]*northVector - rangeData["medium"]["distance"]*east, -2*rangeData["medium"]["distance"]*northVector, BLUE,  "WEST", 1.0, TRUE, 0.2)).
boundaryVDs["medium"]:ADD(VECDRAW(-rangeData["medium"]["distance"]*northVector - rangeData["medium"]["distance"]*east,  2*rangeData["medium"]["distance"]* east, BLUE, "SOUTH", 1.0, TRUE, 0.2)).
boundaryVDs:ADD("short",LIST()).
boundaryVDs["short"]:ADD(VECDRAW( rangeData["short"]["distance"]*northVector + rangeData["short"]["distance"]*east, -2*rangeData["short"]["distance"]* east, RED, "north", 1.0, TRUE, 0.2)).
boundaryVDs["short"]:ADD(VECDRAW(-rangeData["short"]["distance"]*northVector + rangeData["short"]["distance"]*east,  2*rangeData["short"]["distance"]*northVector, RED,  "EAST", 1.0, TRUE, 0.2)).
boundaryVDs["short"]:ADD(VECDRAW( rangeData["short"]["distance"]*northVector - rangeData["short"]["distance"]*east, -2*rangeData["short"]["distance"]*northVector, RED,  "WEST", 1.0, TRUE, 0.2)).
boundaryVDs["short"]:ADD(VECDRAW(-rangeData["short"]["distance"]*northVector - rangeData["short"]["distance"]*east,  2*rangeData["short"]["distance"]* east, RED, "SOUTH", 1.0, TRUE, 0.2)).

LOCAL headingOffsetVD IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Heading Offset", 1.0, TRUE, 0.2).
LOCAL headingCourseVD IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Heading Course", 1.0, TRUE, 0.2).
LOCAL groundVelocity IS VXCL(SHIP:UP:VECTOR, VELOCITY:SURFACE).
LOCAL highDirectionSpeed IS VDOT(groundVelocity, HEADING(yaw_for(rangeData["long"]["northOffset"] * northVector + rangeData["long"]["eastOffset"] * east), 0):VECTOR).

UNTIL AG1 {
	SET downSlopeInfo TO findDownSlopeInfo().
	SET aboveGround TO heightAboveGround().
	SET east TO east_for(SHIP).
	SET groundVelocity TO VXCL(SHIP:UP:VECTOR, VELOCITY:SURFACE).
	SET highDirectionSpeed TO VDOT(groundVelocity, HEADING(yaw_for(rangeData["long"]["northOffset"] * northVector + rangeData["long"]["eastOffset"] * east), 0):VECTOR).
	findLowestSpot(rangeData["long"], TRUE).
	findLowestSpot(rangeData["medium"], TRUE).
	findLowestSpot(rangeData["short"], TRUE).

	SET longVD:VEC   TO   rangeData["long"]["northOffset"] * northVector +   rangeData["long"]["eastOffset"] * east -   rangeData["long"]["verticalOffset"] * SHIP:UP:VECTOR.
	SET mediumVD:VEC TO rangeData["medium"]["northOffset"] * northVector + rangeData["medium"]["eastOffset"] * east - rangeData["medium"]["verticalOffset"] * SHIP:UP:VECTOR.
	SET shortVD:VEC  TO  rangeData["short"]["northOffset"] * northVector +  rangeData["short"]["eastOffset"] * east -  rangeData["short"]["verticalOffset"] * SHIP:UP:VECTOR.
	SET velocityVecDraw:VEC TO MIN(10,VELOCITY:SURFACE:MAG) * VELOCITY:SURFACE:NORMALIZED.

	PRINT "Long Range    " AT(40, 10).
	PRINT " North Offset " + ROUND(rangeData["long"]["northOffset"]) + "   " AT(40, 11).
	PRINT "  East Offset " + ROUND(rangeData["long"]["eastOffset"]) + "   " AT(40, 12).
	PRINT "       Height " + distanceToString(rangeData["long"]["terrainHeight"], 3) + "   " AT(40, 13).
	PRINT "Medium Range  " AT(40, 14).
	PRINT " North Offset " + ROUND(rangeData["medium"]["northOffset"]) + "   " AT(40, 15).
	PRINT "  East Offset " + ROUND(rangeData["medium"]["eastOffset"]) + "   " AT(40, 16).
	PRINT "       Height " + distanceToString(rangeData["medium"]["terrainHeight"], 3) + "   " AT(40, 17).
	PRINT "Short Range   " AT(40, 18).
	PRINT " North Offset " + ROUND(rangeData["short"]["northOffset"]) + "   " AT(40, 19).
	PRINT "  East Offset " + ROUND(rangeData["short"]["eastOffset"]) + "   " AT(40, 20).
	PRINT "       Height " + distanceToString(rangeData["short"]["terrainHeight"], 3) + "   " AT(40, 21).
	PRINT "Mode " + mode AT (40, 0).

	IF (TIME:SECONDS <> oldTime) {
		SET hAccel TO (GROUNDSPEED - oldHSpeed)/(TIME:SECONDS - oldTime).
		SET vAccel TO (VERTICALSPEED - oldVSpeed)/(TIME:SECONDS - oldTime).
		SET gravityAccel TO BODY:MU/(ALTITUDE + BODY:RADIUS)^2.
		SET effectiveAccel TO shipInfo["Maximum"]["Accel"] - gravityAccel.
		IF effectiveAccel <> 0 SET minTimeToStop TO VERTICALSPEED / effectiveAccel.
		SET minTimeToStop TO -VERTICALSPEED / effectiveAccel.

		PRINT "Horizontal Speed " + distanceToString(GROUNDSPEED, 2) + "/s     " AT (0, 0).
		PRINT "Horizontal Acceleration " + distanceToString(hAccel, 2) + "/s^2    " AT (0, 1).
		PRINT "Vertical Speed " + distanceToString(VERTICALSPEED, 2) + "/s    " AT (0, 2).
		PRINT "Vertical Acceleration " + distanceToString(vAccel, 2) + "/s^2    " AT (0, 3).
		PRINT "Ground Speed = " + distanceToString(SHIP:GROUNDSPEED, 3) + "/s     " AT (0, 4).
		PRINT "Slope of Ground " + ROUND(downSlopeInfo["slope"], 2) + " deg    " AT (0, 5).
		PRINT "Slope of Ground " + distanceToString(TAN(downSlopeInfo["slope"]) * 100, 1) + "/100 m     " AT (0, 6).
		PRINT "Ground Slope Heading = " + ROUND(downSlopeInfo["heading"], 2) + " deg from northVector     " AT (0, 7).
		PRINT "High Direction Speed " + distanceToString(highDirectionSpeed, 2) + "/s      " AT (0, 8).
		PRINT "Throttle at " + ROUND(THROTTLE * 100) + "%    " AT (0, 10).
	  PRINT "H_PID at " + ROUND(H_PID:OUTPUT, 2) + " deg from vertical    " AT (0, 11).

		IF connectionToKSC() {
			LOCAL message IS "".
			IF NOT headerCreated {
				DELETEPATH(logFileName).
				SET headerCreated TO TRUE.
				SET message TO "Mission Time,".
				SET message TO message + "Maximum Accel,".
				SET message TO message + "Effective Accel,".
				SET message TO message + "Gravity Accel,".
				SET message TO message + "Min Time To Stop,".
				SET message TO message + "Horizontal Speed,".
				SET message TO message + "Horizontal Acceleration,".
				SET message TO message + "Vertical Speed,".
				SET message TO message + "Vertical Acceleration,".
				SET message TO message + "High Direction Speed,".
				SET message TO message + "Height Above Ground,".
				SET message TO message + "Ground Slope,".
				SET message TO message + "Ground Slope Heading,".
				SET message TO message + "Throttle Velocity Setpoint,".
				SET message TO message + "Throttle PID Output,".
				SET message TO message + "Heading PID Output,".
				SET message TO message + "Heading Steering Adjust,".
				SET message TO message + "Pitch,".
				SET message TO message + "Mode,".
				LOG message TO logFileName.
			}
			SET message TO missionTime.
			SET message TO message + "," + shipInfo["Maximum"]["Accel"].
			SET message TO message + "," + effectiveAccel.
			SET message TO message + "," + gravityAccel.
			SET message TO message + "," + minTimeToStop.
			SET message TO message + "," + GROUNDSPEED.
			SET message TO message + "," + hAccel.
			SET message TO message + "," + VERTICALSPEED.
			SET message TO message + "," + vAccel.
			SET message TO message + "," + highDirectionSpeed.
			SET message TO message + "," + aboveGround.
			SET message TO message + "," + downSlopeInfo["slope"].
			SET message TO message + "," + downSlopeInfo["heading"].
			SET message TO message + "," + T_PID:SETPOINT.
			SET message TO message + "," + T_PID:OUTPUT.
			SET message TO message + "," + H_PID:OUTPUT.
			SET message TO message + "," + headingSteeringAdjust.
			SET message TO message + "," + pitch_for(SHIP).
			SET message TO message + "," + mode.
			LOG message TO logFileName.
		}

		SET oldHSpeed TO GROUNDSPEED.
		SET oldVSpeed TO VERTICALSPEED.
		SET oldTime TO TIME:SECONDS.
	}

	// Maintain height above ground with 5 m/s horizontal speed in the direction of downslope until slope is less than 5.0 degrees
	// Note that the steering is limited to a pitch of 85 degrees at minimum. This limits the remaining horizontal velocity
	PRINT "VSpeed SP = " + ROUND(T_PID:SETPOINT, 2) + "    " AT (40, 1).
	PRINT "Slope = " + ROUND(downSlopeInfo["slope"], 2) + "     " AT (40, 2).
	PRINT "               " AT (40, 3).
	PRINT "Slope < 5.0    " AT (40, 4).
	SET T_PID:SETPOINT TO MIN(15, (500 - aboveGround) / 10).
	SET H_PID:SETPOINT TO V(rangeData["long"]["northOffset"], rangeData["long"]["eastOffset"], 0):MAG / 33.33.
//	IF rangeData["long"]["terrainHeight"] > rangeData["medium"]["terrainHeight"] SET H_PID:SETPOINT TO 20.0.
//	ELSE IF rangeData["medium"]["terrainHeight"] > rangeData["short"]["terrainHeight"] SET H_PID:SETPOINT TO 10.0.
//	ELSE SET H_PID:SETPOINT TO 5.0.

	IF rangeData["long"]["northOffset"] <> 0 AND rangeData["long"]["northOffset"] <> 0 SET desiredHeading TO yaw_for(rangeData["long"]["northOffset"] * northVector + rangeData["long"]["eastOffset"] * east).
	ELSE 																																							 SET desiredHeading TO yaw_for(rangeData["medium"]["northOffset"] * northVector + rangeData["medium"]["eastOffset"] * east).
  SET globalThrottle TO T_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
	SET headingSteeringAdjust TO -2 * ABS(angleDifference(desiredHeading, yaw_for(VELOCITY:SURFACE))).
	IF H_PID:INPUT < 0 SET headingSteeringAdjust TO -headingSteeringAdjust.
	IF headingSteeringAdjust > 30 SET headingSteeringAdjust TO 30.
	IF headingSteeringAdjust < 30 SET headingSteeringAdjust TO -30.
  SET globalSteer TO HEADING (desiredHeading + headingSteeringAdjust, 90 - H_PID:UPDATE(TIME:SECONDS, highDirectionSpeed)).
	PRINT "desiredHeading at " + ROUND(desiredHeading, 2) + " deg from northVector    " AT (0, 12).
	PRINT "Surface Velocity heading at " + ROUND(yaw_for(VELOCITY:SURFACE), 2) + " deg from northVector     " AT (0, 13).
	PRINT "headingSteeringAdjust at " + ROUND(headingSteeringAdjust, 2) + " deg    " AT (0, 14).
	PRINT "globalSteer at " + ROUND(globalSteer:YAW, 2) + " deg from northVector    " AT (0, 15).
	PRINT "Horizontal Speed SP " + distanceToString(H_PID:SETPOINT, 2) + "/s     " AT (0, 16).
	PRINT "Item 1 " + ROUND(angleDifference(desiredHeading, yaw_for(VELOCITY:SURFACE))) + " degrees difference    " AT (0, 17).

	SET headingOffsetVD:VEC TO 10*HEADING(desiredHeading + headingSteeringAdjust, 0):VECTOR.
	SET headingCourseVD:VEC TO 10*HEADING(desiredHeading                        , 0):VECTOR.

	WAIT 0.
}

SET globalThrottle TO 0.
SET globalSteer TO SHIP:UP.
setLockedSteering(FALSE).
setLockedThrottle(FALSE).

IF (VELOCITY:SURFACE:MAG < 1) SET loopMessage TO "Landed on " + SHIP:BODY:NAME.
ELSE SET loopMessage TO "Something went wrong - still moving relative to surface of " + SHIP:BODY:NAME.
