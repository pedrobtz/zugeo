#include "zgo.h"

#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "geoarrow/geoarrow.h"
#include "nanoarrow/nanoarrow.h"

/* Versions of everything the shared object is built from, for
   zugeo_info(). Calling each library's version function, rather than
   reading a macro, proves the vendored objects are linked. */
SEXP zgo_c_info(void) {
  const char *names[] = {"geoarrow_c", "geoarrow_c_commit", "nanoarrow",
                         "geoarrow", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString(GeoArrowVersion()));
  SET_VECTOR_ELT(out, 1, Rf_mkString(ZGO_GEOARROW_C_COMMIT));
  SET_VECTOR_ELT(out, 2, Rf_mkString(ArrowNanoarrowVersion()));
  SET_VECTOR_ELT(out, 3, Rf_mkString(ZGO_GEOARROW_SPEC));
  UNPROTECT(1);
  return out;
}

#define ZGO_CALL(name, n) {#name, (DL_FUNC)&name, n}

static const R_CallMethodDef zgo_call_methods[] = {
    ZGO_CALL(zgo_c_info, 0),
    ZGO_CALL(zgo_c_type_of, 1),
    ZGO_CALL(zgo_c_type_of_children, 1),
    ZGO_CALL(zgo_c_schema_from_spec, 1),
    ZGO_CALL(zgo_c_is_na, 4),
    ZGO_CALL(zgo_c_format, 5),
    ZGO_CALL(zgo_c_take, 4),
    ZGO_CALL(zgo_c_array_length, 1),
    ZGO_CALL(zgo_c_scan, 4),
    ZGO_CALL(zgo_c_write, 7),
    ZGO_CALL(zgo_c_array_set_schema, 2),
    ZGO_CALL(zgo_c_from_wkb, 1),
    ZGO_CALL(zgo_c_from_wkt, 1),
    ZGO_CALL(zgo_c_hex_to_raw, 1),
    ZGO_CALL(zgo_c_type_schema, 2),
    ZGO_CALL(zgo_c_check_inner_nulls, 1),
    ZGO_CALL(zgo_c_check_inner_nulls_union, 1),
    ZGO_CALL(zgo_c_info_kernel, 4),
    ZGO_CALL(zgo_c_hilbert, 3),
    ZGO_CALL(zgo_c_validate, 4),
    ZGO_CALL(zgo_c_geoarrow_box, 2),
    ZGO_CALL(zgo_c_rtree_build, 5),
    ZGO_CALL(zgo_c_index_info, 1),
    ZGO_CALL(zgo_c_rtree_search, 5),
    ZGO_CALL(zgo_c_rtree_join, 2),
    ZGO_CALL(zgo_c_rtree_nearest, 5),
    ZGO_CALL(zgo_c_kdtree_build, 3),
    ZGO_CALL(zgo_c_kdtree_query, 6),
    ZGO_CALL(zgo_c_coords, 4),
    ZGO_CALL(zgo_c_from_coords, 10),
    {NULL, NULL, 0}};

void attribute_visible R_init_zugeo(DllInfo *dll) {
  R_registerRoutines(dll, NULL, zgo_call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
