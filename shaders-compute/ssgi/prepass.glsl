#version 430

layout(local_size_x = 16, local_size_y = 16) in;

layout(rgba32f, binding = 0) uniform image2D outputDepthTexture;
layout(rgba32f, binding = 1) uniform image2D globalHistoryTexture0;
layout(rgba32f, binding = 2) uniform image2D globalHistoryTexture1;
layout(rgba32f, binding = 3) uniform image2D globalNormalDepthTexture;
layout(rgba32f, binding = 4) uniform image2D globalFrameUniformsTexture;

#include<ssgi/de.glsl>

void main()
{
	vec2 jitter = 0.375 - vec2(vec4(0.0, 0.5, 0.25, 0.75)[iFrame & 3], vec4(0.25, 0.0, 0.75, 0.5)[iFrame & 3]);
	vec2 resolution = vec2(imageSize(outputDepthTexture).xy);
	vec2 pixelCoordinates = vec2(gl_GlobalInvocationID.xy) + 0.5 + jitter;
	
	vec2 sensor = Camera.FOV / resolution.y * (2.0 * pixelCoordinates - resolution);
	
	mat3 view = mat3(Camera.dirx, Camera.diry, Camera.dirz);
	vec3 rd = normalize(view * vec3(sensor.x, -sensor.y, 1.0));
	vec3 ro = Camera.position;
	
	float minDt = Camera.FOV / resolution.y * 1.42;
	
	float t = 0.0;
	for (uint i = 0; i < 128; i++)
	{
		float d = de_scene(ro + t * rd);
		if (d < t * minDt || t > 100.0)
		{
			t -= t * minDt;
			break;
		}
		t += d * 0.99;
	}
	
	imageStore(outputDepthTexture, ivec2(gl_GlobalInvocationID.xy), vec4(t));
}