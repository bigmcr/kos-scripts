@LAZYGLOBAL OFF.

// Optional arguments, in this order (all have defaults):
//   retune - FALSE; any other value ignores the saved velocity tuning and tunes again.
//   usePositionStepTest - FALSE; TRUE runs the position loop step test (costs RCS propellant) instead of deriving its gains.
//   autoApproachSpeed - 0.2 m/s; the closing speed of auto mode.
//   rcsPropellantFraction - 0.9; the fraction of the remaining RCS propellant that one move may use (sets the speed limit).
//   rcsReserveDeltaV - 10 m/s; the RCS delta-v that must be left over after tuning for the docking.
PARAMETER retune IS FALSE.
PARAMETER usePositionStepTest IS FALSE.
PARAMETER autoApproachSpeed IS 0.2.
PARAMETER rcsPropellantFraction IS 0.9.
PARAMETER rcsReserveDeltaV IS 10.
LOCAL forceRetune IS retune:TOSTRING:TOLOWER <> "false".

LOCAL positionPIDLoop IS PIDAxesConstruct(3, 1, 0, 0, -10, 10).
LOCAL velocityPIDLoop IS PIDAxesConstruct(3, 1, 0, 0, -1, 1).

// Set from the target's facing by updateTargetAxes(), which MAIN calls every tick once HASTARGET is confirmed TRUE.
LOCAL foreDirectionVector IS V(0,0,0).
LOCAL topDirectionVector IS V(0,0,0).
LOCAL starboardDirectionVector IS V(0,0,0).
// TRUE if the ship faces away from the target's facing (the original behavior), FALSE if it faces the same way. The operator
// chooses with the Q and A keys.
LOCAL facingAway IS TRUE.

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

// updateTargetAxes
// Inputs:
//   None. Reads the file-scope facingAway.
// Outputs:
//   None.
// Side Effects:
//   Sets foreDirectionVector, topDirectionVector and starboardDirectionVector from the target's current facing, and globalSteer to
//   point the ship along them, so the control follows a target that is turning (its orbit alone turns it a little). Facing away
//   from the target's facing turns the ship half a turn around its top direction, so the fore and starboard axes are reversed and
//   the top axis is not. Does nothing if HASTARGET is FALSE.
FUNCTION updateTargetAxes {
    IF NOT HASTARGET { RETURN. }

    IF facingAway {
        SET foreDirectionVector TO -TARGET:FACING:FOREVECTOR.
        SET topDirectionVector TO TARGET:FACING:TOPVECTOR.
        SET starboardDirectionVector TO -TARGET:FACING:STARVECTOR.
    } ELSE {
        SET foreDirectionVector TO TARGET:FACING:FOREVECTOR.
        SET topDirectionVector TO TARGET:FACING:TOPVECTOR.
        SET starboardDirectionVector TO TARGET:FACING:STARVECTOR.
    }
    SET globalSteer TO LOOKDIRUP(foreDirectionVector, topDirectionVector).
}

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

// getRCSSpeedLimit
// Inputs:
//   propellantFraction (Scalar, range (0, 1]) - the fraction of the RCS propellant that is left that one move may use.
//   axisCount (Scalar, integer, > 0, default 3) - number of axes that may be moving at the top speed at the same time.
// Outputs:
//   Scalar - the top speed, in m/s on each axis, that keeps one move within that propellant, or -1 if shipInfo does not report
//   any RCS propellant (so there is nothing to base a limit on). The rocket equation, with the RCS Isp (IspRCS), the ship's mass
//   (CurrentMass) and the RCS propellant mass (fuelRCSMass) from shipInfo["CurrentStage"], gives the delta-v that
//   propellantFraction of the propellant is worth (never more than the stage's DeltaVRCS). Getting to a speed and stopping again on
//   one axis costs twice that speed in delta-v, and the thrusters on different axes burn separately, so all axisCount axes at
//   once cost 2 * axisCount times the speed.
// Side Effects:
//   None. Reads shipInfo, so call updateShipInfoResources() first to have the propellant that is left.
FUNCTION getRCSSpeedLimit {
    PARAMETER propellantFraction.
    PARAMETER axisCount IS 3.

    LOCAL stageInfo IS shipInfo["CurrentStage"].
    LOCAL stageMass IS stageInfo["CurrentMass"].
    LOCAL rcsPropellant IS stageInfo["fuelRCSMass"].
    LOCAL rcsIsp IS stageInfo["IspRCS"].
    IF stageMass <= 0 OR rcsPropellant <= 0 OR rcsIsp <= 0 { RETURN -1. }

    LOCAL usablePropellant IS propellantFraction * rcsPropellant.
    IF usablePropellant >= stageMass { RETURN -1. }
    LOCAL usableDeltaV IS rcsIsp * g_0 * LN(stageMass / (stageMass - usablePropellant)).
    RETURN usableDeltaV / (2 * axisCount).
}

// applyDockingAccel
// Inputs:
//   effortVec (Vector) - desired acceleration, m/s^2, ship-local Fore/Top/Starboard frame.
//   maxLimits (Vector, default V(1,1,1)) - per-axis maximum achievable acceleration, m/s^2.
//   Reads the file-scope rcsEffortDeadband.
// Outputs:
//   None.
// Side Effects:
//   Calls applyRCSAccel() with the default PWM settings and rcsEffortDeadband, so commands below that fraction of full thrust are not
//   sent. Sets SHIP:CONTROL:FORE, SHIP:CONTROL:TOP, SHIP:CONTROL:STARBOARD.
FUNCTION applyDockingAccel {
    PARAMETER effortVec.
    PARAMETER maxLimits IS V(1, 1, 1).
    applyRCSAccel(effortVec, maxLimits, 0.05, 0.2, rcsEffortDeadband).
}

// getDefaultPosition
// Inputs:
//   None. Reads the file-scope facingAway.
// Outputs:
//   List of Scalar - the position that auto mode goes to, metres Fore, Top, Starboard: Top and Starboard are 0, and Fore is
//   MIN(10, MAX(the Fore position now, 2)). When the ship faces the same way as the target (facingAway is FALSE) Fore is negative.
// Side Effects:
//   None.
FUNCTION getDefaultPosition {
    LOCAL foreSign IS 1.
    IF NOT facingAway { SET foreSign TO -1. }
    RETURN LIST(foreSign * MIN(10, MAX(foreSign * getRelativePosition():X, 2)), 0, 0).
}

LOCAL logPath IS "0:/cascaded3dLog.csv".
LOCAL scriptStartTime IS TIME:SECONDS.
LOCAL currentStageLabel IS "".
LOCAL escapeChar IS CHAR(27).
// the on-screen message log, shown by printStatus(); it does not scroll, see logStatus()
LOCAL statusMessages IS LIST().
// rows 16 down to the second to last: writing to the last row scrolls the terminal
LOCAL maxStatusMessages IS MAX(4, TERMINAL:HEIGHT - 17).
// the row of the newest message; once the rows are full each new message replaces the oldest one in place
LOCAL latestStatusSlot IS -1.

