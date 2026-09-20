# Readability review: the original 147 cases

This review covers every case folder that existed before the value-predicate
and native-error increment. New cases for that increment have their own test.md
pages. No original case or assertion was removed.

## What changed

- Native Zig grounds now show control flow and declarations across readable
  lines. Short jpp compositions remain one-liners; multiline blocks, independent
  words and long assertions are separated consistently.
- The tagged-union family now quotes standard and express shipments. Its failure
  cases explain a forgotten shipping method, incompatible quote results, a
  runtime-selected type and crossing argument constraints. Owner identity remains
  a separate small structural test.
- Checkout checks name expected gross, discount, net, freight, tax and total.
  DWARF checks name the width/endian flags and expected size instead of leaving
  unexplained booleans and numbers in long call lines.
- Tiny argument and binding failures use descriptive function names. Their pages
  explain the incorrect call, expected failure and, where useful, a valid repair.
  Diagnostic markers changed only where an intentional name/tag change required it.
- Ordering and predicate pages use small decision tables and direct explanations.
  Mathematical examples retain their actual graph rather than an artificial
  application story.
- Stale claims about implicit Base imports, undeclared library calls, private
  visibility, inaccessible type binders and the old where_gate_pass name were
  corrected against source and executable promises.

## Deliberate complexity

The lattice and collapse cases retain A/B/C and numeric method markers where
those names make the graph visible. The marker identifies the selected method;
it is not an unexplained business calculation. Separate program roots remain
separate because they must start with independent caller contexts.

JSON retains foreign native reflection and IO fixtures. Their multiline layout
makes the existing boundary inspectable; this review does not introduce a jpp
allocation, collection or error model. Small source-negative cases remain
intentionally invalid. Their diagnostic is the assertion.

## Verification

Every original folder was checked against a frozen pre-change compiler/runtime,
including successful programs and both kinds of expected failure. All 147
preserved their promises. A renamed `first` input initially collided with the
ordinary Base.first word; it was changed to `headValue` and its ambiguity
promise was rechecked. The final integrated build validates the same sources
against the new language machinery.

## Reviewed inventory

### Application examples (3)

`checkout`, `dwarf_offsets`, `json_dispatch`.

### Enums and tagged unions (15)

`enum_member_non_enum`, `enum_members`, `enum_missing_member`, `enum_open`,
`enum_pattern_member`, `enum_pattern_missing`, `enum_pattern_order`, `enum_pattern_owner`,
`variant_crossing`, `variant_dispatch`, `variant_missing`, `variant_owner`,
`variant_result`, `variant_runtime_type`, `variant_static`.

### Imports, facades and visibility (25)

`base_folder`, `base_import`, `base_missing`, `base_mixed`, `base_shadow`,
`cycle_ambiguity`, `cycle_facade`, `cycle_facade_ambiguity`, `cycle_facade_hidden`,
`cycle_facade_missing`, `cycle_folder`, `cycle_imports`, `cycle_private`, `export_gate`,
`facade_hidden`, `folder_collision`, `folder_modules`, `folder_scope`, `module_encoding`,
`private_downstream`, `private_helpers`, `reexport_chain`, `reexport_empty_cycle`,
`reexport_hidden`, `wildcard_excludes_facade`.

### Names, bindings and declarations (30)

`binding_call`, `binding_duplicate`, `binding_forward`, `binding_parameter`,
`binding_self`, `binding_type_parameter`, `declaration_names`, `declaration_tunnel`,
`local_bindings`, `static_binding_builtin`, `static_binding_call`,
`static_binding_conflict`, `static_binding_cycle`, `static_binding_duplicate`,
`static_binding_method`, `static_binding_mixed`, `static_binding_private`,
`static_binding_stage`, `static_binding_word_call`, `static_bindings`, `unbound_where`,
`undeclared_call`, `undeclared_gate`, `undeclared_order`, `undeclared_unused_call`,
`undefined_export`, `unused_anonymous`, `unused_ground`, `unused_input`,
`unused_untyped_ground`.

### Named arguments and records (23)

`ground_records`, `named_anonymous`, `named_arguments`, `named_context`, `named_crossing`,
`named_duplicate`, `named_instances`, `named_missing`, `named_specificity`,
`named_to_positional`, `named_type_mismatch`, `named_unknown`, `pack_duplicate_field`,
`pack_empty_tail`, `pack_malformed`, `pack_missing_field`, `pack_non_record`,
`pack_out_of_bounds`, `pack_static`, `pack_values`, `positional_to_named`,
`type_bindings`, `type_values`.

### Rest arguments and splats (22)

`splat_duplicate`, `splat_labelled`, `splat_named_to_positional`, `splat_non_pack`,
`splat_positional_to_named`, `varargs`, `varargs_binary_gap`, `varargs_crossing`,
`varargs_dispatch`, `varargs_empty_ambiguity`, `varargs_empty_unbound`, `varargs_forward`,
`varargs_named_empty_ambiguity`, `varargs_named_type`, `varargs_not_last`,
`varargs_predicate_reject`, `varargs_scale`, `varargs_sections_mismatch`,
`varargs_two_named`, `varargs_type_mismatch`, `varargs_type_pack_witness`,
`varargs_uniform_mixed`.

### Dispatch, predicates and authored order (29)

`ambiguity`, `any`, `any_order_gap`, `any_override`, `any_shadow`, `any_unimported`,
`caller_context`, `collapse_dependencies`, `collapse_imports`, `context_flip`,
`depth_override`, `dispatch`, `equality_scope`, `gate_conjunction`, `lattice`,
`lattice_bridge`, `lattice_gap`, `order_bool`, `order_cycle`, `order_injection`,
`order_negative`, `order_refines`, `order_type_only`, `order_variables`, `override`,
`pointwise_gap`, `pred_join`, `where_gate`, `where_gate_clash`.
