/* Conversions between encodings (design sections 6.3, 6.6 and 6.10): a
   geo_vctr's rows written as WKB, WKT or a native type through geoarrow-c's
   GeoArrowArrayWriter; WKB, EWKB, hex WKB and WKT read into arrays; and
   coordinates as columns, both ways. Every walk goes through
   zgo_visit_feature(), so every layout zugeo reads converts. */

#include "zgo_array.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- Shared ------------------------------------------------------------ */

#define ZGO_TRY(expr)                    \
  do {                                   \
    int zgo_status_ = (expr);            \
    if (zgo_status_ != GEOARROW_OK) return zgo_status_; \
  } while (0)

static void zgo_reset_array_writer(void *p) {
  GeoArrowArrayWriterReset((struct GeoArrowArrayWriter *)p);
}

static void zgo_free_schema_p(void *p) {
  struct ArrowSchema *s = (struct ArrowSchema *)p;
  if (s->release != NULL) s->release(s);
  free(p);
}

/* An array writer of `type`, owned by scratch. */
static struct GeoArrowArrayWriter *zgo_writer_new(SEXP scratch, enum GeoArrowType type) {
  struct GeoArrowArrayWriter *w = (struct GeoArrowArrayWriter *)zgo_scratch_alloc(
      scratch, sizeof(struct GeoArrowArrayWriter), free);
  if (GeoArrowArrayWriterInitFromType(w, type) != GEOARROW_OK) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start a writer for GeoArrow type %d.", (int)type);
  }
  zgo_scratch_add(scratch, zgo_reset_array_writer, w);
  if (type == GEOARROW_TYPE_WKT || type == GEOARROW_TYPE_LARGE_WKT) {
    GeoArrowArrayWriterSetPrecision(w, 16);
  }
  return w;
}

/* A new array handle owning `array` (moved from), tagged with `schema`. */
static SEXP zgo_array_handle(struct ArrowArray *array, SEXP schema) {
  SEXP out = PROTECT(R_MakeExternalPtr(NULL, schema, R_NilValue));
  R_RegisterCFinalizerEx(out, &zgo_array_finalize, TRUE);
  struct ArrowArray *owned = (struct ArrowArray *)malloc(sizeof(struct ArrowArray));
  if (owned == NULL) {
    array->release(array);
    Rf_error("Could not allocate an array.");
  }
  ArrowArrayMove(array, owned);
  R_SetExternalPtrAddr(out, owned);
  SEXP klass = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(klass, 0, Rf_mkChar("zugeo_array"));
  SET_STRING_ELT(klass, 1, Rf_mkChar("nanoarrow_array"));
  Rf_setAttrib(out, R_ClassSymbol, klass);
  UNPROTECT(2);
  return out;
}

static SEXP zgo_schema_handle_finalized(struct ArrowSchema *schema);

/* ---- Scanning: which geometry types and dimensions a column holds ------ */

#define ZGO_SCAN_DEPTH 32

typedef struct {
  int depth;
  int types; /* bit t for top-level geometry type t (1 to 7) */
  int dims;  /* bit d for dimensions d (1 to 4) */
  int n_null;
  /* Whether any line or ring has two vertices or more: an edge, which a
     non-planar edge type changes the meaning of (design section 6.3). */
  int has_edges;
  int type_at[ZGO_SCAN_DEPTH];
} zgo_scan_state;

static int zgo_scan_feat_start(struct GeoArrowVisitor *v) {
  ((zgo_scan_state *)v->private_data)->depth = 0;
  return GEOARROW_OK;
}
static int zgo_scan_null(struct GeoArrowVisitor *v) {
  ((zgo_scan_state *)v->private_data)->n_null++;
  return GEOARROW_OK;
}
static int zgo_scan_geom_start(struct GeoArrowVisitor *v, enum GeoArrowGeometryType type,
                               enum GeoArrowDimensions dims) {
  zgo_scan_state *s = (zgo_scan_state *)v->private_data;
  if (s->depth == 0) {
    s->types |= 1 << (int)type;
    s->dims |= 1 << (int)dims;
  }
  if (s->depth < ZGO_SCAN_DEPTH) s->type_at[s->depth] = (int)type;
  s->depth++;
  return GEOARROW_OK;
}
static int zgo_scan_coords(struct GeoArrowVisitor *v, const struct GeoArrowCoordView *c) {
  zgo_scan_state *s = (zgo_scan_state *)v->private_data;
  int d = s->depth - 1;
  if (d >= 0 && d < ZGO_SCAN_DEPTH && c->n_coords >= 2 &&
      (s->type_at[d] == GEOARROW_GEOMETRY_TYPE_LINESTRING ||
       s->type_at[d] == GEOARROW_GEOMETRY_TYPE_POLYGON)) {
    s->has_edges = 1;
  }
  return GEOARROW_OK;
}
static int zgo_scan_geom_end(struct GeoArrowVisitor *v) {
  ((zgo_scan_state *)v->private_data)->depth--;
  return GEOARROW_OK;
}