// startLogFile
// Inputs:
//   None.
// Outputs:
//   None.
// Side Effects:
//   Deletes logPath if it exists, then writes a 3-row CSV header (names, axes, units) to it. Does nothing without a connection to
//   KSC.
FUNCTION startLogFile {
    IF NOT connectionToKSC() { RETURN. }
    IF EXISTS(logPath) { DELETEPATH(logPath). }
	LOG "time,stage,Velocity,Velocity,Velocity,Velocity,Position,Position,Position,Position,Effort,Effort,Effort,Effort,Tuning,Tuning" TO logPath.
    LOG "time,stage,Fore,Top,Starboard,Total,Fore,Top,Starboard,Total,Fore,Top,Starboard,Total,velocity,position" TO logPath.
    LOG "s,stage,m/s,m/s,m/s,m/s,m,m,m,m,,,,,," TO logPath.
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

	logPIDMultiple(LEXICON("Velocity X", velocityPIDLoop[0]["PID"],
						   "Velocity Y", velocityPIDLoop[1]["PID"],
						   "Velocity Z", velocityPIDLoop[2]["PID"],
						   "Position X", positionPIDLoop[0]["PID"],
						   "Position Y", positionPIDLoop[1]["PID"],
						   "Position Z", positionPIDLoop[2]["PID"]),
				   "0:/multiplePIDLoopLog.csv",
				   FALSE,
				   LEXICON("labelRow", "Position X,Position Y,Position Z,Velocity X,Velocity Y,Velocity Z",
						   "valueRow", "m,m,m,m/s,m/s,m/s",
						   "rowData", pos:X + "," + pos:Y + "," + pos:Z + "," + vel:X + "," + vel:Y + "," + vel:Z)).

    LOCAL t IS TIME:SECONDS - scriptStartTime.
    LOCAL row IS t + "," + currentStageLabel + "," +
        vel:X + "," + vel:Y + "," + vel:Z + "," + vel:MAG + "," +
        pos:X + "," + pos:Y + "," + pos:Z + "," + pos:MAG + "," +
        eff:X + "," + eff:Y + "," + eff:Z + "," + eff:MAG + "," +
        tuningStatus["velocity"] + "," + tuningStatus["position"].
    // logPath is on the archive, which cannot be written to while there is no connection to KSC
    IF connectionToKSC() { LOG row TO logPath. }
}

// formatTableRow
// Inputs:
//   cells (List of String) - the text of each column of a row.
//   widths (List of Scalar) - the width of each column.
//   rightAligned (List of Boolean) - whether each column's text is lined up on its right edge (values) or its left edge (labels and
//        units).
//   columnCount (Scalar) - how many of the columns to use, counting from the first.
// Outputs:
//   String - the cells padded to their widths, with two spaces between every column.
// Side Effects:
//   None.
FUNCTION formatTableRow {
    PARAMETER cells.
    PARAMETER widths.
    PARAMETER rightAligned.
    PARAMETER columnCount.

    LOCAL line IS "".
    LOCAL i IS 0.
    UNTIL i >= columnCount {
        IF i > 0 { SET line TO line + "  ". }
        IF rightAligned[i] { SET line TO line + cells[i]:PADLEFT(widths[i]). }
        ELSE { SET line TO line + cells[i]:PADRIGHT(widths[i]). }
        SET i TO i + 1.
    }
    RETURN line.
}

// printStatus
// Inputs:
//   setpointList (List of Scalar, default empty) - if it has 3 elements (Fore, Top, Starboard), a Setpoint column shows them and the
//        key hints are shown; an empty List suppresses both.
//   unitsList (List of String, default "m" each) - the unit of each setpoint: "m" for a position, "m/s" for a velocity.
// Outputs:
//   None.
// Side Effects:
//   Prints the telemetry table at fixed screen rows: per axis the distance, velocity, velocity loop setpoint and RCS output (% of
//   full thrust), then the optional setpoint column and key hints, then the message log from logStatus() from row 16 down. Needs a
//   terminal at least 84 columns wide.
FUNCTION printStatus {
    PARAMETER setpointList IS LIST().
    PARAMETER unitsList IS LIST("m", "m", "m").

    LOCAL vel IS getRelativeVelocity().
    LOCAL pos IS getRelativePosition().
    LOCAL eff IS V(SHIP:CONTROL:FORE, SHIP:CONTROL:TOP, SHIP:CONTROL:STARBOARD).
    // One column less than the terminal has: a line that fills a row to the last column makes the terminal start a new line, which on the
    // last row scrolls the whole screen up, so nothing is printed in the last column.
    LOCAL terminalWidth IS TERMINAL:WIDTH - 1.
    LOCAL hasSetpoints IS setpointList:LENGTH = 3.

    LOCAL velSetpoints IS LIST(velocityPIDLoop[0]["PID"]:SETPOINT, velocityPIDLoop[1]["PID"]:SETPOINT, velocityPIDLoop[2]["PID"]:SETPOINT).

    // The columns, with two spaces between every one of them: the axis label, then a value and its unit for distance, velocity, the
    // velocity loop's setpoint and the RCS output, then the setpoint and its unit.
    // The output column holds its value (6 wide) and its % as one cell, with a single space between them.
    LOCAL columnWidths IS LIST(7, 8, 1, 8, 3, 7, 3, 8, 8, 5).
    LOCAL columnRight IS LIST(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE, FALSE, FALSE, TRUE, FALSE).
    LOCAL usedColumns IS 8.
    IF hasSetpoints SET usedColumns TO 10.

    // each heading ends over the right edge of its values, in columns of the same widths as the rows
    LOCAL headerCells IS LIST("", "Distance", "", "Velocity", "", "Vel SP", "", "Output":PADLEFT(6) + "  ", "Setpoint", "").
    PRINT formatTableRow(headerCells, columnWidths, columnRight, usedColumns):PADRIGHT(terminalWidth) AT (0, 3).

    LOCAL axisRowLabels IS LIST("  Fore", "  Top", "  Stbd").
    LOCAL posComponents IS LIST(pos:X, pos:Y, pos:Z).
    LOCAL velComponents IS LIST(vel:X, vel:Y, vel:Z).
    LOCAL effComponents IS LIST(eff:X, eff:Y, eff:Z).

    LOCAL i IS 0.
    UNTIL i >= 3 {
        LOCAL rowCells IS LIST(axisRowLabels[i],
            ROUND(posComponents[i], 2):TOSTRING, "m",
            ROUND(velComponents[i], 3):TOSTRING, "m/s",
            ROUND(velSetpoints[i], 3):TOSTRING, "m/s",
            ROUND(100 * effComponents[i], 1):TOSTRING:PADLEFT(6) + " %", "", "").
        IF hasSetpoints {
            SET rowCells[8] TO ROUND(setpointList[i], 2):TOSTRING.
            SET rowCells[9] TO unitsList[i].
        }
        PRINT formatTableRow(rowCells, columnWidths, columnRight, usedColumns):PADRIGHT(terminalWidth) AT (0, 4 + i).
        SET i TO i + 1.
    }

    LOCAL totalCells IS LIST("  Total",
        ROUND(pos:MAG, 2):TOSTRING, "m",
        ROUND(vel:MAG, 3):TOSTRING, "m/s",
        ROUND(PIDListDistance(velSetpoints, LIST(0, 0, 0)), 3):TOSTRING, "m/s",
        ROUND(100 * eff:MAG, 1):TOSTRING:PADLEFT(6) + " %", "", "").
    PRINT formatTableRow(totalCells, columnWidths, columnRight, usedColumns):PADRIGHT(terminalWidth) AT (0, 7).
    PRINT ("  Mode " + currentStageLabel):PADRIGHT(terminalWidth) AT (0, 8).
    PRINT " ":PADRIGHT(terminalWidth) AT (0, 9).
    IF hasSetpoints {
        LOCAL facingText IS "same way as target".
        IF facingAway SET facingText TO "away from target".
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 10).
        PRINT ("  [Q] face same way  [A] face away (now " + facingText + ")   [X/ESC] exit"):PADRIGHT(terminalWidth) AT (0, 11).
        PRINT ("  Any other key cancels auto mode and holds the position"):PADRIGHT(terminalWidth) AT (0, 12).
    } ELSE {
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 10).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 11).
        PRINT " ":PADRIGHT(terminalWidth) AT (0, 12).
    }
    PRINT " ":PADRIGHT(terminalWidth) AT (0, 13).
    PRINT " ":PADRIGHT(terminalWidth) AT (0, 14).

    PRINT "  Messages:":PADRIGHT(terminalWidth) AT (0, 15).
    // each message keeps its row until a later one takes its place, oldest first, so nothing scrolls; once the rows are full the row
    // after the newest message is shown blank, which is where the next one will go
    LOCAL slot IS 0.
    LOCAL gapSlot IS -1.
    IF statusMessages:LENGTH >= maxStatusMessages SET gapSlot TO MOD(latestStatusSlot + 1, maxStatusMessages).
    UNTIL slot >= maxStatusMessages {
        LOCAL lineText IS " ".
        IF slot < statusMessages:LENGTH AND slot <> gapSlot SET lineText TO "  " + statusMessages[slot].
        // a message longer than the row would wrap onto the next row, and the last row would scroll the screen, so cut it off
        IF lineText:LENGTH > terminalWidth SET lineText TO lineText:SUBSTRING(0, terminalWidth).
        PRINT lineText:PADRIGHT(terminalWidth) AT (0, 16 + slot).
        SET slot TO slot + 1.
    }
}

