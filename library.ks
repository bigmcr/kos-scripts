@LAZYGLOBAL OFF.
// First off, define several parameters that are used by multiple files.
// All of these are default parameters; they can be overriden by any vehicle-specific script file
GLOBAL physicsWarpPerm TO 2.					// If non-zero, allow physics warping up to the specified level when reasonable
GLOBAL maxAOA TO 5.								// Maximum angle of attack. Used as the limits of the pitch PID while in atmosphere
GLOBAL debug IS TRUE.							// If TRUE, multiple functions will display or log extra info
GLOBAL missionTimeOffset TO 0.					// Offset for MISSIONTIME to account for time spent on the launchpad
GLOBAL g_0 IS CONSTANT:G0.               			// Gravitational acceleration constant (m/s²)
GLOBAL augerList IS SHIP:PARTSTITLEDPATTERN("Auger").
GLOBAL smelterList IS SHIP:PARTSTITLEDPATTERN("Smelter").
GLOBAL facingVector   IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN SHIP:FACING:VECTOR * 10.}           , RED,   ".                 Facing", 1, TRUE).
GLOBAL guidanceVector IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN STEERINGMANAGER:TARGET:VECTOR * 10.}, GREEN, "Guidance                ", 1, TRUE).
GLOBAL facingVectorFace   IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION + SHIP:FACING:VECTOR * 10.}, {RETURN SHIP:FACING:TOPVECTOR * 5.}           , RED,   "", 1, TRUE).
GLOBAL guidanceVectorFace IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION + STEERINGMANAGER:TARGET:VECTOR * 10.}, {RETURN STEERINGMANAGER:TARGET:TOPVECTOR * 5.}, GREEN, "", 1, TRUE).
LOCAL shipInfoCurrentLoggingStarted IS FALSE.
LOCAL logPhysicsTimeStamp IS 0.
GLOBAL shipBounds IS SHIP:BOUNDS.
GLOBAL resourceList IS LEXICON().
CLEARVECDRAWS().

GLOBAL densityLookUp IS LEXICON().
FOR eachResource IN SHIP:RESOURCES {densityLookUp:ADD(eachResource:NAME, eachResource:DENSITY * 1000).}

GLOBAL shipInfo IS Lexicon().
GLOBAL rotationLastAccel IS 0.				// Last measured angular acceleration (rad/s²), the lower of pitch and yaw. 0 if never measured.
GLOBAL rotationLastMass IS 1.				// SHIP:MASS (t) when rotationLastAccel was measured. Used to rescale it after staging.
GLOBAL rotationLastRCS IS FALSE.			// Whether RCS was on when rotationLastAccel was measured (the RCS thrusters add to the torque). Recorded only; the measurement does not change it.
GLOBAL rotationFile IS "1:rotation.json".	// On the local drive, so a reboot can skip the measurement. See saveRotationData and loadRotationData.

LOCAL partListTree IS LEXICON().
LOCAL decouplerList IS LIST().

updateShipInfo().

// Density of a resource in kg per unit. Refreshes densityLookUp from SHIP:RESOURCES on a miss, so
// resources that arrive after the library loaded (docking, new parts) are found. A resource that is
// not on the ship at all still raises a missing-key error.
FUNCTION resourceDensity {
	PARAMETER resourceName.
	IF NOT densityLookUp:HASKEY(resourceName) {
		FOR eachResource IN SHIP:RESOURCES {
			IF NOT densityLookUp:HASKEY(eachResource:NAME) densityLookUp:ADD(eachResource:NAME, eachResource:DENSITY * 1000).
		}
	}
	RETURN densityLookUp[resourceName].
}

FUNCTION updateFacingVectors {
	SET facingVector:SHOW TO NOT MAPVIEW.
	SET guidanceVector:SHOW TO NOT MAPVIEW AND STEERINGMANAGER:ENABLED.
	SET facingVectorFace:SHOW TO NOT MAPVIEW.
	SET guidanceVectorFace:SHOW TO NOT MAPVIEW AND STEERINGMANAGER:ENABLED.
}

FUNCTION isDecoupler {
	PARAMETER examinePart.
	LOCAL returnValue IS examinePart:MODULES:CONTAINS("ModuleDecouple") OR examinePart:MODULES:CONTAINS("ModuleAnchoredDecoupler").
	FOR eachResource IN examinePart:RESOURCES {
		IF (eachResource:NAME = "Ablator") SET returnValue TO FALSE.
	}
	RETURN returnValue.
}

FUNCTION mergeLists {
	PARAMETER list1.
	PARAMETER list2.
	LOCAL returnList IS LIST().

	FOR eachIndex IN RANGE(0, list1:LENGTH) returnList:ADD(list1[eachIndex]).
	FOR eachIndex IN RANGE(0, list2:LENGTH) returnList:ADD(list2[eachIndex]).

	RETURN returnList.
}

FUNCTION swap {
	PARAMETER list1.
	PARAMETER index1.
	PARAMETER index2.
	LOCAL temporary IS list1[index1].
	SET list1[index1] TO list1[index2].
	SET list1[index2] TO temporary.
	RETURN list1.
}

FUNCTION insertionSort {
	PARAMETER sortMeParam.
	PARAMETER GRTFunction.
	LOCAL sortMe IS sortMeParam:COPY().
	LOCAL i IS 1.
	LOCAL j IS 0.
	UNTIL NOT (i < sortMe:LENGTH) {
		SET j TO i.
		UNTIL NOT ((j > 0) AND (GRTFunction(sortMe[j - 1], sortMe[j]))) {
			swap(sortMe, j, j - 1).
			SET j TO j - 1.
		}
		SET i TO i + 1.
	}
	RETURN sortMe.
}

FUNCTION listArrayGRT {
	PARAMETER list1.
	PARAMETER list2.
	RETURN (list1[0]:STAGE > list2[0]:STAGE).
}

FUNCTION listParts {
	LOCAL decouplerPartList IS LIST().
	SET decouplerList TO LIST().

	SET partListTree TO LEXICON().
	decouplerPartList:ADD(SHIP:PARTS[0]).
	FOR eachPart IN SHIP:PARTS {
		IF isDecoupler(eachPart) {
			decouplerPartList:ADD(eachPart).
		}
	}

	FOR eachIndex IN RANGE(0, decouplerPartList:LENGTH) {
		decouplerList:ADD(LIST()).
		IF eachIndex <> 0 decouplerList[eachIndex]:ADD(decouplerPartList[eachIndex]).
		recursivePartSort(decouplerPartList[eachIndex], eachIndex).
	}

	LOCAL hasDuplicates IS TRUE.
	UNTIL hasDuplicates = FALSE {
		FOR eachIndex IN RANGE(0, decouplerList:LENGTH) {
			FOR eachSubIndex IN RANGE(0, decouplerList:LENGTH) {
				IF eachSubIndex > eachIndex {
					IF (decouplerList[eachIndex][0]:STAGE = decouplerList[eachSubIndex][0]:STAGE) {
						decouplerList:INSERT(eachIndex + 1, mergeLists(decouplerList[eachIndex], decouplerList[eachSubIndex])).
						decouplerList:REMOVE(eachIndex).
						decouplerList:REMOVE(eachSubIndex).
						BREAK.
					}
				}
			}
		}

		SET hasDuplicates TO FALSE.
		FOR eachIndex IN RANGE(0, decouplerList:LENGTH) {
			FOR eachSubIndex IN RANGE(0, decouplerList:LENGTH) {
				IF eachSubIndex > eachIndex {
					LOCAL eachIndexStage IS (decouplerList[eachIndex])[0]:STAGE.
					LOCAL eachSubIndexStage IS (decouplerList[eachSubIndex])[0]:STAGE.
					IF eachIndexStage = eachSubIndexStage SET hasDuplicates TO TRUE.
				}
			}
		}
	}

	LOCAL smallPartList IS LIST().
	LOCAL addedStages IS 0.

	FOR eachIndex IN RANGE(0, decouplerList:LENGTH) {
		smallPartList:ADD(decouplerList[eachIndex]).
	}

	SET smallPartList TO insertionSort(smallPartList, listArrayGRT@).

	FOR eachIndex IN RANGE(0, smallPartList:LENGTH) {
		partListTree:ADD("Stage " + addedStages, smallPartList[eachIndex]).
		SET addedStages TO addedStages + 1.
	}
}

FUNCTION recursivePartSort {
	PARAMETER examinePart.
	PARAMETER decouplerListIndex.
	PARAMETER currentStage IS 0.
	IF currentStage > 50 {
		RETURN.
	}

	IF NOT isDecoupler(examinePart) decouplerList[decouplerListIndex]:ADD(examinePart).

	FOR eachKid IN examinePart:CHILDREN {
		IF NOT isDecoupler(eachKid) recursivePartSort(eachKid, decouplerListIndex, currentStage + 1).
	}
	RETURN.
}

// Sets one of the ship's control axes ("Pitch", "Yaw" or "Roll") to a value from -1 to 1.
FUNCTION setControlAxis {
	PARAMETER axisName.
	PARAMETER axisValue.
	IF axisName = "Pitch" SET SHIP:CONTROL:PITCH TO axisValue.
	ELSE IF axisName = "Yaw" SET SHIP:CONTROL:YAW TO axisValue.
	ELSE SET SHIP:CONTROL:ROLL TO axisValue.
}

// Actively measures how quickly the ship can start rotating about each axis, by applying full control input and watching SHIP:ANGULARVEL.
// Only call this when the ship is free to turn: it unlocks steering, turns SAS off during the test (and restores it), and leaves the
// ship rotating about as it was. Returns a lexicon of "Pitch", "Yaw" and "Roll" angular accelerations in rad/s²
// (0 where the ship did not respond).
FUNCTION measureRotationAccel {
	PARAMETER maxMeasureTime IS 2.					// longest time to apply full input (s)
	PARAMETER maxRateChange IS 0.1.					// stop applying input once the rate has changed this much (rad/s)
	LOCAL accelResult IS LEXICON("Pitch", 0, "Yaw", 0, "Roll", 0).
	LOCAL oldSAS IS SAS.
	SET SAS TO FALSE.
	UNLOCK STEERING.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	WAIT 0.5.

	FOR axisName IN accelResult:KEYS {
		// the axes are fixed in the ship-raw frame, the same frame that SHIP:ANGULARVEL is in
		LOCAL axisVector IS SHIP:FACING:STARVECTOR.
		IF axisName = "Yaw" SET axisVector TO SHIP:FACING:TOPVECTOR.
		IF axisName = "Roll" SET axisVector TO SHIP:FACING:FOREVECTOR.

		LOCAL startRate IS VDOT(SHIP:ANGULARVEL, axisVector).
		LOCAL startMoment IS TIME:SECONDS.
		setControlAxis(axisName, 1).
		UNTIL (TIME:SECONDS - startMoment >= maxMeasureTime) OR (ABS(VDOT(SHIP:ANGULARVEL, axisVector) - startRate) >= maxRateChange) WAIT 0.
		LOCAL elapsedTime IS TIME:SECONDS - startMoment.
		LOCAL rateChange IS ABS(VDOT(SHIP:ANGULARVEL, axisVector) - startRate).
		IF elapsedTime > 0 SET accelResult[axisName] TO rateChange / elapsedTime.

		// Undo the rotation just added: push the other way until the rate is back to where it started.
		setControlAxis(axisName, -1).
		LOCAL stopStart IS TIME:SECONDS.
		UNTIL (ABS(VDOT(SHIP:ANGULARVEL, axisVector) - startRate) < 0.005) OR (TIME:SECONDS - stopStart > 2 * elapsedTime + 1) WAIT 0.
		SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
		WAIT 0.5.
	}
	SET SAS TO oldSAS.
	RETURN accelResult.
}

// Finds the Max Stopping Time that lets a ship with the given angular acceleration (rad/s²) turn through turnAngle (degrees) in no more
// than targetTime (s). The steering manager limits the rotation rate to accel * stoppingTime, so the turn takes turnAngle/(accel*T) + T.
// The smallest (gentlest) T that meets targetTime is returned; if targetTime cannot be met, the T that turns fastest is returned.
// The result is limited to between minTime and maxTime. If accel is not positive, maxTime is returned.
FUNCTION calculateStoppingTime {
	PARAMETER accel.
	PARAMETER turnAngle IS 180.
	PARAMETER targetTime IS 60.
	PARAMETER minTime IS 1.
	PARAMETER maxTime IS 30.
	IF accel <= 0 RETURN maxTime.
	LOCAL turnRadians IS turnAngle * CONSTANT:DEGTORAD.
	LOCAL fastestTime IS 2 * SQRT(turnRadians / accel).
	LOCAL bestStop IS SQRT(turnRadians / accel).
	IF targetTime > fastestTime SET bestStop TO (targetTime - SQRT(targetTime^2 - 4 * turnRadians / accel)) / 2.
	RETURN MIN(maxTime, MAX(minTime, bestStop)).
}

// How long a turn through turnAngle (degrees) takes, in seconds, for a ship that can accelerate its rotation at accel (rad/s^2) while the
// steering manager limits the rotation rate to accel * stoppingTime. Returns -1 if accel is not positive (unknown).
FUNCTION turnTimeFor {
	PARAMETER accel.
	PARAMETER stoppingTime.
	PARAMETER turnAngle IS 180.
	IF accel <= 0 RETURN -1.
	LOCAL turnRadians IS turnAngle * CONSTANT:DEGTORAD.
	IF turnRadians >= accel * stoppingTime^2 RETURN turnRadians / (accel * stoppingTime) + stoppingTime.	// speeds up, cruises at the limit, slows down
	RETURN 2 * SQRT(turnRadians / accel).																// never reaches the limit
}

// Saves the last turn-rate measurement to the local drive (about 1.2 kB as JSON), along with the ship's name and part count so that
// loadRotationData can tell when it no longer describes this ship. Skipped if the drive is too full.
FUNCTION saveRotationData {
	IF rotationLastAccel <= 0 RETURN.
	IF EXISTS(rotationFile) DELETEPATH(rotationFile).
	IF CORE:VOLUME:FREESPACE < 1500 RETURN.
	WRITEJSON(LEXICON("Accel", rotationLastAccel, "Mass", rotationLastMass, "RCS", rotationLastRCS, "Name", SHIP:NAME, "Parts", SHIP:PARTS:LENGTH), rotationFile).
}

// Loads the measurement that saveRotationData saved, so that a reboot doesn't need to move the ship to measure it again.
// The file is ignored (and TRUE is not returned) if it is missing or unreadable, or if the ship's name or number of parts has changed
// (docking, a lost or added part, staging, or a different vessel on this core). Returns TRUE if rotationLastAccel and
// rotationLastMass were loaded.
FUNCTION loadRotationData {
	IF NOT EXISTS(rotationFile) RETURN FALSE.
	LOCAL savedData IS READJSON(rotationFile).
	IF NOT savedData:ISTYPE("Lexicon") RETURN FALSE.
	FOR eachKey IN LIST("Accel", "Mass", "Name", "Parts") IF NOT savedData:HASKEY(eachKey) RETURN FALSE.
	IF savedData["Name"] <> SHIP:NAME OR savedData["Parts"] <> SHIP:PARTS:LENGTH RETURN FALSE.
	IF savedData["Accel"] <= 0 OR savedData["Mass"] <= 0 RETURN FALSE.
	SET rotationLastAccel TO savedData["Accel"].
	SET rotationLastMass TO savedData["Mass"].
	SET rotationLastRCS TO savedData:HASKEY("RCS") AND savedData["RCS"].		// files saved before this was recorded do not have it
	RETURN TRUE.
}

// The Max Stopping Time to use when the ship has not been measured, or is on the ground: 1 s for stock, 15 s for RealFuels.
FUNCTION defaultStoppingTime {
	IF isStock() RETURN 1.0.
	RETURN 15.0.
}

// Updates STEERINGMANAGER:MAXSTOPPINGTIME and shipInfo["Rotation"] for the ship as it is now.
//		shipInfo["Rotation"] is a lexicon of "Accel" (rad/s^2, the slower of pitch and yaw, 0 if unknown), "StoppingTime" (s),
//		"MaxRate" (rad/s, the rotation rate the steering manager will allow), "TurnTime" (s, for a 180 degree turn, -1 if unknown) and
//		"Measured" (boolean, whether this call measured the ship, instead of rescaling the last measurement for the ship's present mass) and
//		"RCS" (boolean, whether RCS was on when the turn rate was last measured; false if it has not been)
// If the ship is LANDED (or on the pad, where it can't turn freely), the stopping time is the default from defaultStoppingTime (1 s stock, 15 s RealFuels).
// measure - if TRUE and it is safe to (engines off), actively measure the ship; the controls are moved for several seconds.
//		updateShipInfo calls this with FALSE, because it runs during burns. With no measurement to go on, the stopping time is left alone.
FUNCTION updateStoppingTime {
	PARAMETER measure IS FALSE.
	PARAMETER announce IS FALSE.					// if TRUE, print to the terminal that the ship is being measured (don't use while the terminal display is up)
	LOCAL turnAccel IS 0.
	LOCAL didMeasure IS FALSE.
	LOCAL onGround IS SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH".
	IF measure AND THROTTLE = 0 AND NOT onGround {
		LOCAL rcsWasOn IS RCS.								// recorded with the measurement; RCS itself is left as it is
		IF announce PRINT "Measuring how fast the ship can rotate (about 10 s). The ship will move slightly.".
		LOCAL measured IS measureRotationAccel().
		SET turnAccel TO MIN(measured["Pitch"], measured["Yaw"]).
		IF announce PRINT "Rotation measured: pitch " + ROUND(measured["Pitch"] * CONSTANT:RADTODEG, 3) + ", yaw " + ROUND(measured["Yaw"] * CONSTANT:RADTODEG, 3) + ", roll " + ROUND(measured["Roll"] * CONSTANT:RADTODEG, 3) + " deg/s^2".
		IF turnAccel > 0 {
			SET rotationLastAccel TO turnAccel.
			SET rotationLastMass TO SHIP:MASS.
			SET rotationLastRCS TO rcsWasOn.
			SET didMeasure TO TRUE.
			saveRotationData().
		}
	}
	IF NOT didMeasure AND rotationLastAccel > 0 {
		// the same torque acting on a moment of inertia that scales with mass (kOS has no suffix for the moment of inertia, so this is an estimate)
		SET turnAccel TO rotationLastAccel * rotationLastMass / SHIP:MASS.
	}
	IF onGround SET STEERINGMANAGER:MAXSTOPPINGTIME TO defaultStoppingTime().
	ELSE IF turnAccel > 0 SET STEERINGMANAGER:MAXSTOPPINGTIME TO calculateStoppingTime(turnAccel).
	LOCAL stopTime IS STEERINGMANAGER:MAXSTOPPINGTIME.
	SET shipInfo["Rotation"] TO LEXICON("Accel", turnAccel, "StoppingTime", stopTime, "MaxRate", turnAccel * stopTime,
		"TurnTime", turnTimeFor(turnAccel, stopTime), "Measured", didMeasure, "RCS", rotationLastRCS).
}

// create and format the Ship Information lexicon.
// For the entire ship, record the following information:
//		NumberOfStages - scalar - number of stages in the current ship
//		CurrentStage - lexicon - the current stage, following the below format
//		Rotation - lexicon - how fast the ship can turn and the Max Stopping Time derived from it, see updateStoppingTime
// For each stage, record the following information:
//		Parts - List - containing PARTs in this stage
//		Engines - List - ENGINEs in this stage, or in the closest stage if this only has resources
//		EngineData - List - for each of the Engines, a lexicon of "Engine" (the ENGINE), "Ignitions" (scalar, the number of ignitions
//				remaining, not counting the one that lit the engine if it is running, so it is 0 for a single use engine that is running,
//				and -1 if it is unlimited), "Throttleable" (boolean, NOT THROTTLELOCK), "CanRestart" (boolean, the engine allows a
//				restart and has an ignition left), "Running" (boolean, the engine is ignited), "ThrustLimit" (scalar, the thrust limiter
//				setting, in percent from 0 to 100) and "MinThrottle" (scalar, the lowest throttle the engine can run at, as a fraction from 0 to 1)
//		MinIgnitions - scalar - the lowest of the engines' ignitions remaining, or -1 if all of them are unlimited
//		LimitedIgnitions - boolean - whether any of the Engines has a limited number of ignitions
//		Throttleable - boolean - whether all of the Engines can be throttled (FALSE if there are none)
//		CanRestart - boolean - whether all of the Engines can be restarted (FALSE if there are none)
//		LowestThrustLimit - scalar - the lowest thrust limiter setting of the Engines, in percent (100 if there are none)
//		HighestMinThrottle - scalar - the highest minimum throttle of the Engines, as a fraction (0 if there are none)
//		EngineData, MinIgnitions, LimitedIgnitions, Throttleable, CanRestart, LowestThrustLimit and HighestMinThrottle are refreshed by
//		updateShipInfoCurrent for the current stage, because ignitions get used up and the thrust limit can be changed.
//		RCS - List - RCSs in this stage, or in the closest stage if this only has resources
//		Sensors - List - SENSORs in this stage
//		Isp - scalar - calculated for all engines in this stage
//		Thrust - scalar - Total thrust of all engines in this stage, in Newtons
//		mDot - scalar - Total fuel flow of all engines in this stage, in kg/s
//		Resources - Lexicon - the masses of resources in this stage
//		Fuels - List - list of names of fuels used by engines in this stage
//		fuelsRCS - List - list of names of fuels used by RCS engines in this stage
//		fuelMass - scalar - the mass of all resources in the list of fuels that are in the appropriate ratio, in kg
//		fuelMassUnused - scalar - the mass of all resources in the list of fuels that are not in the appropriate ratio, in kg
//		fuelRCSMass - scalar - the mass of all resources in the list of fuels for RCS that are in the appropriate ratio, in kg
//		fuelRCSMassUnused - scalar - the mass of all resources in the list of fuels for RCS that are not in the appropriate ratio, in kg
//		ResourceMass - scalar - sum of the masses in the resource list, in kg
//		DryMass - scalar - sum of the dry masses of the parts in the part list, in kg
//		PreviousMass - scalar - mass of all previous stages, in kg (IE, for stage 5, mass of all stages from stage 0 to stage 4)
//		CurrentMass - scalar - mass of all previous and current stages, in kg
//		DeltaV - scalar - calculated delta v for the whole ship given the Isp, mass and resources for this stage
//		DeltaVPrev - scalar - calculated delta v for the whole ship in stages prior to this one.
// Calls a different function to calculate several items about the current stage
FUNCTION updateShipInfo {
	SET shipInfo TO LEXICON().
	LOCAL PreviousMass IS 0.
	LOCAL highestStageEngine IS 0.
	LOCAL deltaVList IS "".
	LOCAL engineListOld IS LIST().
	LOCAL RCSListOld IS LIST().
	LOCAL engineStat IS LIST().
	LOCAL ignitedEngines IS LIST().

	listParts().
	shipInfo:ADD("NumberOfStages", 0).
	shipInfo:ADD("CurrentStage", LEXICON()).

	// for each of the stages, determine the parts, engines and sensors
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		LOCAL stageInfo IS LEXICON().
		stageInfo:ADD("Number", stageNumber).
		stageInfo:ADD("Parts",partListTree["Stage " + stageNumber]).

		// Add a list of all of the engines in this stage.
		stageInfo:ADD("Engines",LIST()).
		FOR eachPart IN stageInfo["Parts"] { IF eachPart:TYPENAME = "Engine" stageInfo["Engines"]:ADD(eachPart).}
		// If there are no engines in this stage, use the engines from the previous stage
		IF (stageInfo["Engines"]:LENGTH = 0) SET stageInfo["Engines"] TO engineListOld.
		// If there are engines in this stage, replace the list of engines from the previous stage
		ELSE {SET engineListOld TO stageInfo["Engines"].}

		stageInfo:ADD("RCS",LIST()).
		FOR eachPart IN stageInfo["Parts"] { IF eachPart:TYPENAME = "RCS" stageInfo["RCS"]:ADD(eachPart).}
		// If there are no engines in this stage, use the engines from the previous stage
		IF (stageInfo["RCS"]:LENGTH = 0) SET stageInfo["RCS"] TO RCSListOld.
		// If there are engines in this stage, replace the list of engines from the previous stage
		ELSE {SET RCSListOld TO stageInfo["RCS"].}

		// Add the Fuels list to the lexicon, but it will be filled out once the engine list has been finalized
		stageInfo:ADD("Fuels", LIST()).

		// Add the FuelsRCS list to the lexicon, but it will be filled out once the engine list has been finalized
		stageInfo:ADD("FuelsRCS", LIST()).

		stageInfo:ADD("Sensors",LIST()).
		FOR eachPart IN stageInfo["Parts"] { IF eachPart:TYPENAME = "sensor" stageInfo["Sensors"]:ADD(eachPart).}

		// Add the engine-related values to the lexicon, but they will be added once the engine list has been finalized
		stageInfo:ADD("Isp", 0).
		stageInfo:ADD("IspRCS", 0).
		stageInfo:ADD("Thrust", 0).
		stageInfo:ADD("mDot", 0).

		// Add the engine capabilities, but they will be filled out once the engine list has been finalized
		stageInfo:ADD("EngineData", LIST()).
		stageInfo:ADD("MinIgnitions", -1).
		stageInfo:ADD("LimitedIgnitions", FALSE).
		stageInfo:ADD("Throttleable", FALSE).
		stageInfo:ADD("CanRestart", FALSE).
		stageInfo:ADD("LowestThrustLimit", 100).
		stageInfo:ADD("HighestMinThrottle", 0).

		// Add the resources from this stage
		stageInfo:ADD("Resources", resourcesInParts(stageInfo["Parts"])).

		// add the various resource-related values to the lexicon, but they will be filled out by updateShipInfoCurrent
		stageInfo:ADD("fuelMass", 0).
		stageInfo:ADD("fuelMassUnused", 0).
		stageInfo:ADD("fuelRCSMass", 0).
		stageInfo:ADD("fuelRCSMassUnused", 0).
		stageInfo:ADD("resourceMass", 0).

		LOCAL dryMasses IS 0.
		FOR eachPart IN stageInfo["Parts"] {SET dryMasses TO dryMasses + eachPart:DRYMASS * 1000.}
		stageInfo:ADD("DryMass", dryMasses).

		stageInfo:ADD("PreviousMass",previousMass).
		FOR eachPart IN stageInfo["Parts"] {SET previousMass TO previousMass + eachPart:MASS * 1000.}

		stageInfo:ADD("CurrentMass",previousMass).

		// Will be updated by updateShipInfoCurrent
		stageInfo:ADD("DeltaV",0).
		stageInfo:ADD("DeltaVRCS",0).
		stageInfo:ADD("DeltaVPrev", 0).

		shipInfo:ADD(("Stage " + stageNumber), stageInfo).
		SET shipInfo["NumberOfStages"] TO shipInfo["NumberOfStages"] + 1.
	}

	LIST ENGINES IN engineListOld.
	FOR eachEngine IN engineListOld {IF eachEngine:STAGE > highestStageEngine SET highestStageEngine TO eachEngine:STAGE.}
	FOR eachEngine IN engineListOld {IF (eachEngine:IGNITION OR eachEngine:STAGE = highestStageEngine) ignitedEngines:ADD(eachEngine).}
	// clear out the highest stage's Engines list, then add all of the active engines and engines with the highest stage number
	SET shipInfo["Stage " + (shipInfo["NumberOfStages"] - 1)]["Engines"] TO ignitedEngines.

	SET shipInfo["CurrentStage"] TO shipInfo["Stage " + (shipInfo["NumberOfStages"] - 1)].

	// for each of the stages, determine the parts, engines and sensors
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		SET engineStat TO engineStats(shipInfo["Stage " + stageNumber]["Engines"]).
		SET shipInfo["Stage " + stageNumber]["Isp"] TO engineStat["Isp"].
		SET shipInfo["Stage " + stageNumber]["IspRCS"] TO engineStatsRCS(shipInfo["Stage " + stageNumber]["RCS"])["Isp"].
		SET shipInfo["Stage " + stageNumber]["Thrust"] TO engineStat["thrustMax"].
		SET shipInfo["Stage " + stageNumber]["mDot"] TO engineStat["mDotMax"].

		SET shipInfo["Stage " + stageNumber]["Fuels"] TO getCurrentFuels(shipInfo["Stage " + stageNumber]["Engines"], stageNumber).
		SET shipInfo["Stage " + stageNumber]["FuelsRCS"] TO getCurrentFuels(shipInfo["Stage " + stageNumber]["RCS"], stageNumber).

		LOCAL capabilities IS engineCapabilities(shipInfo["Stage " + stageNumber]["Engines"]).
		FOR eachKey IN capabilities:KEYS {
			SET shipInfo["Stage " + stageNumber][eachKey] TO capabilities[eachKey].
		}
	}
	updateShipInfoCurrent(FALSE).

	LOCAL deltaVPrev IS 0.
	FOR stageNumber IN RANGE(partListTree:LENGTH - 1, -1) {
		IF stageNumber <> partListTree:LENGTH - 1 {
			SET deltaVPrev TO deltaVPrev + shipInfo["Stage " + (stageNumber + 1)]["DeltaV"].
		}
		SET shipInfo["Stage " + stageNumber]["DeltaVPrev"] TO deltaVPrev.
	}
	SET shipInfo["CurrentStage"] TO shipInfo["Stage " + (shipInfo["NumberOfStages"] - 1)].
	updateStoppingTime(FALSE).
	SET augerList TO SHIP:PARTSTITLEDPATTERN("Auger").
	SET smelterList TO SHIP:PARTSTITLEDPATTERN("Smelter").

	resourceList:CLEAR.
	FOR eachResource IN SHIP:RESOURCES {
		resourceList:ADD(eachResource:NAME, LEXICON(    "Quantity", eachResource:AMOUNT,
												        "Mass", eachResource:AMOUNT * resourceDensity(eachResource:NAME),
													    "Density", resourceDensity(eachResource:NAME),
														"Quantity Use", 0,
														"Mass Use", 0)).
	}
	SET shipBounds TO SHIP:BOUNDS.
}

