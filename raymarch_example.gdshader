shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 noise_transform = vec3(0.0);
uniform float shape_size = 0.5;
uniform float noise_scale = 1.0;
uniform float density_threshold = 0.5;
uniform float deformation = 0.0;
uniform float anim_speed;

uniform float volumeStepSize = 0.005;
uniform int volumeMaxSteps = 120;


varying vec3 camera;
varying vec3 position; //vertex fragment position

const int MAX_STEPS = 100;
const float MAX_DIST = 100.0;
const float SURF_DIST = 1e-3;


float spaceWarp(vec3 p) {
	
	return pow(2.0 * length(p), deformation) / 2.0;
}

vec3 random3d(vec3 uvw){
	
    uvw = vec3( dot(uvw, vec3(127.1,311.7, 513.5) ),
               dot(uvw, vec3(269.5,183.3,417.8) ),
			   dot(uvw, vec3(734.5, 432.4, 541.3)) );
    return -1.0 + 2.0 * fract(sin(uvw) * 43758.5453123);
}

float noise3D(vec3 uvw){
	uvw = uvw * spaceWarp(uvw) * noise_scale;
	uvw += vec3(noise_transform.x + sin(TIME) * anim_speed,
				noise_transform.y + sin(TIME+0.9) * anim_speed,
				noise_transform.z + sin(TIME+0.3) * anim_speed);
	
	vec3 gridIndex = floor(uvw);
	vec3 gridFract = fract(uvw);
	
	vec3 blur = smoothstep(0.0, 1.0, gridFract);
	
	//Grid points
	vec3 blb = gridIndex + vec3(0.0, 0.0, 0.0);
	vec3 brb = gridIndex + vec3(1.0, 0.0, 0.0);
	vec3 tlb = gridIndex + vec3(0.0, 1.0, 0.0);
	vec3 trb = gridIndex + vec3(1.0, 1.0, 0.0);
	vec3 blf = gridIndex + vec3(0.0, 0.0, 1.0);
	vec3 brf = gridIndex + vec3(1.0, 0.0, 1.0);
	vec3 tlf = gridIndex + vec3(0.0, 1.0, 1.0);
	vec3 trf = gridIndex + vec3(1.0, 1.0, 1.0);
	
	//Generate random gradients at grid points
	vec3 gradBlb = random3d(blb);
	vec3 gradBrb = random3d(brb);
	vec3 gradTlb = random3d(tlb);
	vec3 gradTrb = random3d(trb);
	vec3 gradBlf = random3d(blf);
	vec3 gradBrf = random3d(brf);
	vec3 gradTlf = random3d(tlf);
	vec3 gradTrf = random3d(trf);
	
	vec3 DistFromPixelToBlb = gridFract - vec3(0.0, 0.0, 0.0);
	vec3 DistFromPixelToBrb = gridFract - vec3(1.0, 0.0, 0.0); 
	vec3 DistFromPixelToTlb = gridFract - vec3(0.0, 1.0, 0.0);
	vec3 DistFromPixelToTrb = gridFract - vec3(1.0, 1.0, 0.0);
	vec3 DistFromPixelToBlf = gridFract - vec3(0.0, 0.0, 1.0);
	vec3 DistFromPixelToBrf = gridFract - vec3(1.0, 0.0, 1.0);
	vec3 DistFromPixelToTlf = gridFract - vec3(0.0, 1.0, 1.0);
	vec3 DistFromPixelToTrf = gridFract - vec3(1.0, 1.0, 1.0);
	
	float dotBlb = dot(gradBlb, DistFromPixelToBlb);
	float dotBrb = dot(gradBrb, DistFromPixelToBrb);
	float dotTlb = dot(gradTlb, DistFromPixelToTlb);
	float dotTrb = dot(gradTrb, DistFromPixelToTrb);
	float dotBlf = dot(gradBlf, DistFromPixelToBlf);
	float dotBrf = dot(gradBrf, DistFromPixelToBrf);
	float dotTlf = dot(gradTlf, DistFromPixelToTlf);
	float dotTrf = dot(gradTrf, DistFromPixelToTrf);
	
	//Interpolate left to right, bottom to top 
	return mix( mix( mix(dotBlb, dotBrb, blur.x),
			    	 mix(dotTlb, dotTrb, blur.x), blur.y),
				mix( mix(dotBlf, dotBrf, blur.x),
					 mix(dotTlf, dotTrf, blur.x), blur.y), blur.z) + 0.5; 
}

float SdfSphere(vec3 p){
	float d = length(p) - shape_size; //Sphere
//	float d = max(abs(p.x) - 0.5, max(abs(p.y) - 0.5, abs(p.z) - 0.5)); //Cube
	
//	d = length(vec2(length(p.xz) - .5, p.y)) - .1; //torus
	
	return d;
}

float RayMarch(vec3 ro, vec3 rd) {
	float dO = 0.0; //Distance already travelled by ray
	float dS;
	
	for (int i = 0; i < MAX_STEPS; i++) {
		vec3 p = ro + dO * rd;
	
		//noise sample
		float noise = noise3D(p);
		
		//Distance check for SDF Shape
		dS = SdfSphere(p);
		dO += dS;
	
		if (dS < SURF_DIST || dO > MAX_DIST){
			break; //Break free from raymarch loop if sphere surface is detected
		}
	}
	return dO;
}

vec3 GetNormal(vec3 p) {
	
	vec2 e = vec2(1e-2, 0);
	
	vec3 n = noise3D(p) - vec3(
		noise3D(p - e.xyy),
		noise3D(p - e.yxy),
		noise3D(p - e.yyx)
	);
	
	return normalize(n);
}

void vertex() {
	position = VERTEX; //
	camera = (inverse(MODELVIEW_MATRIX) * vec4(0, 0, 0, 1)).xyz;
	COLOR.rgb = VERTEX + 0.5;
}

void fragment() {
	vec3 uvw = COLOR.rgb;
	
	vec3 ro = camera; //CAMERA POSITION in OBJECT SPACE
	vec3 rd =  normalize(position - ro);
	
	vec3 n;
	vec3 col;
	
	
	float d = RayMarch(ro, rd);
	
	
	if (d >= MAX_DIST){
		discard;
	}
	
	vec3 p = ro + rd * d; //Surface point
	
	float noise = noise3D(p);
	if (noise > density_threshold) {
		n = normalize(p);
		col = n;
	}
	else {
		
		//Else density is less than threshold, march forward 1 step
		p += rd * volumeStepSize;
		for (int i = 0; i < volumeMaxSteps; i++) {
			//sample noise
			
			float noise = noise3D(p);
			
			if (noise <= density_threshold){
				p += rd * volumeStepSize;
			
				// Somehow discard the rays that never hit
				if (length(p) >= shape_size) {
					discard;
				}
		
			}
			else {
	//			col = vec3(1.0);
				//calculate normal
				n = GetNormal(p);
				col = vec3(n);
			}
		}
	}

	ALBEDO = col;

}