SEXP zgo_c_scan(SEXP chunks, SEXP schema, SEXP chunk, SEXP row) {
  R_xlen_t n = Rf_xlength(chunk);
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  zgo_readers readers;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  zgo_scan_state state;
  memset(&state, 0, sizeof(state));
  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  vis.feat_start = &zgo_scan_feat_start;
  vis.null_feat = &zgo_scan_null;
  vis.geom_start = &zgo_scan_geom_start;
  vis.geom_end = &zgo_scan_geom_end;
  vis.coords = &zgo_scan_coords;
  vis.private_data = &state;
  vis.error = &error;
  for (R_xlen_t p = 0; p < n; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (zgo_visit_feature(&col, k, r, &readers, &vis) != GEOARROW_OK) {
      snprintf(message, sizeof(message), "Could not read geometry %ld: %.400s",
               (long)(p + 1), error.message);
      zgo_scratch_run(scratch);
      UNPROTECT(1); return zgo_failure("layout", message);
    }
  }
  zgo_scratch_run(scratch);
  const char *names[] = {"types", "dims", "n_null", "has_edges", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  int nt = 0;
  for (int t = 1; t <= 7; t++) nt += (state.types >> t) & 1;
  SEXP types = PROTECT(Rf_allocVector(INTSXP, nt));
  for (int t = 1, i = 0; t <= 7; t++) {
    if ((state.types >> t) & 1) INTEGER(types)[i++] = t;
  }
  int nd = 0;
  for (int d = 1; d <= 4; d++) nd += (state.dims >> d) & 1;
  SEXP dims = PROTECT(Rf_allocVector(INTSXP, nd));
  for (int d = 1, i = 0; d <= 4; d++) {
    if ((state.dims >> d) & 1) INTEGER(dims)[i++] = d;
  }
  SET_VECTOR_ELT(out, 0, types);
  SET_VECTOR_ELT(out, 1, dims);
  SET_VECTOR_ELT(out, 2, Rf_ScalarInteger(state.n_null));
  SET_VECTOR_ELT(out, 3, Rf_ScalarLogical(state.has_edges));
  UNPROTECT(4);
  return out;
}

/* ---- Writing rows as another encoding --------------------------------- */

/* Sets ARROW:extension:metadata on a schema geoarrow-c made, from `text`
   (NA for none). */
static const char *zgo_set_extension_metadata(struct ArrowSchema *s, SEXP text) {
  if (TYPEOF(text) != STRSXP || STRING_ELT(text, 0) == NA_STRING) return NULL;
  struct ArrowBuffer buffer;
  if (ArrowMetadataBuilderInit(&buffer, s->metadata) != NANOARROW_OK) return "metadata";
  if (ArrowMetadataBuilderSet(&buffer, ArrowCharView("ARROW:extension:metadata"),
                              ArrowCharView(CHAR(STRING_ELT(text, 0)))) != NANOARROW_OK ||
      ArrowSchemaSetMetadata(s, (const char *)buffer.data) != NANOARROW_OK) {
    ArrowBufferReset(&buffer);
    return "metadata";
  }
  ArrowBufferReset(&buffer);
  return NULL;
}

/* The selected rows written through an array writer of `type` (a
   GeoArrowType). For WKB and WKT with `as_r`, an R list of raw vectors or a
   character vector; otherwise list(array, schema) handles, the schema
   carrying `metadata`. */
SEXP zgo_c_write(SEXP chunks, SEXP schema, SEXP chunk, SEXP row, SEXP type_sexp,
                 SEXP metadata, SEXP as_r_sexp) {
  R_xlen_t n = Rf_xlength(chunk);
  enum GeoArrowType type = (enum GeoArrowType)Rf_asInteger(type_sexp);
  int as_r = Rf_asLogical(as_r_sexp);
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  zgo_readers readers;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  struct GeoArrowArrayWriter *writer = zgo_writer_new(scratch, type);
  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  GeoArrowArrayWriterInitVisitor(writer, &vis);
  vis.error = &error;
  for (R_xlen_t p = 0; p < n; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (zgo_visit_feature(&col, k, r, &readers, &vis) != GEOARROW_OK) {
      snprintf(message, sizeof(message), "Could not convert geometry %ld: %.400s",
               (long)(p + 1), error.message);
      zgo_scratch_run(scratch);
      UNPROTECT(1); return zgo_failure("layout", message);
    }
  }
  struct ArrowArray *array = (struct ArrowArray *)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowArray), zgo_free_array);
  if (GeoArrowArrayWriterFinish(writer, array, &error) != GEOARROW_OK) {
    snprintf(message, sizeof(message), "Could not finish the conversion: %.400s",
             error.message);
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }

  if (as_r && (type == GEOARROW_TYPE_WKB || type == GEOARROW_TYPE_WKT)) {
    SEXP out = PROTECT(Rf_allocVector(type == GEOARROW_TYPE_WKB ? VECSXP : STRSXP, n));
    const uint8_t *validity = (const uint8_t *)array->buffers[0];
    const int32_t *offsets = (const int32_t *)array->buffers[1];
    const uint8_t *data = (const uint8_t *)array->buffers[2];
    for (R_xlen_t p = 0; p < n; p++) {
      int64_t i = array->offset + p;
      int is_null = validity != NULL && !ArrowBitGet(validity, i);
      int32_t a = offsets[i], b = offsets[i + 1];
      if (type == GEOARROW_TYPE_WKB) {
        if (is_null) continue;
        SEXP bytes = PROTECT(Rf_allocVector(RAWSXP, b - a));
        if (b > a) memcpy(RAW(bytes), data + a, (size_t)(b - a));
        SET_VECTOR_ELT(out, p, bytes);
        UNPROTECT(1);
      } else {
        SET_STRING_ELT(out, p,
                       is_null ? NA_STRING
                               : Rf_mkCharLenCE((const char *)data + a, b - a, CE_UTF8));
      }
    }
    zgo_scratch_run(scratch);
    UNPROTECT(2);
    return out;
  }

  /* The schema: geoarrow-c's for the type, with the source's metadata. */
  struct ArrowSchema *out_schema = (struct ArrowSchema *)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowSchema), zgo_free_schema_p);
  if (GeoArrowSchemaInitExtension(out_schema, type) != GEOARROW_OK ||
      zgo_set_extension_metadata(out_schema, metadata) != NULL) {
    zgo_scratch_run(scratch);
    Rf_error("Could not make the converted schema.");
  }
  struct ArrowSchema moved;
  ArrowSchemaMove(out_schema, &moved);
  struct ArrowArray moved_array;
  ArrowArrayMove(array, &moved_array);
  zgo_scratch_run(scratch);

  SEXP schema_out = PROTECT(zgo_schema_handle_finalized(&moved));
  SEXP array_out = PROTECT(zgo_array_handle(&moved_array, schema_out));
  const char *names[] = {"array", "schema", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, array_out);
  SET_VECTOR_ELT(out, 1, schema_out);
  UNPROTECT(4);
  return out;
}

