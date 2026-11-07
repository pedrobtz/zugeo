/* Packed spatial indexes (design section 6.8, D13): a static R-tree in
   flatbush v4.7.0's serialised format and a static k-d tree in kdbush
   v4.1.0's, written from their index.js (ISC) so the same bytes load in
   flatbush, kdbush and geo-index. Builds follow the JavaScript step for
   step, sorts included, because the bytes depend on them.

   An index lives in an R raw vector. Bytes from outside (geo_index_from_raw())
   are checked once by zgo_index_view(), and every offset read from them
   during a query is checked again, so hostile bytes give an error, never a
   read out of bounds. */

#include "zgo.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define ZGO_FLATBUSH_MAGIC 0xfb
#define ZGO_FLATBUSH_VERSION 3
#define ZGO_KDBUSH_MAGIC 0xdb
#define ZGO_KDBUSH_VERSION 1
#define ZGO_FLOAT64 8 /* index of Float64Array in both ARRAY_TYPES */

static int zgo_little_endian(void) {
  uint16_t one = 1;
  return *(uint8_t *)&one == 1;
}

static void zgo_require_little_endian(void) {
  if (!zgo_little_endian()) {
    Rf_error("Packed indexes are little-endian, as flatbush writes them; this platform is not.");
  }
}

static uint16_t zgo_get_u16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t zgo_get_u32(const uint8_t *p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* ---- The R-tree: layout ------------------------------------------------ */

typedef struct {
  uint32_t n_items;
  uint32_t node_size;
  int64_t n_nodes;
  int n_levels;
  int64_t level_bounds[64]; /* in units of box values (4 per node) */
  int index_u32;            /* Uint32Array indices; else Uint16Array */
  double *boxes;            /* n_nodes * 4 */
  uint8_t *indices;
  int64_t byte_size;
} zgo_rtree;

/* The constructor's arithmetic: level bounds, node count, sizes. */
static int zgo_rtree_layout(zgo_rtree *t, uint32_t n_items, uint32_t node_size) {
  t->n_items = n_items;
  t->node_size = node_size;
  int64_t n = n_items, num_nodes = n_items;
  t->n_levels = 0;
  t->level_bounds[t->n_levels++] = n * 4;
  do {
    n = (n + node_size - 1) / node_size;
    num_nodes += n;
    if (t->n_levels >= 64) return 1;
    t->level_bounds[t->n_levels++] = num_nodes * 4;
  } while (n != 1);
  t->n_nodes = num_nodes;
  t->index_u32 = num_nodes >= 16384;
  t->byte_size = 8 + num_nodes * 4 * 8 + num_nodes * (t->index_u32 ? 4 : 2);
  return 0;
}

static uint32_t zgo_rtree_index(const zgo_rtree *t, int64_t i) {
  if (t->index_u32) {
    uint32_t v;
    memcpy(&v, t->indices + i * 4, 4);
    return v;
  }
  uint16_t v;
  memcpy(&v, t->indices + i * 2, 2);
  return v;
}

static void zgo_rtree_set_index(zgo_rtree *t, int64_t i, uint32_t value) {
  if (t->index_u32) {
    memcpy(t->indices + i * 4, &value, 4);
  } else {
    uint16_t v = (uint16_t)value;
    memcpy(t->indices + i * 2, &v, 2);
  }
}

/* ---- The R-tree: building -------------------------------------------- */

static void zgo_rtree_swap(uint32_t *values, zgo_rtree *t, int64_t i, int64_t j) {
  uint32_t tmp = values[i];
  values[i] = values[j];
  values[j] = tmp;
  double b[4];
  memcpy(b, t->boxes + 4 * i, sizeof(b));
  memcpy(t->boxes + 4 * i, t->boxes + 4 * j, sizeof(b));
  memcpy(t->boxes + 4 * j, b, sizeof(b));
  uint32_t e = zgo_rtree_index(t, i);
  zgo_rtree_set_index(t, i, zgo_rtree_index(t, j));
  zgo_rtree_set_index(t, j, e);
}

/* flatbush's sort(): quicksort by Hilbert value that stops once a range
   lies within one node, with its pivot and stack order, so the item order
   (and the bytes) match flatbush's. The keys are unsigned here and signed
   (shifted by -2^31) in flatbush, which orders them the same. */
static int zgo_rtree_sort(uint32_t *values, zgo_rtree *t, int64_t left, int64_t right) {
  int64_t cap = 256, sp = 0;
  int64_t *stack = (int64_t *)malloc(sizeof(int64_t) * (size_t)cap);
  if (stack == NULL) return 1;
  int64_t node = t->node_size;
  stack[sp++] = left;
  stack[sp++] = right;
  while (sp > 0) {
    int64_t r = stack[--sp];
    int64_t l = stack[--sp];
    if (r - l <= node && l / node >= r / node) continue;
    uint32_t a = values[l], b = values[(l + r) >> 1], c = values[r];
    uint32_t pivot = ((a > b) != (a > c)) ? a : ((b < a) != (b < c)) ? b : c;
    int64_t i = l - 1, j = r + 1;
    for (;;) {
      do i++; while (values[i] < pivot);
      do j--; while (values[j] > pivot);
      if (i >= j) break;
      zgo_rtree_swap(values, t, i, j);
    }
    if (sp + 4 > cap) {
      cap *= 2;
      int64_t *grown = (int64_t *)realloc(stack, sizeof(int64_t) * (size_t)cap);
      if (grown == NULL) {
        free(stack);
        return 1;
      }
      stack = grown;
    }
    stack[sp++] = l;
    stack[sp++] = j;
    stack[sp++] = j + 1;
    stack[sp++] = r;
  }
  free(stack);
  return 0;
}

uint32_t zgo_hilbert_key(uint32_t x, uint32_t y); /* zgo_kernel.c */

/* Boxes in, flatbush bytes out: add() for each box, then finish(). */
SEXP zgo_c_rtree_build(SEXP xmin, SEXP ymin, SEXP xmax, SEXP ymax, SEXP node_size_sexp) {
  zgo_require_little_endian();
  R_xlen_t n = Rf_xlength(xmin);
  if (n < 1 || n > (R_xlen_t)UINT32_MAX) Rf_error("An R-tree needs 1 to 2^32 - 1 boxes.");
  uint32_t node_size = (uint32_t)Rf_asInteger(node_size_sexp);
  zgo_rtree t;
  if (zgo_rtree_layout(&t, (uint32_t)n, node_size)) Rf_error("Too many tree levels.");
  SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)t.byte_size));
  uint8_t *data = RAW(out);
  memset(data, 0, (size_t)t.byte_size);
  t.boxes = (double *)(data + 8);
  t.indices = data + 8 + t.n_nodes * 4 * 8;
  data[0] = ZGO_FLATBUSH_MAGIC;
  data[1] = (ZGO_FLATBUSH_VERSION << 4) + ZGO_FLOAT64;
  uint16_t ns = (uint16_t)node_size;
  memcpy(data + 2, &ns, 2);
  uint32_t ni = (uint32_t)n;
  memcpy(data + 4, &ni, 4);

  const double *x0 = REAL(xmin), *y0 = REAL(ymin), *x1 = REAL(xmax), *y1 = REAL(ymax);
  double minX = R_PosInf, minY = R_PosInf, maxX = R_NegInf, maxY = R_NegInf;
  for (R_xlen_t i = 0; i < n; i++) {
    zgo_rtree_set_index(&t, i, (uint32_t)i);
    t.boxes[4 * i] = x0[i];
    t.boxes[4 * i + 1] = y0[i];
    t.boxes[4 * i + 2] = x1[i];
    t.boxes[4 * i + 3] = y1[i];
    if (x0[i] < minX) minX = x0[i];
    if (y0[i] < minY) minY = y0[i];
    if (x1[i] > maxX) maxX = x1[i];
    if (y1[i] > maxY) maxY = y1[i];
  }
  int64_t pos = (int64_t)n * 4;
  if ((uint32_t)n <= node_size) {
    t.boxes[pos++] = minX;
    t.boxes[pos++] = minY;
    t.boxes[pos++] = maxX;
    t.boxes[pos++] = maxY;
    UNPROTECT(1);
    return out;
  }

  double width = (maxX - minX) != 0 ? (maxX - minX) : 1;
  double height = (maxY - minY) != 0 ? (maxY - minY) : 1;
  double sx = 65535.0 / width, sy = 65535.0 / height;
  uint32_t *values = (uint32_t *)R_alloc((size_t)n, sizeof(uint32_t));
  for (R_xlen_t i = 0; i < n; i++) {
    double cx = (t.boxes[4 * i] + t.boxes[4 * i + 2]) / 2;
    double cy = (t.boxes[4 * i + 1] + t.boxes[4 * i + 3]) / 2;
    /* JavaScript's `| 0`: truncation toward zero, then to int32. */
    int32_t hx = (int32_t)trunc(sx * (cx - minX));
    int32_t hy = (int32_t)trunc(sy * (cy - minY));
    values[i] = zgo_hilbert_key((uint32_t)hx, (uint32_t)hy);
  }
  if (zgo_rtree_sort(values, &t, 0, (int64_t)n - 1)) Rf_error("Could not allocate the sort stack.");

  int64_t readPos = 0;
  for (int lv = 0; lv < t.n_levels - 1; lv++) {
    int64_t end = t.level_bounds[lv];
    int64_t rp = readPos;
    while (rp < end) {
      int64_t nodeIndex = rp;
      double nx0 = t.boxes[rp++], ny0 = t.boxes[rp++], nx1 = t.boxes[rp++],
             ny1 = t.boxes[rp++];
      for (uint32_t j = 1; j < node_size && rp < end; j++) {
        nx0 = fmin(nx0, t.boxes[rp++]);
        ny0 = fmin(ny0, t.boxes[rp++]);
        nx1 = fmax(nx1, t.boxes[rp++]);
        ny1 = fmax(ny1, t.boxes[rp++]);
      }
      zgo_rtree_set_index(&t, pos >> 2, (uint32_t)nodeIndex);
      t.boxes[pos++] = nx0;
      t.boxes[pos++] = ny0;
      t.boxes[pos++] = nx1;
      t.boxes[pos++] = ny1;
    }
    readPos = rp;
  }
  UNPROTECT(1);
  return out;
}

