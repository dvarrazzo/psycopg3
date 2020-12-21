"""
psycopg3_c.pq_cython.PGconn object implementation.
"""

# Copyright (C) 2020 The Psycopg Team

from posix.unistd cimport getpid
from cpython.mem cimport PyMem_Malloc, PyMem_Free
from cpython.bytes cimport PyBytes_AsString

import logging

from psycopg3_c.pq.libpq cimport Oid
from psycopg3.pq.misc import PGnotify

logger = logging.getLogger('psycopg3')


cdef class PGconn:
    @staticmethod
    cdef PGconn _from_ptr(libpq.PGconn *ptr):
        cdef PGconn rv = PGconn.__new__(PGconn)
        rv.pgconn_ptr = ptr

        libpq.PQsetNoticeReceiver(ptr, notice_receiver, <void *>rv)
        return rv

    def __cinit__(self):
        self.pgconn_ptr = NULL
        self._procpid = getpid()

    def __dealloc__(self):
        # Close the connection only if it was created in this process,
        # not if this object is being GC'd after fork.
        if self._procpid == getpid():
            self.finish()

    @classmethod
    def connect(cls, const char *conninfo) -> PGconn:
        cdef libpq.PGconn* pgconn = libpq.PQconnectdb(conninfo)
        if not pgconn:
            raise MemoryError("couldn't allocate PGconn")

        return PGconn._from_ptr(pgconn)

    @classmethod
    def connect_start(cls, const char *conninfo) -> PGconn:
        cdef libpq.PGconn* pgconn = libpq.PQconnectStart(conninfo)
        if not pgconn:
            raise MemoryError("couldn't allocate PGconn")

        return PGconn._from_ptr(pgconn)

    def connect_poll(self) -> PollingStatus:
        cdef int rv = self._call_int(<conn_int_f>libpq.PQconnectPoll)
        return PollingStatus(rv)

    def finish(self) -> None:
        if self.pgconn_ptr is not NULL:
            libpq.PQfinish(self.pgconn_ptr)
            self.pgconn_ptr = NULL

    @property
    def pgconn_ptr(self) -> Optional[int]:
        if self.pgconn_ptr:
            return <long><void *>self.pgconn_ptr
        else:
            return None

    @property
    def info(self) -> List["ConninfoOption"]:
        self._ensure_pgconn()
        cdef libpq.PQconninfoOption *opts = libpq.PQconninfo(self.pgconn_ptr)
        if opts is NULL:
            raise MemoryError("couldn't allocate connection info")
        rv = _options_from_array(opts)
        libpq.PQconninfoFree(opts)
        return rv

    def reset(self) -> None:
        self._ensure_pgconn()
        libpq.PQreset(self.pgconn_ptr)

    def reset_start(self) -> None:
        if not libpq.PQresetStart(self.pgconn_ptr):
            raise PQerror("couldn't reset connection")

    def reset_poll(self) -> PollingStatus:
        cdef int rv = self._call_int(<conn_int_f>libpq.PQresetPoll)
        return PollingStatus(rv)

    @classmethod
    def ping(self, const char *conninfo) -> Ping:
        cdef int rv = libpq.PQping(conninfo)
        return Ping(rv)

    @property
    def db(self) -> bytes:
        return self._call_bytes(libpq.PQdb)

    @property
    def user(self) -> bytes:
        return self._call_bytes(libpq.PQuser)

    @property
    def password(self) -> bytes:
        return self._call_bytes(libpq.PQpass)

    @property
    def host(self) -> bytes:
        return self._call_bytes(libpq.PQhost)

    @property
    def hostaddr(self) -> bytes:
        return b'TODO'

    @property
    def port(self) -> bytes:
        return self._call_bytes(libpq.PQport)

    @property
    def tty(self) -> bytes:
        return self._call_bytes(libpq.PQtty)

    @property
    def options(self) -> bytes:
        return self._call_bytes(libpq.PQoptions)

    @property
    def status(self) -> ConnStatus:
        cdef int rv = libpq.PQstatus(self.pgconn_ptr)
        return ConnStatus(rv)

    @property
    def transaction_status(self) -> TransactionStatus:
        cdef int rv = libpq.PQtransactionStatus(self.pgconn_ptr)
        return TransactionStatus(rv)

    def parameter_status(self, name: bytes) -> Optional[bytes]:
        self._ensure_pgconn()
        cdef const char *rv = libpq.PQparameterStatus(self.pgconn_ptr, name)
        if rv is not NULL:
            return rv
        else:
            return None

    @property
    def error_message(self) -> bytes:
        return libpq.PQerrorMessage(self.pgconn_ptr)

    @property
    def protocol_version(self) -> int:
        return self._call_int(libpq.PQprotocolVersion)

    @property
    def server_version(self) -> int:
        return self._call_int(libpq.PQserverVersion)

    @property
    def socket(self) -> int:
        return self._call_int(libpq.PQsocket)

    @property
    def backend_pid(self) -> int:
        return self._call_int(libpq.PQbackendPID)

    @property
    def needs_password(self) -> bool:
        return bool(self._call_int(libpq.PQconnectionNeedsPassword))

    @property
    def used_password(self) -> bool:
        return bool(self._call_int(libpq.PQconnectionUsedPassword))

    @property
    def ssl_in_use(self) -> bool:
        return bool(self._call_int(<conn_int_f>libpq.PQsslInUse))

    def exec_(self, command: bytes) -> PGresult:
        self._ensure_pgconn()
        cdef libpq.PGresult *pgresult = libpq.PQexec(self.pgconn_ptr, command)
        if pgresult is NULL:
            raise MemoryError("couldn't allocate PGresult")

        return PGresult._from_ptr(pgresult)

    def send_query(self, command: bytes) -> None:
        self._ensure_pgconn()
        if not libpq.PQsendQuery(self.pgconn_ptr, command):
            raise PQerror(f"sending query failed: {error_message(self)}")

    def exec_params(
        self,
        command: bytes,
        param_values: Optional[Sequence[Optional[bytes]]],
        param_types: Optional[Sequence[int]] = None,
        param_formats: Optional[Sequence[Format]] = None,
        result_format: Format = Format.TEXT,
    ) -> PGresult:
        self._ensure_pgconn()

        cdef int cnparams
        cdef Oid *ctypes
        cdef char *const *cvalues
        cdef int *clengths
        cdef int *cformats
        cnparams, ctypes, cvalues, clengths, cformats = _query_params_args(
            param_values, param_types, param_formats)

        cdef libpq.PGresult *pgresult = libpq.PQexecParams(
            self.pgconn_ptr, command, cnparams, ctypes,
            <const char *const *>cvalues, clengths, cformats, result_format)
        _clear_query_params(ctypes, cvalues, clengths, cformats)
        if pgresult is NULL:
            raise MemoryError("couldn't allocate PGresult")
        return PGresult._from_ptr(pgresult)

    def send_query_params(
        self,
        command: bytes,
        param_values: Optional[Sequence[Optional[bytes]]],
        param_types: Optional[Sequence[int]] = None,
        param_formats: Optional[Sequence[Format]] = None,
        result_format: Format = Format.TEXT,
    ) -> None:
        self._ensure_pgconn()

        cdef int cnparams
        cdef Oid *ctypes
        cdef char *const *cvalues
        cdef int *clengths
        cdef int *cformats
        cnparams, ctypes, cvalues, clengths, cformats = _query_params_args(
            param_values, param_types, param_formats)

        cdef int rv = libpq.PQsendQueryParams(
            self.pgconn_ptr, command, cnparams, ctypes,
            <const char *const *>cvalues,
            clengths, cformats, result_format)
        _clear_query_params(ctypes, cvalues, clengths, cformats)
        if not rv:
            raise PQerror(
                f"sending query and params failed: {error_message(self)}"
            )

    def send_prepare(
        self,
        name: bytes,
        command: bytes,
        param_types: Optional[Sequence[int]] = None,
    ) -> None:
        self._ensure_pgconn()

        cdef int i
        cdef int nparams = len(param_types) if param_types else 0
        cdef Oid *atypes = NULL
        if nparams:
            atypes = <Oid *>PyMem_Malloc(nparams * sizeof(Oid))
            for i in range(nparams):
                atypes[i] = param_types[i]

        cdef int rv = libpq.PQsendPrepare(
            self.pgconn_ptr, name, command, nparams, atypes
        )
        PyMem_Free(atypes)
        if not rv:
            raise PQerror(
                f"sending query and params failed: {error_message(self)}"
            )

    def send_query_prepared(
        self,
        name: bytes,
        param_values: Optional[Sequence[Optional[bytes]]],
        param_formats: Optional[Sequence[Format]] = None,
        result_format: Format = Format.TEXT,
    ) -> None:
        self._ensure_pgconn()

        cdef int cnparams
        cdef Oid *ctypes
        cdef char *const *cvalues
        cdef int *clengths
        cdef int *cformats
        cnparams, ctypes, cvalues, clengths, cformats = _query_params_args(
            param_values, None, param_formats)

        cdef int rv = libpq.PQsendQueryPrepared(
            self.pgconn_ptr, name, cnparams,
            <const char *const *>cvalues,
            clengths, cformats, result_format)
        _clear_query_params(ctypes, cvalues, clengths, cformats)
        if not rv:
            raise PQerror(
                f"sending prepared query failed: {error_message(self)}"
            )

    def prepare(
        self,
        name: bytes,
        command: bytes,
        param_types: Optional[Sequence[int]] = None,
    ) -> PGresult:
        self._ensure_pgconn()

        cdef int i
        cdef int nparams = len(param_types) if param_types else 0
        cdef Oid *atypes = NULL
        if nparams:
            atypes = <Oid *>PyMem_Malloc(nparams * sizeof(Oid))
            for i in range(nparams):
                atypes[i] = param_types[i]

        cdef libpq.PGresult *rv = libpq.PQprepare(
            self.pgconn_ptr, name, command, nparams, atypes)
        PyMem_Free(atypes)
        if rv is NULL:
            raise MemoryError("couldn't allocate PGresult")
        return PGresult._from_ptr(rv)

    def exec_prepared(
        self,
        name: bytes,
        param_values: Optional[Sequence[bytes]],
        param_formats: Optional[Sequence[int]] = None,
        result_format: int = 0,
    ) -> PGresult:
        self._ensure_pgconn()

        cdef int cnparams
        cdef Oid *ctypes
        cdef char *const *cvalues
        cdef int *clengths
        cdef int *cformats
        cnparams, ctypes, cvalues, clengths, cformats = _query_params_args(
            param_values, None, param_formats)

        cdef libpq.PGresult *rv = libpq.PQexecPrepared(
            self.pgconn_ptr, name, cnparams,
            <const char *const *>cvalues,
            clengths, cformats, result_format)

        _clear_query_params(ctypes, cvalues, clengths, cformats)
        if rv is NULL:
            raise MemoryError("couldn't allocate PGresult")
        return PGresult._from_ptr(rv)

    def describe_prepared(self, name: bytes) -> PGresult:
        self._ensure_pgconn()
        cdef libpq.PGresult *rv = libpq.PQdescribePrepared(self.pgconn_ptr, name)
        if rv is NULL:
            raise MemoryError("couldn't allocate PGresult")
        return PGresult._from_ptr(rv)

    def describe_portal(self, name: bytes) -> PGresult:
        self._ensure_pgconn()
        cdef libpq.PGresult *rv = libpq.PQdescribePortal(self.pgconn_ptr, name)
        if rv is NULL:
            raise MemoryError("couldn't allocate PGresult")
        return PGresult._from_ptr(rv)

    def get_result(self) -> Optional["PGresult"]:
        cdef libpq.PGresult *pgresult = libpq.PQgetResult(self.pgconn_ptr)
        if pgresult is NULL:
            return None
        return PGresult._from_ptr(pgresult)

    def consume_input(self) -> None:
        if 1 != libpq.PQconsumeInput(self.pgconn_ptr):
            raise PQerror(f"consuming input failed: {error_message(self)}")

    def is_busy(self) -> int:
        cdef int rv
        with nogil:
            rv = libpq.PQisBusy(self.pgconn_ptr)
        return rv

    @property
    def nonblocking(self) -> int:
        return libpq.PQisnonblocking(self.pgconn_ptr)

    @nonblocking.setter
    def nonblocking(self, arg: int) -> None:
        if 0 > libpq.PQsetnonblocking(self.pgconn_ptr, arg):
            raise PQerror(f"setting nonblocking failed: {error_message(self)}")

    def flush(self) -> int:
        cdef int rv = libpq.PQflush(self.pgconn_ptr)
        if rv < 0:
            raise PQerror(f"flushing failed:{error_message(self)}")
        return rv

    def get_cancel(self) -> PGcancel:
        cdef libpq.PGcancel *ptr = libpq.PQgetCancel(self.pgconn_ptr)
        if not ptr:
            raise PQerror("couldn't create cancel object")
        return PGcancel._from_ptr(ptr)

    def notifies(self) -> Optional[PGnotify]:
        cdef libpq.PGnotify *ptr
        with nogil:
            ptr = libpq.PQnotifies(self.pgconn_ptr)
        if ptr:
            ret = PGnotify(ptr.relname, ptr.be_pid, ptr.extra)
            libpq.PQfreemem(ptr)
            return ret
        else:
            return None

    def put_copy_data(self, buffer: bytes) -> int:
        cdef int rv
        cdef const char *cbuffer = PyBytes_AsString(buffer)
        cdef int length = len(buffer)
        rv = libpq.PQputCopyData(self.pgconn_ptr, cbuffer, length)
        if rv < 0:
            raise PQerror(f"sending copy data failed: {error_message(self)}")
        return rv

    def put_copy_end(self, error: Optional[bytes] = None) -> int:
        cdef int rv
        cdef const char *cerr = NULL
        if error is not None:
            cerr = PyBytes_AsString(error)
        rv = libpq.PQputCopyEnd(self.pgconn_ptr, cerr)
        if rv < 0:
            raise PQerror(f"sending copy end failed: {error_message(self)}")
        return rv

    def get_copy_data(self, async_: int) -> Tuple[int, bytes]:
        cdef char *buffer_ptr = NULL
        cdef int nbytes
        nbytes = libpq.PQgetCopyData(self.pgconn_ptr, &buffer_ptr, async_)
        if nbytes == -2:
            raise PQerror(f"receiving copy data failed: {error_message(self)}")
        if buffer_ptr is not NULL:
            # TODO: do it without copy
            data = buffer_ptr[:nbytes]
            libpq.PQfreemem(buffer_ptr)
            return nbytes, data
        else:
            return nbytes, b""

    def make_empty_result(self, exec_status: ExecStatus) -> PGresult:
        cdef libpq.PGresult *rv = libpq.PQmakeEmptyPGresult(
            self.pgconn_ptr, exec_status)
        if not rv:
            raise MemoryError("couldn't allocate empty PGresult")
        return PGresult._from_ptr(rv)

    cdef int _ensure_pgconn(self) except 0:
        if self.pgconn_ptr is not NULL:
            return 1

        raise PQerror("the connection is closed")

    cdef char *_call_bytes(self, conn_bytes_f func) except NULL:
        """
        Call one of the pgconn libpq functions returning a bytes pointer.
        """
        if not self._ensure_pgconn():
            return NULL
        cdef char *rv = func(self.pgconn_ptr)
        assert rv is not NULL
        return rv

    cdef int _call_int(self, conn_int_f func) except -1:
        """
        Call one of the pgconn libpq functions returning an int.
        """
        if not self._ensure_pgconn():
            return -1
        return func(self.pgconn_ptr)


