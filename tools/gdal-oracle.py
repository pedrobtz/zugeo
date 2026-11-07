"""GDAL reads every GeoParquet file zugeo writes (design section 9, Stage 7).

Run by oracles.yaml in GDAL's own image, which has the Arrow-based Parquet
driver that the GDAL behind sf lacks. test-ci-parquet.R writes the files and
expected.json (per file: the hex WKB zugeo reads back, and its CRS text or
null) into the directory given as the one argument. Exits non-zero on any
difference.
"""

import json
import os
import sys

from osgeo import gdal, ogr, osr

gdal.UseExceptions()


def same_crs(srs, expected):
    if expected is None:
        return srs is None
    if srs is None:
        return False
    want = osr.SpatialReference()
    want.SetFromUserInput(expected)
    want.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return bool(srs.IsSame(want, ["IGNORE_DATA_AXIS_TO_SRS_AXIS_MAPPING=YES"]))


def main(directory):
    with open(os.path.join(directory, "expected.json")) as f:
        cases = json.load(f)
    failures = []
    print("GDAL", gdal.__version__)
    for case in cases:
        path = os.path.join(directory, case["file"])
        ds = ogr.Open(path)
        if ds is None:
            failures.append(f"{case['file']}: GDAL cannot open it")
            continue
        driver = ds.GetDriver().GetName()
        layer = ds.GetLayer(0)
        got = []
        for feature in layer:
            g = feature.GetGeometryRef()
            got.append(None if g is None else g.ExportToIsoWkb().hex())
        want = case["wkb"]
        if got != want:
            failures.append(f"{case['file']}: geometries differ\n  GDAL:  {got[:3]}\n  zugeo: {want[:3]}")
        srs = layer.GetSpatialRef()
        if not same_crs(srs, case["crs"]):
            failures.append(
                f"{case['file']}: CRS differs: GDAL {srs.ExportToWkt() if srs else None}, "
                f"zugeo {case['crs']}"
            )
        print(f"{case['file']}: {driver}, {len(got)} features")
    for failure in failures:
        print("FAIL", failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
