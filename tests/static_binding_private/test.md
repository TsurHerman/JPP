# Returning a private width does not export its name

The library's `offsetWidth()` can return its private `InternalWidth` constant.
The application imports that method, then tries to read `InternalWidth`
directly. Compilation must report an undefined value. Exporting a method does
not export every name used in its body.
