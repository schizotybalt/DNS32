/*
CUDA DNS Matrix Multiply: Multiblock Experiment 3
4 * WIDTH blocks each 0.25 * WIDTH-by-WIDTH
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cstring>
#include <math.h>
#include <helper_cuda.h>

#define TILE_WIDTH 8

__global__ void MatMulKernel(float* d_M, float* d_N, float* d_P, int Width) {

	__shared__ float Mds[TILE_WIDTH][TILE_WIDTH];
	__shared__ float Nds[TILE_WIDTH];
	__shared__ float partialSum[TILE_WIDTH][TILE_WIDTH];

	int tx = threadIdx.x, 
		ty = threadIdx.y, 
		bx = (blockIdx.x / 4), 
		bm = blockIdx.x % 4;

	int moffset = (blockIdx.y / 4) * TILE_WIDTH, 
		noffset = (blockIdx.y % 2) * TILE_WIDTH,
		poffset = ((blockIdx.y / 2) % 2) * TILE_WIDTH;

	int mainx = (tx + (2 * bm) + moffset) * Width;
	int mainy = bx + poffset;

	Mds[tx][ty] = d_M[mainx + ty];

	if (tx == 0)
		Nds[ty] = d_N[(ty + noffset) * Width + mainy];
	__syncthreads();

	partialSum[tx][ty] = Mds[tx][ty] * Nds[ty];
	__syncthreads();

	if (ty < 4) 
	{
		partialSum[tx][ty] += partialSum[tx][ty + 4];

		if (ty < 2) {
			partialSum[tx][ty] += partialSum[tx][ty + 2];

			if (ty == 0) 
				//d_P[(tx + 2 * bm) * TILE_WIDTH + bx] = partialSum[tx][ty] 
					atomicAdd(&d_P[mainx + mainy], 
					partialSum[tx][ty]  + partialSum[tx][ty + 1]);
		}
	}
}

void MatrixMultiplication(float* M, float* N, float* P, int Width) {

	int size = Width * Width * sizeof(float);
	float *Md, *Nd, *Pd;

	// Transfer M and N to device memory
	cudaMalloc((void**) &Md, size);
	cudaMemcpy(Md, M, size, cudaMemcpyHostToDevice);
	cudaMalloc((void**) &Nd, size);
	cudaMemcpy(Nd, N, size, cudaMemcpyHostToDevice);

	// Allocate P on the device
	cudaMalloc((void**) &Pd, size);

	int blockfactor = pow(8, (Width / 8) - 1);
	cudaMemset(Pd, 0, size);

	dim3 dimGrid(TILE_WIDTH * 4, 8); //#blocks
	dim3 dimBlock(TILE_WIDTH / 4, TILE_WIDTH); //#threads

	// Launch the device computation threads
	MatMulKernel<<<dimGrid, dimBlock>>>(Md, Nd, Pd, Width);

	// Transfer P from device to host
	cudaMemcpy(P, Pd, size, cudaMemcpyDeviceToHost);

	// Free device matrices
	cudaFree(Md); cudaFree(Nd); cudaFree(Pd);
}

int main(int argc, char* argv[]) {

	int Width = atoi(argv[1]);
	cudaEvent_t start, stop;
	float elapsedTime;

	unsigned int size = Width * Width;
	unsigned int mem_size = size * sizeof(float);

	/*unsigned int size_M = Width * Width;
	unsigned int mem_size_M = size_M * sizeof(float);
	float* hostM = (float*) malloc(mem_size_M);

	unsigned int size_N = Width * Width;
	unsigned int mem_size_N = size_N * sizeof(float);
	float* hostN = (float*) malloc(mem_size_N);

	unsigned int size_P = Width * Width;
	unsigned int mem_size_P = size_P * sizeof(float);
	float* hostP = (float*) malloc(mem_size_P);

	unsigned int size_ref = Width * Width;
	unsigned int mem_size_ref = size_ref * sizeof(float);
	float* ref = (float*) malloc(mem_size_ref);*/

	float* hostM = (float*) malloc(mem_size);
	float* hostN = (float*) malloc(mem_size);
	float* hostP = (float*) malloc(mem_size);
	float* ref = (float*) malloc(mem_size);

	const int filenamelength = 14;

	// file io
	FILE *mat1, *mat2, *ans;
	mat1 = fopen("matrix1.txt", "r");
	for (int i = 0; i < Width; i++){

		for (int j = 0; j < Width; j++){

			fscanf(mat1, "%f", &hostM[i * Width + j]);
			//printf("%f ", hostM[i * Width + j]);
		}	
		//printf("\n");
	}
	fclose(mat1);
	//printf("\n");

	mat2 = fopen("matrix2.txt", "r");
	for (int i = 0; i < Width; i++){

		for (int j = 0; j < Width; j++){

			fscanf(mat2, "%f", &hostN[i * Width + j]);
			//printf("%f ", hostN[i * Width + j]);
		}
		//printf("\n");
	}
	fclose(mat2);
	//printf("\n");

	char productmatfilename[filenamelength];
	strcpy(productmatfilename, argv[1]);
	strcat(productmatfilename, "product.txt");
	ans = fopen(productmatfilename, "r");
	for (int i = 0; i < Width; i++){

		for (int j = 0; j < Width; j++){

			fscanf(ans, "%f", &ref[i * Width + j]);
			//printf("%f ", ref[i * Width + j]);
		}
		//printf("\n");
	}
	fclose(ans);
	//printf("\n");

	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start,0);

	MatrixMultiplication(hostM, hostN, hostP, Width);

	cudaEventRecord(stop,0);
	cudaEventSynchronize(stop);
	cudaEventElapsedTime(&elapsedTime, start, stop);
	printf("Elapsed time: %3.3f us\n", elapsedTime * 1000);
	cudaEventDestroy(start);
	cudaEventDestroy(stop);

	for (int i = 0; i < Width; i++)
		for (int j = 0; j < Width; j++)
			if (abs(ref[i * Width + j] - hostP[i * Width + j]) > 0.05)
				printf("Error, coord[%i][%i]: ref = %f p = %f\n", i, j, 
				ref[i * Width + j], hostP[i * Width + j]);

	// clean up memory
	free(hostM); free(hostN); free(hostP); free(ref);
	return 0;
}
