from pq_cython cimport libpq

cdef class Conninfo:
    pass

cdef _options_from_array(libpq.PQconninfoOption *opts)
