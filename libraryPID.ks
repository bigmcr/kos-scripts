@LAZYGLOBAL OFF.

// ============================================================================
// libraryPID.ks - PID loops that work on any number of axes, plus the tuning math and autotune routines that go with them.
//
// An "axis" is a Lexicon("PID", <a standard kOS PIDLoop>, "tune", <its tuning data>). A "set of axes" is a LIST of axes. An ordinary
// single PID loop is a set of one axis, and a 3D loop is a set of three; the same functions serve both. Every value, setpoint, output
// and limit that goes in or out of a function here is a LIST with one scalar per axis, in the same order as the axes.
//
// For 3D work with vectors (Fore/Top/Starboard, say), vectorToList() and listToVector() convert at the edges, and the adapter
// functions at the end of this file wrap a delegate that reads or applies vectors so that it reads or applies lists.
//
// Moved here from docking.ks (formerly PIDAutotune.ks). The only dependency on another file is timeToString() from library.ks, used
// in one warning message. The autotune and cascade loops have no display or logging of their own: the caller passes an onTick
// delegate (called once per loop iteration with the current stage label, for printing and logging) and an onMessage delegate
// (called with warning and error text). Both are optional; the defaults do nothing and PRINT, respectively.
// ============================================================================

// PIDEmptyTuning
// Inputs:
//   None.
// Outputs:
//   Lexicon with "Ku" and "Pu" (Scalar, both 0 because nothing has been measured). A new Lexicon every call, because Lexicons are
//   references and axes must not share one.
// Side Effects:
//   None.
FUNCTION PIDEmptyTuning {
    RETURN LEXICON("Ku", 0, "Pu", 0).
}

// PIDAxisConstruct
// Inputs:
//   kp (Scalar, default 1) - proportional gain.
//   ki (Scalar, default 0) - integral gain.
//   kd (Scalar, default 0) - derivative gain.
//   minOutput (Scalar, default -1) - minimum output.
//   maxOutput (Scalar, default 1) - maximum output.
// Outputs:
//   Lexicon with "PID" (a PIDLoop built with the given gains and output limits) and "tune" (PIDEmptyTuning(), until an autotune
//   replaces it).
// Side Effects:
//   None.
FUNCTION PIDAxisConstruct {
    PARAMETER kp IS 1.
    PARAMETER ki IS 0.
    PARAMETER kd IS 0.
    PARAMETER minOutput IS -1.
    PARAMETER maxOutput IS 1.

    RETURN LEXICON("PID", PIDLOOP(kp, ki, kd, minOutput, maxOutput), "tune", PIDEmptyTuning()).
}

// PIDAxesConstruct
// Inputs:
//   axisCount (Scalar, integer, > 0) - number of axes: 1 for an ordinary PID loop, 3 for a 3D one.
//   kp, ki, kd, minOutput, maxOutput - as for PIDAxisConstruct(); the same values are used on every axis.
// Outputs:
//   LIST of axisCount axes from PIDAxisConstruct(), each independent of the others.
// Side Effects:
//   None.
FUNCTION PIDAxesConstruct {
    PARAMETER axisCount.
    PARAMETER kp IS 1.
    PARAMETER ki IS 0.
    PARAMETER kd IS 0.
    PARAMETER minOutput IS -1.
    PARAMETER maxOutput IS 1.

    LOCAL axes IS LIST().
    LOCAL i IS 0.
    UNTIL i >= axisCount {
        axes:ADD(PIDAxisConstruct(kp, ki, kd, minOutput, maxOutput)).
        SET i TO i + 1.
    }
    RETURN axes.
}

// vectorToList
// Inputs:
//   vectorValue (Vector) - a vector.
// Outputs:
//   LIST(vectorValue:X, vectorValue:Y, vectorValue:Z).
// Side Effects:
//   None.
FUNCTION vectorToList {
    PARAMETER vectorValue.
    RETURN LIST(vectorValue:X, vectorValue:Y, vectorValue:Z).
}

// listToVector
// Inputs:
//   values (LIST of Scalar, at least 3 elements) - the first three become X, Y and Z.
// Outputs:
//   Vector - V(values[0], values[1], values[2]).
// Side Effects:
//   None.
FUNCTION listToVector {
    PARAMETER values.
    RETURN V(values[0], values[1], values[2]).
}

// PIDFilledList
// Inputs:
//   count (Scalar, integer, >= 0) - number of elements.
//   value (Scalar) - the value of every element.
// Outputs:
//   LIST of count copies of value.
// Side Effects:
//   None.
FUNCTION PIDFilledList {
    PARAMETER count.
    PARAMETER value.

    LOCAL filled IS LIST().
    LOCAL i IS 0.
    UNTIL i >= count {
        filled:ADD(value).
        SET i TO i + 1.
    }
    RETURN filled.
}

// PIDListScale
// Inputs:
//   values (LIST of Scalar) - the values to scale.
//   factor (Scalar) - what to multiply each element by.
// Outputs:
//   A new LIST of the elements of values, each multiplied by factor.
// Side Effects:
//   None.
FUNCTION PIDListScale {
    PARAMETER values.
    PARAMETER factor.

    LOCAL scaled IS LIST().
    FOR value IN values {
        scaled:ADD(value * factor).
    }
    RETURN scaled.
}

// PIDListDistance
// Inputs:
//   a (LIST of Scalar) - one point.
//   b (LIST of Scalar, same length as a) - another point.
// Outputs:
//   Scalar - the Euclidean distance between a and b (the magnitude of their difference, as for vectors).
// Side Effects:
//   None.
FUNCTION PIDListDistance {
    PARAMETER a.
    PARAMETER b.

    LOCAL sumSquares IS 0.
    LOCAL i IS 0.
    UNTIL i >= a:LENGTH {
        SET sumSquares TO sumSquares + (a[i] - b[i])^2.
        SET i TO i + 1.
    }
    RETURN SQRT(sumSquares).
}

// PIDAnyZero
// Inputs:
//   values (LIST of Scalar) - the values to check.
// Outputs:
//   Boolean - TRUE if any element of values is exactly 0.
// Side Effects:
//   None.
FUNCTION PIDAnyZero {
    PARAMETER values.

    FOR value IN values {
        IF value = 0 { RETURN TRUE. }
    }
    RETURN FALSE.
}

// PIDFormatList
// Inputs:
//   values (LIST of Scalar) - the values to show.
//   decimals (Scalar, integer) - places to round each element to.
// Outputs:
//   String - for example "[0.1235, 2, 3.5]".
// Side Effects:
//   None.
FUNCTION PIDFormatList {
    PARAMETER values.
    PARAMETER decimals.

    LOCAL text IS "[".
    LOCAL i IS 0.
    UNTIL i >= values:LENGTH {
        IF i > 0 { SET text TO text + ", ". }
        SET text TO text + ROUND(values[i], decimals).
        SET i TO i + 1.
    }
    RETURN text + "]".
}

// PIDAxesUpdate
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct().
//   sampleTime (Scalar) - current time, seconds; normally TIME:SECONDS.
//   values (LIST of Scalar) - current process value of each axis.
// Outputs:
//   LIST of Scalar - each axis's PIDLoop:UPDATE() output.
// Side Effects:
//   Advances the internal state (error sum, last input/time) of every PIDLoop.
FUNCTION PIDAxesUpdate {
    PARAMETER axes.
    PARAMETER sampleTime.
    PARAMETER values.

    LOCAL outputs IS LIST().
    LOCAL i IS 0.
    UNTIL i >= axes:LENGTH {
        outputs:ADD(axes[i]["PID"]:UPDATE(sampleTime, values[i])).
        SET i TO i + 1.
    }
    RETURN outputs.
}

