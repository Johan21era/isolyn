#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "EvaluationShaderSource.hpp"
#include "BatchValidation.hpp"
#include "IsolynAccelerator.hpp"

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace isolyn::accelerator {
namespace {

constexpr std::size_t kMaxBatchSize = 65536;

struct EvalParams {
    std::uint32_t positionCount;
    std::uint32_t playerCount;
    std::uint32_t componentCount;
};

struct EvalPositionParams {
    std::uint32_t positionCount;
    std::uint32_t playerCount;
};

class MetalBackend final : public Backend {
public:
    MetalBackend() noexcept {
        @autoreleasepool {
            m_device = MTLCreateSystemDefaultDevice();
            if (m_device == nil) return;

            m_queue = [m_device newCommandQueue];
            if (m_queue == nil) return;

            NSError* error = nil;
            id<MTLLibrary> library = [m_device
                newLibraryWithSource:[NSString stringWithUTF8String:detail::kEvaluationShaderSource]
                             options:nil
                               error:&error];
            if (library == nil) return;

            id<MTLFunction> genericFunction =
                [library newFunctionWithName:@"isolyn_evaluate_batch"];
            if (genericFunction != nil) {
                m_pipeline = [m_device newComputePipelineStateWithFunction:genericFunction
                                                                     error:&error];
            }

            id<MTLFunction> positionFunction =
                [library newFunctionWithName:@"isolyn_evaluate_positions"];
            if (positionFunction != nil) {
                m_positionPipeline = [m_device newComputePipelineStateWithFunction:positionFunction
                                                                             error:&error];
            }

            m_available = (m_pipeline != nil) || (m_positionPipeline != nil);
        }
    }

    Capabilities capabilities() const noexcept override {
        if (!m_available) return {};
        return Capabilities{true, static_cast<bool>([m_device hasUnifiedMemory]),
                            kMaxBatchSize, "Apple Metal"};
    }

    bool evaluate(const BatchView& batch) noexcept override {
        if (m_pipeline == nil || !detail::isValidBatch(batch, kMaxBatchSize)) return false;

        @autoreleasepool {
            const std::size_t componentCount = batch.featureCount / batch.playerCount;
            const std::size_t featureCount = batch.positionCount * batch.featureCount;
            const std::size_t valueCount = batch.positionCount * batch.playerCount;
            const std::size_t featureBytes = featureCount * sizeof(float);
            const std::size_t valueBytes = valueCount * sizeof(float);

            if (featureBytes > [m_device maxBufferLength] ||
                valueBytes > [m_device maxBufferLength]) {
                return false;
            }

            if (!ensureBuffer(m_featureBuffer, m_featureCapacity, featureBytes) ||
                !ensureBuffer(m_valueBuffer, m_valueCapacity, valueBytes)) {
                return false;
            }
            std::memcpy(m_featureBuffer.contents, batch.features, featureBytes);

            EvalParams params{static_cast<std::uint32_t>(batch.positionCount),
                              static_cast<std::uint32_t>(batch.playerCount),
                              static_cast<std::uint32_t>(componentCount)};

            id<MTLCommandBuffer> commandBuffer = [m_queue commandBuffer];
            if (commandBuffer == nil) return false;

            id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
            if (encoder == nil) return false;

            [encoder setComputePipelineState:m_pipeline];
            [encoder setBuffer:m_featureBuffer offset:0 atIndex:0];
            [encoder setBuffer:m_valueBuffer offset:0 atIndex:1];
            [encoder setBytes:&params length:sizeof(params) atIndex:2];

            const NSUInteger totalThreads = static_cast<NSUInteger>(valueCount);
            const NSUInteger threadWidth = m_pipeline.threadExecutionWidth;
            const NSUInteger threadsPerGroup = threadWidth == 0 ? 32 : threadWidth;
            [encoder dispatchThreads:MTLSizeMake(totalThreads, 1, 1)
                threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
            [encoder endEncoding];
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];

            if (commandBuffer.status != MTLCommandBufferStatusCompleted ||
                commandBuffer.error != nil) {
                return false;
            }

            std::memcpy(batch.values, m_valueBuffer.contents, valueBytes);
        }
        return true;
    }

    bool evaluatePositions(const PositionBatchView& batch) noexcept override {
        if (m_positionPipeline == nil || batch.positions == nullptr ||
            batch.values == nullptr || batch.positionCount == 0 ||
            batch.playerCount < 2 || batch.playerCount > 4 ||
            batch.positionCount > kMaxBatchSize) {
            return false;
        }

        @autoreleasepool {
            const std::size_t positionBytes = batch.positionCount * sizeof(PositionRow);
            const std::size_t valueCount = batch.positionCount * batch.playerCount;
            const std::size_t valueBytes = valueCount * sizeof(float);

            if (positionBytes > [m_device maxBufferLength] ||
                valueBytes > [m_device maxBufferLength]) {
                return false;
            }

            if (!ensureBuffer(m_positionBuffer, m_positionCapacity, positionBytes) ||
                !ensureBuffer(m_positionValueBuffer, m_positionValueCapacity, valueBytes)) {
                return false;
            }
            std::memcpy(m_positionBuffer.contents, batch.positions, positionBytes);

            EvalPositionParams params{static_cast<std::uint32_t>(batch.positionCount),
                                      static_cast<std::uint32_t>(batch.playerCount)};

            id<MTLCommandBuffer> commandBuffer = [m_queue commandBuffer];
            if (commandBuffer == nil) return false;

            id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
            if (encoder == nil) return false;

            [encoder setComputePipelineState:m_positionPipeline];
            [encoder setBuffer:m_positionBuffer offset:0 atIndex:0];
            [encoder setBuffer:m_positionValueBuffer offset:0 atIndex:1];
            [encoder setBytes:&params length:sizeof(params) atIndex:2];

            const NSUInteger totalThreads = static_cast<NSUInteger>(batch.positionCount);
            const NSUInteger threadWidth = m_positionPipeline.threadExecutionWidth;
            const NSUInteger threadsPerGroup = threadWidth == 0 ? 32 : threadWidth;
            [encoder dispatchThreads:MTLSizeMake(totalThreads, 1, 1)
                threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
            [encoder endEncoding];
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];

            if (commandBuffer.status != MTLCommandBufferStatusCompleted ||
                commandBuffer.error != nil) {
                return false;
            }

            std::memcpy(batch.values, m_positionValueBuffer.contents, valueBytes);
        }
        return true;
    }

private:
    bool ensureBuffer(__strong id<MTLBuffer>& buffer,
                      std::size_t& capacity,
                      std::size_t bytes) {
        if (buffer != nil && capacity >= bytes) return true;
        id<MTLBuffer> next = [m_device newBufferWithLength:bytes
                                                    options:MTLResourceStorageModeShared];
        if (next == nil) return false;
        buffer = next;
        capacity = bytes;
        return true;
    }

    id<MTLDevice> m_device = nil;
    id<MTLCommandQueue> m_queue = nil;
    id<MTLComputePipelineState> m_pipeline = nil;
    id<MTLComputePipelineState> m_positionPipeline = nil;
    id<MTLBuffer> m_featureBuffer = nil;
    id<MTLBuffer> m_valueBuffer = nil;
    id<MTLBuffer> m_positionBuffer = nil;
    id<MTLBuffer> m_positionValueBuffer = nil;
    std::size_t m_featureCapacity = 0;
    std::size_t m_valueCapacity = 0;
    std::size_t m_positionCapacity = 0;
    std::size_t m_positionValueCapacity = 0;
    bool m_available = false;
};

} // namespace

Backend* metalBackend() noexcept {
    static MetalBackend backend;
    return backend.capabilities().available ? &backend : nullptr;
}

} // namespace isolyn::accelerator
