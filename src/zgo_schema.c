/* The schema view: what a GeoArrow field's Arrow schema says, checked
   against GeoArrow 0.2 (design sections 2 and 6.2). zugeo's own rather than
   geoarrow-c's GeoArrowSchemaViewInit(), which knows neither
   geoarrow.geometry nor geoarrow.geometrycollection, nor large_list offsets.

   Nothing here allocates on the C heap, so a failure can return straight
   to R: every check fills a zgo_view or a message, and only
   zgo_c_type_of() builds R objects. */

#include "zgo.h"

#include <stdio.h>
#include <string.h>

#include "nanoarrow/nanoarrow.h"

enum zgo_encoding { ZGO_NATIVE, ZGO_WKB, ZGO_WKT, ZGO_BOX };

/* Geometry type codes follow WKB and the union type ids: 1 point to 7
   geometry collection; 0 is "any" (geoarrow.geometry, WKB, WKT); 990 box. */
enum { ZGO_GEOM_ANY = 0, ZGO_GEOM_BOX = 990 };

/* Dimensions as the union type ids count them, tens digit plus one:
   1 XY, 2 XYZ, 3 XYM, 4 XYZM; 0 unknown or mixed. */
enum { ZGO_DIM_UNKNOWN = 0, ZGO_DIM_XY = 1, ZGO_DIM_XYZ, ZGO_DIM_XYM, ZGO_DIM_XYZM };

enum { ZGO_COORD_NONE = 0, ZGO_COORD_SEPARATED, ZGO_COORD_INTERLEAVED, ZGO_COORD_MIXED };

#define ZGO_MAX_DEPTH 4
#define ZGO_MAX_UNION 64

typedef struct {
  enum zgo_encoding encoding;
  int geometry_type;
  int dimensions;
  int coord_type;
  int n_offsets;
  int offsets_large[ZGO_MAX_DEPTH]; /* outer to inner: 0 list, 1 large_list */
  int n_union;
  int union_ids[ZGO_MAX_UNION];
} zgo_view;

typedef struct {
  char message[512];
} zgo_err;

static int zgo_fail(zgo_err *err, const char *fmt, const char *a, const char *b) {
  snprintf(err->message, sizeof(err->message), fmt, a ? a : "", b ? b : "");
  return 1;
}

static const char *zgo_name(const struct ArrowSchema *s) {
  return s->name ? s->name : "";
}

/* A child may not carry GeoArrow, or any, extension metadata (format.md:
   "The child arrays should not themselves contain GeoArrow metadata"). */
static int zgo_check_no_extension(const struct ArrowSchema *s, zgo_err *err) {
  struct ArrowStringView value = {NULL, 0};
  if (s->metadata != NULL &&
      ArrowMetadataGetValue(s->metadata, ArrowCharView("ARROW:extension:name"),
                            &value) == NANOARROW_OK &&
      value.data != NULL) {
    return zgo_fail(err, "Child field '%s' carries extension metadata; only the "
                         "top-level GeoArrow field may.",
                    zgo_name(s), NULL);
  }
  for (int64_t i = 0; i < s->n_children; i++) {
    if (zgo_check_no_extension(s->children[i], err)) return 1;
  }
  return 0;
}

static int zgo_is_double(const struct ArrowSchema *s) {
  return s->format != NULL && strcmp(s->format, "g") == 0 && s->dictionary == NULL;
}

/* Coordinates, separated (struct of doubles) or interleaved (fixed-size
   list of doubles). The z/m ambiguity of three dimensions is settled by
   names, which format.md fixes for this purpose. */
