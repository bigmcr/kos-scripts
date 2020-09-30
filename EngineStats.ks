@LAZYGLOBAL OFF.

LOCAL engineList IS 0.
LIST ENGINES IN engineList.
LOCAL engineCount IS 0.
LOCAL engineStats IS LEXICON().
LOCAL engineStat IS LEXICON().
LOCAL pressure IS SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:BODY:POSITION:MAG - SHIP:BODY:RADIUS).

FOR eachEngine IN engineList {
	SET engineStat TO LEXICON().
	engineStat:ADD("TITLE", eachEngine:TITLE).
	engineStat:ADD("THRUSTLIMIT", eachEngine:THRUSTLIMIT + ",%").
	engineStat:ADD("MAXTHRUST", eachEngine:MAXTHRUST + ",kN").
	engineStat:ADD("MAXTHRUSTAT(pressure)", eachEngine:MAXTHRUSTAT(pressure) + ",kN").
	engineStat:ADD("THRUST", eachEngine:THRUST + ",kN").
	engineStat:ADD("AVAILABLETHRUST", eachEngine:AVAILABLETHRUST + ",kN").
	engineStat:ADD("AVAILABLETHRUSTAT(pressure)", eachEngine:AVAILABLETHRUSTAT(pressure) + ",kN").
	engineStat:ADD("POSSIBLETHRUST", eachEngine:POSSIBLETHRUST + ",kN").
	engineStat:ADD("POSSIBLETHRUSTAT(pressure)", eachEngine:POSSIBLETHRUSTAT(pressure) + ",kN").
	engineStat:ADD("FUELFLOW", eachEngine:FUELFLOW + ",kg/s").
	engineStat:ADD("ISP", eachEngine:ISP + ",s").
	engineStat:ADD("ISPAT(pressure)", eachEngine:ISPAT(pressure) + ",s").
	engineStat:ADD("VACUUMISP", eachEngine:VACUUMISP + ",s").
	engineStat:ADD("VISP", eachEngine:VISP + ",s").
	engineStat:ADD("SEALEVELISP", eachEngine:SEALEVELISP + ",s").
	engineStat:ADD("SLISP", eachEngine:SLISP + ",s").
	engineStat:ADD("FLAMEOUT", eachEngine:FLAMEOUT).
	engineStat:ADD("IGNITION", eachEngine:IGNITION).
	engineStat:ADD("ALLOWRESTART", eachEngine:ALLOWRESTART).
	engineStat:ADD("ALLOWSHUTDOWN", eachEngine:ALLOWSHUTDOWN).
	engineStat:ADD("THROTTLELOCK", eachEngine:THROTTLELOCK).
	engineStat:ADD("MULTIMODE", eachEngine:MULTIMODE).
//	engineStat:ADD("MODES", eachEngine:MODES).
	engineStat:ADD("HASGIMBAL", eachEngine:HASGIMBAL).
	engineStats:ADD(eachEngine:UID, engineStat).
}

LOCAL message IS "Unique ID".

IF engineStats:LENGTH > 0 {
	FOR eachEngine IN engineStats:KEYS {
		SET message TO message + "," + eachEngine.
	}
	SET message TO message + CHAR(10).
	FOR eachStat IN engineStats[engineList[0]:UID]:KEYS {
		SET message TO message + eachStat.
		FOR eachEngine IN engineStats:KEYS {
			SET message TO message + "," + engineStats[eachEngine][eachStat].
		}
		SET message TO message + CHAR(10).
	}
	SET message TO message + "Throttle," + THROTTLE + CHAR(10).
	SET message TO message + "Pressure," + pressure + ",atms" + CHAR(10).
}
CLEARSCREEN.
PRINT "Engines.csv created on the archive".
SET loopMessage TO "Engines.csv created.".
LOG message TO "0:Engines.csv".
