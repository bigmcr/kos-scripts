@LAZYGLOBAL OFF.

SET CONFIG:IPU TO 2000.
LOCAL stockWorldDetermined IS FALSE.
LOCAL stockRocketsDetermined IS FALSE.
LOCAL lastStockWorld IS FALSE.
LOCAL lastStockRockets IS FALSE.

// The scripts that must be on the local drive for loop to run (without their file extensions).
// The boot file is always required as well. These are also the files that loop loads when it starts, so it is
// global for loop.ks to use: loop refuses to run them again from the terminal.
GLOBAL criticalFileNames IS LIST("library", "libraryTransfer", "loop", "loopCommands", "loopTerminal").

// How scripts get from the archive to a ship
// -------------------------------------------
// The scripts on the archive are compiled once, by the build command (buildArchive below), into the folder
// 0:Compiled. That folder also holds build.json, which lists every script with a fingerprint of its source and the file
// to copy. Ships never compile or hash the sources themselves. They compare build.json to their own manifest.txt,
// which lists what was copied to the local drive and the fingerprint that each copy was made from.
// boot.ks does this when it starts, and the update command does it later (syncScripts).

// The JSON file on the local drive that records which scripts were copied there.
LOCAL manifestPath IS "1:manifest.txt".
LOCAL oldManifestPath IS "1:manifest.json".		// the format before version 3
LOCAL manifestVersion IS 3.

// The version of kOS that is running, such as "1.4.0.0". Compiled files are built again when it changes.
// Global, so that loopTerminal can show it.
GLOBAL kosVersionText IS CORE:VERSION:MAJOR + "." + CORE:VERSION:MINOR + "." + CORE:VERSION:PATCH + "." + CORE:VERSION:BUILD.

// The archive's compiled folder, and the build record in it. A lock file stops two ships building at once.
LOCAL buildFolder IS "0:Compiled".
LOCAL buildFilePath IS "0:Compiled/build.json".
LOCAL buildLockPath IS "0:Compiled/build.lock".
LOCAL buildVersion IS 1.

// The marker of an update that did not finish.
LOCAL journalPath IS "1:update.journal".
// Left by the reinstall command: the next boot deletes the local scripts and installs them again from the archive.
GLOBAL reinstallFlagPath IS "1:reinstall.flag".

// A short message from the boot process that loop shows as its first message.
GLOBAL bootMessage IS "".

// The manifest, once it has been read or written (FALSE until then), so that the file is not read again and again.
GLOBAL manifestCache IS FALSE.

// The fingerprint of each script that has been loaded into memory since the last reboot. A script that is already
// loaded is not read again, so if the local copy changes after that, a reboot is needed to use the change.
GLOBAL loadedVersions IS LEXICON().

// The names of the scripts that were updated after they were loaded. Cleared by a reboot.
GLOBAL rebootPending IS LIST().

