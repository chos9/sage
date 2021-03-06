r"""
Base class for dense matrices

TESTS::

    sage: R.<a,b> = QQ[]
    sage: m = matrix(R,2,[0,a,b,b^2])
    sage: TestSuite(m).run()
"""

cimport matrix

from   sage.structure.element    cimport Element
import sage.matrix.matrix_space
import sage.structure.sequence

include '../ext/cdefs.pxi'
include '../ext/stdsage.pxi'

cdef class Matrix_dense(matrix.Matrix):
    cdef bint is_sparse_c(self):
        return 0

    cdef bint is_dense_c(self):
        return 1

    def __copy__(self):
        """
        Return a copy of this matrix. Changing the entries of the copy will
        not change the entries of this matrix.
        """
        A = self.new_matrix(entries=self.list(), coerce=False, copy=False)
        if self._subdivisions is not None:
            A.subdivide(*self.subdivisions())
        return A

    def __hash__(self):
        """
        Return the hash of this matrix.

        Equal matrices should have equal hashes, even if one is sparse and
        the other is dense.

        EXAMPLES::

            sage: m = matrix(2, range(24), sparse=True)
            sage: m.set_immutable()
            sage: hash(m)
            976

        ::

            sage: d = m.dense_matrix()
            sage: d.set_immutable()
            sage: hash(d)
            976

        ::

            sage: hash(m) == hash(d)
            True
        """
        return self._hash()

    cdef long _hash(self) except -1:
        x = self.fetch('hash')
        if not x is None: return x

        if not self._is_immutable:
            raise TypeError, "mutable matrices are unhashable"

        v = self._list()
        cdef Py_ssize_t i
        cdef long h = 0

        for i from 0 <= i < len(v):
            h = h ^ (i * hash(v[i]))

        if h == -1:
            h = -2

        self.cache('hash', h)
        return h

    cdef set_unsafe_int(self, Py_ssize_t i, Py_ssize_t j, int value):
        self[i][j] = value

    def _pickle(self):
        version = -1
        data = self._list()  # linear list of all elements
        return data, version

    def _unpickle_generic(self, data, int version):
        cdef Py_ssize_t i, j, k
        if version == -1:
            # data is a *list* of the entries of the matrix.
            # TODO: Change the data[k] below to use the fast list access macros from the Python/C API
            k = 0
            for i from 0 <= i < self._nrows:
                for j from 0 <= j < self._ncols:
                    self.set_unsafe(i, j, data[k])
                    k = k + 1
        else:
            raise RuntimeError, "unknown matrix version (=%s)"%version

    cdef int _cmp_c_impl(self, Element right) except -2:
        """
        EXAMPLES::

            sage: P.<x> = QQ[]
            sage: m = matrix([[x,x+1],[1,x]])
            sage: n = matrix([[x+1,x],[1,x]])
            sage: o = matrix([[x,x],[1,x]])
            sage: m.__cmp__(n)
            -1
            sage: m.__cmp__(m)
            0
            sage: n.__cmp__(m)
            1
            sage: m.__cmp__(o)
            1
        """
        cdef Py_ssize_t i, j
        for i from 0 <= i < self._nrows:
            for j from 0 <= j < self._ncols:
                res = cmp( self[i,j], right[i,j] )
                if res != 0:
                    return res
        return 0

    def transpose(self):
        """
        Returns the transpose of self, without changing self.

        EXAMPLES: We create a matrix, compute its transpose, and note that
        the original matrix is not changed.

        ::

            sage: M = MatrixSpace(QQ,  2)
            sage: A = M([1,2,3,4])
            sage: B = A.transpose()
            sage: print B
            [1 3]
            [2 4]
            sage: print A
            [1 2]
            [3 4]

        ``.T`` is a convenient shortcut for the transpose::

           sage: A.T
           [1 3]
           [2 4]

        ::

            sage: A.subdivide(None, 1); A
            [1|2]
            [3|4]
            sage: A.transpose()
            [1 3]
            [---]
            [2 4]
        """
        (nc, nr) = (self.ncols(), self.nrows())
        cdef Matrix_dense trans
        trans = self.new_matrix(nrows = nc, ncols = nr,
                                copy=False, coerce=False)

        cdef Py_ssize_t i, j
        for j from 0<= j < nc:
            for i from 0<= i < nr:
                trans.set_unsafe(j,i,self.get_unsafe(i,j))

        if self._subdivisions is not None:
            row_divs, col_divs = self.subdivisions()
            trans.subdivide(col_divs, row_divs)
        return trans

    def antitranspose(self):
        """
        Returns the antitranspose of self, without changing self.

        EXAMPLES::

            sage: A = matrix(2,3,range(6)); A
            [0 1 2]
            [3 4 5]
            sage: A.antitranspose()
            [5 2]
            [4 1]
            [3 0]

        ::

            sage: A.subdivide(1,2); A
            [0 1|2]
            [---+-]
            [3 4|5]
            sage: A.antitranspose()
            [5|2]
            [-+-]
            [4|1]
            [3|0]
        """
        (nc, nr) = (self.ncols(), self.nrows())
        cdef Matrix_dense atrans
        atrans = self.new_matrix(nrows = nc, ncols = nr,
                                 copy=False, coerce=False)
        cdef Py_ssize_t i,j
        cdef Py_ssize_t ri,rj # reversed i and j
        rj = nc
        for j from 0 <= j < nc:
            ri = nr
            rj = rj-1
            for i from 0 <= i < nr:
                ri = ri-1
                atrans.set_unsafe(j , i, self.get_unsafe(ri,rj))

        if self._subdivisions is not None:
            row_divs, col_divs = self.subdivisions()
            atrans.subdivide([nc - t for t in reversed(col_divs)],
                             [nr - t for t in reversed(row_divs)])
        return atrans

    def _elementwise_product(self, right):
        r"""
        Returns the elementwise product of two dense
        matrices with identical base rings.

        This routine assumes that ``self`` and ``right``
        are both matrices, both dense, with identical
        sizes and with identical base rings.  It is
        "unsafe" in the sense that these conditions
        are not checked and no sensible errors are
        raised.

        This routine is meant to be called from the
        meth:`~sage.matrix.matrix2.Matrix.elementwise_product`
        method, which will ensure that this routine receives
        proper input.  More thorough documentation is provided
        there.

        EXAMPLE::

            sage: A = matrix(ZZ, 2, range(6), sparse=False)
            sage: B = matrix(ZZ, 2, [1,0,2,0,3,0], sparse=False)
            sage: A._elementwise_product(B)
            [ 0  0  4]
            [ 0 12  0]

        AUTHOR:

        - Rob Beezer (2009-07-14)
        """
        cdef Py_ssize_t r, c
        cdef Matrix_dense other, prod

        nc, nr = self.ncols(), self.nrows()
        other = right
        prod = self.new_matrix(nr, nc, copy=False, coerce=False)
        for r in range(nr):
            for c in range(nc):
                entry = self.get_unsafe(r,c)*other.get_unsafe(r,c)
                prod.set_unsafe(r,c,entry)
        return prod

    def apply_morphism(self, phi):
        """
        Apply the morphism phi to the coefficients of this dense matrix.

        The resulting matrix is over the codomain of phi.

        INPUT:


        -  ``phi`` - a morphism, so phi is callable and
           phi.domain() and phi.codomain() are defined. The codomain must be a
           ring.


        OUTPUT: a matrix over the codomain of phi

        EXAMPLES::

            sage: m = matrix(ZZ, 3, range(9))
            sage: phi = ZZ.hom(GF(5))
            sage: m.apply_morphism(phi)
            [0 1 2]
            [3 4 0]
            [1 2 3]
            sage: parent(m.apply_morphism(phi))
            Full MatrixSpace of 3 by 3 dense matrices over Finite Field of size 5

        We apply a morphism to a matrix over a polynomial ring::

            sage: R.<x,y> = QQ[]
            sage: m = matrix(2, [x,x^2 + y, 2/3*y^2-x, x]); m
            [          x     x^2 + y]
            [2/3*y^2 - x           x]
            sage: phi = R.hom([y,x])
            sage: m.apply_morphism(phi)
            [          y     y^2 + x]
            [2/3*x^2 - y           y]
        """
        R = phi.codomain()
        M = sage.matrix.matrix_space.MatrixSpace(R, self._nrows,
                   self._ncols, sparse=False)
        image = M([phi(z) for z in self.list()])
        if self._subdivisions is not None:
            image.subdivide(*self.subdivisions())
        return image

    def apply_map(self, phi, R=None, sparse=False):
        """
        Apply the given map phi (an arbitrary Python function or callable
        object) to this dense matrix. If R is not given, automatically
        determine the base ring of the resulting matrix.

        INPUT:
            sparse -- True to make the output a sparse matrix; default False


        -  ``phi`` - arbitrary Python function or callable
           object

        -  ``R`` - (optional) ring


        OUTPUT: a matrix over R

        EXAMPLES::

            sage: m = matrix(ZZ, 3, range(9))
            sage: k.<a> = GF(9)
            sage: f = lambda x: k(x)
            sage: n = m.apply_map(f); n
            [0 1 2]
            [0 1 2]
            [0 1 2]
            sage: n.parent()
            Full MatrixSpace of 3 by 3 dense matrices over Finite Field in a of size 3^2

        In this example, we explicitly specify the codomain.

        ::

            sage: s = GF(3)
            sage: f = lambda x: s(x)
            sage: n = m.apply_map(f, k); n
            [0 1 2]
            [0 1 2]
            [0 1 2]
            sage: n.parent()
            Full MatrixSpace of 3 by 3 dense matrices over Finite Field in a of size 3^2

        If self is subdivided, the result will be as well::

            sage: m = matrix(2, 2, srange(4))
            sage: m.subdivide(None, 1); m
            [0|1]
            [2|3]
            sage: m.apply_map(lambda x: x*x)
            [0|1]
            [4|9]

        If the map sends most of the matrix to zero, then it may be useful
        to get the result as a sparse matrix.

        ::

            sage: m = matrix(ZZ, 3, 3, range(1, 10))
            sage: n = m.apply_map(lambda x: 1//x, sparse=True); n
            [1 0 0]
            [0 0 0]
            [0 0 0]
            sage: n.parent()
            Full MatrixSpace of 3 by 3 sparse matrices over Integer Ring

        TESTS::

            sage: m = matrix([])
            sage: m.apply_map(lambda x: x*x) == m
            True

            sage: m.apply_map(lambda x: x*x, sparse=True).parent()
            Full MatrixSpace of 0 by 0 sparse matrices over Integer Ring
        """
        if self._nrows==0 or self._ncols==0:
            if sparse:
                return self.sparse_matrix()
            else:
                return self.__copy__()
        v = [phi(z) for z in self.list()]
        if R is None:
            v = sage.structure.sequence.Sequence(v)
            R = v.universe()
        M = sage.matrix.matrix_space.MatrixSpace(R, self._nrows,
                   self._ncols, sparse=sparse)
        image = M(v)
        if self._subdivisions is not None:
            image.subdivide(*self.subdivisions())
        return image

    def _derivative(self, var=None, R=None):
        """
        Differentiate with respect to var by differentiating each element
        with respect to var.

        .. seealso::

           :meth:`derivative`

        EXAMPLES::

            sage: m = matrix(2, [x^i for i in range(4)])
            sage: m._derivative(x)
            [    0     1]
            [  2*x 3*x^2]
        """
        # We would just use apply_map, except that Cython doesn't
        # allow lambda functions

        if self._nrows==0 or self._ncols==0:
            return self.__copy__()
        v = [z.derivative(var) for z in self.list()]
        if R is None:
            v = sage.structure.sequence.Sequence(v)
            R = v.universe()
        M = sage.matrix.matrix_space.MatrixSpace(R, self._nrows,
                   self._ncols, sparse=False)
        image = M(v)
        if self._subdivisions is not None:
            image.subdivide(*self.subdivisions())
        return image

