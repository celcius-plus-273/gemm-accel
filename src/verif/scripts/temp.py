from util import *
from data_gen import overflow_matmul_int

# Generate ib matrix and wb matrix
ib_matrix = random_matrix((-16, 16), (4, 4), int, seed=1)
wb_matrix = random_matrix((-16, 16), (4, 4), int, seed=1)
ob_matrix = overflow_matmul_int(ib_matrix, wb_matrix, 4, 4, 4, 1)

print(ib_matrix)
print(wb_matrix)
print(ob_matrix)
