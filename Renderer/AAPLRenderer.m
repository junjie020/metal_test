/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of a platform independent renderer class, which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
// uses these types as inputs to the shaders.
#import "AAPLShaderTypes.h"

// Main class performing the rendering
@implementation AAPLRenderer
{
    id<MTLDevice> _device;

    // The render pipeline generated from the vertex and fragment shaders in the .metal shader file.
    id<MTLRenderPipelineState> _pipelineState;

    // The command queue used to pass commands to the device.
    id<MTLCommandQueue> _commandQueue;

    // The current size of the view, used as an input to the vertex shader.
    vector_uint2 _viewportSize;
}

void logBindings(NSArray<id<MTLBinding>> *bindings)
{
    for (id<MTLBinding> b in bindings) {
        printf("b.used: %s, [b isUsed]: %s\n", (b.used ? "true" : "false"), ([b isUsed] ? "true" : "false"));
        printf("b.type: %d\n", (int)b.type);
        printf("b.name: %s\n", [b.name UTF8String]);
        printf("b.index: %d\n", (int)b.index);
        printf("b.argument: %s, [b isArgument]: %s\n", b.argument ? "true" : "false", [b isArgument] ? "true" : "false");
        printf("b.access: %d\n", (int)b.access);
        
        printf("==========\n");
    }
}

void logArguments(NSArray<MTLArgument*> *arguments)
{
    for (MTLArgument* a in arguments) {
        printf("a.active: %s, [a isActive]: %s\n", (a.active ? "true" : "false"), ([a isActive] ? "true" : "false"));
        printf("a.type: %d\n", (int)a.type);
        printf("a.name: %s\n", [a.name UTF8String]);
        printf("a.index: %d\n", (int)a.index);
        printf("a.access: %d\n", (int)a.access);
        
        printf("==========\n");
    }

    printf("----********----\n");
}

void processArguments(MTLRenderPipelineReflection* reflection)
{
    //reflection.vertexBindings
    printf("log vertex bindings\n");
    logBindings(reflection.vertexBindings);
    printf("log fragment bindings\n");
    logBindings(reflection.fragmentBindings);

    printf("log vertex arguments\n");
    logArguments(reflection.vertexArguments);
    printf("log fragment argumens\n");
    logArguments(reflection.fragmentArguments);

    printf("cast MTLBinding to MTLArgument\n");
    logArguments((NSArray<MTLArgument*>*)reflection.vertexBindings);
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        // Load all the shader files with a .metal file extension in the project.
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Configure a pipeline descriptor that is used to create a pipeline state.
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Simple Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

        MTLRenderPipelineReflection* _reflection = nil;
        //MTLPipelineOption _options = MTLPipelineOptionArgumentInfo|MTLPipelineOptionBufferTypeInfo;
        MTLPipelineOption _options = MTLPipelineOptionBufferTypeInfo;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 options:_options
                                                            reflection:&_reflection
                                                                 error:&error];
        assert(_reflection);
        processArguments(_reflection);
        // Pipeline State creation could fail if the pipeline descriptor isn't set up properly.
        //  If the Metal API validation is enabled, you can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode.)
        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
    }

    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable to pass to the vertex shader.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Called whenever the view needs to render a frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{
    static const AAPLVertex triangleVertices[] =
    {
        // 2D positions,    RGBA colors
        { {  250,  -250 }, { 1, 0, 0, 1 } },
        { { -250,  -250 }, { 0, 1, 0, 1 } },
        { {    0,   250 }, { 0, 0, 1, 1 } },
    };

    // Create a new command buffer for each render pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    static const AAPLUniformTest uniforms[] = {
        [0] = { .testdata = {1.0, 1.0, 1.0, 1.0}},
        [1] = { .testdata = {2.0, 2.0, 2.0, 1.0}},
    };

    // Obtain a renderPassDescriptor generated from the view's drawable textures.
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder.
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set the region of the drawable to draw into.
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, 0.0, 1.0 }];
        
        [renderEncoder setRenderPipelineState:_pipelineState];

        // Pass in the parameter data.
        [renderEncoder setVertexBytes:triangleVertices
                               length:sizeof(triangleVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];

        [renderEncoder setVertexBytes:uniforms
                                length:sizeof(uniforms)
                                atIndex:AAPLUniformTestData];

        // Draw the triangle.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:3];

        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable.
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    // Finalize rendering here & push the command buffer to the GPU.
    [commandBuffer commit];
}

@end
