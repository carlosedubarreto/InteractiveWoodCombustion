#include "advection.cuh"
__device__ float min8f(float a, float b, float c, float d, float e, float f, float g, float h){
    return fminf(fminf(fminf(a,b), fminf(c,d)),fminf(fminf(e,f),fminf(g,h)));
}
__device__ float max8f(float a, float b, float c, float d, float e, float f, float g, float h){
    return fmaxf(fmaxf(fmaxf(a,b), fmaxf(c,d)),fmaxf(fmaxf(e,f),fmaxf(g,h)));
}
__device__ float clampf(float x, float m, float M){
    if(x < m) return m;
    if(x > M) return M;    
    return x;
}
__device__ float3 min8f3(float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h){
    return make_float3(
        min8f(a.x,b.x,c.x,d.x,e.x,f.x,g.x,h.x),
        min8f(a.y,b.y,c.y,d.y,e.y,f.y,g.y,h.y),
        min8f(a.z,b.z,c.z,d.z,e.z,f.z,g.z,h.z)
    );
}
__device__ float3 max8f3(float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h){
    return make_float3(
        max8f(a.x,b.x,c.x,d.x,e.x,f.x,g.x,h.x),
        max8f(a.y,b.y,c.y,d.y,e.y,f.y,g.y,h.y),
        max8f(a.z,b.z,c.z,d.z,e.z,f.z,g.z,h.z)
    );
}
__device__ float3 clampf3(float3 x, float3 m, float3 M){
    return make_float3(
        clampf(x.x,m.x,M.x),
        clampf(x.y,m.y,M.y),
        clampf(x.z,m.z,M.z)
    );
}

// Advect phi along vel
// Vector 3D MacCormack modified Advection Scheme used to advect velocity
__global__ void macCormackAdvection(float3 * phi, float3 * oldphi, float3 * vel, float3 * predicted){
    const float GRID_SIZE = 1;
    const float BLOCK_SIZE = GRID_SIZE / GRID_COUNT;
    const int k_x = threadIdx.x + blockDim.x * blockIdx.x;
    const int k_y = threadIdx.y + blockDim.y * blockIdx.y;
    const int k_z = threadIdx.z + blockDim.z * blockIdx.z;
    if ((k_x >= dev_Ld[0] ) || (k_y >= dev_Ld[1] ) || (k_z >= dev_Ld[2])) return;
    const int k = flatten(k_x, k_y, k_z);
    const float d = dev_Deltat[0] / BLOCK_SIZE;
    if(k_x == 0 || k_x == GRID_COUNT - 1 || k_y == 0 || k_y == GRID_COUNT - 1 || k_z == 0 || k_z == GRID_COUNT - 1) {
        phi[k] = predicted[k] = make_float3(0,0,0);
        return;
    }
    // Cell centered velocity
    float3 v = {
        0.5f * (vel[k].x + vel[flatten(k_x+1, k_y, k_z)].x),
        0.5f * (vel[k].y + vel[flatten(k_x, k_y+1, k_z)].y),
        0.5f * (vel[k].z + vel[flatten(k_x, k_y, k_z+1)].z)
    };
    // Predictor Step
    predicted[k] = oldphi[k] - d * (v.x * (oldphi[k] - oldphi[flatten(k_x-1, k_y, k_z)]) +
                                    v.y * (oldphi[k] - oldphi[flatten(k_x, k_y-1, k_z)]) +
                                    v.z * (oldphi[k] - oldphi[flatten(k_x, k_y, k_z-1)]) );
    __syncthreads();
    // Corrector Step
    float3 a= 0.5 * (oldphi[k] + predicted[k] - d * (v.x * (predicted[flatten(k_x+1, k_y, k_z)] - predicted[k]) +
                                                     v.y * (predicted[flatten(k_x, k_y+1, k_z)] - predicted[k]) +
                                                     v.z * (predicted[flatten(k_x, k_y, k_z+1)] - predicted[k]) ));
    
    __syncthreads();
    int3 u = {v.x>0 ? -1 : 1, v.y>0 ? -1 : 1, v.z>0 ? -1 : 1};
    float3 m = min8f3(oldphi[flatten(k_x,k_y,k_z)], 
                      oldphi[flatten(k_x+u.x, k_y, k_z)], 
                      oldphi[flatten(k_x, k_y+u.y, k_z)],
                      oldphi[flatten(k_x, k_y, k_z+u.z)],
                      oldphi[flatten(k_x, k_y+u.y, k_z+u.z)],
                      oldphi[flatten(k_x+u.x, k_y, k_z+u.z)],
                      oldphi[flatten(k_x+u.x, k_y+u.y, k_z)],
                      oldphi[flatten(k_x+u.x, k_y+u.y, k_z+u.z)]);
    float3 M = max8f3(oldphi[flatten(k_x,k_y,k_z)], 
                      oldphi[flatten(k_x+u.x, k_y, k_z)], 
                      oldphi[flatten(k_x, k_y+u.y, k_z)],
                      oldphi[flatten(k_x, k_y, k_z+u.z)],
                      oldphi[flatten(k_x, k_y+u.y, k_z+u.z)],
                      oldphi[flatten(k_x+u.x, k_y, k_z+u.z)],
                      oldphi[flatten(k_x+u.x, k_y+u.y, k_z)],
                      oldphi[flatten(k_x+u.x, k_y+u.y, k_z+u.z)]);
    phi[k] = clampf3(a, m, M);
}
void advect(float3 * phi, float3 * oldphi, float3 * vel){
    int NFLAT =  GRID_COUNT * GRID_COUNT * GRID_COUNT;
    const dim3 gridSize(blocksNeeded(GRID_COUNT, M_i.x), 
                        blocksNeeded(GRID_COUNT, M_i.y), 
                        blocksNeeded(GRID_COUNT, M_i.z));
    float3 * predicted;
    HANDLE_ERROR(cudaMalloc(&predicted, NFLAT * sizeof(float3)));
    macCormackAdvection<<<gridSize, M_i>>>(phi, oldphi, vel, predicted);
    HANDLE_ERROR(cudaPeekAtLastError());
    HANDLE_ERROR(cudaDeviceSynchronize());
    HANDLE_ERROR(cudaFree(predicted));
}


