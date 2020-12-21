from pq_cython.pgconn cimport PGconn

cdef class Escaping:
    cdef PGconn conn