static void zgo_schema_xptr_finalize(SEXP xptr) {
  struct ArrowSchema *s = (struct ArrowSchema *)R_ExternalPtrAddr(xptr);
  if (s == NULL) return;
  if (s->release != NULL) s->release(s);
  free(s);
  R_ClearExternalPtr(xptr);
}

/* A schema handle owning `schema` (moved from). */
static SEXP zgo_schema_handle_finalized(struct ArrowSchema *schema) {
  SEXP out = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(out, &zgo_schema_xptr_finalize, TRUE);
  struct ArrowSchema *owned = (struct ArrowSchema *)malloc(sizeof(struct ArrowSchema));
  if (owned == NULL) {
    schema->release(schema);
    Rf_error("Could not allocate a schema.");
  }
  ArrowSchemaMove(schema, owned);
  R_SetExternalPtrAddr(out, owned);
  SEXP klass = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(klass, 0, Rf_mkChar("zugeo_schema"));
  SET_STRING_ELT(klass, 1, Rf_mkChar("nanoarrow_schema"));
  Rf_setAttrib(out, R_ClassSymbol, klass);
  UNPROTECT(2);
  return out;
}

/* Points an array handle at its schema, as zuarrow reads it back. */
SEXP zgo_c_array_set_schema(SEXP array, SEXP schema) {
  zgo_array_from_xptr(array);
  R_SetExternalPtrTag(array, schema);
  return array;
}

/* ---- Reading WKB, EWKB and WKT ------------------------------------------ */

