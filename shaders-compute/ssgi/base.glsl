#version 430

layout(local_size_x = 16, local_size_y = 16) in;

layout(rgba32f, binding = 0) uniform image2D inputDepthTexture;
layout(rgba32f, binding = 1) uniform image2D outputColorTexture;
layout(rgba32f, binding = 2) uniform image2D globalHistoryTexture0;
layout(rgba32f, binding = 3) uniform image2D globalHistoryTexture1;
layout(rgba32f, binding = 4) uniform image2D globalNormalDepthTexture;
layout(rgba32f, binding = 5) uniform image2D globalFrameUniformsTexture;

#include<ssgi/de.glsl>

// from https://www.colour-science.org/apps/
const mat3 linear2acescg = mat3(0.613117812906440, 0.069934082307513, 0.020462992637737, 0.341181995855625, 0.918103037508582, 0.106768663382511, 0.045787344282337, 0.011932775530201, 0.872715910619442);
const mat3 acescg2linear = mat3(1.704887331049501, -0.129520935348888, -0.024127059936902, -0.624157274479026, 1.138399326040076, -0.124620612286390, -0.080886773895704, -0.008779241755018, 1.148822109913262);

vec3 background(vec3 rd)
{
	return mix(linear2acescg * vec3(0.8, 0.7, 0.5), linear2acescg * vec3(0.2, 0.4, 0.8), smoothstep(-1.0, 1.0, rd.y));
}

float depthMatch(float t0, float t1, float allowance)
{
	return clamp(1.0 - 2.0 * abs(t0 / (t0 + t1) - 0.5) / allowance, 0.0, 1.0);
}

vec3 sampleLightBuffer(vec3 p)
{
	vec2 resolution = vec2(imageSize(globalNormalDepthTexture).xy);
	vec3 prevRd = p - PrevCamera.position;
	mat3 prevView = mat3(PrevCamera.dirx, PrevCamera.diry, PrevCamera.dirz);
	vec3 prevViewSpaceRd = prevRd * prevView;
	vec2 prevSensor = vec2(prevViewSpaceRd.x, -prevViewSpaceRd.y) / prevViewSpaceRd.z;
	vec2 prevPixelCoordinates = (prevSensor * resolution.y / PrevCamera.FOV + resolution) * 0.5;
	
	vec4 previous = vec4(0.0);
	if (iFrame > 0)
	{
		if ((iFrame & 1) == 0)
		{
			previous = imageLoad(globalHistoryTexture1, ivec2(prevPixelCoordinates));
		}
		else
		{
			previous = imageLoad(globalHistoryTexture0, ivec2(prevPixelCoordinates));
		}
	}
	
	return depthMatch(previous.w, length(prevRd), 0.1) * previous.xyz;
}

vec3 gi(vec3 p, vec3 n)
{
	vec3 o0 = normalize(abs(n.x) > abs(n.z) ? vec3(-n.y, n.x, 0.0) : vec3(0.0, -n.z, n.y));
	vec3 o1 = cross(n, o0);
	
	uint sampleCount = 2;
	vec3 giSum = vec3(0.0);
	for (uint j = 0; j < sampleCount; j++)
	{
		uint seed = gl_GlobalInvocationID.x * 0x5352eb15u + gl_GlobalInvocationID.y * 0x51a56e3cu + j;
		float f0 = float(seed * 0x63ae952au) / float(~0u);
		float f1 = float(seed * 0x7510058fu) / float(~0u);
		
		float r = sqrt(f0);
		float a = 1000.0 * f1;
		vec3 rd = mat3(o0, o1, n) * vec3(r * cos(a), r * sin(a), sqrt(1.0 - r * r));
		vec3 ro = p;
		
		float t = 0.0;
		float minDt = 0.05;
		float d = 0.0;
		for (uint i = 0; i < 4; i++)
		{
			d = de_scene(ro + t * rd);
			if (d < t * minDt)
			{
				break;
			}
			t += d * 2.0;
		}
		
		if (d >= t * minDt)
		{
			giSum += background(rd);
		}
		else
		{
			giSum += sampleLightBuffer(ro + rd * t);
		}
	}
	
	return giSum / float(sampleCount);
}