// logStatus
// Inputs:
//   message (String) - one line of status text.
// Outputs:
//   None.
// Side Effects:
//   Puts message in the next free row of the message log, or in place of the oldest message once the rows are full (so nothing
//   scrolls), then calls printStatus() so it shows at once.
FUNCTION logStatus {
    PARAMETER message.
    IF statusMessages:LENGTH < maxStatusMessages {
        statusMessages:ADD(message).
        SET latestStatusSlot TO statusMessages:LENGTH - 1.
    } ELSE {
        SET latestStatusSlot TO MOD(latestStatusSlot + 1, maxStatusMessages).
        SET statusMessages[latestStatusSlot] TO message.
    }
    printStatus().
}

// Reasons to stop early: the docking is finished (more parts than at the start), the target is lost, or it rotates faster than
// maxTargetRotation relative to an attitude that faces its body.
LOCAL maxTargetRotation IS 0.5 * 2 * CONSTANT:PI / 60. // half a revolution per minute, in radians per second
LOCAL rotationDebounceTime IS 2. // seconds the target must keep rotating too fast before the script stops
LOCAL startPartCount IS SHIP:PARTS:LENGTH.
LOCAL abortReason IS "". // set by checkAbort() when the script must stop; "" while it may carry on
LOCAL rotationExceededSince IS -1.

// getTargetRotationExcess
// Inputs:
//   None.
// Outputs:
//   Scalar - rad/s, how fast the target's rotation differs from the rotation of its position around the body it orbits, which is
//   the rotation of an attitude that always faces the body. 0 if HASTARGET is FALSE. The target's angular velocity is read in the
//   ship-raw frame, which may turn with the body at low altitude, so the result can be off by up to the body's own rotation rate
//   (a small fraction of the limit). The angular velocity and the orbital rate are in the same frame and handedness, so a
//   target holding an attitude facing the body gives about 0 and a tumbling target gives its tumble rate.
// Side Effects:
//   None.
FUNCTION getTargetRotationExcess {
    IF NOT HASTARGET { RETURN 0. }

    // a docking port is a part; its vessel is what rotates and orbits
    LOCAL targetVessel IS TARGET.
    IF TARGET:ISTYPE("Part") OR TARGET:ISTYPE("DockingPort") SET targetVessel TO TARGET:SHIP.

    LOCAL radius IS targetVessel:POSITION - SHIP:BODY:POSITION.
    LOCAL orbitalRate IS VCRS(radius, targetVessel:VELOCITY:ORBIT) / radius:SQRMAGNITUDE.
    RETURN (targetVessel:ANGULARVEL - orbitalRate):MAG.
}

// checkAbort
// Inputs:
//   rotationDebounce (Scalar, seconds) - how long the target must keep rotating too fast before that counts; 0 counts it at once.
// Outputs:
//   Boolean - TRUE if the script must stop, in which case abortReason says why. It stays TRUE on later calls.
// Side Effects:
//   Sets abortReason and rotationExceededSince. The checks, in order: the ship has more parts than at the start (docking is
//   complete); there is no target any more; the target has rotated faster than maxTargetRotation for rotationDebounce seconds.
FUNCTION checkAbort {
    PARAMETER rotationDebounce.

    IF abortReason <> "" { RETURN TRUE. }

    // docking merges the two ships, so this must be checked before the target is found to be gone
    IF SHIP:PARTS:LENGTH > startPartCount {
        SET abortReason TO "Docking complete".
        RETURN TRUE.
    }
    IF NOT HASTARGET {
        SET abortReason TO "Docking aborted: target unselected".
        RETURN TRUE.
    }

    LOCAL excess IS getTargetRotationExcess().
    IF excess > maxTargetRotation {
        IF rotationExceededSince < 0 { SET rotationExceededSince TO TIME:SECONDS. }
        IF TIME:SECONDS - rotationExceededSince >= rotationDebounce {
            SET abortReason TO "Docking aborted: target rotating too fast".
            RETURN TRUE.
        }
    } ELSE {
        SET rotationExceededSince TO -1.
    }
    RETURN FALSE.
}

