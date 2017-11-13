/**
 * 
 * Matrix Multiplication - CUDA for GPUs
 *
 * CS3210
 *
 **/
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <assert.h>

#define BLOCK_SIZE 32

int size;

typedef struct
{
	float **element;
} matrix;

long long wall_clock_time()
{
#ifdef __linux__
	struct timespec tp;
	clock_gettime(CLOCK_REALTIME, &tp);
	return (long long)(tp.tv_nsec + (long long)tp.tv_sec * 1000000000ll);
#else
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return (long long)(tv.tv_usec * 1000 + (long long)tv.tv_sec * 1000000000ll);
#endif
}

__device__ float getElement(matrix A, int row, int col) {
    return A.element[row][col];
}

__device__ void setElement(matrix A, int row, int col, float value) {
    A.element[row][col] = value;
}

__device__ matrix getSubMatrix(matrix A, int blockRow, int blockCol) {
    int startingRow = BLOCK_SIZE * blockRow;
    int startingCol = BLOCK_SIZE * blockCol;

    // Allocate memory for sub matrix
    matrix subA;
    float temp[BLOCK_SIZE][BLOCK_SIZE];
    subA.element = temp;
    int row;
    for (row = 0; row < BLOCK_SIZE; row++) {
        // subA.element[row] = (float*)malloc(sizeof(float) * BLOCK_SIZE);
        subA.element[row] = A.element[startingRow + row] + startingCol;
    }

    // int row, col;
    // for (row = 0; row < BLOCK_SIZE; row++) {
    //     subA.element[row] = A.element[startingRow + row] + startingCol;
    //     // for (col = 0; col < BLOCK_SIZE; col++) {
    //     //     printf("%f ", A.element[startingRow + row][startingCol + col]);
    //     // }
    //     // printf("\n");
    // }

    // int i, j;
    // for (i = 0; i < BLOCK_SIZE; i++) {
    //     for (j = 0; j < BLOCK_SIZE; j++) {
    //         printf("%f ", subA.element[i][j]);
    //     }
    //     printf("\n");
    // }
    return subA;
}

/**
 * Allocates memory for a matrix of size SIZE
 * The memory is allocated row-major order, i.e. 
 *  elements from the same row are allocated at contiguous 
 *  memory addresses.
 **/
void allocate_matrix(matrix* m)
{
	int i;
	cudaError_t rc;
	
	// allocate array for all the rows
	rc = cudaMallocManaged((void**)&(m->element), sizeof(float*) * size);
	if (rc != cudaSuccess)
	{
		fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(rc));
		exit(1);
	}
	
	// allocate an array for each row of the matrix
	for (i = 0; i < size; i++)
	{
		rc = cudaMallocManaged((void**)&(m->element[i]), sizeof(float) * size);
		if (rc != cudaSuccess)
		{
			fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(rc));
			exit(1);
		}
	}
}

/**
 * Free the memory allocated for a matrix.
 **/
void free_matrix(matrix* m) {
	int i;
	for (i = 0; i < size; i++)
		cudaFree(m->element[i]);
	cudaFree(m->element);
}

/**
 * Initializes the elements of the matrix with
 * random values between 0 and 9
 **/
void init_matrix(matrix m)
{
	int i, j;
	
	for (i = 0; i < size; i++)
		for (j = 0; j < size; j++)
		{
			m.element[i][j] = rand() % 10;
		}
}

/**
 * Initializes the elements of the matrix with
 * element 0.
 **/
void init_matrix_zero(matrix m)
{
	int i, j;
	
	for (i = 0; i < size; i++)
		for (j = 0; j < size; j++)
		{
			m.element[i][j] = 0.0;
		}
}


/**
 * Multiplies matrix @a with matrix @b storing
 * the result in matrix @result
 * 
 * The multiplication algorithm is the O(n^3) 
 * algorithm
 */
void mm(matrix a, matrix b, matrix result)
{
	int i, j, k;
	
	// Do the multiplication
	for (i = 0; i < size; i++)
		for (j = 0; j < size; j++)
			for(k = 0; k < size; k++)
				result.element[i][j] += a.element[i][k] * b.element[k][j];
}

/**
 * Each kernel computes the result element (i,j).
 */
