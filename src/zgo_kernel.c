/* Kernels over the buffers (design sections 6.7 and 6.11): per-row boxes,
   types, dimensions and coordinate counts in one walk, flatbush's Hilbert
   index, and validation findings. Each is a GeoArrowVisitor over
   zgo_visit_feature(), the walk of design D15 and D21, so every layout
   zugeo reads has them. */

#include "zgo_array.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ZGO_KERNEL_DEPTH 32

/* ---- One walk: box, type, dimensions, coordinate count ---------------- */

typedef struct {
  double *xmin, *ymin, *xmax, *ymax, *zmin, *zmax, *mmin, *mmax;
  int *type, *dims, *n_coords;
  R_xlen_t row;
  int depth;
  int type_at[ZGO_KERNEL_DEPTH];
  int dims_at[ZGO_KERNEL_DEPTH];
  int null;
  int any_z, any_m;
} zgo_info_state;

static int zgo_info_feat_start(struct GeoArrowVisitor *v) {
  zgo_info_state *s = (zgo_info_state *)v->private_data;
  R_xlen_t i = s->row;
  s->depth = 0;
  s->null = 0;
  /* An empty geometry's box is all NaN; each coordinate narrows it. */
  s->xmin[i] = s->ymin[i] = s->zmin[i] = s->mmin[i] = R_PosInf;
  s->xmax[i] = s->ymax[i] = s->zmax[i] = s->mmax[i] = R_NegInf;
  s->type[i] = NA_INTEGER;
  s->dims[i] = NA_INTEGER;
  s->n_coords[i] = 0;
  return GEOARROW_OK;
}

static int zgo_info_null(struct GeoArrowVisitor *v) {
  ((zgo_info_state *)v->private_data)->null = 1;
  return GEOARROW_OK;
}

static int zgo_info_geom_start(struct GeoArrowVisitor *v, enum GeoArrowGeometryType type,
                               enum GeoArrowDimensions dims) {
  zgo_info_state *s = (zgo_info_state *)v->private_data;
  if (s->depth == 0) {
    s->type[s->row] = (int)type;
    s->dims[s->row] = (int)dims;
  }
  if (s->depth < ZGO_KERNEL_DEPTH) {
    s->type_at[s->depth] = (int)type;
    s->dims_at[s->depth] = (int)dims;
  }
  s->depth++;
  return GEOARROW_OK;
}

static int zgo_info_geom_end(struct GeoArrowVisitor *v) {
  ((zgo_info_state *)v->private_data)->depth--;
  return GEOARROW_OK;
}

static void zgo_narrow(double *lo, double *hi, double value) {
  if (value < *lo) *lo = value;
  if (value > *hi) *hi = value;
}

static int zgo_info_coords(struct GeoArrowVisitor *v, const struct GeoArrowCoordView *c) {
  zgo_info_state *s = (zgo_info_state *)v->private_data;
  int d = s->depth - 1;
  if (d < 0) return EINVAL;
  if (d >= ZGO_KERNEL_DEPTH) d = ZGO_KERNEL_DEPTH - 1;
  int type = s->type_at[d], dims = s->dims_at[d];
  int zi = (dims == 2 || dims == 4) ? 2 : -1;
  int mi = dims == 3 ? 2 : (dims == 4 ? 3 : -1);
  R_xlen_t i = s->row;
  for (int64_t k = 0; k < c->n_coords; k++) {
    double x = c->values[0][k * c->coords_stride];
    double y = c->values[1][k * c->coords_stride];
    /* An empty point (NaN NaN) has no coordinates (format.md). */
    if (type == 1 && isnan(x) && isnan(y)) continue;
    s->n_coords[i]++;
    zgo_narrow(&s->xmin[i], &s->xmax[i], x);
    zgo_narrow(&s->ymin[i], &s->ymax[i], y);
    if (zi >= 0) {
      s->any_z = 1;
      zgo_narrow(&s->zmin[i], &s->zmax[i], c->values[zi][k * c->coords_stride]);
    }
    if (mi >= 0) {
      s->any_m = 1;
      zgo_narrow(&s->mmin[i], &s->mmax[i], c->values[mi][k * c->coords_stride]);
    }
  }
  return GEOARROW_OK;
}

