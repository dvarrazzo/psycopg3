cdef class PQBuffer:
    cdef unsigned char *buf
    cdef Py_ssize_t len

    @staticmethod
    cdef PQBuffer _from_buffer(unsigned char *buf, Py_ssize_t len)


cdef int _buffer_as_string_and_size(
    data: "Buffer", char **ptr, Py_ssize_t *length
) except -1