// log Data Recursive
// Recursively log data passed to the function.
// It will automatically expand all lists and lexicons, but will otherwise use
// the TOSTRING() function to log data.
FUNCTION logData {
	PARAMETER dataToLog.
	PARAMETER fileName.
	PARAMETER increment IS 0.
	PARAMETER label IS "".
	IF increment > 50 RETURN.

	LOCAL padValue IS "":PADLEFT(increment):REPLACE(" ",",").
	IF label <> "" SET padValue TO padValue + label + ",".

	IF dataToLog:TYPENAME = "List" {
		LOG padValue + "List," + dataToLog:LENGTH + " items" TO fileName.
		FOR eachIndex IN RANGE(dataToLog:LENGTH) {
			logData(dataToLog[eachIndex], fileName, increment + 1, eachIndex).
		}
	} ELSE IF dataToLog:TYPENAME = "LEXICON" {
		LOG padValue + "Lexicon," + dataToLog:LENGTH + " items" TO fileName.
		FOR eachKey IN dataToLog:KEYS {
			logData(dataToLog[eachKey], fileName, increment + 1, eachKey).
		}
	} ELSE IF dataToLog:ISTYPE("Vector") {
		LOG padValue + dataToLog:TYPENAME + "," + dataToLog:TOSTRING():REPLACE("V(",""):REPLACE(")","") TO fileName.
	} ELSE IF dataToLog:ISTYPE("Engine") {
		LOG padValue + dataToLog:TYPENAME + "," + dataToLog:CONFIG:REPLACE(",","") + ",Max Thrust," + dataToLog:MAXTHRUST + ",Isp," + dataToLog:ISP TO fileName.
	} ELSE IF dataToLog:ISTYPE("RCS") {
		LOG padValue + dataToLog:TYPENAME + "," + dataToLog:TITLE:REPLACE(",","") + ",Max Thrust," + dataToLog:MAXTHRUST + ",Isp," + dataToLog:ISP TO fileName.
	} ELSE IF dataToLog:ISTYPE("Part") {
		LOG padValue + dataToLog:TYPENAME + "," + dataToLog:TITLE:REPLACE(",","") TO fileName.
	} ELSE IF dataToLog:ISTYPE("Orbitable") {
		LOG padValue + dataToLog:TYPENAME + "," + dataToLog:NAME:REPLACE(",","") TO fileName.
	} ELSE {
		LOG padValue + dataToLog:TYPENAME + "," + dataToLog:TOSTRING() TO fileName.
	}
}

// Log Ship Info
// Function that logs all information in shipInfo into the specified file.
FUNCTION logShipInfo {
	PARAMETER includeResources IS FALSE.
	PARAMETER fileName TO "0:" + SHIP:NAME + " Info Stage " + STAGE:NUMBER + ".csv".
	LOG "Ship Information for " + SHIP:NAME TO fileName.
	LOG "Rotation" TO fileName.
	LOG ",Angular Acceleration," + ROUND(shipInfo["Rotation"]["Accel"] * CONSTANT:RADTODEG, 4) + ",deg/s^2" TO fileName.
	LOG ",Max Stopping Time," + ROUND(shipInfo["Rotation"]["StoppingTime"], 3) + ",s" TO fileName.
	LOG ",Max Rotation Rate," + ROUND(shipInfo["Rotation"]["MaxRate"] * CONSTANT:RADTODEG, 4) + ",deg/s" TO fileName.
	LOG ",180 Degree Turn Time," + ROUND(shipInfo["Rotation"]["TurnTime"], 2) + ",s (-1 is unknown)" TO fileName.
	LOG ",Measured This Update," + shipInfo["Rotation"]["Measured"] TO fileName.
	LOG ",RCS On When Measured," + shipInfo["Rotation"]["RCS"] TO fileName.
	LOCAL deltaVLogList IS "".
	LOCAL deltaVDisplayList IS "".
	// for each of the stages
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		LOG "Stage " + stageNumber TO fileName.
		LOG ",Parts has " + shipInfo["Stage " + stageNumber]["Parts"]:LENGTH + " Items in it,Part Name,Part Wet Mass,Unit,Stage" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Parts"] {LOG ",," + p:TITLE:REPLACE(",","") + "," + (p:MASS*1000) + ",kg," + p:STAGE TO fileName.}
		LOG ",Engines has " + shipInfo["Stage " + stageNumber]["Engines"]:LENGTH + " Items in it" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Engines"] {LOG ",," + p:CONFIG:REPLACE(",","") TO fileName.}
		LOG ",Engine Capabilities,Engine,Ignitions Remaining (-1 is unlimited),Throttleable,Can Restart,Running,Thrust Limit (%),Minimum Throttle (fraction)" TO fileName.
		FOR eachData IN shipInfo["Stage " + stageNumber]["EngineData"] {
			LOG ",," + eachData["Engine"]:CONFIG:REPLACE(",","") + "," + eachData["Ignitions"] + "," + eachData["Throttleable"] + "," + eachData["CanRestart"] + "," + eachData["Running"] + "," + eachData["ThrustLimit"] + "," + eachData["MinThrottle"] TO fileName.
		}
		LOG ",Minimum Ignitions Remaining," + shipInfo["Stage " + stageNumber]["MinIgnitions"] TO fileName.
		LOG ",Any Engine Has Limited Ignitions," + shipInfo["Stage " + stageNumber]["LimitedIgnitions"] TO fileName.
		LOG ",All Engines Throttleable," + shipInfo["Stage " + stageNumber]["Throttleable"] TO fileName.
		LOG ",All Engines Can Restart," + shipInfo["Stage " + stageNumber]["CanRestart"] TO fileName.
		LOG ",Lowest Thrust Limit," + shipInfo["Stage " + stageNumber]["LowestThrustLimit"] + ",%" TO fileName.
		LOG ",Highest Minimum Throttle," + shipInfo["Stage " + stageNumber]["HighestMinThrottle"] TO fileName.
		LOG ",RCS has " + shipInfo["Stage " + stageNumber]["RCS"]:LENGTH + " Items in it" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["RCS"] {LOG ",," + p:TITLE:REPLACE(",","") TO fileName.}
		LOG ",Sensors has " + shipInfo["Stage " + stageNumber]["Sensors"]:LENGTH + " Items in it" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Sensors"] {LOG ",," + p:TITLE:REPLACE(",","") TO fileName.}
		LOG ",Isp," + ROUND(shipInfo["Stage " + stageNumber]["Isp"], 4) + ",s" TO fileName.
		LOG ",Isp RCS," + ROUND(shipInfo["Stage " + stageNumber]["IspRCS"], 4) + ",s" TO fileName.
		LOG ",Thrust," + ROUND(shipInfo["Stage " + stageNumber]["Thrust"], 4) + ",N" TO fileName.
		LOG ",mDot," + ROUND(shipInfo["Stage " + stageNumber]["mDot"], 4) + ",kg/s" TO fileName.
		LOG ",Resources has " + shipInfo["Stage " + stageNumber]["Resources"]:KEYS:LENGTH + " items in it" TO fileName.
		FOR eachResource IN shipInfo["Stage " + stageNumber]["Resources"]:KEYS {LOG ",," + eachResource + "," + shipInfo["Stage " + stageNumber]["Resources"][eachResource] + ",kg" TO fileName.}
		IF shipInfo["Stage " + stageNumber]["Fuels"]:LENGTH = 0 LOG ",Fuels has 0 items in it" TO fileName.
		ELSE LOG ",Fuels has " + shipInfo["Stage " + stageNumber]["Fuels"]:LENGTH + " items in it,Engine,Fuel,Used Mass kg,Unused Mass kg,Mass Ratio" TO fileName.
		FOR e IN shipInfo["Stage " + stageNumber]["Fuels"]:KEYS {
			FOR f IN shipInfo["Stage " + stageNumber]["Fuels"][e]:KEYS {
				LOG ",," + e + "," + f + "," +
						shipInfo["Stage " + stageNumber]["Fuels"][e][f]["Mass"] + "," +
						shipInfo["Stage " + stageNumber]["Fuels"][e][f]["MassUnused"] + "," +
						shipInfo["Stage " + stageNumber]["Fuels"][e][f]["Ratio"] TO fileName.
			}
		}
		IF shipInfo["Stage " + stageNumber]["FuelsRCS"]:LENGTH = 0 LOG ",RCS Fuels has 0 items in it" TO fileName.
		ELSE LOG ",RCS Fuels has " + shipInfo["Stage " + stageNumber]["FuelsRCS"]:LENGTH + " items in it,Engine,Fuel,Used Mass kg,Unused Mass kg,Mass Ratio" TO fileName.
		FOR e IN shipInfo["Stage " + stageNumber]["FuelsRCS"]:KEYS {
			FOR f IN shipInfo["Stage " + stageNumber]["FuelsRCS"][e]:KEYS {
				LOG ",," + e + "," + f + "," +
						shipInfo["Stage " + stageNumber]["FuelsRCS"][e][f]["Mass"] + "," +
						shipInfo["Stage " + stageNumber]["FuelsRCS"][e][f]["MassUnused"] + "," +
						shipInfo["Stage " + stageNumber]["FuelsRCS"][e][f]["Ratio"] TO fileName.
			}
		}
		LOG ",Fuel Mass," + shipInfo["Stage " + stageNumber]["fuelMass"] + ",kg" TO fileName.
		LOG ",Fuel Mass Unused," + shipInfo["Stage " + stageNumber]["fuelMassUnused"] + ",kg" TO fileName.
		LOG ",RCS Fuel Mass," + shipInfo["Stage " + stageNumber]["fuelRCSMass"] + ",kg" TO fileName.
		LOG ",RCS Fuel Mass Unused," + shipInfo["Stage " + stageNumber]["fuelRCSMassUnused"] + ",kg" TO fileName.
		LOG ",Resource Mass," + shipInfo["Stage " + stageNumber]["resourceMass"] + ",kg" TO fileName.
		LOG ",Dry Mass," + shipInfo["Stage " + stageNumber]["DryMass"] + ",kg" TO fileName.
		LOG ",Previous Mass," + shipInfo["Stage " + stageNumber]["PreviousMass"] + ",kg" TO fileName.
		LOG ",Current Mass," + shipInfo["Stage " + stageNumber]["CurrentMass"] + ",kg" TO fileName.
		LOG ",Stage Delta V," + shipInfo["Stage " + stageNumber]["DeltaV"] + ",m/s" TO fileName.
		LOG ",Stage Delta V RCS," + shipInfo["Stage " + stageNumber]["DeltaVRCS"] + ",m/s" TO fileName.
		LOG ",Stage Delta V Previous," + shipInfo["Stage " + stageNumber]["DeltaVPrev"] + ",m/s" TO fileName.
		IF (shipInfo["Stage " + stageNumber]["Isp"] <> 0) {
			SET deltaVLogList TO deltaVLogList + stageNumber + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["ENGINES"]:LENGTH + ",".
			{
				LOCAL listOfEngines IS LIST().
				LOCAL engineTitle IS "".
				FOR eachEngine IN shipInfo["Stage " + stageNumber]["ENGINES"] {
					SET engineTitle TO eachEngine:CONFIG:REPLACE(",","").
					IF NOT listOfEngines:CONTAINS(engineTitle) listOfEngines:ADD(engineTitle).
				}
				FOR eachNumber IN RANGE(listOfEngines:LENGTH) {
					SET deltaVLogList TO deltaVLogList + listOfEngines[eachNumber].
					IF eachNumber <> listOfEngines:LENGTH - 1 SET deltaVLogList TO deltaVLogList + "/".
				}
				SET deltaVLogList TO deltaVLogList:SUBSTRING(0, deltaVLogList:LENGTH) + ",".
			}
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["FuelMass"] + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["Isp"] + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["DeltaV"] + CHAR(10).
			SET deltaVDisplayList TO deltaVDisplayList + stageNumber:TOSTRING:PADRIGHT(5) +
					shipInfo["Stage " + stageNumber]["ENGINES"]:LENGTH:TOSTRING:PADLEFT(9) +
					ROUND(shipInfo["Stage " + stageNumber]["FuelMass"], 0):TOSTRING:PADLEFT(16) +
					ROUND(shipInfo["Stage " + stageNumber]["Isp"], 0):TOSTRING:PADLEFT(8) +
					ROUND(shipInfo["Stage " + stageNumber]["DeltaV"], 4):TOSTRING:PADLEFT(15) + CHAR(10).
		}
	}
	LOG "" TO fileName.
	LOG "Current Constant Accel," + shipInfo["Current"]["Constant"]["Accel"] + ",m/s^2" TO fileName.
	LOG "Current Constant mDot," + shipInfo["Current"]["Constant"]["mDot"] + ",kg/s" TO fileName.
	LOG "Current Constant Thrust," + shipInfo["Current"]["Constant"]["Thrust"] + ",N" TO fileName.
	LOG "Current Constant TWR," + shipInfo["Current"]["Constant"]["TWR"] + "," TO fileName.
	LOG "Current Variable Accel," + shipInfo["Current"]["Variable"]["Accel"] + ",m/s^2" TO fileName.
	LOG "Current Variable mDot," + shipInfo["Current"]["Variable"]["mDot"] + ",kg/s" TO fileName.
	LOG "Current Variable Thrust," + shipInfo["Current"]["Variable"]["Thrust"] + ",N" TO fileName.
	LOG "Current Variable TWR," + shipInfo["Current"]["Variable"]["TWR"] + "," TO fileName.
	LOG "Current Accel," + shipInfo["Current"]["Accel"] + ",m/s^2" TO fileName.
	LOG "Current BurnTime," + shipInfo["Current"]["BurnTime"] + ",s" TO fileName.
	LOG "Current mDot," + shipInfo["Current"]["mDot"] + ",kg/s" TO fileName.
	LOG "Current Thrust," + shipInfo["Current"]["Thrust"] + ",N" TO fileName.
	LOG "Current TWR," + shipInfo["Current"]["TWR"] + "," TO fileName.
	LOG "Maximum Constant Accel," + shipInfo["Maximum"]["Constant"]["Accel"] + ",m/s^2" TO fileName.
	LOG "Maximum Constant mDot," + shipInfo["Maximum"]["Constant"]["mDot"] + ",kg/s" TO fileName.
	LOG "Maximum Constant Thrust," + shipInfo["Maximum"]["Constant"]["Thrust"] + ",N" TO fileName.
	LOG "Maximum Constant TWR," + shipInfo["Maximum"]["Constant"]["TWR"] + "," TO fileName.
	LOG "Maximum Variable Accel," + shipInfo["Maximum"]["Variable"]["Accel"] + ",m/s^2" TO fileName.
	LOG "Maximum Variable mDot," + shipInfo["Maximum"]["Variable"]["mDot"] + ",kg/s" TO fileName.
	LOG "Maximum Variable Thrust," + shipInfo["Maximum"]["Variable"]["Thrust"] + ",N" TO fileName.
	LOG "Maximum Variable TWR," + shipInfo["Maximum"]["Variable"]["TWR"] + "," TO fileName.
	LOG "Maximum Accel," + shipInfo["Maximum"]["Accel"] + ",m/s^2" TO fileName.
	LOG "Maximum mDot," + shipInfo["Maximum"]["mDot"] + ",kg/s" TO fileName.
	LOG "Maximum Thrust," + shipInfo["Maximum"]["Thrust"] + ",N" TO fileName.
	LOG "Maximum TWR," + shipInfo["Maximum"]["TWR"] + "," TO fileName.
	LOG "Maximum BurnTime," + shipInfo["Maximum"]["BurnTime"] + ",s" TO fileName.
	LOG "" TO fileName.
	LOG "Stage,Engine Count,Engine Type,Fuel Mass (kg),Isp (s),delta V (m/s)" TO fileName.
	LOG deltaVLogList TO fileName.

	IF includeResources {
		LOG "Stage,Part Name,Part UID,Resource Name,Resource Amount (L),Resource Capacity (L),Resource Mass (kg),Resource Density (kg/L)" TO fileName.
		FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
			FOR eachPart IN shipInfo["Stage " + stageNumber]["Parts"] {
				FOR eachResource IN eachPart:RESOURCES {
					LOG stageNumber + "," +
							eachPart:TITLE:REPLACE(",","") + "," +
							eachPart:UID + "," +
							eachResource:NAME + "," +
							eachResource:AMOUNT + "," +
							eachResource:CAPACITY + "," +
							(eachResource:AMOUNT*resourceDensity(eachResource:NAME)) + "," +
							resourceDensity(eachResource:NAME) TO fileName.
				}
			}
		}
	}

	CLEARSCREEN.
	PRINT "Stage  Engines  Fuel Mass (kg)  Isp (s)  Delta V (m/s)".
	PRINT deltaVDisplayList.
}

// Create Resource Log File Headers
// Function that creates the appropriate headers for the log files for resource logging.
FUNCTION createResourcesHeader {
	PARAMETER loggedResources IS LIST("Electricity","Oxygen","Food","Water").
	LOCAL fileName IS "0:" + SHIP:NAME + " Resources.csv".
	LOCAL resourceList IS LIST().
	SET resourceList TO SHIP:RESOURCES.

	LOCAL header IS "Mission Time,Timewarp Rate".
	FOR eachResource IN resourceList {
		IF loggedResources:CONTAINS(eachResource:NAME) SET header TO header + "," + eachResource:NAME + " Volume (L)," + eachResource:NAME + " Mass (kg)".
	}
	LOG header TO fileName.
}

// Given a lexicon of engines, each of which is a lexicon of the fuel and the
// mass ratio, return a lexicon where the masses are in the correct ratio.
// The return lexicon also includes the unused mass of each fuel.
FUNCTION rebalanceFuelMassPerRatio {
	PARAMETER fuelList. // Should be a lexicon.
	PARAMETER loggingAllowed IS FALSE.
	LOCAL errorCode IS "None".
	LOCAL rebalancedLex IS LEXICON().
	FOR engineType IN fuelList:KEYS {
		rebalancedLex:ADD(engineType, LEXICON()).
		FOR examinedFuel IN fuelList[engineType]:KEYS {
			rebalancedLex[engineType]:ADD(examinedFuel, LEXICON("Mass", 0, "MassUnused", 0)).
		}
	}

	FOR engineType IN fuelList:KEYS {
		FOR examinedFuel IN fuelList[engineType]:KEYS {
			IF (fuelList[engineType][examinedFuel]["Ratio"] <> 0) AND (fuelList[engineType][examinedFuel]["Mass"] = 0)
				SET errorCode TO "Zero Fuel Mass".
		}
	}
	IF errorCode = "None" {
		LOCAL requiredToPresentRatio IS 1.
		LOCAL lowestRestraintFuelCombo IS LEXICON().
		lowestRestraintFuelCombo:ADD("Ratio", 1).
		lowestRestraintFuelCombo:ADD("examinedFuel", "").
		lowestRestraintFuelCombo:ADD("constraintFuel", "").
		FOR engineType IN fuelList:KEYS {
			SET lowestRestraintFuelCombo["Ratio"] TO 1.
			SET lowestRestraintFuelCombo["examinedFuel"] TO "".
			SET lowestRestraintFuelCombo["constraintFuel"] TO "".
			IF loggingAllowed {
				LOG "engineType,examinedFuel,ratio,mass" TO "0:fuels.csv".
				FOR examinedFuel IN fuelList[engineType]:KEYS {
					LOG engineType + "," + examinedFuel + "," + fuelList[engineType][examinedFuel]["Ratio"] + "," + fuelList[engineType][examinedFuel]["Mass"] TO "0:fuels.csv".
				}
			}
			FOR examinedFuel IN fuelList[engineType]:KEYS {
				FOR constraintFuel IN fuelList[engineType]:KEYS {
					IF constraintFuel <> examinedFuel {
						IF fuelList[engineType][constraintFuel]["Ratio"] <> 0 AND fuelList[engineType][constraintFuel]["Mass"] <> 0 AND fuelList[engineType][examinedFuel]["Ratio"] <> 0 AND fuelList[engineType][examinedFuel]["Mass"] <> 0 {
							SET requiredToPresentRatio TO (fuelList[engineType][constraintFuel]["Mass"] /
																						fuelList[engineType][constraintFuel]["Ratio"] *
																						fuelList[engineType][examinedFuel]["Ratio"]) /
																						fuelList[engineType][examinedFuel]["Mass"].
							IF requiredToPresentRatio < lowestRestraintFuelCombo["Ratio"] {
								SET lowestRestraintFuelCombo["Ratio"] TO requiredToPresentRatio.
								SET lowestRestraintFuelCombo["examinedFuel"] TO examinedFuel.
								SET lowestRestraintFuelCombo["constraintFuel"] TO constraintFuel.
							}
							IF loggingAllowed {
								LOG "For engine," + engineType + ",there is," + fuelList[engineType][examinedFuel]["Mass"] + ",kg of " + examinedFuel +
								",and according to," + constraintFuel + ",there should be," +
								(fuelList[engineType][constraintFuel]["Mass"] / fuelList[engineType][constraintFuel]["Ratio"] * fuelList[engineType][examinedFuel]["Ratio"]) +
								",kg,which is a ratio of," + requiredToPresentRatio + "," + lowestRestraintFuelCombo["Ratio"] + "," + lowestRestraintFuelCombo["examinedFuel"] + "," + lowestRestraintFuelCombo["constraintFuel"] TO "0:fuels.csv".
							}
						}
					}
				}
			}
			IF lowestRestraintFuelCombo["constraintFuel"] <> "" {
				LOCAL constrainedFuelMass IS fuelList[engineType][lowestRestraintFuelCombo["constraintFuel"]]["Mass"].
				LOCAL constrainedFuelRatio IS fuelList[engineType][lowestRestraintFuelCombo["constraintFuel"]]["Ratio"].
				IF loggingAllowed {
					LOG "Constraining Fuel is," + lowestRestraintFuelCombo["constraintFuel"] + ",Constraining Fuel Mass is," + constrainedFuelMass +
							",kg,Constraining Fuel Ratio is," + constrainedFuelRatio TO "0:fuels.csv".
				}
				FOR examinedFuel IN fuelList[engineType]:KEYS {
					SET rebalancedLex[engineType][examinedFuel]["Mass"] TO constrainedFuelMass * fuelList[engineType][examinedFuel]["Ratio"] / constrainedFuelRatio.
					SET rebalancedLex[engineType][examinedFuel]["MassUnused"] TO fuelList[engineType][examinedFuel]["Mass"] - rebalancedLex[engineType][examinedFuel]["Mass"].
				}
			} ELSE {
				IF loggingAllowed LOG "Constraining Fuel is,None" TO "0:fuels.csv".
				FOR examinedFuel IN fuelList[engineType]:KEYS {
					SET rebalancedLex[engineType][examinedFuel]["Mass"] TO fuelList[engineType][examinedFuel]["Mass"].
					SET rebalancedLex[engineType][examinedFuel]["MassUnused"] TO 0.
				}
			}
		}
	}
	IF errorCode <> "None" {
		FOR engineType IN fuelList:KEYS {
			FOR examinedFuel IN fuelList[engineType]:KEYS {
				SET rebalancedLex[engineType][examinedFuel]["Mass"] TO fuelList[engineType][examinedFuel]["Mass"].
				SET rebalancedLex[engineType][examinedFuel]["MassUnused"] TO 0.
			}
		}
	}
	RETURN rebalancedLex.
}