static int zgo_info_feat_end(struct GeoArrowVisitor *v) {
  zgo_info_state *s = (zgo_info_state *)v->private_data;
  R_xlen_t i = s->row;
  double *lo[] = {s->xmin, s->ymin, s->zmin, s->mmin};
  double *hi[] = {s->xmax, s->ymax, s->zmax, s->mmax};
  for (int k = 0; k < 4; k++) {
    if (s->null) {
      lo[k][i] = hi[k][i] = NA_REAL;
    } else if (lo[k][i] > hi[k][i]) {
      /* No coordinate reached this dimension: empty. */
      lo[k][i] = hi[k][i] = R_NaN;
    }
  }
  if (s->null) s->n_coords[i] = NA_INTEGER;
  s->row++;
  return GEOARROW_OK;
}

/* Per row: list(xmin, ymin, xmax, ymax, zmin, zmax, mmin, mmax, type, dims,
   n_coords, any_z, any_m). A null row is NA throughout; an empty one has
   NaN bounds and 0 coordinates. */
SEXP zgo_c_info_kernel(SEXP chunks, SEXP schema, SEXP chunk, SEXP row) {
  R_xlen_t n = Rf_xlength(chunk);
  const char *names[] = {"xmin", "ymin", "xmax", "ymax", "zmin",     "zmax",  "mmin",
                         "mmax", "type", "dims", "n_coords", "any_z", "any_m", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  for (int k = 0; k < 8; k++) SET_VECTOR_ELT(out, k, Rf_allocVector(REALSXP, n));
  for (int k = 8; k < 11; k++) SET_VECTOR_ELT(out, k, Rf_allocVector(INTSXP, n));

  zgo_info_state state;
  memset(&state, 0, sizeof(state));
  state.xmin = REAL(VECTOR_ELT(out, 0));
  state.ymin = REAL(VECTOR_ELT(out, 1));
  state.xmax = REAL(VECTOR_ELT(out, 2));
  state.ymax = REAL(VECTOR_ELT(out, 3));
  state.zmin = REAL(VECTOR_ELT(out, 4));
  state.zmax = REAL(VECTOR_ELT(out, 5));
  state.mmin = REAL(VECTOR_ELT(out, 6));
  state.mmax = REAL(VECTOR_ELT(out, 7));
  state.type = INTEGER(VECTOR_ELT(out, 8));
  state.dims = INTEGER(VECTOR_ELT(out, 9));
  state.n_coords = INTEGER(VECTOR_ELT(out, 10));

  SEXP scratch = PROTECT(zgo_scratch_new());
  zgo_column col;
  zgo_readers readers;
  char message[512];
  if (zgo_column_init(scratch, chunks, schema, &col, message, sizeof(message))) {
    zgo_scratch_run(scratch);
    UNPROTECT(2); return zgo_failure("layout", message);
  }
  if (zgo_readers_init(scratch, &readers)) {
    zgo_scratch_run(scratch);
    Rf_error("Could not start the geometry readers.");
  }
  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  vis.feat_start = &zgo_info_feat_start;
  vis.null_feat = &zgo_info_null;
  vis.geom_start = &zgo_info_geom_start;
  vis.geom_end = &zgo_info_geom_end;
  vis.coords = &zgo_info_coords;
  vis.feat_end = &zgo_info_feat_end;
  vis.private_data = &state;
  vis.error = &error;
  for (R_xlen_t p = 0; p < n; p++) {
    int64_t r = 0;
    int k = zgo_position(chunk, row, p, col.n_chunks, &r);
    if (zgo_visit_feature(&col, k, r, &readers, &vis) != GEOARROW_OK || state.row != p + 1) {
      snprintf(message, sizeof(message), "Could not read geometry %ld: %.400s",
               (long)(p + 1), error.message);
      zgo_scratch_run(scratch);
      UNPROTECT(2); return zgo_failure("layout", message);
    }
  }
  zgo_scratch_run(scratch);
  SET_VECTOR_ELT(out, 11, Rf_ScalarLogical(state.any_z));
  SET_VECTOR_ELT(out, 12, Rf_ScalarLogical(state.any_m));
  UNPROTECT(2);
  return out;
}

/* ---- Hilbert keys, as flatbush computes them ------------------------- */

/* The Hilbert index of (x, y) on a 2^16 grid: flatbush v4.7.0's hilbert()
   (index.js, ISC), itself the "Fast Hilbert curve algorithm" by
   rawrunprotected (public domain), line for line. flatbush shifts the
   result by -2^31 to keep JavaScript integers small; the unsigned value
   kept here sorts in the same order. */
uint32_t zgo_hilbert_key(uint32_t x, uint32_t y) {
  uint32_t a = x ^ y;
  uint32_t b = 0xFFFF ^ a;
  uint32_t c = 0xFFFF ^ (x | y);
  uint32_t d = x & (y ^ 0xFFFF);

  uint32_t A = a | (b >> 1);
  uint32_t B = (a >> 1) ^ a;
  uint32_t C = c ^ ((c >> 1) ^ (b & (d >> 1)));
  uint32_t D = d ^ ((a & (c >> 1)) ^ (d >> 1));

  a = (A & (A >> 2)) ^ (B & (B >> 2));
  b = (A & (B >> 2)) ^ (B & ((A ^ B) >> 2));
  c = C ^ ((A & (C >> 2)) ^ (B & (D >> 2)));
  d = D ^ ((B & (C >> 2)) ^ ((A ^ B) & (D >> 2)));

  A = (a & (a >> 4)) ^ (b & (b >> 4));
  B = (a & (b >> 4)) ^ (b & ((a ^ b) >> 4));
  C = c ^ ((a & (c >> 4)) ^ (b & (d >> 4)));
  D = d ^ ((b & (c >> 4)) ^ ((a ^ b) & (d >> 4)));

  c = C ^ ((A & (C >> 8)) ^ (B & (D >> 8)));
  d = D ^ ((B & (C >> 8)) ^ ((A ^ B) & (D >> 8)));

  c ^= c >> 1;
  d ^= d >> 1;
  a = x ^ y;
  b = d | (0xFFFF ^ (a | c));

  a = (a | (a << 8)) & 0x00FF00FF;
  a = (a | (a << 4)) & 0x0F0F0F0F;
  a = (a | (a << 2)) & 0x33333333;
  a = (a | (a << 1)) & 0x55555555;

  b = (b | (b << 8)) & 0x00FF00FF;
  b = (b | (b << 4)) & 0x0F0F0F0F;
  b = (b | (b << 2)) & 0x33333333;
  b = (b | (b << 1)) & 0x55555555;

  return (b << 1) | a;
}

/* Hilbert keys of box centres (cx, cy) over the extent (minx, miny,
   width, height), with flatbush's finish() arithmetic exactly: the size is
   the range or 1 when the range is 0, sx = 65535 / size, and the grid
   position is (sx * (centre - min)) truncated, as JavaScript's `| 0` does.
   NA where a centre is not finite. */
SEXP zgo_c_hilbert(SEXP cx, SEXP cy, SEXP extent) {
  R_xlen_t n = Rf_xlength(cx);
  const double *x = REAL(cx), *y = REAL(cy), *e = REAL(extent);
  double minx = e[0], miny = e[1];
  double width = e[2] != 0 ? e[2] : 1, height = e[3] != 0 ? e[3] : 1;
  const double sx = 65535.0 / width, sy = 65535.0 / height;
  SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
  double *o = REAL(out);
  for (R_xlen_t i = 0; i < n; i++) {
    if (!R_FINITE(x[i]) || !R_FINITE(y[i])) {
      o[i] = NA_REAL;
      continue;
    }
    double hx = trunc(sx * (x[i] - minx));
    double hy = trunc(sy * (y[i] - miny));
    /* Centres outside a given extent are clamped onto its edge. */
    hx = hx < 0 ? 0 : (hx > 65535 ? 65535 : hx);
    hy = hy < 0 ? 0 : (hy > 65535 ? 65535 : hy);
    o[i] = (double)zgo_hilbert_key((uint32_t)hx, (uint32_t)hy);
  }
  UNPROTECT(1);
  return out;
}

/* ---- Validation findings ------------------------------------------------ */

typedef struct {
  struct ArrowBuffer row, code, part, ring;
  int32_t feature;
  int depth, part_id, ring_id, in_ring, ring_n;
  int type_at[ZGO_KERNEL_DEPTH];
  int dims_at[ZGO_KERNEL_DEPTH];
  int top_dims;
  double first[4], last[4], area2;
  int ring_dims;
} zgo_valid_state;

enum {
  ZGO_FIND_UNCLOSED = 1,
  ZGO_FIND_SHORT_RING = 2,
  ZGO_FIND_NON_FINITE = 3,
  ZGO_FIND_MIXED_DIMS = 4,
  ZGO_FIND_EXTERIOR_CW = 5,
  ZGO_FIND_INTERIOR_CCW = 6,
  ZGO_FIND_SHORT_LINE = 7
};

static int zgo_find(zgo_valid_state *s, int code) {
  int32_t ring = s->in_ring ? s->ring_id : NA_INTEGER;
  if (ArrowBufferAppendInt32(&s->row, s->feature) ||
      ArrowBufferAppendInt32(&s->code, code) || ArrowBufferAppendInt32(&s->part, s->part_id) ||
      ArrowBufferAppendInt32(&s->ring, ring)) {
    return ENOMEM;
  }
  return GEOARROW_OK;
}

static void zgo_valid_reset(void *p) {
  zgo_valid_state *s = (zgo_valid_state *)p;
  ArrowBufferReset(&s->row);
  ArrowBufferReset(&s->code);
  ArrowBufferReset(&s->part);
  ArrowBufferReset(&s->ring);
}

static int zgo_valid_feat_start(struct GeoArrowVisitor *v) {
  zgo_valid_state *s = (zgo_valid_state *)v->private_data;
  s->feature++;
  s->depth = 0;
  s->part_id = 0;
  s->ring_id = 0;
  s->in_ring = 0;
  s->top_dims = 0;
  return GEOARROW_OK;
}

static int zgo_valid_geom_start(struct GeoArrowVisitor *v, enum GeoArrowGeometryType type,
                                enum GeoArrowDimensions dims) {
  zgo_valid_state *s = (zgo_valid_state *)v->private_data;
  if (s->depth == 0) {
    s->top_dims = (int)dims;
    if (type >= 1 && type <= 3) s->part_id = 1;
  } else if ((int)dims != s->top_dims) {
    int status = zgo_find(s, ZGO_FIND_MIXED_DIMS);
    if (status) return status;
  }
  if (s->depth == 1) s->part_id++;
  s->ring_id = 0;
  if (s->depth < ZGO_KERNEL_DEPTH) {
    s->type_at[s->depth] = (int)type;
    s->dims_at[s->depth] = (int)dims;
  }
  s->depth++;
  return GEOARROW_OK;
}

static int zgo_valid_ring_start(struct GeoArrowVisitor *v) {
  zgo_valid_state *s = (zgo_valid_state *)v->private_data;
  s->ring_id++;
  s->in_ring = 1;
  s->ring_n = 0;
  s->area2 = 0;
  return GEOARROW_OK;
}

static int zgo_valid_coords(struct GeoArrowVisitor *v, const struct GeoArrowCoordView *c) {
  zgo_valid_state *s = (zgo_valid_state *)v->private_data;
  int d = s->depth - 1;
  if (d < 0) return EINVAL;
  if (d >= ZGO_KERNEL_DEPTH) d = ZGO_KERNEL_DEPTH - 1;
  int type = s->type_at[d];
  int reported = 0;
  for (int64_t k = 0; k < c->n_coords; k++) {
    double x = c->values[0][k * c->coords_stride];
    double y = c->values[1][k * c->coords_stride];
    int empty_point = type == 1 && isnan(x) && isnan(y);
    if (!empty_point && !reported) {
      for (int j = 0; j < c->n_values; j++) {
        if (!R_FINITE(c->values[j][k * c->coords_stride])) {
          int status = zgo_find(s, ZGO_FIND_NON_FINITE);
          if (status) return status;
          reported = 1;
          break;
        }
      }
    }
    if (s->in_ring) {
      if (s->ring_n == 0) {
        s->first[0] = x;
        s->first[1] = y;
        s->ring_dims = c->n_values;
        for (int j = 2; j < c->n_values && j < 4; j++) {
          s->first[j] = c->values[j][k * c->coords_stride];
        }
      } else {
        /* Shoelace sum, twice the signed area. */
        s->area2 += s->last[0] * y - x * s->last[1];
      }
      s->last[0] = x;
      s->last[1] = y;
      for (int j = 2; j < c->n_values && j < 4; j++) {
        s->last[j] = c->values[j][k * c->coords_stride];
      }
      s->ring_n++;
    }
  }
  if (!s->in_ring && type == 2 && c->n_coords == 1) {
    return zgo_find(s, ZGO_FIND_SHORT_LINE);
  }
  return GEOARROW_OK;
}

static int zgo_valid_ring_end(struct GeoArrowVisitor *v) {
  zgo_valid_state *s = (zgo_valid_state *)v->private_data;
  int status = GEOARROW_OK;
  if (s->ring_n > 0) {
    int closed = 1;
    for (int j = 0; j < s->ring_dims && j < 4; j++) {
      if (!(s->first[j] == s->last[j]) && !(isnan(s->first[j]) && isnan(s->last[j]))) {
        closed = 0;
      }
    }
    if (!closed) status = zgo_find(s, ZGO_FIND_UNCLOSED);
    if (!status && s->ring_n < 4) status = zgo_find(s, ZGO_FIND_SHORT_RING);
    if (!status && s->ring_n >= 4 && closed) {
      /* RFC 7946's convention: exterior rings counterclockwise, holes
         clockwise. A finding, not an error: Simple Features fixes none. */
      if (s->ring_id == 1 && s->area2 < 0) {
        status = zgo_find(s, ZGO_FIND_EXTERIOR_CW);
      } else if (s->ring_id > 1 && s->area2 > 0) {
        status = zgo_find(s, ZGO_FIND_INTERIOR_CCW);
      }
    }
  }
  s->in_ring = 0;
  return status;
}

static int zgo_valid_geom_end(struct GeoArrowVisitor *v) {
  ((zgo_valid_state *)v->private_data)->depth--;
  return GEOARROW_OK;
}

/* Findings as list(row, code, part, ring), one entry each. */
SEXP zgo_c_validate(SEXP chunks, SEXP schema, SEXP chunk, SEXP row) {
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
  zgo_valid_state *state =
      (zgo_valid_state *)zgo_scratch_alloc(scratch, sizeof(zgo_valid_state), free);
  ArrowBufferInit(&state->row);
  ArrowBufferInit(&state->code);
  ArrowBufferInit(&state->part);
  ArrowBufferInit(&state->ring);
  zgo_scratch_add(scratch, zgo_valid_reset, state);

  struct GeoArrowError error;
  error.message[0] = '\0';
  struct GeoArrowVisitor vis;
  GeoArrowVisitorInitVoid(&vis);
  vis.feat_start = &zgo_valid_feat_start;
  vis.geom_start = &zgo_valid_geom_start;
  vis.ring_start = &zgo_valid_ring_start;
  vis.coords = &zgo_valid_coords;
  vis.ring_end = &zgo_valid_ring_end;
  vis.geom_end = &zgo_valid_geom_end;
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
  const char *names[] = {"row", "code", "part", "ring", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  struct ArrowBuffer *bufs[] = {&state->row, &state->code, &state->part, &state->ring};
  for (int b = 0; b < 4; b++) {
    R_xlen_t m = (R_xlen_t)(bufs[b]->size_bytes / (int64_t)sizeof(int32_t));
    SEXP col_out = PROTECT(Rf_allocVector(INTSXP, m));
    if (m > 0) memcpy(INTEGER(col_out), bufs[b]->data, (size_t)bufs[b]->size_bytes);
    SET_VECTOR_ELT(out, b, col_out);
    UNPROTECT(1);
  }
  zgo_scratch_run(scratch);
  UNPROTECT(2);
  return out;
}

/* ---- geoarrow-c's own box kernel, as an oracle ------------------------- */

static void zgo_release_kernel(void *p) {
  struct GeoArrowKernel *k = (struct GeoArrowKernel *)p;
  if (k->release != NULL) k->release(k);
  free(p);
}

static void zgo_release_schema(void *p) {
  struct ArrowSchema *s = (struct ArrowSchema *)p;
  if (s->release != NULL) s->release(s);
  free(p);
}

static void zgo_release_array(void *p) {
  struct ArrowArray *a = (struct ArrowArray *)p;
  if (a->release != NULL) a->release(a);
  free(p);
}

/* geoarrow-c's "box" kernel over one array: its output columns by name, for
   tests that compare geo_box() with it (design Stage 5). Only for layouts
   geoarrow-c reads (D20); an error otherwise. */
SEXP zgo_c_geoarrow_box(SEXP array_xptr, SEXP schema_xptr) {
  const struct ArrowArray *array = zgo_array_from_xptr(array_xptr);
  const struct ArrowSchema *schema = zgo_schema_from_xptr(schema_xptr);
  SEXP scratch = PROTECT(zgo_scratch_new());
  struct GeoArrowKernel *kernel =
      (struct GeoArrowKernel *)zgo_scratch_alloc(scratch, sizeof(*kernel), zgo_release_kernel);
  struct ArrowSchema *in_schema =
      (struct ArrowSchema *)zgo_scratch_alloc(scratch, sizeof(*in_schema), zgo_release_schema);
  struct ArrowSchema *out_schema =
      (struct ArrowSchema *)zgo_scratch_alloc(scratch, sizeof(*out_schema), zgo_release_schema);
  struct ArrowArray *out =
      (struct ArrowArray *)zgo_scratch_alloc(scratch, sizeof(*out), zgo_release_array);
  struct GeoArrowError error;
  error.message[0] = '\0';
  char message[512];
  int status = ArrowSchemaDeepCopy(schema, in_schema);
  if (status == NANOARROW_OK) status = GeoArrowKernelInit(kernel, "box", NULL);
  if (status == NANOARROW_OK) {
    status = kernel->start(kernel, in_schema, "", out_schema, &error);
  }
  /* push_batch reads the array and does not take it. */
  if (status == NANOARROW_OK) {
    status = kernel->push_batch(kernel, (struct ArrowArray *)array, out, &error);
  }
  if (status != NANOARROW_OK) {
    snprintf(message, sizeof(message), "geoarrow-c's box kernel failed: %.400s",
             error.message);
    zgo_scratch_run(scratch);
    UNPROTECT(1); return zgo_failure("layout", message);
  }
  SEXP result = PROTECT(Rf_allocVector(VECSXP, out->n_children));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, out->n_children));
  for (int64_t c = 0; c < out->n_children; c++) {
    const struct ArrowArray *child = out->children[c];
    SEXP values = PROTECT(Rf_allocVector(REALSXP, child->length));
    const double *data = (const double *)child->buffers[1];
    for (int64_t i = 0; i < child->length; i++) REAL(values)[i] = data[child->offset + i];
    SET_VECTOR_ELT(result, c, values);
    SET_STRING_ELT(names, c, Rf_mkChar(out_schema->children[c]->name));
    UNPROTECT(1);
  }
  Rf_setAttrib(result, R_NamesSymbol, names);
  zgo_scratch_run(scratch);
  UNPROTECT(3);
  return result;
}
