import click as ck
import numpy as np

from ml_dtypes import float8_e4m3
from pathlib import Path
from util import *

@ck.command()
@ck.option('-d', '--dim', type=(int, int, int), help='Matrix Array Dimensions (M, K, N): (M,K) * (K,N) = (M,N)')
@ck.option('-a', '--array', type=(int, int), help='Systolic Array Dimensions (K, N)')
@ck.option('-w', '--width', type=int, default=8, help='Data width in bits')
@ck.option('-f', '--format', type=int, default=0, help='Data format (0: Int | 1: Floating Point)')
@ck.option('-p', '--path', type=str, default='bin', help='Path to output directory. E.g. path/to/bin')
@ck.option('-n', '--numtests', type=int, default=1, help='Number of tests')
@ck.option('-v', '--verbose', is_flag=True)
def main(dim, array, width, format, path, numtests, verbose):
    # args
    M, K, N = dim
    arr_rows, arr_cols = array

    numbytes = width // 8

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
            print("Data format not yet supported... Come back later :)")
            exit()
    else:
        data_format = int 

    print(data_format)

    # summarize all results to single output
    f = open('verif_summary.log', 'w')
    result = ''
    num_passed = 0
    passed = False

    for i in range(numtests):

        dir_path = Path(path) / f'test_{i}'

        if not dir_path.exists():
            print(f'[ERROR]: Results does not exist on path: {dir_path}')
            result += f'Test {i}: UNSUCCESFUL\n'
            continue

        # check systolic array's output matrix :)
        golden_path = dir_path / 'output_golden.bin'
        if golden_path.exists():
            golden_act = read_golden(str(golden_path), M, N, numbytes, data_format)
            if verbose:
                ck.echo("--- Golden Reference ---")
                ck.echo(golden_act)

        output_path = dir_path / 'output_mem.bin'
        if output_path.exists():
            output_act = read_output_mem(str(output_path), M, N, arr_rows, arr_cols, numbytes, data_format)
            if verbose:
                ck.echo("----- DUT Output -----")
                ck.echo(output_act)
        else:
            ck.echo('[ERROR]: No DUT Output Found')
            exit()

        # allclose default tolerance is atol=1e-8, rtol=1e-5, we might need more precision?
        # NOTE:
        #   We actually need distinct tolerances based on the data format: FP32 is quite accurate
        #   but FP16 is not... In fact, I am getting 1e-2 discrepancies :o
        rtol = 0.05
        # atol = 0.01
        if np.allclose(golden_act, output_act, rtol):
            if verbose:
                ck.echo('====================')
                ck.echo('====== PASSED ======')
                ck.echo('====================')
            passed = True
            num_passed += 1
        else:
            if verbose:
                ck.echo('====================')
                ck.echo('====== FAILED ======')
                ck.echo('====================')
        
        if passed:
            result += f'Test {i}: PASSED\n'
        else:
            result += f'Test {i}: FAILED\n'

    # print summary and individual results
    f.write(f'----- Summary -----\n')
    f.write(f'Total Tests: {numtests}\n')
    f.write(f'Passed Tests: {num_passed}\n')
    f.write(f'Completion: {(float(num_passed)/numtests)*100 :.1f}%\n')
    f.write(f'\n----- Results -----\n')
    f.write(result)

if __name__ == '__main__':
    main()