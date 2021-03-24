@LAZYGLOBAL OFF.
// First off, define several parameters that are used by multiple files.
// All of these are default parameters; they can be overriden by any vehicle-specific script file
GLOBAL physicsWarpPerm TO 2.					// If non-zero, allow physics warping up to the specified level when reasonable
GLOBAL maxAOA TO 5.								// Maximum angle of attack. Used as the limits of the pitch PID while in atmosphere
GLOBAL debug IS TRUE.							// If TRUE, multiple functions will display or log extra info
GLOBAL missionTimeOffset TO 0.					// Offset for MISSIONTIME to account for time spent on the launchpad
GLOBAL g_0 IS 9.80665.               			// Gravitational acceleration constant (m/s²)
GLOBAL augerList IS SHIP:PARTSTITLEDPATTERN("Auger").
GLOBAL smelterList IS SHIP:PARTSTITLEDPATTERN("Smelter").
GLOBAL minThrottle IS 0.
GLOBAL facingVector   IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN SHIP:FACING:VECTOR * 10.}           , RED,   "                 Facing", 1).
GLOBAL guidanceVector IS VECDRAW({RETURN SHIP:CONTROLPART:POSITION.}, {RETURN STEERINGMANAGER:TARGET:VECTOR * 10.}, GREEN, "Guidance               ", 1).
LOCAL shipInfoCurrentLoggingStarted IS FALSE.
LOCAL logPhysicsTimeStamp IS 0.
GLOBAL bounds IS SHIP:BOUNDS.
CLEARVECDRAWS().

LOCK timeSinceLaunch TO MISSIONTIME - missionTimeOffset.

GLOBAL shipInfo IS Lexicon().

LOCAL partListTree IS LEXICON().
LOCAL decouplerList IS LIST().

updateShipInfo().

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
//		Sensors - List - SENSORs in this stage
//		Isp - scalar - calculated for all engines in this stage
//		Thrust - scalar - Total thrust of all engines in this stage, in Newtons
//		mDot - scalar - Total fuel flow of all engines in this stage, in kg/s
//		Resources - Lexicon - the masses of resources in this stage
//		Fuels - List - list of names of fuels used by engines in this stage
//		FuelMass - scalar - the mass of all resources in the list of fuels, in kg
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

		// Add the Fuels list to the lexicon, but it will be filled out once the engine list has been finalized
		stageInfo:ADD("Fuels", LIST()).

		stageInfo:ADD("Sensors",LIST()).
		FOR eachPart IN stageInfo["Parts"] { IF eachPart:TYPENAME = "sensor" stageInfo["Sensors"]:ADD(eachPart).}

		// Add the engine-related values to the lexicon, but they will be added once the engine list has been finalized
		stageInfo:ADD("Isp", 0).
		stageInfo:ADD("Thrust", 0).
		stageInfo:ADD("mDot", 0).

		// Add the resources from this stage
		stageInfo:ADD("Resources", resourcesInParts(stageInfo["Parts"])).

		// add the various resource-related values to the lexicon, but they will be filled out by updateShipInfoCurrent
		stageInfo:ADD("FuelMass", 0).
		stageInfo:ADD("ResourceMass", 0).

		LOCAL dryMasses IS 0.
		FOR eachPart IN stageInfo["Parts"] {SET dryMasses TO dryMasses + eachPart:DRYMASS * 1000.}
		stageInfo:ADD("DryMass", dryMasses).

		stageInfo:ADD("PreviousMass",previousMass).
		FOR eachPart IN stageInfo["Parts"] {SET previousMass TO previousMass + eachPart:MASS * 1000.}

		stageInfo:ADD("CurrentMass",previousMass).

		// Will be updated by updateShipInfoCurrent
		stageInfo:ADD("DeltaV",0).
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
		SET shipInfo["Stage " + stageNumber]["Isp"] TO engineStat[0].
		SET shipInfo["Stage " + stageNumber]["Thrust"] TO engineStat[3].
		SET shipInfo["Stage " + stageNumber]["mDot"] TO engineStat[4].

		SET shipInfo["Stage " + stageNumber]["Fuels"] TO getCurrentFuels(shipInfo["Stage " + stageNumber]["Engines"]).
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
	updateBounds().
}

