shader_type spatial;
render_mode unshaded, cull_disabled;

const float MAX_DIST = 100.0;
const int MAX_STEPS = 100;
const float SURF_DIST = 1e-3; //0.001

varying vec3 camera; //Local Camera position
varying vec3 position; //Vertex Position

uniform float shape_size = 0.5;

uniform float noise_scale = 1.0;
uniform vec3 noise_transform;
uniform float density_threshold = 0.5;
uniform float deformation = 0.0;
uniform float anim_speed = 0.0;

uniform float volumeStepSize = 0.005;
uniform int volumeMaxSteps = 200;

float spaceWarp(vec3 p) {
	return pow(2.0 * length(p), deformation)/ 2.0;
}

vec3 random3D(vec3 uvw){
	
    uvw = vec3( dot(uvw, vec3(127.1,311.7, 513.7) ),
               dot(uvw, vec3(269.5,183.3, 396.5) ),
			   dot(uvw, vec3(421.3,314.1, 119.7) ) );
			
    return -1.0 + 2.0 * fract(sin(uvw) * 43758.5453123);
}

float noise3D(vec3 uvw){
	uvw *= spaceWarp(uvw) * noise_scale;
	uvw += vec3(noise_transform.x + sin(TIME * anim_speed),
				noise_transform.y + sin(TIME * anim_speed + 0.5),
				noise_transform.z + sin(TIME * anim_speed + 1.5));
	
	vec3 gridIndex = floor(uvw); 
	vec3 gridFract = fract(uvw);
	
	vec3 blur = smoothstep(0.0, 1.0, gridFract);
	
	vec3 blb = gridIndex + vec3(0.0, 0.0, 0.0);
	vec3 brb = gridIndex + vec3(1.0, 0.0, 0.0);
	vec3 tlb = gridIndex + vec3(0.0, 1.0, 0.0);
	vec3 trb = gridIndex + vec3(1.0, 1.0, 0.0);
	vec3 blf = gridIndex + vec3(0.0, 0.0, 1.0);
	vec3 brf = gridIndex + vec3(1.0, 0.0, 1.0);
	vec3 tlf = gridIndex + vec3(0.0, 1.0, 1.0);
	vec3 trf = gridIndex + vec3(1.0, 1.0, 1.0);
	
	vec3 gradBLB = random3D(blb); 
	vec3 gradBRB = random3D(brb);
	vec3 gradTLB = random3D(tlb);
	vec3 gradTRB = random3D(trb);
	vec3 gradBLF = random3D(blf);
	vec3 gradBRF = random3D(brf);
	vec3 gradTLF = random3D(tlf);
	vec3 gradTRF = random3D(trf);
	
	
	vec3 distToPixelFromBLB = gridFract - vec3(0.0, 0.0, 0.0);
	vec3 distToPixelFromBRB = gridFract - vec3(1.0, 0.0, 0.0);
	vec3 distToPixelFromTLB = gridFract - vec3(0.0, 1.0, 0.0);
	vec3 distToPixelFromTRB = gridFract - vec3(1.0, 1.0, 0.0);
	vec3 distToPixelFromBLF = gridFract - vec3(0.0, 0.0, 1.0);
	vec3 distToPixelFromBRF = gridFract - vec3(1.0, 0.0, 1.0);
	vec3 distToPixelFromTLF = gridFract - vec3(0.0, 1.0, 1.0);
	vec3 distToPixelFromTRF = gridFract - vec3(1.0, 1.0, 1.0);
	
	float dotBLB = dot(gradBLB, distToPixelFromBLB);
	float dotBRB = dot(gradBRB, distToPixelFromBRB);
	float dotTLB = dot(gradTLB, distToPixelFromTLB);
	float dotTRB = dot(gradTRB, distToPixelFromTRB);
	float dotBLF = dot(gradBLF, distToPixelFromBLF);
	float dotBRF = dot(gradBRF, distToPixelFromBRF);
	float dotTLF = dot(gradTLF, distToPixelFromTLF);
	float dotTRF = dot(gradTRF, distToPixelFromTRF);
	
	
	return mix(
		mix(
			mix(dotBLB, dotBRB, blur.x),
			mix(dotTLB, dotTRB, blur.x), blur.y
		),
		mix(
			mix(dotBLF, dotBRF, blur.x),
			mix(dotTLF, dotTRF, blur.x), blur.y
		), blur.z
	) + 0.5;
}

float SdfSphere(vec3 p){
	return length(p) - shape_size;
}

vec3 GetNormal(vec3 p){
	
	vec2 e = vec2(1e-2, 0);
	
	vec3 n = noise3D(p) - vec3(
		noise3D(p - e.xyy),
		noise3D(p - e.yxy),
		noise3D(p - e.yyx)
	);
	return normalize(n);
}

float RayMarch(vec3 ro, vec3 rd){
	
	float dO = 0.0; //Distance ray has already travelled
	float dS;
	
	for (int i = 0; i < MAX_STEPS; i++){
		vec3 p = ro + dO * rd;
		
		dS = SdfSphere(p);
		dO += dS;
		
		if (dS < SURF_DIST || dO > MAX_DIST) {
			break;
		}
	}
	return dO;
}

void vertex() {
	position = VERTEX;
	camera = (inverse(MODELVIEW_MATRIX) * vec4(0,0,0,1)).xyz; //Camera Position in Local Space
}

void fragment() {
	vec3 ro = camera;
	vec3 rd = normalize(position - ro);
	
	vec3 n;
	vec3 col;
	
	float d = RayMarch(ro, rd);
	
	if (d >= MAX_DIST) {
		discard;
	}
	
	vec3 p = ro + rd * d; //Surface Point on shpere
	
	float noise = noise3D(p);
	
	if (noise > density_threshold){
		n = normalize(p);
		col = vec3(n);
	}
	
	else {
		//March a step forward and sample noise texture
		p += rd * volumeStepSize;
		
		for (int i = 0; i < volumeMaxSteps; i++) {
			float noise = noise3D(p);
			if (noise <= density_threshold) {
				p += rd * volumeStepSize;
				
				if (length(p) > shape_size) {
					discard;
				}
			}
			else {
				n = GetNormal(p);
				col = vec3(n);
			}
			
		}
	
	}
	
	
	ALBEDO = n;
}
