/* Building Arrow schemas from an R spec: list(format, name, flags,
   metadata, children). Used by tests now and by export later (design
   section 6.1).

   The external pointer is made first and owns the schema from then on: a
   finalizer releases whatever was built, so an error part way through
   leaks nothing. */

#include "zgo.h"

#include <stdlib.h>
#include <string.h>

#include "nanoarrow/nanoarrow.h"

static void zgo_schema_finalize(SEXP xptr) {
  struct ArrowSchema *schema = (struct ArrowSchema *)R_ExternalPtrAddr(xptr);
  if (schema == NULL) return;
  if (schema->release != NULL) schema->release(schema);
  free(schema);
  R_ClearExternalPtr(xptr);
}

static SEXP zgo_spec_get(SEXP spec, const char *name) {
  SEXP names = Rf_getAttrib(spec, R_NamesSymbol);
  for (R_xlen_t i = 0; i < Rf_xlength(spec); i++) {
    if (strcmp(CHAR(STRING_ELT(names, i)), name) == 0) return VECTOR_ELT(spec, i);
  }
  return R_NilValue;
}

static int zgo_is_string(SEXP x) {
  return TYPEOF(x) == STRSXP && Rf_xlength(x) == 1 && STRING_ELT(x, 0) != NA_STRING;
}

/* Fills `schema`, already initialised to an empty schema, from `spec`.
   Returns a message on failure, NULL on success. No R allocation. */
static const char *zgo_fill(struct ArrowSchema *schema, SEXP spec) {
  if (TYPEOF(spec) != VECSXP || Rf_isNull(Rf_getAttrib(spec, R_NamesSymbol))) {
    return "A schema spec must be a named list.";
  }
  SEXP format = zgo_spec_get(spec, "format");
  if (!zgo_is_string(format)) return "A schema spec needs a `format` string.";
  if (ArrowSchemaSetFormat(schema, CHAR(STRING_ELT(format, 0))) != NANOARROW_OK) {
    return "Could not set the schema format.";
  }

  SEXP name = zgo_spec_get(spec, "name");
  if (zgo_is_string(name) &&
      ArrowSchemaSetName(schema, CHAR(STRING_ELT(name, 0))) != NANOARROW_OK) {
    return "Could not set the schema name.";
  }

  SEXP flags = zgo_spec_get(spec, "flags");
  if (TYPEOF(flags) == INTSXP && Rf_xlength(flags) == 1) {
    schema->flags = INTEGER(flags)[0];
  }

  SEXP metadata = zgo_spec_get(spec, "metadata");
  if (TYPEOF(metadata) == STRSXP && Rf_xlength(metadata) > 0) {
    SEXP keys = Rf_getAttrib(metadata, R_NamesSymbol);
    if (TYPEOF(keys) != STRSXP) return "Schema metadata must be a named character vector.";
    struct ArrowBuffer buffer;
    if (ArrowMetadataBuilderInit(&buffer, NULL) != NANOARROW_OK) {
      return "Could not allocate schema metadata.";
    }
    for (R_xlen_t i = 0; i < Rf_xlength(metadata); i++) {
      if (ArrowMetadataBuilderAppend(&buffer, ArrowCharView(CHAR(STRING_ELT(keys, i))),
                                     ArrowCharView(CHAR(STRING_ELT(metadata, i)))) !=
          NANOARROW_OK) {
        ArrowBufferReset(&buffer);
        return "Could not build schema metadata.";
      }
    }
    int status = ArrowSchemaSetMetadata(schema, (const char *)buffer.data);
    ArrowBufferReset(&buffer);
    if (status != NANOARROW_OK) return "Could not set schema metadata.";
  }

  SEXP children = zgo_spec_get(spec, "children");
  R_xlen_t n = TYPEOF(children) == VECSXP ? Rf_xlength(children) : 0;
  if (n > 0) {
    if (ArrowSchemaAllocateChildren(schema, n) != NANOARROW_OK) {
      return "Could not allocate schema children.";
    }
    for (R_xlen_t i = 0; i < n; i++) {
      ArrowSchemaInit(schema->children[i]);
      const char *message = zgo_fill(schema->children[i], VECTOR_ELT(children, i));
      if (message != NULL) return message;
    }
  }
  return NULL;
}

SEXP zgo_c_schema_from_spec(SEXP spec) {
  SEXP xptr = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(xptr, &zgo_schema_finalize, TRUE);
  struct ArrowSchema *schema = (struct ArrowSchema *)malloc(sizeof(struct ArrowSchema));
  if (schema == NULL) Rf_error("Could not allocate a schema.");
  schema->release = NULL;
  R_SetExternalPtrAddr(xptr, schema);
  ArrowSchemaInit(schema);

  const char *message = zgo_fill(schema, spec);
  if (message != NULL) Rf_error("%s", message);

  const char *cls[] = {"zugeo_schema", "nanoarrow_schema"};
  SEXP klass = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(klass, 0, Rf_mkChar(cls[0]));
  SET_STRING_ELT(klass, 1, Rf_mkChar(cls[1]));
  Rf_setAttrib(xptr, R_ClassSymbol, klass);
  UNPROTECT(2);
  return xptr;
}