/* ---- Reading an index's bytes ------------------------------------------- */

/* Checks a raw vector holds a whole flatbush or kdbush index; fills `t`
   for an R-tree. Returns "rtree", "kdtree", or NULL with `message`. */
static const char *zgo_index_view(SEXP raw, zgo_rtree *t, uint32_t *kd_items,
                                  uint32_t *kd_node, char *message, size_t n) {
  if (TYPEOF(raw) != RAWSXP) {
    snprintf(message, n, "An index is a raw vector.");
    return NULL;
  }
  const uint8_t *data = RAW(raw);
  int64_t size = Rf_xlength(raw);
  if (size < 8) {
    snprintf(message, n, "The index is %ld bytes; the header alone is 8.", (long)size);
    return NULL;
  }
  int version = data[1] >> 4, type = data[1] & 0x0f;
  uint32_t node_size = zgo_get_u16(data + 2), n_items = zgo_get_u32(data + 4);
  if (data[0] == ZGO_FLATBUSH_MAGIC) {
    if (version != ZGO_FLATBUSH_VERSION || type != ZGO_FLOAT64) {
      snprintf(message, n, "A flatbush index of version %d and array type %d; zugeo reads version 3 of Float64.", version, type);
      return NULL;
    }
    if (n_items == 0 || node_size < 2) {
      snprintf(message, n, "A flatbush header with %u items and node size %u.", n_items, node_size);
      return NULL;
    }
    if (zgo_rtree_layout(t, n_items, node_size) || t->byte_size != size) {
      snprintf(message, n, "The flatbush header says %u items of node size %u, which is not %ld bytes.", n_items, node_size, (long)size);
      return NULL;
    }
    t->boxes = (double *)(data + 8);
    t->indices = (uint8_t *)data + 8 + t->n_nodes * 4 * 8;
    return "rtree";
  }
  if (data[0] == ZGO_KDBUSH_MAGIC) {
    if (version != ZGO_KDBUSH_VERSION || type != ZGO_FLOAT64) {
      snprintf(message, n, "A kdbush index of version %d and array type %d; zugeo reads version 1 of Float64.", version, type);
      return NULL;
    }
    int64_t ids = (int64_t)n_items * (n_items < 65536 ? 2 : 4);
    int64_t pad = (8 - ids % 8) % 8;
    if (node_size < 2 || 8 + ids + pad + (int64_t)n_items * 16 != size) {
      snprintf(message, n, "The kdbush header says %u items of node size %u, which is not %ld bytes.", n_items, node_size, (long)size);
      return NULL;
    }
    *kd_items = n_items;
    *kd_node = node_size;
    return "kdtree";
  }
  snprintf(message, n, "The bytes are neither a flatbush nor a kdbush index.");
  return NULL;
}

