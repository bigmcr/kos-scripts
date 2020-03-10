CLEARSCREEN.

ON SHIP:PARTS:LENGTH {
	updateShipInfo().
}

LOCAL timeToSuicideBurn IS SuicideBurnCountdown(50).
LOG "Mission Time,Time To Suicide Burn" TO "SuicideBurn.csv".

UNTIL VELOCITY:SURFACE:MAG < 10 {
	SET timeToSuicideBurn TO SuicideBurnCountdown(50).
	LOG missionTime + "," + timeToSuicideBurn TO "SuicideBurn.csv".
	PRINT "Time to Suicide Burn: " + ROUND( timeToSuicideBurn , 4) + "    " AT (0,0).
	// Engine staging
	// this should drop any used stage
	WHEN MAXTHRUST = 0 THEN {
		PRINT "Staging from max thrust".
		stageFunction().
	}
	WAIT 0.
}

PRINT "AutoStaging Complete!".
