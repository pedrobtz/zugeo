/* The array layer shared by zgo_array.c and zgo_convert.c: scratch
   ownership of C resources, a column's chunk views, and the walk of one
   feature into a GeoArrowVisitor. */
#ifndef ZGO_ARRAY_H
#define ZGO_ARRAY_H

#include "zgo.h"

#include "geoarrow/geoarrow.h"
#include "nanoarrow/nanoarrow.h"

SEXP zgo_scratch_new(void);
void zgo_scratch_run(SEXP xptr);
void zgo_scratch_add(SEXP scratch, void (*fn)(void *), void *p);
void *zgo_scratch_alloc(SEXP scratch, size_t size, void (*reset)(void *));

typedef struct {
  const struct ArrowSchema *schema;
  int code; /* zgo_extension_code() */
  int dims; /* for native types 1 to 6 */
  int n_chunks;
  struct ArrowArrayView **views;
} zgo_column;

typedef struct {
  struct GeoArrowWKBReader *wkb;
  struct GeoArrowWKTReader *wkt;
} zgo_readers;

const char *zgo_column_init(SEXP scratch, SEXP chunks, SEXP schema, zgo_column *col,
                            char *message, size_t n);
int zgo_readers_init(SEXP scratch, zgo_readers *readers);
int zgo_is_null(const struct ArrowArrayView *v, int64_t i);
int zgo_position(SEXP chunk, SEXP row, R_xlen_t p, int n_chunks, int64_t *out_row);
int zgo_visit_feature(const zgo_column *col, int k, int64_t r, zgo_readers *readers,
                      struct GeoArrowVisitor *vis);
void zgo_free_array(void *p);
void zgo_array_finalize(SEXP xptr);
const struct ArrowArray *zgo_array_from_xptr(SEXP x);

#endif