// PIDAxesReset
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct().
// Outputs:
//   None.
// Side Effects:
//   Calls PIDLoop:RESET() on every axis, clearing its error sum and last input/time.
FUNCTION PIDAxesReset {
    PARAMETER axes.

    FOR axis IN axes {
        axis["PID"]:RESET().
    }
}

// PIDAxesSetSetpoints
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct().
//   setpoints (LIST of Scalar) - new setpoint of each axis.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:SETPOINT on every axis.
FUNCTION PIDAxesSetSetpoints {
    PARAMETER axes.
    PARAMETER setpoints.

    LOCAL i IS 0.
    UNTIL i >= axes:LENGTH {
        SET axes[i]["PID"]:SETPOINT TO setpoints[i].
        SET i TO i + 1.
    }
}

// PIDAxesSetLimits
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct().
//   minOutputs (LIST of Scalar) - new minimum output of each axis.
//   maxOutputs (LIST of Scalar) - new maximum output of each axis.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:MINOUTPUT and PIDLoop:MAXOUTPUT on every axis.
FUNCTION PIDAxesSetLimits {
    PARAMETER axes.
    PARAMETER minOutputs.
    PARAMETER maxOutputs.

    LOCAL i IS 0.
    UNTIL i >= axes:LENGTH {
        SET axes[i]["PID"]:MINOUTPUT TO minOutputs[i].
        SET axes[i]["PID"]:MAXOUTPUT TO maxOutputs[i].
        SET i TO i + 1.
    }
}

// PIDAxesSetGains
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct().
//   kps (LIST of Scalar) - new proportional gain of each axis.
//   kis (LIST of Scalar) - new integral gain of each axis.
//   kds (LIST of Scalar) - new derivative gain of each axis.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:KP, PIDLoop:KI and PIDLoop:KD on every axis.
FUNCTION PIDAxesSetGains {
    PARAMETER axes.
    PARAMETER kps.
    PARAMETER kis.
    PARAMETER kds.

    LOCAL i IS 0.
    UNTIL i >= axes:LENGTH {
        SET axes[i]["PID"]:KP TO kps[i].
        SET axes[i]["PID"]:KI TO kis[i].
        SET axes[i]["PID"]:KD TO kds[i].
        SET i TO i + 1.
    }
}

// PIDAxesGetGains
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct().
// Outputs:
//   Lexicon with "kp", "ki" and "kd", each a LIST of Scalar holding that gain of every axis.
// Side Effects:
//   None.
FUNCTION PIDAxesGetGains {
    PARAMETER axes.

    LOCAL gains IS LEXICON("kp", LIST(), "ki", LIST(), "kd", LIST()).
    FOR axis IN axes {
        gains["kp"]:ADD(axis["PID"]:KP).
        gains["ki"]:ADD(axis["PID"]:KI).
        gains["kd"]:ADD(axis["PID"]:KD).
    }
    RETURN gains.
}

// PIDAxesSaveTuning
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct(), already tuned.
//   filePath (String) - file to write, which must be on the local volume (for example "1:/velocityTuning.json"). Any file already
//        there is replaced.
//   context (Lexicon, default empty) - anything the caller wants stored with the tuning, to check when it is read back (for
//        example a description of the ship). It must be made only of numbers, strings, Booleans, Lists and Lexicons.
//   minFreeSpace (Scalar, bytes, default 3000) - the least free space left on the local volume, after removing the old file,
//        for which the file is written at all. kOS stops the script if a write does not fit, so this is checked first. The file
//        is about 3 kB, because kOS writes JSON with a lot of overhead for every List and Lexicon.
// Outputs:
//   Boolean - TRUE if the file was written, FALSE if there was not enough free space or it does not exist afterwards.
// Side Effects:
//   Writes filePath as JSON: "version" (2), "savedAt", "gains" (PIDAxesGetGains()), "ku" and "pu" (the measured ultimate gain and
//   period of each axis) and "context".
FUNCTION PIDAxesSaveTuning {
    PARAMETER axes.
    PARAMETER filePath.
    PARAMETER context IS LEXICON().
    PARAMETER minFreeSpace IS 3000.

    LOCAL kus IS LIST().
    LOCAL pus IS LIST().
    FOR axis IN axes {
        kus:ADD(axis["tune"]["Ku"]).
        pus:ADD(axis["tune"]["Pu"]).
    }
    LOCAL saved IS LEXICON("version", 2, "savedAt", TIME:SECONDS, "gains", PIDAxesGetGains(axes), "ku", kus, "pu", pus, "context", context).

    IF EXISTS(filePath) { DELETEPATH(filePath). }
    IF CORE:VOLUME:FREESPACE < minFreeSpace { RETURN FALSE. }

    WRITEJSON(saved, filePath).
    RETURN EXISTS(filePath).
}

// PIDTuningRead
// Inputs:
//   filePath (String) - a file written by PIDAxesSaveTuning().
// Outputs:
//   Lexicon - the saved Lexicon ("version", "savedAt", "gains", "ku", "pu", "context"), or an empty Lexicon if the file does not exist
//   or is not in the version 2 format.
// Side Effects:
//   None.
FUNCTION PIDTuningRead {
    PARAMETER filePath.

    IF NOT EXISTS(filePath) { RETURN LEXICON(). }
    LOCAL saved IS READJSON(filePath).
    IF NOT saved:ISTYPE("Lexicon") { RETURN LEXICON(). }
    IF NOT (saved:HASKEY("version") AND saved:HASKEY("gains") AND saved:HASKEY("context") AND saved:HASKEY("savedAt")) { RETURN LEXICON(). }
    IF saved["version"] <> 2 OR NOT (saved:HASKEY("ku") AND saved:HASKEY("pu")) { RETURN LEXICON(). }
    RETURN saved.
}

// PIDAxesApplyTuning
// Inputs:
//   axes (LIST of axes) - from PIDAxesConstruct(); it must have as many axes as were saved.
//   saved (Lexicon) - from PIDTuningRead().
// Outputs:
//   Boolean - TRUE if the saved tuning was applied, FALSE (with axes left unchanged) if it does not fit axes.
// Side Effects:
//   Replaces each axis's "tune" with the saved "Ku" and "Pu" and sets the Kp, Ki and Kd of every axis to the saved gains.
FUNCTION PIDAxesApplyTuning {
    PARAMETER axes.
    PARAMETER saved.

    IF NOT saved:HASKEY("gains") { RETURN FALSE. }
    LOCAL gains IS saved["gains"].
    IF gains["kp"]:LENGTH <> axes:LENGTH OR gains["ki"]:LENGTH <> axes:LENGTH OR gains["kd"]:LENGTH <> axes:LENGTH { RETURN FALSE. }

    IF NOT (saved:HASKEY("ku") AND saved:HASKEY("pu")) { RETURN FALSE. }
    IF saved["ku"]:LENGTH <> axes:LENGTH OR saved["pu"]:LENGTH <> axes:LENGTH { RETURN FALSE. }
    LOCAL i IS 0.
    UNTIL i >= axes:LENGTH {
        SET axes[i]["tune"] TO LEXICON("Ku", saved["ku"][i], "Pu", saved["pu"][i]).
        SET i TO i + 1.
    }
    PIDAxesSetGains(axes, gains["kp"], gains["ki"], gains["kd"]).
    RETURN TRUE.
}