// Update Ship Information Resources
// Function designed to update the current values of the "Resources" lexicon within shipInfo.
// Will also update fuelMass, fuelMassUnused, fuelRCSMass, fuelRCSMassUnused, resourceMass, previousMass, currentMass and DeltaV.
FUNCTION updateShipInfoResources {
	PARAMETER createlogFileName IS FALSE.
	PARAMETER loggedResources IS LIST("Electricity","Oxygen","Food","Water").
	LOCAL previousMass IS 0.
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		LOCAL stageInfo IS shipInfo["Stage " + stageNumber].
		stageInfo:REMOVE("Resources").
		stageInfo:REMOVE("fuelMass").
		stageInfo:REMOVE("fuelMassUnused").
		stageInfo:REMOVE("fuelRCSMass").
		stageInfo:REMOVE("fuelRCSMassUnused").
		stageInfo:REMOVE("ResourceMass").
		stageInfo:REMOVE("PreviousMass").
		stageInfo:REMOVE("CurrentMass").
		stageInfo:REMOVE("DeltaV").
		stageInfo:REMOVE("DeltaVRCS").
		stageInfo:ADD("Resources", resourcesInParts(stageInfo["Parts"])).

		IF stageInfo["Resources"]:LENGTH = 0 {stageInfo["Resources"]:ADD("Placeholder",0).}

		LOCAL resourceMass IS 0.
		FOR keys IN stageInfo["Resources"]:KEYS {SET resourceMass TO resourceMass + stageInfo["Resources"][keys].}
		stageInfo:ADD("ResourceMass", resourceMass).

		FOR eachEngineType IN stageInfo["Fuels"]:KEYS {
			FOR eachFuel IN stageInfo["Fuels"][eachEngineType]:KEYS {
				SET stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] TO 0.
				// If the called out fuel is in this stage, you are good to go
				IF (stageInfo["Resources"]:HASKEY(eachFuel)) {
					SET stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] TO
							stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] +
							stageInfo["Resources"][eachFuel].
				} ELSE IF stageNumber <> 0 {
				// If the called out fuel isn't in this stage, search for it in a later stage
					FOR subStageNumber IN RANGE(stageNumber - 1, -1) {
						IF shipInfo["Stage " + subStageNumber]["Resources"]:KEYS:CONTAINS(eachFuel) {
							SET stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] TO
									stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] +
									shipInfo["Stage " + subStageNumber]["Resources"][eachFuel].
							BREAK.
						}
					}
				}
			}
		}
		LOCAL rebalancedFuels IS rebalanceFuelMassPerRatio(stageInfo["Fuels"]).
		LOCAL fuelMass IS 0.
		LOCAL fuelMassUnused IS 0.
		FOR eachEngineType IN rebalancedFuels:KEYS {
			FOR eachFuel IN rebalancedFuels[eachEngineType]:KEYS {
				SET stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] TO rebalancedFuels[eachEngineType][eachFuel]["Mass"].
				SET stageInfo["Fuels"][eachEngineType][eachFuel]["MassUnused"] TO rebalancedFuels[eachEngineType][eachFuel]["MassUnused"].
				SET fuelMass TO fuelMass + rebalancedFuels[eachEngineType][eachFuel]["Mass"].
				SET fuelMassUnused TO fuelMassUnused + rebalancedFuels[eachEngineType][eachFuel]["MassUnused"].
			}
		}
		IF fuelMass > resourceMass {SET fuelMass TO resourceMass. SET fuelMassUnused TO 0.}
		stageInfo:ADD("fuelMass", fuelMass).
		stageInfo:ADD("fuelMassUnused", fuelMassUnused).

		FOR eachEngineType IN stageInfo["FuelsRCS"]:KEYS {
			FOR eachFuel IN stageInfo["FuelsRCS"][eachEngineType]:KEYS {
				SET stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] TO 0.
				// If the called out fuel is in this stage, you are good to go
				IF (stageInfo["Resources"]:HASKEY(eachFuel)) {
					SET stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] TO
							stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] +
							stageInfo["Resources"][eachFuel].
				} ELSE IF stageNumber <> 0 {
				// If the called out fuel isn't in this stage, search for it in a later stage
					FOR subStageNumber IN RANGE(stageNumber - 1, -1) {
						IF shipInfo["Stage " + subStageNumber]["Resources"]:KEYS:CONTAINS(eachFuel) {
							SET stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] TO
									stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] +
									shipInfo["Stage " + subStageNumber]["Resources"][eachFuel].
							BREAK.
						}
					}
				}
			}
		}
		LOCAL fuelRCSMass IS 0.
		LOCAL fuelRCSMassUnused IS 0.
		LOCAL rebalancedFuels IS rebalanceFuelMassPerRatio(stageInfo["FuelsRCS"]).
		FOR eachEngineType IN rebalancedFuels:KEYS {
			FOR eachFuel IN rebalancedFuels[eachEngineType]:KEYS {
				SET stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] TO rebalancedFuels[eachEngineType][eachFuel]["Mass"].
				SET stageInfo["FuelsRCS"][eachEngineType][eachFuel]["MassUnused"] TO rebalancedFuels[eachEngineType][eachFuel]["MassUnused"].
				SET fuelRCSMass TO fuelRCSMass + rebalancedFuels[eachEngineType][eachFuel]["Mass"].
				SET fuelRCSMassUnused TO fuelRCSMassUnused + rebalancedFuels[eachEngineType][eachFuel]["MassUnused"].
			}
		}
		IF fuelRCSMass > resourceMass {SET fuelRCSMass TO resourceMass. SET fuelRCSMassUnused TO 0.}
		stageInfo:ADD("fuelRCSMass", fuelRCSMass).
		stageInfo:ADD("fuelRCSMassUnused", fuelRCSMassUnused).

		stageInfo:ADD("PreviousMass", previousMass).
		FOR p IN stageInfo["Parts"] {
			SET previousMass TO previousMass + p:MASS * 1000.
		}
		stageInfo:ADD("CurrentMass", previousMass).

		LOCAL deltaV TO 0.
		IF stageInfo["CurrentMass"] - stageInfo["FuelMass"] > 0 SET deltaV TO stageInfo["Isp"] * g_0 * LN(stageInfo["CurrentMass"]/(stageInfo["CurrentMass"] - stageInfo["FuelMass"])).
		stageInfo:ADD("DeltaV", deltaV).
		LOCAL deltaVRCS TO 0.
		IF stageInfo["CurrentMass"] - stageInfo["FuelRCSMass"] > 0 SET deltaVRCS TO stageInfo["IspRCS"] * g_0 * LN(stageInfo["CurrentMass"]/(stageInfo["CurrentMass"] - stageInfo["FuelRCSMass"])).
		stageInfo:ADD("DeltaVRCS", deltaVRCS).
		SET shipInfo["Stage " + stageNumber] TO stageInfo.
	}
	IF createlogFileName {
		LOCAL fileName IS "0:" + SHIP:NAME + " Resources.csv".

		LOCAL message IS TIME:SECONDS:TOSTRING() + "," + KUNIVERSE:TIMEWARP:RATE.
		FOR eachResource IN SHIP:RESOURCES {
			IF loggedResources:CONTAINS(eachResource:NAME) SET message TO message + "," + eachResource:AMOUNT + "," + eachResource:AMOUNT * resourceDensity(eachResource:NAME).
		}
		LOG message TO fileName.
	}
}

// Update Ship Information Current
// For the current stage, calculate the following:
//		Current mDot - scalar - fuel consumption rate of the engines at current throttle, kg/s
//		Current burnTime - scalar - burn time of the engine at current throttle, seconds
//		Current thrust - scalar - thrust of active engines at current throttle, N
//		Current thrust from throttleable engines - scalar - thrust of active throttleable engines at current throttle, N
//		Current thrust from nonthrottleable engines - scalar - thrust of active nonthrottleable engines at current throttle, N
//		Current acceleration - scalar - acceleration from engines, m/s^2
//		Current TWR - scalar - thrust-to-weight ratio at the current throttle, unitless
//		Maximum mDot - scalar - fuel consumption rate of the engines at maximum throttle, kg/s
//		Maximum burnTime - scalar - burn time of the engine at maximum throttle, seconds
//		Maximum thrust - scalar - thrust of active engines at maximum throttle, N
//		Maximum thrust from throttleable engines - scalar - thrust of active throttleable engines at maximum throttle, N
//		Maximum thrust from nonthrottleable engines - scalar - thrust of active nonthrottleable engines at maximum throttle, N
//		Maximum acceleration - scalar - acceleration from engines, m/s^2
//		Maximum TWR - scalar - thrust-to-weight ratio at the maximum throttle, unitless
// Note that the above information gets added to shipInfo under two sub headings "Current" and "Maximum"
// Accessing the current TWR, for example, would be shipInfo["Current"]["TWR"]
FUNCTION updateShipInfoCurrent {
	PARAMETER indepententLogging IS FALSE.
	LOCAL fileName IS "0:" + SHIP:NAME + " updateShipInfoCurrent.csv".
	LOCAL current IS LEXICON().
	LOCAL maximum IS LEXICON().
	LOCAL throttleableEngines IS LIST().
	LOCAL nonThrottleableEngines IS LIST().
	FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
		IF eachEngine:THROTTLELOCK nonThrottleableEngines:ADD(eachEngine).
		ELSE throttleableEngines:ADD(eachEngine).
	}
	LOCAL engineStatsVariable IS engineStats(throttleableEngines).
	LOCAL engineStatsConstant IS engineStats(nonThrottleableEngines).
	// the ignitions remaining change as engines are lit, so they are refreshed for the current stage
	LOCAL capabilities IS engineCapabilities(shipInfo["CurrentStage"]["Engines"]).
	FOR eachKey IN capabilities:KEYS {
		SET shipInfo["CurrentStage"][eachKey] TO capabilities[eachKey].
	}
	LOCAL localAccel IS ( SHIP:BODY:MU / (ALTITUDE + SHIP:BODY:RADIUS)^2).
//			effective Isp (scalar, s)
//			thrust (scalar, Newtons)
//			mDot (scalar, kg/s)
//			maximum thrust (scalar, Newtons)
//			maximum mDot (scalar, kg/s)
	current:ADD("Variable", LEXICON("Thrust", engineStatsVariable["Thrust"],
									"mDot", engineStatsVariable["mDot"],
									"Accel", engineStatsVariable["Thrust"]/ ( MASS * 1000),
									"TWR", (engineStatsVariable["Thrust"]/ ( MASS * 1000))/ localAccel)).
	current:ADD("Constant", LEXICON("Thrust", engineStatsConstant["Thrust"],
									"mDot", engineStatsConstant["mDot"],
									"Accel", engineStatsConstant["Thrust"]/ ( MASS * 1000),
									"TWR", (engineStatsConstant["Thrust"]/ ( MASS * 1000))/ localAccel)).
	maximum:ADD("Variable", LEXICON("Thrust", engineStatsVariable["thrustMax"],
									"mDot", engineStatsVariable["mDotMax"],
									"Accel", engineStatsVariable["thrustMax"]/ ( MASS * 1000),
									"TWR", (engineStatsVariable["thrustMax"]/ ( MASS * 1000))/ localAccel)).
	maximum:ADD("Constant", LEXICON("Thrust", engineStatsConstant["thrustMax"],
									"mDot", engineStatsConstant["mDotMax"],
									"Accel", engineStatsConstant["thrustMax"]/ ( MASS * 1000),
									"TWR", (engineStatsConstant["thrustMax"]/ ( MASS * 1000))/ localAccel)).

	current:ADD("Thrust", current["Variable"]["Thrust"] + current["Constant"]["Thrust"]).
	maximum:ADD("Thrust", maximum["Variable"]["Thrust"] + maximum["Constant"]["Thrust"]).

	current:ADD("mDot", current["Variable"]["mDot"] + current["Constant"]["mDot"]).
	maximum:ADD("mDot", maximum["Variable"]["mDot"] + maximum["Constant"]["mDot"]).

	current:ADD("Accel", current["Variable"]["Accel"] + current["Constant"]["Accel"]).
	maximum:ADD("Accel", maximum["Variable"]["Accel"] + maximum["Constant"]["Accel"]).

	current:ADD("TWR", current["Variable"]["TWR"] + current["Constant"]["TWR"]).
	maximum:ADD("TWR", maximum["Variable"]["TWR"] + maximum["Constant"]["TWR"]).

	updateShipInfoResources(FALSE).
	// if the resources do not line up neatly, use resources from the stage that has the most mass in potential fuel
	IF (current["mDot"] <> 0) 	current:ADD("burnTime", shipInfo["CurrentStage"]["FuelMass"] / current["mDot"]).
	ELSE 						current:ADD("burnTime", 0).
	IF (maximum["mDot"] <> 0) 	maximum:ADD("burnTime", shipInfo["CurrentStage"]["FuelMass"] / maximum["mDot"]).
	ELSE 						maximum:ADD("burnTime", 0).
	IF shipInfo:HASKEY("Current") shipInfo:REMOVE("Current").
	shipInfo:ADD("Current", current).
	IF shipInfo:HASKEY("Maximum") shipInfo:REMOVE("Maximum").
	shipInfo:ADD("Maximum", maximum).

	LOCAL thrustPCTThrust IS 0.
	LOCAL thrustPCTEngines IS 0.
	LOCAL thrustPCTEnginesTop IS 0.
	LOCAL thrustPCTEnginesBottom IS 0.
	IF indepententLogging {
		IF NOT shipInfoCurrentLoggingStarted {
			IF connectionToKSC() LOG "Time,Mass,Altitude,Air Pressure,Orbital Velocity,Surface Velocity,Throttle,Current Constant Accel,Current Constant mDot,Current Constant Thrust,Current Constant TWR,Current Variable Accel,Current Variable mDot,Current Variable Thrust,Current Variable TWR,Current Accel,Current BurnTime,Current mDot,Current Thrust,Current TWR,Maximum Constant Accel,Maximum Constant mDot,Maximum Constant Thrust,Maximum Constant TWR,Maximum Variable Accel,Maximum Variable mDot,Maximum Variable Thrust,Maximum Variable TWR,Maximum Accel,Maximum BurnTime,Maximum mDot,Maximum Thrust,Maximum TWR,Thrust Percent Thrust,Thrust Percent Engines" TO fileName.
			IF connectionToKSC() LOG "s,kg,m,atm,m/s,m/s,,m/s^2,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,m/s,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,%,%" TO fileName.
			SET shipInfoCurrentLoggingStarted TO TRUE.
		}

		IF connectionToKSC() LOG TIME:SECONDS + "," + MASS * 1000 + "," + ALTITUDE + "," + SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) + "," + VELOCITY:ORBIT:MAG + "," + VELOCITY:SURFACE:MAG + "," + THROTTLE + "," + shipInfo["Current"]["Constant"]["Accel"] + "," + shipInfo["Current"]["Constant"]["mDot"] + "," + shipInfo["Current"]["Constant"]["Thrust"] + "," + shipInfo["Current"]["Constant"]["TWR"] + "," + shipInfo["Current"]["Variable"]["Accel"] + "," + shipInfo["Current"]["Variable"]["mDot"] + "," + shipInfo["Current"]["Variable"]["Thrust"] + "," + shipInfo["Current"]["Variable"]["TWR"] + "," + shipInfo["Current"]["Accel"] + "," + shipInfo["Current"]["BurnTime"] + "," + shipInfo["Current"]["mDot"] + "," + shipInfo["Current"]["Thrust"] + "," + shipInfo["Current"]["TWR"] + "," + shipInfo["Maximum"]["Constant"]["Accel"] + "," + shipInfo["Maximum"]["Constant"]["mDot"] + "," + shipInfo["Maximum"]["Constant"]["Thrust"] + "," + shipInfo["Maximum"]["Constant"]["TWR"] + "," + shipInfo["Maximum"]["Variable"]["Accel"] + "," + shipInfo["Maximum"]["Variable"]["mDot"] + "," + shipInfo["Maximum"]["Variable"]["Thrust"] + "," + shipInfo["Maximum"]["Variable"]["TWR"] + "," + shipInfo["Maximum"]["Accel"] + "," + shipInfo["Maximum"]["BurnTime"] + "," + shipInfo["Maximum"]["mDot"] + "," + shipInfo["Maximum"]["Thrust"] + "," + shipInfo["Maximum"]["TWR"] + "," + thrustPCTThrust + "," + thrustPCTEngines TO fileName.
	}
}

// given an engine list, return the list of fuels that those engines use
// works for both a list of ENGINEs as well as a list of RCS, or any combination.
FUNCTION getCurrentFuels {
	PARAMETER engineList.
	PARAMETER stageNumber.

	FUNCTION correctFuelName {
		PARAMETER fuelName.
		IF fuelName = "LH2" SET fuelName TO "LqdHydrogen".
		IF fuelName = "Liquid Fuel" SET fuelName TO "LiquidFuel".
		IF fuelName = "LOX" SET fuelName TO "LqdOxygen".
		IF fuelName = "Solid Fuel" SET fuelName TO "SolidFuel".
		IF fuelName = "Xenon Gas" SET fuelName TO "XenonGas".
		IF fuelName = "Electric Charge" SET fuelName TO "ElectricCharge".
		IF fuelName = "Intake Air" SET fuelName TO "IntakeAir".
		RETURN fuelName.
	}

	IF engineList:LENGTH = 0 RETURN LEXICON().
	LOCAL lexOfFuels IS LEXICON().
	LOCAL fuelName IS "".
	LOCAL engineTitle IS "".
	FOR eachEngine IN engineList {
		IF eachEngine:TYPENAME = "Engine" SET engineTitle TO eachEngine:CONFIG:REPLACE(",","").
		ELSE SET engineTitle TO eachEngine:TITLE:REPLACE(",","").
		IF NOT lexOfFuels:KEYS:CONTAINS(engineTitle) {
			lexOfFuels:ADD(engineTitle, LEXICON()).
		}
		FOR eachFuel IN eachEngine:CONSUMEDRESOURCES:KEYS {
			SET fuelName TO correctFuelName(eachFuel).
			IF NOT lexOfFuels[engineTitle]:KEYS:CONTAINS(fuelName) {
				lexOfFuels[engineTitle]:ADD(fuelName,
// Note that the RATIO suffix is the volumetric flow ratio, so it needs to be converted to mass flow ratio by multiplying by the density
											 LEXICON("Ratio", eachEngine:CONSUMEDRESOURCES[eachFuel]:RATIO *
											 resourceDensity(fuelName),
											 "Mass", 0,
											 "MassUnused", 0)).
			}
		}
		// This part is required to ensure that all of the ratios add up to 1.0.
		// Converting from volumetric ratio to mass ratio messes that up.
		LOCAL totalRatio IS 0.
		FOR eachFuel IN eachEngine:CONSUMEDRESOURCES:KEYS {
			SET totalRatio TO totalRatio + lexOfFuels[engineTitle][correctFuelName(eachFuel)]["Ratio"].
		}
		FOR eachFuel IN eachEngine:CONSUMEDRESOURCES:KEYS {
			LOCAL fuelName IS correctFuelName(eachFuel).
			SET lexOfFuels[engineTitle][fuelName]["Ratio"] TO lexOfFuels[engineTitle][fuelName]["Ratio"] / totalRatio.
		}
	}
	RETURN lexOfFuels.
}

FUNCTION gravityTurn {
	PARAMETER START_HEIGHT TO 1000.
	PARAMETER END_HEIGHT TO SHIP:BODY:ATM:HEIGHT * 5/7.
	PARAMETER INITIAL_ANGLE TO 80.
	PARAMETER END_ANGLE TO 5.
	PARAMETER EXP TO 0.740740741.

	IF ALTITUDE < START_HEIGHT RETURN INITIAL_ANGLE.
	IF ALTITUDE > END_HEIGHT RETURN END_ANGLE.

	RETURN ( 1 - ( ( ALTITUDE - START_HEIGHT) / ( END_HEIGHT - START_HEIGHT) ) ^ EXP ) * ( INITIAL_ANGLE - END_ANGLE ) + END_ANGLE.
}

// Height Prediction
// This function calculates the minimum and maximum altitude of the land under the ship's path
// during the specified time. It is passed the number of seconds to look along the current flight
// path and a flag to create a log file with the height information. It returns a lexicon of the
// minimum, maximum and average altitudes that the ship will fly over in the specified duration.
// Passed the following
//			look ahead time (scalar, seconds of flight time to check terrain altitude for)
//			create log file (boolean, if TRUE, a log file will be created)
// Returns a lexicon of the following:
//			"min" (scalar, meters)
//			"max" (scalar, meters)
//			"avg" (scalar, meters)
FUNCTION heightPrediction {
	PARAMETER lookAheadTime.
	PARAMETER createlogFileName IS FALSE.

	IF lookAheadTime < 1 {
		LOCAL returnMe IS LEXICON("min",SHIP:GEOPOSITION:TERRAINHEIGHT).
		returnMe:ADD("max",SHIP:GEOPOSITION:TERRAINHEIGHT).
		returnMe:Add("avg",SHIP:GEOPOSITION:TERRAINHEIGHT).
		RETURN returnMe.
	}

	LOCAL startTime IS TIME:SECONDS.
	LOCAL heightList IS LIST().

	FROM {LOCAL deltaT IS 0.} UNTIL deltaT >= lookAheadTime STEP {SET deltaT TO deltaT + 1.} DO {
		LOCAL geoPos IS SHIP:BODY:GEOPOSITIONOF(POSITIONAT(SHIP, startTime + deltaT)).
		heightList:ADD(LIST(deltaT,geoPos:LAT,geoPos:LNG,geoPos:TERRAINHEIGHT)).
	}

	LOCAL minHeight IS SHIP:GEOPOSITION:TERRAINHEIGHT.
	LOCAL maxHeight IS minHeight.
	LOCAL averageHeight IS 0.
	FOR smallList IN heightList {
		IF smallList[3] < minHeight SET minHeight TO smallList[3].
		IF smallList[3] > maxHeight SET maxHeight TO smallList[3].
		SET averageHeight TO averageHeight + smallList[3].
	}
	SET averageHeight TO averageHeight / heightList:LENGTH.
	IF (createlogFileName AND connectionToKSC()) {
		LOG "Time,Latitude,Longitude,Terrain Height" TO "0:Terrain Heights.csv".
		FOR smallList IN heightList {
			LOG smallList[0] + "," + smallList[1] + "," + smallList[2] + "," + smallList[3] TO "0:Terrain Heights.csv".
		}
	}
	RETURN LEXICON("min",minHeight,"max",maxHeight,"avg",averageHeight).
}

// Removes every maneuver node from the ship's flight plan. Goes through a snapshot of ALLNODES
// rather than looping on HASNODE / NEXTNODE: kOS documents NEXTNODE as a runtime error when there is
// no node, and KSP can take a tick to drop a removed node, so HASNODE can still read TRUE right after
// a REMOVE. Waits one tick afterwards so the flight plan is settled before the caller adds a node.
FUNCTION clearManeuverNodes {
	LOCAL nodesToRemove IS LIST().
	FOR existingNode IN ALLNODES {
		nodesToRemove:ADD(existingNode).
	}
	IF nodesToRemove:LENGTH > 0 {
		FOR existingNode IN nodesToRemove {
			REMOVE existingNode.
		}
		WAIT 0.
	}
}

// Return the vector pointing in the direction of upslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of uphill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of uphill in a vector with length of 1 meter.
// Like all directional functions, north is taken as the Y axis and east is the X axis
FUNCTION findUpSlopeInfo {
	PARAMETER northOffset IS 0.0.
	PARAMETER eastOffset IS 0.0.
	PARAMETER distance IS 0.5.
	LOCAL eastVector IS east_for(SHIP).
	LOCAL terrainHeight IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (       0 + northOffset)*SHIP:NORTH:VECTOR + (       0 + eastOffset)*eastVector):TERRAINHEIGHT                .
	LOCAL heightNorth   IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (distance + northOffset)*SHIP:NORTH:VECTOR + (       0 + eastOffset)*eastVector):TERRAINHEIGHT - terrainHeight.
	LOCAL heightEast    IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (       0 + northOffset)*SHIP:NORTH:VECTOR + (distance + eastOffset)*eastVector):TERRAINHEIGHT - terrainHeight.
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("heading", ARCTAN2(heightEast, heightNorth)).
	returnMe:ADD("slope", ARCTAN2(SQRT(heightNorth * heightNorth + heightEast * heightEast), distance)).
	returnMe:ADD("vector", ((SHIP:NORTH:VECTOR*ANGLEAXIS(-returnMe["slope"], eastVector))*ANGLEAXIS(returnMe["heading"], SHIP:UP:VECTOR))).
	returnMe:ADD("vectorFlat", VXCL(SHIP:UP:VECTOR,returnMe["vector"]):NORMALIZED).
	returnMe:ADD("terrainHeight", terrainHeight).
	returnMe:ADD("heightNorth", heightNorth).
	returnMe:ADD("heightEast", heightEast).
	RETURN returnMe.
}

// Return the vector pointing in the direction of downslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of downhill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of downhill in a vector with length of 1 meter.
FUNCTION findDownSlopeInfo {
	PARAMETER northOffset IS 0.0.
	PARAMETER eastOffset IS 0.0.
	PARAMETER distance IS 0.5.
	LOCAL data IS findUpSlopeInfo(northOffset, eastOffset, distance).
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("heading", data["heading"] + 180).
	returnMe:ADD("slope", data["slope"]).
	returnMe:ADD("vector", -data["vector"]).
	returnMe:ADD("vectorFlat", -data["vectorFlat"]).
	returnMe:ADD("terrainHeight", data["terrainHeight"]).
	returnMe:ADD("heightNorth", data["heightNorth"]).
	returnMe:ADD("heightEast", data["heightEast"]).
	RETURN returnMe.
}

FUNCTION listFiles {
	CLEARSCREEN.
	LOCAL fileList IS LIST().
	LIST Files IN fileList.
	LOCAL totalSize IS 0.
	FOR eachFile IN fileList {
		IF eachFile:EXTENSION <> "csv" {
			PRINT eachFile:NAME + " uses " + eachFile:SIZE + " bytes".
			IF eachFile:ISFILE 	debugString(eachFile:NAME + "," + eachFile:EXTENSION + ",File,"   + eachFile:SIZE + ",bytes").
			ELSE 				debugString(eachFile:NAME + "," + eachFile:EXTENSION + ",Folder," + eachFile:SIZE + ",bytes").
			SET totalSize TO totalSize + eachFile:SIZE.
		}
	}
	PRINT "".
	PRINT "There are a total of " + totalSize + " bytes used.".
	PRINT "Out of a total capacity of " + core:part:getmodule("kOSProcessor"):VOLUME:CAPACITY + " bytes.".
	PRINT "There are " + core:part:getmodule("kOSProcessor"):VOLUME:FREESPACE + " bytes remaining.".
	WAIT 10.
}

FUNCTION logFileNames {
	CLEARSCREEN.
	LOCAL logFileNamesName IS "0:logFileNames.csv".
	LOG "Name,Size (Bytes),Type" TO logFileNamesName.
	LOCAL fileList IS LIST().
	LIST Files IN fileList.
	LOCAL totalSize IS 0.
	FOR eachFile IN fileList {
		IF eachFile:ISFILE 	LOG eachFile:NAME + "," + eachFile:SIZE + ",File" TO logFileNamesName.
		ELSE 								LOG eachFile:NAME + "," + eachFile:SIZE + ",Folder" TO logFileNamesName.

		SET totalSize TO totalSize + eachFile:SIZE.
	}
	LOG "Total all files," + totalSize TO logFileNamesName.
	LOG "Volume Capacity," + core:part:getmodule("kOSProcessor"):VOLUME:CAPACITY TO logFileNamesName.
	LOG "Volume Remaining, " + core:part:getmodule("kOSProcessor"):VOLUME:FREESPACE TO logFileNamesName.
}

// Wait Until Finished Rotating under Locked Steering
// This function pauses until the ship is facing the target direction under cooked control.
// It does not do anything with time warp.
// Passed the following
//			nothing
// Returns the following:
//			nothing
FUNCTION waitUntilFinishedRotating {
	// If the steering manager is not enabled, return immediately.
	IF NOT STEERINGMANAGER:ENABLED RETURN.

	LOCAL previousRoll IS roll_for(SHIP).
	LOCAL previousTime IS 0.
	LOCAL rollRate IS 0.
	UNTIL (VANG(SHIP:FACING:VECTOR, STEERINGMANAGER:TARGET:VECTOR) < 0.1 AND STEERINGMANAGER:ROLLERROR < 0.1 AND ABS(rollRate) < 0.01) {
		IF (previousTime <> 0) SET rollRate TO normalizeAngle180(roll_for(SHIP) - previousRoll)/(TIME:SECONDS - previousTime).
		SET previousRoll TO roll_for(SHIP).
		SET previousTime TO TIME:SECONDS.
		WAIT 0.0.
	}
	RETURN.
}

FUNCTION logArray2Dim {
	PARAMETER array.
	PARAMETER logFileName.
	LOCAL startTime IS TIME:SECONDS.
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
	LOG "Total logging duration:," + (TIME:SECONDS - startTime) TO logFileName.
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
				SET metersNorth TO ((i - (dataOriginal:LENGTH - 1)/2) * delta).
				SET metersEast TO ((j - (dataOriginal:LENGTH - 1)/2) * delta).
				SET currentMin TO derivative.
			}
		}
	}
	RETURN SHIP:BODY:GEOPOSITIONOF(centerPosition + northVector * metersNorth + east * metersEast).
}

// Calculate Engine Stats
// This function calculates a few important stats of a list of engines.
// It assumes that all engines are fired in current atmospheric conditions.
// Passed the following
//			list of engines (list containing type "engine", unitless)
// Returns a lexicon of the following:
//			"Isp" (scalar, s)
//			"thrust" (scalar, Newtons)
//			"mDot" (scalar, kg/s)
//			"thrustMax" (scalar, Newtons)
//			"mDotMax" (scalar, kg/s)
FUNCTION engineStats {
	PARAMETER engineList.
	IF (engineList:LENGTH = 0) RETURN LEXICON("Isp", 0,
																				 "Thrust", 0,
																				 "mDot", 0,
																				 "thrustMax", 0,
																				 "mDotMax", 0).

	LOCAL mDot_cur IS 0.												// Rate of change of mass for the primary engine, given current throttle (kg/s)
	LOCAL mDot_max IS 0.												// Rate of change of mass for the primary engine, with throttle at 100% (kg/s)
	LOCAL F_cur IS 0.														// Current thrust (N)
	LOCAL F_max IS 0.														// Full thrust (N)

	IF NOT engineList:EMPTY {
		FOR eng IN engineList {
			SET mDot_cur TO mDot_cur + eng:MASSFLOW    * 1000.
			SET mDot_max TO mDot_max + eng:MAXMASSFLOW * 1000 * eng:THRUSTLIMIT / 100.		// MAXMASSFLOW ignores the thrust limiter, POSSIBLETHRUST does not
			SET F_cur 	 TO F_cur + eng:THRUST         * 1000.
			SET F_max 	 TO F_max + eng:POSSIBLETHRUST * 1000.
		}
	} ELSE SET mDot_max TO 0.


	IF mDot_max = 0 RETURN LEXICON("Isp", 0,
																 "Thrust", F_cur,
																 "mDot", mDot_cur,
																 "thrustMax", F_max,
																 "mDotMax", mDot_max).

	RETURN LEXICON("Isp", F_max / (g_0 * mDot_max),
								 "Thrust", F_cur,
								 "mDot", mDot_cur,
								 "thrustMax", F_max,
								 "mDotMax", mDot_max).
}

