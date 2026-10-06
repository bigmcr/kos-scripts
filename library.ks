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

LOCAL partListTree IS LEXICON().
LOCAL decouplerList IS LIST().

updateShipInfo().

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

// create and format the Ship Information lexicon.
// For the entire ship, record the following information:
//		NumberOfStages - scalar - number of stages in the current ship
//		CurrentStage - lexicon - the current stage, following the below format
// For each stage, record the following information:
//		Parts - List - containing PARTs in this stage
//		Engines - List - ENGINEs in this stage, or in the closest stage if this only has resources
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
	SET augerList TO SHIP:PARTSTITLEDPATTERN("Auger").
	SET smelterList TO SHIP:PARTSTITLEDPATTERN("Smelter").

	resourceList:CLEAR.
	FOR eachResource IN SHIP:RESOURCES {
		resourceList:ADD(eachResource:NAME, LEXICON(    "Quantity", eachResource:AMOUNT,
																								        "Mass", eachResource:AMOUNT * densityLookUp[eachResource:NAME] * 1000,
																								     "Density", densityLookUp[eachResource:NAME],
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
	LOCAL deltaVLogList IS "".
	LOCAL deltaVDisplayList IS "".
	// for each of the stages
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		LOG "Stage " + stageNumber TO fileName.
		LOG ",Parts has " + shipInfo["Stage " + stageNumber]["Parts"]:LENGTH + " Items in it,Part Name,Part Wet Mass,Unit,Stage" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Parts"] {LOG ",," + p:TITLE:REPLACE(",","") + "," + (p:MASS*1000) + ",kg," + p:STAGE TO fileName.}
		LOG ",Engines has " + shipInfo["Stage " + stageNumber]["Engines"]:LENGTH + " Items in it" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Engines"] {LOG ",," + p:CONFIG:REPLACE(",","") TO fileName.}
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
							(eachResource:AMOUNT*densityLookUp[eachResource:NAME]) + "," +
							densityLookUp[eachResource:NAME] TO fileName.
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
	//	LOG "engineType,examinedFuel,constraintFuel,requiredToPresentRatio,lowestRestraintFuelCombo[Ratio],lowestRestraintFuelCombo[examinedFuel],lowestRestraintFuelCombo[constraintFuel]," TO "0:fuels.csv".
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
//					LOG "Stage " + stageNumber + ",has,"+ shipInfo["Stage " + stageNumber]["Resources"][eachFuel] + ",kg of " + eachFuel + "" TO "0:Fuels.csv".
					SET stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] TO
							stageInfo["Fuels"][eachEngineType][eachFuel]["Mass"] +
							stageInfo["Resources"][eachFuel].
				} ELSE IF stageNumber <> 0 {
				// If the called out fuel isn't in this stage, search for it in a later stage
					FOR subStageNumber IN RANGE(stageNumber - 1, 0) {
						IF shipInfo["Stage " + subStageNumber]["Resources"]:KEYS:CONTAINS(eachFuel) {
//							LOG "Stage " + stageNumber + ",is borrowing,"+ shipInfo["Stage " + subStageNumber]["Resources"][eachFuel] + ",kg of " + eachFuel + ",from Stage " + subStageNumber TO "0:Fuels.csv".
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
//					LOG "Stage " + stageNumber + ",has,"+ shipInfo["Stage " + stageNumber]["Resources"][eachFuel] + ",kg of " + eachFuel + "" TO "0:Fuels.csv".
					SET stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] TO
							stageInfo["FuelsRCS"][eachEngineType][eachFuel]["Mass"] +
							stageInfo["Resources"][eachFuel].
				} ELSE IF stageNumber <> 0 {
				// If the called out fuel isn't in this stage, search for it in a later stage
					FOR subStageNumber IN RANGE(stageNumber - 1, 0) {
						IF shipInfo["Stage " + subStageNumber]["Resources"]:KEYS:CONTAINS(eachFuel) {
//							LOG "Stage " + stageNumber + ",is borrowing,"+ shipInfo["Stage " + subStageNumber]["Resources"][eachFuel] + ",kg of " + eachFuel + ",from Stage " + subStageNumber TO "0:Fuels.csv".
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
		LOCAL fuelMass IS 0.
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
			IF loggedResources:CONTAINS(eachResource:NAME) SET message TO message + "," + eachResource:AMOUNT + "," + eachResource:AMOUNT * densityLookUp[eachResource:NAME].
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
											 densityLookUp[fuelName],
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
	IF (createlogFileName) {
		LOG "Time,Longitude,Latitude,Terrain Height" TO "Terrain Heights.csv".
		FOR smallList IN heightList {
			LOG smallList[0] + "," + smallList[1] + "," + smallList[2] + "," + smallList[3] TO "Terrain Heights.csv".
		}
	}
	RETURN LEXICON("min",minHeight,"max",averageHeight,"avg",averageHeight).
}

// Generic hill climbing function
// Tries to minimize the value of the passed delegate.
// Passed the following
//			delegate, expecting a single scalar input and returns a single scalar
//			initialGuess - initial guess of the final value
//			initialStepSize - how much to start moving the initial guess by
//			logFileName - log file name. If blank, does not log. Defaults to blank.
//			iterationMax - maximum iteration number. Defaults to 1000.
//			smallestStepRatio - Ratio of smallest step size to initial step size
//        (negative power of 2). Defaults to 15, so the smallest step size
//        would be initialStepSize / (2^15).
//			cyclicalPeriod - period of cyclical repition in the input of the delegate.
//        -1 is a special case that indicates input is not cyclical.
//        Defaults to -1.
//			cyclicalPeriodCutoff - value below which cyclicalPeriod should be added to the current guess.
//			deleteOldlogFileName - whether to delete the old version of the log file
//				or append to the end of the file.
// Returns the following:
//			Lexicon with the following members:
//				"iteration" - scalar - number of the final iteration
//				"initialValue" - scalar - value of the delegate given the initial guess
//				"initialGuess" - scalar - value of the initial guess
//				"finalValue" - scalar - value of the delegate given the final guess. This is minimized.
//				"finalGuess" - scalar - value of the final guess
//				"deltaValue" - scalar - how much the delegate changed
// A few notes about the delegate:
//    It is assumed that the delegate recieves a single scalar input and returns a single scalar.
//    This function is a minimization function; if you want it to maximimze instead, make the delegate return a negative.
FUNCTION hillClimb {
	PARAMETER delegate.
	PARAMETER initialGuess.
	PARAMETER initialStepSize.
	PARAMETER logFileName IS "".
	PARAMETER iterationMax IS 100.
	PARAMETER smallestStepRatio IS 15.
	PARAMETER cyclicalPeriod IS -1.
	PARAMETER cyclicalPeriodCutoff IS 0.
	PARAMETER deleteOldlogFileName IS TRUE.
	
	IF initialStepSize = 0 OR delegate:TYPENAME <> "KOSDelegate" {
		RETURN LEXICON("iteration", -1,
										  "initialValue", delegate(initialGuess),
										  "initialGuess", initialGuess,
										  "finalValue", delegate(initialGuess),
										  "finalGuess", initialGuess,
										  "deltaValue", 0).
	}

	LOCAL logDataPerm IS (logFileName <> "").
	IF logFileName:STARTSWITH("0:") AND NOT connectionToKSC() SET logDataPerm TO FALSE.
	LOCAL stepSize IS initialStepSize.
	LOCAL smallestStep IS initialStepSize / (2^smallestStepRatio).
	LOCAL iteration IS 0.
	LOCAL currentDelegate IS 0.
	LOCAL currentPlusDelegate IS 0.
	LOCAL currentMinusDelegate IS 0.
	IF deleteOldlogFileName AND logDataPerm AND EXISTS(logFileName) DELETEPATH(logFileName).
	IF logDataPerm LOG "Iteration,Power of 2,Current Guess,Step Size,Delegate at Current Guess,Delegate at Current Guess + Step,Delegate at Current Guess - Step" TO logFileName.
	LOCAL currentGuess IS initialGuess.
	LOCAL currentDelegate IS delegate(currentGuess).
	LOCAL knownInitialValue IS currentDelegate.

	UNTIL (stepSize <= smallestStep) OR (iteration > iterationMax) {
		LOCAL currentPlusDelegate IS delegate(currentGuess + stepSize).
		LOCAL currentMinusDelegate IS delegate(currentGuess - stepSize).

		IF currentPlusDelegate < currentDelegate {
			SET currentGuess TO currentGuess + stepSize.
			SET currentDelegate TO currentPlusDelegate.
		} ELSE IF currentMinusDelegate < currentDelegate {
			SET currentGuess TO currentGuess - stepSize.
			SET currentDelegate TO currentMinusDelegate.
		} ELSE {
			SET stepSize TO stepSize / 2.
		}
		SET iteration TO iteration + 1.
		IF cyclicalPeriod <> -1 {
			SET currentGuess TO MOD(currentGuess - cyclicalPeriodCutoff, cyclicalPeriod) + cyclicalPeriodCutoff.
			IF currentGuess < cyclicalPeriodCutoff SET currentGuess TO currentGuess + cyclicalPeriod.
		}
	}
	LOCAL initialValue IS knownInitialValue.
	LOCAL finalValue IS currentDelegate.
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("iteration", iteration - 1).
	returnMe:ADD("initialValue", initialValue).
	returnMe:ADD("initialGuess", initialGuess).
	returnMe:ADD("finalValue", finalValue).
	returnMe:ADD("finalGuess", currentGuess).
	returnMe:ADD("deltaValue", finalValue - initialValue).
	RETURN returnMe.
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

// Generic 2D hill climbing function
// Tries to minimize the value of the passed delegate, which takes two scalar
// inputs and returns a single scalar.
// Unlike a pair of independent 1D hill climbs, this searches the full 8-point
// neighborhood (N, S, E, W, and the four diagonals) around the current guess
// each iteration, so it can follow gradients that aren't aligned to either axis.
// Passed the following
//			delegate, expecting two scalar inputs and returning a single scalar
//			initialGuess1 - initial guess of the final value along axis 1
//			initialGuess2 - initial guess of the final value along axis 2
//			initialStepSize1 - how much to start moving the initial guess by, axis 1
//			initialStepSize2 - how much to start moving the initial guess by, axis 2
//			logFileName - log file name. If blank, does not log. Defaults to blank.
//			iterationMax - maximum iteration number. Defaults to 100.
//			smallestStepRatio - Ratio of smallest step size to initial step size
//				(negative power of 2), applied independently to each axis. Defaults
//				to 15, so the smallest step size would be initialStepSize / (2^15).
//			cyclicalPeriod1 - period of cyclical repetition of axis 1's input.
//				-1 is a special case that indicates axis 1 is not cyclical. Defaults to -1.
//			cyclicalPeriodCutoff1 - value below which cyclicalPeriod1 should be added
//				to the current guess for axis 1.
//			cyclicalPeriod2 - as cyclicalPeriod1, but for axis 2. Defaults to -1.
//			cyclicalPeriodCutoff2 - as cyclicalPeriodCutoff1, but for axis 2.
//			deleteOldlogFileName - whether to delete the old version of the log file
//				or append to the end of the file.
// Returns the following:
//			Lexicon with the following members:
//				"iteration" - scalar - number of the final iteration
//				"initialValue" - scalar - value of the delegate given the initial guess
//				"initialGuess1" - scalar - value of the initial guess, axis 1
//				"initialGuess2" - scalar - value of the initial guess, axis 2
//				"finalValue" - scalar - value of the delegate given the final guess. This is minimized.
//				"finalGuess1" - scalar - value of the final guess, axis 1
//				"finalGuess2" - scalar - value of the final guess, axis 2
//				"deltaValue" - scalar - how much the delegate changed
// A few notes about the delegate:
//    It is assumed that the delegate receives two scalar inputs and returns
//    a single scalar. This function is a minimization function; if you want
//    it to maximize instead, make the delegate return a negative.
//    Because this checks 8 neighbors per iteration (versus 2 or 3 for the 1D
//    version), it is roughly 4x more expensive per iteration - keep that in
//    mind if the delegate itself is costly (e.g. involves POSITIONAT/VELOCITYAT).
FUNCTION hillClimb2D {
	PARAMETER delegate.
	PARAMETER initialGuess1.
	PARAMETER initialGuess2.
	PARAMETER initialStepSize1.
	PARAMETER initialStepSize2.
	PARAMETER logFileName IS "".
	PARAMETER iterationMax IS 100.
	PARAMETER smallestStepRatio IS 15.
	PARAMETER cyclicalPeriod1 IS -1.
	PARAMETER cyclicalPeriodCutoff1 IS 0.
	PARAMETER cyclicalPeriod2 IS -1.
	PARAMETER cyclicalPeriodCutoff2 IS 0.
	PARAMETER deleteOldlogFileName IS TRUE.

	LOCAL logDataPerm IS (logFileName <> "").
	IF logFileName:STARTSWITH("0:") AND NOT connectionToKSC() SET logDataPerm TO FALSE.

	// guard against a zero step size on either axis, which would otherwise
	// make the smallest-step floor zero and exit the loop before it starts.
	IF initialStepSize1 = 0 SET initialStepSize1 TO 0.001.
	IF initialStepSize2 = 0 SET initialStepSize2 TO 0.001.

	LOCAL stepSize1 IS initialStepSize1.
	LOCAL stepSize2 IS initialStepSize2.
	LOCAL smallestStep1 IS initialStepSize1 / (2^smallestStepRatio).
	LOCAL smallestStep2 IS initialStepSize2 / (2^smallestStepRatio).
	LOCAL iteration IS 0.

	IF deleteOldlogFileName AND logDataPerm AND EXISTS(logFileName) DELETEPATH(logFileName).
	IF logDataPerm LOG "Iteration,Guess1,Guess2,Step1,Step2,Current Delegate,Neighbor,Neighbor Delegate,Moved" TO logFileName.

	LOCAL currentGuess1 IS initialGuess1.
	LOCAL currentGuess2 IS initialGuess2.
	LOCAL currentDelegate IS delegate(currentGuess1, currentGuess2).
	LOCAL initialValue IS currentDelegate.

	// 3x3 grid of (offset1, offset2) labels, skipping the center (0,0).
	// Ordered N, NE, E, SE, S, SW, W, NW purely for readable logs.
	LOCAL neighborLabels IS LIST("N", "NE", "E", "SE", "S", "SW", "W", "NW").

	UNTIL ((stepSize1 <= smallestStep1) AND (stepSize2 <= smallestStep2)) OR (iteration > iterationMax) {
		LOCAL neighborOffsets IS LIST(
			LIST(       0,  stepSize2), 	// N
			LIST( stepSize1,  stepSize2),	// NE
			LIST( stepSize1,        0),		// E
			LIST( stepSize1, -stepSize2),	// SE
			LIST(       0, -stepSize2),		// S
			LIST(-stepSize1, -stepSize2),	// SW
			LIST(-stepSize1,        0),		// W
			LIST(-stepSize1,  stepSize2)	// NW
		).

		LOCAL bestValue IS currentDelegate.
		LOCAL bestGuess1 IS currentGuess1.
		LOCAL bestGuess2 IS currentGuess2.
		LOCAL bestLabel IS "None".
		LOCAL neighborValue IS 0.
		LOCAL testGuess1 IS 0.
		LOCAL testGuess2 IS 0.

		FOR neighborIndex IN RANGE(0, neighborOffsets:LENGTH) {
			SET testGuess1 TO currentGuess1 + neighborOffsets[neighborIndex][0].
			SET testGuess2 TO currentGuess2 + neighborOffsets[neighborIndex][1].
			SET neighborValue TO delegate(testGuess1, testGuess2).

			IF logDataPerm LOG iteration + "," + testGuess1 + "," + testGuess2 + "," + stepSize1 + "," + stepSize2 + "," + currentDelegate + "," + neighborLabels[neighborIndex] + "," + neighborValue + "," + (neighborValue < bestValue) TO logFileName.

			IF neighborValue < bestValue {
				SET bestValue TO neighborValue.
				SET bestGuess1 TO testGuess1.
				SET bestGuess2 TO testGuess2.
				SET bestLabel TO neighborLabels[neighborIndex].
			}
			WAIT 0.
		}

		IF bestLabel = "None" {
			// no neighbor improved on the current point; shrink whichever
			// axis step size(s) haven't hit their floor yet, and try again.
			IF stepSize1 > smallestStep1 SET stepSize1 TO stepSize1 / 2.
			IF stepSize2 > smallestStep2 SET stepSize2 TO stepSize2 / 2.
		} ELSE {
			SET currentGuess1 TO bestGuess1.
			SET currentGuess2 TO bestGuess2.
			SET currentDelegate TO bestValue.
		}

		// symmetric cyclical wraparound, applied independently per axis
		IF cyclicalPeriod1 <> -1 {
			SET currentGuess1 TO MOD(currentGuess1 - cyclicalPeriodCutoff1, cyclicalPeriod1).
			IF currentGuess1 < 0 SET currentGuess1 TO currentGuess1 + cyclicalPeriod1.
			SET currentGuess1 TO currentGuess1 + cyclicalPeriodCutoff1.
		}
		IF cyclicalPeriod2 <> -1 {
			SET currentGuess2 TO MOD(currentGuess2 - cyclicalPeriodCutoff2, cyclicalPeriod2).
			IF currentGuess2 < 0 SET currentGuess2 TO currentGuess2 + cyclicalPeriod2.
			SET currentGuess2 TO currentGuess2 + cyclicalPeriodCutoff2.
		}

		SET iteration TO iteration + 1.
		// This is present because kOS has odd results when complex calcualtions are spread across different physics ticks.
	}

	LOCAL returnMe IS LEXICON().
	returnMe:ADD("iteration", iteration).
	returnMe:ADD("initialValue", initialValue).
	returnMe:ADD("initialGuess1", initialGuess1).
	returnMe:ADD("initialGuess2", initialGuess2).
	returnMe:ADD("finalValue", currentDelegate).
	returnMe:ADD("finalGuess1", currentGuess1).
	returnMe:ADD("finalGuess2", currentGuess2).
	returnMe:ADD("deltaValue", currentDelegate - initialValue).
	RETURN returnMe.
}

// ============================================================================
// Gradient ascent / descent for a 2-input scalar delegate.
//
// This is intentionally written to sit alongside hillClimb2D in library.ks and
// share its calling convention (a 2-argument delegate, a LEXICON result with
// the same key names) so the two can be swapped for one another easily.
//
// See the accompanying explanation for how this differs from hillClimb2D:
// hillClimb2D is a derivative-free "compass search" (it only ever asks
// "is this neighbor better or worse?" at 8 fixed points a fixed step away),
// while gradientDescent2D estimates the actual slope of the delegate via
// finite differences and moves continuously along it, with a step size that
// naturally shrinks as the slope flattens out near an optimum.
// ============================================================================

// Estimates the partial derivatives of a 2-argument delegate at (guess1, guess2)
// using a central finite difference: (f(x+h) - f(x-h)) / (2h). Central
// differences are used instead of forward differences (f(x+h) - f(x)) / h)
// because they're second-order accurate rather than first-order - i.e. the
// error shrinks with h^2 instead of just h, which matters a lot here since
// gradientStepSize (h) also has to be small enough not to blur out real
// curvature in the delegate's surface.
// Passed the following:
//			delegate, expecting two scalar inputs and returning a single scalar
//			guess1, guess2 - the point to estimate the gradient at
//			gradientStepSize - h, the finite-difference offset
// Returns a LEXICON with "d1" (partial derivative w.r.t. input 1) and
// "d2" (partial derivative w.r.t. input 2).
FUNCTION estimateGradient2D {
	PARAMETER delegate.
	PARAMETER guess1.
	PARAMETER guess2.
	PARAMETER gradientStepSize.

	LOCAL d1 IS (delegate(guess1 + gradientStepSize, guess2) - delegate(guess1 - gradientStepSize, guess2)) / (2 * gradientStepSize).
	LOCAL d2 IS (delegate(guess1, guess2 + gradientStepSize) - delegate(guess1, guess2 - gradientStepSize)) / (2 * gradientStepSize).

	RETURN LEXICON("d1", d1, "d2", d2).
}

// Generic 2D gradient ascent / descent function.
// Minimizes (or maximizes, if ascend is TRUE) the value of the passed delegate,
// which takes two scalar inputs and returns a single scalar, by repeatedly
// estimating the local gradient and stepping along it (downhill to minimize,
// uphill to maximize), scaled by learningRate.
//
// Includes simple backtracking: if a proposed step does not actually improve
// the delegate's value (which can happen if learningRate is too large for the
// local curvature - the classic gradient descent failure mode is overshooting
// past a minimum), learningRate is halved and the same gradient is retried,
// rather than taking the bad step. This is a much cheaper stand-in for a full
// line search, and is the direct analog of hillClimb2D halving its step size
// when no neighbor improves on the current point.
//
// Passed the following:
//			delegate - expects two scalar inputs, returns a single scalar
//			initialGuess1, initialGuess2 - starting point
//			initialLearningRate - initial multiplier applied to the gradient
//        each step (this is the "step size" of gradient descent - unlike
//        hillClimb2D's fixed compass-direction step, the actual distance
//        moved is learningRate * |gradient|, so it shrinks on its own as
//        the surface flattens out near an optimum)
//			gradientStepSize - h used for the finite-difference gradient estimate.
//        Defaults to a small fraction of the learning rate; pass this
//        explicitly if the delegate's inputs are on a very different scale
//        than its output.
//			gradientTolerance - stop once the gradient's magnitude drops below
//        this value (i.e. the surface is locally ~flat - an optimum).
//        Defaults to a small number; tune to the scale of the delegate.
//			iterationMax - maximum number of accepted steps. Defaults to 100.
//			maxBacktracks - maximum number of learningRate halvings to try in a
//        single iteration before giving up and treating the search as
//        converged (learningRate has become negligible). Defaults to 30.
//			ascend - IF TRUE, maximizes the delegate instead of minimizing it.
//        Defaults to FALSE (minimize), matching hillClimb2D's convention.
//			logFileName - log file name. If blank, does not log. Defaults to blank.
//			cyclicalPeriod1 / cyclicalPeriodCutoff1 - as in hillClimb2D: if axis 1
//        wraps around (e.g. an angle or an orbital phase), pass the period
//        here so the guess gets wrapped back into range each iteration.
//        -1 means "not cyclical". Defaults to -1.
//			cyclicalPeriod2 / cyclicalPeriodCutoff2 - as above, for axis 2.
//			deleteOldlogFileName - whether to delete the old version of the log
//        file or append to the end of it. Defaults to TRUE.
// Returns the following:
//			Lexicon with the following members (same shape as hillClimb2D's return,
//      so the two are interchangeable at the call site):
//				"iteration" - scalar - number of accepted steps taken
//				"initialValue" - scalar - delegate's value at the initial guess
//				"initialGuess1" / "initialGuess2" - the starting point
//				"finalValue" - scalar - delegate's value at the final guess
//				"finalGuess1" / "finalGuess2" - the final point
//				"deltaValue" - scalar - how much the delegate's value changed
//				"finalGradientMagnitude" - scalar - |gradient| at the final guess;
//        useful for confirming whether the search actually converged
//        (small) or bailed out on exhausted backtracks (still large)
FUNCTION gradientDescent2D {
	PARAMETER delegate.
	PARAMETER initialGuess1.
	PARAMETER initialGuess2.
	PARAMETER initialLearningRate.
	PARAMETER gradientStepSize IS initialLearningRate / 100.
	PARAMETER gradientTolerance IS 1e-6.
	PARAMETER iterationMax IS 100.
	PARAMETER maxBacktracks IS 30.
	PARAMETER ascend IS FALSE.
	PARAMETER logFileName IS "".
	PARAMETER cyclicalPeriod1 IS -1.
	PARAMETER cyclicalPeriodCutoff1 IS 0.
	PARAMETER cyclicalPeriod2 IS -1.
	PARAMETER cyclicalPeriodCutoff2 IS 0.
	PARAMETER deleteOldlogFileName IS TRUE.

	IF (initialLearningRate = 0) OR (NOT delegate:ISTYPE("UserDelegate")) {
		LOCAL fallbackValue IS delegate(initialGuess1, initialGuess2).
		RETURN LEXICON("iteration", -1,
									  "initialValue", fallbackValue,
									  "initialGuess1", initialGuess1,
									  "initialGuess2", initialGuess2,
									  "finalValue", fallbackValue,
									  "finalGuess1", initialGuess1,
									  "finalGuess2", initialGuess2,
									  "deltaValue", 0,
									  "finalGradientMagnitude", 0).
	}

	LOCAL logDataPerm IS (logFileName <> "").
	IF logFileName:STARTSWITH("0:") AND NOT connectionToKSC() SET logDataPerm TO FALSE.
	IF deleteOldlogFileName AND logDataPerm AND EXISTS(logFileName) DELETEPATH(logFileName).
	IF logDataPerm LOG "Iteration,Guess1,Guess2,Value,Gradient1,Gradient2,GradientMag,LearningRate,Backtracks" TO logFileName.

	// ascending and descending are the same algorithm with the sign of the step
	// flipped - climb the gradient uphill instead of stepping downhill against it.
	LOCAL directionSign IS 1.
	IF ascend SET directionSign TO -1.

	LOCAL currentGuess1 IS initialGuess1.
	LOCAL currentGuess2 IS initialGuess2.
	LOCAL currentValue IS delegate(currentGuess1, currentGuess2).
	LOCAL knownInitialValue IS currentValue.
	LOCAL learningRate IS initialLearningRate.

	LOCAL iteration IS 0.
	LOCAL gradientMagnitude IS gradientTolerance + 1. // anything > tolerance, just to enter the loop

	UNTIL (gradientMagnitude <= gradientTolerance) OR (iteration >= iterationMax) {
		LOCAL gradient IS estimateGradient2D(delegate, currentGuess1, currentGuess2, gradientStepSize).
		SET gradientMagnitude TO SQRT(gradient["d1"]^2 + gradient["d2"]^2).

		IF gradientMagnitude <= gradientTolerance {
			IF logDataPerm LOG iteration + "," + currentGuess1 + "," + currentGuess2 + "," + currentValue + "," +
				gradient["d1"] + "," + gradient["d2"] + "," + gradientMagnitude + "," + learningRate + ",converged" TO logFileName.
			BREAK.
		}

		// backtracking: try the full learning rate first, halving it until the
		// step actually improves on currentValue (or we give up on this iteration)
		LOCAL backtracks IS 0.
		LOCAL stepAccepted IS FALSE.
		LOCAL testGuess1 IS currentGuess1.
		LOCAL testGuess2 IS currentGuess2.
		LOCAL testValue IS currentValue.

		UNTIL stepAccepted OR (backtracks >= maxBacktracks) {
			SET testGuess1 TO currentGuess1 - directionSign * learningRate * gradient["d1"].
			SET testGuess2 TO currentGuess2 - directionSign * learningRate * gradient["d2"].
			SET testValue TO delegate(testGuess1, testGuess2).

			LOCAL improved IS FALSE.
			IF ascend SET improved TO (testValue > currentValue).
			ELSE SET improved TO (testValue < currentValue).

			IF improved {
				SET stepAccepted TO TRUE.
			} ELSE {
				SET learningRate TO learningRate / 2.
				SET backtracks TO backtracks + 1.
			}
		}

		IF logDataPerm LOG iteration + "," + currentGuess1 + "," + currentGuess2 + "," + currentValue + "," +
			gradient["d1"] + "," + gradient["d2"] + "," + gradientMagnitude + "," + learningRate + "," + backtracks TO logFileName.

		IF NOT stepAccepted {
			// learningRate has been halved maxBacktracks times and still can't find
			// an improving step - the gradient estimate is unreliable this close in
			// (often floating-point noise at the scale of gradientStepSize), so stop.
			BREAK.
		}

		SET currentGuess1 TO testGuess1.
		SET currentGuess2 TO testGuess2.
		SET currentValue TO testValue.

		IF cyclicalPeriod1 <> -1 {
			SET currentGuess1 TO MOD(currentGuess1 - cyclicalPeriodCutoff1, cyclicalPeriod1) + cyclicalPeriodCutoff1.
			IF currentGuess1 < cyclicalPeriodCutoff1 SET currentGuess1 TO currentGuess1 + cyclicalPeriod1.
		}
		IF cyclicalPeriod2 <> -1 {
			SET currentGuess2 TO MOD(currentGuess2 - cyclicalPeriodCutoff2, cyclicalPeriod2) + cyclicalPeriodCutoff2.
			IF currentGuess2 < cyclicalPeriodCutoff2 SET currentGuess2 TO currentGuess2 + cyclicalPeriod2.
		}

		SET iteration TO iteration + 1.
	}

	LOCAL returnMe IS LEXICON().
	returnMe:ADD("iteration", iteration).
	returnMe:ADD("initialValue", knownInitialValue).
	returnMe:ADD("initialGuess1", initialGuess1).
	returnMe:ADD("initialGuess2", initialGuess2).
	returnMe:ADD("finalValue", currentValue).
	returnMe:ADD("finalGuess1", currentGuess1).
	returnMe:ADD("finalGuess2", currentGuess2).
	returnMe:ADD("deltaValue", currentValue - knownInitialValue).
	returnMe:ADD("finalGradientMagnitude", gradientMagnitude).
	RETURN returnMe.
}

// Golden-section search for the minimum of costDelegate(x) on [lowBound, highBound].
// Returns the x of the minimum. Derivative-free; assumes the cost is unimodal
// there, which holds for the narrow brackets this file uses.
FUNCTION goldenSectionMinimum {
	PARAMETER costDelegate.
	PARAMETER lowBound.
	PARAMETER highBound.
	PARAMETER iterations IS 14.

	LOCAL inversePhi IS (SQRT(5) - 1) / 2.
	LOCAL low IS lowBound.
	LOCAL high IS highBound.
	LOCAL probeLow IS high - inversePhi * (high - low).
	LOCAL probeHigh IS low + inversePhi * (high - low).
	LOCAL costLow IS costDelegate(probeLow).
	LOCAL costHigh IS costDelegate(probeHigh).

	FROM {LOCAL pass IS 0.} UNTIL pass >= iterations STEP {SET pass TO pass + 1.} DO {
		IF costLow < costHigh {
			SET high TO probeHigh.
			SET probeHigh TO probeLow.
			SET costHigh TO costLow.
			SET probeLow TO high - inversePhi * (high - low).
			SET costLow TO costDelegate(probeLow).
		} ELSE {
			SET low TO probeLow.
			SET probeLow TO probeHigh.
			SET costLow TO costHigh.
			SET probeHigh TO low + inversePhi * (high - low).
			SET costHigh TO costDelegate(probeHigh).
		}
	}
	RETURN (low + high) / 2.
}

// Newton refinement of a minimum in two variables - the end game of the hill climb below.
// Near a minimum a smooth cost is nearly a bowl, so instead of walking down it (the hill climb
// halves its step and re-prices 8 neighbours each time) this fits the bowl and jumps to its bottom.
//   Each step prices a 3x3 patch around the current point (the centre is already known, so 8 new
//   points), fits the slope and curvature from it, and moves to the minimum of the fitted bowl:
//       slope     = (f(+h) - f(-h)) / 2h on each axis
//       curvature = (f(+h) - 2f(0) + f(-h)) / h^2 on each axis, and a cross term from the four corners
//       move      = -(curvature matrix)^-1 * slope
//   The move is capped at two patch widths per axis, and is only taken if it beats every point already
//   priced: otherwise the best point of the patch is taken if that improves on the current one (a patch
//   whose curvature does not describe a bowl gets only that). Each later step uses half the patch width.
//   Two steps cost about 18 evaluations. (In a test on a Lambert porkchop surface, a hill climb stopped
//   at 1/8 of the grid spacing followed by two of these steps took 60 evaluations against 72 for the
//   full hill climb, and found the minimum to within 0.5 m/s in every case against 40% of them.)
//   costDelegate - f(guess1, guess2) -> value, to be minimized
//   startGuess1/2, startValue - the point to refine and its value
//   startStep1/2 - the patch half-width on each axis for the first step (the hill climb's final step)
//   newtonSteps  - how many steps to take
// Returns a LEXICON: "finalValue", "finalGuess1", "finalGuess2", "evaluations", and "steps" (how many
// of the newtonSteps steps actually moved the point to a better one).
FUNCTION newtonRefine2D {
	PARAMETER costDelegate.
	PARAMETER startGuess1.
	PARAMETER startGuess2.
	PARAMETER startValue.
	PARAMETER startStep1.
	PARAMETER startStep2.
	PARAMETER newtonSteps IS 2.

	LOCAL guess1 IS startGuess1.
	LOCAL guess2 IS startGuess2.
	LOCAL currentValue IS startValue.
	LOCAL step1 IS startStep1.
	LOCAL step2 IS startStep2.
	LOCAL evaluations IS 0.
	LOCAL stepsTaken IS 0.

	FROM {LOCAL newtonStep IS 1.} UNTIL newtonStep > newtonSteps STEP {SET newtonStep TO newtonStep + 1.} DO {
		// The 3x3 patch, stored flat: position 3*i + j is the point at (guess1 + (i-1)*step1, guess2 + (j-1)*step2).
		LOCAL patch IS LIST(0, 0, 0, 0, currentValue, 0, 0, 0, 0).
		LOCAL bestPatchValue IS currentValue.
		LOCAL bestPatch1 IS guess1.
		LOCAL bestPatch2 IS guess2.
		FOR patchIndex IN LIST(0, 1, 2, 3, 5, 6, 7, 8) {
			LOCAL point1 IS guess1 + (FLOOR(patchIndex / 3) - 1) * step1.
			LOCAL point2 IS guess2 + (MOD(patchIndex, 3) - 1) * step2.
			LOCAL pointValue IS costDelegate(point1, point2).
			SET evaluations TO evaluations + 1.
			SET patch[patchIndex] TO pointValue.
			IF pointValue < bestPatchValue {
				SET bestPatchValue TO pointValue.
				SET bestPatch1 TO point1.
				SET bestPatch2 TO point2.
			}
			WAIT 0.
		}

		LOCAL slope1 IS (patch[7] - patch[1]) / (2 * step1).
		LOCAL slope2 IS (patch[5] - patch[3]) / (2 * step2).
		LOCAL curvature11 IS (patch[7] - 2 * patch[4] + patch[1]) / step1 ^ 2.
		LOCAL curvature22 IS (patch[5] - 2 * patch[4] + patch[3]) / step2 ^ 2.
		LOCAL curvature12 IS (patch[8] - patch[6] - patch[2] + patch[0]) / (4 * step1 * step2).
		LOCAL determinant IS curvature11 * curvature22 - curvature12 ^ 2.

		// Where this step ends up: the best patch point, unless the fitted bowl's bottom does better.
		LOCAL nextValue IS bestPatchValue.
		LOCAL next1 IS bestPatch1.
		LOCAL next2 IS bestPatch2.
		IF curvature11 > 0 AND determinant > 0 {
			LOCAL move1 IS -(curvature22 * slope1 - curvature12 * slope2) / determinant.
			LOCAL move2 IS -(curvature11 * slope2 - curvature12 * slope1) / determinant.
			LOCAL overshoot IS MAX(ABS(move1) / (2 * step1), ABS(move2) / (2 * step2)).
			IF overshoot > 1 {
				SET move1 TO move1 / overshoot.
				SET move2 TO move2 / overshoot.
			}
			LOCAL bowlValue IS costDelegate(guess1 + move1, guess2 + move2).
			SET evaluations TO evaluations + 1.
			WAIT 0.
			IF bowlValue < nextValue {
				SET nextValue TO bowlValue.
				SET next1 TO guess1 + move1.
				SET next2 TO guess2 + move2.
			}
		}

		IF nextValue < currentValue {
			SET currentValue TO nextValue.
			SET guess1 TO next1.
			SET guess2 TO next2.
			SET stepsTaken TO stepsTaken + 1.
		}
		SET step1 TO step1 / 2.
		SET step2 TO step2 / 2.
	}

	RETURN LEXICON("finalValue", currentValue, "finalGuess1", guess1, "finalGuess2", guess2, "evaluations", evaluations, "steps", stepsTaken).
}

// Return the vector pointing in the direction of downslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of downhill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of downhill in a vector with length of 1 meter.
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

// Return the vector pointing in the direction of upslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of uphill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of uphill in a vector with length of 1 meter.
FUNCTION findDownSlopeInfo {
	PARAMETER northOffset IS 0.0.
	PARAMETER eastOffset IS 0.0.
	PARAMETER distance IS 5.0.
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
	UNTIL (VANG(SHIP:FACING:VECTOR, STEERINGMANAGER:TARGET:VECTOR) < 0.1 AND STEERINGMANAGER:ROLLERROR < 0.1 AND rollRate < 0.01) {
		IF (previousTime <> 0) SET rollRate TO (roll_for(SHIP) - previousRoll)/(previousTime - TIME:SECONDS).
		SET previousRoll TO roll_for(SHIP).
		SET previousTime TO TIME:SECONDS.
		WAIT 0.1.
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
				SET metersNorth TO ((i - dataOriginal:LENGTH/2) * delta).
				SET metersEast TO ((j - dataOriginal:LENGTH/2) * delta).
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
			SET mDot_max TO mDot_max + eng:MAXMASSFLOW * 1000.
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

// Calculate Engine Stats for RCS engines
// This function calculates a few important stats of a list of engines.
// It assumes that all engines are fired in current atmospheric conditions.
// Passed the following
//			list of RCS engines (list containing type "part", unitless)
// Returns a list of the following:
//			effective Isp (scalar, s)
//			maximum thrust (scalar, Newtons)
//			maximum mDot (scalar, kg/s)
FUNCTION engineStatsRCS {
	PARAMETER engineList.
	IF (engineList:LENGTH = 0) RETURN LEXICON("Isp", 0,
																				 "thrustMax", 0,
																				 "mDotMax", 0).

	LOCAL mDot_max IS 0.												// Rate of change of mass for the primary engine, with throttle at 100% (kg/s)
	LOCAL F_max IS 0.														// Full thrust (N)

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
// Passed the following
//			input (vessel, vector or direction)
// Returns the following:
//			heading of input (scalar, degrees from north)
FUNCTION yaw_for {
  PARAMETER input.
	LOCAL pointing IS V(0,0,0).
	     IF input:TYPENAME = "vessel" 		SET pointing TO input:FACING:FOREVECTOR.
	ELSE IF input:TYPENAME = "vector"     SET pointing TO input.
	ELSE IF input:TYPENAME = "direction"  SET pointing TO input:VECTOR.

  LOCAL east IS east_for(SHIP).

  LOCAL trig_x IS VDOT(SHIP:NORTH:VECTOR, pointing).
  LOCAL trig_y IS VDOT(east, pointing).

  LOCAL result IS ARCTAN2(trig_y, trig_x).

  IF result < 0 RETURN 360 + result.
  RETURN result.
}

// Pitch For
// This function recieves a vessel, vector or direction and returns the pitch (degrees above horizon) that the input is pointing toward
// Passed the following
//			input (vessel, vector or direction)
// Returns the following:
//			pitch of vector (scalar, degrees above (or below, for negative) the horizon)
FUNCTION pitch_for {
  PARAMETER input.
	LOCAL pointing IS V(0,0,0).
	     IF input:TYPENAME = "vessel" 		SET pointing TO input:FACING:FOREVECTOR.
	ELSE IF input:TYPENAME = "vector"     SET pointing TO input.
	ELSE IF input:TYPENAME = "direction"  SET pointing TO input:VECTOR.

  RETURN 90 - VANG(SHIP:UP:vector, pointing).
}

// Roll For
// This function recieves a vessel and returns the roll of the vessel
// Passed the following
//			vessel to be looked at (vessel)
// Returns the following:
//			roll of vector (scalar, degrees off of horizontal)
function roll_for {
  parameter ves.

  if vang(ship:facing:vector,ship:up:vector) < 0.2 { //this is the dead zone for roll when the ship is vertical
    return 0.
  } else {
    local raw is vang(vxcl(ship:facing:vector,ship:up:vector), ves:facing:starvector).
    if vang(ves:up:vector, ves:facing:topvector) > 90 {
      if raw > 90 {
        return 270 - raw.
      } else {
        return -90 - raw.
      }
    } else {
      return raw - 90.
    }
  }
}.

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
//			the rounded vector
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
			FOR mod IN MODS {
				IF (mod="ModuleRTAntenna") {
					IF NOT (eachPart:GETMODULE("ModuleRTAntenna"):HASFIELD("dish range")) {
						SET isAntenna TO TRUE.
					}
				}
				IF (mod="ModuleDeployableAntenna") {
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
			FOR mod IN MODS {
				IF (mod="ModuleRTAntenna") {
					IF NOT (eachPart:GETMODULE("ModuleRTAntenna"):HASFIELD("dish range")) {
						SET isAntenna TO TRUE.
					}
				}
				IF (mod="ModuleDeployableAntenna") {
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
		FOR mod IN MODS {
			IF (mod="ModuleRTAntenna") {
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
		FOR mod IN MODS {
			IF (mod="ModuleRTAntenna") {
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
			IF isStockRockets() SET engTitle TO eng:CONFIG:SUBSTRING(0, eng:CONFIG:FINDLAST(CHAR(34)) + 1).
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
			PRINT engType:TOSTRING:PADLEFT(maxLength) + " " + ROUND(engineStat["Thrust"] / engineStat["thrustMax"] * 100) + "%" AT (X + 1 , Y + 1 + COUNT).
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
					SET resourceList[eachResource:NAME] TO resourceList[eachResource:NAME] + eachResource:AMOUNT*densityLookUp[eachResource:NAME].
				}
				// if the resource is not already in the resource list, add the resource to the list
				ELSE {
					resourceList:ADD(eachResource:NAME, eachResource:AMOUNT*densityLookUp[eachResource:NAME]).
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
// example: given 90090.124 (seconds) and in the realistic universe,
//		the function will return "1 d, 1 h, 1 m, 30.12 s"
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
	IF digits > 0 SET seconds TO ROUND( MOD( T, 60), digits).
	ELSE SET seconds TO ROUND( MOD( T, 60), 0).

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

	IF T = 0 SET message TO "0s".

	RETURN message.
}

// given a number, returns a string of the number broken down to Tm, Gm, Mm, km, meters or centimeters.
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
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Velocity Y,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:VELOCITY:ORBIT:Y + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	SET message TO "Velocity Z,".
	FOR eachOrbit IN orbs {SET message TO message + eachOrbit:VELOCITY:ORBIT:Z + ",".}
	SET message TO message + "m".
	LOG message TO fileName.

	// Add a blank line to the end - it helps to differentiate between runs
	LOG "" TO fileName.
}

// get desired launch azimuth given desired circular orbit altitude and inclination
FUNCTION desiredAzimuth
{
	PARAMETER targetAltitude.
	PARAMETER targetInclination.

	LOCAL targetFinalVelocity IS SQRT(SHIP:BODY:MU / (SHIP:BODY:RADIUS + targetAltitude)).

	// this is cheating a little bit - I just take the current orbital speed instead of calculating it based on longitude
	LOCAL launchSiteSpeed IS SHIP:VELOCITY:ORBIT:MAG.
	LOCAL desiredEWVelocity IS COS(targetInclination) * targetFinalVelocity - launchSiteSpeed.
	LOCAL desiredNSVelocity IS SIN(targetInclination) * targetFinalVelocity.
	LOCAL launchAzimuth IS 90 - ARCTAN2(desiredNSVelocity, desiredEWVelocity).
	RETURN launchAzimuth.
}

FUNCTION naiveAzimuth {
  PARAMETER inclination.
  PARAMETER lat.
	RETURN ARCSIN(COS(inclination)/COS(lat)).
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
			IF EXISTS(filename) DELETEPATH(filename).
			IF detailed	{LOG "Timestamp,Last Sample Time,Input,Setpoint,Error,Output,P Term,I Term,D Term,Kp,Ki,Kd,Max Output,Min Output,Change Rate,Error Sum" TO filename. }
			ELSE {LOG "Timestamp,Input,Setpoint,Error,Output" TO filename.}
			initPIDLog:ADD(filename, TIME:SECONDS).
		}
		IF detailed {LOG (TIME:SECONDS - initPIDLog[filename]) + "," + PID:LastSampleTime + "," + PID:Input + "," + PID:Setpoint + "," + PID:Error + "," + PID:Output + "," + PID:PTerm + "," + PID:ITerm + "," + PID:DTerm + "," + PID:Kp + "," + PID:KI + "," + PID:Kd + "," + PID:MAXOUTPUT + "," + PID:MINOUTPUT + "," + PID:CHANGERATE + "," + PID:ERRORSUM TO filename.}
		ELSE {LOG (TIME:SECONDS - initPIDLog[filename]) + "," + PID:Input + "," + PID:Setpoint + "," + PID:Error + "," + PID:Output TO filename.}
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
		IF (initPIDLog:KEYS:EMPTY OR NOT initPIDLog:KEYS:CONTAINS(filename))
		{
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
			LOG labelRow TO fileName.
			LOG valueRow TO fileName.
			initPIDLog:ADD(filename, TIME:SECONDS).
		}
		LOCAL rowData IS (TIME:SECONDS - initPIDLog[filename]) + ",".
		FOR eachPID in PIDLexicon:KEYS {
			SET rowData TO rowData + PIDLexicon[eachPID]:Input + "," + PIDLexicon[eachPID]:Setpoint + "," + PIDLexicon[eachPID]:Error + "," + PIDLexicon[eachPID]:Output + ",".
			IF detailed {
				SET rowData TO rowData + PIDLexicon[eachPID]:PTerm + "," + PIDLexicon[eachPID]:ITerm + "," + PIDLexicon[eachPID]:DTerm + "," + PIDLexicon[eachPID]:Kp + "," + PIDLexicon[eachPID]:KI + "," + PIDLexicon[eachPID]:Kd + "," + PIDLexicon[eachPID]:MAXOUTPUT + "," + PIDLexicon[eachPID]:MINOUTPUT + "," + PIDLexicon[eachPID]:CHANGERATE + "," + PIDLexicon[eachPID]:ERRORSUM + ",".
			}
		}
		IF useAdditional SET rowData TO rowData + additionalData["rowData"].
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

// Warp To Time
// This function timewarps until the system time is the targetTime.
// If there is an SOI change before the target time, the function will slow down for the SOI change.
// This function keeps track of the rate of change of the value, and varies the warp speed to maintain
// 10 seconds or less of realtime remaining for each warp speed.
// Passed the following:
//			target time (scalar, seconds from universe creation)
// Returns the following:
//			in-game time that was warped through (scalar, seconds)
FUNCTION warpToTime
{
	PARAMETER targetTime.
	PARAMETER recursionLevel IS 0.

	IF recursionLevel > 5 RETURN 0.

// 	waitUntilFinishedRotating().
	LOCAL startTime IS TIME:SECONDS.
	LOCAL timeLeft IS targetTime - TIME:SECONDS.

	SET KUNIVERSE:TIMEWARP:RATE TO 0.
	WAIT 0.1.
	SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".

	// if there is an SOI change before the target time, jump to the SOI change.
	IF (SHIP:ORBIT:HASNEXTPATCH) AND ((targetTime - TIME:SECONDS) > ETA:TRANSITION) {
		LOCAL oldBody IS SHIP:BODY:NAME.
		warpToTime(TIME:SECONDS + SHIP:ORBIT:NEXTPATCHETA - 10, recursionLevel + 1).
		WAIT UNTIL SHIP:BODY:NAME <> oldBody.
		warpToTime(targetTime, recursionLevel + 1).
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
		UNTIL (timeLeft < 0.5) AND (KUNIVERSE:TIMEWARP:RATE = 1) {
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
// This function returns the time it will take to rotate to a specific longitude.
// It assumes that the ship is not in motion relative to the body it is on.
// This function is meant to be used in conjunction with the warpToTime function.
// Passed the following:
//			desired longitude (scalar, degrees)
// Returns the following:
//			time to reach that longitude (scalar, seconds)
FUNCTION timeToLongitude
{
	PARAMETER desiredLongitude.
	RETURN TIME:SECONDS + normalizeAngle180(SHIP:GEOPOSITION:LNG, desiredLongitude) / 360 * SHIP:BODY:ROTATIONPERIOD.
}

// Returns time in seconds to the next time SHIP crosses the input altitude or -1 if input altitude is never crossed
FUNCTION timeToAltitude
{
  PARAMETER desiredAltitude.

  // return 0 if never reach altitude
  IF desiredAltitude < SHIP:PERIAPSIS OR desiredAltitude > SHIP:APOAPSIS RETURN -1.

  // query constants
  LOCAL ecc IS SHIP:ORBIT:ECCENTRICITY.
  IF ecc = 0 SET ecc TO 0.00001. // ensure no divide by 0
  LOCAL sma IS SHIP:ORBIT:SEMIMAJORAXIS.
  LOCAL desiredRadius IS desiredAltitude + SHIP:BODY:RADIUS.
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

  RETURN (desiredMeanAnomaly - currentMeanAnomaly) / meanMotion.
}

FUNCTION greatCircleDistance
{
	PARAMETER toPosition.
	PARAMETER fromPosition IS SHIP:GEOPOSITION.
	RETURN SHIP:BODY:RADIUS * Constant:DegToRad * ARCCOS(SIN(fromPosition:LAT) * SIN(toPosition:LAT) + COS(fromPosition:LAT) * COS(toPosition:LAT) * COS(ABS(fromPosition:LNG - toPosition:LNG))).
}

// Function that returns the unit vectors showing the direction of prograde,
// radial and normal for an arbitrary Orbitable at a specified UT time
// Passed:
//	 orbitable object
//   UT Time (seconds)
// Returns a lexicon of prograde vector, radial vector, normal vector, position,
//   velocity
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
  IF useTarget SET normalVector TO VCRS(TARGET:POSITION - TARGET:BODY:POSITION, TARGET:VELOCITY:ORBIT).

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

// returns a lexicon
// "Time" time until closest approach (seconds UT)
// "Distance" distance of closest approach (meters)
FUNCTION closestApproach {
	PARAMETER initialGuess IS TIME:SECONDS.
	PARAMETER initialStepSize IS 10.
	PARAMETER logFileName IS "".
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
		1000).
	// if things didn't work here with the default, try again half an orbit later.
	IF results["finalGuess"] < TIME:SECONDS {
		SET results TO hillClimb(
			distanceAtTime@,
			initialGuess + SHIP:ORBIT:PERIOD/2,
			initialStepSize,
			logFileName,
			1000).
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
	LOCAL totalBottom IS 1.
	IF valueList:LENGTH = weightList:LENGTH AND valueList:LENGTH > 0 {
		IF valueList:LENGTH = 1 {
			RETURN valueList[0].
		}
		IF valueList:LENGTH > 1 {
			FOR eachIndex IN RANGE(0, valueList:LENGTH - 1, 1) {
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

// Using the Secant method, iterate until the function returns the chosen value
//   within tolerance, or the maximum iteration number is reached.
FUNCTION findZeroSecant {
  PARAMETER delegate.
  PARAMETER X1.
  PARAMETER X2.
  PARAMETER tolerance.
  PARAMETER iteration IS 0.

  IF ((iteration = 10) OR (delegate:TYPENAME <> "UserDelegate")) RETURN X1.

  LOCAL F1 IS delegate(X1).
  LOCAL F2 IS delegate(X2).
  LOCAL X3 IS 0.
  IF (F1 <> 0) OR (F2 <> 0) SET X3 TO (X2 * F1 - X1 * F2) / (F1 - F2).
  LOCAL F3 IS delegate(X3).

  IF ABS(F3) < tolerance RETURN X3.
  RETURN  findZeroSecant(delegate, X2, X3, tolerance, iteration + 1).
}

// Using the Newton method, iterate until the function returns the chosen value
//   within tolerance, or the maximum iteration number is reached.
FUNCTION findZeroNewton {
	PARAMETER delegateFunction.
	PARAMETER delegateSlope.
	PARAMETER initialGuess.
	PARAMETER tolerance.
	PARAMETER desiredValue IS 0.
	PARAMETER iteration IS 0.
	PARAMETER maxIteration IS 100.

	IF ((iteration >= 10) OR (NOT delegateFunction:ISTYPE("UserDelegate")) OR (NOT delegateSlope:ISTYPE("UserDelegate"))) RETURN X1.

	LOCAL slope IS delegateSlope(X1).
	LOCAL X2 IS initialGuess.
	IF slope <> 0 SET X2 TO initialGuess - delegateFunction(initialGuess)/slope.
	IF ABS(delegateFunction(initialGuess) - desiredValue) < tolerance RETURN X2.
	RETURN findZeroNewton(delegateFunction, delegateSlope, X2, tolerance, desiredValue, iteration + 1, maxIteration).
}

// given the mean anomaly (in degrees), returns true anomaly (in degrees)
FUNCTION meanToTrueAnomaly {
  PARAMETER meanAnomaly.
  PARAMETER eccentricity IS SHIP:ORBIT:ECCENTRICITY.

  // If eccentricity is 0, mean, true and eccentric anomaly are all the same thing, so return mean anomaly.
  IF eccentricity = 0 RETURN meanAnomaly.

  // Convert to radians for calculations.
  SET meanAnomaly TO CONSTANT:DegToRad * meanAnomaly.

  // Note that this function requires angles to be in radians
  LOCAL functionDelegate IS {PARAMETER E. RETURN E - eccentricity*SIN(CONSTANT:RadToDeg * E) - meanAnomaly.}.

  LOCAL eccentricAnomaly IS findZeroSecant(functionDelegate, meanAnomaly, meanAnomaly + CONSTANT:PI/32, 0.0000001).
  LOCAL trueAnomaly IS ARCTAN2(SQRT(1-eccentricity*eccentricity)*SIN(CONSTANT:RadToDeg * eccentricAnomaly), COS(CONSTANT:RadToDeg * eccentricAnomaly) - eccentricity).
  UNTIL trueAnomaly >= 0 {
    SET trueAnomaly TO trueAnomaly + 360.0.
  }

  RETURN normalizeAngle360(trueAnomaly).
}

// given the true anomaly (in degrees), returns mean anomaly (in degrees)
FUNCTION trueToMeanAnomaly {
  PARAMETER trueAnomaly.
  PARAMETER eccentricity IS SHIP:ORBIT:ECCENTRICITY.

  // If eccentricity is 0, mean, true and eccentric anomaly are all the same thing, so return true anomaly.
  IF eccentricity = 0 RETURN trueAnomaly.

	IF eccentricity < 1 { // elliptical case
		// note that eccentric anomaly is in radians
		LOCAL eccentricAnomaly IS CONSTANT:DegToRad * 2 * ARCTAN(TAN(trueAnomaly / 2) / SQRT((1 + eccentricity) / (1 - eccentricity))).
		//PRINT "eccentric anomaly: " + (eccentricAnomaly * CONSTANT:RadToDeg).

	//  This method also calculates eccentric anomaly equally well, but it is much more processor intensive than the other one.
	//	LOCAL cosE IS (eccentricity + COS(trueAnomaly))/(1 + eccentricity * COS(trueAnomaly)).
	//	LOCAL sinE IS SQRT(1 - eccentricity^2) * SIN(trueAnomaly)/(1 + eccentricity * COS(trueAnomaly)).
	//  LOCAL eccentricAnomaly IS CONSTANT:DegToRad * ARCTAN2(sinE, cosE).
	  LOCAL meanAnomaly IS CONSTANT:RadToDeg * (eccentricAnomaly - eccentricity * SIN(eccentricAnomaly * CONSTANT:RadToDeg)).
		RETURN normalizeAngle360(meanAnomaly).
	} ELSE { // hyperbolic case
		// Note: equations taken from https://en.wikipedia.org/wiki/Hyperbolic_trajectory, section "Equations of Motion"
		// Hyperbolic Eccentric Anomaly
		LOCAL bigE IS ACOSH((eccentricity + COS(trueAnomaly))/(1 + eccentricity * COS(trueAnomaly))).

		LOCAL meanAnomaly IS eccentricity * SINH(bigE) - bigE.
		RETURN normalizeAngle360(CONSTANT:RadToDeg * meanAnomaly).
	}
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
// Returns an angle between 0 degrees and 360 degrees
FUNCTION normalizeAngle360 {
	PARAMETER angle.
	LOCAL tempAngle IS ARCTAN2(SIN(angle), COS(angle)).
	IF tempAngle < 0 SET tempAngle TO tempAngle + 360.
	RETURN tempAngle.
}

// Given an angle in degrees, returns the normalized angle in degrees
// Returns an angle between -180 degrees and 180 degrees
FUNCTION normalizeAngle180 {
	PARAMETER angle.
	LOCAL tempAngle IS ARCTAN2(SIN(angle), COS(angle)).
	IF tempAngle < -180 SET tempAngle TO tempAngle + 360.
	RETURN tempAngle.
}

LOCAL maxHyperbolicVariable IS 709.78.
// A variety of hyperbolic trig functions and their inverses
FUNCTION TANH {PARAMETER x. RETURN (CONSTANT:E ^ (2*x) - 1) / (CONSTANT:E ^ (2*x) + 1).}

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
//     "b" - scalar - semiminor axis of the hyperbola. Negative.
//     "e" - scalar - eccentricity of the hyperbola. Greater than 1.0.
//     "l" - scalar - semimajor axis of the hyperbola. Negative.
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
  IF removals = 3 {PRINT "3 Removals". RETURN finalPosition - originalThing:BODY:BODY:POSITION.}
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

// Find Quadratic Roots
// Given the three values A, B and C, return the solutions to the quadratic Ax^2 + Bx + C = 0
// Returns a LEXICON with up to three entries.
//    Roots will be the number of solutions, scalar with value 0, 1 or 2.
//    Positive will be the positive solution, if it exists (or the only solution, if there is only one)
//		Negative will be the negative solution, if it exists.
FUNCTION solveQuadratic {
	PARAMETER A.
	PARAMETER B.
	PARAMETER C.
  LOCAL discriminant IS B*B-4*A*C.
  IF discriminant < 0 RETURN LEXICON("Roots", 0).
  IF discriminant = 0 RETURN LEXICON("Roots", 1, "Positive", -B/(2*A)).
  RETURN LEXICON("Roots", 2, "Positive", (-B+SQRT(discriminant))/(2*A), "Negative", (-B-SQRT(discriminant))/(2*A)).
}

// Gets the normal vector of an Orbitable object.
// The vector is normalized.
FUNCTION getNormalVector {
  PARAMETER orbitableObject IS "Equator".
  IF orbitableObject = "Equator" RETURN SHIP:BODY:ANGULARVEL:NORMALIZED.
  RETURN VCRS((orbitableObject:POSITION - orbitableObject:BODY:POSITION):NORMALIZED, orbitableObject:VELOCITY:ORBIT:NORMALIZED).
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

// Given two bodies, return the first body that they both orbit around.
// For planets, this will be the Sun. For moons of the same body, this will be that body.
// For moons of different bodies, this will be the same as if it ran with those two different bodies.
FUNCTION firstCommonBody {
	PARAMETER objectOne.
	PARAMETER objectTwo.
	LOCAL object1Bodies IS LIST().
	UNTIL NOT objectOne:HASBODY {object1Bodies:ADD(objectOne:NAME). SET objectOne TO objectOne:BODY.}
	UNTIL NOT objectTwo:HASBODY {
		IF object1Bodies:CONTAINS(objectTwo:NAME) RETURN BODY(objectTwo:NAME).
		SET objectTwo TO objectTwo:BODY.
	}
	RETURN objectTwo.
}

// Returns BODY(objectName) or VESSEL(objectName) (a vessel wins if both exist),
// or the scalar 0 if neither exists - check with :ISTYPE("Scalar").
FUNCTION resolveOrbitable {
	PARAMETER objectName.

	LOCAL result IS 0.
	IF BODYEXISTS(objectName) SET result TO BODY(objectName).
	IF VESSELEXISTS(objectName) SET result TO VESSEL(objectName).
	RETURN result.
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


// Given a single-argument delegate f(x) and a starting guess, searches
// outward from the guess in both directions (doubling the step each attempt,
// clamped to [domainLow, domainHigh]) until it finds two x-values where f
// changes sign - suitable as a bracket for findZeroBrent.
FUNCTION bracketAroundGuess {
	PARAMETER residualDelegate.
	PARAMETER guess.
	PARAMETER domainLow.
	PARAMETER domainHigh.
	PARAMETER initialStep.
	PARAMETER maxDoublings IS 40.

	LOCAL clampedGuess IS MAX(domainLow, MIN(domainHigh, guess)).
	LOCAL guessResidual IS residualDelegate(clampedGuess).
	LOCAL step IS initialStep.
	LOCAL attempt IS 0.

	UNTIL attempt >= maxDoublings {
		LOCAL highCandidate IS MIN(clampedGuess + step, domainHigh).
		IF residualDelegate(highCandidate) * guessResidual <= 0 RETURN LEXICON("low", clampedGuess, "high", highCandidate).

		LOCAL lowCandidate IS MAX(clampedGuess - step, domainLow).
		IF residualDelegate(lowCandidate) * guessResidual <= 0 RETURN LEXICON("low", lowCandidate, "high", clampedGuess).

		IF (highCandidate = domainHigh) AND (lowCandidate = domainLow) BREAK.

		SET step TO step * 2.
		SET attempt TO attempt + 1.
	}

	// Couldn't find a bracket within the domain - return a degenerate
	// "bracket" so findZeroBrent falls back gracefully (its own
	// not-actually-bracketed check) instead of this function crashing or
	// looping forever.
	RETURN LEXICON("low", clampedGuess, "high", clampedGuess).
}

// Brent's method: a bracket-based, derivative-free root finder that combines
// bisection with the much faster secant method and inverse
// quadratic interpolation, falling back to bisection whenever those would
// step outside the current bracket or fail to shrink it fast enough. Takes
// the same first four arguments as findZeroSecant - delegate, X1, X2,
// tolerance - so it can be used as a drop-in alternative wherever a
// bracket is known. Unlike findZeroSecant, X1 and X2 MUST actually bracket a
// root (delegate(X1) and delegate(X2) must have opposite signs); given a
// valid bracket, Brent's method is GUARANTEED to converge - no restart
// cascade and no risk of diverging from a bad initial guess, unlike a plain
// secant or Newton iteration.
//
// This is an iterative loop rather than recursive like findZeroSecant, since
// Brent's method carries several pieces of running state between iterations
// (the previous two bracket points, plus which interpolation mode was used
// last) that would be awkward to thread through repeated recursive calls.
FUNCTION findZeroBrent {
	PARAMETER delegate.
	PARAMETER X1.
	PARAMETER X2.
	PARAMETER tolerance.
	PARAMETER maxIterations IS 100.
	PARAMETER recursionLevel IS 10.

	LOCAL a IS X1.
	LOCAL b IS X2.
	LOCAL fa IS delegate(a).
	LOCAL fb IS delegate(b).

	// If we have reached the limit of recursion, return whichever input
	// results in the smallest function value.
	IF recursionLevel <= 0 {
		IF ABS(fa) < ABS(fb) RETURN a.
		RETURN b.
	}

	// Not actually bracketed - Brent's method can't guarantee anything here, so
	// use the bracketAroundGuess function to generate a bracket and try again.
	IF fa * fb >= 0 {
		LOCAL results IS 0.
		IF ABS(fa) < ABS(fb) SET results TO bracketAroundGuess(delegate, a, -1e12, 1e12, MAX(ABS(a), ABS(b)) * 0.5 + 1).
		ELSE SET results TO bracketAroundGuess(delegate, b, -1e12, 1e12, MAX(ABS(a), ABS(b)) * 0.5 + 1).
		return findZeroBrent(delegate, results["low"], results["high"], tolerance, maxIterations, recursionLevel - 1).
	}

	// Keep b as the current best estimate: |f(b)| <= |f(a)| is an invariant
	// maintained by re-checking and re-swapping after every update below.
	IF ABS(fa) < ABS(fb) {
		LOCAL swapValue IS a. SET a TO b. SET b TO swapValue.
		SET swapValue TO fa. SET fa TO fb. SET fb TO swapValue.
	}

	LOCAL c IS a.
	LOCAL fc IS fa.
	LOCAL useBisection IS TRUE.
	LOCAL d IS a. // unused until useBisection is cleared for the first time
	LOCAL s IS b.
	LOCAL fs IS fb.
	LOCAL iteration IS 0.

	UNTIL (fb = 0) OR (fs = 0) OR (ABS(b - a) < tolerance) OR (iteration >= maxIterations) {
		IF (fa <> fc) AND (fb <> fc) {
			// inverse quadratic interpolation
			SET s TO a * fb * fc / ((fa - fb) * (fa - fc))
				+ b * fa * fc / ((fb - fa) * (fb - fc))
				+ c * fa * fb / ((fc - fa) * (fc - fb)).
		} ELSE {
			// secant method
			SET s TO b - fb * (b - a) / (fb - fa).
		}

		// Reject the interpolated step (falling back to bisection instead)
		// whenever it would land outside the bracket, or isn't shrinking the
		// bracket fast enough - this is what makes Brent's method robust
		// rather than just "secant method with extra steps".
		LOCAL lowBound IS MIN((3 * a + b) / 4, b).
		LOCAL highBound IS MAX((3 * a + b) / 4, b).
		LOCAL fallBackToBisection IS FALSE.
		IF (s < lowBound) OR (s > highBound) SET fallBackToBisection TO TRUE.
		IF useBisection AND (ABS(s - b) >= ABS(b - c) / 2) SET fallBackToBisection TO TRUE.
		IF (NOT useBisection) AND (ABS(s - b) >= ABS(c - d) / 2) SET fallBackToBisection TO TRUE.
		IF useBisection AND (ABS(b - c) < tolerance) SET fallBackToBisection TO TRUE.
		IF (NOT useBisection) AND (ABS(c - d) < tolerance) SET fallBackToBisection TO TRUE.

		IF fallBackToBisection {
			SET s TO (a + b) / 2.
			SET useBisection TO TRUE.
		} ELSE {
			SET useBisection TO FALSE.
		}

		SET fs TO delegate(s).
		SET d TO c.
		SET c TO b.
		SET fc TO fb.

		IF fa * fs < 0 {
			SET b TO s.
			SET fb TO fs.
		} ELSE {
			SET a TO s.
			SET fa TO fs.
		}

		IF ABS(fa) < ABS(fb) {
			LOCAL swapValue2 IS a. SET a TO b. SET b TO swapValue2.
			SET swapValue2 TO fa. SET fa TO fb. SET fb TO swapValue2.
		}

		SET iteration TO iteration + 1.
	}

	RETURN b.
}
