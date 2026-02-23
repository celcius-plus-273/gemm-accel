import numpy as np
from ml_dtypes import float8_e4m3
import time
import struct

# helper function to convert from binary string to FP8 (e4m3)
def unpack_fp8_e4m3(byte_data):
    """
    Manually unpacks a single byte of FP8 (E4M3) data into a float32 representation.
    Based on the NVIDIA/ARM/Intel specification.
    """
    if not isinstance(byte_data, bytes) or len(byte_data) != 1:
        raise ValueError("Input must be a single byte")

    byte_val = byte_data[0]

    # Extract sign, exponent, and mantissa bits
    sign = (byte_val >> 7) & 0x01
    exponent_bits = (byte_val >> 3) & 0x0F
    mantissa_bits = byte_val & 0x07

    # E4M3 has a bias of 7, and an implicit leading 1 for normalized values
    # Handle special cases (zero, subnormals, infinity, NaN) according to spec

    # For a general understanding:
    if exponent_bits == 0:
        if mantissa_bits == 0:
            value = 0.0
        else:
            # Subnormal values
            # value = (-1)**sign * 2**(1 - bias) * (0. + mantissa/2**mantissa_bits)
            value = (-1)**sign * 2**(-6) * (mantissa_bits / 8.0)
    elif exponent_bits == 15:
        # Inf or NaN
        value = float('nan') if mantissa_bits != 0 else float('inf') * (-1)**sign
    else:
        # Normalized values
        # value = (-1)**sign * 2**(exponent - bias) * (1. + mantissa/2**mantissa_bits)
        exponent = exponent_bits - 7
        mantissa = 1.0 + (mantissa_bits / 8.0)
        value = (-1)**sign * (2**exponent) * mantissa

    return value

#  always binary :)
def from_twos_comp(val, bytes=1, dtype=int, format='b'):
    if format == 'b':
        bits = 2
    elif format =='h':
        bits = 16
    else:
        print(f"[ERROR]: Unknown format: {format}")
        exit(-1)

    int_val = int(val, bits)

    if dtype == int:
        unsgined_val = int(val, bits).to_bytes(bytes, 'big', signed=False)
        res = int.from_bytes(unsgined_val, 'big', signed=True)
    elif dtype == np.float32:
        res = struct.unpack('>f', int_val.to_bytes(bytes, byteorder='big'))[0]
    elif dtype == np.float16:
        res = struct.unpack('>e', int_val.to_bytes(bytes, byteorder='big'))[0]
    elif dtype == float8_e4m3:
        res = unpack_fp8_e4m3(int_val.to_bytes(bytes, byteorder='big'))
    else:
        print("Not supported yet :p")
        exit(-1)

    return res

def to_bin(file, A, rows, cols, numbytes, dtype, filetype='b'):
    # write memory to output format [bin/hex]
    f = open(file, 'w')
    for i in range(rows):
        for j in range(cols):
            # assert (A[i][j] <= 127 and A[i][j] >= -128) # saturate 8 bits
            if dtype == int:
                val = np.binary_repr(int(A[i][j]), width=numbytes*8)
            elif dtype == np.float32:
                val = np.binary_repr(np.float32(A[i][j]).view(np.int32), width=32)
            elif dtype == np.float16:
                val = np.binary_repr(np.float16(A[i][j]).view(np.int16), width=16)
            elif dtype == float8_e4m3:
                val = np.binary_repr((A[i][j]).astype(float8_e4m3).view(np.int8), width=8)

            f.write(f'{val}')
        f.write('\n')

# Converts a staggered matrix back into a non-staggered matrix
# Inputs
#   rows: row dimension of expected output matrix
#   cols: col dimension of expected output matrix
def stagger_to_matrix(A, rows, cols, dtype):
    # input matrix A must have the following staggered matrix dimensions
    assert A.shape == (rows + cols - 1, cols)

    # revert a staggered matrix
    # i: row pointer
    # j: col pointer
    B = np.zeros((rows, cols), dtype=dtype)
    for j in range(cols):
        for i in range(j, rows+j):
            B[i-j][j] = A[i][j]

    return B

def matrix_to_stagger(A, dtype):
    # A must be a 2D array
    assert A.ndim == 2

    # extract the two dimensions
    rows, cols = A.shape

    # instantiate output array dimensions
    B = np.zeros((rows + cols - 1, cols), dtype=dtype)
    for j in range(cols):
        for i in range(j, rows+j):
            B[i][j] = A[i-j][j]

    return B

def vertical_flip(A):
    # A must be a 2D array
    assert A.ndim == 2
    return np.flip(A, 0)

def horizontal_flip(A):
    # A must be a 2D array
    assert A.ndim == 2
    return np.flip(A, 1)

def random_matrix(range, dim, dtype, seed):
    # simple seed for now
    rng = np.random.default_rng(seed)

    if dtype == int:
        return rng.integers(range[0], range[1], dim).astype(int)
    else:
        return rng.uniform(range[0], range[1], dim).astype(dtype)

def read_output_mem(file, rows, cols, arr_rows, arr_cols, numbytes, dtype):
    B = np.zeros((rows + cols - 1, cols), dtype=dtype)
    f = open(file, 'r')
    lines = f.readlines()
    for i in range(rows + cols - 1):
        line = lines[i].strip()
        # each line has #cols * 8 bits
        for j in range(cols):
            start = 8*numbytes*(j + (arr_cols-cols))
            # start = 8*numbytes*j
            entry = line[start:start+(8*numbytes)]
            if entry == ('x'*8*numbytes):
                entry = '0'*8*numbytes

            B[i][j] = from_twos_comp(entry, numbytes, dtype)

    return stagger_to_matrix(horizontal_flip(B), rows, cols, dtype)

def read_golden(file, rows, cols, numbytes, dtype):
    B = np.zeros((rows, cols), dtype=dtype)
    f = open(file, 'r')
    lines = f.readlines()
    for i in range(rows):
        line = lines[i]
        # each line has #cols * 8*numbyte bits
        for j in range(cols):
            start = 8*numbytes*(j)
            entry = line[start:start+(8*numbytes)]
            B[i][j] = from_twos_comp(entry, numbytes, dtype)

    return B

if __name__ == '__main__':
    a = np.binary_repr(np.float32(1.1).view(np.int32), width=32)
    print(a)
    print(from_twos_comp(a, 4, np.float32))
