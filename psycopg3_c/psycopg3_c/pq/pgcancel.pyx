"""
psycopg3_c.pq_cython.PGcancel object implementation.
"""

# Copyright (C) 2020 The Psycopg Team


cdef class PGcancel:
    def __cinit__(self):
        self.pgcancel_ptr = NULL

    @staticmethod
    cdef PGcancel _from_ptr(impl.PGcancel *ptr):
        cdef PGcancel rv = PGcancel.__new__(PGcancel)
        rv.pgcancel_ptr = ptr
        return rv

    def __dealloc__(self) -> None:
        self.free()

    def free(self) -> None:
        if self.pgcancel_ptr is not NULL:
            impl.PQfreeCancel(self.pgcancel_ptr)
            self.pgcancel_ptr = NULL

    def cancel(self) -> None:
        cdef char buf[256]
        cdef int res = impl.PQcancel(self.pgcancel_ptr, buf, sizeof(buf))
        if not res:
            raise PQerror(
                f"cancel failed: {buf.decode('utf8', 'ignore')}"
            )
