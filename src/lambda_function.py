"""Sample complete-window SQL Server CDC -> Aurora PostgreSQL worker."""

import json
import os
import re

import boto3
import psycopg2
from psycopg2.extras import execute_values
import pyodbc

DELETE, INSERT, UPDATE_AFTER = 1, 2, 4
CAPTURE_RE = re.compile(r"^[A-Za-z0-9_]+$")
TABLE_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$")


def get_secret(secret_id):
    value = boto3.client("secretsmanager").get_secret_value(SecretId=secret_id)
    return json.loads(value["SecretString"])


def source_connection(secret):
    driver = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
    return pyodbc.connect(
        f"DRIVER={{{driver}}};SERVER={secret['host']},{int(secret.get('port',1433))};"
        f"DATABASE={secret['dbname']};UID={secret['username']};PWD={secret['password']};"
        "Encrypt=yes;TrustServerCertificate=no;",
        autocommit=True,
    )


def target_connection(secret):
    return psycopg2.connect(
        host=secret["host"], port=int(secret.get("port", 5432)),
        dbname=secret["dbname"], user=secret["username"], password=secret["password"],
        sslmode=os.getenv("PGSSLMODE", "verify-full"), connect_timeout=10,
    )


def read_checkpoint(conn, state_key):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT last_to_lsn FROM cdc_sync.cdc_state WHERE capture_instance=%s",
            (state_key,),
        )
        row = cur.fetchone()
    if not row:
        raise RuntimeError("Checkpoint is not initialized")
    return bytes(row[0])


def read_window(conn, capture, last_to_lsn):
    tvf = f"cdc.fn_cdc_get_all_changes_{capture}"
    with conn.cursor() as cur:
        cur.execute(
            """
            DECLARE @last binary(10)=?;
            DECLARE @min binary(10)=sys.fn_cdc_get_min_lsn(?);
            DECLARE @max binary(10)=sys.fn_cdc_get_max_lsn();
            DECLARE @from binary(10)=sys.fn_cdc_increment_lsn(@last);
            SELECT @min, @max, @from;
            """,
            (pyodbc.Binary(last_to_lsn), capture),
        )
        min_lsn, max_lsn, from_lsn = cur.fetchone()

        if min_lsn is None or max_lsn is None:
            raise RuntimeError(
                "CDC is not ready: min_lsn or max_lsn is NULL for the capture instance"
            )
        if from_lsn is None:
            raise RuntimeError("CDC window calculation returned a NULL from_lsn")

        min_lsn = bytes(min_lsn)
        max_lsn = bytes(max_lsn)
        from_lsn = bytes(from_lsn)

        if from_lsn < min_lsn:
            raise RuntimeError("CDC retention gap: from_lsn < min_lsn")
        if from_lsn > max_lsn:
            return None, []

        cur.execute(
            f"""
            DECLARE @from_lsn binary(10) = ?;
            DECLARE @to_lsn   binary(10) = ?;

            SELECT __$start_lsn, __$seqval, __$operation,
                   SourceRecordID, LargeTextValue, ModifiedAt
            FROM {tvf}(@from_lsn, @to_lsn, N'all')
            ORDER BY __$start_lsn, __$seqval
            """,
            (pyodbc.Binary(from_lsn), pyodbc.Binary(max_lsn)),
        )
        return max_lsn, cur.fetchall()


def reduce_changes(rows):
    final = {}
    for row in rows:
        op = int(row[2])
        if op not in (DELETE, INSERT, UPDATE_AFTER):
            continue
        if row[3] is None:
            raise RuntimeError("NULL SourceRecordID encountered")
        final[row[3]] = row
    return final


def apply_window(conn, table, state_key, to_lsn, final):
    deletes, upserts = [], []
    for key, row in final.items():
        if int(row[2]) == DELETE:
            deletes.append((key,))
        else:
            upserts.append((key, row[4], row[5]))

    try:
        with conn.cursor() as cur:
            if deletes:
                cur.executemany(
                    f"DELETE FROM {table} WHERE source_record_id=%s", deletes
                )
            if upserts:
                execute_values(
                    cur,
                    f"""INSERT INTO {table}
                        (source_record_id, large_text_value, modified_at)
                        VALUES %s
                        ON CONFLICT (source_record_id) DO UPDATE SET
                          large_text_value=EXCLUDED.large_text_value,
                          modified_at=EXCLUDED.modified_at""",
                    upserts,
                    page_size=500,
                )

            # Checkpoint and data changes commit atomically.
            cur.execute(
                """INSERT INTO cdc_sync.cdc_state
                     (capture_instance,last_to_lsn,updated_at)
                   VALUES (%s,%s,now())
                   ON CONFLICT (capture_instance) DO UPDATE SET
                     last_to_lsn=EXCLUDED.last_to_lsn,
                     updated_at=EXCLUDED.updated_at""",
                (state_key, psycopg2.Binary(to_lsn)),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise


def lambda_handler(event, context):
    capture = os.environ["CDC_CAPTURE_INSTANCE"]
    table = os.getenv("TARGET_TABLE", "public.large_object_records")
    state_key = os.getenv("STATE_CAPTURE_INSTANCE", capture)

    if not CAPTURE_RE.fullmatch(capture):
        raise ValueError("Invalid CDC capture instance")
    if not TABLE_RE.fullmatch(table):
        raise ValueError("Invalid target table")
    if not state_key or len(state_key) > 255:
        raise ValueError("Invalid checkpoint state key")

    src = tgt = None
    try:
        src = source_connection(get_secret(os.environ["SOURCE_SECRET_ID"]))
        tgt = target_connection(get_secret(os.environ["TARGET_SECRET_ID"]))

        last = read_checkpoint(tgt, state_key)
        to_lsn, rows = read_window(src, capture, last)
        if to_lsn is None:
            return {"status": "no_changes"}

        final = reduce_changes(rows)
        apply_window(tgt, table, state_key, to_lsn, final)
        return {
            "status": "applied",
            "cdc_rows_read": len(rows),
            "logical_records_applied": len(final),
        }
    finally:
        if src:
            src.close()
        if tgt:
            tgt.close()
