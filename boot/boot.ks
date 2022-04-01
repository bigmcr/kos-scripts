@LAZYGLOBAL OFF.

LOCAL stockWorldDetermined IS FALSE.
LOCAL stockRocketsDetermined IS FALSE.
LOCAL lastStockWorld IS FALSE.
LOCAL lastStockRockets IS FALSE.
LOCAL fileListAndContents IS LEXICON().
LOCAL fileList IS LIST().
SWITCH TO 0.
LIST FILES IN fileList.
FOR f IN fileList {
	IF f:NAME:ENDSWITH(".ks") {
		fileListAndContents:ADD(f:NAME:SUBSTRING(0, f:NAME:LENGTH - f:EXTENSION:LENGTH - 1), f:READALL).
	}
}

// Is Stock Universe
// This function returns TRUE if the ship is operating in the stock KSP universe.
// This is determined by reading the .settings file
// Passed the following:
//			no arguments
// Returns the following:
//			whether or not the ship is in KSP Universe (bool)
FUNCTION isStockWorld {
	IF stockWorldDetermined RETURN lastStockWorld.

	LOCAL fileList IS LIST().
	IF connectionToKSC() SET fileList TO ARCHIVE:FILES.
	ELSE SET fileList TO CORE:VOLUME:FILES.
	SET lastStockWorld TO FALSE.
	FOR fileName IN fileList:KEYS {
		IF (fileName = "StockWorld.settings") {
			SET stockWorldDetermined TO TRUE.
			SET lastStockWorld TO TRUE.
			RETURN TRUE.
		}
		IF (fileName = "RSSWorld.settings") {
			SET stockWorldDetermined TO TRUE.
			SET lastStockWorld TO FALSE.
			RETURN FALSE.
		}
	}
}

// Is Stock Rockets
// This function returns TRUE if the ship is composed of stock KSP parts only.
// If this isn't true, code can take ullage, slower turn times, restricted power, etc. into account.
// This is determined by reading the .settings file
// Passed the following:
//			no arguments
// Returns the following:
//			whether or not the ship uses only stock parts (bool)
FUNCTION isStockRockets {
	IF stockRocketsDetermined RETURN lastStockRockets.
	LOCAL fileList IS LIST().
	IF connectionToKSC() SET fileList TO ARCHIVE:FILES.
	ELSE SET fileList TO CORE:VOLUME:FILES.
	SET lastStockRockets TO FALSE.
	FOR fileName IN fileList:KEYS {
		IF (fileName = "StockRockets.settings") {
			SET stockRocketsDetermined TO TRUE.
			SET lastStockRockets TO TRUE.
			RETURN TRUE.
		}
		IF (fileName = "RSSRockets.settings") {
			SET stockRocketsDetermined TO TRUE.
			SET lastStockRockets TO FALSE.
			RETURN FALSE.
		}
	}
}

// Connection to KSC
// This function returns TRUE if the archive is accessible.
// Passed the following:
//			no arguments
// Returns the following:
//			whether or not the ship uses only stock parts (bool)
FUNCTION connectionToKSC {
	RETURN HOMECONNECTION:ISCONNECTED.
}

FUNCTION debugString {
	PARAMETER message.
	IF connectionToKSC() LOG SHIP:NAME + "," + message TO "0:Logfile.txt".
}

FUNCTION compileScript {
	PARAMETER scriptName.
	PARAMETER destination IS "0:KSM Files/".
	IF connectionToKSC {
		IF scriptName:ENDSWITH(".ks") SET scriptName TO scriptName:SUBSTRING(0, scriptName:LENGTH - 3).
		IF EXISTS("0:KSM Files/" + scriptName + ".ksm") DELETEPATH("0:KSM Files/" + scriptName + ".ksm").
		IF EXISTS("0:" + scriptName + ".ksm") DELETEPATH("0:" + scriptName + ".ksm").
		COMPILE "0:" + scriptName TO destination + scriptName + ".ksm".
	}
}

// copy the passed script to the given destination
// compiles the script and copies over the ks or KSM version, whichever is smaller.
FUNCTION copyScript {
	PARAMETER scriptName.
	PARAMETER destination IS "0:Staging/".
	PARAMETER deleteTempFiles IS FALSE.

	IF NOT connectionToKSC() RETURN FALSE.

	// sanitize the input script name
	IF scriptName:ENDSWITH(".ks") SET scriptName TO scriptName:SUBSTRING(0, scriptName:LENGTH - 3).
	IF scriptName:ENDSWITH(".ksm") SET scriptName TO scriptName:SUBSTRING(0, scriptName:LENGTH - 4).

	// go to the archive and compile the passed file.
	compileScript(scriptName, "0:TempFolder/").
	LOCAL ksFile IS OPEN("0:" + scriptName + ".ks").
	LOCAL ksmFile IS OPEN("0:TempFolder/" + scriptName + ".ksm").
	IF ksmFile:SIZE < ksFile:SIZE {
		COPYPATH("0:TempFolder/" + ksmFile:NAME, destination + ksmFile:NAME).
	}
	ELSE {
		COPYPATH(ksFile:NAME, destination + ksFile:NAME).
	}
	IF deleteTempFiles DELETEPATH("0:TempFolder").
	RETURN TRUE.
}