static int zgo_parse_coord(const struct ArrowSchema *s, zgo_view *v, zgo_err *err) {
  if (strcmp(s->format, "+s") == 0) {
    int64_t n = s->n_children;
    if (n < 2 || n > 4) {
      return zgo_fail(err, "Separated coordinates '%s' need 2 to 4 double fields.",
                      zgo_name(s), NULL);
    }
    for (int64_t i = 0; i < n; i++) {
      if (!zgo_is_double(s->children[i])) {
        return zgo_fail(err, "Coordinate field '%s' of '%s' is not a double.",
                        zgo_name(s->children[i]), zgo_name(s));
      }
    }
    v->coord_type = ZGO_COORD_SEPARATED;
    if (n == 2) {
      v->dimensions = ZGO_DIM_XY;
    } else if (n == 4) {
      v->dimensions = ZGO_DIM_XYZM;
    } else {
      const char *third = zgo_name(s->children[2]);
      if (strcmp(third, "z") == 0) {
        v->dimensions = ZGO_DIM_XYZ;
      } else if (strcmp(third, "m") == 0) {
        v->dimensions = ZGO_DIM_XYM;
      } else {
        return zgo_fail(err, "Three separated coordinates need a third field named "
                             "'z' or 'm', not '%s'.",
                        third, NULL);
      }
    }
    return 0;
  }

  if (strncmp(s->format, "+w:", 3) == 0) {
    const char *size = s->format + 3;
    if (s->n_children != 1 || !zgo_is_double(s->children[0])) {
      return zgo_fail(err, "Interleaved coordinates '%s' need one double child.",
                      zgo_name(s), NULL);
    }
    const char *child = zgo_name(s->children[0]);
    v->coord_type = ZGO_COORD_INTERLEAVED;
    if (strcmp(size, "2") == 0) {
      v->dimensions = ZGO_DIM_XY;
    } else if (strcmp(size, "4") == 0) {
      v->dimensions = ZGO_DIM_XYZM;
    } else if (strcmp(size, "3") == 0) {
      if (strcmp(child, "xyz") == 0) {
        v->dimensions = ZGO_DIM_XYZ;
      } else if (strcmp(child, "xym") == 0) {
        v->dimensions = ZGO_DIM_XYM;
      } else {
        return zgo_fail(err, "Three interleaved coordinates need a child named 'xyz' "
                             "or 'xym', not '%s'.",
                        child, NULL);
      }
    } else {
      return zgo_fail(err, "Interleaved coordinates of width %s; GeoArrow allows 2 to 4.",
                      size, NULL);
    }
    return 0;
  }

  return zgo_fail(err, "Coordinates '%s' have storage '%s'; GeoArrow needs a struct "
                       "or a fixed-size list of doubles.",
                  zgo_name(s), s->format);
}

/* `levels` list levels around the coordinates, outer to inner. */
static int zgo_parse_nested(const struct ArrowSchema *s, int levels, zgo_view *v,
                            zgo_err *err) {
  if (levels == 0) return zgo_parse_coord(s, v, err);
  int large;
  if (strcmp(s->format, "+l") == 0) {
    large = 0;
  } else if (strcmp(s->format, "+L") == 0) {
    large = 1;
  } else {
    return zgo_fail(err, "Field '%s' has storage '%s' where GeoArrow needs a list or "
                         "large list.",
                    zgo_name(s), s->format);
  }
  if (s->n_children != 1) {
    return zgo_fail(err, "List field '%s' has no child.", zgo_name(s), NULL);
  }
  v->offsets_large[v->n_offsets++] = large;
  return zgo_parse_nested(s->children[0], levels - 1, v, err);
}

/* List levels around the coordinates for geometry types 1 to 6. */
static int zgo_levels(int geometry_type) {
  static const int levels[] = {0, 0, 1, 2, 1, 2, 3};
  return levels[geometry_type];
}

static const char *zgo_geometry_label(int code) {
  switch (code) {
    case 1: return "point";
    case 2: return "linestring";
    case 3: return "polygon";
    case 4: return "multipoint";
    case 5: return "multilinestring";
    case 6: return "multipolygon";
    case 7: return "geometrycollection";
    case ZGO_GEOM_BOX: return "box";
    default: return "geometry";
  }
}

static const char *zgo_dims_label(int dims) {
  static const char *labels[] = {NULL, "xy", "xyz", "xym", "xyzm"};
  return labels[dims];
}

static int zgo_parse_union(const struct ArrowSchema *s, int allow_collection,
                           zgo_view *v, zgo_err *err);

/* One union child: its type id fixes its geometry type and dimensions, and
   its layout must agree. */