static uint32_t zgo_read_u32(const uint8_t *p, int little) {
  return little ? ((uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 |
                   (uint32_t)p[3] << 24)
                : ((uint32_t)p[3] | (uint32_t)p[2] << 8 | (uint32_t)p[1] << 16 |
                   (uint32_t)p[0] << 24);
}

#define ZGO_EWKB_SRID 0x20000000u

/* A list of raw vectors (NULL for null) read as WKB or EWKB, checked and
   written again as ISO little-endian WKB. Returns list(array, srid): the
   outer EWKB SRID of each element, NA where it has none (design section
   6.6, Q8: geoarrow-c reads past an SRID and drops it, so zugeo reads it
   first). */
SEXP zgo_c_from_wkb(SEXP x) {
  R_xlen_t n = Rf_xlength(x);
  SEXP srid = PROTECT(Rf_allocVector(INTSXP, n));
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_readers readers;
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  struct GeoArrowArrayWriter *writer = zgo_writer_new(scratch, GEOARROW_TYPE_WKB);
  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  GeoArrowArrayWriterInitVisitor(writer, &vis);
  vis.error = &error;
  char message[512];
  for (R_xlen_t i = 0; i < n; i++) {
    SEXP el = VECTOR_ELT(x, i);
    INTEGER(srid)[i] = NA_INTEGER;
    int status;
    if (Rf_isNull(el)) {
      status = vis.feat_start(&vis);
      if (status == GEOARROW_OK) status = vis.null_feat(&vis);
      if (status == GEOARROW_OK) status = vis.feat_end(&vis);
    } else if (TYPEOF(el) != RAWSXP) {
      snprintf(message, sizeof(message), "Element %ld is not a raw vector or NULL.",
               (long)(i + 1));
      zgo_scratch_run(scratch);
      UNPROTECT(2); return zgo_failure("layout", message);
    } else {
      const uint8_t *bytes = RAW(el);
      int64_t size = Rf_xlength(el);
      if (size >= 9 && (bytes[0] == 0 || bytes[0] == 1)) {
        uint32_t type = zgo_read_u32(bytes + 1, bytes[0] == 1);
        if (type & ZGO_EWKB_SRID) {
          uint32_t value = zgo_read_u32(bytes + 5, bytes[0] == 1);
          INTEGER(srid)[i] = value > (uint32_t)2147483647 ? NA_INTEGER : (int)value;
        }
      }
      struct GeoArrowBufferView src = {bytes, size};
      status = GeoArrowWKBReaderVisit(readers.wkb, src, &vis);
    }
    if (status != GEOARROW_OK) {
      snprintf(message, sizeof(message), "Element %ld is not valid WKB: %.400s",
               (long)(i + 1), error.message);
      zgo_scratch_run(scratch);
      UNPROTECT(2); return zgo_failure("layout", message);
    }
  }
  struct ArrowArray *array = (struct ArrowArray *)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowArray), zgo_free_array);
  if (GeoArrowArrayWriterFinish(writer, array, &error) != GEOARROW_OK) {
    zgo_scratch_run(scratch);
    Rf_error("Could not finish the WKB array.");
  }
  struct ArrowArray moved;
  ArrowArrayMove(array, &moved);
  zgo_scratch_run(scratch);
  const char *names[] = {"array", "srid", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, zgo_array_handle(&moved, R_NilValue));
  SET_VECTOR_ELT(out, 1, srid);
  UNPROTECT(3);
  return out;
}

/* A character vector of WKT (NA for null), each element checked by parsing
   it, kept byte for byte as a string array. */
