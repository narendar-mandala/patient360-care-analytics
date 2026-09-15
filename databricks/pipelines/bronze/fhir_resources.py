"""Bronze: every FHIR resource from every source system, one row per NDJSON line.

The payload stays as the raw JSON string, so Bronze never breaks when a source adds fields or
resource types; typing happens in Silver. Each source system is its own append flow into
one streaming table.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

LANDING_ROOT = spark.conf.get("landing_root")  # noqa: F821 - spark is injected by the pipeline runtime

SOURCES = {
    "epic_fhir_sandbox": f"{LANDING_ROOT}/epic_fhir",
    "synthea": f"{LANDING_ROOT}/synthea_fhir",
}

dp.create_streaming_table(
    name="fhir_resources",
    comment="Raw FHIR R4 resources (NDJSON lines) from Epic sandbox and Synthea bulk export, with ingestion metadata.",
    cluster_by=["source_system", "resource_type"],
    table_properties={"quality": "bronze"},
    expect_all={
        "valid_json_with_type": "resource_type IS NOT NULL",
        "has_resource_id": "resource_id IS NOT NULL",
    },
)


def _read_ndjson(path: str):
    return (
        spark.readStream.format("cloudFiles")  # noqa: F821
        .option("cloudFiles.format", "text")
        .option("pathGlobFilter", "*.ndjson")
        .load(path)
    )


def _with_metadata(df, source_system: str):
    file_path = F.col("_metadata.file_path")
    return df.select(
        F.lit(source_system).alias("source_system"),
        F.get_json_object("value", "$.resourceType").alias("resource_type"),
        F.get_json_object("value", "$.id").alias("resource_id"),
        F.get_json_object("value", "$.meta.lastUpdated").alias("source_last_updated"),
        F.col("value").alias("raw"),
        F.nullif(F.regexp_extract(file_path, r"run_id=([^/]+)", 1), F.lit("")).alias("run_id"),
        F.to_date(F.nullif(F.regexp_extract(file_path, r"extract_date=([0-9-]+)", 1), F.lit(""))).alias("extract_date"),
        file_path.alias("source_file"),
        F.col("_metadata.file_modification_time").alias("source_file_modified_at"),
        F.current_timestamp().alias("ingested_at"),
    )


def _register_flow(source_system: str, path: str):
    @dp.append_flow(target="fhir_resources", name=f"fhir_resources_from_{source_system}")
    def _flow():
        return _with_metadata(_read_ndjson(path), source_system)


for _source_system, _path in SOURCES.items():
    _register_flow(_source_system, _path)