static int zgo_parse_union_child(const struct ArrowSchema *child, int id,
                                 int allow_collection, int *dims, int *coord,
                                 zgo_err *err) {
  char id_text[16];
  snprintf(id_text, sizeof(id_text), "%d", id);
  int type = id % 10;
  int want_dims = id / 10 + 1;
  if (type < 1 || type > 7 || want_dims > 4 || (type == 7 && !allow_collection)) {
    return zgo_fail(err, "Union child '%s' has type id %s, which GeoArrow does not "
                         "define here.",
                    zgo_name(child), id_text);
  }
  zgo_view cv;
  memset(&cv, 0, sizeof(cv));
  if (type == 7) {
    if (strcmp(child->format, "+l") != 0 && strcmp(child->format, "+L") != 0) {
      return zgo_fail(err, "Geometry collection child '%s' needs a list of a union, "
                           "not '%s'.",
                      zgo_name(child), child->format);
    }
    if (child->n_children != 1 || zgo_parse_union(child->children[0], 0, &cv, err)) {
      if (child->n_children != 1) {
        return zgo_fail(err, "List field '%s' has no child.", zgo_name(child), NULL);
      }
      return 1;
    }
  } else if (zgo_parse_nested(child, zgo_levels(type), &cv, err)) {
    return 1;
  }
  if (cv.dimensions != want_dims) {
    return zgo_fail(err, "Union child '%s' has type id %s but coordinates of other "
                         "dimensions.",
                    zgo_name(child), id_text);
  }
  *dims = cv.dimensions;
  *coord = cv.coord_type;
  return 0;
}

/* A dense union of native children (format.md, Geometry and
   GeometryCollection). Inside a collection the children share dimensions
   and none is itself a collection. */
static int zgo_parse_union(const struct ArrowSchema *s, int allow_collection,
                           zgo_view *v, zgo_err *err) {
  if (strncmp(s->format, "+ud:", 4) != 0) {
    return zgo_fail(err, "Field '%s' has storage '%s' where GeoArrow needs a dense "
                         "union.",
                    zgo_name(s), s->format);
  }
  int ids[ZGO_MAX_UNION];
  int n = 0;
  const char *p = s->format + 4;
  while (*p != '\0') {
    int id = 0, digits = 0;
    while (*p >= '0' && *p <= '9') {
      id = id * 10 + (*p - '0');
      p++;
      digits++;
      if (id > 127) break;
    }
    if (digits == 0 || id > 127 || n == ZGO_MAX_UNION || (*p != ',' && *p != '\0')) {
      return zgo_fail(err, "Union field '%s' has malformed type ids '%s'.", zgo_name(s),
                      s->format + 4);
    }
    ids[n++] = id;
    if (*p == ',') p++;
  }
  if (n != s->n_children) {
    return zgo_fail(err, "Union field '%s' lists type ids '%s' that do not match its "
                         "children.",
                    zgo_name(s), s->format + 4);
  }

  int dims = ZGO_DIM_UNKNOWN, coord = ZGO_COORD_NONE;
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < i; j++) {
      if (ids[j] == ids[i] ||
          (!allow_collection && ids[j] % 10 == ids[i] % 10)) {
        return zgo_fail(err, "Union field '%s' repeats a geometry type in '%s'.",
                        zgo_name(s), s->format + 4);
      }
    }
    int child_dims, child_coord;
    if (zgo_parse_union_child(s->children[i], ids[i], allow_collection, &child_dims,
                              &child_coord, err)) {
      return 1;
    }
    if (i == 0) {
      dims = child_dims;
      coord = child_coord;
    } else {
      if (child_dims != dims) {
        if (!allow_collection) {
          return zgo_fail(err, "Geometry collection union '%s' mixes dimensions.",
                          zgo_name(s), NULL);
        }
        dims = ZGO_DIM_UNKNOWN;
      }
      if (child_coord != coord) coord = ZGO_COORD_MIXED;
    }
    v->union_ids[i] = ids[i];
  }
  v->n_union = n;
  v->dimensions = dims;
  v->coord_type = coord;
  return 0;
}