// Calculate Engine Capabilities
// Works out what the engines in a list can do about ignition and throttling.
// Passed the following
//			list of engines (list containing type "engine", unitless)
// Returns a lexicon of the following:
//			"EngineData" (list of lexicons, one for each engine, of "Engine", "Ignitions", "Throttleable", "CanRestart", "Running",
//				"ThrustLimit" (percent, 0 to 100) and "MinThrottle" (fraction, 0 to 1))
//			"MinIgnitions" (scalar, the lowest ignitions remaining of the engines, or -1 if all are unlimited)
//			"LimitedIgnitions" (boolean, whether any engine has limited ignitions)
//			"Throttleable" (boolean, whether all engines can be throttled, FALSE if the list is empty)
//			"CanRestart" (boolean, whether all engines can be restarted, FALSE if the list is empty)
//			"LowestThrustLimit" (scalar, the lowest thrust limiter setting in percent, 100 if the list is empty)
//			"HighestMinThrottle" (scalar, the highest minimum throttle as a fraction, 0 if the list is empty)
// The ignitions of an engine (ENGINE:IGNITIONS) are the number remaining, and do not count the ignition that was used to light
// the engine if it is running now, so a single use engine that is running has 0. It is -1 if the number is unlimited.
// An engine can be restarted if it allows a restart at all, and it is not out of ignitions (0).
// An engine can be throttled if it is not THROTTLELOCK. Its minimum throttle is not considered.
FUNCTION engineCapabilities {
	PARAMETER engineList.

	LOCAL engineData IS LIST().
	LOCAL minIgnitions IS -1.
	LOCAL limitedIgnitions IS FALSE.
	LOCAL allThrottleable IS engineList:LENGTH > 0.
	LOCAL allCanRestart IS engineList:LENGTH > 0.
	LOCAL lowestThrustLimit IS 100.
	LOCAL highestMinThrottle IS 0.

	FOR eng IN engineList {
		LOCAL ignitions IS eng:IGNITIONS.
		LOCAL throttleable IS NOT eng:THROTTLELOCK.
		LOCAL canRestart IS eng:ALLOWRESTART AND (ignitions <> 0).
		LOCAL thrustLimit IS eng:THRUSTLIMIT.
		LOCAL minThrottle IS eng:MINTHROTTLE.
		engineData:ADD(LEXICON("Engine", eng,
								"Ignitions", ignitions,
								"Throttleable", throttleable,
								"CanRestart", canRestart,
								"Running", eng:IGNITION,
								"ThrustLimit", thrustLimit,
								"MinThrottle", minThrottle)).
		IF thrustLimit < lowestThrustLimit SET lowestThrustLimit TO thrustLimit.
		IF minThrottle > highestMinThrottle SET highestMinThrottle TO minThrottle.
		IF ignitions <> -1 {
			SET limitedIgnitions TO TRUE.
			IF minIgnitions = -1 OR ignitions < minIgnitions SET minIgnitions TO ignitions.
		}
		IF NOT throttleable SET allThrottleable TO FALSE.
		IF NOT canRestart SET allCanRestart TO FALSE.
	}

	RETURN LEXICON("EngineData", engineData,
					"MinIgnitions", minIgnitions,
					"LimitedIgnitions", limitedIgnitions,
					"Throttleable", allThrottleable,
					"CanRestart", allCanRestart,
					"LowestThrustLimit", lowestThrustLimit,
					"HighestMinThrottle", highestMinThrottle).
}

// Burn Feasibility Error
// Works out whether the stages of the ship can deliver a burn, before any of the burn is started.
// Checks, for the stages that would be needed, that the engines still have ignitions, that they thrust roughly forward,
// and that the whole ship has enough delta V.
// Passed the following
//			stages that could burn, in the order that they would burn (list of shipInfo stage lexicons)
//			delta V required (scalar, m/s)
// Returns "None" if the burn is feasible, otherwise the reason that it is not (string)
FUNCTION burnFeasibilityError {
	PARAMETER usedStages.
	PARAMETER dV_req.

	IF usedStages:LENGTH = 0 RETURN "Ship has no stages with working engines!".

	LOCAL dV_total IS 0.
	LOCAL dV_remaining IS dV_req.
	FOR eachStage IN usedStages {
		SET dV_total TO dV_total + eachStage["DeltaV"].
		IF dV_remaining > 0 {
			// An engine that is not lit and has no ignitions left (ENGINE:IGNITIONS = 0) can never produce thrust.
			// -1 means unlimited, and a lit engine has already used its ignition.
			LOCAL thrustVector IS V(0, 0, 0).
			FOR eachData IN eachStage["EngineData"] {
				IF eachData["Ignitions"] = 0 AND NOT eachData["Running"] RETURN "Engine " + eachData["Engine"]:CONFIG + " has no ignitions remaining!".
				SET thrustVector TO thrustVector + eachData["Engine"]:FACING:VECTOR * eachData["Engine"]:MAXTHRUST.
			}
			// the combined thrust of the stage has to be roughly forward
			IF thrustVector:MAG > 0 AND VANG(thrustVector, SHIP:FACING:VECTOR) > 45 RETURN "Engines facing the wrong way!".
			SET dV_remaining TO dV_remaining - eachStage["DeltaV"].
		}
	}

	IF dV_total < dV_req RETURN "Not enough delta V! Need " + ROUND(dV_req, 1) + " m/s, ship has " + ROUND(dV_total, 1) + " m/s.".
	RETURN "None".
}

// Vector To CSV
// Formats a vector as three comma separated values with a trailing comma.
// Passed the following
//			vector (vector)
//			number of decimal places (scalar)
// Returns a string
FUNCTION vectorToCSV {
	PARAMETER vec.
	PARAMETER decimals IS 5.
	RETURN ROUND(vec:X, decimals) + "," + ROUND(vec:Y, decimals) + "," + ROUND(vec:Z, decimals) + ",".
}

// Burn Frame
// Builds the reference frame used to log the motion of the ship during a burn.
// The frame is inertial and fixed at the moment the function is called (the start of the burn), so that nothing in it
// rotates during the burn, and the unit vectors are a few cross products of the ship's state at that moment.
// All of the vectors in the frame are in kOS's raw (ship-raw, non-rotating) coordinates, centered on the ship's body for
// positions, so the logged raw positions and velocities need no conversion.
//		P is the direction of the ship's orbital velocity (prograde at the start of the burn)
//		R is the direction from the body to the ship, with any part parallel to P removed (radial out at the start of the burn)
//		N is VCRS(P, R). kOS's VCRS is left-handed, so this is expected to be along the orbit normal (the direction of a
//		positive normal maneuver node component). The log records the node's own normal component and the projection of the
//		initial burn vector on N so that the sign can be checked.
// Passed the following
//			no arguments
// Returns a lexicon of "UT" (scalar, s), "Position" and "Velocity" (vectors, raw, body-relative, m and m/s), "P", "N" and "R" (unit vectors)
FUNCTION burnFrame {
	LOCAL r0 IS -SHIP:BODY:POSITION.
	LOCAL v0 IS SHIP:VELOCITY:ORBIT.
	LOCAL pHat IS v0:NORMALIZED.
	LOCAL rHat IS VXCL(pHat, r0):NORMALIZED.
	LOCAL nHat IS VCRS(pHat, rHat):NORMALIZED.
	RETURN LEXICON("UT", TIME:SECONDS, "Position", r0, "Velocity", v0, "P", pHat, "N", nHat, "R", rHat).
}

// Burn Log Header
// Builds the header of a burn log: the parameters of the burn and the frame, followed by the column titles of the samples.
// Nothing is written to the archive, so that the start of the burn is not delayed by file writing. Put the lines in the
// buffer that is given to burnLogFlush, ahead of the samples.
// Passed the following
//			burn frame (lexicon, from burnFrame)
//			maneuver node (node)
//			delta V vector of the burn at the start of the burn (vector, raw)
//			planned total burn time (scalar, s)
// Returns a list of strings
FUNCTION burnLogHeader {
	PARAMETER frame.
	PARAMETER maneuverNode.
	PARAMETER dv0.
	PARAMETER plannedBurnTime.

	LOCAL lines IS LIST().
	lines:ADD("Burn log," + SHIP:NAME + "," + SHIP:BODY:NAME).
	lines:ADD("Frame,inertial raw axes (non-rotating); positions body-relative; P/N/R fixed at the start of the burn").
	lines:ADD("Start UT,"+ frame["UT"] + ",s").
	lines:ADD("Node UT," + (TIME:SECONDS + maneuverNode:ETA) + ",s").
	lines:ADD("Planned burn time," + plannedBurnTime + ",s").
	lines:ADD("Initial dV," + dv0:MAG + ",m/s").
	lines:ADD("Initial dV raw,x,y,z," + vectorToCSV(dv0)).
	lines:ADD("Initial dV in frame,P,N,R," + VDOT(dv0, frame["P"]) + "," + VDOT(dv0, frame["N"]) + "," + VDOT(dv0, frame["R"])).
	lines:ADD("Node components (KSP),prograde,normal,radial," + maneuverNode:PROGRADE + "," + maneuverNode:NORMAL + "," + maneuverNode:RADIALOUT).
	lines:ADD("P raw,x,y,z," + vectorToCSV(frame["P"], 8)).
	lines:ADD("N raw,x,y,z," + vectorToCSV(frame["N"], 8)).
	lines:ADD("R raw,x,y,z," + vectorToCSV(frame["R"], 8)).
	lines:ADD("Position at start raw,x,y,z," + vectorToCSV(frame["Position"])).
	lines:ADD("Velocity at start raw,x,y,z," + vectorToCSV(frame["Velocity"], 6)).
	lines:ADD("Body radius," + SHIP:BODY:RADIUS + ",m,Body mu," + SHIP:BODY:MU + ",m^3/s^2").
	lines:ADD("UT,tBurn,nodeETA,throttle,availThrust,maxThrust,mass,dvThrustEst,stage," +
		"rX,rY,rZ,vX,vY,vZ,faceX,faceY,faceZ,dvX,dvY,dvZ," +
		"rP,rN,rR,vP,vN,vR,faceP,faceN,faceR,dvP,dvN,dvR,dvMag," +
		"nodePrograde,nodeNormal,nodeRadial," +
		"pointErr,steerAngleErr,steerRollErr,angVel," +
		"inc,LAN,ecc,SMA,trueAnom,alt," +
		"planeTilt,dInc,dLAN,dAop,dEcc,dSMA,crossing").
	lines:ADD("units,s,s,s,0-1,kN,kN,kg,m/s,," +
		"m,m,m,m/s,m/s,m/s,,,,m/s,m/s,m/s," +
		"m,m,m,m/s,m/s,m/s,,,,m/s,m/s,m/s,m/s," +
		"m/s,m/s,m/s," +
		"deg,deg,deg,rad/s," +
		"deg,deg,,m,deg,m," +
		"deg,deg,deg,deg,,m,deg").
	RETURN lines.
}

// Burn Log Sample
// Builds one line of the burn log, describing the motion of the ship at this instant.
// The raw columns (r, v, face, dv) are in kOS's raw inertial coordinates, and the P/N/R columns are the same vectors
// projected on the fixed frame of burnFrame.
// Passed the following
//			burn frame (lexicon, from burnFrame)
//			maneuver node (node)
//			throttle setting (scalar, 0 to 1)
//			delta V integrated from the thrust and mass of the ship, as a rough check of the node's delta V (scalar, m/s)
//			snapshot from before the burn (lexicon, from nodeOrbitSnapshot)
// The last columns are the error of the orbit that the ship is in at this instant (the osculating orbit, which is where the
// ship would coast if the engines were cut now) against the orbit that the node predicted: the angle between the orbit planes
// (planeTilt), the differences in inclination, LAN and argument of periapsis (deg), eccentricity and semi-major axis (m), and
// where the new plane crosses the old one, from the node (crossing, see planeCrossingAngle). They go to zero as the burn finishes.
// Returns a string
FUNCTION burnLogSample {
	PARAMETER frame.
	PARAMETER maneuverNode.
	PARAMETER throttleSetting.
	PARAMETER dvThrustEst.
	PARAMETER snapshot.

	LOCAL pos IS -SHIP:BODY:POSITION.
	LOCAL vel IS SHIP:VELOCITY:ORBIT.
	LOCAL face IS SHIP:FACING:VECTOR.
	LOCAL dv IS maneuverNode:DELTAV.
	LOCAL pHat IS frame["P"].
	LOCAL nHat IS frame["N"].
	LOCAL rHat IS frame["R"].

	LOCAL steerAngleError IS 0.
	LOCAL steerRollError IS 0.
	IF STEERINGMANAGER:ENABLED {
		SET steerAngleError TO STEERINGMANAGER:ANGLEERROR.
		SET steerRollError TO STEERINGMANAGER:ROLLERROR.
	}

	LOCAL elements IS orbitElementsLexicon(SHIP:ORBIT).
	LOCAL predicted IS snapshot["Predicted"].
	LOCAL actualNormal IS VCRS(pos, vel):NORMALIZED.			// from the state, not from inc and LAN (see nodeOrbitSnapshot)

	RETURN ROUND(TIME:SECONDS, 3) + "," + ROUND(TIME:SECONDS - frame["UT"], 3) + "," + ROUND(maneuverNode:ETA, 3) + "," +
		ROUND(throttleSetting, 4) + "," + ROUND(AVAILABLETHRUST, 4) + "," + ROUND(MAXTHRUST, 4) + "," + ROUND(SHIP:MASS * 1000, 3) + "," +
		ROUND(dvThrustEst, 5) + "," + STAGE:NUMBER + "," +
		vectorToCSV(pos, 3) + vectorToCSV(vel, 6) + vectorToCSV(face, 6) + vectorToCSV(dv, 6) +
		ROUND(VDOT(pos, pHat), 3) + "," + ROUND(VDOT(pos, nHat), 3) + "," + ROUND(VDOT(pos, rHat), 3) + "," +
		ROUND(VDOT(vel, pHat), 6) + "," + ROUND(VDOT(vel, nHat), 6) + "," + ROUND(VDOT(vel, rHat), 6) + "," +
		ROUND(VDOT(face, pHat), 6) + "," + ROUND(VDOT(face, nHat), 6) + "," + ROUND(VDOT(face, rHat), 6) + "," +
		ROUND(VDOT(dv, pHat), 6) + "," + ROUND(VDOT(dv, nHat), 6) + "," + ROUND(VDOT(dv, rHat), 6) + "," + ROUND(dv:MAG, 6) + "," +
		ROUND(maneuverNode:PROGRADE, 6) + "," + ROUND(maneuverNode:NORMAL, 6) + "," + ROUND(maneuverNode:RADIALOUT, 6) + "," +
		ROUND(VANG(face, dv), 4) + "," + ROUND(steerAngleError, 4) + "," + ROUND(steerRollError, 4) + "," + ROUND(SHIP:ANGULARVEL:MAG, 6) + "," +
		ROUND(SHIP:ORBIT:INCLINATION, 6) + "," + ROUND(SHIP:ORBIT:LAN, 6) + "," + ROUND(SHIP:ORBIT:ECCENTRICITY, 8) + "," +
		ROUND(SHIP:ORBIT:SEMIMAJORAXIS, 2) + "," + ROUND(SHIP:ORBIT:TRUEANOMALY, 5) + "," + ROUND(SHIP:ALTITUDE, 2) + "," +
		ROUND(VANG(actualNormal, snapshot["PredictedNormal"]), 5) + "," + ROUND(elements["inc"] - predicted["inc"], 5) + "," +
		ROUND(normalizeAngle180(elements["lan"] - predicted["lan"]), 5) + "," + ROUND(normalizeAngle180(elements["aop"] - predicted["aop"]), 5) + "," +
		ROUND(elements["ecc"] - predicted["ecc"], 8) + "," + ROUND(elements["sma"] - predicted["sma"], 2) + "," +
		ROUND(planeCrossingAngle(snapshot["OldNormal"], actualNormal, snapshot["NodePosition"], snapshot["NodeVelocity"]), 5).
}

// Burn Log Flush
// Writes the lines buffered by burnLogSample to the burn log and empties the buffer, if the archive can be reached.
// If it cannot, the lines are kept (up to 3000, after which the oldest are dropped).
// Passed the following
//			file name (string)
//			buffered lines (list of strings)
//			write regardless of how many lines are buffered (boolean, default FALSE, otherwise it writes at 10 lines)
// The buffered lines are written with one LOG, because each LOG takes a noticeable amount of game time.
FUNCTION burnLogFlush {
	PARAMETER fileName.
	PARAMETER buffer.
	PARAMETER force IS FALSE.

	IF buffer:LENGTH >= 10 OR (force AND buffer:LENGTH > 0) {
		IF connectionToKSC() {
			LOCAL text IS buffer[0].
			FOR eachIndex IN RANGE(1, buffer:LENGTH) SET text TO text + CHAR(10) + buffer[eachIndex].
			LOG text TO fileName.
			buffer:CLEAR().
		} ELSE {
			UNTIL buffer:LENGTH <= 3000 buffer:REMOVE(0).
		}
	}
}

// Calculate Engine Stats for RCS engines
// This function calculates a few important stats of a list of engines.
// It assumes that all engines are fired in current atmospheric conditions.
// Passed the following
//			list of RCS engines (list containing type "part", unitless)
// Returns a lexicon of the following:
//			"Isp" (scalar, s)
//			"thrustMax" (scalar, Newtons)
//			"mDotMax" (scalar, kg/s)
FUNCTION engineStatsRCS {
	PARAMETER engineList.
	IF (engineList:LENGTH = 0) RETURN LEXICON("Isp", 0,
											 "thrustMax", 0,
											 "mDotMax", 0).

	LOCAL mDot_max IS 0.
	LOCAL F_max IS 0.

	IF NOT engineList:EMPTY {
		FOR eng IN engineList {
			SET mDot_max TO mDot_max + eng:MAXMASSFLOW  * 1000.
			SET F_max 	 TO F_max + eng:AVAILABLETHRUST * 1000.
		}
	} ELSE SET mDot_max TO 0.

	IF mDot_max = 0 RETURN LEXICON("Isp", 0,
																 "thrustMax", F_max,
																 "mDotMax", mDot_max).

	RETURN LEXICON("Isp", F_max / (g_0 * mDot_max),
								 "thrustMax", F_max,
								 "mDotMax", mDot_max).
}

// East For
// This function recieves a vessel and returns a vector pointing east from that vessel.
// Passed the following
//			ves (vessel)
// Returns the following:
// 			east vector
FUNCTION east_for {
  PARAMETER ves.
  RETURN VCRS(ves:UP:VECTOR, VES:NORTH:VECTOR).
}

// Yaw For
// This function recieves a vessel, vector or direction and returns the yaw (compass heading) that the input is pointing toward
// If the input is a vector, or direction, calculate the yaw based on SHIP. If passed a VESSEL, calcualte it based on the passed VESSEL.
// Passed the following
//			input (vessel, vector or direction)
// Returns the following:
//			heading of input (scalar, degrees from north)
FUNCTION yaw_for {
	PARAMETER input.
	LOCAL pointing IS V(0,0,0).
	LOCAL ves IS SHIP.
	IF input:TYPENAME = "vessel"			{SET pointing TO input:FACING:FOREVECTOR. SET ves TO input.}
	ELSE IF input:TYPENAME = "vector"		SET pointing TO input.
	ELSE IF input:TYPENAME = "direction"	SET pointing TO input:VECTOR.

	LOCAL east IS east_for(ves).

	LOCAL trig_x IS VDOT(ves:NORTH:VECTOR, pointing).
	LOCAL trig_y IS VDOT(east, pointing).

	LOCAL result IS ARCTAN2(trig_y, trig_x).

	IF result < 0 RETURN 360 + result.
	RETURN result.
}

// Pitch For
// This function recieves a vessel, vector or direction and returns the pitch (degrees above horizon) that the input is pointing toward
// If the input is a vector, or direction, calculate the yaw based on SHIP. If passed a VESSEL, calcualte it based on the passed VESSEL.
// Passed the following
//			input (vessel, vector or direction)
// Returns the following:
//			pitch of vector (scalar, degrees above (or below, for negative) the horizon)
FUNCTION pitch_for {
  PARAMETER input.
	LOCAL pointing IS V(0,0,0).
	LOCAL ves IS SHIP.
		 IF input:TYPENAME = "vessel"		{SET pointing TO input:FACING:FOREVECTOR. SET ves TO input.}
	ELSE IF input:TYPENAME = "vector"		SET pointing TO input.
	ELSE IF input:TYPENAME = "direction"	SET pointing TO input:VECTOR.

  RETURN 90 - VANG(ves:UP:vector, pointing).
}

// Roll For
// This function recieves a vessel and returns the roll of the vessel
// Passed the following
//			vessel to be looked at (vessel)
// Returns the following:
//			roll of vector (scalar, degrees off of horizontal)
FUNCTION roll_for {
	PARAMETER ves.
	
	//this is the dead zone for roll when the ship is vertical
	IF VANG(ves:FACING:VECTOR,ves:UP:VECTOR) < 0.2 {RETURN 0.}
	ELSE {
		LOCAL raw IS VANG(VXCL(ves:FACING:VECTOR, ves:UP:VECTOR), ves:FACING:STARVECTOR).
		IF VANG(ves:UP:VECTOR, ves:FACING:TOPVECTOR) > 90 {
			IF raw > 90 {
				RETURN 270 - raw.
			} ELSE {
				RETURN -90 - raw.
			}
		} ELSE {
			RETURN raw - 90.
		}
	}
}

// Create Node
// This function creates a node on the current vessel from the given parameters
// Passed the following
//			seconds from now the node should be executed (scalar, seconds)
//			radial component of the delta V (scalar, m/s)
//			normal component of the delta V (scalar, m/s)
//			prograde component of the delta V (scalar, m/s)
// Returns the following:
//			nothing
FUNCTION createNode
{
	PARAMETER dT IS 60.
	PARAMETER Radial IS 0.
	PARAMETER Norm IS 0.
	PARAMETER Pro IS 0.
	LOCAL X TO NODE(TIME:SECONDS + dT, Radial, Norm, Pro).
	ADD X.            // adds maneuver to flight plan
}

// Print Static Lines
// This function prints the given number of lines starting at the given row.
// It assumes that following lines should be printed on following rows.
// Passed the following
//			list of strings to print (LIST)
//			row of the first string (scalar)
// Returns the following:
//			nothing
// Modified from example code given by nuggreat on Discord on July 1, 2022
FUNCTION printLines {
    PARAMETER linesToPrint.
	PARAMETER startingRow IS 0.
    LOCAL i IS startingRow.
	FOR index IN RANGE(linesToPrint:LENGTH) {
		PRINT linesToPrint[index]:PADRIGHT(TERMINAL:WIDTH) AT (0, startingRow + index).
	}
}

// Print Dynamic Lines
// This function prints the given string(s) at the given row(s).
// Passed the following
//			List of Lexicons, each of which contains a string, X coordinate, and Y coordinate
// Returns the following:
//			nothing
// Modified from example code given by nuggreat on Discord on July 1, 2022
FUNCTION printDynamicLines {
    PARAMETER linesToPrint.
	for eachLine in linesToPrint {
		PRINT eachLine["string"] AT (eachLine["xCoord"], eachLine["yCoord"]).
	}
}

// Count given characters in a string
// This function returns an integer of the number of times that the given substring is present in the larger string.
// It defaults to CHAR(10), which is the newline character.
FUNCTION countCharacters {
	PARAMETER stringToReview, characterToFind IS CHAR(10).
	RETURN stringToReview:SPLIT(characterToFind):LENGTH - 1.
}

// Round Vector
// This function rounds the components of vectors to a specified number of digits
// This is the equivalent of the built in ROUND function, but it works on vectors
// This function is intended for use in formatting output to the terminal or a human-readable log file
// Passed the following
//			vector to be rounded (vector, any units)
//			number of digits to round to (scalar, should be integer)
// Returns the following:
//			the rounded vector (string)
FUNCTION ROUNDV {
	PARAMETER vec.
	PARAMETER digits IS 0.
	RETURN ROUND(vec:X, digits) + "," + ROUND(vec:Y, digits) + "," + ROUND(vec:Z, digits).
}

// Log All Actions
// This function logs all actions from all parts to the specified log file.
// It is intended to be used temporarily as part of programming to determine what available actions are.
// Passed the following
//			name of the log file (string)
// Returns the following:
//			nothing
FUNCTION logAllActions
{
	PARAMETER filename IS "0:Action Log.csv".
	PARAMETER oncePerPart IS FALSE.
	LOG "Part Title,Unique ID,Module Name,Item Name,Item Type,Field Value" TO filename.
	LOCAL partNameList IS "".
	FOR eachPart IN SHIP:PARTS {
		IF (NOT oncePerPart) OR (NOT partNameList:CONTAINS(eachPart:TITLE)) {
			SET partNameList TO partNameList + eachPart:TITLE.
			FOR moduleName IN eachPart:MODULES {
				FOR field in eachPart:GETMODULE(moduleName):ALLFIELDNAMES {
					IF field:LENGTH <> 0 LOG eachPart:TITLE:REPLACE(",","") + "," + eachPart:UID + "," + moduleName:REPLACE(",","") + "," + field:REPLACE(",","") + ",Field," + eachPart:GETMODULE(moduleName):GETFIELD(field):TOSTRING:REPLACE(",","") TO filename.
				}
				FOR event in eachPart:GETMODULE(moduleName):ALLEVENTNAMES {
					LOG eachPart:TITLE:REPLACE(",","") + "," + eachPart:UID + "," + moduleName:REPLACE(",","") + "," + event:REPLACE(",","") + ",Event" TO filename.
				}
				FOR action in eachPart:GETMODULE(moduleName):ALLACTIONNAMES {
					LOG eachPart:TITLE:REPLACE(",","") + "," + eachPart:UID + "," + moduleName:REPLACE(",","") + "," + action:REPLACE(",","") + ",Action" TO filename.
				}
			}
		}
	}
}

// Log All Parts
// This function logs the more usefull attributes of all parts to the specified log file.
// It is intended to be used temporarily as part of programming to determine what available actions are.
// Passed the following
//			name of the log file (string)
// Returns the following:
//			nothing
FUNCTION logAllParts
{
	PARAMETER filename IS "0:Part Log.csv".
	LOG "Part Title,Name,Type,Mass (kg),Dry Mass (kg),Wet Mass (kg),Tag,Module Count,Has Physics" TO filename.
	LOCAL partNameList IS "".
	FOR eachPart IN SHIP:PARTS {
		IF NOT partNameList:CONTAINS(eachPart:TITLE) {
			SET partNameList TO partNameList + eachPart:TITLE.
			LOG eachPart:TITLE:REPLACE(",","") + "," + eachPart:NAME + "," + eachPart:TYPENAME + "," + eachPart:MASS * 1000 + "," + eachPart:DRYMASS * 1000 + "," + eachPart:WETMASS * 1000 + "," + eachPart:TAG + "," + eachPart:MODULES:LENGTH + "," + eachPart:HASPHYSICS TO fileName.
		}
	}
}

// Activate All Omni Antennae
// Activate all omnidirectional antennae on the ship
// Note that this function ignores all targetable antennae
// Passed the following
//			nothing
// Returns the following:
//			nothing
FUNCTION activateOmniAntennae
{
	if Career():CANDOACTIONS {
		LOCAL allParts IS LIST().
		LIST PARTS IN allParts.
		LOCAL mods TO 0.
		LOCAL isAntenna TO FALSE.
		FOR eachPart IN allParts {
			SET mods TO eachPart:MODULES.
			SET isAntenna TO FALSE.
			FOR eachModule IN MODS {
				IF (eachModule="ModuleRTAntenna") {
					IF NOT (eachPart:GETMODULE("ModuleRTAntenna"):HASFIELD("dish range")) {
						SET isAntenna TO TRUE.
					}
				}
				IF (eachModule="ModuleDeployableAntenna") {
					IF NOT (eachPart:GETMODULE("ModuleDeployableAntenna"):HASFIELD("dish range")) {
						SET isAntenna TO TRUE.
					}
				}
			}
			IF (isAntenna) {
				IF ADDONS:AVAILABLE("RT") eachPart:GETMODULE("ModuleRTAntenna"):DOACTION("activate",TRUE).
				ELSE eachPart:GETMODULE("ModuleDeployableAntenna"):DOACTION("extend antenna",TRUE).
			}
		}
	}
}

