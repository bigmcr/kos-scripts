@LAZYGLOBAL OFF.

FUNCTION connectionToKSC {
	RETURN HOMECONNECTION:ISCONNECTED.
}

FUNCTION debugString {
	PARAMETER message.
	IF connectionToKSC() LOG SHIP:NAME + "," + message TO "0:Logfile.txt".
}

FUNCTION copyToLocal {
	IF NOT connectionToKSC() RETURN FALSE.
	CLEARSCREEN.

	COMPILE "0:loopMinimal.ks" TO "1:loopMinimal.ksm".
	COMPILE "0:boot/bootMinimal.ks" TO "1:bootMin.ksm".
	SET CORE:BOOTFILENAME    TO "1:bootMin.ksm".
	PRINT "Boot file name set to " + CORE:BOOTFILENAME.
	RETURN TRUE.
}

WAIT 1.

SET TERMINAL:BRIGHTNESS TO 1.
SET TERMINAL:WIDTH TO 40.
SET TERMINAL:HEIGHT TO 20.

LOCAL loopFound TO FALSE.

// default to running on the local drive, if all the files are loaded already
IF EXISTS("1:/loopMinimal.ksm") {
	SET loopFound TO TRUE.
	PRINT "Found local loopMinimal".
}
ELSE {
	// if loopMinimal.ksm does not exist on the local drive, check to see if we can copy it from the archive
	IF (connectionToKSC()) {
		PRINT "Copying scripts to local hard drive".
		IF copyToLocal() {
			PRINT "Sucessfully copied files to local drive".
			SET loopFound TO TRUE.
		} ELSE PRINT "Failed to copy files to local drive".
	} ELSE {
		PRINT "loopMinimal.ksm does not exist on the local drive".
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
