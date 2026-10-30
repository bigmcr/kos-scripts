LOCAL positionPIDLoop IS vectorPIDConstruct(1, 0, 0, -10, 10).
LOCAL velocityPIDLoop IS vectorPIDConstruct(1, 0, 0, -1, 1).

// vectorPIDConstruct
// Inputs:
//   kp (Scalar, default 1) - proportional gain applied to all three axes.
//   ki (Scalar, default 0) - integral gain applied to all three axes.
//   kd (Scalar, default 0) - derivative gain applied to all three axes.
//   minOutput (Scalar, default -1) - minimum output applied to all three axes.
//   maxOutput (Scalar, default 1) - maximum output applied to all three axes.
// Outputs:
//   Lexicon with keys "X", "Y", "Z", each a PIDLoop structure constructed
//   with the given gains and output limits. Lexicon also includes "XTuning",
//   "YTuning", and "ZTuning" lexicons, each of which contain the tuning
//   parameters for that axis.
// Side Effects:
//   None.
FUNCTION vectorPIDConstruct {
    PARAMETER kp IS 1.
    PARAMETER ki IS 0.
    PARAMETER kd IS 0.
    PARAMETER minOutput IS -1.
    PARAMETER maxOutput IS 1.

    LOCAL vp IS LEXICON().
    SET vp["X"] TO PIDLOOP(kp, ki, kd, minOutput, maxOutput).
    SET vp["Y"] TO PIDLOOP(kp, ki, kd, minOutput, maxOutput).
    SET vp["Z"] TO PIDLOOP(kp, ki, kd, minOutput, maxOutput).
	// Each axis gets its own independent placeholder tuning lexicon (never
	// share one Lexicon object across axes, since Lexicons are references
	// in KerboScript and later per-axis updates would otherwise clobber
	// all three axes at once). Ku/Pu start at 0 (not yet measured) and
	// every preset starts at zero gains until an autotune populates it.
    SET vp["XTune"] TO LEXICON("Ku", 0, "Pu", 0, "tuningSets", LEXICON(
        "classic", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "aggressive", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "conservative", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "criticallyDamped", LEXICON("kp", 0, "ki", 0, "kd", 0))).
    SET vp["YTune"] TO LEXICON("Ku", 0, "Pu", 0, "tuningSets", LEXICON(
        "classic", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "aggressive", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "conservative", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "criticallyDamped", LEXICON("kp", 0, "ki", 0, "kd", 0))).
    SET vp["ZTune"] TO LEXICON("Ku", 0, "Pu", 0, "tuningSets", LEXICON(
        "classic", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "aggressive", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "conservative", LEXICON("kp", 0, "ki", 0, "kd", 0),
        "criticallyDamped", LEXICON("kp", 0, "ki", 0, "kd", 0))).
    RETURN vp.
}

// vectorPIDTuningPresetNames
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct(), whose
//        "XTune"/"YTune"/"ZTune" have been populated by an autotune
//        function (e.g. vectorRelayAutotune() or vectorIntegratingStepTest()).
// Outputs:
//   List of String - the preset names available in vp["XTune"]["tuningSets"]
//   (assumed identical across X/Y/Z, since every axis is populated by the
//   same autotune call). Empty LIST if vp has no tuning data yet.
// Side Effects:
//   None.
FUNCTION vectorPIDTuningPresetNames {
    PARAMETER vp.
    IF NOT vp:KEYS:CONTAINS("XTune") { RETURN LIST(). }
    RETURN vp["XTune"]["tuningSets"]:KEYS.
}

// vectorPIDApplyTuningPreset
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct(), whose
//        "XTune"/"YTune"/"ZTune" have been populated by an autotune
//        function.
//   presetName (String) - key into each axis's "tuningSets" Lexicon (for
//        example "classic", "aggressive", "conservative",
//        "criticallyDamped", or any preset name an integrating-loop
//        autotune has stored).
// Outputs:
//   Boolean - TRUE if presetName existed on all three axes and was
//   applied, FALSE (with vp left unchanged) if it was missing on any
//   axis or vp has not been autotuned yet.
// Side Effects:
//   On success, sets vp's Kp, Ki, Kd (via vectorPIDSetKp/Ki/Kd) to the
//   named preset's per-axis values.
FUNCTION vectorPIDApplyTuningPreset {
    PARAMETER vp.
    PARAMETER presetName.

    IF NOT vp:KEYS:CONTAINS("XTune") { RETURN FALSE. }
    IF NOT vp["XTune"]["tuningSets"]:KEYS:CONTAINS(presetName) { RETURN FALSE. }
    IF NOT vp["YTune"]["tuningSets"]:KEYS:CONTAINS(presetName) { RETURN FALSE. }
    IF NOT vp["ZTune"]["tuningSets"]:KEYS:CONTAINS(presetName) { RETURN FALSE. }

    LOCAL kpVec IS V(vp["XTune"]["tuningSets"][presetName]["kp"],
                      vp["YTune"]["tuningSets"][presetName]["kp"],
                      vp["ZTune"]["tuningSets"][presetName]["kp"]).
    LOCAL kiVec IS V(vp["XTune"]["tuningSets"][presetName]["ki"],
                      vp["YTune"]["tuningSets"][presetName]["ki"],
                      vp["ZTune"]["tuningSets"][presetName]["ki"]).
    LOCAL kdVec IS V(vp["XTune"]["tuningSets"][presetName]["kd"],
                      vp["YTune"]["tuningSets"][presetName]["kd"],
                      vp["ZTune"]["tuningSets"][presetName]["kd"]).

    vectorPIDSetKp(vp, kpVec).
    vectorPIDSetKi(vp, kiVec).
    vectorPIDSetKd(vp, kdVec).
    RETURN TRUE.
}

// vectorPIDUpdate
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   sampleTime (Scalar) - current time, seconds; normally TIME:SECONDS.
//   inputVec (Vector) - current process value on all three axes.
// Outputs:
//   Vector - the per-axis PIDLoop:UPDATE() output.
// Side Effects:
//   Advances the internal state (error sum, last input/time) of each of
//   vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDUpdate {
    PARAMETER vp.
    PARAMETER sampleTime.
    PARAMETER inputVec.

    LOCAL outX IS vp["X"]:UPDATE(sampleTime, inputVec:X).
    LOCAL outY IS vp["Y"]:UPDATE(sampleTime, inputVec:Y).
    LOCAL outZ IS vp["Z"]:UPDATE(sampleTime, inputVec:Z).
    RETURN V(outX, outY, outZ).
}

// vectorPIDReset
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
// Outputs:
//   None.
// Side Effects:
//   Calls PIDLoop:RESET() on vp["X"], vp["Y"], vp["Z"], clearing each
//   axis's error sum and last input/time.
FUNCTION vectorPIDReset {
    PARAMETER vp.
    vp["X"]:RESET().
    vp["Y"]:RESET().
    vp["Z"]:RESET().
}

// vectorPIDSetSetpoint
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   setpointVec (Vector) - new setpoint for all three axes.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:SETPOINT on vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDSetSetpoint {
    PARAMETER vp.
    PARAMETER setpointVec.
    SET vp["X"]:SETPOINT TO setpointVec:X.
    SET vp["Y"]:SETPOINT TO setpointVec:Y.
    SET vp["Z"]:SETPOINT TO setpointVec:Z.
}

// vectorPIDGetKp
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
// Outputs:
//   Vector - PIDLoop:KP read from vp["X"], vp["Y"], vp["Z"].
// Side Effects:
//   None.
FUNCTION vectorPIDGetKp {
    PARAMETER vp.
    RETURN V(vp["X"]:KP, vp["Y"]:KP, vp["Z"]:KP).
}

// vectorPIDSetKp
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   kpVec (Vector) - new proportional gain for all three axes.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:KP on vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDSetKp {
    PARAMETER vp.
    PARAMETER kpVec.
    SET vp["X"]:KP TO kpVec:X.
    SET vp["Y"]:KP TO kpVec:Y.
    SET vp["Z"]:KP TO kpVec:Z.
}

// vectorPIDGetKi
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
// Outputs:
//   Vector - PIDLoop:KI read from vp["X"], vp["Y"], vp["Z"].
// Side Effects:
//   None.
FUNCTION vectorPIDGetKi {
    PARAMETER vp.
    RETURN V(vp["X"]:KI, vp["Y"]:KI, vp["Z"]:KI).
}

// vectorPIDSetKi
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   kiVec (Vector) - new integral gain for all three axes.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:KI on vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDSetKi {
    PARAMETER vp.
    PARAMETER kiVec.
    SET vp["X"]:KI TO kiVec:X.
    SET vp["Y"]:KI TO kiVec:Y.
    SET vp["Z"]:KI TO kiVec:Z.
}

// vectorPIDGetKd
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
// Outputs:
//   Vector - PIDLoop:KD read from vp["X"], vp["Y"], vp["Z"].
// Side Effects:
//   None.
FUNCTION vectorPIDGetKd {
    PARAMETER vp.
    RETURN V(vp["X"]:KD, vp["Y"]:KD, vp["Z"]:KD).
}

// vectorPIDSetKd
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   kdVec (Vector) - new derivative gain for all three axes.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:KD on vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDSetKd {
    PARAMETER vp.
    PARAMETER kdVec.
    SET vp["X"]:KD TO kdVec:X.
    SET vp["Y"]:KD TO kdVec:Y.
    SET vp["Z"]:KD TO kdVec:Z.
}

// vectorPIDSetMaxOutput
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   maxVec (Vector) - new maximum output for all three axes.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:MAXOUTPUT on vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDSetMaxOutput {
    PARAMETER vp.
    PARAMETER maxVec.
    SET vp["X"]:MAXOUTPUT TO maxVec:X.
    SET vp["Y"]:MAXOUTPUT TO maxVec:Y.
    SET vp["Z"]:MAXOUTPUT TO maxVec:Z.
}