void main()
{
	vec2 jitter = 0.375 - vec2(vec4(0.0, 0.5, 0.25, 0.75)[iFrame & 3], vec4(0.25, 0.0, 0.75, 0.5)[iFrame & 3]);
	vec2 resolution = vec2(imageSize(globalNormalDepthTexture).xy);
	vec2 pixelCoordinates = vec2(gl_GlobalInvocationID.xy) + 0.5 + jitter;
	
	vec2 sensor = Camera.FOV / resolution.y * (2.0 * pixelCoordinates - resolution);
	
	mat3 view = mat3(Camera.dirx, Camera.diry, Camera.dirz);
	vec3 rd = normalize(view * vec3(sensor.x, -sensor.y, 1.0));
	vec3 ro = Camera.position;
	
	float t = imageLoad(inputDepthTexture, ivec2(gl_GlobalInvocationID.xy >> 1u)).x;
	
	float minDt = Camera.FOV / resolution.y * 1.42;
	
	for (uint i = 0; i < 256; i++)
	{
		float d = de_scene(ro + t * rd);
		if (d < t * minDt || t > 100.0)
		{
			break;
		}
		t += d * 0.99;
	}
	
	vec3 n = vec3(0.0, 0.0, 1.0);
	vec3 col = vec3(0.0);
	
	if (t <= 100.0)
	{
		vec3 p = ro + rd * t;
		
		if (de_marble(vec4(p, 1.0)) < t * minDt)
		{
			n = normalize(p - iMarblePos);
		}
		else if (de_flag(vec4(p, 1.0)) < t * minDt)
		{
			float d = de_flag(vec4(p, 1.0));
			
			n = normalize(d - vec3(de_flag(vec4(p - vec3(d, 0, 0), 1.0)), de_flag(vec4(p - vec3(0, d, 0), 1.0)), de_flag(vec4(p - vec3(0, 0, d), 1.0))));
		}
		else
		{
		#if 0
			uint absxMask = 0;
			uint absyMask = 0;
			uint abszMask = 0;
			uint dxyMask = 0;
			uint dxzMask = 0;
			uint dyzMask = 0;
			
			float s1 = sin(iFracAng1), c1 = cos(iFracAng1), s2 = sin(iFracAng2), c2 = cos(iFracAng2);
			mat2 rmZ = mat2(c1, s1, -s1, c1);
			mat2 rmX = mat2(c2, s2, -s2, c2);
			for (int i = 0; i < FRACTAL_ITER; i++)
			{
				if (p.x < 0.0) { absxMask |= 1 << i; p.x = -p.x; }
				if (p.y < 0.0) { absyMask |= 1 << i; p.y = -p.y; }
				if (p.z < 0.0) { abszMask |= 1 << i; p.z = -p.z; }
				p.xy *= rmZ;
				if (p.x < p.y) { dxyMask |= 1 << i; p.xy = p.yx; }
				if (p.x < p.z) { dxzMask |= 1 << i; p.xz = p.zx; }
				if (p.y < p.z) { dyzMask |= 1 << i; p.yz = p.zy; }
				p.yz *= rmX;
				p *= iFracScale;
				p += iFracShift;
			}
			
			n = normalize(p - clamp(p, vec3(-6.0), vec3(6.0)));
			
			for (int i = FRACTAL_ITER - 1; i >= 0 ; i--)
			{
				n.yz = rmX * n.yz;
				if ((dyzMask & (1 << i)) != 0) n.yz = n.zy;
				if ((dxzMask & (1 << i)) != 0) n.xz = n.zx;
				if ((dxyMask & (1 << i)) != 0) n.xy = n.yx;
				n.xy = rmZ * n.xy;
				if ((abszMask & (1 << i)) != 0) n.z = -n.z;
				if ((absyMask & (1 << i)) != 0) n.y = -n.y;
				if ((absxMask & (1 << i)) != 0) n.x = -n.x;
			}
			#else
			
			float d = de_fractal(vec4(p, 1.0));
			
			n = normalize(d - vec3(de_fractal(vec4(p - vec3(d, 0, 0), 1.0)), de_fractal(vec4(p - vec3(0, d, 0), 1.0)), de_fractal(vec4(p - vec3(0, 0, d), 1.0))));
			
			#endif
		}
		
		if (any(isnan(n)))
		{
			n = vec3(1.0, 0.0, 0.0);
		}
		
		
		col = gi(p + n * (16.0 * t * minDt), n);
		if (any(isnan(col)))
		{
			col = vec3(0.0);
		}
		
		imageStore(outputColorTexture, ivec2(gl_GlobalInvocationID.xy), vec4(col, 0.0));
	}
	
	imageStore(globalNormalDepthTexture, ivec2(gl_GlobalInvocationID.xy), vec4(n, t));
}