// Scalar 3D macCormack modified Advection Scheme
__global__ void macCormackAdvection(float * phi, float * oldphi, float3 * vel, float * predicted, float boundary){
    const float GRID_SIZE = 1;
    const float BLOCK_SIZE = GRID_SIZE / GRID_COUNT;
    const int k_x = threadIdx.x + blockDim.x * blockIdx.x;
    const int k_y = threadIdx.y + blockDim.y * blockIdx.y;
    const int k_z = threadIdx.z + blockDim.z * blockIdx.z;
    if ((k_x >= dev_Ld[0] ) || (k_y >= dev_Ld[1] ) || (k_z >= dev_Ld[2])) return;
    const int k = flatten(k_x, k_y, k_z);
    const float d = dev_Deltat[0] / BLOCK_SIZE;
    if(k_x == 0 || k_x == GRID_COUNT - 1 || k_y == 0 || k_y == GRID_COUNT - 1 || k_z == 0 || k_z == GRID_COUNT - 1) {
        predicted[k] = boundary;
        phi[k] = boundary;
        return;
    }
    __syncthreads();
    // Cell centered velocity
    float3 v = {
        0.5f * (vel[vflatten(k_x,k_y,k_z)].x + vel[vflatten(k_x+1, k_y, k_z)].x),
        0.5f * (vel[vflatten(k_x,k_y,k_z)].y + vel[vflatten(k_x, k_y+1, k_z)].y),
        0.5f * (vel[vflatten(k_x,k_y,k_z)].z + vel[vflatten(k_x, k_y, k_z+1)].z)
    };
    //float3 v = vel[k];
    // Predictor Step
    predicted[k] = oldphi[k] - d * (v.x * (oldphi[k] - oldphi[flatten(k_x-1, k_y, k_z)]) +
                                    v.y * (oldphi[k] - oldphi[flatten(k_x, k_y-1, k_z)]) +
                                    v.z * (oldphi[k] - oldphi[flatten(k_x, k_y, k_z-1)]) );
    __syncthreads();
    // Corrector Step
    float a = 0.5f * (oldphi[k] + predicted[k] - d * (v.x * (predicted[flatten(k_x+1, k_y, k_z)] - predicted[k]) +
                                                      v.y * (predicted[flatten(k_x, k_y+1, k_z)] - predicted[k]) +
                                                      v.z * (predicted[flatten(k_x, k_y, k_z+1)] - predicted[k]) ));
    int3 u = {v.x>0 ? -1 : 1, v.y>0 ? -1 : 1, v.z>0 ? -1 : 1};
    float m = min8f(oldphi[flatten(k_x,k_y,k_z)], 
                    oldphi[flatten(k_x+u.x, k_y, k_z)], 
                    oldphi[flatten(k_x, k_y+u.y, k_z)],
                    oldphi[flatten(k_x, k_y, k_z+u.z)],
                    oldphi[flatten(k_x, k_y+u.y, k_z+u.z)],
                    oldphi[flatten(k_x+u.x, k_y, k_z+u.z)],
                    oldphi[flatten(k_x+u.x, k_y+u.y, k_z)],
                    oldphi[flatten(k_x+u.x, k_y+u.y, k_z+u.z)]);
    float M = max8f(oldphi[flatten(k_x,k_y,k_z)], 
                    oldphi[flatten(k_x+u.x, k_y, k_z)], 
                    oldphi[flatten(k_x, k_y+u.y, k_z)],
                    oldphi[flatten(k_x, k_y, k_z+u.z)],
                    oldphi[flatten(k_x, k_y+u.y, k_z+u.z)],
                    oldphi[flatten(k_x+u.x, k_y, k_z+u.z)],
                    oldphi[flatten(k_x+u.x, k_y+u.y, k_z)],
                    oldphi[flatten(k_x+u.x, k_y+u.y, k_z+u.z)]);
    phi[k] = clampf(a, m, M);
}
void advect(float * phi, float * oldphi, float3 * vel, float boundary){
    int NFLAT =  GRID_COUNT * GRID_COUNT * GRID_COUNT;
    const dim3 gridSize(blocksNeeded(GRID_COUNT, M_i.x), 
                        blocksNeeded(GRID_COUNT, M_i.y), 
                        blocksNeeded(GRID_COUNT, M_i.z));
    float * predicted;
    HANDLE_ERROR(cudaMalloc(&predicted, NFLAT * sizeof(float)));
    macCormackAdvection<<<gridSize, M_i>>>(phi, oldphi, vel, predicted, boundary);
    HANDLE_ERROR(cudaPeekAtLastError());
    HANDLE_ERROR(cudaDeviceSynchronize());
    HANDLE_ERROR(cudaFree(predicted));
}