// vectorPIDSetMinOutput
// Inputs:
//   vp (Lexicon) - a vector PID loop from vectorPIDConstruct().
//   minVec (Vector) - new minimum output for all three axes.
// Outputs:
//   None.
// Side Effects:
//   Sets PIDLoop:MINOUTPUT on vp["X"], vp["Y"], vp["Z"].
FUNCTION vectorPIDSetMinOutput {
    PARAMETER vp.
    PARAMETER minVec.
    SET vp["X"]:MINOUTPUT TO minVec:X.
    SET vp["Y"]:MINOUTPUT TO minVec:Y.
    SET vp["Z"]:MINOUTPUT TO minVec:Z.
}

// getRCSThrusts
// Inputs:
//   None.
// Outputs:
//   Vector - summed AVAILABLETHRUST (Newtons) of all enabled RCS parts on
//   the current SHIP, split by translation axis: X = Fore, Y = Top,
//   Z = Starboard.
// Side Effects:
//   None.
FUNCTION getRCSThrusts {
	LOCAL RCSThrusters IS LIST().
	LIST RCS IN RCSThrusters.
	LOCAL maxRCSThrust IS V(0, 0, 0).
	FOR eachRCS IN RCSThrusters {
		IF eachRCS:ENABLED {
			IF eachRCS:FOREENABLED SET maxRCSThrust:X TO maxRCSThrust:X + eachRCS:AVAILABLETHRUST * 1000.
			IF eachRCS:TOPENABLED SET maxRCSThrust:Y TO maxRCSThrust:Y + eachRCS:AVAILABLETHRUST * 1000.
			IF eachRCS:STARBOARDENABLED SET maxRCSThrust:Z TO maxRCSThrust:Z + eachRCS:AVAILABLETHRUST * 1000.
		}
	}
	RETURN maxRCSThrust.
}

// Populated inside MAIN once HASTARGET is confirmed TRUE.
GLOBAL foreDirectionVector IS V(0,0,0).
GLOBAL topDirectionVector IS V(0,0,0).
GLOBAL starboardDirectionVector IS V(0,0,0).

// getMaxAccel
// Inputs:
//   None.
// Outputs:
//   Vector - maximum achievable acceleration (m/s^2) along Fore/Top/
//   Starboard, computed from getRCSThrusts() and SHIP:MASS. Returns
//   V(0,0,0) if SHIP:MASS is not positive (avoids a divide-by-zero;
//   not printed since this runs every physics tick).
// Side Effects:
//   None.
FUNCTION getMaxAccel {
    IF SHIP:MASS <= 0 { RETURN V(0,0,0). }
    RETURN getRCSThrusts() / (SHIP:MASS * 1000).
}

// modulateInput
// Inputs:
//   input (Scalar, range [-inf, inf]) - desired control input.
//   threshold (Scalar, range [0, inf]) - minimum input magnitude the
//        actuator can respond to continuously.
//   period (Scalar, > 0) - PWM period, seconds, used when
//        ABS(input) < threshold.
// Outputs:
//   Scalar - input unchanged if ABS(input) >= threshold; otherwise
//   +/-threshold during the PWM "on" phase, or 0 during the "off" phase.
// Side Effects:
//   None.
FUNCTION modulateInput {
    PARAMETER input.
    PARAMETER threshold.
    PARAMETER period.
	
	IF threshold < 0 SET threshold TO ABS(threshold).

    IF ABS(input) >= threshold { RETURN input. }

    LOCAL sign IS 1.
    IF input < 0 { SET sign TO -1. }

    LOCAL dutyCycle IS ABS(input) / threshold.
    IF dutyCycle < 0 { SET dutyCycle TO 0. }
    IF dutyCycle > 1 { SET dutyCycle TO 1. }

    LOCAL phase IS MOD(TIME:SECONDS, period) / period.
    IF phase < dutyCycle RETURN threshold * sign.

    RETURN 0.
}

// applyRCSAccel
// Inputs:
//   effortVec (Vector) - desired acceleration, m/s^2, ship-local Fore/
//        Top/Starboard frame.
//   maxLimits (Vector, default V(1,1,1)) - per-axis maximum achievable
//        acceleration, m/s^2, used to normalize effortVec into a
//        [-1, 1] SHIP:CONTROL command. Axes with maxLimits <= 0 are
//        commanded to 0.
//   rcsDeadzoneThreshold (Scalar, range [0, 1], default 0.05) - minimum
//        continuous RCS command, as a fraction of full thrust.
//   rcsPwmPeriod (Scalar, > 0, default 0.2) - PWM period, seconds, used
//        for commands below rcsDeadzoneThreshold.
// Outputs:
//   None.
// Side Effects:
//   Sets SHIP:CONTROL:FORE, SHIP:CONTROL:TOP, SHIP:CONTROL:STARBOARD.
FUNCTION applyRCSAccel {
    PARAMETER effortVec.
    PARAMETER maxLimits IS V(1, 1, 1).
    PARAMETER rcsDeadzoneThreshold IS 0.05.
    PARAMETER rcsPwmPeriod IS 0.2.

    LOCAL effort IS V(0, 0, 0).
    IF maxLimits:X > 0 { SET effort:X TO effortVec:X / maxLimits:X. }
    IF maxLimits:Y > 0 { SET effort:Y TO effortVec:Y / maxLimits:Y. }
    IF maxLimits:Z > 0 { SET effort:Z TO effortVec:Z / maxLimits:Z. }

    IF effort:X > 1 { SET effort:X TO 1. }
    IF effort:X < -1 { SET effort:X TO -1. }
    IF effort:Y > 1 { SET effort:Y TO 1. }
    IF effort:Y < -1 { SET effort:Y TO -1. }
    IF effort:Z > 1 { SET effort:Z TO 1. }
    IF effort:Z < -1 { SET effort:Z TO -1. }

    SET SHIP:CONTROL:FORE TO modulateInput(effort:X, rcsDeadzoneThreshold, rcsPwmPeriod).
    SET SHIP:CONTROL:TOP TO modulateInput(effort:Y, rcsDeadzoneThreshold, rcsPwmPeriod).
    SET SHIP:CONTROL:STARBOARD TO modulateInput(effort:Z, rcsDeadzoneThreshold, rcsPwmPeriod).
}

// applyPlantEffort
// Inputs:
//   effortVec (Vector) - desired acceleration, m/s^2, ship-local Fore/
//        Top/Starboard frame.
// Outputs:
//   None.
// Side Effects:
//   Calls applyRCSAccel(effortVec, getMaxAccel()); see applyRCSAccel for
//   the resulting SHIP:CONTROL changes.
FUNCTION applyPlantEffort {
    PARAMETER effortVec.
    applyRCSAccel(effortVec, getMaxAccel()).
}

// getRelativeVelocity
// Inputs:
//   None.
// Outputs:
//   Vector - (TARGET velocity - SHIP velocity), resolved onto the
//   Fore/Top/Starboard axes (foreDirectionVector, topDirectionVector,
//   starboardDirectionVector), m/s. Returns V(0,0,0) if HASTARGET is
//   FALSE.
// Side Effects:
//   None.
FUNCTION getRelativeVelocity {
    IF NOT HASTARGET { RETURN V(0,0,0). }
	LOCAL targetVelocity IS V(0,0,0).
    IF TARGET:TYPENAME = "DockingPort" SET targetVelocity TO TARGET:SHIP:VELOCITY:ORBIT.
	ELSE SET targetVelocity TO TARGET:VELOCITY:ORBIT.
    LOCAL relVel IS targetVelocity - SHIP:VELOCITY:ORBIT.
    RETURN V(relVel * foreDirectionVector,
			 relVel * topDirectionVector,
			 relVel * starboardDirectionVector).
}

// getRelativePosition
// Inputs:
//   None.
// Outputs:
//   Vector - (TARGET:POSITION - SHIP:CONTROLPART:POSITION), resolved
//   onto the Fore/Top/Starboard axes (foreDirectionVector,
//   topDirectionVector, starboardDirectionVector), m. Returns V(0,0,0)
//   if HASTARGET is FALSE.
// Side Effects:
//   None.
FUNCTION getRelativePosition {
    IF NOT HASTARGET { RETURN V(0,0,0). }
    LOCAL worldOffset IS TARGET:POSITION - SHIP:CONTROLPART:POSITION.
    RETURN V(worldOffset * foreDirectionVector,
			 worldOffset * topDirectionVector,
			 worldOffset * starboardDirectionVector).
}

// applyViaInnerLoop
// Inputs:
//   innerPIDLoopArg (Lexicon) - a vector PID loop from vectorPIDConstruct(),
//        used as the inner (velocity) loop.
//   innerActuator (Delegate, (Vector effortVec, Vector maxInnerCVfn) -> None)
//        - applies the computed effort to the plant.
//   maxInnerCVfn (Delegate, () -> Vector) - returns the current per-axis
//        output limit.
//   innerValueGetter (Delegate, () -> Vector) - returns the current
//        inner process value.
//   setpointVec (Vector) - commanded inner (velocity) setpoint, m/s.
// Outputs:
//   None.
// Side Effects:
//   Sets innerPIDLoopArg's setpoint and output limits, advances its
//   internal state by one UPDATE() step, and calls innerActuator() with
//   the resulting effort.
FUNCTION applyViaInnerLoop {
    PARAMETER innerPIDLoopArg.
    PARAMETER innerActuator.
    PARAMETER maxInnerCVfn.
    PARAMETER innerValueGetter.
    PARAMETER setpointVec.

    vectorPIDSetSetpoint(innerPIDLoopArg, setpointVec).

    LOCAL currentInner IS innerValueGetter().
    LOCAL maxInnerCV IS maxInnerCVfn().
    vectorPIDSetMaxOutput(innerPIDLoopArg, maxInnerCV).
    vectorPIDSetMinOutput(innerPIDLoopArg, -1 * maxInnerCV).

    LOCAL effortVec IS vectorPIDUpdate(innerPIDLoopArg, TIME:SECONDS, currentInner).
    innerActuator(effortVec, maxInnerCV).
}

