# Shared by test-metadata.R; at file level there, a shuffled run could use it before it was defined.

type_with <- function(metadata) geo_type_of(ga_schema("point", metadata = metadata))
