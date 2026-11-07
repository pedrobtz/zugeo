/* The array layer: reading GeoArrow arrays held by a geo_vctr (design
   section 6.1). Three operations over rows picked from several chunks:
   which are null, their WKT for format(), and gathering them into one new
   array for export.

   Native layouts are walked here, over nanoarrow array views, for every
   list width and for unions, which geoarrow-c's own array views cannot
   read (design D20). The walk drives geoarrow-c's GeoArrowVisitor, so its
   WKT writer, and later its WKB writer, consume it unchanged: the start
   of design D15's visitor.

   C heap state (array views, writers, built arrays) is owned by a scratch
   external pointer from the moment it exists, so an R error part way
   through leaks nothing. */

#include "zgo.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zgo_array.h"

/* ---- Scratch: C resources an external pointer owns ------------------- */

typedef struct zgo_cleanup {
  void (*fn)(void *);
  void *p;
  struct zgo_cleanup *next;
} zgo_cleanup;

void zgo_scratch_run(SEXP xptr) {
  zgo_cleanup *c = (zgo_cleanup *)R_ExternalPtrAddr(xptr);
  while (c != NULL) {
    zgo_cleanup *next = c->next;
    if (c->fn != NULL) c->fn(c->p);
    free(c);
    c = next;
  }
  R_ClearExternalPtr(xptr);
}

SEXP zgo_scratch_new(void) {
  SEXP xptr = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(xptr, &zgo_scratch_run, TRUE);
  UNPROTECT(1);
  return xptr;
}

/* Registers `p` for `fn`; on allocation failure frees it at once and
   raises. */
void zgo_scratch_add(SEXP scratch, void (*fn)(void *), void *p) {
  zgo_cleanup *c = (zgo_cleanup *)malloc(sizeof(zgo_cleanup));
  if (c == NULL) {
    fn(p);
    Rf_error("Could not allocate memory.");
  }
  c->fn = fn;
  c->p = p;
  c->next = (zgo_cleanup *)R_ExternalPtrAddr(scratch);
  R_SetExternalPtrAddr(scratch, c);
}

void *zgo_scratch_alloc(SEXP scratch, size_t size, void (*reset)(void *)) {
  void *p = calloc(1, size);
  if (p == NULL) Rf_error("Could not allocate memory.");
  zgo_scratch_add(scratch, reset, p);
  return p;
}

static void zgo_free_view(void *p) {
  ArrowArrayViewReset((struct ArrowArrayView *)p);
  free(p);
}

void zgo_free_array(void *p) {
  struct ArrowArray *a = (struct ArrowArray *)p;
  if (a->release != NULL) a->release(a);
  free(p);
}

/* Resets only; the memory itself is freed by its own cleanup entry. */
static void zgo_reset_wkt_writer(void *p) {
  GeoArrowWKTWriterReset((struct GeoArrowWKTWriter *)p);
}

static void zgo_reset_wkb_reader(void *p) {
  GeoArrowWKBReaderReset((struct GeoArrowWKBReader *)p);
}

static void zgo_reset_wkt_reader(void *p) {
  GeoArrowWKTReaderReset((struct GeoArrowWKTReader *)p);
}

/* Both serialized readers, owned by scratch. 0 on success. */
int zgo_readers_init(SEXP scratch, zgo_readers *readers) {
  readers->wkb = (struct GeoArrowWKBReader *)zgo_scratch_alloc(
      scratch, sizeof(struct GeoArrowWKBReader), free);
  if (GeoArrowWKBReaderInit(readers->wkb) != GEOARROW_OK) return 1;
  zgo_scratch_add(scratch, zgo_reset_wkb_reader, readers->wkb);
  readers->wkt = (struct GeoArrowWKTReader *)zgo_scratch_alloc(
      scratch, sizeof(struct GeoArrowWKTReader), free);
  if (GeoArrowWKTReaderInit(readers->wkt) != GEOARROW_OK) return 1;
  zgo_scratch_add(scratch, zgo_reset_wkt_reader, readers->wkt);
  return 0;
}