GLOBAL logPath IS "0:/cascaded3dLog.csv".
GLOBAL scriptStartTime IS TIME:SECONDS.
GLOBAL currentStageLabel IS "".
GLOBAL escapeChar IS CHAR(27).
// Scrolling on-screen message log; see logStatus()/printStatus().
GLOBAL statusMessages IS LIST().
GLOBAL maxStatusMessages IS 8.

// startLogFile
// Inputs:
//   None.
// Outputs:
//   None.
// Side Effects:
//   Deletes logPath if it already exists, then writes a 3-row CSV
//   header (column names, axis labels, units) to logPath.
FUNCTION startLogFile {
    IF EXISTS(logPath) { DELETEPATH(logPath). }
	LOG "time,stage,Velocity,Velocity,Velocity,Velocity,Position,Position,Position,Position,Effort,Effort,Effort,Effort" TO logPath.
    LOG "time,stage,Fore,Top,Starboard,Total,Fore,Top,Starboard,Total,Fore,Top,Starboard,Total" TO logPath.
    LOG "s,stage,m/s,m/s,m/s,m/s,m,m,m,m,,,," TO logPath.
}

// logRow
// Inputs:
//   None. Reads the file-scope positionPIDLoop and velocityPIDLoop, and the
//   current currentStageLabel.
// Outputs:
//   None.
// Side Effects:
//   Appends one row of all six axis PIDLoops' internal state to
//   "0:/multiplePIDLoopLog.csv" (via logPIDMultiple(), from library.ks),
//   and appends one row of relative velocity, position, and RCS effort
//   to logPath.
FUNCTION logRow {
    LOCAL vel IS getRelativeVelocity().
    LOCAL pos IS getRelativePosition().
    LOCAL eff IS V(SHIP:CONTROL:FORE, SHIP:CONTROL:TOP, SHIP:CONTROL:STARBOARD).

	logPIDMultiple(LEXICON("Velocity X", velocityPIDLoop["X"],
						   "Velocity Y", velocityPIDLoop["Y"],
						   "Velocity Z", velocityPIDLoop["Z"],
						   "Position X", positionPIDLoop["X"],
						   "Position Y", positionPIDLoop["Y"],
						   "Position Z", positionPIDLoop["Z"]),
				   "0:/multiplePIDLoopLog.csv",
				   FALSE,
				   LEXICON("labelRow", "Position X,Position Y,Position Z,Velocity X,Velocity Y,Velocity Z",
						   "valueRow", "m,m,m,m/s,m/s,m/s",
						   "rowData", pos:X + "," + pos:Y + "," + pos:Z + "," + vel:X + "," + vel:Y + "," + vel:Z)).

    LOCAL t IS TIME:SECONDS - scriptStartTime.
    LOCAL row IS t + "," + currentStageLabel + "," +
        vel:X + "," + vel:Y + "," + vel:Z + "," + vel:MAG + "," +
        pos:X + "," + pos:Y + "," + pos:Z + "," + pos:MAG + "," +
        eff:X + "," + eff:Y + "," + eff:Z + "," + eff:MAG.
    LOG row TO logPath.
}

// printStatus
// Inputs:
//   selectedAxisIndex (Scalar, default -1) - index (0=Fore, 1=Top,
//        2=Starboard) of the axis to highlight; -1 highlights none.
//   setpointLex (Lexicon, default empty) - if it has exactly 3 keys
//        ("X","Y","Z"), a Setpoint column and the manual-control key
//        hints are shown using its values; an empty Lexicon suppresses
//        both.
//   incrementValue (Scalar, default 0) - current manual step size,
//        shown next to unitsLabel; only used if setpointLex has 3 keys.
//   unitsLabel (String, default "m/s") - unit label shown after
//        incrementValue.
//   editModeName (String, default "") - "Setpoint" or "Tuning Preset";
//        selects which key hints are shown; only used if setpointLex has
//        3 keys.
//   presetName (String, default "") - name of the currently active
//        tuning preset, shown next to editModeName when non-empty.
// Outputs:
//   None.
// Side Effects:
//   Prints a fixed-position telemetry table (distance, velocity, RCS
//   output per axis, optional setpoint/step-size/key hints, and a
//   scrolling message log fed by logStatus()) to the terminal at screen
//   rows 3 through 15 + maxStatusMessages.
FUNCTION printStatus {
    PARAMETER selectedAxisIndex IS -1.
    PARAMETER setpointLex IS LEXICON().
    PARAMETER incrementValue IS 0.
    PARAMETER unitsLabel IS "m/s".
    PARAMETER editModeName IS "".
    PARAMETER presetName IS "".

    LOCAL vel IS getRelativeVelocity().
    LOCAL pos IS getRelativePosition().
    LOCAL eff IS V(SHIP:CONTROL:FORE, SHIP:CONTROL:TOP, SHIP:CONTROL:STARBOARD).
	LOCAL terminalWidth IS TERMINAL:WIDTH.
    LOCAL hasSetpoints IS setpointLex:LENGTH = 3.

    LOCAL header IS "          Distance  Velocity    Output".
    IF hasSetpoints SET header TO header + "  Setpoint".
    PRINT header:PADRIGHT(terminalWidth) AT (0, 3).

    LOCAL axisRowLabels IS LIST("Fore", "Top ", "Stbd").
    LOCAL axisKeys IS manualAxisKeys.
    LOCAL posComponents IS LIST(pos:X, pos:Y, pos:Z).
    LOCAL velComponents IS LIST(vel:X, vel:Y, vel:Z).
    LOCAL effComponents IS LIST(eff:X, eff:Y, eff:Z).

    LOCAL i IS 0.
    UNTIL i >= 3 {
        LOCAL marker IS "  ".
        IF i = selectedAxisIndex SET marker TO "> ".
        LOCAL row IS marker + axisRowLabels[i] + "  " +
            ROUND(posComponents[i], 2):TOSTRING:PADLEFT(8) +
            ROUND(velComponents[i], 3):TOSTRING:PADLEFT(10) +
            ROUND(effComponents[i], 3):TOSTRING:PADLEFT(10).
        IF hasSetpoints SET row TO row + ROUND(setpointLex[axisKeys[i]], 2):TOSTRING:PADLEFT(10).
        PRINT row:PADRIGHT(terminalWidth) AT (0, 4 + i).
        SET i TO i + 1.
    }

    PRINT ("  Total " + ROUND(pos:MAG, 2):TOSTRING:PADLEFT(8) + ROUND(vel:MAG, 3):TOSTRING:PADLEFT(10) + ROUND(eff:MAG, 3):TOSTRING:PADLEFT(10)):PADRIGHT(terminalWidth) AT (0, 7).
    PRINT ("  Mode " + currentStageLabel):PADRIGHT(terminalWidth) AT (0, 8).
    IF hasSetpoints {
        PRINT ("  Step " + ROUND(incrementValue, 3) + " " + unitsLabel):PADRIGHT(terminalWidth) AT (0, 9).
        LOCAL editLine IS "  Editing: " + editModeName.
        IF presetName <> "" SET editLine TO editLine + " (" + presetName + ")".
        PRINT editLine:PADRIGHT(terminalWidth) AT (0, 10).
        PRINT ("  [LEFT/RIGHT] axis     [V/P] velocity/position loop"):PADRIGHT(terminalWidth) AT (0, 11).
        IF editModeName = "Tuning Preset" {
            PRINT ("  [UP/DOWN] change preset (applied immediately)   [M] edit setpoint instead"):PADRIGHT(terminalWidth) AT (0, 12).
            PRINT (" "):PADRIGHT(terminalWidth) AT (0, 13).
        } ELSE {
            PRINT ("  [UP/DOWN] setpoint     [S/D] step size   [M] edit tuning preset instead"):PADRIGHT(terminalWidth) AT (0, 12).
            PRINT ("  [0] reset setpoint"):PADRIGHT(terminalWidth) AT (0, 13).
        }
        PRINT ("  [X/ESC] exit"):PADRIGHT(terminalWidth) AT (0, 14).
    } ELSE {
        PRINT " ":PADRIGHT(terminalWidth) AT (0,  9).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 10).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 11).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 12).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 13).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 14).
    }

    PRINT "  Messages:":PADRIGHT(terminalWidth) AT (0, 15).
    LOCAL startIndex IS MAX(0, statusMessages:LENGTH - maxStatusMessages).
    LOCAL lineRow IS 16.
    LOCAL msgIndex IS startIndex.
    UNTIL msgIndex >= statusMessages:LENGTH {
        PRINT ("  " + statusMessages[msgIndex]):PADRIGHT(terminalWidth) AT (0, lineRow).
        SET lineRow TO lineRow + 1.
        SET msgIndex TO msgIndex + 1.
    }
    UNTIL lineRow > 15 + maxStatusMessages {
        PRINT " ":PADRIGHT(terminalWidth) AT (0, lineRow).
        SET lineRow TO lineRow + 1.
    }
}

