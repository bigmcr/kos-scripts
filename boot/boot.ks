@LAZYGLOBAL OFF.

SET CONFIG:IPU TO 2000.
LOCAL stockWorldDetermined IS FALSE.
LOCAL stockRocketsDetermined IS FALSE.
LOCAL lastStockWorld IS FALSE.
LOCAL lastStockRockets IS FALSE.
LOCAL fileList IS LIST().

// The scripts that must be on the local drive for loop to run (without their file extensions).
// The boot file is always required as well. These are also the files that loop loads when it starts, so it is
// global for loop.ks to use: loop refuses to run them again from the terminal.
GLOBAL criticalFileNames IS LIST("library", "libraryTransfer", "loop", "loopCommands", "loopTerminal").

// The name of the JSON file on the local drive that records which scripts were copied there, and how big
// each one's source file on the archive was at that moment. Comparing those sizes to the archive's current
// sizes is how scripts that have changed since the last copy are found.
LOCAL manifestName IS "manifest.json".

// A short message from the boot process that loop shows as its first message.
GLOBAL bootMessage IS "".

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
	IF connectionToKSC() LOG KUNIVERSE:REALTIME +"," + SHIP:NAME + "," + message TO "0:Logfile.txt".
}

// Set Terminal Size
// This function sets the kOS terminal to the preferred size that the loop screens are laid out for.
// Passed the following:
//			no arguments
// Returns the following:
//			nothing
FUNCTION setTerminalSize {
	SET TERMINAL:WIDTH TO 80.
	SET TERMINAL:HEIGHT TO 50.
}

// Base Name
// Passed the following:
//			fileName (string, such as "Exec.ks")
// Returns the following:
//			the file name without its extension (string, such as "Exec")
FUNCTION baseName {
	PARAMETER fileName.
	LOCAL dotIndex IS fileName:FINDLAST(".").
	IF dotIndex = -1 RETURN fileName.
	RETURN fileName:SUBSTRING(0, dotIndex).
}

// Is Critical File
// Passed the following:
//			scriptName (string, without an extension)
// Returns the following:
//			whether or not loop cannot run without this file on the local drive (bool)
FUNCTION isCriticalFile {
	PARAMETER scriptName.
	RETURN (scriptName = "boot") OR criticalFileNames:CONTAINS(scriptName).
}

// Local Manifest Path
// Returns the path of the manifest file on the local drive (string)
FUNCTION localManifestPath {
	RETURN "1:" + manifestName.
}

// Archive Script Sizes
// Passed the following:
//			no arguments
// Returns the following:
//			a lexicon, with an entry for each script on the archive. The key is the script name without an
//			extension, and the value is the size in bytes of the source file. The boot file is included as "boot".
FUNCTION archiveScriptSizes {
	LOCAL sizes IS LEXICON().
	FOR item IN ARCHIVE:FILES:VALUES {
		IF item:ISFILE {
			IF item:EXTENSION = "ks" SET sizes[baseName(item:NAME)] TO item:SIZE.
		}
	}
	IF EXISTS("0:boot/boot.ks") SET sizes["boot"] TO OPEN("0:boot/boot.ks"):SIZE.
	RETURN sizes.
}

// Critical Sizes
// Passed the following:
//			sizes (lexicon in the format of archiveScriptSizes)
// Returns the following:
//			only the entries of sizes that are for critical files (lexicon)
FUNCTION criticalSizes {
	PARAMETER sizes.
	LOCAL criticalOnly IS LEXICON().
	FOR scriptName IN sizes:KEYS {
		IF isCriticalFile(scriptName) SET criticalOnly[scriptName] TO sizes[scriptName].
	}
	RETURN criticalOnly.
}

// Write Manifest
// Records what has been copied to the local drive. The manifest is saved on the local drive.
// Passed the following:
//			sizes (lexicon, script name to source size in bytes, of the scripts now on the local drive)
//			criticalOnly (bool, whether only the critical files could fit on the local drive)
// Returns the following:
//			nothing
FUNCTION writeManifest {
	PARAMETER sizes, criticalOnly.
	LOCAL manifest IS LEXICON(
		"ship", SHIP:NAME,
		"savedRealTime", KUNIVERSE:REALWORLDTIME,
		"criticalOnly", criticalOnly,
		"files", sizes).
	IF EXISTS(localManifestPath()) DELETEPATH(localManifestPath()).
	WRITEJSON(manifest, localManifestPath()).
}