// makeAxisRelayState
// Inputs:
//   initialValue (Scalar) - process value at the start of the relay test.
//   neededPoints (Scalar, integer) - number of turning points required
//        before the relay test on this axis is considered done.
//   settleCycles (Scalar, integer) - number of leading turning-point
//        pairs to discard as settling transient when computing tuning.
// Outputs:
//   Lexicon - per-axis relay-test state, with keys "relayState"
//   (Boolean), "prevValue" (Scalar), "rising" (Boolean), "turningPoints"
//   (List of Lexicon("time","value")), "neededPoints" (Scalar),
//   "settleCycles" (Scalar), "reversed" (Boolean), "done" (Boolean).
// Side Effects:
//   None.
FUNCTION makeAxisRelayState {
    PARAMETER initialValue.
    PARAMETER neededPoints.
    PARAMETER settleCycles.

    LOCAL s IS LEXICON().
    SET s["relayState"] TO TRUE.
    SET s["prevValue"] TO initialValue.
    SET s["rising"] TO TRUE.
    SET s["turningPoints"] TO LIST().
    SET s["neededPoints"] TO neededPoints.
    SET s["settleCycles"] TO settleCycles.
	SET s["reversed"] TO FALSE.
    SET s["done"] TO FALSE.
    RETURN s.
}

// tickAxisRelay
// Inputs:
//   axisState (Lexicon) - state from makeAxisRelayState(), updated in
//        place.
//   value (Scalar) - current process value.
//   setpoint (Scalar) - relay test's target value.
//   hysteresis (Scalar, >= 0) - relay switches state only once the error
//        exceeds +/-hysteresis.
// Outputs:
//   Scalar - 1 or -1, the relay's commanded output sign for this tick.
// Side Effects:
//   Updates axisState["relayState"], "prevValue", "rising",
//   "turningPoints" (appends on a rising/falling reversal), and "done"
//   (set TRUE once "turningPoints":LENGTH >= "neededPoints").
FUNCTION tickAxisRelay {
    PARAMETER axisState.
    PARAMETER value.
    PARAMETER setpoint.
    PARAMETER hysteresis.

    LOCAL relayError IS setpoint - value.
    IF relayError > hysteresis { SET axisState["relayState"] TO NOT axisState["reversed"]. }
    ELSE IF relayError < -hysteresis { SET axisState["relayState"] TO axisState["reversed"]. }

    LOCAL nowRising IS value >= axisState["prevValue"].
    IF nowRising <> axisState["rising"] {
        axisState["turningPoints"]:ADD(LEXICON("time", TIME:SECONDS, "value", axisState["prevValue"])).
        SET axisState["rising"] TO nowRising.
    }
    SET axisState["prevValue"] TO value.

    IF axisState["turningPoints"]:LENGTH >= axisState["neededPoints"] {
        SET axisState["done"] TO TRUE.
    }

    IF axisState["relayState"] { RETURN 1. }
    RETURN -1.
}

// computeAxisTuningRelay
// Inputs:
//   axisState (Lexicon) - state from makeAxisRelayState()/tickAxisRelay(), expected to have "turningPoints":LENGTH >= 4 for a valid
//        result.
//   relayAmplitude (Scalar) - magnitude of the relay output used during the test for this axis.
// Outputs:
//   Lexicon with "Ku" (Scalar, measured ultimate gain, negated if axisState["reversed"] is TRUE), "Pu" (Scalar, measured ultimate
//   period, seconds) and "kp", "ki", "kd" (Scalar, from the Tyreus-Luyben rule). All are 0 if the test data is insufficient.
// Side Effects:
//   None.
FUNCTION computeAxisTuningRelay {
    PARAMETER axisState.
    PARAMETER relayAmplitude.

    LOCAL noTuning IS LEXICON("Ku", 0, "Pu", 0, "kp", 0, "ki", 0, "kd", 0).
    LOCAL turningPoints IS axisState["turningPoints"].
    IF turningPoints:LENGTH < 4 { RETURN noTuning. }

    LOCAL skip IS MIN(axisState["settleCycles"] * 2, turningPoints:LENGTH - 4).
    LOCAL periodSum IS 0. LOCAL periodCount IS 0.
    LOCAL ampSum IS 0. LOCAL ampCount IS 0.

    LOCAL i IS skip.
    UNTIL i >= turningPoints:LENGTH - 1 {
        SET ampSum TO ampSum + ABS(turningPoints[i+1]["value"] - turningPoints[i]["value"]) / 2.
        SET ampCount TO ampCount + 1.
        IF i + 2 < turningPoints:LENGTH {
            SET periodSum TO periodSum + (turningPoints[i+2]["time"] - turningPoints[i]["time"]).
            SET periodCount TO periodCount + 1.
        }
        SET i TO i + 1.
    }

    LOCAL amplitude IS ampSum / ampCount.
    LOCAL Pu IS periodSum / periodCount.
    IF amplitude <= 0 OR Pu <= 0 { RETURN noTuning. }

    LOCAL Ku IS (4 * relayAmplitude) / (CONSTANT:PI * amplitude).
    IF axisState["reversed"] { SET Ku TO -Ku. }

    // Tyreus-Luyben rule
    LOCAL kp IS Ku / 2.2.
    LOCAL ti IS 2.2 * Pu.
    LOCAL td IS Pu / 6.3.
    RETURN LEXICON("Ku", Ku, "Pu", Pu, "kp", kp, "ki", kp / ti, "kd", kp * td).
}

// linearRegression
// Inputs:
//   samples (List of Lexicon("t","pos"), both Scalar) - data points to
//        fit; needs at least 2 elements for a non-degenerate result.
// Outputs:
//   Lexicon with "slope" (Scalar) and "intercept" (Scalar) of the
//   least-squares line pos = slope*t + intercept. Both 0 if samples has
//   fewer than 2 elements or all "t" values are identical.
// Side Effects:
//   None.
FUNCTION linearRegression {
    PARAMETER samples.

    LOCAL n IS samples:LENGTH.
    IF n < 2 { RETURN LEXICON("slope", 0, "intercept", 0). }

    LOCAL sumT IS 0. LOCAL sumPos IS 0. LOCAL sumTT IS 0. LOCAL sumTPos IS 0.
    FOR s IN samples {
        SET sumT TO sumT + s["t"].
        SET sumPos TO sumPos + s["pos"].
        SET sumTT TO sumTT + s["t"]^2.
        SET sumTPos TO sumTPos + s["t"] * s["pos"].
    }

    LOCAL denom IS n * sumTT - sumT^2.
    IF denom = 0 { RETURN LEXICON("slope", 0, "intercept", sumPos / n). }

    LOCAL slope IS (n * sumTPos - sumT * sumPos) / denom.
    LOCAL intercept IS (sumPos - slope * sumT) / n.
    RETURN LEXICON("slope", slope, "intercept", intercept).
}

