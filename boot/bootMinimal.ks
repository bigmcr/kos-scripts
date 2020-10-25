@LAZYGLOBAL OFF.

// Bootminimal is intended to run only the loop program locally.
// All other scripts are intended to run from the archive.

LOCAL stockWorldDetermined IS FALSE.
LOCAL stockRocketsDetermined IS FALSE.
LOCAL lastStockWorld IS FALSE.
LOCAL lastStockRockets IS FALSE.

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
	IF connectionToKSC {
		IF scriptName:ENDSWITH(".ks") SET scriptName TO scriptName:SUBSTRING(0, scriptName:LENGTH - 3).
		IF EXISTS("0:KSM Files/" + scriptName + ".ksm") DELETEPATH("0:KSM Files/" + scriptName + ".ksm").
		IF EXISTS("0:" + scriptName + ".ksm") DELETEPATH("0:" + scriptName + ".ksm").
		COMPILE "0:" + scriptName TO "1:" + scriptName + ".ksm".
	}
}

FUNCTION copyToLocal {
	IF NOT connectionToKSC() RETURN FALSE.
	CLEARSCREEN.

	compileScript("loopMinimal.ks").
	compileScript("library.ks").
	COMPILE "0:boot/bootMinimal.ks" TO "1:bootMinimal.ksm".
	SET CORE:BOOTFILENAME    TO "/bootMinimal.ksm".
	PRINT "Boot file name set to " + CORE:BOOTFILENAME.
	PRINT "Updated bootMinimal, loopMinimal, and library".
	PRINT "All other scripts are not stored locally".
	RETURN TRUE.
}

WAIT 0.25.

IF KUNIVERSE:TIMEWARP:RATE < 100 core:part:getmodule("kOSProcessor"):doevent("Open Terminal").
SET TERMINAL:BRIGHTNESS TO 1.
SET TERMINAL:WIDTH TO 40.
SET TERMINAL:HEIGHT TO 20.

LOCAL loopFound TO FALSE.

isStockWorld().
isStockRockets().

// default to running on the local drive, if all the files are loaded already
IF EXISTS("1:/loopMinimal.ksm") AND EXISTS("1:/library.ksm")  {
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
		PRINT "loopMinimal.ksm does not exist on the local drive".
		PRINT "Or there are not valid settings".
		PRINT "There is no connection to the archive".
		PRINT "Not running anything in particular".
	}
}

IF loopFound {
	PRINT "Running local loopMinimal.ksm".
	WAIT 1.
	SWITCH TO 1.
	RUNPATH("1:loopMinimal").
}
PRINT "Returning control to the terminal".