// Is Stock Universe
// This function returns TRUE if the ship is operating in the stock KSP universe.
// This is determined by seeing if a body is called "Kerbin" or "Minmus".
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
//			whether or not there is a connection to the archive back on Kerbin/Earth.
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
//			fileName (string, such as "Exec.ks", "0:Exec.ks" or "1:/exec", with or without a volume, folder and extension)
// Returns the following:
//			the name without its volume, folder or extension (string, such as "Exec")
FUNCTION baseName {
	PARAMETER fileName.
	LOCAL result IS fileName.
	LOCAL separator IS result:FINDLAST(":").
	IF separator <> -1 SET result TO result:SUBSTRING(separator + 1, result:LENGTH - separator - 1).
	SET separator TO result:FINDLAST("/").
	IF separator <> -1 SET result TO result:SUBSTRING(separator + 1, result:LENGTH - separator - 1).
	LOCAL dotIndex IS result:FINDLAST(".").
	IF dotIndex = -1 RETURN result.
	RETURN result:SUBSTRING(0, dotIndex).
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

// Read JSON Guarded
// Reading a damaged JSON file would end this program every time it starts, so a marker file is made before the file
// is read and removed after. If the marker is found, the last read did not finish, and the file is deleted.
// Passed the following:
//			jsonPath (string), markerPath (string, on the local drive)
// Returns the following:
//			what the file holds, or FALSE if there is no file, or if it was found to be damaged
FUNCTION readJsonGuarded {
	PARAMETER jsonPath, markerPath.
	IF EXISTS(markerPath) {
		IF EXISTS(jsonPath) DELETEPATH(jsonPath).
		DELETEPATH(markerPath).
		RETURN FALSE.
	}
	IF NOT EXISTS(jsonPath) RETURN FALSE.
	LOG "reading" TO markerPath.
	LOCAL parsed IS READJSON(jsonPath).
	DELETEPATH(markerPath).
	RETURN parsed.
}

// The manifest is a plain text file, so that its exact size is known before it is written: a write that does not fit
// ends the program, and a guess at the size of a JSON file had to be generous, which made the write be skipped on
// a drive that was nearly full. Line 1 is the format version, line 2 is the version of kOS that compiled the scripts,
// and each line after that is a script name, a tab, and its fingerprint.

// Read Manifest
// Returns the manifest (lexicon with "version", "kos" and "files"), or FALSE if there is none, if it is damaged, or if
// it is an older version.
FUNCTION readManifest {
	IF NOT manifestCache:ISTYPE("Boolean") RETURN manifestCache.
	IF NOT EXISTS(manifestPath) RETURN FALSE.
	LOCAL lines IS OPEN(manifestPath):READALL:STRING:SPLIT(CHAR(10)).
	IF lines:LENGTH < 2 RETURN FALSE.
	IF lines[0]:TRIM:TONUMBER(-1) <> manifestVersion RETURN FALSE.
	LOCAL files IS LEXICON().
	FROM {LOCAL index IS 2.} UNTIL index >= lines:LENGTH STEP {SET index TO index + 1.} DO {
		LOCAL parts IS lines[index]:TRIM:SPLIT(CHAR(9)).
		IF parts:LENGTH = 3 {
			// the fingerprint is kept as two whole numbers, so that no digits are lost in writing it as text
			LOCAL highPart IS parts[1]:TRIM:TONUMBER(-1).
			LOCAL lowPart IS parts[2]:TRIM:TONUMBER(-1).
			IF highPart < 0 OR lowPart < 0 RETURN FALSE.
			SET files[parts[0]] TO highPart * 1e9 + lowPart.
		}
	}
	LOCAL manifest IS LEXICON("version", manifestVersion, "kos", lines[1]:TRIM, "files", files).
	SET manifestCache TO manifest.
	RETURN manifest.
}

// Write Manifest
// Records what has been copied to the local drive. The manifest is saved on the local drive.
// Passed the following:
//			files (lexicon, script name to the fingerprint of the source it was made from)
//			buildKos (string, the version of kOS that compiled the scripts)
// Returns the following:
//			whether or not the manifest was saved (bool). It is not if there is no room for it.
FUNCTION writeManifest {
	PARAMETER files, buildKos.
	LOCAL text IS manifestVersion + CHAR(10) + buildKos.
	FOR eachName IN files:KEYS {
		LOCAL highPart IS FLOOR(files[eachName] / 1e9).
		SET text TO text + CHAR(10) + eachName + CHAR(9) + highPart + CHAR(9) + ROUND(files[eachName] - highPart * 1e9).
	}
	IF EXISTS(manifestPath) DELETEPATH(manifestPath).
	// the manifest from before version 3 is not used again
	IF EXISTS(oldManifestPath) DELETEPATH(oldManifestPath).
	// LOG adds a line ending, which may be two characters, so there is a little extra in the size that is needed
	IF text:LENGTH + 4 >= CORE:VOLUME:FREESPACE {
		SET manifestCache TO FALSE.
		RETURN FALSE.
	}
	LOG text TO manifestPath.
	SET manifestCache TO LEXICON("version", manifestVersion, "kos", buildKos, "files", files).
	RETURN TRUE.
}
// The characters whose counts make up a script's fingerprint (see fileFingerprint). The double quote, tab,
// line feed and carriage return are added in fileFingerprint, because they cannot be typed in this string.
LOCAL fingerprintCharacters IS "0123456789abcdefghijklmnopqrstuvwxyz <>=+-*/()[]{},.:_@'#%&|!?;\".

// File Fingerprint
// A number that changes when the source of a script changes, even if its length does not (swapping "<" for ">",
// or one digit for another). The number of times each character in fingerprintCharacters appears is counted
// with SPLIT, which kOS does natively without looping over the text, and the counts are combined into a number
// below 1e9 with a rolling hash. That is stored together with the size in bytes in one number, size * 1e9 + hash,
// which is at most 15 digits, so a double holds it exactly.
// It does not detect an edit that only moves characters around without adding or removing any, such as swapping
// two letters. This is slow for a large script, so only buildArchive does it.
// Passed the following:
//			text (string, the source of the script)
//			size (scalar, the size of the source file in bytes)
// Returns the following:
//			the fingerprint (scalar)
FUNCTION fileFingerprint {
	PARAMETER text, size.
	LOCAL hashModulus IS 999999937.
	LOCAL hash IS 0.
	LOCAL characterList IS LIST(CHAR(34), CHAR(9), CHAR(10), CHAR(13)).
	FROM {LOCAL index IS 0.} UNTIL index >= fingerprintCharacters:LENGTH STEP {SET index TO index + 1.} DO {
		characterList:ADD(fingerprintCharacters:SUBSTRING(index, 1)).
	}
	FOR eachCharacter IN characterList {
		SET hash TO MOD(hash * 1000003.0 + (text:SPLIT(eachCharacter):LENGTH - 1), hashModulus).
	}
	RETURN size * 1e9 + hash.
}

// ---- Building the archive's compiled scripts -------------------------------------------------------------

// Archive Items
// Returns the files on the archive that go to ships (lexicon). The key is the script name without an extension
// ("boot" for 0:boot/boot.ks), or the whole file name for a .settings file. Each value is a lexicon with
//			"kind" ("script" or "plain"), "source" (its path on the archive), and "sourceSize" (bytes).
FUNCTION archiveItems {
	LOCAL items IS LEXICON().
	FOR item IN ARCHIVE:FILES:VALUES {
		IF item:ISFILE {
			IF item:EXTENSION = "ks" {
				SET items[baseName(item:NAME)] TO LEXICON("kind", "script", "source", "0:" + item:NAME, "sourceSize", item:SIZE).
			} ELSE IF item:EXTENSION = "settings" {
				SET items[item:NAME] TO LEXICON("kind", "plain", "source", "0:" + item:NAME, "sourceSize", item:SIZE).
			}
		}
	}
	IF EXISTS("0:boot/boot.ks") {
		SET items["boot"] TO LEXICON("kind", "script", "source", "0:boot/boot.ks", "sourceSize", OPEN("0:boot/boot.ks"):SIZE).
	}
	RETURN items.
}

// Read Build
// Returns the archive's build record (lexicon), or FALSE if there is none, if it is damaged, or if it is an older
// version. The archive must be connected.
FUNCTION readBuild {
	LOCAL build IS readJsonGuarded(buildFilePath, "1:build.loading").
	IF NOT build:ISTYPE("Lexicon") RETURN FALSE.
	IF NOT (build:HASKEY("version") AND build:HASKEY("kos") AND build:HASKEY("files")) RETURN FALSE.
	IF build["version"] <> buildVersion RETURN FALSE.
	RETURN build.
}

// Compile Entry
// Compiles one script into the archive's compiled folder, and chooses whichever is smaller, the source or the
// compiled version. The boot file is always the compiled version.
// Passed the following:
//			scriptName (string), item (lexicon from archiveItems), fingerprint (scalar)
// Returns the following:
//			the build record's entry for the script (lexicon)
FUNCTION compileEntry {
	PARAMETER scriptName, item, fingerprint.
	LOCAL compiledPath IS buildFolder + "/" + scriptName + ".ksm".
	IF EXISTS(compiledPath) DELETEPATH(compiledPath).
	COMPILE item["source"] TO compiledPath.
	LOCAL compiledSize IS OPEN(compiledPath):SIZE.
	IF scriptName = "boot" OR compiledSize < item["sourceSize"] {
		RETURN LEXICON("kind", "script", "fingerprint", fingerprint, "sourceSize", item["sourceSize"],
			"form", "ksm", "path", compiledPath, "name", scriptName + ".ksm", "size", compiledSize).
	}
	DELETEPATH(compiledPath).
	RETURN LEXICON("kind", "script", "fingerprint", fingerprint, "sourceSize", item["sourceSize"],
		"form", "ks", "path", item["source"], "name", scriptName + ".ks", "size", item["sourceSize"]).
}

// Build Archive
// Compiles the scripts on the archive that have changed since the last build into 0:Compiled, and writes
// build.json. If the version of kOS has changed since the last build, every script is compiled again. Compiling
// pauses the program for a while, and a script with an error in it ends the program, so run this from a ship
// that is not doing anything important.
// Passed the following:
//			forceAll (bool, compile every script again), ignoreLock (bool, build even if another ship's build lock is
//			less than 5 minutes old; default FALSE)
// Returns the following:
//			a short message describing the result (string)
FUNCTION buildArchive {
	PARAMETER forceAll, ignoreLock IS FALSE.
	IF NOT connectionToKSC() RETURN "No connection to the archive".
	IF NOT EXISTS(buildFolder) CREATEDIR(buildFolder).
	IF EXISTS(buildLockPath) {
		LOCAL lockTime IS OPEN(buildLockPath):READALL:STRING:TRIM:TONUMBER(0).
		IF (NOT ignoreLock) AND KUNIVERSE:REALWORLDTIME - lockTime < 300 RETURN "Another ship is building".
		DELETEPATH(buildLockPath).
	}
	LOG KUNIVERSE:REALWORLDTIME TO buildLockPath.

	LOCAL currentKos IS kosVersionText.
	LOCAL items IS archiveItems().
	LOCAL oldBuild IS readBuild().
	LOCAL oldFiles IS LEXICON().
	// compiled files from another version of kOS are not used again, so everything is compiled again
	IF NOT oldBuild:ISTYPE("Boolean") {
		IF oldBuild["kos"] = currentKos SET oldFiles TO oldBuild["files"].
	}

	LOCAL newFiles IS LEXICON().
	LOCAL compiledCount IS 0.
	LOCAL keptCount IS 0.
	FOR eachName IN items:KEYS {
		LOCAL item IS items[eachName].
		LOCAL entry IS FALSE.
		IF item["kind"] = "plain" {
			SET entry TO LEXICON("kind", "plain", "fingerprint", item["sourceSize"], "sourceSize", item["sourceSize"],
				"form", "plain", "path", item["source"], "name", eachName, "size", item["sourceSize"]).
			SET keptCount TO keptCount + 1.
		} ELSE {
			LOCAL fingerprint IS fileFingerprint(OPEN(item["source"]):READALL:STRING, item["sourceSize"]).
			IF (NOT forceAll) AND oldFiles:HASKEY(eachName) {
				LOCAL oldEntry IS oldFiles[eachName].
				IF oldEntry["fingerprint"] = fingerprint {
					IF oldEntry["form"] = "ks" OR EXISTS(oldEntry["path"]) SET entry TO oldEntry.
				}
			}
			IF entry:ISTYPE("Boolean") {
				SET entry TO compileEntry(eachName, item, fingerprint).
				SET compiledCount TO compiledCount + 1.
			} ELSE SET keptCount TO keptCount + 1.
		}
		SET newFiles[eachName] TO entry.
	}

	// compiled files of scripts that are no longer on the archive
	LOCAL removedCount IS 0.
	FOR eachName IN oldFiles:KEYS {
		IF NOT newFiles:HASKEY(eachName) {
			IF oldFiles[eachName]["form"] = "ksm" {
				IF EXISTS(oldFiles[eachName]["path"]) DELETEPATH(oldFiles[eachName]["path"]).
			}
			SET removedCount TO removedCount + 1.
		}
	}

	IF EXISTS(buildFilePath) DELETEPATH(buildFilePath).
	WRITEJSON(LEXICON("version", buildVersion, "kos", currentKos, "builtRealTime", KUNIVERSE:REALWORLDTIME, "files", newFiles), buildFilePath).
	DELETEPATH(buildLockPath).
	RETURN "Built " + compiledCount + ", kept " + keptCount + ", removed " + removedCount.
}

// Build Stale Reason
// Compares the archive's source files to the build record, by size and by name. This is quick, but it does not
// notice an edit that does not change the size of a file. Run the build command after editing in that case.
// Passed the following:
//			build (lexicon, the build record)
// Returns the following:
//			why the build is out of date (string), or "" if it is not
FUNCTION buildStaleReason {
	PARAMETER build.
	IF build["kos"] <> kosVersionText RETURN "kOS version changed".
	LOCAL items IS archiveItems().
	LOCAL differences IS 0.
	FOR eachName IN items:KEYS {
		IF NOT build["files"]:HASKEY(eachName) {
			SET differences TO differences + 1.
		} ELSE IF build["files"][eachName]["sourceSize"] <> items[eachName]["sourceSize"] {
			SET differences TO differences + 1.
		}
	}
	FOR eachName IN build["files"]:KEYS {
		IF NOT items:HASKEY(eachName) SET differences TO differences + 1.
	}
	IF differences > 0 RETURN differences + " source files differ".
	RETURN "".
}

// ---- Putting the compiled scripts on the local drive -----------------------------------------------------

// Installed Files
// Passed the following:
//			scriptName (string, a key of the manifest)
// Returns the following:
//			the paths of the files on the local drive that hold the script (list). That may be a .ks, a .ksm, or
//			both, and is empty if there are none. Both are looked for, because an old .ksm left behind would be run
//			instead of a new .ks. Only a .settings file has a dot in its name.
FUNCTION installedFiles {
	PARAMETER scriptName.
	LOCAL candidates IS LIST(scriptName + ".ks", scriptName + ".ksm").
	IF scriptName:FIND(".") <> -1 SET candidates TO LIST(scriptName).
	LOCAL found IS LIST().
	FOR eachFile IN candidates {
		IF EXISTS("1:" + eachFile) found:ADD("1:" + eachFile).
	}
	RETURN found.
}

// Install Script
// Puts one script from the archive's build onto the local drive, replacing any old version. If there is room, the new
// file is copied next to the old one first, so that an interruption leaves a complete file, and then swapped in.
// Passed the following:
//			scriptName (string), entry (lexicon, the build record's entry for it)
// Returns the following:
//			whether or not the script was installed. It is not if there is not enough room for it (bool)
FUNCTION installScript {
	PARAMETER scriptName, entry.
	LOCAL oldFiles IS installedFiles(scriptName).
	LOCAL oldSize IS 0.
	FOR eachFile IN oldFiles {
		SET oldSize TO oldSize + OPEN(eachFile):SIZE.
	}
	IF entry["size"] > CORE:VOLUME:FREESPACE + oldSize RETURN FALSE.
	LOCAL finalPath IS "1:" + entry["name"].
	IF entry["size"] <= CORE:VOLUME:FREESPACE {
		LOCAL temporaryPath IS finalPath + ".new".
		IF EXISTS(temporaryPath) DELETEPATH(temporaryPath).
		COPYPATH(entry["path"], temporaryPath).
		FOR eachFile IN oldFiles {
			DELETEPATH(eachFile).
		}
		MOVEPATH(temporaryPath, finalPath).
	} ELSE {
		FOR eachFile IN oldFiles {
			DELETEPATH(eachFile).
		}
		COPYPATH(entry["path"], finalPath).
	}
	RETURN TRUE.
}

// Install Order
// Passed the following:
//			names (list of script names), buildFiles (lexicon, the build record's files)
// Returns the following:
//			the names in the order to install them: boot, the critical files, and then the others, smallest first so
//			that the most of them fit if there is not room for all (list)
FUNCTION installOrder {
	PARAMETER names, buildFiles.
	LOCAL ordered IS LIST().
	IF names:CONTAINS("boot") ordered:ADD("boot").
	FOR eachName IN criticalFileNames {
		IF names:CONTAINS(eachName) ordered:ADD(eachName).
	}
	LOCAL others IS LIST().
	FOR eachName IN names {
		IF NOT isCriticalFile(eachName) {
			LOCAL insertAt IS others:LENGTH.
			FROM {LOCAL index IS 0.} UNTIL index >= others:LENGTH STEP {SET index TO index + 1.} DO {
				IF buildFiles[eachName]["size"] < buildFiles[others[index]]["size"] {
					SET insertAt TO index.
					BREAK.
				}
			}
			others:INSERT(insertAt, eachName).
		}
	}
	FOR eachName IN others {
		ordered:ADD(eachName).
	}
	RETURN ordered.
}

// Critical Shortage
// The critical files must be replaced together or not at all, because they work with each other, so this checks
// that all of the new ones fit before any of them is touched.
// Passed the following:
//			names (list of script names that are about to be installed), buildFiles (lexicon)
// Returns the following:
//			the number of bytes that would be missing (scalar), or 0 if they fit
FUNCTION criticalShortage {
	PARAMETER names, buildFiles.
	LOCAL needed IS 0.
	LOCAL freed IS 0.
	FOR eachName IN names {
		IF isCriticalFile(eachName) {
			SET needed TO needed + buildFiles[eachName]["size"].
			FOR eachFile IN installedFiles(eachName) {
				SET freed TO freed + OPEN(eachFile):SIZE.
			}
		}
	}
	// The manifest is written again afterward. The old one is deleted first, and its room is used again, so only the
	// entries that are new need more room (about 120 bytes each), plus a little for the journal file.
	LOCAL manifest IS readManifest().
	LOCAL newEntries IS names:LENGTH.
	IF manifest:ISTYPE("Lexicon") {
		SET newEntries TO 0.
		FOR eachName IN names {
			IF NOT manifest["files"]:HASKEY(eachName) SET newEntries TO newEntries + 1.
		}
	}
	LOCAL reserve IS 300 + 120 * newEntries.
	RETURN MAX(0, needed - freed + reserve - CORE:VOLUME:FREESPACE).
}

// Compare With Archive
// Compares the archive's build to the record of what was copied to the local drive.
// Passed the following:
//			no arguments
// Returns the following:
//			a lexicon with
//			"connected" (bool), "hasBuild" (bool), "hasManifest" (bool),
//			"buildStale" (string, why the build is out of date, or "" if it is not),
//			"changed" (list of script names whose fingerprint in the build is different),
//			"new" (list of script names in the build that were never copied),
//			"removed" (list of script names that were copied, but are no longer in the build),
//			"build" and "manifest" (lexicons, if they could be read)
FUNCTION compareWithArchive {
	LOCAL result IS LEXICON("connected", connectionToKSC(), "hasBuild", FALSE, "hasManifest", FALSE, "buildStale", "",
		"changed", LIST(), "new", LIST(), "removed", LIST(), "build", LEXICON(), "manifest", LEXICON()).
	IF NOT result["connected"] RETURN result.
	LOCAL build IS readBuild().
	LOCAL manifest IS readManifest().
	IF build:ISTYPE("Lexicon") {
		SET result["hasBuild"] TO TRUE.
		SET result["build"] TO build.
		SET result["buildStale"] TO buildStaleReason(build).
	}
	IF manifest:ISTYPE("Lexicon") {
		SET result["hasManifest"] TO TRUE.
		SET result["manifest"] TO manifest.
	}
	IF NOT (result["hasBuild"] AND result["hasManifest"]) RETURN result.

	LOCAL buildFiles IS build["files"].
	LOCAL localFiles IS manifest["files"].
	// the scripts that were compiled by another version of kOS are replaced
	LOCAL kosChanged IS manifest["kos"] <> build["kos"].
	FOR eachName IN buildFiles:KEYS {
		IF NOT localFiles:HASKEY(eachName) {
			result["new"]:ADD(eachName).
		} ELSE IF localFiles[eachName] <> buildFiles[eachName]["fingerprint"] {
			result["changed"]:ADD(eachName).
		} ELSE IF kosChanged AND buildFiles[eachName]["form"] = "ksm" {
			result["changed"]:ADD(eachName).
		}
	}
	FOR eachName IN localFiles:KEYS {
		IF NOT buildFiles:HASKEY(eachName) result["removed"]:ADD(eachName).
	}
	RETURN result.
}

// Report Archive Differences
// Called at boot. Prints how the local scripts compare to the archive's build, and leaves a short message for loop.
// Passed the following:
//			no arguments
// Returns the following:
//			nothing
FUNCTION reportArchiveDifferences {
	IF connectionToKSC() PRINT "Checking script versions...".
	LOCAL state IS compareWithArchive().
	IF NOT state["connected"] {
		PRINT "No connection to the archive, so script versions were not checked.".
		RETURN.
	}
	// there is nothing to compare without a build and a manifest
	IF NOT (state["hasBuild"] AND state["hasManifest"]) {
		LOCAL problem IS syncProblem(state, FALSE).
		PRINT problem + ".".
		SET bootMessage TO problem.
		WAIT 2.
		RETURN.
	}
	LOCAL total IS state["changed"]:LENGTH + state["new"]:LENGTH + state["removed"]:LENGTH.
	IF state["buildStale"] <> "" {
		PRINT "The archive's build is out of date (" + state["buildStale"] + "). Use the build command.".
		SET bootMessage TO "Build out of date: use build".
	}
	IF total = 0 {
		IF state["buildStale"] = "" PRINT "Local scripts match the archive.".
		ELSE WAIT 3.
		RETURN.
	}
	PRINT total + " script(s) differ from the archive's build:".
	FOR scriptName IN state["changed"] { PRINT "   changed  " + scriptName. }
	FOR scriptName IN state["new"] { PRINT "   new      " + scriptName. }
	FOR scriptName IN state["removed"] { PRINT "   removed  " + scriptName. }
	PRINT "Use the update command to apply these changes.".
	IF state["buildStale"] = "" SET bootMessage TO total + " scripts differ: use update".
	WAIT 3.
}

// Scripts Called By
// Looks through the source of a script for the scripts it runs, with RUNPATH, RUNONCEPATH or RUN ONCE followed by
// a name in quotes. A script that is run by a name held in a variable cannot be found, and a call that has been
// commented out is found anyway. The source is read from the archive, or from the local drive if the script
// is there as a .ks file.
// Passed the following:
//			scriptName (string, without an extension)
// Returns the following:
//			a list of the names (without extensions) of the scripts it runs
FUNCTION scriptsCalledBy {
	PARAMETER scriptName.
	LOCAL called IS LIST().
	LOCAL sourcePath IS "".
	IF connectionToKSC() AND EXISTS("0:" + scriptName + ".ks") SET sourcePath TO "0:" + scriptName + ".ks".
	ELSE IF EXISTS("1:" + scriptName + ".ks") SET sourcePath TO "1:" + scriptName + ".ks".
	IF sourcePath = "" RETURN called.
	LOCAL source IS OPEN(sourcePath):READALL:STRING.
	LOCAL upperSource IS source:TOUPPER.
	FOR keyword IN LIST("RUNPATH(", "RUNONCEPATH(", "RUN ONCE") {
		LOCAL position IS upperSource:FIND(keyword).
		UNTIL position = -1 {
			LOCAL afterKeyword IS position + keyword:LENGTH.
			// the name must be a string in quotes right after the keyword
			LOCAL quoteStart IS source:FINDAT(CHAR(34), afterKeyword).
			IF quoteStart <> -1 {
				IF source:SUBSTRING(afterKeyword, quoteStart - afterKeyword):TRIM = "" {
					LOCAL quoteEnd IS source:FINDAT(CHAR(34), quoteStart + 1).
					IF quoteEnd <> -1 called:ADD(baseName(source:SUBSTRING(quoteStart + 1, quoteEnd - quoteStart - 1))).
				}
			}
			SET position TO upperSource:FINDAT(keyword, afterKeyword).
		}
	}
	RETURN called.
}

// Record Loaded Version
// Remembers which version of a script is being loaded into memory, the first time it is. A script that is not in
// the manifest (one made only on this ship) is not tracked, unless unknownIsZero is set.
// Passed the following:
//			scriptName (string, without an extension)
//			unknownIsZero (bool, record the script with an unknown version if it is not in the manifest)
FUNCTION recordLoadedVersion {
	PARAMETER scriptName, unknownIsZero.
	IF loadedVersions:HASKEY(scriptName) RETURN.
	LOCAL manifest IS readManifest().
	IF manifest:ISTYPE("Lexicon") {
		IF manifest["files"]:HASKEY(scriptName) {
			SET loadedVersions[scriptName] TO manifest["files"][scriptName].
			RETURN.
		}
	}
	IF unknownIsZero SET loadedVersions[scriptName] TO 0.
}
// Mark Script Run
// Called by loop before it runs a script. The script, and the scripts that it runs, and so on, become loaded, so a
// later update to one of them needs a reboot before it is noticed.
// Passed the following:
//			scriptName (string, as typed)
FUNCTION markScriptRun {
	PARAMETER scriptName.
	LOCAL toVisit IS LIST(baseName(scriptName)).
	LOCAL visited IS LEXICON().
	UNTIL toVisit:LENGTH = 0 {
		LOCAL current IS toVisit[0].
		toVisit:REMOVE(0).
		IF NOT visited:HASKEY(current) {
			SET visited[current] TO TRUE.
			recordLoadedVersion(current, FALSE).
			FOR eachChild IN scriptsCalledBy(current) {
				IF NOT visited:HASKEY(eachChild) toVisit:ADD(eachChild).
			}
		}
	}
}

// Sync Problem
// Passed the following:
//			state (lexicon, from compareWithArchive)
//			forceAll (bool, installing every script again does not need a manifest)
// Returns the following:
//			why scripts cannot be installed (string, a short message), or "" if they can
FUNCTION syncProblem {
	PARAMETER state, forceAll.
	IF NOT state["connected"] RETURN "No connection to the archive".
	IF NOT state["hasBuild"] RETURN "No archive build: use build".
	IF NOT (state["hasManifest"] OR forceAll) RETURN "No script manifest: use update,T".
	IF state["buildStale"] <> "" RETURN "Build out of date: use build".
	RETURN "".
}

// Sync Scripts
// Brings the local scripts up to date with the archive's build: copies scripts that changed or are new, and
// deletes the local copies of scripts that are no longer in the build. Only files recorded in the manifest are
// ever deleted, so files created by other scripts (logs, the command history and so on) are left alone.
// The critical files are installed first, and only if all of the changed ones fit. If the connection or power is lost
// in the middle, the files that were being replaced are missing from the manifest, so the next update or boot
// installs them again, and boot notices the journal file and does that by itself.
// Passed the following:
//			forceAll (bool, build the archive first if its build is missing or out of date, install every script
//			again even if it has not changed, and make a manifest if there is none)
// Returns the following:
//			a lexicon with "message" (string, a short description of the result) and "installed" (scalar, the number
//			of scripts that were copied)
FUNCTION syncScripts {
	PARAMETER forceAll.
	LOCAL outcome IS LEXICON("message", "", "installed", 0).
	LOCAL state IS compareWithArchive().
	IF forceAll AND state["connected"] AND ((NOT state["hasBuild"]) OR state["buildStale"] <> "") {
		buildArchive(FALSE).
		SET state TO compareWithArchive().
	}
	LOCAL problem IS syncProblem(state, forceAll).
	IF problem <> "" {
		SET outcome["message"] TO problem.
		RETURN outcome.
	}
	// installing everything again shows its progress on a clear screen
	IF forceAll CLEARSCREEN.

	LOCAL buildFiles IS state["build"]["files"].
	LOCAL installed IS LEXICON().
	LOCAL hadBefore IS LEXICON().
	IF state["hasManifest"] {
		SET installed TO state["manifest"]["files"].
		FOR eachName IN installed:KEYS {
			SET hadBefore[eachName] TO TRUE.
		}
	}
	LOCAL toInstall IS LIST().
	IF forceAll {
		FOR eachName IN buildFiles:KEYS {
			toInstall:ADD(eachName).
		}
	} ELSE {
		FOR eachName IN state["changed"] {
			toInstall:ADD(eachName).
		}
		FOR eachName IN state["new"] {
			toInstall:ADD(eachName).
		}
	}
	SET toInstall TO installOrder(toInstall, buildFiles).

	// the critical files fit together, or nothing is changed
	LOCAL shortBytes IS criticalShortage(toInstall, buildFiles).
	IF shortBytes > 0 {
		SET outcome["message"] TO "Critical files need " + ROUND(shortBytes) + " more bytes".
		RETURN outcome.
	}

	// journal: the scripts that are about to change are taken out of the manifest first, and a marker file is
	// left until everything is done
	IF toInstall:LENGTH > 0 OR state["removed"]:LENGTH > 0 {
		LOG "updating" TO journalPath.
		FOR eachName IN toInstall {
			IF installed:HASKEY(eachName) installed:REMOVE(eachName).
		}
		writeManifest(installed, state["build"]["kos"]).
	}

	LOCAL updatedCount IS 0.
	LOCAL newCount IS 0.
	LOCAL removedCount IS 0.
	LOCAL failedCount IS 0.
	LOCAL newlyPending IS 0.
	LOCAL position IS 0.
	FOR eachName IN toInstall {
		SET position TO position + 1.
		IF forceAll PRINT "Installing " + position + " of " + toInstall:LENGTH + ": " + eachName:PADRIGHT(30) AT (0, 3).
		IF installScript(eachName, buildFiles[eachName]) {
			SET installed[eachName] TO buildFiles[eachName]["fingerprint"].
			IF hadBefore:HASKEY(eachName) SET updatedCount TO updatedCount + 1.
			ELSE SET newCount TO newCount + 1.
			// a script that is already in memory does not use the new file until the next reboot
			IF loadedVersions:HASKEY(eachName) {
				IF loadedVersions[eachName] <> buildFiles[eachName]["fingerprint"] {
					IF NOT rebootPending:CONTAINS(eachName) {
						rebootPending:ADD(eachName).
						SET newlyPending TO newlyPending + 1.
					}
				}
			}
		} ELSE SET failedCount TO failedCount + 1.
	}
	FOR eachName IN state["removed"] {
		FOR eachFile IN installedFiles(eachName) {
			DELETEPATH(eachFile).
		}
		IF installed:HASKEY(eachName) installed:REMOVE(eachName).
		SET removedCount TO removedCount + 1.
	}
	// the boot file is always started from here
	IF installed:HASKEY("boot") {
		IF CORE:BOOTFILENAME <> "/boot.ksm" SET CORE:BOOTFILENAME TO "/boot.ksm".
	}
	LOCAL manifestSaved IS writeManifest(installed, state["build"]["kos"]).
	IF EXISTS(journalPath) DELETEPATH(journalPath).

	SET outcome["installed"] TO updatedCount + newCount.
	LOCAL parts IS LIST().
	IF updatedCount > 0 parts:ADD(updatedCount + " updated").
	IF newCount > 0 parts:ADD(newCount + " new").
	IF removedCount > 0 parts:ADD(removedCount + " removed").
	IF failedCount > 0 parts:ADD(failedCount + " no room").
	IF parts:LENGTH = 0 {
		SET outcome["message"] TO "Local scripts already match archive".
		RETURN outcome.
	}
	LOCAL message IS "".
	FOR part IN parts {
		IF message <> "" SET message TO message + ", ".
		SET message TO message + part.
	}
	IF newlyPending > 0 SET message TO message + ". Reboot to apply".
	IF NOT manifestSaved SET message TO message + ". No room to save the manifest".
	SET outcome["message"] TO message.
	RETURN outcome.
}
// Wipe Local Scripts
// Deletes every script on the local drive (.ks and .ksm files), the manifest and the update leftovers, so that a fresh
// copy from the archive has all of the room. Other files (the command history, logs and so on) are left alone.
// Passed the following:
//			no arguments
// Returns the following:
//			nothing
FUNCTION wipeLocalScripts {
	LOCAL doomed IS LIST(manifestPath, oldManifestPath, journalPath).
	FOR item IN CORE:VOLUME:FILES:VALUES {
		IF item:ISFILE {
			IF item:EXTENSION = "ks" OR item:EXTENSION = "ksm" OR item:EXTENSION = "new" doomed:ADD("1:" + item:NAME).
		}
	}
	FOR eachFile IN doomed {
		IF EXISTS(eachFile) DELETEPATH(eachFile).
	}
	IF EXISTS(reinstallFlagPath) DELETEPATH(reinstallFlagPath).
	SET manifestCache TO FALSE.
}
// Wait 1/4 of a second for the universe to fully load.
// If this isn't there, things like HOMECONNECTION:ISCONNECTED aren't right.
WAIT 0.25.

IF KUNIVERSE:TIMEWARP:RATE < 100 CORE:DOEVENT("Open Terminal").
SET TERMINAL:BRIGHTNESS TO 1.
setTerminalSize().

LOCAL loopFound TO TRUE.

isStockWorld().
isStockRockets().

// default to running on the local drive, if all the files are loaded already
FOR criticalFileName IN criticalFileNames {
	IF NOT EXISTS("1:" + criticalFileName) SET loopFound TO FALSE.
}
IF EXISTS(reinstallFlagPath) {
	// only with a connection, because the wipe needs the archive to put everything back
	IF connectionToKSC() {
		PRINT "Reinstall requested".
		SET loopFound TO FALSE.
	} ELSE {
		DELETEPATH(reinstallFlagPath).
		SET bootMessage TO "Reinstall cancelled: no connection".
	}
}
IF loopFound {
	PRINT "Found local loop with valid settings".
	IF EXISTS(journalPath) {
		// the last update did not finish, so install the scripts that were being replaced
		PRINT "The last update did not finish.".
		DELETEPATH(journalPath).
		IF connectionToKSC() {
			PRINT syncScripts(FALSE)["message"].
		} ELSE SET bootMessage TO "Update unfinished: use update".
	}
	reportArchiveDifferences().
}
ELSE {
	// if loop does not exist on the local drive, check to see if we can copy it from the archive
	IF (connectionToKSC()) {
		// a missing critical file means a fresh start: the archive's build must be usable before anything is deleted
		LOCAL freshState IS compareWithArchive().
		IF (NOT freshState["hasBuild"]) OR freshState["buildStale"] <> "" buildArchive(FALSE).
		IF compareWithArchive()["hasBuild"] wipeLocalScripts().
		PRINT "Copying scripts to local hard drive".
		IF syncScripts(TRUE)["installed"] > 0 {
			PRINT "Successfully copied files to local drive".
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
	// boot and the critical files are what runs loop, so they are loaded
	recordLoadedVersion("boot", TRUE).
	FOR eachName IN criticalFileNames {
		recordLoadedVersion(eachName, TRUE).
	}
	PRINT "Running local Loop.ksm".
	WAIT 0.5.
	SWITCH TO 1.
	RUNPATH("1:loop").
}
PRINT "Returning control to the terminal".
