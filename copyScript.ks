@LAZYGLOBAL OFF.

PARAMETER scriptName.						// the name of the script to compile and copy to the local drive

IF connectionToKSC() {
	IF EXISTS("1:" + scriptName + ".ks") DELETEPATH("1:" + scriptName + ".ks").
	IF EXISTS("1:" + scriptName + ".ksm") DELETEPATH("1:" + scriptName + ".ksm").
	COMPILE "0:" + scriptName + ".ks" TO "1:" + scriptName + ".ksm".
	IF EXISTS("1:" + scriptName + ".ksm") SET loopMessage TO "File compiled and copied.".
	ELSE SET loopMessage TO "File was not copied correctly!".
}
ELSE SET loopMessage TO "No connection to KSC, cannot copy script".