static SEXP zgo_index_failure(const char *message) {
  const char *names[] = {"kind", "message", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString("index"));
  SET_VECTOR_ELT(out, 1, Rf_mkString(message));
  Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("zgo_failure"));
  UNPROTECT(1);
  return out;
}

/* list(type, node_size, n_items) for valid bytes, a failure otherwise. */
SEXP zgo_c_index_info(SEXP raw) {
  zgo_rtree t;
  uint32_t kd_items = 0, kd_node = 0;
  char message[256];
  const char *type = zgo_index_view(raw, &t, &kd_items, &kd_node, message, sizeof(message));
  if (type == NULL) return zgo_index_failure(message);
  const char *names[] = {"type", "node_size", "n_items", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString(type));
  int is_r = strcmp(type, "rtree") == 0;
  SET_VECTOR_ELT(out, 1, Rf_ScalarInteger((int)(is_r ? t.node_size : kd_node)));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)(is_r ? t.n_items : kd_items)));
  UNPROTECT(1);
  return out;
}

/* ---- R-tree queries ------------------------------------------------------ */

/* The level of the node block starting at box offset `pos`. */
static int zgo_rtree_level(const zgo_rtree *t, int64_t pos) {
  for (int lv = 0; lv < t->n_levels; lv++) {
    if (pos < t->level_bounds[lv]) return lv;
  }
  return -1;
}

typedef struct {
  int *a, *b;
  R_xlen_t n, cap;
} zgo_pairs;

static int zgo_pairs_push(zgo_pairs *p, int a, int b) {
  if (p->n == p->cap) {
    R_xlen_t cap = p->cap ? p->cap * 2 : 1024;
    int *na = (int *)realloc(p->a, sizeof(int) * (size_t)cap);
    if (na == NULL) return 1;
    p->a = na;
    int *nb = (int *)realloc(p->b, sizeof(int) * (size_t)cap);
    if (nb == NULL) return 1;
    p->b = nb;
    p->cap = cap;
  }
  p->a[p->n] = a;
  p->b[p->n] = b;
  p->n++;
  return 0;
}