// Compile Best Form
// Compiles a script on the archive into 0:TempFolder, and chooses whichever is smaller, the source or the
// compiled version.
// Passed the following:
//			scriptName (string, without an extension. "boot" is found in the archive's boot folder)
// Returns the following:
//			a lexicon with "path" (where the chosen file is), "name" (the file name to give it when copied)
//			and "size" (its size in bytes)
FUNCTION compileBestForm {
	PARAMETER scriptName.
	LOCAL sourcePath IS "0:" + scriptName + ".ks".
	IF scriptName = "boot" SET sourcePath TO "0:boot/boot.ks".
	LOCAL compiledPath IS "0:TempFolder/" + scriptName + ".ksm".
	COMPILE sourcePath TO compiledPath.
	LOCAL ksFile IS OPEN(sourcePath).
	LOCAL ksmFile IS OPEN(compiledPath).
	// the boot file is always the compiled version
	IF scriptName = "boot" OR ksmFile:SIZE < ksFile:SIZE {
		RETURN LEXICON("path", compiledPath, "name", scriptName + ".ksm", "size", ksmFile:SIZE).
	}
	RETURN LEXICON("path", sourcePath, "name", scriptName + ".ks", "size", ksFile:SIZE).
}

// copy the passed script to the given destination
// compiles the script and copies over the ks or KSM version, whichever is smaller.
FUNCTION copyScript {
	PARAMETER scriptName.
	PARAMETER destination IS "0:Staging/".

	IF NOT connectionToKSC() RETURN FALSE.

	LOCAL best IS compileBestForm(baseName(scriptName)).
	COPYPATH(best["path"], destination + best["name"]).
	RETURN TRUE.
}

// Install Script
// Puts the current version of one script from the archive onto the local drive, replacing any old version.
// Both the .ks and .ksm versions of the old file are removed, because an old .ksm left behind would be run
// instead of a new .ks.
// Passed the following:
//			scriptName (string, without an extension)
// Returns the following:
//			whether or not the script was installed. It is not if there is not enough room for it (bool)
FUNCTION installScript {
	PARAMETER scriptName.
	LOCAL best IS compileBestForm(scriptName).
	LOCAL oldSize IS 0.
	FOR extension IN LIST(".ks", ".ksm") {
		IF EXISTS("1:" + scriptName + extension) SET oldSize TO oldSize + OPEN("1:" + scriptName + extension):SIZE.
	}
	IF best["size"] > CORE:VOLUME:FREESPACE + oldSize RETURN FALSE.
	FOR extension IN LIST(".ks", ".ksm") {
		IF EXISTS("1:" + scriptName + extension) DELETEPATH("1:" + scriptName + extension).
	}
	COPYPATH(best["path"], "1:" + best["name"]).
	RETURN TRUE.
}

// Compare With Archive
// Compares the scripts on the archive to the record of what was copied to the local drive.
// Passed the following:
//			no arguments
// Returns the following:
//			a lexicon with
//			"connected" (bool), "hasManifest" (bool), "criticalOnly" (bool, the local drive holds only critical files),
//			"changed" (list of script names whose size on the archive is different),
//			"new" (list of script names on the archive that were never copied),
//			"removed" (list of script names that were copied, but are no longer on the archive),
//			"archiveSizes" (lexicon from archiveScriptSizes)
FUNCTION compareWithArchive {
	LOCAL result IS LEXICON("connected", connectionToKSC(), "hasManifest", FALSE, "criticalOnly", FALSE,
		"changed", LIST(), "new", LIST(), "removed", LIST(), "archiveSizes", LEXICON()).
	IF NOT result["connected"] RETURN result.
	IF NOT EXISTS(localManifestPath()) RETURN result.

	LOCAL manifest IS READJSON(localManifestPath()).
	LOCAL localSizes IS manifest["files"].
	LOCAL archiveSizes IS archiveScriptSizes().
	SET result["hasManifest"] TO TRUE.
	SET result["criticalOnly"] TO manifest["criticalOnly"].
	SET result["archiveSizes"] TO archiveSizes.

	FOR scriptName IN archiveSizes:KEYS {
		// when only the critical files fit on the local drive, the other scripts are not expected to be there
		IF (NOT manifest["criticalOnly"]) OR isCriticalFile(scriptName) {
			IF NOT localSizes:HASKEY(scriptName) result["new"]:ADD(scriptName).
			ELSE IF localSizes[scriptName] <> archiveSizes[scriptName] result["changed"]:ADD(scriptName).
		}
	}
	FOR scriptName IN localSizes:KEYS {
		IF NOT archiveSizes:HASKEY(scriptName) result["removed"]:ADD(scriptName).
	}
	RETURN result.
}

