@LAZYGLOBAL OFF.

// The name of the target, a body or a vessel. If it is not given, or is not found, the target that is selected is used,
// and if none is selected, the script waits until one is.
PARAMETER targetName IS "Default".

LOCAL finalAltitude IS 25000.
IF SHIP:BODY:ATM:EXISTS SET finalAltitude TO SHIP:BODY:ATM:HEIGHT - 5000.

CLEARSCREEN.

// If the name resolves to an orbitable, that is the target. The ship itself does not count.
IF targetName <> "Default" {
	LOCAL namedTarget IS resolveOrbitable("" + targetName).
	IF namedTarget:ISTYPE("Scalar") OR (namedTarget:ISTYPE("Vessel") AND namedTarget:NAME = SHIP:NAME) {
		PRINT "No target named " + targetName + " was found.".
		IF HASTARGET PRINT "Using the selected target, " + TARGET:NAME + ".".
	} ELSE {
		SET TARGET TO namedTarget.
		WAIT 0.
	}
}

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

// A target that never enters this SOI (a body orbiting something else, for instance) has no orbit here to park in.
// If transferCalc saved a launch plan on this ship's own disk for that target, launch into the plan's plane instead.
// Returns "None" if the saved plan can be used for the current target, otherwise the reason it cannot (string).
FUNCTION savedPlanProblem {
	PARAMETER planPath.
	PARAMETER plan.
	IF NOT TARGET:ISTYPE("Body") RETURN "the target is not a body".
	IF NOT EXISTS(planPath) RETURN "no saved launch plan".
	IF NOT plan:ISTYPE("Lexicon") RETURN "the saved plan is not a lexicon".
	FOR requiredKey IN LIST("version", "departureBody", "destination", "inclination", "lan", "burnUT") {
		IF NOT plan:HASKEY(requiredKey) RETURN "the saved plan has no " + requiredKey.
	}
	IF plan["destination"] <> TARGET:NAME RETURN "the saved plan is for " + plan["destination"].
	IF plan["version"] <> 1 RETURN "the saved plan is version " + plan["version"] + ", and only version 1 is understood".
	IF plan["departureBody"] <> SHIP:BODY:NAME RETURN "the saved plan departs from " + plan["departureBody"] + ", not " + SHIP:BODY:NAME.
	IF plan["burnUT"] <= TIME:SECONDS RETURN "the saved plan's ejection burn time has already passed".
	RETURN "None".
}

LOCAL planPath IS "1:transferPlan.json".
LOCAL plan IS LEXICON().
LOCAL usePlan IS FALSE.

// The plane to launch into. Both come from the target's orbit, unless a saved plan overrides them.
LOCAL launchInclination IS 0.
LOCAL launchLAN IS 0.

// With a saved plan, the launch is timed to the ejection burn. GravTurnLaunch then waits for the launch site to pass through
// the plane, which takes at most one rotation of the body, and the ascent takes about 20 minutes. So the lead before the burn is
// a rotation plus the ascent, so that the ship is in orbit before the burn however long the plane wait turns out to be.
LOCAL planLeadTime IS SHIP:BODY:ROTATIONPERIOD + 20 * 60.