// Log Ship Info
// Function that logs all information in shipInfo into the specified file.
FUNCTION logShipInfo {
	PARAMETER fileName TO "0:" + SHIP:NAME + " Info Stage " + STAGE:NUMBER + ".csv".
	LOG "Ship Information for " + SHIP:NAME TO fileName.
	LOCAL deltaVLogList IS "".
	LOCAL deltaVDisplayList IS "".
	LOCAL resourceDensity IS 1.
	// for each of the stages
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		LOG "Stage " + stageNumber TO fileName.
		LOG ",Parts has " + shipInfo["Stage " + stageNumber]["Parts"]:LENGTH + " Items in it,Part Name,Part Wet Mass,Unit,Stage" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Parts"] {LOG ",," + p:TITLE:REPLACE(",","") + "," + p:MASS*1000 + ",kg," + p:STAGE TO fileName.}
		LOG ",Engines has " + shipInfo["Stage " + stageNumber]["Engines"]:LENGTH + " Items in it" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Engines"] {LOG ",," + p:TITLE:REPLACE(",","") TO fileName.}
		LOG ",Sensors has " + shipInfo["Stage " + stageNumber]["Sensors"]:LENGTH + " Items in it" TO fileName.
		FOR p IN shipInfo["Stage " + stageNumber]["Sensors"] {LOG ",," + p:TITLE:REPLACE(",","") TO fileName.}
		LOG ",Isp," + ROUND(shipInfo["Stage " + stageNumber]["Isp"], 4) + ",s" TO fileName.
		LOG ",Thrust," + ROUND(shipInfo["Stage " + stageNumber]["Thrust"], 4) + ",N" TO fileName.
		LOG ",mDot," + ROUND(shipInfo["Stage " + stageNumber]["mDot"], 4) + ",kg/s" TO fileName.
		LOG ",Resources has " + shipInfo["Stage " + stageNumber]["Resources"]:KEYS:LENGTH + " items in it" TO fileName.
		FOR eachResource IN shipInfo["Stage " + stageNumber]["Resources"]:KEYS {LOG ",," + eachResource + "," + shipInfo["Stage " + stageNumber]["Resources"][eachResource] + ",kg" TO fileName.}
		LOG ",Fuels has " + shipInfo["Stage " + stageNumber]["Fuels"]:LENGTH + " items in it,,kg,L" TO fileName.
		FOR f IN shipInfo["Stage " + stageNumber]["Fuels"] {
			SET resourceDensity TO 1.
			FOR eachPart IN SHIP:PARTS {
				FOR eachResource IN eachPart:RESOURCES {
					IF eachResource:NAME = f SET resourceDensity TO eachResource:DENSITY * 1000.
				}
			}
			LOG ",," + f + "," + shipInfo["Stage " + stageNumber]["Resources"][f] + "," + (shipInfo["Stage " + stageNumber]["Resources"][f] / resourceDensity) TO fileName.
		}
		LOG ",FuelMass," + shipInfo["Stage " + stageNumber]["FuelMass"] + ",kg" TO fileName.
		LOG ",Resource Mass," + shipInfo["Stage " + stageNumber]["resourceMass"] + ",kg" TO fileName.
		LOG ",Dry Mass," + shipInfo["Stage " + stageNumber]["DryMass"] + ",kg" TO fileName.
		LOG ",Previous Mass," + shipInfo["Stage " + stageNumber]["PreviousMass"] + ",kg" TO fileName.
		LOG ",Current Mass," + shipInfo["Stage " + stageNumber]["CurrentMass"] + ",kg" TO fileName.
		LOG ",Stage Delta V," + shipInfo["Stage " + stageNumber]["DeltaV"] + ",m/s" TO fileName.
		LOG ",Stage Delta V Previous," + shipInfo["Stage " + stageNumber]["DeltaVPrev"] + ",m/s" TO fileName.
		IF (shipInfo["Stage " + stageNumber]["Isp"] <> 0) {
			SET deltaVLogList TO deltaVLogList + stageNumber + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["ENGINES"]:LENGTH + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["ENGINES"][0]:TITLE:REPLACE(",","") + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["FuelMass"] + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["Isp"] + ",".
			SET deltaVLogList TO deltaVLogList + shipInfo["Stage " + stageNumber]["DeltaV"] + CHAR(10).
			SET deltaVDisplayList TO deltaVDisplayList + stageNumber:TOSTRING:PADRIGHT(5) + shipInfo["Stage " + stageNumber]["ENGINES"]:LENGTH:TOSTRING:PADLEFT(9) + ROUND(shipInfo["Stage " + stageNumber]["FuelMass"], 0):TOSTRING:PADLEFT(16) + ROUND(shipInfo["Stage " + stageNumber]["Isp"], 0):TOSTRING:PADLEFT(8) + ROUND(shipInfo["Stage " + stageNumber]["DeltaV"], 4):TOSTRING:PADLEFT(15) + CHAR(10).
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
	LOG "Maximum BurnTime," + shipInfo["Maximum"]["BurnTime"] + ",s" TO fileName.
	LOG "Maximum mDot," + shipInfo["Maximum"]["mDot"] + ",kg/s" TO fileName.
	LOG "Maximum Thrust," + shipInfo["Maximum"]["Thrust"] + ",N" TO fileName.
	LOG "Maximum TWR," + shipInfo["Maximum"]["TWR"] + "," TO fileName.
	LOG "" TO fileName.
	LOG "Stage,Engine Count,Engine Type,Fuel Mass (kg),Isp (s),delta V (m/s)" TO fileName.
	LOG deltaVLogList TO fileName.

	LOCAL density IS 0.
	LOCAL indexRes IS 0.
	LOG "Name,Amount (L),Capacity (L),Mass (kg),Density (kg/L)" TO fileName.
	LOG ",Liters,Liters,kg,kg/L" TO fileName.
	FOR eachResource IN SHIP:RESOURCES {
		FOR eachIndex IN RANGE(eachResource:PARTS[0]:RESOURCES:LENGTH) {IF eachResource:PARTS[0]:RESOURCES[eachIndex]:NAME = eachResource:NAME SET indexRes TO eachIndex.}
		SET density TO eachResource:PARTS[0]:RESOURCES[indexRes]:DENSITY * 1000.
		LOG eachResource:NAME + "," + eachResource:AMOUNT + "," + eachResource:CAPACITY + "," + eachResource:AMOUNT * density + "," + density TO fileName.
	}

	CLEARSCREEN.
	PRINT "Stage  Engines  Fuel Mass (kg)  Isp (s)  Delta V (m/s)".
	PRINT deltaVDisplayList.
	WAIT 5.
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

// Update Ship Information Resources
// Function designed to update the current values of the "Resources" lexicon within shipInfo.
// Will also update FuelMass, resourceMass, previousMass, currentMass and DeltaV.
FUNCTION updateShipInfoResources {
	PARAMETER createLogFile IS FALSE.
	PARAMETER loggedResources IS LIST("Electricity","Oxygen","Food","Water").
	LOCAL previousMass IS 0.
	FOR stageNumber IN RANGE(0, partListTree:LENGTH) {
		LOCAL stageInfo IS shipInfo["Stage " + stageNumber].
		stageInfo:REMOVE("Resources").
		stageInfo:REMOVE("FuelMass").
		stageInfo:REMOVE("ResourceMass").
		stageInfo:REMOVE("PreviousMass").
		stageInfo:REMOVE("CurrentMass").
		stageInfo:REMOVE("DeltaV").
		stageInfo:ADD("Resources", resourcesInParts(stageInfo["Parts"])).

		IF stageInfo["Resources"]:LENGTH = 0 {stageInfo["Resources"]:ADD("Placeholder",0).}

		LOCAL fuelMass IS 0.
		FOR fuelType IN stageInfo["Fuels"] {
			// If the called out fuel is in this stage, you are good to go
			IF (stageInfo["Resources"]:KEYS:CONTAINS(fuelType)) {
//				LOG "Stage " + stageNumber + ",has,"+ shipInfo["Stage " + stageNumber]["Resources"][fuelType] + ",kg of " + fuelType + " found" TO "Fuels.csv".
				SET fuelMass TO fuelMass + stageInfo["Resources"][fuelType].
			} ELSE {
			// If the called out fuel isn't in this stage, search for it in a later stage
				FOR subStageNumber IN RANGE(stageNumber, 0) {
					IF shipInfo["Stage " + subStageNumber]["Resources"]:KEYS:CONTAINS(fuelType) {
//						LOG "Borrowing "+ shipInfo["Stage " + stageNumber]["Resources"][fuelType] + ",kg of " + fuelType + " from Stage " + stageNumber TO "Fuels.csv".
						SET fuelMass TO fuelMass + shipInfo["Stage " + subStageNumber]["Resources"][fuelType].
						BREAK.
					}
				}
			}
		}
		stageInfo:ADD("FuelMass", fuelMass).

		LOCAL resourceMass IS 0.
		FOR keys IN stageInfo["Resources"]:KEYS {SET resourceMass TO resourceMass + stageInfo["Resources"][keys].}
		stageInfo:ADD("ResourceMass", resourceMass).

		stageInfo:ADD("PreviousMass", previousMass).
		FOR p IN stageInfo["Parts"] {SET previousMass TO previousMass + p:MASS * 1000.}
		stageInfo:ADD("CurrentMass", previousMass).

		LOCAL deltaV TO stageInfo["Isp"] * g_0 * LN(stageInfo["CurrentMass"]/(stageInfo["CurrentMass"] - stageInfo["FuelMass"])).
		stageInfo:ADD("DeltaV", deltaV).
		SET shipInfo["Stage " + stageNumber] TO stageInfo.
	}
	IF createLogFile {
		LOCAL fileName IS "0:" + SHIP:NAME + " Resources.csv".

		LOCAL message IS TIME:SECONDS:TOSTRING() + "," + KUNIVERSE:TIMEWARP:RATE.
		FOR eachResource IN SHIP:RESOURCES {
			IF loggedResources:CONTAINS(eachResource:NAME) SET message TO message + "," + eachResource:AMOUNT + "," + eachResource:AMOUNT * eachResource:DENSITY*1000.
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
	current:ADD("Variable", LEXICON("Thrust", engineStatsVariable[1],
									"mDot", engineStatsVariable[2],
									"Accel", engineStatsVariable[1]/ ( MASS * 1000),
									"TWR", (engineStatsVariable[1]/ ( MASS * 1000))/ localAccel)).
	current:ADD("Constant", LEXICON("Thrust", engineStatsConstant[1],
									"mDot", engineStatsConstant[2],
									"Accel", engineStatsConstant[1]/ ( MASS * 1000),
									"TWR", (engineStatsConstant[1]/ ( MASS * 1000))/ localAccel)).
	maximum:ADD("Variable", LEXICON("Thrust", engineStatsVariable[3],
									"mDot", engineStatsVariable[4],
									"Accel", engineStatsVariable[3]/ ( MASS * 1000),
									"TWR", (engineStatsVariable[3]/ ( MASS * 1000))/ localAccel)).
	maximum:ADD("Constant", LEXICON("Thrust", engineStatsConstant[3],
									"mDot", engineStatsConstant[4],
									"Accel", engineStatsConstant[3]/ ( MASS * 1000),
									"TWR", (engineStatsConstant[3]/ ( MASS * 1000))/ localAccel)).

	current:ADD("Thrust", current["Variable"]["Thrust"] + current["Constant"]["Thrust"]).
	maximum:ADD("Thrust", maximum["Variable"]["Thrust"] + maximum["Constant"]["Thrust"]).

	current:ADD("mDot", current["Variable"]["mDot"] + current["Constant"]["mDot"]).
	maximum:ADD("mDot", maximum["Variable"]["mDot"] + maximum["Constant"]["mDot"]).

	current:ADD("Accel", current["Variable"]["Accel"] + current["Constant"]["Accel"]).
	maximum:ADD("Accel", maximum["Variable"]["Accel"] + maximum["Constant"]["Accel"]).

	current:ADD("TWR", current["Variable"]["TWR"] + current["Constant"]["TWR"]).
	maximum:ADD("TWR", maximum["Variable"]["TWR"] + maximum["Constant"]["TWR"]).

	updateShipInfoResources(FALSE).
	// determine the total mass of the resources used by the engines.
	LOCAL fuelMass IS shipInfo["CurrentStage"]["FuelMass"].
	// if the resources do not line up neatly, use resources from the stage that has the most mass in potential fuel
	IF (current["mDot"] <> 0) 	current:ADD("burnTime", fuelMass / current["mDot"]).
	ELSE 						current:ADD("burnTime", 0).
	IF (maximum["mDot"] <> 0) 	maximum:ADD("burnTime", fuelMass / maximum["mDot"]).
	ELSE 						maximum:ADD("burnTime", 0).
	IF shipInfo:HASKEY("Current") shipInfo:REMOVE("Current").
	shipInfo:ADD("Current", current).
	IF shipInfo:HASKEY("Maximum") shipInfo:REMOVE("Maximum").
	shipInfo:ADD("Maximum", maximum).

	LOCAL thrustPCTThrust IS 0.
	LOCAL thrustPCTEngines IS 0.
	LOCAL thrustPCTEnginesTop IS 0.
	LOCAL thrustPCTEnginesBottom IS 0.
	SET minThrottle TO 0.
	// IF isStockRockets() OR THROTTLE <> 0 OR THROTTLE <> 1 {
		// SET thrustPCTThrust TO THROTTLE.
		// SET thrustPCTEngines TO THROTTLE.
		// SET thrustPCTEnginesTop TO THROTTLE.
		// SET thrustPCTEnginesBottom TO THROTTLE.
		// SET minThrottle TO 0.
	// } ELSE {
		// IF shipInfo["Maximum"]["Variable"]["Thrust"] <> 0 SET thrustPCTThrust TO shipInfo["Current"]["Variable"]["Thrust"] / shipInfo["Maximum"]["Variable"]["Thrust"].
		// SET thrustPCTThrust TO MIN(thrustPCTThrust, 0.999).
		// SET thrustPCTThrust TO MAX(thrustPCTThrust, 0).

		// LOCAL message IS MISSIONTIME + "," + THROTTLE:TOSTRING.

		// FOR eachEngine IN shipInfo["CurrentStage"]["Engines"] {
			// IF eachEngine:IGNITION AND NOT eachEngine:THROTTLELOCK AND eachEngine:GETMODULE("ModuleEnginesRF"):GETFIELD("current throttle") <> 100 {
				// SET thrustPCTEnginesTop TO eachEngine:GETMODULE("ModuleEnginesRF"):GETFIELD("current throttle") * eachEngine:GETMODULE("ModuleEnginesRF"):GETFIELD("thrust").
				// SET thrustPCTEnginesBottom TO eachEngine:GETMODULE("ModuleEnginesRF"):GETFIELD("thrust").
				// SET message TO message + "," + eachEngine:TITLE + "," + eachEngine:GETMODULE("ModuleEnginesRF"):GETFIELD("current throttle") + "," + eachEngine:GETMODULE("ModuleEnginesRF"):GETFIELD("thrust").
			// } ELSE {SET message TO message + "," + eachEngine:TITLE + ",Is Not Throttleable,or is not ignited".}
		// }
		// LOG message TO "0:Engines.csv".
		// IF thrustPCTEnginesBottom <> 0 SET thrustPCTEngines TO thrustPCTEnginesTop / (thrustPCTEnginesBottom * 100).
		// ELSE SET thrustPCTEngines TO 0.
		// SET thrustPCTEngines TO MIN(thrustPCTEngines, 0.999).
		// SET thrustPCTEngines TO MAX(thrustPCTEngines, 0).

		// SET minThrottle TO (THROTTLE-thrustPCTEngines)/(1-thrustPCTEngines).
	// }

	IF indepententLogging {
		IF NOT shipInfoCurrentLoggingStarted {
			IF connectionToKSC() LOG "Time,Mass,Altitude,Air Pressure,Orbital Velocity,Surface Velocity,Throttle,Current Constant Accel,Current Constant mDot,Current Constant Thrust,Current Constant TWR,Current Variable Accel,Current Variable mDot,Current Variable Thrust,Current Variable TWR,Current Accel,Current BurnTime,Current mDot,Current Thrust,Current TWR,Maximum Constant Accel,Maximum Constant mDot,Maximum Constant Thrust,Maximum Constant TWR,Maximum Variable Accel,Maximum Variable mDot,Maximum Variable Thrust,Maximum Variable TWR,Maximum Accel,Maximum BurnTime,Maximum mDot,Maximum Thrust,Maximum TWR,Thrust Percent Thrust,Thrust Percent Engines,Min Throttle" TO fileName.
			IF connectionToKSC() LOG "s,kg,m,atm,m/s,m/s,,m/s^2,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,m/s,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,%,%,%" TO fileName.
			SET shipInfoCurrentLoggingStarted TO TRUE.
		}

		IF connectionToKSC() LOG TIME:SECONDS + "," + MASS * 1000 + "," + ALTITUDE + "," + SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) + "," + VELOCITY:ORBIT:MAG + "," + VELOCITY:SURFACE:MAG + "," + THROTTLE + "," + shipInfo["Current"]["Constant"]["Accel"] + "," + shipInfo["Current"]["Constant"]["mDot"] + "," + shipInfo["Current"]["Constant"]["Thrust"] + "," + shipInfo["Current"]["Constant"]["TWR"] + "," + shipInfo["Current"]["Variable"]["Accel"] + "," + shipInfo["Current"]["Variable"]["mDot"] + "," + shipInfo["Current"]["Variable"]["Thrust"] + "," + shipInfo["Current"]["Variable"]["TWR"] + "," + shipInfo["Current"]["Accel"] + "," + shipInfo["Current"]["BurnTime"] + "," + shipInfo["Current"]["mDot"] + "," + shipInfo["Current"]["Thrust"] + "," + shipInfo["Current"]["TWR"] + "," + shipInfo["Maximum"]["Constant"]["Accel"] + "," + shipInfo["Maximum"]["Constant"]["mDot"] + "," + shipInfo["Maximum"]["Constant"]["Thrust"] + "," + shipInfo["Maximum"]["Constant"]["TWR"] + "," + shipInfo["Maximum"]["Variable"]["Accel"] + "," + shipInfo["Maximum"]["Variable"]["mDot"] + "," + shipInfo["Maximum"]["Variable"]["Thrust"] + "," + shipInfo["Maximum"]["Variable"]["TWR"] + "," + shipInfo["Maximum"]["Accel"] + "," + shipInfo["Maximum"]["BurnTime"] + "," + shipInfo["Maximum"]["mDot"] + "," + shipInfo["Maximum"]["Thrust"] + "," + shipInfo["Maximum"]["TWR"] + "," + thrustPCTThrust + "," + thrustPCTEngines + "," + minThrottle TO fileName.
	}
}

FUNCTION getCurrentFuels {
	PARAMETER engineList.
	LOCAL listOfFuels IS LIST().
	FOR eachEngine IN engineList {
		IF isStockRockets() {
			IF NOT listOfFuels:CONTAINS("LiquidFuel") AND (eachEngine:TITLE:CONTAINS("Liquid Fuel") OR eachEngine:TITLE:CONTAINS("Nuclear")) {
				listOfFuels:ADD("LiquidFuel").
			}
			IF NOT listOfFuels:CONTAINS("Oxidizer") AND eachEngine:TITLE:CONTAINS("Liquid Fuel") {
				listOfFuels:ADD("Oxidizer").
			}
			IF NOT listOfFuels:CONTAINS("SolidFuel") AND eachEngine:TITLE:CONTAINS("Solid") {
				listOfFuels:ADD("SolidFuel").
			}
		} ELSE {
			IF eachEngine:NAME = "LR87LH2Vac" {
				IF NOT listOfFuels:CONTAINS("LqdHydrogen") listOfFuels:ADD("LqdHydrogen").
				IF NOT listOfFuels:CONTAINS("LqdOxygen") listOfFuels:ADD("LqdOxygen").
			}
			IF eachEngine:NAME = "engineLargeSkipper.125m" {
				IF NOT listOfFuels:CONTAINS("Kerosene") listOfFuels:ADD("Kerosene").
				IF NOT listOfFuels:CONTAINS("LqdOxygen") listOfFuels:ADD("LqdOxygen").
			}
			IF eachEngine:TITLE = "RL10 Series Vacuum Engine" {
				IF eachEngine:VACUUMISP > 400 {
					IF NOT listOfFuels:CONTAINS("LqdHydrogen") listOfFuels:ADD("LqdHydrogen").
				} ELSE {
					IF NOT listOfFuels:CONTAINS("LqdMethane") listOfFuels:ADD("LqdMethane").
				}
				IF NOT listOfFuels:CONTAINS("LqdOxygen") listOfFuels:ADD("LqdOxygen").
			}
			IF eachEngine:NAME = "Size2LFB" {
				IF NOT listOfFuels:CONTAINS("Kerosene") listOfFuels:ADD("Kerosene").
				IF NOT listOfFuels:CONTAINS("LqdOxygen") listOfFuels:ADD("LqdOxygen").
			}
			IF eachEngine:NAME = "RO-E1" {
				IF NOT listOfFuels:CONTAINS("Kerosene") listOfFuels:ADD("Kerosene").
				IF NOT listOfFuels:CONTAINS("LqdOxygen") listOfFuels:ADD("LqdOxygen").
			}
			IF eachEngine:NAME = "liquidEngineMiniRescale" {
				IF NOT listOfFuels:CONTAINS("MMH") listOfFuels:ADD("MMH").
				IF NOT listOfFuels:CONTAINS("NTO") listOfFuels:ADD("NTO").
			}
			IF NOT listOfFuels:CONTAINS("SolidFuel") AND eachEngine:TITLE:CONTAINS("Solid") {
				listOfFuels:ADD("SolidFuel").
			}
		}
	}
	RETURN listOfFuels.
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
	PARAMETER createLogFile IS FALSE.

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
	IF (createLogFile) {
		LOG "Time,Longitude,Latitude,Terrain Height" TO "Terrain Heights.csv".
		FOR smallList IN heightList {
			LOG smallList[0] + "," + smallList[1] + "," + smallList[2] + "," + smallList[3] TO "Terrain Heights.csv".
		}
	}
	RETURN LEXICON("min",minHeight,"max",averageHeight,"avg",averageHeight).
}

// Return the vector pointing in the direction of downslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of downhill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of downhill in a vector with length of 1 meter.
FUNCTION findDownSlopeInfo {
	PARAMETER northOffset IS 0.0.
	PARAMETER eastOffset IS 0.0.
	LOCAL distance IS 5.0.
	LOCAL terrainHeight IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + distance*SHIP:NORTH:VECTOR + distance*east_for(SHIP)):TERRAINHEIGHT.
	LOCAL heightNorth IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (distance + northOffset)*SHIP:NORTH:VECTOR):TERRAINHEIGHT - terrainHeight.
	LOCAL heightEast  IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (distance + eastOffset )*   east_for(SHIP)):TERRAINHEIGHT - terrainHeight.
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("heading", ARCTAN2(heightNorth, heightEast) + 90).
	returnMe:ADD("slope", ARCTAN2(V(heightNorth, heightEast, 0):MAG, V(distance + northOffset, distance + eastOffset, 0):MAG)).
  returnMe:ADD("vector", 10*(SHIP:NORTH:VECTOR*ANGLEAXIS(-returnMe["slope"], east_for(ship)))*ANGLEAXIS(returnMe["heading"], SHIP:UP:VECTOR)).
	RETURN returnMe.
}

