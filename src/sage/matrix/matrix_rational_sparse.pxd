include '../ext/cdefs.pxi'
include '../modules/vector_rational_sparse_h.pxi'

cimport matrix_sparse

cdef class Matrix_rational_sparse(matrix_sparse.Matrix_sparse):
    cdef mpq_vector* _matrix
    cdef int _initialized

    cdef int mpz_denom(self, mpz_t d) except -1
    cdef int mpz_height(self, mpz_t height) except -1

    cdef _dealloc(self)


