#version 430

layout(local_size_x = 16, local_size_y = 16) in;

layout(rgba32f, binding = 0) uniform image2D inputColorTexture;
layout(rgba32f, binding = 1) uniform image2D outputColorTexture;
layout(rgba32f, binding = 2) uniform image2D globalHistoryTexture0;
layout(rgba32f, binding = 3) uniform image2D globalHistoryTexture1;
layout(rgba32f, binding = 4) uniform image2D globalNormalDepthTexture;
layout(rgba32f, binding = 5) uniform image2D globalFrameUniformsTexture;

#include<ssgi/de.glsl>

float depthMissatch(float t0, float t1, float allowance)
{
	return clamp(2.0 * abs(t0 / (t0 + t1) - 0.5) / allowance, 0.0, 1.0);
}

// from https://www.colour-science.org/apps/
const mat3 linear2acescg = mat3(0.613117812906440, 0.069934082307513, 0.020462992637737, 0.341181995855625, 0.918103037508582, 0.106768663382511, 0.045787344282337, 0.011932775530201, 0.872715910619442);
const mat3 acescg2linear = mat3(1.704887331049501, -0.129520935348888, -0.024127059936902, -0.624157274479026, 1.138399326040076, -0.124620612286390, -0.080886773895704, -0.008779241755018, 1.148822109913262);

vec3 background(vec3 rd)
{
	return mix(linear2acescg * vec3(0.8, 0.7, 0.5), linear2acescg * vec3(0.2, 0.4, 0.8), smoothstep(-1.0, 1.0, rd.y));
}

vec3 directLight(vec3 p, vec3 n)
{
	vec3 rd = LIGHT_DIRECTION;
	vec3 ro = p;
	
	if (dot(n, rd) < 0.0)
	{
		return vec3(0.0);
	}
	
	float t = 0.0;
	float minSinA = 1.0;
	const float cutoff = 0.5;
	for (uint i = 0; i < 64; i++)
	{
		float d = de_scene(ro + t * rd);
		minSinA = min(minSinA, 10.0 * d / t);
		if (minSinA < cutoff || t > 100.0)
		{
			break;
		}
		t += d;
	}
	
	return dot(n, rd) * max((minSinA - cutoff) / (1.0 - cutoff), 0.0) * (linear2acescg * LIGHT_COLOR);
}

void main()
{
	vec2 jitter = 0.375 - vec2(vec4(0.0, 0.5, 0.25, 0.75)[iFrame & 3], vec4(0.25, 0.0, 0.75, 0.5)[iFrame & 3]);
	vec2 resolution = vec2(imageSize(outputColorTexture).xy);
	vec2 pixelCoordinates = vec2(gl_GlobalInvocationID.xy) + 0.5 + jitter;
	
	vec2 sensor = Camera.FOV / resolution.y * (2.0 * pixelCoordinates - resolution);
	
	mat3 view = mat3(Camera.dirx, Camera.diry, Camera.dirz);
	vec3 rd = normalize(view * vec3(sensor.x, -sensor.y, 1.0));
	vec3 ro = Camera.position;
	
	vec4 baseNormDepth = imageLoad(globalNormalDepthTexture, ivec2(gl_GlobalInvocationID.xy));
	vec3 n = baseNormDepth.xyz;
	float t = baseNormDepth.w;
	
	vec3 p = ro + rd * t;
	
	vec3 col = background(rd);
	
	if (t <= 100.0)
	{
		float d = de_scene(p);
		vec3 albedo = linear2acescg * col_scene(p - n * d).xyz;
		float minDt = Camera.FOV / resolution.y * 1.42;
		
		vec3 direct = directLight(p + n * (16.0 * t * minDt - d), n);
		
		vec4 baseColOffset = imageLoad(inputColorTexture, ivec2(gl_GlobalInvocationID.xy));
		vec3 baseCol = baseColOffset.xyz;
		uint logOffset = uint(round(baseColOffset.w));
		float baseDepth = t;
		vec3 baseNorm = n;
		
		vec3 colSum = baseColOffset.xyz;
		float weightSum = 1.0;
		
		for (int y = -3; y < 4; y++)
		{
			for (int x = -3; x < 4; x++)
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
		
		vec3 indirect = colSum / weightSum;
		
		col = albedo * (direct + indirect);
	}
	
	imageStore(outputColorTexture, ivec2(gl_GlobalInvocationID.xy), vec4(clamp(col, vec3(0.0), vec3(100.0)), t));
}