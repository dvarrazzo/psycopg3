from pq_cython cimport libpq

cdef class PGresult:
    cdef libpq.PGresult* pgresult_ptr

    @staticmethod
    cdef PGresult _from_ptr(libpq.PGresult *ptr)
