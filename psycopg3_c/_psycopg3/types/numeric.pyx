"""
Cython adapters for numeric types.
"""

# Copyright (C) 2020 The Psycopg Team

from libc.stdint cimport *
from cpython.long cimport PyLong_FromString, PyLong_FromLong, PyLong_AsLongLong
from cpython.long cimport PyLong_FromLongLong, PyLong_FromUnsignedLong
from cpython.float cimport PyFloat_FromDouble

from _psycopg3 cimport oids
from _psycopg3.endian cimport be16toh, be32toh, be64toh, htobe64

cdef extern from "Python.h":
    # work around https://github.com/cython/cython/issues/3909
    double PyOS_string_to_double(
        const char *s, char **endptr, object overflow_exception) except? -1.0

    int PyOS_snprintf(char *str, size_t size, const char *format, ...)


cdef class IntDumper(CDumper):

    def __cinit__(self):
        self.oid = oids.INT8_OID

    def __init__(self, src: type, context: AdaptContext = None):
        super().__init__(src, context)

    def dump(self, obj) -> bytes:
        cdef char buf[22]
        cdef long long val = PyLong_AsLongLong(obj)
        cdef int written = PyOS_snprintf(buf, sizeof(buf), "%lld", val)
        return buf[:written]

    def quote(self, obj) -> bytes:
        cdef char buf[23]
        cdef long long val = PyLong_AsLongLong(obj)
        cdef int written
        if val >= 0:
            written = PyOS_snprintf(buf, sizeof(buf), "%lld", val)
        else:
            written = PyOS_snprintf(buf, sizeof(buf), " %lld", val)

        return buf[:written]


cdef class IntBinaryDumper(IntDumper):
    def dump(self, obj) -> bytes:
        cdef long long val = PyLong_AsLongLong(obj)
        cdef uint64_t *ptvar = <uint64_t *>(&val)
        cdef int64_t beval = htobe64(ptvar[0])
        cdef char *buf = <char *>&beval
        return buf[:sizeof(beval)]


cdef class IntLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        return PyLong_FromString(data, NULL, 10)


cdef class Int2BinaryLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        return PyLong_FromLong(<int16_t>be16toh((<uint16_t *>data)[0]))


cdef class Int4BinaryLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        return PyLong_FromLong(<int32_t>be32toh((<uint32_t *>data)[0]))


cdef class Int8BinaryLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        return PyLong_FromLongLong(<int64_t>be64toh((<uint64_t *>data)[0]))


cdef class OidBinaryLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        return PyLong_FromUnsignedLong(be32toh((<uint32_t *>data)[0]))


cdef class FloatLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        cdef double d = PyOS_string_to_double(data, NULL, OverflowError)
        return PyFloat_FromDouble(d)


cdef class Float4BinaryLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        cdef uint32_t asint = be32toh((<uint32_t *>data)[0])
        # avoid warning:
        # dereferencing type-punned pointer will break strict-aliasing rules
        cdef char *swp = <char *>&asint
        return PyFloat_FromDouble((<float *>swp)[0])


cdef class Float8BinaryLoader(CLoader):
    cdef object cload(self, const char *data, size_t length):
        cdef uint64_t asint = be64toh((<uint64_t *>data)[0])
        cdef char *swp = <char *>&asint
        return PyFloat_FromDouble((<double *>swp)[0])


cdef void register_numeric_c_adapters():
    logger.debug("registering optimised numeric c adapters")

    IntDumper.register(int)
    IntBinaryDumper.register(int, format=Format.BINARY)

    IntLoader.register(oids.INT2_OID)
    IntLoader.register(oids.INT4_OID)
    IntLoader.register(oids.INT8_OID)
    IntLoader.register(oids.OID_OID)
    FloatLoader.register(oids.FLOAT4_OID)
    FloatLoader.register(oids.FLOAT8_OID)

    Int2BinaryLoader.register(oids.INT2_OID, format=Format.BINARY)
    Int4BinaryLoader.register(oids.INT4_OID, format=Format.BINARY)
    Int8BinaryLoader.register(oids.INT8_OID, format=Format.BINARY)
    OidBinaryLoader.register(oids.OID_OID, format=Format.BINARY)
    Float4BinaryLoader.register(oids.FLOAT4_OID, format=Format.BINARY)
    Float8BinaryLoader.register(oids.FLOAT8_OID, format=Format.BINARY)
