from posix.fcntl cimport pid_t
from pq_cython cimport libpq

ctypedef char *(*conn_bytes_f) (const libpq.PGconn *)
ctypedef int(*conn_int_f) (const libpq.PGconn *)

cdef class PGconn:
    cdef libpq.PGconn* pgconn_ptr
    cdef object __weakref__
    cdef public object notice_handler
    cdef public object notify_handler
    cdef pid_t _procpid

    @staticmethod
    cdef PGconn _from_ptr(libpq.PGconn *ptr)

    cdef int _ensure_pgconn(self) except 0
    cdef char *_call_bytes(self, conn_bytes_f func) except NULL
    cdef int _call_int(self, conn_int_f func) except -1

cdef void notice_receiver(void *arg, const libpq.PGresult *res_ptr) with gil
