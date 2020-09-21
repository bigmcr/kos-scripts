CLEARSCREEN.

// calculate and create nodes for a Hohmann transfer orbit to the specified altitude.
// Creates nodes for the initial transfer burn and the circularization burn.
PARAMETER finalAltitude.
PARAMETER acknowledge IS TRUE.

LOCAL hohmannIn IS finalAltitude < SHIP:ORBIT:PERIAPSIS.
LOCAL hohmannOut IS finalAltitude > SHIP:ORBIT:APOAPSIS.

LOCAL errorCode IS "None".
IF NOT hohmannIn AND NOT hohmannOut SET errorCode TO "Apo > Final Alt > Peri".
IF SHIP:ORBIT:TRANSITION <> "Final" SET errorCode TO "Transition occures!".

IF errorcode = "None" {
  LOCAL deltaV1 IS 0.
  LOCAL deltaV2 IS 0.

  IF hohmannIn {

  }
  IF hohmannOut {

  }
} ELSE {
  SET loopMessage TO errorCode.
}
