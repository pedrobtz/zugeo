/* libFuzzer target for the parsers zugeo exposes to untrusted input
   (design section 9, "Hostile input"): geoarrow-c's WKB reader, with
   zugeo's bounds patch, and its WKT reader, with zugeo's zufast number
   parser, each driving the WKT writer, with zufast's printer. The first
   byte picks the reader: even for WKB, odd for WKT; the rest is the
   input. Built without R by r-actions' fuzz.yml (tools/fuzz/README.md). */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "geoarrow/geoarrow.h"
#include "nanoarrow/nanoarrow.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size < 1) return 0;
  struct GeoArrowWKTWriter writer;
  if (GeoArrowWKTWriterInit(&writer) != GEOARROW_OK) return 0;
  struct GeoArrowVisitor v;
  GeoArrowVisitorInitVoid(&v);
  GeoArrowWKTWriterInitVisitor(&writer, &v);
  struct GeoArrowError error;
  v.error = &error;

  int status;
  if (data[0] % 2 == 0) {
    struct GeoArrowWKBReader reader;
    if (GeoArrowWKBReaderInit(&reader) != GEOARROW_OK) {
      GeoArrowWKTWriterReset(&writer);
      return 0;
    }
    struct GeoArrowBufferView src = {data + 1, (int64_t)size - 1};
    status = GeoArrowWKBReaderVisit(&reader, src, &v);
    GeoArrowWKBReaderReset(&reader);
  } else {
    struct GeoArrowWKTReader reader;
    if (GeoArrowWKTReaderInit(&reader) != GEOARROW_OK) {
      GeoArrowWKTWriterReset(&writer);
      return 0;
    }
    struct GeoArrowStringView src = {(const char *)data + 1, (int64_t)size - 1};
    status = GeoArrowWKTReaderVisit(&reader, src, &v);
    GeoArrowWKTReaderReset(&reader);
  }

  if (status == GEOARROW_OK) {
    struct ArrowArray out;
    if (GeoArrowWKTWriterFinish(&writer, &out, &error) == GEOARROW_OK) {
      out.release(&out);
    }
  }
  GeoArrowWKTWriterReset(&writer);
  return 0;
}
