"""
libpq Python wrapper using cython bindings.
"""

# Copyright (C) 2020 The Psycopg Team

from pq_cython cimport libpq

from psycopg3.pq.misc import PQerror, error_message

from psycopg3.pq import ConnStatus, PollingStatus, ExecStatus
from psycopg3.pq import TransactionStatus, Ping, DiagnosticField, Format


__impl__ = 'c'


def version():
    return libpq.PQlibVersion()


include "pgconn.pyx"
include "pgresult.pyx"
include "pgcancel.pyx"
include "conninfo.pyx"
include "escaping.pyx"
include "pqbuffer.pyx"
