@LAZYGLOBAL OFF.
// testStaging.ks - logs what shipInfo and stageIfNeeded (library.ks) make of the ship. Nothing is staged, ignited or moved.
// Already confirmed in game (2026-11-25): cargo on the Moho Prime, separation motors and burnt out boosters on the Moho Orbiter,
// auto-staging in a launch and in Exec, and no staging once nothing is left to light.
// Open checks (which decouplers drop away with what they decouple, see decouplerDrops):
//		1. Moho Prime with the lower stage attached: the TD-12 drops away in stage 1, and the TD-06 stays (-1). The Terrier stage is
//		   40 kg lighter than before, about 13837 kg and 2920 m/s.
//		2. Moho Orbiter: the radial decouplers and the separator under the heat shield drop away in their own STAGE, and the heat
//		   shield stays.
// Writes 0:testStaging <ship name> <real time>.csv. Needs library.ks to be loaded (it is when loop is running).

IF NOT connectionToKSC() {
	PRINT "testStaging: no connection to the archive, so nothing was logged.".
} ELSE {
	LOCAL updateStart IS TIME:SECONDS.
	updateShipInfo().
	LOCAL updateDuration IS TIME:SECONDS - updateStart.
	LOCAL checkStart IS TIME:SECONDS.
	LOCAL reasonSeen IS stageIfNeeded(TRUE, FALSE).
	LOCAL checkDuration IS TIME:SECONDS - checkStart.
	LOCAL reasonNotSeen IS stageIfNeeded(FALSE, FALSE).
	LOCAL logPath IS "0:testStaging " + SHIP:NAME + " " + ROUND(KUNIVERSE:REALTIME) + ".csv".

	LOG "Ship," + SHIP:NAME:REPLACE(",", "") + CHAR(10) +
		"Status," + SHIP:STATUS + CHAR(10) +
		"STAGE:NUMBER," + STAGE:NUMBER + CHAR(10) +
		"Parts," + SHIP:PARTS:LENGTH + CHAR(10) +
		"updateShipInfo duration," + ROUND(updateDuration, 2) + ",s" + CHAR(10) +
		"stageIfNeeded duration," + ROUND(checkDuration, 2) + ",s" + CHAR(10) +
		"stageIfNeeded with thrust seen," + reasonSeen + CHAR(10) +
		"stageIfNeeded without thrust seen," + reasonNotSeen + CHAR(10) +
		"Engines thrusting," + shipEnginesThrusting + CHAR(10) +
		"Maximum thrust," + ROUND(shipInfo["Maximum"]["Thrust"] / 1000, 1) + ",kN" TO logPath.

	// one row for each stage of shipInfo
	LOCAL stageText IS CHAR(10) + "Stages" + CHAR(10) +
		"Stage,DecoupledIn,Parts,Cargo Parts,Cargo Mass (kg),Isp (s),Thrust (kN),Current Mass (kg),Fuel Mass (kg)," +
		"Propellant Mass (kg),Propellant Capacity (kg),Delta V (m/s),Delta V Previous (m/s),Engines".
	CLEARSCREEN.
	PRINT "Stage  Din  Cargo  Engines  Fuel (kg)  Delta V (m/s)".
	FROM {LOCAL stageIndex IS 0.} UNTIL stageIndex >= shipInfo["NumberOfStages"] STEP {SET stageIndex TO stageIndex + 1.} DO {
		LOCAL stageEntry IS shipInfo["Stage " + stageIndex].
		LOCAL engineNames IS "".
		FOR eachEngine IN stageEntry["Engines"] {
			SET engineNames TO engineNames + eachEngine:CONFIG:REPLACE(",", "") + " / ".
		}
		SET stageText TO stageText + CHAR(10) + stageIndex + "," + stageEntry["DecoupledIn"] + "," + stageEntry["Parts"]:LENGTH + "," +
			stageEntry["CargoParts"]:LENGTH + "," + ROUND(stageEntry["CargoMass"], 1) + "," + ROUND(stageEntry["Isp"], 2) + "," +
			ROUND(stageEntry["Thrust"] / 1000, 1) + "," + ROUND(stageEntry["CurrentMass"], 1) + "," + ROUND(stageEntry["FuelMass"], 1) + "," +
			ROUND(stageEntry["PropellantMass"], 1) + "," + ROUND(stageEntry["PropellantCapacity"], 1) + "," +
			ROUND(stageEntry["DeltaV"], 1) + "," + ROUND(stageEntry["DeltaVPrev"], 1) + "," + engineNames.
		PRINT stageIndex:TOSTRING:PADLEFT(5) + stageEntry["DecoupledIn"]:TOSTRING:PADLEFT(5) +
			stageEntry["CargoParts"]:LENGTH:TOSTRING:PADLEFT(7) + stageEntry["Engines"]:LENGTH:TOSTRING:PADLEFT(9) +
			ROUND(stageEntry["FuelMass"]):TOSTRING:PADLEFT(11) + ROUND(stageEntry["DeltaV"]):TOSTRING:PADLEFT(15).
	}
	LOG stageText TO logPath.

	// one row for each decoupler and separator
	LOCAL decouplerText IS CHAR(10) + "Decouplers" + CHAR(10) +
		"Title,STAGE,DECOUPLEDIN,Drop Stage,shipInfo DecoupledIn,Module,Explosive Node,Omni,Parent Along Own Up Axis (m),Parent Title".
	LOCAL stageOfPart IS LEXICON().
	FROM {LOCAL stageIndex IS 0.} UNTIL stageIndex >= shipInfo["NumberOfStages"] STEP {SET stageIndex TO stageIndex + 1.} DO {
		FOR eachPart IN shipInfo["Stage " + stageIndex]["Parts"] {
			SET stageOfPart[eachPart:UID] TO shipInfo["Stage " + stageIndex]["DecoupledIn"].
		}
	}
	FOR eachPart IN SHIP:PARTS {
		LOCAL moduleName IS "".
		IF eachPart:HASMODULE("ModuleDecouple") SET moduleName TO "ModuleDecouple".
		ELSE IF eachPart:HASMODULE("ModuleAnchoredDecoupler") SET moduleName TO "ModuleAnchoredDecoupler".
		IF moduleName <> "" {
			LOCAL decoupleModule IS eachPart:GETMODULE(moduleName).
			LOCAL nodeName IS "not found".
			LOCAL omniText IS "not found".
			IF decoupleModule:HASHIDDENFIELD("explosiveNodeID") SET nodeName TO "" + decoupleModule:GETHIDDENFIELD("explosiveNodeID").
			IF decoupleModule:HASHIDDENFIELD("isOmniDecoupler") SET omniText TO "" + decoupleModule:GETHIDDENFIELD("isOmniDecoupler").
			LOCAL parentAlong IS "".
			LOCAL parentTitle IS "None".
			IF eachPart:HASPARENT {
				SET parentAlong TO ROUND(VDOT(eachPart:PARENT:POSITION - eachPart:POSITION, eachPart:FACING:FOREVECTOR), 3).
				SET parentTitle TO eachPart:PARENT:TITLE:REPLACE(",", "").
			}
			SET decouplerText TO decouplerText + CHAR(10) + eachPart:TITLE:REPLACE(",", "") + "," + eachPart:STAGE + "," +
				eachPart:DECOUPLEDIN + "," + partDropStage(eachPart) + "," + stageOfPart[eachPart:UID] + "," + moduleName + "," +
				nodeName + "," + omniText + "," + parentAlong + "," + parentTitle.
		}
	}
	LOG decouplerText TO logPath.

	// one row for each engine on the ship
	LOCAL engineText IS CHAR(10) + "Engines" + CHAR(10) +
		"Config,STAGE,DECOUPLEDIN,Can Push Ship,Cargo,IGNITION,FLAMEOUT,Possible Thrust (kN),In Current Stage".
	LOCAL engineList IS LIST().
	LIST ENGINES IN engineList.
	FOR eachEngine IN engineList {
		LOCAL inCurrentStage IS FALSE.
		FOR currentEngine IN shipInfo["CurrentStage"]["Engines"] {
			IF currentEngine:UID = eachEngine:UID SET inCurrentStage TO TRUE.
		}
		SET engineText TO engineText + CHAR(10) + eachEngine:CONFIG:REPLACE(",", "") + "," + eachEngine:STAGE + "," +
			eachEngine:DECOUPLEDIN + "," + isShipEngine(eachEngine) + "," + shipInfo["CargoUIDs"]:HASKEY(eachEngine:UID) + "," +
			eachEngine:IGNITION + "," + eachEngine:FLAMEOUT + "," + ROUND(eachEngine:POSSIBLETHRUST, 3) + "," + inCurrentStage.
	}
	LOG engineText TO logPath.

	PRINT "STAGE:NUMBER " + STAGE:NUMBER + ", maximum thrust " + ROUND(shipInfo["Maximum"]["Thrust"] / 1000, 1) + " kN".
	PRINT "stageIfNeeded: " + reasonSeen + " (thrust seen), " + reasonNotSeen + " (not seen)".
	PRINT "updateShipInfo took " + ROUND(updateDuration, 2) + " s".
	PRINT "Logged to " + logPath.
}
alertOperator().		// beep and wait, so that the result can be read