// computeAxisIntegratingTuning
// Inputs:
//   samples (List of Lexicon("t","pos"), both Scalar) - process-value
//        samples recorded during the step hold; "t" is seconds since the
//        step was applied. Needs at least 4 elements.
//   pos0 (Scalar) - process value at the moment the step was applied.
//   preSlope (Scalar) - process value's slope measured just before the
//        step.
//   stepAmplitude (Scalar, non-zero) - size of the output step applied.
//   holdDuration (Scalar, seconds, > 0) - length of the step hold.
//   regressionFraction (Scalar, range (0, 1]) - trailing fraction of
//        holdDuration used to fit the final-slope line.
// Outputs:
//   Lexicon with "KpProcess" (Scalar, integrating process gain), "Td"
//   (Scalar, dead time in seconds, clamped to [0, holdDuration]), and
//   "success" (Boolean). On failure (too few samples, stepAmplitude = 0,
//   or a zero resulting KpProcess), returns KpProcess = 0, Td = 0,
//   success = FALSE.
// Side Effects:
//   None.
FUNCTION computeAxisIntegratingTuning {
    PARAMETER samples.
    PARAMETER pos0.
    PARAMETER preSlope.
    PARAMETER stepAmplitude.
    PARAMETER holdDuration.
    PARAMETER regressionFraction.

    LOCAL fail IS LEXICON("KpProcess", 0, "Td", 0, "success", FALSE).
    IF samples:LENGTH < 4 OR stepAmplitude = 0 { RETURN fail. }

    LOCAL windowStart IS holdDuration * (1 - regressionFraction).
    LOCAL finalSamples IS LIST().
    FOR s IN samples {
        IF s["t"] >= windowStart { finalSamples:ADD(s). }
    }
    IF finalSamples:LENGTH < 2 { RETURN fail. }

    LOCAL fit IS linearRegression(finalSamples).
    LOCAL finalSlope IS fit["slope"].
    LOCAL finalIntercept IS fit["intercept"].

    LOCAL KpProcess IS (finalSlope - preSlope) / stepAmplitude.

    LOCAL Td IS 0.
    LOCAL slopeDiff IS preSlope - finalSlope.
    IF ABS(slopeDiff) > 0.00001 {
        SET Td TO (finalIntercept - pos0) / slopeDiff.
    }
    IF Td < 0 { SET Td TO 0. }
    IF Td > holdDuration { SET Td TO holdDuration. }

    IF KpProcess = 0 { RETURN fail. }

    RETURN LEXICON("KpProcess", KpProcess, "Td", Td, "success", TRUE).
}

// computeIntegratingGains
// Inputs:
//   KpProcess (Scalar, non-zero) - integrating process gain, from
//        computeAxisIntegratingTuning().
//   Td (Scalar, seconds, >= 0) - process dead time.
//   lambda (Scalar, seconds, > 0) - desired closed-loop response time.
// Outputs:
//   Lexicon with "kp" (Scalar, controller gain, always >= 0), "ki"
//   (Scalar, kp / (2*lambda + Td)), "kd" (Scalar, always 0). Returns all
//   zero if KpProcess is 0.
// Side Effects:
//   None.
FUNCTION computeIntegratingGains {
    PARAMETER KpProcess.
    PARAMETER Td.
    PARAMETER lambda.

    LOCAL denom IS ABS(KpProcess) * (lambda + Td)^2.
    IF KpProcess = 0 OR denom = 0 { RETURN LEXICON("kp", 0, "ki", 0, "kd", 0). }

    LOCAL kc IS (2 * lambda + Td) / denom.
    LOCAL ti IS 2 * lambda + Td.
    RETURN LEXICON("kp", kc, "ki", kc / ti, "kd", 0).
}

// computeRequiredLambda
// Inputs:
//   KpProcess (Scalar) - integrating process gain, from
//        computeAxisIntegratingTuning().
//   Td (Scalar, seconds, >= 0) - process dead time.
//   apd (Scalar, > 0) - allowable process deviation for the maximum load
//        disturbance below.
//   mld (Scalar) - maximum load disturbance, same units as the
//        controller output.
//   minLambdaFactor (Scalar, default 3) - floor on the returned lambda,
//        expressed as a multiple of Td.
// Outputs:
//   Scalar - lambda (seconds) that would make computeIntegratingGains()'s
//   resulting controller gain equal MLD/APD, clamped to at least
//   minLambdaFactor * Td. Falls back to minLambdaFactor * Td if
//   KpProcess = 0, apd <= 0, or no valid positive root exists.
// Side Effects:
//   None.
FUNCTION computeRequiredLambda {
    PARAMETER KpProcess.
    PARAMETER Td.
    PARAMETER apd.
    PARAMETER mld.
    PARAMETER minLambdaFactor IS 3.

    LOCAL minLambda IS minLambdaFactor * Td.
    IF KpProcess = 0 OR apd <= 0 { RETURN minLambda. }

    LOCAL a IS ABS(KpProcess) * mld.
    IF a = 0 { RETURN minLambda. }
    LOCAL b IS 2 * a * Td - 2 * apd.
    LOCAL c IS a * Td^2 - apd * Td.
    LOCAL disc IS b^2 - 4 * a * c.
    IF disc < 0 { RETURN minLambda. }

    LOCAL sqrtDisc IS SQRT(disc).
    LOCAL lambda1 IS (-b + sqrtDisc) / (2 * a).
    LOCAL lambda2 IS (-b - sqrtDisc) / (2 * a).
    LOCAL lambda IS MAX(lambda1, lambda2).

    IF lambda < minLambda { SET lambda TO minLambda. }
    RETURN lambda.
}

// PIDIgnoreTick
// Inputs:
//   stageLabel (String) - the current stage label; ignored.
// Outputs:
//   None.
// Side Effects:
//   None. Default for the onTick parameter of the autotune and cascade functions.
FUNCTION PIDIgnoreTick {
    PARAMETER stageLabel.
}

// PIDPrintMessage
// Inputs:
//   message (String) - one line of status, warning or error text.
// Outputs:
//   None.
// Side Effects:
//   PRINTs message. Default for the onMessage parameter of the autotune functions.
FUNCTION PIDPrintMessage {
    PARAMETER message.
    PRINT message.
}

// PIDAllRelaysDone
// Inputs:
//   axisStates (LIST of Lexicon) - relay-test states from makeAxisRelayState().
// Outputs:
//   Boolean - TRUE if every state's "done" is TRUE.
// Side Effects:
//   None.
FUNCTION PIDAllRelaysDone {
    PARAMETER axisStates.

    FOR axisState IN axisStates {
        IF NOT axisState["done"] { RETURN FALSE. }
    }
    RETURN TRUE.
}

// autotuneWithRetry
// Inputs:
//   runTest (Delegate, () -> Lexicon) - runs one whole autotune attempt and returns its result Lexicon.
//   coefficientName (String) - key in the result Lexicon holding the LIST of measured coefficients ("Ku" or "KpProcess"); a zero
//        element on any axis counts as a failure.
//   axes (LIST of axes) - the axes the test tunes; a zero Kp on any axis after the attempt also counts as a failure.
//   stageLabel (String) - label used in the messages.
//   maxAttempts (Scalar, integer) - number of attempts before giving up.
//   failureHint (String) - what to check, appended to the final error message.
//   onMessage (Delegate, (String) -> None) - receives the warning after each failed attempt and the error after the last one.
// Outputs:
//   Lexicon - the last attempt's result, plus "success" (Boolean), TRUE unless every attempt failed.
// Side Effects:
//   Whatever runTest does, once per attempt.
FUNCTION autotuneWithRetry {
    PARAMETER runTest.
    PARAMETER coefficientName.
    PARAMETER axes.
    PARAMETER stageLabel.
    PARAMETER maxAttempts.
    PARAMETER failureHint.
    PARAMETER onMessage.

    LOCAL attempt IS 1.
    LOCAL result IS LEXICON(coefficientName, LIST()).

    UNTIL attempt > maxAttempts {
        SET result TO runTest().

        LOCAL coefficients IS result[coefficientName].
        LOCAL gains IS PIDAxesGetGains(axes).
        LOCAL failed IS PIDAnyZero(coefficients) OR PIDAnyZero(gains["kp"]).

        IF NOT failed {
            SET result["success"] TO TRUE.
            RETURN result.
        }

        onMessage("  WARNING: '" + stageLabel + "' autotune attempt " + attempt + "/" + maxAttempts +
              " produced a zero coefficient (" + coefficientName + "=" + PIDFormatList(coefficients, 4) + "). Retrying...").
        SET attempt TO attempt + 1.
    }

    onMessage("  ERROR: '" + stageLabel + "' autotune still produced a zero coefficient after " +
          maxAttempts + " attempts. " + failureHint).
    SET result["success"] TO FALSE.
    RETURN result.
}

