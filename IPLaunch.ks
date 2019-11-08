@LAZYGLOBAL OFF.

CLEARSCREEN.

PARAMETER progradedV.
PARAMETER normaldV.

UNTIL HASTARGET {
	PRINT "Please select a target".
	WAIT 0.
}

// Passed a delegate that recieves a single SCALAR and returns a SCALAR.
FUNCTION hillClimb {
	PARAMETER delegateFunction.
	PARAMETER initialGuess.
	PARAMETER initialStepSize.
	PARAMETER maxSteps IS 1000.
	
	LOCAL stepSize is initialStepSize.

	LOCAL iteration IS 0.

	LOG "Current Guess,Step Size,Distance At Approach,Delegate at Guess + Step,Delegate at Guess - Step,Iteration" TO "0:HillClimb.csv".
	// Do the hill climbing
	LOCAL currentGuess is initialGuess.
	UNTIL (stepSize = (initialStepSize / (2^15))) OR (iteration > 1000) {
		LOG currentGuess + "," + stepSize + "," + delegateFunction(currentGuess) + "," + delegateFunction(currentGuess + stepSize) + "," + delegateFunction(currentGuess - stepSize) + "," + iteration TO "0:HillClimb.csv".
		IF delegateFunction(currentGuess + stepSize) < delegateFunction(currentGuess) {
			SET currentGuess TO currentGuess + stepSize.
		} ELSE IF delegateFunction(currentGuess - stepSize) < delegateFunction(currentGuess) {
			SET currentGuess TO currentGuess - stepSize.
		} ELSE {
			SET stepSize TO (stepSize/2).
		}
		SET iteration TO iteration + 1.
	}
	RETURN delegateFunction(currentGuess).
}

// Passed a delegate that recieves a single SCALAR and returns a SCALAR.
FUNCTION nodeTimeHillClimb {
	PARAMETER proDV.
	PARAMETER normDV.
	PARAMETER initialGuess.
	PARAMETER initialStepSize.
	PARAMETER maxSteps IS 1000.
	
	LOCAL stepSize is initialStepSize.

	LOCAL iteration IS 0.
	
	LOCAL shipToIntercept   IS VECDRAW(V(0,0,0), V(0,0,0), RED,   "Facing", 1, TRUE).

	FOR eachNode IN ALLNODES {
		REMOVE eachNode.
	}

	LOCAL approach IS "".
	LOCAL currentApproach IS "".
	LOCAL plusApproach IS "".
	LOCAL minusApproach IS "".
	LOCAL currentGuess is initialGuess.
	LOCAL newNode IS NODE(currentGuess, 0, normDV, proDV).
	LOCAL halfBodyPeriod IS SHIP:BODY:ORBIT:PERIOD / 2.
	LOCAL previousValues IS LIST().
	ADD newNode.

	LOG "Iteration,Current Guess,Step Size,Delegate,Delegate at Guess + Step,Delegate at Guess - Step,,,Start Time:," + TIME:SECONDS TO "0:HillClimb.csv".
	// Do the hill climbing
	UNTIL (stepSize = (initialStepSize / (2^15))) OR (iteration > 1000) {
		SET newNode:ETA TO currentGuess - TIME:SECONDS.
		SET currentApproach TO closestApproach(currentGuess + halfBodyPeriod, halfBodyPeriod / 5).
		SET plusApproach TO closestApproach(currentGuess + stepSize + halfBodyPeriod, halfBodyPeriod / 5).
		SET minusApproach TO closestApproach(currentGuess - stepSize + halfBodyPeriod, halfBodyPeriod / 5).
		PRINT "Iteration: " + iteration:TOSTRING:PADLEFT(3) + " Closest approach: " + distanceToString(currentApproach[1], 3) + "     ".
		SET shipToIntercept:SHOW TO MAPVIEW.
		IF MAPVIEW {
			SET shipToIntercept:START TO POSITIONAT(SHIP, currentApproach[0]).
			SET shipToIntercept:VEC TO POSITIONAT(TARGET, currentApproach[0]) - POSITIONAT(SHIP, currentApproach[0]).
		}
		IF plusApproach[1] < currentApproach[1] {
			SET currentGuess TO currentGuess + stepSize.
		} ELSE IF minusApproach[1] < currentApproach[1] {
			SET currentGuess TO currentGuess - stepSize.
		} ELSE {
			SET stepSize TO (stepSize/2).
		}
		SET iteration TO iteration + 1.
//		WAIT 1.
		LOG iteration + "," + currentGuess + "," + stepSize + "," + currentApproach[1] + "," + plusApproach[1] + "," + minusApproach[1] TO "0:HillClimb.csv".
	}
	RETURN currentApproach[1].
}

nodeTimeHillClimb(progradedV, normaldV, TIME:SECONDS + SHIP:ORBIT:PERIOD / 2, 64).
