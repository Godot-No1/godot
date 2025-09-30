#[compute]

#version 450

#VERSION_DEFINES

#define BLOCK_SIZE 8

layout(local_size_x = BLOCK_SIZE, local_size_y = BLOCK_SIZE, local_size_z = 1) in;

shared float tmp_data[BLOCK_SIZE * BLOCK_SIZE];

#ifdef READ_TEXTURE

//use for main texture
layout(set = 0, binding = 0) uniform sampler2D source_texture;

#else

//use for intermediate textures
layout(r32f, set = 0, binding = 0) uniform restrict readonly image2D source_luminance;

#endif

layout(rgba32f, set = 1, binding = 0) uniform restrict writeonly image2D dest_luminance;

#ifdef WRITE_LUMINANCE
layout(set = 2, binding = 0) uniform sampler2D prev_luminance;
#endif

layout(push_constant, std430) uniform Params {
	ivec2 source_size;
	float max_luminance;
	float min_luminance;
	float exposure_adjust;
	float pad[3];
}
params;

float ease_in_out_cubic(float x) {
	if (x < 0.5) {
		return 4.0 * pow(x, 3);
	} else {
		return 1.0 - pow(fma(-2.0, x, 2.0), 3) / 2.0;
	}
}

float curve(float current_exposure, float target, float progress, float next_progress) {
	float p_x = progress;
	float p_y = current_exposure;
	float end_y = target;
	float q_x = next_progress;

	float spx = ease_in_out_cubic(p_x);
	// 2. 根據公式求解 start_y
	// start_y = (p_y - end_y * spx) / (1 - spx);
	float start_y = (p_y - end_y * spx) / (1.0 - spx);

	// 3. 計算 S(q_x)
	float sqx = ease_in_out_cubic(q_x);

	// 4. 計算最終的 q_y
	// q_y = start_y + (end_y - start_y) * sqx;
	float q_y = fma(end_y - start_y, sqx, start_y);

	return q_y;
}

void main() {
	uint t = gl_LocalInvocationID.y * BLOCK_SIZE + gl_LocalInvocationID.x;
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);

	if (any(lessThan(pos, params.source_size))) {
#ifdef READ_TEXTURE
		vec3 v = texelFetch(source_texture, pos, 0).rgb;
		tmp_data[t] = max(v.r, max(v.g, v.b));
#else
		tmp_data[t] = imageLoad(source_luminance, pos).r;
#endif
	} else {
		tmp_data[t] = 0.0;
	}

	groupMemoryBarrier();
	barrier();

	uint size = (BLOCK_SIZE * BLOCK_SIZE) >> 1;

	do {
		if (t < size) {
			tmp_data[t] += tmp_data[t + size];
		}
		groupMemoryBarrier();
		barrier();

		size >>= 1;
	} while (size >= 1);

	if (t == 0) {
		//compute rect size
		ivec2 rect_size = min(params.source_size - pos, ivec2(BLOCK_SIZE));
		float avg = tmp_data[0] / float(rect_size.x * rect_size.y);
		//float avg = tmp_data[0] / float(BLOCK_SIZE*BLOCK_SIZE);
		pos /= ivec2(BLOCK_SIZE);
		float target = 0.0;
		float progress = 0.0;
#ifdef WRITE_LUMINANCE
		vec3 texture = texelFetch(prev_luminance, ivec2(0, 0), 0).rgb;
		float prev_lum = texture.r; //1 pixel previous exposure
		target  = texture.g;
		progress = texture.b;
		// avg = clamp(prev_lum + (avg - prev_lum) * params.exposure_adjust, params.min_luminance, params.max_luminance);
		if (progress >= 1.0 || abs(avg - target) > 0.02) { // TODO: get the "0.1" from UI
			target = avg;
			progress = 0.0;
		}
		float next_progress = min(progress + params.exposure_adjust, 1.0);
		avg = clamp(
			curve(prev_lum, avg, progress, next_progress),
			params.min_luminance,
			params.max_luminance
		);
		progress = next_progress;
#endif
		imageStore(dest_luminance, pos, vec4(avg, target, progress, 0.0));
	}
}