// applyViaInnerLoop
// Inputs:
//   innerAxes (LIST of axes) - the inner (velocity) loop.
//   innerActuator (Delegate, (LIST effortList, LIST limitsList) -> None) - applies the computed effort to the plant.
//   maxInnerCVfn (Delegate, () -> LIST) - returns the current per-axis output limit.
//   innerValueGetter (Delegate, () -> LIST) - returns the current inner process value.
//   setpoints (LIST of Scalar) - commanded inner (velocity) setpoint of each axis.
// Outputs:
//   None.
// Side Effects:
//   Sets the inner loop's setpoints and output limits, advances its internal state by one UPDATE() step, and calls
//   innerActuator() with the resulting effort.
FUNCTION applyViaInnerLoop {
    PARAMETER innerAxes.
    PARAMETER innerActuator.
    PARAMETER maxInnerCVfn.
    PARAMETER innerValueGetter.
    PARAMETER setpoints.

    PIDAxesSetSetpoints(innerAxes, setpoints).

    LOCAL currentInner IS innerValueGetter().
    LOCAL maxInnerCV IS maxInnerCVfn().
    PIDAxesSetLimits(innerAxes, PIDListScale(maxInnerCV, -1), maxInnerCV).

    LOCAL effort IS PIDAxesUpdate(innerAxes, TIME:SECONDS, currentInner).
    innerActuator(effort, maxInnerCV).
}

// PIDRelayAutotune
// Inputs:
//   axes (LIST of axes) - the axes to tune; each one's "tune" and gains are overwritten. All of them are tested at the same
//        time, so one axis works the same way as three.
//   getValues (Delegate, () -> LIST) - reads the current process value of each axis.
//   applyOutputs (Delegate, (LIST) -> None) - applies a commanded output to the plant, one element per axis.
//   setpoints (LIST of Scalar) - relay test target value of each axis.
//   relayAmplitudes (LIST of Scalar, all > 0) - relay output magnitude of each axis.
//   stageLabel (String) - label passed to onTick and used in printed warnings.
//   hysteresis (LIST of Scalar, all >= 0, default LIST() meaning 0 on every axis) - per-axis relay hysteresis.
//   settleCycles (Scalar, integer, default 2) - leading oscillation cycles discarded before measuring.
//   measureCycles (Scalar, integer, default 4) - oscillation cycles used to measure Ku/Pu after settling.
//   maxDuration (Scalar, seconds, default 90) - time limit for the test.
//   onTick (Delegate, (String stageLabel) -> None, default PIDIgnoreTick) - called once per loop iteration, for display and
//        logging.
//   onMessage (Delegate, (String) -> None, default PIDPrintMessage) - receives the time-out warning.
// Outputs:
//   Lexicon with:
//     "Ku" (LIST) - measured ultimate gain of each axis.
//     "Pu" (LIST) - measured ultimate period of each axis, seconds.
//     "axisTuning" (LIST of Lexicon) - the full computeAxisTuningRelay() result of each axis.
// Side Effects:
//   Sets the axes' setpoints, "tune", Kp, Ki and Kd. Repeatedly calls applyOutputs() and onTick(stageLabel) until all axes' relay
//   tests finish or maxDuration elapses; applies all zeros before returning. Calls onMessage with a warning if the test times out
//   before converging.
FUNCTION PIDRelayAutotune {
    PARAMETER axes.
    PARAMETER getValues.
    PARAMETER applyOutputs.
    PARAMETER setpoints.
    PARAMETER relayAmplitudes.
    PARAMETER stageLabel.
    PARAMETER hysteresis IS LIST().
    PARAMETER settleCycles IS 2.
    PARAMETER measureCycles IS 4.
    PARAMETER maxDuration IS 90.
    PARAMETER onTick IS PIDIgnoreTick@.
    PARAMETER onMessage IS PIDPrintMessage@.

    LOCAL axisCount IS axes:LENGTH.
    LOCAL zeros IS PIDFilledList(axisCount, 0).
    IF hysteresis:LENGTH = 0 { SET hysteresis TO zeros. }

    PIDAxesSetSetpoints(axes, setpoints).

    LOCAL neededPoints IS (settleCycles + measureCycles) * 2.
    LOCAL initial IS getValues().

    LOCAL axisStates IS LIST().
    LOCAL i IS 0.
    UNTIL i >= axisCount {
        axisStates:ADD(makeAxisRelayState(initial[i], neededPoints, settleCycles)).
        SET i TO i + 1.
    }

    // A short kick at full relay amplitude shows which way each axis moves in response to a positive output, so an axis that is
    // wired backwards is marked "reversed" and the relay drives it the right way round.
    LOCAL reversalKickHoldTime IS 0.5.
    LOCAL reversalKickEpsilon IS 0.01.
    LOCAL kickStartTime IS TIME:SECONDS.
    UNTIL TIME:SECONDS - kickStartTime >= reversalKickHoldTime {
        applyOutputs(relayAmplitudes).
        WAIT 0.
    }
    applyOutputs(zeros).
    LOCAL afterInitial IS getValues().
    SET i TO 0.
    UNTIL i >= axisCount {
        LOCAL initialDelta IS afterInitial[i] - initial[i].
        SET axisStates[i]["rising"] TO initialDelta > 0.
        SET axisStates[i]["reversed"] TO initialDelta < -reversalKickEpsilon.
        SET i TO i + 1.
    }

    LOCAL startTime IS TIME:SECONDS.

    UNTIL PIDAllRelaysDone(axisStates) OR (TIME:SECONDS - startTime > maxDuration) {
        LOCAL values IS getValues().

        LOCAL outputs IS LIST().
        SET i TO 0.
        UNTIL i >= axisCount {
            LOCAL relaySign IS tickAxisRelay(axisStates[i], values[i], setpoints[i], hysteresis[i]).
            outputs:ADD(relaySign * relayAmplitudes[i]).
            SET i TO i + 1.
        }
        applyOutputs(outputs).

        onTick(stageLabel).

        WAIT 0.
    }

    applyOutputs(zeros).

    IF NOT PIDAllRelaysDone(axisStates) {
        onMessage("WARNING: '" + stageLabel + "' relay autotune hit its " + timeToString(maxDuration) + " time limit before converging on all axes.").
    }

    LOCAL kuList IS LIST().
    LOCAL puList IS LIST().
    LOCAL kps IS LIST().
    LOCAL kis IS LIST().
    LOCAL kds IS LIST().
    LOCAL axisTuning IS LIST().
    SET i TO 0.
    UNTIL i >= axisCount {
        LOCAL tuning IS computeAxisTuningRelay(axisStates[i], relayAmplitudes[i]).
        SET axes[i]["tune"] TO LEXICON("Ku", tuning["Ku"], "Pu", tuning["Pu"]).
        axisTuning:ADD(tuning).
        kuList:ADD(tuning["Ku"]).
        puList:ADD(tuning["Pu"]).
        kps:ADD(tuning["kp"]).
        kis:ADD(tuning["ki"]).
        kds:ADD(tuning["kd"]).
        SET i TO i + 1.
    }
    PIDAxesSetGains(axes, kps, kis, kds).

    RETURN LEXICON("Ku", kuList, "Pu", puList, "axisTuning", axisTuning).
}