// Report Archive Differences
// Called at boot. Prints how the local scripts compare to the archive, and leaves a short message for loop.
// Passed the following:
//			no arguments
// Returns the following:
//			nothing
FUNCTION reportArchiveDifferences {
	LOCAL comparison IS compareWithArchive().
	IF NOT comparison["connected"] {
		PRINT "No connection to the archive, so script versions were not checked.".
		RETURN.
	}
	IF NOT comparison["hasManifest"] {
		PRINT "There is no manifest of the local scripts. Use local,T to create one.".
		SET bootMessage TO "No script manifest: use local,T".
		WAIT 2.
		RETURN.
	}
	LOCAL total IS comparison["changed"]:LENGTH + comparison["new"]:LENGTH + comparison["removed"]:LENGTH.
	IF total = 0 {
		PRINT "Local scripts match the archive.".
		RETURN.
	}
	PRINT total + " script(s) differ from the archive:".
	FOR scriptName IN comparison["changed"] { PRINT "   changed  " + scriptName. }
	FOR scriptName IN comparison["new"] { PRINT "   new      " + scriptName. }
	FOR scriptName IN comparison["removed"] { PRINT "   removed  " + scriptName. }
	PRINT "Use the update command to apply these changes.".
	SET bootMessage TO total + " scripts differ: use update".
	WAIT 3.
}

// Update From Archive
// Brings the local scripts up to date with the archive: copies scripts that changed or are new, and
// deletes the local copies of scripts that were removed from the archive. Only files recorded in the manifest
// are ever deleted, so files created by other scripts (logs and so on) are left alone.
// Passed the following:
//			no arguments
// Returns the following:
//			a short message describing the result (string)
FUNCTION updateFromArchive {
	LOCAL comparison IS compareWithArchive().
	IF NOT comparison["connected"] RETURN "No connection to the archive".
	IF NOT comparison["hasManifest"] RETURN "No script manifest: use local,T".

	LOCAL manifest IS READJSON(localManifestPath()).
	LOCAL sizes IS manifest["files"].
	LOCAL archiveSizes IS comparison["archiveSizes"].
	LOCAL updatedCount IS 0.
	LOCAL newCount IS 0.
	LOCAL removedCount IS 0.
	LOCAL failedCount IS 0.

	FOR scriptName IN comparison["changed"] {
		IF installScript(scriptName) {
			SET sizes[scriptName] TO archiveSizes[scriptName].
			SET updatedCount TO updatedCount + 1.
		} ELSE SET failedCount TO failedCount + 1.
	}
	FOR scriptName IN comparison["new"] {
		IF installScript(scriptName) {
			SET sizes[scriptName] TO archiveSizes[scriptName].
			SET newCount TO newCount + 1.
		} ELSE SET failedCount TO failedCount + 1.
	}
	FOR scriptName IN comparison["removed"] {
		FOR extension IN LIST(".ks", ".ksm") {
			IF EXISTS("1:" + scriptName + extension) DELETEPATH("1:" + scriptName + extension).
		}
		sizes:REMOVE(scriptName).
		SET removedCount TO removedCount + 1.
	}
	IF EXISTS("0:TempFolder") DELETEPATH("0:TempFolder").
	IF updatedCount + newCount + removedCount > 0 writeManifest(sizes, manifest["criticalOnly"]).

	LOCAL parts IS LIST().
	IF updatedCount > 0 parts:ADD(updatedCount + " updated").
	IF newCount > 0 parts:ADD(newCount + " new").
	IF removedCount > 0 parts:ADD(removedCount + " removed").
	IF failedCount > 0 parts:ADD(failedCount + " no room").
	IF parts:LENGTH = 0 RETURN "Local scripts already match archive".
	LOCAL message IS "".
	FOR part IN parts {
		IF message <> "" SET message TO message + ", ".
		SET message TO message + part.
	}
	IF updatedCount + newCount + removedCount > 0 RETURN message + ". Reboot to apply".
	RETURN message.
}