SEXP zgo_c_from_wkt(SEXP x) {
  R_xlen_t n = Rf_xlength(x);
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_readers readers;
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  struct ArrowArray *array = (struct ArrowArray *)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowArray), zgo_free_array);
  array->release = NULL;
  if (ArrowArrayInitFromType(array, NANOARROW_TYPE_STRING) != NANOARROW_OK ||
      ArrowArrayStartAppending(array) != NANOARROW_OK) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the WKT array.");
  }
  struct GeoArrowError error;
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  vis.error = &error;
  char message[512];
  for (R_xlen_t i = 0; i < n; i++) {
    SEXP el = STRING_ELT(x, i);
    int status;
    if (el == NA_STRING) {
      status = ArrowArrayAppendNull(array, 1);
    } else {
      const char *text = Rf_translateCharUTF8(el);
      struct GeoArrowStringView src = {text, (int64_t)strlen(text)};
      error.message[0] = '\0';
      if (GeoArrowWKTReaderVisit(readers.wkt, src, &vis) != GEOARROW_OK) {
        snprintf(message, sizeof(message), "Element %ld is not valid WKT: %.400s",
                 (long)(i + 1), error.message);
        zgo_scratch_run(scratch);
        UNPROTECT(1); return zgo_failure("layout", message);
      }
      status = ArrowArrayAppendString(array, ArrowCharView(text));
    }
    if (status != NANOARROW_OK) {
      zgo_scratch_run(scratch);
      Rf_error("Could not append to the WKT array.");
    }
  }
  struct ArrowError nerror;
  if (ArrowArrayFinishBuildingDefault(array, &nerror) != NANOARROW_OK) {
    zgo_scratch_run(scratch);
    Rf_error("Could not finish the WKT array.");
  }
  struct ArrowArray moved;
  ArrowArrayMove(array, &moved);
  zgo_scratch_run(scratch);
  SEXP out = zgo_array_handle(&moved, R_NilValue);
  UNPROTECT(1);
  return out;
}

static int zgo_hex_digit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

/* Hex WKB text (NA for null) as a list of raw vectors. */
SEXP zgo_c_hex_to_raw(SEXP x) {
  R_xlen_t n = Rf_xlength(x);
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
  for (R_xlen_t i = 0; i < n; i++) {
    SEXP el = STRING_ELT(x, i);
    if (el == NA_STRING) continue;
    const char *text = CHAR(el);
    size_t len = strlen(text);
    /* Not reachable from R: geo_vctr() sends only strings of hex pairs here. */
    if (len % 2 != 0) {
      char message[96];
      snprintf(message, sizeof(message), "Element %ld is not hex WKB: odd length.", (long)(i + 1));
      UNPROTECT(1);
      return zgo_failure("layout", message);
    }
    SEXP bytes = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)(len / 2)));
    for (size_t j = 0; j < len / 2; j++) {
      int hi = zgo_hex_digit(text[2 * j]), lo = zgo_hex_digit(text[2 * j + 1]);
      if (hi < 0 || lo < 0) {
        char message[96];
        /* Not reachable from R, for the same reason: a guard for misuse. */
        snprintf(message, sizeof(message), "Element %ld is not hex WKB: '%c%c' is not a hex byte.",
                 (long)(i + 1), text[2 * j], text[2 * j + 1]);
        UNPROTECT(2);
        return zgo_failure("layout", message);
      }
      RAW(bytes)[j] = (Rbyte)(hi * 16 + lo);
    }
    SET_VECTOR_ELT(out, i, bytes);
    UNPROTECT(1);
  }
  UNPROTECT(1);
  return out;
}

/* ---- Coordinates as columns --------------------------------------------- */

#define ZGO_MAX_NESTING 32

typedef struct {
  struct ArrowBuffer x, y, z, m, feature, part, ring;
  int32_t feature_id, part_id, ring_id, depth;
  int type_at[ZGO_MAX_NESTING];
  int dims_at[ZGO_MAX_NESTING];
  int has_z, has_m;
} zgo_coords_state;

static void zgo_coords_reset(void *p) {
  zgo_coords_state *s = (zgo_coords_state *)p;
  ArrowBufferReset(&s->x);
  ArrowBufferReset(&s->y);
  ArrowBufferReset(&s->z);
  ArrowBufferReset(&s->m);
  ArrowBufferReset(&s->feature);
  ArrowBufferReset(&s->part);
  ArrowBufferReset(&s->ring);
}

static int zgo_coords_feat_start(struct GeoArrowVisitor *v) {
  zgo_coords_state *s = (zgo_coords_state *)v->private_data;
  s->feature_id++;
  s->part_id = 0;
  s->ring_id = 0;
  s->depth = 0;
  return GEOARROW_OK;
}

static int zgo_coords_geom_start(struct GeoArrowVisitor *v, enum GeoArrowGeometryType type,
                                 enum GeoArrowDimensions dims) {
  zgo_coords_state *s = (zgo_coords_state *)v->private_data;
  if (s->depth >= ZGO_MAX_NESTING) return EINVAL;
  /* A part is a simple geometry: the feature itself at the top, or each
     child of a multi-geometry or collection. */
  if (s->depth == 0 && type >= 1 && type <= 3) s->part_id = 1;
  if (s->depth == 1) s->part_id++;
  s->ring_id = 0;
  s->type_at[s->depth] = (int)type;
  s->dims_at[s->depth] = (int)dims;
  s->depth++;
  return GEOARROW_OK;
}