// Return the vector pointing in the direction of upslope
// Returns a Lexicon of several items related to the geometry of the ground below the ship.
//     LEXICON[heading] - scalar - compass heading of uphill, in degrees
//     LEXICON[slope] - scalar - slope of the ground, in degrees
//     LEXICON[vector] - Vector - direction of uphill in a vector with length of 1 meter.
FUNCTION findUpSlopeInfo {
	PARAMETER northOffset IS 0.0.
	PARAMETER eastOffset IS 0.0.
	LOCAL distance IS 5.0.
	LOCAL terrainHeight IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + distance*SHIP:NORTH:VECTOR + distance*east_for(SHIP)):TERRAINHEIGHT.
	LOCAL heightNorth IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (distance + northOffset)*SHIP:NORTH:VECTOR):TERRAINHEIGHT - terrainHeight.
	LOCAL heightEast  IS SHIP:BODY:GEOPOSITIONOF(SHIP:POSITION + (distance + eastOffset )*   east_for(SHIP)):TERRAINHEIGHT - terrainHeight.
	LOCAL returnMe IS LEXICON().
	returnMe:ADD("heading", ARCTAN2(heightNorth, heightEast) - 90).
	returnMe:ADD("slope", ARCTAN2(V(heightNorth, heightEast, 0):MAG, V(distance + northOffset, distance + eastOffset, 0):MAG)).
  returnMe:ADD("vector", 10*(SHIP:NORTH:VECTOR*ANGLEAXIS(-returnMe["slope"], east_for(ship)))*ANGLEAXIS(returnMe["heading"], SHIP:UP:VECTOR)).
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

