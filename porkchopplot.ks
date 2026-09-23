@LAZYGLOBAL OFF.

PARAMETER fromBodyName IS "Mun".
PARAMETER toBodyName IS "Minmus".
PARAMETER startOffset IS 120.

LOCAL errorCode IS "None".

IF NOT BODYEXISTS(fromBodyName) SET errorCode TO fromBodyName + " does not exist!".
IF NOT BODYEXISTS(toBodyName) SET errorCode TO toBodyName + " does not exist!".
IF startOffset < 0 SET errorCode TO "negative start offset not allowed!".

IF errorCode = "None" {IF BODY(fromBodyName):BODY:NAME <> BODY(toBodyName):BODY:NAME SET errorCode TO "Bodies must have the same parent!".}

IF errorCode = "None" {
	LOCAL fromBody IS BODY(fromBodyName).
	LOCAL toBody IS BODY(toBodyName).
	LOCAL sunBody IS firstCommonBody(fromBody, toBody).

	LOCAL logFileName IS "0:gaussProblem.csv".
	IF EXISTS(logFileName) DELETEPATH(logFileName).

	LOCAL synodicPeriod IS 1 / ABS((1 / fromBody:ORBIT:PERIOD) - (1 / toBody:ORBIT:PERIOD)).

	LOCAL departureTime IS 0.
	LOCAL startTime IS TIME:SECONDS + startOffset.

	LOCAL timeOfFlight IS 0.
	LOCAL minDeltaV IS LEXICON("value", 1e15).

	LOCAL dvGridRows IS LIST().        // one entry per timeOffset; each entry is a LIST of dV values across all TOFs
	LOCAL departureLabels IS LIST().   // row headers - departure time, in days from now
	LOCAL tofLabels IS LIST().         // column headers - time of flight, in days
	LOCAL tofLabelsBuilt IS FALSE.     // only need to build the column headers once
	
	// Bind this run's bodies into porkchopDeltaV. BIND fills in parameters
	// left-to-right, one per call, so porkchopDeltaV's parameter list was
	// ordered (fromBody, toBody, sunBody, departureTime, timeOfFlight)
	// specifically so these three binds land in the right slots, leaving
	// (departureTime, timeOfFlight) as the only two arguments the resulting
	// delegate still needs - both are absolute values (UT seconds / duration
	// in seconds), so synodicPeriod and startTime never need to be bound at
	// all; they're only used locally below to build the grid of departure/TOF
	// times to test, exactly as they always were for the rest of the loop.
	LOCAL porkchopDeltaVBound IS porkchopDeltaV@.
	SET porkchopDeltaVBound TO porkchopDeltaVBound:BIND(fromBody).
	SET porkchopDeltaVBound TO porkchopDeltaVBound:BIND(toBody).
	SET porkchopDeltaVBound TO porkchopDeltaVBound:BIND(sunBody).

	// timeOffset is departure time in hundredths of the synodic period
	FOR timeOffset IN RANGE(0, 299, 5) {
		LOCAL currentDvRow IS LIST(). // this departure time's row of dV values, one per TOF
		SET departureTime TO startTime + (timeOffset / 100) * synodicPeriod.
		// Number is time of flight in hundredths of the synodic period
		FOR number IN RANGE(30, 151, 5) {
			SET timeOfFlight TO synodicPeriod * ((number) / 100).
			PRINT "Calculating departure " + (timeOffset / 100) + " periods, flight time " + ((number) / 100) + " periods.".
			LOCAL dv IS porkchopDeltaVBound(departureTime, timeOfFlight). // both absolute: UT in seconds, duration in seconds
			
			IF minDeltaV["value"] > dv {
				SET minDeltaV["value"] TO dv.
				SET minDeltaV["departureTime"] TO departureTime.
				SET minDeltaV["timeOfFlight"] TO timeOfFlight.
			}
			currentDvRow:ADD(dv).

			// build the column headers (time of flight, in days) only on the first departure-time pass
			IF NOT tofLabelsBuilt tofLabels:ADD(ROUND(timeOfFlight / (KUNIVERSE:HOURSPERDAY * 3600), 2)).
		} // closes "FOR number IN RANGE" - the time-of-flight loop

		// this departure time's row is now complete (currentDvRow has one cell per
		// TOF value) - store it and record its row header. This must happen here,
		// after the TOF loop closes, NOT inside it - otherwise a partial row gets
		// pushed on every single TOF iteration instead of one full row per
		// departure time.
		dvGridRows:ADD(currentDvRow).
		departureLabels:ADD(ROUND((timeOffset / 100) * synodicPeriod / (KUNIVERSE:HOURSPERDAY * 3600), 2)).
		SET tofLabelsBuilt TO TRUE.
	} // closes "FOR timeOffset IN RANGE" - the departure-time loop

	// --- Write the classic porkchop plot grid: departure time down the rows, TOF across the columns ---
	LOCAL gridHeaderRow IS "Departure (days) \ TOF (days)".
	FOR tofLabel IN tofLabels {
		SET gridHeaderRow TO gridHeaderRow + "," + tofLabel.
	}
	LOG gridHeaderRow TO logFileName.

	FOR rowIndex IN RANGE(0, dvGridRows:LENGTH) {
		LOCAL gridRowString IS departureLabels[rowIndex]:TOSTRING.
		FOR cellValue IN dvGridRows[rowIndex] {
			SET gridRowString TO gridRowString + "," + cellValue.
		}
		LOG gridRowString TO logFileName.
	}

	PRINT "Complete".
	WAIT 0.5.
	SET loopMessage TO "Min dV between " + toBody:NAME + " and " + fromBody:NAME + " is " + distanceToString(minDeltaV["value"]) + "/s" +
		" at departure " + timeToString(minDeltaV["departureTime"] - startTime) + ", TOF " + timeToString(minDeltaV["timeOfFlight"]).
} ELSE SET loopMessage TO "Error: " + errorCode.