// PIDRelayAutotuneRetry
// Inputs:
//   axes, getValues, applyOutputs, setpoints, relayAmplitudes, stageLabel, hysteresis, settleCycles, measureCycles, maxDuration - see
//        PIDRelayAutotune(); setpoints is ignored if setpointIsRelative is TRUE.
//   maxAttempts (Scalar, integer, default 3) - number of times to retry the whole test if any axis comes back with a zero Ku or Kp.
//   setpointIsRelative (Boolean, default FALSE) - if TRUE, the setpoints for each attempt are re-read from getValues() (the
//        current process values) instead of using setpoints.
//   onTick - see PIDRelayAutotune().
//   onMessage (Delegate, (String) -> None, default PIDPrintMessage) - see PIDRelayAutotune(); also receives the retry warnings and
//        the final error.
// Outputs:
//   Lexicon - same as PIDRelayAutotune(), plus "success" (Boolean), TRUE unless every attempt produced a zero Ku/Kp on at least
//   one axis.
// Side Effects:
//   Same as PIDRelayAutotune(), repeated once per attempt. Calls onMessage with a warning after each failed attempt and an error
//   after the last one.
FUNCTION PIDRelayAutotuneRetry {
    PARAMETER axes.
    PARAMETER getValues.
    PARAMETER applyOutputs.
    PARAMETER setpoints.
    PARAMETER relayAmplitudes.
    PARAMETER stageLabel.
    PARAMETER hysteresis IS LIST().
    PARAMETER settleCycles IS 2.
    PARAMETER measureCycles IS 4.
    PARAMETER maxDuration IS 90.
    PARAMETER maxAttempts IS 3.
    PARAMETER setpointIsRelative IS FALSE.
    PARAMETER onTick IS PIDIgnoreTick@.
    PARAMETER onMessage IS PIDPrintMessage@.

    LOCAL runTest IS {
        LOCAL attemptSetpoints IS setpoints.
        IF setpointIsRelative { SET attemptSetpoints TO getValues(). }
        RETURN PIDRelayAutotune(axes, getValues, applyOutputs, attemptSetpoints, relayAmplitudes, stageLabel, hysteresis, settleCycles, measureCycles, maxDuration, onTick, onMessage).
    }.

    RETURN autotuneWithRetry(runTest, "Ku", axes, stageLabel, maxAttempts, "Check RCS thruster availability/orientation and relay amplitude.", onMessage).
}

// PIDIntegratingStepTest
// Inputs:
//   axes (LIST of axes) - the axes to tune; each one's "tune" and gains are overwritten with the computed lambda tuning.
//   getValues (Delegate, () -> LIST) - reads the current process value (position) of each axis.
//   innerActuator (Delegate, (LIST setpoints) -> None) - commands the inner loop's setpoint, one element per axis.
//   stepAmplitudes (LIST of Scalar, non-zero) - velocity-setpoint step commanded on each axis during the hold, m/s.
//   stageLabel (String) - label passed to onTick, with " (settle)" or " (step)" appended.
//   preSettleDuration (Scalar, seconds, default 3) - time to hold zero output before the step, to measure the process value's
//        baseline slope.
//   holdDuration (Scalar, seconds, default 20) - time to hold the step.
//   regressionFraction (Scalar, range (0, 1], default 0.5) - see computeAxisIntegratingTuning().
//   lambdaFactor (Scalar, default 3) - if useCustomLambda is FALSE, lambda = lambdaFactor * Td; if useCustomLambda is TRUE, passed
//        through as computeRequiredLambda()'s minLambdaFactor.
//   lambdaMin (Scalar, seconds, default 1) - floor on lambda; only used if useCustomLambda is FALSE.
//   useCustomLambda (Boolean, default FALSE) - if TRUE, lambda is derived per axis from customAPD/customMLD via
//        computeRequiredLambda() instead of from lambdaFactor/lambdaMin.
//   customAPD (Scalar, > 0, default 0) - allowable process deviation; see computeRequiredLambda(). Only used if useCustomLambda
//        is TRUE.
//   customMLD (Scalar, default 0) - maximum load disturbance; see computeRequiredLambda(). Only used if useCustomLambda is TRUE.
//   onTick (Delegate, (String stageLabel) -> None, default PIDIgnoreTick) - called once per loop iteration, for display and
//        logging.
// Outputs:
//   Lexicon with "KpProcess" (LIST), "Td" (LIST, seconds), "lambda" (LIST, seconds), and "axisTuning" (LIST of Lexicon, each the
//   computeAxisIntegratingTuning() result for that axis).
// Side Effects:
//   Sets the axes' "tune", Kp, Ki and Kd. Repeatedly calls innerActuator() and onTick() during the pre-settle and hold phases, with
//   the label stageLabel + " (settle)" then stageLabel + " (step)"; applies all zeros before returning.
FUNCTION PIDIntegratingStepTest {
    PARAMETER axes.
    PARAMETER getValues.
    PARAMETER innerActuator.
    PARAMETER stepAmplitudes.
    PARAMETER stageLabel.
    PARAMETER preSettleDuration IS 3.
    PARAMETER holdDuration IS 20.
    PARAMETER regressionFraction IS 0.5.
    PARAMETER lambdaFactor IS 3.
    PARAMETER lambdaMin IS 1.
    PARAMETER useCustomLambda IS FALSE.
    PARAMETER customAPD IS 0.
    PARAMETER customMLD IS 0.
    PARAMETER onTick IS PIDIgnoreTick@.

    LOCAL axisCount IS axes:LENGTH.
    LOCAL zeros IS PIDFilledList(axisCount, 0).

    LOCAL preSamples IS LIST().
    LOCAL holdSamples IS LIST().
    LOCAL i IS 0.
    UNTIL i >= axisCount {
        preSamples:ADD(LIST()).
        holdSamples:ADD(LIST()).
        SET i TO i + 1.
    }

    LOCAL settleStart IS TIME:SECONDS.
    UNTIL TIME:SECONDS - settleStart >= preSettleDuration {
        innerActuator(zeros).
        LOCAL valuesNow IS getValues().
        SET i TO 0.
        UNTIL i >= axisCount {
            preSamples[i]:ADD(LEXICON("t", TIME:SECONDS, "pos", valuesNow[i])).
            SET i TO i + 1.
        }
        onTick(stageLabel + " (settle)").
        WAIT 0.
    }

    LOCAL preSlopes IS LIST().
    FOR samples IN preSamples {
        LOCAL fit IS linearRegression(samples).
        preSlopes:ADD(fit["slope"]).
    }

    LOCAL pos0 IS getValues().
    LOCAL t0 IS TIME:SECONDS.

    UNTIL TIME:SECONDS - t0 >= holdDuration {
        innerActuator(stepAmplitudes).
        LOCAL t IS TIME:SECONDS - t0.
        LOCAL valuesHold IS getValues().
        SET i TO 0.
        UNTIL i >= axisCount {
            holdSamples[i]:ADD(LEXICON("t", t, "pos", valuesHold[i])).
            SET i TO i + 1.
        }
        onTick(stageLabel + " (step)").
        WAIT 0.
    }

    innerActuator(zeros).

    LOCAL axisTuning IS LIST().
    LOCAL kpProcessList IS LIST().
    LOCAL tdList IS LIST().
    LOCAL lambdaList IS LIST().
    LOCAL kps IS LIST().
    LOCAL kis IS LIST().
    LOCAL kds IS LIST().
    SET i TO 0.
    UNTIL i >= axisCount {
        LOCAL axisResult IS computeAxisIntegratingTuning(holdSamples[i], pos0[i], preSlopes[i], stepAmplitudes[i], holdDuration, regressionFraction).
        LOCAL axisLambda IS MAX(lambdaFactor * axisResult["Td"], lambdaMin).
        IF useCustomLambda { SET axisLambda TO computeRequiredLambda(axisResult["KpProcess"], axisResult["Td"], customAPD, customMLD, lambdaFactor). }
        LOCAL gains IS computeIntegratingGains(axisResult["KpProcess"], axisResult["Td"], axisLambda).
        axisTuning:ADD(axisResult).
        kpProcessList:ADD(axisResult["KpProcess"]).
        tdList:ADD(axisResult["Td"]).
        lambdaList:ADD(axisLambda).
        kps:ADD(gains["kp"]).
        kis:ADD(gains["ki"]).
        kds:ADD(gains["kd"]).
        SET axes[i]["tune"] TO PIDEmptyTuning().
        SET i TO i + 1.
    }
    PIDAxesSetGains(axes, kps, kis, kds).

    RETURN LEXICON(
        "KpProcess", kpProcessList,
        "Td", tdList,
        "lambda", lambdaList,
        "axisTuning", axisTuning
    ).
}

