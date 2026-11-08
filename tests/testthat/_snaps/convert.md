# malformed WKB and WKT are errors naming the element

    Code
      geo_vctr(list(as.raw(1:3)))
    Condition
      Error in `geo_vctr()`:
      ! Element 1 is not valid WKB: Expected uint32 but found end of buffer at byte 1

---

    Code
      geo_vctr(c("POINT (1 2)", "POINT (1"))
    Condition
      Error in `geo_vctr()`:
      ! Element 2 is not valid WKT: Expected whitespace at byte 8