// The onTick delegate for the libraryPID.ks autotune and cascade functions: shows the stage, logs a row and keeps the axes following
// the target. checkAbort() is not called while an autotune stage runs, only between stages and while docking.
LOCAL autotuneTick IS {
    PARAMETER stageLabel.
    updateTargetAxes().
    SET currentStageLabel TO stageLabel.
    printStatus().
    logRow().
}.

// Where the tunings are saved (the ship's own disk, so they go with the ship), and how far the maximum RCS acceleration on each axis
// may differ from when it was tuned before the saved tuning is not used. Spending propellant is fine; docking, staging, changed
// thrusters or a big mass change is not.
LOCAL velocityTuningPath IS "1:/velocityTuning.json".
LOCAL positionTuningPath IS "1:/positionTuning.json".
LOCAL maxAccelRatioLow IS 0.5.
LOCAL maxAccelRatioHigh IS 2.

// Tuning costs RCS propellant: about 3 m/s of delta-v per m/s of step per axis on the position loop, and at most the relay amplitude
// times the maximum acceleration times the time limit per axis on the velocity loop. A loop is only tuned if the delta-v left covers
// that times rcsTuningMargin and still leaves rcsReserveDeltaV.
LOCAL rcsTuningMargin IS 1.5.

// How each loop's tuning was obtained, which goes in the CSV: "none yet", "loaded", "tuned and saved",
// "tuned but NOT saved", "derived from velocity tuning", "failed" or "skipped (RCS reserve)".
LOCAL tuningStatus IS LEXICON("velocity", "none yet", "position", "none yet").

// RCS commands smaller than this fraction of full thrust are not sent while docking: tiny commands change sign with the noise and
// would fire the thrusters both ways, wasting propellant.
LOCAL rcsEffortDeadband IS 0.03.

// loadSavedTuning
// Inputs:
//   axes (LIST of axes) - the loop to load the tuning into, velocityPIDLoop or positionPIDLoop.
//   filePath (String) - the file that loop's tuning was saved to.
//   loopName (String) - "velocity" or "position", for the messages.
//   Reads the file-scope facingAway, maxAccelRatioLow and maxAccelRatioHigh.
// Outputs:
//   Boolean - TRUE if a saved tuning was found, still fits the ship and was applied to axes; FALSE if the ship must be tuned. The
//   reason it was not used is logged either way.
// Side Effects:
//   On success, replaces the tuning and gains of axes with the saved ones. Calls logStatus().
FUNCTION loadSavedTuning {
    PARAMETER axes.
    PARAMETER filePath.
    PARAMETER loopName.

    IF NOT EXISTS(filePath) {
        logStatus("No saved " + loopName + " tuning, so tuning now.").
        RETURN FALSE.
    }

    LOCAL saved IS PIDTuningRead(filePath).
    IF saved:LENGTH = 0 {
        logStatus("The saved " + loopName + " tuning is in a format that cannot be used, so tuning now.").
        RETURN FALSE.
    }
    LOCAL context IS saved["context"].
    IF NOT (context:HASKEY("facingAway") AND context:HASKEY("signature")) {
        logStatus("The saved " + loopName + " tuning does not say what ship it was for, so tuning now.").
        RETURN FALSE.
    }

    // facing the other way round reverses the fore and starboard axes, and so the signs of their gains
    IF context["facingAway"] <> facingAway {
        logStatus("The saved " + loopName + " tuning was made facing the other way round, so tuning now.").
        RETURN FALSE.
    }
    LOCAL problem IS getRCSSignatureProblem(context["signature"], getRCSSignature(getMaxAccel()), maxAccelRatioLow, maxAccelRatioHigh).
    IF problem <> "" {
        logStatus("Not using the saved " + loopName + " tuning: " + problem + ", so tuning now.").
        RETURN FALSE.
    }

    IF NOT PIDAxesApplyTuning(axes, saved) {
        logStatus("The saved " + loopName + " tuning does not fit the loop, so tuning now.").
        RETURN FALSE.
    }
    logStatus("Using the saved " + loopName + " tuning, made " + timeToString(TIME:SECONDS - saved["savedAt"]) + " ago on this ship as it is now.").

    SET tuningStatus[loopName] TO "loaded".
    RETURN TRUE.
}

// saveTuning
// Inputs:
//   axes (LIST of axes) - the tuned loop, velocityPIDLoop or positionPIDLoop.
//   filePath (String) - the file to save its tuning to.
//   loopName (String) - "velocity" or "position", for the messages.
//   Reads the file-scope facingAway.
// Outputs:
//   None.
// Side Effects:
//   Writes the tuning of axes to filePath, together with which way round the ship is facing and its RCS signature
//   (getRCSSignature()), so loadSavedTuning() can tell later whether it still applies. Logs whether that worked.
FUNCTION saveTuning {
    PARAMETER axes.
    PARAMETER filePath.
    PARAMETER loopName.

    LOCAL context IS LEXICON("facingAway", facingAway, "signature", getRCSSignature(getMaxAccel())).
    IF PIDAxesSaveTuning(axes, filePath, context) {
        SET tuningStatus[loopName] TO "tuned and saved".
        logStatus("Saved the " + loopName + " tuning to " + filePath + ".").
    } ELSE {
        SET tuningStatus[loopName] TO "tuned but NOT saved".
        logStatus("WARNING: could not save the " + loopName + " tuning to " + filePath + " (disk free: " + CORE:VOLUME:FREESPACE + " of " + CORE:VOLUME:CAPACITY + " bytes).").
    }
}

// checkRCSForTuning
// Inputs:
//   tuningCost (Scalar) - the estimated RCS delta-v, m/s, that tuning the loop will use.
//   loopName (String) - "velocity" or "position", for the messages.
//   Reads the file-scope rcsTuningMargin and rcsReserveDeltaV.
// Outputs:
//   Boolean - TRUE if the loop can be tuned: the RCS delta-v that shipInfo reports for the current stage is at least tuningCost *
//   rcsTuningMargin + rcsReserveDeltaV, or shipInfo reports no RCS propellant at all (so there is nothing to check against, which
//   is logged). FALSE if it is not, with abortReason set so that the script stops and says why.
// Side Effects:
//   Refreshes the resources in shipInfo. Calls logStatus().
FUNCTION checkRCSForTuning {
    PARAMETER tuningCost.
    PARAMETER loopName.

    updateShipInfoResources(FALSE).
    LOCAL stageInfo IS shipInfo["CurrentStage"].
    IF stageInfo["fuelRCSMass"] <= 0 OR stageInfo["IspRCS"] <= 0 {
        logStatus("RCS propellant unknown, " + loopName + " tuning unchecked").
        RETURN TRUE.
    }

    LOCAL available IS stageInfo["DeltaVRCS"].
    LOCAL required IS tuningCost * rcsTuningMargin + rcsReserveDeltaV.
    IF available < required {
        SET abortReason TO "Docking aborted: RCS reserve too low".
        SET tuningStatus[loopName] TO "skipped (RCS reserve)".
        logStatus("RCS " + ROUND(available, 1) + " m/s, " + loopName + " tuning needs " + ROUND(required, 1) + " m/s").
        RETURN FALSE.
    }
    logStatus("RCS " + ROUND(available, 1) + " m/s, " + loopName + " tuning costs about " + ROUND(tuningCost, 1) + " m/s").
    RETURN TRUE.
}