/* ---- Handles and views ----------------------------------------------- */

const struct ArrowArray *zgo_array_from_xptr(SEXP x) {
  if (TYPEOF(x) != EXTPTRSXP || !Rf_inherits(x, "nanoarrow_array")) {
    Rf_error("Expected an array handle.");
  }
  const struct ArrowArray *a = (const struct ArrowArray *)R_ExternalPtrAddr(x);
  if (a == NULL || a->release == NULL) Rf_error("The array handle has been released.");
  return a;
}

/* Array views of every chunk, owned by `scratch`. NULL and a message on
   failure; nothing to free then beyond what scratch owns. */
const char *zgo_column_init(SEXP scratch, SEXP chunks, SEXP schema,
                                   zgo_column *col, char *message, size_t n) {
  col->schema = zgo_schema_from_xptr(schema);
  col->code = zgo_extension_code(col->schema);
  if (col->code < 0) return "The schema is not a GeoArrow field.";
  col->dims = (col->code >= 1 && col->code <= 6)
                  ? zgo_native_dims(col->schema, col->code)
                  : 0;
  col->n_chunks = (int)Rf_xlength(chunks);
  col->views = (struct ArrowArrayView **)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowArrayView *) * (size_t)(col->n_chunks + 1), free);
  for (int k = 0; k < col->n_chunks; k++) {
    const struct ArrowArray *array = zgo_array_from_xptr(VECTOR_ELT(chunks, k));
    struct ArrowArrayView *view =
        (struct ArrowArrayView *)zgo_scratch_alloc(scratch, sizeof(*view), zgo_free_view);
    struct ArrowError error;
    if (ArrowArrayViewInitFromSchema(view, col->schema, &error) != NANOARROW_OK ||
        ArrowArrayViewSetArray(view, array, &error) != NANOARROW_OK) {
      snprintf(message, n, "Chunk %d does not match its schema: %.400s", k + 1,
               error.message);
      return message;
    }
    col->views[k] = view;
  }
  return NULL;
}

/* Is element i of view v null? A union has no validity of its own: an
   element is null when the child element it points to is. */
int zgo_is_null(const struct ArrowArrayView *v, int64_t i) {
  if (v->storage_type == NANOARROW_TYPE_DENSE_UNION ||
      v->storage_type == NANOARROW_TYPE_SPARSE_UNION) {
    int8_t k = ArrowArrayViewUnionChildIndex(v, i);
    return ArrowArrayViewIsNull(v->children[k], ArrowArrayViewUnionChildOffset(v, i));
  }
  return ArrowArrayViewIsNull(v, i);
}

/* Reads the (chunk, row) of position p, 0-based, from R vectors; -1 for NA. */
int zgo_position(SEXP chunk, SEXP row, R_xlen_t p, int n_chunks, int64_t *out_row) {
  int k = INTEGER(chunk)[p];
  double r = REAL(row)[p];
  if (k == NA_INTEGER || ISNAN(r)) return -1;
  if (k < 0 || k >= n_chunks || r < 0) Rf_error("A geo_vctr position is out of range.");
  *out_row = (int64_t)r;
  return k;
}

/* ---- is.na() ----------------------------------------------------------- */

SEXP zgo_c_is_na(SEXP chunks, SEXP schema, SEXP chunk, SEXP row) {
  R_xlen_t n = Rf_xlength(chunk);
  SEXP out = PROTECT(Rf_allocVector(LGLSXP, n));
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    Rf_error("%s", message);
  }
  for (R_xlen_t p = 0; p < n; p++) {
    int64_t r;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (k < 0) {
      LOGICAL(out)[p] = TRUE;
      continue;
    }
    if (r >= col.views[k]->length) {
      zgo_scratch_run(scratch);
      Rf_error("A geo_vctr position is past the end of its chunk.");
    }
    LOGICAL(out)[p] = zgo_is_null(col.views[k], r);
  }
  zgo_scratch_run(scratch);
  UNPROTECT(2);
  return out;
}

