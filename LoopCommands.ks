@LAZYGLOBAL OFF.
FUNCTION createCommandList {
	// This function returns a LEXICON of functions that contain the following data
	// Lexicon key - STRING containing the name of the function
	// Lexicon value - LEXICON containing the following information
	// 								 key PossibleArgs, value integer - maximum possible number of arguments
	// 								 key RequiredArgs, value integer - minimum possible number of arguments
	//                 key Delegate, value function delegate
	LOCAL possibleCommands IS LEXICON().
	LOCAL coreHighlight TO HIGHLIGHT(core:part, MAGENTA).
	SET coreHighlight:ENABLED TO FALSE.
	possibleCommands:ADD("debug", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On" SET debug TO TRUE.
		IF changeTo = "Off" SET debug TO FALSE.
		IF (changeTo = "Toggle") OR (changeTo = "T") SET debug TO NOT debug.
		RETURN "Debug is currently " + debug.
		})).
	possibleCommands:ADD("mode", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Default".
		IF (changeTo = "Default") OR (changeTo = "") SET loopMode TO "Default".
		ELSE SET loopMode TO changeTo.
		RETURN "LoopMode is currently " + loopMode.
		})).
	possibleCommands:ADD("solar", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		LOCAL waitTime IS 2.
		IF changeTo = "On"  {SET PANELS TO  TRUE. WAIT waitTime. RETURN  "Panels turned on".}
		IF changeTo = "Off" {SET PANELS TO FALSE. WAIT waitTime. RETURN "Panels turned off".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET PANELS TO NOT PANELS. WAIT waitTime. RETURN "Panels toggled to " + PANELS.}
		IF changeTo = "" RETURN "Panels are currently " + PANELS.
		RETURN "Panels - invalid argument".
		})).
	possibleCommands:ADD("panels", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		RETURN possibleCommands["solar"]["Delegate"](changeTo).
		})).
	possibleCommands:ADD("RCS", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On"  {SET RCS TO  TRUE. RETURN  "RCS turned on".}
		IF changeTo = "Off" {SET RCS TO FALSE. RETURN "RCS turned off".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET RCS TO NOT RCS. RETURN "RCS toggled to " + RCS.}
		IF changeTo = "" RETURN "RCS is currently " + RCS.
		RETURN "RCS - invalid argument".
		})).
	possibleCommands:ADD("SAS", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On"  {SET SAS TO  TRUE. RETURN  "SAS turned on".}
		IF changeTo = "Off" {SET SAS TO FALSE. RETURN "SAS turned off".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET SAS TO NOT SAS. RETURN "SAS toggled to " + SAS.}
		IF changeTo = "" RETURN "RCS is currently " + RCS.
		RETURN "SAS - invalid argument".
		})).
	possibleCommands:ADD("stopTime", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER newTime.
		IF newTime = "" RETURN "Max Stopping time is " + STEERINGMANAGER:MAXSTOPPINGTIME.
		SET STEERINGMANAGER:MAXSTOPPINGTIME TO newTime.
		RETURN "Changed Max Stopping time to " + STEERINGMANAGER:MAXSTOPPINGTIME.
		})).
	possibleCommands:ADD("warp", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER newPermission.
		IF newPermission = "" RETURN "Physics Warp Perm is currently " + (physicsWarpPerm + 1).
		IF ((newPermission = "Up") AND (physicsWarpPerm <> 3)) SET physicsWarpPerm TO physicsWarpPerm + 1.
		ELSE IF ((newPermission = "Down") AND (physicsWarpPerm <> 0)) SET physicsWarpPerm TO physicsWarpPerm - 1.
		ELSE SET physicsWarpPerm TO newPermission + 1.
		RETURN "Changed Physics Warp Perm to " + (physicsWarpPerm + 1).
		})).
	possibleCommands:ADD("physicsWarp", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER newPermission.
		RETURN possibleCommands["warp"]["Delegate"](newPermission).
		})).
	possibleCommands:ADD("GEAR", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On"  {SET GEAR TO  TRUE. RETURN  "Gear turned on".}
		IF changeTo = "Off" {SET GEAR TO FALSE. RETURN "Gear turned off".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET GEAR TO NOT GEAR. RETURN "Gear toggled to " + GEAR.}
		IF changeTo = "" RETURN "Gear are currently " + GEAR.
		RETURN "Gear - invalid argument".
		})).
	possibleCommands:ADD("LIGHTS", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On"  {SET LIGHTS TO  TRUE. RETURN  "Lights turned on".}
		IF changeTo = "Off" {SET LIGHTS TO FALSE. RETURN "Lights turned off".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET LIGHTS TO NOT LIGHTS. RETURN "Lights toggled to " + LIGHTS.}
		IF changeTo = "" RETURN "Lights are currently " + LIGHTS.
		RETURN "Lights - invalid argument".
		})).
	possibleCommands:ADD("RADIATORS", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On"  {SET RADIATORS TO  TRUE. RETURN  "Radiators turned on".}
		IF changeTo = "Off" {SET RADIATORS TO FALSE. RETURN "Radiators turned off".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET RADIATORS TO NOT RADIATORS. RETURN "Radiators toggled to " + RADIATORS.}
		IF changeTo = "" RETURN "Radiators are currently " + RADIATORS.
		RETURN "Radiators - invalid argument".
		})).
	possibleCommands:ADD("DRILL", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER desiredState.
		IF desiredState = "On" 			{DRILLS  ON. RETURN "Drills started".}
		IF desiredState = "Off" 		{DRILLS OFF. RETURN "Drills stopped".}
		IF desiredState = "Deploy" 	{DEPLOYDRILLS  ON. WAIT 1.}
		IF desiredState = "Retract" {DEPLOYDRILLS OFF. WAIT 1.}
		IF (DEPLOYDRILLS) {
			IF DRILLS RETURN "Drills are deployed and running.".
			RETURN "Drills are deployed".
		} ELSE {
			IF DRILLS RETURN "Drills are retracted but running".
			RETURN "Drills are retracted and stopped".
		}
		})).
	possibleCommands:ADD("DRILLS", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER desiredState.
		RETURN possibleCommands["DRILL"]["Delegate"](desiredState).
		})).
	possibleCommands:ADD("AUGER", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On" {
			FOR auger IN augerList auger:getModule("ELExtractor"):DOACTION("start auger",TRUE).
			RETURN "Augers have been turned ON".
		}
		IF changeTo = "Off" {
			FOR auger IN augerList auger:getModule("ELExtractor"):DOACTION("stop auger",TRUE).
			RETURN "Augers have been turned OFF".
		}
		RETURN "Augers - invalid arguments".
		})).
	possibleCommands:ADD("AUGERS", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		RETURN possibleCommands["AUGER"]["Delegate"](changeTo).
		})).
	possibleCommands:ADD("smelter", LEXICON("PossibleArgs", 2, "RequiredArgs", 1, "Delegate", {
		PARAMETER resourceNameOrAction.
		PARAMETER action IS "On".
		IF resourceNameOrAction = "On" {
			FOR smelter IN smelterList {smelter:getModule("ELConverter"):DOACTION("start metal conversion",TRUE). smelter:getModule("ELConverter"):DOACTION("toggle converter",TRUE).}.
			RETURN "Started smelting metal and melting scrap metal".
		}
		IF resourceNameOrAction = "Off" {
			FOR smelter IN smelterList {smelter:getModule("ELConverter"):DOACTION("stop metal conversion",TRUE). smelter:getModule("ELConverter"):DOACTION("toggle converter",FALSE).}.
			RETURN "Stopped smelting metal and melting scrap metal".
		}
		IF resourceNameOrAction = "Metal" {
			IF action = "On" {
				FOR smelter IN smelterList {smelter:getModule("ELConverter"):DOACTION("start metal conversion",TRUE).}.
				RETURN "Started Smelting Metal".
			}
			IF action = "Off" {
				FOR smelter IN smelterList {smelter:getModule("ELConverter"):DOACTION("stop metal conversion",TRUE).}.
				RETURN "Stopped Smelting Metal".
			}
		}
		IF resourceNameOrAction = "Scrap" {
			IF action = "On" {
				FOR smelter IN smelterList {smelter:getModule("ELConverter"):DOACTION("toggle converter",TRUE).}.
				RETURN "Started Melting Scrap Metal".
			}
			IF action = "Off" {
				FOR smelter IN smelterList {smelter:getModule("ELConverter"):DOACTION("toggle converter",FALSE).}.
				RETURN "Stopped Melting Scrap Metal".
			}
		}
		RETURN "Smelters - invalid arguments".
		})).
	possibleCommands:ADD("smelters", LEXICON("PossibleArgs", 2, "RequiredArgs", 1, "Delegate", {
		PARAMETER resourceNameOrAction.
		PARAMETER action IS "On".
		RETURN possibleCommands["smelter"]["Delegate"](resourceNameOrAction, action).
		})).
	possibleCommands:ADD("point", LEXICON("PossibleArgs", 3, "RequiredArgs", 2, "Delegate", {
		PARAMETER yawSetpoint.
		PARAMETER pitchSetpoint.
		PARAMETER rollSetpoint IS 0.
		SET autoSteer TO "point," + yawSetpoint + "," + pitchSetpoint + "," + rollSetpoint.
		RETURN "Steering held to (" + ROUND(yawSetpoint) + "," + ROUND(pitchSetpoint) + "," + ROUND(rollSetpoint) + ")".
		})).
	possibleCommands:ADD("node", LEXICON("PossibleArgs", 4, "RequiredArgs", 1, "Delegate", {
		// note that NODE has syntax of (time, radial, normal, prograde).
		// this command rearranges that to be (prograde, normal, radial, time from now)
		PARAMETER arg1.
		PARAMETER arg2 IS 0.
		PARAMETER arg3 IS 0.
		PARAMETER arg4 IS 60.

		// if the first argument is "delete" or "remove", delete the next node.
		IF arg1 = "delete" OR arg1 = "remove" {
			IF HASNODE {
				REMOVE NEXTNODE.
				RETURN "Removed next node".
			} ELSE RETURN "No next node to delete!".
		}
		// If the first argument is not "delete" or "remove"
		ELSE {
			IF arg1:TYPENAME = "STRING" RETURN "node - invalid arguments".
			ADD NODE(TIME:SECONDS + arg4, arg3, arg2, arg1).
			RETURN "Node created with 4 arguments".
		}
		RETURN "node - invalid arguments".
		})).
	possibleCommands:ADD("ISRU", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On" SET ISRU TO TRUE.
		IF changeTo = "Off" SET ISRU TO FALSE.
		IF (changeTo = "Toggle") OR (changeTo = "T") SET ISRU TO NOT ISRU.
		IF changeTo = "" RETURN "ISRU is currently " + ISRU.
		RETURN "ISRUs are currently " + ISRU.
		})).
	possibleCommands:ADD("CONVERTER", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		RETURN possibleCommands["ISRU"]["Delegate"](changeTo).
		})).
	possibleCommands:ADD("mining", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER changeTo.
		IF changeTo = "On" {ISRU ON. RADIATORS ON. FUELCELLS ON. DEPLOYDRILLS ON. WAIT 0.5. DRILLS ON. RETURN "Surface mining started".}
		IF changeTo = "Off" {ISRU OFF. RADIATORS OFF. FUELCELLS OFF. DEPLOYDRILLS OFF. RETURN "Surface mining stopped".}
		RETURN "Mining - invalid arguments".
		})).
	possibleCommands:ADD("FUELCELL", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On" SET FUELCELLS TO TRUE.
		IF changeTo = "Off" SET FUELCELLS TO FALSE.
		IF (changeTo = "Toggle") OR (changeTo = "T") SET FUELCELLS TO NOT FUELCELLS.
		IF changeTo = "" RETURN "Fuelcells are currently " + FUELCELLS.
		RETURN "Fuelcells are currently " + FUELCELLS.
		})).
	possibleCommands:ADD("FUELCELLS", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		RETURN possibleCommands["FUELCELL"]["Delegate"](changeTo).
		})).
	possibleCommands:ADD("OMNI", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER changeTo IS "On".
		IF changeTo = "On" {activateOmniAntennae(). RETURN "Omni antennae have been activated.".}
		IF changeTo = "Off" {deactivateOmniAntennae(). RETURN "Omni antennae have been deactivated.".}
		RETURN "Omni - invalid arguments".
		})).
	possibleCommands:ADD("DISH", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER changeTo IS "On".
		IF changeTo = "On" {activateDishAntennae(). RETURN "Dish antennae have been activated.".}
		IF changeTo = "Off" {activateDishAntennae(). RETURN "Dish antennae have been deactivated.".}
		RETURN "Dish - invalid arguments".
		})).
	possibleCommands:ADD("Highlight", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER changeTo IS "Toggle".
		IF changeTo = "On" {SET coreHighlight:ENABLED TO TRUE. RETURN "Core highlighting turned on.".}
		IF changeTo = "Off" {SET coreHighlight:ENABLED TO FALSE. RETURN "Core highlighting turned off.".}
		IF (changeTo = "Toggle") OR (changeTo = "T") {SET coreHighlight:ENABLED TO NOT coreHighlight:ENABLED. RETURN "Core highlighting toggled to " + coreHighlight:ENABLED.}
		IF changeTo = "" RETURN "Highlighting is currently " + coreHighlight:ENABLED.
		RETURN "Highlight - invalid argument".
		})).
	possibleCommands:ADD("rename", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER newName.
		SET SHIP:NAME TO newName.
		RETURN "Ship renamed to " + SHIP:NAME.
		})).
	possibleCommands:ADD("nameship", LEXICON("PossibleArgs", 1, "RequiredArgs", 1, "Delegate", {
		PARAMETER newName.
		RETURN possibleCommands["rename"]["Delegate"](newName).
		})).
	possibleCommands:ADD("warpToAltitude", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER desiredAltitude IS 10000.
		IF (processScalarParameter(desiredAltitude, errorValue) <> errorValue) {
			LOCAL warpAltitude IS processScalarParameter(desiredAltitude).
			IF (SHIP:BODY:ATM:EXISTS) SET warpAltitude TO MAX(SHIP:BODY:ATM:HEIGHT + 10000, warpAltitude).
			warpToTime(TIME:SECONDS + timeToAltitude(warpAltitude)).
			RETURN "Warped to altitude of " + distanceToString(warpAltitude).
		}
		RETURN "warpToAltitude - invalid argument".
		})).
	possibleCommands:ADD("target", LEXICON("PossibleArgs", 2, "RequiredArgs", 0, "Delegate", {
		PARAMETER arg1 IS "".
		PARAMETER arg2 IS "".
		IF arg1 = "SET" {
			LOCAL possibleTargets IS LIST().
			LIST TARGETS IN possibleTargets.
			FOR possibleTarget IN possibleTargets {
				IF possibleTarget:NAME = arg2 {
					SET TARGET TO VESSEL(arg2). RETURN "Target now set to " + TARGET:NAME.
				}
			}
			LIST BODIES IN possibleTargets.
			FOR possibleTarget IN possibleTargets {
				IF possibleTarget:NAME = arg2 {
					SET TARGET TO BODY(arg2). RETURN "Target now set to " + TARGET:NAME.
				}
			}
			RETURN "Target set - invalid argument " + arg2.
		}
		IF arg1 = "UNSET" {
			SET TARGET TO "".
			RETURN "Target unset".
		}
		IF HASTARGET {
			IF arg1 = "" {
				SET autoSteer TO "target,".
				IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") RETURN "Steering locked to " + TARGET:TITLE + " on " + TARGET:SHIP:NAME.
				ELSE RETURN "Steering locked to " + TARGET:NAME.
			}
			IF arg1 = "anti" 													{SET autoSteer TO "target,anti".				RETURN "Steering locked to anti target".}
			IF arg1 = "retro" OR arg1 = "retrograde" 	{SET autoSteer TO "target,retrograde".	RETURN "Steering locked to target retrograde".}
			IF arg1 = "pro" OR arg1 = "prograde" 			{SET autoSteer TO "target,prograde". 		RETURN "Steering locked to target prograde".}
			IF arg1 = "facing" 												{SET autoSteer TO "target,facing".			RETURN "Steering locked to target facing".}
			IF arg1 = "antifacing" 										{SET autoSteer TO "target,antifacing".	RETURN "Steering locked to target facing".}
		} ELSE {RETURN "Must have a target set.".}
		})).
	possibleCommands:ADD("hold",        LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "hold". RETURN "Steering held at current".})).
	possibleCommands:ADD("up",          LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "up". RETURN "Steering locked to up".})).
	possibleCommands:ADD("down", 				LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "down". RETURN "Steering locked to down".})).
	possibleCommands:ADD("north", 			LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "north". RETURN "Steering locked to north".})).
	possibleCommands:ADD("south", 			LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "south". RETURN "Steering locked to south".})).
	possibleCommands:ADD("prograde", 		LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "prograde". RETURN "Steering locked to orbit prograde".})).
	possibleCommands:ADD("retrograde", 	LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "retrograde". RETURN "Steering locked to orbit retrograde".})).
	possibleCommands:ADD("radialin", 		LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "radialin". RETURN "Steering locked to radial in".})).
	possibleCommands:ADD("radialout", 	LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "radialout". RETURN "Steering locked to radial out".})).
	possibleCommands:ADD("normal", 			LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "normal". RETURN "Steering locked to normal".})).
	possibleCommands:ADD("antinormal",	LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "antinormal". RETURN "Steering locked to antinormal".})).
	possibleCommands:ADD("srfPro", 			LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "surfaceprograde". RETURN "Steering locked to surface prograde".})).
	possibleCommands:ADD("srfRetro", 		LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {SET autoSteer TO "surfaceretrograde". RETURN "Steering locked to surface retrograde".})).
	possibleCommands:ADD("landLift",		LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER invertRoll IS TRUE.
		IF invertRoll SET autoSteer TO "landliftnormal".
		ELSE SET autoSteer TO "landliftreverse".
		RETURN "Roll control only enabled.".
		})).

	possibleCommands:ADD("maneuver", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER direct IS TRUE.
		IF HASNODE {
			IF direct SET autoSteer TO "maneuverdirect".
			ELSE SET autoSteer TO "maneuverinverse".
			RETURN "Steering locked to maneuver".
		}
		RETURN "No maneuver node to point to!".
		})).
	possibleCommands:ADD("distTgtPlane", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		RETURN ROUND(distanceToTargetOrbitalPlane(), 4) + " km to target's orbital plane".
		})).
	possibleCommands:ADD("reboot", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		debugString("Reboot").
		REBOOT.
		})).
	possibleCommands:ADD("reboot.", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		possibleCommands["reboot"]["Delegate"]().
		REBOOT.
		})).

	possibleCommands:ADD("update", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		IF (connectionToKSC()) {
			copyToLocal().
			RETURN "Updated all scripts from the archive".
		}
		RETURN "Not connected to KSC - cannot update scripts".
		})).

	possibleCommands:ADD("listFiles", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		listFiles().
		RETURN "Files listed".
		})).

	possibleCommands:ADD("apoapsis", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER delayTime IS 10.
		IF delayTime < 0 SET delayTime TO 0.
		IF (NOT ORBIT:HASNEXTPATCH) OR (ORBIT:HASNEXTPATCH AND ETA:APOAPSIS < ORBIT:NEXTPATCHETA) {
			warpToTime(TIME:SECONDS + ETA:APOAPSIS - delayTime).
			RETURN "Warped to apoapsis - " + delayTime + " seconds".
		}
		RETURN "Orbit transitions before apoapsis!".
		})).
	possibleCommands:ADD("apo", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {PARAMETER delayTime IS 10. RETURN possibleCommands["Apoapsis"]["Delegate"](delayTime).})).


	possibleCommands:ADD("periapsis", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER delayTime IS 10.
		IF delayTime < 0 SET delayTime TO 0.
		IF (NOT ORBIT:HASNEXTPATCH) OR (ORBIT:HASNEXTPATCH AND ETA:PERIAPSIS < ORBIT:NEXTPATCHETA) {
			warpToTime(TIME:SECONDS + ETA:PERIAPSIS - delayTime).
			RETURN "Warped to periapsis - " + delayTime + " seconds".
		}
		RETURN "Orbit transitions before periapsis!".
		})).
	possibleCommands:ADD("peri", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {PARAMETER delayTime IS 10. RETURN possibleCommands["periapsis"]["Delegate"](delayTime).})).

	possibleCommands:ADD("transition", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER delayTime IS 10.
		IF delayTime < 0 SET delayTime TO 0.
		IF (ORBIT:HASNEXTPATCH) {
			warpToTime(TIME:SECONDS + ETA:TRANSITION - delayTime).
			RETURN "Warped to transition - " + delayTime + " seconds".
		}
		RETURN "Orbit has no transition!".
		})).
	possibleCommands:ADD("trans", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {PARAMETER delayTime IS 10. RETURN possibleCommands["transition"]["Delegate"](delayTime).})).

	possibleCommands:ADD("stage", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		stageFunction().
		RETURN "Manually Staged!".
		})).

	possibleCommands:ADD("local", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		IF connectionToKSC() {
			copyToLocal().
			SWITCH TO 1.
			SET runLocal TO TRUE.
			RETURN "Updated all scripts, running locally".
		}
		RETURN "Already running locally".
		})).

	possibleCommands:ADD("remote", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		IF connectionToKSC() {
			SWITCH TO 0.
			SET runLocal TO FALSE.
			RETURN "Switched to running on the archive".
		}
		RETURN "KSC not accessible".
		})).
	possibleCommands:ADD("archive", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {RETURN possibleCommands["remote"]["Delegate"]().})).

	possibleCommands:ADD("hide", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		CORE:PART:GETMODULE("kOSProcessor"):DOEVENT("Close Terminal").
		RETURN "Terminal Hidden".
		})).

	possibleCommands:ADD("stageUpdate", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		// Recalculate the staging information for the ship, but do not log it to a file
		updateShipInfo().
		RETURN "shipInfo has been updated".
		})).

	possibleCommands:ADD("stageInfo", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		// Recalculate the staging information for the ship, and log it to a file
		// pause briefly to allow operator to see info on the screen.
		updateShipInfo().
		logShipInfo().
		WAIT 5.
		RETURN SHIP:NAME + " Info Stage " + STAGE:NUMBER + ".csv has been created.".
		})).

	possibleCommands:ADD("logActions", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {logAllActions(). RETURN "Action file created!".})).
	possibleCommands:ADD("log actions", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {RETURN possibleCommands["logActions"]["Delegate"]().})).
	possibleCommands:ADD("actions", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {RETURN possibleCommands["logActions"]["Delegate"]().})).

	possibleCommands:ADD("logParts", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {logAllActions(). RETURN "Part file created!".})).
	possibleCommands:ADD("log parts", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {RETURN possibleCommands["logParts"]["Delegate"]().})).
	possibleCommands:ADD("parts", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {RETURN possibleCommands["logParts"]["Delegate"]().})).

	possibleCommands:ADD("List bodies", LEXICON("PossibleArgs", 1, "RequiredArgs", 0, "Delegate", {
		PARAMETER logFileName IS "Bodies.csv".
		// Create and log to a file on the archive a list of all bodies and their properties.
		IF connectionToKSC() {
			LOG "Name,Description,Mass,Radius,Rotation Period,MU,SOI Radius" TO "0:" + logFileName.
			FOR bod in bodList {
				IF (bod:NAME = "Sun" OR bod:NAME = "Kerbol") {LOG bod:NAME + "," + bod:DESCRIPTION:REPLACE(",","") + "," + bod:MASS + "," + bod:RADIUS + "," + bod:ROTATIONPERIOD + "," + bod:MU + ",infinite" TO "0:" + logFileName.}
				ELSE LOG bod:NAME + "," + bod:DESCRIPTION:REPLACE(",","") + "," + bod:MASS + "," + bod:RADIUS + "," + bod:ROTATIONPERIOD + "," + bod:MU + "," + bod:SOIRADIUS TO "0:" + logFileName.
			}
			RETURN "0:" + logFileName + " file created!".
		}
		RETURN "No connection to KSC, so no list created".
		})).

	// point toward each of the bodies in the solar system, if needed.
	FOR bod in bodList {
		LOCAL selectedBody IS bod.
		possibleCommands:ADD(selectedBody:NAME, LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
			SET autoSteer TO selectedBody:NAME.
			RETURN "Steering locked to facing " + selectedBody:NAME.
			})).
	}

	possibleCommands:ADD("body", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {RETURN possibleCommands["down"]["Delegate"]().})).

	// Kill command - stops all control of the vehicle
	// intended to allow the operator to stop after entering one of the above commands
	possibleCommands:ADD("kill", LEXICON("PossibleArgs", 0, "RequiredArgs", 0, "Delegate", {
		endScript().
		RETURN "Automatic control disabled and reset".
		})).
	RETURN possibleCommands.
}
PRINT "Loop Commands Run!".