// drawArrow
// Inputs:
//   arrowLabel (String) - the text shown beside the arrow.
//   arrowColor (Color) - the colour of the arrow.
//   startGetter (Delegate, () -> Vector) - where the arrow starts, called every frame.
//   vectorGetter (Delegate, () -> Vector) - the arrow itself, called every frame.
// Outputs:
//   None.
// Side Effects:
//   Draws an arrow in the game view until CLEARVECDRAWS().
FUNCTION drawArrow {
    PARAMETER arrowLabel.
    PARAMETER arrowColor.
    PARAMETER startGetter.
    PARAMETER vectorGetter.

    LOCAL arrow IS VECDRAW(V(0,0,0), V(0,0,0), arrowColor, arrowLabel, 1.0, TRUE, 0.2).
    SET arrow:STARTUPDATER TO startGetter.
    SET arrow:VECUPDATER TO vectorGetter.
}

// getStartProblem
// Inputs:
//   maxDistance (Scalar, metres) - the furthest the target may be.
// Outputs:
//   String - why the docking cannot start, or "" if it can. The checks, in order: there is a target; it is a vessel or docking port;
//   it is within maxDistance; the control part is a docking port or grabbing arm; the RCS can thrust along every axis; and, if the
//   target is a docking port: it is on another vessel, it is ready, it is the same size as the control port (not checked for a
//   grabbing arm) and the ship is in front of it.
// Side Effects:
//   None.
FUNCTION getStartProblem {
    PARAMETER maxDistance.

    IF NOT HASTARGET { RETURN "no target". }
    IF NOT (TARGET:ISTYPE("Vessel") OR TARGET:ISTYPE("DockingPort")) { RETURN "target is a " + TARGET:TYPENAME + ", not a vessel or docking port". }
    IF TARGET:POSITION:MAG > maxDistance { RETURN "target too far away". }

    LOCAL controlPart IS SHIP:CONTROLPART.
    LOCAL isGrapple IS controlPart:HASMODULE("ModuleGrappleNode").
    IF NOT (isGrapple OR controlPart:ISTYPE("DockingPort")) { RETURN "control part (" + controlPart:TITLE + ") is not a docking port or grabbing arm". }

    LOCAL thrust IS getMaxAccel().
    IF thrust:X <= 0 OR thrust:Y <= 0 OR thrust:Z <= 0 { RETURN "RCS has no thrust along Fore, Top or Starboard". }

    IF TARGET:ISTYPE("DockingPort") {
        IF TARGET:SHIP = SHIP { RETURN "target port is on this ship". }
        IF TARGET:STATE <> "Ready" { RETURN "target port is not ready (" + TARGET:STATE + ")". }
        IF NOT isGrapple AND controlPart:NODETYPE <> TARGET:NODETYPE { RETURN "port sizes differ (" + controlPart:NODETYPE + " and " + TARGET:NODETYPE + ")". }
        // the port's facing points out of its face, so the ship has to be on that side of it
        IF VDOT(controlPart:POSITION - TARGET:POSITION, TARGET:FACING:FOREVECTOR) <= 0 { RETURN "ship is behind the target port's face". }
    }
    RETURN "".
}

// -----------------------------------------------------------------
// MAIN
// -----------------------------------------------------------------
CLEARSCREEN.
// the script does not start if the target is further away than this, metres
LOCAL maxDockingStartDistance IS 1000.
SET scriptStartTime TO TIME:SECONDS.
startLogFile().

logStatus("=== CASCADED 3-AXIS PID AUTOTUNE + AUTO DOCKING ===").