/* ---- The walk: native buffers into a GeoArrowVisitor -------------------- */

#define ZGO_RETURN(x)              \
  do {                             \
    int status_ = (x);             \
    if (status_ != GEOARROW_OK) return status_; \
  } while (0)

/* n coordinates from element `start` of the coordinate view cv (a struct
   of doubles, or a fixed-size list of doubles). */
static int zgo_visit_coords(const struct ArrowArrayView *cv, int64_t start, int64_t n,
                            struct GeoArrowVisitor *vis) {
  struct GeoArrowCoordView c;
  memset(&c, 0, sizeof(c));
  c.n_coords = n;
  if (cv->storage_type == NANOARROW_TYPE_STRUCT) {
    c.n_values = (int32_t)cv->n_children;
    c.coords_stride = 1;
    for (int32_t d = 0; d < c.n_values; d++) {
      const struct ArrowArrayView *ch = cv->children[d];
      c.values[d] = ch->buffer_views[1].data.as_double + ch->offset + cv->offset + start;
    }
  } else {
    int32_t nd = (int32_t)cv->layout.child_size_elements;
    const struct ArrowArrayView *ch = cv->children[0];
    const double *base =
        ch->buffer_views[1].data.as_double + ch->offset + (cv->offset + start) * nd;
    c.n_values = nd;
    c.coords_stride = nd;
    for (int32_t d = 0; d < nd; d++) c.values[d] = base + d;
  }
  return vis->coords(vis, &c);
}

static void zgo_list_range(const struct ArrowArrayView *v, int64_t i, int64_t *a,
                           int64_t *b) {
  *a = ArrowArrayViewListChildOffset(v, i);
  *b = ArrowArrayViewListChildOffset(v, i + 1);
}

static int zgo_visit_union(const struct ArrowArrayView *v, int64_t i,
                           struct GeoArrowVisitor *vis);

/* Element i of view v, a native geometry of `type` (1 to 7) and `dims`. */
static int zgo_visit_geom(const struct ArrowArrayView *v, int64_t i, int type, int dims,
                          struct GeoArrowVisitor *vis) {
  int64_t a, b, c, d;
  enum GeoArrowDimensions gdims = (enum GeoArrowDimensions)dims;
  ZGO_RETURN(vis->geom_start(vis, (enum GeoArrowGeometryType)type, gdims));
  switch (type) {
    case 1:
      ZGO_RETURN(zgo_visit_coords(v, i, 1, vis));
      break;
    case 2:
      zgo_list_range(v, i, &a, &b);
      ZGO_RETURN(zgo_visit_coords(v->children[0], a, b - a, vis));
      break;
    case 3: {
      const struct ArrowArrayView *rings = v->children[0];
      zgo_list_range(v, i, &a, &b);
      for (int64_t r = a; r < b; r++) {
        ZGO_RETURN(vis->ring_start(vis));
        zgo_list_range(rings, r, &c, &d);
        ZGO_RETURN(zgo_visit_coords(rings->children[0], c, d - c, vis));
        ZGO_RETURN(vis->ring_end(vis));
      }
      break;
    }
    case 4:
      zgo_list_range(v, i, &a, &b);
      for (int64_t j = a; j < b; j++) {
        ZGO_RETURN(vis->geom_start(vis, GEOARROW_GEOMETRY_TYPE_POINT, gdims));
        ZGO_RETURN(zgo_visit_coords(v->children[0], j, 1, vis));
        ZGO_RETURN(vis->geom_end(vis));
      }
      break;
    case 5:
    case 6:
      zgo_list_range(v, i, &a, &b);
      for (int64_t j = a; j < b; j++) {
        ZGO_RETURN(zgo_visit_geom(v->children[0], j, type - 3, dims, vis));
      }
      break;
    case 7:
      zgo_list_range(v, i, &a, &b);
      for (int64_t j = a; j < b; j++) {
        ZGO_RETURN(zgo_visit_union(v->children[0], j, vis));
      }
      break;
    default:
      return EINVAL;
  }
  return vis->geom_end(vis);
}

