@LAZYGLOBAL OFF.
CLEARSCREEN.

PARAMETER EjectionLAN IS 342.27 + 180.0.
PARAMETER DeltaV IS 3641.
PARAMETER UT IS 172780984.

LOCAL bodyPos IS SHIP:BODY:POSITION.
LOCK bodyPos TO SHIP:BODY:POSITION.
LOCAL radius IS (SHIP:BODY:RADIUS + SHIP:BODY:ATM:HEIGHT) * 2.5.
//                          start,    vec,    color, label,        scale, show, width, pointy
LOCAL LANVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), RED, "LAN"     	, 1.0, TRUE, 0.2, TRUE).
SET LANVecDraw:VECUPDATER TO {RETURN (SOLARPRIMEVECTOR * ANGLEAXIS(-SHIP:ORBIT:LAN, NORTH:VECTOR)):NORMALIZED * RADIUS.}.
SET LANVecDraw:STARTUPDATER TO {RETURN bodyPos.}.

LOCAL AoPVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "AoP"     	, 1.0, TRUE, 0.2, TRUE).
SET AoPVecDraw:VECUPDATER TO {RETURN LANVecDraw:VEC * ANGLEAXIS(-SHIP:ORBIT:ARGUMENTOFPERIAPSIS, VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - bodyPos)).}.
SET AoPVecDraw:STARTUPDATER TO {RETURN bodyPos.}.

LOCAL BurnVecDraw IS VECDRAW(V(0,0,0), V(0,0,0), YELLOW, "Burn"     	, 1.0, TRUE, 0.2, TRUE).
SET BurnVecDraw:VECUPDATER TO {RETURN LANVecDraw:VEC * ANGLEAXIS(-EjectionLAN, VCRS(SHIP:VELOCITY:ORBIT, SHIP:POSITION - bodyPos)).}.
SET BurnVecDraw:STARTUPDATER TO {RETURN bodyPos.}.

LOCAL newNode IS NODE(UT, 0, 0, DeltaV).
ADD newNode.
WAIT 0.

PRINT "Press AG1 to Exit".
AG1 OFF.
UNTIL AG1 {
  WAIT 0.
}
//Earth (@161km) -> Mars (@100km)
//Depart at:      23 Jun 1956, 18:43:03
//       UT:      172867384
//   Travel:      193 days , 01:58:45
//       UT:      16682326
//Arrive at:      2 Jan 1957, 20:41:49
//       UT:      189549710
//Phase Angle:    26.05°
//Ejection Angle: 158.67° to prograde
//Ejection Inc.:  1.25°
//Ejection Δv:    3649 m/s
//Prograde Δv:    3640.1 m/s
//Normal Δv:      249.9 m/s
//Heading:        86.07°
//Insertion Inc.: -25.64°
//Insertion Δv:   2116 m/s
//Total Δv:       5764 m/s