/* flatbush's search() for one query box, appending (query, item) pairs.
   Returns a message for corrupt bytes, NULL otherwise. */
static const char *zgo_rtree_search_one(const zgo_rtree *t, double minX, double minY,
                                        double maxX, double maxY, int query,
                                        zgo_pairs *out) {
  int64_t numItems4 = (int64_t)t->n_items * 4;
  int64_t total = t->n_nodes * 4;
  int64_t stack_cap = 64, sp = 0;
  int64_t *stack = (int64_t *)malloc(sizeof(int64_t) * (size_t)stack_cap);
  if (stack == NULL) return "Could not allocate the search stack.";
  int64_t nodeIndex = total - 4;
  int level = t->n_levels - 1;
  for (;;) {
    int64_t end = nodeIndex + (int64_t)t->node_size * 4;
    if (end > t->level_bounds[level]) end = t->level_bounds[level];
    int isNode = nodeIndex >= numItems4;
    for (int64_t pos = nodeIndex; pos < end; pos += 4) {
      const double *b = t->boxes + pos;
      if (maxX < b[0] || maxY < b[1] || minX > b[2] || minY > b[3]) continue;
      uint32_t index = zgo_rtree_index(t, pos >> 2);
      if (isNode) {
        /* A child block offset: it must start a block one level down. */
        if ((int64_t)index >= total || index % 4 != 0 ||
            zgo_rtree_level(t, (int64_t)index) != level - 1) {
          free(stack);
          return "The index's node offsets are corrupt.";
        }
        if (sp + 2 > stack_cap) {
          stack_cap *= 2;
          int64_t *grown = (int64_t *)realloc(stack, sizeof(int64_t) * (size_t)stack_cap);
          if (grown == NULL) {
            free(stack);
            return "Could not grow the search stack.";
          }
          stack = grown;
        }
        stack[sp++] = index;
        stack[sp++] = level - 1;
      } else {
        if (index >= t->n_items) {
          free(stack);
          return "The index's item numbers are corrupt.";
        }
        if (zgo_pairs_push(out, query, (int)index)) {
          free(stack);
          return "Could not allocate the results.";
        }
      }
    }
    if (sp == 0) break;
    level = (int)stack[--sp];
    nodeIndex = stack[--sp];
  }
  free(stack);
  return NULL;
}

