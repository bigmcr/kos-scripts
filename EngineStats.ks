@LAZYGLOBAL OFF.

LOCAL engineList IS 0.
LIST ENGINES IN engineList.
LOCAL engineCount IS 0.
LOCAL engineStats IS LEXICON().
LOCAL engineStat IS LEXICON().
LOCAL pressure IS SHIP:BODY:ATM:ALTITUDEPRESSURE(SHIP:BODY:POSITION:MAG - SHIP:BODY:RADIUS).
LOCAL engineStatsUnits IS LEXICON().

engineStatsUnits:ADD("TITLE", ",").
engineStatsUnits:ADD("THRUSTLIMIT", ",%").
engineStatsUnits:ADD("MAXTHRUST", ",kN").
engineStatsUnits:ADD("MAXTHRUSTAT(pressure)", ",kN").
engineStatsUnits:ADD("THRUST", ",kN").
engineStatsUnits:ADD("AVAILABLETHRUST", ",kN").
engineStatsUnits:ADD("AVAILABLETHRUSTAT(pressure)", ",kN").
engineStatsUnits:ADD("POSSIBLETHRUST", ",kN").
engineStatsUnits:ADD("POSSIBLETHRUSTAT(pressure)", ",kN").
engineStatsUnits:ADD("FUELFLOW", ",kg/s").
engineStatsUnits:ADD("ISP", ",s").
engineStatsUnits:ADD("ISPAT(pressure)", ",s").
engineStatsUnits:ADD("VACUUMISP", ",s").
engineStatsUnits:ADD("VISP", ",s").
engineStatsUnits:ADD("SEALEVELISP", ",s").
engineStatsUnits:ADD("SLISP", ",s").
engineStatsUnits:ADD("FLAMEOUT", ",").
engineStatsUnits:ADD("IGNITION", ",").
engineStatsUnits:ADD("ALLOWRESTART", ",").
engineStatsUnits:ADD("ALLOWSHUTDOWN", ",").
engineStatsUnits:ADD("THROTTLELOCK", ",").
engineStatsUnits:ADD("MULTIMODE", ",").
engineStatsUnits:ADD("HASGIMBAL", ",").

FOR eachEngine IN engineList {
	SET engineStat TO LEXICON().
	engineStat:ADD("TITLE", eachEngine:TITLE).
	engineStat:ADD("THRUSTLIMIT", eachEngine:THRUSTLIMIT).
	engineStat:ADD("MAXTHRUST", eachEngine:MAXTHRUST).
	engineStat:ADD("MAXTHRUSTAT(pressure)", eachEngine:MAXTHRUSTAT(pressure)).
	engineStat:ADD("THRUST", eachEngine:THRUST).
	engineStat:ADD("AVAILABLETHRUST", eachEngine:AVAILABLETHRUST).
	engineStat:ADD("AVAILABLETHRUSTAT(pressure)", eachEngine:AVAILABLETHRUSTAT(pressure)).
	engineStat:ADD("POSSIBLETHRUST", eachEngine:POSSIBLETHRUST).
	engineStat:ADD("POSSIBLETHRUSTAT(pressure)", eachEngine:POSSIBLETHRUSTAT(pressure)).
	engineStat:ADD("FUELFLOW", eachEngine:FUELFLOW).
	engineStat:ADD("ISP", eachEngine:ISP).
	engineStat:ADD("ISPAT(pressure)", eachEngine:ISPAT(pressure)).
	engineStat:ADD("VACUUMISP", eachEngine:VACUUMISP).
	engineStat:ADD("VISP", eachEngine:VISP).
	engineStat:ADD("SEALEVELISP", eachEngine:SEALEVELISP).
	engineStat:ADD("SLISP", eachEngine:SLISP).
	engineStat:ADD("FLAMEOUT", eachEngine:FLAMEOUT).
	engineStat:ADD("IGNITION", eachEngine:IGNITION).
	engineStat:ADD("ALLOWRESTART", eachEngine:ALLOWRESTART).
	engineStat:ADD("ALLOWSHUTDOWN", eachEngine:ALLOWSHUTDOWN).
	engineStat:ADD("THROTTLELOCK", eachEngine:THROTTLELOCK).
	engineStat:ADD("MULTIMODE", eachEngine:MULTIMODE).
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
		SET message TO message + engineStatsUnits[eachStat] + CHAR(10).
	}
	SET message TO message + "Throttle," + THROTTLE + CHAR(10).
	SET message TO message + "Pressure," + pressure + ",atms" + CHAR(10).
}
CLEARSCREEN.
PRINT "Engines.csv created on the archive".
SET loopMessage TO "Engines.csv created.".
LOG message TO "0:Engines.csv".
