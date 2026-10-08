"""Load source CSV files and run the Trino SQL pipeline."""

import csv
import io
import json
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

import psycopg2
from psycopg2 import sql


CLICKHOUSE_URL = os.environ.get("CLICKHOUSE_URL", "http://clickhouse:8123")
TRINO_URL = os.environ.get("TRINO_URL", "http://trino:8080")
POSTGRES_DSN = os.environ.get(
    "POSTGRES_DSN", "postgresql://sales:sales@postgres:5432/sales"
)
DATA_DIR = Path("/data")


def clickhouse(query: str, data: bytes = b"") -> str:
    parameters = urllib.parse.urlencode(
        {"query": query, "user": "sales", "password": "sales"}
    )
    request = urllib.request.Request(
        f"{CLICKHOUSE_URL}/?{parameters}", data=data, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return response.read().decode()
    except urllib.error.HTTPError as error:
        raise RuntimeError(error.read().decode()) from error


def source_files() -> list[Path]:
    return [DATA_DIR / "MOCK_DATA.csv"] + [
        DATA_DIR / f"MOCK_DATA ({index}).csv" for index in range(1, 10)
    ]


def load_raw() -> None:
    files = source_files()
    with files[0].open(newline="", encoding="utf-8") as source:
        fields = next(csv.reader(source))
    if len(fields) != 50:
        raise ValueError(f"Expected 50 source columns, got {len(fields)}")

    columns = fields + ["source_file", "source_row", "source_row_id"]
    clickhouse("CREATE DATABASE IF NOT EXISTS raw")
    clickhouse("DROP TABLE IF EXISTS raw.mock_data")
    declarations = [f"`{name}` String" for name in fields]
    declarations.extend(
        ["source_file String", "source_row Int64", "source_row_id String"]
    )
    clickhouse(
        "CREATE TABLE raw.mock_data ("
        + ", ".join(declarations)
        + ") ENGINE=MergeTree ORDER BY source_row_id"
    )

    counts = {"clickhouse": 0, "postgres": 0}
    with psycopg2.connect(POSTGRES_DSN) as connection:
        with connection.cursor() as cursor:
            cursor.execute("DROP TABLE IF EXISTS public.mock_data")
            declarations = [
                sql.SQL("{} TEXT").format(sql.Identifier(name)) for name in fields
            ]
            declarations.extend(
                [
                    sql.SQL("source_file TEXT"),
                    sql.SQL("source_row BIGINT"),
                    sql.SQL("source_row_id TEXT PRIMARY KEY"),
                ]
            )
            cursor.execute(
                sql.SQL("CREATE TABLE public.mock_data ({})").format(
                    sql.SQL(", ").join(declarations)
                )
            )

            for file_index, file in enumerate(files):
                buffer = io.StringIO(newline="")
                writer = csv.writer(buffer)
                writer.writerow(columns)
                count = 0
                with file.open(newline="", encoding="utf-8") as source:
                    reader = csv.DictReader(source)
                    if reader.fieldnames != fields:
                        raise ValueError(f"Header mismatch: {file.name}")
                    for source_row, row in enumerate(reader, 1):
                        writer.writerow(
                            [row[field] for field in fields]
                            + [file.name, source_row, f"{file.name}:{source_row}"]
                        )
                        count += 1

                if count != 1000:
                    raise ValueError(f"{file.name}: expected 1000 rows, got {count}")

                if file_index < 5:
                    clickhouse(
                        "INSERT INTO raw.mock_data FORMAT CSVWithNames",
                        buffer.getvalue().encode(),
                    )
                    counts["clickhouse"] += count
                else:
                    buffer.seek(0)
                    cursor.copy_expert(
                        "COPY public.mock_data FROM STDIN WITH "
                        "(FORMAT CSV, HEADER TRUE, NULL '__NULL__')",
                        buffer,
                    )
                    counts["postgres"] += count
                print(f"Imported {file.name}: {count} rows", flush=True)

    print(f"Raw source counts: {counts}", flush=True)
    if counts != {"clickhouse": 5000, "postgres": 5000}:
        raise AssertionError(f"Unexpected raw source counts: {counts}")


def trino_query(statement: str) -> list[list[object]]:
    headers = {
        "X-Trino-User": "sales",
        "X-Trino-Source": "bigdata-trino-lab",
    }
    request = urllib.request.Request(
        f"{TRINO_URL}/v1/statement", data=statement.encode(), headers=headers
    )
    rows: list[list[object]] = []
    query_id = "unknown"
    while True:
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                result = json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(error.read().decode()) from error

        query_id = result["id"]
        if "error" in result:
            raise RuntimeError(f"Trino {query_id}: {result['error']['message']}")
        rows.extend(result.get("data", []))
        if "nextUri" not in result:
            break
        request = urllib.request.Request(result["nextUri"], headers=headers)

    print(f"Trino {query_id}: {statement.splitlines()[0][:100]} -> {rows[:5]}", flush=True)
    return rows


def execute_sql_files() -> None:
    for file in sorted(Path("/sql").glob("*.sql")):
        print(f"Executing {file.name} through Trino", flush=True)
        text = "\n".join(
            line
            for line in file.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("--")
        )
        for statement in text.split(";"):
            if statement.strip():
                trino_query(statement.strip())


def main() -> None:
    load_raw()
    execute_sql_files()
    result = trino_query(
        "SELECT count(*), count(DISTINCT source_row_id), "
        "sum(sale_quantity), sum(sale_total_price) "
        "FROM clickhouse.sales.fact_sales"
    )
    if not result or result[0][0] != 10000 or result[0][1] != 10000:
        raise AssertionError(f"Unexpected fact table counts: {result}")
    print("ETL completed: 5000 ClickHouse + 5000 PostgreSQL rows, "
          "10000 facts, six marts.", flush=True)


if __name__ == "__main__":
    main()