static int zgo_parse_box(const struct ArrowSchema *s, zgo_view *v, zgo_err *err) {
  static const char *names[3][8] = {
      {"xmin", "ymin", "xmax", "ymax"},
      {"xmin", "ymin", "zmin", "xmax", "ymax", "zmax"},
      {"xmin", "ymin", "zmin", "mmin", "xmax", "ymax", "zmax", "mmax"}};
  static const char *names_m[6] = {"xmin", "ymin", "mmin", "xmax", "ymax", "mmax"};
  if (strcmp(s->format, "+s") != 0 ||
      (s->n_children != 4 && s->n_children != 6 && s->n_children != 8)) {
    return zgo_fail(err, "geoarrow.box needs a struct of 4, 6 or 8 doubles, not '%s'.",
                    s->format, NULL);
  }
  int n = (int)s->n_children;
  const char **want = (const char **)names[(n - 4) / 2];
  int dims = n == 4 ? ZGO_DIM_XY : n == 8 ? ZGO_DIM_XYZM : ZGO_DIM_XYZ;
  if (n == 6 && strcmp(zgo_name(s->children[2]), "mmin") == 0) {
    want = names_m;
    dims = ZGO_DIM_XYM;
  }
  for (int i = 0; i < n; i++) {
    if (!zgo_is_double(s->children[i]) || strcmp(zgo_name(s->children[i]), want[i]) != 0) {
      return zgo_fail(err, "geoarrow.box field '%s' must be the double '%s'.",
                      zgo_name(s->children[i]), want[i]);
    }
  }
  v->dimensions = dims;
  v->geometry_type = ZGO_GEOM_BOX;
  return 0;
}

static int zgo_parse_serialized(const struct ArrowSchema *s, int wkb, zgo_view *v,
                                zgo_err *err) {
  const char *f = s->format;
  int ok = wkb ? (strcmp(f, "z") == 0 || strcmp(f, "Z") == 0 || strcmp(f, "vz") == 0)
               : (strcmp(f, "u") == 0 || strcmp(f, "U") == 0 || strcmp(f, "vu") == 0);
  if (!ok) {
    return zgo_fail(err, wkb ? "geoarrow.wkb needs binary, large binary or binary view "
                               "storage, not '%s'."
                             : "geoarrow.wkt needs string, large string or string view "
                               "storage, not '%s'.",
                    f, NULL);
  }
  v->encoding = wkb ? ZGO_WKB : ZGO_WKT;
  v->geometry_type = ZGO_GEOM_ANY;
  return 0;
}

static int zgo_view_init(const struct ArrowSchema *s, const char *ext, zgo_view *v,
                         zgo_err *err) {
  static const char *native[] = {"geoarrow.point", "geoarrow.linestring",
                                 "geoarrow.polygon", "geoarrow.multipoint",
                                 "geoarrow.multilinestring", "geoarrow.multipolygon"};
  memset(v, 0, sizeof(*v));
  if (s->dictionary != NULL) {
    return zgo_fail(err, "Field '%s' is dictionary-encoded; GeoArrow storage cannot be.",
                    zgo_name(s), NULL);
  }
  for (int64_t i = 0; i < s->n_children; i++) {
    if (zgo_check_no_extension(s->children[i], err)) return 1;
  }
  for (int t = 1; t <= 6; t++) {
    if (strcmp(ext, native[t - 1]) == 0) {
      v->encoding = ZGO_NATIVE;
      v->geometry_type = t;
      return zgo_parse_nested(s, zgo_levels(t), v, err);
    }
  }
  if (strcmp(ext, "geoarrow.geometry") == 0) {
    v->encoding = ZGO_NATIVE;
    v->geometry_type = ZGO_GEOM_ANY;
    return zgo_parse_union(s, 1, v, err);
  }
  if (strcmp(ext, "geoarrow.geometrycollection") == 0) {
    v->encoding = ZGO_NATIVE;
    v->geometry_type = 7;
    if (strcmp(s->format, "+l") != 0 && strcmp(s->format, "+L") != 0) {
      return zgo_fail(err, "geoarrow.geometrycollection needs a list of a union, not "
                           "'%s'.",
                      s->format, NULL);
    }
    if (s->n_children != 1) {
      return zgo_fail(err, "List field '%s' has no child.", zgo_name(s), NULL);
    }
    v->offsets_large[v->n_offsets++] = strcmp(s->format, "+L") == 0;
    return zgo_parse_union(s->children[0], 0, v, err);
  }
  if (strcmp(ext, "geoarrow.box") == 0) {
    v->encoding = ZGO_BOX;
    return zgo_parse_box(s, v, err);
  }
  if (strcmp(ext, "geoarrow.wkb") == 0) return zgo_parse_serialized(s, 1, v, err);
  if (strcmp(ext, "geoarrow.wkt") == 0) return zgo_parse_serialized(s, 0, v, err);
  return zgo_fail(err, "'%s' is not a GeoArrow 0.2 extension name.", ext, NULL);
}