// logStatus
// Inputs:
//   message (String) - one line of status/progress/warning/error text.
// Outputs:
//   None.
// Side Effects:
//   Appends message to the GLOBAL statusMessages list (dropping the
//   oldest entries beyond maxStatusMessages), then calls printStatus()
//   so the new message is visible immediately, in the terminal's fixed
//   message-log area rather than scrolling the whole screen the way a
//   bare PRINT would.
FUNCTION logStatus {
    PARAMETER message.
    statusMessages:ADD(message).
    UNTIL statusMessages:LENGTH <= maxStatusMessages {
        statusMessages:REMOVE(0).
    }
    printStatus().
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
//   axisState (Lexicon) - state from makeAxisRelayState()/tickAxisRelay(),
//        expected to have "turningPoints":LENGTH >= 4 for a valid result.
//   relayAmplitude (Scalar) - magnitude of the relay output used during
//        the test for this axis.
// Outputs:
//   Lexicon with:
//     "Ku" (Scalar) - measured ultimate gain (0 if the test data is
//          insufficient); negated if axisState["reversed"] is TRUE.
//     "Pu" (Scalar) - measured ultimate period, seconds (0 if the test
//          data is insufficient).
//     "tuningSets" (Lexicon) - four entries, each a Lexicon with "kp",
//          "ki", "kd" (Scalar): "classic" (Ziegler-Nichols PID rule),
//          "aggressive" (Pessen Integral Rule), "conservative"
//          (Ziegler-Nichols no-overshoot rule), "criticallyDamped"
//          (Tyreus-Luyben rule).
// Side Effects:
//   None.
FUNCTION computeAxisTuningRelay {
    PARAMETER axisState.
    PARAMETER relayAmplitude.

    LOCAL emptySets IS LEXICON(
        "classic", LEXICON("kp",0,"ki",0,"kd",0),
        "aggressive", LEXICON("kp",0,"ki",0,"kd",0),
        "conservative", LEXICON("kp",0,"ki",0,"kd",0),
        "criticallyDamped", LEXICON("kp",0,"ki",0,"kd",0)
    ).

    LOCAL turningPoints IS axisState["turningPoints"].
    IF turningPoints:LENGTH < 4 {
        RETURN LEXICON("Ku", 0, "Pu", 0, "tuningSets", emptySets).
    }

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
    IF amplitude <= 0 OR Pu <= 0 {
        RETURN LEXICON("Ku", 0, "Pu", 0, "tuningSets", emptySets).
    }

    LOCAL Ku IS (4 * relayAmplitude) / (CONSTANT:PI * amplitude).

	IF axisState["reversed"] SET Ku TO -Ku.

    LOCAL sets IS LEXICON().

    LOCAL classicKp IS 0.6 * Ku.
    LOCAL classicTi IS 0.5 * Pu.
    LOCAL classicTd IS 0.125 * Pu.
    SET sets["classic"] TO LEXICON("kp", classicKp, "ki", classicKp / classicTi, "kd", classicKp * classicTd).

    LOCAL aggressiveKp IS 0.7 * Ku.
    LOCAL aggressiveTi IS 0.4 * Pu.
    LOCAL aggressiveTd IS 0.15 * Pu.
    SET sets["aggressive"] TO LEXICON("kp", aggressiveKp, "ki", aggressiveKp / aggressiveTi, "kd", aggressiveKp * aggressiveTd).

    LOCAL conservativeKp IS 0.2 * Ku.
    LOCAL conservativeTi IS 0.5 * Pu.
    LOCAL conservativeTd IS 0.33 * Pu.
    SET sets["conservative"] TO LEXICON("kp", conservativeKp, "ki", conservativeKp / conservativeTi, "kd", conservativeKp * conservativeTd).

    LOCAL criticalKp IS Ku / 2.2.
    LOCAL criticalTi IS 2.2 * Pu.
    LOCAL criticalTd IS Pu / 6.3.
    SET sets["criticallyDamped"] TO LEXICON("kp", criticalKp, "ki", criticalKp / criticalTi, "kd", criticalKp * criticalTd).

    RETURN LEXICON("Ku", Ku, "Pu", Pu, "tuningSets", sets).
}

// vectorRelayAutotune
// Inputs:
//   vectorPIDLoop (Lexicon) - a vector PID loop from vectorPIDConstruct();
//        its Kp/Ki/Kd are overwritten with the "criticallyDamped" result.
//   getValueVec (Delegate, () -> Vector) - reads the current process
//        value.
//   applyOutputVec (Delegate, (Vector) -> None) - applies a commanded
//        output vector to the plant.
//   setpointVec (Vector) - relay test target value on all three axes.
//   relayAmplitudeVec (Vector, all components > 0) - relay output
//        magnitude per axis.
//   stageLabel (String) - label written to currentStageLabel and used in
//        printed warnings.
//   hysteresisVec (Vector, all components >= 0, default V(0,0,0)) -
//        per-axis relay hysteresis.
//   settleCycles (Scalar, integer, default 2) - leading oscillation
//        cycles discarded before measuring.
//   measureCycles (Scalar, integer, default 4) - oscillation cycles used
//        to measure Ku/Pu after settling.
//   maxDuration (Scalar, seconds, default 90) - time limit for the test.
//   tuningRuleName (String, default "criticallyDamped") - which key of
//        computeAxisTuningRelay()'s "tuningSets" to apply; one of "classic",
//        "aggressive", "conservative", "criticallyDamped".
// Outputs:
//   Lexicon with:
//     "Ku" (Vector) - measured ultimate gain per axis.
//     "Pu" (Vector) - measured ultimate period per axis, seconds.
//     "axisTuning" (Lexicon) - keys "X","Y","Z", each the full
//          computeAxisTuningRelay() result for that axis.
// Side Effects:
//   Sets vectorPIDLoop's setpoint, Kp, Ki, Kd. Repeatedly calls
//   applyOutputVec(), printStatus(), and logRow() until all three axes'
//   relay tests finish or maxDuration elapses; sets applyOutputVec to
//   V(0,0,0) before returning. Sets currentStageLabel to stageLabel.
//   Prints a warning if the test times out before converging.
FUNCTION vectorRelayAutotune {
    PARAMETER vectorPIDLoop.
    PARAMETER getValueVec.
    PARAMETER applyOutputVec.
    PARAMETER setpointVec.
    PARAMETER relayAmplitudeVec.
    PARAMETER stageLabel.
    PARAMETER hysteresisVec IS V(0,0,0).
    PARAMETER settleCycles IS 2.
    PARAMETER measureCycles IS 4.
    PARAMETER maxDuration IS 90.
    PARAMETER tuningRuleName IS "criticallyDamped".

    vectorPIDSetSetpoint(vectorPIDLoop, setpointVec).

    LOCAL neededPoints IS (settleCycles + measureCycles) * 2.
    LOCAL initial IS getValueVec().

    LOCAL axisStates IS LEXICON().
    SET axisStates["X"] TO makeAxisRelayState(initial:X, neededPoints, settleCycles).
    SET axisStates["Y"] TO makeAxisRelayState(initial:Y, neededPoints, settleCycles).
    SET axisStates["Z"] TO makeAxisRelayState(initial:Z, neededPoints, settleCycles).

	LOCAL reversalKickHoldTime IS 0.5.
	LOCAL reversalKickEpsilon IS 0.01.
	LOCAL kickStartTime IS TIME:SECONDS.
	UNTIL TIME:SECONDS - kickStartTime >= reversalKickHoldTime {
		applyOutputVec(relayAmplitudeVec).
		WAIT 0.
	}
	applyOutputVec(V(0,0,0)).
	LOCAL afterInitial IS getValueVec().
	LOCAL initialDelta IS afterInitial - initial.
	SET axisStates["X"]["rising"] TO initialDelta:X > 0.
	SET axisStates["Y"]["rising"] TO initialDelta:Y > 0.
	SET axisStates["Z"]["rising"] TO initialDelta:Z > 0.
	SET axisStates["X"]["reversed"] TO initialDelta:X < -reversalKickEpsilon.
	SET axisStates["Y"]["reversed"] TO initialDelta:Y < -reversalKickEpsilon.
	SET axisStates["Z"]["reversed"] TO initialDelta:Z < -reversalKickEpsilon.

    LOCAL startTime IS TIME:SECONDS.

    UNTIL (axisStates["X"]["done"] AND axisStates["Y"]["done"] AND axisStates["Z"]["done"])
       OR (TIME:SECONDS - startTime > maxDuration) {

        LOCAL value IS getValueVec().

        LOCAL signX IS tickAxisRelay(axisStates["X"], value:X, setpointVec:X, hysteresisVec:X).
        LOCAL signY IS tickAxisRelay(axisStates["Y"], value:Y, setpointVec:Y, hysteresisVec:Y).
        LOCAL signZ IS tickAxisRelay(axisStates["Z"], value:Z, setpointVec:Z, hysteresisVec:Z).

        LOCAL outputVec IS V(signX * relayAmplitudeVec:X, signY * relayAmplitudeVec:Y, signZ * relayAmplitudeVec:Z).
        applyOutputVec(outputVec).

        SET currentStageLabel TO stageLabel.
        printStatus().
        logRow().

        WAIT 0.
    }

    applyOutputVec(V(0,0,0)).

    IF NOT (axisStates["X"]["done"] AND axisStates["Y"]["done"] AND axisStates["Z"]["done"]) {
        logStatus("WARNING: '" + stageLabel + "' relay autotune hit its " + timeToString(maxDuration) + " time limit before converging on all axes.").
    }

	SET vectorPIDLoop["XTune"] TO computeAxisTuningRelay(axisStates["X"], relayAmplitudeVec:X).
	SET vectorPIDLoop["YTune"] TO computeAxisTuningRelay(axisStates["Y"], relayAmplitudeVec:Y).
	SET vectorPIDLoop["ZTune"] TO computeAxisTuningRelay(axisStates["Z"], relayAmplitudeVec:Z).

    LOCAL chosenKp IS V(vectorPIDLoop["XTune"]["tuningSets"][tuningRuleName]["kp"], vectorPIDLoop["YTune"]["tuningSets"][tuningRuleName]["kp"], vectorPIDLoop["ZTune"]["tuningSets"][tuningRuleName]["kp"]).
    LOCAL chosenKi IS V(vectorPIDLoop["XTune"]["tuningSets"][tuningRuleName]["ki"], vectorPIDLoop["YTune"]["tuningSets"][tuningRuleName]["ki"], vectorPIDLoop["ZTune"]["tuningSets"][tuningRuleName]["ki"]).
    LOCAL chosenKd IS V(vectorPIDLoop["XTune"]["tuningSets"][tuningRuleName]["kd"], vectorPIDLoop["YTune"]["tuningSets"][tuningRuleName]["kd"], vectorPIDLoop["ZTune"]["tuningSets"][tuningRuleName]["kd"]).

    vectorPIDSetKp(vectorPIDLoop, chosenKp).
    vectorPIDSetKi(vectorPIDLoop, chosenKi).
    vectorPIDSetKd(vectorPIDLoop, chosenKd).

    RETURN LEXICON(
        "Ku", V(vectorPIDLoop["XTune"]["Ku"], vectorPIDLoop["YTune"]["Ku"], vectorPIDLoop["ZTune"]["Ku"]),
        "Pu", V(vectorPIDLoop["XTune"]["Pu"], vectorPIDLoop["YTune"]["Pu"], vectorPIDLoop["ZTune"]["Pu"]),
        "axisTuning", LEXICON("X", vectorPIDLoop["XTune"], "Y", vectorPIDLoop["YTune"], "Z", vectorPIDLoop["ZTune"])
    ).
}

// vectorRelayAutotuneRetry
// Inputs:
//   vectorPIDLoop (Lexicon) - see vectorRelayAutotune().
//   getValueVec (Delegate, () -> Vector) - see vectorRelayAutotune().
//   applyOutputVec (Delegate, (Vector) -> None) - see vectorRelayAutotune().
//   setpointVec (Vector) - see vectorRelayAutotune(); ignored if
//        setpointIsRelative is TRUE.
//   relayAmplitudeVec (Vector, all components > 0) - see
//        vectorRelayAutotune().
//   stageLabel (String) - see vectorRelayAutotune().
//   hysteresisVec (Vector, default V(0,0,0)) - see vectorRelayAutotune().
//   settleCycles (Scalar, integer, default 2) - see vectorRelayAutotune().
//   measureCycles (Scalar, integer, default 4) - see vectorRelayAutotune().
//   maxDuration (Scalar, seconds, default 90) - see vectorRelayAutotune().
//   maxAttempts (Scalar, integer, default 3) - number of times to retry
//        the whole test if any axis comes back with a zero Ku or Kp.
//   setpointIsRelative (Boolean, default FALSE) - if TRUE, the setpoint
//        for each attempt is re-read from getValueVec() (the current
//        process value) instead of using setpointVec.
//   tuningRuleName (String, default "criticallyDamped") - see
//        vectorRelayAutotune().
// Outputs:
//   Lexicon - same as vectorRelayAutotune(), plus "success" (Boolean),
//   TRUE unless every attempt produced a zero Ku/Kp on at least one axis.
// Side Effects:
//   Same as vectorRelayAutotune(), repeated once per attempt. Prints a
//   warning after each failed attempt and an error after the last one.
FUNCTION vectorRelayAutotuneRetry {
    PARAMETER vectorPIDLoop.
    PARAMETER getValueVec.
    PARAMETER applyOutputVec.
    PARAMETER setpointVec.
    PARAMETER relayAmplitudeVec.
    PARAMETER stageLabel.
    PARAMETER hysteresisVec IS V(0,0,0).
    PARAMETER settleCycles IS 2.
    PARAMETER measureCycles IS 4.
    PARAMETER maxDuration IS 90.
    PARAMETER maxAttempts IS 3.
    PARAMETER setpointIsRelative IS FALSE.
    PARAMETER tuningRuleName IS "criticallyDamped".

    LOCAL attempt IS 1.
    LOCAL result IS LEXICON("Ku", V(0,0,0), "Pu", V(0,0,0)).

    UNTIL attempt > maxAttempts {
        LOCAL attemptSetpoint IS setpointVec.
        IF setpointIsRelative { SET attemptSetpoint TO getValueVec(). }

        SET result TO vectorRelayAutotune(vectorPIDLoop, getValueVec, applyOutputVec, attemptSetpoint, relayAmplitudeVec, stageLabel, hysteresisVec, settleCycles, measureCycles, maxDuration, tuningRuleName).

        LOCAL kuVec IS result["Ku"].
        LOCAL kpVec IS vectorPIDGetKp(vectorPIDLoop).
        LOCAL failed IS kuVec:X = 0 OR kuVec:Y = 0 OR kuVec:Z = 0
                     OR kpVec:X = 0 OR kpVec:Y = 0 OR kpVec:Z = 0.

        IF NOT failed {
            SET result["success"] TO TRUE.
            RETURN result.
        }

        logStatus("  WARNING: '" + stageLabel + "' autotune attempt " + attempt + "/" + maxAttempts +
              " produced a zero coefficient (Ku=" + ROUNDV(kuVec, 4) + "). Retrying...").
        SET attempt TO attempt + 1.
    }

    logStatus("  ERROR: '" + stageLabel + "' autotune still produced a zero coefficient after " +
          maxAttempts + " attempts. Check RCS thruster availability/orientation and relay amplitude.").
    SET result["success"] TO FALSE.
    RETURN result.
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

// computeIntegratingTuningSets
// Inputs:
//   KpProcess (Scalar) - integrating process gain, from
//        computeAxisIntegratingTuning().
//   Td (Scalar, seconds, >= 0) - process dead time.
//   lambdaMin (Scalar, seconds, default 1) - floor applied to every
//        preset's lambda (see computeIntegratingGains()).
// Outputs:
//   Lexicon with three named presets, each a Lexicon("kp","ki","kd")
//   from computeIntegratingGains(): "aggressive" (lambda = 1*Td, fastest
//   response, least disturbance rejection margin), "standard" (lambda =
//   3*Td, a common default), "conservative" (lambda = 6*Td, slowest,
//   most robust). Every lambda is floored at lambdaMin. This mirrors the
//   shape of computeAxisTuningRelay()'s "tuningSets" so both the inner
//   (velocity) and outer (position) loops can share the same
//   vectorPIDApplyTuningPreset()/vectorPIDTuningPresetNames() functions.
// Side Effects:
//   None.
FUNCTION computeIntegratingTuningSets {
    PARAMETER KpProcess.
    PARAMETER Td.
    PARAMETER lambdaMin IS 1.

    LOCAL sets IS LEXICON().
    SET sets["aggressive"] TO computeIntegratingGains(KpProcess, Td, MAX(1 * Td, lambdaMin)).
    SET sets["standard"] TO computeIntegratingGains(KpProcess, Td, MAX(3 * Td, lambdaMin)).
    SET sets["conservative"] TO computeIntegratingGains(KpProcess, Td, MAX(6 * Td, lambdaMin)).
    RETURN sets.
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

// vectorIntegratingStepTest
// Inputs:
//   vectorPIDLoop (Lexicon) - a vector PID loop from vectorPIDConstruct();
//        its Kp/Ki/Kd are overwritten with the computed lambda tuning.
//   getValueVec (Delegate, () -> Vector) - reads the current process
//        value (position).
//   innerActuator (Delegate, (Vector setpointVec) -> None) - commands the
//        inner loop's setpoint.
//   stepAmplitudeVec (Vector, non-zero components) - velocity-setpoint
//        step commanded on each axis during the hold, m/s.
//   stageLabel (String) - label written to currentStageLabel.
//   preSettleDuration (Scalar, seconds, default 3) - time to hold zero
//        output before the step, to measure the process value's baseline
//        slope.
//   holdDuration (Scalar, seconds, default 20) - time to hold the step.
//   regressionFraction (Scalar, range (0, 1], default 0.5) - see
//        computeAxisIntegratingTuning().
//   lambdaFactor (Scalar, default 3) - if useCustomLambda is FALSE, lambda
//        = lambdaFactor * Td; if useCustomLambda is TRUE, passed through
//        as computeRequiredLambda()'s minLambdaFactor.
//   lambdaMin (Scalar, seconds, default 1) - floor on lambda; only used if
//        useCustomLambda is FALSE.
//   useCustomLambda (Boolean, default FALSE) - if TRUE, lambda is derived
//        per axis from customAPD/customMLD via computeRequiredLambda()
//        instead of from lambdaFactor/lambdaMin.
//   customAPD (Scalar, > 0, default 0) - allowable process deviation; see
//        computeRequiredLambda(). Only used if useCustomLambda is TRUE.
//   customMLD (Scalar, default 0) - maximum load disturbance; see
//        computeRequiredLambda(). Only used if useCustomLambda is TRUE.
// Outputs:
//   Lexicon with "KpProcess" (Vector), "Td" (Vector, seconds), "lambda"
//   (Vector, seconds), and "axisTuning" (Lexicon with keys "X","Y","Z",
//   each the computeAxisIntegratingTuning() result for that axis).
// Side Effects:
//   Sets vectorPIDLoop's Kp, Ki, Kd. Repeatedly calls innerActuator(),
//   printStatus(), and logRow() during the pre-settle and hold phases;
//   calls innerActuator(V(0,0,0)) before returning. Sets
//   currentStageLabel to stageLabel + " (settle)" then stageLabel +
//   " (step)".
FUNCTION vectorIntegratingStepTest {
    PARAMETER vectorPIDLoop.
    PARAMETER getValueVec.
    PARAMETER innerActuator.
    PARAMETER stepAmplitudeVec.
    PARAMETER stageLabel.
    PARAMETER preSettleDuration IS 3.
    PARAMETER holdDuration IS 20.
    PARAMETER regressionFraction IS 0.5.
    PARAMETER lambdaFactor IS 3.
    PARAMETER lambdaMin IS 1.
    PARAMETER useCustomLambda IS FALSE.
    PARAMETER customAPD IS 0.
    PARAMETER customMLD IS 0.

    LOCAL settleStart IS TIME:SECONDS.
    LOCAL preSamples IS LEXICON("X", LIST(), "Y", LIST(), "Z", LIST()).

    UNTIL TIME:SECONDS - settleStart >= preSettleDuration {
        innerActuator(V(0,0,0)).
        LOCAL posNow IS getValueVec().
        preSamples["X"]:ADD(LEXICON("t", TIME:SECONDS, "pos", posNow:X)).
        preSamples["Y"]:ADD(LEXICON("t", TIME:SECONDS, "pos", posNow:Y)).
        preSamples["Z"]:ADD(LEXICON("t", TIME:SECONDS, "pos", posNow:Z)).
        SET currentStageLabel TO stageLabel + " (settle)".
        printStatus().
        logRow().
        WAIT 0.
    }

    LOCAL preSlopeVec IS V(0,0,0).
	LOCAL preX IS linearRegression(preSamples["X"]).
	LOCAL preY IS linearRegression(preSamples["Y"]).
	LOCAL preZ IS linearRegression(preSamples["Z"]).
	SET preSlopeVec TO V(preX["slope"], preY["slope"], preZ["slope"]).

    LOCAL pos0 IS getValueVec().
    LOCAL t0 IS TIME:SECONDS.
    LOCAL holdSamples IS LEXICON("X", LIST(), "Y", LIST(), "Z", LIST()).

	UNTIL TIME:SECONDS - t0 >= holdDuration {
		innerActuator(stepAmplitudeVec).
		LOCAL t IS TIME:SECONDS - t0.
		LOCAL posNow2 IS getValueVec().
		holdSamples["X"]:ADD(LEXICON("t", t, "pos", posNow2:X)).
		holdSamples["Y"]:ADD(LEXICON("t", t, "pos", posNow2:Y)).
		holdSamples["Z"]:ADD(LEXICON("t", t, "pos", posNow2:Z)).
		SET currentStageLabel TO stageLabel + " (step)".
		printStatus().
		logRow().
		WAIT 0.
    }

    innerActuator(V(0,0,0)).

    LOCAL tuneX IS computeAxisIntegratingTuning(holdSamples["X"], pos0:X, preSlopeVec:X, stepAmplitudeVec:X, holdDuration, regressionFraction).
    LOCAL tuneY IS computeAxisIntegratingTuning(holdSamples["Y"], pos0:Y, preSlopeVec:Y, stepAmplitudeVec:Y, holdDuration, regressionFraction).
    LOCAL tuneZ IS computeAxisIntegratingTuning(holdSamples["Z"], pos0:Z, preSlopeVec:Z, stepAmplitudeVec:Z, holdDuration, regressionFraction).

    // Populate XTune/YTune/ZTune with a set of named lambda presets, the
    // same shape vectorRelayAutotune() uses for the velocity loop, so the
    // operator can later switch between them via
    // vectorPIDApplyTuningPreset()/vectorPIDTuningPresetNames().
    SET vectorPIDLoop["XTune"] TO LEXICON("Ku", 0, "Pu", 0, "tuningSets", computeIntegratingTuningSets(tuneX["KpProcess"], tuneX["Td"], lambdaMin)).
    SET vectorPIDLoop["YTune"] TO LEXICON("Ku", 0, "Pu", 0, "tuningSets", computeIntegratingTuningSets(tuneY["KpProcess"], tuneY["Td"], lambdaMin)).
    SET vectorPIDLoop["ZTune"] TO LEXICON("Ku", 0, "Pu", 0, "tuningSets", computeIntegratingTuningSets(tuneZ["KpProcess"], tuneZ["Td"], lambdaMin)).

    LOCAL lambdaVec IS V(0,0,0).
    IF useCustomLambda {
        SET lambdaVec TO V(computeRequiredLambda(tuneX["KpProcess"], tuneX["Td"], customAPD, customMLD, lambdaFactor),
                            computeRequiredLambda(tuneY["KpProcess"], tuneY["Td"], customAPD, customMLD, lambdaFactor),
                            computeRequiredLambda(tuneZ["KpProcess"], tuneZ["Td"], customAPD, customMLD, lambdaFactor)).

        LOCAL gainX IS computeIntegratingGains(tuneX["KpProcess"], tuneX["Td"], lambdaVec:X).
        LOCAL gainY IS computeIntegratingGains(tuneY["KpProcess"], tuneY["Td"], lambdaVec:Y).
        LOCAL gainZ IS computeIntegratingGains(tuneZ["KpProcess"], tuneZ["Td"], lambdaVec:Z).

        vectorPIDSetKp(vectorPIDLoop, V(gainX["kp"], gainY["kp"], gainZ["kp"])).
        vectorPIDSetKi(vectorPIDLoop, V(gainX["ki"], gainY["ki"], gainZ["ki"])).
        vectorPIDSetKd(vectorPIDLoop, V(gainX["kd"], gainY["kd"], gainZ["kd"])).
    } ELSE {
        SET lambdaVec TO V(MAX(lambdaFactor * tuneX["Td"], lambdaMin),
                            MAX(lambdaFactor * tuneY["Td"], lambdaMin),
                            MAX(lambdaFactor * tuneZ["Td"], lambdaMin)).
        // "standard" is computeIntegratingTuningSets()'s 3x-Td preset,
        // matching this branch's historical default lambdaFactor of 3.
        vectorPIDApplyTuningPreset(vectorPIDLoop, "standard").
    }

    RETURN LEXICON(
        "KpProcess", V(tuneX["KpProcess"], tuneY["KpProcess"], tuneZ["KpProcess"]),
        "Td", V(tuneX["Td"], tuneY["Td"], tuneZ["Td"]),
        "lambda", lambdaVec,
        "axisTuning", LEXICON("X", tuneX, "Y", tuneY, "Z", tuneZ)
    ).
}

// vectorIntegratingAutotuneRetry
// Inputs:
//   vectorPIDLoop (Lexicon) - see vectorIntegratingStepTest().
//   getValueVec (Delegate, () -> Vector) - see vectorIntegratingStepTest().
//   innerActuator (Delegate, (Vector) -> None) - see
//        vectorIntegratingStepTest().
//   stepAmplitudeVec (Vector, non-zero components) - see
//        vectorIntegratingStepTest().
//   stageLabel (String) - see vectorIntegratingStepTest().
//   preSettleDuration (Scalar, seconds, default 3) - see
//        vectorIntegratingStepTest().
//   holdDuration (Scalar, seconds, default 20) - see
//        vectorIntegratingStepTest().
//   regressionFraction (Scalar, range (0, 1], default 0.5) - see
//        vectorIntegratingStepTest().
//   lambdaFactor (Scalar, default 3) - see vectorIntegratingStepTest().
//   lambdaMin (Scalar, seconds, default 1) - see
//        vectorIntegratingStepTest().
//   maxAttempts (Scalar, integer, default 3) - number of times to retry
//        the whole test if any axis comes back with a zero KpProcess or
//        Kp.
//   useCustomLambda (Boolean, default FALSE) - see
//        vectorIntegratingStepTest().
//   customAPD (Scalar, > 0, default 0) - see vectorIntegratingStepTest().
//   customMLD (Scalar, default 0) - see vectorIntegratingStepTest().
// Outputs:
//   Lexicon - same as vectorIntegratingStepTest(), plus "success"
//   (Boolean), TRUE unless every attempt produced a zero KpProcess/Kp on
//   at least one axis.
// Side Effects:
//   Same as vectorIntegratingStepTest(), repeated once per attempt.
//   Prints a warning after each failed attempt and an error after the
//   last one.
FUNCTION vectorIntegratingAutotuneRetry {
    PARAMETER vectorPIDLoop.
    PARAMETER getValueVec.
    PARAMETER innerActuator.
    PARAMETER stepAmplitudeVec.
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

    LOCAL attempt IS 1.
    LOCAL result IS LEXICON("KpProcess", V(0,0,0), "Td", V(0,0,0), "lambda", V(0,0,0)).

    UNTIL attempt > maxAttempts {

        SET result TO vectorIntegratingStepTest(vectorPIDLoop, getValueVec, innerActuator, stepAmplitudeVec, stageLabel, preSettleDuration, holdDuration, regressionFraction, lambdaFactor, lambdaMin, useCustomLambda, customAPD, customMLD).

        LOCAL kpVec IS vectorPIDGetKp(vectorPIDLoop).
        LOCAL kpProcessVec IS result["KpProcess"].
        LOCAL failed IS kpProcessVec:X = 0 OR kpProcessVec:Y = 0 OR kpProcessVec:Z = 0
                     OR kpVec:X = 0 OR kpVec:Y = 0 OR kpVec:Z = 0.

        IF NOT failed {
            SET result["success"] TO TRUE.
            RETURN result.
        }

        logStatus("  WARNING: '" + stageLabel + "' autotune attempt " + attempt + "/" + maxAttempts +
              " produced a zero coefficient (KpProcess=" + ROUNDV(kpProcessVec, 4) + "). Retrying...").
        SET attempt TO attempt + 1.
    }

    logStatus("  ERROR: '" + stageLabel + "' autotune still produced a zero coefficient after " +
          maxAttempts + " attempts. Check RCS thruster availability/orientation and step amplitude.").
    SET result["success"] TO FALSE.
    RETURN result.
}

// runCascaded3DPIDLoop
// Inputs:
//   outerPIDLoopArg (Lexicon) - a vector PID loop from vectorPIDConstruct(),
//        used as the outer loop.
//   innerPIDLoopArg (Lexicon) - a vector PID loop from vectorPIDConstruct(),
//        used as the inner loop.
//   innerActuator (Delegate, (Vector effortVec, Vector maxLimits) -> None)
//        - applies the computed effort to the plant.
//   getInnerCVLimits (Delegate, () -> Vector) - returns the current
//        per-axis inner-loop output limit.
//   getInnerPVFn (Delegate, () -> Vector) - reads the current inner
//        process value.
//   getOuterPVFn (Delegate, () -> Vector) - reads the current outer
//        process value.
//   outerSP (Vector) - outer-loop setpoint.
//   stageLabel (String) - label written to currentStageLabel.
//   maxDuration (Scalar, seconds) - time limit for the run.
//   settleConfirmDuration (Scalar, seconds) - time both tolerances must
//        hold continuously before the run is considered settled.
//   outerTolerance (Scalar, >= 0) - maximum outer-loop error magnitude
//        counted as settled.
//   innerTolerance (Scalar, >= 0) - maximum inner-loop value magnitude
//        counted as settled.
// Outputs:
//   Boolean - TRUE if the run settled within maxDuration, FALSE if it
//   timed out first.
// Side Effects:
//   Resets and re-targets outerPIDLoopArg and innerPIDLoopArg.
//   Repeatedly calls innerActuator(), printStatus(), and logRow() until
//   settled or maxDuration elapses; calls innerActuator(V(0,0,0),
//   getInnerCVLimits()) before returning. Sets currentStageLabel to
//   stageLabel.
FUNCTION runCascaded3DPIDLoop {
    PARAMETER outerPIDLoopArg.
    PARAMETER innerPIDLoopArg.
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

    vectorPIDReset(outerPIDLoopArg).
    vectorPIDReset(innerPIDLoopArg).
    vectorPIDSetSetpoint(outerPIDLoopArg, outerSP).

    LOCAL startTime IS TIME:SECONDS.
    LOCAL settledSince IS -1.

    UNTIL (settledSince >= 0 AND (TIME:SECONDS - startTime - settledSince) >= settleConfirmDuration)
       OR (TIME:SECONDS - startTime > maxDuration) {
        LOCAL now IS TIME:SECONDS - startTime.
        LOCAL innerNow IS getInnerPVFn().
        LOCAL outerNow IS getOuterPVFn().

        LOCAL innerSetpoint IS vectorPIDUpdate(outerPIDLoopArg, TIME:SECONDS, outerNow).
        vectorPIDSetSetpoint(innerPIDLoopArg, innerSetpoint).

        LOCAL innerCVLimits IS getInnerCVLimits().
        vectorPIDSetMaxOutput(innerPIDLoopArg, innerCVLimits).
        vectorPIDSetMinOutput(innerPIDLoopArg, -1 * innerCVLimits).
        LOCAL effortVec IS vectorPIDUpdate(innerPIDLoopArg, TIME:SECONDS, innerNow).
        innerActuator(effortVec, innerCVLimits).

        LOCAL outerErrMag IS (outerNow - outerSP):MAG.
        LOCAL innerMag IS innerNow:MAG.
        IF outerErrMag <= outerTolerance AND innerMag <= innerTolerance {
            IF settledSince < 0 { SET settledSince TO now. }
        } ELSE {
            SET settledSince TO -1.
        }

        SET currentStageLabel TO stageLabel.
        printStatus().
        logRow().

        WAIT 0.
    }

    innerActuator(V(0,0,0), getInnerCVLimits()).
    RETURN settledSince >= 0.
}

GLOBAL manualAxisNames IS LIST("Fore", "Top", "Starboard").
GLOBAL manualAxisKeys IS LIST("X", "Y", "Z").
GLOBAL velocityIncrementOptions IS LIST(0.05, 0.1, 0.5, 1, 5, 25, 100).
GLOBAL manualDefaultVelocityIncrementIndex IS 1.
GLOBAL positionIncrementOptions IS LIST(0.1, 0.5, 1, 5, 10, 25, 50, 100).
GLOBAL manualDefaultPositionIncrementIndex IS 1.

// -----------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------
CLEARSCREEN.
SET scriptStartTime TO TIME:SECONDS.
startLogFile().

logStatus("=== CASCADED 3D VECTOR PID AUTOTUNE + MANUAL CONTROL ===").

IF NOT HASTARGET {
    logStatus("No target selected. Select a target and rerun this script.").
} ELSE {
    LOCAL innerRelaySetpoint IS V(0,0,0).
    LOCAL innerRelayAmplitudeFraction IS 0.5.
    LOCAL innerRelayHysteresis IS V(0.05, 0.05, 0.05).
    LOCAL outerRelayAmplitude IS V(2, 2, 2).
    LOCAL outerRelayHysteresis IS V(0.5, 0.5, 0.5).
    LOCAL relaySettleCycles IS 2.
    LOCAL relayMeasureCycles IS 4.
    LOCAL innerRelayMaxDuration IS 40.
    LOCAL outerRelayMaxDuration IS 90.
    LOCAL outerStepAmplitude IS V(1, 1, 1).
    LOCAL outerStepPreSettleDuration IS 3.
    LOCAL outerStepHoldDuration IS 20.
    LOCAL outerStepRegressionFraction IS 0.5.
    LOCAL outerLambdaFactor IS 3.
    LOCAL outerLambdaMin IS 1.
    LOCAL rotationSettleThreshold IS 0.01.
    LOCAL rotationSettleTimeout IS 30.

    SET foreDirectionVector TO -TARGET:FACING:FOREVECTOR.
    SET topDirectionVector TO TARGET:FACING:TOPVECTOR.
    SET starboardDirectionVector TO -TARGET:FACING:STARVECTOR.

    LOCAL foreVector IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), YELLOW, "Fore", 1.0, TRUE, 0.2).
    LOCAL topVector  IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), RED, "Top" , 1.0, TRUE, 0.2).
    LOCAL StarboardVector IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), BLUE, "Starboard", 1.0, TRUE, 0.2).
    LOCAL tgtVector  IS VECDRAW(SHIP:CONTROLPART:POSITION, V(0,0,0), GREEN, "Target", 1.0, TRUE, 0.2).
    LOCAL tgtFacing  IS VECDRAW(V(0,0,0), V(0,0,0), PURPLE, "Target Facing", 1.0, TRUE, 0.2).
    LOCAL velVecDraw  IS VECDRAW(V(0,0,0), V(0,0,0), WHITE, "Velocity", 1.0, TRUE, 0.2).

    SET foreVector:VECUPDATER TO {RETURN foreDirectionVector * 5.0.}.
    SET topVector:VECUPDATER TO {RETURN topDirectionVector * 5.0.}.
    SET starboardVector:VECUPDATER TO {RETURN starboardDirectionVector * 5.0.}.
    SET tgtVector:VECUPDATER TO {RETURN TARGET:POSITION - SHIP:CONTROLPART:POSITION.}.
    SET tgtFacing:VECUPDATER TO {RETURN TARGET:FACING:VECTOR * 5.0.}.
    SET velVecDraw:VECUPDATER TO {LOCAL relVel IS getRelativeVelocity(). RETURN -1 * (relVel:X * foreDirectionVector + relVel:Y * topDirectionVector + relVel:Z * starboardDirectionVector).}.

    SET foreVector:STARTUPDATER TO {RETURN SHIP:CONTROLPART:POSITION.}.
    SET topVector:STARTUPDATER TO {RETURN SHIP:CONTROLPART:POSITION.}.
    SET StarboardVector:STARTUPDATER TO {RETURN SHIP:CONTROLPART:POSITION.}.
    SET tgtVector:STARTUPDATER TO {RETURN SHIP:CONTROLPART:POSITION.}.
    SET tgtFacing:STARTUPDATER TO {RETURN TARGET:POSITION.}.
    SET velVecDraw:STARTUPDATER TO {RETURN SHIP:CONTROLPART:POSITION.}.

    RCS ON.
    SET globalSteer TO LOOKDIRUP(foreDirectionVector, topDirectionVector).
    setLockedSteering(TRUE).
	WAIT 2.

    LOCAL mode IS "setup".
	LOCAL innerActuatorDelegate IS applyViaInnerLoop@:BIND(velocityPIDLoop, applyRCSAccel@, getMaxAccel@, getRelativeVelocity@).
	LOCAL outerResult IS LEXICON().

	LOCAL selectedAxisIndex IS 0.
	LOCAL incrementIndex IS manualDefaultVelocityIncrementIndex.
	LOCAL setpointLex IS LEXICON("X", 0, "Y", 0, "Z", 0).
	LOCAL maxVelocitySetpoint IS 100.
	LOCAL maxPositionSetpoint IS 1000.
	LOCAL tempChar IS "".
	LOCAL currentVel IS getRelativeVelocity().
	LOCAL currentPos IS getRelativePosition().
	LOCAL defaultPosition IS V(10, 0, 0).
	LOCAL usePosition IS FALSE.
	LOCAL maxAccel IS getMaxAccel().
	LOCAL rotationWaitStart IS TIME:SECONDS.

	// Which "variable" the operator's UP/DOWN keys currently modify.
	LOCAL editModeNames IS LIST("Setpoint", "Tuning Preset").
	LOCAL editModeIndex IS 0.
	LOCAL presetIndex IS 0.
	LOCAL currentPresetName IS "".

    UNTIL mode = "done" {
		SET maxAccel TO getMaxAccel().
		SET currentVel TO getRelativeVelocity().
		SET currentPos TO getRelativePosition().
		logRow().

		// Wait for steering to stabilize
        IF mode = "setup" {
            IF (SHIP:ANGULARVEL:MAG < rotationSettleThreshold) OR (TIME:SECONDS - rotationWaitStart >= rotationSettleTimeout) {
				SET mode TO "Tuning Velocity".
            }

        } ELSE IF mode = "Tuning Velocity" {
            logStatus("Stage 1: relay-tuning the velocity PID loop (per axis, simultaneously)...").

            LOCAL innerRelayAmp IS maxAccel * innerRelayAmplitudeFraction.
            LOCAL innerResult IS vectorRelayAutotuneRetry(velocityPIDLoop, getRelativeVelocity@, applyPlantEffort@, innerRelaySetpoint, innerRelayAmp, "innerRelay", innerRelayHysteresis, relaySettleCycles, relayMeasureCycles, innerRelayMaxDuration, 3, FALSE).

            logStatus("  inner Ku=" + ROUNDV(innerResult["Ku"], 4) + "  Pu=" + ROUNDV(innerResult["Pu"], 4)).
            logStatus("  inner Kp=" + ROUNDV(vectorPIDGetKp(velocityPIDLoop), 4) + "  Ki=" + ROUNDV(vectorPIDGetKi(velocityPIDLoop), 4) + "  Kd=" + ROUNDV(vectorPIDGetKd(velocityPIDLoop), 4)).

            IF NOT innerResult["success"] {
                SET mode TO "done".
            } ELSE {
                SET mode TO "Tuning Position".
				logStatus("Stage 2: tuning the outer PID loop (cascade active)...").
            }

        } ELSE IF mode = "Tuning Position" {
			SET outerResult TO vectorIntegratingAutotuneRetry(positionPIDLoop, getRelativePosition@, innerActuatorDelegate, outerStepAmplitude, "outerLambda", outerStepPreSettleDuration, outerStepHoldDuration, outerStepRegressionFraction, outerLambdaFactor, outerLambdaMin, 3).
            logStatus("  outer Kp=" + ROUNDV(vectorPIDGetKp(positionPIDLoop), 4) + "  Ki=" + ROUNDV(vectorPIDGetKi(positionPIDLoop), 4) + "  Kd=" + ROUNDV(vectorPIDGetKd(positionPIDLoop), 4)).

            IF NOT outerResult["success"] {
                logStatus("ERROR! Outer loop failed to autotune after retries - aborting.").
                SET mode TO "done".
            } ELSE {
                logStatus("Stage 3: flying with the newly tuned loops.").
                logStatus("  [V] velocity loop  [P] position loop  [M] setpoint/tuning-preset edit").
                logStatus("  [UP/DOWN] adjust   [LEFT/RIGHT] axis  [X/ESC] exit").

                // Bumpless transfer into manual control: start the velocity
                // setpoint at the ship's current relative velocity instead
                // of snapping to zero.
                SET mode TO "Manual Control".
                SET usePosition TO FALSE.
                SET incrementIndex TO manualDefaultVelocityIncrementIndex.
                SET editModeIndex TO 0.
                SET presetIndex TO 0.
                SET currentPresetName TO "".
                SET setpointLex["X"] TO currentVel:X.
                SET setpointLex["Y"] TO currentVel:Y.
                SET setpointLex["Z"] TO currentVel:Z.
            }

        } ELSE IF mode = "Manual Control" {

			IF usePosition {
				vectorPIDSetSetpoint(positionPIDLoop, V(setpointLex:X, setpointLex:Y, setpointLex:Z)).
				vectorPIDSetMaxOutput(positionPIDLoop, maxAccel * 10).
				vectorPIDSetMinOutput(positionPIDLoop, -1 * maxAccel * 10).
				vectorPIDSetSetpoint(velocityPIDLoop, vectorPIDUpdate(positionPIDLoop, TIME:SECONDS, currentPos)).
				printStatus(selectedAxisIndex, setpointLex, positionIncrementOptions[incrementIndex], "m", editModeNames[editModeIndex], currentPresetName).
			} ELSE {
				vectorPIDSetSetpoint(velocityPIDLoop, V(setpointLex:X, setpointLex:Y, setpointLex:Z)).
				printStatus(selectedAxisIndex, setpointLex, velocityIncrementOptions[incrementIndex], "m/s", editModeNames[editModeIndex], currentPresetName).
			}

			vectorPIDSetMaxOutput(velocityPIDLoop, maxAccel).
			vectorPIDSetMinOutput(velocityPIDLoop, -1 * maxAccel).
			LOCAL effortVec IS vectorPIDUpdate(velocityPIDLoop, TIME:SECONDS, currentVel).
			applyRCSAccel(effortVec, maxAccel).

			// Letter keys are matched case-insensitively so CAPS LOCK/shift
			// doesn't silently do nothing.
			LOCAL chLower IS tempChar:TOLOWER().

			IF tempChar = TERMINAL:INPUT:LEFTCURSORONE {
				SET selectedAxisIndex TO MOD(selectedAxisIndex + 2, 3).
			} ELSE IF tempChar = TERMINAL:INPUT:RIGHTCURSORONE {
				SET selectedAxisIndex TO MOD(selectedAxisIndex + 1, 3).
			} ELSE IF tempChar = TERMINAL:INPUT:UPCURSORONE {
				IF editModeNames[editModeIndex] = "Tuning Preset" {
					LOCAL presetNamesUp IS CHOOSE vectorPIDTuningPresetNames(positionPIDLoop) IF usePosition ELSE vectorPIDTuningPresetNames(velocityPIDLoop).
					IF presetNamesUp:LENGTH > 0 {
						SET presetIndex TO MOD(presetIndex + 1, presetNamesUp:LENGTH).
						SET currentPresetName TO presetNamesUp[presetIndex].
						IF usePosition { vectorPIDApplyTuningPreset(positionPIDLoop, currentPresetName). }
						ELSE { vectorPIDApplyTuningPreset(velocityPIDLoop, currentPresetName). }
					}
				} ELSE {
					LOCAL upAxisKey IS manualAxisKeys[selectedAxisIndex].
					LOCAL upIncrement IS velocityIncrementOptions[incrementIndex].
					LOCAL upMax IS maxVelocitySetpoint.
					IF usePosition {
						SET upIncrement TO positionIncrementOptions[incrementIndex].
						SET upMax TO maxPositionSetpoint.
					}
					LOCAL upValue IS setpointLex[upAxisKey] + upIncrement.
					IF upValue > upMax SET upValue TO upMax.
					SET setpointLex[upAxisKey] TO upValue.
				}
			} ELSE IF tempChar = TERMINAL:INPUT:DOWNCURSORONE {
				IF editModeNames[editModeIndex] = "Tuning Preset" {
					LOCAL presetNamesDown IS CHOOSE vectorPIDTuningPresetNames(positionPIDLoop) IF usePosition ELSE vectorPIDTuningPresetNames(velocityPIDLoop).
					IF presetNamesDown:LENGTH > 0 {
						IF presetIndex = 0 SET presetIndex TO presetNamesDown:LENGTH - 1.
						ELSE SET presetIndex TO presetIndex - 1.
						SET currentPresetName TO presetNamesDown[presetIndex].
						IF usePosition { vectorPIDApplyTuningPreset(positionPIDLoop, currentPresetName). }
						ELSE { vectorPIDApplyTuningPreset(velocityPIDLoop, currentPresetName). }
					}
				} ELSE {
					LOCAL downAxisKey IS manualAxisKeys[selectedAxisIndex].
					LOCAL downIncrement IS velocityIncrementOptions[incrementIndex].
					LOCAL downMax IS maxVelocitySetpoint.
					IF usePosition {
						SET downIncrement TO positionIncrementOptions[incrementIndex].
						SET downMax TO maxPositionSetpoint.
					}
					LOCAL downValue IS setpointLex[downAxisKey] - downIncrement.
					IF downValue < -downMax SET downValue TO -downMax.
					SET setpointLex[downAxisKey] TO downValue.
				}
			} ELSE IF chLower = "v" {
				SET usePosition TO FALSE.
				SET incrementIndex TO manualDefaultVelocityIncrementIndex.
				SET setpointLex["X"] TO currentVel:X.
				SET setpointLex["Y"] TO currentVel:Y.
				SET setpointLex["Z"] TO currentVel:Z.
				SET editModeIndex TO 0.
				SET presetIndex TO 0.
				SET currentPresetName TO "".
			} ELSE IF chLower = "p" {
				SET usePosition TO TRUE.
				SET incrementIndex TO manualDefaultPositionIncrementIndex.
				SET setpointLex["X"] TO currentPos:X.
				SET setpointLex["Y"] TO currentPos:Y.
				SET setpointLex["Z"] TO currentPos:Z.
				SET editModeIndex TO 0.
				SET presetIndex TO 0.
				SET currentPresetName TO "".
			} ELSE IF chLower = "m" {
				SET editModeIndex TO MOD(editModeIndex + 1, editModeNames:LENGTH).
				IF editModeNames[editModeIndex] = "Tuning Preset" {
					LOCAL presetNamesInit IS CHOOSE vectorPIDTuningPresetNames(positionPIDLoop) IF usePosition ELSE vectorPIDTuningPresetNames(velocityPIDLoop).
					SET presetIndex TO 0.
					IF presetNamesInit:LENGTH > 0 SET currentPresetName TO presetNamesInit[0].
					ELSE SET currentPresetName TO "".
				} ELSE {
					SET currentPresetName TO "".
				}
			} ELSE IF chLower = "s" {
				IF usePosition SET incrementIndex TO MOD(incrementIndex + 1, positionIncrementOptions:LENGTH).
				ELSE SET incrementIndex TO MOD(incrementIndex + 1, velocityIncrementOptions:LENGTH).
			} ELSE IF chLower = "d" {
				IF usePosition {
					IF incrementIndex = 0 SET incrementIndex TO positionIncrementOptions:LENGTH - 1.
					ELSE SET incrementIndex TO incrementIndex - 1.
				} ELSE {
					IF incrementIndex = 0 SET incrementIndex TO velocityIncrementOptions:LENGTH - 1.
					ELSE SET incrementIndex TO incrementIndex - 1.
				}
			} ELSE IF tempChar = "0" {
				IF usePosition SET setpointLex TO LEXICON("X", defaultPosition:X, "Y", defaultPosition:Y, "Z", defaultPosition:Z).
				ELSE SET setpointLex TO LEXICON("X", 0, "Y", 0, "Z", 0).
			} ELSE IF chLower = "x" OR tempChar = escapeChar {
				SET mode TO "done".
			}
		}
		SET tempChar TO "".
		UNTIL NOT TERMINAL:INPUT:HASCHAR {
			SET tempChar TO TERMINAL:INPUT:GETCHAR().
		}
    }

    applyRCSAccel(V(0,0,0)).
    setLockedSteering(FALSE).
    RCS OFF.
}
