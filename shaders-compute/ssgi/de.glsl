#include<vdb/uniforms.glsl>

///Original MM distance estimators

float de_sphere(vec4 p, float r) {
	return (length(p.xyz) - r) / p.w;
}

float de_box(vec4 p, vec3 s) {
	vec3 a = abs(p.xyz) - s;
	return (min(max(max(a.x, a.y), a.z), 0.0) + length(max(a, 0.0))) / p.w;
}

float de_capsule(vec4 p, float h, float r) {
	p.y -= clamp(p.y, -h, h);
	return (length(p.xyz) - r) / p.w;
}

float de_fractal(vec4 p)
{
	float s1 = sin(iFracAng1), c1 = cos(iFracAng1), s2 = sin(iFracAng2), c2 = cos(iFracAng2);
	mat2 rmZ = mat2(c1, s1, -s1, c1);
	mat2 rmX = mat2(c2, s2, -s2, c2);
	
	#if 0
	
	for (int i = 0; i < FRACTAL_ITER; i++)
	{
		p.xyz = abs(p.xyz);
		p.xy *= rmZ;
		if (p.x < p.y) p.xy = p.yx;
		if (p.x < p.z) p.xz = p.zx;
		if (p.y < p.z) p.yz = p.zy;
		p.yz *= rmX;
		p *= iFracScale;
		p.xyz += iFracShift;
	}
	
	#else
	
	// (ab)using loop unrolling to get more perf
	
	uint iterationsLeft = FRACTAL_ITER;
	
	if (iterationsLeft >= 16)
	{
		for (int i = 0; i < 16; i++)
		{
			p.xyz = abs(p.xyz);
			p.xy *= rmZ;
			if (p.x < p.y) p.xy = p.yx;
			if (p.x < p.z) p.xz = p.zx;
			if (p.y < p.z) p.yz = p.zy;
			p.yz *= rmX;
			p *= iFracScale;
			p.xyz += iFracShift;
		}
		
		iterationsLeft -= 16;
	}
	
	if (iterationsLeft >= 8)
	{
		for (int i = 0; i < 8; i++)
		{
			p.xyz = abs(p.xyz);
			p.xy *= rmZ;
			if (p.x < p.y) p.xy = p.yx;
			if (p.x < p.z) p.xz = p.zx;
			if (p.y < p.z) p.yz = p.zy;
			p.yz *= rmX;
			p *= iFracScale;
			p.xyz += iFracShift;
		}
		
		iterationsLeft -= 8;
	}
	
	for (int i = 0; i < iterationsLeft; i++)
	{
		p.xyz = abs(p.xyz);
		p.xy *= rmZ;
		if (p.x < p.y) p.xy = p.yx;
		if (p.x < p.z) p.xz = p.zx;
		if (p.y < p.z) p.yz = p.zy;
		p.yz *= rmX;
		p *= iFracScale;
		p.xyz += iFracShift;
	}
	
	#endif
	
	return de_box(p, vec3(6.0));
}

vec4 col_fractal(vec4 p) 
{
	float s1 = sin(iFracAng1), c1 = cos(iFracAng1), s2 = sin(iFracAng2), c2 = cos(iFracAng2);
	vec3 orbit = vec3(0.0);
	mat2 rmZ = mat2(c1, s1, -s1, c1); 
	mat2 rmX = mat2(c2, s2, -s2, c2);
	for (int i = 0; i < FRACTAL_ITER; i++)
	{
		p.xyz = abs(p.xyz);
		p.xy *= rmZ; //rotation around z
		if (p.x < p.y) p.xy = p.yx;
		if (p.x < p.z) p.xz = p.zx;
		if (p.y < p.z) p.yz = p.zy;
		p.yz *= rmX; //rotation around x
		p *= iFracScale;
		p.xyz += iFracShift;
		orbit = max(orbit, p.xyz*iFracCol);
	}
	return vec4(orbit, de_box(p, vec3(6.0)));
}

float de_marble(vec4 p) 
{
	return de_sphere(p - vec4(iMarblePos, 0), iMarbleRad);
}

vec4 col_marble(vec4 p) 
{
	vec4 col = vec4(1.0, 1.0, 1.0, de_sphere(p - vec4(iMarblePos, 0), iMarbleRad));
	return col;
}

float de_flag(vec4 p) 
{
	vec3 f_pos = iFlagPos + vec3(1.5, 4, 0)*iFlagScale;
	vec4 p_s = p/iMarbleRad;
	vec4 d_pos = p - vec4(f_pos, 0);
	vec4 caps_pos = p - vec4(iFlagPos + vec3(0, iFlagScale*2.4, 0), 0);
	//animated flag woooo
	float speed = 14;
	float oscillation = sin(8*p_s.x - 1*p_s.y - speed*time) + 0.4*sin(11*p_s.x + 2*p_s.y - 1.2*speed*time) + 0.15*sin(20*p_s.x - 5*p_s.y -1.4*speed*time);
	//scale the flag displacement amplitude by the distance from the flagpole
	float d = 0.4*de_box(d_pos + caps_pos.x*vec4(0,(0.02+ caps_pos.x* 0.5+0.01*oscillation),0.04*oscillation,0), vec3(1.5, 0.8, 0.005)*iMarbleRad);
	d = min(d, de_capsule(caps_pos, iMarbleRad*2.4, iMarbleRad*0.05));
	return d;
}

vec4 col_flag(vec4 p) 
{
	vec3 f_pos = iFlagPos + vec3(1.5, 4, 0)*iFlagScale;
	vec4 d_pos = p - vec4(f_pos, 0);
	vec3 fsize = vec3(1.5, 0.8, 0.08)*iMarbleRad;
	vec4 caps_pos = p - vec4(iFlagPos + vec3(0, iFlagScale*2.4, 0), 0);
	float d1 = de_box(d_pos, fsize);
	float d2 = de_capsule(p - vec4(iFlagPos + vec3(0, iFlagScale*2.4, 0), 0), iMarbleRad*2.4, iMarbleRad*0.18);
	if (d1 < d2) {
		vec2 texture_coord = d_pos.xy*vec2(0.5,-0.48)/fsize.xy + vec2(0.5,0.5) - 0.5*vec2(0,caps_pos.x*(0.02+ caps_pos.x* 0.5))/fsize.xy;
		vec3 flagcolor = texture(iTexture0, texture_coord).xyz;
		return vec4(flagcolor, d1);
	} else {
		return vec4(0.9, 0.9, 0.1, d2);
	}
}

float de_scene(vec3 pos) 
{
	vec4 p = vec4(pos,1.f);
	float d = de_fractal(p);
	d = min(d, de_marble(p));
	d = min(d, de_flag(p));
	return d;
}

vec4 col_scene(vec3 pos) 
{
	vec4 p = vec4(pos,1.f);
	vec4 col = col_fractal(p);
	vec4 col_f = col_flag(p);
	if (col_f.w < col.w) { col = col_f; }
	vec4 col_m = col_marble(p);
	if (col_m.w < col.w) {
		return vec4(col_m.xyz, 1.0);
	}
	return vec4(min(col.xyz,1), 0.0);
}