@LAZYGLOBAL OFF.

LOCAL finalAltitude IS 25000.
IF SHIP:BODY:ATM:EXISTS SET finalAltitude TO SHIP:BODY:ATM:HEIGHT - 5000.

CLEARSCREEN.

IF NOT HASTARGET {
	PRINT "Select a target.".
	PRINT "One or the other must be true:".
	PRINT "    It must be in the current SOI".
	PRINT "    It must be on an intercept course with the current SOI.".
	UNTIL HASTARGET {WAIT 0.}
	WAIT 0.5.
}

// Find the list of all orbits the target will have over time.
LOCAL orbits IS LIST().
LOCAL targetOrbit IS TARGET:ORBIT.
UNTIL NOT targetOrbit:HASNEXTPATCH {
	orbits:ADD(targetOrbit).
	SET targetOrbit TO targetOrbit:NEXTPATCH.
}
orbits:ADD(targetOrbit).

// Scroll through the orbits and determine which orbits intersect the current SOI.
// If there are more than one, stop at the first.
LOCAL finalTargetOrbit IS "None".
LOCAL previousTargetOrbit IS 0.
FOR eachOrbit IN orbits {
	IF eachOrbit:HASNEXTPATCH AND eachOrbit:NEXTPATCH:BODY:NAME = SHIP:BODY:NAME {
		SET previousTargetOrbit TO eachOrbit.
	}
	IF eachOrbit:BODY:NAME = SHIP:BODY:NAME {
		SET finalTargetOrbit TO eachOrbit.
		BREAK.
	}
}

LOCAL tempChar IS "".
IF finalTargetOrbit = "None" {
	PRINT "Chosen object does not enter current SOI - cannot find orbit to park in".
} ELSE {
	IF previousTargetOrbit = 0 {
		SET tempChar TO TERMINAL:INPUT:ENTER.
		PRINT "Target is already within the current SOI.".
	} ELSE {
		PRINT "Target enters the current SOI in " + timeToString(previousTargetOrbit:NEXTPATCHETA).
	}
	PRINT "Press ENTER to continue or BACKSPACE to abort launch".
	UNTIL (tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE) {
		IF TERMINAL:INPUT:HASCHAR {
			SET tempChar TO TERMINAL:INPUT:GETCHAR().
		}
		WAIT 0.
	}
}
IF tempChar = TERMINAL:INPUT:ENTER {
	// Figure out how long the target will remain within this SOI, and compare
	// that to how long a Hohmann transfer would take from a parking orbit
	// 5 km above the atmosphere up to the periapsis of the target's orbit
	// within this SOI.
	LOCAL entryETA IS 0.
	IF previousTargetOrbit <> 0 SET entryETA TO previousTargetOrbit:NEXTPATCHETA.

	LOCAL exitETA IS 1000000000.		// treat a target that never leaves this SOI as an unlimited window
	IF finalTargetOrbit:HASNEXTPATCH SET exitETA TO finalTargetOrbit:NEXTPATCHETA.

	LOCAL durationInSOI IS exitETA - entryETA.

	LOCAL atmHeight IS 0.
	IF SHIP:BODY:ATM:EXISTS SET atmHeight TO SHIP:BODY:ATM:HEIGHT.
	LOCAL parkingRadius IS SHIP:BODY:RADIUS + atmHeight + 5000.
	LOCAL targetPeriRadius IS SHIP:BODY:RADIUS + finalTargetOrbit:PERIAPSIS.
	LOCAL transferSMA IS (parkingRadius + targetPeriRadius) / 2.
	LOCAL transferTime IS CONSTANT:PI * SQRT(transferSMA^3 / SHIP:BODY:MU).

	PRINT "Target will be within this SOI for " + timeToString(durationInSOI).
	PRINT "Hohmann transfer time to the target's periapsis: " + timeToString(transferTime).

	IF durationInSOI < 1.5 * transferTime {
		PRINT "SOI window is tight relative to the transfer time - launching immediately.".
	} ELSE {
		LOCAL waitTime IS entryETA - transferTime.
		IF waitTime > 0 {
			PRINT "SOI window has plenty of margin - waiting " + timeToString(waitTime) + " so launch happens one transfer time before the target arrives.".
			warpToTime(TIME:SECONDS + waitTime).
			WAIT 0.
			UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE = 1 {WAIT 0.}

			LOCAL oldVelocity IS SHIP:VELOCITY:ORBIT.
			WAIT 0.1.
			UNTIL (SHIP:VELOCITY:ORBIT - oldVelocity):MAG < 0.05 {
				SET oldVelocity TO SHIP:VELOCITY:ORBIT.
				WAIT 0.1.
			}
		} ELSE {
			PRINT "SOI window has plenty of margin, and the target is already within one transfer time of entering - launching immediately.".
		}
	}
	
	WAIT 5.

	RUNPATH("GravTurnLaunch", finalAltitude, finalTargetOrbit:INCLINATION, finalTargetOrbit:LAN).
} ELSE {
	PRINT "Launch aborted!".
	WAIT 1.
	SET loopMessage TO "Launch aborted".
}
