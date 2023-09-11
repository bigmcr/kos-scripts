@LAZYGLOBAL OFF.

SET CONFIG:IPU TO 2000.
LOCAL stockWorldDetermined IS FALSE.
LOCAL stockRocketsDetermined IS FALSE.
LOCAL lastStockWorld IS FALSE.
LOCAL lastStockRockets IS FALSE.
LOCAL fileListAndContents IS LEXICON().
LOCAL fileList IS LIST().
IF connectionToKSC() SWITCH TO 0.
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

	LOCAL bodyList IS LIST().
	LIST BODIES IN bodyList.
	SET lastStockWorld TO FALSE.
	FOR oneBody IN bodyList {
		IF (oneBody:NAME = "Kerbin") OR (oneBody:NAME = "Minmus") {
			SET stockWorldDetermined TO TRUE.
			SET lastStockWorld TO TRUE.
			RETURN TRUE.
		}
	}
	RETURN FALSE.
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
	RETURN FALSE.
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

// copy the passed script to the given destination
// compiles the script and copies over the ks or KSM version, whichever is smaller.
FUNCTION copyScript {
	PARAMETER scriptName.
	PARAMETER destination IS "0:Staging/".

	IF NOT connectionToKSC() RETURN FALSE.

	// strip out the ".ks" at the end of the script name
	SET scriptName TO scriptName:SUBSTRING(0, scriptName:LENGTH - 3).

	// go to the archive and compile the passed file.
	COMPILE "0:" + scriptName TO "0:TempFolder/" + scriptName + ".ksm".
	LOCAL ksFile IS OPEN("0:" + scriptName + ".ks").
	LOCAL ksmFile IS OPEN("0:TempFolder/" + scriptName + ".ksm").
	IF ksmFile:SIZE < ksFile:SIZE {
		COPYPATH("0:TempFolder/" + ksmFile:NAME, destination + ksmFile:NAME).
	}
	ELSE {
		COPYPATH(ksFile:NAME, destination + ksFile:NAME).
	}
	RETURN TRUE.
}

FUNCTION copyToLocal {
	PARAMETER forcedUpdate IS FALSE.
	IF NOT connectionToKSC() RETURN FALSE.

	// if the maneuver node script already exists on the volume, only copy over updated files
	// I.E. files that don't match the original.
	IF (EXISTS("1:exec") AND (NOT forcedUpdate)) {
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
		CLEARSCREEN.
		// if the maneuver node script doesn't already exist, or if forcedUpdate is TRUE, copy everything over.
		CD("0:").
		PRINT "Now compiling files to 0:Staging/".
		LIST FILES IN fileList.
		LOCAL ksFilesCount IS 0.
		FOR f IN fileList {
			IF f:NAME:ENDSWITH(".ks") {
				PRINT "Compiling and copying file " + (ksFilesCount + 1) + " - " + f:NAME + "             " AT (0, 1).
				SET ksFilesCount TO ksFilesCount + 1.
				copyScript(f:NAME, "0:Staging/").
			}
		}
		DELETEPATH("0:TempFolder").
		PRINT "C".
		PRINT "Files compiled and copied.                       ".
		CD("0:Staging").
		LIST FILES IN fileList.
		PRINT "Now checking if there is enough room for all files on the local volume.".
		LOCAL usedSpace IS 0.
		FOR f IN fileList {SET usedSpace TO usedSpace + (f:SIZE).}

		PRINT "Total of " + usedSpace + " bytes in files".
		IF usedSpace < CORE:VOLUME:CAPACITY {
			SWITCH TO 1.
			PRINT "There is enough room for all files on the local volume.".
			PRINT "Now deleting all files on the local volume.".
			SET fileList TO CORE:VOLUME:FILES.
			FOR f IN fileList:KEYS {IF DELETEPATH(f).}

			COMPILE "0:boot/boot.ks" TO "1:boot.ksm".
			SET CORE:BOOTFILENAME    TO "/boot.ksm".
			PRINT "Boot file name set to " + CORE:BOOTFILENAME.

			PRINT "Now copying all scripts.".
			CD("0:Staging").
			LIST FILES IN fileList.
			FOR f IN fileList {COPYPATH(f:NAME, "1:" + f:NAME).}

			CD("0:").
			LIST FILES IN fileList.
			FOR f IN fileList {IF f:EXTENSION = "settings" COPYPATH(f:NAME, "1:" + f:NAME).}
			DELETEPATH("0:Staging").
			SWITCH TO 1.
			WAIT 0.5.
			RETURN TRUE.
		} ELSE {
			PRINT "Now checking to see if there is enough space for critical files".
			CD("0:Boot"). LIST FILES IN fileList.
			LOCAL usedSpaceCritical IS fileList[0]:SIZE.//PATH("0:boot/boot"):SIZE.	// this covers the boot file.
			CD("0:Staging").
			LIST FILES IN fileList.
			LOCAL criticalFiles IS LIST("library", "loop", "loopCommands", "loopTerminal").
			FOR f IN fileList {
				IF criticalFiles:CONTAINS(f:name)	SET usedSpaceCritical TO usedSpaceCritical + f:SIZE.
			}
			PRINT "Total of " + usedSpaceCritical + " bytes in critical files".
			IF usedSpaceCritical < CORE:VOLUME:CAPACITY {
				SWITCH TO 1.
				PRINT "There is enough room for solely critical files on the local volume.".
				PRINT "Now deleting all files on the local volume.".
				SET fileList TO CORE:VOLUME:FILES.
				FOR f IN fileList:KEYS {IF DELETEPATH(f).}

				COMPILE "0:boot/boot.ks" TO "1:boot.ksm".
				SET CORE:BOOTFILENAME    TO "/boot.ksm".
				PRINT "Boot file name set to " + CORE:BOOTFILENAME.

				PRINT "Now copying all critical scripts.".
				CD("0:Staging").
				FOR f IN criticalFiles {COPYPATH(f, "1:" + f + ".ksm").}

				CD("0:").
				LIST FILES IN fileList.
				FOR f IN fileList {IF f:EXTENSION = "settings" COPYPATH(f:NAME, "1:" + f:NAME).}
				DELETEPATH("0:Staging").
				SWITCH TO 1.
				WAIT 0.5.
				RETURN TRUE.
			} ELSE {
				PRINT "There is not enough space on the local volume".
				PRINT "Local volume not modified".
				DELETEPATH("0:Staging").
				RETURN FALSE.
			}
		}
	}
}

// Wait 1/4 of a second for the universe to fully load.
// If this isn't there, things like HOMECONNECTION:ISCONNECTED aren't right.
WAIT 0.25.

IF KUNIVERSE:TIMEWARP:RATE < 100 CORE:DOEVENT("Open Terminal").
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
		IF copyToLocal(TRUE) {
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
	WAIT 0.5.
	SWITCH TO 1.
	RUNPATH("1:loop").
}
PRINT "Returning control to the terminal".
