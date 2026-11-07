#ifndef ZGO_H
#define ZGO_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

/* The geoarrow-c commit src/vendor/ is derived from. tools/verify-vendor
   checks that it matches tools/derive-vendor's COMMIT. */
#define ZGO_GEOARROW_C_COMMIT "b3db89fec68043ade505fffb62a668043812884a"

/* The GeoArrow specification version this package implements. */
#define ZGO_GEOARROW_SPEC "0.2"

/* Codes zgo_extension_code() returns beyond geometry types 0 to 7. */
#define ZGO_CODE_WKB 100
#define ZGO_CODE_WKT 101
#define ZGO_CODE_BOX 990

struct ArrowSchema;
int zgo_extension_code(const struct ArrowSchema *s);
int zgo_native_dims(const struct ArrowSchema *s, int geometry_type);
const struct ArrowSchema *zgo_schema_from_xptr(SEXP x);

SEXP zgo_c_info(void);
SEXP zgo_c_type_of(SEXP schema);
SEXP zgo_c_type_of_children(SEXP schema);
SEXP zgo_c_schema_from_spec(SEXP spec);
SEXP zgo_c_is_na(SEXP chunks, SEXP schema, SEXP chunk, SEXP row);
SEXP zgo_c_format(SEXP chunks, SEXP schema, SEXP chunk, SEXP row, SEXP max_bytes);
SEXP zgo_c_take(SEXP chunks, SEXP schema, SEXP chunk, SEXP row);
SEXP zgo_c_array_length(SEXP array);
SEXP zgo_c_scan(SEXP chunks, SEXP schema, SEXP chunk, SEXP row);
SEXP zgo_c_write(SEXP chunks, SEXP schema, SEXP chunk, SEXP row, SEXP type,
                 SEXP metadata, SEXP as_r);
SEXP zgo_c_array_set_schema(SEXP array, SEXP schema);
SEXP zgo_c_from_wkb(SEXP x);
SEXP zgo_c_from_wkt(SEXP x);
SEXP zgo_c_hex_to_raw(SEXP x);
SEXP zgo_c_type_schema(SEXP type, SEXP metadata);
SEXP zgo_c_check_inner_nulls(SEXP array);
SEXP zgo_c_check_inner_nulls_union(SEXP array);
SEXP zgo_c_info_kernel(SEXP chunks, SEXP schema, SEXP chunk, SEXP row);
SEXP zgo_c_hilbert(SEXP cx, SEXP cy, SEXP extent);
SEXP zgo_c_validate(SEXP chunks, SEXP schema, SEXP chunk, SEXP row);
SEXP zgo_c_geoarrow_box(SEXP array, SEXP schema);
SEXP zgo_c_coords(SEXP chunks, SEXP schema, SEXP chunk, SEXP row);
SEXP zgo_c_from_coords(SEXP x, SEXP y, SEXP z, SEXP m, SEXP feature, SEXP part,
                       SEXP ring, SEXP n_features, SEXP type, SEXP out_type);

#endif