static int zgo_coords_ring_start(struct GeoArrowVisitor *v) {
  ((zgo_coords_state *)v->private_data)->ring_id++;
  return GEOARROW_OK;
}

static int zgo_coords_geom_end(struct GeoArrowVisitor *v) {
  ((zgo_coords_state *)v->private_data)->depth--;
  return GEOARROW_OK;
}

static int zgo_coords_coords(struct GeoArrowVisitor *v, const struct GeoArrowCoordView *c) {
  zgo_coords_state *s = (zgo_coords_state *)v->private_data;
  int type = s->depth > 0 ? s->type_at[s->depth - 1] : 0;
  int dims = s->depth > 0 ? s->dims_at[s->depth - 1] : 1;
  int zi = (dims == 2 || dims == 4) ? 2 : -1;
  int mi = dims == 3 ? 2 : (dims == 4 ? 3 : -1);
  if (zi >= 0) s->has_z = 1;
  if (mi >= 0) s->has_m = 1;
  for (int64_t i = 0; i < c->n_coords; i++) {
    double x = c->values[0][i * c->coords_stride];
    double y = c->values[1][i * c->coords_stride];
    /* An empty point is NaN NaN (format.md); it has no coordinates. */
    if (type == 1 && isnan(x) && isnan(y)) continue;
    double z = zi >= 0 ? c->values[zi][i * c->coords_stride] : NA_REAL;
    double m = mi >= 0 ? c->values[mi][i * c->coords_stride] : NA_REAL;
    int32_t ring = type == 3 ? s->ring_id : NA_INTEGER;
    if (ArrowBufferAppendDouble(&s->x, x) || ArrowBufferAppendDouble(&s->y, y) ||
        ArrowBufferAppendDouble(&s->z, z) || ArrowBufferAppendDouble(&s->m, m) ||
        ArrowBufferAppendInt32(&s->feature, s->feature_id) ||
        ArrowBufferAppendInt32(&s->part, s->part_id) ||
        ArrowBufferAppendInt32(&s->ring, ring)) {
      return ENOMEM;
    }
  }
  return GEOARROW_OK;
}

static SEXP zgo_buffer_doubles(struct ArrowBuffer *b) {
  R_xlen_t n = (R_xlen_t)(b->size_bytes / (int64_t)sizeof(double));
  SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
  if (n > 0) memcpy(REAL(out), b->data, (size_t)b->size_bytes);
  UNPROTECT(1);
  return out;
}

static SEXP zgo_buffer_ints(struct ArrowBuffer *b) {
  R_xlen_t n = (R_xlen_t)(b->size_bytes / (int64_t)sizeof(int32_t));
  SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
  if (n > 0) memcpy(INTEGER(out), b->data, (size_t)b->size_bytes);
  UNPROTECT(1);
  return out;
}

SEXP zgo_c_coords(SEXP chunks, SEXP schema, SEXP chunk, SEXP row) {
  R_xlen_t n = Rf_xlength(chunk);
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  zgo_readers readers;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  zgo_coords_state *state = (zgo_coords_state *)zgo_scratch_alloc(
      scratch, sizeof(zgo_coords_state), free);
  ArrowBufferInit(&state->x);
  ArrowBufferInit(&state->y);
  ArrowBufferInit(&state->z);
  ArrowBufferInit(&state->m);
  ArrowBufferInit(&state->feature);
  ArrowBufferInit(&state->part);
  ArrowBufferInit(&state->ring);
  zgo_scratch_add(scratch, zgo_coords_reset, state);

  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  vis.feat_start = &zgo_coords_feat_start;
  vis.geom_start = &zgo_coords_geom_start;
  vis.ring_start = &zgo_coords_ring_start;
  vis.coords = &zgo_coords_coords;
  vis.geom_end = &zgo_coords_geom_end;
  vis.private_data = state;
  vis.error = &error;
  for (R_xlen_t p = 0; p < n; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (zgo_visit_feature(&col, k, r, &readers, &vis) != GEOARROW_OK) {
      snprintf(message, sizeof(message), "Could not read geometry %ld: %.400s",
               (long)(p + 1), error.message);
      zgo_scratch_run(scratch);
      UNPROTECT(1); return zgo_failure("layout", message);
    }
  }

  const char *names[] = {"x", "y", "z", "m", "feature", "part", "ring", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, zgo_buffer_doubles(&state->x));
  SET_VECTOR_ELT(out, 1, zgo_buffer_doubles(&state->y));
  if (state->has_z) SET_VECTOR_ELT(out, 2, zgo_buffer_doubles(&state->z));
  if (state->has_m) SET_VECTOR_ELT(out, 3, zgo_buffer_doubles(&state->m));
  SET_VECTOR_ELT(out, 4, zgo_buffer_ints(&state->feature));
  SET_VECTOR_ELT(out, 5, zgo_buffer_ints(&state->part));
  SET_VECTOR_ELT(out, 6, zgo_buffer_ints(&state->ring));
  zgo_scratch_run(scratch);
  UNPROTECT(2);
  return out;
}