// Copy To Local
// Replaces everything on the local drive with the current scripts from the archive. If they will not all fit,
// only the critical files are copied. A manifest of what was copied is saved, so that later changes to the
// archive can be found with updateFromArchive.
// Passed the following:
//			no arguments
// Returns the following:
//			the number of files copied (scalar)
FUNCTION copyToLocal {
	IF NOT connectionToKSC() RETURN 0.

	LOCAL filesCopied IS 0.

	CLEARSCREEN.
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
	IF EXISTS("0:TempFolder") DELETEPATH("0:TempFolder").
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
		FOR f IN fileList:KEYS {DELETEPATH(f).}

		COMPILE "0:boot/boot.ks" TO "1:boot.ksm".
		SET CORE:BOOTFILENAME    TO "/boot.ksm".
		PRINT "Boot file name set to " + CORE:BOOTFILENAME.

		PRINT "Now copying all scripts.".
		CD("0:Staging").
		LIST FILES IN fileList.
		FOR f IN fileList {COPYPATH(f:NAME, "1:" + f:NAME). SET filesCopied TO filesCopied + 1.}

		CD("0:").
		LIST FILES IN fileList.
		FOR f IN fileList {IF f:EXTENSION = "settings" COPYPATH(f:NAME, "1:" + f:NAME).}
		DELETEPATH("0:Staging").
		writeManifest(archiveScriptSizes(), FALSE).
	} ELSE {
		PRINT "Now checking to see if there is enough space for critical files".
		CD("0:boot").
		LIST FILES IN fileList.
		LOCAL usedSpaceCritical IS fileList[0]:SIZE. // this covers the boot file.
		CD("0:Staging").
		LIST FILES IN fileList.
		FOR f IN fileList {
			IF criticalFileNames:CONTAINS(baseName(f:NAME))	SET usedSpaceCritical TO usedSpaceCritical + f:SIZE.
		}
		PRINT "Total of " + usedSpaceCritical + " bytes in critical files".
		IF usedSpaceCritical < CORE:VOLUME:CAPACITY {
			SWITCH TO 1.
			PRINT "There is enough room for solely critical files on the local volume.".
			PRINT "Now deleting all files on the local volume.".
			SET fileList TO CORE:VOLUME:FILES.
			FOR f IN fileList:KEYS {DELETEPATH(f).}

			COMPILE "0:boot/boot.ks" TO "1:boot.ksm".
			SET CORE:BOOTFILENAME    TO "/boot.ksm".
			PRINT "Boot file name set to " + CORE:BOOTFILENAME.

			PRINT "Now copying all critical scripts.".
			CD("0:Staging").
			LIST FILES IN fileList.
			FOR f IN fileList {
				IF criticalFileNames:CONTAINS(baseName(f:NAME)) {COPYPATH(f:NAME, "1:" + f:NAME). SET filesCopied TO filesCopied + 1.}
			}

			CD("0:").
			LIST FILES IN fileList.
			FOR f IN fileList {IF f:EXTENSION = "settings" COPYPATH(f:NAME, "1:" + f:NAME).}
			DELETEPATH("0:Staging").
			writeManifest(criticalSizes(archiveScriptSizes()), TRUE).
		} ELSE {
			PRINT "There is not enough space on the local volume".
			PRINT "Local volume not modified".
			CD("0:").
			DELETEPATH("0:Staging").
		}
	}
	// always finish on the local volume, so that scripts are found and run from there.
	SWITCH TO 1.
	RETURN filesCopied.
}

// Wait 1/4 of a second for the universe to fully load.
// If this isn't there, things like HOMECONNECTION:ISCONNECTED aren't right.
WAIT 0.25.

IF KUNIVERSE:TIMEWARP:RATE < 100 CORE:DOEVENT("Open Terminal").
SET TERMINAL:BRIGHTNESS TO 1.
setTerminalSize().

LOCAL loopFound TO FALSE.

isStockWorld().
isStockRockets().

// default to running on the local drive, if all the files are loaded already
IF EXISTS("1:loop") AND EXISTS("1:loopCommands") AND EXISTS("1:loopTerminal") AND EXISTS("1:library") AND EXISTS("1:libraryTransfer") {
	SET loopFound TO TRUE.
	PRINT "Found local loop with valid settings".
	reportArchiveDifferences().
}
ELSE {
	// if loop does not exist on the local drive, check to see if we can copy it from the archive
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
	WAIT 0.5.
	SWITCH TO 1.
	RUNPATH("1:loop").
}
PRINT "Returning control to the terminal".