FUNCTION logFiles {
	CLEARSCREEN.
	LOCAL logFilesName IS "0:logFiles.csv".
	LOG "Name,Size (Bytes),Type" TO logFilesName.
	LOCAL fileList IS LIST().
	LIST Files IN fileList.
	LOCAL totalSize IS 0.
	FOR eachFile IN fileList {
		IF eachFile:ISFILE 	LOG eachFile:NAME + "," + eachFile:SIZE + ",File" TO logFilesName.
		ELSE 								LOG eachFile:NAME + "," + eachFile:SIZE + ",Folder" TO logFilesName.

		SET totalSize TO totalSize + eachFile:SIZE.
	}
	LOG "Total all files," + totalSize TO logFilesName.
	LOG "Volume Capacity," + core:part:getmodule("kOSProcessor"):VOLUME:CAPACITY TO logFilesName.
	LOG "Volume Remaining, " + core:part:getmodule("kOSProcessor"):VOLUME:FREESPACE TO logFilesName.
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
	RETURN SHIP:BODY:GEOPOSITIONOF(centerPosition + north * metersNorth + east * metersEast).
}

// Calculate Engine Stats
// This function calculates a few important stats of a list of engines.
// It assumes that all engines are fired in current atmospheric conditions.
// Passed the following
//			list of engines (list containing type "engine", unitless)
// Returns a list of the following:
//			effective Isp (scalar, s)
//			thrust (scalar, Newtons)
//			mDot (scalar, kg/s)
//			maximum thrust (scalar, Newtons)
//			maximum mDot (scalar, kg/s)
FUNCTION engineStats {
	PARAMETER engineList.
	IF (engineList:LENGTH = 0) RETURN LIST(0, 0, 0, 0, 0).

	LOCAL mDot_cur IS 0.												// Rate of change of mass for the primary engine, given current throttle (kg/s)
	LOCAL mDot_max IS 0.												// Rate of change of mass for the primary engine, with throttle at 100% (kg/s)
	LOCAL F_cur IS 0.														// Current thrust (N)
	LOCAL F_max IS 0.														// Full thrust (N)
	LOCAL pressure IS 0.												// Ambient atmospheric pressure (atmospheres) Default to 0.
	IF SHIP:BODY:ATM:EXISTS SET pressure TO SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE).

	FOR eng IN engineList {
		SET mDot_cur TO mDot_cur + eng:THRUST         * 1000 / (g_0 * eng:ISPAT(pressure)).
		SET mDot_max TO mDot_max + eng:POSSIBLETHRUST * 1000 / (g_0 * eng:ISPAT(pressure)).
		SET F_cur TO F_cur + eng:THRUST         * 1000.
		SET F_max TO F_max + eng:POSSIBLETHRUST * 1000.
	}

	IF mDot_max = 0 RETURN LIST(0, F_cur, mDot_cur, F_max, mDot_max).

	RETURN LIST(F_max / (g_0 * mDot_max), F_cur, mDot_cur, F_max, mDot_max).
}

