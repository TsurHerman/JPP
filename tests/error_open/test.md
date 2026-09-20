# An open error type cannot promise a finite dispatch table

The input is typed `anyerror`, which does not enumerate a closed set of possible
errors. Runtime injection deliberately rejects it, even with a broad default.
Choose a finite native error set at the boundary so coverage can be checked.

This restriction concerns runtime possibilities. A statically known `anyerror`
value can narrow to its one actual error, covered in `error_dispatch`.
