# cycle_private

Mutual imports establish a public dispatch unit, but do not expose another
source file's private definitions. A body calling its cycle neighbor's private
helper fails lexical validation, even though both files belong to one unit.
