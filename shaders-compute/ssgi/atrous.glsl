#version 430

layout(local_size_x = 16, local_size_y = 16) in;

layout(rgba32f, binding = 0) uniform image2D inputColorTexture;
layout(rgba32f, binding = 1) uniform image2D outputColorTexture;
layout(rgba32f, binding = 2) uniform image2D globalHistoryTexture0;
layout(rgba32f, binding = 3) uniform image2D globalHistoryTexture1;
layout(rgba32f, binding = 4) uniform image2D globalNormalDepthTexture;
layout(rgba32f, binding = 5) uniform image2D globalFrameUniformsTexture;

#include<vdb/uniforms.glsl>

float depthMissatch(float t0, float t1, float allowance)
{
	return clamp(2.0 * abs(t0 / (t0 + t1) - 0.5) / allowance, 0.0, 1.0);
}

void main()
{
	vec4 baseNormDepth = imageLoad(globalNormalDepthTexture, ivec2(gl_GlobalInvocationID.xy));
	
	float baseDepth = baseNormDepth.w;
	vec3 baseNorm = baseNormDepth.xyz;
	
	if (baseDepth <= 100.0)
	{
		vec4 baseColOffset = imageLoad(inputColorTexture, ivec2(gl_GlobalInvocationID.xy));
		
		vec3 baseCol = baseColOffset.xyz;
		uint logOffset = uint(round(baseColOffset.w));
		
		vec3 colSum = baseColOffset.xyz;
		float weightSum = 1.0;
		
		for (int y = -1; y < 2; y++)
		{
			for (int x = -1; x < 2; x++)
			{
				if (x != 0 || y != 0)
				{
					ivec2 pixel = ivec2(gl_GlobalInvocationID.xy) + (ivec2(x, y) << logOffset);
					vec3 col = imageLoad(inputColorTexture, pixel).xyz;
					vec4 normDepth = imageLoad(globalNormalDepthTexture, pixel);
					
					float depth = normDepth.w;
					vec3 norm = normDepth.xyz;
					
					float weight = 	exp(-10.0 * depthMissatch(depth, baseDepth, 0.1)) * 
									exp(-5.0 * length(norm - baseNorm));
					
					colSum += weight * col;
					weightSum += weight;
				}
			}
		}
	
		imageStore(outputColorTexture, ivec2(gl_GlobalInvocationID.xy), vec4(colSum / weightSum, float(logOffset + 1)));
	}
}