LOCAL startProblem IS getStartProblem(maxDockingStartDistance).
IF startProblem <> "" {
    LOCAL startMessage IS "Docking aborted: " + startProblem.
    logStatus(startMessage).
    // the status log is gone once the script ends and loop.ks takes the terminal back, so say why it stopped in the loop message too
    SET loopMessage TO startMessage.
} ELSE {
    // the RCS propellant limit reads shipInfo, which describes the ship as it was when it was last built
    updateShipInfo().

    LOCAL innerRelaySetpoint IS LIST(0, 0, 0).
    LOCAL innerRelayAmplitudeFraction IS 0.5.
    LOCAL innerRelayHysteresis IS LIST(0.05, 0.05, 0.05).
    LOCAL relaySettleCycles IS 1. // fewer cycles than before (2 and 4) because every cycle costs RCS propellant
    LOCAL relayMeasureCycles IS 3.
    LOCAL innerRelayMaxDuration IS 40.
    // the position loop step test is used only if usePositionStepTest is TRUE; otherwise Kp is derived (see the Tuning Position stage)
    LOCAL outerStepSpeed IS 0.5. // m/s of each axis's step, which is the sign that moves the ship toward zero position (see the stage)
    LOCAL outerStepAttempts IS 3. // the whole test is repeated up to this many times if it fails
    LOCAL outerStepMinFore IS 15. // metres: Fore only steps toward the target if this much is still left after every attempt's step
    LOCAL positionTimeConstantFactor IS 1.5. // derived Kp = 1 / (this * the velocity loop's ultimate period Pu)
    LOCAL positionKpDefault IS 0.25. // 1/s, used if the velocity tuning has no Pu
    LOCAL positionKpMin IS 0.1. // 1/s
    LOCAL positionKpMax IS 0.5. // 1/s
    LOCAL outerStepPreSettleDuration IS 3.
    LOCAL outerStepHoldDuration IS 10.
    LOCAL outerStepRegressionFraction IS 0.5.
    LOCAL outerLambdaFactor IS 3.
    LOCAL outerLambdaMin IS 1.
    // how much of the maximum acceleration the position loop counts on for braking; the rest is left for the velocity loop
    LOCAL positionBrakeFraction IS 0.5.
    // the position loop top speed, as a multiple of the maximum acceleration; a lower value saves RCS propellant on long moves but
    // takes longer
    LOCAL positionMaxSpeedFactor IS 2.
    // the position loop speed is also limited so one move with all three axes at that speed uses at most this fraction of the RCS
    // propellant that is left (see getRCSSpeedLimit()); the limit is worked out again every fuelLimitRefreshTime seconds
    LOCAL fuelLimitRefreshTime IS 5.
    // the position loop Ki is this fraction of Kp^2 / 4 (the largest value that does not overshoot); the integral only builds up
    // within positionIntegralWindow metres of the setpoint
    LOCAL positionIntegralFraction IS 0.5.
    LOCAL positionIntegralWindow IS 1.
    // Auto mode starts when the tuning is done. Fore only arrives still moving if the ship is within autoArrivalDistance of the Top
    // and Starboard setpoints; otherwise it arrives stopped and waits.
    LOCAL autoArrivalDistance IS 0.25. // metres
    LOCAL rotationSettleThreshold IS 0.01.
    LOCAL rotationSettleTimeout IS 30.

    // Chooses whether the ship faces the same way as the target or away from it, and sets the axes the control works in
    // accordingly (updateTargetAxes() then keeps them following the target every tick).
    LOCAL applyFacing IS {
        PARAMETER faceAway.
        SET facingAway TO faceAway.
        updateTargetAxes().
    }.
    applyFacing(TRUE).

    // kOS runs these updaters every frame, whatever the script is doing, and the target is gone as soon as the docking finishes, so
    // the ones that use TARGET must cope with having none.
    LOCAL fromShip IS {RETURN SHIP:CONTROLPART:POSITION.}.
    drawArrow("Fore", YELLOW, fromShip, {RETURN foreDirectionVector * 5.0.}).
    drawArrow("Top", RED, fromShip, {RETURN topDirectionVector * 5.0.}).
    drawArrow("Starboard", BLUE, fromShip, {RETURN starboardDirectionVector * 5.0.}).
    drawArrow("Target", GREEN, fromShip, {IF NOT HASTARGET { RETURN V(0,0,0). } RETURN TARGET:POSITION - SHIP:CONTROLPART:POSITION.}).
    drawArrow("Target Facing", PURPLE, {IF NOT HASTARGET { RETURN V(0,0,0). } RETURN TARGET:POSITION.}, {IF NOT HASTARGET { RETURN V(0,0,0). } RETURN TARGET:FACING:VECTOR * 5.0.}).
    drawArrow("Velocity", WHITE, fromShip, {LOCAL relVel IS getRelativeVelocity(). RETURN -1 * (relVel:X * foreDirectionVector + relVel:Y * topDirectionVector + relVel:Z * starboardDirectionVector).}).

    // Check the target before the RCS is switched on, so a target that is already rotating too fast costs no propellant.
    LOCAL mode IS "setup".
    IF checkAbort(0) {
        logStatus(abortReason).
        SET mode TO "done".
    }

    IF mode <> "done" {
        RCS ON.
        SET globalSteer TO LOOKDIRUP(foreDirectionVector, topDirectionVector).
        setLockedSteering(TRUE).
	WAIT 2.
    }

	// The plant functions and the relative readings work on vectors; libraryPID.ks works on lists, one element per axis.
	LOCAL velocityGetter IS vectorGetterAsList(getRelativeVelocity@).
	LOCAL positionGetter IS vectorGetterAsList(getRelativePosition@).
	LOCAL plantEffortActuator IS vectorActuatorAsList(applyPlantEffort@).
	LOCAL rcsAccelActuator IS vectorActuatorWithLimitsAsList(applyDockingAccel@).
	LOCAL innerActuatorDelegate IS applyViaInnerLoop@:BIND(velocityPIDLoop, rcsAccelActuator, vectorGetterAsList(getMaxAccel@), velocityGetter).
	LOCAL outerResult IS LEXICON().

	LOCAL setpointList IS LIST(0, 0, 0). // metres Fore, Top, Starboard; while auto mode runs, Fore is a velocity in m/s
	LOCAL tempChar IS "".
	LOCAL currentVel IS getRelativeVelocity().
	LOCAL currentPos IS getRelativePosition().
	LOCAL maxAccel IS getMaxAccel().
	LOCAL rotationWaitStart IS TIME:SECONDS.
	LOCAL fuelSpeedLimit IS -1. // the top speed that the RCS propellant allows, m/s; -1 until it is worked out, or if it cannot be
	LOCAL fuelLimitUpdatedAt IS TIME:SECONDS - fuelLimitRefreshTime.
	LOCAL fuelLimitLogged IS FALSE.
	LOCAL autoClosing IS FALSE. // TRUE while auto mode is closing in on the port, which loosens the lateral tolerance
	LOCAL autoMode IS "off".// "on" while auto mode runs; "off" before it starts and after it is cancelled, when the ship holds its position
	LOCAL autoDefault IS LIST(0, 0, 0). // the default position that auto mode goes to, set when it starts

	// Ends auto mode and holds the ship where it is, in position control. Any key does this, and so does changing the facing.
	LOCAL cancelAutoMode IS {
		SET autoMode TO "off".
		PIDAxesReset(positionPIDLoop).
		SET setpointList TO vectorToList(getRelativePosition()).
		logStatus("Auto Mode Cancelled").
	}.

    UNTIL mode = "done" {
        IF checkAbort(rotationDebounceTime) {
            logStatus(abortReason).
            SET mode TO "done".
            // Do nothing else this tick. After a docking the two ships have only just merged, and the archive (where the logs go) may
            // not be reachable yet.
            BREAK.
        }

        // the target turns, so the axes that everything below is measured in have to turn with it
        updateTargetAxes().

		SET maxAccel TO getMaxAccel().
		SET currentVel TO getRelativeVelocity().
		SET currentPos TO getRelativePosition().
		logRow().

			// [Q] and [A] choose whether the ship faces the same way as the target or away. Not available while an autotune stage runs.
		LOCAL facingKey IS tempChar:TOLOWER().
		IF (mode = "setup" OR mode = "Docking") AND (facingKey = "q" OR facingKey = "a") {
			LOCAL wantAway IS (facingKey = "a").
			IF wantAway <> facingAway {
				applyFacing(wantAway).
				SET rotationWaitStart TO TIME:SECONDS.
				IF mode = "Docking" {
					// the fore and starboard axes have turned around, so the same wanted motion has the opposite sign on them
					SET setpointList[0] TO -setpointList[0].
					SET setpointList[2] TO -setpointList[2].
					PIDAxesReset(velocityPIDLoop).
					PIDAxesReset(positionPIDLoop).
				}
				SET currentVel TO getRelativeVelocity().
				SET currentPos TO getRelativePosition().
				IF autoMode <> "off" { cancelAutoMode(). }
				IF wantAway logStatus("Facing away from the target's facing.").
				ELSE logStatus("Facing the same way as the target's facing.").
			}
			SET tempChar TO "".
		}

		// Wait for steering to stabilize
        IF mode = "setup" {
            IF (SHIP:ANGULARVEL:MAG < rotationSettleThreshold) OR (TIME:SECONDS - rotationWaitStart >= rotationSettleTimeout) {
				SET mode TO "Tuning Velocity".
            }

        } ELSE IF mode = "Tuning Velocity" {
            LOCAL velocityTuned IS FALSE.
            IF forceRetune {
                logStatus("Retuning was requested, so any saved tuning is ignored.").
            } ELSE {
                SET velocityTuned TO loadSavedTuning(velocityPIDLoop, velocityTuningPath, "velocity").
            }

            LOCAL canTuneVelocity IS TRUE.
            IF NOT velocityTuned {
                SET canTuneVelocity TO checkRCSForTuning((maxAccel:X + maxAccel:Y + maxAccel:Z) * innerRelayAmplitudeFraction * innerRelayMaxDuration, "velocity").
            }

            IF NOT velocityTuned AND canTuneVelocity {
                logStatus("Stage 1: relay-tuning the velocity PID loop (per axis, simultaneously)...").

                LOCAL innerRelayAmp IS maxAccel * innerRelayAmplitudeFraction.
                LOCAL innerResult IS PIDRelayAutotuneRetry(velocityPIDLoop, velocityGetter, plantEffortActuator, innerRelaySetpoint, vectorToList(innerRelayAmp), "innerRelay", innerRelayHysteresis, relaySettleCycles, relayMeasureCycles, innerRelayMaxDuration, 3, FALSE, autotuneTick, logStatus@).

                logStatus("  inner Ku=" + PIDFormatList(innerResult["Ku"], 4) + "  Pu=" + PIDFormatList(innerResult["Pu"], 4)).
                SET velocityTuned TO innerResult["success"].
                IF NOT velocityTuned { SET tuningStatus["velocity"] TO "failed". }
                IF velocityTuned {
                    saveTuning(velocityPIDLoop, velocityTuningPath, "velocity").
                    // the position loop was tuned with the old velocity loop, so its saved tuning no longer fits
                    IF EXISTS(positionTuningPath) { DELETEPATH(positionTuningPath). }
                }
            }

            LOCAL innerGains IS PIDAxesGetGains(velocityPIDLoop).
            logStatus("  inner Kp=" + PIDFormatList(innerGains["kp"], 4) + "  Ki=" + PIDFormatList(innerGains["ki"], 4) + "  Kd=" + PIDFormatList(innerGains["kd"], 4)).

            IF NOT velocityTuned {
                IF abortReason = "" { SET abortReason TO "Docking aborted: velocity tuning failed". }
                SET mode TO "done".
            } ELSE {
                SET mode TO "Tuning Position".
            }

        } ELSE IF mode = "Tuning Position" {
            LOCAL positionTuned IS FALSE.
            LOCAL canTunePosition IS TRUE.
            IF NOT usePositionStepTest {
                // No step test, so no RCS propellant is spent: Kp comes from the velocity tuning. A P loop on an integrating plant
                // approaches its setpoint with time constant 1 / Kp, which must stay well above what the velocity loop can follow, so use
                // 1 / (positionTimeConstantFactor * Pu), from the relay test, kept between positionKpMin and positionKpMax.
                LOCAL derivedKps IS LIST().
                LOCAL axisIndex IS 0.
                UNTIL axisIndex >= 3 {
                    LOCAL derivedKp IS positionKpDefault.
                    LOCAL ultimatePeriod IS velocityPIDLoop[axisIndex]["tune"]["Pu"].
                    IF ultimatePeriod > 0 { SET derivedKp TO 1 / (positionTimeConstantFactor * ultimatePeriod). }
                    derivedKps:ADD(MAX(positionKpMin, MIN(positionKpMax, derivedKp))).
                    SET axisIndex TO axisIndex + 1.
                }
                PIDAxesSetGains(positionPIDLoop, derivedKps, PIDFilledList(3, 0), PIDFilledList(3, 0)).
                SET positionTuned TO TRUE.
                SET tuningStatus["position"] TO "derived from velocity tuning".
                logStatus("Stage 2: position gains derived from the velocity tuning (no step test)").
            } ELSE {
                IF NOT forceRetune {
                    SET positionTuned TO loadSavedTuning(positionPIDLoop, positionTuningPath, "position").
                }

                // Each axis steps toward zero position, so little has to be undone afterwards. Fore steps toward the target only if
                // outerStepMinFore metres are still left after every attempt, otherwise away from it.
                LOCAL startPos IS vectorToList(getRelativePosition()).
                LOCAL stepExcursion IS outerStepSpeed * outerStepHoldDuration * outerStepAttempts.
                LOCAL stepSpeeds IS LIST().
                LOCAL stepAxis IS 0.
                UNTIL stepAxis >= 3 {
                    // the target moves toward the ship when the ship moves toward it, so the step has the opposite sign to the position
                    LOCAL stepSign IS 1.
                    IF startPos[stepAxis] > 0 { SET stepSign TO -1. }
                    IF stepAxis = 0 AND ABS(startPos[0]) - stepExcursion < outerStepMinFore { SET stepSign TO -stepSign. }
                    stepSpeeds:ADD(stepSign * outerStepSpeed).
                    SET stepAxis TO stepAxis + 1.
                }

                IF NOT positionTuned {
                    SET canTunePosition TO checkRCSForTuning(3 * 3 * outerStepSpeed, "position").
                }
                IF NOT positionTuned AND canTunePosition {
                    logStatus("Stage 2: tuning the outer PID loop (cascade active)...").
                    SET outerResult TO PIDIntegratingAutotuneRetry(positionPIDLoop, positionGetter, innerActuatorDelegate, stepSpeeds, "outerLambda", outerStepPreSettleDuration, outerStepHoldDuration, outerStepRegressionFraction, outerLambdaFactor, outerLambdaMin, outerStepAttempts, FALSE, 0, 0, autotuneTick, logStatus@).
                    SET positionTuned TO outerResult["success"].
                    IF positionTuned { saveTuning(positionPIDLoop, positionTuningPath, "position"). }
                    ELSE { SET tuningStatus["position"] TO "failed". }
                }
            }

            // The plant is already an integrator, so an integral term can only cause overshoot, but a little removes the offset that a
            // small steady velocity error leaves. The loop does not overshoot while Ki <= Kp^2 / 4, so use a fraction of that.
            LOCAL outerGains IS PIDAxesGetGains(positionPIDLoop).
            LOCAL outerKis IS LIST().
            FOR kpValue IN outerGains["kp"] {
                outerKis:ADD(positionIntegralFraction * kpValue^2 / 4).
            }
            PIDAxesSetGains(positionPIDLoop, outerGains["kp"], outerKis, outerGains["kd"]).
            SET outerGains TO PIDAxesGetGains(positionPIDLoop).
            logStatus("  outer Kp=" + PIDFormatList(outerGains["kp"], 4) + "  Ki=" + PIDFormatList(outerGains["ki"], 4) + "  Kd=" + PIDFormatList(outerGains["kd"], 4)).

            IF NOT positionTuned {
                IF canTunePosition { logStatus("ERROR! Outer loop failed to autotune after retries - aborting."). }
                IF abortReason = "" { SET abortReason TO "Docking aborted: position tuning failed". }
                SET mode TO "done".
            } ELSE {
                logStatus("Stage 3: flying with the tuned loops.").

                // Auto mode: Top and Starboard hold the default position while Fore goes there and carries on toward the target at
                // autoApproachSpeed. Any key but X/ESC cancels it and the ship holds where it is.
                logStatus("Auto Mode Enabled").
                SET mode TO "Docking".
                PIDAxesReset(positionPIDLoop).
                SET autoDefault TO getDefaultPosition().
                SET setpointList TO LIST(0, autoDefault[1], autoDefault[2]).
                SET autoMode TO "on".
                // keys that were pressed during the tuning should not cancel it
                UNTIL NOT TERMINAL:INPUT:HASCHAR {
                    TERMINAL:INPUT:GETCHAR().
                }
            }

        } ELSE IF mode = "Docking" {
			// the speed that the RCS propellant allows is worked out again every few seconds, because the propellant is being used up
			IF TIME:SECONDS - fuelLimitUpdatedAt >= fuelLimitRefreshTime {
				updateShipInfoResources(FALSE).
				SET fuelSpeedLimit TO getRCSSpeedLimit(rcsPropellantFraction, 3).
				SET fuelLimitUpdatedAt TO TIME:SECONDS.
				IF fuelSpeedLimit >= 0 AND NOT fuelLimitLogged {
					logStatus("RCS propellant limits speed to " + ROUND(fuelSpeedLimit, 2) + " m/s").
					SET fuelLimitLogged TO TRUE.
				}
			}

			// The position loop output (the velocity setpoint) is limited to positionMaxSpeedFactor times the maximum acceleration, to the
			// speed from which braking at positionBrakeFraction of the maximum acceleration still stops at the setpoint, and to fuelSpeedLimit.
			LOCAL positionSpeedLimits IS vectorToList(maxAccel * positionMaxSpeedFactor).
			IF fuelSpeedLimit >= 0 {
				SET positionSpeedLimits TO LIST(MIN(positionSpeedLimits[0], fuelSpeedLimit), MIN(positionSpeedLimits[1], fuelSpeedLimit), MIN(positionSpeedLimits[2], fuelSpeedLimit)).
			}

			// The keys: X or ESC exits, and any other key cancels auto mode, which leaves the ship holding the position that it is at.
			IF tempChar <> "" {
				IF tempChar:TOLOWER() = "x" OR tempChar = escapeChar {
					SET abortReason TO "Docking aborted: operator exit".
					SET mode TO "done".
				} ELSE IF autoMode <> "off" {
					cancelAutoMode().
				}
			}

			// Auto mode: Top and Starboard hold the default position with the position loop. Fore uses a velocity setpoint instead: the
			// fastest speed from which braking reaches the default Fore position at finalSpeed, so the ship carries straight on without
			// stopping and starting again, which saves RCS propellant.
			LOCAL foreSign IS 1.
			IF NOT facingAway SET foreSign TO -1.
			LOCAL positionMask IS LIST(TRUE, TRUE, TRUE).
			IF autoMode = "on" {
				SET positionMask TO LIST(FALSE, TRUE, TRUE).
				// how far Fore still has to go to the default position, positive while the ship is further out than that
				LOCAL foreToGo IS foreSign * (currentPos:X - autoDefault[0]).
				// the lateral tolerance is wider once closing in, so Fore does not stutter at the edge
				LOCAL tolerance IS autoArrivalDistance.
				IF autoClosing SET tolerance TO 2 * autoArrivalDistance.
				LOCAL linedUp IS ABS(currentPos:Y - autoDefault[1]) <= tolerance AND ABS(currentPos:Z - autoDefault[2]) <= tolerance.
				SET autoClosing TO foreToGo <= 0 AND linedUp.
				// arrive still moving only if lined up with the port, otherwise arrive stopped
				LOCAL finalSpeed IS 0.
				IF linedUp { SET finalSpeed TO autoApproachSpeed. }
				LOCAL approachSpeed IS MIN(positionSpeedLimits[0], SQRT(finalSpeed^2 + 2 * maxAccel:X * positionBrakeFraction * MAX(foreToGo, 0))).
				// at or past the default Fore position without being lined up: stop and wait here while Top and Starboard keep converging
				IF foreToGo <= 0 AND NOT linedUp { SET approachSpeed TO 0. }
				// closing in means moving toward the target, so the target moves toward the ship: backwards along Fore
				SET setpointList TO LIST(-foreSign * approachSpeed, autoDefault[1], autoDefault[2]).
				IF foreToGo > 0 SET currentStageLabel TO "Auto: to default position (any key cancels)".
				ELSE IF linedUp SET currentStageLabel TO "Auto: closing in (any key cancels)".
				ELSE SET currentStageLabel TO "Auto: waiting for lateral alignment (any key cancels)".
			} ELSE {
				SET currentStageLabel TO "Holding position (X exits)".
			}

			LOCAL setpointUnits IS LIST("m", "m", "m").
			IF autoMode = "on" SET setpointUnits TO LIST("m/s", "m", "m").
			printStatus(setpointList, setpointUnits).

			// while the ship is turning to a new facing, its RCS axes are not the ones that the loops work in, so hold still
			IF VANG(SHIP:FACING:FOREVECTOR, foreDirectionVector) < 10 AND VANG(SHIP:FACING:TOPVECTOR, topDirectionVector) < 10 {
				cascadeStep(positionPIDLoop, velocityPIDLoop, vectorToList(currentPos), vectorToList(currentVel), setpointList, vectorToList(maxAccel), rcsAccelActuator, positionSpeedLimits, vectorToList(maxAccel * positionBrakeFraction), PIDFilledList(3, positionIntegralWindow), positionMask).
			} ELSE {
				PIDAxesReset(velocityPIDLoop).
				PIDAxesReset(positionPIDLoop).
				applyRCSAccel(V(0,0,0), maxAccel).
			}
		}
		SET tempChar TO "".
		UNTIL NOT TERMINAL:INPUT:HASCHAR {
			SET tempChar TO TERMINAL:INPUT:GETCHAR().
		}
    }

    // Stopping because of a docking (or anything else checkAbort() found): let a tick pass before touching anything else.
    IF abortReason <> "" { WAIT 0. }

    applyRCSAccel(V(0,0,0)).
    setLockedSteering(FALSE).
    RCS OFF.
    // the arrows are drawn from the target, which may be gone now, so take them all down
    CLEARVECDRAWS().

    // tell loop.ks why the script stopped
    IF abortReason <> "" {
        SET loopMessage TO abortReason.
    }
}