/* Element i of a union view: its type id gives the child's geometry type
   and dimensions (format.md's table). */
static int zgo_visit_union(const struct ArrowArrayView *v, int64_t i,
                           struct GeoArrowVisitor *vis) {
  int id = ArrowArrayViewUnionTypeId(v, i);
  int8_t k = ArrowArrayViewUnionChildIndex(v, i);
  int64_t o = ArrowArrayViewUnionChildOffset(v, i);
  return zgo_visit_geom(v->children[k], o, id % 10, id / 10 + 1, vis);
}

/* One feature: element r of the column's chunk view, or a null. */
int zgo_visit_feature(const zgo_column *col, int k, int64_t r, zgo_readers *readers,
                      struct GeoArrowVisitor *vis) {
  /* geoarrow-c's WKB and WKT visits make their own feat_start() and
     feat_end(). */
  if (col->code == ZGO_CODE_WKB && k >= 0 && !zgo_is_null(col->views[k], r)) {
    struct ArrowBufferView bytes = ArrowArrayViewGetBytesUnsafe(col->views[k], r);
    struct GeoArrowBufferView src = {bytes.data.as_uint8, bytes.size_bytes};
    return GeoArrowWKBReaderVisit(readers->wkb, src, vis);
  }
  if (col->code == ZGO_CODE_WKT && k >= 0 && !zgo_is_null(col->views[k], r)) {
    struct ArrowStringView text = ArrowArrayViewGetStringUnsafe(col->views[k], r);
    struct GeoArrowStringView src = {text.data, text.size_bytes};
    return GeoArrowWKTReaderVisit(readers->wkt, src, vis);
  }
  ZGO_RETURN(vis->feat_start(vis));
  if (k < 0 || zgo_is_null(col->views[k], r)) {
    ZGO_RETURN(vis->null_feat(vis));
  } else {
    const struct ArrowArrayView *v = col->views[k];
    if (col->code == 0) {
      ZGO_RETURN(zgo_visit_union(v, r, vis));
    } else if (col->code >= 1 && col->code <= 7) {
      if (col->code == 7) {
        /* A collection's dimensions come from its union children. */
        int64_t a, b;
        zgo_list_range(v, r, &a, &b);
        int dims = GEOARROW_DIMENSIONS_XY;
        if (b > a) {
          int id = ArrowArrayViewUnionTypeId(v->children[0], a);
          dims = id / 10 + 1;
        }
        ZGO_RETURN(zgo_visit_geom(v, r, 7, dims, vis));
      } else {
        ZGO_RETURN(zgo_visit_geom(v, r, col->code, col->dims, vis));
      }
    } else {
      return EINVAL;
    }
  }
  return vis->feat_end(vis);
}

/* ---- format(): WKT -------------------------------------------------------- */

static SEXP zgo_box_text(const struct ArrowArrayView *v, int64_t r) {
  int n = (int)v->n_children / 2;
  char buf[512];
  int len = snprintf(buf, sizeof(buf), "BOX (");
  for (int half = 0; half < 2; half++) {
    for (int d = 0; d < n; d++) {
      const struct ArrowArrayView *ch = v->children[half * n + d];
      double x = ArrowArrayViewGetDoubleUnsafe(ch, v->offset + r);
      len += snprintf(buf + len, sizeof(buf) - (size_t)len, d ? " %.15g" : "%.15g", x);
    }
    len += snprintf(buf + len, sizeof(buf) - (size_t)len, half ? ")" : ", ");
  }
  return Rf_mkCharCE(buf, CE_UTF8);
}