LOCAL tempChar IS "".
IF finalTargetOrbit = "None" {
	IF EXISTS(planPath) SET plan TO READJSON(planPath).
	LOCAL planProblem IS savedPlanProblem(planPath, plan).
	IF planProblem = "None" {
		PRINT "Target " + TARGET:NAME + " does not enter the current SOI, so there is no orbit here to park in.".
		PRINT "Using the saved launch plan for " + TARGET:NAME + " instead.".
		PRINT "Inclination:      " + ROUND(plan["inclination"], 3) + " deg".
		PRINT "LAN:              " + ROUND(plan["lan"], 3) + " deg".
		PRINT "Ejection burn at: " + plan["burnClock"] + " (" + plan["burnCalendar"] + "), in " + timeToString(plan["burnUT"] - TIME:SECONDS).
		PRINT "The ship will warp until " + timeToString(planLeadTime) + " before the burn, then wait for the launch site to pass through the plane.".
		PRINT "Press ENTER to continue or BACKSPACE to abort launch".
		UNTIL (tempChar = TERMINAL:INPUT:ENTER OR tempChar = TERMINAL:INPUT:BACKSPACE) {
			IF TERMINAL:INPUT:HASCHAR {
				SET tempChar TO TERMINAL:INPUT:GETCHAR().
			}
			WAIT 0.
		}
		SET usePlan TO (tempChar = TERMINAL:INPUT:ENTER).
		// The plan overrides the plane that would have come from the target's orbit.
		SET launchInclination TO plan["inclination"].
		SET launchLAN TO plan["lan"].
	} ELSE {
		PRINT "Chosen object does not enter current SOI - cannot find orbit to park in".
		IF planProblem <> "no saved launch plan" AND planProblem <> "the target is not a body" PRINT "Saved launch plan not used: " + planProblem + ".".
	}
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
	// With a saved plan there is no orbit of the target in this SOI to time the launch against, so the SOI timing is skipped.
	IF NOT usePlan {
		// Figure out how long the target will remain within this SOI, and compare
		// that to how long a Hohmann transfer would take from a parking orbit
		// 5 km above the atmosphere up to the periapsis of the target's orbit
		// within this SOI.
		LOCAL entryETA IS 0.
		IF previousTargetOrbit <> 0 SET entryETA TO previousTargetOrbit:NEXTPATCHETA.

		LOCAL exitETAInitial IS 1000000000. // treat a target that never leaves this SOI as an unlimited window
		LOCAL exitETA IS 1000000000.
		IF finalTargetOrbit:HASNEXTPATCH SET exitETA TO finalTargetOrbit:NEXTPATCHETA.

		LOCAL durationInSOI IS exitETA - entryETA.

		LOCAL atmHeight IS 0.
		IF SHIP:BODY:ATM:EXISTS SET atmHeight TO SHIP:BODY:ATM:HEIGHT.
		LOCAL parkingRadius IS SHIP:BODY:RADIUS + atmHeight + 5000.
		LOCAL targetPeriRadius IS SHIP:BODY:RADIUS + finalTargetOrbit:PERIAPSIS.
		LOCAL transferSMA IS (parkingRadius + targetPeriRadius) / 2.
		LOCAL transferTime IS CONSTANT:PI * SQRT(transferSMA^3 / SHIP:BODY:MU).

		IF exitETA = exitETAInitial {
			PRINT "Target is in a bound orbit within this SOI.".
		} ELSE PRINT "Target will be within this SOI for " + timeToString(durationInSOI).
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

		SET launchInclination TO finalTargetOrbit:INCLINATION.
		SET launchLAN TO finalTargetOrbit:LAN.
	} ELSE {
		// There is no SOI window to time against, so time the launch to the ejection burn instead.
		LOCAL waitTime IS plan["burnUT"] - TIME:SECONDS - planLeadTime.
		IF waitTime > 0 {
			PRINT "Waiting " + timeToString(waitTime) + " so launch happens " + timeToString(planLeadTime) + " before the ejection burn.".
			warpToTime(TIME:SECONDS + waitTime).
			WAIT 0.
			UNTIL KUNIVERSE:TIMEWARP:ISSETTLED AND KUNIVERSE:TIMEWARP:RATE = 1 {WAIT 0.}
		} ELSE {
			PRINT "The ejection burn is less than " + timeToString(planLeadTime) + " away - launching immediately.".
		}
	}

	WAIT 5.

	// The plan has been used, so remove it from the ship's disk. The values are already in launchInclination and launchLAN.
	IF usePlan DELETEPATH(planPath).

	RUNPATH("GravTurnLaunch", finalAltitude, launchInclination, launchLAN).
} ELSE {
	PRINT "Launch aborted!".
	WAIT 1.
	SET loopMessage TO "Launch aborted".
}
