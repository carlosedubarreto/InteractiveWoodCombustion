#include "physics.h"
//#include <GL/glew.h>//teste
//#include <GL/glut.h>//teste
//#include <GL/glu.h>//teste
extern GPUAnim2dTex* testGPUAnim2dTex;

Physics::Physics(){  
    dev_L3.x = static_cast<unsigned int>(GRID_COUNT);
    dev_L3.y = static_cast<unsigned int>(GRID_COUNT);
    dev_L3.z = static_cast<unsigned int>(GRID_COUNT);
    dev_grid3d = new dev_Grid3d (dev_L3);
    // physics
    constexpr std::array<int,3> LdS {GRID_COUNT, GRID_COUNT, GRID_COUNT };
    constexpr std::array<float,3> ldS {1.f, 1.f, 1.f };
    HANDLE_ERROR(
        cudaMemcpyToSymbol( dev_Deltat, Deltat, sizeof(float)*1,0) );
    HANDLE_ERROR(
        cudaMemcpyToSymbol( dev_heat_params, heat_params, sizeof(float)*2,0,cudaMemcpyHostToDevice) );
    const int Ld_to_const[3] { LdS[0], LdS[1], LdS[2] } ;
    HANDLE_ERROR(
        cudaMemcpyToSymbol( dev_Ld, Ld_to_const, sizeof(int)*3,0,cudaMemcpyHostToDevice) );
    
    grid3d = new Grid3d( LdS, ldS);
    
    const float hds[3] { grid3d->hd[0], grid3d->hd[1], grid3d->hd[2] } ;
    
    // sanity check
    //std::cout << " hds : .x : " << hds[0] << " .y : " << hds[1] << " .z : " << hds[2] << std::endl;
    
//	set1DerivativeParameters(hds);
    set2DerivativeParameters(hds);
//	set3DerivativeParameters(hds);
//	set4DerivativeParameters(hds);
    
    this->reset();
    
    testGPUAnim2dTex->initPixelBuffer();

    glGenBuffers(1, &smokeColorBufferObj);
    glBindBuffer(GL_ARRAY_BUFFER, smokeColorBufferObj);
    
    glBufferData(GL_ARRAY_BUFFER, pow(GRID_COUNT,3)*4*4*sizeof(GLubyte), 0, GL_STREAM_DRAW);
    cudaGLRegisterBufferObject(smokeColorBufferObj);
    initSmokeQuads();

}
Physics::~Physics() {
    delete dev_grid3d;
    delete grid3d;
    if (smokeColorBufferObj) {
        cudaGLUnregisterBufferObject(smokeColorBufferObj);
        glDeleteBuffers(1, &smokeColorBufferObj);
    }
}
void Physics::update() {
    
    uchar4 *d_out = 0;
    cudaGLMapBufferObject((void **)&d_out, smokeColorBufferObj);
    if(activeBuffer)
        kernelLauncher(d_out, 
                       dev_grid3d->dev_temperature0,
                       dev_grid3d->dev_temperature1,
                       dev_grid3d->dev_velocity0,
                       dev_grid3d->dev_velocity1,
                       dev_grid3d->dev_pressure,
                       dev_grid3d->dev_ccvelocity,
                       dev_grid3d->dev_vorticity,
                       dev_grid3d->dev_smokeDensity0,
                       dev_grid3d->dev_smokeDensity1,
                       dev_grid3d->dev_smokeVoxelRadiance,
                       externalForce,
                       sourcesEnabled,
                       activeBuffer,
                       dev_L3, bc, M_i, slice );
    else
        kernelLauncher(d_out, 
                       dev_grid3d->dev_temperature1,
                       dev_grid3d->dev_temperature0,
                       dev_grid3d->dev_velocity1,
                       dev_grid3d->dev_velocity0,
                       dev_grid3d->dev_pressure,
                       dev_grid3d->dev_ccvelocity,
                       dev_grid3d->dev_vorticity,
                       dev_grid3d->dev_smokeDensity1,
                       dev_grid3d->dev_smokeDensity0,
                       dev_grid3d->dev_smokeVoxelRadiance,
                       externalForce,
                       sourcesEnabled,
                       activeBuffer,
                       dev_L3, bc, M_i, slice );

    cudaGLUnmapBufferObject(smokeColorBufferObj);    
    activeBuffer = !activeBuffer;
}

void Physics::reset(){
    resetVariables(dev_grid3d->dev_temperature0,
                   dev_grid3d->dev_temperature1,
                   dev_grid3d->dev_velocity0,
                   dev_grid3d->dev_velocity1,
                   dev_grid3d->dev_smokeDensity0,
                   dev_grid3d->dev_smokeDensity1,
                   dev_grid3d->dev_pressure,
                   dev_L3, bc, M_i);
    this->externalForce = make_float3(0,0,0);
}

void Physics::addExternalForce(float3 f){
    this->externalForce.x += f.x;
    this->externalForce.y += f.y;
    this->externalForce.z += f.z;
}