SEXP zgo_c_format(SEXP chunks, SEXP schema, SEXP chunk, SEXP row, SEXP max_bytes) {
  R_xlen_t n = Rf_xlength(chunk);
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    Rf_error("%s", message);
  }

  for (R_xlen_t p = 0; p < n; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (k >= 0 && r >= col.views[k]->length) {
      zgo_scratch_run(scratch);
      Rf_error("A geo_vctr position is past the end of its chunk.");
    }
    if (k < 0 || zgo_is_null(col.views[k], r)) {
      SET_STRING_ELT(out, p, NA_STRING);
    } else if (col.code == ZGO_CODE_WKT) {
      struct ArrowStringView s = ArrowArrayViewGetStringUnsafe(col.views[k], r);
      SET_STRING_ELT(out, p, Rf_mkCharLenCE(s.data, (int)s.size_bytes, CE_UTF8));
    } else if (col.code == ZGO_CODE_BOX) {
      SET_STRING_ELT(out, p, zgo_box_text(col.views[k], r));
    }
  }
  if (col.code == ZGO_CODE_WKT || col.code == ZGO_CODE_BOX) {
    zgo_scratch_run(scratch);
    UNPROTECT(2);
    return out;
  }

  /* Geometries: through geoarrow-c's WKT writer, one feature per position. */
  struct GeoArrowWKTWriter *writer = (struct GeoArrowWKTWriter *)zgo_scratch_alloc(
      scratch, sizeof(struct GeoArrowWKTWriter), free);
  int status = GeoArrowWKTWriterInit(writer);
  if (status == GEOARROW_OK) {
    /* From now on the reset frees what Init allocated. */
    zgo_scratch_add(scratch, zgo_reset_wkt_writer, writer);
  }
  if (status != GEOARROW_OK) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the WKT writer.");
  }
  writer->max_element_size_bytes = (int64_t)Rf_asReal(max_bytes);

  zgo_readers readers;
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  GeoArrowWKTWriterInitVisitor(writer, &vis);
  vis.error = &error;
  for (R_xlen_t p = 0; p < n && status == GEOARROW_OK; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    status = zgo_visit_feature(&col, k, r, &readers, &vis);
    /* EAGAIN: the writer reached max_element_size_bytes and stopped the
       feature early; it is ended here, as geoarrow-c's own reader does. */
    if (status == EAGAIN) status = vis.feat_end(&vis);
  }
  struct ArrowArray *text =
      (struct ArrowArray *)zgo_scratch_alloc(scratch, sizeof(struct ArrowArray), zgo_free_array);
  if (status == GEOARROW_OK) status = GeoArrowWKTWriterFinish(writer, text, &error);
  if (status != GEOARROW_OK) {
    snprintf(message, sizeof(message), "Could not write WKT: %.400s", error.message);
    zgo_scratch_run(scratch);
    Rf_error("%s", message);
  }

  const int32_t *offsets = (const int32_t *)text->buffers[1];
  const char *data = (const char *)text->buffers[2];
  const uint8_t *validity = (const uint8_t *)text->buffers[0];
  for (R_xlen_t p = 0; p < n; p++) {
    if (validity != NULL && !ArrowBitGet(validity, text->offset + p)) {
      SET_STRING_ELT(out, p, NA_STRING);
    } else {
      int32_t a = offsets[text->offset + p], b = offsets[text->offset + p + 1];
      SET_STRING_ELT(out, p, Rf_mkCharLenCE(data + a, b - a, CE_UTF8));
    }
  }
  zgo_scratch_run(scratch);
  UNPROTECT(2);
  return out;
}

/* ---- Gathering rows into one array, for export -------------------------- */

/* Appends element i of view v to dst, which was made from the same
   schema. Only the outer level may be null (format.md, "Missing values");
   a null inside is a layout error. */