/* ---- Coordinates to geometries ---------------------------------------- */

typedef struct {
  const double *x, *y, *z, *m;
  int dims;
} zgo_coord_source;

static int zgo_emit_coords(struct GeoArrowVisitor *v, const zgo_coord_source *src,
                           R_xlen_t from, R_xlen_t to) {
  struct GeoArrowCoordView c;
  memset(&c, 0, sizeof(c));
  c.n_coords = to - from;
  c.coords_stride = 1;
  c.values[0] = src->x + from;
  c.values[1] = src->y + from;
  c.n_values = 2;
  if (src->dims == GEOARROW_DIMENSIONS_XYZ || src->dims == GEOARROW_DIMENSIONS_XYZM) {
    c.values[c.n_values++] = src->z + from;
  }
  if (src->dims == GEOARROW_DIMENSIONS_XYM || src->dims == GEOARROW_DIMENSIONS_XYZM) {
    c.values[c.n_values++] = src->m + from;
  }
  return v->coords(v, &c);
}

/* Rows [from, to) grouped by consecutive equal keys. */
static R_xlen_t zgo_run_end(const int *key, R_xlen_t from, R_xlen_t to) {
  R_xlen_t i = from + 1;
  while (i < to && key[i] == key[from]) i++;
  return i;
}

static int zgo_emit_polygon(struct GeoArrowVisitor *v, const zgo_coord_source *src,
                            const int *ring, R_xlen_t from, R_xlen_t to) {
  ZGO_TRY(v->geom_start(v, GEOARROW_GEOMETRY_TYPE_POLYGON,
                       (enum GeoArrowDimensions)src->dims));
  for (R_xlen_t a = from; a < to;) {
    R_xlen_t b = zgo_run_end(ring, a, to);
    ZGO_TRY(v->ring_start(v));
    ZGO_TRY(zgo_emit_coords(v, src, a, b));
    ZGO_TRY(v->ring_end(v));
    a = b;
  }
  return v->geom_end(v);
}

/* One feature of `type` from rows [from, to). EINVAL with *failure set for
   input that cannot form one. */
static int zgo_emit_feature(struct GeoArrowVisitor *v, const zgo_coord_source *src,
                            int type, const int *pid, const int *rid, R_xlen_t from,
                            R_xlen_t to, const char **failure) {
  enum GeoArrowDimensions dims = (enum GeoArrowDimensions)src->dims;
  ZGO_TRY(v->feat_start(v));
  switch (type) {
    case 1:
      if (to - from > 1) {
        *failure = "A point feature has more than one coordinate.";
        return EINVAL;
      }
      ZGO_TRY(v->geom_start(v, GEOARROW_GEOMETRY_TYPE_POINT, dims));
      if (to > from) ZGO_TRY(zgo_emit_coords(v, src, from, to));
      ZGO_TRY(v->geom_end(v));
      break;
    case 2:
      ZGO_TRY(v->geom_start(v, GEOARROW_GEOMETRY_TYPE_LINESTRING, dims));
      ZGO_TRY(zgo_emit_coords(v, src, from, to));
      ZGO_TRY(v->geom_end(v));
      break;
    case 3:
      ZGO_TRY(zgo_emit_polygon(v, src, rid, from, to));
      break;
    case 4:
      ZGO_TRY(v->geom_start(v, GEOARROW_GEOMETRY_TYPE_MULTIPOINT, dims));
      for (R_xlen_t a = from; a < to; a++) {
        ZGO_TRY(v->geom_start(v, GEOARROW_GEOMETRY_TYPE_POINT, dims));
        ZGO_TRY(zgo_emit_coords(v, src, a, a + 1));
        ZGO_TRY(v->geom_end(v));
      }
      ZGO_TRY(v->geom_end(v));
      break;
    case 5:
    case 6:
      ZGO_TRY(v->geom_start(v, (enum GeoArrowGeometryType)type, dims));
      for (R_xlen_t a = from; a < to;) {
        R_xlen_t b = zgo_run_end(pid, a, to);
        if (type == 5) {
          ZGO_TRY(v->geom_start(v, GEOARROW_GEOMETRY_TYPE_LINESTRING, dims));
          ZGO_TRY(zgo_emit_coords(v, src, a, b));
          ZGO_TRY(v->geom_end(v));
        } else {
          ZGO_TRY(zgo_emit_polygon(v, src, rid, a, b));
        }
        a = b;
      }
      ZGO_TRY(v->geom_end(v));
      break;
    default:
      *failure = "`type` must be a geometry type from 1 to 6.";
      return EINVAL;
  }
  return v->feat_end(v);
}