// PIDIntegratingAutotuneRetry
// Inputs:
//   axes, getValues, innerActuator, stepAmplitudes, stageLabel, preSettleDuration, holdDuration, regressionFraction, lambdaFactor,
//        lambdaMin - see PIDIntegratingStepTest().
//   maxAttempts (Scalar, integer, default 3) - number of times to retry the whole test if any axis comes back with a zero
//        KpProcess or Kp.
//   useCustomLambda, customAPD, customMLD, onTick - see PIDIntegratingStepTest().
//   onMessage (Delegate, (String) -> None, default PIDPrintMessage) - receives the retry warnings and the final error.
// Outputs:
//   Lexicon - same as PIDIntegratingStepTest(), plus "success" (Boolean), TRUE unless every attempt produced a zero KpProcess/Kp
//   on at least one axis.
// Side Effects:
//   Same as PIDIntegratingStepTest(), repeated once per attempt. Calls onMessage with a warning after each failed attempt and an
//   error after the last one.
FUNCTION PIDIntegratingAutotuneRetry {
    PARAMETER axes.
    PARAMETER getValues.
    PARAMETER innerActuator.
    PARAMETER stepAmplitudes.
    PARAMETER stageLabel.
    PARAMETER preSettleDuration IS 3.
    PARAMETER holdDuration IS 20.
    PARAMETER regressionFraction IS 0.5.
    PARAMETER lambdaFactor IS 3.
    PARAMETER lambdaMin IS 1.
    PARAMETER maxAttempts IS 3.
    PARAMETER useCustomLambda IS FALSE.
    PARAMETER customAPD IS 0.
    PARAMETER customMLD IS 0.
    PARAMETER onTick IS PIDIgnoreTick@.
    PARAMETER onMessage IS PIDPrintMessage@.

    LOCAL runTest IS {
        RETURN PIDIntegratingStepTest(axes, getValues, innerActuator, stepAmplitudes, stageLabel, preSettleDuration, holdDuration, regressionFraction, lambdaFactor, lambdaMin, useCustomLambda, customAPD, customMLD, onTick).
    }.

    RETURN autotuneWithRetry(runTest, "KpProcess", axes, stageLabel, maxAttempts, "Check RCS thruster availability/orientation and step amplitude.", onMessage).
}

// PIDLimitByBraking
// Inputs:
//   demands (LIST of Scalar) - the velocity each axis is being asked for, for example the output of a position loop.
//   errors (LIST of Scalar) - how far each axis still has to go (setpoint minus value), the same units as the demand's distance.
//   brakingAccels (LIST of Scalar, each >= 0) - the deceleration the ship can be counted on for on each axis.
// Outputs:
//   A new LIST of the demands, each limited to +/- SQRT(2 * a * ABS(error)). That is the fastest speed from which braking at a
//   still stops exactly at the setpoint, so a demand below it (for example near the setpoint, where a position loop asks for
//   little) is left alone, and one above it (far away, where a position loop asks for more than the ship can stop from) is cut.
// Side Effects:
//   None.
FUNCTION PIDLimitByBraking {
    PARAMETER demands.
    PARAMETER errors.
    PARAMETER brakingAccels.

    LOCAL limited IS LIST().
    LOCAL i IS 0.
    UNTIL i >= demands:LENGTH {
        LOCAL safeSpeed IS SQRT(2 * MAX(brakingAccels[i], 0) * ABS(errors[i])).
        limited:ADD(MAX(-safeSpeed, MIN(safeSpeed, demands[i]))).
        SET i TO i + 1.
    }
    RETURN limited.
}

// cascadeStep
// Inputs:
//   outerAxes (LIST of axes) - the outer (position) loop; its output is the inner loop's setpoint.
//   innerAxes (LIST of axes) - the inner (velocity) loop.
//   outerPV (LIST of Scalar) - current outer process value of each axis.
//   innerPV (LIST of Scalar) - current inner process value of each axis.
//   outerSP (LIST of Scalar) - outer-loop setpoint of each axis.
//   innerLimits (LIST of Scalar) - output limit of each inner axis, applied as +/- on each, and passed to innerActuator.
//   innerActuator (Delegate, (LIST effortList, LIST limitsList) -> None) - applies the computed effort to the plant.
//   outerLimits (LIST of Scalar, default LIST()) - output limit of each outer axis, applied as +/- on each. An empty LIST leaves
//        the outer loop's existing limits unchanged.
//   brakingAccels (LIST of Scalar, default LIST()) - if not empty, the deceleration the ship can be counted on for on each axis. The
//        outer loop's output is then also limited, with PIDLimitByBraking(), to the speed from which braking at that rate stops
//        at the setpoint. An empty LIST applies no such limit.
//   integralWindows (LIST of Scalar, default LIST()) - if not empty, how close to the setpoint each axis must be, in the units of the
//        outer process value, before its integral term is allowed to build up. Further out the outer loop's integral is cleared
//        every step, so it cannot wind up during a long move and carry the axis past the setpoint. An empty LIST leaves the
//        integral alone.
//   positionAxes (LIST of Boolean, default LIST()) - if not empty, TRUE for each axis that the outer loop controls. On an axis that
//        is FALSE, outerSP is not a setpoint for the outer loop but the inner loop's own setpoint (a velocity, for a position
//        loop over a velocity loop), limited to +/- outerLimits if that is given, and the outer loop is cleared each step so it is
//        fresh when the axis goes back to it. That lets some axes hold a position while another moves at a set speed. An empty
//        LIST means that the outer loop controls every axis.
// Outputs:
//   LIST of Scalar - the effort that was passed to innerActuator.
// Side Effects:
//   Sets the setpoint of the outer loop and the setpoint and output limits of the inner loop (and the outer loop's output limits,
//   if outerLimits is not empty), advances each loop's internal state by one UPDATE() step, and calls innerActuator() once. Does
//   not wait, so the caller sets the pace.
FUNCTION cascadeStep {
    PARAMETER outerAxes.
    PARAMETER innerAxes.
    PARAMETER outerPV.
    PARAMETER innerPV.
    PARAMETER outerSP.
    PARAMETER innerLimits.
    PARAMETER innerActuator.
    PARAMETER outerLimits IS LIST().
    PARAMETER brakingAccels IS LIST().
    PARAMETER integralWindows IS LIST().
    PARAMETER positionAxes IS LIST().

    PIDAxesSetSetpoints(outerAxes, outerSP).
    IF outerLimits:LENGTH > 0 {
        PIDAxesSetLimits(outerAxes, PIDListScale(outerLimits, -1), outerLimits).
    }

    // integral action only helps close to the setpoint; during a long move it would only wind up
    IF integralWindows:LENGTH > 0 {
        LOCAL j IS 0.
        UNTIL j >= outerAxes:LENGTH {
            IF ABS(outerSP[j] - outerPV[j]) > integralWindows[j] { outerAxes[j]["PID"]:RESET(). }
            SET j TO j + 1.
        }
    }

    LOCAL innerSetpoints IS PIDAxesUpdate(outerAxes, TIME:SECONDS, outerPV).

    IF brakingAccels:LENGTH > 0 {
        LOCAL errors IS LIST().
        LOCAL i IS 0.
        UNTIL i >= outerSP:LENGTH {
            errors:ADD(outerSP[i] - outerPV[i]).
            SET i TO i + 1.
        }
        SET innerSetpoints TO PIDLimitByBraking(innerSetpoints, errors, brakingAccels).
    }

    // the axes that the outer loop does not control go straight to the inner loop
    IF positionAxes:LENGTH > 0 {
        LOCAL k IS 0.
        UNTIL k >= outerAxes:LENGTH {
            IF NOT positionAxes[k] {
                LOCAL directSetpoint IS outerSP[k].
                IF outerLimits:LENGTH > 0 { SET directSetpoint TO MAX(-outerLimits[k], MIN(outerLimits[k], directSetpoint)). }
                SET innerSetpoints[k] TO directSetpoint.
                outerAxes[k]["PID"]:RESET().
            }
            SET k TO k + 1.
        }
    }

    PIDAxesSetSetpoints(innerAxes, innerSetpoints).
    PIDAxesSetLimits(innerAxes, PIDListScale(innerLimits, -1), innerLimits).
    LOCAL effort IS PIDAxesUpdate(innerAxes, TIME:SECONDS, innerPV).
    innerActuator(effort, innerLimits).
    RETURN effort.
}