static const char *zgo_append(struct ArrowArray *dst, const struct ArrowArrayView *v,
                              int64_t i, int outer) {
  if (!outer && ArrowArrayViewIsNull(v, i)) {
    return "A geometry has a null inside it, which GeoArrow forbids.";
  }
  switch (v->storage_type) {
    case NANOARROW_TYPE_DOUBLE:
      return ArrowArrayAppendDouble(dst, ArrowArrayViewGetDoubleUnsafe(v, i)) ? "append" : NULL;
    case NANOARROW_TYPE_STRUCT:
      for (int64_t c = 0; c < v->n_children; c++) {
        const char *m = zgo_append(dst->children[c], v->children[c], v->offset + i, 0);
        if (m) return m;
      }
      return ArrowArrayFinishElement(dst) ? "append" : NULL;
    case NANOARROW_TYPE_FIXED_SIZE_LIST: {
      int64_t nd = v->layout.child_size_elements;
      for (int64_t d = 0; d < nd; d++) {
        const char *m =
            zgo_append(dst->children[0], v->children[0], (v->offset + i) * nd + d, 0);
        if (m) return m;
      }
      return ArrowArrayFinishElement(dst) ? "append" : NULL;
    }
    case NANOARROW_TYPE_LIST:
    case NANOARROW_TYPE_LARGE_LIST: {
      int64_t a, b;
      zgo_list_range(v, i, &a, &b);
      for (int64_t j = a; j < b; j++) {
        const char *m = zgo_append(dst->children[0], v->children[0], j, 0);
        if (m) return m;
      }
      return ArrowArrayFinishElement(dst) ? "append" : NULL;
    }
    case NANOARROW_TYPE_DENSE_UNION: {
      int8_t k = ArrowArrayViewUnionChildIndex(v, i);
      int64_t o = ArrowArrayViewUnionChildOffset(v, i);
      const char *m = zgo_append(dst->children[k], v->children[k], o, 0);
      if (m) return m;
      /* Built with type id = child index; zgo_remap_union_ids() fixes it. */
      return ArrowArrayFinishUnionElement(dst, k) ? "append" : NULL;
    }
    case NANOARROW_TYPE_BINARY:
    case NANOARROW_TYPE_LARGE_BINARY:
    case NANOARROW_TYPE_BINARY_VIEW:
    case NANOARROW_TYPE_STRING:
    case NANOARROW_TYPE_LARGE_STRING:
    case NANOARROW_TYPE_STRING_VIEW:
      return ArrowArrayAppendBytes(dst, ArrowArrayViewGetBytesUnsafe(v, i)) ? "append" : NULL;
    default:
      return "A storage type GeoArrow does not use.";
  }
}

/* A null at the outer level. A union has no validity of its own, so its
   null is a null element of a child: the one the source pointed to, or
   the first for an NA position (k < 0). */
static const char *zgo_append_null(struct ArrowArray *dst, const zgo_column *col, int k,
                                   int64_t r) {
  const struct ArrowArrayView *v = col->views[k < 0 ? 0 : k];
  if (v->storage_type == NANOARROW_TYPE_DENSE_UNION) {
    int8_t child = k >= 0 ? ArrowArrayViewUnionChildIndex(v, r) : 0;
    if (ArrowArrayAppendNull(dst->children[child], 1) != NANOARROW_OK) return "append";
    return ArrowArrayFinishUnionElement(dst, child) ? "append" : NULL;
  }
  return ArrowArrayAppendNull(dst, 1) ? "append" : NULL;
}

/* nanoarrow builds a union only when its type ids are its child indices.
   GeoArrow's are not (1, 2, 11, ...), so arrays are built from a copy of
   the schema whose unions say "+ud:0,1,...", and the type id buffers are
   rewritten to the real ids afterwards. Neither step changes a value. */
static int zgo_default_union_ids(struct ArrowSchema *s) {
  if (strncmp(s->format, "+ud:", 4) == 0) {
    char format[4 + 4 * 128 + 1];
    int len = snprintf(format, sizeof(format), "+ud:");
    for (int64_t c = 0; c < s->n_children && len < (int)sizeof(format) - 5; c++) {
      len += snprintf(format + len, sizeof(format) - (size_t)len, c ? ",%d" : "%d", (int)c);
    }
    if (ArrowSchemaSetFormat(s, format) != NANOARROW_OK) return 1;
  }
  for (int64_t c = 0; c < s->n_children; c++) {
    if (zgo_default_union_ids(s->children[c])) return 1;
  }
  return 0;
}

