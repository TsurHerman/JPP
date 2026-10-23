# Callback validity does not choose the receiving method

The exact int64 receiver wins ordinary dispatch, then supplies an integer to a
float64 callback. The callback fails. The compiler must not retry the generic
receiver merely because that receiver would supply a float and make the body
valid.
