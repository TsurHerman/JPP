# Reflection receives an explicit call pack

The second input to returnType describes the argument pack, not a scalar
argument. Invalid shapes receive a jpp diagnostic rather than a native struct
reflection failure.