/* ---- R interface ------------------------------------------------------ */

const struct ArrowSchema *zgo_schema_from_xptr(SEXP x) {
  if (TYPEOF(x) != EXTPTRSXP || !Rf_inherits(x, "nanoarrow_schema")) {
    Rf_error("Expected a schema handle.");
  }
  const struct ArrowSchema *s = (const struct ArrowSchema *)R_ExternalPtrAddr(x);
  if (s == NULL || s->release == NULL || s->format == NULL) {
    Rf_error("The schema handle has been released.");
  }
  return s;
}

SEXP zgo_failure(const char *kind, const char *message) {
  const char *names[] = {"kind", "message", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString(kind));
  SET_VECTOR_ELT(out, 1, Rf_mkString(message));
  Rf_setAttrib(out, R_ClassSymbol, Rf_mkString("zgo_failure"));
  UNPROTECT(1);
  return out;
}

static SEXP zgo_string_or_na(const char *data, int64_t n) {
  if (data == NULL) return Rf_ScalarString(NA_STRING);
  return Rf_ScalarString(Rf_mkCharLenCE(data, (int)n, CE_UTF8));
}

/* The extension name and metadata of a field, or NULL name if none. */
static void zgo_extension(const struct ArrowSchema *s, struct ArrowStringView *name,
                          struct ArrowStringView *metadata) {
  name->data = NULL;
  name->size_bytes = 0;
  metadata->data = NULL;
  metadata->size_bytes = 0;
  if (s->metadata == NULL) return;
  ArrowMetadataGetValue(s->metadata, ArrowCharView("ARROW:extension:name"), name);
  ArrowMetadataGetValue(s->metadata, ArrowCharView("ARROW:extension:metadata"),
                        metadata);
}

static SEXP zgo_describe(const struct ArrowSchema *s) {
  struct ArrowStringView name, metadata;
  zgo_extension(s, &name, &metadata);
  if (name.data == NULL) {
    /* Kind "none": geo_type_of() then looks at a struct's children. */
    return zgo_failure("none", "The field has no extension name, so it is not a "
                               "GeoArrow field.");
  }
  char ext[64];
  if (name.size_bytes >= (int64_t)sizeof(ext)) {
    return zgo_failure("layout", "The extension name is not a GeoArrow 0.2 name.");
  }
  memcpy(ext, name.data, (size_t)name.size_bytes);
  ext[name.size_bytes] = '\0';

  zgo_view v;
  zgo_err err;
  if (zgo_view_init(s, ext, &v, &err)) return zgo_failure("layout", err.message);

  static const char *encodings[] = {"native", "wkb", "wkt", "box"};
  static const char *coords[] = {NULL, "separated", "interleaved", "mixed"};
  const char *names[] = {"extension", "metadata", "storage", "encoding",
                         "geometry_type", "dimensions", "coord_type", "offsets",
                         "union_ids", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString(ext));
  SET_VECTOR_ELT(out, 1, zgo_string_or_na(metadata.data, metadata.size_bytes));
  SET_VECTOR_ELT(out, 2, Rf_mkString(s->format));
  SET_VECTOR_ELT(out, 3, Rf_mkString(encodings[v.encoding]));
  SET_VECTOR_ELT(out, 4, Rf_mkString(zgo_geometry_label(v.geometry_type)));
  const char *dims = v.dimensions ? zgo_dims_label(v.dimensions) : NULL;
  SET_VECTOR_ELT(out, 5, dims ? Rf_mkString(dims) : Rf_ScalarString(NA_STRING));
  const char *coord = coords[v.coord_type];
  SET_VECTOR_ELT(out, 6, coord ? Rf_mkString(coord) : Rf_ScalarString(NA_STRING));
  SEXP offsets = PROTECT(Rf_allocVector(STRSXP, v.n_offsets));
  for (int i = 0; i < v.n_offsets; i++) {
    SET_STRING_ELT(offsets, i, Rf_mkChar(v.offsets_large[i] ? "large_list" : "list"));
  }
  SET_VECTOR_ELT(out, 7, offsets);
  SEXP ids = PROTECT(Rf_allocVector(INTSXP, v.n_union));
  for (int i = 0; i < v.n_union; i++) INTEGER(ids)[i] = v.union_ids[i];
  SET_VECTOR_ELT(out, 8, ids);
  UNPROTECT(3);
  return out;
}

