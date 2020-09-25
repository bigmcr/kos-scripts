//Adds a node to change inclination at the next equatorial node.
PARAMETER desired_i IS 0.
LOCAL delta_i IS desired_i - ORBIT:INCLINATION.

FUNCTION time_to_node_type {
  PARAMETER nodeType.
  LOCAL w IS SHIP:ORBIT:PERIOD/360.
  LOCAL shiptolan IS 0.
  IF nodeType = "desc"  SET shiptolan TO 180 - (ORBIT:ARGUMENTOFPERIAPSIS + ORBIT:TRUEANOMALY).
  ELSE                  SET shiptolan TO 360 - (ORBIT:ARGUMENTOFPERIAPSIS + ORBIT:TRUEANOMALY).
  UNTIL shiptolan > 0 SET shiptolan TO shiptolan + 360.
  RETURN shiptolan * w.
}

FUNCTION dV_normal {
	PARAMETER time_to_node IS 0.
  LOCAL v is VELOCITYAT(SHIP, TIME:SECONDS + time_to_node):ORBIT:MAG.
  RETURN 2 * v * sin(delta_i/2).
}

FUNCTION dV_prograde {
	PARAMETER time_to_node IS 0.
  LOCAL v is VELOCITYAT(SHIP, TIME:SECONDS + time_to_node):ORBIT:MAG.
  LOCAL v_prograde is v/cos(delta_i).
  RETURN v - v_prograde.
}

LOCAL mnv IS "".
LOCAL timeToASCNode IS time_to_node_type("asc").
LOCAL timeToDESCNode IS time_to_node_type("desc").
IF timeToASCNode < timeToDESCNode {
	SET mnv TO NODE(TIME:SECONDS + timeToASCNode, 0, dV_normal(timeToASCNode), dV_prograde(timeToASCNode)).
	SET loopMessage TO "Inc. change node at ASC node created".
} ELSE {
	SET mnv TO NODE(TIME:SECONDS + timeToDESCNode, 0, -dV_normal(timeToDESCNode), dV_prograde(timeToDESCNode)).
	SET loopMessage TO "Inc. change node at DESC node created".
}
ADD mnv.
