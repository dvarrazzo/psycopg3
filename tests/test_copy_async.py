import pytest

from psycopg3 import errors as e
from psycopg3.adapt import Format

from .test_copy import sample_text, sample_binary  # noqa
from .test_copy import sample_values, sample_records, sample_tabledef

pytestmark = pytest.mark.asyncio


@pytest.mark.xfail
@pytest.mark.parametrize(
    "format, buffer",
    [(Format.TEXT, "sample_text"), (Format.BINARY, "sample_binary")],
)
async def test_copy_out_read(aconn, format, buffer):
    cur = aconn.cursor()
    copy = await cur.copy(
        f"copy ({sample_values}) to stdout (format {format.name})"
    )
    assert await copy.read() == globals()[buffer]
    assert await copy.read() is None
    assert await copy.read() is None


@pytest.mark.parametrize(
    "format, buffer",
    [(Format.TEXT, "sample_text"), (Format.BINARY, "sample_binary")],
)
async def test_copy_in_buffers(aconn, format, buffer):
    cur = aconn.cursor()
    await ensure_table(cur, sample_tabledef)
    copy = await cur.copy(f"copy copy_in from stdin (format {format.name})")
    await copy.write(globals()[buffer])
    await copy.finish()
    await cur.execute("select * from copy_in order by 1")
    data = await cur.fetchall()
    assert data == sample_records


async def test_copy_in_buffers_pg_error(aconn):
    cur = aconn.cursor()
    await ensure_table(cur, sample_tabledef)
    copy = await cur.copy("copy copy_in from stdin (format text)")
    await copy.write(sample_text)
    await copy.write(sample_text)
    with pytest.raises(e.UniqueViolation):
        await copy.finish()
    assert aconn.pgconn.transaction_status == aconn.TransactionStatus.INERROR


@pytest.mark.parametrize(
    "format, buffer",
    [(Format.TEXT, "sample_text"), (Format.BINARY, "sample_binary")],
)
async def test_copy_in_buffers_with(aconn, format, buffer):
    cur = aconn.cursor()
    await ensure_table(cur, sample_tabledef)
    async with (
        await cur.copy(f"copy copy_in from stdin (format {format.name})")
    ) as copy:
        await copy.write(globals()[buffer])

    await cur.execute("select * from copy_in order by 1")
    data = await cur.fetchall()
    assert data == sample_records


async def test_copy_in_buffers_with_pg_error(aconn):
    cur = aconn.cursor()
    await ensure_table(cur, sample_tabledef)
    with pytest.raises(e.UniqueViolation):
        async with (
            await cur.copy("copy copy_in from stdin (format text)")
        ) as copy:
            await copy.write(sample_text)
            await copy.write(sample_text)

    assert aconn.pgconn.transaction_status == aconn.TransactionStatus.INERROR


async def test_copy_in_buffers_with_py_error(aconn):
    cur = aconn.cursor()
    await ensure_table(cur, sample_tabledef)
    with pytest.raises(e.QueryCanceled) as exc:
        async with (
            await cur.copy("copy copy_in from stdin (format text)")
        ) as copy:
            await copy.write(sample_text)
            raise Exception("nuttengoggenio")

    assert "nuttengoggenio" in str(exc.value)
    assert aconn.pgconn.transaction_status == aconn.TransactionStatus.INERROR


async def ensure_table(cur, tabledef, name="copy_in"):
    await cur.execute(f"drop table if exists {name}")
    await cur.execute(f"create table {name} ({tabledef})")