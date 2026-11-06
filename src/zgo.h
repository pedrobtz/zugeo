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

SEXP zgo_c_info(void);

#endif
