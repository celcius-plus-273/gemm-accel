import numpy as np
import click as ck
from ml_dtypes import float8_e4m3
import sys
import os

from util import *
from pathlib import Path

# simulate the matrix mult with overflow saturation
def overflow_matmul_int(A, B, M, N, K, numbytes):
    # output matrix
    C = np.zeros((M, N), dtype=int)

    # max and min
    max_val = 2**((8*numbytes) - 1) - 1
    min_val = -1 * 2**((8*numbytes) - 1)

    # f = open('temp.log', 'w'

    # simply do a loop nest output stationary representatio (easier to model)
    # let m = row pointer
    # let n = col pointer
    # output dimensions is MxN
    for m in range(M):
        for n in range(N):
            # f.write(f'Output Matrix [{m}][{n}]\n')
            # each output result uses all the k psum values
            psum = 0
            for k in range(K):
                act = A[m][k]
                weight = B[k][n]
                # prod = np.clip(act * weight, min_val, max_val) # if saturation after mult is needed
                prod = act * weight
                psum = np.clip(prod + psum, min_val, max_val)

            # write output act/psum to index m, n
            C[m][n] = psum

    return C

@ck.command()
@ck.option('-d', '--dim', type=(int, int, int), help='Matrix Array Dimensions: (M,K) * (K,N) = (M,N)')
@ck.option('-b', '--bound', type=(int, int), help='Lower and upper bounds for matrix values')
@ck.option('-w', '--width', type=int, default=8, help='Data width in bits')
# @ck.option('-f', '--format', type=ck.Choice(['int', 'fp8', 'fp16', 'fp32']), default='int', help='Data Format')
@ck.option('-f', '--format', type=int, default=0, help='Data format (0: Int | 1: Floating Point)')
@ck.option('-p', '--path', type=str, default='bin', help='Path to output directory. E.g. path/to/bin')
@ck.option('-n', '--numtests', type=int, default=1, help='Number of tests')
@ck.option('-v', '--verbose', is_flag=True)
def main(dim, bound, width, format, path, numtests, verbose):
    # args
    M, N, K = dim

    # need to generate 4x4 weight matrix and 4x4 input matrix (with staggering)
    low, high = bound

    # width to bytes
    numbytes = width // 8 # width must be a multiple of 8

    # extract data format into python formats
    # for now we will support int and fp32
    if format:
        if width == 32:
            data_format = np.float32
        elif width == 16:
            data_format = np.float16
        elif width == 8:
            data_format = np.dtype('float8_e4m3')
        else:
            print("Invalid FP width")
            exit()
    else:
        data_format = int

    print(data_format)

    # seed for random data
    seed = 123123
    # seed = int(np.round(time.time()))

    # loop :)
    for i in range(numtests):
        weight_matrix = random_matrix((low, high), (K, N), data_format, seed)
        seed += 1
        input_matrix = random_matrix((low, high), (M, K), data_format, seed)
        stag_input_matrix = matrix_to_stagger(input_matrix, data_format)

        # verbose print
        if verbose:
            ck.echo('------ Input Act ------')
            ck.echo(input_matrix)
            ck.echo('------ Weights ------')
            ck.echo(weight_matrix)

        # output :)
        # TODO:
        # for fp32 output I believe we can just use the numpy matmul operation on float matrices
        if (data_format == int):
            output_matrix = overflow_matmul_int(input_matrix, weight_matrix, M, N, K, numbytes)
        else:
            output_matrix = np.matmul(input_matrix, weight_matrix)

        # output paths
        common_path = Path(path)
        if not common_path.exists():
            os.mkdir(common_path)

        dir_path = Path(common_path) / f'test_{i}'

        if not dir_path.exists():
            os.mkdir(dir_path)

        golden_path = dir_path / 'output_golden.bin'
        ref_golden_path = dir_path / 'ref_golden.bin'
        input_path = dir_path / 'input_rom.bin'
        weight_path = dir_path / 'weight_rom.bin'

        # else:
        to_bin(str(weight_path), vertical_flip(weight_matrix), K, N, numbytes, data_format)
        to_bin(str(input_path), horizontal_flip(stag_input_matrix), M + K - 1, K, numbytes, data_format)
        to_bin(str(golden_path), horizontal_flip(output_matrix), M, N, numbytes, data_format)
        to_bin(str(ref_golden_path), horizontal_flip(matrix_to_stagger(output_matrix, data_format)), M + N - 1, N, numbytes, data_format)

        seed += 1

if __name__ == '__main__':
    main()