// Deactivate All Omni Antennae
// Deactivate all omnidirectional antennae on the ship
// Note that this function ignores all targetable antennae
// Passed the following
//			nothing
// Returns the following:
//			nothing
FUNCTION deactivateOmniAntennae
{
	if Career():CANDOACTIONS {
		LOCAL allParts IS LIST().
		LIST PARTS IN allParts.
		LOCAL mods TO 0.
		LOCAL isAntenna TO FALSE.
		FOR eachPart IN allParts {
			SET mods TO eachPart:MODULES.
			SET isAntenna TO FALSE.
			FOR eachModule IN MODS {
				IF (eachModule="ModuleRTAntenna") {
					IF NOT (eachPart:GETMODULE("ModuleRTAntenna"):HASFIELD("dish range")) {
						SET isAntenna TO TRUE.
					}
				}
				IF (eachModule="ModuleDeployableAntenna") {
					IF NOT (eachPart:GETMODULE("ModuleDeployableAntenna"):HASFIELD("dish range")) {
						SET isAntenna TO TRUE.
					}
				}
			}
			IF (isAntenna) {
				IF ADDONS:AVAILABLE("RT") eachPart:GETMODULE("ModuleRTAntenna"):DOACTION("deactivate",TRUE).
				ELSE eachPart:GETMODULE("ModuleDeployableAntenna"):DOACTION("retract antenna",TRUE).
			}
		}
	}
}

// Activate All Dish Antennae
// Activate all dish antennae on the ship
// Note that this function ignores all targetable antennae
// Passed the following
//			nothing
// Returns the following:
//			nothing
FUNCTION activateDishAntennae
{
	LOCAL allParts IS LIST().
	LIST PARTS IN allParts.
	LOCAL mods TO 0.
	LOCAL isAntenna TO FALSE.
	FOR eachPart IN allParts {
		SET mods TO eachPart:MODULES.
		SET isAntenna TO FALSE.
		FOR eachModule IN MODS {
			IF (eachModule="ModuleRTAntenna") {
				IF (eachPart:GETMODULE("ModuleRTAntenna"):HASFIELD("dish range")) {
					SET isAntenna TO TRUE.
				}
			}
		}
		IF (isAntenna) {eachPart:GETMODULE("ModuleRTAntenna"):DOACTION("activate",TRUE). }.
	}
}

// Deactivate All Dish Antennae
// Deactivate all dish antennae on the ship
// Note that this function ignores all targetable antennae
// Passed the following
//			nothing
// Returns the following:
//			nothing
FUNCTION deactivateDishAntennae
{
	LOCAL allParts IS LIST().
	LIST PARTS IN allParts.
	LOCAL mods TO 0.
	LOCAL isAntenna TO FALSE.
	FOR eachPart IN allParts {
		SET mods TO eachPart:MODULES.
		SET isAntenna TO FALSE.
		FOR eachModule IN MODS {
			IF (eachModule="ModuleRTAntenna") {
				IF (eachPart:GETMODULE("ModuleRTAntenna"):HASFIELD("dish range")) {
					SET isAntenna TO TRUE.
				}
			}
		}
		IF (isAntenna) {eachPart:GETMODULE("ModuleRTAntenna"):DOACTION("deactivate",TRUE). }.
	}
}

// Engine Information
// Print a variety of useful information about engines to the terminal
// The default is to only display % of max thrust for each engine, but if the DETAILED option is chosen, more information can be displayed
// Passed the following
//			x-coordinate for display on the terminal (scalar, characters)
//			y-coordinate for display on the terminal (scalar, characters)
//			detailed information is requested (boolean, TRUE means show detailed information)
// Returns the following:
//			nothing
FUNCTION engineInfo {
	PARAMETER X.
	PARAMETER Y.
	PARAMETER DETAILED IS FALSE.

	LOCAL engTitle IS "".
	LOCAL myVariable IS LIST().
	LIST ENGINES IN myVariable.
	LOCAL engineData IS LEXICON().
	FOR eng IN myVariable {
		IF eng:IGNITION {
			IF isStock() SET engTitle TO eng:CONFIG:SUBSTRING(0, eng:CONFIG:FINDLAST(CHAR(34)) + 1).
			ELSE SET engTitle TO eng:CONFIG.
			IF engineData:KEYS:CONTAINS(engTitle) {
				SET engineData[engTitle]["number"] TO engineData[engTitle]["number"] + 1.
				engineData[engTitle]["EngineList"]:ADD(eng).
			} ELSE {
				LOCAL singleEngData IS LEXICON().
				singleEngData:ADD("number", 1).
				singleEngData:ADD("EngineList", LIST(eng)).
				engineData:ADD(engTitle, singleEngData).
			}
		}
	}

	LOCAL message IS "".
	LOCAL count IS 0.
	LOCAL maxLength IS 0.
	LOCAL engineStat IS LIST().
	LOCAL thrustDecimals IS 2.
	LOCAL throttleAdjust IS 0.
	FOR engType IN engineData:KEYS {
		IF engType:LENGTH > maxLength SET maxLength TO engType:LENGTH.
	}
	FOR engType IN engineData:KEYS {
		SET engineStat TO engineStats(engineData[engType]["EngineList"]).
		SET engineStat["Thrust"] TO engineStat["Thrust"] / 1000.0.
		SET engineStat["thrustMax"] TO engineStat["thrustMax"] / 1000.0.
		IF (DETAILED) {
//			effective Isp (scalar, s)
//			thrust (scalar, Newtons)
//			mDot (scalar, kg/s)
//			maximum thrust (scalar, Newtons)
//			maximum mDot (scalar, kg/s)
			SET thrustDecimals TO 2.
			IF engineStat["Thrust"] / engineData[engType]["number"] > 100 SET thrustDecimals TO 1.
			IF engineStat["Thrust"] / engineData[engType]["number"] > 1000 SET thrustDecimals TO 0.
			SET throttleAdjust TO THROTTLE.
			IF NOT engineData[engType]["EngineList"][0]:ALLOWSHUTDOWN SET throttleAdjust TO 1.
			SET message TO "".
			SET message TO message + engType:TOSTRING:PADLEFT(maxLength) + "  ".
			SET message TO message + engineData[engType]["number"]:TOSTRING:PADLEFT(5) + "  ".
			SET message TO message + ROUND(throttleAdjust * engineStat["Thrust"] / engineData[engType]["number"], thrustDecimals):TOSTRING:PADLEFT(6) + "  ".
			SET message TO message + ROUND(engineStat["thrustMax"] / engineData[engType]["number"], thrustDecimals):TOSTRING:PADLEFT(7) + "  ".
			IF engineStat["Isp"] <> 0 SET message TO message + ROUND(engineStat["Isp"], 0):TOSTRING:PADLEFT(3) + "  ".
			ELSE SET message TO message + "  0  ".
			IF engineStat["Isp"] <> 0 SET message TO message + ROUND(throttleAdjust * engineStat["mDot"], 2):TOSTRING:PADLEFT(8) + "  ".
			ELSE SET message TO message + "       0  ".
			SET message TO message + engineData[engType]["EngineList"][0]:ALLOWSHUTDOWN:TOSTRING:PADLEFT(5) + "         ".
			PRINT message AT (X + 2 , Y + 2 + COUNT).
		} ELSE {
			IF engineStat["thrustMax"] <> 0 PRINT engType:TOSTRING:PADLEFT(maxLength) + " " + ROUND(engineStat["Thrust"] / engineStat["thrustMax"] * 100) + "%" AT (X + 1 , Y + 1 + COUNT).
			ELSE 							 PRINT engType:TOSTRING:PADLEFT(maxLength) + " N/A%" AT (X + 1 , Y + 1 + COUNT).
		}
		SET count TO count + 1.
	}

	IF (DETAILED) {
		PRINT "":PADRIGHT(maxLength) + "    COUNT  THRUST  T AVAIL  ISP  FUEL USE   KILL        " AT (X, Y).
		PRINT "":PADRIGHT(maxLength) + "               kN       kN    s      kg/s               " AT (X, Y + 1).
		PRINT "                                                                                 " AT (X, Y + 2 + COUNT).
		PRINT "                                                                                 " AT (X, Y + 3 + COUNT).
	} ELSE {
		PRINT "         % MAX THRUST   " AT (X, Y).
		PRINT "                        " AT (X + 1 , Y + 1 + COUNT).
	}
}

// Height Above Ground
// Determines the current height above ground, taking into account the parts in the current stage
// Because of some inconsistencies in ALT:RADAR, this function was developed to determine the true height above ground
// This function does take into account the position of the parts in the current stage. This assumes that the current
// stage parts are on the bottom of the rocket.
// Passed the following
//			nothing
// Returns the following:
//			current height above ground (scalar, meters)
FUNCTION heightAboveGround {
	RETURN shipBounds:BOTTOMALTRADAR.
}

FUNCTION resourcesInParts {
	PARAMETER partList.
	LOCAL resourceList IS LEXICON().

	// for each part in the specified stage
	FOR eachPart IN partList {
		// for each resource in the part
		FOR eachResource IN eachPart:RESOURCES {
			// if there is more than 0 of the resource
			IF (eachResource:AMOUNT <> 0) {
				// if the resource is already in the list
				IF (resourceList:KEYS:CONTAINS(eachResource:NAME) ) {
					// add the amount to the existing entry in the list
					SET resourceList[eachResource:NAME] TO resourceList[eachResource:NAME] + eachResource:AMOUNT*resourceDensity(eachResource:NAME).
				}
				// if the resource is not already in the resource list, add the resource to the list
				ELSE {
					resourceList:ADD(eachResource:NAME, eachResource:AMOUNT*resourceDensity(eachResource:NAME)).
				}
			}
		}
	}
	RETURN resourceList.
}

FUNCTION isLFFullThrust {
	// This function returns the status of the currently active engines.
	// If the currently active engines are at greater than 85% of available
	// thrust, this function returns TRUE, otherwise FALSE.
	// 85% was chosen because with a TWR of 1.2, 85% of thrust is a TWR of 1.0.
	PARAMETER unclampPercent IS 0.85.

	// If the maximum variable thrust is zero, return TRUE, as there are no LF engines.
	IF shipInfo["Maximum"]["Variable"]["Accel"] = 0 RETURN TRUE.

	LOCAL totalThrust IS 0.0.
	LOCAL currentThrust IS 0.0.
	LOCAL myVariable TO LIST().
	LIST ENGINES IN myVariable.

	// for each ignited engine, add up the current thrust and the target thrust of that engine.
	FOR eng IN myVariable {
		IF (eng:IGNITION) {
			SET currentThrust TO currentThrust + eng:THRUST.
			SET totalThrust TO totalThrust + eng:AVAILABLETHRUST.
		}
	}

	IF totalThrust = 0 SET totalThrust TO 1.

	RETURN (currentThrust / totalThrust) > unclampPercent.
}

// given a time in seconds, returns a string of the time broken down to days, hours, minutes, seconds.
// Units that are zero are left out, and a negative time starts with a minus sign.
// digits is the number of decimal places of the seconds, which are cut off and not rounded. If it is below 0, the smallest units
// are left out as well: -1 leaves out the seconds, -2 the minutes and -3 the hours. If nothing is left to show, a zero is
// shown in the smallest unit that is displayed, such as "0s", "0m" or "-0s".
// Days are KUNIVERSE:HOURSPERDAY hours long, so with 24 hour days (the realistic universe)
// example: given 90090.124 (seconds) and 2 digits, the function will return "1d 1h 1m 30.12s"
// example: given 90090.124 (seconds) and 0 digits, the function will return "1d 1h 1m 30s"
// example: given 0.3 (seconds) and 0 digits, the function will return "0s", and -0.3 gives "-0s"
FUNCTION timeToString
{
	PARAMETER T IS 0.
	PARAMETER digits IS 0.
	PARAMETER padWithZeros IS FALSE.
	LOCAL isNegative IS T < 0.
	IF T < 0 SET T TO -T.

	LOCAL hoursPerDay IS KUNIVERSE:HOURSPERDAY.
	LOCAL days IS 0.
	LOCAL hours IS 0.
	LOCAL minutes IS 0.
	LOCAL seconds IS 0.
	LOCAL message IS "".

	SET days TO FLOOR ( T / (hoursPerDay*60*60) ).
	SET hours TO FLOOR ( MOD ( T, hoursPerDay*60*60) / (60*60) ).
	SET minutes TO FLOOR ( MOD ( T, 60*60) / 60 ).
	IF digits > 0 SET seconds TO FLOOR( MOD(T, 60)*(10^digits))/(10^digits).
	ELSE SET seconds TO FLOOR( MOD(T,60)).

	LOCAL secondsString IS seconds:TOSTRING.
	IF digits > 0 AND (secondsString:FINDLAST(".") <> -1) {
		LOCAL firstPart IS secondsString:SUBSTRING(0, secondsString:FINDLAST(".") + 1).
		LOCAL  lastPart IS secondsString:SUBSTRING(secondsString:FINDLAST(".") + 1, secondsString:LENGTH - 1 - secondsString:FINDLAST(".")):PADRIGHT(digits).
		IF padWithZeros SET lastPart TO lastPart:REPLACE(" ","0").
		SET secondsString TO firstPart + lastPart.
	}

	LOCAL firstSpace IS "".
	IF isNegative SET message TO message + "-".
	IF digits > -4 AND    days <> 0 {SET message TO message + firstSpace +          days + "d". SET firstSpace TO " ".}
	IF digits > -3 AND   hours <> 0 {SET message TO message + firstSpace +         hours + "h". SET firstSpace TO " ".}
	IF digits > -2 AND minutes <> 0 {SET message TO message + firstSpace +       minutes + "m". SET firstSpace TO " ".}
	IF digits > -1 AND seconds <> 0 {SET message TO message + firstSpace + secondsString + "s". SET firstSpace TO " ".}

	// Nothing was added if every part is zero, either because the time is zero or because it is too small to show at the
	// requested number of digits (the parts are cut off, not rounded). Show a zero in the smallest unit that is displayed, instead
	// of an empty string. The minus sign stays, so a small negative time shows as "-0s".
	IF firstSpace = "" {
		LOCAL zeroUnit IS "d".
		IF digits > -1 SET zeroUnit TO "s".
		ELSE IF digits > -2 SET zeroUnit TO "m".
		ELSE IF digits > -3 SET zeroUnit TO "h".
		SET message TO message + "0" + zeroUnit.
	}

	RETURN message.
}

// given a number, returns a string of the number broken down to Tm, Gm, Mm, km, meters or millimeters.
// example: given 90090.124 (meters), and 1 decimal place, the function will return "90.1 km"
FUNCTION distanceToString
{
	PARAMETER dist IS 0.
	PARAMETER digits IS 0.
	IF digits < 0 SET digits TO 0.

	IF dist:TYPENAME <> "scalar" {
		CLEARSCREEN.
		PRINT "distanceToString passed a " + dist:TYPENAME + " instead of a scalar for dist".
		PRINT 1/0.
	}

	IF digits:TYPENAME <> "scalar" {
		CLEARSCREEN.
		PRINT "distanceToString passed a " + digits:TYPENAME + " instead of a scalar for digits".
		PRINT 1/0.
	}

	LOCAL isNegative IS FALSE.
	LOCAL message IS "".
	IF dist < 0 {
		SET isNegative TO TRUE.
		SET dist TO ABS(dist).
	}

	IF dist < 1			        SET message TO ROUND(dist / 0.001        , digits) + " mm".
	IF dist >= 1            SET message TO ROUND(dist / 1            , digits) + " m".
	IF dist > 1000          SET message TO ROUND(dist / 1000         , digits) + " km".
	IF dist > 1000000       SET message TO ROUND(dist / 1000000      , digits) + " Mm".
	IF dist > 1000000000    SET message TO ROUND(dist / 1000000000   , digits) + " Gm".
	IF dist > 1000000000000 SET message TO ROUND(dist / 1000000000000, digits) + " Tm".
	IF isNegative SET message TO "-" + message.
	RETURN message.
}

// prints the parameters of the passed PID to the terminal, starting at the given coordinates
FUNCTION printPID
{
	PARAMETER PID.
	PARAMETER PIDName IS "".
	PARAMETER Xcoord IS 0.
	PARAMETER Ycoord IS 0.
	PARAMETER roundDigits IS 4.
	PRINT PIDName AT(Xcoord, Ycoord + 0).
	PRINT "CV " + ROUND(PID:OUTPUT, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 1).
	PRINT "PV " + ROUND(PID:INPUT, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 2).
	PRINT "SP " + ROUND(PID:SETPOINT, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 3).
	PRINT "Error " + ROUND(PID:ERROR, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 4).
	PRINT "Error Sum " + ROUND(PID:ERRORSUM, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 5).
	PRINT "ChangeRate " + ROUND(PID:CHANGERATE, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 6).
	PRINT "KP " + ROUND(PID:KP, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 7).
	PRINT "KI " + ROUND(PID:KI, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 8).
	PRINT "KD " + ROUND(PID:KD, roundDigits) + " ":PADLEFT(roundDigits + 2) AT(Xcoord, Ycoord + 9).
	PRINT "Min/Max Output: " + PID:MINOUTPUT + " / " + PID:MAXOUTPUT + "       " AT(Xcoord, Ycoord + 10).
	RETURN 0.
}

// prints the parameters of the passed orbit to the terminal, starting at the given coordinates
FUNCTION printOrbit
{
	PARAMETER orb.
	PARAMETER orbName.// IS orb:NAME.
	PARAMETER Xcoord.// IS 0.
	PARAMETER Ycoord.// IS 0.
	PRINT orbName AT(Xcoord, Ycoord + 0).
	PRINT "Apoapsis " + ROUND(orb:APOAPSIS, 2) + " m   " AT(Xcoord, Ycoord + 1).
	PRINT "Periapsis " + ROUND(orb:PERIAPSIS, 2) + " m  " AT(Xcoord, Ycoord + 2).
	IF orb:ECCENTRICITY < 1.0 PRINT "Period " + timeToString(orb:PERIOD) + "    " AT(Xcoord, Ycoord + 3).
	ELSE PRINT "Period not defined    " AT(Xcoord, Ycoord + 3).
	PRINT "Inclination " + ROUND(orb:INCLINATION, 4) + " degrees   " AT(Xcoord, Ycoord + 4).
	PRINT "Eccentricity " + ROUND(orb:ECCENTRICITY, 4) + "   " AT(Xcoord, Ycoord + 5).
	PRINT "Semi-Major Axis " + ROUND(orb:SEMIMAJORAXIS, 2) + "  " AT(Xcoord, Ycoord + 6).
	PRINT "Longitude of Ascending Node " + ROUND(orb:LAN, 4) + "   " AT(Xcoord, Ycoord + 7).
	PRINT "Argument of Periapsis " + ROUND(orb:ARGUMENTOFPERIAPSIS, 4) + "     " AT(Xcoord, Ycoord + 8).
}