// Calculate Engine Stats for RCS engines
// This function calculates a few important stats of a list of engines.
// It assumes that all engines are fired in current atmospheric conditions.
// Passed the following
//			list of RCS engines (list containing type "part", unitless)
// Returns a list of the following:
//			effective Isp (scalar, s)
//			thrust (scalar, Newtons)
//			mDot (scalar, kg/s)
//			maximum thrust (scalar, Newtons)
//			maximum mDot (scalar, kg/s)
FUNCTION engineStatsRCS {
	PARAMETER engineList.
	IF (engineList:LENGTH = 0) RETURN LIST(0, 0, 0, 0, 0).

	LOCAL mDot_cur IS 0.												// Rate of change of mass for the primary engine, given current throttle (kg/s)
	LOCAL mDot_max IS 0.												// Rate of change of mass for the primary engine, with throttle at 100% (kg/s)
	LOCAL F_cur IS 0.													// Partial thrust (N)
	LOCAL F_max IS 0.													// Full thrust (N)
	LOCAL pressure IS 0.												// Ambient atmospheric pressure (atmospheres)
	LOCAL engThrust IS 0.
	LOCAL engISP IS 0.
	LOCAL effectiveThrottle IS 0.
	IF SHIP:BODY:ATM:EXISTS {SET pressure TO SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE).}

	IF isStockRockets() {
		FOR eng IN engineList {
			// The throttle equivalent is the magnitude of the CONTROL:TRANSLATION vector.
			SET effectiveThrottle TO SHIP:CONTROL:TRANSLATION:MAG.

			SET mDot_cur TO mDot_cur + eng:THRUST         * 1000 / (g_0 * eng:ISPAT(pressure)) * (eng:THRUSTLIMIT / 100.0) * effectiveThrottle.
			SET mDot_max TO mDot_max + eng:POSSIBLETHRUST * 1000 / (g_0 * eng:ISPAT(pressure)) * (eng:THRUSTLIMIT / 100.0).
			SET F_cur TO F_cur + eng:THRUST         * 1000 * (eng:THRUSTLIMIT / 100.0) * effectiveThrottle.
			SET F_max TO F_max + eng:POSSIBLETHRUST * 1000 * (eng:THRUSTLIMIT / 100.0).
		}
	} ELSE {
		FOR eng IN engineList {
			// The throttle equivalent is the magnitude of the CONTROL:TRANSLATION vector.
			SET effectiveThrottle TO SHIP:CONTROL:TRANSLATION:MAG.

			// RSS RCS thrusters have names that include two thrust values. If the thruster is a quad, use the first, otherwise use the second.
			IF  eng:TITLE:CONTAINS("RCS Quad") 	SET engThrust TO 1000 * eng:TITLE:SUBSTRING(14, 3):TONUMBER(0).
			ELSE 								SET engThrust TO 1000 * eng:TITLE:SUBSTRING(18, 3):TONUMBER(0).
			SET engISP TO eng:GETMODULE("ModuleRCSFX"):GETFIELD("rcs isp").
			SET mDot_cur TO mDot_cur + engThrust / (engISP * g_0) * effectiveThrottle.
			SET mDot_max TO mDot_max + engThrust / (engISP * g_0).
			SET F_cur TO F_cur + engThrust * 1000 * effectiveThrottle.
			SET F_max TO F_max + engThrust * 1000.
		}
	}

	IF mDot_max = 0 RETURN LIST(0, F_cur, mDot_cur, F_max, mDot_max).

	RETURN LIST(F_max / (g_0 * mDot_max), F_cur, mDot_cur, F_max, mDot_max).
}

// Yaw Vector
// This function recieves a vector and returns the compass heading that points in the direction of that vector
// Returns the compass heading for the given vector
// Passed the following
//			vector to be looked at (vector, any units)
// Returns the following:
//			heading of vector (scalar, degrees from north)
function yaw_vector {
  parameter vect.

  local east is east_for(SHIP).

  local trig_x is vdot(SHIP:north:vector, vect).
  local trig_y is vdot(east, vect).

  local result is arctan2(trig_y, trig_x).

  if result < 0 {
    return 360 + result.
  } else {
    return result.
  }
}

// Pitch Vector
// This function recieves a vector and returns the pitch that points in the direction of that vector
// Returns the pitch for the given vector
// Passed the following
//			vector to be looked at (vector, any units)
// Returns the following:
//			pitch of vector (scalar, degrees above (or below, for negative) the horizon)
function pitch_vector {
  parameter vect.

  return 90 - vang(SHIP:up:vector, vect).
}

function east_for {
  parameter ves.

  return vcrs(ves:up:vector, ves:north:vector).
}

// Yaw For
// This function recieves a vessel and returns the yaw (compass heading) that the vessel is pointing toward
// Passed the following
//			vessel to be looked at (vessel)
// Returns the following:
//			heading of vessel (scalar, degrees from north)
function yaw_for {
  parameter ves.

  local pointing is ves:FACING:FOREVECTOR.
  local east is east_for(ves).

  local trig_x is vdot(ves:north:vector, pointing).
  local trig_y is vdot(east, pointing).

  local result is arctan2(trig_y, trig_x).

  if result < 0 {
    return 360 + result.
  } else {
    return result.
  }
}