/* Columns of coordinates as features 1 to n_features of `type` (1 to 6),
   written through an array writer of `out_type`. Rows must be ordered by
   feature, then part, then ring; a feature with no rows is empty. */
SEXP zgo_c_from_coords(SEXP x, SEXP y, SEXP z, SEXP m, SEXP feature, SEXP part,
                       SEXP ring, SEXP n_features_sexp, SEXP type_sexp,
                       SEXP out_type_sexp) {
  R_xlen_t n = Rf_xlength(x);
  int type = Rf_asInteger(type_sexp);
  int n_features = Rf_asInteger(n_features_sexp);
  zgo_coord_source src = {REAL(x), REAL(y), Rf_isNull(z) ? NULL : REAL(z),
                          Rf_isNull(m) ? NULL : REAL(m), GEOARROW_DIMENSIONS_XY};
  if (src.z && src.m) {
    src.dims = GEOARROW_DIMENSIONS_XYZM;
  } else if (src.z) {
    src.dims = GEOARROW_DIMENSIONS_XYZ;
  } else if (src.m) {
    src.dims = GEOARROW_DIMENSIONS_XYM;
  }
  const int *fid = INTEGER(feature);
  const int *pid = INTEGER(part);
  const int *rid = INTEGER(ring);
  for (R_xlen_t i = 1; i < n; i++) {
    if (fid[i] < fid[i - 1]) return zgo_failure("", "`feature` must be in increasing order.");
  }
  for (R_xlen_t i = 0; i < n; i++) {
    if (fid[i] == NA_INTEGER || fid[i] < 1 || fid[i] > n_features) {
      return zgo_failure("", "`feature` must be between 1 and the number of features.");
    }
  }

  SEXP scratch = PROTECT(zgo_scratch_new());
  struct GeoArrowArrayWriter *writer =
      zgo_writer_new(scratch, (enum GeoArrowType)Rf_asInteger(out_type_sexp));
  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor v;
  GeoArrowVisitorInitVoid(&v);
  GeoArrowArrayWriterInitVisitor(writer, &v);
  v.error = &error;

  R_xlen_t i = 0;
  int status = GEOARROW_OK;
  const char *failure = NULL;
  for (int f = 1; f <= n_features && status == GEOARROW_OK; f++) {
    R_xlen_t from = i;
    while (i < n && fid[i] == f) i++;
    status = zgo_emit_feature(&v, &src, type, pid, rid, from, i, &failure);
  }
  if (failure == NULL && status != GEOARROW_OK) failure = error.message;
  char message[512];
  if (failure != NULL) {
    snprintf(message, sizeof(message), "Could not build geometries: %.400s", failure);
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }
  struct ArrowArray *array = (struct ArrowArray *)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowArray), zgo_free_array);
  if (GeoArrowArrayWriterFinish(writer, array, &error) != GEOARROW_OK) {
    snprintf(message, sizeof(message), "Could not finish the geometries: %.400s",
             error.message);
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }
  struct ArrowArray moved;
  ArrowArrayMove(array, &moved);
  zgo_scratch_run(scratch);
  SEXP out = zgo_array_handle(&moved, R_NilValue);
  UNPROTECT(1);
  return out;
}

/* The schema geoarrow-c makes for `type` (a GeoArrowType), with
   `metadata` as its extension metadata (NA for none). */
SEXP zgo_c_type_schema(SEXP type_sexp, SEXP metadata) {
  struct ArrowSchema schema;
  schema.release = NULL;
  if (GeoArrowSchemaInitExtension(&schema, (enum GeoArrowType)Rf_asInteger(type_sexp)) !=
          GEOARROW_OK ||
      zgo_set_extension_metadata(&schema, metadata) != NULL) {
    if (schema.release != NULL) schema.release(&schema);
    Rf_error("Could not make the schema for GeoArrow type %d.", Rf_asInteger(type_sexp));
  }
  return zgo_schema_handle_finalized(&schema);
}