FUNCTION copyToLocal {
	IF NOT connectionToKSC() RETURN FALSE.
	CLEARSCREEN.

	// if the maneuver node script already exists on the volume, only copy over updated files
	// I.E. files that don't match the original.
	IF EXISTS("1:exec") {
		CLEARSCREEN.
		SWITCH TO 0.
		LOCAL fileListRoot IS LIST().
		LIST FILES IN fileListRoot.
		LOCAL fNameWOExtension IS "".
		FOR f IN fileListRoot {
			SET fNameWOExtension TO f:NAME:SUBSTRING(0, f:NAME:LENGTH - f:EXTENSION:LENGTH - 1).
			IF f:EXTENSION = "ks" {
				IF fileListAndContents:KEYS:CONTAINS(fNameWOExtension) {
					IF f:READALL:LENGTH <> fileListAndContents[fNameWOExtension]:LENGTH {
						PRINT f:NAME + " has changed, updating it now".
						copyScript(f:NAME, "1:").
					}
				}
			}
		}
		DELETEPATH("0:TempFolder").
		PRINT "Finished reviewing files".
		WAIT 1.
	} ELSE {
		// if the maneuver node script doesn't already exist, copy everything over.
		DELETEPATH("0:Staging").
		CD("0:").
		LIST FILES IN fileList.
		FOR f IN fileList {
			IF f:NAME:ENDSWITH(".ks") copyScript(f:NAME, "0:Staging/", TRUE).
		}
		CD("0:Staging").
		LIST FILES IN fileList.
		PRINT "Now checking if there is enough room for all files on the local volume.".
		LOCAL usedSpace IS 0.
		FOR f IN fileList {
			IF f:NAME:ENDSWITH(".ksm") OR f:NAME:ENDSWITH(".ks") {
				SET usedSpace TO usedSpace + (f:SIZE).
			}
		}

		PRINT "Total of " + usedSpace + " bytes in files".
		IF usedSpace < CORE:VOLUME:CAPACITY {
			SWITCH TO 1.
			PRINT "There is enough room for all files on the local volume.".
			PRINT "Now deleting all files on the local volume.".
			SET fileList TO CORE:VOLUME:FILES.
			FOR f IN fileList:KEYS {
				IF DELETEPATH(f).
			}

			COMPILE "0:boot/boot.ks" TO "1:boot.ksm".
			SET CORE:BOOTFILENAME    TO "/boot.ksm".
			PRINT "Boot file name set to " + CORE:BOOTFILENAME.

			PRINT "Now compiling all scripts.".
			CD("0:Staging").
			LIST FILES IN fileList.
			FOR f IN fileList {
				IF f:EXTENSION = "ksm" OR f:EXTENSION = "ks" {
					COPYPATH(f:NAME, "1:" + f:NAME).
				}
			}
			CD("0:").
			LIST FILES IN fileList.
			FOR f IN fileList {
				IF f:EXTENSION = "settings" {
					COPYPATH(f:NAME, "1:" + f:NAME).
				}
			}
			WAIT 1.
			SWITCH TO 1.
			RETURN TRUE.
		} ELSE {
			PRINT "There is not enough space on the local volume".
			PRINT "Not copying files to the local volume".
			RETURN FALSE.
		}
		DELETEPATH("0:Staging").
	}
}

WAIT 0.25.

IF KUNIVERSE:TIMEWARP:RATE < 100 core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
SET TERMINAL:BRIGHTNESS TO 1.
SET TERMINAL:WIDTH TO 80.
SET TERMINAL:HEIGHT TO 50.

LOCAL loopFound TO FALSE.

isStockWorld().
isStockRockets().

// default to running on the local drive, if all the files are loaded already
IF EXISTS("1:/loop.ksm") AND EXISTS("1:/loopCommands.ksm") AND EXISTS("1:loopTerminal.ksm") AND EXISTS("1:Library.ksm") {
	SET loopFound TO TRUE.
	PRINT "Found local loop with valid settings".
}
ELSE {
	// if loop.ksm does not exist on the local drive, check to see if we can copy it from the archive
	IF (connectionToKSC()) {
		PRINT "Copying scripts to local hard drive".
		IF copyToLocal() {
			PRINT "Sucessfully copied files to local drive".
			SET loopFound TO TRUE.
		} ELSE PRINT "Failed to copy files to local drive".
	} ELSE {
		PRINT "Loop.ksm does not exist on the local drive".
		PRINT "Or there are not valid settings".
		PRINT "There is no connection to the archive".
		PRINT "Not running anything in particular".
	}
}

IF loopFound {
	PRINT "Running local Loop.ksm".
	WAIT 1.
	SWITCH TO 1.
	RUNPATH("1:loop").
}
PRINT "Returning control to the terminal".