cdef void notice_receiver(void *arg, const libpq.PGresult *res_ptr) with gil:
    cdef PGconn pgconn = <object>arg
    if pgconn.notice_handler is None:
        return

    cdef PGresult res = PGresult._from_ptr(<libpq.PGresult *>res_ptr)
    try:
        pgconn.notice_handler(res)
    except Exception as e:
        logger.exception("error in notice receiver: %s", e)

    res.pgresult_ptr = NULL  # avoid destroying the pgresult_ptr


cdef (int, Oid *, char * const*, int *, int *) _query_params_args(
    list param_values: Optional[Sequence[Optional[bytes]]],
    list param_types: Optional[Sequence[int]],
    list param_formats: Optional[Sequence[Format]],
) except *:
    cdef int i

    cdef int nparams = len(param_values) if param_values else 0
    if param_types is not None and len(param_types) != nparams:
        raise ValueError(
            "got %d param_values but %d param_types"
            % (nparams, len(param_types))
        )
    if param_formats is not None and len(param_formats) != nparams:
        raise ValueError(
            "got %d param_values but %d param_formats"
            % (nparams, len(param_formats))
        )

    cdef char **aparams = NULL
    cdef int *alenghts = NULL
    cdef char *ptr
    cdef Py_ssize_t length

    if nparams:
        aparams = <char **>PyMem_Malloc(nparams * sizeof(char *))
        alenghts = <int *>PyMem_Malloc(nparams * sizeof(int))
        for i in range(nparams):
            obj = param_values[i]
            if obj is None:
                aparams[i] = NULL
                alenghts[i] = 0
            else:
                # TODO: it is a leak if this fails (but it should only fail
                # on internal error, e.g. if obj is not a buffer)
                _buffer_as_string_and_size(obj, &ptr, &length)
                aparams[i] = ptr
                alenghts[i] = length

    cdef Oid *atypes = NULL
    if param_types is not None:
        atypes = <Oid *>PyMem_Malloc(nparams * sizeof(Oid))
        for i in range(nparams):
            atypes[i] = param_types[i]

    cdef int *aformats = NULL
    if param_formats is not None:
        aformats = <int *>PyMem_Malloc(nparams * sizeof(int *))
        for i in range(nparams):
            aformats[i] = param_formats[i]

    return (nparams, atypes, aparams, alenghts, aformats)


cdef void _clear_query_params(
    Oid *ctypes, char *const *cvalues, int *clenghst, int *cformats
):
    PyMem_Free(ctypes)
    PyMem_Free(<char **>cvalues)
    PyMem_Free(clenghst)
    PyMem_Free(cformats)
