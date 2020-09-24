//Adds a node to change inclination at the next equatorial node.
PARAMETER desired_i IS 0.
LOCAL delta_i IS desired_i - ORBIT:INCLINATION.

FUNCTION time_to_node_asc {

    LOCAL w IS SHIP:ORBIT:PERIOD/360.
    LOCAL shiptolan is 360 - (ORBIT:ARGUMENTOFPERIAPSIS + ORBIT:TRUEANOMALY).
    UNTIL shiptolan > 0 SET shiptolan TO shiptolan + 360.
    RETURN shiptolan * w.
}

FUNCTION time_to_node_desc {
    LOCAL w IS SHIP:ORBIT:PERIOD/360.
    LOCAL shiptolan is 180 - (ORBIT:ARGUMENTOFPERIAPSIS + ORBIT:TRUEANOMALY).
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
IF time_to_node_asc() < time_to_node_desc() {
	SET mnv TO NODE(TIME:SECONDS + time_to_node_asc(), 0, dV_normal(time_to_node_asc()), dV_prograde(time_to_node_asc())).
	SET loopMessage TO "Inc. change node at ASC node created".
} ELSE {
	SET mnv TO NODE(TIME:SECONDS + time_to_node_desc(), 0, -dV_normal(time_to_node_desc()), dV_prograde(time_to_node_asc())).
	SET loopMessage TO "Inc. change node at DESC node created".
}
ADD mnv.