static SEXP zgo_pairs_result(zgo_pairs *p) {
  const char *names[] = {"query", "item", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SEXP a = PROTECT(Rf_allocVector(INTSXP, p->n));
  SEXP b = PROTECT(Rf_allocVector(INTSXP, p->n));
  for (R_xlen_t i = 0; i < p->n; i++) {
    INTEGER(a)[i] = p->a[i] + 1;
    INTEGER(b)[i] = p->b[i] + 1;
  }
  SET_VECTOR_ELT(out, 0, a);
  SET_VECTOR_ELT(out, 1, b);
  UNPROTECT(3);
  return out;
}

static void zgo_pairs_free(zgo_pairs *p) {
  free(p->a);
  free(p->b);
  p->a = p->b = NULL;
}

/* Every query box against the R-tree: list(query, item), both 1-based.
   Query boxes with NA or NaN bounds match nothing. */
SEXP zgo_c_rtree_search(SEXP raw, SEXP qminx, SEXP qminy, SEXP qmaxx, SEXP qmaxy) {
  zgo_rtree t;
  uint32_t ki, kn;
  char message[256];
  const char *type = zgo_index_view(raw, &t, &ki, &kn, message, sizeof(message));
  if (type == NULL || strcmp(type, "rtree") != 0) {
    return zgo_index_failure(type == NULL ? message : "Not an R-tree.");
  }
  R_xlen_t n = Rf_xlength(qminx);
  const double *a = REAL(qminx), *b = REAL(qminy), *c = REAL(qmaxx), *d = REAL(qmaxy);
  zgo_pairs pairs = {NULL, NULL, 0, 0};
  for (R_xlen_t q = 0; q < n; q++) {
    if (ISNAN(a[q]) || ISNAN(b[q]) || ISNAN(c[q]) || ISNAN(d[q])) continue;
    const char *m = zgo_rtree_search_one(&t, a[q], b[q], c[q], d[q], (int)q, &pairs);
    if (m != NULL) {
      zgo_pairs_free(&pairs);
      return zgo_index_failure(m);
    }
  }
  SEXP out = zgo_pairs_result(&pairs);
  zgo_pairs_free(&pairs);
  return out;
}

/* Both R-trees descended together, pruning every pair of nodes whose boxes
   are disjoint (GeometryOps.jl's dual_depth_first_search): list(a, b) of
   intersecting item pairs, 1-based. A stack frame is a block of entries on
   each side, [start, end) at a level, 0 being the items; an item paired
   with a node is carried down as a block of itself. */
SEXP zgo_c_rtree_join(SEXP raw_a, SEXP raw_b) {
  zgo_rtree ta, tb;
  uint32_t ki, kn;
  char message[256];
  const char *type = zgo_index_view(raw_a, &ta, &ki, &kn, message, sizeof(message));
  if (type == NULL || strcmp(type, "rtree") != 0) {
    return zgo_index_failure(type == NULL ? message : "Not an R-tree.");
  }
  type = zgo_index_view(raw_b, &tb, &ki, &kn, message, sizeof(message));
  if (type == NULL || strcmp(type, "rtree") != 0) {
    return zgo_index_failure(type == NULL ? message : "Not an R-tree.");
  }
  zgo_pairs pairs = {NULL, NULL, 0, 0};
  int64_t cap = 6 * 256, sp = 0;
  int64_t *stack = (int64_t *)malloc(sizeof(int64_t) * (size_t)cap);
  if (stack == NULL) return zgo_index_failure("Could not allocate the join stack.");
  int64_t total_a = ta.n_nodes * 4, total_b = tb.n_nodes * 4;
  stack[sp++] = total_a - 4;
  stack[sp++] = total_a;
  stack[sp++] = ta.n_levels - 1;
  stack[sp++] = total_b - 4;
  stack[sp++] = total_b;
  stack[sp++] = tb.n_levels - 1;
  const char *failure = NULL;
  while (sp > 0 && failure == NULL) {
    int lb = (int)stack[--sp];
    int64_t eb = stack[--sp], sb = stack[--sp];
    int la = (int)stack[--sp];
    int64_t ea = stack[--sp], sa = stack[--sp];
    for (int64_t pa = sa; pa < ea && failure == NULL; pa += 4) {
      const double *ba = ta.boxes + pa;
      for (int64_t pb = sb; pb < eb && failure == NULL; pb += 4) {
        const double *bb = tb.boxes + pb;
        if (ba[2] < bb[0] || bb[2] < ba[0] || ba[3] < bb[1] || bb[3] < ba[1]) continue;
        uint32_t ia = zgo_rtree_index(&ta, pa >> 2), ib = zgo_rtree_index(&tb, pb >> 2);
        if (la == 0 && lb == 0) {
          if (ia >= ta.n_items || ib >= tb.n_items) {
            failure = "The index's item numbers are corrupt.";
          } else if (zgo_pairs_push(&pairs, (int)ia, (int)ib)) {
            failure = "Could not allocate the results.";
          }
          continue;
        }
        /* Descend each side that is a node; an item stays as itself. */
        int64_t csa = pa, cea = pa + 4, csb = pb, ceb = pb + 4;
        int cla = 0, clb = 0;
        if (la > 0) {
          if ((int64_t)ia >= total_a || ia % 4 != 0 || zgo_rtree_level(&ta, ia) != la - 1) {
            failure = "The index's node offsets are corrupt.";
            continue;
          }
          csa = ia;
          cea = ia + (int64_t)ta.node_size * 4;
          if (cea > ta.level_bounds[la - 1]) cea = ta.level_bounds[la - 1];
          cla = la - 1;
        }
        if (lb > 0) {
          if ((int64_t)ib >= total_b || ib % 4 != 0 || zgo_rtree_level(&tb, ib) != lb - 1) {
            failure = "The index's node offsets are corrupt.";
            continue;
          }
          csb = ib;
          ceb = ib + (int64_t)tb.node_size * 4;
          if (ceb > tb.level_bounds[lb - 1]) ceb = tb.level_bounds[lb - 1];
          clb = lb - 1;
        }
        if (sp + 6 > cap) {
          cap *= 2;
          int64_t *grown = (int64_t *)realloc(stack, sizeof(int64_t) * (size_t)cap);
          if (grown == NULL) {
            failure = "Could not grow the join stack.";
            continue;
          }
          stack = grown;
        }
        stack[sp++] = csa;
        stack[sp++] = cea;
        stack[sp++] = cla;
        stack[sp++] = csb;
        stack[sp++] = ceb;
        stack[sp++] = clb;
      }
    }
  }
  free(stack);
  if (failure != NULL) {
    zgo_pairs_free(&pairs);
    return zgo_index_failure(failure);
  }
  SEXP out = zgo_pairs_result(&pairs);
  zgo_pairs_free(&pairs);
  return out;
}

/* ---- Nearest neighbours by box distance ------------------------------- */

typedef struct {
  int64_t *ids;
  double *dist;
  int64_t n, cap;
} zgo_heap;

static int zgo_heap_push(zgo_heap *h, int64_t id, double d) {
  if (h->n == h->cap) {
    int64_t cap = h->cap ? h->cap * 2 : 256;
    int64_t *ni = (int64_t *)realloc(h->ids, sizeof(int64_t) * (size_t)cap);
    if (ni == NULL) return 1;
    h->ids = ni;
    double *nd = (double *)realloc(h->dist, sizeof(double) * (size_t)cap);
    if (nd == NULL) return 1;
    h->dist = nd;
    h->cap = cap;
  }
  int64_t i = h->n++;
  while (i > 0) {
    int64_t parent = (i - 1) >> 1;
    if (h->dist[parent] <= d) break;
    h->ids[i] = h->ids[parent];
    h->dist[i] = h->dist[parent];
    i = parent;
  }
  h->ids[i] = id;
  h->dist[i] = d;
  return 0;
}

static void zgo_heap_pop(zgo_heap *h) {
  if (--h->n <= 0) return;
  int64_t id = h->ids[h->n];
  double d = h->dist[h->n];
  int64_t i = 0, half = h->n >> 1;
  while (i < half) {
    int64_t best = 2 * i + 1;
    if (best + 1 < h->n && h->dist[best + 1] < h->dist[best]) best++;
    if (h->dist[best] >= d) break;
    h->ids[i] = h->ids[best];
    h->dist[i] = h->dist[best];
    i = best;
  }
  h->ids[i] = id;
  h->dist[i] = d;
}

/* flatbush's neighbors() for each query point: up to k items by box
   distance within max_distance. list(query, item, distance). */
SEXP zgo_c_rtree_nearest(SEXP raw, SEXP px, SEXP py, SEXP k_sexp, SEXP max_sexp) {
  zgo_rtree t;
  uint32_t ki, kn;
  char message[256];
  const char *type = zgo_index_view(raw, &t, &ki, &kn, message, sizeof(message));
  if (type == NULL || strcmp(type, "rtree") != 0) {
    return zgo_index_failure(type == NULL ? message : "Not an R-tree.");
  }
  R_xlen_t n = Rf_xlength(px);
  double k = Rf_asReal(k_sexp), maxd = Rf_asReal(max_sexp);
  double max2 = maxd * maxd;
  const double *x = REAL(px), *y = REAL(py);
  zgo_pairs pairs = {NULL, NULL, 0, 0};
  double *dists = NULL;
  R_xlen_t dist_cap = 0;
  zgo_heap h = {NULL, NULL, 0, 0};
  const char *failure = NULL;
  int64_t numItems4 = (int64_t)t.n_items * 4, total = t.n_nodes * 4;
  for (R_xlen_t q = 0; q < n && failure == NULL; q++) {
    if (ISNAN(x[q]) || ISNAN(y[q])) continue;
    h.n = 0;
    double found = 0;
    if (zgo_heap_push(&h, (total - 4) << 1, 0)) failure = "Could not allocate the queue.";
    while (h.n > 0 && failure == NULL) {
      int64_t top = h.ids[0];
      double topd = h.dist[0];
      zgo_heap_pop(&h);
      if (top & 1) {
        if (pairs.n == dist_cap) {
          dist_cap = dist_cap ? dist_cap * 2 : 1024;
          double *grown = (double *)realloc(dists, sizeof(double) * (size_t)dist_cap);
          if (grown == NULL) {
            failure = "Could not allocate the results.";
            break;
          }
          dists = grown;
        }
        dists[pairs.n] = sqrt(topd);
        if (zgo_pairs_push(&pairs, (int)q, (int)(top >> 1))) failure = "Could not allocate the results.";
        if (++found >= k) break;
        continue;
      }
      int64_t nodeIndex = top >> 1;
      int level = zgo_rtree_level(&t, nodeIndex);
      if (level < 0) {
        failure = "The index's node offsets are corrupt.";
        break;
      }
      int isLeaf = nodeIndex < numItems4;
      int64_t end = nodeIndex + (int64_t)t.node_size * 4;
      if (end > t.level_bounds[level]) end = t.level_bounds[level];
      for (int64_t pos = nodeIndex; pos < end && failure == NULL; pos += 4) {
        const double *b = t.boxes + pos;
        double dx = fmax(fmax(b[0] - x[q], x[q] - b[2]), 0);
        double dy = fmax(fmax(b[1] - y[q], y[q] - b[3]), 0);
        double d = dx * dx + dy * dy;
        if (d > max2) continue;
        uint32_t child = zgo_rtree_index(&t, pos >> 2);
        if (isLeaf) {
          if (child >= t.n_items) {
            failure = "The index's item numbers are corrupt.";
          } else if (zgo_heap_push(&h, ((int64_t)child << 1) | 1, d)) {
            failure = "Could not allocate the queue.";
          }
        } else {
          if ((int64_t)child >= total || zgo_rtree_level(&t, child) != level - 1) {
            failure = "The index's node offsets are corrupt.";
          } else if (zgo_heap_push(&h, (int64_t)child << 1, d)) {
            failure = "Could not allocate the queue.";
          }
        }
      }
    }
  }
  free(h.ids);
  free(h.dist);
  if (failure != NULL) {
    zgo_pairs_free(&pairs);
    free(dists);
    return zgo_index_failure(failure);
  }
  const char *names[] = {"query", "item", "distance", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SEXP qa = PROTECT(Rf_allocVector(INTSXP, pairs.n));
  SEXP ib = PROTECT(Rf_allocVector(INTSXP, pairs.n));
  SEXP dd = PROTECT(Rf_allocVector(REALSXP, pairs.n));
  for (R_xlen_t i = 0; i < pairs.n; i++) {
    INTEGER(qa)[i] = pairs.a[i] + 1;
    INTEGER(ib)[i] = pairs.b[i] + 1;
    REAL(dd)[i] = dists[i];
  }
  SET_VECTOR_ELT(out, 0, qa);
  SET_VECTOR_ELT(out, 1, ib);
  SET_VECTOR_ELT(out, 2, dd);
  zgo_pairs_free(&pairs);
  free(dists);
  UNPROTECT(4);
  return out;
}

/* ---- The k-d tree ------------------------------------------------------ */

typedef struct {
  uint32_t n, node_size;
  int u32;
  uint8_t *ids;
  double *coords;
} zgo_kd;

static uint32_t zgo_kd_id(const zgo_kd *t, int64_t i) {
  if (t->u32) {
    uint32_t v;
    memcpy(&v, t->ids + 4 * i, 4);
    return v;
  }
  uint16_t v;
  memcpy(&v, t->ids + 2 * i, 2);
  return v;
}

static void zgo_kd_swap_item(zgo_kd *t, int64_t i, int64_t j) {
  if (t->u32) {
    uint32_t a, b;
    memcpy(&a, t->ids + 4 * i, 4);
    memcpy(&b, t->ids + 4 * j, 4);
    memcpy(t->ids + 4 * i, &b, 4);
    memcpy(t->ids + 4 * j, &a, 4);
  } else {
    uint16_t a, b;
    memcpy(&a, t->ids + 2 * i, 2);
    memcpy(&b, t->ids + 2 * j, 2);
    memcpy(t->ids + 2 * i, &b, 2);
    memcpy(t->ids + 2 * j, &a, 2);
  }
  double x = t->coords[2 * i], y = t->coords[2 * i + 1];
  t->coords[2 * i] = t->coords[2 * j];
  t->coords[2 * i + 1] = t->coords[2 * j + 1];
  t->coords[2 * j] = x;
  t->coords[2 * j + 1] = y;
}

/* kdbush's select(): Floyd-Rivest selection, with its sampling arithmetic. */
static void zgo_kd_select(zgo_kd *t, int64_t k, int64_t left, int64_t right, int axis) {
  while (right > left) {
    if (right - left > 600) {
      double n = (double)(right - left + 1);
      double m = (double)(k - left + 1);
      double z = log(n);
      double s = 0.5 * exp(2 * z / 3);
      double sd = 0.5 * sqrt(z * s * (n - s) / n) * (m - n / 2 < 0 ? -1 : 1);
      int64_t newLeft = (int64_t)floor((double)k - m * s / n + sd);
      int64_t newRight = (int64_t)floor((double)k + (n - m) * s / n + sd);
      if (newLeft < left) newLeft = left;
      if (newRight > right) newRight = right;
      zgo_kd_select(t, k, newLeft, newRight, axis);
    }
    double v = t->coords[2 * k + axis];
    int64_t i = left, j = right;
    zgo_kd_swap_item(t, left, k);
    if (t->coords[2 * right + axis] > v) zgo_kd_swap_item(t, left, right);
    while (i < j) {
      zgo_kd_swap_item(t, i, j);
      i++;
      j--;
      while (t->coords[2 * i + axis] < v) i++;
      while (t->coords[2 * j + axis] > v) j--;
    }
    if (t->coords[2 * left + axis] == v) {
      zgo_kd_swap_item(t, left, j);
    } else {
      j++;
      zgo_kd_swap_item(t, j, right);
    }
    if (j <= k) left = j + 1;
    if (k <= j) right = j - 1;
  }
}

static void zgo_kd_sort(zgo_kd *t, int64_t left, int64_t right, int axis) {
  if (right - left <= (int64_t)t->node_size) return;
  int64_t m = (left + right) >> 1;
  zgo_kd_select(t, m, left, right, axis);
  zgo_kd_sort(t, left, m - 1, 1 - axis);
  zgo_kd_sort(t, m + 1, right, 1 - axis);
}

SEXP zgo_c_kdtree_build(SEXP x, SEXP y, SEXP node_size_sexp) {
  zgo_require_little_endian();
  R_xlen_t n = Rf_xlength(x);
  if (n > (R_xlen_t)UINT32_MAX) Rf_error("A k-d tree holds at most 2^32 - 1 points.");
  zgo_kd t;
  t.n = (uint32_t)n;
  t.node_size = (uint32_t)Rf_asInteger(node_size_sexp);
  t.u32 = n >= 65536;
  int64_t ids = (int64_t)n * (t.u32 ? 4 : 2);
  int64_t pad = (8 - ids % 8) % 8;
  int64_t size = 8 + ids + pad + (int64_t)n * 16;
  SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)size));
  uint8_t *data = RAW(out);
  memset(data, 0, (size_t)size);
  data[0] = ZGO_KDBUSH_MAGIC;
  data[1] = (ZGO_KDBUSH_VERSION << 4) + ZGO_FLOAT64;
  uint16_t ns = (uint16_t)t.node_size;
  memcpy(data + 2, &ns, 2);
  memcpy(data + 4, &t.n, 4);
  t.ids = data + 8;
  t.coords = (double *)(data + 8 + ids + pad);
  for (R_xlen_t i = 0; i < n; i++) {
    if (t.u32) {
      uint32_t v = (uint32_t)i;
      memcpy(t.ids + 4 * i, &v, 4);
    } else {
      uint16_t v = (uint16_t)i;
      memcpy(t.ids + 2 * i, &v, 2);
    }
    t.coords[2 * i] = REAL(x)[i];
    t.coords[2 * i + 1] = REAL(y)[i];
  }
  if (n > 0) zgo_kd_sort(&t, 0, (int64_t)n - 1, 0);
  UNPROTECT(1);
  return out;
}