static void zgo_remap_union_ids(struct ArrowArray *a, const struct ArrowSchema *s) {
  if (strncmp(s->format, "+ud:", 4) == 0) {
    int8_t ids[128];
    const char *p = s->format + 4;
    for (int64_t c = 0; c < s->n_children && c < 128; c++) {
      ids[c] = (int8_t)strtol(p, (char **)&p, 10);
      if (*p == ',') p++;
    }
    int8_t *type_ids = (int8_t *)a->buffers[0];
    for (int64_t i = 0; i < a->length; i++) {
      type_ids[a->offset + i] = ids[type_ids[a->offset + i]];
    }
  }
  for (int64_t c = 0; c < a->n_children; c++) {
    zgo_remap_union_ids(a->children[c], s->children[c]);
  }
}

static void zgo_free_schema(void *p) {
  struct ArrowSchema *s = (struct ArrowSchema *)p;
  if (s->release != NULL) s->release(s);
  free(p);
}

void zgo_array_finalize(SEXP xptr) {
  struct ArrowArray *a = (struct ArrowArray *)R_ExternalPtrAddr(xptr);
  if (a == NULL) return;
  if (a->release != NULL) a->release(a);
  free(a);
  R_ClearExternalPtr(xptr);
}

SEXP zgo_c_take(SEXP chunks, SEXP schema, SEXP chunk, SEXP row) {
  R_xlen_t n = Rf_xlength(chunk);
  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    Rf_error("%s", message);
  }

  /* The result is owned by its handle before anything is built. */
  SEXP out = PROTECT(R_MakeExternalPtr(NULL, schema, R_NilValue));
  R_RegisterCFinalizerEx(out, &zgo_array_finalize, TRUE);
  struct ArrowArray *dst = (struct ArrowArray *)malloc(sizeof(struct ArrowArray));
  if (dst == NULL) {
    zgo_scratch_run(scratch);
    Rf_error("Could not allocate an array.");
  }
  dst->release = NULL;
  R_SetExternalPtrAddr(out, dst);

  struct ArrowError error;
  const char *failure = NULL;
  error.message[0] = '\0';
  struct ArrowSchema *build = (struct ArrowSchema *)zgo_scratch_alloc(
      scratch, sizeof(struct ArrowSchema), zgo_free_schema);
  if (ArrowSchemaDeepCopy(col.schema, build) != NANOARROW_OK ||
      zgo_default_union_ids(build)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not copy the schema.");
  }
  if (ArrowArrayInitFromSchema(dst, build, &error) != NANOARROW_OK ||
      ArrowArrayStartAppending(dst) != NANOARROW_OK) {
    snprintf(message, sizeof(message), "Could not start building the array: %.400s",
             error.message);
    failure = message;
  }
  for (R_xlen_t p = 0; p < n && failure == NULL; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (k >= 0 && r >= col.views[k]->length) {
      failure = "A geo_vctr position is past the end of its chunk.";
    } else if (k < 0 || zgo_is_null(col.views[k], r)) {
      failure = zgo_append_null(dst, &col, k, r);
    } else {
      failure = zgo_append(dst, col.views[k], r, 1);
    }
  }
  if (failure == NULL && ArrowArrayFinishBuildingDefault(dst, &error) != NANOARROW_OK) {
    snprintf(message, sizeof(message), "Could not finish the array: %.400s", error.message);
    failure = message;
  }
  if (failure != NULL) {
    if (strcmp(failure, "append") == 0) failure = "Could not append to the array.";
    if (failure != message) snprintf(message, sizeof(message), "%s", failure);
    zgo_scratch_run(scratch);
    Rf_error("%s", message);
  }
  zgo_remap_union_ids(dst, col.schema);
  zgo_scratch_run(scratch);

  SEXP klass = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(klass, 0, Rf_mkChar("zugeo_array"));
  SET_STRING_ELT(klass, 1, Rf_mkChar("nanoarrow_array"));
  Rf_setAttrib(out, R_ClassSymbol, klass);
  UNPROTECT(3);
  return out;
}

/* The length of an array handle, as a double. */
SEXP zgo_c_array_length(SEXP array) {
  return Rf_ScalarReal((double)zgo_array_from_xptr(array)->length);
}