// runCascadedPIDLoop
// Inputs:
//   outerAxes (LIST of axes) - the outer loop.
//   innerAxes (LIST of axes) - the inner loop.
//   innerActuator (Delegate, (LIST effortList, LIST limitsList) -> None) - applies the computed effort to the plant.
//   getInnerCVLimits (Delegate, () -> LIST) - returns the current per-axis inner-loop output limit.
//   getInnerPVFn (Delegate, () -> LIST) - reads the current inner process value.
//   getOuterPVFn (Delegate, () -> LIST) - reads the current outer process value.
//   outerSP (LIST of Scalar) - outer-loop setpoint.
//   stageLabel (String) - label passed to onTick.
//   maxDuration (Scalar, seconds) - time limit for the run.
//   settleConfirmDuration (Scalar, seconds) - time both tolerances must hold continuously before the run is considered settled.
//   outerTolerance (Scalar, >= 0) - maximum outer-loop error magnitude counted as settled.
//   innerTolerance (Scalar, >= 0) - maximum inner-loop value magnitude counted as settled.
//   onTick (Delegate, (String stageLabel) -> None, default PIDIgnoreTick) - called once per loop iteration, for display and
//        logging.
// Outputs:
//   Boolean - TRUE if the run settled within maxDuration, FALSE if it timed out first.
// Side Effects:
//   Resets and re-targets both loops. Repeatedly calls cascadeStep() (so innerActuator()) and onTick(stageLabel) until settled or
//   maxDuration elapses; calls innerActuator(zeros, getInnerCVLimits()) before returning.
FUNCTION runCascadedPIDLoop {
    PARAMETER outerAxes.
    PARAMETER innerAxes.
    PARAMETER innerActuator.
    PARAMETER getInnerCVLimits.
    PARAMETER getInnerPVFn.
    PARAMETER getOuterPVFn.
    PARAMETER outerSP.
    PARAMETER stageLabel.
    PARAMETER maxDuration.
    PARAMETER settleConfirmDuration.
    PARAMETER outerTolerance.
    PARAMETER innerTolerance.
    PARAMETER onTick IS PIDIgnoreTick@.

    PIDAxesReset(outerAxes).
    PIDAxesReset(innerAxes).

    LOCAL zeros IS PIDFilledList(innerAxes:LENGTH, 0).
    LOCAL startTime IS TIME:SECONDS.
    LOCAL settledSince IS -1.

    UNTIL (settledSince >= 0 AND (TIME:SECONDS - startTime - settledSince) >= settleConfirmDuration)
       OR (TIME:SECONDS - startTime > maxDuration) {
        LOCAL elapsedTime IS TIME:SECONDS - startTime.
        LOCAL innerNow IS getInnerPVFn().
        LOCAL outerNow IS getOuterPVFn().

        cascadeStep(outerAxes, innerAxes, outerNow, innerNow, outerSP, getInnerCVLimits(), innerActuator).

        LOCAL outerErrMag IS PIDListDistance(outerNow, outerSP).
        LOCAL innerMag IS PIDListDistance(innerNow, zeros).
        IF outerErrMag <= outerTolerance AND innerMag <= innerTolerance {
            IF settledSince < 0 { SET settledSince TO elapsedTime. }
        } ELSE {
            SET settledSince TO -1.
        }

        onTick(stageLabel).

        WAIT 0.
    }

    innerActuator(zeros, getInnerCVLimits()).
    RETURN settledSince >= 0.
}

// vectorGetterAsList
// Inputs:
//   vectorGetter (Delegate, () -> Vector) - reads a value as a vector, for example getRelativeVelocity@.
// Outputs:
//   Delegate, () -> LIST - the same reading as a LIST of X, Y, Z, for the getValues parameters in this library.
// Side Effects:
//   None.
FUNCTION vectorGetterAsList {
    PARAMETER vectorGetter.
    RETURN { RETURN vectorToList(vectorGetter()). }.
}

// vectorActuatorAsList
// Inputs:
//   vectorActuator (Delegate, (Vector) -> None) - applies a vector to the plant, for example applyPlantEffort@.
// Outputs:
//   Delegate, (LIST) -> None - applies a LIST of X, Y, Z by converting it to a vector, for the applyOutputs and innerActuator
//   parameters in this library.
// Side Effects:
//   None.
FUNCTION vectorActuatorAsList {
    PARAMETER vectorActuator.
    RETURN { PARAMETER values. vectorActuator(listToVector(values)). }.
}

// vectorActuatorWithLimitsAsList
// Inputs:
//   vectorActuator (Delegate, (Vector effort, Vector limits) -> None) - applies a vector effort, scaled against vector limits,
//        for example applyRCSAccel@.
// Outputs:
//   Delegate, (LIST effort, LIST limits) -> None - the same for LISTs, for the innerActuator parameters of applyViaInnerLoop(),
//   cascadeStep() and runCascadedPIDLoop().
// Side Effects:
//   None.
FUNCTION vectorActuatorWithLimitsAsList {
    PARAMETER vectorActuator.
    RETURN { PARAMETER values. PARAMETER limits. vectorActuator(listToVector(values), listToVector(limits)). }.
}