static const char *zgo_kd_view(SEXP raw, zgo_kd *t, char *message, size_t n) {
  zgo_rtree unused;
  uint32_t items = 0, node = 0;
  const char *type = zgo_index_view(raw, &unused, &items, &node, message, n);
  if (type == NULL) return message;
  if (strcmp(type, "kdtree") != 0) return "Not a k-d tree.";
  t->n = items;
  t->node_size = node;
  t->u32 = items >= 65536;
  int64_t ids = (int64_t)items * (t->u32 ? 4 : 2);
  int64_t pad = (8 - ids % 8) % 8;
  t->ids = RAW(raw) + 8;
  t->coords = (double *)(RAW(raw) + 8 + ids + pad);
  return NULL;
}

/* kdbush's range() and within(): mode 0 for boxes (a, b, c, d = min x,
   min y, max x, max y), mode 1 for circles (a, b, c = x, y, radius). */
static const char *zgo_kd_query(const zgo_kd *t, int mode, double a, double b, double c,
                                double d, int query, zgo_pairs *out) {
  if (t->n == 0) return NULL;
  int64_t stack[3 * 128];
  int sp = 0;
  stack[sp++] = 0;
  stack[sp++] = (int64_t)t->n - 1;
  stack[sp++] = 0;
  double r2 = c * c;
  while (sp > 0) {
    int axis = (int)stack[--sp];
    int64_t right = stack[--sp];
    int64_t left = stack[--sp];
    if (right - left <= (int64_t)t->node_size) {
      for (int64_t i = left; i <= right; i++) {
        double x = t->coords[2 * i], y = t->coords[2 * i + 1];
        int hit = mode == 0 ? (x >= a && x <= c && y >= b && y <= d)
                            : ((x - a) * (x - a) + (y - b) * (y - b) <= r2);
        if (hit) {
          uint32_t id = zgo_kd_id(t, i);
          if (id >= t->n) return "The index's item numbers are corrupt.";
          if (zgo_pairs_push(out, query, (int)id)) return "Could not allocate the results.";
        }
      }
      continue;
    }
    int64_t m = (left + right) >> 1;
    double x = t->coords[2 * m], y = t->coords[2 * m + 1];
    int hit = mode == 0 ? (x >= a && x <= c && y >= b && y <= d)
                        : ((x - a) * (x - a) + (y - b) * (y - b) <= r2);
    if (hit) {
      uint32_t id = zgo_kd_id(t, m);
      if (id >= t->n) return "The index's item numbers are corrupt.";
      if (zgo_pairs_push(out, query, (int)id)) return "Could not allocate the results.";
    }
    double lo = mode == 0 ? (axis == 0 ? a : b) : (axis == 0 ? a - c : b - c);
    double hi = mode == 0 ? (axis == 0 ? c : d) : (axis == 0 ? a + c : b + c);
    double split = axis == 0 ? x : y;
    if (sp + 6 > (int)(sizeof(stack) / sizeof(stack[0]))) return "The k-d tree is too deep.";
    if (lo <= split) {
      stack[sp++] = left;
      stack[sp++] = m - 1;
      stack[sp++] = 1 - axis;
    }
    if (hi >= split) {
      stack[sp++] = m + 1;
      stack[sp++] = right;
      stack[sp++] = 1 - axis;
    }
  }
  return NULL;
}

SEXP zgo_c_kdtree_query(SEXP raw, SEXP mode_sexp, SEXP a, SEXP b, SEXP c, SEXP d) {
  zgo_kd t;
  char message[256];
  const char *m = zgo_kd_view(raw, &t, message, sizeof(message));
  if (m != NULL) return zgo_index_failure(m);
  int mode = Rf_asInteger(mode_sexp);
  R_xlen_t n = Rf_xlength(a);
  zgo_pairs pairs = {NULL, NULL, 0, 0};
  for (R_xlen_t q = 0; q < n; q++) {
    double dv = mode == 0 ? REAL(d)[q] : 0;
    if (ISNAN(REAL(a)[q]) || ISNAN(REAL(b)[q]) || ISNAN(REAL(c)[q]) || ISNAN(dv)) continue;
    m = zgo_kd_query(&t, mode, REAL(a)[q], REAL(b)[q], REAL(c)[q], dv, (int)q, &pairs);
    if (m != NULL) {
      zgo_pairs_free(&pairs);
      return zgo_index_failure(m);
    }
  }
  SEXP out = zgo_pairs_result(&pairs);
  zgo_pairs_free(&pairs);
  return out;
}
