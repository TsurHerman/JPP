# undeclared_order

A caller importing Signed/Wide cannot give those names meaning in another module's declaration. Without its own definitions/imports the names are fresh, unused inputs, and the declaration must fail even before it participates in dispatch.
