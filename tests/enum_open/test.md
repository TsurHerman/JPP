# enum_open

Case-sensitive dispatch requests a table and rejects a non-exhaustive enum;
unnamed cases need a separately designed dispatch policy. Ordinary transport
through generic methods does not request a table and works in `enum_demand`.
