@lazyglobal off.

PARAMETER export.
export("line_search", line_search@).
export("grid_search", grid_search@).

// Convenience wrapper FOR searching a single dimension.
LOCAL FUNCTION line_search {
    PARAMETER cost, x, step_size, step_threshold.

    LOCAL dimensions IS list(v(1, 0, 0), v(-1, 0, 0)).
    LOCAL position IS v(x, 0, 0).
    LOCAL minimum IS cost(position).

    RETURN coordinate_descent(dimensions, cost, position, minimum, step_size, step_threshold).
}

// Convenience wrapper for searching two dimensions.
LOCAL FUNCTION grid_search {
    PARAMETER cost, x, y, scale_y, minimum, step_size, step_threshold.

    LOCAL dimensions IS list(v(1, 0, 0), v(-1, 0, 0), v(0, scale_y, 0), v(0, -scale_y, 0)).
    LOCAL position IS v(x, y, 0).

    RETURN coordinate_descent(dimensions, cost, position, minimum, step_size, step_threshold).
}

// Coordinate descent is a variant of the hill climbing algorithm, where only
// one dimension (x, y or z) is minimized at a time. This algorithm implements
// this with a simple binary search approach. This converges reasonable quickly
// wihout too many invocations of the "cost" function.
//
// The approach is:
// (1) Choose an initial starting position
// (2) Determine the lowest cost at a point "step_size" distance away, looking
//     in both positive and negative directions on the x, y and z axes.
// (3) Continue in this direction until the cost increases
// (4) Reduce the step size by half, terminating to below the threshold
//     then go to step (2)
LOCAL FUNCTION coordinate_descent {
    PARAMETER dimensions, cost, position, minimum, step_size, step_threshold.

    LOCAL next_position IS position.
    LOCAL direction IS "none".

    LOCAL FUNCTION test {
        PARAMETER test_direction.

        LOCAL test_position IS position + step_size * test_direction.
        LOCAL test_cost IS cost(test_position).

        IF test_cost < minimum {
            SET minimum TO test_cost.
            SET next_position TO test_position.
            SET direction TO test_direction.
        }
        // Stop IF we are currently line searching.
        ELSE IF direction = test_direction {
            SET direction TO "none".
        }
    }

    until step_size < step_threshold {
        IF direction = "none" {
            FOR test_direction in dimensions {
                test(test_direction).
            }
        }
        ELSE {
            test(direction).
        }

        IF direction = "none" {
            SET step_size TO step_size * 0.5.
        }
        ELSE {
            SET position TO next_position.
        }
    }

    RETURN lex("position", position, "minimum", minimum).
}