SEXP zgo_c_type_of(SEXP schema) {
  return zgo_describe(zgo_schema_from_xptr(schema));
}

/* The children of a struct schema that carry a geoarrow.* extension name,
   described, keyed by field name. */
SEXP zgo_c_type_of_children(SEXP schema) {
  const struct ArrowSchema *s = zgo_schema_from_xptr(schema);
  int n = 0;
  for (int64_t i = 0; i < s->n_children; i++) {
    struct ArrowStringView name, metadata;
    zgo_extension(s->children[i], &name, &metadata);
    if (name.data != NULL && name.size_bytes >= 9 && strncmp(name.data, "geoarrow.", 9) == 0) {
      n++;
    }
  }
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
  int k = 0;
  for (int64_t i = 0; i < s->n_children; i++) {
    struct ArrowStringView name, metadata;
    zgo_extension(s->children[i], &name, &metadata);
    if (name.data != NULL && name.size_bytes >= 9 && strncmp(name.data, "geoarrow.", 9) == 0) {
      SET_VECTOR_ELT(out, k, zgo_describe(s->children[i]));
      SET_STRING_ELT(names, k, Rf_mkCharCE(zgo_name(s->children[i]), CE_UTF8));
      k++;
    }
  }
  Rf_setAttrib(out, R_NamesSymbol, names);
  UNPROTECT(2);
  return out;
}

/* ---- For the array layer (zgo_array.c) -------------------------------- */

/* The geometry code of a GeoArrow field: 1 to 6 native, 7 collection, 0
   geometry union, ZGO_CODE_WKB, ZGO_CODE_WKT, ZGO_CODE_BOX; -1 otherwise. */
int zgo_extension_code(const struct ArrowSchema *s) {
  static const char *names[] = {"geoarrow.geometry", "geoarrow.point",
                                "geoarrow.linestring", "geoarrow.polygon",
                                "geoarrow.multipoint", "geoarrow.multilinestring",
                                "geoarrow.multipolygon", "geoarrow.geometrycollection"};
  struct ArrowStringView name, metadata;
  zgo_extension(s, &name, &metadata);
  if (name.data == NULL) return -1;
  for (int i = 0; i < 8; i++) {
    if ((size_t)name.size_bytes == strlen(names[i]) &&
        strncmp(name.data, names[i], (size_t)name.size_bytes) == 0) {
      return i;
    }
  }
  if (name.size_bytes == 12 && strncmp(name.data, "geoarrow.wkb", 12) == 0) return ZGO_CODE_WKB;
  if (name.size_bytes == 12 && strncmp(name.data, "geoarrow.wkt", 12) == 0) return ZGO_CODE_WKT;
  if (name.size_bytes == 12 && strncmp(name.data, "geoarrow.box", 12) == 0) return ZGO_CODE_BOX;
  return -1;
}

/* Dimensions (1 XY to 4 XYZM) of a native field of geometry type 1 to 6,
   from its coordinates; 0 if the layout is not valid. */
int zgo_native_dims(const struct ArrowSchema *s, int geometry_type) {
  zgo_view v;
  zgo_err err;
  memset(&v, 0, sizeof(v));
  if (zgo_parse_nested(s, zgo_levels(geometry_type), &v, &err)) return 0;
  return v.dimensions;
}