__global__ void mm_kernel(matrix a, matrix b, matrix result, int size)
{
	// int i = blockIdx.x * blockDim.x + threadIdx.x; 
	// int j = blockIdx.y * blockDim.y + threadIdx.y;
	// int k;

	// if (i >= size || j >= size)
	// 	return;

	// for(k = 0; k < size; k++)
    // 	result.element[i][j] += a.element[i][k] * b.element[k][j];
    
    int blockRow = blockIdx.y;
    int blockCol = blockIdx.x;
    float resultValue = 0;

    // if (blockIdx.x == 1 && blockIdx.y == 1 && threadIdx.x == 0 && threadIdx.y == 0) {
    //     matrix subResult = getSubMatrix(a, blockRow, blockCol);
    //     printf("after getting subResult\n");
    // }

    matrix subResult = getSubMatrix(result, blockRow, blockCol);

    int threadRow = threadIdx.y;
    int threadCol = threadIdx.x;

    int m;

    for (m = 0; m < (size / BLOCK_SIZE); m++) {
        matrix subA = getSubMatrix(a, blockRow, m);
        matrix subB = getSubMatrix(b, m, blockCol);

        __shared__ float sharedA[BLOCK_SIZE][BLOCK_SIZE];
        __shared__ float sharedB[BLOCK_SIZE][BLOCK_SIZE];

        sharedA[threadRow][threadCol] = getElement(subA, threadRow, threadCol);
        sharedB[threadRow][threadCol] = getElement(subB, threadRow, threadCol);

        __syncthreads();

        // int x, y;
        // if (blockIdx.x == 0 && blockIdx.y == 0 && threadRow == 0 && threadCol == 0) {
        //     for (x = 0; x < BLOCK_SIZE; x++) {
        //         for (y = 0; y < BLOCK_SIZE; y++) {
        //             printf("%f ", sharedA[x][y]);
        //         }
        //         printf("\n");
        //     }
        //     for (x = 0; x < BLOCK_SIZE; x++) {
        //         for (y = 0; y < BLOCK_SIZE; y++) {
        //             printf("%f ", sharedB[x][y]);
        //         }
        //         printf("\n");
        //     }
        // }

        int i;
        for (i = 0; i < BLOCK_SIZE; i++) {
            // if (threadIdx.x == 0 && threadIdx.y == 0) {
            //     // printf("sharedA[%d][%d] * sharedB[%d][%d]\n", threadRow, i, i, threadCol);
            //     printf("(A[%d][%d](%f) * B[%d][%d](%f))+", threadRow, i, sharedA[threadRow][i], i, threadCol, sharedB[i][threadCol]);
            // }
            resultValue += sharedA[threadRow][i] * sharedB[i][threadCol];
            // if (blockIdx.x == 0 && blockIdx.y == 0 && threadRow == 0 && threadCol == 0) {
            //     printf("result: %f\n", resultValue);
            // }
        }

        __syncthreads();
    }

    // printf("%f ", resultValue);
    setElement(subResult, threadRow, threadCol, resultValue);
}

void print_matrix(matrix m)
{
	int i, j;
	
	for (i = 0; i < size; i++)
	{
		printf("row %4d: ", i);
		for (j = 0; j < size; j++)
			printf("%6.2f  ", m.element[i][j]);
		printf("\n");
	}
}



void work()
{
	matrix a, b, result1, result2;
	long long before, after;
	int correct, i, j, dim;
	cudaError_t rc;

	// Allocate memory for matrices
	allocate_matrix(&a);
	allocate_matrix(&b);
	allocate_matrix(&result1);
    allocate_matrix(&result2);

	// Initialize matrix elements
	init_matrix(a);
    init_matrix(b);
    // print_matrix(a);
    // printf("\n");
    // print_matrix(b);
    // printf("\n");

	// Perform sequential matrix multiplication
	before = wall_clock_time();
	mm(a, b, result1);
	after = wall_clock_time();
        fprintf(stderr, "Matrix multiplication on CPU took %1.2f seconds\n", ((float)(after - before))/1000000000);
    // print_matrix(result1);

	// Perform CUDA matrix  multiplication
	dim3 block(BLOCK_SIZE, BLOCK_SIZE);			// a block of 32 x 32 CUDA threads
	dim = (size % BLOCK_SIZE == 0) ? size / BLOCK_SIZE : size / BLOCK_SIZE + 1; 
	dim3 grid(dim, dim);	// a grid of CUDA thread blocks
	before = wall_clock_time();
	mm_kernel<<<grid, block>>>(a, b, result2, size);
	cudaDeviceSynchronize();
	after = wall_clock_time();
	fprintf(stderr, "Matrix multiplication on GPU took %1.2f seconds\n", ((float)(after - before))/1000000000);
    // print_matrix(result2);

	// was there any error?
        rc = cudaGetLastError();
        if (rc != cudaSuccess)
                printf("Last CUDA error %s\n", cudaGetErrorString(rc));

	// Compare the results
	correct = 1;
	for (i = 0; correct && i < size; i++)
		for (j = 0; j < size; j++)
			if (result1.element[i][j] != result2.element[i][j]) {
                printf("correct: %f, actual: %f\n", result1.element[i][j], result2.element[i][j]);
				correct = 0;
				break;
			}

	if (correct)
		printf("The result matrices are identical!\n");
	else
		printf("Difference in result matrices at element (%d, %d)!\n", i, j);

	free_matrix(&a);
	free_matrix(&b);
	free_matrix(&result1);
	free_matrix(&result2);
}


int main(int argc, char ** argv)
{
	srand(0); 

	printf("Usage: %s <size>\n", argv[0]);
    
	if (argc >= 2)
		size = atoi(argv[1]);
	else
		size = 1024;
		
	fprintf(stderr,"Sequential matrix multiplication of size %d\n", size);
    
	// Multiply the matrices
	work();

	return 0;
}