// Pitch For
// This function recieves a vessel and returns the pitch that the vessel is pointing toward
// Passed the following
//			vessel to be looked at (vessel)
// Returns the following:
//			pitch of vector (scalar, degrees above (or below, for negative) the horizon)
function pitch_for {
  parameter ves.

  return 90 - vang(ves:up:vector, ves:facing:forevector).
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

// Deactivate All Omni Antennae
// Deactivate all omnidirectional antennae on the ship
// Note that this function ignores all targetable antennae
// Passed the following
//			nothing
// Returns the following:
//			nothing
FUNCTION deactivateOmniAntennae
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
			IF isStockRockets() SET engTitle TO eng:TITLE:SUBSTRING(0, eng:TITLE:FINDLAST(CHAR(34)) + 1).
			ELSE SET engTitle TO eng:TITLE.
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
	LOCAL throttleAdjust IS THROTTLE.
	FOR engType IN engineData:KEYS {
		IF engType:LENGTH > maxLength SET maxLength TO engType:LENGTH.
	}
	FOR engType IN engineData:KEYS {
		SET engineStat TO engineStats(engineData[engType]["EngineList"]).
		SET engineStat[1] TO engineStat[1] / 1000.0.
		SET engineStat[3] TO engineStat[3] / 1000.0.
		IF (DETAILED) {
//			effective Isp (scalar, s)
//			thrust (scalar, Newtons)
//			mDot (scalar, kg/s)
//			maximum thrust (scalar, Newtons)
//			maximum mDot (scalar, kg/s)
			SET thrustDecimals TO 2.
			IF engineStat[1] / engineData[engType]["number"] > 100 SET thrustDecimals TO 1.
			IF engineStat[1] / engineData[engType]["number"] > 1000 SET thrustDecimals TO 0.
			SET throttleAdjust TO THROTTLE.
			IF NOT engineData[engType]["EngineList"][0]:ALLOWSHUTDOWN SET throttleAdjust TO 1.
			SET message TO "".
			SET message TO message + engType:TOSTRING:PADLEFT(maxLength) + "  ".
			SET message TO message + engineData[engType]["number"]:TOSTRING:PADLEFT(5) + "  ".
			SET message TO message + ROUND(throttleAdjust * engineStat[1] / engineData[engType]["number"], thrustDecimals):TOSTRING:PADLEFT(6) + "  ".
			SET message TO message + ROUND(engineStat[3] / engineData[engType]["number"], thrustDecimals):TOSTRING:PADLEFT(7) + "  ".
			IF engineStat[0] <> 0 SET message TO message + ROUND(engineStat[0], 0):TOSTRING:PADLEFT(3) + "  ".
			ELSE SET message TO message + "  0  ".
			IF engineStat[0] <> 0 SET message TO message + ROUND(throttleAdjust * engineStat[2], 2):TOSTRING:PADLEFT(8) + "  ".
			ELSE SET message TO message + "       0  ".
			SET message TO message + engineData[engType]["EngineList"][0]:ALLOWSHUTDOWN:TOSTRING:PADLEFT(5) + "         ".
			PRINT message AT (X + 2 , Y + 2 + COUNT).
		} ELSE {
			PRINT engType:TOSTRING:PADLEFT(maxLength) + " " + ROUND(engineStat[1] / engineStat[3] * 100) + "%" AT (X + 1 , Y + 1 + COUNT).
		}
		SET count TO count + 1.
	}

	IF (DETAILED) {
		PRINT " ":PADRIGHT(maxLength) + "    COUNT  THRUST  T AVAIL  ISP  FUEL USE  KILL         " AT (X, Y).
		PRINT " ":PADRIGHT(maxLength) + "              kN       kN    s      kg/s               " AT (X + 1, Y + 1).
		PRINT "                                                                                 " AT (X + 2, Y + 2 + COUNT).
		PRINT "                                                                                 " AT (X + 2, Y + 3 + COUNT).
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
	RETURN bounds:BOTTOMALTRADAR.
}

// Stage Function
// This function activates a stage and updates the appropriate stage information
// If the rocket is below 75% of the way through the atmosphere, the rocket points prograde before and
// after staging. The reason is to allow the staged rocket parts to drop behind without colliding with
// the rocket. This prevents the spent stage from being pushed into the rocket by aerodynamic forces.
// Passed the following
//			waitTime (scalar, seconds rocket should point prograde before and after staging)
// Returns the following:
//			nothing
FUNCTION stageFunction {
	PARAMETER waitTime IS 0.5.
	PARAMETER forceLongWait IS FALSE.
	LOCAL stageInAtm IS ((SHIP:BODY:ATM:EXISTS) AND
											 (SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) / SHIP:BODY:ATM:SEALEVELPRESSURE > 0.05) AND
											 (SHIP:VELOCITY:SURFACE:MAG > 10.0)).
	IF stageInAtm {
		PRINT "Staging in atmosphere!".
	}
	IF forceLongWait SET waitTime TO 5.0.

	LOCAL stageStartTime IS TIME:SECONDS.
	LOCAL facingVect IS SHIP:FACING:VECTOR.
	// this pause is to allow time for the rocket to face pure prograde
	UNTIL TIME:SECONDS > stageStartTime + waitTime {
		IF stageInAtm SET mySteer TO SHIP:VELOCITY:SURFACE.
		ELSE SET mySteer TO facingVect.
		WAIT 0.
	}
	STAGE.
	SET stageStartTime TO TIME:SECONDS.
	SET facingVect TO SHIP:FACING:VECTOR.
	// this pause is to allow time for the spent stage to go past the rocket
	UNTIL TIME:SECONDS > stageStartTime + waitTime {
		IF stageInAtm SET mySteer TO SHIP:VELOCITY:SURFACE.
		ELSE SET mySteer TO facingVect.
		WAIT 0.
	}
	updateShipInfo().
}

