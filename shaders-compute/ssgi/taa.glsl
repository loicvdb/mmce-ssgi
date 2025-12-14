#version 430

layout(local_size_x = 16, local_size_y = 16) in;

layout(rgba32f, binding = 0) uniform image2D inputColorTexture;
layout(rgba8, binding = 1) uniform image2D outputColorTexture;
layout(rgba32f, binding = 2) uniform image2D globalHistoryTexture0;
layout(rgba32f, binding = 3) uniform image2D globalHistoryTexture1;
layout(rgba32f, binding = 4) uniform image2D globalNormalDepthTexture;
layout(rgba32f, binding = 5) uniform image2D globalFrameUniformsTexture;

#include<ssgi/de.glsl>

// from https://www.colour-science.org/apps/
const mat3 linear2acescg = mat3(0.613117812906440, 0.069934082307513, 0.020462992637737, 0.341181995855625, 0.918103037508582, 0.106768663382511, 0.045787344282337, 0.011932775530201, 0.872715910619442);
const mat3 acescg2linear = mat3(1.704887331049501, -0.129520935348888, -0.024127059936902, -0.624157274479026, 1.138399326040076, -0.124620612286390, -0.080886773895704, -0.008779241755018, 1.148822109913262);

vec3 tonemap(vec3 c)
{
    return (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
}

float depthMatch(float t0, float t1, float allowance)
{
	return clamp(1.0 - 2.0 * abs(t0 / (t0 + t1) - 0.5) / allowance, 0.0, 1.0);
}

void main()
{
	vec4 tex = imageLoad(inputColorTexture, ivec2(gl_GlobalInvocationID.xy));
	
	vec4 minTex = tex;
	vec4 maxTex = tex;
	vec4 sumTex = tex;
	ivec2 minDepthPixel = ivec2(gl_GlobalInvocationID.xy);
	float minDepth = tex.w;
	for (int y = -1; y < 2; y++)
	{
		for (int x = -1; x < 2; x++)
		{
			if (x != 0 || y != 0)
			{
				ivec2 depthPixel = clamp(ivec2(gl_GlobalInvocationID.xy) + ivec2(x, y), ivec2(0), ivec2(imageSize(inputColorTexture).xy - 1));
				vec4 ptex = imageLoad(inputColorTexture, depthPixel);
				minTex = min(minTex, ptex);
				maxTex = max(maxTex, ptex);
				sumTex += ptex;
				float depth = ptex.w;
				if (depth < minDepth)
				{
					minDepth = depth;
					minDepthPixel = depthPixel;
				}
			}
		}
	}
	
	vec2 jitter = 0.375 - vec2(vec4(0.0, 0.5, 0.25, 0.75)[iFrame & 3], vec4(0.25, 0.0, 0.75, 0.5)[iFrame & 3]);
	vec2 resolution = vec2(imageSize(globalNormalDepthTexture).xy);
	vec2 pixelCoordinates = vec2(minDepthPixel) + 0.5 + jitter;
	
	vec2 sensor = Camera.FOV / resolution.y * (2.0 * pixelCoordinates - resolution);
	
	mat3 view = mat3(Camera.dirx, Camera.diry, Camera.dirz);
	vec3 rd = normalize(view * vec3(sensor.x, -sensor.y, 1.0));
	vec3 ro = Camera.position;
	
	float minDt = Camera.FOV / resolution.y * 1.42;
	float t = minDepth;
	vec3 p = ro + rd * t;
	
	vec3 currentP = p;
	
	uint absxMask = 0;
	uint absyMask = 0;
	uint abszMask = 0;
	uint dxyMask = 0;
	uint dxzMask = 0;
	uint dyzMask = 0;
	
	{
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
	}
	
	bool onFractal = de_box(vec4(p, pow(iFracScale, float(FRACTAL_ITER))), vec3(6.0)) < t * minDt;
	
	vec4 prevFractalSettings = imageLoad(globalFrameUniformsTexture, ivec2(iFrame & 1, 0));
	vec3 prevIMarblePos = imageLoad(globalFrameUniformsTexture, ivec2(iFrame & 1, 1)).xyz;
	
	if (gl_GlobalInvocationID.xy == uvec2(0, 0))
	{
		imageStore(globalFrameUniformsTexture, ivec2(~iFrame & 1, 0), vec4(iFracAng1, iFracAng2, iFracShift.y, 0.0));
		imageStore(globalFrameUniformsTexture, ivec2(~iFrame & 1, 1), vec4(iMarblePos, 0.0));
	}
	
	{
		float prevIFractAng1 = prevFractalSettings.x;
		float prevIFractAng2 = prevFractalSettings.y;
		vec3 prevIFracShift = vec3(iFracShift.x, prevFractalSettings.z, iFracShift.z);
		float s1 = sin(prevIFractAng1), c1 = cos(prevIFractAng1), s2 = sin(prevIFractAng2), c2 = cos(prevIFractAng2);
		mat2 rmZ = mat2(c1, s1, -s1, c1);
		mat2 rmX = mat2(c2, s2, -s2, c2);
		for (int i = FRACTAL_ITER - 1; i >= 0 ; i--)
		{
			p -= prevIFracShift;
			p /= iFracScale;
			p.yz = rmX * p.yz;
			if ((dyzMask & (1 << i)) != 0) p.yz = p.zy;
			if ((dxzMask & (1 << i)) != 0) p.xz = p.zx;
			if ((dxyMask & (1 << i)) != 0) p.xy = p.yx;
			p.xy = rmZ * p.xy;
			if ((abszMask & (1 << i)) != 0) p.z = -p.z;
			if ((absyMask & (1 << i)) != 0) p.y = -p.y;
			if ((absxMask & (1 << i)) != 0) p.x = -p.x;
		}
	}
	
	vec3 prevPFractal = p;
	vec3 prevPMarble = currentP + prevIMarblePos - iMarblePos;
	
	bool onMarble = de_marble(vec4(currentP, 1.0)) < t * minDt;
	
	vec3 prevP = onMarble ? prevPMarble : onFractal ? prevPFractal : currentP;
	vec3 prevRd = prevP - PrevCamera.position;
	mat3 prevView = mat3(PrevCamera.dirx, PrevCamera.diry, PrevCamera.dirz);
	vec3 prevViewSpaceRd = prevRd * prevView;
	vec2 prevSensor = vec2(prevViewSpaceRd.x, -prevViewSpaceRd.y) / prevViewSpaceRd.z;
	vec2 prevPixelCoordinates = (prevSensor * resolution.y / PrevCamera.FOV + resolution) * 0.5 + vec2(gl_GlobalInvocationID.xy) - vec2(minDepthPixel);
	
	vec4 previous = vec4(0.0);
	if (iFrame > 0)
	{
		vec4 previousMM = vec4(0.0);
		vec4 previousPM = vec4(0.0);
		vec4 previousMP = vec4(0.0);
		vec4 previousPP = vec4(0.0);
		ivec2 hp = ivec2(floor(prevPixelCoordinates - 0.5));
		if ((iFrame & 1) == 0)
		{
			previousMM = imageLoad(globalHistoryTexture1, hp + ivec2(+0, +0));
			previousPM = imageLoad(globalHistoryTexture1, hp + ivec2(+1, +0));
			previousMP = imageLoad(globalHistoryTexture1, hp + ivec2(+0, +1));
			previousPP = imageLoad(globalHistoryTexture1, hp + ivec2(+1, +1));
		}
		else
		{
			previousMM = imageLoad(globalHistoryTexture0, hp + ivec2(+0, +0));
			previousPM = imageLoad(globalHistoryTexture0, hp + ivec2(+1, +0));
			previousMP = imageLoad(globalHistoryTexture0, hp + ivec2(+0, +1));
			previousPP = imageLoad(globalHistoryTexture0, hp + ivec2(+1, +1));
		}
		vec2 f = fract(prevPixelCoordinates - 0.5);
		previous = mix(mix(previousMM, previousPM, f.x), mix(previousMP, previousPP, f.x), f.y);
	}
	
	vec4 col = mix(tex, sumTex / 9.0, depthMatch(minTex.w, maxTex.w, 0.1));
	if (previous.w > minTex.w * 0.99 && previous.w < maxTex.w * 1.01)
	{
		col = mix(tex, clamp(previous, minTex, maxTex), 0.8);
	}
	
	//col = tex;
	
	if ((iFrame & 1) == 0)
	{
		imageStore(globalHistoryTexture0, ivec2(gl_GlobalInvocationID.xy), col);
	}
	else
	{
		imageStore(globalHistoryTexture1, ivec2(gl_GlobalInvocationID.xy), col);
	}
	
	vec3 c = tonemap(max(acescg2linear * col.xyz, vec3(0.0)));
	//vec3 c = 0.5 + 0.5 * imageLoad(globalNormalDepthTexture, ivec2(gl_GlobalInvocationID.xy)).xyz;
	
	imageStore(outputColorTexture, ivec2(gl_GlobalInvocationID.xy), vec4(c, 1.0));
	
}