// Log the list of orbits passed to the passed file name.
//	orbs - orbit (or list of orbits) that should be logged
//	fileName - file name that the orbits should be logged to
FUNCTION logOrbit
{
	PARAMETER orbs.
	PARAMETER fileName.
	// if passed only a single orbit, add it as a single element list.
	IF orbs:TYPENAME <> "LIST" SET orbs TO LIST(orbs).
	LOCAL message IS "".

	SET message TO "Name,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:NAME + ",".}
	SET message TO message + "".
	LOG message TO fileName.

	SET message TO "Apoapsis,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:APOAPSIS + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Periapsis,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:PERIAPSIS + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Orbited Body,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:BODY:NAME + ",".}
	SET message TO message + "".
	LOG message TO fileName.

	SET message TO "Orbited Body MU,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:BODY:MU + ",".}
	SET message TO message + "m^3/s^2".
	LOG message TO fileName.

	SET message TO "Orbited Body Radius,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:BODY:Radius + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Orbited Body SOI Radius,".
	FOR eachOrbit IN orbs {
		IF eachOrbit:BODY:HASBODY SET message TO message + eachOrbit:BODY:SOIRADIUS + ",".
		ELSE SET message TO message + "infinite,".
	}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Period,".
	FOR eachOrbit IN orbs {
		IF eachOrbit:SEMIMAJORAXIS < 0 SET message TO message + "Undefined,".
		ELSE SET message TO message + eachOrbit:PERIOD + ",".
	}
	SET message TO message + "s".
	LOG message TO fileName.

	SET message TO "Inclination,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:INCLINATION + ",".}
	SET message TO message + "deg".
	LOG message TO fileName.

	SET message TO "Inclination,".
	FOR eachOrbit IN orbs {SET message TO message + (CONSTANT:DegToRad * eachOrbit:INCLINATION) + ",".}
	SET message TO message + "rad".
	LOG message TO fileName.

	SET message TO "Eccentricity,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:ECCENTRICITY + ",".}
	SET message TO message + "".
	LOG message TO fileName.

	SET message TO "Semi-Major Axis,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:SEMIMAJORAXIS + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Semi-Minor Axis,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:SEMIMINORAXIS + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Longitude of Ascending Node,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:LAN + ",".}
	SET message TO message + "deg".
	LOG message TO fileName.

	SET message TO "Longitude of Ascending Node,".
	FOR eachOrbit IN orbs {SET message TO message + (CONSTANT:DegToRad * eachOrbit:LAN) + ",".}
	SET message TO message + "rad".
	LOG message TO fileName.

	SET message TO "Argument of Periapsis,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:ARGUMENTOFPERIAPSIS + ",".}
	SET message TO message + "deg".
	LOG message TO fileName.

	SET message TO "Argument of Periapsis,".
	FOR eachOrbit IN orbs {SET message TO message + (CONSTANT:DegToRad * eachOrbit:ARGUMENTOFPERIAPSIS) + ",".}
	SET message TO message + "rad".
	LOG message TO fileName.

	SET message TO "True Anomaly,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:TRUEANOMALY + ",".}
	SET message TO message + "deg".
	LOG message TO fileName.

	SET message TO "True Anomaly,".
	FOR eachOrbit IN orbs {SET message TO message + (CONSTANT:DegToRad * eachOrbit:TRUEANOMALY) + ",".}
	SET message TO message + "rad".
	LOG message TO fileName.

	SET message TO "Mean Anomaly at Epoch,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:MEANANOMALYATEPOCH + ",".}
	SET message TO message + "deg".
	LOG message TO fileName.

	SET message TO "Mean Anomaly at Epoch,".
	FOR eachOrbit IN orbs {SET message TO message + (CONSTANT:DegToRad * eachOrbit:MEANANOMALYATEPOCH) + ",".}
	SET message TO message + "rad".
	LOG message TO fileName.

	SET message TO "Epoch,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:EPOCH + ",".}
	SET message TO message + "s".
	LOG message TO fileName.

	SET message TO "Current UT,".
	FOR eachOrbit IN orbs {SET message TO message + TIME:SECONDS + ",".}
	SET message TO message + "s".
	LOG message TO fileName.

	SET message TO "Transition,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:TRANSITION + ",".}
	SET message TO message + "".
	LOG message TO fileName.

	SET message TO "Position (r),".
	FOR eachOrbit IN orbs {SET message TO message + (eachOrbit:POSITION - eachOrbit:BODY:POSITION):MAG + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Velocity (v),".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:VELOCITY:ORBIT:MAG + ",".}
	SET message TO message + "m/s".
	LOG message TO fileName.

	SET message TO "Has Next Patch,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:HASNEXTPATCH + ",".}
	SET message TO message + "".
	LOG message TO fileName.

	SET message TO "Next Patch ETA,".
	FOR eachOrbit IN orbs {
		IF eachOrbit:HASNEXTPATCH {
		  SET message TO message + eachOrbit:NEXTPATCHETA + ",".
		} ELSE SET message TO message + "N/A,".
	}
	SET message TO message + "s".
	LOG message TO fileName.

	SET message TO "Position X,".
	FOR eachOrbit IN orbs {SET message TO message + (eachOrbit:POSITION - eachOrbit:BODY:POSITION):X + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Position Y,".
	FOR eachOrbit IN orbs {SET message TO message + (eachOrbit:POSITION - eachOrbit:BODY:POSITION):Y + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Position Z,".
	FOR eachOrbit IN orbs {SET message TO message + (eachOrbit:POSITION - eachOrbit:BODY:POSITION):Z + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Velocity X,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:VELOCITY:ORBIT:X + ",".}
	SET message TO message + "m/s".
	LOG message TO fileName.

	SET message TO "Velocity Y,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:VELOCITY:ORBIT:Y + ",".}
	SET message TO message + "m/s".
	LOG message TO fileName.

	SET message TO "Velocity Z,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:VELOCITY:ORBIT:Z + ",".}
	SET message TO message + "m/s".
	LOG message TO fileName.

	// Add a blank line to the end - it helps to differentiate between runs
	LOG "" TO fileName.
}

// get desired launch azimuth given desired circular orbit altitude and inclination
FUNCTION desiredAzimuth
{
	PARAMETER targetAltitude.
	PARAMETER targetInclination.	// signed: a negative value means launch to the south (descending-node ascent)

	LOCAL launchNorth IS targetInclination >= 0.
	LOCAL inc IS ABS(targetInclination).
	LOCAL lat IS SHIP:LATITUDE.
	LOCAL targetFinalVelocity IS SQRT(SHIP:BODY:MU / (SHIP:BODY:RADIUS + targetAltitude)).

	// Inertial azimuth. A ratio beyond +/-1 means the inclination is below the site latitude, so clamp to due east/west.
	LOCAL inertialAzimuth IS ARCSIN(MAX(-1, MIN(1, COS(inc) / COS(lat)))).
	IF NOT launchNorth SET inertialAzimuth TO 180 - inertialAzimuth.

	// Speed the pad is already moving east because of the body's rotation.
	LOCAL rotationSpeed IS 2 * CONSTANT:PI * (SHIP:BODY:RADIUS + ALTITUDE) * COS(lat) / SHIP:BODY:ROTATIONPERIOD.

	LOCAL desiredEastVelocity IS targetFinalVelocity * SIN(inertialAzimuth) - rotationSpeed.
	LOCAL desiredNorthVelocity IS targetFinalVelocity * COS(inertialAzimuth).
	RETURN normalizeAngle360(ARCTAN2(desiredEastVelocity, desiredNorthVelocity)).
}

// global list of initialized PID logs.
GLOBAL initPIDLog IS LEXICON().

FUNCTION logPID
{
	PARAMETER PID.
	PARAMETER filename IS "0:logFileName.txt".
	PARAMETER detailed IS TRUE.
	LOCAL recordsToArchive IS filename:SUBSTRING(0, 1) = "0".
	IF NOT recordsToArchive OR (recordsToArchive AND connectionToKSC()) {
		IF (initPIDLog:KEYS:EMPTY OR NOT initPIDLog:KEYS:CONTAINS(filename))
		{
			// The connection can be lost after the check at the top of this function (building a row takes several ticks, and time warp can change the
			// connection), and writing to the archive without one stops the script, so check again just before each write.
			IF recordsToArchive AND NOT connectionToKSC() { RETURN. }
			IF EXISTS(filename) DELETEPATH(filename).
			IF recordsToArchive AND NOT connectionToKSC() { RETURN. }
			IF detailed	{LOG "Timestamp,Last Sample Time,Input,Setpoint,Error,Output,P Term,I Term,D Term,Kp,Ki,Kd,Max Output,Min Output,Change Rate,Error Sum" TO filename. }
			ELSE {LOG "Timestamp,Input,Setpoint,Error,Output" TO filename.}
			initPIDLog:ADD(filename, TIME:SECONDS).
		}
		LOCAL rowData IS "".
		IF detailed {SET rowData TO (TIME:SECONDS - initPIDLog[filename]) + "," + PID:LastSampleTime + "," + PID:Input + "," + PID:Setpoint + "," + PID:Error + "," + PID:Output + "," + PID:PTerm + "," + PID:ITerm + "," + PID:DTerm + "," + PID:Kp + "," + PID:KI + "," + PID:Kd + "," + PID:MAXOUTPUT + "," + PID:MINOUTPUT + "," + PID:CHANGERATE + "," + PID:ERRORSUM.}
		ELSE {SET rowData TO (TIME:SECONDS - initPIDLog[filename]) + "," + PID:Input + "," + PID:Setpoint + "," + PID:Error + "," + PID:Output.}
		IF recordsToArchive AND NOT connectionToKSC() { RETURN. }
		LOG rowData TO filename.
	}
}

// Global list of initialized multiple PID logs.
GLOBAL initPIDLogMultiple IS LEXICON().

FUNCTION logPIDMultiple
{
	PARAMETER PIDLexicon.
	PARAMETER filename IS "0:logFileName.txt".
	PARAMETER detailed IS TRUE.
	PARAMETER additionalData IS LEXICON().
	LOCAL useAdditional IS additionalData:LENGTH = 3 AND additionalData:KEYS:CONTAINS("rowData") AND additionalData:KEYS:CONTAINS("labelRow") AND additionalData:KEYS:CONTAINS("valueRow").
	LOCAL recordsToArchive IS filename:SUBSTRING(0, 1) = "0".
	IF NOT recordsToArchive OR (recordsToArchive AND connectionToKSC()) {
		IF (initPIDLogMultiple:KEYS:EMPTY OR NOT initPIDLogMultiple:KEYS:CONTAINS(filename))
		{
			// The connection can be lost after the check at the top of this function (building a row takes several ticks, and time warp can change the
			// connection), and writing to the archive without one stops the script, so check again just before each write.
			IF recordsToArchive AND NOT connectionToKSC() { RETURN. }
			IF EXISTS(filename) DELETEPATH(filename).
			LOCAL labelRow IS "Time,".
			LOCAL valueRow IS "Stamp,".
			FOR eachPID IN PIDLexicon:KEYS {
				FOR eachNumber IN RANGE(0, 4) SET labelRow TO labelRow + eachPID + ",".
				SET valueRow TO valueRow + "Input,Setpoint,Error,Output,".
				IF detailed	{
					FOR eachNumber IN RANGE(0, 10) SET labelRow TO labelRow + eachPID + ",".
					SET valueRow TO valueRow + "P Term,I Term,D Term,Kp,Ki,Kd,Max Output,Min Output,Change Rate,Error Sum,".
				}
			}
			IF useAdditional {
				SET labelRow TO labelRow + additionalData["LabelRow"].
				SET valueRow TO valueRow + additionalData["valueRow"].
			}
			IF recordsToArchive AND NOT connectionToKSC() { RETURN. }
			LOG labelRow TO fileName.
			LOG valueRow TO fileName.
			initPIDLogMultiple:ADD(filename, TIME:SECONDS).
		}
		LOCAL rowData IS (TIME:SECONDS - initPIDLogMultiple[filename]) + ",".
		FOR eachPID in PIDLexicon:KEYS {
			SET rowData TO rowData + PIDLexicon[eachPID]:Input + "," + PIDLexicon[eachPID]:Setpoint + "," + PIDLexicon[eachPID]:Error + "," + PIDLexicon[eachPID]:Output + ",".
			IF detailed {
				SET rowData TO rowData + PIDLexicon[eachPID]:PTerm + "," + PIDLexicon[eachPID]:ITerm + "," + PIDLexicon[eachPID]:DTerm + "," + PIDLexicon[eachPID]:Kp + "," + PIDLexicon[eachPID]:KI + "," + PIDLexicon[eachPID]:Kd + "," + PIDLexicon[eachPID]:MAXOUTPUT + "," + PIDLexicon[eachPID]:MINOUTPUT + "," + PIDLexicon[eachPID]:CHANGERATE + "," + PIDLexicon[eachPID]:ERRORSUM + ",".
			}
		}
		IF useAdditional SET rowData TO rowData + additionalData["rowData"].
		IF recordsToArchive AND NOT connectionToKSC() { RETURN. }
		LOG rowData TO filename.
	}
}

// function that returns a value given the weights for a polynomial in the form of a + b*x + c*x^2 + d*x^3 + e*x^4 + ...
// passed an input (scalar) and a list of term weights (list)
// returns a scalar
FUNCTION evaluatePolynomial
{
	PARAMETER input.
	PARAMETER weightList.
	IF weightList:LENGTH < 1 RETURN 0.
	LOCAL total IS 0.
	FROM {LOCAL index IS 0.}
	UNTIL index = weightList:LENGTH
	STEP {SET index TO index + 1.}
	DO {
		SET total TO total + weightList[weightList:LENGTH - 1 - index] * input ^ (weightList:LENGTH - 1 - index).
	}
	return total.
}

// Warp To Value
// This function timewarps until the passed delegate returns a value that is less than the targetValue.
// This function keeps track of the rate of change of the value, and varies the warp speed to maintain
// 10 seconds or less of realtime remaining for each warp speed.
// Note that the delegate passed must return a scalar, but can do other things as well.
// Passed the following:
//			delegate to function returning a scalar (delegate)
//			target value (scalar)
//			maximum allowed warp rate (scalar)
// Returns the following:
//			time that was warped through (scalar, seconds)
FUNCTION warpToValue
{
	PARAMETER delegate.
	PARAMETER targetValue IS 0.
	PARAMETER maxWarpRate IS 1000.

	SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

	LOCAL startTime IS TIME:SECONDS.
	LOCAL newValue IS delegate().
	LOCAL newTime IS TIME:SECONDS.
	LOCAL oldValue IS newValue.
	LOCAL oldTime IS newTime.

	LOCAL delegateRate IS 1.
	LOCAL realTimeLeft IS 10.
	LOCAL firstTime IS TRUE.
//	LOG "Time,Old Time,New Value,Old Value,Delegate Rate,Real Time Left" TO "Warping.csv".

	// continue waiting until there is five seconds or less of real time remaining, or the delegate is less than the target value
	UNTIL ((realTimeLeft < 5) AND (KUNIVERSE:TIMEWARP:RATE = 1)) AND newTime > startTime + 10 {
		// if the rate is still changing, do nothing
		IF KUNIVERSE:TIMEWARP:ISSETTLED {
			IF NOT firstTime {
				SET newTime TO TIME:SECONDS.
				SET newValue TO delegate().
				// calculate the rate in terms of units per in-game second
				IF (oldTime <> newTime) SET delegateRate TO (newValue - oldValue)/(newTime - oldTime).

				// calculate how long it will take to get to the target value in real-world seconds
				IF (delegateRate <> 0) SET realTimeLeft TO (targetValue - newValue) / (delegateRate * KUNIVERSE:TIMEWARP:RATE).
			}

			// warp slower, if not at min rate
			IF (realTimeLeft < 2) AND (KUNIVERSE:TIMEWARP:RATE <> 1) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
			}

			// warp faster, if not at max rate - this assumes that the next rate is 10x faster than the current rate
			IF (realTimeLeft > 15) AND (KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) AND (KUNIVERSE:TIMEWARP:RATE <> maxWarpRate) {
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
			}

//			LOG newTime + "," + oldTime + "," + newValue + "," + oldValue + "," + delegateRate + "," + realTimeLeft TO "Warping.csv".

			// update the old values used in the rate calculations
			SET oldValue TO newValue.
			SET oldTime TO newTime.
			// if this is the first scan of this logic, reset the flag
			IF firstTime SET firstTime TO FALSE.
			WAIT 0.
		}
		// if the debug flag is active, print everything to the terminal
		IF (debug) {
			PRINT "Delegate Rate " + ROUND(delegateRate, 5) + "         " AT (0, 20).
			PRINT "Real Time Left " + ROUND(realTimeLeft, 2) + "         " AT (0, 21).
			PRINT "Real Time Rate " + ROUND(KUNIVERSE:TIMEWARP:RATE, 2) + "         " AT (0, 22).
			PRINT "Delegate " + ROUND(newValue,2) + "       " AT (0, 23).
		}
		WAIT 0.
	}

	SET KUNIVERSE:timewarp:warp TO 0.
	RETURN TIME:SECONDS - startTime.
}

// Warp To Value Physics
// This function timewarps until the passed delegate returns a value that is less than the targetValue.
// This function goes to the maximum physics warp rate (x4) and maintains that until the delegate returns less than targetValue.
// Note that the delegate passed must return a scalar, but can do other things as well.
// Note also that this function does not affect the ship directly at all. Delegate should be set to return a physical value
//		that will change over time. Example: delegate returns angle between FORE and direction steering is locked to.
// Passed the following:
//			delegate to function returning a scalar (delegate)
//			target value (scalar, unitless)
// Returns the following:
//			time that was warped through (scalar, seconds)
FUNCTION warpToValuePhysics
{
	PARAMETER delegate.
	PARAMETER targetValue IS 0.1.

	LOCAL firstTime IS TRUE.
	LOCAL startTime IS TIME:SECONDS.
	LOCAL oldMode IS KUNIVERSE:TIMEWARP:MODE.

	// continue waiting until the delegate returns less than targetValue
	UNTIL (delegate() < targetValue) {
		// if the rate is still changing, do nothing
		IF KUNIVERSE:TIMEWARP:ISSETTLED {
			IF NOT firstTime {
				// set the warp rate to the maximum possible for the physical warp
				SET KUNIVERSE:TIMEWARP:MODE TO "PHYSICS".
				SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:PHYSICSRATELIST:LENGTH - 1.
			}
			IF firstTime SET firstTime TO FALSE.
		}
		// if the debug flag is active, print everything to the terminal
//		IF (debug) {
			PRINT "Delegate " + ROUND(delegate(),2) + "       " AT (0, 20).
//		}
		WAIT 0.
	}

	SET KUNIVERSE:TIMEWARP:MODE TO oldMode.
	SET KUNIVERSE:TIMEWARP:warp TO 0.
	RETURN TIME:SECONDS - startTime.
}

// Abort
// A manual abort for long scripts. A script calls resetAbort() when it starts, and then asks abortKeyPressed() wherever it waits or loops
// (WAIT UNTIL condition OR abortKeyPressed(), the loop of a burn, warpToTime and the solvers, which take it as a delegate: abortKeyPressed@).
// Nothing runs in the background, so the key is only noticed where the script asks.
// The key is the End key (abortKey), not Enter, which runs scripts from the loop terminal. It is not Escape: a terminal that has focus
// captures it (the game does not pause), but kOS does not deliver it as a character (testAbort.ks showed that). All the keys that were typed since the last call are read and thrown
// away, so that they do not run commands in the loop terminal after the script ends.
// abortRequested is TRUE once the key was pressed and stays TRUE until the next resetAbort(), so every later check agrees, and a script
// that ran this one can look at it after it returns.
GLOBAL abortRequested IS FALSE.
GLOBAL abortKey IS TERMINAL:INPUT:ENDCURSOR.
GLOBAL abortNote IS "".												// why a script set abortRequested itself, for stopReason ("" if it did not)

// Clears the abort request.
FUNCTION resetAbort {
	SET abortRequested TO FALSE.
	SET abortNote TO "".
}

// Returns TRUE if the abort key has been pressed (see above), FALSE if not. It is generic: it knows nothing about what the script that
// calls it is doing, so any script can use it. A script that has other reasons to stop sets abortRequested itself (as Exec does when
// its maneuver node is gone) and then every later check agrees.
FUNCTION abortKeyPressed {
	UNTIL NOT TERMINAL:INPUT:HASCHAR {
		IF TERMINAL:INPUT:GETCHAR() = abortKey SET abortRequested TO TRUE.
	}
	RETURN abortRequested.
}

// Maneuver-node execution helpers (Exec.ks). They are here and not in Exec.ks because kOS keeps the code of a script that was run, and a
// FUNCTION or LOCK defined in a script that is loaded a second time (ExecRCS runs Exec under another name) is a label that already exists,
// which freezes the game. Exec.ks therefore defines no named labels of its own.
// The kind of burn: TRUE for an RCS burn, where the thrust is the forward translation control of the ship and the main throttle stays 0.
GLOBAL burnWithRCS IS FALSE.
GLOBAL burnLevel IS 0.												// the level that setBurnThrottle last set (0 to 1), for the logs

// Sets the level of the burn (0 to 1): the throttle of the main engines, or, for an RCS burn, the forward translation control.
FUNCTION setBurnThrottle {
	PARAMETER level.
	SET burnLevel TO level.
	IF burnWithRCS SET SHIP:CONTROL:FORE TO level.
	ELSE SET globalThrottle TO level.
}

// Whether a maneuver-node script has to stop now: the abort key was pressed (abortKeyPressed, which knows nothing about nodes), or the
// maneuver node is gone. A missing node sets the shared abort request, so that everything that is skipped after the abort key is skipped
// for it too, and stopReason says which it was.
FUNCTION executeStop {
	IF NOT HASNODE SET abortRequested TO TRUE.
	RETURN abortKeyPressed().
}

// What a stop was for (string)
FUNCTION stopReason {
	IF abortNote <> "" RETURN abortNote.
	IF NOT HASNODE RETURN "the maneuver node was removed".
	RETURN "aborted by the operator".
}

// For the solver, which takes a function that returns whether to stop: also takes a sample of the rotation if one is due
FUNCTION executeStopOrSample {
	sampleRotation().
	RETURN executeStop().
}

// Safe Node Reads
// NEXTNODE:ETA and NEXTNODE:DELTAV fail when there is no maneuver node, with an error that kOS cannot catch, and the script stops with
// whatever it was doing (the throttle where it was). A script that waits for a node or burns it reads the node all the time, and the node
// can be deleted in the meantime. These read it only if it is there, and give the fallback if it is not. Nothing is remembered about the
// node: it is read from the game each time, so a node that was moved or edited is not noticed, and what is read is what it is now.
// The script decides what the fallback must be (for a time: a time that never comes, so that nothing waits for it to arrive and then
// acts as if the node had; for the delta V: zero, so that a burn finds that nothing is left) and checks HASNODE where it matters.
// Passed the following:
//			fallback (scalar, s, the default 1E9; or vector, the default V(0, 0, 0))
// Returns the time to the next node (s), or the delta V that is left of it (vector, raw), or the fallback
FUNCTION nodeETA {
	PARAMETER fallback IS 1E9.
	IF HASNODE RETURN NEXTNODE:ETA.
	RETURN fallback.
}

FUNCTION nodeDeltaV {
	PARAMETER fallback IS V(0, 0, 0).
	IF HASNODE RETURN NEXTNODE:DELTAV.
	RETURN fallback.
}
// Ullage Fuel Check
// Whether the RCS can fire forward for the ullage of the burn: a thruster that can, and enough propellant for it, which is the thrust
// over the Isp and g0, for the ullage time, with a margin of 50%. The propellant and the Isp are the current stage's (shipInfo, from
// updateShipInfo), the thrust is that of every enabled RCS thruster that fires forward (getRCSThrusts). Not tested in flight.
// Passed the following:
//			ullage time (scalar, s)
// Returns a lexicon of "Message" ("None" if the ullage can be done, otherwise what is wrong, a string), "Thrust" (N, forward),
//		"Needed" (kg, with the margin) and "Have" (kg)
FUNCTION ullageFuelCheck {
	PARAMETER ullageTime.
	LOCAL foreThrust IS getRCSThrusts():X.
	LOCAL rcsIsp IS shipInfo["CurrentStage"]["IspRCS"].
	LOCAL fuelHave IS shipInfo["CurrentStage"]["fuelRCSMass"].
	LOCAL fuelNeeded IS 0.
	IF foreThrust > 0 AND rcsIsp > 0 SET fuelNeeded TO 1.5 * foreThrust / (rcsIsp * 9.80665) * ullageTime.
	LOCAL message IS "None".
	IF foreThrust <= 0 SET message TO "no RCS thruster can fire forward for the ullage".
	ELSE IF rcsIsp <= 0 SET message TO "the RCS has no propellant data for the ullage".
	ELSE IF fuelHave < fuelNeeded SET message TO "the RCS has " + ROUND(fuelHave, 2) + " kg of propellant and the ullage needs about " + ROUND(fuelNeeded, 2) + " kg".
	RETURN LEXICON("Message", message, "Thrust", foreThrust, "Needed", fuelNeeded, "Have", fuelHave).
}

// RCS Burn Stage
// The plan of a burn with the RCS thrusters instead of the main engines (Exec with its useRCSforThrust parameter): one stage in the form
// that Exec's planner and the burn solver read (the keys of a shipInfo stage that they use). The thrusters are the enabled ones that fire
// forward, their thrust and mass flow are those of engineStatsRCS for them (the thrust is each thruster's own, not its component along the
// ship's axis, so a ring of angled thrusters is overstated), the mass is the ship's, and the propellant is the current stage's RCS
// propellant (shipInfo, from updateShipInfo). The delta V it can deliver is Isp * g0 * ln(mass / mass without that propellant).
// Not tested in flight.
// Passed the following:
//			delta V required (scalar, m/s; 0 to skip the check of the delta V)
// Returns a lexicon of "Stage" (a lexicon of "Isp" (s), "Thrust" (N), "mDot" (kg/s), "CurrentMass" (kg), "FuelMass" (kg), "DeltaV" (m/s),
//		"DeltaVPrev" (0), "Number" (0), "Throttleable" (TRUE), "HighestMinThrottle" (0), "Engines" (the thrusters) and "EngineData" (empty))
//		and "Error" ("None" if the burn can be done, otherwise the reason, a string; the delta V needs a margin of 5%)
FUNCTION rcsBurnStage {
	PARAMETER deltaVRequired IS 0.
	LOCAL allRCS IS LIST().
	LIST RCS IN allRCS.
	LOCAL foreRCS IS LIST().
	FOR eachRCS IN allRCS {
		IF eachRCS:ENABLED AND eachRCS:FOREENABLED foreRCS:ADD(eachRCS).
	}
	LOCAL stats IS engineStatsRCS(foreRCS).
	LOCAL massNow IS SHIP:MASS * 1000.
	LOCAL fuelMass IS shipInfo["CurrentStage"]["fuelRCSMass"].
	LOCAL dryMass IS massNow - fuelMass.
	LOCAL deltaVAvailable IS 0.
	IF stats["Isp"] > 0 AND dryMass > 0 AND fuelMass > 0 SET deltaVAvailable TO stats["Isp"] * 9.80665 * LN(massNow / dryMass).
	LOCAL message IS "None".
	IF foreRCS:LENGTH = 0 SET message TO "Ship has no RCS thrusters that fire forward!".
	ELSE IF stats["thrustMax"] <= 0 SET message TO "The RCS thrust forward is zero!".
	ELSE IF stats["Isp"] <= 0 SET message TO "RCS Isp is zero!".
	ELSE IF fuelMass <= 0 SET message TO "The ship has no RCS propellant!".
	ELSE IF deltaVAvailable < 1.05 * deltaVRequired SET message TO "Not enough RCS delta V! Need " + ROUND(deltaVRequired, 1) + " m/s (with a margin of 5%) and the RCS has " + ROUND(deltaVAvailable, 1) + " m/s.".
	LOCAL burnStage IS LEXICON("Isp", stats["Isp"], "Thrust", stats["thrustMax"], "mDot", stats["mDotMax"], "CurrentMass", massNow, "FuelMass", fuelMass,
								"DeltaV", deltaVAvailable, "DeltaVPrev", 0, "Number", 0, "Throttleable", TRUE, "HighestMinThrottle", 0,
								"Engines", foreRCS, "EngineData", LIST()).
	RETURN LEXICON("Stage", burnStage, "Error", message).
}

// The delegate for functions that can be aborted when the caller does not want that. It always returns FALSE.
FUNCTION neverAbort {
	RETURN FALSE.
}

// Rotation Monitor
// Watches how the ship rotates while a script waits for it to point at a target direction, and says whether it has settled. It keeps a history
// of the pointing error and of the pitch and yaw rate, and can write a log (a line every logInterval s) to see why a ship does not settle.
// sampleRotation does the work, and takes a sample only when one is due, so it can be called as often as the caller likes: every pass of a
// wait loop, and from the solver (abortOrSample is a delegate for the solver that does both), which blocks the script for a minute.
// The rotation rate that matters for pointing is the pitch and yaw rate, the rotation with the part about the facing axis removed. A roll about
// that axis does not move the facing direction, and a flown ship rolled steadily at 0.003 rad/s that the steering never removed (the steering
// lets the roll follow when it is given a vector), which made the total rate useless as a test for being settled.
// A ship with little control authority oscillates slowly about the target (a flown one: 0.5 degrees either side with a period of 18 s), and its
// rate is zero twice per cycle, so one reading says nothing: rotationSettled looks at the highest rate and the largest error over a window.
GLOBAL rotationMonitor IS LEXICON("On", FALSE).

// Starts the monitor. Passed the following:
//			target vector (vector, the direction to point at, raw; the burn vector does not move, so one reading of it is enough)
//			node UT (scalar, UT in s, for the time to the node in the log)
//			turn start UT (scalar, UT in s, when the turn started, for the log)
//			log file (string, "" for no log file)
//			aligned error (scalar, deg, the pointing error that counts as aligned, for the time that the ship was first aligned)
//			log interval (scalar, s) and history interval (scalar, s, between the samples of the history; 0.5 s)
FUNCTION startRotationMonitor {
	PARAMETER targetVector.
	PARAMETER nodeUT.
	PARAMETER turnStartUT.
	PARAMETER logFileName IS "".
	PARAMETER alignedError IS 1.
	PARAMETER logInterval IS 2.
	PARAMETER historyInterval IS 0.5.

	SET rotationMonitor TO LEXICON("On", TRUE, "Target", targetVector, "NodeUT", nodeUT, "TurnStart", turnStartUT, "File", logFileName,
		"AlignedError", alignedError, "LogInterval", logInterval, "HistoryInterval", historyInterval, "LastLog", -1E9, "LastHistory", -1E9,
		"FirstAligned", -1, "Times", LIST(), "Errors", LIST(), "Rates", LIST(), "Buffer", LIST(), "KeepTime", 60, "CheckedAt", -1, "Result", FALSE).
	IF logFileName <> "" {
		LOCAL buffer IS rotationMonitor["Buffer"].
		buffer:ADD("Alignment log," + SHIP:NAME).
		buffer:ADD("UT,since turn start,ETA,pointing error,steering angle error,steering roll error,rotation rate,roll rate,pitch and yaw rate,stopping time,warp rate,warp mode").
		buffer:ADD("s,s,s,deg,deg,deg,rad/s,rad/s,rad/s,s,,").
	}
}

// Takes a sample of the ship's rotation if one is due (see above). Passed: force (boolean, TRUE to take a log line now)
FUNCTION sampleRotation {
	PARAMETER force IS FALSE.
	IF NOT rotationMonitor["On"] RETURN.
	LOCAL nowUT IS TIME:SECONDS.
	LOCAL historyDue IS nowUT - rotationMonitor["LastHistory"] >= rotationMonitor["HistoryInterval"].
	LOCAL logDue IS rotationMonitor["File"] <> "" AND (force OR nowUT - rotationMonitor["LastLog"] >= rotationMonitor["LogInterval"]).
	IF NOT (historyDue OR logDue) RETURN.

	LOCAL pointError IS VANG(SHIP:FACING:VECTOR, rotationMonitor["Target"]).
	LOCAL turnRate IS VXCL(SHIP:FACING:FOREVECTOR, SHIP:ANGULARVEL):MAG.
	IF historyDue {
		rotationMonitor["Times"]:ADD(nowUT).
		rotationMonitor["Errors"]:ADD(pointError).
		rotationMonitor["Rates"]:ADD(turnRate).
		SET rotationMonitor["LastHistory"] TO nowUT.
		UNTIL rotationMonitor["Times"]:LENGTH < 2 OR rotationMonitor["Times"][0] >= nowUT - rotationMonitor["KeepTime"] {
			rotationMonitor["Times"]:REMOVE(0).
			rotationMonitor["Errors"]:REMOVE(0).
			rotationMonitor["Rates"]:REMOVE(0).
		}
		IF pointError < rotationMonitor["AlignedError"] AND rotationMonitor["FirstAligned"] < 0 SET rotationMonitor["FirstAligned"] TO nowUT.
	}
	IF logDue {
		LOCAL steerAngleError IS 0.
		LOCAL steerRollError IS 0.
		IF STEERINGMANAGER:ENABLED {
			SET steerAngleError TO STEERINGMANAGER:ANGLEERROR.
			SET steerRollError TO STEERINGMANAGER:ROLLERROR.
		}
		rotationMonitor["Buffer"]:ADD(ROUND(nowUT, 2) + "," + ROUND(nowUT - rotationMonitor["TurnStart"], 2) + "," + ROUND(rotationMonitor["NodeUT"] - nowUT, 2) + "," +
			ROUND(pointError, 4) + "," + ROUND(steerAngleError, 4) + "," + ROUND(steerRollError, 4) + "," + ROUND(SHIP:ANGULARVEL:MAG, 6) + "," +
			ROUND(VDOT(SHIP:ANGULARVEL, SHIP:FACING:FOREVECTOR), 6) + "," + ROUND(turnRate, 6) + "," + ROUND(STEERINGMANAGER:MAXSTOPPINGTIME, 2) + "," +
			KUNIVERSE:TIMEWARP:RATE + "," + KUNIVERSE:TIMEWARP:MODE).
		SET rotationMonitor["LastLog"] TO nowUT.
		burnLogFlush(rotationMonitor["File"], rotationMonitor["Buffer"]).
	}
}

// Whether the ship has been settled for a whole window: for the last window seconds, every sample of the history has a pitch and yaw rate
// of at most rateLimit and a pointing error of at most errorLimit. FALSE until the history covers the window (it is kept for 60 s).
// Passed the following:
//			window (scalar, s), rate limit (scalar, rad/s), error limit (scalar, deg)
FUNCTION rotationSettled {
	PARAMETER window.
	PARAMETER rateLimit.
	PARAMETER errorLimit.
	IF NOT rotationMonitor["On"] RETURN FALSE.
	IF rotationMonitor["CheckedAt"] = rotationMonitor["LastHistory"] RETURN rotationMonitor["Result"].		// nothing new since the last answer
	SET rotationMonitor["CheckedAt"] TO rotationMonitor["LastHistory"].
	SET rotationMonitor["Result"] TO FALSE.

	LOCAL times IS rotationMonitor["Times"].
	LOCAL errors IS rotationMonitor["Errors"].
	LOCAL rates IS rotationMonitor["Rates"].
	IF times:LENGTH < 2 RETURN FALSE.
	LOCAL lastTime IS times[times:LENGTH - 1].
	IF times[0] > lastTime - window + rotationMonitor["HistoryInterval"] RETURN FALSE.						// the history does not cover the window yet
	LOCAL settled IS TRUE.
	LOCAL index IS times:LENGTH - 1.
	UNTIL index < 0 {
		IF times[index] < lastTime - window BREAK.
		IF rates[index] > rateLimit OR errors[index] > errorLimit {
			SET settled TO FALSE.
			BREAK.
		}
		SET index TO index - 1.
	}
	SET rotationMonitor["Result"] TO settled.
	RETURN settled.
}

// Ends the monitor, after writing what is left of the log. Passed: nothing
FUNCTION stopRotationMonitor {
	IF NOT rotationMonitor["On"] RETURN.
	sampleRotation(TRUE).
	IF rotationMonitor["File"] <> "" burnLogFlush(rotationMonitor["File"], rotationMonitor["Buffer"], TRUE).
	SET rotationMonitor["On"] TO FALSE.
}

// For functions that take an abort delegate (the solver): takes a sample of the rotation if one is due, and returns whether the abort key
// was pressed, as abortKeyPressed does.
FUNCTION abortOrSample {
	sampleRotation().
	RETURN abortKeyPressed().
}

// Stop Warp Before
// Stops time warp early enough that the game is back at normal speed when a time arrives, such as an ignition. A script that is
// waiting for that time calls it every pass of its loop, so that a warp that was started by hand is ended by the script, not by the person.
// The warp on rails does not stop at once: the game keeps running at the warp rate while the rate comes down (50x took about a second to come
// down), so the lead is 15 s plus 0.6 s for each unit of the warp rate. Physics warp stops at once, and its lead is a parameter (10 s: a
// physics warp makes every pass of the script's loops longer, and a precise time needs short ones).
// Passed the following:
//			time left (scalar, s, until the time that the warp has to be over)
//			physics warp lead (scalar, s, default 10)
// Returns the following:
//			TRUE if it set the warp to 0 on this call
FUNCTION stopWarpBefore {
	PARAMETER timeLeft.
	PARAMETER physicsLead IS 10.
	IF KUNIVERSE:TIMEWARP:RATE > 1 {
		IF (KUNIVERSE:TIMEWARP:MODE = "RAILS" AND timeLeft <= 15 + 0.6 * KUNIVERSE:TIMEWARP:RATE) OR (KUNIVERSE:TIMEWARP:MODE = "PHYSICS" AND timeLeft <= physicsLead) {
			SET KUNIVERSE:TIMEWARP:WARP TO 0.
			RETURN TRUE.
		}
	}
	RETURN FALSE.
}

// Warp To Time
// This function timewarps until the system time is the targetTime.
// If there is an SOI change before the target time, the function will slow down for the SOI change.
// This function keeps track of the rate of change of the value, and varies the warp speed to maintain
// 10 seconds or less of realtime remaining for each warp speed.
// Passed the following:
//			target time (scalar, seconds from universe creation)
//			abort check (delegate, returns TRUE to stop warping now, such as abortKeyPressed@; the default never aborts)
//			recursion level (scalar, only used by the function itself)
// Returns the following:
//			in-game time that was warped through (scalar, seconds)
FUNCTION warpToTime
{
	PARAMETER targetTime.
	PARAMETER abortCheck IS neverAbort@.
	PARAMETER recursionLevel IS 0.

	IF recursionLevel > 5 RETURN 0.
	IF abortCheck:CALL() RETURN 0.

	LOCAL startTime IS TIME:SECONDS.
	LOCAL timeLeft IS (targetTime - TIME:SECONDS) / KUNIVERSE:TIMEWARP:RATE.

	SET KUNIVERSE:TIMEWARP:RATE TO 0.
	WAIT 0.1.
	SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

	// if there is an SOI change before the target time, jump to the SOI change.
	IF (SHIP:ORBIT:HASNEXTPATCH) AND ((targetTime - TIME:SECONDS) > ETA:TRANSITION) {
		LOCAL oldBody IS SHIP:BODY:NAME.
		warpToTime(TIME:SECONDS + SHIP:ORBIT:NEXTPATCHETA - 10, abortCheck, recursionLevel + 1).
		WAIT UNTIL SHIP:BODY:NAME <> oldBody OR abortCheck:CALL().
		IF NOT abortCheck:CALL() warpToTime(targetTime, abortCheck, recursionLevel + 1).
	}
	// if the target doesn't have any interruptions, warp to it.
	ELSE {
		LOCAL startPower IS 0.
		LOCAL RESLIST IS 0.
		LIST RESOURCES IN RESLIST.
		FOR RES IN RESLIST {
			IF RES:NAME = "ElectricCharge" SET startPower TO RES:AMOUNT/RES:CAPACITY.
		}
		LOCAL currentPower IS 1.
		// continue waiting until there is five seconds or less of real time remaining
		UNTIL ((timeLeft < 0.5) AND (KUNIVERSE:TIMEWARP:RATE = 1)) OR abortCheck:CALL() {
			LIST RESOURCES IN RESLIST.
			FOR RES IN RESLIST {
				IF RES:NAME = "ElectricCharge" SET currentPower TO RES:AMOUNT/RES:CAPACITY.
			}
			// if the rate is still changing, do nothing
			IF KUNIVERSE:TIMEWARP:ISSETTLED {
				// calculate how long it will take to get to the target value in real-world seconds
				SET timeLeft TO (targetTime - TIME:SECONDS) / (KUNIVERSE:TIMEWARP:RATE).

				// warp slower, if not at min rate
				IF (timeLeft < 1) AND (KUNIVERSE:TIMEWARP:RATE <> 1) {
					SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
				}

				// warp faster, if not at max rate - this assumes that the next rate is 10x faster than the current rate
				IF (timeLeft > 15) AND
				(KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) AND
				(currentPower > 0.2 * startPower) {
					SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
				}
			}
			WAIT 0.
		}
	}

	SET KUNIVERSE:timewarp:warp TO 0.
	RETURN TIME:SECONDS - startTime.
}

// Time to Longitude
// This function returns the UT time it will take to rotate to a specific longitude.
// It assumes that the ship is not in motion relative to the body it is on.
// This function is meant to be used in conjunction with the warpToTime function.
// Passed the following:
//			desired longitude (scalar, degrees)
// Returns the following:
//			UT time at which the rocket will be at that longitude (scalar, UT seconds)
FUNCTION timeToLongitude
{
	PARAMETER desiredLongitude.
	RETURN TIME:SECONDS + normalizeAngle360(SHIP:GEOPOSITION:LNG - desiredLongitude) / 360 * SHIP:BODY:ROTATIONPERIOD.
}

// Returns time in seconds to the next time SHIP crosses the input altitude or -1 if input altitude is never crossed.
// Works for both kinds of orbit:
//		elliptical - the ship crosses an altitude between the periapsis and apoapsis twice per orbit.
//		hyperbolic (eccentricity of 1 or more) - the ship crosses an altitude above the periapsis once on the way in and
//			once on the way out. The time of each is its hyperbolic mean anomaly (see trueToMeanAnomaly) over the hyperbolic
//			mean motion, measured from periapsis and negative on the way in. The nearer one that is still ahead is used.
// Either way, once the time is known it is compared with the time of the next sphere of influence change. If the crossing
// would be after that, the ship is on a different orbit by then and does not cross the altitude, so the result is -1.
// Passed the following:
//			desiredAltitude (scalar, meters above sea level)
// Returns the following:
//			time from now in seconds (scalar), or -1 if the altitude is never crossed on this orbit. For a hyperbolic orbit
//			that includes an altitude below the periapsis, at or beyond the sphere of influence, or crossed both ways already.
FUNCTION timeToAltitude
{
	PARAMETER desiredAltitude.

	LOCAL ecc IS SHIP:ORBIT:ECCENTRICITY.
	LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
	LOCAL desiredRadius IS desiredAltitude + SHIP:BODY:RADIUS.
	LOCAL crossingTime IS -1.

	// return -1 if never reach altitude (for either kind of orbit, it is not reached below the periapsis)
	IF desiredAltitude < SHIP:PERIAPSIS RETURN -1.

	IF ecc >= 1 {
		// a parabola has no finite semi-major axis to work with
		IF ecc < 1 + 1e-9 RETURN -1.
		// outside the sphere of influence the ship is on another orbit (the Sun has no sphere of influence)
		IF SHIP:BODY:HASBODY AND desiredRadius >= SHIP:BODY:SOIRADIUS RETURN -1.

		// the semi-latus rectum, sma * (1 - e^2), is positive for a hyperbola because sma is negative
		LOCAL semiLatus IS sma * (1 - ecc^2).
		LOCAL desiredCos IS MAX(-1, MIN(1, (semiLatus / desiredRadius - 1) / ecc)).
		LOCAL desiredTrueAnomaly IS ARCCOS(desiredCos).

		// the mean motion is in radians per second, so the mean anomalies (in degrees) are converted to radians
		LOCAL hyperbolicMeanMotion IS SQRT(SHIP:BODY:MU / (-sma)^3).
		LOCAL desiredMean IS Constant:DegToRad * trueToMeanAnomaly(desiredTrueAnomaly, ecc).
		LOCAL currentMean IS Constant:DegToRad * trueToMeanAnomaly(normalizeAngle180(SHIP:ORBIT:TRUEANOMALY), ecc).

		// the way in comes first (desiredMean is positive), then the way out
		LOCAL inboundTime IS (-desiredMean - currentMean) / hyperbolicMeanMotion.
		LOCAL outboundTime IS (desiredMean - currentMean) / hyperbolicMeanMotion.
		IF inboundTime >= 0 SET crossingTime TO inboundTime.
		ELSE IF outboundTime >= 0 SET crossingTime TO outboundTime.
	} ELSE {
		// an ellipse does not go above its apoapsis
		IF desiredAltitude > SHIP:APOAPSIS RETURN -1.
		IF ecc = 0 SET ecc TO 0.00001. // ensure no divide by 0
		LOCAL currentRadius IS SHIP:ALTITUDE + SHIP:BODY:RADIUS.

		// Step 1: get true anomaly (bounds required for numerical errors near apsides)
		LOCAL desiredTrueAnomalyCos IS MAX(-1, MIN(1, ((sma * (1 - ecc^2) / desiredRadius) - 1) / ecc)).
		LOCAL currentTrueAnomalyCos IS MAX(-1, MIN(1, ((sma * (1 - ecc^2) / currentRadius) - 1) / ecc)).

		// Step 2: calculate eccentric anomaly
		LOCAL desiredEccentricAnomaly IS ARCCOS((ecc + desiredTrueAnomalyCos) / (1 + ecc * desiredTrueAnomalyCos)).
		LOCAL currentEccentricAnomaly IS ARCCOS((ecc + currentTrueAnomalyCos) / (1 + ecc * currentTrueAnomalyCos)).

		// Step 3: calculate mean anomaly
		LOCAL desiredMeanAnomaly IS Constant:DegToRad * desiredEccentricAnomaly - ecc * SIN( desiredEccentricAnomaly).
		LOCAL currentMeanAnomaly IS Constant:DegToRad * currentEccentricAnomaly - ecc * SIN( currentEccentricAnomaly).
		IF ETA:APOAPSIS > ETA:PERIAPSIS {
			SET currentMeanAnomaly TO Constant:PI * 2 - currentMeanAnomaly.
		}
		IF desiredAltitude < SHIP:ALTITUDE {
			SET desiredMeanAnomaly TO Constant:PI * 2 - desiredMeanAnomaly.
		}
		ELSE IF desiredAltitude > SHIP:ALTITUDE AND ETA:APOAPSIS > ETA:PERIAPSIS {
			SET desiredMeanAnomaly TO Constant:PI * 2 + desiredMeanAnomaly.
		}

		// Step 4: calculate time difference via mean motion
		LOCAL meanMotion IS Constant:PI * 2 / SHIP:ORBIT:PERIOD. // in rad/s

		SET crossingTime TO (desiredMeanAnomaly - currentMeanAnomaly) / meanMotion.
	}

	// compare the crossing with the next sphere of influence change
	IF crossingTime >= 0 AND SHIP:ORBIT:HASNEXTPATCH {
		IF crossingTime > SHIP:ORBIT:NEXTPATCHETA RETURN -1.
	}
	RETURN crossingTime.
}

FUNCTION greatCircleDistance
{
	PARAMETER toPosition.
	PARAMETER fromPosition IS SHIP:GEOPOSITION.
	RETURN SHIP:BODY:RADIUS * Constant:DegToRad * ARCCOS(MAX(MIN(SIN(fromPosition:LAT) * SIN(toPosition:LAT) + COS(fromPosition:LAT) * COS(toPosition:LAT) * COS(ABS(fromPosition:LNG - toPosition:LNG)), 1), -1)).
}

// Function that returns the unit vectors showing the direction of prograde,
// radial and normal for an arbitrary Orbitable at a specified UT time
// Passed:
//	 orbitable object
//   UT Time (seconds)
// Returns a lexicon of prograde vector, radial vector, normal vector, position,
//   velocity
// Only valid while the orbitable is in the sphere of influence that it is in now at that time.
FUNCTION getOrbitDirectionsAt {
	PARAMETER orbitable IS SHIP.
  PARAMETER UTTime IS 0.
  LOCAL velocityOf IS VELOCITYAT(orbitable, UTTime):ORBIT.
  LOCAL positionOf IS POSITIONAT(orbitable, UTTime).
  LOCAL vectorPrograde IS velocityOf:NORMALIZED.
  LOCAL vectorRadial IS (positionOf - orbitable:BODY:POSITION).
  LOCAL vectorNormal IS VCRS(vectorPrograde, vectorRadial):NORMALIZED.
  SET vectorRadial TO VCRS(vectorNormal, vectorPrograde):NORMALIZED.
  RETURN LEXICON("prograde", vectorPrograde, "radial", vectorRadial, "normal", vectorNormal, "position", positionOf, "velocity", velocityOf).
}

// Determine the angle between the SHIP's orbital plane and either the equator
//   (if useTarget is false) or the target's orbit (if useTarget is true).
//   Note that because this angle doesn't change, this doesn't take a time argument.
FUNCTION angleFromPlane {
  PARAMETER useTarget IS HASTARGET.

  IF useTarget = FALSE RETURN SHIP:ORBIT:INCLINATION.

  // Normal vector is angular velocity of the object being orbited
  LOCAL normalVector IS SHIP:BODY:ANGULARVEL:NORMALIZED.

  // Normal vector is cross product of the target's position and velocity
  IF useTarget SET normalVector TO VCRS(TARGET:POSITION - TARGET:BODY:POSITION, VELOCITYAT(TARGET, TIME:SECONDS):ORBIT).

  RETURN VANG(VCRS( - SHIP:BODY:POSITION, SHIP:VELOCITY:ORBIT), normalVector).
}

// Determine the distance in meters between SHIP and the plane defined by either
//   the equator (if useTarget is false) or by the target's orbit (if useTarget
//   is true).
FUNCTION distanceFromPlane {
  PARAMETER timeOffset IS 0.
  PARAMETER useTarget IS HASTARGET.

	// Due to KSP using LEFT-handed coordinate systems, use the negative of the
	//   vector to get positive values for north of the plane
  // Normal vector is angular velocity of the object being orbited
  LOCAL normalVector IS -SHIP:BODY:ANGULARVEL:NORMALIZED.

  // Normal vector is cross product of the target's position and velocity
  IF useTarget SET normalVector TO -VCRS(POSITIONAT(TARGET, TIME:SECONDS + timeOffset) - TARGET:BODY:POSITION, VELOCITYAT(TARGET, TIME:SECONDS + timeOffset):ORBIT):NORMALIZED.

  RETURN (POSITIONAT(SHIP, TIME:SECONDS + timeOffset) - SHIP:BODY:POSITION) * normalVector.
}

// returns the number of kilometers from the orbital plane of the target
FUNCTION distanceToTargetOrbitalPlane {
	PARAMETER timeOffset IS 0.
	RETURN distanceFromPlane(timeoffset, TRUE) / 1000.
}

// smallestStepRatio: the search ends when the step is initialStepSize / 2^smallestStepRatio. A guess that is already close
// can start with a small step and end sooner with a lower ratio.
// returns a lexicon
// "Time" time until closest approach (seconds UT)
// "Distance" distance of closest approach (meters)
FUNCTION closestApproach {
	PARAMETER initialGuess IS TIME:SECONDS.
	PARAMETER initialStepSize IS 10.
	PARAMETER logFileName IS "".
	PARAMETER smallestStepRatio IS 15.
	IF (initialGuess < TIME:SECONDS) SET initialGuess TO TIME:SECONDS.
	IF NOT HASTARGET RETURN LEXICON("Time", 0, "Distance", 0).

	FUNCTION distanceAtTime {
	  PARAMETER t.
	  RETURN (POSITIONAT(SHIP, t) - POSITIONAT(TARGET, t)):MAG.
	}

	LOCAL results IS hillClimb(
		distanceAtTime@,
		initialGuess,
		initialStepSize,
		logFileName,
		1000,
		smallestStepRatio).
	// if things didn't work here with the default, try again half an orbit later. A hyperbolic orbit has no period, so it is not retried.
	IF results["finalGuess"] < TIME:SECONDS AND SHIP:ORBIT:ECCENTRICITY < 1 {
		SET results TO hillClimb(
			distanceAtTime@,
			initialGuess + SHIP:ORBIT:PERIOD/2,
			initialStepSize,
			logFileName,
			1000,
			smallestStepRatio).
	}
	RETURN LEXICON("Time", results["finalGuess"], "Distance", results["finalValue"]).
}

// Print some basic information about each of the various orbits that this craft will experience.
FUNCTION exploreOrbits {
  PARAMETER orb IS SHIP:ORBIT.
  CLEARSCREEN.
  LOCAL printCurrentOrbit IS TRUE.
  PRINT "There are " + ALLNODES:LENGTH + " nodes".
	PRINT "Orbit Body:           ".
	PRINT "Orbit Eccentricity:   ".
	PRINT "Orbit Apoapsis:       ".
	PRINT "Orbit Periapsis:      ".
	PRINT "Orbit Inclination:    ".
	PRINT "Orbit Transition:     ".
	PRINT "Orbit Has Next Patch: ".
	LOCAL orbitNumber IS 0.
  UNTIL NOT printCurrentOrbit {
    PRINT orb:BODY:NAME               		AT (22 + orbitNumber * 10, 1).
    PRINT ROUND(orb:ECCENTRICITY, 6)  		AT (22 + orbitNumber * 10, 2).
		PRINT distanceToString(orb:APOAPSIS)  AT (22 + orbitNumber * 10, 3).
		PRINT distanceToString(orb:PERIAPSIS) AT (22 + orbitNumber * 10, 4).
		PRINT ROUND(orb:INCLINATION, 4)       AT (22 + orbitNumber * 10, 5).
		PRINT orb:TRANSITION              AT (22 + orbitNumber * 10, 6).
    PRINT orb:HASNEXTPATCH            AT (22 + orbitNumber * 10, 7).
    SET printCurrentOrbit TO orb:HASNEXTPATCH.
    IF orb:HASNEXTPATCH SET orb TO orb:NEXTPATCH.
		SET orbitNumber TO orbitNumber + 1.
  }
  WAIT 1.
}

// wait for the planet to rotate until you are the specified number of degrees of longitude away from the ground track of the target
FUNCTION waitForTarget {
	PARAMETER offset IS 0.25.

	CLEARSCREEN.
	IF NOT HASTARGET PRINT "Please select a target vessel or body in the same SOI.".

	UNTIL HASTARGET WAIT 0.1.

	LOCAL rotationPeriod IS SHIP:BODY:ROTATIONPERIOD.
	LOCAL currentLongitude IS SHIP:GEOPOSITION:LNG.
	LOCAL targetLAN TO TARGET:ORBIT:LAN.

	LOCAL angleASC IS currentLongitude - (targetLAN - SHIP:BODY:ROTATIONANGLE).
	LOCAL correctedAngleASC IS 0.
	IF angleASC > 0 SET correctedAngleASC TO 360 - angleASC.
	ELSE SET correctedAngleASC TO -angleASC.

	LOCAL angleDES IS currentLongitude - (targetLAN - SHIP:BODY:ROTATIONANGLE + 180).
	LOCAL correctedAngleDES IS 0.
	IF angleDES > 0 SET correctedAngleDES TO 360 - angleDES.
	ELSE SET correctedAngleDES TO -angleDES.

	IF correctedAngleASC < correctedAngleDES {
		PRINT "Warping to the ascending node".
		WAIT 0.
		warpToTime(TIME:SECONDS + (correctedAngleASC - offset) / 360 * rotationPeriod).
		RETURN 1.
	} ELSE {
		PRINT "Warping to the descending node".
		WAIT 0.
		warpToTime(TIME:SECONDS + (correctedAngleDES - offset) / 360 * rotationPeriod).
		RETURN -1.
	}
}

FUNCTION logPhysics {
	PARAMETER fileName IS "0:" + SHIP:NAME + " Physics.csv".
	IF connectionToKSC() {
		IF (NOT logPhysicsTimeStamp) {
			LOG "s,kg,m,m,atm,m/s,m/s,,m/s^2,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,m/s,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,,,,,,,," TO fileName.
			LOG "Time,Mass,Altitude ASL,Altitude AGL,Air Pressure,Orbital Velocity,Surface Velocity,Throttle,Current Constant Accel,Current Constant mDot,Current Constant Thrust,Current Constant TWR,Current Variable Accel,Current Variable mDot,Current Variable Thrust,Current Variable TWR,Current Accel,Current BurnTime,Current mDot,Current Thrust,Current TWR,Maximum Constant Accel,Maximum Constant mDot,Maximum Constant Thrust,Maximum Constant TWR,Maximum Variable Accel,Maximum Variable mDot,Maximum Variable Thrust,Maximum Variable TWR,Maximum Accel,Maximum BurnTime,Maximum mDot,Maximum Thrust,Maximum TWR,Yaw,Pitch,Roll,Yaw Throttle,Pitch Throttle,Roll Throttle,Steering Manager Enabled,Steering Manager Angle Error,PITCHPID:KP,PITCHPID:KI,PITCHPID:KD,YAWPID:KP,YAWPID:KI,YAWPID:KD,ROLLPID:KP,ROLLPID:KI,ROLLPID:KD" TO fileName.
			SET logPhysicsTimeStamp TO TIME:SECONDS.
		}
		updateShipInfoCurrent(FALSE).
		LOG (TIME:SECONDS - logPhysicsTimeStamp) + "," + MASS * 1000 + "," + ALTITUDE + "," + ALT:RADAR + "," + SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) + "," + VELOCITY:ORBIT:MAG + "," + VELOCITY:SURFACE:MAG + "," + THROTTLE + "," + shipInfo["Current"]["Constant"]["Accel"] + "," + shipInfo["Current"]["Constant"]["mDot"] + "," + shipInfo["Current"]["Constant"]["Thrust"] + "," + shipInfo["Current"]["Constant"]["TWR"] + "," + shipInfo["Current"]["Variable"]["Accel"] + "," + shipInfo["Current"]["Variable"]["mDot"] + "," + shipInfo["Current"]["Variable"]["Thrust"] + "," + shipInfo["Current"]["Variable"]["TWR"] + "," + shipInfo["Current"]["Accel"] + "," + shipInfo["Current"]["BurnTime"] + "," + shipInfo["Current"]["mDot"] + "," + shipInfo["Current"]["Thrust"] + "," + shipInfo["Current"]["TWR"] + "," + shipInfo["Maximum"]["Constant"]["Accel"] + "," + shipInfo["Maximum"]["Constant"]["mDot"] + "," + shipInfo["Maximum"]["Constant"]["Thrust"] + "," + shipInfo["Maximum"]["Constant"]["TWR"] + "," + shipInfo["Maximum"]["Variable"]["Accel"] + "," + shipInfo["Maximum"]["Variable"]["mDot"] + "," + shipInfo["Maximum"]["Variable"]["Thrust"] + "," + shipInfo["Maximum"]["Variable"]["TWR"] + "," + shipInfo["Maximum"]["Accel"] + "," + shipInfo["Maximum"]["BurnTime"] + "," + shipInfo["Maximum"]["mDot"] + "," + shipInfo["Maximum"]["Thrust"] + "," + shipInfo["Maximum"]["TWR"] + "," + yaw_for(SHIP) + "," + pitch_for(SHIP) + "," + SHIP:FACING:ROLL + "," + STEERINGMANAGER:YAWPID:OUTPUT + "," + STEERINGMANAGER:PITCHPID:OUTPUT + "," + STEERINGMANAGER:ROLLPID:OUTPUT + "," + STEERINGMANAGER:ENABLED + "," + STEERINGMANAGER:ANGLEERROR + "," + STEERINGMANAGER:PITCHPID:KP + "," + STEERINGMANAGER:PITCHPID:KI + "," + STEERINGMANAGER:PITCHPID:KD + "," + STEERINGMANAGER:YAWPID:KP + "," + STEERINGMANAGER:YAWPID:KI + "," + STEERINGMANAGER:YAWPID:KD + "," + STEERINGMANAGER:ROLLPID:KP + "," + STEERINGMANAGER:ROLLPID:KI + "," + STEERINGMANAGER:ROLLPID:KD TO fileName.
	}
}

FUNCTION weightedAverage {
	PARAMETER valueList IS LIST().
	PARAMETER weightList IS LIST().
	LOCAL totalTop IS 0.
	LOCAL totalBottom IS 0.
	IF valueList:LENGTH = weightList:LENGTH AND valueList:LENGTH > 0 {
		IF valueList:LENGTH = 1 {
			RETURN valueList[0].
		}
		IF valueList:LENGTH > 1 {
			FOR eachIndex IN RANGE(0, valueList:LENGTH, 1) {
				SET totalTop TO totalTop + valueList[eachIndex] * weightList[eachIndex].
				SET totalBottom TO totalBottom + weightList[eachIndex].
			}
			IF totalBottom = 0 RETURN totalTop.
			ELSE RETURN totalTop / totalBottom.
		}
	} ELSE RETURN 0.
}

FUNCTION processScalarParameter {
	PARAMETER para.
	PARAMETER errorValueScalar IS errorValue.
	IF para:TYPENAME = "Scalar" RETURN para.
	IF para:TYPENAME = "String" {
		LOCAL returnNumber IS errorValueScalar.
		IF para:ENDSWITH("k") {
			SET returnNumber TO para:REPLACE("k", ""):TONUMBER(errorValueScalar).
			IF returnNumber <> errorValueScalar RETURN returnNumber * 1000.0.
		}
		IF para:ENDSWITH("M") {
			SET returnNumber TO para:REPLACE("M", ""):TONUMBER(errorValueScalar).
			IF returnNumber <> errorValueScalar RETURN returnNumber * 1000000.0.
		}
		IF para:ENDSWITH("G") {
			SET returnNumber TO para:REPLACE("G", ""):TONUMBER(errorValueScalar).
			IF returnNumber <> errorValueScalar RETURN returnNumber * 1000000000.0.
		}
		RETURN returnNumber.
	}
	RETURN errorValueScalar.
}

// Calculate Flight Path Angle
// passed:
//		True anomaly (scalar)
//		Eccentricity (scalar)
FUNCTION flightPathAngle {
	PARAMETER trueAnomaly.
	PARAMETER eccentricity.
	RETURN ARCTAN(eccentricity * SIN(trueAnomaly) / (1 + eccentricity * COS(trueAnomaly))).
}

// Given an angle in degrees, returns the normalized angle in degrees
// Returns an angle from 0 degrees up to, but not including, 360 degrees
FUNCTION normalizeAngle360 {
	PARAMETER angle.
	RETURN MOD(MOD(angle, 360) + 360, 360).
}

// Given an angle in degrees, returns the normalized angle in degrees
// Returns an angle greater than -180 degrees, up to and including 180 degrees
FUNCTION normalizeAngle180 {
	PARAMETER angle.
	LOCAL tempAngle IS MOD(MOD(angle, 360) + 360, 360).
	IF tempAngle > 180 RETURN tempAngle - 360.
	RETURN tempAngle.
}

LOCAL maxHyperbolicVariable IS 709.78.
LOCAL maxHyperbolicVariableTANH IS 354.0.

// A variety of hyperbolic trig functions and their inverses
FUNCTION TANH {
	PARAMETER x.
	SET X TO MIN(maxHyperbolicVariableTANH, MAX(-maxHyperbolicVariableTANH, x)).
	RETURN (CONSTANT:E ^ (2*x) - 1) / (CONSTANT:E ^ (2*x) + 1).
}

FUNCTION COSH {
	PARAMETER x.
	SET X TO MIN(maxHyperbolicVariable, MAX(-maxHyperbolicVariable, x)).
	RETURN ((CONSTANT:E ^ x) + (CONSTANT:E ^ (-x)))/2.
}

FUNCTION SINH {
	PARAMETER x.
	SET X TO MIN(maxHyperbolicVariable, MAX(-maxHyperbolicVariable, x)).
	RETURN ((CONSTANT:E ^ x) - (CONSTANT:E ^ (-x)))/2.
}

FUNCTION ATANH {PARAMETER x. RETURN LN((1 + x) / (1 - x))/2.}

FUNCTION ACOSH {
	PARAMETER x.
	IF x < 1 AND x > 1 - 1e-9 SET x TO 1.
	RETURN LN(x + SQRT((x - 1) * (x + 1))).
}

FUNCTION ASINH {
	PARAMETER x.
	IF x < 0 RETURN -LN(-x + SQRT(x^2 + 1)).
	RETURN LN(x + SQRT(x^2 + 1)).
}

// Function that calculates the approximate distance travelled during the course of a burn.
// Assumes that all of the thrust of the engines are directly in line with travel.
// Ignores all gravity.
FUNCTION burnDistance {
	PARAMETER x_i.
	PARAMETER v_i.
	PARAMETER v_e.
	PARAMETER m_i.
	PARAMETER m_dot.
	PARAMETER t.
	RETURN x_i + t*(v_i + v_e) + v_e*(t - m_i/m_dot)*LN(m_i/(m_i - m_dot*t)).
}

// Calculates how long it will take to perform a given engine burn.
FUNCTION burnTime {
	PARAMETER m_i.
	PARAMETER m_dot.
	PARAMETER dV.
	PARAMETER v_e.
	RETURN m_i/m_dot*(1 - CONSTANT:E^(-dV/v_e)).
}

// function that calculates the time (in seconds) required before firing all engines at 100% for a suicide burn.
// Assumes that updateShipInfoCurrent has been run recently.
// Currently only partially assumes vertical drop
//   and does NOT assume constant acceleration or gravity.
FUNCTION SuicideBurnInfo {
	LOCAL t IS 1.
	LOCAL v_i IS -VELOCITY:SURFACE:MAG.
	LOCAL totalDVNeeded IS VELOCITY:SURFACE:MAG.
	LOCAL m_dot IS shipInfo["Maximum"]["mDot"].
	LOCAL v_e IS shipInfo["CurrentStage"]["Isp"] * g_0.
	LOCAL x_i IS heightAboveGround().
	LOCAL x_f IS 0.
	LOCAL x_fOld IS x_f + 20.
	LOCAL x_avg IS 0.
	LOCAL g_avg IS 0.
	LOCAL g_i TO (SHIP:BODY:MU / (ALTITUDE + SHIP:BODY:RADIUS)^2).
	LOCAL m_i IS SHIP:MASS * 1000.
	LOCAL gravityDrag IS 0.
	LOCAL iteration IS 0.

	LOCAL integralOfDistanceAtT0 IS -v_e*m_dot*m_i^2*LN(m_i)/(2*m_dot^3).

	UNTIL ABS(x_fOld - x_f) < 0.01 OR iteration > 25 {	// Until the distance estimate changes by less than 1 centimeter
		SET iteration TO iteration + 1.
		SET x_fOld TO x_f.
		// the below horrible equation is the analytical integration (over time) of the equation for distance. It sucks, I know.
		SET x_avg TO (t*x_i+(t^2*(v_i+v_e))/2+((t^2/2-(m_i*t)/m_dot)*LN(m_i/(m_i-m_dot*t))-m_dot*((m_i^2*LN(ABS(m_dot*t-m_i)))/(2*m_dot^3)-(m_dot*t^2-2*m_i*t)/(4*m_dot^2)))*v_e-integralOfDistanceAtT0)/t.
		SET g_avg TO (SHIP:BODY:MU / (ALTITUDE - x_avg + SHIP:BODY:RADIUS)^2).
		SET t TO m_i * (1 - CONSTANT:E^(-totalDVNeeded/v_e))/m_dot.
		SET gravityDrag TO t * g_avg.
		SET x_f TO v_e/m_dot*((m_i-m_dot*t)*LN((m_i-m_dot*t)/m_i)+m_dot*t) - 0.5*g_avg*t^2.
		SET totalDVNeeded TO ABS(v_i) + gravityDrag.
	}
	LOCAL returnMe IS LEXICON().
	returnMe:ADD(   "distance",           x_f).
	returnMe:ADD("distanceAvg",         x_avg).
	returnMe:ADD(      "g_avg",         g_avg).
	returnMe:ADD(       "time",             t).
	returnMe:ADD(     "deltaV", totalDVNeeded).
	returnMe:ADD( "deltaVGrav",   gravityDrag).
	RETURN returnMe.
}

// Given the desired velocity at infinity and ETA, calculate the various parameters
// to transition the existing elliptical orbit (of whatever type) to a hyperbolic
// escape orbit from the body.
// Passed the following:
//   v_inf - scalar - velocity ship should have "at infinity" in m/s
//   burnETA - scalar - time in seconds until the burn.
//	 vesselObject - vessel object - ship for which these calculations should take place. Defaults to SHIP.
// Returns the following:
//   Lexicon of the following data points:
//     "a" - scalar - semimajor axis of the hyperbola. Negative.
//     "b" - scalar - semiminor axis of the hyperbola.
//     "e" - scalar - eccentricity of the hyperbola. Greater than 1.0.
//     "l" - scalar - semi-latus rectum of the hyperbola. Negative.
//     "theta_turn" - scalar - turning angle from the burn to SOI edge.
//     "v_delta" - scalar - delta V (m/s) required for the burn to transition from elliptical orbit to hyperbolic orbit.
//     "flightPathAngle" - scalar - flight path angle (degrees) of both orbits at the burn.
//     "trueAnomaly" - scalar - true anomaly (degrees) of the burn on the hyperbolic orbit.
//     "flightPathAngleSOI" - scalar - flight path angle (degrees) of hyperbolic orbit at the SOI edge.
//     "trueAnomalySOI" - scalar - true anomaly (degrees) of hyperbolic orbit at the SOI edge.
FUNCTION getHyperbolicBurnInfo {
  PARAMETER v_inf.
  PARAMETER burnETA.
  PARAMETER vesselObject IS SHIP.
  LOCAL r_body IS vesselObject:BODY:RADIUS.
  LOCAL r_SOI IS vesselObject:BODY:SOIRADIUS.
  LOCAL mu IS vesselObject:BODY:MU.
  LOCAL pos_burn IS POSITIONAT(vesselObject, TIME:SECONDS + burnETA) - vesselObject:BODY:POSITION.
  LOCAL r_burn IS pos_burn:MAG.
  LOCAL v_ellipse IS VELOCITYAT(vesselObject, TIME:SECONDS + burnETA):ORBIT.
  LOCAL phi_burn IS (90 - VANG(pos_burn, v_ellipse)).
  LOCAL v_esc IS SQRT(2*mu/r_burn).
  LOCAL v_hyperbola IS SQRT(v_inf^2+v_esc^2).
  LOCAL a IS -mu/v_inf^2.
  LOCAL e IS SQRT((r_burn * v_hyperbola^2 / mu - 1)^2 * COS(phi_burn)^2 + SIN(phi_burn)^2).
  LOCAL b IS -a*SQRT(e^2-1).
  LOCAL l IS b^2/a.
  LOCAL v_delta IS v_hyperbola - v_ellipse:MAG.
  LOCAL theta_SOI IS ARCCOS((a*(1-e^2)-r_SOI)/(e*r_SOI)).
  LOCAL phi_SOI IS ARCTAN((e*SIN(theta_SOI))/(1+e*COS(theta_SOI))).
  LOCAL theta_burn IS ARCCOS(MAX(-1, MIN(1, (a*(1-e^2) - r_burn)/(r_burn*e)))).
  IF phi_burn < 0 SET theta_burn TO -theta_burn.
  LOCAL theta_turn IS ARCTAN2(e+COS(theta_SOI), -SIN(theta_SOI)) - ARCTAN2(e+COS(theta_burn), -SIN(theta_burn)).
  RETURN LEXICON("a", a,
                 "b", b,
                 "e", e,
								 "l", l,
                 "theta_turn", theta_turn,
                 "v_delta", v_delta,
                 "flightPathAngle", phi_burn,
                 "trueAnomaly", theta_burn,
                 "flightPathAngleSOI", phi_SOI,
                 "trueAnomalySOI", theta_SOI).
}

FUNCTION absolutePosition {
  PARAMETER thing.
  PARAMETER timeStampNew IS TIME:SECONDS.

  IF thing:NAME = "Sun" RETURN V(0, 0, 0).

  LOCAL originalThing IS thing.
  LOCAL removals IS 0.
  LOCAL finalPosition IS V(0, 0, 0).
  UNTIL NOT thing:HASBODY {
    SET finalPosition TO finalPosition + POSITIONAT(thing, timeStampNew).
    SET thing TO thing:BODY.
    SET removals TO removals + 1.
  }
  SET finalPosition TO finalPosition - POSITIONAT(BODY("Sun"), timeStampNew).
  IF removals = 2 RETURN finalPosition - originalThing:BODY:POSITION.
  IF removals = 3 RETURN finalPosition - originalThing:BODY:POSITION - originalThing:BODY:BODY:POSITION.
  RETURN finalPosition.
}

FUNCTION absoluteVelocity {
  PARAMETER thing.
  PARAMETER timeStampNew IS TIME:SECONDS.

  LOCAL removals IS 0.
  LOCAL finalVelocity IS V(0, 0, 0).
  UNTIL NOT thing:HASBODY {
    SET finalVelocity TO finalVelocity + VELOCITYAT(thing, timeStampNew):ORBIT.
    SET thing TO thing:BODY.
  }
  RETURN finalVelocity.
}

// Gets the normal vector of an Orbitable object.
// The vector is normalized.
FUNCTION getNormalVector {
  PARAMETER orbitableObject IS "Equator".
  IF orbitableObject = "Equator" RETURN SHIP:BODY:ANGULARVEL:NORMALIZED.
  RETURN VCRS(orbitableObject:POSITION - orbitableObject:BODY:POSITION, VELOCITYAT(orbitableObject, TIME:SECONDS):ORBIT):NORMALIZED.
}

// take the current orbit and a desired final true anomaly and return the time
// until the passed object will be at that true anomaly.
// This works for either elliptical or hyperbolic orbits.
// If the true anomaly is less than the current true anomaly, response varies
// based on eccentricity.
//     In the elliptical case, it just adds the period to the true anomaly.
//     In the hyperbolic case, it returns 0 seconds.
FUNCTION trueAnomalyDeltaToTime {
	PARAMETER orbitObject.
	PARAMETER startingTrueAnomaly.
	PARAMETER finalTrueAnomaly.
	IF orbitObject:ECCENTRICITY < 1 {
		// for elliptical orbits, this is fairly easy
		IF finalTrueAnomaly < startingTrueAnomaly SET finalTrueAnomaly TO finalTrueAnomaly + 360.
		LOCAL trueAnomalyDelta IS normalizeAngle360(trueToMeanAnomaly(finalTrueAnomaly) - trueToMeanAnomaly(startingTrueAnomaly)).
		RETURN trueAnomalyDelta / 360 * orbitObject:PERIOD.
	} ELSE {
		// For hyperbolic orbits, true anomaly to time is more complicated.
		IF finalTrueAnomaly < startingTrueAnomaly RETURN 0.
		// The time of flight equations only work for positive true anomalies.
		// Because of this, if the starting true anomaly is less than zero, split
		// up the equation into two portions - the time to go from the starting true
		// anomaly to the periapsis, and the time to go from the periapsis to the
		// final true anomaly.
		IF startingTrueAnomaly < 0 {
			LOCAL secondPortionTime IS trueAnomalyDeltaToTime(orbitObject,0,ABS(finalTrueAnomaly)).
			IF finalTrueAnomaly < 0 SET secondPortionTime TO -secondPortionTime.
			RETURN secondPortionTime + orbitObject:ETA:PERIAPSIS.
		} ELSE {
			LOCAL ecc IS orbitObject:ECCENTRICITY.
			LOCAL a IS orbitObject:SEMIMAJORAXIS.
			LOCAL GM IS orbitObject:BODY:MU.
			LOCAL v_0 IS startingTrueAnomaly.
			LOCAL v_1 IS finalTrueAnomaly.

			// Equation taken from http://www.braeunig.us/space/index.htm, section "Orbital Mechanics", equation 4.87.
			LOCAL F_0 IS ACOSH((ecc + COS(v_0))/(1 + ecc * COS(V_0))).
			LOCAL F_1 IS ACOSH((ecc + COS(v_1))/(1 + ecc * COS(V_1))).

			// This equation only uses the hyperbolic eccentric anomaly, not the mean anomaly.
			// Equation taken from http://www.braeunig.us/space/index.htm, section "Orbital Mechanics", equation 4.86.
			RETURN SQRT((-a)^3/GM)*((ecc*SINH(F_1)-F_1)-(ecc*SINH(F_0)-F_0)).
		}
	}
}

// Returns the angle from the first vector to the second vector in the direction
//   indicated by the third vector, in degrees between 0 and 360.
FUNCTION VANGSigned {
  PARAMETER vector1.
  PARAMETER vector2.
  PARAMETER vector3.
  LOCAL norm IS VCRS(vector1:NORMALIZED, vector2:NORMALIZED).
  IF VDOT(norm, vector3) >= 0 RETURN VANG(vector1, vector2).
  RETURN 360 - VANG(vector1, vector2).
}

// Given two bodies, return the first body that is in both of their chains of parent bodies, counting the
// objects themselves. For planets, this will be the Sun. For moons of the same body, this will be that body.
// For moons of different bodies, this will be the same as if it ran with those two different bodies.
// If one object is an ancestor of the other (for example Mun and Kerbin), that ancestor itself is returned.
FUNCTION firstCommonBody {
	PARAMETER objectOne.
	PARAMETER objectTwo.
	LOCAL object1Bodies IS LIST().
	UNTIL NOT objectOne:HASBODY {
		IF objectOne:ISTYPE("Body") object1Bodies:ADD(objectOne:NAME).
		SET objectOne TO objectOne:BODY.
	}
	UNTIL NOT objectTwo:HASBODY {
		IF objectTwo:ISTYPE("Body") AND object1Bodies:CONTAINS(objectTwo:NAME) RETURN objectTwo.
		SET objectTwo TO objectTwo:BODY.
	}
	RETURN objectTwo.
}

// Returns BODY(objectName) or VESSEL(objectName) (a vessel wins), or the scalar 0 if neither exists.
// A BODY or VESSEL passed in is returned as it is; a part is rejected with 0 (pass its :SHIP).
// Vessel names are not unique, so a name that is the current target's returns the target itself.
FUNCTION resolveOrbitable {
	PARAMETER objectName.

	IF objectName:ISTYPE("Body") OR objectName:ISTYPE("Vessel") RETURN objectName.
	IF objectName:ISTYPE("DockingPort") OR objectName:ISTYPE("Part") RETURN 0.

	IF HASTARGET {
		IF TARGET:NAME = objectName AND (TARGET:ISTYPE("Body") OR TARGET:ISTYPE("Vessel")) RETURN TARGET.
	}

	LOCAL result IS 0.
	IF BODYEXISTS(objectName) SET result TO BODY(objectName).
	IF VESSELEXISTS(objectName) SET result TO VESSEL(objectName).
	RETURN result.
}

// The current target as an orbitable, the object itself (not its name, which another vessel can share): a Body or
// a Vessel, or for a docking port (or any part) the vessel it is on. The scalar 0 if there is no target.
FUNCTION currentTargetOrbitable {
	IF NOT HASTARGET RETURN 0.
	IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") RETURN TARGET:SHIP.
	RETURN TARGET.
}

// Gets the operator's attention: a short beep (0.2 s at 880 Hz, voice 0), then a 5 s wait.
FUNCTION alertOperator {
	LOCAL alertVoice IS GETVOICE(0).
	SET alertVoice:WAVE TO "square".
	SET alertVoice:VOLUME TO 0.5.
	alertVoice:PLAY(NOTE(880, 0.2)).
	WAIT 5.
}

// Formats a real-world (wall-clock) duration in seconds, e.g. "9.4s", "4m 09s" or "1h 04m 09s".
// timeToString counts in game days (6 hours long) and so is wrong for real time; use this for
// differences of KUNIVERSE:REALWORLDTIME.
FUNCTION realTimeToString {
	PARAMETER seconds.

	IF seconds < 60 RETURN ROUND(seconds, 1) + "s".
	LOCAL wholeSeconds IS ROUND(seconds).
	LOCAL wholeHours IS FLOOR(wholeSeconds / 3600).
	LOCAL wholeMinutes IS FLOOR((wholeSeconds - wholeHours * 3600) / 60).
	LOCAL secondsLeft IS wholeSeconds - wholeHours * 3600 - wholeMinutes * 60.
	LOCAL minutesText IS "" + wholeMinutes.
	LOCAL secondsText IS "" + secondsLeft.
	IF secondsLeft < 10 SET secondsText TO "0" + secondsText.
	IF wholeHours > 0 {
		IF wholeMinutes < 10 SET minutesText TO "0" + minutesText.
		RETURN wholeHours + "h " + minutesText + "m " + secondsText + "s".
	}
	RETURN minutesText + "m " + secondsText + "s".
}

// Picks a readable unit for a duration: "Days", or "Hours" if under half a day,
// or "Minutes" if under an hour.
FUNCTION timeUnitFor {
	PARAMETER seconds.

	IF seconds < 3600 RETURN "Minutes".
	IF seconds < KUNIVERSE:HOURSPERDAY * 1800 RETURN "Hours".
	RETURN "Days".
}

// Number of seconds in one of the units returned by timeUnitFor.
FUNCTION timeUnitSeconds {
	PARAMETER unitName.

	IF unitName = "Days" RETURN KUNIVERSE:HOURSPERDAY * 3600.
	IF unitName = "Hours" RETURN 3600.
	RETURN 60.
}

// A duration as one number in the largest unit it is not smaller than, with 2 decimal places,
// e.g. "5.42 days", "1.23 minutes", "37.00 seconds". Days are game days (KUNIVERSE:HOURSPERDAY
// hours long), as in timeToString.
FUNCTION durationToUnitString {
	PARAMETER totalSeconds.

	LOCAL unitName IS "seconds".
	LOCAL unitLength IS 1.
	IF totalSeconds >= KUNIVERSE:HOURSPERDAY * 3600 {
		SET unitName TO "days".
		SET unitLength TO KUNIVERSE:HOURSPERDAY * 3600.
	} ELSE IF totalSeconds >= 3600 {
		SET unitName TO "hours".
		SET unitLength TO 3600.
	} ELSE IF totalSeconds >= 60 {
		SET unitName TO "minutes".
		SET unitLength TO 60.
	}

	// ROUND(x, 2):TOSTRING drops a trailing zero ("5.4"), so build the two decimals by hand.
	LOCAL hundredths IS ROUND(totalSeconds / unitLength * 100).
	LOCAL wholePart IS FLOOR(hundredths / 100).
	LOCAL fractionPart IS hundredths - wholePart * 100.
	LOCAL fractionText IS "" + fractionPart.
	IF fractionPart < 10 SET fractionText TO "0" + fractionPart.
	RETURN wholePart + "." + fractionText + " " + unitName.
}

FUNCTION VESSELEXISTS {
	PARAMETER vesselNameCandidate.
	
	LOCAL vessels IS LIST().
	LIST TARGETS IN vessels.
	
	FOR eachVessel IN vessels {
		IF eachVessel:NAME = vesselNameCandidate RETURN TRUE.
	}
	RETURN FALSE.
}


// Stages if it is time to, and returns the reason. It is time to stage when the engines are producing no thrust, when an
// engine has flamed out, or when the tanks of the current stage are empty. Below the top of the atmosphere the long wait
// of stageFunction (in loop.ks) is used, so that the spent stage drops clear of the rocket.
// Assumes that updateShipInfoCurrent has been run recently, for the resources.
// Passed the following:
//   thrustSeen (boolean, whether the engines of the current stage have been seen producing thrust. The no-thrust and
//               empty-tank checks only apply when it is TRUE, so that a stage that has not started yet is not dropped.)
//   execute (boolean, FALSE to only report the reason without staging, so that the caller can prepare first, for ullage)
// Returns the following:
//   "max thrust", "flameout" or "resources" if the ship was staged (or would be, if execute is FALSE), "None" if it was not
FUNCTION stageIfNeeded {
	PARAMETER thrustSeen IS TRUE.
	PARAMETER execute IS TRUE.
	LOCAL reason IS "None".

	IF thrustSeen AND MAXTHRUST = 0 SET reason TO "max thrust".

	IF reason = "None" {
		LOCAL engineList IS LIST().
		LIST ENGINES IN engineList.
		FOR eng IN engineList {
			IF eng:FLAMEOUT AND eng:IGNITION {
				SET reason TO "flameout".
				BREAK.
			}
		}
	}

	IF reason = "None" AND thrustSeen AND shipInfo["CurrentStage"]["ResourceMass"] < 1.0 SET reason TO "resources".

	IF reason <> "None" AND execute {
		IF ALTITUDE < SHIP:BODY:ATM:HEIGHT stageFunction(10, TRUE).
		ELSE stageFunction().
	}
	RETURN reason.
}

// getRCSThrusts
// Inputs:
//   None.
// Outputs:
//   Vector - summed AVAILABLETHRUST (Newtons) of all enabled RCS parts on
//   the current SHIP, split by translation axis: X = Fore, Y = Top,
//   Z = Starboard.
// Side Effects:
//   None.
FUNCTION getRCSThrusts {
	LOCAL RCSThrusters IS LIST().
	LIST RCS IN RCSThrusters.
	LOCAL maxRCSThrust IS V(0, 0, 0).
	FOR eachRCS IN RCSThrusters {
		IF eachRCS:ENABLED {
			IF eachRCS:FOREENABLED SET maxRCSThrust:X TO maxRCSThrust:X + eachRCS:AVAILABLETHRUST * 1000.
			IF eachRCS:TOPENABLED SET maxRCSThrust:Y TO maxRCSThrust:Y + eachRCS:AVAILABLETHRUST * 1000.
			IF eachRCS:STARBOARDENABLED SET maxRCSThrust:Z TO maxRCSThrust:Z + eachRCS:AVAILABLETHRUST * 1000.
		}
	}
	RETURN maxRCSThrust.
}

// modulateInput
// Inputs:
//   input (Scalar, range [-inf, inf]) - desired control input.
//   threshold (Scalar, range [0, inf]) - minimum input magnitude the
//        actuator can respond to continuously.
//   period (Scalar, > 0) - PWM period, seconds, used when
//        ABS(input) < threshold.
// Outputs:
//   Scalar - input unchanged if ABS(input) >= threshold; otherwise
//   +/-threshold during the PWM "on" phase, or 0 during the "off" phase.
// Side Effects:
//   None.
FUNCTION modulateInput {
    PARAMETER input.
    PARAMETER threshold.
    PARAMETER period.
	
	IF threshold < 0 SET threshold TO ABS(threshold).

    IF ABS(input) >= threshold { RETURN input. }

    LOCAL sign IS 1.
    IF input < 0 { SET sign TO -1. }

    LOCAL dutyCycle IS ABS(input) / threshold.
    IF dutyCycle < 0 { SET dutyCycle TO 0. }
    IF dutyCycle > 1 { SET dutyCycle TO 1. }

    LOCAL phase IS MOD(TIME:SECONDS, period) / period.
    IF phase < dutyCycle RETURN threshold * sign.

    RETURN 0.
}

// applyRCSAccel
// Inputs:
//   effortVec (Vector) - desired acceleration, m/s^2, ship-local Fore/
//        Top/Starboard frame.
//   maxLimits (Vector, default V(1,1,1)) - per-axis maximum achievable
//        acceleration, m/s^2, used to normalize effortVec into a
//        [-1, 1] SHIP:CONTROL command. Axes with maxLimits <= 0 are
//        commanded to 0.
//   rcsDeadzoneThreshold (Scalar, range [0, 1], default 0.05) - minimum
//        continuous RCS command, as a fraction of full thrust.
//   rcsPwmPeriod (Scalar, > 0, default 0.2) - PWM period, seconds, used
//        for commands below rcsDeadzoneThreshold.
//   effortDeadband (Scalar, range [0, 1], default 0) - commands smaller
//        than this fraction of full thrust, on an axis, are not sent at
//        all. Tiny commands that change sign with the noise would otherwise
//        be turned into pulses that fire the thrusters in both directions.
// Outputs:
//   None.
// Side Effects:
//   Sets SHIP:CONTROL:FORE, SHIP:CONTROL:TOP, SHIP:CONTROL:STARBOARD.
FUNCTION applyRCSAccel {
    PARAMETER effortVec.
    PARAMETER maxLimits IS V(1, 1, 1).
    PARAMETER rcsDeadzoneThreshold IS 0.05.
    PARAMETER rcsPwmPeriod IS 0.2.
    PARAMETER effortDeadband IS 0.

    LOCAL effort IS V(0, 0, 0).
    IF maxLimits:X > 0 { SET effort:X TO effortVec:X / maxLimits:X. }
    IF maxLimits:Y > 0 { SET effort:Y TO effortVec:Y / maxLimits:Y. }
    IF maxLimits:Z > 0 { SET effort:Z TO effortVec:Z / maxLimits:Z. }

    IF effort:X > 1 { SET effort:X TO 1. }
    IF effort:X < -1 { SET effort:X TO -1. }
    IF effort:Y > 1 { SET effort:Y TO 1. }
    IF effort:Y < -1 { SET effort:Y TO -1. }
    IF effort:Z > 1 { SET effort:Z TO 1. }
    IF effort:Z < -1 { SET effort:Z TO -1. }

    IF ABS(effort:X) < effortDeadband { SET effort:X TO 0. }
    IF ABS(effort:Y) < effortDeadband { SET effort:Y TO 0. }
    IF ABS(effort:Z) < effortDeadband { SET effort:Z TO 0. }

    SET SHIP:CONTROL:FORE TO modulateInput(effort:X, rcsDeadzoneThreshold, rcsPwmPeriod).
    SET SHIP:CONTROL:TOP TO modulateInput(effort:Y, rcsDeadzoneThreshold, rcsPwmPeriod).
    SET SHIP:CONTROL:STARBOARD TO modulateInput(effort:Z, rcsDeadzoneThreshold, rcsPwmPeriod).
}

// getRCSSignature
// Inputs:
//   maxAccel (Vector) - the ship's maximum RCS acceleration along Fore, Top, Starboard, m/s^2, as the calling script works it out
//        (thrust divided by mass).
// Outputs:
//   Lexicon describing the ship's RCS setup, for deciding whether an earlier RCS tuning still applies:
//     "partCount" (Scalar) - number of parts on the SHIP, which changes on docking, undocking and staging.
//     "controlPart" (String) - UID of SHIP:CONTROLPART, since controlling from another part changes the axes.
//     "rcsCount" (Scalar) - number of RCS parts.
//     "rcsChecksum" (Scalar) - a number that changes when the set of RCS parts changes, or when any of them has a different
//          enabled flag, enabled direction or thrust limit. It is not affected by mass.
//     "maxAccel" (List of Scalar) - the maxAccel parameter as a list. Changes with mass and with thrust.
//     "mass" (Scalar) - SHIP:MASS, tonnes. Not used to compare signatures, only kept for information.
// Side Effects:
//   None.
FUNCTION getRCSSignature {
    PARAMETER maxAccel.

    LOCAL rcsList IS LIST().
    LIST RCS IN rcsList.

    LOCAL checksum IS 0.
    FOR eachRCS IN rcsList {
        // each RCS part adds a number that depends on which part it is and how it is set up; adding them makes the order irrelevant
        LOCAL flags IS 1.
        IF eachRCS:ENABLED SET flags TO flags + 1.
        IF eachRCS:FOREENABLED SET flags TO flags + 2.
        IF eachRCS:TOPENABLED SET flags TO flags + 4.
        IF eachRCS:STARBOARDENABLED SET flags TO flags + 8.
        SET flags TO flags + 16 * ROUND(eachRCS:THRUSTLIMIT).
        LOCAL partNumber IS MOD(eachRCS:UID:TONUMBER(0), 1000003).
        SET checksum TO MOD(checksum + (partNumber + 1) * flags, 1000000007).
    }

    RETURN LEXICON(
        "partCount", SHIP:PARTS:LENGTH,
        "controlPart", SHIP:CONTROLPART:UID,
        "rcsCount", rcsList:LENGTH,
        "rcsChecksum", checksum,
        "maxAccel", LIST(maxAccel:X, maxAccel:Y, maxAccel:Z),
        "mass", SHIP:MASS
    ).
}

// getRCSSignatureProblem
// Inputs:
//   saved (Lexicon) - a signature from getRCSSignature(), taken when the RCS was tuned (for example read back from disk).
//   current (Lexicon) - the signature from getRCSSignature() now.
//   minRatio (Scalar, > 0) - lowest allowed ratio of the current to the saved maximum acceleration, on every axis.
//   maxRatio (Scalar, > minRatio) - highest allowed ratio of the current to the saved maximum acceleration, on every axis.
// Outputs:
//   String - "" if the saved tuning can still be used, otherwise a short reason it cannot: a different part count, control part
//   or RCS setup, or a maximum acceleration outside the allowed ratios. Spending propellant lowers the mass and so raises the
//   acceleration a little, which stays inside a window such as 0.7 to 1.4; a big change in mass or thrust does not.
// Side Effects:
//   None.
FUNCTION getRCSSignatureProblem {
    PARAMETER saved.
    PARAMETER current.
    PARAMETER minRatio.
    PARAMETER maxRatio.

    IF saved["partCount"] <> current["partCount"] {
        RETURN "the ship has " + current["partCount"] + " parts now and had " + saved["partCount"] + " when it was tuned".
    }
    IF saved["controlPart"] <> current["controlPart"] {
        RETURN "the ship is controlled from a different part".
    }
    IF saved["rcsCount"] <> current["rcsCount"] OR saved["rcsChecksum"] <> current["rcsChecksum"] {
        RETURN "the RCS thrusters, or their enabled directions or thrust limits, have changed".
    }

    LOCAL axisNames IS LIST("Fore", "Top", "Starboard").
    LOCAL i IS 0.
    UNTIL i >= axisNames:LENGTH {
        LOCAL savedAccel IS saved["maxAccel"][i].
        LOCAL currentAccel IS current["maxAccel"][i].
        IF savedAccel <= 0 {
            RETURN "there was no " + axisNames[i] + " RCS thrust when it was tuned".
        }
        LOCAL ratio IS currentAccel / savedAccel.
        IF ratio < minRatio OR ratio > maxRatio {
            RETURN "the " + axisNames[i] + " RCS acceleration is " + ROUND(ratio * 100) + "% of what it was when tuned (allowed " + ROUND(minRatio * 100) + "% to " + ROUND(maxRatio * 100) + "%)".
        }
        SET i TO i + 1.
    }
    RETURN "".
}