FUNCTION resourcesInParts {
	PARAMETER partList.
	LOCAL resourceList IS LEXICON().

	// for each part in the specified stage
	FOR eachPart IN partList {
		// for each resource in the part
		FOR specificResource IN eachPart:RESOURCES {
			// if there is more than 0 of the resource
			IF (specificResource:AMOUNT <> 0) {
				// if the resource is already in the list
				IF (resourceList:KEYS:CONTAINS(specificResource:NAME) ) {
					// add the amount to the existing entry in the list
					SET resourceList[specificResource:NAME] TO resourceList[specificResource:NAME] + specificResource:AMOUNT*specificResource:DENSITY*1000.
				}
				// if the resource is not already in the resource list, add the resource to the list
				ELSE {
					resourceList:ADD(specificResource:NAME, specificResource:AMOUNT*specificResource:DENSITY*1000).
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
	PARAMETER unclampPercent IS 0.85.

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

	LOCAL firstSpace IS "".
	IF isNegative SET message TO message + "-".
	IF digits > -4 AND    days <> 0 {SET message TO message + firstSpace +    days + "d". SET firstSpace TO " ".}
	IF digits > -3 AND   hours <> 0 {SET message TO message + firstSpace +   hours + "h". SET firstSpace TO " ".}
	IF digits > -2 AND minutes <> 0 {SET message TO message + firstSpace + minutes + "m". SET firstSpace TO " ".}
	IF digits > -1 AND seconds <> 0 {SET message TO message + firstSpace + seconds + "s". SET firstSpace TO " ".}

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
	PRINT PIDName AT(Xcoord, Ycoord + 0).
	PRINT "CV " + ROUND(PID:OUTPUT, 2) + "   " AT(Xcoord, Ycoord + 1).
	PRINT "PV " + ROUND(PID:INPUT, 2) + "    " AT(Xcoord, Ycoord + 2).
	PRINT "SP " + ROUND(PID:SETPOINT, 3) + "    " AT(Xcoord, Ycoord + 3).
	PRINT "Error " + ROUND(PID:ERROR, 2) + "   " AT(Xcoord, Ycoord + 4).
	PRINT "Error Sum " + ROUND(PID:ERRORSUM, 4) + "  " AT(Xcoord, Ycoord + 5).
	PRINT "ChangeRate " + ROUND(PID:CHANGERATE, 2) + "     " AT(Xcoord, Ycoord + 6).
	PRINT "KP " + ROUND(PID:KP, 4) + "     " AT(Xcoord, Ycoord + 7).
	PRINT "KI " + ROUND(PID:KI, 4) + "     " AT(Xcoord, Ycoord + 8).
	PRINT "KD " + ROUND(PID:KD, 4) + "     " AT(Xcoord, Ycoord + 9).
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
	PRINT "Period " + timeToString(orb:PERIOD) + "    " AT(Xcoord, Ycoord + 3).
	PRINT "Inclination " + ROUND(orb:INCLINATION, 4) + " degrees   " AT(Xcoord, Ycoord + 4).
	PRINT "Eccentricity " + ROUND(orb:ECCENTRICITY, 4) + "   " AT(Xcoord, Ycoord + 5).
	PRINT "Semi-Major Axis " + ROUND(orb:SEMIMAJORAXIS, 2) + "  " AT(Xcoord, Ycoord + 6).
	PRINT "Longitude of Ascending Node " + ROUND(orb:LAN, 4) + "   " AT(Xcoord, Ycoord + 7).
	PRINT "Argument of Periapsis " + ROUND(orb:ARGUMENTOFPERIAPSIS, 4) + "     " AT(Xcoord, Ycoord + 8).
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

// global list of initialized PID logs.
GLOBAL initPIDLog IS LIST().

FUNCTION logPID
{
	PARAMETER PID.
	PARAMETER filename IS "0:logfile.txt".
	PARAMETER detailed IS TRUE.
	PARAMETER number IS 0.
	IF (initPIDLog:EMPTY OR NOT initPIDLog:CONTAINS(number))
	{
		IF detailed	{LOG "Time Since Launch,Last Sample Time,Input,Setpoint,Error,Output,P Term, I Term, D Term,Kp,Ki,Kd,Max Output,Min Output" TO filename. }
		ELSE {LOG "Time Since Launch,Input,Setpoint,Error,Output" TO filename.}
		initPIDLog:ADD(number).
	}
	IF detailed {LOG timeSinceLaunch() + "," + PID:LastSampleTime + "," + PID:Input + "," + PID:Setpoint + "," + PID:Error + "," + PID:Output + "," + PID:PTerm + "," + PID:ITerm + "," + PID:DTerm + "," + PID:Kp + "," + PID:KI + "," + PID:Kd + "," + PID:MAXOUTPUT + "," + PID:MINOUTPUT TO filename.}
	ELSE {LOG timeSinceLaunch() + "," + PID:Input + "," + PID:Setpoint + "," + PID:Error + "," + PID:Output TO filename.}
	RETURN 0.
}.

// turn off all engines
FUNCTION killEngines
{
	LOCAL myVariable TO LIST().
	LIST ENGINES IN myVariable.
	FOR eng IN myVariable {
		IF (eng:IGNITION) { eng:SHUTDOWN(). }
	}.
}

// Function that updates the stpred BOUNDS from the ship.
// It should be called when the geometry of the ship changes.
FUNCTION updateBounds
{
	SET bounds TO SHIP:BOUNDS.
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
			PRINT "Delegate Rate " + ROUND(delegateRate, 5) + "       " AT (0, 20).
			PRINT "Real Time Left " + ROUND(realTimeLeft, 2) + "       " AT (0, 21).
			PRINT "Real Time Rate " + ROUND(KUNIVERSE:TIMEWARP:RATE, 2) + "       " AT (0, 22).
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
		// continue waiting until there is five seconds or less of real time remaining
		UNTIL (timeLeft < 0.5) AND (KUNIVERSE:TIMEWARP:RATE = 1) {
			// if the rate is still changing, do nothing
			IF KUNIVERSE:TIMEWARP:ISSETTLED {
				// calculate how long it will take to get to the target value in real-world seconds
				SET timeLeft TO (targetTime - TIME:SECONDS) / (KUNIVERSE:TIMEWARP:RATE).

				// warp slower, if not at min rate
				IF (timeLeft < 1) AND (KUNIVERSE:TIMEWARP:RATE <> 1) {
					SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP - 1.
				}

				// warp faster, if not at max rate - this assumes that the next rate is 10x faster than the current rate
				IF (timeLeft > 15) AND (KUNIVERSE:TIMEWARP:WARP <> KUNIVERSE:TimeWarp:RAILSRATELIST:LENGTH - 1) {
					SET KUNIVERSE:TIMEWARP:WARP TO KUNIVERSE:TIMEWARP:WARP + 1.
				}
			}
			WAIT 0.
		}
	}

	SET KUNIVERSE:timewarp:warp TO 0.
	RETURN TIME:SECONDS - startTime.
}

// Angle Difference
// This function returns the angular distance between two angles, bound between [0, 180). All angles are in degrees.
// Passed the following:
//			angle 1 (scalar, degrees)
//			angle 2 (scalar, degrees)
// Returns the following:
//			angle difference (scalar, degrees)
FUNCTION angleDifference
{
	PARAMETER angle1.
	PARAMETER angle2.
	RETURN ABS(MOD(angle1-angle2+180,360)-180).
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
	RETURN TIME:SECONDS + angleDifference(SHIP:GEOPOSITION:LNG, desiredLongitude) / 360 * SHIP:BODY:ROTATIONPERIOD.
}

// Returns time in seconds to the next time SHIP crosses the input altitude or 0 if input altitude is never crossed
FUNCTION timeToAltitude
{
  PARAMETER desiredAltitude.

  // return 0 if never reach altitude
  IF desiredAltitude < SHIP:PERIAPSIS OR desiredAltitude > SHIP:APOAPSIS RETURN 0.

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
  LOCAL meanMotion IS Constant:PI * 2 / SHIP:ORBIT:PERIOD. // in deg/s

  RETURN (desiredMeanAnomaly - currentMeanAnomaly) / meanMotion.
}

// End Script
// This function completely unlocks all control over the ship.
// Passed the following:
//			no arguments
// Returns the following:
//			null
FUNCTION endScript {
	SAS OFF.
	RCS OFF.
	UNLOCK useMySteer.
	SET useMySteer TO FALSE.
	UNLOCK mySteer.
	SET mySteer TO SHIP:FACING.

	UNLOCK useMyThrottle.
	SET useMyThrottle TO FALSE.
	UNLOCK myThrottle.
	SET myThrottle TO 0.0.

	SET SHIP:CONTROL:FORE TO 0.0.
	SET SHIP:CONTROL:STARBOARD TO 0.0.
	SET SHIP:CONTROL:PITCH TO 0.0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:MAINTHROTTLE TO 0.
	WAIT 0.0.
	SET SHIP:CONTROL:FORE TO 0.0.
	SET SHIP:CONTROL:STARBOARD TO 0.0.
	SET SHIP:CONTROL:PITCH TO 0.0.
	SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
	SET SHIP:CONTROL:MAINTHROTTLE TO 0.
	CLEARVECDRAWS().
	SET KUNIVERSE:TIMEWARP:WARP TO 0.
}

FUNCTION greatCircleDistance
{
	PARAMETER toPosition.
	PARAMETER fromPosition IS SHIP:GEOPOSITION.
	RETURN SHIP:BODY:RADIUS * Constant:DegToRad * ARCCOS(SIN(fromPosition:LAT) * SIN(toPosition:LAT) + COS(fromPosition:LAT) * COS(toPosition:LAT) * COS(ABS(fromPosition:LNG - toPosition:LNG))).
}

// Function that returns the unit vectors showing the direction of prograde,
// radial and normal for an arbitrary Orbitable at a specified time offset
// Returns a lexicon of prograde vector, radial vector, normal vector, position,
//   velocity
FUNCTION getOrbitDirectionsAt {
  PARAMETER timeOffset IS 0.
  PARAMETER orbitable IS SHIP.
  LOCAL velocityOf IS VELOCITYAT(orbitable, TIME:SECONDS + timeOffset):ORBIT.
  LOCAL positionOf IS POSITIONAT(orbitable, TIME:SECONDS + timeOffset).
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

// returns a list
// list[0] time until closest approach (seconds UT)
// list[1] distance of closest approach (meters)
FUNCTION closestApproach {
	PARAMETER initialGuess IS TIME:SECONDS.
	PARAMETER initialStepSize IS 10.
	IF (initialGuess < TIME:SECONDS) SET initialGuess TO TIME:SECONDS.
	IF NOT HASTARGET RETURN LIST(0, 0).

	LOCAL stepSize is initialStepSize.

	FUNCTION distanceAtTime {
	  PARAMETER t.
	  RETURN (POSITIONAT(SHIP, t) - POSITIONAT(TARGET, t)):MAG.
	}

	LOCAL iteration IS 0.

//	LOG "Approach Time,Step Size,Distance At Approach,Distance At Approach + Step,Distance At Approach - Step,Iteration" TO "0:HillClimb.csv".
	// Do the hill climbing
	LOCAL approachTime is initialGuess.
	UNTIL (stepSize = (initialStepSize / (2^15))) OR (iteration > 1000) {
//		LOG approachTime + "," + stepSize + "," + distanceAtTime(approachTime) + "," + distanceAtTime(approachTime + stepSize) + "," + distanceAtTime(approachTime - stepSize) + "," + iteration TO "0:HillClimb.csv".
		IF distanceAtTime(approachTime + stepSize) < distanceAtTime(approachTime) {
			SET approachTime TO approachTime + stepSize.
		} ELSE IF distanceAtTime(approachTime - stepSize) < distanceAtTime(approachTime) {
			SET approachTime TO approachTime - stepSize.
		} ELSE {
			SET stepSize TO (stepSize/2).
		}
		SET iteration TO iteration + 1.
	}

//	PRINT "Closest approach is at UT " + ROUND(approachTime, 0) + " (" + ROUND(approachTime - TIME:SECONDS, 0) + ") seconds from now, distance will be " + ROUND(distanceAtTime(approachTime), 0) + " meters".
	RETURN LIST(approachTime, distanceAtTime(approachTime)).
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
			LOG "Time,Mass,Altitude ASL,Altitude AGL,Air Pressure,Orbital Velocity,Surface Velocity,Throttle,Current Constant Accel,Current Constant mDot,Current Constant Thrust,Current Constant TWR,Current Variable Accel,Current Variable mDot,Current Variable Thrust,Current Variable TWR,Current Accel,Current BurnTime,Current mDot,Current Thrust,Current TWR,Maximum Constant Accel,Maximum Constant mDot,Maximum Constant Thrust,Maximum Constant TWR,Maximum Variable Accel,Maximum Variable mDot,Maximum Variable Thrust,Maximum Variable TWR,Maximum Accel,Maximum BurnTime,Maximum mDot,Maximum Thrust,Maximum TWR,Yaw,Pitch,Roll,Yaw Throttle,Pitch Throttle,Roll Throttle,Steering Manager Enabled,Steering Manager Angle Error,PITCHPID:KP,PITCHPID:KI,PITCHPID:KD,YAWPID:KP,YAWPID:KI,YAWPID:KD,ROLLPID:KP,ROLLPID:KI,ROLLPID:KD,Min Throttle" TO fileName.
			LOG "s,kg,m,m,atm,m/s,m/s,,m/s^2,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,m/s,kg/s,N,,m/s,kg/s,N,,m/s,s,kg/s,N,,,,,,,,,," TO fileName.
			SET logPhysicsTimeStamp TO TIME:SECONDS.
		}
		updateShipInfoCurrent(FALSE).
		LOG (TIME:SECONDS - logPhysicsTimeStamp) + "," + MASS * 1000 + "," + ALTITUDE + "," + ALT:RADAR + "," + SHIP:BODY:ATM:ALTITUDEPRESSURE(ALTITUDE) + "," + VELOCITY:ORBIT:MAG + "," + VELOCITY:SURFACE:MAG + "," + THROTTLE + "," + shipInfo["Current"]["Constant"]["Accel"] + "," + shipInfo["Current"]["Constant"]["mDot"] + "," + shipInfo["Current"]["Constant"]["Thrust"] + "," + shipInfo["Current"]["Constant"]["TWR"] + "," + shipInfo["Current"]["Variable"]["Accel"] + "," + shipInfo["Current"]["Variable"]["mDot"] + "," + shipInfo["Current"]["Variable"]["Thrust"] + "," + shipInfo["Current"]["Variable"]["TWR"] + "," + shipInfo["Current"]["Accel"] + "," + shipInfo["Current"]["BurnTime"] + "," + shipInfo["Current"]["mDot"] + "," + shipInfo["Current"]["Thrust"] + "," + shipInfo["Current"]["TWR"] + "," + shipInfo["Maximum"]["Constant"]["Accel"] + "," + shipInfo["Maximum"]["Constant"]["mDot"] + "," + shipInfo["Maximum"]["Constant"]["Thrust"] + "," + shipInfo["Maximum"]["Constant"]["TWR"] + "," + shipInfo["Maximum"]["Variable"]["Accel"] + "," + shipInfo["Maximum"]["Variable"]["mDot"] + "," + shipInfo["Maximum"]["Variable"]["Thrust"] + "," + shipInfo["Maximum"]["Variable"]["TWR"] + "," + shipInfo["Maximum"]["Accel"] + "," + shipInfo["Maximum"]["BurnTime"] + "," + shipInfo["Maximum"]["mDot"] + "," + shipInfo["Maximum"]["Thrust"] + "," + shipInfo["Maximum"]["TWR"] + "," + yaw_for(SHIP) + "," + pitch_for(SHIP) + "," + SHIP:FACING:ROLL + "," + STEERINGMANAGER:YAWPID:OUTPUT + "," + STEERINGMANAGER:PITCHPID:OUTPUT + "," + STEERINGMANAGER:ROLLPID:OUTPUT + "," + STEERINGMANAGER:ENABLED + "," + STEERINGMANAGER:ANGLEERROR + "," + STEERINGMANAGER:PITCHPID:KP + "," + STEERINGMANAGER:PITCHPID:KI + "," + STEERINGMANAGER:PITCHPID:KD + "," + STEERINGMANAGER:YAWPID:KP + "," + STEERINGMANAGER:YAWPID:KI + "," + STEERINGMANAGER:YAWPID:KD + "," + STEERINGMANAGER:ROLLPID:KP + "," + STEERINGMANAGER:ROLLPID:KI + "," + STEERINGMANAGER:ROLLPID:KD + "," + minThrottle TO fileName.
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
//   within tolerance, or the maximum number of iterations is reached.
FUNCTION findZeroSecant {
  PARAMETER delegate.
  PARAMETER X1.
  PARAMETER X2.
  PARAMETER tolerance.
  PARAMETER iteration IS 0.

  IF ((iteration = 10) OR (delegate:TYPENAME <> "UserDelegate")) RETURN delegate(X1).

  LOCAL F1 IS delegate(X1).
  LOCAL F2 IS delegate(X2).
  LOCAL X3 IS 0.
  IF (F1 <> 0) OR (F2 <> 0) SET X3 TO (X2 * F1 - X1 * F2) / (F1 - F2).
  LOCAL F3 IS delegate(X3).

  IF ABS(F3) < tolerance RETURN X3.
  RETURN  findZeroSecant(delegate, X2, X3, tolerance, iteration + 1).
}

// Using the Newton method, iterate until the function returns the chosen value
//   within tolerance, or the maximum number of iterations is reached.
FUNCTION findZeroNewton {
	PARAMETER delegateFunction.
	PARAMETER delegateSlope.
  PARAMETER initialGuess.
  PARAMETER tolerance.
	PARAMETER desiredValue IS 0.
  PARAMETER iteration IS 0.
	PARAMETER maxIterations IS 100.

  IF ((iteration >= 10) OR (NOT delegateFunction:ISTYPE("UserDelegate")) OR (NOT delegateSlope:ISTYPE("UserDelegate"))) RETURN X1.

	LOCAL slope IS delegateSlope(X1).
	LOCAL X2 IS initialGuess.
	IF slope <> 0 SET X2 TO initialGuess - delegateFunction(initialGuess)/slope.
	IF ABS(delegateFunction(initialGuess) - desiredValue) < tolerance RETURN X2.
	RETURN findZeroNewton(delegateFunction, delegateSlope, X2, tolerance, desiredValue, iteration + 1, maxIterations).
}

// given the mean anomaly (in degrees), returns true anomaly (in degrees)
FUNCTION meanToTrueAnomaly {
  PARAMETER meanAnomaly.
  PARAMETER eccentricity.

  // If eccentricity is 0, mean, true and eccentric anomaly are all the same thing, so return mean anomaly.
  IF eccentricity = 0 RETURN meanAnomaly.

  // Convert to radians for calculations.
  SET meanAnomaly TO CONSTANT:DegToRad * meanAnomaly.

  // Note that this function requires angles to be in radians
  LOCAL functionDelegate IS {PARAMETER E. RETURN E - eccentricity*SIN(CONSTANT:RadToDeg * E) - meanAnomaly.}.

  LOCAL eccentricAnomaly IS findZeroSecant(functionDelegate, meanAnomaly, meanAnomaly + CONSTANT:PI/32, 0.0000001).
  LOCAL trueAnomaly IS ARCTAN2(COS(CONSTANT:RadToDeg * eccentricAnomaly) - eccentricity, SQRT(1-eccentricity*eccentricity)*SIN(CONSTANT:RadToDeg * eccentricAnomaly)).
  UNTIL trueAnomaly >= 0 {
    SET trueAnomaly TO trueAnomaly + 360.0.
  }

  RETURN trueAnomaly.
}

// given the true anomaly (in degrees), returns mean anomaly (in degrees)
FUNCTION trueToMeanAnomaly {
  PARAMETER trueAnomaly.
  PARAMETER eccentricity.

  // If eccentricity is 0, mean, true and eccentric anomaly are all the same thing, so return mean anomaly.
  IF eccentricity = 0 RETURN trueAnomaly.

  // Convert to radians for calculations.
  SET trueAnomaly TO CONSTANT:DegToRad * trueAnomaly.

  LOCAL eccentricAnomaly IS CONSTANT:DegToRad * ARCCOS((eccentricity + COS(trueAnomaly))/(1 + eccentricity * COS(trueAnomaly))).
  LOCAL meanAnomaly IS eccentricAnomaly * CONSTANT:DegToRad - eccentricity * SIN(eccentricAnomaly).
  RETURN CONSTANT:RadToDeg * meanAnomaly.
}

// Given an angle in degrees, returns the normalized angle in degrees
FUNCTION normalizeAngle {
	PARAMETER angle.
	RETURN ARCTAN2(SIN(angle), COS(angle)).
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

FUNCTION ACOSH {PARAMETER x. RETURN LN(x + SQRT(x^2 - 1)).}

FUNCTION ASINH {PARAMETER x. RETURN LN(x + SQRT(x^2 + 1)).}
