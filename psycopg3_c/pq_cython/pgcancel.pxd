from pq_cython cimport libpq


cdef class PGcancel:
    cdef libpq.PGcancel* pgcancel_ptr

    @staticmethod
    cdef PGcancel _from_ptr(libpq.PGcancel *ptr)
