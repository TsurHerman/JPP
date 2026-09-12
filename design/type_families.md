# Type families without implicit inheritance

Status: predicates and authored order RUN. A concrete Vector constructor and
its pattern checks are VALIDATED by spike/vecprobe.zig. General surface type
families and immutable nominal record declarations are unbuilt.

Integer, Signed, Float, Real, and domain categories are ordinary predicates over
type values. An authored `<:(Signed, Real)` preference does not prove inclusion,
provide storage inheritance, or create conversions. The names must be declared.
Overlaps and missing edges are useful executable promises.

## Selector-dependent types

The next family example is a Vector selected by element type T and dimension N.
T is a static type value; N is a static integer value. Runtime elements are data.
Repeated selectors in a signature require identity, including shared dimensions
in a mixed-element dot product. No arithmetic promotion happens during binding.

The surface must explicitly define type application and construction through
its returned type, including locally bound type values. Those call targets must
also participate in dependency discovery before context collapse removes modules.
Test a caller override behind a constructor alias through several imports.

Supported family patterns may inspect selector metadata and validate provenance
by re-applying the declared family and checking type identity. The Vector probe
proves this for one generative constructor. It does not make arbitrary
functions returning types invertible or injective; forged metadata must fail.

## Records

Anonymous structural packs already provide immutable named values. Nominal
record declarations should add explicit family identity and construction rules
over the same field model. They must not quietly change anonymous pack identity.
Define field access, missing/extra-field rejection, static fields, and provenance
before choosing declaration sugar. Preserve original declaration homes in units.

Mutation, runtime-sized tensors, ownership, views, and storage layout are later
work. Shapes as static values are useful without committing to an allocator or
fusion system. A standalone nominal struct expression duplicated in an inferred
Zig ground return can produce two distinct native types; define the type once
through a type-returning method and construct that selected type until a better
ground representation removes this limitation.
